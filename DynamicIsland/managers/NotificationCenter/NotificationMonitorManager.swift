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

    /// Rolling feed, newest first, capped at `maxStored`. Excludes muted apps.
    @Published private(set) var notifications: [IslandNotification] = []
    /// Whether the database is currently readable (proxy for Full Disk Access).
    @Published private(set) var hasFullDiskAccess: Bool = NotificationCenterReader.hasAccess
    /// The most recent newly delivered notification, for the live-activity popup.
    @Published private(set) var latestDelivery: IslandNotification?
    /// Every bundle id seen this session (including muted), for the per-app filter UI.
    @Published private(set) var seenApps: [String] = []

    private let reader = NotificationCenterReader()
    private let logger = os.Logger(subsystem: "com.zaaacqwq.VibeIsland", category: "Notifications")

    private var watcher: NotificationDatabaseWatcher?
    private var safetyTimer: Timer?
    private var lastSeenRecordID: Int64 = 0
    private var isRunning = false
    private let maxStored = 200
    /// Coarse backstop in case FSEvents misses a write; real-time updates come
    /// from the file watcher.
    private let safetyPollInterval: TimeInterval = 15.0
    private var soundPlayer: NSSound?

    private init() {}

    var isEnabled: Bool { Defaults[.enableNotificationMonitoring] }

    // MARK: - Lifecycle

    func startIfNeeded() {
        guard isEnabled, !isRunning else { return }
        isRunning = true

        // Establish a baseline from existing history without replaying it as
        // popups: load the recent feed, then mark everything seen.
        loadInitialFeed()
        startWatching()
    }

    func stop() {
        isRunning = false
        watcher?.stop()
        watcher = nil
        safetyTimer?.invalidate()
        safetyTimer = nil
    }

    /// Clear the in-app feed. Does not affect the system Notification Center.
    func clearFeed() {
        notifications = []
    }

    // MARK: - Per-app filtering

    func isMuted(_ bundleID: String) -> Bool {
        Defaults[.mutedNotificationApps].contains(bundleID)
    }

    /// Mute or unmute an app. Unmuted apps reappear on their next notification;
    /// muting also drops the app's existing entries from the current feed.
    func setMuted(_ muted: Bool, bundleID: String) {
        if muted {
            Defaults[.mutedNotificationApps].insert(bundleID)
            notifications.removeAll { $0.bundleID == bundleID }
        } else {
            Defaults[.mutedNotificationApps].remove(bundleID)
        }
    }

    private func recordSeenApps(_ records: [IslandNotification]) {
        var changed = false
        for record in records where !seenApps.contains(record.bundleID) {
            seenApps.append(record.bundleID)
            changed = true
        }
        if changed {
            seenApps.sort { NotificationAppCatalog.displayName(for: $0) < NotificationAppCatalog.displayName(for: $1) }
        }
    }

    // MARK: - Initial load

    private func loadInitialFeed() {
        do {
            let baseline = try reader.latestRecordID()
            // Pull the tail of history for the tab (rec_id > baseline - window).
            let window: Int64 = 50
            let history = try reader.fetchRecords(sinceRecordID: max(0, baseline - window), limit: 50)
            recordSeenApps(history)
            notifications = history.reversed().filter { !isMuted($0.bundleID) }  // newest first
            lastSeenRecordID = baseline
            hasFullDiskAccess = true
            logger.info("Loaded \(history.count) notifications, baseline rec_id=\(baseline)")
        } catch {
            handle(error)
        }
    }

    // MARK: - Watching

    private func startWatching() {
        // Real-time: FSEvents on the database directory.
        if let directory = NotificationCenterReader.databaseURL?.deletingLastPathComponent() {
            let watcher = NotificationDatabaseWatcher { [weak self] in
                Task { @MainActor in self?.poll() }
            }
            watcher.start(directory: directory)
            self.watcher = watcher
        }

        // Backstop poll in case an event is missed.
        safetyTimer?.invalidate()
        let timer = Timer(timeInterval: safetyPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        safetyTimer = timer
    }

    private func poll() {
        guard isRunning, isEnabled else { return }
        do {
            let allFresh = try reader.fetchRecords(sinceRecordID: lastSeenRecordID)
            hasFullDiskAccess = true
            guard !allFresh.isEmpty else { return }

            lastSeenRecordID = max(lastSeenRecordID, allFresh.map(\.recordID).max() ?? lastSeenRecordID)
            recordSeenApps(allFresh)

            let fresh = allFresh.filter { !isMuted($0.bundleID) }
            guard !fresh.isEmpty else { return }

            // Prepend newest-first, dedupe by record id, cap.
            let merged = (fresh.reversed() + notifications)
            var seen = Set<Int64>()
            notifications = merged.filter { seen.insert($0.recordID).inserted }.prefix(maxStored).map { $0 }

            // Surface the newest delivery for the popup.
            if let newest = fresh.last {
                latestDelivery = newest
                logger.info("New notification from \(newest.bundleID, privacy: .public)")
                playSoundIfEnabled()
                presentPopup(for: newest)
            }
        } catch {
            handle(error)
        }
    }

    // MARK: - Sound

    private func playSoundIfEnabled() {
        guard Defaults[.notificationSoundEnabled] else { return }
        if soundPlayer == nil {
            soundPlayer = NSSound(named: "Tink")
        }
        soundPlayer?.stop()
        soundPlayer?.play()
    }

    // MARK: - Popup

    /// Posted (throttled) when a new notification arrives, so the app can expand
    /// the notch to the notifications tab — same UX as agent-completion.
    static let didArrive = Notification.Name("vibeIslandNotificationDidArrive")

    private static let popupThrottle: TimeInterval = 5
    private var lastPopupAt: Date = .distantPast

    /// Request the big expand-to-tab popup. Throttled so notification bursts
    /// don't repeatedly re-open the notch.
    private func presentPopup(for notification: IslandNotification) {
        guard Defaults[.showNotificationLiveActivity] else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPopupAt) > Self.popupThrottle else { return }
        lastPopupAt = now
        NotificationCenter.default.post(name: Self.didArrive, object: notification.recordID)
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
