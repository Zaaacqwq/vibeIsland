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

/// Frame shared by all seven Monitor detail views: a back control, the category
/// title, an optional headline figure on the right, and the content below.
///
/// The back affordance is an explicit button rather than a swipe: horizontal
/// drags inside the open notch are already bound to tab switching
/// (`DynamicIslandViewCoordinator.navigateToAdjacentTab`), so a swipe-back here
/// would fight the gesture that leaves the Monitor tab entirely.
struct MonitorDetailScaffold<Content: View>: View {
    let category: MonitorCategory
    /// Right-aligned headline, e.g. "34%" or "16.2 / 32 GB".
    var headline: String?
    var subtitle: String?
    let onBack: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isHoveringBack = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .bold))
                    Image(systemName: category.systemImage)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(category.tint)
                    Text(category.title)
                        .font(NotchDesign.Typography.voice(12, weight: .medium))
                }
                .foregroundStyle(
                    isHoveringBack ? NotchDesign.Colors.textPrimary : NotchDesign.Colors.textSecondary
                )
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background {
                    Capsule().fill(Color.white.opacity(isHoveringBack ? 0.09 : 0.04))
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringBack = $0 }
            .animation(.easeOut(duration: 0.15), value: isHoveringBack)

            if let subtitle {
                Text(subtitle)
                    .font(NotchDesign.Typography.mono(9, weight: .medium))
                    .foregroundStyle(NotchDesign.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            if let headline {
                Text(headline)
                    .font(NotchDesign.Typography.mono(15, weight: .semibold))
                    .foregroundStyle(NotchDesign.Colors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }
}

/// A `#141414` card holding one labelled group inside a detail view.
struct MonitorDetailCard<Content: View>: View {
    var title: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let title {
                NotchMonoEyebrow(text: title)
            }
            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .notchCard(radius: NotchDesign.Radius.sm)
    }
}

/// Label on the left, mono value on the right — the workhorse row of every
/// detail view. Values are right-aligned so a column of them lines up.
struct MonitorMetricRow: View {
    let label: String
    let value: String
    var tint: Color = NotchDesign.Colors.textPrimary
    /// Optional leading swatch, for rows that key into a segmented bar.
    var swatch: Color?

    var body: some View {
        HStack(spacing: 5) {
            if let swatch {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(swatch)
                    .frame(width: 6, height: 6)
            }
            Text(verbatim: notchLocalized(label))
                .font(NotchDesign.Typography.voice(10))
                .foregroundStyle(NotchDesign.Colors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(value)
                .font(NotchDesign.Typography.mono(10, weight: .medium))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

/// Stacked eyebrow-over-value block, for the two or three figures a detail view
/// wants to state large rather than list.
struct MonitorStatBlock: View {
    let label: String
    let value: String
    var unit: String?
    var tint: Color = NotchDesign.Colors.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: notchLocalized(label).uppercased())
                .font(NotchDesign.Typography.mono(8, weight: .medium))
                .tracking(NotchDesign.eyebrowTracking * 0.6)
                .foregroundStyle(NotchDesign.Colors.textTertiary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(NotchDesign.Typography.mono(14, weight: .semibold))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1)
                if let unit {
                    Text(unit)
                        .font(NotchDesign.Typography.mono(8, weight: .medium))
                        .foregroundStyle(NotchDesign.Colors.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shared thresholds so "busy" looks the same in every card. Below 60% reads
/// neutral rather than green — a green CPU meter implies "good" when it only
/// means "idle".
enum MonitorTint {
    static func forLoad(percent: Double) -> Color {
        switch percent {
        case ..<60: return NotchDesign.Colors.textPrimary
        case ..<85: return NotchDesign.Colors.warning
        default: return NotchDesign.Colors.danger
        }
    }

    static func forCapacity(fraction: Double) -> Color {
        forLoad(percent: fraction * 100)
    }

    /// Battery colour follows charge remaining, so the ramp runs the other way.
    static func forCharge(fraction: Double, isCharging: Bool) -> Color {
        if isCharging { return NotchDesign.Colors.success }
        switch fraction {
        case ..<0.1: return NotchDesign.Colors.danger
        case ..<0.2: return NotchDesign.Colors.warning
        default: return NotchDesign.Colors.textPrimary
        }
    }
}
