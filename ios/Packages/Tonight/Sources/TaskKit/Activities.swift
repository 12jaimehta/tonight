import Foundation
import MarkingKit

/// A later class 4–5 activity can carry a written answer. v1 does not present this.
public struct WrittenAnswer: Codable, Hashable, Sendable {
    public var prompt: String
    public var text: String

    public init(prompt: String, text: String) {
        self.prompt = prompt
        self.text = text
    }
}

/// A later objective item. v1 does not present this.
public struct ObjectiveItem: Codable, Hashable, Sendable {
    public var prompt: String
    public var choiceID: String

    public init(prompt: String, choiceID: String) {
        self.prompt = prompt
        self.choiceID = choiceID
    }
}

public struct ActivityAttempt: Hashable, Sendable {
    public var expectedText: String
    public var heardText: String
    public var written: WrittenAnswer?
    public var objective: ObjectiveItem?

    public init(
        expectedText: String = "",
        heardText: String = "",
        written: WrittenAnswer? = nil,
        objective: ObjectiveItem? = nil
    ) {
        self.expectedText = expectedText
        self.heardText = heardText
        self.written = written
        self.objective = objective
    }
}

public protocol Activity: Sendable {
    var kind: String { get }
    func score(attempt: ActivityAttempt) -> Mark
}

public struct ReadAloudActivity: Activity {
    public let kind = "read_aloud"
    public init() {}

    public func score(attempt: ActivityAttempt) -> Mark {
        Marker().mark(expected: attempt.expectedText, heard: attempt.heardText, options: MarkerOptions(locale: "en-IN"))
    }
}

public struct ShortAnswerActivity: Activity {
    public let kind = "short_answer"
    public init() {}

    public func score(attempt: ActivityAttempt) -> Mark {
        Marker().mark(expected: attempt.expectedText, heard: attempt.heardText, options: MarkerOptions(locale: "en-IN"))
    }
}

public protocol LessonMediaProvider: Sendable {
    func media(for taskID: UUID) -> [MediaRef]
}

/// v1 registers no media provider. Animation can attach here later.
public struct NoLessonMedia: LessonMediaProvider {
    public init() {}
    public func media(for taskID: UUID) -> [MediaRef] { [] }
}

public struct ActivityRegistry: Sendable {
    private var activities: [String: any Activity]

    public init(activities: [String: any Activity]) {
        self.activities = activities
    }

    public static func v1() -> ActivityRegistry {
        ActivityRegistry(activities: [
            "read_aloud": ReadAloudActivity(),
            "short_answer": ShortAnswerActivity(),
        ])
    }

    public func activity(kind: String) -> (any Activity)? {
        activities[kind]
    }

    public func registering(_ activity: any Activity) -> ActivityRegistry {
        var copy = self
        copy.activities[activity.kind] = activity
        return copy
    }

    public var kinds: [String] {
        activities.keys.sorted()
    }
}
