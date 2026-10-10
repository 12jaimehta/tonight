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

    /// A real presentation draws one spelled number and keeps it until the parent submits.
    public static func randomChallenge<G: RandomNumberGenerator>(using generator: inout G) -> GateChallenge {
        let offset = Int(generator.next() % 900)
        return challenge(fixed: false, offset: offset)
    }
}

/// Three wrong answers lock the gate for 60 seconds. The lockout survives backgrounding and relaunch. This is not a PIN.
public struct ParentalGateSession: Equatable, Sendable {
    public static let failureLimit = 3
    public static let lockout: TimeInterval = 60

    public private(set) var failures = 0
    public private(set) var lockedUntil: Date?

    public init() {}

    public func isLocked(at now: Date) -> Bool {
        guard let lockedUntil else { return false }
        return now < lockedUntil
    }

    public mutating func submit(answer: String, to challenge: GateChallenge, now: Date) -> GateVerdict {
        if isLocked(at: now) { return .locked }
        let digits = answer.filter(\.isNumber)
        if Int(digits) == challenge.answer {
            failures = 0
            lockedUntil = nil
            return .unlocked
        }
        failures += 1
        if failures >= Self.failureLimit {
            lockedUntil = now.addingTimeInterval(Self.lockout)
            return .locked
        }
        return .incorrect(remaining: Self.failureLimit - failures)
    }

    /// Backgrounding may clear the unlocked screen. It does not reset failures or the lockout.
    public mutating func resetForBackground() {}

    public var lockoutRecord: ParentalGateLockout {
        ParentalGateLockout(failures: failures, lockedUntil: lockedUntil)
    }

    public init(lockoutRecord: ParentalGateLockout) {
        failures = lockoutRecord.failures
        lockedUntil = lockoutRecord.lockedUntil
    }
}

/// Failures and the lockout deadline. This is not a PIN and it is not the challenge answer.
public struct ParentalGateLockout: Codable, Equatable, Sendable {
    public var failures: Int
    public var lockedUntil: Date?

    public init(failures: Int = 0, lockedUntil: Date? = nil) {
        self.failures = failures
        self.lockedUntil = lockedUntil
    }

    public static func load(from defaults: UserDefaults, key: String = ParentalGateLockout.storageKey) -> ParentalGateLockout {
        guard let data = defaults.data(forKey: key) else { return ParentalGateLockout() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ParentalGateLockout.self, from: data)) ?? ParentalGateLockout()
    }

    public func save(to defaults: UserDefaults, key: String = ParentalGateLockout.storageKey) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return }
        defaults.set(data, forKey: key)
    }

    public static let storageKey = "parental-gate-lockout"
}

/// A link or purchase leaves the app only after the gate is unlocked. A locked gate has no destination.
public enum ParentalGatedLink {
    public static func destination(_ url: URL, unlocked: Bool) -> URL? {
        unlocked ? url : nil
    }
}
