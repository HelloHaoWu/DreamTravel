import Foundation

struct MockPlanningModelAdapter: PlanningModelAdapter {
    func makeDraft(
        for intent: TripIntent,
        weather: WeatherEvidenceSummary,
        runID: UUID
    ) async throws -> TripDraftManifest {
        try await Task.sleep(for: .milliseconds(1_000))
        try Task.checkCancellation()

        let slotCount = 3
        let candidatesPerSlot = 3
        let candidateCount = slotCount * candidatesPerSlot
        let endpointConnections = candidatesPerSlot * 2
        let betweenSlotConnections = (slotCount - 1) * candidatesPerSlot * candidatesPerSlot
        let planningBrief = TripPlanningBrief(
            title: "慢慢逛",
            summary: "用三段松弛体验串起一个不用赶路的周末下午。",
            weatherStrategy: "根据天气减少连续户外停留，并为每一段保留室内选择。",
            variants: [
                TripPlanVariantBrief(title: "慢慢逛", subtitle: "轻松开场、一起体验和安静晚餐", selection: [0, 0, 0]),
                TripPlanVariantBrief(title: "吹吹风", subtitle: "湖边停留、室内互动和景观晚餐", selection: [1, 1, 1]),
                TripPlanVariantBrief(title: "雨天版", subtitle: "室内小展、手作活动和从容收尾", selection: [2, 2, 2])
            ],
            slots: [
                TripSlotSearchBrief(
                    title: "轻松开场",
                    purpose: "用安静、可坐下的体验进入状态。",
                    preferredEnvironment: .mixed,
                    searchQueries: ["安静街区", "湖景茶室", "室内小展"]
                ),
                TripSlotSearchBrief(
                    title: "一起做点什么",
                    purpose: "安排有互动、体力负担不高的共同体验。",
                    preferredEnvironment: .mixed,
                    searchQueries: ["周末市集", "手作体验", "室内活动"]
                ),
                TripSlotSearchBrief(
                    title: "安静收尾",
                    purpose: "用适合聊天的晚餐结束行程。",
                    preferredEnvironment: .indoor,
                    searchQueries: ["安静晚餐", "景观餐厅", "预约餐厅"]
                )
            ]
        )

        return TripDraftManifest(
            runID: runID,
            intent: intent,
            slotCount: slotCount,
            candidatesPerSlot: candidatesPerSlot,
            candidateCount: candidateCount,
            requiredConnectionCount: endpointConnections + betweenSlotConnections,
            planningBrief: planningBrief,
            modelProvider: "Mock Planning",
            weatherSnapshotAt: weather.metadata.fetchedAt,
            generatedAt: Date()
        )
    }
}

struct MockTravelToolService: TravelToolService {
    func resolveWeather(for intent: TripIntent) async throws -> WeatherEvidenceSummary {
        try await Task.sleep(for: .milliseconds(700))
        try Task.checkCancellation()

        let fetchedAt = Date()
        return WeatherEvidenceSummary(
            city: intent.city,
            forecastFor: intent.scheduledStart,
            condition: "多云，傍晚可能有短时阵雨",
            temperatureCelsius: 24,
            feelsLikeCelsius: 25,
            humidityPercent: 72,
            precipitationProbabilityPercent: 35,
            metadata: EvidenceMetadata(
                provider: "Mock Weather",
                origin: .mock,
                fetchedAt: fetchedAt,
                validUntil: fetchedAt.addingTimeInterval(60 * 60)
            ),
            sourceAttributions: []
        )
    }

    func resolveCandidates(for draft: TripDraftManifest) async throws -> CandidateEvidenceSummary {
        try await Task.sleep(for: .milliseconds(1_300))
        try Task.checkCancellation()

        return CandidateEvidenceSummary(
            resolvedCandidateCount: draft.candidateCount,
            verifiedAddressCount: draft.candidateCount,
            verifiedOpeningHoursCount: draft.candidateCount,
            unresolvedFactCount: 0,
            metadata: EvidenceMetadata(
                provider: "Mock Places",
                origin: .mock,
                fetchedAt: Date(),
                validUntil: Date().addingTimeInterval(60 * 60)
            ),
            places: nil,
            meetingPoint: nil,
            endingPoint: nil
        )
    }

    func resolveConnections(for draft: TripDraftManifest) async throws -> RouteEvidenceSummary {
        try await Task.sleep(for: .milliseconds(1_300))
        try Task.checkCancellation()

        return RouteEvidenceSummary(
            resolvedConnectionCount: draft.requiredConnectionCount,
            unresolvedFactCount: 0,
            metadata: EvidenceMetadata(
                provider: "Mock Routes",
                origin: .mock,
                fetchedAt: Date(),
                validUntil: Date().addingTimeInterval(15 * 60)
            ),
            matrix: nil
        )
    }
}
