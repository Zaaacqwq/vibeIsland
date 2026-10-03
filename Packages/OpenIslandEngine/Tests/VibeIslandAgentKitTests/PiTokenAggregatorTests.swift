import Foundation
import OpenIslandCore
import Testing

private func piUsage(
    input: Int = 0,
    output: Int = 0,
    cacheRead: Int = 0,
    cacheWrite: Int = 0,
    reasoning: Int = 0,
    cacheWrite1h: Int = 0,
    cost: Double = 0
) -> [String: Any] {
    [
        "input": input, "output": output,
        "cacheRead": cacheRead, "cacheWrite": cacheWrite,
        "reasoning": reasoning, "cacheWrite1h": cacheWrite1h,
        "cost": ["total": cost],
    ]
}

@Test("Pi card totals assistant, tool, usage, and summary records without double counting")
func piTokenUsageFromLocalSessions() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("vibe-island-pi-usage-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let project = root.appendingPathComponent("--project--", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

    let now = Date()
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    func row(_ id: String, _ type: String, secondsAgo: TimeInterval, fields: [String: Any]) throws -> String {
        var object: [String: Any] = [
            "id": id,
            "type": type,
            "timestamp": formatter.string(from: now.addingTimeInterval(-secondsAgo)),
        ]
        object.merge(fields) { _, new in new }
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    let assistant = try row("reply", "message", secondsAgo: 80, fields: [
        "message": [
            "role": "assistant", "provider": "anthropic", "model": "claude-sonnet-4-5",
            "usage": piUsage(input: 10, output: 20, cacheRead: 30, cacheWrite: 40,
                             reasoning: 7, cacheWrite1h: 15, cost: 0.11),
        ],
    ])
    let tool = try row("tool", "message", secondsAgo: 60, fields: [
        "message": ["role": "toolResult", "usage": piUsage(output: 5, cost: 0.02)],
    ])
    let standalone = try row("cache", "usage", secondsAgo: 40, fields: [
        "provider": "anthropic", "model": "claude-sonnet-4-5",
        "usage": piUsage(cacheRead: 8, cost: 0.03),
    ])
    let compaction = try row("compact", "compaction", secondsAgo: 20, fields: [
        "usage": piUsage(input: 2, output: 3, cost: 0.04),
    ])
    let old = try row("old", "message", secondsAgo: 20 * 86_400, fields: [
        "message": ["role": "assistant", "usage": piUsage(input: 999, cost: 9.99)],
    ])
    let contents = [assistant, assistant, tool, standalone, compaction, old].joined(separator: "\n") + "\n"
    try Data(contents.utf8).write(to: project.appendingPathComponent("session.jsonl"))

    let provider = AgentTokenUsageProvider(aggregators: [PiTokenAggregator(rootURL: root)])
    let summary = provider.detailedSnapshot(now: now)
    let pi = try #require(summary.provider(.pi))
    #expect(pi.breakdown == TokenBreakdown(input: 12, output: 28, reasoning: 0, cacheRead: 38, cacheWrite: 40))
    #expect(abs(pi.costUSD - 0.20) < 0.000_001)
    #expect(abs(pi.activeSeconds - 60) < 0.01)
    #expect(pi.models.contains { $0.model == "anthropic/claude-sonnet-4-5" })
    #expect(summary.total.breakdown == pi.breakdown)
}

@Test("Pi usage is empty when no session directory exists")
func piTokenUsageMissingDirectory() {
    let missing = FileManager.default.temporaryDirectory
        .appendingPathComponent("vibe-island-pi-missing-\(UUID().uuidString)")
    let contribution = PiTokenAggregator(rootURL: missing)
        .aggregate(since: Date().addingTimeInterval(-86_400), now: .now)
    #expect(contribution.breakdown.isEmpty)
    #expect(contribution.costUSD == 0)
}
