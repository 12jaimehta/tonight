import XCTest
@testable import ProfilesKit

final class ParentalGateTests: XCTestCase {
    func testFixedChallengeIsSpelledOut() {
        let fixed = ParentalGateBank.challenge(fixed: true)
        XCTAssertEqual(fixed.answer, 347)
        XCTAssertEqual(fixed.prompt, "three hundred and forty-seven")
        XCTAssertEqual(ParentalGateBank.challenge(fixed: true, offset: 4).prompt, fixed.prompt)
        XCTAssertEqual(EnglishNumberWords.spell(100), "one hundred")
        XCTAssertEqual(EnglishNumberWords.spell(101), "one hundred and one")
        XCTAssertEqual(EnglishNumberWords.spell(111), "one hundred and eleven")
        XCTAssertEqual(EnglishNumberWords.spell(120), "one hundred and twenty")
        XCTAssertEqual(ParentalGateBank.number(at: 0), 100)
        XCTAssertEqual(ParentalGateBank.challenge(fixed: false, offset: 247).answer, 347)
        XCTAssertEqual(ParentalGateBank.digitCount, 3)
    }

    func testCorrectAnswerUnlocks() {
        var session = ParentalGateSession()
        let now = Date(timeIntervalSince1970: 1_000)
        let challenge = ParentalGateBank.challenge(fixed: true)
        let verdict = session.submit(answer: "347", to: challenge, now: now)
        XCTAssertEqual(verdict, .unlocked)
        XCTAssertEqual(session.failures, 0)
    }

    func testThreeWrongAnswersCloseUntilBackground() {
        var session = ParentalGateSession()
        let now = Date(timeIntervalSince1970: 5_000)
        let challenge = ParentalGateBank.challenge(fixed: true)
        XCTAssertEqual(session.submit(answer: "1", to: challenge, now: now), .incorrect(remaining: 2))
        XCTAssertEqual(session.submit(answer: "2", to: challenge, now: now), .incorrect(remaining: 1))
        XCTAssertEqual(session.submit(answer: "3", to: challenge, now: now), .locked)
        XCTAssertEqual(session.submit(answer: "347", to: challenge, now: now.addingTimeInterval(60)), .locked)
        XCTAssertTrue(session.isLocked(at: now.addingTimeInterval(3_600)))
    }

    func testBackgroundClearsTheLockout() {
        var session = ParentalGateSession()
        let now = Date()
        let challenge = ParentalGateBank.challenge(fixed: false, offset: 20)
        _ = session.submit(answer: "0", to: challenge, now: now)
        _ = session.submit(answer: "0", to: challenge, now: now)
        _ = session.submit(answer: "0", to: challenge, now: now)
        XCTAssertTrue(session.isLocked(at: now))
        session.resetForBackground()
        XCTAssertFalse(session.isLocked(at: now))
        XCTAssertEqual(session.failures, 0)
        XCTAssertEqual(session.submit(answer: "120", to: challenge, now: now), .unlocked)
    }
}
