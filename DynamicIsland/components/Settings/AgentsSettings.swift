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

/// Settings pane for the AI coding-agent monitor (Open Island integration).
/// Master switch, live-activity toggle, and Claude Code hook installation.
struct AgentsSettings: View {
    @ObservedObject var agentMonitor = AgentMonitorManager.shared
    @Default(.enableAgentMonitoring) var enableAgentMonitoring

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableAgentMonitoring) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable agent monitoring")
                        Text("Track AI coding-agent sessions (Claude Code) in the notch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if enableAgentMonitoring {
                    Defaults.Toggle(key: .showAgentLiveActivity) {
                        Text("Show status in the notch (live activity)")
                    }
                }
            } header: {
                Text("General")
            } footer: {
                Text("Adds an Agents tab and a closed-notch live activity showing running Claude Code sessions, permission prompts, and one-click jump-back to the terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if enableAgentMonitoring {
                Section {
                    HStack {
                        Text("Bridge")
                        Spacer()
                        Label(
                            agentMonitor.isBridgeReady ? "Connected" : "Starting…",
                            systemImage: agentMonitor.isBridgeReady ? "checkmark.circle.fill" : "clock"
                        )
                        .foregroundStyle(agentMonitor.isBridgeReady ? .green : .secondary)
                        .labelStyle(.titleAndIcon)
                    }

                    HStack {
                        Text("Claude Code hooks")
                        Spacer()
                        hookStatusLabel
                    }

                    HStack(spacing: 8) {
                        switch agentMonitor.hookStatus {
                        case .installed:
                            Button("Reinstall") { agentMonitor.installHooks() }
                            Button("Remove", role: .destructive) { agentMonitor.uninstallHooks() }
                        case .notInstalled, .unknown:
                            Button("Install hooks") { agentMonitor.installHooks() }
                        }
                    }
                } header: {
                    Text("Claude Code")
                } footer: {
                    Text("Installing writes Atoll-namespaced hooks into ~/.claude/settings.json. Hooks fail open — if Atoll isn't running, Claude is unaffected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = agentMonitor.lastErrorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("Agents")
        .onAppear { agentMonitor.refreshHookStatus() }
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
