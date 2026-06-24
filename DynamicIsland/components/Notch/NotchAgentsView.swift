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

    // Suppress the notch's scroll-to-close gesture while hovering the list, so
    // scrolling pages through sessions instead of closing the notch.
    @State private var scrollSuppressionToken = UUID()
    @State private var isSuppressingScroll = false

    var body: some View {
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
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundStyle(claudeColor)
            Text("Agents")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            if let usage = agentMonitor.usage, !usage.isEmpty {
                usageBadges(usage)
            } else if !agentMonitor.isBridgeReady {
                Text("Connecting…")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
        }
    }

    @ViewBuilder
    private func usageBadges(_ usage: ClaudeUsageSnapshot) -> some View {
        HStack(spacing: 6) {
            if let five = usage.fiveHour {
                usageBadge(title: "5h", window: five)
            }
            if let week = usage.sevenDay {
                usageBadge(title: "7d", window: week)
            }
        }
    }

    private func usageBadge(title: String, window: ClaudeUsageWindow) -> some View {
        let warn = window.usedPercentage >= 80
        return Text("\(title) \(window.roundedUsedPercentage)%")
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(warn ? .orange : .gray)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .help("Claude \(title == "5h" ? "5-hour" : "7-day") limit used")
    }

    @ViewBuilder
    private var content: some View {
        if agentMonitor.sessions.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(agentMonitor.sessions) { session in
                        AgentSessionRow(session: session, accent: claudeColor)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            switch agentMonitor.hookStatus {
            case .installed, .unknown:
                Image(systemName: "moon.zzz")
                    .font(.title2)
                    .foregroundStyle(.gray)
                Text("No active Claude sessions")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                Text("Start `claude` in a terminal to see it here.")
                    .font(.caption2)
                    .foregroundStyle(.gray.opacity(0.7))
            case .notInstalled:
                Image(systemName: "wrench.and.screwdriver")
                    .font(.title2)
                    .foregroundStyle(claudeColor)
                Text("Set up Claude Code")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Install hooks so VibeIsland can track your Claude sessions.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.gray)
                Button {
                    agentMonitor.installHooks()
                } label: {
                    Text("Install hooks")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(claudeColor.opacity(0.85)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// A single session row: status glyph, title/summary, and contextual actions.
private struct AgentSessionRow: View {
    let session: AgentSession
    let accent: Color
    @ObservedObject private var agentMonitor = AgentMonitorManager.shared

    var body: some View {
        let halo = agentMonitor.haloState(for: session)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HaloRingView(state: halo, size: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title.isEmpty ? "Claude session" : session.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(halo.label)
                        .font(.system(size: 9))
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
                            .foregroundStyle(.gray)
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
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
    }

    @ViewBuilder
    private func permissionActions(_ permission: PermissionRequest) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !permission.summary.isEmpty {
                Text(permission.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Button {
                    agentMonitor.resolvePermission(sessionID: session.id, approved: true)
                } label: {
                    Text(permission.primaryActionTitle.isEmpty ? "Allow" : permission.primaryActionTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.green.opacity(0.8)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Button {
                    agentMonitor.resolvePermission(sessionID: session.id, approved: false)
                } label: {
                    Text(permission.secondaryActionTitle.isEmpty ? "Deny" : permission.secondaryActionTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.red.opacity(0.7)))
                        .foregroundStyle(.white)
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
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
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
            HStack(spacing: 6) {
                Text("\(index + 1)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(Color.white.opacity(0.15)))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if allowsFreeform {
                    Image(systemName: "pencil").font(.system(size: 9)).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Capsule().fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }
}
