import Foundation

struct ReferenceEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let city: String
    var idea: DiscoveryIdea
    let sources: [ResearchSource]
    var savedAt: Date
    var isEnabled: Bool
}

struct ReferenceArchive: Codable, Sendable {
    var version = 1
    var entries: [ReferenceEntry] = []
    var deletedFingerprints: Set<String> = []
}

actor ReferenceLibrary {
    static let shared = ReferenceLibrary()
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DreamTravel", isDirectory: true).appendingPathComponent("references-v1.json")
    }

    func entries(city: String? = nil, enabledOnly: Bool = false) throws -> [ReferenceEntry] {
        try load().entries.filter {
            (city == nil || $0.city == city) && (!enabledOnly || $0.isEnabled)
        }.sorted { $0.savedAt > $1.savedAt }
    }

    func save(_ report: DiscoveryReport) throws {
        var archive = try load()
        for idea in report.ideas {
            let fingerprint = Self.fingerprint(city: report.city, idea: idea)
            guard !archive.deletedFingerprints.contains(fingerprint) else { continue }
            let sources = report.sources.filter { idea.sourceURLs.contains($0.url) }
            if let index = archive.entries.firstIndex(where: { Self.fingerprint(city: $0.city, idea: $0.idea) == fingerprint }) {
                // Preserve the user's edit and disabled status when refreshing a matching source set.
                archive.entries[index].savedAt = report.searchedAt
            } else {
                archive.entries.append(ReferenceEntry(id: UUID(), city: report.city, idea: idea, sources: sources, savedAt: report.searchedAt, isEnabled: true))
            }
        }
        try write(archive)
    }

    func update(_ entry: ReferenceEntry) throws {
        var archive = try load()
        guard let index = archive.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        archive.entries[index] = entry
        try write(archive)
    }

    func delete(_ ids: Set<UUID>) throws {
        var archive = try load()
        for entry in archive.entries where ids.contains(entry.id) {
            archive.deletedFingerprints.insert(Self.fingerprint(city: entry.city, idea: entry.idea))
        }
        archive.entries.removeAll { ids.contains($0.id) }
        try write(archive)
    }

    private static func fingerprint(city: String, idea: DiscoveryIdea) -> String {
        city + "|" + idea.sourceURLs.sorted().joined(separator: "|")
    }

    private func load() throws -> ReferenceArchive {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return ReferenceArchive() }
        let archive = try JSONDecoder().decode(ReferenceArchive.self, from: Data(contentsOf: fileURL))
        guard archive.version == 1 else { throw AgentFailure(message: "参考库版本不兼容，原文件保持不变。") }
        return archive
    }

    private func write(_ archive: ReferenceArchive) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(archive)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

struct ResearchPreferences: Sendable {
    let searches: Bool
    let usesLibrary: Bool
    let savesReferences: Bool
    let researchesPlaces: Bool

    static func current() -> Self {
        let defaults = UserDefaults.standard
        return Self(searches: defaults.object(forKey: "research.activeSearch") as? Bool ?? true,
                    usesLibrary: defaults.object(forKey: "research.useLibrary") as? Bool ?? true,
                    savesReferences: defaults.object(forKey: "research.saveReferences") as? Bool ?? true,
                    researchesPlaces: defaults.object(forKey: "research.placeDetails") as? Bool ?? true)
    }
}
