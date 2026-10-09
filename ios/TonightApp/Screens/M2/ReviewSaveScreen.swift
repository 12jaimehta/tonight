import DesignSystem
import ProfilesKit
import SwiftUI

/// M2-05. Save stays off while HomeworkRules rejects the draft.
struct ReviewSaveScreen: View {
    var child: ChildProfile
    @Bindable var draft: NewTaskModel
    var onBack: @MainActor () -> Void
    var onSaveLater: @MainActor () -> Void
    var onSaveHand: @MainActor () -> Void

    var body: some View {
        ZStack {
            ParentRoomBackground()
            VStack(spacing: 0) {
                DraftHeader(title: "Ready for \(child.nickname)", close: "chevron.left", action: onBack)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summary
                        Text("Show the mark to \(child.nickname)?")
                            .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                        HStack(spacing: 8) {
                            markSegment("Default (\(child.showMarkToChild ? "on" : "off"))", .useDefault, "task.mark.default")
                            markSegment("Show", .show, "task.mark.show")
                            markSegment("Hide", .hide, "task.mark.hide")
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Show the mark to \(child.nickname)")
                        Text("If it's hidden, \(child.nickname) sees \"All done!\" and no score or stars. You'll always see the full mark.")
                            .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
                            .foregroundStyle(TonightColor.pInkSoft)
                        if !draft.canSave && !draft.saving {
                            Text(blockReason)
                                .font(TonightFont.parent(CGFloat(TonightType.Text.pSm), weight: .semibold))
                                .foregroundStyle(TonightColor.pWarnInk)
                                .accessibilityIdentifier("task.save.blocked")
                        }
                    }
                    .padding(24)
                }
                VStack(spacing: 8) {
                    Button(action: onSaveHand) {
                        Text(draft.saving ? "Save and hand to \(child.nickname)" : "Save and hand to \(child.nickname)")
                    }
                    .buttonStyle(ToyButtonStyle(fill: TonightColor.sun, edge: TonightColor.sunEdge, minHeight: 54))
                    .disabled(!draft.canSave)
                    .opacity(draft.canSave ? 1 : 0.45)
                    .accessibilityIdentifier("task.saveHand")
                    Button(action: onSaveLater) {
                        Text("Save for later")
                    }
                    .buttonStyle(ParentWideButtonStyle(fill: TonightColor.white, foreground: TonightColor.pAccent))
                    .disabled(!draft.canSave)
                    .opacity(draft.canSave ? 1 : 0.45)
                    .accessibilityIdentifier("task.saveLater")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }

    private var blockReason: String {
        if draft.issues().contains(.autoNeedsConfirmedText) {
            return "Add the words \(child.nickname) will read before saving."
        }
        if draft.issues().contains(.parentNeedsPhoto) {
            return "Add a page photo before saving."
        }
        return "This task still needs a subject."
    }

    private var summary: some View {
        let soft = TonightColor.hex(TonightSubjects.record(draft.subjectID)?.soft ?? TonightPalette.pBg)
        let name = child.subjects.first { $0.subjectID == draft.subjectID }?.displayName
            ?? SubjectCatalog.record(draft.subjectID)?.displayName()
            ?? draft.subjectID
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if !draft.subjectID.isEmpty {
                    SubjectBadge(subjectID: draft.subjectID, size: 40)
                }
                Text(name)
                    .font(TonightFont.parent(18, weight: .bold))
            }
            if draft.pageAttached {
                RoundedRectangle(cornerRadius: 12)
                    .fill(TonightColor.white)
                    .frame(height: 72)
                    .overlay { Image(systemName: "doc.text").foregroundStyle(TonightColor.pAccent) }
                    .accessibilityLabel("Page photo")
            }
            Text(draft.instruction)
                .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .semibold))
            if draft.checkMode == .auto {
                Text(draft.confirmedText.split(separator: "\n").first.map(String.init) ?? "")
                    .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
                    .foregroundStyle(TonightColor.pInkSoft)
                Text("\(draft.wordCount) words")
                    .font(TonightFont.parent(CGFloat(TonightType.Text.pSm), weight: .bold))
            } else {
                Text("Notebook · you'll check the photo")
                    .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
                    .foregroundStyle(TonightColor.pInkSoft)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(soft))
    }

    private func markSegment(_ title: String, _ choice: MarkChoice, _ identifier: String) -> some View {
        let selected = draft.markChoice == choice
        return Button(title) { draft.markChoice = choice }
            .font(TonightFont.parent(14, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? TonightColor.white : TonightColor.pLine.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? TonightColor.pAccent : TonightColor.clear, lineWidth: 2))
            .accessibilityIdentifier(identifier)
            .selectedTrait(selected)
    }
}

#Preview("Review") {
    ReviewSaveScreen(
        child: ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: true, parentLabel: "Mummy"),
        draft: NewTaskModel.previewEnglish(),
        onBack: {},
        onSaveLater: {},
        onSaveHand: {}
    )
}

#Preview("Needs a photo") {
    ReviewSaveScreen(
        child: ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: true, parentLabel: "Mummy"),
        draft: NewTaskModel.previewMaths(),
        onBack: {},
        onSaveLater: {},
        onSaveHand: {}
    )
}
