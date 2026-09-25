import Foundation

struct GameProgress: Codable, Equatable {
    struct BoardObject: Codable, Equatable {
        enum Kind: String, Codable {
            case brick
            case extraBall
            case spring
            case laserVertical
            case laserHorizontal
            case laserCross
        }

        let kind: Kind
        let xFraction: Double
        let yFraction: Double
        let value: Int
    }

    let round: Int
    let ballCount: Int
    let hitCount: Int
    let launchXFraction: Double
    let objects: [BoardObject]
}

enum ProgressStore {
    private static let key = "brickRain.savedProgress.v1"

    static func load() -> GameProgress? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GameProgress.self, from: data)
    }

    static func save(_ progress: GameProgress) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

