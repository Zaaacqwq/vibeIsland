import Foundation

/// Totals Cursor token usage from a locally cached usage-export CSV.
///
/// Cursor keeps no local token store (its `state.vscdb` has zero usage keys);
/// usage lives server-side and is retrieved from
/// `cursor.com/api/dashboard/export-usage-events-csv?strategy=tokens` with a
/// pasted session token. The app-side sync manager fetches that CSV and writes
/// it to `defaultCacheURL`; this aggregator parses the cached copy, windowed on
/// each event's date. Cost is taken verbatim from the CSV (Cursor prices its
/// own routed/`auto` models), so `ModelPricing` is never consulted.
public struct CursorTokenAggregator: TokenUsageAggregating {
    public let providerID: AgentUsageProviderID = .cursor

    private let cacheURL: URL
    private let fileManager: FileManager

    /// `~/Library/Caches/VibeIsland/CursorUsage/usage.csv`.
    public static var defaultCacheURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("VibeIsland", isDirectory: true)
            .appendingPathComponent("CursorUsage", isDirectory: true)
            .appendingPathComponent("usage.csv")
    }

    public init(
        cacheURL: URL = CursorTokenAggregator.defaultCacheURL,
        fileManager: FileManager = .default
    ) {
        self.cacheURL = cacheURL
        self.fileManager = fileManager
    }

    public func aggregate(since cutoff: Date, now: Date) -> AgentUsageContribution {
        guard fileManager.fileExists(atPath: cacheURL.path),
              let csv = try? String(contentsOf: cacheURL, encoding: .utf8) else {
            return .empty
        }

        var breakdown = TokenBreakdown.zero
        var cost = 0.0
        var timestamps: [Date] = []
        var modelBreakdowns: [String: TokenBreakdown] = [:]
        var modelCosts: [String: Double] = [:]

        for record in CursorUsageCSVParser.parse(csv) {
            guard record.date >= cutoff, record.date <= now else { continue }

            breakdown += record.breakdown
            cost += record.costUSD
            timestamps.append(record.date)
            modelBreakdowns[record.model, default: .zero] += record.breakdown
            modelCosts[record.model, default: 0] += record.costUSD
        }

        guard !breakdown.isEmpty else { return .empty }

        let models = modelBreakdowns.map { model, breakdown in
            ModelTokenUsageSummary(model: model, breakdown: breakdown, costUSD: modelCosts[model] ?? 0)
        }
        .sorted { lhs, rhs in
            if lhs.costUSD == rhs.costUSD { return lhs.breakdown.nonCacheTokens > rhs.breakdown.nonCacheTokens }
            return lhs.costUSD > rhs.costUSD
        }

        // Cursor rows are per-event with distinct timestamps; the shared
        // idle-gap model turns them into an approximate active-time figure.
        let activeSeconds = AgentTokenUsageProvider.sessionActiveSeconds(timestamps: timestamps)

        return AgentUsageContribution(
            breakdown: breakdown,
            costUSD: cost,
            activeSeconds: activeSeconds,
            models: models
        )
    }
}
