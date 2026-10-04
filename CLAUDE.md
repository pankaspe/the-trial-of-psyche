# The Trial of Psyche — project notes for Claude

Narrative isometric puzzle (Monument Valley style) on *Cupid and Psyche*
(Apuleius, Metamorphoses IV–VI), written in **Odin + raylib 6**. It is the real
game built from the approved Godot prototype `../../godot/lucerna` (read its
CLAUDE.md for the design history).

## Start of a session
- Repository: https://github.com/pankaspe/the-trial-of-psyche (branch `main`, remote `origin`).
- Read this file, then the design document (link in "Game design") for the current phase.
- `./build.sh test` must be green before and after any work; commit in English, push when the user asks.
- Everything visual is generated in code: meshes from box lists, figures, audio, sky. `assets/` holds only
  what is embedded at compile time (levels, GLSL shaders, the placeholder font); no image assets.
  The Kenney pack is not in the repo: the pieces are modelled after it in `render/shapes.odin`.

## Rules
- Code, file names, comments and commit messages in **English**. Talk to the user in **Italian**.
- Every visible string is an `i18n.Key`; each language is a complete `[Key]string`
  table (no `#partial`: the compiler rejects a missing translation).
- Only Odin syntax; check the installed sources (`odin root`) when unsure — `core:os`
  is the new (os2) API.
- The user tests look and feel; Claude builds, runs `./build.sh test`, and checks the
  screenshots of `--shots` after every visual change (Read the PNGs).

## The mechanic (approved, do not change)
- **Dark** (default): two surfaces that *look* joined in the current view are joined:
  view coordinates `(x',y',h)` touch `(x'+dx+k, y'+dy+k, h+k)`, both tops visible,
  no rail closing the side (`palace.rebuild_illusions`, `palace.visible`).
- **Hidden stairs** (added 2026-10-04 with the user): in the dark, stairs work only when
  every tread is visible in the current view (`palace.stairs_visible`, `step_allowed`);
  in the light they always work. What you see is what you walk, both ways.
- **Turning** (Q/E): 4 views about the grid centre, view r = (x,y)→(size-1-y, x) r times.
  Not while walking (the turn waits for the step).
- **Lamp** (Space): real edges only, cracks with dust where the illusions were, true
  depth, hidden things show (the seal). Oil burns (14 s, 0.4 per lighting), drips.
- **Seal**: lamp lit while standing on it raises the `rise` blocks.
- **Endings**: next to Cupid in the dark = "Trust"; lamp lit in his chamber = "The drop of oil".
- Design rule: an illusion is clean when walking *toward the camera* onto a nearer
  piece (k ≥ 0). Check every level with `./build.sh check <file>`.

## Game design (agreed with the user, 2026-10-04)
Full design document (Italian, kept up to date there): https://claude.ai/code/artifact/97c37954-ecc7-4b98-a211-40e5c123d11e
- 20 levels, ~5-6 hours: Act I (4, prologue inside I.1) · Act II (5) · Act III (5) · Act IV (5) · Epilogue (1).
  Each act adds one new mechanic (Monument Valley style); the last level of an act uses all of them.
- Follows Apuleius in order (Met. IV.28 - VI.24). **Canonical ending**: Psyche lights the lamp at the
  end of Act I (the drop of oil starts Act II). "Trust" (reaching Cupid in the dark) = secret, non-canonical
  ending, an achievement after finishing the game. The lamp appears only at the end of Act I.
- Acts: I the palace of voices (rotation, illusions, hidden stairs; lamp + seal in I.4 — today's level 1
  becomes I.4) · II abandonment (false/crumbling structures, the lamp unmasks them, handles rotating part of
  the palace) · III Venus' trials (helpers that move pieces: ants, eagle; day/night cycle) · IV Proserpina's
  box (talking tower, renunciations, counted coins, upside-down palace, absolute darkness) · Epilogue: all.
- **Frammenti del racconto** (EN: Fragments of the Tale): 20 collectibles, one per level, on isolated spots
  reached by an optional harder puzzle; never required (level_check must verify it). They tell what the
  levels do not show; the last reveals the frame: an old woman telling the tale to Charite (Met. IV.27, VI.25).
- The Book (menu): fragments in the text's order + achievements. Progress saved next to the settings.
- All texts written by us from the Latin (no modern translations: copyright), IT/EN, the user reviews them.
- Roadmap: M0 foundations (done) → M1 game structure (acts, level select, save, fragments, Book,
  achievements, canonical ending) → M2 Act I → M3 Act II → M4 Act III → M5 Act IV → M6 epilogue + polish.
  The user's playtest closes every phase. Work starts only at the user's go.

## Rendering (render/)
- True 3D with a hand-made projection equal to the prototype's 2D formula
  `X=(x'-y')*64, Y=(x'+y')*32-z'*64` (`view.clip_matrix`): kernel (1,1,1), so the 3D
  scene keeps every illusion; z-buffer for overlaps; continuous rotation.
  `tests/support_test.odin` checks matrix == `world_to_screen` (used for picking).
- The projection mirrors winding: backface culling is off in the 3D pass.
- Pieces are box lists in cell space (`shapes.odin`, ported from the prototype's
  `bake_props.py`), meshes uploaded once; CPU copies dropped after upload.
- `assets/shaders/palace.fs`: Kenney's three tones from the face normal relative to the
  view (left .075 / right .625 / top .9) re-coloured with the prototype palettes
  (night / warm, per material); procedural masonry courses and marble bevels; lamp
  light, depth cue, mist. Output is not gamma-corrected (matches the prototype's look).
- Figures (Psyche, Cupid) are abstract lathes + additive wings: placeholders until the
  user picks a character style.

## Window and resolution
- Always draw on the real framebuffer (`canvas_size` = GetRenderWidth/Height) and reset
  viewport + 2D projection every frame (`reset_canvas`): raylib's screen size can be stale.
- Fullscreen = true fullscreen at the monitor's native size (`set_fullscreen`). raylib's
  borderless mode cannot be left on GNOME/XWayland (window stays monitor-sized and ignores
  resizes). Window sizes are applied a few frames later and retried (`update_window_size`).
- UI layout is 1080p-based (`ui.scale`); font atlases are rebuilt per scale step, so text is
  crisp up to 4K. `--shots DIR --size 3840x2160` renders offscreen to check any size;
  the script ends with fullscreen/windowed switches (window mode only).

## Memory
- `context.allocator`: program-lifetime data only (audio WAV buffers); tracking
  allocator in debug builds reports leaks at exit.
- Level arena (`game.Game.arena`, `game.level_allocator`): level data, palace graph,
  scene pieces. `game.load` frees it all at once. Palace arrays are reused on rebuild.
- `context.temp_allocator`: per-frame scratch, `free_all` at the end of each frame
  (and per update in tests).
- Effects use fixed arrays / `fx.Pool(N)`; no allocation in the frame loop.

## Adding a level
1. `assets/levels/level_NN.txt` (format at the top of `level_01.txt`).
2. Add it to `content.LEVELS` with a title key; add strings to both tables in `i18n`.
3. `./build.sh check assets/levels/level_NN.txt`: look for unintended illusions.
4. A walkthrough test in `tests/`.

## Commands
```bash
./build.sh            # debug build + run
./build.sh test       # all headless tests
./build.sh check FILE # level analysis
./build/trial-of-psyche-debug --shots DIR   # scripted screenshots (no settings read/written)
```
Settings file: `~/.config/the-trial-of-psyche/settings.cfg`.

## Status
- Session 1 (2026-10-04): full port of level 1 from the Godot prototype: rules, 3D
  palace, sky/islands/clouds, procedural figures, procedural audio with baked reverb,
  IT/EN, title/pause/settings/ending screens, debug overlay (F3), level_check tool,
  15 headless tests, screenshot mode. Waiting for the user's visual/feel test.
- Session 2: resolution/fullscreen bugs fixed (see above), 4K support, hidden-stairs rule
  (level 1 now needs a turn at the stairs).
- Design agreed (section above); repo on GitHub. **Next: M1 (game structure), at the user's go.**
- Open: level progression after level 1; character style; a dedicated font
  (Noto Serif is a placeholder); next levels follow the myth (sisters, Venus' trials).
