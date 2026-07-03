import Foundation

/// Totals Claude Code token usage from `~/.claude/projects/**/*.jsonl`.
///
/// Claude writes one line per turn; the `assistant` line carries `message.usage`
/// with uncached `input_tokens`, `output_tokens`, and the two cache counters.
/// Lines are de-duplicated by `(message.id, requestId)` so a resumed/replayed
/// transcript does not double-count. Reasoning is always 0 (Claude reports no
/// separate reasoning token field).
public struct ClaudeTokenAggregator: TokenUsageAggregating {
    private let rootURL: URL
    private let fileManager: FileManager

    public init(
        rootURL: URL = ClaudeTranscriptDiscovery.defaultRootURL,
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

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl",
                  !fileURL.path.contains("/subagents/") else { continue }
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

                guard let message = object["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else { return }

                // De-dupe replayed assistant lines by message id + request id.
                let messageID = message["id"] as? String ?? ""
                let requestID = object["requestId"] as? String ?? ""
                if !messageID.isEmpty || !requestID.isEmpty {
                    let key = messageID + "|" + requestID
                    if seen.contains(key) { return }
                    seen.insert(key)
                }

                let lineBreakdown = TokenBreakdown(
                    input: TranscriptParsing.int(usage["input_tokens"]),
                    output: TranscriptParsing.int(usage["output_tokens"]),
                    reasoning: 0,
                    cacheRead: TranscriptParsing.int(usage["cache_read_input_tokens"]),
                    cacheWrite: TranscriptParsing.int(usage["cache_creation_input_tokens"])
                )
                guard !lineBreakdown.isEmpty else { return }

                breakdown += lineBreakdown
                let model = message["model"] as? String ?? ""
                cost += ModelPricing.cost(model: model, breakdown: lineBreakdown)
            }

            activeSeconds += AgentTokenUsageProvider.sessionActiveSeconds(timestamps: timestamps)
        }

        return AgentUsageContribution(breakdown: breakdown, costUSD: cost, activeSeconds: activeSeconds)
    }
}
