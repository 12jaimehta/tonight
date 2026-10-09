import XCTest
@testable import DesignSystem

final class DesignSystemTests: XCTestCase {
    func testPaletteHasFourTokensFromTheHue() {
        let palette = SubjectPalette.from(hue: 35)
        XCTAssertEqual(palette.bg.hue, 35)
        XCTAssertEqual(palette.fg.hue, 35)
        XCTAssertEqual(palette.accent.hue, 35)
        XCTAssertEqual(palette.soft.hue, 35)
        XCTAssertEqual(palette.bg.lightness, PalettePlaceholders.backgroundLightness)
        XCTAssertEqual(palette.bg.chroma, PalettePlaceholders.backgroundChroma)
        XCTAssertEqual(palette.fg.lightness, PalettePlaceholders.foregroundLightness)
        XCTAssertEqual(palette.accent.chroma, PalettePlaceholders.accentChroma)
        XCTAssertEqual(palette.soft.lightness, PalettePlaceholders.softLightness)
    }

    func testDifferentHuesStayApart() {
        let hindi = SubjectPalette.from(hue: 35)
        let maths = SubjectPalette.from(hue: 255)
        XCTAssertNotEqual(hindi.accent.hue, maths.accent.hue)
        XCTAssertEqual(hindi.accent.lightness, maths.accent.lightness)
    }

    func testHueWrapsIntoACircle() {
        XCTAssertEqual(SubjectPalette.normalizedHue(360), 0)
        XCTAssertEqual(SubjectPalette.normalizedHue(-20), 340)
        XCTAssertEqual(SubjectPalette.from(hue: 400).bg.hue, 40)
    }

    func testMotionIsOff() {
        XCTAssertFalse(TonightMotion.animationsInV1)
    }

    func testStaticChipKeepsThePaletteItWasGiven() {
        let palette = SubjectPalette.from(hue: 145)
        let chip = StaticSubjectChip(title: "EVS", palette: palette)
        XCTAssertEqual(chip.title, "EVS")
        XCTAssertEqual(chip.palette.accent.hue, 145)
        let block = StaticCopyBlock(title: "Tonight", lines: ["Classes 1–3", "Ages 6–8"])
        XCTAssertEqual(block.lines.count, 2)
    }

    func testConvertedColorStaysInsideSRGB() {
        let color = OKLCH(lightness: 0.62, chroma: 0.14, hue: 35)
        let parts = OKLCHColor.srgb(color)
        XCTAssertTrue((0...1).contains(parts.0))
        XCTAssertTrue((0...1).contains(parts.1))
        XCTAssertTrue((0...1).contains(parts.2))
        XCTAssertTrue(color.css.hasPrefix("oklch("))
    }
}
