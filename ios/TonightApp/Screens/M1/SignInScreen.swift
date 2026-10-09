import DesignSystem
import SwiftUI

/// M1-01 Sign in. Apple and email are placeholders: nothing leaves the phone.
struct SignInScreen: View {
    @Bindable var model: SignInModel
    var onApple: @MainActor () -> Void
    var onVerify: @MainActor () -> Void

    var body: some View {
        ZStack {
            ParentRoomBackground()
            if model.phase == .welcome {
                welcome
            } else {
                code
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)
            ChandaView(mood: .idle, size: 132)
            Text("Tonight")
                .font(TonightFont.child(CGFloat(TonightType.Text.pHero)))
                .foregroundStyle(TonightColor.ink)
            Text("Homework time, made calm.\nYour child reads, Tonight listens.")
                .font(TonightFont.parent(CGFloat(TonightType.Text.pLg), weight: .semibold))
                .foregroundStyle(TonightColor.inkSoft)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                ForEach(["english", "hindi", "maths", "evs"], id: \.self) { id in
                    SubjectBadge(subjectID: id, size: 48)
                }
            }
            .padding(.top, 8)
            .accessibilityElement(children: .contain)
            Spacer(minLength: 12)
            Button(action: onApple) {
                Label("Sign in with Apple", systemImage: "apple.logo")
            }
            .buttonStyle(ParentWideButtonStyle(fill: .black, foreground: .white))
            .accessibilityIdentifier("signin.apple")
            Button(action: { model.continueWithEmail() }) {
                Label("Continue with email", systemImage: "envelope")
            }
            .buttonStyle(ParentWideButtonStyle(fill: TonightColor.white, foreground: TonightColor.pAccent))
            .overlay(
                RoundedRectangle(cornerRadius: CGFloat(TonightRadius.lg), style: .continuous)
                    .stroke(TonightColor.pLine, lineWidth: 1)
            )
            .accessibilityIdentifier("signin.email")
            Text("For parents and guardians. Children don't need an account.")
                .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
                .foregroundStyle(TonightColor.pInkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private var code: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: { model.phase = .welcome }) {
                Image(systemName: "chevron.left")
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("Back")
            Text("Check your email")
                .font(TonightFont.child(CGFloat(TonightType.Text.pTitle)))
                .foregroundStyle(TonightColor.ink)
            Text("We sent a 6-digit code to \(model.email)")
                .font(TonightFont.parent(CGFloat(TonightType.Text.pBase)))
                .foregroundStyle(TonightColor.pInkSoft)
            codeBoxes
            Text("Resend code in 0:24")
                .font(TonightFont.parent(CGFloat(TonightType.Text.pSm), weight: .semibold))
                .foregroundStyle(TonightColor.pInkSoft)
                .frame(minHeight: 44)
            if model.offline || model.phase == .offline {
                notice(
                    "You're offline. Connect to the internet to sign in. Homework you've already added still works.",
                    fill: TonightColor.pWarnSoft,
                    ink: TonightColor.pWarnInk
                )
            }
            if model.phase == .codeError {
                notice(
                    "That code didn't work. Check the latest email.",
                    fill: TonightColor.pErrorSoft,
                    ink: TonightColor.pError
                )
            }
            Spacer()
            Button(action: onVerify) {
                HStack(spacing: 8) {
                    if model.phase == .loading {
                        ProgressView()
                    }
                    Text("Verify")
                }
            }
            .buttonStyle(ParentWideButtonStyle(fill: TonightColor.pAccent, foreground: TonightColor.pAccentInk))
            .disabled(!model.canVerify)
            .opacity(model.canVerify ? 1 : 0.45)
            .accessibilityIdentifier("signin.verify")
        }
        .padding(24)
    }

    private var codeBoxes: some View {
        ZStack {
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    let filled = index < model.digitCount
                    RoundedRectangle(cornerRadius: CGFloat(TonightRadius.md), style: .continuous)
                        .stroke(model.phase == .codeError ? TonightColor.pError : TonightColor.pAccent, lineWidth: filled ? 2 : 1)
                        .background(
                            RoundedRectangle(cornerRadius: CGFloat(TonightRadius.md), style: .continuous)
                                .fill(TonightColor.white)
                        )
                        .frame(width: 48, height: 58)
                        .overlay {
                            Text(digit(at: index))
                                .font(TonightFont.parent(22, weight: .bold))
                                .foregroundStyle(TonightColor.ink)
                        }
                }
            }
            TextField("Code", text: $model.code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(maxWidth: .infinity, minHeight: 58)
                .accessibilityIdentifier("signin.code")
                .accessibilityLabel("Code, \(model.digitCount) of 6 digits entered")
                .onChange(of: model.code) { _, _ in
                    model.clampCode()
                }
        }
        .frame(minHeight: 58)
    }

    private func digit(at index: Int) -> String {
        let digits = Array(model.code.filter(\.isNumber))
        guard digits.indices.contains(index) else { return "" }
        return String(digits[index])
    }

    private func notice(_ text: String, fill: Color, ink: Color) -> some View {
        Text(text)
            .font(TonightFont.parent(CGFloat(TonightType.Text.pSm)))
            .foregroundStyle(ink)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: CGFloat(TonightRadius.md), style: .continuous).fill(fill))
            .accessibilityIdentifier("signin.notice")
    }
}

#Preview("Welcome") {
    SignInScreen(model: SignInModel(), onApple: {}, onVerify: {})
}

#Preview("Code") {
    SignInScreen(model: SignInModel.preview(phase: .code, code: "123"), onApple: {}, onVerify: {})
}

#Preview("Code error") {
    SignInScreen(model: SignInModel.preview(phase: .codeError, code: "000000"), onApple: {}, onVerify: {})
}

#Preview("Offline") {
    SignInScreen(model: SignInModel.preview(phase: .offline, offline: true), onApple: {}, onVerify: {})
}

#Preview("Loading") {
    SignInScreen(model: SignInModel.preview(phase: .loading, code: "123456"), onApple: {}, onVerify: {})
}
