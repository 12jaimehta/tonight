import DesignSystem
import SwiftUI

/// Parent-only withdrawal. The sheet is presented after the parental gate unlocks.
struct WithdrawConsentSheet: View {
    var confirming: Bool
    var notice: String
    var hasConsent: Bool = true
    var onAsk: @MainActor () -> Void
    var onConfirm: @MainActor () -> Void
    var onCancel: @MainActor () -> Void

    var body: some View {
        ZStack {
            TonightColor.ink.opacity(0.35).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("Withdraw consent")
                    .font(TonightFont.child(CGFloat(TonightType.Text.pTitle)))
                    .foregroundStyle(TonightColor.ink)
                Text("This clears the consent record for this child and queues deletion of their data.")
                    .font(TonightFont.parent(CGFloat(TonightType.Text.pBase)))
                    .foregroundStyle(TonightColor.pInkSoft)
                if !hasConsent {
                    Text(notice.isEmpty ? "No consent on file" : notice)
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .semibold))
                        .foregroundStyle(TonightColor.ink)
                        .accessibilityIdentifier("consent.withdraw.empty")
                } else if !notice.isEmpty {
                    Text(notice)
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .semibold))
                        .foregroundStyle(TonightColor.ink)
                        .accessibilityIdentifier("consent.withdrawn")
                }
                if hasConsent && confirming {
                    Button("Yes, withdraw", action: onConfirm)
                        .buttonStyle(ParentWideButtonStyle(fill: TonightColor.pError, foreground: TonightColor.white))
                        .accessibilityIdentifier("consent.withdraw.confirm")
                } else if hasConsent && notice.isEmpty {
                    Button("Withdraw consent", action: onAsk)
                        .buttonStyle(ParentWideButtonStyle(fill: TonightColor.pAccent, foreground: TonightColor.pAccentInk))
                        .accessibilityIdentifier("consent.withdraw")
                }
                Button("Cancel", action: onCancel)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("consent.withdraw.cancel")
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(TonightColor.white))
            .padding(24)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("consent.withdraw.sheet")
        }
    }
}
