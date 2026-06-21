import Foundation

enum UserRole: String, Codable, CaseIterable, Identifiable {
    case wife
    case husband

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wife:
            return "老婆"
        case .husband:
            return "老公"
        }
    }

    var counterpart: UserRole {
        switch self {
        case .wife:
            return .husband
        case .husband:
            return .wife
        }
    }
}

struct FamilyProfile: Codable, Equatable {
    var familyId: String
    var userId: UserRole
    var userName: String

    var counterpartUserId: UserRole {
        userId.counterpart
    }

    var effectiveDisplayName: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? userId.displayName : trimmed
    }
}
