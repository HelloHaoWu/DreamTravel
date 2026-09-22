import Foundation

struct PlanThemeContext: Sendable {
    let title: String
    var detail: String = ""
}

/// Bundled visual tokens. Matching is local, deterministic, and never starts generation.
struct PlanThemePreset: Sendable {
    let name: String
    let family: String
    let accent: String
    let darkAccent: String
    let glow: String
    let surface: String
    let motif: String
    let symbol: String
    let caption: String
    let keywords: [String]
    let corner: Double
    let editorial: Bool
}

enum PlanAtmosphere: String, CaseIterable, Sendable {
    case classic, rain, romance, evening, forest, seaside, sunset
    case craft, reading, gallery, dining, future, garden

    static var presets: [Self] { allCases.filter { $0 != .classic } }
    var tokens: PlanThemePreset {
        switch self {
        case .classic: .init(name: "清朗蓝", family: "blue", accent: "2E6F9D", darkAccent: "8AC5EF", glow: "C6E4F3", surface: "F3F7FC", motif: "orbit", symbol: "sparkles", caption: "清晰、安静的默认界面", keywords: [], corner: 20, editorial: false)
        case .rain: .init(name: "雨雾青", family: "teal", accent: "216E73", darkAccent: "86D4CB", glow: "BADED8", surface: "F0F7F5", motif: "ripple", symbol: "cloud.drizzle", caption: "雾面青绿，细细的水波", keywords: ["雨", "避雨", "慢享", "水乡", "烟雨"], corner: 24, editorial: false)
        case .romance: .init(name: "柔雾粉", family: "pink", accent: "A04468", darkAccent: "F3AEC6", glow: "F2C9D5", surface: "FCF3F6", motif: "petal", symbol: "heart", caption: "淡粉留白，柔软的花瓣曲线", keywords: ["微浪漫", "浪漫", "温柔", "约会", "甜蜜", "烛光"], corner: 26, editorial: false)
        case .evening: .init(name: "暮色紫", family: "violet", accent: "655193", darkAccent: "C2B1F1", glow: "D6CEF1", surface: "F5F2FA", motif: "orbit", symbol: "moon.stars", caption: "浅紫夜幕，疏落的星轨", keywords: ["夜色", "夜景", "轻步", "暮", "星空", "晚风", "夜游"], corner: 24, editorial: false)
        case .forest: .init(name: "林间苔绿", family: "green", accent: "47703E", darkAccent: "B5D6A0", glow: "CFDFC0", surface: "F4F7EF", motif: "canopy", symbol: "leaf", caption: "草木绿与弧形叶影", keywords: ["森林", "林间", "自然", "徒步", "露营", "山野", "绿道", "植物"], corner: 24, editorial: false)
        case .seaside: .init(name: "海盐晴蓝", family: "blue", accent: "286FA3", darkAccent: "9BD4F3", glow: "C3E4F3", surface: "F0F7FC", motif: "wave", symbol: "water.waves", caption: "晴蓝留白，舒展的海浪", keywords: ["海", "湖", "游船", "滨水", "江边", "水岸", "沙滩"], corner: 24, editorial: false)
        case .sunset: .init(name: "落日杏橙", family: "orange", accent: "A55327", darkAccent: "F2BD91", glow: "F5D5B7", surface: "FFF6ED", motif: "horizon", symbol: "sun.horizon", caption: "奶杏色的日落与地平线", keywords: ["落日", "日落", "夕阳", "黄昏", "日出", "晚霞"], corner: 24, editorial: false)
        case .craft: .init(name: "陶土手作", family: "orange", accent: "985649", darkAccent: "E5B5A3", glow: "E8CDBD", surface: "FAF3ED", motif: "arch", symbol: "hands.sparkles", caption: "陶土与奶油白，圆拱形细节", keywords: ["手作", "手工", "陶艺", "陶", "DIY", "工坊", "纪念物", "非遗"], corner: 28, editorial: false)
        case .reading: .init(name: "暖纸书房", family: "gold", accent: "806426", darkAccent: "DAC68F", glow: "E8DAB4", surface: "FAF7EE", motif: "paper", symbol: "book", caption: "暖纸、墨棕与衬线标题", keywords: ["书", "阅读", "茶叙", "茶事", "书香", "茶馆", "茶室"], corner: 16, editorial: true)
        case .gallery: .init(name: "银灰艺廊", family: "slate", accent: "526775", darkAccent: "B4CAD8", glow: "D5E0E6", surface: "F3F6F8", motif: "grid", symbol: "square.grid.2x2", caption: "冷灰展签，克制的细框构图", keywords: ["美术", "展览", "画廊", "艺术", "博物", "看展", "文化"], corner: 14, editorial: true)
        case .dining: .init(name: "莓酒晚宴", family: "pink", accent: "993E4D", darkAccent: "E8A8B3", glow: "EBC4CB", surface: "FCF1F2", motif: "ribbon", symbol: "wineglass", caption: "淡莓红与细长丝带", keywords: ["美食", "晚宴", "品酒", "小酌", "寻味", "餐酒", "饕餮", "味蕾"], corner: 22, editorial: true)
        case .future: .init(name: "冰蓝幻境", family: "blue", accent: "405CAC", darkAccent: "ADBFF5", glow: "D1DDFB", surface: "F1F5FD", motif: "prism", symbol: "sparkle", caption: "冰蓝棱镜，轻盈的几何光面", keywords: ["XR", "VR", "科幻", "幻境", "沉浸", "潮玩", "电玩", "科技"], corner: 18, editorial: false)
        case .garden: .init(name: "丁香花园", family: "violet", accent: "865083", darkAccent: "DBB1DB", glow: "E6CEE7", surface: "FAF2FA", motif: "bloom", symbol: "camera.macro", caption: "丁香浅紫，留白中的小花影", keywords: ["花园", "赏花", "花季", "樱花", "花海", "花市", "花艺"], corner: 26, editorial: false)
        }
    }
    var name: String { tokens.name }

    static func palette(titles: [String]) -> [Self] { palette(contexts: titles.map { .init(title: $0) }) }

    /// Joint assignment reserves distinct color families and optimizes relevance across all three plans.
    static func palette(contexts: [PlanThemeContext]) -> [Self] {
        guard !contexts.isEmpty else { return [] }
        let inputs = Array(contexts.prefix(3))
        var best: [Self] = []
        var bestScore = Int.min
        func score(_ theme: Self, _ input: PlanThemeContext, _ index: Int) -> Int {
            let title = input.title.lowercased(), detail = input.detail.lowercased()
            let relevance = theme.tokens.keywords.reduce(0) { sum, keyword in
                let term = keyword.lowercased()
                return sum + (title.contains(term) ? 12 : 0) + (detail.contains(term) ? 4 : 0)
            }
            // Stable tie breaks; semantic matches always outweigh index defaults.
            return relevance * 100 + ([Self.rain, .romance, .evening][index] == theme ? 10 : 0)
        }
        let scores = inputs.enumerated().map { index, input in
            Dictionary(uniqueKeysWithValues: presets.map { ($0, score($0, input, index)) })
        }
        func visit(_ chosen: [Self], _ total: Int) {
            let index = chosen.count
            if index == inputs.count {
                if total > bestScore { bestScore = total; best = chosen }
                return
            }
            for theme in presets where !chosen.contains(where: { $0.tokens.family == theme.tokens.family }) {
                visit(chosen + [theme], total + (scores[index][theme] ?? 0))
            }
        }
        visit([], 0)
        // Current product has three plans. Additional callers still receive a safe, deterministic palette.
        return best + contexts.dropFirst(3).enumerated().map { presets[$0.offset % presets.count] }
    }
}
