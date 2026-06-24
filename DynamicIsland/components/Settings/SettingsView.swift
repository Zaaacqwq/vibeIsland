//
//  SettingsView.swift
//  DynamicIsland
//
//  Created by Richard Kunkli on 07/08/2024.
//
import AppKit
import AVFoundation
import Combine
import Defaults
import EventKit
import KeyboardShortcuts
import LaunchAtLogin
import LottieUI
import Sparkle
import SwiftUI
import SwiftUIIntrospect
import UniformTypeIdentifiers

/// Groups for organizing settings tabs in the sidebar.
private enum SettingsTabGroup: String, CaseIterable, Identifiable {
    case core
    case mediaAndDisplay
    case system
    case productivity
    case utilities
    case developer
    case integrations
    case info

    var id: String { rawValue }

    /// Display title for the section header.  `nil` means no visible header.
    var title: String? {
        switch self {
        case .core:             return nil
        case .mediaAndDisplay:  return String(localized: "Media & Display")
        case .system:           return String(localized: "System")
        case .productivity:     return String(localized: "Productivity")
        case .utilities:        return String(localized: "Utilities")
        case .developer:        return String(localized: "Developer")
        case .integrations:     return String(localized: "Integrations")
        case .info:             return nil
        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case liveActivities
    case appearance
    case media
    case devices
    case extensions
    case timer
    case calendar
    case hudAndOSD
    case battery
    case downloads
    case shelf
    case shortcuts
    case agents
    case notifications
    case weather
    case debug
    case about

    var id: String { rawValue }

    /// Which sidebar group this tab belongs to.
    var group: SettingsTabGroup {
        switch self {
        case .general, .appearance:                                          return .core
        case .media, .liveActivities, .devices, .notifications, .weather: return .mediaAndDisplay
        case .hudAndOSD, .battery:                                           return .system
        case .timer, .calendar:                                      return .productivity
        case .shelf,
             .downloads, .shortcuts:                                         return .utilities
        case .agents, .debug:                             return .developer
        case .extensions:                                                    return .integrations
        case .about:                                                         return .info
        }
    }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .liveActivities: return String(localized: "Live Activities")
        case .appearance: return String(localized: "Appearance")
        case .media: return String(localized: "Media")
        case .devices: return String(localized: "Devices")
        case .extensions: return String(localized: "Extensions")
        case .timer: return String(localized: "Timer")
        case .calendar: return String(localized: "Calendar")
        case .hudAndOSD: return String(localized: "Controls")
        case .battery: return String(localized: "Battery")
        case .downloads: return String(localized: "Downloads")
        case .shelf: return String(localized: "Shelf")
        case .shortcuts: return String(localized: "Shortcuts")
        case .agents: return String(localized: "Agents")
        case .notifications: return String(localized: "Notifications")
        case .weather: return String(localized: "Weather")
        case .debug: return String(localized: "Debug")
        case .about: return String(localized: "About")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .liveActivities: return "waveform.path.ecg"
        case .appearance: return "paintpalette"
        case .media: return "play.laptopcomputer"
        case .devices: return "headphones"
        case .extensions: return "puzzlepiece.extension"
        case .timer: return "timer"
        case .calendar: return "calendar"
        case .hudAndOSD: return "dial.medium.fill"
        case .battery: return "battery.100.bolt"
        case .downloads: return "square.and.arrow.down"
        case .shelf: return "books.vertical"
        case .shortcuts: return "keyboard"
        case .agents: return "sparkles"
        case .notifications: return "bell.fill"
        case .weather: return "cloud.sun.fill"
        case .debug: return "ladybug"
        case .about: return "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .blue
        case .liveActivities: return .pink
        case .appearance: return .purple
        case .media: return .green
        case .devices: return Color(red: 0.1, green: 0.11, blue: 0.12)
        case .extensions: return Color(red: 0.557, green: 0.353, blue: 0.957)
        case .timer: return .red
        case .calendar: return .cyan
        case .hudAndOSD: return .indigo
        case .battery: return Color(red: 0.202, green: 0.783, blue: 0.348, opacity: 1.000)
        case .downloads: return .gray
        case .shelf: return .brown
        case .shortcuts: return .orange
        case .agents: return Color(red: 217.0 / 255.0, green: 119.0 / 255.0, blue: 66.0 / 255.0)
        case .notifications: return .red
        case .weather: return .cyan
        case .debug: return .gray
        case .about: return .secondary
        }
    }

    func highlightID(for title: String) -> String {
        "\(rawValue)-\(title)"
    }
}

private struct SettingsSearchEntry: Identifiable {
    let tab: SettingsTab
    let title: String
    let keywords: [String]
    let highlightID: String?

    var id: String { "\(tab.rawValue)-\(title)" }
}

final class SettingsHighlightCoordinator: ObservableObject {
    struct ScrollRequest: Identifiable, Equatable {
        let id: String
        fileprivate let tab: SettingsTab
    }

    @Published fileprivate var pendingScrollRequest: ScrollRequest?
    @Published private(set) var activeHighlightID: String?

    private var clearWorkItem: DispatchWorkItem?

    fileprivate func focus(on entry: SettingsSearchEntry) {
        guard let highlightID = entry.highlightID else { return }
        pendingScrollRequest = ScrollRequest(id: highlightID, tab: entry.tab)
        activateHighlight(id: highlightID)
    }

    func consumeScrollRequest(_ request: ScrollRequest) {
        guard pendingScrollRequest?.id == request.id else { return }
        pendingScrollRequest = nil
    }

    private func activateHighlight(id: String) {
        activeHighlightID = id
        clearWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard self?.activeHighlightID == id else { return }
            self?.activeHighlightID = nil
        }

        clearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }
}

private struct SettingsHighlightModifier: ViewModifier {
    let id: String
    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator
    @State private var animatePulse = false

    private var isActive: Bool {
        highlightCoordinator.activeHighlightID == id
    }

    func body(content: Content) -> some View {
        content
            .id(id)
            .background(highlightBackground)
            .onChange(of: isActive) { _, active in
                animatePulse = active
            }
            .onAppear {
                if isActive {
                    animatePulse = true
                }
            }
    }

    private var highlightBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                Color.accentColor.opacity(isActive ? (animatePulse ? 0.95 : 0.4) : 0),
                lineWidth: 2
            )
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(isActive ? 0.08 : 0))
            )
            .padding(-4)
            .shadow(color: Color.accentColor.opacity(isActive ? 0.25 : 0), radius: animatePulse ? 8 : 2)
            .animation(
                isActive ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                value: animatePulse
            )
    }
}

extension View {
    func settingsHighlight(id: String) -> some View {
        modifier(SettingsHighlightModifier(id: id))
    }

    @ViewBuilder
    func settingsHighlightIfPresent(_ id: String?) -> some View {
        if let id {
            settingsHighlight(id: id)
        } else {
            self
        }
    }
}

private struct SettingsForm<Content: View>: View {
    let tab: SettingsTab
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator

    var body: some View {
        ScrollViewReader { proxy in
            content()
                .onReceive(highlightCoordinator.$pendingScrollRequest.compactMap { request -> SettingsHighlightCoordinator.ScrollRequest? in
                    guard let request, request.tab == tab else { return nil }
                    return request
                }) { request in
                    withAnimation(.easeInOut(duration: 0.45)) {
                        proxy.scrollTo(request.id, anchor: .center)
                    }
                    highlightCoordinator.consumeScrollRequest(request)
                }
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var searchText: String = ""
    @StateObject private var highlightCoordinator = SettingsHighlightCoordinator()
    @Default(.enableMinimalisticUI) var enableMinimalisticUI

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 12) {
                SettingsSidebarSearchBar(
                    text: $searchText,
                    suggestions: searchSuggestions,
                    onSuggestionSelected: handleSearchSuggestionSelection
                )
                .padding(.horizontal, 12)
                .padding(.top, 12)

                Divider()
                    .padding(.horizontal, 12)

                List(selection: selectionBinding) {
                    ForEach(groupedFilteredTabs, id: \.group) { section in
                        Section {
                            ForEach(section.tabs) { tab in
                                NavigationLink(value: tab) {
                                    sidebarRow(for: tab)
                                }
                            }
                        } header: {
                            if let title = section.group.title {
                                Text(title)
                            }
                        }
                    }
                }
                .listStyle(SidebarListStyle())
                .frame(minWidth: 200)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 240)
                .environment(\.defaultMinListRowHeight, 44)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } detail: {
            detailView(for: resolvedSelection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar { toolbarSpacingShim }
        .environmentObject(highlightCoordinator)
        .formStyle(.grouped)
        .tint(Geist.Colors.accent)
        .frame(width: 700)
        .onChange(of: searchText) { _, newValue in
            let matches = tabsMatchingSearch(newValue)
            guard let firstMatch = matches.first else { return }
            if !matches.contains(resolvedSelection) {
                selectedTab = firstMatch
            }
        }
        .background {
            Geist.Colors.canvas
                .ignoresSafeArea()
        }
    }

    private var resolvedSelection: SettingsTab {
        availableTabs.contains(selectedTab) ? selectedTab : (availableTabs.first ?? .general)
    }

    @ToolbarContentBuilder
    private var toolbarSpacingShim: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) {
                toolbarSpacerView
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) {
                toolbarSpacerView
            }
        }
    }

    @ViewBuilder
    private var toolbarSpacerView: some View {
        Color.clear
            .frame(width: 96, height: 32)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var filteredTabs: [SettingsTab] {
        tabsMatchingSearch(searchText)
    }

    private var selectionBinding: Binding<SettingsTab> {
        Binding(
            get: { resolvedSelection },
            set: { newValue in
                selectedTab = newValue
            }
        )
    }

    @ViewBuilder
    private func sidebarIcon(for tab: SettingsTab) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        tab.tint.opacity(1),
                        tab.tint.opacity(0.7)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 26, height: 26)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.7)
                    .blendMode(.plusLighter)
            }
            .shadow(color: tab.tint.opacity(0.35), radius: 2, x: 0, y: 1)
            .overlay {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
    }

    @ViewBuilder
    private func sidebarRow(for tab: SettingsTab) -> some View {
        HStack(spacing: 10) {
            sidebarIcon(for: tab)
            Text(tab.title)
                .font(Geist.Typography.bodyStrong)
            if tab == .downloads {
                Spacer()
                Text("BETA")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.blue)
                    )
            } else if tab == .extensions {
                Spacer()
                Text("BETA")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.blue)
                    )
            }
        }
        .padding(.vertical, 4)
    }

    private var availableTabs: [SettingsTab] {
        // Ordered to match group layout: core → media & display → system →
        // productivity → utilities → developer → integrations → info.
        let ordered: [SettingsTab] = [
            // Core
            .general,
            .appearance,
            // Media & Display
            .media,
            .liveActivities,
            .notifications,
            .weather,
            .devices,
            // System
            .hudAndOSD,
            .battery,
            // Productivity
            .timer,
            .calendar,
            // Utilities
            .shelf,
            .downloads,
            .shortcuts,
            // Developer
            .agents,
            .debug,
            // Integrations
            .extensions,
            // Info
            .about
        ]

        return ordered.filter { isTabVisible($0) }
    }

    /// Groups the filtered tabs into sidebar sections, preserving both
    /// the group order and the per-group tab order from `availableTabs`.
    private var groupedFilteredTabs: [(group: SettingsTabGroup, tabs: [SettingsTab])] {
        let visible = filteredTabs
        var result: [(group: SettingsTabGroup, tabs: [SettingsTab])] = []

        for group in SettingsTabGroup.allCases {
            let tabs = visible.filter { $0.group == group }
            if !tabs.isEmpty {
                result.append((group: group, tabs: tabs))
            }
        }

        return result
    }

    private func tabsMatchingSearch(_ query: String) -> [SettingsTab] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return availableTabs }

        let entryMatches = searchEntries(matching: trimmed)
        let matchingTabs = Set(entryMatches.map(\.tab))

        return availableTabs.filter { tab in
            tab.title.localizedCaseInsensitiveContains(trimmed) || matchingTabs.contains(tab)
        }
    }

    private var searchSuggestions: [SettingsSearchEntry] {
        Array(searchEntries(matching: searchText).filter { $0.tab != .downloads }.prefix(8))
    }

    private func handleSearchSuggestionSelection(_ suggestion: SettingsSearchEntry) {
        guard suggestion.tab != .downloads else { return }
        highlightCoordinator.focus(on: suggestion)
        selectedTab = suggestion.tab
    }

    private struct SettingsSidebarSearchBar: View {
        @Binding var text: String
        let suggestions: [SettingsSearchEntry]
        let onSuggestionSelected: (SettingsSearchEntry) -> Void

        @FocusState private var isFocused: Bool
        @State private var hoveredSuggestionID: SettingsSearchEntry.ID?

        var body: some View {
            VStack(spacing: 6) {
                searchField
                if showSuggestions {
                    suggestionList
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showSuggestions)
        }

        private var showSuggestions: Bool {
            isFocused && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !suggestions.isEmpty
        }

        private var searchField: some View {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.secondary)

                TextField("Search Settings", text: $text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit(triggerFirstSuggestion)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08))
            )
        }

        private var suggestionList: some View {
            VStack(spacing: 0) {
                ForEach(suggestions) { suggestion in
                    Button {
                        selectSuggestion(suggestion)
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(suggestion.tab.tint)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    Image(systemName: suggestion.tab.systemImage)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.white)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.primary)
                                Text(suggestion.tab.title)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.secondary)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .background(rowBackground(for: suggestion))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredSuggestionID = hovering ? suggestion.id : (hoveredSuggestionID == suggestion.id ? nil : hoveredSuggestionID)
                    }

                    if suggestion.id != suggestions.last?.id {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08))
            )
            .shadow(color: Color.black.opacity(0.2), radius: 8, y: 4)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        private func rowBackground(for suggestion: SettingsSearchEntry) -> some View {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hoveredSuggestionID == suggestion.id ? Color.white.opacity(0.08) : Color.clear)
        }

        private func selectSuggestion(_ suggestion: SettingsSearchEntry) {
            onSuggestionSelected(suggestion)
            isFocused = false
        }

        private func triggerFirstSuggestion() {
            guard let first = suggestions.first else { return }
            selectSuggestion(first)
        }
    }

    private func searchEntries(matching query: String) -> [SettingsSearchEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return settingsSearchIndex
            .filter { availableTabs.contains($0.tab) }
            .filter { entry in
                entry.title.localizedCaseInsensitiveContains(trimmed) ||
                entry.keywords.contains { $0.localizedCaseInsensitiveContains(trimmed) }
            }
    }

    private var settingsSearchIndex: [SettingsSearchEntry] {
        [
            // General
            SettingsSearchEntry(tab: .general, title: "Enable Minimalistic UI", keywords: ["minimalistic", "ui mode", "general"], highlightID: SettingsTab.general.highlightID(for: "Enable Minimalistic UI")),
            SettingsSearchEntry(tab: .general, title: "Menubar icon", keywords: ["menu bar", "status bar", "icon"], highlightID: SettingsTab.general.highlightID(for: "Menubar icon")),
            SettingsSearchEntry(tab: .general, title: "Launch at login", keywords: ["autostart", "startup"], highlightID: SettingsTab.general.highlightID(for: "Launch at login")),
            SettingsSearchEntry(tab: .general, title: "Show on all displays", keywords: ["multi-display", "external monitor"], highlightID: SettingsTab.general.highlightID(for: "Show on all displays")),
            SettingsSearchEntry(tab: .general, title: "Show on a specific display", keywords: ["preferred screen", "display picker"], highlightID: SettingsTab.general.highlightID(for: "Show on a specific display")),
            SettingsSearchEntry(tab: .general, title: "Automatically switch displays", keywords: ["auto switch", "displays"], highlightID: SettingsTab.general.highlightID(for: "Automatically switch displays")),
            SettingsSearchEntry(tab: .general, title: "Hide Dynamic Island during screenshots & recordings", keywords: ["privacy", "screenshot", "recording"], highlightID: SettingsTab.general.highlightID(for: "Hide Dynamic Island during screenshots & recordings")),
            SettingsSearchEntry(tab: .general, title: "Enable gestures", keywords: ["gestures", "trackpad"], highlightID: SettingsTab.general.highlightID(for: "Enable gestures")),
            SettingsSearchEntry(tab: .general, title: "Close gesture", keywords: ["pinch", "swipe"], highlightID: SettingsTab.general.highlightID(for: "Close gesture")),
            SettingsSearchEntry(tab: .general, title: "Reverse swipe gestures", keywords: ["reverse", "swipe", "media"], highlightID: SettingsTab.general.highlightID(for: "Reverse swipe gestures")),
            SettingsSearchEntry(tab: .general, title: "Reverse scroll gestures", keywords: ["reverse", "scroll", "open", "close"], highlightID: SettingsTab.general.highlightID(for: "Reverse scroll gestures")),
            SettingsSearchEntry(tab: .general, title: "Extend hover area", keywords: ["hover", "cursor"], highlightID: SettingsTab.general.highlightID(for: "Extend hover area")),
            SettingsSearchEntry(tab: .general, title: "Enable haptics", keywords: ["haptic", "feedback"], highlightID: SettingsTab.general.highlightID(for: "Enable haptics")),
            SettingsSearchEntry(tab: .general, title: "Open notch on hover", keywords: ["hover to open", "auto open"], highlightID: SettingsTab.general.highlightID(for: "Open notch on hover")),
            SettingsSearchEntry(tab: .general, title: "External display style", keywords: ["dynamic island", "pill", "external display", "non-notch", "floating", "capsule"], highlightID: SettingsTab.general.highlightID(for: "External display style")),
            SettingsSearchEntry(tab: .general, title: "Hide until hovered", keywords: ["hide", "hover", "external", "non-notch", "auto hide", "slide"], highlightID: SettingsTab.general.highlightID(for: "Hide until hovered")),
            SettingsSearchEntry(tab: .general, title: "Notch display height", keywords: ["display height", "menu bar size"], highlightID: SettingsTab.general.highlightID(for: "Notch display height")),

            // Live Activities
            SettingsSearchEntry(tab: .liveActivities, title: "Enable Screen Recording Detection", keywords: ["screen recording", "indicator"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Screen Recording Detection")),
            SettingsSearchEntry(tab: .liveActivities, title: "Show Recording Indicator", keywords: ["recording indicator", "red dot"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show Recording Indicator")),
            SettingsSearchEntry(tab: .liveActivities, title: "Enable Focus Detection", keywords: ["focus", "do not disturb", "dnd"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Focus Detection")),
            SettingsSearchEntry(tab: .liveActivities, title: "Show Focus Indicator", keywords: ["focus icon", "moon"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show Focus Indicator")),
            SettingsSearchEntry(tab: .liveActivities, title: "Show Focus Label", keywords: ["focus label", "text"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show Focus Label")),
            SettingsSearchEntry(tab: .liveActivities, title: "Enable Camera Detection", keywords: ["camera", "privacy indicator"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Camera Detection")),
            SettingsSearchEntry(tab: .liveActivities, title: "Enable Microphone Detection", keywords: ["microphone", "privacy"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Microphone Detection")),
            SettingsSearchEntry(tab: .liveActivities, title: "Enable music live activity", keywords: ["music", "now playing"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable music live activity")),
            SettingsSearchEntry(tab: .liveActivities, title: "Enable reminder live activity", keywords: ["reminder", "live activity"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable reminder live activity")),

            // Battery (Charge)
            SettingsSearchEntry(tab: .battery, title: "Show battery indicator", keywords: ["battery hud", "charge"], highlightID: SettingsTab.battery.highlightID(for: "Show battery indicator")),
            SettingsSearchEntry(tab: .battery, title: "Show battery percentage", keywords: ["battery percent"], highlightID: SettingsTab.battery.highlightID(for: "Show battery percentage")),
            SettingsSearchEntry(tab: .battery, title: "Show power status notifications", keywords: ["notifications", "power"], highlightID: SettingsTab.battery.highlightID(for: "Show power status notifications")),
            SettingsSearchEntry(tab: .battery, title: "Show power status icons", keywords: ["power icons", "charging icon"], highlightID: SettingsTab.battery.highlightID(for: "Show power status icons")),
            SettingsSearchEntry(tab: .battery, title: "Play low battery alert sound", keywords: ["low battery", "alert", "sound"], highlightID: SettingsTab.battery.highlightID(for: "Play low battery alert sound")),
            SettingsSearchEntry(tab: .battery, title: "Charging HUD", keywords: ["battery", "charging", "temporary activity"], highlightID: SettingsTab.battery.highlightID(for: "Charging HUD")),
            SettingsSearchEntry(tab: .battery, title: "Low battery HUD", keywords: ["battery", "low", "temporary activity"], highlightID: SettingsTab.battery.highlightID(for: "Low battery HUD")),
            SettingsSearchEntry(tab: .battery, title: "Fully charged HUD", keywords: ["battery", "full", "temporary activity"], highlightID: SettingsTab.battery.highlightID(for: "Fully charged HUD")),
            SettingsSearchEntry(tab: .battery, title: "Charging duration", keywords: ["charging", "duration", "seconds"], highlightID: SettingsTab.battery.highlightID(for: "Charging duration")),
            SettingsSearchEntry(tab: .battery, title: "Low battery duration", keywords: ["low battery", "duration", "seconds"], highlightID: SettingsTab.battery.highlightID(for: "Low battery duration")),
            SettingsSearchEntry(tab: .battery, title: "Full battery duration", keywords: ["full battery", "duration", "seconds"], highlightID: SettingsTab.battery.highlightID(for: "Full battery duration")),
            SettingsSearchEntry(tab: .battery, title: "Test charging HUD", keywords: ["battery", "test", "charging", "preview"], highlightID: nil),
            SettingsSearchEntry(tab: .battery, title: "Test low battery HUD", keywords: ["battery", "test", "low", "preview"], highlightID: nil),
            SettingsSearchEntry(tab: .battery, title: "Test full battery HUD", keywords: ["battery", "test", "full", "preview"], highlightID: nil),
            SettingsSearchEntry(tab: .battery, title: "Low battery style", keywords: ["battery", "style", "compact", "standard"], highlightID: SettingsTab.battery.highlightID(for: "Low battery style")),
            SettingsSearchEntry(tab: .battery, title: "Low battery threshold", keywords: ["battery", "threshold", "percent"], highlightID: SettingsTab.battery.highlightID(for: "Low battery threshold")),
            SettingsSearchEntry(tab: .battery, title: "Full battery style", keywords: ["battery", "style", "compact", "standard"], highlightID: SettingsTab.battery.highlightID(for: "Full battery style")),
            SettingsSearchEntry(tab: .battery, title: "Full charge threshold", keywords: ["battery", "threshold", "full"], highlightID: SettingsTab.battery.highlightID(for: "Full charge threshold")),

            // HUDs
            SettingsSearchEntry(tab: .devices, title: "Show Bluetooth device connections", keywords: ["bluetooth", "hud"], highlightID: SettingsTab.devices.highlightID(for: "Show Bluetooth device connections")),
            SettingsSearchEntry(tab: .devices, title: "Use circular battery indicator", keywords: ["battery", "circular"], highlightID: SettingsTab.devices.highlightID(for: "Use circular battery indicator")),
            SettingsSearchEntry(tab: .devices, title: "Show battery percentage text in HUD", keywords: ["battery text"], highlightID: SettingsTab.devices.highlightID(for: "Show battery percentage text in HUD")),
            SettingsSearchEntry(tab: .devices, title: "Scroll device name in HUD", keywords: ["marquee", "device name"], highlightID: SettingsTab.devices.highlightID(for: "Scroll device name in HUD")),
            SettingsSearchEntry(tab: .devices, title: "Use 3D Bluetooth HUD icon", keywords: ["bluetooth", "3d", "animation", "mov"], highlightID: SettingsTab.devices.highlightID(for: "Use 3D Bluetooth HUD icon")),
            SettingsSearchEntry(tab: .devices, title: "Color-coded battery display", keywords: ["color", "battery"], highlightID: SettingsTab.devices.highlightID(for: "Color-coded battery display")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Color-coded volume display", keywords: ["volume", "color"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Color-coded volume display")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Smooth color transitions", keywords: ["gradient", "smooth"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Smooth color transitions")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Show percentages beside progress bars", keywords: ["percentages", "progress"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Show percentages beside progress bars")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "HUD style", keywords: ["inline", "compact"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "HUD style")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Progressbar style", keywords: ["progress", "style"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Progressbar style")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Enable glowing effect", keywords: ["glow", "indicator"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable glowing effect")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Use accent color", keywords: ["accent", "color"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Use accent color")),

            // Custom OSD
            SettingsSearchEntry(tab: .hudAndOSD, title: "Enable Custom OSD", keywords: ["osd", "on-screen display", "custom osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable Custom OSD")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Volume OSD", keywords: ["volume", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Volume OSD")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Brightness OSD", keywords: ["brightness", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Brightness OSD")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Keyboard Backlight OSD", keywords: ["keyboard", "backlight", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Keyboard Backlight OSD")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Material", keywords: ["material", "frosted", "liquid", "glass", "solid", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Material")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Icon & Progress Color", keywords: ["color", "icon", "white", "black", "gray", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Icon & Progress Color")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Volume step", keywords: ["volume", "step", "percent"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Volume step")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Volume fine step", keywords: ["volume", "fine", "step", "percent"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Volume fine step")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Brightness step", keywords: ["brightness", "step", "percent"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Brightness step")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Brightness fine step", keywords: ["brightness", "fine", "step", "percent"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Brightness fine step")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Enable external volume control listener", keywords: ["external volume", "ddc volume", "betterdisplay volume", "lunar volume", "disable native volume"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable external volume control listener")),

            // Media
            SettingsSearchEntry(tab: .media, title: "Music Source", keywords: ["media source", "controller"], highlightID: SettingsTab.media.highlightID(for: "Music Source")),
            SettingsSearchEntry(tab: .media, title: "Skip buttons", keywords: ["skip", "controls", "±10"], highlightID: SettingsTab.media.highlightID(for: "Skip buttons")),
            SettingsSearchEntry(tab: .media, title: "Sneak Peek Style", keywords: ["sneak peek", "preview"], highlightID: SettingsTab.media.highlightID(for: "Sneak Peek Style")),
            SettingsSearchEntry(tab: .media, title: "Enable lyrics", keywords: ["lyrics", "song text"], highlightID: SettingsTab.media.highlightID(for: "Enable lyrics")),
            SettingsSearchEntry(tab: .media, title: "Show lyrics in closed notch", keywords: ["lyrics", "closed notch", "pill", "song text", "pop down"], highlightID: SettingsTab.media.highlightID(for: "Show lyrics in closed notch")),
            SettingsSearchEntry(tab: .media, title: "Show live canvas in Dynamic Island", keywords: ["canvas", "live canvas", "album art", "dynamic island", "spotify canvas"], highlightID: SettingsTab.media.highlightID(for: "Show live canvas in Dynamic Island")),
            SettingsSearchEntry(tab: .media, title: "Auto-hide inactive notch media player", keywords: ["auto hide", "inactive", "placeholder", "notch media"], highlightID: SettingsTab.media.highlightID(for: "Auto-hide inactive notch media player")),
            SettingsSearchEntry(tab: .media, title: "Show Change Media Output control", keywords: ["airplay", "route picker", "media output"], highlightID: SettingsTab.media.highlightID(for: "Show Change Media Output control")),
            SettingsSearchEntry(tab: .media, title: "Enable album art parallax effect", keywords: ["parallax", "parallax effect", "album art"], highlightID: SettingsTab.media.highlightID(for: "Enable album art parallax effect")),

            // Calendar
            SettingsSearchEntry(tab: .calendar, title: "Show calendar", keywords: ["calendar", "events"], highlightID: SettingsTab.calendar.highlightID(for: "Show calendar")),
            SettingsSearchEntry(tab: .calendar, title: "Enable reminder live activity", keywords: ["reminder", "live activity"], highlightID: SettingsTab.calendar.highlightID(for: "Enable reminder live activity")),
            SettingsSearchEntry(tab: .calendar, title: "Countdown style", keywords: ["reminder countdown"], highlightID: SettingsTab.calendar.highlightID(for: "Countdown style")),
            SettingsSearchEntry(tab: .calendar, title: "Show events within the next", keywords: ["calendar widget", "lookahead"], highlightID: SettingsTab.calendar.highlightID(for: "Show events within the next")),
            SettingsSearchEntry(tab: .calendar, title: "Show events from all calendars", keywords: ["calendar widget", "selection"], highlightID: SettingsTab.calendar.highlightID(for: "Show events from all calendars")),
            SettingsSearchEntry(tab: .calendar, title: "Show countdown", keywords: ["calendar widget", "countdown"], highlightID: SettingsTab.calendar.highlightID(for: "Show countdown")),
            SettingsSearchEntry(tab: .calendar, title: "Show event for entire duration", keywords: ["calendar widget", "duration"], highlightID: SettingsTab.calendar.highlightID(for: "Show event for entire duration")),
            SettingsSearchEntry(tab: .calendar, title: "Hide active event and show next upcoming event", keywords: ["calendar widget", "after start"], highlightID: SettingsTab.calendar.highlightID(for: "Hide active event and show next upcoming event")),
            SettingsSearchEntry(tab: .calendar, title: "Show time remaining", keywords: ["calendar widget", "remaining"], highlightID: SettingsTab.calendar.highlightID(for: "Show time remaining")),
            SettingsSearchEntry(tab: .calendar, title: "Show start time after event begins", keywords: ["calendar widget", "start time"], highlightID: SettingsTab.calendar.highlightID(for: "Show start time after event begins")),
            SettingsSearchEntry(tab: .calendar, title: "Chip color", keywords: ["reminder chip", "color"], highlightID: SettingsTab.calendar.highlightID(for: "Chip color")),
            SettingsSearchEntry(tab: .calendar, title: "Hide all-day events", keywords: ["calendar", "all-day"], highlightID: SettingsTab.calendar.highlightID(for: "Hide all-day events")),
            SettingsSearchEntry(tab: .calendar, title: "Hide completed reminders", keywords: ["reminder", "completed"], highlightID: SettingsTab.calendar.highlightID(for: "Hide completed reminders")),
            SettingsSearchEntry(tab: .calendar, title: "Show full event titles", keywords: ["calendar", "titles"], highlightID: SettingsTab.calendar.highlightID(for: "Show full event titles")),
            SettingsSearchEntry(tab: .calendar, title: "Auto-scroll to next event", keywords: ["calendar", "scroll"], highlightID: SettingsTab.calendar.highlightID(for: "Auto-scroll to next event")),

            // Shelf
            SettingsSearchEntry(tab: .shelf, title: "Enable shelf", keywords: ["shelf", "dock"], highlightID: SettingsTab.shelf.highlightID(for: "Enable shelf")),
            SettingsSearchEntry(tab: .shelf, title: "Open shelf tab by default if items added", keywords: ["auto open", "shelf tab"], highlightID: SettingsTab.shelf.highlightID(for: "Open shelf tab by default if items added")),
            SettingsSearchEntry(tab: .shelf, title: "Expanded drag detection area", keywords: ["shelf", "drag"], highlightID: SettingsTab.shelf.highlightID(for: "Expanded drag detection area")),
            SettingsSearchEntry(tab: .shelf, title: "Copy items on drag", keywords: ["shelf", "drag", "copy"], highlightID: SettingsTab.shelf.highlightID(for: "Copy items on drag")),
            SettingsSearchEntry(tab: .shelf, title: "Remove from shelf after dragging", keywords: ["shelf", "drag", "remove"], highlightID: SettingsTab.shelf.highlightID(for: "Remove from shelf after dragging")),
            SettingsSearchEntry(tab: .shelf, title: "Quick Share Service", keywords: ["shelf", "share", "airdrop", "localsend"], highlightID: SettingsTab.shelf.highlightID(for: "Quick Share Service")),
            SettingsSearchEntry(tab: .shelf, title: "LocalSend Device Picker Style", keywords: ["localsend", "glass", "picker", "material"], highlightID: SettingsTab.shelf.highlightID(for: "Device Picker Style")),

            // Appearance
            SettingsSearchEntry(tab: .appearance, title: "Main screen style", keywords: ["dynamic island", "pill", "non-notch", "display style", "notch style"], highlightID: SettingsTab.appearance.highlightID(for: "Main screen style")),
            SettingsSearchEntry(tab: .appearance, title: "Settings icon in notch", keywords: ["settings button", "toolbar"], highlightID: SettingsTab.appearance.highlightID(for: "Settings icon in notch")),
            SettingsSearchEntry(tab: .appearance, title: "Enable window shadow", keywords: ["shadow", "appearance"], highlightID: SettingsTab.appearance.highlightID(for: "Enable window shadow")),
            SettingsSearchEntry(tab: .appearance, title: "Corner radius scaling", keywords: ["corner radius", "shape"], highlightID: SettingsTab.appearance.highlightID(for: "Corner radius scaling")),
            SettingsSearchEntry(tab: .appearance, title: "Use simpler close animation", keywords: ["close animation", "notch"], highlightID: SettingsTab.appearance.highlightID(for: "Use simpler close animation")),
            SettingsSearchEntry(tab: .appearance, title: "Notch Width", keywords: ["expanded notch", "width", "resize"], highlightID: SettingsTab.appearance.highlightID(for: "Expanded notch width")),
            SettingsSearchEntry(tab: .appearance, title: "Enable colored spectrograms", keywords: ["spectrogram", "audio"], highlightID: SettingsTab.appearance.highlightID(for: "Enable colored spectrograms")),
            SettingsSearchEntry(tab: .appearance, title: "Enable colored lyrics", keywords: ["lyrics", "color", "album color"], highlightID: SettingsTab.appearance.highlightID(for: "Enable colored lyrics")),
            SettingsSearchEntry(tab: .appearance, title: "Enable player color tinting", keywords: ["tint", "album color", "player"], highlightID: SettingsTab.appearance.highlightID(for: "Enable player color tinting")),
            SettingsSearchEntry(tab: .appearance, title: "Enable blur effect behind album art", keywords: ["blur", "album art"], highlightID: SettingsTab.appearance.highlightID(for: "Enable blur effect behind album art")),
            SettingsSearchEntry(tab: .appearance, title: "Slider color", keywords: ["slider", "accent"], highlightID: SettingsTab.appearance.highlightID(for: "Slider color")),
            SettingsSearchEntry(tab: .appearance, title: "Idle Animation", keywords: ["face animation", "idle", "cool face"], highlightID: SettingsTab.appearance.highlightID(for: "Idle Animation")),
            SettingsSearchEntry(tab: .appearance, title: "App icon", keywords: ["app icon", "custom icon"], highlightID: SettingsTab.appearance.highlightID(for: "App icon")),

            // Extensions
            SettingsSearchEntry(tab: .extensions, title: "Enable third-party extensions", keywords: ["extensions", "authorization", "third party"], highlightID: SettingsTab.extensions.highlightID(for: "Enable third-party extensions")),
            SettingsSearchEntry(tab: .extensions, title: "Allow extension live activities", keywords: ["extensions", "live activities", "permissions"], highlightID: SettingsTab.extensions.highlightID(for: "Allow extension live activities")),
            SettingsSearchEntry(tab: .extensions, title: "Enable extension diagnostics logging", keywords: ["extensions", "diagnostics", "logging"], highlightID: SettingsTab.extensions.highlightID(for: "Enable extension diagnostics logging")),
            SettingsSearchEntry(tab: .extensions, title: "Manage app permissions", keywords: ["extensions", "permissions", "apps"], highlightID: SettingsTab.extensions.highlightID(for: "App permissions list")),

            // Shortcuts
            SettingsSearchEntry(tab: .shortcuts, title: "Enable global keyboard shortcuts", keywords: ["keyboard", "shortcut"], highlightID: SettingsTab.shortcuts.highlightID(for: "Enable global keyboard shortcuts")),

            // Timer
            SettingsSearchEntry(tab: .timer, title: "Enable timer feature", keywords: ["timer", "enable"], highlightID: SettingsTab.timer.highlightID(for: "Enable timer feature")),
            SettingsSearchEntry(tab: .timer, title: "Mirror macOS Clock timers", keywords: ["system timer", "clock app"], highlightID: SettingsTab.timer.highlightID(for: "Mirror macOS Clock timers")),
            SettingsSearchEntry(tab: .timer, title: "Timer tint", keywords: ["timer colour", "preset"], highlightID: SettingsTab.timer.highlightID(for: "Timer tint")),
            SettingsSearchEntry(tab: .timer, title: "Solid colour", keywords: ["timer colour", "custom"], highlightID: SettingsTab.timer.highlightID(for: "Solid colour")),
            SettingsSearchEntry(tab: .timer, title: "Progress style", keywords: ["progress", "bar", "ring"], highlightID: SettingsTab.timer.highlightID(for: "Progress style")),
            SettingsSearchEntry(tab: .timer, title: "Accent colour", keywords: ["accent", "timer"], highlightID: SettingsTab.timer.highlightID(for: "Accent colour")),

            // Stats

            // Clipboard

            // Color Picker

            // Terminal
        ]
    }

    private func isTabVisible(_ tab: SettingsTab) -> Bool {
        switch tab {
        case .timer, .shelf:
            return !enableMinimalisticUI
        default:
            return true
        }
    }

    @ViewBuilder
    private func detailView(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            SettingsForm(tab: .general) {
                GeneralSettings()
            }
        case .liveActivities:
            SettingsForm(tab: .liveActivities) {
                LiveActivitiesSettings()
            }
        case .appearance:
            SettingsForm(tab: .appearance) {
                Appearance()
            }
        case .media:
            SettingsForm(tab: .media) {
                Media()
            }
        case .devices:
            SettingsForm(tab: .devices) {
                DevicesSettingsView()
            }
        case .extensions:
            SettingsForm(tab: .extensions) {
                ExtensionsSettingsView()
            }
        case .timer:
            SettingsForm(tab: .timer) {
                TimerSettings()
            }
        case .calendar:
            SettingsForm(tab: .calendar) {
                CalendarSettings()
            }
        case .hudAndOSD:
            SettingsForm(tab: .hudAndOSD) {
                HUDAndOSDSettingsView()
            }
        case .battery:
            SettingsForm(tab: .battery) {
                Charge()
            }
        case .downloads:
            SettingsForm(tab: .downloads) {
                Downloads()
            }
        case .shelf:
            SettingsForm(tab: .shelf) {
                Shelf()
            }
        case .shortcuts:
            SettingsForm(tab: .shortcuts) {
                Shortcuts()
            }
        case .agents:
            SettingsForm(tab: .agents) {
                AgentsSettings()
            }
        case .notifications:
            SettingsForm(tab: .notifications) {
                NotificationsSettings()
            }
        case .weather:
            SettingsForm(tab: .weather) {
                WeatherSettings()
            }
        case .debug:
            SettingsForm(tab: .debug) {
                DebugSettings()
            }
        case .about:
            if let controller = updaterController {
                SettingsForm(tab: .about) {
                    About(updaterController: controller)
                }
            } else {
                SettingsForm(tab: .about) {
                    About(updaterController: SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil))
                }
            }
        }
    }
}

struct GeneralSettings: View {
    @State private var screens: [String] = NSScreen.screens.compactMap { $0.localizedName }
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.showEmojis) var showEmojis
    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @Default(.enableHorizontalTabGestures) var enableHorizontalTabGestures
    @Default(.reverseSwipeGestures) var reverseSwipeGestures
    @Default(.reverseScrollGestures) var reverseScrollGestures
    @Default(.externalDisplayStyle) var externalDisplayStyle
    @Default(.hideNonNotchUntilHover) var hideNonNotchUntilHover

    private var gestureSensitivityLabel: String {
        gestureSensitivity == 100 ? "High" : gestureSensitivity == 200 ? "Medium" : "Low"
    }

    var body: some View {
        GeistSettingsPage(title: "General") {
            GeistSection(
                title: "UI Mode",
                footer: "Minimalistic mode focuses on media controls and system HUDs, hiding all extra features for a clean, focused experience. Automatically enables simpler animations."
            ) {
                GeistToggleRow(title: "Enable Minimalistic UI", isOn: $enableMinimalisticUI)
                    .onChange(of: enableMinimalisticUI) { _, newValue in
                        if newValue {
                            // Auto-enable simpler animation mode
                            Defaults[.useModernCloseAnimation] = true
                        }
                    }
                GeistToggleRow(title: "Show battery percentage inside icon", isOn: geistBinding(.showBatteryPercentInside), divider: false)
                    .disabled(!enableMinimalisticUI)
            }

            systemFeatures()

            notchHeightSection()

            notchBehaviour()

            gestureControls()
        }
        .toolbar {
            Button("Quit app") {
                NSApp.terminate(self)
            }
            .controlSize(.extraLarge)
        }
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }

    @ViewBuilder
    func systemFeatures() -> some View {
        GeistSection(title: "System features") {
            GeistToggleRow(title: "Menubar icon", isOn: geistBinding(.menubarIcon))
            GeistToggleRow(title: "Launch at login", isOn: Binding(
                get: { LaunchAtLogin.isEnabled }, set: { LaunchAtLogin.isEnabled = $0 }
            ))
            GeistToggleRow(title: "Show on all displays", isOn: $showOnAllDisplays)
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
            GeistPickerRow(title: "Show on a specific display", selection: $coordinator.preferredScreen) {
                ForEach(screens, id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: NSScreen.screens) {
                screens = NSScreen.screens.compactMap { $0.localizedName }
            }
            .disabled(showOnAllDisplays)
            GeistToggleRow(title: "Automatically switch displays", isOn: $automaticallySwitchDisplay)
                .onChange(of: automaticallySwitchDisplay) {
                    NotificationCenter.default.post(name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                }
                .disabled(showOnAllDisplays)
            GeistToggleRow(title: "Hide Dynamic Island during screenshots & recordings", isOn: geistBinding(.hideDynamicIslandFromScreenCapture), divider: false)
        }
    }

    @ViewBuilder
    func notchHeightSection() -> some View {
        GeistSection(title: "Notch Height") {
            GeistPickerRow(title: "Notch display height", selection: $notchHeightMode, divider: notchHeightMode == .custom) {
                Text("Match real notch size").tag(WindowHeightMode.matchRealNotchSize)
                Text("Match menubar height").tag(WindowHeightMode.matchMenuBar)
                Text("Custom height").tag(WindowHeightMode.custom)
            }
            .onChange(of: notchHeightMode) {
                switch notchHeightMode {
                case .matchRealNotchSize: notchHeight = 38
                case .matchMenuBar: notchHeight = 44
                case .custom: notchHeight = 38
                }
                NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
            }
            if notchHeightMode == .custom {
                GeistSliderRow(
                    title: "Custom notch size",
                    valueLabel: String(format: "%.0f", notchHeight),
                    value: $notchHeight, range: 15...45, step: 1,
                    onChange: { NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil) }
                )
            }
            GeistPickerRow(title: "Non-notch display height", selection: $nonNotchHeightMode, divider: nonNotchHeightMode == .custom) {
                Text("Match menubar height").tag(WindowHeightMode.matchMenuBar)
                Text("Match real notch size").tag(WindowHeightMode.matchRealNotchSize)
                Text("Custom height").tag(WindowHeightMode.custom)
            }
            .onChange(of: nonNotchHeightMode) {
                switch nonNotchHeightMode {
                case .matchMenuBar: nonNotchHeight = 24
                case .matchRealNotchSize: nonNotchHeight = 32
                case .custom: nonNotchHeight = 32
                }
                NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
            }
            if nonNotchHeightMode == .custom {
                GeistSliderRow(
                    title: "Custom non-notch size",
                    valueLabel: String(format: "%.0f", nonNotchHeight),
                    value: $nonNotchHeight, range: 0...40, step: 1, divider: false,
                    onChange: { NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil) }
                )
            }
        }
    }

    @ViewBuilder
    func gestureControls() -> some View {
        GeistSection(
            title: "Gesture control",
            badge: "Beta",
            footer: "Two-finger swipe up on notch to close, two-finger swipe down on notch to open when **Open notch on hover** option is disabled."
        ) {
            GeistToggleRow(title: "Enable gestures", isOn: $enableGestures, divider: enableGestures)
                .disabled(!openNotchOnHover)
            if enableGestures {
                GeistToggleRow(title: "Tab change with horizontal gestures", isOn: $enableHorizontalTabGestures)
                if enableHorizontalTabGestures {
                    GeistToggleRow(title: "Reverse swipe gestures", isOn: geistBinding(.reverseSwipeGestures))
                }
                GeistToggleRow(title: "Close gesture", isOn: geistBinding(.closeGestureEnabled))
                GeistSliderRow(
                    title: "Gesture sensitivity",
                    valueLabel: gestureSensitivityLabel,
                    value: $gestureSensitivity, range: 100...300, step: 100
                )
                GeistToggleRow(title: "Reverse open/close scroll gestures", isOn: $reverseScrollGestures, divider: false)
            }
        }
    }

    @ViewBuilder
    func notchBehaviour() -> some View {
        GeistSection(
            title: "Notch behavior",
            footer: "When \"Hide until hovered\" is enabled, the notch slides up and hides on external (non-notch) displays until you hover over it."
        ) {
            GeistToggleRow(title: "Extend hover area", isOn: geistBinding(.extendHoverArea))
            GeistToggleRow(title: "Enable haptics", isOn: geistBinding(.enableHaptics))
            GeistToggleRow(title: "Open notch on hover", isOn: geistBinding(.openNotchOnHover))
            GeistToggleRow(title: "Remember last tab", isOn: $coordinator.openLastTabByDefault)
            if openNotchOnHover {
                GeistSliderRow(
                    title: "Minimum hover duration",
                    valueLabel: String(format: "%.1fs", minimumHoverDuration),
                    value: $minimumHoverDuration, range: 0...1, step: 0.1,
                    onChange: { NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil) }
                )
            }
            GeistPickerRow(title: "External display style", selection: $externalDisplayStyle) {
                ForEach(ExternalDisplayStyle.allCases) { Text($0.localizedName).tag($0) }
            }
            .onChange(of: externalDisplayStyle) {
                NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
            }
            GeistRow {
                Text(externalDisplayStyle.description)
                    .font(Geist.Typography.caption)
                    .foregroundStyle(Geist.Colors.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            GeistToggleRow(title: "Hide until hovered on non-notch displays", isOn: $hideNonNotchUntilHover, divider: false)
        }
    }
}

struct Charge: View {
    @ObservedObject private var batteryStatusViewModel = BatteryStatusViewModel.shared
    @Default(.showPowerStatusNotifications) private var showPowerStatusNotifications
    @Default(.showChargingBatteryHUD) private var showChargingBatteryHUD
    @Default(.showLowBatteryHUD) private var showLowBatteryHUD
    @Default(.showFullBatteryHUD) private var showFullBatteryHUD
    @Default(.chargingBatteryHUDDuration) private var chargingBatteryHUDDuration
    @Default(.lowBatteryHUDDuration) private var lowBatteryHUDDuration
    @Default(.fullBatteryHUDDuration) private var fullBatteryHUDDuration
    @Default(.lowBatteryHUDThreshold) private var lowBatteryHUDThreshold
    @Default(.fullBatteryHUDThreshold) private var fullBatteryHUDThreshold
    @Default(.lowBatteryHUDStyle) private var lowBatteryHUDStyle
    @Default(.fullBatteryHUDStyle) private var fullBatteryHUDStyle

    private var chargingDurationBinding: Binding<Double> {
        Binding(
            get: { Double(chargingBatteryHUDDuration) },
            set: { chargingBatteryHUDDuration = Int($0.rounded()) }
        )
    }

    private var lowBatteryDurationBinding: Binding<Double> {
        Binding(
            get: { Double(lowBatteryHUDDuration) },
            set: { lowBatteryHUDDuration = Int($0.rounded()) }
        )
    }

    private var fullBatteryDurationBinding: Binding<Double> {
        Binding(
            get: { Double(fullBatteryHUDDuration) },
            set: { fullBatteryHUDDuration = Int($0.rounded()) }
        )
    }

    private var lowBatteryThresholdBinding: Binding<Double> {
        Binding(
            get: { Double(lowBatteryHUDThreshold) },
            set: { lowBatteryHUDThreshold = Int($0.rounded()) }
        )
    }

    private var fullBatteryThresholdBinding: Binding<Double> {
        Binding(
            get: { Double(fullBatteryHUDThreshold) },
            set: { fullBatteryHUDThreshold = Int($0.rounded()) }
        )
    }

    private func sectionOpacity(_ isEnabled: Bool) -> Double {
        isEnabled ? 1 : 0.5
    }

    private var chargingEnabled: Bool { showPowerStatusNotifications && showChargingBatteryHUD }
    private var lowEnabled: Bool { showPowerStatusNotifications && showLowBatteryHUD }
    private var fullEnabled: Bool { showPowerStatusNotifications && showFullBatteryHUD }

    var body: some View {
        GeistSettingsPage(title: "Battery") {
            if BatteryActivityManager.shared.hasBattery() {
                GeistSection(title: "General") {
                    GeistToggleRow(title: "Show battery indicator", isOn: geistBinding(.showBatteryIndicator))
                    GeistToggleRow(title: "Show power status notifications", isOn: $showPowerStatusNotifications)
                    GeistToggleRow(title: "Play low battery alert sound", isOn: geistBinding(.playLowBatteryAlertSound), divider: false)
                }

                GeistSection(title: "Battery Information") {
                    GeistToggleRow(title: "Show battery percentage", isOn: geistBinding(.showBatteryPercentage))
                    GeistToggleRow(title: "Show power status icons", isOn: geistBinding(.showPowerStatusIcons), divider: false)
                }

                GeistSection(
                    title: "Battery HUDs",
                    footer: "These temporary HUDs recreate the charging, low-battery, and full-battery notch alerts."
                ) {
                    GeistToggleRow(title: "Charging HUD", isOn: $showChargingBatteryHUD)
                    GeistToggleRow(title: "Low battery HUD", isOn: $showLowBatteryHUD)
                    GeistToggleRow(title: "Fully charged HUD", isOn: $showFullBatteryHUD, divider: false)
                }

                GeistSection(title: "HUD Duration") {
                    GeistSliderRow(title: "Charging duration", valueLabel: "\(chargingBatteryHUDDuration)s", value: chargingDurationBinding, range: 1...10, step: 1)
                        .disabled(!chargingEnabled).opacity(sectionOpacity(chargingEnabled))
                    GeistSliderRow(title: "Low battery duration", valueLabel: "\(lowBatteryHUDDuration)s", value: lowBatteryDurationBinding, range: 1...10, step: 1)
                        .disabled(!lowEnabled).opacity(sectionOpacity(lowEnabled))
                    GeistSliderRow(title: "Full battery duration", valueLabel: "\(fullBatteryHUDDuration)s", value: fullBatteryDurationBinding, range: 1...10, step: 1, divider: false)
                        .disabled(!fullEnabled).opacity(sectionOpacity(fullEnabled))
                }

                GeistSection(
                    title: "HUD Tests",
                    footer: "Runs the real notch animation on the current target display. If an external screen is using Dynamic Island mode, the battery HUD is sent there first."
                ) {
                    GeistRow {
                        Button { batteryStatusViewModel.triggerTestHUD(kind: .charging) } label: {
                            Label("Test charging HUD", systemImage: "bolt.fill")
                        }
                        .buttonStyle(.geist).disabled(!chargingEnabled)
                    }
                    GeistRow {
                        Button { batteryStatusViewModel.triggerTestHUD(kind: .lowBattery) } label: {
                            Label("Test low battery HUD", systemImage: "battery.25")
                        }
                        .buttonStyle(.geist).disabled(!lowEnabled)
                    }
                    GeistRow(divider: false) {
                        Button { batteryStatusViewModel.triggerTestHUD(kind: .fullBattery) } label: {
                            Label("Test full battery HUD", systemImage: "battery.100")
                        }
                        .buttonStyle(.geist).disabled(!fullEnabled)
                    }
                }

                GeistSection(title: "Low Battery") {
                    GeistSegmentedRow(title: "Low battery style", selection: $lowBatteryHUDStyle) {
                        ForEach(BatteryNotificationStyle.allCases) { Text($0.title).tag($0) }
                    }
                    GeistRow {
                        Text("Compact matches the charging HUD. Standard uses the expanded DynamicNotch-style card.")
                            .font(Geist.Typography.caption).foregroundStyle(Geist.Colors.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    GeistSliderRow(title: "Low battery threshold", valueLabel: "\(lowBatteryHUDThreshold)%", value: lowBatteryThresholdBinding, range: 5...30, step: 1, divider: false)
                }
                .disabled(!lowEnabled).opacity(sectionOpacity(lowEnabled))

                GeistSection(title: "Full Battery") {
                    GeistSegmentedRow(title: "Full battery style", selection: $fullBatteryHUDStyle) {
                        ForEach(BatteryNotificationStyle.allCases) { Text($0.title).tag($0) }
                    }
                    GeistRow {
                        Text("Compact keeps the alert inline. Standard uses the taller full-charge HUD with the charging animation.")
                            .font(Geist.Typography.caption).foregroundStyle(Geist.Colors.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    GeistSliderRow(title: "Full charge threshold", valueLabel: "\(fullBatteryHUDThreshold)%", value: fullBatteryThresholdBinding, range: 80...100, step: 1, divider: false)
                }
                .disabled(!fullEnabled).opacity(sectionOpacity(fullEnabled))
            } else {
                GeistSection {
                    GeistRow(divider: false) {
                        VStack(spacing: Geist.Spacing.sm) {
                            Image("battery.100percent.slash")
                                .font(.title)
                                .foregroundStyle(Geist.Colors.mute)
                            Text("Battery settings and information are only available on MacBooks")
                                .font(Geist.Typography.body)
                                .foregroundStyle(Geist.Colors.body)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Geist.Spacing.lg)
                    }
                }
            }
        }
    }
}

struct Downloads: View {
    @Default(.selectedDownloadIndicatorStyle) var selectedDownloadIndicatorStyle
    @Default(.selectedDownloadIconStyle) var selectedDownloadIconStyle

    var body: some View {
        GeistSettingsPage(title: "Downloads") {
            GeistSection(
                title: "Download Detection",
                footer: "Monitor your Downloads folder for Chromium-style downloads (.crdownload files) and show a live activity in the Dynamic Island while downloads are in progress."
            ) {
                GeistToggleRow(title: "Enable download detection", isOn: geistBinding(.enableDownloadListener))
                GeistRow(divider: false) {
                    VStack(alignment: .leading, spacing: Geist.Spacing.sm) {
                        Text("Download indicator style")
                            .font(Geist.Typography.bodyStrong)
                            .foregroundStyle(Geist.Colors.ink)
                        HStack(spacing: Geist.Spacing.md) {
                            DownloadStyleButton(
                                style: .progress,
                                isSelected: selectedDownloadIndicatorStyle == .progress,
                                disabled: !Defaults[.enableDownloadListener]
                            ) {
                                selectedDownloadIndicatorStyle = .progress
                            }
                            DownloadStyleButton(
                                style: .circle,
                                isSelected: selectedDownloadIndicatorStyle == .circle,
                                disabled: !Defaults[.enableDownloadListener]
                            ) {
                                selectedDownloadIndicatorStyle = .circle
                            }
                        }
                    }
                }
            }
        }
    }

    struct DownloadStyleButton: View {
        let style: DownloadIndicatorStyle
        let isSelected: Bool
        let disabled: Bool
        let action: () -> Void

        @State private var isHovering = false

        var body: some View {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
                        )

                    if style == .progress {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                            .frame(width: 40)
                    } else {
                        SpinningCircleDownloadView()
                    }
                }
                .frame(width: 80, height: 60)
                .onHover { hovering in
                    if !disabled {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isHovering = hovering
                        }
                    }
                }

                Text(style.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 100)
                    .foregroundStyle(disabled ? .secondary : .primary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !disabled {
                    action()
                }
            }
            .opacity(disabled ? 0.5 : 1.0)
        }

        private var backgroundColor: Color {
            if disabled { return Color(nsColor: .controlBackgroundColor) }
            if isSelected { return Color.accentColor.opacity(0.1) }
            if isHovering { return Color.primary.opacity(0.05) }
            return Color(nsColor: .controlBackgroundColor)
        }

        private var borderColor: Color {
            if isSelected { return Color.accentColor }
            if isHovering { return Color.primary.opacity(0.1) }
            return Color.clear
        }
    }
}

final class HUDPreviewViewModel: ObservableObject {
    @Published var level: Float = 0
    @Published var iconName: String = "speaker.wave.3.fill"

    private var cancellables = Set<AnyCancellable>()

    init() {
        setup()
    }

    private func setup() {
        // Ensure controllers are active
        SystemVolumeController.shared.start()
        SystemBrightnessController.shared.start()
        SystemKeyboardBacklightController.shared.start()

        // Initial state from volume
        let vol = SystemVolumeController.shared.currentVolume
        self.level = vol
        if vol <= 0.01 { self.iconName = "speaker.slash.fill" }
        else if vol < 0.33 { self.iconName = "speaker.wave.1.fill" }
        else if vol < 0.66 { self.iconName = "speaker.wave.2.fill" }
        else { self.iconName = "speaker.wave.3.fill" }

        // Listeners
        NotificationCenter.default.publisher(for: .systemVolumeDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                if let vol = info["value"] as? Float {
                    self.level = vol
                    if vol <= 0.01 { self.iconName = "speaker.slash.fill" }
                    else if vol < 0.33 { self.iconName = "speaker.wave.1.fill" }
                    else if vol < 0.66 { self.iconName = "speaker.wave.2.fill" }
                    else { self.iconName = "speaker.wave.3.fill" }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .systemBrightnessDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                if let val = info["value"] as? Float {
                    self.level = val
                    self.iconName = "sun.max.fill"
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .keyboardBacklightDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                if let val = info["value"] as? Float {
                    self.level = val
                    self.iconName = val > 0.5 ? "light.max" : "light.min"
                }
            }
            .store(in: &cancellables)
    }
}

private struct HUDAndOSDSettingsView: View {
    @State private var selectedTab: Tab = {
        if Defaults[.enableSystemHUD] { return .hud }
        if Defaults[.enableCustomOSD] { return .osd }
        if Defaults[.enableVerticalHUD] { return .vertical }
        if Defaults[.enableCircularHUD] { return .circular }
        return .hud
    }()
    @Default(.enableSystemHUD) var enableSystemHUD
    @Default(.enableCustomOSD) var enableCustomOSD
    @Default(.enableVerticalHUD) var enableVerticalHUD
    @Default(.enableCircularHUD) var enableCircularHUD
    @Default(.verticalHUDPosition) var verticalHUDPosition
    @Default(.enableVolumeHUD) var enableVolumeHUD
    @Default(.enableBrightnessHUD) var enableBrightnessHUD
    @Default(.enableKeyboardBacklightHUD) var enableKeyboardBacklightHUD
    @Default(.verticalHUDShowValue) var verticalHUDShowValue
    @Default(.verticalHUDInteractive) var verticalHUDInteractive
    @Default(.verticalHUDHeight) var verticalHUDHeight
    @Default(.verticalHUDWidth) var verticalHUDWidth
    @Default(.verticalHUDPadding) var verticalHUDPadding
    @Default(.verticalHUDUseAccentColor) var verticalHUDUseAccentColor
    @Default(.verticalHUDMaterial) var verticalHUDMaterial
    @Default(.verticalHUDLiquidGlassCustomizationMode) var verticalHUDLiquidGlassCustomizationMode
    @Default(.verticalHUDLiquidGlassVariant) var verticalHUDLiquidGlassVariant

    // Circular HUD Props
    @Default(.circularHUDShowValue) var circularHUDShowValue
    @Default(.circularHUDSize) var circularHUDSize
    @Default(.circularHUDStrokeWidth) var circularHUDStrokeWidth
    @Default(.circularHUDUseAccentColor) var circularHUDUseAccentColor
    @StateObject private var previewModel = HUDPreviewViewModel()
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared

    private enum Tab: String, CaseIterable, Identifiable {
        case hud = "Dynamic Island HUD"
        case osd = "Custom OSD"
        case vertical = "Vertical Bar"
        case circular = "Circular"

        var id: String { rawValue }
    }

    private var paneBackgroundColor: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private var availableVerticalMaterials: [OSDMaterial] {
        if #available(macOS 26.0, *) {
            return OSDMaterial.allCases
        }
        return OSDMaterial.allCases.filter { $0 != .liquid }
    }

    private var verticalLiquidVariantBinding: Binding<Double> {
        Binding(
            get: { Double(verticalHUDLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                verticalHUDLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    var body: some View {
        GeistSettingsPage(title: "Controls") {
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Geist.Spacing.sm) {
                HUDSelectionCard(
                    title: String(localized: "Dynamic Island"),
                    isSelected: selectedTab == .hud,
                    action: {
                        selectedTab = .hud
                        enableSystemHUD = true
                        enableCustomOSD = false
                        enableVerticalHUD = false
                        enableCircularHUD = false
                    }
                ) {
                    VStack {
                        Capsule()
                            .fill(Color.black)
                            .frame(width: 64, height: 20)
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                            .overlay {
                                HStack(spacing: 6) {
                                    Image(systemName: previewModel.iconName)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 12)

                                    GeometryReader { geo in
                                        Capsule()
                                            .fill(Color.white.opacity(0.2))
                                            .overlay(alignment: .leading) {
                                                Capsule()
                                                    .fill(Color.white)
                                                    .frame(width: geo.size.width * CGFloat(previewModel.level))
                                                    .animation(.spring(response: 0.3), value: previewModel.level)
                                            }
                                    }
                                    .frame(height: 4)
                                }
                                .padding(.horizontal, 8)
                            }
                    }
                }

                HUDSelectionCard(
                    title: String(localized: "Custom OSD"),
                    isSelected: selectedTab == .osd,
                    action: {
                        selectedTab = .osd
                        enableCustomOSD = true
                        enableSystemHUD = false
                        enableVerticalHUD = false
                        enableCircularHUD = false
                    }
                ) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: previewModel.iconName)
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                                    .symbolRenderingMode(.hierarchical)
                                    .contentTransition(.symbolEffect(.replace))

                                GeometryReader { geo in
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.2))
                                        .overlay(alignment: .leading) {
                                            Capsule()
                                                .fill(Color.primary)
                                                .frame(width: geo.size.width * CGFloat(previewModel.level))
                                                .animation(.spring(response: 0.3), value: previewModel.level)
                                        }
                                }
                                .frame(width: 36, height: 4)
                            }
                        }
                        .frame(width: 44, height: 44)
                }

                HUDSelectionCard(
                    title: String(localized: "Vertical Bar"),
                    isSelected: selectedTab == .vertical,
                    action: {
                        selectedTab = .vertical
                        enableVerticalHUD = true
                        enableSystemHUD = false
                        enableCustomOSD = false
                        enableCircularHUD = false
                    }
                ) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                        .overlay {
                            VStack {
                                GeometryReader { geo in
                                    VStack {
                                        Spacer()
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.white)
                                            .frame(height: max(0, geo.size.height * CGFloat(previewModel.level)))
                                            .animation(.spring(response: 0.3), value: previewModel.level)
                                    }
                                }
                                .mask(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .padding(.bottom, 2)

                                Image(systemName: previewModel.iconName)
                                    .font(.system(size: 9))
                                    .foregroundStyle(previewModel.level > 0.15 ? .black : .secondary)
                                    .symbolRenderingMode(.hierarchical)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .padding(4)
                        }
                        .frame(width: 22, height: 54)
                }

                HUDSelectionCard(
                    title: String(localized: "Circular"),
                    isSelected: selectedTab == .circular,
                    action: {
                        selectedTab = .circular
                        enableCircularHUD = true
                        enableSystemHUD = false
                        enableCustomOSD = false
                        enableVerticalHUD = false
                    }
                ) {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: CGFloat(previewModel.level))
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.3), value: previewModel.level)
                        Image(systemName: previewModel.iconName)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                            .symbolRenderingMode(.hierarchical)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .frame(width: 44, height: 44)
                }
            }
            .padding(.top, 8)
            }

            switch selectedTab {
            case .hud:
                HUD()
            case .osd:
                if #available(macOS 15.0, *) {
                    CustomOSDSettings()
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)

                        Text("macOS 15 or later required")
                            .font(.headline)

                        Text("Custom OSD feature requires macOS 15 or later.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            case .vertical:
                verticalSections

            case .circular:
                circularSections
            }

            // Step size controls (shared across all HUD variants)
            HUDStepSizeSection()
        }
        .onAppear {
            if #unavailable(macOS 26.0), verticalHUDMaterial == .liquid {
                verticalHUDMaterial = .frosted
                verticalHUDLiquidGlassCustomizationMode = .standard
            }
        }
    }

    @ViewBuilder
    private var hudControlsSection: some View {
        if accessibilityPermission.isAuthorized {
            GeistSection(title: "Controls", footer: "Choose which system controls should display HUD notifications.") {
                GeistToggleRow(title: "Volume HUD", isOn: $enableVolumeHUD)
                GeistToggleRow(title: "Brightness HUD", isOn: $enableBrightnessHUD)
                GeistToggleRow(title: "Keyboard Backlight HUD", isOn: $enableKeyboardBacklightHUD, divider: false)
            }
        }
    }

    @ViewBuilder
    private var verticalSections: some View {
        if !accessibilityPermission.isAuthorized {
            SettingsPermissionCallout(
                message: "Accessibility permission is needed to intercept system controls for the Vertical HUD.",
                requestAction: { accessibilityPermission.requestAuthorizationPrompt() },
                openSettingsAction: { accessibilityPermission.openSystemSettings() }
            )
        }
        hudControlsSection

        GeistSection(title: "Behavior & Style") {
            GeistToggleRow(title: "Show Percentage", isOn: $verticalHUDShowValue)
            GeistToggleRow(title: "Use Accent Color", isOn: $verticalHUDUseAccentColor)
            GeistToggleRow(title: "Interactive (Drag to Change)", isOn: $verticalHUDInteractive)
            GeistPickerRow(title: "Material", selection: $verticalHUDMaterial) {
                ForEach(availableVerticalMaterials, id: \.self) { Text($0.rawValue).tag($0) }
            }
            if verticalHUDMaterial == .liquid {
                if #available(macOS 26.0, *) {
                    GeistSegmentedRow(title: "Glass mode", selection: $verticalHUDLiquidGlassCustomizationMode) {
                        ForEach(GlassCustomizationMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if verticalHUDLiquidGlassCustomizationMode == .customLiquid {
                        GeistSliderRow(title: "Custom liquid variant", valueLabel: "v\(verticalHUDLiquidGlassVariant.rawValue)", value: verticalLiquidVariantBinding, range: liquidVariantRange, step: 1)
                    }
                } else {
                    GeistRow {
                        Text("Custom Liquid is available on macOS 26 or later.")
                            .font(Geist.Typography.caption).foregroundStyle(Geist.Colors.mute)
                    }
                }
            }
            GeistToggleRow(title: "Color-coded Volume", isOn: geistBinding(.useColorCodedVolumeDisplay), divider: Defaults[.useColorCodedVolumeDisplay])
            if Defaults[.useColorCodedVolumeDisplay] {
                GeistToggleRow(title: "Smooth color transitions", isOn: geistBinding(.useSmoothColorGradient), divider: false)
            }
        }

        GeistSection(title: "Position", footer: "Choose directly on which side of the screen the vertical bar appears.") {
            GeistPickerRow(title: "HUD Position", selection: $verticalHUDPosition) {
                Text("Left").tag("left")
                Text("Right").tag("right")
            }
            GeistSliderRow(title: "Screen Padding", valueLabel: "\(Int(verticalHUDPadding))px", value: $verticalHUDPadding, range: 0...100, step: 4, divider: false)
        }

        GeistSection(title: "Dimensions") {
            GeistSliderRow(title: "Width", valueLabel: "\(Int(verticalHUDWidth))px", value: $verticalHUDWidth, range: 24...80, step: 2)
            GeistSliderRow(title: "Height", valueLabel: "\(Int(verticalHUDHeight))px", value: $verticalHUDHeight, range: 100...500, step: 10)
            GeistRow(divider: false) {
                Button("Reset to Default") {
                    verticalHUDWidth = 36
                    verticalHUDHeight = 160
                    verticalHUDPadding = 24
                }
                .buttonStyle(.geist)
            }
        }
    }

    @ViewBuilder
    private var circularSections: some View {
        if !accessibilityPermission.isAuthorized {
            SettingsPermissionCallout(
                message: "Accessibility permission is needed to intercept system controls for the Circular HUD.",
                requestAction: { accessibilityPermission.requestAuthorizationPrompt() },
                openSettingsAction: { accessibilityPermission.openSystemSettings() }
            )
        }
        hudControlsSection

        GeistSection(title: "Style") {
            GeistToggleRow(title: "Show Percentage", isOn: $circularHUDShowValue)
            GeistToggleRow(title: "Use Accent Color", isOn: $circularHUDUseAccentColor)
            GeistToggleRow(title: "Color-coded Volume", isOn: geistBinding(.useColorCodedVolumeDisplay), divider: Defaults[.useColorCodedVolumeDisplay])
            if Defaults[.useColorCodedVolumeDisplay] {
                GeistToggleRow(title: "Smooth color transitions", isOn: geistBinding(.useSmoothColorGradient), divider: false)
            }
        }

        GeistSection(title: "Dimensions") {
            GeistSliderRow(title: "Size", valueLabel: "\(Int(circularHUDSize))px", value: $circularHUDSize, range: 40...200, step: 5)
            GeistSliderRow(title: "Line Width", valueLabel: "\(Int(circularHUDStrokeWidth))px", value: $circularHUDStrokeWidth, range: 2...16, step: 1)
            GeistRow(divider: false) {
                Button("Reset to Default") {
                    circularHUDSize = 65
                    circularHUDStrokeWidth = 4
                }
                .buttonStyle(.geist)
            }
        }
    }
}

// MARK: - HUD Step Size Settings Section

private struct HUDStepSizeSection: View {
    @Default(.volumeStepPercent) var volumeStepPercent
    @Default(.volumeFineStepPercent) var volumeFineStepPercent
    @Default(.brightnessStepPercent) var brightnessStepPercent
    @Default(.brightnessFineStepPercent) var brightnessFineStepPercent

    var body: some View {
        GeistSection(title: "Step size", footer: "Percent change per key press. Fine step applies when holding Shift+Option.") {
            GeistStepperRow(title: "Volume step", value: $volumeStepPercent, range: 1...25, valueLabel: "\(volumeStepPercent)%")
            GeistStepperRow(title: "Volume fine step", value: $volumeFineStepPercent, range: 1...25, valueLabel: "\(volumeFineStepPercent)%")
            GeistStepperRow(title: "Brightness step", value: $brightnessStepPercent, range: 1...25, valueLabel: "\(brightnessStepPercent)%")
            GeistStepperRow(title: "Brightness fine step", value: $brightnessFineStepPercent, range: 1...25, divider: false, valueLabel: "\(brightnessFineStepPercent)%")
        }
    }
}

private struct HUDSelectionCard<Preview: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let preview: Preview

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    isSelected ? Color.accentColor : Color.clear,
                                    lineWidth: 2.5
                                )
                        )
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)

                    preview
                }
                .frame(width: 92, height: 62)

                VStack(spacing: 4) {
                    Text(title)
                        .font(Geist.Typography.bodyStrong)
                        .foregroundStyle(isSelected ? .primary : .secondary)

                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 4, height: 4)
                    } else {
                        Color.clear
                            .frame(width: 4, height: 4)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

private struct DevicesSettingsView: View {
    @Default(.progressBarStyle) var progressBarStyle

    private var colorCodingDisabled: Bool {
        progressBarStyle == .segmented
    }

    private var batteryFooter: String {
        if progressBarStyle == .segmented {
            return "Color-coded fills are unavailable in Segmented mode. Switch to Hierarchical or Gradient inside Controls › Dynamic Island to adjust advanced options."
        } else if Defaults[.useSmoothColorGradient] {
            return "Smooth transitions blend Green (0–60%), Yellow (60–85%), and Red (85–100%) through the entire fill. Adjust gradient behavior from Controls › Dynamic Island."
        } else {
            return "Discrete transitions snap between Green (0–60%), Yellow (60–85%), and Red (85–100%)."
        }
    }

    var body: some View {
        GeistSettingsPage(title: "Devices") {
            GeistSection(
                title: "Bluetooth Audio Devices",
                footer: "Displays a HUD notification when Bluetooth audio devices (headphones, AirPods, speakers) connect, showing device name and battery level."
            ) {
                GeistToggleRow(title: "Show Bluetooth device connections", isOn: geistBinding(.showBluetoothDeviceConnections))
                GeistToggleRow(title: "Use circular battery indicator", isOn: geistBinding(.useCircularBluetoothBatteryIndicator))
                GeistToggleRow(title: "Show battery percentage text in HUD", isOn: geistBinding(.showBluetoothBatteryPercentageText))
                GeistToggleRow(title: "Scroll device name in HUD", isOn: geistBinding(.showBluetoothDeviceNameMarquee), divider: false)
            }

            GeistSection(title: "Battery Indicator Styling", footer: batteryFooter) {
                GeistToggleRow(title: "Color-coded battery display", isOn: geistBinding(.useColorCodedBatteryDisplay), divider: false)
                    .disabled(colorCodingDisabled)
            }
        }
    }
}

struct HUD: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Default(.inlineHUD) var inlineHUD
    @Default(.progressBarStyle) var progressBarStyle
    @Default(.enableSystemHUD) var enableSystemHUD
    @Default(.enableVolumeHUD) var enableVolumeHUD
    @Default(.enableBrightnessHUD) var enableBrightnessHUD
    @Default(.enableKeyboardBacklightHUD) var enableKeyboardBacklightHUD
    @Default(.systemHUDSensitivity) var systemHUDSensitivity
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared

    private var hasAccessibilityPermission: Bool {
        accessibilityPermission.isAuthorized
    }

    private var colorCodingDisabled: Bool {
        progressBarStyle == .segmented
    }

    private var progressBarsFooter: String {
        if colorCodingDisabled {
            return "Color-coded fills and smooth gradients are unavailable in Segmented mode. Switch to Hierarchical or Gradient to adjust these options."
        } else if Defaults[.useSmoothColorGradient] {
            return "Smooth transitions blend Green (0–60%), Yellow (60–85%), and Red (85–100%) through the entire fill."
        } else {
            return "Discrete transitions snap between Green (0–60%), Yellow (60–85%), and Red (85–100%)."
        }
    }

    var body: some View {
        Group {
            if !hasAccessibilityPermission {
                SettingsPermissionCallout(
                    message: "Accessibility permission lets Dynamic Island replace the native volume, brightness, and keyboard HUDs.",
                    requestAction: { accessibilityPermission.requestAuthorizationPrompt() },
                    openSettingsAction: { accessibilityPermission.openSystemSettings() }
                )
            }

            if enableSystemHUD && !Defaults[.enableCustomOSD] && hasAccessibilityPermission {
                GeistSection(title: "Controls", footer: "Choose which system controls should display HUD notifications.") {
                    GeistToggleRow(title: "Volume HUD", isOn: $enableVolumeHUD)
                    GeistToggleRow(title: "Brightness HUD", isOn: $enableBrightnessHUD)
                    GeistToggleRow(title: "Keyboard Backlight HUD", isOn: $enableKeyboardBacklightHUD, divider: false)
                }
            }

            GeistSection(title: "Audio feedback", footer: "Requires Accessibility permission so Dynamic Island can intercept the hardware volume keys.") {
                GeistToggleRow(title: "Play feedback when volume is changed", isOn: geistBinding(.playVolumeChangeFeedback), divider: false)
                    .help("Plays the supplied feedback clip whenever you press the hardware volume keys.")
            }

            GeistSection(title: "Dynamic Island Progress Bars", footer: progressBarsFooter) {
                GeistToggleRow(title: "Color-coded volume display", isOn: geistBinding(.useColorCodedVolumeDisplay))
                    .disabled(colorCodingDisabled)
                if !colorCodingDisabled && (Defaults[.useColorCodedBatteryDisplay] || Defaults[.useColorCodedVolumeDisplay]) {
                    GeistToggleRow(title: "Smooth color transitions", isOn: geistBinding(.useSmoothColorGradient))
                }
                GeistToggleRow(title: "Show percentages beside progress bars", isOn: geistBinding(.showProgressPercentages), divider: false)
            }

            GeistSection(title: "Appearance") {
                GeistPickerRow(title: "HUD style", selection: $inlineHUD) {
                    Text("Default").tag(false)
                    Text("Inline").tag(true)
                }
                .onChange(of: Defaults[.inlineHUD]) {
                    if Defaults[.inlineHUD] {
                        withAnimation {
                            Defaults[.systemEventIndicatorShadow] = false
                            Defaults[.progressBarStyle] = .hierarchical
                        }
                    }
                }
                GeistPickerRow(title: "Progressbar style", selection: $progressBarStyle) {
                    Text("Hierarchical").tag(ProgressBarStyle.hierarchical)
                    Text("Gradient").tag(ProgressBarStyle.gradient)
                    Text("Segmented").tag(ProgressBarStyle.segmented)
                }
                GeistToggleRow(title: "Enable glowing effect", isOn: geistBinding(.systemEventIndicatorShadow))
                GeistToggleRow(title: "Use accent color", isOn: geistBinding(.systemEventIndicatorUseAccent), divider: false)
            }
        }
        .onAppear {
            accessibilityPermission.refreshStatus()
        }
        .onChange(of: accessibilityPermission.isAuthorized) { _, granted in
            if !granted {
                enableSystemHUD = false
            }
        }
    }
}

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @Default(.showShuffleAndRepeat) private var showShuffleAndRepeat
    @Default(.musicSkipBehavior) private var musicSkipBehavior
    @Default(.musicControlWindowEnabled) private var musicControlWindowEnabled
    @Default(.showSneakPeekOnTrackChange) private var showSneakPeekOnTrackChange
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.autoHideInactiveNotchMediaPlayer) private var autoHideInactiveNotchMediaPlayer
    @Default(.parallaxEffectIntensity) private var parallaxEffectIntensity

    
    @ObservedObject private var musicManager = MusicManager.shared

    private var isAppleMusicActive: Bool {
        musicManager.bundleIdentifier == "com.apple.Music"
    }

    private var standardControlsSuppressed: Bool {
        !showStandardMediaControls && !enableMinimalisticUI
    }

    private var visibilityNote: String? {
        if enableMinimalisticUI {
            return "Disable Minimalistic UI to configure the standard notch media controls."
        }
        if standardControlsSuppressed {
            return "Standard notch media controls are hidden. Re-enable the toggle above to restore them."
        }
        if !autoHideInactiveNotchMediaPlayer {
            return "When disabled, the notch music player stays visible with placeholder metadata even when playback is inactive."
        }
        return nil
    }

    var body: some View {
        GeistSettingsPage(title: "Media") {
            GeistSection(title: "Media Source") {
                GeistPickerRow(title: "Music Source", selection: $mediaController, divider: false) {
                    ForEach(availableMediaControllers) { Text($0.rawValue).tag($0) }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(name: Notification.Name.mediaControllerChanged, object: nil)
                }
            }
            mediaSourceFooter()

            if mediaController == .spotify {
                SpotifyAuthSettingsSection()
            }

            GeistSection(title: "Dynamic Island Visibility") {
                GeistToggleRow(title: "Show media controls in Dynamic Island", isOn: $showStandardMediaControls)
                    .disabled(enableMinimalisticUI)
                GeistToggleRow(title: "Auto-hide inactive notch media player", isOn: $autoHideInactiveNotchMediaPlayer, divider: visibilityNote != nil)
                    .disabled(enableMinimalisticUI || !showStandardMediaControls)
                if let visibilityNote {
                    GeistRow(divider: false) {
                        Text(visibilityNote)
                            .font(Geist.Typography.caption).foregroundStyle(Geist.Colors.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            GeistSection(title: "Media controls", badge: "Beta") {
                GeistToggleRow(title: "Enable customizable controls", isOn: $showShuffleAndRepeat, divider: showShuffleAndRepeat)
                if showShuffleAndRepeat {
                    GeistToggleRow(title: "Show \"Change Media Output\" control", isOn: geistBinding(.showMediaOutputControl))
                        .help("Adds the AirPlay/route picker button back to the customizable controls palette.")
                    GeistRow(divider: false) {
                        MusicSlotConfigurationView()
                    }
                } else {
                    GeistRow(divider: false) {
                        Text("Turn on customizable controls to rearrange media buttons.")
                            .font(Geist.Typography.caption).foregroundStyle(Geist.Colors.body)
                    }
                }
            }
            .disabled(!showStandardMediaControls)
            .opacity(showStandardMediaControls ? 1 : 0.5)

            GeistSection(title: "Fullscreen", badge: "Beta") {
                GeistPickerRow(title: "Hide Dynamic Island", selection: $hideNotchOption, divider: false) {
                    Text("Always hide in fullscreen").tag(HideNotchOption.always)
                    Text("Hide only when NowPlaying app is in fullscreen").tag(HideNotchOption.nowPlayingOnly)
                    Text("Never hide").tag(HideNotchOption.never)
                }
                .onChange(of: hideNotchOption) {
                    Defaults[.enableFullscreenMediaDetection] = hideNotchOption != .never
                }
            }
        }
    }

    @ViewBuilder
    private func mediaSourceFooter() -> some View {
        if MusicManager.shared.isNowPlayingDeprecated {
            HStack(spacing: 0) {
                Text("YouTube Music requires this third-party app to be installed: ")
                    .foregroundStyle(Geist.Colors.mute)
                Link("github.com/th-ch/youtube-music", destination: URL(string: "https://github.com/th-ch/youtube-music")!)
                    .foregroundStyle(Geist.Colors.accent)
            }
            .font(Geist.Typography.caption)
            .padding(.leading, Geist.Spacing.xxs)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: Geist.Spacing.xxs) {
                Text(String(localized: "'Now Playing' was the only option on previous versions and works with all media apps."))
                Text(String(localized: "Uses macOS Now Playing when the Amazon Music app is the active media source. Playback controls follow the system Now Playing target. Scrubbing the timeline may not work if the Amazon Music app does not support remote seek."))
            }
            .font(Geist.Typography.caption)
            .foregroundStyle(Geist.Colors.mute)
            .padding(.leading, Geist.Spacing.xxs)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Only show controller options that are available on this macOS version
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }

    private var unavailableBlurRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Enable media panel blur")
                .foregroundStyle(.secondary)
            Text("Only applies when Material is set to Frosted Glass.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var customLiquidBlurRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Enable media panel blur")
                .foregroundStyle(.secondary)
            Text("Custom liquid glass already renders with Apple's liquid material, so this option is managed automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CalendarSettings: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) var showCalendar: Bool
    @Default(.enableReminderLiveActivity) var enableReminderLiveActivity
    @Default(.reminderPresentationStyle) var reminderPresentationStyle
    @Default(.reminderLeadTime) var reminderLeadTime
    @Default(.reminderSneakPeekDuration) var reminderSneakPeekDuration
    @Default(.hideAllDayEvents) var hideAllDayEvents
    @Default(.hideCompletedReminders) var hideCompletedReminders
    @Default(.calendarTabLayout) var calendarTabLayout
    @Default(.showFullEventTitles) var showFullEventTitles
    @Default(.autoScrollToNextEvent) var autoScrollToNextEvent
    @Default(.enableThirdPartyCalendarApp) private var enableThirdPartyCalendarApp
    @Default(.selectedCalendarApp) private var selectedCalendarApp
    @Default(.fantasticalDefaultView) private var fantasticalDefaultView

    private enum CalendarLookaheadOption: String, CaseIterable, Identifiable {
        case mins15 = "15m"
        case mins30 = "30m"
        case hour1 = "1h"
        case hours3 = "3h"
        case hours6 = "6h"
        case hours12 = "12h"
        case restOfDay = "rest_of_day"
        case allTime = "all_time"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mins15: return "15 mins"
            case .mins30: return "30 mins"
            case .hour1: return "1 hour"
            case .hours3: return "3 hours"
            case .hours6: return "6 hours"
            case .hours12: return "12 hours"
            case .restOfDay: return "Rest of the day"
            case .allTime: return "All time"
            }
        }
    }

    var body: some View {
        GeistSettingsPage(title: "Calendar") {
            if !calendarManager.hasCalendarAccess || !calendarManager.hasReminderAccess {
                GeistSection {
                    GeistRow(divider: false) {
                        VStack(alignment: .leading, spacing: Geist.Spacing.sm) {
                            Text("Calendar or Reminder access is denied. Please enable it in System Settings.")
                                .font(Geist.Typography.body)
                                .foregroundStyle(Geist.Colors.error)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: Geist.Spacing.xs) {
                                Button("Request Access") {
                                    Task {
                                        await calendarManager.checkCalendarAuthorization()
                                        await calendarManager.checkReminderAuthorization()
                                    }
                                }
                                .buttonStyle(.geistProminent)
                                Button("Open System Settings") {
                                    if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                                        NSWorkspace.shared.open(settingsURL)
                                    }
                                }
                                .buttonStyle(.geist)
                            }
                        }
                    }
                }
            } else {
                GeistSection(title: "Permissions") {
                    GeistLabeledRow(title: "Calendars") {
                        Text(statusText(for: calendarManager.calendarAuthorizationStatus))
                            .font(Geist.Typography.body)
                            .foregroundStyle(color(for: calendarManager.calendarAuthorizationStatus))
                    }
                    GeistLabeledRow(title: "Reminders", divider: false) {
                        Text(statusText(for: calendarManager.reminderAuthorizationStatus))
                            .font(Geist.Typography.body)
                            .foregroundStyle(color(for: calendarManager.reminderAuthorizationStatus))
                    }
                }

                GeistSection {
                    GeistToggleRow(title: "Show calendar", isOn: geistBinding(.showCalendar), divider: false)
                }

                GeistSection(
                    title: "Notch Tab",
                    footer: "Choose how the date picker appears in the notch Calendar tab."
                ) {
                    GeistPickerRow(title: "Calendar layout", selection: $calendarTabLayout, divider: false) {
                        ForEach(CalendarTabLayout.allCases) { Text($0.displayName).tag($0) }
                    }
                }

                GeistSection(title: "Event List") {
                    GeistToggleRow(title: "Hide completed reminders", isOn: $hideCompletedReminders)
                    GeistToggleRow(title: "Show full event titles", isOn: $showFullEventTitles)
                    GeistToggleRow(title: "Auto-scroll to next event", isOn: $autoScrollToNextEvent, divider: false)
                }

                GeistSection(
                    title: "All-Day Events",
                    footer: "Turn this off to include all-day entries in the notch calendar and reminder live activity."
                ) {
                    GeistToggleRow(title: "Hide all-day events", isOn: $hideAllDayEvents, divider: false)
                        .disabled(!showCalendar)
                }

                GeistSection(title: "Reminder Live Activity") {
                    GeistToggleRow(title: "Enable reminder live activity", isOn: $enableReminderLiveActivity)
                    GeistSegmentedRow(title: "Countdown style", selection: $reminderPresentationStyle) {
                        ForEach(ReminderPresentationStyle.allCases) { Text($0.displayName).tag($0) }
                    }
                    .disabled(!enableReminderLiveActivity)
                    GeistSliderRow(
                        title: "Notify before",
                        valueLabel: "\(reminderLeadTime) min",
                        value: Binding(get: { Double(reminderLeadTime) }, set: { reminderLeadTime = Int($0) }),
                        range: 1...60, step: 1
                    )
                    .disabled(!enableReminderLiveActivity)
                    GeistSliderRow(
                        title: "Sneak peek duration",
                        valueLabel: "\(Int(reminderSneakPeekDuration)) s",
                        value: $reminderSneakPeekDuration, range: 3...20, step: 1, divider: false
                    )
                    .disabled(!enableReminderLiveActivity)
                }

                GeistSection(
                    title: "Third-party Calendar Integration",
                    footer: "When enabled, clicking on calendar events will open the selected third-party calendar app instead of Apple Calendar."
                ) {
                    GeistToggleRow(title: "Enable third-party calendar app launch", isOn: $enableThirdPartyCalendarApp, divider: enableThirdPartyCalendarApp)
                    if enableThirdPartyCalendarApp {
                        GeistPickerRow(title: "Calendar App", selection: $selectedCalendarApp, divider: selectedCalendarApp == .fantastical) {
                            ForEach(ThirdPartyCalendarApp.allCases) { app in
                                HStack {
                                    AppIconImage(
                                        bundleIdentifiers: app.bundleIdentifiers,
                                        symbolFallback: app.fallbackIconName,
                                        symbolColor: app.fallbackIconColor
                                    )
                                    Text(app.displayName)
                                }
                                .tag(app)
                            }
                        }
                        if selectedCalendarApp == .fantastical {
                            GeistPickerRow(title: "Default View", selection: $fantasticalDefaultView, divider: false) {
                                ForEach(FantasticalViewStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                        }
                    }
                }

                calendarSelectionSections()
            }
        }
        .onAppear {
            Task {
                await calendarManager.checkCalendarAuthorization()
                await calendarManager.checkReminderAuthorization()
            }
        }
    }

    @ViewBuilder
    private func calendarSelectionSections() -> some View {
        let grouped = Dictionary(grouping: calendarManager.allCalendars, by: \.accountName)
        let sortedAccounts = grouped.keys.sorted()

        Text("Select Calendars".uppercased())
            .font(Geist.Typography.captionStrong)
            .foregroundStyle(Geist.Colors.mute)
            .tracking(0.6)
            .padding(.leading, Geist.Spacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)

        ForEach(sortedAccounts, id: \.self) { account in
            let accountCalendars = grouped[account] ?? []
            let allAccountSelected = accountCalendars.allSatisfy { calendarManager.getCalendarSelected($0) }

            GeistSection(title: account) {
                GeistToggleRow(title: "Select all", isOn: Binding(
                    get: { allAccountSelected },
                    set: { isSelected in
                        Task { await calendarManager.setCalendarsSelected(accountCalendars, isSelected: isSelected) }
                    }
                ), divider: !accountCalendars.isEmpty)
                .disabled(!showCalendar)

                ForEach(Array(accountCalendars.enumerated()), id: \.element.id) { index, calendar in
                    GeistRow(divider: index < accountCalendars.count - 1) {
                        HStack(spacing: Geist.Spacing.md) {
                            Circle()
                                .fill(Color(calendar.color))
                                .frame(width: 8, height: 8)
                            Text(calendar.title)
                                .font(Geist.Typography.bodyStrong)
                                .foregroundStyle(Geist.Colors.ink)
                            Spacer(minLength: Geist.Spacing.sm)
                            Toggle("", isOn: Binding(
                                get: { calendarManager.getCalendarSelected(calendar) },
                                set: { isSelected in
                                    Task { await calendarManager.setCalendarSelected(calendar, isSelected: isSelected) }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .disabled(!showCalendar)
                        }
                    }
                }
            }
        }
    }

    private func statusText(for status: EKAuthorizationStatus) -> String {
        switch status {
        case .fullAccess, .authorized: return String(localized: "Full Access")
        case .writeOnly: return String(localized: "Write Only")
        case .denied: return String(localized: "Denied")
        case .restricted: return String(localized: "Restricted")
        case .notDetermined: return String(localized: "Not Determined")
        @unknown default: return String(localized: "Unknown")
        }
    }

    private func color(for status: EKAuthorizationStatus) -> Color {
        switch status {
        case .fullAccess, .authorized: return .green
        case .writeOnly: return .yellow
        case .denied, .restricted: return .red
        case .notDetermined: return .secondary
        @unknown default: return .secondary
        }
    }
}

struct About: View {
    @State private var showBuildNumber: Bool = false
    let updaterController: SPUStandardUpdaterController
    @Environment(\.openWindow) var openWindow
    var body: some View {
        GeistSettingsPage(title: "About") {
            GeistSection(title: "Version info") {
                GeistLabeledRow(title: "Release name") {
                    Text(Defaults[.releaseName])
                        .font(Geist.Typography.body)
                        .foregroundStyle(Geist.Colors.body)
                }
                GeistLabeledRow(title: "Version", divider: false) {
                    HStack(spacing: 4) {
                        if showBuildNumber {
                            Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                                .foregroundStyle(Geist.Colors.mute)
                        }
                        Text(Bundle.main.releaseVersionNumber ?? "unknown")
                            .foregroundStyle(Geist.Colors.body)
                    }
                    .font(Geist.Typography.body)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { showBuildNumber.toggle() } }
                }
            }

            GeistSection(title: "Updates") {
                GeistRow(divider: false) {
                    UpdaterSettingsView(updater: updaterController.updater)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            GeistSection {
                Button {
                    NSWorkspace.shared.open(productPage)
                } label: {
                    GeistRow(divider: false) {
                        HStack(spacing: Geist.Spacing.sm) {
                            Image("Github")
                                .resizable()
                                .renderingMode(.template)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18, height: 18)
                                .foregroundStyle(Geist.Colors.ink)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("GitHub")
                                    .font(Geist.Typography.bodyStrong)
                                    .foregroundStyle(Geist.Colors.ink)
                                Text("Zaaacqwq/vibeIsland")
                                    .font(Geist.Typography.caption)
                                    .foregroundStyle(Geist.Colors.mute)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(Geist.Typography.caption)
                                .foregroundStyle(Geist.Colors.mute)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Text("Made with ❤️ by Zaaacqwq")
                .font(Geist.Typography.caption)
                .foregroundStyle(Geist.Colors.mute)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .toolbar {
            CheckForUpdatesView(updater: updaterController.updater)
        }
    }
}

struct Shelf: View {
    @Default(.quickShareProvider) var quickShareProvider
    @Default(.expandedDragDetection) var expandedDragDetection
    @Default(.copyOnDrag) var copyOnDrag
    @Default(.autoRemoveShelfItems) var autoRemoveShelfItems
    @StateObject private var quickShareService = QuickShareService.shared
    @ObservedObject private var fullDiskAccessPermission = FullDiskAccessPermissionStore.shared
    @ObservedObject private var shelfFolderAccessPermission = ShelfFolderAccessPermissionStore.shared

    private var hasDocumentsAndDownloadsAccess: Bool {
        shelfFolderAccessPermission.hasDocumentsAndDownloadsAccess
    }

    private var canEnableShelf: Bool {
        fullDiskAccessPermission.isAuthorized || hasDocumentsAndDownloadsAccess
    }

    private var selectedProvider: QuickShareProvider? {
        quickShareService.availableProviders.first(where: { $0.id == quickShareProvider })
    }

    init() {
        QuickShareService.shared.ensureDiscovered()
    }

    var body: some View {
        GeistSettingsPage(title: "Shelf") {
            if !canEnableShelf {
                SettingsPermissionCallout(
                    title: "Additional folder access required",
                    message: "Enable Full Disk Access, or grant access to both Documents and Downloads folders to use Shelf.",
                    icon: "folder.badge.questionmark",
                    iconColor: .orange,
                    requestButtonTitle: "Request Folder Access",
                    openSettingsButtonTitle: "Open Privacy & Security",
                    requestAction: { shelfFolderAccessPermission.requestAccessPrompt() },
                    openSettingsAction: { shelfFolderAccessPermission.openSystemSettings() }
                )
            }
            if !fullDiskAccessPermission.isAuthorized {
                SettingsPermissionCallout(
                    title: "Full Disk Access for global mode",
                    message: "Without Full Disk Access, Shelf can only read files from Documents and Downloads. Grant Full Disk Access to make Shelf work globally.",
                    icon: "externaldrive.fill",
                    iconColor: .purple,
                    requestButtonTitle: "Request Full Disk Access",
                    openSettingsButtonTitle: "Open Privacy & Security",
                    requestAction: { fullDiskAccessPermission.requestAccessPrompt() },
                    openSettingsAction: { fullDiskAccessPermission.openSystemSettings() }
                )
            }

            GeistSection(title: "General") {
                GeistToggleRow(title: "Enable shelf", isOn: geistBinding(.dynamicShelf))
                    .disabled(!canEnableShelf)
                GeistToggleRow(title: "Open shelf tab by default if items added", isOn: geistBinding(.openShelfByDefault))
                GeistToggleRow(title: "Expanded drag detection area", isOn: $expandedDragDetection)
                GeistToggleRow(title: "Copy items on drag", isOn: $copyOnDrag)
                GeistToggleRow(title: "Remove from shelf after dragging", isOn: $autoRemoveShelfItems, divider: false)
            }

            GeistSection(
                title: "Quick Share",
                footer: "Choose which service to use when sharing files from the shelf. Drag files onto the shelf or click the shelf button to pick files."
            ) {
                GeistPickerRow(title: "Quick Share Service", selection: $quickShareProvider, divider: selectedProvider != nil) {
                    ForEach(quickShareService.availableProviders, id: \.id) { provider in
                        HStack {
                            QuickShareProviderIconImage(provider: provider, size: 16)
                            Text(provider.id)
                        }
                        .tag(provider.id)
                    }
                }
                if let selectedProvider {
                    GeistRow(divider: false) {
                        HStack(spacing: Geist.Spacing.xs) {
                            QuickShareProviderIconImage(provider: selectedProvider, size: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Currently selected: \(selectedProvider.id)")
                                    .font(Geist.Typography.caption)
                                    .foregroundStyle(Geist.Colors.body)
                                Text("Files dropped on the shelf will be shared via this service")
                                    .font(Geist.Typography.caption)
                                    .foregroundStyle(Geist.Colors.mute)
                            }
                        }
                    }
                }
            }

            if quickShareProvider == "LocalSend" {
                LocalSendSettingsSection()
            }
        }
        .onAppear {
            fullDiskAccessPermission.refreshStatus()
            shelfFolderAccessPermission.refreshStatus()
        }
    }
}

// MARK: - LocalSend Settings Section

private struct LocalSendSettingsSection: View {
    @Default(.localSendDevicePickerGlassMode) private var glassMode
    @Default(.localSendDevicePickerLiquidGlassVariant) private var liquidGlassVariant

    var body: some View {
        GeistSection(
            title: "LocalSend Device Picker",
            footer: "Customize the appearance of the LocalSend device selection popup that appears when you drop files."
        ) {
            GeistPickerRow(title: "Device Picker Style", selection: $glassMode, divider: glassMode == .customLiquid) {
                ForEach(GlassCustomizationMode.allCases) { Text($0.localizedName).tag($0) }
            }
            if glassMode == .customLiquid {
                GeistPickerRow(title: "Liquid Glass Variant", selection: $liquidGlassVariant, divider: false) {
                    ForEach(LiquidGlassVariant.allCases) { Text("Variant \($0.rawValue)").tag($0) }
                }
            }
        }
    }
}

struct LiveActivitiesSettings: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    @ObservedObject var privacyManager = PrivacyIndicatorManager.shared
    @ObservedObject var doNotDisturbManager = DoNotDisturbManager.shared
    @ObservedObject private var fullDiskAccessPermission = FullDiskAccessPermissionStore.shared

    @Default(.enableScreenRecordingDetection) var enableScreenRecordingDetection
    @Default(.enableDoNotDisturbDetection) var enableDoNotDisturbDetection
    @Default(.focusIndicatorNonPersistent) var focusIndicatorNonPersistent
    @Default(.capsLockIndicatorTintMode) var capsLockTintMode
    @Default(.closedNotchActivityPriorityOrder) private var closedNotchActivityPriorityOrder
    @Default(.disabledClosedNotchActivities) private var disabledClosedNotchActivities

    @ViewBuilder
    private func statusLabel(dot: Color?, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            if let dot {
                Circle().fill(dot).frame(width: 8, height: 8)
            }
            Text(text).font(Geist.Typography.body).foregroundStyle(color)
        }
    }

    var body: some View {
        GeistSettingsPage(title: "Live Activities") {
            GeistSection(
                title: "Closed Notch Priority",
                footer: "Toggle each live activity on or off with its switch, and drag with the arrows to set priority. Temporary HUDs such as volume, brightness, notifications, and battery status always appear above this order. When two persistent activities are active, VibeIsland shows the two highest-priority items side by side."
            ) {
                let order = normalizedClosedNotchPriorityOrder
                ForEach(Array(order.enumerated()), id: \.element) { index, kind in
                    GeistRow {
                        HStack(spacing: Geist.Spacing.sm) {
                            Text("\(index + 1)")
                                .font(Geist.Typography.caption.monospacedDigit())
                                .foregroundStyle(Geist.Colors.mute)
                                .frame(width: 22, alignment: .trailing)
                            Toggle("", isOn: Binding(
                                get: { !disabledClosedNotchActivities.contains(kind) },
                                set: { isOn in
                                    if isOn { disabledClosedNotchActivities.remove(kind) }
                                    else { disabledClosedNotchActivities.insert(kind) }
                                }
                            ))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                            Label(kind.displayName, systemImage: kind.systemImage)
                                .labelStyle(.titleAndIcon)
                                .font(Geist.Typography.bodyStrong)
                                .foregroundStyle(disabledClosedNotchActivities.contains(kind) ? Geist.Colors.mute : Geist.Colors.ink)
                            Spacer()
                            HStack(spacing: 4) {
                                Button { moveClosedNotchActivity(kind, direction: -1) } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .buttonStyle(.borderless).disabled(index == 0).help("Raise priority")
                                Button { moveClosedNotchActivity(kind, direction: 1) } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .buttonStyle(.borderless).disabled(index == order.count - 1).help("Lower priority")
                            }
                            .foregroundStyle(Geist.Colors.body)
                        }
                    }
                }
                GeistRow(divider: false) {
                    Button("Reset Closed Notch Priority") {
                        closedNotchActivityPriorityOrder = ClosedNotchActivityKind.defaultPriorityOrder
                    }
                    .buttonStyle(.geist)
                }
            }

            GeistSection(
                title: "Screen Recording",
                footer: "Uses event-driven private API for real-time screen recording detection"
            ) {
                GeistToggleRow(title: "Enable Screen Recording Detection", isOn: $enableScreenRecordingDetection)
                GeistToggleRow(title: "Show Recording Indicator", isOn: geistBinding(.showRecordingIndicator), divider: recordingManager.isMonitoring)
                    .disabled(!enableScreenRecordingDetection)
                if recordingManager.isMonitoring {
                    GeistLabeledRow(title: "Detection Status", divider: false) {
                        if recordingManager.isRecording {
                            statusLabel(dot: .red, text: "Recording Detected", color: Geist.Colors.error)
                        } else {
                            statusLabel(dot: nil, text: "Active - No Recording", color: Geist.Colors.success)
                        }
                    }
                }
            }

            if !fullDiskAccessPermission.isAuthorized {
                SettingsPermissionCallout(
                    title: String(localized: "Custom Focus metadata"),
                    message: String(localized: "Full Disk Access unlocks custom Focus icons, colors, and labels. Standard Focus detection still works without it—grant access only if you need personalized indicators."),
                    icon: "externaldrive.fill",
                    iconColor: .purple,
                    requestButtonTitle: String(localized: "Request Full Disk Access"),
                    openSettingsButtonTitle: String(localized: "Open Privacy & Security"),
                    requestAction: { fullDiskAccessPermission.requestAccessPrompt() },
                    openSettingsAction: { fullDiskAccessPermission.openSystemSettings() }
                )
            }

            GeistSection(
                title: "Do Not Disturb",
                footer: "Listens for Focus session changes via distributed notifications"
            ) {
                GeistToggleRow(title: "Enable Focus Detection", isOn: $enableDoNotDisturbDetection)
                GeistToggleRow(title: "Show Focus Indicator", isOn: geistBinding(.showDoNotDisturbIndicator))
                    .disabled(!enableDoNotDisturbDetection)
                GeistToggleRow(title: "Show Focus Label", isOn: geistBinding(.showDoNotDisturbLabel))
                    .disabled(!enableDoNotDisturbDetection || focusIndicatorNonPersistent)
                    .help(focusIndicatorNonPersistent ? "Labels are forced to compact on/off text while brief toast mode is enabled." : "Show the active Focus name inside the indicator.")
                GeistToggleRow(title: "Show Focus as brief toast", isOn: geistBinding(.focusIndicatorNonPersistent))
                    .disabled(!enableDoNotDisturbDetection)
                    .help("When enabled, Focus appears briefly (on/off) and then collapses instead of staying visible.")
                GeistLabeledRow(title: "Focus Status", divider: false) {
                    if doNotDisturbManager.isMonitoring {
                        if doNotDisturbManager.isDoNotDisturbActive {
                            statusLabel(dot: .purple, text: doNotDisturbManager.currentFocusModeName.isEmpty ? "Focus Enabled" : doNotDisturbManager.currentFocusModeName, color: .purple)
                        } else {
                            statusLabel(dot: nil, text: "Active - No Focus", color: Geist.Colors.success)
                        }
                    } else {
                        statusLabel(dot: nil, text: "Disabled", color: Geist.Colors.mute)
                    }
                }
            }

            GeistSection(
                title: "Caps Lock Indicator",
                footer: "Adds a notch HUD when Caps Lock is enabled, with optional label and tint controls."
            ) {
                GeistToggleRow(title: "Show Caps Lock Indicator", isOn: geistBinding(.enableCapsLockIndicator))
                GeistToggleRow(title: "Show Caps Lock label", isOn: geistBinding(.showCapsLockLabel))
                    .disabled(!Defaults[.enableCapsLockIndicator])
                GeistSegmentedRow(title: "Caps Lock color", selection: $capsLockTintMode, divider: false) {
                    ForEach(CapsLockIndicatorTintMode.allCases) { Text($0.displayName).tag($0) }
                }
                .disabled(!Defaults[.enableCapsLockIndicator])
            }

            GeistSection(
                title: "Privacy Indicators",
                footer: "Shows green camera icon and yellow microphone icon when in use. Uses event-driven CoreAudio and CoreMediaIO APIs."
            ) {
                GeistToggleRow(title: "Enable Camera Detection", isOn: geistBinding(.enableCameraDetection))
                GeistToggleRow(title: "Enable Microphone Detection", isOn: geistBinding(.enableMicrophoneDetection), divider: privacyManager.isMonitoring)
                if privacyManager.isMonitoring {
                    GeistLabeledRow(title: "Camera Status") {
                        if privacyManager.cameraActive {
                            statusLabel(dot: .green, text: "Camera Active", color: Geist.Colors.success)
                        } else {
                            statusLabel(dot: nil, text: "Inactive", color: Geist.Colors.mute)
                        }
                    }
                    GeistLabeledRow(title: "Microphone Status", divider: false) {
                        if privacyManager.microphoneActive {
                            statusLabel(dot: .yellow, text: "Microphone Active", color: .yellow)
                        } else {
                            statusLabel(dot: nil, text: "Inactive", color: Geist.Colors.mute)
                        }
                    }
                }
            }

            GeistSection(
                title: "Media Live Activity",
                footer: "Use the Media tab to configure sneak peek, lyrics, and floating media controls."
            ) {
                GeistToggleRow(title: "Enable music live activity", isOn: $coordinator.musicLiveActivityEnabled.animation(), divider: false)
            }

            GeistSection(
                title: "Reminder Live Activity",
                footer: "Configure countdown style in the Calendar tab."
            ) {
                GeistToggleRow(title: "Enable reminder live activity", isOn: geistBinding(.enableReminderLiveActivity), divider: false)
            }
        }
        .onAppear {
            fullDiskAccessPermission.refreshStatus()
            normalizeClosedNotchActivityPriorityOrder()
        }
    }

    private var normalizedClosedNotchPriorityOrder: [ClosedNotchActivityKind] {
        var seen = Set<ClosedNotchActivityKind>()
        var order: [ClosedNotchActivityKind] = []

        for kind in closedNotchActivityPriorityOrder where !seen.contains(kind) {
            seen.insert(kind)
            order.append(kind)
        }

        for kind in ClosedNotchActivityKind.defaultPriorityOrder where !seen.contains(kind) {
            seen.insert(kind)
            order.append(kind)
        }

        return order
    }

    private func normalizeClosedNotchActivityPriorityOrder() {
        let normalized = normalizedClosedNotchPriorityOrder
        if closedNotchActivityPriorityOrder != normalized {
            closedNotchActivityPriorityOrder = normalized
        }
    }

    private func moveClosedNotchActivity(_ kind: ClosedNotchActivityKind, direction: Int) {
        var order = normalizedClosedNotchPriorityOrder
        guard let currentIndex = order.firstIndex(of: kind) else { return }
        let targetIndex = currentIndex + direction
        guard order.indices.contains(targetIndex) else { return }
        order.swapAt(currentIndex, targetIndex)
        closedNotchActivityPriorityOrder = order
    }
}

struct Appearance: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.sliderColor) var sliderColor
    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.customVisualizers) var customVisualizers
    @Default(.selectedVisualizer) var selectedVisualizer
    @Default(.customAppIcons) private var customAppIcons
    @Default(.selectedAppIconID) private var selectedAppIconID
    @Default(.openNotchWidth) var openNotchWidth
    @Default(.autoNotchWidth) var autoNotchWidth
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @Default(.externalDisplayStyle) private var externalDisplayStyle
    @State private var selectedListVisualizer: CustomVisualizer? = nil

    @State private var isIconImporterPresented = false
    @State private var isIconDropTarget = false
    @State private var iconImportError: String?

    @State private var isPresented: Bool = false
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var speed: CGFloat = 1.0

    /// Whether the main screen has a physical notch.
    private var mainScreenHasPhysicalNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.safeAreaInsets.top > 0
    }

    private var notchWidthRange: ClosedRange<Double> {
        let minW = Double(currentRecommendedMinimumNotchWidth())
        let maxW = min(900, Double(maxAllowedNotchWidth()))
        return minW...max(minW, maxW)
    }
    private var defaultOpenNotchWidth: CGFloat {
        currentRecommendedMinimumNotchWidth()
    }

    var body: some View {
        GeistSettingsPage(title: "Appearance") {
            GeistSection(title: "General") {
                GeistToggleRow(title: "Always show tabs", isOn: $coordinator.alwaysShowTabs)
                GeistToggleRow(title: "Settings icon in notch", isOn: geistBinding(.settingsIconInNotch))
                GeistToggleRow(title: "Enable window shadow", isOn: geistBinding(.enableShadow))
                GeistToggleRow(title: "Corner radius scaling", isOn: geistBinding(.cornerRadiusScaling))
                GeistToggleRow(title: "Use simpler close animation", isOn: geistBinding(.useModernCloseAnimation), divider: false)
            }

            // Show display style picker only on non-notch Macs (main screen has no physical notch)
            if !mainScreenHasPhysicalNotch {
                GeistSection(title: "Display Style") {
                    GeistPickerRow(title: "Main screen style", selection: $externalDisplayStyle) {
                        ForEach(ExternalDisplayStyle.allCases) { Text($0.localizedName).tag($0) }
                    }
                    .onChange(of: externalDisplayStyle) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                    GeistRow(divider: false) {
                        Text(externalDisplayStyle.description)
                            .font(Geist.Typography.caption).foregroundStyle(Geist.Colors.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            notchWidthControls()

            GeistSection(title: "Media") {
                GeistToggleRow(title: "Enable colored spectrograms", isOn: geistBinding(.coloredSpectrogram))
                GeistToggleRow(title: "Enable colored lyrics", isOn: geistBinding(.coloredLyrics))
                GeistToggleRow(title: "Enable player color tinting", isOn: geistBinding(.playerColorTinting))
                GeistToggleRow(title: "Enable blur effect behind album art", isOn: geistBinding(.lightingEffect))
                GeistPickerRow(title: "Slider color", selection: $sliderColor, divider: false) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }

            GeistSection(title: "Custom music live activity animation", badge: "Coming soon") {
                GeistToggleRow(title: "Use music visualizer spectrogram", isOn: $useMusicVisualizer.animation(), divider: !useMusicVisualizer)
                    .disabled(true)
                if !useMusicVisualizer {
                    if customVisualizers.count > 0 {
                        GeistPickerRow(title: "Selected animation", selection: $selectedVisualizer, divider: false) {
                            ForEach(customVisualizers, id: \.self) { Text($0.name).tag($0) }
                        }
                    } else {
                        GeistLabeledRow(title: "Selected animation", divider: false) {
                            Text("No custom animation available")
                                .font(Geist.Typography.body).foregroundStyle(Geist.Colors.mute)
                        }
                    }
                }
            }

            GeistSection(title: customVisualizers.isEmpty ? "Custom visualizers (Lottie)" : "Custom visualizers (Lottie) – \(customVisualizers.count)") {
              GeistRow(divider: false) {
                List {
                    ForEach(customVisualizers, id: \.self) { visualizer in
                        HStack {
                            LottieView(state: LUStateData(type: .loadedFrom(visualizer.url), speed: visualizer.speed, loopMode: .loop))
                                .frame(width: 30, height: 30, alignment: .center)
                            Text(visualizer.name)
                            Spacer(minLength: 0)
                            if selectedVisualizer == visualizer {
                                Text("selected")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 8)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 2)
                        .background(
                            selectedListVisualizer != nil ? selectedListVisualizer == visualizer ? Color.accentColor : Color.clear : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedListVisualizer == visualizer {
                                selectedListVisualizer = nil
                                return
                            }
                            selectedListVisualizer = visualizer
                        }
                    }
                }
                .safeAreaPadding(
                    EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)
                )
                .frame(minHeight: 120)
                .actionBar {
                    HStack(spacing: 5) {
                        Button {
                            name = ""
                            url = ""
                            speed = 1.0
                            isPresented.toggle()
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        Divider()
                        Button {
                            if selectedListVisualizer != nil {
                                let visualizer = selectedListVisualizer!
                                selectedListVisualizer = nil
                                customVisualizers.remove(at: customVisualizers.firstIndex(of: visualizer)!)
                                if visualizer == selectedVisualizer && customVisualizers.count > 0 {
                                    selectedVisualizer = customVisualizers[0]
                                }
                            }
                        } label: {
                            Image(systemName: "minus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                    }
                }
                .controlSize(.small)
                .buttonStyle(PlainButtonStyle())
                .overlay {
                    if customVisualizers.isEmpty {
                        Text("No custom visualizer")
                            .foregroundStyle(Color(.secondaryLabelColor))
                            .padding(.bottom, 22)
                    }
                }
                .sheet(isPresented: $isPresented) {
                    VStack(alignment: .leading) {
                        Text("Add new visualizer")
                            .font(.largeTitle.bold())
                            .padding(.vertical)
                        TextField("Name", text: $name)
                        TextField("Lottie JSON URL", text: $url)
                        HStack {
                            Text("Speed")
                            Spacer(minLength: 80)
                            Text("\(speed, specifier: "%.1f")s")
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                            Slider(value: $speed, in: 0...2, step: 0.1)
                        }
                        .padding(.vertical)
                        HStack {
                            Button {
                                isPresented.toggle()
                            } label: {
                                Text("Cancel")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }

                            Button {
                                let visualizer: CustomVisualizer = .init(
                                    UUID: UUID(),
                                    name: name,
                                    url: URL(string: url)!,
                                    speed: speed
                                )

                                if !customVisualizers.contains(visualizer) {
                                    customVisualizers.append(visualizer)
                                }

                                isPresented.toggle()
                            } label: {
                                Text("Add")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(BorderedProminentButtonStyle())
                        }
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .controlSize(.extraLarge)
                    .padding()
                }
              }
            }

            GeistSection(title: "Additional features") {
                GeistToggleRow(title: "Idle Animation", isOn: geistBinding(.showNotHumanFace), divider: false)
            }

            GeistSection(title: "App icon") {
                GeistRow(divider: false) {
                    VStack(alignment: .leading, spacing: Geist.Spacing.sm) {
                        let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]
                        LazyVGrid(columns: columns, spacing: 12) {
                            appIconCard(
                                title: "Default",
                                image: defaultAppIconImage(),
                                isSelected: selectedAppIconID == nil
                            ) {
                                selectedAppIconID = nil
                                applySelectedAppIcon()
                            }
                            ForEach(customAppIcons) { icon in
                                appIconCard(
                                    title: icon.name,
                                    image: customIconImage(for: icon),
                                    isSelected: selectedAppIconID == icon.id.uuidString
                                ) {
                                    selectedAppIconID = icon.id.uuidString
                                    applySelectedAppIcon()
                                }
                                .contextMenu {
                                    Button("Remove") { removeCustomIcon(icon) }
                                }
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.secondary.opacity(isIconDropTarget ? 0.18 : 0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(isIconDropTarget ? 0.8 : 0), lineWidth: 2)
                        )
                        .onDrop(of: [UTType.fileURL], isTargeted: $isIconDropTarget) { providers in
                            handleIconDrop(providers)
                        }

                        HStack(spacing: Geist.Spacing.xs) {
                            Button("Add icon") {
                                iconImportError = nil
                                isIconImporterPresented = true
                            }
                            .buttonStyle(.geistProminent)
                            Button("Remove selected") {
                                if let id = selectedAppIconID,
                                   let icon = customAppIcons.first(where: { $0.id.uuidString == id }) {
                                    removeCustomIcon(icon)
                                }
                            }
                            .buttonStyle(.geist)
                            .disabled(selectedAppIconID == nil)
                        }

                        Text(iconImportError ?? "Drop a PNG, JPEG, TIFF, or ICNS file to add it to your icon library.")
                            .font(Geist.Typography.caption)
                            .foregroundStyle(Geist.Colors.mute)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isIconImporterPresented,
            allowedContentTypes: [.png, .jpeg, .tiff, .icns, .image]
        ) { result in
            switch result {
            case .success(let url):
                importCustomIcon(from: url)
            case .failure:
                iconImportError = "Icon import was canceled or failed."
            }
        }
    }

    private func defaultAppIconImage() -> NSImage? {
        let fallbackName = Bundle.main.iconFileName ?? "AppIcon"
        return NSImage(named: fallbackName)
    }

    private func customIconImage(for icon: CustomAppIcon) -> NSImage? {
        NSImage(contentsOf: icon.fileURL)
    }

    private func appIconCard(title: String, image: NSImage?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 64, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                )

                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(isSelected ? Color.accentColor : .clear)
                    )
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func handleIconDrop(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.first { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard let provider = matching else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let directURL = item as? URL {
                url = directURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }
            guard let url else { return }
            Task { @MainActor in importCustomIcon(from: url) }
        }
        return true
    }

    private func importCustomIcon(from url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            iconImportError = "That file could not be loaded as an image."
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let id = UUID()
        let fileName = "custom-icon-\(id.uuidString).\(ext)"
        let destination = CustomAppIcon.iconDirectory.appendingPathComponent(fileName)

        do {
            let data = try Data(contentsOf: url)
            try data.write(to: destination, options: [.atomic])
        } catch {
            iconImportError = "Unable to save the icon file."
            return
        }

        let newIcon = CustomAppIcon(id: id, name: name.isEmpty ? "Custom Icon" : name, fileName: fileName)
        if !customAppIcons.contains(newIcon) {
            customAppIcons.append(newIcon)
        }
        selectedAppIconID = newIcon.id.uuidString
        NSApp.applicationIconImage = image
        iconImportError = nil
    }

    private func removeCustomIcon(_ icon: CustomAppIcon) {
        if let index = customAppIcons.firstIndex(of: icon) {
            customAppIcons.remove(at: index)
        }
        if FileManager.default.fileExists(atPath: icon.fileURL.path) {
            try? FileManager.default.removeItem(at: icon.fileURL)
        }
        if selectedAppIconID == icon.id.uuidString {
            selectedAppIconID = nil
            applySelectedAppIcon()
        }
    }

    @ViewBuilder
    private func notchWidthControls() -> some View {
        let recommendedMin = currentRecommendedMinimumNotchWidth()
        let tabCount = enabledStandardTabCount()
        let dynamicRange = Double(recommendedMin)...900
        let widthBinding = Binding<Double>(
            get: { Double(openNotchWidth) },
            set: { newValue in
                let clamped = min(max(newValue, dynamicRange.lowerBound), dynamicRange.upperBound)
                let value = CGFloat(clamped)
                if openNotchWidth != value {
                    openNotchWidth = value
                }
            }
        )
        let description = enableMinimalisticUI
        ? String(localized: "Width adjustments apply only to the standard notch layout. Disable Minimalistic UI to edit this value.")
        : (autoNotchWidth
            ? String(localized: "The expanded notch sizes itself to the number of enabled tabs. Turn this off to set a fixed width.")
            : String(localized: "Recommended minimum width adjusts automatically based on the number of enabled tabs."))

        GeistSection(title: "Notch Width", badge: "Beta") {
            GeistToggleRow(
                title: "Auto width",
                description: "Size the expanded notch from the number of enabled tabs.",
                isOn: $autoNotchWidth
            )
            .disabled(enableMinimalisticUI)
            .onChange(of: autoNotchWidth) { _, _ in enforceMinimumNotchWidth() }

            if !autoNotchWidth {
                GeistSliderRow(title: "Expanded notch width", valueLabel: "\(Int(openNotchWidth)) px", value: widthBinding, range: dynamicRange, step: 10)
                    .disabled(enableMinimalisticUI)
                GeistRow {
                    HStack {
                        Text("\(tabCount) tab\(tabCount == 1 ? "" : "s") enabled · min \(Int(recommendedMin)) px")
                            .font(Geist.Typography.caption).foregroundStyle(Geist.Colors.mute)
                        Spacer()
                        Button("Reset Width") { openNotchWidth = recommendedMin }
                            .buttonStyle(.geist)
                            .disabled(abs(openNotchWidth - recommendedMin) < 0.5)
                    }
                }
            }

            GeistRow(divider: false) {
                Text(description)
                    .font(Geist.Typography.caption).foregroundStyle(Geist.Colors.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            enforceMinimumNotchWidth()
        }
    }

}

struct Shortcuts: View {
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.enableShortcuts) var enableShortcuts

    var body: some View {
        GeistSettingsPage(title: "Shortcuts") {
            GeistSection(
                title: "General",
                footer: "When disabled, all keyboard shortcuts will be inactive. You can still use the UI controls."
            ) {
                GeistToggleRow(title: "Enable global keyboard shortcuts", isOn: $enableShortcuts, divider: false)
            }

            if enableShortcuts {
                GeistSection(
                    title: "Media",
                    footer: "Sneak Peek shows the media title and artist under the notch for a few seconds."
                ) {
                    GeistLabeledRow(title: "Toggle Sneak Peek", divider: false) {
                        KeyboardShortcuts.Recorder("", name: .toggleSneakPeek)
                    }
                }

                GeistSection(
                    title: "Navigation",
                    footer: "Toggle the Dynamic Island open or closed from anywhere."
                ) {
                    GeistLabeledRow(title: "Toggle Notch Open", divider: false) {
                        KeyboardShortcuts.Recorder("", name: .toggleNotchOpen)
                    }
                }

                shortcutSection(
                    title: "Timer",
                    label: "Start Demo Timer",
                    name: .startDemoTimer,
                    enabled: enableTimerFeature,
                    disabledNote: "Timer feature is disabled",
                    footer: "Starts a 5-minute demo timer to test the timer live activity feature. Only works when timer feature is enabled."
                )

            } else {
                GeistSection {
                    GeistRow(divider: false) {
                        VStack(alignment: .leading, spacing: Geist.Spacing.xs) {
                            Text("Keyboard shortcuts are disabled")
                                .font(Geist.Typography.bodyStrong)
                                .foregroundStyle(Geist.Colors.ink)
                            Text("Enable global keyboard shortcuts above to customize your shortcuts.")
                                .font(Geist.Typography.caption)
                                .foregroundStyle(Geist.Colors.body)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func shortcutSection(
        title: String,
        label: String,
        name: KeyboardShortcuts.Name,
        enabled: Bool,
        disabledNote: String,
        footer: String
    ) -> some View {
        GeistSection(title: title, footer: footer) {
            GeistLabeledRow(title: label, divider: !enabled) {
                KeyboardShortcuts.Recorder("", name: name)
                    .disabled(!enableShortcuts || !enabled)
            }
            if !enabled {
                GeistRow(divider: false) {
                    Text(disabledNote)
                        .font(Geist.Typography.caption)
                        .foregroundStyle(Geist.Colors.mute)
                }
            }
        }
    }
}

func proFeatureBadge() -> some View {
    Text("Upgrade to Pro")
        .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 4).stroke(Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1))
}

func comingSoonTag() -> some View {
    Text("Coming soon")
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func customBadge(text: String) -> some View {
    Text(text)
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func alphaBadge() -> some View {
    Text("ALPHA")
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.9))
        )
}

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text(text)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct TimerSettings: View {
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.timerPresets) private var timerPresets
    @Default(.timerIconColorMode) private var colorMode
    @Default(.timerSolidColor) private var solidColor
    @Default(.timerShowsCountdown) private var showsCountdown
    @Default(.timerShowsLabel) private var showsLabel
    @Default(.timerShowsProgress) private var showsProgress
    @Default(.timerProgressStyle) private var progressStyle
    @Default(.showTimerPresetsInNotchTab) private var showTimerPresetsInNotchTab
    @Default(.timerControlWindowEnabled) private var controlWindowEnabled
    @Default(.mirrorSystemTimer) private var mirrorSystemTimer
    @Default(.timerDisplayMode) private var timerDisplayMode
    @AppStorage("customTimerDuration") private var customTimerDuration: Double = 600
    @State private var customHours: Int = 0
    @State private var customMinutes: Int = 10
    @State private var customSeconds: Int = 0
    @State private var showingResetConfirmation = false

    private func highlightID(_ title: String) -> String {
        SettingsTab.timer.highlightID(for: title)
    }

    var body: some View {
        GeistSettingsPage(title: "Timer") {
            timerFeatureSection
            if enableTimerFeature {
                timerConfigurationSections
            }
        }
        .onAppear { syncCustomDuration() }
        .onChange(of: customTimerDuration) { _, newValue in syncCustomDuration(newValue) }
    }

    @ViewBuilder
    private var timerFeatureSection: some View {
        GeistSection(
            title: "Timer Feature",
            footer: "Control timer availability, live activity behaviour, and whether the app mirrors timers started from the macOS Clock app."
        ) {
            GeistToggleRow(title: "Enable timer feature", isOn: $enableTimerFeature, divider: enableTimerFeature)
            if enableTimerFeature {
                GeistToggleRow(title: "Enable timer live activity", isOn: $coordinator.timerLiveActivityEnabled)
                    .animation(.easeInOut, value: coordinator.timerLiveActivityEnabled)
                GeistToggleRow(
                    title: "Mirror macOS Clock timers",
                    description: "Shows the system Clock timer in the notch when available. Requires Accessibility permission to read the status item.",
                    isOn: $mirrorSystemTimer
                )
                GeistSegmentedRow(title: "Timer controls appear as", selection: $timerDisplayMode, divider: false) {
                    ForEach(TimerDisplayMode.allCases) { Text($0.displayName).tag($0) }
                }
                .help(timerDisplayMode.description)
            }
        }
    }

    @ViewBuilder
    private var timerConfigurationSections: some View {
        Group {
            customTimerSection
            appearanceSection
            timerPresetsSection
            timerSoundSection
        }
        .onAppear {
            if showsLabel {
                controlWindowEnabled = false
            }
        }
        .onChange(of: showsLabel) { _, show in
            if show {
                controlWindowEnabled = false
            }
        }
    }

    @ViewBuilder
    private var customTimerSection: some View {
        GeistSection(
            title: "Custom Timer",
            footer: "This duration powers the \"Custom\" option inside the timer popover for quick access."
        ) {
            GeistStepperRow(title: String(localized: "Hours"), value: $customHours, range: 0...23, valueLabel: "\(customHours)", onChange: updateCustomDuration)
            GeistStepperRow(title: String(localized: "Minutes"), value: $customMinutes, range: 0...59, valueLabel: "\(customMinutes)", onChange: updateCustomDuration)
            GeistStepperRow(title: String(localized: "Seconds"), value: $customSeconds, range: 0...59, valueLabel: "\(customSeconds)", onChange: updateCustomDuration)
            GeistLabeledRow(title: "Current default", divider: false) {
                Text(customDurationDisplay)
                    .font(Geist.Typography.mono)
                    .foregroundStyle(Geist.Colors.ink)
            }
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        GeistSection(
            title: "Appearance",
            footer: "Configure how the timer looks inside the closed notch. Progress can render as a ring around the icon or as horizontal bars."
        ) {
            GeistSegmentedRow(title: "Timer tint", selection: $colorMode) {
                ForEach(TimerIconColorMode.allCases) { Text($0.displayName).tag($0) }
            }
            if colorMode == .solid {
                GeistLabeledRow(title: "Solid colour") {
                    ColorPicker("", selection: $solidColor, supportsOpacity: false).labelsHidden()
                }
            }
            GeistToggleRow(title: "Show timer name", isOn: $showsLabel)
            GeistToggleRow(title: "Show countdown", isOn: $showsCountdown)
            GeistToggleRow(title: "Show progress", isOn: $showsProgress)
            GeistToggleRow(title: "Show preset list in timer tab", isOn: $showTimerPresetsInNotchTab)
            GeistToggleRow(
                title: "Show floating pause/stop controls",
                description: "These controls sit beside the notch while a timer runs. They require the timer name to stay hidden for spacing.",
                isOn: $controlWindowEnabled
            )
            .disabled(showsLabel)
            GeistSegmentedRow(title: "Progress style", selection: $progressStyle, divider: false) {
                ForEach(TimerProgressStyle.allCases) { Text($0.rawValue).tag($0) }
            }
            .disabled(!showsProgress)
        }
    }

    @ViewBuilder
    private var timerPresetsSection: some View {
        GeistSection(
            title: "Timer Presets",
            footer: "Presets show up inside the timer popover with the configured name, duration, and accent colour. Reorder them to change the display order."
        ) {
            if timerPresets.isEmpty {
                GeistRow {
                    Text("No presets configured. Add a preset to make it appear in the timer popover.")
                        .font(Geist.Typography.caption)
                        .foregroundStyle(Geist.Colors.body)
                }
            } else {
                GeistRow {
                    VStack(spacing: Geist.Spacing.sm) {
                        TimerPresetListView(
                            presets: $timerPresets,
                            highlightProvider: highlightID,
                            moveUp: movePresetUp,
                            moveDown: movePresetDown,
                            remove: removePreset
                        )
                    }
                }
            }

            GeistRow(divider: false) {
                HStack {
                    Button(action: addPreset) {
                        Label("Add Preset", systemImage: "plus")
                    }
                    .buttonStyle(.geist)
                    Spacer()
                    Button(role: .destructive, action: { showingResetConfirmation = true }) {
                        Label("Restore Defaults", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.geist)
                    .confirmationDialog("Restore default timer presets?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                        Button("Restore", role: .destructive, action: resetPresets)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var timerSoundSection: some View {
        GeistSection(
            title: "Timer Sound",
            footer: "Select a custom sound to play when a timer ends. Supported formats include MP3, M4A, WAV, and AIFF."
        ) {
            GeistLabeledRow(title: "Timer Sound") {
                Button("Choose File", action: selectCustomTimerSound).buttonStyle(.geist)
            }
            GeistRow {
                if let customTimerSoundPath = UserDefaults.standard.string(forKey: "customTimerSoundPath") {
                    Text("Custom: \(URL(fileURLWithPath: customTimerSoundPath).lastPathComponent)")
                        .font(Geist.Typography.caption).foregroundStyle(Geist.Colors.mute)
                } else {
                    Text("Default: dynamic.m4a")
                        .font(Geist.Typography.caption).foregroundStyle(Geist.Colors.mute)
                }
            }
            GeistRow(divider: false) {
                Button("Reset to Default") {
                    UserDefaults.standard.removeObject(forKey: "customTimerSoundPath")
                }
                .buttonStyle(.geist)
                .disabled(UserDefaults.standard.string(forKey: "customTimerSoundPath") == nil)
            }
        }
    }

    private var customDurationDisplay: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = customTimerDuration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: customTimerDuration) ?? "0:00"
    }

    private func syncCustomDuration(_ value: Double? = nil) {
        let baseValue = value ?? customTimerDuration
        let components = TimerPreset.components(for: baseValue)
        customHours = components.hours
        customMinutes = components.minutes
        customSeconds = components.seconds
    }

    private func updateCustomDuration() {
        let duration = TimeInterval(customHours * 3600 + customMinutes * 60 + customSeconds)
        customTimerDuration = duration
    }

    private func addPreset() {
        let nextIndex = timerPresets.count + 1
        let defaultColor = Defaults[.accentColor]
        let newPreset = TimerPreset(name: "Preset \(nextIndex)", duration: 5 * 60, color: defaultColor)
        _ = withAnimation(.smooth) {
            timerPresets.append(newPreset)
        }
    }

    private func movePresetUp(_ index: Int) {
        guard index > timerPresets.startIndex else { return }
        _ = withAnimation(.smooth) {
            timerPresets.swapAt(index, index - 1)
        }
    }

    private func movePresetDown(_ index: Int) {
        guard index < timerPresets.index(before: timerPresets.endIndex) else { return }
        _ = withAnimation(.smooth) {
            timerPresets.swapAt(index, index + 1)
        }
    }

    private func removePreset(_ index: Int) {
        guard timerPresets.indices.contains(index) else { return }
        _ = withAnimation(.smooth) {
            timerPresets.remove(at: index)
        }
    }

    private func resetPresets() {
        _ = withAnimation(.smooth) {
            timerPresets = TimerPreset.defaultPresets
        }
    }

    private func selectCustomTimerSound() {
        let panel = NSOpenPanel()
        panel.title = "Select Timer Sound"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            if let url = panel.url {
                UserDefaults.standard.set(url.path, forKey: "customTimerSoundPath")
            }
        }
    }
}

private struct TimerDurationStepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        Stepper(value: $value, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
        }
    }
}

private struct TimerPresetListView: View {
    @Binding var presets: [TimerPreset]
    let highlightProvider: (String) -> String
    let moveUp: (Int) -> Void
    let moveDown: (Int) -> Void
    let remove: (Int) -> Void

    var body: some View {
        ForEach(presets.indices, id: \.self) { index in
            presetRow(at: index)
        }
    }

    @ViewBuilder
    private func presetRow(at index: Int) -> some View {
        TimerPresetEditorRow(
            preset: $presets[index],
            isFirst: index == presets.startIndex,
            isLast: index == presets.index(before: presets.endIndex),
            highlightID: highlightID(for: index),
            moveUp: { moveUp(index) },
            moveDown: { moveDown(index) },
            remove: { remove(index) }
        )
    }

    private func highlightID(for index: Int) -> String? {
        index == presets.startIndex ? highlightProvider("Accent colour") : nil
    }
}

private struct TimerPresetEditorRow: View {
    @Binding var preset: TimerPreset
    let isFirst: Bool
    let isLast: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void
    let highlightID: String?

    init(
        preset: Binding<TimerPreset>,
        isFirst: Bool,
        isLast: Bool,
        highlightID: String? = nil,
        moveUp: @escaping () -> Void,
        moveDown: @escaping () -> Void,
        remove: @escaping () -> Void
    ) {
        _preset = preset
        self.isFirst = isFirst
        self.isLast = isLast
        self.highlightID = highlightID
        self.moveUp = moveUp
        self.moveDown = moveDown
        self.remove = remove
    }

    private var components: TimerPreset.DurationComponents {
        TimerPreset.components(for: preset.duration)
    }

    private var hoursBinding: Binding<Int> {
        Binding(
            get: { components.hours },
            set: { updateDuration(hours: $0) }
        )
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { components.minutes },
            set: { updateDuration(minutes: $0) }
        )
    }

    private var secondsBinding: Binding<Int> {
        Binding(
            get: { components.seconds },
            set: { updateDuration(seconds: $0) }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { preset.color },
            set: { preset.updateColor($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(preset.color.gradient)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )

                TextField("Preset name", text: $preset.name)
                    .textFieldStyle(.roundedBorder)

                Spacer()

                Text(preset.formattedDuration)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                TimerPresetComponentControl(title: String(localized: "Hours"), value: hoursBinding, range: 0...23)
                TimerPresetComponentControl(title: String(localized: "Minutes"), value: minutesBinding, range: 0...59)
                TimerPresetComponentControl(title: String(localized: "Seconds"), value: secondsBinding, range: 0...59)
            }

            ColorPicker("Accent colour", selection: colorBinding, supportsOpacity: false)
                .frame(maxWidth: 240, alignment: .leading)

            HStack(spacing: 12) {
                Button(action: moveUp) {
                    Label("Move Up", systemImage: "chevron.up")
                }
                .buttonStyle(.bordered)
                .disabled(isFirst)

                Button(action: moveDown) {
                    Label("Move Down", systemImage: "chevron.down")
                }
                .buttonStyle(.bordered)
                .disabled(isLast)

                Spacer()

                Button(role: .destructive, action: remove) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .font(.system(size: 12, weight: .medium))
        }
        .padding(.vertical, 6)
        .settingsHighlightIfPresent(highlightID)
    }

    private func updateDuration(hours: Int? = nil, minutes: Int? = nil, seconds: Int? = nil) {
        var values = components
        if let hours { values.hours = hours }
        if let minutes { values.minutes = minutes }
        if let seconds { values.seconds = seconds }
        preset.duration = TimerPreset.duration(from: values)
    }
}

private struct TimerPresetComponentControl: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        Stepper(value: $value, in: range) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(value)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
        }
        .frame(width: 110, alignment: .leading)
    }
}


struct CustomOSDSettings: View {
    @Default(.enableCustomOSD) var enableCustomOSD
    @Default(.hasSeenOSDAlphaWarning) var hasSeenOSDAlphaWarning
    @Default(.enableOSDVolume) var enableOSDVolume
    @Default(.enableOSDBrightness) var enableOSDBrightness
    @Default(.enableOSDKeyboardBacklight) var enableOSDKeyboardBacklight
    @Default(.osdMaterial) var osdMaterial
    @Default(.osdLiquidGlassCustomizationMode) var osdLiquidGlassCustomizationMode
    @Default(.osdLiquidGlassVariant) var osdLiquidGlassVariant
    @Default(.osdIconColorStyle) var osdIconColorStyle
    @Default(.enableSystemHUD) var enableSystemHUD
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared

    @State private var showAlphaWarning = false
    @State private var previewValue: CGFloat = 0.65
    @State private var previewType: SneakContentType = .volume

    private var hasAccessibilityPermission: Bool {
        accessibilityPermission.isAuthorized
    }

    private var availableOSDMaterials: [OSDMaterial] {
        if #available(macOS 26.0, *) {
            return OSDMaterial.allCases
        }
        return OSDMaterial.allCases.filter { $0 != .liquid }
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private var osdLiquidVariantBinding: Binding<Double> {
        Binding(
            get: { Double(osdLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                osdLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    private let materialFooter = """
    Material Options:
    • Frosted Glass: Translucent blur effect
    • Liquid Glass: Modern glass effect (macOS 26+)
    • Solid Dark/Light/Auto: Opaque backgrounds

    Color options control the icon and progress bar appearance. Auto adapts to system theme.
    """

    var body: some View {
        Group {
            if !hasAccessibilityPermission {
                SettingsPermissionCallout(
                    message: "Accessibility permission is needed to intercept system controls for the Custom OSD.",
                    requestAction: { accessibilityPermission.requestAuthorizationPrompt() },
                    openSettingsAction: { accessibilityPermission.openSystemSettings() }
                )
            }

            if hasAccessibilityPermission {
                GeistSection(title: "Controls", footer: "Choose which system controls should display custom OSD windows.") {
                    GeistToggleRow(title: "Volume OSD", isOn: $enableOSDVolume)
                    GeistToggleRow(title: "Brightness OSD", isOn: $enableOSDBrightness)
                    GeistToggleRow(title: "Keyboard Backlight OSD", isOn: $enableOSDKeyboardBacklight, divider: false)
                }

                GeistSection(title: "Appearance", footer: materialFooter) {
                    GeistPickerRow(title: "Material", selection: $osdMaterial) {
                        ForEach(availableOSDMaterials, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .onChange(of: osdMaterial) { _, _ in
                        previewValue = previewValue == 0.65 ? 0.651 : 0.65
                    }
                    if osdMaterial == .liquid {
                        if #available(macOS 26.0, *) {
                            GeistSegmentedRow(title: "Glass mode", selection: $osdLiquidGlassCustomizationMode) {
                                ForEach(GlassCustomizationMode.allCases) { Text($0.rawValue).tag($0) }
                            }
                            if osdLiquidGlassCustomizationMode == .customLiquid {
                                GeistSliderRow(title: "Custom liquid variant", valueLabel: "v\(osdLiquidGlassVariant.rawValue)", value: osdLiquidVariantBinding, range: liquidVariantRange, step: 1)
                            }
                        } else {
                            GeistRow {
                                Text("Custom Liquid is available on macOS 26 or later.")
                                    .font(Geist.Typography.caption).foregroundStyle(Geist.Colors.mute)
                            }
                        }
                    }
                    GeistPickerRow(title: "Icon & Progress Color", selection: $osdIconColorStyle, divider: false) {
                        ForEach(OSDIconColorStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .onChange(of: osdIconColorStyle) { _, _ in
                        previewValue = previewValue == 0.65 ? 0.651 : 0.65
                    }
                }

                GeistSection(title: "Preview", footer: "Adjust settings above to see changes in real-time. The actual OSD appears at the bottom center of your screen.") {
                    GeistRow(divider: false) {
                        HStack {
                            Spacer()
                            VStack(spacing: Geist.Spacing.md) {
                                Text("Live Preview")
                                    .font(Geist.Typography.caption)
                                    .foregroundStyle(Geist.Colors.mute)
                                CustomOSDView(
                                    type: .constant(previewType),
                                    value: .constant(previewValue),
                                    icon: .constant("")
                                )
                                .frame(width: 200, height: 200)
                                HStack(spacing: Geist.Spacing.xs) {
                                    Button("Volume") { previewType = .volume }.buttonStyle(.geist)
                                    Button("Brightness") { previewType = .brightness }.buttonStyle(.geist)
                                    Button("Backlight") { previewType = .backlight }.buttonStyle(.geist)
                                }
                                Slider(value: $previewValue, in: 0...1)
                                    .frame(width: 160)
                            }
                            .padding(.vertical, Geist.Spacing.sm)
                            Spacer()
                        }
                    }
                }
            }
        }
        .onAppear {
            accessibilityPermission.refreshStatus()
            if #unavailable(macOS 26.0), osdMaterial == .liquid {
                osdMaterial = .frosted
                osdLiquidGlassCustomizationMode = .standard
            }
        }
        .onChange(of: accessibilityPermission.isAuthorized) { _, granted in
            if !granted {
                enableCustomOSD = false
            }
        }
    }
}

struct SettingsPermissionCallout: View {
    let title: String
    let message: String
    let icon: String
    let iconColor: Color
    let requestButtonTitle: String
    let openSettingsButtonTitle: String
    let requestAction: () -> Void
    let openSettingsAction: () -> Void

    init(
        title: String = "Accessibility permission required",
        message: String,
        icon: String = "exclamationmark.triangle.fill",
        iconColor: Color = .orange,
        requestButtonTitle: String = "Request Access",
        openSettingsButtonTitle: String = "Open Settings",
        requestAction: @escaping () -> Void,
        openSettingsAction: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconColor = iconColor
        self.requestButtonTitle = requestButtonTitle
        self.openSettingsButtonTitle = openSettingsButtonTitle
        self.requestAction = requestAction
        self.openSettingsAction = openSettingsAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(requestButtonTitle) {
                    requestAction()
                }
                .buttonStyle(.borderedProminent)

                Button(openSettingsButtonTitle) {
                    openSettingsAction()
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    HUD()
}


// MARK: - Reusable App Icon View

/// Fetches the real app icon from the system using bundle identifiers,
/// falling back to an asset catalog image or an SF Symbol.
struct AppIconImage: View {
    let bundleIdentifiers: [String]
    var assetFallback: String? = nil
    var symbolFallback: String = "app.fill"
    var symbolColor: Color = .accentColor
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let nsImage = resolvedIcon() {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else if let assetFallback, let nsImage = NSImage(named: NSImage.Name(assetFallback)) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                Image(systemName: symbolFallback)
                    .foregroundColor(symbolColor)
            }
        }
        .frame(width: size, height: size)
    }

    private func resolvedIcon() -> NSImage? {
        for bundleID in bundleIdentifiers {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                // NSWorkspace returns a valid icon even for generic apps;
                // resize to keep memory low.
                let thumb = NSImage(size: NSSize(width: 32, height: 32))
                thumb.lockFocus()
                icon.draw(in: NSRect(origin: .zero, size: NSSize(width: 32, height: 32)),
                          from: NSRect(origin: .zero, size: icon.size),
                          operation: .copy, fraction: 1.0)
                thumb.unlockFocus()
                return thumb
            }
        }
        return nil
    }
}

private struct QuickShareProviderIconImage: View {
    let provider: QuickShareProvider
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
                Image(nsImage: nsImg)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                AppIconImage(
                    bundleIdentifiers: provider.bundleIdentifiersFallback,
                    assetFallback: provider.assetFallbackName,
                    symbolFallback: provider.symbolFallbackName,
                    symbolColor: .accentColor,
                    size: size
                )
            }
        }
        .frame(width: size, height: size)
    }
}

private extension QuickShareProvider {
    var bundleIdentifiersFallback: [String] {
        switch id {
        case "LocalSend":
            return ["org.localsend.localsend_app", "org.localsend.localsend"]
        case "AirDrop":
            return ["com.apple.finder"]
        case "Mail":
            return ["com.apple.mail"]
        case "Messages":
            return ["com.apple.MobileSMS", "com.apple.iChat"]
        case "Notes":
            return ["com.apple.Notes"]
        case "Reminders":
            return ["com.apple.reminders"]
        case "Add to Safari Reading List":
            return ["com.apple.Safari"]
        default:
            return []
        }
    }

    var assetFallbackName: String? {
        id == "LocalSend" ? "LocalSend" : nil
    }

    var symbolFallbackName: String {
        id == "System Share Menu" ? "square.and.arrow.up.on.square" : "square.and.arrow.up"
    }
}
