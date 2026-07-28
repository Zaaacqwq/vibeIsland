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
import Foundation

/// Publishes live system stats to the open-notch header widget and the Monitor
/// tab. All the actual reading happens off-main in `SystemStatsSampler`; this
/// type owns only the poll loop, the published snapshot, and the rolling
/// history the sparklines chart.
///
/// Sampling is on-demand and **retained by token**: the Home header widget and
/// the Monitor tab are independent consumers, so a plain start/stop pair would
/// let whichever disappears first kill sampling for the other. Each consumer
/// retains under its own token and the loop runs while at least one is held.
@MainActor
final class SystemStatsMonitor: ObservableObject {
    static let shared = SystemStatsMonitor()

    /// Kept so existing call sites (`SystemStatsMonitor.Snapshot`) read
    /// unchanged after the snapshot moved to top level for actor-crossing.
    typealias Snapshot = SystemStatsSnapshot

    @Published private(set) var snapshot: SystemStatsSnapshot = .zero
    @Published private(set) var history = MonitorHistoryBundle()

    /// Tokens used by the two in-app consumers. Any string works; these exist so
    /// the call sites don't invent colliding literals.
    enum Consumer {
        static let headerWidget = "header-widget"
        static let monitorTab = "monitor-tab"
    }

    private let pollInterval: TimeInterval = 2
    private let sampler = SystemStatsSampler()
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
            // Seed immediately so the widget shows a value on the first frame.
            // The CPU delta and the disk/net rates need a prior sample, so those
            // read as a whole-uptime average / zero until the second tick lands.
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
        Task { [sampler] in await sampler.reset() }
    }

    // MARK: - Sampling

    private func tick() async {
        let next = await sampler.sample()
        guard !Task.isCancelled else { return }
        // Publish only on change: an idle machine produces byte-identical
        // snapshots, and re-publishing one re-renders the whole notch.
        if next != snapshot {
            snapshot = next
        }
        // History always advances — the sparkline needs the flat stretch even
        // when the value itself didn't move.
        history.record(next)
    }
}
