import SwiftUI

struct ItineraryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                if let changeSummary = model.changeSummary {
                    changeBanner(changeSummary)
                }

                planCard
                timeline
                preparation
                actions
            }
            .frame(maxWidth: 650)
            .padding(.horizontal, 32)
            .padding(.top, 23)
            .padding(.bottom, 30)
        }
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("完整方案 \(model.selectedPlanIndex + 1) / \(DemoItinerary.plans.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Label("小红书体验灵感", systemImage: "sparkles")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DreamStyle.accent)
            }

            HStack(spacing: 14) {
                planArrow(systemName: "chevron.left", label: "上一个完整方案", direction: -1)

                VStack(alignment: .leading, spacing: 5) {
                    Text(model.itineraryTitle)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                    Text(model.itinerarySubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("\(model.city) · \(model.timeRange) · 体验预算约 ¥\(model.estimatedCost)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                planArrow(systemName: "chevron.right", label: "下一个完整方案", direction: 1)
            }

            HStack(spacing: 6) {
                ForEach(DemoItinerary.plans) { plan in
                    Button {
                        model.selectPlan(plan.id)
                    } label: {
                        Capsule()
                            .fill(plan.id == model.selectedPlanIndex ? Color.primary : Color.primary.opacity(0.15))
                            .frame(width: plan.id == model.selectedPlanIndex ? 22 : 7, height: 7)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("切换到方案：\(plan.title)")
                }
            }
        }
        .padding(17)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DreamStyle.softBlue.opacity(0.95), DreamStyle.accent.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private func planArrow(systemName: String, label: String, direction: Int) -> some View {
        Button {
            model.cyclePlan(direction)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var timeline: some View {
        VStack(spacing: 7) {
            ForEach(Array(model.stops.enumerated()), id: \.element.id) { index, stop in
                HStack(alignment: .top, spacing: 13) {
                    Text(stop.time)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 43, alignment: .leading)
                        .padding(.top, 14)

                    VStack(spacing: 0) {
                        Circle()
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .stroke(DreamStyle.accent, lineWidth: 2)
                            .frame(width: 9, height: 9)
                            .padding(.top, 16)

                        if index < model.stops.count - 1 {
                            Rectangle()
                                .fill(Color(nsColor: .separatorColor))
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 10)

                    VStack(spacing: 0) {
                        Button {
                            model.selectedStop = stop
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(stop.title)
                                        .font(.system(size: 14, weight: .semibold))
                                    Spacer()
                                    Text(stop.meta)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(stop.summary)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                Text(stop.place)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Label(stop.address ?? "具体地址待选定", systemImage: stop.address == nil ? "mappin.slash" : "mappin")
                                    .font(.caption2)
                                    .foregroundStyle(stop.address == nil ? DreamStyle.warning : .secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 13)
                            .padding(.top, 11)
                            .padding(.bottom, 8)
                            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 9) {
                            Label("小红书灵感", systemImage: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(DreamStyle.accent)
                            Button {
                                model.openBookingCenter(category: index == 2 ? .dining : .tickets)
                            } label: {
                                Label("去平台", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.plain)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            Spacer()
                            optionArrow(systemName: "chevron.left", slot: index, direction: -1)
                            Text(model.optionPosition(at: index))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 34)
                            optionArrow(systemName: "chevron.right", slot: index, direction: 1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 9)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(index.isMultiple(of: 2) ? DreamStyle.softGreen.opacity(0.42) : DreamStyle.softBlue.opacity(0.50))
                    )
                }
            }
        }
    }

    private func optionArrow(systemName: String, slot: Int, direction: Int) -> some View {
        Button {
            model.cycleStop(at: slot, direction: direction)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 22)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction < 0 ? "上一个时间段候选" : "下一个时间段候选")
    }

    private var preparation: some View {
        HStack(spacing: 11) {
            Image(systemName: model.preparationDone ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(model.preparationDone ? DreamStyle.verified : DreamStyle.warning)

            VStack(alignment: .leading, spacing: 2) {
                Text("确定后再核实")
                    .font(.caption.weight(.semibold))
                Text(model.preparationDone ? "已标记为准备核实" : "当前是体验候选；开放时间、价格、路线和预约仍待查询。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(model.preparationDone ? "取消标记" : "标记待核实") {
                model.preparationDone.toggle()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(DreamStyle.accent)
        }
        .padding(12)
        .dreamCard()
    }

    private var actions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Button("去预订") { model.openBookingCenter(category: .tickets) }
                    .buttonStyle(PrimaryButtonStyle())
                Button("查看出发卡") { model.showsDepartureCard = true }
                    .buttonStyle(.bordered)
                Button("再轻松一点") { model.apply(.lighter) }
                    .buttonStyle(.bordered)
                Button("下雨了") { model.apply(.rainy) }
                    .buttonStyle(.bordered)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                TextField("想改什么？说一句就好", text: $model.adjustmentText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { applyCustomAdjustment() }
                Button("调整") { applyCustomAdjustment() }
                    .buttonStyle(.plain)
                    .foregroundStyle(DreamStyle.accent)
                    .disabled(model.adjustmentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func changeBanner(_ text: String) -> some View {
        HStack {
            Label(text, systemImage: "wand.and.sparkles")
                .font(.caption)
            Spacer()
            Button("撤销") { model.undoAdjustment() }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DreamStyle.accent)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .background(RoundedRectangle(cornerRadius: 9).fill(DreamStyle.softBlue.opacity(0.85)))
    }

    private func applyCustomAdjustment() {
        model.apply(.custom(model.adjustmentText))
    }
}
