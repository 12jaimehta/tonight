import Foundation
import MarkingKit

public enum CheckModeMarking {
    /// English reading. The mark is the count of words read correctly.
    public static func auto(expected: String, heard: String) -> Mark {
        Marker().mark(
            expected: expected,
            heard: heard,
            options: MarkerOptions(locale: "en-IN", asrEngine: "apple_on_device")
        )
    }

    /// The parent looked at the notebook and awarded stars. Nil unless the count is 1, 2, or 3.
    public static func parent(stars: Int) -> Mark? {
        guard let stars = NotebookStars.count(picked: stars) else { return nil }
        return Mark(
            strategyID: "parent-stars",
            source: .parent,
            locale: "und",
            correct: stars,
            total: StarScale.maximum,
            percent: nil,
            words: [],
            missed: []
        )
    }
}
