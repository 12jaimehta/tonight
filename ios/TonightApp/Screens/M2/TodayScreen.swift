import DesignSystem
import ProfilesKit
import SwiftUI
import TaskKit

/// M2-01 Today. Empty, loading, and error are states of the same screen.
struct TodayScreen: View {
    @Bindable var today: TodayModel
    var gate: GateModel
    var onHandPhone: @MainActor () -> Void
    var onNewTask: @MainActor () -> Void
    var onSettings: @MainActor () -> Void
    var onOpenTask: @MainActor (UUID) -> Void
    var onRetry: @MainActor () -> Void
    var onKey: @MainActor (String) -> Void
    var onCloseGate: @MainActor () -> Void
    var showingWithdrawal: Bool = false
    var confirmingWithdrawal: Bool = false
    var withdrawalNotice: String = ""
    var withdrawalHasConsent: Bool = true
    var onAskWithdrawal: @MainActor () -> Void = {}
    var onConfirmWithdrawal: @MainActor () -> Void = {}
    var onCancelWithdrawal: @MainActor () -> Void = {}

    var body: some View {
        ZStack {
            ParentRoomBackground()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        topBar
                        if let child = today.selected {
                            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                                .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
                                .foregroundStyle(TonightColor.pInkSoft)
                            Text("Tonight for \(child.nickname)")
                                .font(TonightFont.child(CGFloat(TonightType.Text.pHero)))
                                .foregroundStyle(TonightColor.ink)
                            Button(action: onHandPhone) {
                                Label("Hand phone to \(child.nickname)", systemImage: "hand.raised.fill")
                            }
                            .buttonStyle(ToyButtonStyle(fill: TonightColor.sun, edge: TonightColor.sunEdge, minHeight: 54))
                            .accessibilityIdentifier("today.hand")
                            content(for: child)
                            weekLine
                        }
                    }
                    .padding(24)
                }
                tabBar
            }
            .overlay(alignment: .bottomTrailing) {
                newTaskButton
            }
            if gate.presented {
                ParentalGateSheet(
                    gate: gate,
                    childName: today.selected?.nickname ?? "your child",
                    onKey: onKey,
                    onClose: onCloseGate
                )
            }
            if showingWithdrawal && !gate.presented {
                WithdrawConsentSheet(
                    confirming: confirmingWithdrawal,
                    notice: withdrawalNotice,
                    hasConsent: withdrawalHasConsent,
                    onAsk: onAskWithdrawal,
                    onConfirm: onConfirmWithdrawal,
                    onCancel: onCancelWithdrawal
                )
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(today.children) { child in
                        Button(action: { today.selectedID = child.id }) {
                            HStack(spacing: 6) {
                                Image(systemName: AvatarSymbol.name(for: child.avatarID))
                                Text(child.nickname)
                                    .font(TonightFont.parent(16, weight: .bold))
                            }
                            .padding(.horizontal, 10)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(today.selectedID == child.id ? TonightColor.grapeSoft : TonightColor.white))
                        }
                        .accessibilityIdentifier("today.child.\(child.nickname)")
                        .selectedTrait(today.selectedID == child.id)
                    }
                }
            }
            Spacer(minLength: 0)
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("today.settings")
        }
    }

    @ViewBuilder
    private func content(for child: ChildProfile) -> some View {
        switch today.phase {
        case .loading:
            VStack(spacing: 12) {
                skeleton
                skeleton
                skeleton
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading tonight's homework")
        case .failed:
            Text("Couldn't load. Pull to try again.")
                .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .semibold))
                .foregroundStyle(TonightColor.pWarnInk)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(TonightColor.pWarnSoft))
                .accessibilityIdentifier("today.error")
            Button("Try again", action: onRetry)
                .frame(minHeight: 48)
                .accessibilityIdentifier("today.retry")
        case .empty:
            emptyState(child)
        case .ready:
            if today.visibleTasks.isEmpty {
                emptyState(child)
            } else {
                ForEach(today.groups(), id: \.subjectID) { group in
                    subjectGroup(group.subjectID, tasks: group.tasks, child: child)
                }
            }
        }
    }

    private func emptyState(_ child: ChildProfile) -> some View {
        VStack(spacing: 12) {
            ChandaView(mood: .idle, size: 104)
            Text("Nothing added for tonight")
                .font(TonightFont.child(CGFloat(TonightType.Text.pTitle)))
            Button("New task", action: onNewTask)
                .buttonStyle(ParentWideButtonStyle(fill: TonightColor.pAccent, foreground: TonightColor.pAccentInk))
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("today.empty")
    }

    private var skeleton: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(TonightColor.pLine)
            .frame(height: 72)
    }

    private func subjectGroup(_ subjectID: String, tasks: [HomeworkTask], child: ChildProfile) -> some View {
        let row = child.subjects.first { $0.subjectID == subjectID }
        let record = SubjectCatalog.record(subjectID)
        let title = row?.displayName ?? record?.displayName() ?? subjectID
        let soft = TonightColor.hex(TonightSubjects.record(subjectID)?.soft ?? TonightPalette.pBg)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SubjectBadge(subjectID: subjectID, size: 32)
                Text(title)
                    .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .bold))
                if row?.displayName != nil, let english = record?.nameEn {
                    Text(english)
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pXs)))
                        .foregroundStyle(TonightColor.pInkSoft)
                }
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(soft)
            .accessibilityAddTraits(.isHeader)
            ForEach(tasks) { task in
                taskRow(task, child: child)
            }
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(TonightColor.white))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func taskRow(_ task: HomeworkTask, child: ChildProfile) -> some View {
        let state = today.statuses[task.id] ?? .todo
        let record = SubjectCatalog.record(task.subjectID)
        return Button(action: { onOpenTask(task.id) }) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.instruction)
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .bold))
                        .foregroundStyle(TonightColor.ink)
                        .multilineTextAlignment(.leading)
                    Text(detail(task))
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pXs)))
                        .foregroundStyle(TonightColor.pInkSoft)
                }
                Spacer(minLength: 0)
                statusView(state, task: task)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        }
        .accessibilityLabel(rowLabel(task, state: state, subject: record?.nameEn ?? task.subjectID))
        .accessibilityIdentifier("today.task.\(task.subjectID)")
    }

    @ViewBuilder
    private func statusView(_ state: TodayTaskState, task: HomeworkTask) -> some View {
        switch state {
        case .todo:
            pill("To do", fill: TonightColor.pLine.opacity(0.6), ink: TonightColor.pInkSoft)
        case .reading:
            pill("Reading now", fill: TonightColor.pWarnSoft, ink: TonightColor.pWarnInk)
        case .marked(let correct, let total):
            pill("\(correct) of \(total)", fill: TonightColor.pSuccessSoft, ink: TonightColor.pSuccess, icon: "checkmark")
        case .awaitingCheck:
            Text("Check")
                .font(TonightFont.parent(16, weight: .bold))
                .foregroundStyle(TonightColor.pAccentInk)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Capsule().fill(TonightColor.grape))
                .accessibilityIdentifier("today.check.\(task.subjectID)")
        case .checked(let stars):
            VStack(alignment: .trailing, spacing: 2) {
                pill("Checked", fill: TonightColor.pSuccessSoft, ink: TonightColor.pSuccess)
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { index in
                        Image(systemName: index < stars ? "star.fill" : "star")
                            .foregroundStyle(index < stars ? TonightColor.star : TonightColor.starEmpty)
                    }
                }
            }
        }
    }

    private func pill(_ title: String, fill: Color, ink: Color, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
            }
            Text(title)
        }
        .font(TonightFont.parent(14, weight: .bold))
        .foregroundStyle(ink)
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(Capsule().fill(fill))
    }

    private func detail(_ task: HomeworkTask) -> String {
        switch task.checkMode {
        case .auto:
            let count = (task.confirmedText ?? "").split { $0.isWhitespace || $0.isNewline }.count
            return "Read aloud · \(count) words"
        case .parent:
            if today.statuses[task.id] == .awaitingCheck {
                return "Notebook · photo sent"
            }
            return "Notebook"
        }
    }

    private func rowLabel(_ task: HomeworkTask, state: TodayTaskState, subject: String) -> String {
        var label = "\(subject). \(task.instruction). \(detail(task))."
        switch state {
        case .todo: label += " To do."
        case .reading: label += " Reading now."
        case .marked(let correct, let total): label += " Marked \(correct) of \(total)."
        case .awaitingCheck: label += " Check."
        case .checked(let stars): label += " Checked. \(stars) stars."
        }
        return label
    }

    private var weekLine: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("This week")
                    .font(TonightFont.parent(CGFloat(TonightType.Text.pXs)))
                    .foregroundStyle(TonightColor.pInkSoft)
                Text("\(today.weekCount) tasks done")
                    .font(TonightFont.parent(CGFloat(TonightType.Text.pLg), weight: .bold))
            }
            Spacer()
            Button("See all") {}
                .font(TonightFont.parent(16, weight: .bold))
                .frame(minHeight: 44)
                .accessibilityIdentifier("today.seeAll")
        }
    }

    private var tabBar: some View {
        HStack {
            tab("Today", "calendar", enabled: true, selected: true)
            tab("Remember", "bookmark", enabled: false, selected: false)
            tab("History", "chart.bar", enabled: false, selected: false)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(TonightColor.white)
    }

    private func tab(_ title: String, _ symbol: String, enabled: Bool, selected: Bool) -> some View {
        Button(action: {}) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                Text(title)
                    .font(TonightFont.parent(12, weight: .bold))
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(selected ? TonightColor.pAccent : TonightColor.pInkSoft.opacity(enabled ? 1 : 0.45))
        }
        .disabled(!enabled)
        .accessibilityLabel(enabled ? title : "\(title), coming later")
        .accessibilityIdentifier("today.tab.\(title)")
    }

    private var newTaskButton: some View {
        Button(action: onNewTask) {
            Label("New task", systemImage: "plus")
                .font(TonightFont.parent(16, weight: .bold))
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
        }
        .buttonStyle(ParentWideButtonStyle(fill: TonightColor.pAccent, foreground: TonightColor.pAccentInk))
        .fixedSize(horizontal: true, vertical: false)
        .padding(.trailing, 20)
        .padding(.bottom, 64)
        .accessibilityIdentifier("today.newTask")
    }
}

#Preview("Today") {
    TodayScreen(
        today: TodayModel.previewPopulated(),
        gate: GateModel(fixed: true),
        onHandPhone: {},
        onNewTask: {},
        onSettings: {},
        onOpenTask: { _ in },
        onRetry: {},
        onKey: { _ in },
        onCloseGate: {}
    )
}

#Preview("Empty") {
    TodayScreen(
        today: TodayModel.preview(phase: .empty),
        gate: GateModel(fixed: true),
        onHandPhone: {},
        onNewTask: {},
        onSettings: {},
        onOpenTask: { _ in },
        onRetry: {},
        onKey: { _ in },
        onCloseGate: {}
    )
}

#Preview("Loading") {
    TodayScreen(
        today: TodayModel.preview(phase: .loading),
        gate: GateModel(fixed: true),
        onHandPhone: {},
        onNewTask: {},
        onSettings: {},
        onOpenTask: { _ in },
        onRetry: {},
        onKey: { _ in },
        onCloseGate: {}
    )
}

#Preview("Error") {
    TodayScreen(
        today: TodayModel.preview(phase: .failed),
        gate: GateModel(fixed: true),
        onHandPhone: {},
        onNewTask: {},
        onSettings: {},
        onOpenTask: { _ in },
        onRetry: {},
        onKey: { _ in },
        onCloseGate: {}
    )
}
