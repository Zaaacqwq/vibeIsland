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

/// GPU drill-in: the utilization trend plus what little identity the
/// accelerator publishes.
///
/// Thinner than the other cards by necessity — IOAccelerator exposes device
/// utilization reliably, but not clock, power or temperature, so this view
/// states what is measurable instead of padding with invented figures.
struct GPUDetailView: View {
    let snapshot: SystemStatsSnapshot
    let history: MonitorHistoryBundle
    let onBack: () -> Void

    var body: some View {
        MonitorDetailScaffold(
            category: .gpu,
            headline: MonitorFormat.percent(snapshot.gpuPercent),
            subtitle: snapshot.gpuName.isEmpty ? nil : snapshot.gpuName,
            onBack: onBack
        ) {
            HStack(spacing: 6) {
                MonitorDetailCard(title: "Utilization · 2 min") {
                    MonitorSparkline(
                        normalized: history.gpu.normalized(ceiling: 100),
                        tint: MonitorCategory.gpu.tint
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)

                MonitorDetailCard(title: "Device") {
                    VStack(alignment: .leading, spacing: 6) {
                        MonitorMetricRow(
                            label: String(localized: "Peak · 2 min"),
                            value: MonitorFormat.percent(history.gpu.peak)
                        )
                        MonitorMetricRow(
                            label: String(localized: "Video memory"),
                            value: vramText,
                            tint: snapshot.gpuVRAMBytes > 0
                                ? NotchDesign.Colors.textPrimary
                                : NotchDesign.Colors.textSecondary
                        )
                        MonitorMetricRow(
                            label: String(localized: "Renderer"),
                            value: snapshot.gpuName.isEmpty ? String(localized: "Unknown") : snapshot.gpuName,
                            tint: NotchDesign.Colors.textSecondary
                        )
                        Spacer(minLength: 0)
                    }
                }
                .frame(width: 200)
            }
        }
    }

    /// Apple silicon shares system RAM with the GPU and publishes no separate
    /// VRAM key, so 0 means "unified" rather than "none".
    private var vramText: String {
        guard snapshot.gpuVRAMBytes > 0 else { return String(localized: "Unified") }
        return MonitorFormat.size(snapshot.gpuVRAMBytes)
    }
}
