import DesignSystem
import ProfilesKit
import SwiftUI

/// M2-03. The scanner and the photo library are not opened. "From Photos" writes a JPEG into the app directory.
struct AddPageScreen: View {
    var child: ChildProfile
    @Bindable var draft: NewTaskModel
    var onBack: @MainActor () -> Void
    var onNext: @MainActor () -> Void
    var onTypeInstead: @MainActor () -> Void

    var body: some View {
        ZStack {
            ParentRoomBackground()
            VStack(spacing: 0) {
                DraftHeader(title: "Add the page", close: "chevron.left", action: onBack)
                StepperBar(index: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        pagePreview
                        if draft.cameraDenied {
                            Text("Camera is off for Tonight. Turn it on in Settings, or choose from Photos.")
                                .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
                                .foregroundStyle(TonightColor.pWarnInk)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12).fill(TonightColor.pWarnSoft))
                                .accessibilityIdentifier("task.cameraDenied")
                        }
                        HStack(spacing: 8) {
                            Button("Rescan") { draft.rescan() }
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(RoundedRectangle(cornerRadius: 12).stroke(TonightColor.pLine, lineWidth: 1))
                                .accessibilityIdentifier("task.rescan")
                            Button("From Photos") { draft.attachSamplePage() }
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(RoundedRectangle(cornerRadius: 12).stroke(TonightColor.pLine, lineWidth: 1))
                                .accessibilityIdentifier("task.fromPhotos")
                        }
                        if draft.checkMode == .auto {
                            Button("Type the text instead", action: onTypeInstead)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("task.typeInstead")
                        } else {
                            Button("Skip: no page photo", action: onNext)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("task.skipPhoto")
                        }
                    }
                    .padding(24)
                }
                Button(action: onNext) {
                    Text(draft.checkMode == .auto ? "Next: check the words" : "Next: review")
                }
                .buttonStyle(ParentWideButtonStyle(fill: TonightColor.pAccent, foreground: TonightColor.pAccentInk))
                .disabled(draft.checkMode == .auto && !draft.pageAttached && !draft.manualFallback)
                .opacity(draft.checkMode == .parent || draft.pageAttached ? 1 : 0.45)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .accessibilityIdentifier("task.next")
            }
        }
    }

    @ViewBuilder
    private var pagePreview: some View {
        if draft.pageAttached {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TonightColor.pAccent, style: StrokeStyle(lineWidth: 2, dash: [6]))
                .background(RoundedRectangle(cornerRadius: 18).fill(TonightColor.white))
                .frame(height: 280)
                .overlay {
                    VStack {
                        Image(systemName: "doc.text")
                            .font(.system(size: 40))
                            .foregroundStyle(TonightColor.pAccent)
                        Text(draft.noEnglish ? "No English words found" : "Page 12")
                            .font(TonightFont.parent(18, weight: .bold))
                    }
                }
                .accessibilityLabel("Scanned page 12")
                .accessibilityIdentifier("task.preview")
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(TonightColor.pLine.opacity(0.45))
                .frame(height: 220)
                .overlay {
                    Text("The page scanner is not open in this build. Choose a sample page from Photos, or type the text.")
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
                        .foregroundStyle(TonightColor.pInkSoft)
                        .multilineTextAlignment(.center)
                        .padding(24)
                }
                .accessibilityIdentifier("task.preview.empty")
        }
    }
}

#Preview("Not scanned") {
    AddPageScreen(
        child: ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: true, parentLabel: "Mummy"),
        draft: NewTaskModel.previewMaths(),
        onBack: {},
        onNext: {},
        onTypeInstead: {}
    )
}

#Preview("Scanned") {
    AddPageScreen(
        child: ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: true, parentLabel: "Mummy"),
        draft: NewTaskModel.previewEnglish(),
        onBack: {},
        onNext: {},
        onTypeInstead: {}
    )
}

#Preview("Camera off") {
    AddPageScreen(
        child: ProfileRules.make(nickname: "Aarav", schoolClass: "1", showMarkToChild: true, parentLabel: "Mummy"),
        draft: NewTaskModel.previewCameraOff(),
        onBack: {},
        onNext: {},
        onTypeInstead: {}
    )
}
