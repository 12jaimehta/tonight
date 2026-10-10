import XCTest
@testable import SpeechKit

final class SpeechLedgerTests: XCTestCase {
    private let child = UUID()
    private let other = UUID()

    func test_CG32_consentSurvivesRelaunch() throws {
        let directory = try makeDirectory()
        let first = try SpeechLedger(directory: directory)
        try first.grant(record(child: child))
        let second = try SpeechLedger(directory: directory)
        XCTAssertEqual(second.record(for: child)?.scopeIsActive(.server), true)
        XCTAssertEqual(second.record(for: other), nil)
    }

    func test_DEL01_withdrawalDeletesAudioBeforeReturning() throws {
        let directory = try makeDirectory()
        let ledger = try SpeechLedger(directory: directory)
        try ledger.grant(record(child: child))
        _ = try ledger.storeAudio(Data([1, 2, 3, 4]), childProfileID: child, serverPath: true)
        _ = try ledger.storeAudio(Data([9]), childProfileID: other, serverPath: false)
        let effect = try ledger.withdraw(childProfileID: child, at: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(effect.deletedAudioBytes, 4)
        XCTAssertTrue(try ledger.liveArtefacts(childProfileID: child).isEmpty)
        let folder = directory.appendingPathComponent(child.uuidString)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertTrue(files.isEmpty)
        let kept = try SpeechLedger(directory: directory)
        XCTAssertEqual(try kept.liveArtefacts(childProfileID: other).count, 1)
    }

    func test_DEL02_withdrawalDeletesTranscripts() throws {
        let ledger = try SpeechLedger(directory: makeDirectory())
        _ = try ledger.storeText("the cat", childProfileID: child, kind: .transcript, serverPath: true)
        _ = try ledger.storeText("sibling", childProfileID: other, kind: .transcript, serverPath: false)
        let effect = try ledger.withdraw(childProfileID: child, at: Date())
        XCTAssertEqual(effect.deletedTranscripts, 1)
        XCTAssertTrue(ledger.liveArtefacts(childProfileID: child).isEmpty)
        XCTAssertEqual(ledger.liveArtefacts(childProfileID: other).count, 1)
    }

    func test_DEL07_deletionQueueRetriesWithBackoff() throws {
        let ledger = try SpeechLedger(directory: makeDirectory())
        try ledger.grant(record(child: child))
        _ = try ledger.storeText("heard", childProfileID: child, kind: .transcript, serverPath: true)
        let at = Date(timeIntervalSince1970: 5_000)
        let effect = try ledger.withdraw(childProfileID: child, at: at)
        XCTAssertTrue(effect.queuedServerDeletion)
        let job = try XCTUnwrap(ledger.deletionQueue().first)
        XCTAssertEqual(job.prefix, "\(child.uuidString)/")
        XCTAssertEqual(ledger.dueDeletions(at: at).map(\.id), [job.id])
        try ledger.recordDeletionAttempt(id: job.id, at: at, succeeded: false)
        XCTAssertTrue(ledger.dueDeletions(at: at.addingTimeInterval(0.5)).isEmpty)
        XCTAssertEqual(ledger.dueDeletions(at: at.addingTimeInterval(1)).map(\.id), [job.id])
        try ledger.recordDeletionAttempt(id: job.id, at: at.addingTimeInterval(1), succeeded: true)
        XCTAssertNotNil(ledger.deletionQueue().first?.completedAt)
        XCTAssertTrue(ledger.dueDeletions(at: at.addingTimeInterval(10_000)).isEmpty)
    }

    func test_DEL18_withdrawalDeletesAlignment() throws {
        let ledger = try SpeechLedger(directory: makeDirectory())
        _ = try ledger.storeText("the:match", childProfileID: child, kind: .alignment, serverPath: false)
        let effect = try ledger.withdraw(childProfileID: child, at: Date())
        XCTAssertEqual(effect.deletedAlignments, 1)
        XCTAssertTrue(ledger.liveArtefacts(childProfileID: child).isEmpty)
    }

    func test_DEL19_withdrawalDeletesRememberWords() throws {
        let ledger = try SpeechLedger(directory: makeDirectory())
        try ledger.addRememberWord("apple", childProfileID: child)
        try ledger.addRememberWord("kept", childProfileID: other)
        let effect = try ledger.withdraw(childProfileID: child, at: Date())
        XCTAssertEqual(effect.deletedRememberWords, 1)
        XCTAssertTrue(ledger.rememberWords(childProfileID: child).isEmpty)
        XCTAssertEqual(ledger.rememberWords(childProfileID: other).map(\.word), ["kept"])
    }

    func test_DEL20_withdrawalWritesAnAuditRow() throws {
        let directory = try makeDirectory()
        let ledger = try SpeechLedger(directory: directory)
        try ledger.grant(record(child: child))
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try ledger.withdraw(childProfileID: child, at: at)
        let reloaded = try SpeechLedger(directory: directory)
        let entry = try XCTUnwrap(reloaded.auditSnapshot().first)
        XCTAssertEqual(entry.childProfileID, child)
        XCTAssertEqual(entry.reason, "withdrawn")
        XCTAssertEqual(entry.ts, at)
        XCTAssertEqual(reloaded.record(for: child)?.scopeIsActive(.onDevice), false)
        XCTAssertEqual(reloaded.record(for: child)?.scopeIsActive(.server), false)
    }

    func test_PRIV05_withdrawalIsStillWithdrawnAfterRelaunch() throws {
        let directory = try makeDirectory()
        let ledger = try SpeechLedger(directory: directory)
        try ledger.grant(record(child: child))
        try ledger.addMarkCorrection("parent changed the mark", childProfileID: child)
        let effect = try ledger.withdraw(childProfileID: child, at: Date())
        XCTAssertEqual(effect.deletedMarks, 1)
        let reloaded = try SpeechLedger(directory: directory)
        XCTAssertNotNil(reloaded.record(for: child)?.withdrawnAt)
        XCTAssertTrue(reloaded.markCorrections(childProfileID: child).isEmpty)
        XCTAssertFalse(reloaded.auditSnapshot().isEmpty)
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func record(child: UUID) -> AudioConsentRecord {
        AudioConsentRecord(
            parentID: "parent",
            childProfileID: child,
            scopes: [.onDevice, .server],
            tappedAt: Date(timeIntervalSince1970: 1_700_000_000),
            method: "screen",
            backendConfirmed: true
        )
    }
}
