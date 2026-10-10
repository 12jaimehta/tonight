import XCTest
@testable import GateHarness

final class GateHarnessTests: XCTestCase {
    func test_HAR01_agreementFalseAcceptAndFalseReject() throws {
        let report = try report("apple_pass")
        XCTAssertEqual(report.apple.agreement, Rational(1, 1))
        XCTAssertEqual(report.apple.falseAcceptRate, Rational(0, 1))
        XCTAssertEqual(report.apple.falseRejectRate, Rational(0, 1))
        XCTAssertEqual(report.apple.agreements, 64)
        XCTAssertEqual(report.apple.falseAccepts, 0)
        XCTAssertEqual(report.apple.falseRejects, 0)
        XCTAssertEqual(report.sarvam.falseAcceptRate, Rational(1, 1))
        XCTAssertEqual(report.sarvam.agreement, Rational(3, 4))
    }

    func test_HAR02_bootstrapUsesChildClusters() throws {
        let report = try report("apple_pass")
        XCTAssertEqual(GateHarness.bootstrapCount, 10_000)
        XCTAssertEqual(report.apple.agreementCI.lower, Rational(1, 1))
        XCTAssertEqual(report.apple.agreementCI.upper, Rational(1, 1))
        XCTAssertEqual(report.sarvam.falseAcceptCI.lower, Rational(1, 1))
        XCTAssertEqual(report.sarvam.falseAcceptCI.upper, Rational(1, 1))
        XCTAssertEqual(report.apple.perChildFalseAccept["c0"], Rational(0, 1))
        XCTAssertEqual(report.sarvam.perChildFalseAccept["c3"], Rational(1, 1))
    }

    func test_HAR03_decisionIsOneOfThreeCases() throws {
        XCTAssertEqual(GateDecision.allCases.map(\.rawValue), ["APPLE", "SARVAM", "NO_GO"])
        XCTAssertEqual(try report("apple_pass").decision, .apple)
        XCTAssertEqual(try report("sarvam_pass").decision, .sarvam)
        XCTAssertEqual(try report("no_go").decision, .noGo)
    }

    func test_MET01_pooledAgreement() throws {
        XCTAssertEqual(try report("no_go").apple.agreement, Rational(2, 5))
    }

    func test_MET02_pooledFalseAccept() throws {
        XCTAssertEqual(try report("apple_pass").sarvam.falseAccepts, 16)
        XCTAssertEqual(try report("apple_pass").sarvam.referenceIncorrect, 16)
    }

    func test_MET03_perChildFalseAccept() throws {
        let rates = try report("sarvam_pass").apple.perChildFalseAccept
        XCTAssertEqual(rates.count, 8)
        XCTAssertTrue(rates.values.allSatisfy { $0 == Rational(1, 1) })
    }

    func test_MET04_falseReject() throws {
        XCTAssertEqual(try report("no_go").apple.falseRejectRate, Rational(3, 5))
        XCTAssertEqual(try report("no_go").apple.falseRejects, 24)
        XCTAssertEqual(try report("no_go").apple.referenceCorrect, 40)
    }

    func test_MET05_exactIntegerCounts() throws {
        let apple = try report("apple_pass").apple
        XCTAssertEqual(apple.paired, apple.referenceCorrect + apple.referenceIncorrect)
        XCTAssertEqual(apple.agreements + (apple.paired - apple.agreements), apple.paired)
    }

    func test_MET06_compareBeforeRounding() throws {
        XCTAssertGreaterThan(Rational(901, 1000), Rational(900, 1000))
        XCTAssertEqual(Rational(1, 2), Rational(2, 4))
        XCTAssertGreaterThan(Rational(1, 3), Rational(333, 1000))
        XCTAssertEqual(try report("close_call").decision, .sarvam)
        XCTAssertEqual(try report("close_call").apple.agreement, Rational(9, 10))
        XCTAssertEqual(try report("close_call").sarvam.agreement, Rational(901, 1000))
    }

    func test_MET07_fixedSeedBootstrap() throws {
        let first = try report("no_go")
        let second = try report("no_go")
        XCTAssertEqual(first, second)
        XCTAssertEqual(GateHarness.seed, 20_261_010)
    }

    func test_MET10_onlyAppleSarvamOrNoGo() throws {
        let decision = try report("apple_pass").decision
        XCTAssertTrue([GateDecision.apple, .sarvam, .noGo].contains(decision))
    }

    func test_MET14_pythonGolden() throws {
        for name in ["apple_pass", "sarvam_pass", "no_go", "close_call"] {
            let golden = try golden(name)
            let actual = try report(name)
            XCTAssertEqual(actual.decision.rawValue, golden.decision, name)
            try assertEngine(actual.apple, golden.apple, name)
            try assertEngine(actual.sarvam, golden.sarvam, name)
        }
    }

    func test_MET20_unpairedRecording() {
        XCTAssertThrowsError(try report("unpaired")) { error in
            XCTAssertEqual(error as? GateHarnessError, .unpairedRecording(recordingID: "c00-0"))
        }
    }

    func test_MET21_outOfCohort() {
        XCTAssertThrowsError(try report("out_of_cohort")) { error in
            XCTAssertEqual(error as? GateHarnessError, .outOfCohort(recordingID: "c00-0"))
        }
    }

    func test_MET23_appleWhenOnlyAppleClearsTheBar() throws {
        XCTAssertEqual(try report("apple_pass").decision, .apple)
        XCTAssertTrue(try report("apple_pass").apple.passesBar)
        XCTAssertFalse(try report("apple_pass").sarvam.passesBar)
    }

    func test_MET24_sarvamWhenOnlySarvamClearsTheBar() throws {
        XCTAssertEqual(try report("sarvam_pass").decision, .sarvam)
        XCTAssertTrue(try report("sarvam_pass").sarvam.passesBar)
        XCTAssertFalse(try report("sarvam_pass").apple.passesBar)
    }

    func test_MET25_noGoWhenNeitherClearsTheBar() throws {
        let report = try report("no_go")
        XCTAssertEqual(report.decision, .noGo)
        XCTAssertFalse(report.apple.passesBar)
        XCTAssertFalse(report.sarvam.passesBar)
    }

    func test_MET26_tiePrefersApple() throws {
        let document = try load("apple_pass")
        var tied = document
        tied.recordings = document.recordings.map { row in
            Recording(
                id: row.id,
                childID: row.childID,
                referenceCorrect: row.referenceCorrect,
                appleCorrect: row.referenceCorrect,
                sarvamCorrect: row.referenceCorrect
            )
        }
        let report = try GateHarness.evaluate(tied)
        XCTAssertEqual(report.apple.agreement, report.sarvam.agreement)
        XCTAssertEqual(report.decision, .apple)
    }

    func test_MET27_percentileIndexes() {
        let lower = (25 * (GateHarness.bootstrapCount - 1)) / 1000
        let upper = (975 * (GateHarness.bootstrapCount - 1) + 999) / 1000
        XCTAssertEqual(lower, 249)
        XCTAssertEqual(upper, 9750)
    }

    func test_MET28_resamplesChildrenNotItems() throws {
        var recordings: [Recording] = []
        recordings.append(Recording(id: "good-0", childID: "good", referenceCorrect: true, appleCorrect: true, sarvamCorrect: true))
        for index in 0..<9 {
            recordings.append(Recording(id: "bad-\(index)", childID: "bad", referenceCorrect: true, appleCorrect: false, sarvamCorrect: false))
        }
        let report = try GateHarness.evaluate(GateDocument(cohort: ["good", "bad"], recordings: recordings))
        XCTAssertEqual(report.apple.agreement, Rational(1, 10))
        XCTAssertLessThan(report.apple.agreementCI.lower, report.apple.agreementCI.upper)
    }

    func test_MET30_falseAcceptBarIsOneInTwenty() {
        XCTAssertEqual(GateHarness.falseAcceptBar, Rational(1, 20))
    }

    func test_MET31_agreementBarIsNineInTen() {
        XCTAssertEqual(GateHarness.agreementBar, Rational(9, 10))
    }

    func test_MET32_falseRejectBarIsOneInTen() {
        XCTAssertEqual(GateHarness.falseRejectBar, Rational(1, 10))
    }

    func test_MET33_zeroReferenceIncorrectIsNotAFalseAccept() throws {
        XCTAssertEqual(try report("close_call").apple.falseAcceptRate, Rational(0, 1))
        XCTAssertEqual(try report("close_call").apple.referenceIncorrect, 0)
    }

    func test_MET34_sarvamFalseAcceptBlocksIt() throws {
        XCTAssertGreaterThan(try report("apple_pass").sarvam.falseAcceptCI.upper, GateHarness.falseAcceptBar)
    }

    func test_MET35_intervalsUseTheSameSeedForBothEngines() throws {
        let report = try report("no_go")
        XCTAssertEqual(report.apple.agreementCI, report.sarvam.agreementCI)
    }

    func test_MET36_reducedRationals() {
        XCTAssertEqual(Rational(2, 4).text, "1/2")
        XCTAssertEqual(Rational(100, 1000).text, "1/10")
    }

    func test_MET36d_negativeDenominatorFlipsTheSign() {
        XCTAssertEqual(Rational(1, -2), Rational(-1, 2))
    }

    func test_MET37_emptyCohortInputIsUnpaired() {
        XCTAssertThrowsError(try GateHarness.evaluate(GateDocument(cohort: [], recordings: []))) { error in
            XCTAssertEqual(error as? GateHarnessError, .unpairedRecording(recordingID: ""))
        }
    }

    private func report(_ name: String) throws -> GateReport {
        try GateHarness.evaluate(load(name))
    }

    private func load(_ name: String) throws -> GateDocument {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(GateDocument.self, from: Data(contentsOf: url))
    }

    private func golden(_ name: String) throws -> GoldenFile {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "\(name).golden", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(GoldenFile.self, from: Data(contentsOf: url))
    }

    private func assertEngine(_ actual: EngineReport, _ expected: GoldenEngine?, _ name: String) throws {
        let expected = try XCTUnwrap(expected, name)
        XCTAssertEqual(actual.paired, expected.paired, name)
        XCTAssertEqual(actual.agreements, expected.agreements, name)
        XCTAssertEqual(actual.falseAccepts, expected.falseAccepts, name)
        XCTAssertEqual(actual.referenceIncorrect, expected.referenceIncorrect, name)
        XCTAssertEqual(actual.falseRejects, expected.falseRejects, name)
        XCTAssertEqual(actual.referenceCorrect, expected.referenceCorrect, name)
        XCTAssertEqual(actual.agreement.text, expected.agreement, name)
        XCTAssertEqual(actual.falseAcceptRate.text, expected.falseAcceptRate, name)
        XCTAssertEqual(actual.falseRejectRate.text, expected.falseRejectRate, name)
        XCTAssertEqual(actual.agreementCI.lower.text, expected.agreementCI[0], name)
        XCTAssertEqual(actual.agreementCI.upper.text, expected.agreementCI[1], name)
        XCTAssertEqual(actual.falseAcceptCI.lower.text, expected.falseAcceptCI[0], name)
        XCTAssertEqual(actual.falseAcceptCI.upper.text, expected.falseAcceptCI[1], name)
        let perChild = actual.perChildFalseAccept.mapValues(\.text)
        XCTAssertEqual(perChild, expected.perChildFalseAccept, name)
    }
}

private struct GoldenFile: Decodable {
    var decision: String?
    var apple: GoldenEngine?
    var sarvam: GoldenEngine?
}

private struct GoldenEngine: Decodable {
    var paired: Int
    var agreements: Int
    var falseAccepts: Int
    var referenceIncorrect: Int
    var falseRejects: Int
    var referenceCorrect: Int
    var agreement: String
    var falseAcceptRate: String
    var falseRejectRate: String
    var perChildFalseAccept: [String: String]
    var agreementCI: [String]
    var falseAcceptCI: [String]
}
