import Foundation

/// Global word alignment (Needleman–Wunsch) with a fixed tie-break.
/// Match cost 0, substitution cost 2, insertion or omission cost 1.
/// When costs tie: prefer a real match, then omitting an expected word, then an insertion, then a substitution.
///
/// Each heard token pairs with at most one expected token. A word that was not spoken
/// is omitted or substituted, never matched. Fuzzy edit-distance is off unless asked.
enum WordAligner {
    static func align(expected: [String], heard: [String], fuzzy: Bool) -> [AlignedWord] {
        let rows = expected.count
        let columns = heard.count
        var cost = Array(repeating: Array(repeating: 0, count: columns + 1), count: rows + 1)
        var step = Array(repeating: Array(repeating: Step.none, count: columns + 1), count: rows + 1)

        if rows > 0 {
            for row in 1...rows {
                cost[row][0] = row
                step[row][0] = .omit
            }
        }
        if columns > 0 {
            for column in 1...columns {
                cost[0][column] = column
                step[0][column] = .insert
            }
        }

        if rows > 0 && columns > 0 {
            for row in 1...rows {
                for column in 1...columns {
                    let same = tokensMatch(expected[row - 1], heard[column - 1], fuzzy: fuzzy)
                    var best = Candidate(cost: cost[row - 1][column - 1] + (same ? 0 : 2), priority: same ? 0 : 3, step: same ? .match : .substitute)
                    let omit = Candidate(cost: cost[row - 1][column] + 1, priority: 1, step: .omit)
                    let insert = Candidate(cost: cost[row][column - 1] + 1, priority: 2, step: .insert)
                    if omit.isBetter(than: best) { best = omit }
                    if insert.isBetter(than: best) { best = insert }
                    cost[row][column] = best.cost
                    step[row][column] = best.step
                }
            }
        }

        var row = rows
        var column = columns
        var reversed: [AlignedWord] = []
        var nextID = 0
        while row > 0 || column > 0 {
            let kind = step[row][column]
            switch kind {
            case .match, .substitute:
                reversed.append(AlignedWord(id: nextID, expected: expected[row - 1], heard: heard[column - 1], status: kind == .match ? .matched : .substituted))
                row -= 1
                column -= 1
            case .omit:
                reversed.append(AlignedWord(id: nextID, expected: expected[row - 1], heard: nil, status: .omitted))
                row -= 1
            case .insert:
                reversed.append(AlignedWord(id: nextID, expected: nil, heard: heard[column - 1], status: .inserted))
                column -= 1
            case .none:
                row = 0
                column = 0
            }
            nextID += 1
        }
        return reversed.reversed().enumerated().map { index, word in
            AlignedWord(id: index, expected: word.expected, heard: word.heard, status: word.status)
        }
    }

    private static func tokensMatch(_ expected: String, _ heard: String, fuzzy: Bool) -> Bool {
        if expected == heard { return true }
        guard fuzzy, expected.count >= 5, heard.count >= 5 else { return false }
        return editDistance(expected, heard) <= 1
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let left = Array(a)
        let right = Array(b)
        var previous = Array(0...right.count)
        for (i, leftChar) in left.enumerated() {
            var current = [i + 1]
            for (j, rightChar) in right.enumerated() {
                let cost = leftChar == rightChar ? 0 : 1
                current.append(min(current[j] + 1, previous[j + 1] + 1, previous[j] + cost))
            }
            previous = current
        }
        return previous[right.count]
    }

    private enum Step {
        case none
        case match
        case substitute
        case omit
        case insert
    }

    private struct Candidate {
        var cost: Int
        var priority: Int
        var step: Step

        func isBetter(than other: Candidate) -> Bool {
            if cost != other.cost { return cost < other.cost }
            return priority < other.priority
        }
    }
}
