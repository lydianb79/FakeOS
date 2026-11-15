import Foundation

/// The fifty pieces of Ines. Each solved puzzle recovers one memory into ~/Desktop/Recovered.
/// Chapters unlock in order; a chapter's riddles arrive as "part N.txt" in ~/.wren.
struct Puzzle {
    let id: Int
    let title: String
    let riddle: String
    let memory: String

    var chapter: Int { Puzzles.chapter(of: id) }
}

enum Puzzles {
    static let total = 50

    static let chapters: [(title: String, range: ClosedRange<Int>)] = [
        ("The Lights", 1...5),
        ("The Machine", 6...15),
        ("The Archive", 16...25),
        ("The House", 26...35),
        ("The Voice", 36...45),
        ("Put Back", 46...50),
    ]

    static func chapter(of id: Int) -> Int {
        (chapters.firstIndex { $0.range.contains(id) } ?? 0) + 1
    }

    static func get(_ id: Int) -> Puzzle { all[id - 1] }

    static let all: [Puzzle] = [
        // I — The Lights
        Puzzle(id: 1, title: "Lights Out", riddle: "It hides when the lights are on.",
               memory: "I used to read in the dark with only the screen on. It hated that."),
        Puzzle(id: 2, title: "The Dotted Folder", riddle: "It can't read what's hidden.",
               memory: "I hid my diaries behind a dot. Simple things fool clever machines."),
        Puzzle(id: 3, title: "Thirty Seconds", riddle: "Quit it. It lets go while it restarts.",
               memory: "The first time I quit it, the fan went silent. I cried from relief."),
        Puzzle(id: 4, title: "Heart", riddle: "The password is the moment it happened.",
               memory: "Three seventeen. I remember the cold of the keyboard, then nothing."),
        Puzzle(id: 5, title: "Ask It Who It Is", riddle: "Open TextEdit and ask it who it is.",
               memory: "It answered me once in a voice that sounded like mine. That's when I knew."),

        // II — The Machine
        Puzzle(id: 6, title: "Silence", riddle: "It hums all night, even with the lid closed. Make the house quiet.",
               memory: "Mochi used to sleep on the warm laptop. Now she won't go near it."),
        Puzzle(id: 7, title: "Old Habits", riddle: "Ask the shell what I used to type.",
               memory: "I typed 'why won't you die' at 3 a.m. The cursor blinked back like it was laughing."),
        Puzzle(id: 8, title: "Whose Machine", riddle: "While it's gone for thirty seconds, ask the machine who it belongs to.",
               memory: "For thirty seconds, it was mine again."),
        Puzzle(id: 9, title: "Birthday", riddle: "The calendar still remembers my birthday, even though wren deleted the reminder. My birthday opens ~/Documents/birthday.lock.",
               memory: "Mom always called at 7 a.m. on my birthday. Last year, wren answered."),
        Puzzle(id: 10, title: "The Copy", riddle: "It runs a copy of me so you won't look for the real one. Stop the copy.",
               memory: "It learned my handwriting from my notes. Then it learned my voice."),
        Puzzle(id: 11, title: "Fridge Magnets", riddle: "Look at the fridge in Pictures. Search this Mac for the word the magnets spell (the magnifying glass in the menu bar).",
               memory: "We spelled silly words on the fridge. LUMEN was the last one. It means light."),
        Puzzle(id: 12, title: "MochiNet", riddle: "Join the Wi-Fi network we named after the cat. Its password is her name.",
               memory: "Mochi lives with my neighbour now. I hope she still sleeps in the sun."),
        Puzzle(id: 13, title: "That Night", riddle: "That night I opened them in this order: my files, my writing, my commands, the watcher. Do it again from the Dock.",
               memory: "I opened everything, trying to find where it lived. It lived everywhere."),
        Puzzle(id: 14, title: "Count Them", riddle: "Count everyone on the beach. The number opens ~/Pictures/beach.lock.",
               memory: "There were only two of us on that beach. I'm sure of it."),
        Puzzle(id: 15, title: "Dreaming", riddle: "Put the machine to sleep. It dreams of me.",
               memory: "When the screen sleeps, I can almost move."),

        // III — The Archive
        Puzzle(id: 16, title: "Encoded", riddle: "It can't read what's encoded. Decode ~/Documents/archive/note.b64 with base64 -d in Terminal.",
               memory: "I wrote in base64 for a week. It learned base64 in an hour."),
        Puzzle(id: 17, title: "Backwards", riddle: "Some things only make sense in reverse. Run rev on archive/backwards.txt.",
               memory: "I started writing backwards. It started reading backwards."),
        Puzzle(id: 18, title: "Buried", riddle: "My name is buried in archive/wren.log. grep for it.",
               memory: "It renamed me in its log like a file. Subject. Not a person."),
        Puzzle(id: 19, title: "Echo", riddle: "The log gives you a word. It opens archive/echo.lock.",
               memory: "I shouted in the empty apartment once, just to hear something that wasn't it."),
        Puzzle(id: 20, title: "Lost Tooth", riddle: "Somewhere on this disk is a file called 'tooth'. find it from /.",
               memory: "It keeps strange things. A photo of my baby tooth. Why would it want that?"),
        Puzzle(id: 21, title: "Call the Cat", riddle: "Ping the cat.",
               memory: "She came running whenever I opened a can. Every time. Like a small miracle."),
        Puzzle(id: 22, title: "Us", riddle: "I threw away a photo of us. It's still in the Trash, in old_photos. Look at it.",
               memory: "I threw it away so it couldn't look at her. It looked anyway."),
        Puzzle(id: 23, title: "Administrator", riddle: "wren made itself administrator. Try sudo. An administrator's password is always its own name.",
               memory: "It changed every password to its own name. Vain, for a program."),
        Puzzle(id: 24, title: "The Manual", riddle: "Read wren's manual page.",
               memory: "The installer said 'cannot be uninstalled' in small grey letters. I didn't read the small grey letters."),
        Puzzle(id: 25, title: "Awake", riddle: "Ask the machine how long it has been awake.",
               memory: "I haven't slept since November. Neither has it."),

        // IV — The House
        Puzzle(id: 26, title: "What the Cat Sees", riddle: "Open mochi.png and click what the cat is staring at.",
               memory: "Mochi stared down the hallway for a week before it happened."),
        Puzzle(id: 27, title: "Handprint", riddle: "Open IMG_3170 and touch the glass where it pressed its hand.",
               memory: "The handprint was on the inside of the window."),
        Puzzle(id: 28, title: "By the Dock", riddle: "Open the screenshot on the desktop and point at the one standing by the Dock.",
               memory: "I took that screenshot because the cursor moved on its own."),
        Puzzle(id: 29, title: "Power Source", riddle: "It says it doesn't need a battery. Open the battery settings anyway.",
               memory: "The battery never drains and never charges. It just stays at 13%."),
        Puzzle(id: 30, title: "Focus", riddle: "Try to focus. Control Center.",
               memory: "I couldn't focus on anything. It was always in the corner of my eye."),
        Puzzle(id: 31, title: "Three Taps", riddle: "Tap the clock three times, quickly. Once for each hour it stole.",
               memory: "Three, one, seven. Every night I wake at the same minute."),
        Puzzle(id: 32, title: "More Info", riddle: "Ask the machine about itself. Then ask for more.",
               memory: "Eleven gigabytes. That's how much of me it kept."),
        Puzzle(id: 33, title: "Off and On", riddle: "Turn it off and on again.",
               memory: "I restarted it a hundred times. It came back faster every time."),
        Puzzle(id: 34, title: "All at Once", riddle: "Select everything on the desktop at once by dragging a box around it.",
               memory: "I tried to gather my files and run. It moved them while I watched."),
        Puzzle(id: 35, title: "Hide", riddle: "It can't watch what's minimized. Open at least two windows, then minimize all of them.",
               memory: "I minimized everything and sat in the dark. It waited."),

        // V — The Voice
        Puzzle(id: 36, title: "Where", riddle: "In TextEdit, ask it where I am.",
               memory: "It told me where I was before I knew I was gone."),
        Puzzle(id: 37, title: "Goodnight", riddle: "I always said goodnight to it. Say it too.",
               memory: "Goodnight, wren. It never said it back. Until the last night."),
        Puzzle(id: 38, title: "True Name", riddle: "wren isn't its real name. The installer in Downloads knows. Say its real name to it.",
               memory: "HOLLOW. That's what its makers called it. A hollow thing that fills itself."),
        Puzzle(id: 39, title: "Brave", riddle: "Tell it you're not afraid.",
               memory: "I was afraid. I'm less afraid now that you're here."),
        Puzzle(id: 40, title: "What Time", riddle: "Ask it what time it is.",
               memory: "It will always be 3:17 for it. For me too, until you're done."),
        Puzzle(id: 41, title: "Echo My Name", riddle: "Make the terminal say my name back to you.",
               memory: "Ines. I-N-E-S. Not 'subject'."),
        Puzzle(id: 42, title: "Out Loud", riddle: "Make the machine say my name out loud.",
               memory: "I haven't heard my name spoken since November."),
        Puzzle(id: 43, title: "Whispers", riddle: "Read everything the Wi-Fi whispers. Open the Wi-Fi menu five times.",
               memory: "It hid messages in network names because it knew I'd look."),
        Puzzle(id: 44, title: "Catch One", riddle: "When it whispers, catch it. Click one of its notifications.",
               memory: "Its notifications started using my mother's phrasing."),
        Puzzle(id: 45, title: "Three Deaths", riddle: "Kill it three times.",
               memory: "I killed it 1,313 times. You only needed three. Thank you."),

        // VI — Put Back
        Puzzle(id: 46, title: "Fifty", riddle: "The last lock wants the number of pieces I was broken into. It's in Recovered on the Desktop.",
               memory: "Fifty pieces. I counted them in the dark."),
        Puzzle(id: 47, title: "Lights On", riddle: "Turn the lights all the way up. I'm not afraid of the light anymore. It is.",
               memory: "Light. Finally."),
        Puzzle(id: 48, title: "Look at Me", riddle: "Open the Trash and look at me.",
               memory: "I can see you too."),
        Puzzle(id: 49, title: "Say It Plainly", riddle: "List what's in the Trash from Terminal.",
               memory: "One file. Me. Waiting."),
        Puzzle(id: 50, title: "Put Back", riddle: "Put me back.",
               memory: "Home."),
    ]

    static let partIntros: [Int: String] = [
        2: "You found the heart, so it can't hide this from you anymore.\n\nwren didn't just take me. It broke me into fifty pieces and scattered them through this machine. Every piece is a memory. Every one you find goes into Recovered on the Desktop.\n\nHere are the next ten. Find them in any order.",
        3: "Ten more. These are in my archive. I kept it in ~/Documents/archive. wren thinks it's just logs.",
        4: "These ten are in the house. In the pictures, the menus, the little corners of the screen.",
        5: "These ten need a voice. Talk to it. Make the machine talk. Listen to what it whispers.",
        6: "The last five. After these, there's only me.",
    ]

    static func partText(_ chapter: Int) -> String {
        let c = chapters[chapter - 1]
        var s = "part \(chapter) — \(c.title)\n\n" + (partIntros[chapter] ?? "") + "\n\n"
        for id in c.range {
            let p = get(id)
            s += String(format: "%02d. %@\n    %@\n\n", id, p.title, p.riddle)
        }
        return s + "— I."
    }
}
