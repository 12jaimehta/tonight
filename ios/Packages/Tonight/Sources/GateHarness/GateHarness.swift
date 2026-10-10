import Foundation

/// M0 speech-engine gate. The results file and outcome codes match the
/// independent checker: `APPLE`, `SARVAM`, `NO_GO`, `OUT_OF_COHORT`,
/// `INVALID_STUDY`, and `INVALID_INPUT`.
///
/// Expected age/class pairs are 6→1, 7→2, and 8→3. Any other in-range pair
/// is a warning and the study is still scored. A pooled false-accept or
/// false-reject denominator of 0 is `INVALID_STUDY` and never passes.
public enum GateHarness {
    public static let schemaVersion = 1
    public static let bootstrapCount = 10_000
    public static let seed = 20_261_009
    public static let agreementBar = Rational(9, 10)
    public static let falseAcceptBar = Rational(1, 20)
    public static let falseRejectBar = Rational(1, 10)
    public static let childFalseAcceptCap = Rational(1, 10)
    public static let sarvamMargin = Rational(1, 20)
    public static let confidence = Rational(95, 100)

    public static func evaluate(_ data: Data, seed: Int = GateHarness.seed, resamples: Int = GateHarness.bootstrapCount) throws -> GateReport {
        let object = try jsonObject(data)
        return try evaluate(object: object, seed: seed, resamples: resamples)
    }

    public static func evaluate(object: [String: Any], seed: Int = GateHarness.seed, resamples: Int = GateHarness.bootstrapCount) throws -> GateReport {
        let cohort = try parseCohort(object)
        try requireDefinedDenominators(cohort)
        let apple = score(cohort, engine: .apple)
        let sarvam = score(cohort, engine: .sarvam)
        let delta = pooledDelta(cohort.recordings)
        let interval = agreementInterval(cohort.children, resamples: resamples, seed: seed)
        let beats = sarvamClearlyBeats(
            applePasses: apple.passes,
            sarvamPasses: sarvam.passes,
            delta: delta,
            ciLow: interval.low,
            appleFalseAccept: apple.comparableFalseAccept,
            sarvamFalseAccept: sarvam.comparableFalseAccept
        )
        return GateReport(
            schemaVersion: schemaVersion,
            decision: decide(applePasses: apple.passes, sarvamPasses: sarvam.passes, beats: beats),
            seed: interval.seed,
            warnings: cohort.warnings,
            agreementDelta: delta,
            interval: interval,
            apple: apple,
            sarvam: sarvam,
            beats: beats
        )
    }

    private static func decide(applePasses: Bool, sarvamPasses: Bool, beats: Bool) -> GateDecision {
        if applePasses && sarvamPasses { return beats ? .sarvam : .apple }
        if sarvamPasses { return .sarvam }
        if applePasses { return .apple }
        return .noGo
    }

    private static func sarvamClearlyBeats(
        applePasses: Bool,
        sarvamPasses: Bool,
        delta: Rational,
        ciLow: Rational,
        appleFalseAccept: Rational,
        sarvamFalseAccept: Rational
    ) -> Bool {
        applePasses && sarvamPasses
            && delta >= sarvamMargin
            && ciLow > Rational(0, 1)
            && sarvamFalseAccept <= appleFalseAccept
    }
}

public struct GateReport: Equatable, Sendable {
    public var schemaVersion: Int
    public var decision: GateDecision
    public var seed: Int
    public var warnings: [String]
    public var agreementDelta: Rational
    public var interval: AgreementInterval
    public var apple: EngineScore
    public var sarvam: EngineScore
    public var beats: Bool

    /// Results JSON fields from the independent checker.
    public func dictionary() -> [String: Any] {
        [
            "schema_version": schemaVersion,
            "decision": decision.rawValue,
            "seed": seed,
            "warnings": warnings,
            "agreement_delta": agreementDelta.dictionary(),
            "apple": apple.dictionary(),
            "sarvam": sarvam.dictionary(),
            "clearly_beats": [
                "sarvam_wins": beats,
                "both_pass": apple.passes && sarvam.passes,
                "margin_at_least_5pp": agreementDelta >= GateHarness.sarvamMargin,
                "interval_strictly_above_zero": interval.low > Rational(0, 1),
                "false_accept_not_worse": sarvam.comparableFalseAccept <= apple.comparableFalseAccept,
            ] as [String: Any],
            "interval": [
                "method": "paired child-cluster bootstrap, Hyndman-Fan type 7 percentile",
                "generator": "random.Random",
                "confidence": GateHarness.confidence.dictionary(),
                "resamples": interval.resamples,
                "seed": interval.seed,
                "low": interval.low.dictionary(),
                "high": interval.high.dictionary(),
                "strictly_above_zero": interval.low > Rational(0, 1),
            ] as [String: Any],
        ]
    }
}

public struct AgreementInterval: Equatable, Sendable {
    public var low: Rational
    public var high: Rational
    public var resamples: Int
    public var seed: Int
}

public struct EngineScore: Equatable, Sendable {
    public var passes: Bool
    public var words: Int
    public var matches: Int
    public var agreement: Rational
    public var referenceCorrect: Int
    public var referenceIncorrect: Int
    public var falseAccepts: Int
    public var falseAcceptRate: Rational?
    public var falseRejects: Int
    public var falseRejectRate: Rational?
    public var perChildFalseAccept: [ChildFalseAccept]
    public var comparableFalseAccept: Rational

    func dictionary() -> [String: Any] {
        [
            "passes": passes,
            "words": words,
            "matches": matches,
            "agreement": agreement.dictionary(),
            "reference_correct": referenceCorrect,
            "reference_incorrect": referenceIncorrect,
            "false_accepts": falseAccepts,
            "false_accept_rate": rateDictionary(falseAcceptRate, absent: "not_applicable"),
            "false_rejects": falseRejects,
            "false_reject_rate": rateDictionary(falseRejectRate, absent: "undefined"),
            "children": perChildFalseAccept.map { child in
                [
                    "child_id": child.childID,
                    "false_accepts": child.falseAccepts,
                    "reference_incorrect": child.referenceIncorrect,
                    "false_accept_rate": rateDictionary(child.rate, absent: "not_applicable"),
                    "within_cap": child.withinCap,
                ] as [String: Any]
            },
        ]
    }
}

public struct ChildFalseAccept: Equatable, Sendable {
    public var childID: String
    public var falseAccepts: Int
    public var referenceIncorrect: Int
    public var rate: Rational?
    public var withinCap: Bool
}

public enum GateDecision: String, Codable, Sendable, CaseIterable {
    case apple = "APPLE"
    case sarvam = "SARVAM"
    case noGo = "NO_GO"
}

public struct GateHarnessError: Error, Equatable, Sendable {
    public var code: String
    public var message: String

    public static func outOfCohort(_ message: String) -> GateHarnessError {
        GateHarnessError(code: "OUT_OF_COHORT", message: message)
    }

    public static func invalidStudy(_ message: String) -> GateHarnessError {
        GateHarnessError(code: "INVALID_STUDY", message: message)
    }

    public static func invalidInput(_ message: String) -> GateHarnessError {
        GateHarnessError(code: "INVALID_INPUT", message: message)
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

    public func dictionary() -> [String: Int] {
        ["numerator": numerator, "denominator": denominator]
    }

    public static func < (lhs: Rational, rhs: Rational) -> Bool {
        lhs.numerator * rhs.denominator < rhs.numerator * lhs.denominator
    }

    public static func + (lhs: Rational, rhs: Rational) -> Rational {
        Rational(
            lhs.numerator * rhs.denominator + rhs.numerator * lhs.denominator,
            lhs.denominator * rhs.denominator
        )
    }

    public static func - (lhs: Rational, rhs: Rational) -> Rational {
        Rational(
            lhs.numerator * rhs.denominator - rhs.numerator * lhs.denominator,
            lhs.denominator * rhs.denominator
        )
    }

    public static func * (lhs: Rational, rhs: Rational) -> Rational {
        Rational(lhs.numerator * rhs.numerator, lhs.denominator * rhs.denominator)
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

private enum EngineField {
    case apple
    case sarvam
}

private struct RecordingTotals {
    var recordingID: String
    var childID: String
    var words: Int
    var referenceCorrect: Int
    var appleMatches: Int
    var sarvamMatches: Int
    var appleFalseAccepts: Int
    var sarvamFalseAccepts: Int
    var appleFalseRejects: Int
    var sarvamFalseRejects: Int

    var referenceIncorrect: Int { words - referenceCorrect }
    var matchDifference: Int { sarvamMatches - appleMatches }
}

private struct ChildCluster {
    var childID: String
    var age: Int
    var schoolClass: Int
    var recordings: [RecordingTotals]
}

private struct ParsedCohort {
    var children: [ChildCluster]
    var warnings: [String]
    var recordings: [RecordingTotals] { children.flatMap(\.recordings) }
}

private func jsonObject(_ data: Data) throws -> [String: Any] {
    let parsed = try JSONSerialization.jsonObject(with: data)
    guard let object = parsed as? [String: Any] else {
        throw GateHarnessError.invalidInput("results must be a JSON object")
    }
    return object
}

private func parseCohort(_ payload: [String: Any]) throws -> ParsedCohort {
    guard strictInteger(payload["schema_version"]) == GateHarness.schemaVersion else {
        throw GateHarnessError.invalidInput("schema_version must be the integer \(GateHarness.schemaVersion)")
    }
    guard let rawChildren = payload["children"] as? [Any], !rawChildren.isEmpty else {
        throw GateHarnessError.invalidInput("children must be a non-empty list")
    }
    var pending: [(id: String, age: Int?, schoolClass: Int?, recordings: [RecordingTotals])] = []
    var seenChildren = Set<String>()
    var seenRecordings = Set<String>()
    for (index, raw) in rawChildren.enumerated() {
        let child = try parseChild(raw, path: "children[\(index)]", seen: &seenRecordings)
        if seenChildren.contains(child.id) {
            throw GateHarnessError.invalidInput("children[\(index)].child_id: duplicate id \(child.id)")
        }
        seenChildren.insert(child.id)
        pending.append(child)
    }
    var problems: [String] = []
    for child in pending {
        if child.age == nil {
            problems.append("\(child.id) is missing an age")
        } else if let age = child.age, !(6...8).contains(age) {
            problems.append("\(child.id) age \(age) is outside 6-8")
        }
        if child.schoolClass == nil {
            problems.append("\(child.id) is missing a class")
        } else if let schoolClass = child.schoolClass, !(1...3).contains(schoolClass) {
            problems.append("\(child.id) class \(schoolClass) is outside 1-3")
        }
    }
    if !problems.isEmpty {
        throw GateHarnessError.outOfCohort(
            "\(problems.count) cohort member(s) outside ages 6-8 and classes 1-3: \(problems.joined(separator: "; "))"
        )
    }
    let expectedClass = [6: 1, 7: 2, 8: 3]
    var children: [ChildCluster] = []
    var warnings: [String] = []
    for child in pending {
        let age = child.age!
        let schoolClass = child.schoolClass!
        children.append(ChildCluster(childID: child.id, age: age, schoolClass: schoolClass, recordings: child.recordings))
        if schoolClass != expectedClass[age] {
            warnings.append("child \(child.id) age \(age) is paired with class \(schoolClass); expected class \(expectedClass[age]!)")
        }
    }
    return ParsedCohort(children: children, warnings: warnings)
}

private func parseChild(
    _ raw: Any,
    path: String,
    seen: inout Set<String>
) throws -> (id: String, age: Int?, schoolClass: Int?, recordings: [RecordingTotals]) {
    guard let body = raw as? [String: Any] else {
        throw GateHarnessError.invalidInput("\(path) must be a JSON object")
    }
    let childID = try identifier(body["child_id"], path: "\(path).child_id")
    let age = try optionalInteger(body, key: "age", path: "\(path).age")
    let schoolClass = try optionalInteger(body, key: "school_class", path: "\(path).school_class")
    guard let rawRecordings = body["recordings"] as? [Any], !rawRecordings.isEmpty else {
        throw GateHarnessError.invalidInput("\(path).recordings must be a non-empty list")
    }
    var recordings: [RecordingTotals] = []
    for (index, rawRecording) in rawRecordings.enumerated() {
        recordings.append(try parseRecording(rawRecording, path: "\(path).recordings[\(index)]", childID: childID, seen: &seen))
    }
    return (childID, age, schoolClass, recordings)
}

private func parseRecording(
    _ raw: Any,
    path: String,
    childID: String,
    seen: inout Set<String>
) throws -> RecordingTotals {
    guard let body = raw as? [String: Any] else {
        throw GateHarnessError.invalidInput("\(path) must be a JSON object")
    }
    let recordingID = try identifier(body["recording_id"], path: "\(path).recording_id")
    if seen.contains(recordingID) {
        throw GateHarnessError.invalidInput("\(path).recording_id: duplicate id \(recordingID)")
    }
    seen.insert(recordingID)
    let hasCells = body.keys.contains("cells")
    let hasWords = body.keys.contains("words")
    if hasCells == hasWords {
        throw GateHarnessError.invalidInput("\(path) must contain exactly one of 'cells' or 'words'")
    }
    let counts: [JudgedPattern: Int]
    if hasCells {
        counts = try countsFromCells(body["cells"], path: "\(path).cells")
    } else {
        counts = try countsFromWords(body["words"], path: "\(path).words")
    }
    return try totals(recordingID: recordingID, childID: childID, counts: counts, path: path)
}

private struct JudgedPattern: Hashable {
    var referenceCorrect: Bool
    var appleCorrect: Bool
    var sarvamCorrect: Bool
}

private func countsFromCells(_ raw: Any?, path: String) throws -> [JudgedPattern: Int] {
    guard let items = raw as? [Any], !items.isEmpty else {
        throw GateHarnessError.invalidInput("\(path) must be a non-empty list")
    }
    var counts: [JudgedPattern: Int] = [:]
    for (index, item) in items.enumerated() {
        guard let cell = item as? [String: Any] else {
            throw GateHarnessError.invalidInput("\(path)[\(index)] must be a JSON object")
        }
        guard let pattern = try judgedPattern(cell, path: "\(path)[\(index)]") else { continue }
        let count = try nonNegativeInteger(cell["n"], path: "\(path)[\(index)].n")
        counts[pattern, default: 0] += count
    }
    return counts
}

private func countsFromWords(_ raw: Any?, path: String) throws -> [JudgedPattern: Int] {
    guard let items = raw as? [Any], !items.isEmpty else {
        throw GateHarnessError.invalidInput("\(path) must be a non-empty list")
    }
    var counts: [JudgedPattern: Int] = [:]
    for (index, item) in items.enumerated() {
        guard let word = item as? [String: Any] else {
            throw GateHarnessError.invalidInput("\(path)[\(index)] must be a JSON object")
        }
        guard let pattern = try judgedPattern(word, path: "\(path)[\(index)]") else { continue }
        counts[pattern, default: 0] += 1
    }
    return counts
}

private func judgedPattern(_ body: [String: Any], path: String) throws -> JudgedPattern? {
    if !body.keys.contains("reference_correct") {
        throw GateHarnessError.invalidInput("\(path).reference_correct is required")
    }
    let apple = try boolean(body["apple_correct"], path: "\(path).apple_correct")
    let sarvam = try boolean(body["sarvam_correct"], path: "\(path).sarvam_correct")
    if body["reference_correct"] is NSNull || body["reference_correct"] == nil {
        return nil
    }
    let reference = try boolean(body["reference_correct"], path: "\(path).reference_correct")
    return JudgedPattern(referenceCorrect: reference, appleCorrect: apple, sarvamCorrect: sarvam)
}

private func totals(recordingID: String, childID: String, counts: [JudgedPattern: Int], path: String) throws -> RecordingTotals {
    var words = 0
    var referenceCorrect = 0
    var appleMatches = 0
    var sarvamMatches = 0
    var appleFalseAccepts = 0
    var sarvamFalseAccepts = 0
    var appleFalseRejects = 0
    var sarvamFalseRejects = 0
    for (pattern, count) in counts {
        words += count
        if pattern.referenceCorrect { referenceCorrect += count }
        if pattern.appleCorrect == pattern.referenceCorrect {
            appleMatches += count
        } else if pattern.referenceCorrect {
            appleFalseRejects += count
        } else {
            appleFalseAccepts += count
        }
        if pattern.sarvamCorrect == pattern.referenceCorrect {
            sarvamMatches += count
        } else if pattern.referenceCorrect {
            sarvamFalseRejects += count
        } else {
            sarvamFalseAccepts += count
        }
    }
    if words == 0 {
        throw GateHarnessError.invalidInput("\(path) has no judged words")
    }
    return RecordingTotals(
        recordingID: recordingID,
        childID: childID,
        words: words,
        referenceCorrect: referenceCorrect,
        appleMatches: appleMatches,
        sarvamMatches: sarvamMatches,
        appleFalseAccepts: appleFalseAccepts,
        sarvamFalseAccepts: sarvamFalseAccepts,
        appleFalseRejects: appleFalseRejects,
        sarvamFalseRejects: sarvamFalseRejects
    )
}

private func requireDefinedDenominators(_ cohort: ParsedCohort) throws {
    var referenceCorrect = 0
    var referenceIncorrect = 0
    for recording in cohort.recordings {
        referenceCorrect += recording.referenceCorrect
        referenceIncorrect += recording.referenceIncorrect
    }
    var problems: [String] = []
    if referenceCorrect == 0 { problems.append("pooled false-reject denominator is 0") }
    if referenceIncorrect == 0 { problems.append("pooled false-accept denominator is 0") }
    if !problems.isEmpty {
        throw GateHarnessError.invalidStudy(problems.joined(separator: "; "))
    }
}

private func score(_ cohort: ParsedCohort, engine: EngineField) -> EngineScore {
    var words = 0
    var matches = 0
    var referenceCorrect = 0
    var falseAccepts = 0
    var falseRejects = 0
    var children: [ChildFalseAccept] = []
    for child in cohort.children {
        var childAccepts = 0
        var childIncorrect = 0
        var childWords = 0
        var childMatches = 0
        var childCorrect = 0
        var childRejects = 0
        for recording in child.recordings {
            childWords += recording.words
            childCorrect += recording.referenceCorrect
            childIncorrect += recording.referenceIncorrect
            switch engine {
            case .apple:
                childMatches += recording.appleMatches
                childAccepts += recording.appleFalseAccepts
                childRejects += recording.appleFalseRejects
            case .sarvam:
                childMatches += recording.sarvamMatches
                childAccepts += recording.sarvamFalseAccepts
                childRejects += recording.sarvamFalseRejects
            }
        }
        words += childWords
        matches += childMatches
        referenceCorrect += childCorrect
        falseAccepts += childAccepts
        falseRejects += childRejects
        children.append(childFalseAccept(child.childID, accepts: childAccepts, incorrect: childIncorrect))
    }
    let referenceIncorrect = words - referenceCorrect
    let agreement = Rational(matches, words)
    let falseAcceptRate: Rational?
    let falseAcceptOK: Bool
    if referenceIncorrect == 0 {
        falseAcceptRate = nil
        falseAcceptOK = false
    } else {
        falseAcceptRate = Rational(falseAccepts, referenceIncorrect)
        falseAcceptOK = falseAcceptRate! <= GateHarness.falseAcceptBar
    }
    let falseRejectRate: Rational?
    let falseRejectOK: Bool
    if referenceCorrect == 0 {
        falseRejectRate = nil
        falseRejectOK = false
    } else {
        falseRejectRate = Rational(falseRejects, referenceCorrect)
        falseRejectOK = falseRejectRate! <= GateHarness.falseRejectBar
    }
    let perChildOK = children.allSatisfy(\.withinCap)
    let comparable = falseAcceptRate ?? Rational(0, 1)
    return EngineScore(
        passes: agreement >= GateHarness.agreementBar && falseAcceptOK && falseRejectOK && perChildOK,
        words: words,
        matches: matches,
        agreement: agreement,
        referenceCorrect: referenceCorrect,
        referenceIncorrect: referenceIncorrect,
        falseAccepts: falseAccepts,
        falseAcceptRate: falseAcceptRate,
        falseRejects: falseRejects,
        falseRejectRate: falseRejectRate,
        perChildFalseAccept: children,
        comparableFalseAccept: comparable
    )
}

private func childFalseAccept(_ childID: String, accepts: Int, incorrect: Int) -> ChildFalseAccept {
    if incorrect == 0 {
        return ChildFalseAccept(childID: childID, falseAccepts: accepts, referenceIncorrect: 0, rate: nil, withinCap: true)
    }
    let rate = Rational(accepts, incorrect)
    return ChildFalseAccept(
        childID: childID,
        falseAccepts: accepts,
        referenceIncorrect: incorrect,
        rate: rate,
        withinCap: rate <= GateHarness.childFalseAcceptCap
    )
}

private func pooledDelta(_ recordings: [RecordingTotals]) -> Rational {
    var words = 0
    var difference = 0
    for recording in recordings {
        words += recording.words
        difference += recording.matchDifference
    }
    return Rational(difference, words)
}

private func agreementInterval(_ children: [ChildCluster], resamples: Int, seed: Int) -> AgreementInterval {
    var generator = PythonRandom(seed: seed)
    var samples: [Rational] = []
    samples.reserveCapacity(resamples)
    let count = children.count
    for _ in 0..<resamples {
        var recordings: [RecordingTotals] = []
        for _ in 0..<count {
            recordings.append(contentsOf: children[generator.randrange(count)].recordings)
        }
        samples.append(pooledDelta(recordings))
    }
    samples.sort()
    let tail = (Rational(1, 1) - GateHarness.confidence) * Rational(1, 2)
    return AgreementInterval(
        low: percentileType7(samples, tail),
        high: percentileType7(samples, Rational(1, 1) - tail),
        resamples: resamples,
        seed: seed
    )
}

private func percentileType7(_ sortedSamples: [Rational], _ probability: Rational) -> Rational {
    if sortedSamples.count == 1 { return sortedSamples[0] }
    let position = Rational(sortedSamples.count - 1, 1) * probability
    let lowerIndex = position.numerator / position.denominator
    if lowerIndex >= sortedSamples.count - 1 { return sortedSamples[sortedSamples.count - 1] }
    let weight = position - Rational(lowerIndex, 1)
    if weight.numerator == 0 { return sortedSamples[lowerIndex] }
    let lower = sortedSamples[lowerIndex]
    let upper = sortedSamples[lowerIndex + 1]
    return lower + (upper - lower) * weight
}

private func rateDictionary(_ rate: Rational?, absent: String) -> [String: Any] {
    guard let rate else { return ["status": absent] }
    return ["status": "ratio", "numerator": rate.numerator, "denominator": rate.denominator]
}

private func identifier(_ raw: Any?, path: String) throws -> String {
    guard let text = raw as? String, !text.isEmpty else {
        throw GateHarnessError.invalidInput("\(path) must be a non-empty string")
    }
    return text
}

private func optionalInteger(_ body: [String: Any], key: String, path: String) throws -> Int? {
    if !body.keys.contains(key) || body[key] is NSNull || body[key] == nil { return nil }
    return try integer(body[key], path: path)
}

private func integer(_ raw: Any?, path: String) throws -> Int {
    guard let value = strictInteger(raw) else {
        throw GateHarnessError.invalidInput("\(path) must be an integer, or null if unknown")
    }
    return value
}

private func nonNegativeInteger(_ raw: Any?, path: String) throws -> Int {
    guard let value = strictInteger(raw), value >= 0 else {
        throw GateHarnessError.invalidInput("\(path) must be a non-negative integer")
    }
    return value
}

private func boolean(_ raw: Any?, path: String) throws -> Bool {
    guard let value = strictBoolean(raw) else {
        throw GateHarnessError.invalidInput("\(path) must be a boolean")
    }
    return value
}

private func strictInteger(_ raw: Any?) -> Int? {
    guard let raw else { return nil }
    if type(of: raw) == Bool.self { return nil }
    if let number = raw as? NSNumber {
        if isJSONBool(number) { return nil }
        return number.intValue
    }
    if let value = raw as? Int { return value }
    return nil
}

private func strictBoolean(_ raw: Any?) -> Bool? {
    guard let raw else { return nil }
    if type(of: raw) == Bool.self { return raw as? Bool }
    if let number = raw as? NSNumber, isJSONBool(number) { return number.boolValue }
    return nil
}

private func isJSONBool(_ number: NSNumber) -> Bool {
    #if canImport(Darwin)
    return CFGetTypeID(number) == CFBooleanGetTypeID()
    #else
    return String(cString: number.objCType) == "c"
    #endif
}

/// Python `random.Random`: MT19937 seeded like CPython, `randrange` via `getrandbits`.
private struct PythonRandom {
    private var mt = [UInt32](repeating: 0, count: 624)
    private var index = 624

    init(seed: Int) {
        var value = seed < 0 ? -seed : seed
        var key: [UInt32] = []
        if value == 0 {
            key = [0]
        } else {
            while value > 0 {
                key.append(UInt32(truncatingIfNeeded: value))
                value >>= 32
            }
        }
        initByArray(key)
    }

    mutating func randrange(_ n: Int) -> Int {
        let bits = bitLength(n)
        var draw = getrandbits(bits)
        while draw >= n {
            draw = getrandbits(bits)
        }
        return draw
    }

    private mutating func getrandbits(_ k: Int) -> Int {
        Int(next() >> UInt32(32 - k))
    }

    private func bitLength(_ n: Int) -> Int {
        var count = 0
        var value = n
        while value > 0 {
            value >>= 1
            count += 1
        }
        return count
    }

    private mutating func initByArray(_ key: [UInt32]) {
        initGenrand(19_650_218)
        var i = 1
        var j = 0
        var k = max(624, key.count)
        while k > 0 {
            let mixed = (mt[i - 1] ^ (mt[i - 1] >> 30)) &* 1_664_525
            mt[i] = (mt[i] ^ mixed) &+ key[j] &+ UInt32(j)
            i += 1
            j += 1
            if i >= 624 {
                mt[0] = mt[623]
                i = 1
            }
            if j >= key.count { j = 0 }
            k -= 1
        }
        k = 623
        while k > 0 {
            let mixed = (mt[i - 1] ^ (mt[i - 1] >> 30)) &* 1_566_083_941
            mt[i] = (mt[i] ^ mixed) &- UInt32(i)
            i += 1
            if i >= 624 {
                mt[0] = mt[623]
                i = 1
            }
            k -= 1
        }
        mt[0] = 0x8000_0000
        index = 624
    }

    private mutating func initGenrand(_ seed: UInt32) {
        mt[0] = seed
        for i in 1..<624 {
            mt[i] = 1_812_433_253 &* (mt[i - 1] ^ (mt[i - 1] >> 30)) &+ UInt32(i)
        }
        index = 624
    }

    private mutating func next() -> UInt32 {
        if index >= 624 {
            twist()
        }
        var y = mt[index]
        index += 1
        y ^= y >> 11
        y ^= (y << 7) & 0x9D2C_5680
        y ^= (y << 15) & 0xEFC6_0000
        y ^= y >> 18
        return y
    }

    private mutating func twist() {
        let matrix: UInt32 = 0x9908_B0DF
        let upper: UInt32 = 0x8000_0000
        let lower: UInt32 = 0x7FFF_FFFF
        for kk in 0..<227 {
            let y = (mt[kk] & upper) | (mt[kk + 1] & lower)
            mt[kk] = mt[kk + 397] ^ (y >> 1) ^ ((y & 1) == 0 ? 0 : matrix)
        }
        for kk in 227..<623 {
            let y = (mt[kk] & upper) | (mt[kk + 1] & lower)
            mt[kk] = mt[kk + 397 - 624] ^ (y >> 1) ^ ((y & 1) == 0 ? 0 : matrix)
        }
        let y = (mt[623] & upper) | (mt[0] & lower)
        mt[623] = mt[396] ^ (y >> 1) ^ ((y & 1) == 0 ? 0 : matrix)
        index = 0
    }
}
