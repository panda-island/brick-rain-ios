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
        XCTAssertEqual(BallStyle.allCases.count, 6)
    }
}
