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

/// A system metric the open-notch Home header can surface. Users pick which
/// ones show via `Defaults[.homeHeaderStats]`; the rendering order follows
/// `allCases`.
enum HeaderStatKind: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case cpu
    case gpu
    case ram
    case disk
    case network

    var id: String { rawValue }

    /// Short mono eyebrow shown above the value in the header cell.
    var eyebrow: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .ram: return "RAM"
        case .disk: return "DISK"
        case .network: return "NET"
        }
    }

    /// Descriptive title for the Settings toggle row.
    var settingsTitle: String {
        switch self {
        case .cpu: return "CPU usage"
        case .gpu: return "GPU usage"
        case .ram: return "Memory (RAM)"
        case .disk: return "Disk I/O"
        case .network: return "Network I/O"
        }
    }
}

enum HeaderStatFormatting {
    /// Transfer rate split into its number and unit, e.g. `("1.2", "MB/s")`,
    /// `("340", "KB/s")`. The two-line network cell renders the number in a
    /// fixed-width, right-aligned slot so the unit stays pinned in place instead
    /// of shifting as the digits change.
    static func rateParts(_ bytesPerSecond: Double) -> (value: String, unit: String) {
        let mb = bytesPerSecond / 1_048_576
        if mb >= 1 { return (String(format: mb >= 10 ? "%.0f" : "%.1f", mb), "MB/s") }
        let kb = bytesPerSecond / 1024
        return (String(format: kb >= 10 ? "%.0f" : "%.1f", kb), "KB/s")
    }
}
