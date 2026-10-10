import Foundation
import PracticeKit
import SwiftData

/// Deletes this child's Remember words and homework marks from the app store.
/// `RememberList.removeAll` is the same rule the practice list uses.
public enum ChildWithdrawalErase {
    public static func erase(childID: UUID, in context: ModelContext) throws {
        let remembers = try context.fetch(FetchDescriptor<TonightSchemaV1.StoredRemember>())
        var practice = RememberList(entries: remembers.filter { $0.childID == childID }.map { $0.entry() })
        practice.removeAll(childID: childID)
        let kept = Set(practice.entries.map(\.id))
        for row in remembers where row.childID == childID && !kept.contains(row.id) {
            context.delete(row)
        }

        let homework = try context.fetch(FetchDescriptor<TonightSchemaV1.StoredHomework>())
        let taskIDs = Set(homework.filter { $0.childID == childID }.map(\.id))
        for row in homework where row.childID == childID {
            row.stars = nil
        }

        let notebooks = try context.fetch(FetchDescriptor<TonightSchemaV1.StoredNotebook>())
        let attemptIDs = Set(notebooks.filter { taskIDs.contains($0.taskID) }.map(\.id))
        let checks = try context.fetch(FetchDescriptor<TonightSchemaV1.StoredParentCheck>())
        for row in checks where attemptIDs.contains(row.attemptID) {
            context.delete(row)
        }
        try context.save()
    }
}
