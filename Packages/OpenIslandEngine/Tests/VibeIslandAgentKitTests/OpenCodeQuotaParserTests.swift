import Foundation
import Testing
@testable import OpenIslandCore

@Test("OpenCode quota parses SolidJS hydration values in either field order")
func openCodeQuotaParsesSSR() throws {
    let source = """
    <script>
    rollingUsage:$R[42]={usagePercent:12.5,resetInSec:3600}
    weeklyUsage:$R[43]={resetInSec:172800,usagePercent:30}
    monthlyUsage:$R[44]={usagePercent:4,anything:true,resetInSec:2592000}
    </script>
    """
    let now = Date(timeIntervalSince1970: 1_000)
    let snapshot = try #require(OpenCodeQuotaParser.parse(pageSource: source, fetchedAt: now))

    #expect(snapshot.providerID == .opencode)
    #expect(snapshot.windows.map(\.key) == ["rolling", "weekly", "monthly"])
    #expect(snapshot.windows.map(\.label) == ["5h", "7d", "30d"])
    #expect(snapshot.windows.map(\.usedPercentage) == [12.5, 30, 4])
    #expect(snapshot.windows[0].resetsAt == now.addingTimeInterval(3_600))
    #expect(snapshot.windows[1].resetsAt == now.addingTimeInterval(172_800))
}

@Test("OpenCode quota parses data-slot HTML")
func openCodeQuotaParsesDataSlots() throws {
    let source = """
    <div data-slot="usage-item">
      <span data-slot="usage-label">Rolling Usage</span>
      <span data-slot="usage-value">8%</span>
      <span data-slot="reset-time">Resets in <!--$-->1 hour 30 minutes<!--/--></span>
    </div>
    <div data-slot="usage-item">
      <span data-slot="usage-label">Weekly Usage</span>
      <span data-slot="usage-value">22.5%</span>
      <span data-slot="reset-time">Resets in 6 days 2 hours</span>
    </div>
    """
    let now = Date(timeIntervalSince1970: 2_000)
    let snapshot = try #require(OpenCodeQuotaParser.parse(pageSource: source, fetchedAt: now))

    #expect(snapshot.windows.map(\.usedPercentage) == [8, 22.5])
    #expect(snapshot.windows[0].resetsAt == now.addingTimeInterval(5_400))
    #expect(snapshot.windows[1].resetsAt == now.addingTimeInterval(525_600))
}

@Test("OpenCode quota visible-text fallback supports short durations")
func openCodeQuotaParsesVisibleText() throws {
    let source = """
    Rolling Usage 0% Resets in 3h 38m
    Weekly Usage 10% Resets in 6d 4h
    Monthly Usage 4% Resets in 17d 21h
    """
    let now = Date(timeIntervalSince1970: 3_000)
    let snapshot = try #require(OpenCodeQuotaParser.parse(pageSource: source, fetchedAt: now))

    #expect(snapshot.windows.map(\.usedPercentage) == [0, 10, 4])
    #expect(snapshot.windows[0].resetsAt == now.addingTimeInterval(13_080))
    #expect(snapshot.windows[2].resetsAt == now.addingTimeInterval(1_544_400))
}

@Test("OpenCode quota visible-text fallback supports split dashboard layout")
func openCodeQuotaParsesSplitDashboardText() throws {
    let source = """
    You are subscribed to OpenCode Go.
    Rolling Usage 0% Weekly Usage 0% Monthly Usage 4%
    Resets in 5 hours 0 minutes
    Resets in 6 days 0 hours
    Resets in 17 days 17 hours
    """
    let now = Date(timeIntervalSince1970: 4_000)
    let snapshot = try #require(OpenCodeQuotaParser.parse(pageSource: source, fetchedAt: now))

    #expect(snapshot.windows.map(\.usedPercentage) == [0, 0, 4])
    #expect(snapshot.windows[0].resetsAt == now.addingTimeInterval(18_000))
    #expect(snapshot.windows[1].resetsAt == now.addingTimeInterval(518_400))
    #expect(snapshot.windows[2].resetsAt == now.addingTimeInterval(1_530_000))
}
