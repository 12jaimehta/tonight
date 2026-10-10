import Foundation

/// Device-passcode encryption for files Tonight writes. This is the local encryption.
public enum LocalProtection {
    public static let fileProtection: FileProtectionType = .complete

    public static func protect(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }

    /// Creates the store directory, excludes it from backup, and sets protection before the container opens.
    public static func prepareStoreDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var copy = directory
        try copy.setResourceValues(values)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen],
            ofItemAtPath: directory.path
        )
    }

    /// Protects the store file and its sidecars once they exist.
    public static func protectStore(at url: URL) throws {
        for suffix in ["", "-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: url.path + suffix)
            guard FileManager.default.fileExists(atPath: sidecar.path) else { continue }
            try protect(sidecar)
        }
    }
}

/// Page photos are excluded from iCloud and device backup.
public enum PhotoFilePolicy {
    public static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var copy = url
        try copy.setResourceValues(values)
        try LocalProtection.protect(url)
    }

    public static func isExcludedFromBackup(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    }
}

public enum PhotoAccessError: Error, Equatable {
    case parentLocked
}

/// Reading a page photo requires the parent gate to be open.
public struct PhotoAccess: Sendable {
    public var parentUnlocked: Bool

    public init(parentUnlocked: Bool) {
        self.parentUnlocked = parentUnlocked
    }

    public func contents(of url: URL) throws -> Data {
        guard parentUnlocked else { throw PhotoAccessError.parentLocked }
        return try Data(contentsOf: url)
    }
}
