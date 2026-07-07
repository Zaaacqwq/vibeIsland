import Foundation

/// Totals Gemini CLI token usage from `~/.gemini/tmp/<project>/chats/session-*.jsonl`.
///
/// Each `gemini`-type line carries a **per-turn** `tokens` snapshot (NOT a
/// running cumulative like Codex): `{input, output, cached, thoughts, tool,
/// total}` where `total == input + output + thoughts` and `cached ⊆ input`.
/// Lines are written twice (a streaming update and its final), so turns are
/// de-duplicated by their record `id` before summing — matching how the Claude
/// aggregator sums per-turn usage rather than reading one cumulative total.
///
/// The model can change mid-session (e.g. `gemini-3.1-pro-preview` →
/// `gemini-3-flash-preview`), so cost is attributed per turn from that record's
/// own `model` via `ModelPricing`.
public struct GeminiTokenAggregator: TokenUsageAggregating {
    public let providerID: AgentUsageProviderID = .gemini

    private let rootURL: URL
    private let fileManager: FileManager

    public static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/tmp", isDirectory: true)
    }

    public init(
        rootURL: URL = GeminiTokenAggregator.defaultRootURL,
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
        var seen = Set<String>()
        var modelBreakdowns: [String: TokenBreakdown] = [:]
        var modelCosts: [String: Double] = [:]

        for case let fileURL as URL in enumerator {
            // Chat transcripts only: <project>/chats/session-*.jsonl.
            guard fileURL.pathExtension == "jsonl",
                  fileURL.lastPathComponent.hasPrefix("session-"),
                  fileURL.deletingLastPathComponent().lastPathComponent == "chats" else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true,
                  let modifiedAt = values?.contentModificationDate,
                  modifiedAt >= cutoff else { continue }

            // One transcript file = one session; collect its in-window timestamps.
            var timestamps: [Date] = []

            TranscriptParsing.forEachLine(in: fileURL) { line in
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

                // Window filter by row timestamp; also feeds active-time.
                if let timestamp = object["timestamp"] as? String,
                   let date = TranscriptParsing.date(fromISO8601: timestamp) {
                    guard date >= cutoff && date <= now else { return }
                    timestamps.append(date)
                }

                guard let tokens = object["tokens"] as? [String: Any] else { return }

                // De-dupe the streaming/final double-write by record id.
                let recordID = object["id"] as? String ?? ""
                if !recordID.isEmpty {
                    if seen.contains(recordID) { return }
                    seen.insert(recordID)
                }

                let input = TranscriptParsing.int(tokens["input"])
                let cached = TranscriptParsing.int(tokens["cached"])
                let output = TranscriptParsing.int(tokens["output"])
                let thoughts = TranscriptParsing.int(tokens["thoughts"])

                let turnBreakdown = TokenBreakdown(
                    input: max(0, input - cached),
                    output: output,
                    reasoning: thoughts,
                    cacheRead: cached,
                    cacheWrite: 0
                )
                guard !turnBreakdown.isEmpty else { return }

                breakdown += turnBreakdown
                let model = object["model"] as? String ?? "gemini"
                let turnCost = ModelPricing.cost(model: model, breakdown: turnBreakdown)
                cost += turnCost
                modelBreakdowns[model, default: .zero] += turnBreakdown
                modelCosts[model, default: 0] += turnCost
            }

            activeSeconds += AgentTokenUsageProvider.sessionActiveSeconds(timestamps: timestamps)
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
