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

import SwiftUI
import Defaults
import AppKit

struct TabSelectionView: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.notchTabOrder) private var storedOrder
    @Default(.showNotchTabTitles) private var showTabTitles
    @Default(.enableTabReordering) private var enableTabReordering
    // Visibility inputs. Read here (rather than only inside `NotchTabOrder`) so
    // SwiftUI re-renders the row when a tab is switched on or off.
    @Default(.enableTimerFeature) private var enableTimerFeature
    @Default(.timerDisplayMode) private var timerDisplayMode
    @Default(.enableColorPicker) private var enableColorPicker
    @Default(.colorPickerDisplayMode) private var colorPickerDisplayMode
    @Default(.enableClipboardManager) private var enableClipboardManager
    @Default(.clipboardDisplayMode) private var clipboardDisplayMode
    @Default(.showCalendar) private var showCalendar
    @Default(.showReminders) private var showReminders
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.dynamicShelf) private var dynamicShelf
    @Default(.enableAgentMonitoring) private var enableAgentMonitoring
    @Default(.enableNotificationMonitoring) private var enableNotificationMonitoring
    @Default(.enableWeather) private var enableWeather
    @Default(.enableSystemMonitor) private var enableSystemMonitor
    @Default(.enableMinimalisticUI) private var enableMinimalisticUI
    @Namespace var animation

    /// Drag state. `dragOrder` is frozen at drag start and the row keeps rendering
    /// it unchanged — the preview happens entirely through per-tab offsets, never by
    /// reordering the array mid-drag.
    ///
    /// An earlier version did reorder live and compensated the dragged tab's offset
    /// by one `slotWidth` per shuffle. That compensation has to cancel the layout
    /// shift *exactly*, and frame-by-frame measurement of a real drag showed it
    /// missing by ~3pt at the swap — the tab twitched backwards and the cursor's
    /// grip on the icon slid. With the array frozen there is nothing to cancel.
    @State private var draggingTab: NotchViews?
    @State private var dragOriginIndex: Int?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragOrder: [NotchViews] = []

    /// One tab slot: the icon-only button plus the row's 4pt spacing. Drag
    /// distances are measured in these, so it has to track `TabButton`.
    private static let slotWidth: CGFloat = TabButton.iconOnlyWidth + 4

    private var tabs: [NotchViews] {
        if draggingTab != nil, !dragOrder.isEmpty { return dragOrder }
        return NotchTabOrder.visibleTabs()
    }

    /// Where the dragged tab would land if released now.
    private var dragTargetIndex: Int? {
        guard let origin = dragOriginIndex, !dragOrder.isEmpty else { return nil }
        let slots = Int((dragTranslation / Self.slotWidth).rounded())
        return min(max(origin + slots, 0), dragOrder.count - 1)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .animation(.smooth(duration: 0.3), value: coordinator.currentView)
        .animation(.smooth(duration: 0.22), value: tabs)
        .onAppear { ensureValidSelection() }
        .onChange(of: tabs) { _, _ in ensureValidSelection() }
    }

    @ViewBuilder
    private func tabButton(_ tab: NotchViews) -> some View {
        let isSelected = coordinator.currentView == tab
        let isDragging = draggingTab == tab

        TabButton(
            label: tab.tabLabel,
            icon: tab.tabIcon,
            selected: isSelected,
            showsTitle: showTabTitles
        ) {
            coordinator.currentView = tab
        }
        .foregroundStyle(isSelected ? NotchDesign.Colors.textPrimary : NotchDesign.Colors.textTertiary)
        .background {
            if isSelected {
                Capsule()
                    .fill(Color.white.opacity(0.09))
                    .matchedGeometryEffect(id: "capsule", in: animation)
            } else {
                Capsule()
                    .fill(Color.clear)
                    .matchedGeometryEffect(id: "capsule", in: animation)
                    .hidden()
            }
        }
        // Scale FIRST, offset second. Modifiers compose outward, so `.offset`
        // inside `.scaleEffect` gets scaled along with the view — the tab then
        // travelled 1.18× the cursor's distance and ran ahead of the pointer.
        // With the offset outside, the lift no longer touches the translation.
        .scaleEffect(isDragging ? 1.18 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.5 : 0), radius: 6, y: 2)
        // The lifted tab is offset by the raw drag translation — its slot never
        // moves, so this tracks the cursor exactly for the whole gesture.
        .offset(x: isDragging ? dragTranslation : displacement(for: tab))
        .zIndex(isDragging ? 1 : 0)
        // Neighbours glide into the gap; the lifted tab must not animate, or it
        // would lag behind the pointer.
        .animation(isDragging ? nil : .smooth(duration: 0.16), value: dragTargetIndex)
        .transaction { transaction in
            if isDragging { transaction.animation = nil }
        }
        // Composes with `TabButton`'s tap gesture: a click selects, a ⌘-drag past
        // 4pt reorders. (`TabButton` is not a `Button` precisely so this works —
        // see the note there.)
        .gesture(reorderGesture(for: tab))
    }

    // MARK: - Reordering

    /// ⌘-drag only, so a plain click still selects the tab and a plain drag on the
    /// notch keeps whatever meaning it already had.
    private func reorderGesture(for tab: NotchViews) -> some Gesture {
        // `.global`, not the default local space: the dragged tab is moved by
        // `.offset`, and a local-space gesture measures translation against that
        // moving view — the reading then oscillates instead of growing (observed:
        // 4, 9, 14, 19, 23, then back to 14 once the row shuffled), so the tab
        // jittered in place and long drags landed one slot short.
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                guard enableTabReordering, !enableMinimalisticUI else { return }

                if draggingTab == nil {
                    // Checked at drag start rather than continuously: releasing ⌘
                    // mid-drag shouldn't abandon the tab somewhere arbitrary.
                    guard NSEvent.modifierFlags.contains(.command) else { return }
                    let order = NotchTabOrder.visibleTabs()
                    guard order.count > 1, let index = order.firstIndex(of: tab) else { return }
                    draggingTab = tab
                    dragOriginIndex = index
                    dragOrder = order
                }

                guard draggingTab == tab else { return }
                dragTranslation = value.translation.width
            }
            .onEnded { _ in
                defer { resetDragState() }
                // The array was never touched during the drag, so the committed
                // order is built here from where the tab ended up.
                guard let dragged = draggingTab,
                      let origin = dragOriginIndex,
                      let target = dragTargetIndex,
                      target != origin,
                      dragOrder.indices.contains(origin) else { return }

                var committed = dragOrder
                committed.remove(at: origin)
                committed.insert(dragged, at: target)
                NotchTabOrder.persist(visibleOrder: committed)
            }
    }

    /// How far a *non-dragged* tab steps aside to open a gap at the drop position.
    /// Tabs between the origin and the target shift by one slot, everything else
    /// stays put.
    private func displacement(for tab: NotchViews) -> CGFloat {
        guard draggingTab != nil,
              let origin = dragOriginIndex,
              let target = dragTargetIndex,
              let index = dragOrder.firstIndex(of: tab),
              target != origin else { return 0 }

        if target > origin, index > origin, index <= target { return -Self.slotWidth }
        if target < origin, index >= target, index < origin { return Self.slotWidth }
        return 0
    }

    private func resetDragState() {
        draggingTab = nil
        dragOriginIndex = nil
        dragTranslation = 0
        dragOrder = []
    }

    // MARK: - Selection

    private func ensureValidSelection() {
        let visible = tabs
        guard !visible.isEmpty else { return }
        guard !visible.contains(coordinator.currentView) else { return }
        coordinator.currentView = visible[0]
    }
}

#Preview {
    DynamicIslandHeader().environmentObject(DynamicIslandViewModel())
}
