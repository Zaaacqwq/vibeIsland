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

import AppKit
import CoreGraphics
import OpenIslandCore

/// Global keyboard shortcuts for the agent approve/ask overlay, so the user can
/// decide without leaving the terminal:
/// - ⌘Y / ⌘N approve / deny a pending permission request
/// - ⌘1…⌘9 pick an option for a pending question
///
/// Uses a `CGEventTap` (not an `NSEvent` monitor) so that, *while a session is
/// awaiting input*, these chords are **consumed** and never reach the focused
/// app — otherwise ⌘Y etc. would fire that app's own shortcut. When nothing is
/// pending, every key is passed through untouched. Requires Accessibility
/// permission (already used for HUD interception).
@MainActor
final class AgentInputHotkeyMonitor {
    static let shared = AgentInputHotkeyMonitor()

    private var runLoopSource: CFRunLoopSource?

    /// Read from the event-tap callback (runs on the main run loop). Updated
    /// whenever the agent session list changes.
    nonisolated(unsafe) private var tapPort: CFMachPort?
    nonisolated(unsafe) private var hasPendingPermission = false
    nonisolated(unsafe) private var hasPendingQuestion = false

    private init() {}

    func start() {
        guard tapPort == nil else { return }

        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let callback: CGEventTapCallBack = { _, type, cgEvent, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(cgEvent) }
            let monitor = Unmanaged<AgentInputHotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handle(cgEvent: cgEvent, type: type)
        }

        var created: CFMachPort?
        for location in [CGEventTapLocation.cgSessionEventTap, .cghidEventTap] {
            if let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            ) {
                created = tap
                break
            }
        }

        guard let tap = created else {
            NSLog("⚠️ AgentInputHotkeyMonitor: could not create event tap (Accessibility permission?)")
            return
        }

        tapPort = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = tapPort {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tapPort = nil
        runLoopSource = nil
        hasPendingPermission = false
        hasPendingQuestion = false
    }

    /// Refresh the cached pending-input flags. Called when the session list changes.
    func updatePendingState() {
        let pending = AgentMonitorManager.shared.pendingInputSession
        hasPendingPermission = pending?.permissionRequest != nil
        hasPendingQuestion = pending?.questionPrompt != nil
    }

    // MARK: - Event tap callback (main run loop)

    nonisolated private func handle(cgEvent: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
            return Unmanaged.passUnretained(cgEvent)
        }

        let passthrough = Unmanaged.passUnretained(cgEvent)
        guard type == .keyDown, hasPendingPermission || hasPendingQuestion else { return passthrough }
        guard let nsEvent = NSEvent(cgEvent: cgEvent),
              nsEvent.modifierFlags.contains(.command),
              let key = nsEvent.charactersIgnoringModifiers?.lowercased(),
              !key.isEmpty else { return passthrough }

        if hasPendingPermission, key == "y" || key == "n" {
            let approve = key == "y"
            Task { @MainActor in self.resolvePermission(approve: approve) }
            return nil // consume — don't let the focused app see ⌘Y/⌘N
        }

        if hasPendingQuestion, let index = Int(key), index >= 1, index <= 9 {
            Task { @MainActor in self.answerQuestion(index: index) }
            return nil // consume — don't let the focused app see ⌘<n>
        }

        return passthrough
    }

    // MARK: - Actions (main actor)

    private func resolvePermission(approve: Bool) {
        let manager = AgentMonitorManager.shared
        guard let pending = manager.pendingInputSession, pending.permissionRequest != nil else { return }
        manager.resolvePermission(sessionID: pending.id, approved: approve)
    }

    private func answerQuestion(index: Int) {
        let manager = AgentMonitorManager.shared
        guard let pending = manager.pendingInputSession, let prompt = pending.questionPrompt else { return }
        let options = questionOptions(prompt)
        guard index <= options.count else { return }
        let option = options[index - 1]
        if option.allowsFreeform {
            // Freeform needs typed input — ask the overlay to open text entry.
            manager.requestedFreeformOptionID = option.id
            return
        }
        manager.answerQuestion(sessionID: pending.id, optionLabel: option.label)
    }

    private func questionOptions(_ prompt: QuestionPrompt) -> [QuestionOption] {
        if let first = prompt.questions.first, !first.options.isEmpty {
            return first.options
        }
        return prompt.options.map { QuestionOption(label: $0) }
    }
}
