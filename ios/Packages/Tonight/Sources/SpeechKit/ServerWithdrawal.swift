import Foundation

/// Marks `consent_record.withdrawn_at` and deletes `child_profile` through PostgREST.
/// The database triggers write the audit row and enqueue deletion. Offline calls stay queued.
public struct ServerWithdrawalClient: Sendable {
    public var baseURL: URL
    public var anonKey: String
    public var accessToken: @Sendable () -> String
    public var send: @Sendable (URLRequest) async throws -> Int
    public var queueFile: URL
    public var now: @Sendable () -> Date

    public init(
        baseURL: URL,
        anonKey: String,
        accessToken: @escaping @Sendable () -> String,
        send: @escaping @Sendable (URLRequest) async throws -> Int,
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

    public func submit(childID: UUID, consentRecordID: UUID?) async {
        var jobs = load()
        if !jobs.contains(where: { $0.childID == childID && !$0.isFinished }) {
            jobs.append(ServerWithdrawalJob(childID: childID, consentRecordID: consentRecordID))
            store(jobs)
        }
        await flush()
    }

    public func flush() async {
        var jobs = load()
        let token = accessToken().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        for index in jobs.indices where !jobs[index].isFinished {
            let job = jobs[index]
            if let consentID = job.consentRecordID, !job.consentPatched {
                let call = Self.consentPatch(id: consentID, withdrawnAt: now())
                let reached = await perform(method: call.method, path: call.path, body: call.body, token: token)
                if !reached { continue }
                jobs[index].consentPatched = true
                store(jobs)
            }
            if !jobs[index].childDeleted {
                let call = Self.childDelete(id: job.childID)
                let reached = await perform(method: call.method, path: call.path, body: nil, token: token)
                if !reached { continue }
                jobs[index].childDeleted = true
                store(jobs)
            }
        }
    }

    public func pending() -> [ServerWithdrawalJob] {
        load().filter { !$0.isFinished }
    }

    private func perform(method: String, path: String, body: [String: String]?, token: String) async -> Bool {
        guard let url = Self.url(base: baseURL, path: path) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "api" + "key")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        do {
            let status = try await send(request)
            return (200..<300).contains(status)
        } catch {
            return false
        }
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
