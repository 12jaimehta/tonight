import SwiftUI

/// Colours from the generated palette. Screens use these instead of a second set of hex values.
public enum TonightColor {
    public static func hex(_ value: String) -> Color {
        var hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        var number: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&number)
        let red = Double((number >> 16) & 0xFF) / 255
        let green = Double((number >> 8) & 0xFF) / 255
        let blue = Double(number & 0xFF) / 255
        return Color(red: red, green: green, blue: blue)
    }

    public static let cream = hex(TonightPalette.cream)
    public static let creamDot = hex(TonightPalette.creamDot)
    public static let ink = hex(TonightPalette.ink)
    public static let inkSoft = hex(TonightPalette.inkSoft)
    public static let white = hex(TonightPalette.white)
    public static let sun = hex(TonightPalette.sun)
    public static let sunEdge = hex(TonightPalette.sunEdge)
    public static let sky = hex(TonightPalette.sky)
    public static let skyEdge = hex(TonightPalette.skyEdge)
    public static let mint = hex(TonightPalette.mint)
    public static let mintEdge = hex(TonightPalette.mintEdge)
    public static let berry = hex(TonightPalette.berry)
    public static let berryEdge = hex(TonightPalette.berryEdge)
    public static let mango = hex(TonightPalette.mango)
    public static let mangoSoft = hex(TonightPalette.mangoSoft)
    public static let grape = hex(TonightPalette.grape)
    public static let grapeEdge = hex(TonightPalette.grapeEdge)
    public static let grapeSoft = hex(TonightPalette.grapeSoft)
    public static let star = hex(TonightPalette.star)
    public static let starEdge = hex(TonightPalette.starEdge)
    public static let starEmpty = hex(TonightPalette.starEmpty)
    public static let toyEdge = hex(TonightPalette.toyEdge)
    public static let pBg = hex(TonightPalette.pBg)
    public static let pCard = hex(TonightPalette.pCard)
    public static let pInk = hex(TonightPalette.pInk)
    public static let pInkSoft = hex(TonightPalette.pInkSoft)
    public static let pLine = hex(TonightPalette.pLine)
    public static let pAccent = hex(TonightPalette.pAccent)
    public static let pAccentInk = hex(TonightPalette.pAccentInk)
    public static let pSuccess = hex(TonightPalette.pSuccess)
    public static let pSuccessSoft = hex(TonightPalette.pSuccessSoft)
    public static let pWarnSoft = hex(TonightPalette.pWarnSoft)
    public static let pWarnInk = hex(TonightPalette.pWarnInk)
    public static let pError = hex(TonightPalette.pError)
    public static let pErrorSoft = hex(TonightPalette.pErrorSoft)
}

/// Fredoka, Nunito, and the Noto script files are not in the repo yet.
/// Until they are bundled, child type uses the rounded system face at the token sizes.
public enum TonightFont {
    public static func child(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    public static func parent(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
