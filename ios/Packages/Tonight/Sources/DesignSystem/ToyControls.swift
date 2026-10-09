import SwiftUI

/// Cream room with the still dot pattern. Nothing here moves.
public struct ToyRoomBackground: View {
    public init() {}

    public var body: some View {
        TonightColor.cream
            .overlay {
                Canvas { context, size in
                    let step: CGFloat = 18
                    var y: CGFloat = 10
                    while y < size.height {
                        var x: CGFloat = 10
                        while x < size.width {
                            let dot = CGRect(x: x, y: y, width: 3, height: 3)
                            context.fill(Path(ellipseIn: dot), with: .color(TonightColor.creamDot))
                            x += step
                        }
                        y += step
                    }
                }
            }
            .ignoresSafeArea()
    }
}

public struct ParentRoomBackground: View {
    public init() {}

    public var body: some View {
        TonightColor.pBg.ignoresSafeArea()
    }
}

/// Thick-edge toy surface. Pressed state is a still offset: 6pt down, 2pt edge. No animation.
public struct ToySurface<Label: View>: View {
    public var fill: Color
    public var edge: Color
    public var pressed: Bool
    public var radius: CGFloat
    public var label: Label

    public init(fill: Color, edge: Color, pressed: Bool, radius: CGFloat, @ViewBuilder label: () -> Label) {
        self.fill = fill
        self.edge = edge
        self.pressed = pressed
        self.radius = radius
        self.label = label()
    }

    public var body: some View {
        let edgeDrop: CGFloat = pressed ? 2 : CGFloat(TonightEdge.toy)
        let sink: CGFloat = pressed ? CGFloat(TonightEdge.pressDepth) : 0
        label
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .background(alignment: .bottom) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(edge)
                    .offset(y: edgeDrop)
            }
            .offset(y: sink)
            .padding(.bottom, CGFloat(TonightEdge.toy))
    }
}

public struct ToyButtonStyle: ButtonStyle {
    public var fill: Color
    public var edge: Color
    public var foreground: Color
    public var minHeight: CGFloat
    public var radius: CGFloat

    public init(
        fill: Color,
        edge: Color,
        foreground: Color = TonightColor.ink,
        minHeight: CGFloat = CGFloat(TonightSize.tapChild),
        radius: CGFloat = CGFloat(TonightRadius.lg)
    ) {
        self.fill = fill
        self.edge = edge
        self.foreground = foreground
        self.minHeight = minHeight
        self.radius = radius
    }

    public func makeBody(configuration: Configuration) -> some View {
        ToySurface(fill: fill, edge: edge, pressed: configuration.isPressed, radius: radius) {
            configuration.label
                .font(TonightFont.child(18))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .padding(.horizontal, 16)
        }
    }
}

public struct RoundToyButtonStyle: ButtonStyle {
    public var fill: Color
    public var edge: Color
    public var foreground: Color
    public var diameter: CGFloat

    public init(fill: Color, edge: Color, foreground: Color = TonightColor.ink, diameter: CGFloat) {
        self.fill = fill
        self.edge = edge
        self.foreground = foreground
        self.diameter = diameter
    }

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let edgeDrop: CGFloat = pressed ? 2 : CGFloat(TonightEdge.toy)
        let sink: CGFloat = pressed ? CGFloat(TonightEdge.pressDepth) : 0
        configuration.label
            .font(TonightFont.child(16))
            .foregroundStyle(foreground)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(fill))
            .background(alignment: .bottom) {
                Circle().fill(edge).offset(y: edgeDrop)
            }
            .offset(y: sink)
            .padding(.bottom, CGFloat(TonightEdge.toy))
    }
}

public struct ParentWideButtonStyle: ButtonStyle {
    public var fill: Color
    public var foreground: Color

    public init(fill: Color, foreground: Color) {
        self.fill = fill
        self.foreground = foreground
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TonightFont.parent(18, weight: .bold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: CGFloat(TonightRadius.lg), style: .continuous)
                    .fill(fill)
            )
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

public struct ParentCard<Content: View>: View {
    public var content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CGFloat(TonightRadius.lg), style: .continuous)
                    .fill(TonightColor.pCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CGFloat(TonightRadius.lg), style: .continuous)
                    .stroke(TonightColor.pLine, lineWidth: 1)
            )
    }
}

public struct ParentSectionLabel: View {
    public var title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(TonightFont.parent(CGFloat(TonightType.Text.pXs), weight: .bold))
            .foregroundStyle(TonightColor.pInkSoft)
            .textCase(.uppercase)
            .tracking(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
