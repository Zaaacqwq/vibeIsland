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

/// Open-notch tab acting as a mini Notification Center: lists notifications
/// mirrored from the macOS database, newest first. Clicking a row opens the
/// originating app. Falls back to a Full Disk Access onboarding state.
struct NotchNotificationCenterView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var monitor = NotificationMonitorManager.shared

    // Suppress the notch's scroll-to-close gesture while hovering the list.
    @State private var scrollSuppressionToken = UUID()
    @State private var isSuppressingScroll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onHover { updateScrollSuppression(for: $0) }
        .onDisappear { updateScrollSuppression(for: false) }
    }

    private func updateScrollSuppression(for hovering: Bool) {
        guard hovering != isSuppressingScroll else { return }
        isSuppressingScroll = hovering
        vm.setScrollGestureSuppression(hovering, token: scrollSuppressionToken)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "bell.fill")
                .foregroundStyle(.secondary)
            Text("Notifications")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            if !monitor.notifications.isEmpty {
                Button {
                    monitor.clearFeed()
                } label: {
                    Text("Clear")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !monitor.hasFullDiskAccess {
            fullDiskAccessPrompt
        } else if monitor.notifications.isEmpty {
            emptyState(icon: "bell.slash", text: "No notifications")
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(monitor.notifications) { notification in
                        NotificationRow(notification: notification, hideContent: Defaults[.hideNotificationContent])
                            .onTapGesture { open(notification) }
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fullDiskAccessPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
            Text("Full Disk Access required")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            Text("VibeIsland needs Full Disk Access to read notifications.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func open(_ notification: IslandNotification) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: notification.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// A single notification row: app icon, app name + relative time, title, body.
private struct NotificationRow: View {
    let notification: IslandNotification
    let hideContent: Bool

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(nsImage: NotificationAppCatalog.icon(for: notification.bundleID))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(NotificationAppCatalog.displayName(for: notification.bundleID))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Self.relativeFormatter.localizedString(for: notification.date, relativeTo: Date()))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize()
                }
                if !notification.title.isEmpty {
                    Text(notification.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                let preview = notification.preview
                if !preview.isEmpty && !hideContent {
                    Text(preview)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
        )
        .contentShape(Rectangle())
    }
}
