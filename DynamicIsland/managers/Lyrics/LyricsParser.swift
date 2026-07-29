/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation

enum LyricsParser {
    static func lookupResult(from rawLyrics: String) -> LyricsLookupResult {
        let trimmed = rawLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isNoLyricsPlaceholder(trimmed) else {
            return .none
        }

        let lines = parseLRC(trimmed)
        if !lines.isEmpty {
            return .synced(lines)
        }

        let plain = cleanedPlainLyrics(trimmed)
        return plain.isEmpty ? .none : .plainOnly(plain)
    }

    static func parseLRC(_ lrc: String) -> [LyricLine] {
        let lines = lrc.components(separatedBy: .newlines)
        var lyrics: [(line: LyricLine, order: Int)] = []
        let offsetSeconds = parseLRCOffsetSeconds(lines)
        var insertionOrder = 0

        // Accept [m:ss], [mm:ss], and 1-3 fractional digits separated by '.'
        // or ':'. QQ Music uses the latter in notices such as [00:00:00].
        let pattern = "\\[(\\d{1,2}):(\\d{2})(?:[.:](\\d{1,3}))?\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        for line in lines {
            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            let matches = regex.matches(in: line, range: fullRange)
            guard let lastMatch = matches.last else {
                continue
            }

            let textStart = lastMatch.range.location + lastMatch.range.length
            guard textStart <= nsLine.length else { continue }
            let text = cleanedLineText(nsLine.substring(from: textStart))
            guard !text.isEmpty,
                  !isNoLyricsPlaceholder(text),
                  !isJunkLine(text) else { continue }

            // One LRC row may carry several timestamps for a repeated line.
            for match in matches {
                let minRange = match.range(at: 1)
                let secRange = match.range(at: 2)
                let fracRange = match.range(at: 3)
                let minutes = Double(nsLine.substring(with: minRange)) ?? 0
                let seconds = Double(nsLine.substring(with: secRange)) ?? 0
                guard seconds < 60 else { continue }

                let fractionString = fracRange.location == NSNotFound
                    ? ""
                    : nsLine.substring(with: fracRange)
                let fraction = fractionString.isEmpty
                    ? 0
                    : (Double(fractionString) ?? 0)
                        / pow(10, Double(fractionString.count))
                let timestamp = max(
                    0,
                    minutes * 60 + seconds + fraction - offsetSeconds
                )
                lyrics.append((
                    LyricLine(timestamp: timestamp, text: text),
                    insertionOrder
                ))
                insertionOrder += 1
            }
        }

        let sorted = lyrics.sorted {
            if $0.line.timestamp == $1.line.timestamp {
                return $0.order < $1.order
            }
            return $0.line.timestamp < $1.line.timestamp
        }

        // Exact/near-exact duplicate timestamps otherwise create zero-duration
        // rows, which make the KTV text appear to jump.
        var result: [LyricLine] = []
        for item in sorted {
            if let previous = result.last,
               abs(previous.timestamp - item.line.timestamp) < 0.01 {
                continue
            }
            result.append(item.line)
        }
        return result
    }

    static func sanitized(
        _ lines: [LyricLine],
        trackDuration: TimeInterval
    ) -> [LyricLine] {
        guard trackDuration > 0 else { return lines }
        // A small grace period accommodates rounded player durations while
        // rejecting corrupt timestamps far beyond the end of the track.
        return lines.filter { $0.timestamp <= trackDuration + 2 }
    }

    /// Providers sometimes return a timed one-line notice for an instrumental
    /// track. It is not a real lyric and must not keep the closed-notch band open.
    static func isNoLyricsPlaceholder(_ value: String) -> Bool {
        let content = value
            .components(separatedBy: .newlines)
            .map {
                $0.replacingOccurrences(
                    of: "\\[[^\\]]+\\]",
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        guard !content.isEmpty, content.count <= 2 else { return false }

        let normalized = content
            .joined(separator: " ")
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .lowercased()
            .replacingOccurrences(
                of: "[^\\p{L}\\p{N}]+",
                with: "",
                options: .regularExpression
            )

        return normalized.contains("没有填词的纯音乐")
            || normalized == "纯音乐请欣赏"
            || normalized == "纯音乐请您欣赏"
            || normalized == "纯音乐无歌词"
            || normalized == "该歌曲为纯音乐请欣赏"
            || normalized == "此歌曲为纯音乐请您欣赏"
            || normalized == "暂无歌词"
            || normalized == "无歌词"
            || normalized == "instrumental"
            || normalized == "nolyric"
            || normalized == "nolyrics"
    }

    static func isJunkLine(_ value: String) -> Bool {
        let normalized = cleanedLineText(value)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .lowercased()
        guard !normalized.isEmpty else { return true }

        let prefixes = [
            "推广", "营销推广", "音乐推广", "发行推广", "歌曲推广",
            "出品推广", "广告", "商务合作",
        ]
        if prefixes.contains(where: {
            normalized.range(
                of: "^\\s*\($0)\\s*[:：]",
                options: .regularExpression
            ) != nil
        }) {
            return true
        }

        return normalized.hasPrefix("本歌词由")
            || normalized.hasPrefix("本歌曲来自")
            || normalized.hasPrefix("未经许可，不得")
            || normalized.hasPrefix("未经许可,不得")
    }

    private static func cleanedPlainLyrics(_ value: String) -> String {
        value
            .components(separatedBy: .newlines)
            .map(cleanedLineText)
            .filter {
                !$0.isEmpty
                    && !isJunkLine($0)
                    && !isNoLyricsPlaceholder($0)
            }
            .joined(separator: "\n")
    }

    private static func cleanedLineText(_ value: String) -> String {
        let invisibleScalars = CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}")
        let scalars = value.unicodeScalars.filter {
            !invisibleScalars.contains($0)
        }
        return String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseLRCOffsetSeconds(_ lines: [String]) -> TimeInterval {
        guard let regex = try? NSRegularExpression(
            pattern: "\\[offset:\\s*([+-]?\\d+)\\]",
            options: [.caseInsensitive]
        ) else {
            return 0
        }

        for line in lines {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            if let match = regex.firstMatch(in: line, range: range),
               match.range(at: 1).location != NSNotFound {
                let milliseconds = Double(
                    nsLine.substring(with: match.range(at: 1))
                ) ?? 0
                return milliseconds / 1000
            }
        }
        return 0
    }
}
