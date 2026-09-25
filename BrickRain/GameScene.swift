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
    private let ballRadius: CGFloat = 5.5
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
    private var didSetUp = false
    private var launchTimer: Timer?
    private var brickValues: [ObjectIdentifier: Int] = [:]
    private var activatedPowerUps = Set<ObjectIdentifier>()

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
        } else {
            addRow()
            saveProgress()
        }
        publish(.ready)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard didSetUp, oldSize.width > 0, oldSize.height > 0 else { return }
        let progress = makeProgress()
        removeAllChildren()
        brickValues.removeAll()
        configureBoard()
        restore(progress)
    }

    private var floorY: CGFloat { max(28, size.height * 0.045) }
    private var topY: CGFloat { size.height - 12 }
    // Keep one full cell between the top wall and the first row. Balls can use
    // this corridor to travel across the board and bounce back into bricks.
    private var brickSpawnY: CGFloat { topY - cellSize * 1.5 }

    private func configureBoard() {
        cellSize = size.width / CGFloat(columns)
        launchOrigin = CGPoint(x: size.width / 2, y: floorY + ballRadius + 1)

        addWall(from: CGPoint(x: 0, y: floorY), to: CGPoint(x: 0, y: topY))
        addWall(from: CGPoint(x: size.width, y: floorY), to: CGPoint(x: size.width, y: topY))
        addWall(from: CGPoint(x: 0, y: topY), to: CGPoint(x: size.width, y: topY))

        let launchMarker = SKShapeNode(circleOfRadius: ballRadius + 2)
        launchMarker.name = "launchMarker"
        launchMarker.fillColor = .white
        launchMarker.strokeColor = .clear
        launchMarker.position = launchOrigin
        addChild(launchMarker)
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
        guard !isFiring, let point = touches.first?.location(in: self), point.y > launchOrigin.y + 35 else { return }
        aimPoint = point
        publish(.aiming)
        drawAimGuide(to: point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isFiring, let point = touches.first?.location(in: self), point.y > launchOrigin.y + 20 else { return }
        aimPoint = point
        drawAimGuide(to: point)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isFiring, let target = aimPoint else { return }
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

        // Trace the actual ray to each wall instead of stepping in fixed-size
        // jumps. This keeps the reflected preview stable while the finger moves.
        for _ in 0..<8 {
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
        activeBalls = 0
        collectedBalls = 0
        firstLandingX = nil
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
        activeBalls += 1

        let ball = SKShapeNode(circleOfRadius: ballRadius)
        ball.name = "ball"
        ball.fillColor = .white
        ball.strokeColor = .clear
        ball.position = launchOrigin
        ball.zPosition = 5
        ball.physicsBody = SKPhysicsBody(circleOfRadius: ballRadius)
        ball.physicsBody?.isDynamic = true
        ball.physicsBody?.affectedByGravity = false
        ball.physicsBody?.allowsRotation = false
        ball.physicsBody?.friction = 0
        ball.physicsBody?.linearDamping = 0
        ball.physicsBody?.restitution = 1
        ball.physicsBody?.usesPreciseCollisionDetection = true
        ball.physicsBody?.categoryBitMask = Category.ball
        ball.physicsBody?.collisionBitMask = Category.brick | Category.wall
        ball.physicsBody?.contactTestBitMask = Category.brick | Category.pickup
        ball.physicsBody?.velocity = CGVector(dx: direction.dx * 520, dy: direction.dy * 520)
        addChild(ball)
    }

    override func update(_ currentTime: TimeInterval) {
        guard isFiring else { return }
        enumerateChildNodes(withName: "ball") { [weak self] node, _ in
            guard let self else { return }
            if node.position.y <= self.floorY + self.ballRadius + 3,
               (node.physicsBody?.velocity.dy ?? 0) < 0 {
                self.land(ball: node)
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
        if session.soundEnabled {
            run(.playSoundFileNamed("pop.wav", waitForCompletion: false))
        }
        if value <= 1 {
            brickValues[key] = nil
            brick.run(.sequence([.scale(to: 1.18, duration: 0.04), .fadeOut(withDuration: 0.08), .removeFromParent()]))
        } else {
            brickValues[key] = value - 1
            updateBrick(brick, value: value - 1)
            brick.run(.sequence([.scale(to: 0.93, duration: 0.025), .scale(to: 1, duration: 0.04)]))
        }
    }

    private func collect(pickup: SKNode, ball: SKNode) {
        guard pickup.parent != nil else { return }
        let kind = powerUpKind(for: pickup)
        switch kind {
        case .extraBall:
            pickup.removeFromParent()
            collectedBalls += 1
        case .spring:
            markActivated(pickup)
            if let body = ball.physicsBody {
                let speed = max(hypot(body.velocity.dx, body.velocity.dy) * 1.22, 560)
                let angle = CGFloat.random(in: 28...152) * .pi / 180
                body.velocity = CGVector(
                    dx: cos(angle) * speed,
                    dy: sin(angle) * speed
                )
            }
        case .laserVertical, .laserHorizontal, .laserCross:
            markActivated(pickup)
            fireLaser(kind, from: pickup.position)
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

    private func finishTurn() {
        isFiring = false
        totalBalls += collectedBalls
        roundNumber += 1
        hitCount = 0
        launchOrigin.x = firstLandingX ?? launchOrigin.x
        childNode(withName: "launchMarker")?.position = launchOrigin

        var reachedBottom = false
        enumerateChildNodes(withName: "brick") { [weak self] node, _ in
            guard let self else { return }
            node.position.y -= self.cellSize
            if node.position.y - self.cellSize * 0.445 <= self.floorY + 8 {
                reachedBottom = true
            }
        }
        enumerateChildNodes(withName: "pickup") { [weak self] node, _ in
            guard let self else { return }
            if self.activatedPowerUps.contains(ObjectIdentifier(node)) {
                node.removeFromParent()
                return
            }
            node.position.y -= self.cellSize
            if node.position.y < self.floorY { node.removeFromParent() }
        }
        activatedPowerUps.removeAll()

        if reachedBottom {
            ProgressStore.clear()
            publish(.gameOver)
        } else {
            addRow()
            saveProgress()
            publish(.ready)
        }
    }

    private func addRow() {
        var occupied = Set<Int>()
        let brickCount = Int.random(in: 2...5)
        for _ in 0..<brickCount {
            var column = Int.random(in: 0..<columns)
            while occupied.contains(column) { column = Int.random(in: 0..<columns) }
            occupied.insert(column)
            let variance = Int.random(in: 0...max(1, roundNumber / 3))
            let shape: GameProgress.BoardObject.Kind = Int.random(in: 0..<100) < 14 ? .triangleBrick : .brick
            addBrick(
                column: column,
                value: roundNumber + variance,
                kind: shape,
                orientation: shape == .triangleBrick ? Int.random(in: 0..<4) : nil
            )
        }

        if occupied.count < columns {
            var column = Int.random(in: 0..<columns)
            while occupied.contains(column) { column = Int.random(in: 0..<columns) }
            occupied.insert(column)
            addPowerUp(column: column, kind: .extraBall)
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
            brick = SKShapeNode(rectOf: CGSize(width: side, height: side), cornerRadius: 6)
            brick.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: side, height: side))
        }
        brick.name = "brick"
        brick.position = position ?? CGPoint(x: (CGFloat(column) + 0.5) * cellSize, y: brickSpawnY)
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
        brick.addChild(label)
        updateBrick(brick, value: value)
        addChild(brick)
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
        pickup.position = position ?? CGPoint(x: (CGFloat(column) + 0.5) * cellSize, y: brickSpawnY)
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
        label.fontSize = 12
        label.fontColor = color(for: kind)
        label.verticalAlignmentMode = .center
        pickup.addChild(label)
        addChild(pickup)
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
        case .brick, .triangleBrick: return .white
        }
    }

    private func symbol(for kind: GameProgress.BoardObject.Kind) -> String {
        switch kind {
        case .extraBall: return "+1"
        case .spring: return "↟"
        case .laserVertical: return "┃"
        case .laserHorizontal: return "↔"
        case .laserCross: return "✣"
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
        targets.forEach(hit)

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
        let beam = SKShapeNode(path: path)
        beam.strokeColor = color
        beam.lineWidth = 5
        beam.glowWidth = 7
        beam.zPosition = 20
        beam.run(.sequence([.fadeOut(withDuration: 0.22), .removeFromParent()]))
        addChild(beam)
    }

    private func makeProgress() -> GameProgress {
        var objects: [GameProgress.BoardObject] = []
        for node in children where node.name == "brick" || node.name == "pickup" {
            let kind: GameProgress.BoardObject.Kind
            let value: Int
            if node.name == "brick" {
                let rawShape = node.userData?["shape"] as? String
                kind = GameProgress.BoardObject.Kind(rawValue: rawShape ?? "") ?? .brick
                value = brickValues[ObjectIdentifier(node)] ?? 1
            } else {
                kind = powerUpKind(for: node)
                value = 0
            }
            objects.append(.init(
                kind: kind,
                xFraction: Double(node.position.x / max(size.width, 1)),
                yFraction: Double(node.position.y / max(size.height, 1)),
                value: value,
                orientation: node.userData?["orientation"] as? Int
            ))
        }
        return GameProgress(
            round: roundNumber,
            ballCount: totalBalls,
            hitCount: hitCount,
            launchXFraction: Double(launchOrigin.x / max(size.width, 1)),
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

        for object in progress.objects {
            let position = CGPoint(
                x: CGFloat(object.xFraction) * size.width,
                y: CGFloat(object.yFraction) * size.height
            )
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
