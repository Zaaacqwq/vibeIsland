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

/// The Monitor tab: a grid of live system-stat tiles that drill into per-category
/// detail.
///
/// Two states, one view. The overview is a 4-column grid of `MonitorTile`s;
/// tapping one swaps in that category's detail view with the same height
/// budget. The drill-in target is view-local `@State`, not a persisted default —
/// closing the notch returns to the overview, because a detail view is a
/// deliberate act rather than a place you want to be left.
struct NotchMonitorView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var stats = SystemStatsMonitor.shared
    @ObservedObject private var power = PowerStatsMonitor.shared
    @ObservedObject private var displays = DisplayStatsMonitor.shared
    @ObservedObject private var processes = ProcessStatsMonitor.shared
    @Default(.monitorCategories) private var enabledCategories

    @State private var focused: MonitorCategory?
    /// Held while the pointer is over the Displays detail, whose card row
    /// scrolls horizontally past three screens. Without this, dragging through
    /// that list would be read as the notch's swipe-to-switch-tab gesture.
    @State private var scrollSuppressionToken = UUID()

    /// This tab fills its region instead of sizing to its content, so it uses
    /// the *filled* budget — the plain `contentHeight` ceiling is not reachable
    /// without drawing taller than every other tab.
    private var contentHeight: CGFloat {
        NotchDesign.TabInset.filledContentHeight(headerHeight: max(24, vm.effectiveClosedNotchHeight))
    }

    /// Filtered through `allCases` rather than used as stored, so the grid order
    /// stays canonical no matter what order Settings wrote the array in. An
    /// empty selection shows everything — an empty Monitor tab is a dead end.
    private var categories: [MonitorCategory] {
        guard !enabledCategories.isEmpty else { return MonitorCategory.allCases }
        let enabled = Set(enabledCategories)
        return MonitorCategory.allCases.filter(enabled.contains)
    }

    var body: some View {
        Group {
            if let focused {
                detail(for: focused)
            } else {
                overview
            }
        }
        // Pinned to an exact height, not `maxHeight: .infinity`.
        //
        // The container hands tabs a `maxHeight` — a cap, not a floor — and the
        // open notch sizes itself to whatever the tab reports. Under that
        // unspecified height proposal `maxHeight: .infinity` resolves to the
        // view's *ideal* height, which differs between the tile grid and each
        // detail view, so every drill-in resized the window. Taking the budget
        // exactly keeps all eight states the same height.
        .frame(
            maxWidth: .infinity,
            minHeight: contentHeight,
            maxHeight: contentHeight,
            alignment: .top
        )
        .onAppear {
            stats.startMonitoring(token: SystemStatsMonitor.Consumer.monitorTab)
            power.startMonitoring(token: SystemStatsMonitor.Consumer.monitorTab)
            displays.startMonitoring(token: SystemStatsMonitor.Consumer.monitorTab)
            // Only the network list is warmed with the tab: its rate needs two
            // `nettop` runs ~11s apart, and it is nearly free (~0.03s of CPU per
            // run, the rest of its 5s is spent asleep). The CPU and memory
            // lists read absolute figures, so they are correct from their first
            // sample and start with their own card instead — that keeps `top`,
            // which costs ~0.45s of CPU per run, off the overview entirely.
            processes.start(.network)
        }
        .onDisappear {
            stats.stopMonitoring(token: SystemStatsMonitor.Consumer.monitorTab)
            power.stopMonitoring(token: SystemStatsMonitor.Consumer.monitorTab)
            displays.stopMonitoring(token: SystemStatsMonitor.Consumer.monitorTab)
            vm.setScrollGestureSuppression(false, token: scrollSuppressionToken)
            processes.stopAll()
        }
        .onChange(of: vm.notchState) { _, state in
            if state == .closed { focused = nil }
        }
        .onChange(of: focused) { previous, category in
            // Leaving the Displays detail releases the hold even if the pointer
            // never left the region (e.g. the back button was hit via keyboard).
            if category != .display {
                vm.setScrollGestureSuppression(false, token: scrollSuppressionToken)
            }
            if let metric = Self.cardScopedMetric(for: previous) {
                processes.stop(metric)
            }
            if let metric = Self.cardScopedMetric(for: category) {
                processes.start(metric)
            }
        }
    }

    // MARK: - Overview

    /// Explicit rows rather than a `LazyVGrid`.
    ///
    /// A grid sizes its rows to their content, and the tiles declare
    /// `maxHeight: .infinity` so they fill whatever cell they get — together
    /// that asks for unbounded height, which in this window means the notch
    /// grows instead of the tiles shrinking. Two `HStack`s that each take half
    /// the height budget keep the split fixed and the notch at its own size.
    private var overview: some View {
        let rows = Self.rows(for: categories)
        return VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { category in
                        tile(for: category)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    // Pad the last row so four tiles and seven tiles produce the
                    // same column width instead of the final row stretching.
                    if row.count < Self.columns {
                        ForEach(0..<(Self.columns - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private static let columns = 4

    /// Process lists that run only while their own card is open. Network is
    /// absent on purpose — it is warmed with the whole tab.
    private static func cardScopedMetric(for category: MonitorCategory?) -> ProcessStatsMonitor.Metric? {
        switch category {
        case .cpu: return .cpu
        case .memory: return .memory
        default: return nil
        }
    }


    /// Chunks into rows of four. One to four categories stay on a single row so
    /// a trimmed-down grid fills the height instead of leaving a gap below.
    private static func rows(for categories: [MonitorCategory]) -> [[MonitorCategory]] {
        stride(from: 0, to: categories.count, by: columns).map { start in
            Array(categories[start..<min(start + columns, categories.count)])
        }
    }

    @ViewBuilder
    private func tile(for category: MonitorCategory) -> some View {
        let snapshot = stats.snapshot
        let history = stats.history

        switch category {
        case .cpu:
            MonitorTile(
                category: category,
                value: MonitorFormat.percent(snapshot.cpuActivePercent),
                trailing: .sparkline(normalized: history.cpu.normalized(ceiling: 100)),
                valueTint: MonitorTint.forLoad(percent: snapshot.cpuActivePercent),
                action: { focus(category) }
            )

        case .gpu:
            MonitorTile(
                category: category,
                value: MonitorFormat.percent(snapshot.gpuPercent),
                trailing: .sparkline(normalized: history.gpu.normalized(ceiling: 100)),
                valueTint: MonitorTint.forLoad(percent: snapshot.gpuPercent),
                action: { focus(category) }
            )

        case .memory:
            MonitorTile(
                category: category,
                value: MonitorFormat.percent(fraction: snapshot.ramUsedFraction),
                trailing: .sparkline(normalized: history.memory.normalized(ceiling: 100)),
                valueTint: MonitorTint.forCapacity(fraction: snapshot.ramUsedFraction),
                action: { focus(category) }
            )

        case .storage:
            let free = MonitorFormat.sizeParts(snapshot.diskFreeBytes)
            MonitorTile(
                category: category,
                value: free.value,
                unit: "\(free.unit) free",
                trailing: .bar(fraction: snapshot.diskUsedFraction),
                valueTint: MonitorTint.forCapacity(fraction: snapshot.diskUsedFraction),
                action: { focus(category) }
            )

        case .network:
            // Both series share one ceiling so the two lines stay comparable —
            // scaling each to its own peak would make a trickle look like a
            // flood next to a download.
            let ceiling = max(
                history.netDown.rateCeiling(minimum: 65_536),
                history.netUp.rateCeiling(minimum: 65_536)
            )
            let down = MonitorFormat.rateParts(snapshot.netDownBytesPerSec)
            MonitorTile(
                category: category,
                value: down.value,
                unit: down.unit,
                trailing: .dualSparkline(
                    primary: history.netDown.normalized(ceiling: ceiling),
                    secondary: history.netUp.normalized(ceiling: ceiling)
                ),
                action: { focus(category) }
            )

        case .power:
            let snapshotPower = power.snapshot
            // Deliberately one tile whose *values* vary, not an `if` on
            // `hasBattery`. A ViewBuilder conditional gives each branch its own
            // identity, so flipping between them is a remove+insert rather than
            // an update — and an inserted subtree does not join the parent's
            // in-flight transition. On a cold start the first power sample
            // lands a few milliseconds after the tab appears, mid-slide, which
            // made this one tile pop into place while its neighbours were still
            // animating in.
            MonitorTile(
                category: category,
                // Desktop Macs have no battery node, so lead with the thing
                // that is true (it is on wall power) instead of a 0% meter.
                value: snapshotPower.hasBattery
                    ? MonitorFormat.percent(fraction: snapshotPower.chargeFraction)
                    : "AC",
                trailing: .caption(powerCaption(snapshotPower)),
                valueTint: snapshotPower.hasBattery
                    ? MonitorTint.forCharge(
                        fraction: snapshotPower.chargeFraction,
                        isCharging: snapshotPower.isCharging
                    )
                    : nil,
                action: { focus(category) }
            )

        case .display:
            let list = displays.displays
            MonitorTile(
                category: category,
                value: "\(list.count)",
                unit: list.count == 1 ? String(localized: "display") : String(localized: "displays"),
                trailing: .caption(displayCaption(list)),
                action: { focus(category) }
            )
        }
    }

    private func powerCaption(_ snapshot: PowerStatsMonitor.Snapshot) -> String {
        guard snapshot.hasBattery else {
            return snapshot.adapterName ?? String(localized: "Wall power")
        }
        if snapshot.isCharging, let minutes = snapshot.minutesToFull {
            return String(localized: "\(MonitorFormat.duration(minutes: minutes)) to full")
        }
        if snapshot.isPluggedIn {
            return String(localized: "Plugged in")
        }
        if let minutes = snapshot.minutesToEmpty {
            return String(localized: "\(MonitorFormat.duration(minutes: minutes)) left")
        }
        return String(localized: "On battery")
    }

    private func displayCaption(_ list: [DisplayStatsMonitor.DisplayInfo]) -> String {
        guard let main = list.first(where: \.isMain) ?? list.first else {
            return String(localized: "None detected")
        }
        return "\(main.resolutionText) · \(main.refreshText)"
    }

    // MARK: - Detail

    @ViewBuilder
    private func detail(for category: MonitorCategory) -> some View {
        let back = { focus(nil) }
        switch category {
        case .cpu:
            CPUDetailView(
                snapshot: stats.snapshot,
                history: stats.history,
                processes: processes.topCPU,
                onBack: back
            )
        case .gpu:
            GPUDetailView(snapshot: stats.snapshot, history: stats.history, onBack: back)
        case .memory:
            MemoryDetailView(
                snapshot: stats.snapshot,
                history: stats.history,
                processes: processes.topMemory,
                onBack: back
            )
        case .storage:
            StorageDetailView(snapshot: stats.snapshot, history: stats.history, onBack: back)
        case .network:
            NetworkDetailView(
                snapshot: stats.snapshot,
                history: stats.history,
                processes: processes.topNetwork,
                isLoadingProcesses: processes.isLoadingNetwork,
                onBack: back
            )
        case .power:
            PowerDetailView(snapshot: power.snapshot, onBack: back)
        case .display:
            DisplayDetailView(displays: displays.displays, onBack: back)
                .onHover { hovering in
                    vm.setScrollGestureSuppression(hovering, token: scrollSuppressionToken)
                }
        }
    }

    /// Overview and detail cross-fade in place. A slide would read as a tab
    /// change, which is a different navigation entirely and is already spoken
    /// for by the container's horizontal transition.
    private func focus(_ category: MonitorCategory?) {
        withAnimation(.smooth(duration: 0.22)) {
            focused = category
        }
    }
}
