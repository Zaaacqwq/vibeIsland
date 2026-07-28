/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Defaults
import Foundation

/// Number formatting for the Monitor tab.
///
/// Every helper returns short, fixed-shape strings — the tab renders in mono at
/// 10–24pt inside a fixed-width tile, so "1.2 GB" is always preferable to
/// "1,234,567,890 bytes". Values are split into `(value, unit)` where the view
/// needs to style or align the two halves separately.
enum MonitorFormat {
    // MARK: Percentages

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func percent(fraction: Double) -> String {
        percent(fraction * 100)
    }

    /// One decimal place — for figures where a whole percent is too coarse to
    /// show movement (battery health, memory pressure).
    static func precisePercent(fraction: Double) -> String {
        String(format: "%.1f%%", fraction * 100)
    }

    // MARK: Capacities

    /// Binary-prefixed size with an adaptive decimal place, e.g. `("16", "GB")`,
    /// `("1.4", "TB")`, `("512", "MB")`.
    static func sizeParts(_ bytes: UInt64) -> (value: String, unit: String) {
        sizeParts(Double(bytes))
    }

    static func sizeParts(_ bytes: Double) -> (value: String, unit: String) {
        let units: [(threshold: Double, suffix: String)] = [
            (1_099_511_627_776, "TB"),
            (1_073_741_824, "GB"),
            (1_048_576, "MB"),
            (1024, "KB"),
        ]
        for unit in units where bytes >= unit.threshold {
            let scaled = bytes / unit.threshold
            return (String(format: scaled >= 100 ? "%.0f" : (scaled >= 10 ? "%.1f" : "%.2f"), scaled), unit.suffix)
        }
        return (String(format: "%.0f", max(bytes, 0)), "B")
    }

    static func size(_ bytes: UInt64) -> String {
        let parts = sizeParts(bytes)
        return "\(parts.value) \(parts.unit)"
    }

    // MARK: Rates

    /// Throughput split into number and unit, honouring the bits/bytes
    /// preference. Bits mode reports decimal (SI) multiples the way link speeds
    /// are quoted; bytes mode stays binary, matching the capacity figures.
    static func rateParts(_ bytesPerSecond: Double, useBits: Bool = Defaults[.monitorNetworkUsesBits]) -> (value: String, unit: String) {
        guard useBits else {
            let parts = sizeParts(max(bytesPerSecond, 0))
            return (parts.value, "\(parts.unit)/s")
        }
        let bits = max(bytesPerSecond, 0) * 8
        let units: [(threshold: Double, suffix: String)] = [
            (1_000_000_000, "Gb/s"),
            (1_000_000, "Mb/s"),
            (1_000, "Kb/s"),
        ]
        for unit in units where bits >= unit.threshold {
            let scaled = bits / unit.threshold
            return (String(format: scaled >= 100 ? "%.0f" : (scaled >= 10 ? "%.1f" : "%.2f"), scaled), unit.suffix)
        }
        return (String(format: "%.0f", bits), "b/s")
    }

    static func rate(_ bytesPerSecond: Double, useBits: Bool = Defaults[.monitorNetworkUsesBits]) -> String {
        let parts = rateParts(bytesPerSecond, useBits: useBits)
        return "\(parts.value) \(parts.unit)"
    }

    // MARK: Time

    /// Compact `h:mm` for battery estimates, or `Nm` under an hour.
    static func duration(minutes: Int) -> String {
        guard minutes > 0 else { return "—" }
        let hours = minutes / 60
        let remainder = minutes % 60
        guard hours > 0 else { return "\(remainder)m" }
        return String(format: "%d:%02d", hours, remainder)
    }

    // MARK: Misc

    static func temperature(celsius: Double) -> String {
        String(format: "%.1f°C", celsius)
    }

    /// Two decimals, the conventional shape for `getloadavg` output.
    static func loadAverage(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
