import Foundation
import os

struct TravelHTTPTransport: Sendable {
    let send: @Sendable (URLRequest) async throws -> (data: Data, status: Int)
    static let live = TravelHTTPTransport { request in
        try await HTTPRecovery.send(request) { request, fresh in
            try await HTTPConnectionPool.shared.send(request, fresh: fresh)
        }
    }
}

private actor HTTPConnectionPool {
    static let shared = HTTPConnectionPool()
    private var sessions: [String: URLSession] = [:]
    func send(_ request: URLRequest, fresh: Bool) async throws -> (data: Data, status: Int) {
        guard let host = request.url?.host else { throw TravelProviderError.invalidRequest }
        if fresh { sessions.removeValue(forKey: host)?.finishTasksAndInvalidate() }
        let session: URLSession
        if let existing = sessions[host] { session = existing }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            configuration.timeoutIntervalForResource = 180
            // Keep normal system routing, ATS and certificate verification.
            session = URLSession(configuration: configuration)
            sessions[host] = session
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TravelProviderError.invalidRequest }
        return (data, http.statusCode)
    }
}

struct TravelNetworkFailure: LocalizedError, Sendable {
    let service: String
    let code: URLError.Code
    var errorDescription: String? {
        switch code {
        case .secureConnectionFailed:
            "与\(service)的安全连接暂时失败，自动重连后仍未恢复。请重试；若使用了代理或 VPN，请检查其连接后再试。已保存的 Key 无需重填。"
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected, .clientCertificateRequired:
            "无法验证\(service)的安全证书。请检查设备日期及网络的 HTTPS 检查设置，再重试。"
        case .notConnectedToInternet: "网络未连接，暂时无法访问\(service)。请联网后重试。"
        case .timedOut: "\(service)响应超时，请稍后重试。已有行程和 Key 已保留。"
        default: "暂时无法连接\(service)（网络错误 \(code.rawValue)），请检查网络后重试。"
        }
    }
    static func service(for request: URLRequest) -> String {
        switch request.url?.host {
        case "api.deepseek.com": request.url?.path.contains("anthropic") == true ? "DeepSeek 联网搜索" : "DeepSeek"
        case "apis.map.qq.com": request.url?.path.contains("weather") == true ? "腾讯天气" : "腾讯位置服务"
        default: "数据服务"
        }
    }
}

enum HTTPRecovery {
    typealias Operation = @Sendable (URLRequest, Bool) async throws -> (data: Data, status: Int)
    private static let logger = Logger(subsystem: "com.dreamtravel.mobile", category: "NetworkRecovery")
    static func send(_ request: URLRequest,
                     pause: @Sendable (Int) async throws -> Void = { attempt in
                         try await Task.sleep(for: .milliseconds(attempt == 0 ? 500 : 1500))
                     }, operation: Operation) async throws -> (data: Data, status: Int) {
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do { return try await operation(request, attempt > 0) }
            catch let error as URLError {
                if error.code == .cancelled { throw CancellationError() }
                let service = TravelNetworkFailure.service(for: request)
                logger.error("Service=\(service, privacy: .public) code=\(error.code.rawValue) attempt=\(attempt + 1)")
                guard attempt < 2, shouldRetry(error.code, method: request.httpMethod ?? "GET") else {
                    throw TravelNetworkFailure(service: service, code: error.code)
                }
                try await pause(attempt)
            }
        }
        throw TravelProviderError.invalidRequest
    }
    static func shouldRetry(_ code: URLError.Code, method: String) -> Bool {
        if [.secureConnectionFailed, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(code) { return true }
        // A timed-out POST may already have run remotely; do not replay it automatically.
        return ["GET", "HEAD"].contains(method.uppercased()) && [.timedOut, .networkConnectionLost].contains(code)
    }
}

#if DEBUG
enum NativeNetworkCheck {
    static func run() async {
        var status = ["state": "running", "phase": "credentials"]
        func save() {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DreamTravel")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = try? JSONSerialization.data(withJSONObject: status, options: .sortedKeys) {
                try? data.write(to: directory.appendingPathComponent("network-check.json"), options: .atomic)
            }
        }
        save()
        do {
            guard let modelKey = try DeepSeekCredentialProvider.read(),
                  case let .tencentMap(mapKey) = TravelProviderConfiguration.current() else {
                throw AgentFailure(message: "测试缺少已保存的凭据")
            }
            status["phase"] = "model-validation"; save()
            _ = try await DeepSeekAPIClient().validate(apiKey: modelKey)
            status["models-and-responses"] = "passed"
            status["phase"] = "tencent-weather"; save()
            let intent = TripIntent(city: "杭州", scheduledStart: Date().addingTimeInterval(86400), timeWindow: "下午到晚上", energy: "轻松", mood: "约会", note: "文化和室内体验")
            let weather = try await TencentLiveTravelToolService(key: mapKey).resolveWeather(for: intent)
            status["geocoder-and-weather"] = "passed"
            status["phase"] = "search-and-structured-research"; save()
            let report = try await DeepSeekInspirationDiscovery().discover(intent: intent, weather: weather)
            status["search-and-structured-research"] = "passed"
            status["ideas"] = String(report.ideas.count)
            status["sources"] = String(report.sources.count)
            status["state"] = "passed"
        } catch {
            status["state"] = "failed"
            if let error = error as? TravelNetworkFailure { status["error"] = error.localizedDescription }
            else { status["error"] = "Native API validation failed" }
        }
        save()
    }
}
#endif
