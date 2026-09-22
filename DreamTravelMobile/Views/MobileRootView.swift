import SwiftUI

struct MobileRootView: View {
    @StateObject private var model = MobileAppModel()
    @StateObject private var planning = TripPlanningViewModel()
    @State private var selectedTab = 0
    @State private var didRunDebugValidation = false
    @AppStorage("appearance.planAtmosphere") private var usesAtmosphere = true

    private var atmosphere: PlanAtmosphere {
        usesAtmosphere
            ? model.planAtmospheres[model.selectedPlanIndex]
            : .classic
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            MobileHomeView {
                selectedTab = 1
            }
            .tabItem {
                Label("开始", systemImage: "sparkles")
            }
            .tag(0)

            Group {
                if planning.isRunning {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("正在准备完整行程")
                            .font(.headline)
                        Text(planning.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("三套方案、各自的备选和全部连接准备好后，一次展示。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("取消安排") { planning.cancel() }
                    }
                    .padding(24)
                } else {
                    MobileItineraryView()
                }
            }
                .tabItem {
                    Label("行程", systemImage: "map")
                }
                .tag(1)
        }
        .environmentObject(model)
        .environmentObject(planning)
        .environment(\.planAtmosphere, atmosphere)
        .tint(atmosphere.accent)
        .onChange(of: planning.completedRunCount) { _, completedRunCount in
            if completedRunCount > 0 {
                if let result = planning.lastResult {
                    model.apply(result: result)
                }
                selectedTab = 1
            }
        }
        .task {
#if DEBUG
            if ProcessInfo.processInfo.environment["DREAMTRAVEL_REPLAY_VALIDATION"] == "1", !didRunDebugValidation {
                didRunDebugValidation = true
                planning.replayValidationResult()
                return
            }
            if ProcessInfo.processInfo.environment["DREAMTRAVEL_NETWORK_CHECK"] == "1", !didRunDebugValidation {
                didRunDebugValidation = true
                await NativeNetworkCheck.run()
                return
            }
            if ProcessInfo.processInfo.environment["DREAMTRAVEL_AUTORUN"] == "1", !didRunDebugValidation {
                didRunDebugValidation = true
                planning.start(city: "杭州", note: ProcessInfo.processInfo.environment["DREAMTRAVEL_VALIDATION_NOTE"] ?? "优先市区里少走路、有新意的约会体验")
            }
#endif
        }
    }
}
