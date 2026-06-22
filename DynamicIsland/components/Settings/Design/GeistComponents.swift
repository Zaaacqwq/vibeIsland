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

/// Binding to a boolean `Defaults` key, for Geist toggle rows.
func geistBinding(_ key: Defaults.Key<Bool>) -> Binding<Bool> {
    Binding(get: { Defaults[key] }, set: { Defaults[key] = $0 })
}

/// A scrollable Geist settings page: a large title, optional description, and a
/// stack of sections. Replaces the native grouped `Form` look.
struct GeistSettingsPage<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: Geist.Spacing.xxs) {
                    Text(title)
                        .font(Geist.Typography.displayMd)
                        .foregroundStyle(Geist.Colors.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(Geist.Typography.body)
                            .foregroundStyle(Geist.Colors.body)
                    }
                }
                content
            }
            .padding(Geist.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(Geist.Colors.canvas)
        .tint(Geist.Colors.accent)
    }
}

/// A titled group of rows inside a hairline-bordered card.
struct GeistSection<Content: View>: View {
    var title: String?
    var badge: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Geist.Spacing.xs) {
            if let title {
                HStack(spacing: Geist.Spacing.xs) {
                    Text(title.uppercased())
                        .font(Geist.Typography.captionStrong)
                        .foregroundStyle(Geist.Colors.mute)
                        .tracking(0.6)
                    if let badge {
                        Text(badge.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Geist.Colors.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .overlay(
                                Capsule().strokeBorder(Geist.Colors.accent.opacity(0.4), lineWidth: 1)
                            )
                    }
                }
                .padding(.leading, Geist.Spacing.xxs)
            }
            GeistCard { content }
            if let footer {
                Text(footer)
                    .font(Geist.Typography.caption)
                    .foregroundStyle(Geist.Colors.mute)
                    .padding(.leading, Geist.Spacing.xxs)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A card surface: soft background + hairline border + rounded corners.
struct GeistCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Geist.Colors.canvasSoft)
            .clipShape(RoundedRectangle(cornerRadius: Geist.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Geist.Radius.md, style: .continuous)
                    .strokeBorder(Geist.Colors.hairline, lineWidth: Geist.hairlineWidth)
            )
    }
}

/// A single row inside a card. Use `divider: true` on all but the last row.
struct GeistRow<Content: View>: View {
    var divider: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
            if divider {
                Rectangle()
                    .fill(Geist.Colors.hairline)
                    .frame(height: Geist.hairlineWidth)
            }
        }
    }
}

/// A labelled switch row (title + optional description + trailing Toggle).
struct GeistToggleRow: View {
    let title: String
    var description: String?
    @Binding var isOn: Bool
    var divider: Bool = true

    var body: some View {
        GeistRow(divider: divider) {
            HStack(alignment: .center, spacing: Geist.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Geist.Typography.bodyStrong)
                        .foregroundStyle(Geist.Colors.ink)
                    if let description {
                        Text(description)
                            .font(Geist.Typography.caption)
                            .foregroundStyle(Geist.Colors.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Geist.Spacing.sm)
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }
}

/// A row with a leading label and a trailing menu picker.
struct GeistPickerRow<T: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: T
    var divider: Bool = true
    @ViewBuilder var options: Options

    var body: some View {
        GeistRow(divider: divider) {
            HStack(spacing: Geist.Spacing.sm) {
                Text(title)
                    .font(Geist.Typography.bodyStrong)
                    .foregroundStyle(Geist.Colors.ink)
                Spacer(minLength: 0)
                Picker("", selection: $selection) { options }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .font(Geist.Typography.body)
            }
        }
    }
}

/// A row with a leading label and arbitrary trailing content.
struct GeistLabeledRow<Trailing: View>: View {
    let title: String
    var divider: Bool = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        GeistRow(divider: divider) {
            HStack(spacing: Geist.Spacing.sm) {
                Text(title)
                    .font(Geist.Typography.bodyStrong)
                    .foregroundStyle(Geist.Colors.ink)
                Spacer(minLength: 0)
                trailing
            }
        }
    }
}

/// A row with a leading label, a trailing value, and a slider underneath.
struct GeistSliderRow<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
    let title: String
    var valueLabel: String?
    @Binding var value: V
    let range: ClosedRange<V>
    var step: V.Stride = 1
    var divider: Bool = true
    var onChange: (() -> Void)?

    var body: some View {
        GeistRow(divider: divider) {
            VStack(alignment: .leading, spacing: Geist.Spacing.xs) {
                HStack(spacing: Geist.Spacing.sm) {
                    Text(title)
                        .font(Geist.Typography.bodyStrong)
                        .foregroundStyle(Geist.Colors.ink)
                    Spacer(minLength: 0)
                    if let valueLabel {
                        Text(valueLabel)
                            .font(Geist.Typography.body)
                            .foregroundStyle(Geist.Colors.mute)
                            .monospacedDigit()
                    }
                }
                Slider(value: $value, in: range, step: step)
                    .controlSize(.small)
                    .onChange(of: value) { _, _ in onChange?() }
            }
        }
    }
}

/// A row with a leading label/description and a trailing native stepper.
struct GeistStepperRow: View {
    let title: String
    var description: String?
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var divider: Bool = true
    var valueLabel: String?
    var onChange: (() -> Void)?

    var body: some View {
        GeistRow(divider: divider) {
            HStack(alignment: .center, spacing: Geist.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Geist.Typography.bodyStrong)
                        .foregroundStyle(Geist.Colors.ink)
                    if let description {
                        Text(description)
                            .font(Geist.Typography.caption)
                            .foregroundStyle(Geist.Colors.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Geist.Spacing.sm)
                if let valueLabel {
                    Text(valueLabel)
                        .font(Geist.Typography.body)
                        .foregroundStyle(Geist.Colors.mute)
                        .monospacedDigit()
                }
                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: value) { _, _ in onChange?() }
            }
        }
    }
}

/// A row with a leading label and a trailing segmented picker. Falls back to a
/// full-width segmented control underneath the label when space is tight.
struct GeistSegmentedRow<T: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: T
    var divider: Bool = true
    @ViewBuilder var options: Options

    var body: some View {
        GeistRow(divider: divider) {
            VStack(alignment: .leading, spacing: Geist.Spacing.xs) {
                Text(title)
                    .font(Geist.Typography.bodyStrong)
                    .foregroundStyle(Geist.Colors.ink)
                Picker("", selection: $selection) { options }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .font(Geist.Typography.body)
            }
        }
    }
}

/// A pill-shaped Geist button.
struct GeistButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Geist.Typography.bodyStrong)
            .foregroundStyle(prominent ? Color.white : Geist.Colors.ink)
            .padding(.horizontal, Geist.Spacing.md)
            .padding(.vertical, Geist.Spacing.xs)
            .background(prominent ? Geist.Colors.accent : Geist.Colors.canvasSoft)
            .overlay(
                Capsule().strokeBorder(prominent ? Color.clear : Geist.Colors.hairlineStrong, lineWidth: Geist.hairlineWidth)
            )
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == GeistButtonStyle {
    static var geist: GeistButtonStyle { GeistButtonStyle() }
    static var geistProminent: GeistButtonStyle { GeistButtonStyle(prominent: true) }
}
