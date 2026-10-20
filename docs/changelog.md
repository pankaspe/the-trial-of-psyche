# The Trial of Psyche — Changelog

Newest first. Each entry: a title, the kind of work, one line on what changed.

Kinds: **feature** (new code or mechanic) · **level** (a level built or rebuilt) ·
**rework** (something existing redone) · **refactor** (same behaviour, cleaner code) ·
**fix** · **removal** · **sound** · **ui** · **tooling** · **docs**

## 2026-10-20

| Title | Kind | Description |
|---|---|---|
| Two worlds, one stone | rework | Proserpina's flip: the world above is now the land of the dead in a cold violet dusk, clouds of ash drifting; the world under is the inferno, a sky of fire over a sea of lava (lying under the diorama, never over it), embers rising, the stones lit red from below. |
| The world turns over | feature | A new flip (2.65 s): the pomegranate wakes and its seeds of light spiral out, the world leans back, comes apart (the stones thrown from the axle, the farthest the most, their edges inked dark) and falls over, swings past and settles, together again; the skies roll (the old one goes up, the fire comes from below) and meet at a seam of dark matter, a thin ridge of ink jagged like a range of mountains seen from both worlds, a web of ink veins branching from it into both skies; embers burst along the axle edge-on, and Psyche turns head over heels with it. |
| A new face for the README | docs | A banner with the title alone in its own face, the mechanics of the four acts as a GIF instead of the title shot (Act IV's flip on the way back, by night), and a square logo. |
| Clips of the mechanics | tooling | The screenshots can record a window of a level's plan (`--record-from`, `--record-to`): five-second GIFs of each act's mechanic and a 20-second one of all four. |
| IV.4-IV.6 float | rework | Like IV.2 and IV.3, the last three levels of Act IV float with no basin: only a faint sheen of water fading toward the edges, each of Charon's boats on a patch of dark water of its own that goes where it goes. |
| Boats and hanging stones part cleanly | fix | Charon's boats rise and sink with their landings as a diorama comes together or breaks up; the hanging world's stones sink down on screen too; after Charon's boat the diorama breaks up like every other. |
| No more rings | fix | The sundials', perches' and pomegranates' rings are gone: their glowing stones are the only hint (none in Puzzle). |
| Difficulty | feature | A new game asks how to play: Story (every aid, endless oil, the guide), Normal (the hints, the oil counted) or Puzzle (no help at all). Each aid can be changed alone in a new Difficulty tab of the settings; the choice is kept in the game's save. |
| The guide | feature | In Story, the light on Psyche (Tab, the pad's North) also shows the way: a trail of violet lights from her feet to the next place to act, and what to do there (turn, light the lamp, use the spindle, call the eagle...). |
| Morning skies | rework | The sunny settings now have a morning light: a cool blue shade, warm sunlit faces and pale tops, so the blocks read clearly; a deeper blue sky with the sun lower, white clouds drifting across it, and birds far off (swallows, Venus's doves, a raptor over the Styx). |
| Hints in violet | rework | The stone under every device (handles, sundials, perches, caves, moorings) glows softly from within, breathing, instead of the rings and halos; seals and veiled stones near her flame twinkle with little violet stars instead of gold sparks, never taken for a brazier's embers. |

## 2026-10-19

| Title | Kind | Description |
|---|---|---|
| Devices glow | feature | A faint warm glow, breathing slowly, over everything that changes the diorama or takes her elsewhere: handles, sundials, the eagles' perches, the caves' mouths, the moorings where a ferry waits; the handles get a ring of light on their stone (amber by day). Seen even half hidden; an accessibility setting, on by default. |
| Saved inside a level | feature | In a level of several dioramas the game remembers the diorama reached: Continue and the level select start again from it (the diorama from its start), the level select says so, and R (pad West) starts the level from the beginning. |
| III.5: the gardens of the Hours and the terraces at evening | level | The Order of the Box grows to three dioramas, the finale of Act III. The gardens of the Hours (VI.16): three L slabs of plank turned by crossed handles, two terraces each with its sundial, rams at evening and stairs of the sun by day, the eagle to the gate. The terraces at evening (VI.16-17): illusions in two views, two seals, two veiled bridges, a stair of the sun between two sundials, the eagle to the top of the highest tower. Two new fragments (III.5d, III.5e). |

## 2026-10-18

| Title | Kind | Description |
|---|---|---|
| Dioramas part cleanly, by day too | fix | Between dioramas the cracks the sun shows where the illusions were, and their dust, now go down with their stones; the rings on sundials, perches and pomegranates sink as well as fade; the basin's water goes as its rim starts down and comes once the rim is up, instead of hanging in the air. |
| III.4: the gorges of deceit | level | A second diorama after the spring (VI.14-15): a puzzle of illusions, a spiral of rocks round the gorge each joined to the next in one view only, stairs seen from one side, three decoy rocks, two sundials, stairs of the sun by day to the crag where the eagle brings the urn back; a new fragment (III.4d, the dragons). |
| Dioramas part cleanly | fix | Between two dioramas of a level, the handles' and sundials' wheels, the eagles (even one flying home), the rams, the rings on perches and sundials, the parts' inlays, the braziers' light and the water's foam now sink and fade with their stones, instead of staying in the air. |
| III.3: the channels and the summit | level | Jupiter's Eagle grows to three dioramas (VI.13-15): the channels under the summit, a handle puzzle of two crossed slabs and one eagle; then the summit, a long bridge of veiled stones woken by the lamp, a corrupt stone at its end, stairs hidden by crags, the eagle to the spring. Two new fragments (III.3c, III.3d). |
| Veiled stones feel the flame | feature | Like the seals, a veiled stone not yet real gives off a faint warmth and a few sparks of gold when Psyche comes near it in the dark. |
| The dioramas' column | ui | In a level of several dioramas a gilt column on the right: a diamond for each, climbing from the first; the one in play bright, those done half clear, those to come in outline; "2 / 3" under it. |
| III.2: the grove of the plane tree | level | A second diorama after the pasture (VI.12-13): three sundials, two rams, a stair of the sun down and an evening illusion back up, the knoll under the great plane tree; a new fragment (III.2d) on the pond's islet. |
| The plane tree | feature | A new prop for the Sun's pastures: a great plane tree, its crown broad and low. |
| Psyche's Notebook | feature | C (pad West), or from the title and the pause: every mechanic met so far in four tabs (the world, the lamp, the spindle, the actions of the place), with its sign and keys; those still to come are veiled, those of the level in play in gold. |
| Corrupt stones | feature | The one veiled stone that closes the way (II.1, III.1) shows ashen violet and cracked in the light, ash with dark cracks once real; a tutorial the first time; `check` tells which veiled stones make dead ends. |
| Seals feel the flame | feature | In the dark an unlit seal near Psyche gives off a faint warmth and rising sparks of gold, so the lamp need not be lit blindly. |
| Fish | feature | Dark fish glide under the water of the living places (river, pastures, Venus, palace, temple, crag), darting now and then with a ring on the surface; none in the Styx or the land of the dead. |
| Turning tried | rework | A softer turn and turns chained mid-turn were tried and dropped: the original turn stays. |
| README: the changelog | docs | The trailer badge (old) gives way to the changelog on trialofpsyche.com. |
| Wings of energy | rework | One system of wings for both figures: Cupid's broad, five golden filaments with light flowing along them; Psyche's small, violet to blue, her body a faint rose. |
| II.2: Pan's meadow | level | A second diorama after the crag: a gentle way down to the river's high brow where Pan sits (V.25), a plank the lamp shows, a short way for whoever turns twice; a new fragment (II.2b, Pan and Echo). |
| README | docs | New title shot (New game, Games), two shots of the new screens (the games, the constellation), the new controls. |
| Cupid as light | rework | Cupid is a figure of pure light that breathes, with trails of light for wings (a ripple running along them, quicker in flight); his robe mesh and feathers removed. |
| The act as a constellation | feature | In the level select Tab (pad Y) turns the row of pictures into a constellation: a star per level, lit lines where the tale went on, a level's other dioramas as small stars rising from it. |
| Shots of the games | tooling | The shots script shows the games list with three saves, the erase question and the title on Continue. |
| Five games | feature | Up to five saves side by side ("Games" on the title: continue one, start a new one, erase one); the old save becomes game 1. The title opens on Continue or New game. |
| Levels of several dioramas, shown | ui | In the level select a small plate per diorama on the tile and a "2 dioramas" plaque in the panel. |
| The act's plaque | ui | "Act III 100% complete": a gilt plaque over the diorama instead of the round medal. |
| The last brazier, seen | feature | A column of warm light and rising embers over the last brazier lit; every lit flame larger. |
| Hold to skip | feature | Cutscenes skip when held: a ring fills with rising plucks and the pad shakes; a press with "R twice". |
| The brazier's tutorial | ui | Lighting a brazier shows a tutorial card (its sign, the R button pointed at, a tick when she goes back to it). |
| Where am I, in pause | ui | The pause names the act, the level and which diorama at the top, the title in the titles' face. |
| Act change sound | sound | A pluck when the level select changes act, a step higher for each act. |
| Changelog | docs | The devlog becomes this changelog. |

## 2026-10-17

| Title | Kind | Description |
|---|---|---|
| Act IV retitled | docs | "The Last Trial": the last of Venus's trials; its card leads on from Act III. |
| The blurred passage | rework | Between levels the world blurs under a framed card, then the next level comes into focus, traced in gold. |
| Dioramas in the open | feature | Between two dioramas of one level the first breaks up and the next rises, with no card. |
| I.4: Cupid's tower | level | A second diorama: the bridge from the palace leads to the tower, two seals up to Cupid. |
| Levels of several dioramas | feature | One slot can hold up to four dioramas, played one after the other. |
| Act I playtest notes | ui | A notice for each new page of the Book, the oil shown in a phial, sealed acts in the level select. |

## 2026-10-16

| Title | Kind | Description |
|---|---|---|
| Psyche's step | refactor | One kind of step instead of three flags. |
| Level parser lookups | refactor | One lookup by name for every table. |
| `check --try` | tooling | Weighs a decoration: refused, neutral, or what it changes in the plan. |
| Biomes | feature | A level names its place; the place gives its light, floor and props. |
| Props catalogue | refactor | One row per prop kind, in the rules and in the renderer. |
| Fires and pale boats | feature | `prop fire` lights the stones and crackles as she nears it; Charon's boats in pale wood, turning with the world above. |
| Basins for every level | rework | Each diorama stands in a basin of marble, rock or earth, with water or swamp. |
| Floors | feature | `floor water` and `floor basin`: every diorama stands on something. |
| IV.6 The Open Box | level | Act IV's finale: the box scene, two souls (rock above, marble under), 81 steps. |
| IV.5 The Way Back | level | Three ferries, three seals, both worlds, by night. |
| IV.4 Cerberus and Proserpina | level | Introduces Charon's ferry; Act IV grows to six levels. |
| Charon's ferry | feature | One boat between two landings; it stays where it took her. |
| Devlog | docs | A devlog in English and a smaller README gallery (now this changelog). |

## 2026-10-15

| Title | Kind | Description |
|---|---|---|
| Trailer tool | tooling | `tools/make_trailer.sh`: a landscape trailer from recorded segments. |
| No download yet | docs | The v0.2.0 release withdrawn until the game is finished. |
| One side panel | ui | The level select and the settings share one panel; the frosted glass removed. |
| Level select | ui | The chosen level sleeps behind, turning slowly; a panel with its place, chapters and pieces. |
| IV.3 The Stone of Two Worlds | level | One floor for both worlds; a seal per world, each bridge crossed in the other. |

## 2026-10-14

| Title | Kind | Description |
|---|---|---|
| Proserpina's flip | feature | On a pomegranate the spindle turns the world over; the world under is written in `under ... end`. |
| IV.2 The Underside of the World | level | Introduces the flip: three pomegranates, over, back, over again. |
| Save fix | fix | The portable ChaCha20 (the SIMD one corrupted a save in debug builds); the save read back after writing. |

## 2026-10-12

| Title | Kind | Description |
|---|---|---|
| IV.1 The Speaking Tower | level | The Tower cutscene, a tower widening as it falls, a guard candelabrum, Charon's boat, lightning. |
| Cleanup | refactor | Shared helpers for config lines, triangles, ellipses; dead code out. |
| Footsteps generated | sound | Footsteps synthesised and darker; the last recordings and Kenney's credit removed. |
| III.5 The Order of the Box | level | Act III's finale: every piece of the act; the solver folds half-symmetric parts. |
| III.4 The Water of the Styx | level | Light at evening, fly by day; a rope bridge of veiled planks. |
| Sealed save | feature | `progress.sav` sealed with ChaCha20-Poly1305; the old plain file read once. |

## 2026-10-11

| Title | Kind | Description |
|---|---|---|
| Jupiter's eagle | feature | The eagle carries her to its landing; III.3 in total darkness. |
| III.2 The Flock of the Sun | level | Rebuilt: islands, three swing bridges, rams and sundials. |
| Dead ends | feature | The solver finds states that can no longer reach the goal; a hint says how to get out. |
| The light over Psyche | ui | An orange-red shaft comes down on her at each start and on Tab. |
| The lamp held | rework | It burns while the button is held; press-to-toggle kept as an accessibility setting. |
| Stairs of the sun | feature | Blocks standing only by day, crumbling at evening. |
| III.1 rebuilt for the sundial | level | The court of Venus, two sundials, three seals in order. |
| Two tools, three modifiers | refactor | The lamp and the spindle; the place decides what they do. |

## 2026-10-10

| Title | Kind | Description |
|---|---|---|
| See-through walls | ui | Pieces between the camera and Psyche fade (on by default). |
| III.2 first version | level | Day and evening, the Sun's rams. |
| The Book | ui | An open book: act tabs, an index of levels and fragments, a page turning. |
| III.1 The House of Venus | level | Act III begins (with the ants, later removed). |

## 2026-10-09

| Title | Kind | Description |
|---|---|---|
| Gamepad | feature | Play, menus and HUD fully playable with a controller. |
| Linux release archive | tooling | `./build.sh dist VER`, linked against glibc 2.29 with zig. |
| README and license | docs | A README for players; GPL-3.0. |
| Cupid's flight | feature | Act II opens with a cutscene. |
| Dreamy sound | sound | A flute, softer effects, a flute voice in each act's music. |
| Graphics quality | rework | Low / Medium / High / Ultra replace the visual styles. |
| II.4 and II.5 merged | level | The temple of Ceres and Juno; Act II has four levels. |

## 2026-10-08

| Title | Kind | Description |
|---|---|---|
| Act II rebuilt | level | II.1 veiled stones in a forest, II.2 Pan's river and a cave, II.3 a spiral crag with handles, II.4–II.5 the temples. |
| Squared HUD | ui | Skills sidebar, diorama buttons, hold R to restart, accessibility settings. |

## 2026-10-06

| Title | Kind | Description |
|---|---|---|
| Video recording | tooling | 60 fps with a sound log; YouTube Short tools. |
| Generative sound | sound | Act music, ambient beds, rebuilt effects; the Suno tracks removed. |
| Act I rebuilt | level | I.1 on a crag at sunset, I.2 at dusk, I.3 a night climb, I.4 the lamp in deep night. |
| Settings per level | feature | Sky, ranges, light and props per place. |
| Transitions | feature | Psyche passes through a veil between levels. |
| Tutorial hints | ui | A card on the left, a sign per mechanic, a tick when done. |

## 2026-10-05

| Title | Kind | Description |
|---|---|---|
| Mechanic cards | ui | A card at the start of a mechanic's level, its pieces glowing. |
| Act II first version | level | Crumbling, phantom and veiled stones, handles, braziers. |
| Act I first version | level | I.1–I.4, the prologue cutscene, tutorial hints, decoration. |

## 2026-10-04

| Title | Kind | Description |
|---|---|---|
| Game structure | feature | Acts, level select, save, fragments, the Book, achievements. |
| Renderer and UI | feature | True 3D with the isometric projection, screens, tools; up to 4K. |
| Core | feature | Iso grid, level parser, palace graph and the rules of the world. |
