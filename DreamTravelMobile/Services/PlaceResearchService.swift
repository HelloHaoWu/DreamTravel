import Foundation

struct DishMention: Codable, Hashable, Sendable {
    let name: String
    let sentiment: String
    let reason: String
    let quote: String
    let priceYuan: Double?
    let priceQuote: String?
    let unit: String?
}
struct ExperienceTip: Codable, Hashable, Sendable {
    let advice: String
    let quote: String
}
struct PlaceObservation: Codable, Hashable, Sendable {
    let url: String
    let venueQuote: String
    let kind: String
    let author: String?
    let visitDate: String?
    var dishes: [DishMention]
    var perPersonYuan: Double?
    let perPersonQuote: String?
    var totalYuan: Double?
    var diners: Int?
    let billQuote: String?
    var openingHours: String?
    let openingQuote: String?
    var tips: [ExperienceTip]
    var reservation: ReservationObservation? = nil
}
struct DishRecommendation: Codable, Hashable, Identifiable, Sendable {
    var id: String { name }
    let name: String
    let reason: String
    let positiveCount: Int
    let negativeCount: Int
    let sampleCount: Int
    let priceText: String?
    let sourceURLs: [String]
}
struct PlaceResearchReport: Codable, Hashable, Sendable {
    let placeID: String
    let searchedAt: Date
    let sources: [ResearchSource]
    let readableCount: Int
    let relevantReviewCount: Int
    let dishes: [DishRecommendation]
    let perPersonText: String?
    let openingText: String?
    let tips: [String]
    let notice: String
    // Small, source-bound extracts allow deterministic statistics to be audited.
    var observations: [PlaceObservation] = []
    var reservation: PlaceReservation? = nil
}
struct ReadableResearchPage: Sendable {
    let source: ResearchSource
    let text: String
    var links: [ResearchPageLink] = []
}
protocol PlaceResearching: Sendable {
    func research(place: TravelPlaceEvidence, city: String, isDining: Bool) async throws -> PlaceResearchReport
}

private final class ResearchRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.map(ResearchPageReader.isAllowed) == true ? request : nil)
    }
}
struct ResearchPageReader: Sendable {
    static func isAllowed(_ url: URL) -> Bool {
        guard ResearchURL.validated(url.absoluteString) != nil, let host = url.host?.lowercased() else { return false }
        let domains = ["xiaohongshu.com", "douyin.com", "dianping.com", "meituan.com", "trip.com", "ctrip.com", "sohu.com", "zjol.com.cn", "hangzhou.com.cn", "mafengwo.cn", "you.ctrip.com"]
        return host.hasSuffix(".gov.cn") || domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
    func read(_ source: ResearchSource) async throws -> ReadableResearchPage? {
        guard let url = ResearchURL.validated(source.url), Self.isAllowed(url) else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 18; configuration.timeoutIntervalForResource = 24
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: ResearchRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.mimeType?.contains("html") == true else { return nil }
        var data = Data()
        for try await byte in bytes {
            if data.count >= 1_500_000 { return nil }
            data.append(byte)
        }
        try Task.checkCancellation()
        guard let html = String(data: data, encoding: .utf8) else { return nil }
        let text = Self.visibleText(html)
        guard text.count >= 180,
              !["访问验证", "安全验证", "请完成验证", "Access Denied"].contains(where: { text.prefix(1200).contains($0) }) else { return nil }
        return ReadableResearchPage(source: source, text: String(text.prefix(14000)), links: ReservationValidation.links(in: html, base: response.url ?? url))
    }
    static func visibleText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "(?is)<(script|style|noscript|nav|footer|header)\\b[^>]*>.*?</\\1>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?s)<[^>]+>", with: " ", options: .regularExpression)
        for (from, to) in [("&nbsp;", " "), ("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&yen;", "¥")] { text = text.replacingOccurrences(of: from, with: to) }
        return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct DeepSeekPlaceResearch: PlaceResearching {
    var search = DeepSeekWebSearchClient()
    var summarizer = DeepSeekResearchJSONClient()
    var reader = ResearchPageReader()

    func research(place: TravelPlaceEvidence, city: String, isDining: Bool) async throws -> PlaceResearchReport {
        let purpose = isDining ? "寻找3至5篇同一家分店真实就餐记录，招牌菜、推荐与避雷、菜价、人均、账单，另查菜单与营业时间" : "寻找具体游览体验：看什么、路线顺序、停留时间、避坑，以及场馆开放与预约说明"
        let batch: WebResearchBatch
        do {
            batch = try await search.search("\(city) \(place.name) 地址：\(place.address)。\(purpose)。同时查是否必须预约、建议提前预订或无需预约，以及该分店/场馆实际预约订座购票入口；酒店查对应酒店预订页。优先大众点评、美团、小红书、抖音、携程及商家官方公开网页。必须同一地点，附原始帖子URL，不要仅搜索主题聚合页。", maxUses: 1)
        } catch is CancellationError { throw CancellationError() }
        catch { return Self.unavailable(place: place, notice: "地点资料搜索暂不可用，未据此生成菜价或营业时间。") }
        var pages: [ReadableResearchPage] = []
        // Fetch a small bounded set in parallel, without shared login cookies or account credentials.
        let selected = Array(batch.sources.filter { ResearchURL.validated($0.url).map(ResearchPageReader.isAllowed) == true }.prefix(7))
        await withTaskGroup(of: ReadableResearchPage?.self) { group in
            for source in selected { group.addTask { try? await reader.read(source) } }
            for await page in group { if let page { pages.append(page) } }
        }
        try Task.checkCancellation()
        pages.sort { $0.source.url < $1.source.url }
        guard !pages.isEmpty else {
            return PlaceResearchReport(placeID: place.providerID, searchedAt: Date(), sources: batch.sources, readableCount: 0, relevantReviewCount: 0, dishes: [], perPersonText: nil, openingText: nil, tips: [], notice: "找到了线索，但未取得可读的同店正文；不能生成帖子统计或价格估值。可打开来源查看。")
        }
        struct Answer: Decodable, Sendable { let observations: [PlaceObservation] }
        let input = pages.map { "URL：\($0.source.url)\n标题：\($0.source.title)\n网页文本：\($0.text)\n本页实际链接：\($0.links.map { $0.title + " | " + $0.url }.joined(separator: "\n"))" }.joined(separator: "\n\n")
        let answer: Answer
        do {
            answer = try await summarizer.generate(Answer.self, instruction: """
            从提供的可读网页抽取关于 \(city) \(place.name)（\(place.address)）的记录，不能补充常识。
            仅同一家分店；地点身份不明确、主题聚合、无实际体验、广告/转载都不要标为review。最多5篇独立review，商家菜单用menu，官方说明用official，店铺信息用listing，其他other。
            只保留页面明确包含的事实。所有quote必须逐字引用当前页面的一小段文本（20至160字），用于本地检验；不能用自己的话冒充原文。未提及字段用null，数组无内容用[]。推荐理由用中文归纳。
            输出JSON：{"observations":[{"url":"输入URL","venueQuote":"证明具体同店身份的原文","kind":"review/menu/official/listing/other","author":null,"visitDate":null,"dishes":[{"name":"菜名","sentiment":"positive/negative/neutral","reason":"推荐或避坑理由","quote":"支持态度与菜名的原文","priceYuan":null,"priceQuote":null,"unit":null}],"perPersonYuan":null,"perPersonQuote":null,"totalYuan":null,"diners":null,"billQuote":null,"openingHours":null,"openingQuote":null,"tips":[{"advice":"具体游玩建议","quote":"支持建议的原文"}]}]}。
            价格单位为人民币元；有酒水/团购/优惠/套餐等不同口径不混合，不能换算成人均。总价除人数仅限原文明确普通就餐实付与人数。营业原文有冲突分别保留，不能推断今天必定营业。
            每条记录还包含reservation，没查到写null。有依据时结构为{"status":"required/recommended/notRequired/unknown","quote":"说明预约要求的逐字原文或null","entryURL":"本页实际预约链接或输入的店铺页URL或null","entryKind":"booking/merchantPage"}。required必须为明确需要预约；建议预约只用recommended；未提预约不等于无需预约。booking必须选本页实际链接里的预约/预订入口；普通店铺页用merchantPage；社交帖子、搜索页、平台首页都不充当直接预订入口。不得编造URL、库存、日期或预约已完成。
            """, input: input, schema: ResearchSchemas.place)
        } catch is CancellationError { throw CancellationError() }
        catch {
            return PlaceResearchReport(placeID: place.providerID, searchedAt: Date(), sources: batch.sources, readableCount: pages.count, relevantReviewCount: 0, dishes: [], perPersonText: nil, openingText: nil, tips: [], notice: "取得部分网页，但未能可靠整理同店证据；没有补全未知数字。")
        }
        let observations = PlaceResearchValidation.validate(answer.observations, pages: pages, place: place)
        return PlaceResearchValidation.summarize(observations, place: place, sources: batch.sources, readableCount: pages.count)
    }

    static func unavailable(place: TravelPlaceEvidence, notice: String) -> PlaceResearchReport {
        PlaceResearchReport(placeID: place.providerID, searchedAt: Date(), sources: [], readableCount: 0, relevantReviewCount: 0, dishes: [], perPersonText: nil, openingText: nil, tips: [], notice: notice)
    }
}

enum PlaceResearchValidation {
    static func normalized(_ text: String) -> String { text.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression).lowercased() }
    static func containsQuote(_ quote: String?, text: String) -> Bool {
        guard let quote, quote.count >= 4, quote.count <= 180 else { return false }
        return normalized(text).contains(normalized(quote))
    }
    static func money(_ amount: Double?, quote: String?, text: String) -> Double? {
        guard let amount, amount > 0, amount <= 100_000, containsQuote(quote, text: text), let quote,
              ["元", "¥", "￥", "人均"].contains(where: quote.contains) else { return nil }
        let number = amount == amount.rounded() ? String(Int(amount)) : String(amount)
        guard quote.range(of: "(?<![0-9.])" + NSRegularExpression.escapedPattern(for: number) + "(?![0-9.])", options: .regularExpression) != nil else { return nil }
        return amount
    }
    static func validate(_ records: [PlaceObservation], pages: [ReadableResearchPage], place: TravelPlaceEvidence) -> [PlaceObservation] {
        let allowed = Dictionary(uniqueKeysWithValues: pages.map { ($0.source.url, $0.text) })
        var seenURLs = Set<String>(); var seenAuthors = Set<String>(); var seenContent = Set<String>()
        var reviewCount = 0
        return records.compactMap { original in
            var row = original
            guard let text = allowed[row.url], containsQuote(row.venueQuote, text: text),
                  seenURLs.insert(row.url).inserted else { return nil }
            let name = normalized(place.name)
            let quoted = normalized(row.venueQuote)
            // Require the exact POI name or its address, not merely a matching chain name.
            guard quoted.contains(name) || quoted.contains(normalized(place.address)) else { return nil }
            guard ["review", "menu", "official", "listing", "other"].contains(row.kind) else { return nil }
            if row.kind == "review" {
                let fingerprint = normalized(text)
                guard reviewCount < 5, seenContent.insert(fingerprint).inserted else { return nil }
                if let author = row.author, !author.isEmpty {
                    guard seenAuthors.insert(normalized(author)).inserted else { return nil }
                }
                reviewCount += 1
            }
            row.dishes = row.dishes.filter { mention in
                !mention.name.isEmpty && ["positive", "negative", "neutral"].contains(mention.sentiment) &&
                containsQuote(mention.quote, text: text) && normalized(mention.quote).contains(normalized(mention.name))
            }.map { mention in
                DishMention(name: mention.name, sentiment: mention.sentiment, reason: mention.reason, quote: mention.quote,
                            priceYuan: money(mention.priceYuan, quote: mention.priceQuote, text: text), priceQuote: mention.priceQuote, unit: mention.unit)
            }
            let discounts = ["团购", "优惠", "酒水", "套餐", "折扣", "券"]
            row.perPersonYuan = row.perPersonQuote?.contains("人均") == true && !discounts.contains(where: { row.perPersonQuote?.contains($0) == true }) ? money(row.perPersonYuan, quote: row.perPersonQuote, text: text) : nil
            row.totalYuan = money(row.totalYuan, quote: row.billQuote, text: text)
            if let diners = row.diners, diners > 0, diners <= 20, let quote = row.billQuote,
               quote.contains("\(diners)人"), !discounts.contains(where: quote.contains), ["实付", "合计", "总计"].contains(where: quote.contains) { }
            else { row.totalYuan = nil; row.diners = nil }
            if !containsQuote(row.openingQuote, text: text) || !["official", "listing", "menu"].contains(row.kind) ||
                row.openingHours.map({ normalized(row.openingQuote ?? "").contains(normalized($0)) }) != true { row.openingHours = nil }
            row.tips = row.tips.filter { containsQuote($0.quote, text: text) }
            if let page = pages.first(where: { $0.source.url == row.url }) {
                row.reservation = ReservationValidation.validate(row.reservation, page: page)
            }
            return row
        }
    }

    static func summarize(_ observations: [PlaceObservation], place: TravelPlaceEvidence, sources: [ResearchSource], readableCount: Int) -> PlaceResearchReport {
        let reviews = observations.filter { $0.kind == "review" }
        let names = Set(reviews.flatMap { $0.dishes.map(\.name) })
        let dishes = names.compactMap { name -> DishRecommendation? in
            let positives = reviews.filter { $0.dishes.contains { $0.name == name && $0.sentiment == "positive" } }
            let negatives = reviews.filter { $0.dishes.contains { $0.name == name && $0.sentiment == "negative" } }
            guard !positives.isEmpty else { return nil }
            let priced = observations.flatMap { $0.dishes }.filter { $0.name == name && $0.priceYuan != nil }
            let units = Set(priced.compactMap(\.unit))
            let priceText: String?
            if units.count == 1, let unit = units.first, !unit.isEmpty {
                priceText = range(priced.compactMap(\.priceYuan)).map { "参考 \($0)／\(unit)" }
            } else { priceText = nil }
            return DishRecommendation(name: name, reason: positives.first?.dishes.first(where: { $0.name == name && $0.sentiment == "positive" })?.reason ?? "样本中提到", positiveCount: positives.count, negativeCount: negatives.count, sampleCount: reviews.count, priceText: priceText, sourceURLs: positives.map(\.url))
        }.sorted { $0.positiveCount == $1.positiveCount ? $0.name < $1.name : $0.positiveCount > $1.positiveCount }
        let costs = reviews.compactMap { row in row.perPersonYuan ?? (row.totalYuan.flatMap { total in row.diners.map { total / Double($0) } }) }
        let listingCosts = observations.filter { $0.kind == "listing" }.compactMap(\.perPersonYuan)
        let perPerson = range(costs).map { "参考人均 \($0)／人（人民币）" } ?? range(listingCosts).map { "平台展示人均 \($0)／人（人民币，非样本均值）" }
        let hours = Array(Set(observations.compactMap(\.openingHours))).sorted()
        let opening = hours.isEmpty ? nil : (hours.count > 1 ? "来源有不同说法：" : "来源记录：") + hours.joined(separator: "；") + "；出发前复核"
        let tips = Array(Set(observations.flatMap { $0.tips.map(\.advice) })).sorted()
        return PlaceResearchReport(placeID: place.providerID, searchedAt: Date(), sources: sources, readableCount: readableCount,
                                   relevantReviewCount: reviews.count, dishes: Array(dishes.prefix(5)), perPersonText: perPerson,
                                   openingText: opening, tips: Array(tips.prefix(5)),
                                   notice: reviews.count >= 3 ? "基于 \(reviews.count) 篇同店样本归纳，非全平台统计；价格与营业记录不保证当前有效。" : "仅找到 \(reviews.count) 篇可核对的同店体验，未达到 3～5 篇统计要求；以下为有限参考，缺失信息未补全。",
                                   observations: observations, reservation: ReservationValidation.summarize(observations))
    }
    private static func range(_ values: [Double]) -> String? {
        guard let low = values.min(), let high = values.max() else { return nil }
        func amount(_ value: Double) -> String { value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value) }
        return abs(high - low) < 0.01 ? "¥\(amount(low))" : "¥\(amount(low))–\(amount(high))"
    }
}
