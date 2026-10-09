import XCTest
@testable import ProfilesKit

final class SubjectCatalogTests: XCTestCase {
    func testAudienceIsClasses1To3Ages6To8() {
        let audience = AudienceConfig.v1
        XCTAssertEqual(audience.classes, ["1", "2", "3"])
        XCTAssertEqual(audience.ageBandID, "6-8")
        XCTAssertEqual(audience.ageMin, 6)
        XCTAssertEqual(audience.ageMax, 8)
        XCTAssertEqual(audience.appleKidsBand, "6-8")
    }

    func testHindiMathsAndEVSAreTheDefaults() {
        for schoolClass in AudienceConfig.v1.classes {
            XCTAssertEqual(SubjectCatalog.defaults(for: schoolClass).map(\.id), ["hindi", "maths", "evs"])
        }
        XCTAssertEqual(SubjectCatalog.defaults(for: "4").map(\.id), ["hindi", "maths", "evs"])
        let optional = SubjectCatalog.all.filter { !$0.enabledByDefault }.map(\.id)
        XCTAssertTrue(optional.contains("english"))
        XCTAssertFalse(optional.contains("hindi"))
    }

    func testStateLanguagesUseTheirOwnScript() {
        let expected = [
            "hindi": "हिन्दी",
            "tamil": "தமிழ்",
            "telugu": "తెలుగు",
            "kannada": "ಕನ್ನಡ",
            "malayalam": "മലയാളം",
            "bengali": "বাংলা",
            "marathi": "मराठी",
            "gujarati": "ગુજરાતી",
            "punjabi": "ਪੰਜਾਬੀ",
            "odia": "ଓଡ଼ିଆ",
            "urdu": "اردو",
            "assamese": "অসমীয়া",
        ]
        for (id, script) in expected {
            XCTAssertEqual(SubjectCatalog.record(id)?.displayName(), script, id)
        }
        XCTAssertEqual(SubjectCatalog.record("maths")?.displayName(), "Maths")
        XCTAssertEqual(SubjectCatalog.record("evs")?.displayName(), "EVS")
    }

    func testOnlyEnglishAllowsAutomaticCheck() {
        let auto = SubjectCatalog.all.filter(\.automaticCheckAllowed).map(\.id)
        XCTAssertEqual(auto, ["english"])
    }

    func testSubjectIDsAreUnique() {
        let ids = SubjectCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testChildProfileHasNoDateOfBirthOrPhoto() throws {
        let child = ProfileRules.make(nickname: "Asha", schoolClass: "2")
        XCTAssertEqual(child.enabledSubjectIDs, ["hindi", "maths", "evs"])
        XCTAssertEqual(child.ageBandID, "6-8")
        XCTAssertTrue(ProfileRules.canAddChild(currentCount: 2))
        XCTAssertFalse(ProfileRules.canAddChild(currentCount: 3))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(child)) as? [String: Any]
        XCTAssertNotNil(object?["nickname"])
        XCTAssertNil(object?["dateOfBirth"])
        XCTAssertNil(object?["photo"])
        XCTAssertNil(object?["syllabus"])
    }
}
