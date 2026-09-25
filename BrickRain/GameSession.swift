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
    var bestRound = UserDefaults.standard.integer(forKey: "bestRound")
    var phase: Phase = .ready
    var soundEnabled = true

    func update(round: Int, ballCount: Int, phase: Phase) {
        self.round = round
        self.ballCount = ballCount
        self.phase = phase
        if round > bestRound {
            bestRound = round
            UserDefaults.standard.set(round, forKey: "bestRound")
        }
    }
}

