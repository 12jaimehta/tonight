import DesignSystem
import ProfilesKit
import SwiftUI

/// M1-03 Add a child. Class seeds the default subjects. No date of birth and no photo.
struct AddChildScreen: View {
    @Bindable var model: AddChildModel
    var childCount: Int
    var onClose: @MainActor () -> Void
    var onNext: @MainActor () -> Void

    private let parentChoices = ["Mummy", "Papa", "Nani", "Other"]

    var body: some View {
        ZStack {
            ParentRoomBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if ProfileRules.canAddChild(currentCount: childCount) {
                        form
                    } else {
                        Text("You can add up to 3 children.")
                            .font(TonightFont.parent(CGFloat(TonightType.Text.pBase)))
                            .accessibilityIdentifier("child.limit")
                    }
                }
                .padding(24)
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("Close")
            Spacer()
            Text("Add a child")
                .font(TonightFont.child(CGFloat(TonightType.Text.pLg)))
            Spacer()
            Color.clear.frame(width: 48, height: 48)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nickname")
                .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .bold))
            TextField("Nickname", text: $model.nickname)
                .textInputAutocapitalization(.words)
                .font(TonightFont.parent(18))
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: CGFloat(TonightRadius.md), style: .continuous)
                        .fill(TonightColor.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CGFloat(TonightRadius.md), style: .continuous)
                        .stroke(model.nicknameError == nil ? TonightColor.pLine : TonightColor.pError, lineWidth: 1)
                )
                .accessibilityIdentifier("child.nickname")
                .onChange(of: model.nickname) { _, _ in
                    model.touchedNickname = true
                }
            Text("This is what Tonight calls them. Don't use their full name.")
                .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
                .foregroundStyle(TonightColor.pInkSoft)
            if let error = model.nicknameError {
                Text(error)
                    .font(TonightFont.parent(CGFloat(TonightType.Text.pSm), weight: .semibold))
                    .foregroundStyle(TonightColor.pError)
                    .accessibilityIdentifier("child.error")
            }
            Text("Class")
                .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .bold))
            HStack(spacing: 8) {
                ForEach(AudienceConfig.v1.classes, id: \.self) { schoolClass in
                    Button("Class \(schoolClass)") {
                        model.schoolClass = schoolClass
                    }
                    .font(TonightFont.parent(16, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: CGFloat(TonightRadius.md), style: .continuous)
                            .fill(model.schoolClass == schoolClass ? TonightColor.white : TonightColor.pLine.opacity(0.45))
                    )
                    .accessibilityIdentifier("child.class.\(schoolClass)")
                    .selectedTrait(model.schoolClass == schoolClass)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Class")
            Text("Pick a picture")
                .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .bold))
            HStack(spacing: 10) {
                ForEach(AvatarPresets.ids, id: \.self) { avatar in
                    Button(action: { model.avatarID = avatar }) {
                        Image(systemName: AvatarSymbol.name(for: avatar))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(TonightColor.ink)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(AvatarSymbol.color(for: avatar)))
                            .overlay(Circle().stroke(TonightColor.ink, lineWidth: model.avatarID == avatar ? 3 : 0))
                    }
                    .accessibilityLabel("\(AvatarSymbol.spoken(for: avatar)), \(model.avatarID == avatar ? "selected" : "not selected")")
                    .accessibilityIdentifier("child.avatar.\(avatar)")
                }
            }
            Text("\(model.trimmedNickname.isEmpty ? "They" : model.trimmedNickname) call you")
                .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .bold))
            parentChips
            if model.parentChoice == "Other" {
                TextField("What they call you", text: $model.customParentLabel)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: CGFloat(TonightRadius.md)).fill(TonightColor.white))
                    .accessibilityIdentifier("child.parent.custom")
            }
            marksRow
            summary
            Button(action: onNext) {
                Text("Next: subjects")
            }
            .buttonStyle(ParentWideButtonStyle(fill: TonightColor.pAccent, foreground: TonightColor.pAccentInk))
            .disabled(!model.canContinue)
            .opacity(model.canContinue ? 1 : 0.45)
            .accessibilityIdentifier("child.next")
        }
    }

    private var parentChips: some View {
        HStack(spacing: 8) {
            ForEach(parentChoices, id: \.self) { choice in
                Button(choice == "Other" ? "Other…" : choice) {
                    model.parentChoice = choice
                }
                .font(TonightFont.parent(16, weight: .bold))
                .frame(minHeight: 44)
                .padding(.horizontal, 14)
                .background(
                    Capsule().fill(model.parentChoice == choice ? TonightColor.white : TonightColor.pLine.opacity(0.4))
                )
                .overlay(
                    Capsule().stroke(model.parentChoice == choice ? TonightColor.pAccent : TonightColor.pLine, lineWidth: model.parentChoice == choice ? 2 : 1)
                )
                .accessibilityIdentifier("child.parent.\(choice)")
                .selectedTrait(model.parentChoice == choice)
            }
        }
    }

    private var marksRow: some View {
        let name = model.trimmedNickname.isEmpty ? "them" : model.trimmedNickname
        return ParentCard {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show marks to \(name)")
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .bold))
                    Text("When this is off, \(name) sees \"All done!\" with no score. You can change it for any single task.")
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
                        .foregroundStyle(TonightColor.pInkSoft)
                }
                Toggle("Show marks", isOn: $model.showMarkToChild)
                    .labelsHidden()
                    .tint(TonightColor.pSuccess)
                    .frame(minWidth: 64, minHeight: 44)
                    .accessibilityIdentifier("child.marks")
            }
        }
    }

    private var summary: some View {
        let defaults = SubjectCatalog.defaults(for: model.schoolClass)
        return ParentCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Class \(model.schoolClass) subjects")
                    .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .bold))
                Text("\(defaults.map(\.nameEn).joined(separator: ", ")). You can change these next.")
                    .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
                    .foregroundStyle(TonightColor.pInkSoft)
                HStack(spacing: 6) {
                    ForEach(defaults) { subject in
                        SubjectBadge(subjectID: subject.id, size: 32)
                    }
                }
            }
        }
        .accessibilityIdentifier("child.subjects.summary")
    }
}

enum AvatarSymbol {
    static func name(for id: String) -> String {
        switch id {
        case "sun": return "sun.max.fill"
        case "moon": return "moon.fill"
        case "star": return "star.fill"
        case "leaf": return "leaf.fill"
        case "book": return "book.fill"
        default: return "circle.fill"
        }
    }

    static func spoken(for id: String) -> String {
        switch id {
        case "sun": return "Sun"
        case "moon": return "Moon"
        case "star": return "Star"
        case "leaf": return "Leaf"
        case "book": return "Book"
        default: return id
        }
    }

    static func color(for id: String) -> Color {
        switch id {
        case "sun": return TonightColor.sun
        case "moon": return TonightColor.sky
        case "star": return TonightColor.mango
        case "leaf": return TonightColor.mint
        case "book": return TonightColor.grapeSoft
        default: return TonightColor.pLine
        }
    }
}

#Preview("Add child") {
    AddChildScreen(model: AddChildModel.preview(nickname: "Aarav", schoolClass: "2"), childCount: 0, onClose: {}, onNext: {})
}

#Preview("Nickname too long") {
    AddChildScreen(
        model: AddChildModel.preview(nickname: "This nickname is far too long", touched: true),
        childCount: 0,
        onClose: {},
        onNext: {}
    )
}

#Preview("Max children") {
    AddChildScreen(model: AddChildModel(), childCount: 3, onClose: {}, onNext: {})
}
