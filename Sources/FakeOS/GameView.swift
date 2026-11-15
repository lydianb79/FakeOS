import AppKit
import MetalKit

/// Keyboard input in a form the fake OS understands.
struct KeyInput {
    let chars: String
    let keyCode: UInt16
    let cmd: Bool
    let shift: Bool
    let option: Bool
    let control: Bool

    var isReturn: Bool { keyCode == 36 || keyCode == 76 }
    var isBackspace: Bool { keyCode == 51 }
    var isEscape: Bool { keyCode == 53 }
    var isTab: Bool { keyCode == 48 }
    var isUp: Bool { keyCode == 126 }
    var isDown: Bool { keyCode == 125 }
    var isLeft: Bool { keyCode == 123 }
    var isRight: Bool { keyCode == 124 }
    /// Printable text (empty for control keys).
    var text: String {
        if cmd || control || isReturn || isBackspace || isEscape || isTab || isUp || isDown || isLeft || isRight { return "" }
        return chars.filter { !$0.isNewline && ($0.unicodeScalars.first.map { $0.value >= 32 && $0.value != 127 && !(0xF700...0xF8FF).contains($0.value) } ?? false) }
    }
}

final class GameView: MTKView {
    var renderer: Renderer!
    var world: World!
    private var lastTime = CACurrentMediaTime()
    private var cursorHidden = false

    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        preferredFramesPerSecond = 60
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        renderer = Renderer(device: device!)
        world = World(renderer: renderer, size: frame.size, scale: 2)
        delegate = self
    }

    required init(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.backingScaleFactor ?? 2
        world.resize(size: bounds.size, scale: scale)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    private func point(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    private func hideCursor() { if !cursorHidden { NSCursor.hide(); cursorHidden = true } }
    private func showCursor() { if cursorHidden { NSCursor.unhide(); cursorHidden = false } }

    override func mouseEntered(with event: NSEvent) { hideCursor(); world.mouseMoved(point(event)) }
    override func mouseExited(with event: NSEvent) { showCursor() }
    override func mouseMoved(with event: NSEvent) { hideCursor(); world.mouseMoved(point(event)) }
    override func mouseDown(with event: NSEvent) {
        hideCursor()
        world.mouseDown(point(event), clicks: event.clickCount, right: event.modifierFlags.contains(.control))
    }
    override func mouseDragged(with event: NSEvent) { world.mouseDragged(point(event)) }
    override func mouseUp(with event: NSEvent) { world.mouseUp(point(event)) }
    override func rightMouseDown(with event: NSEvent) { world.mouseDown(point(event), clicks: 1, right: true) }
    override func scrollWheel(with event: NSEvent) {
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
        world.scroll(dy: dy)
    }

    private func keyInput(_ e: NSEvent) -> KeyInput {
        let f = e.modifierFlags
        return KeyInput(chars: e.characters ?? "", keyCode: e.keyCode,
                        cmd: f.contains(.command), shift: f.contains(.shift),
                        option: f.contains(.option), control: f.contains(.control))
    }

    override func keyDown(with event: NSEvent) {
        let k = keyInput(event)
        if k.cmd, event.charactersIgnoringModifiers?.lowercased() == "q" {
            NSApp.terminate(nil)
            return
        }
        world.keyDown(KeyInput(chars: k.cmd ? (event.charactersIgnoringModifiers ?? "") : k.chars,
                               keyCode: k.keyCode, cmd: k.cmd, shift: k.shift, option: k.option, control: k.control))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.modifierFlags.contains(.command) else { return false }
        keyDown(with: event)
        return true
    }
}

extension GameView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        world.resize(size: bounds.size, scale: window?.backingScaleFactor ?? 2)
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = min(Float(now - lastTime), 1.0 / 20.0)
        lastTime = now
        world.update(dt: dt)
        renderer.render(world: world, in: self)
    }
}
