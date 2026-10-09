import AuthKit
import Foundation
import PracticeKit
import ProfilesKit
import SwiftData
import TaskKit

/// First store. There is no earlier schema, so the migration plan is empty.
public enum TonightSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            StoredChild.self,
            StoredHomework.self,
            StoredRemember.self,
            StoredAdultConsent.self,
            StoredNotebook.self,
            StoredParentCheck.self,
            StoredPraise.self,
        ]
    }

    @Model
    public final class StoredChild {
        @Attribute(.unique) public var id: UUID
        public var nickname: String
        public var ageBandID: String
        public var schoolClass: String?
        public var avatarID: String
        public var showMarkToChild: Bool
        public var parentLabel: String
        /// JSON array of per-child subject rows. The catalogue id is inside each row.
        public var subjectsJSON: String

        public init(
            id: UUID,
            nickname: String,
            ageBandID: String,
            schoolClass: String?,
            avatarID: String,
            showMarkToChild: Bool,
            parentLabel: String,
            subjectsJSON: String
        ) {
            self.id = id
            self.nickname = nickname
            self.ageBandID = ageBandID
            self.schoolClass = schoolClass
            self.avatarID = avatarID
            self.showMarkToChild = showMarkToChild
            self.parentLabel = parentLabel
            self.subjectsJSON = subjectsJSON
        }

        public convenience init(profile: ChildProfile) {
            self.init(
                id: profile.id,
                nickname: profile.nickname,
                ageBandID: profile.ageBandID,
                schoolClass: profile.schoolClass,
                avatarID: profile.avatarID,
                showMarkToChild: profile.showMarkToChild,
                parentLabel: profile.parentLabel,
                subjectsJSON: JSONText.encode(profile.subjects)
            )
        }

        public func profile() -> ChildProfile {
            ChildProfile(
                id: id,
                nickname: nickname,
                ageBandID: ageBandID,
                schoolClass: schoolClass,
                avatarID: avatarID,
                showMarkToChild: showMarkToChild,
                parentLabel: parentLabel,
                subjects: JSONText.decode([ChildSubject].self, subjectsJSON)
            )
        }
    }

    @Model
    public final class StoredHomework {
        @Attribute(.unique) public var id: UUID
        public var childID: UUID
        public var subjectID: String
        public var schoolClass: String
        public var instruction: String
        public var checkMode: String
        public var confirmedText: String?
        /// Relative paths only. The image files live beside the store, not in this row.
        public var photoPaths: String
        public var showMarkOverride: Bool?
        public var stars: Int?
        public var createdAt: Date

        public init(
            id: UUID,
            childID: UUID,
            subjectID: String,
            schoolClass: String,
            instruction: String,
            checkMode: String,
            confirmedText: String?,
            photoPaths: String,
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
            self.photoPaths = photoPaths
            self.showMarkOverride = showMarkOverride
            self.stars = stars
            self.createdAt = createdAt
        }

        public convenience init(task: HomeworkTask) {
            self.init(
                id: task.id,
                childID: task.childID,
                subjectID: task.subjectID,
                schoolClass: task.schoolClass,
                instruction: task.instruction,
                checkMode: task.checkMode.rawValue,
                confirmedText: task.confirmedText,
                photoPaths: JSONText.encode(task.pagePhotoRefs.map(\.relativePath)),
                showMarkOverride: task.showMarkOverride,
                stars: task.stars,
                createdAt: task.createdAt
            )
        }

        public func task() -> HomeworkTask {
            let paths = JSONText.decode([String].self, photoPaths)
            return HomeworkTask(
                id: id,
                childID: childID,
                subjectID: subjectID,
                schoolClass: schoolClass,
                instruction: instruction,
                checkMode: CheckMode(rawValue: checkMode) ?? .parent,
                confirmedText: confirmedText,
                pagePhotoRefs: paths.map { PhotoRef(relativePath: $0) },
                media: [],
                showMarkOverride: showMarkOverride,
                stars: stars,
                createdAt: createdAt
            )
        }
    }

    @Model
    public final class StoredRemember {
        @Attribute(.unique) public var id: UUID
        public var childID: UUID
        public var word: String
        public var subjectID: String
        public var createdAt: Date
        public var correctDays: String
        public var clearedAt: Date?

        public init(
            id: UUID,
            childID: UUID,
            word: String,
            subjectID: String,
            createdAt: Date,
            correctDays: String,
            clearedAt: Date?
        ) {
            self.id = id
            self.childID = childID
            self.word = word
            self.subjectID = subjectID
            self.createdAt = createdAt
            self.correctDays = correctDays
            self.clearedAt = clearedAt
        }

        public convenience init(entry: RememberEntry) {
            self.init(
                id: entry.id,
                childID: entry.childID,
                word: entry.word,
                subjectID: entry.subjectID,
                createdAt: entry.createdAt,
                correctDays: JSONText.encode(entry.correctDays),
                clearedAt: entry.clearedAt
            )
        }

        public func entry() -> RememberEntry {
            RememberEntry(
                id: id,
                childID: childID,
                word: word,
                subjectID: subjectID,
                createdAt: createdAt,
                correctDays: JSONText.decode([String].self, correctDays),
                clearedAt: clearedAt
            )
        }
    }

    @Model
    public final class StoredAdultConsent {
        @Attribute(.unique) public var id: UUID
        public var parentID: String
        public var version: String
        public var acceptedAt: Date
        public var method: String

        public init(id: UUID, parentID: String, version: String, acceptedAt: Date, method: String) {
            self.id = id
            self.parentID = parentID
            self.version = version
            self.acceptedAt = acceptedAt
            self.method = method
        }

        public convenience init(record: AdultConsentRecord) {
            self.init(
                id: record.id,
                parentID: record.parentID,
                version: record.version,
                acceptedAt: record.acceptedAt,
                method: record.method
            )
        }

        public func record() -> AdultConsentRecord {
            AdultConsentRecord(id: id, parentID: parentID, version: version, acceptedAt: acceptedAt, method: method)
        }
    }

    @Model
    public final class StoredNotebook {
        @Attribute(.unique) public var id: UUID
        public var taskID: UUID
        public var at: Date
        /// Relative path. The photo file is not in this row and is not backed up.
        public var photoPath: String

        public init(id: UUID, taskID: UUID, at: Date, photoPath: String) {
            self.id = id
            self.taskID = taskID
            self.at = at
            self.photoPath = photoPath
        }

        public convenience init(attempt: NotebookAttempt) {
            self.init(id: attempt.id, taskID: attempt.taskID, at: attempt.at, photoPath: attempt.workPhotoRef.relativePath)
        }

        public func attempt() -> NotebookAttempt {
            NotebookAttempt(id: id, taskID: taskID, at: at, workPhotoRef: PhotoRef(relativePath: photoPath))
        }
    }

    @Model
    public final class StoredParentCheck {
        @Attribute(.unique) public var id: UUID
        public var attemptID: UUID
        public var stars: Int
        public var checkedAt: Date

        public init(id: UUID, attemptID: UUID, stars: Int, checkedAt: Date) {
            self.id = id
            self.attemptID = attemptID
            self.stars = stars
            self.checkedAt = checkedAt
        }

        public convenience init(check: ParentCheck) {
            self.init(id: check.id, attemptID: check.attemptID, stars: check.stars, checkedAt: check.checkedAt)
        }

        public func check() -> ParentCheck {
            ParentCheck(id: id, attemptID: attemptID, stars: stars, checkedAt: checkedAt)
        }
    }

    @Model
    public final class StoredPraise {
        @Attribute(.unique) public var id: UUID
        public var taskID: UUID
        public var attemptID: UUID?
        public var presetID: String
        public var text: String?
        public var lang: String
        public var sentAt: Date
        public var seenAt: Date?

        public init(
            id: UUID,
            taskID: UUID,
            attemptID: UUID?,
            presetID: String,
            text: String?,
            lang: String,
            sentAt: Date,
            seenAt: Date?
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

        public convenience init(praise: Praise) {
            self.init(
                id: praise.id,
                taskID: praise.taskID,
                attemptID: praise.attemptID,
                presetID: praise.presetID,
                text: praise.text,
                lang: praise.lang,
                sentAt: praise.sentAt,
                seenAt: praise.seenAt
            )
        }

        public func praise() -> Praise {
            Praise(
                id: id,
                taskID: taskID,
                attemptID: attemptID,
                presetID: presetID,
                text: text,
                lang: lang,
                sentAt: sentAt,
                seenAt: seenAt
            )
        }
    }
}

enum JSONText {
    static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    static func decode<T: Decodable>(_ type: T.Type, _ text: String) -> T {
        if let data = text.data(using: .utf8), let value = try? JSONDecoder().decode(type, from: data) {
            return value
        }
        if let empty = try? JSONDecoder().decode(type, from: Data("[]".utf8)) {
            return empty
        }
        fatalError("JSONText could not decode \(T.self)")
    }
}

public enum TonightMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [TonightSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}

public enum TonightStore {
    public static func makeContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TonightSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: TonightSchemaV1.self,
            migrationPlan: TonightMigrationPlan.self,
            configurations: configuration
        )
        try LocalProtection.protectStore(at: url)
        return container
    }
}
