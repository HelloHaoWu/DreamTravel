import Foundation
@main struct Inspect {
 @MainActor static func main() throws {
    let directory = URL(fileURLWithPath: CommandLine.arguments[1])
    let state = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("validation-state.json"))) as! [String: Any]
    print("PHASE=\(state["phase"] ?? "unknown") PUBLICATIONS=\(state["completedRunCount"] ?? 0)")
    print(state["message"] ?? "")
    guard state["phase"] as? String == "ready" else { return }
    let data = try Data(contentsOf: directory.appendingPathComponent("validation-result.json"))
    let result = try JSONDecoder().decode(VerifiedTripSummary.self, from: data)
    let plans = result.independentPlans ?? [result]
    print("PLANS=\(plans.count) CANDIDATES=\(plans.reduce(0) { $0 + $1.candidateCount }) ROUTES=\(plans.reduce(0) { $0 + $1.connectionCount })")
    print("SEARCH_SOURCES=\(result.discovery?.sources.count ?? 0) IDEAS=\(result.discovery?.ideas.count ?? 0)")
    let model = MobileAppModel()
    model.apply(result: result)
    var combinations = 0
    for index in plans.indices {
        model.selectPlan(index)
        precondition(model.choices.flatMap { $0.map(\.id) } == plans[index].places!.flatMap { $0.map(\.providerID) })
        for a in 0..<3 { for b in 0..<3 { for c in 0..<3 {
            model.selectStop(at: 0, choice: a); model.selectStop(at: 1, choice: b); model.selectStop(at: 2, choice: c)
            for edge in 0..<4 { precondition(!model.connection(at: edge).needsVerification) }
            combinations += 1
        } } }
        model.selectStop(at: 0, choice: index)
    }
    for index in plans.indices { model.selectPlan(index); precondition(model.selections[0] == index) }
    print("LIVE_RESULT_SELECTION_COMBINATIONS=\(combinations) SELECTION_MEMORY=passed")
    for plan in plans {
        print("PLAN", plan.planningBrief.variants[0].title)
        for row in plan.places ?? [] { print(row.map(\.name).joined(separator: " | ")) }
    }
    let reports = result.placeResearch ?? [:]
    print("PLACE_REPORTS=\(reports.count) WITH_PRICE=\(reports.values.filter { $0.perPersonText != nil }.count) WITH_3PLUS_REVIEWS=\(reports.values.filter { $0.relevantReviewCount >= 3 }.count)")
    let references = try JSONDecoder().decode(ReferenceArchive.self, from: Data(contentsOf: directory.appendingPathComponent("references-v1.json")))
    print("SAVED_REFERENCES=\(references.entries.count)")
 }
}
