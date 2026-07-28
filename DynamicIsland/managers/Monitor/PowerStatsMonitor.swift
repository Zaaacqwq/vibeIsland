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
import IOKit
import IOKit.ps

/// Battery and power-adapter detail for the Monitor tab's Power card.
///
/// Two sources, deliberately: `IOPowerSources` supplies the headline figures
/// (percentage, charging state, time remaining) so they match the menu bar
/// exactly, while the `AppleSmartBattery` IORegistry node supplies the deep
/// stats (cycle count, health, temperature, adapter wattage) that IOPS does not
/// expose. Every deep stat is optional — key names vary across Intel and Apple
/// silicon, and desktops have no battery node at all.
///
/// This does **not** subscribe to `BatteryActivityManager`: that type's
/// `addObserver` hands back an array index while `removeObserver(byId:)` removes
/// by that index, so unsubscribing would shift every later observer's id out
/// from under it. Polling at the shared 2-second tick is accurate enough for a
/// stats panel and keeps that manager's observer list untouched.
@MainActor
final class PowerStatsMonitor: ObservableObject {
    static let shared = PowerStatsMonitor()

    struct Snapshot: Equatable, Sendable {
        var hasBattery = false
        var isPluggedIn = false
        var isCharging = false
        var isInLowPowerMode = false
        /// 0...1.
        var chargeFraction: Double = 0
        var minutesToFull: Int?
        var minutesToEmpty: Int?

        var cycleCount: Int?
        /// Current full-charge capacity as a share of the design capacity, 0...1.
        var healthFraction: Double?
        var designCapacitymAh: Int?
        var currentMaxCapacitymAh: Int?
        var temperatureCelsius: Double?
        /// Signed: positive while charging, negative while discharging.
        var amperagemA: Int?
        var voltageV: Double?
        var adapterWatts: Int?
        var adapterName: String?

        static let zero = Snapshot()

        /// Instantaneous power draw derived from the battery's own current and
        /// voltage. Sign follows `amperagemA`, so a discharging Mac reads
        /// negative. Nil when either factor is unavailable.
        var powerWatts: Double? {
            guard let amperagemA, let voltageV else { return nil }
            return (Double(amperagemA) / 1000) * voltageV
        }

        /// Apple calls a battery "service recommended" below ~80% health.
        var isHealthDegraded: Bool {
            guard let healthFraction else { return false }
            return healthFraction < 0.8
        }
    }

    @Published private(set) var snapshot: Snapshot = .zero

    private let pollInterval: TimeInterval = 2
    private var monitorTask: Task<Void, Never>?
    private var retainers: Set<String> = []

    private init() {}

    // MARK: - Lifecycle

    func startMonitoring(token: String) {
        let wasEmpty = retainers.isEmpty
        retainers.insert(token)
        guard wasEmpty, monitorTask == nil else { return }

        monitorTask = Task { [weak self] in
            guard let self else { return }
            await self.tick()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(self.pollInterval))
                } catch {
                    break
                }
                await self.tick()
            }
        }
    }

    func stopMonitoring(token: String) {
        retainers.remove(token)
        guard retainers.isEmpty else { return }
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func tick() async {
        let next = await Task.detached(priority: .utility) { Self.read() }.value
        guard !Task.isCancelled, next != snapshot else { return }
        snapshot = next
    }

    // MARK: - Reading (off-main, stateless)

    private nonisolated static func read() -> Snapshot {
        var snapshot = Snapshot()
        snapshot.isInLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        applyPowerSources(to: &snapshot)
        applySmartBattery(to: &snapshot)
        return snapshot
    }

    /// Headline figures, straight from the same API the menu bar uses.
    private nonisolated static func applyPowerSources(to snapshot: inout Snapshot) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(blob, source)?
                  .takeUnretainedValue() as? [String: Any] else {
            return
        }

        snapshot.hasBattery = (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            || description[kIOPSCurrentCapacityKey] != nil

        if let current = description[kIOPSCurrentCapacityKey] as? Double,
           let max = description[kIOPSMaxCapacityKey] as? Double, max > 0 {
            snapshot.chargeFraction = min(Swift.max(current / max, 0), 1)
        }
        if let state = description[kIOPSPowerSourceStateKey] as? String {
            snapshot.isPluggedIn = state == kIOPSACPowerValue
        }
        snapshot.isCharging = description[kIOPSIsChargingKey] as? Bool ?? false

        // IOPS reports -1 while it is still estimating; treat that as unknown
        // rather than rendering a bogus countdown.
        if let toFull = description[kIOPSTimeToFullChargeKey] as? Int, toFull >= 0 {
            snapshot.minutesToFull = toFull
        }
        if let toEmpty = description[kIOPSTimeToEmptyKey] as? Int, toEmpty >= 0 {
            snapshot.minutesToEmpty = toEmpty
        }
    }

    /// Deep stats from the IORegistry. Absent keys simply stay nil.
    private nonisolated static func applySmartBattery(to snapshot: inout Snapshot) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any] else {
            return
        }

        if let installed = dict["BatteryInstalled"] as? Bool {
            snapshot.hasBattery = installed
        }
        snapshot.cycleCount = (dict["CycleCount"] as? NSNumber)?.intValue

        let design = (dict["DesignCapacity"] as? NSNumber)?.intValue
        // Key name for "capacity at full charge" moved across generations:
        // Intel exposes AppleRawMaxCapacity, Apple silicon NominalChargeCapacity.
        // Plain MaxCapacity is a percentage on Apple silicon, so it is only
        // trusted when it is clearly an mAh-scale number.
        let rawMax = (dict["AppleRawMaxCapacity"] as? NSNumber)?.intValue
            ?? (dict["NominalChargeCapacity"] as? NSNumber)?.intValue
            ?? (dict["MaxCapacity"] as? NSNumber).map(\.intValue).flatMap { $0 > 1000 ? $0 : nil }

        snapshot.designCapacitymAh = design
        snapshot.currentMaxCapacitymAh = rawMax
        if let design, let rawMax, design > 0 {
            snapshot.healthFraction = min(Double(rawMax) / Double(design), 1)
        }

        // AppleSmartBattery reports temperature in hundredths of a degree C.
        if let raw = (dict["Temperature"] as? NSNumber)?.doubleValue, raw > 0 {
            snapshot.temperatureCelsius = raw / 100
        }
        snapshot.amperagemA = (dict["Amperage"] as? NSNumber)?.intValue
        if let millivolts = (dict["Voltage"] as? NSNumber)?.doubleValue, millivolts > 0 {
            snapshot.voltageV = millivolts / 1000
        }

        if let adapter = dict["AdapterDetails"] as? [String: Any] {
            snapshot.adapterWatts = (adapter["Watts"] as? NSNumber)?.intValue
            let name = (adapter["Name"] as? String)
                ?? (adapter["Description"] as? String)
                ?? (adapter["Manufacturer"] as? String)
            snapshot.adapterName = name?.isEmpty == true ? nil : name
        }
    }
}
