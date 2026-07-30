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
import CryptoKit
import Defaults
import Foundation

/// How the clipboard list orders entries.
enum ClipboardSortMode: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case lastCopied
    case firstCopied
    case numberOfCopies

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lastCopied: return String(localized: "Last copied")
        case .firstCopied: return String(localized: "First copied")
        case .numberOfCopies: return String(localized: "Most copied")
        }
    }
}

/// The broad content class of an entry, which drives how a row renders.
enum ClipboardItemKind: String, Codable, Hashable {
    case text
    case image
    case file
}

/// One pasteboard representation of an entry.
///
/// Small values are inlined in the JSON index; anything larger lives in a blob
/// file so the index stays cheap to read at launch. `digest` is always present
/// so de-duplication never has to load a blob off disk to compare two entries.
struct ClipboardPayload: Codable, Hashable {
    /// Raw `NSPasteboard.PasteboardType` value.
    let type: String
    let digest: String
    let byteCount: Int
    var inlineValue: Data?
    var blobFileName: String?

    /// Values at or below this size stay in the index instead of becoming a
    /// separate file — most text clips land here.
    static let inlineByteLimit = 16 * 1024

    init(type: String, value: Data) {
        self.type = type
        self.digest = Self.digest(of: value)
        self.byteCount = value.count
        if value.count <= Self.inlineByteLimit {
            self.inlineValue = value
            self.blobFileName = nil
        } else {
            self.inlineValue = nil
            self.blobFileName = "\(UUID().uuidString).\(ClipboardPasteboard.blobExtension(for: type))"
        }
    }

    static func digest(of value: Data) -> String {
        SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
    }

    /// True when this payload's bytes live in a blob file rather than inline.
    var isBlobBacked: Bool { blobFileName != nil }
}

/// One entry in the clipboard history.
struct ClipboardItem: Codable, Identifiable, Hashable {
    let id: UUID
    var kind: ClipboardItemKind
    /// Preview text already shortened for display; empty for image-only entries.
    var title: String
    var payloads: [ClipboardPayload]
    var firstCopiedAt: Date
    var lastCopiedAt: Date
    var numberOfCopies: Int
    var isPinned: Bool
    var sourceAppBundleID: String?
    var sourceAppName: String?
    /// Display names of the copied files, for `.file` entries.
    var fileNames: [String]

    init(
        id: UUID = UUID(),
        kind: ClipboardItemKind,
        title: String,
        payloads: [ClipboardPayload],
        firstCopiedAt: Date = .now,
        lastCopiedAt: Date = .now,
        numberOfCopies: Int = 1,
        isPinned: Bool = false,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil,
        fileNames: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.payloads = payloads
        self.firstCopiedAt = firstCopiedAt
        self.lastCopiedAt = lastCopiedAt
        self.numberOfCopies = numberOfCopies
        self.isPinned = isPinned
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.fileNames = fileNames
    }

    var totalByteCount: Int {
        payloads.reduce(0) { $0 + $1.byteCount }
    }

    /// The (type, digest) pairs that identify this entry's *content*, ignoring
    /// the editor metadata that varies between otherwise identical copies.
    var contentSignature: Set<String> {
        Set(
            payloads
                .filter { !ClipboardPasteboard.metadataTypes.contains($0.type) }
                .map { "\($0.type)#\($0.digest)" }
        )
    }

    /// True when the two entries hold the same content and should collapse into
    /// one history row rather than stacking as duplicates.
    func hasSameContent(as other: ClipboardItem) -> Bool {
        let mine = contentSignature
        guard !mine.isEmpty else { return false }
        return mine == other.contentSignature
    }

    /// Bumps recency for a re-copy of content already in the history.
    func recopied(at date: Date = .now, sourceAppBundleID: String?, sourceAppName: String?) -> ClipboardItem {
        var copy = self
        copy.lastCopiedAt = date
        copy.numberOfCopies += 1
        // Later copies win for attribution: the row should say where the clip
        // most recently came from.
        if let sourceAppBundleID { copy.sourceAppBundleID = sourceAppBundleID }
        if let sourceAppName { copy.sourceAppName = sourceAppName }
        return copy
    }

    func pinned(_ pinned: Bool) -> ClipboardItem {
        var copy = self
        copy.isPinned = pinned
        return copy
    }

    func payload(ofType type: String) -> ClipboardPayload? {
        payloads.first { $0.type == type }
    }

    /// The copied file URLs, for `.file` entries. Readable without touching the
    /// store: a URL list is always small enough to be inlined in the index.
    var fileURLs: [URL] {
        guard let payload = payload(ofType: NSPasteboard.PasteboardType.fileURL.rawValue),
              let data = payload.inlineValue,
              let joined = String(data: data, encoding: .utf8) else { return [] }
        return joined.split(separator: "\n").compactMap { URL(string: String($0)) }
    }

    var matchableText: String {
        var parts = [title]
        parts.append(contentsOf: fileNames)
        if let sourceAppName { parts.append(sourceAppName) }
        return parts.joined(separator: " ")
    }

    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return matchableText.localizedCaseInsensitiveContains(trimmed)
    }
}
