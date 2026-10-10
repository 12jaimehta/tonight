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

    func test_PRIV26_lockoutSurvivesBackground() {
        var session = ParentalGateSession()
        let now = Date()
        let challenge = ParentalGateBank.challenges[1]
        _ = session.submit(answer: "0", to: challenge, now: now)
        _ = session.submit(answer: "0", to: challenge, now: now)
        _ = session.submit(answer: "0", to: challenge, now: now)
        XCTAssertTrue(session.isLocked(at: now))
        session.resetForBackground()
        XCTAssertTrue(session.isLocked(at: now))
        XCTAssertEqual(session.failures, 3)
        XCTAssertEqual(session.submit(answer: "2322", to: challenge, now: now), .locked)
        let later = session.submit(answer: "2322", to: challenge, now: now.addingTimeInterval(60))
        XCTAssertEqual(later, .unlocked)
    }

    func test_PRIV25c_eachDrawCanChangeTheChallenge() {
        struct Scripted: RandomNumberGenerator {
            var nextValue: UInt64
            mutating func next() -> UInt64 { nextValue }
        }
        var first = Scripted(nextValue: 0)
        var later = Scripted(nextValue: 3)
        XCTAssertEqual(ParentalGateBank.randomChallenge(using: &first).prompt, "47 × 36")
        XCTAssertEqual(ParentalGateBank.randomChallenge(using: &later).prompt, "93 × 47")
        XCTAssertNotEqual(
            ParentalGateBank.randomChallenge(using: &first).prompt,
            ParentalGateBank.randomChallenge(using: &later).prompt
        )
    }

    func test_PRIV24_gatedLinkStaysClosedUntilUnlock() throws {
        let url = try XCTUnwrap(URL(string: "https://project-ref.supabase.co/functions/v1/sarvam-proxy"))
        XCTAssertNil(ParentalGatedLink.destination(url, unlocked: false))
        XCTAssertEqual(ParentalGatedLink.destination(url, unlocked: true), url)
    }

    func test_KIDS02_gateIsAProductNotAPIN() {
        for challenge in ParentalGateBank.challenges {
            XCTAssertTrue(challenge.prompt.contains("×"))
            XCTAssertGreaterThan(challenge.answer, 999)
        }
        var session = ParentalGateSession()
        XCTAssertNotEqual(session.submit(answer: "1234", to: ParentalGateBank.challenges[0], now: Date()), .unlocked)
    }
}
