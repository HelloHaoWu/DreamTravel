import SwiftUI

struct MobileSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var connection = ModelConnectionViewModel()
    @StateObject private var mapConnection = MapConnectionViewModel()
    @AppStorage("appearance.planAtmosphere") private var usesAtmosphere = true
    @AppStorage("appearance.softTransitions") private var usesTransitions = true
    @AppStorage("research.activeSearch") private var activeSearch = true
    @AppStorage("research.useLibrary") private var useLibrary = true
    @AppStorage("research.saveReferences") private var saveReferences = true
    @AppStorage("research.placeDetails") private var placeDetails = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("方案氛围色", isOn: $usesAtmosphere)
                    Toggle("柔和过渡", isOn: $usesTransitions)
                        .disabled(!usesAtmosphere)
                    NavigationLink("预览 12 种旅行氛围") { MobileThemeGalleryView() }
                } header: {
                    Text("外观与动效")
                } footer: {
                    Text("根据方案标题与内容自动匹配风格，三个方案使用不同色系。关闭氛围色后统一为清朗蓝；关闭柔和过渡或开启系统“减少动态效果”时即时切换。")
                }

                Section {
                    Toggle("主动搜索新玩法", isOn: $activeSearch)
                    Toggle("整理点单与游玩参考", isOn: $placeDetails)
                    Toggle("自动积累搜索参考", isOn: $saveReferences)
                    Toggle("使用已保存的参考", isOn: $useLibrary)
                    NavigationLink("我的旅行灵感") { MobileReferenceLibraryView() }
                } header: {
                    Text("旅行灵感")
                } footer: {
                    Text("安排时用 DeepSeek 联网发现玩法及地点体验，会增加等待时间与模型用量。点单统计需取得 3～5 篇同店正文，资料不足时如实说明；可分别关闭两个搜索功能。")
                }

                Section("规划模型") {
                    LabeledContent("服务", value: "DeepSeek")
                    LabeledContent("模型", value: connection.configuration.model)
                    SecureField("DeepSeek API Key", text: $connection.apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Button {
                        connection.validateAndSave()
                    } label: {
                        HStack {
                            if connection.isChecking { ProgressView() }
                            Text(connection.isChecking ? "正在验证" : "验证并保存")
                        }
                    }
                    .disabled(connection.isChecking || connection.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if !connection.message.isEmpty {
                        Label(
                            connection.message,
                            systemImage: connection.isConnected ? "checkmark.circle.fill" : "info.circle"
                        )
                        .font(.footnote)
                        .foregroundStyle(connection.isConnected ? .green : .secondary)
                    }
                }

                Section {
                    Button("一键获取腾讯地图 Key", systemImage: "safari") {
                        openURL(TravelProviderConfiguration.quickRegisterURL) { accepted in
                            if !accepted { mapConnection.message = "未能打开浏览器，请稍后重试。" }
                        }
                    }
                    SecureField("腾讯位置服务 WebService Key", text: $mapConnection.apiKey)
                        .textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never)
                        .disabled(mapConnection.isChecking)
                    Button {
                        mapConnection.validateAndSave()
                    } label: {
                        HStack {
                            if mapConnection.isChecking { ProgressView() }
                            Text(mapConnection.isChecking ? "正在验证地图与天气" : "验证并保存腾讯 Key")
                        }
                    }.disabled(mapConnection.isChecking || mapConnection.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if mapConnection.hasSavedKey {
                        Button("移除我的腾讯 Key", role: .destructive) { mapConnection.remove() }
                            .disabled(mapConnection.isChecking)
                    }
                    Text(mapConnection.message).font(.footnote).foregroundStyle(.secondary)
                } header: { Text("我的腾讯位置服务") }
                footer: {
                    Text("在手机默认浏览器中完成官方手机号验证并获取 Key，复制后回到这里粘贴。Key 仅存入本机钥匙串；保存后下一次安排立即使用，不影响正在生成的行程。")
                }

                Section("真实数据") {
                    Label("腾讯位置服务提供地点、地址和路线", systemImage: "map")
                    Label("腾讯天气提供行程日期的温度和日夜湿度", systemImage: "cloud.sun")
                    Text("消费、营业记录和预约要求在地点详情中附来源；查不到时明确说明。建议停留时长是行程安排，已与交通和缓冲一起校验。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("优先使用你保存的腾讯 Key。未设置时，开发版可使用测试配置；没有可用配置时显示演示数据。个人 Key 的额度与可用接口以腾讯账号为准。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

@MainActor
final class MapConnectionViewModel: ObservableObject {
    @Published var apiKey = ""
    @Published var message = "尚未保存个人腾讯 Key"
    @Published private(set) var hasSavedKey = false
    @Published private(set) var isChecking = false
    init() {
        do {
            if let stored = try TencentKeychainStore.read(), !stored.isEmpty {
                apiKey = stored
                hasSavedKey = true
                message = "已保存个人腾讯 Key，可直接安排；输入框已安全预填，可替换或移除。"
            }
        } catch { message = "无法读取钥匙串，请稍后重试。" }
    }
    func validateAndSave() {
        guard !isChecking else { return }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isChecking = true
        message = "正在检查地点、路线和天气权限…"
        Task {
            defer { isChecking = false }
            do {
                let api = TencentTravelAPI(key: key)
                let places = try await api.search(query: "西湖", city: "杭州")
                guard places.count >= 2 else { throw TravelProviderError.missingEvidence("地点查询未返回足够结果，请检查 WebService 权限。") }
                _ = try await api.travelRoute(from: places[0].coordinate, to: places[1].coordinate)
                let intent = TripIntent(city: "杭州", scheduledStart: Date(), timeWindow: "验证", energy: "", mood: "", note: nil)
                _ = try await TencentLiveTravelToolService(key: key).resolveWeather(for: intent)
                try TencentKeychainStore.save(key)
                apiKey = ""
                hasSavedKey = true
                message = "地点、路线和天气验证成功，下一次安排使用你的 Key。"
            } catch {
                // Never echo provider responses or credential-bearing URLs.
                message = "验证未通过。请检查 Key、WebService 权限、天气接口额度和网络；原有 Key 未替换。"
            }
        }
    }
    func remove() {
        do {
            try TencentKeychainStore.remove()
            hasSavedKey = false; apiKey = ""
            message = "已移除个人 Key。下一次安排使用可用的开发配置，没有配置时显示演示数据。"
        } catch { message = "移除失败，请稍后重试。" }
    }
}
