import Foundation
import SQLite3

/// Minimal read-only SQLite access shared by the token-usage aggregators that
/// read agent databases (OpenCode's `opencode.db`, Antigravity's per-conversation
/// databases, Copilot Desktop's `data.db`).
///
/// Every failure degrades to `nil` — a locked, missing, or malformed database
/// never throws into the aggregate. Databases are opened `READONLY | NOMUTEX`.
/// A plain read-only open returns the latest committed data when the `-wal` /
/// `-shm` sidecars are readable (the common case for a live agent). If that
/// fails, the opener retries via the `immutable=1` URI, which reads the main
/// database file directly and tolerates a slightly stale but self-consistent
/// snapshot rather than failing outright.
///
/// Not `Sendable`: `Connection` / `Row` wrap raw `sqlite3` pointers scoped to a
/// single `read(atPath:)` call. The aggregators run serially on one background
/// thread, so a connection never crosses an isolation boundary.
public enum SQLiteReadOnly {
    /// A single result row. Column indices are zero-based and match the order
    /// of the `SELECT` list. Accessors return SQLite's type-coerced value and
    /// treat `NULL` as absent (`0` / `nil`).
    public struct Row {
        fileprivate let stmt: OpaquePointer

        public func int64(_ index: Int32) -> Int64 {
            sqlite3_column_int64(stmt, index)
        }

        public func int(_ index: Int32) -> Int {
            Int(sqlite3_column_int64(stmt, index))
        }

        public func double(_ index: Int32) -> Double {
            sqlite3_column_double(stmt, index)
        }

        public func text(_ index: Int32) -> String? {
            guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
                  let cString = sqlite3_column_text(stmt, index) else { return nil }
            return String(cString: cString)
        }

        public func blob(_ index: Int32) -> Data? {
            guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
                  let bytes = sqlite3_column_blob(stmt, index) else { return nil }
            let count = Int(sqlite3_column_bytes(stmt, index))
            guard count > 0 else { return Data() }
            return Data(bytes: bytes, count: count)
        }

        public func isNull(_ index: Int32) -> Bool {
            sqlite3_column_type(stmt, index) == SQLITE_NULL
        }
    }

    /// An open read-only handle. Valid only inside the `read(atPath:)` closure.
    public struct Connection {
        fileprivate let db: OpaquePointer

        /// Prepares `sql`, binds `params` as positional text parameters (`?`),
        /// and invokes `row` for each result row. Return `false` from `row` to
        /// stop iterating early. Any prepare/step failure returns `false`
        /// without surfacing an error.
        @discardableResult
        public func query(
            _ sql: String,
            bind params: [String] = [],
            row: (Row) -> Bool
        ) -> Bool {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let stmt else { return false }
            defer { sqlite3_finalize(stmt) }

            // Hold copies of the bound strings alive until finalize; a nil
            // destructor means SQLite does not copy them itself.
            var heldCStrings: [UnsafeMutablePointer<CChar>?] = []
            defer { heldCStrings.forEach { free($0) } }
            for (offset, param) in params.enumerated() {
                let cString = param.withCString { strdup($0) }
                heldCStrings.append(cString)
                sqlite3_bind_text(stmt, Int32(offset + 1), cString, -1, nil)
            }

            while sqlite3_step(stmt) == SQLITE_ROW {
                if !row(Row(stmt: stmt)) { break }
            }
            return true
        }

        /// Whether a table with `name` exists — lets callers skip a query when
        /// the schema is a version that predates a column/table they need.
        public func tableExists(_ name: String) -> Bool {
            var exists = false
            query(
                "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;",
                bind: [name]
            ) { _ in
                exists = true
                return false
            }
            return exists
        }
    }

    /// Opens the database at `path` read-only, runs `body` with the connection,
    /// and closes it. Returns `nil` (without invoking `body`) when the file is
    /// missing or cannot be opened by either strategy.
    public static func read<T>(atPath path: String, _ body: (Connection) -> T) -> T? {
        guard FileManager.default.fileExists(atPath: path),
              let db = open(path: path) else { return nil }
        defer { sqlite3_close(db) }
        return body(Connection(db: db))
    }

    private static func open(path: String) -> OpaquePointer? {
        let flags: Int32 = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX

        var db: OpaquePointer?
        if sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let opened = db {
            sqlite3_busy_timeout(opened, 100) // ms
            return opened
        }
        if db != nil { sqlite3_close(db); db = nil }

        // Fallback for WAL-locked databases whose sidecars we cannot use:
        // read the main file as immutable, accepting a possibly stale snapshot.
        let uri = "file:\(uriEncoded(path))?immutable=1"
        if sqlite3_open_v2(uri, &db, flags | SQLITE_OPEN_URI, nil) == SQLITE_OK, let opened = db {
            sqlite3_busy_timeout(opened, 100) // ms
            return opened
        }
        if db != nil { sqlite3_close(db) }
        return nil
    }

    /// Percent-encodes a filesystem path for use in a `file:` URI, preserving
    /// path separators while escaping spaces and other reserved characters.
    private static func uriEncoded(_ path: String) -> String {
        path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    }
}
