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
        Form {
            Section {
                if debugForcedActivities.isEmpty {
                    Text("Turn an activity on to force it into the closed notch with sample data. Enable two to preview a pair.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(previewableActivities) { kind in
                    Toggle(isOn: Binding(
                        get: { debugForcedActivities.contains(kind) },
                        set: { isOn in
                            if isOn { debugForcedActivities.insert(kind) }
                            else { debugForcedActivities.remove(kind) }
                        }
                    )) {
                        Label(kind.displayName, systemImage: kind.systemImage)
                            .labelStyle(.titleAndIcon)
                    }
                }
                if !debugForcedActivities.isEmpty {
                    Button("Clear preview") { debugForcedActivities = [] }
                }
            } header: {
                Text("Preview activities")
            } footer: {
                Text("Only the two highest-priority activities show at once (see Live Activities → Closed Notch Priority). Reminder and extension activities can't be previewed with sample data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle(key: .debugNotchBackgroundEnabled) {
                    Text("Tint notch background")
                }
                if debugNotchBackgroundEnabled {
                    ColorPicker("Background color", selection: $debugNotchBackgroundColor, supportsOpacity: true)
                }
            } header: {
                Text("Notch background")
            } footer: {
                Text("Replaces the notch's black background with a colour so you can see each region's boundaries. The centre notch fill stays black for contrast.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Debug")
    }
}
