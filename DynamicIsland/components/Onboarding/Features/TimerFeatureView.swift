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

/// Timer setup page: manage the quick-start presets (seeded with three
/// defaults) — add, edit, or delete.
struct TimerFeatureView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onBack: () -> Void

    @Default(.timerPresets) private var presets
    @State private var editing: TimerPreset?
    @State private var isAdding = false

    var body: some View {
        OnboardingScaffold(
            symbol: OnboardingFeature.timer.symbol,
            gradient: OnboardingFeature.timer.gradient,
            title: String(localized: "Timer presets"),
            subtitle: String(localized: "Tune your quick-start presets. Add, edit, or remove any of them."),
            onBack: onBack,
            onSkip: onSkip,
            onContinue: onContinue
        ) {
            VStack(spacing: 8) {
                ForEach(presets) { preset in
                    presetRow(preset)
                }

                Button {
                    isAdding = true
                } label: {
                    Label("Add preset", systemImage: "plus.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.gray.opacity(0.08))
                )
                .padding(.top, 2)
            }
        }
        .sheet(item: $editing) { preset in
            TimerPresetEditor(preset: preset) { updated in
                if let index = presets.firstIndex(where: { $0.id == updated.id }) {
                    presets[index] = updated
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            TimerPresetEditor(preset: nil) { created in
                presets.append(created)
            }
        }
    }

    @ViewBuilder
    private func presetRow(_ preset: TimerPreset) -> some View {
        HStack(spacing: 10) {
            Circle().fill(preset.color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.name).font(.system(size: 13, weight: .medium))
                Text(preset.formattedDuration).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Button { editing = preset } label: {
                Image(systemName: "pencil").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            Button {
                presets.removeAll { $0.id == preset.id }
            } label: {
                Image(systemName: "trash").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.08))
        )
    }
}

/// Add/edit sheet for a single timer preset.
private struct TimerPresetEditor: View {
    let preset: TimerPreset?
    let onSave: (TimerPreset) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var hours: Int
    @State private var minutes: Int
    @State private var seconds: Int
    @State private var color: Color

    init(preset: TimerPreset?, onSave: @escaping (TimerPreset) -> Void) {
        self.preset = preset
        self.onSave = onSave
        let components = TimerPreset.components(for: preset?.duration ?? 25 * 60)
        _name = State(initialValue: preset?.name ?? String(localized: "New Timer"))
        _hours = State(initialValue: components.hours)
        _minutes = State(initialValue: components.minutes)
        _seconds = State(initialValue: components.seconds)
        _color = State(initialValue: preset?.color ?? .orange)
    }

    private var duration: TimeInterval {
        TimerPreset.duration(from: .init(hours: hours, minutes: minutes, seconds: seconds))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(preset == nil ? String(localized: "New Preset") : String(localized: "Edit Preset"))
                .font(.headline)

            TextField(String(localized: "Name"), text: $name)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                durationStepper(String(localized: "Hours"), value: $hours, range: 0...23)
                durationStepper(String(localized: "Min"), value: $minutes, range: 0...59)
                durationStepper(String(localized: "Sec"), value: $seconds, range: 0...59)
            }

            ColorPicker(String(localized: "Color"), selection: $color, supportsOpacity: false)

            HStack {
                Button(String(localized: "Cancel")) { dismiss() }
                Spacer()
                Button(String(localized: "Save")) {
                    let id = preset?.id ?? UUID()
                    onSave(TimerPreset(id: id, name: name.isEmpty ? String(localized: "Timer") : name, duration: max(1, duration), color: color))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(duration < 1)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    @ViewBuilder
    private func durationStepper(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue)").font(.system(.body, design: .monospaced))
            }
        }
    }
}
