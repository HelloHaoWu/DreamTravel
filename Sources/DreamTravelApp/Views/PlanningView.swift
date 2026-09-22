import SwiftUI

struct PlanningView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            ProgressView()
                .controlSize(.large)
                .tint(DreamStyle.accent)

            VStack(spacing: 7) {
                Text("\(model.city) · 周六")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(DreamStyle.accent)
                Text("正在核对路线与营业时间")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text("已经找到适合安静聊天的晚餐。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: 0.68)
                .tint(DreamStyle.accent)
                .frame(width: 250)

            Button("取消") {
                model.cancelPlanning()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            do {
                try await Task.sleep(for: .seconds(1.8))
                guard !Task.isCancelled else { return }
                model.finishPlanning()
            } catch {
                return
            }
        }
    }
}
