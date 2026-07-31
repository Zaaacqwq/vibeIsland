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

import Defaults
import KeyboardShortcuts
import SwiftUI

/// Settings pane for the color picker utility.
struct ColorPickerSettings: View {
    @ObservedObject private var manager = ColorPickerManager.shared
    @Default(.enableColorPicker) private var enableColorPicker
    @Default(.colorPickerDisplayMode) private var displayMode
    @Default(.colorPickerDefaultFormat) private var defaultFormat
    @Default(.colorPickerCopyOnPick) private var copyOnPick
    @Default(.colorPickerUppercaseHex) private var uppercaseHex
    @Default(.colorPickerHistoryLimit) private var historyLimit
    @Default(.enableShortcuts) private var enableShortcuts

    var body: some View {
        GeistSettingsPage(
            title: "Color Picker",
            subtitle: "Sample any color on screen and copy it in the format you need."
        ) {
            GeistSection {
                GeistToggleRow(
                    title: "Enable color picker",
                    description: "Adds the eyedropper to the notch, with a history of what you have picked.",
                    isOn: $enableColorPicker,
                    divider: enableColorPicker
                )

                if enableColorPicker {
                    GeistSegmentedRow(
                        title: "Color picker appears as",
                        selection: $displayMode,
                        divider: false,
                        info: modeFooter
                    ) {
                        ForEach(ToolDisplayMode.allCases) { Text($0.displayName).tag($0) }
                    }
                }
            }

            if enableColorPicker {
                GeistSection(
                    title: "Copying",
                    noteBullets: [
                        "Click a swatch: copy it in the default format.",
                        "Right-click a swatch: choose any available format."
                    ]
                ) {
                    // Only the short name goes in the menu: `GeistPickerRow`
                    // fixed-sizes its picker, so a label carrying the whole
                    // sample string (`NSColor(srgbRed: …)`) widens the settings
                    // page past the window. The sample gets its own row.
                    GeistPickerRow(title: "Default format", selection: $defaultFormat) {
                        ForEach(ColorFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    GeistLabeledRow(title: "Example") {
                        Text(sample(defaultFormat))
                            .font(Geist.Typography.mono)
                            .foregroundStyle(Geist.Colors.mute)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    GeistToggleRow(
                        title: "Copy immediately after picking",
                        description: "Makes the eyedropper a one-shot gesture: sample, and the value is already on the clipboard.",
                        isOn: $copyOnPick
                    )
                    GeistToggleRow(
                        title: "Uppercase hex",
                        description: "Writes #FF8000 instead of #ff8000.",
                        isOn: $uppercaseHex,
                        divider: false
                    )
                }

                GeistSection(title: "Shortcut", note: shortcutWarning) {
                    GeistLabeledRow(
                        title: "Pick a color",
                        divider: false,
                        info: shortcutExplanation
                    ) {
                        KeyboardShortcuts.Recorder("", name: .pickColor)
                    }
                }

                GeistSection(title: "History", note: historyNote) {
                    GeistStepperRow(
                        title: "Colors to keep",
                        value: $historyLimit,
                        range: 5...200,
                        step: 5,
                        valueLabel: "\(historyLimit)"
                    )
                    GeistLabeledRow(title: "Clear history", divider: false) {
                        Button(String(localized: "Clear")) {
                            manager.clearHistory()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(manager.history.isEmpty)
                    }
                }
            }
        }
    }

    private var modeFooter: String {
        switch displayMode {
        case .tab:
            let width = Int(recommendedMinimumNotchWidth(forTabCount: enabledStandardTabCount()))
            return "Tab mode adds a tab to the open notch, which needs at least \(width)pt of notch width with your current tabs. Popover mode uses a header button instead and costs no width."
        case .popover:
            return "Popover mode puts an eyedropper button in the notch header. Tab mode gives the picker a full tab instead."
        }
    }

    /// The master switch on the Shortcuts page gates every hotkey in the app, so
    /// say so here rather than letting a recorded shortcut silently do nothing.
    private var shortcutExplanation: String {
        String(localized: "Opens the system loupe straight away, without opening the notch first.")
    }

    private var shortcutWarning: String? {
        guard !enableShortcuts else { return nil }
        return String(localized: "Global keyboard shortcuts are off. Enable them in Settings › Shortcuts before using this shortcut.")
    }

    private var historyNote: String {
        String(
            localized: "Picked colors are stored in preferences (\(manager.history.count) saved). Only the pixel you click is captured."
        )
    }

    private func sample(_ format: ColorFormat) -> String {
        format.string(for: PickedColor(red: 1, green: 0.5, blue: 0), uppercaseHex: uppercaseHex)
    }
}
