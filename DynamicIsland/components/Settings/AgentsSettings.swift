/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Agent monitoring feature ported from Open Vibe Island (Open Island),
 * GPL v3 — Copyright (C) Octane0411 and Open Island contributors.
 * See NOTICE for details.
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
 */

import SwiftUI
import Defaults
import OpenIslandCore

/// Settings pane for the AI coding-agent monitor (Open Island integration).
/// Master switch, live-activity toggle, and Claude Code hook installation.
struct AgentsSettings: View {
    @ObservedObject var agentMonitor = AgentMonitorManager.shared
    @Default(.enableAgentMonitoring) var enableAgentMonitoring

    var body: some View {
        GeistSettingsPage(title: "Agents", subtitle: "Track AI coding-agent sessions (Claude Code) in the notch.") {
            GeistSection(
                footer: "Adds an Agents tab and a closed-notch live activity showing running Claude Code sessions, permission prompts, and one-click jump-back to the terminal."
            ) {
                GeistToggleRow(
                    title: "Enable agent monitoring",
                    description: "Track AI coding-agent sessions (Claude Code) in the notch.",
                    isOn: $enableAgentMonitoring,
                    divider: enableAgentMonitoring
                )
                if enableAgentMonitoring {
                    GeistToggleRow(title: "Play a sound when Claude finishes", isOn: geistBinding(.agentCompletionSoundEnabled))
                    GeistToggleRow(title: "Expand the notch to Agents when Claude finishes", isOn: geistBinding(.agentExpandOnComplete), divider: false)
                }
            }

            if enableAgentMonitoring {
                GeistSection(
                    title: "Claude Code",
                    footer: "Installing writes VibeIsland-namespaced hooks into ~/.claude/settings.json. Hooks fail open — if VibeIsland isn't running, Claude is unaffected."
                ) {
                    GeistLabeledRow(title: "Bridge") {
                        Label(agentMonitor.isBridgeReady ? "Connected" : "Starting…",
                              systemImage: agentMonitor.isBridgeReady ? "checkmark.circle.fill" : "clock")
                            .font(Geist.Typography.body)
                            .foregroundStyle(agentMonitor.isBridgeReady ? Geist.Colors.success : Geist.Colors.mute)
                            .labelStyle(.titleAndIcon)
                    }
                    GeistLabeledRow(title: "Claude Code hooks") { hookStatusLabel }
                    GeistRow(divider: false) {
                        HStack(spacing: Geist.Spacing.xs) {
                            switch agentMonitor.hookStatus {
                            case .installed:
                                Button("Reinstall") { agentMonitor.installHooks() }.buttonStyle(.geist)
                                Button("Remove") { agentMonitor.uninstallHooks() }.buttonStyle(.geist)
                            case .notInstalled, .unknown:
                                Button("Install hooks") { agentMonitor.installHooks() }.buttonStyle(.geistProminent)
                            }
                        }
                    }
                }

                GeistSection(
                    title: "Usage",
                    footer: "Installs a managed Claude Code status line that reports your 5-hour and 7-day rate-limit usage. Modifies the statusLine entry in ~/.claude/settings.json."
                ) {
                    GeistLabeledRow(title: "Usage status line") {
                        if agentMonitor.statusLineInstalled {
                            Label("Installed", systemImage: "checkmark.circle.fill")
                                .font(Geist.Typography.body).foregroundStyle(Geist.Colors.success).labelStyle(.titleAndIcon)
                        } else {
                            Label("Not installed", systemImage: "xmark.circle")
                                .font(Geist.Typography.body).foregroundStyle(Geist.Colors.mute).labelStyle(.titleAndIcon)
                        }
                    }
                    if let usage = agentMonitor.usage, !usage.isEmpty {
                        if let five = usage.fiveHour { GeistRow { usageRow(label: "5-hour limit", window: five) } }
                        if let week = usage.sevenDay { GeistRow { usageRow(label: "7-day limit", window: week) } }
                        if let cachedAt = usage.cachedAt {
                            GeistRow {
                                Text("Updated \(relativeTime(cachedAt)) · refreshes on each Claude turn")
                                    .font(Geist.Typography.caption).foregroundStyle(Geist.Colors.mute)
                            }
                        }
                    }
                    GeistRow(divider: false) {
                        HStack(spacing: Geist.Spacing.xs) {
                            if agentMonitor.statusLineInstalled {
                                Button("Reinstall") { agentMonitor.installStatusLine() }.buttonStyle(.geist)
                                Button("Remove") { agentMonitor.uninstallStatusLine() }.buttonStyle(.geist)
                            } else {
                                Button("Install status line") { agentMonitor.installStatusLine() }.buttonStyle(.geistProminent)
                            }
                        }
                    }
                }

                if let error = agentMonitor.lastErrorMessage {
                    GeistSection {
                        GeistRow(divider: false) {
                            Text(error).font(Geist.Typography.caption).foregroundStyle(Geist.Colors.error)
                        }
                    }
                }
            }
        }
        .onAppear {
            agentMonitor.refreshHookStatus()
            agentMonitor.refreshStatusLineStatus()
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private func usageRow(label: String, window: ClaudeUsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                Spacer()
                Text("\(window.roundedUsedPercentage)%")
                    .foregroundStyle(window.usedPercentage >= 80 ? .orange : .secondary)
                    .monospacedDigit()
            }
            ProgressView(value: min(max(window.usedPercentage / 100, 0), 1))
                .tint(window.usedPercentage >= 80 ? .orange : .accentColor)
        }
    }

    @ViewBuilder
    private var hookStatusLabel: some View {
        switch agentMonitor.hookStatus {
        case .installed:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        case .notInstalled:
            Label("Not installed", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
        case .unknown:
            Label("Unknown", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
        }
    }
}
