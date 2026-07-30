/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for VibeIsland (DynamicIsland)
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

/// Fixed content height for every standard (non-minimalistic) open-notch tab
/// surface. Uniform across Home/Shelf/Timer/Agents/Calendar/Notifications/
/// Weather, per the notch redesign's "same height everywhere" rule — tabs
/// with shorter content top-align and leave breathing room below rather than
/// shrinking the window (see the tab-switch container in ContentView.swift).
let standardOpenNotchContentHeight: CGFloat = 212

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
    return .init(width: width, height: standardOpenNotchContentHeight)
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

/// Number of tabs the row currently draws. Reads the same visibility rules as the
/// row itself (``NotchTabOrder``) rather than re-deriving them — a fourth copy of
/// that `if` chain is a fourth place to forget a new tab.
func enabledStandardTabCount() -> Int {
    NotchTabOrder.visibleTabs().count
}

/// Returns the recommended minimum notch width for the given tab count, sized
/// so the tab row never extends behind the physical notch.
///
/// Never exceeds what the screen can show: callers build slider ranges from this,
/// and a "minimum" above the maximum is both meaningless and, as a `ClosedRange`,
/// a crash.
func recommendedMinimumNotchWidth(forTabCount count: Int) -> CGFloat {
    let required = max(openNotchContentFloorWidth, headerRowMinimumWidth(forTabCount: count))
    return min(required, maxAllowedNotchWidth())
}

/// Narrowest the open notch goes regardless of how quiet the header is: below
/// this the Home tab's media card and side panel get cramped.
///
/// This replaces the old per-tab-count width table. That table was a proxy for
/// "the header needs room", calibrated back when the selected tab also rendered
/// its label; now that ``headerRowMinimumWidth`` computes the requirement
/// directly, the table only made the notch wider than it had to be.
let openNotchContentFloorWidth: CGFloat = 640

// MARK: - Header-Aware Minimum Width

/// Width the open-notch header row needs to lay out without anything sliding
/// under the physical notch.
///
/// The tab-count tables above assume a busy tab row is what drives width, but
/// the header has two sides: turning tabs *off* shrinks the notch while the
/// trailing side (stats widget, tool buttons, battery) keeps its size, so past a
/// point the trailing content gets squeezed toward — and behind — the notch
/// cutout, and the selected tab's label collapses to nothing. Flooring both the
/// auto width and the manual minimum at this keeps both sides intact.
///
/// Deliberately an estimate rather than a measurement: the notch width has to be
/// known before the header lays out, and it must not change when switching tabs
/// (that would resize the window on every tab switch), so the per-tab widgets are
/// folded in as a worst case.
func headerRowMinimumWidth(forTabCount count: Int) -> CGFloat {
    // The two sides split the window evenly — that is what centers the black
    // spacer on the notch cutout — so each side gets half of (width - cutout)
    // whether it needs it or not. The window therefore has to be sized from the
    // *wider* side, doubled. Sizing it from the sum instead leaves the wider side
    // short, and on the trailing side "short" means drawn behind the cutout.
    let leading = tabRowWidthEstimate(forTabCount: count) + headerLeadingPaddingEstimate
    let trailing = headerTrailingWidthEstimate() + headerTrailingGapEstimate
    return 2 * (max(leading, trailing) + headerSideSlack) + centerNotchGapEstimate()
}

/// `.padding(8)` around the tab row.
private let headerLeadingPaddingEstimate: CGFloat = 16
/// Minimum breathing room the trailing group keeps from the notch cover.
private let headerTrailingGapEstimate: CGFloat = 8
/// Margin on each side so content never lands flush against the notch cutout.
///
/// Without it the estimates have to be exactly right: at one point the tab row
/// needed 246pt and got exactly 246, so the last icon touched the cutout and any
/// rounding hid part of it. 8pt of slack costs 16pt of notch width and removes a
/// whole class of off-by-a-few clipping.
private let headerSideSlack: CGFloat = 8

/// A tab is a fixed-width button with 4pt gaps. With titles on, the selected tab
/// also carries its label — budgeted at the widest label in the row so switching
/// tabs never needs a wider notch than the one already on screen.
private func tabRowWidthEstimate(forTabCount count: Int) -> CGFloat {
    guard count > 0 else { return 0 }
    let icons = CGFloat(count) * TabButton.iconOnlyWidth + CGFloat(count - 1) * 4
    guard Defaults[.showNotchTabTitles] else { return icons }
    // 7pt icon-to-label gap + "Notifications" + 12pt padding either side, less
    // the icon-only width the selected slot no longer uses.
    return icons + 7 + 92 + 24 - TabButton.iconOnlyWidth + 30
}

/// The black spacer in the middle of the header, which covers the real notch.
/// Mirrors `DynamicIslandHeader`'s `min(closedNotchSize.width, 300)`.
private func centerNotchGapEstimate() -> CGFloat {
    min(getClosedNotchSize().width, 300)
}

/// Everything on the trailing side of the notch: the context widget, the
/// popover-mode tool buttons, the gear, the status glyphs and the battery.
private func headerTrailingWidthEstimate() -> CGFloat {
    var width = headerContextWidgetWidthEstimate()

    // 30pt each, and each one is a fixed frame that cannot shrink.
    var buttonCount = 0
    if Defaults[.enableTimerFeature] && Defaults[.timerDisplayMode] == .popover { buttonCount += 1 }
    if Defaults[.enableColorPicker] && Defaults[.colorPickerDisplayMode] == .popover { buttonCount += 1 }
    if Defaults[.enableClipboardManager] && Defaults[.clipboardDisplayMode] == .popover { buttonCount += 1 }
    if Defaults[.settingsIconInNotch] { buttonCount += 1 }
    // The recording / Do Not Disturb glyphs come and go at runtime, so budget for
    // them while they are switched on — but only when the header would actually
    // draw them. Reserving space the header then suppresses is 60pt of notch
    // width nobody asked for.
    if !notchHeaderSuppressesStatusIndicators() {
        if Defaults[.enableScreenRecordingDetection] && Defaults[.showRecordingIndicator] { buttonCount += 1 }
        if Defaults[.enableDoNotDisturbDetection] && Defaults[.showDoNotDisturbIndicator] { buttonCount += 1 }
    }
    width += CGFloat(buttonCount) * 30 + CGFloat(max(0, buttonCount - 1)) * 4

    if Defaults[.showBatteryIndicator] {
        width += Defaults[.enableMinimalisticUI] ? 32 : 44
    }

    return width
}

/// Whether the open-notch header hides its optional status glyphs (screen
/// recording, Do Not Disturb) because the row is already carrying the gear plus
/// tool buttons.
///
/// Lives here, next to the width math, because the two have to agree: the width
/// budget reserving space the header then suppresses (or vice versa) is exactly
/// how the row ends up mis-sized. `DynamicIslandHeader` reads this same function.
func notchHeaderSuppressesStatusIndicators() -> Bool {
    guard Defaults[.settingsIconInNotch] else { return false }
    if Defaults[.enableTimerFeature] { return true }
    return Defaults[.enableColorPicker] && Defaults[.colorPickerDisplayMode] == .popover
        || Defaults[.enableClipboardManager] && Defaults[.clipboardDisplayMode] == .popover
}

/// Width of the header's tab-dependent context widget, taken as the worst case
/// across the tabs that are actually enabled — a tab switch must not change the
/// window width.
private func headerContextWidgetWidthEstimate() -> CGFloat {
    guard Defaults[.showHeaderContextWidgets] else { return 0 }

    // The Home stats row is sized exactly and is NOT subject to the cap below:
    // its cells are `fixedSize`, so they cannot truncate — short-changing them
    // pushes the row under the notch cutout instead. Per metric, because they are
    // not interchangeable: a percentage cell is a short mono string, while the
    // network cell is a dot + a fixed 28pt number slot + a "KB/s" unit.
    var unboundedWidth: CGFloat = 0
    let stats = HeaderStatKind.normalizedHeaderStats(Defaults[.homeHeaderStats])
    if !stats.isEmpty {
        let cells = stats.reduce(CGFloat(0)) { $0 + $1.headerCellWidthEstimate }
        unboundedWidth = cells + CGFloat(stats.count - 1) * 14
    }

    // Widgets that truncate rather than overflow. A pessimistic estimate for one
    // of these only costs a slightly earlier ellipsis, so they are capped.
    var boundedCandidates: [CGFloat] = []
    // Agents: a provider icon plus its quota badges, per provider shown in the
    // header. Counted rather than assumed, so dropping a provider from the header
    // actually narrows the notch.
    if Defaults[.enableAgentMonitoring] {
        let providers = AgentUsageProviderCatalog
            .normalizedHeaderProviders(Defaults[.agentHeaderProviders])
            .count
        if providers > 0 {
            boundedCandidates.append(CGFloat(providers) * 94 + CGFloat(providers - 1) * 12)
        }
    }
    // Calendar: next-event title, bounded at 160 by `StatCell`'s own truncation.
    if Defaults[.showCalendar] || Defaults[.showReminders] { boundedCandidates.append(160) }
    // Shelf: device name, bounded the same way.
    if Defaults[.dynamicShelf] { boundedCandidates.append(160) }
    if Defaults[.enableWeather] { boundedCandidates.append(100) }
    if Defaults[.enableSystemMonitor] { boundedCandidates.append(60) }

    let boundedWidth = min(boundedCandidates.max() ?? 0, headerContextWidgetWidthCap)
    let widest = max(unboundedWidth, boundedWidth)
    guard widest > 0 else { return 0 }
    // Plus the 8pt minimum gap the widget keeps from the buttons beside it.
    return widest + 8
}

/// Cap for widgets that truncate: `StatCell`'s own 160pt value limit plus room
/// for its eyebrow label.
private let headerContextWidgetWidthCap: CGFloat = 168

/// Returns the recommended minimum notch width for the current tab configuration.
func currentRecommendedMinimumNotchWidth() -> CGFloat {
    recommendedMinimumNotchWidth(forTabCount: enabledStandardTabCount())
}

/// The automatic expanded-notch width for a given tab count. Unlike the
/// "minimum" above (a one-way floor), this scales both up and down so the notch
/// grows when tabs are added and shrinks when they're removed. Floored at a
/// width that still fits the home tab's media + side-panel content.
func autoNotchWidth(forTabCount count: Int) -> CGFloat {
    // Exactly what the header row needs, never less than the Home tab's content
    // floor. Both sides of the header are accounted for, so this shrinks when
    // tabs are removed *and* grows when the trailing side gets denser.
    max(openNotchContentFloorWidth, headerRowMinimumWidth(forTabCount: count))
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
    // `enableLyrics` is the master switch (toggled by the notch lyrics button).
    // Disabling it hides both the open-notch/home lyrics and this closed-notch band.
    guard Defaults[.enableLyrics] else { return false }
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
