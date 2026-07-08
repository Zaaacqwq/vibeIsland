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

struct DynamicIslandHeader: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var shelfState = ShelfStateViewModel.shared
    @ObservedObject var timerManager = TimerManager.shared
    @ObservedObject var doNotDisturbManager = DoNotDisturbManager.shared
    @State private var showTimerPopover = false
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.timerDisplayMode) var timerDisplayMode
    @Default(.showBatteryIndicator) var showBatteryIndicator
    @Default(.showBatteryPercentInside) var showBatteryPercentInside
    @Default(.enableMinimalisticUI) var enableMinimalisticUI

    /// When the notch is open and a brightness/volume/backlight HUD is peeking,
    /// it temporarily replaces the header context widget (stats/usage/next event/
    /// device name) with a compact level bar, fading in and out.
    private var headerSystemHUDActive: Bool {
        vm.notchState == .open
            && coordinator.sneakPeek.show
            && [.brightness, .volume, .backlight].contains(coordinator.sneakPeek.type)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if !enableMinimalisticUI {
                    let shouldShowTabs = coordinator.alwaysShowTabs || vm.notchState == .open || !shelfState.items.isEmpty
                    if shouldShowTabs {
                        TabSelectionView()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.1), value: vm.notchState)
            .zIndex(2)
            .padding(8)

            if vm.notchState == .open {
                let spacerWidth = min(vm.closedNotchSize.width, 300)
                Rectangle()
                    .fill(enableMinimalisticUI ? .clear : (NSScreen.screens
                        .first(where: { $0.localizedName == coordinator.selectedScreen })?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear))
                    .frame(width: spacerWidth)
                    .mask {
                        NotchShape()
                    }
            }

            HStack(spacing: 4) {
                if vm.notchState == .open && !enableMinimalisticUI {
                    let showContext = Defaults[.showHeaderContextWidgets]
                    if headerSystemHUDActive || showContext {
                        ZStack {
                            if headerSystemHUDActive {
                                HeaderSystemHUD(
                                    icon: coordinator.sneakPeek.icon,
                                    type: coordinator.sneakPeek.type,
                                    value: coordinator.sneakPeek.value,
                                    accent: coordinator.sneakPeek.accentColor
                                )
                                .transition(.opacity)
                            } else {
                                NotchHeaderContextWidget()
                                    .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.25), value: headerSystemHUDActive)
                        Spacer(minLength: 8)
                    }
                }

                if vm.notchState == .open && !enableMinimalisticUI {
                    if Defaults[.enableTimerFeature] && timerDisplayMode == .popover {
                        Button(action: {
                            withAnimation(.smooth) {
                                showTimerPopover.toggle()
                            }
                        }) {
                            Image(systemName: "timer")
                                .foregroundColor(NotchDesign.Colors.textTertiary)
                                .frame(width: 30, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .popover(isPresented: $showTimerPopover, arrowEdge: .bottom) {
                            TimerPopover()
                        }
                        .onChange(of: showTimerPopover) { isActive in
                            vm.isTimerPopoverActive = isActive
                            if !isActive {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    vm.shouldRecheckHover.toggle()
                                }
                            }
                        }
                    }
                    
                    if Defaults[.settingsIconInNotch] {
                        Button(action: {
                            SettingsWindowController.shared.showWindow()
                        }) {
                            Image(systemName: "gear")
                                .foregroundColor(NotchDesign.Colors.textTertiary)
                                .frame(width: 30, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Screen Recording Indicator
                    if Defaults[.enableScreenRecordingDetection] && Defaults[.showRecordingIndicator] && !shouldSuppressStatusIndicators {
                        RecordingIndicator()
                            .frame(width: 30, height: 30) // Same size as other header elements
                    }

                    if Defaults[.enableDoNotDisturbDetection]
                        && Defaults[.showDoNotDisturbIndicator]
                        && doNotDisturbManager.isDoNotDisturbActive
                        && !shouldSuppressStatusIndicators {
                        FocusIndicator()
                            .frame(width: 30, height: 30)
                            .transition(.opacity)
                    }
                }

                if vm.notchState == .open && showBatteryIndicator {
                    if enableMinimalisticUI {
                        MinimalisticBatteryView(
                            levelBattery: batteryModel.levelBattery,
                            isPluggedIn: batteryModel.isPluggedIn,
                            isCharging: batteryModel.isCharging,
                            isInLowPowerMode: batteryModel.isInLowPowerMode,
                            bodyWidth: 28,
                            bodyHeight: 14,
                            isForNotification: false,
                            showPercentInside: showBatteryPercentInside
                        )
                        .padding(.trailing, 4)
                    } else {
                        DynamicIslandBatteryView(
                            batteryWidth: 30,
                            isCharging: batteryModel.isCharging,
                            isInLowPowerMode: batteryModel.isInLowPowerMode,
                            isPluggedIn: batteryModel.isPluggedIn,
                            levelBattery: batteryModel.levelBattery,
                            maxCapacity: batteryModel.maxCapacity,
                            timeToFullCharge: batteryModel.timeToFullCharge,
                            isForNotification: false
                        )
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.1), value: vm.notchState)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
        .onChange(of: enableTimerFeature) { _, newValue in
            if !newValue {
                showTimerPopover = false
                vm.isTimerPopoverActive = false
            }
        }
        .onChange(of: timerDisplayMode) { _, mode in
            if mode == .tab {
                showTimerPopover = false
                vm.isTimerPopoverActive = false
            }
        }
    }
}

private extension DynamicIslandHeader {
    var shouldSuppressStatusIndicators: Bool {
        Defaults[.settingsIconInNotch]
            && Defaults[.enableTimerFeature]
    }
}

/// Compact volume/brightness level shown in the open-notch header (icon + bar)
/// in place of the tab context widget while a system HUD is peeking.
private struct HeaderSystemHUD: View {
    let icon: String
    let type: SneakContentType
    let value: CGFloat
    let accent: Color?

    /// The sneak-peek `icon` is often empty for brightness/backlight, so fall
    /// back to a type-appropriate glyph rather than a hardcoded speaker.
    private var resolvedIcon: String {
        if !icon.isEmpty { return icon }
        switch type {
        case .brightness: return "sun.max.fill"
        case .backlight: return "keyboard"
        case .volume: return value <= 0 ? "speaker.slash.fill" : "speaker.wave.2.fill"
        default: return "speaker.wave.2.fill"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: resolvedIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchDesign.Colors.textPrimary)
                .frame(width: 16)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule()
                        .fill(accent ?? NotchDesign.Colors.textPrimary)
                        .frame(width: max(2, geo.size.width * min(max(value, 0), 1)))
                }
            }
            .frame(width: 84, height: 4)
        }
        .frame(height: 30)
        .padding(.leading, 2)
    }
}

#Preview {
    DynamicIslandHeader()
        .environmentObject(DynamicIslandViewModel())
}
