import Foundation

private actor Attempts {
    var errors: [URLError.Code]
    private(set) var freshFlags: [Bool] = []
    init(_ errors: [URLError.Code]) { self.errors = errors }
    func send(_ request: URLRequest, fresh: Bool) throws -> (data: Data, status: Int) {
        freshFlags.append(fresh)
        if !errors.isEmpty { throw URLError(errors.removeFirst()) }
        return (Data(), 200)
    }
}

@main struct HTTPRecoveryCheck {
    static func main() async throws {
        let get = URLRequest(url: URL(string: "https://api.deepseek.com/models")!)
        var post = get; post.httpMethod = "POST"
        let handshake = Attempts([.secureConnectionFailed, .secureConnectionFailed])
        let result = try await HTTPRecovery.send(post, pause: { _ in }) { try await handshake.send($0, fresh: $1) }
        let flags = await handshake.freshFlags
        precondition(result.status == 200 && flags == [false, true, true])
        for (method, codes, expected) in [
            ("POST", [URLError.Code.secureConnectionFailed, .secureConnectionFailed, .secureConnectionFailed], 3),
            ("POST", [.serverCertificateUntrusted], 1),
            ("POST", [.serverCertificateHasBadDate], 1),
            ("POST", [.timedOut], 1),
            ("POST", [.networkConnectionLost], 1),
            ("GET", [.notConnectedToInternet], 1)
        ] {
            var request = get; request.httpMethod = method
            let attempts = Attempts(codes)
            do {
                _ = try await HTTPRecovery.send(request, pause: { _ in }) { try await attempts.send($0, fresh: $1) }
                preconditionFailure("Unexpected success")
            } catch let failure as TravelNetworkFailure {
                precondition(failure.service == "DeepSeek")
                precondition(!failure.localizedDescription.contains("https://"))
            }
            let count = await attempts.freshFlags.count
            precondition(count == expected)
        }
        let cancelled = Attempts([.cancelled])
        do { _ = try await HTTPRecovery.send(post, pause: { _ in }) { try await cancelled.send($0, fresh: $1) }; preconditionFailure() }
        catch is CancellationError {}
        let delay = Attempts([.secureConnectionFailed])
        do { _ = try await HTTPRecovery.send(post, pause: { _ in throw CancellationError() }) { try await delay.send($0, fresh: $1) }; preconditionFailure() }
        catch is CancellationError {}
        let delayCount = await delay.freshFlags.count; precondition(delayCount == 1)
        let status = try await HTTPRecovery.send(get, pause: { _ in preconditionFailure() }) { _, _ in (Data(), 401) }
        precondition(status.status == 401)
        print("TLS_FRESH_SESSION_RECOVERY_AND_THREE_ATTEMPT_LIMIT=passed")
        print("CERTIFICATE_FAILURE_NO_RETRY_POST_TIMEOUT_NO_REPLAY=passed")
        print("CANCELLATION_AND_HTTP_AUTH_STATUS=passed")
    }
}
