import SwiftUI

struct MobileStopPickerView: View {
    @Environment(\.planAtmosphere) private var atmosphere
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: MobileAppModel

    let slot: Int

    private var choices: [MobileStop] {
        model.choices[slot]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("为 \(choices[0].time) 选择一段体验")
                            .font(.title2.bold())
                        Text(model.isLiveItinerary
                             ? "三个候选与相邻路线已预排，选择后立即切换。"
                             : "三个演示候选和相邻路线已预排，选择后立即切换。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(Array(choices.enumerated()), id: \.element.id) { index, stop in
                        choiceCard(stop, index: index)
                    }
                }
                .padding(20)
            }
            .background { AtmosphereBackground() }
            .navigationTitle("三选一")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func choiceCard(_ stop: MobileStop, index: Int) -> some View {
        let isSelected = model.selections[slot] == index

        return Button {
            model.selectStop(at: slot, choice: index)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text("\(index + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(isSelected ? .white : atmosphere.accent)
                        .frame(width: 26, height: 26)
                        .background(isSelected ? atmosphere.solid : atmosphere.wash, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(stop.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(stop.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    if isSelected {
                        Label("当前", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MobileStyle.verified)
                    }
                }

                HStack(spacing: 14) {
                    Label(stop.duration, systemImage: "clock")
                    Label(stop.price, systemImage: "yensign.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Label(model.isLiveItinerary ? "腾讯地址与路线已核对" : "演示地点与路线已预排", systemImage: "checkmark.shield")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MobileStyle.verified)

                Label(
                    stop.address ?? "具体地点待选定",
                    systemImage: stop.address == nil ? "mappin.slash" : "mappin"
                )
                .font(.caption)
                .foregroundStyle(stop.address == nil ? MobileStyle.warning : .secondary)
                .lineLimit(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? atmosphere.wash : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? atmosphere.accent.opacity(0.45) : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stop.title)，\(stop.duration)，\(stop.price)\(isSelected ? "，当前选择" : "")")
    }
}
