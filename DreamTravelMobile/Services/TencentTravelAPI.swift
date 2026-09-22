import Foundation

struct TencentPlaceRecord: Sendable {
    let id: String
    let name: String
    let address: String
    let coordinate: TravelCoordinate

    var endpoint: TravelEndpointEvidence {
        TravelEndpointEvidence(name: name, address: address, coordinate: coordinate)
    }
}

actor TencentTravelAPI {
    private let key: String
    private let transport: TravelHTTPTransport
    private var lastRequestAt: Date?

    init(key: String, transport: TravelHTTPTransport = .live) {
        self.key = key
        self.transport = transport
    }

    func geocode(city: String) async throws -> TravelCoordinate {
        let data = try await get(
            path: "/ws/geocoder/v1/",
            parameters: [URLQueryItem(name: "address", value: city)]
        )
        let root = try Self.validatedObject(data)
        guard let result = root["result"] as? [String: Any],
              let coordinate = Self.coordinate(result["location"]) else {
            throw TravelProviderError.missingEvidence("无法从腾讯位置服务获取城市坐标，请确认城市名称。")
        }
        return coordinate
    }

    func search(query: String, city: String) async throws -> [TencentPlaceRecord] {
        let data = try await get(
            path: "/ws/place/v1/search",
            parameters: [
                URLQueryItem(name: "boundary", value: "region(\(city),0)"),
                URLQueryItem(name: "keyword", value: query),
                URLQueryItem(name: "page_size", value: "20")
            ]
        )
        return try Self.parsePlaces(data)
    }

    func searchNearby(query: String, center: TravelCoordinate) async throws -> [TencentPlaceRecord] {
        let data = try await get(
            path: "/ws/place/v1/search",
            parameters: [
                URLQueryItem(name: "boundary", value: "nearby(\(center.tencentQueryValue),3000,0)"),
                URLQueryItem(name: "keyword", value: query),
                URLQueryItem(name: "orderby", value: "_distance"),
                URLQueryItem(name: "page_size", value: "20")
            ]
        )
        return try Self.parsePlaces(data)
    }

    func nearbyTransitStation(near coordinate: TravelCoordinate) async throws -> TencentPlaceRecord {
        let results = try await searchNearby(query: "地铁站", center: coordinate)
        guard let station = results.first(where: {
            !$0.address.isEmpty && ($0.name.contains("地铁") || $0.name.contains("站"))
        }) else {
            throw TravelProviderError.missingEvidence("附近没有可核实的地铁会合点，请换一个区域。")
        }
        return station
    }

    func travelRoute(
        from origin: TravelCoordinate,
        to destination: TravelCoordinate
    ) async throws -> TravelRouteEvidence {
        let walking = try await route(
            path: "/ws/direction/v1/walking/",
            from: origin,
            to: destination,
            method: "步行"
        )
        if walking.distanceMeters <= 2_200 { return walking }
        return try await route(
            path: "/ws/direction/v1/driving/",
            from: origin,
            to: destination,
            method: "打车"
        )
    }

    /// Query walking first; short walks need neither alternative requests nor extra UI.
    func travelRouteOptions(from origin: TravelCoordinate, to destination: TravelCoordinate) async throws -> TravelRouteEvidence {
        var options: [TravelModeOption] = []
        for mode in TravelMode.allCases {
            try Task.checkCancellation()
            do {
                let value = try await route(path: "/ws/direction/v1/\(mode.rawValue)/", from: origin, to: destination, method: mode.title)
                options.append(.init(mode: mode, distanceMeters: value.distanceMeters, durationSeconds: value.durationSeconds))
                if mode == .walking && value.durationSeconds < 8 * 60 { break }
            } catch is CancellationError { throw CancellationError() }
            catch {
                options.append(.init(mode: mode, distanceMeters: nil, durationSeconds: nil,
                    unavailableReason: "腾讯未返回可用的\(mode.title)路线，可能受道路、接口权限或网络影响。"))
            }
        }
        let defaultOption = TravelModePolicy.recommended(options)
        guard let selected = defaultOption, let distance = selected.distanceMeters, let duration = selected.durationSeconds else {
            throw TravelProviderError.missingEvidence("没有合适的交通路线：步行不能超过15分钟，骑行或驾车也未返回可用路线，请换附近地点。")
        }
        return TravelRouteEvidence(distanceMeters: distance, durationSeconds: duration, method: selected.mode.title, alternatives: options)
    }

    func forecast(
        city: String,
        coordinate: TravelCoordinate,
        visitTime: Date
    ) async throws -> WeatherEvidenceSummary {
        let hourlyData = try await get(
            path: "/ws/weather/v1/",
            parameters: [
                URLQueryItem(name: "location", value: coordinate.tencentQueryValue),
                URLQueryItem(name: "type", value: "hours")
            ]
        )
        let futureData = try await get(
            path: "/ws/weather/v1/",
            parameters: [
                URLQueryItem(name: "location", value: coordinate.tencentQueryValue),
                URLQueryItem(name: "type", value: "future"),
                URLQueryItem(name: "get_md", value: "1")
            ]
        )
        return try Self.parseForecast(
            hourlyData: hourlyData,
            futureData: futureData,
            city: city,
            visitTime: visitTime,
            fetchedAt: Date()
        )
    }

    private func route(
        path: String,
        from origin: TravelCoordinate,
        to destination: TravelCoordinate,
        method: String
    ) async throws -> TravelRouteEvidence {
        let data = try await get(
            path: path,
            parameters: [
                URLQueryItem(name: "from", value: origin.tencentQueryValue),
                URLQueryItem(name: "to", value: destination.tencentQueryValue)
            ]
        )
        let root = try Self.validatedObject(data)
        guard let result = root["result"] as? [String: Any],
              let routes = result["routes"] as? [[String: Any]],
              let first = routes.first,
              let distance = Self.int(first["distance"]),
              let durationMinutes = Self.number(first["duration"]),
              distance >= 0,
              durationMinutes.isFinite, (0...10_080).contains(durationMinutes) else {
            throw TravelProviderError.missingEvidence("腾讯位置服务没有返回完整的路线距离和耗时。")
        }
        return TravelRouteEvidence(
            distanceMeters: distance,
            durationSeconds: Int(ceil(durationMinutes * 60)),
            method: method
        )
    }

    private func get(path: String, parameters: [URLQueryItem]) async throws -> Data {
        try await respectFreeQuotaRateLimit()
        var components = URLComponents()
        components.scheme = "https"
        components.host = "apis.map.qq.com"
        components.path = path
        components.queryItems = parameters + [URLQueryItem(name: "key", value: key)]
        guard let url = components.url else { throw TravelProviderError.invalidRequest }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try await transport.send(request)
        guard (200..<300).contains(response.status) else {
            throw TravelProviderError.unavailable("腾讯位置服务")
        }
        return response.data
    }

    private func respectFreeQuotaRateLimit() async throws {
        if let lastRequestAt {
            let remaining = 0.22 - Date().timeIntervalSince(lastRequestAt)
            if remaining > 0 {
                try await Task.sleep(for: .seconds(remaining))
            }
        }
        lastRequestAt = Date()
    }

    static func parsePlaces(_ data: Data) throws -> [TencentPlaceRecord] {
        let root = try validatedObject(data)
        guard let records = root["data"] as? [[String: Any]] else { return [] }
        return records.compactMap { record in
            guard let id = string(record["id"]), !id.isEmpty,
                  let name = string(record["title"]), !name.isEmpty,
                  let address = string(record["address"]), !address.isEmpty,
                  let coordinate = coordinate(record["location"]) else { return nil }
            return TencentPlaceRecord(
                id: id,
                name: name,
                address: address,
                coordinate: coordinate
            )
        }
    }

    static func parseForecast(
        hourlyData: Data,
        futureData: Data,
        city: String,
        visitTime: Date,
        fetchedAt: Date
    ) throws -> WeatherEvidenceSummary {
        let hourlyRoot = try validatedObject(hourlyData)
        let futureRoot = try validatedObject(futureData)
        let hourlyInfos = nestedInfos(in: hourlyRoot, key: "forecast_hours")
        let dailyInfos = nestedInfos(in: futureRoot, key: "forecast")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let targetDay = calendar.startOfDay(for: visitTime)
        let targetHour = calendar.component(.hour, from: visitTime)

        let daily = dailyInfos.first { item in
            guard let value = string(item["date"]),
                  let date = date(value, format: "yyyy-MM-dd") else { return false }
            return calendar.startOfDay(for: date) == targetDay
        }
        guard let daily,
              let period = daily[targetHour >= 6 && targetHour < 18 ? "day" : "night"] as? [String: Any],
              let dailyCondition = string(period["weather"]),
              let dailyTemperature = number(period["temperature"]),
              let humidity = int(period["humidity"]),
              (0...100).contains(humidity) else {
            throw TravelProviderError.missingEvidence("腾讯天气没有覆盖行程日期的温度和湿度。")
        }

        let nearestHourly = hourlyInfos.compactMap { item -> (Date, [String: Any])? in
            guard let value = string(item["hour"]),
                  let time = date(value, format: "yyyy-MM-dd HH:mm:ss"),
                  let info = item["info"] as? [String: Any] else { return nil }
            return (time, info)
        }.filter { calendar.isDate($0.0, inSameDayAs: visitTime) }
            .min { abs($0.0.timeIntervalSince(visitTime)) < abs($1.0.timeIntervalSince(visitTime)) }

        let hourlyIsClose = nearestHourly.map { abs($0.0.timeIntervalSince(visitTime)) <= 90 * 60 } ?? false
        let condition = hourlyIsClose
            ? (string(nearestHourly?.1["weather"]) ?? dailyCondition)
            : dailyCondition
        let temperature = hourlyIsClose
            ? (number(nearestHourly?.1["temperature"]) ?? dailyTemperature)
            : dailyTemperature

        return WeatherEvidenceSummary(
            city: city,
            forecastFor: visitTime,
            condition: condition,
            temperatureCelsius: temperature,
            feelsLikeCelsius: nil,
            humidityPercent: humidity,
            precipitationProbabilityPercent: nil,
            metadata: EvidenceMetadata(
                provider: hourlyIsClose ? "腾讯天气逐小时温度＋日夜湿度" : "腾讯天气日夜预报",
                origin: .liveAPI,
                fetchedAt: fetchedAt,
                validUntil: fetchedAt.addingTimeInterval(30 * 60)
            ),
            sourceAttributions: ["https://lbs.qq.com/service/webService/webServiceGuide/weatherinfo"]
        )
    }

    private static func nestedInfos(in root: [String: Any], key: String) -> [[String: Any]] {
        guard let result = root["result"] as? [String: Any],
              let containers = result[key] as? [[String: Any]],
              let first = containers.first,
              let infos = first["infos"] as? [[String: Any]] else { return [] }
        return infos
    }

    private static func validatedObject(_ data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TravelProviderError.unavailable("腾讯位置服务")
        }
        guard int(root["status"]) == 0 else {
            let message = string(root["message"]) ?? "请求失败"
            throw TravelProviderError.missingEvidence("腾讯位置服务：\(message)")
        }
        return root
    }

    private static func coordinate(_ value: Any?) -> TravelCoordinate? {
        guard let object = value as? [String: Any],
              let longitude = number(object["lng"]),
              let latitude = number(object["lat"]),
              (-180...180).contains(longitude),
              (-90...90).contains(latitude) else { return nil }
        return TravelCoordinate(longitude: longitude, latitude: latitude)
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func date(_ value: String, format: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = format
        return formatter.date(from: value)
    }
}

actor TencentLiveTravelToolService: TravelToolService {
    private let api: TencentTravelAPI
    private var preparedTrips: [UUID: TencentPreparedTrip] = [:]
    private var catalog: [TencentPlaceRecord] = []
    private var catalogFetchedAt: Date?
    private var inspirationAnchorID: String?

    init(key: String, transport: TravelHTTPTransport = .live) {
        api = TencentTravelAPI(key: key, transport: transport)
    }

    func resolveWeather(for intent: TripIntent) async throws -> WeatherEvidenceSummary {
        let coordinate = try await api.geocode(city: intent.city)
        return try await api.forecast(
            city: intent.city,
            coordinate: coordinate,
            visitTime: intent.scheduledStart
        )
    }

    func availablePlaceHints(for intent: TripIntent, inspiration: DiscoveryIdea?) async throws -> String {
        let fetchedAt = Date()
        var inspirationPlaces: [TencentPlaceRecord] = []
        for term in inspiration?.searchTerms.prefix(3) ?? [] {
            try Task.checkCancellation()
            let matches = try await api.search(query: term, city: intent.city)
            inspirationPlaces += matches.prefix(3)
            if !inspirationPlaces.isEmpty { break }
        }
        let center: TravelCoordinate
        if let anchor = inspirationPlaces.first { center = anchor.coordinate }
        else { center = try await api.geocode(city: intent.city) }
        var found: [TencentPlaceRecord] = []
        var rows: [String] = []
        var seen = Set<String>()
        // The searched activity establishes this plan's area; all backup places stay nearby.
        for place in inspirationPlaces where seen.insert(place.id).inserted {
            found.append(place)
            rows.append("[本主题搜索地点，优先保留为第二段默认体验] \(place.name) | \(place.address)")
        }
        if let anchor = inspirationPlaces.first {
            rows.append("本方案以 \(anchor.name) 为主题核心。默认组合应包含它，其他体验和晚餐围绕它就近安排；不能把真实搜到的核心玩法换成无关茶馆。")
        }
        for category in ["书店", "美术馆", "博物馆", "咖啡", "茶馆", "陶艺", "公园", "餐厅"] {
            try Task.checkCancellation()
            let matches = try await api.searchNearby(query: category, center: center)
            for place in matches.prefix(category == "餐厅" ? 18 : 10) where seen.insert(place.id).inserted {
                found.append(place)
                rows.append("[\(category)] \(place.name) | \(place.address)")
            }
        }
        guard found.count >= 9 else { throw TravelProviderError.missingEvidence("这种玩法附近真实可选地点不足以组成完整备选，请换一个城市或区域。") }
        try Task.checkCancellation()
        catalog = found
        catalogFetchedAt = fetchedAt
        inspirationAnchorID = inspirationPlaces.first?.id
        return rows.joined(separator: "\n")
    }

    func resolveCandidates(for draft: TripDraftManifest) async throws -> CandidateEvidenceSummary {
        let fetchedAt = draft.requiresThematicMatch ? (catalogFetchedAt ?? Date()) : Date()
        var places: [[TravelPlaceEvidence]] = []
        var usedIDs = Set(draft.excludedPlaceIDs)
        var activityCenter: TravelCoordinate?

        for (slotIndex, slot) in draft.planningBrief.slots.enumerated() {
            var row: [TravelPlaceEvidence] = []
            for query in slot.searchQueries {
                try Task.checkCancellation()
                var results: [TencentPlaceRecord] = []
                if draft.requiresThematicMatch, !catalog.isEmpty {
                    results = catalog.filter { $0.name == query && !usedIDs.contains($0.id) }
                    guard !results.isEmpty else {
                        throw TravelProviderError.missingEvidence("候选“\(query)”不在可选真实地点清单内或已被使用，请从清单换一个。")
                    }
                } else {
                for searchTerm in TencentSearchQueryPolicy.searchTerms(
                    from: query,
                    slotIndex: slotIndex,
                    strict: draft.requiresThematicMatch
                ) {
                    results = if let activityCenter {
                        try await api.searchNearby(query: searchTerm, center: activityCenter)
                    } else {
                        try await api.search(query: searchTerm, city: draft.intent.city)
                    }
                    if results.contains(where: { !usedIDs.contains($0.id) }) {
                        break
                    }
                }
                }
                guard let chosen = results.first(where: { !usedIDs.contains($0.id) }) else {
                    throw TravelProviderError.missingEvidence("腾讯位置服务没有为“\(query)”返回新的可用地点，请换一个搜索方向。")
                }
                usedIDs.insert(chosen.id)
                if activityCenter == nil { activityCenter = chosen.coordinate }
                row.append(TravelPlaceEvidence(
                    providerID: chosen.id,
                    name: chosen.name,
                    address: chosen.address,
                    coordinate: chosen.coordinate,
                    weeklyOpeningHours: "腾讯免费地点接口未提供营业时间，出发前需核实",
                    openingHoursStatus: .unavailable,
                    openingHoursCoverVisit: false,
                    estimatedCostYuan: nil
                ))
            }
            places.append(row)
        }

        guard let primarySelection = draft.planningBrief.variants.first?.selection,
              primarySelection.count == places.count, (3...5).contains(places.count),
              places.enumerated().allSatisfy({ $0.element.indices.contains(primarySelection[$0.offset]) }) else {
            throw TravelProviderError.missingEvidence("腾讯位置服务没有返回完整的三至五段候选地点。")
        }
        if draft.requiresThematicMatch, let anchorID = inspirationAnchorID {
            let primaryIDs = places.enumerated().compactMap { slot, row in
                row.indices.contains(primarySelection[slot]) ? row[primarySelection[slot]].providerID : nil
            }
            guard primaryIDs.contains(anchorID) else {
                throw TravelProviderError.missingEvidence("默认行程未包含清单中标注的本主题核心地点，必须保留搜索到的新玩法。")
            }
        }
        let first = places[0][primarySelection[0]]
        let lastIndex = places.count - 1
        let last = places[lastIndex][primarySelection[lastIndex]]
        let meeting = try await api.nearbyTransitStation(near: first.coordinate)
        let ending = try await api.nearbyTransitStation(near: last.coordinate)
        let prepared = TencentPreparedTrip(
            places: places,
            meeting: meeting.endpoint,
            ending: ending.endpoint
        )
        preparedTrips[draft.runID] = prepared

        return CandidateEvidenceSummary(
            resolvedCandidateCount: places.flatMap { $0 }.count,
            verifiedAddressCount: places.flatMap { $0 }.count,
            verifiedOpeningHoursCount: 0,
            unresolvedFactCount: 0,
            metadata: EvidenceMetadata(
                provider: "腾讯位置服务地点搜索",
                origin: .liveAPI,
                fetchedAt: fetchedAt,
                validUntil: fetchedAt.addingTimeInterval(60 * 60)
            ),
            places: places,
            meetingPoint: prepared.meeting,
            endingPoint: prepared.ending
        )
    }

    func resolveConnections(for draft: TripDraftManifest) async throws -> RouteEvidenceSummary {
        let fetchedAt = Date()
        defer { preparedTrips[draft.runID] = nil }
        guard let prepared = preparedTrips[draft.runID],
              prepared.places.count == draft.slotCount, (3...5).contains(draft.slotCount),
              prepared.places.allSatisfy({ $0.count == 3 }) else {
            throw TravelProviderError.missingEvidence("地点尚未解析，不能开始计算路线。")
        }

        var edges: [(TravelCoordinate, TravelCoordinate)] = []
        edges += prepared.places[0].map { (prepared.meeting.coordinate, $0.coordinate) }
        for slot in 0..<(prepared.places.count - 1) {
            for from in prepared.places[slot] {
                for to in prepared.places[slot + 1] {
                    edges.append((from.coordinate, to.coordinate))
                }
            }
        }
        edges += prepared.places[prepared.places.count - 1].map { ($0.coordinate, prepared.ending.coordinate) }
        guard edges.count == draft.requiredConnectionCount else {
            throw TravelProviderError.missingEvidence("候选路线数量与规划草案不一致。")
        }

        var routes: [TravelRouteEvidence] = []
        routes.reserveCapacity(edges.count)
        for edge in edges {
            try Task.checkCancellation()
            routes.append(try await api.travelRouteOptions(from: edge.0, to: edge.1))
        }
        let matrix = TripRouteEvidenceMatrix(
            meetingToFirst: Array(routes[0..<3]),
            betweenSlots: (0..<(prepared.places.count - 1)).map { slot in
                (0..<3).map { from in
                    let start = 3 + slot * 9 + from * 3
                    return Array(routes[start..<(start + 3)])
                }
            },
            lastToEnding: Array(routes.suffix(3))
        )
        preparedTrips[draft.runID] = nil
        return RouteEvidenceSummary(
            resolvedConnectionCount: routes.count,
            unresolvedFactCount: 0,
            metadata: EvidenceMetadata(
                provider: "腾讯位置服务路线规划",
                origin: .liveAPI,
                fetchedAt: fetchedAt,
                validUntil: fetchedAt.addingTimeInterval(15 * 60)
            ),
            matrix: matrix
        )
    }
}

private struct TencentPreparedTrip: Sendable {
    let places: [[TravelPlaceEvidence]]
    let meeting: TravelEndpointEvidence
    let ending: TravelEndpointEvidence
}

enum TencentSearchQueryPolicy {
    static func searchTerms(from query: String, slotIndex: Int, strict: Bool = false) -> [String] {
        let slotFallback = ["咖啡店", "休闲娱乐", "餐厅"][min(max(slotIndex, 0), 2)]
        let related: [String]
        if strict, ["妆造", "汉服", "写真"].contains(where: query.contains) { related = ["汉服", "摄影工作室"] }
        else if strict, ["艺术空间", "艺术馆", "展览", "画廊"].contains(where: query.contains) { related = ["美术馆", "画廊"] }
        else if strict, ["手作", "手工", "陶艺", "DIY"].contains(where: query.contains) { related = ["陶艺", "手工", "DIY"] }
        else { related = [] }
        var terms: [String] = []
        for term in [query, poiCategory(from: query)] + related + (strict ? [] : [slotFallback])
            where !term.isEmpty && !terms.contains(term) {
            terms.append(term)
        }
        return terms
    }

    static func poiCategory(from query: String) -> String {
        let knownCategories = [
            "甜品店", "咖啡馆", "咖啡店", "茶馆", "餐厅", "美术馆", "博物馆",
            "展览", "书店", "市集", "手作", "羽毛球馆", "电影院", "公园", "酒吧", "妆造", "汉服", "陶艺", "摄影工作室"
        ]
        if let category = knownCategories.first(where: { query.contains($0) }) {
            return category
        }
        let ignored = ["周边", "附近", "室内", "室外", "安静", "浪漫", "约会"]
        let tokens = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return tokens.reversed().first(where: { token in
            token.count >= 2 && !ignored.contains(where: { token.contains($0) })
        }) ?? query
    }
}
