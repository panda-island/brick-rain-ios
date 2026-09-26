import Foundation
import XCTest
@testable import BrickRain

@MainActor
final class BrickRainTests: XCTestCase {
    func testSessionKeepsHighestRound() {
        let key = "bestRound"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set(3, forKey: key)
        let session = GameSession()
        session.update(round: 7, ballCount: 2, hitCount: 9, phase: .ready)
        session.update(round: 4, ballCount: 2, hitCount: 10, phase: .ready)
        XCTAssertEqual(session.bestRound, 7)
    }

    func testProgressRoundTripsThroughJSON() throws {
        let progress = GameProgress(
            round: 12,
            ballCount: 7,
            hitCount: 88,
            launchXFraction: 0.4,
            objects: [.init(kind: .laserCross, xFraction: 0.5, yFraction: 0.8, value: 0, orientation: nil, rowFromSpawn: 3)]
        )
        let data = try JSONEncoder().encode(progress)
        XCTAssertEqual(try JSONDecoder().decode(GameProgress.self, from: data), progress)
    }

    func testMiniBallFitsWhereClassicBallCannot() {
        let cellSize: CGFloat = 390 / 7
        let gap = cellSize * (1 - 0.89)
        XCTAssertLessThan(BallStyle.mini.radius * 2, gap)
        XCTAssertGreaterThan(BallStyle.classic.radius * 2, gap)
    }

    func testEveryDrawStyleHasAUniqueIdentifier() {
        XCTAssertEqual(Set(BallStyle.allCases.map(\.rawValue)).count, BallStyle.allCases.count)
        XCTAssertEqual(BallStyle.allCases.count, 10)
    }

    func testSavedObjectsSnapBackToWholeRows() {
        let cellSize: CGFloat = 390 / 7
        let spawnY: CGFloat = 700 - 12 - cellSize * 1.5
        XCTAssertEqual(GameScene.snappedRow(positionY: spawnY - cellSize * 3.42, spawnY: spawnY, cellSize: cellSize), 3)
        XCTAssertEqual(GameScene.snappedRow(positionY: spawnY - cellSize * 3.58, spawnY: spawnY, cellSize: cellSize), 4)
    }

    func testBrickLosesOneFullRowAboveTheFloor() {
        let cellSize: CGFloat = 56
        let floorY: CGFloat = 30
        let lossLineY = floorY + cellSize
        let touchingCenter = lossLineY + cellSize * 0.445
        XCTAssertTrue(GameScene.brickTouchesLossLine(centerY: touchingCenter, cellSize: cellSize, lossLineY: lossLineY))
        XCTAssertFalse(GameScene.brickTouchesLossLine(centerY: touchingCenter + 1, cellSize: cellSize, lossLineY: lossLineY))
    }

    func testReviveSpendsTenPersistentCoins() {
        let key = "brickRain.coins.v1"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set(12, forKey: key)
        let session = GameSession()
        XCTAssertTrue(session.spendCoins(10))
        XCTAssertEqual(session.coins, 2)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: key), 2)
        XCTAssertFalse(session.spendCoins(10))
        XCTAssertEqual(session.coins, 2)
    }
}
