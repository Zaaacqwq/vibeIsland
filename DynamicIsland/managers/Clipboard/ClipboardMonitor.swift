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
import Foundation

/// Watches the system pasteboard and owns the clipboard history.
///
/// macOS has no change notification for `NSPasteboard`, so the only option is
/// polling `changeCount` — the same approach every clipboard manager on the
/// platform takes.
@MainActor
final class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()

    /// History in storage order: pinned entries are *not* hoisted here, only in
    /// ``displayItems(matching:)``, so pinning never loses recency information.
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var isRunning = false
    /// Set while the next copy is being deliberately skipped, so the UI can show
    /// the armed state.
    @Published private(set) var isIgnoringNextCopy = false

    private let pasteboard = NSPasteboard.general
    private let store = ClipboardStore.shared
    private var changeCount: Int
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var persistTask: Task<Void, Never>?
    private var didLoad = false

    private init() {
        changeCount = NSPasteboard.general.changeCount
    }

    // MARK: - Lifecycle

    /// Loads the stored history and binds the monitor's running state to the
    /// feature toggle. Safe to call more than once.
    func bootstrap() {
        guard !didLoad else { return }
        didLoad = true

        Task { [weak self] in
            guard let self else { return }
            let loaded = await store.load()
            self.items = loaded
        }

        Defaults.publisher(.enableClipboardManager)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                if change.newValue {
                    self?.start()
                } else {
                    self?.stop()
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.clipboardCheckInterval)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isRunning else { return }
                self.restart()
            }
            .store(in: &cancellables)

        if Defaults[.enableClipboardManager] {
            start()
        }
    }

    func start() {
        guard timer == nil else { return }
        // Adopt the current change count so enabling the feature does not
        // immediately record whatever happened to be on the pasteboard.
        changeCount = pasteboard.changeCount
        isRunning = true

        let interval = max(0.1, Defaults[.clipboardCheckInterval])
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkForChanges()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    func restart() {
        stop()
        start()
    }

    /// Skips the next copy — the "don't record this one" escape hatch for a
    /// password or token the user is about to copy by hand.
    func ignoreNextCopy() {
        isIgnoringNextCopy = true
    }

    // MARK: - Capture

    func checkForChanges() {
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount

        if isIgnoringNextCopy {
            isIgnoringNextCopy = false
            return
        }

        guard let pasteboardItems = pasteboard.pasteboardItems, !pasteboardItems.isEmpty else { return }

        let source = frontmostSource()
        if let bundleID = source.bundleID, Defaults[.clipboardIgnoredApps].contains(bundleID) {
            return
        }

        let representations: [[String: Data]] = pasteboardItems.map { item in
            var representation: [String: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { continue }
                representation[type.rawValue] = data
            }
            return representation
        }

        guard let capture = ClipboardCapture.makeItem(
            representations: representations,
            enabledTypes: Defaults[.clipboardEnabledTypes],
            source: source,
            maxItemBytes: Defaults[.clipboardMaxItemBytes]
        ) else { return }

        record(capture, source: source)
    }

    private func record(_ capture: ClipboardCapture.Result, source: ClipboardCapture.Source) {
        if let index = items.firstIndex(where: { $0.hasSameContent(as: capture.item) }) {
            let bumped = items[index].recopied(
                sourceAppBundleID: source.bundleID,
                sourceAppName: source.name
            )
            items.remove(at: index)
            items.insert(bumped, at: 0)
            schedulePersist()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let stored = await store.writeBlobs(for: capture.item, values: capture.values)
            // A payload can be dropped if its blob failed to write; an entry
            // with nothing left in it must not enter the history.
            guard !stored.payloads.isEmpty else { return }
            self.items.insert(stored, at: 0)
            self.items = Self.evicting(
                self.items,
                historySize: Defaults[.clipboardHistorySize],
                maxTotalBytes: Defaults[.clipboardMaxTotalBytes]
            )
            self.schedulePersist()
        }
    }

    /// Trims the history to the configured limits. Pinned entries are exempt
    /// from both the count cap and the byte budget — pinning is the user saying
    /// "keep this", and silently dropping it would be a data-loss surprise.
    static func evicting(
        _ items: [ClipboardItem],
        historySize: Int,
        maxTotalBytes: Int
    ) -> [ClipboardItem] {
        var kept = items
        let limit = max(1, historySize)

        var unpinnedSeen = 0
        kept = kept.filter { item in
            guard !item.isPinned else { return true }
            unpinnedSeen += 1
            return unpinnedSeen <= limit
        }

        var total = kept.reduce(0) { $0 + $1.totalByteCount }
        while total > maxTotalBytes,
              let dropIndex = kept.lastIndex(where: { !$0.isPinned }) {
            total -= kept[dropIndex].totalByteCount
            kept.remove(at: dropIndex)
        }

        return kept
    }

    // MARK: - Mutation

    /// Records that an existing entry was put back on the pasteboard.
    ///
    /// Our own write-backs carry a marker that makes ``checkForChanges()`` skip
    /// them, so without this an entry re-used from the history would never move
    /// back to the top of a recency-sorted list.
    func noteReuse(of item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let bumped = items[index].recopied(
            sourceAppBundleID: items[index].sourceAppBundleID,
            sourceAppName: items[index].sourceAppName
        )
        items.remove(at: index)
        items.insert(bumped, at: 0)
        schedulePersist()
    }

    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = items[index].pinned(!items[index].isPinned)
        schedulePersist()
    }

    func delete(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        schedulePersist()
    }

    func clearUnpinned() {
        items = items.filter(\.isPinned)
        clearSystemClipboardIfRequested()
        schedulePersist()
    }

    func clearAll() {
        items = []
        clearSystemClipboardIfRequested()
        Task { [store] in
            await store.removeAll()
        }
    }

    private func clearSystemClipboardIfRequested() {
        guard Defaults[.clipboardClearSystemClipboardOnClear] else { return }
        pasteboard.clearContents()
        changeCount = pasteboard.changeCount
    }

    // MARK: - Presentation

    /// Filtered, sorted, pinned-first view of the history for the UI.
    func displayItems(matching query: String = "") -> [ClipboardItem] {
        let filtered = query.isEmpty ? items : items.filter { $0.matches(query) }
        let sorted = filtered.sorted(by: Self.comparator(for: Defaults[.clipboardSortMode]))
        let pinned = sorted.filter(\.isPinned)
        let rest = sorted.filter { !$0.isPinned }
        return pinned + rest
    }

    static func comparator(for mode: ClipboardSortMode) -> (ClipboardItem, ClipboardItem) -> Bool {
        switch mode {
        case .lastCopied:
            return { $0.lastCopiedAt > $1.lastCopiedAt }
        case .firstCopied:
            return { $0.firstCopiedAt > $1.firstCopiedAt }
        case .numberOfCopies:
            return {
                $0.numberOfCopies == $1.numberOfCopies
                    ? $0.lastCopiedAt > $1.lastCopiedAt
                    : $0.numberOfCopies > $1.numberOfCopies
            }
        }
    }

    // MARK: - Helpers

    /// Ignores our own process so a copy made from inside the app is still
    /// attributed to the app the user was actually working in.
    private func frontmostSource() -> ClipboardCapture.Source {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return ClipboardCapture.Source(
                bundleID: ClipboardPaster.shared.lastExternalApp?.bundleIdentifier,
                name: ClipboardPaster.shared.lastExternalApp?.localizedName
            )
        }
        return ClipboardCapture.Source(bundleID: app.bundleIdentifier, name: app.localizedName)
    }

    /// Coalesces the index write: a burst of copies (or a pin toggled twice)
    /// should not rewrite the whole index once per change.
    private func schedulePersist() {
        persistTask?.cancel()
        let snapshot = items
        persistTask = Task { [store] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await store.persist(snapshot)
        }
    }

    /// Bytes currently held by the history, for the settings page.
    var totalByteCount: Int {
        items.reduce(0) { $0 + $1.totalByteCount }
    }
}
