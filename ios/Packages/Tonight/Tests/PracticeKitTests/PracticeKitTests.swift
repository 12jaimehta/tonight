import XCTest
@testable import PracticeKit

final class PracticeKitTests: XCTestCase {
    private let child = UUID()

    func testTwoDifferentCorrectDaysClearTheWord() {
        var list = RememberList()
        let added = list.add(childID: child, word: "cat", subjectID: "english", at: day(0), id: UUID())
        let id = try! XCTUnwrap(added).id

        let once = list.recordCorrect(id: id, day: "2026-10-01", at: day(1))
        XCTAssertEqual(once?.correctDays, ["2026-10-01"])
        XCTAssertNil(once?.clearedAt)
        XCTAssertEqual(list.active().count, 1)

        let sameDay = list.recordCorrect(id: id, day: "2026-10-01", at: day(1))
        XCTAssertEqual(sameDay?.correctDays, ["2026-10-01"])
        XCTAssertNil(sameDay?.clearedAt)

        let cleared = list.recordCorrect(id: id, day: "2026-10-02", at: day(2))
        XCTAssertEqual(cleared?.correctDays, ["2026-10-01", "2026-10-02"])
        XCTAssertNotNil(cleared?.clearedAt)
        XCTAssertTrue(list.active().isEmpty)
        XCTAssertTrue(list.warmup().isEmpty)
    }

    func test_DEL19_removeAllDropsThatChildsWords() {
        var list = RememberList()
        list.add(childID: child, word: "cat", subjectID: "english", at: day(0), id: UUID())
        list.add(childID: UUID(), word: "kept", subjectID: "english", at: day(0), id: UUID())
        list.removeAll(childID: child)
        XCTAssertEqual(list.active().map(\.word), ["kept"])
    }

    func testWarmupCapIsFiveOldest() {
        var list = RememberList()
        for index in 0..<6 {
            list.add(childID: child, word: "w\(index)", subjectID: "english", at: day(index), id: UUID())
        }
        XCTAssertEqual(RememberRules.correctDaysToClear, 2)
        XCTAssertEqual(RememberRules.warmupCap, 5)
        XCTAssertEqual(list.active().count, 6)
        XCTAssertEqual(list.warmup().map(\.word), ["w0", "w1", "w2", "w3", "w4"])

        let oldest = list.active()[0]
        _ = list.recordCorrect(id: oldest.id, day: "2026-10-01", at: day(10))
        _ = list.recordCorrect(id: oldest.id, day: "2026-10-02", at: day(11))
        XCTAssertEqual(list.warmup().map(\.word), ["w1", "w2", "w3", "w4", "w5"])
    }

    func testBlankWordsAreDroppedAndDuplicatesStayOne() {
        var list = RememberList()
        XCTAssertNil(list.add(childID: child, word: "   ", subjectID: "english", at: day(0)))
        let first = list.add(childID: child, word: " cat ", subjectID: "english", at: day(0))
        let second = list.add(childID: child, word: "cat", subjectID: "english", at: day(1))
        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(list.active().count, 1)
        XCTAssertEqual(list.active().first?.word, "cat")
    }

    func testDayKeyUsesUTC() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(RememberDay.key(for: date), "1970-01-01")
    }

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(offset) * 86_400)
    }
}
