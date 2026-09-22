import Foundation

enum MapDestination {
    static func amapURL(for stop: ItineraryStop) -> URL {
        makeURL(
            base: "https://uri.amap.com/search",
            items: [
                URLQueryItem(name: "keyword", value: searchText(for: stop)),
                URLQueryItem(name: "city", value: stop.city),
                URLQueryItem(name: "view", value: "map"),
                URLQueryItem(name: "src", value: "webapp.dreamtravel.prototype"),
                URLQueryItem(name: "callnative", value: "1")
            ]
        )
    }

    static func baiduURL(for stop: ItineraryStop) -> URL {
        makeURL(
            base: "https://api.map.baidu.com/place/search",
            items: [
                URLQueryItem(name: "query", value: searchText(for: stop)),
                URLQueryItem(name: "region", value: stop.city),
                URLQueryItem(name: "output", value: "html"),
                URLQueryItem(name: "src", value: "webapp.dreamtravel.prototype")
            ]
        )
    }

    private static func searchText(for stop: ItineraryStop) -> String {
        [stop.place, stop.address].compactMap { $0 }.joined(separator: " ")
    }

    private static func makeURL(base: String, items: [URLQueryItem]) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = items
        return components.url!
    }
}
