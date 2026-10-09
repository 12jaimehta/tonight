import XCTest
import MarkingKit
@testable import TaskKit

final class HomeworkTaskTests: XCTestCase {
    func testAutoIsEnglishReadingWithConfirmedText() {
        let child = UUID()
        let saved = HomeworkTask.make(
            childID: child,
            subjectID: "english",
            schoolClass: "1",
            instruction: "Read page 12",
            checkMode: .auto,
            confirmedText: "the cat sat"
        )
        guard case .success(let task) = saved else {
            return XCTFail("expected a task")
        }
        XCTAssertEqual(task.subjectID, "english")
        XCTAssertEqual(task.checkMode, .auto)
        XCTAssertEqual(task.activityKind, V1ActivityKind.readAloud)
        XCTAssertTrue(type(of: task.subjectID) == String.self)

        let maths = HomeworkTask.make(childID: child, subjectID: "maths", schoolClass: "1", instruction: "Sums", checkMode: .auto, confirmedText: "2")
        XCTAssertEqual(resultIssues(maths), [.autoIsEnglishOnly])

        let empty = HomeworkTask.make(childID: child, subjectID: "english", schoolClass: "1", instruction: "Read", checkMode: .auto, confirmedText: "  ")
        XCTAssertEqual(resultIssues(empty), [.autoNeedsConfirmedText])
    }

    func testParentModeNeedsAPhotoAndStarsStayInRange() {
        let child = UUID()
        let missing = HomeworkTask.make(childID: child, subjectID: "hindi", schoolClass: "2", instruction: "Copy the letters", checkMode: .parent)
        XCTAssertEqual(resultIssues(missing), [.parentNeedsPhoto])

        let photos = [
            PhotoRef(relativePath: "a.jpg"),
            PhotoRef(relativePath: "b.jpg"),
        ]
        let saved = HomeworkTask.make(
            childID: child,
            subjectID: "hindi",
            schoolClass: "2",
            instruction: "Copy the letters",
            checkMode: .parent,
            pagePhotoRefs: photos,
            stars: 2
        )
        guard case .success(let task) = saved else { return XCTFail("expected a task") }
        XCTAssertEqual(task.pagePhotoRefs.count, 2)
        XCTAssertEqual(task.stars, 2)
        XCTAssertEqual(task.activityKind, V1ActivityKind.notebook)
        XCTAssertEqual(ActivityRegistry.v1Kind(subjectID: "hindi"), V1ActivityKind.notebook)
        XCTAssertNil(StarReward(count: 4))
        XCTAssertNil(StarReward(count: 0))
        XCTAssertEqual(StarReward(count: 3)?.count, 3)
        XCTAssertEqual(StarReward(count: 1)?.count, 1)

        let tooMany = HomeworkTask.make(
            childID: child,
            subjectID: "evs",
            schoolClass: "3",
            instruction: "Draw a plant",
            checkMode: .parent,
            pagePhotoRefs: [PhotoRef(relativePath: "p.jpg")],
            stars: 9
        )
        XCTAssertEqual(resultIssues(tooMany), [.starsOutOfRange])
    }

    func testTaskJSONHasNoLevelsXPOrSyllabus() throws {
        let task = try HomeworkTask.make(
            childID: UUID(),
            subjectID: "english",
            schoolClass: "3",
            instruction: "Read",
            checkMode: .auto,
            confirmedText: "birds fly"
        ).get()
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any]
        XCTAssertEqual(object?["subjectID"] as? String, "english")
        XCTAssertEqual(object?["checkMode"] as? String, "auto")
        XCTAssertNil(object?["xp"])
        XCTAssertNil(object?["level"])
        XCTAssertNil(object?["syllabus"])
        XCTAssertNil(object?["chapters"])
        XCTAssertNil(object?["subjectIDs"])
        XCTAssertNil(object?["subjects"])
    }

    func testSubjectIDHoldsExactlyOneSubject() throws {
        let task = try HomeworkTask.make(
            childID: UUID(),
            subjectID: "maths",
            schoolClass: "1",
            instruction: "Page 14",
            checkMode: .parent,
            pagePhotoRefs: [PhotoRef(relativePath: "sums.jpg")]
        ).get()
        XCTAssertEqual(task.subjectID, "maths")
        XCTAssertFalse(task.subjectID.contains(","))
        XCTAssertEqual(task.activityKind, "notebook")
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any]
        XCTAssertEqual(object?["subjectID"] as? String, "maths")
        XCTAssertNil(object?["subjectIDs"])
        XCTAssertNil(object?["subjectId"])
    }

    func testPraiseIsAPresetPlusOptionalText() throws {
        let praise = Praise(
            taskID: UUID(),
            attemptID: UUID(),
            presetID: "shabash",
            text: "You kept going",
            lang: "hi"
        )
        XCTAssertEqual(praise.presetPhrase, "शाबाश!")
        XCTAssertEqual(praise.text, "You kept going")
        let bare = Praise(taskID: UUID(), presetID: "proud", lang: "en")
        XCTAssertNil(bare.text)
        XCTAssertEqual(bare.presetPhrase, "So proud of you")
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(praise)) as? [String: Any]
        XCTAssertEqual(object?["presetID"] as? String, "shabash")
        XCTAssertEqual(object?["text"] as? String, "You kept going")
        XCTAssertNil(object?["voice"])
        XCTAssertNil(object?["audio"])
        XCTAssertNil(object?["audioURL"])
        XCTAssertNil(object?["voiceNote"])
    }

    func testNotebookAttemptIsAPhotoForParentCheck() throws {
        let attempt = NotebookAttempt(taskID: UUID(), workPhotoRef: PhotoRef(relativePath: "work.jpg"))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(attempt)) as? [String: Any]
        XCTAssertNotNil(object?["workPhotoRef"])
        XCTAssertNil(object?["audio"])
        XCTAssertNil(object?["transcript"])
        let mark = NotebookActivity().score(attempt: ActivityAttempt())
        XCTAssertEqual(mark.source, .parent)
        XCTAssertEqual(mark.words, [])
        XCTAssertNil(ActivityRegistry.v1().activity(kind: "short_answer"))
        XCTAssertEqual(ActivityRegistry.v1Kind(subjectID: "english"), "read_aloud")
    }

    func testAutoCountsWordsAndParentSetsStars() {
        let mark = CheckModeMarking.auto(expected: "the cat sat", heard: "the sat")
        XCTAssertEqual(mark.correct, 2)
        XCTAssertEqual(mark.total, 3)
        XCTAssertEqual(mark.source, .auto)
        let stars = CheckModeMarking.parent(stars: 1)
        XCTAssertEqual(stars?.source, .parent)
        XCTAssertEqual(stars?.correct, 1)
        XCTAssertEqual(stars?.total, 3)
        XCTAssertNil(CheckModeMarking.parent(stars: -1))
        XCTAssertNil(CheckModeMarking.parent(stars: 0))
        XCTAssertNil(ParentCheck(attemptID: UUID(), stars: 0))
        XCTAssertEqual(ParentCheck(attemptID: UUID(), stars: 2)?.stars, 2)

        let zero = HomeworkTask.make(
            childID: UUID(),
            subjectID: "hindi",
            schoolClass: "1",
            instruction: "Copy",
            checkMode: .parent,
            pagePhotoRefs: [PhotoRef(relativePath: "p.jpg")],
            stars: 0
        )
        XCTAssertEqual(resultIssues(zero), [.starsOutOfRange])
    }

    func testANewActivityCanBeRegistered() {
        let registry = ActivityRegistry.v1().registering(SeamActivity())
        XCTAssertEqual(registry.kinds, ["notebook", "read_aloud", "seam"])
        XCTAssertNil(registry.activity(kind: "short_answer"))
        let attempt = ActivityAttempt(
            written: WrittenAnswer(prompt: "2+2", text: "4"),
            objective: ObjectiveItem(prompt: "Pick", choiceID: "b")
        )
        XCTAssertEqual(registry.activity(kind: "seam")?.score(attempt: attempt).source, .rubric)
        XCTAssertTrue(NoLessonMedia().media(for: UUID()).isEmpty)
        let read = ReadAloudActivity().score(attempt: ActivityAttempt(expectedText: "the cat", heardText: "the cat"))
        XCTAssertEqual(read.correct, 2)
    }

    private func resultIssues(_ result: Result<HomeworkTask, [HomeworkIssue]>) -> [HomeworkIssue] {
        switch result {
        case .success: return []
        case .failure(let issues): return issues
        }
    }
}

private struct SeamActivity: Activity {
    let kind = "seam"
    func score(attempt: ActivityAttempt) -> Mark {
        Mark.notScored(strategyID: "seam", source: .rubric, locale: "en-IN")
    }
}
