import AppKit

final class FinderWindow: FakeWindow {
    private(set) var folder: FSNode
    private var back: [FSNode] = []
    private var forward: [FSNode] = []
    var selected: FSNode?
    private var scrollY: CGFloat = 0
    private let sidebarW: CGFloat = 176

    override var titleBarHeight: CGFloat { 52 }
    override var trafficLightY: CGFloat { 26 }

    init(world: World, folder: FSNode) {
        self.folder = folder
        super.init(world: world, size: CGSize(width: 820, height: 480), title: "", app: .finder)
        title = displayName(folder)
    }

    func displayName(_ n: FSNode) -> String {
        if n === world.fs.trash { return "Trash" }
        if n === world.fs.root { return "Macintosh HD" }
        return n.name
    }

    var isTrash: Bool { folder === world.fs.trash }

    private var sidebarItems: [(String, String, FSNode?)] {
        let fs: FileSystem = world.fs
        return [
            ("Favorites", "", nil),
            ("Desktop", "menubar.dock.rectangle", fs.desktop),
            ("Documents", "doc", fs.documents),
            ("Downloads", "arrow.down.circle", fs.downloads),
            ("Pictures", "photo", fs.pictures),
            ("ines", "house", fs.home),
            ("Locations", "", nil),
            ("Macintosh HD", "internaldrive", fs.root),
            ("Trash", "trash", fs.trash),
            ("Tags", "", nil),
        ]
    }

    private func sidebarRects() -> [(CGRect, Int)] {
        var y: CGFloat = 58
        var out: [(CGRect, Int)] = []
        for (i, item) in sidebarItems.enumerated() {
            if item.2 == nil {
                y += i == 0 ? 0 : 10
                out.append((CGRect(x: 10, y: y, width: sidebarW - 20, height: 20), i))
                y += 20
            } else {
                out.append((CGRect(x: 10, y: y, width: sidebarW - 20, height: 26), i))
                y += 26
            }
        }
        return out
    }

    func navigate(to n: FSNode, record: Bool = true) {
        guard n !== folder else { return }
        if record { back.append(folder); forward.removeAll() }
        folder = n
        selected = nil
        scrollY = 0
        title = displayName(n)
        world.story.didOpenFolder(n)
        setNeedsDisplay()
    }

    private var items: [FSNode] { folder.visibleChildren(showHidden: world.showHidden) }

    private var gridTop: CGFloat { titleBarHeight + (isTrash ? 40 : 0) }

    private func layout() -> [(FSNode, CGRect)] {
        let cellW: CGFloat = 104, cellH: CGFloat = 104
        let x0 = sidebarW + 14
        let cols = max(1, Int((frame.width - x0 - 10) / cellW))
        return items.enumerated().map { i, n in
            let col = i % cols, row = i / cols
            return (n, CGRect(x: x0 + CGFloat(col) * cellW, y: gridTop + 14 + CGFloat(row) * cellH - scrollY, width: cellW, height: cellH))
        }
    }

    override func isDragRegion(_ p: CGPoint) -> Bool {
        p.y < titleBarHeight && !(p.x > sidebarW && p.x < sidebarW + 70)
    }

    override func drawTitleBar(_ ctx: CGContext) {
        let tb = CGRect(x: sidebarW, y: 0, width: frame.width - sidebarW, height: titleBarHeight)
        Draw.fill(ctx, tb, .white)
        Draw.line(ctx, CGPoint(x: sidebarW, y: tb.maxY - 0.25), CGPoint(x: frame.width, y: tb.maxY - 0.25), NSColor(white: 0, alpha: 0.1), width: 0.5)
        Draw.trafficLights(ctx, y: trafficLightY, active: isKey, hover: hoverLights)
        let dim = NSColor(white: 0.75, alpha: 1), on = NSColor(white: 0.35, alpha: 1)
        Draw.symbol("chevron.left", in: CGRect(x: sidebarW + 14, y: 18, width: 14, height: 16), color: back.isEmpty ? dim : on, weight: .semibold)
        Draw.symbol("chevron.right", in: CGRect(x: sidebarW + 42, y: 18, width: 14, height: 16), color: forward.isEmpty ? dim : on, weight: .semibold)
        Draw.text(titleOverride ?? title, in: CGRect(x: sidebarW + 72, y: 16, width: 300, height: 20),
                  font: Draw.font(14, .bold), color: isKey ? Draw.label : Draw.secondary, lineBreak: .byTruncatingTail)
        let icons = ["magnifyingglass", "tag", "square.and.arrow.up", "ellipsis.circle", "square.grid.2x2"]
        for (i, s) in icons.enumerated() {
            Draw.symbol(s, in: CGRect(x: frame.width - 36 - CGFloat(i) * 36, y: 17, width: 17, height: 17), color: on)
        }
    }

    override func drawContent(_ ctx: CGContext) {
        // sidebar
        let sb = CGRect(x: 0, y: 0, width: sidebarW, height: frame.height)
        Draw.fill(ctx, sb, Draw.hex(0xE9E6EE))
        Draw.line(ctx, CGPoint(x: sidebarW - 0.25, y: 0), CGPoint(x: sidebarW - 0.25, y: frame.height), NSColor(white: 0, alpha: 0.1), width: 0.5)
        let sitems = sidebarItems
        for (r, i) in sidebarRects() {
            let item = sitems[i]
            if let n = item.2 {
                if n === folder { Draw.fill(ctx, r, NSColor(white: 0, alpha: 0.09), radius: 6) }
                Draw.symbol(item.1, in: CGRect(x: r.minX + 8, y: r.minY + 5, width: 16, height: 16), color: Draw.accent)
                Draw.text(item.0, at: CGPoint(x: r.minX + 32, y: r.minY + 5), font: Draw.font(13), color: Draw.label)
            } else {
                Draw.text(item.0, at: CGPoint(x: r.minX + 6, y: r.minY + 4), font: Draw.font(11, .semibold), color: NSColor(white: 0.55, alpha: 1))
                if item.0 == "Tags" {
                    let tags: [(String, UInt32)] = [("Red", 0xFF5F57), ("Orange", 0xFF9F0A), ("Important", 0x8E8E93)]
                    for (j, t) in tags.enumerated() {
                        let y = r.maxY + 4 + CGFloat(j) * 24
                        Draw.circle(ctx, CGPoint(x: r.minX + 16, y: y + 8), 5, Draw.hex(t.1))
                        Draw.text(t.0, at: CGPoint(x: r.minX + 32, y: y), font: Draw.font(13), color: Draw.label)
                    }
                }
            }
        }

        // content
        let content = CGRect(x: sidebarW, y: titleBarHeight, width: frame.width - sidebarW, height: frame.height - titleBarHeight)
        if isTrash {
            let bar = CGRect(x: sidebarW, y: titleBarHeight, width: content.width, height: 40)
            Draw.fill(ctx, bar, Draw.hex(0xF7F7F7))
            Draw.line(ctx, CGPoint(x: bar.minX, y: bar.maxY), CGPoint(x: bar.maxX, y: bar.maxY), NSColor(white: 0, alpha: 0.08))
            Draw.text("Trash", at: CGPoint(x: bar.minX + 14, y: bar.minY + 12), font: Draw.font(13, .semibold), color: Draw.label)
            let b = emptyButtonRect
            Draw.fill(ctx, b, .white, radius: 6)
            Draw.stroke(ctx, b, NSColor(white: 0, alpha: 0.18), radius: 6, width: 0.5)
            Draw.text("Empty", in: b.offsetBy(dx: 0, dy: 3), font: Draw.font(12), color: Draw.label, align: .center)
        }
        ctx.saveGState()
        ctx.clip(to: CGRect(x: sidebarW, y: gridTop, width: content.width, height: frame.height - gridTop))
        let l = layout()
        if l.isEmpty {
            Draw.text(isTrash ? "Trash is empty" : "", in: CGRect(x: sidebarW, y: content.midY - 10, width: content.width, height: 20),
                      font: Draw.font(13), color: Draw.secondary, align: .center)
        }
        for (n, r) in l {
            let iconR = CGRect(x: r.midX - 32, y: r.minY + 4, width: 64, height: 64)
            let sel = selected === n
            if sel { Draw.fill(ctx, iconR.insetBy(dx: -4, dy: -4), NSColor(white: 0, alpha: 0.1), radius: 6) }
            ctx.saveGState()
            if n.isHidden { ctx.setAlpha(0.55) }
            Icons.file(n, in: iconR, ctx: ctx)
            ctx.restoreGState()
            let font = Draw.font(12)
            let labelW = min(r.width - 6, Draw.size(n.name, font: font).width + 10)
            let lr = CGRect(x: r.midX - labelW / 2, y: iconR.maxY + 6, width: labelW, height: 30)
            let lines: CGFloat = Draw.size(n.name, font: font).width + 10 > r.width - 6 ? 2 : 1
            if sel { Draw.fill(ctx, CGRect(x: lr.minX, y: lr.minY - 1, width: lr.width, height: 16 * lines + 2), Draw.selection, radius: 4) }
            Draw.text(n.name, in: CGRect(x: lr.minX + 4, y: lr.minY, width: lr.width - 8, height: 16 * lines),
                      font: font, color: sel ? .white : (n.isHidden ? Draw.secondary : Draw.label), align: .center, lineBreak: .byTruncatingMiddle)
        }
        ctx.restoreGState()
    }

    private var emptyButtonRect: CGRect { CGRect(x: frame.width - 84, y: titleBarHeight + 8, width: 70, height: 24) }

    override func mouseDown(_ p: CGPoint, clicks: Int) {
        if p.y < titleBarHeight {
            if CGRect(x: sidebarW + 8, y: 12, width: 26, height: 28).contains(p), let b = back.popLast() {
                forward.append(folder)
                navigate(to: b, record: false)
            } else if CGRect(x: sidebarW + 36, y: 12, width: 26, height: 28).contains(p), let f = forward.popLast() {
                back.append(folder)
                navigate(to: f, record: false)
            }
            return
        }
        if p.x < sidebarW {
            let sitems = sidebarItems
            for (r, i) in sidebarRects() where r.contains(p) {
                if let n = sitems[i].2 { navigate(to: n) }
            }
            return
        }
        if isTrash, emptyButtonRect.contains(p) {
            world.story.requestEmptyTrash()
            return
        }
        selected = nil
        for (n, r) in layout() where r.insetBy(dx: 8, dy: 0).contains(p) {
            selected = n
            if clicks >= 2 { open(n) }
        }
        setNeedsDisplay()
    }

    func open(_ n: FSNode) {
        if n.kind == .folder { navigate(to: n) } else { world.openNode(n) }
    }

    override func keyDown(_ k: KeyInput) -> Bool {
        if k.cmd, k.isUp, let p = folder.parent { navigate(to: p); return true }
        if k.cmd, k.isDown, let s = selected { open(s); return true }
        if k.cmd, k.isBackspace, let s = selected {
            world.story.moveToTrash(s, from: self)
            return true
        }
        return false
    }

    override func scroll(_ dy: CGFloat) {
        let rows = CGFloat((items.count + 5) / 6)
        scrollY = max(0, min(scrollY - dy, max(0, rows * 104 + 40 - (frame.height - gridTop))))
        setNeedsDisplay()
    }

    func refresh() {
        if let s = selected, s.parent !== folder { selected = nil }
        setNeedsDisplay()
    }
}
