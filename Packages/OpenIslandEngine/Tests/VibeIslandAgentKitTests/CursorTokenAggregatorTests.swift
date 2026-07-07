import Foundation
import Testing
@testable import OpenIslandCore

private func writeCursorCache(_ csv: String) -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("cursor-usage-\(UUID().uuidString).csv")
    try? csv.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@Test("Cursor aggregator sums in-window CSV rows and uses CSV cost verbatim")
func cursorAggregatesWindowedRows() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let cutoff = now.addingTimeInterval(-14 * 86_400)

    let iso = ISO8601DateFormatter()
    let inWindowA = iso.string(from: now.addingTimeInterval(-3_600))
    let inWindowB = iso.string(from: now.addingTimeInterval(-7_200))
    let outOfWindow = iso.string(from: now.addingTimeInterval(-40 * 86_400))

    let csv = """
    Date,Kind,Model,Max Mode,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,Total Tokens,Cost
    "\(inWindowA)","On-Demand","gpt-5-codex","No","1000","600","5000","200","6800","0.20"
    "\(inWindowB)","Included","auto","No","0","100","0","50","150","0.05"
    "\(outOfWindow)","On-Demand","gpt-5-codex","No","9999","9999","0","999","20997","99.0"
    """
    let url = writeCursorCache(csv)
    defer { try? FileManager.default.removeItem(at: url) }

    let contribution = CursorTokenAggregator(cacheURL: url).aggregate(since: cutoff, now: now)

    // Out-of-window row excluded; A + B summed.
    #expect(contribution.breakdown == TokenBreakdown(
        input: 700, output: 250, reasoning: 0, cacheRead: 5000, cacheWrite: 400
    ))
    #expect(abs(contribution.costUSD - 0.25) < 1e-9)
    // Two models, sorted by cost desc.
    #expect(contribution.models.count == 2)
    #expect(contribution.models.first?.model == "gpt-5-codex")
}

@Test("Cursor aggregator returns empty when no cache file exists")
func cursorMissingCache() {
    let url = URL(fileURLWithPath: "/no/such/usage.csv")
    let contribution = CursorTokenAggregator(cacheURL: url).aggregate(since: .distantPast, now: .now)
    #expect(contribution.breakdown == .zero)
    #expect(contribution.models.isEmpty)
}
