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
import Defaults
import Combine

class SystemHUDManager {
    static let shared = SystemHUDManager()
    
    private var changesObserver: SystemChangesObserver?
    private weak var coordinator: DynamicIslandViewCoordinator?
    private var isSetupComplete = false
    private var isSystemOperationInProgress = false
    
    private init() {
        // Set up observer for settings changes
        setupSettingsObserver()
    }
    
    private func setupSettingsObserver() {
        // Observe Vertical HUD toggle
        Defaults.publisher(.enableVerticalHUD, options: []).sink { [weak self] change in
            guard let self = self, self.isSetupComplete else {
                return
            }
            Task { @MainActor in
                if change.newValue {
                    // Always restart to ensure correct flags are applied
                    await self.startSystemObserver()
                } else if Defaults[.enableSystemHUD] || Defaults[.enableCustomOSD] || Defaults[.enableCircularHUD] {
                    // Restart to apply flags for the remaining active HUD
                    await self.startSystemObserver()
                } else {
                    await self.stopSystemObserver()
                }
            }
        }.store(in: &cancellables)
        
        // Observe master HUD toggle
        Defaults.publisher(.enableSystemHUD, options: []).sink { [weak self] change in
            guard let self = self, self.isSetupComplete else {
                return
            }
            Task { @MainActor in
                if change.newValue && !Defaults[.enableCustomOSD] && !Defaults[.enableVerticalHUD] && !Defaults[.enableCircularHUD] {
                     // Always restart to ensure correct flags are applied
                    await self.startSystemObserver()
                } else if !Defaults[.enableCustomOSD] && !Defaults[.enableVerticalHUD] && !Defaults[.enableCircularHUD] {
                    // Only stop if others are also disabled
                    await self.stopSystemObserver()
                } else if change.newValue == false && (Defaults[.enableCustomOSD] || Defaults[.enableVerticalHUD] || Defaults[.enableCircularHUD]) {
                     // If disabling system HUD but others are active, restart to update flags
                     await self.startSystemObserver()
                }
            }
        }.store(in: &cancellables)
        
        // Observe OSD toggle
        Defaults.publisher(.enableCustomOSD, options: []).sink { [weak self] change in
            guard let self = self, self.isSetupComplete else {
                return
            }
            Task { @MainActor in
                if change.newValue {
                     // Always restart to ensure correct flags are applied
                    await self.startSystemObserver()
                } else if Defaults[.enableSystemHUD] || Defaults[.enableVerticalHUD] || Defaults[.enableCircularHUD] {
                    // Restart to apply flags for the remaining active HUD
                    await self.startSystemObserver()
                } else {
                    await self.stopSystemObserver()
                }
            }
        }.store(in: &cancellables)
        
        // Observe Circular HUD toggle
        Defaults.publisher(.enableCircularHUD, options: []).sink { [weak self] change in
            guard let self = self, self.isSetupComplete else {
                return
            }
            Task { @MainActor in
                if change.newValue {
                     // Always restart to ensure correct flags are applied
                    await self.startSystemObserver()
                } else if Defaults[.enableSystemHUD] || Defaults[.enableCustomOSD] || Defaults[.enableVerticalHUD] {
                    // Restart to apply flags for the remaining active HUD
                    await self.startSystemObserver()
                } else {
                    await self.stopSystemObserver()
                }
            }
        }.store(in: &cancellables)
        
        // Observe individual HUD toggles
        Defaults.publisher(.enableVolumeHUD, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete, self.requiresSystemToggleHandling else {
                return
            }
            let flags = self.resolvedControlFlags()
            self.changesObserver?.update(
                volumeEnabled: flags.volume,
                brightnessEnabled: flags.brightness,
                keyboardBacklightEnabled: flags.backlight
            )
        }.store(in: &cancellables)
        
        Defaults.publisher(.enableBrightnessHUD, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete, self.requiresSystemToggleHandling else {
                return
            }
            let flags = self.resolvedControlFlags()
            self.changesObserver?.update(
                volumeEnabled: flags.volume,
                brightnessEnabled: flags.brightness,
                keyboardBacklightEnabled: flags.backlight
            )
        }.store(in: &cancellables)

        Defaults.publisher(.enableKeyboardBacklightHUD, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete, self.requiresSystemToggleHandling else {
                return
            }
            let flags = self.resolvedControlFlags()
            self.changesObserver?.update(
                volumeEnabled: flags.volume,
                brightnessEnabled: flags.brightness,
                keyboardBacklightEnabled: flags.backlight
            )
        }.store(in: &cancellables)
        
        // Observe individual OSD toggles
        Defaults.publisher(.enableOSDVolume, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete, Defaults[.enableCustomOSD] else {
                return
            }
            let flags = self.resolvedControlFlags()
            self.changesObserver?.update(
                volumeEnabled: flags.volume,
                brightnessEnabled: flags.brightness,
                keyboardBacklightEnabled: flags.backlight
            )
        }.store(in: &cancellables)
        
        Defaults.publisher(.enableOSDBrightness, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete, Defaults[.enableCustomOSD] else {
                return
            }
            let flags = self.resolvedControlFlags()
            self.changesObserver?.update(
                volumeEnabled: flags.volume,
                brightnessEnabled: flags.brightness,
                keyboardBacklightEnabled: flags.backlight
            )
        }.store(in: &cancellables)
        
        Defaults.publisher(.enableOSDKeyboardBacklight, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete, Defaults[.enableCustomOSD] else {
                return
            }
            let flags = self.resolvedControlFlags()
            self.changesObserver?.update(
                volumeEnabled: flags.volume,
                brightnessEnabled: flags.brightness,
                keyboardBacklightEnabled: flags.backlight
            )
        }.store(in: &cancellables)

    }
    
    private var cancellables = Set<AnyCancellable>()

    private var requiresSystemToggleHandling: Bool {
        Defaults[.enableSystemHUD] || Defaults[.enableVerticalHUD] || Defaults[.enableCircularHUD]
    }
    
    /// Public property to check if system operations are in progress
    var isOperationInProgress: Bool {
        return isSystemOperationInProgress
    }
    
    func setup(coordinator: DynamicIslandViewCoordinator) {
        self.coordinator = coordinator

        // Initialize OSD manager
        Task { @MainActor in
            CustomOSDWindowManager.shared.initialize()
        }

        // Start observer if any HUD/OSD is enabled
        if Defaults[.enableSystemHUD] || Defaults[.enableCustomOSD] || Defaults[.enableVerticalHUD] || Defaults[.enableCircularHUD] {
            Task { @MainActor in
                await startSystemObserver()
                self.isSetupComplete = true
            }
        } else {
            isSetupComplete = true
        }
    }
    
    /// Resolves the effective control flags for the active HUD/OSD style.
    private func resolvedControlFlags() -> (volume: Bool, brightness: Bool, backlight: Bool) {
        if Defaults[.enableCustomOSD] && !(Defaults[.enableCircularHUD] || Defaults[.enableVerticalHUD]) {
            return (Defaults[.enableOSDVolume], Defaults[.enableOSDBrightness], Defaults[.enableOSDKeyboardBacklight])
        }
        return (Defaults[.enableVolumeHUD], Defaults[.enableBrightnessHUD], Defaults[.enableKeyboardBacklightHUD])
    }

    @MainActor
    private func startSystemObserver() async {
        guard let coordinator = coordinator, !isSystemOperationInProgress else { return }
        
        isSystemOperationInProgress = true

        // Stop any existing observer directly (cannot call stopSystemObserver()
        // because isSystemOperationInProgress is already true).
        changesObserver?.stopObserving()
        changesObserver = nil
        
        changesObserver = SystemChangesObserver(coordinator: coordinator)

        let flags = resolvedControlFlags()
        changesObserver?.startObserving(
            volumeEnabled: flags.volume,
            brightnessEnabled: flags.brightness,
            keyboardBacklightEnabled: flags.backlight
        )
        
        // Force disable system HUD to ensure no duplicates
        SystemOSDManager.disableSystemHUD()
        
        print("System observer started (HUD: \(Defaults[.enableSystemHUD]), OSD: \(Defaults[.enableCustomOSD]), Vertical: \(Defaults[.enableVerticalHUD]))")
        isSystemOperationInProgress = false
    }
    
    @MainActor
    private func stopSystemObserver() async {
        guard !isSystemOperationInProgress else { return }
        
        isSystemOperationInProgress = true
        changesObserver?.stopObserving()
        changesObserver = nil
        
        // Re-enable system HUD when we stop observing
        SystemOSDManager.enableSystemHUD()
        
        print("System observer stopped")
        isSystemOperationInProgress = false
    }
    
    deinit {
        cancellables.removeAll()
        Task { @MainActor in
            await stopSystemObserver()
        }
    }
}