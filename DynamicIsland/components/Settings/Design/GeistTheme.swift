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
import SwiftUI

/// A SwiftUI reinterpretation of Vercel's Geist design language (see DESIGN.md
/// at the repo root), using the system SF Pro font and colours that follow the
/// system light/dark appearance. Scoped to the Settings window.
enum Geist {
    // MARK: - Colors (light / dark hex pairs)

    enum Colors {
        /// Page background.
        static let canvas = dynamic(light: "#ffffff", dark: "#0a0a0a")
        /// Slightly recessed surface (cards, grouped rows).
        static let canvasSoft = dynamic(light: "#fafafa", dark: "#161616")
        static let canvasSoft2 = dynamic(light: "#f5f5f5", dark: "#1c1c1c")
        /// Primary text.
        static let ink = dynamic(light: "#171717", dark: "#ededed")
        /// Body / secondary text.
        static let body = dynamic(light: "#4d4d4d", dark: "#a1a1a1")
        /// Muted / tertiary text.
        static let mute = dynamic(light: "#888888", dark: "#707070")
        /// Hairline borders / dividers.
        static let hairline = dynamic(light: "#ebebeb", dark: "#2a2a2a")
        static let hairlineStrong = dynamic(light: "#d4d4d4", dark: "#3d3d3d")
        /// Accent / links / primary action.
        static let accent = dynamic(light: "#0070f3", dark: "#3291ff")
        static let success = dynamic(light: "#0070f3", dark: "#3291ff")
        static let warning = dynamic(light: "#f5a623", dark: "#f5a623")
        static let error = dynamic(light: "#ee0000", dark: "#ff5c5c")
        /// Selected sidebar row fill.
        static let selectionFill = dynamic(light: "#f0f0f0", dark: "#1f1f1f")

        static func dynamic(light: String, dark: String) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor(geistHex: isDark ? dark : light)
            })
        }
    }

    // MARK: - Typography (SF Pro at the Geist scale)

    enum Typography {
        static let displayMd = Font.system(size: 24, weight: .semibold)
        static let titleLg = Font.system(size: 20, weight: .semibold)
        static let title = Font.system(size: 17, weight: .semibold)
        static let bodyLg = Font.system(size: 16, weight: .regular)
        static let body = Font.system(size: 13, weight: .regular)
        static let bodyStrong = Font.system(size: 13, weight: .medium)
        static let caption = Font.system(size: 11, weight: .regular)
        static let captionStrong = Font.system(size: 11, weight: .medium)
        static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    }

    // MARK: - Spacing (8pt scale)

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 40
    }

    // MARK: - Radii

    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let pill: CGFloat = 100
    }

    static let hairlineWidth: CGFloat = 1
}

extension NSColor {
    /// Initialise from a `#rrggbb` / `#rrggbbaa` hex string.
    convenience init(geistHex hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: string).scanHexInt64(&value)
        let r, g, b, a: CGFloat
        switch string.count {
        case 8:
            r = CGFloat((value >> 24) & 0xff) / 255
            g = CGFloat((value >> 16) & 0xff) / 255
            b = CGFloat((value >> 8) & 0xff) / 255
            a = CGFloat(value & 0xff) / 255
        default:
            r = CGFloat((value >> 16) & 0xff) / 255
            g = CGFloat((value >> 8) & 0xff) / 255
            b = CGFloat(value & 0xff) / 255
            a = 1
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
