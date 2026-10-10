import Foundation

/// One speech runner for a scene. Leaving the active phase suspends it.
/// A consent withdrawal, a flag turning off, or a child change cancels the upload and asks for deletion.
public final class SpeechSceneController: @unchecked Sendable {
    public let runner: SpeechAttemptRunner
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(runner: SpeechAttemptRunner) {
        self.runner = runner
    }

    public var suspended: Bool { state.withLock { $0.suspended } }
    public var deletionRequested: Bool { state.withLock { $0.deletionRequested } }

    public func sceneDidChange(isActive: Bool) async {
        guard !isActive else { return }
        state.withLock { $0.suspended = true }
        await runner.suspend()
    }

    public func apply(_ watch: SpeechWatch) async {
        let cancel = state.withLock { state -> Bool in
            let changedChild = state.started && watch.childID != state.childID
            let withdrew = state.started && state.consentActive && !watch.consentActive
            let flagOff = state.started && state.flagOn && !watch.flagOn
            state.started = true
            state.childID = watch.childID
            state.consentActive = watch.consentActive
            state.flagOn = watch.flagOn
            if changedChild || withdrew || flagOff {
                state.deletionRequested = true
                return true
            }
            return false
        }
        if cancel {
            await runner.suspend()
        }
    }

    private struct State {
        var started = false
        var childID: UUID?
        var consentActive = false
        var flagOn = false
        var suspended = false
        var deletionRequested = false
    }
}

public struct SpeechWatch: Equatable, Sendable {
    public var childID: UUID?
    public var consentActive: Bool
    public var flagOn: Bool

    public init(childID: UUID?, consentActive: Bool, flagOn: Bool) {
        self.childID = childID
        self.consentActive = consentActive
        self.flagOn = flagOn
    }
}
