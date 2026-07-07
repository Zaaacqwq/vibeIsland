import Foundation
import SQLite3
import Testing
@testable import OpenIslandCore

/// Builds a minimal `opencode.db`-shaped fixture (only the columns the
/// aggregator reads) and returns its path.
private func makeOpenCodeFixture(_ setupSQL: String) -> String {
    let path = NSTemporaryDirectory() + "opencode-\(UUID().uuidString).db"
    var db: OpaquePointer?
    #expect(sqlite3_open(path, &db) == SQLITE_OK)
    let schema = """
    CREATE TABLE session (
      id TEXT, time_updated INTEGER, model TEXT, cost REAL,
      tokens_input INTEGER, tokens_output INTEGER, tokens_reasoning INTEGER,
      tokens_cache_read INTEGER, tokens_cache_write INTEGER
    );
    CREATE TABLE message (session_id TEXT, time_created INTEGER);
    """
    #expect(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK)
    #expect(sqlite3_exec(db, setupSQL, nil, nil, nil) == SQLITE_OK)
    sqlite3_close(db)
    return path
}

private func ms(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970 * 1000) }

@Test("OpenCode aggregator sums in-window sessions and uses DB cost verbatim")
func openCodeAggregatesWindowedSessions() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let cutoff = now.addingTimeInterval(-14 * 86_400)

    let inWindowA = ms(now.addingTimeInterval(-3_600))
    let inWindowB = ms(now.addingTimeInterval(-7_200))
    let outOfWindow = ms(now.addingTimeInterval(-30 * 86_400))
    let msgA1 = ms(now.addingTimeInterval(-3_600))
    let msgA2 = ms(now.addingTimeInterval(-3_540)) // +60s → 60s active

    let path = makeOpenCodeFixture(
        """
        INSERT INTO session VALUES
          ('a', \(inWindowA), '{"id":"glm-5.2","providerID":"opencode-go"}', 0.10, 1000, 100, 10, 500, 0),
          ('b', \(inWindowB), '{"id":"claude-sonnet"}', 0.05, 200, 20, 0, 0, 50),
          ('old', \(outOfWindow), '{"id":"glm-5.2"}', 99.0, 999999, 9999, 0, 0, 0);
        INSERT INTO message VALUES
          ('a', \(msgA1)), ('a', \(msgA2)), ('b', \(inWindowB));
        """
    )
    defer { try? FileManager.default.removeItem(atPath: path) }

    let contribution = OpenCodeTokenAggregator(databasePath: path).aggregate(since: cutoff, now: now)

    // Out-of-window session excluded; A + B summed.
    #expect(contribution.breakdown == TokenBreakdown(
        input: 1_200, output: 120, reasoning: 10, cacheRead: 500, cacheWrite: 50
    ))
    #expect(abs(contribution.costUSD - 0.15) < 1e-9)

    // Two models, sorted by cost desc: glm-5.2 (0.10) then claude-sonnet (0.05).
    #expect(contribution.models.count == 2)
    #expect(contribution.models.first?.model == "glm-5.2")
    #expect(contribution.models.first?.costUSD == 0.10)
    #expect(contribution.models.last?.model == "claude-sonnet")

    // Session A: two messages 60s apart → 60s; B: one message → 0.
    #expect(contribution.activeSeconds == 60)
}

@Test("OpenCode aggregator returns empty for a missing database")
func openCodeMissingDatabase() {
    let contribution = OpenCodeTokenAggregator(databasePath: "/no/such/opencode.db")
        .aggregate(since: .distantPast, now: .now)
    #expect(contribution.breakdown == .zero)
    #expect(contribution.costUSD == 0)
    #expect(contribution.models.isEmpty)
}

@Test("OpenCode model JSON parsing tolerates malformed values")
func openCodeModelIDParsing() {
    #expect(OpenCodeTokenAggregator.modelID(fromJSON: #"{"id":"glm-5.2","providerID":"x"}"#) == "glm-5.2")
    #expect(OpenCodeTokenAggregator.modelID(fromJSON: nil) == "unknown")
    #expect(OpenCodeTokenAggregator.modelID(fromJSON: "not json") == "unknown")
    #expect(OpenCodeTokenAggregator.modelID(fromJSON: #"{"providerID":"x"}"#) == "unknown")
}
