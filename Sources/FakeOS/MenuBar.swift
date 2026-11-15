import AppKit

struct MenuItem {
    var title: String
    var shortcut: String = ""
    var enabled = true
    var checked = false
    var isSeparator = false
    var action: (() -> Void)?

    static let separator = MenuItem(title: "", isSeparator: true)
    init(_ title: String, _ shortcut: String = "", enabled: Bool = true, checked: Bool = false, action: (() -> Void)? = nil) {
        self.title = title
        self.shortcut = shortcut
        self.enabled = enabled
        self.checked = checked
        self.action = action
    }
    init(title: String, isSeparator: Bool) {
        self.title = title
        self.isSeparator = isSeparator
    }
}

class Popup {
    unowned let world: World
    var frame: CGRect
    var canvas: Canvas
    var dirty = true
    var owner: String = ""

    init(world: World, frame: CGRect) {
        self.world = world
        self.frame = frame
        canvas = Canvas(size: frame.size, scale: world.scale)
    }

    func redrawIfNeeded() {
        guard dirty else { return }
        dirty = false
        canvas.draw { ctx in self.drawContent(ctx) }
    }

    func drawContent(_ ctx: CGContext) {}
    func mouseDown(_ p: CGPoint) {}
    func mouseDragged(_ p: CGPoint) {}
    func mouseUp(_ p: CGPoint) {}
    func mouseMoved(_ p: CGPoint) {}
    var radius: CGFloat { 8 }
}

final class MenuPopup: Popup {
    let items: [MenuItem]
    var highlighted: Int?

    init(world: World, items: [MenuItem], at origin: CGPoint) {
        self.items = items
        let font = Draw.font(13)
        var w: CGFloat = 200
        for it in items {
            w = max(w, Draw.size(it.title, font: font).width + Draw.size(it.shortcut, font: font).width + 70)
        }
        let h = items.reduce(CGFloat(10)) { $0 + ($1.isSeparator ? 11 : 22) }
        super.init(world: world, frame: CGRect(x: min(origin.x, world.size.width - w - 6), y: origin.y, width: w, height: h))
    }

    private func rowRects() -> [CGRect] {
        var y: CGFloat = 5
        return items.map { it in
            let r = CGRect(x: 5, y: y, width: frame.width - 10, height: it.isSeparator ? 11 : 22)
            y += r.height
            return r
        }
    }

    override func drawContent(_ ctx: CGContext) {
        let font = Draw.font(13)
        for (i, (it, r)) in zip(items, rowRects()).enumerated() {
            if it.isSeparator {
                Draw.line(ctx, CGPoint(x: r.minX + 9, y: r.midY), CGPoint(x: r.maxX - 9, y: r.midY), NSColor(white: 0, alpha: 0.12))
                continue
            }
            let hi = highlighted == i && it.enabled
            if hi { Draw.fill(ctx, r, Draw.accent, radius: 4) }
            let color: NSColor = !it.enabled ? NSColor(white: 0, alpha: 0.28) : (hi ? .white : NSColor(white: 0.08, alpha: 1))
            if it.checked { Draw.symbol("checkmark", in: CGRect(x: r.minX + 6, y: r.minY + 6, width: 11, height: 11), color: color, weight: .bold) }
            Draw.text(it.title, at: CGPoint(x: r.minX + 22, y: r.minY + 3), font: font, color: color)
            if !it.shortcut.isEmpty {
                let sw = Draw.size(it.shortcut, font: font).width
                Draw.text(it.shortcut, at: CGPoint(x: r.maxX - sw - 10, y: r.minY + 3), font: font,
                          color: hi ? .white : NSColor(white: 0, alpha: it.enabled ? 0.45 : 0.25))
            }
        }
    }

    override func mouseMoved(_ p: CGPoint) {
        let h = rowRects().firstIndex { $0.contains(p) }
        if h != highlighted { highlighted = h; dirty = true }
    }

    override func mouseDown(_ p: CGPoint) {}

    override func mouseUp(_ p: CGPoint) {
        guard let i = rowRects().firstIndex(where: { $0.contains(p) }) else { return }
        let it = items[i]
        guard !it.isSeparator, it.enabled else { return }
        world.closePopup()
        it.action?()
    }
}

// MARK: - Wi-Fi

final class WifiPopup: Popup {
    var highlighted: Int?
    let ghostName: String
    let networks = ["NETGEAR-2F", "MochiNet", "DIRECT-37-HP OfficeJet"]

    init(world: World, at origin: CGPoint, ghostName: String) {
        self.ghostName = ghostName
        super.init(world: world, frame: CGRect(x: origin.x, y: origin.y, width: 300, height: 316))
    }

    override var radius: CGFloat { 12 }

    private var rows: [(String, CGRect)] {
        var out: [(String, CGRect)] = [("Halloway Home", CGRect(x: 6, y: 74, width: 288, height: 32))]
        var y: CGFloat = 136
        for n in [networks[0], ghostName, networks[1], networks[2]] {
            out.append((n, CGRect(x: 6, y: y, width: 288, height: 30)))
            y += 30
        }
        out.append(("Other…", CGRect(x: 6, y: y + 10, width: 288, height: 24)))
        out.append(("Wi-Fi Settings…", CGRect(x: 6, y: y + 34, width: 288, height: 24)))
        return out
    }

    override func drawContent(_ ctx: CGContext) {
        Draw.text("Wi-Fi", at: CGPoint(x: 16, y: 14), font: Draw.font(13, .bold), color: Draw.label)
        let tg = CGRect(x: frame.width - 50, y: 14, width: 34, height: 19)
        Draw.fill(ctx, tg, Draw.accent, radius: 9.5)
        Draw.circle(ctx, CGPoint(x: tg.maxX - 9.5, y: tg.midY), 8, .white)
        Draw.line(ctx, CGPoint(x: 14, y: 46), CGPoint(x: frame.width - 14, y: 46), NSColor(white: 0, alpha: 0.1))
        Draw.text("Known Network", at: CGPoint(x: 16, y: 54), font: Draw.font(11, .semibold), color: Draw.secondary)
        Draw.text("Other Networks", at: CGPoint(x: 16, y: 116), font: Draw.font(11, .semibold), color: Draw.secondary)
        let rs = rows
        Draw.line(ctx, CGPoint(x: 14, y: rs[rs.count - 2].1.minY - 5), CGPoint(x: frame.width - 14, y: rs[rs.count - 2].1.minY - 5), NSColor(white: 0, alpha: 0.1))
        for (i, (name, r)) in rs.enumerated() {
            if highlighted == i { Draw.fill(ctx, r, NSColor(white: 0, alpha: 0.08), radius: 6) }
            if i >= rs.count - 2 {
                Draw.text(name, at: CGPoint(x: r.minX + 10, y: r.minY + 4), font: Draw.font(13), color: Draw.label)
                continue
            }
            let known = i == 0
            let isGhost = name == ghostName
            Draw.circle(ctx, CGPoint(x: r.minX + 20, y: r.midY), 13, known ? Draw.accent : NSColor(white: 0, alpha: 0.09))
            Draw.symbol(isGhost ? "wifi.exclamationmark" : "wifi", in: CGRect(x: r.minX + 12, y: r.midY - 7, width: 16, height: 14),
                        color: known ? .white : NSColor(white: 0.2, alpha: 1), weight: .semibold)
            Draw.text(name, at: CGPoint(x: r.minX + 42, y: r.minY + (r.height - 16) / 2), font: Draw.font(13), color: Draw.label)
            Draw.symbol("lock.fill", in: CGRect(x: r.maxX - 24, y: r.midY - 6, width: 10, height: 12), color: Draw.secondary)
        }
    }

    override func mouseMoved(_ p: CGPoint) {
        let h = rows.firstIndex { $0.1.contains(p) }
        if h != highlighted { highlighted = h; dirty = true }
    }

    override func mouseUp(_ p: CGPoint) {
        guard let (name, _) = rows.first(where: { $0.1.contains(p) }) else { return }
        world.closePopup()
        world.story.wifiChosen(name, ghost: name == ghostName)
    }
}

// MARK: - Control Center

final class ControlCenterPopup: Popup {
    private var draggingSlider: Int?   // 0 display, 1 sound

    init(world: World, at origin: CGPoint) {
        super.init(world: world, frame: CGRect(x: origin.x, y: origin.y, width: 320, height: 360))
    }

    override var radius: CGFloat { 16 }

    private let displayModule = CGRect(x: 10, y: 150, width: 300, height: 66)
    private let soundModule = CGRect(x: 10, y: 224, width: 300, height: 66)
    private func track(_ m: CGRect) -> CGRect { CGRect(x: m.minX + 12, y: m.minY + 32, width: m.width - 24, height: 22) }

    override func drawContent(_ ctx: CGContext) {
        let tile = NSColor(white: 1, alpha: 0.55)
        // connectivity
        let conn = CGRect(x: 10, y: 10, width: 146, height: 132)
        Draw.fill(ctx, conn, tile, radius: 14)
        let rows: [(String, String, String, Bool)] = [
            ("wifi", "Wi-Fi", "Halloway Home", true),
            ("antenna.radiowaves.left.and.right", "Bluetooth", "On", true),
            ("airplayaudio", "AirDrop", "Contacts Only", false),
        ]
        for (i, r) in rows.enumerated() {
            let y = conn.minY + 12 + CGFloat(i) * 40
            Draw.circle(ctx, CGPoint(x: conn.minX + 24, y: y + 14), 14, r.3 ? Draw.accent : NSColor(white: 0, alpha: 0.1))
            Draw.symbol(r.0, in: CGRect(x: conn.minX + 16, y: y + 7, width: 16, height: 14), color: r.3 ? .white : NSColor(white: 0.2, alpha: 1), weight: .semibold)
            Draw.text(r.1, at: CGPoint(x: conn.minX + 45, y: y + 1), font: Draw.font(12, .semibold), color: Draw.label)
            Draw.text(r.2, at: CGPoint(x: conn.minX + 45, y: y + 15), font: Draw.font(11), color: Draw.secondary)
        }
        // focus + two small tiles
        let focus = CGRect(x: 164, y: 10, width: 146, height: 62)
        Draw.fill(ctx, focus, tile, radius: 14)
        Draw.circle(ctx, CGPoint(x: focus.minX + 24, y: focus.midY), 14, NSColor(white: 0, alpha: 0.1))
        Draw.symbol("moon.fill", in: CGRect(x: focus.minX + 17, y: focus.midY - 7, width: 14, height: 14), color: NSColor(white: 0.2, alpha: 1))
        Draw.text("Focus", at: CGPoint(x: focus.minX + 45, y: focus.midY - 8), font: Draw.font(12, .semibold), color: Draw.label)
        let small: [(String, String)] = [("rectangle.split.3x1", "Stage\nManager"), ("rectangle.on.rectangle", "Screen\nMirroring")]
        for (i, s) in small.enumerated() {
            let r = CGRect(x: 164 + CGFloat(i) * 77, y: 80, width: 69, height: 62)
            Draw.fill(ctx, r, tile, radius: 14)
            Draw.symbol(s.0, in: CGRect(x: r.midX - 9, y: r.minY + 8, width: 18, height: 16), color: NSColor(white: 0.2, alpha: 1))
            Draw.text(s.1, in: CGRect(x: r.minX, y: r.minY + 28, width: r.width, height: 30), font: Draw.font(9.5), color: Draw.label, align: .center)
        }
        // sliders
        for (m, title, icon, value) in [(displayModule, "Display", "sun.max.fill", world.brightness),
                                        (soundModule, "Sound", "speaker.wave.2.fill", world.audio.master)] {
            Draw.fill(ctx, m, tile, radius: 14)
            Draw.text(title, at: CGPoint(x: m.minX + 12, y: m.minY + 9), font: Draw.font(12, .semibold), color: Draw.label)
            let t = track(m)
            Draw.fill(ctx, t, NSColor(white: 0, alpha: 0.1), radius: 11)
            let fw = max(22, t.width * CGFloat(value))
            Draw.fill(ctx, CGRect(x: t.minX, y: t.minY, width: fw, height: t.height), .white, radius: 11)
            Draw.circle(ctx, CGPoint(x: t.minX + fw - 11, y: t.midY), 10, .white)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 0.5), blur: 2, color: NSColor(white: 0, alpha: 0.3).cgColor)
            Draw.circle(ctx, CGPoint(x: t.minX + fw - 11, y: t.midY), 10, .white)
            ctx.restoreGState()
            Draw.symbol(icon, in: CGRect(x: t.minX + 5, y: t.minY + 4, width: 14, height: 14), color: NSColor(white: 0.45, alpha: 1))
        }
        // now playing
        let np = CGRect(x: 10, y: 298, width: 300, height: 52)
        Draw.fill(ctx, np, tile, radius: 14)
        Draw.fill(ctx, CGRect(x: np.minX + 10, y: np.minY + 8, width: 36, height: 36), NSColor(white: 0, alpha: 0.12), radius: 6)
        Draw.symbol("music.note", in: CGRect(x: np.minX + 18, y: np.minY + 16, width: 20, height: 20), color: NSColor(white: 0.4, alpha: 1))
        let playing = world.story.haunt > 0.5 && !world.story.ended
        Draw.text(playing ? "breathing (loop)" : "Not Playing", at: CGPoint(x: np.minX + 56, y: np.minY + (playing ? 9 : 17)), font: Draw.font(12, .semibold), color: Draw.label)
        if playing { Draw.text("wren", at: CGPoint(x: np.minX + 56, y: np.minY + 25), font: Draw.font(11), color: Draw.secondary) }
        Draw.symbol(playing ? "pause.fill" : "play.fill", in: CGRect(x: np.maxX - 34, y: np.midY - 9, width: 18, height: 18), color: NSColor(white: 0.3, alpha: 1))
    }

    private func setValue(_ i: Int, _ p: CGPoint) {
        let t = track(i == 0 ? displayModule : soundModule)
        let v = Float(max(0, min(1, (p.x - t.minX) / t.width)))
        if i == 0 { world.setBrightness(max(0.02, v)) } else { world.audio.master = v; world.story.volumeChanged(v) }
        dirty = true
    }

    override func mouseDown(_ p: CGPoint) {
        if track(displayModule).insetBy(dx: -4, dy: -6).contains(p) { draggingSlider = 0; setValue(0, p) }
        else if track(soundModule).insetBy(dx: -4, dy: -6).contains(p) { draggingSlider = 1; setValue(1, p) }
        else if CGRect(x: 10, y: 10, width: 146, height: 50).contains(p) {
            world.closePopup()
            world.openWifiMenu()
        } else if CGRect(x: 164, y: 10, width: 146, height: 62).contains(p) {
            world.story.focusTapped()
        }
    }

    override func mouseDragged(_ p: CGPoint) {
        if let i = draggingSlider { setValue(i, p) }
    }

    override func mouseUp(_ p: CGPoint) {
        draggingSlider = nil
    }
}

// MARK: - Menu bar

final class MenuBar {
    unowned let world: World
    var canvas: Canvas
    var dirty = true
    let height: CGFloat = 24
    private(set) var leftRects: [CGRect] = []
    private(set) var rightRects: [(String, CGRect)] = []
    var openTitle: Int?
    var openRight: String?
    var clockOverride: String? { didSet { dirty = true } }
    var appNameOverride: String? { didSet { dirty = true } }
    private var lastClock = ""

    init(world: World) {
        self.world = world
        canvas = Canvas(size: CGSize(width: world.size.width, height: 24), scale: world.scale)
    }

    func resize() {
        canvas = Canvas(size: CGSize(width: world.size.width, height: height), scale: world.scale)
        dirty = true
    }

    var appName: String { appNameOverride ?? world.activeApp.rawValue }
    var titles: [String] { ["", appName, "File", "Edit", "View", "Go", "Window", "Help"] }

    func redrawIfNeeded() {
        let clock = clockOverride ?? world.story.clockString
        if clock != lastClock { lastClock = clock; dirty = true }
        guard dirty else { return }
        dirty = false
        let W = world.size.width
        canvas.draw { ctx in
            let font = Draw.font(13)
            let white = NSColor(white: 1, alpha: 0.95)
            var x: CGFloat = 10
            var rects: [CGRect] = []
            for (i, t) in self.titles.enumerated() {
                let w: CGFloat = i == 0 ? 34 : Draw.size(t, font: i == 1 ? Draw.font(13, .bold) : font).width + 20
                let r = CGRect(x: x, y: 2, width: w, height: 20)
                if self.openTitle == i { Draw.fill(ctx, r, NSColor(white: 1, alpha: 0.24), radius: 5) }
                if i == 0 {
                    Draw.symbol("hexagon.fill", in: CGRect(x: r.midX - 7, y: 5, width: 14, height: 14), color: white)
                } else {
                    Draw.text(t, at: CGPoint(x: r.minX + 10, y: 3), font: i == 1 ? Draw.font(13, .bold) : font, color: white)
                }
                rects.append(r)
                x += w
            }
            self.leftRects = rects
            // right side
            var rx = W - 12
            var rr: [(String, CGRect)] = []
            let cs = Draw.size(clock, font: font).width
            let clockR = CGRect(x: rx - cs - 16, y: 2, width: cs + 16, height: 20)
            rr.append(("clock", clockR))
            rx = clockR.minX - 2
            for (id, sym, w) in [("cc", "switch.2", CGFloat(30)), ("search", "magnifyingglass", 30), ("wifi", "wifi", 32), ("battery", "battery.75percent", 38)] {
                let r = CGRect(x: rx - w, y: 2, width: w, height: 20)
                rr.append((id, r))
                if self.openRight == id { Draw.fill(ctx, r, NSColor(white: 1, alpha: 0.24), radius: 5) }
                Draw.symbol(sym, in: CGRect(x: r.midX - (id == "battery" ? 12 : 8), y: 5, width: id == "battery" ? 24 : 16, height: 14), color: white)
                rx -= w + 2
            }
            if self.openRight == "clock" { Draw.fill(ctx, clockR, NSColor(white: 1, alpha: 0.24), radius: 5) }
            Draw.text(clock, at: CGPoint(x: clockR.minX + 8, y: 3), font: font, color: white)
            self.rightRects = rr
        }
    }

    func menuItems(for i: Int) -> [MenuItem] {
        let w = world
        switch i {
        case 0:
            return [
                MenuItem("About This Mac") { w.open(AboutWindow(world: w)) },
                .separator,
                MenuItem("System Settings…") { w.launch(.settings) },
                MenuItem("App Store…", enabled: false),
                .separator,
                MenuItem("Recent Items", enabled: false),
                .separator,
                MenuItem("Force Quit…", "⌥⌘⎋") { w.launch(.activity) },
                .separator,
                MenuItem("Sleep") { w.sleepDisplay() },
                MenuItem("Restart…") { w.restart() },
                MenuItem("Shut Down…") { w.shutDown() },
                .separator,
                MenuItem("Lock Screen", "^⌘Q", enabled: false),
                MenuItem("Log Out ines…", "⇧⌘Q") { w.restart() },
                .separator,
                MenuItem("Erase All Progress…") { w.confirmEraseProgress() },
            ]
        case 1:
            let app = w.activeApp
            return [
                MenuItem("About \(app.rawValue)") { w.open(AboutWindow(world: w)) },
                .separator,
                MenuItem("Settings…", "⌘,", enabled: false),
                .separator,
                MenuItem("Empty Trash…", "⇧⌘⌫") { w.story.requestEmptyTrash() },
                .separator,
                MenuItem("Hide \(app.rawValue)", "⌘H", enabled: false),
                MenuItem("Quit \(app.rawValue)", "⌘Q", enabled: app != .finder) { w.quitApp(app) },
            ]
        case 2:
            return [
                MenuItem("New Finder Window", "⌘N") { w.openFinder(w.fs.home) },
                MenuItem("New Folder", "⇧⌘N") { w.story.ambientWhisper("there's no room left in here.") },
                MenuItem("Open", "⌘O", enabled: w.desktop.selected.count == 1) { w.openSelectedDesktopItem() },
                MenuItem("Close Window", "⌘W", enabled: w.keyWindow != nil) { if let k = w.keyWindow { w.close(k) } },
            ]
        case 3:
            return [
                MenuItem("Undo", "⌘Z", enabled: false), MenuItem("Redo", "⇧⌘Z", enabled: false), .separator,
                MenuItem("Cut", "⌘X", enabled: false), MenuItem("Copy", "⌘C", enabled: false), MenuItem("Paste", "⌘V", enabled: false),
                MenuItem("Select All", "⌘A", enabled: false), .separator,
                MenuItem("Emoji & Symbols", "fn E", enabled: false),
            ]
        case 4:
            return [
                MenuItem("as Icons", "⌘1", checked: true), MenuItem("as List", "⌘2", enabled: false),
                MenuItem("as Columns", "⌘3", enabled: false), MenuItem("as Gallery", "⌘4", enabled: false), .separator,
                MenuItem("Show Hidden Files", "⇧⌘.", checked: w.showHidden) { w.toggleHidden() },
                .separator,
                MenuItem("Enter Full Screen", "fn F", enabled: false),
            ]
        case 5:
            return [
                MenuItem("Enclosing Folder", "⌘↑", enabled: false), .separator,
                MenuItem("Desktop", "⇧⌘D") { w.openFinder(w.fs.desktop) },
                MenuItem("Documents", "⇧⌘O") { w.openFinder(w.fs.documents) },
                MenuItem("Downloads", "⌥⌘L") { w.openFinder(w.fs.downloads) },
                MenuItem("Home", "⇧⌘H") { w.openFinder(w.fs.home) },
                MenuItem("Computer", "⇧⌘C") { w.openFinder(w.fs.root) },
                .separator,
                MenuItem("Utilities", "⇧⌘U") { w.launch(.terminal) },
                MenuItem("Go to Folder…", "⇧⌘G", enabled: false),
            ]
        case 6:
            return [
                MenuItem("Minimize", "⌘M", enabled: w.keyWindow != nil) { w.minimizeKey() },
                MenuItem("Zoom", enabled: false),
                .separator,
                MenuItem("Bring All to Front") { w.bringAllToFront() },
            ]
        default:
            return [
                MenuItem("Search", enabled: false),
                .separator,
                MenuItem("macOS Help") { w.story.ambientWhisper("no one is coming to help.") },
            ]
        }
    }

    func mouseDown(_ p: CGPoint) {
        if let i = leftRects.firstIndex(where: { $0.contains(p) }) {
            if openTitle == i { world.closePopup(); return }
            openMenu(i)
            return
        }
        if let (id, r) = rightRects.first(where: { $0.1.contains(p) }) {
            if openRight == id { world.closePopup(); return }
            world.closePopup()
            switch id {
            case "cc":
                openRight = id
                world.popup = ControlCenterPopup(world: world, at: CGPoint(x: world.size.width - 330, y: height + 4))
            case "wifi":
                world.openWifiMenu(anchor: r)
            case "clock":
                world.story.clockClicked()
            case "battery":
                openRight = id
                world.popup = MenuPopup(world: world, items: [
                    MenuItem("Battery                          13%", enabled: false),
                    MenuItem("Power Source: wren", enabled: false),
                    .separator,
                    MenuItem("Battery Settings…") { self.world.story.batterySettings() },
                ], at: CGPoint(x: r.minX - 140, y: height + 2))
            case "search":
                world.openSpotlight()
            default: break
            }
            dirty = true
        }
    }

    func openMenu(_ i: Int) {
        world.closePopup()
        openTitle = i
        let r = leftRects[i]
        let m = MenuPopup(world: world, items: menuItems(for: i), at: CGPoint(x: r.minX, y: height + 2))
        m.owner = "menu"
        world.popup = m
        dirty = true
    }

    func mouseMoved(_ p: CGPoint) {
        guard let open = openTitle, p.y < height else { return }
        if let i = leftRects.firstIndex(where: { $0.contains(p) }), i != open { openMenu(i) }
    }
}
