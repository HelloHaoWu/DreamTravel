import Foundation

struct TripIntent: Codable, Equatable, Sendable {
    let city: String
    let scheduledStart: Date
    let timeWindow: String
    let energy: String
    let mood: String
    let note: String?
}

enum PreferredEnvironment: String, Codable, Equatable, Sendable {
    case indoor
    case outdoor
    case mixed
}

struct TripSlotSearchBrief: Codable, Equatable, Sendable {
    let title: String
    let purpose: String
    let preferredEnvironment: PreferredEnvironment
    let searchQueries: [String]
    var suggestedStayMinutes: [Int]? = nil
    var startMinute: Int? = nil
    var isDining: Bool? = nil
}

enum TripSchedule {
    static let starts = [14 * 60, 16 * 60 + 20, 18 * 60 + 40]
    static let meeting = 13 * 60 + 30
    static let ending = 21 * 60 + 30
    static let bufferMinutes = 10
    // Compatibility with older saved plans. These are planning allowances, not venue facts.
    static let defaultStays = [90, 80, 100]
    static func connectionCount(slots: Int) -> Int { 6 + max(0, slots - 1) * 9 }
    static func start(_ brief: TripPlanningBrief, slot: Int) -> Int {
        if let value = brief.slots[slot].startMinute { return value }
        if brief.slots.count == 3 { return starts[slot] }
        return 840 + slot * (420 / max(1, brief.slots.count))
    }
    static func stay(_ brief: TripPlanningBrief, slot: Int, candidate: Int) -> Int {
        guard brief.slots.indices.contains(slot), let stays = brief.slots[slot].suggestedStayMinutes,
              stays.indices.contains(candidate) else { return brief.slots.count == 3 ? defaultStays[slot] : 45 }
        return stays[candidate]
    }
    static func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }

    /// Schedule the entire candidate graph once, before publication. Durations are never shortened.
    static func scheduled(_ draft: TripDraftManifest, routes: TripRouteEvidenceMatrix?) throws -> TripDraftManifest {
        guard let routes else { return draft }
        let count = draft.planningBrief.slots.count
        guard (3...5).contains(count), routes.betweenSlots.count == count - 1,
              routes.betweenSlots.allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.count == 3 && $0.allSatisfy { $0.durationSeconds >= 0 } } }) else {
            throw AgentFailure(message: "时间编排缺少完整的候选路线。")
        }
        var slots = draft.planningBrief.slots
        var start = 840
        for slot in 0..<count {
            // Keep the proposed meal time as a lower bound. Other slack can move earlier.
            if slots[slot].isDining == true { start = max(start, slots[slot].startMinute ?? start) }
            slots[slot].startMinute = start
            if slot < count - 1 {
                let longest = (0..<3).map { candidate in
                    stay(draft.planningBrief, slot: slot, candidate: candidate) * 60 +
                        (routes.betweenSlots[slot][candidate].map(\.durationSeconds).max() ?? 0)
                }.max() ?? 0
                start += Int(ceil(Double(longest) / 60)) + bufferMinutes
                start = ((start + 4) / 5) * 5
            }
        }
        let original = draft.planningBrief
        let brief = TripPlanningBrief(title: original.title, summary: original.summary, weatherStrategy: original.weatherStrategy, variants: original.variants, slots: slots)
        return TripDraftManifest(runID: draft.runID, intent: draft.intent, slotCount: draft.slotCount,
            candidatesPerSlot: draft.candidatesPerSlot, candidateCount: draft.candidateCount, requiredConnectionCount: draft.requiredConnectionCount,
            planningBrief: brief, modelProvider: draft.modelProvider, weatherSnapshotAt: draft.weatherSnapshotAt,
            generatedAt: draft.generatedAt, excludedPlaceIDs: draft.excludedPlaceIDs, requiresThematicMatch: draft.requiresThematicMatch)
    }
}

struct TripPlanVariantBrief: Codable, Equatable, Sendable {
    let title: String
    let subtitle: String
    let selection: [Int]
}

struct TripPlanningBrief: Codable, Equatable, Sendable {
    let title: String
    let summary: String
    let weatherStrategy: String
    let variants: [TripPlanVariantBrief]
    let slots: [TripSlotSearchBrief]
}

enum AgentPhase: String, Codable, Equatable, Sendable {
    case idle
    case snapshotting
    case queryingWeather
    case discovering
    case researchingPlaces
    case planning
    case queryingPlaces
    case queryingRoutes
    case verifying
    case ready
    case cancelled
    case failed
}

struct TripDraftManifest: Codable, Equatable, Sendable {
    let runID: UUID
    let intent: TripIntent
    let slotCount: Int
    let candidatesPerSlot: Int
    let candidateCount: Int
    let requiredConnectionCount: Int
    let planningBrief: TripPlanningBrief
    let modelProvider: String
    let weatherSnapshotAt: Date
    let generatedAt: Date
    var excludedPlaceIDs: [String] = []
    var requiresThematicMatch: Bool = false
}

enum EvidenceOrigin: String, Codable, Equatable, Sendable {
    case mock
    case liveAPI
}

struct EvidenceMetadata: Codable, Equatable, Sendable {
    let provider: String
    let origin: EvidenceOrigin
    let fetchedAt: Date
    let validUntil: Date
}

struct WeatherEvidenceSummary: Codable, Equatable, Sendable {
    let city: String
    let forecastFor: Date
    let condition: String
    let temperatureCelsius: Double
    let feelsLikeCelsius: Double?
    let humidityPercent: Int
    let precipitationProbabilityPercent: Int?
    let metadata: EvidenceMetadata
    let sourceAttributions: [String]
}

/// Mainland map providers return GCJ-02 coordinates. Keep them separate from MapKit coordinates.
struct TravelCoordinate: Codable, Hashable, Sendable {
    let longitude: Double
    let latitude: Double

    var tencentQueryValue: String {
        String(format: "%.6f,%.6f", latitude, longitude)
    }
}

enum OpeningHoursEvidenceStatus: String, Codable, Equatable, Sendable {
    case verified
    case unavailable
}

struct TravelPlaceEvidence: Codable, Equatable, Sendable {
    let providerID: String
    let name: String
    let address: String
    let coordinate: TravelCoordinate
    let weeklyOpeningHours: String
    let openingHoursStatus: OpeningHoursEvidenceStatus
    let openingHoursCoverVisit: Bool
    let estimatedCostYuan: Double?
}

struct TravelEndpointEvidence: Codable, Equatable, Sendable {
    let name: String
    let address: String
    let coordinate: TravelCoordinate
}

enum TravelMode: String, CaseIterable, Codable, Hashable, Sendable {
    case walking, bicycling, driving
    var title: String {
        switch self { case .walking: "步行"; case .bicycling: "骑行"; case .driving: "驾车" }
    }
    var symbol: String {
        switch self { case .walking: "figure.walk"; case .bicycling: "bicycle"; case .driving: "car.fill" }
    }
    static func from(method: String) -> TravelMode {
        if method == "步行" { return .walking }
        if method == "骑行" { return .bicycling }
        return .driving
    }
}

struct TravelModeOption: Codable, Equatable, Sendable {
    let mode: TravelMode
    let distanceMeters: Int?
    let durationSeconds: Int?
    var unavailableReason: String? = nil
    var isAvailable: Bool { distanceMeters.map { $0 >= 0 } == true && durationSeconds.map { $0 >= 0 } == true && unavailableReason == nil }
    var timeText: String {
        guard let seconds = durationSeconds else { return "暂无数据" }
        return seconds < 60 ? "不足 1 分钟" : "约 \(Int(ceil(Double(seconds) / 60))) 分钟"
    }
}

enum TravelModePolicy {
    static func offered(_ options: [TravelModeOption]) -> [TravelModeOption] {
        let available = options.filter(\.isAvailable)
        if let walking = available.first(where: { $0.mode == .walking }), walking.durationSeconds! < 8 * 60 {
            return [walking]
        }
        return available.filter { $0.mode != .walking || $0.durationSeconds! <= 15 * 60 }
    }

    static func recommended(_ options: [TravelModeOption]) -> TravelModeOption? {
        let eligible = offered(options)
        // Short walks avoid finding a bike or parking; longer transfers prioritize lower effort.
        return eligible.first { $0.mode == .walking } ?? eligible.first { $0.mode == .driving } ?? eligible.first
    }
}

struct TravelRouteEvidence: Codable, Equatable, Sendable {
    let distanceMeters: Int
    let durationSeconds: Int
    let method: String
    var alternatives: [TravelModeOption]? = nil
    var modeOptions: [TravelModeOption] {
        alternatives ?? [TravelModeOption(mode: .from(method: method), distanceMeters: distanceMeters, durationSeconds: durationSeconds)]
    }
}

struct TripRouteEvidenceMatrix: Codable, Equatable, Sendable {
    let meetingToFirst: [TravelRouteEvidence]
    let betweenSlots: [[[TravelRouteEvidence]]]
    let lastToEnding: [TravelRouteEvidence]
}

struct TravelEvidenceSummary: Codable, Equatable, Sendable {
    let resolvedCandidateCount: Int
    let resolvedConnectionCount: Int
    let verifiedAddressCount: Int
    let verifiedOpeningHoursCount: Int
    let unresolvedFactCount: Int
    let weather: WeatherEvidenceSummary
    let candidateMetadata: EvidenceMetadata
    let routeMetadata: EvidenceMetadata
    let places: [[TravelPlaceEvidence]]?
    let meetingPoint: TravelEndpointEvidence?
    let endingPoint: TravelEndpointEvidence?
    let routeMatrix: TripRouteEvidenceMatrix?
}

struct CandidateEvidenceSummary: Codable, Equatable, Sendable {
    let resolvedCandidateCount: Int
    let verifiedAddressCount: Int
    let verifiedOpeningHoursCount: Int
    let unresolvedFactCount: Int
    let metadata: EvidenceMetadata
    let places: [[TravelPlaceEvidence]]?
    let meetingPoint: TravelEndpointEvidence?
    let endingPoint: TravelEndpointEvidence?
}

struct RouteEvidenceSummary: Codable, Equatable, Sendable {
    let resolvedConnectionCount: Int
    let unresolvedFactCount: Int
    let metadata: EvidenceMetadata
    let matrix: TripRouteEvidenceMatrix?
}

struct VerifiedTripSummary: Codable, Equatable, Sendable {
    let runID: UUID
    let city: String
    let candidateCount: Int
    let connectionCount: Int
    let unverifiedOpeningHoursCount: Int
    let planningBrief: TripPlanningBrief
    let modelProvider: String
    let weather: WeatherEvidenceSummary
    let isLive: Bool
    let evidenceProviders: [String]
    let verifiedAt: Date
    let places: [[TravelPlaceEvidence]]?
    let meetingPoint: TravelEndpointEvidence?
    let endingPoint: TravelEndpointEvidence?
    let routeMatrix: TripRouteEvidenceMatrix?
    var independentPlans: [VerifiedTripSummary]? = nil
    var discovery: DiscoveryReport? = nil
    var researchNotice: String? = nil
    var placeResearch: [String: PlaceResearchReport]? = nil
    var evidenceValidUntil: Date? = nil
}

struct AgentCheckpoint: Codable, Equatable, Sendable {
    let runID: UUID
    let intent: TripIntent
    let phase: AgentPhase
    let completedCandidateCount: Int
    let completedConnectionCount: Int
    let updatedAt: Date
}

struct AgentFailure: Codable, Error, Equatable, Sendable {
    let message: String
}

enum AgentEvent: Codable, Equatable, Sendable {
    case progress(phase: AgentPhase, message: String)
    case completed(VerifiedTripSummary)
    case cancelled
    case failed(AgentFailure)
}

protocol PlanningModelAdapter: Sendable {
    func makeDraft(
        for intent: TripIntent,
        weather: WeatherEvidenceSummary,
        runID: UUID
    ) async throws -> TripDraftManifest
    func makeDraft(for intent: TripIntent, weather: WeatherEvidenceSummary, runID: UUID, researchContext: String) async throws -> TripDraftManifest
}

extension PlanningModelAdapter {
    func makeDraft(for intent: TripIntent, weather: WeatherEvidenceSummary, runID: UUID, researchContext: String) async throws -> TripDraftManifest {
        try await makeDraft(for: intent, weather: weather, runID: runID)
    }
}

protocol TravelToolService: Sendable {
    func resolveWeather(for intent: TripIntent) async throws -> WeatherEvidenceSummary
    func resolveCandidates(for draft: TripDraftManifest) async throws -> CandidateEvidenceSummary
    func resolveConnections(for draft: TripDraftManifest) async throws -> RouteEvidenceSummary
    func availablePlaceHints(for intent: TripIntent, inspiration: DiscoveryIdea?) async throws -> String
}

extension TravelToolService {
    func availablePlaceHints(for intent: TripIntent, inspiration: DiscoveryIdea?) async throws -> String { "" }
}

protocol TripVerifying: Sendable {
    func verify(draft: TripDraftManifest, evidence: TravelEvidenceSummary) throws -> VerifiedTripSummary
}
