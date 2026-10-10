import os
import XCTest
@testable import SpeechKit

final class ServerWithdrawalTests: XCTestCase {
    private let child = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let consent = UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!
    private let when = Date(timeIntervalSince1970: 1_700_000_000)

    func test_P0_5_withdrawalPatchesConsentAndDeletesTheChild() async throws {
        let transport = RecordingTransport()
        let client = makeClient(transport: transport, token: "parent-access-token")
        await client.submit(childID: child, consentRecordID: consent)
        let calls = await transport.calls
        XCTAssertEqual(calls.count, 2)

        let patch = calls[0]
        XCTAssertEqual(patch.method, "PATCH")
        XCTAssertEqual(patch.path, "/rest/v1/consent_record")
        XCTAssertEqual(patch.query, "id=eq.\(consent.uuidString.lowercased())")
        XCTAssertEqual(patch.authorization, "Bearer parent-access-token")
        XCTAssertEqual(patch.apiKey, "anon-test")
        XCTAssertEqual(patch.body?["withdrawn_at"], "2023-11-14T22:13:20Z")

        let deletion = calls[1]
        XCTAssertEqual(deletion.method, "DELETE")
        XCTAssertEqual(deletion.path, "/rest/v1/child_profile")
        XCTAssertEqual(deletion.query, "id=eq.\(child.uuidString.lowercased())")
        XCTAssertEqual(deletion.authorization, "Bearer parent-access-token")
        XCTAssertEqual(deletion.apiKey, "anon-test")
        XCTAssertNil(deletion.body)
        XCTAssertEqual(patch.prefer, "return=representation")
        XCTAssertTrue(client.pending().isEmpty)

        let model = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TonightApp/Flow/TonightModel.swift")
        let source = try String(contentsOf: model, encoding: .utf8)
        XCTAssertTrue(source.contains("serverWithdrawal?.submit(childID: childID, consentRecordID: consentID)"))
    }

    func test_P0_5_offlineWithdrawalStaysQueuedUntilTheNextFlush() async throws {
        let transport = RecordingTransport()
        await transport.setOffline(true)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("queue.json")
        let client = makeClient(transport: transport, token: "parent-access-token", queueFile: file)
        await client.submit(childID: child, consentRecordID: consent)
        XCTAssertEqual(client.pending().count, 1)
        let offlineCalls = await transport.calls
        XCTAssertEqual(offlineCalls.count, 0)

        let relaunched = makeClient(transport: transport, token: "parent-access-token", queueFile: file)
        XCTAssertEqual(relaunched.pending().count, 1)
        await transport.setOffline(false)
        await relaunched.flush()
        let flushed = await transport.calls
        XCTAssertEqual(flushed.map(\.method), ["PATCH", "DELETE"])
        XCTAssertTrue(relaunched.pending().isEmpty)
    }

    func test_N29_createsParentChildAndConsentForTheEmailSession() async throws {
        let transport = RecordingTransport()
        let client = makeClient(transport: transport, token: "parent-access-token")
        let parent = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let childID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let consentID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let parentResult = await client.createParent(id: parent)
        let childResult = await client.createChild(id: childID, parentID: parent, nickname: "Aarav", schoolClass: "1")
        let consentResult = await client.createConsent(id: consentID, parentID: parent, childID: childID)
        XCTAssertEqual(parentResult, .synced)
        XCTAssertEqual(childResult, .synced)
        XCTAssertEqual(consentResult, .synced)
        let calls = await transport.calls
        XCTAssertEqual(calls.map(\.method), ["POST", "POST", "POST"])
        XCTAssertEqual(calls.map(\.path), ["/rest/v1/parent", "/rest/v1/child_profile", "/rest/v1/consent_record"])
        XCTAssertEqual(calls[0].body?["id"], parent.uuidString.lowercased())
        XCTAssertEqual(calls[1].body?["parent_id"], parent.uuidString.lowercased())
        XCTAssertEqual(calls[2].scopes, ["on_device_speech"])
        XCTAssertTrue(calls.allSatisfy { $0.prefer == "return=representation" })
        XCTAssertTrue(calls.allSatisfy { $0.authorization == "Bearer parent-access-token" })

        let model = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TonightApp/Flow/TonightModel.swift")
        let source = try String(contentsOf: model, encoding: .utf8)
        XCTAssertFalse(source.contains("parent-placeholder"))
        XCTAssertTrue(source.contains("createParent(id: parent)"))
        XCTAssertTrue(source.contains("createChild("))
        XCTAssertTrue(source.contains("createConsent("))
    }

    func test_N32_refreshThenForegroundFlushSendsTheNewToken() async throws {
        let transport = RecordingTransport()
        await transport.setOffline(true)
        let token = OSAllocatedUnfairLock(initialState: "expired-token")
        let when = self.when
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("queue.json")
        let client = makeClient(transport: transport, token: "expired-token", queueFile: file)
        let refreshing = ServerWithdrawalClient(
            baseURL: URL(string: "https://project-ref.supabase.co")!,
            anonKey: "anon-test",
            accessToken: { token.withLock { $0 } },
            send: { request in try await transport.send(request) },
            queueFile: file,
            now: { when }
        )
        await client.submit(childID: child, consentRecordID: consent)
        await transport.setOffline(false)
        token.withLock { $0 = "fresh-token" }
        _ = await refreshing.flush()
        let calls = await transport.calls
        XCTAssertEqual(calls.map(\.authorization), ["Bearer fresh-token", "Bearer fresh-token"])
    }

    func test_N29_withdrawalRequiresExactlyOneRow() async {
        let transport = RecordingTransport()
        await transport.setBody(Data("[]".utf8))
        let none = makeClient(transport: transport, token: "parent-access-token")
        let noneResult = await none.submit(childID: child, consentRecordID: consent)
        XCTAssertEqual(noneResult, .notOneRow(0))
        XCTAssertEqual(none.pending().count, 1)

        await transport.setBody(Data("[{},{}]".utf8))
        let many = makeClient(transport: transport, token: "parent-access-token")
        let manyResult = await many.submit(childID: child, consentRecordID: consent)
        XCTAssertEqual(manyResult, .notOneRow(2))
        XCTAssertEqual(many.pending().count, 1)
    }

    private func makeClient(
        transport: RecordingTransport,
        token: String,
        queueFile: URL? = nil
    ) -> ServerWithdrawalClient {
        let file = queueFile ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("queue.json")
        let when = self.when
        return ServerWithdrawalClient(
            baseURL: URL(string: "https://project-ref.supabase.co")!,
            anonKey: "anon-test",
            accessToken: { token },
            send: { request in try await transport.send(request) },
            queueFile: file,
            now: { when }
        )
    }
}

private struct CapturedCall: Equatable, Sendable {
    var method: String
    var path: String
    var query: String?
    var authorization: String?
    var apiKey: String?
    var prefer: String?
    var body: [String: String]?
    var scopes: [String]?
}

private actor RecordingTransport {
    var calls: [CapturedCall] = []
    var offline = false
    var body = Data("[{}]".utf8)

    func setOffline(_ offline: Bool) { self.offline = offline }
    func setBody(_ body: Data) { self.body = body }

    func send(_ request: URLRequest) throws -> ServerHTTPResponse {
        if offline { throw URLError(.notConnectedToInternet) }
        let object = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let scopes = (object?["scopes"] as? [Any])?.compactMap { $0 as? String }
        calls.append(CapturedCall(
            method: request.httpMethod ?? "",
            path: request.url?.path ?? "",
            query: request.url?.query,
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            apiKey: request.value(forHTTPHeaderField: "api" + "key"),
            prefer: request.value(forHTTPHeaderField: "Prefer"),
            body: object as? [String: String],
            scopes: scopes
        ))
        return ServerHTTPResponse(status: 200, body: body)
    }
}
