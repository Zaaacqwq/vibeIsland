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

import Darwin
import Foundation
import IOKit
import IOKit.graphics

/// Off-main sampler for `SystemStatsMonitor`.
///
/// Every reading here is a blocking syscall or an IORegistry walk — the GPU and
/// disk passes iterate the whole matching-service list. Running them on the
/// main actor stalls SwiftUI's commit phase (the same class of problem behind
/// the render-commit stalls we fixed earlier), so the monitor `await`s this
/// actor and only the finished `SystemStatsSnapshot` hops back to main.
///
/// The actor also owns every piece of previous-sample state (CPU ticks,
/// cumulative network/disk counters, the wall clock), which is what makes the
/// rate math correct without the main actor holding any of it.
actor SystemStatsSampler {
    private let hostPort: mach_port_t = mach_host_self()

    private var previousCPULoadInfo: host_cpu_load_info?
    private var previousPerCoreTicks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []
    private var previousNet: (inBytes: UInt64, outBytes: UInt64)?
    private var previousDisk: (readBytes: UInt64, writeBytes: UInt64)?
    private var previousSampleTime: Date?

    /// Last emitted snapshot. Used purely as the fallback when an individual
    /// reading fails, so one bad tick shows the previous value instead of a
    /// misleading zero.
    private var previous: SystemStatsSnapshot = .zero

    // MARK: - Constants resolved once

    private lazy var totalPhysicalMemory: UInt64 = {
        var stats = host_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let port = mach_host_self()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_info(port, HOST_BASIC_INFO, $0, &count)
            }
        }
        mach_port_deallocate(mach_task_self_, port)
        if result == KERN_SUCCESS { return UInt64(stats.max_mem) }
        return UInt64(ProcessInfo.processInfo.physicalMemory)
    }()

    private lazy var cpuBrand: String = sysctlString("machdep.cpu.brand_string")
        ?? sysctlString("hw.model")
        ?? ""

    private lazy var physicalCoreCount: Int = sysctlInt("hw.physicalcpu") ?? 0

    private lazy var logicalCoreCount: Int = sysctlInt("hw.logicalcpu")
        ?? ProcessInfo.processInfo.processorCount

    /// GPU name and VRAM change only when displays are re-plugged, and the
    /// IORegistry walk for them is the expensive half of the GPU pass — resolve
    /// once and reuse.
    private lazy var gpuIdentity: (name: String, vramBytes: UInt64) = readGPUIdentity()

    func reset() {
        previousCPULoadInfo = nil
        previousPerCoreTicks = []
        previousNet = nil
        previousDisk = nil
        previousSampleTime = nil
        previous = .zero
    }

    // MARK: - Sampling

    func sample() -> SystemStatsSnapshot {
        let now = Date()
        let dt = previousSampleTime.map { now.timeIntervalSince($0) } ?? 0

        var next = SystemStatsSnapshot()

        // CPU
        next.cpu = sampleCPU()
        next.perCoreActive = samplePerCore()
        next.physicalCoreCount = physicalCoreCount
        next.logicalCoreCount = logicalCoreCount
        next.cpuBrand = cpuBrand
        let load = sampleLoadAverage()
        next.loadAverage1 = load.0
        next.loadAverage5 = load.1
        next.loadAverage15 = load.2

        // GPU
        next.gpuPercent = sampleGPUPercent()
        next.gpuName = gpuIdentity.name
        next.gpuVRAMBytes = gpuIdentity.vramBytes

        // Memory
        let memory = sampleMemory()
        next.ramUsedBytes = memory.used
        next.ramTotalBytes = memory.total
        next.ramWiredBytes = memory.wired
        next.ramCompressedBytes = memory.compressed
        next.ramActiveBytes = memory.active
        next.ramCachedBytes = memory.cached
        let swap = sampleSwap()
        next.swapUsedBytes = swap.used
        next.swapTotalBytes = swap.total

        // Storage
        let capacity = sampleDiskCapacity()
        next.diskUsedBytes = capacity.used
        next.diskTotalBytes = capacity.total
        next.volumeName = capacity.name
        let disk = sampleDiskCounters()
        let diskRates = rate(current: disk, previous: previousDisk, dt: dt)
        next.diskReadBytesPerSec = diskRates.0
        next.diskWriteBytesPerSec = diskRates.1
        previousDisk = disk

        // Network
        let net = sampleNetworkCounters()
        let netRates = rate(current: (net.inBytes, net.outBytes), previous: previousNet, dt: dt)
        next.netDownBytesPerSec = netRates.0
        next.netUpBytesPerSec = netRates.1
        next.netTotalInBytes = net.inBytes
        next.netTotalOutBytes = net.outBytes
        next.primaryInterfaceName = net.primaryName
        next.primaryIPv4Address = net.primaryIPv4
        previousNet = (net.inBytes, net.outBytes)

        previousSampleTime = now
        previous = next
        return next
    }

    /// Turns two cumulative counters into units/second, guarding against the
    /// first sample and counter resets (clamped to non-negative).
    private func rate(
        current: (UInt64, UInt64),
        previous: (UInt64, UInt64)?,
        dt: TimeInterval
    ) -> (Double, Double) {
        guard let previous, dt > 0.1 else { return (0, 0) }
        let a = current.0 >= previous.0 ? Double(current.0 - previous.0) / dt : 0
        let b = current.1 >= previous.1 ? Double(current.1 - previous.1) / dt : 0
        return (a, b)
    }

    // MARK: - CPU

    /// HOST_CPU_LOAD_INFO tick deltas between samples. The first sample has no
    /// predecessor, so it reports a whole-uptime average instead.
    private func sampleCPU() -> CPULoadBreakdown {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return previous.cpu }

        let breakdown: CPULoadBreakdown
        if let prior = previousCPULoadInfo {
            breakdown = Self.breakdown(
                user: Double(info.cpu_ticks.0 &- prior.cpu_ticks.0),
                system: Double(info.cpu_ticks.1 &- prior.cpu_ticks.1),
                idle: Double(info.cpu_ticks.2 &- prior.cpu_ticks.2),
                nice: Double(info.cpu_ticks.3 &- prior.cpu_ticks.3)
            ) ?? previous.cpu
        } else {
            breakdown = Self.breakdown(
                user: Double(info.cpu_ticks.0),
                system: Double(info.cpu_ticks.1),
                idle: Double(info.cpu_ticks.2),
                nice: Double(info.cpu_ticks.3)
            ) ?? previous.cpu
        }

        previousCPULoadInfo = info
        return breakdown
    }

    private static func breakdown(user: Double, system: Double, idle: Double, nice: Double) -> CPULoadBreakdown? {
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        let clamp: (Double) -> Double = { min(max($0, 0), 100) }
        return CPULoadBreakdown(
            user: clamp(((user + nice) / total) * 100),
            system: clamp((system / total) * 100),
            idle: clamp((idle / total) * 100)
        )
    }

    /// Active percentage per logical core via PROCESSOR_CPU_LOAD_INFO. Same tick
    /// delta as the aggregate pass, one entry per core.
    private func samplePerCore() -> [Double] {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &infoArray, &infoCount)
        guard result == KERN_SUCCESS, let infoArray else { return previous.perCoreActive }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: infoArray)),
                vm_size_t(UInt(infoCount) * UInt(MemoryLayout<integer_t>.size))
            )
        }

        let stride = Int(CPU_STATE_MAX)
        var current: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []
        current.reserveCapacity(Int(cpuCount))
        for core in 0..<Int(cpuCount) {
            let base = core * stride
            current.append((
                user: UInt32(bitPattern: infoArray[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: infoArray[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: infoArray[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: infoArray[base + Int(CPU_STATE_NICE)])
            ))
        }

        defer { previousPerCoreTicks = current }

        // Core count can change across samples (CPU hot-plug on some hosts);
        // fall back to a whole-uptime average rather than mismatching indices.
        let usePrevious = previousPerCoreTicks.count == current.count
        return current.enumerated().map { index, ticks in
            let prior = usePrevious ? previousPerCoreTicks[index] : (user: 0, system: 0, idle: 0, nice: 0)
            let user = Double(ticks.user &- prior.user)
            let system = Double(ticks.system &- prior.system)
            let idle = Double(ticks.idle &- prior.idle)
            let nice = Double(ticks.nice &- prior.nice)
            let total = user + system + idle + nice
            guard total > 0 else { return 0 }
            return min(max(((user + system + nice) / total) * 100, 0), 100)
        }
    }

    private func sampleLoadAverage() -> (Double, Double, Double) {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) == 3 else {
            return (previous.loadAverage1, previous.loadAverage5, previous.loadAverage15)
        }
        return (loads[0], loads[1], loads[2])
    }

    // MARK: - GPU

    /// Average "Device Utilization %" across IOAccelerator devices.
    private func sampleGPUPercent() -> Double {
        let matching = IOServiceMatching(kIOAcceleratorClassName)
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return previous.gpuPercent
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

    /// Model name + VRAM from the PCI/AGX device backing the accelerator.
    /// Unified-memory Macs report no VRAM key; callers treat 0 as "shared".
    private func readGPUIdentity() -> (name: String, vramBytes: UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(kIOAcceleratorClassName),
            &iterator
        ) == KERN_SUCCESS else {
            return ("", 0)
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            // The accelerator itself carries the stats; its parent carries the
            // human-readable model and the VRAM size.
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(parent) }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(parent, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = properties?.takeRetainedValue() as? [String: Any] else { continue }

            var name = ""
            if let model = dict["model"] as? Data {
                name = String(data: model, encoding: .utf8)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""
            } else if let model = dict["model"] as? String {
                name = model
            }

            var vram: UInt64 = 0
            for key in ["VRAM,totalMB", "VRAM,totalsize"] {
                guard let raw = dict[key] else { continue }
                if let number = raw as? NSNumber {
                    vram = key.hasSuffix("MB")
                        ? number.uint64Value * 1_048_576
                        : number.uint64Value
                }
                break
            }

            if !name.isEmpty || vram > 0 {
                return (name, vram)
            }
        }
        return ("", 0)
    }

    // MARK: - Memory

    /// HOST_VM_INFO64. "Used" matches Activity Monitor: active + inactive +
    /// speculative + wired + compressed, less the reclaimable file cache.
    private func sampleMemory() -> (
        used: UInt64, total: UInt64, wired: UInt64,
        compressed: UInt64, active: UInt64, cached: UInt64
    ) {
        var vmStatistics = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStatistics) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else {
            return (
                previous.ramUsedBytes, previous.ramTotalBytes, previous.ramWiredBytes,
                previous.ramCompressedBytes, previous.ramActiveBytes, previous.ramCachedBytes
            )
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let free = UInt64(vmStatistics.free_count) * pageSize
        let speculative = UInt64(vmStatistics.speculative_count) * pageSize
        let active = UInt64(vmStatistics.active_count) * pageSize
        let inactive = UInt64(vmStatistics.inactive_count) * pageSize
        let wired = UInt64(vmStatistics.wire_count) * pageSize
        let compressed = UInt64(vmStatistics.compressor_page_count) * pageSize
        let purgeable = UInt64(vmStatistics.purgeable_count) * pageSize
        let external = UInt64(vmStatistics.external_page_count) * pageSize

        let total = totalPhysicalMemory > 0
            ? totalPhysicalMemory
            : free + speculative + active + inactive + wired + compressed
        guard total > 0 else { return (0, 0, 0, 0, 0, 0) }

        let usedWithoutCache = active + inactive + speculative + wired + compressed
        let cache = purgeable + external
        let used = usedWithoutCache > cache ? usedWithoutCache - cache : 0

        return (min(used, total), total, wired, compressed, active, cache)
    }

    private func sampleSwap() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else {
            return (previous.swapUsedBytes, previous.swapTotalBytes)
        }
        return (usage.xsu_used, usage.xsu_total)
    }

    // MARK: - Storage

    /// `availableForImportantUsage` mirrors what Finder reports as free space
    /// (purgeable excluded).
    private func sampleDiskCapacity() -> (used: UInt64, total: UInt64, name: String) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeNameKey,
        ]), let total = values.volumeTotalCapacity else {
            return (previous.diskUsedBytes, previous.diskTotalBytes, previous.volumeName)
        }
        let totalBytes = UInt64(max(total, 0))
        let available = UInt64(max(values.volumeAvailableCapacityForImportantUsage ?? 0, 0))
        let used = totalBytes > available ? totalBytes - available : 0
        return (used, totalBytes, values.volumeName ?? "Macintosh HD")
    }

    /// Cumulative bytes read/written across every block-storage driver. Summed
    /// rather than filtered to a single device so external volumes count too.
    private func sampleDiskCounters() -> (readBytes: UInt64, writeBytes: UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        ) == KERN_SUCCESS else {
            return previousDisk ?? (0, 0)
        }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var written: UInt64 = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = properties?.takeRetainedValue() as? [String: Any],
               let statistics = dict["Statistics"] as? [String: Any] {
                read += (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                written += (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return (read, written)
    }

    // MARK: - Network

    /// Cumulative in/out bytes across physical (en*/Wi-Fi) interfaces, plus the
    /// busiest interface's name and IPv4 address for the detail view.
    private func sampleNetworkCounters() -> (
        inBytes: UInt64, outBytes: UInt64, primaryName: String, primaryIPv4: String
    ) {
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var perInterface: [String: UInt64] = [:]
        var addresses: [String: String] = [:]

        var ifaddrsPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrsPtr) == 0 else {
            return (totalIn, totalOut, previous.primaryInterfaceName, previous.primaryIPv4Address)
        }
        defer { freeifaddrs(ifaddrsPtr) }

        var ptr = ifaddrsPtr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee, let addr = interface.ifa_addr else { continue }
            let name = String(cString: interface.ifa_name)
            guard Self.isPhysicalInterface(name) else { continue }

            switch Int32(addr.pointee.sa_family) {
            case AF_LINK:
                guard let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
                let inBytes = UInt64(data.pointee.ifi_ibytes)
                let outBytes = UInt64(data.pointee.ifi_obytes)
                totalIn += inBytes
                totalOut += outBytes
                perInterface[name, default: 0] += inBytes + outBytes
            case AF_INET:
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let status = getnameinfo(
                    addr,
                    socklen_t(addr.pointee.sa_len),
                    &host, socklen_t(host.count),
                    nil, 0,
                    NI_NUMERICHOST
                )
                if status == 0 {
                    addresses[name] = String(cString: host)
                }
            default:
                continue
            }
        }

        // "Primary" = the interface that has moved the most traffic since boot.
        // Cheaper and steadier than asking SystemConfiguration for the default
        // route, and it is only used as a label.
        let primaryName = perInterface.max { $0.value < $1.value }?.key ?? ""
        return (totalIn, totalOut, primaryName, addresses[primaryName] ?? "")
    }

    private static func isPhysicalInterface(_ name: String) -> Bool {
        let excluded = ["lo", "gif", "stf", "bridge", "utun", "awdl", "llw", "ap"]
        guard !excluded.contains(where: { name.hasPrefix($0) }) else { return false }
        return name.hasPrefix("en") || name.contains("Wi-Fi")
    }

    // MARK: - sysctl helpers

    private func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}
