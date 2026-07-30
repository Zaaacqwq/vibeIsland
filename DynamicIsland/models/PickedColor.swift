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

/// One color sampled with the eyedropper, stored in the picker's history.
///
/// Components are always **sRGB** in `0...1`: `NSColorSampler` hands back a
/// color in the display's space, and persisting that as-is would make the same
/// swatch decode to different hex on a different monitor.
struct PickedColor: Codable, Hashable, Identifiable, Defaults.Serializable {
    let id: UUID
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
    var pickedAt: Date

    init(
        id: UUID = UUID(),
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double = 1,
        pickedAt: Date = .now
    ) {
        self.id = id
        self.red = red.clampedToUnit
        self.green = green.clampedToUnit
        self.blue = blue.clampedToUnit
        self.alpha = alpha.clampedToUnit
        self.pickedAt = pickedAt
    }

    /// Falls back to the raw component values when the color cannot be
    /// converted (monochrome or pattern colors have no RGB components, and
    /// asking for `.redComponent` on those throws an exception).
    init(nsColor: NSColor, pickedAt: Date = .now) {
        let converted = nsColor.usingColorSpace(.sRGB) ?? .black
        self.init(
            red: Double(converted.redComponent),
            green: Double(converted.greenComponent),
            blue: Double(converted.blueComponent),
            alpha: Double(converted.alphaComponent),
            pickedAt: pickedAt
        )
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var color: Color {
        Color(nsColor: nsColor)
    }

    /// Two picks of the same color are "the same swatch" regardless of when
    /// they happened — used to de-duplicate the history.
    func hasSameComponents(as other: PickedColor) -> Bool {
        byteComponents == other.byteComponents && alphaByte == other.alphaByte
    }

    // MARK: - Component conversions

    /// 8-bit RGB, the basis for every textual format.
    var byteComponents: (r: Int, g: Int, b: Int) {
        (red.toByte, green.toByte, blue.toByte)
    }

    var alphaByte: Int { alpha.toByte }

    /// Hue 0..<360, saturation/lightness 0...1.
    var hsl: (h: Double, s: Double, l: Double) {
        let maxC = max(red, green, blue)
        let minC = min(red, green, blue)
        let lightness = (maxC + minC) / 2
        let delta = maxC - minC

        guard delta > 0 else { return (0, 0, lightness) }

        let saturation = delta / (1 - abs(2 * lightness - 1))
        return (hueDegrees(maxC: maxC, delta: delta), min(saturation, 1), lightness)
    }

    /// Hue 0..<360, saturation/brightness 0...1.
    var hsb: (h: Double, s: Double, b: Double) {
        let maxC = max(red, green, blue)
        let minC = min(red, green, blue)
        let delta = maxC - minC

        guard delta > 0 else { return (0, 0, maxC) }
        return (hueDegrees(maxC: maxC, delta: delta), delta / maxC, maxC)
    }

    /// Relative luminance per WCAG 2.1, used to decide whether a swatch needs
    /// dark or light text drawn on top of it.
    var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    var prefersDarkForeground: Bool { relativeLuminance > 0.45 }

    private func hueDegrees(maxC: Double, delta: Double) -> Double {
        let hue: Double
        switch maxC {
        case red:
            hue = 60 * (((green - blue) / delta).truncatingRemainder(dividingBy: 6))
        case green:
            hue = 60 * (((blue - red) / delta) + 2)
        default:
            hue = 60 * (((red - green) / delta) + 4)
        }
        return hue < 0 ? hue + 360 : hue
    }
}

private extension Double {
    var clampedToUnit: Double { min(max(self, 0), 1) }
    var toByte: Int { Int((self * 255).rounded()) }
}
