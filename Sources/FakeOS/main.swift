import AppKit

// Fake OS — a haunted fake desktop.
// Run fullscreen by default. Pass --windowed for a 1440x900 window (handy for development).
// ⌘Q always quits the real game.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
