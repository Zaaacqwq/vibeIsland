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

import Combine
import Defaults
import Foundation
import os

/// Mirrors the macOS Notification Center into VibeIsland: maintains a rolling
/// feed for the notifications tab and surfaces freshly delivered notifications
/// for the closed-pill popup.
///
/// Opt-in (`enableNotificationMonitoring`, default off) and requires Full Disk
/// Access. Everything fails open: if access is missing or a read errors, the
/// feed stays empty and `hasFullDiskAccess` flips to drive the onboarding UI.
@MainActor
final class NotificationMonitorManager: ObservableObject {
    static let shared = NotificationMonitorManager()

    /// Rolling feed, newest first, capped at `maxStored`.
    @Published private(set) var notifications: [IslandNotification] = []
    /// Whether the database is currently readable (proxy for Full Disk Access).
    @Published private(set) var hasFullDiskAccess: Bool = NotificationCenterReader.hasAccess
    /// The most recent newly delivered notification, for the live-activity popup.
    @Published private(set) var latestDelivery: IslandNotification?

    private let reader = NotificationCenterReader()
    private let logger = os.Logger(subsystem: "com.zaaacqwq.VibeIsland", category: "Notifications")

    private var pollTimer: Timer?
    private var lastSeenRecordID: Int64 = 0
    private var isRunning = false
    private let maxStored = 200
    private let pollInterval: TimeInterval = 2.0

    private init() {}

    var isEnabled: Bool { Defaults[.enableNotificationMonitoring] }

    // MARK: - Lifecycle

    func startIfNeeded() {
        guard isEnabled, !isRunning else { return }
        isRunning = true

        // Establish a baseline from existing history without replaying it as
        // popups: load the recent feed, then mark everything seen.
        loadInitialFeed()
        startPolling()
    }

    func stop() {
        isRunning = false
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Clear the in-app feed. Does not affect the system Notification Center.
    func clearFeed() {
        notifications = []
    }

    // MARK: - Initial load

    private func loadInitialFeed() {
        do {
            let baseline = try reader.latestRecordID()
            // Pull the tail of history for the tab (rec_id > baseline - window).
            let window: Int64 = 50
            let history = try reader.fetchRecords(sinceRecordID: max(0, baseline - window), limit: 50)
            notifications = history.reversed()  // newest first
            lastSeenRecordID = baseline
            hasFullDiskAccess = true
            logger.info("Loaded \(history.count) notifications, baseline rec_id=\(baseline)")
        } catch {
            handle(error)
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func poll() {
        guard isRunning, isEnabled else { return }
        do {
            let fresh = try reader.fetchRecords(sinceRecordID: lastSeenRecordID)
            hasFullDiskAccess = true
            guard !fresh.isEmpty else { return }

            lastSeenRecordID = max(lastSeenRecordID, fresh.map(\.recordID).max() ?? lastSeenRecordID)

            // Prepend newest-first, dedupe by record id, cap.
            let merged = (fresh.reversed() + notifications)
            var seen = Set<Int64>()
            notifications = merged.filter { seen.insert($0.recordID).inserted }.prefix(maxStored).map { $0 }

            // Surface the newest delivery for the popup.
            if let newest = fresh.last {
                latestDelivery = newest
                logger.info("New notification from \(newest.bundleID, privacy: .public)")
                presentPopup(for: newest)
            }
        } catch {
            handle(error)
        }
    }

    // MARK: - Popup

    private let popupDuration: TimeInterval = 4

    /// Pop the closed-pill notification toast via the shared sneak-peek machinery,
    /// which handles notch widening + auto-hide. No-op while the notch is open.
    private func presentPopup(for notification: IslandNotification) {
        guard Defaults[.showNotificationLiveActivity] else { return }
        let coordinator = DynamicIslandViewCoordinator.shared

        let appName = NotificationAppCatalog.displayName(for: notification.bundleID)
        coordinator.toggleSneakPeek(
            status: true,
            type: .notification,
            duration: popupDuration,
            title: notification.title.isEmpty ? appName : notification.title,
            subtitle: notification.preview
        )
    }

    // MARK: - Errors

    private func handle(_ error: Error) {
        if case NotificationCenterReader.ReadError.accessDenied = error {
            hasFullDiskAccess = false
            logger.error("Notification DB access denied — Full Disk Access required")
        } else if case NotificationCenterReader.ReadError.databaseNotFound = error {
            hasFullDiskAccess = false
            logger.error("Notification DB not found at known locations")
        } else {
            logger.error("Notification read failed: \(error.localizedDescription)")
        }
    }
}
