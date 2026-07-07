import Foundation
import Testing
@testable import OpenIslandCore

private func iso8601String(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

/// Writes `lines` as a `session-*.jsonl` transcript under a fresh
/// `<root>/proj/chats/` tree and returns the root URL the aggregator scans.
private func makeGeminiFixture(_ lines: [String]) -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("gemini-\(UUID().uuidString)", isDirectory: true)
    let chats = root.appendingPathComponent("proj/chats", isDirectory: true)
    try? FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
    let file = chats.appendingPathComponent("session-test.jsonl")
    try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    return root
}

private func geminiTurn(
    id: String,
    at date: Date,
    model: String,
    input: Int,
    output: Int,
    cached: Int,
    thoughts: Int
) -> String {
    """
    {"id":"\(id)","type":"gemini","timestamp":"\(iso8601String(date))","model":"\(model)",\
    "tokens":{"input":\(input),"output":\(output),"cached":\(cached),"thoughts":\(thoughts),\
    "tool":0,"total":\(input + output + thoughts)}}
    """
}

@Test("Gemini aggregator sums per-turn tokens, de-duped by id, per-record model")
func geminiAggregatesPerTurn() {
    // Real `now`: the aggregator pre-filters files by modification date, and the
    // fixture file is written at the real wall-clock time.
    let now = Date()
    let cutoff = now.addingTimeInterval(-14 * 86_400)

    let turn1 = geminiTurn(
        id: "t1", at: now.addingTimeInterval(-120), model: "gemini-3.1-pro-preview",
        input: 1_000, output: 100, cached: 200, thoughts: 50
    )
    let turn2 = geminiTurn(
        id: "t2", at: now.addingTimeInterval(-60), model: "gemini-3-flash-preview",
        input: 2_000, output: 20, cached: 1_500, thoughts: 5
    )
    let outOfWindow = geminiTurn(
        id: "t3", at: now.addingTimeInterval(-30 * 86_400), model: "gemini-3-flash-preview",
        input: 999_999, output: 9_999, cached: 0, thoughts: 0
    )

    // turn1 written twice (streaming + final) to exercise id de-dup.
    let root = makeGeminiFixture([turn1, turn1, turn2, outOfWindow])
    defer { try? FileManager.default.removeItem(at: root) }

    let contribution = GeminiTokenAggregator(rootURL: root).aggregate(since: cutoff, now: now)

    // turn1: input 1000-200=800, cacheRead 200, output 100, reasoning 50
    // turn2: input 2000-1500=500, cacheRead 1500, output 20, reasoning 5
    #expect(contribution.breakdown == TokenBreakdown(
        input: 1_300, output: 120, reasoning: 55, cacheRead: 1_700, cacheWrite: 0
    ))
    #expect(contribution.models.count == 2)
    #expect(Set(contribution.models.map(\.model)) == ["gemini-3.1-pro-preview", "gemini-3-flash-preview"])

    // Two in-window turns 60s apart → 60s active.
    #expect(contribution.activeSeconds == 60)
}

@Test("Gemini aggregator ignores non-chat and non-session files")
func geminiIgnoresIrrelevantFiles() {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("gemini-\(UUID().uuidString)", isDirectory: true)
    let logs = root.appendingPathComponent("proj", isDirectory: true)
    try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    // logs.json sits outside chats/ and must be ignored.
    try? #"[{"message":"hi","tokens":{"input":500}}]"#
        .write(to: logs.appendingPathComponent("logs.json"), atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: root) }

    let contribution = GeminiTokenAggregator(rootURL: root)
        .aggregate(since: .distantPast, now: .now)
    #expect(contribution.breakdown == .zero)
}
