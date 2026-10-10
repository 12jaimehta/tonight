import Foundation

/// Stage B speech gate. Counts stay integers. Rates stay reduced rationals.
/// A child-level bootstrap (B = 10_000, fixed seed) supplies the intervals.
/// Pass uses the pooled ratios: agreement ≥ 9/10, false accepts ≤ 1/20,
/// false rejects ≤ 1/10, and every scored child ≤ 10% false accepts.
/// SARVAM requires both passes, a gap of at least 5 percentage points, and a
/// paired bootstrap interval that sits strictly above zero.
public enum GateHarness {
    public static let scoringVersion = 2
    public static let bootstrapCount = 10_000
    public static let seed: UInt64 = 20_261_010
    public static let agreementBar = Rational(9, 10)
    public static let falseAcceptBar = Rational(1, 20)
    public static let falseRejectBar = Rational(1, 10)
    public static let childFalseAcceptCap = Rational(1, 10)
    public static let sarvamMargin = Rational(1, 20)
    public static let cohortAges = 6...8
    public static let cohortClasses: Set<String> = ["1", "2", "3"]

    public static func evaluate(_ document: GateDocument) throws -> GateReport {
        try screen(document)
        var groups: [String: [Recording]] = [:]
        for recording in document.recordings {
            groups[recording.childID, default: []].append(recording)
        }
        let children = groups.keys.sorted()
        let apple = engineReport(document.recordings, groups: groups, children: children, engine: .apple)
        let sarvam = engineReport(document.recordings, groups: groups, children: children, engine: .sarvam)
        let deltaCI = deltaInterval(groups: groups, children: children)
        let delta = sarvam.agreement - apple.agreement
        return GateReport(
            scoringVersion: scoringVersion,
            decision: decide(apple: apple, sarvam: sarvam, delta: delta, deltaCI: deltaCI),
            apple: apple,
            sarvam: sarvam,
            deltaAgreement: delta,
            deltaCI: deltaCI
        )
    }

    private static func screen(_ document: GateDocument) throws {
        for recording in document.recordings {
            if recording.appleCorrect == nil || recording.sarvamCorrect == nil {
                throw GateHarnessError.unpairedRecording(recordingID: recording.id)
            }
        }
        if document.recordings.isEmpty {
            throw GateHarnessError.unpairedRecording(recordingID: "")
        }
        var members: [String: CohortMember] = [:]
        for member in document.cohort {
            if let age = member.age, !cohortAges.contains(age) {
                throw GateHarnessError.cohortRejected(recordingID: member.id)
            }
            if let schoolClass = member.schoolClass, !cohortClasses.contains(schoolClass) {
                throw GateHarnessError.cohortRejected(recordingID: member.id)
            }
            members[member.id] = member
        }
        for recording in document.recordings {
            guard let member = members[recording.childID] else {
                throw GateHarnessError.outOfCohort(recordingID: recording.id)
            }
            if let age = recording.age {
                guard let expected = member.age, expected == age, cohortAges.contains(age) else {
                    throw GateHarnessError.cohortRejected(recordingID: recording.id)
                }
            }
            if let schoolClass = recording.schoolClass {
                guard let expected = member.schoolClass, expected == schoolClass, cohortClasses.contains(schoolClass) else {
                    throw GateHarnessError.cohortRejected(recordingID: recording.id)
                }
            }
        }
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
        let perChild = perChildFalseAccept(groups, engine: engine)
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
            perChildFalseAccept: perChild,
            agreementCI: intervals.agreement,
            falseAcceptCI: intervals.falseAccept,
            passesBar: passes(agreement: agreement, falseAccept: falseAccept, falseReject: falseReject, perChild: perChild)
        )
    }

    private static func decide(apple: EngineReport, sarvam: EngineReport, delta: Rational, deltaCI: ClosedRangePair) -> GateDecision {
        let beats = delta >= sarvamMargin && deltaCI.lower > Rational(0, 1)
        if apple.passesBar && sarvam.passesBar && beats {
            return .sarvam
        }
        if apple.passesBar { return .apple }
        return .noGo
    }

    private static func passes(
        agreement: Rational,
        falseAccept: Rational,
        falseReject: Rational,
        perChild: [String: Rational?]
    ) -> Bool {
        guard agreement >= agreementBar else { return false }
        guard falseAccept <= falseAcceptBar else { return false }
        guard falseReject <= falseRejectBar else { return false }
        for value in perChild.values {
            if let value, value > childFalseAcceptCap { return false }
        }
        return true
    }

    private static func perChildFalseAccept(_ groups: [String: [Recording]], engine: EngineField) -> [String: Rational?] {
        var rates: [String: Rational?] = [:]
        for child in groups.keys.sorted() {
            let counts = count(groups[child] ?? [], engine: engine)
            if counts.referenceIncorrect == 0 {
                rates.updateValue(nil, forKey: child)
            } else {
                rates[child] = rate(counts.falseAccepts, counts.referenceIncorrect)
            }
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
                let draw = generator.next()
                let mixed = draw ^ (draw >> 16)
                let child = children[Int(mixed % UInt64(children.count))]
                sample.append(contentsOf: groups[child] ?? [])
            }
            let counts = count(sample, engine: engine)
            agreements.append(rate(counts.agreements, counts.paired))
            falseAccepts.append(rate(counts.falseAccepts, counts.referenceIncorrect))
        }
        return (percentile(agreements), percentile(falseAccepts))
    }

    /// Paired child resample of Sarvam agreement minus Apple agreement. A fresh seed, so it does not disturb the per-engine intervals.
    private static func deltaInterval(groups: [String: [Recording]], children: [String]) -> ClosedRangePair {
        var generator = LCG(seed: seed)
        var gaps: [Rational] = []
        gaps.reserveCapacity(bootstrapCount)
        for _ in 0..<bootstrapCount {
            var sample: [Recording] = []
            sample.reserveCapacity(children.count)
            for _ in children {
                let draw = generator.next()
                let mixed = draw ^ (draw >> 16)
                let child = children[Int(mixed % UInt64(children.count))]
                sample.append(contentsOf: groups[child] ?? [])
            }
            let apple = count(sample, engine: .apple)
            let sarvam = count(sample, engine: .sarvam)
            gaps.append(rate(sarvam.agreements, sarvam.paired) - rate(apple.agreements, apple.paired))
        }
        return percentile(gaps)
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

    public static func - (lhs: Rational, rhs: Rational) -> Rational {
        Rational(
            lhs.numerator * rhs.denominator - rhs.numerator * lhs.denominator,
            lhs.denominator * rhs.denominator
        )
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
    /// Nil means the child had no incorrect reference, so the false-accept rate is n/a.
    public var perChildFalseAccept: [String: Rational?]
    public var agreementCI: ClosedRangePair
    public var falseAcceptCI: ClosedRangePair
    public var passesBar: Bool
}

public struct GateReport: Equatable, Sendable {
    public var scoringVersion: Int
    public var decision: GateDecision
    public var apple: EngineReport
    public var sarvam: EngineReport
    public var deltaAgreement: Rational
    public var deltaCI: ClosedRangePair
}

public enum GateDecision: String, Codable, Sendable, CaseIterable {
    case apple = "APPLE"
    case sarvam = "SARVAM"
    case noGo = "NO_GO"
}

public enum GateHarnessError: Error, Equatable {
    case unpairedRecording(recordingID: String)
    case outOfCohort(recordingID: String)
    case cohortRejected(recordingID: String)
}

private struct CohortItem: Decodable {
    var member: CohortMember

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let id = try? container.decode(String.self) {
            member = CohortMember(id: id)
            return
        }
        member = try CohortMember(from: decoder)
    }
}

public struct CohortMember: Codable, Equatable, Sendable {
    public var id: String
    public var age: Int?
    public var schoolClass: String?

    public init(id: String, age: Int? = nil, schoolClass: String? = nil) {
        self.id = id
        self.age = age
        self.schoolClass = schoolClass
    }
}

public struct GateDocument: Codable, Equatable, Sendable {
    public var cohort: [CohortMember]
    public var recordings: [Recording]

    public init(cohort: [String], recordings: [Recording]) {
        self.cohort = cohort.map { CohortMember(id: $0) }
        self.recordings = recordings
    }

    public init(members: [CohortMember], recordings: [Recording]) {
        self.cohort = members
        self.recordings = recordings
    }

    private enum CodingKeys: String, CodingKey {
        case cohort
        case recordings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let items = try container.decode([CohortItem].self, forKey: .cohort)
        self.cohort = items.map(\.member)
        self.recordings = try container.decode([Recording].self, forKey: .recordings)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cohort, forKey: .cohort)
        try container.encode(recordings, forKey: .recordings)
    }
}

public struct Recording: Codable, Equatable, Sendable {
    public var id: String
    public var childID: String
    public var referenceCorrect: Bool
    public var appleCorrect: Bool?
    public var sarvamCorrect: Bool?
    public var age: Int?
    public var schoolClass: String?

    public init(
        id: String,
        childID: String,
        referenceCorrect: Bool,
        appleCorrect: Bool?,
        sarvamCorrect: Bool?,
        age: Int? = nil,
        schoolClass: String? = nil
    ) {
        self.id = id
        self.childID = childID
        self.referenceCorrect = referenceCorrect
        self.appleCorrect = appleCorrect
        self.sarvamCorrect = sarvamCorrect
        self.age = age
        self.schoolClass = schoolClass
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
