import Foundation

enum TaskSyncState: Equatable {
    case localCache
    case syncing
    case synced(Date)
    case failed(String)
}

protocol TaskSyncServicing {
    var providerName: String { get }

    func fetchTasks(for profile: FamilyProfile, localTasks: [PaihuorTask]) async throws -> [PaihuorTask]
    func upsertTask(_ task: PaihuorTask, for profile: FamilyProfile) async throws -> PaihuorTask
    func deleteTask(_ task: PaihuorTask, for profile: FamilyProfile) async throws -> PaihuorTask
    func deleteTasks(for profile: FamilyProfile) async throws
}

actor MockTaskSyncService: TaskSyncServicing {
    nonisolated var providerName: String { "Mock" }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        self.fileURL = (documentsURL ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("paihuor_mock_remote_tasks.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func fetchTasks(for profile: FamilyProfile, localTasks: [PaihuorTask]) async throws -> [PaihuorTask] {
        try await simulateLatency()

        var remoteTasks = try load()
        let localFamilyTasks = localTasks.filter { $0.familyId == profile.familyId }
        remoteTasks = Self.merged(existing: remoteTasks, incoming: localFamilyTasks)
        try save(remoteTasks)

        return Self.relevantTasks(from: remoteTasks, for: profile)
    }

    func upsertTask(_ task: PaihuorTask, for profile: FamilyProfile) async throws -> PaihuorTask {
        try await simulateLatency()

        var remoteTasks = try load()
        remoteTasks = Self.merged(existing: remoteTasks, incoming: [task])
        try save(remoteTasks)

        return task
    }

    func deleteTask(_ task: PaihuorTask, for profile: FamilyProfile) async throws -> PaihuorTask {
        try await simulateLatency()

        var deletedTask = task
        deletedTask.deleted = true
        deletedTask.deletedAt = deletedTask.deletedAt ?? Date().epochMilliseconds
        deletedTask.deletedBy = deletedTask.deletedBy ?? profile.userId.rawValue

        var remoteTasks = try load()
        remoteTasks = Self.merged(existing: remoteTasks, incoming: [deletedTask])
        try save(remoteTasks)

        return deletedTask
    }

    func deleteTasks(for profile: FamilyProfile) async throws {
        try await simulateLatency()

        let remoteTasks = try load().filter { $0.familyId != profile.familyId }
        try save(remoteTasks)
    }

    private func simulateLatency() async throws {
        try await Task.sleep(nanoseconds: 250_000_000)
    }

    private func load() throws -> [PaihuorTask] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([PaihuorTask].self, from: data)
    }

    private func save(_ tasks: [PaihuorTask]) throws {
        let data = try encoder.encode(tasks)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func merged(existing: [PaihuorTask], incoming: [PaihuorTask]) -> [PaihuorTask] {
        var tasksById = Dictionary(uniqueKeysWithValues: existing.map { ($0.objectId, $0) })

        for task in incoming {
            if let current = tasksById[task.objectId], current.updatedAt > task.updatedAt {
                continue
            }

            tasksById[task.objectId] = task
        }

        return tasksById.values.sorted { $0.createdAt > $1.createdAt }
    }

    private static func relevantTasks(from tasks: [PaihuorTask], for profile: FamilyProfile) -> [PaihuorTask] {
        tasks
            .filter { task in
                task.familyId == profile.familyId
                    && (task.fromUserId == profile.userId.rawValue || task.toUserId == profile.userId.rawValue)
                    && !task.deleted
                    && (task.deletedAt ?? 0) == 0
            }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

actor PaihuorRelayTaskSyncService: TaskSyncServicing {
    nonisolated var providerName: String { "Paihuor Relay" }

    private let baseURL: URL?
    private let lanURL: URL?
    private let apiKey: String
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var activeBaseURL: URL?

    init?(baseURL: URL?, lanURL: URL? = nil, apiKey: String, session: URLSession = .shared) {
        guard (baseURL != nil || lanURL != nil),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        self.baseURL = baseURL
        self.lanURL = lanURL
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func fetchTasks(for profile: FamilyProfile, localTasks: [PaihuorTask]) async throws -> [PaihuorTask] {
        let since = localTasks
            .filter { $0.familyId == profile.familyId }
            .map(\.updatedAt.epochMilliseconds)
            .max() ?? 0
        let url = try await makeTasksURL(familyId: profile.familyId, since: since)
        let data = try await send(method: "GET", url: url)
        return try decoder.decode([RelayTaskDTO].self, from: data)
            .map { $0.task() }
            .filter { task in
                task.familyId == profile.familyId
                    && (task.fromUserId == profile.userId.rawValue || task.toUserId == profile.userId.rawValue)
            }
    }

    func upsertTask(_ task: PaihuorTask, for profile: FamilyProfile) async throws -> PaihuorTask {
        do {
            return try await updateTask(task)
        } catch PaihuorRelayError.notFound {
            return try await createTask(task)
        }
    }

    func deleteTask(_ task: PaihuorTask, for profile: FamilyProfile) async throws -> PaihuorTask {
        let data = try await send(method: "DELETE", url: await endpoint("tasks", task.objectId))
        return try decoder.decode(RelayTaskDTO.self, from: data).task(fallback: task)
    }

    func deleteTasks(for profile: FamilyProfile) async throws {
        // The current relay exposes send, fetch, and status/update routes only.
        // Clearing remains a local reset until the service adds a delete endpoint.
    }

    private func createTask(_ task: PaihuorTask) async throws -> PaihuorTask {
        let body = try encoder.encode(RelayTaskDTO(
            task: task,
            includesObjectId: false,
            includesServerTimestamps: false
        ))
        let data = try await send(method: "POST", url: await endpoint("tasks"), body: body)
        return try decoder.decode(RelayTaskDTO.self, from: data).task(fallback: task)
    }

    private func updateTask(_ task: PaihuorTask) async throws -> PaihuorTask {
        let body = try encoder.encode(RelayTaskDTO(task: task, includesServerTimestamps: false))
        let data = try await send(method: "POST", url: await endpoint("tasks", task.objectId), body: body)
        return try decoder.decode(RelayTaskDTO.self, from: data).task(fallback: task)
    }

    private func makeTasksURL(familyId: String, since: Int64) async throws -> URL {
        guard var components = URLComponents(url: await endpoint("tasks"), resolvingAgainstBaseURL: false) else {
            throw PaihuorRelayError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "familyId", value: familyId),
            URLQueryItem(name: "since", value: String(since)),
            URLQueryItem(name: "caps", value: "v2")
        ]

        guard let url = components.url else {
            throw PaihuorRelayError.invalidURL
        }

        return url
    }

    private func endpoint(_ pathComponents: String...) async -> URL {
        let baseURL = await resolveBaseURL()
        return pathComponents.reduce(baseURL) { url, component in
            url.appendingPathComponent(component)
        }
    }

    private func resolveBaseURL() async -> URL {
        if let activeBaseURL {
            return activeBaseURL
        }

        if let lanURL, await isHealthy(lanURL) {
            activeBaseURL = lanURL
            return lanURL
        }

        if let baseURL {
            activeBaseURL = baseURL
            return baseURL
        }

        if let lanURL {
            activeBaseURL = lanURL
            return lanURL
        }

        return URL(string: "http://127.0.0.1")!
    }

    private func isHealthy(_ baseURL: URL) async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 2.5

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    private func send(
        method: String,
        url: URL,
        body: Data? = nil,
        attempt: Int = 0
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "x-paihuor-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw PaihuorRelayError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200..<300:
                return data
            case 404:
                throw PaihuorRelayError.notFound
            default:
                let message = String(data: data, encoding: .utf8)
                throw PaihuorRelayError.requestFailed(
                    statusCode: httpResponse.statusCode,
                    message: message
                )
            }
        } catch let error as PaihuorRelayError {
            throw error
        } catch {
            activeBaseURL = nil
            guard attempt < 2 else { throw error }
            let delay = UInt64(attempt + 1) * 400_000_000
            try? await Task.sleep(nanoseconds: delay)
            return try await send(method: method, url: url, body: body, attempt: attempt + 1)
        }
    }
}

private struct RelayTaskDTO: Codable {
    var objectId: String?
    var familyId: String?
    var fromUserId: String?
    var toUserId: String?
    var rawText: String?
    var title: String?
    var detail: String?
    var deadline: Int64?
    var status: String?
    var reminder: TaskReminder?
    var negotiation: [RelayNegotiationDTO]?
    var receivedAt: Int64?
    var doneAt: Int64?
    var archived: Bool?
    var deleted: Bool?
    var archivedAt: Int64?
    var archivedBy: String?
    var deletedAt: Int64?
    var deletedBy: String?
    var createdAt: Int64?
    var updatedAt: Int64?

    init(
        task: PaihuorTask,
        includesObjectId: Bool = true,
        includesServerTimestamps: Bool = true
    ) {
        self.objectId = includesObjectId ? task.objectId : nil
        self.familyId = task.familyId
        self.fromUserId = task.fromUserId
        self.toUserId = task.toUserId
        self.rawText = task.rawText
        self.title = task.title
        self.detail = task.detail
        self.deadline = task.deadline
        self.status = task.status.rawValue
        self.reminder = task.reminder
        self.negotiation = task.negotiation.map(RelayNegotiationDTO.init(message:))
        self.receivedAt = task.receivedAt
        self.doneAt = task.doneAt
        self.archived = task.archived
        self.deleted = task.deleted
        self.archivedAt = task.archivedAt
        self.archivedBy = task.archivedBy
        self.deletedAt = task.deletedAt
        self.deletedBy = task.deletedBy
        self.createdAt = includesServerTimestamps ? task.createdAt.epochMilliseconds : nil
        self.updatedAt = includesServerTimestamps ? task.updatedAt.epochMilliseconds : nil
    }

    func task(fallback: PaihuorTask? = nil) -> PaihuorTask {
        let createdAtMilliseconds = createdAt
            ?? fallback?.createdAt.epochMilliseconds
            ?? Date().epochMilliseconds
        let updatedAtMilliseconds = updatedAt
            ?? fallback?.updatedAt.epochMilliseconds
            ?? createdAtMilliseconds

        return PaihuorTask(
            objectId: objectId ?? fallback?.objectId ?? UUID().uuidString,
            createdAt: Date(epochMilliseconds: createdAtMilliseconds),
            updatedAt: Date(epochMilliseconds: updatedAtMilliseconds),
            familyId: familyId ?? fallback?.familyId ?? AppConfig.defaultFamilyId,
            fromUserId: fromUserId ?? fallback?.fromUserId ?? UserRole.wife.rawValue,
            toUserId: toUserId ?? fallback?.toUserId ?? UserRole.husband.rawValue,
            rawText: rawText ?? fallback?.rawText ?? "",
            title: title ?? fallback?.title ?? rawText ?? "",
            detail: detail ?? fallback?.detail ?? "",
            deadline: deadline ?? fallback?.deadline ?? 0,
            status: status.flatMap(TaskStatus.init(rawValue:)) ?? fallback?.status ?? .pending,
            reminder: reminder ?? fallback?.reminder ?? .default,
            negotiation: negotiation?.map { $0.message() } ?? fallback?.negotiation ?? [],
            receivedAt: receivedAt ?? fallback?.receivedAt ?? 0,
            doneAt: doneAt ?? fallback?.doneAt ?? 0,
            archived: archived ?? fallback?.archived ?? false,
            deleted: deleted ?? fallback?.deleted ?? false,
            archivedAt: archivedAt ?? fallback?.archivedAt,
            archivedBy: archivedBy ?? fallback?.archivedBy,
            deletedAt: deletedAt ?? fallback?.deletedAt,
            deletedBy: deletedBy ?? fallback?.deletedBy
        )
    }
}

private struct RelayNegotiationDTO: Codable {
    var fromUserId: String
    var text: String
    var proposedDeadline: Int64
    var at: Int64

    init(message: NegotiationMessage) {
        self.fromUserId = message.fromUserId
        self.text = message.text
        self.proposedDeadline = message.proposedDeadline
        self.at = message.at
    }

    func message() -> NegotiationMessage {
        NegotiationMessage(
            fromUserId: fromUserId,
            text: text,
            proposedDeadline: proposedDeadline,
            at: at
        )
    }
}

private enum PaihuorRelayError: LocalizedError {
    case invalidURL
    case invalidResponse
    case notFound
    case requestFailed(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "中继服务地址无效"
        case .invalidResponse:
            return "中继服务响应无效"
        case .notFound:
            return "中继服务没有找到对应任务"
        case .requestFailed(let statusCode, let message):
            if let message,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "中继服务请求失败（\(statusCode)）：\(message)"
            }
            return "中继服务请求失败（\(statusCode)）"
        }
    }
}
