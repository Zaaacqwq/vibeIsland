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

/// How a utility tool (color picker, clipboard manager, …) surfaces itself in
/// the open notch — as its own tab, or as a header button with a popover.
///
/// Mirrors ``TimerDisplayMode``, which predates this and keeps its own key so
/// existing users' stored preference needs no migration. New tools share this
/// one instead of each declaring another two-case enum.
public enum ToolDisplayMode: String, CaseIterable, Defaults.Serializable, Identifiable {
    case tab
    case popover

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tab:
            return String(localized: "Tab")
        case .popover:
            return String(localized: "Popover")
        }
    }

    /// Tool-specific wording is built from the tool's own name so the segmented
    /// control's help text reads naturally for each one.
    func description(toolName: String) -> String {
        switch self {
        case .tab:
            return String(localized: "Shows \(toolName) as a dedicated tab inside the open notch.")
        case .popover:
            return String(localized: "Shows \(toolName) in a popover from a button in the notch header.")
        }
    }
}
