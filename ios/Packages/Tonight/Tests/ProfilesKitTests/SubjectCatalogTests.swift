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

    func testClassDefaultsFollowSubjectsPy() {
        XCTAssertEqual(SubjectCatalog.all.count, 20)
        for schoolClass in AudienceConfig.v1.classes {
            XCTAssertEqual(
                SubjectCatalog.defaults(for: schoolClass).map(\.id),
                ["english", "hindi", "maths", "evs"]
            )
        }
        XCTAssertEqual(SubjectCatalog.defaults(for: "4").map(\.id), ["english", "hindi", "maths", "evs"])
        let optional = SubjectCatalog.all.filter { !$0.enabledByDefault }.map(\.id)
        XCTAssertEqual(optional.count, 16)
        XCTAssertFalse(optional.contains("english"))
        XCTAssertFalse(optional.contains("hindi"))
        XCTAssertFalse(optional.contains("maths"))
        XCTAssertFalse(optional.contains("evs"))
        XCTAssertTrue(optional.contains("science"))
        XCTAssertTrue(optional.contains("sanskrit"))
        XCTAssertNil(SubjectCatalog.record("assamese"))
    }

    func testStateLanguagesUseTheirOwnScript() {
        let expected = [
            "hindi": "हिन्दी",
            "sanskrit": "संस्कृतम्",
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
        ]
        for (id, script) in expected {
            let record = SubjectCatalog.record(id)
            XCTAssertEqual(record?.displayName(), script, id)
            XCTAssertEqual(record?.names.first { $0.lang == record?.lang }?.text, script, id)
        }
        XCTAssertEqual(SubjectCatalog.record("maths")?.displayName(), "Maths")
        XCTAssertEqual(SubjectCatalog.record("evs")?.displayName(), "EVS")
        XCTAssertEqual(SubjectCatalog.record("hindi")?.glyph, "अ")
        XCTAssertEqual(SubjectCatalog.record("hindi")?.hue, 30)
        XCTAssertEqual(SubjectCatalog.record("english")?.hue, 335)
        XCTAssertEqual(SubjectCatalog.record("maths")?.hue, 262)
        XCTAssertEqual(SubjectCatalog.record("urdu")?.dir, .rtl)
        XCTAssertEqual(SubjectCatalog.record("english")?.glyph, "Aa")
    }

    func testOnlyEnglishAllowsAutomaticCheck() {
        let auto = SubjectCatalog.all.filter(\.automaticCheckAllowed).map(\.id)
        XCTAssertEqual(auto, ["english"])
    }

    func testSubjectIDsAreUnique() {
        let ids = SubjectCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testChildProfileSeedsSubjectSettingsAndParentLabel() throws {
        var child = ProfileRules.make(nickname: "Asha", schoolClass: "2", parentLabel: "Papa")
        XCTAssertEqual(child.subjects.map(\.subjectID), ["english", "hindi", "maths", "evs"])
        XCTAssertTrue(child.subjects.allSatisfy { $0.displayName == nil && $0.hidden == false })
        XCTAssertEqual(child.ageBandID, "6-8")
        XCTAssertEqual(child.parentLabel, "Papa")
        XCTAssertTrue(ProfileRules.canAddChild(currentCount: 2))
        XCTAssertFalse(ProfileRules.canAddChild(currentCount: 3))

        child.renameSubject("evs", to: "पर्यावरण")
        XCTAssertEqual(child.subjects.first { $0.subjectID == "evs" }?.displayName, "पर्यावरण")
        XCTAssertEqual(SubjectCatalog.record("evs")?.glyph, "s-evs")

        child.setSubjectHidden("hindi", true)
        XCTAssertEqual(child.visibleSubjectIDs, ["english", "maths", "evs"])
        child.setSubjectHidden("english", true)
        child.setSubjectHidden("maths", true)
        child.setSubjectHidden("evs", true)
        XCTAssertEqual(child.visibleSubjectIDs, ["evs"])

        child.reorderSubjects(["maths", "evs", "english", "hindi"])
        XCTAssertEqual(child.subjects.map(\.subjectID), ["maths", "evs", "english", "hindi"])
        XCTAssertEqual(child.subjects.map(\.order), [0, 1, 2, 3])

        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(child)) as? [String: Any]
        XCTAssertNotNil(object?["nickname"])
        XCTAssertEqual(object?["parentLabel"] as? String, "Papa")
        XCTAssertNotNil(object?["subjects"])
        XCTAssertNil(object?["dateOfBirth"])
        XCTAssertNil(object?["photo"])
        XCTAssertNil(object?["syllabus"])
        XCTAssertNil(object?["enabledSubjectIDs"])
    }
}
