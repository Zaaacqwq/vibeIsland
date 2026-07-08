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

/// Notification setup page: notification mirroring needs Full Disk Access,
/// which can only be granted in System Settings — this page links there and
/// reflects the live grant status.
struct NotificationFeatureView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onBack: () -> Void

    @ObservedObject private var manager = NotificationMonitorManager.shared

    var body: some View {
        OnboardingScaffold(
            symbol: OnboardingFeature.notification.symbol,
            gradient: OnboardingFeature.notification.gradient,
            title: String(localized: "Mirror your notifications"),
            subtitle: String(localized: "VibeIsland needs Full Disk Access to read macOS notifications. Nothing is ever sent off your Mac."),
            onBack: onBack,
            onSkip: onSkip,
            onContinue: applyAndContinue
        ) {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: manager.hasFullDiskAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(manager.hasFullDiskAccess ? Color.green : Color.orange)
                    Text(manager.hasFullDiskAccess
                        ? String(localized: "Full Disk Access granted")
                        : String(localized: "Full Disk Access not granted yet"))
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.gray.opacity(0.08))
                )

                if !manager.hasFullDiskAccess {
                    HStack(spacing: 10) {
                        Button(String(localized: "Open Full Disk Access")) { openFullDiskAccessSettings() }
                            .buttonStyle(.bordered)
                        Button(String(localized: "Recheck")) { manager.startIfNeeded() }
                            .buttonStyle(.bordered)
                    }
                    Text("After enabling VibeIsland in the list, come back and tap Recheck.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func applyAndContinue() {
        Defaults[.enableNotificationMonitoring] = true
        manager.startIfNeeded()
        onContinue()
    }
}
