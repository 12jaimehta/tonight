import DesignSystem
import MarkingKit
import ProfilesKit
import SwiftUI
import TaskKit

/// M3-05. Show Mummy opens the parental gate, then the parent check.
struct ParentChecksChildScreen: View {
    var child: ChildProfile
    var task: HomeworkTask
    var gate: GateModel
    var onShow: @MainActor () -> Void
    var onLater: @MainActor () -> Void
    var onKey: @MainActor (String) -> Void
    var onCloseGate: @MainActor () -> Void

    var body: some View {
        ZStack {
            ToyRoomBackground()
            VStack(spacing: 16) {
                ChandaView(mood: .success, size: 104)
                Text("All done!")
                    .font(TonightFont.child(CGFloat(TonightType.Text.cHero)))
                Text("Now show \(child.parentLabel) your work. \(child.parentLabel) will check it and send you a message.")
                    .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Image(systemName: "eye")
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(TonightColor.grapeSoft))
                    Text("\(child.parentLabel) checks")
                        .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
                    Spacer()
                    Image(systemName: "doc.text")
                        .frame(width: 64, height: 48)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18).fill(TonightColor.white))
                Button(action: onShow) {
                    Text("Show \(child.parentLabel)")
                }
                .buttonStyle(ToyButtonStyle(fill: TonightColor.grape, edge: TonightColor.grapeEdge, foreground: TonightColor.white, minHeight: CGFloat(TonightSize.tapChildLg)))
                .accessibilityHint("Opens a grown-up check")
                .accessibilityIdentifier("checks.show")
                Button("Later", action: onLater)
                    .buttonStyle(ToyButtonStyle(fill: TonightColor.white, edge: TonightColor.toyEdge, minHeight: CGFloat(TonightSize.tapChild)))
                    .accessibilityIdentifier("checks.later")
                Spacer()
            }
            .padding(20)
            if gate.presented {
                ParentalGateSheet(gate: gate, childName: child.nickname, onKey: onKey, onClose: onCloseGate)
            }
        }
    }
}

/// M3-06. The parent sees the stored mark. The child does not.
struct ParentResultScreen: View {
    var child: ChildProfile
    var task: HomeworkTask
    var mark: Mark
    @Bindable var praise: PraiseDraft
    var onBack: @MainActor () -> Void
    var onToggle: @MainActor (Bool) -> Void
    var onSend: @MainActor () -> Void

    private var shown: Bool {
        MarkVisibility.shownToChild(taskOverride: task.showMarkOverride, childDefault: child.showMarkToChild)
    }

    var body: some View {
        ZStack {
            ParentRoomBackground()
            VStack(spacing: 0) {
                DraftHeader(title: "\(child.nickname)'s reading", close: "chevron.left", action: onBack)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("\(mark.correct) of \(mark.total)")
                            .font(TonightFont.child(CGFloat(TonightType.Text.pHero)))
                        Text("words read correctly")
                            .font(TonightFont.parent(CGFloat(TonightType.Text.pBase)))
                            .foregroundStyle(TonightColor.pInkSoft)
                        passage
                        legend
                        Text("Tries tonight")
                            .font(TonightFont.parent(CGFloat(TonightType.Text.pSm), weight: .bold))
                        HStack(spacing: 8) {
                            Text("This try")
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(TonightColor.pAccent, lineWidth: 2))
                            Text("Try again")
                                .foregroundStyle(TonightColor.pInkSoft)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(RoundedRectangle(cornerRadius: 12).fill(TonightColor.pLine.opacity(0.5)))
                                .accessibilityLabel("Try again, later")
                        }
                        Toggle(isOn: Binding(get: { shown }, set: { onToggle($0) })) {
                            Text("Show this mark to \(child.nickname)")
                                .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .bold))
                        }
                        .tint(TonightColor.pSuccess)
                        .accessibilityIdentifier("result.visibility")
                        Text(shown
                             ? "On: \(child.nickname) sees \(EnglishStars.count(for: mark)) stars and '\(mark.correct) of \(mark.total)'"
                             : "Off: \(child.nickname) sees 'All done!' only")
                            .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
                            .foregroundStyle(TonightColor.pInkSoft)
                        Text("Send praise")
                            .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .bold))
                        PraiseChips(draft: praise, presets: PraisePresets.reading)
                        Button(action: onSend) {
                            Text(praise.sent ? "Sent ✓" : "Send to \(child.nickname)")
                        }
                        .buttonStyle(ParentWideButtonStyle(fill: TonightColor.pAccent, foreground: TonightColor.pAccentInk))
                        .disabled(praise.sent || praise.phrase == nil)
                        .opacity(praise.sent || praise.phrase == nil ? 0.45 : 1)
                        .accessibilityIdentifier("result.send")
                    }
                    .padding(24)
                }
            }
        }
    }

    private var passage: some View {
        WordWrap {
            ForEach(mark.words) { word in
                wordView(word)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(TonightColor.white))
    }

    @ViewBuilder
    private func wordView(_ word: AlignedWord) -> some View {
        if let expected = word.expected {
            VStack(alignment: .leading, spacing: 0) {
                if word.status == .substituted, let heard = word.heard {
                    Text(heard)
                        .font(TonightFont.parent(11, weight: .bold))
                        .foregroundStyle(TonightColor.grape)
                }
                Text(expected)
                    .font(TonightFont.parent(CGFloat(TonightType.Text.pLg), weight: .semibold))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .background(fill(word.status))
                    .underline(word.status == .omitted || word.status == .substituted)
            }
            .accessibilityLabel(spoken(word, expected: expected))
        }
    }

    private func fill(_ status: WordStatus) -> Color {
        switch status {
        case .omitted: return TonightColor.mangoSoft
        case .substituted: return TonightColor.grapeSoft
        case .matched, .inserted: return .clear
        }
    }

    private func spoken(_ word: AlignedWord, expected: String) -> String {
        switch word.status {
        case .omitted: return "\(expected), missed"
        case .substituted: return "\(expected), read as \(word.heard ?? "")"
        case .inserted: return "\(word.heard ?? expected), extra"
        case .matched: return expected
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            Text("Missed")
                .padding(.horizontal, 8)
                .background(TonightColor.mangoSoft)
            Text("Substituted")
                .padding(.horizontal, 8)
                .background(TonightColor.grapeSoft)
        }
        .font(TonightFont.parent(12, weight: .bold))
    }
}

/// M3-07. The parent awards 1–3 stars. Zero is not a choice.
struct ParentCheckScreen: View {
    var child: ChildProfile
    var task: HomeworkTask
    @Bindable var praise: PraiseDraft
    var onBack: @MainActor () -> Void
    var onSend: @MainActor () -> Void

    private var marksShown: Bool {
        MarkVisibility.shownToChild(taskOverride: task.showMarkOverride, childDefault: child.showMarkToChild)
    }

    var body: some View {
        let soft = TonightColor.hex(TonightSubjects.record(task.subjectID)?.soft ?? TonightPalette.pBg)
        ZStack {
            ParentRoomBackground()
            VStack(spacing: 0) {
                DraftHeader(title: "Check \(child.nickname)'s \(subjectName)", close: "chevron.left", action: onBack)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                SubjectBadge(subjectID: task.subjectID, size: 40)
                                Text(task.instruction)
                                    .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .bold))
                            }
                            notebookPage
                            Text("Sent 7:31 pm · pinch to zoom")
                                .font(TonightFont.parent(CGFloat(TonightType.Text.pXs)))
                                .foregroundStyle(TonightColor.pInkSoft)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 18).fill(soft))
                        Text("How did it go?")
                            .font(TonightFont.parent(CGFloat(TonightType.Text.pSm), weight: .bold))
                        HStack(spacing: 8) {
                            ForEach(1...3, id: \.self) { count in
                                Button(action: { praise.stars = count }) {
                                    Image(systemName: (praise.stars ?? 0) >= count ? "star.fill" : "star")
                                        .font(.system(size: 28))
                                        .foregroundStyle(TonightColor.star)
                                        .frame(width: 52, height: 52)
                                }
                                .accessibilityLabel("\(count) stars")
                                .accessibilityIdentifier("check.star.\(count)")
                                .selectedTrait(praise.stars == count)
                            }
                            Text("3 = great · 2 = good try · 1 = keep going")
                                .font(TonightFont.parent(12))
                                .foregroundStyle(TonightColor.pInkSoft)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("How did it go?")
                        Text("Say something nice")
                            .font(TonightFont.parent(CGFloat(TonightType.Text.pSm), weight: .bold))
                        PraiseChips(draft: praise, presets: PraisePresets.notebook)
                        Text(previewLine)
                            .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
                            .foregroundStyle(TonightColor.pInkSoft)
                            .accessibilityIdentifier("check.preview")
                    }
                    .padding(24)
                }
                Button(action: onSend) {
                    Text(praise.sent ? "Sent ✓" : "Send to \(child.nickname)")
                }
                .buttonStyle(ParentWideButtonStyle(fill: TonightColor.pAccent, foreground: TonightColor.pAccentInk))
                .disabled(praise.stars == nil || praise.sent)
                .opacity(praise.stars == nil || praise.sent ? 0.45 : 1)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .accessibilityIdentifier("check.send")
            }
        }
    }

    private var notebookPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("2 + 3 = 5    4 + 1 = 5")
            Text("6 − 2 = 4    3 + 3 = 6")
            Text("5 − 1 = 3    2 + 2 = 4")
        }
        .font(TonightFont.parent(18, weight: .semibold))
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(TonightColor.white))
        .accessibilityLabel("Photo of \(child.nickname)'s notebook, \(subjectName)")
    }

    private var subjectName: String {
        SubjectCatalog.record(task.subjectID)?.nameEn ?? task.subjectID
    }

    private var previewLine: String {
        let phrase = praise.phrase ?? "a message"
        if marksShown, let stars = praise.stars {
            return "\(child.nickname) will see: \(stars) stars + '\(phrase)'"
        }
        if marksShown {
            return "\(child.nickname) will see the stars you pick."
        }
        return "\(child.nickname) will see: '\(phrase)' (marks are hidden for \(child.nickname))"
    }
}

struct PraiseChips: View {
    @Bindable var draft: PraiseDraft
    var presets: [PraisePreset]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(presets) { preset in
                    Button(preset.phrase) { draft.presetID = preset.id; draft.writing = false }
                        .font(TonightFont.parent(14, weight: .bold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(draft.presetID == preset.id ? TonightColor.grapeSoft : TonightColor.white))
                        .overlay(Capsule().stroke(draft.presetID == preset.id ? TonightColor.pAccent : TonightColor.pLine, lineWidth: 1))
                        .accessibilityIdentifier("praise.\(preset.id)")
                        .environment(\.locale, Locale(identifier: preset.lang))
                        .selectedTrait(draft.presetID == preset.id)
                }
            }
            Button("Write…") { draft.writing = true; draft.presetID = nil }
                .font(TonightFont.parent(14, weight: .bold))
                .frame(minHeight: 44)
                .accessibilityIdentifier("praise.write")
            if draft.writing {
                TextField("A short note", text: $draft.custom)
                    .onChange(of: draft.custom) { _, value in
                        if value.count > 40 { draft.custom = String(value.prefix(40)) }
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 12).stroke(TonightColor.pLine, lineWidth: 1))
                    .accessibilityIdentifier("praise.custom")
            }
        }
    }
}

/// M3-08. Thank you marks the praise seen. It does not send anything back.
struct PraiseMessageScreen: View {
    var child: ChildProfile
    var task: HomeworkTask
    var praise: Praise
    var stars: Int?
    var markVisible: Bool
    var onHear: @MainActor () -> Void
    var onThanks: @MainActor () -> Void

    var body: some View {
        ZStack {
            ToyRoomBackground()
            VStack(spacing: 16) {
                HStack {
                    SubjectBadge(subjectID: task.subjectID, size: 48)
                    Text(subjectName)
                        .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
                    Spacer()
                }
                Text(headline)
                    .font(TonightFont.child(CGFloat(TonightType.Text.cTitle)))
                    .multilineTextAlignment(.center)
                if markVisible, let stars {
                    StarRow(filled: stars, size: 76)
                        .accessibilityLabel("\(stars) of 3 stars")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(child.parentLabel.uppercased()) SAYS")
                        .font(TonightFont.child(14))
                        .foregroundStyle(TonightColor.grape)
                    Text(praise.text ?? praise.presetPhrase ?? "")
                        .font(TonightFont.child(28))
                        .environment(\.locale, Locale(identifier: praise.lang))
                    Button(action: onHear) {
                        Image(systemName: "speaker.wave.2.fill")
                            .frame(width: CGFloat(TonightSize.tapChild), height: CGFloat(TonightSize.tapChild))
                    }
                    .buttonStyle(RoundToyButtonStyle(fill: TonightColor.sky, edge: TonightColor.skyEdge, diameter: CGFloat(TonightSize.tapChild)))
                    .accessibilityLabel("Hear it")
                    .accessibilityIdentifier("praise.hear")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 22).fill(TonightColor.white))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(TonightColor.grapeEdge, lineWidth: 4))
                ChandaView(mood: .success, size: 76)
                Button("Thank you!", action: onThanks)
                    .buttonStyle(ToyButtonStyle(fill: TonightColor.mint, edge: TonightColor.mintEdge, minHeight: CGFloat(TonightSize.tapChildLg)))
                    .accessibilityIdentifier("praise.thanks")
                Spacer()
            }
            .padding(20)
        }
    }

    private var subjectName: String {
        SubjectCatalog.record(task.subjectID)?.displayName() ?? task.subjectID
    }

    private var headline: String {
        if markVisible {
            return "\(child.parentLabel) checked your \(subjectName.lowercased())!"
        }
        return "\(child.parentLabel) looked at your \(subjectName.lowercased())!"
    }
}

#Preview("Parent checks") {
    ParentChecksChildScreen(
        child: ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: true, parentLabel: "Mummy"),
        task: mathsTask(),
        gate: GateModel(fixed: true),
        onShow: {},
        onLater: {},
        onKey: { _ in },
        onCloseGate: {}
    )
}

#Preview("Parent result") {
    ParentResultScreen(
        child: ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: true, parentLabel: "Mummy"),
        task: englishTask(),
        mark: TodayCopy.sampleMark(),
        praise: PraiseDraft(),
        onBack: {},
        onToggle: { _ in },
        onSend: {}
    )
}

#Preview("Parent check") {
    ParentCheckScreen(
        child: ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: true, parentLabel: "Mummy"),
        task: mathsTask(),
        praise: PraiseDraft(),
        onBack: {},
        onSend: {}
    )
}

#Preview("Praise shown") {
    PraiseMessageScreen(
        child: ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: true, parentLabel: "Mummy"),
        task: mathsTask(),
        praise: Praise(taskID: UUID(), presetID: "shabash", lang: "hi"),
        stars: 3,
        markVisible: true,
        onHear: {},
        onThanks: {}
    )
}

#Preview("Praise hidden") {
    PraiseMessageScreen(
        child: ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: false, parentLabel: "Mummy"),
        task: mathsTask(),
        praise: Praise(taskID: UUID(), presetID: "shabash", lang: "hi"),
        stars: 3,
        markVisible: false,
        onHear: {},
        onThanks: {}
    )
}

private func mathsTask() -> HomeworkTask {
    HomeworkTask(
        id: UUID(),
        childID: UUID(),
        subjectID: "maths",
        schoolClass: "1",
        instruction: "Sums on page 14",
        checkMode: .parent,
        confirmedText: nil,
        pagePhotoRefs: [PhotoRef(relativePath: "pages/maths.jpg")],
        media: [],
        showMarkOverride: nil,
        stars: nil,
        createdAt: Date()
    )
}

private func englishTask() -> HomeworkTask {
    HomeworkTask(
        id: UUID(),
        childID: UUID(),
        subjectID: "english",
        schoolClass: "1",
        instruction: "Read page 12",
        checkMode: .auto,
        confirmedText: TodayCopy.passage,
        pagePhotoRefs: [],
        media: [],
        showMarkOverride: nil,
        stars: nil,
        createdAt: Date()
    )
}
