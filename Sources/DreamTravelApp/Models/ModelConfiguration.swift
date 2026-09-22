import Foundation

enum ModelProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case deepSeek
    case openAI
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepSeek: "DeepSeek"
        case .openAI: "OpenAI"
        case .custom: "自定义兼容接口"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .deepSeek: "https://api.deepseek.com"
        case .openAI: "https://api.openai.com/v1"
        case .custom: ""
        }
    }

    var defaultModel: String {
        switch self {
        case .deepSeek: "deepseek-v4-flash"
        case .openAI: ""
        case .custom: ""
        }
    }
}

enum ModelAPIFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case responses
    case chatCompletions

    var id: String { rawValue }
    var title: String {
        switch self {
        case .responses: "Responses API"
        case .chatCompletions: "Chat Completions"
        }
    }
}

enum ModelReasoningEffort: String, CaseIterable, Identifiable, Codable, Sendable {
    case low
    case high
    case max

    var id: String { rawValue }
    var title: String {
        switch self {
        case .low: "快速"
        case .high: "周密"
        case .max: "深度"
        }
    }
}

struct ModelConfiguration: Codable, Equatable, Sendable {
    var provider: ModelProvider
    var baseURL: String
    var model: String
    var apiFormat: ModelAPIFormat
    var reasoningEffort: ModelReasoningEffort

    static let deepSeekFlash = ModelConfiguration(
        provider: .deepSeek,
        baseURL: ModelProvider.deepSeek.defaultBaseURL,
        model: ModelProvider.deepSeek.defaultModel,
        apiFormat: .responses,
        reasoningEffort: .high
    )
}
