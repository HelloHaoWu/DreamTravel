import Foundation

@main struct ThemeCheck {
    static func main() throws {
        precondition(PlanAtmosphere.presets.count == 12)
        precondition(PlanAtmosphere.palette(titles: ["雨天慢享", "室内微浪漫", "轻步夜色"]) == [.rain, .romance, .evening])
        precondition(PlanAtmosphere.palette(titles: ["金沙湖 XR 科幻约", "陶艺手作", "森林露营"]) == [.future, .craft, .forest])
        let triplets = [
            ["浪漫晚宴", "莓酒晚宴", "手作陶艺"],
            ["陶艺手作", "落日留白", "海边晴日"],
            ["雨天慢享", "雨中散步", "烟雨茶事"],
            ["夜色", "夜景", "星空"],
            ["计划 A", "计划 B", "计划 C"],
            ["花园赏花", "暮色星空", "海边度假"],
            ["书香", "森林", "日落"]
        ]
        for titles in triplets {
            let matched = PlanAtmosphere.palette(titles: titles)
            precondition(matched.count == 3 && Set(matched.map { $0.tokens.family }).count == 3)
            precondition(matched == PlanAtmosphere.palette(titles: titles))
        }
        let titles = ["陶艺手作", "海边游船", "花园赏花"]
        let forward = PlanAtmosphere.palette(titles: titles)
        precondition(PlanAtmosphere.palette(titles: titles.reversed()) == forward.reversed())
        let details = PlanAtmosphere.palette(contexts: [.init(title: "一起体验", detail: "陶艺手作工坊"), .init(title: "一起散步", detail: "森林绿道自然"), .init(title: "一起发现", detail: "沉浸 XR 科幻")])
        precondition(details == [.craft, .forest, .future])
        func luminance(_ hex: String) -> Double {
            let n = UInt64(hex, radix: 16)!
            let channels = [16,8,0].map { shift -> Double in
                let c = Double((n >> shift) & 255) / 255
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        for style in PlanAtmosphere.allCases {
            precondition(1.05 / (luminance(style.tokens.accent) + 0.05) >= 4.5, "White selected text contrast: \(style)")
            precondition((luminance(style.tokens.surface) + 0.05) / (luminance(style.tokens.accent) + 0.05) >= 4.5, "Tint text contrast: \(style)")
        }
        print("12_PRESETS_TITLE_AND_CONTENT_MATCHING=passed")
        print("THREE_DISTINCT_FAMILIES_COLLISIONS_AND_ORDER=passed")
        print("LIGHT_SURFACE_AND_SELECTED_TEXT_CONTRAST=passed")
        if CommandLine.arguments.count > 1 {
            let values: [[String: Any]] = PlanAtmosphere.presets.map { style in
                let t = style.tokens
                return ["id":style.rawValue,"name":t.name,"family":t.family,"accent":t.accent,"glow":t.glow,"surface":t.surface,"motif":t.motif,"caption":t.caption,"keywords":t.keywords,"corner":t.corner,"editorial":t.editorial]
            }
            let json = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
            let js = "window.DREAM_THEMES = " + String(decoding: json, as: UTF8.self) + ";\n"
            try js.write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
        }
    }
}
