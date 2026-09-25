import SpriteKit
import SwiftUI

struct ContentView: View {
    @State private var session = GameSession()
    @State private var sceneID = UUID()

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.065, blue: 0.09)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScoreHeader(
                    round: session.round,
                    ballCount: session.ballCount,
                    hitCount: session.hitCount,
                    bestRound: session.bestRound,
                    soundEnabled: session.soundEnabled,
                    onToggleSound: { session.soundEnabled.toggle() }
                )

                GameBoardView(session: session, sceneID: sceneID)
                    .id(sceneID)
            }

            if session.phase == .gameOver {
                GameOverCard(round: session.round) {
                    session = GameSession()
                    sceneID = UUID()
                }
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact, trigger: session.round)
    }
}

private struct ScoreHeader: View {
    let round: Int
    let ballCount: Int
    let hitCount: Int
    let bestRound: Int
    let soundEnabled: Bool
    let onToggleSound: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("BRICK RAIN • UPDATE 1.3 ACTIVE")
                .font(.caption.bold())
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(.yellow)
                .accessibilityLabel("Brick Rain update 1.3 active")

            HStack(spacing: 16) {
                StatBlock(title: "ROUND", value: round, prominent: true)
                StatBlock(title: "HITS", value: hitCount)
                    .accessibilityLabel("Total hits \(hitCount)")
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    StatBlock(title: "BEST", value: bestRound)
                    Text(appVersion)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Button(action: onToggleSound) {
                    Image(systemName: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(soundEnabled ? "Mute sound" : "Enable sound")
            }

            HStack(spacing: 12) {
                Label("\(ballCount)", systemImage: "circle.fill")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(.cyan)
                    .accessibilityLabel("\(ballCount) balls")
                Spacer()
                PowerUpKey(symbol: "+1", color: .cyan, label: "ball")
                PowerUpKey(symbol: "↟", color: .purple, label: "spring")
                PowerUpKey(symbol: "↕", color: .yellow, label: "vertical laser")
                PowerUpKey(symbol: "↔", color: .orange, label: "horizontal laser")
                PowerUpKey(symbol: "✣", color: .pink, label: "cross laser")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.black.opacity(0.22))
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(version) (\(build))"
    }
}

private struct StatBlock: View {
    let title: String
    let value: Int
    var prominent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: prominent ? 28 : 19, weight: .black, design: .rounded))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PowerUpKey: View {
    let symbol: String
    let color: Color
    let label: String

    var body: some View {
        Text(symbol)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(color, lineWidth: 1.5))
            .accessibilityLabel(label)
    }
}

private struct GameBoardView: View {
    let session: GameSession
    let sceneID: UUID
    @State private var scene: GameScene

    init(session: GameSession, sceneID: UUID) {
        self.session = session
        self.sceneID = sceneID
        self.scene = GameScene(size: CGSize(width: 390, height: 700), session: session)
        self.scene.scaleMode = .resizeFill
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                SpriteView(scene: scene)
                    .ignoresSafeArea(edges: .bottom)
                    .accessibilityLabel("Brick Rain game board. Drag to aim and release to fire.")
                    .accessibilityHint("Clear numbered bricks before they reach the bottom.")
                    .onAppear { scene.size = proxy.size }
                    .onChange(of: proxy.size) { _, newSize in scene.size = newSize }

                Button {
                    scene.recallAllBalls()
                } label: {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.headline.weight(.bold))
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.65), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.28)))
                }
                .buttonStyle(.plain)
                .disabled(!session.canRecall)
                .opacity(session.canRecall ? 1 : 0.3)
                .padding(16)
                .accessibilityLabel("Recall all balls")
                .accessibilityHint(session.canRecall ? "Ends the current volley" : "Available while balls are moving")
            }
        }
    }
}

private struct GameOverCard: View {
    let round: Int
    let onRestart: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("GAME OVER")
                .font(.system(size: 34, weight: .black, design: .rounded))
            Text("You reached round \(round)")
                .foregroundStyle(.secondary)
            Button("PLAY AGAIN", action: onRestart)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.cyan)
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.12)))
        .padding(28)
        .transition(.scale.combined(with: .opacity))
    }
}

#Preview {
    ContentView()
}
