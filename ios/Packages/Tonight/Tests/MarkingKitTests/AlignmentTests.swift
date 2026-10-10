import XCTest
@testable import MarkingKit

final class AlignmentTests: XCTestCase {
    private let marker = Marker()

    func testSkippedDistinctLineIsNeverCountedCorrect() {
        let mark = marker.mark(expected: "Birds fly south. The cat sat.", heard: "the cat sat")
        XCTAssertEqual(mark.correct, 3)
        XCTAssertEqual(mark.total, 6)
        let matched = Set(mark.words.filter { $0.status == .matched }.compactMap(\.expected))
        XCTAssertFalse(matched.contains("birds"))
        XCTAssertFalse(matched.contains("fly"))
        XCTAssertFalse(matched.contains("south"))
        XCTAssertEqual(mark.missed.prefix(3), ["birds", "fly", "south"])
    }

    func testRepeatedWordNeedsAnotherOccurrence() {
        let mark = marker.mark(expected: "the the", heard: "the")
        XCTAssertEqual(mark.correct, 1)
        XCTAssertEqual(mark.total, 2)
        XCTAssertEqual(mark.words.filter { $0.status == .matched }.count, 1)
    }

    func testOutOfOrderIsNotAFullMark() {
        let mark = marker.mark(expected: "alpha beta", heard: "beta alpha")
        XCTAssertEqual(mark.correct, 1)
        XCTAssertLessThan(mark.correct, mark.total)
    }

    func testPunctuationCaseAndNumerals() {
        XCTAssertEqual(marker.mark(expected: "Hello, world!", heard: "hello world").correct, 2)
        let numbers = marker.mark(expected: "I have 7 pens", heard: "i have seven pens")
        XCTAssertEqual(numbers.correct, numbers.total)
        XCTAssertEqual(numbers.percent, 100)
    }

    func test_P15_sentenceDecimalNumberWordAndOrdinal() {
        XCTAssertEqual(ReadingNormalizer.tokens(in: "It costs 3.5."), ["it", "costs", "3.5"])
        XCTAssertEqual(ReadingNormalizer.tokens(in: "3.5."), ["3.5"])
        XCTAssertEqual(ReadingNormalizer.tokens(in: "twenty five"), ["25"])
        XCTAssertEqual(ReadingNormalizer.tokens(in: "twenty-five"), ["25"])
        XCTAssertEqual(ReadingNormalizer.tokens(in: "3rd"), ["3rd"])
        XCTAssertEqual(ReadingNormalizer.tokens(in: "1st, 2nd and 4th."), ["1st", "2nd", "and", "4th"])
        let sentence = marker.mark(expected: "It costs 3.5.", heard: "it costs 3.5")
        XCTAssertEqual(sentence.correct, sentence.total)
        let words = marker.mark(expected: "twenty five", heard: "25")
        XCTAssertEqual(words.correct, 1)
        XCTAssertEqual(words.total, 1)
        let ordinal = marker.mark(expected: "3rd", heard: "third")
        XCTAssertEqual(ordinal.correct, ordinal.total)
        let cardinal = marker.mark(expected: "3rd", heard: "three")
        XCTAssertLessThan(cardinal.correct, cardinal.total)
        let comma = AnswerScorer.score(expected: "3.5", child: "3,5", questionType: "decimal", settings: "locale=en_IN")
        XCTAssertEqual(comma.result, .needsReview)
    }

    func test_N20_thirdMatches3rdThroughThirtyFirst() throws {
        let words = [
            "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
            "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth",
            "eighteenth", "nineteenth", "twentieth", "twenty-first", "twenty-second", "twenty-third",
            "twenty-fourth", "twenty-fifth", "twenty-sixth", "twenty-seventh", "twenty-eighth",
            "twenty-ninth", "thirtieth", "thirty-first",
        ]
        let digits = (1...31).map { value -> String in
            let suffix: String
            switch value {
            case 1, 21, 31: suffix = "st"
            case 2, 22: suffix = "nd"
            case 3, 23: suffix = "rd"
            default: suffix = "th"
            }
            return "\(value)\(suffix)"
        }
        XCTAssertEqual(words.count, 31)
        for (word, digit) in zip(words, digits) {
            XCTAssertEqual(ReadingNormalizer.tokens(in: word), [digit], word)
            XCTAssertEqual(ReadingNormalizer.tokens(in: digit), [digit], digit)
            let mark = marker.mark(expected: digit, heard: word)
            XCTAssertEqual(mark.correct, mark.total, "\(digit) vs \(word)")
        }
        XCTAssertEqual(ReadingNormalizer.tokens(in: "twenty first"), ["21st"])
        XCTAssertEqual(ReadingNormalizer.tokens(in: "thirty first"), ["31st"])
        XCTAssertEqual(ReadingNormalizer.tokens(in: "3rd"), ReadingNormalizer.tokens(in: "third"))
        XCTAssertNotEqual(ReadingNormalizer.tokens(in: "3rd"), ReadingNormalizer.tokens(in: "three"))
        XCTAssertNotEqual(ReadingNormalizer.tokens(in: "3rd"), ReadingNormalizer.tokens(in: "3"))
        XCTAssertEqual(ReadingNormalizer.tokens(in: "It costs 3.5."), ["it", "costs", "3.5"])
        XCTAssertEqual(ReadingNormalizer.tokens(in: "3.5."), ["3.5"])
        XCTAssertEqual(ReadingNormalizer.tokens(in: "twenty five"), ["25"])
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MarkingKit/Normalizer.swift"), encoding: .utf8)
        XCTAssertFalse(source.contains("Locale.current"))
        XCTAssertTrue(source.contains("en_US_POSIX"))
    }

    func testPrototypeTokenizerBugsStayFixed() {
        XCTAssertEqual(ReadingNormalizer.tokens(in: "1,00,000"), ["100000"])
        XCTAssertEqual(ReadingNormalizer.tokens(in: "3.5"), ["3.5"])
        XCTAssertEqual(ReadingNormalizer.tokens(in: "Don't"), ["dont"])
        XCTAssertEqual(ReadingNormalizer.tokens(in: "dont"), ["dont"])
        XCTAssertEqual(ReadingNormalizer.tokens(in: "किताब"), ["किताब"])
        XCTAssertEqual(ReadingNormalizer.tokens(in: "किताब पढ़ो"), ["किताब", "पढ़ो"])
        let hindi = marker.mark(expected: "किताब पढ़ो", heard: "किताब पढ़ो")
        XCTAssertEqual(hindi.correct, 2)
    }

    func testFuzzyMatchIsOffByDefault() {
        let mark = marker.mark(expected: "plant", heard: "plent")
        XCTAssertEqual(mark.correct, 0)
        XCTAssertEqual(mark.words.first?.status, .substituted)
        let fuzzy = marker.mark(expected: "plant", heard: "plent", options: MarkerOptions(fuzzyMatch: true))
        XCTAssertEqual(fuzzy.correct, 1)
    }

    func testMarkCarriesScoringVersionAndMissedWords() {
        let mark = marker.mark(expected: "the cat sat", heard: "the sat", options: MarkerOptions(asrEngine: "apple_on_device"))
        XCTAssertEqual(mark.scoringVersion, Mark.currentScoringVersion)
        XCTAssertEqual(mark.strategyID, "word-alignment")
        XCTAssertEqual(mark.source, .auto)
        XCTAssertEqual(mark.asrEngine, "apple_on_device")
        XCTAssertEqual(mark.correct, 2)
        XCTAssertEqual(mark.total, 3)
        XCTAssertEqual(mark.percent, 67)
        XCTAssertEqual(mark.missed, ["cat"])
    }

    func testEmptyPassageDoesNotDivideByZero() {
        let mark = marker.mark(expected: "...", heard: "hello")
        XCTAssertEqual(mark.total, 0)
        XCTAssertNil(mark.percent)
    }

    func testDisplayRoundingHalfUpAndNeverFalse100() {
        XCTAssertEqual(DisplayRounding.percentLabel(correct: 2, total: 3), "67%")
        XCTAssertEqual(DisplayRounding.percentLabel(correct: 1, total: 8), "13%")
        XCTAssertEqual(DisplayRounding.percentLabel(correct: 199, total: 200), "99%")
        XCTAssertEqual(DisplayRounding.percentLabel(correct: 0, total: 0), "—")
        XCTAssertEqual(DisplayRounding.percentLabel(correct: 3, total: 3), "100%")
    }

    func testNormaliserIsIdempotent() {
        let samples = ["Don't run", "1,00,000", "किताब पढ़ो", "Hello, world!", "I have 7 pens"]
        for sample in samples {
            let once = ReadingNormalizer.tokens(in: sample)
            let twice = ReadingNormalizer.tokens(in: once.joined(separator: " "))
            XCTAssertEqual(once, twice, sample)
        }
    }

    func testThreeHundredWordsStayUnderFiftyMilliseconds() {
        let words = (0..<300).map { "word\($0)" }
        let passage = words.joined(separator: " ")
        let heard = words.enumerated().filter { $0.offset % 4 != 0 }.map(\.element).joined(separator: " ")
        _ = marker.mark(expected: passage, heard: heard)
        var best = TimeInterval.greatestFiniteMagnitude
        for _ in 0..<30 {
            let start = Date()
            let mark = marker.mark(expected: passage, heard: heard)
            best = min(best, Date().timeIntervalSince(start))
            XCTAssertEqual(mark.total, 300)
        }
        XCTAssertLessThan(best, 0.05, "T-003 requires 300 words in under 50 ms")
    }

    func testInjectedStrategyIsUsed() {
        let marker = Marker(strategy: FixedStrategy())
        let mark = marker.mark(expected: "anything", heard: "else")
        XCTAssertEqual(mark.strategyID, "fixed")
        XCTAssertEqual(mark.source, .rubric)
    }

    func testLongEmojiAnswerDoesNotCrash() {
        let junk = String(repeating: "😀", count: 10_000)
        let score = AnswerScorer.score(expected: "7", child: junk, questionType: "integer", settings: "")
        XCTAssertEqual(score.result, .needsReview)
        XCTAssertEqual(score.points, 0)
    }
}

private struct FixedStrategy: ScoringStrategy {
    let strategyID = "fixed"
    func score(expected: String, heard: String, options: MarkerOptions) -> Mark {
        Mark.notScored(strategyID: strategyID, source: .rubric, locale: options.locale)
    }
}
