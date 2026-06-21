import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [PaihuorTask] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
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

        load()
    }

    func relevantTasks(for profile: FamilyProfile) -> [PaihuorTask] {
        tasks
            .filter { task in
                task.familyId == profile.familyId
                    && (task.fromUserId == profile.userId.rawValue || task.toUserId == profile.userId.rawValue)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func createTask(
        rawText: String,
        title: String,
        detail: String,
        deadline: Int64,
        toUserId: UserRole,
        profile: FamilyProfile
    ) {
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
    }

    func markReceived(_ task: PaihuorTask) {
        update(task.objectId) { draft in
            draft.status = .received
            draft.receivedAt = Date().epochMilliseconds
        }
    }

    func markDone(_ task: PaihuorTask) {
        update(task.objectId) { draft in
            draft.status = .done
            draft.doneAt = Date().epochMilliseconds
        }
    }

    func addNegotiation(
        to task: PaihuorTask,
        from profile: FamilyProfile,
        text: String,
        proposedDeadline: Int64
    ) {
        update(task.objectId) { draft in
            draft.status = .negotiating
            draft.negotiation.append(
                NegotiationMessage(
                    fromUserId: profile.userId.rawValue,
                    text: text,
                    proposedDeadline: proposedDeadline
                )
            )
        }
    }

    func clearAll() {
        tasks = []
        save()
    }

    private func update(_ objectId: String, mutate: (inout PaihuorTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.objectId == objectId }) else { return }

        var updatedTasks = tasks
        mutate(&updatedTasks[index])
        updatedTasks[index].updatedAt = Date()
        tasks = updatedTasks
        save()
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
}
