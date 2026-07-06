import Foundation

/// Totals Codex token usage from `~/.codex/sessions/**/rollout-*.jsonl`.
///
/// Unlike Claude, Codex reports `total_token_usage` as a **cumulative** running
/// total on every `event_msg`, so per file we take the last one rather than
/// summing. The cumulative counters nest — `cached_input_tokens ⊆ input_tokens`
/// and `reasoning_output_tokens ⊆ output_tokens` — so we split them into the
/// mutually-exclusive segments the summary expects. The model id comes from a
/// `turn_context` line.
public struct CodexTokenAggregator: TokenUsageAggregating {
    public let providerID: AgentUsageProviderID = .codex

    private let rootURL: URL
    private let fileManager: FileManager

    public static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    public init(
        rootURL: URL = CodexTokenAggregator.defaultRootURL,
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    public func aggregate(since cutoff: Date, now: Date) -> AgentUsageContribution {
        guard fileManager.fileExists(atPath: rootURL.path),
              let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return .empty
        }

        var breakdown = TokenBreakdown.zero
        var cost = 0.0
        var activeSeconds = 0.0
        var modelBreakdowns: [String: TokenBreakdown] = [:]
        var modelCosts: [String: Double] = [:]

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl",
                  fileURL.lastPathComponent.hasPrefix("rollout-") else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true,
                  let modifiedAt = values?.contentModificationDate,
                  modifiedAt >= cutoff else { continue }

            var model = "gpt-5"
            var lastUsage: [String: Any]?
            // One rollout file = one session; collect its in-window timestamps.
            var timestamps: [Date] = []

            TranscriptParsing.forEachLine(in: fileURL) { line in
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

                if let timestamp = object["timestamp"] as? String,
                   let date = TranscriptParsing.date(fromISO8601: timestamp),
                   date >= cutoff, date <= now {
                    timestamps.append(date)
                }

                let payload = object["payload"] as? [String: Any]
                if object["type"] as? String == "turn_context",
                   let contextModel = payload?["model"] as? String, !contextModel.isEmpty {
                    model = contextModel
                }
                if let info = payload?["info"] as? [String: Any],
                   let usage = info["total_token_usage"] as? [String: Any] {
                    lastUsage = usage
                }
            }

            activeSeconds += AgentTokenUsageProvider.sessionActiveSeconds(timestamps: timestamps)

            guard let usage = lastUsage else { continue }
            let inputTotal = TranscriptParsing.int(usage["input_tokens"])
            let cached = TranscriptParsing.int(usage["cached_input_tokens"])
            let outputTotal = TranscriptParsing.int(usage["output_tokens"])
            let reasoning = TranscriptParsing.int(usage["reasoning_output_tokens"])

            let fileBreakdown = TokenBreakdown(
                input: max(0, inputTotal - cached),
                output: max(0, outputTotal - reasoning),
                reasoning: reasoning,
                cacheRead: cached,
                cacheWrite: 0
            )
            guard !fileBreakdown.isEmpty else { continue }

            let fileCost = ModelPricing.cost(model: model, breakdown: fileBreakdown)
            breakdown += fileBreakdown
            cost += fileCost
            modelBreakdowns[model, default: .zero] += fileBreakdown
            modelCosts[model, default: 0] += fileCost
        }

        let models = modelBreakdowns.map { model, breakdown in
            ModelTokenUsageSummary(model: model, breakdown: breakdown, costUSD: modelCosts[model] ?? 0)
        }
        .sorted { lhs, rhs in
            if lhs.costUSD == rhs.costUSD { return lhs.breakdown.nonCacheTokens > rhs.breakdown.nonCacheTokens }
            return lhs.costUSD > rhs.costUSD
        }

        return AgentUsageContribution(breakdown: breakdown, costUSD: cost, activeSeconds: activeSeconds, models: models)
    }
}
