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

    // The full Agents tab (overlay + two-column) fills the shared tab container
    // from ContentView, which already applies uniform insets and the shared
    // height budget (`NotchDesign.TabInset`). Only the Home-embed branch below
    // keeps its own padding, since it renders inside a Home card, not the tab.

    // Suppress the notch's scroll-to-close gesture while hovering the list, so
    // scrolling pages through sessions instead of closing the notch.
    @State private var scrollSuppressionToken = UUID()
    @State private var isSuppressingScroll = false

    /// Edge-fade heights for the session lists. Rows are inset by the same amount
    /// so the first/last clear the fade at rest; the compact Home embed uses a
    /// smaller fade than the full tab.
    private let homeListFadeHeight: CGFloat = 12
    private let fullListFadeHeight: CGFloat = 16

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
                // The approve/ask overlay fills (nearly) the whole content region
                // so a long diff / option list has room and no dead-black band
                // sits beneath it. Its content scrolls, so this never grows the
                // notch past the cap.
                AgentInputOverlay(session: active)
                    .id(active.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
            } else if showsInputOverlay {
                // Full Agents tab: two columns — session list on the left (~60%),
                // rate-limit + token-usage panels stacked on the right (~40%).
                GeometryReader { geo in
                    let gap: CGFloat = 12
                    let leftWidth = max(0, (geo.size.width - gap) * 0.5)
                    HStack(alignment: .top, spacing: gap) {
                        sessionColumn
                            .frame(width: leftWidth, alignment: .top)
                        usageColumn
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                // Home embed: intrinsic height, eyebrow header + compact session
                // list. Its parent card owns the height (maxHeight nil).
                VStack(alignment: .leading, spacing: 8) {
                    header
                    content
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .contentShape(Rectangle())
        .onHover { updateScrollSuppression(for: $0) }
        .onAppear {
            agentMonitor.refreshHookStatus()
            if showsInputOverlay { agentMonitor.refreshTokenUsage() }
        }
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
        let badges = AgentUsageBadges(claude: agentMonitor.usage, codex: agentMonitor.codexUsage)
        return HStack(spacing: 6) {
            if !showsInputOverlay {
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(NotchDesign.Colors.accent)
                NotchMonoEyebrow(text: "Agents")
                    // Keep the wordmark on one line — the rigid badges otherwise
                    // compress it into "AGE…" / "AGEN\nTS".
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            if badges.hasAny {
                badges
            } else if !agentMonitor.isBridgeReady {
                Text("Connecting…")
                    .font(NotchDesign.Typography.mono(11))
                    .foregroundStyle(NotchDesign.Colors.textTertiary)
            }
        }
    }

    /// Home-embed content: compact session list, no usage panels.
    @ViewBuilder
    private var content: some View {
        if agentMonitor.sessions.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(agentMonitor.sessions) { session in
                        AgentSessionRow(session: session, accent: NotchDesign.Colors.accent, compact: true)
                    }
                }
                // Inset the rows by the fade height so the short list's first and
                // last rows clear the fade at rest instead of sitting dimmed under
                // it — the fade then only bites into the padding / while scrolling.
                .padding(.vertical, homeListFadeHeight)
            }
            // Home embed sits on the lighter card fill, not the black panel, so
            // fade to the card colour (a black fade would read as a dark band).
            .notchListEdgeFade(color: NotchDesign.Colors.cardFill, height: homeListFadeHeight)
        }
    }

    /// Left column of the full tab: the scrollable session list, or the centered
    /// empty / hook-setup state when there are none.
    @ViewBuilder
    private var sessionColumn: some View {
        if agentMonitor.sessions.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 9) {
                    ForEach(agentMonitor.sessions) { session in
                        AgentSessionRow(session: session, accent: NotchDesign.Colors.accent, compact: false)
                    }
                }
                // Keep the first row aligned with the usage column; only inset the
                // bottom so the last row clears the bottom fade at rest.
                .padding(.bottom, fullListFadeHeight)
            }
            .notchListEdgeFade(height: fullListFadeHeight, showsTop: false)
        }
    }

    /// Right column of the full tab: a bare rate-limit line above the token-usage
    /// card, sized to fit without scrolling.
    private var usageColumn: some View {
        // The compact rate-limit badges now live in the open-notch header
        // (`NotchHeaderContextWidget`), so the tab body keeps only the detailed
        // token-usage panel and lets it own the column.
        VStack(alignment: .leading, spacing: 10) {
            if agentMonitor.detailedTokenUsage != nil || agentMonitor.tokenUsage != nil || agentMonitor.usage != nil || agentMonitor.codexUsage != nil {
                AgentProviderUsagePager(
                    summary: agentMonitor.detailedTokenUsage,
                    claudeUsage: agentMonitor.usage,
                    codexUsage: agentMonitor.codexUsage,
                    providerQuotas: agentMonitor.providerQuotas,
                    isRefreshing: agentMonitor.isRefreshingTokenUsage,
                    onRefresh: { agentMonitor.refreshTokenUsage(force: true) }
                )
            } else if !agentMonitor.isBridgeReady {
                Text("Connecting…")
                    .font(NotchDesign.Typography.mono(11))
                    .foregroundStyle(NotchDesign.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                AgentProviderUsagePager(
                    summary: nil,
                    claudeUsage: nil,
                    codexUsage: nil,
                    providerQuotas: agentMonitor.providerQuotas,
                    isRefreshing: agentMonitor.isRefreshingTokenUsage,
                    onRefresh: { agentMonitor.refreshTokenUsage(force: true) }
                )
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            // Center the empty state in the full Agents tab. The Home embed stays
            // compact here; its parent owns the card height.
            if showsInputOverlay {
                Spacer()
            }
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
                Text("Set up Agents")
                    .font(NotchDesign.Typography.voice(13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
            if showsInputOverlay {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: showsInputOverlay ? .infinity : nil)
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

    private var ringSize: CGFloat { compact ? 14 : 15 }
    private var titleFont: Font { NotchDesign.Typography.voice(compact ? 12 : 12.5, weight: .medium) }
    private var statusFont: Font { NotchDesign.Typography.mono(compact ? 10 : 10) }
    private var rowPadding: EdgeInsets { compact ? EdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 10) : EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12) }
    private var rowRadius: CGFloat { compact ? NotchDesign.Radius.sm : NotchDesign.Radius.md }
    private var rowFill: Color { compact ? NotchDesign.Colors.sunken : NotchDesign.Colors.cardFill }
    private var rowGap: CGFloat { compact ? 9 : 11 }

    private var isAwaitingPermission: Bool { session.permissionRequest != nil }

    /// A prompt we can detect and show but not answer in-notch — e.g. a Codex
    /// `request_user_input` (question) or approval read from the rollout, which
    /// has no write channel back. The prompt text lives in `summary`; the user
    /// jumps back to answer in the terminal. Distinct from an interactive
    /// permission/question that carries its own request object.
    private var detectedPromptText: String? {
        guard session.permissionRequest == nil,
              session.questionPrompt == nil,
              session.phase.requiresAttention,
              !session.summary.isEmpty else { return nil }
        return session.summary
    }

    private var isAwaiting: Bool { session.phase.requiresAttention }

    private var borderColor: Color {
        isAwaiting ? NotchDesign.Colors.warning.opacity(compact ? 0.22 : 0.28) : NotchDesign.Colors.hairline
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
            if let prompt = detectedPromptText {
                // Read-only prompt (e.g. Codex asked a question) — show the text
                // and let the user jump back to answer in the terminal. No input
                // field: there is no channel to send an answer back.
                HStack(alignment: .top, spacing: 6) {
                    Text(prompt)
                        .font(statusFont)
                        .foregroundStyle(NotchDesign.Colors.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if session.jumpTarget != nil {
                        Text("Answer in terminal ↗")
                            .font(NotchDesign.Typography.voice(compact ? 10 : 11, weight: .medium))
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }
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
