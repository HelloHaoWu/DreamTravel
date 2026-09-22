import Foundation
import Darwin

@main struct LiveCheck {
    static func credential(_ service: String) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", service, "-w"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        guard p.terminationStatus == 0, let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { throw AgentFailure(message: "Missing test credential") }
        return key
    }
    static func main() async {
        do { try await run() }
        catch {
            let message = (error as? AgentFailure)?.message ?? "Live validation failed; no credentials were logged."
            FileHandle.standardError.write(Data((message + "\n").utf8))
            exit(1)
        }
    }
    static func run() async throws {
        let deepseek = try credential("com.dreamtravel.test.deepseek")
        let tencent = try credential("com.dreamtravel.test.tencent-map")
        if CommandLine.arguments.contains("--transport-only") {
            let api = TencentTravelAPI(key: tencent)
            guard let place = try await api.search(query: "浙江省博物馆武林馆区", city: "杭州").first else {
                throw AgentFailure(message: "No live test destination")
            }
            let station = try await api.nearbyTransitStation(near: place.coordinate)
            let route = try await api.travelRouteOptions(from: station.coordinate, to: place.coordinate)
            print("TRANSPORT_LIVE_FROM=\(station.name) TO=\(place.name)")
            for option in route.modeOptions {
                print("MODE=\(option.mode.rawValue) AVAILABLE=\(option.isAvailable) METERS=\(option.distanceMeters ?? -1) SECONDS=\(option.durationSeconds ?? -1)")
            }
            let offered = TravelModePolicy.offered(route.modeOptions)
            guard !offered.isEmpty, offered.contains(where: { $0.mode.title == route.method }) else {
                throw AgentFailure(message: "No eligible recommended route")
            }
            if let walking = offered.first(where: { $0.mode == .walking }), walking.durationSeconds! < 480 {
                guard route.modeOptions.count == 1 else { throw AgentFailure(message: "Short walk queried unnecessary modes") }
            }
            print("TENCENT_TRANSPORT_POLICY_LIVE=passed OFFERED=\(offered.map { $0.mode.rawValue }.joined(separator: ","))")
            return
        }
        if CommandLine.arguments.contains("--flexible-live") {
            for count in CommandLine.arguments.contains("--five-only") ? [5] : [4, 5] {
                let intent = TripIntent(city: "杭州", scheduledStart: Date().addingTimeInterval(24 * 3600), timeWindow: "14:00到21:30", energy: "有精力，短体验且少步行", mood: "约会", note: "这次希望安排\(count)段短而集中的不同体验，含晚餐")
                let tools = TencentLiveTravelToolService(key: tencent)
                let weather = try await tools.resolveWeather(for: intent)
                let catalog = try await tools.availablePlaceHints(for: intent, inspiration: nil)
                var context = "仅从下面腾讯刚返回的清单选择完整地点名称。为本轮\(count)段体验检查生成\(count)段，各段三个不重复地点。第一站14:00，21:30前返程，给交通留够时间。\n" + catalog
                var complete = false
                for attempt in 0..<3 {
                    do {
                        var draft = try await DeepSeekResponsesPlanningAdapter(keyProvider: { deepseek }).makeDraft(for: intent, weather: weather, runID: UUID(), researchContext: context)
                        guard draft.slotCount == count else { throw AgentFailure(message: "本轮需要\(count)段验证") }
                        draft.requiresThematicMatch = true
                        let candidates = try await tools.resolveCandidates(for: draft)
                        let routes = try await tools.resolveConnections(for: draft)
                        draft = try TripSchedule.scheduled(draft, routes: routes.matrix)
                        let evidence = TravelEvidenceSummary(resolvedCandidateCount: candidates.resolvedCandidateCount, resolvedConnectionCount: routes.resolvedConnectionCount,
                            verifiedAddressCount: candidates.verifiedAddressCount, verifiedOpeningHoursCount: candidates.verifiedOpeningHoursCount,
                            unresolvedFactCount: candidates.unresolvedFactCount + routes.unresolvedFactCount, weather: weather,
                            candidateMetadata: candidates.metadata, routeMetadata: routes.metadata,
                            places: candidates.places, meetingPoint: candidates.meetingPoint, endingPoint: candidates.endingPoint, routeMatrix: routes.matrix)
                        let verified = try DeterministicTripVerifier(mode: .live).verify(draft: draft, evidence: evidence)
                        try JSONEncoder().encode(verified).write(to: URL(fileURLWithPath: "/tmp/DreamTravel-flexible-\(count)-live.json"))
                        print("FLEXIBLE_LIVE_SLOTS=\(count) CANDIDATES=\(verified.candidateCount) ROUTES=\(verified.connectionCount) ATTEMPTS=\(attempt + 1)")
                        for slot in verified.planningBrief.slots { print("START=\(slot.startMinute ?? -1) STAYS=\(slot.suggestedStayMinutes ?? []) DINING=\(slot.isDining ?? false)") }
                        complete = true; break
                    } catch {
                        if attempt == 2 { throw error }
                        context += "\n上一轮校验失败，改正后重排：\(error is AgentFailure ? (error as! AgentFailure).message : error.localizedDescription)。候选集中并适当留白。"
                    }
                }
                guard complete else { throw AgentFailure(message: "可变段数验证未完成") }
            }
            return
        }
        if CommandLine.arguments.contains("--plan-only") {
            let intent = TripIntent(city: "杭州", scheduledStart: Date().addingTimeInterval(24 * 3600), timeWindow: "下午到晚上", energy: "不要太累", mood: "轻松约会", note: "给每个候选安排建议停留时长")
            let weather = try await TencentLiveTravelToolService(key: tencent).resolveWeather(for: intent)
            let draft = try await DeepSeekResponsesPlanningAdapter(keyProvider: { deepseek }).makeDraft(for: intent, weather: weather, runID: UUID())
            try JSONEncoder().encode(draft).write(to: URL(fileURLWithPath: "/tmp/DreamTravel-duration-live.json"))
            for (index, slot) in draft.planningBrief.slots.enumerated() {
                guard let stays = slot.suggestedStayMinutes, stays.count == 3 else { throw AgentFailure(message: "Missing candidate durations") }
                print("SLOT=\(index + 1) SUGGESTED_STAY_MINUTES=\(stays)")
            }
            print("DEEPSEEK_STAY_SCHEMA_LIVE=passed; route feasibility is covered separately by deterministic tests")
            return
        }
        if CommandLine.arguments.contains("--place-only") {
            let matches = try await TencentTravelAPI(key: tencent).search(query: "新白鹿餐厅", city: "杭州")
            guard let match = matches.first else { throw AgentFailure(message: "No live restaurant") }
            let place = TravelPlaceEvidence(providerID: match.id, name: match.name, address: match.address, coordinate: match.coordinate, weeklyOpeningHours: "未知", openingHoursStatus: .unavailable, openingHoursCoverVisit: false, estimatedCostYuan: nil)
            let diagnosticTransport = TravelHTTPTransport { request in
                let response = try await TravelHTTPTransport.live.send(request)
                try response.data.write(to: URL(fileURLWithPath: "/tmp/DreamTravel-place-structured-response.json"))
                if let object = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] {
                    print("STRUCTURED HTTP=\(response.status) status=\(object["status"] ?? "nil") tokens=\(object["usage"] ?? "nil")")
                }
                return response
            }
            let research = DeepSeekPlaceResearch(search: DeepSeekWebSearchClient(keyProvider: { deepseek }), summarizer: DeepSeekResearchJSONClient(transport: diagnosticTransport, keyProvider: { deepseek }))
            let report = try await research.research(place: place, city: "杭州", isDining: true)
            try JSONEncoder().encode(report).write(to: URL(fileURLWithPath: "/tmp/DreamTravel-place-research-live.json"))
            print("PLACE_RESEARCH", match.name, "sources=\(report.sources.count) readable=\(report.readableCount) relevant=\(report.relevantReviewCount)")
            print(report.notice, report.perPersonText ?? "No verified price")
            print("RESERVATION=\(report.reservation?.status.rawValue ?? "unknown") ENTRIES=\(report.reservation?.entries.count ?? 0)")
            for entry in report.reservation?.entries ?? [] { print("ENTRY=\(entry.kind) \(entry.url)") }
            return
        }
        let tools = TencentLiveTravelToolService(key: tencent)
        let intent = TripIntent(city: "杭州", scheduledStart: Date().addingTimeInterval(24 * 3600), timeWindow: "下午到晚上", energy: "不要太累", mood: "浪漫", note: "优先有新意的室内文化体验，三套方案不同区域，不要全是咖啡店")
        let discovery = DeepSeekInspirationDiscovery(search: DeepSeekWebSearchClient(keyProvider: { deepseek }), summarizer: DeepSeekResearchJSONClient(keyProvider: { deepseek }))
        let runtime = AgentRuntime(model: DeepSeekResponsesPlanningAdapter(keyProvider: { deepseek }), tools: tools,
                                   verifier: DeterministicTripVerifier(mode: .live), discovery: discovery,
                                   independentPlans: true, library: ReferenceLibrary(fileURL: URL(fileURLWithPath: "/tmp/DreamTravel-live-references.json")),
                                   preferences: { ResearchPreferences(searches: true, usesLibrary: false, savesReferences: true, researchesPlaces: false) })
        for await event in await runtime.start(intent: intent) {
            switch event {
            case let .progress(_, message): print(message)
            case let .completed(result):
                let data = try JSONEncoder().encode(result)
                try data.write(to: URL(fileURLWithPath: "/tmp/DreamTravel-active-search-live.json"))
                print("LIVE_DISCOVERY_COMPLETE plans=\(result.independentPlans?.count ?? 0) sources=\(result.discovery?.sources.count ?? 0)")
                for plan in result.independentPlans ?? [] { print("PLAN", plan.planningBrief.variants[0].title, plan.places?.flatMap { $0.map(\.name) } ?? []) }
            case let .failed(failure): throw failure
            case .cancelled: throw CancellationError()
            }
        }
    }
}
