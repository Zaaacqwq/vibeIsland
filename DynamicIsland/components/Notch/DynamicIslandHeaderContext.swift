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
import Defaults
import OpenIslandCore
import SwiftUI

/// Compact, tab-aware widget that fills the open-notch header's right wing (the
/// gap between the physical notch and the timer/settings controls). Each tab
/// gets contextual info rendered as one or more stacked "stat cells" — a small
/// mono eyebrow on top, the value below — so Home stats and Agents usage share
/// a single visual language.
struct NotchHeaderContextWidget: View {
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var stats = SystemStatsMonitor.shared
    @ObservedObject private var agentMonitor = AgentMonitorManager.shared
    @ObservedObject private var weather = WeatherManager.shared
    @ObservedObject private var calendar = CalendarManager.shared

    /// Resolved once — the Mac's user-facing name (e.g. "Zac's MacBook Pro").
    private static let deviceName: String = Host.current().localizedName ?? "This Mac"

    var body: some View {
        content
            .frame(maxHeight: .infinity)
            // Never shove the trailing timer/settings controls off-screen: the
            // widget yields width first and truncates its own text.
            .layoutPriority(0)
            .onAppear { updateStatsMonitoring() }
            .onDisappear { stats.stopMonitoring(token: SystemStatsMonitor.Consumer.headerWidget) }
            .onChange(of: coordinator.currentView) { _, _ in updateStatsMonitoring() }
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.currentView {
        case .home:
            homeStats
        case .shelf:
            StatCell(label: "Device", value: Self.deviceName, alignment: .leading, maxValueWidth: 160)
        case .agents:
            agentUsage
        case .calendar:
            calendarEvent
        case .weather:
            weatherLocation
        case .monitor:
            monitorContext
        // The utility tools state their own status inside the tab (saved count,
        // item count, paused), so the header stays quiet for them.
        case .timer, .notifications, .colorPicker, .clipboard:
            EmptyView()
        }
    }

    // MARK: - Monitor

    /// The Monitor tab already renders every metric in its own grid, so the
    /// header states the one thing the grid does not: how long the Mac has been
    /// up. The device name lives in the Shelf header instead — repeating it here
    /// just crowded the row.
    private var monitorContext: some View {
        StatCell(label: "Uptime", value: Self.uptimeText())
    }

    /// Coarse on purpose — a header that ticks every second would repaint the
    /// notch once a second for a number nobody reads that precisely.
    private static func uptimeText() -> String {
        let seconds = Int(ProcessInfo.processInfo.systemUptime)
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.calendar = AppLanguageController.calendar
        return formatter.string(from: TimeInterval(seconds)) ?? "—"
    }

    // MARK: - Home (configurable: CPU / GPU / RAM / Disk / Network)

    @Default(.homeHeaderStats) private var homeHeaderStats

    @ViewBuilder
    private var homeStats: some View {
        // Clamped here too, not just in Settings: a preference saved before the
        // cap existed would otherwise overflow the row.
        let kinds = HeaderStatKind.normalizedHeaderStats(homeHeaderStats)
        if !kinds.isEmpty {
            HStack(spacing: 14) {
                ForEach(kinds) { kind in
                    statCell(for: kind)
                }
            }
        }
    }

    @ViewBuilder
    private func statCell(for kind: HeaderStatKind) -> some View {
        let snapshot = stats.snapshot
        switch kind {
        case .cpu:
            let pct = snapshot.cpuActivePercent.rounded()
            StatCell(label: kind.eyebrow, value: "\(Int(pct))%", tint: tint(for: pct))
        case .gpu:
            let pct = snapshot.gpuPercent.rounded()
            StatCell(label: kind.eyebrow, value: "\(Int(pct))%", tint: tint(for: pct))
        case .ram:
            let pct = (snapshot.ramUsedFraction * 100).rounded()
            StatCell(label: kind.eyebrow, value: "\(Int(pct))%", tint: tint(for: pct))
        case .disk:
            let pct = (snapshot.diskUsedFraction * 100).rounded()
            StatCell(label: kind.eyebrow, value: "\(Int(pct))%", tint: tint(for: pct))
        case .network:
            networkCell(snapshot)
        }
    }

    /// Two fixed rows — upload (red) on top, download (blue) below — so the cell
    /// keeps a stable width instead of the single line jittering as rates change.
    private func networkCell(_ snapshot: SystemStatsMonitor.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            netLine(color: NotchDesign.Colors.danger, bytesPerSecond: snapshot.netUpBytesPerSec)
            netLine(color: NotchDesign.Colors.info, bytesPerSecond: snapshot.netDownBytesPerSec)
        }
    }

    private func netLine(color: Color, bytesPerSecond: Double) -> some View {
        let parts = HeaderStatFormatting.rateParts(bytesPerSecond)
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            // Number sits in a fixed-width, right-aligned slot so the unit that
            // follows never shifts as the digits change.
            Text(parts.value)
                .font(NotchDesign.Typography.mono(10, weight: .medium))
                .foregroundStyle(NotchDesign.Colors.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 28, alignment: .trailing)
            Text(parts.unit)
                .font(NotchDesign.Typography.mono(10, weight: .medium))
                .foregroundStyle(NotchDesign.Colors.textTertiary)
                .lineLimit(1)
        }
    }

    // MARK: - Agents (Claude / Codex rate-limit usage)

    @Default(.agentHeaderProviders) private var agentHeaderProviders
    @Default(.agentAntigravityCompactQuotaWindows) private var compactAntigravityQuotaWindows
    @Default(.agentOpenCodeCompactQuotaWindows) private var compactOpenCodeQuotaWindows

    /// Usage for the providers picked in Settings › Notch Header, at most two.
    /// A selected provider with no data yet is skipped rather than rendered as
    /// a bare icon, so an agent you have not run today costs no header width.
    @ViewBuilder
    private var agentUsage: some View {
        if Defaults[.enableAgentMonitoring] {
            let groups = AgentUsageProviderCatalog
                .normalizedHeaderProviders(agentHeaderProviders)
                .compactMap(headerGroup(for:))
            if !groups.isEmpty {
                HStack(spacing: 12) {
                    ForEach(groups) { group in
                        providerUsage(id: group.id, cells: group.cells)
                    }
                }
            }
        }
    }

    private struct ProviderUsageGroup: Identifiable {
        let id: AgentUsageProviderID
        let cells: [UsageCell]
    }

    /// Claude and Codex carry dedicated rate-limit snapshots; everything else
    /// reads the shared provider-quota map through the same presentation rules
    /// the Agents panel uses, so a window relabelled there (Antigravity/OpenCode
    /// compact mode) reads identically here.
    private func headerGroup(for id: AgentUsageProviderID) -> ProviderUsageGroup? {
        let cells: [UsageCell]
        switch id {
        case .claude:
            guard let usage = agentMonitor.usage, !usage.isEmpty else { return nil }
            cells = claudeCells(usage)
        case .codex:
            guard let usage = agentMonitor.codexUsage, !usage.isEmpty else { return nil }
            cells = codexCells(usage)
        default:
            guard let quota = AgentQuotaPresentation.snapshot(
                providerID: id,
                quota: agentMonitor.providerQuotas[id],
                compactAntigravity: compactAntigravityQuotaWindows,
                compactOpenCode: compactOpenCodeQuotaWindows
            ) else { return nil }
            cells = quota.windows.map {
                UsageCell(label: $0.label, percent: Int($0.usedPercentage.rounded()))
            }
        }
        guard !cells.isEmpty else { return nil }
        return ProviderUsageGroup(id: id, cells: cells)
    }

    private func providerUsage(id: AgentUsageProviderID, cells: [UsageCell]) -> some View {
        let icon = AgentUsageProviderCatalog.icon(for: id)
        return HStack(spacing: 8) {
            Group {
                if let asset = icon.asset {
                    Image(asset).renderingMode(.template).resizable().scaledToFit()
                } else {
                    Image(systemName: icon.system).resizable().scaledToFit()
                }
            }
            .frame(width: 12, height: 12)
            .foregroundStyle(NotchDesign.Colors.textPrimary)
            ForEach(cells) { cell in
                // Debug override forces MAX; at the cap show "MAX" (three chars)
                // rather than the four-char "100%" which gets truncated here.
                let percent = Defaults[.debugForceUsageMax] ? 100 : cell.percent
                StatCell(label: cell.label, value: percent >= 100 ? "MAX" : "\(percent)%", tint: tint(for: Double(percent)))
            }
        }
    }

    private struct UsageCell: Identifiable {
        let id = UUID()
        let label: String
        let percent: Int
    }

    private func claudeCells(_ usage: ClaudeUsageSnapshot) -> [UsageCell] {
        var cells: [UsageCell] = []
        if let five = usage.fiveHour { cells.append(UsageCell(label: "5h", percent: five.roundedUsedPercentage)) }
        if let week = usage.sevenDay { cells.append(UsageCell(label: "7d", percent: week.roundedUsedPercentage)) }
        return cells
    }

    private func codexCells(_ usage: CodexUsageSnapshot) -> [UsageCell] {
        usage.windows.map { UsageCell(label: $0.label, percent: $0.roundedUsedPercentage) }
    }

    // MARK: - Calendar (next event today)

    @ViewBuilder
    private var calendarEvent: some View {
        if let event = calendar.nextEventToday {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(nsColor: event.calendar.color).ensureMinimumBrightness(factor: 0.7))
                    .frame(width: 3, height: 22)
                StatCell(
                    label: event.start.formatted(date: .omitted, time: .shortened),
                    value: event.title.isEmpty ? String(localized: "Event") : event.title,
                    alignment: .leading,
                    maxValueWidth: 150
                )
            }
        }
    }

    // MARK: - Weather (current location)

    @ViewBuilder
    private var weatherLocation: some View {
        if Defaults[.enableWeather], let place = weather.snapshot?.locationName, !place.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "location.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(NotchDesign.Colors.textTertiary)
                StatCell(label: "Location", value: place, alignment: .leading, maxValueWidth: 160)
            }
        }
    }

    // MARK: - Helpers

    private func tint(for percent: Double) -> Color {
        percent >= 80 ? NotchDesign.Colors.warning : NotchDesign.Colors.textPrimary
    }

    private func updateStatsMonitoring() {
        // Retained under the header's own token: the Monitor tab holds a second
        // retain, so leaving Home must not stop sampling out from under it.
        if coordinator.currentView == .home {
            stats.startMonitoring(token: SystemStatsMonitor.Consumer.headerWidget)
        } else {
            stats.stopMonitoring(token: SystemStatsMonitor.Consumer.headerWidget)
        }
    }
}

/// A stacked label-over-value cell: small mono eyebrow on top, the value below.
/// The shared building block for every header context widget.
private struct StatCell: View {
    let label: String
    let value: String
    var tint: Color = NotchDesign.Colors.textPrimary
    var alignment: HorizontalAlignment = .leading
    /// When set, the value line truncates instead of stretching the header.
    var maxValueWidth: CGFloat?

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(verbatim: notchLocalized(label).uppercased())
                .font(NotchDesign.Typography.mono(8, weight: .medium))
                .foregroundStyle(NotchDesign.Colors.textTertiary)
                .lineLimit(1)
            Text(value)
                .font(NotchDesign.Typography.mono(13, weight: .medium))
                .foregroundStyle(tint)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: maxValueWidth, alignment: textAlignment)
        }
        .fixedSize(horizontal: maxValueWidth == nil, vertical: true)
    }

    private var textAlignment: Alignment {
        switch alignment {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }
}
