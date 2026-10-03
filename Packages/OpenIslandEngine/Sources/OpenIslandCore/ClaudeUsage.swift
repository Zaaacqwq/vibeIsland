import Foundation

public struct ClaudeUsageWindow: Equatable, Codable, Sendable {
    public var usedPercentage: Double
    public var resetsAt: Date?

    public init(usedPercentage: Double, resetsAt: Date?) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }

    public var roundedUsedPercentage: Int {
        Int(usedPercentage.rounded())
    }

    /// Stand-in for a window the status line did not report. No `resetsAt`,
    /// because a window we never saw has no reset time to claim.
    public static let unused = ClaudeUsageWindow(usedPercentage: 0, resetsAt: nil)
}

public struct ClaudeUsageSnapshot: Equatable, Codable, Sendable {
    public var fiveHour: ClaudeUsageWindow?
    public var sevenDay: ClaudeUsageWindow?
    public var cachedAt: Date?

    public init(
        fiveHour: ClaudeUsageWindow?,
        sevenDay: ClaudeUsageWindow?,
        cachedAt: Date? = nil
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.cachedAt = cachedAt
    }

    public var isEmpty: Bool {
        fiveHour == nil && sevenDay == nil
    }

    // Claude Code drops a window from `rate_limits` while it carries no usage —
    // typically right after the 5h window rolls over. Rendering only the windows
    // that happen to be present made the badge vanish, which reads identically to
    // "the status line is broken". Once a snapshot exists at all the account
    // demonstrably has both windows, so a missing one is 0%, not unknown.
    // Callers must still skip an absent snapshot (see `isEmpty`) rather than
    // inventing a 0%/0% pair for accounts that report no quota at all.

    public var displayFiveHour: ClaudeUsageWindow { fiveHour ?? .unused }

    public var displaySevenDay: ClaudeUsageWindow { sevenDay ?? .unused }
}

public enum ClaudeUsageLoader {
    public static let defaultCacheURL = URL(fileURLWithPath: "/tmp/open-island-rl.json")
    public static let legacyCacheURL = URL(fileURLWithPath: "/tmp/vibe-island-rl.json")

    public static func load() throws -> ClaudeUsageSnapshot? {
        try load(from: [defaultCacheURL, legacyCacheURL])
    }

    public static func load(from url: URL) throws -> ClaudeUsageSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else {
            return nil
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let cachedAt = attributes?[.modificationDate] as? Date
        let snapshot = ClaudeUsageSnapshot(
            fiveHour: usageWindow(for: "five_hour", in: payload),
            sevenDay: usageWindow(for: "seven_day", in: payload),
            cachedAt: cachedAt
        )

        return snapshot.isEmpty ? nil : snapshot
    }

    public static func load(from urls: [URL]) throws -> ClaudeUsageSnapshot? {
        let candidates = urls
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { url in
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let modificationDate = attributes?[.modificationDate] as? Date ?? .distantPast
                return (url, modificationDate)
            }
            .sorted { lhs, rhs in
                lhs.1 > rhs.1
            }

        for (url, _) in candidates {
            if let snapshot = try load(from: url) {
                return snapshot
            }
        }

        return nil
    }

    private static func usageWindow(for key: String, in payload: [String: Any]) -> ClaudeUsageWindow? {
        guard let window = payload[key] as? [String: Any],
              let rawPercentage = number(from: window["used_percentage"]) ?? number(from: window["utilization"]) else {
            return nil
        }

        return ClaudeUsageWindow(
            usedPercentage: rawPercentage,
            resetsAt: resetDate(in: window)
        )
    }

    private static func resetDate(in window: [String: Any]) -> Date? {
        let absoluteKeys = ["resets_at", "reset_at", "resetsAt", "resetAt"]
        for key in absoluteKeys {
            if let date = date(from: window[key]) {
                return date
            }
        }

        let relativeKeys = ["resets_in_seconds", "reset_after_seconds", "resetsInSeconds", "resetAfterSeconds"]
        for key in relativeKeys {
            if let seconds = number(from: window[key]) {
                return Date().addingTimeInterval(seconds)
            }
        }

        return nil
    }

    private static func number(from value: Any?) -> Double? {
        switch value {
        case let value as NSNumber:
            value.doubleValue
        case let value as String:
            Double(value)
        default:
            nil
        }
    }

    private static func date(from value: Any?) -> Date? {
        switch value {
        case let value as NSNumber:
            return Date(timeIntervalSince1970: value.doubleValue)
        case let value as String:
            if let seconds = Double(value) {
                return Date(timeIntervalSince1970: seconds)
            }
            let formatterWithFractionalSeconds = ISO8601DateFormatter()
            formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatterWithFractionalSeconds.date(from: value) {
                return date
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) {
                return date
            }
            return nil
        default:
            return nil
        }
    }
}
