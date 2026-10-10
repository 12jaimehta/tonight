import Foundation

public struct RupeePrice: Equatable, Sendable, Hashable {
    public var rupees: Int
    public var currency: String

    public init(rupees: Int, currency: String = "INR") {
        self.rupees = rupees
        self.currency = currency
    }
}

public enum PaywallOffer: String, Codable, CaseIterable, Sendable {
    case monthly
    case annual
}

public struct CatalogPrice: Equatable, Sendable {
    public var offer: PaywallOffer
    public var price: RupeePrice
    /// Free nights included with this offer. Zero means there is no trial.
    public var trialNights: Int

    public init(offer: PaywallOffer, price: RupeePrice, trialNights: Int = 0) {
        self.offer = offer
        self.price = price
        self.trialNights = trialNights
    }
}

/// Local prices. Nothing here contacts a store or the network.
public enum PaywallCatalog {
    /// Length of the annual plan's free trial. The monthly plan has no trial.
    public static let trialNights = 7
    public static let monthly = RupeePrice(rupees: 149)
    /// Annual price. A higher annual price is not offered.
    public static let annualCap = RupeePrice(rupees: 999)
    public static let monthlyProductID = "com.tonight.homework.monthly"
    public static let annualProductID = "com.tonight.homework.annual"
    /// Family Sharing is not offered.
    public static let familySharingOffered = false

    public static func trialNights(for offer: PaywallOffer) -> Int {
        switch offer {
        case .monthly:
            return 0
        case .annual:
            return trialNights
        }
    }

    public static var prices: [CatalogPrice] {
        [
            CatalogPrice(offer: .monthly, price: monthly, trialNights: trialNights(for: .monthly)),
            CatalogPrice(offer: .annual, price: annualCap, trialNights: trialNights(for: .annual)),
        ]
    }

    public static func annualIsWithinCap(_ rupees: Int) -> Bool {
        rupees <= annualCap.rupees
    }
}

public struct PaywallFlags: Equatable, Sendable {
    /// Off until a later release. The catalogue can be read either way.
    public var purchasesEnabled: Bool

    public init(purchasesEnabled: Bool = false) {
        self.purchasesEnabled = purchasesEnabled
    }
}

public enum PaywallAccess {
    /// Both the flag and the parental gate have to allow it.
    public static func canPresent(flag: PaywallFlags, parentUnlocked: Bool) -> Bool {
        flag.purchasesEnabled && parentUnlocked
    }
}

public struct Trial: Equatable, Sendable {
    public var startedAt: Date
    public var nights: Int

    public init(startedAt: Date, nights: Int = PaywallCatalog.trialNights) {
        self.startedAt = startedAt
        self.nights = nights
    }

    public func endsAt() -> Date {
        startedAt.addingTimeInterval(TimeInterval(nights) * 24 * 60 * 60)
    }

    public func isActive(at date: Date) -> Bool {
        date >= startedAt && date < endsAt()
    }
}

public protocol PriceListing: Sendable {
    func prices() -> [CatalogPrice]
}

public struct LocalPriceList: PriceListing {
    public init() {}

    public func prices() -> [CatalogPrice] {
        PaywallCatalog.prices
    }
}
