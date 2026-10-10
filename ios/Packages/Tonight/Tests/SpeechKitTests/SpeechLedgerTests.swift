import Foundation
import os
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

    func test_CG32_appConstructsTheConsentCenter() throws {
        let app = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TonightApp/TonightApp.swift")
        let source = try String(contentsOf: app, encoding: .utf8)
        XCTAssertTrue(source.contains("ConsentCenter.make"), "the app must construct the consent store")
        XCTAssertTrue(source.contains("ChildWithdrawalErase"))
        XCTAssertFalse(source.contains("IgnoringChildEraser"), "a missing store must not erase nothing and continue")
        let model = try String(contentsOf: app.deletingLastPathComponent().appendingPathComponent("Flow/TonightModel.swift"), encoding: .utf8)
        XCTAssertTrue(model.contains("consentStore.clear()"))
        XCTAssertTrue(model.contains("consentCenter.withdraw"))
        let root = try String(contentsOf: app.deletingLastPathComponent().appendingPathComponent("RootView.swift"), encoding: .utf8)
        XCTAssertTrue(root.contains("consentCenter.flush"))
        let sheet = try String(contentsOf: app.deletingLastPathComponent().appendingPathComponent("Screens/M1/WithdrawConsentSheet.swift"), encoding: .utf8)
        XCTAssertTrue(sheet.contains("consent.withdraw.confirm"))
        let directory = try makeDirectory()
        let center = try ConsentCenter.make(directory: directory, eraser: IgnoringChildEraser(), sender: FailingDeletionSender())
        try center.grant(record(child: child))
        let relaunched = try ConsentCenter.make(directory: directory, eraser: IgnoringChildEraser(), sender: FailingDeletionSender())
        XCTAssertEqual(relaunched.record(for: child)?.scopeIsActive(.onDevice), true)
    }

    func test_DEL07_queuedDeletionReachesTheBackendAndRetries() async throws {
        let directory = try makeDirectory()
        let sender = ScriptedDeletionSender(failuresRemaining: 1)
        let center = try ConsentCenter.make(directory: directory, eraser: IgnoringChildEraser(), sender: sender)
        try center.grant(record(child: child))
        _ = try center.ledger.storeAudio(Data([1, 2, 3]), childProfileID: child, serverPath: true)
        let at = Date(timeIntervalSince1970: 9_000)
        let effect = try await center.withdraw(childProfileID: child, at: at)
        XCTAssertTrue(effect.queuedServerDeletion)
        XCTAssertEqual(effect.deletedAudioBytes, 3)
        XCTAssertTrue(sender.sent.isEmpty)
        XCTAssertEqual(center.ledger.deletionQueue().first?.attempts, 1)
        XCTAssertTrue(center.ledger.dueDeletions(at: at).isEmpty)
        await center.flush(at: at.addingTimeInterval(1))
        XCTAssertEqual(sender.sent.map(\.childProfileID), [child])
        XCTAssertEqual(sender.sent.first?.prefix, "\(child.uuidString)/")
        XCTAssertNotNil(center.ledger.deletionQueue().first?.completedAt)
    }

    func test_DEL08_serverOnlyWithdrawalKeepsRememberWords() async throws {
        let directory = try makeDirectory()
        let eraser = RecordingChildEraser()
        let sender = ScriptedDeletionSender(failuresRemaining: 0)
        let center = try ConsentCenter.make(directory: directory, eraser: eraser, sender: sender)
        try center.grant(record(child: child))
        try center.ledger.addRememberWord("apple", childProfileID: child)
        _ = try center.ledger.storeText("heard", childProfileID: child, kind: .transcript, serverPath: true)
        let effect = try await center.withdraw(childProfileID: child, scopes: [.server], at: Date())
        XCTAssertTrue(effect.queuedServerDeletion)
        XCTAssertEqual(effect.deletedRememberWords, 0)
        XCTAssertEqual(eraser.erased, [])
        XCTAssertEqual(center.ledger.rememberWords(childProfileID: child).map(\.word), ["apple"])
        XCTAssertEqual(center.record(for: child)?.scopeIsActive(.server), false)
        XCTAssertEqual(center.record(for: child)?.scopeIsActive(.onDevice), true)
        XCTAssertEqual(sender.sent.count, 1)
    }

    func test_DEL15_deletionPostUsesTheConfiguredHost() async throws {
        let host = URL(string: "https://project-ref.supabase.co")!
        TonightEndpoints.use(SupabaseSpeechConfig(baseURL: host, anonKey: "anon-test"))
        let child = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let job = ServerDeletionJob(
            id: UUID(),
            childProfileID: child,
            prefix: "\(child.uuidString)/",
            enqueuedAt: Date(timeIntervalSince1970: 10),
            attempts: 0,
            nextAttemptAt: Date(timeIntervalSince1970: 10),
            completedAt: nil
        )
        let captured = OSAllocatedUnfairLock<URLRequest?>(initialState: nil)
        let sender = HostDeletionSender(
            post: { request in captured.withLock { $0 = request } },
            baseURL: host,
            anonKey: "anon-test",
            accessToken: "parent-token"
        )
        try await sender.send(job)
        let request = try XCTUnwrap(captured.withLock { $0 })
        XCTAssertEqual(request.url?.host, "project-ref.supabase.co")
        XCTAssertEqual(request.url?.path, "/functions/v1/storage-purge")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer parent-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon-test")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]
        XCTAssertEqual(body, ["mode": "due"])
        XCTAssertNil(body?["child_profile_id"])
        XCTAssertNil(body?["object_prefix"])
    }

    func test_N12_deletionCallMatchesTheSharedContract() async throws {
        let contractURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("backend/supabase/functions/storage-purge/storage-purge.contract.json")
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: contractURL)) as? [String: Any]
        XCTAssertEqual(fixture?["name"] as? String, "storage-purge")
        let requestSpec = try XCTUnwrap(fixture?["request"] as? [String: Any])
        XCTAssertEqual(requestSpec["method"] as? String, "POST")
        XCTAssertEqual(requestSpec["path"] as? String, "/functions/v1/storage-purge")
        let headerSpec = try XCTUnwrap(requestSpec["headers"] as? [String: String])
        XCTAssertTrue(headerSpec["Authorization"]?.hasPrefix("Bearer ") == true)
        let bodySpec = try XCTUnwrap(requestSpec["body"] as? [String: Any])
        let required = try XCTUnwrap(bodySpec["required"] as? [String])
        XCTAssertEqual(required, ["mode"])
        let properties = try XCTUnwrap(bodySpec["properties"] as? [String: Any])
        let mode = try XCTUnwrap(properties["mode"] as? [String: Any])
        let allowed = try XCTUnwrap(mode["enum"] as? [String])
        XCTAssertEqual(allowed, ["due", "retention"])

        let host = URL(string: "https://project-ref.supabase.co")!
        TonightEndpoints.use(SupabaseSpeechConfig(baseURL: host, anonKey: "anon-test"))
        let captured = OSAllocatedUnfairLock<URLRequest?>(initialState: nil)
        let sender = HostDeletionSender(
            post: { request in captured.withLock { $0 = request } },
            baseURL: host,
            anonKey: "anon-test",
            accessToken: "parent-access-token"
        )
        let child = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        try await sender.send(ServerDeletionJob(
            id: UUID(),
            childProfileID: child,
            prefix: "\(child.uuidString)/",
            enqueuedAt: Date(timeIntervalSince1970: 10),
            attempts: 0,
            nextAttemptAt: Date(timeIntervalSince1970: 10),
            completedAt: nil
        ))
        let request = try XCTUnwrap(captured.withLock { $0 })
        XCTAssertEqual(request.httpMethod, requestSpec["method"] as? String)
        XCTAssertEqual(request.url?.path, requestSpec["path"] as? String)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer parent-access-token")
        XCTAssertFalse(request.value(forHTTPHeaderField: "Authorization") == "Bearer ")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]
        XCTAssertEqual(Set((body ?? [:]).keys), Set(required))
        XCTAssertTrue(allowed.contains(body?["mode"] ?? ""))
        XCTAssertEqual(body?["mode"], HostDeletionSender.dueMode)

        let empty = HostDeletionSender(
            post: { _ in },
            baseURL: host,
            anonKey: "anon-test",
            accessToken: ""
        )
        do {
            try await empty.send(ServerDeletionJob(
                id: UUID(),
                childProfileID: child,
                prefix: "\(child.uuidString)/",
                enqueuedAt: Date(),
                attempts: 0,
                nextAttemptAt: Date(),
                completedAt: nil
            ))
            XCTFail("an empty access token must not be sent")
        } catch DeletionSendError.notConfigured {
        } catch {
            XCTFail("unexpected \(error)")
        }

        let app = contractURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ios/TonightApp/TonightApp.swift")
        let source = try String(contentsOf: app, encoding: .utf8)
        XCTAssertTrue(source.contains("KeychainAccessTokenStore().load()"))
        XCTAssertFalse(source.contains("accessToken: \"\""))
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

private final class ScriptedDeletionSender: DeletionSending, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(failuresRemaining: Int) {
        state.withLock { $0.failuresRemaining = failuresRemaining }
    }

    var sent: [ServerDeletionJob] { state.withLock { $0.sent } }

    func send(_ job: ServerDeletionJob) async throws {
        let shouldFail = state.withLock { state -> Bool in
            if state.failuresRemaining > 0 {
                state.failuresRemaining -= 1
                return true
            }
            return false
        }
        if shouldFail { throw DeletionSendError.rejected(503) }
        state.withLock { $0.sent.append(job) }
    }

    private struct State {
        var failuresRemaining = 0
        var sent: [ServerDeletionJob] = []
    }
}

private final class RecordingChildEraser: ChildDataErasing, @unchecked Sendable {
    private let ids = OSAllocatedUnfairLock(initialState: [UUID]())
    var erased: [UUID] { ids.withLock { $0 } }
    func erase(childID: UUID) throws {
        ids.withLock { $0.append(childID) }
    }
}
