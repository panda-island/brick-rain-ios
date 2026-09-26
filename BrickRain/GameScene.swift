import SpriteKit

@MainActor
final class GameScene: SKScene, SKPhysicsContactDelegate {
    private enum Category {
        static let ball: UInt32 = 1 << 0
        static let brick: UInt32 = 1 << 1
        static let pickup: UInt32 = 1 << 2
        static let wall: UInt32 = 1 << 3
    }

    private let session: GameSession
    private let columns = 7
    private var ballRadius: CGFloat { session.selectedBallStyle.radius }
    private let ballSpeed: CGFloat = 520
    private let launchInterval = 0.075
    private var cellSize: CGFloat = 0
    private var roundNumber = 1
    private var totalBalls = 1
    private var hitCount = 0
    private var ballsToLaunch = 0
    private var activeBalls = 0
    private var collectedBalls = 0
    private var launchOrigin = CGPoint.zero
    private var firstLandingX: CGFloat?
    private var aimPoint: CGPoint?
    private var isFiring = false
    private var isTransitioning = false
    private var didSetUp = false
    private var launchTimer: Timer?
    private var brickValues: [ObjectIdentifier: Int] = [:]
    private var activatedPowerUps = Set<ObjectIdentifier>()
    private var sceneTime: TimeInterval = 0
    private var lastTrailTime: TimeInterval = 0
    private var lastPopTime: TimeInterval = -1
    private var comboCount = 0
    private var earnedClearBonus = false
    private var lastEffectTimes: [String: TimeInterval] = [:]

    init(size: CGSize, session: GameSession) {
        self.session = session
        super.init(size: size)
        backgroundColor = UIColor(red: 0.055, green: 0.065, blue: 0.09, alpha: 1)
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMove(to view: SKView) {
        guard !didSetUp else { return }
        didSetUp = true
        view.isMultipleTouchEnabled = false
        configureBoard()
        if let progress = ProgressStore.load() {
            restore(progress)
            saveProgress()
        } else {
            addRow()
            saveProgress()
        }
        publish(hasBrickTouchingFloor() ? .gameOver : .ready)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard didSetUp, oldSize.width > 0, oldSize.height > 0 else { return }
        // SpriteKit updates `size` before this callback. Capture nodes against
        // the previous geometry so a height change cannot mix a new top edge
        // with the old cell size and create fractional row spacing.
        let previousCellSize = oldSize.width / CGFloat(columns)
        let previousSpawnY = oldSize.height - 12 - previousCellSize * 1.5
        let progress = makeProgress(
            referenceSize: oldSize,
            referenceCellSize: previousCellSize,
            referenceSpawnY: previousSpawnY
        )
        removeAllChildren()
        brickValues.removeAll()
        configureBoard()
        restore(progress)
        if hasBrickTouchingFloor() { publish(.gameOver) }
    }

    private var floorY: CGFloat { max(28, size.height * 0.045) }
    private var topY: CGFloat { size.height - 12 }
    // Keep one full cell between the top wall and the first row. Balls can use
    // this corridor to travel across the board and bounce back into bricks.
    private var brickSpawnY: CGFloat { topY - cellSize * 1.5 }

    static func snappedRow(positionY: CGFloat, spawnY: CGFloat, cellSize: CGFloat) -> Int {
        max(0, Int(round((spawnY - positionY) / max(cellSize, 1))))
    }

    private func configureBoard() {
        cellSize = size.width / CGFloat(columns)
        launchOrigin = CGPoint(x: size.width / 2, y: floorY + ballRadius + 1)

        addWall(from: CGPoint(x: 0, y: floorY), to: CGPoint(x: 0, y: topY))
        addWall(from: CGPoint(x: size.width, y: floorY), to: CGPoint(x: size.width, y: topY))
        addWall(from: CGPoint(x: 0, y: topY), to: CGPoint(x: size.width, y: topY))

        let launchMarker = makeBallNode()
        launchMarker.name = "launchMarker"
        launchMarker.physicsBody = nil
        launchMarker.position = launchOrigin

        let remainingLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        remainingLabel.name = "remainingBallsLabel"
        remainingLabel.text = "×\(totalBalls)"
        remainingLabel.fontSize = 15
        remainingLabel.fontColor = .white
        remainingLabel.horizontalAlignmentMode = .left
        remainingLabel.verticalAlignmentMode = .center
        remainingLabel.position = CGPoint(x: ballRadius + 7, y: 0)
        remainingLabel.zPosition = 6
        launchMarker.addChild(remainingLabel)
        addChild(launchMarker)
        updateRemainingBallLabel(totalBalls)
    }

    private func addWall(from start: CGPoint, to end: CGPoint) {
        let wall = SKNode()
        wall.name = "wall"
        wall.physicsBody = SKPhysicsBody(edgeFrom: start, to: end)
        wall.physicsBody?.categoryBitMask = Category.wall
        wall.physicsBody?.friction = 0
        wall.physicsBody?.restitution = 1
        addChild(wall)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.phase != .gameOver, !isFiring, !isTransitioning,
              let point = touches.first?.location(in: self), point.y > launchOrigin.y + 35 else { return }
        aimPoint = point
        publish(.aiming)
        drawAimGuide(to: point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.phase != .gameOver, !isFiring, !isTransitioning,
              let point = touches.first?.location(in: self), point.y > launchOrigin.y + 20 else { return }
        aimPoint = point
        drawAimGuide(to: point)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.phase != .gameOver, !isFiring, !isTransitioning, let target = aimPoint else { return }
        childNode(withName: "aimGuide")?.removeFromParent()
        aimPoint = nil
        fire(toward: target)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        aimPoint = nil
        childNode(withName: "aimGuide")?.removeFromParent()
        publish(.ready)
    }

    private func drawAimGuide(to target: CGPoint) {
        childNode(withName: "aimGuide")?.removeFromParent()
        var direction = normalizedDirection(to: target)
        var point = launchOrigin
        let path = CGMutablePath()
        path.move(to: point)

        // Draw the incoming segment plus one reflected segment. The guide stops
        // at the next wall instead of predicting additional rebounds.
        for _ in 0..<2 {
            let topDistance = (topY - point.y) / max(direction.dy, 0.0001)
            let sideDistance: CGFloat
            if direction.dx > 0.0001 {
                sideDistance = (size.width - ballRadius - point.x) / direction.dx
            } else if direction.dx < -0.0001 {
                sideDistance = (ballRadius - point.x) / direction.dx
            } else {
                sideDistance = .greatestFiniteMagnitude
            }

            let distance = min(topDistance, sideDistance)
            guard distance.isFinite, distance > 0 else { break }
            point = CGPoint(
                x: point.x + direction.dx * distance,
                y: point.y + direction.dy * distance
            )
            path.addLine(to: point)
            if topDistance <= sideDistance + 0.01 { break }
            direction.dx *= -1
        }
        let guide = SKShapeNode(path: path)
        guide.name = "aimGuide"
        guide.strokeColor = .white.withAlphaComponent(0.6)
        guide.lineWidth = 2
        guide.glowWidth = 1
        guide.lineCap = .round
        guide.zPosition = 30
        addChild(guide)
    }

    private func normalizedDirection(to target: CGPoint) -> CGVector {
        let dx = target.x - launchOrigin.x
        let dy = max(target.y - launchOrigin.y, 1)
        let length = max(hypot(dx, dy), 1)
        var vector = CGVector(dx: dx / length, dy: dy / length)
        if abs(vector.dy) < 0.22 {
            vector.dy = 0.22
            let normalized = max(hypot(vector.dx, vector.dy), 1)
            vector.dx /= normalized
            vector.dy /= normalized
        }
        return vector
    }

    private func fire(toward target: CGPoint) {
        isFiring = true
        ballsToLaunch = totalBalls
        updateRemainingBallLabel(totalBalls)
        activeBalls = 0
        collectedBalls = 0
        firstLandingX = nil
        comboCount = 0
        earnedClearBonus = false
        let direction = normalizedDirection(to: target)
        publish(.firing, canRecall: true)
        launchOne(direction: direction)

        launchTimer?.invalidate()
        launchTimer = Timer.scheduledTimer(withTimeInterval: launchInterval, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                if self.ballsToLaunch > 0 {
                    self.launchOne(direction: direction)
                } else {
                    timer.invalidate()
                }
            }
        }
    }

    private func launchOne(direction: CGVector) {
        guard ballsToLaunch > 0 else { return }
        ballsToLaunch -= 1
        updateRemainingBallLabel(ballsToLaunch)
        activeBalls += 1

        let ball = makeBallNode()
        ball.name = "ball"
        ball.position = launchOrigin
        ball.zPosition = 5
        ball.physicsBody?.isDynamic = true
        ball.physicsBody?.affectedByGravity = false
        ball.physicsBody?.allowsRotation = [.triangle, .hexagon, .pixel, .star].contains(session.selectedBallStyle)
        ball.physicsBody?.friction = 0
        ball.physicsBody?.linearDamping = 0
        ball.physicsBody?.restitution = 1
        ball.physicsBody?.usesPreciseCollisionDetection = true
        ball.physicsBody?.categoryBitMask = Category.ball
        ball.physicsBody?.collisionBitMask = Category.brick | Category.wall
        ball.physicsBody?.contactTestBitMask = Category.brick | Category.pickup
        ball.physicsBody?.velocity = CGVector(dx: direction.dx * ballSpeed, dy: direction.dy * ballSpeed)
        ball.userData?["lastDX"] = direction.dx
        ball.userData?["lastDY"] = direction.dy
        if session.selectedBallStyle == .triangle { ball.physicsBody?.angularVelocity = 3.8 }
        if session.selectedBallStyle == .star { ball.physicsBody?.angularVelocity = 2.8 }
        addChild(ball)
    }

    private func makeBallNode() -> SKShapeNode {
        let ball: SKShapeNode
        switch session.selectedBallStyle {
        case .classic:
            ball = SKShapeNode(circleOfRadius: ballRadius)
            ball.fillColor = .white
            ball.strokeColor = .cyan
            ball.lineWidth = 1.2
            ball.physicsBody = SKPhysicsBody(circleOfRadius: ballRadius)
            let core = SKShapeNode(circleOfRadius: ballRadius * 0.34)
            core.fillColor = .cyan
            core.strokeColor = .clear
            ball.addChild(core)
            ball.userData = NSMutableDictionary(object: UIColor.cyan, forKey: "trailColor" as NSString)
        case .mini:
            ball = SKShapeNode(circleOfRadius: ballRadius)
            ball.fillColor = .systemYellow
            ball.strokeColor = .white
            ball.lineWidth = 0.8
            ball.glowWidth = 2
            ball.physicsBody = SKPhysicsBody(circleOfRadius: ballRadius)
            ball.userData = NSMutableDictionary(object: UIColor.systemYellow, forKey: "trailColor" as NSString)
        case .triangle:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: ballRadius))
            path.addLine(to: CGPoint(x: -ballRadius * 0.9, y: -ballRadius * 0.72))
            path.addLine(to: CGPoint(x: ballRadius * 0.9, y: -ballRadius * 0.72))
            path.closeSubpath()
            ball = SKShapeNode(path: path)
            ball.fillColor = .systemPink
            ball.strokeColor = .white
            ball.lineWidth = 1
            ball.glowWidth = 2
            ball.physicsBody = SKPhysicsBody(polygonFrom: path)
            let inset = SKShapeNode(path: path)
            inset.setScale(0.42)
            inset.fillColor = .clear
            inset.strokeColor = UIColor.white.withAlphaComponent(0.75)
            inset.lineWidth = 1
            ball.addChild(inset)
            ball.userData = NSMutableDictionary(object: UIColor.systemPink, forKey: "trailColor" as NSString)
        case .comet:
            ball = SKShapeNode(circleOfRadius: ballRadius)
            ball.fillColor = .systemOrange
            ball.strokeColor = .systemYellow
            ball.lineWidth = 1.2
            ball.glowWidth = 3
            ball.physicsBody = SKPhysicsBody(circleOfRadius: ballRadius)
            let flame = SKShapeNode(circleOfRadius: ballRadius * 0.36)
            flame.fillColor = .systemYellow
            flame.strokeColor = .clear
            ball.addChild(flame)
            ball.userData = NSMutableDictionary(object: UIColor.systemOrange, forKey: "trailColor" as NSString)
        case .hexagon:
            let path = regularPolygonPath(sides: 6, radius: ballRadius, rotation: .pi / 6)
            ball = SKShapeNode(path: path)
            ball.fillColor = .systemMint
            ball.strokeColor = .white
            ball.lineWidth = 1
            ball.glowWidth = 2
            ball.physicsBody = SKPhysicsBody(polygonFrom: path)
            let inset = SKShapeNode(path: path)
            inset.setScale(0.48)
            inset.fillColor = .clear
            inset.strokeColor = UIColor.white.withAlphaComponent(0.8)
            inset.lineWidth = 1
            ball.addChild(inset)
            ball.userData = NSMutableDictionary(object: UIColor.systemMint, forKey: "trailColor" as NSString)
        case .pixel:
            let side = ballRadius * 1.65
            ball = SKShapeNode(rectOf: CGSize(width: side, height: side), cornerRadius: 0.8)
            ball.fillColor = .systemGreen
            ball.strokeColor = .white
            ball.lineWidth = 1
            ball.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: side, height: side))
            let core = SKShapeNode(rectOf: CGSize(width: side * 0.34, height: side * 0.34))
            core.fillColor = .white
            core.strokeColor = .clear
            ball.addChild(core)
            ball.userData = NSMutableDictionary(object: UIColor.systemGreen, forKey: "trailColor" as NSString)
        case .giant:
            ball = SKShapeNode(circleOfRadius: ballRadius)
            ball.fillColor = UIColor(red: 0.12, green: 0.32, blue: 0.95, alpha: 1)
            ball.strokeColor = .white
            ball.lineWidth = 1.5
            ball.glowWidth = 4
            ball.physicsBody = SKPhysicsBody(circleOfRadius: ballRadius)
            let ring = SKShapeNode(circleOfRadius: ballRadius * 0.55)
            ring.fillColor = .clear
            ring.strokeColor = UIColor.white.withAlphaComponent(0.9)
            ring.lineWidth = 1.2
            ball.addChild(ring)
            ball.userData = NSMutableDictionary(object: UIColor.systemBlue, forKey: "trailColor" as NSString)
        case .phantom:
            ball = SKShapeNode(circleOfRadius: ballRadius)
            ball.fillColor = UIColor.systemPurple.withAlphaComponent(0.55)
            ball.strokeColor = UIColor.white.withAlphaComponent(0.85)
            ball.lineWidth = 1
            ball.glowWidth = 5
            ball.physicsBody = SKPhysicsBody(circleOfRadius: ballRadius)
            let eye = SKShapeNode(circleOfRadius: ballRadius * 0.25)
            eye.fillColor = .white
            eye.strokeColor = .clear
            ball.addChild(eye)
            ball.userData = NSMutableDictionary(object: UIColor.systemPurple, forKey: "trailColor" as NSString)
        case .rainbow:
            ball = SKShapeNode(circleOfRadius: ballRadius)
            ball.fillColor = .cyan
            ball.strokeColor = .white
            ball.lineWidth = 1.2
            ball.glowWidth = 3
            ball.physicsBody = SKPhysicsBody(circleOfRadius: ballRadius)
            for (index, color) in [UIColor.systemRed, .systemYellow, .systemGreen, .systemBlue].enumerated() {
                let dot = SKShapeNode(circleOfRadius: ballRadius * 0.18)
                let angle = CGFloat(index) * .pi / 2
                dot.position = CGPoint(x: cos(angle) * ballRadius * 0.42, y: sin(angle) * ballRadius * 0.42)
                dot.fillColor = color
                dot.strokeColor = .clear
                ball.addChild(dot)
            }
            ball.userData = NSMutableDictionary(object: UIColor.cyan, forKey: "trailColor" as NSString)
        case .star:
            let path = starPath(points: 5, outerRadius: ballRadius, innerRadius: ballRadius * 0.46)
            ball = SKShapeNode(path: path)
            ball.fillColor = .systemYellow
            ball.strokeColor = .white
            ball.lineWidth = 1
            ball.glowWidth = 4
            ball.physicsBody = SKPhysicsBody(circleOfRadius: ballRadius * 0.78)
            ball.userData = NSMutableDictionary(object: UIColor.systemYellow, forKey: "trailColor" as NSString)
        }
        return ball
    }

    private func regularPolygonPath(sides: Int, radius: CGFloat, rotation: CGFloat = 0) -> CGPath {
        let path = CGMutablePath()
        for index in 0..<sides {
            let angle = rotation + CGFloat(index) * 2 * .pi / CGFloat(sides)
            let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private func starPath(points: Int, outerRadius: CGFloat, innerRadius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for index in 0..<(points * 2) {
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            let angle = -.pi / 2 + CGFloat(index) * .pi / CGFloat(points)
            let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    override func update(_ currentTime: TimeInterval) {
        sceneTime = currentTime
        guard isFiring else { return }
        let shouldAddTrail = currentTime - lastTrailTime >= 0.055
        if shouldAddTrail { lastTrailTime = currentTime }
        enumerateChildNodes(withName: "ball") { [weak self] node, _ in
            guard let self else { return }
            if shouldAddTrail { self.addTrail(at: node.position, color: node.userData?["trailColor"] as? UIColor ?? .white) }
            if node.position.y <= self.floorY + self.ballRadius + 3,
               (node.physicsBody?.velocity.dy ?? 0) < 0 {
                self.land(ball: node)
            }
        }
    }

    override func didSimulatePhysics() {
        guard isFiring else { return }
        enumerateChildNodes(withName: "ball") { [weak self] node, _ in
            guard let self, let body = node.physicsBody else { return }
            let speed = hypot(body.velocity.dx, body.velocity.dy)
            if speed > 20 {
                let dx = body.velocity.dx / speed
                let dy = body.velocity.dy / speed
                body.velocity = CGVector(dx: dx * self.ballSpeed, dy: dy * self.ballSpeed)
                node.userData?["lastDX"] = dx
                node.userData?["lastDY"] = dy
            } else {
                let dx = CGFloat((node.userData?["lastDX"] as? NSNumber)?.doubleValue ?? 0)
                let dy = CGFloat((node.userData?["lastDY"] as? NSNumber)?.doubleValue ?? 1)
                body.velocity = CGVector(dx: dx * self.ballSpeed, dy: dy * self.ballSpeed)
            }
        }
    }

    private func land(ball: SKNode) {
        guard ball.parent != nil else { return }
        if firstLandingX == nil {
            firstLandingX = min(max(ball.position.x, ballRadius + 2), size.width - ballRadius - 2)
        }
        ball.removeFromParent()
        activeBalls -= 1
        if activeBalls == 0 && ballsToLaunch == 0 {
            finishTurn()
        }
    }

    func recallAllBalls() {
        guard isFiring else { return }
        launchTimer?.invalidate()
        launchTimer = nil
        ballsToLaunch = 0
        updateRemainingBallLabel(0)
        if firstLandingX == nil {
            firstLandingX = launchOrigin.x
        }
        enumerateChildNodes(withName: "ball") { node, _ in node.removeFromParent() }
        activeBalls = 0
        finishTurn()
    }

    func didBegin(_ contact: SKPhysicsContact) {
        let nodes = [contact.bodyA.node, contact.bodyB.node].compactMap { $0 }
        guard let ball = nodes.first(where: { $0.name == "ball" }) else { return }
        if let brick = nodes.first(where: { $0.name == "brick" }) {
            showBallImpact(at: contact.contactPoint)
            hit(brick: brick)
        } else if let pickup = nodes.first(where: { $0.name == "pickup" }) {
            collect(pickup: pickup, ball: ball)
        }
    }

    private func hit(brick: SKNode) {
        let key = ObjectIdentifier(brick)
        guard let value = brickValues[key] else { return }
        hitCount += 1
        session.hitCount = hitCount
        if session.soundEnabled, sceneTime - lastPopTime > 0.028 {
            lastPopTime = sceneTime
            run(.playSoundFileNamed("pop.wav", waitForCompletion: false))
        }
        emitBrickParticles(at: brick.position, color: (brick as? SKShapeNode)?.fillColor ?? .white, count: value <= 1 ? 9 : 4)
        if value <= 1 {
            brickValues[key] = nil
            comboCount += 1
            showCombo()
            playEffect("break.wav")
            brick.run(.sequence([.scale(to: 1.18, duration: 0.04), .fadeOut(withDuration: 0.08), .removeFromParent()]))
            if brickValues.isEmpty, !earnedClearBonus {
                earnedClearBonus = true
                showBoardClearBonus()
            }
            if comboCount.isMultiple(of: 10) {
                shake(intensity: min(5, CGFloat(comboCount) / 8))
                if session.hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            }
        } else {
            brickValues[key] = value - 1
            updateBrick(brick, value: value - 1)
            if let label = brick.childNode(withName: "value") {
                label.removeAction(forKey: "numberPulse")
                label.run(.sequence([.scale(to: 1.35, duration: 0.035), .scale(to: 1, duration: 0.08)]), withKey: "numberPulse")
            }
        }
    }

    private func collect(pickup: SKNode, ball: SKNode) {
        guard pickup.parent != nil else { return }
        let kind = powerUpKind(for: pickup)
        switch kind {
        case .extraBall:
            pickup.removeFromParent()
            collectedBalls += 1
            playEffect("pickup.wav")
        case .spring:
            markActivated(pickup)
            playEffect("spring.wav")
            if let body = ball.physicsBody {
                let speed = max(hypot(body.velocity.dx, body.velocity.dy), 1)
                let angle = CGFloat.random(in: 28...152) * .pi / 180
                body.velocity = CGVector(
                    dx: cos(angle) * speed,
                    dy: sin(angle) * speed
                )
                if ball.userData == nil { ball.userData = NSMutableDictionary() }
                ball.userData?["trailColor"] = color(for: kind)
            }
        case .laserVertical, .laserHorizontal, .laserCross:
            markActivated(pickup)
            playEffect("laser.wav")
            if session.hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            shake(intensity: 4)
            fireLaser(kind, from: pickup.position)
        case .coin:
            pickup.removeFromParent()
            session.collectCoin()
            playEffect("pickup.wav")
            showCoinCollected(at: ball.position)
            if session.hapticsEnabled { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
        case .brick, .triangleBrick:
            break
        }
        let pulse = SKShapeNode(circleOfRadius: 13)
        pulse.position = ball.position
        pulse.strokeColor = color(for: kind)
        pulse.lineWidth = 2
        pulse.run(.sequence([.group([.scale(to: 2.2, duration: 0.2), .fadeOut(withDuration: 0.2)]), .removeFromParent()]))
        addChild(pulse)
    }

    private func markActivated(_ pickup: SKNode) {
        activatedPowerUps.insert(ObjectIdentifier(pickup))
        pickup.alpha = 0.55
    }

    private func playEffect(_ name: String) {
        guard session.soundEnabled else { return }
        guard sceneTime - (lastEffectTimes[name] ?? -1) > 0.06 else { return }
        lastEffectTimes[name] = sceneTime
        run(.playSoundFileNamed(name, waitForCompletion: false))
    }

    private func addTrail(at position: CGPoint, color: UIColor) {
        let trail: SKShapeNode
        if session.selectedBallStyle == .triangle || session.selectedBallStyle == .star {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 3))
            path.addLine(to: CGPoint(x: -2.6, y: -2))
            path.addLine(to: CGPoint(x: 2.6, y: -2))
            path.closeSubpath()
            trail = SKShapeNode(path: path)
        } else if session.selectedBallStyle == .pixel {
            trail = SKShapeNode(rectOf: CGSize(width: 3.8, height: 3.8))
        } else {
            let radius: CGFloat = session.selectedBallStyle == .mini ? 1.25 : session.selectedBallStyle == .giant ? 3.4 : 2.3
            trail = SKShapeNode(circleOfRadius: radius)
        }
        trail.position = position
        let trailColor = session.selectedBallStyle == .rainbow
            ? UIColor(hue: CGFloat.random(in: 0...1), saturation: 0.9, brightness: 1, alpha: 0.8)
            : color.withAlphaComponent(session.selectedBallStyle == .phantom ? 0.38 : 0.72)
        trail.fillColor = trailColor
        trail.strokeColor = .clear
        trail.zPosition = 3
        trail.run(.sequence([
            .group([.scale(to: 0.15, duration: 0.18), .fadeOut(withDuration: 0.18)]),
            .removeFromParent()
        ]))
        addChild(trail)
    }

    private func showBallImpact(at position: CGPoint) {
        let color: UIColor
        let count: Int
        switch session.selectedBallStyle {
        case .classic:
            color = .cyan
            count = 1
        case .mini:
            color = .systemYellow
            count = 5
        case .triangle:
            color = .systemPink
            count = 3
        case .comet:
            color = .systemOrange
            count = 8
        case .hexagon:
            color = .systemMint
            count = 6
        case .pixel:
            color = .systemGreen
            count = 4
        case .giant:
            color = .systemBlue
            count = 12
            addImpactRing(at: position, color: color, radius: 9, scale: 4.2)
            shake(intensity: 2.2)
        case .phantom:
            color = .systemPurple
            count = 2
            addImpactRing(at: position, color: color.withAlphaComponent(0.7), radius: 7, scale: 3.2)
            addImpactRing(at: position, color: .white.withAlphaComponent(0.55), radius: 4, scale: 4.4)
        case .rainbow:
            color = UIColor(hue: CGFloat.random(in: 0...1), saturation: 0.9, brightness: 1, alpha: 1)
            count = 10
        case .star:
            color = .systemYellow
            count = 5
            addImpactRing(at: position, color: .white, radius: 5, scale: 2.8)
        }

        for index in 0..<count {
            let spark: SKShapeNode
            if session.selectedBallStyle == .classic {
                spark = SKShapeNode(circleOfRadius: 4)
                spark.fillColor = .clear
                spark.strokeColor = color
            } else {
                spark = SKShapeNode(rectOf: CGSize(width: session.selectedBallStyle == .mini ? 2 : 3, height: 9))
                spark.fillColor = color
                spark.strokeColor = .clear
                spark.zRotation = CGFloat(index) * (2 * .pi / CGFloat(count))
            }
            spark.position = position
            spark.zPosition = 24
            let angle = CGFloat(index) * (2 * .pi / CGFloat(count)) + CGFloat.random(in: -0.25...0.25)
            spark.run(.sequence([
                .group([
                    .moveBy(x: cos(angle) * 17, y: sin(angle) * 17, duration: 0.12),
                    .scale(to: session.selectedBallStyle == .classic ? 2.4 : 0.2, duration: 0.12),
                    .fadeOut(withDuration: 0.12)
                ]),
                .removeFromParent()
            ]))
            addChild(spark)
        }
    }

    private func addImpactRing(at position: CGPoint, color: UIColor, radius: CGFloat, scale: CGFloat) {
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.position = position
        ring.strokeColor = color
        ring.fillColor = .clear
        ring.lineWidth = 2
        ring.glowWidth = 4
        ring.zPosition = 23
        ring.run(.sequence([
            .group([.scale(to: scale, duration: 0.18), .fadeOut(withDuration: 0.18)]),
            .removeFromParent()
        ]))
        addChild(ring)
    }

    private func showCoinCollected(at position: CGPoint) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = "+1 COIN"
        label.fontSize = 15
        label.fontColor = .systemYellow
        label.position = position
        label.zPosition = 70
        label.run(.sequence([
            .group([.moveBy(x: 0, y: 34, duration: 0.45), .fadeOut(withDuration: 0.45)]),
            .removeFromParent()
        ]))
        addChild(label)
    }

    private func emitBrickParticles(at position: CGPoint, color: UIColor, count: Int) {
        for _ in 0..<count {
            let shard = SKShapeNode(rectOf: CGSize(width: 3.5, height: 3.5))
            shard.position = position
            shard.fillColor = color
            shard.strokeColor = .clear
            shard.zPosition = 18
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 13...31)
            shard.run(.sequence([
                .group([
                    .moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: 0.2),
                    .rotate(byAngle: CGFloat.random(in: -2...2), duration: 0.2),
                    .fadeOut(withDuration: 0.2),
                    .scale(to: 0.25, duration: 0.2)
                ]),
                .removeFromParent()
            ]))
            addChild(shard)
        }
    }

    private func showCombo() {
        guard comboCount >= 1 else { return }
        let label: SKLabelNode
        if let existing = childNode(withName: "comboLabel") as? SKLabelNode {
            label = existing
        } else {
            label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            label.name = "comboLabel"
            label.position = CGPoint(x: size.width / 2, y: topY - cellSize * 0.48)
            label.zPosition = 60
            addChild(label)
        }
        label.text = "COMBO ×\(comboCount)"
        label.fontSize = min(30, 17 + CGFloat(comboCount) * 0.32)
        label.fontColor = UIColor(hue: CGFloat((comboCount * 7) % 100) / 100, saturation: 0.72, brightness: 1, alpha: 1)
        label.alpha = 1
        label.setScale(0.82)
        label.removeAllActions()
        label.run(.sequence([
            .scale(to: 1.12, duration: 0.06),
            .scale(to: 1, duration: 0.08),
            .wait(forDuration: 0.55),
            .fadeOut(withDuration: 0.18)
        ]))
    }

    private func shake(intensity: CGFloat) {
        removeAction(forKey: "screenShake")
        run(.sequence([
            .moveBy(x: -intensity, y: intensity * 0.45, duration: 0.025),
            .moveBy(x: intensity * 1.7, y: -intensity * 0.8, duration: 0.035),
            .moveBy(x: -intensity * 0.7, y: intensity * 0.35, duration: 0.035)
        ]), withKey: "screenShake")
    }

    private func showBoardClearBonus() {
        childNode(withName: "boardClearBonus")?.removeFromParent()
        let banner = SKNode()
        banner.name = "boardClearBonus"
        banner.position = CGPoint(x: size.width / 2, y: size.height * 0.53)
        banner.zPosition = 90
        banner.alpha = 0
        banner.setScale(0.55)

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "BOARD CLEAR!"
        title.fontSize = 34
        title.fontColor = .cyan
        title.verticalAlignmentMode = .center
        banner.addChild(title)

        let reward = SKLabelNode(fontNamed: "AvenirNext-Bold")
        reward.text = "EXTRA +1 NEXT ROUND"
        reward.fontSize = 16
        reward.fontColor = .white
        reward.position.y = -34
        banner.addChild(reward)

        let ring = SKShapeNode(circleOfRadius: 34)
        ring.strokeColor = .cyan
        ring.lineWidth = 3
        ring.glowWidth = 8
        ring.zPosition = -1
        ring.run(.group([.scale(to: 3.2, duration: 0.55), .fadeOut(withDuration: 0.55)]))
        banner.addChild(ring)

        banner.run(.sequence([
            .group([.fadeIn(withDuration: 0.12), .scale(to: 1.12, duration: 0.18)]),
            .scale(to: 1, duration: 0.08),
            .wait(forDuration: 0.72),
            .group([.fadeOut(withDuration: 0.2), .moveBy(x: 0, y: 18, duration: 0.2)]),
            .removeFromParent()
        ]))
        addChild(banner)
        emitBrickParticles(at: banner.position, color: .cyan, count: 18)
        shake(intensity: 6)
        playEffect("pickup.wav")
        if session.hapticsEnabled { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    private func finishTurn() {
        isFiring = false
        isTransitioning = true
        totalBalls += collectedBalls
        roundNumber += 1
        hitCount = 0
        launchOrigin.x = firstLandingX ?? launchOrigin.x
        childNode(withName: "launchMarker")?.position = launchOrigin
        updateRemainingBallLabel(totalBalls)

        var reachedBottom = false
        enumerateChildNodes(withName: "brick") { [weak self] node, _ in
            guard let self else { return }
            guard self.brickValues[ObjectIdentifier(node)] != nil else { return }
            let destinationY = node.position.y - self.cellSize
            node.run(.moveTo(y: destinationY, duration: 0.24))
            if self.brickTouchesFloor(centerY: destinationY) {
                reachedBottom = true
            }
        }
        enumerateChildNodes(withName: "pickup") { [weak self] node, _ in
            guard let self else { return }
            if self.activatedPowerUps.contains(ObjectIdentifier(node)) {
                node.run(.sequence([.fadeOut(withDuration: 0.12), .removeFromParent()]))
                return
            }
            let destinationY = node.position.y - self.cellSize
            node.run(.moveTo(y: destinationY, duration: 0.24))
            if destinationY < self.floorY { node.run(.sequence([.wait(forDuration: 0.24), .removeFromParent()])) }
        }
        activatedPowerUps.removeAll()
        publish(.firing)

        let didReachBottom = reachedBottom
        run(.sequence([.wait(forDuration: 0.26), .run { [weak self] in
            Task { @MainActor in self?.completeTurn(reachedBottom: didReachBottom) }
        }]))
    }

    private func completeTurn(reachedBottom: Bool) {
        isTransitioning = false
        if reachedBottom {
            saveProgress()
            publish(.gameOver)
        } else {
            let extraBallCount = earnedClearBonus ? 2 : 1
            earnedClearBonus = false
            addRow(extraBallCount: extraBallCount)
            saveProgress()
            publish(.ready)
        }
    }

    static func brickTouchesFloor(centerY: CGFloat, cellSize: CGFloat, floorY: CGFloat) -> Bool {
        centerY - cellSize * 0.445 <= floorY + 0.5
    }

    private func brickTouchesFloor(centerY: CGFloat) -> Bool {
        Self.brickTouchesFloor(centerY: centerY, cellSize: cellSize, floorY: floorY)
    }

    private func hasBrickTouchingFloor() -> Bool {
        children.contains { node in
            node.name == "brick" && brickValues[ObjectIdentifier(node)] != nil && brickTouchesFloor(centerY: node.position.y)
        }
    }

    private func updateRemainingBallLabel(_ count: Int) {
        guard let label = childNode(withName: "//remainingBallsLabel") as? SKLabelNode else { return }
        label.text = "×\(max(0, count))"
        label.isHidden = count <= 0
        let placeOnLeft = launchOrigin.x > size.width - 64
        label.horizontalAlignmentMode = placeOnLeft ? .right : .left
        label.position.x = placeOnLeft ? -(ballRadius + 7) : ballRadius + 7
    }

    func clearBottomThreeRowsAndContinue() {
        guard !isFiring, session.phase == .gameOver else { return }
        let bricks = children.filter { $0.name == "brick" }
        let bottomRows = Set(
            bricks.map { Int(round(($0.position.y - floorY) / max(cellSize, 1))) }
                .sorted()
                .reduce(into: [Int]()) { rows, row in
                    if rows.last != row { rows.append(row) }
                }
                .prefix(3)
        )

        for brick in bricks {
            let row = Int(round((brick.position.y - floorY) / max(cellSize, 1)))
            guard bottomRows.contains(row) else { continue }
            brickValues[ObjectIdentifier(brick)] = nil
            brick.removeFromParent()
        }
        addRow()
        saveProgress()
        publish(.ready)
    }

    private func addRow(extraBallCount: Int = 1) {
        if roundNumber.isMultiple(of: 10) { showRoundBanner() }
        var occupied = Set<Int>()
        let brickCount = Int.random(in: 2...5)
        for _ in 0..<brickCount {
            var column = Int.random(in: 0..<columns)
            while occupied.contains(column) { column = Int.random(in: 0..<columns) }
            occupied.insert(column)
            let isDoubleStrength = roundNumber.isMultiple(of: 10) && Int.random(in: 0..<100) < 25
            let value = isDoubleStrength ? roundNumber * 2 : roundNumber
            let shape: GameProgress.BoardObject.Kind = Int.random(in: 0..<100) < 14 ? .triangleBrick : .brick
            addBrick(
                column: column,
                value: value,
                kind: shape,
                orientation: shape == .triangleBrick ? Int.random(in: 0..<4) : nil
            )
        }

        for _ in 0..<min(extraBallCount, columns - occupied.count) {
            var column = Int.random(in: 0..<columns)
            while occupied.contains(column) { column = Int.random(in: 0..<columns) }
            occupied.insert(column)
            addPowerUp(column: column, kind: .extraBall)
        }

        if occupied.count < columns, Int.random(in: 0..<100) < 45 {
            var column = Int.random(in: 0..<columns)
            while occupied.contains(column) { column = Int.random(in: 0..<columns) }
            occupied.insert(column)
            addPowerUp(column: column, kind: .coin)
        }

        if occupied.count < columns, Int.random(in: 0..<100) < 58 {
            var column = Int.random(in: 0..<columns)
            while occupied.contains(column) { column = Int.random(in: 0..<columns) }
            addPowerUp(column: column, kind: randomBonusPowerUp())
        }
    }

    private func addBrick(
        column: Int,
        value: Int,
        kind: GameProgress.BoardObject.Kind = .brick,
        orientation: Int? = nil,
        position: CGPoint? = nil
    ) {
        let side = cellSize * 0.89
        let brick: SKShapeNode
        if kind == .triangleBrick {
            let corner = orientation ?? Int.random(in: 0..<4)
            let path = CGMutablePath()
            let half = side / 2
            switch corner {
            case 0: // upper-left
                path.move(to: CGPoint(x: -half, y: half))
                path.addLine(to: CGPoint(x: half, y: half))
                path.addLine(to: CGPoint(x: -half, y: -half))
            case 1: // upper-right
                path.move(to: CGPoint(x: -half, y: half))
                path.addLine(to: CGPoint(x: half, y: half))
                path.addLine(to: CGPoint(x: half, y: -half))
            case 2: // lower-right
                path.move(to: CGPoint(x: half, y: half))
                path.addLine(to: CGPoint(x: half, y: -half))
                path.addLine(to: CGPoint(x: -half, y: -half))
            default: // lower-left
                path.move(to: CGPoint(x: -half, y: half))
                path.addLine(to: CGPoint(x: half, y: -half))
                path.addLine(to: CGPoint(x: -half, y: -half))
            }
            path.closeSubpath()
            brick = SKShapeNode(path: path)
            brick.physicsBody = SKPhysicsBody(polygonFrom: path)
            brick.userData = NSMutableDictionary(object: corner, forKey: "orientation" as NSString)
        } else {
            brick = SKShapeNode(rectOf: CGSize(width: side, height: side))
            brick.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: side, height: side))
        }
        brick.name = "brick"
        let destination = position ?? CGPoint(x: (CGFloat(column) + 0.5) * cellSize, y: brickSpawnY)
        brick.position = destination
        brick.lineWidth = 2
        if brick.userData == nil { brick.userData = NSMutableDictionary() }
        brick.userData?["shape"] = kind.rawValue
        brick.physicsBody?.isDynamic = false
        brick.physicsBody?.friction = 0
        brick.physicsBody?.restitution = 1
        brick.physicsBody?.categoryBitMask = Category.brick
        brick.physicsBody?.collisionBitMask = Category.ball
        brick.physicsBody?.contactTestBitMask = Category.ball
        brickValues[ObjectIdentifier(brick)] = value

        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.name = "value"
        label.verticalAlignmentMode = .center
        label.fontSize = min(22, cellSize * 0.34)
        if kind == .triangleBrick {
            let inset = side / 6
            switch orientation ?? (brick.userData?["orientation"] as? Int ?? 0) {
            case 0: label.position = CGPoint(x: -inset, y: inset)
            case 1: label.position = CGPoint(x: inset, y: inset)
            case 2: label.position = CGPoint(x: inset, y: -inset)
            default: label.position = CGPoint(x: -inset, y: -inset)
            }
        }
        brick.addChild(label)
        updateBrick(brick, value: value)
        addChild(brick)
        if position == nil {
            brick.alpha = 0
            brick.position.y += cellSize * 0.4
            brick.run(.group([.fadeIn(withDuration: 0.2), .moveTo(y: destination.y, duration: 0.24)]))
        }
    }

    private func updateBrick(_ brick: SKNode, value: Int) {
        guard let shape = brick as? SKShapeNode,
              let label = shape.childNode(withName: "value") as? SKLabelNode else { return }
        let hue = CGFloat((value * 19) % 360) / 360
        let color = UIColor(hue: hue, saturation: 0.72, brightness: 0.98, alpha: 1)
        shape.fillColor = color
        shape.strokeColor = color.withAlphaComponent(0.4)
        label.text = "\(value)"
        label.fontColor = .white
    }

    private func randomBonusPowerUp() -> GameProgress.BoardObject.Kind {
        let roll = Int.random(in: 0..<100)
        switch roll {
        case 0..<34: return .spring
        case 34..<57: return .laserVertical
        case 57..<80: return .laserHorizontal
        default: return .laserCross
        }
    }

    private func addPowerUp(
        column: Int,
        kind: GameProgress.BoardObject.Kind,
        position: CGPoint? = nil
    ) {
        let pickup = SKShapeNode(circleOfRadius: min(14, cellSize * 0.22))
        pickup.name = "pickup"
        let destination = position ?? CGPoint(x: (CGFloat(column) + 0.5) * cellSize, y: brickSpawnY)
        pickup.position = destination
        pickup.fillColor = .clear
        pickup.strokeColor = color(for: kind)
        pickup.lineWidth = 2
        pickup.userData = NSMutableDictionary(object: kind.rawValue, forKey: "kind" as NSString)
        pickup.physicsBody = SKPhysicsBody(circleOfRadius: min(14, cellSize * 0.22))
        pickup.physicsBody?.isDynamic = false
        pickup.physicsBody?.categoryBitMask = Category.pickup
        pickup.physicsBody?.collisionBitMask = 0
        pickup.physicsBody?.contactTestBitMask = Category.ball

        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = symbol(for: kind)
        label.fontSize = kind == .laserVertical || kind == .laserHorizontal ? 18 : 12
        label.fontColor = color(for: kind)
        label.verticalAlignmentMode = .center
        pickup.addChild(label)
        addChild(pickup)
        if position == nil {
            pickup.alpha = 0
            pickup.position.y += cellSize * 0.4
            pickup.run(.group([.fadeIn(withDuration: 0.2), .moveTo(y: destination.y, duration: 0.24)]))
        }
    }

    private func showRoundBanner() {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = "ROUND \(roundNumber)"
        label.fontSize = 36
        label.fontColor = .systemYellow
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.58)
        label.zPosition = 80
        label.alpha = 0
        label.setScale(0.55)
        label.run(.sequence([
            .group([.fadeIn(withDuration: 0.12), .scale(to: 1.12, duration: 0.18)]),
            .scale(to: 1, duration: 0.08),
            .wait(forDuration: 0.55),
            .group([.fadeOut(withDuration: 0.2), .moveBy(x: 0, y: 18, duration: 0.2)]),
            .removeFromParent()
        ]))
        addChild(label)
        if session.hapticsEnabled { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    private func powerUpKind(for node: SKNode) -> GameProgress.BoardObject.Kind {
        guard let raw = node.userData?["kind"] as? String,
              let kind = GameProgress.BoardObject.Kind(rawValue: raw) else { return .extraBall }
        return kind
    }

    private func color(for kind: GameProgress.BoardObject.Kind) -> UIColor {
        switch kind {
        case .extraBall: return .cyan
        case .spring: return UIColor(red: 0.72, green: 0.35, blue: 1, alpha: 1)
        case .laserVertical: return .systemYellow
        case .laserHorizontal: return .systemOrange
        case .laserCross: return .systemPink
        case .coin: return .systemYellow
        case .brick, .triangleBrick: return .white
        }
    }

    private func symbol(for kind: GameProgress.BoardObject.Kind) -> String {
        switch kind {
        case .extraBall: return "+1"
        case .spring: return "↟"
        case .laserVertical: return "┃"
        case .laserHorizontal: return "━"
        case .laserCross: return "✣"
        case .coin: return "●"
        case .brick, .triangleBrick: return ""
        }
    }

    private func fireLaser(_ kind: GameProgress.BoardObject.Kind, from origin: CGPoint) {
        let vertical = kind == .laserVertical || kind == .laserCross
        let horizontal = kind == .laserHorizontal || kind == .laserCross
        let targets = children.filter { node in
            guard node.name == "brick" else { return false }
            let sameColumn = abs(node.position.x - origin.x) < cellSize * 0.48
            let sameRow = abs(node.position.y - origin.y) < cellSize * 0.48
            return (vertical && sameColumn) || (horizontal && sameRow)
        }
        for target in targets {
            flashBrick(target)
            hit(brick: target)
        }

        if vertical {
            addLaserBeam(from: CGPoint(x: origin.x, y: floorY), to: CGPoint(x: origin.x, y: topY), color: color(for: kind))
        }
        if horizontal {
            addLaserBeam(from: CGPoint(x: 0, y: origin.y), to: CGPoint(x: size.width, y: origin.y), color: color(for: kind))
        }
    }

    private func addLaserBeam(from start: CGPoint, to end: CGPoint, color: UIColor) {
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        let charge = SKShapeNode(path: path)
        charge.strokeColor = .white.withAlphaComponent(0.75)
        charge.lineWidth = 1
        charge.glowWidth = 2
        charge.zPosition = 19
        charge.run(.sequence([.wait(forDuration: 0.065), .removeFromParent()]))
        addChild(charge)

        let beam = SKShapeNode(path: path)
        beam.strokeColor = color
        beam.lineWidth = 2
        beam.glowWidth = 10
        beam.zPosition = 20
        beam.alpha = 0
        beam.run(.sequence([
            .wait(forDuration: 0.055),
            .fadeIn(withDuration: 0.025),
            .customAction(withDuration: 0.07) { node, elapsed in
                (node as? SKShapeNode)?.lineWidth = 2 + 7 * elapsed / 0.07
            },
            .fadeOut(withDuration: 0.2),
            .removeFromParent()
        ]))
        addChild(beam)

        let burst = SKShapeNode(circleOfRadius: 7)
        burst.position = start
        burst.strokeColor = color
        burst.lineWidth = 3
        burst.zPosition = 21
        burst.run(.sequence([.group([.scale(to: 3, duration: 0.2), .fadeOut(withDuration: 0.2)]), .removeFromParent()]))
        addChild(burst)
    }

    private func flashBrick(_ brick: SKNode) {
        guard let shape = brick as? SKShapeNode else { return }
        shape.removeAction(forKey: "laserFlash")
        shape.run(.sequence([
            .customAction(withDuration: 0.09) { node, elapsed in
                (node as? SKShapeNode)?.glowWidth = 12 * (1 - elapsed / 0.09)
            }
        ]), withKey: "laserFlash")
    }

    private func makeProgress(
        referenceSize: CGSize? = nil,
        referenceCellSize: CGFloat? = nil,
        referenceSpawnY: CGFloat? = nil
    ) -> GameProgress {
        let savedSize = referenceSize ?? size
        let savedCellSize = referenceCellSize ?? cellSize
        let savedSpawnY = referenceSpawnY ?? brickSpawnY
        var objects: [GameProgress.BoardObject] = []
        for node in children where node.name == "brick" || node.name == "pickup" {
            let kind: GameProgress.BoardObject.Kind
            let value: Int
            if node.name == "brick" {
                let rawShape = node.userData?["shape"] as? String
                kind = GameProgress.BoardObject.Kind(rawValue: rawShape ?? "") ?? .brick
                guard let liveValue = brickValues[ObjectIdentifier(node)] else { continue }
                value = liveValue
            } else {
                kind = powerUpKind(for: node)
                value = 0
            }
            objects.append(.init(
                kind: kind,
                xFraction: Double(node.position.x / max(savedSize.width, 1)),
                yFraction: Double(node.position.y / max(savedSize.height, 1)),
                value: value,
                orientation: node.userData?["orientation"] as? Int,
                rowFromSpawn: Double(Self.snappedRow(
                    positionY: node.position.y,
                    spawnY: savedSpawnY,
                    cellSize: savedCellSize
                ))
            ))
        }
        return GameProgress(
            round: roundNumber,
            ballCount: totalBalls,
            hitCount: hitCount,
            launchXFraction: Double(launchOrigin.x / max(savedSize.width, 1)),
            objects: objects
        )
    }

    private func saveProgress() {
        ProgressStore.save(makeProgress())
    }

    private func restore(_ progress: GameProgress) {
        roundNumber = max(1, progress.round)
        totalBalls = max(1, progress.ballCount)
        hitCount = max(0, progress.hitCount)
        launchOrigin.x = CGFloat(progress.launchXFraction) * size.width
        childNode(withName: "launchMarker")?.position = launchOrigin
        updateRemainingBallLabel(totalBalls)

        for object in progress.objects {
            let legacyY = CGFloat(object.yFraction) * size.height
            let rawRow = object.rowFromSpawn.map { CGFloat($0) }
                ?? (brickSpawnY - legacyY) / max(cellSize, 1)
            let row = Self.snappedRow(
                positionY: brickSpawnY - rawRow * cellSize,
                spawnY: brickSpawnY,
                cellSize: cellSize
            )
            let restoredY = brickSpawnY - CGFloat(row) * cellSize
            let position = CGPoint(x: CGFloat(object.xFraction) * size.width, y: restoredY)
            let column = min(max(Int(position.x / max(cellSize, 1)), 0), columns - 1)
            if object.kind == .brick || object.kind == .triangleBrick {
                addBrick(
                    column: column,
                    value: max(1, object.value),
                    kind: object.kind,
                    orientation: object.orientation,
                    position: position
                )
            } else {
                addPowerUp(column: column, kind: object.kind, position: position)
            }
        }
    }

    private func publish(_ phase: GameSession.Phase, canRecall: Bool = false) {
        session.update(
            round: roundNumber,
            ballCount: totalBalls,
            hitCount: hitCount,
            phase: phase,
            canRecall: canRecall
        )
    }

    deinit {
        launchTimer?.invalidate()
    }
}
