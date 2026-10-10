import DesignSystem
import MarkingKit
import ProfilesKit
import SpeechKit
import SwiftUI
import TaskKit

/// M3-03. A hidden mark renders no stars, numbers, or word list.
struct ChildResultScreen: View {
    var child: ChildProfile
    var task: HomeworkTask
    var mark: Mark
    var inputMode: InputMode = .spoken
    var speech: any SpeechSynthesizing = IndianEnglishSpeech()
    var onHome: @MainActor () -> Void
    @State private var hearing: String?

    private var visible: Bool {
        MarkVisibility.shownToChild(taskOverride: task.showMarkOverride, childDefault: child.showMarkToChild)
    }

    private var stars: Int {
        EnglishStars.count(for: mark, inputMode: inputMode)
    }

    var body: some View {
        ZStack {
            ToyRoomBackground()
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        SubjectBadge(subjectID: "english", size: 48)
                        Text("English")
                            .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
                    }
                    ChandaView(mood: .success, size: 104)
                    if visible {
                        shown
                    } else {
                        hidden
                    }
                    Button(action: onHome) {
                        Label("My homework", systemImage: "house.fill")
                    }
                    .buttonStyle(ToyButtonStyle(fill: TonightColor.sun, edge: TonightColor.sunEdge, minHeight: CGFloat(TonightSize.tapChildLg)))
                    .accessibilityIdentifier("result.home")
                }
                .padding(20)
            }
        }
    }

    private var shown: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(TonightFont.child(CGFloat(TonightType.Text.cTitle)))
                .multilineTextAlignment(.center)
            StarRow(filled: stars, size: 76)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(stars) of 3 stars")
            Text("You read \(mark.correct) of \(mark.total) words")
                .font(TonightFont.child(CGFloat(TonightType.Text.cBody)))
            if mark.missed.isEmpty {
                Text("You read every word!")
                    .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
            } else {
                tricky
            }
        }
    }

    private var hidden: some View {
        VStack(spacing: 12) {
            Text("All done!")
                .font(TonightFont.child(CGFloat(TonightType.Text.cTitle)))
            Text("You read the whole page. \(child.parentLabel) will see how it went.")
                .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
                .multilineTextAlignment(.center)
            Text("\(child.parentLabel) might send you a message soon!")
                .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 20).fill(TonightColor.grapeSoft))
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch stars {
        case 3: return "Super reading!"
        case 2: return "Great reading!"
        default: return "Good try! Let's hear the tricky ones."
        }
    }

    private var tricky: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tricky words. Tap to hear them!")
                .font(TonightFont.child(18))
                ForEach(Array(mark.missed.prefix(3).enumerated()), id: \.offset) { _, word in
                HStack {
                    Text(word)
                        .font(TonightFont.child(26))
                    Spacer()
                    Button(action: {
                        hearing = word
                        let speaker = speech
                        Task { await SpokenCue.word(word, using: speaker) }
                    }) {
                        Image(systemName: hearing == word ? "speaker.wave.2.fill" : "speaker.wave.2")
                            .frame(width: CGFloat(TonightSize.tapChild), height: CGFloat(TonightSize.tapChild))
                    }
                    .buttonStyle(RoundToyButtonStyle(fill: TonightColor.sky, edge: TonightColor.skyEdge, diameter: CGFloat(TonightSize.tapChild)))
                    .accessibilityLabel("Hear \(word)")
                }
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 18).fill(TonightColor.white))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(TonightColor.mango, lineWidth: 3))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 22).fill(TonightColor.mangoSoft))
    }
}

struct StarRow: View {
    var filled: Int
    var size: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index < filled ? "star.fill" : "star")
                    .font(.system(size: size * 0.7))
                    .foregroundStyle(index < filled ? TonightColor.star : TonightColor.starEmpty)
                    .frame(width: size, height: size)
            }
        }
    }
}

#Preview("Mark shown") {
    ChildResultScreen(
        child: ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: true, parentLabel: "Mummy"),
        task: sampleEnglishTask(show: true),
        mark: TodayCopy.sampleMark(),
        onHome: {}
    )
}

#Preview("Mark hidden") {
    ChildResultScreen(
        child: ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: false, parentLabel: "Mummy"),
        task: sampleEnglishTask(show: false),
        mark: TodayCopy.sampleMark(),
        onHome: {}
    )
}

private func sampleEnglishTask(show: Bool) -> HomeworkTask {
    var task = HomeworkTask(
        id: UUID(),
        childID: UUID(),
        subjectID: "english",
        schoolClass: "1",
        instruction: "Read page 12",
        checkMode: .auto,
        confirmedText: TodayCopy.passage,
        pagePhotoRefs: [],
        media: [],
        showMarkOverride: show,
        stars: nil,
        createdAt: Date()
    )
    if show {
        task.showMarkOverride = nil
    }
    return task
}
