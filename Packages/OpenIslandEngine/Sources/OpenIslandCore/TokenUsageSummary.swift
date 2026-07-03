import Foundation

/// A breakdown of token counts by category, aggregated across agent
/// transcripts. Segments are mutually exclusive so `totalTokens` never
/// double-counts: for Claude, `input` is the uncached prompt and cache is
/// tracked separately; for Codex, the cached slice of the prompt lands in
/// `cacheRead` and the reasoning slice of the output lands in `reasoning`.
public struct TokenBreakdown: Equatable, Codable, Sendable {
    public var input: Int
    public var output: Int
    public var reasoning: Int
    public var cacheRead: Int
    public var cacheWrite: Int

    public init(
        input: Int = 0,
        output: Int = 0,
        reasoning: Int = 0,
        cacheRead: Int = 0,
        cacheWrite: Int = 0
    ) {
        self.input = input
        self.output = output
        self.reasoning = reasoning
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }

    public static let zero = TokenBreakdown()

    /// Total tokens across every mutually-exclusive segment (drives the
    /// proportional stacked bar, which still shows cache's true share).
    public var totalTokens: Int { input + output + reasoning + cacheRead + cacheWrite }

    /// Non-cache tokens (real generation: prompt + completion + reasoning).
    /// This is the headline "Token" figure — cache is excluded so Claude and
    /// Codex are comparable (Claude re-reads its whole context as cache every
    /// turn, which would otherwise dwarf everything else).
    public var nonCacheTokens: Int { input + output + reasoning }

    /// Cache tokens (creation + read), shown as its own stat tile.
    public var cacheTokens: Int { cacheRead + cacheWrite }

    public var isEmpty: Bool { totalTokens == 0 }

    public static func + (lhs: TokenBreakdown, rhs: TokenBreakdown) -> TokenBreakdown {
        TokenBreakdown(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            reasoning: lhs.reasoning + rhs.reasoning,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite
        )
    }

    public static func += (lhs: inout TokenBreakdown, rhs: TokenBreakdown) {
        lhs = lhs + rhs
    }
}

/// A rolling-window summary of token usage, cost, and active time across all
/// tracked coding agents. Rendered by the Agents tab's "Token Usage" card.
public struct TokenUsageSummary: Equatable, Codable, Sendable {
    public var breakdown: TokenBreakdown
    public var costUSD: Double
    /// Active coding time, derived from distinct activity blocks (see the
    /// aggregator). A proxy for wall-clock time spent with an agent running,
    /// not a precise stopwatch.
    public var activeSeconds: TimeInterval
    public var windowDays: Int
    public var generatedAt: Date

    public init(
        breakdown: TokenBreakdown,
        costUSD: Double,
        activeSeconds: TimeInterval,
        windowDays: Int,
        generatedAt: Date
    ) {
        self.breakdown = breakdown
        self.costUSD = costUSD
        self.activeSeconds = activeSeconds
        self.windowDays = windowDays
        self.generatedAt = generatedAt
    }

    public static func empty(windowDays: Int, generatedAt: Date = .now) -> TokenUsageSummary {
        TokenUsageSummary(
            breakdown: .zero,
            costUSD: 0,
            activeSeconds: 0,
            windowDays: windowDays,
            generatedAt: generatedAt
        )
    }

    public var isEmpty: Bool { breakdown.isEmpty }
}

/// Pure display formatters, factored out so they are unit-testable without any
/// SwiftUI or filesystem dependency.
public enum TokenUsageFormat {
    /// `12_918` → "12.9K", `780_000_000` → "780M", `1_200_000_000` → "1.2B".
    public static func compactCount(_ value: Int) -> String {
        let magnitude = Double(abs(value))
        switch magnitude {
        case 1_000_000_000...:
            return trimmed(Double(value) / 1_000_000_000) + "B"
        case 1_000_000...:
            return trimmed(Double(value) / 1_000_000) + "M"
        case 1_000...:
            return trimmed(Double(value) / 1_000) + "K"
        default:
            return "\(value)"
        }
    }

    /// `3.42` → "$3.42", `1_100` → "$1.1K", `1_250_000` → "$1.3M".
    public static func cost(_ value: Double) -> String {
        let magnitude = abs(value)
        switch magnitude {
        case 1_000_000...:
            return "$" + trimmed(value / 1_000_000) + "M"
        case 1_000...:
            return "$" + trimmed(value / 1_000) + "K"
        case 100...:
            return "$" + String(format: "%.0f", value)
        default:
            return "$" + String(format: "%.2f", value)
        }
    }

    /// `1_065_600` seconds → "12d 8h", `30_600` → "8h 30m", `2_700` → "45m",
    /// `0` → "0m". Shows the two most-significant units.
    public static func activeDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }

    /// Drops a trailing ".0" so 780.0 → "780" but 1.2 → "1.2".
    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", rounded)
    }
}
