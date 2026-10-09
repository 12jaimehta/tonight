import Foundation
import os

/// A closed list of first-party names. Events carry a name and a time.
public enum TonightEventName: String, Codable, CaseIterable, Sendable, Equatable {
    case appOpened = "app.opened"
    case childHomeShown = "child_home.shown"
    case gateShown = "gate.shown"
    case gateUnlocked = "gate.unlocked"
    case gateLocked = "gate.locked"
    case parentAreaShown = "parent_area.shown"
    case adultConsentRecorded = "adult_consent.recorded"
    case pageCaptured = "page.captured"
    case rememberAdded = "remember.added"
    case rememberCleared = "remember.cleared"
    case speechSelected = "speech.selected"
    case paywallBlocked = "paywall.blocked"
}

public struct TonightEvent: Codable, Equatable, Sendable {
    public var name: TonightEventName
    public var recordedAt: Date

    public init(name: TonightEventName, recordedAt: Date) {
        self.name = name
        self.recordedAt = recordedAt
    }
}

public final class TonightEventLog: @unchecked Sendable {
    private let events = OSAllocatedUnfairLock(initialState: [TonightEvent]())

    public init() {}

    public func record(_ name: TonightEventName, at date: Date = Date()) {
        let event = TonightEvent(name: name, recordedAt: date)
        events.withLock { $0.append(event) }
    }

    public func snapshot() -> [TonightEvent] {
        events.withLock { $0 }
    }
}

public enum TelemetryPolicy {
    public static let acceptsFreeText = false
    public static let usesThirdPartySDK = false
}
