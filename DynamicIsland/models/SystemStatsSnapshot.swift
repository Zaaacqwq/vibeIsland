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

/// One sampling tick's worth of CPU / GPU / memory / storage / network figures.
///
/// Lives at top level (rather than nested in `SystemStatsMonitor`) so it can
/// cross the actor boundary from the off-main `SystemStatsSampler` to the
/// `@MainActor` monitor without isolation gymnastics. `SystemStatsMonitor`
/// keeps a `Snapshot` typealias so existing call sites read unchanged.
///
/// All `*BytesPerSec` fields are rates; everything else is an instantaneous
/// reading. Fields the host can't answer stay at their zero value rather than
/// being optional — the views decide what "0" means per metric.
struct SystemStatsSnapshot: Equatable, Sendable {
    // MARK: CPU

    var cpu: CPULoadBreakdown = .zero
    /// Active (user + system) percentage per logical core, in core order.
    /// Empty when `host_processor_info` is unavailable.
    var perCoreActive: [Double] = []
    var physicalCoreCount: Int = 0
    var logicalCoreCount: Int = 0
    /// `getloadavg` 1 / 5 / 15-minute run-queue averages.
    var loadAverage1: Double = 0
    var loadAverage5: Double = 0
    var loadAverage15: Double = 0
    var cpuBrand: String = ""

    // MARK: GPU

    var gpuPercent: Double = 0
    var gpuName: String = ""
    /// Total VRAM as reported by the accelerator. 0 on unified-memory Macs that
    /// don't publish a separate figure.
    var gpuVRAMBytes: UInt64 = 0

    // MARK: Memory

    var ramUsedBytes: UInt64 = 0
    var ramTotalBytes: UInt64 = 0
    var ramWiredBytes: UInt64 = 0
    var ramCompressedBytes: UInt64 = 0
    var ramActiveBytes: UInt64 = 0
    var ramCachedBytes: UInt64 = 0
    var swapUsedBytes: UInt64 = 0
    var swapTotalBytes: UInt64 = 0

    // MARK: Storage

    var diskUsedBytes: UInt64 = 0
    var diskTotalBytes: UInt64 = 0
    var diskReadBytesPerSec: Double = 0
    var diskWriteBytesPerSec: Double = 0
    var volumeName: String = ""

    // MARK: Network

    var netDownBytesPerSec: Double = 0
    var netUpBytesPerSec: Double = 0
    /// Cumulative counters since boot, across the same interfaces the rates use.
    var netTotalInBytes: UInt64 = 0
    var netTotalOutBytes: UInt64 = 0
    var primaryInterfaceName: String = ""
    var primaryIPv4Address: String = ""

    static let zero = SystemStatsSnapshot()

    // MARK: - Derived

    var cpuActivePercent: Double { cpu.activeUsage }

    var ramUsedFraction: Double { fraction(ramUsedBytes, of: ramTotalBytes) }

    var diskUsedFraction: Double { fraction(diskUsedBytes, of: diskTotalBytes) }

    var swapUsedFraction: Double { fraction(swapUsedBytes, of: swapTotalBytes) }

    /// Activity Monitor's memory-pressure proxy: the share of RAM held by pages
    /// the kernel cannot simply evict (wired + compressed).
    var memoryPressureFraction: Double {
        fraction(ramWiredBytes + ramCompressedBytes, of: ramTotalBytes)
    }

    var diskFreeBytes: UInt64 {
        diskTotalBytes > diskUsedBytes ? diskTotalBytes - diskUsedBytes : 0
    }

    private func fraction(_ part: UInt64, of whole: UInt64) -> Double {
        guard whole > 0 else { return 0 }
        return min(max(Double(part) / Double(whole), 0), 1)
    }
}
