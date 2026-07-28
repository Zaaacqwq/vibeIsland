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

import Foundation

/// Fixed-capacity rolling series backing one sparkline. At the shared 2-second
/// tick, 60 samples is two minutes of history — enough to read a trend in a
/// 40pt-wide tile without holding an unbounded array.
///
/// Deliberately a plain value type: the monitor publishes histories as a single
/// `Equatable` bundle, so SwiftUI diffs them like any other state instead of
/// each sparkline observing its own object.
struct MonitorHistory: Equatable, Sendable {
    static let capacity = 60

    private(set) var samples: [Double] = []

    init() {}

    init(samples: [Double]) {
        self.samples = Array(samples.suffix(Self.capacity))
    }

    mutating func append(_ value: Double) {
        samples.append(value)
        if samples.count > Self.capacity {
            samples.removeFirst(samples.count - Self.capacity)
        }
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    var latest: Double { samples.last ?? 0 }

    var peak: Double { samples.max() ?? 0 }

    /// Samples mapped into 0...1 against `ceiling`. Percentage series pass 100;
    /// rate series pass their own running peak so the curve stays legible when
    /// throughput is low. A zero/negative ceiling flattens the line rather than
    /// dividing by zero.
    func normalized(ceiling: Double) -> [Double] {
        guard ceiling > 0 else { return samples.map { _ in 0 } }
        return samples.map { min(max($0 / ceiling, 0), 1) }
    }

    /// Ceiling for an unbounded rate series: the running peak, floored at
    /// `minimum` so an idle line doesn't amplify noise to full scale.
    func rateCeiling(minimum: Double) -> Double {
        max(peak, minimum)
    }
}

/// Every series the Monitor tab charts, bundled so the monitor publishes one
/// value per tick instead of eight separate `@Published` properties.
struct MonitorHistoryBundle: Equatable, Sendable {
    var cpu = MonitorHistory()
    var gpu = MonitorHistory()
    var memory = MonitorHistory()
    var netDown = MonitorHistory()
    var netUp = MonitorHistory()
    var diskRead = MonitorHistory()
    var diskWrite = MonitorHistory()
    var battery = MonitorHistory()

    mutating func record(_ snapshot: SystemStatsSnapshot) {
        cpu.append(snapshot.cpuActivePercent)
        gpu.append(snapshot.gpuPercent)
        memory.append(snapshot.ramUsedFraction * 100)
        netDown.append(snapshot.netDownBytesPerSec)
        netUp.append(snapshot.netUpBytesPerSec)
        diskRead.append(snapshot.diskReadBytesPerSec)
        diskWrite.append(snapshot.diskWriteBytesPerSec)
    }

    mutating func reset() {
        self = MonitorHistoryBundle()
    }
}
