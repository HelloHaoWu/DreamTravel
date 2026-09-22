import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var provider: ModelProvider = .deepSeek
    @State private var apiKey = ""
    @State private var baseURL = ModelConfiguration.deepSeekFlash.baseURL
    @State private var modelName = ModelConfiguration.deepSeekFlash.model
    @State private var apiFormat: ModelAPIFormat = .responses
    @State private var reasoningEffort: ModelReasoningEffort = .high

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("D")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 13).fill(DreamStyle.accent))

                VStack(spacing: 7) {
                    Text("第一次使用")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(DreamStyle.accent)
                        .textCase(.uppercase)
                    Text("先连接你的模型")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                    Text("只需要一枚 API Key。验证成功后，它会保存在这台 Mac 的钥匙串中。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("服务商")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("服务商", selection: $provider) {
                        ForEach(ModelProvider.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("API Key")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 5)
                    SecureField("sk-••••••••••••••••", text: $apiKey)
                        .textFieldStyle(.roundedBorder)

                    DisclosureGroup("高级设置") {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("模型")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("模型名称", text: $modelName)
                                .textFieldStyle(.roundedBorder)

                            Text("API 格式")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Picker("API 格式", selection: $apiFormat) {
                                ForEach(ModelAPIFormat.allCases) { format in
                                    Text(format.title).tag(format)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)

                            Text("规划强度")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Picker("规划强度", selection: $reasoningEffort) {
                                ForEach(ModelReasoningEffort.allCases) { effort in
                                    Text(effort.title).tag(effort)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)

                            Text("Base URL")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("https://api.example.com", text: $baseURL)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.top, 8)
                    }
                    .font(.caption.weight(.semibold))

                    if provider == .deepSeek {
                        Text("已适配 DeepSeek-V4-Flash：默认使用 Responses API 与周密规划模式。")
                            .font(.caption2)
                            .foregroundStyle(DreamStyle.accent)
                    }

                    if let error = model.modelConnectionError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: 7) {
                    Button {
                        Task {
                            await model.connectModel(
                                configuration: ModelConfiguration(
                                    provider: provider,
                                    baseURL: baseURL,
                                    model: modelName,
                                    apiFormat: apiFormat,
                                    reasoningEffort: reasoningEffort
                                ),
                                apiKey: apiKey
                            )
                        }
                    } label: {
                        if model.isConnectingModel {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("验证并保存")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity)
                    .disabled(
                        model.isConnectingModel ||
                        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    Button("跳过连接，进入主页") {
                        model.resetToHome()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Text("验证只读取可用模型列表；成功后 Key 保存在这台 Mac 的钥匙串中。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: 390)
            .padding(.horizontal, 32)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, minHeight: 500)
        }
        .scrollIndicators(.hidden)
        .onChange(of: provider) { _, newProvider in
            baseURL = newProvider.defaultBaseURL
            modelName = newProvider.defaultModel
            apiFormat = .responses
            model.modelConnectionError = nil
        }
        .onChange(of: apiKey) { _, _ in
            model.modelConnectionError = nil
        }
        .onAppear {
            guard let saved = model.savedModelConfiguration else { return }
            provider = saved.provider
            baseURL = saved.baseURL
            modelName = saved.model
            apiFormat = saved.apiFormat
            reasoningEffort = saved.reasoningEffort
        }
    }
}
