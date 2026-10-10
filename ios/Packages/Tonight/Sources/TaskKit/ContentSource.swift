import Foundation

/// Where the confirmed passage comes from. Template is reserved and not built.
public enum ContentSourceKind: String, Codable, Hashable, Sendable, CaseIterable {
    case photo
    case paste
    case template
}

/// A task can be created from a photo, pasted text, or a later template.
public protocol TaskContentSource: Sendable {
    var kind: ContentSourceKind { get }
    func confirmedText() -> String
}

/// Confirmed OCR, including a parent edit of those lines.
public struct PhotoContentSource: TaskContentSource {
    public var kind: ContentSourceKind { .photo }
    public var ocrText: String

    public init(ocrText: String) {
        self.ocrText = ocrText
    }

    public func confirmedText() -> String { ocrText }
}

/// Text the parent pasted. This is the passage, not a typed child attempt.
public struct PasteContentSource: TaskContentSource {
    public var kind: ContentSourceKind { .paste }
    public var pastedText: String

    public init(pastedText: String) {
        self.pastedText = pastedText
    }

    public func confirmedText() -> String { pastedText }
}

public enum TaskContent {
    /// Photo and paste supply the confirmed passage. Template is accepted and returns nothing.
    public static func confirmedPassage(from source: any TaskContentSource) -> String? {
        switch source.kind {
        case .photo, .paste:
            let text = source.confirmedText().trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        case .template:
            return nil
        }
    }

    public static func isParentSupplied(_ kind: ContentSourceKind) -> Bool {
        switch kind {
        case .photo, .paste:
            return true
        case .template:
            return false
        }
    }

    /// Passage supply never records a typed child attempt.
    public static func recordsTypedAttempt(_ kind: ContentSourceKind) -> Bool {
        switch kind {
        case .photo, .paste, .template:
            return false
        }
    }
}
