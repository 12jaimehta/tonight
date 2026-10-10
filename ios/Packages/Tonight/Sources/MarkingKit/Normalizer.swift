import Foundation

/// Reading-passage tokenizer. This replaces the web prototype's greedy
/// `lib/score.ts` preprocessor.
///
/// Prototype bugs fixed here:
/// - `1,00,000` and `3.5` stay one token (commas and decimal points inside numbers are kept).
/// - `don't` stays one token, then folds to `dont` so a missing apostrophe still matches.
/// - Devanagari vowel signs and nukta stay attached (`किताब` is not split into `क त ब`).
///
/// Case folding uses Unicode default lowercase, not `Locale.current`.
public enum ReadingNormalizer {
    public static func tokens(in text: String) -> [String] {
        let folded = text.precomposedStringWithCompatibilityMapping.lowercased()
        let scalars = Array(folded.unicodeScalars)
        var pieces: [Piece] = []
        var word = ""
        var index = 0

        func flushWord() {
            guard !word.isEmpty else { return }
            pieces.append(.word(word))
            word = ""
        }

        while index < scalars.count {
            let scalar = scalars[index]
            if isIgnorable(scalar) {
                index += 1
                continue
            }
            if isDigit(scalar) {
                // "word12" is one token. A digit only starts a number when it is not already inside a word.
                if !word.isEmpty {
                    word.unicodeScalars.append(asciiDigit(scalar))
                    index += 1
                    continue
                }
                flushWord()
                let (token, next) = consumeNumber(scalars, from: index)
                pieces.append(.number(token))
                index = next
                continue
            }
            if isLetter(scalar) || isMark(scalar) {
                word.unicodeScalars.append(scalar)
                index += 1
                continue
            }
            if isApostrophe(scalar), !word.isEmpty {
                word.unicodeScalars.append(scalar)
                index += 1
                continue
            }
            // ZWJ and ZWNJ stay inside a word so Hindi conjuncts are not split.
            if (scalar == "\u{200C}" || scalar == "\u{200D}"), !word.isEmpty {
                word.unicodeScalars.append(scalar)
                index += 1
                continue
            }
            if isHyphen(scalar), !word.isEmpty, index + 1 < scalars.count, isLetter(scalars[index + 1]) {
                word.unicodeScalars.append(scalar)
                index += 1
                continue
            }
            flushWord()
            index += 1
        }
        flushWord()
        return mergeNumberWords(pieces)
    }

    /// Adjacent number words such as "twenty five" are one value. A hyphen is not required.
    static func mergeNumberWords(_ pieces: [Piece]) -> [String] {
        var output: [String] = []
        var index = 0
        while index < pieces.count {
            if case .word(let first) = pieces[index], NumberWords.isPart(first) {
                var end = index
                var bestEnd = index
                var best: Decimal?
                while end < pieces.count {
                    guard case .word(let part) = pieces[end], NumberWords.isPart(part) else { break }
                    end += 1
                    let phrase = pieces[index..<end].compactMap { piece -> String? in
                        if case .word(let word) = piece { return word }
                        return nil
                    }.joined(separator: " ")
                    if let value = NumberWords.parse(phrase) {
                        bestEnd = end
                        best = value
                    }
                }
                if let best {
                    output.append(plain(best))
                    index = bestEnd
                    continue
                }
            }
            switch pieces[index] {
            case .number(let number):
                output.append(number)
            case .word(let word):
                output.append(canonicalizeWord(word))
            }
            index += 1
        }
        return output
    }

    /// Idempotent on its own output: tokenising the joined tokens again is stable
    /// for the canonical forms this function emits.
    public static func canonicalizeWord(_ raw: String) -> String {
        let stripped = raw.unicodeScalars.filter { !isApostrophe($0) }
        let word = String(String.UnicodeScalarView(stripped))
        if let number = numberWordValue(word) {
            return plain(number)
        }
        return spellingFold(word)
    }

    static func consumeNumber(_ scalars: [Unicode.Scalar], from start: Int) -> (String, Int) {
        var index = start
        var raw = ""
        while index < scalars.count {
            let scalar = scalars[index]
            if isDigit(scalar) || scalar == "," {
                raw.unicodeScalars.append(scalar)
                index += 1
                continue
            }
            // A dot is a decimal point only when a digit follows. "3.5." keeps the sentence period.
            if scalar == "." {
                let next = index + 1
                if next < scalars.count, isDigit(scalars[next]) {
                    raw.unicodeScalars.append(scalar)
                    index += 1
                    continue
                }
                break
            }
            if isIgnorable(scalar) {
                index += 1
                continue
            }
            break
        }
        let token: String
        let consumed: Int
        if let canonical = canonicalNumber(raw), !raw.isEmpty {
            token = canonical
            consumed = index
        } else {
            // Malformed grouping: keep only the leading digits and rescan the rest.
            var digits = ""
            var fallback = start
            while fallback < scalars.count, isDigit(scalars[fallback]) || isIgnorable(scalars[fallback]) {
                if isDigit(scalars[fallback]) {
                    digits.unicodeScalars.append(asciiDigit(scalars[fallback]))
                }
                fallback += 1
            }
            if fallback == start { fallback += 1 }
            token = digits.isEmpty ? raw : plainIntegerDigits(digits)
            consumed = fallback
        }
        return consumeOrdinal(token, scalars: scalars, index: consumed)
    }

    /// "3rd" is the ordinal 3. The suffix is not its own token.
    static func consumeOrdinal(_ token: String, scalars: [Unicode.Scalar], index: Int) -> (String, Int) {
        guard !token.contains(".") else { return (token, index) }
        let suffixes: [[Unicode.Scalar]] = [
            Array("st".unicodeScalars),
            Array("nd".unicodeScalars),
            Array("rd".unicodeScalars),
            Array("th".unicodeScalars),
        ]
        for suffix in suffixes {
            let end = index + suffix.count
            guard end <= scalars.count else { continue }
            guard zip(suffix, scalars[index..<end]).allSatisfy({ $0 == $1 }) else { continue }
            if end < scalars.count, isLetter(scalars[end]) || isMark(scalars[end]) { continue }
            return (token, end)
        }
        return (token, index)
    }

    static func canonicalNumber(_ raw: String) -> String? {
        // `map` yields `[Unicode.Scalar]`, which is not a `String` element sequence.
        let scalars = raw.unicodeScalars.map { asciiDigit($0) }.filter { !isIgnorable($0) }
        let cleaned = String(String.UnicodeScalarView(scalars))
        if cleaned.contains(".") {
            let pieces = cleaned.split(separator: ".", omittingEmptySubsequences: false)
            guard pieces.count == 2 else { return nil }
            guard let whole = stripGrouping(String(pieces[0])), !whole.isEmpty || !pieces[1].isEmpty else { return nil }
            let fraction = String(pieces[1])
            guard fraction.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            guard !whole.contains(",") else { return nil }
            return plain(parsePlainDecimal(whole.isEmpty ? "0" : whole, fraction: fraction) ?? 0)
        }
        guard let digits = stripGrouping(cleaned) else { return nil }
        return plainIntegerDigits(digits)
    }

    /// Indian lakh/crore grouping or Western groups of three. Anything else is rejected.
    static func stripGrouping(_ body: String) -> String? {
        let parts = body.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        if parts.count == 1 { return parts[0] }
        let western = parts[0].count >= 1 && parts[0].count <= 3 && parts.dropFirst().allSatisfy { $0.count == 3 }
        let indian: Bool = {
            guard let last = parts.last, last.count == 3, let first = parts.first else { return false }
            let middle = parts.dropFirst().dropLast()
            return (1...3).contains(first.count) && middle.allSatisfy { $0.count == 2 }
        }()
        guard western || indian else { return nil }
        return parts.joined()
    }

    static func plainIntegerDigits(_ digits: String) -> String {
        let trimmed = digits.drop { $0 == "0" }
        return trimmed.isEmpty ? "0" : String(trimmed)
    }

    static func plain(_ value: Decimal) -> String {
        let number = value as NSDecimalNumber
        // Keep the exact digit string when the decimal is already an integer.
        // `Decimal` has no `intValue`; integrality is value == rounded-to-0-places.
        if value.exponent >= 0 && isIntegral(value) {
            return number.stringValue
        }
        var copy = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &copy, 6, .plain)
        let text = (rounded as NSDecimalNumber).stringValue
        if text.contains(".") {
            var trimmed = text
            while trimmed.last == "0" { trimmed.removeLast() }
            if trimmed.last == "." { trimmed.removeLast() }
            return trimmed
        }
        return text
    }

    /// True when rounding to zero decimal places does not change the value.
    private static func isIntegral(_ value: Decimal) -> Bool {
        var source = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .plain)
        return value == rounded
    }

    private static func parsePlainDecimal(_ whole: String, fraction: String) -> Decimal? {
        guard let wholeValue = Decimal(string: whole.isEmpty ? "0" : whole, locale: posix) else { return nil }
        guard let fracValue = Decimal(string: fraction.isEmpty ? "0" : fraction, locale: posix) else { return nil }
        var scale = Decimal(1)
        for _ in 0..<fraction.count { scale *= 10 }
        return wholeValue + fracValue / scale
    }

    /// Fixed locale for digit strings only. Device region is never consulted.
    private static let posix = Locale(identifier: "en_US_POSIX")

    private static func spellingFold(_ word: String) -> String {
        spellings[word] ?? word
    }

    /// Indian-English spellings folded both ways onto one form. Homophones are not folded
    /// unless fuzzy matching is turned on; that stays off by default.
    private static let spellings: [String: String] = [
        "colour": "color",
        "favourite": "favorite",
        "metre": "meter",
        "litre": "liter",
        "maths": "math",
    ]

    private static func numberWordValue(_ word: String) -> Decimal? {
        let spaced = word.replacingOccurrences(of: "-", with: " ")
        return NumberWords.parse(spaced)
    }

    static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return true
        default:
            return false
        }
    }

    static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return true
        default:
            return false
        }
    }

    static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        if devanagariDigits[scalar] != nil || fullwidthDigits[scalar] != nil { return true }
        return scalar.properties.generalCategory == .decimalNumber
    }

    static func asciiDigit(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        if let mapped = devanagariDigits[scalar] ?? fullwidthDigits[scalar] {
            return mapped
        }
        if scalar.properties.generalCategory == .decimalNumber, let value = scalar.properties.numericValue {
            let digit = Int(value)
            if (0...9).contains(digit), let ascii = Unicode.Scalar(48 + digit) {
                return ascii
            }
        }
        return scalar
    }

    static func isApostrophe(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "'" || scalar == "’" || scalar == "‘" || scalar == "ʼ"
    }

    static func isHyphen(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "-" || scalar == "‐" || scalar == "‑"
    }

    static func isIgnorable(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\u{200B}" || scalar == "\u{FEFF}" || scalar == "\u{00AD}"
    }

    private static let devanagariDigits: [Unicode.Scalar: Unicode.Scalar] = [
        "०": "0", "१": "1", "२": "2", "३": "3", "४": "4",
        "५": "5", "६": "6", "७": "7", "८": "8", "९": "9",
    ]

    private static let fullwidthDigits: [Unicode.Scalar: Unicode.Scalar] = [
        "０": "0", "１": "1", "２": "2", "３": "3", "４": "4",
        "５": "5", "６": "6", "７": "7", "８": "8", "９": "9",
    ]
}

private enum Piece {
    case number(String)
    case word(String)
}

enum NumberWords {
    static func isPart(_ word: String) -> Bool {
        if word.contains("-") { return parse(word.replacingOccurrences(of: "-", with: " ")) != nil }
        return small[word] != nil || multipliers[word] != nil
    }

    static func parse(_ text: String) -> Decimal? {
        let parts = text.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        let hasLexical = parts.contains { small[$0] != nil || multipliers[$0] != nil }
        guard hasLexical else { return nil }
        if parts.count == 2, let head = Decimal(string: parts[0], locale: Locale(identifier: "en_US_POSIX")),
           let multiplier = multipliers[parts[1]] {
            return head * multiplier
        }
        var total = Decimal(0)
        var current = Decimal(0)
        var saw = false
        for part in parts {
            if let value = small[part] {
                current += value
                saw = true
            } else if let multiplier = multipliers[part] {
                if current == 0 { current = 1 }
                total += current * multiplier
                current = 0
                saw = true
            } else if let digit = Decimal(string: part, locale: Locale(identifier: "en_US_POSIX")) {
                current += digit
                saw = true
            } else {
                return nil
            }
        }
        guard saw else { return nil }
        return total + current
    }

    private static let small: [String: Decimal] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
        "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30,
        "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    private static let multipliers: [String: Decimal] = [
        "hundred": 100,
        "thousand": 1_000,
        "lakh": 100_000,
        "crore": 10_000_000,
    ]
}
