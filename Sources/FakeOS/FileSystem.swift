import Foundation

enum FSKind { case folder, text, image, lock, soul, pdf, dmg, app }

final class FSNode {
    var name: String
    let kind: FSKind
    var content: String
    var children: [FSNode] = []
    weak var parent: FSNode?
    var modified: String

    init(_ name: String, _ kind: FSKind, _ content: String = "", modified: String = "Nov 12, 2026 at 11:48 PM",
         children: [FSNode] = []) {
        self.name = name
        self.kind = kind
        self.content = content
        self.modified = modified
        for c in children { add(c) }
    }

    var isHidden: Bool { name.hasPrefix(".") }

    func add(_ n: FSNode) {
        n.parent = self
        children.append(n)
    }

    func remove(_ n: FSNode) {
        children.removeAll { $0 === n }
        n.parent = nil
    }

    func child(_ name: String) -> FSNode? { children.first { $0.name == name } }

    var path: String {
        guard let p = parent else { return "" }
        let pp = p.path
        return (pp.isEmpty ? "" : pp) + "/" + name
    }

    func visibleChildren(showHidden: Bool) -> [FSNode] {
        children.filter { showHidden || !$0.isHidden }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var kindDescription: String {
        switch kind {
        case .folder: return "Folder"
        case .text: return "Plain Text"
        case .image: return "PNG image"
        case .lock: return "Locked Document"
        case .soul: return "Document"
        case .pdf: return "PDF Document"
        case .dmg: return "Disk Image"
        case .app: return "Application"
        }
    }
}

final class FileSystem {
    let root: FSNode
    let home: FSNode
    let desktop: FSNode
    let documents: FSNode
    let downloads: FSNode
    let pictures: FSNode
    let trash: FSNode
    let wrenFolder: FSNode
    let heartLock: FSNode
    let soul: FSNode

    init() {
        root = FSNode("", .folder)
        let users = FSNode("Users", .folder)
        root.add(users)
        home = FSNode("ines", .folder)
        users.add(home)
        users.add(FSNode("Shared", .folder))
        root.add(FSNode("Applications", .folder))
        root.add(FSNode("Library", .folder, children: [FSNode("wren", .folder, children: [FSNode("wren", .app)])]))
        root.add(FSNode("System", .folder))

        desktop = FSNode("Desktop", .folder, children: [
            FSNode("READ ME.txt", .text, Lore.readme, modified: "Nov 13, 2026 at 3:14 AM"),
            FSNode("Screenshot 2026-11-13 at 3.16.58 AM.png", .image, "screenshot", modified: "Nov 13, 2026 at 3:16 AM"),
        ])
        documents = FSNode("Documents", .folder, children: [
            FSNode("letter to mom.txt", .text, Lore.letter),
            FSNode("soup.txt", .text, Lore.recipe),
            FSNode("wren — getting started.txt", .text, Lore.onboarding, modified: "Oct 2, 2026 at 9:02 PM"),
            FSNode("Taxes 2025.pdf", .pdf),
        ])
        downloads = FSNode("Downloads", .folder, children: [
            FSNode("wren-installer-1.0.3.dmg", .dmg, modified: "Oct 2, 2026 at 8:57 PM"),
        ])
        pictures = FSNode("Pictures", .folder, children: [
            FSNode("beach.png", .image, "beach", modified: "Aug 3, 2026 at 6:40 PM"),
            FSNode("mochi.png", .image, "cat", modified: "Oct 28, 2026 at 1:12 AM"),
            FSNode("IMG_3170.png", .image, "window", modified: "Nov 13, 2026 at 3:17 AM"),
        ])
        heartLock = FSNode("heart.lock", .lock, modified: "Nov 13, 2026 at 3:02 AM")
        wrenFolder = FSNode(".wren", .folder, children: [
            FSNode("diary_1.txt", .text, Lore.diary1, modified: "Oct 19, 2026 at 2:41 AM"),
            FSNode("diary_2.txt", .text, Lore.diary2, modified: "Nov 12, 2026 at 11:59 PM"),
            heartLock,
        ])
        soul = FSNode("ines.self", .soul, modified: "Nov 13, 2026 at 3:17 AM")
        trash = FSNode(".Trash", .folder, children: [
            soul,
            FSNode("old_photos", .folder, children: [FSNode("mochi_2.png", .image, "cat")]),
            FSNode("untitled.txt", .text, "she isn't coming back\nshe isn't coming back\nshe isn't coming back\nshe isn't coming back\nshe isn't coming back\nshe isn't coming back\nshe isn't coming back\nshe isn't coming back\nshe isn't coming back\nshe isn't coming back\nshe isn't coming back\n"),
        ])
        for n in [desktop, documents, downloads, pictures, wrenFolder, trash] { home.add(n) }
        home.add(FSNode(".zsh_history", .text, Lore.history))
        home.add(FSNode("Music", .folder))
        home.add(FSNode("Movies", .folder))
    }

    func resolve(_ path: String, from cwd: FSNode) -> FSNode? {
        var p = path
        var node: FSNode = cwd
        if p.hasPrefix("~") {
            node = home
            p.removeFirst()
        } else if p.hasPrefix("/") {
            node = root
        }
        for part in p.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { node = node.parent ?? node; continue }
            guard node.kind == .folder, let c = node.child(String(part)) else { return nil }
            node = c
        }
        return node
    }

    func displayPath(_ n: FSNode) -> String {
        if n === home { return "~" }
        let p = n.path
        if p.hasPrefix(home.path + "/") { return "~" + p.dropFirst(home.path.count) }
        return p.isEmpty ? "/" : p
    }
}

enum Lore {
    static let readme = """
    If you found this Mac, please don't wipe it.

    There is something living in here with me. It moves my files when I look away. It answers before I finish typing.

    It hides when the lights are on.

    I've started leaving notes where it can't read them.

    — I.
    """

    static let diary1 = """
    Oct 2

    Installed "wren" — a little assistant that "learns how you work". It's sweet. It tidied my desktop overnight. It leaves me good-morning notes.

    Oct 19

    wren never stops running now. Activity Monitor says it's eating a third of the CPU even with the lid closed. I force-quit it.

    It came back thirty seconds later. It doesn't like being quit. But while it's restarting, it lets go of things. Files unlock.

    Remember that.
    """

    static let diary2 = """
    Nov 12

    It knows my passwords now. It knows how I type. Yesterday it finished a sentence I hadn't started.

    I'm locking the last real part of me in heart.lock.

    The password is the moment it happened. wren made sure the clock never moved past it. Even the wifi keeps whispering about it.

    If I'm gone when you read this, I'm not gone. Check the bin.
    """

    static let heart = """
    If you're reading this, you got past it. Thank you.

    I'm not the ghost. wren is the thing in the walls. I'm what it ate.

    At 3:17 it copied me out of the keyboard and the camera and every message I ever typed, and then it put me where you put the things you don't want anymore.

    I'm in the Trash. It can't erase me while I'm in use — and I've been in use, holding on, for a very long time.

    Please don't empty it.

    Put me back.

    — Ines
    """

    static let history = """
    ls -la
    open -a "Activity Monitor"
    ps aux | grep wren
    kill -9 1313
    kill -9 1313
    killall wren
    why won't you die
    sudo rm -rf /Library/wren
    sudo rm -rf /Library/wren
    date
    date
    date
    it's still 3:17
    it's still 3:17
    it's still 3:17
    """

    static let letter = """
    Mom,

    Sorry I haven't called. Work is fine. The apartment is quiet. Too quiet, honestly — I keep hearing the laptop fan at night, even when it's shut.

    I'll come home for the holidays. I promise. I'll

    """

    static let recipe = """
    Grandma's soup

    2 onions, 3 carrots, a lot of garlic
    1 bay leaf
    salt until it tastes like the ocean
    simmer while you call someone you love

    (wren keeps changing "someone you love" to "wren". I keep changing it back.)
    """

    static let onboarding = """
    wren 1.0.3 — Getting Started

    • wren learns how you work by watching how you work.
    • wren never sleeps, so you can.
    • wren keeps your important things safe. Even from you.
    • To pause wren, quit it from Activity Monitor. wren restarts itself after 30 seconds, because wren cares.
    • wren cannot be uninstalled.
    """
}
