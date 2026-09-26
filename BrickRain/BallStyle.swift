import Foundation

enum BallStyle: String, CaseIterable, Codable, Identifiable {
    case classic
    case mini
    case triangle
    case comet
    case hexagon
    case pixel
    case giant
    case phantom
    case rainbow
    case star

    var id: String { rawValue }

    var name: String {
        switch self {
        case .classic: return "經典核心"
        case .mini: return "迷你穿梭球"
        case .triangle: return "稜鏡三角球"
        case .comet: return "彗星火球"
        case .hexagon: return "薄荷六角球"
        case .pixel: return "像素方球"
        case .giant: return "泰坦大球"
        case .phantom: return "幽影球"
        case .rainbow: return "彩虹脈衝球"
        case .star: return "星芒球"
        }
    }

    var detail: String {
        switch self {
        case .classic: return "穩定的標準尺寸與光環打擊"
        case .mini: return "最小圓球，可穿過相鄰方塊的窄縫"
        case .triangle: return "三角外型，撞擊時迸出稜鏡光線"
        case .comet: return "拖著橘紅尾焰，撞擊時爆出火花"
        case .hexagon: return "大型六角外框，撞擊時展開能量環"
        case .pixel: return "小型方形球，撞擊時散出像素碎片"
        case .giant: return "目前最大的球，撞擊時產生重型震波"
        case .phantom: return "半透明球體，撞擊時留下雙層幽影"
        case .rainbow: return "拖出變色光跡，撞擊時綻放彩色火花"
        case .star: return "星形外觀，撞擊時放射五道星芒"
        }
    }

    var radius: CGFloat {
        switch self {
        case .classic: return 5.5
        case .mini: return 2.3
        case .triangle: return 6.2
        case .comet: return 5.1
        case .hexagon: return 6.4
        case .pixel: return 4.6
        case .giant: return 8.4
        case .phantom: return 5.3
        case .rainbow: return 5.7
        case .star: return 6.1
        }
    }

    var spinsInFlight: Bool {
        switch self {
        case .triangle, .hexagon, .pixel, .star: return true
        default: return false
        }
    }
}

enum BallDrawResult: Equatable {
    case unlocked(BallStyle)
}

enum BallCollectionStore {
    private static let coinsKey = "brickRain.coins.v1"
    private static let unlockedKey = "brickRain.unlockedBalls.v1"
    private static let selectedKey = "brickRain.selectedBall.v1"

    static var coins: Int {
        get { max(0, UserDefaults.standard.integer(forKey: coinsKey)) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: coinsKey) }
    }

    static var unlocked: Set<BallStyle> {
        get {
            let saved = UserDefaults.standard.stringArray(forKey: unlockedKey) ?? []
            return Set(saved.compactMap(BallStyle.init(rawValue:))).union([.classic])
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: unlockedKey)
        }
    }

    static var selected: BallStyle {
        get {
            guard let raw = UserDefaults.standard.string(forKey: selectedKey),
                  let style = BallStyle(rawValue: raw), unlocked.contains(style) else { return .classic }
            return style
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: selectedKey) }
    }
}
