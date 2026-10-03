import Foundation
import Testing
@testable import OpenIslandCore

// Claude Code drops a window from `rate_limits` while it carries no usage, which
// used to make the badge disappear. The display accessors turn that gap into 0%.

@Test("A reported window is shown as-is")
func claudeUsageDisplayKeepsReportedWindows() throws {
    let snapshot = ClaudeUsageSnapshot(
        fiveHour: ClaudeUsageWindow(usedPercentage: 42, resetsAt: Date(timeIntervalSince1970: 1_789_707_600)),
        sevenDay: ClaudeUsageWindow(usedPercentage: 58, resetsAt: nil)
    )

    #expect(snapshot.displayFiveHour.roundedUsedPercentage == 42)
    #expect(snapshot.displayFiveHour.resetsAt == Date(timeIntervalSince1970: 1_789_707_600))
    #expect(snapshot.displaySevenDay.roundedUsedPercentage == 58)
}

@Test("An omitted window reads 0% with no reset time")
func claudeUsageDisplayFillsOmittedWindow() throws {
    let snapshot = ClaudeUsageSnapshot(fiveHour: nil, sevenDay: ClaudeUsageWindow(usedPercentage: 58, resetsAt: nil))

    #expect(!snapshot.isEmpty)
    #expect(snapshot.displayFiveHour.roundedUsedPercentage == 0)
    #expect(snapshot.displayFiveHour.resetsAt == nil)
    #expect(snapshot.displaySevenDay.roundedUsedPercentage == 58)
}

@Test("A payload carrying only seven_day still parses, leaving five_hour absent")
func claudeUsageLoaderParsesPartialRateLimits() throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("claude-usage-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try #"{"seven_day":{"used_percentage":58,"resets_at":1790006400}}"#
        .write(to: url, atomically: true, encoding: .utf8)

    let snapshot = try #require(try ClaudeUsageLoader.load(from: url))

    #expect(snapshot.fiveHour == nil)
    #expect(snapshot.displayFiveHour == .unused)
    #expect(snapshot.displaySevenDay.roundedUsedPercentage == 58)
}

@Test("A payload with neither window yields no snapshot at all")
func claudeUsageLoaderRejectsEmptyRateLimits() throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("claude-usage-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try "{}".write(to: url, atomically: true, encoding: .utf8)

    #expect(try ClaudeUsageLoader.load(from: url) == nil)
}
