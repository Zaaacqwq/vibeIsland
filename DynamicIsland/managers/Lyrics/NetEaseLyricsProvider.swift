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

struct NetEaseLyricsProvider: LyricsProvider {
    let kind: LyricsProviderKind = .netease

    func fetchLyrics(for query: LyricsTrackQuery) async throws -> LyricsLookupResult {
        for searchQuery in LyricsProviderSupport.searchQueries(for: query) {
            let candidates = try await search(searchQuery)
            guard let match = LyricsProviderSupport.bestMatch(
                in: candidates,
                for: query
            ) else {
                continue
            }

            let result = try await lyrics(songID: match.identifier)
            if result.isAvailable {
                print("Lyrics: matched NetEase song \(match.identifier)")
            }
            return result
        }
        return .none
    }

    private func search(_ searchQuery: String) async throws -> [ProviderLyricsCandidate] {
        var components = URLComponents(string: "https://music.163.com/api/search/get")
        components?.queryItems = [
            URLQueryItem(name: "s", value: searchQuery),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "total", value: "true"),
            URLQueryItem(name: "limit", value: "12"),
        ]
        guard let url = components?.url else { return [] }

        var request = LyricsProviderSupport.request(
            url: url,
            referer: "https://music.163.com/"
        )
        request.httpMethod = "GET"
        let data = try await LyricsProviderSupport.data(for: request)
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = root["result"] as? [String: Any],
            let songs = result["songs"] as? [[String: Any]]
        else {
            return []
        }

        return songs.compactMap { song in
            guard let songID = (song["id"] as? NSNumber)?.stringValue else {
                return nil
            }
            let artists = (
                song["artists"] as? [[String: Any]]
                    ?? song["ar"] as? [[String: Any]]
                    ?? []
            )
            .compactMap { $0["name"] as? String }
            let album = song["album"] as? [String: Any]
                ?? song["al"] as? [String: Any]
            let durationMilliseconds = (song["duration"] as? NSNumber)?.doubleValue
                ?? (song["dt"] as? NSNumber)?.doubleValue
                ?? 0
            return ProviderLyricsCandidate(
                identifier: songID,
                title: song["name"] as? String ?? "",
                artists: artists,
                album: album?["name"] as? String ?? "",
                duration: durationMilliseconds / 1000
            )
        }
    }

    private func lyrics(songID: String) async throws -> LyricsLookupResult {
        var components = URLComponents(string: "https://music.163.com/api/song/lyric")
        components?.queryItems = [
            URLQueryItem(name: "id", value: songID),
            URLQueryItem(name: "lv", value: "-1"),
            URLQueryItem(name: "kv", value: "-1"),
            URLQueryItem(name: "tv", value: "-1"),
        ]
        guard let url = components?.url else { return .none }

        let request = LyricsProviderSupport.request(
            url: url,
            referer: "https://music.163.com/"
        )
        let data = try await LyricsProviderSupport.data(for: request)
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let lrc = root["lrc"] as? [String: Any],
            let lyric = lrc["lyric"] as? String
        else {
            return .none
        }
        return LyricsParser.lookupResult(from: lyric)
    }
}
