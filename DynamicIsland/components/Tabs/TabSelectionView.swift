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

struct TabModel: Identifiable {
    let id: String
    let label: String
    let icon: String
    let view: NotchViews

    init(label: String, icon: String, view: NotchViews) {
        self.id = "system-\(view)-\(label)"
        self.label = label
        self.icon = icon
        self.view = view
    }
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @StateObject private var quickShareService = QuickShareService.shared
    @Default(.quickShareProvider) private var quickShareProvider
    @State private var showQuickSharePopover = false
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.timerDisplayMode) var timerDisplayMode
    @Default(.showCalendar) private var showCalendar
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.enableMinimalisticUI) private var enableMinimalisticUI
    @Namespace var animation
    
    private var tabs: [TabModel] {
        var tabsArray: [TabModel] = []

        if homeTabVisible {
            tabsArray.append(TabModel(label: "Home", icon: "house.fill", view: .home))
        }

        if Defaults[.dynamicShelf] {
            tabsArray.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }
        
        if enableTimerFeature && timerDisplayMode == .tab {
            tabsArray.append(TabModel(label: "Timer", icon: "timer", view: .timer))
        }
        if Defaults[.enableAgentMonitoring] {
            tabsArray.append(TabModel(label: "Agents", icon: "sparkles", view: .agents))
        }
        if Defaults[.showCalendar] {
            tabsArray.append(TabModel(label: "Calendar", icon: "calendar", view: .calendar))
        }
        if Defaults[.enableNotificationMonitoring] {
            tabsArray.append(TabModel(label: "Notifications", icon: "bell.fill", view: .notifications))
        }
        if Defaults[.enableWeather] {
            tabsArray.append(TabModel(label: "Weather", icon: "cloud.sun.fill", view: .weather))
        }
        return tabsArray
    }
    var body: some View {
        HStack(spacing: 24) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { idx, tab in
                let isSelected = isSelected(tab)

                // Render the tab button
                TabButton(label: tab.label, icon: tab.icon, selected: isSelected) {
                    coordinator.currentView = tab.view
                }
                .frame(height: 26)
                .foregroundStyle(isSelected ? .white : .gray)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color(nsColor: .secondarySystemFill).opacity(0.25))
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                            .hidden()
                    }
                }

                
            }
        }
        .animation(.smooth(duration: 0.3), value: coordinator.currentView)
        .clipShape(Capsule())
        .onAppear {
            ensureValidSelection(with: tabs)
        }
    }

    private var homeTabVisible: Bool {
        if enableMinimalisticUI {
            return true
        }
        return showStandardMediaControls || showCalendar
    }

    private func isSelected(_ tab: TabModel) -> Bool {
        return coordinator.currentView == tab.view
    }

    private func ensureValidSelection(with tabs: [TabModel]) {
        guard !tabs.isEmpty else { return }
        if tabs.contains(where: { isSelected($0) }) {
            return
        }
        guard let first = tabs.first else { return }
        coordinator.currentView = first.view
    }
}

#Preview {
    DynamicIslandHeader().environmentObject(DynamicIslandViewModel())
}
