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

import AppKit
import Defaults
import SwiftUI

/// The color picker's content, shared by both presentation modes.
///
/// One view, parameterized by ``ToolDisplayMode``, rather than a popover view
/// and a tab view that drift apart: only the swatch grid density and the
/// vertical layout policy differ between the two.
struct ColorPickerPanel: View {
    let mode: ToolDisplayMode

    @ObservedObject private var manager = ColorPickerManager.shared
    @Default(.colorPickerHistory) private var history
    @Default(.colorPickerDefaultFormat) private var defaultFormat
    @Default(.colorPickerUppercaseHex) private var uppercaseHex

    @State private var hoveredSwatchID: UUID?

    private var isTab: Bool { mode == .tab }
    private var swatchSize: CGFloat { isTab ? 34 : 28 }
    private var swatchSpacing: CGFloat { isTab ? 8 : 6 }

    var body: some View {
        if isTab {
            tabLayout
        } else {
            popoverLayout
        }
    }

    /// The open notch is wide and short, so the tab puts the current color and
    /// the history side by side. Stacking them vertically (as the popover does)
    /// overflows the fixed tab height budget and clips the swatch grid.
    private var tabLayout: some View {
        VStack(alignment: .leading, spacing: NotchDesign.Spacing.xs) {
            header

            HStack(alignment: .top, spacing: NotchDesign.Spacing.sm) {
                if let current = manager.mostRecent {
                    currentColorCard(current)
                        .frame(width: 240)
                } else {
                    emptyState
                }

                if !history.isEmpty {
                    recentSection
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var popoverLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let current = manager.mostRecent {
                currentColorCard(current)
            } else {
                emptyState
            }

            if !history.isEmpty {
                recentSection
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(ToolPanelStyle.iconTile)
                Image(systemName: "eyedropper")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ToolPanelStyle.title)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Color Picker"))
                    .font(NotchDesign.Typography.voice(14, weight: .semibold))
                    .foregroundStyle(ToolPanelStyle.title)
                Text(manager.isSampling
                     ? String(localized: "Sampling — click anywhere")
                     : String(localized: "\(history.count) saved"))
                    .font(NotchDesign.Typography.mono(11, weight: .medium))
                    .foregroundStyle(ToolPanelStyle.muted)
            }

            Spacer(minLength: 8)

            pickButton
        }
    }

    private var pickButton: some View {
        Button {
            manager.pick()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "eyedropper.halffull")
                    .font(.system(size: 11, weight: .semibold))
                Text(String(localized: "Pick"))
                    .font(NotchDesign.Typography.voice(12, weight: .medium))
            }
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(NotchDesign.Colors.accent.opacity(manager.isSampling ? 0.5 : 1))
            )
        }
        .buttonStyle(.plain)
        .disabled(manager.isSampling)
        .help(String(localized: "Sample a color from anywhere on screen"))
    }

    // MARK: - Current color

    private func currentColorCard(_ color: PickedColor) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: ToolPanelStyle.controlRadius, style: .continuous)
                .fill(color.color)
                .frame(width: isTab ? 64 : 52, height: isTab ? 64 : 52)
                .overlay(
                    RoundedRectangle(cornerRadius: ToolPanelStyle.controlRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 8) {
                Text(ColorFormat.hex.string(for: color, uppercaseHex: uppercaseHex))
                    .font(NotchDesign.Typography.mono(isTab ? 15 : 13, weight: .semibold))
                    .foregroundStyle(ToolPanelStyle.value)
                    .textSelection(.enabled)

                HStack(spacing: 6) {
                    ForEach(ColorFormat.quickFormats) { format in
                        formatChip(format, for: color)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(isTab ? 12 : 10)
        .background(
            RoundedRectangle(cornerRadius: ToolPanelStyle.cardRadius, style: .continuous)
                .fill(ToolPanelStyle.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ToolPanelStyle.cardRadius, style: .continuous)
                .strokeBorder(ToolPanelStyle.cardStroke, lineWidth: 1)
        )
    }

    private func formatChip(_ format: ColorFormat, for color: PickedColor) -> some View {
        let flashing = manager.isFlashing(color, format: format)
        return Button {
            manager.copy(color, as: format)
        } label: {
            Text(flashing ? String(localized: "Copied") : format.displayName)
                .font(NotchDesign.Typography.mono(10, weight: .medium))
                .tracking(NotchDesign.eyebrowTracking * 0.5)
                .foregroundStyle(flashing ? NotchDesign.Colors.success : ToolPanelStyle.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(flashing ? NotchDesign.Colors.success.opacity(0.14) : ToolPanelStyle.chipFill)
                )
                .overlay(Capsule().strokeBorder(ToolPanelStyle.chipStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(manager.string(for: color, as: format))
    }

    // MARK: - History

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "RECENT"))
                    .font(NotchDesign.Typography.eyebrow)
                    .tracking(NotchDesign.eyebrowTracking)
                    .foregroundStyle(ToolPanelStyle.faint)
                Spacer()
                Button(String(localized: "Clear")) {
                    manager.clearHistory()
                }
                .buttonStyle(.plain)
                .font(NotchDesign.Typography.voice(11, weight: .medium))
                .foregroundStyle(ToolPanelStyle.muted)
            }

            swatchGrid
        }
        .frame(maxWidth: isTab ? .infinity : nil, alignment: .leading)
    }

    private var swatchGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: swatchSize, maximum: swatchSize), spacing: swatchSpacing)],
                alignment: .leading,
                spacing: swatchSpacing
            ) {
                ForEach(history) { color in
                    swatch(color)
                }
            }
        }
        // Bounded so a long history scrolls inside the panel instead of growing
        // it — in tab mode an unbounded grid would stretch the notch window.
        .frame(maxHeight: isTab ? .infinity : 104)
    }

    private func swatch(_ color: PickedColor) -> some View {
        Button {
            manager.copy(color, as: defaultFormat)
        } label: {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.color)
                .frame(width: swatchSize, height: swatchSize)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            hoveredSwatchID == color.id ? Color.white.opacity(0.5) : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                )
                .overlay {
                    if manager.isFlashing(color, format: defaultFormat) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(color.prefersDarkForeground ? .black : .white)
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hoveredSwatchID = $0 ? color.id : nil }
        .help(manager.string(for: color, as: defaultFormat))
        .contextMenu {
            ForEach(ColorFormat.allCases) { format in
                Button(String(localized: "Copy as \(format.displayName)")) {
                    manager.copy(color, as: format)
                }
            }
            Divider()
            Button(String(localized: "Remove"), role: .destructive) {
                manager.remove(color)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "eyedropper")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(ToolPanelStyle.faint)
            Text(String(localized: "No colors picked yet"))
                .font(NotchDesign.Typography.voice(12, weight: .medium))
                .foregroundStyle(ToolPanelStyle.muted)
            Text(String(localized: "Pick a color to start a history."))
                .font(NotchDesign.Typography.caption)
                .foregroundStyle(ToolPanelStyle.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isTab ? 20 : 14)
        .background(
            RoundedRectangle(cornerRadius: ToolPanelStyle.cardRadius, style: .continuous)
                .fill(ToolPanelStyle.cardFill)
        )
    }
}
