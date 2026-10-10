import XCTest
@testable import PaywallKit

final class PaywallKitTests: XCTestCase {
    func testAnnualTrialLastsSevenNightsAndMonthlyHasNone() {
        XCTAssertEqual(PaywallCatalog.trialNights(for: .monthly), 0)
        XCTAssertEqual(PaywallCatalog.trialNights(for: .annual), 7)
        let start = Date(timeIntervalSince1970: 1_000)
        let trial = Trial(startedAt: start, nights: PaywallCatalog.trialNights(for: .annual))
        XCTAssertEqual(trial.nights, 7)
        XCTAssertEqual(PaywallCatalog.trialNights, 7)
        XCTAssertTrue(trial.isActive(at: start))
        XCTAssertTrue(trial.isActive(at: start.addingTimeInterval(6 * 86_400)))
        XCTAssertFalse(trial.isActive(at: start.addingTimeInterval(7 * 86_400)))
        let listed = LocalPriceList().prices()
        XCTAssertEqual(listed.first { $0.offer == .monthly }?.trialNights, 0)
        XCTAssertEqual(listed.first { $0.offer == .annual }?.trialNights, 7)
    }

    func testPricesAreMonthly149AndAnnual999() {
        XCTAssertEqual(PaywallCatalog.monthly, RupeePrice(rupees: 149, currency: "INR"))
        XCTAssertEqual(PaywallCatalog.annualCap, RupeePrice(rupees: 999, currency: "INR"))
        XCTAssertGreaterThan(149 * 12, PaywallCatalog.annualCap.rupees)
        XCTAssertTrue(PaywallCatalog.annualIsWithinCap(999))
        XCTAssertFalse(PaywallCatalog.annualIsWithinCap(1000))
        XCTAssertFalse(PaywallCatalog.annualIsWithinCap(1499))
        XCTAssertEqual(LocalPriceList().prices().map(\.offer), [.monthly, .annual])
        XCTAssertFalse(PaywallCatalog.familySharingOffered)
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
        XCTAssertFalse(files.isEmpty)
        XCTAssertFalse(text.contains("import StoreKit"))
        XCTAssertFalse(text.contains("SKProductsRequest"))
        XCTAssertFalse(text.contains("https://"))
    }

    func testLocalStoreKitMatchesTheCatalogue() throws {
        let iosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: iosRoot.appendingPathComponent("Tonight.storekit"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let settings = try XCTUnwrap(root["settings"] as? [String: Any])
        XCTAssertEqual(settings["_storefront"] as? String, "IND")
        let groups = try XCTUnwrap(root["subscriptionGroups"] as? [[String: Any]])
        let subscriptions = groups.flatMap { $0["subscriptions"] as? [[String: Any]] ?? [] }
        XCTAssertEqual(
            Set(subscriptions.compactMap { $0["productID"] as? String }),
            [PaywallCatalog.monthlyProductID, PaywallCatalog.annualProductID]
        )
        let monthly = try XCTUnwrap(subscriptions.first { $0["productID"] as? String == PaywallCatalog.monthlyProductID })
        let annual = try XCTUnwrap(subscriptions.first { $0["productID"] as? String == PaywallCatalog.annualProductID })
        XCTAssertEqual(rupees(in: monthly), PaywallCatalog.monthly.rupees)
        XCTAssertEqual(rupees(in: annual), PaywallCatalog.annualCap.rupees)
        XCTAssertNil(introductoryOffer(in: monthly))
        let trial = try XCTUnwrap(introductoryOffer(in: annual))
        XCTAssertEqual(trial["subscriptionPeriod"] as? String, "P1W")
        XCTAssertEqual(trial["numberOfPeriods"] as? Int, 1)
        let mode = try XCTUnwrap(trial["paymentMode"] as? String)
        XCTAssertTrue(mode == "free" || mode == "freeTrial")
        for subscription in subscriptions {
            XCTAssertEqual(subscription["familyShareable"] as? Bool, false)
        }
        XCTAssertFalse(PaywallCatalog.familySharingOffered)
        let scheme = try String(
            contentsOf: iosRoot.appendingPathComponent("Tonight.xcodeproj/xcshareddata/xcschemes/Tonight.xcscheme")
        )
        XCTAssertEqual(scheme.components(separatedBy: "<StoreKitConfigurationFileReference").count - 1, 2)
        XCTAssertTrue(scheme.contains("../Tonight.storekit"))
    }

    private func rupees(in subscription: [String: Any]) -> Int? {
        guard let display = subscription["displayPrice"] as? String else { return nil }
        return Int(display.split(separator: ".").first ?? "")
    }

    private func introductoryOffer(in subscription: [String: Any]) -> [String: Any]? {
        if let offer = subscription["introductoryOffer"] as? [String: Any] {
            return offer
        }
        if let offers = subscription["introductoryOffers"] as? [[String: Any]] {
            return offers.first
        }
        return nil
    }
}
