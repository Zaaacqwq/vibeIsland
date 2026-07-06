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

import Combine
import Darwin
import Foundation
import IOKit
import IOKit.graphics

/// Live system-stats sampler for the open-notch header widget. The sampling
/// routines (CPU HOST_CPU_LOAD_INFO delta, RAM HOST_VM_INFO64, GPU
/// IOAccelerator, disk IOStorage, network `getifaddrs`) are ported from the
/// retired `StatsManager` so the header reuses the same battle-tested math,
/// trimmed to the handful of headline figures the Home widget shows. Sampling
/// is on-demand: only runs while the notch is open on the Home tab.
@MainActor
final class SystemStatsMonitor: ObservableObject {
    static let shared = SystemStatsMonitor()

    /// The single snapshot the header renders. All rate fields are bytes/second.
    struct Snapshot: Equatable {
        var cpu: CPULoadBreakdown = .zero
        var gpuPercent: Double = 0
        var ramUsedBytes: UInt64 = 0
        var ramTotalBytes: UInt64 = 0
        var diskUsedBytes: UInt64 = 0
        var diskTotalBytes: UInt64 = 0
        var netDownBytesPerSec: Double = 0
        var netUpBytesPerSec: Double = 0

        static let zero = Snapshot()

        var cpuActivePercent: Double { cpu.activeUsage }

        var ramUsedFraction: Double {
            guard ramTotalBytes > 0 else { return 0 }
            return min(max(Double(ramUsedBytes) / Double(ramTotalBytes), 0), 1)
        }

        var diskUsedFraction: Double {
            guard diskTotalBytes > 0 else { return 0 }
            return min(max(Double(diskUsedBytes) / Double(diskTotalBytes), 0), 1)
        }
    }

    @Published private(set) var snapshot: Snapshot = .zero

    private let pollInterval: TimeInterval = 2
    private var monitorTask: Task<Void, Never>?

    private let hostPort: mach_port_t = mach_host_self()
    private var previousCPULoadInfo: host_cpu_load_info?

    // Rate baseline for network (cumulative byte counters + wall clock).
    private var previousNet: (inBytes: UInt64, outBytes: UInt64)?
    private var previousSampleTime: Date?

    /// Physical RAM, resolved once. Falls back to `ProcessInfo` if the mach call
    /// fails.
    private let totalPhysicalMemory: UInt64 = {
        var stats = host_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let initHostPort = mach_host_self()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_info(initHostPort, HOST_BASIC_INFO, $0, &count)
            }
        }
        mach_port_deallocate(mach_task_self_, initHostPort)
        if result == KERN_SUCCESS {
            return UInt64(stats.max_mem)
        }
        return UInt64(ProcessInfo.processInfo.physicalMemory)
    }()

    private init() {}

    // MARK: - Lifecycle

    func startMonitoring() {
        guard monitorTask == nil else { return }
        // Seed immediately so the widget shows a value on the first frame; the
        // CPU delta and disk/net rates need a prior sample, so those read as a
        // whole-uptime average / zero until the second tick lands.
        sample()
        monitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(self.pollInterval))
                } catch {
                    break
                }
                self.sample()
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        previousCPULoadInfo = nil
        previousNet = nil
        previousSampleTime = nil
    }

    // MARK: - Sampling

    private func sample() {
        let now = Date()
        let dt = previousSampleTime.map { now.timeIntervalSince($0) } ?? 0

        let cpu = getCPULoadBreakdown()
        let (ramUsed, ramTotal) = getMemoryUsage()
        let gpu = getGPUPercent()
        let (diskUsed, diskTotal) = getDiskCapacity()

        let net = getNetworkCounters()
        let (netDown, netUp) = rate(current: net, previous: previousNet, dt: dt)

        previousNet = net
        previousSampleTime = now

        var next = Snapshot()
        next.cpu = cpu
        next.gpuPercent = gpu
        next.ramUsedBytes = ramUsed
        next.ramTotalBytes = ramTotal
        next.diskUsedBytes = diskUsed
        next.diskTotalBytes = diskTotal
        next.netDownBytesPerSec = netDown
        next.netUpBytesPerSec = netUp
        if next != snapshot { snapshot = next }
    }

    /// Turns two cumulative counters into bytes/second, guarding against the
    /// first sample and counter resets (clamped to non-negative).
    private func rate(current: (UInt64, UInt64), previous: (UInt64, UInt64)?, dt: TimeInterval) -> (Double, Double) {
        guard let previous, dt > 0.1 else { return (0, 0) }
        let a = current.0 >= previous.0 ? Double(current.0 - previous.0) / dt : 0
        let b = current.1 >= previous.1 ? Double(current.1 - previous.1) / dt : 0
        return (a, b)
    }

    /// Ported from `StatsManager.getCPULoadBreakdown` — HOST_CPU_LOAD_INFO tick
    /// deltas between samples.
    private func getCPULoadBreakdown() -> CPULoadBreakdown {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return snapshot.cpu }

        let clamped: (Double) -> Double = { min(max($0, 0), 100) }
        let breakdown: CPULoadBreakdown

        if let previous = previousCPULoadInfo {
            let userDiff = Double(info.cpu_ticks.0 - previous.cpu_ticks.0)
            let systemDiff = Double(info.cpu_ticks.1 - previous.cpu_ticks.1)
            let idleDiff = Double(info.cpu_ticks.2 - previous.cpu_ticks.2)
            let niceDiff = Double(info.cpu_ticks.3 - previous.cpu_ticks.3)
            let total = userDiff + systemDiff + idleDiff + niceDiff
            if total > 0 {
                breakdown = CPULoadBreakdown(
                    user: clamped(((userDiff + niceDiff) / total) * 100),
                    system: clamped((systemDiff / total) * 100),
                    idle: clamped((idleDiff / total) * 100)
                )
            } else {
                breakdown = snapshot.cpu
            }
        } else {
            let totalTicks = Double(info.cpu_ticks.0 + info.cpu_ticks.1 + info.cpu_ticks.2 + info.cpu_ticks.3)
            if totalTicks > 0 {
                breakdown = CPULoadBreakdown(
                    user: clamped(((Double(info.cpu_ticks.0) + Double(info.cpu_ticks.3)) / totalTicks) * 100),
                    system: clamped((Double(info.cpu_ticks.1) / totalTicks) * 100),
                    idle: clamped((Double(info.cpu_ticks.2) / totalTicks) * 100)
                )
            } else {
                breakdown = snapshot.cpu
            }
        }

        previousCPULoadInfo = info
        return breakdown
    }

    /// Ported from `StatsManager.getMemorySnapshot` — HOST_VM_INFO64, trimmed to
    /// the used/total figures (swap + pressure detail dropped, not needed here).
    private func getMemoryUsage() -> (used: UInt64, total: UInt64) {
        var vmStatistics = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let vmResult = withUnsafeMutablePointer(to: &vmStatistics) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &size)
            }
        }

        guard vmResult == KERN_SUCCESS else {
            return (snapshot.ramUsedBytes, snapshot.ramTotalBytes)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let freeBytes = UInt64(vmStatistics.free_count) * pageSize
        let speculativeBytes = UInt64(vmStatistics.speculative_count) * pageSize
        let activeBytes = UInt64(vmStatistics.active_count) * pageSize
        let inactiveBytes = UInt64(vmStatistics.inactive_count) * pageSize
        let wiredBytes = UInt64(vmStatistics.wire_count) * pageSize
        let compressedBytes = UInt64(vmStatistics.compressor_page_count) * pageSize
        let purgeableBytes = UInt64(vmStatistics.purgeable_count) * pageSize
        let externalBytes = UInt64(vmStatistics.external_page_count) * pageSize

        let totalMemoryBytes: UInt64
        if totalPhysicalMemory > 0 {
            totalMemoryBytes = totalPhysicalMemory
        } else {
            totalMemoryBytes = freeBytes + speculativeBytes + activeBytes + inactiveBytes + wiredBytes + compressedBytes
        }
        guard totalMemoryBytes > 0 else { return (0, 0) }

        // Match Activity Monitor's "Memory Used": active + inactive + speculative
        // + wired + compressed, less the reclaimable file cache.
        let usedWithoutCache = activeBytes + inactiveBytes + speculativeBytes + wiredBytes + compressedBytes
        let cacheBytes = purgeableBytes + externalBytes
        let usedBytes = usedWithoutCache > cacheBytes ? usedWithoutCache - cacheBytes : 0
        let clampedUsedBytes = min(usedBytes, totalMemoryBytes)

        return (clampedUsedBytes, totalMemoryBytes)
    }

    /// Average GPU "Device Utilization %" across IOAccelerator devices. Lean
    /// port of `StatsManager`'s `GPUInfoCollector` (utilization only).
    private func getGPUPercent() -> Double {
        let matching = IOServiceMatching(kIOAcceleratorClassName)
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return snapshot.gpuPercent
        }
        defer { IOObjectRelease(iterator) }

        var values: [Double] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = properties?.takeRetainedValue() as? [String: Any],
               let stats = dict["PerformanceStatistics"] as? [String: Any] {
                for key in ["Device Utilization %", "GPU Activity(%)"] {
                    if let number = stats[key] as? NSNumber {
                        values.append(min(max(number.doubleValue, 0), 100))
                        break
                    }
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Used / total capacity of the boot volume. `availableForImportantUsage`
    /// mirrors what Finder reports as free space (purgeable excluded).
    private func getDiskCapacity() -> (used: UInt64, total: UInt64) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]), let total = values.volumeTotalCapacity else {
            return (snapshot.diskUsedBytes, snapshot.diskTotalBytes)
        }
        let totalBytes = UInt64(max(total, 0))
        let availableBytes = UInt64(max(values.volumeAvailableCapacityForImportantUsage ?? 0, 0))
        let usedBytes = totalBytes > availableBytes ? totalBytes - availableBytes : 0
        return (usedBytes, totalBytes)
    }

    /// Cumulative in/out bytes across physical (en*/Wi-Fi) interfaces. Ported
    /// from `StatsManager.getNetworkStats`.
    private func getNetworkCounters() -> (inBytes: UInt64, outBytes: UInt64) {
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        var ifaddrsPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrsPtr) == 0 else { return (totalIn, totalOut) }
        defer { freeifaddrs(ifaddrsPtr) }

        var ptr = ifaddrsPtr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee,
                  interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else {
                continue
            }
            let name = String(cString: interface.ifa_name)
            guard !name.hasPrefix("lo"),
                  !name.hasPrefix("gif"),
                  !name.hasPrefix("stf"),
                  !name.hasPrefix("bridge"),
                  !name.hasPrefix("utun"),
                  !name.hasPrefix("awdl") else {
                continue
            }
            if name.hasPrefix("en") || name.contains("Wi-Fi") {
                if let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    totalIn += UInt64(data.pointee.ifi_ibytes)
                    totalOut += UInt64(data.pointee.ifi_obytes)
                }
            }
        }
        return (totalIn, totalOut)
    }
}
