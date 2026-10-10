import XCTest
@testable import GateHarness

final class GateHarnessTests: XCTestCase {
    func testDecisionCodesAreAppleSarvamOrNoGo() {
        XCTAssertEqual(GateDecision.allCases.map(\.rawValue), ["APPLE", "SARVAM", "NO_GO"])
        XCTAssertEqual(GateHarness.bootstrapCount, 10_000)
        XCTAssertEqual(GateHarness.seed, 20_261_009)
        XCTAssertEqual(GateHarness.agreementBar, Rational(9, 10))
        XCTAssertEqual(GateHarness.falseAcceptBar, Rational(1, 20))
        XCTAssertEqual(GateHarness.falseRejectBar, Rational(1, 10))
        XCTAssertEqual(GateHarness.childFalseAcceptCap, Rational(1, 10))
        XCTAssertEqual(GateHarness.sarvamMargin, Rational(5, 100))
    }

    func test_PMRule7_nineInRangeAgeClassCombinations() throws {
        let warned: Set<String> = ["1-8", "3-6"]
        for schoolClass in 1...3 {
            for age in 6...8 {
                let report = try evaluate(study([
                    child("c1", age: age, schoolClass: schoolClass, cells: passingCells()),
                ]))
                let key = "\(schoolClass)-\(age)"
                XCTAssertNotEqual(report.decision, .noGo, key)
                XCTAssertEqual(report.decision, .apple, key)
                if warned.contains(key) {
                    let expectedAge = schoolClass + 5
                    XCTAssertEqual(report.warnings, [
                        "child c1 age \(age) is paired with class \(schoolClass); expected age \(expectedAge) ± 1",
                    ], key)
                } else {
                    XCTAssertEqual(report.warnings, [], key)
                }
                let document = report.dictionary()
                XCTAssertEqual(document["warnings"] as? [String], report.warnings, key)
                XCTAssertEqual(document["decision"] as? String, "APPLE", key)
                XCTAssertEqual(document["schema_version"] as? Int, 1, key)
            }
        }
    }

    func test_MET28_missingAppleCorrectIsExcluded() throws {
        var cells = passingCells()
        cells.append([
            "reference_correct": true,
            "sarvam_correct": true,
            "n": 7,
        ])
        let report = try evaluate(study([
            child("c1", age: 7, schoolClass: 2, cells: cells),
        ]))
        XCTAssertEqual(report.decision, .apple)
        XCTAssertEqual(report.apple.words, 100)
        XCTAssertEqual(report.sarvam.words, 100)
        XCTAssertEqual(report.apple.falseRejects, 0)
        XCTAssertEqual(report.apple.falseAccepts, 0)
        XCTAssertEqual(report.sarvam.falseRejects, 0)
        XCTAssertEqual(report.sarvam.falseAccepts, 0)
    }

    func test_MET28_missingSarvamCorrectIsExcluded() throws {
        var cells = passingCells()
        cells.append([
            "reference_correct": false,
            "apple_correct": true,
            "n": 3,
        ])
        let report = try evaluate(study([
            child("c1", age: 7, schoolClass: 2, cells: cells),
        ]))
        XCTAssertEqual(report.decision, .apple)
        XCTAssertEqual(report.apple.words, 100)
        XCTAssertEqual(report.apple.falseAccepts, 0)
        XCTAssertEqual(report.sarvam.words, 100)
        XCTAssertEqual(report.sarvam.falseAccepts, 0)
    }

    func test_MET28_nullEngineCallIsExcluded() throws {
        var cells = passingCells()
        cells.append([
            "reference_correct": true,
            "apple_correct": NSNull(),
            "sarvam_correct": false,
            "n": 4,
        ])
        let report = try evaluate(study([
            child("c1", age: 7, schoolClass: 2, cells: cells),
        ]))
        XCTAssertEqual(report.decision, .apple)
        XCTAssertEqual(report.apple.words, 100)
        XCTAssertEqual(report.apple.falseRejects, 0)
        XCTAssertEqual(report.sarvam.words, 100)
        XCTAssertEqual(report.sarvam.falseRejects, 0)
    }

    func test_MET28_recordingBecomesUnpairedAfterDroppedWords() throws {
        let dropped = study([[
            "child_id": "c1",
            "age": 7,
            "school_class": 2,
            "recordings": [[
                "recording_id": "c1-passage",
                "words": [
                    ["reference_correct": true, "sarvam_correct": true],
                    ["reference_correct": false, "apple_correct": NSNull(), "sarvam_correct": false],
                    ["reference_correct": true, "apple_correct": false],
                ],
            ]],
        ]])
        XCTAssertEqual(code(of: dropped), "UNPAIRED_RECORDING")
        XCTAssertNotEqual(code(of: dropped), "DECIDED")
        XCTAssertEqual(try code(ofFile: "met28"), "UNPAIRED_RECORDING")
    }

    func test_OUT_OF_COHORT_missingOrOutOfRangeAgeOrClass() throws {
        XCTAssertEqual(code(of: study([child("c1", age: nil, schoolClass: 1, cells: passingCells())])), "OUT_OF_COHORT")
        XCTAssertEqual(code(of: study([child("c1", age: 9, schoolClass: 1, cells: passingCells())])), "OUT_OF_COHORT")
        XCTAssertEqual(code(of: study([child("c1", age: 5, schoolClass: 1, cells: passingCells())])), "OUT_OF_COHORT")
        XCTAssertEqual(code(of: study([child("c1", age: 7, schoolClass: nil, cells: passingCells())])), "OUT_OF_COHORT")
        XCTAssertEqual(code(of: study([child("c1", age: 7, schoolClass: 4, cells: passingCells())])), "OUT_OF_COHORT")
        XCTAssertEqual(try code(ofFile: "met13"), "OUT_OF_COHORT")
    }

    func test_INVALID_STUDY_zeroPooledDenominatorNeverPasses() {
        let noIncorrect = study([
            child("c1", age: 6, schoolClass: 1, cells: [
                cell(true, true, true, 36),
            ]),
        ])
        XCTAssertEqual(code(of: noIncorrect), "INVALID_STUDY")
        let noCorrect = study([
            child("c1", age: 6, schoolClass: 1, cells: [
                cell(false, false, false, 20),
            ]),
        ])
        XCTAssertEqual(code(of: noCorrect), "INVALID_STUDY")
    }

    func test_seedIsLoggedOnTheReport() throws {
        let report = try evaluate(study([
            child("c1", age: 7, schoolClass: 2, cells: passingCells()),
        ]))
        XCTAssertEqual(report.seed, 20_261_009)
        XCTAssertEqual(report.interval.seed, 20_261_009)
        XCTAssertEqual(report.interval.resamples, 10_000)
        let document = report.dictionary()
        XCTAssertEqual(document["seed"] as? Int, 20_261_009)
        let interval = document["interval"] as? [String: Any]
        XCTAssertEqual(interval?["seed"] as? Int, 20_261_009)
        XCTAssertEqual(interval?["resamples"] as? Int, 10_000)
        XCTAssertEqual(interval?["generator"] as? String, "random.Random")
        XCTAssertEqual(interval?["method"] as? String, "paired child-cluster bootstrap, Hyndman-Fan type 7 percentile")
    }

    func test_falseRejectExcludesRecordingsWithNoReferenceCorrectWords() throws {
        let report = try evaluate(study([
            child("c1", age: 7, schoolClass: 2, recordings: [
                recording("with-correct", cells: [
                    cell(true, true, true, 8),
                    cell(false, false, false, 2),
                ]),
                recording("no-correct", cells: [
                    cell(false, false, false, 4),
                ]),
                recording("no-incorrect", cells: [
                    cell(true, true, true, 5),
                ]),
            ]),
        ]))
        XCTAssertEqual(report.apple.referenceCorrect, 13)
        XCTAssertEqual(report.apple.falseRejects, 0)
        XCTAssertEqual(report.apple.falseRejectRate, Rational(0, 13))
        XCTAssertEqual(report.apple.referenceIncorrect, 6)
        XCTAssertEqual(report.apple.falseAccepts, 0)
        XCTAssertEqual(report.apple.falseAcceptRate, Rational(0, 6))
        XCTAssertTrue(report.apple.passes)
    }

    func test_falseAcceptSkipsChildrenWithNoReferenceIncorrectWords() throws {
        let report = try evaluate(study([
            child("skipped", age: 6, schoolClass: 1, cells: [
                cell(true, true, true, 20),
            ]),
            child("capped", age: 8, schoolClass: 3, cells: [
                cell(true, true, true, 90),
                cell(false, false, false, 19),
                cell(false, true, true, 1),
            ]),
        ]))
        let skipped = try XCTUnwrap(report.apple.perChildFalseAccept.first { $0.childID == "skipped" })
        XCTAssertNil(skipped.rate)
        XCTAssertEqual(skipped.referenceIncorrect, 0)
        XCTAssertTrue(skipped.withinCap)
        let capped = try XCTUnwrap(report.apple.perChildFalseAccept.first { $0.childID == "capped" })
        XCTAssertEqual(capped.rate, Rational(1, 20))
        XCTAssertTrue(capped.withinCap)
        XCTAssertEqual(report.apple.falseAcceptRate, Rational(1, 20))
        XCTAssertNotEqual(report.decision, .noGo)
    }

    /// The earlier all-correct MET-36 fixture has a zero false-accept denominator, so it is INVALID_STUDY.
    /// This file is the only-Sarvam case with both denominators defined.
    func test_MET36_onlySarvamPassesSelectsSarvam() throws {
        let report = try evaluate(file: "met36")
        XCTAssertFalse(report.apple.passes)
        XCTAssertTrue(report.sarvam.passes)
        XCTAssertEqual(report.apple.agreement, Rational(105, 120))
        XCTAssertEqual(report.sarvam.agreement, Rational(117, 120))
        XCTAssertEqual(report.decision, .sarvam)
    }

    func test_MET34_worseFalseAcceptStaysApple() throws {
        let report = try evaluate(file: "met34")
        XCTAssertTrue(report.apple.passes)
        XCTAssertTrue(report.sarvam.passes)
        XCTAssertEqual(report.agreementDelta, Rational(6, 100))
        XCTAssertGreaterThan(report.interval.low, Rational(0, 1))
        XCTAssertEqual(report.apple.falseAcceptRate, Rational(0, 1))
        XCTAssertEqual(report.sarvam.falseAcceptRate, Rational(1, 20))
        XCTAssertGreaterThan(report.sarvam.falseAcceptRate ?? Rational(0, 1), report.apple.falseAcceptRate ?? Rational(0, 1))
        XCTAssertEqual(report.decision, .apple)
    }

    func testExactlyFivePointsSelectsSarvam() throws {
        let report = try evaluate(study([
            child("c1", age: 7, schoolClass: 2, cells: [
                cell(true, true, true, 180),
                cell(true, false, true, 12),
                cell(true, false, false, 8),
                cell(false, false, false, 40),
            ]),
        ]))
        XCTAssertEqual(report.agreementDelta, Rational(1, 20))
        XCTAssertEqual(report.interval.low, Rational(1, 20))
        XCTAssertEqual(report.interval.high, Rational(1, 20))
        XCTAssertEqual(report.decision, .sarvam)
    }

    func testPooledFalseAcceptTiePasses() throws {
        let report = try evaluate(study([
            child("c1", age: 7, schoolClass: 2, cells: [
                cell(true, true, true, 80),
                cell(false, false, false, 19),
                cell(false, true, true, 1),
            ]),
        ]))
        XCTAssertEqual(report.apple.falseAcceptRate, Rational(1, 20))
        XCTAssertTrue(report.apple.passes)
        XCTAssertEqual(report.decision, .apple)
    }

    func testChildFalseAcceptCapIsNoGo() throws {
        let report = try evaluate(study([
            child("c1", age: 6, schoolClass: 1, cells: [
                cell(true, true, true, 40),
                cell(false, false, false, 49),
                cell(false, true, true, 1),
            ]),
            child("c2", age: 8, schoolClass: 3, cells: [
                cell(true, true, true, 40),
                cell(false, true, true, 1),
            ]),
        ]))
        XCTAssertFalse(report.apple.passes)
        XCTAssertEqual(report.decision, .noGo)
    }

    func testBootstrapIntervalUsesTheLoggedSeed() throws {
        let report = try evaluate(study([
            child("a", age: 6, schoolClass: 1, cells: [
                cell(true, true, true, 4),
                cell(true, false, true, 2),
                cell(true, false, false, 2),
                cell(false, false, false, 2),
            ]),
            child("b", age: 8, schoolClass: 3, cells: [
                cell(true, true, true, 4),
                cell(true, true, false, 2),
                cell(true, false, false, 2),
                cell(false, false, false, 2),
            ]),
        ]))
        XCTAssertEqual(report.seed, GateHarness.seed)
        XCTAssertEqual(report.interval.low, Rational(-1, 5))
        XCTAssertEqual(report.interval.high, Rational(1, 5))
    }

    func testLargeCohortIsGeneratedAtTestTime() throws {
        var children: [[String: Any]] = []
        for index in 0..<40 {
            let age = [6, 7, 8][index % 3]
            let schoolClass = [1, 2, 3][index % 3]
            children.append(child("c\(index)", age: age, schoolClass: schoolClass, cells: passingCells()))
        }
        let report = try evaluate(study(children))
        XCTAssertEqual(report.warnings, [])
        XCTAssertEqual(report.seed, GateHarness.seed)
        XCTAssertEqual(report.apple.words, 40 * 100)
        XCTAssertEqual(report.decision, .apple)
        XCTAssertEqual(report.interval.low, report.agreementDelta)
        XCTAssertEqual(report.interval.high, report.agreementDelta)
    }

    func test_missingGoldenFailsTheRun() {
        let invented = Bundle.module.url(forResource: "not_a_golden.golden", withExtension: "json", subdirectory: "Fixtures")
        if invented != nil {
            XCTFail("a missing golden must not be treated as present")
        }
        for name in [
            "apple_pass", "sarvam_pass", "no_go", "close_call",
            "exactly_090", "exactly_plus_5pp", "ci_includes_zero",
            "per_child_fa_cap", "per_child_fa_exact",
            "unpaired", "out_of_cohort", "age_reject", "class_reject",
        ] {
            let url = Bundle.module.url(forResource: "\(name).golden", withExtension: "json", subdirectory: "Fixtures")
            XCTAssertNil(url, "round-2 golden \(name) is not an expected result")
        }
    }

    private func evaluate(file name: String) throws -> GateReport {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try GateHarness.evaluate(Data(contentsOf: url))
    }

    private func code(ofFile name: String) throws -> String {
        do {
            _ = try evaluate(file: name)
            return "DECIDED"
        } catch let error as GateHarnessError {
            return error.code
        } catch {
            return "THREW"
        }
    }

    private func evaluate(_ document: [String: Any]) throws -> GateReport {
        try GateHarness.evaluate(object: document)
    }

    private func code(of document: [String: Any]) -> String {
        do {
            _ = try evaluate(document)
            return "DECIDED"
        } catch let error as GateHarnessError {
            return error.code
        } catch {
            return "THREW"
        }
    }

    private func study(_ children: [[String: Any]]) -> [String: Any] {
        ["schema_version": 1, "children": children]
    }

    private func child(_ id: String, age: Int?, schoolClass: Int?, cells: [[String: Any]]) -> [String: Any] {
        child(id, age: age, schoolClass: schoolClass, recordings: [recording("\(id)-passage", cells: cells)])
    }

    private func child(_ id: String, age: Int?, schoolClass: Int?, recordings: [[String: Any]]) -> [String: Any] {
        var body: [String: Any] = [
            "child_id": id,
            "recordings": recordings,
        ]
        if let age { body["age"] = age }
        if let schoolClass { body["school_class"] = schoolClass }
        return body
    }

    private func recording(_ id: String, cells: [[String: Any]]) -> [String: Any] {
        ["recording_id": id, "cells": cells]
    }

    private func cell(_ reference: Bool, _ apple: Bool, _ sarvam: Bool, _ count: Int) -> [String: Any] {
        [
            "reference_correct": reference,
            "apple_correct": apple,
            "sarvam_correct": sarvam,
            "n": count,
        ]
    }

    private func passingCells() -> [[String: Any]] {
        [
            cell(true, true, true, 90),
            cell(false, false, false, 10),
        ]
    }
}
