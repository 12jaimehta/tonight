import DesignSystem
import PaywallKit
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
            case .parentArea:
                ParentAreaView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            model.backgrounded()
        }
    }
}

struct ParentAreaView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Parent area")
                .font(TonightFont.child(CGFloat(TonightType.Text.pHero)))
                .foregroundStyle(TonightColor.ink)
                .accessibilityIdentifier("parent.area")
            Text("A grown-up unlocked Tonight.")
            Text(TonightComposition.speechFlags.sarvamEnabled ? "Server speech is on." : "Server speech is off.")
            Text(PaywallAccess.canPresent(flag: PaywallFlags(), parentUnlocked: true) ? "Purchases are on." : "Purchases are off.")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ParentRoomBackground())
    }
}
