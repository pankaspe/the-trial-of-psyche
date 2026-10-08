# The Trial of Psyche — project notes for Claude

Narrative isometric puzzle (Monument Valley style) on *Cupid and Psyche*
(Apuleius, Metamorphoses IV–VI), written in **Odin + raylib 6**. It is the real
game built from the approved Godot prototype `../../godot/lucerna` (read its
CLAUDE.md for the design history).

## Start of a session
- Repository: https://github.com/pankaspe/the-trial-of-psyche (branch `main`, remote `origin`).
- Read this file, then the design document (link in "Game design") for the current phase.
- `./build.sh test` must be green before and after any work; commit in English, push when the user asks.
- Everything visual is generated in code: meshes from box lists, figures, sky. `assets/` holds only
  what is embedded at compile time (levels, GLSL shaders, the placeholder font,
  the recorded footsteps in `assets/sfx`); no image assets.
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
  view coordinates `(x',y',h)` touch `(x'+dx+k, y'+dy+k, h+k)`, the touching edge of both
  tops visible, no rail closing the side (`palace.rebuild_illusions`, `palace.edge_visible`).
  Refined 2026-10-08 (the user got stuck on tiles that looked joined): a top half covered by a
  cube beside the diagonal still joins across the edges of its uncovered half. Checked on
  every level: I.3 lands one tile further on the same terrace; I.4 got a rail on the fragment
  pillar (3 11 6 my) against a jump past the four-pillar chain; II.1 a log on the ledge.
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

## Mechanics per act (user, 2026-10-06: decided)
- **Two new mechanics per act, eight in all**, every one used in the final level. A level is
  never a tutorial of its own: after an act's two introductions its other levels only deepen.
  Act I: rotation (with the hidden stairs, found by intuition) and the lamp (light on/off).
  Act II: veiled stones and handles (crumbling dropped, 2026-10-08). Acts III, IV: two each,
  designed when their first level comes.
- The game may be deliberately hard (not as relaxed as Monument Valley): the last levels of an
  act are true puzzles.
- **Act II plan** (revised 2026-10-08): II.1 veiled stones with the lamp, already a real puzzle ·
  II.2 (to rework: today built on crumbling) · II.3 handles (today's II.4 handle level) · II.4 and
  II.5 two real puzzles using all four: rotation, light, veiled stones, handles.
- Phantom stones are **out of Act II** (code kept for now; decide later whether a later act
  reuses them or they are removed).
- **2026-10-08, the user: "togliamo le pietre che cadono, non mi piacciono"**: crumbling leaves
  II.1; veiled stones move into II.1 (they belong with the lamp, found at the end of Act I).
  "Dall'atto II inizia il vero puzzle game." II.2 (approved, built on crumbling) still uses it:
  ask the user whether crumbling goes from II.2 and the whole game (code kept until then).
- **II.1 rebuilt (2026-10-08), approved by the user and pushed**: deep night in a forest of rock
  pillars (`setting forest_night`, bed `Forest`), 16x16; a rope bridge whose planks are veiled
  (`veiled x y z plank`, `prop rope`), veiled grassy caps on rock spires (`veiled ... ground`),
  a trap (lit from the wrong hilltop cell, a second cap rises and covers the seam's foot), the
  seal hidden on a needle raises a corridor of rock (`rise ... ground`) to the cypress clearing.
  Two fragments: II.1b (V.22, the god seen by the lamp: light on the spur, then view 1) and
  II.1 (V.23, the arrow: a needle off the corridor). Solver: 25 steps, 6 turns, 3 lightings,
  404 dead ends. New pieces: `spruce` (fir), `log` (fallen trunk, an edge prop for closing stray
  seams in nature), `rope`.
- **II.2 rebuilt (2026-10-08), waiting for the user's playtest**: the user's brief: a breather after
  II.1 (long corridors, nothing new: rotation, the lamp's veiled stones, candelabra), dawn over Pan's
  river (`setting river_dawn`, bed `River`: water, bubbles, first birds; water colour per setting:
  `Look.water/glint`), lots of water, the diorama in **two sections joined only by a cave**
  (`cave x y h dir`, pairs in file order; a real edge between the mouths, `palace.is_passage`; the
  step is a 2.4 s passage, she fades into one mouth and out of the other: `game.passage_alpha`).
  Entered only on purpose: Space (or F) at the mouth (`game.enter_cave`; a hint says so; a lit
  candelabrum marks each mouth); `find_path` never goes through a cave (user's playtest: a click on
  the scroll picked her own cell at the mouth and sent her back down). Low: bank, boardwalk with two veiled planks, islet,
  view 3 joins the high bank, long bank north to the cave. High (h11+, beyond ILLUSION_REACH from
  the river so no illusion joins the sections): ridge arch, view 0 to the second tower, veiled rope
  bridge, seal raising a rock bridge, steps to the summit (h13, exit: it recalls the Crag of II.3).
  Fragment on a rock in the middle of the river: stepping stones from the start bank, two veiled
  (light), then view 3 from the last one. `level_check` now errors on a cave without rock on its
  side and warns when a click on a scroll would pick another cell (veiled hidden or shown). Solver: 36 steps,
  2 turns, 2 lightings. Outro: Pan sits on the river's *high brow* (Met. V.25 "supercilium fluminis").
- **II.3 "The Sisters' Crag" rebuilt (2026-10-08), approved by the user ("perfetto", 5 minutes to finish; no illusion to add) and pushed**: the user's brief: a
  narrow, very tall diorama climbed in a spiral, too tall for the screen (the camera pans up through a cave,
  as in II.2), by day (no lamp: `setting crag_day`, bed Mountain; the lamp's slot shows "not needed here"),
  bare rock and earth, very few trees (at the foot), long, harder as it climbs, two fragments reached with
  the handles (one hard). Size 11, a 3x3 core of rock to a peak (h27), three bands (`tier h0 h1`: the
  camera frames Psyche's band, `render.camera_tier`, and pans 1.8 s when it changes, during a passage while
  she is inside the rock; the far backdrop follows the pan by 0.25-0.5). Below (h1-h7): a slab turned across
  the gap (tutorial, one turn), steps up the west face seen only from the west, steps turned at the end of
  the north ledge (two turns). Middle (h11-h13): the collar, an L round the core joining two of four doors
  at a time (II.4's floor, material reused), handles at the west and north doors; the steps up from the east
  door turn from the south door (W, S, W, N, E, up). Above (h19-h22): two arms round the core, lower (h19)
  and upper (h22), each turned from a handle on its own level and one on the other level; exit on the west
  precipice. Fragments: II.3 (the gull, V.28) on the north needle (upper arm north: 17 handles, the hard
  one); II.3b (Psyche's lie to the sister, V.26, new text to review) on a spur the east steps reach turned
  once more. Solver: 98 steps, 5 turns, 14 handles, 0 dead ends, no illusions (only hidden stairs: ask the
  user whether to add one). New edge prop `lip` (a low lip of rock). The layout was generated by a scratch
  script; edit the level file directly from now on.
- **II.4 "The Temple of Ceres" rebuilt (2026-10-08), approved by the user ("tutto perfetto") and pushed**: the user's brief:
  everything learned so far, sunset, windy, horizontal (after II.3's vertical): the crag on the left, a
  rope bridge, then a real temple on the right; two hidden buttons and two corridors raised with the lamp,
  one tunnel from one side to the other, a hard passage of my choosing, two fragments; the player must be
  at ease with every command, and a little wit is needed. Size 30, `follow 13` (a long level: the camera
  frames ~13 cells and follows Psyche, kept inside the level; backdrop parallax), `setting windy_sunset`
  (I.1's sunset with `Look.wind`: gusts streak across, `Scene.gusts`; candles lit), `oil 20`. Several
  seals now (up to 4: `sigil` lines in order, `rise ... n` raised by the n-th; `palace.risen`,
  `game.activated` are `level.Seals` sets, `rise_t` per seal). Crag: veiled stones over a cleft, view 3
  from the ledge to a pillar with the first hidden seal (raises a corridor of rock), the tunnel through a
  jagged ridge, steps behind it seen only from the north (or climbed in the light), the rope bridge with
  two veiled planks; temple: steps up to the north gallery, where the second hidden seal and the handle of
  the nave's turning stair are (three turns to the south), the second corridor from the south gallery to
  Ceres' altar (exit). Fragments: II.4 (V.29-31) on Ceres' column by the altar: view 1 from the south
  gallery, lost for good once the second corridor rises (the hard passage: go before lighting the second
  seal); II.4b (new text, VI.2, Psyche's prayer to Ceres, to review) on a needle, view 0 from the first
  seal's pillar. Solver: 53 steps, 1 turn, 3 lightings, 3 handles, 0 dead ends.
- **II.5 "The Temple of Juno" rebuilt (2026-10-08), pushed, waiting for the user's playtest**: the user's brief: the
  last of Act II, a real puzzle with everything learned (light, handles, veiled stones, caves, hidden seals,
  dead ends, dark corridors), two fragments; vertical at first, then horizontal to the right, then down;
  dusk going into night, candelabra lit in the temple. Size 32, `follow 13`, `setting valley_dusk` (new:
  the end of twilight in a deep valley, bed Dusk), `oil 24`, `lamp 4`. The rock: steps in its west face
  (hidden from views 0-1), a cave from the north ledge up to a shoulder (blind until the seal), the first
  hidden seal at the north ledge's blind end raises the steps to the summit. The ridge: a veiled grassy cap
  on a needle off the ridge's line, reached in the dark by view 0, left by view 3. The gate: an L bridge
  (part, handles at the gate and on the north balcony) joining two of its doors (gate, north balcony, east
  terrace), one stone veiled (it turns with the arm); its south arm's tip joins the temple's north gallery
  by view 2. The temple: view 0 from the gallery to Juno's column (the turning stair's first handle); the
  dark stair between four pillars (light only, unlit candelabra) to the east ledge, the second hidden seal
  raising a stair to a landing over the nave; the turning stair has two tasks: toward the landing to go
  down (set from the column), then toward the altar (the second handle, in the nave). Wrong from the column,
  the landing is a dead end until she goes back up (view 2 from the risen stair to the bridge's tip).
  Fragments: II.5 (V.31) on a needle, view 1 from the cap; II.5b (new text, VI.4, Psyche's prayer to Juno,
  to review) in the grove before the temple, through the east terrace's cave (bridge to the north balcony,
  its handle to the east terrace). Solver: 67 steps, 7 turns, 4 lightings, 6 handles, 0 dead ends; every
  key piece checked as required (removed, the level cannot be solved). The layout was written by a scratch
  generator; edit the level file directly from now on.
- Level tools (2026-10-08, with II.5): the solver costs whatever is done in the light a little more (the
  oil it burns), so its plans put the lamp out when they can; `palace.oil_left` replays a plan counting the
  oil (`game.oil_rules`), checked by level_check and `act2_levels_solve_and_play`; level_check lists the
  illusions that appear once the palace is whole (veiled shown, seals raised) and `check_props` reports
  visual errors in every position of the parts: props inside blocks or hanging in the air, candles with no
  wall, candelabra off a floor, blocking props on needed cells, handles on parts, blocks given twice, more
  flames than the shader shows (`level.MAX_LIGHTS`). It found a floating urn by II.4's altar (now a vase).
- Settings follow the slot titles (each level reflects its title): II.2 river and Pan, II.3 the
  sisters' crag, II.4 Ceres, II.5 Juno; level content is rebuilt to fit.
- Work strictly step by step: one level, the user plays and judges, then the next.
- Natural settings (2026-10-06): `ground x y z0 z1` (living rock, brown strata, grassy top),
  `steps x y z dir` (stairs cut in the rock), `crumble x y z rock` (a cracked stone of bare rock),
  `water x0 y0 x1 y1` (a river just under h1, decoration), `prop reeds x y z dir`. The solver also
  handles the seal (`rise` blocks raised by the lamp on `sigil`), so a seal can open an Act II exit.
- (old, replaced 2026-10-08) II.1 rebuilt at the bottom: a meadow on living rock, steps up to the exit, the fragment on a rock
  spur behind a cracked stone (way back: the view-0 seam it hid). II.2 rebuilt (proposal B, "Pan's
  crag"): ford of cracked rocks, a spiral of ledges round the crag, the broken east ledge bridged
  by view 1 from its cracked end, the seal on the summit raises the bridge to Pan's meadow;
  fragment on a rock in the river (view 2 from the first ford stone, back by view 3).
  **II.1 and II.2 approved by the user (2026-10-06)**: II.2 "bello, ambientazione perfetta",
  all mechanics used well, not too hard: right for its place. Pushed.
- (old brief, replaced 2026-10-08 by the one above: no lamp, so no seals) **II.3 "The Sisters' Crag"** — the user's brief (2026-10-06):
  a real puzzle, **longer to play** (the user will time it), introduces **handles** (Act II's
  second mechanic, with its `mechanic` card), and **several buttons to press**: today only one
  `sigil` per level exists, so build multiple seals (each lit by the lamp raising its own set of
  blocks; the solver must track each one). Coherent with the title (Met. V.11-21: the jealous
  sisters climb the crag where Zephyr carried Psyche; sea crag setting, wind, the sisters' road):
  reuse the current handle level (II.4 today) as material, restyled to the crag. Then the user
  plays it and reports the time.

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

## Art direction (user, 2026-10-05: "l'ambientazione è tutto")
- **Platforms**: call every walkable surface a *piattaforma* (EN: platform). One visual
  language for all of them: a light top with a thin bright rim, the same shape whatever the
  material. Material (grass, rock, marble, wood) lives on the sides and in details, never on
  the top: walking from a meadow onto stone must always read as possible. Stones that do not
  hold (phantom, veiled, cracked) change the top in a recognisable way in every style.
- **Settings**: each act has its own setting, at night where the lamp is needed (I.1 is a sunset:
  no lamp yet; user, 2026-10-06); each
  level a sub-setting of it, with props coherent with the place (add/remove elements per level).
  Act I the palace of voices · Act II the land without the palace (II.1 the palace crumbling onto
  living rock, II.2 river and reeds of Pan, II.3 sea crag, II.4 mountain sanctuary of Ceres with
  wheat terraces, II.5 valley temple of Juno) · III house of Venus · IV the underworld ·
  Epilogue Olympus (proposal, to confirm level by level).
- **Art style**: to be chosen by the user among five mockups (canvas
  https://claude.ai/artifact/L4ScxhCgDi5rJNCThSX7jZ): moonlit marble (today's, refined),
  red-figure vase, Pompeian fresco, mosaic, book engraving. The mockups are flat 2D sketches
  (palette, materials, readability), not renders. A style is a "skin" on the same engine: the
  3D pipeline, lamp light, depth cue, glows, particles, mist, rotation all stay; what changes is
  the shader (palette per act/setting, procedural face treatment: masonry, hatching, tesserae,
  plaster grain, ink outline), how the glows read in that style (mosaic gold lit by the lamp,
  the lamp as the only colour on engraved paper...), props per setting, sky and UI font.
- **Backdrop** (agreed 2026-10-05): a layered parallax background per setting, **generated in
  code** (no images: the rule stays). Far to near: sky (stars, moon) · far silhouettes (hills,
  mountains, sea horizon) · middle silhouettes (trees, ruins) · a mist band at the foot of the
  level · rare foreground pieces only at the screen edges (reeds, a branch). Driven by the view
  rotation (each layer is a 360° panorama that closes on itself over the four views) plus a slow
  drift of clouds and mist. Always darker and lower-contrast than the platforms, never in front
  of the palace. Replaces today's generic sky/clouds/islands per level.

## Game design (agreed with the user, 2026-10-04)
Full design document (Italian, kept up to date there): https://claude.ai/code/artifact/97c37954-ecc7-4b98-a211-40e5c123d11e
- 20 levels, ~5-6 hours: Act I (4, prologue inside I.1) · Act II (5) · Act III (5) · Act IV (5) · Epilogue (1).
  Each act adds two new mechanics (see "Mechanics per act"); the last level uses all eight.
- Follows Apuleius in order (Met. IV.28 - VI.24). **Canonical ending**: Psyche lights the lamp at the
  end of Act I (the drop of oil starts Act II). "Trust" (reaching Cupid in the dark) = secret, non-canonical
  ending, an achievement after finishing the game. The lamp appears only at the end of Act I.
- Acts: I the palace of voices (rotation, illusions, hidden stairs; lamp + seal in I.4 — today's level 1
  becomes I.4) · II abandonment (false/crumbling structures, the lamp unmasks them, handles rotating part of
  the palace) · III Venus' trials (helpers that move pieces: ants, eagle; day/night cycle) · IV Proserpina's
  box (talking tower, renunciations, counted coins, upside-down palace, absolute darkness) · Epilogue: all.
- **Frammenti del racconto** (EN: Fragments of the Tale): collectibles, one or more per level
  (`content.FRAGMENTS`, saved by fragment id: I.3 has two, "I.3" and "I.3b"; 25 today), on isolated spots
  reached by an optional harder puzzle; never required (level_check must verify it). They tell what the
  levels do not show; the last reveals the frame: an old woman telling the tale to Charite (Met. IV.27, VI.25).
- The Book (menu): fragments in the text's order + achievements. Progress saved next to the settings.
- All texts written by us from the Latin (no modern translations: copyright), IT/EN, the user reviews them.
- Roadmap: M0 foundations, M1 game structure, M2 Act I, M3 Act II mechanics and levels (done);
  from now on art direction, then level by level (see "Roadmap from now" at the end).

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
- Long levels (`follow n`): the camera follows Psyche framing about n cells (`Scene.cam`, smoothed, kept
  inside the level's fit); `--survey` shoots four stretches along x.
- Tall levels (`tier h0 h1` lines): the camera frames one band of heights at a time, with the zoom of the
  tallest band; `--survey` (with `--level`) shoots each band from the four views, no walking.
- Settings per level (`setting night|night_candles|deep_night|crag_sunset|dusk|forest_night|river_dawn|crag_day|windy_sunset|valley_dusk`, `render/setting.odin` `LOOKS`): sky gradient,
  orb, stars, layered ranges (`ridges.fs`, panoramas that close over a full turn), clouds,
  mist, and a sunset palette for the stones (`daylight`). I.1 is the crag at sunset (approved).
  `dusk` (I.2): the palace at twilight, pink clouds, first stars, a pale moon, `daylight` 0.4,
  and `candles` lit (a flame glow on every `sconce`, and warm light on the stones around it:
  `candle_lights` -> `candles[]` in palace.fs). `night_candles` (I.3): the night with candles lit. `deep_night` (I.4): darker stones (`gloom`),
  candles out, clouds drifting across the moon (`moon_clouds`; sky.fs draws them, `moon_cover` mirrors
  them on the CPU and dims the stones while the moon is hidden: `moonlight` in palace.fs).
- Post-processing (`render/post.odin`, `post*.fs`): the world goes to a canvas, then bloom,
  soft scene, light shafts, tilt-shift (focus on Psyche), Kuwahara paint, grade, vignette,
  grain; the UI is drawn after, untouched. Six visual styles (`settings.Look`: off, clean
  (default), miniature, film, dream, painted) chosen by the player in Settings > Graphics
  with a strength slider; F4 cycles them; `--shots ... --post NAME`.
- Figures (Psyche, Cupid) are abstract lathes + additive wings: placeholders until the
  user picks a character style.

## Sound (session 8, 2026-10-06; kept by the user "per ora": generative music, new effects, beds)
- User's direction: soft, meditative, relaxing music, one per act, never heard to start again;
  professional effects; the player's senses first ("esperienza sensoriale"). The user's Suno tracks
  were tried and dropped ("troppo agitate"; removed with their OGG player and loop tools, in git
  history at c219b4f if ever needed).
- The act music is **generative** (`audio/generative.odin`), played live in the mixer
  (`audio/music.odin`, audio thread): a mood per act (`ACT_MOOD` in main.odin: Palace A minor,
  Abandonment G minor, Trials D minor, Underworld E Phrygian; Epilogue = Palace): additive pads
  breathing through 4 chords, a Karplus-Strong lyre with short pentatonic phrases, rare glass bells,
  a low drone, a stereo FDN hall; no beat. `ACT_KEY` follows the moods' roots. Demo WAVs:
  `tools/sound_board` -> `build/sounds/music_*.wav`.
- Title screen: mood `Title` (Psyche's theme: written lyre phrases, `Mood.motif`) while the palace
  sleeps behind the menus (`!game.active`); it crossfades into the act's mood when play begins.
- `update_sound` (main.odin): music per act (silent while the screen goes black), ambience bed per
  setting (`SETTING_BED`: mountain wind, dusk breeze + crickets, night crickets, deep night), duck
  under cards and menus. Veil: where Psyche carries the lamp, in the dark the music is low-passed;
  her light opens it (`audio.set_veil`).
- Effects: footsteps recorded (Kenney CC0, `tools/sfx_prep.sh`, grass / stone / rock by what is under
  her: `game.footstep`); the rest synthesised at startup on a worker thread (`synth.odin`: modal
  glass/wood, Karplus-Strong plucks, SVF noise, FDN reverb), a few takes each, never the same take
  twice in a row. In-key effects (`TUNED`) are written in A minor pentatonic and follow `ACT_KEY`;
  pitch arguments at call sites are in semitones (`audio.semitones`). `tools/sound_board` writes
  every effect and bed as WAV (build/sounds) to listen outside the game.
- Next, after the user's verdict: per-place one-shots in the beds (birds at sunset, an owl), positional
  pan of events, crumble/handle sounds for Act II.

## Window and resolution
- Always draw on the real framebuffer (`canvas_size` = GetRenderWidth/Height) and reset
  viewport + 2D projection every frame (`reset_canvas`): raylib's screen size can be stale.
- Settings panel: a sheet on the left with tabs (General, Graphics, Audio); the game stays
  visible on the right, unshaded on the Graphics tab, so the style is judged live.
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
   add `--plan` to play the solver's plan with a shot after every decision (`--record`: every
   frame at a steady 60 fps instead, for a video, from the level's start (a prologue plays and is
   started by itself); it also writes `sounds.txt`, every effect at the video's clock; I.4's plan
   ends lighting the lamp beside Cupid). Record with the release build (10x faster).
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
./build/trial-of-psyche-debug --shots DIR --no-ui   # the world only (backdrops for mockups, stills)
./build/trial-of-psyche --shots build/video/i3 --size 1920x1080 --level I.3 --plan --record  # a video (60 fps + sounds.txt)
odin build tools/video_audio -out:build/video_audio -o:speed   # then:
./build/video_audio effects build/video/i3/sounds.txt build/video/i3.wav   # its sound, in sync
tools/make_short.sh i1 180 300 i3 60 420 i4 1260 357   # a YouTube Short from recorded segments
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
  - Tools: `--shots DIR --level ID` tours a level.
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

- Session 5, later: the user, testing Act II, asked for a card that presents each new mechanic
  (done: `mechanic` command) and found the meadow/stone floors unreadable as one walkway. New
  direction: art direction first (settings per act, platform language, art style, total graphics
  overhaul), then **level by level, not act by act**.

- Session 7 (2026-10-06): the user replays every level from I.1, adapting the **settings level by
  level** and building a reusable prop set; one level at a time, only at the user's ok.
  - **I.1 approved** ("perfetto"): a mountain crag at sunset over a sea of clouds (`setting
    crag_sunset`): structure unchanged, `ground`/`rock`/`steps`, mountain props (pine, boulder,
    shrub, cairn), two decorative spurs out of reach. Daylight/sunset fits Act I's early levels
    because the lamp is not needed yet (Act I settings need not all be at night).
  - Filmed prologue: letterbox (`game.cine`, `ui.cinema_bars`), tilt down from the sky,
    close-up on Psyche, bars withdraw when play begins.
  - Visual styles (post-processing) shown as five previews (artifact
    https://claude.ai/artifact/8TSirwBuD8xmcCeztNwmJv); the user chose to keep **all of them as a
    player setting** (default Clean) in a tabbed settings panel. 32 tests. Pushed.
  - Tutorial hints (`game.is_tutorial`) are a card over the game on the left (`ui.draw_tutorial`):
    "How to play" label, a drawn sign per mechanic, slides in, stays until done, then a tick;
    the controls it talks about pulse (`point_at`). Other hints keep the bottom band.
  - A keys badge top left (Esc pause and controls, R restart: `ui.keys_badge`) replaces the old
    Hint_Keys; it comes once the turning tutorial is done (at once in levels that do not teach it).
    The turning tutorial now speaks in the tale's voice (the mountain never shows itself whole...).
  - Figures climb stairs tread by tread (`pl.stair_ground`, `pl.stand_world`), in play and prologue.
  - Transitions between levels: at an exit the wind lifts Psyche higher, the camera follows and
    the **veil between the levels** closes (`veil.fs`, `game.veil`); the ending card floats on it;
    Continue loads the next level behind the veil and plays the **arrival** (phase `Arrival`: the
    veil opens, the blocks rise into place from the start outward, Psyche comes down onto the
    start). Retry after an exit arrives the same way. At the end of an act (or after a non-exit
    ending) the screen goes to black (`continue_story`, `black_t`) and the next act opens with its
    card or cutscene. The tour (`--shots --level`) ends with the transition (10a..10d shots).
  - **I.1 polished and approved by the user** ("perfetto"): tutorial card, keys badge, grid on
    grass, stairs, transitions. It is the reference for every level from now on.
  - I.2 reworked (2026-10-06): the layout turned so the start view shows Psyche on the lawn
    (seams now in views 1, 2, 0; fragment view 3), setting `dusk`, five lit candles.
  - **I.2 approved** (dusk, start view). **I.3 rebuilt (2026-10-06)**:
    night with candles lit (`night_candles`), bigger (13x13), no tutorial hint; three hidden
    stairs and three seams, each in its own view (solver: 6 turns, 15 steps); a candle tower as
    a decoy; two fragments on the sisters' statues (`prop statue`), texts from Met. V.9-10 (the
    elder's and the younger's complaints; the old Venus fragment IV.30-31 was dropped).
    `./build.sh check` now prints the solver's plan for static levels too.
    **I.3 approved** ("bellissimo").
  - **I.4 rebuilt (2026-10-06), approved by the user ("perfetto")**: deep night, 16x16; the lamp is
    introduced under a portico whose four columns hide the stairs from every view (only the light
    climbs them); the seal raises a bridge of five stones (gold trail, a thud and dust as each
    lands: `rise_landing`) to the gallery; view 0 joins the gallery to Cupid's chamber. Fragment:
    four pillars joined in views 3, 2, 1, 0. Solver: 27 steps, 3 lightings (`lamp 3`).
  - Where to light the lamp: candelabra (user, 2026-10-06, after a floor symbol and a pool of shadow
    with a wandering light were both rejected): `candelabrum x y h dir [lit]` stands in a corner of a
    surface (not blocking). Lit ones light the stones around (`candles[]`/`candle_reach[]` in
    palace.fs); unlit ones catch the flame when the lamp burns within `CANDELABRUM_REACH` of Psyche
    (`light_candelabra`), for good. I.4: two lit at the arrival, a row of unlit ones along the lamp's
    path (portico, balcony, seal, gallery) up to Cupid's in the chamber. Decoration only: the rules
    and the solver ignore them. The lamp's tutorial card draws a candelabrum.
  - End of session 7: orphan code removed (Hint_Stairs: the hidden stairs are found by turning, no
    lesson; unused helpers), README shortened with badges and a gameplay GIF (`docs/gameplay.gif`,
    made from `--plan --record` frames of I.2-I.4 with ffmpeg). **Act I is done and approved.**
  - **Next session: Act II, from II.1**, level by level as for Act I (its settings, props, depth;
    II.3's brief above still stands when its turn comes).

- Session 8 (2026-10-06): **sound design** (section "Sound"): mixer on the audio thread, ambience
  beds per setting, effects rebuilt (recorded footsteps + synthesis), the music veiled in the dark.
  The user's Suno tracks were tried and judged too agitated: the act music is now generative (kept);
  the Suno tracks were then removed. Then the **HUD restyle** (section "Art direction") and a
  **YouTube Short** (30 s, 1080x1920 at 60 fps, the game in landscape turned 90 degrees after a
  "flip your phone" card; I.1 prologue and exit, I.3, I.4 lamp and ending; the user liked it):
  `--record` at 60 fps with a sound log, `tools/video_audio` rebuilds the sound in sync (ambience,
  effects; the generative music apart), `tools/make_short.sh` cuts, turns, titles and mixes
  (-14 LUFS). Videos live in build/video (not in git).
  **Next session: Act II, from II.1**, level by level as for Act I.

- **HUD restyle (2026-10-06, chosen by the user on the canvas
  https://claude.ai/artifact/Ya9pa2yLXkfwybJAycj7AW)**: style 2 "Luce di lampada" (lamplight) for
  everything, its title screen as drawn (the lamp's side darkened on the left, the source in spaced
  capitals, the title in two lines, an ornament, menu entries with diamonds, the oracle's words bottom
  right); the settings are style 1's sheet of **dark glass** at full height on the left
  (`ui.glass_panel`: `render.post_glass` frosts the soft scene at quarter size; the world goes
  through the post canvas while the sheet is open, even with the visual style off); the oil gauge is
  style 4's upright line of light on the right with a bead of flame (`draw_oil`). Acts are named in
  spaced capitals between two rules, ──── ATTO I ──── (`ui.rule_label`): under the level's title,
  on act cards, in the prologue. Fonts (OFL, assets/fonts): Mystery Quest for titles (`Face.Display`,
  with a warm halo `Style.glow`), Cormorant Garamond Medium / SemiBold / Medium Italic for text
  (`Face.Body/Semi/Italic`); Noto Serif removed. Palette in ui.odin (ivory, parchment, gold, warm
  tint). `--shots` has a pause shot (03b).

- **Squared HUD (2026-10-08, the user's choice on the canvas
  https://claude.ai/artifact/3myJRHmykiACnRbuZfLL9e)**: nothing rounded; cards and key caps square
  with four gold corners (`ui.corner_frame`, `warm_card`). **Skills** (`content.Skill`, `SKILL_FROM`:
  one skill learned per act or so, each on its number key): a sidebar on the left, a square slot each
  (1 the lamp, its oil as 14 notches inside the slot; 2 the handle; still to learn: hatched, a padlock);
  the name and state slide out on hover (animated) and for a moment when the state changes, or always
  (setting). **Diorama** (world, not skills): small square buttons bottom right, Q E (turn) and R (the
  brazier: a tap goes back to it; held, a ring fills and the level restarts; let go half way: nothing;
  `update_rest` in main.odin); no view indicator (the user removed it). **Space** = the action of the place (today: into a cave), a card over Psyche.
  Settings > Accessibility: HUD size, skill names (hover/always), hold time or R twice, reduce motion,
  endless oil. The pause hides the HUD.

## Roadmap from now (user, 2026-10-06): level by level
- **Next session (user, 2026-10-08)**: review II.4 and II.5 together, carefully, with the user (play,
  judge, adjust); then the II.5b text; only after their ok, Act III.
- Art direction is settled as: settings per level (`render/setting.odin`, add a `Look` per new
  place) + the player's visual style (post-processing). The A0 "art style" mockups (engraving,
  mosaic...) are superseded by the post styles unless the user brings them back.
- **One level at a time**, in order I.1 … E: its setting and props (grow the reusable prop set),
  puzzle depth (aim 15-18 minutes), texts, level_check + tests; the user's playtest and ok close
  each level before the next. Act II levels already built (mechanics, solver) are reworked in
  turn, not thrown away.
- Mechanics of Acts III-IV are designed when their first level comes.
- Open: character style; a dedicated font (Noto Serif is a placeholder); the user's review of the
  texts (M1 drafts: fragments, act cards, titles, achievements; Act I lines: table in the design
  document).
