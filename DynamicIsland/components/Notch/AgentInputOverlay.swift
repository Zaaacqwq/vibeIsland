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

import OpenIslandCore
import SwiftUI

/// Focused approve / ask overlay shown in the open notch when a Claude session
/// needs a decision. Permission requests show the tool, an optional diff, and
/// Deny/Allow; questions show selectable options. Keyboard handling (⌘Y/⌘N,
/// ⌘1…9) lives in the global hotkey monitor.
struct AgentInputOverlay: View {
    let session: AgentSession
    @ObservedObject private var agentMonitor = AgentMonitorManager.shared
    @State private var freeformOption: QuestionOption?
    @State private var freeformText: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        Group {
            if let permission = session.permissionRequest {
                permissionCard(permission)
            } else if let question = session.questionPrompt {
                questionCard(question)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .overlay(alignment: .topTrailing) { collapseButton }
        // Apply on appear too, so opening straight into a freeform option (from a
        // collapsed agent row) mounts already in text-entry mode (no flicker).
        .onAppear { applyRequestedFreeformOption(agentMonitor.requestedFreeformOptionID) }
        .onChange(of: agentMonitor.requestedFreeformOptionID) { _, id in
            applyRequestedFreeformOption(id)
        }
    }

    private func applyRequestedFreeformOption(_ id: UUID?) {
        defer { agentMonitor.requestedFreeformOptionID = nil }
        guard let id, let prompt = session.questionPrompt,
              let option = questionOptions(prompt).first(where: { $0.id == id }) else { return }
        freeformText = ""
        freeformOption = option
        focusInput()
    }

    /// Collapse without answering — the request stays pending and is reopenable
    /// from its agent row.
    private var collapseButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) { agentMonitor.collapseActiveInput() }
        } label: {
            Image(systemName: "chevron.up")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchDesign.Colors.textSecondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .padding(.trailing, 6)
        .help("Collapse — reopen from the agent row")
    }

    /// Bring the notch forward and focus the freeform text field so the user can
    /// type immediately (the panel needs key focus to receive keystrokes).
    private func focusInput() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0 is DynamicIslandWindow }?.makeKeyAndOrderFront(nil)
            inputFocused = true
        }
    }

    // MARK: - Permission

    @ViewBuilder
    private func permissionCard(_ permission: PermissionRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // Amber pulsing dot — the handoff's shared "needs permission"
                // signature (same signal as the collapsed pill and the tab row).
                NotchPulsingDot(color: NotchDesign.Colors.warning, size: 8)
                NotchMonoEyebrow(text: "Needs permission")
            }
            .padding(.trailing, 28)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchDesign.Colors.warning)
                Text(permission.title.isEmpty ? "Tool use" : permission.title)
                    .font(NotchDesign.Typography.voice(15, weight: .semibold))
                    .foregroundStyle(NotchDesign.Colors.textPrimary)
                if !permission.affectedPath.isEmpty, permission.affectedPath != permission.title {
                    Text(permission.affectedPath)
                        .font(NotchDesign.Typography.mono(13))
                        .foregroundStyle(NotchDesign.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }

            if !permission.summary.isEmpty {
                // Scroll so long diffs fit the (fixed) tab height without growing
                // the notch — which is what removes the open/close glitch.
                ScrollView(.vertical, showsIndicators: false) {
                    DiffView(text: permission.summary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                permissionButton(title: permission.secondaryActionTitle.isEmpty ? "Deny" : permission.secondaryActionTitle,
                                 shortcut: "⌘N",
                                 kind: .deny) {
                    agentMonitor.resolvePermission(sessionID: session.id, approved: false)
                }
                permissionButton(title: permission.primaryActionTitle.isEmpty ? "Allow" : permission.primaryActionTitle,
                                 shortcut: "⌘Y",
                                 kind: .allow) {
                    agentMonitor.resolvePermission(sessionID: session.id, approved: true)
                }
            }
        }
    }

    private enum PermissionButtonKind { case allow, deny }

    /// Allow = green fill / black text; Deny = red outline — matching the inline
    /// approve/deny grammar in the Agents tab list.
    private func permissionButton(title: String, shortcut: String, kind: PermissionButtonKind, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(NotchDesign.Typography.voice(13, weight: .semibold))
                Text(shortcut).font(NotchDesign.Typography.mono(11)).opacity(0.55)
            }
            .foregroundStyle(kind == .allow ? .black : NotchDesign.Colors.danger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background {
                if kind == .allow {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(NotchDesign.Colors.success)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(NotchDesign.Colors.danger.opacity(0.4), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Question

    @ViewBuilder
    private func questionCard(_ prompt: QuestionPrompt) -> some View {
        let options = questionOptions(prompt)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.bubble")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchDesign.Colors.accent)
                NotchMonoEyebrow(text: "Claude asks")
            }
            .padding(.trailing, 28)

            Text(questionText(prompt))
                .font(NotchDesign.Typography.voice(15, weight: .semibold))
                .foregroundStyle(NotchDesign.Colors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let editing = freeformOption {
                freeformEntry(editing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                            optionButton(index: index, option: option)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func optionButton(index: Int, option: QuestionOption) -> some View {
        Button {
            if option.allowsFreeform {
                freeformText = ""
                freeformOption = option
            } else {
                agentMonitor.answerQuestion(sessionID: session.id, optionLabel: option.label)
            }
        } label: {
            HStack(spacing: 9) {
                // Circular numeral badge — the same option grammar the Agents
                // tab list uses, so an expanded question reads identically.
                Text("\(index + 1)")
                    .font(NotchDesign.Typography.voice(10, weight: .bold))
                    .foregroundStyle(NotchDesign.Colors.textSecondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white.opacity(0.12)))

                Text(option.label)
                    .font(NotchDesign.Typography.voice(13, weight: .medium))
                    .foregroundStyle(NotchDesign.Colors.textPrimary)
                    .lineLimit(1)
                if option.allowsFreeform {
                    Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(NotchDesign.Colors.accent)
                }
                Spacer(minLength: 0)
                // Subtle mono shortcut hint (the ⌘1…9 hotkeys live in the global
                // monitor); only the first nine options have a keyboard binding.
                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(NotchDesign.Typography.mono(10))
                        .foregroundStyle(NotchDesign.Colors.textTertiary)
                }
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .notchCard(radius: 8, fill: NotchDesign.Colors.sunken)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func freeformEntry(_ option: QuestionOption) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(option.label.isEmpty ? "Type your answer…" : option.label, text: $freeformText)
                .textFieldStyle(.plain)
                .font(NotchDesign.Typography.voice(14))
                .foregroundStyle(NotchDesign.Colors.textPrimary)
                .tint(NotchDesign.Colors.accent)
                .focused($inputFocused)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(NotchDesign.Colors.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(NotchDesign.Colors.accent.opacity(0.35), lineWidth: 1))
                .onSubmit { submitFreeform() }
                .onAppear { focusInput() }

            HStack(spacing: 8) {
                Button { freeformOption = nil } label: {
                    Text("Back")
                        .font(NotchDesign.Typography.voice(13, weight: .semibold))
                        .foregroundStyle(NotchDesign.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                Button { submitFreeform() } label: {
                    Text("Submit")
                        .font(NotchDesign.Typography.voice(13, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(NotchDesign.Colors.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(freeformText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(freeformText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
            }
        }
    }

    private func submitFreeform() {
        let answer = freeformText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        agentMonitor.answerQuestion(sessionID: session.id, response: QuestionPromptResponse(answer: answer))
        freeformOption = nil
        freeformText = ""
    }

    private func questionText(_ prompt: QuestionPrompt) -> String {
        if let first = prompt.questions.first, !first.question.isEmpty { return first.question }
        return prompt.title
    }

    private func questionOptions(_ prompt: QuestionPrompt) -> [QuestionOption] {
        if let first = prompt.questions.first, !first.options.isEmpty {
            return first.options
        }
        return prompt.options.map { QuestionOption(label: $0) }
    }
}

/// Renders a unified-diff-ish text block: `+` lines green, `-` lines red, with a
/// trailing add/remove count. Falls back to plain text when there's no diff.
private struct DiffView: View {
    let text: String

    private var lines: [String] { text.components(separatedBy: "\n") }
    private var adds: Int { lines.filter { $0.hasPrefix("+") }.count }
    private var removes: Int { lines.filter { $0.hasPrefix("-") }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(NotchDesign.Typography.mono(11))
                            .foregroundStyle(color(for: line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1.5)
                            .background(background(for: line))
                    }
                }
                .padding(.vertical, 4)
            }
            .background(NotchDesign.Colors.sunken)
            .clipShape(RoundedRectangle(cornerRadius: NotchDesign.Radius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: NotchDesign.Radius.sm, style: .continuous)
                    .strokeBorder(NotchDesign.Colors.hairline, lineWidth: NotchDesign.hairlineWidth)
            }

            if adds > 0 || removes > 0 {
                Text("+\(adds) -\(removes)")
                    .font(NotchDesign.Typography.mono(11))
                    .foregroundStyle(NotchDesign.Colors.textTertiary)
                    .padding(.leading, 2)
            }
        }
    }

    private func color(for line: String) -> Color {
        if line.hasPrefix("+") { return NotchDesign.Colors.success }
        if line.hasPrefix("-") { return NotchDesign.Colors.danger }
        return NotchDesign.Colors.textSecondary
    }

    private func background(for line: String) -> Color {
        if line.hasPrefix("+") { return NotchDesign.Colors.success.opacity(0.10) }
        if line.hasPrefix("-") { return NotchDesign.Colors.danger.opacity(0.12) }
        return .clear
    }
}
