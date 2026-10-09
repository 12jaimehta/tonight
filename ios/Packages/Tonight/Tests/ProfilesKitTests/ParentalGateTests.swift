import XCTest
@testable import ProfilesKit

final class ParentalGateTests: XCTestCase {
    func testFixedChallengeIsTheFirstProduct() {
        XCTAssertEqual(ParentalGateBank.challenge(fixed: true).answer, 47 * 36)
        XCTAssertEqual(ParentalGateBank.challenges.map(\.answer), [
            47 * 36, 86 * 27, 64 * 58, 93 * 47, 74 * 53, 39 * 68, 58 * 46, 27 * 84,
        ])
    }

    func testCorrectAnswerUnlocks() {
        var session = ParentalGateSession()
        let now = Date(timeIntervalSince1970: 1_000)
        let verdict = session.submit(answer: "1692", to: ParentalGateBank.challenges[0], now: now)
        XCTAssertEqual(verdict, .unlocked)
        XCTAssertEqual(session.failures, 0)
    }

    func testThreeWrongAnswersLockForSixtySeconds() {
        var session = ParentalGateSession()
        let now = Date(timeIntervalSince1970: 5_000)
        let challenge = ParentalGateBank.challenges[0]
        XCTAssertEqual(session.submit(answer: "1", to: challenge, now: now), .incorrect(remaining: 2))
        XCTAssertEqual(session.submit(answer: "2", to: challenge, now: now), .incorrect(remaining: 1))
        XCTAssertEqual(session.submit(answer: "3", to: challenge, now: now), .locked)
        XCTAssertEqual(session.submit(answer: "1692", to: challenge, now: now.addingTimeInterval(30)), .locked)
        let later = session.submit(answer: "1692", to: challenge, now: now.addingTimeInterval(60))
        XCTAssertEqual(later, .unlocked)
    }

    func testBackgroundClearsTheLockout() {
        var session = ParentalGateSession()
        let now = Date()
        let challenge = ParentalGateBank.challenges[1]
        _ = session.submit(answer: "0", to: challenge, now: now)
        _ = session.submit(answer: "0", to: challenge, now: now)
        _ = session.submit(answer: "0", to: challenge, now: now)
        XCTAssertTrue(session.isLocked(at: now))
        session.resetForBackground()
        XCTAssertFalse(session.isLocked(at: now))
        XCTAssertEqual(session.failures, 0)
        XCTAssertEqual(session.submit(answer: "2322", to: challenge, now: now), .unlocked)
    }
}
