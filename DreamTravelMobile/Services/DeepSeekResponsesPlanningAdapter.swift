import Foundation

enum DeepSeekCredentialProvider {
    static func read() throws -> String? {
#if DEBUG
        if let environmentKey = ProcessInfo.processInfo.environment["DREAMTRAVEL_DEEPSEEK_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !environmentKey.isEmpty {
            return environmentKey
        }
#endif
        return try DeepSeekKeychainStore.read()
    }
}

struct DeepSeekResponsesPlanningAdapter: PlanningModelAdapter {
    private let client: DeepSeekResponsesPlanningClient
    private let keyProvider: @Sendable () throws -> String?

    init(
        client: DeepSeekResponsesPlanningClient = DeepSeekResponsesPlanningClient(),
        keyProvider: @escaping @Sendable () throws -> String? = {
            try DeepSeekCredentialProvider.read()
        }
    ) {
        self.client = client
        self.keyProvider = keyProvider
    }

    func makeDraft(
        for intent: TripIntent,
        weather: WeatherEvidenceSummary,
        runID: UUID
    ) async throws -> TripDraftManifest {
        try await makeDraft(for: intent, weather: weather, runID: runID, researchContext: "")
    }

    func makeDraft(for intent: TripIntent, weather: WeatherEvidenceSummary, runID: UUID, researchContext: String) async throws -> TripDraftManifest {
        let key: String
        do {
            guard let storedKey = try keyProvider(), !storedKey.isEmpty else {
                throw AgentFailure(message: "请先在设置中连接 DeepSeek。")
            }
            key = storedKey
        } catch let failure as AgentFailure {
            throw failure
        } catch {
            throw AgentFailure(message: "无法读取 DeepSeek API Key，请重新连接。")
        }

        do {
            let result = try await client.generateBrief(
                apiKey: key,
                intent: intent,
                weather: weather,
                researchContext: researchContext
            )
            let slotCount = result.brief.slots.count
            let candidatesPerSlot = result.brief.slots.first?.searchQueries.count ?? 0
            let candidateCount = slotCount * candidatesPerSlot
            let endpointConnections = candidatesPerSlot * 2
            let betweenSlotConnections = max(0, slotCount - 1) * candidatesPerSlot * candidatesPerSlot

            return TripDraftManifest(
                runID: runID,
                intent: intent,
                slotCount: slotCount,
                candidatesPerSlot: candidatesPerSlot,
                candidateCount: candidateCount,
                requiredConnectionCount: endpointConnections + betweenSlotConnections,
                planningBrief: result.brief,
                modelProvider: "DeepSeek \(result.resolvedModel)",
                weatherSnapshotAt: weather.metadata.fetchedAt,
                generatedAt: Date()
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as AgentFailure {
            throw failure
        } catch {
            throw AgentFailure(message: error.localizedDescription)
        }
    }
}

struct DeepSeekPlanningResult: Equatable, Sendable {
    let brief: TripPlanningBrief
    let resolvedModel: String
}

struct DeepSeekResponsesPlanningClient: Sendable {
    func generateBrief(
        apiKey: String,
        configuration: DeepSeekConfiguration = DeepSeekConfiguration(),
        intent: TripIntent,
        weather: WeatherEvidenceSummary,
        researchContext: String = ""
    ) async throws -> DeepSeekPlanningResult {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw DeepSeekConnectionError.emptyKey }

        guard var components = URLComponents(string: configuration.baseURL),
              components.scheme == "https",
              components.host != nil else {
            throw DeepSeekConnectionError.invalidBaseURL
        }
        components.path = "/responses"
        guard let url = components.url else { throw DeepSeekConnectionError.invalidBaseURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PlanningRequest(
            model: configuration.model,
            instructions: Self.instructions,
            input: Self.input(intent: intent, weather: weather) + "\n" + researchContext,
            maxOutputTokens: 8_192,
            text: PlanningTextConfiguration()
        ))

        let response = try await TravelHTTPTransport.live.send(request)
        let data = response.data
        guard (200..<300).contains(response.status) else {
            let message = (try? JSONDecoder().decode(PlanningErrorEnvelope.self, from: data).error.message)
            throw DeepSeekConnectionError.http(status: response.status, message: message)
        }

        let envelope = try JSONDecoder().decode(PlanningResponseEnvelope.self, from: data)
        guard envelope.status == "completed" else {
            throw AgentFailure(message: "DeepSeek 输出被截断，请重试。")
        }
        guard let text = envelope.output
            .lazy
            .filter({ $0.type == "message" })
            .compactMap({ $0.content })
            .flatMap({ $0 })
            .first(where: { $0.type == "output_text" })?
            .text,
              let briefData = text.data(using: .utf8) else {
            throw AgentFailure(message: "DeepSeek 没有返回可用的结构化计划。")
        }

        let brief = try JSONDecoder().decode(TripPlanningBrief.self, from: briefData)
        try validate(brief)
        return DeepSeekPlanningResult(brief: brief, resolvedModel: envelope.model)
    }

    private func validate(_ brief: TripPlanningBrief) throws {
        let topLevelStrings = [brief.title, brief.summary, brief.weatherStrategy]
        guard topLevelStrings.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              brief.variants.count == 3,
              brief.variants.allSatisfy({ variant in
                  !variant.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  !variant.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  variant.selection.count == brief.slots.count &&
                  variant.selection.allSatisfy({ (0..<3).contains($0) })
              }),
              Set(brief.variants.map(\.selection)).count == 3,
              (3...5).contains(brief.slots.count),
              brief.slots.first?.startMinute == 840,
              zip(brief.slots, brief.slots.dropFirst()).allSatisfy({ ($0.startMinute ?? 0) < ($1.startMinute ?? 0) }),
              brief.slots.allSatisfy({ slot in
                  !slot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  !slot.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  slot.searchQueries.count == 3 &&
                  slot.suggestedStayMinutes?.count == 3 &&
                  slot.suggestedStayMinutes?.allSatisfy({ (20...180).contains($0) }) == true &&
                  slot.startMinute.map({ (840..<1290).contains($0) }) == true && slot.isDining != nil &&
                  slot.searchQueries.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
              }) else {
            throw AgentFailure(message: "DeepSeek 返回的三至五段候选或时间安排不完整，请重试。")
        }
    }

    private static let instructions = """
    你是 DreamTravel 的行程规划器。根据用户体力、天气、主题和时间，自主安排3至5段连续约会体验，不为凑数量添加地点。累、雨天或长体验优先3段；短而集中的体验可4至5段。
    所有用户可见文字必须使用简体中文。每段必须提供三个适合交给地图 POI API 的简短搜索词。
    每段三个备选，variants 给出三个不同内部组合；selection 长度必须等于 slots 数量，每个值为0到2，三套组合不能相同。
    文案保持简短：标题不超过 18 字，摘要不超过 100 字，天气策略不超过 120 字，检索词不超过 60 字。
    若输入附有地图真实地点清单，检索词必须使用清单中的完整名称，不得截短分店信息。第一段轻松开场，安排共同体验和合理的晚餐，可在晚餐后安排短夜景。每段标明 isDining；晚餐无需固定为最后一段。
    每个候选都给 suggestedStayMinutes 建议停留分钟数，与三个 searchQueries 一一对应。这是行程建议，不是商家规定或待用户确认。
    每段提供 startMinute（当地当天从0点起的分钟数）。第一段840即14:00，后续严格递增，21:30即1290前完成返程。三个备选共用该段开始时间。每段预留最长备选停留+至少20分钟交通+10分钟缓冲，晚餐建议60至90分钟。3段可840/980/1120；4段可840/950/1060/1170；5段可840/930/1020/1110/1200，结合体验调整。不能为凑五段压缩必须长时间的活动。之后按真实路线检验所有备选组合。
    天气会影响室内外比例、步行强度、留白和移动方式。不要编造具体店名、地址、营业时间、价格或路线时长，
    因为这些事实必须由后续地图和天气工具核实。严格遵守 JSON Schema。
    """

    private static func input(intent: TripIntent, weather: WeatherEvidenceSummary) -> String {
        let note = intent.note ?? "无补充"
        let feelsLike = weather.feelsLikeCelsius.map { "\($0)℃" } ?? "供应商未提供"
        let rainProbability = weather.precipitationProbabilityPercent.map { "\($0)%" } ?? "供应商未提供"
        return """
        城市：\(intent.city)
        开始时间：\(intent.scheduledStart.ISO8601Format())
        时间范围：\(intent.timeWindow)
        体力：\(intent.energy)
        氛围：\(intent.mood)
        用户补充：\(note)
        天气现象：\(weather.condition)
        温度：\(weather.temperatureCelsius)℃
        体感温度：\(feelsLike)
        湿度：\(weather.humidityPercent)%
        降水概率：\(rainProbability)
        天气目标时间：\(weather.forecastFor.ISO8601Format())
        """
    }
}

private struct PlanningRequest: Encodable {
    let model: String
    let instructions: String
    let input: String
    let maxOutputTokens: Int
    let text: PlanningTextConfiguration
    let reasoning = PlanningReasoningConfiguration()

    enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case maxOutputTokens = "max_output_tokens"
        case text
        case reasoning
    }
}

private struct PlanningReasoningConfiguration: Encodable {
    let effort = "low"
}

private struct PlanningTextConfiguration: Encodable {
    let format = PlanningJSONSchemaFormat()
}

private struct PlanningJSONSchemaFormat: Encodable {
    let type = "json_schema"
    let name = "trip_planning_brief"
    let strict = true
    let schema = PlanningRootSchema()
}

private struct PlanningRootSchema: Encodable {
    let type = "object"
    let properties = PlanningRootProperties()
    let required = ["title", "summary", "weatherStrategy", "variants", "slots"]
    let additionalProperties = false
}

private struct PlanningRootProperties: Encodable {
    let title = PlanningStringSchema(maxLength: 18)
    let summary = PlanningStringSchema(maxLength: 100)
    let weatherStrategy = PlanningStringSchema(maxLength: 120)
    let variants = PlanningVariantsSchema()
    let slots = PlanningSlotsSchema()
}

private struct PlanningVariantsSchema: Encodable {
    let type = "array"
    let minItems = 3
    let maxItems = 3
    let items = PlanningVariantObjectSchema()
}

private struct PlanningVariantObjectSchema: Encodable {
    let type = "object"
    let properties = PlanningVariantProperties()
    let required = ["title", "subtitle", "selection"]
    let additionalProperties = false
}

private struct PlanningVariantProperties: Encodable {
    let title = PlanningStringSchema(maxLength: 8)
    let subtitle = PlanningStringSchema(maxLength: 24)
    let selection = PlanningSelectionSchema()
}

private struct PlanningSelectionSchema: Encodable {
    let type = "array"
    let minItems = 3
    let maxItems = 5
    let items = PlanningIntegerSchema()
}

private struct PlanningIntegerSchema: Encodable {
    let type = "integer"
    let minimum = 0
    let maximum = 2
}

private struct PlanningSlotsSchema: Encodable {
    let type = "array"
    let minItems = 3
    let maxItems = 5
    let items = PlanningSlotObjectSchema()
}

private struct PlanningSlotObjectSchema: Encodable {
    let type = "object"
    let properties = PlanningSlotProperties()
    let required = ["title", "purpose", "preferredEnvironment", "searchQueries", "suggestedStayMinutes", "startMinute", "isDining"]
    let additionalProperties = false
}

private struct PlanningSlotProperties: Encodable {
    let title = PlanningStringSchema(maxLength: 18)
    let purpose = PlanningStringSchema(maxLength: 60)
    let preferredEnvironment = PlanningEnvironmentSchema()
    let searchQueries = PlanningQueriesSchema()
    let suggestedStayMinutes = PlanningStaySchema()
    let startMinute = StartMinuteSchema()
    let isDining = DiningSchema()
}

private struct StartMinuteSchema: Encodable { let type = "integer"; let minimum = 840; let maximum = 1289 }
private struct DiningSchema: Encodable { let type = "boolean" }

private struct PlanningStaySchema: Encodable {
    let type = "array"
    let minItems = 3
    let maxItems = 3
    let items = StayIntegerSchema()
    struct StayIntegerSchema: Encodable { let type = "integer"; let minimum = 20; let maximum = 180 }
}

private struct PlanningEnvironmentSchema: Encodable {
    let type = "string"
    let allowedValues = ["indoor", "outdoor", "mixed"]

    enum CodingKeys: String, CodingKey {
        case type
        case allowedValues = "enum"
    }
}

private struct PlanningQueriesSchema: Encodable {
    let type = "array"
    let minItems = 3
    let maxItems = 3
    let items = PlanningStringSchema(maxLength: 60)
}

private struct PlanningStringSchema: Encodable {
    let type = "string"
    let maxLength: Int?

    init(maxLength: Int? = nil) {
        self.maxLength = maxLength
    }
}

private struct PlanningResponseEnvelope: Decodable {
    let model: String
    let status: String
    let output: [PlanningOutputItem]
}

private struct PlanningOutputItem: Decodable {
    let type: String
    let content: [PlanningOutputContent]?
}

private struct PlanningOutputContent: Decodable {
    let type: String
    let text: String?
}

private struct PlanningErrorEnvelope: Decodable {
    let error: Body
    struct Body: Decodable { let message: String }
}
