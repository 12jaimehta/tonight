import Foundation

/// Stage B speech gate. Counts stay integers. Rates stay reduced rationals.
/// A child-level bootstrap (B = 10_000, fixed seed) supplies the intervals.
/// APPLE, SARVAM, and NO_GO are compared before any decimal rounding.
public enum GateHarness {
    public static let bootstrapCount = 10_000
    public static let seed: UInt64 = 20_261_010
    public static let agreementBar = Rational(9, 10)
    public static let falseAcceptBar = Rational(1, 20)
    public static let falseRejectBar = Rational(1, 10)

    public static func evaluate(_ document: GateDocument) throws -> GateReport {
        for recording in document.recordings {
            if recording.appleCorrect == nil || recording.sarvamCorrect == nil {
                throw GateHarnessError.unpairedRecording(recordingID: recording.id)
            }
        }
        let cohort = Set(document.cohort)
        for recording in document.recordings where !cohort.contains(recording.childID) {
            throw GateHarnessError.outOfCohort(recordingID: recording.id)
        }
        if document.recordings.isEmpty {
            throw GateHarnessError.unpairedRecording(recordingID: "")
        }

        var groups: [String: [Recording]] = [:]
        for recording in document.recordings {
            groups[recording.childID, default: []].append(recording)
        }
        let children = groups.keys.sorted()
        let apple = engineReport(document.recordings, groups: groups, children: children, engine: .apple)
        let sarvam = engineReport(document.recordings, groups: groups, children: children, engine: .sarvam)
        return GateReport(decision: decide(apple: apple, sarvam: sarvam), apple: apple, sarvam: sarvam)
    }

    private static func engineReport(
        _ recordings: [Recording],
        groups: [String: [Recording]],
        children: [String],
        engine: EngineField
    ) -> EngineReport {
        let counts = count(recordings, engine: engine)
        let agreement = rate(counts.agreements, counts.paired)
        let falseAccept = rate(counts.falseAccepts, counts.referenceIncorrect)
        let falseReject = rate(counts.falseRejects, counts.referenceCorrect)
        let intervals = bootstrap(groups: groups, children: children, engine: engine)
        return EngineReport(
            paired: counts.paired,
            agreements: counts.agreements,
            falseAccepts: counts.falseAccepts,
            referenceIncorrect: counts.referenceIncorrect,
            falseRejects: counts.falseRejects,
            referenceCorrect: counts.referenceCorrect,
            agreement: agreement,
            falseAcceptRate: falseAccept,
            falseRejectRate: falseReject,
            perChildFalseAccept: perChildFalseAccept(groups, engine: engine),
            agreementCI: intervals.agreement,
            falseAcceptCI: intervals.falseAccept,
            passesBar: passes(agreementLower: intervals.agreement.lower, falseAcceptUpper: intervals.falseAccept.upper, falseReject: falseReject)
        )
    }

    private static func decide(apple: EngineReport, sarvam: EngineReport) -> GateDecision {
        if apple.passesBar && sarvam.passesBar {
            return apple.agreement >= sarvam.agreement ? .apple : .sarvam
        }
        if apple.passesBar { return .apple }
        if sarvam.passesBar { return .sarvam }
        return .noGo
    }

    private static func passes(agreementLower: Rational, falseAcceptUpper: Rational, falseReject: Rational) -> Bool {
        agreementLower >= agreementBar && falseAcceptUpper <= falseAcceptBar && falseReject <= falseRejectBar
    }

    private static func perChildFalseAccept(_ groups: [String: [Recording]], engine: EngineField) -> [String: Rational] {
        var rates: [String: Rational] = [:]
        for child in groups.keys.sorted() {
            let counts = count(groups[child] ?? [], engine: engine)
            rates[child] = rate(counts.falseAccepts, counts.referenceIncorrect)
        }
        return rates
    }

    private static func bootstrap(
        groups: [String: [Recording]],
        children: [String],
        engine: EngineField
    ) -> (agreement: ClosedRangePair, falseAccept: ClosedRangePair) {
        var generator = LCG(seed: seed)
        var agreements: [Rational] = []
        var falseAccepts: [Rational] = []
        agreements.reserveCapacity(bootstrapCount)
        falseAccepts.reserveCapacity(bootstrapCount)
        for _ in 0..<bootstrapCount {
            var sample: [Recording] = []
            sample.reserveCapacity(children.count)
            for _ in children {
                let child = children[Int(generator.next() % UInt64(children.count))]
                sample.append(contentsOf: groups[child] ?? [])
            }
            let counts = count(sample, engine: engine)
            agreements.append(rate(counts.agreements, counts.paired))
            falseAccepts.append(rate(counts.falseAccepts, counts.referenceIncorrect))
        }
        return (percentile(agreements), percentile(falseAccepts))
    }

    private static func percentile(_ samples: [Rational]) -> ClosedRangePair {
        let ordered = samples.sorted()
        let lower = (25 * (bootstrapCount - 1)) / 1000
        let upper = (975 * (bootstrapCount - 1) + 999) / 1000
        return ClosedRangePair(lower: ordered[lower], upper: ordered[upper])
    }

    private static func count(_ rows: [Recording], engine: EngineField) -> Counts {
        var counts = Counts()
        counts.paired = rows.count
        for row in rows {
            let heard = engine.value(in: row) ?? false
            if heard == row.referenceCorrect { counts.agreements += 1 }
            if row.referenceCorrect {
                counts.referenceCorrect += 1
                if !heard { counts.falseRejects += 1 }
            } else {
                counts.referenceIncorrect += 1
                if heard { counts.falseAccepts += 1 }
            }
        }
        return counts
    }

    private static func rate(_ numerator: Int, _ denominator: Int) -> Rational {
        denominator == 0 ? Rational(0, 1) : Rational(numerator, denominator)
    }
}

public struct Rational: Hashable, Comparable, Sendable {
    public var numerator: Int
    public var denominator: Int

    public init(_ numerator: Int, _ denominator: Int) {
        var numerator = numerator
        var denominator = denominator
        if denominator < 0 {
            numerator = -numerator
            denominator = -denominator
        }
        let factor = Self.gcd(numerator, denominator)
        self.numerator = numerator / factor
        self.denominator = denominator / factor
    }

    public var text: String { "\(numerator)/\(denominator)" }

    public static func < (lhs: Rational, rhs: Rational) -> Bool {
        lhs.numerator * rhs.denominator < rhs.numerator * lhs.denominator
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = abs(a)
        var b = abs(b)
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return a == 0 ? 1 : a
    }
}

public struct ClosedRangePair: Equatable, Sendable {
    public var lower: Rational
    public var upper: Rational
}

public struct EngineReport: Equatable, Sendable {
    public var paired: Int
    public var agreements: Int
    public var falseAccepts: Int
    public var referenceIncorrect: Int
    public var falseRejects: Int
    public var referenceCorrect: Int
    public var agreement: Rational
    public var falseAcceptRate: Rational
    public var falseRejectRate: Rational
    public var perChildFalseAccept: [String: Rational]
    public var agreementCI: ClosedRangePair
    public var falseAcceptCI: ClosedRangePair
    public var passesBar: Bool
}

public struct GateReport: Equatable, Sendable {
    public var decision: GateDecision
    public var apple: EngineReport
    public var sarvam: EngineReport
}

public enum GateDecision: String, Codable, Sendable, CaseIterable {
    case apple = "APPLE"
    case sarvam = "SARVAM"
    case noGo = "NO_GO"
}

public enum GateHarnessError: Error, Equatable {
    case unpairedRecording(recordingID: String)
    case outOfCohort(recordingID: String)
}

public struct GateDocument: Codable, Equatable, Sendable {
    public var cohort: [String]
    public var recordings: [Recording]

    public init(cohort: [String], recordings: [Recording]) {
        self.cohort = cohort
        self.recordings = recordings
    }
}

public struct Recording: Codable, Equatable, Sendable {
    public var id: String
    public var childID: String
    public var referenceCorrect: Bool
    public var appleCorrect: Bool?
    public var sarvamCorrect: Bool?

    public init(id: String, childID: String, referenceCorrect: Bool, appleCorrect: Bool?, sarvamCorrect: Bool?) {
        self.id = id
        self.childID = childID
        self.referenceCorrect = referenceCorrect
        self.appleCorrect = appleCorrect
        self.sarvamCorrect = sarvamCorrect
    }
}

private enum EngineField {
    case apple
    case sarvam

    func value(in recording: Recording) -> Bool? {
        switch self {
        case .apple: recording.appleCorrect
        case .sarvam: recording.sarvamCorrect
        }
    }
}

private struct Counts {
    var paired = 0
    var agreements = 0
    var falseAccepts = 0
    var referenceIncorrect = 0
    var falseRejects = 0
    var referenceCorrect = 0
}

private struct LCG {
    var state: UInt64

    init(seed: UInt64) {
        state = seed & 0xFFFF_FFFF
    }

    mutating func next() -> UInt64 {
        state = (state &* 1_664_525 &+ 1_013_904_223) & 0xFFFF_FFFF
        return state
    }
}
