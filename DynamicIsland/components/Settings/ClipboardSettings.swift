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
import KeyboardShortcuts
import SwiftUI

/// Settings pane for the clipboard manager.
struct ClipboardSettings: View {
    @ObservedObject private var monitor = ClipboardMonitor.shared
    @ObservedObject private var accessibility = AccessibilityPermissionStore.shared

    @Default(.enableClipboardManager) private var enableClipboardManager
    @Default(.clipboardDisplayMode) private var displayMode
    @Default(.clipboardHistorySize) private var historySize
    @Default(.clipboardCheckInterval) private var checkInterval
    @Default(.clipboardEnabledTypes) private var enabledTypes
    @Default(.clipboardIgnoredApps) private var ignoredApps
    @Default(.clipboardPasteAutomatically) private var pasteAutomatically
    @Default(.clipboardSortMode) private var sortMode
    @Default(.clipboardShowSourceApp) private var showSourceApp
    @Default(.clipboardClearSystemClipboardOnClear) private var clearSystemClipboard
    @Default(.clipboardMaxItemBytes) private var maxItemBytes
    @Default(.enableShortcuts) private var enableShortcuts

    @State private var newIgnoredApp = ""

    var body: some View {
        GeistSettingsPage(
            title: "Clipboard",
            subtitle: "A searchable history of what you copy — text, images and files."
        ) {
            GeistSection(footer: modeFooter) {
                GeistToggleRow(
                    title: "Enable clipboard manager",
                    description: "Records copies so you can find and reuse them later.",
                    isOn: $enableClipboardManager,
                    divider: enableClipboardManager
                )

                if enableClipboardManager {
                    GeistSegmentedRow(title: "Clipboard appears as", selection: $displayMode, divider: false) {
                        ForEach(ToolDisplayMode.allCases) { Text($0.displayName).tag($0) }
                    }
                    .help(displayMode.description(toolName: String(localized: "the clipboard history")))
                }
            }

            if enableClipboardManager {
                privacySection
                historySection
                contentTypesSection
                pasteSection
                shortcutSection
                ignoredAppsSection
            }
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        GeistSection(
            title: "Privacy",
            footer: "Copies marked confidential by the source app are never recorded — that covers password managers using the org.nspasteboard.ConcealedType convention, plus 1Password and KeeWeb's own markers. Use “Ignore next copy” in the clipboard menu for anything else you would rather not store."
        ) {
            GeistLabeledRow(title: "Stored on this Mac") {
                Text(storageSummary)
                    .font(Geist.Typography.mono)
                    .foregroundStyle(Geist.Colors.mute)
            }
            GeistToggleRow(
                title: "Also clear the system clipboard",
                description: "When you clear the history, wipe what is currently on the clipboard too.",
                isOn: $clearSystemClipboard
            )
            GeistLabeledRow(title: "Clear history now", divider: false) {
                HStack(spacing: 8) {
                    Button(String(localized: "Clear unpinned")) { monitor.clearUnpinned() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button(String(localized: "Clear all")) { monitor.clearAll() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .disabled(monitor.items.isEmpty)
            }
        }
    }

    private var storageSummary: String {
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(monitor.totalByteCount), countStyle: .file)
        return "\(monitor.items.count) items · \(bytes)"
    }

    // MARK: - History

    private var historySection: some View {
        GeistSection(
            title: "History",
            footer: "Pinned entries are never evicted, whatever the limit says. Checking more often catches fast successive copies at the cost of a little more idle work — macOS has no clipboard-change notification, so this is a poll."
        ) {
            GeistStepperRow(
                title: "Entries to keep",
                description: "Unpinned entries beyond this are dropped, oldest first.",
                value: $historySize,
                range: 10...1_000,
                step: 10,
                valueLabel: "\(historySize)"
            )
            GeistPickerRow(title: "Sort by", selection: $sortMode) {
                ForEach(ClipboardSortMode.allCases) { Text($0.displayName).tag($0) }
            }
            GeistSliderRow(
                title: "Check interval",
                valueLabel: String(format: "%.1fs", checkInterval),
                value: $checkInterval,
                range: 0.2...2.0,
                step: 0.1
            )
            GeistToggleRow(
                title: "Show the source app",
                description: "Draws the icon of the app a clip came from on each row.",
                isOn: $showSourceApp,
                divider: false
            )
        }
    }

    // MARK: - Content types

    private var contentTypesSection: some View {
        GeistSection(
            title: "Content",
            footer: "Turning a type off stops it from being recorded at all. Large payloads are written to Application Support rather than kept in the index."
        ) {
            ForEach(Array(ClipboardPasteboard.supportedTypes.enumerated()), id: \.element.rawValue) { index, type in
                GeistToggleRow(
                    title: label(for: type),
                    description: description(for: type),
                    isOn: binding(for: type),
                    divider: index < ClipboardPasteboard.supportedTypes.count - 1
                )
            }
            GeistStepperRow(
                title: "Skip entries larger than",
                value: megabyteBinding,
                range: 1...200,
                step: 1,
                divider: false,
                valueLabel: "\(megabyteBinding.wrappedValue) MB"
            )
        }
    }

    private var megabyteBinding: Binding<Int> {
        Binding(
            get: { max(1, maxItemBytes / (1024 * 1024)) },
            set: { maxItemBytes = $0 * 1024 * 1024 }
        )
    }

    private func label(for type: NSPasteboard.PasteboardType) -> String {
        switch type {
        case .string: return String(localized: "Plain text")
        case .rtf: return String(localized: "Rich text")
        case .html: return String(localized: "HTML")
        case .png: return String(localized: "PNG images")
        case .tiff: return String(localized: "TIFF images")
        case .fileURL: return String(localized: "Files")
        default: return type.rawValue
        }
    }

    private func description(for type: NSPasteboard.PasteboardType) -> String? {
        switch type {
        case .rtf, .html:
            return String(localized: "Kept alongside the plain text so formatting survives a paste.")
        case .fileURL:
            return String(localized: "Stores the file references, not copies of the files.")
        default:
            return nil
        }
    }

    private func binding(for type: NSPasteboard.PasteboardType) -> Binding<Bool> {
        Binding(
            get: { enabledTypes.contains(type.rawValue) },
            set: { isOn in
                if isOn {
                    enabledTypes.insert(type.rawValue)
                } else {
                    enabledTypes.remove(type.rawValue)
                }
            }
        )
    }

    // MARK: - Paste

    private var pasteSection: some View {
        GeistSection(title: "Pasting", footer: pasteFooter) {
            GeistToggleRow(
                title: "Paste automatically",
                description: "Selecting an entry pastes it into the app you came from, instead of only putting it on the clipboard.",
                isOn: $pasteAutomatically
            )
            if pasteAutomatically && !accessibility.isAuthorized {
                GeistLabeledRow(title: "Accessibility permission required", divider: false) {
                    Button(String(localized: "Grant")) {
                        accessibility.requestAuthorizationPrompt()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    private var shortcutSection: some View {
        GeistSection(title: "Shortcut", footer: shortcutFooter) {
            GeistLabeledRow(title: "Open clipboard history", divider: false) {
                KeyboardShortcuts.Recorder("", name: .showClipboardHistory)
            }
        }
    }

    /// The master switch on the Shortcuts page gates every hotkey in the app, so
    /// say so here rather than letting a recorded shortcut silently do nothing.
    private var shortcutFooter: String {
        let base = String(localized: "Opens the history wherever you are — the Clipboard tab in tab mode, the header popover in popover mode.")
        guard !enableShortcuts else { return base }
        return base + " " + String(localized: "Global keyboard shortcuts are turned off — this will not fire until you enable “Enable global keyboard shortcuts” in Settings › Shortcuts.")
    }

    private var pasteFooter: String {
        "Hold ⌥ while selecting an entry to paste it even when automatic pasting is off, and ⌥⇧ to paste it without formatting. Automatic pasting synthesizes ⌘V, which needs Accessibility permission and assumes a QWERTY V key position."
    }

    // MARK: - Ignored apps

    private var ignoredAppsSection: some View {
        GeistSection(
            title: "Ignored apps",
            footer: "Copies made while one of these apps is frontmost are not recorded. Enter bundle identifiers, e.g. com.apple.Terminal."
        ) {
            ForEach(Array(ignoredApps).sorted(), id: \.self) { bundleID in
                GeistLabeledRow(title: bundleID) {
                    Button {
                        ignoredApps.remove(bundleID)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Geist.Colors.mute)
                }
            }
            GeistLabeledRow(title: "Add an app", divider: false) {
                HStack(spacing: 8) {
                    TextField("com.example.app", text: $newIgnoredApp)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onSubmit(addIgnoredApp)
                    Button(String(localized: "Add"), action: addIgnoredApp)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(newIgnoredApp.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addIgnoredApp() {
        let trimmed = newIgnoredApp.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        ignoredApps.insert(trimmed)
        newIgnoredApp = ""
    }

    // MARK: - Footers

    private var modeFooter: String {
        switch displayMode {
        case .tab:
            let width = Int(recommendedMinimumNotchWidth(forTabCount: enabledStandardTabCount()))
            return "Tab mode adds a tab to the open notch, which needs at least \(width)pt of notch width with your current tabs. Popover mode uses a header button instead and costs no width."
        case .popover:
            return "Popover mode puts a clipboard button in the notch header. Tab mode gives the history a full tab instead."
        }
    }
}
