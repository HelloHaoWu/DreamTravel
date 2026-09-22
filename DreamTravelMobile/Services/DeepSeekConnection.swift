import Foundation
import Security

struct DeepSeekConfiguration: Codable, Equatable, Sendable {
    var baseURL = "https://api.deepseek.com"
    var model = "deepseek-v4-flash"
}

struct DeepSeekValidationResult: Equatable, Sendable {
    let requestedModel: String
    let resolvedModel: String
    let advertisedModels: [String]
}

enum DeepSeekConnectionError: LocalizedError, Sendable {
    case emptyKey
    case invalidBaseURL
    case invalidResponse
    case http(status: Int, message: String?)
    case modelUnavailable(String)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            "请先填写 DeepSeek API Key。"
        case .invalidBaseURL:
            "DeepSeek 服务地址无效。"
        case .invalidResponse:
            "DeepSeek 返回了无法识别的响应。"
        case let .http(status, message):
            switch status {
            case 401:
                "DeepSeek API Key 无效或已失效。"
            case 429:
                "DeepSeek 当前请求过多或额度不足，请稍后再试。"
            default:
                message.map { "连接失败（\(status)）：\($0)" } ?? "连接失败（HTTP \(status)）。"
            }
        case let .modelUnavailable(model):
            "连接成功，但账号当前没有返回模型 \(model)。"
        case let .keychain(status):
            "无法访问钥匙串（\(status)）。"
        }
    }
}

enum DeepSeekKeychainStore {
    private static let service = "com.dreamtravel.mobile.deepseek"
    private static let account = "api-key"

    static func save(_ key: String) throws {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw DeepSeekConnectionError.keychain(updateStatus)
        }

        var item = lookup
        attributes.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw DeepSeekConnectionError.keychain(addStatus)
        }
    }

    static func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw DeepSeekConnectionError.keychain(status)
        }
        return String(data: data, encoding: .utf8)
    }
}

struct DeepSeekAPIClient: Sendable {
    func validate(
        apiKey: String,
        configuration: DeepSeekConfiguration = DeepSeekConfiguration()
    ) async throws -> DeepSeekValidationResult {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw DeepSeekConnectionError.emptyKey }

        guard var components = URLComponents(string: configuration.baseURL),
              components.scheme == "https",
              components.host != nil else {
            throw DeepSeekConnectionError.invalidBaseURL
        }
        components.path = "/models"
        guard let modelsURL = components.url else { throw DeepSeekConnectionError.invalidBaseURL }

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")

        let response = try await TravelHTTPTransport.live.send(request)
        let data = response.data
        guard (200..<300).contains(response.status) else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error.message)
            throw DeepSeekConnectionError.http(status: response.status, message: message)
        }

        let advertisedModels = try JSONDecoder().decode(ModelList.self, from: data).data.map(\.id)

        // `/models` can return canonical model names while the Responses endpoint
        // accepts a public alias. Probe the configured name instead of rejecting
        // an alias only because it is absent from the discovery response.
        components.path = "/responses"
        guard let responsesURL = components.url else { throw DeepSeekConnectionError.invalidBaseURL }

        var probe = URLRequest(url: responsesURL)
        probe.httpMethod = "POST"
        probe.timeoutInterval = 30
        probe.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        probe.setValue("application/json", forHTTPHeaderField: "Content-Type")
        probe.httpBody = try JSONEncoder().encode(ResponsesProbeRequest(
            model: configuration.model,
            input: "Reply with OK.",
            maxOutputTokens: 16
        ))

        let probeResponse = try await TravelHTTPTransport.live.send(probe)
        let probeData = probeResponse.data
        guard (200..<300).contains(probeResponse.status) else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: probeData).error.message)
            if probeResponse.status == 400 || probeResponse.status == 404 {
                throw DeepSeekConnectionError.modelUnavailable(configuration.model)
            }
            throw DeepSeekConnectionError.http(status: probeResponse.status, message: message)
        }

        let probePayload = try JSONDecoder().decode(ResponsesProbeResponse.self, from: probeData)
        guard !probePayload.id.isEmpty, !probePayload.model.isEmpty else {
            throw DeepSeekConnectionError.invalidResponse
        }

        return DeepSeekValidationResult(
            requestedModel: configuration.model,
            resolvedModel: probePayload.model,
            advertisedModels: advertisedModels
        )
    }
}

private struct ResponsesProbeRequest: Encodable {
    let model: String
    let input: String
    let maxOutputTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case maxOutputTokens = "max_output_tokens"
    }
}

private struct ResponsesProbeResponse: Decodable {
    let id: String
    let model: String
}

private struct ModelList: Decodable {
    let data: [Item]
    struct Item: Decodable { let id: String }
}

private struct ErrorEnvelope: Decodable {
    let error: Body
    struct Body: Decodable { let message: String }
}
