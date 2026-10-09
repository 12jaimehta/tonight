import XCTest
@testable import CaptureKit

final class CaptureKitTests: XCTestCase {
    func testPhotosStayOutOfTheCameraRoll() throws {
        XCTAssertFalse(PhotoCapturePolicy.writesToPhotoLibrary)
        XCTAssertEqual(PhotoCapturePolicy.destination, "app-private")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppPrivatePhotoStore(directory: directory)
        let image = CapturedPageImage(bytes: Data([0xFF, 0xD8, 0xFF]), capturedAt: Date(timeIntervalSince1970: 10))
        let relative = try store.save(image, id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)
        XCTAssertEqual(relative, "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.jpg")
        let saved = try Data(contentsOf: directory.appendingPathComponent(relative))
        XCTAssertEqual(saved, image.bytes)
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(contents.count, 1)
    }

    func testOCREngineIsAProtocol() async {
        let engine = ScriptedOCR(lines: [OCRLine(text: "the cat")])
        let lines = await engine.recognize(CapturedPageImage(bytes: Data([1]), capturedAt: Date()))
        XCTAssertEqual(lines.map(\.text), ["the cat"])
    }

    func testHandwritingSeamStartsEmpty() async {
        let image = CapturedPageImage(bytes: Data([1]), capturedAt: Date())
        let seam = HandwritingSeam()
        let empty = await seam.recognize(image)
        XCTAssertTrue(empty.isEmpty)
        let replaced = seam.replacing(ScriptedHandwriting(lines: [OCRLine(text: "क")]))
        let lines = await replaced.recognize(image)
        XCTAssertEqual(lines.map(\.text), ["क"])
    }

    func testSourcesDoNotSaveToThePhotoLibrary() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CaptureKit")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        let text = try files.filter { $0.pathExtension == "swift" }.map { try String(contentsOf: $0) }.joined(separator: "\n")
        XCTAssertFalse(text.contains("UIImageWriteToSavedPhotosAlbum"))
        XCTAssertFalse(text.contains("PHPhotoLibrary"))
        XCTAssertFalse(text.contains("PHAssetChangeRequest"))
        XCTAssertTrue(text.contains("writesToPhotoLibrary = false"))
    }
}

private struct ScriptedOCR: OCREngine {
    var lines: [OCRLine]
    func recognize(_ image: CapturedPageImage) async -> [OCRLine] { lines }
}

private struct ScriptedHandwriting: HandwritingEngine {
    var lines: [OCRLine]
    func recognize(_ image: CapturedPageImage) async -> [OCRLine] { lines }
}
