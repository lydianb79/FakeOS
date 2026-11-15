import AppKit

final class DesktopIcon {
    let node: FSNode
    var pos: CGPoint   // top-left of the 90x96 cell
    init(node: FSNode, pos: CGPoint) { self.node = node; self.pos = pos }
    var rect: CGRect { CGRect(x: pos.x, y: pos.y, width: 90, height: 96) }
    var iconRect: CGRect { CGRect(x: pos.x + 13, y: pos.y + 4, width: 64, height: 64) }
}

final class Desktop {
    unowned let world: World
    var icons: [DesktopIcon] = []
    var selected = Set<ObjectIdentifier>()
    var canvas: Canvas
    var dirty = true
    var band: CGRect?
    private var bandStart: CGPoint?
    private var dragging: [(DesktopIcon, CGPoint)] = []
    private var dragStart: CGPoint?

    init(world: World) {
        self.world = world
        canvas = Canvas(size: world.size, scale: world.scale)
        sync()
    }

    func resize() {
        canvas = Canvas(size: world.size, scale: world.scale)
        dirty = true
    }

    private func slot(_ i: Int) -> CGPoint {
        let perCol = max(1, Int((world.size.height - 120) / 100))
        let col = i / perCol, row = i % perCol
        return CGPoint(x: world.size.width - 110 - CGFloat(col) * 100, y: 40 + CGFloat(row) * 100)
    }

    /// Keep icons in step with ~/Desktop.
    func sync() {
        let nodes = world.fs.desktop.children
        icons.removeAll { ic in !nodes.contains { $0 === ic.node } }
        for n in nodes where !icons.contains(where: { $0.node === n }) {
            var i = 0
            while icons.contains(where: { abs($0.pos.x - slot(i).x) < 40 && abs($0.pos.y - slot(i).y) < 40 }) { i += 1 }
            icons.append(DesktopIcon(node: n, pos: slot(i)))
        }
        dirty = true
    }

    func redrawIfNeeded() {
        guard dirty else { return }
        dirty = false
        canvas.draw { ctx in
            for ic in self.icons {
                let sel = self.selected.contains(ObjectIdentifier(ic))
                if sel { Draw.fill(ctx, ic.iconRect.insetBy(dx: -5, dy: -5), NSColor(white: 0, alpha: 0.28), radius: 6) }
                Icons.file(ic.node, in: ic.iconRect, ctx: ctx)
                let font = Draw.font(12, .medium)
                let maxW: CGFloat = 92
                let tw = min(maxW, Draw.size(ic.node.name, font: font).width + 8)
                let lines: CGFloat = Draw.size(ic.node.name, font: font).width + 8 > maxW ? 2 : 1
                let lr = CGRect(x: ic.rect.midX - tw / 2, y: ic.iconRect.maxY + 5, width: tw, height: 16 * lines + 1)
                if sel { Draw.fill(ctx, lr, Draw.selection, radius: 4) }
                ctx.saveGState()
                if !sel { ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 2.5, color: NSColor(white: 0, alpha: 0.85).cgColor) }
                Draw.text(ic.node.name, in: lr.insetBy(dx: 3, dy: 0), font: font, color: .white, align: .center, lineBreak: .byTruncatingMiddle)
                ctx.restoreGState()
            }
        }
    }

    func hit(_ p: CGPoint) -> DesktopIcon? {
        icons.last { $0.iconRect.insetBy(dx: -4, dy: -4).contains(p) || CGRect(x: $0.pos.x, y: $0.iconRect.maxY, width: 90, height: 30).contains(p) }
    }

    func mouseDown(_ p: CGPoint, clicks: Int, shift: Bool = false) {
        world.unfocusWindows()
        if let ic = hit(p) {
            if !selected.contains(ObjectIdentifier(ic)) { selected = [ObjectIdentifier(ic)] }
            if clicks >= 2 { world.openNode(ic.node) }
            dragging = icons.filter { selected.contains(ObjectIdentifier($0)) }.map { ($0, $0.pos) }
            dragStart = p
        } else {
            selected.removeAll()
            bandStart = p
            band = CGRect(origin: p, size: .zero)
        }
        dirty = true
    }

    func mouseDragged(_ p: CGPoint) {
        if let s = dragStart {
            for (ic, start) in dragging { ic.pos = CGPoint(x: start.x + p.x - s.x, y: max(26, start.y + p.y - s.y)) }
            dirty = true
        } else if let b = bandStart {
            let r = CGRect(x: min(b.x, p.x), y: min(b.y, p.y), width: abs(p.x - b.x), height: abs(p.y - b.y))
            band = r
            let newSel = Set(icons.filter { $0.iconRect.intersects(r) }.map { ObjectIdentifier($0) })
            if newSel != selected {
                selected = newSel
                dirty = true
                if icons.count >= 3 && selected.count == icons.count { world.story.desktopSelectedAll() }
            }
        }
    }

    func mouseUp(_ p: CGPoint) {
        dragStart = nil
        dragging.removeAll()
        bandStart = nil
        band = nil
    }

    func nudge(_ ic: DesktopIcon, by d: CGPoint) {
        ic.pos.x += d.x
        ic.pos.y += d.y
        dirty = true
    }
}
