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

/// Network drill-in: live down/up throughput charted together, with the active
/// interface and since-boot totals alongside.
struct NetworkDetailView: View {
    let snapshot: SystemStatsSnapshot
    let history: MonitorHistoryBundle
    let processes: [ProcessSample]
    let isLoadingProcesses: Bool
    let onBack: () -> Void

    private var downTint: Color { NotchDesign.Colors.info }
    private var upTint: Color { NotchDesign.Colors.danger }

    var body: some View {
        MonitorDetailScaffold(
            category: .network,
            headline: MonitorFormat.rate(snapshot.netDownBytesPerSec),
            subtitle: interfaceSubtitle,
            onBack: onBack
        ) {
            HStack(spacing: 6) {
                throughputCard
                    .frame(maxWidth: .infinity)
                interfaceCard
                    .frame(maxWidth: .infinity)
                // Live per-process rates, down then up, tinted to match the
                // throughput chart's two lines.
                MonitorProcessList(
                    title: "Top processes",
                    rows: processes,
                    format: MonitorProcessList.compactRateFormat,
                    tint: downTint,
                    secondaryTint: upTint,
                    isLoading: isLoadingProcesses,
                    emptyMessage: String(localized: "No active transfers")
                )
                .frame(width: MonitorProcessList.dualColumnWidth)
            }
        }
    }

    private var interfaceSubtitle: String? {
        guard !snapshot.primaryInterfaceName.isEmpty else { return nil }
        guard !snapshot.primaryIPv4Address.isEmpty else { return snapshot.primaryInterfaceName }
        return "\(snapshot.primaryInterfaceName) · \(snapshot.primaryIPv4Address)"
    }

    private var throughputCard: some View {
        MonitorDetailCard(title: "Throughput · 2 min") {
            VStack(alignment: .leading, spacing: 7) {
                // One shared ceiling across both directions, floored at 64 KB/s
                // so an idle link shows a flat line instead of amplifying noise
                // into a mountain range.
                let ceiling = max(
                    history.netDown.rateCeiling(minimum: 65_536),
                    history.netUp.rateCeiling(minimum: 65_536)
                )
                MonitorDualSparkline(
                    primary: history.netDown.normalized(ceiling: ceiling),
                    secondary: history.netUp.normalized(ceiling: ceiling),
                    primaryTint: downTint,
                    secondaryTint: upTint
                )
                .frame(maxHeight: .infinity)

                HStack(spacing: 0) {
                    MonitorStatBlock(
                        label: "Down",
                        value: MonitorFormat.rateParts(snapshot.netDownBytesPerSec).value,
                        unit: MonitorFormat.rateParts(snapshot.netDownBytesPerSec).unit,
                        tint: downTint
                    )
                    MonitorStatBlock(
                        label: "Up",
                        value: MonitorFormat.rateParts(snapshot.netUpBytesPerSec).value,
                        unit: MonitorFormat.rateParts(snapshot.netUpBytesPerSec).unit,
                        tint: upTint
                    )
                    MonitorStatBlock(
                        label: "Peak down",
                        value: MonitorFormat.rateParts(history.netDown.peak).value,
                        unit: MonitorFormat.rateParts(history.netDown.peak).unit,
                        tint: NotchDesign.Colors.textSecondary
                    )
                }
            }
        }
    }

    private var interfaceCard: some View {
        MonitorDetailCard(title: "Interface") {
            VStack(alignment: .leading, spacing: 6) {
                MonitorMetricRow(
                    label: String(localized: "Active"),
                    value: snapshot.primaryInterfaceName.isEmpty
                        ? String(localized: "None")
                        : snapshot.primaryInterfaceName
                )
                MonitorMetricRow(
                    label: String(localized: "IPv4"),
                    value: snapshot.primaryIPv4Address.isEmpty
                        ? String(localized: "Not assigned")
                        : snapshot.primaryIPv4Address,
                    tint: NotchDesign.Colors.textSecondary
                )

                Rectangle()
                    .fill(NotchDesign.Colors.hairline)
                    .frame(height: NotchDesign.hairlineWidth)
                    .padding(.vertical, 1)

                // Interface counters reset at boot, not at midnight — label it
                // so the number isn't mistaken for daily usage.
                MonitorMetricRow(
                    label: String(localized: "Received · boot"),
                    value: MonitorFormat.size(snapshot.netTotalInBytes),
                    swatch: downTint
                )
                MonitorMetricRow(
                    label: String(localized: "Sent · boot"),
                    value: MonitorFormat.size(snapshot.netTotalOutBytes),
                    swatch: upTint
                )

                Spacer(minLength: 0)
            }
        }
    }
}
