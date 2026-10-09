import DesignSystem
import ProfilesKit
import SwiftUI
import TaskKit

/// M2-02. One subject. English can be read aloud. Every other subject is a notebook.
struct NewTaskScreen: View {
    var child: ChildProfile
    @Bindable var draft: NewTaskModel
    var onClose: @MainActor () -> Void
    var onNext: @MainActor () -> Void

    private var subjects: [SubjectRecord] {
        child.visibleSubjectIDs.compactMap { SubjectCatalog.record($0) }
    }

    var body: some View {
        ZStack {
            ParentRoomBackground()
            VStack(spacing: 0) {
                DraftHeader(title: "New task for \(child.nickname)", close: "xmark", action: onClose)
                StepperBar(index: 0)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ParentSectionLabel("Subject")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(subjects) { subject in
                                subjectTile(subject)
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Subject")
                        ParentSectionLabel("What should \(child.nickname) do?")
                        if draft.offersReadAloud {
                            activityCard(
                                title: "Read aloud",
                                detail: "\(child.nickname) reads the page to Tonight, which counts the words read correctly.",
                                symbol: "mic",
                                mode: .auto
                            )
                        }
                        activityCard(
                            title: "Do it in the notebook",
                            detail: "\(child.nickname) takes a photo of the finished work, and you check it.",
                            symbol: "pencil",
                            mode: .parent
                        )
                        if !draft.subjectID.isEmpty && !draft.offersReadAloud {
                            let name = SubjectCatalog.record(draft.subjectID)?.nameEn ?? "this subject"
                            Text("Tonight can only mark English reading for now. You'll check \(name) yourself; it takes about a minute.")
                                .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
                                .foregroundStyle(TonightColor.pWarnInk)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12).fill(TonightColor.pWarnSoft))
                                .accessibilityIdentifier("task.notice")
                        }
                        Text("Instruction (\(child.nickname) hears this)")
                            .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .bold))
                        TextField("Instruction", text: instructionBinding)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: 12).fill(TonightColor.white))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(TonightColor.pLine, lineWidth: 1))
                            .accessibilityIdentifier("task.instruction")
                    }
                    .padding(24)
                }
                Button(action: onNext) {
                    Text("Next: add the page")
                }
                .buttonStyle(ParentWideButtonStyle(fill: TonightColor.pAccent, foreground: TonightColor.pAccentInk))
                .disabled(!draft.canLeaveActivity)
                .opacity(draft.canLeaveActivity ? 1 : 0.45)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .accessibilityIdentifier("task.next")
            }
        }
    }

    private var instructionBinding: Binding<String> {
        Binding(
            get: { draft.instruction },
            set: {
                draft.instruction = $0
                draft.instructionEdited = true
            }
        )
    }

    private func subjectTile(_ subject: SubjectRecord) -> some View {
        let selected = draft.subjectID == subject.id
        let soft = TonightColor.hex(TonightSubjects.record(subject.id)?.soft ?? TonightPalette.pBg)
        let accent = TonightColor.hex(TonightSubjects.record(subject.id)?.accent ?? TonightPalette.pAccent)
        return Button(action: { draft.selectSubject(subject.id) }) {
            VStack(spacing: 6) {
                SubjectBadge(subjectID: subject.id, size: 48)
                Text(subject.displayName())
                    .font(TonightFont.parent(14, weight: .bold))
                    .foregroundStyle(TonightColor.ink)
                    .environment(\.locale, Locale(identifier: subject.lang))
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 16).fill(selected ? soft : TonightColor.white))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? accent : TonightColor.pLine, lineWidth: selected ? 2 : 1))
        }
        .accessibilityLabel(subject.nameEn)
        .accessibilityIdentifier("task.subject.\(subject.id)")
        .selectedTrait(selected)
    }

    private func activityCard(title: String, detail: String, symbol: String, mode: CheckMode) -> some View {
        let selected = draft.checkMode == mode && !draft.subjectID.isEmpty
        return Button(action: { draft.selectMode(mode) }) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .frame(width: 28)
                    .foregroundStyle(TonightColor.pAccent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .bold))
                        .foregroundStyle(TonightColor.ink)
                    Text(detail)
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
                        .foregroundStyle(TonightColor.pInkSoft)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? TonightColor.pAccent : TonightColor.pLine)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? TonightColor.grapeSoft : TonightColor.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? TonightColor.pAccent : TonightColor.pLine, lineWidth: selected ? 2 : 1)
            )
        }
        .accessibilityIdentifier(mode == .auto ? "task.activity.auto" : "task.activity.parent")
        .accessibilityHint(detail)
        .selectedTrait(selected)
    }
}

struct DraftHeader: View {
    var title: String
    var close: String
    var action: @MainActor () -> Void

    var body: some View {
        HStack {
            Button(action: action) {
                Image(systemName: close)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel(close == "xmark" ? "Close" : "Back")
            .accessibilityIdentifier("task.back")
            Spacer()
            Text(title)
                .font(TonightFont.child(20))
                .multilineTextAlignment(.center)
            Spacer()
            Color.clear.frame(width: 48, height: 48)
        }
        .padding(.horizontal, 8)
    }
}

struct StepperBar: View {
    var index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { step in
                Capsule()
                    .fill(step <= index ? TonightColor.pAccent : TonightColor.pLine)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 24)
        .accessibilityLabel("Step \(index + 1) of 3")
    }
}

#Preview("English") {
    let child = ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: true, parentLabel: "Mummy")
    NewTaskScreen(child: child, draft: NewTaskModel.previewEnglish(), onClose: {}, onNext: {})
}

#Preview("Maths") {
    let child = ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: true, parentLabel: "Mummy")
    NewTaskScreen(child: child, draft: NewTaskModel.previewMaths(), onClose: {}, onNext: {})
}

#Preview("No subject") {
    let child = ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: true, parentLabel: "Mummy")
    NewTaskScreen(child: child, draft: NewTaskModel(), onClose: {}, onNext: {})
}
