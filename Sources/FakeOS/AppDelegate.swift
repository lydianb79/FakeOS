import AppKit
import MetalKit

final class GameWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: GameWindow!
    var view: GameView!
    let windowed = CommandLine.arguments.contains("--windowed")

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not available on this Mac.")
        }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame: NSRect
        if windowed {
            let size = NSSize(width: 1440, height: 900)
            frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                           width: size.width, height: size.height)
            window = GameWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable],
                                backing: .buffered, defer: false)
            window.title = "Fake OS"
        } else {
            frame = screen.frame
            window = GameWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .normal
            window.collectionBehavior = [.fullScreenPrimary]
        }
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black

        view = GameView(frame: NSRect(origin: .zero, size: frame.size), device: device)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)

        if !windowed {
            NSApp.presentationOptions = [.hideDock, .hideMenuBar]
            window.setFrame(screen.frame, display: true)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidBecomeActive(_ notification: Notification) {
        if !windowed { NSApp.presentationOptions = [.hideDock, .hideMenuBar] }
    }
}
