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

/// Ensures only one VibeIsland process runs at a time.
///
/// On reboot macOS can launch the app twice — once from the registered login
/// item (`LaunchAtLogin`/`SMAppService`) and once from "Reopen windows when
/// logging back in" state restoration. Nothing in the app deduplicated those,
/// so two pills appeared. This guard makes the second (and later) launch step
/// aside in favor of the one already running.
///
/// The in-app "Restart VibeIsland" command intentionally spawns a fresh
/// instance while the current one is still alive, so it passes
/// ``restartArgument`` to exempt that launch from the guard.
enum SingleInstanceGuard {
    /// Launch argument that marks an instance as an intentional restart and
    /// therefore exempt from the single-instance check.
    static let restartArgument = "--vibeisland-restart"

    /// Returns `true` when another instance with the same bundle identifier is
    /// already running and this instance should terminate. As a side effect it
    /// activates the surviving instance and calls `NSApp.terminate` before
    /// returning `true`, so the caller can simply `return`.
    static func shouldTerminateForExistingInstance() -> Bool {
        // An intentional restart is allowed to coexist briefly with the
        // outgoing instance; never terminate it.
        guard !ProcessInfo.processInfo.arguments.contains(restartArgument) else {
            return false
        }

        guard let bundleID = Bundle.main.bundleIdentifier else {
            return false
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ownPID && !$0.isTerminated }

        guard let existing = others.first else {
            return false
        }

        existing.activate()
        NSApp.terminate(nil)
        return true
    }
}
