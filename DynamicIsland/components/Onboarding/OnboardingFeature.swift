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

import AppKit
import Defaults
import SwiftUI

/// A feature the user can opt into during onboarding. The bubble picker
/// (`FeatureSelectionView`) toggles these; each with `hasConfigPage == true`
/// then gets a focused setup page. Rendering/sequence order follows `allCases`.
enum OnboardingFeature: String, CaseIterable, Identifiable {
    case agent
    case calendar
    case timer
    case weather
    case stats
    case notification
    case shelf
    case music

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agent: return String(localized: "Agents")
        case .calendar: return String(localized: "Calendar")
        case .timer: return String(localized: "Timer")
        case .weather: return String(localized: "Weather")
        case .stats: return String(localized: "System Stats")
        case .notification: return String(localized: "Notifications")
        case .shelf: return String(localized: "Shelf")
        case .music: return String(localized: "Music")
        }
    }

    var subtitle: String {
        switch self {
        case .agent: return String(localized: "Monitor coding agents and jump back to their terminal.")
        case .calendar: return String(localized: "See your upcoming events in the notch.")
        case .timer: return String(localized: "Quick presets and a live countdown.")
        case .weather: return String(localized: "Current conditions at a glance.")
        case .stats: return String(localized: "CPU, memory, and more in the header.")
        case .notification: return String(localized: "Mirror macOS notifications into the notch.")
        case .shelf: return String(localized: "Drag-and-drop file stash.")
        case .music: return String(localized: "Now-playing controls and visualizer.")
        }
    }

    /// SF Symbol shown in the bubble.
    var symbol: String {
        switch self {
        case .agent: return "chevron.left.forwardslash.chevron.right"
        case .calendar: return "calendar"
        case .timer: return "timer"
        case .weather: return "cloud.sun.fill"
        case .stats: return "chart.bar.fill"
        case .notification: return "bell.fill"
        case .shelf: return "tray.full.fill"
        case .music: return "music.note"
        }
    }

    /// Two-stop gradient used for the bubble's selected tint / icon.
    var gradient: [Color] {
        switch self {
        case .agent: return [.blue, .purple]
        case .calendar: return [.red, .orange]
        case .timer: return [.orange, .yellow]
        case .weather: return [.cyan, .blue]
        case .stats: return [.green, .mint]
        case .notification: return [.pink, .red]
        case .shelf: return [.indigo, .blue]
        case .music: return [.purple, .pink]
        }
    }

    /// Whether selecting this feature leads to a dedicated setup page.
    /// Weather and Shelf need no configuration — selecting them is enough.
    var hasConfigPage: Bool {
        switch self {
        case .weather, .shelf: return false
        default: return true
        }
    }

    /// Flip the feature's primary enable flag. Music has no single boolean
    /// (a media controller is always set), so it is a no-op there.
    func setEnabled(_ enabled: Bool) {
        switch self {
        case .agent: Defaults[.enableAgentMonitoring] = enabled
        case .calendar:
            Defaults[.showCalendar] = enabled
            Defaults[.showReminders] = enabled
        case .timer: Defaults[.enableTimerFeature] = enabled
        case .weather: Defaults[.enableWeather] = enabled
        case .stats: Defaults[.showHeaderContextWidgets] = enabled
        case .notification: Defaults[.enableNotificationMonitoring] = enabled
        case .shelf: Defaults[.dynamicShelf] = enabled
        case .music: break
        }
    }

    // MARK: - Selection application

    /// Apply an onboarding selection: enable chosen features, disable the rest
    /// (scoped to these keys only), then write the common first-run settings.
    /// Replaces the old `applyProfileSettings`.
    static func applySelection(_ selected: Set<OnboardingFeature>) {
        for feature in allCases {
            feature.setEnabled(selected.contains(feature))
        }

        Defaults[.menubarIcon] = true
        Defaults[.enableHaptics] = true

        // Auto-detect notch: real notch -> notch style, otherwise Dynamic Island.
        Defaults[.externalDisplayStyle] = mainScreenHasNotch() ? .notch : .dynamicIsland
    }

    /// Ordered config pages for a selection (canonical `allCases` order).
    static func configPages(for selected: Set<OnboardingFeature>) -> [OnboardingFeature] {
        allCases.filter { selected.contains($0) && $0.hasConfigPage }
    }

    /// `true` when the main screen has a physical notch (safe-area top inset).
    /// Moved here from the removed `ProfileSelectionView`.
    static func mainScreenHasNotch() -> Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.safeAreaInsets.top > 0
    }
}
