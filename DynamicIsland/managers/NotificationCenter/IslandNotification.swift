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
import Foundation

/// A single notification mirrored from the macOS Notification Center database.
///
/// Sourced from `~/Library/Group Containers/group.com.apple.usernoted/db2/db`
/// (macOS 26+) — the `record` table's binary-plist `data` blob, joined with the
/// `app` table for the originating bundle identifier.
struct IslandNotification: Identifiable, Equatable, Sendable {
    /// The Notification Center `record.rec_id` — stable and monotonically increasing.
    let recordID: Int64
    let bundleID: String
    let title: String
    let subtitle: String
    let body: String
    let date: Date

    var id: Int64 { recordID }

    /// Best-effort single-line preview combining subtitle + body.
    var preview: String {
        [subtitle, body]
            .filter { !$0.isEmpty }
            .joined(separator: " — ")
    }
}

/// Resolves and caches per-bundle display names and icons. App-bundle lookups
/// hit the filesystem, so results are memoised for the lifetime of the process.
@MainActor
enum NotificationAppCatalog {
    private static var nameCache: [String: String] = [:]
    private static var iconCache: [String: NSImage] = [:]

    static func displayName(for bundleID: String) -> String {
        if let cached = nameCache[bundleID] { return cached }
        let resolved = resolveURL(for: bundleID).map { url in
            FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        } ?? bundleID
        nameCache[bundleID] = resolved
        return resolved
    }

    static func icon(for bundleID: String) -> NSImage {
        if let cached = iconCache[bundleID] { return cached }
        let image: NSImage
        if let url = resolveURL(for: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        iconCache[bundleID] = image
        return image
    }

    private static func resolveURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}
