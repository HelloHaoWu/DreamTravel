import SwiftUI
import SafariServices

struct MobileBookingWebView: View {
    let entry: PlaceBookingEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var loadFailed = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.host).font(.caption.bold())
                    Text("请在平台选择日期、人数或房型。只有平台确认成功，才算预约完成。")
                        .font(.caption).foregroundStyle(.secondary)
                    if loadFailed { Text("页面暂未打开，可使用右上角的 Safari 按钮重试。").font(.caption).foregroundStyle(.orange) }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                if let url = ReservationValidation.publicURL(entry.url) {
                    BookingSafariView(url: url, failed: $loadFailed) { dismiss() }
                } else { ContentUnavailableView("链接不可用", systemImage: "link.badge.plus") }
            }
            .navigationTitle(entry.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Safari 打开", systemImage: "safari") {
                        if let url = ReservationValidation.publicURL(entry.url) { openURL(url) }
                    }.labelStyle(.iconOnly).accessibilityLabel("在 Safari 打开")
                }
            }
        }
    }
}

private struct BookingSafariView: UIViewControllerRepresentable {
    let url: URL
    @Binding var failed: Bool
    let close: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
    @MainActor final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let parent: BookingSafariView
        init(parent: BookingSafariView) { self.parent = parent }
        nonisolated func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            Task { @MainActor [weak self] in self?.parent.close() }
        }
        nonisolated func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {
            Task { @MainActor [weak self] in self?.parent.failed = !didLoadSuccessfully }
        }
    }
}

struct MobileReservationSection: View {
    let stop: MobileStop
    let open: (PlaceBookingEntry) -> Void
    @Environment(\.planAtmosphere) private var atmosphere
    @State private var copied = false
    private var reservation: PlaceReservation { stop.research?.reservation ?? .unknown }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("预约与预订", systemImage: "calendar.badge.clock").font(.title3.bold())
            Text(reservation.status.label).font(.headline).foregroundStyle(atmosphere.accent)
            Text(reservation.explanation).font(.subheadline).foregroundStyle(.secondary)
            ForEach(reservation.entries) { entry in
                Button { open(entry) } label: {
                    Label(entry.title, systemImage: "arrow.up.right.square").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(atmosphere.solid)
                Text(entry.host).font(.caption).foregroundStyle(.secondary)
            }
            if reservation.entries.isEmpty {
                Text("暂未找到这家店的直接预订链接，可复制店名后到平台查找。").font(.caption).foregroundStyle(.secondary)
                Button(copied ? "已复制店名与地址" : "复制店名与地址", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = stop.city + " " + stop.place + " " + (stop.address ?? "")
                    copied = true
                }.font(.caption)
                HStack {
                    platform("大众点评", "https://m.dianping.com/")
                    platform("美团", "https://m.meituan.com/")
                    platform("携程酒店", "https://m.ctrip.com/html5/hotel/")
                }
                Text("以上为平台入口，并非该店预约页。").font(.caption2).foregroundStyle(.secondary)
            }
            if !reservation.claims.isEmpty {
                DisclosureGroup("查看预约依据（\(reservation.claims.count)）") {
                    ForEach(Array(reservation.claims.enumerated()), id: \.offset) { _, claim in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(claim.quote).font(.caption)
                            Button("查看原文") { open(.init(url: claim.sourceURL, kind: "reference", sourceURL: claim.sourceURL)) }.font(.caption)
                        }.padding(.vertical, 5)
                    }
                    if let report = stop.research {
                        Text("查询于 \(report.searchedAt.formatted(date: .abbreviated, time: .shortened))；历史记录以商家当前要求为准。")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }.padding(16).mobileCard()
    }
    private func platform(_ name: String, _ url: String) -> some View {
        Button(name) { open(.init(url: url, kind: "platform", sourceURL: url)) }.buttonStyle(.bordered).font(.caption)
    }
}
