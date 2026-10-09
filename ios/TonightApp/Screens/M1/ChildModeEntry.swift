import DesignSystem
import ProfilesKit
import SwiftUI

/// Child-mode backdrop for the parental gate. M3 replaces the body with the full home.
struct ChildModeEntry: View {
    var child: ChildProfile
    var gate: GateModel
    var onLock: @MainActor () -> Void
    var onKey: @MainActor (String) -> Void
    var onCloseGate: @MainActor () -> Void

    var body: some View {
        ZStack {
            ToyRoomBackground()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    avatar
                    Text("Hi \(child.nickname)!")
                        .font(TonightFont.child(CGFloat(TonightType.Text.cTitle)))
                        .foregroundStyle(TonightColor.ink)
                    Spacer()
                    Button(action: onLock) {
                        Image(systemName: "lock")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(TonightColor.ink)
                            .frame(width: CGFloat(TonightSize.tapChild), height: CGFloat(TonightSize.tapChild))
                            .background(Circle().fill(TonightColor.white.opacity(0.7)))
                    }
                    .accessibilityLabel("Grown-ups only: exit")
                    .accessibilityIdentifier("child.lock")
                }
                Text("Tonight")
                    .font(TonightFont.child(CGFloat(TonightType.Text.cBody)))
                    .foregroundStyle(TonightColor.inkSoft)
                ForEach(visibleSubjects) { subject in
                    HStack(spacing: 12) {
                        SubjectBadge(subjectID: subject.id, size: 48)
                        Text(subject.displayName())
                            .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
                            .foregroundStyle(TonightColor.ink)
                            .accessibilityLanguage(subject.lang)
                    }
                    .accessibilityIdentifier("subject.\(subject.id)")
                }
                Spacer()
            }
            .padding(24)
            if gate.presented {
                ParentalGateSheet(gate: gate, childName: child.nickname, onKey: onKey, onClose: onCloseGate)
            }
        }
    }

    private var visibleSubjects: [SubjectRecord] {
        child.visibleSubjectIDs.compactMap { SubjectCatalog.record($0) }
    }

    private var avatar: some View {
        Image(systemName: AvatarSymbol.name(for: child.avatarID))
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(TonightColor.ink)
            .frame(width: 56, height: 56)
            .background(Circle().fill(AvatarSymbol.color(for: child.avatarID)))
            .accessibilityHidden(true)
    }
}

#Preview("Child entry") {
    ChildModeEntry(
        child: ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: true, parentLabel: "Mummy"),
        gate: GateModel(fixed: true),
        onLock: {},
        onKey: { _ in },
        onCloseGate: {}
    )
}
