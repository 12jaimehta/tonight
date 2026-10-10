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
        XCTAssertEqual(report.apple.perChildFalseAccept["c0"], .some(Rational(0, 1)))
        XCTAssertEqual(report.sarvam.perChildFalseAccept["c3"], .some(Rational(1, 1)))
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
        XCTAssertTrue(rates.values.allSatisfy { $0 == .some(Rational(1, 1)) })
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
        XCTAssertEqual(try report("close_call").decision, .apple)
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
        let names = [
            "apple_pass", "sarvam_pass", "no_go", "close_call",
            "exactly_090", "exactly_plus_5pp", "ci_includes_zero",
            "per_child_fa_cap", "per_child_fa_exact",
        ]
        for name in names {
            let golden = try golden(name)
            let actual = try report(name)
            XCTAssertEqual(actual.scoringVersion, try XCTUnwrap(golden.scoringVersion), name)
            XCTAssertEqual(GateHarness.scoringVersion, 2, name)
            XCTAssertEqual(actual.decision.rawValue, golden.decision, name)
            XCTAssertEqual(actual.deltaAgreement.text, try XCTUnwrap(golden.deltaAgreement), name)
            let deltaCI = try XCTUnwrap(golden.deltaCI, name)
            XCTAssertEqual(actual.deltaCI.lower.text, deltaCI[0], name)
            XCTAssertEqual(actual.deltaCI.upper.text, deltaCI[1], name)
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

    func test_MET36_appleFailsAndSarvamPassesSelectsSarvam() throws {
        let report = try report("met36")
        XCTAssertEqual(report.apple.agreement, Rational(17, 20))
        XCTAssertEqual(report.sarvam.agreement, Rational(97, 100))
        XCTAssertFalse(report.apple.passesBar)
        XCTAssertTrue(report.sarvam.passesBar)
        XCTAssertEqual(report.decision, .sarvam)
    }

    func test_MET36b_swappedSarvamPassFixtureSelectsSarvam() throws {
        XCTAssertEqual(try report("sarvam_pass").decision, .sarvam)
        XCTAssertTrue(try report("sarvam_pass").sarvam.passesBar)
        XCTAssertFalse(try report("sarvam_pass").apple.passesBar)
    }

    func test_MET34_worseSarvamFalseAcceptStaysApple() throws {
        let report = try report("met34")
        XCTAssertTrue(report.apple.passesBar)
        XCTAssertTrue(report.sarvam.passesBar)
        XCTAssertEqual(report.deltaAgreement, Rational(3, 50))
        XCTAssertGreaterThan(report.deltaCI.lower, Rational(0, 1))
        XCTAssertEqual(report.apple.falseAcceptRate, Rational(0, 1))
        XCTAssertEqual(report.sarvam.falseAcceptRate, Rational(1, 20))
        XCTAssertGreaterThan(report.sarvam.falseAcceptRate, report.apple.falseAcceptRate)
        XCTAssertEqual(report.decision, .apple)
    }

    func test_MET13_childWithNoAgeIsRejected() {
        XCTAssertThrowsError(try report("met13")) { error in
            XCTAssertEqual(error as? GateHarnessError, .outOfCohort(recordingID: "ageless"))
        }
    }

    func test_missingGoldenFailsTheRun() {
        let invented = Bundle.module.url(forResource: "not_a_golden.golden", withExtension: "json", subdirectory: "Fixtures")
        if invented != nil {
            XCTFail("a missing golden must not be treated as present")
        }
        for name in FixtureCatalog.requiredGoldens {
            let url = Bundle.module.url(forResource: "\(name).golden", withExtension: "json", subdirectory: "Fixtures")
            XCTAssertNotNil(url, "missing golden \(name) fails the run")
        }
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

    func test_MET02_exactlyNinetyPercentAgreementPasses() throws {
        let report = try report("exactly_090")
        XCTAssertEqual(report.apple.agreement, Rational(9, 10))
        XCTAssertEqual(report.apple.falseRejectRate, Rational(1, 10))
        XCTAssertLessThan(report.apple.agreementCI.lower, GateHarness.agreementBar)
        XCTAssertTrue(report.apple.passesBar)
        XCTAssertTrue(report.sarvam.passesBar)
        XCTAssertEqual(report.decision, .apple)
    }

    func test_MET04_thresholdIsGreaterThanOrEqual() throws {
        XCTAssertTrue(Rational(9, 10) >= GateHarness.agreementBar)
        XCTAssertTrue(Rational(1, 10) <= GateHarness.falseRejectBar)
        XCTAssertTrue(Rational(1, 20) <= GateHarness.falseAcceptBar)
        XCTAssertTrue(try report("exactly_090").apple.passesBar)
        XCTAssertTrue(try report("exactly_plus_5pp").apple.passesBar)
    }

    func test_MET06_perChildFalseAcceptCapFailsTheGate() throws {
        let report = try report("per_child_fa_cap")
        XCTAssertEqual(report.apple.falseAcceptRate, Rational(1, 20))
        XCTAssertLessThanOrEqual(report.apple.falseAcceptRate, GateHarness.falseAcceptBar)
        XCTAssertEqual(report.apple.perChildFalseAccept["over"], .some(Rational(1, 1)))
        XCTAssertFalse(report.apple.passesBar)
        XCTAssertFalse(report.sarvam.passesBar)
        XCTAssertEqual(report.decision, .noGo)
    }

    func test_MET07_childWithNoIncorrectWordsIsNotApplicable() throws {
        let report = try report("close_call")
        XCTAssertEqual(report.apple.referenceIncorrect, 0)
        XCTAssertEqual(report.apple.perChildFalseAccept["c00"], .some(nil))
        XCTAssertTrue(report.apple.perChildFalseAccept.values.allSatisfy { $0 == nil })
    }

    func test_MET20_exactTenPercentChildCapStillPasses() throws {
        let report = try report("per_child_fa_exact")
        XCTAssertEqual(report.apple.perChildFalseAccept["c00"], .some(Rational(1, 10)))
        XCTAssertEqual(report.apple.falseAcceptRate, Rational(1, 100))
        XCTAssertTrue(report.apple.passesBar)
        XCTAssertEqual(report.decision, .apple)
    }

    func test_MET21_oneChildOverTenPercentFalseAcceptFails() throws {
        let report = try report("per_child_fa_cap")
        XCTAssertEqual(report.decision, .noGo)
        let child = try XCTUnwrap(report.apple.perChildFalseAccept["over"] ?? nil)
        XCTAssertGreaterThan(child, GateHarness.childFalseAcceptCap)
    }

    func test_MET26_deltaIntervalExcludesZero() throws {
        let report = try report("exactly_plus_5pp")
        XCTAssertEqual(report.deltaAgreement, Rational(1, 20))
        XCTAssertGreaterThan(report.deltaCI.lower, Rational(0, 1))
        XCTAssertEqual(report.decision, .sarvam)
    }

    func test_MET27_deltaIntervalThatIncludesZeroStaysApple() throws {
        let report = try report("ci_includes_zero")
        XCTAssertEqual(report.deltaAgreement, Rational(1, 20))
        XCTAssertLessThan(report.deltaCI.lower, Rational(0, 1))
        XCTAssertGreaterThan(report.deltaCI.upper, Rational(0, 1))
        XCTAssertTrue(report.apple.passesBar)
        XCTAssertTrue(report.sarvam.passesBar)
        XCTAssertEqual(report.decision, .apple)
    }

    func test_MET30_twoPointGapDoesNotSelectSarvam() throws {
        var recordings: [Recording] = []
        for item in 0..<50 {
            recordings.append(Recording(
                id: "c-\(item)",
                childID: "c",
                referenceCorrect: true,
                appleCorrect: item < 45,
                sarvamCorrect: item < 46
            ))
        }
        let report = try GateHarness.evaluate(GateDocument(cohort: ["c"], recordings: recordings))
        XCTAssertEqual(report.apple.agreement, Rational(9, 10))
        XCTAssertEqual(report.sarvam.agreement, Rational(23, 25))
        XCTAssertEqual(report.deltaAgreement, Rational(1, 50))
        XCTAssertLessThan(report.deltaAgreement, GateHarness.sarvamMargin)
        XCTAssertEqual(report.decision, .apple)
    }

    func test_MET33_twoPointsIsNotEnoughForSarvam() throws {
        XCTAssertEqual(try report("close_call").decision, .apple)
        XCTAssertEqual(try report("close_call").deltaAgreement, Rational(1, 1000))
        XCTAssertLessThan(try report("close_call").deltaAgreement, GateHarness.sarvamMargin)
    }

    func test_MET37_ageAndClassMustMatchTheCohort() {
        XCTAssertThrowsError(try report("age_reject")) { error in
            XCTAssertEqual(error as? GateHarnessError, .cohortRejected(recordingID: "c00"))
        }
        XCTAssertThrowsError(try report("class_reject")) { error in
            XCTAssertEqual(error as? GateHarnessError, .cohortRejected(recordingID: "c00"))
        }
        let recording = Recording(
            id: "c-0",
            childID: "c",
            referenceCorrect: true,
            appleCorrect: true,
            sarvamCorrect: true,
            age: 7,
            schoolClass: "4"
        )
        let document = GateDocument(
            members: [CohortMember(id: "c", age: 7, schoolClass: "2")],
            recordings: [recording]
        )
        XCTAssertThrowsError(try GateHarness.evaluate(document)) { error in
            XCTAssertEqual(error as? GateHarnessError, .cohortRejected(recordingID: "c-0"))
        }
    }

    func test_HAR04_exactlyFivePointsSelectsSarvam() throws {
        let report = try report("exactly_plus_5pp")
        XCTAssertEqual(report.apple.agreement, Rational(9, 10))
        XCTAssertEqual(report.sarvam.agreement, Rational(19, 20))
        XCTAssertEqual(report.deltaAgreement, GateHarness.sarvamMargin)
        XCTAssertEqual(report.decision, .sarvam)
    }

    private func report(_ name: String) throws -> GateReport {
        try GateHarness.evaluate(load(name))
    }

    private func load(_ name: String) throws -> GateDocument {
        if let built = FixtureCatalog.build(name) {
            return built
        }
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name) fails the run"
        )
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
        let perChild = actual.perChildFalseAccept.mapValues { $0?.text ?? "n/a" }
        XCTAssertEqual(perChild, expected.perChildFalseAccept, name)
    }
}

/// Seeds for the large cohorts. The expansion rules are in Fixtures/SCHEMA.md.
private enum FixtureCatalog {
    static let requiredGoldens = [
        "apple_pass", "sarvam_pass", "no_go", "close_call",
        "exactly_090", "exactly_plus_5pp", "ci_includes_zero",
        "per_child_fa_cap", "per_child_fa_exact",
        "unpaired", "out_of_cohort", "age_reject", "class_reject",
    ]

    static func build(_ name: String) -> GateDocument? {
        switch name {
        case "apple_pass": return applePass(swap: false)
        case "sarvam_pass": return applePass(swap: true)
        case "no_go": return rows(children: 4, items: 10, appleCorrect: 4, sarvamCorrect: 4)
        case "close_call": return rows(children: 4, items: 1000, appleCorrect: 900, sarvamCorrect: 901)
        case "exactly_090": return exactlyNinety()
        case "exactly_plus_5pp": return rows(children: 4, items: 20, appleCorrect: 18, sarvamCorrect: 19)
        case "ci_includes_zero": return ciIncludesZero()
        case "per_child_fa_cap": return perChildCap()
        case "per_child_fa_exact": return perChildExact()
        case "unpaired": return unpaired()
        case "out_of_cohort": return outOfCohort()
        case "age_reject": return demographic(age: 9, schoolClass: "2")
        case "class_reject": return demographic(age: 7, schoolClass: "5")
        default: return nil
        }
    }

    private static func rows(children: Int, items: Int, appleCorrect: Int, sarvamCorrect: Int, reference: Bool = true) -> GateDocument {
        var cohort: [String] = []
        var recordings: [Recording] = []
        for childIndex in 0..<children {
            let child = String(format: "c%02d", childIndex)
            cohort.append(child)
            for item in 0..<items {
                recordings.append(Recording(
                    id: "\(child)-\(item)",
                    childID: child,
                    referenceCorrect: reference,
                    appleCorrect: item < appleCorrect,
                    sarvamCorrect: item < sarvamCorrect
                ))
            }
        }
        return GateDocument(cohort: cohort, recordings: recordings)
    }

    private static func applePass(swap: Bool) -> GateDocument {
        var cohort: [String] = []
        var recordings: [Recording] = []
        for childIndex in 0..<8 {
            let child = "c\(childIndex)"
            cohort.append(child)
            for item in 0..<8 {
                let reference = item < 6
                let apple = swap ? true : reference
                let sarvam = swap ? reference : true
                recordings.append(Recording(
                    id: "\(child)-\(item)",
                    childID: child,
                    referenceCorrect: reference,
                    appleCorrect: apple,
                    sarvamCorrect: sarvam
                ))
            }
        }
        return GateDocument(cohort: cohort, recordings: recordings)
    }

    private static func exactlyNinety() -> GateDocument {
        var cohort: [String] = []
        var recordings: [Recording] = []
        for childIndex in 0..<20 {
            let child = String(format: "c%02d", childIndex)
            cohort.append(child)
            let correct = childIndex % 2 == 0 ? 47 : 43
            for item in 0..<50 {
                let heard = item < correct
                recordings.append(Recording(
                    id: "\(child)-\(item)",
                    childID: child,
                    referenceCorrect: true,
                    appleCorrect: heard,
                    sarvamCorrect: heard
                ))
            }
        }
        return GateDocument(cohort: cohort, recordings: recordings)
    }

    private static func ciIncludesZero() -> GateDocument {
        var cohort: [String] = []
        var recordings: [Recording] = []
        for childIndex in 0..<10 {
            let child = String(format: "c%02d", childIndex)
            cohort.append(child)
            let sarvamCorrect = childIndex == 9 ? 10 : 20
            for item in 0..<20 {
                recordings.append(Recording(
                    id: "\(child)-\(item)",
                    childID: child,
                    referenceCorrect: true,
                    appleCorrect: item < 18,
                    sarvamCorrect: item < sarvamCorrect
                ))
            }
        }
        return GateDocument(cohort: cohort, recordings: recordings)
    }

    private static func perChildCap() -> GateDocument {
        var recordings: [Recording] = []
        for item in 0..<19 {
            recordings.append(Recording(
                id: "good-\(item)",
                childID: "good",
                referenceCorrect: false,
                appleCorrect: false,
                sarvamCorrect: false
            ))
        }
        recordings.append(Recording(
            id: "over-0",
            childID: "over",
            referenceCorrect: false,
            appleCorrect: true,
            sarvamCorrect: true
        ))
        return GateDocument(cohort: ["good", "over"], recordings: recordings)
    }

    private static func perChildExact() -> GateDocument {
        var cohort: [String] = []
        var recordings: [Recording] = []
        for childIndex in 0..<10 {
            let child = String(format: "c%02d", childIndex)
            cohort.append(child)
            for item in 0..<10 {
                let falseAccept = childIndex == 0 && item == 0
                recordings.append(Recording(
                    id: "\(child)-\(item)",
                    childID: child,
                    referenceCorrect: false,
                    appleCorrect: falseAccept,
                    sarvamCorrect: falseAccept
                ))
            }
        }
        return GateDocument(cohort: cohort, recordings: recordings)
    }

    private static func unpaired() -> GateDocument {
        var document = rows(children: 1, items: 1, appleCorrect: 1, sarvamCorrect: 1)
        let row = document.recordings[0]
        document.recordings[0] = Recording(
            id: row.id,
            childID: row.childID,
            referenceCorrect: row.referenceCorrect,
            appleCorrect: row.appleCorrect,
            sarvamCorrect: nil
        )
        return document
    }

    private static func outOfCohort() -> GateDocument {
        var document = rows(children: 1, items: 1, appleCorrect: 1, sarvamCorrect: 1)
        document.cohort = [CohortMember(id: "someone-else")]
        return document
    }

    private static func demographic(age: Int, schoolClass: String) -> GateDocument {
        var document = rows(children: 1, items: 1, appleCorrect: 1, sarvamCorrect: 1)
        document.cohort = [CohortMember(id: "c00", age: age, schoolClass: schoolClass, demographic: true)]
        let row = document.recordings[0]
        document.recordings[0] = Recording(
            id: row.id,
            childID: row.childID,
            referenceCorrect: row.referenceCorrect,
            appleCorrect: row.appleCorrect,
            sarvamCorrect: row.sarvamCorrect,
            age: age,
            schoolClass: schoolClass
        )
        return document
    }
}

private struct GoldenFile: Decodable {
    var scoringVersion: Int?
    var decision: String?
    var deltaAgreement: String?
    var deltaCI: [String]?
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
