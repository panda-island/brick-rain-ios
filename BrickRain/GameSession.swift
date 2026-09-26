import Foundation
import Observation

@MainActor
@Observable
final class GameSession {
    enum Phase: Equatable {
        case ready
        case aiming
        case firing
        case gameOver
    }

    var round = 1
    var ballCount = 1
    var hitCount = 0
    var bestRound = UserDefaults.standard.integer(forKey: "bestRound")
    var phase: Phase = .ready
    var soundEnabled = true
    var hapticsEnabled = UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    var canRecall = false
    var coins = BallCollectionStore.coins
    var unlockedBalls = BallCollectionStore.unlocked
    var selectedBallStyle = BallCollectionStore.selected
    var canDrawBall: Bool { coins >= 10 && unlockedBalls.count < BallStyle.allCases.count }

    func toggleHaptics() {
        hapticsEnabled.toggle()
        UserDefaults.standard.set(hapticsEnabled, forKey: "hapticsEnabled")
    }

    func collectCoin() {
        coins += 1
        BallCollectionStore.coins = coins
    }

    @discardableResult
    func spendCoins(_ amount: Int) -> Bool {
        guard amount > 0, coins >= amount else { return false }
        coins -= amount
        BallCollectionStore.coins = coins
        return true
    }

    func selectBall(_ style: BallStyle) {
        guard unlockedBalls.contains(style) else { return }
        selectedBallStyle = style
        BallCollectionStore.selected = style
    }

    func drawBall() -> BallDrawResult? {
        let lockedStyles = BallStyle.allCases.filter { !unlockedBalls.contains($0) }
        guard coins >= 10, let style = lockedStyles.randomElement() else { return nil }
        coins -= 10
        unlockedBalls.insert(style)
        BallCollectionStore.unlocked = unlockedBalls
        selectedBallStyle = style
        BallCollectionStore.selected = style
        BallCollectionStore.coins = coins
        return .unlocked(style)
    }

    func update(round: Int, ballCount: Int, hitCount: Int, phase: Phase, canRecall: Bool = false) {
        self.round = round
        self.ballCount = ballCount
        self.hitCount = hitCount
        self.phase = phase
        self.canRecall = canRecall
        if round > bestRound {
            bestRound = round
            UserDefaults.standard.set(round, forKey: "bestRound")
        }
    }
}
