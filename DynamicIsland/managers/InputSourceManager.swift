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

import Foundation
import Combine
import AppKit
import Carbon.HIToolbox
import Defaults
import SwiftUI

/// Watches the active keyboard input source (输入法) and shows a brief notch HUD
/// whenever the user switches, mirroring the Caps Lock indicator behavior.
///
/// Unlike Caps Lock there is no persistent on/off state to hold — a switch is a
/// transient event, so we simply fire a finite-duration sneak peek that
/// auto-dismisses (like Volume/Brightness).
@MainActor
class InputSourceManager: ObservableObject {
    static let shared = InputSourceManager()

    /// Localized name of the currently selected input source, e.g. "Pinyin", "ABC".
    @Published var currentSourceName: String = ""

    private let coordinator = DynamicIslandViewCoordinator.shared
    private var didReceiveInitialChange = false

    private init() {
        currentSourceName = Self.readCurrentSourceName()

        // TIS posts this to the distributed center whenever the selected
        // keyboard input source changes — no accessibility permission needed.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceDidChange),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )

        print("InputSourceManager: ✅ Initialized with input source \"\(currentSourceName)\"")
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func inputSourceDidChange() {
        // The distributed notification may arrive off the main thread.
        Task { @MainActor in
            let newName = Self.readCurrentSourceName()

            guard newName != self.currentSourceName else { return }
            self.currentSourceName = newName

            // Swallow the very first change fired during app launch so we don't
            // flash the HUD on startup.
            guard self.didReceiveInitialChange else {
                self.didReceiveInitialChange = true
                return
            }

            print("InputSourceManager: Input source switched to \"\(newName)\"")

            guard Defaults[.enableInputSourceIndicator] else { return }
            guard !newName.isEmpty else { return }

            self.coordinator.toggleSneakPeek(
                status: true,
                type: .inputSource,
                duration: 1.5,
                icon: "keyboard"
            )
        }
    }

    /// Reads the localized name of the current keyboard input source via TIS.
    private static func readCurrentSourceName() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return ""
        }
        guard let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
            return ""
        }
        let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue()
        return name as String
    }
}
