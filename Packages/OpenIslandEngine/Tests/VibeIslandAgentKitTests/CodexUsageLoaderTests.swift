import Foundation
import Testing
@testable import OpenIslandCore

// MARK: - Fixtures

private struct CodexRolloutFixture {
    let rootURL: URL

    init() throws {
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-usage-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    /// Writes a `rollout-*.jsonl` under a dated subdirectory, mirroring the real
    /// `~/.codex/sessions/YYYY/MM/DD/` layout the loader walks.
    @discardableResult
    func writeRollout(
        name: String,
        lines: [String],
        modifiedAt: Date
    ) throws -> URL {
        let dayURL = rootURL.appendingPathComponent("2026/08/09", isDirectory: true)
        try FileManager.default.createDirectory(at: dayURL, withIntermediateDirectories: true)

        let fileURL = dayURL.appendingPathComponent("rollout-\(name).jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        try setModified(fileURL, to: modifiedAt)
        return fileURL
    }

    func setModified(_ fileURL: URL, to date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: fileURL.path)
    }
}

private func tokenCountLine(
    usedPercent: Double,
    windowMinutes: Int = 300,
    planType: String = "pro",
    timestamp: String = "2026-08-09T14:52:16.019Z"
) -> String {
    """
    {"type":"event_msg","timestamp":"\(timestamp)","payload":{"type":"token_count",\
    "rate_limits":{"plan_type":"\(planType)","limit_id":"limit-a",\
    "primary":{"used_percent":\(usedPercent),"window_minutes":\(windowMinutes),"resets_at":1786000000},\
    "secondary":{"used_percent":12.5,"window_minutes":10080}}}}
    """
}

/// A line the loader must skip — the shape Codex writes for ordinary turns.
private func noiseLine(padding: Int = 0) -> String {
    let filler = String(repeating: "a", count: padding)
    return #"{"type":"response_item","payload":{"type":"message","content":"\#(filler)"}}"#
}

// MARK: - Parsing

@Test("Loads the rate-limit snapshot from a rollout transcript")
func codexUsageLoadsSnapshot() throws {
    let fixture = try CodexRolloutFixture()
    defer { fixture.cleanUp() }

    try fixture.writeRollout(
        name: "a",
        lines: [noiseLine(), tokenCountLine(usedPercent: 42.5), noiseLine()],
        modifiedAt: Date()
    )

    let snapshot = try #require(try CodexUsageLoader.load(fromRootURL: fixture.rootURL))
    #expect(snapshot.planType == "pro")
    #expect(snapshot.limitID == "limit-a")
    #expect(snapshot.windows.count == 2)

    let primary = try #require(snapshot.windows.first { $0.key == "primary" })
    #expect(primary.usedPercentage == 42.5)
    #expect(primary.leftPercentage == 57.5)
    #expect(primary.windowMinutes == 300)
    #expect(primary.label == "5h")
}

@Test("Keeps the last rate-limit line, not the first")
func codexUsageKeepsLastSnapshot() throws {
    let fixture = try CodexRolloutFixture()
    defer { fixture.cleanUp() }

    try fixture.writeRollout(
        name: "b",
        lines: [
            tokenCountLine(usedPercent: 10),
            noiseLine(),
            tokenCountLine(usedPercent: 88.5),
        ],
        modifiedAt: Date()
    )

    let snapshot = try #require(try CodexUsageLoader.load(fromRootURL: fixture.rootURL))
    let primary = try #require(snapshot.windows.first { $0.key == "primary" })
    #expect(primary.usedPercentage == 88.5)
}

@Test("Falls back to an older rollout when the newest has no rate limits")
func codexUsageFallsBackToOlderRollout() throws {
    let fixture = try CodexRolloutFixture()
    defer { fixture.cleanUp() }

    try fixture.writeRollout(
        name: "old",
        lines: [tokenCountLine(usedPercent: 33)],
        modifiedAt: Date(timeIntervalSince1970: 1_000_000)
    )
    try fixture.writeRollout(
        name: "new",
        lines: [noiseLine(), noiseLine()],
        modifiedAt: Date(timeIntervalSince1970: 2_000_000)
    )

    let snapshot = try #require(try CodexUsageLoader.load(fromRootURL: fixture.rootURL))
    let primary = try #require(snapshot.windows.first { $0.key == "primary" })
    #expect(primary.usedPercentage == 33)
}

@Test("Parses rate-limit lines that straddle streaming chunk boundaries")
func codexUsageHandlesLinesLargerThanOneChunk() throws {
    let fixture = try CodexRolloutFixture()
    defer { fixture.cleanUp() }

    // Real rollouts carry multi-MB lines (tool output, base64 images). The
    // streaming reader must reassemble a line that spans many 256 KB chunks,
    // and must not lose the rate-limit line that follows one.
    try fixture.writeRollout(
        name: "wide",
        lines: [
            noiseLine(padding: 1_200_000),
            tokenCountLine(usedPercent: 61.25),
            noiseLine(padding: 800_000),
        ],
        modifiedAt: Date()
    )

    let snapshot = try #require(try CodexUsageLoader.load(fromRootURL: fixture.rootURL))
    let primary = try #require(snapshot.windows.first { $0.key == "primary" })
    #expect(primary.usedPercentage == 61.25)
}

@Test("Honors a final rate-limit line written without a trailing newline")
func codexUsageHandlesMissingTrailingNewline() throws {
    let fixture = try CodexRolloutFixture()
    defer { fixture.cleanUp() }

    let fileURL = try fixture.writeRollout(
        name: "partial",
        lines: [noiseLine()],
        modifiedAt: Date()
    )
    let unterminated = noiseLine() + "\n" + tokenCountLine(usedPercent: 77)
    try unterminated.write(to: fileURL, atomically: true, encoding: .utf8)
    try fixture.setModified(fileURL, to: Date())

    let snapshot = try #require(try CodexUsageLoader.load(fromRootURL: fixture.rootURL))
    let primary = try #require(snapshot.windows.first { $0.key == "primary" })
    #expect(primary.usedPercentage == 77)
}

@Test("Returns nil when no rollout carries rate limits")
func codexUsageReturnsNilWithoutRateLimits() throws {
    let fixture = try CodexRolloutFixture()
    defer { fixture.cleanUp() }

    try fixture.writeRollout(name: "empty", lines: [noiseLine(), noiseLine()], modifiedAt: Date())
    #expect(try CodexUsageLoader.load(fromRootURL: fixture.rootURL) == nil)
}

// MARK: - Modification-date cache

@Test("Reuses the cached snapshot while the rollout's modification date is unchanged")
func codexUsageReusesCacheForUnchangedFile() throws {
    let fixture = try CodexRolloutFixture()
    defer { fixture.cleanUp() }

    let pinnedDate = Date(timeIntervalSince1970: 3_000_000)
    let fileURL = try fixture.writeRollout(
        name: "cached",
        lines: [tokenCountLine(usedPercent: 20)],
        modifiedAt: pinnedDate
    )

    let first = try #require(try CodexUsageLoader.load(fromRootURL: fixture.rootURL))
    #expect(first.windows.first { $0.key == "primary" }?.usedPercentage == 20)

    // Rewrite the contents but restore the modification date. A loader that
    // re-reads the file every sweep would report 99; one that trusts the mtime
    // cache keeps 20. This is what stops a 4-second timer from re-reading an
    // 88 MB transcript that has not changed.
    try (tokenCountLine(usedPercent: 99) + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    try fixture.setModified(fileURL, to: pinnedDate)

    let second = try #require(try CodexUsageLoader.load(fromRootURL: fixture.rootURL))
    #expect(second.windows.first { $0.key == "primary" }?.usedPercentage == 20)
}

@Test("Re-reads a rollout once its modification date advances")
func codexUsageInvalidatesCacheOnNewModificationDate() throws {
    let fixture = try CodexRolloutFixture()
    defer { fixture.cleanUp() }

    let fileURL = try fixture.writeRollout(
        name: "moving",
        lines: [tokenCountLine(usedPercent: 20)],
        modifiedAt: Date(timeIntervalSince1970: 3_000_000)
    )
    _ = try CodexUsageLoader.load(fromRootURL: fixture.rootURL)

    try (tokenCountLine(usedPercent: 99) + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    try fixture.setModified(fileURL, to: Date(timeIntervalSince1970: 4_000_000))

    let refreshed = try #require(try CodexUsageLoader.load(fromRootURL: fixture.rootURL))
    #expect(refreshed.windows.first { $0.key == "primary" }?.usedPercentage == 99)
}

@Test("Caches the miss so a rollout without rate limits is not re-read")
func codexUsageCachesNegativeResult() throws {
    let fixture = try CodexRolloutFixture()
    defer { fixture.cleanUp() }

    let pinnedDate = Date(timeIntervalSince1970: 5_000_000)
    let fileURL = try fixture.writeRollout(
        name: "miss",
        lines: [noiseLine(), noiseLine()],
        modifiedAt: pinnedDate
    )
    #expect(try CodexUsageLoader.load(fromRootURL: fixture.rootURL) == nil)

    // Same trick as the positive case: new contents, same mtime. Without a
    // negative cache the loader would re-scan the whole file on every sweep —
    // the worst case, since a miss means reading it end to end.
    try (tokenCountLine(usedPercent: 55) + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    try fixture.setModified(fileURL, to: pinnedDate)

    #expect(try CodexUsageLoader.load(fromRootURL: fixture.rootURL) == nil)
}
