import SwiftUI

struct MobileItineraryView: View {
    @Environment(\.planAtmosphere) private var atmosphere
    @EnvironmentObject private var model: MobileAppModel
    @EnvironmentObject private var planning: TripPlanningViewModel
    @State private var selectedStop: MobileStop?
    @State private var stopPicker: StopPickerSelection?
    @State private var showsSettings = false
    @State private var bookingEntry: PlaceBookingEntry?
    @AppStorage("appearance.planAtmosphere") private var usesAtmosphere = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    planSelector
                    if let result = planning.lastResult {
                        planningBriefCard(result.independentPlans?[model.selectedPlanIndex] ?? result)
                        if let discovery = result.discovery { discoveryCard(discovery, notice: result.researchNotice) }
                    }
                    timeline
                    readinessCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background { AtmosphereBackground() }
            .navigationTitle("这周末")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
            }
            .sheet(isPresented: $showsSettings) { MobileSettingsView() }
            .sheet(item: $bookingEntry) { MobileBookingWebView(entry: $0) }
            .sheet(item: $selectedStop) { stop in
                MobilePlaceDetailView(stop: stop)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $stopPicker) { selection in
                MobileStopPickerView(slot: selection.slot)
                    .environmentObject(model)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func planningBriefCard(_ result: VerifiedTripSummary) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("模型规划方向", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(atmosphere.accent)
            Text(result.planningBrief.title)
                .font(.headline)
            Text(result.planningBrief.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Label(result.planningBrief.weatherStrategy, systemImage: "cloud.sun")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mobileCard()
    }

    private var planSelector: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.plans) { plan in
                        let style = usesAtmosphere ? model.planAtmospheres[plan.id] : .classic
                        Button {
                            model.selectPlan(plan.id)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: style.tokens.symbol).font(.caption)
                                Text(plan.title)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(plan.id == model.selectedPlanIndex ? .white : style.accent)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 9)
                        .background(
                            plan.id == model.selectedPlanIndex ? style.solid : style.wash,
                            in: Capsule()
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(model.selectedPlan.title)
                    .contentTransition(.opacity)
                    .font(atmosphere.titleFont)
                Text(model.selectedPlan.subtitle)
                    .contentTransition(.opacity)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(model.displayCity) · \(model.selectedPlan.meetingTime)–\(model.selectedPlan.endingTime) · \(model.isLiveItinerary ? "价格待核实" : "双人约 ¥490 起")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("\(model.choices.count) 站连续行程 · 含交通与留白", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(atmosphere.accent)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [atmosphere.wash, atmosphere.glow.opacity(0.26)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            endpointNode(
                time: model.selectedPlan.meetingTime,
                title: model.selectedPlan.meetingPlace,
                note: model.selectedPlan.meetingNote,
                symbol: "person.2.fill",
                isEnding: false
            )

            ForEach(Array(model.stops.enumerated()), id: \.element.id) { index, stop in
                connectionRow(at: index)
                stopNode(stop, index: index)
            }

            connectionRow(at: model.stops.count)
            endpointNode(
                time: model.selectedPlan.endingTime,
                title: model.selectedPlan.endingTitle,
                note: model.selectedPlan.endingNote,
                symbol: "house.fill",
                isEnding: true
            )
        }
    }

    private func stopNode(_ stop: MobileStop, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(atmosphere.solid)
                    .frame(width: 28, height: 28)
                Text("\(index + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
            .padding(.top, 15)

            VStack(alignment: .leading, spacing: 12) {
                Button {
                    selectedStop = stop
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(stop.time)
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(atmosphere.accent)
                            Spacer()
                            Text(stop.duration)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(stop.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(stop.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let reservation = stop.research?.reservation, reservation.status != .unknown {
                            Label(reservation.status.label, systemImage: "calendar.badge.clock")
                                .font(.caption).foregroundStyle(atmosphere.accent)
                        }
                        if let price = stop.research?.perPersonText {
                            Label(price, systemImage: "yensign.circle")
                                .font(.caption)
                                .foregroundStyle(atmosphere.accent)
                        }
                        Label(stop.address ?? "具体地址待选定", systemImage: stop.address == nil ? "mappin.slash" : "mappin")
                            .font(.caption)
                            .foregroundStyle(stop.address == nil ? MobileStyle.warning : .secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()

                HStack {
                    Text("备选 \(model.selections[index] + 1) / 3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let entry = stop.research?.reservation?.entries.first {
                        Button(entry.kind == "booking" ? "去预约" : "查看预订") { bookingEntry = entry }
                            .font(.caption.weight(.semibold)).buttonStyle(.bordered).controlSize(.small)
                    }
                    Button {
                        stopPicker = StopPickerSelection(slot: index)
                    } label: {
                        Label("3 选 1", systemImage: "rectangle.stack")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(16)
            .mobileCard()
        }
    }

    private func connectionRow(at index: Int) -> some View {
        let connection = model.connection(at: index)
        let options = model.transportOptions(at: index)
        let selected = model.selectedTransport(at: index)?.mode
        return HStack(alignment: .center, spacing: 12) {
            ZStack {
                Rectangle()
                    .fill(atmosphere.accent.opacity(0.28))
                    .frame(width: 2)
                Circle()
                    .fill(Color(.systemGroupedBackground))
                    .frame(width: 26, height: 26)
                Image(systemName: connection.symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(connection.needsVerification ? MobileStyle.warning : atmosphere.accent)
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(connection.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    if options.count > 1 {
                        Menu {
                            ForEach(options, id: \.mode) { option in
                                Button { model.selectTransport(option.mode, at: index) } label: {
                                    Label("\(option.mode.title) · \(option.timeText)",
                                          systemImage: selected == option.mode ? "checkmark" : option.mode.symbol)
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.triangle.swap")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(atmosphere.accent)
                                .frame(width: 28, height: 28)
                                .background(atmosphere.wash, in: Circle())
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .menuIndicator(.hidden)
                        .accessibilityLabel("切换这段交通，当前\(connection.title)")
                    }
                }
                Text(connection.detail)
                    .font(.caption)
                    .foregroundStyle(connection.needsVerification ? MobileStyle.warning : .secondary)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func endpointNode(
        time: String,
        title: String,
        note: String,
        symbol: String,
        isEnding: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(isEnding ? MobileStyle.softGreen : atmosphere.wash)
                    .frame(width: 28, height: 28)
                Image(systemName: symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isEnding ? MobileStyle.verified : atmosphere.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(time)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isEnding ? MobileStyle.verified : atmosphere.accent)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }

    private var readinessCard: some View {
        let message = if let result = planning.lastResult {
            "\(result.isLive ? "实时" : "演示")数据 · \(result.modelProvider) · \(result.weather.condition)，\(Int(result.weather.temperatureCelsius))℃，湿度 \(result.weather.humidityPercent)%；已核对 \((result.independentPlans ?? [result]).reduce(0) { $0 + $1.candidateCount }) 个候选地址和 \((result.independentPlans ?? [result]).reduce(0) { $0 + $1.connectionCount }) 条连接。营业信息、价格和预约以各地点说明为准。"
        } else {
            "三个候选及连接已随方案校验并预排；出发前只复查实时变化。"
        }

        return VStack(alignment: .leading, spacing: 8) {
            if model.hasTransportConflict {
                Label("当前交通选择会晚到，请调整上方标出的交通或备选。", systemImage: "exclamationmark.triangle")
                    .font(.footnote.weight(.semibold)).foregroundStyle(MobileStyle.warning)
            }
            Label(message, systemImage: "checkmark.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let result = planning.lastResult,
               result.isLive,
               let url = URL(string: result.weather.sourceAttributions.first ?? "https://lbs.qq.com/") {
                Link("查看天气数据来源", destination: url)
                    .font(.caption)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MobileStyle.softGreen, in: RoundedRectangle(cornerRadius: 16))
    }

    private func discoveryCard(_ report: DiscoveryReport, notice: String?) -> some View {
        DisclosureGroup {
            ForEach(report.ideas) { idea in
                VStack(alignment: .leading, spacing: 5) {
                    Text(idea.title).font(.subheadline.weight(.semibold))
                    Text(idea.summary).font(.caption).foregroundStyle(.secondary)
                    ForEach(report.sources.filter { idea.sourceURLs.contains($0.url) }) { source in
                        if let url = ResearchURL.validated(source.url) { Link(source.title, destination: url).font(.caption) }
                    }
                }.padding(.vertical, 5)
            }
            Text(notice ?? report.notice).font(.caption).foregroundStyle(.secondary)
        } label: {
            Label("这次参考了 \(report.ideas.count) 种新玩法", systemImage: "sparkle.magnifyingglass")
                .font(.subheadline)
        }
        .padding(16)
        .mobileCard()
    }
}

private struct StopPickerSelection: Identifiable {
    let slot: Int
    var id: Int { slot }
}
