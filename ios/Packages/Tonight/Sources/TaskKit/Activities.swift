import Foundation
import MarkingKit

public enum V1ActivityKind {
    public static let readAloud = "read_aloud"
    public static let notebook = "notebook"
}

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

/// A reading attempt. `inputMode` is spoken or typed. Paste and OCR are not attempts.
public struct ActivityAttempt: Hashable, Sendable {
    public var expectedText: String
    public var heardText: String
    public var written: WrittenAnswer?
    public var objective: ObjectiveItem?
    public var inputMode: InputMode

    public init(
        expectedText: String = "",
        heardText: String = "",
        written: WrittenAnswer? = nil,
        objective: ObjectiveItem? = nil,
        inputMode: InputMode = .spoken
    ) {
        self.expectedText = expectedText
        self.heardText = heardText
        self.written = written
        self.objective = objective
        self.inputMode = inputMode
    }

    public func readingSample(percent: Int?) -> ReadingSample? {
        ReadingHistory.sample(inputMode: inputMode, percent: percent)
    }
}

public protocol Activity: Sendable {
    var kind: String { get }
    func score(attempt: ActivityAttempt) -> Mark
}

public struct ReadAloudActivity: Activity {
    public let kind = V1ActivityKind.readAloud
    /// The child read-aloud screen does not offer a keyboard.
    public static let offersKeyboard = false
    public init() {}

    public func score(attempt: ActivityAttempt) -> Mark {
        Marker().mark(expected: attempt.expectedText, heard: attempt.heardText, options: MarkerOptions(locale: "en-IN"))
    }
}

/// Notebook photo for a non-English subject. The parent checks it. v1 does not auto-mark it.
public struct NotebookActivity: Activity {
    public let kind = V1ActivityKind.notebook
    public init() {}

    public func score(attempt: ActivityAttempt) -> Mark {
        Mark.notScored(strategyID: "parent-check", source: .parent, locale: "und")
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

    /// English read-aloud and notebook photo. Typed Short Answer is not in v1.
    public static func v1() -> ActivityRegistry {
        ActivityRegistry(activities: [
            V1ActivityKind.readAloud: ReadAloudActivity(),
            V1ActivityKind.notebook: NotebookActivity(),
        ])
    }

    public static func v1Kind(subjectID: String) -> String {
        subjectID == HomeworkRules.autoSubjectID ? V1ActivityKind.readAloud : V1ActivityKind.notebook
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
