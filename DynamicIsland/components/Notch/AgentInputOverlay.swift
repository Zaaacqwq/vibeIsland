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

    private enum Palette {
        static let orange = Color(red: 1.0, green: 0.56, blue: 0.22)
        static let teal = Color(red: 0.18, green: 0.7, blue: 0.9)
        static let muted = Color(white: 0.66)
    }

    var body: some View {
        Group {
            if let permission = session.permissionRequest {
                permissionCard(permission)
            } else if let question = session.questionPrompt {
                questionCard(question)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .onChange(of: agentMonitor.requestedFreeformOptionID) { _, id in
            defer { agentMonitor.requestedFreeformOptionID = nil }
            guard let id, let prompt = session.questionPrompt,
                  let option = questionOptions(prompt).first(where: { $0.id == id }) else { return }
            freeformText = ""
            freeformOption = option
            focusInput()
        }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(Palette.orange).frame(width: 8, height: 8)
                Text("Permission Request")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.orange)
                Text(permission.title.isEmpty ? "Tool use" : permission.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.orange)
                if !permission.affectedPath.isEmpty, permission.affectedPath != permission.title {
                    Text(permission.affectedPath)
                        .font(.system(size: 16, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }

            if !permission.summary.isEmpty {
                DiffView(text: permission.summary)
                    .frame(maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                actionButton(title: permission.secondaryActionTitle.isEmpty ? "Deny" : permission.secondaryActionTitle,
                             shortcut: "⌘N",
                             foreground: .white,
                             background: Color.white.opacity(0.12)) {
                    agentMonitor.resolvePermission(sessionID: session.id, approved: false)
                }
                actionButton(title: permission.primaryActionTitle.isEmpty ? "Allow" : permission.primaryActionTitle,
                             shortcut: "⌘Y",
                             foreground: .black,
                             background: Color.white.opacity(0.92)) {
                    agentMonitor.resolvePermission(sessionID: session.id, approved: true)
                }
            }
        }
    }

    private func actionButton(title: String, shortcut: String, foreground: Color, background: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(shortcut).font(.system(size: 12, weight: .medium)).opacity(0.6)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(background))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Question

    @ViewBuilder
    private func questionCard(_ prompt: QuestionPrompt) -> some View {
        let options = questionOptions(prompt)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.teal)
                Text("Claude asks")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.teal)
            }

            Text(questionText(prompt))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let editing = freeformOption {
                freeformEntry(editing)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        optionButton(index: index, option: option)
                    }
                }
            }
            Spacer(minLength: 0)
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
            HStack(spacing: 10) {
                HStack(spacing: 1) {
                    Image(systemName: "command").font(.system(size: 9, weight: .bold))
                    Text("\(index + 1)").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Palette.teal)
                .frame(width: 32, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.teal.opacity(0.18)))

                Text(option.label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if option.allowsFreeform {
                    Image(systemName: "pencil").font(.system(size: 11)).foregroundStyle(Palette.teal)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.teal.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func freeformEntry(_ option: QuestionOption) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(option.label.isEmpty ? "Type your answer…" : option.label, text: $freeformText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(Palette.teal)
                .focused($inputFocused)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.teal.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Palette.teal.opacity(0.4), lineWidth: 1))
                .onSubmit { submitFreeform() }
                .onAppear { focusInput() }

            HStack(spacing: 8) {
                Button { freeformOption = nil } label: {
                    Text("Back")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                Button { submitFreeform() } label: {
                    Text("Submit")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.92)))
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
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(color(for: line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1.5)
                            .background(background(for: line))
                    }
                }
                .padding(.vertical, 4)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if adds > 0 || removes > 0 {
                Text("+\(adds) -\(removes)")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(white: 0.5))
                    .padding(.leading, 2)
            }
        }
    }

    private func color(for line: String) -> Color {
        if line.hasPrefix("+") { return Color(red: 0.45, green: 0.85, blue: 0.52) }
        if line.hasPrefix("-") { return Color(red: 0.95, green: 0.45, blue: 0.45) }
        return Color(white: 0.78)
    }

    private func background(for line: String) -> Color {
        if line.hasPrefix("+") { return Color.green.opacity(0.10) }
        if line.hasPrefix("-") { return Color.red.opacity(0.12) }
        return .clear
    }
}
