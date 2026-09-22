import Foundation

struct ItineraryStop: Identifiable, Hashable {
    let id: String
    let time: String
    let title: String
    let place: String
    let city: String
    let address: String?
    let addressSource: String?
    let addressSourceURL: URL?
    let summary: String
    let meta: String
    let reason: String
    let transit: String
    let openingHours: String
    let price: String
    let source: String
    let sourceURL: URL
    let verification: String
    let costEstimate: Int
}

struct ItineraryPlan: Identifiable, Hashable {
    let id: Int
    let title: String
    let subtitle: String
    let selection: [Int]
}

enum DemoItinerary {
    static let plans = [
        ItineraryPlan(id: 0, title: "小城慢慢逛", subtitle: "街巷、手作和运河晚餐，转场集中", selection: [0, 0, 0]),
        ItineraryPlan(id: 1, title: "湖边吹吹风", subtitle: "游船、甜品和湖滨晚餐，适合晴天", selection: [1, 1, 1]),
        ItineraryPlan(id: 2, title: "雨天也从容", subtitle: "小展、轻运动和夜景晚餐，全程室内", selection: [2, 2, 2])
    ]

    static let choices: [[ItineraryStop]] = [
        [
            stop(
                id: "afternoon-citywalk", time: "14:00", title: "小河直街慢慢逛", place: "小河直街历史文化街区",
                address: "浙江省杭州市拱墅区小河直街51号", addressSource: "高德地图地点页",
                addressSourceURL: URL(string: "https://ditu.amap.com/place/B0FFFWQ8DS"),
                summary: "沿河 Citywalk，随时可以坐下休息", meta: "约 90 分钟",
                reason: "小红书公开杭州约会内容中反复出现安静、小众、Citywalk 等体验诉求，适合把第一段安排得松弛。",
                transit: "具体起点与路线待地图工具核实", price: "免费体验；现场消费另计", cost: 0,
                source: "小红书灵感：杭州约会、Citywalk", query: "杭州约会 citywalk"
            ),
            stop(
                id: "afternoon-boat", time: "14:00", title: "西湖上坐一会儿", place: "西湖游船湖滨一公园码头",
                address: "浙江省杭州市上城区南山路197号", addressSource: "杭州市民卡服务厅",
                addressSourceURL: URL(string: "https://www.96225.com/smknet/service/merchant_searchMerInfo.action?ishit=1&mer.mermerchantid=8a8a8ae2451ca29b01451ca86a6b1539"),
                summary: "用一段慢船程代替连续步行", meta: "约 60–90 分钟",
                reason: "小红书公开搜索中出现西湖游船与低强度双人玩法，适合希望少走路又保留杭州感的约会。",
                transit: "码头位置、排队与天气待地图和现场信息核实", price: "价格待核实", cost: 180,
                source: "小红书灵感：西湖游船玩法", query: "杭州约会 西湖游船"
            ),
            stop(
                id: "afternoon-gallery", time: "14:00", title: "先看一个室内小展", place: "中国丝绸博物馆",
                address: "浙江省杭州市玉皇山路73-1号", addressSource: "中国丝绸博物馆官网",
                addressSourceURL: URL(string: "https://www.chinasilkmuseum.com/xwdtIR/info_9.aspx?itemid=4389"),
                summary: "雨天不赶路，也留有聊天内容", meta: "约 90 分钟",
                reason: "小红书公开结果中有高温不出汗、室内约会等主题，室内展览可以降低天气与体力影响。",
                transit: "具体场馆和当日展览待场馆与地图工具核实", price: "票价待核实", cost: 120,
                source: "小红书灵感：杭州室内约会", query: "杭州室内约会"
            )
        ],
        [
            stop(
                id: "late-market", time: "16:20", title: "一起逛二手市场", place: "杭州周末二手市场候选",
                summary: "边逛边聊，各自挑一件有趣的小东西", meta: "约 80 分钟",
                reason: "小红书公开搜索结果出现情侣周末逛二手市场的体验内容，互动比单纯打卡更自然。",
                transit: "当周市集地点与开放时间待活动页核实", price: "免费入场；购物另计", cost: 80,
                source: "小红书灵感：情侣周末逛二手市场", query: "杭州情侣 二手市场"
            ),
            stop(
                id: "late-dessert", time: "16:20", title: "留一段下午茶", place: "湖滨安静甜品店候选",
                summary: "坐下来休息，把聊天时间留足", meta: "约 70 分钟",
                reason: "下午茶是小红书杭州约会搜索中的直接关联主题，适合作为行程中段的休息锚点。",
                transit: "具体店铺与上一站路线待地图工具核实", price: "预计双人 ¥120–180", cost: 150,
                source: "小红书灵感：杭州约会、下午茶", query: "杭州约会 下午茶"
            ),
            stop(
                id: "late-sport", time: "16:20", title: "打一小时羽毛球", place: "市区室内羽毛球馆候选",
                summary: "一点轻运动，让雨天不只是坐着", meta: "约 60 分钟",
                reason: "小红书公开杭州约会结果中出现羽毛球约会经验，适合喜欢轻运动的两个人。",
                transit: "场馆距离与空场情况待地图和订场平台核实", price: "场地费待核实", cost: 120,
                source: "小红书灵感：杭州羽毛球约会", query: "杭州 羽毛球 约会"
            )
        ],
        [
            stop(
                id: "dinner-canal", time: "18:40", title: "运河边安静吃饭", place: "桥西历史街区餐厅候选",
                summary: "结束后还能沿河走一小段", meta: "预计双人 ¥360–460",
                reason: "与小河直街和桥西路线集中，减少晚间折返；具体餐厅仍需按口味与营业信息筛选。",
                transit: "与前一站的路线待地图工具核实", price: "预计双人 ¥360–460", cost: 410,
                source: "小红书灵感：杭州约会、漂亮饭", query: "杭州约会 漂亮饭"
            ),
            stop(
                id: "dinner-lakeside", time: "18:40", title: "湖滨吃一顿晚餐", place: "湖滨安静餐厅候选",
                summary: "和游船、下午茶在同一区域完成", meta: "预计双人 ¥420–520",
                reason: "把三段体验放在湖滨附近，可以减少交通；餐厅需要进一步按噪声、等位与返程筛选。",
                transit: "步行距离与返程时间待地图工具核实", price: "预计双人 ¥420–520", cost: 470,
                source: "小红书灵感：杭州约会、餐厅", query: "杭州约会 安静餐厅"
            ),
            stop(
                id: "dinner-view", time: "18:40", title: "室内看夜景吃饭", place: "杭州高层景观餐厅候选",
                summary: "雨天也保留一点特别的收尾", meta: "预计双人 ¥460–600",
                reason: "小红书杭州约会搜索包含餐厅、漂亮饭与私人空间等主题，可以作为雨天方案的浪漫收尾。",
                transit: "具体店铺、靠窗位置与返程待核实", price: "预计双人 ¥460–600", cost: 530,
                source: "小红书灵感：杭州漂亮饭、私人空间", query: "杭州约会 漂亮饭 私人空间"
            )
        ]
    ]

    private static func stop(
        id: String, time: String, title: String, place: String,
        address: String? = nil, addressSource: String? = nil, addressSourceURL: URL? = nil,
        summary: String, meta: String,
        reason: String, transit: String, price: String, cost: Int, source: String, query: String
    ) -> ItineraryStop {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = URL(string: "https://www.xiaohongshu.com/search_result?keyword=\(encoded)")!

        return ItineraryStop(
            id: id, time: time, title: title, place: place, city: "杭州", address: address,
            addressSource: addressSource, addressSourceURL: addressSourceURL,
            summary: summary, meta: meta, reason: reason,
            transit: transit, openingHours: "营业与开放信息待核实", price: price, source: source,
            sourceURL: url, verification: "体验来自公开内容线索；地点事实、价格与路线尚未实时核对",
            costEstimate: cost
        )
    }
}
