import Foundation
import Testing
@testable import OpenIslandCore

@Test("Cursor parser reads v1 (no Kind column) rows")
func cursorParsesV1() {
    let csv = """
    Date,Model,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,Total Tokens,Cost,Cost to you
    2026-02-01,gpt-4o,10,5,0,15,30,$0.10,$0.10
    2026-02-02,gpt-4o-mini,0,0,0,5,5,$0.05,$0.05
    """
    let records = CursorUsageCSVParser.parse(csv)
    #expect(records.count == 2)
    #expect(records[0].model == "gpt-4o")
    #expect(records[0].breakdown == TokenBreakdown(input: 5, output: 15, cacheWrite: 5))
    #expect(abs(records[0].costUSD - 0.10) < 1e-9)
    #expect(records[1].model == "gpt-4o-mini")
}

@Test("Cursor parser reads v2 (Kind column) rows")
func cursorParsesV2() {
    let csv = """
    Date,Kind,Model,Max Mode,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,Total Tokens,Cost
    "2026-11-13T18:36:05.846Z","Included","auto","No","28342","775","105891","21282","156290","0.19"
    "2026-11-13T13:35:04.658Z","On-Demand","gpt-5-codex","No","0","8263","66964","1612","76839","0.03"
    """
    let records = CursorUsageCSVParser.parse(csv)
    #expect(records.count == 2)
    #expect(records[0].model == "auto")
    #expect(records[0].breakdown == TokenBreakdown(
        input: 775, output: 21282, cacheRead: 105891, cacheWrite: 28342 - 775
    ))
    #expect(abs(records[0].costUSD - 0.19) < 1e-9)
    #expect(records[1].model == "gpt-5-codex")
    #expect(records[1].breakdown.cacheRead == 66964)
}

@Test("Cursor parser reads v3 (Cloud Agent + Automation columns) rows")
func cursorParsesV3() {
    let csv = """
    Date,Cloud Agent ID,Automation ID,Kind,Model,Max Mode,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,Total Tokens,Cost
    "2026-04-09T20:01:10.528Z","bc-a380","cc307","Included","composer-2","Yes","0","343446","29045760","915201","30304407","Included"
    "2026-04-09T18:02:13.576Z","bc-19a9","1a0df","On-Demand","composer-2","Yes","0","43478","420864","7957","472299","0.11"
    "2026-04-09T07:39:09.091Z","bc-4926","","Errored, No Charge","composer-2","Yes","0","104504","985600","3666","1093770","-"
    """
    let records = CursorUsageCSVParser.parse(csv)
    #expect(records.count == 3)
    // "Included" and "-" spend labels normalize to $0.
    #expect(records[0].costUSD == 0)
    #expect(records[0].breakdown.cacheRead == 29045760)
    #expect(abs(records[1].costUSD - 0.11) < 1e-9)
    #expect(records[2].costUSD == 0)
}

@Test("Cursor parser rejects non-Cursor content and handles date-only rows")
func cursorParserEdges() {
    #expect(CursorUsageCSVParser.parse("<html>error</html>").isEmpty)
    #expect(CursorUsageCSVParser.parse("").isEmpty)

    let dateOnly = """
    Date,Model,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,Total Tokens,Cost,Cost to you
    2026-03-15,gpt-4o,0,100,0,50,150,$0.02,$0.02
    """
    let records = CursorUsageCSVParser.parse(dateOnly)
    #expect(records.count == 1)
    // Date-only parsed to noon UTC (stable calendar day across all timezones).
    var components = DateComponents()
    components.year = 2026; components.month = 3; components.day = 15; components.hour = 12
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    #expect(records[0].date == calendar.date(from: components))
}

@Test("Cursor cost parsing tolerates symbols and spend labels")
func cursorCostParsing() {
    #expect(CursorUsageCSVParser.parseCost("$0.50") == 0.50)
    #expect(CursorUsageCSVParser.parseCost("$1,234.56") == 1234.56)
    #expect(CursorUsageCSVParser.parseCost("Included") == 0)
    #expect(CursorUsageCSVParser.parseCost("-") == 0)
    #expect(CursorUsageCSVParser.parseCost("") == 0)
}
