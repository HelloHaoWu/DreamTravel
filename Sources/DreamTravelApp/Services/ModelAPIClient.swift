import Foundation

struct ModelAPIClient: Sendable {
    func validate(configuration: ModelConfiguration, apiKey: String) async throws {
        let url = try endpoint("models", baseURL: configuration.baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)

        let list = try JSONDecoder().decode(ModelListResponse.self, from: data)
        guard list.data.contains(where: { $0.id == configuration.model }) else {
            throw ModelAPIError.modelUnavailable(configuration.model)
        }
    }

    func createTextResponse(
        configuration: ModelConfiguration,
        apiKey: String,
        instructions: String,
        input: String
    ) async throws -> String {
        switch configuration.apiFormat {
        case .responses:
            return try await createResponsesAPIResponse(
                configuration: configuration,
                apiKey: apiKey,
                instructions: instructions,
                input: input
            )
        case .chatCompletions:
            return try await createChatCompletion(
                configuration: configuration,
                apiKey: apiKey,
                instructions: instructions,
                input: input
            )
        }
    }

    private func createResponsesAPIResponse(
        configuration: ModelConfiguration,
        apiKey: String,
        instructions: String,
        input: String
    ) async throws -> String {
        let body = ResponsesRequest(
            model: configuration.model,
            instructions: instructions,
            input: input,
            reasoning: .init(effort: configuration.reasoningEffort.rawValue),
            maxOutputTokens: 4_096
        )
        let data = try await sendJSON(
            path: "responses",
            configuration: configuration,
            apiKey: apiKey,
            body: body
        )
        let result = try JSONDecoder().decode(ResponsesResult.self, from: data)
        let text = result.output
            .flatMap(\.content)
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ModelAPIError.emptyResponse }
        return text
    }

    private func createChatCompletion(
        configuration: ModelConfiguration,
        apiKey: String,
        instructions: String,
        input: String
    ) async throws -> String {
        let body = ChatRequest(
            model: configuration.model,
            messages: [
                .init(role: "system", content: instructions),
                .init(role: "user", content: input)
            ],
            thinking: .init(type: "enabled"),
            reasoningEffort: configuration.reasoningEffort.rawValue,
            maxTokens: 4_096
        )
        let data = try await sendJSON(
            path: "chat/completions",
            configuration: configuration,
            apiKey: apiKey,
            body: body
        )
        let result = try JSONDecoder().decode(ChatResult.self, from: data)
        guard let text = result.choices.first?.message.content,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModelAPIError.emptyResponse
        }
        return text
    }

    private func sendJSON<Body: Encodable>(
        path: String,
        configuration: ModelConfiguration,
        apiKey: String,
        body: Body
    ) async throws -> Data {
        var request = URLRequest(url: try endpoint(path, baseURL: configuration.baseURL))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)
        return data
    }

    private func endpoint(_ path: String, baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              components.host != nil else {
            throw ModelAPIError.invalidBaseURL
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, path]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        guard let url = components.url else { throw ModelAPIError.invalidBaseURL }
        return url
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ModelAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error.message)
            throw ModelAPIError.http(status: http.statusCode, message: message)
        }
    }
}

enum ModelAPIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case http(status: Int, message: String?)
    case modelUnavailable(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Base URL 格式不正确。"
        case .invalidResponse:
            "模型服务返回了无法识别的响应。"
        case .http(let status, let message):
            message.map { "连接失败（\(status)）：\($0)" } ?? "连接失败（HTTP \(status)）。"
        case .modelUnavailable(let model):
            "连接成功，但服务端没有返回模型 \(model)。"
        case .emptyResponse:
            "模型没有返回可用文本。"
        }
    }
}

private struct ModelListResponse: Decodable {
    let data: [ModelItem]
    struct ModelItem: Decodable { let id: String }
}

private struct APIErrorEnvelope: Decodable {
    let error: APIErrorBody
    struct APIErrorBody: Decodable { let message: String }
}

private struct ResponsesRequest: Encodable {
    let model: String
    let instructions: String
    let input: String
    let reasoning: Reasoning
    let maxOutputTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, instructions, input, reasoning
        case maxOutputTokens = "max_output_tokens"
    }

    struct Reasoning: Encodable { let effort: String }
}

private struct ResponsesResult: Decodable {
    let output: [OutputItem]
    struct OutputItem: Decodable { let content: [Content] }
    struct Content: Decodable { let text: String? }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let thinking: Thinking
    let reasoningEffort: String
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages, thinking
        case reasoningEffort = "reasoning_effort"
        case maxTokens = "max_tokens"
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct Thinking: Encodable { let type: String }
}

private struct ChatResult: Decodable {
    let choices: [Choice]
    struct Choice: Decodable { let message: Message }
    struct Message: Decodable { let content: String? }
}
