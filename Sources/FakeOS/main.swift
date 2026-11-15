import AppKit

// Fake OS — a haunted fake desktop.
// Run fullscreen by default. Pass --windowed for a 1440x900 window (handy for development).
// ⌘Q always quits the real game.

if let i = CommandLine.arguments.firstIndex(of: "--export-icon"), i + 1 < CommandLine.arguments.count {
    // Dev/build helper: write AppIcon.iconset PNGs and exit.
    let dir = CommandLine.arguments[i + 1]
    try AppIconArt.exportIconset(to: dir)
    if let png = CommandLine.arguments.firstIndex(of: "--preview").map({ CommandLine.arguments[$0 + 1] }) {
        try AppIconArt.png(pixels: 1024).write(to: URL(fileURLWithPath: png))
    }
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--render-audio"), i + 1 < CommandLine.arguments.count {
    // Dev helper: renders every sound offline to a WAV for checking levels.
    renderAudioTest(to: CommandLine.arguments[i + 1])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
