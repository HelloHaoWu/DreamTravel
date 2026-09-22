import Foundation

func checkPlaceResearchFixtures() throws {
    let place = TravelPlaceEvidence(providerID: "sample-poi", name: "测试餐厅(湖滨店)", address: "杭州测试路1号", coordinate: TravelCoordinate(longitude: 120, latitude: 30), weeklyOpeningHours: "未知", openingHoursStatus: .unavailable, openingHoursCoverVisit: false, estimatedCostYuan: nil)
    var pages: [ReadableResearchPage] = []
    var records: [PlaceObservation] = []
    for index in 0..<4 {
        let url = "https://www.dianping.com/review/\(index)"
        let title = "就餐记录\(index)"
        let dishQuote = index == 3 ? "招牌鱼不推荐，口感偏柴，单份价格68元" : "招牌鱼推荐，鱼肉鲜嫩，单份价格68元"
        let text = "测试餐厅(湖滨店)这次和朋友吃饭。\(dishQuote)。人均90元。记录编号\(index)不同作者不同经历。"
        pages.append(ReadableResearchPage(source: ResearchSource(title: title, url: url, pageAge: nil), text: text))
        records.append(PlaceObservation(url: url, venueQuote: "测试餐厅(湖滨店)这次和朋友吃饭", kind: "review", author: "author-\(index)", visitDate: nil,
            dishes: [DishMention(name: "招牌鱼", sentiment: index == 3 ? "negative" : "positive", reason: index == 3 ? "口感偏柴" : "鱼肉鲜嫩", quote: dishQuote, priceYuan: 68, priceQuote: "单份价格68元", unit: "份")],
            perPersonYuan: 90, perPersonQuote: "人均90元", totalYuan: nil, diners: nil, billQuote: nil,
            openingHours: "全天营业", openingQuote: "不存在的原文", tips: []))
    }
    let valid = PlaceResearchValidation.validate(records, pages: pages, place: place)
    let result = PlaceResearchValidation.summarize(valid, place: place, sources: pages.map(\.source), readableCount: pages.count)
    precondition(result.relevantReviewCount == 4)
    precondition(result.dishes.first?.positiveCount == 3 && result.dishes.first?.negativeCount == 1)
    precondition(result.dishes.first?.priceText == "参考 ¥68／份")
    precondition(result.perPersonText == "参考人均 ¥90／人（人民币）")
    precondition(result.openingText == nil)
    precondition(PlaceResearchValidation.money(168, quote: "单份价格68元", text: pages[0].text) == nil)
    precondition(PlaceResearchValidation.money(68, quote: "单份价格68元", text: "另一篇无价格") == nil)
    let wrong = TravelPlaceEvidence(providerID: "other", name: "测试餐厅(滨江店)", address: "杭州另一条路2号", coordinate: place.coordinate, weeklyOpeningHours: "未知", openingHoursStatus: .unavailable, openingHoursCoverVisit: false, estimatedCostYuan: nil)
    precondition(PlaceResearchValidation.validate(records, pages: pages, place: wrong).isEmpty)
    let duplicate = PlaceResearchValidation.validate([records[0], records[0]], pages: pages, place: place)
    precondition(duplicate.count == 1)
    let few = PlaceResearchValidation.summarize(duplicate, place: place, sources: pages.map(\.source), readableCount: 4)
    precondition(few.notice.contains("未达到 3～5"))
    let stripped = ResearchPageReader.visibleText("<html><script>虚假菜价99元</script><p>正文价格68元</p></html>")
    precondition(!stripped.contains("99") && stripped.contains("68"))
    precondition(!ResearchPageReader.isAllowed(URL(string: "http://127.0.0.1/test")!))
    precondition(!ResearchPageReader.isAllowed(URL(string: "https://dianping.com.evil.example/test")!))
    print("PLACE_SAME_BRANCH_QUOTES_PRICES_SAMPLE_COUNTS=passed")
}

func checkReservationFixtures() throws {
    let url = "https://www.dianping.com/shop/fixture"
    let text = "测试餐厅(湖滨店)需要预约。周末建议提前预约。午间无需预约。"
    let source = ResearchSource(title: "店铺", url: url, pageAge: nil)
    let links = ReservationValidation.links(in: "<a href='/reserve/fixture'>立即预约</a><a href='javascript:evil()'>预约</a><a href='/rules'>预约须知</a>", base: URL(string: url)!)
    precondition(links.count == 1 && links[0].url == "https://www.dianping.com/reserve/fixture")
    let page = ReadableResearchPage(source: source, text: text, links: links)
    let valid = ReservationValidation.validate(.init(status: .required, quote: "测试餐厅(湖滨店)需要预约", entryURL: links[0].url, entryKind: "booking"), page: page)!
    precondition(valid.status == .required && valid.entryURL != nil)
    let invented = ReservationValidation.validate(.init(status: .required, quote: "店家要求提前一天预订", entryURL: "https://www.dianping.com/reserve/invented", entryKind: "booking"), page: page)!
    precondition(invented.status == .unknown && invented.entryURL == nil)
    let negated = ReservationValidation.validate(.init(status: .required, quote: "午间无需预约", entryURL: nil, entryKind: "merchantPage"), page: page)!
    precondition(negated.status == .unknown)
    for quote in ["非预约制", "不需要提前预约", "无需提前预订"] {
        let negativePage = ReadableResearchPage(source: source, text: quote)
        precondition(ReservationValidation.validate(.init(status: .required, quote: quote, entryURL: nil, entryKind: "merchantPage"), page: negativePage)?.status == .unknown)
        precondition(ReservationValidation.validate(.init(status: .notRequired, quote: quote, entryURL: nil, entryKind: "merchantPage"), page: negativePage)?.status == .notRequired)
    }
    let noRequirement = ReservationValidation.validate(.init(status: .notRequired, quote: "周末建议提前预约", entryURL: nil, entryKind: "merchantPage"), page: page)!
    precondition(noRequirement.status == .unknown)
    let advisory = ReservationValidation.validate(.init(status: .recommended, quote: "周末建议提前预约", entryURL: nil, entryKind: "merchantPage"), page: page)!
    precondition(advisory.status == .recommended)
    precondition(!ReservationValidation.isMerchantPage("https://www.xiaohongshu.com/explore/test"))
    precondition(!ReservationValidation.isMerchantPage("https://dianping.com.evil.example/shop/1"))
    precondition(!ReservationValidation.isMerchantPage("https://m.ctrip.com/html5/hotel/"))
    precondition(ReservationValidation.isMerchantPage("https://m.ctrip.com/html5/hotel/hoteldetail/123.html"))
    var rows: [PlaceObservation] = []
    for item in [valid, ReservationObservation(status: .notRequired, quote: "午间无需预约", entryURL: nil, entryKind: "merchantPage")] {
        rows.append(PlaceObservation(url: url, venueQuote: "测试餐厅(湖滨店)", kind: "listing", author: nil, visitDate: nil, dishes: [], perPersonYuan: nil, perPersonQuote: nil, totalYuan: nil, diners: nil, billQuote: nil, openingHours: nil, openingQuote: nil, tips: [], reservation: item))
    }
    let summary = ReservationValidation.summarize(rows)
    precondition(summary.status == .conflicting && summary.entries.contains { $0.kind == "booking" })
    precondition(ReservationValidation.summarize([]).status == .unknown)
    print("RESERVATION_QUOTES_NEGATION_CONFLICT_REAL_LINKS=passed")
}
