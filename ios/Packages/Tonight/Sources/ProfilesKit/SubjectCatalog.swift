import Foundation

public struct LocalizedName: Codable, Hashable, Sendable {
    public var lang: String
    public var text: String

    public init(lang: String, text: String) {
        self.lang = lang
        self.text = text
    }
}

public enum SubjectScriptDirection: String, Codable, Hashable, Sendable {
    case ltr
    case rtl
}

public enum SubjectGlyphKind: String, Codable, Hashable, Sendable {
    case icon
    case glyph
}

public enum SubjectGroup: String, Codable, Hashable, Sendable {
    case core
    case language
}

/// One row in the subject table. Subjects are data, not an enum.
/// Shape follows subjects.py: id, English name, native name, lang, direction,
/// glyph kind, glyph, hue, and group. `names` keeps the English and own-script
/// labels the app already shows. There is no syllabus or chapter list.
public struct SubjectRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var nameEn: String
    public var nameNative: String
    public var lang: String
    public var dir: SubjectScriptDirection
    public var glyphKind: SubjectGlyphKind
    public var glyph: String
    /// OKLCH hue from subjects.py. The hex palette lives in DesignSystem.
    public var hue: Int
    public var group: SubjectGroup
    public var enabledByDefault: Bool

    public init(
        id: String,
        nameEn: String,
        nameNative: String,
        lang: String,
        dir: SubjectScriptDirection,
        glyphKind: SubjectGlyphKind,
        glyph: String,
        hue: Int,
        group: SubjectGroup,
        enabledByDefault: Bool
    ) {
        self.id = id
        self.nameEn = nameEn
        self.nameNative = nameNative
        self.lang = lang
        self.dir = dir
        self.glyphKind = glyphKind
        self.glyph = glyph
        self.hue = hue
        self.group = group
        self.enabledByDefault = enabledByDefault
    }

    /// English name plus the name in the subject's own script.
    public var names: [LocalizedName] {
        if lang == "en" {
            return [LocalizedName(lang: "en", text: nameNative)]
        }
        return [
            LocalizedName(lang: "en", text: nameEn),
            LocalizedName(lang: lang, text: nameNative),
        ]
    }

    /// The name in the subject's own script. State languages therefore render in that script.
    public func displayName() -> String {
        names.first { $0.lang == lang }?.text ?? nameNative
    }

    /// Automatic word-count marking is English reading only (`subjects.py` AUTO_MARK).
    public var automaticCheckAllowed: Bool { SubjectCatalog.autoMarkIDs.contains(id) }
}

public enum SubjectCatalog {
    /// Class defaults from subjects.py. English, Hindi, Maths, and EVS for classes 1–3.
    public static let classDefaultIDs = ["english", "hindi", "maths", "evs"]

    public static let classDefaults: [String: [String]] = [
        "1": ["english", "hindi", "maths", "evs"],
        "2": ["english", "hindi", "maths", "evs"],
        "3": ["english", "hindi", "maths", "evs"],
    ]

    public static let autoMarkIDs: Set<String> = ["english"]

    public static let all: [SubjectRecord] = {
        let defaults: Set<String> = ["english", "hindi", "maths", "evs"]
        func row(
            _ id: String,
            _ nameEn: String,
            _ nameNative: String,
            _ lang: String,
            _ dir: SubjectScriptDirection,
            _ glyphKind: SubjectGlyphKind,
            _ glyph: String,
            _ hue: Int,
            _ group: SubjectGroup
        ) -> SubjectRecord {
            SubjectRecord(
                id: id,
                nameEn: nameEn,
                nameNative: nameNative,
                lang: lang,
                dir: dir,
                glyphKind: glyphKind,
                glyph: glyph,
                hue: hue,
                group: group,
                enabledByDefault: defaults.contains(id)
            )
        }
        return [
            row("maths", "Maths", "Maths", "en", .ltr, .icon, "s-maths", 262, .core),
            row("science", "Science", "Science", "en", .ltr, .icon, "s-science", 195, .core),
            row("social", "Social Studies", "Social Studies", "en", .ltr, .icon, "s-social", 60, .core),
            row("evs", "EVS", "EVS", "en", .ltr, .icon, "s-evs", 142, .core),
            row("computers", "Computers", "Computers", "en", .ltr, .icon, "s-computers", 225, .core),
            row("gk", "GK", "GK", "en", .ltr, .icon, "s-gk", 105, .core),
            row("art", "Art", "Art", "en", .ltr, .icon, "s-art", 305, .core),
            row("english", "English", "English", "en", .ltr, .glyph, "Aa", 335, .language),
            row("hindi", "Hindi", "हिन्दी", "hi", .ltr, .glyph, "अ", 30, .language),
            row("sanskrit", "Sanskrit", "संस्कृतम्", "sa", .ltr, .glyph, "ॐ", 80, .language),
            row("marathi", "Marathi", "मराठी", "mr", .ltr, .glyph, "ळ", 5, .language),
            row("punjabi", "Punjabi", "ਪੰਜਾਬੀ", "pa", .ltr, .glyph, "ੳ", 90, .language),
            row("gujarati", "Gujarati", "ગુજરાતી", "gu", .ltr, .glyph, "અ", 285, .language),
            row("bengali", "Bengali", "বাংলা", "bn", .ltr, .glyph, "অ", 165, .language),
            row("odia", "Odia", "ଓଡ଼ିଆ", "or", .ltr, .glyph, "ଅ", 245, .language),
            row("telugu", "Telugu", "తెలుగు", "te", .ltr, .glyph, "అ", 15, .language),
            row("tamil", "Tamil", "தமிழ்", "ta", .ltr, .glyph, "அ", 350, .language),
            row("kannada", "Kannada", "ಕನ್ನಡ", "kn", .ltr, .glyph, "ಅ", 120, .language),
            row("malayalam", "Malayalam", "മലയാളം", "ml", .ltr, .glyph, "അ", 180, .language),
            row("urdu", "Urdu", "اردو", "ur", .rtl, .glyph, "ب", 155, .language),
        ]
    }()

    public static func record(_ id: String) -> SubjectRecord? {
        all.first { $0.id == id }
    }

    /// Seed list for a class. Classes 1–3 use subjects.py. Any other class keeps those same default-on rows.
    public static func defaults(for schoolClass: String, audience: AudienceConfig = .v1) -> [SubjectRecord] {
        let ids: [String]
        if audience.classes.contains(schoolClass), let seeded = classDefaults[schoolClass] {
            ids = seeded
        } else {
            ids = classDefaultIDs
        }
        return ids.compactMap(record)
    }
}
