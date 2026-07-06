import Foundation

/// USD price per 1M tokens for one model, split by token category.
public struct ModelRate: Equatable, Sendable {
    public let inputPerM: Double
    public let outputPerM: Double
    public let cacheReadPerM: Double
    public let cacheWritePerM: Double

    public init(inputPerM: Double, outputPerM: Double, cacheReadPerM: Double, cacheWritePerM: Double) {
        self.inputPerM = inputPerM
        self.outputPerM = outputPerM
        self.cacheReadPerM = cacheReadPerM
        self.cacheWritePerM = cacheWritePerM
    }
}

/// A bundled, best-effort pricing table so token totals can be turned into an
/// approximate cost without a network call.
///
/// NOTE (maintenance): these rates drift as vendors change prices and ship new
/// models. Unknown models fall back to `nil` — their tokens still count toward
/// totals, but contribute $0 to cost. Update the table when adding models.
public enum ModelPricing {
    /// Prices in USD per 1,000,000 tokens. Reasoning tokens are billed at the
    /// output rate (they are a slice of the completion).
    static let table: [String: ModelRate] = [
        // Anthropic Claude
        "opus": ModelRate(inputPerM: 15, outputPerM: 75, cacheReadPerM: 1.5, cacheWritePerM: 18.75),
        "sonnet": ModelRate(inputPerM: 3, outputPerM: 15, cacheReadPerM: 0.3, cacheWritePerM: 3.75),
        "haiku": ModelRate(inputPerM: 1, outputPerM: 5, cacheReadPerM: 0.1, cacheWritePerM: 1.25),
        // OpenAI GPT-5 / Codex
        "gpt-5": ModelRate(inputPerM: 1.25, outputPerM: 10, cacheReadPerM: 0.125, cacheWritePerM: 1.25),
        // Google Gemini
        "gemini": ModelRate(inputPerM: 1.25, outputPerM: 10, cacheReadPerM: 0.3125, cacheWritePerM: 1.625),
    ]

    /// Resolves a raw model id (e.g. `claude-opus-4-8`, `gpt-5.4-codex`,
    /// `gemini-2.5-pro`) to a rate via substring match, longest key first so
    /// "gpt-5" beats a hypothetical "gpt". Returns nil for unknown models.
    public static func rate(for model: String) -> ModelRate? {
        let normalized = model.lowercased()
        for key in table.keys.sorted(by: { $0.count > $1.count }) where normalized.contains(key) {
            return table[key]
        }
        return nil
    }

    /// Cost for a breakdown attributed to a single model. Reasoning tokens are
    /// priced at the output rate. Unknown model → $0.
    public static func cost(model: String, breakdown: TokenBreakdown) -> Double {
        guard let rate = rate(for: model) else { return 0 }
        return cost(rate: rate, breakdown: breakdown)
    }

    public static func cost(rate: ModelRate, breakdown: TokenBreakdown) -> Double {
        let perToken = 1.0 / 1_000_000
        let inputCost = Double(breakdown.input) * rate.inputPerM
        let outputCost = Double(breakdown.output + breakdown.reasoning) * rate.outputPerM
        let cacheReadCost = Double(breakdown.cacheRead) * rate.cacheReadPerM
        let cacheWriteCost = Double(breakdown.cacheWrite) * rate.cacheWritePerM
        return (inputCost + outputCost + cacheReadCost + cacheWriteCost) * perToken
    }
}
