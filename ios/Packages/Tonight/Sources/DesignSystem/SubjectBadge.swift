import SwiftUI

/// Toy-block subject badge. Colours come from the generated subject tokens.
public struct SubjectBadge: View {
    public var subjectID: String
    public var size: CGFloat

    public init(subjectID: String, size: CGFloat) {
        self.subjectID = subjectID
        self.size = size
    }

    public var body: some View {
        let subject = TonightSubjects.record(subjectID)
        let bg = TonightColor.hex(subject?.bg ?? TonightPalette.pLine)
        let edge = TonightColor.hex(subject?.edge ?? TonightPalette.ink)
        let fg = TonightColor.hex(subject?.fg ?? TonightPalette.ink)
        let accent = TonightColor.hex(subject?.accent ?? TonightPalette.pAccent)
        let radius = size * 0.32
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        ZStack {
            shape.fill(bg)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle()
                    .fill(edge)
                    .frame(height: size * 0.09)
            }
            .clipShape(shape)
            glyph(subject, fg: fg)
            Circle()
                .fill(accent)
                .frame(width: size * 0.16, height: size * 0.16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(size * 0.09)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subject?.nameEn ?? subjectID)
        .accessibilityLanguage(subject?.lang ?? "en")
    }

    @ViewBuilder
    private func glyph(_ subject: TonightSubject?, fg: Color) -> some View {
        if subject?.glyphKind == "glyph" {
            Text(subject?.glyph ?? "?")
                .font(TonightFont.child(size * 0.36))
                .foregroundStyle(fg)
                .environment(\.layoutDirection, subject?.dir == "rtl" ? .rightToLeft : .leftToRight)
        } else {
            Image(systemName: SubjectSymbol.systemName(for: subject?.glyph ?? ""))
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(fg)
        }
    }
}

public enum SubjectSymbol {
    public static func systemName(for glyph: String) -> String {
        switch glyph {
        case "s-maths": return "plus.forwardslash.minus"
        case "s-science": return "atom"
        case "s-social": return "globe.americas.fill"
        case "s-evs": return "leaf.fill"
        case "s-computers": return "desktopcomputer"
        case "s-gk": return "lightbulb.fill"
        case "s-art": return "paintpalette.fill"
        default: return "circle.fill"
        }
    }
}
