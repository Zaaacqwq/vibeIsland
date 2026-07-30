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

/// The single source of truth for tab order and tab visibility.
///
/// This used to be an `if` chain duplicated in three places — `TabSelectionView`,
/// `DynamicIslandViewCoordinator.orderedVisibleTabs()`, and the coordinator's
/// static `tabOrder` used for slide direction — which is how a new tab could end
/// up animating backwards while looking correct everywhere else. With a
/// user-defined order there is no way to keep three copies honest, so they all
/// read from here.
enum NotchTabOrder {
    /// Shipping order, and the order the "Reset" button restores.
    static let defaultOrder: [NotchViews] = [
        .home,
        .shelf,
        .timer,
        .agents,
        .calendar,
        .notifications,
        .weather,
        .monitor,
        .colorPicker,
        .clipboard
    ]

    /// The stored order, repaired: unknown entries dropped, duplicates removed,
    /// and any tab missing from the stored list appended in default order.
    ///
    /// The append matters for updates — a tab introduced by a new version is
    /// absent from an order saved by the old one, and dropping it would make the
    /// feature look broken.
    static func normalized(_ raw: [NotchViews]) -> [NotchViews] {
        var seen = Set<NotchViews>()
        var result: [NotchViews] = []
        for tab in raw where !seen.contains(tab) {
            seen.insert(tab)
            result.append(tab)
        }
        for tab in defaultOrder where !seen.contains(tab) {
            result.append(tab)
        }
        return result
    }

    /// Every tab in the user's order, visible or not.
    static var current: [NotchViews] {
        normalized(Defaults[.notchTabOrder])
    }

    /// Whether a tab is currently switched on. Home is special: it also stands in
    /// as the only tab in minimalistic mode.
    static func isVisible(_ tab: NotchViews) -> Bool {
        switch tab {
        case .home:
            if Defaults[.enableMinimalisticUI] { return true }
            return Defaults[.showStandardMediaControls] || Defaults[.showCalendar]
        case .shelf:
            return Defaults[.dynamicShelf]
        case .timer:
            return Defaults[.enableTimerFeature] && Defaults[.timerDisplayMode] == .tab
        case .agents:
            return Defaults[.enableAgentMonitoring]
        case .calendar:
            return Defaults[.showCalendar] || Defaults[.showReminders]
        case .notifications:
            return Defaults[.enableNotificationMonitoring]
        case .weather:
            return Defaults[.enableWeather]
        case .monitor:
            return Defaults[.enableSystemMonitor]
        case .colorPicker:
            return Defaults[.enableColorPicker] && Defaults[.colorPickerDisplayMode] == .tab
        case .clipboard:
            return Defaults[.enableClipboardManager] && Defaults[.clipboardDisplayMode] == .tab
        }
    }

    /// The tabs the row actually draws, in the user's order. Minimalistic mode
    /// collapses to Home alone.
    static func visibleTabs() -> [NotchViews] {
        if Defaults[.enableMinimalisticUI] { return [.home] }
        return current.filter(isVisible)
    }

    /// Writes back a reordered *visible* row while leaving switched-off tabs where
    /// they sit, so turning a tab back on doesn't jump it to the end.
    static func applyingVisibleOrder(_ visible: [NotchViews]) -> [NotchViews] {
        let moved = Set(visible)
        var remaining = visible.makeIterator()
        return current.map { tab in
            guard moved.contains(tab) else { return tab }
            return remaining.next() ?? tab
        }
    }

    static func persist(visibleOrder: [NotchViews]) {
        Defaults[.notchTabOrder] = applyingVisibleOrder(visibleOrder)
    }

    static func resetToDefault() {
        Defaults[.notchTabOrder] = defaultOrder
    }

    static var isDefaultOrder: Bool {
        current == defaultOrder
    }
}
