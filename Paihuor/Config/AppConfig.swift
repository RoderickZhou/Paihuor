import Foundation

enum AppConfig {
    static var minimaxAPIKey: String {
        infoValue(for: "MiniMaxAPIKey")
    }

    static var minimaxModel: String {
        let configuredModel = infoValue(for: "MiniMaxModel")
        return configuredModel.isEmpty ? "MiniMax-M2.7-highspeed" : configuredModel
    }

    static var minimaxEndpoint: URL {
        let configuredEndpoint = infoValue(for: "MiniMaxEndpoint")
        return URL(string: configuredEndpoint)
            ?? URL(string: "https://api.minimaxi.com/v1/chat/completions")!
    }

    static var hasMiniMaxAPIKey: Bool {
        !minimaxAPIKey.isEmpty
    }

    private static func infoValue(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return ""
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("$(") ? "" : trimmed
    }
}
