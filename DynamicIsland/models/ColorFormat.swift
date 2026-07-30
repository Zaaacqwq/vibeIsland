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

import Defaults
import Foundation

/// Textual representations the color picker can copy a swatch as.
enum ColorFormat: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case hex
    case hexAlpha
    case rgb
    case rgba
    case hsl
    case hsb
    case swiftUI
    case appKit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hex: return "HEX"
        case .hexAlpha: return "HEX+A"
        case .rgb: return "RGB"
        case .rgba: return "RGBA"
        case .hsl: return "HSL"
        case .hsb: return "HSB"
        case .swiftUI: return "SwiftUI"
        case .appKit: return "NSColor"
        }
    }

    /// The formats offered as one-tap chips in the compact notch UI. The code
    /// snippets stay available in the format menu but would crowd the strip.
    static let quickFormats: [ColorFormat] = [.hex, .rgb, .hsl]

    func string(for color: PickedColor, uppercaseHex: Bool = false) -> String {
        let (r, g, b) = color.byteComponents

        switch self {
        case .hex:
            return hexString(r, g, b, uppercase: uppercaseHex)
        case .hexAlpha:
            return hexString(r, g, b, color.alphaByte, uppercase: uppercaseHex)
        case .rgb:
            return "rgb(\(r), \(g), \(b))"
        case .rgba:
            return "rgba(\(r), \(g), \(b), \(decimal(color.alpha)))"
        case .hsl:
            let (h, s, l) = color.hsl
            return "hsl(\(Int(h.rounded())), \(percent(s)), \(percent(l)))"
        case .hsb:
            let (h, s, brightness) = color.hsb
            return "hsb(\(Int(h.rounded())), \(percent(s)), \(percent(brightness)))"
        case .swiftUI:
            return "Color(red: \(decimal(color.red)), green: \(decimal(color.green)), blue: \(decimal(color.blue)))"
        case .appKit:
            return "NSColor(srgbRed: \(decimal(color.red)), green: \(decimal(color.green)), blue: \(decimal(color.blue)), alpha: \(decimal(color.alpha)))"
        }
    }

    private func hexString(_ components: Int..., uppercase: Bool) -> String {
        let digits = components
            .map { String(format: "%02x", min(max($0, 0), 255)) }
            .joined()
        return "#" + (uppercase ? digits.uppercased() : digits)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
