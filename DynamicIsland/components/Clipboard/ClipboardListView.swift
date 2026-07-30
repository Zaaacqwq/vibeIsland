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
import SwiftUI

/// The clipboard history, shared by both presentation modes.
///
/// One view parameterized by ``ToolDisplayMode`` (as with the color picker), so
/// the popover and the notch tab cannot drift apart in behavior — only in
/// density and height policy.
struct ClipboardListView: View {
    let mode: ToolDisplayMode

    @ObservedObject private var monitor = ClipboardMonitor.shared
    @Default(.clipboardSortMode) private var sortMode
    @Default(.clipboardPasteAutomatically) private var pasteAutomatically

    @State private var searchText = ""
    @State private var selectedID: UUID?
    @FocusState private var searchFocused: Bool

    /// Suppresses the notch's scroll-to-close gesture while the pointer is over
    /// the list, so a vertical scroll browses history instead of shutting the
    /// notch. Same pattern the Calendar tab uses.
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var scrollSuppressionToken = UUID()

    private var isTab: Bool { mode == .tab }

    private var visibleItems: [ClipboardItem] {
        monitor.displayItems(matching: searchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isTab ? 8 : 10) {
            // In tab mode the search field shares the title row: the notch's
            // tab height only fits a couple of rows, and a dedicated search row
            // costs one of them.
            if isTab {
                HStack(spacing: 10) {
                    identity
                    Spacer(minLength: 8)
                    searchField.frame(width: 220)
                    actionsMenu
                }
            } else {
                header
                searchField
            }

            if visibleItems.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .onAppear { selectFirstIfNeeded() }
        .onChange(of: searchText) { _, _ in selectedID = visibleItems.first?.id }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            identity
            Spacer(minLength: 8)
            actionsMenu
        }
    }

    private var identity: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(ToolPanelStyle.iconTile)
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ToolPanelStyle.title)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Clipboard"))
                    .font(NotchDesign.Typography.voice(14, weight: .semibold))
                    .foregroundStyle(ToolPanelStyle.title)
                Text(statusText)
                    .font(NotchDesign.Typography.mono(11, weight: .medium))
                    .foregroundStyle(monitor.isIgnoringNextCopy ? NotchDesign.Colors.warning : ToolPanelStyle.muted)
            }
        }
    }

    private var statusText: String {
        if monitor.isIgnoringNextCopy {
            return String(localized: "Skipping next copy")
        }
        if !monitor.isRunning {
            return String(localized: "Paused")
        }
        let count = monitor.items.count
        return count == 1 ? String(localized: "1 item") : String(localized: "\(count) items")
    }

    private var actionsMenu: some View {
        Menu {
            Picker(String(localized: "Sort by"), selection: $sortMode) {
                ForEach(ClipboardSortMode.allCases) { Text($0.displayName).tag($0) }
            }
            Toggle(String(localized: "Paste automatically"), isOn: $pasteAutomatically)
            Divider()
            Button(String(localized: "Ignore next copy")) { monitor.ignoreNextCopy() }
            Divider()
            Button(String(localized: "Clear unpinned")) { monitor.clearUnpinned() }
            Button(String(localized: "Clear all"), role: .destructive) { monitor.clearAll() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ToolPanelStyle.muted)
                .frame(width: 26, height: 26)
                .background(Circle().fill(ToolPanelStyle.chipFill))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 26, height: 26)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ToolPanelStyle.faint)

            TextField(String(localized: "Search"), text: $searchText)
                .textFieldStyle(.plain)
                .font(NotchDesign.Typography.voice(12))
                .foregroundStyle(NotchDesign.Colors.textPrimary)
                .focused($searchFocused)
                // Arrow keys and Return drive the list while the field has
                // focus; returning `.handled` keeps the field from consuming
                // them for caret movement.
                .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
                .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
                .onKeyPress(.return) {
                    activateSelection(ClipboardActivation.current())
                    return .handled
                }
                .onKeyPress(.escape) {
                    if searchText.isEmpty { return .ignored }
                    searchText = ""
                    return .handled
                }
                .onKeyPress(.delete) {
                    // ⌥⌫ deletes the highlighted entry; a bare backspace has to
                    // keep editing the query.
                    guard NSEvent.modifierFlags.contains(.option), let item = selectedItem else { return .ignored }
                    monitor.delete(item)
                    selectFirstIfNeeded()
                    return .handled
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(ToolPanelStyle.faint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: ToolPanelStyle.controlRadius, style: .continuous)
                .fill(ToolPanelStyle.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ToolPanelStyle.controlRadius, style: .continuous)
                .strokeBorder(searchFocused ? Color.white.opacity(0.18) : ToolPanelStyle.cardStroke, lineWidth: 1)
        )
        .onTapGesture { focusSearch() }
    }

    /// The notch panel only receives keystrokes once it is the key window, which
    /// it is not by default — the same dance `AgentInputOverlay` does.
    private func focusSearch() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0 is DynamicIslandWindow }?.makeKeyAndOrderFront(nil)
            searchFocused = true
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(visibleItems) { item in
                        ClipboardRow(
                            item: item,
                            isSelected: item.id == selectedID,
                            onActivate: { activation in
                                selectedID = item.id
                                activate(item, with: activation)
                            },
                            onTogglePin: { monitor.togglePin(item) },
                            onDelete: {
                                monitor.delete(item)
                                selectFirstIfNeeded()
                            }
                        )
                        .id(item.id)
                    }
                }
            }
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        // Bounded in both modes: in tab mode an unbounded list would grow the
        // notch window rather than scroll inside it.
        .frame(maxHeight: isTab ? .infinity : 260)
        .onHover { hovering in
            vm.setScrollGestureSuppression(hovering, token: scrollSuppressionToken)
        }
        .onDisappear {
            vm.setScrollGestureSuppression(false, token: scrollSuppressionToken)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(ToolPanelStyle.faint)
            Text(searchText.isEmpty
                 ? String(localized: "Clipboard history is empty")
                 : String(localized: "No matches"))
                .font(NotchDesign.Typography.voice(12, weight: .medium))
                .foregroundStyle(ToolPanelStyle.muted)
            if searchText.isEmpty {
                Text(String(localized: "Copy something to start the history."))
                    .font(NotchDesign.Typography.caption)
                    .foregroundStyle(ToolPanelStyle.faint)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isTab ? 28 : 18)
        .frame(maxHeight: isTab ? .infinity : nil)
    }

    // MARK: - Actions

    private var selectedItem: ClipboardItem? {
        guard let selectedID else { return nil }
        return visibleItems.first { $0.id == selectedID }
    }

    private func selectFirstIfNeeded() {
        let items = visibleItems
        if let selectedID, items.contains(where: { $0.id == selectedID }) { return }
        selectedID = items.first?.id
    }

    private func moveSelection(by offset: Int) {
        let items = visibleItems
        guard !items.isEmpty else { return }
        guard let selectedID, let index = items.firstIndex(where: { $0.id == selectedID }) else {
            self.selectedID = items.first?.id
            return
        }
        let next = min(max(index + offset, 0), items.count - 1)
        self.selectedID = items[next].id
    }

    private func activateSelection(_ activation: ClipboardActivation) {
        guard let selectedItem else { return }
        activate(selectedItem, with: activation)
    }

    private func activate(_ item: ClipboardItem, with activation: ClipboardActivation) {
        Task {
            if activation.pastesNever {
                await ClipboardPaster.shared.copy(item)
            } else {
                await ClipboardPaster.shared.use(
                    item,
                    removeFormatting: activation.removesFormatting,
                    forcePaste: activation.forcesPaste
                )
            }
        }
    }
}
