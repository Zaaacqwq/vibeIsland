/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit

/// Relaunches the exact bundle that is currently running.
///
/// Resolving the app through LaunchServices can start a stale copy from
/// /Applications while developing. Opening `Bundle.main.bundleURL` preserves
/// the running build, and the restart argument lets the new process pass the
/// single-instance guard while this one is shutting down.
@MainActor
enum AppRelauncher {
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [SingleInstanceGuard.restartArgument]

        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            guard error == nil else {
                NSSound.beep()
                return
            }
            Task { @MainActor in
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
