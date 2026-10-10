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
        XCTAssertNil(session.lockedUntil)
    }

    func testThreeWrongAnswersLockForSixtySeconds() {
        var session = ParentalGateSession()
        let now = Date(timeIntervalSince1970: 5_000)
        let challenge = ParentalGateBank.challenge(fixed: true)
        XCTAssertEqual(session.submit(answer: "1", to: challenge, now: now), .incorrect(remaining: 2))
        XCTAssertEqual(session.submit(answer: "2", to: challenge, now: now), .incorrect(remaining: 1))
        XCTAssertEqual(session.submit(answer: "3", to: challenge, now: now), .locked)
        XCTAssertEqual(session.submit(answer: "347", to: challenge, now: now.addingTimeInterval(30)), .locked)
        XCTAssertTrue(session.isLocked(at: now.addingTimeInterval(59)))
        let later = session.submit(answer: "347", to: challenge, now: now.addingTimeInterval(60))
        XCTAssertEqual(later, .unlocked)
        XCTAssertFalse(session.isLocked(at: now.addingTimeInterval(3_600)))
    }

    func test_PRIV26_lockoutSurvivesBackground() {
        var session = ParentalGateSession()
        let now = Date(timeIntervalSince1970: 8_000)
        let challenge = ParentalGateBank.challenge(fixed: false, offset: 20)
        XCTAssertEqual(challenge.answer, 120)
        _ = session.submit(answer: "0", to: challenge, now: now)
        _ = session.submit(answer: "0", to: challenge, now: now)
        _ = session.submit(answer: "0", to: challenge, now: now)
        XCTAssertTrue(session.isLocked(at: now))
        session.resetForBackground()
        XCTAssertTrue(session.isLocked(at: now))
        XCTAssertEqual(session.failures, 3)
        XCTAssertEqual(session.submit(answer: "120", to: challenge, now: now), .locked)
        let later = session.submit(answer: "120", to: challenge, now: now.addingTimeInterval(60))
        XCTAssertEqual(later, .unlocked)
    }

    func test_PRIV26_lockoutSurvivesRelaunch() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "gate-\(UUID().uuidString)"))
        var session = ParentalGateSession()
        let now = Date(timeIntervalSince1970: 10_000)
        let challenge = ParentalGateBank.challenge(fixed: true)
        XCTAssertEqual(session.submit(answer: "0", to: challenge, now: now), .incorrect(remaining: 2))
        XCTAssertEqual(session.submit(answer: "0", to: challenge, now: now), .incorrect(remaining: 1))
        XCTAssertEqual(session.submit(answer: "0", to: challenge, now: now), .locked)
        session.resetForBackground()
        session.lockoutRecord.save(to: defaults)
        var relaunched = ParentalGateSession(lockoutRecord: ParentalGateLockout.load(from: defaults))
        XCTAssertEqual(relaunched.failures, 3)
        XCTAssertTrue(relaunched.isLocked(at: now))
        XCTAssertEqual(relaunched.submit(answer: "347", to: challenge, now: now.addingTimeInterval(30)), .locked)
        XCTAssertEqual(relaunched.submit(answer: "347", to: challenge, now: now.addingTimeInterval(60)), .unlocked)
        let stored = try XCTUnwrap(defaults.data(forKey: ParentalGateLockout.storageKey))
        let text = try XCTUnwrap(String(data: stored, encoding: .utf8)).lowercased()
        XCTAssertFalse(text.contains("347"))
        XCTAssertFalse(text.contains("pin"))
        XCTAssertFalse(text.contains("forty-seven"))
        let model = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TonightApp/Flow/TonightModel.swift")
        let source = try String(contentsOf: model, encoding: .utf8)
        XCTAssertTrue(source.contains("ParentalGateLockout.load"))
        XCTAssertTrue(source.contains("lockoutRecord.save"))
        XCTAssertTrue(source.contains("randomChallenge"))
    }

    func test_PRIV25c_eachPresentationDrawsANewChallenge() {
        struct Scripted: RandomNumberGenerator {
            var nextValue: UInt64
            mutating func next() -> UInt64 { nextValue }
        }
        var first = Scripted(nextValue: 0)
        var later = Scripted(nextValue: 3)
        XCTAssertEqual(ParentalGateBank.randomChallenge(using: &first).prompt, "one hundred")
        XCTAssertEqual(ParentalGateBank.randomChallenge(using: &later).prompt, "one hundred and three")
        var again = Scripted(nextValue: 0)
        var other = Scripted(nextValue: 3)
        XCTAssertNotEqual(
            ParentalGateBank.randomChallenge(using: &again).prompt,
            ParentalGateBank.randomChallenge(using: &other).prompt
        )
    }

    func test_PRIV24_gatedLinkStaysClosedUntilUnlock() throws {
        let url = try XCTUnwrap(URL(string: "https://project-ref.supabase.co/functions/v1/sarvam-proxy"))
        XCTAssertNil(ParentalGatedLink.destination(url, unlocked: false))
        XCTAssertEqual(ParentalGatedLink.destination(url, unlocked: true), url)
    }

    func test_KIDS02_gateIsASpelledNumberNotAPIN() {
        let samples = [
            ParentalGateBank.challenge(fixed: true),
            ParentalGateBank.challenge(fixed: false, offset: 0),
            ParentalGateBank.challenge(fixed: false, offset: 247),
        ]
        for challenge in samples {
            XCTAssertFalse(challenge.prompt.allSatisfy(\.isNumber))
            XCTAssertTrue(challenge.prompt.contains("hundred"))
            XCTAssertGreaterThanOrEqual(challenge.answer, 100)
            XCTAssertLessThanOrEqual(challenge.answer, 999)
        }
        var session = ParentalGateSession()
        XCTAssertNotEqual(session.submit(answer: "1234", to: samples[0], now: Date()), .unlocked)
    }
}
