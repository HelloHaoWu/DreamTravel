import SwiftUI

@main
struct DreamTravelMobileApp: App {
    init() {
#if DEBUG
        TencentDevelopmentBootstrap.run()
#endif
    }

    var body: some Scene {
        WindowGroup {
            MobileRootView()
        }
    }
}
