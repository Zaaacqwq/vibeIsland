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
import AppKit
import Defaults

/// Visual tokens for the menu-bar Timer popover (Form B in the notch redesign
/// handoff). Shares the dark ink-and-hairline language of the in-notch Timer
/// tab (`NotchDesign`); the few exact hexes the mockup calls out that aren't in
/// the shared ramp live here.
private enum PopoverStyle {
    static let surface = Color(nsColor: NSColor(geistHex: "#161618"))
    static let cardFill = Color.white.opacity(0.05)
    static let cardStroke = Color.white.opacity(0.06)
    static let fieldFill = Color.white.opacity(0.05)
    static let fieldStroke = Color.white.opacity(0.07)
    static let chipFill = Color.white.opacity(0.06)
    static let chipStroke = Color.white.opacity(0.10)
    static let activeCardFill = Color.white.opacity(0.08)
    static let activeCardStroke = Color.white.opacity(0.08)
    static let divider = Color.white.opacity(0.09)
    static let iconTile = Color.white.opacity(0.06)

    static let title = Color(nsColor: NSColor(geistHex: "#F2F2F2"))
    static let value = Color(nsColor: NSColor(geistHex: "#FAFAFA"))
    static let bright = Color(nsColor: NSColor(geistHex: "#CFCFCF"))
    static let muted = Color(nsColor: NSColor(geistHex: "#8A8A8A"))
    static let faint = NotchDesign.Colors.textTertiary // #6E6E6E
    static let danger = NotchDesign.Colors.danger      // #E5645F

    static let cardRadius: CGFloat = 10
    static let controlRadius: CGFloat = 8
    static let quickAddMinutes = [1, 5, 10, 30]
}

struct TimerPopover: View {
    @ObservedObject var timerManager = TimerManager.shared
    @Default(.timerPresets) private var timerPresets
    @Default(.timerShowsProgress) private var showsProgress
    @Default(.timerProgressStyle) private var progressStyle
    @Default(.timerIconColorMode) private var colorMode
    @Default(.timerSolidColor) private var solidColor
    @AppStorage("customTimerDuration") private var customTimerDuration: Double = 600
    @Environment(\.dismiss) private var dismiss

    @State private var customHours: Int = 0
    @State private var customMinutes: Int = 10
    @State private var customSeconds: Int = 0

    private var customDurationInSeconds: TimeInterval {
        TimeInterval(customHours * 3600 + customMinutes * 60 + customSeconds)
    }

    /// The active timer's resolved color (respects the user's color mode), used
    /// for running-state accents. Falls back to the brand accent when idle.
    private var timerAccent: Color {
        switch colorMode {
        case .adaptive: return timerManager.activePreset?.color ?? timerManager.timerColor
        case .solid: return solidColor
        }
    }

    /// Brand accent for idle call-to-action (the "Start Custom Timer" fill),
    /// per the mockup — independent of the timer's progress color.
    private var ctaAccent: Color { NotchDesign.Colors.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if timerManager.isTimerActive {
                activeCard
            } else {
                customTimerCard
                    .onChange(of: customHours) { _, _ in updateStoredCustomDuration() }
                    .onChange(of: customMinutes) { _, _ in updateStoredCustomDuration() }
                    .onChange(of: customSeconds) { _, _ in updateStoredCustomDuration() }
            }

            Rectangle()
                .fill(PopoverStyle.divider)
                .frame(height: 1)

            presets
        }
        .padding(16)
        .frame(width: 300)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                PopoverStyle.surface.opacity(0.92)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
        )
        .onAppear { syncCustomDuration(with: customTimerDuration) }
        .onChange(of: customTimerDuration) { _, newValue in syncCustomDuration(with: newValue) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(timerManager.isTimerActive ? timerAccent.opacity(0.16) : PopoverStyle.iconTile)
                Image(systemName: "timer")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(timerManager.isTimerActive ? timerAccent : Color(nsColor: NSColor(geistHex: "#E6E6E6")))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Timer"))
                    .font(NotchDesign.Typography.voice(14, weight: .semibold))
                    .foregroundStyle(PopoverStyle.title)
                Text(statusText)
                    .font(NotchDesign.Typography.mono(11, weight: .medium))
                    .foregroundStyle(timerManager.isTimerActive ? timerAccent : PopoverStyle.muted)
            }

            Spacer()
        }
    }

    private var statusText: String {
        if timerManager.isOvertime { return String(localized: "Overtime") }
        if timerManager.isPaused { return String(localized: "Paused") }
        if timerManager.isTimerActive { return String(localized: "Running") }
        return String(localized: "Ready")
    }

    // MARK: - Setup state

    private var customTimerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Custom Timer"))
                .font(NotchDesign.Typography.voice(13, weight: .semibold))
                .foregroundStyle(NotchDesign.Colors.textPrimary)

            HStack(spacing: 6) {
                DurationField(title: "h", value: $customHours, range: 0...23)
                DurationField(title: "m", value: $customMinutes, range: 0...59)
                DurationField(title: "s", value: $customSeconds, range: 0...59)
            }

            HStack(spacing: 5) {
                ForEach(PopoverStyle.quickAddMinutes, id: \.self) { minutes in
                    QuickAddChip(minutes: minutes) { addMinutes(minutes) }
                }
                Spacer(minLength: 0)
                Button(action: resetDuration) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PopoverStyle.muted)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(PopoverStyle.chipFill)
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(PopoverStyle.chipStroke, lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                .disabled(customDurationInSeconds == 0)
                .help(String(localized: "Reset"))
            }

            Text(durationCaption)
                .font(NotchDesign.Typography.mono(11, weight: .medium))
                .foregroundStyle(PopoverStyle.muted)

            Button(action: startCustomTimer) {
                HStack(spacing: 7) {
                    Image(systemName: "play.fill").font(.system(size: 11, weight: .semibold))
                    Text("Start Custom Timer").font(NotchDesign.Typography.voice(12, weight: .semibold))
                }
                .foregroundStyle(Color(nsColor: NSColor(geistHex: "#0A0A0A")))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: PopoverStyle.controlRadius, style: .continuous)
                        .fill(ctaAccent.opacity(customDurationInSeconds == 0 ? 0.5 : 1))
                )
            }
            .buttonStyle(.plain)
            .disabled(customDurationInSeconds == 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: PopoverStyle.cardRadius, style: .continuous)
                .fill(PopoverStyle.cardFill)
                .overlay(RoundedRectangle(cornerRadius: PopoverStyle.cardRadius, style: .continuous).strokeBorder(PopoverStyle.cardStroke, lineWidth: 1))
        )
    }

    /// Human-readable summary of the chosen duration, e.g. "10 min", "1h 30m".
    private var durationCaption: String {
        let total = Int(customDurationInSeconds)
        if total == 0 { return String(localized: "No duration set") }
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h)h") }
        if m > 0 { parts.append("\(m)m") }
        if s > 0 { parts.append("\(s)s") }
        return parts.joined(separator: " ")
    }

    // MARK: - Running state

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(timerManager.timerName)
                .font(NotchDesign.Typography.voice(14, weight: .semibold))
                .foregroundStyle(PopoverStyle.title)
                .lineLimit(1)

            Text(timerManager.formattedRemainingTime())
                .font(NotchDesign.Typography.mono(30, weight: .bold))
                .foregroundStyle(timerManager.isOvertime ? PopoverStyle.danger : PopoverStyle.value)
                .contentTransition(.numericText())
                .padding(.top, 8)

            if showsProgress {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 5)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule()
                                .fill(timerAccent)
                                .frame(width: geo.size.width * CGFloat(min(max(timerManager.progress, 0), 1)))
                                .animation(.smooth(duration: 0.25), value: timerManager.progress)
                        }
                    }
                    .padding(.top, 14)
            }

            HStack(spacing: 8) {
                if !timerManager.isOvertime {
                    ActionButton(
                        title: timerManager.isPaused ? String(localized: "Resume") : String(localized: "Pause"),
                        systemImage: timerManager.isPaused ? "play.fill" : "pause.fill",
                        fill: Color.white.opacity(0.09),
                        stroke: Color.white.opacity(0.12),
                        foreground: NotchDesign.Colors.textPrimary,
                        action: togglePause
                    )
                    .disabled(!timerManager.allowsManualInteraction)
                }
                ActionButton(
                    title: String(localized: "Stop"),
                    systemImage: "stop.fill",
                    fill: PopoverStyle.danger,
                    stroke: .clear,
                    foreground: Color(nsColor: NSColor(geistHex: "#0A0A0A")),
                    action: stopTimer
                )
                .disabled(!timerManager.allowsManualInteraction)
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: PopoverStyle.cardRadius, style: .continuous)
                .fill(PopoverStyle.activeCardFill)
                .overlay(RoundedRectangle(cornerRadius: PopoverStyle.cardRadius, style: .continuous).strokeBorder(PopoverStyle.activeCardStroke, lineWidth: 1))
        )
        .animation(.smooth, value: timerManager.isPaused)
    }

    // MARK: - Presets

    private var presets: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Presets"))
                .font(NotchDesign.Typography.voice(12, weight: .semibold))
                .foregroundStyle(PopoverStyle.bright)
                .padding(.leading, 2)

            if timerPresets.isEmpty {
                Text("Configure presets in Settings")
                    .font(NotchDesign.Typography.voice(12))
                    .foregroundStyle(PopoverStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(PopoverStyle.cardFill)
                    )
            } else {
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(timerPresets) { preset in
                            PresetRow(
                                preset: preset,
                                isActive: timerManager.activePresetId == preset.id,
                                accent: timerAccent
                            ) { startPreset(preset) }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .animation(.smooth, value: timerManager.activePresetId)
            }
        }
    }

    // MARK: - Actions (unchanged state machine)

    private func syncCustomDuration(with value: Double) {
        let components = TimerPreset.components(for: value)
        customHours = components.hours
        customMinutes = components.minutes
        customSeconds = components.seconds
    }

    private func updateStoredCustomDuration() {
        customTimerDuration = customDurationInSeconds
    }

    private func addMinutes(_ increment: Int) {
        let maxSeconds = 23 * 3600 + 59 * 60 + 59
        let total = min(Int(customDurationInSeconds) + increment * 60, maxSeconds)
        let components = TimerPreset.components(for: Double(total))
        withAnimation(.smooth(duration: 0.2)) {
            customHours = components.hours
            customMinutes = components.minutes
            customSeconds = components.seconds
        }
    }

    private func resetDuration() {
        withAnimation(.smooth(duration: 0.2)) {
            customHours = 0
            customMinutes = 0
            customSeconds = 0
        }
    }

    private func startCustomTimer() {
        let duration = customDurationInSeconds
        guard duration > 0 else { return }
        withAnimation(.smooth) {
            timerManager.startTimer(duration: duration, name: String(localized: "Custom Timer"))
        }
        dismiss()
    }

    private func startPreset(_ preset: TimerPreset) {
        withAnimation(.smooth) {
            timerManager.startTimer(duration: preset.duration, name: preset.name, preset: preset)
        }
        dismiss()
    }

    private func togglePause() {
        guard timerManager.allowsManualInteraction else { return }
        withAnimation(.smooth) {
            timerManager.isPaused ? timerManager.resumeTimer() : timerManager.pauseTimer()
        }
    }

    private func stopTimer() {
        guard timerManager.allowsManualInteraction else {
            timerManager.endExternalTimer(triggerSmoothClose: false)
            return
        }
        withAnimation(.smooth) { timerManager.stopTimer() }
    }
}

// MARK: - Duration field (mono numeral + chevron stepper)

private struct DurationField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(NotchDesign.Typography.voice(8.5, weight: .medium))
                    .foregroundStyle(PopoverStyle.muted)
                Text("\(value)")
                    .font(NotchDesign.Typography.mono(13, weight: .semibold))
                    .foregroundStyle(PopoverStyle.value)
            }

            Spacer(minLength: 0)

            VStack(spacing: 3) {
                chevron("chevron.up") { step(1) }
                chevron("chevron.down") { step(-1) }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: PopoverStyle.controlRadius, style: .continuous)
                .fill(PopoverStyle.fieldFill)
                .overlay(RoundedRectangle(cornerRadius: PopoverStyle.controlRadius, style: .continuous).strokeBorder(PopoverStyle.fieldStroke, lineWidth: 1))
        )
    }

    private func chevron(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(PopoverStyle.faint)
                .frame(width: 12, height: 9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func step(_ delta: Int) {
        let next = min(max(value + delta, range.lowerBound), range.upperBound)
        withAnimation(.smooth(duration: 0.15)) { value = next }
    }
}

// MARK: - Quick-add chip

private struct QuickAddChip: View {
    let minutes: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: "+\(minutes)m")
                .font(NotchDesign.Typography.voice(11, weight: .medium))
                .foregroundStyle(PopoverStyle.bright)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(PopoverStyle.chipFill)
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(PopoverStyle.chipStroke, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Active card action button

private struct ActionButton: View {
    let title: String
    let systemImage: String
    let fill: Color
    let stroke: Color
    let foreground: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
                Text(title).font(NotchDesign.Typography.voice(12, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: PopoverStyle.controlRadius, style: .continuous)
                    .fill(fill)
                    .overlay(RoundedRectangle(cornerRadius: PopoverStyle.controlRadius, style: .continuous).strokeBorder(stroke, lineWidth: 1))
            )
            .contentShape(RoundedRectangle(cornerRadius: PopoverStyle.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preset row

private struct PresetRow: View {
    let preset: TimerPreset
    let isActive: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Circle()
                    .fill(preset.color)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.name)
                        .font(NotchDesign.Typography.voice(12, weight: .medium))
                        .foregroundStyle(NotchDesign.Colors.textPrimary)
                        .lineLimit(1)
                    Text(preset.formattedDuration)
                        .font(NotchDesign.Typography.mono(10, weight: .medium))
                        .foregroundStyle(PopoverStyle.muted)
                }

                Spacer(minLength: 0)

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(accent.opacity(0.25)))
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PopoverStyle.faint)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive ? accent.opacity(0.18) : PopoverStyle.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(isActive ? accent.opacity(0.35) : Color.clear, lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TimerPopover()
        .padding(40)
        .background(Color.black)
}
