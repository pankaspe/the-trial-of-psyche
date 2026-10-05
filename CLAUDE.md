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
- **Endings**: lamp lit in Cupid's chamber = "The drop of oil" (canonical, closes Act I); next to
  him in the dark = "Trust", only once the game is finished (`game.trust_allowed`), otherwise
  Psyche doubts (`V_Doubt`). Other levels end at an `exit` cell.
- **Lamp only where carried**: the `lamp [par]` command gives Psyche the lamp (from I.4 on);
  without it the oil gauge and lamp button are hidden.
- Design rule: an illusion is clean when walking *toward the camera* onto a nearer
  piece (k ≥ 0). Check every level with `./build.sh check <file>`.

## Act II mechanics (M3, 2026-10-05; `palace.flipped`, `part_rot`)
- **Crumbling** (`crumble`): a cracked block falls (for good) once Psyche steps off it; what
  falls stops hiding things, so seams and stairs can appear. Paths avoid cracked stones unless
  there is no other way (`find_path` tries a careful search first).
- **Phantom** (`phantom`): real only in the dark (walk, hide, join by illusion); the lamp's
  light within `palace.TRUTH_RADIUS` (2.5) of her feet dissolves it for good; the lamp cannot
  be lit over one (`can_light`). Pale, misty material; thin in the light.
- **Veiled** (`veiled`): absent in the dark; the lamp shows it as a golden ghost, and within
  the same radius makes it real for good. Never appears where Psyche stands.
- **Handles** (`part px py ... end`, `handle x y h [n]`): standing on a handle, a click on
  Psyche (or F) turns the part a quarter, counter-clockwise from above (phase `Mechanism`);
  parts carry a bronze inlay. Handles are never on a part (Psyche never rides one).
- **Braziers** (`rest x y h`): lit by passing (one on the start cell is lit already); R brings
  back Psyche and the palace as they were at the last one; R again restarts the level.
- **New mechanic card** (`mechanic name` in the level, user's request 2026-10-05: "mi serve
  qualcosa che spieghi la nuova meccanica, dobbiamo dargli importanza"): the level that
  introduces a mechanic opens with a card "Nuovo: …" (name + two lines), the game paused, and
  its pieces pulse with golden diamonds while it is read and a few seconds after; the tutorial
  hint stays as a reminder. Not shown again on a restart.
- Changes are permanent, so levels have dead ends: `palace.solve` (tools and tests) searches
  every state (cell, view, lamp, changed blocks, part turns) and counts the dead ones.

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

## Game structure (M1, `content`, `progress`)
- `content.LEVELS`: the 20 slots (id "I.1".."E", act, title, fragment key, citation, source);
  a slot with `source = ""` is not built (level select shows it, nobody plays it).
  `BOOK_ORDER` = fragments in Apuleius' order. Act label/title/card keys per `content.Act`.
- `progress`: completed levels, fragments, achievements in `progress.cfg` next to the settings,
  stored by level id. Pure rules (`collect_fragment`, `complete_level` return the unlocked
  achievements); a level is open when built and every earlier built level is finished.
  `--shots` neither reads nor writes it.
- Flow (`main.odin`): Title → (act card if the level opens an act) → Play → ending card
  (Continue / Retry / Menu). Continue onto an unbuilt level shows its act card, then the title.
- Fragment: `fragment x y h` in the level; picked up by walking onto it (`game.fragment_new`
  event → app saves); collected ones show faint. `palace.check_fragment` (level_check, tests):
  reachable and never required.

## Adding a level
1. `assets/levels/level_NN.txt`, NN = slot number 01..20 (format at the top of `level_04.txt`).
   Texts per cell: `voice x y h key`, `hint x y h key` (on the start cell: when the level begins);
   `outro key` = the ending card at the exit. Keep the layout centred in the grid (it turns about the centre).
2. Point the slot's `source` in `content.LEVELS` at it (titles and fragments are already in `i18n`).
3. `./build.sh check assets/levels/level_NN.txt`: unintended illusions, fragment reachable and optional.
   For a palace that changes it also solves the level: the plan with the fewest decisions,
   states and dead ends, parts that would turn into the palace. Read the plan: a short one
   means a shortcut. Translating a whole layout keeps every illusion (handy to recentre it).
4. A walkthrough test in `tests/` (`act1_test.odin` is the model); Act II levels are covered
   by `act2_levels_solve_and_play` (the solver's plan played through the game).
5. `--shots DIR --level ID` tours it: act card, the four views, lamp, fragment, exit, end card;
   add `--plan` to play the solver's plan with a shot after every decision.
- Occlusion across four views is hard to foresee: a seam from a high near piece goes down only
  from its view-mx/my edges to a farther, lower piece. Reserve the cover cells of a seam's foot
  (view offsets (k,k,k-1), (k,k,k), (1+k,k,k), (k,1+k,k)) and close stray seams with
  parapets on the far piece rather than on the path.

## Commands
```bash
./build.sh            # debug build + run
./build.sh test       # all headless tests
./build.sh check FILE # level analysis
./build/trial-of-psyche-debug --shots DIR   # scripted screenshots (no settings read/written)
./build/trial-of-psyche-debug --shots DIR --size 1600x900 --level I.2   # tour of one level
./build/trial-of-psyche-debug --shots DIR --level II.3 --plan   # the solver's plan, a shot per decision
```
Settings file: `~/.config/the-trial-of-psyche/settings.cfg`.

## Status
- Session 1 (2026-10-04): full port of level 1 from the Godot prototype: rules, 3D
  palace, sky/islands/clouds, procedural figures, procedural audio with baked reverb,
  IT/EN, title/pause/settings/ending screens, debug overlay (F3), level_check tool,
  15 headless tests, screenshot mode. Waiting for the user's visual/feel test.
- Session 2: resolution/fullscreen bugs fixed (see above), 4K support, hidden-stairs rule
  (level 1 now needs a turn at the stairs).
- Design agreed (section above); repo on GitHub.
- Session 3: **M1 done and playtested by the user (approved)**: 20 level slots in 4 acts +
  epilogue, level select, save file, act cards (Act I = the oracle prologue), fragments of the
  tale (all 20 texts drafted IT/EN, to be reviewed), the Book (fragments + achievements),
  achievements with corner notices, canonical ending with Continue, secret Trust ending after the
  game, levels without lamp, `exit` goal. The prototype level is now I.4 (`level_04.txt`), its
  fragment on the west pillar. Picking a fragment pauses the game until Enter; Cupid's lines
  queue instead of cutting each other off. 23 tests. Commits are local, not pushed yet.
- Testing tip: a collected fragment shows faint and cannot be taken again; to replay from
  scratch delete `~/.config/the-trial-of-psyche/progress.cfg`.
- Session 4 (2026-10-05): **M2 done and approved by the user** ("adesso è perfetto"). Act I is
  playable end to end:
  - I.1 Zephyr's Crag (walk, first turn) opens with the **prologue cutscene** (`prologue x y h`,
    `game/prologue.odin`, a timeline): the oracle, the procession of veiled mourners with torches
    climbs the crag, leaves Psyche and puts the torches out, Zephyr's breath, "press any key" (a key
    skips it, a restart skips it; it replaces the Act I card). I.2 The Invisible Palace (one seam per
    view: 0, 1, 3; fragment from view 2; starts on a meadow), I.3 The Sisters on the Crag (two hidden
    stairs, a decoy tower; fragment on the second tower), I.4 as before. Each has an exit or ending,
    fragment, intro/outro and a walkthrough test.
  - Exits: a column of light, floor rings and a spiral of wind; at the end the wind lifts Psyche.
  - Text: prologue -> one `intro` line per level -> outro card (`outro`); no mid-level voices (only
    V_Doubt beside Cupid). Each new mechanic taught once by a tutorial hint that stays until done
    (`game.learn`): move/turn/Esc-R in I.1, illusions I.2, hidden stairs I.3, lamp, oil (the gauge
    pulses) and seal I.4. Controls legend only in the pause menu. Fragment and ending cards darken
    the game (`ui.focus_shade`).
  - Sound: no chime on lines or tap on clicks, quieter steps/turns/seams; a wind sound for exits.
  - Look: Lawn material (`lawn x y z`, grass, earth, flowers); mourner material; decoration set:
    slim `arch`, corner `vase`, unlit wall `sconce`; slender battlements; no windows (disliked).
  - Tools: `--shots DIR --level ID` tours a level; README has screenshots (`docs/screenshots/`).
  - 27 tests. Pushed to GitHub.
- Text rule (user, 2026-10-05): little text, so the gameplay comes first: prologue -> one intro line
  per level -> outro at the end; mechanics explained once, by tutorial hints.
- Decoration rules (user: readable, not cluttered): small, few objects; never hide Psyche's start.
  Blocking props must not sit on a needed cell, edge props must not close a side an illusion uses;
  compare `./build.sh check` before and after (same illusions, same goals).
- Session 5 (2026-10-05): **M3, Act II built, waiting for the user's playtest.** Mechanics above;
  solver (`palace/solve.odin`), braziers, `--plan` shots, 31 tests.
  - II.1 Cupid's Flight (crumbling: bridge; break the stone that hides the seam; choose the
    view before leaving a cracked stone; lower the exit column's cap; fragment: lower a column
    twice). II.2 The River and Pan (phantoms: stepping stones; the barring block; light from the
    cliff ledge, out of reach of the river stone; fragment: use the barring block's top first).
    II.3 The Sisters' Crag (veiled: bridge in the light; climb before revealing the stone that
    hides the seam's foot; the sisters' phantom road vs the veiled true road; a revealed stone
    as a seam; fragment on the precipice before the light). II.4 The Temple of Ceres (handles:
    a turning bridge; an L floor joining two doors at a time, two handles and a trip over a
    high stone). II.5 The Temple of Juno (all: break to see, reveal the high stone before
    turning the phantom arm toward the light, the floor, a handle on a cracked stone).
  - Solver plans: 25/24/18/27/28 steps; the levels are probably 6-15 minutes each, shorter than
    the 15-18 minute target: to extend after the playtest if the user wants.

## Next session: M3 playtest, then M4 — Act III (at the user's go)
- Fix what the user's playtest of Act II finds (difficulty, readability of phantom/veiled
  stones, handles), maybe lengthen levels; then Act III, Venus' trials (helpers that move
  pieces, day/night), same workflow.
- Open: character style; a dedicated font (Noto Serif is a placeholder); the user's review of the
  texts (M1 drafts: fragments, act cards, titles, achievements; Act I lines: table in the design
  document).
