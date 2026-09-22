import Foundation
import Combine

private actor TencentFixtureResponder {
    private var placeRequestCount = 0
    private(set) var routeRequestCount = 0

    func respond(_ request: URLRequest) throws -> (data: Data, status: Int) {
        guard let url = request.url else { throw TravelProviderError.invalidRequest }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        let keyword = items.first(where: { $0.name == "keyword" })?.value
        let type = items.first(where: { $0.name == "type" })?.value

        if url.path == "/ws/geocoder/v1" {
            return try json(["status": 0, "result": ["location": ["lat": 30.28, "lng": 120.15]]])
        }
        if url.path == "/ws/weather/v1", type == "hours" {
            return try json(["status": 0, "result": ["forecast_hours": [["infos": [[
                "hour": "2026-09-19 14:00:00",
                "info": ["weather": "多云", "temperature": 25]
            ]]]]]])
        }
        if url.path == "/ws/weather/v1", type == "future" {
            return try json(["status": 0, "result": ["forecast": [["infos": [[
                "date": "2026-09-19",
                "day": ["weather": "多云", "temperature": 26, "humidity": 72],
                "night": ["weather": "晴", "temperature": 21, "humidity": 61]
            ]]]]]])
        }
        if url.path == "/ws/place/v1/search" {
            if keyword == "地铁站" {
                return try json(["status": 0, "data": [[
                    "id": "tencent-station", "title": "测试地铁站", "address": "测试路 1 号",
                    "location": ["lat": 30.2805, "lng": 120.1505]
                ]]])
            }
            placeRequestCount += 1
            let index = placeRequestCount
            return try json(["status": 0, "data": [[
                "id": "tencent-poi-\(index)", "title": "腾讯候选 \(index)",
                "address": "测试路 \(index) 号",
                "location": ["lat": 30.28, "lng": 120.15 + Double(index) * 0.001]
            ]]])
        }
        if ["walking", "bicycling", "driving"].contains(url.lastPathComponent) {
            routeRequestCount += 1
            let duration = url.lastPathComponent == "walking" ? 10 : url.lastPathComponent == "bicycling" ? 4 : 6
            return try json(["status": 0, "result": ["routes": [[
                "distance": 900 + (routeRequestCount + 2) / 3, "duration": duration
            ]]]])
        }
        print("UNHANDLED_TENCENT_FIXTURE_REQUEST=\(url.path) type=\(type ?? "nil") keyword=\(keyword ?? "nil")")
        throw TravelProviderError.invalidRequest
    }

    private func json(_ object: Any) throws -> (data: Data, status: Int) {
        (try JSONSerialization.data(withJSONObject: object), 200)
    }
}

@main
struct TravelToolFixtureCheck {
    static func main() async throws {
        let start = ISO8601DateFormatter().date(from: "2026-09-19T06:00:00Z")!
        let intent = TripIntent(
            city: "杭州", scheduledStart: start, timeWindow: "周六下午到晚上",
            energy: "不要太累", mood: "浪漫", note: nil
        )

        let tencentResponder = TencentFixtureResponder()
        for (personal, expected) in [(" own-test ", "own-test"), ("", "dev-test")] {
            guard case let .tencentMap(key) = TravelProviderConfiguration.select(personalKey: personal, development: .tencentMap(key: "dev-test")) else { preconditionFailure("Missing provider") }
            precondition(key == expected)
        }
        precondition(TravelProviderConfiguration.select(personalKey: nil, development: nil) == nil)
        precondition(TravelProviderConfiguration.quickRegisterURL.absoluteString == "https://lbs.qq.com/dev/console/quick-register")
        print("PERSONAL_TENCENT_PRIORITY_REMOVAL_FALLBACK=passed")
        precondition(TencentSearchQueryPolicy.poiCategory(from: "西湖周边 甜品店 室内") == "甜品店")
        precondition(TencentSearchQueryPolicy.searchTerms(
            from: "杭州 小型 演出 约会",
            slotIndex: 1
        ) == ["杭州 小型 演出 约会", "演出", "休闲娱乐"])
        let tencentTransport = TravelHTTPTransport { request in
            try await tencentResponder.respond(request)
        }
        let tencentTools = TencentLiveTravelToolService(
            key: "fixture-only",
            transport: tencentTransport
        )
        let tencentWeather = try await tencentTools.resolveWeather(for: intent)
        precondition(tencentWeather.temperatureCelsius == 25)
        precondition(tencentWeather.humidityPercent == 72)
        precondition(tencentWeather.feelsLikeCelsius == nil)
        precondition(tencentWeather.precipitationProbabilityPercent == nil)

        let tencentDraft = try await MockPlanningModelAdapter().makeDraft(
            for: intent, weather: tencentWeather, runID: UUID()
        )
        let tencentCandidates = try await tencentTools.resolveCandidates(for: tencentDraft)
        let tencentRoutes = try await tencentTools.resolveConnections(for: tencentDraft)
        precondition(tencentCandidates.verifiedOpeningHoursCount == 0)
        precondition(tencentCandidates.places?.flatMap { $0 }.allSatisfy {
            $0.openingHoursStatus == .unavailable && !$0.openingHoursCoverVisit
        } == true)
        precondition(tencentRoutes.matrix?.meetingToFirst[0].durationSeconds == 600)
        let tencentRouteRequestCount = await tencentResponder.routeRequestCount
        precondition(tencentRouteRequestCount == 72)
        try await checkTransportFailures()

        let tencentEvidence = TravelEvidenceSummary(
            resolvedCandidateCount: tencentCandidates.resolvedCandidateCount,
            resolvedConnectionCount: tencentRoutes.resolvedConnectionCount,
            verifiedAddressCount: tencentCandidates.verifiedAddressCount,
            verifiedOpeningHoursCount: tencentCandidates.verifiedOpeningHoursCount,
            unresolvedFactCount: 0,
            weather: tencentWeather,
            candidateMetadata: tencentCandidates.metadata,
            routeMetadata: tencentRoutes.metadata,
            places: tencentCandidates.places,
            meetingPoint: tencentCandidates.meetingPoint,
            endingPoint: tencentCandidates.endingPoint,
            routeMatrix: tencentRoutes.matrix
        )
        let tencentVerified = try DeterministicTripVerifier(mode: .live).verify(
            draft: tencentDraft,
            evidence: tencentEvidence
        )
        func reshapeRoutes(_ value: Any, seconds: Int, keepAll: Bool) -> Any {
            if var object = value as? [String: Any] {
                if let modes = object["alternatives"] as? [[String: Any]], object["method"] != nil {
                    object["durationSeconds"] = seconds
                    object["alternatives"] = modes.filter { keepAll || $0["mode"] as? String == "walking" }.map { mode in
                        var result = mode
                        if mode["mode"] as? String == "walking" { result["durationSeconds"] = seconds }
                        return result
                    }
                    return object
                }
                return object.mapValues { reshapeRoutes($0, seconds: seconds, keepAll: keepAll) }
            }
            if let array = value as? [Any] { return array.map { reshapeRoutes($0, seconds: seconds, keepAll: keepAll) } }
            return value
        }
        let sourceEvidence = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tencentEvidence))
        for (seconds, keepAll, valid) in [(420, false, true), (480, false, false), (960, true, false)] {
            let reshaped = reshapeRoutes(sourceEvidence, seconds: seconds, keepAll: keepAll)
            let evidence = try JSONDecoder().decode(TravelEvidenceSummary.self, from: JSONSerialization.data(withJSONObject: reshaped))
            do {
                _ = try DeterministicTripVerifier(mode: .live).verify(draft: tencentDraft, evidence: evidence)
                precondition(valid, "Accepted invalid transport policy")
            } catch is AgentFailure { precondition(!valid, "Rejected short walk only publication") }
        }
        print("SHORT_WALK_ONLY_PUBLICATION_AND_LONG_WALK_DEFAULT_REJECTION=passed")
        precondition(tencentVerified.unverifiedOpeningHoursCount == 9)
        try await checkDiscoveryFixtures(template: tencentVerified)
        try await checkResearchRuntime(template: tencentVerified)
        try checkPlaceResearchFixtures()
        try checkReservationFixtures()
        var longStay = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tencentDraft)) as! [String: Any]
        var longBrief = longStay["planningBrief"] as! [String: Any]
        var longSlots = longBrief["slots"] as! [[String: Any]]
        longSlots[0]["suggestedStayMinutes"] = [140, 90, 90]
        longBrief["slots"] = longSlots; longStay["planningBrief"] = longBrief
        let impossibleStay = try JSONDecoder().decode(TripDraftManifest.self, from: JSONSerialization.data(withJSONObject: longStay))
        do {
            _ = try DeterministicTripVerifier(mode: .live).verify(draft: impossibleStay, evidence: tencentEvidence)
            preconditionFailure("Accepted a stay that overlaps the next stop")
        } catch let failure as AgentFailure { precondition(failure.message.contains("停留时间")) }
        await MainActor.run {
            let app = MobileAppModel(); app.apply(result: tencentVerified)
            precondition(app.stops[0].duration == "建议 90 分钟")
            precondition(app.stops[0].plannedFinish == "15:30")
        }
        try checkTransportSelection(summary: tencentVerified)
        print("STAY_TIME_ROUTE_BUFFER_AND_LEGACY_DISPLAY=passed")
        try await checkFlexiblePlans(intent: intent, weather: tencentWeather, template: tencentDraft)
        // Reject partial, stale, wrong-day and impossible-route results before UI publication.
        let encoded = try JSONEncoder().encode(tencentEvidence)
        for mutation in ["missingRoute", "negativeRoute", "lateRoute", "duplicateMode", "negativeAlternative", "wrongDay", "expired", "mock", "missingAddress"] {
            var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            if ["missingRoute", "negativeRoute", "lateRoute", "duplicateMode", "negativeAlternative"].contains(mutation) {
                var matrix = object["routeMatrix"] as! [String: Any]
                var row = matrix["meetingToFirst"] as! [[String: Any]]
                if mutation == "missingRoute" { row.removeLast() }
                else if mutation == "duplicateMode" || mutation == "negativeAlternative" {
                    var modes = row[0]["alternatives"] as! [[String: Any]]
                    if mutation == "duplicateMode" { modes[1]["mode"] = "walking" }
                    else { modes[1]["durationSeconds"] = -1 }
                    row[0]["alternatives"] = modes
                }
                else { row[0]["durationSeconds"] = mutation == "negativeRoute" ? -1 : 2_500 }
                matrix["meetingToFirst"] = row
                object["routeMatrix"] = matrix
            } else if mutation == "wrongDay" {
                var weather = object["weather"] as! [String: Any]
                weather["forecastFor"] = start.addingTimeInterval(-86_400).timeIntervalSinceReferenceDate
                object["weather"] = weather
            } else if mutation == "missingAddress" {
                object["verifiedAddressCount"] = 8
            } else {
                var metadata = object["candidateMetadata"] as! [String: Any]
                if mutation == "mock" { metadata["origin"] = "mock" }
                else { metadata["validUntil"] = Date().addingTimeInterval(-60).timeIntervalSinceReferenceDate }
                object["candidateMetadata"] = metadata
            }
            let bad = try JSONDecoder().decode(TravelEvidenceSummary.self, from: JSONSerialization.data(withJSONObject: object))
            do {
                _ = try DeterministicTripVerifier(mode: .live).verify(draft: tencentDraft, evidence: bad)
                fatalError("Accepted invalid evidence: \(mutation)")
            } catch is AgentFailure { print("REJECTED_\(mutation)=yes") }
        }
        try await checkAtomicPublication(
            draft: tencentDraft, weather: tencentWeather,
            candidates: tencentCandidates, routes: tencentRoutes
        )
        try await checkViewModelRetention(
            draft: tencentDraft, weather: tencentWeather,
            candidates: tencentCandidates, routes: tencentRoutes
        )
        print("TENCENT_FIXTURE_LIVE_PIPELINE=passed")
        print("FIXTURE_LIVE_PIPELINE=passed")
        print("PLACES=9 ROUTES=24 WEATHER_HUMIDITY=72")
    }
}

private func checkTransportFailures() async throws {
    let point = TravelCoordinate(longitude: 120.15, latitude: 30.28)
    for unavailable in [Set(["bicycling"]), Set(["walking"]), Set(["walking", "bicycling", "driving"])] {
        let api = TencentTravelAPI(key: "fixture-only", transport: TravelHTTPTransport { request in
            let mode = request.url!.lastPathComponent
            precondition(["walking", "bicycling", "driving"].contains(mode))
            let response: [String: Any] = unavailable.contains(mode) ? ["status": 347, "message": "unavailable"] :
                ["status": 0, "result": ["routes": [["distance": 1500, "duration": mode == "driving" ? 6 : 12]]]]
            return (try JSONSerialization.data(withJSONObject: response), 200)
        })
        do {
            let route = try await api.travelRouteOptions(from: point, to: point)
            precondition(unavailable.count < 3)
            precondition(route.modeOptions.count == 3)
            for option in route.modeOptions {
                precondition(option.isAvailable == !unavailable.contains(option.mode.rawValue))
                if !option.isAvailable { precondition(option.durationSeconds == nil && option.distanceMeters == nil) }
            }
            precondition(route.durationSeconds == (unavailable.contains("walking") ? 360 : 720))
        } catch is TravelProviderError { precondition(unavailable.count == 3) }
    }
    let cancelled = TencentTravelAPI(key: "fixture-only", transport: TravelHTTPTransport { _ in throw CancellationError() })
    do { _ = try await cancelled.travelRouteOptions(from: point, to: point); preconditionFailure("Cancellation swallowed") }
    catch is CancellationError {}
    let legacy = try JSONDecoder().decode(TravelRouteEvidence.self, from: Data(#"{"distanceMeters":800,"durationSeconds":300,"method":"打车"}"#.utf8))
    precondition(legacy.modeOptions.count == 1 && legacy.modeOptions[0].mode == .driving)
    let fractional = TencentTravelAPI(key: "fixture-only", transport: TravelHTTPTransport { _ in
        (Data(#"{"status":0,"result":{"routes":[{"distance":50,"duration":1.51}]}}"#.utf8), 200)
    })
    let rounded = try await fractional.travelRouteOptions(from: point, to: point)
    precondition(rounded.modeOptions.allSatisfy { $0.durationSeconds == 91 && $0.timeText == "约 2 分钟" })
    for seconds in [0, 479, 480, 900, 901] {
        let recorder = TransportRequestRecorder()
        let api = TencentTravelAPI(key: "fixture-only", transport: TravelHTTPTransport { request in
            await recorder.record(request.url!.lastPathComponent)
            return (try JSONSerialization.data(withJSONObject: ["status": 0, "result": ["routes": [[
                "distance": 800, "duration": request.url!.lastPathComponent == "walking" ? Double(seconds) / 60 : 5
            ]]]]), 200)
        })
        let route = try await api.travelRouteOptions(from: point, to: point)
        let offered = TravelModePolicy.offered(route.modeOptions)
        let requests = await recorder.modes
        precondition(requests == (seconds < 480 ? ["walking"] : ["walking", "bicycling", "driving"]))
        precondition(offered.count == (seconds < 480 ? 1 : seconds <= 900 ? 3 : 2))
        precondition(route.method == (seconds <= 900 ? "步行" : "驾车"))
        precondition(offered.contains { $0.mode == .walking } == (seconds <= 900))
        if seconds == 0 { precondition(offered[0].timeText == "不足 1 分钟") }
    }
    let noEligible = TencentTravelAPI(key: "fixture-only", transport: TravelHTTPTransport { request in
        let object: [String: Any] = request.url!.lastPathComponent == "walking" ?
            ["status": 0, "result": ["routes": [["distance": 2000, "duration": 16]]]] : ["status": 347]
        return (try JSONSerialization.data(withJSONObject: object), 200)
    })
    do { _ = try await noEligible.travelRouteOptions(from: point, to: point); preconditionFailure("Long walk fallback") }
    catch is TravelProviderError {}
    print("TRANSPORT_8_15_MIN_BOUNDARIES_SHORT_WALK_ONLY_REQUEST_LONG_WALK_EXCLUDED=passed")
    print("MODE_ENDPOINTS_MINUTES_TO_SECONDS_PARTIAL_FAILURE_CANCELLATION_LEGACY=passed")
}

private actor TransportRequestRecorder {
    private(set) var modes: [String] = []
    func record(_ mode: String) { modes.append(mode) }
}

@MainActor
private func checkTransportSelection(summary: VerifiedTripSummary) throws {
    // A deliberately slow bicycle route exposes a conflict without altering the published schedule.
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(summary)) as! [String: Any]
    var matrix = json["routeMatrix"] as! [String: Any]
    var between = matrix["betweenSlots"] as! [[[[String: Any]]]]
    var alternatives = between[0][0][0]["alternatives"] as! [[String: Any]]
    alternatives[1]["durationSeconds"] = 12_000
    between[0][0][0]["alternatives"] = alternatives
    matrix["betweenSlots"] = between; json["routeMatrix"] = matrix
    let slow = try JSONDecoder().decode(VerifiedTripSummary.self, from: JSONSerialization.data(withJSONObject: json))
    var bundle = slow; bundle.independentPlans = [slow, summary, summary]
    let app = MobileAppModel(); app.apply(result: bundle)
    let times = app.stops.map(\.time)
    precondition(app.selectedTransport(at: 1)?.mode == .walking)
    app.selectTransport(.bicycling, at: 1)
    precondition(app.selectedTransport(at: 1)?.durationSeconds == 12_000)
    precondition(app.transportDelayMinutes(at: 1) > 0 && app.transportDelayMinutes(at: 2) > 0)
    precondition(app.hasTransportConflict && app.connection(at: 1).needsVerification)
    precondition(app.stops.map(\.time) == times)
    app.selectStop(at: 0, choice: 1)
    precondition(app.selectedTransport(at: 1)?.mode == .walking && !app.hasTransportConflict)
    app.selectStop(at: 0, choice: 0)
    precondition(app.selectedTransport(at: 1)?.mode == .bicycling)
    app.selectPlan(1)
    precondition(app.selectedTransport(at: 1)?.mode == .walking)
    app.selectPlan(0)
    precondition(app.selectedTransport(at: 1)?.mode == .bicycling)
    app.selectTransport(.driving, at: 1)
    precondition(app.selectedTransport(at: 1)?.durationSeconds == 360 && !app.hasTransportConflict)
    let builds = app.presentationBuildCount
    for index in 0..<1000 { app.selectTransport(TravelMode.allCases[index % 3], at: 1) }
    precondition(app.presentationBuildCount == builds)
    app.apply(result: bundle)
    precondition(app.selectedTransport(at: 1)?.mode == .walking)
    let demo = MobileAppModel()
    demo.selectTransport(.bicycling, at: 1)
    precondition(demo.selectedTransport(at: 1) == nil && !demo.hasTransportConflict)
    print("TRANSPORT_SWITCH_CACHED_EDGE_PLAN_MEMORY_LATE_PROPAGATION_RESET_DEMO=passed")
}

private func checkFlexiblePlans(intent: TripIntent, weather: WeatherEvidenceSummary, template: TripDraftManifest) async throws {
    var summaries: [VerifiedTripSummary] = []
    for count in 3...5 {
        let slots = (0..<count).map { index in
            TripSlotSearchBrief(title: "体验\(index)", purpose: "短时文化体验", preferredEnvironment: .indoor,
                searchQueries: (0..<3).map { "独立地点\(count)-\(index)-\($0)" }, suggestedStayMinutes: [40, 45, 50],
                startMinute: 840 + index * 90, isDining: index == count - 2)
        }
        let brief = TripPlanningBrief(title: "\(count)站行程", summary: "可变长度", weatherStrategy: "室内优先",
            variants: (0..<3).map { TripPlanVariantBrief(title: "方案\($0)", subtitle: "轻松", selection: Array(repeating: $0, count: count)) }, slots: slots)
        let draft = TripDraftManifest(runID: UUID(), intent: intent, slotCount: count, candidatesPerSlot: 3,
            candidateCount: count * 3, requiredConnectionCount: 6 + (count - 1) * 9,
            planningBrief: brief, modelProvider: "Fixture", weatherSnapshotAt: weather.metadata.fetchedAt, generatedAt: Date())
        let responder = TencentFixtureResponder()
        let tools = TencentLiveTravelToolService(key: "fixture-only", transport: TravelHTTPTransport { try await responder.respond($0) })
        let candidates = try await tools.resolveCandidates(for: draft)
        let routes = try await tools.resolveConnections(for: draft)
        precondition(candidates.resolvedCandidateCount == count * 3)
        let routeCalls = await responder.routeRequestCount
        precondition(routeCalls == (6 + (count - 1) * 9) * 3)
        let evidence = TravelEvidenceSummary(resolvedCandidateCount: candidates.resolvedCandidateCount,
            resolvedConnectionCount: routes.resolvedConnectionCount, verifiedAddressCount: candidates.verifiedAddressCount,
            verifiedOpeningHoursCount: 0, unresolvedFactCount: 0, weather: weather,
            candidateMetadata: candidates.metadata, routeMetadata: routes.metadata,
            places: candidates.places, meetingPoint: candidates.meetingPoint, endingPoint: candidates.endingPoint, routeMatrix: routes.matrix)
        var verified = try DeterministicTripVerifier(mode: .live).verify(draft: draft, evidence: evidence)
        let scheduled = try TripSchedule.scheduled(draft, routes: routes.matrix)
        _ = try DeterministicTripVerifier(mode: .live).verify(draft: scheduled, evidence: evidence)
        precondition(scheduled.planningBrief.slots.map(\.suggestedStayMinutes) == draft.planningBrief.slots.map(\.suggestedStayMinutes))
        let meal = count - 2
        precondition(TripSchedule.start(scheduled.planningBrief, slot: meal) >= TripSchedule.start(draft.planningBrief, slot: meal))
        // Prefix fixture IDs to make independently generated pools distinct.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(verified)) as! [String: Any]
        json["places"] = (json["places"] as! [[[String: Any]]]).map { row in row.map { source in
            var place = source; place["providerID"] = "\(count)-\(source["providerID"]!)"; return place
        } }
        verified = try JSONDecoder().decode(VerifiedTripSummary.self, from: JSONSerialization.data(withJSONObject: json))
        summaries.append(verified)
        let matrix = routes.matrix!
        // Exhaustively verify each possible selection (27, 81, 243).
        let combinations = Int(pow(3.0, Double(count)))
        for combination in 0..<combinations {
            var remainder = combination
            let selection = (0..<count).map { _ in let index = remainder % 3; remainder /= 3; return index }
            for edge in 0...count {
                let expected: Int
                if edge == 0 { expected = selection[0] + 1 }
                else if edge == count { expected = 3 + (count - 1) * 9 + selection[count - 1] + 1 }
                else { expected = 3 + (edge - 1) * 9 + selection[edge - 1] * 3 + selection[edge] + 1 }
                precondition(matrix.route(at: edge, selections: selection)?.distanceMeters == 900 + expected)
            }
        }
        for mutation in ["missing-edge", "bad-last-stay", "reversed-time"] {
            var brokenDraft = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as! [String: Any]
            var brokenEvidence = try JSONSerialization.jsonObject(with: JSONEncoder().encode(evidence)) as! [String: Any]
            if mutation == "missing-edge" {
                var matrix = brokenEvidence["routeMatrix"] as! [String: Any]
                var between = matrix["betweenSlots"] as! [Any]; between.removeLast()
                matrix["betweenSlots"] = between; brokenEvidence["routeMatrix"] = matrix
            } else {
                var brief = brokenDraft["planningBrief"] as! [String: Any]
                var rows = brief["slots"] as! [[String: Any]]
                if mutation == "bad-last-stay" { rows[count - 1]["startMinute"] = 1270 }
                else { rows[1]["startMinute"] = 830 }
                brief["slots"] = rows; brokenDraft["planningBrief"] = brief
            }
            let badDraft = try JSONDecoder().decode(TripDraftManifest.self, from: JSONSerialization.data(withJSONObject: brokenDraft))
            let badEvidence = try JSONDecoder().decode(TravelEvidenceSummary.self, from: JSONSerialization.data(withJSONObject: brokenEvidence))
            do { _ = try DeterministicTripVerifier(mode: .live).verify(draft: badDraft, evidence: badEvidence); preconditionFailure("Accepted \(mutation)") }
            catch is AgentFailure {}
        }
        print("FLEXIBLE_SLOTS=\(count) CANDIDATES=\(count * 3) EDGES=\(routes.resolvedConnectionCount) MODE_REQUESTS=\(routeCalls) COMBINATIONS=\(combinations) REJECTION_CHECKS=passed")
    }
    try AgentRuntime.validateDistinct(summaries)
    var bundle = summaries[0]; bundle.independentPlans = summaries
    let complete = bundle
    await MainActor.run {
        let app = MobileAppModel(); app.apply(result: complete)
        let builds = app.presentationBuildCount
        for index in 0..<3 {
            app.selectPlan(index); precondition(app.stops.count == index + 3)
            app.selectStop(at: index + 2, choice: 2)
        }
        for index in 0..<3 { app.selectPlan(index); precondition(app.selections.last == 2) }
        var durations: [Double] = []
        var publications = 0
        let subscription = app.objectWillChange.sink { publications += 1 }
        for index in 0..<1000 {
            let begin = ContinuousClock.now
            app.selectPlan(index % 3)
            let elapsed = begin.duration(to: .now).components
            durations.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
        }
        precondition(app.presentationBuildCount == builds, "Switch rebuilt presentation data")
        precondition(publications == 1000, "Switch must publish once")
        app.selectPlan(app.selectedPlanIndex)
        precondition(publications == 1000, "Reselecting current plan should do no work")
        subscription.cancel()
        durations.sort()
        print(String(format: "PLAN_SWITCH_1000_CPU_P95_MS=%.4f MAX_MS=%.4f CACHE_REBUILDS=0 PUBLICATIONS=1000 (model only, not frame rate)", durations[950], durations.last!))
    }
}

// Deliberately ignores cancellation while paused to model a late provider response.
private actor PausedTravelTools: TravelToolService {
    let weather: WeatherEvidenceSummary
    let candidates: CandidateEvidenceSummary
    let routes: RouteEvidenceSummary
    private(set) var waiting = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var shouldFail = false

    init(weather: WeatherEvidenceSummary, candidates: CandidateEvidenceSummary, routes: RouteEvidenceSummary) {
        self.weather = weather
        self.candidates = candidates
        self.routes = routes
    }
    func resolveWeather(for intent: TripIntent) async throws -> WeatherEvidenceSummary {
        WeatherEvidenceSummary(
            city: weather.city, forecastFor: intent.scheduledStart,
            condition: weather.condition, temperatureCelsius: weather.temperatureCelsius,
            feelsLikeCelsius: weather.feelsLikeCelsius, humidityPercent: weather.humidityPercent,
            precipitationProbabilityPercent: weather.precipitationProbabilityPercent,
            metadata: weather.metadata, sourceAttributions: weather.sourceAttributions
        )
    }
    func resolveCandidates(for draft: TripDraftManifest) async throws -> CandidateEvidenceSummary { candidates }
    func resolveConnections(for draft: TripDraftManifest) async throws -> RouteEvidenceSummary {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            waiting = true
        }
        if shouldFail { throw TravelProviderError.unavailable("测试路线") }
        return routes
    }
    func release(fail: Bool = false) {
        shouldFail = fail
        waiting = false
        continuation?.resume()
        continuation = nil
    }
}

private struct FixedPlanningAdapter: PlanningModelAdapter {
    let template: TripDraftManifest
    func makeDraft(for intent: TripIntent, weather: WeatherEvidenceSummary, runID: UUID) async throws -> TripDraftManifest {
        TripDraftManifest(
            runID: runID, intent: intent, slotCount: 3, candidatesPerSlot: 3,
            candidateCount: 9, requiredConnectionCount: 24,
            planningBrief: template.planningBrief, modelProvider: "Fixture",
            weatherSnapshotAt: weather.metadata.fetchedAt, generatedAt: Date()
        )
    }
}

private actor EventRecorder {
    private(set) var events: [AgentEvent] = []
    func append(_ event: AgentEvent) { events.append(event) }
    var completed: [VerifiedTripSummary] {
        events.compactMap { if case let .completed(result) = $0 { result } else { nil } }
    }
}

private func checkAtomicPublication(
    draft: TripDraftManifest, weather: WeatherEvidenceSummary,
    candidates: CandidateEvidenceSummary, routes: RouteEvidenceSummary
) async throws {
    for outcome in ["success", "failure", "cancelled"] {
        let tools = PausedTravelTools(weather: weather, candidates: candidates, routes: routes)
        let runtime = AgentRuntime(
            model: FixedPlanningAdapter(template: draft), tools: tools,
            verifier: DeterministicTripVerifier(mode: .live)
        )
        let recorder = EventRecorder()
        let stream = await runtime.start(intent: draft.intent)
        let consumer = Task { for await event in stream { await recorder.append(event) } }
        for _ in 0..<500 {
            if await tools.waiting { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let waiting = await tools.waiting
        precondition(waiting, "Runtime did not reach routes")
        let before = await recorder.completed
        precondition(before.isEmpty, "Published before all routes were available")
        if outcome == "cancelled" { await runtime.cancel() }
        await tools.release(fail: outcome == "failure")
        await consumer.value
        let completed = await recorder.completed
        let events = await recorder.events
        precondition(completed.count == (outcome == "success" ? 1 : 0))
        if outcome == "success" {
            precondition(completed[0].places?.flatMap { $0 }.count == 9)
            precondition(completed[0].connectionCount == 24)
            // Every combination reads the already published matrix synchronously.
            let app = await MainActor.run { MobileAppModel() }
            await MainActor.run {
                app.apply(result: completed[0])
                for first in 0..<3 {
                    for second in 0..<3 {
                        for third in 0..<3 {
                            app.selectStop(at: 0, choice: first)
                            app.selectStop(at: 1, choice: second)
                            app.selectStop(at: 2, choice: third)
                            precondition(app.stops.count == 3)
                            for edge in 0..<4 {
                                precondition(app.liveRouteMatrix?.route(at: edge, selections: app.selections) != nil)
                            }
                        }
                    }
                }
            }
        } else if outcome == "failure" {
            precondition(events.contains { if case .failed = $0 { true } else { false } })
        } else {
            precondition(events.contains(.cancelled))
        }
        print("ATOMIC_PUBLICATION_\(outcome.uppercased())=passed")
    }
}

@MainActor
private func checkViewModelRetention(
    draft: TripDraftManifest, weather: WeatherEvidenceSummary,
    candidates: CandidateEvidenceSummary, routes: RouteEvidenceSummary
) async throws {
    let tools = PausedTravelTools(weather: weather, candidates: candidates, routes: routes)
    let runtime = AgentRuntime(
        model: FixedPlanningAdapter(template: draft), tools: tools,
        verifier: DeterministicTripVerifier(mode: .live)
    )
    let viewModel = TripPlanningViewModel(runtime: runtime)
    for outcome in ["success", "failure", "cancelled", "success"] {
        let previous = viewModel.lastResult
        let previousCount = viewModel.completedRunCount
        viewModel.start(city: "杭州", note: "")
        for _ in 0..<500 {
            if await tools.waiting { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let waiting = await tools.waiting
        precondition(waiting)
        precondition(viewModel.lastResult == previous)
        precondition(viewModel.completedRunCount == previousCount)
        if outcome == "cancelled" { viewModel.cancel() }
        await tools.release(fail: outcome == "failure")
        for _ in 0..<500 {
            if !viewModel.isRunning { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(!viewModel.isRunning)
        if outcome == "success" {
            precondition(viewModel.completedRunCount == previousCount + 1)
            precondition(viewModel.lastResult?.runID != previous?.runID)
        } else {
            precondition(viewModel.completedRunCount == previousCount)
            precondition(viewModel.lastResult == previous)
        }
    }
    print("VIEW_MODEL_RETAIN_RETRY_CANCEL=passed")
}
