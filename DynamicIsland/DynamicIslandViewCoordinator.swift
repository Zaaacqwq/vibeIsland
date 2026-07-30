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

import Combine
import Defaults
import SwiftUI

enum SneakContentType: Equatable {
    case brightness
    case volume
    case backlight
    case music
    case mic
    case battery
    case download
    case timer
    case reminder
    case recording
    case doNotDisturb
    case bluetoothAudio
    case privacy
    case capsLock
    case notification
    case inputSource
}

extension SneakContentType {
    /// True for peeks that report a momentary change to a system setting — a level
    /// or a state that the user just toggled, with nothing to read afterwards.
    ///
    /// These render inside the open notch's header rather than replacing it; see
    /// `sneakPeek.showsInsideOpenNotchHeader`. Exhaustive on purpose: a new peek
    /// type has to declare which side it falls on rather than inheriting a default
    /// and looking broken when the notch happens to be open.
    var isMomentarySystemHUD: Bool {
        switch self {
        case .volume, .brightness, .backlight, .capsLock, .inputSource, .mic:
            return true
        case .bluetoothAudio:
            // Depends on the payload, not the type — resolved by
            // `sneakPeek.showsInsideOpenNotchHeader`.
            return false
        case .music, .battery, .download, .timer, .reminder, .recording,
             .doNotDisturb, .privacy, .notification:
            return false
        }
    }

    static func == (lhs: SneakContentType, rhs: SneakContentType) -> Bool {
        switch (lhs, rhs) {
        case (.brightness, .brightness),
             (.volume, .volume),
             (.backlight, .backlight),
             (.music, .music),
             (.mic, .mic),
             (.battery, .battery),
             (.download, .download),
             (.timer, .timer),
             (.reminder, .reminder),
             (.recording, .recording),
             (.doNotDisturb, .doNotDisturb),
             (.bluetoothAudio, .bluetoothAudio),
             (.privacy, .privacy),
             (.capsLock, .capsLock),
             (.notification, .notification),
             (.inputSource, .inputSource):
            return true
        default:
            return false
        }
    }
}

struct sneakPeek {
    var show: Bool = false
    var type: SneakContentType = .music
    var value: CGFloat = 0
    var icon: String = ""
    var title: String = ""
    var subtitle: String = ""
    var accentColor: Color?
    var styleOverride: SneakPeekStyle? = nil
    var targetScreenName: String? = nil

    /// Whether the **open** notch shows this peek as a compact widget inside its
    /// header (`HeaderSystemHUD`) instead of letting it take over the header slot.
    ///
    /// Taking the slot swaps the tab row for the much taller `InlineHUD`, which
    /// inflates the whole notch and strands the glyph at the leading edge. That is
    /// right for rich, durable content (music, battery, timers, notifications) and
    /// wrong for a momentary system-setting HUD — those belong in the header, the
    /// way volume and brightness already did.
    ///
    /// The single source of truth for that split: `ContentView` decides whether to
    /// yield the header slot and `DynamicIslandHeader` decides whether to draw the
    /// widget, and the two lists used to be maintained separately.
    var showsInsideOpenNotchHeader: Bool {
        // `.bluetoothAudio` carries two very different things: a listening-mode
        // change (a momentary HUD) and device connect/disconnect (rich content,
        // which keeps its own row).
        if type == .bluetoothAudio { return isAirPodsListeningMode }
        return type.isMomentarySystemHUD
    }

    /// An AirPods listening-mode change: `.bluetoothAudio` with a negative value
    /// (there is no level to show) and an icon that names the mode.
    var isAirPodsListeningMode: Bool {
        type == .bluetoothAudio
            && value < 0
            && AirPodsListeningMode.fromHUDSymbol(icon) != nil
    }
}

enum BrowserType {
    case chromium
    case safari
}

struct ExpandedItem {
    var show: Bool = false
    var type: SneakContentType = .battery
    var value: CGFloat = 0
    var browser: BrowserType = .chromium
    var autoHideDuration: TimeInterval? = nil
}

class DynamicIslandViewCoordinator: ObservableObject {
    static let shared = DynamicIslandViewCoordinator()
    private var cancellables = Set<AnyCancellable>()
    private var hoverOpenSuppressedUntil: Date = .distantPast
    
    /// Slide direction is derived from the user's order, so dragging a tab to a
    /// new position also changes which way switching to it animates.
    private static var tabOrder: [NotchViews] { NotchTabOrder.current }

    /// Direction of the most recent tab switch (true = forward/right, false = backward/left)
    @Published var tabSwitchForward: Bool = true

    /// A utility tool whose header popover something outside the header asked to
    /// open — currently the global hotkeys. The popover is anchored to a button
    /// that only exists while the notch is open, so the request is parked here
    /// and `DynamicIslandHeader` consumes it once its buttons are on screen.
    @Published var requestedToolPopover: NotchViews?

    @Published var currentView: NotchViews = .home {
        didSet {
            if Defaults[.enableMinimalisticUI] && currentView != .home {
                currentView = .home
                return
            }
            // Track direction before SwiftUI re-renders
            let oldIdx = Self.tabOrder.firstIndex(of: oldValue) ?? 0
            let newIdx = Self.tabOrder.firstIndex(of: currentView) ?? 0
            tabSwitchForward = newIdx >= oldIdx
        }
    }

    /// The notch tabs currently visible, in display order. Same source as the row
    /// itself (`NotchTabOrder`) — this used to be a hand-mirrored copy of the tab
    /// list, which is exactly the kind of duplication a user-defined order breaks.
    /// Used by the horizontal swipe-to-switch gesture.
    private func orderedVisibleTabs() -> [NotchViews] {
        NotchTabOrder.visibleTabs()
    }

    /// Move to the next (`forward`) or previous visible tab. Clamps at the ends.
    func navigateToAdjacentTab(forward: Bool) {
        let tabs = orderedVisibleTabs()
        guard tabs.count > 1 else { return }
        guard let idx = tabs.firstIndex(of: currentView) else {
            withAnimation(.smooth) { currentView = tabs.first ?? .home }
            return
        }
        let nextIdx = forward ? idx + 1 : idx - 1
        guard nextIdx >= 0, nextIdx < tabs.count else { return }
        withAnimation(.smooth) { currentView = tabs[nextIdx] }
    }

    @AppStorage("firstLaunch") var firstLaunch: Bool = true
    @AppStorage("showWhatsNew") var showWhatsNew: Bool = true
    @AppStorage("musicLiveActivityEnabled") var musicLiveActivityEnabled: Bool = true
    @AppStorage("timerLiveActivityEnabled") var timerLiveActivityEnabled: Bool = true

    @Default(.enableTimerFeature) private var enableTimerFeature
    @Default(.timerDisplayMode) private var timerDisplayMode
    
    @AppStorage("alwaysShowTabs") var alwaysShowTabs: Bool = true {
        didSet {
            if !alwaysShowTabs {
                openLastTabByDefault = false
                if TrayDrop.shared.isEmpty || !Defaults[.openShelfByDefault] {
                    currentView = .home
                }
            }
        }
    }
    
    @AppStorage("openLastTabByDefault") var openLastTabByDefault: Bool = false {
        didSet {
            if openLastTabByDefault {
                alwaysShowTabs = true
            }
        }
    }
    
    @AppStorage("hudReplacement") var hudReplacement: Bool = true
    
    @AppStorage("preferred_screen_name") var preferredScreen = NSScreen.main?.localizedName ?? "Unknown" {
        didSet {
            selectedScreen = preferredScreen
            NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
        }
    }
    
    @Published var selectedScreen: String = NSScreen.main?.localizedName ?? "Unknown"

    @Published var optionKeyPressed: Bool = true
    
    private init() {
        selectedScreen = preferredScreen
        Defaults.publisher(.timerDisplayMode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.handleTimerDisplayModeChange(change.newValue)
            }
            .store(in: &cancellables)

        Defaults.publisher(.enableTimerFeature)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.handleTimerFeatureToggle(change.newValue)
            }
            .store(in: &cancellables)

        Defaults.publisher(.enableMinimalisticUI)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.handleMinimalisticModeChange(change.newValue)
            }
            .store(in: &cancellables)

        // A utility tool that loses its tab (switched off, or moved to popover
        // mode) must not leave the notch showing a tab that no longer exists.
        Publishers.MergeMany(
            Defaults.publisher(.enableColorPicker).map { _ in NotchViews.colorPicker }.eraseToAnyPublisher(),
            Defaults.publisher(.colorPickerDisplayMode).map { _ in NotchViews.colorPicker }.eraseToAnyPublisher(),
            Defaults.publisher(.enableClipboardManager).map { _ in NotchViews.clipboard }.eraseToAnyPublisher(),
            Defaults.publisher(.clipboardDisplayMode).map { _ in NotchViews.clipboard }.eraseToAnyPublisher()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] tab in
            self?.leaveTabIfNoLongerVisible(tab)
        }
        .store(in: &cancellables)

        // Observe every setting the open-notch width depends on — both the tab
        // row and (via `headerRowMinimumWidth`) the header's trailing side.
        // Collected into an array first: as one big `MergeMany` literal this
        // exceeded what the type checker will solve.
        Publishers.MergeMany(Self.notchWidthAffectingPublishers())
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { _ in
                enforceMinimumNotchWidth()
            }
            .store(in: &cancellables)

        // Enforce minimum width on launch for existing configurations
        enforceMinimumNotchWidth()
    }

    var isHoverOpenSuppressed: Bool {
        Date() < hoverOpenSuppressedUntil
    }

    func suppressHoverOpen(for duration: TimeInterval = 0.35) {
        hoverOpenSuppressedUntil = Date().addingTimeInterval(max(0, duration))
    }

    private func handleTimerDisplayModeChange(_ mode: TimerDisplayMode) {
        guard mode == .popover, currentView == .timer else { return }
        withAnimation(.smooth) {
            currentView = .home
        }
    }

    private func handleTimerFeatureToggle(_ isEnabled: Bool) {
        guard !isEnabled, currentView == .timer else { return }
        withAnimation(.smooth) {
            currentView = .home
        }
    }

    /// Every `Defaults` key the open-notch width is computed from.
    private static func notchWidthAffectingPublishers() -> [AnyPublisher<Void, Never>] {
        var publishers: [AnyPublisher<Void, Never>] = []

        func observe<Value: Defaults.Serializable & Equatable>(_ key: Defaults.Key<Value>) {
            publishers.append(Defaults.publisher(key).map { _ in () }.eraseToAnyPublisher())
        }

        // Tab row
        observe(.showStandardMediaControls)
        observe(.showCalendar)
        observe(.showReminders)
        observe(.dynamicShelf)
        observe(.enableAgentMonitoring)
        observe(.enableNotificationMonitoring)
        observe(.enableWeather)
        observe(.enableSystemMonitor)
        observe(.enableTimerFeature)
        observe(.timerDisplayMode)
        observe(.enableColorPicker)
        observe(.colorPickerDisplayMode)
        observe(.enableClipboardManager)
        observe(.clipboardDisplayMode)
        // Header trailing side
        observe(.showHeaderContextWidgets)
        observe(.homeHeaderStats)
        observe(.settingsIconInNotch)
        observe(.showBatteryIndicator)
        observe(.showRecordingIndicator)
        observe(.showDoNotDisturbIndicator)
        // Tab row
        observe(.showNotchTabTitles)
        // Sizing mode
        observe(.autoNotchWidth)
        observe(.enableMinimalisticUI)

        return publishers
    }

    /// Falls back to Home when `tab` is the current view but is no longer among
    /// the visible tabs.
    private func leaveTabIfNoLongerVisible(_ tab: NotchViews) {
        guard currentView == tab, !orderedVisibleTabs().contains(tab) else { return }
        withAnimation(.smooth) {
            currentView = .home
        }
    }

    private func handleMinimalisticModeChange(_ isEnabled: Bool) {
        guard isEnabled else { return }
        if currentView != .home {
            withAnimation(.smooth) {
                currentView = .home
            }
        }
    }

    func toggleSneakPeek(
        status: Bool,
        type: SneakContentType,
        duration: TimeInterval = 1.5,
        value: CGFloat = 0,
        icon: String = "",
        title: String = "",
        subtitle: String = "",
        accentColor: Color? = nil,
        styleOverride: SneakPeekStyle? = nil,
        onScreen targetScreen: NSScreen? = nil
    ) {
        let resolvedDuration: TimeInterval
        switch type {
        case .timer:
            resolvedDuration = 10
        case .reminder:
            resolvedDuration = Defaults[.reminderSneakPeekDuration]
        default:
            resolvedDuration = duration
        }
        sneakPeekDuration = resolvedDuration
        let bypassedTypes: [SneakContentType] = [.music, .timer, .reminder, .bluetoothAudio, .notification, .inputSource]
        
        if !bypassedTypes.contains(type) && !Defaults[.enableSystemHUD] {
            return
        }
        DispatchQueue.main.async {
            // Single write so `sneakPeek.didSet` (which schedules the auto-hide)
            // fires once, not once per field — the per-field writes raced the hide
            // Task and could wedge `show == true` with no pending hide.
            var updated = self.sneakPeek
            updated.show = status
            updated.type = type
            updated.value = value
            updated.icon = icon
            updated.title = title
            updated.subtitle = subtitle
            updated.accentColor = accentColor
            updated.styleOverride = styleOverride
            updated.targetScreenName = targetScreen?.localizedName
            withAnimation(.smooth(duration: 0.3)) {
                self.sneakPeek = updated
            }
        }
    }
    
    private var sneakPeekDuration: TimeInterval = 1.5
    private var sneakPeekTask: Task<Void, Never>?

    // Helper function to manage sneakPeek timer using Swift Concurrency
    private func scheduleSneakPeekHide(after duration: TimeInterval) {
        sneakPeekTask?.cancel()
        
        // Don't schedule auto-hide if duration is infinite (for persistent indicators like Caps Lock)
        guard duration.isFinite else { return }

        sneakPeekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self = self, !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    // Hide the sneak peek with the correct type that was showing
                    self.toggleSneakPeek(status: false, type: self.sneakPeek.type)
                    self.sneakPeekDuration = 1.5
                }
            }
        }
    }
    
    @Published var sneakPeek: sneakPeek = .init() {
        didSet {
            if sneakPeek.show {
                scheduleSneakPeekHide(after: sneakPeekDuration)
            } else {
                sneakPeekTask?.cancel()
            }
        }
    }
    
    func toggleExpandingView(
        status: Bool,
        type: SneakContentType,
        value: CGFloat = 0,
        browser: BrowserType = .chromium,
        autoHideDuration: TimeInterval? = nil
    ) {
        Task { @MainActor in
            withAnimation(.smooth) {
                self.expandingView.show = status
                self.expandingView.type = type
                self.expandingView.value = value
                self.expandingView.browser = browser
                self.expandingView.autoHideDuration = autoHideDuration
            }
        }
    }

    private var expandingViewTask: Task<Void, Never>?
    
    @Published var expandingView: ExpandedItem = .init() {
        didSet {
            if expandingView.show {
                expandingViewTask?.cancel()
                // Only auto-hide for battery, not for downloads (DownloadManager handles that)
                if expandingView.type != .download {
                    let duration = expandingView.autoHideDuration ?? 3
                    expandingViewTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(duration))
                        guard let self = self, !Task.isCancelled else { return }
                        self.toggleExpandingView(status: false, type: .battery)
                    }
                }
            } else {
                expandingViewTask?.cancel()
            }
        }
    }

    
    func showEmpty() {
        currentView = .home
    }
    
}
