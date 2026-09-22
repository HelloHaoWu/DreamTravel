import CoreLocation
import Foundation
import UIKit

enum MobileMapProvider {
    case amap
    case baidu
}

@MainActor
enum MobileMapLauncher {
    static func open(_ provider: MobileMapProvider, stop: MobileStop, coordinate: CLLocationCoordinate2D?) {
        let probeURL = URL(string: provider == .amap ? "iosamap://" : "baidumap://")!

        if UIApplication.shared.canOpenURL(probeURL), let nativeURL = nativeURL(for: provider, stop: stop, coordinate: coordinate) {
            UIApplication.shared.open(nativeURL, options: [:])
        } else {
            UIApplication.shared.open(webURL(for: provider, stop: stop), options: [:])
        }
    }

    private static func nativeURL(
        for provider: MobileMapProvider,
        stop: MobileStop,
        coordinate: CLLocationCoordinate2D?
    ) -> URL? {
        switch provider {
        case .amap:
            guard let selectedCoordinate = stop.gcj02Coordinate.map({
                (latitude: $0.latitude, longitude: $0.longitude, dev: "0")
            }) ?? coordinate.map({
                (latitude: $0.latitude, longitude: $0.longitude, dev: "1")
            }) else { return nil }
            return makeURL(
                scheme: "iosamap", host: "viewMap", path: "",
                items: [
                    URLQueryItem(name: "sourceApplication", value: "DreamTravel"),
                    URLQueryItem(name: "poiname", value: stop.place),
                    URLQueryItem(name: "lat", value: String(selectedCoordinate.latitude)),
                    URLQueryItem(name: "lon", value: String(selectedCoordinate.longitude)),
                    URLQueryItem(name: "dev", value: selectedCoordinate.dev)
                ]
            )
        case .baidu:
            if let address = stop.address {
                return makeURL(
                    scheme: "baidumap", host: "map", path: "/geocoder",
                    items: [
                        URLQueryItem(name: "address", value: address),
                        URLQueryItem(name: "src", value: "ios.dreamtravel.mobile")
                    ]
                )
            }
            return makeURL(
                scheme: "baidumap", host: "map", path: "/place/search",
                items: [
                    URLQueryItem(name: "query", value: stop.place),
                    URLQueryItem(name: "region", value: stop.city),
                    URLQueryItem(name: "src", value: "ios.dreamtravel.mobile")
                ]
            )
        }
    }

    private static func webURL(for provider: MobileMapProvider, stop: MobileStop) -> URL {
        switch provider {
        case .amap:
            return makeURL(
                scheme: "https", host: "uri.amap.com", path: "/search",
                items: [
                    URLQueryItem(name: "keyword", value: stop.searchText),
                    URLQueryItem(name: "city", value: stop.city),
                    URLQueryItem(name: "view", value: "map"),
                    URLQueryItem(name: "src", value: "ios.dreamtravel.mobile"),
                    URLQueryItem(name: "callnative", value: "1")
                ]
            )!
        case .baidu:
            return makeURL(
                scheme: "https", host: "api.map.baidu.com", path: "/place/search",
                items: [
                    URLQueryItem(name: "query", value: stop.searchText),
                    URLQueryItem(name: "region", value: stop.city),
                    URLQueryItem(name: "output", value: "html"),
                    URLQueryItem(name: "src", value: "ios.dreamtravel.mobile")
                ]
            )!
        }
    }

    private static func makeURL(
        scheme: String,
        host: String,
        path: String,
        items: [URLQueryItem]
    ) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        components.queryItems = items
        return components.url
    }
}
