import Foundation

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profile: FamilyProfile?

    private let defaults: UserDefaults
    private let key = "paihuor.familyProfile"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.profile = Self.loadProfile(from: defaults, key: key)
    }

    func save(familyId: String, userId: UserRole, userName: String) {
        let profile = FamilyProfile(
            familyId: familyId.trimmingCharacters(in: .whitespacesAndNewlines),
            userId: userId,
            userName: userName.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        self.profile = profile
        persist(profile)
    }

    func clear() {
        profile = nil
        defaults.removeObject(forKey: key)
    }

    private func persist(_ profile: FamilyProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: key)
    }

    private static func loadProfile(from defaults: UserDefaults, key: String) -> FamilyProfile? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FamilyProfile.self, from: data)
    }
}
