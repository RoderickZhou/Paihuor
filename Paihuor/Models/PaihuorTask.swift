import Foundation

enum TaskStatus: String, Codable, CaseIterable {
    case pending
    case received
    case negotiating
    case done
}

struct TaskReminder: Codable, Equatable {
    var intervalMinutes: Int
    var rampUpLastMinutes: Int
    var ringtone: String

    static let `default` = TaskReminder(
        intervalMinutes: 30,
        rampUpLastMinutes: 5,
        ringtone: "default"
    )
}

struct NegotiationMessage: Codable, Equatable, Identifiable {
    var id: String
    var fromUserId: String
    var text: String
    var proposedDeadline: Int64
    var at: Int64

    init(
        id: String = UUID().uuidString,
        fromUserId: String,
        text: String,
        proposedDeadline: Int64 = 0,
        at: Int64 = Date().epochMilliseconds
    ) {
        self.id = id
        self.fromUserId = fromUserId
        self.text = text
        self.proposedDeadline = proposedDeadline
        self.at = at
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case fromUserId
        case text
        case proposedDeadline
        case at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.fromUserId = try container.decode(String.self, forKey: .fromUserId)
        self.text = try container.decode(String.self, forKey: .text)
        self.proposedDeadline = try container.decodeIfPresent(Int64.self, forKey: .proposedDeadline) ?? 0
        self.at = try container.decodeIfPresent(Int64.self, forKey: .at) ?? Date().epochMilliseconds
    }
}

struct PaihuorTask: Codable, Equatable, Identifiable {
    var objectId: String
    var createdAt: Date
    var updatedAt: Date
    var familyId: String
    var fromUserId: String
    var toUserId: String
    var rawText: String
    var title: String
    var detail: String
    var deadline: Int64
    var status: TaskStatus
    var reminder: TaskReminder
    var negotiation: [NegotiationMessage]
    var receivedAt: Int64
    var doneAt: Int64
    var archived: Bool
    var deleted: Bool
    var archivedAt: Int64?
    var archivedBy: String?
    var deletedAt: Int64?
    var deletedBy: String?

    var id: String { objectId }

    var isDone: Bool {
        status == .done
    }

    init(
        objectId: String = UUID().uuidString,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        familyId: String,
        fromUserId: String,
        toUserId: String,
        rawText: String,
        title: String,
        detail: String = "",
        deadline: Int64 = 0,
        status: TaskStatus = .pending,
        reminder: TaskReminder = .default,
        negotiation: [NegotiationMessage] = [],
        receivedAt: Int64 = 0,
        doneAt: Int64 = 0,
        archived: Bool = false,
        deleted: Bool = false,
        archivedAt: Int64? = nil,
        archivedBy: String? = nil,
        deletedAt: Int64? = nil,
        deletedBy: String? = nil
    ) {
        self.objectId = objectId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.familyId = familyId
        self.fromUserId = fromUserId
        self.toUserId = toUserId
        self.rawText = rawText
        self.title = title
        self.detail = detail
        self.deadline = deadline
        self.status = status
        self.reminder = reminder
        self.negotiation = negotiation
        self.receivedAt = receivedAt
        self.doneAt = doneAt
        self.archived = archived
        self.deleted = deleted
        self.archivedAt = archivedAt
        self.archivedBy = archivedBy
        self.deletedAt = deletedAt
        self.deletedBy = deletedBy
    }
}
