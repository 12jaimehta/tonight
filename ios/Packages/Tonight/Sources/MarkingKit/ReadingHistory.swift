import Foundation

/// One scored reading. Typed attempts stay out of accuracy and the history trend.
public struct ReadingSample: Hashable, Sendable {
    public var inputMode: InputMode
    public var percent: Int

    public init(inputMode: InputMode, percent: Int) {
        self.inputMode = inputMode
        self.percent = percent
    }
}

public enum ReadingHistory {
    /// Mean whole-number percent of spoken readings. Typed readings are left out.
    public static func accuracy(of samples: [ReadingSample]) -> Int? {
        let spoken = samples.filter { $0.inputMode == .spoken }
        guard !spoken.isEmpty else { return nil }
        let total = spoken.reduce(0) { $0 + $1.percent }
        return total / spoken.count
    }

    /// Spoken percents, in the order they were recorded.
    public static func trend(of samples: [ReadingSample]) -> [Int] {
        samples.compactMap { sample in
            sample.inputMode == .spoken ? sample.percent : nil
        }
    }

    public static func sample(inputMode: InputMode, percent: Int?) -> ReadingSample? {
        guard let percent else { return nil }
        return ReadingSample(inputMode: inputMode, percent: percent)
    }
}
