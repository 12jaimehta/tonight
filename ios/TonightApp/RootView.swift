import DesignSystem
import PaywallKit
import ProfilesKit
import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var gate = ParentalGateSession()
    @State private var showingParent = false
    @State private var unlocked = false
    @State private var answer = ""
    @State private var notice = ""

    private var fixedGate: Bool {
        ProcessInfo.processInfo.arguments.contains("-TonightFixedGate")
    }

    private var challenge: GateChallenge {
        ParentalGateBank.challenge(fixed: fixedGate)
    }

    var body: some View {
        Group {
            if showingParent && unlocked {
                ParentAreaView()
            } else if showingParent {
                GateView(
                    challenge: challenge,
                    answer: $answer,
                    notice: notice,
                    onSubmit: submit,
                    onClose: closeParent
                )
            } else {
                ChildHomeView(onParent: { showingParent = true })
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            gate.resetForBackground()
            unlocked = false
            showingParent = false
            answer = ""
            notice = ""
        }
    }

    private func submit() {
        switch gate.submit(answer: answer, to: challenge, now: Date()) {
        case .unlocked:
            unlocked = true
            notice = ""
        case .incorrect(let remaining):
            notice = "Try again. \(remaining) left."
        case .locked:
            notice = "Locked for a minute."
        }
    }

    private func closeParent() {
        showingParent = false
        answer = ""
        notice = ""
    }
}

struct ChildHomeView: View {
    var onParent: () -> Void

    private var subjects: [SubjectRecord] {
        SubjectCatalog.defaults(for: AudienceConfig.v1.classes[0])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StaticCopyBlock(title: "Tonight", lines: [classLine, ageLine])
                ForEach(subjects) { subject in
                    StaticSubjectChip(
                        title: subject.displayName(),
                        palette: SubjectPalette.from(hue: Double(subject.hue))
                    )
                    .accessibilityIdentifier("subject.\(subject.id)")
                }
                Button("Parent", action: onParent)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("parent.button")
            }
            .padding(24)
        }
    }

    private var classLine: String {
        let classes = AudienceConfig.v1.classes
        return "Classes \(classes.first ?? "")–\(classes.last ?? "")"
    }

    private var ageLine: String {
        let audience = AudienceConfig.v1
        return "Ages \(audience.ageMin)–\(audience.ageMax)"
    }
}

struct GateView: View {
    var challenge: GateChallenge
    @Binding var answer: String
    var notice: String
    var onSubmit: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StaticCopyBlock(title: "Parents", lines: ["A grown-up answers this."])
            Text(challenge.prompt)
                .font(.largeTitle)
                .accessibilityIdentifier("gate.prompt")
            TextField("Answer", text: $answer)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("gate.answer")
                .onSubmit(onSubmit)
            Button("Unlock", action: onSubmit)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("gate.unlock")
            if !notice.isEmpty {
                Text(notice)
                    .accessibilityIdentifier("gate.notice")
            }
            Button("Back", action: onClose)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ParentAreaView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Parent area")
                .font(.largeTitle)
                .accessibilityIdentifier("parent.area")
            Text("Adult consent is a stub until the consent screen is designed.")
            Text(TonightComposition.speechFlags.sarvamEnabled ? "Server speech is on." : "Server speech is off.")
            Text(PaywallAccess.canPresent(flag: PaywallFlags(), parentUnlocked: true) ? "Purchases are on." : "Purchases are off.")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
