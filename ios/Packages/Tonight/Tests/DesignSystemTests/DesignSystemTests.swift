import XCTest
@testable import DesignSystem

final class DesignSystemTests: XCTestCase {
    func testPaletteHasFourTokensFromTheHue() {
        let palette = SubjectPalette.from(hue: 30)
        XCTAssertEqual(palette.bg.hue, 30)
        XCTAssertEqual(palette.edge.hue, 30)
        XCTAssertEqual(palette.fg.hue, 30)
        XCTAssertEqual(palette.accent.hue, 30)
        XCTAssertEqual(palette.soft.hue, 30)
        XCTAssertEqual(palette.bg.lightness, 0.84)
        XCTAssertEqual(palette.bg.chroma, 0.115)
        XCTAssertEqual(palette.edge.lightness, 0.7)
        XCTAssertEqual(palette.fg.lightness, 0.33)
        XCTAssertEqual(palette.accent.chroma, 0.17)
        XCTAssertEqual(palette.soft.lightness, 0.955)
        XCTAssertEqual(palette.bg.lightness, PalettePlaceholders.backgroundLightness)
    }

    func testDifferentHuesStayApart() {
        let hindi = SubjectPalette.from(hue: Double(TonightSubjects.record("hindi")?.hue ?? 0))
        let maths = SubjectPalette.from(hue: Double(TonightSubjects.record("maths")?.hue ?? 0))
        XCTAssertEqual(hindi.bg.hue, 30)
        XCTAssertEqual(maths.bg.hue, 262)
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
        let palette = SubjectPalette.from(hue: Double(TonightSubjects.record("evs")?.hue ?? 0))
        let chip = StaticSubjectChip(title: "EVS", palette: palette)
        XCTAssertEqual(chip.title, "EVS")
        XCTAssertEqual(chip.palette.accent.hue, 142)
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

    func testGeneratedTokensAndSubjectTable() {
        XCTAssertEqual(TonightPalette.cream, "#fff4e2")
        XCTAssertEqual(TonightPalette.ink, "#2e2550")
        XCTAssertEqual(TonightPalette.mango, "#ff8a3d")
        XCTAssertEqual(TonightType.Font.child, "Fredoka, 'Noto Sans Devanagari', system-ui, sans-serif")
        XCTAssertEqual(TonightType.Text.cLabel, 20)
        XCTAssertEqual(TonightType.Text.cBody, 24)
        XCTAssertEqual(TonightType.Text.cRead, 30)
        XCTAssertEqual(TonightSize.tapChild, 64)
        XCTAssertEqual(TonightSize.tapParent, 48)
        XCTAssertEqual(TonightSpace.n4, 16)
        XCTAssertEqual(TonightSubjects.all.count, 20)
        XCTAssertEqual(TonightSubjects.classDefaults[1], ["english", "hindi", "maths", "evs"])
        XCTAssertEqual(TonightSubjects.classDefaults[2], TonightSubjects.classDefaults[1])
        XCTAssertEqual(TonightSubjects.classDefaults[3], TonightSubjects.classDefaults[1])
        XCTAssertEqual(TonightSubjects.autoMark, Set(["english"]))

        let hindi = TonightSubjects.record("hindi")
        XCTAssertEqual(hindi?.nameNative, "हिन्दी")
        XCTAssertEqual(hindi?.names.first { $0.lang == "hi" }?.text, "हिन्दी")
        XCTAssertEqual(hindi?.glyph, "अ")
        XCTAssertEqual(hindi?.hue, 30)
        XCTAssertEqual(hindi?.lang, "hi")
        XCTAssertEqual(hindi?.enabledByDefault, true)
        XCTAssertEqual(hindi?.bg, "#ffae9e")
        XCTAssertEqual(hindi?.autoMark, false)

        XCTAssertEqual(TonightSubjects.record("english")?.autoMark, true)
        XCTAssertEqual(TonightSubjects.record("english")?.enabledByDefault, true)
        XCTAssertEqual(TonightSubjects.record("english")?.hue, 335)
        XCTAssertEqual(TonightSubjects.record("urdu")?.dir, "rtl")
        XCTAssertEqual(TonightSubjects.record("urdu")?.nameNative, "اردو")
        XCTAssertEqual(TonightSubjects.record("tamil")?.nameNative, "தமிழ்")
        XCTAssertEqual(TonightSubjects.scriptFonts["ur"], "Noto Nastaliq Urdu")
        XCTAssertEqual(TonightSubjects.all.filter(\.enabledByDefault).map(\.id).sorted(), ["english", "evs", "hindi", "maths"])
        XCTAssertEqual(ConsentCopy.placeholder, "Consent copy placeholder")
    }

    func testDesignSourcesDoNotAnimate() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DesignSystem")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        let text = try files.filter { $0.pathExtension == "swift" }.map { try String(contentsOf: $0) }.joined(separator: "\n")
        XCTAssertFalse(text.contains("withAnimation"))
        XCTAssertFalse(TonightMotion.animationsInV1)
    }
}
