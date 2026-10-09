import Foundation

/// JPEG bytes for one homework page. The bytes live in the app container.
public struct CapturedPageImage: Sendable, Equatable {
    public var bytes: Data
    public var capturedAt: Date

    public init(bytes: Data, capturedAt: Date) {
        self.bytes = bytes
        self.capturedAt = capturedAt
    }
}

public struct OCRLine: Sendable, Equatable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

/// Reads printed text on a page. v1 can supply a fake or a later on-device engine.
public protocol OCREngine: Sendable {
    func recognize(_ image: CapturedPageImage) async -> [OCRLine]
}

/// A later handwriting model plugs in here. M0 ships no model.
public protocol HandwritingEngine: Sendable {
    func recognize(_ image: CapturedPageImage) async -> [OCRLine]
}

public struct NoHandwritingEngine: HandwritingEngine {
    public init() {}

    public func recognize(_ image: CapturedPageImage) async -> [OCRLine] {
        []
    }
}

public struct HandwritingSeam: Sendable {
    private var engine: any HandwritingEngine

    public init(engine: any HandwritingEngine = NoHandwritingEngine()) {
        self.engine = engine
    }

    public func recognize(_ image: CapturedPageImage) async -> [OCRLine] {
        await engine.recognize(image)
    }

    public func replacing(_ engine: any HandwritingEngine) -> HandwritingSeam {
        var copy = self
        copy.engine = engine
        return copy
    }
}
