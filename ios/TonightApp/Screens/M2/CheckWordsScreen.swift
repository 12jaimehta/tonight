import DesignSystem
import ProfilesKit
import SwiftUI

/// M2-04. "Looks right" stays off until the included text is non-empty.
struct CheckWordsScreen: View {
    var child: ChildProfile
    @Bindable var draft: NewTaskModel
    var onBack: @MainActor () -> Void
    var onConfirm: @MainActor () -> Void
    var onMakeNotebook: @MainActor () -> Void

    var body: some View {
        ZStack {
            ParentRoomBackground()
            VStack(spacing: 0) {
                DraftHeader(title: "Check the words", close: "chevron.left", action: onBack)
                StepperBar(index: 2)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(draft.instruction.isEmpty ? "Untick anything \(child.nickname) shouldn't read. Tap the pencil to fix a word." : draft.instruction)
                            .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .semibold))
                        Text("Untick anything \(child.nickname) shouldn't read. Tap the pencil to fix a word.")
                            .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
                            .foregroundStyle(TonightColor.pInkSoft)
                        if draft.noEnglish && draft.lines.isEmpty {
                            Text("We couldn't find English words on this page. If it's a Hindi page, make this a Notebook task instead. Otherwise, type the lines \(child.nickname) should read.")
                                .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
                                .foregroundStyle(TonightColor.pWarnInk)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12).fill(TonightColor.pWarnSoft))
                                .accessibilityIdentifier("task.noEnglish")
                            Button("Make it a Notebook task", action: onMakeNotebook)
                                .frame(minHeight: 48)
                                .accessibilityIdentifier("task.makeNotebook")
                        }
                        if draft.lines.isEmpty || draft.manualFallback {
                            TextField("Type the lines", text: $draft.manualText, axis: .vertical)
                                .lineLimit(4...8)
                                .padding(12)
                                .frame(minHeight: 120, alignment: .topLeading)
                                .background(RoundedRectangle(cornerRadius: 12).fill(TonightColor.white))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(TonightColor.pLine, lineWidth: 1))
                                .accessibilityIdentifier("task.manual")
                        }
                        ParentCard {
                            VStack(spacing: 0) {
                                ForEach(draft.lines) { line in
                                    lineRow(line)
                                }
                            }
                        }
                        Text("\(draft.wordCount) words will be read · dotted = Tonight wasn't sure")
                            .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
                            .foregroundStyle(TonightColor.pInkSoft)
                            .accessibilityIdentifier("task.wordCount")
                    }
                    .padding(24)
                }
                Button(action: onConfirm) {
                    Text("Looks right")
                }
                .buttonStyle(ParentWideButtonStyle(fill: TonightColor.pAccent, foreground: TonightColor.pAccentInk))
                .disabled(!draft.canConfirmWords)
                .opacity(draft.canConfirmWords ? 1 : 0.45)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .accessibilityIdentifier("task.looksRight")
            }
        }
    }

    private func lineRow(_ line: DraftLine) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: { toggle(line.id) }) {
                Image(systemName: line.included ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(line.included ? TonightColor.pAccent : TonightColor.pInkSoft)
                    .frame(width: 48, height: 52)
            }
            .accessibilityIdentifier("task.line.\(line.id)")
            .accessibilityLabel(line.included ? "Included. \(line.text). Double-tap to exclude." : "Excluded. \(line.text).")
            if line.editing {
                TextField("Word", text: textBinding(line.id))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("task.line.edit.\(line.id)")
            } else {
                Text(line.text)
                    .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .semibold))
                    .strikethrough(!line.included)
                    .foregroundStyle(line.included ? TonightColor.ink : TonightColor.pInkSoft)
                    .underline(line.uncertain, pattern: .dot, color: TonightColor.pWarnInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: { beginEdit(line.id) }) {
                Image(systemName: "pencil")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Edit")
            .accessibilityIdentifier("task.pencil.\(line.id)")
        }
    }

    private func toggle(_ id: Int) {
        guard let index = draft.lines.firstIndex(where: { $0.id == id }) else { return }
        draft.lines[index].included.toggle()
    }

    private func beginEdit(_ id: Int) {
        guard let index = draft.lines.firstIndex(where: { $0.id == id }) else { return }
        draft.lines[index].editing.toggle()
    }

    private func textBinding(_ id: Int) -> Binding<String> {
        Binding(
            get: { draft.lines.first { $0.id == id }?.text ?? "" },
            set: { newValue in
                guard let index = draft.lines.firstIndex(where: { $0.id == id }) else { return }
                draft.lines[index].text = newValue
            }
        )
    }
}

#Preview("Words") {
    CheckWordsScreen(
        child: ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: true, parentLabel: "Mummy"),
        draft: NewTaskModel.previewEnglish(),
        onBack: {},
        onConfirm: {},
        onMakeNotebook: {}
    )
}

#Preview("No English") {
    CheckWordsScreen(
        child: ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: true, parentLabel: "Mummy"),
        draft: NewTaskModel.previewNoEnglish(),
        onBack: {},
        onConfirm: {},
        onMakeNotebook: {}
    )
}
