import Foundation

enum AppConfig {
    static var minimaxAPIKey: String {
        infoValue(for: "MiniMaxAPIKey")
    }

    static var minimaxModel: String {
        let configuredModel = infoValue(for: "MiniMaxModel")
        return configuredModel.isEmpty ? "MiniMax-M3" : configuredModel
    }

    static var minimaxEndpoint: URL {
        let configuredEndpoint = infoValue(for: "MiniMaxEndpoint")
        return URL(string: configuredEndpoint)
            ?? URL(string: "https://api.minimaxi.com/v1/chat/completions")!
    }

    static var hasMiniMaxAPIKey: Bool {
        !minimaxAPIKey.isEmpty
    }

    static var paihuorRelayBaseURL: URL? {
        URL(string: infoValue(for: "PaihuorRelayBaseURL"))
    }

    static var paihuorRelayLanURL: URL? {
        URL(string: infoValue(for: "PaihuorRelayLanURL"))
    }

    static var paihuorRelayKey: String {
        infoValue(for: "PaihuorRelayKey")
    }

    static var hasPaihuorRelayConfig: Bool {
        (paihuorRelayBaseURL != nil || paihuorRelayLanURL != nil) && !paihuorRelayKey.isEmpty
    }

    static var defaultFamilyId: String {
        let configuredFamilyId = infoValue(for: "PaihuorDefaultFamilyId")
        return configuredFamilyId.isEmpty ? "fam-zx-001" : configuredFamilyId
    }

    private static func infoValue(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return ""
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("$(") ? "" : trimmed
    }
}
