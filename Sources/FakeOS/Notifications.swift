import AppKit

final class Banner {
    let canvas: Canvas
    var age: Float = 0
    let life: Float
    var slide: Float = 0
    var dismissed = false
    var y: CGFloat = 0
    let app: AppKind

    init(world: World, app: AppKind, title: String, body: String) {
        self.app = app
        let w: CGFloat = 344
        let bodyH = min(48, Draw.textHeight(body, width: w - 70 - 16, font: Draw.font(12.5)))
        let h = max(62, 28 + bodyH + 12)
        canvas = Canvas(size: CGSize(width: w, height: h), scale: world.scale)
        life = 5 + Float(body.count) * 0.03
        canvas.draw { ctx in
            Icons.app(app, in: CGRect(x: 10, y: (h - 40) / 2, width: 40, height: 40), ctx: ctx)
            Draw.text(title, in: CGRect(x: 58, y: 11, width: w - 120, height: 18), font: Draw.font(13, .semibold), color: Draw.label,
                      lineBreak: .byTruncatingTail)
            Draw.text("now", at: CGPoint(x: w - 40, y: 12), font: Draw.font(11), color: Draw.secondary)
            Draw.text(body, in: CGRect(x: 58, y: 28, width: w - 70 - 8, height: bodyH + 2), font: Draw.font(12.5), color: NSColor(white: 0.15, alpha: 1))
        }
    }
}

final class Notifications {
    unowned let world: World
    var banners: [Banner] = []

    init(world: World) { self.world = world }

    func post(app: AppKind, title: String, body: String) {
        let b = Banner(world: world, app: app, title: title, body: body)
        banners.insert(b, at: 0)
        if banners.count > 3 { banners.removeLast(banners.count - 3) }
        world.audio.systemSound(app == .wren ? "Submarine" : "Glass")
    }

    func update(_ dt: Float) {
        for b in banners {
            b.age += dt
            if b.age > b.life { b.dismissed = true }
            let target: Float = b.dismissed ? 0 : 1
            b.slide += (target - b.slide) * min(1, dt * 9)
        }
        banners.removeAll { $0.dismissed && $0.slide < 0.02 }
        var y: CGFloat = world.menuBar.height + 10
        for b in banners {
            b.y += (y - b.y) * CGFloat(min(1, dt * 10))
            if b.age < 0.05 { b.y = y }
            y += b.canvas.size.height + 10
        }
    }

    private func rect(_ b: Banner) -> CGRect {
        let s = b.canvas.size
        let x = world.size.width - s.width - 14 + (1 - CGFloat(b.slide)) * (s.width + 30)
        return CGRect(x: x, y: b.y, width: s.width, height: s.height)
    }

    func hit(_ p: CGPoint) -> Banner? { banners.first { rect($0).contains(p) } }

    func draw(_ r: Renderer) {
        for b in banners.reversed() {
            let rect = rect(b)
            r.shadow(rect.offsetBy(dx: 0, dy: 4), radius: 16, blur: 14, opacity: 0.3)
            r.frosted(rect, tint: .rgba(0.96, 0.96, 0.97, 0.8), radius: 16)
            r.image(b.canvas, rect, radius: 16)
        }
    }
}
