import CaptureKit
import Foundation
import Persistence
import TaskKit

/// Page and notebook photos live in the app container. `PhotoFilePolicy` applies
/// complete file protection and excludes the file from backup. Nothing is written
/// to the camera roll, and there is no public route.
enum AppPhotoFiles {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("TonightPhotos", isDirectory: true)
    }

    static func writeJPEG(relativePath: String) throws -> PhotoRef {
        let url = directory.appendingPathComponent(relativePath)
        try PhotoFilePolicy.write(PageJPEG.bytes, to: url)
        return PhotoRef(relativePath: relativePath)
    }
}
