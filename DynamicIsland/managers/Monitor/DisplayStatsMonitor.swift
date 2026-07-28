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

import AppKit
import CoreGraphics
import Foundation

/// Connected-display inventory for the Monitor tab's Displays card.
///
/// Split into two refresh paths on purpose. Topology (which screens exist,
/// their resolution, scale, refresh rate) only changes when a display is
/// plugged, unplugged or reconfigured, so it is driven by
/// `didChangeScreenParametersNotification` rather than the poll loop. Only
/// brightness — the one genuinely live value — rides the shared 2-second tick.
@MainActor
final class DisplayStatsMonitor: ObservableObject {
    static let shared = DisplayStatsMonitor()

    struct DisplayInfo: Identifiable, Equatable, Sendable {
        /// `CGDirectDisplayID`.
        let id: UInt32
        var name: String
        var pixelWidth: Int
        var pixelHeight: Int
        var pointWidth: Int
        var pointHeight: Int
        var refreshHz: Double
        var backingScale: Double
        var isMain: Bool
        var isBuiltIn: Bool
        var colorSpaceName: String?
        /// 0...1. Nil when the private brightness API is unavailable or the
        /// panel doesn't expose a level (most external monitors).
        var brightness: Double?

        var isHiDPI: Bool { backingScale > 1.5 }

        var resolutionText: String { "\(pixelWidth) × \(pixelHeight)" }

        /// Logical resolution, only meaningful on HiDPI panels where it differs
        /// from the native pixel grid.
        var scaledResolutionText: String { "\(pointWidth) × \(pointHeight)" }

        var refreshText: String {
            guard refreshHz > 0 else { return "—" }
            return "\(Int(refreshHz.rounded())) Hz"
        }
    }

    @Published private(set) var displays: [DisplayInfo] = []

    private let pollInterval: TimeInterval = 2
    private var monitorTask: Task<Void, Never>?
    private var retainers: Set<String> = []
    private var screenObserver: NSObjectProtocol?

    private init() {}

    // MARK: - Lifecycle

    func startMonitoring(token: String) {
        let wasEmpty = retainers.isEmpty
        retainers.insert(token)
        guard wasEmpty, monitorTask == nil else { return }

        refreshTopology()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshTopology()
            }
        }

        monitorTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshBrightness()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(self.pollInterval))
                } catch {
                    break
                }
                await self.refreshBrightness()
            }
        }
    }

    func stopMonitoring(token: String) {
        retainers.remove(token)
        guard retainers.isEmpty else { return }
        monitorTask?.cancel()
        monitorTask = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    // MARK: - Topology

    /// Rebuilds the display list from `NSScreen` (names, scale) joined with
    /// `CGDisplayMode` (native pixel grid, refresh rate). Runs on main because
    /// `NSScreen` requires it; only fires on screen-parameter changes.
    private func refreshTopology() {
        let mainID = CGMainDisplayID()
        let previousBrightness = Dictionary(
            displays.map { ($0.id, $0.brightness) },
            uniquingKeysWith: { first, _ in first }
        )

        let next: [DisplayInfo] = NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else {
                return nil
            }
            let id = number.uint32Value
            let mode = CGDisplayCopyDisplayMode(id)

            // Refresh rate reads 0 for most built-in panels; NSScreen's own
            // figure is the reliable fallback there.
            var refresh = mode?.refreshRate ?? 0
            if refresh <= 0 {
                refresh = Double(screen.maximumFramesPerSecond)
            }

            let pixelWidth = mode?.pixelWidth ?? Int(screen.frame.width * screen.backingScaleFactor)
            let pixelHeight = mode?.pixelHeight ?? Int(screen.frame.height * screen.backingScaleFactor)

            return DisplayInfo(
                id: id,
                name: screen.localizedName,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                pointWidth: mode?.width ?? Int(screen.frame.width),
                pointHeight: mode?.height ?? Int(screen.frame.height),
                refreshHz: refresh,
                backingScale: Double(screen.backingScaleFactor),
                isMain: id == mainID,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                colorSpaceName: screen.colorSpace?.localizedName,
                // Carry the last known level so the row doesn't blank out for a
                // tick between a topology change and the next brightness pass.
                brightness: previousBrightness[id] ?? nil
            )
        }

        if next != displays {
            displays = next
        }
    }

    // MARK: - Brightness

    private func refreshBrightness() async {
        let ids = displays.map(\.id)
        guard !ids.isEmpty else { return }

        let levels = await Task.detached(priority: .utility) {
            Self.readBrightness(for: ids)
        }.value

        guard !Task.isCancelled else { return }
        var next = displays
        var changed = false
        for index in next.indices {
            let level = levels[next[index].id] ?? nil
            if next[index].brightness != level {
                next[index].brightness = level
                changed = true
            }
        }
        if changed {
            displays = next
        }
    }

    /// `DisplayServicesGetBrightness` is a private API reached through a
    /// dynamically loaded handle, so a missing symbol or a non-zero status just
    /// yields nil for that display instead of failing the pass.
    private nonisolated static func readBrightness(for ids: [UInt32]) -> [UInt32: Double?] {
        var result: [UInt32: Double?] = [:]
        for id in ids {
            guard let reading = DisplayServicesDynamic.shared.getBrightness(displayID: id),
                  reading.status == KERN_SUCCESS else {
                result[id] = Double?.none
                continue
            }
            result[id] = min(max(Double(reading.value), 0), 1)
        }
        return result
    }
}
