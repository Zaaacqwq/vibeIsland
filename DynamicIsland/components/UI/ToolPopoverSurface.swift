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
import SwiftUI

/// Shared chrome for the utility tools' header popovers (color picker,
/// clipboard). Matches the surface `TimerPopover` establishes — dark HUD
/// material, 14pt continuous corner, hairline border — so a tool rendered in
/// popover mode is indistinguishable in style from the timer's.
struct ToolPopoverSurface: ViewModifier {
    var width: CGFloat = 300
    var padding: CGFloat = 16

    private static let cornerRadius: CGFloat = 14
    private static let surface = Color(nsColor: NSColor(geistHex: "#161618"))

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(width: width)
            .background(
                ZStack {
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    Self.surface.opacity(0.92)
                }
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
            )
    }
}

extension View {
    func toolPopoverSurface(width: CGFloat = 300, padding: CGFloat = 16) -> some View {
        modifier(ToolPopoverSurface(width: width, padding: padding))
    }
}

/// Tokens shared by the two utility tools' panels. Deliberately thin: the notch
/// ramp in ``NotchDesign`` is the source of truth, and this only names the few
/// derived values both tools repeat.
enum ToolPanelStyle {
    static let cardFill = Color.white.opacity(0.05)
    static let cardStroke = Color.white.opacity(0.06)
    static let chipFill = Color.white.opacity(0.06)
    static let chipStroke = Color.white.opacity(0.10)
    static let chipFillActive = Color.white.opacity(0.12)
    static let divider = Color.white.opacity(0.09)
    static let iconTile = Color.white.opacity(0.06)

    static let title = Color(nsColor: NSColor(geistHex: "#F2F2F2"))
    static let value = Color(nsColor: NSColor(geistHex: "#FAFAFA"))
    static let muted = Color(nsColor: NSColor(geistHex: "#8A8A8A"))
    static let faint = NotchDesign.Colors.textTertiary

    static let cardRadius: CGFloat = 10
    static let controlRadius: CGFloat = 8
}
