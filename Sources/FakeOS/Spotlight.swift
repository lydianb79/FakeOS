import AppKit

/// A Spotlight-style search bar over the fake file system (hidden files included — wren indexes everything).
final class SpotlightPopup: Popup {
    private var query = ""
    private var results: [FSNode] = []
    private var selected = 0
    private var caretOn = true
    private var caretTimer: Float = 0

    init(world: World) {
        super.init(world: world, frame: CGRect(x: world.size.width / 2 - 340, y: world.size.height * 0.22, width: 680, height: 58))
    }

    override var radius: CGFloat { 14 }

    private func search() {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty { results = [] } else {
            results = world.fs.root.descendants.filter { $0.name.lowercased().contains(q) }
                .sorted { ($0.isHidden ? 1 : 0, $0.name.count) < ($1.isHidden ? 1 : 0, $1.name.count) }
            results = Array(results.prefix(7))
        }
        selected = 0
        let h: CGFloat = 58 + (results.isEmpty ? (q.isEmpty ? 0 : 40) : CGFloat(results.count) * 34 + 14)
        let origin = frame.origin
        frame = CGRect(x: origin.x, y: origin.y, width: 680, height: h)
        canvas = Canvas(size: frame.size, scale: world.scale)
        dirty = true
        world.story.spotlightQuery(query)
    }

    override func drawContent(_ ctx: CGContext) {
        Draw.symbol("magnifyingglass", in: CGRect(x: 18, y: 17, width: 24, height: 24), color: NSColor(white: 0.35, alpha: 1))
        let font = Draw.font(24, .light)
        if query.isEmpty {
            Draw.text("Spotlight Search", at: CGPoint(x: 54, y: 13), font: font, color: NSColor(white: 0.6, alpha: 1))
        }
        let sz = Draw.text(query, at: CGPoint(x: 54, y: 13), font: font, color: Draw.label)
        if caretOn { Draw.fill(ctx, CGRect(x: 55 + sz.width, y: 16, width: 2, height: 28), Draw.accent) }
        if !query.isEmpty {
            Draw.line(ctx, CGPoint(x: 0, y: 58), CGPoint(x: frame.width, y: 58), NSColor(white: 0, alpha: 0.1))
            if results.isEmpty {
                Draw.text("No Results", at: CGPoint(x: 54, y: 69), font: Draw.font(13), color: Draw.secondary)
            }
            for (i, n) in results.enumerated() {
                let r = CGRect(x: 8, y: 64 + CGFloat(i) * 34, width: frame.width - 16, height: 32)
                if i == selected { Draw.fill(ctx, r, Draw.accent, radius: 7) }
                Icons.file(n, in: CGRect(x: r.minX + 8, y: r.minY + 2, width: 28, height: 28), ctx: ctx)
                Draw.text(n.name, at: CGPoint(x: r.minX + 46, y: r.minY + 7), font: Draw.font(14), color: i == selected ? .white : Draw.label)
                let path = world.fs.displayPath(n.parent ?? world.fs.root)
                let pw = Draw.size(path, font: Draw.font(11)).width
                Draw.text(path, at: CGPoint(x: r.maxX - pw - 12, y: r.minY + 9), font: Draw.font(11),
                          color: i == selected ? NSColor(white: 1, alpha: 0.8) : Draw.secondary)
            }
        }
    }

    func keyDown(_ k: KeyInput) {
        if k.isReturn {
            if results.indices.contains(selected) { open(results[selected]) }
            return
        }
        if k.isDown { selected = min(results.count - 1, selected + 1); dirty = true; return }
        if k.isUp { selected = max(0, selected - 1); dirty = true; return }
        if k.isBackspace { if !query.isEmpty { query.removeLast(); search() }; return }
        if k.cmd { return }
        if !k.text.isEmpty, query.count < 40 { query += k.text; search() }
    }

    private func open(_ n: FSNode) {
        world.closePopup()
        if n.kind == .folder { world.openFinder(n) } else { world.openNode(n) }
    }

    override func mouseUp(_ p: CGPoint) {
        let i = Int((p.y - 64) / 34)
        if p.y > 64, results.indices.contains(i) { open(results[i]) }
    }

    func tick(_ dt: Float) {
        caretTimer += dt
        if caretTimer > 0.5 { caretTimer = 0; caretOn.toggle(); dirty = true }
    }
}
