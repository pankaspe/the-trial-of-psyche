# Building and checking The Trial of Psyche

How to build the game from source on every system, run the tests, and analyse or
photograph a level. For players who only want to play, the
[Linux download](https://github.com/pankaspe/the-trial-of-psyche/releases/tag/v0.9.0-beta)
is enough.

The game is plain [Odin](https://odin-lang.org) and [raylib 6](https://www.raylib.com).
Everything else (meshes, sky, music, every sound) is generated in code, and the levels,
shaders and fonts are embedded in the binary at compile time: the built executable
runs on its own, from any folder.

> **Status of the platforms.** Linux x86_64 is the platform the game is made and
> tested on. Windows, macOS and Linux on ARM should build, since Odin and raylib
> support them, but **nobody has tried yet**. If you do, a
> [playtest note](https://github.com/pankaspe/the-trial-of-psyche/issues/new?template=playtest.yml)
> on how it went (even "it doesn't build", with the error) helps a lot.

## 1. Requirements

All systems:

- **Odin dev-2026-10 or newer.** Older releases lack raylib 6 and parts of `core:os`
  the game uses. Odin bundles raylib 6 in `vendor:raylib`: there is nothing else to
  download.
- A GPU with **OpenGL 3.3**.
- Git, to get the source.

Per system:

| System | What to install | Notes |
| --- | --- | --- |
| Linux x86_64 / ARM64 | Odin ([install](https://odin-lang.org/docs/install/)), clang, the X11 development files | `libx11-dev` (Debian/Ubuntu), `libX11-devel` (Fedora), `libX11-devel` (Void). Odin's raylib ships builds for `linux` and `linux-arm64`. |
| Windows 10/11 (x64) | Visual Studio Build Tools (the "Desktop development with C++" workload), then Odin | Build from the **x64 Native Tools Command Prompt**, so Odin finds the MSVC linker. |
| macOS (Apple Silicon or Intel) | Xcode Command Line Tools (`xcode-select --install`), then Odin | A package manager's Odin may be older than dev-2026-10: check `odin version`, or build Odin from source. |

Check the install with `odin version` and `odin root` (the folder whose
`vendor/raylib` holds raylib for your system).

## 2. Build and run

```sh
git clone https://github.com/pankaspe/the-trial-of-psyche.git
cd the-trial-of-psyche
```

**Linux and macOS**

```sh
odin build src -out:trial-of-psyche -o:speed
./trial-of-psyche
```

**Windows** (in the x64 Native Tools Command Prompt)

```bat
odin build src -out:trial-of-psyche.exe -o:speed -subsystem:windows
trial-of-psyche.exe
```

`-subsystem:windows` opens the game without a console window; leave it out to see
the log while you play.

Saves and settings go to the system's settings folder, under `the-trial-of-psyche`:
`~/.config/` on Linux, `%APPDATA%` on Windows, `~/Library/Application Support/` on
macOS. Five save slots (`save1.sav` … `save5.sav`), sealed against hand edits, and
`settings.cfg`, a plain text file.

### The build script (Linux, macOS, Git Bash)

`build.sh` wraps the commands the development uses; every build passes
`-vet -strict-style`, so warnings are errors.

| Command | What it does |
| --- | --- |
| `./build.sh` | debug build into `build/trial-of-psyche-debug`, then runs it |
| `./build.sh debug` | debug build only (bounds checks, a memory leak report at exit) |
| `./build.sh release` | optimised build into `build/trial-of-psyche` |
| `./build.sh test` | every headless test |
| `./build.sh check FILE` | the level analysis (section 4) |
| `./build.sh dist VER` | the Linux release archive (section 6) |

On Windows without Git Bash, run the same Odin commands by hand: they are one line
each in the script.

## 3. Tests

```sh
./build.sh test
# or: odin test tests -vet -strict-style -all-packages
```

The tests open no window. They cover the rules of the world (illusions, hidden
stairs, the lamp, seals, handles, the time of day, the eagle, the flip, the ferry),
the walk and the pad's steering, the save file, settings, the translations (every
text in both languages) and the audio synth. Above all they **play every level**:
Act I through hand-written walkthroughs, every other level and diorama through the
solver's plan, start to exit, checking that each fragment of the tale is reachable
and never required. A green run means every level can still be finished.

## 4. Analysing a level

Levels are text files in `assets/levels/` (`level_NN.txt`, one per slot of
`src/content`). The format is documented in the comment at the top of
`assets/levels/level_04.txt`: one command per line (`size`, `column`, `block`,
`stairs`, `exit`, `sigil`, `handle`, `pomegranate`, `ferry`, …).

```sh
./build.sh check assets/levels/level_07.txt              # the whole report
./build.sh check assets/levels/level_20.txt --diorama 1  # one diorama (0 = the first)
./build.sh check assets/levels/level_07.txt --brief      # one line per solve
./build.sh check assets/levels/level_07.txt --try FILE   # weigh candidate changes
```

The report lists:

- how much of the palace Psyche reaches, in the light and in the dark, view by view;
- the **illusions** of every view (surfaces that look joined, so they are) and which
  stairs work in the dark in each view, to spot unintended shortcuts;
- the solver's **plan with the fewest decisions** (turns, lightings, handles, the time
  of day, flights, overturns, crossings), how many states the level has and how many of
  them are **dead ends**;
- the oil left along the plan, for levels with the lamp;
- **every piece taken out in turn**: a level still solvable without a handle, sundial,
  ram, eagle, ferry or cave has a piece that does nothing, or a way round it;
- the fragments of the tale: reachable, optional, and what they cost;
- a visual lint: floating or colliding props, too many flames, a scroll a click
  would miss.

The exit status is 1 when a level is broken (a line the loader refuses, an exit
the solver can't reach, a fragment unreachable or required, a lint error), so the
tool fits a script.

`--try FILE` weighs candidate decorations or edits without touching the level: each line
of FILE is a variant (several level lines joined by `;`, `under LINE` for the world
under the palace). Each one is reported as refused by the loader, neutral, or with what
it changes.

## 5. Shots and recordings

The game has a scripted mode that plays by itself, saves PNGs and quits. It never
reads or writes your saves or settings. It opens a window, so it needs a desktop
session. Create the output folder first.

```sh
./build.sh release
mkdir -p shots
./build/trial-of-psyche --shots shots --size 1600x900 --level II.4            # a tour of the level
./build/trial-of-psyche --shots shots --level II.4 --survey                   # the four views, band by band
./build/trial-of-psyche --shots shots --level III.5 --diorama 2 --plan        # the solver's plan, a shot per decision
./build/trial-of-psyche --shots shots --level I.3 --plan --record             # every frame at 60 fps, for a video
```

| Option | Meaning |
| --- | --- |
| `--shots DIR` | the scripted mode, PNGs into DIR; without `--level` it walks the menus and plays I.4 |
| `--level ID` | the level (`I.1` … `IV.6`, `E`) |
| `--diorama N` | start at that diorama (0 = the first) |
| `--plan` | play the solver's plan; `--go-on` plays on into the next level |
| `--survey` | the four views of every height band |
| `--record`, `--record-from N`, `--record-to N` | every frame (or a window of frames) plus a log of the sounds |
| `--file PATH` | load that level's slot from a file: a design in progress |
| `--size WxH`, `--quality low\|medium\|high\|ultra`, `--no-ui` | the picture |
| `--pad xbox\|playstation\|nintendo` | the HUD's button glyphs |

`LANG=en_US.UTF-8` gives the English texts (the language follows the system).

## 6. Release archives

`./build.sh dist 0.9.0-beta` builds the Linux archive
`build/dist/the-trial-of-psyche-VER-linux-x86_64.tar.gz`: the binary, a README for
players, the license and the fonts' licenses. It links with
[zig](https://ziglang.org) against glibc 2.29, so the binary runs on older
distributions than the build machine; `zig` must be on the PATH. A plain
`./build.sh release` binary needs the build machine's glibc: don't ship it.

There are no Windows or macOS archives yet. Built natively on those systems as above,
the executable is self-contained (raylib is linked statically). A macOS build would
still need an `.app` bundle and at least an ad-hoc signature (`codesign -s -`), and
without Apple's notarization Gatekeeper asks the player to open it from the context
menu. An unsigned Windows `.exe` gets a SmartScreen warning.

## 7. Where things are

| Path | What |
| --- | --- |
| `src/` | the game: `game` (rules and state), `palace` (walk graph, illusions, solver), `level` (loader, props, biomes), `render`, `audio`, `ui`, `input`, `i18n`, `progress`, `settings`, `content` (level slots, fragments of the tale) |
| `assets/` | what is embedded at compile time: levels, GLSL shaders, fonts |
| `tests/` | the headless tests |
| `tools/level_check` | the level analysis |
| `tools/sound_board` | writes every generated sound, bed and mood as WAV |
| `tools/dist` | the release archive's README and the zig linker wrapper |
