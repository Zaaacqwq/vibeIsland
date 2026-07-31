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

struct LyricsProviderPipeline {
    private let providers: [LyricsProviderKind: any LyricsProvider]

    init(
        providers: [LyricsProviderKind: any LyricsProvider] = [
            .lrclib: LRCLIBLyricsProvider(),
            .netease: NetEaseLyricsProvider(),
            .qqMusic: QQMusicLyricsProvider(),
        ]
    ) {
        self.providers = providers
    }

    func fetchLyrics(
        for query: LyricsTrackQuery,
        sourceBundleIdentifier: String?
    ) async throws -> LyricsLookupResult {
        try await fetchLyrics(
            for: query,
            sourceProvider: LyricsProviderKind(
                bundleIdentifier: sourceBundleIdentifier
            )
        )
    }

    func fetchLyrics(
        for query: LyricsTrackQuery,
        sourceProvider: LyricsProviderKind?
    ) async throws -> LyricsLookupResult {
        guard !query.artist.isEmpty, !query.title.isEmpty else {
            return .none
        }

        var fallbackResult: LyricsLookupResult = .none

        // Native Chinese players use their own catalogue first so the selected
        // song identifier and timeline match the version being played.
        if let sourceProvider {
            let sourceResult = try await safelyFetch(
                sourceProvider,
                query: query,
                context: "source"
            )
            if sourceResult.isSynced {
                return sourceResult
            }
            if sourceResult.isAvailable {
                fallbackResult = sourceResult
            }
        }

        let lrclibResult = try await safelyFetch(
            .lrclib,
            query: query,
            context: "primary"
        )
        if lrclibResult.isSynced {
            return lrclibResult
        }
        if lrclibResult.isAvailable {
            fallbackResult = lrclibResult
        }

        // LRCLIB can be unavailable or have no match even when another
        // catalogue has a usable timeline. Continue through the fallback
        // providers for both plain-only and unavailable primary results.
        for kind in [LyricsProviderKind.netease, .qqMusic]
            where kind != sourceProvider {
            let result = try await safelyFetch(
                kind,
                query: query,
                context: "cross-provider"
            )
            if result.isSynced {
                print("Lyrics: using cross-provider synced fallback from \(kind.rawValue)")
                return result
            }
            if !fallbackResult.isAvailable, result.isAvailable {
                fallbackResult = result
            }
        }

        return fallbackResult
    }

    private func safelyFetch(
        _ kind: LyricsProviderKind,
        query: LyricsTrackQuery,
        context: String
    ) async throws -> LyricsLookupResult {
        guard let provider = providers[kind] else { return .none }
        do {
            let result = try await provider.fetchLyrics(for: query)
            if case .synced(let lines) = result {
                let sanitized = LyricsParser.sanitized(
                    lines,
                    trackDuration: query.duration
                )
                return sanitized.isEmpty ? .none : .synced(sanitized)
            }
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            print("\(kind.rawValue) \(context) lyrics lookup failed: \(error)")
            return .none
        }
    }
}
