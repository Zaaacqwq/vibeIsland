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

/// One entry in the clipboard history list.
struct ClipboardRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onActivate: (ClipboardActivation) -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @Default(.clipboardShowSourceApp) private var showSourceApp
    @State private var isHovering = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        Button {
            onActivate(ClipboardActivation.current())
        } label: {
            HStack(spacing: 10) {
                leadingVisual

                VStack(alignment: .leading, spacing: 2) {
                    title
                    metaLine
                }

                Spacer(minLength: 4)

                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(NotchDesign.Colors.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(background)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(item.title.isEmpty ? String(localized: "Image") : item.title)
        .contextMenu {
            Button(String(localized: "Copy")) { onActivate(.copy) }
            if item.kind == .text {
                Button(String(localized: "Copy without formatting")) { onActivate(.copyUnformatted) }
            }
            Button(String(localized: "Paste")) { onActivate(.paste) }
            Divider()
            Button(item.isPinned ? String(localized: "Unpin") : String(localized: "Pin")) { onTogglePin() }
            Button(String(localized: "Delete"), role: .destructive) { onDelete() }
        }
    }

    private var background: Color {
        if isSelected { return Color.white.opacity(0.12) }
        if isHovering { return Color.white.opacity(0.07) }
        return .clear
    }

    // MARK: - Leading visual

    @ViewBuilder
    private var leadingVisual: some View {
        switch item.kind {
        case .image:
            ClipboardImageThumbnail(item: item, size: 26)
        case .file:
            fileIcon
        case .text:
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ToolPanelStyle.iconTile)
                Image(systemName: "text.alignleft")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ToolPanelStyle.muted)
            }
            .frame(width: 26, height: 26)
        }
    }

    @ViewBuilder
    private var fileIcon: some View {
        if let url = item.fileURLs.first {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 26, height: 26)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ToolPanelStyle.iconTile)
                Image(systemName: "doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ToolPanelStyle.muted)
            }
            .frame(width: 26, height: 26)
        }
    }

    // MARK: - Text

    private var title: some View {
        Text(displayTitle)
            .font(NotchDesign.Typography.voice(12, weight: .regular))
            .foregroundStyle(NotchDesign.Colors.textPrimary)
            .lineLimit(item.kind == .text ? 2 : 1)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
    }

    private var displayTitle: String {
        if !item.title.isEmpty { return item.title }
        switch item.kind {
        case .image: return String(localized: "Image")
        case .file: return String(localized: "File")
        case .text: return ""
        }
    }

    private var metaLine: some View {
        HStack(spacing: 5) {
            if showSourceApp, let source = item.sourceAppBundleID, let icon = Self.appIcon(for: source) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 10, height: 10)
            }
            Text(Self.relativeFormatter.localizedString(for: item.lastCopiedAt, relativeTo: .now))
                .font(NotchDesign.Typography.mono(9, weight: .medium))
                .foregroundStyle(ToolPanelStyle.faint)
            if item.numberOfCopies > 1 {
                Text("×\(item.numberOfCopies)")
                    .font(NotchDesign.Typography.mono(9, weight: .medium))
                    .foregroundStyle(ToolPanelStyle.faint)
            }
        }
    }

    /// App icons are looked up by bundle id on every row, so the results are
    /// cached — `urlForApplication` hits the Launch Services database.
    private static var iconCache: [String: NSImage?] = [:]

    static func appIcon(for bundleID: String) -> NSImage? {
        if let cached = iconCache[bundleID] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        iconCache[bundleID] = icon
        return icon
    }
}

/// Thumbnail for an image entry, loaded from the store off the main actor.
struct ClipboardImageThumbnail: View {
    let item: ClipboardItem
    let size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(ToolPanelStyle.iconTile)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ToolPanelStyle.muted)
            }
        }
        .frame(width: size, height: size)
        .task(id: item.id) {
            await load()
        }
    }

    private func load() async {
        let imageTypes = [
            NSPasteboard.PasteboardType.png.rawValue,
            NSPasteboard.PasteboardType.tiff.rawValue
        ]
        guard let payload = imageTypes.compactMap({ item.payload(ofType: $0) }).first else { return }
        guard let data = await ClipboardStore.shared.data(for: payload) else { return }
        image = NSImage(data: data)
    }
}

/// What a click or key press on an entry should do. Mirrors the modifier
/// vocabulary Maccy established, so muscle memory carries over.
enum ClipboardActivation {
    /// Copy to the pasteboard (and auto-paste if the user enabled that).
    case `default`
    /// Copy only, never paste.
    case copy
    /// Copy the plain-text representation only, then paste.
    case copyUnformatted
    /// Copy and paste regardless of the auto-paste setting.
    case paste

    /// Resolves the intent from the modifier keys held right now: ⌥ pastes,
    /// ⌥⇧ pastes without formatting.
    static func current() -> ClipboardActivation {
        let flags = NSEvent.modifierFlags
        guard flags.contains(.option) else { return .default }
        return flags.contains(.shift) ? .copyUnformatted : .paste
    }

    var removesFormatting: Bool { self == .copyUnformatted }

    var forcesPaste: Bool {
        switch self {
        case .paste, .copyUnformatted: return true
        case .default, .copy: return false
        }
    }

    var pastesNever: Bool { self == .copy }
}
