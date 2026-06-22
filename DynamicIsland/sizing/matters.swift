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

import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

var openNotchSize: CGSize {
    let maxWidth = maxAllowedNotchWidth()
    let width: CGFloat
    if Defaults[.autoNotchWidth] {
        // Auto: size purely from the number of enabled tabs.
        width = min(autoNotchWidth(forTabCount: enabledStandardTabCount()), maxWidth)
    } else {
        // Manual: use the stored width, floored at the tab-count minimum.
        let storedWidth = Defaults[.openNotchWidth]
        let minWidth = currentRecommendedMinimumNotchWidth()
        width = min(max(storedWidth, minWidth), maxWidth)
    }
    return .init(width: width, height: 200)
}

/// Maximum notch width based on the current screen's point width.
/// Prevents the notch from extending beyond the screen on scaled displays.
func maxAllowedNotchWidth(for screenName: String? = nil) -> CGFloat {
    let screen: NSScreen?
    if let screenName {
        screen = NSScreen.screens.first { $0.localizedName == screenName }
    } else {
        screen = NSScreen.main
    }
    guard let screenWidth = screen?.frame.width, screenWidth > 0 else {
        return 900
    }
    return max(screenWidth - 60, 400)
}

/// Convenience for the main screen.
func maxAllowedNotchWidth() -> CGFloat {
    maxAllowedNotchWidth(for: nil)
}

// MARK: - Tab-Based Notch Width

/// Counts the number of currently enabled standard notch tabs.
/// Mirrors the tab-building logic in ``TabSelectionView`` and
/// ``DynamicIslandViewCoordinator.orderedVisibleTabs``.
func enabledStandardTabCount() -> Int {
    var count = 0

    // Home tab
    if Defaults[.showStandardMediaControls] || Defaults[.showCalendar] || Defaults[.showMirror] {
        count += 1
    }
    // Shelf tab
    if Defaults[.dynamicShelf] {
        count += 1
    }
    // Terminal tab
    if Defaults[.enableTerminalFeature] {
        count += 1
    }
    // Agents tab
    if Defaults[.enableAgentMonitoring] {
        count += 1
    }
    // Calendar tab
    if Defaults[.showCalendar] {
        count += 1
    }
    // Notifications tab
    if Defaults[.enableNotificationMonitoring] {
        count += 1
    }
    // Weather tab
    if Defaults[.enableWeather] {
        count += 1
    }

    return count
}

/// Returns the recommended minimum notch width for the given tab count, sized
/// so the tab row never extends behind the physical notch.
func recommendedMinimumNotchWidth(forTabCount count: Int) -> CGFloat {
    switch count {
    case ...4: return 640
    case 5: return 720
    case 6: return 800
    default: return 880
    }
}

/// Returns the recommended minimum notch width for the current tab configuration.
func currentRecommendedMinimumNotchWidth() -> CGFloat {
    recommendedMinimumNotchWidth(forTabCount: enabledStandardTabCount())
}

/// The automatic expanded-notch width for a given tab count. Unlike the
/// "minimum" above (a one-way floor), this scales both up and down so the notch
/// grows when tabs are added and shrinks when they're removed. Floored at a
/// width that still fits the home tab's media + side-panel content.
func autoNotchWidth(forTabCount count: Int) -> CGFloat {
    switch count {
    case ...1: return 560
    case 2: return 580
    case 3: return 610
    case 4: return 640
    case 5: return 720
    case 6: return 800
    default: return 880
    }
}

/// Keeps the stored notch width in sync with the current tab count and clamps it
/// to the screen width. In auto mode it tracks the tab-based width (up *and*
/// down); in manual mode it only enforces the per-tab minimum. Writing the value
/// also drives the window-resize publisher. Skipped in minimalistic mode.
func enforceMinimumNotchWidth() {
    guard !Defaults[.enableMinimalisticUI] else { return }
    let maxWidth = maxAllowedNotchWidth()
    let target: CGFloat
    if Defaults[.autoNotchWidth] {
        target = min(autoNotchWidth(forTabCount: enabledStandardTabCount()), maxWidth)
    } else {
        let minWidth = currentRecommendedMinimumNotchWidth()
        var width = Defaults[.openNotchWidth]
        if width < minWidth { width = minWidth }
        if width > maxWidth { width = maxWidth }
        target = width
    }
    if Defaults[.openNotchWidth] != target {
        Defaults[.openNotchWidth] = target
    }
}
private let minimalisticBaseOpenNotchSize: CGSize = .init(width: 420, height: 180)
private let minimalisticLyricsExtraHeight: CGFloat = 40

/// Extra height added below the closed notch pill to show the current synced
/// lyric line when `showLyricsInClosedNotch` is enabled (standard notch only).
let closedLyricsBandHeight: CGFloat = 28
let minimalisticTimerCountdownTopPadding: CGFloat = 12
let minimalisticTimerCountdownContentHeight: CGFloat = 82
let minimalisticTimerCountdownBlockHeight: CGFloat = minimalisticTimerCountdownTopPadding + minimalisticTimerCountdownContentHeight
let notchShadowPaddingStandard: CGFloat = 18
let notchShadowPaddingMinimalistic: CGFloat = 12

@MainActor
var minimalisticOpenNotchSize: CGSize {
    var size = minimalisticBaseOpenNotchSize

    if Defaults[.enableLyrics] {
        size.height += minimalisticLyricsExtraHeight
    }
    
    let reminderCount = ReminderLiveActivityManager.shared.activeWindowReminders.count
    if reminderCount > 0 {
        let reminderHeight = ReminderLiveActivityManager.additionalHeight(forRowCount: reminderCount)
        size.height += reminderHeight
    }

    if DynamicIslandViewCoordinator.shared.timerLiveActivityEnabled && TimerManager.shared.isExternalTimerActive {
        size.height += minimalisticTimerCountdownBlockHeight
    }

    return size
}
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 24), closed: (top: 6, bottom: 14))
let minimalisticCornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 35, bottom: 35), closed: cornerRadiusInsets.closed)

// MARK: - Terminal tab clip (notch surface)

/// Padding on the terminal block inside the notch. Inner corner radius = outer shell radius on that edge, minus the matching edge padding.
let notchTerminalContentEdgePadding: (top: CGFloat, horizontal: CGFloat, bottom: CGFloat) = (4, 8, 8)

/// Inner margin (all edges) between the SwiftTerm view's glyphs and the terminal block edge.
/// Applied to the LocalProcessTerminalView frame only; the frosted blur underlay stays full-bleed.
let notchTerminalInnerTextInset: CGFloat = 6

/// Bottom radii for the shell (outer) and the terminal ``clipShape`` (inner), per design: inner = outer shell bottom radius − `notchTerminalContentEdgePadding.bottom`.
func notchTerminalBottomCornerRadii(
    isDynamicIslandMode: Bool,
    notchState: NotchState,
    cornerRadiusScaling: Bool,
    enableMinimalisticUI: Bool,
    closedNotchHeight: CGFloat
) -> (outerBottom: CGFloat, innerBottom: CGFloat) {
    let p = notchTerminalContentEdgePadding.bottom
    if isDynamicIslandMode {
        let outer: CGFloat
        if notchState == .open {
            outer = enableMinimalisticUI
                ? minimalisticCornerRadiusInsets.opened.top
                : dynamicIslandPillCornerRadiusInsets.opened
        } else {
            outer = max(closedNotchHeight / 2, dynamicIslandPillCornerRadiusInsets.closed.standard)
        }
        return (outer, max(0, outer - p))
    }
    let active: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = {
        if enableMinimalisticUI {
            return (opened: minimalisticCornerRadiusInsets.opened, closed: cornerRadiusInsets.closed)
        }
        return cornerRadiusInsets
    }()
    let outerBottom: CGFloat
    if notchState == .open && cornerRadiusScaling {
        outerBottom = active.opened.bottom
    } else {
        outerBottom = active.closed.bottom
    }
    return (outerBottom, max(0, outerBottom - p))
}

func notchShadowPaddingValue(isMinimalistic: Bool) -> CGFloat {
    isMinimalistic ? notchShadowPaddingMinimalistic : notchShadowPaddingStandard
}

func addShadowPadding(to size: CGSize, isMinimalistic: Bool) -> CGSize {
    CGSize(width: size.width, height: size.height + notchShadowPaddingValue(isMinimalistic: isMinimalistic))
}

/// Determines whether a specific screen should render the Dynamic Island pill
/// shape instead of the standard notch shape.
///
/// Returns `true` only when ALL of these conditions are met:
/// 1. The user has selected `.dynamicIsland` in `externalDisplayStyle`
/// 2. The screen does NOT have a physical notch (safeAreaInsets.top == 0)
///
/// Screens with a physical notch always use the standard notch shape.
func shouldUseDynamicIslandMode(for screenName: String?) -> Bool {
    guard Defaults[.externalDisplayStyle] == .dynamicIsland else {
        return false
    }

    var selectedScreen: NSScreen? = NSScreen.main
    if let screenName {
        selectedScreen = NSScreen.screens.first(where: { $0.localizedName == screenName })
    }

    guard let screen = selectedScreen else {
        // No screen found — fallback to standard notch
        return false
    }

    // Physical notch screens always use standard notch shape
    return screen.safeAreaInsets.top <= 0
}

/// Whether the closed-notch lyrics band should be shown (and the closed window
/// grown downward) on the given screen. Standard notch only — excludes
/// minimalistic UI and Dynamic Island pill mode, per the feature scope.
@MainActor
func closedNotchLyricsBandActive(for screenName: String?) -> Bool {
    guard Defaults[.showLyricsInClosedNotch] else { return false }
    guard !Defaults[.enableMinimalisticUI] else { return false }
    guard !shouldUseDynamicIslandMode(for: screenName) else { return false }
    let music = MusicManager.shared
    return music.isPlaying && (music.hasDisplayableLyricLine || music.isLoadingLyricLine)
}

/// Corner radius insets for the Dynamic Island pill shape.
/// - closed: half the closed notch height for a true capsule look
/// - opened: generous radius for smooth expanded pill
let dynamicIslandPillCornerRadiusInsets: (opened: CGFloat, closed: (standard: CGFloat, minimalistic: CGFloat)) = (
    opened: 24,
    closed: (standard: 16, minimalistic: 16)
)

/// Vertical offset from the top screen edge for the Dynamic Island pill.
/// Creates a visual gap so the pill floats below the menu bar, mimicking
/// the iPhone's Dynamic Island detachment from the physical screen edge.
let dynamicIslandTopOffset: CGFloat = 6

/// Extra horizontal padding applied OUTSIDE the pill clip shape in Dynamic
/// Island mode so the drop shadow has room to render without being clipped
/// by the outer frame constraint.
let dynamicIslandShadowInset: CGFloat = 14

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 13.0, closed: 4.0)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

func getScreenFrame(_ screen: String? = nil) -> CGRect? {
    var selectedScreen = NSScreen.main

    if let customScreen = screen {
        selectedScreen = NSScreen.screens.first(where: { $0.localizedName == customScreen })
    }
    
    if let screen = selectedScreen {
        return screen.frame
    }
    
    return nil
}

func getClosedNotchSize(screen: String? = nil) -> CGSize {
    // Default notch size, to avoid using optionals
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = 185

    var selectedScreen = NSScreen.main

    if let customScreen = screen {
        selectedScreen = NSScreen.screens.first(where: { $0.localizedName == customScreen })
    }

    // Check if the screen is available
    if let screen = selectedScreen {
        // Calculate and set the exact width of the notch
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
        }

        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            // This is a display WITH a notch - use notch height settings
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        } else {
            // This is a display WITHOUT a notch - use non-notch height settings
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}
