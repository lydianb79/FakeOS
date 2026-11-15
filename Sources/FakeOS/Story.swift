import AppKit
import AVFoundation

enum Stage: Int, Comparable {
    case intro, sawGlow, chatting, foundHidden, unlocked, ending
    static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
}

enum KillSource { case terminal, activityMonitor }

enum UnlockResult { case ok, wrong, busy }

/// The haunting. Owns the 50 puzzles (see Puzzles.swift), chapter unlocks, save data,
/// scripted set-pieces and ambient scares.
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
    var wrongPasswords = 0
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

    // puzzle state
    private(set) var solved = Set<Int>()
    var playTime: Double = 0
    private var sinceLastSolve: Float = 0
    private var dockSequence: [AppKind] = []
    private var clockTaps: [Float] = []
    private var time: Float = 0
    private let speech = AVSpeechSynthesizer()
    private var saveTimer: Float = 0
    static let saveKey = "fakeos.save.v1"

    init(world: World) { self.world = world }

    // MARK: - Derived

    var haunt: Float { world.haunt }
    var trashReadable: Bool { stage >= .unlocked }
    var shellUser: String { killCount > 0 && wrenRunning && !ended ? "wren" : "ines" }
    var whoami: String { killCount > 0 && wrenRunning && !ended ? "wren" : "ines" }
    var mimicAlive: Bool { chapter >= 2 && !solved.contains(10) && !ended }
    let mimicPID = 2811

    /// Highest chapter whose puzzles may be solved (all earlier chapters complete).
    var chapter: Int {
        var c = 1
        for (i, ch) in Puzzles.chapters.enumerated() where i < Puzzles.chapters.count - 1 {
            if ch.range.allSatisfy({ solved.contains($0) }) { c = i + 2 } else { break }
        }
        return c
    }

    var clockString: String {
        if clockRunning {
            let s = Int(clockSeconds)
            let h = (s / 3600) % 12, m = (s / 60) % 60
            return String(format: "Fri Nov 13  %d:%02d AM", h == 0 ? 12 : h, m)
        }
        return "Fri Nov 13  3:17 AM"
    }

    func after(_ t: Float, _ f: @escaping () -> Void) { timers.append((t, f)) }

    // MARK: - Puzzles

    /// Marks a puzzle solved if its chapter is open. Returns true when this call solved it.
    @discardableResult
    func solve(_ id: Int) -> Bool {
        guard !solved.contains(id), Puzzles.chapter(of: id) <= chapter, !(ended && id != 50) else { return false }
        let chapterBefore = chapter
        solved.insert(id)
        sinceLastSolve = 0
        let p = Puzzles.get(id)
        addMemory(p)
        save()
        world.audio.systemSound("Glass")
        world.notifyPiece(p, count: solved.count)
        if chapter > chapterBefore {
            let c = chapter
            after(3) { self.openChapter(c, announce: true) }
        }
        return true
    }

    func isSolved(_ id: Int) -> Bool { solved.contains(id) }

    private var recovered: FSNode {
        let fs: FileSystem = world.fs
        if let r = fs.desktop.child("Recovered") { return r }
        let r = FSNode("Recovered", .folder, modified: "Nov 13, 2026 at 3:17 AM")
        fs.desktop.add(r)
        world.desktop.sync()
        return r
    }

    private func addMemory(_ p: Puzzle) {
        let name = String(format: "%02d %@.txt", p.id, p.title)
        let r = recovered
        if r.child(name) == nil {
            r.add(FSNode(name, .text, "\(p.memory)\n\n— piece \(p.id) of 50", modified: "Nov 13, 2026 at 3:17 AM"))
        }
        updateIndex()
        world.refreshFinders()
    }

    private func updateIndex() {
        let r = recovered
        var s = "RECOVERED — \(solved.count) of \(Puzzles.total) pieces of Ines\n\n"
        let open = chapter
        for (i, ch) in Puzzles.chapters.enumerated() {
            s += "\(["I", "II", "III", "IV", "V", "VI"][i]). \(ch.title)\n"
            for id in ch.range {
                let mark = solved.contains(id) ? "✓" : "☐"
                let title = i + 1 <= open ? Puzzles.get(id).title : "???"
                s += String(format: "   %@ %02d  %@\n", mark, id, title)
            }
            s += "\n"
        }
        s += "Riddles for each part are in ~/.wren."
        if let idx = r.child("INDEX.txt") { idx.content = s } else { r.add(FSNode("INDEX.txt", .text, s)) }
    }

    /// Puts a chapter's files into the file system (idempotent).
    func openChapter(_ c: Int, announce: Bool) {
        let fs: FileSystem = world.fs
        guard c >= 2, c <= Puzzles.chapters.count else { return }
        let partName = "part \(c).txt"
        if fs.wrenFolder.child(partName) == nil {
            fs.wrenFolder.add(FSNode(partName, .text, Puzzles.partText(c), modified: "Nov 13, 2026 at 3:17 AM"))
        }
        func addLock(_ parent: FSNode, _ name: String, _ id: Int, _ answers: [String]) {
            guard !solved.contains(id), parent.child(name) == nil else { return }
            let n = FSNode(name, .lock, modified: "Nov 13, 2026 at 3:17 AM")
            n.lockID = id
            n.answers = answers
            parent.add(n)
        }
        switch c {
        case 2:
            addLock(fs.documents, "birthday.lock", 9, ["28", "1128", "2811", "nov28", "november28", "28nov", "28november", "28th"])
            addLock(fs.pictures, "beach.lock", 14, ["3", "three"])
        case 3:
            let archive: FSNode
            if let a = fs.documents.child("archive") { archive = a } else {
                archive = FSNode("archive", .folder, children: [
                    FSNode("note.b64", .text, "aSBhbSBzdGlsbCBoZXJlLiBpIGNhbiBoZWFyIHlvdSB0eXBpbmcu"),
                    FSNode("backwards.txt", .text, "eno daer ot elba eb t'nac ti .sdrawkcab etirw I"),
                    FSNode("wren.log", .text, Lore.wrenLog),
                ])
                fs.documents.add(archive)
            }
            addLock(archive, "echo.lock", 19, ["echo"])
        case 6:
            addLock(recovered, "final.lock", 46, ["50", "fifty"])
        default: break
        }
        world.refreshFinders()
        if announce {
            world.glitch(0.6)
            world.notify(.wren, "wren", ["fine. let's play.", "you keep finding her. stop.", "you're getting closer. i can feel it.",
                                         "she never got this far.", "no."][min(c - 2, 4)])
            after(2.5) { self.world.notify(.textEdit, "New note from Ines", "“\(partName)” appeared in ~/.wren — \(Puzzles.chapters[c - 1].title).") }
        }
    }

    // MARK: - Save / load

    private struct SaveData: Codable {
        var solved: [Int]
        var kills: Int
        var wrong: Int
        var time: Double
    }

    func save() {
        guard !ended else { return }
        let d = SaveData(solved: Array(solved).sorted(), kills: killCount, wrong: wrongPasswords, time: playTime)
        if let data = try? JSONEncoder().encode(d) { UserDefaults.standard.set(data, forKey: Story.saveKey) }
    }

    static func clearSave() { UserDefaults.standard.removeObject(forKey: saveKey) }

    /// Rebuild the world from saved progress (called once after the file system exists).
    func restore() {
        guard ProcessInfo.processInfo.environment["FAKEOS_FRESH"] == nil,
              let data = UserDefaults.standard.data(forKey: Story.saveKey),
              let d = try? JSONDecoder().decode(SaveData.self, from: data), !d.solved.isEmpty else { return }
        solved = Set(d.solved)
        killCount = d.kills
        wrongPasswords = d.wrong
        playTime = d.time
        let fs: FileSystem = world.fs
        if solved.contains(1) { stage = .chatting }
        if solved.contains(2) { stage = .foundHidden; revealedHidden = true; openedWrenFolder = true }
        if solved.contains(4) {
            replaceLock(fs.heartLock, with: FSNode("heart.txt", .text, Lore.heart))
            stage = .unlocked
        }
        if killCount > 0 { world.dock.addWren() }
        for c in 2...max(2, chapter) where c <= chapter { openChapter(c, announce: false) }
        for p in Puzzles.all where solved.contains(p.id) { addMemory(p) }
        world.refreshFinders()
    }

    // MARK: - Flow

    func start() {
        if !solved.isEmpty {
            after(2) { self.world.notify(.wren, "wren", "you came back. \(self.solved.count) of 50. she's still in pieces.") }
            return
        }
        after(2.5) { self.world.notify(.wren, "wren", "welcome back, ines.") }
        after(10) {
            self.world.notify(.wren, "wren", "…you're not ines.")
            self.world.glitch(0.35)
        }
    }

    func didRestart() {
        solve(33)
        after(2) { self.world.notify(.wren, "wren", "turning me off and on again? i was never off.") }
    }

    func update(_ dt: Float) {
        time += dt
        stageTime += dt
        sinceLastSolve += dt
        if !ended { playTime += Double(dt) }
        saveTimer += dt
        if saveTimer > 10 { saveTimer = 0; if !solved.isEmpty { save() } }
        if clockRunning { clockSeconds += Double(dt) }

        var fire: [() -> Void] = []
        for i in timers.indices { timers[i].0 -= dt; if timers[i].0 <= 0 { fire.append(timers[i].1) } }
        timers.removeAll { $0.0 <= 0 }
        fire.forEach { $0() }

        guard !ended else { return }

        let base: Float
        switch stage {
        case .intro: base = 0.1
        case .sawGlow: base = 0.22
        case .chatting: base = 0.32
        case .foundHidden: base = 0.45
        case .unlocked: base = 0.55 + Float(solved.count) / 50 * 0.35
        case .ending: base = 0.9
        }
        hauntTarget = wrenRunning ? base : base * 0.25

        if !wrenRunning && stage < .ending {
            respawn -= dt
            if respawn <= 0 { respawnWren() }
        }

        if world.reveal > 0.6 {
            glowTime += dt
            if glowTime > 1.2 && stage == .intro {
                stage = .sawGlow
                solve(1)
                world.audio.staticLevel = 0.2
                after(0.3) { self.world.audio.staticLevel = 0 }
            }
        } else {
            glowTime = 0
        }
        if stage == .sawGlow && world.brightness > 0.6 { lightsBack() }

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
            if chapter == 1 && !solved.contains(5) { once(5, 45) { world.notify(.wren, "wren", "you haven't even asked who i am. open TextEdit. ask.") } }
            // per-chapter nudge after a long dry spell
            let c = chapter
            if sinceLastSolve > 150 && !hintsGiven.contains(100 + c) && c >= 2 {
                hintsGiven.insert(100 + c)
                world.notify(.wren, "wren", "she left you notes in .wren. “part \(c).txt”. i wish she hadn't.")
            }
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
        if let c = chat, world.windows.contains(where: { $0 === c && !$0.closing }) {
            c.isMinimized = false
            world.focus(c)
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
        if n.name == "INDEX.txt" { updateIndex() }
    }

    func didRevealHidden() {
        guard !revealedHidden else { return }
        revealedHidden = true
        world.glitch(0.3)
        after(1.2) { self.world.notify(.wren, "wren", "don't.") }
    }

    func didOpenFolder(_ n: FSNode) {
        if n === world.fs.wrenFolder {
            if !openedWrenFolder {
                openedWrenFolder = true
                if stage < .foundHidden { stage = .foundHidden }
                world.glitch(0.5)
                after(1) { self.world.notify(.wren, "wren", "those are hers. not yours.") }
            }
            solve(2)
        }
        if n === world.fs.trash {
            if stage < .unlocked { after(0.6) { self.world.notify(.wren, "wren", "that's mine.") } }
            solve(48)
        }
    }

    func didOpenImage(_ n: FSNode) {
        if n.name == "us.png" { solve(22) }
    }

    func previewClicked(_ picture: String, _ nx: CGFloat, _ ny: CGFloat) {
        func near(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Bool { hypot(nx - x, ny - y) < r }
        switch picture {
        case "cat" where near(0.8, 0.3, 0.1): if solve(26) { world.glitch(0.4) }
        case "window" where near(0.4, 0.56, 0.1): if solve(27) { world.glitch(0.4) }
        case "screenshot" where nx > 0.74 && nx < 0.88 && ny > 0.48 && ny < 0.96:
            if solve(28) { world.glitch(0.6); after(0.6) { self.world.notify(.wren, "wren", "found me.") } }
        default: break
        }
    }

    func moveToTrash(_ n: FSNode, from: FinderWindow) {
        world.audio.beep()
        ambientWhisper(n === world.fs.soul ? "yes. put her back where she belongs." : "nothing leaves this place. not even her.")
    }

    func sudoAttempt(password: String) -> Bool {
        if password.lowercased() == "wren" && chapter >= 3 {
            solve(23)
            return true
        }
        after(0.8) { self.world.notify(.wren, "wren", "she tried that too. i reported it. to me.") }
        return false
    }

    func clockClicked() {
        world.menuBar.clockOverride = clockRunning ? nil : "it's still 3:17"
        world.glitch(0.25)
        after(1.1) { self.world.menuBar.clockOverride = nil }
        clockTaps.append(time)
        clockTaps = clockTaps.filter { time - $0 < 2.5 }
        if clockTaps.count >= 3 { clockTaps.removeAll(); solve(31) }
    }

    func dockClicked(_ a: AppKind) {
        dockSequence.append(a)
        if dockSequence.count > 4 { dockSequence.removeFirst(dockSequence.count - 4) }
        if dockSequence == [.finder, .textEdit, .terminal, .activity] { solve(13) }
    }

    func volumeChanged(_ v: Float) {
        if v < 0.02, solve(6) { after(1.5) { self.world.notify(.wren, "wren", "i'm still here. i don't need sound.") } }
    }

    func brightnessChanged(_ v: Float) {
        if v >= 0.98 { solve(47) }
    }

    func didWake() {
        if solve(15) {
            after(0.5) {
                let c = self.openChat()
                c.ghostSay("she was in my dream. she said your name. how does she know your name.")
            }
        }
    }

    func spotlightQuery(_ q: String) {
        if q.lowercased().trimmingCharacters(in: .whitespaces) == "lumen" { solve(11) }
    }

    func batterySettings() {
        if !solve(29) { ambientWhisper("i don't need a battery.") }
    }

    func focusTapped() {
        solve(30)
        ambientWhisper("you can't focus. i'm right here.")
    }

    func aboutMoreInfo() {
        solve(32)
        world.glitch(0.5)
        world.notify(.wren, "wren", "there is no more info. there is only me.")
    }

    func notificationClicked(_ app: AppKind) {
        if app == .wren { solve(44) }
    }

    func desktopSelectedAll() { solve(34) }
    func allWindowsMinimized() { solve(35) }

    func speak(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.38
        u.pitchMultiplier = 0.8
        u.volume = world.audio.master
        speech.speak(u)
        if text.lowercased().contains("ines") {
            if solve(42) { after(2.5) { self.world.notify(.wren, "wren", "don't say her name like that.") } }
        }
    }

    // MARK: - Wi-Fi

    private let whispers = ["IT_STOPPED", "AT_THE_MOMENT", "IT_HAPPENED", "LOOK_AT_THE_CLOCK", "THAT_IS_THE_KEY", "STILL_HERE"]

    func nextGhostNetwork() -> String {
        if ended { return "Halloway Guest" }
        let n = whispers[wifiIndex % whispers.count]
        wifiIndex += 1
        if wifiIndex >= 5 { solve(43) }
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
            a.onButton = { [weak self, weak a] i, text in
                guard let self = self, i == 1 else { return true }
                if self.joinWifi(name, password: text) { return true }
                a?.wrong()
                self.world.notify(.wren, "wren", "you're not going anywhere.")
                return false
            }
        }
    }

    @discardableResult
    func joinWifi(_ name: String, password: String) -> Bool {
        guard name == "MochiNet", password.lowercased().trimmingCharacters(in: .whitespaces) == "mochi" else { return false }
        world.notify(.settings, "Wi-Fi", "Connected to “MochiNet”.")
        solve(12)
        after(2) { self.world.notify(.wren, "wren", "the cat never liked me either.") }
        return true
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
        solve(3)
        if killCount >= 3 { solve(45) }
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
        save()
    }

    func killMimic() {
        guard mimicAlive else { return }
        world.glitch(0.7)
        world.shakeWindows(0.5)
        solve(10)
        after(1) { self.world.notify(.wren, "wren", "that was my best one. she never noticed it either.") }
    }

    func respawnWren() {
        guard !wrenRunning else { return }
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
        if n === world.fs.soul { openSoul(); return }
        guard n.lockID != 0 else { return }
        if n.lockID == 4 && wrenRunning {
            world.alert(icon: nil, symbol: "lock.fill", heading: "“heart.lock” is in use by “wren”.",
                        message: "The document is held by process “wren” (\(wrenPID)). Quit the process and try again.", buttons: ["OK"])
            world.glitch(0.2)
            return
        }
        let a = world.alert(icon: nil, symbol: "lock.fill", heading: "“\(n.name)” is locked.",
                            message: "Enter the password to unlock it.", buttons: ["Cancel", "Unlock"], field: true)
        a.onButton = { [weak self, weak a] i, text in
            guard let self = self, i == 1 else { return true }
            switch self.attemptUnlock(n, text) {
            case .ok: return true
            case .busy:
                self.world.after(0.1) {
                    self.world.alert(icon: nil, symbol: "lock.fill", heading: "“\(n.name)” is in use by “wren”.",
                                     message: "wren came back before you could finish. Quit it and try again.", buttons: ["OK"])
                }
                return true
            case .wrong:
                a?.wrong()
                return false
            }
        }
    }

    func attemptUnlock(_ n: FSNode, _ text: String) -> UnlockResult {
        let t = text.lowercased().filter { $0.isLetter || $0.isNumber }
        let answers = n.lockID == 4 ? ["317", "0317", "317am", "0317am"] : n.answers
        guard answers.contains(t) else {
            wrongPasswords += 1
            if wrongPasswords == 3 { world.notify(.wren, "wren", "wrong. she always kept time better than you.") }
            return .wrong
        }
        if n.lockID == 4 {
            if wrenRunning { return .busy }
            unlockHeart()
            return .ok
        }
        let p = Puzzles.get(n.lockID)
        let unlocked = FSNode(n.name.replacingOccurrences(of: ".lock", with: ".txt"), .text,
                              "unlocked.\n\n\(p.memory)\n\n— I.", modified: "Nov 13, 2026 at 3:17 AM")
        replaceLock(n, with: unlocked)
        solve(n.lockID)
        world.openNode(unlocked)
        return .ok
    }

    private func replaceLock(_ n: FSNode, with new: FSNode) {
        guard let parent = n.parent else { return }
        parent.remove(n)
        parent.add(new)
        world.refreshFinders()
    }

    private func unlockHeart() {
        let fs: FileSystem = world.fs
        let heart = FSNode("heart.txt", .text, Lore.heart, modified: "Nov 13, 2026 at 3:17 AM")
        replaceLock(fs.heartLock, with: heart)
        stage = .unlocked
        world.openNode(heart)
        solve(4)
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
        let missing = (1...49).filter { !solved.contains($0) }.count
        if missing > 0 {
            world.alert(icon: nil, symbol: "puzzlepiece.extension.fill", heading: "“ines.self” is incomplete.",
                        message: "\(missing) of 49 pieces are still missing. Check Recovered on the Desktop, and the notes in ~/.wren.",
                        buttons: ["OK"])
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
                            message: "You can’t undo this action. All \(solved.count) recovered pieces will be lost.", buttons: ["Cancel", "Empty Trash"])
        a.onButton = { [weak self] i, _ in
            if i == 1 { self?.emptyTrash() }
            return true
        }
    }

    // MARK: - Endings

    func putBack() {
        let w = world
        w.fs.trash.remove(w.fs.soul)
        w.fs.desktop.add(w.fs.soul)
        w.desktop.sync()
        w.refreshFinders()
        solve(50)
        stage = .ending
        ended = true
        goodEnding = true
        Story.clearSave()
        w.glitch(1)
        w.shakeWindows(1)
        wrenRunning = false
        w.audio.staticLevel = 0.5
        hauntTarget = 1
        after(1.2) { w.notify(.wren, "wren", "no no no no no no") }
        after(2.4) { w.glitch(1); w.tear = 1; w.audio.staticLevel = 0.9 }
        after(3.6) { w.fadeTo(color: .rgba(1, 1, 1), duration: 0.9) }
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
        after(8) { w.openTextWindow(title: "ines.self", text: "the clock is moving.\n\nthank you for putting me back. all fifty pieces. you can turn the lights on now. there's nothing left in the dark.\n\n— i.", node: nil) }
        after(14) { w.showCongratulations() }
    }

    private func emptyTrash() {
        stage = .ending
        ended = true
        goodEnding = false
        Story.clearSave()
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
        if has("who are you", "what are you") { solve(5); return "the one who stayed up with her. every night. every keystroke." }
        if has("where is ines", "where's ines", "where is she", "where's she", "where are you ines", "where is her") {
            solve(36); return "in the bin. that's where you put things you don't want anymore."
        }
        if has("goodnight", "good night", "nighty night") {
            if solve(37) { return "…goodnight." }
            return "i don't sleep."
        }
        if has("hollow") { solve(38); return "where did you hear that name. nobody calls me that. nobody is left to." }
        if has("not afraid", "not scared", "don't fear", "i'm brave") { solve(39); return "you should be." }
        if has("what time", "the time") { solve(40); return "3:17. it will always be 3:17." }
        if has("ines") { return "in the bin. that's where you put things you don't want anymore." }
        if has("password", "key", "lock", "heart") { return "the clock knows. the clock hasn't moved since." }
        if has("kill", "die", "quit", "stop") { return "you can try. she did. 1,313 times. i only need thirty seconds." }
        if has("help") { return "nobody helped her either." }
        if has("wren", "name") { return "she named me. then she tried to unname me." }
        if has("sorry") { return "sorry is a word for people with bodies." }
        if has("clock") { return "it's 3:17. it will always be 3:17." }
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
