import XCTest
@testable import PaywallKit

final class PaywallKitTests: XCTestCase {
    func testTrialLastsSevenNights() {
        let start = Date(timeIntervalSince1970: 1_000)
        let trial = Trial(startedAt: start)
        XCTAssertEqual(trial.nights, 7)
        XCTAssertEqual(PaywallCatalog.trialNights, 7)
        XCTAssertTrue(trial.isActive(at: start))
        XCTAssertTrue(trial.isActive(at: start.addingTimeInterval(6 * 86_400)))
        XCTAssertFalse(trial.isActive(at: start.addingTimeInterval(7 * 86_400)))
    }

    func testPricesAreMonthly149AndAnnualCap1499() {
        XCTAssertEqual(PaywallCatalog.monthly, RupeePrice(rupees: 149, currency: "INR"))
        XCTAssertEqual(PaywallCatalog.annualCap, RupeePrice(rupees: 1499, currency: "INR"))
        XCTAssertGreaterThan(149 * 12, PaywallCatalog.annualCap.rupees)
        XCTAssertTrue(PaywallCatalog.annualIsWithinCap(1499))
        XCTAssertFalse(PaywallCatalog.annualIsWithinCap(1500))
        XCTAssertEqual(LocalPriceList().prices().map(\.offer), [.monthly, .annual])
    }

    func testFlagIsOffAndTheGateIsRequired() {
        let off = PaywallFlags()
        XCTAssertFalse(off.purchasesEnabled)
        XCTAssertFalse(PaywallAccess.canPresent(flag: off, parentUnlocked: true))
        XCTAssertFalse(PaywallAccess.canPresent(flag: PaywallFlags(purchasesEnabled: true), parentUnlocked: false))
        XCTAssertTrue(PaywallAccess.canPresent(flag: PaywallFlags(purchasesEnabled: true), parentUnlocked: true))
    }

    func testSourcesDoNotTalkToAStore() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PaywallKit")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        let text = try files.filter { $0.pathExtension == "swift" }.map { try String(contentsOf: $0) }.joined(separator: "\n")
        XCTAssertFalse(text.contains("import StoreKit"))
        XCTAssertFalse(text.contains("SKProductsRequest"))
        XCTAssertFalse(text.contains("https://"))
    }
}
