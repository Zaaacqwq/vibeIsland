import Foundation
import OpenIslandCore
import Security
import os

/// Stores the pasted Cursor `WorkosCursorSessionToken` in the macOS Keychain.
/// The token is a bearer-equivalent session credential, so it never touches
/// `UserDefaults` or disk in the clear (see `~/.claude/rules/swift/security.md`).
actor CursorTokenKeychainStore {
    static let shared = CursorTokenKeychainStore()

    private let service = "com.zaaacqwq.VibeIsland.cursor-session"
    private let account = "cursor-workos-session-token"

    func loadToken() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw KeychainError(status)
        }
        return token.isEmpty ? nil : token
    }

    func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError(updateStatus)
        }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError(addStatus)
        }
    }

    func deleteToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus
        init(_ status: OSStatus) { self.status = status }
        var errorDescription: String? {
            let message = SecCopyErrorMessageString(status, nil) as String?
            return message.map { "Keychain: \($0)" } ?? "Keychain error \(status)."
        }
    }
}

/// Drives Cursor usage: validates a pasted session token, downloads the
/// usage-export CSV, and writes it to the shared cache that
/// `CursorTokenAggregator` reads. Cursor has no local token store and no clean
/// rate-limit window, so this powers a token/cost card only (no quota ring).
@MainActor
final class CursorUsageSyncManager: ObservableObject {
    static let shared = CursorUsageSyncManager()

    @Published private(set) var isConnected = false
    @Published private(set) var isSyncing = false
    @Published private(set) var membershipType: String?
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var errorMessage: String?

    private let keychain = CursorTokenKeychainStore.shared
    private let client = CursorUsageClient()
    private let cacheURL = CursorTokenAggregator.defaultCacheURL
    private var backgroundLoopTask: Task<Void, Never>?
    private let logger = os.Logger(
        subsystem: "com.zaaacqwq.VibeIsland",
        category: "CursorUsage"
    )

    /// Cursor usage moves slowly and the export is unofficial; refresh only
    /// every 30 minutes in the background.
    private static let backgroundRefreshInterval: TimeInterval = 30 * 60

    private init() {
        Task { await reloadStatus() }
    }

    /// Connects a pasted `WorkosCursorSessionToken`: validates it, persists it to
    /// the Keychain, then performs the first sync.
    func connect(token rawToken: String) {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            errorMessage = "Paste your Cursor session token first."
            return
        }
        Task { _ = await signIn(withToken: token) }
    }

    /// Shared connect path for both the pasted token and the in-app login window.
    /// Returns whether the token validated (so the login window can close on
    /// success and stay open with an error otherwise).
    @discardableResult
    func signIn(withToken rawToken: String) async -> Bool {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            errorMessage = "Cursor session token was empty."
            return false
        }
        guard !isSyncing else { return false }
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            let info = try await client.validateSession(token: token)
            try await keychain.saveToken(token)
            membershipType = info.membershipType
            isConnected = true
            try await syncNow(token: token)
            return true
        } catch {
            logger.error("connect failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return false
        }
    }

    func disconnect() {
        backgroundLoopTask?.cancel()
        backgroundLoopTask = nil
        Task {
            try? await keychain.deleteToken()
            try? FileManager.default.removeItem(at: cacheURL)
            isConnected = false
            membershipType = nil
            lastSyncedAt = nil
            errorMessage = nil
            AgentMonitorManager.shared.refreshTokenUsage(force: true, refreshQuotas: false)
        }
    }

    /// Manual "Sync" button and background loop entry point. No-op when no token
    /// is stored.
    func sync() {
        guard !isSyncing else { return }
        isSyncing = true
        errorMessage = nil
        Task {
            defer { isSyncing = false }
            do {
                guard let token = try await keychain.loadToken() else {
                    isConnected = false
                    return
                }
                try await syncNow(token: token)
            } catch let error as CursorUsageError where isUnauthorized(error) {
                // Keep the token so the user can retry, but surface the prompt.
                errorMessage = error.localizedDescription
            } catch {
                logger.error("sync failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    func startBackgroundRefresh() {
        guard backgroundLoopTask == nil else { return }
        backgroundLoopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.isConnected { self.sync() }
                try? await Task.sleep(for: .seconds(Int(Self.backgroundRefreshInterval)))
            }
        }
    }

    func reloadStatus() async {
        do {
            let token = try await keychain.loadToken()
            isConnected = token != nil
        } catch {
            isConnected = false
            errorMessage = error.localizedDescription
        }
    }

    /// Downloads the CSV and writes it to the aggregator's cache, then refreshes
    /// the usage summary so the new numbers appear immediately.
    private func syncNow(token: String) async throws {
        let csv = try await client.fetchUsageCSV(token: token)
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try csv.write(to: cacheURL, atomically: true, encoding: .utf8)
        lastSyncedAt = Date()
        // Only recompute token totals; Cursor has no quota ring, so don't wake
        // every provider's quota fetcher (which would spin OpenCode's web view).
        AgentMonitorManager.shared.refreshTokenUsage(force: true, refreshQuotas: false)
    }

    private func isUnauthorized(_ error: CursorUsageError) -> Bool {
        if case .unauthorized = error { return true }
        return false
    }
}
