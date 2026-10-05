import SwiftUI
import UIKit


struct ContentView: View {
    @State private var game = Game()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                game.update(now: timeline.date, size: size)
                game.draw(in: &context, size: size)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { game.pointerMoved(to: $0.location) }
                .onEnded { _ in game.tapped() }
        )
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}


@MainActor
final class Game {
    enum Phase { case menu, playing, over }

    struct Meteor {
        var pos: CGPoint
        var radius: CGFloat
        var velocity: CGVector
        var angle: Double
        var spin: Double
        var bumps: [CGFloat]
    }
    struct Gem { var pos: CGPoint; var speed: CGFloat }
    struct Particle {
        var pos: CGPoint
        var velocity: CGVector
        var life: Double
        let maxLife: Double
        let color: Color
        let size: CGFloat
    }
    struct Star { var pos: CGPoint; let speed: CGFloat; let size: CGFloat }

    private var phase: Phase = .menu
    private var size: CGSize = .zero
    private var lastFrame: Date?
    private var clock: Double = 0
    private var runTime: Double = 0

    private var player: CGPoint = .zero
    private var targetX: CGFloat = 0
    private let shipSize: CGFloat = 18

    private var meteors: [Meteor] = []
    private var gems: [Gem] = []
    private var particles: [Particle] = []
    private var stars: [Star] = []

    private var meteorTimer = 0.0
    private var gemTimer = 0.0
    private var score = 0.0
    private var best = UserDefaults.standard.integer(forKey: "starfallBest")
    private var isNewBest = false
    private var shake = 0.0
    private var gameOverAt = 0.0


    func pointerMoved(to point: CGPoint) {
        targetX = min(max(point.x, shipSize), size.width - shipSize)
    }

    func tapped() {
        switch phase {
        case .menu:
            start()
        case .over where clock - gameOverAt > 0.7:
            start()
        default:
            break
        }
    }


    private func start() {
        meteors.removeAll()
        gems.removeAll()
        runTime = 0
        score = 0
        isNewBest = false
        meteorTimer = 0.6
        gemTimer = 2.5
        player = CGPoint(x: size.width / 2, y: size.height - 140)
        targetX = player.x
        phase = .playing
    }

    private func layout(for newSize: CGSize) {
        size = newSize
        stars = (0..<90).map { _ in
            let depth = CGFloat.random(in: 0.2...1)
            return Star(
                pos: CGPoint(x: .random(in: 0...max(newSize.width, 1)),
                             y: .random(in: 0...max(newSize.height, 1))),
                speed: 30 + 140 * depth,
                size: 0.6 + 1.6 * depth
            )
        }
        player = CGPoint(x: newSize.width / 2, y: newSize.height - 140)
        targetX = player.x
    }


    func update(now: Date, size newSize: CGSize) {
        if newSize != size { layout(for: newSize) }
        let dt = min(now.timeIntervalSince(lastFrame ?? now), 1.0 / 30)
        lastFrame = now
        clock += dt
        let d = CGFloat(dt)

        let pace: CGFloat = phase == .playing ? 1 + CGFloat(runTime) / 25 : 0.5
        for i in stars.indices {
            stars[i].pos.y += stars[i].speed * pace * d
            if stars[i].pos.y > size.height {
                stars[i].pos = CGPoint(x: .random(in: 0...max(size.width, 1)), y: -2)
            }
        }


        let drag = CGFloat(pow(0.08, dt))
        for i in particles.indices {
            particles[i].pos.x += particles[i].velocity.dx * d
            particles[i].pos.y += particles[i].velocity.dy * d
            particles[i].velocity.dx *= drag
            particles[i].velocity.dy *= drag
            particles[i].life -= dt
        }
        particles.removeAll { $0.life <= 0 }
        shake = max(0, shake - dt * 2.5)

        guard phase == .playing else { return }

        runTime += dt
        score += dt * 10
        player.x += (targetX - player.x) * min(1, d * 14)

        particles.append(Particle(
            pos: CGPoint(x: player.x + .random(in: -4...4), y: player.y + shipSize * 0.7),
            velocity: CGVector(dx: .random(in: -20...20), dy: .random(in: 140...220)),
            life: 0.3, maxLife: 0.3,
            color: [.orange, .yellow, .red].randomElement()!,
            size: .random(in: 2...5)
        ))


        let difficulty = 1 + runTime / 18
        meteorTimer -= dt
        if meteorTimer <= 0 {
            spawnMeteor(difficulty: difficulty)
            meteorTimer = max(0.14, 0.85 / difficulty) * .random(in: 0.6...1.3)
        }
        gemTimer -= dt
        if gemTimer <= 0 {
            gems.append(Gem(pos: CGPoint(x: .random(in: 30...max(size.width - 30, 31)), y: -20),
                            speed: 170))
            gemTimer = .random(in: 2...4)
        }

        for i in meteors.indices {
            meteors[i].pos.x += meteors[i].velocity.dx * d
            meteors[i].pos.y += meteors[i].velocity.dy * d
            meteors[i].angle += meteors[i].spin * dt
        }
        meteors.removeAll { $0.pos.y - $0.radius > size.height + 20 }

        for i in gems.indices { gems[i].pos.y += gems[i].speed * d }
        gems.removeAll { $0.pos.y > size.height + 20 }

        if let idx = gems.firstIndex(where: { distance($0.pos, player) < shipSize + 14 }) {
            let gem = gems.remove(at: idx)
            score += 25
            burst(at: gem.pos, count: 24, colors: [.yellow, .white, .mint], speed: 220)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        if meteors.contains(where: { distance($0.pos, player) < $0.radius * 0.8 + shipSize * 0.7 }) {
            die()
        }
    }

    private func spawnMeteor(difficulty: Double) {
        let r = CGFloat.random(in: 14...38)
        let speed = CGFloat.random(in: 180...280) * CGFloat(min(difficulty, 2.8))
        meteors.append(Meteor(
            pos: CGPoint(x: .random(in: 0...max(size.width, 1)), y: -r - 10),
            radius: r,
            velocity: CGVector(dx: .random(in: -40...40), dy: speed),
            angle: .random(in: 0...(2 * .pi)),
            spin: .random(in: -2...2),
            bumps: (0..<10).map { _ in .random(in: 0.75...1.1) }
        ))
    }

    private func die() {
        phase = .over
        gameOverAt = clock
        shake = 1
        burst(at: player, count: 70, colors: [.cyan, .white, .orange, .pink], speed: 380)
        let final = Int(score)
        if final > best {
            best = final
            isNewBest = true
            UserDefaults.standard.set(best, forKey: "starfallBest")
        }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func burst(at point: CGPoint, count: Int, colors: [Color], speed: CGFloat) {
        for _ in 0..<count {
            let a = Double.random(in: 0...(2 * .pi))
            let s = CGFloat.random(in: 0.3...1) * speed
            let life = Double.random(in: 0.4...0.9)
            particles.append(Particle(
                pos: point,
                velocity: CGVector(dx: CGFloat(cos(a)) * s, dy: CGFloat(sin(a)) * s),
                life: life, maxLife: life,
                color: colors.randomElement()!,
                size: .random(in: 2...5)
            ))
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height

        ctx.fill(
            Path(CGRect(origin: .zero, size: size).insetBy(dx: -30, dy: -30)),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.02, green: 0.01, blue: 0.10),
                                  Color(red: 0.13, green: 0.02, blue: 0.24)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h))
        )

        if shake > 0 {
            let m = CGFloat(shake * shake * 14)
            ctx.translateBy(x: .random(in: -m...m), y: .random(in: -m...m))
        }

        for s in stars {
            ctx.fill(Path(ellipseIn: CGRect(x: s.pos.x, y: s.pos.y, width: s.size, height: s.size)),
                     with: .color(.white.opacity(Double(s.size / 2.4))))
        }

        for g in gems {
            let r = CGFloat(11 * (1 + 0.15 * sin(clock * 6)))
            let diamond = Path { p in
                p.move(to: CGPoint(x: g.pos.x, y: g.pos.y - r * 1.3))
                p.addLine(to: CGPoint(x: g.pos.x + r, y: g.pos.y))
                p.addLine(to: CGPoint(x: g.pos.x, y: g.pos.y + r * 1.3))
                p.addLine(to: CGPoint(x: g.pos.x - r, y: g.pos.y))
                p.closeSubpath()
            }
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: .yellow, radius: 10))
                layer.fill(diamond, with: .color(.yellow))
            }
        }

        for m in meteors {
            let rock = Path { p in
                for (i, bump) in m.bumps.enumerated() {
                    let a = m.angle + Double(i) / Double(m.bumps.count) * 2 * .pi
                    let pt = CGPoint(x: m.pos.x + CGFloat(cos(a)) * m.radius * bump,
                                     y: m.pos.y + CGFloat(sin(a)) * m.radius * bump)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                p.closeSubpath()
            }
            ctx.fill(rock, with: .radialGradient(
                Gradient(colors: [Color(red: 0.65, green: 0.50, blue: 0.44),
                                  Color(red: 0.28, green: 0.20, blue: 0.22)]),
                center: CGPoint(x: m.pos.x - m.radius * 0.3, y: m.pos.y - m.radius * 0.3),
                startRadius: 0, endRadius: m.radius * 1.4))
            ctx.stroke(rock, with: .color(.black.opacity(0.35)), lineWidth: 2)
        }

        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            for p in particles {
                let t = p.life / p.maxLife
                layer.fill(Path(ellipseIn: CGRect(x: p.pos.x - p.size / 2, y: p.pos.y - p.size / 2,
                                                  width: p.size, height: p.size)),
                           with: .color(p.color.opacity(t)))
            }
        }

        if phase != .over {
            let s = shipSize
            let bob = phase == .menu ? CGFloat(sin(clock * 2.5)) * 6 : 0
            let c = CGPoint(x: player.x, y: player.y + bob)
            let ship = Path { p in
                p.move(to: CGPoint(x: c.x, y: c.y - s * 1.2))
                p.addLine(to: CGPoint(x: c.x + s, y: c.y + s))
                p.addLine(to: CGPoint(x: c.x, y: c.y + s * 0.55))
                p.addLine(to: CGPoint(x: c.x - s, y: c.y + s))
                p.closeSubpath()
            }
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: .cyan, radius: 12))
                layer.fill(ship, with: .linearGradient(
                    Gradient(colors: [.white, .cyan]),
                    startPoint: CGPoint(x: c.x, y: c.y - s),
                    endPoint: CGPoint(x: c.x, y: c.y + s)))
            }
        }

        var pulse = ctx
        pulse.opacity = 0.55 + 0.45 * sin(clock * 4)

        switch phase {
        case .playing:
            ctx.draw(label("\(Int(score))", 44, .heavy), at: CGPoint(x: w / 2, y: 90))

        case .menu:
            ctx.draw(label("STARFALL", 60, .black), at: CGPoint(x: w / 2, y: h * 0.28))
            ctx.draw(label("Drag to steer your ship", 17, .medium, .white.opacity(0.8)),
                     at: CGPoint(x: w / 2, y: h * 0.28 + 62))
            ctx.draw(label("Grab gems  •  Avoid rocks", 17, .medium, .white.opacity(0.8)),
                     at: CGPoint(x: w / 2, y: h * 0.28 + 88))
            pulse.draw(label("Tap to start", 24, .bold, .cyan), at: CGPoint(x: w / 2, y: h * 0.52))
            if best > 0 {
                ctx.draw(label("Best: \(best)", 18, .semibold, .yellow), at: CGPoint(x: w / 2, y: h * 0.52 + 44))
            }

        case .over:
            ctx.draw(label("GAME OVER", 52, .black), at: CGPoint(x: w / 2, y: h * 0.3))
            ctx.draw(label("\(Int(score))", 72, .heavy, .cyan), at: CGPoint(x: w / 2, y: h * 0.3 + 80))
            ctx.draw(label(isNewBest ? "New best! 🎉" : "Best: \(best)", 20, .semibold, .yellow),
                     at: CGPoint(x: w / 2, y: h * 0.3 + 140))
            if clock - gameOverAt > 0.7 {
                pulse.draw(label("Tap to play again", 22, .bold), at: CGPoint(x: w / 2, y: h * 0.62))
            }
        }
    }

    private func label(_ text: String, _ size: CGFloat, _ weight: Font.Weight, _ color: Color = .white) -> Text {
        Text(text)
            .font(.system(size: size, weight: weight, design: .rounded))
            .foregroundStyle(color)
    }
}

#Preview {
    ContentView()
}
