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

/// Settings components accept ordinary strings because some labels are runtime
/// values (account names, bundle identifiers, measured values). Static strings
/// are resolved through the app's string catalog at the final rendering edge;
/// unknown keys naturally remain verbatim.
private func geistLocalized(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

private func geistCombinedHelp(_ values: String?...) -> String? {
    let parts = values.compactMap { value -> String? in
        guard let value, !value.isEmpty else { return nil }
        return geistLocalized(value)
    }
    return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
}

/// Binding to a boolean `Defaults` key, for Geist toggle rows.
func geistBinding(_ key: Defaults.Key<Bool>) -> Binding<Bool> {
    Binding(get: { Defaults[key] }, set: { Defaults[key] = $0 })
}

/// A scrollable Geist settings page: a large title, optional description, and a
/// stack of sections. Replaces the native grouped `Form` look.
struct GeistSettingsPage<Content: View>: View {
    let title: String
    var subtitle: String?
    var info: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: Geist.Spacing.xs) {
                    Text(verbatim: geistLocalized(title))
                        .font(Geist.Typography.displayMd)
                        .foregroundStyle(Geist.Colors.ink)
                    if let help = geistCombinedHelp(info, subtitle) {
                        GeistInfoButton(text: help, isLocalized: true)
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
    var info: String?
    var note: String?
    var noteBullets: [String] = []
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Geist.Spacing.xs) {
            if let title {
                HStack(spacing: Geist.Spacing.xs) {
                    Text(verbatim: geistLocalized(title).uppercased())
                        .font(Geist.Typography.captionStrong)
                        .foregroundStyle(Geist.Colors.mute)
                        .tracking(0.6)
                    if let badge {
                        Text(verbatim: geistLocalized(badge).uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Geist.Colors.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .overlay(
                                Capsule().strokeBorder(Geist.Colors.accent.opacity(0.4), lineWidth: 1)
                            )
                    }
                    if let help = geistCombinedHelp(info, footer) {
                        GeistInfoButton(text: help, isLocalized: true)
                    }
                }
                .padding(.leading, Geist.Spacing.xxs)
            } else if let help = geistCombinedHelp(info, footer) {
                GeistInfoButton(text: help, isLocalized: true)
                    .padding(.leading, Geist.Spacing.xxs)
            }
            GeistCard { content }
            if note != nil || !noteBullets.isEmpty {
                GeistPersistentNote(text: note, bullets: noteBullets)
            }
        }
    }
}

/// Concise help that must remain visible because it describes an operation,
/// prerequisite, privacy implication, destructive effect, or blocking state.
struct GeistPersistentNote: View {
    var text: String?
    var bullets: [String] = []
    var isWarning = false

    var body: some View {
        HStack(alignment: .top, spacing: Geist.Spacing.xs) {
            if isWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Geist.Colors.warning)
                    .font(.system(size: 11))
                    .padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 3) {
                if let text {
                    Text(verbatim: geistLocalized(text))
                }
                ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(verbatim: geistLocalized(bullet))
                    }
                }
            }
        }
        .font(Geist.Typography.caption)
        .foregroundStyle(isWarning ? Geist.Colors.ink : Geist.Colors.mute)
        .padding(.leading, Geist.Spacing.xxs)
        .fixedSize(horizontal: false, vertical: true)
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

/// A small ⓘ affordance that reveals help text on click (popover) and hover.
/// Attach to any row whose purpose isn't self-evident.
struct GeistInfoButton: View {
    let text: String
    var isLocalized = false
    @State private var showPopover = false

    private var resolvedText: String {
        isLocalized ? text : geistLocalized(text)
    }

    var body: some View {
        Button { showPopover.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(Geist.Colors.mute)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("More information"))
        .help(resolvedText)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            Text(verbatim: resolvedText)
                .font(Geist.Typography.caption)
                .foregroundStyle(Geist.Colors.body)
                .frame(maxWidth: 320, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Geist.Spacing.md)
        }
    }
}

/// A row title (`bodyStrong` ink text) with an optional trailing ⓘ info button.
struct GeistRowTitle: View {
    let title: String
    var info: String?

    var body: some View {
        HStack(spacing: Geist.Spacing.xxs) {
            Text(verbatim: geistLocalized(title))
                .font(Geist.Typography.bodyStrong)
                .foregroundStyle(Geist.Colors.ink)
            if let info {
                GeistInfoButton(text: info)
            }
        }
    }
}

/// A small speaker button that auditions a sound. Attach next to any sound
/// setting so the user can hear it without triggering the real event.
struct GeistPreviewButton: View {
    var help: String = "Preview sound"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Geist.Colors.accent)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(geistLocalized(help))
    }
}

/// A labelled switch row (title + optional description + trailing Toggle).
/// Pass `onPreview` to show a speaker button (e.g. for sound settings).
struct GeistToggleRow: View {
    let title: String
    var description: String?
    @Binding var isOn: Bool
    var divider: Bool = true
    var info: String?
    var onPreview: (() -> Void)?

    var body: some View {
        GeistRow(divider: divider) {
            HStack(alignment: .center, spacing: Geist.Spacing.md) {
                GeistRowTitle(title: title, info: geistCombinedHelp(info, description))
                Spacer(minLength: Geist.Spacing.sm)
                if let onPreview {
                    GeistPreviewButton(action: onPreview)
                }
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
    var info: String?
    @ViewBuilder var options: Options

    var body: some View {
        GeistRow(divider: divider) {
            HStack(spacing: Geist.Spacing.sm) {
                GeistRowTitle(title: title, info: info)
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
    var info: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        GeistRow(divider: divider) {
            HStack(spacing: Geist.Spacing.sm) {
                GeistRowTitle(title: title, info: info)
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
    var info: String?
    var onChange: (() -> Void)?

    var body: some View {
        GeistRow(divider: divider) {
            VStack(alignment: .leading, spacing: Geist.Spacing.xs) {
                HStack(spacing: Geist.Spacing.sm) {
                    GeistRowTitle(title: title, info: info)
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
    var info: String?
    var onChange: (() -> Void)?

    var body: some View {
        GeistRow(divider: divider) {
            HStack(alignment: .center, spacing: Geist.Spacing.md) {
                GeistRowTitle(title: title, info: geistCombinedHelp(info, description))
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
    var info: String?
    @ViewBuilder var options: Options

    var body: some View {
        GeistRow(divider: divider) {
            VStack(alignment: .leading, spacing: Geist.Spacing.xs) {
                GeistRowTitle(title: title, info: info)
                Picker("", selection: $selection) { options }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .font(Geist.Typography.body)
            }
        }
    }
}

/// A drill-down row: leading colored SF-Symbol tile, title + optional subtitle, and a
/// trailing chevron. Acts as a `NavigationLink` into a sub-page, mirroring the way
/// macOS System Settings nests categories (e.g. Accessibility → VoiceOver).
struct GeistNavRow<V: Hashable>: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var tint: Color = Geist.Colors.accent
    var badge: String?
    let value: V
    var divider: Bool = true

    var body: some View {
        NavigationLink(value: value) {
            GeistRow(divider: divider) {
                HStack(spacing: Geist.Spacing.md) {
                    if let systemImage {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tint, tint.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 22, height: 22)
                            .overlay {
                                Image(systemName: systemImage)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.white)
                            }
                    }
                    GeistRowTitle(title: title, info: subtitle)
                    Spacer(minLength: Geist.Spacing.sm)
                    if let badge {
                        Text(verbatim: geistLocalized(badge).uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Geist.Colors.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .overlay(
                                Capsule().strokeBorder(Geist.Colors.accent.opacity(0.4), lineWidth: 1)
                            )
                    }
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Geist.Colors.mute)
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
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
