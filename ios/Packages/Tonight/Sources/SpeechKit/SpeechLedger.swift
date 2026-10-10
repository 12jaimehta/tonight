import Foundation
import os

/// Persistent per-child consent, audit log, audio, and the server deletion queue.
/// Withdrawal erases local speech data before it returns, then queues the server delete.
public final class SpeechLedger: @unchecked Sendable {
    public let directory: URL
    private let lock = OSAllocatedUnfairLock<LedgerFile>(initialState: LedgerFile())
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protected = directory
        try protected.setResourceValues(values)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen],
            ofItemAtPath: directory.path
        )
        let url = directory.appendingPathComponent("ledger.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            let file = try decoder.decode(LedgerFile.self, from: data)
            lock.withLock { state in state = file }
        }
    }

    public func record(for childProfileID: UUID) -> AudioConsentRecord? {
        lock.withLock { $0.consent.first { $0.childProfileID == childProfileID } }
    }

    public func grant(_ record: AudioConsentRecord) throws {
        try lock.withLock { file in
            file.consent.removeAll { $0.childProfileID == record.childProfileID }
            file.consent.append(record)
            try save(file)
        }
    }

    public func storeAudio(_ data: Data, childProfileID: UUID, serverPath: Bool) throws -> LedgerArtefact {
        let id = UUID()
        let filename = "\(id.uuidString).bin"
        let folder = directory.appendingPathComponent(childProfileID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen],
            ofItemAtPath: url.path
        )
        var excluded = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        let artefact = LedgerArtefact(
            id: id,
            childProfileID: childProfileID,
            kind: .audio,
            serverPath: serverPath,
            filename: filename,
            body: nil
        )
        try lock.withLock { file in
            file.artefacts.append(artefact)
            try save(file)
        }
        return artefact
    }

    public func storeText(_ text: String, childProfileID: UUID, kind: ArtefactKind, serverPath: Bool) throws -> LedgerArtefact {
        let artefact = LedgerArtefact(
            id: UUID(),
            childProfileID: childProfileID,
            kind: kind,
            serverPath: serverPath,
            filename: nil,
            body: text
        )
        try lock.withLock { file in
            file.artefacts.append(artefact)
            try save(file)
        }
        return artefact
    }

    public func addRememberWord(_ word: String, childProfileID: UUID) throws {
        try lock.withLock { file in
            file.remember.append(LedgerRemember(id: UUID(), childProfileID: childProfileID, word: word))
            try save(file)
        }
    }

    public func addMarkCorrection(_ note: String, childProfileID: UUID) throws {
        try lock.withLock { file in
            file.marks.append(LedgerMark(id: UUID(), childProfileID: childProfileID, note: note))
            try save(file)
        }
    }

    public func liveArtefacts(childProfileID: UUID) -> [LedgerArtefact] {
        lock.withLock { $0.artefacts.filter { $0.childProfileID == childProfileID } }
    }

    public func rememberWords(childProfileID: UUID) -> [LedgerRemember] {
        lock.withLock { $0.remember.filter { $0.childProfileID == childProfileID } }
    }

    public func markCorrections(childProfileID: UUID) -> [LedgerMark] {
        lock.withLock { $0.marks.filter { $0.childProfileID == childProfileID } }
    }

    public func auditSnapshot() -> [SpeechAuditEntry] {
        lock.withLock { $0.audit }
    }

    public func deletionQueue() -> [ServerDeletionJob] {
        lock.withLock { $0.queue }
    }

    /// Deletes this child's audio, transcripts, alignment, marks, and Remember words, writes the audit row, and queues the server deletion. The ledger is saved before this returns.
    @discardableResult
    public func withdraw(childProfileID: UUID, at date: Date) throws -> WithdrawalEffect {
        let prepared: (urls: [URL], hadServer: Bool) = lock.withLock { file in
            let urls = file.artefacts.compactMap { artefact -> URL? in
                guard artefact.childProfileID == childProfileID, let filename = artefact.filename else { return nil }
                return directory
                    .appendingPathComponent(childProfileID.uuidString, isDirectory: true)
                    .appendingPathComponent(filename)
            }
            let hadServer = file.consent.contains { record in
                record.childProfileID == childProfileID && record.scopeIsActive(.server)
            } || file.artefacts.contains { $0.childProfileID == childProfileID && $0.serverPath }
            return (urls, hadServer)
        }
        var deletedAudio = 0
        for url in prepared.urls where FileManager.default.fileExists(atPath: url.path) {
            let bytes = (try? Data(contentsOf: url).count) ?? 0
            try FileManager.default.removeItem(at: url)
            deletedAudio += bytes
        }
        let bytesDeleted = deletedAudio

        return try lock.withLock { file in
            let childArtefacts = file.artefacts.filter { $0.childProfileID == childProfileID }
            let transcripts = childArtefacts.filter { $0.kind == .transcript }.count
            let alignments = childArtefacts.filter { $0.kind == .alignment }.count
            let marks = file.marks.filter { $0.childProfileID == childProfileID }.count
            let words = file.remember.filter { $0.childProfileID == childProfileID }.count
            file.artefacts.removeAll { $0.childProfileID == childProfileID }
            file.marks.removeAll { $0.childProfileID == childProfileID }
            file.remember.removeAll { $0.childProfileID == childProfileID }
            if let index = file.consent.firstIndex(where: { $0.childProfileID == childProfileID }) {
                file.consent[index].withdrawnAt = date
                file.consent[index].withdrawnScopes.formUnion([.onDevice, .server])
                file.consent[index].scopes.subtract([.onDevice, .server])
            }
            let consent = file.consent.first { $0.childProfileID == childProfileID }
            file.audit.append(SpeechAuditEntry(
                ts: date,
                attemptID: UUID(),
                childProfileID: childProfileID,
                engine: "none",
                reason: "withdrawn",
                consentRecordID: consent?.id,
                consentVersion: consent?.version,
                flag: false,
                online: false,
                bytesSent: 0,
                cancelledAfterBytes: bytesDeleted
            ))
            if prepared.hadServer {
                file.queue.append(ServerDeletionJob(
                    id: UUID(),
                    childProfileID: childProfileID,
                    prefix: "\(childProfileID.uuidString)/",
                    enqueuedAt: date,
                    attempts: 0,
                    nextAttemptAt: date,
                    completedAt: nil
                ))
            }
            try save(file)
            return WithdrawalEffect(
                deletedAudioBytes: bytesDeleted,
                deletedTranscripts: transcripts,
                deletedAlignments: alignments,
                deletedMarks: marks,
                deletedRememberWords: words,
                queuedServerDeletion: prepared.hadServer
            )
        }
    }

    /// Drops server audio and queues the backend delete. On-device Remember words and marks stay.
    @discardableResult
    public func withdrawServer(childProfileID: UUID, at date: Date) throws -> WithdrawalEffect {
        let prepared: (urls: [URL], hadServer: Bool) = lock.withLock { file in
            let urls = file.artefacts.compactMap { artefact -> URL? in
                guard artefact.childProfileID == childProfileID, artefact.serverPath, let filename = artefact.filename else { return nil }
                return directory
                    .appendingPathComponent(childProfileID.uuidString, isDirectory: true)
                    .appendingPathComponent(filename)
            }
            let hadServer = file.consent.contains { record in
                record.childProfileID == childProfileID && record.scopeIsActive(.server)
            } || file.artefacts.contains { $0.childProfileID == childProfileID && $0.serverPath }
            return (urls, hadServer)
        }
        var deletedAudio = 0
        for url in prepared.urls where FileManager.default.fileExists(atPath: url.path) {
            let bytes = (try? Data(contentsOf: url).count) ?? 0
            try FileManager.default.removeItem(at: url)
            deletedAudio += bytes
        }
        return try lock.withLock { file in
            let removed = file.artefacts.filter { $0.childProfileID == childProfileID && $0.serverPath }
            file.artefacts.removeAll { $0.childProfileID == childProfileID && $0.serverPath }
            if let index = file.consent.firstIndex(where: { $0.childProfileID == childProfileID }) {
                file.consent[index].withdrawnScopes.insert(.server)
                file.consent[index].scopes.remove(.server)
            }
            if prepared.hadServer {
                file.queue.append(ServerDeletionJob(
                    id: UUID(),
                    childProfileID: childProfileID,
                    prefix: "\(childProfileID.uuidString)/",
                    enqueuedAt: date,
                    attempts: 0,
                    nextAttemptAt: date,
                    completedAt: nil
                ))
            }
            try save(file)
            return WithdrawalEffect(
                deletedAudioBytes: deletedAudio,
                deletedTranscripts: removed.filter { $0.kind == .transcript }.count,
                deletedAlignments: removed.filter { $0.kind == .alignment }.count,
                deletedMarks: 0,
                deletedRememberWords: 0,
                queuedServerDeletion: prepared.hadServer
            )
        }
    }

    public func dueDeletions(at date: Date) -> [ServerDeletionJob] {
        lock.withLock { file in
            file.queue.filter { $0.completedAt == nil && $0.nextAttemptAt <= date }
        }
    }

    /// Failed attempts wait 1s, 2s, 4s, then at most 60s. A confirmed delete stamps completedAt.
    public func recordDeletionAttempt(id: UUID, at date: Date, succeeded: Bool) throws {
        try lock.withLock { file in
            guard let index = file.queue.firstIndex(where: { $0.id == id }) else { return }
            file.queue[index].attempts += 1
            if succeeded {
                file.queue[index].completedAt = date
            } else {
                let exponent = min(file.queue[index].attempts - 1, 6)
                let delay = min(Double(1 << exponent), 60)
                file.queue[index].nextAttemptAt = date.addingTimeInterval(delay)
            }
            try save(file)
        }
    }

    private func save(_ file: LedgerFile) throws {
        let url = directory.appendingPathComponent("ledger.json")
        let data = try encoder.encode(file)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen],
            ofItemAtPath: url.path
        )
    }
}

public struct WithdrawalEffect: Equatable, Sendable {
    public var deletedAudioBytes: Int
    public var deletedTranscripts: Int
    public var deletedAlignments: Int
    public var deletedMarks: Int
    public var deletedRememberWords: Int
    public var queuedServerDeletion: Bool
}

public struct LedgerArtefact: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var childProfileID: UUID
    public var kind: ArtefactKind
    public var serverPath: Bool
    public var filename: String?
    public var body: String?
}

public struct LedgerRemember: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var childProfileID: UUID
    public var word: String
}

public struct LedgerMark: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var childProfileID: UUID
    public var note: String
}

public struct ServerDeletionJob: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var childProfileID: UUID
    public var prefix: String
    public var enqueuedAt: Date
    public var attempts: Int
    public var nextAttemptAt: Date
    public var completedAt: Date?
}

private struct LedgerFile: Codable, Sendable {
    var consent: [AudioConsentRecord] = []
    var audit: [SpeechAuditEntry] = []
    var artefacts: [LedgerArtefact] = []
    var queue: [ServerDeletionJob] = []
    var remember: [LedgerRemember] = []
    var marks: [LedgerMark] = []
}
