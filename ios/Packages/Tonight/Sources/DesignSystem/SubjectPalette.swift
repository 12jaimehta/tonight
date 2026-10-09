import Foundation

/// Four tokens for one subject. The hue comes from the subject row.
/// Lightness and chroma are stand-ins until Tonight Design publishes the numbers.
public struct SubjectPalette: Hashable, Sendable {
    public var bg: OKLCH
    public var fg: OKLCH
    public var accent: OKLCH
    public var soft: OKLCH

    public init(bg: OKLCH, fg: OKLCH, accent: OKLCH, soft: OKLCH) {
        self.bg = bg
        self.fg = fg
        self.accent = accent
        self.soft = soft
    }

    public static func from(hue: Double) -> SubjectPalette {
        let hue = normalizedHue(hue)
        return SubjectPalette(
            bg: OKLCH(lightness: PalettePlaceholders.backgroundLightness, chroma: PalettePlaceholders.backgroundChroma, hue: hue),
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

/// Placeholder lightness and chroma. Replace these when design ships the real tokens.
public enum PalettePlaceholders {
    public static let backgroundLightness = 0.96
    public static let backgroundChroma = 0.03
    public static let foregroundLightness = 0.30
    public static let foregroundChroma = 0.07
    public static let accentLightness = 0.62
    public static let accentChroma = 0.14
    public static let softLightness = 0.91
    public static let softChroma = 0.045
}
