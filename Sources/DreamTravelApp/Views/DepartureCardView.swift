import SwiftUI

struct DepartureCardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var partnerMode = false

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button("返回安排", systemImage: "chevron.left") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Picker("出发卡版本", selection: $partnerMode) {
                    Text("本人版").tag(false)
                    Text("给她看").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)

                Spacer()

                ShareLink(item: model.shareText(partnerMode: partnerMode)) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }

            departureCard

            Text(partnerMode ? "预算和惊喜备注已经隐藏。" : "本人版包含预算、准备事项和内部备注。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 650, height: 590)
    }

    private var departureCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SAT · 09.12 · HANGZHOU")
                .font(.system(size: 10, weight: .medium))
                .tracking(1.6)
                .foregroundStyle(.secondary)

            Text(model.itineraryTitle)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .padding(.top, 17)

            Text("慢慢见面，好好吃饭。")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            VStack(spacing: 15) {
                ForEach(model.stops) { stop in
                    HStack(alignment: .top, spacing: 13) {
                        Text(stop.time)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 45, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(stop.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(stop.place)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.top, 25)

            Divider()
                .padding(.vertical, 18)

            if partnerMode {
                Text("天气可能有阵雨，我们慢慢走，累了就随时歇一会儿。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("给自己的提醒")
                        .font(.caption.weight(.semibold))
                    Text("18:00 前预约晚餐 · 预计预算 ¥\(model.estimatedCost) · 小礼物放在包里")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(30)
        .frame(width: 360, height: 430)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DreamStyle.softBlue, DreamStyle.accent.opacity(0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.12), radius: 24, y: 12)
        )
    }
}
