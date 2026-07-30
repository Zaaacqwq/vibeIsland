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
import Combine
import Defaults
import SwiftUI

/// Owns the eyedropper and the picked-color history.
///
/// Sampling goes through `NSColorSampler`, which runs the loupe **out of
/// process**: no Screen Recording permission is required, unlike a
/// self-rolled magnifier built on ScreenCaptureKit.
@MainActor
final class ColorPickerManager: ObservableObject {
    static let shared = ColorPickerManager()

    /// True while the system loupe is on screen. The UI uses it to disable the
    /// pick button — `NSColorSampler` ignores a second `show` while active.
    @Published private(set) var isSampling = false

    /// The format most recently copied, so the UI can flash a confirmation on
    /// the right chip.
    @Published private(set) var lastCopied: (colorID: UUID, format: ColorFormat)?

    private var sampler: NSColorSampler?
    private var lastCopiedResetTask: Task<Void, Never>?

    private init() {}

    var history: [PickedColor] { Defaults[.colorPickerHistory] }

    var mostRecent: PickedColor? { history.first }

    // MARK: - Sampling

    func pick() {
        guard !isSampling else { return }
        isSampling = true

        // Retained for the lifetime of the sampling session: NSColorSampler
        // cancels itself when deallocated, so a local would end the session the
        // moment this function returns.
        let sampler = NSColorSampler()
        self.sampler = sampler

        sampler.show { [weak self] color in
            guard let self else { return }
            self.isSampling = false
            self.sampler = nil
            guard let color else { return }  // nil == user pressed Escape
            self.record(color)
        }
    }

    /// Adds a sample to the front of the history, collapsing a repeat of the
    /// swatch that is already newest instead of stacking duplicates.
    @discardableResult
    func record(_ nsColor: NSColor) -> PickedColor {
        let picked = PickedColor(nsColor: nsColor)
        var items = history

        if let first = items.first, first.hasSameComponents(as: picked) {
            items[0] = picked
        } else {
            items.removeAll { $0.hasSameComponents(as: picked) }
            items.insert(picked, at: 0)
        }

        let limit = max(1, Defaults[.colorPickerHistoryLimit])
        Defaults[.colorPickerHistory] = Array(items.prefix(limit))

        if Defaults[.colorPickerCopyOnPick] {
            copy(picked, as: Defaults[.colorPickerDefaultFormat])
        }

        return picked
    }

    // MARK: - History mutation

    func remove(_ color: PickedColor) {
        Defaults[.colorPickerHistory].removeAll { $0.id == color.id }
    }

    func clearHistory() {
        Defaults[.colorPickerHistory] = []
    }

    // MARK: - Copying

    func copy(_ color: PickedColor, as format: ColorFormat) {
        let text = format.string(for: color, uppercaseHex: Defaults[.colorPickerUppercaseHex])
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        lastCopied = (color.id, format)
        lastCopiedResetTask?.cancel()
        lastCopiedResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.lastCopied = nil
        }
    }

    func string(for color: PickedColor, as format: ColorFormat) -> String {
        format.string(for: color, uppercaseHex: Defaults[.colorPickerUppercaseHex])
    }

    func isFlashing(_ color: PickedColor, format: ColorFormat) -> Bool {
        lastCopied?.colorID == color.id && lastCopied?.format == format
    }
}
