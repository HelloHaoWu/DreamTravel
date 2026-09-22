import CoreLocation
import SwiftUI

struct MobilePlaceDetailView: View {
    @Environment(\.planAtmosphere) private var atmosphere
    @Environment(\.dismiss) private var dismiss
    let stop: MobileStop

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var bookingEntry: PlaceBookingEntry?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(stop.time) · \(stop.duration)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(atmosphere.accent)
                        Text(stop.title)
                            .font(.title.bold())
                        Text(stop.place)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    addressSection
                    if let finish = stop.plannedFinish {
                        fact("停留安排", "\(stop.time)–\(finish)，\(stop.duration)。已另外预留交通与缓冲时间。这是行程建议；有固定场次时，以预约场次为准。")
                    }
                    MobileReservationSection(stop: stop) { bookingEntry = $0 }
                    fact("为什么适合", stop.reason)
                    fact("营业与价格", [stop.openingHours, stop.price].compactMap { $0 }.joined(separator: " · "))
                    fact("信息状态", informationStatus)
                    if let research = stop.research { researchSection(research) }
                }
                .padding(20)
            }
            .background { AtmosphereBackground() }
            .navigationTitle("地点详情")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $bookingEntry) { MobileBookingWebView(entry: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var informationStatus: String {
        if let source = stop.evidenceSource {
            if stop.openingHoursVerified {
                return "\(source) 返回了地点与常规营业时间；节假日、临时停业和预约请在出发前复核。"
            }
            return "\(source) 已核对地点和地址。营业、消费和预约的补充记录见详情中的来源；当天名额和预订结果以平台确认为准。"
        }
        return stop.address == nil
            ? "当前还是体验候选，选定实际地点后再核实地址。"
            : "演示地址；营业、路线和预约仍需出发前核实。"
    }

    private func researchSection(_ report: PlaceResearchReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("怎么点 · 怎么玩").font(.title3.bold())
            Text(report.notice).font(.caption).foregroundStyle(.secondary)
            if let price = report.perPersonText { fact("消费参考", price) }
            if let hours = report.openingText { fact("营业信息来源记录", hours) }
            ForEach(report.dishes) { dish in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(dish.name).font(.headline)
                        Spacer()
                        Text(dish.priceText ?? "单品价未找到").font(.caption)
                    }
                    Text(dish.reason).font(.subheadline)
                    Text("\(dish.sampleCount) 篇样本中 \(dish.positiveCount) 篇推荐\(dish.negativeCount > 0 ? "，\(dish.negativeCount) 篇有负面意见" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(12).background(atmosphere.wash, in: RoundedRectangle(cornerRadius: 14))
            }
            ForEach(report.tips, id: \.self) { tip in
                Label(tip, systemImage: "lightbulb").font(.subheadline)
            }
            DisclosureGroup("查看参考来源（\(report.sources.count)）") {
                ForEach(report.sources) { source in
                    if let url = ResearchURL.validated(source.url) {
                        VStack(alignment: .leading, spacing: 3) {
                            Link(source.title, destination: url).font(.caption)
                            if let record = report.observations.first(where: { $0.url == source.url }) {
                                Text("\(record.kind == "review" ? "同店体验样本" : "地点信息参考") · \(record.visitDate ?? source.pageAge ?? "原文时间不详")")
                                    .font(.caption2).foregroundStyle(.secondary)
                            } else {
                                Text("搜索线索，未计入统计").font(.caption2).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }
                }
                Text("搜索时间：\(report.searchedAt.formatted(date: .abbreviated, time: .shortened))。链接列表包含未能读取的线索；有效同店样本为 \(report.relevantReviewCount) 篇。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var addressSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("具体地址", systemImage: "mappin.and.ellipse")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(stop.evidenceSource == nil ? (stop.address == nil ? "待选定" : "演示") : "地图已核对")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stop.address == nil ? MobileStyle.warning : MobileStyle.verified)
            }

            if let address = stop.address {
                Text(address)
                    .font(.body.weight(.semibold))
                    .textSelection(.enabled)

                MobilePlaceMapView(stop: stop, coordinate: $coordinate)
                if let source = stop.evidenceSource {
                    Text("内嵌地图为 Apple 地图搜索预览，地点地址以\(source)返回值为准。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Agent 选定具体店铺或场馆后，这里才显示门牌地址和地图点位。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                mapButton("高德打开", symbol: "location.fill", provider: .amap)
                mapButton("百度打开", symbol: "map.fill", provider: .baidu)
            }
        }
        .padding(16)
        .background(atmosphere.wash, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func mapButton(_ title: String, symbol: String, provider: MobileMapProvider) -> some View {
        Button {
            MobileMapLauncher.open(provider, stop: stop, coordinate: coordinate)
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(provider == .amap ? Color(red: 0.08, green: 0.52, blue: 0.96) : Color(red: 0.17, green: 0.42, blue: 0.92))
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
