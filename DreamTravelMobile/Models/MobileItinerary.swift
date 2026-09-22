import Foundation
import SwiftUI
import os

struct MobileStop: Identifiable, Hashable {
    let id: String
    let time: String
    let title: String
    let place: String
    let city: String
    let address: String?
    let summary: String
    let duration: String
    let reason: String
    let price: String
    var openingHours: String? = nil
    var openingHoursVerified: Bool = false
    var evidenceSource: String? = nil
    var gcj02Coordinate: TravelCoordinate? = nil
    var research: PlaceResearchReport? = nil
    var suggestedStayMinutes: Int? = nil
    var plannedFinish: String? = nil

    var searchText: String {
        [place, address].compactMap { $0 }.joined(separator: " ")
    }
}

struct MobilePlan: Identifiable, Hashable {
    let id: Int
    let title: String
    let subtitle: String
    let selection: [Int]
    let meetingTime: String
    let meetingPlace: String
    let meetingNote: String
    let endingTime: String
    let endingTitle: String
    let endingNote: String
    let validatedRoutes: MobileValidatedRouteMatrix
}

/// 时间线中两个节点之间的交通连接段。
/// 正式 Agent 接入后将补充起终点 POI ID、距离、出发到达时间、路线来源与查询时间。
struct MobileJourneyConnection: Hashable {
    let symbol: String
    let title: String
    let detail: String
    let needsVerification: Bool
}

/// 一次生成阶段完成核验的候选连接矩阵。
/// 三个时段、每段三个候选只需要 3 + 9 + 9 + 3 = 24 条相邻连接，
/// 用户之后任意组合三选一时都能直接读取，不需要在选择后再次等待 Agent。
struct MobileValidatedRouteMatrix: Hashable {
    let meetingToFirstMinutes: [Int]
    let betweenStopMinutes: [[[Int]]]
    let lastToEndingMinutes: [Int]

    static func demo(seed: Int) -> MobileValidatedRouteMatrix {
        let meeting = [18, 23, 27].map { $0 + seed }
        let between = (0..<2).map { leg in
            (0..<3).map { from in
                (0..<3).map { to in
                    16 + seed + leg * 5 + abs(from - to) * 6 + from * 2 + to
                }
            }
        }
        let ending = [28, 24, 21].map { $0 + seed }
        return MobileValidatedRouteMatrix(
            meetingToFirstMinutes: meeting,
            betweenStopMinutes: between,
            lastToEndingMinutes: ending
        )
    }

    func minutes(at connectionIndex: Int, selections: [Int], stopCount: Int) -> Int? {
        guard selections.count == stopCount else { return nil }

        if connectionIndex == 0 {
            return meetingToFirstMinutes[safe: selections[0]]
        }
        if connectionIndex == stopCount {
            return lastToEndingMinutes[safe: selections[stopCount - 1]]
        }

        let legIndex = connectionIndex - 1
        guard betweenStopMinutes.indices.contains(legIndex) else { return nil }
        return betweenStopMinutes[legIndex][safe: selections[legIndex]]?[safe: selections[connectionIndex]]
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

@MainActor
final class MobileAppModel: ObservableObject {
    private struct SelectionSnapshot {
        var planIndex = 0
        var candidates = [0, 0, 0]
    }
    @Published private var selection = SelectionSnapshot()
    var selectedPlanIndex: Int { selection.planIndex }
    var selections: [Int] { selection.candidates }
    @Published private(set) var displayCity = "杭州"
    @Published private(set) var isLiveItinerary = false
    private var singleRouteMatrix: TripRouteEvidenceMatrix?
    var liveRouteMatrix: TripRouteEvidenceMatrix? {
        independentResults.indices.contains(selectedPlanIndex) ? independentResults[selectedPlanIndex].routeMatrix : singleRouteMatrix
    }
    @Published private(set) var liveMapProviderName = "地图服务"
    private var independentResults: [VerifiedTripSummary] = []
    private var cachedChoices: [[[MobileStop]]] = []
    private(set) var presentationBuildCount = 0
    private let performanceLog = OSLog(subsystem: "com.dreamtravel.mobile", category: "PlanSwitch")
    private var rememberedSelections: [Int: [Int]] = [:]
    @Published private var transportSelections: [String: TravelMode] = [:]
    @Published private(set) var planAtmospheres: [PlanAtmosphere] = [.rain, .romance, .evening]

    @Published private(set) var plans = [
        MobilePlan(
            id: 0,
            title: "慢慢逛",
            subtitle: "运河街巷、互动小事和安静晚餐",
            selection: [0, 0, 0],
            meetingTime: "13:30",
            meetingPlace: "武林广场地铁站会合",
            meetingNote: "给彼此留出不赶时间的开场",
            endingTime: "21:30",
            endingTitle: "沿运河散步后返程",
            endingNote: "根据她的返程方向再决定送到哪里",
            validatedRoutes: .demo(seed: 0)
        ),
        MobilePlan(
            id: 1,
            title: "吹吹风",
            subtitle: "西湖游船、下午茶和湖滨晚餐",
            selection: [1, 1, 1],
            meetingTime: "13:35",
            meetingPlace: "龙翔桥地铁站会合",
            meetingNote: "从湖滨步行到码头，沿途先聊聊天",
            endingTime: "21:20",
            endingTitle: "湖滨散步后返程",
            endingNote: "路线集中在湖滨，晚上不需要折返",
            validatedRoutes: .demo(seed: 2)
        ),
        MobilePlan(
            id: 2,
            title: "雨天版",
            subtitle: "室内小展、轻运动和城市夜景",
            selection: [2, 2, 2],
            meetingTime: "13:25",
            meetingPlace: "定安路地铁站会合",
            meetingNote: "优先选择有遮雨衔接的入口",
            endingTime: "21:10",
            endingTitle: "直接打车返程",
            endingNote: "下雨时取消饭后散步，减少户外停留",
            validatedRoutes: .demo(seed: 4)
        )
    ]

    var choices: [[MobileStop]] {
        cachedChoices.indices.contains(selectedPlanIndex) ? cachedChoices[selectedPlanIndex] : fallbackChoices
    }
    private var fallbackChoices: [[MobileStop]] = [
        [
            MobileStop(
                id: "citywalk", time: "14:00", title: "小河直街慢慢逛", place: "小河直街历史文化街区",
                city: "杭州", address: "浙江省杭州市拱墅区小河直街51号", summary: "沿河走走，累了随时坐下", duration: "约 90 分钟",
                reason: "第一段节奏松弛，也给两个人留足聊天时间。", price: "街区免费"
            ),
            MobileStop(
                id: "boat", time: "14:00", title: "西湖上坐一会儿", place: "西湖游船湖滨一公园码头",
                city: "杭州", address: "浙江省杭州市上城区南山路197号", summary: "用一段船程代替连续步行", duration: "约 60–90 分钟",
                reason: "少走路，又能保留属于杭州的体验。", price: "船票待实时核实"
            ),
            MobileStop(
                id: "museum", time: "14:00", title: "先看一个室内小展", place: "中国丝绸博物馆",
                city: "杭州", address: "浙江省杭州市玉皇山路73-1号", summary: "雨天不赶路，也有聊天内容", duration: "约 90 分钟",
                reason: "天气不稳定时更从容，展览也能自然开启话题。", price: "常设展免费，活动待核实"
            )
        ],
        [
            MobileStop(
                id: "market", time: "16:20", title: "一起逛二手市场", place: "杭州周末二手市场候选",
                city: "杭州", address: nil, summary: "各自挑一件有趣的小东西", duration: "约 80 分钟",
                reason: "共同挑选比单纯打卡更有互动感。", price: "入场与购物待核实"
            ),
            MobileStop(
                id: "dessert", time: "16:20", title: "留一段下午茶", place: "湖滨安静甜品店候选",
                city: "杭州", address: nil, summary: "坐下来休息，把聊天时间留足", duration: "约 70 分钟",
                reason: "中段留白能避免行程变成连续赶场。", price: "预计双人 ¥120–180"
            ),
            MobileStop(
                id: "sport", time: "16:20", title: "打一小时羽毛球", place: "市区室内羽毛球馆候选",
                city: "杭州", address: nil, summary: "一点轻运动，让雨天不只是坐着", duration: "约 60 分钟",
                reason: "适合喜欢轻运动、又不想安排太满的两个人。", price: "场地费待核实"
            )
        ],
        [
            MobileStop(
                id: "canal-dinner", time: "18:40", title: "运河边安静吃饭", place: "桥西历史街区餐厅候选",
                city: "杭州", address: nil, summary: "结束后还能沿河走一小段", duration: "约 100 分钟",
                reason: "与小河直街路线集中，减少晚间折返。", price: "预计双人 ¥360–460"
            ),
            MobileStop(
                id: "lake-dinner", time: "18:40", title: "湖滨吃一顿晚餐", place: "湖滨安静餐厅候选",
                city: "杭州", address: nil, summary: "和游船、下午茶在同一区域完成", duration: "约 100 分钟",
                reason: "三段体验距离更近，把精力留给相处。", price: "预计双人 ¥420–520"
            ),
            MobileStop(
                id: "view-dinner", time: "18:40", title: "室内看夜景吃饭", place: "杭州高层景观餐厅候选",
                city: "杭州", address: nil, summary: "雨天也保留一点特别的收尾", duration: "约 100 分钟",
                reason: "不受雨天影响，也能给约会一个有记忆点的结尾。", price: "预计双人 ¥460–600"
            )
        ]
    ]

    var selectedPlan: MobilePlan { plans[selectedPlanIndex] }

    init() { planAtmospheres = PlanAtmosphere.palette(contexts: themeContexts) }

    var themeContexts: [PlanThemeContext] {
        plans.enumerated().map { index, plan in
            let details = independentResults.indices.contains(index)
                ? independentResults[index].planningBrief.slots.map { $0.title + " " + $0.purpose }.joined(separator: " ") : ""
            return PlanThemeContext(title: plan.title, detail: plan.subtitle + " " + details)
        }
    }

    var stops: [MobileStop] {
        choices.indices.map { choices[$0][selections[$0]] }
    }

    func selectPlan(_ index: Int) {
        guard plans.indices.contains(index), index != selectedPlanIndex else { return }
        os_signpost(.begin, log: performanceLog, name: "PlanSwitch")
        defer { os_signpost(.end, log: performanceLog, name: "PlanSwitch") }
        rememberedSelections[selectedPlanIndex] = selections
        // A single publication switches plan, candidates and matrix coherently.
        selection = SelectionSnapshot(planIndex: index, candidates: rememberedSelections[index] ?? plans[index].selection)
    }

    func apply(result: VerifiedTripSummary) {
        defer { planAtmospheres = PlanAtmosphere.palette(contexts: themeContexts) }
        independentResults = result.independentPlans ?? []
        cachedChoices = []
        rememberedSelections = [:]
        transportSelections = [:]
        if independentResults.count == 3 {
            cachedChoices = independentResults.map { buildChoices($0) }
            let basePlans = plans
            plans = independentResults.enumerated().map { index, summary in
                let variant = summary.planningBrief.variants[0]
                return MobilePlan(id: index, title: variant.title, subtitle: variant.subtitle,
                                  selection: variant.selection, meetingTime: "13:30",
                                  meetingPlace: summary.meetingPoint.map { "\($0.name)会合" } ?? "会合地点",
                                  meetingNote: summary.meetingPoint?.address ?? "",
                                  endingTime: "21:30", endingTitle: summary.endingPoint.map { "\($0.name)返程" } ?? "返程",
                                  endingNote: summary.endingPoint?.address ?? "", validatedRoutes: basePlans[index].validatedRoutes)
            }
            displayCity = result.city
            isLiveItinerary = result.isLive
            liveMapProviderName = "腾讯位置服务"
            selection = SelectionSnapshot(planIndex: 0, candidates: plans[0].selection)
            return
        }
        loadPlaces(result)
        applyLegacyPlans(result)
    }

    private func loadPlaces(_ result: VerifiedTripSummary) {
        displayCity = result.city
        isLiveItinerary = result.isLive
        singleRouteMatrix = result.routeMatrix
        liveMapProviderName = "腾讯位置服务"
        fallbackChoices = buildChoices(result)
    }

    private func buildChoices(_ result: VerifiedTripSummary) -> [[MobileStop]] {
        presentationBuildCount += 1
        let planningBrief = result.planningBrief
        if result.isLive,
           let places = result.places,
           (3...5).contains(places.count), places.count == planningBrief.slots.count,
           places.allSatisfy({ $0.count == 3 }) {
            return places.enumerated().map { slotIndex, row in
                row.enumerated().map { candidateIndex, place in
                    MobileStop(
                        id: place.providerID,
                        time: TripSchedule.time(TripSchedule.start(planningBrief, slot: slotIndex)),
                        title: place.name,
                        place: place.name,
                        city: result.city,
                        address: place.address,
                        summary: planningBrief.slots[slotIndex].purpose,
                        duration: "建议 \(TripSchedule.stay(planningBrief, slot: slotIndex, candidate: candidateIndex)) 分钟",
                        reason: planningBrief.slots[slotIndex].purpose,
                        price: result.placeResearch?[place.providerID]?.perPersonText ?? place.estimatedCostYuan.map { "地图参考人均约 ¥\(Int($0))／人" } ?? "人均价格暂无可靠记录",
                        openingHours: place.weeklyOpeningHours,
                        openingHoursVerified: place.openingHoursStatus == .verified,
                        evidenceSource: "腾讯位置服务",
                        gcj02Coordinate: place.coordinate,
                        research: result.placeResearch?[place.providerID],
                        suggestedStayMinutes: TripSchedule.stay(planningBrief, slot: slotIndex, candidate: candidateIndex),
                        plannedFinish: TripSchedule.time(TripSchedule.start(planningBrief, slot: slotIndex) + TripSchedule.stay(planningBrief, slot: slotIndex, candidate: candidateIndex))
                    )
                }
            }
        }
        return fallbackChoices
    }

    private func applyLegacyPlans(_ result: VerifiedTripSummary) {
        let planningBrief = result.planningBrief
        guard planningBrief.variants.count == plans.count else { return }
        plans = zip(plans, planningBrief.variants).map { base, variant in
            MobilePlan(
                id: base.id,
                title: variant.title,
                subtitle: variant.subtitle,
                selection: variant.selection,
                meetingTime: result.isLive ? "13:30" : base.meetingTime,
                meetingPlace: result.meetingPoint.map { "\($0.name)会合" } ?? base.meetingPlace,
                meetingNote: result.meetingPoint?.address ?? base.meetingNote,
                endingTime: result.isLive ? "21:30" : base.endingTime,
                endingTitle: result.endingPoint.map { "\($0.name)返程" } ?? base.endingTitle,
                endingNote: result.endingPoint?.address ?? base.endingNote,
                validatedRoutes: base.validatedRoutes
            )
        }
        selection = SelectionSnapshot(planIndex: 0, candidates: plans[0].selection)
    }

    func cycleStop(at slot: Int, direction: Int) {
        let count = choices[slot].count
        selection.candidates[slot] = (selections[slot] + direction + count) % count
    }

    func selectStop(at slot: Int, choice: Int) {
        guard choices.indices.contains(slot), choices[slot].indices.contains(choice) else { return }
        selection.candidates[slot] = choice
    }

    private func transportKey(at index: Int) -> String {
        let nodes = stops.map(\.id)
        let from = index == 0 ? "meeting" : nodes[safe: index - 1] ?? "invalid"
        let to = index == nodes.count ? "ending" : nodes[safe: index] ?? "invalid"
        return "\(selectedPlanIndex):\(index):\(from):\(to)"
    }

    func transportOptions(at index: Int) -> [TravelModeOption] {
        TravelModePolicy.offered(liveRouteMatrix?.route(at: index, selections: selections)?.modeOptions ?? [])
    }

    func selectedTransport(at index: Int) -> TravelModeOption? {
        guard let route = liveRouteMatrix?.route(at: index, selections: selections) else { return nil }
        let mode = transportSelections[transportKey(at: index)] ?? TravelMode.from(method: route.method)
        let options = transportOptions(at: index)
        return options.first { $0.mode == mode } ?? TravelModePolicy.recommended(options)
    }

    func selectTransport(_ mode: TravelMode, at index: Int) {
        guard transportOptions(at: index).contains(where: { $0.mode == mode && $0.isAvailable }),
              selectedTransport(at: index)?.mode != mode else { return }
        transportSelections[transportKey(at: index)] = mode
    }

    /// Propagate late arrival locally; keep the published timetable and stay durations intact.
    func transportDelayMinutes(at index: Int) -> Int {
        func minute(_ value: String) -> Int {
            let parts = value.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 ? parts[0] * 60 + parts[1] : 0
        }
        let nodes = stops
        guard isLiveItinerary, (0...nodes.count).contains(index) else { return 0 }
        var departure = minute(selectedPlan.meetingTime)
        for edge in 0...index {
            guard let duration = selectedTransport(at: edge)?.durationSeconds else { return 0 }
            let arrival = departure + Int(ceil(Double(duration) / 60))
            let deadline = edge == nodes.count ? minute(selectedPlan.endingTime) : minute(nodes[edge].time)
            if edge == index { return max(0, arrival - deadline) }
            departure = max(arrival, deadline) + (nodes[edge].suggestedStayMinutes ?? 0) + TripSchedule.bufferMinutes
        }
        return 0
    }

    var hasTransportConflict: Bool {
        (0...stops.count).contains { transportDelayMinutes(at: $0) > 0 }
    }

    func connection(at index: Int) -> MobileJourneyConnection {
        if let liveRouteMatrix,
           liveRouteMatrix.route(at: index, selections: selections) != nil,
           let option = selectedTransport(at: index), let distance = option.distanceMeters {
            let delay = transportDelayMinutes(at: index)
            let traffic = option.mode == .driving ? " · 按查询时路况，不含找车位" : ""
            return MobileJourneyConnection(
                symbol: option.mode.symbol,
                title: "\(option.mode.title) · \(option.timeText)",
                detail: "\(liveMapProviderName) · \(distance) 米\(traffic) · 出发前复核" +
                    (delay > 0 ? "\n预计比原定到达晚 \(delay) 分钟，请换交通或备选。" : ""),
                needsVerification: delay > 0
            )
        }
        if isLiveItinerary {
            return MobileJourneyConnection(symbol: "exclamationmark.triangle", title: "暂无合适交通",
                detail: "这段旧行程没有符合条件的路线，请换地点备选或重新安排。", needsVerification: true)
        }
        guard let minutes = selectedPlan.validatedRoutes.minutes(
            at: index,
            selections: selections,
            stopCount: choices.count
        ) else {
            return MobileJourneyConnection(
                symbol: "exclamationmark.triangle",
                title: "连接信息不可用",
                detail: "当前演示矩阵缺少这组连接",
                needsVerification: true
            )
        }

        let isWalking = minutes <= 15
        return MobileJourneyConnection(
            symbol: isWalking ? "figure.walk" : "car.fill",
            title: "\(isWalking ? "步行" : "移动") · 约 \(minutes) 分钟",
            detail: "演示时间；重新安排后提供合适交通",
            needsVerification: false
        )
    }
}

extension TripRouteEvidenceMatrix {
    func route(at connectionIndex: Int, selections: [Int]) -> TravelRouteEvidence? {
        let count = selections.count
        guard (3...5).contains(count), betweenSlots.count == count - 1,
              selections.allSatisfy({ (0..<3).contains($0) }) else { return nil }
        if connectionIndex == 0 { return meetingToFirst[safe: selections[0]] }
        if connectionIndex == count { return lastToEnding[safe: selections[count - 1]] }
        guard (1..<count).contains(connectionIndex) else { return nil }
        return betweenSlots[connectionIndex - 1][safe: selections[connectionIndex - 1]]?[safe: selections[connectionIndex]]
    }
}
