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

/// CPU drill-in: the two-minute utilization trend and its user/system split on
/// the left, per-core load and run-queue averages on the right.
struct CPUDetailView: View {
    let snapshot: SystemStatsSnapshot
    let history: MonitorHistoryBundle
    let processes: [ProcessSample]
    let onBack: () -> Void

    var body: some View {
        MonitorDetailScaffold(
            category: .cpu,
            headline: MonitorFormat.percent(snapshot.cpuActivePercent),
            subtitle: snapshot.cpuBrand.isEmpty ? nil : snapshot.cpuBrand,
            onBack: onBack
        ) {
            HStack(spacing: 6) {
                trendCard
                    .frame(maxWidth: .infinity)
                coresCard
                    .frame(maxWidth: .infinity)
                MonitorProcessList(
                    title: "Top processes",
                    rows: processes,
                    format: MonitorProcessList.percentFormat,
                    // A process percentage is per-core, so a busy thread can
                    // read over 100% — the shared load ramp would paint every
                    // such row red, so these stay on the neutral text colour.
                    isLoading: processes.isEmpty
                )
                .frame(width: MonitorProcessList.columnWidth)
            }
        }
    }

    private var trendCard: some View {
        MonitorDetailCard(title: "Utilization · 2 min") {
            VStack(alignment: .leading, spacing: 6) {
                MonitorSparkline(
                    normalized: history.cpu.normalized(ceiling: 100),
                    tint: MonitorCategory.cpu.tint
                )
                .frame(maxHeight: .infinity)

                MonitorMetricRow(
                    label: String(localized: "User"),
                    value: MonitorFormat.percent(snapshot.cpu.user),
                    swatch: MonitorCategory.cpu.tint
                )
                MonitorMetricRow(
                    label: String(localized: "System"),
                    value: MonitorFormat.percent(snapshot.cpu.system),
                    swatch: NotchDesign.Colors.danger
                )
                MonitorMetricRow(
                    label: String(localized: "Idle"),
                    value: MonitorFormat.percent(snapshot.cpu.idle),
                    tint: NotchDesign.Colors.textSecondary,
                    swatch: Color.white.opacity(0.18)
                )
            }
        }
    }

    private var coresCard: some View {
        MonitorDetailCard(title: coresTitle) {
            VStack(alignment: .leading, spacing: 7) {
                coreBars
                    .frame(maxHeight: .infinity)

                HStack(spacing: 0) {
                    MonitorStatBlock(
                        label: "Load 1m",
                        value: MonitorFormat.loadAverage(snapshot.loadAverage1)
                    )
                    MonitorStatBlock(
                        label: "5m",
                        value: MonitorFormat.loadAverage(snapshot.loadAverage5)
                    )
                    MonitorStatBlock(
                        label: "15m",
                        value: MonitorFormat.loadAverage(snapshot.loadAverage15)
                    )
                }
            }
        }
    }

    private var coresTitle: String {
        guard snapshot.logicalCoreCount > 0 else { return String(localized: "Cores") }
        if snapshot.physicalCoreCount > 0, snapshot.physicalCoreCount != snapshot.logicalCoreCount {
            return String(localized: "\(snapshot.physicalCoreCount) cores · \(snapshot.logicalCoreCount) threads")
        }
        return String(localized: "\(snapshot.logicalCoreCount) cores")
    }

    /// One vertical bar per logical core, filling upward. Bars share the row's
    /// width so a 4-core Mac and a 24-core Mac both stay inside the card.
    @ViewBuilder
    private var coreBars: some View {
        if snapshot.perCoreActive.isEmpty {
            Text(String(localized: "Per-core data unavailable"))
                .font(NotchDesign.Typography.voice(10))
                .foregroundStyle(NotchDesign.Colors.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            GeometryReader { proxy in
                let count = snapshot.perCoreActive.count
                let spacing: CGFloat = count > 12 ? 1.5 : 3
                let width = max((proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count), 1)
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(Array(snapshot.perCoreActive.enumerated()), id: \.offset) { _, load in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(MonitorTint.forLoad(percent: load))
                                .frame(height: max(proxy.size.height * (load / 100), 1.5))
                        }
                        .frame(width: width)
                        .background(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .frame(width: width)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}
