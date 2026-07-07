import Foundation

/// Totals Google Antigravity token usage from its per-conversation SQLite
/// databases:
///   - `~/.gemini/antigravity-cli/conversations/<uuid>.db` (the terminal CLI)
///   - `~/.gemini/antigravity/conversations/<uuid>.db`     (the IDE)
///
/// Each database has a `gen_metadata(idx, data BLOB, size)` table where `data`
/// is a `GeneratorMetadata` protobuf blob — one row per generation (turn).
/// There is no `.proto` schema, so the field numbers below were reverse-
/// engineered (cross-checked against real transcripts, matching tokscale) and
/// decoded with the schema-less `ProtobufWire` reader:
///
///   root.#1                       → chatModel message
///     .#19  (string)              → model id (e.g. `gemini-default`,
///                                    `claude-opus-4-6-thinking`; can change
///                                    mid-conversation)
///     .#9.#4.#1 (varint)          → generation time, Unix seconds
///     .#4   (usage message)
///       .#2  (varint)             → non-cached input tokens
///       .#5  (varint)             → cache-read tokens (per-turn cached prefix)
///       .#9  (varint)             → output (text) tokens
///       .#10 (varint)             → thinking / reasoning tokens
///       .#11 (string)             → responseId (de-dup key)
///
/// Values are PER-TURN (not cumulative), verified by `#2` dropping as the
/// prefix gets cached and by the identity `#9 + #10 == #3` (total output) on
/// every row. Turns are summed and de-duplicated by responseId across all
/// databases; cost is attributed per turn from that turn's own model.
public struct AntigravityTokenAggregator: TokenUsageAggregating {
    public let providerID: AgentUsageProviderID = .antigravity

    private let rootURLs: [URL]
    private let fileManager: FileManager

    public static var defaultRootURLs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".gemini/antigravity-cli/conversations", isDirectory: true),
            home.appendingPathComponent(".gemini/antigravity/conversations", isDirectory: true),
        ]
    }

    public init(
        rootURLs: [URL] = AntigravityTokenAggregator.defaultRootURLs,
        fileManager: FileManager = .default
    ) {
        self.rootURLs = rootURLs
        self.fileManager = fileManager
    }

    public func aggregate(since cutoff: Date, now: Date) -> AgentUsageContribution {
        var breakdown = TokenBreakdown.zero
        var cost = 0.0
        var activeSeconds = 0.0
        var seen = Set<String>() // responseId de-dup, spanning every database
        var modelBreakdowns: [String: TokenBreakdown] = [:]
        var modelCosts: [String: Double] = [:]

        for root in rootURLs {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for dbURL in contents {
                guard dbURL.pathExtension == "db" else { continue }
                let values = try? dbURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
                guard values?.isRegularFile == true,
                      let modifiedAt = values?.contentModificationDate,
                      modifiedAt >= cutoff else { continue }

                // One conversation database = one session; collect its in-window
                // generation timestamps for active time.
                var timestamps: [Date] = []

                SQLiteReadOnly.read(atPath: dbURL.path) { db in
                    guard db.tableExists("gen_metadata") else { return }
                    db.query("SELECT data FROM gen_metadata ORDER BY idx;") { row in
                        guard let blob = row.blob(0) else { return true }
                        let root = ProtobufWire.parse(Array(blob))
                        guard let chat = ProtobufWire.message(root, 1),
                              let usage = ProtobufWire.message(chat, 4) else { return true }

                        // Window filter by generation time (when present).
                        if let time = ProtobufWire.message(chat, 9),
                           let stamp = ProtobufWire.message(time, 4),
                           let seconds = ProtobufWire.varint(stamp, 1) {
                            let date = Date(timeIntervalSince1970: Double(seconds))
                            guard date >= cutoff, date <= now else { return true }
                            timestamps.append(date)
                        }

                        // De-dupe replayed generations by responseId.
                        let responseID = ProtobufWire.string(usage, 11) ?? ""
                        if !responseID.isEmpty {
                            if seen.contains(responseID) { return true }
                            seen.insert(responseID)
                        }

                        let turnBreakdown = TokenBreakdown(
                            input: Int(ProtobufWire.varint(usage, 2) ?? 0),
                            output: Int(ProtobufWire.varint(usage, 9) ?? 0),
                            reasoning: Int(ProtobufWire.varint(usage, 10) ?? 0),
                            cacheRead: Int(ProtobufWire.varint(usage, 5) ?? 0),
                            cacheWrite: 0
                        )
                        guard !turnBreakdown.isEmpty else { return true }

                        breakdown += turnBreakdown
                        let model = ProtobufWire.string(chat, 19) ?? "gemini"
                        let turnCost = ModelPricing.cost(model: model, breakdown: turnBreakdown)
                        cost += turnCost
                        modelBreakdowns[model, default: .zero] += turnBreakdown
                        modelCosts[model, default: 0] += turnCost
                        return true
                    }
                }

                activeSeconds += AgentTokenUsageProvider.sessionActiveSeconds(timestamps: timestamps)
            }
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
