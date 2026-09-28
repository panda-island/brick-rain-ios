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

    func testPolygonBallsSpinInFlight() {
        let spinning = Set(BallStyle.allCases.filter(\.spinsInFlight))
        XCTAssertEqual(spinning, Set([.triangle, .hexagon, .pixel, .star]))
        XCTAssertFalse(BallStyle.mini.spinsInFlight)
    }

    func testVolleyCompletionUsesActualVisibleBalls() {
        XCTAssertTrue(GameScene.volleyIsComplete(ballsToLaunch: 0, visibleBallCount: 0))
        XCTAssertFalse(GameScene.volleyIsComplete(ballsToLaunch: 1, visibleBallCount: 0))
        XCTAssertFalse(GameScene.volleyIsComplete(ballsToLaunch: 0, visibleBallCount: 1))
    }

    func testFastBallIsReflectedBackInsideEveryWall() {
        let left = GameScene.containedFlight(
            position: CGPoint(x: -20, y: 300), velocity: CGVector(dx: -1_040, dy: 200),
            radius: 5, boardWidth: 390, ceilingY: 700
        )
        XCTAssertEqual(left.position.x, 5)
        XCTAssertGreaterThan(left.velocity.dx, 0)

        let topRight = GameScene.containedFlight(
            position: CGPoint(x: 410, y: 720), velocity: CGVector(dx: 1_040, dy: 900),
            radius: 5, boardWidth: 390, ceilingY: 700
        )
        XCTAssertEqual(topRight.position.x, 385)
        XCTAssertEqual(topRight.position.y, 695)
        XCTAssertLessThan(topRight.velocity.dx, 0)
        XCTAssertLessThan(topRight.velocity.dy, 0)
    }

    func testHighRoundVolleyLaunchesWithinAReasonableWindow() {
        let normal = GameScene.adaptiveLaunchInterval(totalBallCount: 1_000, isFastForwarding: false)
        let fast = GameScene.adaptiveLaunchInterval(totalBallCount: 1_000, isFastForwarding: true)
        XCTAssertLessThanOrEqual(normal * 1_000, 22.01)
        XCTAssertEqual(fast, normal / 2, accuracy: 0.000_001)
        XCTAssertEqual(GameScene.adaptiveLaunchInterval(totalBallCount: 10, isFastForwarding: false), 0.075)
    }

    func testFourDigitBrickValuesFitInsideTheBrick() {
        let threeDigits = GameScene.brickLabelFontSize(value: 999, cellSize: 56)
        let fourDigits = GameScene.brickLabelFontSize(value: 1_000, cellSize: 56)
        let fiveDigits = GameScene.brickLabelFontSize(value: 10_000, cellSize: 56)
        XCTAssertLessThan(fourDigits, threeDigits)
        XCTAssertLessThan(fiveDigits, fourDigits)
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
