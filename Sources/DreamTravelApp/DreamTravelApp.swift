import SwiftUI

@main
struct DreamTravelPrototypeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("DreamTravel") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 680, minHeight: 540)
        }
        .defaultSize(width: 720, height: 560)
        .windowToolbarStyle(.unifiedCompact)
    }
}
