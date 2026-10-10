import Foundation

/// How the child produced an English reading attempt.
/// Paste and confirmed OCR are parent-supplied passage text, not a value of this enum.
public enum InputMode: String, Codable, Hashable, Sendable {
    case spoken
    case typed
}

public enum ReadingAttemptLabel {
    /// Shown on the parent result when the child typed the reading.
    public static let typedNotReadAloud = "Typed, not read aloud"
}
