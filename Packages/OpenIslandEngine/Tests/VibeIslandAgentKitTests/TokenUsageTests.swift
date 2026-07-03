import Foundation
import Testing
@testable import OpenIslandCore

// MARK: - Formatting

@Test("Compact token counts use K/M/B with trimmed decimals")
func compactCountFormatting() {
    #expect(TokenUsageFormat.compactCount(500) == "500")
    #expect(TokenUsageFormat.compactCount(12_918) == "12.9K")
    #expect(TokenUsageFormat.compactCount(780_000_000) == "780M")
    #expect(TokenUsageFormat.compactCount(667_300_000) == "667.3M")
    #expect(TokenUsageFormat.compactCount(1_200_000_000) == "1.2B")
}

@Test("Cost formatting scales to $, $K, $M")
func costFormatting() {
    #expect(TokenUsageFormat.cost(3.42) == "$3.42")
    #expect(TokenUsageFormat.cost(150) == "$150")
    #expect(TokenUsageFormat.cost(1_100) == "$1.1K")
    #expect(TokenUsageFormat.cost(1_250_000) == "$1.3M")
}

@Test("Active duration shows the two most significant units")
func activeDurationFormatting() {
    #expect(TokenUsageFormat.activeDuration(0) == "0m")
    #expect(TokenUsageFormat.activeDuration(2_700) == "45m")
    #expect(TokenUsageFormat.activeDuration(30_600) == "8h 30m")
    #expect(TokenUsageFormat.activeDuration(1_065_600) == "12d 8h")
}

// MARK: - Pricing

@Test("Model ids resolve to the right rate via substring match")
func modelPricingResolution() {
    #expect(ModelPricing.rate(for: "claude-opus-4-8") == ModelPricing.table["opus"])
    #expect(ModelPricing.rate(for: "claude-sonnet-5") == ModelPricing.table["sonnet"])
    #expect(ModelPricing.rate(for: "gpt-5.5") == ModelPricing.table["gpt-5"])
    #expect(ModelPricing.rate(for: "gemini-2.5-pro") == ModelPricing.table["gemini"])
    #expect(ModelPricing.rate(for: "who-knows") == nil)
}

@Test("Cost sums each category at its own rate; unknown model is free")
func modelPricingCost() {
    // 1M input tokens on Opus = $15; reasoning billed at output rate.
    let opus = ModelPricing.cost(model: "claude-opus-4-8", breakdown: TokenBreakdown(input: 1_000_000))
    #expect(abs(opus - 15) < 0.0001)

    let mixed = ModelPricing.cost(
        model: "gpt-5.5",
        breakdown: TokenBreakdown(input: 1_000_000, output: 1_000_000, reasoning: 1_000_000, cacheRead: 1_000_000)
    )
    // input 1.25 + (output+reasoning) 2*10 + cacheRead 0.125 = 21.375
    #expect(abs(mixed - 21.375) < 0.0001)

    let unknown = ModelPricing.cost(model: "mystery", breakdown: TokenBreakdown(input: 999_999))
    #expect(unknown == 0)
}

// MARK: - Aggregators (fixtures)

private func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("tokusage-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func iso(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

@Test("Claude aggregator sums usage and de-dupes replayed lines")
func claudeAggregation() throws {
    let root = makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let now = Date()
    let ts = iso(now)

    // Same message twice (replay) collapses to one; the reasoning field is absent.
    let line = """
    {"type":"assistant","timestamp":"\(ts)","requestId":"req1","message":{"id":"msg1","model":"claude-opus-4-8","role":"assistant","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":10,"cache_read_input_tokens":20}}}
    """
    try "\(line)\n\(line)\n".write(to: root.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

    let contribution = ClaudeTokenAggregator(rootURL: root).aggregate(since: now.addingTimeInterval(-86_400), now: now.addingTimeInterval(1))
    #expect(contribution.breakdown == TokenBreakdown(input: 100, output: 50, reasoning: 0, cacheRead: 20, cacheWrite: 10))
    // Both replayed lines share one timestamp, so the active span is 0.
    #expect(contribution.activeSeconds == 0)
    // 100 input * $15/M + 50 output * $75/M + 20 read * $1.5/M + 10 write * $18.75/M
    let inputCost: Double = 100 * 15
    let outputCost: Double = 50 * 75
    let readCost: Double = 20 * 1.5
    let writeCost: Double = 10 * 18.75
    let expected = (inputCost + outputCost + readCost + writeCost) / 1_000_000
    #expect(abs(contribution.costUSD - expected) < 0.0001)
}

@Test("Claude aggregator ignores lines outside the window")
func claudeWindowFilter() throws {
    let root = makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let now = Date()
    let old = iso(now.addingTimeInterval(-20 * 86_400))
    let line = """
    {"type":"assistant","timestamp":"\(old)","requestId":"r","message":{"id":"m","model":"claude-opus-4-8","role":"assistant","usage":{"input_tokens":100,"output_tokens":50}}}
    """
    try "\(line)\n".write(to: root.appendingPathComponent("old.jsonl"), atomically: true, encoding: .utf8)

    let contribution = ClaudeTokenAggregator(rootURL: root).aggregate(since: now.addingTimeInterval(-14 * 86_400), now: now)
    #expect(contribution.breakdown.isEmpty)
}

@Test("Codex aggregator takes the last cumulative usage and splits nested counts")
func codexAggregation() throws {
    let root = makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let now = Date()
    let ts = iso(now)

    let lines = """
    {"timestamp":"\(ts)","type":"turn_context","payload":{"model":"gpt-5.5"}}
    {"timestamp":"\(ts)","type":"event_msg","payload":{"info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":30,"reasoning_output_tokens":10}}}}
    {"timestamp":"\(ts)","type":"event_msg","payload":{"info":{"total_token_usage":{"input_tokens":200,"cached_input_tokens":80,"output_tokens":60,"reasoning_output_tokens":20}}}}
    """
    try "\(lines)\n".write(to: root.appendingPathComponent("rollout-2026.jsonl"), atomically: true, encoding: .utf8)

    let contribution = CodexTokenAggregator(rootURL: root).aggregate(since: now.addingTimeInterval(-86_400), now: now.addingTimeInterval(1))
    // last cumulative: input 200 (80 cached), output 60 (20 reasoning)
    #expect(contribution.breakdown == TokenBreakdown(input: 120, output: 40, reasoning: 20, cacheRead: 80, cacheWrite: 0))
}

@Test("Provider sums per-session active spans using the idle-gap model")
func providerActiveTime() throws {
    let root = makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let now = Date()
    func line(_ offset: TimeInterval, _ id: String) -> String {
        let ts = iso(now.addingTimeInterval(-offset))
        return "{\"type\":\"assistant\",\"timestamp\":\"\(ts)\",\"requestId\":\"\(id)\",\"message\":{\"id\":\"\(id)\",\"model\":\"claude-opus-4-8\",\"role\":\"assistant\",\"usage\":{\"input_tokens\":10,\"output_tokens\":5}}}"
    }
    // a,b,c are 60s apart (≤180 gap) → one run spanning 120s; d is 380s after c
    // (>180 gap) → its own run of a single message, contributing 0.
    let body = [line(1000, "a"), line(940, "b"), line(880, "c"), line(500, "d")].joined(separator: "\n")
    try "\(body)\n".write(to: root.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)

    let provider = AgentTokenUsageProvider(
        windowDays: 14,
        aggregators: [ClaudeTokenAggregator(rootURL: root)]
    )
    let summary = provider.snapshot(now: now.addingTimeInterval(1))
    #expect(summary.breakdown.totalTokens == 60)
    #expect(abs(summary.activeSeconds - 120) < 1)
    #expect(summary.windowDays == 14)
}
