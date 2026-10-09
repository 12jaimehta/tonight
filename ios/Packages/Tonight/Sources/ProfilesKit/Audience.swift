import Foundation

/// Who v1 is for. Classes and the age band are configuration, not scattered literals.
public struct AudienceConfig: Codable, Hashable, Sendable {
    public var classes: [String]
    public var ageBandID: String
    public var ageMin: Int
    public var ageMax: Int
    public var appleKidsBand: String

    public init(classes: [String], ageBandID: String, ageMin: Int, ageMax: Int, appleKidsBand: String) {
        self.classes = classes
        self.ageBandID = ageBandID
        self.ageMin = ageMin
        self.ageMax = ageMax
        self.appleKidsBand = appleKidsBand
    }

    /// Classes 1–3, ages 6–8, Apple Kids band 6–8.
    public static let v1 = AudienceConfig(
        classes: ["1", "2", "3"],
        ageBandID: "6-8",
        ageMin: 6,
        ageMax: 8,
        appleKidsBand: "6-8"
    )
}
