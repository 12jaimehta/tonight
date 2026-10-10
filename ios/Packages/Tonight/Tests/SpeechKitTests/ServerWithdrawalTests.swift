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
        XCTAssertEqual(await transport.calls.count, 0)

        let relaunched = makeClient(transport: transport, token: "parent-access-token", queueFile: file)
        XCTAssertEqual(relaunched.pending().count, 1)
        await transport.setOffline(false)
        await relaunched.flush()
        XCTAssertEqual(await transport.calls.map(\.method), ["PATCH", "DELETE"])
        XCTAssertTrue(relaunched.pending().isEmpty)
    }

    private func makeClient(
        transport: RecordingTransport,
        token: String,
        queueFile: URL? = nil
    ) -> ServerWithdrawalClient {
        let file = queueFile ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("queue.json")
        return ServerWithdrawalClient(
            baseURL: URL(string: "https://project-ref.supabase.co")!,
            anonKey: "anon-test",
            accessToken: { token },
            send: { request in try await transport.send(request) },
            queueFile: file,
            now: { self.when }
        )
    }
}

private struct CapturedCall: Equatable {
    var method: String
    var path: String
    var query: String?
    var authorization: String?
    var apiKey: String?
    var body: [String: String]?
}

private actor RecordingTransport {
    var calls: [CapturedCall] = []
    var offline = false

    func setOffline(_ offline: Bool) { self.offline = offline }

    func send(_ request: URLRequest) throws -> Int {
        if offline { throw URLError(.notConnectedToInternet) }
        let body: [String: String]?
        if let data = request.httpBody {
            body = try JSONSerialization.jsonObject(with: data) as? [String: String]
        } else {
            body = nil
        }
        calls.append(CapturedCall(
            method: request.httpMethod ?? "",
            path: request.url?.path ?? "",
            query: request.url?.query,
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            apiKey: request.value(forHTTPHeaderField: "api" + "key"),
            body: body
        ))
        return 204
    }
}
