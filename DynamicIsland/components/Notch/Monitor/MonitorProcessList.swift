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

/// The "top processes" card shared by the CPU, Memory and Network detail views.
///
/// Sits in the narrow third column, so process names get the width and the
/// figure is right-aligned in mono — the same label/value grammar as
/// `MonitorMetricRow`, just with a truncating name in the label slot.
struct MonitorProcessList: View {
    let title: String
    let rows: [ProcessSample]
    /// Formats a row's value for its metric (percent, bytes, …).
    let format: (Double) -> String
    var tint: Color = NotchDesign.Colors.textPrimary
    /// Set to render `ProcessSample.secondary` in a second column — the network
    /// card's upload rate beside its download rate.
    var secondaryTint: Color?
    /// Shown while the first sample is still being collected.
    var isLoading = false
    var emptyMessage: String = String(localized: "No data yet")

    private var hasSecondColumn: Bool { secondaryTint != nil }

    var body: some View {
        MonitorDetailCard(title: title) {
            VStack(alignment: .leading, spacing: 3) {
                if hasSecondColumn { legend }
                if rows.isEmpty {
                    Text(isLoading ? String(localized: "Measuring…") : emptyMessage)
                        .font(NotchDesign.Typography.voice(10))
                        .foregroundStyle(NotchDesign.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(rows) { row in
                        HStack(spacing: 6) {
                            Text(row.name)
                                .font(NotchDesign.Typography.voice(10))
                                .foregroundStyle(NotchDesign.Colors.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            value(format(row.value), tint: tint)
                            if let secondaryTint {
                                value(format(row.secondary ?? 0), tint: secondaryTint)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Two coloured dots stand in for column headers — at this width "Down" and
    /// "Up" would eat the room the names need, and the dots match the tints the
    /// throughput chart already uses for the same two directions.
    private var legend: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            dot(tint)
            dot(secondaryTint ?? tint)
        }
        .padding(.bottom, 1)
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .frame(width: Self.valueColumnWidth, alignment: .trailing)
    }

    private func value(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(NotchDesign.Typography.mono(9, weight: .medium))
            .foregroundStyle(tint)
            .monospacedDigit()
            .lineLimit(1)
            .layoutPriority(1)
            // Fixed-width slots so the two columns line up down the card instead
            // of jittering as the digits change.
            .frame(width: hasSecondColumn ? Self.valueColumnWidth : nil, alignment: .trailing)
    }
}

extension MonitorProcessList {
    /// Width of the process card. Wider than Power's 165pt adapter card because
    /// these rows carry a process name rather than a short value.
    static let columnWidth: CGFloat = 200
    /// Wider still when two rate columns share the row.
    static let dualColumnWidth: CGFloat = 250
    static let valueColumnWidth: CGFloat = 54

    static func percentFormat(_ value: Double) -> String {
        String(format: value >= 100 ? "%.0f%%" : "%.1f%%", value)
    }

    static func bytesFormat(_ value: Double) -> String {
        let parts = MonitorFormat.sizeParts(value)
        return "\(parts.value) \(parts.unit)"
    }

    /// Compact rate for the two-column network card — the unit is dropped to
    /// "K"/"M" so both columns fit beside a readable process name.
    static func compactRateFormat(_ bytesPerSecond: Double) -> String {
        let parts = MonitorFormat.rateParts(bytesPerSecond)
        return "\(parts.value) \(parts.unit)"
    }
}
