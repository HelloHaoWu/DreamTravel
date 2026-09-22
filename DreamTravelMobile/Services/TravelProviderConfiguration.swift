import Foundation
import Security

enum TravelProviderConfiguration: Sendable {
    case tencentMap(key: String)

    static let quickRegisterURL = URL(string: "https://lbs.qq.com/dev/console/quick-register")!

    /// A personal key takes precedence. Each new generation reads a fresh snapshot.
    static func current() -> TravelProviderConfiguration? {
        select(personalKey: try? TencentKeychainStore.read(), development: fromDevelopmentEnvironment())
    }

    static func select(personalKey: String?, development: TravelProviderConfiguration?) -> TravelProviderConfiguration? {
        if let key = personalKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty { return .tencentMap(key: key) }
        return development
    }

    /// Product credentials are injected for a local development run only.
    /// Release can use a user's personal key; shared product keys need a gateway.
    static func fromDevelopmentEnvironment() -> TravelProviderConfiguration? {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let tencentKey = environment["DREAMTRAVEL_TENCENT_MAP_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !tencentKey.isEmpty {
            return .tencentMap(key: tencentKey)
        }
        return nil
#else
        return nil
#endif
    }
}

enum TencentKeychainStore {
    private static var lookup: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.dreamtravel.mobile.tencent-map",
         kSecAttrAccount as String: "web-service"]
    }
    static func save(_ key: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw DeepSeekConnectionError.keychain(status) }
        var item = lookup
        attributes.forEach { item[$0.key] = $0.value }
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw DeepSeekConnectionError.keychain(added) }
    }
    static func read() throws -> String? {
        var query = lookup
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw DeepSeekConnectionError.keychain(status) }
        return String(data: data, encoding: .utf8)
    }
    static func remove() throws {
        let status = SecItemDelete(lookup as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw DeepSeekConnectionError.keychain(status) }
    }
}

enum TravelProviderError: LocalizedError, Sendable {
    case invalidRequest
    case unavailable(String)
    case missingEvidence(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "地图或天气请求参数无效。"
        case let .unavailable(provider):
            "\(provider)暂时无法提供数据，请稍后重试。"
        case let .missingEvidence(detail):
            detail
        }
    }
}

#if DEBUG
/// Explicit local provisioning only: the secret arrives from the developer's Keychain.
/// Never overwrites an existing personal key, and never embeds one in the application.
enum TencentDevelopmentBootstrap {
    static func run() {
        let environment = ProcessInfo.processInfo.environment
        let shouldSave = environment["DREAMTRAVEL_SAVE_TENCENT_KEY"] == "1"
        guard shouldSave || environment["DREAMTRAVEL_CHECK_TENCENT_KEY"] == "1" else { return }
        var status: [String: Any] = [:]
        do {
            if shouldSave, try TencentKeychainStore.read() == nil,
               case let .tencentMap(key) = TravelProviderConfiguration.fromDevelopmentEnvironment() {
                try TencentKeychainStore.save(key)
            }
            let stored = try TencentKeychainStore.read()
            status["savedPersonalKeyPresent"] = stored?.isEmpty == false
            status["developmentKeyPresent"] = TravelProviderConfiguration.fromDevelopmentEnvironment() != nil
            if case let .tencentMap(injected) = TravelProviderConfiguration.fromDevelopmentEnvironment() {
                status["matchesInjectedKey"] = stored == injected
            }
        } catch { status["error"] = "Keychain access failed" }
        // Only booleans and a fixed error string, never credentials or request URLs.
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DreamTravel", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: status, options: .sortedKeys)
                .write(to: directory.appendingPathComponent("tencent-key-status.json"), options: .atomic)
        } catch { /* Diagnostics must not prevent application launch. */ }
    }
}
#endif
