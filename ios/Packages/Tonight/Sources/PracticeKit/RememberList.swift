import Foundation
import MarkingKit

/// A missed word kept for practice. Two different correct days clear it.
public struct RememberEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var childID: UUID
    public var word: String
    public var subjectID: String
    public var createdAt: Date
    /// Calendar-day keys (`yyyy-MM-dd`). The same day does not count twice.
    public var correctDays: [String]
    public var clearedAt: Date?

    public init(
        id: UUID,
        childID: UUID,
        word: String,
        subjectID: String,
        createdAt: Date,
        correctDays: [String] = [],
        clearedAt: Date? = nil
    ) {
        self.id = id
        self.childID = childID
        self.word = word
        self.subjectID = subjectID
        self.createdAt = createdAt
        self.correctDays = correctDays
        self.clearedAt = clearedAt
    }

    public var isCleared: Bool { clearedAt != nil }
}

public enum RememberRules {
    public static let correctDaysToClear = 2
    public static let warmupCap = 5
}

public enum RememberDay {
    public static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    public static func key(for date: Date, calendar: Calendar = RememberDay.utc) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

public struct RememberList: Codable, Equatable, Sendable {
    public private(set) var entries: [RememberEntry]

    public init(entries: [RememberEntry] = []) {
        self.entries = entries
    }

    /// Adds the word unless this child already has it on the active list.
    @discardableResult
    public mutating func add(
        childID: UUID,
        word: String,
        subjectID: String,
        at date: Date,
        id: UUID = UUID()
    ) -> RememberEntry? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = entries.first(where: { $0.childID == childID && $0.word == trimmed && !$0.isCleared }) {
            return existing
        }
        let entry = RememberEntry(id: id, childID: childID, word: trimmed, subjectID: subjectID, createdAt: date)
        entries.append(entry)
        return entry
    }

    /// One correct spoken day is recorded. A second, different day clears the word.
    /// A typed reading is not a correct read, so it does not move auto-clear. `add` can still save a word by hand.
    @discardableResult
    public mutating func recordCorrect(
        id: UUID,
        day: String,
        at date: Date,
        inputMode: InputMode = .spoken
    ) -> RememberEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        guard inputMode == .spoken else { return entries[index] }
        guard !entries[index].isCleared else { return entries[index] }
        if !entries[index].correctDays.contains(day) {
            entries[index].correctDays.append(day)
        }
        if entries[index].correctDays.count >= RememberRules.correctDaysToClear {
            entries[index].clearedAt = date
        }
        return entries[index]
    }

    public func active(childID: UUID? = nil) -> [RememberEntry] {
        entries
            .filter { !$0.isCleared && (childID == nil || $0.childID == childID) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// The oldest active words, at most `RememberRules.warmupCap`.
    public func warmup(childID: UUID? = nil) -> [RememberEntry] {
        Array(active(childID: childID).prefix(RememberRules.warmupCap))
    }
}
