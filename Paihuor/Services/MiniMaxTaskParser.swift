import Foundation

enum MiniMaxTaskParserError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)
    case emptyContent
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "MiniMax Key 未配置"
        case .invalidResponse:
            return "MiniMax 返回格式不正确"
        case .requestFailed(let statusCode, let message):
            return "MiniMax 请求失败：\(statusCode) \(message)"
        case .emptyContent:
            return "MiniMax 没有返回内容"
        case .invalidJSON(let content):
            return "MiniMax 返回的 JSON 无法解析：\(content)"
        }
    }
}

struct MiniMaxTaskParser {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func parse(rawText: String, now: Date = Date()) async throws -> ParsedTaskDraft {
        let apiKey = AppConfig.minimaxAPIKey
        guard !apiKey.isEmpty else {
            throw MiniMaxTaskParserError.missingAPIKey
        }

        var request = URLRequest(url: AppConfig.minimaxEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ChatCompletionRequest(
                model: AppConfig.minimaxModel,
                messages: [
                    ChatMessage(role: "system", content: Self.systemPrompt),
                    ChatMessage(role: "user", content: Self.userPrompt(rawText: rawText, now: now))
                ],
                temperature: 0.2,
                maxTokens: 300
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MiniMaxTaskParserError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw MiniMaxTaskParserError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw MiniMaxTaskParserError.emptyContent
        }

        let jsonContent = Self.extractJSONObject(from: content)
        guard let jsonData = jsonContent.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(ModelTaskDraft.self, from: jsonData) else {
            throw MiniMaxTaskParserError.invalidJSON(jsonContent)
        }

        return ParsedTaskDraft(
            title: parsed.title.trimmingCharacters(in: .whitespacesAndNewlines),
            detail: parsed.detail.trimmingCharacters(in: .whitespacesAndNewlines),
            deadline: parsed.hasDeadline ? Self.deadlineMilliseconds(from: parsed.deadlineISO) : 0
        )
    }

    private static let systemPrompt = """
    你是"派活儿"App 的待办解析助手。用户会口述/输入一件要交代对方做的事。
    只输出一个严格的 JSON 对象，不要任何多余文字、不要 markdown 代码块：
    {"title":"一句话动作标题(不超过15字)","detail":"补充细节，没有则空字符串","hasDeadline":true或false,"deadlineISO":"ISO8601带时区的截止时间，如 2026-06-21T20:00:00+08:00；无截止则空字符串"}
    这是简单的信息抽取任务，不需要深度推理。不要输出 <think>、思考过程、解释、注释或前后缀。
    解析规则：
    - 基于用户消息里给出的"当前时间"解析相对时间。
    - "今晚X点"=当天X:00；"明早/明天X点"=次日X:00；"X小时后/X分钟后"=当前时间加对应时长；"下班前"约当天18:00；没提到时间则 hasDeadline=false。
    - 时区固定 Asia/Shanghai (+08:00)。
    """

    private static func userPrompt(rawText: String, now: Date) -> String {
        """
        当前时间：\(localISO8601String(from: now))
        口述内容：\(rawText)
        """
    }

    private static func localISO8601String(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.string(from: date)
    }

    private static func extractJSONObject(from content: String) -> String {
        let withoutThink = removeThinkBlocks(from: content)
        let trimmed = stripMarkdownFence(from: withoutThink)

        if let object = firstJSONObject(in: trimmed) {
            return object
        }

        return trimmed
    }

    private static func removeThinkBlocks(from content: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>") else {
            return content
        }

        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return regex
            .stringByReplacingMatches(in: content, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripMarkdownFence(from content: String) -> String {
        var trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("```") {
            trimmed = trimmed
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```JSON", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private static func firstJSONObject(in content: String) -> String? {
        guard let startIndex = content.firstIndex(of: "{") else {
            return nil
        }

        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var currentIndex = startIndex

        while currentIndex < content.endIndex {
            let character = content[currentIndex]

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1

                if depth == 0 {
                    return String(content[startIndex...currentIndex])
                }
            }

            currentIndex = content.index(after: currentIndex)
        }

        return nil
    }

    private static func deadlineMilliseconds(from isoString: String) -> Int64 {
        let trimmed = isoString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        if let date = formatter.date(from: trimmed) {
            return date.epochMilliseconds
        }

        let fallbackFormatter = DateFormatter()
        fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")
        fallbackFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return fallbackFormatter.date(from: trimmed)?.epochMilliseconds ?? 0
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
    }
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessage
    }
}

private struct ModelTaskDraft: Decodable {
    let title: String
    let detail: String
    let hasDeadline: Bool
    let deadlineISO: String
}
