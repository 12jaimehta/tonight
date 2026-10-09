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

    /// The parent looked at the notebook and awarded stars. Nil when the star count is outside 0...3.
    public static func parent(stars: Int) -> Mark? {
        guard HomeworkRules.starScale.contains(stars) else { return nil }
        return Mark(
            strategyID: "parent-stars",
            source: .parent,
            locale: "und",
            correct: stars,
            total: HomeworkRules.starScale.upperBound,
            percent: nil,
            words: [],
            missed: []
        )
    }
}
