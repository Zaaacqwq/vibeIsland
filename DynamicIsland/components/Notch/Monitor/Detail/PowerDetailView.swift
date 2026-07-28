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

/// Power drill-in: charge state and the battery's long-term condition.
///
/// Every deep figure here is optional — `AppleSmartBattery` key names differ
/// across Intel and Apple silicon, and desktops publish no battery node at all.
/// Missing rows are omitted rather than shown as zero, so the card never
/// asserts something it did not measure.
struct PowerDetailView: View {
    let snapshot: PowerStatsMonitor.Snapshot
    let onBack: () -> Void

    var body: some View {
        MonitorDetailScaffold(
            category: .power,
            headline: headline,
            subtitle: stateSubtitle,
            onBack: onBack
        ) {
            if snapshot.hasBattery {
                HStack(spacing: 6) {
                    chargeCard
                        .frame(maxWidth: .infinity)
                    healthCard
                        .frame(maxWidth: .infinity)
                    adapterCard
                        .frame(width: 165)
                }
            } else {
                desktopCard
            }
        }
    }

    private var headline: String {
        guard snapshot.hasBattery else { return String(localized: "AC power") }
        return MonitorFormat.percent(fraction: snapshot.chargeFraction)
    }

    private var stateSubtitle: String {
        if snapshot.isInLowPowerMode { return String(localized: "Low Power Mode") }
        if snapshot.isCharging { return String(localized: "Charging") }
        if snapshot.isPluggedIn { return String(localized: "Plugged in") }
        return String(localized: "On battery")
    }

    // MARK: - Cards

    private var chargeCard: some View {
        MonitorDetailCard(title: "Charge") {
            VStack(alignment: .leading, spacing: 8) {
                MonitorBar(
                    fraction: snapshot.chargeFraction,
                    tint: MonitorTint.forCharge(
                        fraction: snapshot.chargeFraction,
                        isCharging: snapshot.isCharging
                    ),
                    height: 7
                )

                if let minutes = remainingMinutes {
                    MonitorMetricRow(
                        label: snapshot.isCharging
                            ? String(localized: "Until full")
                            : String(localized: "Time remaining"),
                        value: MonitorFormat.duration(minutes: minutes)
                    )
                }
                if let watts = snapshot.powerWatts {
                    // Sign carries the direction, so state it in words rather
                    // than making the reader decode a minus.
                    MonitorMetricRow(
                        label: watts >= 0
                            ? String(localized: "Charging at")
                            : String(localized: "Drawing"),
                        value: String(format: "%.1f W", abs(watts))
                    )
                }
                if let temperature = snapshot.temperatureCelsius {
                    MonitorMetricRow(
                        label: String(localized: "Temperature"),
                        value: MonitorFormat.temperature(celsius: temperature),
                        tint: temperature > 40 ? NotchDesign.Colors.warning : NotchDesign.Colors.textPrimary
                    )
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var remainingMinutes: Int? {
        snapshot.isCharging ? snapshot.minutesToFull : snapshot.minutesToEmpty
    }

    private var healthCard: some View {
        MonitorDetailCard(title: "Condition") {
            VStack(alignment: .leading, spacing: 8) {
                if let health = snapshot.healthFraction {
                    MonitorBar(
                        fraction: health,
                        tint: snapshot.isHealthDegraded
                            ? NotchDesign.Colors.warning
                            : NotchDesign.Colors.success,
                        height: 7
                    )
                    MonitorMetricRow(
                        label: String(localized: "Maximum capacity"),
                        value: MonitorFormat.precisePercent(fraction: health),
                        tint: snapshot.isHealthDegraded
                            ? NotchDesign.Colors.warning
                            : NotchDesign.Colors.textPrimary
                    )
                }
                if let cycles = snapshot.cycleCount {
                    MonitorMetricRow(
                        label: String(localized: "Cycle count"),
                        value: "\(cycles)"
                    )
                }
                if let current = snapshot.currentMaxCapacitymAh, let design = snapshot.designCapacitymAh {
                    MonitorMetricRow(
                        label: String(localized: "Capacity"),
                        value: "\(current) / \(design) mAh",
                        tint: NotchDesign.Colors.textSecondary
                    )
                }
                if snapshot.healthFraction == nil && snapshot.cycleCount == nil {
                    Text(String(localized: "Condition data unavailable on this Mac"))
                        .font(NotchDesign.Typography.voice(10))
                        .foregroundStyle(NotchDesign.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var adapterCard: some View {
        MonitorDetailCard(title: "Adapter") {
            VStack(alignment: .leading, spacing: 6) {
                MonitorMetricRow(
                    label: String(localized: "Connected"),
                    value: snapshot.isPluggedIn ? String(localized: "Yes") : String(localized: "No"),
                    tint: snapshot.isPluggedIn
                        ? NotchDesign.Colors.success
                        : NotchDesign.Colors.textSecondary
                )
                if let watts = snapshot.adapterWatts {
                    MonitorMetricRow(label: String(localized: "Rated"), value: "\(watts) W")
                }
                if let name = snapshot.adapterName {
                    MonitorMetricRow(
                        label: String(localized: "Model"),
                        value: name,
                        tint: NotchDesign.Colors.textSecondary
                    )
                }
                if let voltage = snapshot.voltageV {
                    MonitorMetricRow(
                        label: String(localized: "Voltage"),
                        value: String(format: "%.2f V", voltage),
                        tint: NotchDesign.Colors.textSecondary
                    )
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var desktopCard: some View {
        MonitorDetailCard(title: "Power source") {
            VStack(alignment: .leading, spacing: 6) {
                MonitorMetricRow(
                    label: String(localized: "Source"),
                    value: String(localized: "Wall power"),
                    tint: NotchDesign.Colors.success
                )
                MonitorMetricRow(
                    label: String(localized: "Low Power Mode"),
                    value: snapshot.isInLowPowerMode
                        ? String(localized: "On")
                        : String(localized: "Off")
                )
                Text(String(localized: "This Mac has no battery, so charge and condition are not reported."))
                    .font(NotchDesign.Typography.voice(10))
                    .foregroundStyle(NotchDesign.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
        }
    }
}
