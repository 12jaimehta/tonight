import DesignSystem
import SwiftUI

/// M3-02 Read aloud. Buttons change the static state. The microphone is not opened.
/// There is no keyboard. Typing the reading is not offered on this screen.
struct ReadAloudScreen: View {
    @Bindable var session: ReadAloudSession
    var passage: String
    var pageTitle: String
    var onBack: @MainActor () -> Void
    var onDone: @MainActor () -> Void
    var onGrownUp: @MainActor () -> Void

    private var words: [String] {
        passage.split { $0.isWhitespace || $0.isNewline }.map(String.init)
    }

    var body: some View {
        ZStack {
            ToyRoomBackground()
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 22, weight: .bold))
                            .frame(width: CGFloat(TonightSize.tapChild), height: CGFloat(TonightSize.tapChild))
                    }
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("read.back")
                    SubjectBadge(subjectID: "english", size: 48)
                    Text("English")
                        .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
                    Spacer()
                }
                bubble
                if session.phase == .micOff || session.phase == .unavailable {
                    grownUpCard
                    Spacer()
                } else {
                    pageCard
                    Spacer(minLength: 0)
                    dock
                }
            }
            .padding(16)
        }
    }

    private var bubble: some View {
        HStack(alignment: .top, spacing: 8) {
            ChandaView(mood: chanda, size: 76)
            Text(bubbleText)
                .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
                .foregroundStyle(TonightColor.ink)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(TonightColor.white))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chanda: ChandaMood {
        switch session.phase {
        case .hearing: return .listening
        case .recording: return .recording
        case .micOff, .unavailable: return .tryAgain
        case .idle: return .idle
        }
    }

    private var bubbleText: String {
        switch session.phase {
        case .idle: return "Read \(pageTitle) out loud! Tap the blue button to hear it first."
        case .hearing: return "Listen with me…"
        case .recording: return "I'm listening!"
        case .micOff: return "Let's get a grown-up. Tonight can't hear you yet."
        case .unavailable: return "Let's get a grown-up."
        }
    }

    private var pageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pageTitle)
                .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
            RoundedRectangle(cornerRadius: 12)
                .fill(TonightColor.cream)
                .frame(width: 72, height: 64)
                .overlay { Image(systemName: "doc.text") }
                .accessibilityLabel("Scanned \(pageTitle)")
            WordWrap {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    Text(word)
                        .font(TonightFont.child(CGFloat(TonightType.Text.cRead)))
                        .padding(.horizontal, 2)
                        .background(highlight(index))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(TonightColor.white))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(passage)
    }

    private func highlight(_ index: Int) -> Color {
        switch session.phase {
        case .hearing:
            return index == 0 ? TonightColor.sun : .clear
        case .recording:
            if index < 3 { return TonightColor.mint.opacity(0.35) }
            if index == 3 { return TonightColor.sun }
            return .clear
        default:
            return .clear
        }
    }

    private var dock: some View {
        HStack(alignment: .bottom, spacing: 16) {
            labeled("Hear it", session.phase == .hearing ? "Stop" : "Hear it") {
                Button(action: { session.hear() }) {
                    Image(systemName: session.phase == .hearing ? "stop.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(RoundToyButtonStyle(fill: TonightColor.sky, edge: TonightColor.skyEdge, foreground: TonightColor.ink, diameter: CGFloat(TonightSize.tapChildLg)))
                .disabled(session.phase == .recording)
                .accessibilityIdentifier("read.hear")
            }
            labeled("Read", session.phase == .recording ? "Pause" : "Read") {
                Button(action: { session.phase == .recording ? session.pause() : session.read() }) {
                    Image(systemName: session.phase == .recording ? "pause.fill" : "mic.fill")
                }
                .buttonStyle(RoundToyButtonStyle(
                    fill: session.phase == .recording ? TonightColor.berry : TonightColor.sun,
                    edge: session.phase == .recording ? TonightColor.berryEdge : TonightColor.sunEdge,
                    diameter: CGFloat(TonightSize.tapChildHero)
                ))
                .disabled(session.phase == .hearing)
                .accessibilityLabel(session.phase == .recording ? "Pause reading" : "Start reading")
                .accessibilityIdentifier("read.mic")
            }
            if session.started {
                labeled("Done", "Done") {
                    Button(action: onDone) {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(RoundToyButtonStyle(fill: TonightColor.mint, edge: TonightColor.mintEdge, diameter: CGFloat(TonightSize.tapChildLg)))
                    .accessibilityIdentifier("read.done")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func labeled<Content: View>(_ id: String, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 4) {
            content()
            Text(title)
                .font(TonightFont.child(16))
                .foregroundStyle(TonightColor.ink)
        }
    }

    private var grownUpCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.phase == .unavailable
                 ? "Reading marks need a newer iPhone. Make this a Notebook task instead."
                 : "Microphone access is off for Tonight. Open Settings › Tonight › Microphone and turn it on. The voice is processed on this phone and isn't saved.")
                .font(TonightFont.parent(CGFloat(TonightType.Text.pBase)))
                .foregroundStyle(TonightColor.ink)
            Button(action: onGrownUp) {
                Text("Get a grown-up")
            }
            .buttonStyle(ToyButtonStyle(fill: TonightColor.grape, edge: TonightColor.grapeEdge, foreground: TonightColor.white, minHeight: CGFloat(TonightSize.tapChildLg)))
            .accessibilityIdentifier("read.grownup")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(TonightColor.white))
    }
}

/// Still rows of words. Nothing moves.
struct WordWrap: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let rows = rows(width: width, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indexes {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [(indexes: [Int], height: CGFloat)] {
        var rows: [(indexes: [Int], height: CGFloat)] = []
        var current: [Int] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = rowWidth == 0 ? size.width : rowWidth + spacing + size.width
            if next > width && !current.isEmpty {
                rows.append((current, rowHeight))
                current = [index]
                rowWidth = size.width
                rowHeight = size.height
            } else {
                current.append(index)
                rowWidth = next
                rowHeight = max(rowHeight, size.height)
            }
        }
        if !current.isEmpty { rows.append((current, rowHeight)) }
        return rows
    }
}

#Preview("Idle") {
    ReadAloudScreen(session: ReadAloudSession.preview(phase: .idle), passage: TodayCopy.passage, pageTitle: "Page 12", onBack: {}, onDone: {}, onGrownUp: {})
}

#Preview("Hearing") {
    ReadAloudScreen(session: ReadAloudSession.preview(phase: .hearing), passage: TodayCopy.passage, pageTitle: "Page 12", onBack: {}, onDone: {}, onGrownUp: {})
}

#Preview("Recording") {
    ReadAloudScreen(session: ReadAloudSession.preview(phase: .recording), passage: TodayCopy.passage, pageTitle: "Page 12", onBack: {}, onDone: {}, onGrownUp: {})
}

#Preview("Mic off") {
    ReadAloudScreen(session: ReadAloudSession.preview(phase: .micOff), passage: TodayCopy.passage, pageTitle: "Page 12", onBack: {}, onDone: {}, onGrownUp: {})
}
