import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [PaihuorTask] = []
    @Published private(set) var syncState: TaskSyncState = .localCache
    @Published private(set) var syncErrorMessage: String?

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let injectedSyncService: TaskSyncServicing?
    private var resolvedSyncService: TaskSyncServicing?
    private var isRefreshingFromRemote = false

    var syncProviderName: String {
        injectedSyncService?.providerName ?? Self.defaultSyncProviderName
    }

    init(fileManager: FileManager = .default, syncService: TaskSyncServicing? = nil) {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        self.fileURL = (documentsURL ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("paihuor_tasks.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        self.injectedSyncService = syncService

        load()
    }

    func refreshFromRemote(for profile: FamilyProfile, showsActivity: Bool = true) async {
        guard !isRefreshingFromRemote else { return }

        isRefreshingFromRemote = true
        defer { isRefreshingFromRemote = false }

        let previousState = syncState

        if showsActivity {
            syncState = .syncing
        }

        do {
            let remoteTasks = try await syncService().fetchTasks(for: profile, localTasks: tasks)
            merge(remoteTasks)
            save()
            syncErrorMessage = nil
            syncState = .synced(Date())
        } catch {
            syncErrorMessage = error.localizedDescription
            if showsActivity || previousState == .localCache {
                syncState = .failed(error.localizedDescription)
            } else {
                syncState = previousState
            }
        }
    }

    func relevantTasks(for profile: FamilyProfile) -> [PaihuorTask] {
        tasks
            .filter { task in
                task.familyId == profile.familyId
                    && (task.fromUserId == profile.userId.rawValue || task.toUserId == profile.userId.rawValue)
                    && !task.deleted
                    && (task.deletedAt ?? 0) == 0
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func createTask(
        rawText: String,
        title: String,
        detail: String,
        deadline: Int64,
        toUserId: UserRole,
        profile: FamilyProfile
    ) -> PaihuorTask {
        let task = PaihuorTask(
            familyId: profile.familyId,
            fromUserId: profile.userId.rawValue,
            toUserId: toUserId.rawValue,
            rawText: rawText,
            title: title,
            detail: detail,
            deadline: deadline
        )

        tasks.insert(task, at: 0)
        save()
        push(task, profile: profile)
        return task
    }

    func markReceived(_ task: PaihuorTask, profile: FamilyProfile) {
        guard let updatedTask = update(task.objectId, mutate: { draft in
            draft.status = .received
            draft.receivedAt = Date().epochMilliseconds
        }) else { return }

        push(updatedTask, profile: profile)
    }

    func markDone(_ task: PaihuorTask, profile: FamilyProfile) {
        guard let updatedTask = update(task.objectId, mutate: { draft in
            draft.status = .done
            draft.doneAt = Date().epochMilliseconds
        }) else { return }

        push(updatedTask, profile: profile)
    }

    func archiveTask(_ task: PaihuorTask, profile: FamilyProfile) {
        guard task.status == .done else { return }

        guard let updatedTask = update(task.objectId, mutate: { draft in
            draft.archived = true
            draft.archivedAt = Date().epochMilliseconds
            draft.archivedBy = profile.userId.rawValue
        }) else { return }

        push(updatedTask, profile: profile)
    }

    func deleteTask(_ task: PaihuorTask, profile: FamilyProfile) {
        guard task.fromUserId == profile.userId.rawValue else { return }

        guard let updatedTask = update(task.objectId, mutate: { draft in
            draft.deleted = true
            draft.deletedAt = Date().epochMilliseconds
            draft.deletedBy = profile.userId.rawValue
        }) else { return }

        Task {
            await deleteRemoteTask(updatedTask, profile: profile)
        }
    }

    func addNegotiation(
        to task: PaihuorTask,
        from profile: FamilyProfile,
        text: String,
        proposedDeadline: Int64
    ) {
        guard let updatedTask = update(task.objectId, mutate: { draft in
            draft.status = .negotiating
            draft.negotiation.append(
                NegotiationMessage(
                    fromUserId: profile.userId.rawValue,
                    text: text,
                    proposedDeadline: proposedDeadline
                )
            )
        }) else { return }

        push(updatedTask, profile: profile)
    }

    func acceptLatestNegotiation(_ task: PaihuorTask, profile: FamilyProfile) {
        guard let latestNegotiation = task.negotiation.last,
              latestNegotiation.fromUserId != profile.userId.rawValue else {
            return
        }

        guard let updatedTask = update(task.objectId, mutate: { draft in
            if latestNegotiation.proposedDeadline > 0 {
                draft.deadline = latestNegotiation.proposedDeadline
            }

            if draft.toUserId == profile.userId.rawValue && draft.receivedAt == 0 {
                draft.receivedAt = Date().epochMilliseconds
            }

            draft.status = .received
            draft.negotiation.append(
                NegotiationMessage(
                    fromUserId: profile.userId.rawValue,
                    text: "同意",
                    proposedDeadline: latestNegotiation.proposedDeadline
                )
            )
        }) else { return }

        push(updatedTask, profile: profile)
    }

    func clearAll(profile: FamilyProfile?) {
        if let profile {
            tasks.removeAll { $0.familyId == profile.familyId }
        } else {
            tasks = []
        }

        save()

        guard let profile else {
            syncState = .localCache
            return
        }

        Task {
            await clearRemoteTasks(for: profile)
        }
    }

    private func update(_ objectId: String, mutate: (inout PaihuorTask) -> Void) -> PaihuorTask? {
        guard let index = tasks.firstIndex(where: { $0.objectId == objectId }) else { return nil }

        var updatedTasks = tasks
        mutate(&updatedTasks[index])
        updatedTasks[index].updatedAt = Date()
        tasks = updatedTasks
        save()
        return updatedTasks[index]
    }

    private func push(_ task: PaihuorTask, profile: FamilyProfile) {
        Task {
            await pushTask(task, profile: profile)
        }
    }

    private func pushTask(_ task: PaihuorTask, profile: FamilyProfile) async {
        syncState = .syncing

        do {
            let syncedTask = try await syncService().upsertTask(task, for: profile)
            if syncedTask.objectId != task.objectId {
                tasks.removeAll { $0.objectId == task.objectId }
            }
            merge([syncedTask])
            save()
            syncErrorMessage = nil
            syncState = .synced(Date())
        } catch {
            syncErrorMessage = error.localizedDescription
            syncState = .failed(error.localizedDescription)
        }
    }

    private func deleteRemoteTask(_ task: PaihuorTask, profile: FamilyProfile) async {
        syncState = .syncing

        do {
            let syncedTask = try await syncService().deleteTask(task, for: profile)
            merge([syncedTask])
            save()
            syncErrorMessage = nil
            syncState = .synced(Date())
        } catch {
            syncErrorMessage = error.localizedDescription
            syncState = .failed(error.localizedDescription)
        }
    }

    private func clearRemoteTasks(for profile: FamilyProfile) async {
        syncState = .syncing

        do {
            try await syncService().deleteTasks(for: profile)
            syncErrorMessage = nil
            syncState = .synced(Date())
        } catch {
            syncErrorMessage = error.localizedDescription
            syncState = .failed(error.localizedDescription)
        }
    }

    private func merge(_ remoteTasks: [PaihuorTask]) {
        var tasksById = Dictionary(uniqueKeysWithValues: tasks.map { ($0.objectId, $0) })

        for remoteTask in remoteTasks {
            if let localTask = tasksById[remoteTask.objectId], localTask.updatedAt > remoteTask.updatedAt {
                continue
            }

            tasksById[remoteTask.objectId] = remoteTask
        }

        tasks = tasksById.values.sorted { $0.createdAt > $1.createdAt }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decodedTasks = try? decoder.decode([PaihuorTask].self, from: data) else {
            tasks = []
            return
        }

        tasks = decodedTasks
    }

    private func save() {
        guard let data = try? encoder.encode(tasks) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    private func syncService() -> TaskSyncServicing {
        if let injectedSyncService {
            return injectedSyncService
        }

        if let resolvedSyncService {
            return resolvedSyncService
        }

        let syncService = Self.defaultSyncService()
        resolvedSyncService = syncService
        return syncService
    }

    private static func defaultSyncService() -> TaskSyncServicing {
        PaihuorRelayTaskSyncService(
            baseURL: AppConfig.paihuorRelayBaseURL,
            lanURL: AppConfig.paihuorRelayLanURL,
            apiKey: AppConfig.paihuorRelayKey
        ) ?? MockTaskSyncService()
    }

    private static var defaultSyncProviderName: String {
        AppConfig.hasPaihuorRelayConfig ? "Paihuor Relay" : "Mock"
    }
}
