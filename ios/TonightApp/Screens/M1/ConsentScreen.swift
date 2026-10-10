import AuthKit
import DesignSystem
import SwiftUI

/// M1-02. The legal sentence is `ConsentCopy.placeholder` until counsel supplies it.
struct ConsentScreen: View {
    @Bindable var model: ConsentModel
    var onAgree: @MainActor () -> Void

    var body: some View {
        ZStack {
            ParentRoomBackground()
            VStack(alignment: .leading, spacing: 16) {
                Text("Before we start")
                    .font(TonightFont.parent(CGFloat(TonightType.Text.pSm), weight: .bold))
                    .foregroundStyle(TonightColor.pInkSoft)
                    .frame(maxWidth: .infinity)
                Text("A grown-up sets up Tonight")
                    .font(TonightFont.child(CGFloat(TonightType.Text.pTitle)))
                    .foregroundStyle(TonightColor.ink)
                ParentCard {
                    VStack(alignment: .leading, spacing: 16) {
                        promise("checkmark.shield", "Your child's voice stays on this phone.", "Speech is turned into words on the device, then the audio is deleted.")
                        promise("camera", "Page photos stay on this phone.", "Never uploaded and never saved to your camera roll.")
                        promise("lock", "We store only your sign-in and this consent.", "You can withdraw any time in Settings, and the local record is cleared.")
                    }
                }
                Button(action: { model.toggleAccepted() }) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: model.accepted ? "checkmark.square.fill" : "square")
                            .font(.system(size: 28))
                            .foregroundStyle(model.accepted ? TonightColor.pAccent : TonightColor.pInkSoft)
                        Text(ConsentCopy.placeholder)
                            .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .semibold))
                            .foregroundStyle(TonightColor.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                }
                .accessibilityIdentifier("consent.accept")
                .accessibilityLabel(ConsentCopy.placeholder)
                .selectedTrait(model.accepted)
                Button("Read the privacy notice") {
                    model.showingPrivacy = true
                }
                .font(TonightFont.parent(CGFloat(TonightType.Text.pSm), weight: .semibold))
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("consent.privacy")
                if let error = model.error {
                    Text(error)
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
                        .foregroundStyle(TonightColor.pError)
                        .accessibilityIdentifier("consent.error")
                }
                Spacer(minLength: 8)
                Button(action: onAgree) {
                    Text(model.saving ? "I agree" : "I agree")
                }
                .buttonStyle(ParentWideButtonStyle(fill: TonightColor.pAccent, foreground: TonightColor.pAccentInk))
                .disabled(!model.canContinue)
                .opacity(model.canContinue ? 1 : 0.45)
                .accessibilityIdentifier("consent.agree")
                Text("Consent \(AdultConsentRecord.currentVersion) · we record the version, time and method")
                    .font(TonightFont.parent(CGFloat(TonightType.Text.pXs)))
                    .foregroundStyle(TonightColor.pInkSoft)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
            if model.showingPrivacy {
                privacyNotice
            }
        }
    }

    private func promise(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 28)
                .foregroundStyle(TonightColor.pAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .bold))
                    .foregroundStyle(TonightColor.ink)
                Text(detail)
                    .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
                    .foregroundStyle(TonightColor.pInkSoft)
            }
        }
    }

    private var privacyNotice: some View {
        ZStack {
            TonightColor.ink.opacity(0.35).ignoresSafeArea()
            ParentCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(ConsentCopy.placeholder)
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pLg), weight: .bold))
                    Text("The privacy notice is the same placeholder until the policy is final.")
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pBase)))
                        .foregroundStyle(TonightColor.pInkSoft)
                    Button("Close") { model.showingPrivacy = false }
                        .frame(minHeight: 48)
                }
            }
            .padding(24)
        }
        .accessibilityIdentifier("consent.privacy.sheet")
    }
}

#Preview("Consent off") {
    ConsentScreen(model: ConsentModel(), onAgree: {})
}

#Preview("Consent on") {
    ConsentScreen(model: ConsentModel.preview(accepted: true), onAgree: {})
}

#Preview("Consent error") {
    ConsentScreen(model: ConsentModel.preview(accepted: true, error: "Couldn't save. Try again."), onAgree: {})
}
