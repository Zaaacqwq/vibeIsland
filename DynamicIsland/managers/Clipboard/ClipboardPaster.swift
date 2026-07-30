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
import Defaults
import Foundation
import os.log

/// Writes history entries back to the system pasteboard, and optionally
/// synthesizes ⌘V into the app the user came from.
@MainActor
final class ClipboardPaster: ObservableObject {
    static let shared = ClipboardPaster()

    /// The last app that was frontmost other than us. Opening the notch or its
    /// popover makes VibeIsland frontmost, so this is the app a paste has to be
    /// aimed back at.
    private(set) var lastExternalApp: NSRunningApplication?

    private let pasteboard = NSPasteboard.general
    private let store = ClipboardStore.shared
    private let log = os.Logger(subsystem: "com.zaaacqwq.VibeIsland", category: "ClipboardPaster")

    /// `kVK_ANSI_V`. Hardcoded rather than resolved per keyboard layout, so a
    /// non-QWERTY layout that moves V will paste the wrong key — the trade-off
    /// for not pulling in a keycode-mapping dependency.
    private let virtualKeyV: CGKeyCode = 0x09

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            MainActor.assumeIsolated {
                self?.lastExternalApp = app
            }
        }
    }

    // MARK: - Copy

    /// Puts an entry back on the pasteboard.
    /// - Parameter removeFormatting: keeps only the plain-text representation.
    func copy(_ item: ClipboardItem, removeFormatting: Bool = false) async {
        var values = await store.values(for: item)
        guard !values.isEmpty else {
            log.error("Clipboard entry has no readable payload; refusing to write an empty pasteboard")
            return
        }

        if removeFormatting {
            values.removeAll { ClipboardPasteboard.formattingTypes.contains($0.type) }
            guard !values.isEmpty else { return }
        }

        let fileURLType = NSPasteboard.PasteboardType.fileURL.rawValue
        pasteboard.clearContents()

        for value in values where value.type != fileURLType {
            pasteboard.setData(value.data, forType: NSPasteboard.PasteboardType(value.type))
        }

        // File URLs go through `writeObjects` as one item each; setting them as
        // raw data collapses a multi-file copy down to a single file.
        if let fileValue = values.first(where: { $0.type == fileURLType }),
           let joined = String(data: fileValue.data, encoding: .utf8) {
            let fileItems: [NSPasteboardItem] = joined
                .split(separator: "\n")
                .map { urlString in
                    let pasteboardItem = NSPasteboardItem()
                    pasteboardItem.setData(Data(urlString.utf8), forType: .fileURL)
                    return pasteboardItem
                }
            if !fileItems.isEmpty {
                pasteboard.writeObjects(fileItems)
            }
        }

        // Marks the write as ours so the monitor's next poll recognizes its own
        // echo instead of recording a duplicate entry.
        pasteboard.setString("", forType: ClipboardPasteboard.clipboardManagerMarker)

        ClipboardMonitor.shared.noteReuse(of: item)
    }

    /// Copies, then pastes if the user has asked for automatic pasting.
    func use(_ item: ClipboardItem, removeFormatting: Bool = false, forcePaste: Bool = false) async {
        await copy(item, removeFormatting: removeFormatting)
        guard forcePaste || Defaults[.clipboardPasteAutomatically] else { return }
        await paste()
    }

    // MARK: - Paste

    /// Synthesizes ⌘V into ``lastExternalApp``.
    ///
    /// Returns without acting when Accessibility is not granted — a synthetic
    /// key event from an untrusted process is silently dropped, which would look
    /// like the feature simply not working.
    @discardableResult
    func paste() async -> Bool {
        guard AccessibilityPermissionStore.shared.isAuthorized else {
            AccessibilityPermissionStore.shared.requestAuthorizationPrompt()
            return false
        }

        // The paste has to land in the app the user was in, not in ours.
        if let target = lastExternalApp, !target.isActive {
            target.activate()
            // Activation crosses the WindowServer asynchronously; posting the
            // key event before the handoff lands types into the wrong app.
            try? await Task.sleep(for: .milliseconds(120))
        }

        postCommandV()
        return true
    }

    private func postCommandV() {
        // The extra 0x000008 bit marks a left/right modifier as physically
        // pressed. Without it some apps ignore the synthetic ⌘ entirely.
        let commandFlag = CGEventFlags(rawValue: UInt64(NSEvent.ModifierFlags.command.rawValue) | 0x000008)

        let source = CGEventSource(stateID: .combinedSessionState)
        // Keeps the user's own keystrokes from interleaving with the synthetic
        // pair while it is in flight.
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: false) else {
            log.error("Failed to create synthetic ⌘V events")
            return
        }

        keyDown.flags = commandFlag
        keyUp.flags = commandFlag
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}
