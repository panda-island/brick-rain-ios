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
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ROUND")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("\(round)")
                    .font(.system(size: 30, weight: .black, design: .rounded))
            }

            Label("\(ballCount)", systemImage: "circle.fill")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.cyan)
                .accessibilityLabel("\(ballCount) balls")

            VStack(spacing: 1) {
                Text("HITS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("\(hitCount)")
                    .font(.headline.monospacedDigit())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Total hits \(hitCount)")

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("BEST")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("\(bestRound)")
                    .font(.headline.monospacedDigit())
            }

            Button(action: onToggleSound) {
                Image(systemName: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(soundEnabled ? "Mute sound" : "Enable sound")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.black.opacity(0.22))
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

                if session.canRecall {
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
                    .padding(16)
                    .accessibilityLabel("Recall all balls")
                }
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
