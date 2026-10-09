import Foundation

public enum AvatarPresets {
    public static let ids = ["sun", "moon", "star", "leaf", "book"]
}

/// A child on a parent account. No date of birth and no photo of the child.
public struct ChildProfile: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var nickname: String
    public var ageBandID: String
    public var schoolClass: String?
    public var avatarID: String
    public var showMarkToChild: Bool
    public var enabledSubjectIDs: [String]

    public init(
        id: UUID,
        nickname: String,
        ageBandID: String,
        schoolClass: String?,
        avatarID: String,
        showMarkToChild: Bool,
        enabledSubjectIDs: [String]
    ) {
        self.id = id
        self.nickname = nickname
        self.ageBandID = ageBandID
        self.schoolClass = schoolClass
        self.avatarID = avatarID
        self.showMarkToChild = showMarkToChild
        self.enabledSubjectIDs = enabledSubjectIDs
    }
}

public enum ProfileRules {
    public static let maxChildren = 3

    public static func canAddChild(currentCount: Int) -> Bool {
        currentCount < maxChildren
    }

    public static func make(
        nickname: String,
        schoolClass: String,
        avatarID: String = "sun",
        showMarkToChild: Bool = false,
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
            enabledSubjectIDs: SubjectCatalog.defaults(for: schoolClass, audience: audience).map(\.id)
        )
    }
}
