import AppKit
import Foundation
import Network
import OpenIslandCore
import Security

actor AntigravityKeychainCredentialStore: AntigravityCredentialStoring {
    static let shared = AntigravityKeychainCredentialStore()

    private let service = "com.zaaacqwq.VibeIsland.antigravity-oauth"
    private let account = "google-antigravity"

    func loadCredentials() throws -> AntigravityOAuthCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status)
        }
        return try JSONDecoder().decode(AntigravityOAuthCredentials.self, from: data)
    }

    func saveCredentials(_ credentials: AntigravityOAuthCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
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

    func deleteCredentials() throws {
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

        init(_ status: OSStatus) {
            self.status = status
        }

        var errorDescription: String? {
            let message = SecCopyErrorMessageString(status, nil) as String?
            return message.map { "Keychain: \($0)" } ?? "Keychain error \(status)."
        }
    }
}

@MainActor
final class AntigravityQuotaAuthManager: ObservableObject {
    static let shared = AntigravityQuotaAuthManager()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var isAuthorizing = false
    @Published private(set) var accountEmail: String?
    @Published private(set) var errorMessage: String?

    private let credentialStore = AntigravityKeychainCredentialStore.shared
    private var loginTask: Task<Void, Never>?

    private init() {
        Task { await reloadStatus() }
    }

    func signIn() {
        guard !isAuthorizing else { return }
        isAuthorizing = true
        errorMessage = nil

        loginTask = Task {
            defer { isAuthorizing = false }
            do {
                let request = try AntigravityOAuth.makeAuthorizationRequest()
                let code = try await AntigravityLoopbackOAuthServer.authorize(request)
                let credentials = try await AntigravityOAuth.exchangeAuthorizationCode(
                    code,
                    codeVerifier: request.codeVerifier
                )
                try await credentialStore.saveCredentials(credentials)
                await reloadStatus()
                AgentMonitorManager.shared.refreshProviderQuotas(force: true)
            } catch is CancellationError {
                // Closing settings or explicitly cancelling is not an auth error.
            } catch {
                errorMessage = error.localizedDescription
                await reloadStatus(preserveError: true)
            }
        }
    }

    func signOut() {
        loginTask?.cancel()
        loginTask = nil
        Task {
            do {
                try await credentialStore.deleteCredentials()
                await reloadStatus()
                AgentMonitorManager.shared.clearProviderQuota(.antigravity)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func reloadStatus(preserveError: Bool = false) async {
        do {
            let credentials = try await credentialStore.loadCredentials()
            isAuthenticated = credentials != nil
            accountEmail = credentials?.email
            if !preserveError {
                errorMessage = nil
            }
        } catch {
            isAuthenticated = false
            accountEmail = nil
            errorMessage = error.localizedDescription
        }
    }
}

private enum AntigravityLoopbackOAuthServer {
    static func authorize(_ request: AntigravityOAuthRequest) async throws -> String {
        let listener = try NWListener(using: .tcp, on: 51_121)
        let box = OAuthCallbackBox(listener: listener, expectedState: request.state)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                box.install(continuation)
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        Task { @MainActor in
                            guard NSWorkspace.shared.open(request.authorizationURL) else {
                                box.finish(.failure(OAuthCallbackError.couldNotOpenBrowser))
                                return
                            }
                        }
                    case let .failed(error):
                        box.finish(.failure(error))
                    case .cancelled:
                        box.finish(.failure(CancellationError()))
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { connection in
                    receiveCallback(on: connection, box: box)
                }
                listener.start(queue: DispatchQueue(label: "VibeIsland.AntigravityOAuth"))
            }
        } onCancel: {
            box.finish(.failure(CancellationError()))
        }
    }

    private static func receiveCallback(on connection: NWConnection, box: OAuthCallbackBox) {
        connection.start(queue: DispatchQueue(label: "VibeIsland.AntigravityOAuth.Connection"))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            data,
            _,
            _,
            error in
            if let error {
                connection.cancel()
                box.finish(.failure(error))
                return
            }
            guard let data,
                  let request = String(data: data, encoding: .utf8),
                  let firstLine = request.split(separator: "\r\n", maxSplits: 1).first,
                  firstLine.hasPrefix("GET "),
                  let target = firstLine.split(separator: " ").dropFirst().first,
                  let components = URLComponents(string: "http://localhost\(target)") else {
                sendResponse(
                    status: "400 Bad Request",
                    message: "Invalid OAuth callback.",
                    on: connection
                )
                box.finish(.failure(OAuthCallbackError.invalidCallback))
                return
            }

            let values = Dictionary(
                uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
            )
            if let oauthError = values["error"], !oauthError.isEmpty {
                sendResponse(
                    status: "400 Bad Request",
                    message: "Authorization was not completed. You can close this tab.",
                    on: connection
                )
                box.finish(.failure(OAuthCallbackError.authorizationDenied(oauthError)))
                return
            }
            guard components.path == "/oauth-callback",
                  values["state"] == box.expectedState,
                  let code = values["code"],
                  !code.isEmpty else {
                sendResponse(
                    status: "400 Bad Request",
                    message: "OAuth state validation failed.",
                    on: connection
                )
                box.finish(.failure(OAuthCallbackError.invalidState))
                return
            }

            sendResponse(
                status: "200 OK",
                message: "Antigravity is connected to VibeIsland. You can close this tab.",
                on: connection
            )
            box.finish(.success(code))
        }
    }

    private static func sendResponse(status: String, message: String, on connection: NWConnection) {
        let body = """
        <!doctype html><html><head><meta charset="utf-8"><title>VibeIsland</title></head>
        <body style="font:16px -apple-system;padding:40px;background:#111;color:#eee">
        <h2>VibeIsland</h2><p>\(message)</p></body></html>
        """
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private final class OAuthCallbackBox: @unchecked Sendable {
        let expectedState: String

        private let lock = NSLock()
        private let listener: NWListener
        private var continuation: CheckedContinuation<String, Error>?
        private var result: Result<String, Error>?

        init(listener: NWListener, expectedState: String) {
            self.listener = listener
            self.expectedState = expectedState
        }

        func install(_ continuation: CheckedContinuation<String, Error>) {
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }

        func finish(_ result: Result<String, Error>) {
            lock.lock()
            guard self.result == nil else {
                lock.unlock()
                return
            }
            self.result = result
            let continuation = continuation
            self.continuation = nil
            lock.unlock()

            listener.cancel()
            continuation?.resume(with: result)
        }
    }

    private enum OAuthCallbackError: LocalizedError {
        case couldNotOpenBrowser
        case invalidCallback
        case invalidState
        case authorizationDenied(String)

        var errorDescription: String? {
            switch self {
            case .couldNotOpenBrowser:
                "Could not open the Google authorization page."
            case .invalidCallback:
                "Google returned an invalid authorization callback."
            case .invalidState:
                "Google authorization state validation failed."
            case let .authorizationDenied(reason):
                "Google authorization was not completed: \(reason)"
            }
        }
    }
}
