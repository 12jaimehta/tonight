import XCTest
@testable import AuthKit

final class AuthKitTests: XCTestCase {
    func testInMemoryStoreRoundTripsASession() throws {
        let store = InMemorySessionStore()
        let issued = Date(timeIntervalSince1970: 1_700_000_000)
        let session = ParentSession.issue(parentID: "parent-1", at: issued, id: UUID(), accessToken: "parent-session-token")
        try store.save(session)
        XCTAssertEqual(try store.load(), session)
        XCTAssertEqual(try store.load()?.accessToken, "parent-session-token")
        XCTAssertTrue(session.isValid(at: issued))
        XCTAssertFalse(session.isValid(at: issued.addingTimeInterval(ParentSession.defaultLifetime)))
        try store.clear()
        XCTAssertNil(try store.load())
    }

    func testEncodedSessionHasNoPIN() throws {
        let session = ParentSession.issue(
            parentID: "parent-1",
            at: Date(timeIntervalSince1970: 1_700_000_000),
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            accessToken: "parent-session-token"
        )
        let data = try SessionCodec.encode(session)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(Set(object?.keys.map { $0.lowercased() } ?? []), ["id", "parentid", "issuedat", "expiresat", "accesstoken"])
        let text = String(data: data, encoding: .utf8)?.lowercased() ?? ""
        XCTAssertFalse(text.contains("pin"))
        let decoded = try SessionCodec.decode(data)
        XCTAssertEqual(decoded, session)
        let legacy = String(data: data, encoding: .utf8)?.replacingOccurrences(of: "\"accessToken\":\"parent-session-token\",", with: "") ?? ""
        let legacySession = try SessionCodec.decode(Data(legacy.utf8))
        XCTAssertEqual(legacySession.accessToken, "")
        XCTAssertEqual(legacySession.parentID, session.parentID)
    }

    func testKeychainAccountIsASession() {
        XCTAssertEqual(KeychainSessionQuery.account, "session")
        XCTAssertFalse(KeychainSessionQuery.storesPIN)
        XCTAssertEqual(KeychainSessionQuery.service, "com.tonight.homework.parent-session")
        XCTAssertFalse(KeychainSessionQuery.lookup().values.contains { value in
            String(describing: value).lowercased().contains("pin")
        })
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
