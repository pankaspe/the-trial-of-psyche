# The Trial of Psyche — project notes for Claude

Narrative isometric puzzle (Monument Valley style) on *Cupid and Psyche* (Apuleius,
Metamorphoses IV–VI), in **Odin + raylib 6**, built from the Godot prototype
`../../godot/lucerna`. This file is the current state; the history is in git.

## Start of a session
- Repo: https://github.com/pankaspe/the-trial-of-psyche (`main`, remote `origin`).
- `./build.sh test` green before and after any work; commit in English; push when the user asks.
- Design document (Italian): https://claude.ai/code/artifact/97c37954-ecc7-4b98-a211-40e5c123d11e —
  **do not update it for now** (the user, 2026-10-09: level counts still moving, see Roadmap).

## Rules
- Code, file names, comments, commits in **English**; talk to the user in **Italian**.
- Every visible string is an `i18n.Key`; each language is a complete `[Key]string` table.
- Only Odin syntax; check the installed sources (`odin root`) when unsure (`core:os` is os2).
- Everything is generated in code: meshes from box lists, figures, sky, almost all sound.
  `assets/` holds only what is embedded at compile time (levels, GLSL, fonts, footsteps).
  Level files are `#load`ed: **rebuild before taking shots** after editing a level.
- The user tests look and feel; Claude builds, tests and checks `--shots` PNGs after every
  visual change. Sound can't be heard by Claude: measure it (peaks, brightness, attacks).
- Work **one level at a time**: build, the user plays and judges, then the next.
- Text: little of it, gameplay first: a cutscene opens each act, one `intro` line per level, an
  `outro` card at the end; each mechanic taught once by a tutorial hint (`game.learn`).
- Decoration: readable, few small objects; never hide the start; blocking props off needed cells,
  edge props never closing a side an illusion uses (compare `./build.sh check` before/after).
- The user dislikes a camera that moves sideways: no levels wider than the screen (tall levels
  with `tier` bands are fine).

## The rules of the world (approved, do not change)
- **Dark** (default): surfaces that *look* joined in the current view are joined: view cells
  `(x',y',h)` and `(x'+dx+k, y'+dy+k, h+k)`, the touching edges of both tops visible (a top half
  covered by a cube beside the diagonal still joins across its uncovered half), no rail on either
  side (`palace.rebuild_illusions`, `edge_visible`). Clean illusions run toward the camera (k ≥ 0).
- **Hidden stairs**: in the dark stairs work only when every tread is visible in the current
  view (`stairs_visible`, `step_allowed`); in the light always.
- **Turning** (Q/E): 4 views about the grid centre, view r = (x,y)→(size-1-y, x) r times; waits
  for the step.
- **Lamp** (1 / L / right click), from I.4 on (`lamp [par]`): real edges only, cracks where the
  illusions were, true depth, hidden things show. Oil (`oil s`, default 14 s, 0.4 per lighting).
- **Seals**: up to 4 (`sigil` lines in order); the lamp lit on the n-th raises its `rise ... n`.
- **Veiled** (`veiled x y z [opt]`): absent in the dark, a golden ghost in the light, real for good
  within `TRUTH_RADIUS` 2.5 of her feet (never under her).
- **Handles** (`part px py … end`, `handle x y h [n]`): standing on one, 2 / F / a click on Psyche
  turns part n a quarter, counter-clockwise from above. Never on a part. Parts must not collide in
  any combination (level_check); same-pivot square rings never do.
- **Caves** (`cave x y h dir`, paired in file order): a 2.4 s passage, entered only on purpose with
  Space at the mouth; `find_path` never goes through one.
- **Braziers** (`rest x y h`): R tap = back to the last one lit (palace as it was), hold = restart.
- **Endings**: lamp lit beside Cupid (I.4) = "The drop of oil" (canonical); beside him in the dark =
  "Trust", only once the game is finished. Other levels end at `exit`.
- **Mechanic card** (`mechanic veiled|handle`): presented once at the level's first start (also
  after its cutscene), its pieces glowing.
- **Candelabra** (`candelabrum x y h dir [lit]`): decoration that marks where light matters; unlit
  ones catch the flame near the lit lamp. Rules and solver ignore them.
- Removed for good (in git history): crumbling and phantom stones, the following camera
  (`follow`), wind gusts, the post-processing visual styles.

## Acts and mechanics
- **Two new mechanics per act**, all used in the last level; other levels deepen, never teach.
  Act I: turning (with hidden stairs) and the lamp. Act II: veiled stones and handles.
  Acts III, IV: designed when their first level comes (design-doc ideas: III helpers that move
  pieces, ants, eagle, day/night; IV the talking tower, renunciations, coins, darkness).
- The game may be deliberately hard; an act's last levels are real puzzles.
- **The first level of every act opens with a cutscene** (user, 2026-10-09).
- Each level is a place that fits its title (sky, ranges, light, props, sound bed).
- Fragments of the tale: one or more per level (max 4), on isolated optional spots; level_check
  proves them reachable and never required. The last reveals the frame (the old woman, Charite).

## The levels (19 slots: I ×4, II ×4, III ×5, IV ×5, E; `content.LEVELS`)
Act I and II are built; all approved and pushed except II.2 and II.4 (waiting for the playtest).
- **I.1 Zephyr's Crag** (`crag_sunset`): the Oracle cutscene (`prologue x y h`), walk, first turn.
- **I.2 The Invisible Palace** (`dusk`): one seam per view; fragment from view 3.
- **I.3 The Sisters on the Crag** (`night_candles`, 13×13): three hidden stairs, three seams; two
  fragments on the sisters' statues.
- **I.4 The Lamp and the Razor** (`deep_night`, 16×16): the lamp under a portico whose columns hide
  the stairs; the seal raises a bridge; view 0 to Cupid's chamber; candelabra along the lamp's path.
- **II.1 Cupid's Flight** (`forest_night`, 16×16): opens with the **Flight** cutscene (`flight x y h`
  = the cypress: Cupid crosses the sky with Psyche on his leg, she drifts down like a leaf, he goes
  over the cypress into the stars). Veiled planks and caps, a trap, a hidden seal; Cupid speaks
  from the cypress at the end. Introduces veiled stones.
- **II.2 The River and Pan** (`river_dawn`): a breather; two sections joined only by a cave; veiled
  planks, a seal; fragment on a river rock.
- **II.3 The Sisters' Crag** (`crag_day`, size 11, tall: three `tier` bands): a spiral climb turned
  by handles (introduces them); 98-step plan, 14 handles; no lamp.
- **II.4 The Temple of Ceres and Juno** (`temple_dusk`, 15×15; the old II.4 and II.5 merged): a sacred
  pool, two square rings about the altar (same pivot), balustrades on the rings' inner edges; the
  porch and the outer SE pillar turn the middle ring, the middle NW pillar the outer one; Juno's and
  Ceres' seals raise the middle ring's missing pillars; one veiled stone; the last step to the altar
  is an illusion from a balcony. Plan: 101 steps, 1 turn, 3 lightings, 11 handles, 0 dead ends.
  Four fragments (II.4, II.4b, II.4c, II.4d) on pedestals reached by illusions.
- Texts still to review by the user: II.3b, II.4b, II.4d, the Flight captions (`Fl_*`), every
  fragment, act card and title (M1 drafts).

## Rendering (`render/`)
- True 3D with the prototype's projection `X=(x'-y')*64, Y=(x'+y')*32-z'*64` (`view.clip_matrix`,
  kernel (1,1,1): every illusion survives); z-buffer; continuous rotation; no backface culling.
- Pieces are box lists (`shapes.odin`, after Kenney's prototype tiles), uploaded once.
- `palace.fs`: Kenney's three tones re-coloured per material and setting (night / sunset
  `daylight` / `gloom` / `moonlight`), masonry and marble detail, lamp light, candles, depth, mist.
  Materials: marble, masonry, foliage, bronze, figures, lawn, rock, wood, cave void.
- Settings (`setting name`, `render/setting.odin` `LOOKS`, bed in `SETTING_BED`): night,
  night_candles, deep_night (clouds over the moon), dusk, crag_sunset, forest_night, river_dawn,
  crag_day, temple_dusk. Sky, orb, stars, parallax ranges (`ridges.fs`, closing over a full turn),
  clouds, mist, water colour.
- Cutscenes are filmed by `game.cine` (letterbox, look-up, zoom, focus on Psyche).
- No post-processing. **Graphics quality** (`settings.Quality`, live): Low = canvas 0.67×, Medium =
  canvas 1×, High (default) = straight to the screen with MSAA 4× (always requested), Ultra = canvas
  2× (supersampling, long side ≤ 8192). `render/post.odin` also frosts the glass settings sheet.
  Offscreen shots have no MSAA.
- Figures (Psyche, Cupid) are abstract lathes + additive wings: placeholders until the user picks
  a character style.

## Sound (`audio/`)
- Direction: soft, dreamy, meditative ("come un sogno"), never agitated.
- Music: generative per act (`generative.odin`, live in the mixer `music.odin`): pads, a
  Karplus–Strong lyre, a flute, glass bells, drone, an 8.5 s stereo hall. Moods (`ACT_MOOD`):
  Title (Psyche's theme), Palace A minor (lyre leads), Abandonment G minor (the flute leads alone),
  Trials D minor (lyre and flute answer), Underworld E Phrygian (a low slow flute).
- Beds per setting (seamless loops); duck under cards; the music is veiled in the dark when she
  carries the lamp.
- Effects (`synth.odin`, on a worker thread, stereo): soft attacks, highs rounded (`soften`), long
  `DREAM` reverb; a synthesised `flute` in `Good` (the arpeggio), `Wind` (exits, flight), `Reveal`.
  Footsteps recorded (Kenney CC0), softened into a small room (`step_take`). In-key effects follow
  the act's key. `tools/sound_board` writes every effect, bed and 40 s of each mood as WAV.

## Interface (`ui/`)
- Style "lamplight", squared: gold-cornered cards, fonts Mystery Quest (titles) and Cormorant
  Garamond (text), acts as ──── ATTO I ────. Title screen with the lamp's side darkened.
- Skills sidebar (1 lamp with its oil notches, 2 handle, locked slots), diorama buttons (Q, E, R
  with the hold ring), Space card for the action of the place, tutorial cards, keys badge.
- Settings: a dark-glass sheet with tabs (General, Graphics, Audio, Accessibility); the game stays
  visible on the Graphics tab. Accessibility: HUD size, skill labels, hold time / R twice, reduce
  motion, endless oil.
- Window: always draw on the real framebuffer (`canvas_size`, `reset_canvas`); true fullscreen at
  native size (borderless can't be left on GNOME/XWayland); 1080p-based layout, crisp up to 4K.

## Code structure
- `content`: level slots, fragments (`FRAGMENTS`, ids stable for the save), `BOOK_ORDER`, skills.
- `progress`: completed levels, fragments, achievements in `progress.cfg` (by id; unknown ids
  ignored). Delete it to replay from scratch. `--shots` never reads or writes it.
- Flow (`main.odin`): Title → act card or cutscene (first level of an act) → Play → ending card
  (Continue / Retry / Menu); exits fly through the veil into the next level's arrival; the end of an
  act goes to black.
- `palace`: the walk graph, illusions, paths; `palace/solve.odin`: every state (cell, view, lamp,
  changed blocks, part turns, seals), plan with the fewest decisions, dead ends, `oil_left`.
- Memory: level arena (freed by `game.load`), per-frame `temp_allocator`, fixed pools for effects.

## Making a level
1. `assets/levels/level_NN.txt` (NN = slot), format at the top of `level_04.txt`; point the slot's
   `source` at it. Keep the layout centred (it turns about the grid centre).
2. `./build.sh check FILE`: illusions per view (and once the palace is whole), stairs visible per
   view, the solver's plan (a short plan = a shortcut), dead ends, oil left, fragments reachable and
   optional, visual lint (`check_props`: floating props, collisions in every part position, too many
   flames), scroll clicks. For exploration, scratch scripts that generate variants and scan them with
   `build/level_check` worked well (II.4); then edit the file by hand.
3. Occlusion tips: a seam from a high near piece goes down only from its view-mx/my edges; reserve
   the cover cells of a seam's foot; close stray seams with rails on the far piece, not on the path.
4. Tests: Act I has walkthrough tests (`act1_test.odin`); Act II levels are played from the solver's
   plan (`act2_levels_solve_and_play`).
5. Shots: `--level ID` (a tour), `--survey` (the four views per band), `--plan` (a shot per decision,
   and the cutscene every 1.5 s), `--record` (60 fps video + `sounds.txt`), `--no-ui`,
   `--quality NAME`, `LANG=en_US.UTF-8` for English.

## Commands
```bash
./build.sh            # debug build + run
./build.sh release    # optimised build (use it for many shots or videos)
./build.sh test       # all headless tests
./build.sh check FILE # level analysis
./build/trial-of-psyche-debug --shots DIR --size 1600x900 --level II.4 [--plan|--survey]
./build/trial-of-psyche --shots build/video/i3 --size 1920x1080 --level I.3 --plan --record
./build/video_audio effects build/video/i3/sounds.txt build/video/i3.wav
tools/make_short.sh i1 180 300 i3 60 420 i4 1260 357   # a YouTube Short from recorded segments
```
Settings: `~/.config/the-trial-of-psyche/settings.cfg`.

## README and license
- The README presents the game (8 screenshots in `docs/screenshots/`, Ultra, English UI), badges in
  the game's colours (violet label, gold value, `for-the-badge`). Linux build only for now.
- License **GPL-3.0** (`LICENSE`); fonts OFL, Kenney's material CC0.

## Roadmap
- **Next**: the user plays the new II.4 (and II.2, II.1's cutscene); then the open texts; then
  **Act III**, level by level, its first level with a cutscene and its two new mechanics designed
  then.
- Level counts not final: Act III probably **4** levels, the last act **5** (user, 2026-10-09). Ask
  before dropping slots; don't touch the design doc until it settles.
- Open: character style; per-place one-shot sounds in the beds; positional pan of events.
