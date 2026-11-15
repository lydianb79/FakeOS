import AppKit

/// A fake window. Painted into its own canvas; the World moves it around as a textured quad.
class FakeWindow {
    unowned let world: World
    var frame: CGRect
    var title: String { didSet { setNeedsDisplay() } }
    let app: AppKind
    private(set) var canvas: Canvas
    var needsDisplay = true
    var isKey = false { didSet { if oldValue != isKey { setNeedsDisplay() } } }
    var isMinimized = false
    var appear: Float = 0
    var closing = false
    var hoverLights = false { didSet { if oldValue != hoverLights { setNeedsDisplay() } } }
    var shake: Float = 0
    var titleOverride: String? { didSet { setNeedsDisplay() } }

    var titleBarHeight: CGFloat { 28 }
    var cornerRadius: CGFloat { 10 }
    var isModal: Bool { false }
    var showsTrafficLights: Bool { true }
    var trafficLightY: CGFloat { 14 }
    var backgroundColor: NSColor { .white }

    init(world: World, size: CGSize, title: String, app: AppKind, origin: CGPoint? = nil) {
        self.world = world
        self.title = title
        self.app = app
        let o = origin ?? world.nextWindowOrigin(for: size)
        frame = CGRect(origin: o, size: size)
        canvas = Canvas(size: size, scale: world.scale)
    }

    func setNeedsDisplay() { needsDisplay = true }

    func redrawIfNeeded() {
        guard needsDisplay else { return }
        needsDisplay = false
        canvas.draw { ctx in self.drawWindow(ctx) }
    }

    func drawWindow(_ ctx: CGContext) {
        let b = CGRect(origin: .zero, size: frame.size)
        Draw.fill(ctx, b, backgroundColor)
        drawContent(ctx)
        drawTitleBar(ctx)
        Draw.stroke(ctx, b.insetBy(dx: 0.25, dy: 0.25), NSColor(white: 0, alpha: 0.22), radius: cornerRadius, width: 0.5)
    }

    func drawTitleBar(_ ctx: CGContext) {
        let tb = CGRect(x: 0, y: 0, width: frame.width, height: titleBarHeight)
        Draw.fill(ctx, tb, isKey ? Draw.hex(0xECECEC) : Draw.hex(0xF6F6F6))
        Draw.line(ctx, CGPoint(x: 0, y: tb.maxY - 0.25), CGPoint(x: tb.maxX, y: tb.maxY - 0.25), NSColor(white: 0, alpha: 0.12), width: 0.5)
        if showsTrafficLights { Draw.trafficLights(ctx, y: trafficLightY, active: isKey, hover: hoverLights) }
        let t = titleOverride ?? title
        Draw.text(t, in: CGRect(x: 80, y: (titleBarHeight - 16) / 2, width: frame.width - 160, height: 18),
                  font: Draw.font(13, .semibold), color: isKey ? NSColor(white: 0.25, alpha: 1) : NSColor(white: 0.6, alpha: 1),
                  align: .center, lineBreak: .byTruncatingMiddle)
    }

    func drawContent(_ ctx: CGContext) {}

    /// Which part of the window starts a drag.
    func isDragRegion(_ p: CGPoint) -> Bool { p.y < titleBarHeight }

    func mouseDown(_ p: CGPoint, clicks: Int) {}
    func mouseDragged(_ p: CGPoint) {}
    func mouseUp(_ p: CGPoint) {}
    func mouseMoved(_ p: CGPoint) {}
    func keyDown(_ k: KeyInput) -> Bool { false }
    func scroll(_ dy: CGFloat) {}
    func update(_ dt: Float) {}
    func willClose() {}

    var contentRect: CGRect { CGRect(x: 0, y: titleBarHeight, width: frame.width, height: frame.height - titleBarHeight) }
}

// MARK: - TextEdit

class TextEditWindow: FakeWindow {
    var text: String
    var scrollY: CGFloat = 0
    let docFont = NSFont(name: "Helvetica", size: 13) ?? Draw.font(13)
    let node: FSNode?

    init(world: World, title: String, text: String, node: FSNode?, size: CGSize = CGSize(width: 560, height: 440), origin: CGPoint? = nil) {
        self.text = text
        self.node = node
        super.init(world: world, size: size, title: title, app: .textEdit, origin: origin)
    }

    var textInset: CGFloat { 22 }

    func attributed() -> NSAttributedString {
        NSAttributedString(string: text, attributes: Draw.attrs(docFont, .black, lineSpacing: 3))
    }

    override func drawContent(_ ctx: CGContext) {
        let c = contentRect
        let s = attributed()
        let w = c.width - textInset * 2
        let h = ceil(s.boundingRect(with: CGSize(width: w, height: 100000), options: [.usesLineFragmentOrigin]).height)
        let maxScroll = max(0, h + textInset * 2 - c.height)
        scrollY = min(max(0, scrollY), maxScroll)
        ctx.saveGState()
        ctx.clip(to: c)
        s.draw(with: CGRect(x: textInset, y: c.minY + textInset - scrollY, width: w, height: h + 40), options: [.usesLineFragmentOrigin])
        ctx.restoreGState()
        if maxScroll > 0 {
            let barH = max(30, c.height * c.height / (h + textInset * 2))
            let y = c.minY + (c.height - barH) * (scrollY / maxScroll)
            Draw.fill(ctx, CGRect(x: c.maxX - 9, y: y + 2, width: 6, height: barH - 4), NSColor(white: 0, alpha: 0.3), radius: 3)
        }
    }

    override func scroll(_ dy: CGFloat) {
        scrollY -= dy
        setNeedsDisplay()
    }
}

/// The TextEdit window wren opens by itself. It types, and it answers.
final class GhostChatWindow: TextEditWindow {
    private var segments: [(String, Bool)] = []   // (text, isGhost)
    private var pending: [Character] = []
    private var typeTimer: Float = 0
    private var input = ""
    private var caretTimer: Float = 0
    private var caretOn = true
    private var replyDelay: Float = -1
    private var queuedReply: String?
    var onFinishedTyping: (() -> Void)?

    init(world: World) {
        super.init(world: world, title: "Untitled", text: "", node: nil, size: CGSize(width: 520, height: 360),
                   origin: CGPoint(x: world.size.width * 0.5 - 360, y: world.size.height * 0.32))
    }

    var isTyping: Bool { !pending.isEmpty || queuedReply != nil }

    func ghostSay(_ s: String) {
        if !segments.isEmpty || !pending.isEmpty { pending.append(contentsOf: "\n\n") }
        pending.append(contentsOf: s)
    }

    override func attributed() -> NSAttributedString {
        let out = NSMutableAttributedString()
        let ghostColor = Draw.hex(0x5A0A10)
        for (t, ghost) in segments {
            out.append(NSAttributedString(string: t, attributes: Draw.attrs(docFont, ghost ? ghostColor : .black, lineSpacing: 3)))
        }
        if !input.isEmpty || !isTyping {
            out.append(NSAttributedString(string: input, attributes: Draw.attrs(docFont, .black, lineSpacing: 3)))
        }
        out.append(NSAttributedString(string: "▏", attributes: Draw.attrs(docFont, caretOn && isKey ? .black : .clear, lineSpacing: 3)))
        return out
    }

    private func appendChar(_ c: Character, ghost: Bool) {
        if let last = segments.last, last.1 == ghost {
            segments[segments.count - 1].0.append(c)
        } else {
            segments.append((String(c), ghost))
        }
    }

    override func drawContent(_ ctx: CGContext) {
        // keep the newest text in view
        let c = contentRect
        let h = ceil(attributed().boundingRect(with: CGSize(width: c.width - textInset * 2, height: 100000), options: [.usesLineFragmentOrigin]).height)
        scrollY = max(0, h + textInset * 2 - c.height)
        super.drawContent(ctx)
    }

    override func update(_ dt: Float) {
        caretTimer += dt
        if caretTimer > 0.53 { caretTimer = 0; caretOn.toggle(); setNeedsDisplay() }
        if !pending.isEmpty {
            typeTimer -= dt
            while typeTimer <= 0, !pending.isEmpty {
                let ch = pending.removeFirst()
                appendChar(ch, ghost: true)
                typeTimer += ch == "." || ch == "\n" ? Float.random(in: 0.18...0.45) : Float.random(in: 0.03...0.11)
                world.audio.tick()
                setNeedsDisplay()
                if pending.isEmpty { onFinishedTyping?(); onFinishedTyping = nil }
            }
        } else if let r = queuedReply {
            replyDelay -= dt
            if replyDelay <= 0 {
                queuedReply = nil
                ghostSay(r)
            }
        }
    }

    override func keyDown(_ k: KeyInput) -> Bool {
        if k.cmd { return false }
        if isTyping { world.audio.beep(); return true }
        if k.isReturn {
            let msg = input.trimmingCharacters(in: .whitespaces)
            if !msg.isEmpty {
                segments.append(("\n\n" + input, false))
                input = ""
                queuedReply = world.story.ghostReply(to: msg)
                replyDelay = Float.random(in: 0.8...1.6)
            }
        } else if k.isBackspace {
            if !input.isEmpty { input.removeLast() }
        } else if !k.text.isEmpty {
            input += k.text
        }
        caretOn = true
        caretTimer = 0
        setNeedsDisplay()
        return true
    }

    override func willClose() { world.story.ghostChatClosed() }
}

// MARK: - Preview

final class PreviewWindow: FakeWindow {
    let picture: String
    override var titleBarHeight: CGFloat { 52 }
    override var trafficLightY: CGFloat { 26 }
    override var backgroundColor: NSColor { Draw.hex(0x2B2B2D) }

    init(world: World, name: String, picture: String) {
        self.picture = picture
        super.init(world: world, size: CGSize(width: 640, height: 532), title: name, app: .preview)
    }

    override func drawTitleBar(_ ctx: CGContext) {
        let tb = CGRect(x: 0, y: 0, width: frame.width, height: titleBarHeight)
        Draw.fill(ctx, tb, isKey ? Draw.hex(0xE8E8E8) : Draw.hex(0xF4F4F4))
        Draw.line(ctx, CGPoint(x: 0, y: tb.maxY - 0.25), CGPoint(x: tb.maxX, y: tb.maxY - 0.25), NSColor(white: 0, alpha: 0.15), width: 0.5)
        Draw.trafficLights(ctx, y: trafficLightY, active: isKey, hover: hoverLights)
        Draw.text(titleOverride ?? title, in: CGRect(x: 90, y: 10, width: frame.width - 260, height: 18),
                  font: Draw.font(13, .bold), color: NSColor(white: 0.2, alpha: 1), lineBreak: .byTruncatingMiddle)
        Draw.text("1440 × 1080", at: CGPoint(x: 90, y: 28), font: Draw.font(11), color: Draw.secondary)
        let icons = ["info.circle", "magnifyingglass", "square.and.arrow.up", "pencil.tip.crop.circle", "rotate.left"]
        for (i, s) in icons.enumerated() {
            Draw.symbol(s, in: CGRect(x: frame.width - 34 - CGFloat(i) * 34, y: 17, width: 18, height: 18), color: NSColor(white: 0.35, alpha: 1))
        }
    }

    override func drawContent(_ ctx: CGContext) {
        let c = contentRect.insetBy(dx: 16, dy: 16)
        let aspect: CGFloat = 4.0 / 3.0
        var w = c.width, h = w / aspect
        if h > c.height { h = c.height; w = h * aspect }
        let r = CGRect(x: c.midX - w / 2, y: c.midY - h / 2, width: w, height: h)
        ctx.saveGState()
        ctx.clip(to: r)
        Pictures.draw(picture, in: r, ctx: ctx)
        ctx.restoreGState()
    }
}

// MARK: - About This Mac

final class AboutWindow: FakeWindow {
    override var titleBarHeight: CGFloat { 28 }
    init(world: World) {
        super.init(world: world, size: CGSize(width: 290, height: 430), title: "", app: .finder,
                   origin: CGPoint(x: world.size.width / 2 - 145, y: world.size.height / 2 - 250))
    }
    override func drawTitleBar(_ ctx: CGContext) {
        Draw.trafficLights(ctx, y: 14, active: isKey, hover: hoverLights)
    }
    override var backgroundColor: NSColor { Draw.hex(0xF2F2F2) }
    override func isDragRegion(_ p: CGPoint) -> Bool { true }

    override func drawContent(_ ctx: CGContext) {
        let w = frame.width
        Draw.symbol("laptopcomputer", in: CGRect(x: w / 2 - 70, y: 40, width: 140, height: 96), color: NSColor(white: 0.3, alpha: 1))
        Draw.text("MacBook Pro", in: CGRect(x: 0, y: 150, width: w, height: 30), font: Draw.font(22, .bold), color: Draw.label, align: .center)
        Draw.text("14-inch, Nov 2026", in: CGRect(x: 0, y: 180, width: w, height: 18), font: Draw.font(11), color: Draw.secondary, align: .center)
        let rows: [(String, String)] = [
            ("Chip", "Hollow M4"),
            ("Memory", "16 GB (11 GB used by wren)"),
            ("Startup disk", "Macintosh HD"),
            ("Serial number", "W7R3N-1313-0317"),
            ("macOS", "Hollow 15.3.17"),
            ("Uptime", "3:17 since Nov 13"),
        ]
        var y: CGFloat = 220
        for (k, v) in rows {
            Draw.text(k, in: CGRect(x: 0, y: y, width: w / 2 - 6, height: 16), font: Draw.font(11, .medium), color: Draw.label, align: .right)
            Draw.text(v, in: CGRect(x: w / 2 + 2, y: y, width: w / 2 - 14, height: 30), font: Draw.font(11), color: Draw.secondary)
            y += k == "Memory" ? 32 : 20
        }
        let b = CGRect(x: w / 2 - 50, y: 375, width: 100, height: 24)
        Draw.fill(ctx, b, .white, radius: 6)
        Draw.stroke(ctx, b, NSColor(white: 0, alpha: 0.15), radius: 6, width: 0.5)
        Draw.text("More Info…", in: b.offsetBy(dx: 0, dy: 4), font: Draw.font(12), color: Draw.label, align: .center)
    }

    override func mouseDown(_ p: CGPoint, clicks: Int) {
        if CGRect(x: frame.width / 2 - 50, y: 375, width: 100, height: 24).contains(p) {
            world.glitch(0.5)
            world.notify(.wren, "wren", "there is no more info. there is only me.")
        }
    }
}

// MARK: - Alerts

final class AlertWindow: FakeWindow {
    let icon: AppKind?
    let symbol: String?
    let heading: String
    let message: String
    let buttons: [String]
    let hasField: Bool
    var field = ""
    var onButton: ((Int, String) -> Bool)?   // return false to keep the alert open
    private var caretTimer: Float = 0
    private var caretOn = true
    private var shakeT: Float = 0

    override var isModal: Bool { true }
    override var showsTrafficLights: Bool { false }
    override var titleBarHeight: CGFloat { 0 }
    override var cornerRadius: CGFloat { 12 }
    override var backgroundColor: NSColor { Draw.hex(0xEDEDED) }

    init(world: World, icon: AppKind?, symbol: String? = nil, heading: String, message: String,
         buttons: [String], field: Bool = false) {
        self.icon = icon
        self.symbol = symbol
        self.heading = heading
        self.message = message
        self.buttons = buttons
        self.hasField = field
        let w: CGFloat = 260
        let mh = Draw.textHeight(message, width: w - 32, font: Draw.font(11))
        let hh = Draw.textHeight(heading, width: w - 32, font: Draw.font(13, .bold))
        let h = 20 + 64 + 14 + hh + 6 + mh + (field ? 38 : 0) + 20 + 28 + 16
        super.init(world: world, size: CGSize(width: w, height: h), title: "", app: icon ?? .finder,
                   origin: CGPoint(x: world.size.width / 2 - w / 2, y: world.size.height * 0.36 - h / 2))
    }

    override func isDragRegion(_ p: CGPoint) -> Bool { buttonIndex(at: p) == nil }
    override func drawTitleBar(_ ctx: CGContext) {}

    private func buttonRects() -> [CGRect] {
        let n = CGFloat(buttons.count)
        let gap: CGFloat = 8
        let w = (frame.width - 32 - gap * (n - 1)) / n
        return (0..<buttons.count).map { i in
            CGRect(x: 16 + CGFloat(i) * (w + gap), y: frame.height - 16 - 28, width: w, height: 28)
        }
    }

    private func buttonIndex(at p: CGPoint) -> Int? { buttonRects().firstIndex { $0.contains(p) } }

    override func drawContent(_ ctx: CGContext) {
        let w = frame.width
        let iconRect = CGRect(x: w / 2 - 32, y: 20, width: 64, height: 64)
        if let s = symbol {
            Draw.symbol(s, in: iconRect.insetBy(dx: 6, dy: 6), color: Draw.hex(0xF5B400))
        } else if let i = icon {
            Icons.app(i, in: iconRect, ctx: ctx)
        }
        var y: CGFloat = 98
        let hh = Draw.textHeight(heading, width: w - 32, font: Draw.font(13, .bold))
        Draw.text(heading, in: CGRect(x: 16, y: y, width: w - 32, height: hh + 4), font: Draw.font(13, .bold), color: Draw.label, align: .center)
        y += hh + 6
        let mh = Draw.textHeight(message, width: w - 32, font: Draw.font(11))
        Draw.text(message, in: CGRect(x: 16, y: y, width: w - 32, height: mh + 4), font: Draw.font(11), color: Draw.label, align: .center)
        y += mh + 12
        if hasField {
            let f = CGRect(x: 16, y: y, width: w - 32, height: 24)
            Draw.fill(ctx, f, .white, radius: 5)
            Draw.stroke(ctx, f.insetBy(dx: -1.5, dy: -1.5), Draw.accent.withAlphaComponent(0.55), radius: 6.5, width: 3)
            let dots = String(repeating: "•", count: field.count)
            let sz = Draw.text(dots, at: CGPoint(x: f.minX + 7, y: f.minY + 3), font: Draw.font(14), color: Draw.label)
            if caretOn { Draw.fill(ctx, CGRect(x: f.minX + 8 + sz.width, y: f.minY + 5, width: 1.2, height: 14), Draw.label) }
            if field.isEmpty {
                Draw.text("Password", at: CGPoint(x: f.minX + 9, y: f.minY + 4), font: Draw.font(13), color: NSColor(white: 0.7, alpha: 1))
            }
        }
        for (i, r) in buttonRects().enumerated() {
            let isDefault = i == buttons.count - 1
            if isDefault {
                Draw.gradient(ctx, r, Draw.hex(0x3A95FF), Draw.hex(0x0A6CFF), radius: 6)
            } else {
                Draw.fill(ctx, r, .white, radius: 6)
                Draw.stroke(ctx, r, NSColor(white: 0, alpha: 0.12), radius: 6, width: 0.5)
            }
            Draw.text(buttons[i], in: r.offsetBy(dx: 0, dy: 6), font: Draw.font(13, isDefault ? .medium : .regular),
                      color: isDefault ? .white : Draw.label, align: .center)
        }
    }

    func wrong() {
        shakeT = 0.45
        field = ""
        world.audio.systemSound("Basso")
        setNeedsDisplay()
    }

    override func update(_ dt: Float) {
        if hasField {
            caretTimer += dt
            if caretTimer > 0.53 { caretTimer = 0; caretOn.toggle(); setNeedsDisplay() }
        }
        if shakeT > 0 {
            shakeT -= dt
            shake = sin(shakeT * 60) * 9 * (shakeT / 0.45)
        } else {
            shake = 0
        }
    }

    override func mouseDown(_ p: CGPoint, clicks: Int) {
        if let i = buttonIndex(at: p) { press(i) }
    }

    private func press(_ i: Int) {
        let shouldClose = onButton?(i, field) ?? true
        if shouldClose { world.close(self) }
    }

    override func keyDown(_ k: KeyInput) -> Bool {
        if k.isReturn { press(buttons.count - 1); return true }
        if k.isEscape, buttons.count > 1 { press(0); return true }
        if hasField {
            if k.isBackspace { if !field.isEmpty { field.removeLast() } }
            else if !k.cmd && !k.text.isEmpty && field.count < 24 { field += k.text }
            caretOn = true
            caretTimer = 0
            setNeedsDisplay()
        }
        return true
    }
}
