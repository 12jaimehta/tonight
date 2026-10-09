import Foundation

/// Subject colours from the tokens.json recipe. The hue comes from subjects.py.
public struct SubjectPalette: Hashable, Sendable {
    public var bg: OKLCH
    public var edge: OKLCH
    public var fg: OKLCH
    public var accent: OKLCH
    public var soft: OKLCH

    public init(bg: OKLCH, edge: OKLCH, fg: OKLCH, accent: OKLCH, soft: OKLCH) {
        self.bg = bg
        self.edge = edge
        self.fg = fg
        self.accent = accent
        self.soft = soft
    }

    public static func from(hue: Double) -> SubjectPalette {
        let hue = normalizedHue(hue)
        return SubjectPalette(
            bg: OKLCH(lightness: PalettePlaceholders.backgroundLightness, chroma: PalettePlaceholders.backgroundChroma, hue: hue),
            edge: OKLCH(lightness: PalettePlaceholders.edgeLightness, chroma: PalettePlaceholders.edgeChroma, hue: hue),
            fg: OKLCH(lightness: PalettePlaceholders.foregroundLightness, chroma: PalettePlaceholders.foregroundChroma, hue: hue),
            accent: OKLCH(lightness: PalettePlaceholders.accentLightness, chroma: PalettePlaceholders.accentChroma, hue: hue),
            soft: OKLCH(lightness: PalettePlaceholders.softLightness, chroma: PalettePlaceholders.softChroma, hue: hue)
        )
    }

    public static func normalizedHue(_ hue: Double) -> Double {
        guard hue.isFinite else { return 0 }
        let turns = hue.truncatingRemainder(dividingBy: 360)
        return turns < 0 ? turns + 360 : turns
    }
}

/// Recipe lightness and chroma. The numbers are TonightRecipe, generated from tokens.json.
public enum PalettePlaceholders {
    public static let backgroundLightness = TonightRecipe.bgLightness
    public static let backgroundChroma = TonightRecipe.bgChroma
    public static let edgeLightness = TonightRecipe.edgeLightness
    public static let edgeChroma = TonightRecipe.edgeChroma
    public static let foregroundLightness = TonightRecipe.fgLightness
    public static let foregroundChroma = TonightRecipe.fgChroma
    public static let accentLightness = TonightRecipe.accentLightness
    public static let accentChroma = TonightRecipe.accentChroma
    public static let softLightness = TonightRecipe.softLightness
    public static let softChroma = TonightRecipe.softChroma
}
