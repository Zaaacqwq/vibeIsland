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

/// Displays drill-in: one card per connected screen.
///
/// Up to three cards fit side by side; beyond that the row scrolls
/// horizontally. That scroll is why the parent suppresses the notch's swipe
/// gesture while this view is on screen — otherwise dragging through the list
/// would switch tabs instead.
struct DisplayDetailView: View {
    let displays: [DisplayStatsMonitor.DisplayInfo]
    let onBack: () -> Void

    var body: some View {
        MonitorDetailScaffold(
            category: .display,
            headline: displays.isEmpty ? nil : "\(displays.count)",
            subtitle: subtitle,
            onBack: onBack
        ) {
            if displays.isEmpty {
                MonitorDetailCard(title: "Displays") {
                    Text(String(localized: "No displays detected"))
                        .font(NotchDesign.Typography.voice(10))
                        .foregroundStyle(NotchDesign.Colors.textTertiary)
                }
            } else if displays.count <= 3 {
                HStack(spacing: 6) {
                    ForEach(displays) { display in
                        card(for: display).frame(maxWidth: .infinity)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(displays) { display in
                            card(for: display).frame(width: 210)
                        }
                    }
                }
            }
        }
    }

    private var subtitle: String? {
        guard let main = displays.first(where: \.isMain) else { return nil }
        return String(localized: "Main · \(main.name)")
    }

    /// The display name doubles as the card's eyebrow line rather than sitting
    /// on a row of its own — a built-in Retina panel reports every optional
    /// field at once (scaled resolution *and* colour *and* brightness), and the
    /// extra row pushed that longest case past the height budget and clipped
    /// the brightness meter.
    private func card(for display: DisplayStatsMonitor.DisplayInfo) -> some View {
        MonitorDetailCard {
            VStack(alignment: .leading, spacing: 4) {
                cardHeader(display)

                MonitorMetricRow(
                    label: String(localized: "Resolution"),
                    value: display.resolutionText
                )
                // Only worth stating when it differs from the native grid —
                // on a 1x panel the two lines would be identical.
                if display.isHiDPI {
                    MonitorMetricRow(
                        label: String(localized: "Scaled"),
                        value: "\(display.scaledResolutionText) @\(Int(display.backingScale))x",
                        tint: NotchDesign.Colors.textSecondary
                    )
                }
                MonitorMetricRow(
                    label: String(localized: "Refresh rate"),
                    value: display.refreshText
                )
                if let colorSpace = colorSpaceLabel(display) {
                    MonitorMetricRow(
                        label: String(localized: "Color"),
                        value: colorSpace,
                        tint: NotchDesign.Colors.textSecondary
                    )
                }
                if let brightness = display.brightness {
                    VStack(alignment: .leading, spacing: 2) {
                        MonitorMetricRow(
                            label: String(localized: "Brightness"),
                            value: MonitorFormat.percent(fraction: brightness)
                        )
                        MonitorBar(fraction: brightness, tint: MonitorCategory.display.tint, height: 3)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func cardHeader(_ display: DisplayStatsMonitor.DisplayInfo) -> some View {
        HStack(spacing: 5) {
            Text(display.name)
                .font(NotchDesign.Typography.voice(11, weight: .medium))
                .foregroundStyle(NotchDesign.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if display.isMain {
                Text(String(localized: "MAIN"))
                    .font(NotchDesign.Typography.mono(7, weight: .medium))
                    .foregroundStyle(MonitorCategory.display.tint)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background {
                        Capsule().fill(MonitorCategory.display.tint.opacity(0.16))
                    }
            }
            Spacer(minLength: 4)
            Text(display.isBuiltIn ? String(localized: "BUILT-IN") : String(localized: "EXTERNAL"))
                .font(NotchDesign.Typography.mono(8, weight: .medium))
                .tracking(NotchDesign.eyebrowTracking * 0.6)
                .foregroundStyle(NotchDesign.Colors.textTertiary)
                .layoutPriority(1)
        }
    }

    /// External monitors commonly report their colour space as the product name
    /// ("VG27AQ5A"), which just restates the card's own title — drop the row in
    /// that case rather than printing the name twice.
    private func colorSpaceLabel(_ display: DisplayStatsMonitor.DisplayInfo) -> String? {
        guard let name = display.colorSpaceName, !name.isEmpty else { return nil }
        return name.caseInsensitiveCompare(display.name) == .orderedSame ? nil : name
    }
}
