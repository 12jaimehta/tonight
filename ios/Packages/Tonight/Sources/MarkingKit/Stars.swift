import Foundation

/// Star rewards. Counts come from a mark that word alignment already produced.
/// There is no streak, XP, or level.
public enum StarScale {
    public static let minimum = 1
    public static let maximum = 3
    public static let valid = 1...3
}

public enum EnglishStars {
    /// 3 at 90% or above, 2 at 60% or above, otherwise 1. Never 0.
    public static func count(percent: Int) -> Int {
        if percent >= 90 { return 3 }
        if percent >= 60 { return 2 }
        return 1
    }

    /// A typed reading is practice and caps at 1. Spoken reading keeps the percent scale.
    public static func count(percent: Int, inputMode: InputMode) -> Int {
        switch inputMode {
        case .spoken:
            return count(percent: percent)
        case .typed:
            return 1
        }
    }

    public static func count(for mark: Mark) -> Int {
        count(percent: mark.percent ?? 0)
    }

    public static func count(for mark: Mark, inputMode: InputMode) -> Int {
        count(percent: mark.percent ?? 0, inputMode: inputMode)
    }
}

public enum NotebookStars {
    /// The parent picks 1, 2, or 3. Zero is not a mark.
    public static func count(picked: Int) -> Int? {
        guard StarScale.valid.contains(picked) else { return nil }
        return picked
    }
}

/// Whether the child is allowed to see the numeric mark.
public enum MarkVisibility {
    public static func shownToChild(taskOverride: Bool?, childDefault: Bool) -> Bool {
        taskOverride ?? childDefault
    }
}

public enum AutomaticStarDisplay: Equatable, Sendable {
    case shown(Int)
    /// Hidden mark, and the parent has not reviewed the attempt yet.
    case withheldUntilParentReview
    /// The parent reviewed, but showing stars would reveal a mark that is still hidden.
    case withheldHiddenMark
}

public enum StarDisplay {
    /// Automatic stars stay hidden while the mark is hidden. A visible mark shows them immediately.
    public static func automatic(
        percent: Int,
        markVisible: Bool,
        parentReviewed: Bool,
        inputMode: InputMode = .spoken
    ) -> AutomaticStarDisplay {
        let stars = EnglishStars.count(percent: percent, inputMode: inputMode)
        if markVisible {
            return .shown(stars)
        }
        if !parentReviewed {
            return .withheldUntilParentReview
        }
        return .withheldHiddenMark
    }

    public static func automatic(
        mark: Mark,
        markVisible: Bool,
        parentReviewed: Bool,
        inputMode: InputMode = .spoken
    ) -> AutomaticStarDisplay {
        automatic(
            percent: mark.percent ?? 0,
            markVisible: markVisible,
            parentReviewed: parentReviewed,
            inputMode: inputMode
        )
    }
}
