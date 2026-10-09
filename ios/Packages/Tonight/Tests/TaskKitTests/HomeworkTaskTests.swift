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
        XCTAssertNil(StarReward(count: 4))
        XCTAssertEqual(StarReward(count: 3)?.count, 3)

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
    }

    func testANewActivityCanBeRegistered() {
        let registry = ActivityRegistry.v1().registering(SeamActivity())
        XCTAssertEqual(registry.kinds, ["read_aloud", "seam", "short_answer"])
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
