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

    func toggleHaptics() {
        hapticsEnabled.toggle()
        UserDefaults.standard.set(hapticsEnabled, forKey: "hapticsEnabled")
    }

    func collectCoin() {
        coins += 1
        BallCollectionStore.coins = coins
    }

    func selectBall(_ style: BallStyle) {
        guard unlockedBalls.contains(style) else { return }
        selectedBallStyle = style
        BallCollectionStore.selected = style
    }

    func drawBall() -> BallDrawResult? {
        guard coins >= 10, let style = BallStyle.allCases.randomElement() else { return nil }
        coins -= 10
        let result: BallDrawResult
        if unlockedBalls.insert(style).inserted {
            BallCollectionStore.unlocked = unlockedBalls
            selectedBallStyle = style
            BallCollectionStore.selected = style
            result = .unlocked(style)
        } else {
            let refund = 5
            coins += refund
            result = .duplicate(style, refund: refund)
        }
        BallCollectionStore.coins = coins
        return result
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
