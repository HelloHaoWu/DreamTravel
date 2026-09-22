import SwiftUI

struct MobileHomeView: View {
    @Environment(\.planAtmosphere) private var atmosphere
    @EnvironmentObject private var planning: TripPlanningViewModel

    let showItinerary: () -> Void

    @State private var city = "杭州"
    @State private var note = ""
    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("DreamTravel")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(atmosphere.accent)
                        Text("这周末，\n替你想好。")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                        Text("不用再做一晚上攻略，只告诉我你们在哪见。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        Label("在哪见面", systemImage: "location")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField("城市", text: $city)
                            .font(.title3.weight(.semibold))

                        Divider()

                        HStack(spacing: 8) {
                            condition("周六下午")
                            condition("不要太累")
                            condition("有点浪漫")
                        }

                        TextField("还有什么想照顾到的？可以不填", text: $note, axis: .vertical)
                            .lineLimit(2...4)

                        Button {
                            planning.start(city: city, note: note)
                        } label: {
                            HStack(spacing: 9) {
                                if planning.isRunning {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(planning.isRunning ? "正在安排" : "替我安排")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(planning.isRunning || city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if !planning.message.isEmpty {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: planning.phase == .failed ? "exclamationmark.circle" : "sparkles")
                                    .foregroundStyle(planning.phase == .failed ? MobileStyle.warning : atmosphere.accent)
                                Text(planning.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 8)
                                if planning.isRunning {
                                    Button("取消") { planning.cancel() }
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(20)
                    .mobileCard()

                    Button("先看看演示行程", action: showItinerary)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .disabled(planning.isRunning)
                }
                .padding(.horizontal, 20)
                .padding(.top, 30)
                .padding(.bottom, 24)
            }
            .background(
                LinearGradient(
                    colors: [atmosphere.wash, Color(.systemGroupedBackground)],
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
            }
            .sheet(isPresented: $showsSettings) {
                MobileSettingsView()
            }
            .animation(.easeInOut(duration: 0.2), value: planning.message)
        }
    }

    private func condition(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(atmosphere.wash, in: Capsule())
    }
}
