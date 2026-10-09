import Foundation

public struct PraisePreset: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var phrase: String
    public var lang: String

    public init(id: String, phrase: String, lang: String) {
        self.id = id
        self.phrase = phrase
        self.lang = lang
    }
}

public enum PraisePresets {
    public static let v1: [PraisePreset] = [
        PraisePreset(id: "super-reading", phrase: "Super reading!", lang: "en"),
        PraisePreset(id: "shabash", phrase: "शाबाश!", lang: "hi"),
        PraisePreset(id: "proud", phrase: "So proud of you", lang: "en"),
    ]

    public static func phrase(id: String) -> String? {
        v1.first { $0.id == id }?.phrase
    }
}

/// A preset phrase plus optional text. There is no voice note and no audio field.
public struct Praise: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var taskID: UUID
    public var attemptID: UUID?
    public var presetID: String
    public var text: String?
    public var lang: String
    public var sentAt: Date
    public var seenAt: Date?

    public init(
        id: UUID = UUID(),
        taskID: UUID,
        attemptID: UUID? = nil,
        presetID: String,
        text: String? = nil,
        lang: String,
        sentAt: Date = Date(),
        seenAt: Date? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.attemptID = attemptID
        self.presetID = presetID
        self.text = text
        self.lang = lang
        self.sentAt = sentAt
        self.seenAt = seenAt
    }

    public var presetPhrase: String? {
        PraisePresets.phrase(id: presetID)
    }
}
