import SwiftUI

/// Chanda the moon. Faces are still drawings. Mood names match the spec.
public enum ChandaMood: String, Sendable {
    case idle
    case listening
    case recording
    case success
    case tryAgain
}

public struct ChandaView: View {
    public var mood: ChandaMood
    public var size: CGFloat

    public init(mood: ChandaMood, size: CGFloat) {
        self.mood = mood
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(TonightColor.sunEdge)
                .offset(y: size * 0.04)
            Circle()
                .fill(TonightColor.sun)
            cheeks
            eyes
            mouth
            if mood == .success {
                sparkles
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch mood {
        case .idle: return "Chanda"
        case .listening: return "Chanda listening"
        case .recording: return "Chanda listening"
        case .success: return "Chanda cheering"
        case .tryAgain: return "Chanda"
        }
    }

    private var cheeks: some View {
        HStack(spacing: size * 0.42) {
            Circle().fill(TonightColor.mango.opacity(0.45)).frame(width: size * 0.12, height: size * 0.08)
            Circle().fill(TonightColor.mango.opacity(0.45)).frame(width: size * 0.12, height: size * 0.08)
        }
        .offset(y: size * 0.08)
    }

    @ViewBuilder
    private var eyes: some View {
        let eye = size * 0.08
        HStack(spacing: size * 0.22) {
            eyeShape(eye)
            eyeShape(eye)
        }
        .offset(y: -size * 0.06)
    }

    @ViewBuilder
    private func eyeShape(_ eye: CGFloat) -> some View {
        switch mood {
        case .success:
            HappyEye()
                .stroke(TonightColor.ink, style: StrokeStyle(lineWidth: max(2, size * 0.035), lineCap: .round))
                .frame(width: eye * 1.3, height: eye * 0.7)
        case .tryAgain:
            Circle().fill(TonightColor.ink).frame(width: eye * 0.7, height: eye * 0.7)
        default:
            Circle().fill(TonightColor.ink).frame(width: eye, height: eye)
        }
    }

    private var mouth: some View {
        let smile = mood == .tryAgain ? 0.35 : 1.0
        return Smile(open: mood == .success)
            .stroke(TonightColor.ink, style: StrokeStyle(lineWidth: max(2, size * 0.04), lineCap: .round))
            .frame(width: size * 0.28, height: size * 0.14 * smile)
            .offset(y: size * 0.16)
    }

    private var sparkles: some View {
        ZStack {
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.16, weight: .bold))
                .foregroundStyle(TonightColor.sunEdge)
                .offset(x: -size * 0.55, y: -size * 0.42)
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.12, weight: .bold))
                .foregroundStyle(TonightColor.sunEdge)
                .offset(x: size * 0.55, y: -size * 0.36)
        }
    }
}

private struct Smile: Shape {
    var open: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.2))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.2),
            control: CGPoint(x: rect.midX, y: rect.maxY + (open ? rect.height * 0.4 : 0))
        )
        return path
    }
}

private struct HappyEye: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY)
        )
        return path
    }
}
