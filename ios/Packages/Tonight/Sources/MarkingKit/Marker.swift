import Foundation

/// Who produced a mark. Automatic alignment is v1. Parent taps and rubric
/// checklists are seams for later (class 4–5); no LLM writes a score.
public enum MarkSource: String, Codable, Sendable, Equatable {
    case auto
    case parent
    case rubric
}

public enum WordStatus: String, Codable, Sendable, Equatable {
    case matched
    case substituted
    case omitted
    case inserted
}

public struct AlignedWord: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var expected: String?
    public var heard: String?
    public var status: WordStatus

    public init(id: Int, expected: String?, heard: String?, status: WordStatus) {
        self.id = id
        self.expected = expected
        self.heard = heard
        self.status = status
    }
}

public struct Mark: Codable, Sendable, Equatable {
    public static let currentScoringVersion = "1.0.0"

    public var scoringVersion: String
    public var strategyID: String
    public var source: MarkSource
    public var locale: String
    public var asrEngine: String?
    public var correct: Int
    public var total: Int
    /// Whole-number percent for display. Round half up, and never 100 unless every expected word matched.
    public var percent: Int?
    public var words: [AlignedWord]
    /// Omitted and substituted expected words, in passage order, duplicates kept.
    public var missed: [String]

    public init(
        scoringVersion: String = Mark.currentScoringVersion,
        strategyID: String,
        source: MarkSource,
        locale: String,
        asrEngine: String? = nil,
        correct: Int,
        total: Int,
        percent: Int?,
        words: [AlignedWord],
        missed: [String]
    ) {
        self.scoringVersion = scoringVersion
        self.strategyID = strategyID
        self.source = source
        self.locale = locale
        self.asrEngine = asrEngine
        self.correct = correct
        self.total = total
        self.percent = percent
        self.words = words
        self.missed = missed
    }

    public static func notScored(strategyID: String, source: MarkSource, locale: String) -> Mark {
        Mark(
            strategyID: strategyID,
            source: source,
            locale: locale,
            correct: 0,
            total: 0,
            percent: nil,
            words: [],
            missed: []
        )
    }
}

public struct MarkerOptions: Sendable, Equatable {
    /// Phonetic / edit-distance matching. Off until the accuracy study says otherwise.
    public var fuzzyMatch: Bool
    /// Passed through onto the mark. The scorer does not read `Locale.current`.
    public var locale: String
    public var asrEngine: String?

    public init(fuzzyMatch: Bool = false, locale: String = "en-IN", asrEngine: String? = nil) {
        self.fuzzyMatch = fuzzyMatch
        self.locale = locale
        self.asrEngine = asrEngine
    }
}

/// A replaceable scoring strategy. v1 ships word alignment. Answer-key match and
/// rubric scoring can be added later without changing this type's callers.
public protocol ScoringStrategy: Sendable {
    var strategyID: String { get }
    func score(expected: String, heard: String, options: MarkerOptions) -> Mark
}

public struct Marker: Sendable {
    public var strategy: any ScoringStrategy

    public init(strategy: any ScoringStrategy = WordAlignmentStrategy()) {
        self.strategy = strategy
    }

    public func mark(expected: String, heard: String, options: MarkerOptions = MarkerOptions()) -> Mark {
        strategy.score(expected: expected, heard: heard, options: options)
    }
}

public struct WordAlignmentStrategy: ScoringStrategy {
    public let strategyID = "word-alignment"

    public init() {}

    public func score(expected: String, heard: String, options: MarkerOptions) -> Mark {
        let want = ReadingNormalizer.tokens(in: expected)
        let got = ReadingNormalizer.tokens(in: heard)
        let aligned = WordAligner.align(expected: want, heard: got, fuzzy: options.fuzzyMatch)
        let correct = aligned.filter { $0.status == .matched }.count
        let missed = aligned.compactMap { word -> String? in
            guard word.status == .omitted || word.status == .substituted else { return nil }
            return word.expected
        }
        return Mark(
            strategyID: strategyID,
            source: .auto,
            locale: options.locale,
            asrEngine: options.asrEngine,
            correct: correct,
            total: want.count,
            percent: DisplayRounding.percentValue(correct: correct, total: want.count),
            words: aligned,
            missed: missed
        )
    }
}
