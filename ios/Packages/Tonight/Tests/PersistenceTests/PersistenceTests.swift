import AuthKit
import PracticeKit
import ProfilesKit
import SwiftData
import TaskKit
import XCTest
@testable import Persistence

final class PersistenceTests: XCTestCase {
    func testSchemaV1HasAnEmptyMigrationPlan() {
        XCTAssertEqual(TonightSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(TonightSchemaV1.models.count, 7)
        XCTAssertEqual(TonightMigrationPlan.schemas.count, 1)
        XCTAssertTrue(TonightMigrationPlan.stages.isEmpty)
    }

    func testChildHomeworkAndRememberRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("Tonight.store")
        let container = try TonightStore.makeContainer(at: storeURL)
        let context = ModelContext(container)

        let profile = ProfileRules.make(nickname: "Asha", schoolClass: "2", id: UUID())
        context.insert(TonightSchemaV1.StoredChild(profile: profile))

        let task = try HomeworkTask.make(
            childID: profile.id,
            subjectID: "hindi",
            schoolClass: "2",
            instruction: "Copy the letters",
            checkMode: .parent,
            pagePhotoRefs: [PhotoRef(relativePath: "pages/a.jpg")],
            stars: 2
        ).get()
        context.insert(TonightSchemaV1.StoredHomework(task: task))

        let entry = RememberEntry(
            id: UUID(),
            childID: profile.id,
            word: "cat",
            subjectID: "english",
            createdAt: Date(timeIntervalSince1970: 20),
            correctDays: ["2026-10-01"],
            clearedAt: nil
        )
        context.insert(TonightSchemaV1.StoredRemember(entry: entry))

        let consent = AdultConsentRecord(
            parentID: "parent-1",
            acceptedAt: Date(timeIntervalSince1970: 30),
            method: "stub"
        )
        context.insert(TonightSchemaV1.StoredAdultConsent(record: consent))
        try context.save()
        try LocalProtection.protectStore(at: storeURL)

        let children = try context.fetch(FetchDescriptor<TonightSchemaV1.StoredChild>())
        XCTAssertEqual(children.first?.profile().visibleSubjectIDs, ["english", "hindi", "maths", "evs"])
        XCTAssertEqual(children.first?.profile().parentLabel, "")
        XCTAssertNil(children.first?.profile().subjects.first?.displayName)
        let homework = try context.fetch(FetchDescriptor<TonightSchemaV1.StoredHomework>())
        XCTAssertEqual(homework.first?.task().pagePhotoRefs.map(\.relativePath), ["pages/a.jpg"])
        XCTAssertEqual(homework.first?.task().stars, 2)
        let remembered = try context.fetch(FetchDescriptor<TonightSchemaV1.StoredRemember>())
        XCTAssertEqual(remembered.first?.entry().word, "cat")
        let storedConsent = try context.fetch(FetchDescriptor<TonightSchemaV1.StoredAdultConsent>())
        XCTAssertEqual(storedConsent.first?.record().method, "stub")

        let encoded = try JSONEncoder().encode(homework.first?.task())
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        XCTAssertNil(object?["xp"])
        XCTAssertNil(object?["level"])
    }

    func testPhotosAreExcludedFromBackupAndNeedTheParent() throws {
        XCTAssertEqual(LocalProtection.fileProtection, .complete)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("page.jpg")
        let bytes = Data([9, 8, 7])
        try PhotoFilePolicy.write(bytes, to: url)
        XCTAssertTrue(try PhotoFilePolicy.isExcludedFromBackup(url))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .complete)

        XCTAssertThrowsError(try PhotoAccess(parentUnlocked: false).contents(of: url)) { error in
            XCTAssertEqual(error as? PhotoAccessError, .parentLocked)
        }
        XCTAssertEqual(try PhotoAccess(parentUnlocked: true).contents(of: url), bytes)
    }
}
