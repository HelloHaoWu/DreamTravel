import Foundation

enum ReservationStatus: String, Codable, Hashable, Sendable {
    case unknown, required, recommended, notRequired, conflicting
    var label: String {
        switch self {
        case .unknown: "未查到预约要求"
        case .required: "需要提前预约"
        case .recommended: "建议提前预约"
        case .notRequired: "来源说明无需预约"
        case .conflicting: "预约说法不一致"
        }
    }
}

struct ReservationObservation: Codable, Hashable, Sendable {
    var status: ReservationStatus
    var quote: String?
    var entryURL: String?
    var entryKind: String
}
struct ResearchPageLink: Hashable, Sendable {
    let title: String
    let url: String
}
struct PlaceBookingEntry: Codable, Hashable, Identifiable, Sendable {
    var id: String { url }
    let url: String
    let kind: String
    let sourceURL: String
    var title: String {
        switch kind {
        case "booking": "打开预约／预订页面"
        case "reference": "查看原始来源"
        case "platform": "平台入口"
        default: "查看店铺与预订"
        }
    }
    var host: String { URL(string: url)?.host ?? "来源平台" }
}
struct ReservationClaim: Codable, Hashable, Sendable {
    let status: ReservationStatus
    let quote: String
    let sourceURL: String
}
struct PlaceReservation: Codable, Hashable, Sendable {
    let status: ReservationStatus
    let claims: [ReservationClaim]
    let entries: [PlaceBookingEntry]
    static let unknown = PlaceReservation(status: .unknown, claims: [], entries: [])
    var explanation: String {
        switch status {
        case .unknown: "还没有取得这家店明确的预约规定，不代表可以直接到店。可打开平台联系商家。"
        case .required: "来源记录要求预约；请在平台选择日期、人数或场次，并以确认结果为准。"
        case .recommended: "来源建议提前预约，尤其是周末；是否仍有位置需在平台查看。"
        case .notRequired: "来源写明无需预约；日期、节假日或特殊活动可能有不同安排。"
        case .conflicting: "不同来源对预约的说法不同，请先联系商家确认，避免白跑。"
        }
    }
}

enum ReservationValidation {
    static func publicURL(_ value: String) -> URL? {
        guard let url = ResearchURL.validated(value), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }
    static func isBookingLabel(_ text: String) -> Bool {
        let excluded = ["须知", "规则", "政策", "帮助", "攻略", "问答", "说明", "取消", "我的订单"]
        return !excluded.contains(where: text.contains) && ["预约", "预订", "订座", "订房", "购票"].contains(where: text.contains)
    }
    static func isMerchantPage(_ raw: String) -> Bool {
        guard let url = publicURL(raw), let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()
        func domain(_ name: String) -> Bool { host == name || host.hasSuffix("." + name) }
        if domain("dianping.com") { return path.contains("/shop/") }
        if domain("meituan.com") { return path.contains("/poi/") || path.contains("/merchant/") || path.contains("/hotel/") }
        if domain("ctrip.com") || domain("trip.com") {
            return path.contains("/fooddetail/") || path.contains("/foods/") || path.contains("/hoteldetail") || path.contains("/hotel-detail-") || (host.hasPrefix("hotels.") && path.contains("/hotels/"))
        }
        return false
    }
    static func validate(_ original: ReservationObservation?, page: ReadableResearchPage) -> ReservationObservation? {
        guard var row = original else { return nil }
        let quote = row.quote ?? ""
        let noBooking = ["无需预约", "不用预约", "免预约", "不需预约", "无需预订", "不需要预约", "不用提前预约", "无需提前预约", "不需要提前预约", "非预约制", "不实行预约制", "无需提前预订", "不用提前预订", "不需要提前预订"].contains(where: quote.contains)
        let advice = ["建议", "最好", "推荐"].contains(where: quote.contains)
        let must = ["必须预约", "须提前预约", "需提前预约", "需要预约", "预约制", "预约入馆", "请提前预约", "提前预订", "必须预订"].contains(where: quote.contains)
        let quoted = PlaceResearchValidation.containsQuote(row.quote, text: page.text) && !quote.contains("？") && !quote.contains("?")
        switch row.status {
        case .notRequired: if !quoted || !noBooking { row.status = .unknown }
        case .required: if !quoted || noBooking || advice || !must { row.status = .unknown }
        case .recommended: if !quoted || noBooking || !advice || !["预约", "预订", "订座", "订房"].contains(where: quote.contains) { row.status = .unknown }
        default: row.status = .unknown
        }
        if row.status == .unknown { row.quote = nil }
        if let raw = row.entryURL, let url = publicURL(raw) {
            if row.entryKind == "booking" {
                let host = url.host?.lowercased() ?? ""
                let sameHost = host == URL(string: page.source.url)?.host?.lowercased()
                let platform = ["dianping.com", "meituan.com", "ctrip.com", "trip.com", "damai.cn", "maoyan.com"].contains { host == $0 || host.hasSuffix("." + $0) }
                guard (sameHost || platform), page.links.contains(where: { $0.url == url.absoluteString && isBookingLabel($0.title) }) else {
                    row.entryURL = nil; return row
                }
            } else if row.entryKind == "merchantPage" {
                guard raw == page.source.url, isMerchantPage(raw) else { row.entryURL = nil; return row }
            } else { row.entryURL = nil }
        } else { row.entryURL = nil }
        return row
    }
    static func summarize(_ observations: [PlaceObservation]) -> PlaceReservation {
        let claims = observations.compactMap { row -> ReservationClaim? in
            guard let item = row.reservation, item.status != .unknown, let quote = item.quote else { return nil }
            return ReservationClaim(status: item.status, quote: quote, sourceURL: row.url)
        }
        let statuses = Set(claims.map(\.status))
        let status: ReservationStatus = statuses.contains(.required) && statuses.contains(.notRequired) ? .conflicting :
            statuses.contains(.required) ? .required : statuses.contains(.recommended) ? .recommended : statuses.contains(.notRequired) ? .notRequired : .unknown
        var seen = Set<String>()
        let entries = observations.compactMap { row -> PlaceBookingEntry? in
            if let reservation = row.reservation, let url = reservation.entryURL, seen.insert(url).inserted {
                return PlaceBookingEntry(url: url, kind: reservation.entryKind, sourceURL: row.url)
            }
            if ["listing", "menu"].contains(row.kind), isMerchantPage(row.url), seen.insert(row.url).inserted {
                return PlaceBookingEntry(url: row.url, kind: "merchantPage", sourceURL: row.url)
            }
            return nil
        }.sorted { $0.kind == "booking" && $1.kind != "booking" }
        return PlaceReservation(status: status, claims: claims, entries: entries)
    }
    static func links(in html: String, base: URL) -> [ResearchPageLink] {
        guard let regex = try? NSRegularExpression(pattern: "(?is)<a\\b[^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>") else { return [] }
        let text = html as NSString
        var seen = Set<String>()
        return regex.matches(in: html, range: NSRange(location: 0, length: text.length)).compactMap { match in
            let label = ResearchPageReader.visibleText(text.substring(with: match.range(at: 2)))
            let href = text.substring(with: match.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")
            guard label.count <= 80, isBookingLabel(label),
                  let url = URL(string: href, relativeTo: base)?.absoluteURL,
                  publicURL(url.absoluteString) != nil, seen.insert(url.absoluteString).inserted else { return nil }
            return ResearchPageLink(title: label, url: url.absoluteString)
        }.prefix(15).map { $0 }
    }
}
