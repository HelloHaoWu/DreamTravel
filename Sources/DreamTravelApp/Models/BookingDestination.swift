import Foundation

enum BookingCategory: String, CaseIterable, Identifiable {
    case tickets
    case dining
    case hotel
    case transport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tickets: "门票玩乐"
        case .dining: "餐厅"
        case .hotel: "酒店"
        case .transport: "交通"
        }
    }

    var symbol: String {
        switch self {
        case .tickets: "ticket"
        case .dining: "fork.knife"
        case .hotel: "bed.double"
        case .transport: "train.side.front.car"
        }
    }
}

struct BookingDestination: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let url: URL
}

enum BookingCatalog {
    static func destinations(for category: BookingCategory, city: String) -> [BookingDestination] {
        switch category {
        case .tickets:
            return [
                destination(
                    "ctrip-tickets", "携程", "景点门票与当地玩乐", "ticket.fill",
                    city == "杭州" ? "https://you.ctrip.com/sightlist/hangzhou14.html" : "https://piao.ctrip.com/"
                ),
                destination("meituan-play", "美团", "本地休闲与团购", "mappin.and.ellipse", "https://i.meituan.com/"),
                destination("damai", "大麦", "演出与现场活动", "music.note", "https://www.damai.cn/")
            ]
        case .dining:
            let dianpingCity = ["杭州": "hangzhou", "上海": "shanghai", "苏州": "suzhou"][city] ?? "hangzhou"
            return [
                destination("dianping", "大众点评", "餐厅评价与订座线索", "fork.knife", "https://www.dianping.com/\(dianpingCity)"),
                destination("meituan-food", "美团", "餐饮团购与套餐", "takeoutbag.and.cup.and.straw", "https://i.meituan.com/")
            ]
        case .hotel:
            return [
                destination(
                    "ctrip-hotel", "携程酒店", "房型、价格与预订", "bed.double.fill",
                    city == "杭州" ? "https://hotels.ctrip.com/hotel/city17" : "https://hotels.ctrip.com/"
                ),
                destination("meituan-hotel", "美团酒店", "本地住宿与套餐", "building.2", "https://i.meituan.com/")
            ]
        case .transport:
            return [
                destination("railway-12306", "铁路 12306", "官方火车票入口", "train.side.front.car", "https://www.12306.cn/index/"),
                destination("ctrip-flight", "携程机票", "国内与国际航班", "airplane", "https://flights.ctrip.com/booking/china-city-flights-sitemap.html")
            ]
        }
    }

    private static func destination(
        _ id: String,
        _ title: String,
        _ subtitle: String,
        _ symbol: String,
        _ urlString: String
    ) -> BookingDestination {
        BookingDestination(
            id: id,
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            url: URL(string: urlString)!
        )
    }
}
