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
    @State private var showColorPickerPopover = false
    @State private var showClipboardPopover = false
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.timerDisplayMode) var timerDisplayMode
    @Default(.enableColorPicker) var enableColorPicker
    @Default(.colorPickerDisplayMode) var colorPickerDisplayMode
    @Default(.enableClipboardManager) var enableClipboardManager
    @Default(.clipboardDisplayMode) var clipboardDisplayMode
    @Default(.showBatteryIndicator) var showBatteryIndicator
    @Default(.showBatteryPercentInside) var showBatteryPercentInside
    @Default(.enableMinimalisticUI) var enableMinimalisticUI

    /// When the notch is open and a system HUD is peeking, it temporarily
    /// replaces the header context widget (stats/usage/next event/device name),
    /// fading in and out.
    ///
    /// Which peeks qualify is declared on the peek itself — see
    /// `sneakPeek.showsInsideOpenNotchHeader`. As full-width peeks they displaced
    /// the header and stretched the notch, and none of them is worth resizing the
    /// window for.
    private var headerSystemHUDActive: Bool {
        vm.notchState == .open
            && coordinator.sneakPeek.show
            && coordinator.sneakPeek.showsInsideOpenNotchHeader
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
            // MUST stay greedy. This group and the trailing one split the window
            // evenly, which is the only thing centering the black spacer between
            // them on the physical notch cutout. Sizing this group to its content
            // instead moves that spacer left by (half − tab row) and parks the
            // trailing widgets *behind* the notch, where they are invisible on
            // device — a screenshot still shows them, because `screencapture`
            // reads the framebuffer under the cutout.
            //
            // The consequence is that dead space between the last tab and the
            // cutout is unavoidable whenever the trailing side is the wider of
            // the two; `headerRowMinimumWidth` sizes the window so it is no wider
            // than it has to be.
            .frame(maxWidth: .infinity, alignment: .leading)
            // Wins space over the trailing group, whose context widget is built
            // to truncate. Tab icons are fixed-size and would otherwise be
            // clipped when the notch cannot satisfy both sides (a display too
            // small for `headerRowMinimumWidth`).
            .layoutPriority(1)
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
                    
                    if enableColorPicker && colorPickerDisplayMode == .popover {
                        HeaderToolPopoverButton(
                            systemImage: "eyedropper",
                            help: String(localized: "Color Picker"),
                            isPresented: $showColorPickerPopover,
                            isActive: $vm.isColorPickerPopoverActive,
                            onDismissed: { vm.shouldRecheckHover.toggle() }
                        ) {
                            ColorPickerPopover()
                        }
                    }

                    if enableClipboardManager && clipboardDisplayMode == .popover {
                        HeaderToolPopoverButton(
                            systemImage: "doc.on.clipboard",
                            help: String(localized: "Clipboard"),
                            isPresented: $showClipboardPopover,
                            isActive: $vm.isClipboardPopoverActive,
                            onDismissed: { vm.shouldRecheckHover.toggle() }
                        ) {
                            ClipboardPopover()
                                .environmentObject(vm)
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
        // A tool switched to tab mode (or switched off) must not leave its
        // popover on screen — the button it was anchored to is gone.
        .onChange(of: enableColorPicker) { _, isOn in
            if !isOn { dismissColorPickerPopover() }
        }
        .onChange(of: colorPickerDisplayMode) { _, mode in
            if mode == .tab { dismissColorPickerPopover() }
        }
        .onChange(of: enableClipboardManager) { _, isOn in
            if !isOn { dismissClipboardPopover() }
        }
        .onChange(of: clipboardDisplayMode) { _, mode in
            if mode == .tab { dismissClipboardPopover() }
        }
        // Three entry points, because the request can land before this view even
        // exists: the header is mounted as part of opening the notch, so a
        // request parked by the hotkey just before `open()` is already stale by
        // the time `onChange` could observe it. `onAppear` covers that case,
        // `onChange` covers a hotkey pressed while the notch is already open.
        .onAppear {
            applyRequestedToolPopover(coordinator.requestedToolPopover)
        }
        .onChange(of: coordinator.requestedToolPopover) { _, request in
            applyRequestedToolPopover(request)
        }
        .onChange(of: vm.notchState) { _, _ in
            applyRequestedToolPopover(coordinator.requestedToolPopover)
        }
    }

    /// Presents the popover a hotkey asked for, once this header actually has the
    /// button to anchor it to. Only the screen whose notch opened responds, so on
    /// a multi-display setup the popover does not appear on every notch.
    private func applyRequestedToolPopover(_ request: NotchViews?) {
        guard let request, vm.notchState == .open, !enableMinimalisticUI else { return }
        coordinator.requestedToolPopover = nil

        // One run-loop hop so the button exists in the layout before SwiftUI is
        // asked to anchor a popover to it.
        DispatchQueue.main.async {
            // A popover needs a key window, and a global hotkey does not
            // activate us — without this the notch opens and nothing else
            // happens. Activating is also what lets the clipboard's search
            // field accept typing; pasting still targets the app the user came
            // from, which `ClipboardPaster` tracks separately.
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0 is DynamicIslandWindow }?.makeKeyAndOrderFront(nil)

            switch request {
            case .clipboard:
                guard enableClipboardManager, clipboardDisplayMode == .popover else { return }
                showClipboardPopover = true
            case .colorPicker:
                guard enableColorPicker, colorPickerDisplayMode == .popover else { return }
                showColorPickerPopover = true
            default:
                break
            }
        }
    }

    private func dismissColorPickerPopover() {
        showColorPickerPopover = false
        vm.isColorPickerPopoverActive = false
    }

    private func dismissClipboardPopover() {
        showClipboardPopover = false
        vm.isClipboardPopoverActive = false
    }
}

/// The notch header's popover-mode tool button: a 30×30 glyph that toggles a
/// popover and mirrors its presentation into the view model, so the notch does
/// not auto-close while the popover is up.
///
/// Extracted because each utility tool in popover mode needs exactly this, and
/// the hover-recheck-after-dismiss detail is easy to omit when copy-pasting.
struct HeaderToolPopoverButton<Content: View>: View {
    let systemImage: String
    let help: String
    @Binding var isPresented: Bool
    @Binding var isActive: Bool
    let onDismissed: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button {
            withAnimation(.smooth) {
                isPresented.toggle()
            }
        } label: {
            Image(systemName: systemImage)
                .foregroundColor(NotchDesign.Colors.textTertiary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .help(help)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            content()
        }
        .onChange(of: isPresented) { presented in
            isActive = presented
            if !presented {
                // The hover state is stale for a moment after the popover's
                // window goes away; re-check just after it does.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    onDismissed()
                }
            }
        }
    }
}

private extension DynamicIslandHeader {
    /// The trailing header row runs out of room once the gear shares it with the
    /// tool buttons, so the optional status glyphs step aside.
    ///
    /// Defined in `matters.swift` so the notch-width budget applies the identical
    /// rule — reserving width for a glyph this hides would pad the notch for
    /// nothing.
    var shouldSuppressStatusIndicators: Bool {
        notchHeaderSuppressesStatusIndicators()
    }
}

/// Compact system HUD shown in the open-notch header in place of the tab
/// context widget while a peek is active.
///
/// Two shapes: a level bar for the continuous values (volume, brightness,
/// keyboard backlight) and a text label for the discrete states (caps lock,
/// input source), which have no level to draw.
private struct HeaderSystemHUD: View {
    let icon: String
    let type: SneakContentType
    let value: CGFloat
    let accent: Color?

    @Default(.capsLockIndicatorTintMode) private var capsLockTintMode
    @Default(.showCapsLockLabel) private var showCapsLockLabel
    @ObservedObject private var inputSourceManager = InputSourceManager.shared

    /// A level bar only makes sense for a continuous value. The state peeks —
    /// caps lock, input source, AirPods listening mode — carry no level (the
    /// listening-mode peek even reports a negative value), so they render as a
    /// label instead.
    private var isLevel: Bool {
        ![.capsLock, .inputSource, .bluetoothAudio].contains(type)
    }

    /// The sneak-peek `icon` is often empty for brightness/backlight, so fall
    /// back to a type-appropriate glyph rather than a hardcoded speaker. The
    /// state types always use their own glyph — the peek's icon carries a
    /// different meaning for them.
    private var resolvedIcon: String {
        switch type {
        case .capsLock: return "capslock.fill"
        case .inputSource: return "keyboard"
        case .brightness: return icon.isEmpty ? "sun.max.fill" : icon
        case .backlight: return icon.isEmpty ? "keyboard" : icon
        case .volume:
            if !icon.isEmpty { return icon }
            return value <= 0 ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .bluetoothAudio:
            // The peek's icon *is* the listening mode, so keep it.
            return AirPodsListeningMode.fromHUDSymbol(icon)?.sfSymbol ?? "airpods.pro"
        default: return icon.isEmpty ? "speaker.wave.2.fill" : icon
        }
    }

    private var tint: Color {
        type == .capsLock ? capsLockTintMode.color : NotchDesign.Colors.textPrimary
    }

    /// Nil keeps the row icon-only — which is what Caps Lock does when its
    /// label is switched off in settings.
    private var label: String? {
        switch type {
        case .inputSource:
            let name = inputSourceManager.currentSourceName
            return name.isEmpty ? nil : name
        case .capsLock:
            return showCapsLockLabel ? String(localized: "Caps Lock") : nil
        case .bluetoothAudio:
            return AirPodsListeningMode.fromHUDSymbol(icon)?.displayName
        default:
            return nil
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: resolvedIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
                .contentTransition(.interpolate)

            if isLevel {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule()
                            .fill(accent ?? NotchDesign.Colors.textPrimary)
                            .frame(width: max(2, geo.size.width * min(max(value, 0), 1)))
                    }
                }
                .frame(width: 84, height: 4)
            } else if let label {
                // Bounded so a long input-source name truncates instead of
                // pushing the trailing timer/settings controls off-screen.
                Text(label)
                    .font(NotchDesign.Typography.voice(12, weight: .medium))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 170, alignment: .leading)
                    .contentTransition(.interpolate)
            }
        }
        .frame(height: 30)
        .padding(.leading, 2)
    }
}

#Preview {
    DynamicIslandHeader()
        .environmentObject(DynamicIslandViewModel())
}
