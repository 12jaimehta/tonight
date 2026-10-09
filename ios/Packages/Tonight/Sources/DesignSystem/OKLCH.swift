import SwiftUI

/// A colour in OKLCH. Lightness is 0...1, chroma is OKLCH chroma, hue is degrees.
public struct OKLCH: Hashable, Sendable {
    public var lightness: Double
    public var chroma: Double
    public var hue: Double

    public init(lightness: Double, chroma: Double, hue: Double) {
        self.lightness = lightness
        self.chroma = chroma
        self.hue = hue
    }

    /// sRGB for SwiftUI. Components are clamped after the OKLab conversion.
    public var color: Color {
        let (red, green, blue) = OKLCHColor.srgb(self)
        return Color(red: red, green: green, blue: blue)
    }

    public var css: String {
        "oklch(\(lightness) \(chroma) \(hue))"
    }
}

enum OKLCHColor {
    static func srgb(_ color: OKLCH) -> (Double, Double, Double) {
        let radians = color.hue * .pi / 180
        let a = color.chroma * cos(radians)
        let b = color.chroma * sin(radians)
        let l = color.lightness + 0.3963377774 * a + 0.2158037573 * b
        let m = color.lightness - 0.1055613458 * a - 0.0638541728 * b
        let s = color.lightness - 0.0894841775 * a - 1.2914855480 * b
        let lmsL = l * l * l
        let lmsM = m * m * m
        let lmsS = s * s * s
        let red = 4.0767416621 * lmsL - 3.3077115913 * lmsM + 0.2309699292 * lmsS
        let green = -1.2684380046 * lmsL + 2.6097574011 * lmsM - 0.3413193965 * lmsS
        let blue = -0.0041960863 * lmsL - 0.7034186147 * lmsM + 1.7076147010 * lmsS
        return (encode(red), encode(green), encode(blue))
    }

    private static func encode(_ linear: Double) -> Double {
        let mapped: Double
        if linear <= 0.0031308 {
            mapped = 12.92 * linear
        } else {
            mapped = 1.055 * pow(linear, 1 / 2.4) - 0.055
        }
        return min(1, max(0, mapped))
    }
}
