import Foundation
import Observation

enum ParticleEffectLevel: Int, CaseIterable, Identifiable {
    case low
    case standard
    case high

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .low: return "低"
        case .standard: return "標準"
        case .high: return "高"
        }
    }
}

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
    var soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
    var hapticsEnabled = UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    var highRefreshRateEnabled = UserDefaults.standard.bool(forKey: "highRefreshRateEnabled")
    var particleEffectLevel: ParticleEffectLevel = {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "particleEffectLevel") != nil else { return .standard }
        return ParticleEffectLevel(rawValue: defaults.integer(forKey: "particleEffectLevel")) ?? .standard
    }()
    var canRecall = false
    var canFastForward = false
    var isFastForwarding = false
    var coins = BallCollectionStore.coins
    var unlockedBalls = BallCollectionStore.unlocked
    var selectedBallStyle = BallCollectionStore.selected
    var canDrawBall: Bool { coins >= 10 && unlockedBalls.count < BallStyle.allCases.count }

    func toggleHaptics() {
        hapticsEnabled.toggle()
        UserDefaults.standard.set(hapticsEnabled, forKey: "hapticsEnabled")
    }

    func setSoundEnabled(_ enabled: Bool) {
        soundEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "soundEnabled")
    }

    func setHapticsEnabled(_ enabled: Bool) {
        hapticsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "hapticsEnabled")
    }

    func setHighRefreshRateEnabled(_ enabled: Bool) {
        highRefreshRateEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "highRefreshRateEnabled")
    }

    func setParticleEffectLevel(_ level: ParticleEffectLevel) {
        particleEffectLevel = level
        UserDefaults.standard.set(level.rawValue, forKey: "particleEffectLevel")
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

    func update(
        round: Int,
        ballCount: Int,
        hitCount: Int,
        phase: Phase,
        canRecall: Bool = false,
        canFastForward: Bool = false
    ) {
        self.round = round
        self.ballCount = ballCount
        self.hitCount = hitCount
        self.phase = phase
        self.canRecall = canRecall
        self.canFastForward = canFastForward
        if round > bestRound {
            bestRound = round
            UserDefaults.standard.set(round, forKey: "bestRound")
        }
    }
}
