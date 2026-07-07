import Foundation

/// Totals GitHub Copilot CLI token usage, from whichever local source the
/// installed Copilot version writes.
///
/// **Primary — `~/.copilot/data.db`** (older CLI / desktop): one row per session
/// in `sessions` with per-session totals `total_input_tokens`,
/// `total_output_tokens`, `total_cached_tokens`, `total_reasoning_tokens`, a
/// `model` id, and a `created_at`. KEY (matches tokscale's `copilot_desktop.rs`):
/// `total_input_tokens` is **inclusive of cache reads**, so the cached slice is
/// subtracted back out of `input` while the reported cache bucket is preserved
/// intact — otherwise additive pricing would double-charge the cached portion.
///
/// **Fallback — `~/.copilot/session-state/<id>/events.jsonl`** (newer CLI, e.g.
/// 1.0.68): the `sessions` DB no longer stores tokens; the only per-message
/// signal is `assistant.message` events, and those record **`outputTokens`
/// only** (no input/cache/reasoning). The card therefore shows output tokens
/// alone on these versions — partial but real — and auto-upgrades to the full
/// breakdown if a `data.db` reappears.
///
/// Copilot bills by premium request rather than by token and exposes no
/// per-session cost, so cost is a best-effort `ModelPricing` estimate (unknown
/// models contribute $0 but still count toward token totals).
public struct CopilotTokenAggregator: TokenUsageAggregating {
    public let providerID: AgentUsageProviderID = .copilot

    private let databasePath: String
    private let sessionStateRoot: URL
    private let fileManager: FileManager

    public static var defaultDatabasePath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".copilot/data.db")
            .path
    }

    public static var defaultSessionStateRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".copilot/session-state", isDirectory: true)
    }

    public init(
        databasePath: String = CopilotTokenAggregator.defaultDatabasePath,
        sessionStateRoot: URL = CopilotTokenAggregator.defaultSessionStateRoot,
        fileManager: FileManager = .default
    ) {
        self.databasePath = databasePath
        self.sessionStateRoot = sessionStateRoot
        self.fileManager = fileManager
    }

    public func aggregate(since cutoff: Date, now: Date) -> AgentUsageContribution {
        let dbContribution = aggregateDatabase(since: cutoff, now: now)
        if let dbContribution, !dbContribution.breakdown.isEmpty {
            return dbContribution
        }
        return aggregateEventLogs(since: cutoff, now: now)
    }

    // MARK: - Primary: data.db

    private func aggregateDatabase(since cutoff: Date, now: Date) -> AgentUsageContribution? {
        SQLiteReadOnly.read(atPath: databasePath) { db -> AgentUsageContribution in
            guard db.tableExists("sessions") else { return .empty }

            var breakdown = TokenBreakdown.zero
            var cost = 0.0
            var modelBreakdowns: [String: TokenBreakdown] = [:]
            var modelCosts: [String: Double] = [:]

            db.query(
                """
                SELECT model, total_input_tokens, total_output_tokens, \
                total_cached_tokens, total_reasoning_tokens, created_at \
                FROM sessions \
                WHERE total_input_tokens > 0 OR total_output_tokens > 0 \
                OR total_cached_tokens > 0 OR total_reasoning_tokens > 0;
                """
            ) { row in
                // A parseable created_at outside the window excludes the row;
                // an absent/unparseable timestamp is kept (a live CLI database is
                // recent, and dropping real usage is worse than a rare stale row).
                if let createdAt = Self.timestamp(row: row, index: 5),
                   createdAt < cutoff || createdAt > now {
                    return true
                }

                let sessionBreakdown = Self.breakdown(
                    input: row.int(1),
                    output: row.int(2),
                    cached: row.int(3),
                    reasoning: row.int(4)
                )
                guard !sessionBreakdown.isEmpty else { return true }

                let model = Self.modelID(row.text(0))
                let sessionCost = ModelPricing.cost(model: model, breakdown: sessionBreakdown)

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

            return AgentUsageContribution(breakdown: breakdown, costUSD: cost, activeSeconds: 0, models: models)
        }
    }

    // MARK: - Fallback: session-state event logs

    /// Scans `session-state/<id>/events.jsonl`, summing `outputTokens` from
    /// `assistant.message` events within the window. Newer Copilot CLIs record
    /// no input/cache/reasoning locally, so only the output segment is populated.
    private func aggregateEventLogs(since cutoff: Date, now: Date) -> AgentUsageContribution {
        guard let sessionDirs = try? fileManager.contentsOfDirectory(
            at: sessionStateRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return .empty
        }

        var breakdown = TokenBreakdown.zero
        var cost = 0.0
        var activeSeconds = 0.0
        var modelBreakdowns: [String: TokenBreakdown] = [:]
        var modelCosts: [String: Double] = [:]

        for sessionDir in sessionDirs {
            let eventsURL = sessionDir.appendingPathComponent("events.jsonl")
            guard fileManager.fileExists(atPath: eventsURL.path) else { continue }

            var timestamps: [Date] = []
            TranscriptParsing.forEachLine(in: eventsURL) { line in
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

                guard let timestampString = object["timestamp"] as? String,
                      let timestamp = TranscriptParsing.date(fromISO8601: timestampString),
                      timestamp >= cutoff, timestamp <= now else { return }

                let type = object["type"] as? String
                // User + assistant turns bound the active-time stretches.
                guard type == "assistant.message" || type == "user.message" else { return }
                timestamps.append(timestamp)

                guard type == "assistant.message",
                      let payload = object["data"] as? [String: Any] else { return }
                let output = TranscriptParsing.int(payload["outputTokens"])
                guard output > 0 else { return }

                let turnBreakdown = TokenBreakdown(output: output)
                let model = Self.modelID(payload["model"] as? String)
                let turnCost = ModelPricing.cost(model: model, breakdown: turnBreakdown)

                breakdown += turnBreakdown
                cost += turnCost
                modelBreakdowns[model, default: .zero] += turnBreakdown
                modelCosts[model, default: 0] += turnCost
            }

            activeSeconds += AgentTokenUsageProvider.sessionActiveSeconds(timestamps: timestamps)
        }

        guard !breakdown.isEmpty else { return .empty }

        let models = modelBreakdowns.map { model, breakdown in
            ModelTokenUsageSummary(model: model, breakdown: breakdown, costUSD: modelCosts[model] ?? 0)
        }
        .sorted { lhs, rhs in
            if lhs.costUSD == rhs.costUSD { return lhs.breakdown.nonCacheTokens > rhs.breakdown.nonCacheTokens }
            return lhs.costUSD > rhs.costUSD
        }

        return AgentUsageContribution(breakdown: breakdown, costUSD: cost, activeSeconds: activeSeconds, models: models)
    }

    /// Normalizes Copilot's cache-inclusive input into the exclusive segments the
    /// rest of the pipeline expects: the cached read is carved back out of
    /// `input` and preserved in `cacheRead`. Copilot desktop exposes no
    /// cache-write bucket, so it stays zero.
    static func breakdown(input: Int, output: Int, cached: Int, reasoning: Int) -> TokenBreakdown {
        let cacheRead = max(0, cached)
        let cacheReadForInput = min(cacheRead, max(0, input))
        return TokenBreakdown(
            input: max(0, input - cacheReadForInput),
            output: max(0, output),
            reasoning: max(0, reasoning),
            cacheRead: cacheRead,
            cacheWrite: 0
        )
    }

    /// Resolves the session's model id, falling back to `"auto"` (Copilot's
    /// own default label for auto-routed sessions) for null/empty values.
    static func modelID(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return "auto"
        }
        return raw
    }

    /// Reads `created_at`, tolerating both an integer Unix-millisecond column and
    /// a text ISO-8601 / SQLite-datetime column. Returns `nil` when the value is
    /// absent or unparseable so the caller can keep the row.
    static func timestamp(row: SQLiteReadOnly.Row, index: Int32) -> Date? {
        if row.isNull(index) { return nil }
        if let text = row.text(index), !text.isEmpty {
            return parseTimestamp(text)
        }
        let ms = row.int64(index)
        guard ms > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(ms) / 1000)
    }

    static func parseTimestamp(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Pure-numeric text is Unix milliseconds (Copilot writes this on some
        // platforms); seconds-vs-ms is disambiguated by magnitude.
        if let number = Int64(trimmed) {
            let seconds = number > 100_000_000_000 ? Double(number) / 1000 : Double(number)
            return Date(timeIntervalSince1970: seconds)
        }

        if let date = TranscriptParsing.date(fromISO8601: trimmed) { return date }
        // SQLite's default datetime() text form is space-separated and may carry
        // fractional seconds: "2026-07-01 12:34:56[.fff]".
        return sqliteDateFormatter.date(from: trimmed)
            ?? sqliteFractionalDateFormatter.date(from: trimmed)
    }

    private static let sqliteDateFormatter =
        makeSQLiteFormatter(dateFormat: "yyyy-MM-dd HH:mm:ss")
    private static let sqliteFractionalDateFormatter =
        makeSQLiteFormatter(dateFormat: "yyyy-MM-dd HH:mm:ss.SSS")

    private static func makeSQLiteFormatter(dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = dateFormat
        return formatter
    }
}
