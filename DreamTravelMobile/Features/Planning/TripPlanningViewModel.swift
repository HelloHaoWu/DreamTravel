import SwiftUI

@MainActor
final class TripPlanningViewModel: ObservableObject {
    @Published private(set) var phase: AgentPhase = .idle
    @Published private(set) var message = ""
    @Published private(set) var isRunning = false
    @Published private(set) var completedRunCount = 0
    @Published private(set) var lastResult: VerifiedTripSummary?

    private let runtime: AgentRuntime?
    private var eventTask: Task<Void, Never>?
    private var generationID: UUID?
#if DEBUG
    private var validationEvents: [String] = []
#endif

    init(runtime: AgentRuntime? = nil) {
        self.runtime = runtime
    }

#if DEBUG
    /// Replay a previously completed native validation run for UI/old-result compatibility checks.
    func replayValidationResult() {
        let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DreamTravel/validation-result.json")
        guard let data = try? Data(contentsOf: file),
              let result = try? JSONDecoder().decode(VerifiedTripSummary.self, from: data) else { return }
        apply(.completed(result))
    }
#endif

    func start(city: String, note: String) {
        guard !isRunning else { return }

        let cleanedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let intent = TripIntent(
            city: city.trimmingCharacters(in: .whitespacesAndNewlines),
            scheduledStart: nextSaturdayAtTwoPM(),
            timeWindow: "周六下午到晚上",
            energy: "不要太累",
            mood: "有点浪漫",
            note: cleanedNote.isEmpty ? nil : cleanedNote
        )

        isRunning = true
        phase = .snapshotting
        message = "正在开始这次安排"
        let generation = UUID()
        generationID = generation

        eventTask = Task { [weak self] in
            guard let self, !Task.isCancelled, generationID == generation else { return }
            let runtime = self.runtime ?? AgentRuntime()
            let events = await runtime.start(intent: intent)
            for await event in events {
                guard !Task.isCancelled, generationID == generation else { return }
                apply(event)
            }
        }
    }

    private func nextSaturdayAtTwoPM(now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let currentWeekday = calendar.component(.weekday, from: startOfToday)
        let saturday = 7
        var daysAhead = (saturday - currentWeekday + 7) % 7
        if daysAhead == 0,
           calendar.component(.hour, from: now) >= 14 {
            daysAhead = 7
        }
        let date = calendar.date(byAdding: .day, value: daysAhead, to: startOfToday) ?? now
        return calendar.date(bySettingHour: 14, minute: 0, second: 0, of: date) ?? date
    }

    func cancel() {
        generationID = nil
        eventTask?.cancel()
        eventTask = nil
        // Cancelling the event consumer terminates only its own runtime stream.
        // A delayed global cancel must never cancel a newly started generation.
        isRunning = false
        phase = .cancelled
        message = "已取消，本次条件没有丢失"
    }

    private func apply(_ event: AgentEvent) {
        switch event {
        case let .progress(phase, message):
            self.phase = phase
            self.message = message
        case let .completed(result):
            phase = .ready
            message = "已结合当天温度、湿度和天气完成校验"
            isRunning = false
            lastResult = result
            completedRunCount += 1
            eventTask = nil
        case .cancelled:
            phase = .cancelled
            message = "已取消，本次条件没有丢失"
            isRunning = false
            eventTask = nil
        case let .failed(failure):
            phase = .failed
            message = failure.message
            isRunning = false
            eventTask = nil
        }
#if DEBUG
        if ProcessInfo.processInfo.environment["DREAMTRAVEL_AUTORUN"] == "1" {
            validationEvents.append("\(phase.rawValue): \(message)")
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("DreamTravel", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let state: [String: Any] = ["phase": phase.rawValue, "message": message, "completedRunCount": completedRunCount, "events": validationEvents]
                try JSONSerialization.data(withJSONObject: state, options: .prettyPrinted)
                    .write(to: directory.appendingPathComponent("validation-state.json"), options: .atomic)
                if case let .completed(result) = event {
                    try JSONEncoder().encode(result).write(to: directory.appendingPathComponent("validation-result.json"), options: .atomic)
                }
            } catch { print("DreamTravel validation artifact could not be saved") }
        }
#endif
    }
}
