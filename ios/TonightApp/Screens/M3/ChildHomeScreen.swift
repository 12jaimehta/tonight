import DesignSystem
import ProfilesKit
import SwiftUI
import TaskKit

/// M3-01 Child home. The lock is the only way out, and it opens the parental gate.
struct ChildHomeScreen: View {
    var child: ChildProfile
    var today: TodayModel
    var gate: GateModel
    var onLock: @MainActor () -> Void
    var onPlay: @MainActor (HomeworkTask) -> Void
    var onPraise: @MainActor (Praise) -> Void
    var onKey: @MainActor (String) -> Void
    var onCloseGate: @MainActor () -> Void

    private var board: ChildHomeBoard {
        ChildHomeBoard(child: child, tasks: today.tasks, statuses: today.statuses, praises: today.praises)
    }

    var body: some View {
        ZStack {
            ToyRoomBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let praise = board.unseenPraise {
                        praiseCard(praise)
                            .accessibilitySortPriority(4)
                    }
                    banner
                        .accessibilitySortPriority(3)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(board.cards) { card in
                            subjectCard(card)
                        }
                    }
                    .accessibilitySortPriority(2)
                }
                .padding(20)
            }
            if gate.presented {
                ParentalGateSheet(gate: gate, childName: child.nickname, onKey: onKey, onClose: onCloseGate)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: AvatarSymbol.name(for: child.avatarID))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(TonightColor.ink)
                .frame(width: 56, height: 56)
                .background(Circle().fill(AvatarSymbol.color(for: child.avatarID)))
                .accessibilityHidden(true)
            Text("Hi \(child.nickname)!")
                .font(TonightFont.child(CGFloat(TonightType.Text.cTitle)))
                .foregroundStyle(TonightColor.ink)
            Spacer()
            Button(action: onLock) {
                Image(systemName: "lock")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(TonightColor.ink)
                    .frame(width: CGFloat(TonightSize.tapChild), height: CGFloat(TonightSize.tapChild))
                    .background(Circle().fill(TonightColor.white.opacity(0.72)))
            }
            .accessibilityLabel("Grown-ups only: exit")
            .accessibilityIdentifier("child.lock")
            .accessibilitySortPriority(1)
        }
    }

    private var banner: some View {
        Group {
            if board.allDone {
                allDoneBanner
            } else if let task = board.nextTask {
                nextBanner(task)
            } else if board.awaitingTask != nil {
                waitingBanner
            } else {
                restingBanner
            }
        }
    }

    private func nextBanner(_ task: HomeworkTask) -> some View {
        let name = subjectTitle(task.subjectID)
        let activity = task.checkMode == .auto ? "Read aloud" : "Notebook"
        return HStack(spacing: 12) {
            SubjectBadge(subjectID: task.subjectID, size: 72)
            VStack(alignment: .leading, spacing: 2) {
                Text("Next stop")
                    .font(TonightFont.child(14))
                    .foregroundStyle(TonightColor.ink.opacity(0.7))
                Text(name)
                    .font(TonightFont.child(CGFloat(TonightType.Text.cBody)))
                Text(activity)
                    .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
            }
            Spacer(minLength: 0)
            Button(action: { onPlay(task) }) {
                Image(systemName: "play.fill")
                    .font(.system(size: 28, weight: .bold))
            }
            .buttonStyle(RoundToyButtonStyle(fill: TonightColor.sun, edge: TonightColor.sunEdge, diameter: CGFloat(TonightSize.tapChildLg)))
            .accessibilityLabel("Next stop: \(SubjectCatalog.record(task.subjectID)?.nameEn ?? name), \(activity). Start.")
            .accessibilityIdentifier("child.play")
        }
        .padding(14)
        .background(bannerShape(task.subjectID))
    }

    private var allDoneBanner: some View {
        HStack(spacing: 12) {
            ChandaView(mood: .success, size: 76)
            Text("All done for tonight!")
                .font(TonightFont.child(CGFloat(TonightType.Text.cBody)))
                .foregroundStyle(TonightColor.ink)
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(TonightColor.white))
    }

    private var waitingBanner: some View {
        HStack(spacing: 12) {
            ChandaView(mood: .idle, size: 76)
            Text("A grown-up checks your work.")
                .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
                .foregroundStyle(TonightColor.ink)
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(TonightColor.white))
    }

    private var restingBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ChandaView(mood: .idle, size: 76)
                Text(board.openCount == 0 ? "Nothing for tonight." : "\(board.openCount) things tonight!")
                    .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
                    .foregroundStyle(TonightColor.ink)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(TonightColor.white))
    }

    private func praiseCard(_ praise: Praise) -> some View {
        Button(action: { onPraise(praise) }) {
            HStack {
                Text("\(child.parentLabel) checked your work · You got a message!")
                    .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
                    .foregroundStyle(TonightColor.ink)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(TonightColor.grapeSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(TonightColor.grapeEdge, lineWidth: 3)
            )
        }
        .accessibilityIdentifier("child.praise")
    }

    private func subjectCard(_ card: ChildHomeBoard.Card) -> some View {
        let record = SubjectCatalog.record(card.subject.subjectID)
        let title = card.subject.displayName ?? record?.displayName() ?? card.subject.subjectID
        let edge = TonightColor.hex(TonightSubjects.record(card.subject.subjectID)?.edge ?? TonightPalette.ink)
        let border = card.isNext ? TonightColor.sunEdge : edge
        return Button(action: { if let task = card.task, card.state != .resting { onPlay(task) } }) {
            VStack(spacing: 8) {
                SubjectBadge(subjectID: card.subject.subjectID, size: 72)
                    .opacity(card.state == .resting ? 0.45 : 1)
                Text(title)
                    .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
                    .foregroundStyle(TonightColor.ink)
                    .opacity(card.state == .resting ? 0.55 : 1)
                    .accessibilityLanguage(record?.lang ?? "en")
                    .environment(\.layoutDirection, record?.dir == .rtl ? .rightToLeft : .leftToRight)
                chip(card.state)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(TonightColor.white))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(border, lineWidth: card.isNext ? 4 : 3))
        }
        .disabled(card.task == nil || card.state == .resting || card.state == .done || card.state == .checked)
        .accessibilityLabel("\(title), \(chipText(card.state))")
        .accessibilityIdentifier("subject.\(card.subject.subjectID)")
    }

    private func chip(_ state: ChildCardState) -> some View {
        let text = chipText(state)
        return Text(text)
            .font(TonightFont.child(16))
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(Capsule().fill(chipFill(state)))
            .foregroundStyle(TonightColor.ink)
    }

    private func chipText(_ state: ChildCardState) -> String {
        switch state {
        case .todo(let count, _): return "\(count) to do"
        case .done: return "Done"
        case .awaitingCheck: return "Grown-up checks"
        case .checked: return "Checked"
        case .resting: return "Nothing tonight"
        }
    }

    private func chipFill(_ state: ChildCardState) -> Color {
        switch state {
        case .todo: return TonightColor.sun.opacity(0.35)
        case .done, .checked: return TonightColor.mint.opacity(0.35)
        case .awaitingCheck: return TonightColor.grapeSoft
        case .resting: return TonightColor.cream
        }
    }

    private func subjectTitle(_ id: String) -> String {
        child.subjects.first { $0.subjectID == id }?.displayName
            ?? SubjectCatalog.record(id)?.displayName()
            ?? id
    }

    private func bannerShape(_ subjectID: String) -> some View {
        let bg = TonightColor.hex(TonightSubjects.record(subjectID)?.bg ?? TonightPalette.sun)
        let edge = TonightColor.hex(TonightSubjects.record(subjectID)?.edge ?? TonightPalette.sunEdge)
        return RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(bg)
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(edge)
                    .frame(height: 10)
            }
    }
}

#Preview("Child home") {
    ChildHomeSample()
}

private struct ChildHomeSample: View {
    var body: some View {
        let today = TodayModel.previewPopulated()
        let child = today.selected ?? ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: true, parentLabel: "Mummy")
        ChildHomeScreen(
            child: child,
            today: today,
            gate: GateModel(fixed: true),
            onLock: {},
            onPlay: { _ in },
            onPraise: { _ in },
            onKey: { _ in },
            onCloseGate: {}
        )
    }
}
