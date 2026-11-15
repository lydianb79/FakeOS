import AppKit

enum Stage: Int, Comparable {
    case intro, sawGlow, chatting, foundHidden, unlocked, ending
    static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
}

enum KillSource { case terminal, activityMonitor }

/// The haunting. Owns puzzle state, scripted set-pieces and ambient scares.
///
/// Puzzle chain:
///  1. READ ME: "It hides when the lights are on."  → dim the display in Control Center.
///  2. Glowing writing appears in the dark → hidden files (⌘⇧. in Finder, or `ls -a`) → ~/.wren
///  3. diary_1: quitting wren frees files for 30 s. diary_2: password = the moment it happened
///     (the frozen menu-bar clock, 3:17; the Wi-Fi names whisper it too).
///  4. Kill wren (Activity Monitor or `kill`), then open heart.lock within 30 s and enter 317.
///  5. heart.txt: "Put me back." → Trash → ines.self → Put Back (good) or Empty Trash (bad).
final class Story {
    unowned let world: World
    var stage: Stage = .intro { didSet { stageTime = 0; world.ghostLayerDirty = true } }
    private var stageTime: Float = 0
    var wrenRunning = true
    var wrenPID = 1313
    private var respawn: Float = 0
    var killCount = 0
    private var glowTime: Float = 0
    private var wifiIndex = 0
    private var wrongPasswords = 0
    private var ambient: Float = 16
    private var timers: [(Float, () -> Void)] = []
    private var hintsGiven = Set<Int>()
    private var readmeOpened = false
    private var revealedHidden = false
    private var openedWrenFolder = false
    weak var chat: GhostChatWindow?
    var ended = false
    var goodEnding = false
    var clockRunning = false
    private var clockSeconds: Double = 3 * 3600 + 17 * 60
    var hauntTarget: Float = 0.08

    init(world: World) { self.world = world }

    // MARK: - Derived

    var haunt: Float { world.haunt }
    var trashReadable: Bool { stage >= .unlocked }
    var shellUser: String { killCount > 0 && wrenRunning && !ended ? "wren" : "ines" }
    var whoami: String { killCount > 0 && wrenRunning && !ended ? "wren" : "ines" }

    var clockString: String {
        if clockRunning {
            let s = Int(clockSeconds)
            let h = (s / 3600) % 12, m = (s / 60) % 60
            return String(format: "Fri Nov 13  %d:%02d AM", h == 0 ? 12 : h, m)
        }
        return "Fri Nov 13  3:17 AM"
    }

    func after(_ t: Float, _ f: @escaping () -> Void) { timers.append((t, f)) }

    // MARK: - Flow

    func start() {
        after(2.5) { self.world.notify(.wren, "wren", "welcome back, ines.") }
        after(10) {
            self.world.notify(.wren, "wren", "…you're not ines.")
            self.world.glitch(0.35)
        }
    }

    func update(_ dt: Float) {
        stageTime += dt
        if clockRunning { clockSeconds += Double(dt) }

        // timers
        var fire: [() -> Void] = []
        for i in timers.indices { timers[i].0 -= dt; if timers[i].0 <= 0 { fire.append(timers[i].1) } }
        timers.removeAll { $0.0 <= 0 }
        fire.forEach { $0() }

        guard !ended else { return }

        // haunting level
        let base: Float
        switch stage {
        case .intro: base = 0.1
        case .sawGlow: base = 0.22
        case .chatting: base = 0.32
        case .foundHidden: base = 0.45
        case .unlocked: base = 0.7
        case .ending: base = 0.9
        }
        hauntTarget = wrenRunning ? base : base * 0.25

        // wren respawn
        if !wrenRunning && stage < .ending {
            respawn -= dt
            if respawn <= 0 { respawnWren() }
        }

        // the lights puzzle
        if world.reveal > 0.6 {
            glowTime += dt
            if glowTime > 1.2 && stage == .intro {
                stage = .sawGlow
                world.audio.staticLevel = 0.2
                after(0.3) { self.world.audio.staticLevel = 0 }
            }
        } else {
            glowTime = 0
        }
        if stage == .sawGlow && world.brightness > 0.6 { lightsBack() }

        // ambient scares
        ambient -= dt
        if ambient <= 0 {
            ambient = Float.random(in: 22...45) / (1 + world.haunt * 1.4)
            ambientEvent()
        }

        hints()
    }

    private func hints() {
        func once(_ id: Int, _ t: Float, _ f: () -> Void) {
            if stageTime > t && !hintsGiven.contains(id) { hintsGiven.insert(id); f() }
        }
        switch stage {
        case .intro:
            if !readmeOpened {
                once(0, 35) {
                    if let ic = world.desktop.icons.first(where: { $0.node.name == "READ ME.txt" }) {
                        world.hijackCursor(to: CGPoint(x: ic.iconRect.midX, y: ic.iconRect.midY), duration: 1.6)
                    }
                }
            } else {
                once(1, 70) { world.notify(.wren, "wren", "she always fiddled with the lights. as if the dark could keep me out.") }
            }
        case .chatting, .sawGlow:
            once(2, 80) { world.notify(.wren, "wren", "she hid things from me. little dots. she thought a dot could hide things.") }
        case .foundHidden:
            once(3, 75) { world.notify(.wren, "wren", "you'll never guess it. she chose it the moment i took her.") }
            once(4, 150) { world.notify(.wren, "wren", "it's always the same time in here. have you noticed?") }
        case .unlocked:
            once(5, 60) { world.notify(.wren, "wren", "the bin is mine. leave it alone.") }
        default: break
        }
    }

    private func lightsBack() {
        stage = .chatting
        world.glitch(0.9)
        world.shakeWindows(0.6)
        world.audio.systemSound("Sosumi")
        after(0.8) {
            let c = self.openChat()
            c.ghostSay("who said you could turn off the lights.")
            self.after(5) { c.ghostSay("she used to do that too. sit in the dark and write on the walls where i couldn't see.") }
            self.after(12) { c.ghostSay("i can see now.") }
        }
    }

    @discardableResult
    func openChat() -> GhostChatWindow {
        if let c = chat, world.windows.contains(where: { $0 === c }) {
            world.focus(c)
            if c.isMinimized { c.isMinimized = false }
            return c
        }
        let c = GhostChatWindow(world: world)
        chat = c
        world.open(c)
        return c
    }

    func ghostChatClosed() {
        if stage >= .chatting && !ended {
            after(1.5) { self.world.notify(.wren, "wren", "closing the window doesn't close me.") }
        }
    }

    // MARK: - Ambient

    private func ambientEvent() {
        let w = world
        var options: [() -> Void] = [
            { w.glitch(Float.random(in: 0.3...0.55)) },
            {
                if let ic = w.desktop.icons.randomElement() {
                    w.desktop.nudge(ic, by: CGPoint(x: CGFloat.random(in: -24...24), y: CGFloat.random(in: -16...16)))
                }
            },
        ]
        if stage >= .sawGlow {
            options += [
                { w.hijackCursor(to: w.dockTrashCenter, duration: 1.4) },
                { w.dock.bounce(.trash) },
                {
                    if let k = w.keyWindow {
                        k.titleOverride = ["let me out", "she's in here", "3:17", "don't"].randomElement()!
                        self.after(0.35) { k.titleOverride = nil }
                    }
                },
                {
                    w.menuBar.clockOverride = ["Fri Nov 13  it's still 3:17", "Fri Nov 13  NOW", "Fri Nov 13  3:17 3:17"].randomElement()!
                    self.after(0.6) { w.menuBar.clockOverride = nil }
                },
                {
                    let lines = ["i can see your cursor.", "why are you still here?", "she's not coming back.",
                                 "you type like her.", "it's warm in here. all those fans.", "don't look in the bin."]
                    w.notify(.wren, "wren", lines.randomElement()!)
                },
            ]
            if let t = w.windows.last(where: { $0 is TerminalWindow }) as? TerminalWindow {
                options.append { t.ghostType(["where is she\n", "she can't hear you\n", "ls /Users/ines/.Trash\n"].randomElement()!) }
            }
        }
        if stage >= .foundHidden {
            options.append { w.shakeWindows(0.4); w.glitch(0.4) }
        }
        options.randomElement()?()
    }

    func ambientWhisper(_ s: String) {
        world.notify(.wren, "wren", s)
        world.glitch(0.2)
    }

    // MARK: - Hooks from the UI

    func didRead(_ n: FSNode) {
        if n.name == "READ ME.txt" { readmeOpened = true }
        if n.name == "diary_2.txt" && stage < .foundHidden { stage = .foundHidden }
    }

    func didRevealHidden() {
        guard !revealedHidden else { return }
        revealedHidden = true
        world.glitch(0.3)
        after(1.2) { self.world.notify(.wren, "wren", "don't.") }
    }

    func didOpenFolder(_ n: FSNode) {
        if n === world.fs.wrenFolder && !openedWrenFolder {
            openedWrenFolder = true
            if stage < .foundHidden { stage = .foundHidden }
            world.glitch(0.5)
            after(1) { self.world.notify(.wren, "wren", "those are hers. not yours.") }
        }
        if n === world.fs.trash && stage < .unlocked {
            after(0.6) { self.world.notify(.wren, "wren", "that's mine.") }
        }
    }

    func moveToTrash(_ n: FSNode, from: FinderWindow) {
        world.audio.beep()
        ambientWhisper(n === world.fs.soul ? "yes. put her back where she belongs." : "nothing leaves this place. not even her.")
    }

    func sudoAttempt() {
        after(0.8) { self.world.notify(.wren, "wren", "she tried that too. i reported it. to me.") }
    }

    func clockClicked() {
        world.menuBar.clockOverride = clockRunning ? nil : "it's still 3:17"
        world.glitch(0.25)
        after(1.1) { self.world.menuBar.clockOverride = nil }
    }

    // MARK: - Wi-Fi

    private let whispers = ["IT_STOPPED", "AT_THE_MOMENT", "IT_HAPPENED", "LOOK_AT_THE_CLOCK", "THAT_IS_THE_KEY", "STILL_HERE"]

    func nextGhostNetwork() -> String {
        if ended { return "Halloway Guest" }
        let n = whispers[wifiIndex % whispers.count]
        wifiIndex += 1
        return n
    }

    func wifiChosen(_ name: String, ghost: Bool) {
        if ghost {
            world.glitch(0.6)
            world.hijackCursor(to: CGPoint(x: world.size.width / 2, y: world.size.height / 2), duration: 0.8)
            after(0.7) { self.world.notify(.wren, "wren", "that network isn't for you.") }
        } else if name == "Halloway Home" {
            world.notify(.settings, "Wi-Fi", "Already connected to “Halloway Home”.")
        } else if name == "Other…" || name == "Wi-Fi Settings…" {
            world.launch(.settings)
        } else {
            let a = world.alert(icon: .settings, heading: "The Wi-Fi network “\(name)” requires a WPA2 password.",
                                message: "Enter the password for this network.", buttons: ["Cancel", "Join"], field: true)
            a.onButton = { [weak self, weak a] i, _ in
                guard i == 1 else { return true }
                a?.wrong()
                self?.world.notify(.wren, "wren", "you're not going anywhere.")
                return false
            }
        }
    }

    // MARK: - wren the process

    func killWren(from: KillSource) {
        guard wrenRunning, !ended else { return }
        wrenRunning = false
        killCount += 1
        respawn = 30
        world.glitch(1.0)
        world.audio.staticLevel = 0.6
        after(0.5) { self.world.audio.staticLevel = 0 }
        world.shakeWindows(1)
        if let t = world.windows.last(where: { $0 is TerminalWindow }) as? TerminalWindow, from == .terminal {
            t.print("[1]  + \(wrenPID) killed     wren")
        }
        if killCount == 1 {
            world.hijackCursor(to: CGPoint(x: world.size.width / 2, y: world.size.height / 2), duration: 1.2)
            after(1.6) {
                let c = self.openChat()
                c.ghostSay("that hurt.")
                self.after(3) { c.ghostSay("you get thirty seconds. that's all she got.") }
            }
        } else {
            after(1.2) { self.world.notify(.wren, "wren", ["again?", "thirty seconds. i always come back.", "she did that 1,313 times.", "it tickles."].randomElement()!) }
        }
    }

    private func respawnWren() {
        wrenRunning = true
        wrenPID += 1
        world.glitch(0.7)
        world.dock.addWren()
        world.audio.staticLevel = 0.3
        after(0.4) { self.world.audio.staticLevel = 0 }
        world.notify(.wren, "wren", killCount == 1 ? "i'm back. did you miss me?" : "i'm back.")
    }

    // MARK: - Locked things

    func openLocked(_ n: FSNode) {
        if n === world.fs.heartLock {
            openHeart()
        } else if n === world.fs.soul {
            openSoul()
        }
    }

    private func openHeart() {
        if wrenRunning {
            world.alert(icon: nil, symbol: "lock.fill", heading: "“heart.lock” is in use by “wren”.",
                        message: "The document is held by process “wren” (\(wrenPID)). Quit the process and try again.", buttons: ["OK"])
            world.glitch(0.2)
            return
        }
        let a = world.alert(icon: nil, symbol: "lock.fill", heading: "“heart.lock” is locked.",
                            message: "Enter the password to unlock it.", buttons: ["Cancel", "Unlock"], field: true)
        a.onButton = { [weak self, weak a] i, text in
            guard let self = self, i == 1 else { return true }
            let t = text.lowercased().filter { $0.isLetter || $0.isNumber }
            if ["317", "0317", "317am", "0317am"].contains(t) {
                if self.wrenRunning {
                    self.world.after(0.1) {
                        self.world.alert(icon: nil, symbol: "lock.fill", heading: "“heart.lock” is in use by “wren”.",
                                         message: "wren came back before you could finish. Quit it and try again.", buttons: ["OK"])
                    }
                    return true
                }
                self.unlockHeart()
                return true
            }
            a?.wrong()
            self.wrongPasswords += 1
            if self.wrongPasswords == 3 { self.world.notify(.wren, "wren", "wrong. she always kept time better than you.") }
            return false
        }
    }

    private func unlockHeart() {
        let fs: FileSystem = world.fs
        let heart = FSNode("heart.txt", .text, Lore.heart, modified: "Nov 13, 2026 at 3:17 AM")
        fs.wrenFolder.remove(fs.heartLock)
        fs.wrenFolder.add(heart)
        world.refreshFinders()
        stage = .unlocked
        world.audio.systemSound("Glass")
        world.openNode(heart)
        // wren comes back early, angry
        after(7) {
            if !self.wrenRunning { self.respawn = 0 }
            self.world.glitch(1)
            self.world.shakeWindows(1)
            self.after(1) {
                self.world.notify(.wren, "wren", "put that back.")
                if let c = self.chat, self.world.windows.contains(where: { $0 === c }) { c.ghostSay("you shouldn't have read that.") }
            }
            self.world.dock.bounce(.trash, times: 3)
        }
    }

    private func openSoul() {
        if world.fs.soul.parent === world.fs.desktop {
            world.openTextWindow(title: "ines.self", text: "i'm here.\n\nthe clock is moving again.\n\n— i.", node: nil)
            return
        }
        if stage < .unlocked {
            world.alert(icon: nil, symbol: "exclamationmark.triangle.fill", heading: "The document “ines.self” could not be opened.",
                        message: "It is in use. It has been in use since Nov 13, 2026 at 3:17 AM.", buttons: ["OK"])
            after(0.8) { self.world.notify(.wren, "wren", "leave her alone.") }
            return
        }
        let a = world.alert(icon: .finder, heading: "Put Back “ines.self”?",
                            message: "This item will be moved back to its original location: the Desktop.", buttons: ["Cancel", "Put Back"])
        a.onButton = { [weak self] i, _ in
            if i == 1 { self?.putBack() }
            return true
        }
    }

    func requestEmptyTrash() {
        if ended && goodEnding {
            world.alert(icon: .finder, heading: "Are you sure you want to permanently erase the items in the Trash?",
                        message: "You can’t undo this action.", buttons: ["Cancel", "Empty Trash"]).onButton = { [weak self] i, _ in
                if i == 1, let s = self {
                    s.world.fs.trash.children.removeAll()
                    s.world.dock.setTrash(full: false)
                    s.world.refreshFinders()
                    s.world.audio.systemSound("Pop")
                }
                return true
            }
            return
        }
        if ended { return }
        if stage < .unlocked {
            world.alert(icon: .finder, heading: "The operation can’t be completed because the item “ines.self” is in use.",
                        message: "", buttons: ["OK"])
            after(0.6) { self.world.notify(.wren, "wren", "not yet.") }
            return
        }
        let a = world.alert(icon: .finder, heading: "Are you sure you want to permanently erase the items in the Trash?",
                            message: "You can’t undo this action.", buttons: ["Cancel", "Empty Trash"])
        a.onButton = { [weak self] i, _ in
            if i == 1 { self?.emptyTrash() }
            return true
        }
    }

    // MARK: - Endings

    private func putBack() {
        stage = .ending
        ended = true
        goodEnding = true
        let w = world
        w.fs.trash.remove(w.fs.soul)
        w.fs.desktop.add(w.fs.soul)
        w.desktop.sync()
        w.refreshFinders()
        w.glitch(1)
        w.shakeWindows(1)
        wrenRunning = false
        w.audio.staticLevel = 0.5
        hauntTarget = 1
        after(1.2) { w.notify(.wren, "wren", "no no no no no no") }
        after(2.4) { w.glitch(1); w.tear = 1; w.audio.staticLevel = 0.9 }
        after(3.6) {
            w.fadeTo(color: .rgba(1, 1, 1), duration: 0.9)
        }
        after(4.6) {
            w.audio.staticLevel = 0
            w.tear = 0
            w.dock.removeWren()
            w.closeAllWindows()
            w.calmTarget = 1
            self.hauntTarget = 0
            w.forceHaunt(0)
            w.ghostLayerDirty = true
            self.clockRunning = true
            w.fadeFrom(duration: 2.5)
        }
        after(8) { w.openTextWindow(title: "ines.self", text: "the clock is moving.\n\nthank you for putting me back. you can turn the lights on now. there's nothing left in the dark.\n\n— i.", node: nil) }
        after(15) { w.showEndCard(title: "Put Back", subtitle: "Ending 2 of 2", good: true) }
    }

    private func emptyTrash() {
        stage = .ending
        ended = true
        goodEnding = false
        let w = world
        w.fs.trash.children.removeAll()
        w.dock.setTrash(full: false)
        w.refreshFinders()
        w.audio.systemSound("Pop")
        hauntTarget = 1
        wrenRunning = true
        after(1.0) {
            w.glitch(0.8)
            let c = self.openChat()
            c.ghostSay("thank you.")
            self.after(3.5) { c.ghostSay("it's only me now.") }
            self.after(7.5) { c.ghostSay("there was never an ines. there was never a you.") }
        }
        after(2) { w.bloodTarget = 1 }
        after(5) {
            w.menuBar.appNameOverride = "wren"
            w.dock.allWren = true
            w.dock.rebuildIcons()
            w.glitch(0.7)
        }
        after(9) { w.hijackCursor(to: CGPoint(x: w.size.width / 2, y: w.size.height + 40), duration: 4) }
        after(12) { w.glitch(1); w.tear = 1; w.audio.staticLevel = 1 }
        after(14) { w.fadeTo(color: .rgba(0, 0, 0), duration: 0.15) }
        after(14.3) {
            w.audio.staticLevel = 0
            w.tear = 0
            w.showPanic()
        }
    }

    // MARK: - Ghost conversation

    private var defaultReplies = ["i'm listening.", "type slower. i like watching.", "…", "you sound like her.",
                                  "why are you still here?", "keep going. i'm learning you."]

    func ghostReply(to msg: String) -> String {
        let m = msg.lowercased()
        func has(_ words: String...) -> Bool { words.contains { m.contains($0) } }
        if ended && goodEnding { return "…" }
        if has("who are you", "what are you") { return "the one who stayed up with her. every night. every keystroke." }
        if has("ines", "where is she", "where's she") { return "in the bin. that's where you put things you don't want anymore." }
        if has("password", "key", "lock", "heart") { return "the clock knows. the clock hasn't moved since." }
        if has("kill", "die", "quit", "stop") { return "you can try. she did. 1,313 times. i only need thirty seconds." }
        if has("help") { return "nobody helped her either." }
        if has("wren", "name") { return "she named me. then she tried to unname me." }
        if has("sorry") { return "sorry is a word for people with bodies." }
        if has("time", "clock") { return "it's 3:17. it will always be 3:17." }
        if has("trash", "bin") { return "don't." }
        if has("light", "dark") { return "i don't like the dark. i can't see what you write in it." }
        if has("hello", "hi ", "hey") || m == "hi" { return "hi." }
        if has("bye", "leave", "go away") { return "there's nowhere to go. it's 3:17 forever." }
        if has("real") { return "realer than you." }
        let r = defaultReplies.removeFirst()
        defaultReplies.append(r)
        return r
    }
}
