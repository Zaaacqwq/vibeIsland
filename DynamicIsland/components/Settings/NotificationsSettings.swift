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

import AppKit
import Defaults
import SwiftUI

/// Settings pane for the Notification Center mirror: master switch, popup +
/// privacy options, Full Disk Access status, and per-app muting.
struct NotificationsSettings: View {
    @ObservedObject var monitor = NotificationMonitorManager.shared
    @Default(.enableNotificationMonitoring) var enableNotificationMonitoring
    @Default(.mutedNotificationApps) var mutedNotificationApps

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableNotificationMonitoring) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable notification mirroring")
                        Text("Show macOS notifications (WeChat, Discord, system, …) in the notch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if enableNotificationMonitoring {
                    Defaults.Toggle(key: .showNotificationLiveActivity) {
                        Text("Pop up the notch on new notifications")
                    }
                    Defaults.Toggle(key: .hideNotificationContent) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hide message content")
                            Text("Show only the app and title, never the body.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("General")
            } footer: {
                Text("Adds a Notifications tab and reads the system Notification Center. Requires Full Disk Access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if enableNotificationMonitoring {
                Section {
                    HStack {
                        Text("Full Disk Access")
                        Spacer()
                        if monitor.hasFullDiskAccess {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .labelStyle(.titleAndIcon)
                        } else {
                            Label("Not granted", systemImage: "xmark.circle")
                                .foregroundStyle(.orange)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    if !monitor.hasFullDiskAccess {
                        Button("Open System Settings…") { openFullDiskAccessSettings() }
                    }
                } header: {
                    Text("Permissions")
                } footer: {
                    Text("VibeIsland reads ~/Library/Group Containers/group.com.apple.usernoted. Grant Full Disk Access, then quit and reopen VibeIsland.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if monitor.seenApps.isEmpty {
                        Text("Apps appear here once they send a notification.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(monitor.seenApps, id: \.self) { bundleID in
                            appMuteRow(bundleID)
                        }
                    }
                } header: {
                    Text("Per-app filter")
                } footer: {
                    Text("Turn an app off to hide its notifications from the feed and popups.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Notifications")
    }

    @ViewBuilder
    private func appMuteRow(_ bundleID: String) -> some View {
        Toggle(isOn: Binding(
            get: { !mutedNotificationApps.contains(bundleID) },
            set: { monitor.setMuted(!$0, bundleID: bundleID) }
        )) {
            HStack(spacing: 8) {
                Image(nsImage: NotificationAppCatalog.icon(for: bundleID))
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(NotificationAppCatalog.displayName(for: bundleID))
            }
        }
    }

    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
