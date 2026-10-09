import SwiftUI

extension View {
    @ViewBuilder
    func selectedTrait(_ selected: Bool) -> some View {
        if selected {
            accessibilityAddTraits(.isSelected)
        } else {
            self
        }
    }
}
