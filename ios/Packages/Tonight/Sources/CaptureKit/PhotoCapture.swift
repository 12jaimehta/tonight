import Foundation

/// Page photos stay in the directory the caller passes. They are not added to the camera roll.
public enum PhotoCapturePolicy {
    public static let writesToPhotoLibrary = false
    public static let destination = "app-private"
}

public struct AppPrivatePhotoStore: Sendable {
    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Returns a path relative to `directory`. The file is the only copy.
    public func save(_ image: CapturedPageImage, id: UUID = UUID()) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(id.uuidString).jpg"
        let url = directory.appendingPathComponent(name)
        try image.bytes.write(to: url, options: [.atomic])
        return name
    }
}
