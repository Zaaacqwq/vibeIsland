/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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

/// Closed-pill ambient weather indicator: a weather glyph on the leading
/// accessory and the current temperature on the trailing accessory, flanking
/// the physical notch. Lowest-priority activity — shows when the pill is idle.
struct WeatherLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    let snapshot: WeatherSnapshot
    /// Driven by the notch's hover state so the pill scales/expands on hover
    /// like the other live activities.
    let isHovering: Bool
    @State private var isExpanded: Bool = false

    private var accessoryHeight: CGFloat {
        vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)
    }

    private var accessoryWidth: CGFloat {
        isExpanded ? max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)) : 0
    }

    /// Gap between each accessory and the physical notch so the icon/temperature
    /// aren't clipped by the notch edge.
    private let notchInset: CGFloat = 8

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .background {
                    if isExpanded {
                        Image(systemName: snapshot.symbolName)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: min(accessoryHeight, 16)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
                .frame(width: accessoryWidth, height: accessoryHeight)
                .padding(.trailing, isExpanded ? notchInset : 0)

            Rectangle()
                .fill(.black)
                .frame(width: vm.physicalNotchWidth)

            Color.clear
                .background {
                    if isExpanded {
                        WeatherTemperatureBadge(snapshot: snapshot)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    }
                }
                .frame(width: accessoryWidth, height: accessoryHeight)
                .padding(.leading, isExpanded ? notchInset : 0)
        }
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0))
        .onAppear { withAnimation(.smooth(duration: 0.4)) { isExpanded = true } }
    }
}

/// Compact temperature text used in both the trailing accessory and the
/// music-paired wing.
struct WeatherTemperatureBadge: View {
    let snapshot: WeatherSnapshot

    var body: some View {
        // temperatureText already carries the degree glyph (e.g. "20°").
        Text(snapshot.temperatureText)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
    }
}

/// The wing shown when weather is paired beside another activity (dual mode):
/// just the temperature, so it stays legible in the narrow side accessory
/// (the weather glyph appears in single mode and the album-art badge).
struct WeatherMusicWingView: View {
    let snapshot: WeatherSnapshot

    var body: some View {
        WeatherTemperatureBadge(snapshot: snapshot)
    }
}
