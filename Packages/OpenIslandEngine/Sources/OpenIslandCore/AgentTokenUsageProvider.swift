import Foundation

/// One agent's contribution to the aggregate token summary. Each aggregator
/// computes its own `activeSeconds` (sessions are independent), and the
/// provider sums them.
public struct AgentUsageContribution: Sendable {
    public var breakdown: TokenBreakdown
    public var costUSD: Double
    public var activeSeconds: Double
    public var models: [ModelTokenUsageSummary]

    public init(
        breakdown: TokenBreakdown = .zero,
        costUSD: Double = 0,
        activeSeconds: Double = 0,
        models: [ModelTokenUsageSummary] = []
    ) {
        self.breakdown = breakdown
        self.costUSD = costUSD
        self.activeSeconds = activeSeconds
        self.models = models
    }

    public static let empty = AgentUsageContribution()
}

/// A per-agent transcript aggregator. Implementations walk that agent's local
/// transcripts and total up tokens/cost within the window. Not `Sendable` (they
/// hold a `FileManager`); the provider owns thread-safety and only runs them
/// serially on one background thread.
public protocol TokenUsageAggregating {
    var providerID: AgentUsageProviderID { get }
    func aggregate(since cutoff: Date, now: Date) -> AgentUsageContribution
}

/// Aggregates token usage across every tracked coding agent into a single
/// rolling-window `TokenUsageSummary`. Synchronous and blocking — callers run
/// it off the main thread.
public final class AgentTokenUsageProvider: @unchecked Sendable {
    /// Messages within a session closer than this are treated as one continuous
    /// active stretch; a larger silence splits the session (matching tokscale's
    /// 3-minute idle-gap model). Active time = sum of each stretch's span.
    public static let idleGapSeconds: TimeInterval = 180

    private let windowDays: Int
    private let aggregators: [TokenUsageAggregating]

    public init(
        windowDays: Int = 14,
        aggregators: [TokenUsageAggregating] = [
            ClaudeTokenAggregator(),
            CodexTokenAggregator(),
            OpenCodeTokenAggregator(),
            GeminiTokenAggregator(),
            AntigravityTokenAggregator(),
            CopilotTokenAggregator(),
            CursorTokenAggregator(),
        ]
    ) {
        self.windowDays = windowDays
        self.aggregators = aggregators
    }

    public func snapshot(now: Date = .now) -> TokenUsageSummary {
        detailedSnapshot(now: now).total
    }

    public func detailedSnapshot(now: Date = .now) -> AgentUsageSummary {
        let cutoff = now.addingTimeInterval(-Double(windowDays) * 86_400)
        var breakdown = TokenBreakdown.zero
        var cost = 0.0
        var activeSeconds = 0.0
        var providers: [ProviderTokenUsageSummary] = []

        for aggregator in aggregators {
            let contribution = aggregator.aggregate(since: cutoff, now: now)
            breakdown += contribution.breakdown
            cost += contribution.costUSD
            activeSeconds += contribution.activeSeconds

            providers.append(
                ProviderTokenUsageSummary(
                    id: aggregator.providerID,
                    breakdown: contribution.breakdown,
                    costUSD: contribution.costUSD,
                    activeSeconds: contribution.activeSeconds,
                    windowDays: windowDays,
                    generatedAt: now,
                    models: contribution.models
                )
            )
        }

        let total = TokenUsageSummary(
            breakdown: breakdown,
            costUSD: cost,
            activeSeconds: activeSeconds,
            windowDays: windowDays,
            generatedAt: now
        )

        return AgentUsageSummary(total: total, providers: providers)
    }

    /// Active time for one session's message timestamps: sort, then sum the span
    /// of each run whose consecutive gaps stay within `idleGapSeconds`. A lone
    /// message (or one isolated by long gaps) contributes 0, since transcripts
    /// carry no per-message duration.
    public static func sessionActiveSeconds(timestamps: [Date]) -> Double {
        guard timestamps.count > 1 else { return 0 }
        let sorted = timestamps.sorted()
        var total = 0.0
        var runStart = sorted[0]
        var runEnd = sorted[0]
        for ts in sorted.dropFirst() {
            if ts.timeIntervalSince(runEnd) <= idleGapSeconds {
                runEnd = ts
            } else {
                total += runEnd.timeIntervalSince(runStart)
                runStart = ts
                runEnd = ts
            }
        }
        total += runEnd.timeIntervalSince(runStart)
        return total
    }
}

/// Shared helpers for line-oriented transcript parsing.
enum TranscriptParsing {
    /// 256 KB measured fastest over a 197 MB corpus: 2.5 s per sweep against
    /// 4.0 s at 64 KB (syscall and pool churn) and 2.8 s at 1 MB. Peak memory is
    /// one chunk either way.
    private static let streamingChunkSize = 256 * 1_024

    /// Reads a `.jsonl` file and yields each non-empty line. Returns silently on
    /// unreadable files so one bad transcript never aborts the whole aggregate.
    ///
    /// Streamed in chunks rather than slurped: `String(contentsOf:)` plus a
    /// whole-file `split` held an entire transcript — 40 MB+ for a heavy
    /// session — in memory at once, and the callers run over every transcript
    /// in a 14-day window on a 60-second refresh. That was the same failure
    /// `ClaudeTranscriptDiscovery` already had to fix.
    ///
    /// The `read` itself must happen *inside* the autorelease pool. It returns an
    /// autoreleased buffer, so a `while let chunk = try? handle.read(...)` loop
    /// with the pool only around the loop *body* leaves every chunk to pile up
    /// until the enclosing pool drains — retaining the whole file, which is the
    /// leak this streaming was supposed to avoid. The aggregation is one
    /// synchronous run on a detached task with no suspension points, so nothing
    /// drains it implicitly; measured against a 197 MB transcript corpus this
    /// was +198 MB of live heap per refresh, on a 60-second timer.
    static func forEachLine(in url: URL, _ body: (String) -> Void) {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? fileHandle.close() }

        var buffer = Data()
        var reachedEnd = false
        while !reachedEnd {
            autoreleasepool {
                guard let chunk = try? fileHandle.read(upToCount: streamingChunkSize),
                      !chunk.isEmpty else {
                    reachedEnd = true
                    return
                }
                buffer.append(chunk)
                for line in extractCompleteLines(from: &buffer) {
                    body(line)
                }
            }
        }

        // Honor a final line written without a trailing newline.
        if !buffer.isEmpty {
            autoreleasepool {
                let trailing = String(decoding: buffer, as: UTF8.self)
                if !trailing.isEmpty {
                    body(trailing)
                }
            }
        }
    }

    private static func extractCompleteLines(from buffer: inout Data) -> [String] {
        let newline = UInt8(ascii: "\n")
        var lines: [String] = []
        while let newlineIndex = buffer.firstIndex(of: newline) {
            let lineData = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(...newlineIndex)
            guard !lineData.isEmpty else { continue }
            lines.append(String(decoding: lineData, as: UTF8.self))
        }
        return lines
    }

    /// Parses an ISO-8601 timestamp, tolerating the presence or absence of
    /// fractional seconds.
    static func date(fromISO8601 value: String) -> Date? {
        if let date = iso8601WithFractional.date(from: value) { return date }
        return iso8601Plain.date(from: value)
    }

    // Safe: the aggregators run serially on one background thread, so these
    // shared formatters are never touched concurrently.
    nonisolated(unsafe) private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let iso8601Plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func int(_ value: Any?) -> Int {
        switch value {
        case let value as NSNumber: return value.intValue
        case let value as String: return Int(value) ?? 0
        default: return 0
        }
    }
}
