import AppKit

/// The whole fake computer: window manager, input routing, effects state and drawing.
final class World {
    let renderer: Renderer
    private(set) var size: CGSize
    private(set) var scale: CGFloat
    let audio = Audio()
    let processes = ProcessTable()

    // rebuilt on restart
    var fs: FileSystem!
    var desktop: Desktop!
    var dock: Dock!
    var menuBar: MenuBar!
    var notifications: Notifications!
    var story: Story!
    var windows: [FakeWindow] = []
    var popup: Popup? { didSet { if popup == nil { menuBar?.openTitle = nil; menuBar?.openRight = nil; menuBar?.dirty = true } } }
    var showHidden = false

    // effects
    var time: Float = 0
    private(set) var haunt: Float = 0.1
    private var glitchLevel: Float = 0
    private(set) var brightness: Float = 1
    var reveal: Float = 0
    var calmTarget: Float = 0
    private var calm: Float = 0
    var bloodTarget: Float = 0
    private var blood: Float = 0
    var tear: Float = 0
    private var fade: Float = 1
    private var fadeTarget: Float = 1
    private var fadeSpeed: Float = 1
    private var fadeColor: RGBA = .rgba(0, 0, 0)
    private var shakeAmount: Float = 0
    var ghostLayerDirty = true
    private var ghostCanvas: Canvas!
    private var cursorCanvas: Canvas!
    private var bootLogo: Canvas!

    // cursor
    private var mouse = CGPoint(x: 400, y: 300)
    private var cursorOffset = CGPoint.zero
    private var hijackTarget = CGPoint.zero
    private var hijackTime: Float = 0
    var cursorPoint: CGPoint {
        CGPoint(x: max(0, min(size.width - 2, mouse.x + cursorOffset.x)), y: max(0, min(size.height - 2, mouse.y + cursorOffset.y)))
    }

    // phases
    private enum Phase { case boot, desktop, panic }
    private var phase: Phase = .boot
    private var bootTime: Float = 0
    private var endCard: Canvas?
    private var endCardGood = false
    private var endCardAlpha: Float = 0
    private var panicCanvas: Canvas?
    private var cascade = 0

    // input
    private enum Target { case none, popup, window(FakeWindow), drag(FakeWindow, CGPoint), desktop, menubar }
    private var target: Target = .none

    init(renderer: Renderer, size: CGSize, scale: CGFloat) {
        self.renderer = renderer
        self.size = size
        self.scale = scale
        buildStatic()
        reset()
    }

    private func buildStatic() {
        ghostCanvas = Canvas(size: size, scale: 1, mipmapped: true)
        renderer.ghostTexture = ghostCanvas.texture
        cursorCanvas = Canvas(size: CGSize(width: 28, height: 28), scale: scale)
        cursorCanvas.draw { ctx in Icons.cursor(ctx: ctx) }
        bootLogo = Canvas(size: CGSize(width: 120, height: 120), scale: scale)
        bootLogo.draw { _ in Draw.symbol("hexagon.fill", in: CGRect(x: 18, y: 18, width: 84, height: 84), color: .white) }
        ghostLayerDirty = true
    }

    func reset() {
        windows.removeAll()
        popup = nil
        showHidden = false
        fs = FileSystem()
        story = Story(world: self)
        desktop = Desktop(world: self)
        dock = Dock(world: self)
        menuBar = MenuBar(world: self)
        notifications = Notifications(world: self)
        haunt = 0.1
        calm = 0; calmTarget = 0
        blood = 0; bloodTarget = 0
        tear = 0
        brightness = 1
        glitchLevel = 0
        endCard = nil
        panicCanvas = nil
        phase = .boot
        bootTime = 0
        fade = 0
        fadeTarget = 0
        fadeColor = .rgba(0, 0, 0)
        cascade = 0
        ghostLayerDirty = true
        audio.staticLevel = 0
    }

    func resize(size: CGSize, scale: CGFloat) {
        guard size != self.size || scale != self.scale, size.width > 10 else { return }
        renderer.waitForGPU()
        self.size = size
        self.scale = scale
        buildStatic()
        desktop.resize()
        menuBar.resize()
        dock.rebuildIcons()
        desktop.sync()
    }

    // MARK: - Scheduling helpers

    func after(_ t: Float, _ f: @escaping () -> Void) { story.after(t, f) }

    // MARK: - Effects API

    func glitch(_ amount: Float) { glitchLevel = max(glitchLevel, amount) }
    func shakeWindows(_ amount: Float) { shakeAmount = max(shakeAmount, amount) }
    func forceHaunt(_ v: Float) { haunt = v }

    func hijackCursor(to p: CGPoint, duration: Float) {
        hijackTarget = p
        hijackTime = duration
    }

    func setBrightness(_ v: Float) { brightness = v }

    func fadeTo(color: RGBA, duration: Float) {
        fadeColor = color
        fadeTarget = 1
        fadeSpeed = 1 / max(0.01, duration)
    }

    func fadeFrom(duration: Float) {
        fadeTarget = 0
        fadeSpeed = 1 / max(0.01, duration)
    }

    func notify(_ app: AppKind, _ title: String, _ body: String) {
        guard phase == .desktop else { return }
        notifications.post(app: app, title: title, body: body)
    }

    var dockTrashCenter: CGPoint {
        let l = dock.layout()
        if let i = dock.items.firstIndex(where: { $0.kind == .trash }) { return CGPoint(x: l.frames[i].midX, y: l.frames[i].midY) }
        return CGPoint(x: size.width / 2, y: size.height - 30)
    }

    var dockAcceptsHover: Bool {
        if case .drag = target { return false }
        return true
    }

    // MARK: - Windows

    var keyWindow: FakeWindow? { windows.last { !$0.isMinimized && !$0.closing } }
    var activeApp: AppKind { keyWindow?.app ?? .finder }

    func isRunning(_ a: AppKind) -> Bool {
        if a == .finder { return true }
        if a == .wren { return story.wrenRunning }
        return windows.contains { $0.app == a && !$0.closing && !($0 is AlertWindow) }
    }

    func nextWindowOrigin(for s: CGSize) -> CGPoint {
        let x = size.width * 0.16 + CGFloat(cascade % 8) * 28
        let y = 70 + CGFloat(cascade % 8) * 26
        cascade += 1
        return CGPoint(x: min(x, size.width - s.width - 20), y: min(y, max(30, size.height - s.height - 100)))
    }

    func open(_ w: FakeWindow) {
        windows.append(w)
        w.appear = 0
        updateKey()
    }

    func close(_ w: FakeWindow) {
        guard !w.closing else { return }
        w.closing = true
        w.willClose()
        updateKey()
    }

    func closeAllWindows() { windows.forEach { close($0) } }

    func focus(_ w: FakeWindow) {
        if let modal = windows.last(where: { $0.isModal && !$0.closing }), modal !== w { return }
        windows.removeAll { $0 === w }
        windows.append(w)
        updateKey()
    }

    func unfocusWindows() {
        windows.forEach { $0.isKey = false }
    }

    private func updateKey() {
        let k = keyWindow
        windows.forEach { $0.isKey = $0 === k }
        menuBar?.dirty = true
    }

    func minimizeKey() {
        guard let k = keyWindow, !k.isModal else { return }
        k.isMinimized = true
        updateKey()
    }

    func bringAllToFront() {
        windows.forEach { $0.isMinimized = false }
        updateKey()
    }

    func refreshFinders() {
        windows.compactMap { $0 as? FinderWindow }.forEach { $0.refresh() }
        desktop.sync()
    }

    func toggleHidden() {
        showHidden.toggle()
        refreshFinders()
        if showHidden { story.didRevealHidden() }
    }

    @discardableResult
    func alert(icon: AppKind?, symbol: String? = nil, heading: String, message: String, buttons: [String], field: Bool = false) -> AlertWindow {
        let a = AlertWindow(world: self, icon: icon, symbol: symbol, heading: heading, message: message, buttons: buttons, field: field)
        open(a)
        audio.systemSound(field ? "Tink" : "Funk")
        return a
    }

    // MARK: - Apps

    func openFinder(_ n: FSNode) {
        open(FinderWindow(world: self, folder: n))
        story.didOpenFolder(n)
    }

    func openTextWindow(title: String, text: String, node: FSNode?) {
        open(TextEditWindow(world: self, title: title, text: text, node: node))
    }

    func openNode(_ n: FSNode) {
        switch n.kind {
        case .folder:
            openFinder(n)
        case .text:
            if let existing = windows.first(where: { ($0 as? TextEditWindow)?.node === n && !$0.closing }) {
                existing.isMinimized = false
                focus(existing)
            } else {
                openTextWindow(title: n.name, text: n.content, node: n)
            }
            story.didRead(n)
        case .image:
            open(PreviewWindow(world: self, name: n.name, picture: n.content))
            if n.content == "screenshot" { after(2.5) { self.glitch(0.3) } }
        case .lock, .soul:
            story.openLocked(n)
        case .pdf:
            alert(icon: .preview, heading: "The file “\(n.name)” could not be opened.",
                  message: "It may be damaged or use a file format that Preview doesn’t recognize.", buttons: ["OK"])
        case .dmg:
            alert(icon: .wren, heading: "“wren” is already installed.", message: "wren will always be installed.", buttons: ["OK"])
            glitch(0.4)
        case .app:
            launch(.wren)
        }
    }

    func launch(_ a: AppKind) {
        switch a {
        case .finder:
            if let f = windows.last(where: { $0 is FinderWindow && !$0.closing }) { f.isMinimized = false; focus(f) }
            else { openFinder(fs.home) }
        case .terminal:
            open(TerminalWindow(world: self))
        case .textEdit:
            story.openChat()
        case .activity:
            if let w = windows.last(where: { $0 is ActivityMonitorWindow && !$0.closing }) { w.isMinimized = false; focus(w) }
            else { open(ActivityMonitorWindow(world: self)) }
        case .preview:
            openFinder(fs.pictures)
        case .settings:
            alert(icon: .settings, heading: "System Settings is managed by your organization.",
                  message: "Organization: wren\nContact your administrator. Your administrator is wren.", buttons: ["OK"])
            glitch(0.25)
        case .wren:
            glitch(0.8)
            shakeWindows(0.5)
            hijackCursor(to: CGPoint(x: size.width / 2, y: size.height / 2), duration: 0.9)
            after(0.6) { self.notify(.wren, "wren", "you don't open me. i open you.") }
        }
    }

    func quitApp(_ a: AppKind) {
        windows.filter { $0.app == a }.forEach { close($0) }
    }

    func openSelectedDesktopItem() {
        if let ic = desktop.icons.first(where: { desktop.selected.contains(ObjectIdentifier($0)) }) { openNode(ic.node) }
    }

    func closePopup() { popup = nil }

    func openWifiMenu(anchor: CGRect? = nil) {
        let r = anchor ?? menuBar.rightRects.first(where: { $0.0 == "wifi" })?.1 ?? CGRect(x: size.width - 200, y: 0, width: 30, height: 24)
        menuBar.openRight = "wifi"
        menuBar.dirty = true
        popup = WifiPopup(world: self, at: CGPoint(x: min(r.minX - 20, size.width - 310), y: menuBar.height + 4), ghostName: story.nextGhostNetwork())
    }

    // MARK: - System

    func sleepDisplay() {
        fadeTo(color: .rgba(0, 0, 0), duration: 0.4)
        after(2.5) { self.fadeFrom(duration: 0.6); self.glitch(0.5) }
        after(3.2) { self.notify(.wren, "wren", "i don't sleep.") }
    }

    func restart() {
        fadeTo(color: .rgba(0, 0, 0), duration: 0.6)
        after(1.0) { self.reset() }
    }

    func shutDown() {
        fadeTo(color: .rgba(0, 0, 0), duration: 0.8)
        after(1.2) { NSApp.terminate(nil) }
    }

    func showEndCard(title: String, subtitle: String, good: Bool) {
        endCardGood = good
        let c = Canvas(size: CGSize(width: 520, height: 250), scale: scale)
        c.draw { ctx in
            let w: CGFloat = 520
            Draw.text("F A K E   O S", in: CGRect(x: 0, y: 28, width: w, height: 18), font: Draw.font(12, .semibold),
                      color: NSColor(white: 1, alpha: 0.55), align: .center)
            Draw.text(title, in: CGRect(x: 0, y: 58, width: w, height: 60), font: Draw.font(44, .bold), color: .white, align: .center)
            Draw.text(subtitle, in: CGRect(x: 0, y: 120, width: w, height: 22), font: Draw.font(15, .medium),
                      color: NSColor(white: 1, alpha: 0.75), align: .center)
            Draw.text("Thanks for playing.", in: CGRect(x: 0, y: 160, width: w, height: 20), font: Draw.font(13),
                      color: NSColor(white: 1, alpha: 0.65), align: .center)
            Draw.text(good ? "Click to keep exploring  ·  ⌘Q to quit" : "Press any key to restart  ·  ⌘Q to quit",
                      in: CGRect(x: 0, y: 206, width: w, height: 18), font: Draw.font(12), color: NSColor(white: 1, alpha: 0.45), align: .center)
        }
        endCard = c
        endCardAlpha = 0
    }

    func showPanic() {
        phase = .panic
        closeAllWindows()
        windows.removeAll()
        popup = nil
        let c = Canvas(size: CGSize(width: 640, height: 160), scale: scale)
        c.draw { _ in
            Draw.symbol("power", in: CGRect(x: 296, y: 0, width: 48, height: 48), color: NSColor(white: 0.75, alpha: 1))
            Draw.text("Your computer restarted because of a problem.\nPress a key or wait a few seconds to continue starting up.",
                      in: CGRect(x: 0, y: 70, width: 640, height: 50), font: Draw.font(15), color: NSColor(white: 0.8, alpha: 1), align: .center)
            Draw.text("panic(cpu 3 caller 0x1313): \"user ines not found\" @wren.c:317", in: CGRect(x: 0, y: 136, width: 640, height: 18),
                      font: Draw.mono(10), color: NSColor(white: 0.35, alpha: 1), align: .center)
        }
        panicCanvas = c
        fade = 0
        fadeTarget = 0
        bloodTarget = 0
        after(3) { self.showEndCard(title: "Erased", subtitle: "Ending 1 of 2", good: false) }
    }

    // MARK: - Update

    func update(dt: Float) {
        renderer.waitForGPU()
        time += dt

        if phase == .boot {
            bootTime += dt
            if bootTime > 4.6 {
                phase = .desktop
                fade = 1
                fadeColor = .rgba(0, 0, 0)
                fadeFrom(duration: 1.2)
                story.start()
                if let scene = ProcessInfo.processInfo.environment["FAKEOS_SCENE"] { debugScene(scene) }
            }
        }

        story.update(dt)

        // effect smoothing
        haunt += (story.hauntTarget - haunt) * min(1, dt * 0.6)
        calm += (calmTarget - calm) * min(1, dt * 0.5)
        blood += (bloodTarget - blood) * min(1, dt * 0.4)
        glitchLevel = max(0, glitchLevel - dt * 1.5)
        shakeAmount = max(0, shakeAmount - dt * 1.2)
        fade += max(-dt * fadeSpeed, min(dt * fadeSpeed, fadeTarget - fade))
        let b = brightness
        let rv = max(0, min(1, (0.3 - b) / 0.24))
        reveal = story.ended && story.goodEnding ? 0 : rv * rv * (3 - 2 * rv)
        audio.drone = phase == .desktop ? haunt * 0.9 + blood * 0.5 : 0
        audio.glitchStatic = glitchLevel * 0.22
        if endCard != nil { endCardAlpha = min(1, endCardAlpha + dt * 1.2) }

        // cursor hijack
        if hijackTime > 0 {
            hijackTime -= dt
            let desired = CGPoint(x: hijackTarget.x - mouse.x, y: hijackTarget.y - mouse.y)
            let k = CGFloat(min(1, dt * 2.5))
            cursorOffset.x += (desired.x - cursorOffset.x) * k
            cursorOffset.y += (desired.y - cursorOffset.y) * k
        } else {
            let k = CGFloat(min(1, dt * 3))
            cursorOffset.x -= cursorOffset.x * k
            cursorOffset.y -= cursorOffset.y * k
        }

        // windows
        for w in windows {
            if w.closing { w.appear = max(0, w.appear - dt * 7) } else { w.appear = min(1, w.appear + dt * 6) }
            w.update(dt)
        }
        windows.removeAll { $0.closing && $0.appear <= 0 }

        dock.update(dt)
        notifications.update(dt)

        // redraw dirty canvases
        if ghostLayerDirty { ghostLayerDirty = false; drawGhostLayer() }
        desktop.redrawIfNeeded()
        menuBar.redrawIfNeeded()
        popup?.redrawIfNeeded()
        windows.forEach { $0.redrawIfNeeded() }

        renderer.uniforms = Uniforms(
            a: SIMD4(Float(size.width), Float(size.height), time, haunt),
            b: SIMD4(glitchLevel, 0.03 + 0.97 * brightness, reveal, fade),
            c: fadeColor,
            d: SIMD4(calm, blood, tear, 0))
    }

    private func drawGhostLayer() {
        let W = size.width, H = size.height
        let stage = story.stage
        let ended = story.ended
        ghostCanvas.draw { ctx in
            let ink = NSColor(srgbRed: 0.78, green: 0.92, blue: 1.0, alpha: 0.95)
            func scrawl(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ angle: CGFloat) {
                ctx.saveGState()
                ctx.translateBy(x: x, y: y)
                ctx.rotate(by: angle)
                Draw.text(s, at: .zero, font: Draw.hand(size), color: ink)
                ctx.restoreGState()
            }
            if ended { return }
            if stage < .unlocked {
                scrawl("it can't read what's hidden", W * 0.08, H * 0.2, H * 0.06, -0.06)
                scrawl("⌘ ⇧ .", W * 0.5, H * 0.38, H * 0.13, 0.04)
                scrawl("look for  .wren", W * 0.14, H * 0.55, H * 0.07, 0.03)
                scrawl("— i", W * 0.66, H * 0.7, H * 0.05, -0.05)
                // tally marks: days counted in the dark
                for g in 0..<4 {
                    let gx = W * 0.72 + CGFloat(g) * H * 0.07, gy = H * 0.1
                    for i in 0..<4 {
                        Draw.line(ctx, CGPoint(x: gx + CGFloat(i) * H * 0.012, y: gy), CGPoint(x: gx + CGFloat(i) * H * 0.012 + 2, y: gy + H * 0.06), ink, width: 2.5)
                    }
                    Draw.line(ctx, CGPoint(x: gx - 6, y: gy + H * 0.045), CGPoint(x: gx + H * 0.05, y: gy + H * 0.012), ink, width: 2.5)
                }
            } else {
                var rng = SystemRandomNumberGenerator()
                for i in 0..<7 {
                    let x = W * (0.05 + 0.13 * CGFloat(i)) + CGFloat.random(in: -20...20, using: &rng)
                    let y = H * (0.15 + 0.1 * CGFloat(i % 4)) + CGFloat.random(in: -20...40, using: &rng)
                    scrawl("PUT ME BACK", x, y, H * (0.04 + 0.01 * CGFloat(i % 3)), CGFloat.random(in: -0.2...0.2, using: &rng))
                }
                scrawl("don't let it empty the bin", W * 0.3, H * 0.66, H * 0.06, -0.03)
            }
        }
    }

    // MARK: - Draw

    func draw(_ r: Renderer) {
        let full = CGRect(origin: .zero, size: size)
        if phase == .boot {
            let logo = CGRect(x: size.width / 2 - 60, y: size.height / 2 - 100, width: 120, height: 120)
            r.image(bootLogo, logo, alpha: min(1, bootTime * 2))
            if bootTime > 0.8 {
                let t = min(1, (bootTime - 0.8) / 3.4)
                let p = CGFloat(t < 0.4 ? t * 1.5 : (t < 0.7 ? 0.6 : 0.6 + (t - 0.7) * 1.33))
                let track = CGRect(x: size.width / 2 - 110, y: size.height / 2 + 60, width: 220, height: 5)
                r.quad(track, .rgba(1, 1, 1, 0.25), radius: 2.5)
                r.quad(CGRect(x: track.minX, y: track.minY, width: track.width * min(1, p), height: 5), .rgba(1, 1, 1, 0.95), radius: 2.5)
            }
            return
        }
        if phase == .panic {
            r.quad(full, .rgba(0, 0, 0))
            if let p = panicCanvas {
                r.image(p, CGRect(x: size.width / 2 - 320, y: size.height / 2 - 80, width: 640, height: 160))
            }
            drawEndCard(r)
            return
        }

        r.wallpaper(full)
        r.image(desktop.canvas, full)
        if let b = desktop.band {
            r.quad(b, .rgba(0.6, 0.6, 0.6, 0.25))
            r.quad(CGRect(x: b.minX, y: b.minY, width: b.width, height: 1), .rgba(0.85, 0.85, 0.85, 0.6))
            r.quad(CGRect(x: b.minX, y: b.maxY - 1, width: b.width, height: 1), .rgba(0.85, 0.85, 0.85, 0.6))
            r.quad(CGRect(x: b.minX, y: b.minY, width: 1, height: b.height), .rgba(0.85, 0.85, 0.85, 0.6))
            r.quad(CGRect(x: b.maxX - 1, y: b.minY, width: 1, height: b.height), .rgba(0.85, 0.85, 0.85, 0.6))
        }

        for w in windows where !w.isMinimized {
            let e = CGFloat(w.appear)
            let s = 0.94 + 0.06 * e
            var f = w.frame
            f = CGRect(x: f.midX - f.width * s / 2, y: f.midY - f.height * s / 2, width: f.width * s, height: f.height * s)
            if shakeAmount > 0 {
                f = f.offsetBy(dx: CGFloat.random(in: -1...1) * CGFloat(shakeAmount) * 7, dy: CGFloat.random(in: -1...1) * CGFloat(shakeAmount) * 4)
            }
            f = f.offsetBy(dx: CGFloat(w.shake), dy: 0)
            r.shadow(f.offsetBy(dx: 0, dy: w.isKey ? 14 : 6), radius: w.cornerRadius, blur: w.isKey ? 28 : 14, opacity: (w.isKey ? 0.5 : 0.3) * w.appear)
            r.image(w.canvas, f, radius: w.cornerRadius, alpha: w.appear)
        }

        dock.draw(r)

        let mb = CGRect(x: 0, y: 0, width: size.width, height: menuBar.height)
        r.frosted(mb, tint: .rgba(0.1, 0.08, 0.15, 0.25), radius: 0)
        r.image(menuBar.canvas, mb)

        notifications.draw(r)

        if let p = popup {
            r.shadow(p.frame.offsetBy(dx: 0, dy: 6), radius: p.radius, blur: 16, opacity: 0.35)
            r.frosted(p.frame, tint: .rgba(0.94, 0.94, 0.95, 0.82), radius: p.radius)
            r.image(p.canvas, p.frame, radius: p.radius)
        }

        drawEndCard(r)

        let c = cursorPoint
        r.image(cursorCanvas, CGRect(x: c.x - 2, y: c.y - 2, width: 28, height: 28))
    }

    private func drawEndCard(_ r: Renderer) {
        guard let card = endCard else { return }
        let a = endCardAlpha
        r.quad(CGRect(origin: .zero, size: size), .rgba(0, 0, 0, 0.6 * a))
        let rect = CGRect(x: size.width / 2 - 260, y: size.height / 2 - 125, width: 520, height: 250)
        r.image(card, rect, alpha: a)
    }

    // MARK: - Input

    func mouseMoved(_ p: CGPoint) {
        mouse = p
        let c = cursorPoint
        if let pop = popup {
            if pop.frame.contains(c) { pop.mouseMoved(CGPoint(x: c.x - pop.frame.minX, y: c.y - pop.frame.minY)); pop.dirty = true }
            menuBar.mouseMoved(c)
        }
        // traffic-light hover
        var hovered: FakeWindow?
        for w in windows.reversed() where !w.isMinimized && w.frame.contains(c) {
            let l = CGPoint(x: c.x - w.frame.minX, y: c.y - w.frame.minY)
            if w.showsTrafficLights && l.x < 72 && abs(l.y - w.trafficLightY) < 10 { hovered = w }
            break
        }
        windows.forEach { $0.hoverLights = $0 === hovered }
    }

    func mouseDown(_ p: CGPoint, clicks: Int, right: Bool) {
        mouse = p
        let c = cursorPoint
        target = .none

        if phase == .boot { return }
        if endCard != nil && endCardAlpha > 0.5 {
            if endCardGood { endCard = nil } else { restart() }
            return
        }
        if phase == .panic { return }

        if let pop = popup {
            if pop.frame.contains(c) {
                pop.mouseDown(CGPoint(x: c.x - pop.frame.minX, y: c.y - pop.frame.minY))
                pop.dirty = true
                target = .popup
                return
            }
            if c.y < menuBar.height { menuBar.mouseDown(c); return }
            closePopup()
            return
        }

        if let modal = windows.last(where: { $0.isModal && !$0.closing }) {
            if modal.frame.contains(c) { windowMouseDown(modal, c, clicks) } else { audio.beep() }
            return
        }

        if let b = notifications.hit(c) { b.dismissed = true; return }

        if c.y < menuBar.height {
            menuBar.mouseDown(c)
            target = .menubar
            return
        }

        if let i = dock.hit(c) {
            dockClicked(i)
            return
        }

        for w in windows.reversed() where !w.isMinimized && !w.closing && w.frame.contains(c) {
            windowMouseDown(w, c, clicks)
            return
        }

        desktop.mouseDown(c, clicks: clicks)
        target = .desktop
    }

    private func windowMouseDown(_ w: FakeWindow, _ c: CGPoint, _ clicks: Int) {
        focus(w)
        let l = CGPoint(x: c.x - w.frame.minX, y: c.y - w.frame.minY)
        if w.showsTrafficLights && abs(l.y - w.trafficLightY) < 8 {
            for i in 0..<3 where abs(l.x - (20 + CGFloat(i) * 20)) < 8 {
                switch i {
                case 0: close(w)
                case 1: w.isMinimized = true; updateKey()
                default: break
                }
                return
            }
        }
        if w.isDragRegion(l) {
            if clicks == 2 && !w.isModal { w.isMinimized = true; updateKey(); return }
            target = .drag(w, CGPoint(x: c.x - w.frame.minX, y: c.y - w.frame.minY))
            w.mouseDown(l, clicks: clicks)
            return
        }
        w.mouseDown(l, clicks: clicks)
        target = .window(w)
    }

    private func dockClicked(_ i: Int) {
        let it = dock.items[i]
        switch it.kind {
        case .trash:
            openFinder(fs.trash)
        case .app(let a):
            if dock.allWren { launch(.wren); return }
            let own = windows.filter { $0.app == a && !$0.closing && !($0 is AlertWindow) }
            if a == .wren || own.isEmpty {
                if a != .wren && a != .settings { dock.bounce(it.kind) }
                after(a == .wren || a == .settings ? 0 : 0.45) { self.launch(a) }
            } else {
                own.forEach { $0.isMinimized = false }
                if let last = own.last { focus(last) }
            }
        case .separator: break
        }
    }

    func mouseDragged(_ p: CGPoint) {
        mouse = p
        let c = cursorPoint
        switch target {
        case .popup:
            if let pop = popup { pop.mouseDragged(CGPoint(x: c.x - pop.frame.minX, y: c.y - pop.frame.minY)); pop.dirty = true }
        case .drag(let w, let off):
            w.frame.origin = CGPoint(x: c.x - off.x, y: max(menuBar.height + 1, c.y - off.y))
        case .window(let w):
            w.mouseDragged(CGPoint(x: c.x - w.frame.minX, y: c.y - w.frame.minY))
        case .desktop:
            desktop.mouseDragged(c)
        default:
            if let pop = popup, pop.frame.contains(c) { pop.mouseMoved(CGPoint(x: c.x - pop.frame.minX, y: c.y - pop.frame.minY)); pop.dirty = true }
        }
    }

    func mouseUp(_ p: CGPoint) {
        mouse = p
        let c = cursorPoint
        switch target {
        case .popup, .menubar, .none:
            if let pop = popup, pop.frame.contains(c) {
                pop.mouseUp(CGPoint(x: c.x - pop.frame.minX, y: c.y - pop.frame.minY))
                popup?.dirty = true
            }
        case .window(let w):
            w.mouseUp(CGPoint(x: c.x - w.frame.minX, y: c.y - w.frame.minY))
        case .desktop:
            desktop.mouseUp(c)
        case .drag: break
        }
        target = .none
    }

    func scroll(dy: CGFloat) {
        let c = cursorPoint
        for w in windows.reversed() where !w.isMinimized && w.frame.contains(c) {
            w.scroll(dy)
            return
        }
    }

    func keyDown(_ k: KeyInput) {
        if phase == .boot { return }
        if endCard != nil && endCardAlpha > 0.5 {
            if endCardGood { endCard = nil } else { restart() }
            return
        }
        if phase == .panic { return }
        if k.isEscape && popup != nil { closePopup(); return }

        let ch = k.chars.lowercased()
        let modal = windows.last { $0.isModal && !$0.closing }
        if let m = modal { _ = m.keyDown(k); return }

        if k.cmd {
            if k.shift && (ch == "." || ch == ">") { toggleHidden(); return }
            if k.shift && k.isBackspace { story.requestEmptyTrash(); return }
            if k.shift && ch == "d" { openFinder(fs.desktop); return }
            if k.shift && ch == "h" { openFinder(fs.home); return }
            if k.shift && ch == "o" { openFinder(fs.documents); return }
            if k.option && ch == "l" { openFinder(fs.downloads); return }
            if k.option && k.keyCode == 53 { launch(.activity); return }
            if !k.shift && ch == "w" { if let w = keyWindow { close(w) }; return }
            if !k.shift && ch == "m" { minimizeKey(); return }
            if !k.shift && ch == "n" && !(keyWindow is TerminalWindow) { openFinder(fs.home); return }
            if !k.shift && ch == "n", keyWindow is TerminalWindow { launch(.terminal); return }
            if !k.shift && ch == "o" && keyWindow == nil { openSelectedDesktopItem(); return }
            if ch == " " { story.ambientWhisper("you won't find her by searching."); return }
        }
        if let w = keyWindow, w.isKey {
            if w.keyDown(k) { return }
        } else if k.isReturn || (k.cmd && k.isDown) {
            openSelectedDesktopItem()
            return
        }
        if k.cmd { audio.beep() }
    }
}

// MARK: - Dev scenes (FAKEOS_SCENE=windows|dark|chat|ending) for screenshot checks
extension World {
    func debugScene(_ s: String) {
        switch s {
        case "windows":
            showHidden = true
            let f = FinderWindow(world: self, folder: fs.wrenFolder)
            open(f)
            let t = TerminalWindow(world: self)
            open(t)
            t.frame.origin = CGPoint(x: 700, y: 380)
            t.ghostType("ps\n")
            open(ActivityMonitorWindow(world: self))
            alert(icon: nil, symbol: "lock.fill", heading: "“heart.lock” is locked.", message: "Enter the password to unlock it.",
                  buttons: ["Cancel", "Unlock"], field: true)
        case "dark":
            menuBar.openRight = "cc"
            popup = ControlCenterPopup(world: self, at: CGPoint(x: size.width - 330, y: menuBar.height + 4))
            setBrightness(0.05)
        case "chat":
            story.stage = .sawGlow
            setBrightness(1)
            openFinder(fs.trash)
            after(2) { self.openWifiMenu() }
        case "ending":
            story.stage = .unlocked
            story.wrenRunning = false
            story.openLocked(fs.soul)
        default: break
        }
    }
}
