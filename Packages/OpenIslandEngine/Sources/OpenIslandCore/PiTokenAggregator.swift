import Foundation

/// Reads Pi's persisted JSONL sessions. Pi reports usage per assistant reply,
/// optional tool result, and standalone usage/summary entry. Its `reasoning`
/// counter is already part of `output`, and `cacheWrite1h` is part of
/// `cacheWrite`, so neither is added a second time.
public struct PiTokenAggregator: TokenUsageAggregating {
    public let providerID: AgentUsageProviderID = .pi

    private let rootURL: URL
    private let fileManager: FileManager

    public static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pi/agent/sessions", isDirectory: true)
    }

    public init(
        rootURL: URL = PiTokenAggregator.defaultRootURL,
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    public func aggregate(since cutoff: Date, now: Date) -> AgentUsageContribution {
        guard fileManager.fileExists(atPath: rootURL.path),
              let files = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else { return .empty }

        var breakdown = TokenBreakdown.zero
        var cost = 0.0
        var activeSeconds = 0.0
        var modelBreakdowns: [String: TokenBreakdown] = [:]
        var modelCosts: [String: Double] = [:]

        for case let fileURL as URL in files where fileURL.pathExtension == "jsonl" {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true,
                  let modifiedAt = values?.contentModificationDate,
                  modifiedAt >= cutoff else { continue }

            var timestamps: [Date] = []
            var seenEntryIDs = Set<String>()

            TranscriptParsing.forEachLine(in: fileURL) { line in
                guard let data = line.data(using: .utf8),
                      let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = entry["type"] as? String,
                      let rawTimestamp = entry["timestamp"] as? String,
                      let timestamp = TranscriptParsing.date(fromISO8601: rawTimestamp),
                      timestamp >= cutoff, timestamp <= now else { return }

                let usage: [String: Any]
                let model: String
                switch type {
                case "message":
                    guard let message = entry["message"] as? [String: Any],
                          let role = message["role"] as? String,
                          role == "assistant" || role == "toolResult",
                          let messageUsage = message["usage"] as? [String: Any] else { return }
                    usage = messageUsage
                    model = Self.modelName(provider: message["provider"], model: message["model"])
                case "usage", "compaction", "branch_summary":
                    guard let entryUsage = entry["usage"] as? [String: Any] else { return }
                    usage = entryUsage
                    model = Self.modelName(provider: entry["provider"], model: entry["model"])
                default:
                    return
                }

                if let entryID = entry["id"] as? String, !entryID.isEmpty {
                    guard seenEntryIDs.insert(entryID).inserted else { return }
                }

                let lineBreakdown = TokenBreakdown(
                    input: max(0, TranscriptParsing.int(usage["input"])),
                    output: max(0, TranscriptParsing.int(usage["output"])),
                    reasoning: 0,
                    cacheRead: max(0, TranscriptParsing.int(usage["cacheRead"])),
                    cacheWrite: max(0, TranscriptParsing.int(usage["cacheWrite"]))
                )
                let lineCost = max(0, (usage["cost"] as? [String: Any])?["total"] as? Double ?? 0)
                guard !lineBreakdown.isEmpty || lineCost > 0 else { return }

                timestamps.append(timestamp)
                breakdown += lineBreakdown
                cost += lineCost
                modelBreakdowns[model, default: .zero] += lineBreakdown
                modelCosts[model, default: 0] += lineCost
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

        return AgentUsageContribution(
            breakdown: breakdown,
            costUSD: cost,
            activeSeconds: activeSeconds,
            models: models
        )
    }

    private static func modelName(provider: Any?, model: Any?) -> String {
        guard let model = model as? String, !model.isEmpty else { return "Pi" }
        guard let provider = provider as? String, !provider.isEmpty else { return model }
        return "\(provider)/\(model)"
    }
}
