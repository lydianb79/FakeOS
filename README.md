<p align="center"><img src="Assets/AppIcon.png" width="200" alt="Fake OS icon"></p>

# Fake OS

A haunted fake macOS desktop built with Swift + Metal. Everything you see (the windows, files, Dock, menu bar, even the cursor) is drawn by the game. It reads no real files and touches nothing on your Mac.

## Run

```bash
swift run FakeOS                      # fullscreen
swift run FakeOS --windowed           # 1440×900 window for development
./build-app.sh && open dist/FakeOS.app
```

**⌘Q always quits the real game.**

## How it's built

- **Metal** draws everything. Each window, popup and banner is painted into a Core Graphics canvas and uploaded as a texture. Metal then draws those as quads, with rounded corners and soft shadows done as SDFs in the shader. The wallpaper is a procedural shader, and the frosted Dock and menu bar sample it. A post-process pass adds the glitches, chromatic split, static, the tear line, display brightness and the glowing writing that only shows in the dark.
- **AppKit** is used only for the borderless fullscreen window, input, text and SF Symbols.
- **AVAudioEngine** makes the procedural drone and static. Real system alert sounds are used for UI realism.

| File | What it does |
|---|---|
| `Renderer.swift`, `Shaders.swift`, `Canvas.swift` | Compositor, shaders, CG→texture |
| `World.swift` | Window manager, input routing, effects, endings |
| `Story.swift`, `Puzzles.swift` | Puzzle engine and the 50 puzzles, saves, scripted scares, ghost chat |
| `Spotlight.swift` | Spotlight search over the fake disk |
| `Finder`, `Terminal`, `ActivityMonitor`, `Windows` | Fake apps |
| `Desktop`, `Dock`, `MenuBar`, `Notifications` | Shell chrome |
| `FileSystem.swift` | Fake files and lore |
| `AppIcon.swift` | The app icon, drawn in code (Dock icon at runtime + `.icns` via `build-app.sh`) |

## The 50 puzzles

wren broke Ines into **50 pieces**. Each puzzle recovers one, saved as a memory in **Recovered** on the desktop (with an `INDEX.txt` checklist). They're grouped into six chapters, and each chapter opens when the one before it is complete. From chapter 2 on, Ines leaves the riddles as `part N.txt` in `~/.wren`. Progress saves automatically (Apple menu → *Erase All Progress…* starts over). Put Ines back with all 49 other pieces and you get the **Congratulations** screen.

<details>
<summary>Full solution (spoilers)</summary>

| # | Puzzle | Solution |
|---|---|---|
| **I** | **The Lights** | |
| 1 | Lights Out | Control Center → Display slider almost to zero |
| 2 | The Dotted Folder | Show hidden files (⌘⇧. or `ls -a`), open `~/.wren` |
| 3 | Thirty Seconds | Force-quit `wren` (Activity Monitor or `kill 1313`) |
| 4 | Heart | While wren is down, unlock `heart.lock` with `317` (the frozen clock) |
| 5 | Ask It Who It Is | In TextEdit, type "who are you" |
| **II** | **The Machine** | |
| 6 | Silence | Sound slider to zero |
| 7 | Old Habits | `history` |
| 8 | Whose Machine | `whoami` while wren is dead |
| 9 | Birthday | `cal` shows the 28th → `birthday.lock` = `28` |
| 10 | The Copy | Kill the fake `ines` process (pid 2811) |
| 11 | Fridge Magnets | `fridge.png` spells LUMEN → search "lumen" in Spotlight |
| 12 | MochiNet | Join Wi-Fi "MochiNet", password `mochi` |
| 13 | That Night | Click Finder, TextEdit, Terminal, Activity Monitor in the Dock, in that order |
| 14 | Count Them | Three people on the beach → `beach.lock` = `3` |
| 15 | Dreaming | Apple menu → Sleep |
| **III** | **The Archive** | |
| 16 | Encoded | `base64 -d note.b64` (in `~/Documents/archive`) |
| 17 | Backwards | `rev backwards.txt` |
| 18 | Buried | `grep ines wren.log` |
| 19 | Echo | `echo.lock` = `echo` |
| 20 | Lost Tooth | `find / -name tooth` |
| 21 | Call the Cat | `ping mochi` |
| 22 | Us | Open `us.png` in Trash → old_photos |
| 23 | Administrator | `sudo …` with password `wren` |
| 24 | The Manual | `man wren` |
| 25 | Awake | `uptime` |
| **IV** | **The House** | |
| 26 | What the Cat Sees | In `mochi.png`, click the eyes in the doorway |
| 27 | Handprint | In `IMG_3170.png`, click the handprint |
| 28 | By the Dock | In the desktop screenshot, click the figure |
| 29 | Power Source | Battery menu → Battery Settings… |
| 30 | Focus | Control Center → Focus |
| 31 | Three Taps | Click the menu-bar clock 3 times quickly |
| 32 | More Info | About This Mac → More Info… |
| 33 | Off and On | Apple menu → Restart… |
| 34 | All at Once | Drag a selection box around every desktop icon |
| 35 | Hide | Open 2+ windows and minimize them all |
| **V** | **The Voice** | |
| 36 | Where | Ask wren "where is ines" |
| 37 | Goodnight | Say "goodnight" |
| 38 | True Name | The installer in Downloads reveals HOLLOW → say "hollow" |
| 39 | Brave | Say "I'm not afraid" |
| 40 | What Time | Ask "what time is it" |
| 41 | Echo My Name | `echo ines` |
| 42 | Out Loud | `say ines` (really speaks) |
| 43 | Whispers | Open the Wi-Fi menu 5 times |
| 44 | Catch One | Click a wren notification |
| 45 | Three Deaths | Kill wren 3 times in total |
| **VI** | **Put Back** | |
| 46 | Fifty | `Recovered/final.lock` = `50` |
| 47 | Lights On | Display slider all the way up |
| 48 | Look at Me | Open the Trash |
| 49 | Say It Plainly | `ls ~/.Trash` |
| 50 | Put Back | Double-click `ines.self` in the Trash → Put Back → **Congratulations** |

Emptying the Trash at any point after the heart is unlocked triggers the bad ending, which erases your progress.
</details>

Dev helpers: `FAKEOS_SCENE=windows|dark|chat|ending|spotlight|congrats` stages a scene, `FAKEOS_SCENE=selftest` drives all 50 puzzles through the real game hooks and prints `SELFTEST RESULT …`, and `FAKEOS_FRESH=1` ignores saved progress.
