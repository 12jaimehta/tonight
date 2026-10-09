import Foundation

public enum AnswerResult: String, Codable, Sendable, Equatable {
    case correct
    case incorrect
    case partial
    case needsReview = "needs_review"
    case notAnswered = "not_answered"
}

public struct AnswerScore: Sendable, Equatable {
    public var result: AnswerResult
    public var points: Decimal

    public init(result: AnswerResult, points: Decimal) {
        self.result = result
        self.points = points
    }
}

public enum AnswerScorer {
    /// Fixed parser locale. Scoring does not read `Locale.current`, so a German
    /// decimal comma never silently becomes 3.5.
    private static let posix = Locale(identifier: "en_US_POSIX")

    public static func score(expected: String, child: String, questionType: String, settings rawSettings: String) -> AnswerScore {
        let settings = Settings(rawSettings)
        let trimmed = stripOuterSpace(child)
        if trimmed.isEmpty { return AnswerScore(result: .notAnswered, points: 0) }
        if trimmed.count > 10_000 { return AnswerScore(result: .needsReview, points: 0) }

        switch questionType {
        case "reading":
            return scoreReading(expected: expected, child: child, locale: settings.values["lang"] ?? "en-IN")
        case "homework_total":
            return scoreHomeworkTotal(expected)
        case "multi_blank":
            return scoreBlanks(expected: expected, child: child, settings: settings)
        case "time":
            return scoreTime(expected: expected, child: child)
        default:
            return scoreValue(expected: expected, child: trimmed, questionType: questionType, settings: settings)
        }
    }

    private static func scoreReading(expected: String, child: String, locale: String) -> AnswerScore {
        let mark = Marker().mark(expected: expected, heard: child, options: MarkerOptions(locale: locale))
        guard mark.total > 0 else { return AnswerScore(result: .notAnswered, points: 0) }
        let points = Decimal(mark.correct) / Decimal(mark.total)
        if mark.correct == mark.total { return AnswerScore(result: .correct, points: 1) }
        if mark.correct == 0 { return AnswerScore(result: .incorrect, points: 0) }
        return AnswerScore(result: .partial, points: points)
    }

    private static func scoreHomeworkTotal(_ expected: String) -> AnswerScore {
        let numbers = integers(in: expected)
        guard numbers.count >= 2 else { return AnswerScore(result: .notAnswered, points: 0) }
        let correct = numbers[0]
        let total = numbers[1]
        guard total > 0 else { return AnswerScore(result: .notAnswered, points: 0) }
        return AnswerScore(result: .correct, points: Decimal(correct) / Decimal(total))
    }

    public static func homeworkDisplay(expected: String) -> String {
        let numbers = integers(in: expected)
        guard numbers.count >= 2 else { return "—" }
        return DisplayRounding.percentLabel(correct: numbers[0], total: numbers[1])
    }

    private static func scoreBlanks(expected: String, child: String, settings: Settings) -> AnswerScore {
        let want = list(expected)
        let got = list(child)
        let total = settings.values["blanks"].flatMap(Int.init) ?? want.count
        guard total > 0 else { return AnswerScore(result: .needsReview, points: 0) }
        let hits: Int
        if settings.values["unordered"] == "true" {
            var remaining = got.filter { !$0.isEmpty }
            hits = want.filter { item in
                guard let index = remaining.firstIndex(of: item) else { return false }
                remaining.remove(at: index)
                return true
            }.count
        } else {
            hits = zip(want, got).filter { !$0.1.isEmpty && $0.0 == $0.1 }.count
        }
        let points = Decimal(hits) / Decimal(total)
        if hits == total { return AnswerScore(result: .correct, points: 1) }
        if hits == 0 { return AnswerScore(result: .incorrect, points: 0) }
        return AnswerScore(result: .partial, points: points)
    }

    private static func scoreValue(expected: String, child: String, questionType: String, settings: Settings) -> AnswerScore {
        let expectedBody = parentheticalStripped(expected)
        if looksLikeExpression(child) || looksScientific(child) {
            return AnswerScore(result: .needsReview, points: 0)
        }
        if questionType == "fraction" {
            return scoreFraction(expected: expectedBody, child: child, settings: settings)
        }
        if questionType == "measure" {
            return scoreMeasure(expected: expectedBody, child: child, settings: settings)
        }
        if questionType == "money" {
            return scoreMoney(expected: expectedBody, child: child, settings: settings)
        }
        if questionType == "percent" {
            return compareNumbers(expected: stripPercent(expectedBody), child: stripPercent(child), tolerance: settings.tolerance, allowNegative: true)
        }
        if questionType == "integer", expectedBody.contains("rounded"), let dp = settings.dp {
            return scoreRounded(expected: expectedBody, child: child, dp: dp)
        }
        let childBody = questionType == "integer" || questionType == "decimal" ? stripTrailingNoun(child) : child
        return compareNumbers(expected: expectedBody, child: childBody, tolerance: settings.tolerance, allowNegative: settings.flag("allow_negative") || expectedBody.contains("-") || expectedBody.contains("−"))
    }

    private static func scoreRounded(expected: String, child: String, dp: Int) -> AnswerScore {
        guard let source = firstDecimal(in: expected), let given = parseDecimal(child) else {
            return AnswerScore(result: .needsReview, points: 0)
        }
        let target = DisplayRounding.roundHalfUp(source, scale: dp)
        return given == target
            ? AnswerScore(result: .correct, points: 1)
            : AnswerScore(result: .incorrect, points: 0)
    }

    private static func scoreFraction(expected: String, child: String, settings: Settings) -> AnswerScore {
        guard let want = parseRational(expected) else { return AnswerScore(result: .needsReview, points: 0) }
        if child.contains("//") || child.hasSuffix("/") || child.hasPrefix("/") {
            return AnswerScore(result: .needsReview, points: 0)
        }
        if let got = parseRational(child) {
            if got.denominator == 0 || want.denominator == 0 {
                return AnswerScore(result: .needsReview, points: 0)
            }
            guard got.value == want.value else { return AnswerScore(result: .incorrect, points: 0) }
            if settings.values["simplest"] == "true", !got.isSimplest {
                return AnswerScore(result: .partial, points: Decimal(string: "0.5", locale: posix)!)
            }
            return AnswerScore(result: .correct, points: 1)
        }
        if let decimal = parseDecimal(child), decimal == want.value {
            if settings.values["form"] == "fraction_only" {
                return AnswerScore(result: .partial, points: Decimal(string: "0.5", locale: posix)!)
            }
            return AnswerScore(result: .correct, points: 1)
        }
        return AnswerScore(result: .needsReview, points: 0)
    }

    private static func scoreMeasure(expected: String, child: String, settings: Settings) -> AnswerScore {
        guard let want = parseQuantity(expected), let got = parseQuantity(child) else {
            return AnswerScore(result: .needsReview, points: 0)
        }
        let mode = settings.values["unit"] ?? "none"
        if got.unit == nil {
            if mode == "required" {
                return want.value == got.value
                    ? AnswerScore(result: .partial, points: Decimal(string: "0.5", locale: posix)!)
                    : AnswerScore(result: .incorrect, points: 0)
            }
            return want.value == got.value
                ? AnswerScore(result: .correct, points: 1)
                : AnswerScore(result: .incorrect, points: 0)
        }
        if settings.values["convert"] == "true" {
            if let left = want.convertedToBase(), let right = got.convertedToBase(), left.dimension == right.dimension {
                return left.value == right.value
                    ? AnswerScore(result: .correct, points: 1)
                    : AnswerScore(result: .incorrect, points: 0)
            }
        }
        guard want.unit == got.unit, want.value == got.value else {
            return AnswerScore(result: .incorrect, points: 0)
        }
        return AnswerScore(result: .correct, points: 1)
    }

    private static func scoreMoney(expected: String, child: String, settings: Settings) -> AnswerScore {
        if let words = parseRupeesPaise(child) {
            return compareDecimals(parseDecimal(stripMoney(expected)), words, strictDP: nil)
        }
        let strict = settings.values["dp"] == "2_strict" ? 2 : nil
        return compareDecimals(parseDecimal(stripMoney(expected)), parseDecimal(stripMoney(child)), strictDP: strict, childText: stripMoney(child))
    }

    private static func scoreTime(expected: String, child: String) -> AnswerScore {
        guard let want = parseClock(expected), let got = parseClock(child) else {
            return AnswerScore(result: .needsReview, points: 0)
        }
        return clocksMatch(want, got)
            ? AnswerScore(result: .correct, points: 1)
            : AnswerScore(result: .incorrect, points: 0)
    }

    private static func compareNumbers(expected: String, child: String, tolerance: Decimal?, allowNegative: Bool) -> AnswerScore {
        if isMalformedGrouping(child) { return AnswerScore(result: .needsReview, points: 0) }
        guard var want = parseDecimal(expected), var got = parseDecimal(child) else {
            return AnswerScore(result: .needsReview, points: 0)
        }
        if !allowNegative && (got < 0 || want < 0) && got != want {
            return AnswerScore(result: .incorrect, points: 0)
        }
        if let tolerance {
            let delta = got > want ? got - want : want - got
            return delta <= tolerance
                ? AnswerScore(result: .correct, points: 1)
                : AnswerScore(result: .incorrect, points: 0)
        }
        return got == want
            ? AnswerScore(result: .correct, points: 1)
            : AnswerScore(result: .incorrect, points: 0)
    }

    private static func compareDecimals(_ want: Decimal?, _ got: Decimal?, strictDP: Int?, childText: String = "") -> AnswerScore {
        guard let want, let got else { return AnswerScore(result: .needsReview, points: 0) }
        guard want == got else { return AnswerScore(result: .incorrect, points: 0) }
        if let strictDP, fractionDigits(childText) != strictDP {
            return AnswerScore(result: .partial, points: Decimal(string: "0.5", locale: posix)!)
        }
        return AnswerScore(result: .correct, points: 1)
    }

    static func parseDecimal(_ raw: String) -> Decimal? {
        var text = normalizeDigits(raw)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "−", with: "-")
        text = text.replacingOccurrences(of: "–", with: "-")
        if text.hasPrefix("+") { text.removeFirst() }
        if text.hasSuffix(".") && !text.dropLast().contains(".") { text.removeLast() }
        if text.hasPrefix(".") { text = "0" + text }
        if text.hasPrefix("-.") { text = "-0" + text.dropFirst() }
        let wordSource = text.lowercased().replacingOccurrences(of: "-", with: " ")
        if wordSource.contains(where: \.isLetter), let words = NumberWords.parse(wordSource) { return words }
        let negative = text.hasPrefix("-")
        if negative { text.removeFirst() }
        guard let digits = ReadingNormalizer.stripGrouping(text.filter { $0 != " " }) else { return nil }
        guard let value = Decimal(string: digits, locale: posix) else { return nil }
        return negative ? -value : value
    }

    private static func isMalformedGrouping(_ raw: String) -> Bool {
        let text = normalizeDigits(raw).filter { !$0.isWhitespace }
        guard text.contains(",") else { return false }
        return ReadingNormalizer.stripGrouping(text) == nil && !text.contains(".")
    }

    private static func parseRational(_ raw: String) -> Rational? {
        var text = normalizeDigits(raw).replacingOccurrences(of: "−", with: "-")
        text = text.replacingOccurrences(of: "⁄", with: "/")
        text = text.replacingOccurrences(of: " / ", with: "/")
        while text.contains(" /") { text = text.replacingOccurrences(of: " /", with: "/") }
        while text.contains("/ ") { text = text.replacingOccurrences(of: "/ ", with: "/") }
        let negative = text.hasPrefix("-")
        if negative { text.removeFirst() }
        let pieces = text.split(separator: " ").map(String.init)
        if pieces.count == 2, let whole = Int(pieces[0]), let fraction = parseSimpleFraction(pieces[1]) {
            if fraction.denominator == 0 { return fraction }
            let numerator = whole * fraction.denominator + fraction.numerator
            return Rational(numerator: negative ? -numerator : numerator, denominator: fraction.denominator)
        }
        guard pieces.count == 1, var fraction = parseSimpleFraction(pieces[0]) else { return nil }
        if negative { fraction.numerator = -fraction.numerator }
        return fraction
    }

    private static func parseSimpleFraction(_ text: String) -> Rational? {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, let numerator = Int(parts[0]), let denominator = Int(parts[1]) else { return nil }
        return Rational(numerator: numerator, denominator: denominator)
    }

    private static func parseQuantity(_ raw: String) -> Quantity? {
        let text = normalizeDigits(raw).lowercased()
        let cleaned = text.replacingOccurrences(of: "−", with: "-")
        var number = ""
        var unit = ""
        var seenUnit = false
        for character in cleaned {
            if !seenUnit && (character.isASCII && character.isNumber || character == "." || character == "," || character == "-" || character == "+") {
                number.append(character)
            } else if character.isWhitespace {
                if !number.isEmpty { seenUnit = true }
            } else {
                seenUnit = true
                unit.append(character)
            }
        }
        guard let value = parseDecimal(number) else { return nil }
        let canonical = unit.isEmpty ? nil : unitTable[unit]
        if !unit.isEmpty && canonical == nil { return nil }
        return Quantity(value: value, unit: canonical)
    }

    private static func parseRupeesPaise(_ raw: String) -> Decimal? {
        let text = normalizeDigits(raw).lowercased()
        guard text.contains("rupee"), text.contains("paise") else { return nil }
        let numbers = text.split { !$0.isNumber && $0 != "." }.compactMap { Decimal(string: String($0), locale: posix) }
        guard numbers.count >= 2 else { return nil }
        return numbers[0] + numbers[1] / 100
    }

    private static func parseClock(_ raw: String) -> ClockTime? {
        let text = normalizeDigits(raw).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "half past three" { return ClockTime(hour: 3, minute: 30, explicitPeriod: false) }
        var body = text
        var period: String?
        if body.hasSuffix("am") || body.hasSuffix("pm") {
            period = String(body.suffix(2))
            body = String(body.dropLast(2)).trimmingCharacters(in: .whitespaces)
        }
        let separator: Character = body.contains(":") ? ":" : (body.contains(".") ? "." : " ")
        guard separator != " " else { return nil }
        let parts = body.split(separator: separator).map(String.init)
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]), parts[1].count == 2 || separator == ":" else {
            return nil
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        var hour24 = hour
        if period == "pm", hour < 12 { hour24 += 12 }
        if period == "am", hour == 12 { hour24 = 0 }
        let explicit = period != nil || hour >= 13
        return ClockTime(hour: hour24, minute: minute, explicitPeriod: explicit)
    }

    private static func clocksMatch(_ expected: ClockTime, _ child: ClockTime) -> Bool {
        guard expected.minute == child.minute else { return false }
        if expected.explicitPeriod && child.explicitPeriod {
            return expected.hour == child.hour
        }
        return expected.hour % 12 == child.hour % 12
    }

    private static func stripMoney(_ raw: String) -> String {
        var text = normalizeDigits(raw)
        for token in ["₹", "rs.", "rs", "inr", "/-"] {
            text = text.replacingOccurrences(of: token, with: "", options: .caseInsensitive)
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func stripPercent(_ raw: String) -> String {
        var text = normalizeDigits(raw).lowercased()
        text = text.replacingOccurrences(of: "percent", with: "")
        text = text.replacingOccurrences(of: "%", with: "")
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func stripTrailingNoun(_ raw: String) -> String {
        let parts = raw.split(separator: " ").map(String.init)
        guard parts.count == 2, parts[1].allSatisfy({ $0.isLetter }) else { return raw }
        return parts[0]
    }

    private static func parentheticalStripped(_ raw: String) -> String {
        guard let open = raw.firstIndex(of: "(") else { return raw }
        return String(raw[..<open]).trimmingCharacters(in: .whitespaces)
    }

    private static func looksLikeExpression(_ raw: String) -> Bool {
        let text = normalizeDigits(raw).filter { !$0.isWhitespace }
        if text.contains("*") || text.contains("×") { return true }
        if let plus = text.firstIndex(of: "+"), plus != text.startIndex { return true }
        return false
    }

    private static func looksScientific(_ raw: String) -> Bool {
        let text = normalizeDigits(raw).lowercased().filter { !$0.isWhitespace }
        return text.contains("e") && text.contains(where: \.isNumber)
    }

    private static func fractionDigits(_ raw: String) -> Int {
        guard let dot = raw.firstIndex(of: ".") else { return 0 }
        return raw[raw.index(after: dot)...].prefix { $0.isNumber }.count
    }

    private static func firstDecimal(in text: String) -> Decimal? {
        let matches = text.split { !$0.isNumber && $0 != "." }
        return matches.compactMap { parseDecimal(String($0)) }.first
    }

    private static func integers(in text: String) -> [Int] {
        var numbers: [Int] = []
        var current = ""
        for character in text {
            if character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                if let value = Int(current) { numbers.append(value) }
                current = ""
            }
        }
        if let value = Int(current) { numbers.append(value) }
        return numbers
    }

    private static func list(_ raw: String) -> [String] {
        raw.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func normalizeDigits(_ raw: String) -> String {
        let folded = raw.precomposedStringWithCompatibilityMapping
        var output = ""
        for scalar in folded.unicodeScalars {
            if scalar == "\u{00A0}" || scalar == "\u{2009}" || scalar == "\u{200B}" || scalar == "\u{FEFF}" {
                continue
            }
            output.unicodeScalars.append(ReadingNormalizer.asciiDigit(scalar))
        }
        return output
    }

    private static func stripOuterSpace(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let unitTable: [String: String] = [
        "cm": "cm", "cms": "cm", "centimetre": "cm", "centimeter": "cm",
        "centimetres": "cm", "centimeters": "cm",
        "m": "m", "metre": "m", "meter": "m", "metres": "m", "meters": "m",
        "km": "km", "kilometre": "km", "kilometer": "km",
        "kg": "kg", "kgs": "kg", "kilogram": "kg", "kilograms": "kg",
        "g": "g", "gm": "g", "gms": "g", "gram": "g", "grams": "g",
        "l": "l", "litre": "l", "liter": "l", "litres": "l", "liters": "l", "ltr": "l",
        "ml": "ml", "millilitre": "ml", "milliliter": "ml",
    ]
}

struct Rational: Equatable {
    var numerator: Int
    var denominator: Int

    var value: Decimal {
        guard denominator != 0 else { return 0 }
        return Decimal(numerator) / Decimal(denominator)
    }

    var isSimplest: Bool {
        guard denominator != 0 else { return false }
        return gcd(abs(numerator), abs(denominator)) == 1
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a
        var y = b
        while y != 0 {
            let next = x % y
            x = y
            y = next
        }
        return x
    }
}

struct Quantity: Equatable {
    var value: Decimal
    var unit: String?

    func convertedToBase() -> (dimension: String, value: Decimal)? {
        switch unit {
        case "g": return ("mass", value)
        case "kg": return ("mass", value * 1000)
        case "cm": return ("length", value * 10)
        case "m": return ("length", value * 1000)
        case "km": return ("length", value * 1_000_000)
        case "ml": return ("volume", value)
        case "l": return ("volume", value * 1000)
        default: return nil
        }
    }
}

struct ClockTime: Equatable {
    var hour: Int
    var minute: Int
    var explicitPeriod: Bool
}

struct Settings {
    var flags: Set<String>
    var values: [String: String]

    init(_ raw: String) {
        var flags: Set<String> = []
        var values: [String: String] = [:]
        for piece in raw.split(separator: ";") {
            let part = piece.trimmingCharacters(in: .whitespaces)
            guard !part.isEmpty else { continue }
            if let equal = part.firstIndex(of: "=") {
                let key = String(part[..<equal])
                let value = String(part[part.index(after: equal)...])
                values[key] = value
            } else if !part.contains(" ") {
                flags.insert(part)
            }
        }
        self.flags = flags
        self.values = values
    }

    var tolerance: Decimal? {
        values["tolerance"].flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
    }

    var dp: Int? {
        guard let raw = values["dp"] else { return nil }
        let digits = raw.prefix { $0.isNumber }
        return Int(digits)
    }

    func flag(_ name: String) -> Bool { flags.contains(name) }
}
