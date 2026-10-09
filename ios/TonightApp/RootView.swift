import DesignSystem
import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = TonightModel()

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
                    ChildModeEntry(
                        child: child,
                        gate: model.gate,
                        onLock: model.openGate,
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
                    onSettings: model.openGate,
                    onOpenTask: { model.today.selectedTaskID = $0 },
                    onRetry: { model.today.phase = .ready },
                    onKey: model.pressGate,
                    onCloseGate: model.closeGate
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
                        onBack: model.backFromReview,
                        onSaveLater: { model.saveDraft(handOff: false) },
                        onSaveHand: { model.saveDraft(handOff: true) }
                    )
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            model.backgrounded()
        }
    }
}

