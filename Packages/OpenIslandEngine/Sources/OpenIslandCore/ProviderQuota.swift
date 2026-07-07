import Foundation

/// A provider-defined quota window normalized for the shared usage UI.
public struct ProviderQuotaWindow: Equatable, Codable, Sendable, Identifiable {
    public var key: String
    public var label: String
    public var usedPercentage: Double
    public var resetsAt: Date?

    public var id: String { key }

    public init(
        key: String,
        label: String,
        usedPercentage: Double,
        resetsAt: Date?
    ) {
        self.key = key
        self.label = label
        self.usedPercentage = usedPercentage.isFinite
            ? min(max(usedPercentage, 0), 100)
            : 0
        self.resetsAt = resetsAt
    }
}

/// The last successfully fetched quota state for one provider.
public struct ProviderQuotaSnapshot: Equatable, Codable, Sendable, Identifiable {
    public var providerID: AgentUsageProviderID
    public var windows: [ProviderQuotaWindow]
    public var fetchedAt: Date

    public var id: AgentUsageProviderID { providerID }
    public var isEmpty: Bool { windows.isEmpty }

    public init(
        providerID: AgentUsageProviderID,
        windows: [ProviderQuotaWindow],
        fetchedAt: Date = .now
    ) {
        self.providerID = providerID
        self.windows = windows
        self.fetchedAt = fetchedAt
    }
}

/// Implemented by provider-specific network or web-session quota clients.
public protocol ProviderQuotaFetching: Sendable {
    var providerID: AgentUsageProviderID { get }
    func fetchQuota() async throws -> ProviderQuotaSnapshot?
}

/// Adds TTL and disk fallback around slow or failure-prone provider quota APIs.
///
/// A failed refresh never deletes the last successful value. This lets the UI
/// continue showing stale quota data when an unofficial endpoint, login session,
/// or network connection is temporarily unavailable.
public actor ProviderQuotaStore {
    public static let defaultTTL: TimeInterval = 5 * 60

    private let fetchers: [AgentUsageProviderID: any ProviderQuotaFetching]
    private let cacheDirectory: URL
    private let ttl: TimeInterval
    private let fileManager: FileManager
    private var memory: [AgentUsageProviderID: ProviderQuotaSnapshot] = [:]
    private var lastAttempt: [AgentUsageProviderID: Date] = [:]
    private var didLoadDiskCache = false

    public init(
        fetchers: [any ProviderQuotaFetching] = [],
        cacheDirectory: URL = ProviderQuotaStore.defaultCacheDirectory,
        ttl: TimeInterval = ProviderQuotaStore.defaultTTL,
        fileManager: FileManager = .default
    ) {
        var fetchersByProvider: [AgentUsageProviderID: any ProviderQuotaFetching] = [:]
        for fetcher in fetchers where fetchersByProvider[fetcher.providerID] == nil {
            fetchersByProvider[fetcher.providerID] = fetcher
        }
        self.fetchers = fetchersByProvider
        self.cacheDirectory = cacheDirectory
        self.ttl = max(0, ttl)
        self.fileManager = fileManager
    }

    public static var defaultCacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("VibeIsland", isDirectory: true)
            .appendingPathComponent("AgentQuota", isDirectory: true)
    }

    /// Returns all cached snapshots, refreshing configured providers as needed.
    public func snapshots(
        forceRefresh: Bool = false,
        now: Date = .now
    ) async -> [AgentUsageProviderID: ProviderQuotaSnapshot] {
        loadDiskCacheIfNeeded()

        for (providerID, fetcher) in fetchers {
            if !forceRefresh,
               let cached = memory[providerID],
               now.timeIntervalSince(cached.fetchedAt) < ttl {
                continue
            }
            if !forceRefresh,
               let attemptedAt = lastAttempt[providerID],
               now.timeIntervalSince(attemptedAt) < ttl {
                continue
            }

            lastAttempt[providerID] = now
            do {
                guard var snapshot = try await fetcher.fetchQuota(),
                      snapshot.providerID == providerID,
                      !snapshot.isEmpty else {
                    continue
                }
                snapshot.fetchedAt = now
                memory[providerID] = snapshot
                persist(snapshot)
            } catch {
                // Deliberately retain the last successful memory/disk value.
            }
        }

        return memory
    }

    /// Refreshes a single provider, honoring the same TTL/dedup rules as
    /// `snapshots(forceRefresh:)`. Returns the latest snapshot (fresh, cached,
    /// or `nil` if never fetched). A failed refresh keeps the last good value.
    public func refreshSnapshot(
        for providerID: AgentUsageProviderID,
        force: Bool = false,
        now: Date = .now
    ) async -> ProviderQuotaSnapshot? {
        loadDiskCacheIfNeeded()
        guard let fetcher = fetchers[providerID] else { return memory[providerID] }

        if !force,
           let cached = memory[providerID],
           now.timeIntervalSince(cached.fetchedAt) < ttl {
            return cached
        }
        if !force,
           let attemptedAt = lastAttempt[providerID],
           now.timeIntervalSince(attemptedAt) < ttl {
            return memory[providerID]
        }

        lastAttempt[providerID] = now
        do {
            guard var snapshot = try await fetcher.fetchQuota(),
                  snapshot.providerID == providerID,
                  !snapshot.isEmpty else {
                return memory[providerID]
            }
            snapshot.fetchedAt = now
            memory[providerID] = snapshot
            persist(snapshot)
            return snapshot
        } catch {
            return memory[providerID]
        }
    }

    /// Removes both memory and disk state, used when a user disconnects an
    /// authenticated provider.
    public func removeSnapshot(for providerID: AgentUsageProviderID) {
        loadDiskCacheIfNeeded()
        memory.removeValue(forKey: providerID)
        lastAttempt.removeValue(forKey: providerID)
        try? fileManager.removeItem(at: cacheURL(for: providerID))
    }

    /// Stores a snapshot produced outside the configured fetchers, for example
    /// from an already-visible provider login web view.
    public func storeSnapshot(_ snapshot: ProviderQuotaSnapshot) {
        loadDiskCacheIfNeeded()
        guard !snapshot.isEmpty else { return }
        memory[snapshot.providerID] = snapshot
        lastAttempt.removeValue(forKey: snapshot.providerID)
        persist(snapshot)
    }

    private func loadDiskCacheIfNeeded() {
        guard !didLoadDiskCache else { return }
        didLoadDiskCache = true

        for providerID in AgentUsageProviderID.allCases where providerID != .summary {
            let url = cacheURL(for: providerID)
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(ProviderQuotaSnapshot.self, from: data),
                  snapshot.providerID == providerID,
                  !snapshot.isEmpty else {
                continue
            }
            memory[providerID] = snapshot
        }
    }

    private func persist(_ snapshot: ProviderQuotaSnapshot) {
        do {
            try fileManager.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: cacheURL(for: snapshot.providerID), options: .atomic)
        } catch {
            // Cache persistence is best-effort; the fresh in-memory value remains.
        }
    }

    private func cacheURL(for providerID: AgentUsageProviderID) -> URL {
        cacheDirectory.appendingPathComponent("\(providerID.rawValue).json")
    }
}
