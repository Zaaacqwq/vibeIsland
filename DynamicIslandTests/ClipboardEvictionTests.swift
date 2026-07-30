import AppKit
import XCTest
@testable import VibeIsland

/// Eviction and ordering rules for the clipboard history.
@MainActor
final class ClipboardEvictionTests: XCTestCase {
    /// `bytes` inflates the payload so the byte-budget path can be exercised
    /// without building real images.
    private func item(
        _ title: String,
        pinned: Bool = false,
        copies: Int = 1,
        secondsAgo: TimeInterval = 0,
        bytes: Int = 0
    ) -> ClipboardItem {
        let padding = bytes > 0 ? String(repeating: "x", count: bytes) : title
        let date = Date(timeIntervalSinceNow: -secondsAgo)
        return ClipboardItem(
            kind: .text,
            title: title,
            payloads: [ClipboardPayload(type: NSPasteboard.PasteboardType.string.rawValue, value: Data(padding.utf8))],
            firstCopiedAt: date,
            lastCopiedAt: date,
            numberOfCopies: copies,
            isPinned: pinned
        )
    }

    private let generousByteBudget = 512 * 1024 * 1024

    // MARK: - Count cap

    func testUnpinnedEntriesBeyondTheLimitAreDropped() throws {
        let items = (0..<5).map { item("entry \($0)", secondsAgo: TimeInterval($0)) }

        let kept = ClipboardMonitor.evicting(items, historySize: 3, maxTotalBytes: generousByteBudget)

        XCTAssertEqual(kept.map(\.title), ["entry 0", "entry 1", "entry 2"], "Newest survive, in storage order")
    }

    func testPinnedEntriesAreExemptFromTheCountCap() throws {
        let items = [
            item("new"),
            item("pinned old", pinned: true, secondsAgo: 1_000),
            item("also new", secondsAgo: 1),
            item("pinned older", pinned: true, secondsAgo: 2_000)
        ]

        let kept = ClipboardMonitor.evicting(items, historySize: 1, maxTotalBytes: generousByteBudget)

        XCTAssertEqual(kept.map(\.title), ["new", "pinned old", "pinned older"])
        XCTAssertEqual(kept.filter(\.isPinned).count, 2, "Pinning means keep, whatever the cap says")
    }

    func testHistorySizeOfZeroStillKeepsTheNewestEntry() throws {
        let kept = ClipboardMonitor.evicting(
            [item("only"), item("older", secondsAgo: 10)],
            historySize: 0,
            maxTotalBytes: generousByteBudget
        )

        XCTAssertEqual(kept.map(\.title), ["only"], "A zero limit is clamped, not honored literally")
    }

    // MARK: - Byte budget

    func testOldestUnpinnedEntriesAreDroppedToFitTheByteBudget() throws {
        let items = [
            item("newest", bytes: 400),
            item("middle", secondsAgo: 10, bytes: 400),
            item("oldest", secondsAgo: 20, bytes: 400)
        ]

        let kept = ClipboardMonitor.evicting(items, historySize: 100, maxTotalBytes: 900)

        XCTAssertEqual(kept.map(\.title), ["newest", "middle"])
    }

    func testByteBudgetNeverDropsPinnedEntries() throws {
        let items = [
            item("pinned", pinned: true, bytes: 800),
            item("unpinned", secondsAgo: 5, bytes: 800)
        ]

        let kept = ClipboardMonitor.evicting(items, historySize: 100, maxTotalBytes: 100)

        XCTAssertEqual(kept.map(\.title), ["pinned"], "Eviction stops once only pinned entries remain")
    }

    // MARK: - Sorting

    func testLastCopiedSortIsNewestFirst() throws {
        let items = [item("old", secondsAgo: 100), item("new")]

        let sorted = items.sorted(by: ClipboardMonitor.comparator(for: .lastCopied))

        XCTAssertEqual(sorted.map(\.title), ["new", "old"])
    }

    func testMostCopiedSortFallsBackToRecency() throws {
        let items = [
            item("once", copies: 1),
            item("thrice", copies: 3, secondsAgo: 500),
            item("twice recent", copies: 2),
            item("twice old", copies: 2, secondsAgo: 900)
        ]

        let sorted = items.sorted(by: ClipboardMonitor.comparator(for: .numberOfCopies))

        XCTAssertEqual(sorted.map(\.title), ["thrice", "twice recent", "twice old", "once"])
    }
}
