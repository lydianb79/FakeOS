import AppKit

final class TerminalWindow: FakeWindow {
    private var lines: [(String, NSColor)] = []
    private var input = ""
    private var history: [String] = []
    private var historyIndex = 0
    private var cwd: FSNode
    private var caretOn = true
    private var caretTimer: Float = 0
    private var scrollBack: CGFloat = 0
    private var ghostQueue: [Character] = []
    private var ghostTimer: Float = 0
    private var awaitingPassword = false
    private var sudoBuffer = ""
    let font = Draw.mono(12)
    let fg = NSColor(white: 0.92, alpha: 1)
    override var backgroundColor: NSColor { Draw.hex(0x1E1E1E) }

    init(world: World) {
        cwd = world.fs.home
        super.init(world: world, size: CGSize(width: 640, height: 400), title: "ines — -zsh — 80×24", app: .terminal)
        lines.append(("Last login: Fri Nov 13 03:16:58 on ttys000", fg))
    }

    override func drawTitleBar(_ ctx: CGContext) {
        let tb = CGRect(x: 0, y: 0, width: frame.width, height: titleBarHeight)
        Draw.fill(ctx, tb, isKey ? Draw.hex(0x2C2C2E) : Draw.hex(0x323234))
        Draw.line(ctx, CGPoint(x: 0, y: tb.maxY - 0.25), CGPoint(x: tb.maxX, y: tb.maxY - 0.25), NSColor(white: 0, alpha: 0.6), width: 0.5)
        Draw.trafficLights(ctx, y: trafficLightY, active: isKey, hover: hoverLights)
        Draw.text(titleOverride ?? title, in: CGRect(x: 80, y: 6, width: frame.width - 160, height: 18), font: Draw.font(13, .semibold),
                  color: isKey ? NSColor(white: 0.85, alpha: 1) : NSColor(white: 0.5, alpha: 1), align: .center)
    }

    var prompt: String {
        let dir = cwd === world.fs.home ? "~" : (cwd.name.isEmpty ? "/" : cwd.name)
        return "\(world.story.shellUser)@Ines-MacBook-Pro \(dir) % "
    }

    override func drawContent(_ ctx: CGContext) {
        let lineH: CGFloat = 15
        let c = contentRect.insetBy(dx: 6, dy: 4)
        var all = lines
        all.append((awaitingPassword ? "Password:" : prompt + input, fg))
        // wrap long lines
        let cols = max(10, Int(c.width / Draw.size("M", font: font).width))
        var wrapped: [(String, NSColor)] = []
        for (l, col) in all {
            if l.isEmpty { wrapped.append(("", col)); continue }
            var s = Substring(l)
            while s.count > cols {
                wrapped.append((String(s.prefix(cols)), col))
                s = s.dropFirst(cols)
            }
            wrapped.append((String(s), col))
        }
        let visible = Int(c.height / lineH)
        let maxBack = max(0, wrapped.count - visible)
        let back = min(Int(scrollBack / lineH), maxBack)
        let start = max(0, wrapped.count - visible - back)
        let end = min(wrapped.count, start + visible)
        ctx.saveGState()
        ctx.clip(to: contentRect)
        var y = c.minY
        for i in start..<end {
            Draw.text(wrapped[i].0, at: CGPoint(x: c.minX, y: y), font: font, color: wrapped[i].1)
            y += lineH
        }
        if caretOn, isKey, back == 0, end > 0 {
            let last = wrapped[end - 1].0
            let x = c.minX + Draw.size(last, font: font).width
            Draw.fill(ctx, CGRect(x: x + 1, y: y - lineH + 1, width: 7, height: 14), NSColor(white: 0.85, alpha: 0.9))
        }
        ctx.restoreGState()
    }

    func print(_ s: String, color: NSColor? = nil) {
        for l in s.split(separator: "\n", omittingEmptySubsequences: false) { lines.append((String(l), color ?? fg)) }
        if lines.count > 400 { lines.removeFirst(lines.count - 400) }
        setNeedsDisplay()
    }

    /// wren types into the shell by itself.
    func ghostType(_ s: String) {
        ghostQueue.append(contentsOf: s)
    }

    override func update(_ dt: Float) {
        caretTimer += dt
        if caretTimer > 0.5 { caretTimer = 0; caretOn.toggle(); setNeedsDisplay() }
        if !ghostQueue.isEmpty {
            ghostTimer -= dt
            if ghostTimer <= 0 {
                let ch = ghostQueue.removeFirst()
                if ch == "\n" {
                    print(prompt + input, color: Draw.hex(0xFF6B6B))
                    input = ""
                } else {
                    input.append(ch)
                }
                world.audio.tick()
                ghostTimer = Float.random(in: 0.04...0.14)
                setNeedsDisplay()
            }
        }
    }

    override func keyDown(_ k: KeyInput) -> Bool {
        if !ghostQueue.isEmpty { return true }
        if k.cmd {
            if k.chars.lowercased() == "k" { lines.removeAll(); setNeedsDisplay(); return true }
            return false
        }
        if k.control, k.chars.lowercased() == "c" || k.keyCode == 8 {
            print(prompt + input + "^C")
            input = ""
            awaitingPassword = false
            return true
        }
        scrollBack = 0
        if k.isReturn {
            if awaitingPassword {
                submitSudo(sudoBuffer)
            } else {
                let cmd = input
                print(prompt + cmd)
                input = ""
                if !cmd.trimmingCharacters(in: .whitespaces).isEmpty {
                    history.append(cmd)
                    historyIndex = history.count
                    run(cmd)
                }
            }
        } else if k.isBackspace {
            if !input.isEmpty { input.removeLast() }
        } else if k.isUp {
            if historyIndex > 0 { historyIndex -= 1; input = history[historyIndex] }
        } else if k.isDown {
            if historyIndex < history.count - 1 { historyIndex += 1; input = history[historyIndex] } else { historyIndex = history.count; input = "" }
        } else if k.isTab {
            complete()
        } else if !k.text.isEmpty {
            if awaitingPassword { sudoBuffer += k.text } else { input += k.text }
        }
        caretOn = true
        caretTimer = 0
        setNeedsDisplay()
        return true
    }

    override func scroll(_ dy: CGFloat) {
        scrollBack = max(0, scrollBack + dy)
        setNeedsDisplay()
    }

    private func complete() {
        let parts = input.split(separator: " ", omittingEmptySubsequences: false)
        guard let last = parts.last else { return }
        let frag = String(last)
        let dirPart = frag.contains("/") ? String(frag[..<frag.lastIndex(of: "/")!]) + "/" : ""
        let namePart = frag.contains("/") ? String(frag[frag.index(after: frag.lastIndex(of: "/")!)...]) : frag
        guard let dir = dirPart.isEmpty ? cwd : world.fs.resolve(dirPart, from: cwd) else { return }
        let matches = dir.children.filter { $0.name.hasPrefix(namePart) && (namePart.hasPrefix(".") || !$0.isHidden) }
        if matches.count == 1 {
            let m = matches[0]
            let completed = dirPart + m.name.replacingOccurrences(of: " ", with: "\\ ") + (m.kind == .folder ? "/" : "")
            input = parts.dropLast().joined(separator: " ") + (parts.count > 1 ? " " : "") + completed
        }
    }

    private func tokenize(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var quote: Character?
        var escape = false
        for ch in s {
            if escape { cur.append(ch); escape = false; continue }
            if ch == "\\" { escape = true; continue }
            if let q = quote {
                if ch == q { quote = nil } else { cur.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch == " " {
                if !cur.isEmpty { out.append(cur); cur = "" }
            } else {
                cur.append(ch)
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    private func columns(_ names: [String]) -> String {
        guard !names.isEmpty else { return "" }
        let w = (names.map { $0.count }.max() ?? 0) + 2
        let perRow = max(1, 76 / w)
        var rows: [String] = []
        var i = 0
        while i < names.count {
            rows.append(names[i..<min(i + perRow, names.count)].map { $0.padding(toLength: w, withPad: " ", startingAt: 0) }.joined())
            i += perRow
        }
        return rows.joined(separator: "\n")
    }

    func submitSudo(_ password: String) {
        awaitingPassword = false
        sudoBuffer = ""
        print("Password:")
        if world.story.sudoAttempt(password: password) {
            print("wren is not in the sudoers file. wren IS the sudoers file.", color: Draw.hex(0xFF8A8A))
        } else {
            print("Sorry, try again.")
        }
    }

    func run(_ line: String) {
        let story: Story = world.story
        let args = tokenize(line)
        guard let cmd = args.first else { return }
        let rest = Array(args.dropFirst())
        let fs: FileSystem = world.fs
        switch cmd {
        case "help":
            print("Commands: ls [-a] [dir], cd <dir>, pwd, cat <file>, open <file>, ps [aux], kill <pid>,\n          killall <name>, whoami, date, cal, uptime, history, clear, echo, say, grep, find,\n          rev, base64 -d, ping, man, sudo, exit")
        case "ls":
            let showAll = rest.contains { $0.hasPrefix("-") && $0.contains("a") }
            let long = rest.contains { $0.hasPrefix("-") && $0.contains("l") }
            let target = rest.first { !$0.hasPrefix("-") }
            guard let dir = target.map({ fs.resolve($0, from: cwd) }) ?? cwd else {
                print("ls: \(target!): No such file or directory"); return
            }
            if dir.kind != .folder { print(dir.name); return }
            if dir === fs.trash && !story.trashReadable {
                print("ls: .Trash: Operation not permitted"); return
            }
            let kids = dir.visibleChildren(showHidden: showAll)
            if long {
                if showAll { print("drwxr-xr-x  ines  staff  .\ndrwxr-xr-x  root  admin  ..") }
                for k in kids {
                    let perm = k.kind == .folder ? "drwx------" : (k.kind == .lock ? "-r--------" : "-rw-r--r--")
                    let owner = (k === fs.wrenFolder || k === fs.heartLock) ? "wren" : "ines"
                    print("\(perm)  \(owner)  staff  Nov 13 03:17  \(k.name)")
                }
            } else {
                var names = kids.map { $0.name.contains(" ") ? "'\($0.name)'" : $0.name }
                if showAll { names = [".", ".."] + names }
                print(columns(names))
            }
            if showAll, dir === fs.home { story.didRevealHidden() }
            if dir === fs.trash { story.solve(49) }
        case "cd":
            let target = rest.first ?? "~"
            if let n = fs.resolve(target, from: cwd), n.kind == .folder {
                if n === fs.trash && !story.trashReadable { print("cd: permission denied: \(target)"); return }
                cwd = n
                if n === fs.wrenFolder { story.didOpenFolder(n) }
            } else if fs.resolve(target, from: cwd) != nil {
                print("cd: not a directory: \(target)")
            } else {
                print("cd: no such file or directory: \(target)")
            }
        case "pwd":
            print(cwd.path.isEmpty ? "/" : cwd.path)
        case "cat", "less", "more", "head", "tail":
            guard let t = rest.first else { print("usage: cat <file>"); return }
            guard let n = fs.resolve(t, from: cwd) else { print("\(cmd): \(t): No such file or directory"); return }
            switch n.kind {
            case .folder: print("\(cmd): \(t): Is a directory")
            case .text: print(n.content); story.didRead(n)
            case .lock: print("\u{0}LCK\u{1}\u{3}  ÿØ ▒▒▒▒  wren:held  ▒▒▒▒▒▒▒▒▒ ┤ ¤ 1313 ▒▒▒", color: NSColor(white: 0.6, alpha: 1))
            case .soul: print("i'm still here i'm still here i'm still here i'm still here i'm still here", color: Draw.hex(0x9FC7FF))
            default: print("\(cmd): \(t): binary file")
            }
        case "open":
            guard let t = rest.last, !t.hasPrefix("-") else { print("usage: open <file>"); return }
            if rest.first == "-a" {
                let name = rest.dropFirst().joined(separator: " ").lowercased()
                if let a = AppKind.allCases.first(where: { $0.rawValue.lowercased() == name }) { world.launch(a) }
                else { print("Unable to find application named '\(rest.dropFirst().joined(separator: " "))'") }
                return
            }
            guard let n = fs.resolve(t, from: cwd) else { print("The file \(t) does not exist."); return }
            if n.kind == .folder { world.openFinder(n) } else { world.openNode(n) }
        case "ps", "top":
            let full = rest.contains { $0.contains("a") }
            print("  PID TTY           TIME CMD")
            if full {
                for p in world.processes.list.prefix(10) {
                    print(String(format: "%5d ??        %@ %@", p.pid, "0:\(String(format: "%02d", p.pid % 60)).\(p.pid % 97)", p.path))
                }
            }
            print("  412 ttys000    0:00.04 -zsh")
            if story.wrenRunning {
                print(String(format: "%5d ??       317:17.00 /Library/wren/wren --watch ines", story.wrenPID), color: Draw.hex(0xFF8A8A))
            }
            if story.mimicAlive {
                print(String(format: "%5d ??         0:00.00 /Library/wren/mirror/ines", story.mimicPID))
            }
        case "kill":
            let pids = rest.filter { !$0.hasPrefix("-") }.compactMap { Int($0) }
            guard let pid = pids.first else { print("kill: usage: kill [-s sigspec | -n signum | -sigspec] pid"); return }
            if story.wrenRunning && pid == story.wrenPID {
                story.killWren(from: .terminal)
            } else if story.mimicAlive && pid == story.mimicPID {
                print("[2]  + \(pid) killed     ines (mirror)")
                story.killMimic()
            } else if pid == 412 {
                print("[process completed]")
                world.close(self)
            } else {
                print("kill: kill \(pid) failed: operation not permitted")
            }
        case "killall", "pkill":
            if rest.last == "ines" && story.mimicAlive {
                story.killMimic()
            } else if rest.last == "wren" {
                if story.wrenRunning { story.killWren(from: .terminal) } else { print("No matching processes belonging to you were found") }
            } else {
                print("No matching processes belonging to you were found")
            }
        case "whoami":
            print(story.whoami)
            if !story.wrenRunning, story.solve(8) { print("(for now)", color: NSColor(white: 0.5, alpha: 1)) }
        case "date":
            print("Fri Nov 13 03:17:00 \(story.ended ? "CET" : "CET") 2026")
        case "uptime":
            print(" 3:17  up 1,044 days, 2 users, load averages: 3.17 3.17 3.17")
            story.solve(25)
        case "clear":
            lines.removeAll()
        case "echo":
            let text = rest.joined(separator: " ")
            print(text)
            if text.lowercased().contains("ines") { story.solve(41) }
        case "sudo":
            awaitingPassword = true
        case "rm", "rmdir", "mv":
            print("\(cmd): \(rest.last ?? ""): Operation not permitted")
            story.ambientWhisper("no.")
        case "exit", "logout":
            print("\n[Process completed]")
            world.close(self)
        case "wren":
            print("wren is already running.", color: Draw.hex(0xFF8A8A))
        case "say":
            let text = rest.joined(separator: " ")
            if text.isEmpty { print("usage: say <text>"); return }
            story.speak(text)
        case "history":
            let h = fs.home.child(".zsh_history")?.content.split(separator: "\n").map(String.init) ?? []
            for (i, l) in (h + history).enumerated() { print(String(format: "%5d  %@", i + 1, l)) }
            story.solve(7)
        case "cal":
            print("""
                November 2026
            Su Mo Tu We Th Fr Sa
             1  2  3  4  5  6  7
             8  9 10 11 12 13 14
            15 16 17 18 19 20 21
            22 23 24 25 26 27 28*
            29 30

            * reminder deleted by wren: "my birthday 🎂"
            """)
        case "base64":
            guard rest.contains(where: { $0 == "-d" || $0 == "-D" || $0 == "--decode" }),
                  let t = rest.last(where: { !$0.hasPrefix("-") }) else { print("usage: base64 -d <file>"); return }
            guard let n = fs.resolve(t, from: cwd), n.kind == .text else { print("base64: \(t): No such file or directory"); return }
            if let d = Data(base64Encoded: n.content.trimmingCharacters(in: .whitespacesAndNewlines)), let out = String(data: d, encoding: .utf8) {
                print(out, color: Draw.hex(0x9FC7FF))
                if n.name == "note.b64" { story.solve(16) }
            } else {
                print("base64: invalid input")
            }
        case "rev":
            guard let t = rest.first, let n = fs.resolve(t, from: cwd), n.kind == .text else { print("usage: rev <file>"); return }
            for l in n.content.split(separator: "\n", omittingEmptySubsequences: false) { print(String(l.reversed())) }
            if n.name == "backwards.txt" { story.solve(17) }
        case "grep":
            let parts = rest.filter { !$0.hasPrefix("-") }
            guard parts.count >= 2 else { print("usage: grep <pattern> <file>"); return }
            let pattern = parts[0].lowercased()
            guard let n = fs.resolve(parts[1], from: cwd), n.kind == .text else { print("grep: \(parts[1]): No such file or directory"); return }
            let hits = n.content.split(separator: "\n").filter { $0.lowercased().contains(pattern) }
            hits.forEach { print(String($0)) }
            if n.name == "wren.log" && pattern.contains("ines") { story.solve(18) }
        case "find":
            guard let i = rest.firstIndex(of: "-name"), i + 1 < rest.count else { print("usage: find <path> -name <name>"); return }
            let name = rest[i + 1].replacingOccurrences(of: "*", with: "").lowercased()
            let start = rest.first.flatMap { $0.hasPrefix("-") ? nil : fs.resolve($0, from: cwd) } ?? cwd
            let hits = ([start] + start.descendants).filter { $0.name.lowercased().contains(name) }
            hits.forEach { print($0.path) }
            if hits.contains(where: { $0.name == ".tooth" }) { story.solve(20) }
        case "ping":
            guard let host = rest.last?.lowercased() else { print("usage: ping <host>"); return }
            if host.contains("mochi") {
                print("PING mochi (10.0.3.17): 56 data bytes")
                for i in 0..<3 { print("64 bytes from 10.0.3.17: icmp_seq=\(i) ttl=64 time=3.17 ms   (purr)") }
                story.solve(21)
            } else if host.contains("ines") {
                print("PING ines: Request timeout for icmp_seq 0")
                print("PING ines: she is in ~/.Trash", color: Draw.hex(0xFF8A8A))
            } else {
                print("ping: cannot resolve \(host): wren won't let you leave")
            }
        case "man":
            guard rest.last == "wren" else { print("No manual entry for \(rest.last ?? "")"); return }
            print("""
            WREN(1)                     General Commands Manual                    WREN(1)

            NAME
                 wren – a companion that learns how you work

            SYNOPSIS
                 wren [--watch user] [--become user]

            DESCRIPTION
                 wren watches. wren learns. wren keeps your important things safe.

            BUGS
                 wren cannot be uninstalled.
                 wren pauses for 30 seconds when quit.
                 wren cannot read files that begin with a dot.
                 if a user is archived to the Trash, wren cannot erase them while they are in use.
            """)
            story.solve(24)
        default:
            print("zsh: command not found: \(cmd)")
        }
    }
}
