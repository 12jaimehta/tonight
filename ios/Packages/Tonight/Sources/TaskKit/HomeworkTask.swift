import Foundation

public enum CheckMode: String, Codable, Hashable, Sendable {
    case auto
    case parent
}

public struct PhotoRef: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var relativePath: String

    public init(id: UUID = UUID(), relativePath: String) {
        self.id = id
        self.relativePath = relativePath
    }
}

public struct MediaRef: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: String

    public init(id: UUID = UUID(), kind: String) {
        self.id = id
        self.kind = kind
    }
}

public enum HomeworkIssue: String, Equatable, Sendable {
    case missingSubject
    case autoIsEnglishOnly
    case autoNeedsConfirmedText
    case parentNeedsPhoto
    case starsOutOfRange
}

/// Rule failures from making a homework task. An array of issues is not itself an Error.
public struct HomeworkRulesError: Error, Equatable, Sendable {
    public var issues: [HomeworkIssue]

    public init(issues: [HomeworkIssue]) {
        self.issues = issues
    }
}

public struct HomeworkDraft: Equatable, Sendable {
    public var subjectID: String
    public var checkMode: CheckMode
    public var confirmedText: String
    public var photoCount: Int
    public var stars: Int?

    public init(subjectID: String, checkMode: CheckMode, confirmedText: String = "", photoCount: Int = 0, stars: Int? = nil) {
        self.subjectID = subjectID
        self.checkMode = checkMode
        self.confirmedText = confirmedText
        self.photoCount = photoCount
        self.stars = stars
    }
}

public enum HomeworkRules {
    public static let autoSubjectID = "english"
    /// Notebook stars the parent can award. Zero is not a reward.
    public static let starScale = StarScale.valid

    public static func issues(for draft: HomeworkDraft) -> [HomeworkIssue] {
        var issues: [HomeworkIssue] = []
        if draft.subjectID.isEmpty { issues.append(.missingSubject) }
        if let stars = draft.stars, !starScale.contains(stars) {
            issues.append(.starsOutOfRange)
        }
        switch draft.checkMode {
        case .auto:
            if draft.subjectID != autoSubjectID { issues.append(.autoIsEnglishOnly) }
            if draft.confirmedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.autoNeedsConfirmedText)
            }
        case .parent:
            if draft.photoCount < 1 { issues.append(.parentNeedsPhoto) }
        }
        return issues
    }
}

/// One homework item. Exactly one subject. Rewards are stars: there is no level, XP, or syllabus.
public struct HomeworkTask: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var childID: UUID
    /// Exactly one subject. A task does not store a list of subjects.
    public var subjectID: String
    public var schoolClass: String
    public var instruction: String
    public var checkMode: CheckMode
    public var confirmedText: String?
    public var pagePhotoRefs: [PhotoRef]
    public var media: [MediaRef]
    public var showMarkOverride: Bool?
    public var stars: Int?
    public var createdAt: Date

    /// v1 flow for this one subject. English is read-aloud. Anything else is a notebook photo.
    public var activityKind: String {
        checkMode == .auto ? V1ActivityKind.readAloud : V1ActivityKind.notebook
    }

    public init(
        id: UUID,
        childID: UUID,
        subjectID: String,
        schoolClass: String,
        instruction: String,
        checkMode: CheckMode,
        confirmedText: String?,
        pagePhotoRefs: [PhotoRef],
        media: [MediaRef],
        showMarkOverride: Bool?,
        stars: Int?,
        createdAt: Date
    ) {
        self.id = id
        self.childID = childID
        self.subjectID = subjectID
        self.schoolClass = schoolClass
        self.instruction = instruction
        self.checkMode = checkMode
        self.confirmedText = confirmedText
        self.pagePhotoRefs = pagePhotoRefs
        self.media = media
        self.showMarkOverride = showMarkOverride
        self.stars = stars
        self.createdAt = createdAt
    }

    public static func make(
        id: UUID = UUID(),
        childID: UUID,
        subjectID: String,
        schoolClass: String,
        instruction: String,
        checkMode: CheckMode,
        confirmedText: String? = nil,
        pagePhotoRefs: [PhotoRef] = [],
        stars: Int? = nil,
        createdAt: Date = Date()
    ) -> Result<HomeworkTask, HomeworkRulesError> {
        let draft = HomeworkDraft(
            subjectID: subjectID,
            checkMode: checkMode,
            confirmedText: confirmedText ?? "",
            photoCount: pagePhotoRefs.count,
            stars: stars
        )
        let issues = HomeworkRules.issues(for: draft)
        guard issues.isEmpty else { return .failure(HomeworkRulesError(issues: issues)) }
        return .success(HomeworkTask(
            id: id,
            childID: childID,
            subjectID: subjectID,
            schoolClass: schoolClass,
            instruction: instruction,
            checkMode: checkMode,
            confirmedText: confirmedText,
            pagePhotoRefs: pagePhotoRefs,
            media: [],
            showMarkOverride: nil,
            stars: stars,
            createdAt: createdAt
        ))
    }
}

public struct StarReward: Codable, Hashable, Sendable {
    public static let scale = StarScale.valid
    public var count: Int

    public init?(count: Int) {
        guard let count = NotebookStars.count(picked: count) else { return nil }
        self.count = count
    }
}
