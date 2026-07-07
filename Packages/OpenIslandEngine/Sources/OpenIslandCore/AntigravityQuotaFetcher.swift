import CryptoKit
import Foundation

public struct AntigravityOAuthCredentials: Equatable, Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var projectID: String
    public var email: String?

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        projectID: String = "",
        email: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.projectID = projectID
        self.email = email
    }
}

public protocol AntigravityCredentialStoring: Sendable {
    func loadCredentials() async throws -> AntigravityOAuthCredentials?
    func saveCredentials(_ credentials: AntigravityOAuthCredentials) async throws
    func deleteCredentials() async throws
}

public struct AntigravityOAuthRequest: Equatable, Sendable {
    public var authorizationURL: URL
    public var state: String
    public var codeVerifier: String

    public init(authorizationURL: URL, state: String, codeVerifier: String) {
        self.authorizationURL = authorizationURL
        self.state = state
        self.codeVerifier = codeVerifier
    }
}

public enum AntigravityOAuth {
    public static let clientID = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    public static let clientSecret = "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"
    public static let redirectURI = "http://localhost:51121/oauth-callback"
    public static let scopes = [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "https://www.googleapis.com/auth/cclog",
        "https://www.googleapis.com/auth/experimentsandconfigs",
    ]

    public static func makeAuthorizationRequest() throws -> AntigravityOAuthRequest {
        let verifier = randomBase64URL(byteCount: 32)
        let state = randomBase64URL(byteCount: 24)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        guard let url = components?.url else {
            throw AntigravityQuotaError.invalidOAuthRequest
        }
        return AntigravityOAuthRequest(
            authorizationURL: url,
            state: state,
            codeVerifier: verifier
        )
    }

    public static func exchangeAuthorizationCode(
        _ code: String,
        codeVerifier: String,
        session: URLSession = .shared,
        now: Date = .now
    ) async throws -> AntigravityOAuthCredentials {
        let payload: TokenResponse = try await formRequest(
            to: URL(string: "https://oauth2.googleapis.com/token")!,
            values: [
                "client_id": clientID,
                "client_secret": clientSecret,
                "code": code,
                "grant_type": "authorization_code",
                "redirect_uri": redirectURI,
                "code_verifier": codeVerifier,
            ],
            session: session
        )
        guard let refreshToken = payload.refreshToken, !refreshToken.isEmpty else {
            throw AntigravityQuotaError.missingRefreshToken
        }

        async let email = fetchEmail(accessToken: payload.accessToken, session: session)
        async let projectID = AntigravityQuotaFetcher.resolveProjectID(
            accessToken: payload.accessToken,
            session: session
        )
        return await AntigravityOAuthCredentials(
            accessToken: payload.accessToken,
            refreshToken: refreshToken,
            expiresAt: now.addingTimeInterval(TimeInterval(payload.expiresIn)),
            projectID: (try? projectID) ?? "",
            email: try? email
        )
    }

    fileprivate static func refresh(
        _ credentials: AntigravityOAuthCredentials,
        session: URLSession,
        now: Date
    ) async throws -> AntigravityOAuthCredentials {
        let payload: TokenResponse = try await formRequest(
            to: URL(string: "https://oauth2.googleapis.com/token")!,
            values: [
                "grant_type": "refresh_token",
                "refresh_token": credentials.refreshToken,
                "client_id": clientID,
                "client_secret": clientSecret,
            ],
            session: session
        )
        var refreshed = credentials
        refreshed.accessToken = payload.accessToken
        refreshed.refreshToken = payload.refreshToken ?? credentials.refreshToken
        refreshed.expiresAt = now.addingTimeInterval(TimeInterval(payload.expiresIn))
        return refreshed
    }

    private static func fetchEmail(accessToken: String, session: URLSession) async throws -> String? {
        var request = URLRequest(
            url: URL(string: "https://www.googleapis.com/oauth2/v1/userinfo?alt=json")!
        )
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(UserInfoResponse.self, from: data).email
    }

    private static func formRequest<Response: Decodable>(
        to url: URL,
        values: [String: String],
        session: URLSession
    ) async throws -> Response {
        var components = URLComponents()
        components.queryItems = values.map(URLQueryItem.init(name:value:))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded;charset=UTF-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func randomBase64URL(byteCount: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
            .base64URLEncodedString()
    }

    fileprivate static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AntigravityQuotaError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(300)
            throw AntigravityQuotaError.httpError(
                status: http.statusCode,
                message: body.map(String.init) ?? ""
            )
        }
    }

    private struct TokenResponse: Decodable {
        var accessToken: String
        var expiresIn: Int
        var refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }

    private struct UserInfoResponse: Decodable {
        var email: String?
    }
}

public struct AntigravityQuotaFetcher: ProviderQuotaFetching {
    public let providerID: AgentUsageProviderID = .antigravity

    private static let productionEndpoint = URL(string: "https://cloudcode-pa.googleapis.com")!
    private static let projectFallbackEndpoints = [
        productionEndpoint,
        URL(string: "https://daily-cloudcode-pa.sandbox.googleapis.com")!,
        URL(string: "https://autopush-cloudcode-pa.sandbox.googleapis.com")!,
    ]
    private static let fallbackProjectID = "rising-fact-p41fc"

    private let credentialStore: any AntigravityCredentialStoring
    private let session: URLSession
    private let now: @Sendable () -> Date

    public init(
        credentialStore: any AntigravityCredentialStoring,
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.credentialStore = credentialStore
        self.session = session
        self.now = now
    }

    public func fetchQuota() async throws -> ProviderQuotaSnapshot? {
        guard var credentials = try await credentialStore.loadCredentials() else {
            return nil
        }

        let fetchedAt = now()
        if credentials.expiresAt.timeIntervalSince(fetchedAt) < 60 {
            credentials = try await AntigravityOAuth.refresh(
                credentials,
                session: session,
                now: fetchedAt
            )
            try await credentialStore.saveCredentials(credentials)
        }

        if credentials.projectID.isEmpty,
           let resolvedProjectID = try? await Self.resolveProjectID(
               accessToken: credentials.accessToken,
               session: session
           ),
           !resolvedProjectID.isEmpty {
            credentials.projectID = resolvedProjectID
            try await credentialStore.saveCredentials(credentials)
        }

        let projectID = credentials.projectID.isEmpty ? Self.fallbackProjectID : credentials.projectID

        if let summary = try? await requestQuotaSummary(
            accessToken: credentials.accessToken,
            projectID: projectID,
            fetchedAt: fetchedAt
        ) {
            return summary
        }

        let data = try await postQuotaRequest(
            path: "v1internal:fetchAvailableModels",
            accessToken: credentials.accessToken,
            projectID: projectID
        )
        return try Self.quotaSnapshot(from: data, fetchedAt: fetchedAt)
    }

    private func requestQuotaSummary(
        accessToken: String,
        projectID: String,
        fetchedAt: Date
    ) async throws -> ProviderQuotaSnapshot? {
        let data = try await postQuotaRequest(
            path: "v1internal:retrieveUserQuotaSummary",
            accessToken: accessToken,
            projectID: projectID
        )
        return try Self.summaryQuotaSnapshot(from: data, fetchedAt: fetchedAt)
    }

    private func postQuotaRequest(
        path: String,
        accessToken: String,
        projectID: String
    ) async throws -> Data {
        var request = URLRequest(url: Self.productionEndpoint.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.clientMetadata, forHTTPHeaderField: "Client-Metadata")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["project": projectID])

        let (data, response) = try await session.data(for: request)
        try AntigravityOAuth.validate(response: response, data: data)
        return data
    }

    fileprivate static func resolveProjectID(
        accessToken: String,
        session: URLSession
    ) async throws -> String {
        var lastError: Error?
        for endpoint in projectFallbackEndpoints {
            do {
                var request = URLRequest(
                    url: endpoint.appendingPathComponent("v1internal:loadCodeAssist")
                )
                request.httpMethod = "POST"
                request.timeoutInterval = 10
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("google-api-nodejs-client/9.15.1", forHTTPHeaderField: "User-Agent")
                request.setValue(clientMetadata, forHTTPHeaderField: "Client-Metadata")
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "metadata": [
                        "ideType": "ANTIGRAVITY",
                        "platform": "MACOS",
                        "pluginType": "GEMINI",
                    ],
                ])
                let (data, response) = try await session.data(for: request)
                try AntigravityOAuth.validate(response: response, data: data)
                let payload = try JSONDecoder().decode(LoadCodeAssistResponse.self, from: data)
                if let projectID = payload.projectID, !projectID.isEmpty {
                    return projectID
                }
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        throw AntigravityQuotaError.missingProjectID
    }

    static func quotaSnapshot(
        from data: Data,
        fetchedAt: Date
    ) throws -> ProviderQuotaSnapshot? {
        let response = try JSONDecoder().decode(AvailableModelsResponse.self, from: data)
        var groups: [QuotaGroup: QuotaAccumulator] = [:]

        for (modelID, model) in response.models {
            guard let group = quotaGroup(modelID: modelID, model: model),
                  let remaining = model.quotaInfo?.remainingFraction,
                  remaining.isFinite else {
                continue
            }
            let normalizedRemaining = min(max(remaining, 0), 1)
            let reset = model.quotaInfo?.resetTime.flatMap(parseISO8601Date)
            if var existing = groups[group] {
                existing.remainingFraction = min(existing.remainingFraction, normalizedRemaining)
                existing.resetsAt = earliest(existing.resetsAt, reset)
                groups[group] = existing
            } else {
                groups[group] = QuotaAccumulator(
                    remainingFraction: normalizedRemaining,
                    resetsAt: reset
                )
            }
        }

        let windows = QuotaGroup.allCases.compactMap { group -> ProviderQuotaWindow? in
            guard let value = groups[group] else { return nil }
            return ProviderQuotaWindow(
                key: group.rawValue,
                label: group.label,
                usedPercentage: (1 - value.remainingFraction) * 100,
                resetsAt: value.resetsAt
            )
        }
        guard !windows.isEmpty else { return nil }
        return ProviderQuotaSnapshot(
            providerID: .antigravity,
            windows: windows,
            fetchedAt: fetchedAt
        )
    }

    static func summaryQuotaSnapshot(
        from data: Data,
        fetchedAt: Date
    ) throws -> ProviderQuotaSnapshot? {
        let response = try JSONDecoder().decode(QuotaSummaryResponse.self, from: data)
        var windows: [ProviderQuotaWindow] = []

        for group in response.groups {
            guard let groupLabel = summaryGroupLabel(group.displayName) else { continue }
            for bucket in group.buckets {
                guard let remaining = bucket.remainingFraction, remaining.isFinite else { continue }
                let normalizedRemaining = min(max(remaining, 0), 1)
                let windowLabel = summaryWindowLabel(bucket.window, displayName: bucket.displayName)
                windows.append(
                    ProviderQuotaWindow(
                        key: bucket.bucketId,
                        label: "\(groupLabel) \(windowLabel)",
                        usedPercentage: (1 - normalizedRemaining) * 100,
                        resetsAt: bucket.resetTime.flatMap(parseISO8601Date)
                    )
                )
            }
        }

        guard !windows.isEmpty else { return nil }
        return ProviderQuotaSnapshot(
            providerID: .antigravity,
            windows: windows,
            fetchedAt: fetchedAt
        )
    }

    private static func quotaGroup(
        modelID: String,
        model: AvailableModel
    ) -> QuotaGroup? {
        let combined = "\(modelID) \(model.modelName ?? "") \(model.displayName ?? "")".lowercased()
        if combined.contains("claude") {
            return .claude
        }
        guard combined.contains("gemini-3") || combined.contains("gemini 3") else {
            return nil
        }
        return combined.contains("flash") ? .geminiFlash : .geminiPro
    }

    private static func parseISO8601Date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func summaryGroupLabel(_ displayName: String) -> String? {
        let lowercased = displayName.lowercased()
        if lowercased.contains("gemini") {
            return "Gemini"
        }
        if lowercased.contains("claude") || lowercased.contains("gpt") {
            return "Claude/GPT"
        }
        return nil
    }

    private static func summaryWindowLabel(_ window: String?, displayName: String) -> String {
        switch window?.lowercased() {
        case "5h": return "5h"
        case "weekly": return "7d"
        default:
            let lowercased = displayName.lowercased()
            if lowercased.contains("five") || lowercased.contains("5") {
                return "5h"
            }
            if lowercased.contains("week") {
                return "7d"
            }
            return displayName
        }
    }

    private static func earliest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): min(lhs, rhs)
        case let (lhs?, nil): lhs
        case let (nil, rhs?): rhs
        case (nil, nil): nil
        }
    }

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/537.36 (KHTML, like Gecko) Antigravity/1.18.3 "
        + "Chrome/138.0.7204.235 Electron/37.3.1 Safari/537.36"
    private static let clientMetadata =
        #"{"ideType":"ANTIGRAVITY","platform":"MACOS","pluginType":"GEMINI"}"#

    private enum QuotaGroup: String, CaseIterable {
        case claude
        case geminiPro = "gemini-pro"
        case geminiFlash = "gemini-flash"

        var label: String {
            switch self {
            case .claude: "Claude"
            case .geminiPro: "Gemini Pro"
            case .geminiFlash: "Gemini Flash"
            }
        }
    }

    private struct QuotaAccumulator {
        var remainingFraction: Double
        var resetsAt: Date?
    }

    private struct AvailableModelsResponse: Decodable {
        var models: [String: AvailableModel]
    }

    private struct AvailableModel: Decodable {
        var quotaInfo: QuotaInfo?
        var displayName: String?
        var modelName: String?
    }

    private struct QuotaSummaryResponse: Decodable {
        var groups: [QuotaSummaryGroup]
    }

    private struct QuotaSummaryGroup: Decodable {
        var buckets: [QuotaSummaryBucket]
        var displayName: String
    }

    private struct QuotaSummaryBucket: Decodable {
        var bucketId: String
        var displayName: String
        var window: String?
        var resetTime: String?
        var remainingFraction: Double?
    }

    private struct QuotaInfo: Decodable {
        var remainingFraction: Double?
        var resetTime: String?
    }

    private struct LoadCodeAssistResponse: Decodable {
        var cloudaicompanionProject: ProjectValue?

        var projectID: String? {
            switch cloudaicompanionProject {
            case let .string(value): value
            case let .object(value): value.id
            case nil: nil
            }
        }
    }

    private enum ProjectValue: Decodable {
        case string(String)
        case object(ProjectObject)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
            } else {
                self = .object(try container.decode(ProjectObject.self))
            }
        }
    }

    private struct ProjectObject: Decodable {
        var id: String?
    }
}

public enum AntigravityQuotaError: LocalizedError {
    case invalidOAuthRequest
    case invalidResponse
    case httpError(status: Int, message: String)
    case missingRefreshToken
    case missingProjectID

    public var errorDescription: String? {
        switch self {
        case .invalidOAuthRequest:
            "Could not create the Google authorization request."
        case .invalidResponse:
            "Google returned an invalid response."
        case let .httpError(status, message):
            message.isEmpty
                ? "Google request failed with HTTP \(status)."
                : "Google request failed with HTTP \(status): \(message)"
        case .missingRefreshToken:
            "Google did not return a refresh token. Please authorize again."
        case .missingProjectID:
            "Google did not return an Antigravity project."
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
