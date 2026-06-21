/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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
import SwiftUI

/// Developer/debug tools: preview any combination of closed-pill activities and
/// tint the notch background to inspect the layout.
struct DebugSettings: View {
    @Default(.debugNotchBackgroundEnabled) private var debugNotchBackgroundEnabled
    @Default(.debugNotchBackgroundColor) private var debugNotchBackgroundColor
    @Default(.debugForcedActivities) private var debugForcedActivities

    /// Activities that can be previewed with sample data.
    private let previewableActivities: [ClosedNotchActivityKind] = [
        .music, .agent, .timer, .weather, .focus, .recording, .download, .localSend, .privacy, .shelf,
    ]

    var body: some View {
        GeistSettingsPage(title: "Debug", subtitle: "Preview activity combinations and inspect the notch layout.") {
            GeistSection(
                title: "Preview activities",
                footer: "Only the two highest-priority activities show at once (see Live Activities → Closed Notch Priority). Reminder and extension activities can't be previewed with sample data."
            ) {
                ForEach(Array(previewableActivities.enumerated()), id: \.element) { index, kind in
                    GeistToggleRow(
                        title: kind.displayName,
                        isOn: Binding(
                            get: { debugForcedActivities.contains(kind) },
                            set: { isOn in
                                if isOn { debugForcedActivities.insert(kind) }
                                else { debugForcedActivities.remove(kind) }
                            }
                        ),
                        divider: index < previewableActivities.count - 1
                    )
                }
            }

            if !debugForcedActivities.isEmpty {
                Button("Clear preview") { debugForcedActivities = [] }
                    .buttonStyle(.geist)
            }

            GeistSection(
                title: "Notch background",
                footer: "Replaces the notch's black background with a colour so you can see each region's boundaries. The centre notch fill stays black for contrast."
            ) {
                GeistToggleRow(
                    title: "Tint notch background",
                    isOn: $debugNotchBackgroundEnabled,
                    divider: debugNotchBackgroundEnabled
                )
                if debugNotchBackgroundEnabled {
                    GeistRow(divider: false) {
                        ColorPicker("Background color", selection: $debugNotchBackgroundColor, supportsOpacity: true)
                            .font(Geist.Typography.bodyStrong)
                            .foregroundStyle(Geist.Colors.ink)
                    }
                }
            }
        }
    }
}
