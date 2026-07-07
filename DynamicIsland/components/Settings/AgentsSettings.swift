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
    @ObservedObject private var antigravityQuotaAuth = AntigravityQuotaAuthManager.shared
    @ObservedObject private var openCodeQuotaSession = OpenCodeQuotaSessionManager.shared
    @ObservedObject private var cursorSync = CursorUsageSyncManager.shared
    @State private var cursorTokenInput = ""
    @Default(.enableAgentMonitoring) var enableAgentMonitoring
    @Default(.agentUsageProviderOrder) private var providerOrder
    @Default(.disabledAgentUsageProviders) private var disabledProviders
    @Environment(\.colorScheme) private var colorScheme
    @Default(.agentInputSoundEnabled) private var inputSoundEnabled
    @Default(.agentCompletionSoundEnabled) private var completionSoundEnabled
    @Default(.agentInputSoundPath) private var inputSoundPath
    @Default(.agentCompletionSoundPath) private var completionSoundPath
    @Default(.agentAntigravityCompactQuotaWindows) private var compactAntigravityQuotaWindows
    @Default(.agentOpenCodeCompactQuotaWindows) private var compactOpenCodeQuotaWindows

    private enum SubPage: String, Hashable { case usage, order }

    private let agentTint = Color(red: 217.0 / 255.0, green: 119.0 / 255.0, blue: 66.0 / 255.0)

    var body: some View {
        NavigationStack {
            agentsRoot
                .navigationDestination(for: SubPage.self) { page in
                    switch page {
                    case .usage: usagePage
                    case .order: usageOrderPage
                    }
                }
        }
    }

    private var agentsRoot: some View {
        GeistSettingsPage(title: "Agents", subtitle: "Track AI coding-agent sessions (Claude Code, Codex, Antigravity, OpenCode, Gemini, Cursor, Kimi) in the notch.") {
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

                hookSection(
                    title: "Gemini",
                    info: "Installing writes VibeIsland-namespaced hooks into ~/.gemini/settings.json. Fails open if VibeIsland isn't running.",
                    status: agentMonitor.geminiHookStatus,
                    install: { agentMonitor.installGeminiHooks() },
                    uninstall: { agentMonitor.uninstallGeminiHooks() }
                )

                hookSection(
                    title: "Cursor",
                    info: "Installing writes VibeIsland-namespaced hooks into ~/.cursor/hooks.json. Fails open if VibeIsland isn't running.",
                    status: agentMonitor.cursorHookStatus,
                    install: { agentMonitor.installCursorHooks() },
                    uninstall: { agentMonitor.uninstallCursorHooks() }
                )

                hookSection(
                    title: "Kimi",
                    info: "Installing writes VibeIsland-namespaced hooks into ~/.kimi/config.toml. Fails open if VibeIsland isn't running.",
                    status: agentMonitor.kimiHookStatus,
                    install: { agentMonitor.installKimiHooks() },
                    uninstall: { agentMonitor.uninstallKimiHooks() }
                )

                GeistSection {
                    GeistNavRow(
                        title: "Usage",
                        subtitle: "Rate limits, cost, and token totals",
                        systemImage: "chart.bar.xaxis",
                        tint: agentTint,
                        value: SubPage.usage
                    )
                    GeistNavRow(
                        title: "Card order",
                        subtitle: "Reorder and toggle the usage-panel cards",
                        systemImage: "arrow.up.arrow.down",
                        tint: agentTint,
                        value: SubPage.order,
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
            agentMonitor.refreshGeminiHookStatus()
            agentMonitor.refreshCursorHookStatus()
            agentMonitor.refreshKimiHookStatus()
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

            GeistSection(
                title: "Antigravity rate limits",
                footer: "Uses Google OAuth and the Antigravity Code Assist quota endpoint. Tokens are stored in your macOS Keychain."
            ) {
                GeistToggleRow(
                    title: "Merge Antigravity quota groups",
                    description: "Show one 5-hour row and one 7-day row instead of separate Gemini and Claude/GPT rows.",
                    isOn: $compactAntigravityQuotaWindows
                )
                GeistLabeledRow(title: "Google account") {
                    if antigravityQuotaAuth.isAuthenticated {
                        Label(
                            antigravityQuotaAuth.accountEmail ?? "Connected",
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(Geist.Typography.body)
                        .foregroundStyle(Geist.Colors.success)
                        .labelStyle(.titleAndIcon)
                    } else {
                        Label("Not connected", systemImage: "xmark.circle")
                            .font(Geist.Typography.body)
                            .foregroundStyle(Geist.Colors.mute)
                            .labelStyle(.titleAndIcon)
                    }
                }
                if let quota = agentMonitor.providerQuotas[.antigravity] {
                    let windows = AgentQuotaPresentation.windows(
                        providerID: .antigravity,
                        windows: quota.windows,
                        compactAntigravity: compactAntigravityQuotaWindows,
                        compactOpenCode: compactOpenCodeQuotaWindows
                    )
                    ForEach(windows) { window in
                        GeistRow {
                            providerQuotaRow(window: window)
                                .font(Geist.Typography.body)
                        }
                    }
                }
                if let error = antigravityQuotaAuth.errorMessage {
                    GeistRow {
                        Text(error)
                            .font(Geist.Typography.caption)
                            .foregroundStyle(Geist.Colors.error)
                    }
                }
                GeistRow(divider: false) {
                    HStack(spacing: Geist.Spacing.xs) {
                        if antigravityQuotaAuth.isAuthenticated {
                            Button("Refresh") {
                                agentMonitor.refreshProviderQuotas(force: true)
                            }
                            .buttonStyle(.geistProminent)
                            Button("Disconnect") {
                                antigravityQuotaAuth.signOut()
                            }
                            .buttonStyle(.geist)
                        } else {
                            Button(
                                antigravityQuotaAuth.isAuthorizing
                                    ? "Waiting for Google…"
                                    : "Connect Google account"
                            ) {
                                antigravityQuotaAuth.signIn()
                            }
                            .buttonStyle(.geistProminent)
                            .disabled(antigravityQuotaAuth.isAuthorizing)
                        }
                    }
                }
            }

            GeistSection(
                title: "OpenCode Go rate limits",
                footer: "Uses a persistent in-app opencode.ai session to read the Rolling, Weekly, and Monthly windows from your Go dashboard."
            ) {
                GeistToggleRow(
                    title: "Show compact OpenCode quota",
                    description: "Show only the rolling 5-hour and weekly 7-day rows, hiding the monthly row.",
                    isOn: $compactOpenCodeQuotaWindows
                )
                let openCodeQuota = agentMonitor.providerQuotas[.opencode]
                let isOpenCodeConnected = openCodeQuotaSession.isAuthenticated || openCodeQuota != nil
                GeistLabeledRow(title: "Dashboard session") {
                    if isOpenCodeConnected {
                        Label(
                            openCodeQuotaSession.workspaceID.map(maskedWorkspaceID) ?? "Connected",
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(Geist.Typography.body)
                        .monospacedDigit()
                        .foregroundStyle(Geist.Colors.success)
                        .labelStyle(.titleAndIcon)
                    } else {
                        Label("Not connected", systemImage: "xmark.circle")
                            .font(Geist.Typography.body)
                            .foregroundStyle(Geist.Colors.mute)
                            .labelStyle(.titleAndIcon)
                    }
                }
                if let quota = openCodeQuota {
                    let windows = AgentQuotaPresentation.windows(
                        providerID: .opencode,
                        windows: quota.windows,
                        compactAntigravity: compactAntigravityQuotaWindows,
                        compactOpenCode: compactOpenCodeQuotaWindows
                    )
                    ForEach(windows) { window in
                        GeistRow {
                            providerQuotaRow(window: window)
                                .font(Geist.Typography.body)
                        }
                    }
                }
                if !isOpenCodeConnected, let error = openCodeQuotaSession.errorMessage {
                    GeistRow {
                        Text(error)
                            .font(Geist.Typography.caption)
                            .foregroundStyle(Geist.Colors.error)
                    }
                }
                GeistRow(divider: false) {
                    HStack(spacing: Geist.Spacing.xs) {
                        if isOpenCodeConnected {
                            Button(
                                openCodeQuotaSession.isRefreshing ? "Refreshing…" : "Refresh"
                            ) {
                                openCodeQuotaSession.refresh()
                            }
                            .buttonStyle(.geistProminent)
                            .disabled(openCodeQuotaSession.isRefreshing)
                            Button("Sign in again") {
                                OpenCodeLoginWindowController.shared.show()
                            }
                            .buttonStyle(.geist)
                            Button("Disconnect") {
                                openCodeQuotaSession.disconnect()
                            }
                            .buttonStyle(.geist)
                        } else {
                            Button("Sign in to OpenCode") {
                                OpenCodeLoginWindowController.shared.show()
                            }
                            .buttonStyle(.geistProminent)
                        }
                    }
                }
            }

            cursorUsageSection
        }
        .onAppear {
            Task { await antigravityQuotaAuth.reloadStatus() }
            Task { await cursorSync.reloadStatus() }
            agentMonitor.refreshStatusLineStatus()
            agentMonitor.refreshTokenUsage(force: true)
        }
    }

    private var usageOrderPage: some View {
        GeistSettingsPage(title: "Card Order") {
            let order = AgentUsageProviderCatalog.normalizedOrder(providerOrder)
            VStack(alignment: .leading, spacing: Geist.Spacing.xs) {
                List {
                    ForEach(order, id: \.self) { id in
                        usageOrderRow(id)
                            .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .onMove(perform: moveProvider)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(height: CGFloat(order.count) * 40)
                .background(Geist.Colors.canvasSoft)
                .clipShape(RoundedRectangle(cornerRadius: Geist.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Geist.Radius.md, style: .continuous)
                        .strokeBorder(Geist.Colors.hairline, lineWidth: Geist.hairlineWidth)
                )

                Text("Drag rows to reorder the provider cards in the Agents usage panel, and toggle each card on or off. The Summary card is always shown first. An enabled provider's card only appears once it has token or quota data.")
                    .font(Geist.Typography.caption)
                    .foregroundStyle(Geist.Colors.mute)
                    .padding(.leading, Geist.Spacing.xxs)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Reset Order") {
                    providerOrder = AgentUsageProviderCatalog.defaultOrderRawValues
                    disabledProviders = []
                }
                .buttonStyle(.geist)
                .padding(.top, Geist.Spacing.xxs)
            }
        }
    }

    private func usageOrderRow(_ id: AgentUsageProviderID) -> some View {
        let isEnabled = !disabledProviders.contains(id.rawValue)
        return HStack(spacing: Geist.Spacing.sm) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Geist.Colors.mute)
            usageOrderIcon(id)
                .frame(width: 18, height: 18)
                .opacity(isEnabled ? 1 : 0.4)
            Text(id.displayName)
                .font(Geist.Typography.bodyStrong)
                .foregroundStyle(isEnabled ? Geist.Colors.ink : Geist.Colors.mute)
            Spacer(minLength: Geist.Spacing.sm)
            Toggle("", isOn: Binding(
                get: { !disabledProviders.contains(id.rawValue) },
                set: { isOn in
                    if isOn { disabledProviders.remove(id.rawValue) }
                    else { disabledProviders.insert(id.rawValue) }
                }
            ))
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .frame(height: 24)
    }

    @ViewBuilder
    private func usageOrderIcon(_ id: AgentUsageProviderID) -> some View {
        if colorScheme == .dark {
            // In dark mode the full-color marks (cursor/opencode/copilot are dark)
            // vanish against the dark surface, so use the monochrome template
            // marks tinted to the foreground — the same white glyphs the notch uses.
            if let asset = AgentUsageProviderCatalog.icon(for: id).asset {
                Image(asset)
                    .renderingMode(.template)
                    .resizable().aspectRatio(contentMode: .fit)
                    .foregroundStyle(Geist.Colors.ink)
            } else {
                Image(systemName: AgentUsageProviderCatalog.icon(for: id).system)
                    .resizable().aspectRatio(contentMode: .fit)
                    .foregroundStyle(Geist.Colors.ink)
            }
        } else if let asset = AgentUsageProviderCatalog.settingsIconAsset(for: id) {
            Image(asset).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: AgentUsageProviderCatalog.icon(for: id).system)
                .resizable().aspectRatio(contentMode: .fit)
                .foregroundStyle(Geist.Colors.ink)
        }
    }

    private func moveProvider(from source: IndexSet, to destination: Int) {
        var order = AgentUsageProviderCatalog.normalizedOrder(providerOrder)
        order.move(fromOffsets: source, toOffset: destination)
        providerOrder = order.map(\.rawValue)
    }

    private var cursorUsageSection: some View {
        GeistSection(
            title: "Cursor usage",
            footer: "Cursor keeps no local token data, so VibeIsland downloads your usage export from cursor.com to show a token/cost card. Sign in below to capture your session automatically (or paste the WorkosCursorSessionToken cookie manually); it is stored in your macOS Keychain."
        ) {
            GeistLabeledRow(title: "Account") {
                if cursorSync.isConnected {
                    Label(
                        cursorSync.membershipType.map { "Connected · \($0)" } ?? "Connected",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(Geist.Typography.body)
                    .foregroundStyle(Geist.Colors.success)
                    .labelStyle(.titleAndIcon)
                } else {
                    Label("Not connected", systemImage: "xmark.circle")
                        .font(Geist.Typography.body)
                        .foregroundStyle(Geist.Colors.mute)
                        .labelStyle(.titleAndIcon)
                }
            }
            if cursorSync.isConnected, let syncedAt = cursorSync.lastSyncedAt {
                GeistLabeledRow(title: "Last synced") {
                    Text(syncedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(Geist.Typography.body)
                        .foregroundStyle(Geist.Colors.mute)
                        .monospacedDigit()
                }
            }
            if !cursorSync.isConnected {
                GeistRow {
                    VStack(alignment: .leading, spacing: Geist.Spacing.xs) {
                        Text("Advanced: paste the cookie value instead of signing in.")
                            .font(Geist.Typography.caption)
                            .foregroundStyle(Geist.Colors.mute)
                        SecureField("WorkosCursorSessionToken", text: $cursorTokenInput)
                            .textFieldStyle(.roundedBorder)
                            .font(Geist.Typography.body)
                    }
                }
            }
            if let error = cursorSync.errorMessage {
                GeistRow {
                    Text(error)
                        .font(Geist.Typography.caption)
                        .foregroundStyle(Geist.Colors.error)
                }
            }
            GeistRow(divider: false) {
                HStack(spacing: Geist.Spacing.xs) {
                    if cursorSync.isConnected {
                        Button(cursorSync.isSyncing ? "Syncing…" : "Sync") {
                            cursorSync.sync()
                        }
                        .buttonStyle(.geistProminent)
                        .disabled(cursorSync.isSyncing)
                        Button("Sign in again") {
                            CursorLoginWindowController.shared.show()
                        }
                        .buttonStyle(.geist)
                        Button("Disconnect") {
                            cursorSync.disconnect()
                        }
                        .buttonStyle(.geist)
                    } else {
                        Button(cursorSync.isSyncing ? "Signing in…" : "Sign in to Cursor") {
                            CursorLoginWindowController.shared.show()
                        }
                        .buttonStyle(.geistProminent)
                        .disabled(cursorSync.isSyncing)
                        Button("Connect with token") {
                            cursorSync.connect(token: cursorTokenInput)
                            cursorTokenInput = ""
                        }
                        .buttonStyle(.geist)
                        .disabled(cursorSync.isSyncing || cursorTokenInput.isEmpty)
                    }
                }
            }
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

    /// Masks the middle of the workspace id so the connected account is
    /// recognizable without exposing the full identifier (e.g.
    /// `wrk_01KR********VR1`).
    private func maskedWorkspaceID(_ id: String) -> String {
        guard id.count > 11 else { return id }
        return "\(id.prefix(8))********\(id.suffix(3))"
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

    /// Progress-bar row for a provider-neutral quota window (Antigravity,
    /// OpenCode…), matching the Claude/Codex rate-limit rows.
    @ViewBuilder
    private func providerQuotaRow(window: ProviderQuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.label)
                Spacer()
                Text("\(Int(window.usedPercentage.rounded()))%")
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
