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

/// One cell of the Monitor tab's overview grid: a tinted icon + mono eyebrow,
/// one headline number, and either a trend line or a caption underneath.
/// Tapping it drills into that category's detail view.
///
/// The tile owns no data of its own — the parent reads the monitors once and
/// hands each tile a finished `Content`, so a tick doesn't invalidate eight
/// separate observers.
struct MonitorTile: View {
    enum Trailing: Equatable {
        /// A trend line for the category's series.
        case sparkline(normalized: [Double])
        /// Two overlaid series (network down/up, disk read/write).
        case dualSparkline(primary: [Double], secondary: [Double])
        /// A filled proportion bar — for capacities, where "72% of 1 TB" is the
        /// story and a time series would be a flat line.
        case bar(fraction: Double)
        /// A short mono line, for categories with nothing to chart.
        case caption(String)
    }

    let category: MonitorCategory
    /// Headline number, already formatted (e.g. "34%", "16.2").
    let value: String
    /// Optional unit rendered small and dim beside the value ("GB", "MB/s").
    var unit: String?
    var trailing: Trailing
    /// Overrides the value colour — used to flag a metric into warning/danger.
    var valueTint: Color?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                header
                headline
                Spacer(minLength: 0)
                trailingContent
                    .frame(height: 18)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .notchCard(radius: NotchDesign.Radius.sm)
            .overlay {
                RoundedRectangle(cornerRadius: NotchDesign.Radius.sm, style: .continuous)
                    .strokeBorder(
                        isHovering ? category.tint.opacity(0.45) : NotchDesign.Colors.hairline,
                        lineWidth: NotchDesign.hairlineWidth
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: NotchDesign.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        // Hover feedback only — the value itself must never animate, or every
        // tick would schedule an interpolation for all eight tiles at once.
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .accessibilityLabel("\(category.title) \(value)\(unit.map { " \($0)" } ?? "")")
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: category.systemImage)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(category.tint)
            Text(verbatim: category.eyebrow.uppercased())
                .font(NotchDesign.Typography.mono(8, weight: .medium))
                .tracking(NotchDesign.eyebrowTracking * 0.6)
                .foregroundStyle(NotchDesign.Colors.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(NotchDesign.Typography.mono(19, weight: .semibold))
                .foregroundStyle(valueTint ?? NotchDesign.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let unit {
                Text(unit)
                    .font(NotchDesign.Typography.mono(9, weight: .medium))
                    .foregroundStyle(NotchDesign.Colors.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var trailingContent: some View {
        switch trailing {
        case .sparkline(let normalized):
            MonitorSparkline(normalized: normalized, tint: category.tint)
        case .dualSparkline(let primary, let secondary):
            MonitorDualSparkline(
                primary: primary,
                secondary: secondary,
                primaryTint: NotchDesign.Colors.info,
                secondaryTint: NotchDesign.Colors.danger
            )
        case .bar(let fraction):
            VStack {
                Spacer(minLength: 0)
                MonitorBar(fraction: fraction, tint: category.tint)
                Spacer(minLength: 0)
            }
        case .caption(let text):
            VStack(alignment: .leading) {
                Spacer(minLength: 0)
                Text(verbatim: notchLocalized(text))
                    .font(NotchDesign.Typography.mono(9, weight: .medium))
                    .foregroundStyle(NotchDesign.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A slim proportion bar. Shared by tiles and detail rows so a "62% of RAM"
/// reads identically wherever it appears.
struct MonitorBar: View {
    let fraction: Double
    var tint: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}

/// A bar split into proportional, individually tinted segments — the memory
/// breakdown (app / wired / compressed / cached) reads as one bar rather than
/// four unrelated numbers.
struct MonitorSegmentedBar: View {
    struct Segment: Identifiable, Equatable {
        let id: String
        let fraction: Double
        let tint: Color
    }

    let segments: [Segment]
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.tint)
                        .frame(width: max(proxy.size.width * min(max(segment.fraction, 0), 1), 0))
                }
                Spacer(minLength: 0)
            }
            .frame(height: height)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
        }
        .frame(height: height)
    }
}
