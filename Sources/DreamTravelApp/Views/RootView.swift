import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            DreamBackground()

            switch model.screen {
            case .setup:
                SetupView()
            case .home:
                HomeView()
            case .planning:
                PlanningView()
            case .itinerary:
                ItineraryView()
            }
        }
        .tint(DreamStyle.accent)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.resetToHome()
                } label: {
                    Label("主页", systemImage: "house")
                }
                .help("主页 · 开始新的安排")
                .disabled(model.screen == .home)

                Button {
                    model.previewItinerary()
                } label: {
                    Label("当前安排", systemImage: "list.bullet.rectangle")
                }
                .help("当前安排")
                .disabled(model.screen == .itinerary)

                Menu {
                    Button("预订中心", systemImage: "ticket") {
                        model.openBookingCenter(category: .tickets)
                    }
                    Divider()
                    Button("模型连接", systemImage: "key") {
                        model.previewSetup()
                    }
                    .disabled(model.screen == .setup)
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
                .help("更多")
            }
        }
        .sheet(item: $model.selectedStop) { stop in
            PlaceDetailView(stop: stop)
                .environmentObject(model)
        }
        .sheet(isPresented: $model.showsDepartureCard) {
            DepartureCardView()
                .environmentObject(model)
        }
        .sheet(isPresented: $model.showsBookingCenter) {
            BookingCenterView()
                .environmentObject(model)
        }
    }
}
