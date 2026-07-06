/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for VibeIsland (DynamicIsland)
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
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import ApplicationServices
import ApplicationServices
import Defaults
import MacroVisionKit
import SwiftUI

class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()
    private let detector: MacroVisionKit
    @ObservedObject private var musicManager = MusicManager.shared
    @MainActor @Published private(set) var fullscreenStatus: [String: Bool] = [:]
    private var notificationTask: Task<Void, Never>?

    private init() {
        self.detector = MacroVisionKit.shared
        detector.configuration.includeSystemApps = true
        setupNotificationObservers()
        updateFullScreenStatus()
    }

    private func setupNotificationObservers() {
        notificationTask = Task { @Sendable [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    let activeSpaceNotifications = NSWorkspace.shared.notificationCenter.notifications(
                        named: NSWorkspace.activeSpaceDidChangeNotification
                    )
                    
                    for await _ in activeSpaceNotifications {
                        await self?.handleChange()
                    }
                }
                
                group.addTask {
                    let screenParameterNotifications = NSWorkspace.shared.notificationCenter.notifications(
                        named:  NSApplication.didChangeScreenParametersNotification
                    )
                    
                    for await _ in screenParameterNotifications {
                        await  self?.handleChange()
                    }
                }
            }
        }
    }

    private func handleChange() async {
        try? await Task.sleep(for: .milliseconds(500))
        self.updateFullScreenStatus()
    }

    private func updateFullScreenStatus() {
        guard Defaults[.enableFullscreenMediaDetection] else {
            let reset = Dictionary(uniqueKeysWithValues: NSScreen.screens.map { ($0.localizedName, false) })
            if reset != fullscreenStatus {
                fullscreenStatus = reset
            }
            return
        }
        

        let apps = detector.detectFullscreenApps(debug: false)
        let names = NSScreen.screens.map { $0.localizedName }
        let hideOption = Defaults[.hideNotchOption]

        var newStatus: [String: Bool] = [:]
        for name in names {
            newStatus[name] = apps.contains { app in
                guard app.screen.localizedName == name,
                      app.bundleIdentifier != "com.apple.finder" else { return false }

                switch hideOption {
                case .always:
                    return isInNativeFullscreen(app)
                case .nowPlayingOnly:
                    return app.bundleIdentifier == musicManager.bundleIdentifier
                        && isInNativeFullscreen(app)
                case .never:
                    return false
                }
            }
        }

        if newStatus != fullscreenStatus {
            fullscreenStatus = newStatus
            NSLog("✅ Fullscreen status: \(newStatus)")
        }
    }

    /// Confirms an app flagged as screen-filling is in genuine native
    /// fullscreen, not merely maximized/zoomed. When Accessibility is not
    /// trusted, keep the detector's frame-based behavior as a fallback.
    private func isInNativeFullscreen(_ app: MacroVisionKit.FullscreenWindowInfo) -> Bool {
        guard AXIsProcessTrusted() else { return true }

        let appElement = AXUIElementCreateApplication(app.processId)

        if let focused: AXUIElement = copyAttribute(kAXFocusedWindowAttribute as CFString, from: appElement),
           isWindowFullscreen(focused) {
            return true
        }

        if let windows: [AXUIElement] = copyAttribute(kAXWindowsAttribute as CFString, from: appElement) {
            return windows.contains { isWindowFullscreen($0) }
        }

        return false
    }

    private func isWindowFullscreen(_ window: AXUIElement) -> Bool {
        let value: Bool? = copyAttribute("AXFullScreen" as CFString, from: window)
        return value ?? false
    }

    private func copyAttribute<T>(_ attribute: CFString, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let typed = value as? T else { return nil }
        return typed
    }

    private func cleanupNotificationObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
