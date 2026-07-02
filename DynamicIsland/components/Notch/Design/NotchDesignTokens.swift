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

/// Shared visual tokens for every notch surface (Home, Media, Agents, Timer,
/// Weather, Shelf, Calendar). Unlike `Geist` (Settings, light/dark-adaptive),
/// this palette is **always dark** — the notch never follows system
/// appearance. Card grammar, mono-label rule, and accent come from the
/// `design_handoff_notch_ui_redesign/` mockup.
enum NotchDesign {
    // MARK: - Colors (fixed dark ramp, never adapts to system appearance)

    enum Colors {
        static let panel = Color(nsColor: NSColor(geistHex: "#000000"))
        static let cardFill = Color(nsColor: NSColor(geistHex: "#141414"))
        static let cardFillAlt = Color(nsColor: NSColor(geistHex: "#151515"))
        static let cardFillRaised = Color(nsColor: NSColor(geistHex: "#1e1e1e"))

        static let hairline = Color.white.opacity(0.07)
        static let hairlineStrong = Color.white.opacity(0.09)

        /// The app's user-configurable accent (Settings > Appearance), not a
        /// hardcoded hex — the handoff's own accent is explicitly "tweakable".
        static var accent: Color { Color.effectiveAccent }

        static let success = Color(nsColor: NSColor(geistHex: "#3FB27F"))
        static let warning = Color(nsColor: NSColor(geistHex: "#E0A83E"))
        static let danger = Color(nsColor: NSColor(geistHex: "#E5645F"))
        static let info = Color(nsColor: NSColor(geistHex: "#6EA8F5"))

        static let textPrimary = Color(nsColor: NSColor(geistHex: "#EDEDED"))
        static let textSecondary = Color(nsColor: NSColor(geistHex: "#9A9A9A"))
        static let textTertiary = Color(nsColor: NSColor(geistHex: "#6E6E6E"))
    }

    // MARK: - Typography (Geist for voice, Geist Mono for every numeric/technical value)

    enum Typography {
        static func voice(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .custom(voicePostScriptName(for: weight), size: size)
        }

        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .custom(monoPostScriptName(for: weight), size: size)
        }

        /// Mono, uppercase, letter-spaced card eyebrow label — the repeated
        /// signature every card in the system opens with.
        static let eyebrow = mono(10, weight: .medium)

        static let titleLg = voice(20, weight: .semibold)
        static let title = voice(15, weight: .semibold)
        static let body = voice(13, weight: .regular)
        static let bodyStrong = voice(13, weight: .medium)
        static let caption = voice(11, weight: .regular)

        private static func voicePostScriptName(for weight: Font.Weight) -> String {
            switch weight {
            case .bold, .heavy, .black: return "Geist-Bold"
            case .semibold: return "Geist-SemiBold"
            case .medium: return "Geist-Medium"
            default: return "Geist-Regular"
            }
        }

        private static func monoPostScriptName(for weight: Font.Weight) -> String {
            switch weight {
            case .bold, .heavy, .black: return "GeistMono-Bold"
            case .semibold: return "GeistMono-SemiBold"
            case .medium: return "GeistMono-Medium"
            default: return "GeistMono-Regular"
            }
        }
    }

    // MARK: - Spacing / Radius

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
    }

    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 12
        static let lg: CGFloat = 14
        static let xl: CGFloat = 16
        static let pill: CGFloat = 100
    }

    static let hairlineWidth: CGFloat = 1
    /// Letter-spacing for mono eyebrow labels (~0.12–0.16em per the handoff).
    static let eyebrowTracking: CGFloat = 1.2
}
