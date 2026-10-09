import Foundation
import MarkingKit

/// The child's photo of notebook work. Non-English subjects wait for a parent check.
public struct NotebookAttempt: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var taskID: UUID
    public var at: Date
    public var workPhotoRef: PhotoRef

    public init(id: UUID = UUID(), taskID: UUID, at: Date = Date(), workPhotoRef: PhotoRef) {
        self.id = id
        self.taskID = taskID
        self.at = at
        self.workPhotoRef = workPhotoRef
    }
}

/// The parent looked at the notebook photo and awarded stars.
public struct ParentCheck: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var attemptID: UUID
    public var stars: Int
    public var checkedAt: Date

    public init?(id: UUID = UUID(), attemptID: UUID, stars: Int, checkedAt: Date = Date()) {
        guard let stars = NotebookStars.count(picked: stars) else { return nil }
        self.id = id
        self.attemptID = attemptID
        self.stars = stars
        self.checkedAt = checkedAt
    }
}
