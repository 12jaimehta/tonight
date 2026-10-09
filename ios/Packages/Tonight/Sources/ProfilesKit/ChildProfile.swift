import Foundation

public enum AvatarPresets {
    public static let ids = ["sun", "moon", "star", "leaf", "book"]
}

/// Per-child subject row: rename (`displayName`), hide, and order.
/// Seeded from the class defaults. The catalogue id never changes.
public struct ChildSubject: Codable, Hashable, Sendable, Identifiable {
    public var subjectID: String
    public var displayName: String?
    public var hidden: Bool
    public var order: Int

    public var id: String { subjectID }

    public init(subjectID: String, displayName: String? = nil, hidden: Bool = false, order: Int) {
        self.subjectID = subjectID
        self.displayName = displayName
        self.hidden = hidden
        self.order = order
    }
}

/// A child on a parent account. No date of birth and no photo of the child.
public struct ChildProfile: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var nickname: String
    public var ageBandID: String
    public var schoolClass: String?
    public var avatarID: String
    public var showMarkToChild: Bool
    /// What the child calls the parent ("Mummy", "Papa", or any other words).
    public var parentLabel: String
    public var subjects: [ChildSubject]

    public init(
        id: UUID,
        nickname: String,
        ageBandID: String,
        schoolClass: String?,
        avatarID: String,
        showMarkToChild: Bool,
        parentLabel: String,
        subjects: [ChildSubject]
    ) {
        self.id = id
        self.nickname = nickname
        self.ageBandID = ageBandID
        self.schoolClass = schoolClass
        self.avatarID = avatarID
        self.showMarkToChild = showMarkToChild
        self.parentLabel = parentLabel
        self.subjects = subjects
    }

    public var visibleSubjectIDs: [String] {
        subjects.filter { !$0.hidden }.sorted { $0.order < $1.order }.map(\.subjectID)
    }

    public mutating func renameSubject(_ subjectID: String, to displayName: String?) {
        guard let index = subjects.firstIndex(where: { $0.subjectID == subjectID }) else { return }
        subjects[index].displayName = displayName
    }

    /// Hiding the last visible subject is ignored so the child still has one.
    public mutating func setSubjectHidden(_ subjectID: String, _ hidden: Bool) {
        guard let index = subjects.firstIndex(where: { $0.subjectID == subjectID }) else { return }
        if hidden {
            let visible = subjects.filter { !$0.hidden }
            if visible.count <= 1, visible.contains(where: { $0.subjectID == subjectID }) {
                return
            }
        }
        subjects[index].hidden = hidden
    }

    public mutating func reorderSubjects(_ subjectIDs: [String]) {
        var ordered: [ChildSubject] = []
        var remaining = subjects
        for id in subjectIDs {
            if let index = remaining.firstIndex(where: { $0.subjectID == id }) {
                ordered.append(remaining.remove(at: index))
            }
        }
        ordered.append(contentsOf: remaining)
        subjects = ordered.enumerated().map { index, row in
            var copy = row
            copy.order = index
            return copy
        }
    }
}

public enum ProfileRules {
    public static let maxChildren = 3

    public static func canAddChild(currentCount: Int) -> Bool {
        currentCount < maxChildren
    }

    public static func seedSubjects(schoolClass: String, audience: AudienceConfig = .v1) -> [ChildSubject] {
        SubjectCatalog.defaults(for: schoolClass, audience: audience).enumerated().map { index, record in
            ChildSubject(subjectID: record.id, displayName: nil, hidden: false, order: index)
        }
    }

    public static func make(
        nickname: String,
        schoolClass: String,
        avatarID: String = "sun",
        showMarkToChild: Bool = false,
        parentLabel: String = "",
        id: UUID = UUID(),
        audience: AudienceConfig = .v1
    ) -> ChildProfile {
        ChildProfile(
            id: id,
            nickname: nickname,
            ageBandID: audience.ageBandID,
            schoolClass: schoolClass,
            avatarID: avatarID,
            showMarkToChild: showMarkToChild,
            parentLabel: parentLabel,
            subjects: seedSubjects(schoolClass: schoolClass, audience: audience)
        )
    }
}
