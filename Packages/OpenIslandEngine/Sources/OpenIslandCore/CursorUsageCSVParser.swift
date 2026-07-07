import Foundation

/// One usage event parsed from a Cursor usage-export CSV row.
public struct CursorUsageRecord: Equatable, Sendable {
    public var date: Date
    public var model: String
    public var breakdown: TokenBreakdown
    public var costUSD: Double

    public init(date: Date, model: String, breakdown: TokenBreakdown, costUSD: Double) {
        self.date = date
        self.model = model
        self.breakdown = breakdown
        self.costUSD = costUSD
    }
}

/// Parses the CSV that Cursor's dashboard export endpoint
/// (`/api/dashboard/export-usage-events-csv?strategy=tokens`) returns. Cursor
/// bills server-side and ships no local token store, so this cached CSV is the
/// only source of per-event tokens/cost.
///
/// Three column layouts are supported (matching tokscale's `cursor.rs`):
/// - v1: `Date,Model,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,Total Tokens,Cost,Cost to you`
/// - v2: `Date,Kind,Model,Max Mode,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,Total Tokens,Cost`
/// - v3: `Date,Cloud Agent ID,Automation ID,Kind,Model,Max Mode,Input (w/ Cache Write),…,Cost`
///
/// `input = Input (w/o Cache Write)` and `cacheWrite = (w/ Cache Write) − (w/o
/// Cache Write)`, so the buckets stay mutually exclusive. Cost is taken verbatim
/// from the CSV (non-numeric values like `Included` / `-` become $0).
public enum CursorUsageCSVParser {
    private struct ColumnLayout {
        let model: Int
        let inputWithCacheWrite: Int
        let inputWithoutCacheWrite: Int
        let cacheRead: Int
        let output: Int
        let cost: Int

        var minimumFieldCount: Int { cost + 1 }
    }

    public static func parse(_ csv: String) -> [CursorUsageRecord] {
        var lines = csv.split(whereSeparator: \.isNewline).makeIterator()
        guard let header = lines.next() else { return [] }

        let headerFields = splitCSVLine(String(header))
        // Guard against non-Cursor content (e.g. an HTML error page).
        guard headerFields.contains(where: { $0.contains("Date") }),
              headerFields.contains(where: { $0.contains("Model") }) else {
            return []
        }

        let layout = columnLayout(headerFields: headerFields)
        var records: [CursorUsageRecord] = []

        while let line = lines.next() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty else { continue }

            let fields = splitCSVLine(String(line))
            guard fields.count >= layout.minimumFieldCount else { continue }

            let model = field(fields, layout.model)
            guard !model.isEmpty else { continue }

            guard let date = parseDate(field(fields, 0)) else { continue }

            let inputWith = int(field(fields, layout.inputWithCacheWrite))
            let inputWithout = int(field(fields, layout.inputWithoutCacheWrite))
            let cacheRead = int(field(fields, layout.cacheRead))
            let output = int(field(fields, layout.output))
            let cost = parseCost(field(fields, layout.cost))

            let breakdown = TokenBreakdown(
                input: max(0, inputWithout),
                output: max(0, output),
                reasoning: 0,
                cacheRead: max(0, cacheRead),
                cacheWrite: max(0, inputWith - inputWithout)
            )
            guard !breakdown.isEmpty else { continue }

            records.append(
                CursorUsageRecord(date: date, model: model, breakdown: breakdown, costUSD: cost)
            )
        }

        return records
    }

    private static func columnLayout(headerFields: [String]) -> ColumnLayout {
        let hasKind = headerFields.contains { $0.trimmingCharacters(in: .whitespaces) == "Kind" }
        if hasKind, headerFields.count >= 11 {
            // v3: Date, Cloud Agent ID, Automation ID, Kind, Model, Max Mode, …
            return ColumnLayout(
                model: 4, inputWithCacheWrite: 6, inputWithoutCacheWrite: 7,
                cacheRead: 8, output: 9, cost: 11
            )
        }
        if hasKind {
            // v2: Date, Kind, Model, Max Mode, …
            return ColumnLayout(
                model: 2, inputWithCacheWrite: 4, inputWithoutCacheWrite: 5,
                cacheRead: 6, output: 7, cost: 9
            )
        }
        // v1: Date, Model, …
        return ColumnLayout(
            model: 1, inputWithCacheWrite: 2, inputWithoutCacheWrite: 3,
            cacheRead: 4, output: 5, cost: 7
        )
    }

    /// Splits one CSV line on unquoted commas. Cursor never embeds commas in
    /// quoted fields we read, so this simple quote-toggling splitter is enough.
    static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for character in line {
            switch character {
            case "\"":
                inQuotes.toggle()
            case "," where !inQuotes:
                fields.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        fields.append(current)
        return fields
    }

    private static func field(_ fields: [String], _ index: Int) -> String {
        guard index >= 0, index < fields.count else { return "" }
        return fields[index]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            .trimmingCharacters(in: .whitespaces)
    }

    private static func int(_ value: String) -> Int {
        Int(value) ?? 0
    }

    /// Parses `$1,234.56` / `0.19` / `Included` / `-` → Double, defaulting the
    /// non-numeric spend labels to 0.
    static func parseCost(_ value: String) -> Double {
        let cleaned = value
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard cleaned.contains(where: { $0.isNumber }) else { return 0 }
        return Double(cleaned) ?? 0
    }

    static func parseDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let date = TranscriptParsing.date(fromISO8601: trimmed) { return date }
        // Date-only rows ("2026-04-09") → noon UTC, which keeps the calendar day
        // stable across every timezone from UTC-12 to UTC+14.
        guard let midnight = dateOnlyFormatter.date(from: trimmed) else { return nil }
        return midnight.addingTimeInterval(12 * 3600)
    }

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
