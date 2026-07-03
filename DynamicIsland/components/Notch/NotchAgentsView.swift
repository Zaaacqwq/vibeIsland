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

import SwiftUI
import Defaults
import OpenIslandCore

/// Open-notch tab listing Claude Code sessions, with jump-back and inline
/// permission approve/deny. Falls back to a hook-setup empty state when no
/// hooks are installed, or a "no sessions" state once they are.
struct NotchAgentsView: View {
    /// Only the primary Agents tab renders the full approve/ask overlay; the
    /// home view's secondary panel shows the list (with per-row reopen buttons).
    var showsInputOverlay: Bool = true
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var agentMonitor = AgentMonitorManager.shared

    private let claudeColor = Color(red: 217.0 / 255.0, green: 119.0 / 255.0, blue: 66.0 / 255.0)
    private let codexColor = Color(red: 16.0 / 255.0, green: 163.0 / 255.0, blue: 127.0 / 255.0)

    // Suppress the notch's scroll-to-close gesture while hovering the list, so
    // scrolling pages through sessions instead of closing the notch.
    @State private var scrollSuppressionToken = UUID()
    @State private var isSuppressingScroll = false

    var body: some View {
        // Stays a `Group` (not a ZStack): a ZStack with the maxHeight:.infinity
        // frame below fills greedily, which made the Agents panel embedded in the
        // Home tab balloon to the full notch height. The list branch carries NO
        // root `.transition`, so when this tab switches the ContentView slide owns
        // enter/exit (Agents slides like every other tab). The `.transition(.opacity)`
        // stays on the approve/ask overlay only, so it still crossfades over the
        // list when `activeInputSession` toggles — an internal swap, not a tab switch.
        Group {
            if showsInputOverlay, let active = agentMonitor.activeInputSession {
                // The approve/ask overlay lives inside the Agents tab so it sits
                // at the normal tab height (content scrolls) — no notch-height
                // jump, hence no open/close glitch.
                AgentInputOverlay(session: active)
                    .id(active.id)
                    .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    header
                    content
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        // Always fill the available height — both as the full Agents tab and as
        // the Home-embedded card. The Home card is now given a fixed, definite
        // height by its parent (equal-height two-column grid), so filling here
        // makes the idle empty-state center within that card instead of hugging
        // its content and sticking out taller than the media card beside it.
        // (This no longer inflates Home: the open-notch height is fixed — see
        // `standardOpenNotchContentHeight` — so filling can't grow the window.)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
        )
        .contentShape(Rectangle())
        .onHover { updateScrollSuppression(for: $0) }
        .onAppear { agentMonitor.refreshHookStatus() }
        .onDisappear { updateScrollSuppression(for: false) }
        .animation(.smooth(duration: 0.25), value: agentMonitor.activeInputSession?.id)
    }

    private func updateScrollSuppression(for hovering: Bool) {
        guard hovering != isSuppressingScroll else { return }
        isSuppressingScroll = hovering
        vm.setScrollGestureSuppression(hovering, token: scrollSuppressionToken)
    }

    /// Home-embed has no tab pill of its own (the shared header only shows
    /// "Home" as active), so it needs its own mono "AGENTS" eyebrow. The full
    /// Agents tab is already identified by the shared header's active tab
    /// pill, so its own content starts straight with the usage badges.
    private var header: some View {
        HStack(spacing: 6) {
            if !showsInputOverlay {
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(claudeColor)
                NotchMonoEyebrow(text: "Agents")
            }
            Spacer()
            let claudeUsage = agentMonitor.usage
            let codexUsage = agentMonitor.codexUsage
            let hasClaude = claudeUsage.map { !$0.isEmpty } ?? false
            let hasCodex = codexUsage.map { !$0.isEmpty } ?? false
            if hasClaude || hasCodex {
                HStack(spacing: 6) {
                    if let claudeUsage, hasClaude {
                        claudeUsageBadges(claudeUsage)
                    }
                    if let codexUsage, hasCodex {
                        codexUsageBadges(codexUsage)
                    }
                }
            } else if !agentMonitor.isBridgeReady {
                Text("Connecting…")
                    .font(NotchDesign.Typography.mono(11))
                    .foregroundStyle(NotchDesign.Colors.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func claudeUsageBadges(_ usage: ClaudeUsageSnapshot) -> some View {
        HStack(spacing: 4) {
            Image("claude-icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 11, height: 11)
                .foregroundStyle(NotchDesign.Colors.textPrimary)
                .help("Claude usage")
            if let five = usage.fiveHour {
                usageBadge(title: "5h", percent: five.roundedUsedPercentage, warn: five.usedPercentage >= 80, help: "Claude 5-hour limit used")
            }
            if let week = usage.sevenDay {
                usageBadge(title: "7d", percent: week.roundedUsedPercentage, warn: week.usedPercentage >= 80, help: "Claude 7-day limit used")
            }
        }
    }

    @ViewBuilder
    private func codexUsageBadges(_ usage: CodexUsageSnapshot) -> some View {
        HStack(spacing: 4) {
            Image("codex-icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 11, height: 11)
                .foregroundStyle(NotchDesign.Colors.textPrimary)
                .help("Codex usage")
            ForEach(usage.windows) { window in
                usageBadge(
                    title: window.label,
                    percent: window.roundedUsedPercentage,
                    warn: window.usedPercentage >= 80,
                    help: "Codex \(window.label) limit used"
                )
            }
        }
    }

    private func usageBadge(title: String, percent: Int, warn: Bool, help: String) -> some View {
        Text("\(title) \(percent)%")
            .font(NotchDesign.Typography.mono(10, weight: .medium))
            .foregroundStyle(warn ? NotchDesign.Colors.warning : NotchDesign.Colors.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(warn ? NotchDesign.Colors.warning.opacity(0.1) : Color.white.opacity(0.06)))
            .help(help)
    }

    @ViewBuilder
    private var content: some View {
        if agentMonitor.sessions.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: showsInputOverlay ? 9 : 8) {
                    ForEach(agentMonitor.sessions) { session in
                        AgentSessionRow(session: session, accent: claudeColor, compact: !showsInputOverlay)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            // Center the moon vertically in the card — both in the full Agents tab
            // and in the Home embed. The Home card now has a fixed, definite height
            // (equal-height grid), so these Spacers center the empty-state within it
            // rather than ballooning Home (the window height is fixed regardless).
            Spacer()
            switch agentMonitor.hookStatus {
            case .installed, .unknown:
                Image(systemName: "moon.zzz")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(NotchDesign.Colors.textTertiary)
                Text("No active sessions")
                    .font(NotchDesign.Typography.voice(15, weight: .semibold))
                    .foregroundStyle(NotchDesign.Colors.textSecondary)
                Text("$ claude")
                    .font(NotchDesign.Typography.mono(12))
                    .foregroundStyle(NotchDesign.Colors.textFaint)
            case .notInstalled:
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(NotchDesign.Colors.accent)
                Text("Set up Claude Code")
                    .font(NotchDesign.Typography.voice(15, weight: .semibold))
                    .foregroundStyle(NotchDesign.Colors.textPrimary)
                Text("Install hooks so VibeIsland can track your sessions.")
                    .font(NotchDesign.Typography.voice(12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(NotchDesign.Colors.textSecondary)
                Button {
                    agentMonitor.installHooks()
                } label: {
                    Text("Install hooks")
                        .font(NotchDesign.Typography.voice(12, weight: .semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(NotchDesign.Colors.accent))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A single session row: status glyph, title/summary, and contextual actions.
/// `compact` is the Home-embed sizing (smaller ring/type, sunken `#0b0b0b`
/// fill nested inside the outer `#141414` card); the full Agents tab uses the
/// larger sizing directly on the card fill (no outer wrapper there).
private struct AgentSessionRow: View {
    let session: AgentSession
    let accent: Color
    var compact: Bool = true
    @ObservedObject private var agentMonitor = AgentMonitorManager.shared

    private var ringSize: CGFloat { compact ? 14 : 16 }
    private var titleFont: Font { NotchDesign.Typography.voice(compact ? 12 : 14, weight: .medium) }
    private var statusFont: Font { NotchDesign.Typography.mono(compact ? 10 : 11) }
    private var rowPadding: EdgeInsets { compact ? EdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 10) : EdgeInsets(top: 12, leading: 13, bottom: 12, trailing: 13) }
    private var rowRadius: CGFloat { compact ? NotchDesign.Radius.sm : NotchDesign.Radius.md }
    private var rowFill: Color { compact ? NotchDesign.Colors.sunken : NotchDesign.Colors.cardFill }
    private var rowGap: CGFloat { compact ? 9 : 11 }

    private var isAwaitingPermission: Bool { session.permissionRequest != nil }

    private var borderColor: Color {
        isAwaitingPermission ? NotchDesign.Colors.warning.opacity(compact ? 0.22 : 0.28) : NotchDesign.Colors.hairline
    }

    var body: some View {
        let halo = agentMonitor.haloState(for: session)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: rowGap) {
                HaloRingView(state: halo, size: ringSize)
                VStack(alignment: .leading, spacing: compact ? 1 : 4) {
                    Text(session.title.isEmpty ? "Claude session" : session.title)
                        .font(titleFont)
                        .foregroundStyle(NotchDesign.Colors.textPrimary)
                        .lineLimit(1)
                    Text(halo.label)
                        .font(statusFont)
                        .foregroundStyle(halo.color)
                }
                Spacer()
                if session.permissionRequest != nil || session.questionPrompt != nil {
                    Button {
                        agentMonitor.presentInput(for: session.id)
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                    .help("Open the full prompt")
                }
                if session.jumpTarget != nil {
                    Button {
                        agentMonitor.jumpBack(to: session)
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(NotchDesign.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Jump back to the external terminal")
                }
            }

            if let permission = session.permissionRequest {
                permissionActions(permission)
            }
            if let question = session.questionPrompt {
                questionActions(question, sessionID: session.id)
            }
        }
        .padding(rowPadding)
        .background(rowFill, in: RoundedRectangle(cornerRadius: rowRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: rowRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func permissionActions(_ permission: PermissionRequest) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !permission.summary.isEmpty {
                Text(permission.summary)
                    .font(statusFont)
                    .foregroundStyle(NotchDesign.Colors.textSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: compact ? 6 : 8) {
                Button {
                    agentMonitor.resolvePermission(sessionID: session.id, approved: true)
                } label: {
                    Text(permission.primaryActionTitle.isEmpty ? "Allow" : permission.primaryActionTitle)
                        .font(NotchDesign.Typography.voice(compact ? 11 : 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, compact ? 6 : 8)
                        .background(NotchDesign.Colors.success, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                Button {
                    agentMonitor.resolvePermission(sessionID: session.id, approved: false)
                } label: {
                    Text(permission.secondaryActionTitle.isEmpty ? "Deny" : permission.secondaryActionTitle)
                        .font(NotchDesign.Typography.voice(compact ? 11 : 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, compact ? 6 : 8)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(NotchDesign.Colors.danger.opacity(0.4), lineWidth: 1)
                        }
                        .foregroundStyle(NotchDesign.Colors.danger)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func questionActions(_ prompt: QuestionPrompt, sessionID: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !prompt.title.isEmpty {
                Text(prompt.title)
                    .font(statusFont)
                    .foregroundStyle(NotchDesign.Colors.textSecondary)
                    .lineLimit(2)
            }
            if let options = prompt.questions.first?.options, !options.isEmpty {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    optionButton(index: index, label: option.label, allowsFreeform: option.allowsFreeform) {
                        if option.allowsFreeform {
                            // Freeform needs the text field in the full overlay —
                            // open it (un-collapse) straight into text-entry mode.
                            agentMonitor.requestedFreeformOptionID = option.id
                            agentMonitor.presentInput(for: sessionID)
                        } else {
                            agentMonitor.answerQuestion(sessionID: sessionID, optionLabel: option.label)
                        }
                    }
                }
            } else {
                ForEach(Array(prompt.options.enumerated()), id: \.offset) { index, label in
                    optionButton(index: index, label: label, allowsFreeform: false) {
                        agentMonitor.answerQuestion(sessionID: sessionID, optionLabel: label)
                    }
                }
            }
        }
    }

    private func optionButton(index: Int, label: String, allowsFreeform: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text("\(index + 1)")
                    .font(NotchDesign.Typography.voice(10, weight: .bold))
                    .foregroundStyle(NotchDesign.Colors.textSecondary)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                Text(label)
                    .font(NotchDesign.Typography.voice(12, weight: .medium))
                    .foregroundStyle(NotchDesign.Colors.textPrimary)
                    .lineLimit(1)
                if allowsFreeform {
                    Image(systemName: "pencil").font(.system(size: 9)).foregroundStyle(NotchDesign.Colors.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NotchDesign.Colors.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(NotchDesign.Colors.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
