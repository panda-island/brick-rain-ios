import Foundation

struct GameProgress: Codable, Equatable {
    struct BoardObject: Codable, Equatable {
        enum Kind: String, Codable {
            case brick
            case triangleBrick
            case extraBall
            case spring
            case laserVertical
            case laserHorizontal
            case laserCross
            case coin
        }

        let kind: Kind
        let xFraction: Double
        let yFraction: Double
        let value: Int
        let orientation: Int?
        let rowFromSpawn: Double?

        init(
            kind: Kind,
            xFraction: Double,
            yFraction: Double,
            value: Int,
            orientation: Int?,
            rowFromSpawn: Double? = nil
        ) {
            self.kind = kind
            self.xFraction = xFraction
            self.yFraction = yFraction
            self.value = value
            self.orientation = orientation
            self.rowFromSpawn = rowFromSpawn
        }
    }

    let round: Int
    let ballCount: Int
    let hitCount: Int
    let launchXFraction: Double
    let objects: [BoardObject]
}

enum ProgressStore {
    // Bump this key when a release changes board geometry so stale coordinates
    // cannot make an upgraded app look or behave like the previous version.
    private static let key = "brickRain.savedProgress.v7"
    private static let legacyKeys = ["brickRain.savedProgress.v6", "brickRain.savedProgress.v5"]

    static func load() -> GameProgress? {
        let defaults = UserDefaults.standard
        for candidate in [key] + legacyKeys {
            guard let data = defaults.data(forKey: candidate),
                  let progress = try? JSONDecoder().decode(GameProgress.self, from: data) else { continue }
            if candidate != key { save(progress) }
            return progress
        }
        return nil
    }

    static func save(_ progress: GameProgress) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        for legacyKey in legacyKeys { UserDefaults.standard.removeObject(forKey: legacyKey) }
    }
}
