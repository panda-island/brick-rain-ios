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
        addRow()
        publish(.ready)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard didSetUp else { return }
        removeAllChildren()
        brickValues.removeAll()
        configureBoard()
        addRow()
    }

    private var floorY: CGFloat { max(28, size.height * 0.045) }
    private var topY: CGFloat { size.height - 12 }

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
        let direction = normalizedDirection(to: target)
        let path = CGMutablePath()
        path.move(to: launchOrigin)
        for index in 1...9 {
            let distance = CGFloat(index) * 26
            path.addEllipse(in: CGRect(
                x: launchOrigin.x + direction.dx * distance - 2,
                y: launchOrigin.y + direction.dy * distance - 2,
                width: 4,
                height: 4
            ))
        }
        let guide = SKShapeNode(path: path)
        guide.name = "aimGuide"
        guide.fillColor = .white.withAlphaComponent(0.55)
        guide.strokeColor = .clear
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
        publish(.firing)
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
        pickup.removeFromParent()
        collectedBalls += 1
        let pulse = SKShapeNode(circleOfRadius: 13)
        pulse.position = ball.position
        pulse.strokeColor = .cyan
        pulse.lineWidth = 2
        pulse.run(.sequence([.group([.scale(to: 2.2, duration: 0.2), .fadeOut(withDuration: 0.2)]), .removeFromParent()]))
        addChild(pulse)
    }

    private func finishTurn() {
        isFiring = false
        totalBalls += collectedBalls
        roundNumber += 1
        launchOrigin.x = firstLandingX ?? launchOrigin.x
        childNode(withName: "launchMarker")?.position = launchOrigin

        var reachedBottom = false
        enumerateChildNodes(withName: "brick") { [weak self] node, _ in
            guard let self else { return }
            node.position.y -= self.cellSize
            if node.position.y - self.cellSize * 0.39 <= self.floorY + 8 {
                reachedBottom = true
            }
        }
        enumerateChildNodes(withName: "pickup") { [weak self] node, _ in
            guard let self else { return }
            node.position.y -= self.cellSize
            if node.position.y < self.floorY { node.removeFromParent() }
        }

        if reachedBottom {
            publish(.gameOver)
        } else {
            addRow()
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
            addBrick(column: column, value: roundNumber + variance)
        }
        if occupied.count < columns, Int.random(in: 0..<100) < 72 {
            var column = Int.random(in: 0..<columns)
            while occupied.contains(column) { column = Int.random(in: 0..<columns) }
            addPickup(column: column)
        }
    }

    private func addBrick(column: Int, value: Int) {
        let side = cellSize * 0.78
        let brick = SKShapeNode(rectOf: CGSize(width: side, height: side), cornerRadius: 6)
        brick.name = "brick"
        brick.position = CGPoint(x: (CGFloat(column) + 0.5) * cellSize, y: topY - cellSize * 0.52)
        brick.lineWidth = 2
        brick.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: side, height: side))
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

    private func addPickup(column: Int) {
        let pickup = SKShapeNode(circleOfRadius: min(14, cellSize * 0.22))
        pickup.name = "pickup"
        pickup.position = CGPoint(x: (CGFloat(column) + 0.5) * cellSize, y: topY - cellSize * 0.52)
        pickup.fillColor = .clear
        pickup.strokeColor = .cyan
        pickup.lineWidth = 2
        pickup.physicsBody = SKPhysicsBody(circleOfRadius: min(14, cellSize * 0.22))
        pickup.physicsBody?.isDynamic = false
        pickup.physicsBody?.categoryBitMask = Category.pickup
        pickup.physicsBody?.collisionBitMask = 0
        pickup.physicsBody?.contactTestBitMask = Category.ball

        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = "+1"
        label.fontSize = 12
        label.fontColor = .cyan
        label.verticalAlignmentMode = .center
        pickup.addChild(label)
        addChild(pickup)
    }

    private func publish(_ phase: GameSession.Phase) {
        session.update(round: roundNumber, ballCount: totalBalls, phase: phase)
    }

    deinit {
        launchTimer?.invalidate()
    }
}
