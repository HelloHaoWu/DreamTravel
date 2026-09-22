import Foundation

enum VerificationMode: String, Codable, Equatable, Sendable {
    case demo
    case live
}

struct DeterministicTripVerifier: TripVerifying {
    let mode: VerificationMode
    let now: @Sendable () -> Date

    init(mode: VerificationMode = .demo, now: @escaping @Sendable () -> Date = { Date() }) {
        self.mode = mode
        self.now = now
    }

    func verify(
        draft: TripDraftManifest,
        evidence: TravelEvidenceSummary
    ) throws -> VerifiedTripSummary {
        guard !draft.intent.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentFailure(message: "还不知道你们在哪见面。")
        }
        guard (3...5).contains(draft.slotCount), draft.candidatesPerSlot == 3,
              draft.candidateCount == draft.slotCount * 3,
              draft.requiredConnectionCount == TripSchedule.connectionCount(slots: draft.slotCount) else {
            throw AgentFailure(message: "行程需要三至五段体验，每段三个备选，并接好全部路线。")
        }
        guard draft.candidateCount == evidence.resolvedCandidateCount else {
            throw AgentFailure(message: "还有候选地点没有完成核验。")
        }
        guard draft.requiredConnectionCount == evidence.resolvedConnectionCount else {
            throw AgentFailure(message: "候选之间的路线还没有全部接好。")
        }
        guard draft.planningBrief.variants.count == 3,
              draft.planningBrief.variants.allSatisfy({ variant in
                  variant.selection.count == draft.slotCount &&
                  variant.selection.allSatisfy({ (0..<draft.candidatesPerSlot).contains($0) })
              }),
              draft.planningBrief.slots.count == draft.slotCount,
              draft.planningBrief.slots.allSatisfy({ $0.searchQueries.count == draft.candidatesPerSlot }) else {
            throw AgentFailure(message: "模型没有为每个时间段生成完整的三个候选方向。")
        }
        guard evidence.unresolvedFactCount == 0 else {
            throw AgentFailure(message: "还有影响出发的事实没有确认。")
        }

        guard evidence.verifiedAddressCount == draft.candidateCount else {
            throw AgentFailure(message: "还有地点没有获得地图 API 返回的地址。")
        }
        guard Calendar.current.isDate(
            evidence.weather.forecastFor,
            inSameDayAs: draft.intent.scheduledStart
        ) else {
            throw AgentFailure(message: "天气数据不是行程当天的数据。")
        }

        let currentTime = now()
        let metadata = [
            evidence.weather.metadata,
            evidence.candidateMetadata,
            evidence.routeMetadata
        ]
        guard metadata.allSatisfy({ $0.fetchedAt <= currentTime && $0.validUntil > currentTime }) else {
            throw AgentFailure(message: "地点、路线或天气数据已经过期，需要重新查询。")
        }
        if mode == .live,
           metadata.contains(where: { $0.origin != .liveAPI }) {
            throw AgentFailure(message: "真实行程不能使用演示数据发布。")
        }

        if mode == .live {
            guard let places = evidence.places,
                  places.count == draft.slotCount,
                  places.allSatisfy({ $0.count == draft.candidatesPerSlot }),
                  places.flatMap({ $0 }).allSatisfy({
                      !$0.providerID.isEmpty && !$0.address.isEmpty &&
                      ($0.openingHoursStatus == .unavailable || $0.openingHoursCoverVisit)
                  }),
                  let matrix = evidence.routeMatrix,
                  matrix.meetingToFirst.count == draft.candidatesPerSlot,
                  matrix.betweenSlots.count == draft.slotCount - 1,
                  matrix.betweenSlots.allSatisfy({ row in
                      row.count == draft.candidatesPerSlot &&
                      row.allSatisfy({ $0.count == draft.candidatesPerSlot })
                  }),
                  matrix.lastToEnding.count == draft.candidatesPerSlot,
                  evidence.meetingPoint != nil,
                  evidence.endingPoint != nil else {
                throw AgentFailure(message: "真实地点或候选路线矩阵不完整。")
            }
            let verifiedHours = places.flatMap { $0 }.filter {
                $0.openingHoursStatus == .verified && $0.openingHoursCoverVisit
            }.count
            guard verifiedHours == evidence.verifiedOpeningHoursCount else {
                throw AgentFailure(message: "营业时间证据数量与地点状态不一致。")
            }
            let allRoutes = matrix.meetingToFirst +
                matrix.betweenSlots.flatMap { $0.flatMap { $0 } } +
                matrix.lastToEnding
            for route in allRoutes {
                guard let alternatives = route.alternatives else { continue } // Legacy snapshots.
                let shortWalkOnly = alternatives.count == 1 && alternatives[0].mode == .walking &&
                    alternatives[0].isAvailable && alternatives[0].durationSeconds! < 8 * 60
                guard (shortWalkOnly || alternatives.count == 3), Set(alternatives.map(\.mode)).count == alternatives.count,
                      alternatives.allSatisfy({ option in
                          option.isAvailable || (option.distanceMeters == nil && option.durationSeconds == nil && option.unavailableReason?.isEmpty == false)
                      }),
                      TravelModePolicy.offered(alternatives).contains(where: {
                          $0.isAvailable && $0.mode.title == route.method &&
                          $0.distanceMeters == route.distanceMeters && $0.durationSeconds == route.durationSeconds
                      }) else {
                    throw AgentFailure(message: "交通方式数据不完整或默认耗时不一致，不能发布。")
                }
            }
            guard allRoutes.count == draft.requiredConnectionCount,
                  allRoutes.allSatisfy({ $0.durationSeconds >= 0 && $0.distanceMeters >= 0 && ($0.method != "步行" || $0.durationSeconds <= 15 * 60) }),
                  matrix.meetingToFirst.allSatisfy({ $0.durationSeconds <= 20 * 60 }),
                  matrix.betweenSlots.flatMap({ $0.flatMap { $0 } }).allSatisfy({ $0.durationSeconds <= 50 * 60 }),
                  matrix.lastToEnding.allSatisfy({ $0.durationSeconds <= 60 * 60 }) else {
                throw AgentFailure(message: "有备选组合赶不上下一站，不能发布为完整实时行程。")
            }
            let starts = draft.planningBrief.slots.indices.map { TripSchedule.start(draft.planningBrief, slot: $0) }
            guard starts.first == 840, starts.allSatisfy({ (840..<TripSchedule.ending).contains($0) }),
                  zip(starts, starts.dropFirst()).allSatisfy({ $0 < $1 }) else {
                throw AgentFailure(message: "行程时间顺序不完整，或赶不上当天返程，需要减少站数或重新安排。")
            }
            for slot in 0..<draft.slotCount {
                if let durations = draft.planningBrief.slots[slot].suggestedStayMinutes,
                   durations.count != 3 || !durations.allSatisfy({ (20...180).contains($0) }) {
                    throw AgentFailure(message: "候选的建议停留时间不完整，需要重新安排。")
                }
                for candidate in 0..<3 {
                    let finish = (starts[slot] + TripSchedule.stay(draft.planningBrief, slot: slot, candidate: candidate) + TripSchedule.bufferMinutes) * 60
                    let isLast = slot == draft.slotCount - 1
                    let connections = isLast ? [matrix.lastToEnding[candidate]] : matrix.betweenSlots[slot][candidate]
                    let deadline = (isLast ? TripSchedule.ending : starts[slot + 1]) * 60
                    guard connections.allSatisfy({ finish + $0.durationSeconds <= deadline }) else {
                        let latest = TripSchedule.time(Int(ceil(Double(finish + (connections.map(\.durationSeconds).max() ?? 0)) / 60)))
                        throw AgentFailure(message: "第\(slot + 1)段建议停留时间加上交通和缓冲后，最晚\(latest)到达，赶不上\(TripSchedule.time(deadline / 60))的安排。请减少站数或重新选择附近体验。")
                    }
                }
            }
        }

        let providers = metadata.map(\.provider)

        var summary = VerifiedTripSummary(
            runID: draft.runID,
            city: draft.intent.city,
            candidateCount: evidence.resolvedCandidateCount,
            connectionCount: evidence.resolvedConnectionCount,
            unverifiedOpeningHoursCount: max(
                0,
                evidence.resolvedCandidateCount - evidence.verifiedOpeningHoursCount
            ),
            planningBrief: draft.planningBrief,
            modelProvider: draft.modelProvider,
            weather: evidence.weather,
            isLive: mode == .live,
            evidenceProviders: Array(Set(providers)).sorted(),
            verifiedAt: currentTime,
            places: evidence.places,
            meetingPoint: evidence.meetingPoint,
            endingPoint: evidence.endingPoint,
            routeMatrix: evidence.routeMatrix
        )
        summary.evidenceValidUntil = metadata.map(\.validUntil).min()
        return summary
    }
}
