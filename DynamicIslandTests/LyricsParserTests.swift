import XCTest
@testable import VibeIsland

final class LyricsParserTests: XCTestCase {
    func testFiltersPromotionAndKeepsRealLyrics() {
        let result = LyricsParser.parseLRC(
            """
            [00:00.00]推广：炬能推
            [00:01.00]
            [00:02.00]第一句
            [00:04.00]第二句
            """
        )

        XCTAssertEqual(result.map(\.text), ["第一句", "第二句"])
        XCTAssertEqual(result.map(\.timestamp), [2, 4])
    }

    func testSortsAndRemovesDuplicateTimestamps() {
        let result = LyricsParser.parseLRC(
            """
            [00:05.00]后一句
            [00:01.00]前一句
            [00:01.005]重复时间戳
            """
        )

        XCTAssertEqual(result.map(\.text), ["前一句", "后一句"])
        XCTAssertEqual(result.map(\.timestamp), [1, 5])
    }

    func testExpandsMultipleTimestampsOnOneRow() {
        let result = LyricsParser.parseLRC("[00:01.00][00:03.50]副歌")

        XCTAssertEqual(result.map(\.text), ["副歌", "副歌"])
        XCTAssertEqual(result.map(\.timestamp), [1, 3.5])
    }

    func testRejectsInvalidSecondsAndOutOfRangeTimeline() {
        let parsed = LyricsParser.parseLRC(
            """
            [00:61.00]坏时间
            [00:02.00]正常
            [04:20.00]超过歌曲结尾
            """
        )
        let result = LyricsParser.sanitized(parsed, trackDuration: 180)

        XCTAssertEqual(result.map(\.text), ["正常"])
    }

    func testInstrumentalPlaceholderDoesNotBecomeLyrics() {
        let result = LyricsParser.lookupResult(
            from: "[00:00.00]此歌曲为没有填词的纯音乐，请您欣赏"
        )

        guard case .none = result else {
            return XCTFail("Expected an unavailable lyric result")
        }
    }

    func testPlainLyricsAreCleanedWithoutInventingTimeline() {
        let result = LyricsParser.lookupResult(
            from: "推广：测试渠道\n第一句\n\n第二句"
        )

        guard case .plainOnly(let text) = result else {
            return XCTFail("Expected plain-only lyrics")
        }
        XCTAssertEqual(text, "第一句\n第二句")
    }
}
