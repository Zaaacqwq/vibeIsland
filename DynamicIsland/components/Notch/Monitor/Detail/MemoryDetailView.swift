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

/// Memory drill-in: where the RAM actually went, plus swap and the pressure
/// proxy.
///
/// The composition bar is the point of this view — "61% used" says far less
/// than knowing that half of it is wired and compressed, which is the part the
/// kernel cannot hand back.
struct MemoryDetailView: View {
    let snapshot: SystemStatsSnapshot
    let history: MonitorHistoryBundle
    let processes: [ProcessSample]
    let onBack: () -> Void

    private var appBytes: UInt64 {
        let accounted = snapshot.ramWiredBytes + snapshot.ramCompressedBytes
        return snapshot.ramUsedBytes > accounted ? snapshot.ramUsedBytes - accounted : 0
    }

    private var wiredTint: Color { NotchDesign.Colors.warning }
    private var compressedTint: Color { NotchDesign.Colors.danger }
    private var cachedTint: Color { Color.white.opacity(0.18) }

    var body: some View {
        MonitorDetailScaffold(
            category: .memory,
            headline: "\(MonitorFormat.size(snapshot.ramUsedBytes)) / \(MonitorFormat.size(snapshot.ramTotalBytes))",
            subtitle: MonitorFormat.percent(fraction: snapshot.ramUsedFraction),
            onBack: onBack
        ) {
            HStack(spacing: 6) {
                compositionCard
                    .frame(maxWidth: .infinity)
                pressureCard
                    .frame(maxWidth: .infinity)
                MonitorProcessList(
                    title: "Top processes",
                    rows: processes,
                    format: MonitorProcessList.bytesFormat,
                    isLoading: processes.isEmpty
                )
                .frame(width: MonitorProcessList.columnWidth)
            }
        }
    }

    private var compositionCard: some View {
        MonitorDetailCard(title: "Composition") {
            VStack(alignment: .leading, spacing: 7) {
                MonitorSegmentedBar(segments: segments)

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        MonitorMetricRow(
                            label: String(localized: "App memory"),
                            value: MonitorFormat.size(appBytes),
                            swatch: MonitorCategory.memory.tint
                        )
                        MonitorMetricRow(
                            label: String(localized: "Wired"),
                            value: MonitorFormat.size(snapshot.ramWiredBytes),
                            swatch: wiredTint
                        )
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        MonitorMetricRow(
                            label: String(localized: "Compressed"),
                            value: MonitorFormat.size(snapshot.ramCompressedBytes),
                            swatch: compressedTint
                        )
                        MonitorMetricRow(
                            label: String(localized: "Cached files"),
                            value: MonitorFormat.size(snapshot.ramCachedBytes),
                            tint: NotchDesign.Colors.textSecondary,
                            swatch: cachedTint
                        )
                    }
                }

                MonitorSparkline(
                    normalized: history.memory.normalized(ceiling: 100),
                    tint: MonitorCategory.memory.tint
                )
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var segments: [MonitorSegmentedBar.Segment] {
        let total = max(Double(snapshot.ramTotalBytes), 1)
        return [
            .init(id: "app", fraction: Double(appBytes) / total, tint: MonitorCategory.memory.tint),
            .init(id: "wired", fraction: Double(snapshot.ramWiredBytes) / total, tint: wiredTint),
            .init(
                id: "compressed",
                fraction: Double(snapshot.ramCompressedBytes) / total,
                tint: compressedTint
            ),
            .init(id: "cached", fraction: Double(snapshot.ramCachedBytes) / total, tint: cachedTint),
        ]
    }

    private var pressureCard: some View {
        MonitorDetailCard(title: "Pressure & swap") {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    MonitorMetricRow(
                        label: String(localized: "Memory pressure"),
                        value: MonitorFormat.percent(fraction: snapshot.memoryPressureFraction),
                        tint: MonitorTint.forCapacity(fraction: snapshot.memoryPressureFraction)
                    )
                    MonitorBar(
                        fraction: snapshot.memoryPressureFraction,
                        tint: MonitorTint.forCapacity(fraction: snapshot.memoryPressureFraction)
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    MonitorMetricRow(
                        label: String(localized: "Swap used"),
                        value: swapText,
                        tint: snapshot.swapUsedBytes > 0
                            ? MonitorTint.forCapacity(fraction: snapshot.swapUsedFraction)
                            : NotchDesign.Colors.textSecondary
                    )
                    MonitorBar(
                        fraction: snapshot.swapUsedFraction,
                        tint: MonitorTint.forCapacity(fraction: snapshot.swapUsedFraction)
                    )
                }

                MonitorMetricRow(
                    label: String(localized: "Physical memory"),
                    value: MonitorFormat.size(snapshot.ramTotalBytes),
                    tint: NotchDesign.Colors.textSecondary
                )

                Spacer(minLength: 0)
            }
        }
    }

    /// A Mac that has never swapped reports a zero-size swap file; "None" is
    /// more honest than "0 B / 0 B".
    private var swapText: String {
        guard snapshot.swapTotalBytes > 0 else { return String(localized: "None") }
        return "\(MonitorFormat.size(snapshot.swapUsedBytes)) / \(MonitorFormat.size(snapshot.swapTotalBytes))"
    }
}
