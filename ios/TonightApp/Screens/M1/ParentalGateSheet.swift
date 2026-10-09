import DesignSystem
import ProfilesKit
import SwiftUI

/// M1-05. A 3-digit number in words. Not a PIN, not stored, and not timed.
struct ParentalGateSheet: View {
    @Bindable var gate: GateModel
    var childName: String
    var onKey: @MainActor (String) -> Void
    var onClose: @MainActor () -> Void

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "empty", "0", "delete"]

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Grown-ups only")
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pXs), weight: .bold))
                        .foregroundStyle(TonightColor.pInkSoft)
                        .textCase(.uppercase)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .frame(width: 48, height: 48)
                    }
                    .accessibilityLabel("Cancel, back to \(childName)")
                    .accessibilityIdentifier("gate.close")
                }
                Text("Type this number:")
                    .font(TonightFont.child(CGFloat(TonightType.Text.cLabel)))
                    .frame(maxWidth: .infinity)
                Text(gate.challenge.prompt)
                    .font(TonightFont.child(CGFloat(TonightType.Text.cTitle)))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(gate.challenge.prompt)
                    .accessibilityIdentifier("gate.prompt")
                HStack(spacing: 8) {
                    ForEach(0..<GateModel.digitCount, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(TonightColor.pAccent, lineWidth: 1.5)
                            .frame(width: 52, height: 58)
                            .background(RoundedRectangle(cornerRadius: 12).fill(TonightColor.white))
                            .overlay {
                                Text(digit(at: index))
                                    .font(TonightFont.child(28))
                            }
                    }
                }
                .frame(maxWidth: .infinity)
                if !gate.notice.isEmpty {
                    Text(gate.notice)
                        .font(TonightFont.parent(CGFloat(TonightType.Text.pBase), weight: .semibold))
                        .foregroundStyle(TonightColor.pWarnInk)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("gate.notice")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(keys, id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
            .padding(20)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: CGFloat(TonightRadius.xl),
                    topTrailingRadius: CGFloat(TonightRadius.xl)
                )
                .fill(TonightColor.pBg)
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .background(TonightColor.ink.opacity(0.28).ignoresSafeArea())
        .accessibilityIdentifier("gate.sheet")
    }

    private func digit(at index: Int) -> String {
        let digits = Array(gate.answer)
        guard digits.indices.contains(index) else { return "" }
        return String(digits[index])
    }

    @ViewBuilder
    private func keyButton(_ key: String) -> some View {
        if key == "empty" {
            Color.clear.frame(height: 56)
        } else {
            let label = key == "delete" ? "Delete" : key
            Button(action: { onKey(key) }) {
                Group {
                    if key == "delete" {
                        Image(systemName: "delete.left")
                    } else {
                        Text(key)
                    }
                }
                .font(TonightFont.child(24))
                .foregroundStyle(TonightColor.ink)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(TonightColor.white)
                )
            }
            .disabled(gate.isLocked)
            .accessibilityLabel(label)
            .accessibilityIdentifier(key == "delete" ? "gate.key.delete" : "gate.key.\(key)")
        }
    }
}

#Preview("Gate") {
    ZStack {
        ToyRoomBackground()
        ParentalGateSheet(gate: GateModel.preview(answer: "16"), childName: "Aarav", onKey: { _ in }, onClose: {})
    }
}

#Preview("Gate locked") {
    ParentalGateSheet(gate: GateModel.previewLocked(), childName: "Aarav", onKey: { _ in }, onClose: {})
}
