import SwiftUI

@MainActor
final class ModelConnectionViewModel: ObservableObject {
    @Published var apiKey = ""
    @Published private(set) var isChecking = false
    @Published private(set) var isConnected = false
    @Published private(set) var message = ""

    let configuration = DeepSeekConfiguration()
    private let client = DeepSeekAPIClient()

    init() {
        do {
            if let saved = try DeepSeekKeychainStore.read() {
                apiKey = saved
                isConnected = true
                message = "已从本机钥匙串读取连接配置"
            }
        } catch {
            // Unsigned simulator builds can deny Keychain reads. Keep first use quiet;
            // validation will surface a concrete save error if access is still unavailable.
            message = ""
        }
    }

    func validateAndSave() {
        guard !isChecking else { return }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            message = DeepSeekConnectionError.emptyKey.localizedDescription
            return
        }

        isChecking = true
        isConnected = false
        message = "正在调用 DeepSeek 验证模型"

        Task {
            do {
                let result = try await client.validate(apiKey: key, configuration: configuration)
                try DeepSeekKeychainStore.save(key)
                apiKey = key
                isConnected = true
                if result.resolvedModel == result.requestedModel {
                    message = "连接成功，API Key 已保存到本机钥匙串"
                } else {
                    message = "连接成功，\(result.requestedModel) 当前映射为 \(result.resolvedModel)；Key 已保存到本机钥匙串"
                }
            } catch {
                isConnected = false
                message = error.localizedDescription
            }
            isChecking = false
        }
    }
}
