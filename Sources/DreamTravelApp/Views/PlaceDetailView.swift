import SwiftUI

struct PlaceDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let stop: ItineraryStop

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(stop.time) · 体验候选")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(DreamStyle.accent)

                    Text(stop.title)
                        .font(.system(size: 24, weight: .semibold))
                        .padding(.top, 7)

                    Text(stop.place)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)
                }

                Spacer()

                Button { dismiss() } label: {
                    Label("关闭", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("关闭地点详情")
            }
            .padding(.horizontal, 26)
            .padding(.top, 24)
            .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    addressCard
                    detailRow("为什么适合", stop.reason)
                    detailRow("从上一站", stop.transit)
                    detailRow("营业与价格", "\(stop.openingHours) · \(stop.price)")
                    detailRow("信息依据", "\(stop.source)\n\(stop.verification)", verified: false)

                    Link(destination: stop.sourceURL) {
                        Label("查看小红书公开搜索", systemImage: "arrow.up.right.square")
                    }
                    .font(.caption)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 26)
            }

            Divider()

            Button("替换这一站") {
                model.replace(stop)
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .frame(width: 540, height: 680)
    }

    @ViewBuilder
    private var addressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("具体地址", systemImage: "mappin.and.ellipse")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(stop.address == nil ? "待选定" : "已核对")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(stop.address == nil ? DreamStyle.warning : DreamStyle.verified)
            }

            if let address = stop.address {
                Text(address)
                    .font(.system(size: 14, weight: .medium))
                    .textSelection(.enabled)

                if let source = stop.addressSource, let sourceURL = stop.addressSourceURL {
                    Link("地址依据：\(source)", destination: sourceURL)
                        .font(.caption2)
                }

                PlaceMiniMapView(place: stop.place, address: address)
            } else {
                Text("当前还是体验类型，Agent 选定具体店铺或场馆后才会写入门牌地址和地图点位。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Label("地图入口会先搜索“\(stop.place)”", systemImage: "magnifyingglass")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 10) {
                Link(destination: MapDestination.amapURL(for: stop)) {
                    Label("高德地图", systemImage: "location.fill")
                }
                .buttonStyle(.bordered)

                Link(destination: MapDestination.baiduURL(for: stop)) {
                    Label("百度地图", systemImage: "map.fill")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .controlSize(.regular)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DreamStyle.softBlue.opacity(0.55))
        )
        .padding(.bottom, 7)
    }

    private func detailRow(_ title: String, _ value: String, verified: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 7) {
                if title == "信息依据" {
                    Circle()
                        .fill(verified ? DreamStyle.verified : DreamStyle.warning)
                        .frame(width: 7, height: 7)
                        .padding(.top, 5)
                }
                Text(value)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
