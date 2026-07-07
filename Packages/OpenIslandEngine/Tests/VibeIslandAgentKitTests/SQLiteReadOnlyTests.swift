import Foundation
import SQLite3
import Testing
@testable import OpenIslandCore

/// Builds a throwaway SQLite database at a unique temp path, seeds it with
/// `setupSQL`, and returns the path. The caller reads it back through the
/// read-only helper under test.
private func makeFixtureDatabase(_ setupSQL: String) -> String {
    let path = NSTemporaryDirectory() + "sqlite-readonly-\(UUID().uuidString).db"
    var db: OpaquePointer?
    #expect(sqlite3_open(path, &db) == SQLITE_OK)
    #expect(sqlite3_exec(db, setupSQL, nil, nil, nil) == SQLITE_OK)
    sqlite3_close(db)
    return path
}

@Test("read returns nil for a missing database")
func sqliteReadMissingFile() {
    let result = SQLiteReadOnly.read(atPath: "/no/such/database.db") { _ in true }
    #expect(result == nil)
}

@Test("query iterates rows and reads typed columns")
func sqliteQueryReadsColumns() {
    let path = makeFixtureDatabase(
        """
        CREATE TABLE t (name TEXT, count INTEGER, cost REAL, note TEXT);
        INSERT INTO t VALUES ('a', 10, 1.5, NULL);
        INSERT INTO t VALUES ('b', 20, 2.5, 'hi');
        """
    )
    defer { try? FileManager.default.removeItem(atPath: path) }

    var names: [String] = []
    var counts: [Int] = []
    var totalCost = 0.0
    var noteWasNull = false

    let ran = SQLiteReadOnly.read(atPath: path) { db in
        db.query("SELECT name, count, cost, note FROM t ORDER BY count ASC;") { row in
            names.append(row.text(0) ?? "")
            counts.append(row.int(1))
            totalCost += row.double(2)
            if row.text(3) == nil { noteWasNull = true }
            return true
        }
        return true
    }

    #expect(ran == true)
    #expect(names == ["a", "b"])
    #expect(counts == [10, 20])
    #expect(totalCost == 4.0)
    #expect(noteWasNull == true)
}

@Test("query returning false stops iteration early")
func sqliteQueryEarlyStop() {
    let path = makeFixtureDatabase(
        """
        CREATE TABLE t (n INTEGER);
        INSERT INTO t VALUES (1), (2), (3), (4);
        """
    )
    defer { try? FileManager.default.removeItem(atPath: path) }

    var seen: [Int] = []
    SQLiteReadOnly.read(atPath: path) { db in
        db.query("SELECT n FROM t ORDER BY n ASC;") { row in
            seen.append(row.int(0))
            return row.int(0) < 2 // stop after reading 2
        }
    }

    #expect(seen == [1, 2])
}

@Test("positional text bindings filter rows")
func sqliteQueryBindings() {
    let path = makeFixtureDatabase(
        """
        CREATE TABLE t (id TEXT, v INTEGER);
        INSERT INTO t VALUES ('keep', 7), ('drop', 9);
        """
    )
    defer { try? FileManager.default.removeItem(atPath: path) }

    var value = 0
    SQLiteReadOnly.read(atPath: path) { db in
        db.query("SELECT v FROM t WHERE id = ?;", bind: ["keep"]) { row in
            value = row.int(0)
            return true
        }
    }

    #expect(value == 7)
}

@Test("tableExists reflects the schema")
func sqliteTableExists() {
    let path = makeFixtureDatabase("CREATE TABLE present (x INTEGER);")
    defer { try? FileManager.default.removeItem(atPath: path) }

    let result = SQLiteReadOnly.read(atPath: path) { db in
        (db.tableExists("present"), db.tableExists("absent"))
    }

    #expect(result?.0 == true)
    #expect(result?.1 == false)
}

@Test("blob columns round-trip through Data")
func sqliteBlobColumn() {
    let path = makeFixtureDatabase(
        """
        CREATE TABLE b (data BLOB);
        INSERT INTO b VALUES (x'00ff10');
        """
    )
    defer { try? FileManager.default.removeItem(atPath: path) }

    var bytes: [UInt8] = []
    SQLiteReadOnly.read(atPath: path) { db in
        db.query("SELECT data FROM b;") { row in
            if let data = row.blob(0) { bytes = Array(data) }
            return true
        }
    }

    #expect(bytes == [0x00, 0xff, 0x10])
}
