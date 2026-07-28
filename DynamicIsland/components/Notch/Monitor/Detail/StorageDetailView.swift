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

/// Storage drill-in: boot-volume capacity on the left, live disk throughput on
/// the right.
///
/// The two halves answer different questions — "am I running out of space" is
/// a capacity bar, "is something hammering the disk right now" is a rate chart —
/// so they get equal billing rather than one headline number.
struct StorageDetailView: View {
    let snapshot: SystemStatsSnapshot
    let history: MonitorHistoryBundle
    let onBack: () -> Void

    private var readTint: Color { NotchDesign.Colors.info }
    private var writeTint: Color { NotchDesign.Colors.danger }

    var body: some View {
        MonitorDetailScaffold(
            category: .storage,
            headline: "\(MonitorFormat.size(snapshot.diskFreeBytes)) free",
            subtitle: snapshot.volumeName.isEmpty ? nil : snapshot.volumeName,
            onBack: onBack
        ) {
            HStack(spacing: 6) {
                capacityCard
                    .frame(width: 220)
                throughputCard
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var capacityCard: some View {
        MonitorDetailCard(title: "Capacity") {
            VStack(alignment: .leading, spacing: 8) {
                MonitorBar(
                    fraction: snapshot.diskUsedFraction,
                    tint: MonitorTint.forCapacity(fraction: snapshot.diskUsedFraction),
                    height: 7
                )

                MonitorMetricRow(
                    label: String(localized: "Used"),
                    value: MonitorFormat.size(snapshot.diskUsedBytes),
                    tint: MonitorTint.forCapacity(fraction: snapshot.diskUsedFraction),
                    swatch: MonitorCategory.storage.tint
                )
                MonitorMetricRow(
                    label: String(localized: "Available"),
                    value: MonitorFormat.size(snapshot.diskFreeBytes),
                    swatch: Color.white.opacity(0.18)
                )
                MonitorMetricRow(
                    label: String(localized: "Total"),
                    value: MonitorFormat.size(snapshot.diskTotalBytes),
                    tint: NotchDesign.Colors.textSecondary
                )

                Spacer(minLength: 0)
            }
        }
    }

    private var throughputCard: some View {
        MonitorDetailCard(title: "Throughput · 2 min") {
            VStack(alignment: .leading, spacing: 7) {
                // Read and write share one ceiling so the taller line genuinely
                // means more bytes moved, not just a different scale.
                let ceiling = max(
                    history.diskRead.rateCeiling(minimum: 1_048_576),
                    history.diskWrite.rateCeiling(minimum: 1_048_576)
                )
                MonitorDualSparkline(
                    primary: history.diskRead.normalized(ceiling: ceiling),
                    secondary: history.diskWrite.normalized(ceiling: ceiling),
                    primaryTint: readTint,
                    secondaryTint: writeTint
                )
                .frame(maxHeight: .infinity)

                HStack(spacing: 0) {
                    MonitorStatBlock(
                        label: "Read",
                        value: MonitorFormat.rateParts(snapshot.diskReadBytesPerSec, useBits: false).value,
                        unit: MonitorFormat.rateParts(snapshot.diskReadBytesPerSec, useBits: false).unit,
                        tint: readTint
                    )
                    MonitorStatBlock(
                        label: "Write",
                        value: MonitorFormat.rateParts(snapshot.diskWriteBytesPerSec, useBits: false).value,
                        unit: MonitorFormat.rateParts(snapshot.diskWriteBytesPerSec, useBits: false).unit,
                        tint: writeTint
                    )
                    MonitorStatBlock(
                        label: "Peak read",
                        value: MonitorFormat.rateParts(history.diskRead.peak, useBits: false).value,
                        unit: MonitorFormat.rateParts(history.diskRead.peak, useBits: false).unit,
                        tint: NotchDesign.Colors.textSecondary
                    )
                }
            }
        }
    }
}
