import SwiftUI
import WebKit

struct BookingCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var category: BookingCategory = .tickets
    @State private var selectedDestinationID = "ctrip-tickets"

    private var destinations: [BookingDestination] {
        BookingCatalog.destinations(for: category, city: model.city)
    }

    private var selectedDestination: BookingDestination {
        destinations.first(where: { $0.id == selectedDestinationID }) ?? destinations[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            platformBar
            Divider()
            EmbeddedBookingWebView(url: selectedDestination.url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: category) { _, newCategory in
            selectedDestinationID = BookingCatalog.destinations(for: newCategory, city: model.city)[0].id
        }
        .onAppear {
            category = model.bookingCategory
            selectedDestinationID = BookingCatalog.destinations(for: model.bookingCategory, city: model.city)[0].id
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("预订中心")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                    Text("从计划直接去平台确认库存与下单")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Picker("预订类型", selection: $category) {
                ForEach(BookingCategory.allCases) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var platformBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(destinations) { destination in
                    Button {
                        selectedDestinationID = destination.id
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: destination.symbol)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(destination.title)
                                    .font(.caption.weight(.semibold))
                                Text(destination.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(destination.id == selectedDestination.id ? DreamStyle.softBlue : Color.primary.opacity(0.045))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 8)

                Link(destination: selectedDestination.url) {
                    Label("用浏览器打开", systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.semibold))
                }
            }

            Label("登录、订单与支付由所选平台完成；DreamTravel 不保存平台密码或支付信息。", systemImage: "lock.shield")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if selectedDestination.id.hasPrefix("meituan") {
                Label("美团可能要求安全验证；看到验证页时，请点右侧“用浏览器打开”。", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(DreamStyle.warning)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

private struct EmbeddedBookingWebView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        load(url, in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastRequestedURL != url else { return }
        load(url, in: webView, coordinator: context.coordinator)
    }

    private func load(_ url: URL, in webView: WKWebView, coordinator: Coordinator) {
        coordinator.lastRequestedURL = url
        webView.load(URLRequest(url: url))
    }

    final class Coordinator {
        var lastRequestedURL: URL?
    }
}
