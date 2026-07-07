import Foundation

public enum OpenCodeQuotaParser {
    public static func parse(
        pageSource: String,
        fetchedAt: Date = .now
    ) -> ProviderQuotaSnapshot? {
        var values: [Window: Usage] = [:]

        for window in Window.allCases {
            if let usage = parseSSRWindow(window, source: pageSource) {
                values[window] = usage
            }
        }

        if values.isEmpty {
            values = parseDataSlotWindows(pageSource)
        }

        if values.count < Window.allCases.count {
            let separatedValues = parseSeparatedVisibleText(pageSource)
            for (window, usage) in separatedValues {
                values[window] = usage
            }
        }

        if values.isEmpty {
            values = parseVisibleText(pageSource)
        }

        let windows = Window.allCases.compactMap { window -> ProviderQuotaWindow? in
            guard let usage = values[window] else { return nil }
            return ProviderQuotaWindow(
                key: window.rawValue,
                label: window.label,
                usedPercentage: usage.usedPercentage,
                resetsAt: fetchedAt.addingTimeInterval(max(0, usage.resetSeconds))
            )
        }
        guard !windows.isEmpty else { return nil }
        return ProviderQuotaSnapshot(
            providerID: .opencode,
            windows: windows,
            fetchedAt: fetchedAt
        )
    }

    private static func parseSSRWindow(_ window: Window, source: String) -> Usage? {
        let number = #"(-?\d+(?:\.\d+)?)"#
        let prefix = NSRegularExpression.escapedPattern(for: "\(window.rawValue)Usage")
            + #":\$R\[\d+\]=\{[^}]*"#
        let percentageFirst = prefix
            + "usagePercent:\(number)[^}]*resetInSec:\(number)[^}]*\\}"
        if let captures = captures(percentageFirst, in: source),
           let used = Double(captures[0]),
           let reset = Double(captures[1]) {
            return Usage(usedPercentage: used, resetSeconds: reset)
        }

        let resetFirst = prefix
            + "resetInSec:\(number)[^}]*usagePercent:\(number)[^}]*\\}"
        if let captures = captures(resetFirst, in: source),
           let reset = Double(captures[0]),
           let used = Double(captures[1]) {
            return Usage(usedPercentage: used, resetSeconds: reset)
        }
        return nil
    }

    private static func parseDataSlotWindows(_ source: String) -> [Window: Usage] {
        var result: [Window: Usage] = [:]
        let chunks = source.components(separatedBy: #"data-slot="usage-item""#).dropFirst()

        for chunk in chunks {
            guard let label = firstCapture(
                #"data-slot="usage-label"[^>]*>([\s\S]*?)<"#,
                in: chunk
            ),
            let window = Window(label: stripMarkup(label)),
            let usedText = firstCapture(
                #"data-slot="usage-value"[^>]*>[^0-9-]*(-?\d+(?:\.\d+)?)"#,
                in: chunk
            ),
            let used = Double(usedText) else {
                continue
            }

            let resetNow = chunk.range(
                of: #"data-slot="reset-now""#,
                options: .regularExpression
            ) != nil
            let resetText = firstCapture(
                #"data-slot="(?:reset-time|reset-now)"[^>]*>([\s\S]*?)</span>"#,
                in: chunk
            )
            guard resetNow || resetText != nil,
                  let reset = resetNow ? 0 : parseDuration(stripMarkup(resetText ?? "")) else {
                continue
            }
            result[window] = Usage(usedPercentage: used, resetSeconds: reset)
        }
        return result
    }

    private static func parseVisibleText(_ source: String) -> [Window: Usage] {
        let text = stripMarkup(source)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        var result: [Window: Usage] = [:]

        for window in Window.allCases {
            let name = window.visibleName
            let pattern =
                #"(?i)"#
                + name
                + #"\s+Usage\s+(-?\d+(?:\.\d+)?)\s*%\s+Resets?\s+(?:in\s+)?"#
                + #"((?:\d+(?:\.\d+)?\s*(?:days?|d|hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\s*)+|now)"#
            guard let match = captures(pattern, in: text),
                  let used = Double(match[0]),
                  let reset = parseDuration(match[1]) else {
                continue
            }
            result[window] = Usage(usedPercentage: used, resetSeconds: reset)
        }
        return result
    }

    private static func parseSeparatedVisibleText(_ source: String) -> [Window: Usage] {
        let text = stripMarkup(source)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        var result: [Window: Usage] = [:]

        for window in Window.allCases {
            let name = window.visibleName
            let pattern = #"(?i)"# + name + #"\s+Usage\s+(-?\d+(?:\.\d+)?)\s*%"#
            guard let match = captures(pattern, in: text),
                  let used = Double(match[0]) else {
                continue
            }
            result[window] = Usage(usedPercentage: used, resetSeconds: 0)
        }
        guard !result.isEmpty else { return [:] }

        let resetMatches = allCaptures(
            #"(?i)Resets?\s+(?:in\s+)?((?:\d+(?:\.\d+)?\s*(?:days?|d|hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\s*)+|now)"#,
            in: text
        )
        for (index, window) in Window.allCases.enumerated() {
            guard result[window] != nil,
                  resetMatches.indices.contains(index),
                  let reset = parseDuration(resetMatches[index][0]) else {
                continue
            }
            result[window]?.resetSeconds = reset
        }
        return result
    }

    private static func parseDuration(_ input: String) -> TimeInterval? {
        let normalized = input
            .lowercased()
            .replacingOccurrences(of: "resets", with: "")
            .replacingOccurrences(of: "reset", with: "")
            .replacingOccurrences(of: "in", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized == "now" || normalized.isEmpty {
            return normalized == "now" ? 0 : nil
        }

        let pattern =
            #"(\d+(?:\.\d+)?)\s*(days?|d|hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(normalized.startIndex..., in: normalized)
        let matches = regex.matches(in: normalized, range: range)
        guard !matches.isEmpty else { return nil }

        return matches.reduce(0) { total, match in
            guard let valueRange = Range(match.range(at: 1), in: normalized),
                  let unitRange = Range(match.range(at: 2), in: normalized),
                  let value = Double(normalized[valueRange]) else {
                return total
            }
            let unit = normalized[unitRange]
            let multiplier: TimeInterval
            if unit.hasPrefix("d") {
                multiplier = 86_400
            } else if unit.hasPrefix("h") {
                multiplier = 3_600
            } else if unit.hasPrefix("m") {
                multiplier = 60
            } else {
                multiplier = 1
            }
            return total + value * multiplier
        }
    }

    private static func stripMarkup(_ input: String) -> String {
        input
            .replacingOccurrences(of: #"<!--.*?-->"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstCapture(_ pattern: String, in source: String) -> String? {
        captures(pattern, in: source)?.first
    }

    private static func captures(_ pattern: String, in source: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(
                  in: source,
                  range: NSRange(source.startIndex..., in: source)
              ) else {
            return nil
        }

        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: source) else { return nil }
            return String(source[range])
        }
    }

    private static func allCaptures(_ pattern: String, in source: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: source) else { return nil }
                return String(source[range])
            }
        }
    }

    private struct Usage {
        var usedPercentage: Double
        var resetSeconds: TimeInterval
    }

    private enum Window: String, CaseIterable {
        case rolling
        case weekly
        case monthly

        init?(label: String) {
            let normalized = label.lowercased()
            if normalized.contains("rolling") {
                self = .rolling
            } else if normalized.contains("weekly") {
                self = .weekly
            } else if normalized.contains("monthly") {
                self = .monthly
            } else {
                return nil
            }
        }

        var visibleName: String {
            switch self {
            case .rolling: "Rolling"
            case .weekly: "Weekly"
            case .monthly: "Monthly"
            }
        }

        var label: String {
            switch self {
            case .rolling: "5h"
            case .weekly: "7d"
            case .monthly: "30d"
            }
        }
    }
}
