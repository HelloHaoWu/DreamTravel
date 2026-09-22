import SwiftUI

struct MobileThemeGalleryView: View {
    @State private var selected = PlanAtmosphere.rain
    @AppStorage("appearance.softTransitions") private var transitions = true
    @AppStorage("appearance.planAtmosphere") private var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Label(selected.name, systemImage: selected.tokens.symbol).font(selected.titleFont)
                    Text(selected.tokens.caption).font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Text("14:00").font(.caption.monospacedDigit().bold())
                        Text("一起慢慢体验").font(.headline)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }.padding(18).mobileCard()
                    Text("同一条旅程，随主题自然变换。").font(.caption).foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { AtmosphereBackground().clipShape(RoundedRectangle(cornerRadius: 28)) }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(PlanAtmosphere.presets, id: \.self) { style in
                        Button { selected = style } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: style.tokens.symbol)
                                    Spacer()
                                    if selected == style { Image(systemName: "checkmark.circle.fill") }
                                }.font(.title3)
                                Text(style.name).font(.subheadline.bold())
                                Text(style.tokens.caption).font(.caption).lineLimit(2).frame(minHeight: 32, alignment: .topLeading)
                            }
                            .foregroundStyle(style.accent)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(style.surface, in: RoundedRectangle(cornerRadius: style.tokens.corner))
                            .overlay { RoundedRectangle(cornerRadius: style.tokens.corner).strokeBorder(style.accent.opacity(selected == style ? 0.8 : 0.1), lineWidth: selected == style ? 2 : 1) }
                        }.buttonStyle(.plain)
                        .accessibilityLabel("\(style.name)，\(style.tokens.caption)\(selected == style ? "，已选预览" : "")")
                    }
                }
                Text("这里只预览风格。行程会根据标题与内容自动选配，三个方案使用不同色系；不改变你的行程选择。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(18)
        }
        .environment(\.planAtmosphere, selected)
        .tint(selected.accent)
        .animation(enabled && transitions && !reduceMotion ? .easeInOut(duration: 0.45) : nil, value: selected)
        .navigationTitle("12 种旅行氛围")
        .navigationBarTitleDisplayMode(.inline)
    }
}
