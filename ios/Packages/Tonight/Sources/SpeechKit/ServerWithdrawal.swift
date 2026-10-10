import Foundation

public struct ServerHTTPResponse: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

public enum ServerSyncResult: Equatable, Sendable {
    case synced
    case notOneRow(Int)
    case waiting
}

/// Marks `consent_record.withdrawn_at` and deletes `child_profile` through PostgREST.
/// The database triggers write the audit row and enqueue deletion. Offline calls stay queued.
/// A 2xx response that changes zero rows, or more than one, is not success.
public struct ServerWithdrawalClient: Sendable {
    public var baseURL: URL
    public var anonKey: String
    public var accessToken: @Sendable () -> String
    public var send: @Sendable (URLRequest) async throws -> ServerHTTPResponse
    public var queueFile: URL
    public var now: @Sendable () -> Date

    public init(
        baseURL: URL,
        anonKey: String,
        accessToken: @escaping @Sendable () -> String,
        send: @escaping @Sendable (URLRequest) async throws -> ServerHTTPResponse,
        queueFile: URL,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.accessToken = accessToken
        self.send = send
        self.queueFile = queueFile
        self.now = now
    }

    public static func consentPatch(id: UUID, withdrawnAt: Date) -> (method: String, path: String, body: [String: String]) {
        (
            "PATCH",
            "/rest/v1/consent_record?id=eq.\(id.uuidString.lowercased())",
            ["withdrawn_at": iso8601(withdrawnAt)]
        )
    }

    public static func childDelete(id: UUID) -> (method: String, path: String) {
        ("DELETE", "/rest/v1/child_profile?id=eq.\(id.uuidString.lowercased())")
    }

    public func submit(childID: UUID, consentRecordID: UUID?) async -> ServerSyncResult {
        var jobs = load()
        if !jobs.contains(where: { $0.childID == childID && !$0.isFinished }) {
            jobs.append(ServerWithdrawalJob(childID: childID, consentRecordID: consentRecordID))
            store(jobs)
        }
        return await flush()
    }

    public func flush() async -> ServerSyncResult {
        var jobs = load()
        let token = accessToken().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return .waiting }
        for index in jobs.indices where !jobs[index].isFinished {
            let job = jobs[index]
            if let consentID = job.consentRecordID, !job.consentPatched {
                let call = Self.consentPatch(id: consentID, withdrawnAt: now())
                let outcome = await perform(method: call.method, path: call.path, json: call.body, token: token)
                switch outcome {
                case .one:
                    jobs[index].consentPatched = true
                    store(jobs)
                case .count(let count):
                    return .notOneRow(count)
                case .failed:
                    return .waiting
                }
            }
            if !jobs[index].childDeleted {
                let call = Self.childDelete(id: job.childID)
                let outcome = await perform(method: call.method, path: call.path, json: nil, token: token)
                switch outcome {
                case .one:
                    jobs[index].childDeleted = true
                    store(jobs)
                case .count(let count):
                    return .notOneRow(count)
                case .failed:
                    return .waiting
                }
            }
        }
        return jobs.contains(where: { !$0.isFinished }) ? .waiting : .synced
    }

    public func createParent(id: UUID) async -> ServerSyncResult {
        await write(method: "POST", path: "/rest/v1/parent", json: ["id": id.uuidString.lowercased()])
    }

    public func createChild(id: UUID, parentID: UUID, nickname: String, schoolClass: String) async -> ServerSyncResult {
        await write(
            method: "POST",
            path: "/rest/v1/child_profile",
            json: [
                "id": id.uuidString.lowercased(),
                "parent_id": parentID.uuidString.lowercased(),
                "nickname": nickname,
                "age_band": "6-8",
                "school_class": schoolClass,
            ]
        )
    }

    public func createConsent(id: UUID, parentID: UUID, childID: UUID) async -> ServerSyncResult {
        await write(
            method: "POST",
            path: "/rest/v1/consent_record",
            json: [
                "id": id.uuidString.lowercased(),
                "parent_id": parentID.uuidString.lowercased(),
                "child_profile_id": childID.uuidString.lowercased(),
                "version": AudioConsentRecord.currentVersion,
                "scopes": ["on_device_speech"],
                "method": "screen",
            ]
        )
    }

    private func write(method: String, path: String, json: [String: Any]) async -> ServerSyncResult {
        let token = accessToken().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return .waiting }
        switch await perform(method: method, path: path, json: json, token: token) {
        case .one:
            return .synced
        case .count(let count):
            return .notOneRow(count)
        case .failed:
            return .waiting
        }
    }

    public func pending() -> [ServerWithdrawalJob] {
        load().filter { !$0.isFinished }
    }

    private enum RowWrite {
        case one
        case count(Int)
        case failed
    }

    private func perform(method: String, path: String, json: Any?, token: String) async -> RowWrite {
        guard let url = Self.url(base: baseURL, path: path) else { return .failed }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let json {
            request.httpBody = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "api" + "key")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        do {
            let response = try await send(request)
            guard (200..<300).contains(response.status) else { return .failed }
            let count = Self.changedRowCount(response.body)
            return count == 1 ? .one : .count(count)
        } catch {
            return .failed
        }
    }

    static func changedRowCount(_ data: Data) -> Int {
        guard !data.isEmpty, let rows = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return 0 }
        return rows.count
    }

    private func load() -> [ServerWithdrawalJob] {
        guard let data = try? Data(contentsOf: queueFile),
              let jobs = try? JSONDecoder().decode([ServerWithdrawalJob].self, from: data) else {
            return []
        }
        return jobs
    }

    private func store(_ jobs: [ServerWithdrawalJob]) {
        let directory = queueFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(jobs.filter { !$0.isFinished }) else { return }
        try? data.write(to: queueFile, options: [.atomic])
    }

    static func url(base: URL, path: String) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        let pieces = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        components.path = String(pieces[0])
        components.query = pieces.count == 2 ? String(pieces[1]) : nil
        return components.url
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

public struct ServerWithdrawalJob: Codable, Equatable, Sendable {
    public var childID: UUID
    public var consentRecordID: UUID?
    public var consentPatched: Bool
    public var childDeleted: Bool

    public init(childID: UUID, consentRecordID: UUID?, consentPatched: Bool = false, childDeleted: Bool = false) {
        self.childID = childID
        self.consentRecordID = consentRecordID
        self.consentPatched = consentPatched
        self.childDeleted = childDeleted
    }

    public var isFinished: Bool {
        consentPatched && childDeleted || (consentRecordID == nil && childDeleted)
    }
}
