import Foundation

/// One rounding function for display. Round half up (away from zero for the
/// positive scores Tonight produces). Never banker's rounding.
public enum DisplayRounding {
    public static func percentValue(correct: Int, total: Int) -> Int? {
        guard total > 0 else { return nil }
        if correct >= total { return 100 }
        let raw = (Decimal(correct) * 100) / Decimal(total)
        var rounded = Int(truncating: roundHalfUp(raw, scale: 0) as NSDecimalNumber)
        if rounded >= 100 { rounded = 99 }
        return rounded
    }

    public static func percentLabel(correct: Int, total: Int) -> String {
        guard let value = percentValue(correct: correct, total: total) else { return "—" }
        return "\(value)%"
    }

    public static func roundHalfUp(_ value: Decimal, scale: Int) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        return result
    }
}
