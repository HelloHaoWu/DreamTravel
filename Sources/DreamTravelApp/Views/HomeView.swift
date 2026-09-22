import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsImporter = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 38)

            VStack(spacing: 0) {
                Text("9 月 12 日 · 周六")
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)

                Text("周六，去见她。")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .padding(.top, 8)

                Text("这次想轻松一点，其他的交给我。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.top, 7)

                HStack(spacing: 8) {
                    Menu {
                        ForEach(model.cities, id: \.self) { city in
                            Button(city) { model.city = city }
                        }
                    } label: {
                        Label(model.city, systemImage: "chevron.down")
                            .labelStyle(TrailingIconLabelStyle())
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(ConditionButtonStyle())

                    Menu {
                        ForEach(model.timeRanges, id: \.self) { range in
                            Button(range) { model.timeRange = range }
                        }
                    } label: {
                        Label(model.timeRange, systemImage: "chevron.down")
                            .labelStyle(TrailingIconLabelStyle())
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(ConditionButtonStyle())

                    Menu {
                        ForEach(model.budgets, id: \.self) { value in
                            Button("预算 ¥\(value)") { model.budget = value }
                        }
                    } label: {
                        Label("预算 ¥\(model.budget)", systemImage: "chevron.down")
                            .labelStyle(TrailingIconLabelStyle())
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(ConditionButtonStyle())
                }
                .padding(.top, 25)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $model.idea)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .padding(8)

                    if model.idea.isEmpty {
                        Text("想补充什么？可以留空")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 15)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 88)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: DreamStyle.accent.opacity(0.12), radius: 24, y: 9)
                )
                .overlay(alignment: .bottomLeading) {
                    Text("例如：这周有点累，想安静一点")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.bottom, 9)
                        .allowsHitTesting(false)
                }
                .padding(.top, 14)

                if let importedItemName = model.importedItemName {
                    Label("已带入：\(importedItemName)", systemImage: "doc.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }

                Button("帮我安排") {
                    model.requestPlan()
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                .padding(.top, 18)

                Button {
                    showsImporter = true
                } label: {
                    Label("带入攻略或地点", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            }
            .frame(maxWidth: DreamStyle.contentWidth)
            .padding(.horizontal, 32)

            Spacer(minLength: 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $model.showsMeetingQuestion) {
            MeetingPointSheet()
                .environmentObject(model)
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.plainText, .image, .pdf]
        ) { result in
            if case .success(let url) = result {
                model.importedItemName = url.lastPathComponent
            }
        }
    }
}

private struct MeetingPointSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var customPoint = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("还差一个信息")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(DreamStyle.accent)
                Text("你们大概从哪里会合？")
                    .font(.system(size: 23, weight: .semibold))
                Text("只用来估算第一段路程。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(["杭州东站", "武林广场", "使用当前位置"], id: \.self) { point in
                    Button {
                        dismiss()
                        model.useMeetingPoint(point)
                    } label: {
                        HStack {
                            Text(point)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 41)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .dreamCard(cornerRadius: 9)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("其他地点")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("输入商圈或地标", text: $customPoint)
                        .textFieldStyle(.roundedBorder)
                    Button("继续") {
                        dismiss()
                        model.useMeetingPoint(customPoint)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(customPoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(26)
        .frame(width: 420)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.title
            configuration.icon
                .font(.system(size: 8, weight: .semibold))
        }
    }
}
