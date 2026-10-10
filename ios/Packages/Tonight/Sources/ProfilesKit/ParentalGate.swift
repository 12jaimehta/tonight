import Foundation

/// An adult-solvable challenge. This is not a 4-digit PIN, and it is not stored in the Keychain.
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

public enum ParentalGateBank {
    public static let challenges: [GateChallenge] = [
        GateChallenge(prompt: "47 × 36", answer: 1692),
        GateChallenge(prompt: "86 × 27", answer: 2322),
        GateChallenge(prompt: "64 × 58", answer: 3712),
        GateChallenge(prompt: "93 × 47", answer: 4371),
        GateChallenge(prompt: "74 × 53", answer: 3922),
        GateChallenge(prompt: "39 × 68", answer: 2652),
        GateChallenge(prompt: "58 × 46", answer: 2668),
        GateChallenge(prompt: "27 × 84", answer: 2268),
    ]

    /// `-TonightFixedGate` uses the first product so a UI test can solve it.
    /// A real presentation passes a fresh random index and keeps that challenge until submit.
    public static func challenge(fixed: Bool, offset: Int = 0) -> GateChallenge {
        if fixed { return challenges[0] }
        let index = offset % challenges.count
        return challenges[index]
    }

    public static func randomChallenge<G: RandomNumberGenerator>(using generator: inout G) -> GateChallenge {
        let index = Int(generator.next() % UInt64(challenges.count))
        return challenges[index]
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
