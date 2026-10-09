import SwiftUI

/// A subject name on its soft token, with the accent as a still bar.
public struct StaticSubjectChip: View {
    public var title: String
    public var palette: SubjectPalette

    public init(title: String, palette: SubjectPalette) {
        self.title = title
        self.palette = palette
    }

    public var body: some View {
        Text(title)
            .font(.title3)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(palette.fg.color)
            .background(palette.soft.color)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(palette.accent.color)
                    .frame(width: 6)
            }
            .accessibilityLabel(title)
    }
}

/// A still block of text. Used for the child home and the parent placeholder.
public struct StaticCopyBlock: View {
    public var title: String
    public var lines: [String]

    public init(title: String, lines: [String]) {
        self.title = title
        self.lines = lines
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.largeTitle)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.title3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
