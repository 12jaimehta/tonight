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
    public static func challenge(fixed: Bool, offset: Int = 0) -> GateChallenge {
        if fixed { return challenges[0] }
        let index = offset % challenges.count
        return challenges[index]
    }
}

/// Three wrong answers lock the gate for 60 seconds. The lockout lives in memory and is cleared on background or launch.
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
        let digits = answer.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
        if Int(String(String.UnicodeScalarView(digits))) == challenge.answer {
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

    public mutating func resetForBackground() {
        failures = 0
        lockedUntil = nil
    }
}
