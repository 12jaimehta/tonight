import Foundation

public struct LocalizedName: Codable, Hashable, Sendable {
    public var lang: String
    public var text: String

    public init(lang: String, text: String) {
        self.lang = lang
        self.text = text
    }
}

/// One row in the subject table. Subjects are data, not an enum.
/// There is no syllabus or chapter list attached to a subject.
public struct SubjectRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var names: [LocalizedName]
    public var lang: String
    public var glyph: String
    /// Hue in degrees for the OKLCH subject palette. DesignSystem turns this into bg, fg, accent, and soft.
    public var hue: Double
    public var enabledByDefault: Bool

    public init(
        id: String,
        names: [LocalizedName],
        lang: String,
        glyph: String,
        hue: Double,
        enabledByDefault: Bool
    ) {
        self.id = id
        self.names = names
        self.lang = lang
        self.glyph = glyph
        self.hue = hue
        self.enabledByDefault = enabledByDefault
    }

    /// The name in the subject's own script. State languages therefore render in that script.
    public func displayName() -> String {
        names.first { $0.lang == lang }?.text ?? names.first?.text ?? id
    }

    /// Automatic word-count marking is English reading only.
    public var automaticCheckAllowed: Bool { id == "english" }
}

public enum SubjectCatalog {
    public static let all: [SubjectRecord] = [
        row("hindi", "Hindi", "hi", "हिन्दी", "हि", 35, true),
        row("maths", "Maths", "en", "Maths", "+", 255, true),
        row("evs", "EVS", "en", "EVS", "◉", 145, true),
        row("english", "English", "en", "English", "Aa", 55, false),
        row("tamil", "Tamil", "ta", "தமிழ்", "த", 15, false),
        row("telugu", "Telugu", "te", "తెలుగు", "తె", 300, false),
        row("kannada", "Kannada", "kn", "ಕನ್ನಡ", "ಕ", 80, false),
        row("malayalam", "Malayalam", "ml", "മലയാളം", "മ", 175, false),
        row("bengali", "Bengali", "bn", "বাংলা", "ব", 340, false),
        row("marathi", "Marathi", "mr", "मराठी", "म", 25, false),
        row("gujarati", "Gujarati", "gu", "ગુજરાતી", "ગ", 200, false),
        row("punjabi", "Punjabi", "pa", "ਪੰਜਾਬੀ", "ਪ", 310, false),
        row("odia", "Odia", "or", "ଓଡ଼ିଆ", "ଓ", 95, false),
        row("urdu", "Urdu", "ur", "اردو", "ا", 280, false),
        row("assamese", "Assamese", "as", "অসমীয়া", "অ", 160, false),
    ]

    public static func record(_ id: String) -> SubjectRecord? {
        all.first { $0.id == id }
    }

    /// Hindi, Maths, and EVS for classes 1–3. Other subjects stay optional.
    /// A later class uses the same default-on rows; v1 does not ship a class 4–5 syllabus.
    public static func defaults(for schoolClass: String, audience: AudienceConfig = .v1) -> [SubjectRecord] {
        let enabled = all.filter(\.enabledByDefault)
        guard audience.classes.contains(schoolClass) else { return enabled }
        return enabled
    }

    private static func row(
        _ id: String,
        _ english: String,
        _ lang: String,
        _ ownScript: String,
        _ glyph: String,
        _ hue: Double,
        _ enabledByDefault: Bool
    ) -> SubjectRecord {
        SubjectRecord(
            id: id,
            names: [LocalizedName(lang: "en", text: english), LocalizedName(lang: lang, text: ownScript)],
            lang: lang,
            glyph: glyph,
            hue: hue,
            enabledByDefault: enabledByDefault
        )
    }
}
