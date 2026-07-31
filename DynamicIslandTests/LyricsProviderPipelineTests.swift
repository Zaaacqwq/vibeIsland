import XCTest
@testable import VibeIsland

final class LyricsProviderPipelineTests: XCTestCase {
    private let query = LyricsTrackQuery(
        artist: "菲菲公主",
        title: "第57次取消发送",
        album: "",
        duration: 180.56
    )

    func testReturnsLRCLIBSyncedLyricsWithoutFallback() async throws {
        let recorder = ProviderCallRecorder()
        let pipeline = makePipeline(
            recorder: recorder,
            results: [
                .lrclib: .synced([LyricLine(timestamp: 1, text: "LRCLIB")]),
                .netease: .synced([LyricLine(timestamp: 1, text: "网易云")]),
                .qqMusic: .synced([LyricLine(timestamp: 1, text: "QQ")]),
            ]
        )

        let result = try await pipeline.fetchLyrics(
            for: query,
            sourceProvider: nil
        )

        XCTAssertEqual(syncedTexts(result), ["LRCLIB"])
        let calls = await recorder.calls
        XCTAssertEqual(calls, [.lrclib])
    }

    func testPlainLRCLIBFallsBackToNetEaseTimeline() async throws {
        let recorder = ProviderCallRecorder()
        let pipeline = makePipeline(
            recorder: recorder,
            results: [
                .lrclib: .plainOnly("完整纯文本"),
                .netease: .synced([LyricLine(timestamp: 2, text: "网易云同步歌词")]),
                .qqMusic: .synced([LyricLine(timestamp: 2, text: "QQ同步歌词")]),
            ]
        )

        let result = try await pipeline.fetchLyrics(
            for: query,
            sourceProvider: nil
        )

        XCTAssertEqual(syncedTexts(result), ["网易云同步歌词"])
        let calls = await recorder.calls
        XCTAssertEqual(calls, [.lrclib, .netease])
    }

    func testMissingLRCLIBFallsBackToNetEaseTimeline() async throws {
        let recorder = ProviderCallRecorder()
        let pipeline = makePipeline(
            recorder: recorder,
            results: [
                .lrclib: .none,
                .netease: .synced([LyricLine(timestamp: 2, text: "网易云同步歌词")]),
                .qqMusic: .synced([LyricLine(timestamp: 2, text: "QQ同步歌词")]),
            ]
        )

        let result = try await pipeline.fetchLyrics(
            for: query,
            sourceProvider: nil
        )

        XCTAssertEqual(syncedTexts(result), ["网易云同步歌词"])
        let calls = await recorder.calls
        XCTAssertEqual(calls, [.lrclib, .netease])
    }

    func testFailedNetEaseSourceContinuesToQQFallback() async throws {
        let recorder = ProviderCallRecorder()
        let pipeline = LyricsProviderPipeline(providers: [
            .lrclib: StubLyricsProvider(
                kind: .lrclib,
                recorder: recorder,
                outcome: .result(.plainOnly("完整纯文本"))
            ),
            .netease: StubLyricsProvider(
                kind: .netease,
                recorder: recorder,
                outcome: .failure(TestFailure.expected)
            ),
            .qqMusic: StubLyricsProvider(
                kind: .qqMusic,
                recorder: recorder,
                outcome: .result(
                    .synced([LyricLine(timestamp: 3, text: "QQ同步歌词")])
                )
            ),
        ])

        let result = try await pipeline.fetchLyrics(
            for: query,
            sourceProvider: .netease
        )

        XCTAssertEqual(syncedTexts(result), ["QQ同步歌词"])
        let calls = await recorder.calls
        XCTAssertEqual(calls, [.netease, .lrclib, .qqMusic])
    }

    func testNativeSourceTimelineWins() async throws {
        let recorder = ProviderCallRecorder()
        let pipeline = makePipeline(
            recorder: recorder,
            results: [
                .lrclib: .synced([LyricLine(timestamp: 1, text: "LRCLIB")]),
                .netease: .synced([LyricLine(timestamp: 1, text: "网易云")]),
                .qqMusic: .none,
            ]
        )

        let result = try await pipeline.fetchLyrics(
            for: query,
            sourceProvider: .netease
        )

        XCTAssertEqual(syncedTexts(result), ["网易云"])
        let calls = await recorder.calls
        XCTAssertEqual(calls, [.netease])
    }

    func testCorruptTimelineFallsThroughToNextProvider() async throws {
        let recorder = ProviderCallRecorder()
        let pipeline = makePipeline(
            recorder: recorder,
            results: [
                .lrclib: .plainOnly("完整纯文本"),
                .netease: .synced([
                    LyricLine(timestamp: 500, text: "错误时间轴"),
                ]),
                .qqMusic: .synced([
                    LyricLine(timestamp: 4, text: "可用时间轴"),
                ]),
            ]
        )

        let result = try await pipeline.fetchLyrics(
            for: query,
            sourceProvider: nil
        )

        XCTAssertEqual(syncedTexts(result), ["可用时间轴"])
        let calls = await recorder.calls
        XCTAssertEqual(calls, [.lrclib, .netease, .qqMusic])
    }

    private func makePipeline(
        recorder: ProviderCallRecorder,
        results: [LyricsProviderKind: LyricsLookupResult]
    ) -> LyricsProviderPipeline {
        LyricsProviderPipeline(providers: Dictionary(
            uniqueKeysWithValues: LyricsProviderKind.allCases.map { kind in
                (
                    kind,
                    StubLyricsProvider(
                        kind: kind,
                        recorder: recorder,
                        outcome: .result(results[kind] ?? .none)
                    ) as any LyricsProvider
                )
            }
        ))
    }

    private func syncedTexts(_ result: LyricsLookupResult) -> [String] {
        guard case .synced(let lines) = result else { return [] }
        return lines.map(\.text)
    }
}

private actor ProviderCallRecorder {
    private(set) var calls: [LyricsProviderKind] = []

    func record(_ kind: LyricsProviderKind) {
        calls.append(kind)
    }
}

private struct StubLyricsProvider: LyricsProvider {
    enum Outcome {
        case result(LyricsLookupResult)
        case failure(Error)
    }

    let kind: LyricsProviderKind
    let recorder: ProviderCallRecorder
    let outcome: Outcome

    func fetchLyrics(
        for query: LyricsTrackQuery
    ) async throws -> LyricsLookupResult {
        await recorder.record(kind)
        switch outcome {
        case .result(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}

private enum TestFailure: Error {
    case expected
}
