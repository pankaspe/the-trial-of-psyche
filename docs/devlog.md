# The Trial of Psyche — Devlog

*Last updated: October 16, 2026.* One entry per step of the work, oldest first. Each entry
gives its **date**, a few **tags**, some **meta** (the numbers) and a **description**.

---

## How it started

| | |
|---|---|
| **Date** | October 4, 2026 |
| **Tags** | `origin` `odin` `raylib` `design` |
| **Meta** | From a Godot prototype (`lucerna`) to Odin + raylib 6 · 4 acts, 19 levels and about 140 commits by October 16 |

**Description**

The idea: an isometric puzzle in the style of Monument Valley, set in the tale of Cupid and
Psyche (Apuleius, *Metamorphoses* IV–VI). Psyche crosses floating dioramas where whatever
*looks* joined in the dark is joined. The Godot prototype proved the illusions worked; on
October 4 everything started again from scratch in Odin, with raylib 6 for the window, input
and GPU.

Three rules were set on day one and never changed:

- **Everything generated in code**: meshes, sky, figures, music, every sound (the footsteps
  too). `assets/` holds only levels, shaders and fonts.
- **Little text, gameplay first**: a cutscene opens each act, one line per level, a card at
  the end.
- **One level at a time**: build it, play it, judge it, then the next.

---

## The engine

| | |
|---|---|
| **Date** | October 4–16, 2026 (grown with every act) |
| **Tags** | `engine` `rendering` `solver` `sound` `save` |
| **Meta** | True 3D with an isometric projection · up to 16 flames on the stones · a solver over every state · no image or audio file |

**Description**

The core is a single rule: two surfaces that *appear* joined in the current view are joined.
The rest of the engine exists to make that true, drawable and provable.

- **True 3D with the prototype's isometric projection**: `X = (x'−y')·64`,
  `Y = (x'+y')·32 − z'·64`, with a z-buffer and continuous rotation. Every illusion survives
  in 3D.
- **Pieces are lists of boxes**, uploaded once; a single shader recolours stone, marble, rock
  and bronze for each setting, with up to 16 flames lighting the stones.
- **The palace graph** is rebuilt on every turn (Q/E): illusions become edges, and hidden
  stairs count only when every tread is visible.
- **A solver** explores every state (cell, view, lamp, seals, handles, time of day, world)
  and finds the plan with the fewest decisions. `./build.sh check` uses it to prove that each
  level can be solved, that every piece is needed and that fragments are optional; in game, on
  a worker thread, it spots dead ends and tells the player.
- **Synthesised sound**: generative music per act (a Karplus–Strong lyre, flute, bells, pads),
  ambient beds per place, effects and footsteps computed on a worker thread.
- **A sealed save** (ChaCha20-Poly1305), 100% playable on keyboard or gamepad, from 720p to 4K.

---

## Act I — The Palace

| | |
|---|---|
| **Date** | October 5–6, 2026 |
| **Tags** | `act-i` `turning` `hidden-stairs` `lamp` `seals` |
| **Meta** | 4 levels (I.1–I.4) · the Oracle's cutscene · two endings |

![I.2 The Invisible Palace at dusk, its title over the level](screenshots/act1_invisible_palace.jpg)

*I.2 — The Invisible Palace: one seam per view.*

**Description**

Four levels that teach you how to look, from Zephyr's Crag to the night of the lamp.

- **Turning** (Q/E): four views about the centre; it changes which surfaces touch.
- **Hidden stairs**: in the dark they work only when every tread is visible.
- **The lamp** (I.4): while it burns it shows the real edges and the cracks where the
  illusions were, and it uses up oil.
- **Seals**: the lamp lit over a seal raises a bridge.

The Oracle's cutscene opens I.1; I.4 has two endings, the canonical drop of oil and a secret
one, "Trust".

---

## Act II — The Abandonment

| | |
|---|---|
| **Date** | October 5–9, 2026 |
| **Tags** | `act-ii` `spindle` `veiled-stones` `handles` `caves` `braziers` `sound` |
| **Meta** | 4 levels (II.1–II.4) · Cupid's flight cutscene · II.4: 101 steps, 11 handles |

![II.2 The River and Pan at dawn, its title over the level](screenshots/act2_river_and_pan.jpg)

*II.2 — The River and Pan: two sections joined by a cave, at dawn.*

**Description**

Act II brings the second tool, the **Spindle**, and the first pieces that change the diorama
under Psyche's feet.

- **Veiled stones**: absent in the dark, golden ghosts in the light, real for good near her.
- **The Spindle and handles**: standing on a handle, the spindle turns a part of the diorama
  a quarter turn.
- **Caves**: passages between sections, entered only on purpose.
- **Braziers**: places to go back to.

At first the act had five levels and two mechanics later dropped (crumbling stones, phantom
stones). On October 9 II.4 and II.5 became a single temple of Ceres and Juno. In the same days
the sound was redone: no outside tracks, only generative music and a synthesised flute, "like
a dream".

---

## Act III — Venus's Trials

| | |
|---|---|
| **Date** | October 10–12, 2026 |
| **Tags** | `act-iii` `two-tools` `sundial` `rams` `stairs-of-the-sun` `eagle` |
| **Meta** | 5 levels (III.1–III.5) · the Venus cutscene · III.5: 64 steps, 12 decisions, 63,800 states |

![III.2 The Flock of the Sun at noon, its title over the level](screenshots/act3_flock_of_the_sun.jpg)

*III.2 — The Flock of the Sun: islands, swing bridges and the Sun's golden rams.*

**Description**

Act III is where the game found its shape: on October 11 the **two tools, three modifiers**
refactor replaced "one skill per act". The Lamp and the Spindle stay the only two buttons;
the place decides what they do.

- **The sundial**: the Spindle turns the hour. By day the sun shows the truth as the lamp
  does but makes nothing real; at evening the illusions come back.
- **The Sun's rams**: standing by day, lying down at evening as steps.
- **Stairs of the sun**: they stand only by day and crumble at sunset.
- **Jupiter's eagle**: with Space it carries Psyche to a landing no sundial reaches.

From here on difficulty comes from fusing the pieces: III.4 has 54 steps and 11 decisions,
III.5 (the finale) 64 steps and 12 decisions. A solver trick (parts that are the same turned
half way counted once) took III.2 from 135,000 states to 4,000.

---

## Act IV — The Underworld

| | |
|---|---|
| **Date** | October 12–16, 2026 |
| **Tags** | `act-iv` `flip` `two-worlds` `charon` `ferry` `guard` `box` |
| **Meta** | 6 levels (IV.1–IV.6) · the Tower cutscene · IV.6: 81 steps, 15 decisions |

![IV.6 The Open Box under the red sky of Taenarus, its title over the level](screenshots/act4_open_box.jpg)

*IV.6 — The Open Box: the act's finale.*

**Description**

Psyche goes down from the tower of Taenarus to Proserpina's kingdom and comes back with the
box. The longest act.

- **Proserpina's flip**: on a pomegranate, the Spindle turns the world over about an axle.
  A second world hangs under the palace, Proserpina's marble kingdom, and the axle's layer is
  one floor walked on from both sides.
- **Charon's boat**: first IV.1's exit, then a ferry between two landings that stays where it
  took her (IV.4–IV.6).
- **The guard candelabrum**: a seal that shows the stones across a dark stretch.
- **The box** (IV.6): at the exit the camera closes in, the lid lifts, the Stygian sleep pours
  out and Psyche falls asleep.

IV.1 is a tower of Babel widening as it falls, the sky fading from dusk to the red of the
underworld. In IV.4–IV.6 each world has its own soul: crags and pines above, a temple of
pillars and urns below. Only the epilogue is left.

---

## The level select and the side panel

| | |
|---|---|
| **Date** | October 15, 2026 |
| **Tags** | `ui` `level-select` `settings` `book` |
| **Meta** | The chosen level loaded live behind the panel · one side-panel look for levels, settings and the Book |

**Description**

Instead of a list, the chosen level is the real diorama, asleep in the background.

- **The diorama behind**: the chosen level is actually loaded, framed on the right and turning
  slowly, with its own sky and sound. Changing the choice dims the world out and back in.
- **The left panel**: act, title, place, the chapters in Apuleius, the opening line, the
  fragments found and what the place holds (lamp, seals, handles, sundials, eagle, boat…),
  read from the level file rather than written by hand.
- **The pictures below**: the act's levels drawn once per session from a level loaded apart,
  one per frame, without stalling the interface.
- **Controls**: ← → level, ↑ ↓ or LB/RB act, Enter or South to play; the mouse chooses by
  hovering a picture.

The same day the look became **one side panel** shared by the levels, the settings and the
Book: the lamp's side darkened, tabs in capitals along the top, the controls at the foot,
"[Esc] Back" in the corner. The frosted glass of the old settings, with its blur shader, was
removed.

---

## A basin for every diorama

| | |
|---|---|
| **Date** | October 16, 2026 |
| **Tags** | `art` `floors` `basins` `water` `fires` `sound` |
| **Meta** | 17 of 19 levels in a basin (IV.2 and IV.3 keep their void) · marble, rock or earth · water or swamp |

**Description**

A pass of coherence across all the levels: the first acts floated over the void while the
later ones stood in water. Now every place stands on something of its own.

- **The basin**: a low wall on a plinth around the diorama, water inside. Its rim is marble for
  the palaces and temples, living rock for the crags and the Styx, earth for the woods and the
  pasture; the whole diorama stays inside it (the level loader refuses anything on the rim).
- **The fluid**: water coloured by the setting (blue at night, rose at sunset, black on the
  Styx), or a swamp, still and dark, with algae and slow bubbles (II.1).
- **The underworld**: where the world turns over the basin has no bottom, so Proserpina's
  kingdom still hangs beneath it; the rim opens where Charon's boat leaves. IV.2 and IV.3 keep
  their void: there it *is* the hanging world.
- **Two souls**: IV.4 and IV.5 took IV.6's crags above and temple below, every piece kept only
  if the solver's plans stayed the same; IV.5 went to night, with fires that light the stones
  and crackle as she passes, and Charon's boats are now pale wood against the dark.

---

## The kit

| | |
|---|---|
| **Date** | October 16, 2026 |
| **Tags** | `tools` `refactor` `props` `biomes` `level-check` |
| **Meta** | 28 props in one catalogue · 11 biomes · every level's check output unchanged by each step |

**Description**

Before the full playtest, the game's building blocks were made modular, one neutral step at a
time (each proved by the level checks, the tests and before/after screenshots).

- **The props catalogue**: every object (rails, pillars, pines, fires…) is one row saying how it
  holds its cell, whether it turns, what it rests on and whether it burns, plus one row for how
  it looks. A new object is two rows and its shape.
- **Biomes**: a level names its place (`biome palace`, `biome styx`, `biome taenarus`…) and the
  place gives its light, its day and evening, the world under it, its basin, and the objects
  found there; the checks warn of an object foreign to the place.
- **`check --try`**: before any decoration goes in, the tool tries each candidate alone and
  says whether it is refused, harmless, or what it changes (the plan, the illusions of a view,
  a prop hanging in the air).
- **A cleanup**: one lookup by name for every table of the level format, and one kind of step
  for Psyche (walking, a cave, the eagle, the boat) instead of three flags.

Prefabricated pieces ("stamps") and automatic decoration were weighed and postponed: they will
come with the epilogue or the endless mode, when something needs them.
