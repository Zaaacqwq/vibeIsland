/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation

struct LyricLine: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    let text: String

    init(timestamp: TimeInterval, text: String) {
        self.timestamp = timestamp
        self.text = text
    }
}

/// A plain lyric is kept distinct from an unavailable lyric. Neither may drive
/// line-by-line UI, but a plain lyric can trigger a cross-provider timeline
/// lookup while an unavailable result should fail cheaply.
enum LyricsLookupResult {
    case synced([LyricLine])
    case plainOnly(String)
    case none

    var isSynced: Bool {
        if case .synced(let lines) = self {
            return !lines.isEmpty
        }
        return false
    }

    var isAvailable: Bool {
        if case .none = self {
            return false
        }
        return true
    }

    var isPlainOnly: Bool {
        if case .plainOnly = self {
            return true
        }
        return false
    }
}

struct LyricsTrackQuery {
    let artist: String
    let title: String
    let album: String
    let duration: TimeInterval
}

enum LyricsProviderKind: String, CaseIterable {
    case lrclib = "LRCLIB"
    case netease = "NetEase"
    case qqMusic = "QQ Music"

    init?(bundleIdentifier: String?) {
        switch bundleIdentifier {
        case FilteredMediaRemoteConfiguration.neteaseMusic.bundleIdentifier:
            self = .netease
        case FilteredMediaRemoteConfiguration.qqMusic.bundleIdentifier:
            self = .qqMusic
        default:
            return nil
        }
    }
}

protocol LyricsProvider {
    var kind: LyricsProviderKind { get }
    func fetchLyrics(for query: LyricsTrackQuery) async throws -> LyricsLookupResult
}

struct ProviderLyricsCandidate {
    let identifier: String
    let title: String
    let artists: [String]
    let album: String
    let duration: TimeInterval
}

enum LyricsProviderError: Error {
    case invalidHTTPResponse
    case httpStatus(Int)
}
