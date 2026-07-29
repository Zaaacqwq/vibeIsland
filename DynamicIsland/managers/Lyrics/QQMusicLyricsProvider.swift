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

struct QQMusicLyricsProvider: LyricsProvider {
    let kind: LyricsProviderKind = .qqMusic

    func fetchLyrics(for query: LyricsTrackQuery) async throws -> LyricsLookupResult {
        for searchQuery in LyricsProviderSupport.searchQueries(for: query) {
            var candidates = try await moduleSearch(searchQuery)
            if candidates.isEmpty {
                candidates = try await legacySearch(searchQuery)
            }
            guard let match = LyricsProviderSupport.bestMatch(
                in: candidates,
                for: query
            ) else {
                continue
            }

            let result = try await lyrics(songMID: match.identifier)
            if result.isAvailable {
                print("Lyrics: matched QQ Music song \(match.identifier)")
            }
            return result
        }
        return .none
    }

    private func moduleSearch(_ searchQuery: String) async throws -> [ProviderLyricsCandidate] {
        guard let url = URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg") else {
            return []
        }

        let payload: [String: Any] = [
            "music.search.SearchCgiService": [
                "method": "DoSearchForQQMusicDesktop",
                "module": "music.search.SearchCgiService",
                "param": [
                    "num_per_page": 12,
                    "page_num": 1,
                    "query": searchQuery,
                    "search_type": 0,
                ],
            ],
        ]
        var request = LyricsProviderSupport.request(
            url: url,
            referer: "https://y.qq.com/"
        )
        request.httpMethod = "POST"
        request.setValue("https://y.qq.com", forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let data = try await LyricsProviderSupport.data(for: request)

        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let module = root["music.search.SearchCgiService"] as? [String: Any],
            let resultData = module["data"] as? [String: Any],
            let body = resultData["body"] as? [String: Any],
            let songResult = body["song"] as? [String: Any],
            let songs = songResult["list"] as? [[String: Any]]
        else {
            return []
        }

        return songs.compactMap { song in
            guard let songMID = song["mid"] as? String, !songMID.isEmpty else {
                return nil
            }
            let artists = (song["singer"] as? [[String: Any]] ?? [])
                .compactMap { $0["name"] as? String }
            let album = song["album"] as? [String: Any]
            return ProviderLyricsCandidate(
                identifier: songMID,
                title: song["title"] as? String ?? song["name"] as? String ?? "",
                artists: artists,
                album: album?["name"] as? String ?? "",
                duration: (song["interval"] as? NSNumber)?.doubleValue ?? 0
            )
        }
    }

    private func legacySearch(_ searchQuery: String) async throws -> [ProviderLyricsCandidate] {
        var components = URLComponents(
            string: "https://c.y.qq.com/soso/fcgi-bin/client_search_cp"
        )
        components?.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "p", value: "1"),
            URLQueryItem(name: "n", value: "12"),
            URLQueryItem(name: "w", value: searchQuery),
        ]
        guard let url = components?.url else { return [] }

        let request = LyricsProviderSupport.request(
            url: url,
            referer: "https://y.qq.com/"
        )
        let data = try await LyricsProviderSupport.data(for: request)
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let resultData = root["data"] as? [String: Any],
            let songResult = resultData["song"] as? [String: Any],
            let songs = songResult["list"] as? [[String: Any]]
        else {
            return []
        }

        return songs.compactMap { song in
            guard let songMID = song["songmid"] as? String, !songMID.isEmpty else {
                return nil
            }
            let artists = (song["singer"] as? [[String: Any]] ?? [])
                .compactMap { $0["name"] as? String }
            return ProviderLyricsCandidate(
                identifier: songMID,
                title: song["songname"] as? String ?? "",
                artists: artists,
                album: song["albumname"] as? String ?? "",
                duration: (song["interval"] as? NSNumber)?.doubleValue ?? 0
            )
        }
    }

    private func lyrics(songMID: String) async throws -> LyricsLookupResult {
        var components = URLComponents(
            string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg"
        )
        components?.queryItems = [
            URLQueryItem(name: "songmid", value: songMID),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "nobase64", value: "1"),
        ]
        guard let url = components?.url else { return .none }

        let request = LyricsProviderSupport.request(
            url: url,
            referer: "https://c.y.qq.com/"
        )
        let data = try await LyricsProviderSupport.data(for: request)
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            var lyric = root["lyric"] as? String
        else {
            return .none
        }

        // Older endpoint variants ignore nobase64=1.
        if !lyric.contains("["),
           let decodedData = Data(base64Encoded: lyric),
           let decoded = String(data: decodedData, encoding: .utf8) {
            lyric = decoded
        }
        return LyricsParser.lookupResult(from: lyric)
    }
}
