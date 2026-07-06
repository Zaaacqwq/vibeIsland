/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
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

import AppKit
import SwiftUI
import Defaults
import OpenIslandCore
import UniformTypeIdentifiers

/// Settings pane for the AI coding-agent monitor (Open Island integration).
/// Master switch, live-activity toggle, and per-agent hook installation.
struct AgentsSettings: View {
    @ObservedObject var agentMonitor = AgentMonitorManager.shared
    @Default(.enableAgentMonitoring) var enableAgentMonitoring
    @Default(.agentInputSoundEnabled) private var inputSoundEnabled
    @Default(.agentCompletionSoundEnabled) private var completionSoundEnabled
    @Default(.agentInputSoundPath) private var inputSoundPath
    @Default(.agentCompletionSoundPath) private var completionSoundPath

    private enum SubPage: String, Hashable { case usage }

    private let agentTint = Color(red: 217.0 / 255.0, green: 119.0 / 255.0, blue: 66.0 / 255.0)

    var body: some View {
        NavigationStack {
            agentsRoot
                .navigationDestination(for: SubPage.self) { page in
                    switch page {
                    case .usage: usagePage
                    }
                }
        }
    }

    private var agentsRoot: some View {
        GeistSettingsPage(title: "Agents", subtitle: "Track AI coding-agent sessions (Claude Code, Codex, Antigravity, OpenCode) in the notch.") {
            GeistSection(
                footer: "Adds an Agents tab and a closed-notch live activity showing running agent sessions, permission prompts, and one-click jump-back to the terminal."
            ) {
                GeistToggleRow(
                    title: "Enable agent monitoring",
                    description: "Track AI coding-agent sessions in the notch.",
                    isOn: $enableAgentMonitoring,
                    divider: enableAgentMonitoring
                )
                if enableAgentMonitoring {
                    GeistToggleRow(title: "Play a sound when an agent needs input", isOn: $inputSoundEnabled)
                    if inputSoundEnabled {
                        agentSoundRow(title: "Input-needed sound", path: $inputSoundPath, bundled: "agent-input-needed")
                    }
                    GeistToggleRow(title: "Play a sound when an agent finishes", isOn: $completionSoundEnabled)
                    if completionSoundEnabled {
                        agentSoundRow(title: "Completion sound", path: $completionSoundPath, bundled: "agent-complete")
                    }
                    GeistToggleRow(
                        title: "Pop up the notch when an agent needs input",
                        description: "Surface the notch for permission and question prompts so you can approve or answer without switching apps.",
                        isOn: geistBinding(.agentExpandOnInputNeeded)
                    )
                    GeistToggleRow(title: "Expand the notch to Agents when an agent finishes", isOn: geistBinding(.agentExpandOnComplete), divider: false)
                }
            }

            if enableAgentMonitoring {
                GeistSection(
                    title: "Claude Code",
                    info: "Installing writes VibeIsland-namespaced hooks into ~/.claude/settings.json. Hooks fail open — if VibeIsland isn't running, Claude is unaffected."
                ) {
                    GeistLabeledRow(title: "Bridge") {
                        Label(agentMonitor.isBridgeReady ? "Connected" : "Starting…",
                              systemImage: agentMonitor.isBridgeReady ? "checkmark.circle.fill" : "clock")
                            .font(Geist.Typography.body)
                            .foregroundStyle(agentMonitor.isBridgeReady ? Geist.Colors.success : Geist.Colors.mute)
                            .labelStyle(.titleAndIcon)
                    }
                    GeistLabeledRow(title: "Claude Code hooks") { hookStatusLabel(agentMonitor.hookStatus) }
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

                hookSection(
                    title: "Codex",
                    info: "Installing writes VibeIsland-namespaced hooks into ~/.codex (config.toml + hooks.json). Fails open if VibeIsland isn't running.",
                    status: agentMonitor.codexHookStatus,
                    install: { agentMonitor.installCodexHooks() },
                    uninstall: { agentMonitor.uninstallCodexHooks() }
                )

                hookSection(
                    title: "Antigravity",
                    info: "Installs a VibeIsland plugin into ~/.gemini/config/plugins/ (and registers it) so Antigravity CLI (agy) sessions appear in the notch. Fails open if VibeIsland isn't running.",
                    status: agentMonitor.antigravityHookStatus,
                    install: { agentMonitor.installAntigravityHooks() },
                    uninstall: { agentMonitor.uninstallAntigravityHooks() }
                )

                hookSection(
                    title: "OpenCode",
                    info: "Installs a JS plugin into ~/.config/opencode/plugins/ and registers it in config.json. Fails open if VibeIsland isn't running.",
                    status: agentMonitor.openCodeHookStatus,
                    install: { agentMonitor.installOpenCodeHooks() },
                    uninstall: { agentMonitor.uninstallOpenCodeHooks() }
                )

                GeistSection {
                    GeistNavRow(
                        title: "Usage",
                        subtitle: "Rate limits, cost, and token totals",
                        systemImage: "chart.bar.xaxis",
                        tint: agentTint,
                        value: SubPage.usage,
                        divider: false
                    )
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
            agentMonitor.refreshCodexHookStatus()
            agentMonitor.refreshAntigravityHookStatus()
            agentMonitor.refreshOpenCodeHookStatus()
            agentMonitor.refreshStatusLineStatus()
            agentMonitor.refreshTokenUsage()
        }
    }

    private var usagePage: some View {
        GeistSettingsPage(title: "Usage") {
            tokenUsageSection

            GeistSection(
                title: "Claude rate limits",
                info: "Installs a managed Claude Code status line that reports your 5-hour and 7-day rate-limit usage. Modifies the statusLine entry in ~/.claude/settings.json."
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

            GeistSection(
                title: "Codex rate limits",
                footer: "Read directly from your latest Codex rollout under ~/.codex/sessions — no setup required. Updates after each Codex turn."
            ) {
                if let codexUsage = agentMonitor.codexUsage, !codexUsage.isEmpty {
                    ForEach(codexUsage.windows) { window in
                        GeistRow { codexUsageRow(window: window) }
                    }
                    if let plan = codexUsage.planType {
                        GeistRow(divider: codexUsage.capturedAt != nil) {
                            HStack {
                                Text("Plan")
                                Spacer()
                                Text(plan.capitalized).foregroundStyle(Geist.Colors.mute)
                            }
                            .font(Geist.Typography.body)
                        }
                    }
                    if let capturedAt = codexUsage.capturedAt {
                        GeistRow(divider: false) {
                            Text("Updated \(relativeTime(capturedAt)) · refreshes on each Codex turn")
                                .font(Geist.Typography.caption).foregroundStyle(Geist.Colors.mute)
                        }
                    }
                } else {
                    GeistRow(divider: false) {
                        Text("No Codex usage found yet. Run `codex` in a terminal to populate it.")
                            .font(Geist.Typography.caption).foregroundStyle(Geist.Colors.mute)
                    }
                }
            }
        }
        .onAppear {
            agentMonitor.refreshStatusLineStatus()
            agentMonitor.refreshTokenUsage(force: true)
        }
    }

    @ViewBuilder
    private var tokenUsageSection: some View {
        let windowText: String? = agentMonitor.tokenUsage.map { summary in
            "Rolling \(summary.windowDays)-day window across all agents · updated \(relativeTime(summary.generatedAt))."
        }
        GeistSection(title: "Token Usage", footer: windowText) {
            if let usage = agentMonitor.tokenUsage, !usage.isEmpty {
                let b = usage.breakdown
                tokenStatRow("Cost", TokenUsageFormat.cost(usage.costUSD))
                tokenStatRow("Active", TokenUsageFormat.activeDuration(usage.activeSeconds))
                tokenStatRow("Input", TokenUsageFormat.compactCount(b.input))
                tokenStatRow("Output", TokenUsageFormat.compactCount(b.output))
                tokenStatRow("Reasoning", TokenUsageFormat.compactCount(b.reasoning))
                tokenStatRow("Cache", TokenUsageFormat.compactCount(b.cacheTokens))
                tokenStatRow("Total tokens", TokenUsageFormat.compactCount(b.totalTokens), divider: false)
            } else {
                GeistRow(divider: false) {
                    Text("No agent token usage yet. Run an agent in a terminal to populate it.")
                        .font(Geist.Typography.caption).foregroundStyle(Geist.Colors.mute)
                }
            }
        }
    }

    private func tokenStatRow(_ label: String, _ value: String, divider: Bool = true) -> some View {
        GeistLabeledRow(title: label, divider: divider) {
            Text(value)
                .font(Geist.Typography.body)
                .foregroundStyle(Geist.Colors.ink)
                .monospacedDigit()
        }
    }

    // MARK: - Custom agent sounds

    @ViewBuilder
    private func agentSoundRow(title: String, path: Binding<String>, bundled: String, divider: Bool = true) -> some View {
        GeistRow(divider: divider) {
            HStack(spacing: Geist.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Geist.Typography.bodyStrong)
                        .foregroundStyle(Geist.Colors.ink)
                    Text(soundSourceLabel(path.wrappedValue))
                        .font(Geist.Typography.caption)
                        .foregroundStyle(Geist.Colors.mute)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: Geist.Spacing.sm)
                GeistPreviewButton { previewAgentSound(customPath: path.wrappedValue, bundled: bundled) }
                Button("Choose") { chooseAgentSound(into: path) }.buttonStyle(.geist)
                Button("Reset") { path.wrappedValue = "" }
                    .buttonStyle(.geist)
                    .disabled(path.wrappedValue.isEmpty)
            }
        }
    }

    private func soundSourceLabel(_ path: String) -> String {
        path.isEmpty ? String(localized: "Built-in") : String(localized: "Custom: \(URL(fileURLWithPath: path).lastPathComponent)")
    }

    private func previewAgentSound(customPath: String, bundled: String) {
        if let url = AgentMonitorManager.resolveAgentSoundURL(customPath: customPath, bundled: bundled, ext: "mp3") {
            SoundPreview.play(url: url)
        }
    }

    private func chooseAgentSound(into path: Binding<String>) {
        let panel = NSOpenPanel()
        panel.title = "Select Agent Sound"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            path.wrappedValue = url.path
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
    private func codexUsageRow(window: CodexUsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("\(window.label) limit")
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
    private func hookStatusLabel(_ status: AgentMonitorManager.HookStatus) -> some View {
        switch status {
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

    /// A reusable per-agent hook section: status row + Install/Reinstall/Remove.
    @ViewBuilder
    private func hookSection(
        title: String,
        info: String,
        status: AgentMonitorManager.HookStatus,
        install: @escaping () -> Void,
        uninstall: @escaping () -> Void
    ) -> some View {
        GeistSection(title: title, info: info) {
            GeistLabeledRow(title: "\(title) hooks") { hookStatusLabel(status) }
            GeistRow(divider: false) {
                HStack(spacing: Geist.Spacing.xs) {
                    switch status {
                    case .installed:
                        Button("Reinstall", action: install).buttonStyle(.geist)
                        Button("Remove", action: uninstall).buttonStyle(.geist)
                    case .notInstalled, .unknown:
                        Button("Install hooks", action: install).buttonStyle(.geistProminent)
                    }
                }
            }
        }
    }
}
