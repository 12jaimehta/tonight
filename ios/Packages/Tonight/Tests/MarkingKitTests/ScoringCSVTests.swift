import XCTest
@testable import MarkingKit

final class ScoringCSVTests: XCTestCase {
    func testEveryCSVRow() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "scoring_test_cases", withExtension: "csv", subdirectory: "Fixtures")
        )
        let rows = try parseCSV(String(contentsOf: url, encoding: .utf8))
        let cases = rows.dropFirst().filter { $0.count >= 8 && !$0[0].isEmpty }
        XCTAssertGreaterThanOrEqual(cases.count, 98, "SC-53 expects every scoring_test_cases.csv row")

        for columns in cases {
            let id = columns[0]
            let questionType = columns[2]
            let settings = columns[3]
            let expectedAnswer = columns[4]
            let child = columns[5]
            let expectedResult = columns[6]
            let expectedPoints = Decimal(string: columns[7], locale: Locale(identifier: "en_US_POSIX"))

            if questionType == "homework_total" {
                let label = AnswerScorer.homeworkDisplay(expected: expectedAnswer)
                XCTAssertEqual(expectedResult, "display \(label)", id)
                let score = AnswerScorer.score(
                    expected: expectedAnswer,
                    child: "—",
                    questionType: questionType,
                    settings: settings
                )
                XCTAssertEqual(score.points, expectedPoints ?? 0, accuracy: decimal("0.0002"), id)
                continue
            }

            let score = AnswerScorer.score(
                expected: expectedAnswer,
                child: child,
                questionType: questionType,
                settings: settings
            )
            XCTAssertEqual(score.result.rawValue, expectedResult, id)
            XCTAssertEqual(score.points, expectedPoints ?? -1, accuracy: decimal("0.0002"), id)
        }
    }

    func testDecimalCommaDoesNotDependOnAPassedLocale() {
        let german = AnswerScorer.score(expected: "3.5", child: "3,5", questionType: "decimal", settings: "locale=de_DE")
        let india = AnswerScorer.score(expected: "3.5", child: "3,5", questionType: "decimal", settings: "locale=en_IN")
        let arabic = AnswerScorer.score(expected: "3.5", child: "3,5", questionType: "decimal", settings: "locale=ar_SA")
        XCTAssertEqual(german, india)
        XCTAssertEqual(india, arabic)
        XCTAssertEqual(german.result, .needsReview)
    }
}

private func decimal(_ text: String) -> Decimal {
    Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
}

private func XCTAssertEqual(
    _ actual: Decimal,
    _ expected: Decimal,
    accuracy: Decimal,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let delta = actual > expected ? actual - expected : expected - actual
    XCTAssertLessThanOrEqual(delta, accuracy, "\(message): \(actual) != \(expected)", file: file, line: line)
}

private func parseCSV(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var inQuotes = false
    let scalars = Array(text.unicodeScalars)
    var index = 0
    while index < scalars.count {
        let scalar = scalars[index]
        if inQuotes {
            if scalar == "\"" {
                if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                    field.unicodeScalars.append("\"")
                    index += 2
                    continue
                }
                inQuotes = false
            } else {
                field.unicodeScalars.append(scalar)
            }
        } else if scalar == "\"" {
            inQuotes = true
        } else if scalar == "," {
            row.append(field)
            field = ""
        } else if scalar == "\n" {
            row.append(field)
            field = ""
            rows.append(row)
            row = []
        } else if scalar != "\r" {
            field.unicodeScalars.append(scalar)
        }
        index += 1
    }
    if !field.isEmpty || !row.isEmpty {
        row.append(field)
        rows.append(row)
    }
    return rows
}
