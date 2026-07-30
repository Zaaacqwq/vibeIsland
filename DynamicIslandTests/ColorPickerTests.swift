import AppKit
import XCTest
@testable import VibeIsland

/// Color conversion and formatting for the picker. Pure math, so it is cheap to
/// pin exactly — and easy to get subtly wrong by hand.
final class ColorPickerTests: XCTestCase {
    private let orange = PickedColor(red: 1, green: 0.5, blue: 0, alpha: 1)
    private let white = PickedColor(red: 1, green: 1, blue: 1)
    private let black = PickedColor(red: 0, green: 0, blue: 0)

    func testComponentsAreClampedToUnitRange() throws {
        let color = PickedColor(red: 1.4, green: -0.2, blue: 0.5, alpha: 3)

        XCTAssertEqual(color.red, 1)
        XCTAssertEqual(color.green, 0)
        XCTAssertEqual(color.blue, 0.5)
        XCTAssertEqual(color.alpha, 1)
    }

    func testHexFormatting() throws {
        XCTAssertEqual(ColorFormat.hex.string(for: orange), "#ff8000")
        XCTAssertEqual(ColorFormat.hex.string(for: orange, uppercaseHex: true), "#FF8000")
        XCTAssertEqual(ColorFormat.hex.string(for: black), "#000000")
        XCTAssertEqual(ColorFormat.hex.string(for: white), "#ffffff")
    }

    func testHexWithAlphaAppendsTheAlphaByte() throws {
        let translucent = PickedColor(red: 1, green: 0.5, blue: 0, alpha: 0.5)

        XCTAssertEqual(ColorFormat.hexAlpha.string(for: translucent), "#ff800080")
    }

    func testRgbAndRgbaFormatting() throws {
        XCTAssertEqual(ColorFormat.rgb.string(for: orange), "rgb(255, 128, 0)")
        XCTAssertEqual(ColorFormat.rgba.string(for: orange), "rgba(255, 128, 0, 1.000)")
    }

    func testHslFormatting() throws {
        XCTAssertEqual(ColorFormat.hsl.string(for: orange), "hsl(30, 100%, 50%)")
        XCTAssertEqual(ColorFormat.hsl.string(for: white), "hsl(0, 0%, 100%)")
    }

    func testHsbFormatting() throws {
        XCTAssertEqual(ColorFormat.hsb.string(for: orange), "hsb(30, 100%, 100%)")
    }

    func testCodeSnippetFormatting() throws {
        XCTAssertEqual(
            ColorFormat.swiftUI.string(for: orange),
            "Color(red: 1.000, green: 0.500, blue: 0.000)"
        )
        XCTAssertEqual(
            ColorFormat.appKit.string(for: orange),
            "NSColor(srgbRed: 1.000, green: 0.500, blue: 0.000, alpha: 1.000)"
        )
    }

    func testHueIsComputedForEachDominantChannel() throws {
        XCTAssertEqual(PickedColor(red: 1, green: 0, blue: 0).hsl.h, 0, accuracy: 0.001)
        XCTAssertEqual(PickedColor(red: 0, green: 1, blue: 0).hsl.h, 120, accuracy: 0.001)
        XCTAssertEqual(PickedColor(red: 0, green: 0, blue: 1).hsl.h, 240, accuracy: 0.001)
        // Magenta exercises the negative-hue wrap in the red branch.
        XCTAssertEqual(PickedColor(red: 1, green: 0, blue: 1).hsl.h, 300, accuracy: 0.001)
    }

    func testForegroundPreferenceFollowsLuminance() throws {
        XCTAssertTrue(white.prefersDarkForeground, "Dark text on a light swatch")
        XCTAssertFalse(black.prefersDarkForeground)
    }

    func testSameComponentsIgnoresTimestampAndIdentity() throws {
        let first = PickedColor(red: 0.2, green: 0.4, blue: 0.6, pickedAt: .distantPast)
        let second = PickedColor(red: 0.2, green: 0.4, blue: 0.6, pickedAt: .now)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertTrue(first.hasSameComponents(as: second))
        XCTAssertFalse(first.hasSameComponents(as: PickedColor(red: 0.2, green: 0.4, blue: 0.7)))
    }

    func testConversionFromNSColorNormalizesToSRGB() throws {
        let color = PickedColor(nsColor: NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1))

        XCTAssertEqual(ColorFormat.hex.string(for: color), "#ff8000")
    }
}
