import Foundation
import Testing
@testable import OpenIslandCore

private struct FixedQuotaFetcher: ProviderQuotaFetching {
    let providerID: AgentUsageProviderID
    let snapshot: ProviderQuotaSnapshot

    func fetchQuota() async throws -> ProviderQuotaSnapshot? {
        snapshot
    }
}

private struct FailingQuotaFetcher: ProviderQuotaFetching {
    let providerID: AgentUsageProviderID

    func fetchQuota() async throws -> ProviderQuotaSnapshot? {
        throw URLError(.notConnectedToInternet)
    }
}

private func quotaTestDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("provider-quota-\(UUID().uuidString)", isDirectory: true)
}

@Test("Quota windows clamp percentages into the UI range")
func providerQuotaClampsPercentage() {
    #expect(ProviderQuotaWindow(key: "low", label: "Low", usedPercentage: -4, resetsAt: nil).usedPercentage == 0)
    #expect(ProviderQuotaWindow(key: "high", label: "High", usedPercentage: 140, resetsAt: nil).usedPercentage == 100)
    #expect(ProviderQuotaWindow(key: "nan", label: "NaN", usedPercentage: .nan, resetsAt: nil).usedPercentage == 0)
}

@Test("Quota store persists successful fetches and falls back to disk on failure")
func providerQuotaDiskFallback() async {
    let directory = quotaTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let fetchedAt = Date(timeIntervalSince1970: 10_000)
    let snapshot = ProviderQuotaSnapshot(
        providerID: .antigravity,
        windows: [
            ProviderQuotaWindow(
                key: "claude-weekly",
                label: "Claude 7d",
                usedPercentage: 42,
                resetsAt: Date(timeIntervalSince1970: 20_000)
            ),
        ],
        fetchedAt: .distantPast
    )
    let writer = ProviderQuotaStore(
        fetchers: [FixedQuotaFetcher(providerID: .antigravity, snapshot: snapshot)],
        cacheDirectory: directory,
        ttl: 300
    )
    let fresh = await writer.snapshots(forceRefresh: true, now: fetchedAt)
    #expect(fresh[.antigravity]?.fetchedAt == fetchedAt)

    let reader = ProviderQuotaStore(
        fetchers: [FailingQuotaFetcher(providerID: .antigravity)],
        cacheDirectory: directory,
        ttl: 0
    )
    let fallback = await reader.snapshots(forceRefresh: true, now: fetchedAt.addingTimeInterval(60))
    #expect(fallback[.antigravity] == fresh[.antigravity])
}

@Test("Quota store ignores snapshots returned for the wrong provider")
func providerQuotaRejectsMismatchedProvider() async {
    let directory = quotaTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let mismatched = ProviderQuotaSnapshot(
        providerID: .cursor,
        windows: [ProviderQuotaWindow(key: "monthly", label: "30d", usedPercentage: 10, resetsAt: nil)]
    )
    let store = ProviderQuotaStore(
        fetchers: [FixedQuotaFetcher(providerID: .opencode, snapshot: mismatched)],
        cacheDirectory: directory
    )

    let snapshots = await store.snapshots(forceRefresh: true)
    #expect(snapshots.isEmpty)
}

@Test("Removing a quota snapshot clears memory and disk")
func providerQuotaRemoval() async {
    let directory = quotaTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let snapshot = ProviderQuotaSnapshot(
        providerID: .antigravity,
        windows: [ProviderQuotaWindow(key: "claude", label: "Claude", usedPercentage: 25, resetsAt: nil)]
    )
    let store = ProviderQuotaStore(
        fetchers: [FixedQuotaFetcher(providerID: .antigravity, snapshot: snapshot)],
        cacheDirectory: directory
    )
    _ = await store.snapshots(forceRefresh: true)
    await store.removeSnapshot(for: .antigravity)

    let diskOnlyStore = ProviderQuotaStore(cacheDirectory: directory)
    let snapshots = await diskOnlyStore.snapshots()
    #expect(snapshots[.antigravity] == nil)
}
