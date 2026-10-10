import AuthKit
import DesignSystem
import SpeechKit
import SwiftUI

struct RootView: View {
    var consentCenter: ConsentCenter
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: TonightModel

    init(consentCenter: ConsentCenter, emailOTP: EmailOTPClient? = nil) {
        self.consentCenter = consentCenter
        _model = State(initialValue: TonightComposition.makeModel(consentCenter: consentCenter, emailOTP: emailOTP))
    }
    @State private var uploadStatus = ""
    @State private var speechScene = SpeechSceneController(runner: TonightSpeechScene.makeRunner())
    @State private var speechSession = SpeechSessionModel(flagOn: TonightComposition.speechFlags.sarvamEnabled)

    private var stubUpload: Bool {
        ProcessInfo.processInfo.arguments.contains("-TonightStubUpload")
    }

    var body: some View {
        Group {
            switch model.route {
            case .signIn:
                SignInScreen(model: model.signIn, onApple: model.continueFromApple, onVerify: model.verifyEmailCode)
            case .consent:
                ConsentScreen(model: model.consent, onAgree: model.agreeToConsent)
            case .addChild:
                AddChildScreen(
                    model: model.addChild,
                    childCount: model.child == nil ? 0 : 1,
                    onClose: { model.route = .consent },
                    onNext: model.continueToSubjects
                )
            case .subjects:
                if let editor = model.editor {
                    SubjectsScreen(editor: editor, onBack: { model.route = .addChild }, onDone: model.finishSubjects)
                }
            case .childHome:
                if let child = model.child {
                    ChildHomeScreen(
                        child: child,
                        today: model.today,
                        gate: model.gate,
                        onLock: { model.openGate(for: .exitChild) },
                        onPlay: model.openChildTask,
                        onPraise: { praise in
                            model.today.selectedTaskID = praise.taskID
                            model.route = .praise
                        },
                        onKey: model.pressGate,
                        onCloseGate: model.closeGate
                    )
                }
            case .today:
                TodayScreen(
                    today: model.today,
                    gate: model.gate,
                    onHandPhone: { model.route = .childHome },
                    onNewTask: model.startNewTask,
                    onSettings: { model.openGate(for: .settings) },
                    onOpenTask: model.openTask,
                    onRetry: { model.today.phase = .ready },
                    onKey: model.pressGate,
                    onCloseGate: model.closeGate,
                    showingWithdrawal: model.showingWithdrawal,
                    confirmingWithdrawal: model.confirmingWithdrawal,
                    withdrawalNotice: model.withdrawalNotice,
                    onAskWithdrawal: model.askWithdrawal,
                    onConfirmWithdrawal: { Task { @MainActor in await model.confirmWithdrawal() } },
                    onCancelWithdrawal: model.cancelWithdrawal
                )
            case .newTask:
                if let child = model.child {
                    NewTaskScreen(child: child, draft: model.draft, onClose: model.closeDraft, onNext: model.nextFromActivity)
                }
            case .addPage:
                if let child = model.child {
                    AddPageScreen(
                        child: child,
                        draft: model.draft,
                        onBack: model.backFromPage,
                        onNext: model.nextFromPage,
                        onTypeInstead: model.typeInstead
                    )
                }
            case .checkWords:
                if let child = model.child {
                    CheckWordsScreen(
                        child: child,
                        draft: model.draft,
                        onBack: model.backFromWords,
                        onConfirm: model.confirmWords,
                        onMakeNotebook: model.makeNotebook
                    )
                }
            case .review:
                if let child = model.child {
                    ReviewSaveScreen(
                        child: child,
                        draft: model.draft,
                        gate: model.gate,
                        onBack: model.backFromReview,
                        onSaveLater: { model.saveDraft(handOff: false) },
                        onSaveHand: { model.saveDraft(handOff: true) },
                        onAllowTyping: model.allowTyping,
                        onGateKey: model.pressGate,
                        onCloseGate: model.closeGate
                    )
                }
            case .readAloud:
                if let session = model.readAloud, let task = model.task(session.taskID) {
                    ReadAloudScreen(
                        session: session,
                        passage: task.confirmedText ?? "",
                        pageTitle: "Page 12",
                        onBack: { model.route = .childHome },
                        onDone: { Task { @MainActor in await model.finishReading() } },
                        onGrownUp: { model.openGate(for: .exitChild) }
                    )
                }
            case .childResult:
                if let child = model.child, let session = model.readAloud, let task = model.task(session.taskID), let mark = (session.mark ?? model.today.marks[task.id]) {
                    ChildResultScreen(
                        child: child,
                        task: task,
                        mark: mark,
                        inputMode: model.readingMode(for: task.id),
                        speech: model.speech,
                        onHome: { model.route = .childHome }
                    )
                }
            case .notebook:
                if let child = model.child, let session = model.notebook, let task = model.task(session.taskID) {
                    NotebookScreen(
                        child: child,
                        task: task,
                        session: session,
                        speech: model.speech,
                        onBack: { model.route = .childHome },
                        onSend: model.sendNotebook,
                        onGrownUp: { model.openGate(for: .exitChild) }
                    )
                }
            case .parentChecksChild:
                if let child = model.child, let task = model.parentTask {
                    ParentChecksChildScreen(
                        child: child,
                        task: task,
                        gate: model.gate,
                        onShow: { model.openGate(for: .parentCheck) },
                        onLater: { model.route = .childHome },
                        onKey: model.pressGate,
                        onCloseGate: model.closeGate
                    )
                }
            case .parentResult:
                if let child = model.child, let task = model.parentTask, let mark = model.today.marks[task.id] {
                    ParentResultScreen(
                        child: child,
                        task: task,
                        mark: mark,
                        inputMode: model.readingMode(for: task.id),
                        praise: model.praiseDraft,
                        onBack: { model.route = .today },
                        onToggle: model.setMarkShown,
                        onSend: model.sendEnglishPraise
                    )
                }
            case .parentCheck:
                if let child = model.child, let task = model.parentTask {
                    ParentCheckScreen(
                        child: child,
                        task: task,
                        praise: model.praiseDraft,
                        onBack: { model.route = .today },
                        onSend: model.sendParentCheck
                    )
                }
            case .praise:
                if let child = model.child, let task = model.parentTask, let praise = (model.today.praises.first(where: { $0.taskID == task.id && $0.seenAt == nil }) ?? model.today.praises.last(where: { $0.taskID == task.id })) {
                    PraiseMessageScreen(
                        child: child,
                        task: task,
                        praise: praise,
                        stars: model.praiseStars(for: task),
                        markVisible: model.markVisible(for: task),
                        onHear: { model.hearPraise(praise) },
                        onThanks: { model.thankPraise(praise) }
                    )
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !uploadStatus.isEmpty {
                Text(uploadStatus)
                    .accessibilityIdentifier("speech.status")
                    .padding(8)
            }
        }
        .onChange(of: speechSession) { _, session in
            Task { await speechScene.apply(session.watch) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            if stubUpload { uploadStatus = "Suspended" }
            model.speech.stop()
            Task { await speechScene.sceneDidChange(isActive: false) }
            guard phase == .background else { return }
            model.backgrounded()
        }
        .onAppear {
            refreshSpeechSession(childID: model.child?.id)
            Task { await speechScene.apply(speechSession.watch) }
            Task { await consentCenter.flush(at: Date()) }
            guard stubUpload else { return }
            uploadStatus = "Uploading"
        }
        .onChange(of: model.child?.id) { _, childID in
            refreshSpeechSession(childID: childID)
        }
        .onChange(of: model.withdrawalEpoch) { _, _ in
            refreshSpeechSession(childID: model.child?.id)
        }
    }

    /// Withdrawal, a flag turning off, or a different child each publish a new session, and `onChange` cancels the upload.
    private func refreshSpeechSession(childID: UUID?) {
        var session = speechSession
        if let childID {
            session = session.switchingChild(to: childID)
            if consentCenter.record(for: childID)?.withdrawnAt != nil || consentCenter.record(for: childID)?.scopeIsActive(.onDevice) == false {
                session = session.withdrawing()
            }
        }
        if !TonightComposition.speechFlags.sarvamEnabled {
            session = session.turningFlagOff()
        }
        speechSession = session
    }
}

