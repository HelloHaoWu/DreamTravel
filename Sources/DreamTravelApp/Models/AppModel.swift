import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Screen: Equatable { case setup, home, planning, itinerary }
    enum Adjustment { case lighter, rainy, custom(String) }

    @Published var screen: Screen = .setup
    @Published var city = "杭州"
    @Published var timeRange = "14:00–21:30"
    @Published var budget = 800
    @Published var idea = ""
    @Published var meetingPoint: String?
    @Published var showsMeetingQuestion = false
    @Published var selectedStop: ItineraryStop?
    @Published var showsDepartureCard = false
    @Published var showsBookingCenter = false
    @Published var bookingCategory: BookingCategory = .tickets
    @Published var selectedPlanIndex = 0
    @Published var selectedOptionIndices = DemoItinerary.plans[0].selection
    @Published var changeSummary: String?
    @Published var adjustmentText = ""
    @Published var importedItemName: String?
    @Published var preparationDone = false
    @Published var isConnectingModel = false
    @Published var modelConnectionError: String?
    @Published var modelConnectionSummary: String?

    private(set) var savedModelConfiguration: ModelConfiguration?

    private var previousSelection: (plan: Int, options: [Int])?

    init() {
        if let data = UserDefaults.standard.data(forKey: "model-configuration") {
            savedModelConfiguration = try? JSONDecoder().decode(ModelConfiguration.self, from: data)
            if let savedModelConfiguration {
                modelConnectionSummary = "已连接 \(savedModelConfiguration.provider.title) · \(savedModelConfiguration.model)"
            }
        }
    }

    func connectModel(configuration: ModelConfiguration, apiKey: String) async {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        isConnectingModel = true
        modelConnectionError = nil
        defer { isConnectingModel = false }

        do {
            try await ModelAPIClient().validate(configuration: configuration, apiKey: trimmedKey)
            try KeychainStore.saveAPIKey(trimmedKey)
            let encoded = try JSONEncoder().encode(configuration)
            UserDefaults.standard.set(encoded, forKey: "model-configuration")
            savedModelConfiguration = configuration
            modelConnectionSummary = "已连接 \(configuration.provider.title) · \(configuration.model)"
            resetToHome()
        } catch {
            modelConnectionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    let cities = ["杭州", "上海", "苏州"]
    let timeRanges = ["14:00–21:30", "15:00–22:00", "全天"]
    let budgets = [500, 800, 1200]

    var currentPlan: ItineraryPlan { DemoItinerary.plans[selectedPlanIndex] }
    var stops: [ItineraryStop] {
        DemoItinerary.choices.enumerated().map { slotIndex, options in
            options[selectedOptionIndices[slotIndex]]
        }
    }
    var itineraryTitle: String { currentPlan.title }
    var itinerarySubtitle: String { currentPlan.subtitle }
    var estimatedCost: Int { stops.reduce(0) { $0 + $1.costEstimate } }

    func requestPlan() {
        if meetingPoint == nil {
            showsMeetingQuestion = true
        } else {
            beginPlanning()
        }
    }

    func openBookingCenter(category: BookingCategory) {
        bookingCategory = category
        showsBookingCenter = true
    }

    func useMeetingPoint(_ point: String) {
        let trimmed = point.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        meetingPoint = trimmed
        showsMeetingQuestion = false
        beginPlanning()
    }

    func beginPlanning() { screen = .planning }

    func finishPlanning() {
        guard screen == .planning else { return }
        selectPlan(0, recordsUndo: false, announcesChange: false)
        screen = .itinerary
    }

    func cancelPlanning() { screen = .home }

    func cyclePlan(_ direction: Int) {
        let count = DemoItinerary.plans.count
        selectPlan((selectedPlanIndex + direction + count) % count)
    }

    func selectPlan(_ index: Int, recordsUndo: Bool = true, announcesChange: Bool = true) {
        guard DemoItinerary.plans.indices.contains(index) else { return }
        if recordsUndo { rememberSelection() }
        selectedPlanIndex = index
        selectedOptionIndices = DemoItinerary.plans[index].selection
        changeSummary = announcesChange ? "已切换到完整方案“\(DemoItinerary.plans[index].title)”。" : nil
    }

    func cycleStop(at slotIndex: Int, direction: Int) {
        guard DemoItinerary.choices.indices.contains(slotIndex) else { return }
        rememberSelection()
        let count = DemoItinerary.choices[slotIndex].count
        selectedOptionIndices[slotIndex] = (selectedOptionIndices[slotIndex] + direction + count) % count
        changeSummary = "已替换 \(stops[slotIndex].time) 的安排，其他时间段保持不变。"
    }

    func replace(_ stop: ItineraryStop) {
        guard let slotIndex = DemoItinerary.choices.firstIndex(where: { choices in
            choices.contains(where: { $0.id == stop.id })
        }) else { return }
        cycleStop(at: slotIndex, direction: 1)
        selectedStop = nil
    }

    func optionPosition(at slotIndex: Int) -> String {
        "\(selectedOptionIndices[slotIndex] + 1) / \(DemoItinerary.choices[slotIndex].count)"
    }

    func apply(_ adjustment: Adjustment) {
        switch adjustment {
        case .lighter:
            selectPlan(0)
            changeSummary = "已切换到转场更集中的小城慢游方案。"
        case .rainy:
            selectPlan(2)
            changeSummary = "已切换到三段室内体验，其他条件保持不变。"
        case .custom(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            rememberSelection()
            selectedOptionIndices[0] = 2
            changeSummary = "已按“\(trimmed)”替换第一段，其他时间段保持不变。"
        }
        adjustmentText = ""
    }

    func undoAdjustment() {
        guard let previousSelection else { return }
        selectedPlanIndex = previousSelection.plan
        selectedOptionIndices = previousSelection.options
        self.previousSelection = nil
        changeSummary = nil
    }

    func resetToHome() {
        screen = .home
        showsMeetingQuestion = false
        selectedStop = nil
        showsDepartureCard = false
        showsBookingCenter = false
    }

    func previewSetup() { screen = .setup }

    func previewItinerary() {
        selectPlan(0, recordsUndo: false, announcesChange: false)
        screen = .itinerary
    }

    func shareText(partnerMode: Bool) -> String {
        var lines = [itineraryTitle, "\(city) · 9 月 12 日 · \(timeRange)", ""]
        lines.append(contentsOf: stops.map { "\($0.time)  \($0.title) · \($0.place)" })
        lines.append(partnerMode
            ? "\n我们慢慢走，累了就随时歇一会儿。"
            : "\n提醒：地点、价格、营业信息与路线仍待核实 · 体验预算约 ¥\(estimatedCost)")
        return lines.joined(separator: "\n")
    }

    private func rememberSelection() {
        previousSelection = (selectedPlanIndex, selectedOptionIndices)
    }
}
