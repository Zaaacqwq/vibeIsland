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
import SwiftUI

/// The seven groups the Monitor tab renders — one overview tile each, and one
/// drill-in detail view each. Order here is the order tiles appear in the
/// overview grid and the order checkboxes appear in Settings.
enum MonitorCategory: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case cpu
    case gpu
    case memory
    case storage
    case network
    case power
    case display

    var id: String { rawValue }

    /// Full name shown in the detail header and in Settings.
    var title: String {
        switch self {
        case .cpu: return String(localized: "CPU")
        case .gpu: return String(localized: "GPU")
        case .memory: return String(localized: "Memory")
        case .storage: return String(localized: "Storage")
        case .network: return String(localized: "Network")
        case .power: return String(localized: "Power")
        case .display: return String(localized: "Displays")
        }
    }

    /// Short mono eyebrow for the overview tile — kept to ~7 characters so a
    /// tile never has to truncate its own label.
    var eyebrow: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "MEMORY"
        case .storage: return "STORAGE"
        case .network: return "NETWORK"
        case .power: return "POWER"
        case .display: return "DISPLAY"
        }
    }

    var systemImage: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "cpu.fill"
        case .memory: return "memorychip"
        case .storage: return "internaldrive"
        case .network: return "network"
        case .power: return "bolt.fill"
        case .display: return "display"
        }
    }

    /// Tile accent. Used only for the icon and the sparkline stroke — values
    /// stay on the neutral text ramp so the grid never turns into confetti.
    var tint: Color {
        switch self {
        case .cpu: return NotchDesign.Colors.info
        case .gpu: return Color(nsColor: NSColor(geistHex: "#A78BFA"))
        case .memory: return NotchDesign.Colors.success
        case .storage: return Color(nsColor: NSColor(geistHex: "#E0A83E"))
        case .network: return Color(nsColor: NSColor(geistHex: "#4EC9B0"))
        case .power: return Color(nsColor: NSColor(geistHex: "#7BD88F"))
        case .display: return Color(nsColor: NSColor(geistHex: "#F0A8C0"))
        }
    }
}
