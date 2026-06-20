/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import Foundation
import Defaults
import CoreGraphics

public enum Style {
    case notch
    case floating
}

/// Controls how Atoll renders on external and non-notched displays.
/// - `notch`: Standard notch shape (concave top corners blending into the screen edge).
/// - `dynamicIsland`: Pill-shaped island with continuously rounded corners,
///   inspired by DynamicNotchKit's floating style. Only applies to screens
///   that do NOT have a physical notch.
enum ExternalDisplayStyle: String, CaseIterable, Defaults.Serializable, Identifiable {
    case notch = "Standard Notch"
    case dynamicIsland = "Dynamic Island"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .notch:
            return String(localized: "Standard Notch")
        case .dynamicIsland:
            return String(localized: "Dynamic Island")
        }
    }

    var description: String {
        switch self {
        case .notch:
            return String(localized: "Classic notch shape that blends into the top screen edge")
        case .dynamicIsland:
            return String(localized: "Pill-shaped island with rounded corners, similar to iPhone's Dynamic Island")
        }
    }
}

public enum ContentType: Int, Codable, Hashable, Equatable {
    case normal
    case menu
    case settings
}

public enum NotchState {
    case closed
    case open
}

public enum NotchViews {
    case home
    case shelf
    case timer
    case terminal
    case agents
    case calendar
    case notifications
    case extensionExperience
}

enum ClosedNotchActivityKind: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case music
    case agent
    case timer
    case reminder
    case recording
    case download
    case localSend
    case privacy
    case shelf
    case focus
    case extensionActivity

    enum SidePreference {
        case left
        case right
        case automatic
    }

    var id: String { rawValue }

    static let defaultPriorityOrder: [ClosedNotchActivityKind] = [
        .music,
        .agent,
        .timer,
        .reminder,
        .recording,
        .download,
        .localSend,
        .privacy,
        .shelf,
        .focus,
        .extensionActivity
    ]

    var displayName: String {
        switch self {
        case .music: return String(localized: "Music")
        case .agent: return String(localized: "Claude")
        case .timer: return String(localized: "Timer")
        case .reminder: return String(localized: "Reminder")
        case .recording: return String(localized: "Recording")
        case .download: return String(localized: "Downloads")
        case .localSend: return String(localized: "LocalSend")
        case .privacy: return String(localized: "Privacy")
        case .shelf: return String(localized: "Shelf")
        case .focus: return String(localized: "Focus")
        case .extensionActivity: return String(localized: "Extensions")
        }
    }

    var systemImage: String {
        switch self {
        case .music: return "music.note"
        case .agent: return "sparkles"
        case .timer: return "timer"
        case .reminder: return "calendar.badge.clock"
        case .recording: return "record.circle"
        case .download: return "arrow.down.circle"
        case .localSend: return "paperplane.fill"
        case .privacy: return "camera.metering.center.weighted"
        case .shelf: return "tray.and.arrow.down.fill"
        case .focus: return "moon.fill"
        case .extensionActivity: return "puzzlepiece.extension"
        }
    }

    var sidePreference: SidePreference {
        switch self {
        case .music:
            return .left
        case .agent:
            return .right
        default:
            return .automatic
        }
    }
}

enum NotesLayoutState: Equatable {
    case list
    case split
    case editor

    var preferredHeight: CGFloat {
        switch self {
        case .list:
            return 240
        case .split:
            return 260
        case .editor:
            return 320
        }
    }
}

enum SettingsEnum {
    case general
    case about
    case charge
    case download
    case mediaPlayback
    case hud
    case shelf
    case extensions
}

enum DownloadIndicatorStyle: String, Defaults.Serializable {
    case progress = "Progress"
    case percentage = "Percentage"
    case circle = "Circle"
    
    var localizedName: String {
        switch self {
            case .progress:
                return String(localized: "Progress")
            case .percentage:
                return String(localized: "Percentage")
            case .circle:
                return String(localized: "Circle")
        }
    }
}

enum DownloadIconStyle: String, Defaults.Serializable {
    case onlyAppIcon = "Only app icon"
    case onlyIcon = "Only download icon"
    case iconAndAppIcon = "Icon and app icon"
}

enum MirrorShapeEnum: String, Defaults.Serializable {
    case rectangle = "Rectangular"
    case circle = "Circular"
}

enum WindowHeightMode: String, Defaults.Serializable {
    case matchMenuBar = "Match menubar height"
    case matchRealNotchSize = "Match real notch height"
    case custom = "Custom height"
}

enum SliderColorEnum: String, CaseIterable, Defaults.Serializable {
    case white = "White"
    case albumArt = "Match album art"
    case accent = "Accent color"
    
    var localizedName: String {
        switch self {
            case .white:
                return String(localized: "Standard")
            case .albumArt:
                return String(localized: "Custom Liquid")
            case .accent:
            return String(localized: "Accent color")
        }
    }
}

enum GlassCustomizationMode: String, CaseIterable, Defaults.Serializable, Identifiable {
    case standard = "Standard"
    case customLiquid = "Custom Liquid"

    var id: String { rawValue }

    var allowsVariantSelection: Bool {
        self == .customLiquid
    }
    
    var localizedName: String {
        switch self {
            case .standard:
                return String(localized: "Standard")
            case .customLiquid:
                return String(localized: "Custom Liquid")
        }
    }
}

enum TemperatureUnit: String, CaseIterable, Defaults.Serializable, Identifiable {
    case celsius = "Celsius"
    case fahrenheit = "Fahrenheit"

    var id: String { rawValue }

    var usesMetricSystem: Bool { self == .celsius }

    var symbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    var openMeteoTemperatureParameter: String? {
        switch self {
        case .celsius: return nil
        case .fahrenheit: return "fahrenheit"
        }
    }
}

enum TimerInputStyle: String, CaseIterable, Defaults.Serializable, Identifiable {
    case ruler = "Ruler"
    case manual = "Manual"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .ruler: return String(localized: "Ruler")
        case .manual: return String(localized: "Manual")
        }
    }
}
