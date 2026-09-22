import Foundation

func checkDiscoveryFixtures(template: VerifiedTripSummary) async throws {
    let search: [String: Any] = ["stop_reason": "end_turn", "content": [
        ["type": "server_tool_use", "id": "search-1", "name": "web_search"],
        ["type": "web_search_tool_result", "tool_use_id": "search-1", "content": [
            ["type": "web_search_result", "url": "https://example.com/post?utm_source=test", "title": "真实返回的来源"],
            ["type": "web_search_result", "url": "https://example.com/post", "title": "重复"],
            ["type": "web_search_result", "url": "http://127.0.0.1/secrets", "title": "拒绝本地地址"]]],
        ["type": "text", "text": "搜索摘要"]]]
    let batch = try DeepSeekWebSearchClient.parse(JSONSerialization.data(withJSONObject: search))
    precondition(batch.sources.count == 1 && batch.searchCount == 1)
    for bad in [
        ["stop_reason": "end_turn", "content": [["type": "text", "text": "我搜到了 https://fake.example"]]],
        ["stop_reason": "pause_turn", "content": search["content"]!],
        ["stop_reason": "end_turn", "content": [["type": "web_search_tool_result", "tool_use_id": "fake", "content": [["type": "web_search_result", "url": "https://example.com", "title": "伪来源"]]]]]
    ] {
        do { _ = try DeepSeekWebSearchClient.parse(JSONSerialization.data(withJSONObject: bad)); preconditionFailure("Accepted unproven search") }
        catch is AgentFailure { }
    }
    precondition(ResearchURL.validated("file:///etc/passwd") == nil)
    precondition(ResearchURL.validated("https://secret@domain.example/x") == nil)
    print("SEARCH_PROVENANCE_AND_URLS=passed")

    let location = URL(fileURLWithPath: "/tmp/DreamTravel-reference-fixture-\(UUID().uuidString).json")
    let library = ReferenceLibrary(fileURL: location)
    let report = DiscoveryReport(city: "杭州", searchedAt: Date(), ideas: [DiscoveryIdea(title: "雨天看展", summary: "短路线", searchTerms: ["美术馆"], sourceURLs: [batch.sources[0].url])], sources: batch.sources, searchCount: 1)
    try await library.save(report)
    try await library.save(report)
    var entries = try await ReferenceLibrary(fileURL: location).entries()
    precondition(entries.count == 1)
    entries[0].isEnabled = false
    try await library.update(entries[0])
    try await library.save(report)
    let enabled = try await library.entries(city: "杭州", enabledOnly: true)
    precondition(enabled.isEmpty)
    try await library.delete([entries[0].id])
    try await library.save(report)
    let deleted = try await library.entries()
    precondition(deleted.isEmpty)
    try Data("broken".utf8).write(to: location)
    do { try await library.save(report); preconditionFailure("Overwrote corrupt library") } catch { }
    let unchanged = try String(contentsOf: location, encoding: .utf8)
    precondition(unchanged == "broken")
    print("REFERENCE_PERSISTENCE_DISABLE_DELETE_CORRUPTION=passed")

    var plans: [VerifiedTripSummary] = []
    for index in 0..<3 {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(template)) as! [String: Any]
        var rows = object["places"] as! [[[String: Any]]]
        for slot in 0..<3 { for candidate in 0..<3 {
            rows[slot][candidate]["providerID"] = "\(index)-\(slot)-\(candidate)"
            rows[slot][candidate]["name"] = "\(index)号方案店\(slot)\(candidate)"
        } }
        object["places"] = rows
        plans.append(try JSONDecoder().decode(VerifiedTripSummary.self, from: JSONSerialization.data(withJSONObject: object)))
    }
    try AgentRuntime.validateDistinct(plans)
    do { try AgentRuntime.validateDistinct([plans[0], plans[0], plans[2]]); preconditionFailure("Shared pools accepted") } catch is AgentFailure { }
    var bundle = plans[0]; bundle.independentPlans = plans
    let stableBundle = bundle
    await MainActor.run {
        let app = MobileAppModel(); app.apply(result: stableBundle)
        for plan in 0..<3 {
            app.selectPlan(plan)
            precondition(app.choices[0][0].id == "\(plan)-0-0")
            for a in 0..<3 { for b in 0..<3 { for c in 0..<3 {
                app.selectStop(at: 0, choice: a); app.selectStop(at: 1, choice: b); app.selectStop(at: 2, choice: c)
                for edge in 0..<4 { precondition(!app.connection(at: edge).needsVerification) }
            } } }
            app.selectStop(at: 0, choice: plan)
        }
        for plan in 0..<3 { app.selectPlan(plan); precondition(app.selections[0] == plan) }
    }
    print("INDEPENDENT_POOLS_81_COMBINATIONS_AND_SELECTION_MEMORY=passed")
}

private actor ResearchFixturePlanner: PlanningModelAdapter {
    let brief: TripPlanningBrief
    private(set) var inputs: [String] = []
    init(brief: TripPlanningBrief) { self.brief = brief }
    func makeDraft(for intent: TripIntent, weather: WeatherEvidenceSummary, runID: UUID) async throws -> TripDraftManifest {
        TripDraftManifest(runID: runID, intent: intent, slotCount: 3, candidatesPerSlot: 3, candidateCount: 9, requiredConnectionCount: 24, planningBrief: brief, modelProvider: "Fixture", weatherSnapshotAt: weather.metadata.fetchedAt, generatedAt: Date())
    }
    func makeDraft(for intent: TripIntent, weather: WeatherEvidenceSummary, runID: UUID, researchContext: String) async throws -> TripDraftManifest {
        inputs.append(researchContext)
        return try await makeDraft(for: intent, weather: weather, runID: runID)
    }
}
private struct ResearchFixtureDiscovery: InspirationDiscovering {
    let fail: Bool
    func discover(intent: TripIntent, weather: WeatherEvidenceSummary) async throws -> DiscoveryReport {
        if fail { throw AgentFailure(message: "fixture search failure") }
        return DiscoveryReport(city: intent.city, searchedAt: Date(), ideas: (0..<3).map { index in
            DiscoveryIdea(title: "新玩法\(index)", summary: "来自搜索的主题\(index)", searchTerms: ["文化空间"], sourceURLs: ["https://example.com/\(index)"])
        }, sources: (0..<3).map { ResearchSource(title: "来源\($0)", url: "https://example.com/\($0)", pageAge: nil) }, searchCount: 1)
    }
}
private actor ResearchFixtureTools: TravelToolService {
    let template: VerifiedTripSummary
    private var index = 0
    init(template: VerifiedTripSummary) { self.template = template }
    func resolveWeather(for intent: TripIntent) async throws -> WeatherEvidenceSummary { template.weather }
    func availablePlaceHints(for intent: TripIntent, inspiration: DiscoveryIdea?) async throws -> String {
        "主题专属地图清单：\(inspiration?.title ?? "无主题")"
    }
    func resolveCandidates(for draft: TripDraftManifest) async throws -> CandidateEvidenceSummary {
        index += 1
        let places = template.places!.enumerated().map { slot, row in row.enumerated().map { candidate, place in
            TravelPlaceEvidence(providerID: "set-\(index)-\(slot)-\(candidate)", name: "独立\(index)-\(slot)-\(candidate)", address: place.address, coordinate: place.coordinate, weeklyOpeningHours: place.weeklyOpeningHours, openingHoursStatus: place.openingHoursStatus, openingHoursCoverVisit: place.openingHoursCoverVisit, estimatedCostYuan: nil)
        } }
        return CandidateEvidenceSummary(resolvedCandidateCount: 9, verifiedAddressCount: 9, verifiedOpeningHoursCount: 0, unresolvedFactCount: 0, metadata: EvidenceMetadata(provider: "Fixture", origin: .liveAPI, fetchedAt: Date(), validUntil: Date().addingTimeInterval(1000)), places: places, meetingPoint: template.meetingPoint, endingPoint: template.endingPoint)
    }
    func resolveConnections(for draft: TripDraftManifest) async throws -> RouteEvidenceSummary {
        RouteEvidenceSummary(resolvedConnectionCount: 24, unresolvedFactCount: 0, metadata: EvidenceMetadata(provider: "Fixture", origin: .liveAPI, fetchedAt: Date(), validUntil: Date().addingTimeInterval(1000)), matrix: template.routeMatrix)
    }
}

func checkResearchRuntime(template: VerifiedTripSummary) async throws {
    let intent = TripIntent(city: template.city, scheduledStart: template.weather.forecastFor, timeWindow: "下午", energy: "轻松", mood: "浪漫", note: nil)
    for fail in [false, true] {
        let planner = ResearchFixturePlanner(brief: template.planningBrief)
        let runtime = AgentRuntime(model: planner, tools: ResearchFixtureTools(template: template), verifier: DeterministicTripVerifier(mode: .live), discovery: ResearchFixtureDiscovery(fail: fail), independentPlans: true, preferences: { ResearchPreferences(searches: true, usesLibrary: false, savesReferences: false, researchesPlaces: false) })
        var completed: [VerifiedTripSummary] = []
        var failed = false
        for await event in await runtime.start(intent: intent) {
            switch event {
            case let .completed(result): completed.append(result)
            case .failed: failed = true
            default: break
            }
        }
        let inputs = await planner.inputs
        if fail {
            precondition(completed.isEmpty && failed && inputs.isEmpty)
        } else {
            precondition(!failed && completed.count == 1 && completed[0].independentPlans?.count == 3)
            precondition(inputs.count == 3)
            for index in 0..<3 {
                precondition(inputs[index].contains("来自搜索的主题\(index)"))
                precondition(inputs[index].contains("主题专属地图清单：新玩法\(index)"))
            }
        }
    }
    print("ACTIVE_SEARCH_CONTEXT_AND_BUNDLE_PUBLICATION=passed")
}
