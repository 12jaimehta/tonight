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

    public init(offer: PaywallOffer, price: RupeePrice) {
        self.offer = offer
        self.price = price
    }
}

/// Local prices. Nothing here contacts a store or the network.
public enum PaywallCatalog {
    public static let trialNights = 7
    public static let monthly = RupeePrice(rupees: 149)
    public static let annualCap = RupeePrice(rupees: 1499)

    public static var prices: [CatalogPrice] {
        [
            CatalogPrice(offer: .monthly, price: monthly),
            CatalogPrice(offer: .annual, price: annualCap),
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
