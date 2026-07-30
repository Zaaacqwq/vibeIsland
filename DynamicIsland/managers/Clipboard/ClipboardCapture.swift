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

import AppKit
import Foundation

/// Turns a pasteboard snapshot into a ``ClipboardItem``.
///
/// Kept free of `NSPasteboard` and of any global state so the capture rules —
/// which types are refused, how multi-file copies collapse, what counts as an
/// image — are unit-testable from plain dictionaries.
enum ClipboardCapture {
    struct Source {
        let bundleID: String?
        let name: String?

        static let unknown = Source(bundleID: nil, name: nil)
    }

    struct Result {
        let item: ClipboardItem
        /// Payload bytes keyed by pasteboard type, for the store to write.
        let values: [String: Data]
    }

    /// Longest preview kept in the index. Matches Maccy's trade-off: enough to
    /// search meaningfully, short enough that the index stays small.
    static let maxTitleLength = 1_000

    /// - Parameter representations: one type→bytes dictionary per pasteboard
    ///   item. Multi-file copies arrive as several items, everything else as one.
    /// - Returns: `nil` when the snapshot must not be recorded (opted out,
    ///   nothing usable, or over the size limit).
    static func makeItem(
        representations: [[String: Data]],
        enabledTypes: Set<String>,
        source: Source = .unknown,
        maxItemBytes: Int,
        now: Date = .now
    ) -> Result? {
        guard !representations.isEmpty else { return nil }

        let allTypes = Set(representations.flatMap(\.keys))

        // Explicit opt-outs (passwords, transient hand-offs) and our own
        // write-back echo are never recorded.
        guard allTypes.isDisjoint(with: ClipboardPasteboard.ignoredTypes) else { return nil }
        guard !allTypes.contains(ClipboardPasteboard.clipboardManagerMarker.rawValue) else { return nil }

        let fileURLType = NSPasteboard.PasteboardType.fileURL.rawValue
        var values: [String: Data] = [:]
        var fileNames: [String] = []

        // A multi-file copy spreads one `fileURL` per pasteboard item; collapse
        // them into a single newline-separated payload so the entry stays one
        // row and can be written back with `writeObjects`.
        if enabledTypes.contains(fileURLType) {
            let urlStrings = representations.compactMap { representation -> String? in
                guard let data = representation[fileURLType] else { return nil }
                return String(data: data, encoding: .utf8)
            }
            if !urlStrings.isEmpty {
                values[fileURLType] = Data(urlStrings.joined(separator: "\n").utf8)
                fileNames = urlStrings.map { URL(string: $0)?.lastPathComponent ?? $0 }
            }
        }

        for type in allTypes where type != fileURLType {
            guard enabledTypes.contains(type) else { continue }
            guard let data = representations.compactMap({ $0[type] }).first, !data.isEmpty else { continue }
            values[type] = data
        }

        guard !values.isEmpty else { return nil }

        let totalBytes = values.values.reduce(0) { $0 + $1.count }
        guard totalBytes <= maxItemBytes else { return nil }

        let text = values[NSPasteboard.PasteboardType.string.rawValue]
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let kind = kind(hasFiles: !fileNames.isEmpty, types: Set(values.keys), text: text)

        let title: String
        switch kind {
        case .file:
            title = fileNames.joined(separator: ", ")
        case .image:
            title = text.isEmpty ? "" : previewTitle(for: text)
        case .text:
            title = previewTitle(for: text)
        }

        // Text with nothing but whitespace is noise — Finder and some editors
        // emit it on internal operations.
        if kind == .text && title.isEmpty { return nil }

        let payloads = values.map { ClipboardPayload(type: $0.key, value: $0.value) }
            .sorted { $0.type < $1.type }

        let item = ClipboardItem(
            kind: kind,
            title: title,
            payloads: payloads,
            firstCopiedAt: now,
            lastCopiedAt: now,
            sourceAppBundleID: source.bundleID,
            sourceAppName: source.name,
            fileNames: fileNames
        )

        return Result(item: item, values: values)
    }

    static func kind(hasFiles: Bool, types: Set<String>, text: String) -> ClipboardItemKind {
        if hasFiles { return .file }

        let imageTypes: Set<String> = [
            NSPasteboard.PasteboardType.png.rawValue,
            NSPasteboard.PasteboardType.tiff.rawValue
        ]
        // A rich-text copy from a browser can carry a TIFF rendition alongside
        // its text; only call it an image when there is no text to show.
        if !types.isDisjoint(with: imageTypes), text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .image
        }
        return .text
    }

    static func previewTitle(for text: String) -> String {
        let collapsed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > maxTitleLength else { return collapsed }
        return String(collapsed.prefix(maxTitleLength))
    }
}
