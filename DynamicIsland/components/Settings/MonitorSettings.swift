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

import Defaults
import SwiftUI

/// Settings pane for the Monitor tab: master switch, which cards appear in the
/// overview grid, and the throughput unit preference.
struct MonitorSettings: View {
    @Default(.enableSystemMonitor) private var enableSystemMonitor
    @Default(.monitorCategories) private var monitorCategories
    @Default(.monitorNetworkUsesBits) private var monitorNetworkUsesBits

    var body: some View {
        GeistSettingsPage(
            title: "System Monitor",
            subtitle: "A live CPU, GPU, memory, storage, network, power and display dashboard in the notch."
        ) {
            GeistSection {
                GeistToggleRow(
                    title: "Enable system monitor",
                    description: "Adds a Monitor tab to the open notch. Tap any card to drill into its detail.",
                    isOn: $enableSystemMonitor,
                    divider: false,
                    info: widthFooter
                )
            }

            if enableSystemMonitor {
                GeistSection(
                    title: "Cards",
                    note: "If every card is turned off, all cards are shown."
                ) {
                    ForEach(Array(MonitorCategory.allCases.enumerated()), id: \.element.id) { index, category in
                        GeistToggleRow(
                            title: category.title,
                            description: description(for: category),
                            isOn: binding(for: category),
                            divider: index < MonitorCategory.allCases.count - 1
                        )
                    }
                }

                GeistSection(
                    title: "Units",
                    footer: "Sampling runs every 2 seconds, and only while the Monitor tab is open."
                ) {
                    GeistToggleRow(
                        title: "Show network speed in bits",
                        description: "Report throughput as Mb/s, the way link speeds are quoted, instead of MB/s.",
                        isOn: $monitorNetworkUsesBits,
                        divider: false
                    )
                }
            }
        }
    }

    /// Enabling an eighth tab raises the notch's minimum width, which is a
    /// visible change to the whole app — say so before the toggle is flipped
    /// rather than letting the notch silently grow.
    private var widthFooter: String {
        let width = Int(recommendedMinimumNotchWidth(forTabCount: enabledStandardTabCount()))
        return "The Monitor tab is the widest tab. With your current tabs the notch needs at least \(width)pt, and enabling more tabs widens it further."
    }

    private func description(for category: MonitorCategory) -> String {
        switch category {
        case .cpu: return "Utilization trend, per-core load and run-queue averages."
        case .gpu: return "Device utilization and renderer identity."
        case .memory: return "App, wired, compressed and cached breakdown, plus swap."
        case .storage: return "Boot-volume capacity and live read/write throughput."
        case .network: return "Down/up throughput, active interface and since-boot totals."
        case .power: return "Charge, battery condition, cycle count and adapter."
        case .display: return "Resolution, refresh rate, scaling and brightness per screen."
        }
    }

    /// Writes back in `allCases` order so the stored array always matches the
    /// grid order, whatever sequence the toggles were flipped in.
    private func binding(for category: MonitorCategory) -> Binding<Bool> {
        Binding(
            get: { monitorCategories.contains(category) },
            set: { isOn in
                var selection = Set(monitorCategories)
                if isOn {
                    selection.insert(category)
                } else {
                    selection.remove(category)
                }
                monitorCategories = MonitorCategory.allCases.filter(selection.contains)
            }
        )
    }
}
