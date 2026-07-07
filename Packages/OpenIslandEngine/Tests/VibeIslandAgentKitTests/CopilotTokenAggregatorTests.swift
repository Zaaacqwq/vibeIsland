import Foundation
import SQLite3
import Testing
@testable import OpenIslandCore

/// Builds a minimal `~/.copilot/data.db`-shaped fixture (only the columns the
/// aggregator reads) and returns its path.
private func makeCopilotFixture(_ setupSQL: String) -> String {
    let path = NSTemporaryDirectory() + "copilot-\(UUID().uuidString).db"
    var db: OpaquePointer?
    #expect(sqlite3_open(path, &db) == SQLITE_OK)
    let schema = """
    CREATE TABLE sessions (
      id TEXT, title TEXT, model TEXT,
      total_input_tokens INTEGER, total_output_tokens INTEGER,
      total_cached_tokens INTEGER, total_reasoning_tokens INTEGER,
      total_nano_aiu INTEGER, created_at TEXT
    );
    """
    #expect(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK)
    #expect(sqlite3_exec(db, setupSQL, nil, nil, nil) == SQLITE_OK)
    sqlite3_close(db)
    return path
}

@Test("Copilot aggregator sums sessions and carves cache out of input")
func copilotAggregatesSessions() {
    // Recent fixed clock so ISO created_at values land inside the window.
    let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15
    let cutoff = now.addingTimeInterval(-14 * 86_400)

    // In window: created 3 days ago. Out of window: 40 days ago.
    let recent = "2027-01-12T10:00:00Z"
    let old = "2026-12-01T10:00:00Z"

    let path = makeCopilotFixture(
        """
        INSERT INTO sessions (id, model, total_input_tokens, total_output_tokens, \
        total_cached_tokens, total_reasoning_tokens, created_at) VALUES
          ('a', 'gpt-5', 1000, 200, 400, 50, '\(recent)'),
          ('b', 'claude-sonnet-4', 300, 80, 0, 0, '\(recent)'),
          ('old', 'gpt-5', 99999, 9999, 0, 0, '\(old)');
        """
    )
    defer { try? FileManager.default.removeItem(atPath: path) }

    let contribution = CopilotTokenAggregator(databasePath: path).aggregate(since: cutoff, now: now)

    // Session a: input 1000 inclusive of 400 cache → input 600, cacheRead 400.
    // Session b: input 300, no cache. Out-of-window row excluded.
    #expect(contribution.breakdown == TokenBreakdown(
        input: 900, output: 280, reasoning: 50, cacheRead: 400, cacheWrite: 0
    ))
    #expect(contribution.models.count == 2)
    // Both models priced via ModelPricing (gpt-5 + sonnet), cost > 0.
    #expect(contribution.costUSD > 0)
    // No per-message timestamps → active time not derived.
    #expect(contribution.activeSeconds == 0)
}

@Test("Copilot aggregator keeps rows with an unparseable created_at")
func copilotKeepsUnparseableTimestamps() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let cutoff = now.addingTimeInterval(-14 * 86_400)

    let path = makeCopilotFixture(
        """
        INSERT INTO sessions (id, model, total_input_tokens, total_output_tokens, \
        total_cached_tokens, total_reasoning_tokens, created_at) VALUES
          ('a', 'auto', 500, 100, 0, 0, NULL),
          ('b', 'auto', 200, 40, 0, 0, 'not-a-date');
        """
    )
    defer { try? FileManager.default.removeItem(atPath: path) }

    let contribution = CopilotTokenAggregator(databasePath: path).aggregate(since: cutoff, now: now)
    #expect(contribution.breakdown == TokenBreakdown(input: 700, output: 140))
}

@Test("Copilot aggregator returns empty for a missing database")
func copilotMissingDatabase() {
    let contribution = CopilotTokenAggregator(
        databasePath: "/no/such/data.db",
        sessionStateRoot: URL(fileURLWithPath: "/no/such/session-state")
    ).aggregate(since: .distantPast, now: .now)
    #expect(contribution.breakdown == .zero)
    #expect(contribution.models.isEmpty)
}

@Test("Copilot aggregator falls back to session-state event logs (output-only)")
func copilotEventLogFallback() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let cutoff = now.addingTimeInterval(-14 * 86_400)

    let iso = ISO8601DateFormatter()
    let t1 = iso.string(from: now.addingTimeInterval(-3_600))
    let t2 = iso.string(from: now.addingTimeInterval(-3_540)) // +60s → active time
    let old = iso.string(from: now.addingTimeInterval(-40 * 86_400))

    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("copilot-ss-\(UUID().uuidString)", isDirectory: true)
    let sessionDir = root.appendingPathComponent("session-a", isDirectory: true)
    try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
    let events = """
    {"type":"user.message","timestamp":"\(t1)","data":{"prompt":"hi"}}
    {"type":"assistant.message","timestamp":"\(t2)","data":{"model":"claude-haiku-4.5","outputTokens":113}}
    {"type":"assistant.message","timestamp":"\(t2)","data":{"model":"claude-haiku-4.5","outputTokens":32}}
    {"type":"assistant.message","timestamp":"\(old)","data":{"model":"claude-haiku-4.5","outputTokens":9999}}
    """
    try? events.write(to: sessionDir.appendingPathComponent("events.jsonl"), atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: root) }

    let contribution = CopilotTokenAggregator(
        databasePath: "/no/such/data.db",
        sessionStateRoot: root
    ).aggregate(since: cutoff, now: now)

    // Only output tokens, out-of-window message excluded: 113 + 32 = 145.
    #expect(contribution.breakdown == TokenBreakdown(output: 145))
    #expect(contribution.models.first?.model == "claude-haiku-4.5")
    // user.message at t1 and assistant at t2 span 60s → active time derived.
    #expect(contribution.activeSeconds == 60)
}

@Test("Copilot breakdown clamps cache read to available input")
func copilotBreakdownClamps() {
    // Cache reported larger than input: input floors at 0, cacheRead preserved.
    let breakdown = CopilotTokenAggregator.breakdown(input: 100, output: 50, cached: 300, reasoning: 10)
    #expect(breakdown == TokenBreakdown(input: 0, output: 50, reasoning: 10, cacheRead: 300, cacheWrite: 0))
}

@Test("Copilot model id falls back to auto")
func copilotModelIDFallback() {
    #expect(CopilotTokenAggregator.modelID("gpt-5") == "gpt-5")
    #expect(CopilotTokenAggregator.modelID(nil) == "auto")
    #expect(CopilotTokenAggregator.modelID("   ") == "auto")
}

@Test("Copilot timestamp parsing handles numeric and text forms")
func copilotTimestampParsing() {
    // Unix milliseconds.
    let ms = CopilotTokenAggregator.parseTimestamp("1700000000000")
    #expect(ms == Date(timeIntervalSince1970: 1_700_000_000))
    // ISO-8601.
    #expect(CopilotTokenAggregator.parseTimestamp("2026-07-01T12:00:00Z") != nil)
    // SQLite datetime() text form.
    #expect(CopilotTokenAggregator.parseTimestamp("2026-07-01 12:34:56") != nil)
    #expect(CopilotTokenAggregator.parseTimestamp("2026-07-01 12:34:56.789") != nil)
    #expect(CopilotTokenAggregator.parseTimestamp("garbage") == nil)
}
