import DesignSystem
import ProfilesKit
import SwiftUI

/// M1-04. Rename, hide, and reorder. Hiding the last visible subject is blocked.
struct SubjectsScreen: View {
    @Bindable var editor: SubjectsEditor
    var onBack: @MainActor () -> Void
    var onDone: @MainActor () -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            ParentRoomBackground()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ParentSectionLabel("On \(editor.child.nickname)'s homework screen")
                        ParentCard {
                            VStack(spacing: 0) {
                                ForEach(editor.ordered) { row in
                                    subjectRow(row)
                                    if row.id != editor.ordered.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                        Text(editor.orderLabel)
                            .font(TonightFont.parent(1))
                            .foregroundStyle(TonightColor.pBg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("subject.order")
                            .accessibilityLabel(editor.orderLabel)
                        if !editor.notice.isEmpty {
                            Text(editor.notice)
                                .font(TonightFont.parent(CGFloat(TonightType.Text.pSm), weight: .semibold))
                                .foregroundStyle(TonightColor.pWarnInk)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12).fill(TonightColor.pWarnSoft))
                                .accessibilityIdentifier("subject.notice")
                        }
                        ParentSectionLabel("Add more (optional)")
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(editor.visibleOptionalIDs, id: \.self) { id in
                                optionalTile(id)
                            }
                        }
                        Button(editor.showAllOptional ? "Show fewer subjects" : "See all 16 optional subjects") {
                            editor.showAllOptional.toggle()
                        }
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("subject.all")
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
                Button(action: onDone) {
                    Text("Done")
                }
                .buttonStyle(ParentWideButtonStyle(fill: TonightColor.pAccent, foreground: TonightColor.pAccentInk))
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .accessibilityIdentifier("subject.done")
            }
            if editor.renamingID != nil {
                renameSheet
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("Back")
            Spacer()
            Text("\(editor.child.nickname)'s subjects")
                .font(TonightFont.child(22))
            Spacer()
            Color.clear.frame(width: 48, height: 48)
        }
        .padding(.horizontal, 12)
    }

    private func subjectRow(_ row: ChildSubject) -> some View {
        let record = SubjectCatalog.record(row.subjectID)
        let title = row.displayName ?? record?.displayName() ?? row.subjectID
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                SubjectBadge(subjectID: row.subjectID, size: 40)
                    .opacity(row.hidden ? 0.4 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .bold))
                        .foregroundStyle(TonightColor.ink)
                        .opacity(row.hidden ? 0.4 : 1)
                        .environment(\.layoutDirection, record?.dir == .rtl ? .rightToLeft : .leftToRight)
                        .accessibilityLanguage(record?.lang ?? "en")
                    Text(subtitle(row, record: record))
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pXs)))
                        .foregroundStyle(TonightColor.pInkSoft)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                rowAction("Move up", "arrow.up", "subject.up.\(row.subjectID)", "Move \(record?.nameEn ?? row.subjectID) up") {
                    editor.move(row.subjectID, by: -1)
                }
                rowAction("Move down", "arrow.down", "subject.down.\(row.subjectID)", "Move \(record?.nameEn ?? row.subjectID) down") {
                    editor.move(row.subjectID, by: 1)
                }
                rowAction("Rename", "pencil", "subject.rename.\(row.subjectID)", "Rename \(record?.nameEn ?? row.subjectID)") {
                    editor.beginRename(row.subjectID)
                }
                rowAction(row.hidden ? "Show" : "Hide", row.hidden ? "eye.slash" : "eye", "subject.hide.\(row.subjectID)", "Show \(record?.nameEn ?? row.subjectID) to child: \(row.hidden ? "off" : "on")") {
                    editor.toggleHidden(row.subjectID)
                }
            }
        }
        .frame(minHeight: 60)
        .accessibilityIdentifier("subject.row.\(row.subjectID)")
    }

    private func rowAction(_ title: String, _ symbol: String, _ identifier: String, _ label: String, action: @MainActor @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                Text(title)
                    .font(TonightFont.parent(11, weight: .bold))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func subtitle(_ row: ChildSubject, record: SubjectRecord?) -> String {
        if row.displayName != nil {
            return "\(record?.nameEn ?? row.subjectID) · renamed by you"
        }
        if !SubjectCatalog.classDefaultIDs.contains(row.subjectID) {
            return "Optional · added by you"
        }
        if let record, record.lang != "en" {
            return "\(record.nameEn) · default"
        }
        let schoolClass = editor.child.schoolClass ?? "1"
        return "Default for class \(schoolClass)"
    }

    private func optionalTile(_ id: String) -> some View {
        let selected = editor.child.subjects.contains { $0.subjectID == id }
        let record = SubjectCatalog.record(id)
        let soft = TonightColor.hex(TonightSubjects.record(id)?.soft ?? TonightPalette.pBg)
        let accent = TonightColor.hex(TonightSubjects.record(id)?.accent ?? TonightPalette.pAccent)
        return Button(action: { editor.toggleOptional(id) }) {
            VStack(spacing: 6) {
                SubjectBadge(subjectID: id, size: 40)
                Text(record?.displayName() ?? id)
                    .font(TonightFont.parent(14, weight: .bold))
                    .foregroundStyle(TonightColor.ink)
                    .lineLimit(1)
                    .environment(\.layoutDirection, record?.dir == .rtl ? .rightToLeft : .leftToRight)
                    .accessibilityLanguage(record?.lang ?? "en")
                if let record, record.lang != "en" {
                    Text(record.nameEn)
                        .font(TonightFont.parent(11))
                        .foregroundStyle(TonightColor.pInkSoft)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? soft : TonightColor.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? accent : TonightColor.pLine, lineWidth: selected ? 2 : 1)
            )
            .overlay(alignment: .topLeading) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(accent)
                        .padding(6)
                }
            }
        }
        .accessibilityLabel(record?.nameEn ?? id)
        .accessibilityIdentifier("subject.tile.\(id)")
        .selectedTrait(selected)
    }

    private var renameSheet: some View {
        let id = editor.renamingID ?? ""
        let record = SubjectCatalog.record(id)
        return ZStack {
            TonightColor.ink.opacity(0.35).ignoresSafeArea()
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SubjectBadge(subjectID: id, size: 48)
                        Text("Rename \(record?.nameEn ?? "subject")")
                            .font(TonightFont.child(22))
                        Spacer()
                    }
                    Text("Use the name \(editor.child.nickname)'s school uses.")
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
                        .foregroundStyle(TonightColor.pInkSoft)
                    Text("Name \(editor.child.nickname) sees")
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pSm), weight: .bold))
                    TextField("Name", text: $editor.renameText)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 12).stroke(TonightColor.pAccent, lineWidth: 2))
                        .accessibilityIdentifier("subject.rename.field")
                    suggestionChips(record)
                    Text("Maximum 16 characters. The colour and icon stay the same, so \(editor.child.nickname) still recognises it.")
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pXs)))
                        .foregroundStyle(TonightColor.pInkSoft)
                    HStack {
                        Button("Reset") { editor.resetRename() }
                            .frame(minHeight: 48)
                            .accessibilityIdentifier("subject.rename.reset")
                        Spacer()
                        Button("Save") { editor.saveRename() }
                            .font(TonightFont.parent(16, weight: .bold))
                            .frame(minWidth: 88, minHeight: 48)
                            .accessibilityIdentifier("subject.rename.save")
                    }
                }
                .padding(20)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: CGFloat(TonightRadius.xl), topTrailingRadius: CGFloat(TonightRadius.xl))
                        .fill(TonightColor.pBg)
                        .ignoresSafeArea(edges: .bottom)
                )
            }
        }
        .accessibilityIdentifier("subject.rename.sheet")
    }

    private func suggestionChips(_ record: SubjectRecord?) -> some View {
        let suggestions = renameSuggestions(record)
        return HStack(spacing: 8) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button(suggestion) { editor.renameText = suggestion }
                    .font(TonightFont.parent(14, weight: .semibold))
                    .frame(minHeight: 44)
                    .padding(.horizontal, 12)
                    .background(Capsule().fill(TonightColor.white))
                    .overlay(Capsule().stroke(TonightColor.pLine, lineWidth: 1))
            }
        }
    }

    private func renameSuggestions(_ record: SubjectRecord?) -> [String] {
        guard let record else { return [] }
        if record.id == "evs" {
            return [record.nameEn, "Our World", "पर्यावरण"]
        }
        if record.lang == "en" {
            return [record.nameEn]
        }
        return [record.nameEn, record.nameNative]
    }
}

#Preview("Subjects") {
    SubjectsScreen(editor: SubjectsEditor.preview(), onBack: {}, onDone: {})
}

#Preview("Rename EVS") {
    SubjectsScreen(editor: SubjectsEditor.previewRename(), onBack: {}, onDone: {})
}
