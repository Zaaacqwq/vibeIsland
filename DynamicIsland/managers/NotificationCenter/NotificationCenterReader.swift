/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import SQLite3

/// Reads the macOS Notification Center SQLite database.
///
/// The live database is owned and WAL-journalled by `usernoted`, and the
/// containing group container is protected by TCC (requires Full Disk Access).
/// To read a consistent, up-to-date snapshot without contending for locks we
/// copy the `db` + `-wal` + `-shm` files to a private temp directory and open
/// the copy. The DB is small (hundreds of KB), so the copy is cheap.
///
/// Field mapping verified on macOS 26.4 (Tahoe):
/// ```
/// record.data (binary plist) →
///   "app"      → bundle id
///   "date"     → CFAbsoluteTime
///   "req.titl" → title    "req.subt" → subtitle    "req.body" → body
/// app.identifier → bundle id (fallback when "app" missing in the blob)
/// ```
struct NotificationCenterReader {
    enum ReadError: Error {
        case databaseNotFound
        case accessDenied
        case openFailed(String)
    }

    /// Candidate database locations, newest macOS layout first.
    static let databaseURL: URL? = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            "Library/Group Containers/group.com.apple.usernoted/db2/db",     // macOS 26+
            "Library/Group Containers/group.com.apple.usernoteddb/db2/db",   // macOS 15 and earlier
        ]
        return candidates
            .map { home.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }()

    /// Whether the database file exists *and* is readable by this process.
    /// A `false` result almost always means Full Disk Access has not been granted.
    static var hasAccess: Bool {
        guard let url = databaseURL else { return false }
        return FileManager.default.isReadableFile(atPath: url.path)
    }

    /// The highest `rec_id` currently in the database, used to establish a
    /// baseline so historical notifications are not replayed as popups.
    func latestRecordID() throws -> Int64 {
        try withDatabaseCopy { db in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT IFNULL(MAX(rec_id), 0) FROM record;", -1, &stmt, nil) == SQLITE_OK else {
                throw ReadError.openFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }
            return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : 0
        }
    }

    /// Fetch records with `rec_id > sinceRecordID`, oldest first.
    func fetchRecords(sinceRecordID: Int64, limit: Int = 60) throws -> [IslandNotification] {
        try withDatabaseCopy { db in
            let sql = """
            SELECT r.rec_id, a.identifier, r.delivered_date, r.data
            FROM record r JOIN app a USING(app_id)
            WHERE r.rec_id > ?
            ORDER BY r.rec_id ASC
            LIMIT ?;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw ReadError.openFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, sinceRecordID)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            var results: [IslandNotification] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let recordID = sqlite3_column_int64(stmt, 0)
                let appBundle = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                let deliveredDate = sqlite3_column_double(stmt, 2)

                guard let blobPointer = sqlite3_column_blob(stmt, 3) else { continue }
                let blobLength = Int(sqlite3_column_bytes(stmt, 3))
                let blob = Data(bytes: blobPointer, count: blobLength)
                let parsed = Self.parse(blob)

                let date = deliveredDate > 0
                    ? Date(timeIntervalSinceReferenceDate: deliveredDate)
                    : (parsed.date ?? Date())

                let bundleID = parsed.bundleID ?? appBundle
                guard !bundleID.isEmpty else { continue }

                // Skip fully empty notifications (e.g. badge-only updates).
                let title = parsed.title ?? ""
                let body = parsed.body ?? ""
                let subtitle = parsed.subtitle ?? ""
                if title.isEmpty, body.isEmpty, subtitle.isEmpty { continue }

                results.append(
                    IslandNotification(
                        recordID: recordID,
                        bundleID: bundleID,
                        title: title,
                        subtitle: subtitle,
                        body: body,
                        date: date
                    )
                )
            }
            return results
        }
    }

    // MARK: - Database copy + open

    private func withDatabaseCopy<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        guard let sourceURL = Self.databaseURL else { throw ReadError.databaseNotFound }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibeisland-notif-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let copyURL = tempDir.appendingPathComponent("db")
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: sourceURL.path + suffix)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            do {
                try FileManager.default.copyItem(at: src, to: URL(fileURLWithPath: copyURL.path + suffix))
            } catch {
                // Permission failure on the primary db file → no Full Disk Access.
                if suffix.isEmpty { throw ReadError.accessDenied }
            }
        }

        var db: OpaquePointer?
        // Open the copy read-write so SQLite may replay the copied WAL.
        guard sqlite3_open_v2(copyURL.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(db)
            throw ReadError.openFailed(message)
        }
        defer { sqlite3_close(db) }
        return try body(db)
    }

    // MARK: - Binary plist parsing

    private static func parse(_ data: Data) -> (bundleID: String?, date: Date?, title: String?, subtitle: String?, body: String?) {
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let root = plist as? [String: Any]
        else {
            return (nil, nil, nil, nil, nil)
        }

        let bundleID = root["app"] as? String
        let date = (root["date"] as? Double).map { Date(timeIntervalSinceReferenceDate: $0) }
        let request = root["req"] as? [String: Any]

        return (
            bundleID,
            date,
            (request?["titl"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            (request?["subt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            (request?["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
