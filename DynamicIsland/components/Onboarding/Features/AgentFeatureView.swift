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

/// Agent setup page: pick the coding agents you use; Continue installs the
/// matching hooks/plugin for each (e.g. OpenCode → session/usage/ask/approve).
struct AgentFeatureView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onBack: () -> Void

    @ObservedObject private var agentMonitor = AgentMonitorManager.shared
    @State private var selected: Set<String> = []

    /// A selectable agent provider and how to install its integration.
    private struct Provider: Identifiable {
        let id: String
        let title: String
        let icon: BubbleIcon
        let install: (AgentMonitorManager) -> Void
        /// Hooks install one-click, but these providers' token usage lives in
        /// the cloud and needs a one-time sign-in from Settings › Agents.
        var usageNeedsSignIn: Bool = false
    }

    private let providers: [Provider] = [
        Provider(id: "claude", title: "Claude Code", icon: .asset("claude-icon"), install: { $0.installHooks() }),
        Provider(id: "opencode", title: "OpenCode", icon: .asset("opencode-icon"), install: { $0.installOpenCodeHooks() }, usageNeedsSignIn: true),
        Provider(id: "codex", title: "Codex", icon: .asset("codex-icon"), install: { $0.installCodexHooks() }),
        Provider(id: "gemini", title: "Gemini", icon: .asset("gemini-icon"), install: { $0.installGeminiHooks() }),
        Provider(id: "cursor", title: "Cursor", icon: .asset("cursor-icon"), install: { $0.installCursorHooks() }, usageNeedsSignIn: true),
        Provider(id: "antigravity", title: "Antigravity", icon: .asset("antigravity-icon"), install: { $0.installAntigravityHooks() }, usageNeedsSignIn: true),
    ]

    /// Titles of currently-selected providers whose usage needs a manual sign-in.
    private var manualUsageSelected: [String] {
        providers.filter { selected.contains($0.id) && $0.usageNeedsSignIn }.map(\.title)
    }

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        OnboardingScaffold(
            symbol: OnboardingFeature.agent.symbol,
            gradient: OnboardingFeature.agent.gradient,
            title: String(localized: "Which agents do you use?"),
            subtitle: String(localized: "We'll install the hooks so their sessions, usage, and approval prompts show up in the notch."),
            continueTitle: selected.isEmpty ? String(localized: "Continue") : String(localized: "Install & Continue"),
            onBack: onBack,
            onSkip: onSkip,
            onContinue: applyAndContinue
        ) {
            VStack(spacing: 14) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(providers) { provider in
                        SelectBubble(
                            title: provider.title,
                            icon: provider.icon,
                            isSelected: selected.contains(provider.id),
                            gradient: OnboardingFeature.agent.gradient,
                            onTap: { toggle(provider.id) }
                        )
                    }
                }

                if !manualUsageSelected.isEmpty {
                    usageHint
                }
            }
        }
    }

    /// Note shown when a selected provider's usage needs a manual sign-in.
    private var usageHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.orange)
            Text("\(manualUsageSelected.joined(separator: ", ")) hooks install now, but their token usage needs a one-time sign-in later in Settings › Agents.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
    }

    private func toggle(_ id: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        }
    }

    private func applyAndContinue() {
        Defaults[.enableAgentMonitoring] = true
        for provider in providers where selected.contains(provider.id) {
            provider.install(agentMonitor)
        }
        onContinue()
    }
}
