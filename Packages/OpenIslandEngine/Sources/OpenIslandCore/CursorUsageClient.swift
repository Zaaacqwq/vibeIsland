import Foundation

/// Result of validating a Cursor session token against the account summary
/// endpoint.
public struct CursorSessionInfo: Equatable, Sendable {
    public var membershipType: String?

    public init(membershipType: String?) {
        self.membershipType = membershipType
    }
}

/// Talks to Cursor's unofficial dashboard endpoints using a pasted
/// `WorkosCursorSessionToken`. Cursor exposes no local token store, so the CSV
/// export is the only usage source; this client downloads it (for the token
/// aggregator's cache) and validates the token via the usage-summary endpoint.
///
/// These are undocumented, cookie-authenticated endpoints and may change without
/// notice — every call has a short timeout and surfaces auth failures explicitly
/// so the UI can prompt the user to repaste their token.
public struct CursorUsageClient: Sendable {
    public static let usageCSVEndpoint = URL(
        string: "https://cursor.com/api/dashboard/export-usage-events-csv?strategy=tokens"
    )!
    public static let usageSummaryEndpoint = URL(
        string: "https://cursor.com/api/usage-summary"
    )!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Downloads the raw usage-export CSV. Throws `CursorUsageError.unauthorized`
    /// when the session token is expired/invalid so the caller can re-prompt.
    public func fetchUsageCSV(token: String) async throws -> String {
        let (data, response) = try await session.data(for: request(url: Self.usageCSVEndpoint, token: token))
        try Self.validate(response: response)
        guard let text = String(data: data, encoding: .utf8), text.hasPrefix("Date,") else {
            throw CursorUsageError.invalidResponse
        }
        return text
    }

    /// Confirms the token is accepted and returns the account's membership type.
    /// A valid summary always carries a billing cycle; its absence means the
    /// token was rejected or the response shape changed.
    @discardableResult
    public func validateSession(token: String) async throws -> CursorSessionInfo {
        let (data, response) = try await session.data(for: request(url: Self.usageSummaryEndpoint, token: token))
        try Self.validate(response: response)
        let summary = try JSONDecoder().decode(UsageSummaryResponse.self, from: data)
        guard summary.billingCycleStart != nil, summary.billingCycleEnd != nil else {
            throw CursorUsageError.invalidResponse
        }
        return CursorSessionInfo(membershipType: summary.membershipType)
    }

    private func request(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("WorkosCursorSessionToken=\(token)", forHTTPHeaderField: "Cookie")
        request.setValue("https://www.cursor.com/settings", forHTTPHeaderField: "Referer")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CursorUsageError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw CursorUsageError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CursorUsageError.httpError(status: http.statusCode)
        }
    }

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private struct UsageSummaryResponse: Decodable {
        var membershipType: String?
        var billingCycleStart: String?
        var billingCycleEnd: String?
    }
}

public enum CursorUsageError: LocalizedError {
    case unauthorized
    case invalidResponse
    case httpError(status: Int)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Cursor session expired or invalid. Paste a fresh session token."
        case .invalidResponse:
            "Cursor returned an unexpected response."
        case let .httpError(status):
            "Cursor request failed with HTTP \(status)."
        }
    }
}
