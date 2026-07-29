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

enum LyricsProviderSupport {
    static func request(url: URL, referer: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(referer, forHTTPHeaderField: "Referer")
        return request
    }

    static func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw LyricsProviderError.invalidHTTPResponse
        }
        guard response.statusCode == 200 else {
            throw LyricsProviderError.httpStatus(response.statusCode)
        }
        return data
    }

    static func searchQueries(for query: LyricsTrackQuery) -> [String] {
        let compactTitle = query.title.replacingOccurrences(
            of: "\\s*[\\(（\\[].*?[\\)）\\]]\\s*",
            with: " ",
            options: .regularExpression
        )
        let candidates = [
            "\(query.title) \(query.artist)",
            query.title,
            "\(compactTitle) \(query.artist)",
            compactTitle,
        ]
        var seen = Set<String>()
        return candidates.compactMap { value in
            let value = normalizedRequestComponent(value)
            guard !value.isEmpty, seen.insert(value.lowercased()).inserted else {
                return nil
            }
            return value
        }
    }

    static func bestMatch(
        in candidates: [ProviderLyricsCandidate],
        for query: LyricsTrackQuery
    ) -> ProviderLyricsCandidate? {
        let scored = candidates.map {
            (candidate: $0, score: matchScore(for: $0, query: query))
        }
        guard let best = scored.max(by: { $0.score < $1.score }),
              best.score >= 45 else {
            return nil
        }
        return best.candidate
    }

    static func normalizedMatchText(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .lowercased()
            .replacingOccurrences(
                of: "[^\\p{L}\\p{N}]+",
                with: "",
                options: .regularExpression
            )
    }

    private static func matchScore(
        for candidate: ProviderLyricsCandidate,
        query: LyricsTrackQuery
    ) -> Int {
        let expectedTitle = normalizedMatchText(query.title)
        let candidateTitle = normalizedMatchText(candidate.title)
        guard !expectedTitle.isEmpty, !candidateTitle.isEmpty else {
            return -10_000
        }

        var score = 0
        if candidateTitle == expectedTitle {
            score += 50
        } else if candidateTitle.contains(expectedTitle)
                    || expectedTitle.contains(candidateTitle) {
            score += 28
        } else {
            return -10_000
        }

        let expectedArtist = normalizedMatchText(query.artist)
        let candidateArtists = candidate.artists.map(normalizedMatchText)
        let joinedArtists = normalizedMatchText(candidate.artists.joined(separator: " "))
        let artistMatches = candidateArtists.contains(expectedArtist)
            || candidateArtists.contains {
                $0.contains(expectedArtist) || expectedArtist.contains($0)
            }
            || joinedArtists.contains(expectedArtist)
            || expectedArtist.contains(joinedArtists)
        score += artistMatches ? 35 : -25

        let expectedAlbum = normalizedMatchText(query.album)
        let candidateAlbum = normalizedMatchText(candidate.album)
        if !expectedAlbum.isEmpty, !candidateAlbum.isEmpty {
            if expectedAlbum == candidateAlbum {
                score += 12
            } else if expectedAlbum.contains(candidateAlbum)
                        || candidateAlbum.contains(expectedAlbum) {
                score += 5
            }
        }

        if query.duration > 0, candidate.duration > 0 {
            switch abs(candidate.duration - query.duration) {
            case ..<1.5: score += 30
            case ..<3: score += 18
            case ..<6: score += 6
            case 15...: score -= 25
            default: break
            }
        }

        return score
    }

    private static func normalizedRequestComponent(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
    }
}
