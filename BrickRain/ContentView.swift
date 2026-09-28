import SpriteKit
import SwiftUI

struct ContentView: View {
    private enum Screen: Equatable { case home, game }

    @State private var session = GameSession()
    @State private var screen: Screen = .home
    @State private var sceneID = UUID()
    @State private var recoveryRequest = 0
    @State private var drawResult: BallDrawResult?
    @State private var showsGameMenu = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.035, green: 0.045, blue: 0.08), Color(red: 0.08, green: 0.055, blue: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if screen == .home {
                HomeView(session: session, onPlay: startGame, onDraw: { drawResult = session.drawBall() })
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                gameView.transition(.opacity)
            }

            if let drawResult {
                DrawResultCard(result: drawResult) { self.drawResult = nil }
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: screen)
        .animation(.spring(response: 0.4, dampingFraction: 0.72), value: drawResult != nil)
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact, trigger: session.round)
    }

    private var gameView: some View {
        VStack(spacing: 0) {
            ScoreHeader(
                round: session.round,
                hitCount: session.hitCount,
                bestRound: session.bestRound,
                coins: session.coins,
                canOpenMenu: session.phase != .firing && session.phase != .aiming,
                onMenu: { showsGameMenu = true }
            )
            GameBoardView(session: session, sceneID: sceneID, recoveryRequest: recoveryRequest).id(sceneID)
        }
        .overlay {
            if session.phase == .gameOver {
                ZStack {
                    Color.black.opacity(0.62)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { }
                    GameOverCard(
                        round: session.round,
                        coins: session.coins,
                        onHome: { screen = .home },
                        onContinue: {
                            guard session.spendCoins(10) else { return }
                            recoveryRequest += 1
                        },
                        onRestart: {
                            ProgressStore.clear()
                            let selected = session.selectedBallStyle
                            session = GameSession()
                            session.selectBall(selected)
                            sceneID = UUID()
                        }
                    )
                }
                .transition(.opacity)
            } else if showsGameMenu {
                ZStack {
                    Color.black.opacity(0.62)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { showsGameMenu = false }
                    GameSettingsCard(
                        session: session,
                        onResume: { showsGameMenu = false },
                        onHome: {
                            showsGameMenu = false
                            screen = .home
                        }
                    )
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
    }

    private func startGame() {
        sceneID = UUID()
        screen = .game
    }
}

private struct HomeView: View {
    let session: GameSession
    let onPlay: () -> Void
    let onDraw: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("BRICK RAIN").font(.system(size: 38, weight: .black, design: .rounded))
                    Text("BALL LAB").font(.caption.weight(.black)).tracking(5).foregroundStyle(.cyan)
                }
                .padding(.top, 24)

                HStack(spacing: 8) {
                    Image(systemName: "circle.hexagongrid.fill").foregroundStyle(.yellow)
                    Text("\(session.coins)").font(.title2.weight(.black).monospacedDigit())
                    Text("金幣").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(.white.opacity(0.08), in: Capsule())

                BallPreview(style: session.selectedBallStyle, size: 88)
                    .frame(height: 102)
                    .shadow(color: ballColor(session.selectedBallStyle).opacity(0.65), radius: 24)

                VStack(spacing: 8) {
                    Text(session.selectedBallStyle.name).font(.title3.weight(.black))
                    Text(session.selectedBallStyle.detail)
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }

                Button(action: onPlay) {
                    Label("開始遊戲", systemImage: "play.fill")
                        .font(.headline.weight(.black)).frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent).tint(.cyan)

                Button(action: onDraw) {
                    HStack {
                        Label(session.unlockedBalls.count == BallStyle.allCases.count ? "球款已全數解鎖" : "抽一顆新球", systemImage: "sparkles")
                        Spacer()
                        if session.unlockedBalls.count < BallStyle.allCases.count {
                            Text("10")
                            Image(systemName: "circle.hexagongrid.fill").foregroundStyle(.yellow)
                        }
                    }
                    .font(.headline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.bordered).disabled(!session.canDrawBall)

                VStack(alignment: .leading, spacing: 10) {
                    Text("我的球").font(.headline.weight(.black))
                    ForEach(BallStyle.allCases) { style in
                        BallRow(
                            style: style,
                            isUnlocked: session.unlockedBalls.contains(style),
                            isSelected: session.selectedBallStyle == style,
                            onSelect: { session.selectBall(style) }
                        )
                    }
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 30)
        }
    }
}

private struct BallRow: View {
    let style: BallStyle
    let isUnlocked: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                BallPreview(style: style, size: 42)
                    .frame(width: 50, height: 50).saturation(isUnlocked ? 1 : 0).opacity(isUnlocked ? 1 : 0.28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isUnlocked ? style.name : "尚未解鎖").font(.subheadline.weight(.bold))
                    Text(isUnlocked ? style.detail : "收集 10 枚金幣抽取")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : isUnlocked ? "circle" : "lock.fill")
                    .foregroundStyle(isSelected ? Color.cyan : Color.secondary)
            }
            .padding(12)
            .background(isSelected ? Color.cyan.opacity(0.12) : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isSelected ? Color.cyan.opacity(0.65) : .white.opacity(0.08)))
        }
        .buttonStyle(.plain).disabled(!isUnlocked)
    }
}

private struct DrawResultCard: View {
    let result: BallDrawResult
    let onDismiss: () -> Void

    private var style: BallStyle {
        switch result {
        case .unlocked(let style): return style
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.68).ignoresSafeArea().onTapGesture(perform: onDismiss)
            VStack(spacing: 18) {
                Text("NEW BALL").font(.caption.weight(.black)).tracking(5).foregroundStyle(.cyan)
                BallPreview(style: style, size: 104)
                    .frame(height: 120).shadow(color: ballColor(style).opacity(0.8), radius: 28)
                Text(style.name).font(.system(size: 27, weight: .black, design: .rounded))
                switch result {
                case .unlocked:
                    Text("已解鎖並自動裝備").foregroundStyle(.secondary)
                }
                Button("收下", action: onDismiss).buttonStyle(.borderedProminent).tint(.cyan).controlSize(.large)
            }
            .padding(30)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(.cyan.opacity(0.4)))
            .padding(34)
        }
    }
}

private struct BallPreview: View {
    let style: BallStyle
    let size: CGFloat

    var body: some View {
        ZStack {
            if style == .triangle {
                Image(systemName: "triangle.fill").resizable().scaledToFit().foregroundStyle(ballColor(style))
                    .overlay(Image(systemName: "triangle").resizable().scaledToFit().foregroundStyle(.white.opacity(0.75)).padding(size * 0.21))
            } else if style == .hexagon {
                Image(systemName: "hexagon.fill").resizable().scaledToFit().foregroundStyle(ballColor(style))
                    .overlay(Image(systemName: "hexagon").resizable().scaledToFit().foregroundStyle(.white.opacity(0.8)).padding(size * 0.2))
            } else if style == .pixel {
                RoundedRectangle(cornerRadius: size * 0.08).fill(ballColor(style))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.08).stroke(.white.opacity(0.9), lineWidth: max(1, size * 0.05)))
                    .overlay(Image(systemName: "circle.grid.cross.fill").resizable().scaledToFit().padding(size * 0.26).foregroundStyle(.white.opacity(0.8)))
            } else if style == .star {
                Image(systemName: "star.fill").resizable().scaledToFit().foregroundStyle(ballColor(style))
                    .overlay(Image(systemName: "sparkle").resizable().scaledToFit().padding(size * 0.3).foregroundStyle(.white))
            } else if style == .diamond {
                Image(systemName: "diamond.fill").resizable().scaledToFit().foregroundStyle(ballColor(style))
                    .overlay(Image(systemName: "diamond").resizable().scaledToFit().padding(size * 0.2).foregroundStyle(.white))
            } else if style == .shuriken {
                ZStack {
                    Image(systemName: "star.fill").resizable().scaledToFit().foregroundStyle(ballColor(style))
                    Image(systemName: "diamond.fill").resizable().scaledToFit().padding(size * 0.25).foregroundStyle(.white)
                }
            } else {
                Circle().fill(ballColor(style))
                    .overlay(Circle().stroke(
                        style == .classic || style == .mini ? .clear : .white.opacity(0.9),
                        lineWidth: max(1, size * 0.045)
                    ))
                    .overlay {
                        if style == .classic || style == .mini {
                            EmptyView()
                        } else if style == .comet {
                            Image(systemName: "flame.fill").resizable().scaledToFit().padding(size * 0.24).foregroundStyle(.yellow)
                        } else if style == .giant {
                            Circle().stroke(.white.opacity(0.9), lineWidth: max(2, size * 0.08)).padding(size * 0.2)
                        } else if style == .phantom {
                            Image(systemName: "moon.haze.fill").resizable().scaledToFit().padding(size * 0.22).foregroundStyle(.white.opacity(0.85))
                        } else if style == .rainbow {
                            AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .pink, .red], center: .center)
                                .clipShape(Circle()).padding(size * 0.2)
                        } else if style == .nova {
                            Image(systemName: "sparkles").resizable().scaledToFit().padding(size * 0.22).foregroundStyle(.white)
                        } else if style == .bubble {
                            Circle().stroke(.white.opacity(0.75), lineWidth: max(1, size * 0.045)).padding(size * 0.2)
                        }
                    }
            }
        }
        .frame(width: style == .mini ? size * 0.52 : style == .pixel ? size * 0.8 : style == .giant ? size * 1.12 : size,
               height: style == .mini ? size * 0.52 : style == .pixel ? size * 0.8 : style == .giant ? size * 1.12 : size)
    }
}

private func ballColor(_ style: BallStyle) -> Color {
    switch style {
    case .classic: return .white
    case .mini: return .white
    case .triangle: return .pink
    case .comet: return .orange
    case .hexagon: return .mint
    case .pixel: return .green
    case .giant: return Color(red: 0.18, green: 0.42, blue: 1)
    case .phantom: return .purple.opacity(0.72)
    case .rainbow: return .cyan
    case .star: return .yellow
    case .diamond: return .pink
    case .shuriken: return .red
    case .nova: return .indigo
    case .bubble: return .cyan.opacity(0.65)
    }
}

private struct ScoreHeader: View {
    let round: Int
    let hitCount: Int
    let bestRound: Int
    let coins: Int
    let canOpenMenu: Bool
    let onMenu: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onMenu) { Image(systemName: "house.fill").frame(width: 30, height: 34) }
                .buttonStyle(.plain).disabled(!canOpenMenu).opacity(canOpenMenu ? 1 : 0.3)
                .accessibilityLabel("Open game settings")
            StatBlock(title: "ROUND", value: round, prominent: true)
            StatBlock(title: "HITS", value: hitCount)
            Spacer(minLength: 2)
            HStack(spacing: 3) {
                Image(systemName: "circle.hexagongrid.fill").foregroundStyle(.yellow)
                Text("\(coins)").font(.caption.weight(.black).monospacedDigit())
            }
            .accessibilityLabel("Coins \(coins)")
            StatBlock(title: "BEST", value: bestRound)
        }
        .padding(.horizontal, 12).padding(.vertical, 10).background(.black.opacity(0.22))
    }
}

private struct GameSettingsCard: View {
    let session: GameSession
    let onResume: () -> Void
    let onHome: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("遊戲選單").font(.title2.weight(.black))
                    Text("設定會自動保存").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onResume) {
                    Image(systemName: "xmark").font(.headline.weight(.bold)).frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .background(.white.opacity(0.08), in: Circle())
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("粒子效果程度", systemImage: "sparkles")
                    .font(.subheadline.weight(.bold))
                Picker("粒子效果程度", selection: Binding(
                    get: { session.particleEffectLevel },
                    set: { session.setParticleEffectLevel($0) }
                )) {
                    ForEach(ParticleEffectLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }

            Toggle(isOn: Binding(
                get: { session.soundEnabled },
                set: { session.setSoundEnabled($0) }
            )) {
                Label("聲音", systemImage: session.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }

            Toggle(isOn: Binding(
                get: { session.hapticsEnabled },
                set: { session.setHapticsEnabled($0) }
            )) {
                Label("震動", systemImage: "waveform.path")
            }

            Button(action: onHome) {
                Label("回主畫面", systemImage: "house.fill")
                    .font(.headline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent).tint(.cyan)
        }
        .toggleStyle(.switch)
        .tint(.cyan)
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.12)))
        .padding(28)
    }
}

private struct StatBlock: View {
    let title: String
    let value: Int
    var prominent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text("\(value)").font(.system(size: prominent ? 25 : 18, weight: .black, design: .rounded)).monospacedDigit()
        }
    }
}

private struct GameBoardView: View {
    let session: GameSession
    let sceneID: UUID
    let recoveryRequest: Int
    @State private var scene: GameScene

    init(session: GameSession, sceneID: UUID, recoveryRequest: Int) {
        self.session = session
        self.sceneID = sceneID
        self.recoveryRequest = recoveryRequest
        self.scene = GameScene(size: CGSize(width: 390, height: 700), session: session)
        self.scene.scaleMode = .resizeFill
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                SpriteView(scene: scene)
                    .ignoresSafeArea(edges: .bottom)
                    .accessibilityLabel("Brick Rain game board. Drag to aim and release to fire.")
                    .onAppear {
                        scene.size = proxy.size
                    }
                    .onChange(of: proxy.size) { _, newSize in scene.size = newSize }
                    .onChange(of: recoveryRequest) { _, _ in scene.clearBottomThreeRowsAndContinue() }

                HStack(spacing: 10) {
                    Button { scene.toggleFastForward() } label: {
                        VStack(spacing: 0) {
                            Image(systemName: "forward.fill")
                            Text("2×").font(.system(size: 9, weight: .black, design: .rounded))
                        }
                        .font(.subheadline.weight(.bold)).frame(width: 44, height: 44)
                        .foregroundStyle(session.isFastForwarding ? .yellow : .white)
                        .background(.black.opacity(0.65), in: Circle())
                        .overlay(Circle().stroke(session.isFastForwarding ? .yellow.opacity(0.8) : .white.opacity(0.28)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!session.canFastForward)
                    .opacity(session.canFastForward ? 1 : 0.3)
                    .accessibilityLabel(session.isFastForwarding ? "Disable two times speed" : "Enable two times speed")

                    Button { scene.recallAllBalls() } label: {
                        Image(systemName: "arrow.down.to.line.compact")
                            .font(.headline.weight(.bold)).frame(width: 44, height: 44)
                            .background(.black.opacity(0.65), in: Circle()).overlay(Circle().stroke(.white.opacity(0.28)))
                    }
                    .buttonStyle(.plain).disabled(!session.canRecall).opacity(session.canRecall ? 1 : 0.3)
                    .accessibilityLabel("Recall all balls")
                }
                .padding(16)
            }
        }
    }
}

private struct GameOverCard: View {
    let round: Int
    let coins: Int
    let onHome: () -> Void
    let onContinue: () -> Void
    let onRestart: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("GAME OVER").font(.system(size: 34, weight: .black, design: .rounded))
            Text("You reached round \(round)").foregroundStyle(.secondary)
            Button(action: onContinue) {
                HStack(spacing: 7) {
                    Text("CLEAR BOTTOM 3 ROWS & CONTINUE")
                    Text("10")
                    Image(systemName: "circle.hexagongrid.fill").foregroundStyle(.yellow)
                }
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(.cyan)
            .disabled(coins < 10)
            if coins < 10 {
                Text("需要 10 枚金幣才能復活")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Button("START OVER", action: onRestart).buttonStyle(.bordered).controlSize(.large)
            Button("BALL LAB", action: onHome).buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.12))).padding(28)
    }
}

#Preview { ContentView() }
