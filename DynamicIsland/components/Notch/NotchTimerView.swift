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

import SwiftUI
import Defaults
#if canImport(AppKit)
import AppKit
#endif

/// Shared visual tokens for the in-notch Timer tab. Notch-native (dark glass,
/// white text, accent-driven) — intentionally separate from the Geist settings
/// design system.
private enum TimerStyle {
    static let cardFill = NotchDesign.Colors.cardFill
    static let cardStroke = NotchDesign.Colors.hairline
    static let fieldFill = NotchDesign.Colors.sunken
    static let controlFill = NotchDesign.Colors.cardFillRaised
    static let chipFill = Color.white.opacity(0.06)
    static let muted = NotchDesign.Colors.textTertiary

    static let cardRadius = NotchDesign.Radius.xl
    static let controlRadius = NotchDesign.Radius.md
    static let controlSize: CGFloat = 36

    static let startGreen = NotchDesign.Colors.success

    /// Quick-add increments (minutes) offered when no presets are shown.
    static let quickAddMinutes: [Int] = [1, 5, 10, 30]
}

struct NotchTimerView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var timerManager = TimerManager.shared
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.enableMinimalisticUI) private var enableMinimalisticUI
    @Default(.timerPresets) private var timerPresets
    @Default(.timerIconColorMode) private var colorMode
    @Default(.timerSolidColor) private var solidColor
    @Default(.timerShowsProgress) private var showsProgress
    @Default(.timerProgressStyle) private var progressStyle
    @Default(.showTimerPresetsInNotchTab) private var showTimerPresetsInNotchTab

    @AppStorage("customTimerDuration") private var customTimerDuration: Double = 600
    @State private var customHours: Int = 0
    @State private var customMinutes: Int = 10
    @State private var customSeconds: Int = 0
    @State private var isSyncingCustomDuration = false
    @State private var lockedAccentColor: Color?
    // Suppress the notch's scroll-to-close gesture while hovering the preset
    // strip, so left/right scrolling browses presets instead of closing.
    @State private var presetScrollSuppressionToken = UUID()

    var body: some View {
        Group {
            if enableTimerFeature {
                content
                    // Uniform tab insets + height budget come from the shared tab
                    // container in ContentView (`NotchDesign.TabInset`); fill it.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    // No root `.transition`: the tab switcher owns the directional
                    // slide; a blur transition here would override it.
                    .onAppear { syncCustomDuration(with: customTimerDuration) }
                    .onChange(of: customTimerDuration) { _, newValue in syncCustomDuration(with: newValue) }
                    .onChange(of: customHours) { _, _ in updateStoredCustomDuration() }
                    .onChange(of: customMinutes) { _, _ in updateStoredCustomDuration() }
                    .onChange(of: customSeconds) { _, _ in updateStoredCustomDuration() }
            } else {
                disabledState
            }
        }
        .onAppear { lockAccentColorIfNeeded() }
        .onChange(of: timerManager.isTimerActive) { _, isActive in
            if isActive { lockAccentColorIfNeeded() } else { lockedAccentColor = nil }
        }
        .onChange(of: timerManager.activePresetId) { _, _ in
            if timerManager.isTimerActive && lockedAccentColor == nil { lockAccentColorIfNeeded() }
        }
    }

    private var content: some View {
        ZStack(alignment: .top) {
            if timerManager.isTimerActive {
                activeTimerCard
                    .id("timer-active")
                    .transition(timerStateTransition)
            } else {
                idleComposer
                    .id("timer-idle")
                    .transition(timerStateTransition)
            }
        }
        // Match the ambient `.smooth` that TimerManager.startTimer uses when it
        // flips `isTimerActive` (which drives the window/tab resize). Sharing one
        // curve keeps the countdown travelling with the card instead of settling
        // on a faster timeline than the frame around it.
        .animation(.smooth, value: timerManager.isTimerActive)
    }

    private var timerStateTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: - Idle

    private var idleComposer: some View {
        VStack(alignment: .leading, spacing: 9) {
            inputSection
                .frame(maxWidth: .infinity)

            bottomChipRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                NotchMonoEyebrow(text: "Set duration")
                Spacer()
                Text(formattedCustomDuration)
                    .font(NotchDesign.Typography.mono(10, weight: .medium))
                    .foregroundStyle(NotchDesign.Colors.textFaint)
            }

            HStack(alignment: .center, spacing: 10) {
                DurationInputRow(
                    hours: $customHours,
                    minutes: $customMinutes,
                    seconds: $customSeconds
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                startButton
                    .frame(width: 108)
                resetButton
            }
        }
        .padding(10)
        .background(card)
    }

    /// Bottom band. With presets shown: presets on the left, quick-add chips on
    /// the right. Without presets: quick-add chips fill the row.
    @ViewBuilder
    private var bottomChipRow: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 12) {
                if showTimerPresetsInNotchTab {
                    // Presets stay on a single row, capped at half the notch width;
                    // overflow scrolls horizontally (see presetChipsArea).
                    presetChipsArea
                        .frame(maxWidth: geo.size.width * 0.5, alignment: .leading)
                    Spacer(minLength: 0)
                    quickAddChips
                } else {
                    quickAddChips
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 30)
    }

    @ViewBuilder
    private var presetChipsArea: some View {
        if timerPresets.isEmpty {
            Text("Configure presets in Settings to see them here.")
                .font(.system(size: 12))
                .foregroundStyle(TimerStyle.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(timerPresets) { preset in
                        TimerPresetChip(preset: preset, isActive: timerManager.activePresetId == preset.id) {
                            timerManager.startTimer(duration: preset.duration, name: preset.name, preset: preset)
                            if !enableMinimalisticUI { coordinator.currentView = .timer }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            // Fade the chips out at both ends of the scroll (the band sits on the
            // black notch panel, so fade to black).
            .overlay(alignment: .leading) { presetEdgeFade(leading: true) }
            .overlay(alignment: .trailing) { presetEdgeFade(leading: false) }
            .onHover { hovering in
                vm.setScrollGestureSuppression(hovering, token: presetScrollSuppressionToken)
                vm.setTabSwitchSuppression(hovering, token: presetScrollSuppressionToken)
            }
            .onDisappear {
                vm.setScrollGestureSuppression(false, token: presetScrollSuppressionToken)
                vm.setTabSwitchSuppression(false, token: presetScrollSuppressionToken)
            }
        }
    }

    private func presetEdgeFade(leading: Bool) -> some View {
        LinearGradient(
            colors: leading ? [Color.black, .clear] : [.clear, Color.black],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(width: 16)
        .allowsHitTesting(false)
    }

    private var quickAddChips: some View {
        HStack(spacing: 8) {
            ForEach(TimerStyle.quickAddMinutes, id: \.self) { minutes in
                QuickAddChip(minutes: minutes, tint: timerAccentColor) { addQuickMinutes(minutes) }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Active

    private var activeTimerCard: some View {
        HStack(alignment: .center, spacing: 14) {
            heroCountdown

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    NotchMonoEyebrow(text: "Running")
                    if let status = timerStatusText {
                        statusBadge(status)
                    }
                }

                MarqueeText(
                    .constant(timerDisplayName),
                    font: NotchDesign.Typography.voice(17, weight: .semibold),
                    nsFont: .title3,
                    textColor: NotchDesign.Colors.textPrimary,
                    minDuration: 0.2,
                    frameWidth: 220
                )
                .foregroundStyle(NotchDesign.Colors.textPrimary)
                .frame(height: 24, alignment: .leading)

                progressBar
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            controlCluster
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(card)
        // Resolve the whole card's geometry as one unit before the tab's `.move`
        // transition offsets it. Its observable-driven children (countdown ring,
        // marquee name) each re-render mid-transition; without this they snap to
        // their final position and "appear in place" while the card slides in.
        .geometryGroup()
    }

    @ViewBuilder
    private var controlCluster: some View {
        if timerManager.allowsManualInteraction {
            HStack(spacing: 10) {
                if !timerManager.isOvertime {
                    TimerControlButton(
                        icon: pauseIconName,
                        background: timerAccentColor.opacity(0.32),
                        accessibilityLabel: pauseAccessibilityLabel,
                        action: togglePauseAction
                    )
                    TimerControlButton(
                        icon: "xmark",
                        background: TimerStyle.controlFill,
                        accessibilityLabel: String(localized: "Cancel"),
                        action: stopTimerAction
                    )
                } else {
                    TimerControlButton(
                        icon: "stop.fill",
                        background: TimerStyle.controlFill,
                        accessibilityLabel: String(localized: "Stop"),
                        action: stopTimerAction
                    )
                }
            }
        } else {
            Color.clear.frame(width: TimerStyle.controlSize, height: TimerStyle.controlSize)
        }
    }

    @ViewBuilder
    private var heroCountdown: some View {
        if showsProgress && progressStyle == .ring {
            TimerProgressRing(
                progress: timerManager.progress,
                tint: timerAccentColor,
                timeText: timerManager.formattedRemainingTime(),
                isOvertime: timerManager.isOvertime,
                remainingTime: timerManager.remainingTime
            )
        } else {
            Text(timerManager.formattedRemainingTime())
                .font(.system(size: 40, weight: .black, design: .monospaced))
                .foregroundStyle(timerManager.isOvertime ? Color.red : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(alignment: .trailing)
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        if showsProgress && progressStyle == .bar {
            Capsule()
                .fill(Color.white.opacity(0.12))
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(timerAccentColor)
                            .frame(width: geo.size.width * normalizedProgress, height: 5)
                            .animation(.smooth(duration: 0.25), value: timerManager.progress)
                    }
                }
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Disabled

    private var disabledState: some View {
        VStack(spacing: 16) {
            Image(systemName: "timer.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Timer Disabled")
                .font(.title2)
                .fontWeight(.medium)
            Text("Enable the timer feature in Settings to access this tab.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Buttons

    private var startButton: some View {
        Button(action: startCustomTimer) {
            Label(String(localized: "Start"), systemImage: "play.fill")
                .font(NotchDesign.Typography.voice(13, weight: .semibold))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: TimerStyle.controlRadius, style: .continuous)
                        .fill(TimerStyle.startGreen.opacity(isStartDisabled ? 0.5 : 1))
                )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: TimerStyle.controlRadius, style: .continuous))
        .opacity(isStartDisabled ? 0.7 : 1)
        .disabled(isStartDisabled)
    }

    private var resetButton: some View {
        Button(action: resetCustomTimerInputs) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchDesign.Colors.textSecondary)
                .frame(width: 38, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: TimerStyle.controlRadius, style: .continuous)
                        .fill(TimerStyle.controlFill)
                )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: TimerStyle.controlRadius, style: .continuous))
        .help(String(localized: "Reset"))
    }

    // MARK: - Surfaces

    private var card: some View {
        RoundedRectangle(cornerRadius: TimerStyle.cardRadius, style: .continuous)
            .fill(TimerStyle.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: TimerStyle.cardRadius, style: .continuous)
                    .stroke(TimerStyle.cardStroke, lineWidth: 1)
            )
    }

    private func statusBadge(_ text: String) -> some View {
        Text(text)
            .font(NotchDesign.Typography.mono(10, weight: .medium))
            .foregroundStyle(timerStatusColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(timerStatusColor.opacity(0.18))
            .clipShape(Capsule())
    }

    // MARK: - Actions

    private func togglePauseAction() {
        guard timerManager.allowsManualInteraction else { return }
        timerManager.isPaused ? timerManager.resumeTimer() : timerManager.pauseTimer()
    }

    private func stopTimerAction() {
        if timerManager.allowsManualInteraction {
            timerManager.stopTimer()
        } else {
            timerManager.endExternalTimer(triggerSmoothClose: false)
        }
    }

    private func startCustomTimer() {
        withAnimation(.smooth) {
            timerManager.startTimer(duration: customDurationInSeconds, name: String(localized: "Custom Timer"))
            if !enableMinimalisticUI { coordinator.currentView = .timer }
        }
    }

    private func resetCustomTimerInputs() {
        withAnimation(.smooth(duration: 0.2)) {
            customHours = 0
            customMinutes = 0
            customSeconds = 0
        }
        customTimerDuration = 0
    }

    private func addQuickMinutes(_ minutes: Int) {
        let maxSeconds = Double(23 * 3600 + 59 * 60 + 59)
        let total = min(customDurationInSeconds + Double(minutes * 60), maxSeconds)
        withAnimation(.smooth(duration: 0.2)) {
            customTimerDuration = total
        }
    }

    private func syncCustomDuration(with value: Double) {
        isSyncingCustomDuration = true
        let components = TimerPreset.components(for: value)
        customHours = components.hours
        customMinutes = components.minutes
        customSeconds = components.seconds
        isSyncingCustomDuration = false
    }

    private func updateStoredCustomDuration() {
        guard !isSyncingCustomDuration else { return }
        customTimerDuration = customDurationInSeconds
    }

    // MARK: - Derived values

    private func lockAccentColorIfNeeded() {
        if timerManager.isTimerActive { lockedAccentColor = resolvedAccentColor }
    }

    private var timerAccentColor: Color { lockedAccentColor ?? resolvedAccentColor }

    private var resolvedAccentColor: Color {
        switch colorMode {
        case .adaptive:
            return timerManager.activePreset?.color ?? timerManager.timerColor
        case .solid:
            return solidColor
        }
    }

    private var normalizedProgress: CGFloat { CGFloat(max(0, min(timerManager.progress, 1))) }

    private var timerDisplayName: String {
        timerManager.timerName.isEmpty ? "Timer" : timerManager.timerName
    }

    private var timerStatusText: String? {
        if timerManager.isOvertime { return String(localized: "Overtime") }
        if timerManager.isPaused { return String(localized: "Paused") }
        if timerManager.isFinished { return "Completed" }
        return nil
    }

    private var timerStatusColor: Color {
        timerManager.isOvertime ? .red : timerAccentColor
    }

    private var pauseIconName: String { timerManager.isPaused ? "play.fill" : "pause.fill" }

    private var pauseAccessibilityLabel: String {
        timerManager.isPaused ? String(localized: "Resume") : String(localized: "Pause")
    }

    private var isStartDisabled: Bool { customDurationInSeconds == 0 }

    private var customDurationInSeconds: TimeInterval {
        TimeInterval(customHours * 3600 + customMinutes * 60 + customSeconds)
    }

    private var formattedCustomDuration: String {
        let total = Int(customDurationInSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Control button

private struct TimerControlButton: View {
    let icon: String
    var foreground: Color = .white.opacity(0.95)
    let background: Color
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: TimerStyle.controlSize, height: TimerStyle.controlSize)
                .background(background.opacity(isHovering ? 1 : 0.85))
                .clipShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .help(accessibilityLabel)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Progress ring

private struct TimerProgressRing: View {
    let progress: Double
    let tint: Color
    let timeText: String
    let isOvertime: Bool
    let remainingTime: TimeInterval

    private var clampedProgress: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 6)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.3), value: clampedProgress)
            Text(timeText)
                .font(NotchDesign.Typography.mono(20, weight: .semibold))
                .foregroundStyle(isOvertime ? Color.red : .white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(width: 84, height: 84)
    }
}

// MARK: - Duration input

private struct DurationInputRow: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var seconds: Int
    var fieldWidth: CGFloat = 54

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            DurationField(label: String(localized: "Hours"), value: $hours, range: 0...23, width: fieldWidth)
            colon
            DurationField(label: String(localized: "Minutes"), value: $minutes, range: 0...59, width: fieldWidth)
            colon
            DurationField(label: String(localized: "Seconds"), value: $seconds, range: 0...59, width: fieldWidth)
        }
    }

    private var colon: some View {
        Text(":")
            .font(NotchDesign.Typography.mono(20, weight: .semibold))
            .foregroundStyle(TimerStyle.muted)
            .padding(.bottom, 14)
    }
}

private struct DurationField: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var width: CGFloat = 62

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                // Display layer: a plain SwiftUI Text centers perfectly in the box
                // (unlike NSTextField, which top-aligns its line box). The digits
                // shown here are always the committed value, so they stay centered.
                Text(String(format: "%02d", value))
                    .font(NotchDesign.Typography.mono(22, weight: .semibold))
                    .foregroundColor(.white)

                // Input layer: an invisible TextField on top captures typing. Its
                // own glyphs are clear (the centered Text above is what you see);
                // the tint keeps a visible caret while editing.
                TextField("", text: binding)
                    .font(NotchDesign.Typography.mono(22, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .foregroundColor(.clear)
                    .tint(.white)
                    .lineLimit(1)
            }
            .frame(width: width, height: 38)
            // Background fill (not a clipShape) so tall glyphs are never clipped.
            .background(
                RoundedRectangle(cornerRadius: TimerStyle.controlRadius, style: .continuous)
                    .fill(TimerStyle.fieldFill)
            )

            Text(label)
                .font(NotchDesign.Typography.mono(9))
                .foregroundStyle(TimerStyle.muted)
        }
    }

    private var binding: Binding<String> {
        Binding<String>(
            get: { String(format: "%02d", value) },
            set: { newValue in
                let digits = newValue.filter { $0.isNumber }
                let number = min(max(range.lowerBound, Int(digits) ?? 0), range.upperBound)
                value = number
            }
        )
    }
}

// MARK: - Quick-add chip

private struct QuickAddChip: View {
    let minutes: Int
    let tint: Color
    let action: () -> Void

    @State private var isHovering = false

    private var label: String { "+\(minutes)m" }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(NotchDesign.Typography.mono(11, weight: .medium))
                .foregroundStyle(NotchDesign.Colors.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isHovering ? tint.opacity(0.45) : TimerStyle.chipFill)
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Preset chip

private struct TimerPresetChip: View {
    let preset: TimerPreset
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(preset.color)
                    .frame(width: 8, height: 8)

                // Name + duration inline on a single line (was stacked two rows).
                Text(preset.name)
                    .font(NotchDesign.Typography.voice(11, weight: .medium))
                    .foregroundStyle(NotchDesign.Colors.textPrimary)
                    .lineLimit(1)
                Text(preset.formattedDuration)
                    .font(NotchDesign.Typography.mono(9, weight: .medium))
                    .foregroundStyle(TimerStyle.muted)
                    .lineLimit(1)
            }
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isActive ? preset.color.opacity(0.22) : (isHovering ? Color.white.opacity(0.12) : TimerStyle.chipFill))
            )
            .overlay(
                Capsule().stroke(isActive ? preset.color.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

#Preview {
    NotchTimerView()
        .environmentObject(DynamicIslandViewModel())
        .frame(width: 600, height: 200)
        .background(.black)
}
