import Foundation

@main struct PublicationCheck {
    struct Failure: Error { let message: String }
    static let rules: [(String, String)] = [
        ("model-key", #"\bsk-[A-Za-z0-9_-]{20,}\b"#),
        ("tencent-key", #"\b[A-Z0-9]{5}(?:-[A-Z0-9]{5}){5}\b"#),
        ("github-token", #"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"#),
        ("cloud-key", #"\b(?:AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,})\b"#),
        ("private-key", #"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#),
        ("personal-home-path", #"/(?:Users|home)/[^\s/\"'<>]+"#),
        ("signing-team", #"DEVELOPMENT_TEAM\s*=\s*\"?[A-Z0-9]{10}\"?\s*;"#),
        ("device-identifier", #"\b[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\b"#)
    ]
    static func run(_ executable: String, _ args: [String], required: Bool = true) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if required && process.terminationStatus != 0 { throw Failure(message: "Command failed; no credential output is printed.") }
        return process.terminationStatus == 0 ? data : Data()
    }
    static func git(_ args: [String], required: Bool = true) throws -> Data { try run("/usr/bin/git", args, required: required) }
    static func forbiddenPath(_ path: String) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        let blocked = ["Validation", "xcuserdata", ".build", "Build", "DerivedData", ".private", ".swiftpm"]
        let name = parts.last ?? ""
        return parts.contains(where: blocked.contains) || name == ".DS_Store" || name == ".env" ||
            (name.hasPrefix(".env.") && name != ".env.example") ||
            [".xcuserstate", ".pem", ".p12", ".p8", ".key", ".mobileprovision", ".log", ".local.xcconfig"].contains(where: name.hasSuffix) ||
            name.contains(".keychain") || parts.contains { $0.hasSuffix(".app") || $0.hasSuffix(".xcarchive") || $0.hasSuffix(".xcresult") }
    }
    static func findings(_ text: String, secrets: [String]) throws -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        var hits = try rules.compactMap { name, pattern -> String? in
            try NSRegularExpression(pattern: pattern).firstMatch(in: text, range: range) == nil ? nil : name
        }
        let email = try NSRegularExpression(pattern: #"[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})"#)
        for match in email.matches(in: text, range: range) {
            guard let domainRange = Range(match.range(at: 1), in: text) else { continue }
            let domain = text[domainRange].lowercased()
            if !["example.com", "example.org", "example.net", "users.noreply.github.com"].contains(domain) && !domain.hasSuffix(".test") && !domain.hasSuffix(".example") {
                hits.append("personal-email")
            }
        }
        if secrets.contains(where: text.contains) { hits.append("known-local-credential") }
        return Array(Set(hits)).sorted()
    }
    static func main() {
        do { try check() }
        catch let error as Failure {
            FileHandle.standardError.write(Data((error.message + "\n").utf8)); exit(1)
        } catch {
            FileHandle.standardError.write(Data("Publication check failed; sensitive contents were not printed.\n".utf8)); exit(1)
        }
    }
    static func check() throws {
        if CommandLine.arguments.contains("--self-test") {
            let fakeModel = "sk" + "-" + String(repeating: "a", count: 32)
            let fakeMap = Array(repeating: String(repeating: "A", count: 5), count: 6).joined(separator: "-")
            guard try findings(fakeModel, secrets: []).contains("model-key"),
                  try findings(fakeMap, secrets: []).contains("tencent-key"),
                  try findings("/" + "Users" + "/example/private", secrets: []).contains("personal-home-path"),
                  try findings("alice" + "@private.invalid", secrets: []).contains("personal-email"),
                  try findings("fixture-only", secrets: []).isEmpty,
                  try findings("local-secret-sentinel", secrets: ["local-secret-sentinel"]).contains("known-local-credential"),
                  forbiddenPath("Validation/result.json"), forbiddenPath("App.xcodeproj/xcuserdata/user/settings"),
                  !forbiddenPath("Tests/TravelToolFixtureCheck.swift") else { throw Failure(message: "Publication checker self-test failed.") }
            print("PUBLICATION_CHECK_SELF_TEST=passed")
            return
        }
        var secrets: [String] = []
        if CommandLine.arguments.contains("--local-credentials") {
            for service in ["com.dreamtravel.test.deepseek", "com.dreamtravel.test.tencent-map"] {
                let data = try run("/usr/bin/security", ["find-generic-password", "-s", service, "-w"])
                let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { throw Failure(message: "A requested local credential was unavailable; exact-match audit incomplete.") }
                secrets += [value, Data(value.utf8).base64EncodedString(), value.utf8.map { String(format: "%02x", $0) }.joined()]
            }
            print("LOCAL_CREDENTIAL_COMPARISON=enabled (values never printed)")
        }
        let staged = String(decoding: try git(["ls-files", "--stage", "-z"]), as: UTF8.self)
        var blobs: [String: Set<String>] = [:]
        for entry in staged.split(separator: "\0") {
            let pair = entry.split(separator: "\t", maxSplits: 1)
            guard pair.count == 2 else { throw Failure(message: "Malformed index entry.") }
            let meta = pair[0].split(separator: " ")
            guard meta.count == 3, meta[2] == "0", meta[0] != "120000", meta[0] != "160000" else {
                throw Failure(message: "Unmerged files, symlinks or submodules need manual publication review.")
            }
            blobs[String(meta[1]), default: []].insert(String(pair[1]))
        }
        guard !blobs.isEmpty else { throw Failure(message: "Stage the intended public files before running this check.") }
        let history = String(decoding: try git(["rev-list", "--objects", "--all"], required: false), as: UTF8.self)
        for entry in history.split(separator: "\n") {
            let pair = entry.split(separator: " ", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let type = String(decoding: try git(["cat-file", "-t", String(pair[0])]), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if type == "blob" { blobs[String(pair[0]), default: []].insert(String(pair[1])) }
        }
        var failures: [String] = []
        for (hash, paths) in blobs {
            for path in paths where forbiddenPath(path) { failures.append("Excluded local artifact is tracked: \(path)") }
            let data = try git(["cat-file", "blob", hash])
            guard data.count < 10_000_000, let text = String(data: data, encoding: .utf8) else {
                failures.append("Non-text or oversized artifact requires review: \(paths.sorted().joined(separator: ", "))"); continue
            }
            for finding in try findings(text, secrets: secrets) {
                failures.append("\(finding): \(paths.sorted().joined(separator: ", "))")
            }
        }
        let identities = String(decoding: try git(["log", "--all", "--format=%an <%ae>%n%cn <%ce>"], required: false), as: UTF8.self)
        for finding in try findings(identities, secrets: secrets) { failures.append("Commit identity: \(finding)") }
        guard failures.isEmpty else { throw Failure(message: failures.sorted().joined(separator: "\n")) }
        print("PUBLICATION_INDEX_AND_HISTORY=passed BLOBS=\(blobs.count)")
    }
}
