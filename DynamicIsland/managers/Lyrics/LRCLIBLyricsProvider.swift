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

struct LRCLIBLyricsProvider: LyricsProvider {
    let kind: LyricsProviderKind = .lrclib

    func fetchLyrics(for query: LyricsTrackQuery) async throws -> LyricsLookupResult {
        let cleanArtist = query.artist.folding(
            options: .diacriticInsensitive,
            locale: .current
        )
        let cleanTitle = query.title.folding(
            options: .diacriticInsensitive,
            locale: .current
        )
        let cleanAlbum = query.album.folding(
            options: .diacriticInsensitive,
            locale: .current
        )

        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: cleanTitle),
            URLQueryItem(name: "artist_name", value: cleanArtist),
        ]
        guard let url = components?.url else { return .none }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let data = try await LyricsProviderSupport.data(for: request)

        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return fallbackResult(from: data)
        }

        if let results = json as? [[String: Any]] {
            guard let bestMatch = bestMatch(
                in: results,
                artist: cleanArtist,
                title: cleanTitle,
                album: cleanAlbum,
                duration: query.duration
            ) else {
                return .none
            }
            return result(from: bestMatch)
        }

        if let result = json as? [String: Any] {
            return self.result(from: result)
        }

        return .none
    }

    private func result(from value: [String: Any]) -> LyricsLookupResult {
        if value["instrumental"] as? Bool == true {
            return .none
        }

        let plain = (value["plainLyrics"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let synced = (value["syncedLyrics"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !synced.isEmpty {
            let lines = LyricsParser.parseLRC(synced)
            if !lines.isEmpty {
                return .synced(lines)
            }
        }
        return plain.isEmpty ? .none : .plainOnly(plain)
    }

    private func fallbackResult(from data: Data) -> LyricsLookupResult {
        guard let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty else {
            return .none
        }
        return LyricsParser.lookupResult(from: value)
    }

    private func bestMatch(
        in results: [[String: Any]],
        artist: String,
        title: String,
        album: String,
        duration: TimeInterval
    ) -> [String: Any]? {
        let artist = artist.lowercased()
        let title = title.lowercased()
        let album = album.lowercased()
        return results.max {
            matchScore(
                for: $0,
                artist: artist,
                title: title,
                album: album,
                duration: duration
            ) < matchScore(
                for: $1,
                artist: artist,
                title: title,
                album: album,
                duration: duration
            )
        }
    }

    private func matchScore(
        for result: [String: Any],
        artist: String,
        title: String,
        album: String,
        duration: TimeInterval
    ) -> Int {
        let resultArtist = (result["artistName"] as? String ?? "").lowercased()
        let resultTitle = (result["trackName"] as? String ?? "").lowercased()
        let resultAlbum = (result["albumName"] as? String ?? "").lowercased()
        var score = 0

        if resultTitle == title {
            score += 8
        } else if resultTitle.contains(title) || title.contains(resultTitle) {
            score += 4
        }

        if resultArtist == artist {
            score += 8
        } else if resultArtist.contains(artist) || artist.contains(resultArtist) {
            score += 4
        }

        if !album.isEmpty {
            if resultAlbum == album {
                score += 4
            } else if resultAlbum.contains(album) || album.contains(resultAlbum) {
                score += 2
            }
        }

        if !(result["syncedLyrics"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty {
            score += 3
        }

        if duration > 0,
           let resultDuration = (result["duration"] as? NSNumber)?.doubleValue,
           resultDuration > 0 {
            let difference = abs(resultDuration - duration)
            switch difference {
            case ..<1.5: score += 25
            case ..<3: score += 12
            case ..<6: score += 4
            default: score -= Int(min(difference, 120))
            }
        }

        return score
    }
}
