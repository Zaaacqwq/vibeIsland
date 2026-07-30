/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
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
import os.log

/// On-disk home of the clipboard history: a JSON index plus a `blobs/`
/// directory for payloads too large to inline.
///
/// An actor rather than a class with a queue, so the index and the blob
/// directory can never be mutated from two places at once — the monitor writes
/// on every copy while the UI reads image payloads to draw thumbnails.
///
/// Deliberately *not* SwiftData/Core Data: nothing else in the app uses a
/// persistence stack, and the shape here (append, de-duplicate, evict oldest)
/// is what `ShelfPersistenceService` already does with a plain JSON file.
actor ClipboardStore {
    static let shared = ClipboardStore()

    private let directory: URL
    private let indexURL: URL
    private let blobsDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let log = os.Logger(subsystem: "com.zaaacqwq.VibeIsland", category: "ClipboardStore")

    init(directory: URL? = nil) {
        let fm = FileManager.default
        let resolved: URL
        if let directory {
            resolved = directory
        } else {
            let support = try? fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            resolved = (support ?? fm.temporaryDirectory)
                .appendingPathComponent("DynamicIsland", isDirectory: true)
                .appendingPathComponent("Clipboard", isDirectory: true)
        }

        self.directory = resolved
        self.indexURL = resolved.appendingPathComponent("index.json")
        self.blobsDirectory = resolved.appendingPathComponent("blobs", isDirectory: true)

        try? fm.createDirectory(at: resolved, withIntermediateDirectories: true)
        try? fm.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)

        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Index

    func load() -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        do {
            return try decoder.decode([ClipboardItem].self, from: data)
        } catch {
            // A corrupt index must not wedge the feature on every launch;
            // start over rather than throwing on the way to the UI.
            log.error("Discarding unreadable clipboard index: \(error.localizedDescription)")
            return []
        }
    }

    /// Writes the index and removes any blob no longer referenced by it, which
    /// covers deletions, evictions, and blobs orphaned by a crash mid-write.
    func persist(_ items: [ClipboardItem]) {
        do {
            let data = try encoder.encode(items)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            log.error("Failed to save clipboard index: \(error.localizedDescription)")
        }
        pruneOrphanBlobs(keeping: items)
    }

    // MARK: - Blobs

    /// Persists the blob-backed payloads of `item`, dropping any payload whose
    /// bytes could not be written so the index never references a missing file.
    func writeBlobs(for item: ClipboardItem, values: [String: Data]) -> ClipboardItem {
        var stored = item
        stored.payloads = item.payloads.compactMap { payload -> ClipboardPayload? in
            guard let fileName = payload.blobFileName else { return payload }
            guard let data = values[payload.type] else { return nil }
            do {
                try data.write(to: blobsDirectory.appendingPathComponent(fileName), options: .atomic)
                return payload
            } catch {
                log.error("Failed to write clipboard blob: \(error.localizedDescription)")
                return nil
            }
        }
        return stored
    }

    func data(for payload: ClipboardPayload) -> Data? {
        if let inlineValue = payload.inlineValue { return inlineValue }
        guard let fileName = payload.blobFileName else { return nil }
        return try? Data(contentsOf: blobsDirectory.appendingPathComponent(fileName))
    }

    /// Every payload of `item`, keyed by pasteboard type, ready to be written
    /// back to `NSPasteboard`.
    func values(for item: ClipboardItem) -> [(type: String, data: Data)] {
        item.payloads.compactMap { payload in
            guard let data = data(for: payload) else { return nil }
            return (payload.type, data)
        }
    }

    func totalBlobBytes() -> Int {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: blobsDirectory.path) else {
            return 0
        }
        return names.reduce(0) { total, name in
            let path = blobsDirectory.appendingPathComponent(name).path
            let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int ?? 0
            return total + size
        }
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: indexURL)
        try? FileManager.default.removeItem(at: blobsDirectory)
        try? FileManager.default.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)
    }

    private func pruneOrphanBlobs(keeping items: [ClipboardItem]) {
        let referenced = Set(items.flatMap { $0.payloads.compactMap(\.blobFileName) })
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: blobsDirectory.path) else {
            return
        }
        for name in names where !referenced.contains(name) {
            try? FileManager.default.removeItem(at: blobsDirectory.appendingPathComponent(name))
        }
    }
}
