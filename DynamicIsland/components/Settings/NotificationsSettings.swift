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

/// Settings pane for the Notification Center mirror: master switch, popup +
/// privacy options, Full Disk Access status, and per-app muting.
struct NotificationsSettings: View {
    @ObservedObject var monitor = NotificationMonitorManager.shared
    @Default(.enableNotificationMonitoring) var enableNotificationMonitoring
    @Default(.mutedNotificationApps) var mutedNotificationApps

    var body: some View {
        GeistSettingsPage(title: "Notifications", subtitle: "Mirror the macOS Notification Center into the notch. Requires Full Disk Access.") {
            GeistSection {
                GeistToggleRow(
                    title: "Enable notification mirroring",
                    description: "Show macOS notifications (WeChat, Discord, system, …) in the notch.",
                    isOn: $enableNotificationMonitoring,
                    divider: enableNotificationMonitoring
                )
                if enableNotificationMonitoring {
                    GeistToggleRow(title: "Pop up the notch on new notifications", isOn: defaultsBinding(.showNotificationLiveActivity))
                    GeistToggleRow(title: "Play a sound on new notifications", isOn: defaultsBinding(.notificationSoundEnabled))
                    GeistToggleRow(
                        title: "Hide message content",
                        description: "Show only the app and title, never the body.",
                        isOn: defaultsBinding(.hideNotificationContent),
                        divider: false
                    )
                }
            }

            if enableNotificationMonitoring {
                GeistSection(
                    title: "Permissions",
                    footer: "VibeIsland reads ~/Library/Group Containers/group.com.apple.usernoted. Grant Full Disk Access, then quit and reopen VibeIsland."
                ) {
                    GeistLabeledRow(title: "Full Disk Access", divider: !monitor.hasFullDiskAccess) {
                        if monitor.hasFullDiskAccess {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .font(Geist.Typography.body).foregroundStyle(Geist.Colors.success).labelStyle(.titleAndIcon)
                        } else {
                            Label("Not granted", systemImage: "xmark.circle")
                                .font(Geist.Typography.body).foregroundStyle(Geist.Colors.warning).labelStyle(.titleAndIcon)
                        }
                    }
                    if !monitor.hasFullDiskAccess {
                        GeistRow(divider: false) {
                            Button("Open System Settings…") { openFullDiskAccessSettings() }
                                .buttonStyle(.geist)
                        }
                    }
                }

                GeistSection(
                    title: "Per-app filter",
                    footer: "Turn an app off to hide its notifications from the feed and popups."
                ) {
                    if monitor.seenApps.isEmpty {
                        GeistRow(divider: false) {
                            Text("Apps appear here once they send a notification.")
                                .font(Geist.Typography.caption).foregroundStyle(Geist.Colors.mute)
                        }
                    } else {
                        ForEach(Array(monitor.seenApps.enumerated()), id: \.element) { index, bundleID in
                            appMuteRow(bundleID, divider: index < monitor.seenApps.count - 1)
                        }
                    }
                }
            }
        }
    }

    private func defaultsBinding(_ key: Defaults.Key<Bool>) -> Binding<Bool> {
        Binding(get: { Defaults[key] }, set: { Defaults[key] = $0 })
    }

    @ViewBuilder
    private func appMuteRow(_ bundleID: String, divider: Bool) -> some View {
        GeistRow(divider: divider) {
            HStack(spacing: Geist.Spacing.sm) {
                Image(nsImage: NotificationAppCatalog.icon(for: bundleID))
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(NotificationAppCatalog.displayName(for: bundleID))
                    .font(Geist.Typography.bodyStrong)
                    .foregroundStyle(Geist.Colors.ink)
                Spacer(minLength: Geist.Spacing.sm)
                Toggle("", isOn: Binding(
                    get: { !mutedNotificationApps.contains(bundleID) },
                    set: { monitor.setMuted(!$0, bundleID: bundleID) }
                ))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
        }
    }

    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
