import AppKit

final class DockItem {
    enum Kind: Equatable { case app(AppKind), trash, separator }
    let kind: Kind
    var canvas: Canvas?
    var bounce: Float = 0
    var bounceCount: Int = 0
    var appear: Float = 1
    var trashFull = true
    init(kind: Kind, canvas: Canvas?) { self.kind = kind; self.canvas = canvas }

    var name: String {
        switch kind {
        case .app(let a): return a.rawValue
        case .trash: return "Trash"
        case .separator: return ""
        }
    }
}

final class Dock {
    unowned let world: World
    var items: [DockItem] = []
    let base: CGFloat = 50
    let maxSize: CGFloat = 76
    private var labelCanvas: Canvas?
    private var labelText = ""
    var hovered: Int?
    var allWren = false

    init(world: World) {
        self.world = world
        for a in [AppKind.finder, .terminal, .textEdit, .activity, .preview, .settings] {
            items.append(DockItem(kind: .app(a), canvas: makeIcon(.app(a))))
        }
        items.append(DockItem(kind: .separator, canvas: nil))
        items.append(DockItem(kind: .trash, canvas: makeIcon(.trash)))
    }

    func makeIcon(_ k: DockItem.Kind, full: Bool = true) -> Canvas {
        let c = Canvas(size: CGSize(width: 96, height: 96), scale: world.scale)
        c.draw { ctx in
            switch k {
            case .app(let a): Icons.app(self.allWren ? .wren : a, in: CGRect(x: 0, y: 0, width: 96, height: 96), ctx: ctx)
            case .trash: Icons.trash(full: full, in: CGRect(x: 0, y: 0, width: 96, height: 96), ctx: ctx)
            case .separator: break
            }
        }
        return c
    }

    func rebuildIcons() {
        for it in items where it.kind != .separator {
            it.canvas = makeIcon(it.kind, full: it.trashFull)
        }
    }

    func setTrash(full: Bool) {
        guard let t = items.first(where: { $0.kind == .trash }), t.trashFull != full else { return }
        t.trashFull = full
        t.canvas = makeIcon(.trash, full: full)
    }

    func addWren() {
        guard !items.contains(where: { $0.kind == .app(.wren) }) else { return }
        let it = DockItem(kind: .app(.wren), canvas: makeIcon(.app(.wren)))
        it.appear = 0
        let sep = items.firstIndex { $0.kind == .separator } ?? items.count
        items.insert(it, at: sep)
        bounce(.app(.wren), times: 2)
    }

    func removeWren() {
        items.removeAll { $0.kind == .app(.wren) }
    }

    func bounce(_ k: DockItem.Kind, times: Int = 1) {
        if let it = items.first(where: { $0.kind == k }) { it.bounceCount = times; if it.bounce <= 0 { it.bounce = 0.0001 } }
    }

    /// Icon frames with magnification for the current cursor position.
    func layout() -> (bg: CGRect, frames: [CGRect]) {
        let W = world.size.width, H = world.size.height
        let cursor = world.cursorPoint
        let pad: CGFloat = 6, gap: CGFloat = 4
        let restWidth = items.reduce(CGFloat(0)) { $0 + ($1.kind == .separator ? 14 : base * CGFloat($1.appear)) + gap } - gap
        let restX = W / 2 - restWidth / 2
        let near = cursor.y > H - base - pad * 2 - 30 && cursor.x > restX - 60 && cursor.x < restX + restWidth + 60
        var sizes: [CGFloat] = []
        var cx = restX
        for it in items {
            let w = it.kind == .separator ? 14 : base * CGFloat(it.appear)
            let center = cx + w / 2
            var s = w
            if near && it.kind != .separator {
                let d = abs(cursor.x - center)
                let k = max(0, 1 - d / 150)
                s = w + (maxSize - base) * CGFloat(it.appear) * (k * k * (3 - 2 * k))
            }
            sizes.append(s)
            cx += w + gap
        }
        let total = sizes.reduce(0, +) + gap * CGFloat(items.count - 1)
        var x = W / 2 - total / 2
        let bottom = H - pad - 4
        var frames: [CGRect] = []
        for (i, it) in items.enumerated() {
            let s = sizes[i]
            var y = bottom - s
            if it.bounce > 0 { y -= abs(sin(CGFloat(it.bounce) * .pi)) * 26 }
            frames.append(CGRect(x: x, y: y, width: s, height: s))
            x += s + gap
        }
        let bgW = restWidth + pad * 2 + max(0, total - restWidth)
        let bg = CGRect(x: W / 2 - bgW / 2, y: H - base - pad * 2 - 4, width: bgW, height: base + pad * 2)
        return (bg, frames)
    }

    var bounds: CGRect { layout().bg.insetBy(dx: 0, dy: -4) }

    func hit(_ p: CGPoint) -> Int? {
        let l = layout()
        guard l.bg.insetBy(dx: -2, dy: -40).contains(p) else { return nil }
        for (i, f) in l.frames.enumerated() where items[i].kind != .separator {
            if p.x >= f.minX - 2 && p.x <= f.maxX + 2 && p.y > f.minY - 4 { return i }
        }
        return nil
    }

    func update(_ dt: Float) {
        for it in items {
            if it.appear < 1 { it.appear = min(1, it.appear + dt * 3) }
            if it.bounce > 0 {
                it.bounce += dt * 1.9
                if it.bounce >= 1 {
                    it.bounceCount -= 1
                    it.bounce = it.bounceCount > 0 ? 0.0001 : 0
                }
            }
        }
        let p = world.cursorPoint
        let h = world.popup == nil && world.dockAcceptsHover ? hit(p) : nil
        if h != hovered {
            hovered = h
            if let i = h {
                let name = allWren ? "wren" : items[i].name
                if name != labelText {
                    labelText = name
                    let font = Draw.font(13)
                    let w = Draw.size(name, font: font).width + 22
                    let c = Canvas(size: CGSize(width: w, height: 26), scale: world.scale)
                    c.draw { _ in Draw.text(name, at: CGPoint(x: 11, y: 4), font: font, color: NSColor(white: 0.1, alpha: 1)) }
                    labelCanvas = c
                }
            }
        }
    }

    func draw(_ r: Renderer) {
        let l = layout()
        r.shadow(l.bg.offsetBy(dx: 0, dy: 3), radius: 18, blur: 14, opacity: 0.3)
        r.frosted(l.bg, tint: .rgba(0.95, 0.95, 0.98, 0.32), radius: 18)
        r.quad(l.bg, .rgba(1, 1, 1, 0.12), radius: 18)
        for (i, it) in items.enumerated() {
            let f = l.frames[i]
            if it.kind == .separator {
                r.quad(CGRect(x: f.midX - 0.5, y: l.bg.minY + 10, width: 1, height: l.bg.height - 20), .rgba(1, 1, 1, 0.4))
                continue
            }
            if let c = it.canvas { r.image(c, f, alpha: it.appear) }
            if case .app(let a) = it.kind, world.isRunning(a) {
                r.quad(CGRect(x: f.midX - 2, y: l.bg.maxY - 6, width: 4, height: 4), .rgba(0.1, 0.1, 0.1, 0.85), radius: 2)
            }
        }
        if let h = hovered, h < l.frames.count, let lc = labelCanvas {
            let f = l.frames[h]
            let rect = CGRect(x: f.midX - lc.size.width / 2, y: f.minY - 38, width: lc.size.width, height: lc.size.height)
            r.shadow(rect, radius: 7, blur: 6, opacity: 0.25)
            r.quad(rect, .rgba(0.93, 0.93, 0.95, 0.96), radius: 7)
            r.image(lc, rect)
        }
    }
}
