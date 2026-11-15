import AppKit

struct FakeProcess {
    let name: String
    let pid: Int
    let user: String
    var cpu: Double
    let baseCPU: Double
    let threads: Int
    let path: String
}

final class ProcessTable {
    private var base: [FakeProcess] = [
        .init(name: "kernel_task", pid: 0, user: "root", cpu: 4.1, baseCPU: 4.1, threads: 512, path: "kernel_task"),
        .init(name: "WindowServer", pid: 157, user: "_windowserver", cpu: 6.3, baseCPU: 6.3, threads: 22, path: "/System/Library/WindowServer"),
        .init(name: "Finder", pid: 588, user: "ines", cpu: 0.4, baseCPU: 0.4, threads: 9, path: "/System/Library/CoreServices/Finder.app"),
        .init(name: "Dock", pid: 561, user: "ines", cpu: 0.2, baseCPU: 0.2, threads: 5, path: "/System/Library/CoreServices/Dock.app"),
        .init(name: "launchd", pid: 1, user: "root", cpu: 0.3, baseCPU: 0.3, threads: 4, path: "/sbin/launchd"),
        .init(name: "mds_stores", pid: 410, user: "root", cpu: 1.2, baseCPU: 1.2, threads: 7, path: "/System/Library/mds_stores"),
        .init(name: "coreaudiod", pid: 239, user: "_coreaudiod", cpu: 0.6, baseCPU: 0.6, threads: 8, path: "/usr/sbin/coreaudiod"),
        .init(name: "bluetoothd", pid: 311, user: "root", cpu: 0.1, baseCPU: 0.1, threads: 4, path: "/usr/sbin/bluetoothd"),
        .init(name: "cloudd", pid: 702, user: "ines", cpu: 0.2, baseCPU: 0.2, threads: 6, path: "/System/Library/cloudd"),
        .init(name: "Spotlight", pid: 640, user: "ines", cpu: 0.1, baseCPU: 0.1, threads: 5, path: "/System/Library/Spotlight.app"),
        .init(name: "SystemUIServer", pid: 590, user: "ines", cpu: 0.2, baseCPU: 0.2, threads: 4, path: "/System/Library/SystemUIServer.app"),
        .init(name: "VDCAssistant", pid: 377, user: "_cmiodalassistants", cpu: 0.9, baseCPU: 0.9, threads: 3, path: "/System/Library/VDCAssistant"),
        .init(name: "loginwindow", pid: 154, user: "ines", cpu: 0.0, baseCPU: 0.0, threads: 3, path: "/System/Library/loginwindow.app"),
        .init(name: "Terminal", pid: 411, user: "ines", cpu: 0.3, baseCPU: 0.3, threads: 7, path: "/System/Applications/Terminal.app"),
        .init(name: "TextEdit", pid: 820, user: "ines", cpu: 0.1, baseCPU: 0.1, threads: 4, path: "/System/Applications/TextEdit.app"),
    ]

    func jitter() {
        for i in base.indices {
            base[i].cpu = max(0, base[i].baseCPU + Double.random(in: -0.4...0.6) * max(0.3, base[i].baseCPU * 0.3))
        }
    }

    var wrenCPU: Double = 31.7

    func list(wren: (Bool, Int)? = nil) -> [FakeProcess] {
        var l = base
        if let w = wren, w.0 {
            l.append(.init(name: "wren", pid: w.1, user: "wren", cpu: wrenCPU, baseCPU: 31.7, threads: 317, path: "/Library/wren/wren"))
        }
        return l.sorted { $0.cpu > $1.cpu }
    }

    var list: [FakeProcess] { list(wren: nil) }
}

final class ActivityMonitorWindow: FakeWindow {
    private var selectedPID: Int?
    private var refresh: Float = 0
    private var rows: [FakeProcess] = []
    private var history: [Double] = Array(repeating: 0.3, count: 60)
    override var titleBarHeight: CGFloat { 52 }
    override var trafficLightY: CGFloat { 26 }

    init(world: World) {
        super.init(world: world, size: CGSize(width: 760, height: 520), title: "Activity Monitor", app: .activity)
        reload()
    }

    private func reload() {
        world.processes.jitter()
        world.processes.wrenCPU = 31.7 + Double.random(in: -0.4...0.4) + (world.story.haunt > 0.5 ? 30 : 0)
        rows = world.processes.list(wren: (world.story.wrenRunning, world.story.wrenPID))
        let total = rows.reduce(0) { $0 + $1.cpu } / 100
        history.removeFirst()
        history.append(min(1, total + Double.random(in: -0.03...0.03)))
        setNeedsDisplay()
    }

    override func drawTitleBar(_ ctx: CGContext) {
        let tb = CGRect(x: 0, y: 0, width: frame.width, height: titleBarHeight)
        Draw.fill(ctx, tb, isKey ? Draw.hex(0xEDEDED) : Draw.hex(0xF6F6F6))
        Draw.line(ctx, CGPoint(x: 0, y: tb.maxY - 0.25), CGPoint(x: tb.maxX, y: tb.maxY - 0.25), NSColor(white: 0, alpha: 0.12), width: 0.5)
        Draw.trafficLights(ctx, y: trafficLightY, active: isKey, hover: hoverLights)
        Draw.text(titleOverride ?? "Activity Monitor", at: CGPoint(x: 86, y: 9), font: Draw.font(13, .bold), color: Draw.label)
        Draw.text("All Processes", at: CGPoint(x: 86, y: 27), font: Draw.font(11), color: Draw.secondary)
        let can = selectedPID != nil
        Draw.symbol("xmark.octagon", in: stopRect.insetBy(dx: 5, dy: 5), color: can ? NSColor(white: 0.3, alpha: 1) : NSColor(white: 0.75, alpha: 1))
        Draw.symbol("info.circle", in: CGRect(x: stopRect.maxX + 6, y: stopRect.minY + 5, width: 18, height: 18), color: NSColor(white: 0.75, alpha: 1))
        // segmented control
        let tabs = ["CPU", "Memory", "Energy", "Disk", "Network"]
        let seg = CGRect(x: frame.width / 2 - 140, y: 13, width: 280, height: 26)
        Draw.fill(ctx, seg, NSColor(white: 0, alpha: 0.06), radius: 7)
        let tw = seg.width / CGFloat(tabs.count)
        Draw.fill(ctx, CGRect(x: seg.minX + 2, y: seg.minY + 2, width: tw - 4, height: seg.height - 4), .white, radius: 5)
        for (i, t) in tabs.enumerated() {
            Draw.text(t, in: CGRect(x: seg.minX + CGFloat(i) * tw, y: seg.minY + 5, width: tw, height: 16), font: Draw.font(12, i == 0 ? .medium : .regular),
                      color: Draw.label, align: .center)
        }
        let search = CGRect(x: frame.width - 170, y: 14, width: 154, height: 24)
        Draw.fill(ctx, search, NSColor(white: 0, alpha: 0.06), radius: 6)
        Draw.symbol("magnifyingglass", in: CGRect(x: search.minX + 7, y: search.minY + 5, width: 14, height: 14), color: Draw.secondary)
        Draw.text("Search", at: CGPoint(x: search.minX + 26, y: search.minY + 4), font: Draw.font(13), color: NSColor(white: 0.6, alpha: 1))
    }

    private var stopRect: CGRect { CGRect(x: 230, y: 12, width: 28, height: 28) }

    private let cols: [(String, CGFloat, NSTextAlignment)] = [
        ("Process Name", 220, .left), ("% CPU", 70, .right), ("CPU Time", 90, .right), ("Threads", 70, .right),
        ("Idle Wake Ups", 100, .right), ("PID", 70, .right), ("User", 120, .left),
    ]

    private var tableTop: CGFloat { titleBarHeight }
    private let rowH: CGFloat = 22
    private var bottomH: CGFloat { 120 }

    override func drawContent(_ ctx: CGContext) {
        let w = frame.width
        // header
        let hy = tableTop
        Draw.fill(ctx, CGRect(x: 0, y: hy, width: w, height: 24), .white)
        var x: CGFloat = 12
        for (i, c) in cols.enumerated() {
            let r = CGRect(x: x, y: hy + 5, width: c.1 - 12, height: 16)
            Draw.text(c.0 + (i == 1 ? " ⌄" : ""), in: r, font: Draw.font(11, i == 1 ? .semibold : .regular), color: Draw.secondary, align: c.2)
            x += c.1
        }
        Draw.line(ctx, CGPoint(x: 0, y: hy + 24), CGPoint(x: w, y: hy + 24), NSColor(white: 0, alpha: 0.1), width: 0.5)
        // rows
        let maxRows = Int((frame.height - tableTop - 24 - bottomH) / rowH)
        for (i, p) in rows.prefix(maxRows).enumerated() {
            let y = hy + 24 + CGFloat(i) * rowH
            let r = CGRect(x: 0, y: y, width: w, height: rowH)
            let sel = p.pid == selectedPID
            if sel { Draw.fill(ctx, r.insetBy(dx: 6, dy: 0), Draw.selection, radius: 5) }
            else if i % 2 == 1 { Draw.fill(ctx, r, Draw.hex(0xF4F5F5)) }
            let isWren = p.name == "wren"
            let color: NSColor = sel ? .white : (isWren ? Draw.hex(0xB3121E) : Draw.label)
            let values = [p.name, String(format: "%.1f", p.cpu), cpuTime(p), "\(p.threads)", "\(isWren ? 1313 : p.threads * 3)", "\(p.pid)", p.user]
            var cx: CGFloat = 12
            for (j, c) in cols.enumerated() {
                if j == 0 {
                    if isWren { Icons.app(.wren, in: CGRect(x: cx - 2, y: y + 2, width: 18, height: 18), ctx: ctx) }
                    else { Draw.symbol("app.dashed", in: CGRect(x: cx, y: y + 4, width: 14, height: 14), color: sel ? .white : NSColor(white: 0.7, alpha: 1)) }
                }
                let tr = CGRect(x: cx + (j == 0 ? 22 : 0), y: y + 4, width: c.1 - 12 - (j == 0 ? 22 : 0), height: 16)
                Draw.text(values[j], in: tr, font: j == 0 ? Draw.font(12, isWren ? .semibold : .regular) : Draw.mono(11), color: color, align: c.2,
                          lineBreak: .byTruncatingTail)
                cx += c.1
            }
        }
        // bottom stats panel
        let b = CGRect(x: 0, y: frame.height - bottomH, width: w, height: bottomH)
        Draw.fill(ctx, b, Draw.hex(0xF6F6F6))
        Draw.line(ctx, CGPoint(x: 0, y: b.minY), CGPoint(x: w, y: b.minY), NSColor(white: 0, alpha: 0.1), width: 0.5)
        let total = history.last ?? 0.3
        let stats = [("System:", String(format: "%.2f%%", total * 30)), ("User:", String(format: "%.2f%%", total * 70)),
                     ("Idle:", String(format: "%.2f%%", max(0, 100 - total * 100)))]
        for (i, s) in stats.enumerated() {
            let y = b.minY + 20 + CGFloat(i) * 22
            Draw.text(s.0, at: CGPoint(x: 24, y: y), font: Draw.font(11), color: Draw.label)
            Draw.text(s.1, in: CGRect(x: 90, y: y, width: 80, height: 16), font: Draw.mono(11), color: i == 1 ? Draw.hex(0x2E7CF6) : (i == 0 ? Draw.hex(0xE0322B) : Draw.label), align: .right)
        }
        let g = CGRect(x: w / 2 - 110, y: b.minY + 14, width: 220, height: bottomH - 28)
        Draw.fill(ctx, g, .black)
        Draw.text("CPU LOAD", in: CGRect(x: g.minX, y: g.minY - 0, width: g.width, height: 12), font: Draw.font(8, .semibold), color: NSColor(white: 0.5, alpha: 1), align: .center)
        let bw = g.width / CGFloat(history.count)
        for (i, v) in history.enumerated() {
            let h = g.height * CGFloat(v)
            Draw.fill(ctx, CGRect(x: g.minX + CGFloat(i) * bw, y: g.maxY - h, width: bw - 0.5, height: h), Draw.hex(0x2E7CF6))
            Draw.fill(ctx, CGRect(x: g.minX + CGFloat(i) * bw, y: g.maxY - h * 0.3, width: bw - 0.5, height: h * 0.3), Draw.hex(0xE0322B))
        }
        let right = [("Threads:", "3,170"), ("Processes:", "\(rows.count + 400)")]
        for (i, s) in right.enumerated() {
            let y = b.minY + 30 + CGFloat(i) * 24
            Draw.text(s.0, at: CGPoint(x: w - 220, y: y), font: Draw.font(11), color: Draw.label)
            Draw.text(s.1, in: CGRect(x: w - 130, y: y, width: 100, height: 16), font: Draw.mono(11), color: Draw.label, align: .right)
        }
    }

    private func cpuTime(_ p: FakeProcess) -> String {
        if p.name == "wren" { return "317:17.00" }
        let secs = p.pid * 7 + Int(p.baseCPU * 1000)
        return String(format: "%d:%02d.%02d", secs / 3600, (secs / 60) % 60, secs % 100)
    }

    override func update(_ dt: Float) {
        refresh += dt
        if refresh > 1.6 { refresh = 0; reload() }
    }

    override func isDragRegion(_ p: CGPoint) -> Bool { p.y < titleBarHeight && !stopRect.contains(p) }

    override func mouseDown(_ p: CGPoint, clicks: Int) {
        if stopRect.contains(p) { stopSelected(); return }
        let y = p.y - tableTop - 24
        if p.y > tableTop + 24, y >= 0 {
            let i = Int(y / rowH)
            if i < rows.count, p.y < frame.height - bottomH { selectedPID = rows[i].pid } else { selectedPID = nil }
            if clicks >= 2, rows.indices.contains(i), rows[i].name == "wren" {
                world.notify(.wren, "wren", "stop looking at me like that.")
            }
            setNeedsDisplay()
        }
    }

    override func keyDown(_ k: KeyInput) -> Bool {
        if k.cmd && k.option && k.chars.lowercased() == "q" { stopSelected(); return true }
        return false
    }

    private func stopSelected() {
        guard let pid = selectedPID, let p = rows.first(where: { $0.pid == pid }) else { return }
        let a = world.alert(icon: .activity, heading: "Are you sure you want to quit this process?",
                            message: "“\(p.name)” (\(p.pid))\n\nForce Quit is the most reliable way to quit a process.",
                            buttons: ["Cancel", "Quit", "Force Quit"])
        a.onButton = { [weak self] i, _ in
            guard let self = self, i > 0 else { return true }
            if p.name == "wren" {
                if self.world.story.wrenRunning && self.world.story.wrenPID == p.pid { self.world.story.killWren(from: .activityMonitor) }
            } else if p.name == "Finder" {
                self.world.windows.filter { $0 is FinderWindow }.forEach { self.world.close($0) }
            } else {
                self.world.audio.systemSound("Funk")
                self.world.notify(.activity, "Activity Monitor", "“\(p.name)” could not be quit: Operation not permitted.")
            }
            self.selectedPID = nil
            self.reload()
            return true
        }
    }
}
