/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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

import AppKit
import OpenIslandCore

/// Global keyboard shortcuts for the agent approve/ask overlay, so the user can
/// decide without leaving the terminal:
/// - ⌘Y / ⌘N approve / deny a pending permission request
/// - ⌘1…⌘9 pick an option for a pending question
///
/// Only acts when a session is actually awaiting input. The local monitor can
/// swallow the event (when the notch is key); the global monitor observes keys
/// while another app is focused (requires Accessibility permission, which the
/// app already uses for HUD interception).
@MainActor
final class AgentInputHotkeyMonitor {
    static let shared = AgentInputHotkeyMonitor()

    private var localMonitor: Any?
    private var globalMonitor: Any?

    private init() {}

    func start() {
        guard localMonitor == nil, globalMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handle(event) == true { return nil }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handle(event)
        }
    }

    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        let manager = AgentMonitorManager.shared
        guard let pending = manager.pendingInputSession else { return false }
        guard let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else { return false }

        if pending.permissionRequest != nil {
            switch key {
            case "y":
                manager.resolvePermission(sessionID: pending.id, approved: true)
                return true
            case "n":
                manager.resolvePermission(sessionID: pending.id, approved: false)
                return true
            default:
                return false
            }
        }

        if let prompt = pending.questionPrompt, let index = Int(key), index >= 1 {
            let labels = optionLabels(prompt)
            guard index <= labels.count else { return false }
            manager.answerQuestion(sessionID: pending.id, optionLabel: labels[index - 1])
            return true
        }

        return false
    }

    private func optionLabels(_ prompt: QuestionPrompt) -> [String] {
        if let first = prompt.questions.first, !first.options.isEmpty {
            return first.options.map(\.label)
        }
        return prompt.options
    }
}
