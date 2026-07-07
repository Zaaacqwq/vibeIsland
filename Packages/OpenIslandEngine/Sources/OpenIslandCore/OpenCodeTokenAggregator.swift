import Foundation

/// Totals OpenCode token usage from `~/.local/share/opencode/opencode.db`.
///
/// OpenCode stores one row per session in the `session` table with the counters
/// already aggregated by the app: `cost` (USD), `tokens_input/output/reasoning/
/// cache_read/cache_write`, and `model` (a JSON blob `{"id":…,"providerID":…}`).
/// Because cost is precomputed we use it verbatim and never consult
/// `ModelPricing` (OpenCode routes many third-party models we don't price).
///
/// Times are Unix milliseconds. The window is filtered on `session.time_updated`;
/// active time is derived from per-message `time_created` in the `message` table,
/// grouped by session and split on the shared idle-gap model — matching how the
/// Claude/Codex aggregators compute active time.
public struct OpenCodeTokenAggregator: TokenUsageAggregating {
    public let providerID: AgentUsageProviderID = .opencode

    private let databasePath: String

    public static var defaultDatabasePath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/opencode.db")
            .path
    }

    public init(databasePath: String = OpenCodeTokenAggregator.defaultDatabasePath) {
        self.databasePath = databasePath
    }

    public func aggregate(since cutoff: Date, now: Date) -> AgentUsageContribution {
        let cutoffMs = Int64(cutoff.timeIntervalSince1970 * 1000)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)

        let contribution = SQLiteReadOnly.read(atPath: databasePath) { db -> AgentUsageContribution in
            guard db.tableExists("session") else { return .empty }

            var breakdown = TokenBreakdown.zero
            var cost = 0.0
            var modelBreakdowns: [String: TokenBreakdown] = [:]
            var modelCosts: [String: Double] = [:]

            // cutoffMs is an internally-computed integer, so inlining it carries
            // no injection risk and keeps the query free of type-affinity
            // surprises from binding a numeric value as text.
            db.query(
                """
                SELECT model, cost, tokens_input, tokens_output, tokens_reasoning, \
                tokens_cache_read, tokens_cache_write \
                FROM session WHERE time_updated >= \(cutoffMs);
                """
            ) { row in
                let sessionBreakdown = TokenBreakdown(
                    input: row.int(2),
                    output: row.int(3),
                    reasoning: row.int(4),
                    cacheRead: row.int(5),
                    cacheWrite: row.int(6)
                )
                guard !sessionBreakdown.isEmpty else { return true }

                let sessionCost = row.double(1)
                let model = Self.modelID(fromJSON: row.text(0))

                breakdown += sessionBreakdown
                cost += sessionCost
                modelBreakdowns[model, default: .zero] += sessionBreakdown
                modelCosts[model, default: 0] += sessionCost
                return true
            }

            let models = modelBreakdowns.map { model, breakdown in
                ModelTokenUsageSummary(model: model, breakdown: breakdown, costUSD: modelCosts[model] ?? 0)
            }
            .sorted { lhs, rhs in
                if lhs.costUSD == rhs.costUSD { return lhs.breakdown.nonCacheTokens > rhs.breakdown.nonCacheTokens }
                return lhs.costUSD > rhs.costUSD
            }

            let activeSeconds = Self.activeSeconds(db: db, cutoffMs: cutoffMs, nowMs: nowMs)
            return AgentUsageContribution(
                breakdown: breakdown,
                costUSD: cost,
                activeSeconds: activeSeconds,
                models: models
            )
        }

        return contribution ?? .empty
    }

    /// Sums per-session active time from in-window message timestamps. Returns 0
    /// when the `message` table is absent (older schema) — tokens still count.
    private static func activeSeconds(db: SQLiteReadOnly.Connection, cutoffMs: Int64, nowMs: Int64) -> Double {
        guard db.tableExists("message") else { return 0 }

        var timestampsBySession: [String: [Date]] = [:]
        db.query(
            """
            SELECT session_id, time_created FROM message \
            WHERE time_created >= \(cutoffMs) AND time_created <= \(nowMs);
            """
        ) { row in
            guard let sessionID = row.text(0) else { return true }
            let date = Date(timeIntervalSince1970: Double(row.int64(1)) / 1000)
            timestampsBySession[sessionID, default: []].append(date)
            return true
        }

        return timestampsBySession.values.reduce(0.0) { total, timestamps in
            total + AgentTokenUsageProvider.sessionActiveSeconds(timestamps: timestamps)
        }
    }

    /// Extracts the `id` from OpenCode's `model` JSON blob, e.g.
    /// `{"id":"glm-5.2","providerID":"opencode-go"}` → `"glm-5.2"`. Falls back to
    /// `"unknown"` for null/malformed values so those tokens still aggregate.
    static func modelID(fromJSON json: String?) -> String {
        guard let json,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String,
              !id.isEmpty else {
            return "unknown"
        }
        return id
    }
}
