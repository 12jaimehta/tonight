import Foundation

/// An adult-solvable challenge. This is not a PIN, and it is not stored in the Keychain.
public struct GateChallenge: Hashable, Sendable {
    public var prompt: String
    public var answer: Int

    public init(prompt: String, answer: Int) {
        self.prompt = prompt
        self.answer = answer
    }
}

public enum GateVerdict: Equatable, Sendable {
    case unlocked
    case incorrect(remaining: Int)
    case locked
}

/// Spells a 3-digit number the way M1-05 shows it: "three hundred and forty-seven".
public enum EnglishNumberWords {
    public static func spell(_ number: Int) -> String {
        let value = min(max(number, 0), 999)
        if value < 100 { return belowHundred(value) }
        let hundreds = belowHundred(value / 100)
        let rest = value % 100
        if rest == 0 { return "\(hundreds) hundred" }
        return "\(hundreds) hundred and \(belowHundred(rest))"
    }

    private static let small = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
        "seventeen", "eighteen", "nineteen",
    ]

    private static let tens = [
        "", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
    ]

    private static func belowHundred(_ number: Int) -> String {
        if number < 20 { return small[number] }
        let ten = tens[number / 10]
        let one = number % 10
        if one == 0 { return ten }
        return "\(ten)-\(small[one])"
    }
}

public enum ParentalGateBank {
    /// `-TonightFixedGate` always asks for this number so a UI test can solve it.
    public static let fixedNumber = 347
    public static let digitCount = 3

    public static func challenge(fixed: Bool, offset: Int = 0) -> GateChallenge {
        let number = fixed ? fixedNumber : number(at: offset)
        return GateChallenge(prompt: EnglishNumberWords.spell(number), answer: number)
    }

    /// 100...999, so the parent always types three digits.
    public static func number(at offset: Int) -> Int {
        let span = 900
        let index = ((offset % span) + span) % span
        return 100 + index
    }
}

/// Three wrong answers close the gate. The count lives in memory and is cleared on background.
/// M1-05 has no timer: the sheet closes, and nothing is stored.
public struct ParentalGateSession: Equatable, Sendable {
    public static let failureLimit = 3

    public private(set) var failures = 0

    public init() {}

    public func isLocked(at now: Date) -> Bool {
        _ = now
        return failures >= Self.failureLimit
    }

    public mutating func submit(answer: String, to challenge: GateChallenge, now: Date) -> GateVerdict {
        if isLocked(at: now) { return .locked }
        let digits = answer.filter(\.isNumber)
        if Int(digits) == challenge.answer {
            failures = 0
            return .unlocked
        }
        failures += 1
        if failures >= Self.failureLimit {
            return .locked
        }
        return .incorrect(remaining: Self.failureLimit - failures)
    }

    public mutating func resetForBackground() {
        failures = 0
    }
}
