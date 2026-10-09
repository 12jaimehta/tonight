import DesignSystem
import ProfilesKit
import SwiftUI
import TaskKit

/// M3-04 Notebook. The shutter stores an in-app photo reference and does not open the camera.
struct NotebookScreen: View {
    var child: ChildProfile
    var task: HomeworkTask
    @Bindable var session: NotebookSession
    var onBack: @MainActor () -> Void
    var onSend: @MainActor () -> Void
    var onGrownUp: @MainActor () -> Void

    var body: some View {
        ZStack {
            if session.phase == .camera {
                camera
            } else {
                ToyRoomBackground()
                instructionBody
            }
        }
    }

    private var instructionBody: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .frame(width: CGFloat(TonightSize.tapChild), height: CGFloat(TonightSize.tapChild))
                }
                .accessibilityLabel("Back")
                SubjectBadge(subjectID: task.subjectID, size: 48)
                Text(subjectName)
                    .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
                Spacer()
            }
            if session.phase == .denied {
                denied
            } else if session.phase == .blurry {
                Text("Hmm, hold the phone still and try again.")
                    .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(TonightColor.white))
                Button("Take a photo") { session.phase = .camera }
                    .buttonStyle(ToyButtonStyle(fill: TonightColor.sun, edge: TonightColor.sunEdge, minHeight: 64))
            } else if session.phase == .confirm {
                confirm
            } else {
                prompt
            }
            Spacer()
        }
        .padding(16)
    }

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                ChandaView(mood: .idle, size: 76)
                Text(task.instruction)
                    .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(TonightColor.white))
            }
            if !task.pagePhotoRefs.isEmpty {
                HStack {
                    Image(systemName: "doc.text")
                    Text("Page photo")
                    Spacer()
                    Image(systemName: "speaker.wave.2.fill")
                        .frame(width: CGFloat(TonightSize.tapChild), height: CGFloat(TonightSize.tapChild))
                        .background(Circle().fill(TonightColor.sky))
                        .accessibilityLabel("Hear it")
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18).fill(TonightColor.white))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Do it in your notebook")
                Text("2. Take a photo")
                Text("3. \(child.parentLabel) checks it")
            }
            .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
            Button(action: { session.phase = .camera }) {
                Text("Done! Take a photo")
            }
            .buttonStyle(ToyButtonStyle(fill: TonightColor.sun, edge: TonightColor.sunEdge, minHeight: CGFloat(TonightSize.tapChildLg)))
            .accessibilityIdentifier("notebook.camera")
        }
    }

    private var camera: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: { session.phase = .instruction }) {
                    Image(systemName: "xmark")
                        .foregroundStyle(TonightColor.white)
                        .frame(width: CGFloat(TonightSize.tapChild), height: CGFloat(TonightSize.tapChild))
                }
                .accessibilityLabel("Close")
                Spacer()
            }
            Text("Take a photo")
                .font(TonightFont.child(CGFloat(TonightType.Text.cTitle)))
                .foregroundStyle(TonightColor.white)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(TonightColor.sun, style: StrokeStyle(lineWidth: 3, dash: [8]))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    Text("Fit your page in the box")
                        .font(TonightFont.child(18))
                        .foregroundStyle(TonightColor.ink)
                        .padding(10)
                        .background(Capsule().fill(TonightColor.white))
                }
                .accessibilityLabel("Page detected")
            Button(action: { session.shutter() }) {
                Circle().fill(TonightColor.white).frame(width: 72, height: 72)
            }
            .frame(width: 96, height: 96)
            .background(Circle().stroke(TonightColor.white, lineWidth: 4))
            .accessibilityLabel("Take photo")
            .accessibilityIdentifier("notebook.shutter")
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TonightColor.ink.ignoresSafeArea())
    }

    private var confirm: some View {
        VStack(spacing: 16) {
            Text("Can you see all your work?")
                .font(TonightFont.child(CGFloat(TonightType.Text.cTitle)))
                .multilineTextAlignment(.center)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TonightColor.mint, lineWidth: 4)
                .background(RoundedRectangle(cornerRadius: 20).fill(TonightColor.white))
                .frame(height: 280)
                .overlay {
                    VStack(spacing: 8) {
                        Text("2 + 3 = 5")
                        Text("6 − 2 = 4")
                        Text("5 − 1 = 3")
                    }
                    .font(TonightFont.child(CGFloat(TonightType.Text.cBody)))
                }
                .accessibilityLabel("Photo of your notebook")
            HStack(spacing: 12) {
                Button("Again") { session.phase = .camera }
                    .buttonStyle(ToyButtonStyle(fill: TonightColor.white, edge: TonightColor.toyEdge, minHeight: CGFloat(TonightSize.tapChildLg)))
                    .accessibilityIdentifier("notebook.again")
                Button("Yes, send") { onSend() }
                    .buttonStyle(ToyButtonStyle(fill: TonightColor.mint, edge: TonightColor.mintEdge, minHeight: CGFloat(TonightSize.tapChildLg)))
                    .accessibilityIdentifier("notebook.send")
            }
        }
    }

    private var denied: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChandaView(mood: .tryAgain, size: 76)
            Text("Let's get a grown-up")
                .font(TonightFont.child(CGFloat(TonightType.Text.cTitle)))
            Text("Camera is off for Tonight. A grown-up can turn it on in Settings.")
                .font(TonightFont.parent(CGFloat(TonightType.Text.pBase)))
            Button("Get a grown-up", action: onGrownUp)
                .buttonStyle(ToyButtonStyle(fill: TonightColor.grape, edge: TonightColor.grapeEdge, foreground: TonightColor.white, minHeight: CGFloat(TonightSize.tapChildLg)))
                .accessibilityIdentifier("notebook.grownup")
        }
    }

    private var subjectName: String {
        child.subjects.first { $0.subjectID == task.subjectID }?.displayName
            ?? SubjectCatalog.record(task.subjectID)?.displayName()
            ?? task.subjectID
    }
}

#Preview("Instruction") {
    NotebookPreview(phase: .instruction)
}

#Preview("Camera") {
    NotebookPreview(phase: .camera)
}

#Preview("Confirm") {
    NotebookPreview(phase: .confirm)
}

#Preview("Camera off") {
    NotebookPreview(phase: .denied)
}

private struct NotebookPreview: View {
    var phase: NotebookPhase

    var body: some View {
        let session = NotebookSession.preview(phase)
        let task = HomeworkTask(
            id: session.taskID,
            childID: UUID(),
            subjectID: "maths",
            schoolClass: "1",
            instruction: "Do the sums on page 14 in your notebook.",
            checkMode: .parent,
            confirmedText: nil,
            pagePhotoRefs: [PhotoRef(relativePath: "pages/maths.jpg")],
            media: [],
            showMarkOverride: nil,
            stars: nil,
            createdAt: Date()
        )
        NotebookScreen(
            child: ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: true, parentLabel: "Mummy"),
            task: task,
            session: session,
            onBack: {},
            onSend: {},
            onGrownUp: {}
        )
    }
}
