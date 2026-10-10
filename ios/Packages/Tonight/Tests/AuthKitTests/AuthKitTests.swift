import os
import XCTest
@testable import AuthKit

final class AuthKitTests: XCTestCase {
    func testInMemoryStoreRoundTripsASession() throws {
        let store = InMemorySessionStore()
        let issued = Date(timeIntervalSince1970: 1_700_000_000)
        let session = ParentSession.issue(parentID: "parent-1", at: issued, id: UUID())
        try store.save(session)
        XCTAssertEqual(try store.load(), session)
        XCTAssertTrue(session.isValid(at: issued))
        XCTAssertFalse(session.isValid(at: issued.addingTimeInterval(ParentSession.defaultLifetime)))
        try store.clear()
        XCTAssertNil(try store.load())
    }

    func testEncodedSessionHasNoPIN() throws {
        let session = ParentSession.issue(
            parentID: "parent-1",
            at: Date(timeIntervalSince1970: 1_700_000_000),
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        )
        let data = try SessionCodec.encode(session)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(Set(object?.keys.map { $0.lowercased() } ?? []), ["id", "parentid", "issuedat", "expiresat"])
        let text = String(data: data, encoding: .utf8)?.lowercased() ?? ""
        XCTAssertFalse(text.contains("pin"))
        let decoded = try SessionCodec.decode(data)
        XCTAssertEqual(decoded, session)
    }

    func testKeychainAccountIsASession() {
        XCTAssertEqual(KeychainSessionQuery.account, "session")
        XCTAssertFalse(KeychainSessionQuery.storesPIN)
        XCTAssertEqual(KeychainSessionQuery.service, "com.tonight.homework.parent-session")
        XCTAssertFalse(KeychainSessionQuery.lookup().values.contains { value in
            String(describing: value).lowercased().contains("pin")
        })
    }

    func test_N13_emailOTPRequestsAndVerifiesOnTheConfiguredHost() async throws {
        let host = URL(string: "https://project-ref.supabase.co")!
        let transport = ScriptedOTPTransport()
        let sessions = InMemorySessionStore()
        let tokens = InMemoryAccessTokenStore()
        let client = EmailOTPClient(
            config: SupabaseAuthConfig(baseURL: host, anonKey: "anon-test"),
            transport: transport,
            sessions: sessions,
            tokens: tokens,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        transport.next = (Data("{}".utf8), 200)
        try await client.requestCode(email: "Parent@Example.com")
        let verifyBody = """
        {"access_token":"parent-token","expires_in":3600,"user":{"id":"parent-1"}}
        """.data(using: .utf8)!
        transport.next = (verifyBody, 200)
        let session = try await client.verify(email: "parent@example.com", code: "123456")
        XCTAssertEqual(session.parentID, "parent-1")
        XCTAssertEqual(try sessions.load()?.parentID, "parent-1")
        XCTAssertEqual(try tokens.load(), "parent-token")
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].url?.host, "project-ref.supabase.co")
        XCTAssertEqual(transport.requests[0].url?.path, "/auth/v1/otp")
        XCTAssertEqual(transport.requests[1].url?.path, "/auth/v1/verify")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "apikey"), "anon-test")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer anon-test")
        let otp = try JSONSerialization.jsonObject(with: transport.requests[0].httpBody ?? Data()) as? [String: Any]
        XCTAssertEqual(otp?["email"] as? String, "parent@example.com")
        let verify = try JSONSerialization.jsonObject(with: transport.requests[1].httpBody ?? Data()) as? [String: Any]
        XCTAssertEqual(verify?["token"] as? String, "123456")
        XCTAssertEqual(verify?["type"] as? String, "email")
        XCTAssertFalse(transport.requests.contains { $0.url?.host?.contains("sarvam") == true })
    }

    func test_N13_emailOTPRejectsAnyOtherHost() async throws {
        let transport = ScriptedOTPTransport()
        let client = EmailOTPClient(
            config: SupabaseAuthConfig(baseURL: URL(string: "https://api.sarvam.ai")!, anonKey: "nope"),
            transport: transport,
            sessions: InMemorySessionStore(),
            tokens: InMemoryAccessTokenStore()
        )
        do {
            try await client.requestCode(email: "parent@example.com")
            XCTFail("expected the host to be rejected")
        } catch EmailOTPError.hostNotAllowed {
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertThrowsError(try EmailOTPClient.endpoint(URL(string: "http://project-ref.supabase.co")!, path: "otp"))
    }

    func test_N13_signInWithAppleStaysOffUnlessTheFlagIsSet() throws {
        #if SIGN_IN_WITH_APPLE
        XCTAssertTrue(SignInWithApple.isEnabled)
        #else
        XCTAssertFalse(SignInWithApple.isEnabled)
        #endif
        let view = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TonightApp/EmailSignInView.swift")
        let source = try String(contentsOf: view, encoding: .utf8)
        XCTAssertTrue(source.contains("#if SIGN_IN_WITH_APPLE"))
        XCTAssertFalse(source.contains("Nothing leaves the phone"))
    }

    func testAdultConsentIsStoredInMemory() {
        let store = InMemoryAdultConsentStore()
        XCTAssertNil(store.current())
        let record = AdultConsentRecord(
            parentID: "parent-1",
            acceptedAt: Date(timeIntervalSince1970: 1_700_000_000),
            method: "stub"
        )
        store.save(record)
        XCTAssertEqual(store.current(), record)
        XCTAssertEqual(store.current()?.version, AdultConsentRecord.currentVersion)
        store.clear()
        XCTAssertNil(store.current())
    }
}

private final class ScriptedOTPTransport: OTPTransporting, @unchecked Sendable {
    var next: (Data, Int) = (Data("{}".utf8), 200)
    private let sent = OSAllocatedUnfairLock(initialState: [URLRequest]())

    var requests: [URLRequest] { sent.withLock { $0 } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sent.withLock { $0.append(request) }
        let response = HTTPURLResponse(url: request.url!, statusCode: next.1, httpVersion: nil, headerFields: nil)
        return (next.0, try XCTUnwrap(response))
    }
}
