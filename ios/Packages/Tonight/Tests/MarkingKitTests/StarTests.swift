import XCTest
@testable import MarkingKit

final class StarTests: XCTestCase {
    func testEnglishThresholdsNeverReturnZero() {
        XCTAssertEqual(EnglishStars.count(percent: 100), 3)
        XCTAssertEqual(EnglishStars.count(percent: 90), 3)
        XCTAssertEqual(EnglishStars.count(percent: 89), 2)
        XCTAssertEqual(EnglishStars.count(percent: 60), 2)
        XCTAssertEqual(EnglishStars.count(percent: 59), 1)
        XCTAssertEqual(EnglishStars.count(percent: 0), 1)
        XCTAssertEqual(EnglishStars.count(percent: -5), 1)
        for percent in 0...100 {
            let stars = EnglishStars.count(percent: percent)
            XCTAssertTrue(StarScale.valid.contains(stars), "\(percent) -> \(stars)")
        }
    }

    func testStarsAreDerivedFromTheAlignedMark() {
        let marker = Marker()
        let ten = "one two three four five six seven eight nine ten"
        let perfect = marker.mark(expected: ten, heard: ten)
        XCTAssertEqual(perfect.strategyID, "word-alignment")
        XCTAssertEqual(perfect.percent, 100)
        XCTAssertEqual(EnglishStars.count(for: perfect), 3)

        let nine = marker.mark(expected: ten, heard: "one two three four five six seven eight nine")
        XCTAssertEqual(nine.correct, 9)
        XCTAssertEqual(nine.percent, 90)
        XCTAssertEqual(EnglishStars.count(for: nine), 3)

        let eight = marker.mark(expected: ten, heard: "one two three four five six seven eight")
        XCTAssertEqual(eight.percent, 80)
        XCTAssertEqual(EnglishStars.count(for: eight), 2)

        let six = marker.mark(expected: ten, heard: "one two three four five six")
        XCTAssertEqual(six.percent, 60)
        XCTAssertEqual(EnglishStars.count(for: six), 2)

        let five = marker.mark(expected: ten, heard: "one two three four five")
        XCTAssertEqual(five.percent, 50)
        XCTAssertEqual(EnglishStars.count(for: five), 1)

        let empty = marker.mark(expected: "...", heard: "hello")
        XCTAssertNil(empty.percent)
        XCTAssertEqual(EnglishStars.count(for: empty), 1)
    }

    func testNotebookStarsAreOneTwoOrThree() {
        XCTAssertNil(NotebookStars.count(picked: 0))
        XCTAssertNil(NotebookStars.count(picked: -1))
        XCTAssertNil(NotebookStars.count(picked: 4))
        XCTAssertEqual(NotebookStars.count(picked: 1), 1)
        XCTAssertEqual(NotebookStars.count(picked: 2), 2)
        XCTAssertEqual(NotebookStars.count(picked: 3), 3)
    }

    func testHiddenMarkWithholdsAutomaticStarsUntilReviewAndStillHidesThem() {
        XCTAssertEqual(
            StarDisplay.automatic(percent: 95, markVisible: false, parentReviewed: false),
            .withheldUntilParentReview
        )
        XCTAssertEqual(
            StarDisplay.automatic(percent: 95, markVisible: false, parentReviewed: true),
            .withheldHiddenMark
        )
        XCTAssertEqual(
            StarDisplay.automatic(percent: 95, markVisible: true, parentReviewed: false),
            .shown(3)
        )
        XCTAssertEqual(
            StarDisplay.automatic(percent: 59, markVisible: true, parentReviewed: true),
            .shown(1)
        )
        XCTAssertFalse(MarkVisibility.shownToChild(taskOverride: false, childDefault: true))
        XCTAssertTrue(MarkVisibility.shownToChild(taskOverride: nil, childDefault: true))
        XCTAssertFalse(MarkVisibility.shownToChild(taskOverride: nil, childDefault: false))

        let mark = Marker().mark(expected: "one two", heard: "one two")
        XCTAssertEqual(
            StarDisplay.automatic(mark: mark, markVisible: false, parentReviewed: false),
            .withheldUntilParentReview
        )
    }

    func testTypedReadingCapsAtOneStarAndSpokenKeepsTheScale() {
        XCTAssertEqual(EnglishStars.count(percent: 100, inputMode: .spoken), 3)
        XCTAssertEqual(EnglishStars.count(percent: 90, inputMode: .spoken), 3)
        XCTAssertEqual(EnglishStars.count(percent: 89, inputMode: .spoken), 2)
        XCTAssertEqual(EnglishStars.count(percent: 60, inputMode: .spoken), 2)
        XCTAssertEqual(EnglishStars.count(percent: 59, inputMode: .spoken), 1)
        XCTAssertEqual(EnglishStars.count(percent: 0, inputMode: .spoken), 1)
        for percent in [0, 59, 60, 89, 90, 100] {
            XCTAssertEqual(EnglishStars.count(percent: percent, inputMode: .typed), 1)
        }

        let marker = Marker()
        let perfect = marker.mark(expected: "one two three", heard: "one two three")
        XCTAssertEqual(perfect.percent, 100)
        XCTAssertEqual(EnglishStars.count(for: perfect, inputMode: .spoken), 3)
        XCTAssertEqual(EnglishStars.count(for: perfect, inputMode: .typed), 1)
        XCTAssertEqual(
            StarDisplay.automatic(percent: 100, markVisible: true, parentReviewed: false, inputMode: .typed),
            .shown(1)
        )
        XCTAssertEqual(
            StarDisplay.automatic(percent: 100, markVisible: true, parentReviewed: false, inputMode: .spoken),
            .shown(3)
        )
        XCTAssertEqual(NotebookStars.count(picked: 1), 1)
        XCTAssertEqual(NotebookStars.count(picked: 2), 2)
        XCTAssertEqual(NotebookStars.count(picked: 3), 3)
        XCTAssertEqual(ReadingAttemptLabel.typedNotReadAloud, "Typed, not read aloud")
    }

    func testTypedAttemptsStayOutOfAccuracyAndHistory() {
        let samples = [
            ReadingSample(inputMode: .spoken, percent: 50),
            ReadingSample(inputMode: .typed, percent: 100),
            ReadingSample(inputMode: .spoken, percent: 90),
        ]
        XCTAssertEqual(ReadingHistory.accuracy(of: samples), 70)
        XCTAssertEqual(ReadingHistory.trend(of: samples), [50, 90])
        XCTAssertNil(ReadingHistory.accuracy(of: [ReadingSample(inputMode: .typed, percent: 100)]))
        XCTAssertEqual(ReadingHistory.trend(of: [ReadingSample(inputMode: .typed, percent: 100)]), [])
        XCTAssertEqual(ReadingHistory.sample(inputMode: .typed, percent: nil), nil)
    }

    func testAStarCountDoesNotCarryStreakXPOrLevel() throws {
        let award = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(StarCount(count: 2))
        ) as? [String: Any]
        XCTAssertEqual(award?["count"] as? Int, 2)
        XCTAssertNil(award?["streak"])
        XCTAssertNil(award?["xp"])
        XCTAssertNil(award?["level"])
        XCTAssertEqual(award?.count, 1)
    }
}

private struct StarCount: Codable {
    var count: Int
}
