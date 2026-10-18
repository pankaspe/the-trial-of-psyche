// One playable level and its rules.
//   Dark (default): the illusion edges of the current view are walkable.
//   Lamp lit (levels where Psyche carries it): only real edges, true depth
//   shows, hidden seals appear, oil burns.
//   Q / E turn the diorama: every view has its own illusions.
// A seal lit by the lamp while Psyche stands on it raises hidden blocks.
// Lighting the lamp in Cupid's chamber ends the level (the myth's drop of oil,
// the canonical ending); reaching him in the dark ends it with trust, a secret
// ending open only once the game has been finished (`trust_allowed`).
// Other levels end at their exit. Fragments of the tale (one or more) wait on
// optional spots: picking one up is reported to the app (`fragment_new`), which
// shows its text and waits for the player.
// Cupid's lines never cut each other off: a line said while another is on
// screen waits its turn.
// Two tools, one button each; the place decides what they do:
//   the lamp (1): the truth around her, the seal under her feet, the veiled
//   blocks near her (Act II: they become real for good);
//   the spindle (2, F, or a click on her own cell): on a handle it turns a
//   part of the palace a quarter (Act II); on a sundial it turns the time
//   (Act III).
//
// Day and evening (Act III, a level with sundials): the sky goes down (or up)
// while the game waits. By day the sun shows the truth as the lamp does
// (`dark` is false) and the Sun's golden rams stand in the way; at evening the
// illusions are back and the rams lie down, each a step up. The sun shows,
// only the flame makes real: by day the lamp is not lit (seals and veiled
// blocks wait for the evening), and the sun coming up puts it out.
//
// Caves come in pairs. Standing at the mouth of one, Space (or the card the
// HUD shows over her) takes her through the rock, a step longer than the
// others: she walks into the dark and out of the other. Walks never go
// through a cave by themselves: a click elsewhere must not carry her there.
//
// Jupiter's eagle (Act III) waits on its perch. Standing there, Space (or the
// card over her) calls it: it takes her by the shoulders and carries her to
// its landing, one way, then flies back to its perch. Walks never call it.
//
// Charon's boat (Act IV) is moored at the exit: reaching the landing does not
// end the level; standing there, Space (or the card over her) boards it, she
// gives him the coin and he ferries her away into the mist.
//
// Charon's ferry (Act IV): his boat between two landings, moored where it took
// her last (palace.boats). Standing where it waits, Space (or the card over
// her) boards it and he poles her across: a step of its own, like the eagle's
// flight; walks never take it.
//
// Proserpina's flip (Act IV): standing on one of her pomegranates, the
// spindle turns the world over about the axle while she stays on her stone
// (phase Overturn); the world under the palace stands up, the other hangs
// below. Her cell is of the frame of the world up now (palace.upside).
//
// A level that goes down (`below`): its look at the foot is blended in as she
// descends from the start's height to the exit's (`descent`).
//
// Cutscenes are timelines: a phase plus the time spent in it; every animation
// is a function of that time, so there are no callbacks to keep alive.
//
// Memory: everything that lives as long as the level (parsed data, palace
// graph, scratch arrays) comes from `arena`, freed in one go by `load`.
// Effects (stains, drops, markers) use fixed arrays.
package game

import "core:math"
import "core:mem"
import "core:slice"
import "core:mem/virtual"
import "core:unicode/utf8"
import sa "core:container/small_array"

import "../audio"
import "../content"
import "../fx"
import "../i18n"
import "../iso"
import "../level"
import pl "../palace"

Cell :: iso.Cell
Vec2 :: iso.Vec2
Vec3 :: iso.Vec3
Key :: i18n.Key

OIL_MAX :: 14.0
LIGHT_COST :: 0.4
STEP_TIME :: 0.3
DRIP_EVERY :: 1.4
ROTATE_TIME :: 0.75
RISE_DELAY :: 0.45
RISE_TIME :: 1.4
RISE_DEPTH :: 520.0 / iso.WALL // risen blocks come up from this far below
WELCOME_DELAY :: 1.6 // the start cell's cues, in a level without an intro
INTRO_AT :: 0.8 // the intro line, under the level's title
TEACH_AT :: 0.6 // the card of a new mechanic, before the intro line
MAX_STAINS :: 96
MAX_DROPS :: 8
MAX_MARKERS :: 4
MARKER_TIME :: 0.6
MAX_QUEUED_VOICES :: 4
PART_TIME :: 0.9 // a part of the palace turning a quarter
DISSOLVE_TIME :: 1.2 // a veiled block appearing
PASSAGE_TIME :: 2.4 // through the rock from one cave to the other
PASSAGE_DEPTH :: 0.45 // how far into the mouth she walks before the dark takes her
TIME_TURN :: 2.4 // a sundial turns the time: the sun goes down (or comes up)
FLIGHT_TIME :: 3.6 // carried by the eagle from its perch to its landing
FLIGHT_TAKE :: 0.2 // ...the part of it where the eagle comes down to her...
FLIGHT_LAND :: 0.86 // ...and where she touches the ground again
EAGLE_RETURN :: 3.2 // the eagle flying back to its perch
EAGLE_HOLD :: 0.82 // how far above her feet the eagle holds her
OVERTURN_TIME :: 2.6 // the world turning over on a pomegranate
DESCENT_TIME :: 2.0 // the sky following her down (a level that goes down), at most this long from top to foot

Phase :: enum u8 {
	Play,
	Sigil, // the seal is lit: blocks rise, input waits
	Mechanism, // a handle turns a part of the palace: input waits
	Time, // a sundial turns the time: the sky changes, the rams stand up or lie down; input waits
	Overturn, // a pomegranate: the world turns over about the axle; input waits
	Prologue, // the opening cutscene (prologue.odin): input only skips or starts
	Arrival, // coming from the last level: the palace rises, Psyche comes down; input waits
	Ending_Oil,
	Ending_Trust,
	Ending_Exit,
	Finished,
}

Ending :: enum u8 {
	None,
	Oil, // the lamp lit in Cupid's chamber: the canonical ending
	Trust, // Cupid reached in the dark: the secret ending
	Exit, // the level's exit reached
}

// A line of text that fades in, holds and fades out (hold < 0: until hidden).
Fade_Text :: struct {
	key:      Key,
	active:   bool,
	t:        f32,
	fade_in:  f32,
	hold:     f32,
	fade_out: f32,
	hide_t:   f32, // < 0 unless being hidden
}

Hud :: struct {
	visible: bool,
	title:    Fade_Text,
	voice:    Fade_Text,
	hint:     Fade_Text,
	badge_t:  f32, // time the keys badge (Esc, R) has been on screen
	queued:   sa.Small_Array(MAX_QUEUED_VOICES, Key), // lines waiting for the current one
}

// What a step of Psyche's is.
Step_Kind :: enum u8 {
	Walk, // a step on her feet (or across an illusion)
	Passage, // through the rock between two caves
	Flight, // in the eagle's talons
	Ferry, // a crossing in Charon's boat
}

Psyche :: struct {
	cell:          Cell,
	walking:       bool,
	step_from:     Cell,
	step_to:       Cell,
	step_t:        f32,
	step_illusion: bool,
	step_kind:     Step_Kind,
	pos:           Vec3, // feet, world space
	yaw:           f32, // facing, radians in the world xy plane
	target_yaw:    f32,
	walk_anim:     f32, // grows while walking (bob, wings)
}

Amore :: struct {
	reveal:  f32, // 0 presence only .. 1 seen
	fly_t:   f32, // < 0 until he flies away
	breath:  f32,
	embrace: f32, // 0..1
}

Stain :: struct {
	pos: Vec3,
}

Drop :: struct {
	active: bool,
	from:   Vec3,
	to:     Vec3,
	t:      f32,
}

Marker :: struct {
	active: bool,
	cell:   Cell,
	ok:     bool,
	t:      f32,
}

Game :: struct {
	arena:          virtual.Arena,
	level_index:    int,
	diorama:        int, // the slot's diorama being played (level.dioramas)
	dioramas:       int, // how many the slot has
	fragment_base:  int, // the slot's fragments in the dioramas before this one
	data:           level.Level_Data,
	palace:         pl.Palace,
	loaded:         bool,

	active:         bool, // false on the title screen: the palace sleeps
	phase:          Phase,
	phase_t:        f32,
	ending:         Ending,
	time:           f32,

	lamp_on:        bool,
	light:          f32, // 0..1, follows lamp_on
	oil:            f32,
	flicker:        f32,
	drip:           f32,
	activated:      level.Seals, // the seals that have been lit
	rising:         int, // the seal lit last (phase Sigil: its blocks are rising)
	lightings:      int, // times the lamp was lit

	oil_max:        f32, // the lamp's oil when full (seconds)
	flip_t:         []f32, // per data.blocks entry: time since it changed for good, < 0 before
	part_turning:   int, // the part a handle is turning (phase Mechanism)
	evening:        f32, // 0 day .. 1 evening, follows palace.day (the sky, the rams' pose)
	overturn:       f32, // 0 the world as described .. 1 turned over, follows palace.upside (render turns the world by it)
	descent:        f32, // a level that goes down: 0 at the start's height .. 1 at the exit's (the look at its foot)
	ferried:        bool, // the exit was by Charon's boat (phase Ending_Exit: its own timeline)
	parting:        bool, // the exit leads into the level's next diorama: this one breaks up (no wind, no veil)
	arrive_veiled:  bool, // the arrival comes through the veil (not from the level's diorama before)
	arrive_traced:  bool, // set by the app: between levels, gold traces the blocks as they rise
	boxed:          bool, // the exit opened Proserpina's box (phase Ending_Exit: its own timeline)
	rest:           Rest, // the last brazier Psyche lit
	eagle_flying:   int, // the eagle carrying her (while psyche.step_kind is .Flight)
	eagle_back:     [level.MAX_EAGLES]f32, // per eagle: time since it let her go, < 0 before
	ferry_crossing: int, // the ferry taking her across (while psyche.step_kind is .Ferry)
	rests_lit:      []bool, // per data.rests entry
	teach_pending:  bool, // the level's new mechanic is still to be presented
	mechanic_new:   bool, // event for the app: present the new mechanic now (it clears it)
	teach_card:     bool, // set by the app while the mechanic's card is on screen
	teach_after:    f32, // time since that card was closed, < 0 before
	trust_allowed:  bool, // set by the app: the game has been finished once
	endless_oil:    bool, // set by the app (accessibility): the lamp never runs dry
	reduce_motion:  bool, // set by the app (accessibility): the screen does not shake
	fragments_known: Fragment_Set, // set by the app: collected in an earlier play
	fragments_taken: Fragment_Set, // picked up in this play
	fragment_new:   bool, // event for the app: `fragment_last` just picked up (it clears it)
	fragment_last:  int, // index into data.fragments
	fragment_t:     [level.MAX_FRAGMENTS]f32, // time since each was picked up, < 0 before
	candelabra_lit: bit_set[0 ..< level.MAX_CANDELABRA],
	candelabrum_t:  [level.MAX_CANDELABRA]f32, // time since the lamp lit each, < 0 before (or lit from the start)

	angle:          f32, // continuous view angle in quarter turns (unbounded)
	turning:        bool,
	turn_from:      f32,
	turn_step:      int,
	turn_t:         f32,
	pending_turn:   int,
	reach_before:   []bool, // reachable nodes when a turn started

	path:           pl.Path,
	steering:       bool, // the path is the next step of a stick (or d-pad) held
	steer_wait:     bool, // the view turned (or the world over) under a stick held: it must be let go, pushed again or pointed elsewhere
	steer_held:     Vec2, // ...the way it was held then
	prologue:       Prologue,
	psyche:         Psyche,
	amore:          Amore,

	heard:          [Key]bool,
	hinted:         [Key]bool,
	learned:        [Key]bool, // tutorial hints whose action has been done
	begin_t:        f32, // time since begin(), < 0 before
	pointer_on:     bool, // a light points at Psyche (the level begins, or she was asked for) until she walks
	pointer_title:  bool, // ...once the level's title is gone (at the start, not when asked for)
	pointer:        f32, // its fade, 0..1
	dead_ends:      map[pl.State]struct {}, // the states that cannot reach the goal any more (`find_dead_ends`)
	dead_end:       bool, // Psyche is in one
	cine_out:       f32, // time since the prologue gave way to play, < 0 before (the bars withdraw)
	arrive_t:       f32, // time since the arrival from the last level began, < 0 without one
	rise_t:         [level.MAX_SEALS]f32, // per seal: time since it was lit, < 0 before
	rise_rank:      []int, // per data.rise entry: its place among the blocks of its seal
	lightning_t:    f32, // time since the last lightning, < 0 before (`lightning`)
	collapse_t:     f32, // < 0 until the palace falls
	collapse_keep:  Cell,
	shake_t:        f32,
	shake_duration: f32,

	stains:         [MAX_STAINS]Stain,
	stain_count:    int,
	stain_next:     int,
	drops:          [MAX_DROPS]Drop,
	markers:        [MAX_MARKERS]Marker,
	hud:            Hud,
	rng:            fx.Rng,
}

// What a brazier remembers: the palace and Psyche as they were when she lit it.
Rest :: struct {
	valid:     bool,
	cell:      Cell,
	view:      int,
	flipped:   []bool,
	part_rot:  [level.MAX_PARTS]int,
	day:       bool,
	upside:    bool,
	boats:     level.Boats,
	oil:       f32,
	activated: level.Seals,
	lightings: int,
}

Load_Error :: level.Parse_Error

// (Re)load a level (one of its dioramas): frees everything from the previous one.
load :: proc(g: ^Game, index: int, diorama := 0) -> (err: Maybe(Load_Error)) {
	return load_text(g, index, content.LEVELS[index].source, diorama)
}

// Load diorama `diorama` of level slot `index` from the given level text
// (tests use their own).
load_text :: proc(g: ^Game, index: int, text: string, diorama := 0) -> (err: Maybe(Load_Error)) {
	parts := level.dioramas(text)
	if diorama < 0 || diorama >= len(parts) {
		return Load_Error{0, "no such diorama in the level"}
	}
	base := 0
	for part in parts[:diorama] {
		before, perr := level.parse(part, context.temp_allocator)
		if perr != nil {
			return perr
		}
		base += len(before.fragments)
	}

	arena := g.arena
	if arena.curr_block == nil {
		if virtual.arena_init_growing(&arena) != nil {
			return Load_Error{0, "cannot reserve memory for the level"}
		}
	} else {
		virtual.arena_free_all(&arena)
	}
	g^ = {}
	g.arena = arena
	g.level_index = index
	g.diorama = diorama
	g.dioramas = len(parts)
	g.fragment_base = base
	alloc := virtual.arena_allocator(&g.arena)

	data, perr := level.parse(parts[diorama], alloc)
	if perr != nil {
		return perr
	}
	g.data = data
	pl.init(&g.palace, &g.data, alloc)
	g.reach_before = make([]bool, len(g.palace.solid), alloc) // one per grid cell: enough for any node count
	g.rise_rank = make([]int, len(g.data.rise), alloc)
	for e, i in g.data.rise {
		for f in g.data.rise[:i] {
			g.rise_rank[i] += int(f.seal == e.seal)
		}
	}
	g.flip_t = make([]f32, len(g.data.blocks), alloc)
	g.rest.flipped = make([]bool, len(g.data.blocks), alloc)
	g.rests_lit = make([]bool, len(g.data.rests), alloc)
	for &t in g.flip_t {
		t = -1
	}

	g.oil_max = g.data.oil > 0 ? g.data.oil : OIL_MAX
	g.oil = g.oil_max
	g.flicker = 1
	g.begin_t = -1
	g.cine_out = -1
	g.arrive_t = -1
	g.rise_t = -1
	g.eagle_back = -1
	g.collapse_t = -1
	g.lightning_t = -1
	for &t in g.fragment_t {
		t = -1
	}
	for &t in g.candelabrum_t {
		t = -1
	}
	for c, i in g.data.candelabra {
		if c.lit {
			g.candelabra_lit += {i}
		}
	}
	g.teach_after = -1
	g.amore = {fly_t = -1, breath = 1}
	g.psyche.cell = g.data.start
	g.psyche.pos = pl.stand_world(&g.palace, g.data.start)
	g.psyche.yaw = math.PI * 0.75 // facing the camera
	g.psyche.target_yaw = g.psyche.yaw
	g.rng = fx.rng_init(u32(index) * 7919 + 17)
	g.evening = g.palace.day || len(g.data.sundials) == 0 ? 0 : 1
	g.descent = descent_target(g)
	for c, i in g.data.rests {
		if c == g.data.start {
			light_rest(g, i, quiet = true) // a brazier where she starts is lit already
		}
	}
	g.loaded = true
	return nil
}

// The game's timings, for counting the oil a solver plan burns (palace.oil_left).
oil_rules :: proc(d: ^level.Level_Data) -> pl.Oil_Rules {
	return {
		oil = d.oil > 0 ? d.oil : OIL_MAX,
		light_cost = LIGHT_COST,
		step = STEP_TIME,
		passage = PASSAGE_TIME,
		flight = FLIGHT_TIME,
		ferry = FERRY_TIME,
		turn = ROTATE_TIME,
		handle = PART_TIME,
		overturn = OVERTURN_TIME,
		rise_delay = RISE_DELAY,
		rise_time = RISE_TIME,
	}
}

// Allocator of the level arena: for anything that must live exactly as long as the level.
level_allocator :: proc(g: ^Game) -> mem.Allocator {
	return virtual.arena_allocator(&g.arena)
}

destroy :: proc(g: ^Game) {
	virtual.arena_destroy(&g.arena)
	g^ = {}
}

title_key :: proc(g: ^Game) -> Key {
	return content.LEVELS[g.level_index].title
}

// Leave attract mode and start playing: after the prologue, if the level
// has one and `prologue` is set (a restart does not show it again).
// `arrival`: coming from the last level through the veil, the palace rises
// into place and Psyche comes down onto the start.
// `veiled`: through the veil from another level; a diorama of the same level
// rises in the open, where the one before broke up.
begin :: proc(g: ^Game, prologue := true, arrival := false, veiled := true) {
	g.active = true
	if g.data.has_prologue && prologue {
		prologue_start(g)
		return
	}
	if arrival {
		set_phase(g, .Arrival)
		g.arrive_t = 0
		g.arrive_veiled = veiled
		g.arrive_traced = false
		g.teach_pending = prologue && g.data.mechanic != .None
		if veiled {
			audio.play(.Wind, -10, 0.8)
		} else {
			audio.play(.Rumble, -16, 1.3)
		}
		return
	}
	start_play(g, prologue)
}

// The level is on: the title, the timeline of the first texts, music.
@(private)
start_play :: proc(g: ^Game, prologue: bool) {
	g.hud.visible = true
	if g.diorama == 0 {
		show(&g.hud.title, title_key(g), 1.5, 3.5, 2.0) // the next dioramas are the same level
	}
	g.begin_t = 0
	g.pointer_on = true
	g.pointer_title = true
	// a restart (prologue = false) does not present the mechanic again
	g.teach_pending = prologue && g.data.mechanic != .None
}

// How strongly the pieces of the new mechanic are pointed out: fully while
// its card is on screen, fading a few seconds after.
teach_glow :: proc(g: ^Game) -> f32 {
	if g.teach_card {
		return 1
	}
	if g.teach_after < 0 {
		return 0
	}
	return 1 - fx.clamp01((g.teach_after - 3) / 2)
}

rot :: proc(g: ^Game) -> int {
	return g.palace.rot
}

is_over :: proc(g: ^Game) -> bool {
	return g.phase >= .Ending_Oil
}

// Do the illusions hold now? In the dark: the lamp out, and no sun up.
dark :: proc(g: ^Game) -> bool {
	return !g.lamp_on && !g.palace.day
}

// The place as it looks now: the evening's setting once the sun is down, the
// foot's once she is more than half way down.
setting_now :: proc(g: ^Game) -> level.Setting {
	switch {
	case has_time(g) && g.evening > 0.5: return g.data.evening
	case g.data.has_below && g.descent > 0.5: return g.data.below
	case g.data.has_upside && g.overturn > 0.5: return g.data.upside
	}
	return g.data.setting
}

// How far down she is, from the start's height (0) to the exit's (1), in a
// level that goes down.
@(private)
descent_target :: proc(g: ^Game) -> f32 {
	if !g.data.has_below {
		return 0
	}
	top, foot := f32(g.data.start.z), f32(g.data.exit.z)
	if top <= foot {
		return 0
	}
	return fx.clamp01((top - g.psyche.pos.z) / (top - foot))
}

// How much the truth shows now (the cracks where the illusions were): the
// lamp's light, or the sun up.
truth :: proc(g: ^Game) -> f32 {
	return max(g.light, has_time(g) ? 1 - g.evening : 0)
}

// Does the level turn between day and evening (it has sundials)?
has_time :: proc(g: ^Game) -> bool {
	return len(g.data.sundials) > 0
}

// The level's fragments, by their index in data.fragments.
Fragment_Set :: bit_set[0 ..< level.MAX_FRAGMENTS]

// Fragment i of this level, as an index into content.FRAGMENTS.
fragment_index :: proc(g: ^Game, i: int) -> int {
	first, _ := content.level_fragments(g.level_index)
	return first + g.fragment_base + i
}

// Does the slot go on after this diorama? Its exit then leads into the next.
leads_on :: proc(g: ^Game) -> bool {
	return g.diorama + 1 < g.dioramas
}

// The text of fragment i of this level.
fragment_key :: proc(g: ^Game, i: int) -> Key {
	return content.FRAGMENTS[fragment_index(g, i)].key
}

// --- per frame -------------------------------------------------------------------

update :: proc(g: ^Game, dt: f32) {
	if !g.loaded {
		return
	}
	g.time += dt
	g.phase_t += dt
	g.light = fx.move_toward(g.light, g.lamp_on ? 1 : 0, dt * 3.2)
	g.flicker = 0.93 + 0.05 * math.sin(g.time * 23) + 0.03 * math.sin(g.time * 37 + 1.3)

	if g.lamp_on && g.phase != .Finished {
		if !g.endless_oil {
			g.oil = max(g.oil - dt, 0)
		}
		g.drip += dt
		if g.drip >= DRIP_EVERY {
			g.drip = 0
			drop_oil(g)
		}
		if g.oil <= 0 {
			set_lamp(g, false)
			if g.activated == {} {
				tell_no_oil(g)
			}
		}
	}

	if g.cine_out >= 0 {
		g.cine_out += dt
	}
	if g.begin_t >= 0 {
		before := g.begin_t
		g.begin_t += dt
		if g.teach_pending && before < TEACH_AT && g.begin_t >= TEACH_AT && g.phase == .Play {
			g.teach_pending = false
			g.mechanic_new = true
			audio.play(.Good, -8, audio.semitones(3))
		}
		if g.data.has_intro && before < INTRO_AT && g.begin_t >= INTRO_AT && g.phase == .Play {
			speak(g, g.data.intro)
		}
		// the start cell's hints wait for the intro to be read
		at := start_cues_time(g)
		if before < at && g.begin_t >= at && g.phase == .Play {
			cues(g, g.data.start)
		}
	}

	if has_time(g) {
		g.evening = fx.move_toward(g.evening, g.palace.day ? 0 : 1, dt / TIME_TURN)
	}
	g.overturn = fx.move_toward(g.overturn, g.palace.upside ? 1 : 0, dt / OVERTURN_TIME)
	if g.data.has_below && g.phase != .Prologue {
		g.descent = fx.move_toward(g.descent, descent_target(g), dt / DESCENT_TIME)
	}
	update_turn(g, dt)
	update_walk(g, dt)
	update_effects(g, dt)
	update_hud(g, dt)
	update_pointer(g, dt)
	update_dead_end(g)
	teach_fragments(g)
	// in the dark the music is veiled; her light opens it
	audio.set_veil(g.data.has_lamp ? 1 - g.light : 0)

	if g.lamp_on && g.light > 0.25 && g.phase != .Arrival && g.phase != .Prologue {
		light_candelabra(g)
	}

	switch g.phase {
	case .Play:
		if !g.active {
			break
		}
		psy := g.psyche.cell
		if g.lamp_on {
			warn_trap(g)
		}
		if g.lamp_on && g.light > 0.6 {
			lamp_truth(g)
		}
		if k := seal_at(g, psy); g.lamp_on && g.light > 0.6 && !g.psyche.walking && k >= 0 && k not_in g.activated {
			activate_sigil(g, k)
		} else if g.lamp_on && g.light > 0.3 && in_chamber(g, psy) {
			start_ending(g, .Ending_Oil)
		}
	case .Prologue:
		update_prologue(g, dt)
	case .Arrival:
		g.arrive_t += dt
		g.psyche.pos = pl.stand_world(&g.palace, g.psyche.cell) + {0, 0, arrival_drop(g)}
		if g.arrive_t >= ARRIVE_END {
			pending := g.teach_pending
			set_phase(g, .Play)
			start_play(g, true)
			g.teach_pending = pending
		}
	case .Sigil:
		if g.phase_t >= rise_duration(g, g.rising) {
			set_phase(g, .Play)
		}
	case .Mechanism:
		if g.phase_t >= PART_TIME {
			pl.turn_part(&g.palace, g.part_turning)
			audio.play(.Thud, -6, 0.8)
			shake(g, 0.25)
			set_phase(g, .Play)
		}
	case .Time:
		if g.phase_t >= TIME_TURN {
			set_phase(g, .Play)
		}
	case .Overturn:
		if crossed(g.phase_t, dt, OVERTURN_TIME * 0.92) {
			audio.play(.Thud, -9, 0.6)
		}
		if g.phase_t >= OVERTURN_TIME {
			set_phase(g, .Play)
		}
	case .Ending_Oil:
		update_ending_oil(g, dt)
	case .Ending_Trust:
		update_ending_trust(g)
	case .Ending_Exit:
		if g.ferried {
			update_ferry(g, dt)
		}
		if g.boxed {
			update_box(g, dt)
		}
		if g.phase_t >= exit_end(g) {
			g.ending = .Exit
			set_phase(g, .Finished)
		}
	case .Finished:
	}
}

@(private)
set_phase :: proc(g: ^Game, p: Phase) {
	g.phase = p
	g.phase_t = 0
}

// True on the frame where `t` crosses `mark`.
@(private)
crossed :: proc(t, dt, mark: f32) -> bool {
	return t >= mark && t - dt < mark
}

// --- turning the diorama ---------------------------------------------------------------

request_turn :: proc(g: ^Game, step: int) {
	if !g.active || g.phase != .Play || g.turning {
		return
	}
	if g.psyche.walking {
		// finish the current step, then turn
		sa.clear(&g.path)
		g.pending_turn = step
		return
	}
	start_turn(g, step)
}

@(private)
start_turn :: proc(g: ^Game, step: int) {
	audio.play(.Turn, -11)
	learn(g, .Hint_Turn)
	g.steer_wait = true
	pl.reachable(&g.palace, g.psyche.cell, dark(g), g.reach_before[:len(g.palace.nodes)])
	g.turning = true
	g.turn_from = math.round(g.angle)
	g.turn_step = step
	g.turn_t = 0
}

@(private)
update_turn :: proc(g: ^Game, dt: f32) {
	if !g.turning {
		return
	}
	g.turn_t += dt
	u := min(g.turn_t / ROTATE_TIME, 1)
	g.angle = g.turn_from + f32(g.turn_step) * fx.sine_in_out(u)
	if u < 1 {
		return
	}
	g.angle = g.turn_from + f32(g.turn_step)
	g.turning = false
	pl.set_view(&g.palace, int(math.round(g.angle)))
	after := make([]bool, len(g.palace.nodes), context.temp_allocator)
	pl.reachable(&g.palace, g.psyche.cell, dark(g), after)
	for ok, i in after {
		if ok && !g.reach_before[i] {
			// a new way has opened in this view
			audio.play(.Seam, -16, audio.semitones(-2))
			break
		}
	}
}

// Jump to a view without animation (tests, restarts).
set_view :: proc(g: ^Game, r: int) {
	g.turning = false
	g.angle = f32(r)
	pl.set_view(&g.palace, r)
}

// --- lamp --------------------------------------------------------------------------

toggle_lamp :: proc(g: ^Game) {
	if !g.active || is_over(g) || !g.data.has_lamp || g.phase == .Arrival {
		return
	}
	if g.lamp_on {
		set_lamp(g, false)
		learn(g, .Hint_Oil)
	} else if g.palace.day {
		// the sun shows already; only at evening has the flame work to do
		audio.play(.Blocked, -6)
		hint(g, .Hint_Lamp_Day, 4, true)
	} else if g.oil > 0.05 {
		if !g.endless_oil {
			g.oil = max(g.oil - LIGHT_COST, 0)
		}
		g.lightings += 1
		set_lamp(g, true)
		learn(g, .Hint_Lamp)
		if teaches(g, .Hint_Lamp) {
			// the level that teaches the lamp teaches its oil right after
			hint(g, .Hint_Oil, 0)
		}
	} else {
		audio.play(.Blocked, -6)
		tell_no_oil(g)
	}
}

// The oil is gone: the way out is the brazier, or the level again.
@(private)
tell_no_oil :: proc(g: ^Game) {
	hint(g, has_rest(g) ? .Hint_No_Oil : .Hint_No_Oil_No_Rest, 0, true)
}

@(private)
set_lamp :: proc(g: ^Game, on: bool) {
	if g.lamp_on == on {
		return
	}
	g.lamp_on = on
	g.drip = DRIP_EVERY * 0.5
	if !on && g.hinted[.Hint_Trap] {
		learn(g, .Hint_Trap) // she put the light out in time
	}
	audio.play(on ? .Lamp_On : .Lamp_Off, -4)
}

// Where the flame is, in world space: in Psyche's hand.
lamp_world :: proc(g: ^Game) -> Vec3 {
	p := g.psyche
	side := Vec3{-math.sin(p.yaw), math.cos(p.yaw), 0} // her left hand
	fwd := Vec3{math.cos(p.yaw), math.sin(p.yaw), 0}
	bob := p.walking ? math.abs(math.sin(p.walk_anim * 11)) * 0.02 : 0
	return p.pos + side * 0.13 + fwd * 0.06 + {0, 0, 0.36 + bob}
}

@(private)
drop_oil :: proc(g: ^Game) {
	for &d in g.drops {
		if d.active {
			continue
		}
		c := g.psyche.pos
		d = {
			active = true,
			from   = lamp_world(g),
			to     = {c.x + fx.rand_range(&g.rng, -0.2, 0.2), c.y + fx.rand_range(&g.rng, -0.2, 0.2), c.z},
		}
		return
	}
}

// --- walking -----------------------------------------------------------------------

// A click on the palace, at `point` in proto pixels of the current view.
click :: proc(g: ^Game, point: Vec2) {
	if !g.active || g.phase != .Play || g.turning {
		return
	}
	target, ok := pl.pick(&g.palace, point, g.angle)
	if !ok {
		return
	}
	if target == g.psyche.cell && on_spindle(g) {
		use_spindle(g)
		return
	}
	// while a step is under way, plan from where that step will end
	from := g.psyche.walking ? g.psyche.step_to : g.psyche.cell
	path: pl.Path
	found := pl.find_path(&g.palace, from, target, dark(g), &path)
	if !found && target != from {
		add_marker(g, target, false)
		audio.play(.Blocked, -10)
		other: pl.Path
		if !dark(g) && pl.find_path(&g.palace, from, target, true, &other) {
			hint(g, .Hint_Seam, 3, true)
		} else if dark(g) && pl.find_path(&g.palace, from, target, false, &other) && crosses_hidden_stairs(g, from, other) {
			hint(g, .Hint_Hidden_Stairs, 4, true)
		}
		return
	}
	add_marker(g, target, true)
	learn(g, .Hint_Move)
	g.pending_turn = 0
	g.path = path
	g.steering = false
	if !g.psyche.walking {
		next_step(g)
	}
}

// Can Psyche use the skill in this level? The lamp where she carries it, the
// spindle from the level that teaches it on.
has_skill :: proc(g: ^Game, skill: content.Skill) -> bool {
	switch skill {
	case .Lamp: return g.data.has_lamp
	case .Spindle: return content.skill_known(g.level_index, .Spindle)
	}
	return false
}

// Psyche stands still in play, the palace at rest: a tool or the place can act.
standing :: proc(g: ^Game) -> bool {
	return g.active && g.phase == .Play && !g.turning && !g.psyche.walking
}

// Is she standing still on a handle or a sundial, the spindle ready to turn it?
on_spindle :: proc(g: ^Game) -> bool {
	if !standing(g) || !has_skill(g, .Spindle) {
		return false
	}
	return pl.handle_at(&g.palace, g.psyche.cell) >= 0 || pl.sundial_at(&g.palace, g.psyche.cell) >= 0 || at_pomegranate(g)
}

// Psyche stands still at the mouth of a cave whose other end can be reached.
at_cave :: proc(g: ^Game) -> bool {
	if !standing(g) {
		return false
	}
	i := pl.cave_at(&g.palace, g.psyche.cell)
	return i >= 0 && pl.is_passage(&g.palace, g.psyche.cell, g.data.caves[i ~ 1].cell) && pl.is_real_edge(&g.palace, g.psyche.cell, g.data.caves[i ~ 1].cell)
}

// Into the cave at her feet, out of the other end.
enter_cave :: proc(g: ^Game) -> bool {
	if !at_cave(g) {
		return false
	}
	sa.clear(&g.path)
	sa.push_back(&g.path, g.data.caves[pl.cave_at(&g.palace, g.psyche.cell) ~ 1].cell)
	g.pending_turn = 0
	next_step(g)
	return true
}

// Psyche stands still on an eagle's perch (the action of the place shows).
on_perch :: proc(g: ^Game) -> bool {
	return standing(g) && pl.eagle_at(&g.palace, g.psyche.cell) >= 0
}

// ...and it can carry her: where it would set her down there is a floor.
at_eagle :: proc(g: ^Game) -> bool {
	return on_perch(g) && pl.eagle_flies(&g.palace, pl.eagle_at(&g.palace, g.psyche.cell))
}

// The eagle on the perch at her feet carries her to its landing; with no
// floor there, it does not stir (and she is told why).
call_eagle :: proc(g: ^Game) -> bool {
	if !on_perch(g) {
		return false
	}
	if !at_eagle(g) {
		audio.play(.Blocked, -8)
		hint(g, .Hint_Eagle_No_Floor, 4, true)
		return true
	}
	i := pl.eagle_at(&g.palace, g.psyche.cell)
	psy := &g.psyche
	g.eagle_flying = i
	g.eagle_back[i] = -1
	carry(g, g.data.eagles[i].to, .Flight)
	face_toward(g, pl.node_world(&g.palace, psy.step_to) - pl.node_world(&g.palace, psy.step_from))
	learn(g, .Hint_Eagle)
	audio.play(.Wings, -8)
	return true
}

// Psyche stands still on the landing where Charon's boat is moored.
at_boat :: proc(g: ^Game) -> bool {
	return standing(g) && g.data.has_boat && g.psyche.cell == g.data.boat.cell
}

// Into Charon's boat: the level ends as he ferries her away.
board_boat :: proc(g: ^Game) -> bool {
	if !at_boat(g) {
		return false
	}
	learn(g, .Hint_Boat)
	g.ferried = true
	start_ending(g, .Ending_Exit)
	face_toward(g, boat_dir(g))
	return true
}

// Psyche stands still on a landing of Charon's ferry where his boat waits.
at_ferry :: proc(g: ^Game) -> bool {
	if !standing(g) {
		return false
	}
	f, k := pl.ferry_at(&g.palace, g.psyche.cell)
	return f >= 0 && pl.boat_moored(g.palace.boats, f, k)
}

// Into the ferry's boat, across to its other landing; at a landing the boat
// has left, nothing (and she is told why).
board_ferry :: proc(g: ^Game) -> bool {
	if !standing(g) {
		return false
	}
	f, k := pl.ferry_at(&g.palace, g.psyche.cell)
	if f < 0 {
		return false
	}
	to := g.data.ferries[f].ends[1 - k].cell
	if !pl.boat_moored(g.palace.boats, f, k) || !pl.is_surface(&g.palace, to) {
		audio.play(.Blocked, -8)
		hint(g, .Hint_Ferry_Away, 4, true)
		return true
	}
	g.ferry_crossing = f
	carry(g, to, .Ferry)
	face_toward(g, crossing_point(g, FERRY_IN) - g.psyche.pos)
	learn(g, .Hint_Boat)
	return true
}

// Start walking to `target` as a click on it would (tests, scripted scenes).
walk_to :: proc(g: ^Game, target: Cell) -> bool {
	from := g.psyche.walking ? g.psyche.step_to : g.psyche.cell
	if !pl.find_path(&g.palace, from, target, dark(g), &g.path) {
		return false
	}
	if !g.psyche.walking {
		next_step(g)
	}
	return true
}

// Steered with a pad: Psyche steps to the neighbour that lies the way `dir`
// points on screen (y down), over the same edges a click would use (the
// illusions of this view in the dark, real edges in the light, stairs seen),
// and keeps walking while it is held. The next step is chosen from where the
// current one ends, so she does not stop between cells. `dir` zero: she stops
// at the end of the step. `fresh`: the stick was just pushed (a way that is
// not there is answered once, not every frame). After a turn of the view
// (or of the world) the stick held still points where it did on screen, now
// another way through the palace (often back): it must be let go or pushed
// again.
steer :: proc(g: ^Game, dir: Vec2, fresh: bool) {
	if !g.active || g.phase != .Play || g.turning {
		return
	}
	if g.steer_wait {
		if g.steer_held == {} {
			g.steer_held = dir
		}
		if dir != {} && !fresh && dir.x * g.steer_held.x + dir.y * g.steer_held.y > 0.8 {
			return
		}
		g.steer_wait, g.steer_held = false, {}
	}
	psy := &g.psyche
	if dir == {} || g.pending_turn != 0 {
		if g.steering {
			sa.clear(&g.path)
			g.steering = false
		}
		return
	}
	from := psy.walking ? psy.step_to : psy.cell
	next, ok := step_toward(g, from, dir, dark(g))
	if !ok {
		if g.steering {
			sa.clear(&g.path)
			g.steering = false
		}
		if fresh && !psy.walking {
			audio.play(.Blocked, -12)
			if _, seam := step_toward(g, from, dir, true); seam && !dark(g) {
				hint(g, .Hint_Seam, 3, true)
			} else if _, hidden := step_toward(g, from, dir, false); hidden && dark(g) {
				hint(g, .Hint_Hidden_Stairs, 4, true)
			}
		}
		return
	}
	if g.steering && sa.len(g.path) == 1 && sa.get(g.path, 0) == next {
		return
	}
	if !g.steering {
		learn(g, .Hint_Move)
	}
	sa.clear(&g.path)
	sa.push_back(&g.path, next)
	g.steering = true
	if !psy.walking {
		next_step(g)
	}
}

// The neighbour of `from` that lies the way `dir` points on screen, over the
// edges of the dark (`dark`: illusions, seen stairs) or of the light. Caves
// are never stepped into (Space, on purpose). Each step points along the
// floor's grid as the view shows it (`step_dir`); the nearest within about
// 70 degrees wins, and between steps that point the same way, the nearer to
// the camera (the one a click there would pick).
step_toward :: proc(g: ^Game, from: Cell, dir: Vec2, dark: bool) -> (next: Cell, ok: bool) {
	p := &g.palace
	a := pl.node_index(p, from)
	if a < 0 {
		return
	}
	best: f32 = 0.35
	best_depth: i32
	for graph in ([]^pl.Graph{&p.real, &p.illusion}) {
		if graph == &p.illusion && !dark {
			break
		}
		for b in pl.neighbours(graph, a) {
			cell := p.nodes[b].cell
			if !pl.step_allowed(p, a, b, dark) || pl.is_passage(p, from, cell) {
				continue
			}
			d := step_dir(g, from, cell)
			c := d.x * dir.x + d.y * dir.y
			v := iso.to_view(cell, p.rot, p.size)
			depth := v.x + v.y + v.z
			if c > best + 1e-4 || (ok && abs(c - best) <= 1e-4 && depth > best_depth) {
				best, best_depth = c, depth
				next, ok = cell, true
			}
		}
	}
	return
}

// The way a step from cell a to its neighbour b points on screen: along the
// floor's grid in the current view, heights left out (a stair climbs along
// its own side), and an illusion's lift k taken off (it looks like a plain
// step: (x', y', h) to (x'+dx+k, y'+dy+k, h+k)). One of four diagonals.
step_dir :: proc(g: ^Game, a, b: Cell) -> Vec2 {
	p := &g.palace
	av := iso.to_view(a, p.rot, p.size)
	bv := iso.to_view(b, p.rot, p.size)
	d := bv - av
	if pl.is_illusion(p, a, b) {
		d.x -= d.z
		d.y -= d.z
	}
	s := iso.project({f32(d.x), f32(d.y), 0})
	l := math.sqrt(s.x * s.x + s.y * s.y)
	return l > 1e-6 ? s / l : {}
}

// Psyche sets off from her cell toward `to`.
@(private)
begin_step :: proc(g: ^Game, to: Cell, kind: Step_Kind, illusion := false) {
	psy := &g.psyche
	psy.step_from = psy.cell
	psy.step_to = to
	psy.step_t = 0
	psy.step_illusion = illusion
	psy.step_kind = kind
	psy.walking = true
}

// Psyche carried to `to` (the eagle, the boat): whatever she was walking to
// or turning is forgotten.
@(private)
carry :: proc(g: ^Game, to: Cell, kind: Step_Kind) {
	sa.clear(&g.path)
	g.pending_turn = 0
	g.steering = false
	begin_step(g, to, kind)
}

@(private)
next_step :: proc(g: ^Game) {
	psy := &g.psyche
	if sa.len(g.path) == 0 || g.phase != .Play {
		stop_walking(g)
		return
	}
	next := sa.get(g.path, 0)
	illusion := pl.is_illusion(&g.palace, psy.cell, next)
	passage := pl.is_passage(&g.palace, psy.cell, next)
	if !pl.is_real_edge(&g.palace, psy.cell, next) && !(illusion && dark(g)) {
		// the way has changed under her (a part turned away)
		sa.clear(&g.path)
		audio.play(.Blocked, -8)
		stop_walking(g)
		return
	}
	if illusion && !dark(g) && !pl.is_real_edge(&g.palace, psy.cell, next) {
		sa.clear(&g.path)
		audio.play(.Blocked, -8)
		hint(g, .Hint_Seam, 3, true)
		stop_walking(g)
		return
	}
	if dark(g) && !pl.step_allowed(&g.palace, pl.node_index(&g.palace, psy.cell), pl.node_index(&g.palace, next), true) {
		// the lamp went out on the way: stairs hidden in this view are gone
		sa.clear(&g.path)
		audio.play(.Blocked, -8)
		hint(g, .Hint_Hidden_Stairs, 4, true)
		stop_walking(g)
		return
	}
	sa.pop_front(&g.path)
	begin_step(g, next, passage ? .Passage : .Walk, illusion && !passage)
	if psy.step_illusion {
		audio.play(.Seam, -18)
		learn(g, .Hint_Illusion)
	}
	if passage {
		audio.play(.Wind, -15, 0.55)
	}
	a, _ := step_points(g, 0)
	b, _ := step_points(g, 0.49)
	face_toward(g, b - a)
}

// How long the current step lasts.
step_time :: proc(g: ^Game) -> f32 {
	switch g.psyche.step_kind {
	case .Passage: return PASSAGE_TIME
	case .Flight: return FLIGHT_TIME
	case .Ferry: return FERRY_TIME
	case .Walk:
	}
	return STEP_TIME
}

// Where the dark of cave i begins: inside its mouth, toward the rock.
cave_inside :: proc(g: ^Game, i: int) -> Vec3 {
	c := g.data.caves[i]
	d := iso.DIR_VEC[c.dir]
	return pl.node_world(&g.palace, c.cell) + {f32(d.x), f32(d.y), 0} * PASSAGE_DEPTH
}

// How much of Psyche the dark of a cave leaves seen (1 outside).
passage_alpha :: proc(g: ^Game) -> f32 {
	psy := &g.psyche
	if !psy.walking || psy.step_kind != .Passage {
		return 1
	}
	u := psy.step_t / PASSAGE_TIME
	return u < 0.5 ? 1 - fx.sine_in_out(fx.progress(u, 0.18, 0.22)) : fx.sine_in_out(fx.progress(u, 0.6, 0.22))
}

// Does the (lamp-lit) path from `from` use stairs that are hidden in this view?
@(private)
crosses_hidden_stairs :: proc(g: ^Game, from: Cell, path: pl.Path) -> bool {
	prev := pl.node_index(&g.palace, from)
	for i in 0 ..< sa.len(path) {
		cur := pl.node_index(&g.palace, sa.get(path, i))
		if !pl.step_allowed(&g.palace, prev, cur, true) {
			return true
		}
		prev = cur
	}
	return false
}

@(private)
stop_walking :: proc(g: ^Game) {
	g.psyche.walking = false
	if g.pending_turn != 0 && g.phase == .Play {
		step := g.pending_turn
		g.pending_turn = 0
		start_turn(g, step)
	}
}

// Position along the current step (u in 0..1). An illusion step walks to the
// edge of the first surface, then continues from the matching edge of the
// second one: both edges fall on the same screen spot, so the walk looks
// continuous while Psyche always stands on real stone.
step_points :: proc(g: ^Game, u: f32) -> (pos: Vec3, second_half: bool) {
	psy := &g.psyche
	a := pl.node_world(&g.palace, psy.step_from)
	b := pl.node_world(&g.palace, psy.step_to)
	switch psy.step_kind {
	case .Passage:
		// into the dark of one mouth, out of the other
		i, j := pl.cave_at(&g.palace, psy.step_from), pl.cave_at(&g.palace, psy.step_to)
		if u < 0.5 {
			return fx.lerp(a, cave_inside(g, i), fx.sine_in_out(u * 2)), false
		}
		return fx.lerp(cave_inside(g, j), b, fx.sine_in_out((u - 0.5) * 2)), true
	case .Flight:
		return flight_point(g, a, b, u), u >= 0.5
	case .Ferry:
		return crossing_point(g, u), u >= 0.5
	case .Walk:
	}
	if !psy.step_illusion {
		return walk_point(g, psy.step_from, psy.step_to, u), u >= 0.5
	}
	r, size := g.palace.rot, g.palace.size
	av := iso.to_view(psy.step_from, r, size)
	bv := iso.to_view(psy.step_to, r, size)
	k := bv.z - av.z
	d := [2]f32{f32(bv.x - av.x - k), f32(bv.y - av.y - k)}
	edge_view := Vec3{f32(av.x) + 0.5 + d.x * 0.5, f32(av.y) + 0.5 + d.y * 0.5, f32(av.z)}
	if u < 0.5 {
		edge_a := iso.world_point(edge_view, f32(r), size)
		return fx.lerp(a, edge_a, u * 2), false
	}
	edge_b := iso.world_point(edge_view + f32(k), f32(r), size)
	return fx.lerp(edge_b, b, (u - 0.5) * 2), true
}

// Where the eagle holds her along a flight from a to b (u = 0..1): she waits
// for it, is lifted, carried high over the gorge, set down.
flight_point :: proc(g: ^Game, a, b: Vec3, u: f32) -> Vec3 {
	k := fx.progress(u, FLIGHT_TAKE, FLIGHT_LAND - FLIGHT_TAKE)
	s := fx.sine_in_out(k)
	high := 1.3 + abs(a.z - b.z) * 0.5
	return fx.lerp(a, b, s) + {0, 0, high * math.sin(math.PI * k)}
}

// Where eagle i is, which way it faces (world yaw) and how far its wings are
// spread (0 folded on its perch .. 1 open).
eagle_pose :: proc(g: ^Game, i: int) -> (pos: Vec3, yaw: f32, spread: f32) {
	e := g.data.eagles[i]
	perch := Vec3{f32(e.from.x), f32(e.from.y), f32(e.from.z)} + EAGLE_PERCH
	land := pl.node_world(&g.palace, e.to)
	out := land - pl.node_world(&g.palace, e.from)
	yaw = math.atan2(out.y, out.x)
	psy := &g.psyche
	if psy.walking && psy.step_kind == .Flight && g.eagle_flying == i {
		u := psy.step_t / FLIGHT_TIME
		held := psy.pos + {0, 0, EAGLE_HOLD}
		if u < FLIGHT_TAKE {
			// off the perch, a wingbeat up, down onto her shoulders
			k := fx.sine_in_out(u / FLIGHT_TAKE)
			return fx.lerp(perch, held, k) + {0, 0, 0.5 * math.sin(math.PI * k)}, yaw, k
		}
		return held, yaw, 1
	}
	if t := g.eagle_back[i]; t >= 0 && t < EAGLE_RETURN {
		// up from where it let her go and back over the gorge to its perch
		k := fx.sine_in_out(t / EAGLE_RETURN)
		from := land + {0, 0, EAGLE_HOLD}
		home := perch - from
		return fx.lerp(from, perch, k) + {0, 0, (1.8 + abs(home.z) * 0.5) * math.sin(math.PI * k)}, math.atan2(home.y, home.x), 1 - fx.progress(t, EAGLE_RETURN * 0.85, EAGLE_RETURN * 0.15)
	}
	return perch, yaw, 0
}

// Where the eagle sits on its post, in cell space (the post: render's Perch).
EAGLE_PERCH :: Vec3{0.78, 0.22, 0.86}

// A point on the way from cell a to the next cell b (u = 0..1), on the
// ground: stairs are climbed tread by tread.
walk_point :: proc(g: ^Game, a, b: Cell, u: f32) -> Vec3 {
	p := fx.lerp(pl.node_world(&g.palace, a), pl.node_world(&g.palace, b), u)
	on_a, on_b := pl.is_stair(&g.palace, a), pl.is_stair(&g.palace, b)
	if on_a || on_b {
		p.z = pl.stair_ground(&g.palace, on_a && (!on_b || u < 0.5) ? a : b, p)
	}
	return p
}

@(private)
face_toward :: proc(g: ^Game, d: Vec3) {
	if d.x * d.x + d.y * d.y > 1e-6 {
		g.psyche.target_yaw = math.atan2(d.y, d.x)
	}
}

// Face a world point (cutscenes).
face_point :: proc(g: ^Game, p: Vec3) {
	face_toward(g, p - g.psyche.pos)
}

// A footfall on what is under her: grass (a lawn, or living rock with a
// grassy top), bare rock (lower), or masonry.
@(private)
footstep :: proc(g: ^Game, cell: Cell) {
	// the marks of living rock and lawns are kept in the world as described
	here, below := cell, Cell{cell.x, cell.y, cell.z - 1}
	if g.palace.upside {
		here, below = level.flip_cell(&g.data, here), level.flip_cell(&g.data, below)
	}
	vary := fx.rand_range(&g.rng, 0.93, 1.07)
	for c in g.data.lawn {
		if c == below {
			audio.play(.Step_Grass, -15, vary)
			return
		}
	}
	for c in g.data.ground {
		if c == below || c == here {
			audio.play(.Step_Stone, -16, vary * 0.88)
			return
		}
	}
	audio.play(.Step_Stone, -16, vary)
}

@(private)
update_walk :: proc(g: ^Game, dt: f32) {
	psy := &g.psyche
	// turn smoothly toward the target yaw, the short way round
	psy.yaw += short_turn(psy.yaw, psy.target_yaw) * min(dt * 14, 1)

	if !psy.walking {
		psy.pos = pl.stand_world(&g.palace, psy.cell) + {0, 0, exit_lift(g) + overturn_lift(g)}
		return
	}
	psy.walk_anim += dt
	before := psy.step_t
	psy.step_t += dt
	u := min(psy.step_t / step_time(g), 1)
	psy.pos, _ = step_points(g, u)
	if psy.step_kind == .Ferry {
		update_crossing(g, dt)
	}
	if psy.step_kind == .Passage && before < PASSAGE_TIME * 0.5 && psy.step_t >= PASSAGE_TIME * 0.5 {
		// in the dark of the rock: she comes out of the other mouth, facing out
		out, _ := step_points(g, 0.51)
		face_toward(g, pl.node_world(&g.palace, psy.step_to) - out)
		psy.yaw = psy.target_yaw
		audio.play(.Drip, -14, 0.6)
	}
	if u < 1 {
		return
	}
	psy.cell = psy.step_to
	psy.pos = pl.stand_world(&g.palace, psy.cell)
	#partial switch psy.step_kind {
	case .Flight:
		// the eagle lets her go and flies home
		g.eagle_back[g.eagle_flying] = 0
		psy.step_kind = .Walk
	case .Ferry:
		// the boat stays at this landing
		g.palace.boats ~= {g.ferry_crossing}
		psy.step_kind = .Walk
	}
	footstep(g, psy.cell)
	arrive(g, psy.cell)
	next_step(g)
}

// The voice lines and hints tied to cell n (each is given once per level).
@(private)
cues :: proc(g: ^Game, n: Cell) {
	for v in g.data.voices {
		if v.cell == n && upright(g, v.under) {
			say(g, v.key)
		}
	}
	for h in g.data.hints {
		if h.cell == n && upright(g, h.under) {
			hint(g, h.key, is_tutorial(h.key) ? 0 : 7)
		}
	}
}

@(private)
arrive :: proc(g: ^Game, n: Cell) {
	cues(g, n)
	for c, i in g.data.rests {
		if c == n && !g.palace.upside {
			light_rest(g, i)
		}
	}
	for c, i in g.data.fragments {
		if n == c && upright(g, i in g.data.fragments_under) && i not_in g.fragments_taken && i not_in g.fragments_known {
			take_fragment(g, i)
		}
	}
	if g.phase != .Play {
		return
	}
	if g.data.has_exit && n == g.data.exit && upright(g, g.data.exit_under) && !g.data.has_boat {
		start_ending(g, .Ending_Exit)
	} else if g.data.has_boat && n == g.data.boat.cell {
		hint(g, .Hint_Boat, 0)
	} else if f, k := pl.ferry_at(&g.palace, n); f >= 0 && pl.boat_moored(g.palace.boats, f, k) {
		hint(g, .Hint_Boat, 0)
	} else if !g.lamp_on && g.data.has_amore && adjacent_to_amore(g, n) {
		if g.trust_allowed {
			start_ending(g, .Ending_Trust)
		} else {
			// the story goes on only with the lamp: Psyche doubts
			say(g, .V_Doubt)
		}
	}
}

@(private)
take_fragment :: proc(g: ^Game, i: int) {
	g.fragments_taken += {i}
	g.fragment_new = true
	g.fragment_last = i
	g.fragment_t[i] = 0
	sa.clear(&g.path) // she stops to read
	learn(g, .Hint_Fragment)
	audio.play(.Good, -8, audio.semitones(7))
}

// Where fragment i lies (a scroll floating over its cell), in the frame of
// its own world (`fragments_under`).
fragment_world :: proc(g: ^Game, i: int) -> Vec3 {
	c := g.data.fragments[i]
	return {f32(c.x) + 0.5, f32(c.y) + 0.5, f32(c.z) + 0.22 + 0.04 * math.sin(g.time * 1.6 + f32(i) * 2.1)}
}

@(private)
add_marker :: proc(g: ^Game, c: Cell, ok: bool) {
	slot := 0
	for m, i in g.markers {
		if !m.active || m.t > g.markers[slot].t {
			slot = i
			if !m.active {
				break
			}
		}
	}
	g.markers[slot] = {true, c, ok, 0}
}

// --- Act II: the lamp's truth, handles ---------------------------------------------------

// The light close to Psyche makes veiled blocks real.
@(private)
lamp_truth :: proc(g: ^Game) {
	psy := &g.psyche
	keep := [2]Cell{psy.cell, psy.walking ? psy.step_to : psy.cell}
	if !pl.lamp_touch(&g.palace, psy.cell, keep[:]) {
		return
	}
	for &t, i in g.flip_t {
		if t >= 0 || !g.palace.flipped[i] {
			continue
		}
		t = 0
		audio.play(.Good, -14, audio.semitones(-5))
		learn(g, .Hint_Veiled)
	}
}

TRAP_SEEN :: 5.0 // cells: a corrupt stone this near her lamp is seen, and its tutorial given

// A corrupt stone in the light of her lamp, still veiled: what it is (once).
@(private)
warn_trap :: proc(g: ^Game) {
	for e, i in g.data.blocks {
		if !e.trap || g.palace.flipped[i] || !upright(g, e.under) {
			continue
		}
		c := level.frame_cell(&g.data, e.cell, e.under, g.palace.upside)
		d := Vec3{f32(c.x) + 0.5, f32(c.y) + 0.5, f32(c.z)} - g.psyche.pos
		if d.x * d.x + d.y * d.y + d.z * d.z < TRAP_SEEN * TRAP_SEEN {
			hint(g, .Hint_Trap, 10)
			return
		}
	}
}

// Is she on a sundial (where the spindle turns the time)?
at_sundial :: proc(g: ^Game) -> bool {
	return pl.sundial_at(&g.palace, g.psyche.cell) >= 0
}

// The spindle: on a handle it turns its part of the palace a quarter, on a
// sundial it turns the time, on a pomegranate it turns the world over.
// Anywhere else nothing happens.
use_spindle :: proc(g: ^Game) {
	if !on_spindle(g) {
		return
	}
	if pl.sundial_at(&g.palace, g.psyche.cell) >= 0 {
		turn_time(g)
		return
	}
	if at_pomegranate(g) {
		turn_over(g)
		return
	}
	h := pl.handle_at(&g.palace, g.psyche.cell)
	g.part_turning = g.data.handles[h].part
	set_phase(g, .Mechanism)
	audio.play(.Turn, -4, 0.6)
	learn(g, .Hint_Handle)
}

// How far part n is turned now, in quarter turns (animated while a handle turns it).
part_angle :: proc(g: ^Game, n: int) -> f32 {
	a := f32(g.palace.part_rot[n])
	if g.phase == .Mechanism && g.part_turning == n {
		a += fx.sine_in_out(fx.clamp01(g.phase_t / PART_TIME))
	}
	return a
}

// --- day and evening ------------------------------------------------------------------

// The spindle on a sundial: the time turns. The palace changes at once (the
// rams stand up or lie down while the sky goes); the game waits. The sun
// coming up puts the lamp out.
@(private)
turn_time :: proc(g: ^Game) {
	if !g.palace.day {
		set_lamp(g, false)
	}
	pl.set_day(&g.palace, !g.palace.day)
	set_phase(g, .Time)
	audio.play(.Wind, -12, g.palace.day ? 1.1 : 0.7)
	audio.play(.Good, -12, audio.semitones(g.palace.day ? 7 : -5))
	learn(g, .Hint_Sundial)
}

// How far the rams have lain down: 0 standing (day) .. 1 lying (evening).
ram_lie :: proc(g: ^Game) -> f32 {
	return fx.sine_in_out(g.evening)
}

// --- Proserpina's flip -----------------------------------------------------------------

// Is she on one of Proserpina's pomegranates, with room to stand on the other
// side of her stone (the spindle turns the world over there)?
at_pomegranate :: proc(g: ^Game) -> bool {
	return pl.can_turn_over(&g.palace, g.psyche.cell)
}

// The spindle on a pomegranate: the world turns over about the axle, she
// stays on her stone. The palace changes at once (the world under it stands
// up); the game waits while render turns it.
@(private)
turn_over :: proc(g: ^Game) {
	pl.set_upside(&g.palace, !g.palace.upside)
	set_phase(g, .Overturn)
	sa.clear(&g.path)
	g.steer_wait = true
	g.markers = {}
	// the oil spilt stays on its stones: in the frame of the world up now
	for &st in g.stains[:g.stain_count] {
		st.pos = turned_point(g, st.pos)
	}
	for &d in g.drops {
		d.active = false
	}
	audio.play(.Rumble, -10, 0.55)
	audio.play(.Wind, -12, 0.6)
	audio.play(.Reveal, -14, audio.semitones(-7))
	learn(g, .Hint_Pomegranate)
}

// How far she is lifted off her stone while it turns over under her feet
// (a cube on its edge stands taller than on its face).
overturn_lift :: proc(g: ^Game) -> f32 {
	if g.phase != .Overturn {
		return 0
	}
	return 0.24 * math.sin(math.PI * fx.clamp01(g.phase_t / OVERTURN_TIME))
}

// A world point in the frame of the world turned over: the half turn about
// the axle (level.flip_cell, for points).
turned_point :: proc(g: ^Game, w: Vec3) -> Vec3 {
	return {w.x, f32(g.data.size) - w.y, f32(2 * g.data.axle + 1) - w.z}
}

// Does a thing of the world `under` (or above) stand up now (not hanging below)?
upright :: proc(g: ^Game, under: bool) -> bool {
	return pl.upright(&g.palace, under)
}

// --- braziers -----------------------------------------------------------------------

REST_TUTORIAL :: 10 // seconds the brazier's tutorial stays, unless she goes back to it first

@(private)
light_rest :: proc(g: ^Game, i: int, quiet := false) {
	if !g.rests_lit[i] {
		g.rests_lit[i] = true
		if !quiet {
			audio.play(.Lamp_On, -10, audio.semitones(-5))
			hint(g, .Hint_Rest, REST_TUTORIAL)
		}
	}
	r := &g.rest
	r.valid = true
	r.cell = g.data.rests[i]
	r.view = g.palace.rot
	copy(r.flipped, g.palace.flipped)
	r.part_rot = g.palace.part_rot
	r.day = g.palace.day
	r.upside = g.palace.upside
	r.boats = g.palace.boats
	r.oil = g.oil
	r.activated = g.activated
	r.lightings = g.lightings
}

has_rest :: proc(g: ^Game) -> bool {
	return g.rest.valid && g.phase == .Play
}

// Back to the last brazier: the palace and Psyche as they were there.
// False when she is there already with nothing changed (the app then
// restarts the whole level: a brazier may remember a lost cause).
return_to_rest :: proc(g: ^Game) -> bool {
	if !has_rest(g) {
		return false
	}
	learn(g, .Hint_Rest)
	r := &g.rest
	if g.psyche.cell == r.cell && !g.psyche.walking && slice.equal(g.palace.flipped, r.flipped) && g.palace.part_rot == r.part_rot && g.palace.day == r.day && g.palace.upside == r.upside && g.palace.boats == r.boats && g.activated == r.activated {
		return false
	}
	set_lamp(g, false)
	g.light = 0
	g.oil = r.oil
	g.lightings = r.lightings
	copy(g.palace.flipped, r.flipped)
	g.palace.part_rot = r.part_rot
	g.palace.day = r.day
	g.evening = r.day || !has_time(g) ? 0 : 1
	if g.palace.upside != r.upside {
		g.stain_count, g.stain_next = 0, 0 // the oil spilt was of the other frame
	}
	g.palace.upside = r.upside
	g.palace.boats = r.boats
	g.overturn = r.upside ? 1 : 0
	g.activated = r.activated
	g.palace.risen = r.activated
	for c, i in g.data.candelabra {
		if c.guard && int(c.seal) not_in r.activated {
			g.candelabra_lit -= {i}
			g.candelabrum_t[i] = -1
		}
	}
	for &t, k in g.rise_t {
		t = k in r.activated ? 1e3 : -1
	}
	pl.rebuild_graph(&g.palace)
	for &t, i in g.flip_t {
		t = g.palace.flipped[i] ? 1e3 : -1
	}
	set_view(g, r.view)
	g.pending_turn = 0
	sa.clear(&g.path)
	psy := &g.psyche
	psy.walking = false
	psy.cell = r.cell
	psy.pos = pl.stand_world(&g.palace, r.cell)
	g.markers = {}
	audio.play(.Wind, -14)
	return true
}

// --- story events ----------------------------------------------------------------

in_chamber :: proc(g: ^Game, n: Cell) -> bool {
	if !g.data.has_amore || !pl.is_surface(&g.palace, n) {
		return false
	}
	a := g.data.amore
	return n.z == a.z && iso.manhattan2(n, a) <= 2
}

adjacent_to_amore :: proc(g: ^Game, n: Cell) -> bool {
	a := g.data.amore
	return n.z == a.z && iso.manhattan2(n, a) == 1
}

amore_world :: proc(g: ^Game) -> Vec3 {
	a := g.data.amore
	return {f32(a.x) + 0.5, f32(a.y) + 0.5, f32(a.z) + 0.3}
}

// The seal at feet cell c (index into data.sigils), or -1.
seal_at :: proc(g: ^Game, c: Cell) -> int {
	for s, k in g.data.sigils {
		if s == c && upright(g, k in g.data.sigils_under) {
			return k
		}
	}
	return -1
}

SEAL_SENSE :: 3.0 // cells: an unlit seal or a veiled stone feels the flame she carries this near, in the dark

// How strongly something at surface cell c answers the unlit lamp she carries:
// 0 .. 1 as she comes within SEAL_SENSE cells of it in the dark.
@(private)
flame_sense :: proc(g: ^Game, c: Cell) -> f32 {
	if !g.data.has_lamp || !dark(g) {
		return 0
	}
	d := Vec3{f32(c.x) + 0.5, f32(c.y) + 0.5, f32(c.z)} - g.psyche.pos
	dist := math.sqrt(d.x * d.x + d.y * d.y + 2 * d.z * d.z)
	return 1 - math.smoothstep(f32(SEAL_SENSE * 0.5), SEAL_SENSE, dist)
}

// How strongly the k-th seal, not yet lit, answers the lamp she carries (never
// by day, with the lamp lit, for a guard, on a stone not yet there or in the
// world hanging).
seal_sense :: proc(g: ^Game, k: int) -> f32 {
	under := k in g.data.sigils_under
	if k in g.activated || k in g.data.guard_seals || !upright(g, under) {
		return 0
	}
	c := level.frame_cell(&g.data, g.data.sigils[k], under, g.palace.upside)
	if !pl.is_surface(&g.palace, c) {
		return 0
	}
	return flame_sense(g, c)
}

// How strongly block i, veiled and not yet real, answers the lamp she carries
// (its top: the place the stone will be walked on).
veil_sense :: proc(g: ^Game, i: int) -> f32 {
	e := g.data.blocks[i]
	if e.trait != .Veiled || g.palace.flipped[i] || !upright(g, e.under) {
		return 0
	}
	return flame_sense(g, pl.block_cell(&g.palace, i) + {0, 0, 1})
}

@(private)
activate_sigil :: proc(g: ^Game, k: int) {
	g.activated += {k}
	g.rising = k
	set_phase(g, .Sigil)
	sa.clear(&g.path)
	if k in g.data.guard_seals {
		// a guard candelabrum catches the flame: its light shows the way
		for c, i in g.data.candelabra {
			if c.guard && int(c.seal) == k && i not_in g.candelabra_lit {
				g.candelabra_lit += {i}
				g.candelabrum_t[i] = 0
			}
		}
		learn(g, .Hint_Guard)
		audio.play(.Lamp_On, -6, audio.semitones(-5))
		audio.play(.Reveal, -10)
	} else {
		learn(g, .Hint_Sigil)
		audio.play(.Rumble, -2)
		shake(g, 2.6)
	}
	g.palace.risen = g.activated
	pl.rebuild_graph(&g.palace)
	g.rise_t[k] = 0
}

// Seconds since the seal raising rise entry i was lit (< 0 before).
rise_time :: proc(g: ^Game, i: int) -> f32 {
	return g.rise_t[g.data.rise[i].seal]
}

// When rise entry i reaches its place, seconds after its seal is lit (the
// stones of a seal come up one after the other, in file order).
rise_start :: proc(g: ^Game, i: int) -> f32 {
	return f32(g.rise_rank[i]) * RISE_DELAY
}

rise_landing :: proc(g: ^Game, i: int) -> f32 {
	return rise_start(g, i) + RISE_TIME * 0.55
}

// How long the stones of seal k take to rise.
rise_duration :: proc(g: ^Game, k: int) -> f32 {
	n := 0
	for e in g.data.rise {
		n += int(int(e.seal) == k)
	}
	return f32(max(n - 1, 0)) * RISE_DELAY + RISE_TIME
}

shake :: proc(g: ^Game, seconds: f32) {
	if g.reduce_motion {
		return
	}
	g.shake_t = 0
	g.shake_duration = seconds
}

start_ending :: proc(g: ^Game, p: Phase) {
	set_phase(g, p)
	sa.clear(&g.path)
	g.hud.visible = false
	hide(&g.hud.voice)
	sa.clear(&g.hud.queued)
	switch p {
	case .Ending_Oil:
		face_point(g, amore_world(g))
		audio.play(.Reveal, -2)
	case .Ending_Trust:
		face_point(g, amore_world(g))
		audio.play(.Good, -2)
	case .Ending_Exit:
		g.boxed = g.data.has_box && !g.ferried
		g.parting = !g.ferried && !g.boxed
		switch {
		case g.ferried: audio.play(.Oar, -10)
		case g.boxed: audio.play(.Wind, -16, 0.5)
		case: audio.play(.Rumble, -14, 0.8) // it breaks up
		}
	case .Play, .Sigil, .Mechanism, .Time, .Overturn, .Prologue, .Arrival, .Finished:
	}
}

// The veil between the levels closes this long after the boat is lost in the mist.
VEIL_IN_TIME :: 1.8

// Timeline of an arrival: the palace rises into place from the start outward
// (out of the veil after the boat), Psyche comes down onto the start.
ARRIVE_END :: 3.2
ARRIVE_DROP :: 3.0 // cells above the start she comes down from
VEIL_OUT :: 0.15
VEIL_OUT_TIME :: 1.3

// How bright the gold tracing the blocks is (0 .. 1): it comes up softly with
// them between the levels and has faded before the arrival is over.
TRACE_IN :: 0.3 // seconds into the arrival it begins to show...
TRACE_IN_TIME :: 0.7 // ...over this long
TRACE_FADE_TIME :: 1.4 // it fades over this long, ending just before ARRIVE_END
TRACE_FADE :: ARRIVE_END - TRACE_FADE_TIME - 0.1

trace :: proc(g: ^Game) -> f32 {
	if !g.arrive_traced || g.phase != .Arrival {
		return 0
	}
	t := g.arrive_t
	return fx.sine_in_out(fx.progress(t, TRACE_IN, TRACE_IN_TIME)) * (1 - fx.sine_in_out(fx.progress(t, TRACE_FADE, TRACE_FADE_TIME)))
}

// How far above the start Psyche still is while she arrives.
arrival_drop :: proc(g: ^Game) -> f32 {
	if g.arrive_t < 0 || g.phase != .Arrival {
		return 0
	}
	return ARRIVE_DROP * (1 - fx.cubic_out(fx.progress(g.arrive_t, 1.0, ARRIVE_END - 1.0)))
}

// How much a block has risen into place during the arrival (0 below, 1 there):
// the stones nearest the start come first. `d` is its distance from the start.
arrival_rise :: proc(g: ^Game, d: f32, jitter: f32) -> f32 {
	if g.arrive_t < 0 || g.phase != .Arrival {
		return 1
	}
	return fx.cubic_out(fx.progress(g.arrive_t, 0.45 + d * 0.08 + jitter * 0.15, 1.0))
}

// How long the exit lasts: the crossing in Charon's boat, the box opened, or
// the diorama breaking up.
exit_end :: proc(g: ^Game) -> f32 {
	switch {
	case g.ferried: return BOAT_END
	case g.boxed: return BOX_END
	}
	return PART_END
}

// Timeline of a diorama breaking up at an exit (but the boat's and the box's):
// the pieces sink away from the far side in, the stones under her last, and
// she goes down with them.
PART_END :: 2.8
PART_SPREAD :: 1.5 // the farthest piece goes this long before hers
PART_FALL :: 0.9 // each piece's fall

// How far a cell is from the heart of the assembly (the start on arrival,
// Psyche as the diorama breaks up): the stones near it come first, go last.
@(private)
spread :: proc(c: Cell) -> f32 {
	return math.sqrt(f32(c.x * c.x + c.y * c.y)) + f32(abs(c.z)) * 0.3
}

// How much a piece in cell `c` is in place: 1 there, 0 gone below. It rises
// on arrival (the start's stones first) and sinks as the diorama breaks up
// (the far ones first). `jitter` (0..1) staggers pieces of one distance.
assembly :: proc(g: ^Game, c: Cell, jitter: f32) -> f32 {
	switch {
	case g.phase == .Arrival:
		return arrival_rise(g, spread(c - g.data.start), jitter)
	case g.parting && (g.phase == .Ending_Exit || g.phase == .Finished):
		t := g.phase == .Finished ? PART_END : g.phase_t
		near := fx.clamp01(1 - spread(c - g.psyche.cell) / f32(g.data.size))
		return 1 - fx.quad_in(fx.progress(t, 0.2 + PART_SPREAD * near + jitter * 0.15, PART_FALL))
	}
	return 1
}

// How much of the floors' water is there, as the diorama rises or breaks up.
floors_shown :: proc(g: ^Game) -> f32 {
	switch {
	case g.phase == .Arrival:
		return fx.progress(g.arrive_t, 0.3, 1.2)
	case g.parting && (g.phase == .Ending_Exit || g.phase == .Finished):
		return 1 - fx.progress(g.phase == .Finished ? PART_END : g.phase_t, 0.6, 1.2)
	}
	return 1
}

// The veil between the levels over the world: closing as the boat is lost in
// the mist (or the box's sleep falls), opening as she arrives after it.
// 0: no veil, 1: closed.
veil :: proc(g: ^Game) -> f32 {
	switch {
	case g.parting && (g.phase == .Ending_Exit || g.phase == .Finished), g.phase == .Arrival && !g.arrive_veiled:
		return 0 // the diorama breaks up and the next rises, in the open
	case g.phase == .Ending_Exit:
		start: f32 = g.ferried ? BOAT_VEIL : BOX_VEIL
		return fx.sine_in_out(fx.progress(g.phase_t, start, g.boxed ? BOX_VEIL_TIME : VEIL_IN_TIME))
	case g.phase == .Finished && g.ending == .Exit:
		return 1
	case g.phase == .Arrival:
		return 1 - fx.sine_in_out(fx.progress(g.arrive_t, VEIL_OUT, VEIL_OUT_TIME))
	}
	return 0
}

// How far Psyche has gone down with her stone (cells, below zero) as the
// diorama breaks up at the exit.
exit_lift :: proc(g: ^Game) -> f32 {
	if !g.parting || g.phase != .Ending_Exit && g.phase != .Finished {
		return 0
	}
	return -9 * (1 - assembly(g, g.psyche.cell - {0, 0, 1}, 1))
}

// --- Charon's boat ---------------------------------------------------------------------

// Timeline of the crossing: she steps down into the boat, puts the coin in
// Charon's hand, and he poles the boat away into the mist.
BOAT_STEP :: 1.0 // stepping down from the landing into the boat
BOAT_COIN :: 1.2 // the coin passes from her to him...
BOAT_COIN_TIME :: 0.9 // ...this long
BOAT_PUSH :: 2.4 // he pushes off
BOAT_GONE :: 4.6 // cells the boat goes before the veil hides it
BOAT_VEIL :: 4.6 // the veil starts to close
BOAT_END :: 6.6
BOAT_STERN :: 0.55 // the stern, cells out from the landing's centre (render's Boat)...
BOAT_LENGTH :: 1.78 // ...and the boat's length to the prow
BOAT_SEAT :: 1.0 // where she stands in it, cells out from the landing's centre
BOAT_CHARON :: 1.85 // where Charon stands, at the far end (cells out)
BOAT_DRAFT :: 0.22 // its floor under the landing's surface

BOAT_MID :: BOAT_STERN + BOAT_LENGTH * 0.5 // the middle of the hull, cells out from the landing's centre

// A boat as it floats: the middle of its hull (its floor) and the way its
// prow points. Every boat is of the world above (render turns it with it).
Boat_Pose :: struct {
	mid: Vec3,
	yaw: f32,
}

// Charon in his boat: where he stands, which way he faces, how far his pole
// leans (0 upright .. 1 thrust), how much of him is seen (the mist takes him).
Charon :: struct {
	boat:  Boat_Pose,
	pos:   Vec3,
	face:  f32,
	pole:  f32,
	alpha: f32,
}

// A point of a boat, `out` cells along it from the landing's centre (as moored).
boat_at :: proc(b: Boat_Pose, out: f32) -> Vec3 {
	return b.mid + Vec3{math.cos(b.yaw), math.sin(b.yaw), 0} * (out - BOAT_MID)
}

// A boat moored on its side of a landing, rocking on the water, `away` cells further out.
@(private)
moored :: proc(g: ^Game, e: level.Boat, away: f32 = 0) -> Boat_Pose {
	d := iso.DIR_VEC[e.dir]
	out := Vec3{f32(d.x), f32(d.y), 0}
	land := Vec3{f32(e.cell.x) + 0.5, f32(e.cell.y) + 0.5, f32(e.cell.z)}
	bob := 0.015 * math.sin(g.time * 1.4)
	return {land + out * (BOAT_MID + away) + {0, 0, bob - BOAT_DRAFT}, math.atan2(out.y, out.x)}
}

// The way the boat at the exit lies: out from the landing, along its side `dir`.
boat_dir :: proc(g: ^Game) -> Vec3 {
	d := iso.DIR_VEC[g.data.boat.dir]
	return {f32(d.x), f32(d.y), 0}
}

// Cells the boat at the exit has gone out from its mooring.
@(private)
boat_away :: proc(g: ^Game) -> f32 {
	if !g.ferried || !(g.phase == .Ending_Exit || g.phase == .Finished) {
		return 0
	}
	t := g.phase == .Finished ? BOAT_END : g.phase_t
	return BOAT_GONE * fx.quad_in(fx.clamp01((t - BOAT_PUSH) / (BOAT_END - BOAT_PUSH)))
}

// A point of the boat at the exit (`out` cells from the landing's centre, along
// its length), as it floats now: rocking on the water, then going away.
boat_point :: proc(g: ^Game, out: f32) -> Vec3 {
	return boat_at(moored(g, g.data.boat, boat_away(g)), out)
}

// Charon at the exit: facing the landing while he waits, out over the water
// once he poles.
exit_charon :: proc(g: ^Game) -> Charon {
	b := moored(g, g.data.boat, boat_away(g))
	c := Charon{boat = b, pos = boat_at(b, BOAT_CHARON), face = b.yaw + math.PI, alpha = 1 - boat_fade(g)}
	if g.ferried && (g.phase == .Finished || g.phase == .Ending_Exit && g.phase_t > BOAT_PUSH - 0.4) {
		t := g.phase == .Finished ? BOAT_END : g.phase_t
		c.face = b.yaw
		c.pole = poling(t - BOAT_PUSH)
	}
	return c
}

// How far the pole leans, `t` seconds after he pushes off.
@(private)
poling :: proc(t: f32) -> f32 {
	return 0.5 + 0.5 * math.sin(t * 1.6 - math.PI * 0.5)
}

// How much the mist has taken the boat at the exit (0 there .. 1 gone).
boat_fade :: proc(g: ^Game) -> f32 {
	return fx.clamp01((boat_away(g) - BOAT_GONE * 0.45) / (BOAT_GONE * 0.55))
}

// The coin on its way from her hand to his (ok while it passes).
boat_coin :: proc(g: ^Game) -> (pos: Vec3, ok: bool) {
	if !g.ferried || g.phase != .Ending_Exit || g.phase_t < BOAT_COIN || g.phase_t >= BOAT_COIN + BOAT_COIN_TIME {
		return
	}
	u := fx.sine_in_out((g.phase_t - BOAT_COIN) / BOAT_COIN_TIME)
	her := g.psyche.pos + {0, 0, 0.52}
	him := exit_charon(g).pos
	return fx.lerp(her, him + {0, 0, 0.5}, u) + {0, 0, 0.12 * math.sin(math.PI * u)}, true
}

// Every Charon of the level as he is now: at the exit, then on each ferry.
charons :: proc(g: ^Game, allocator := context.temp_allocator) -> []Charon {
	list := make([dynamic]Charon, 0, len(g.data.ferries) + 1, allocator)
	if g.data.has_boat {
		append(&list, exit_charon(g))
	}
	for _, i in g.data.ferries {
		append(&list, ferry_charon(g, i))
	}
	return list[:]
}

// --- Charon's ferry ---------------------------------------------------------------------

// Timeline of a crossing (a step, `step_t` over FERRY_TIME): she steps down
// into the boat, he poles it round and across, she steps up onto the other
// landing.
FERRY_TIME :: 5.0
FERRY_IN :: 0.18 // she is in the boat; he pushes off...
FERRY_OUT :: 0.84 // ...it is moored at the other landing; she steps up
FERRY_SWING :: 0.3 // the part of the way the boat takes to come round, out and in

// The angle from a to b, the short way round.
@(private)
short_turn :: proc(a, b: f32) -> f32 {
	return math.mod(b - a + 3 * math.PI, 2 * math.PI) - math.PI
}

// Ferry i's boat at `u` of a crossing from where it is moored (u < 0: moored,
// still): the way it goes (`heading`) and whether it is under way.
@(private)
ferry_boat :: proc(g: ^Game, i: int, u: f32) -> (b: Boat_Pose, under_way: bool, heading: f32) {
	f := g.data.ferries[i]
	k := i in g.palace.boats ? 1 : 0
	b = moored(g, f.ends[k])
	heading = b.yaw
	if u < 0 {
		return
	}
	to := moored(g, f.ends[1 - k])
	way := to.mid - b.mid
	heading = math.atan2(way.y, way.x)
	s := fx.progress(u, FERRY_IN, FERRY_OUT - FERRY_IN)
	under_way = s > 0 && s < 1
	b.mid = fx.lerp(b.mid, to.mid, fx.sine_in_out(s))
	// round from its mooring to the way, then round to the other mooring
	b.yaw += short_turn(b.yaw, heading) * fx.sine_in_out(fx.clamp01(s / FERRY_SWING))
	b.yaw += short_turn(b.yaw, to.yaw) * fx.sine_in_out(fx.clamp01((s - 1 + FERRY_SWING) / FERRY_SWING))
	return
}

// How far along the crossing ferry i is (-1: not crossing).
@(private)
crossing_u :: proc(g: ^Game, i: int) -> f32 {
	psy := &g.psyche
	if !psy.walking || psy.step_kind != .Ferry || g.ferry_crossing != i {
		return -1
	}
	return psy.step_t / FERRY_TIME
}

// Charon on ferry i: facing the landing while he waits, the way on as he poles.
ferry_charon :: proc(g: ^Game, i: int) -> Charon {
	u := crossing_u(g, i)
	b, under_way, heading := ferry_boat(g, i, u)
	c := Charon{boat = b, pos = boat_at(b, BOAT_CHARON), face = b.yaw + math.PI, alpha = 1}
	if under_way {
		s := fx.progress(u, FERRY_IN, FERRY_OUT - FERRY_IN)
		c.face += short_turn(c.face, heading) * fx.sine_in_out(fx.clamp01(min(s, 1 - s) / 0.12))
		c.pole = poling((u - FERRY_IN) * FERRY_TIME)
	}
	return c
}

// Where she is along a crossing (u = 0..1): down from the landing into the
// boat, carried in it, up onto the other landing.
@(private)
crossing_point :: proc(g: ^Game, u: f32) -> Vec3 {
	psy := &g.psyche
	i := g.ferry_crossing
	if u < FERRY_IN {
		b, _, _ := ferry_boat(g, i, 0)
		w := fx.sine_in_out(u / FERRY_IN)
		return fx.lerp(pl.stand_world(&g.palace, psy.step_from), boat_at(b, BOAT_SEAT), w) + {0, 0, 0.12 * math.sin(math.PI * w)}
	}
	if u > FERRY_OUT {
		b, _, _ := ferry_boat(g, i, 1)
		w := fx.sine_in_out((u - FERRY_OUT) / (1 - FERRY_OUT))
		return fx.lerp(boat_at(b, BOAT_SEAT), pl.stand_world(&g.palace, psy.step_to), w) + {0, 0, 0.12 * math.sin(math.PI * w)}
	}
	b, _, _ := ferry_boat(g, i, u)
	return boat_at(b, BOAT_SEAT)
}

// The crossing's sounds, and she faces the way on.
@(private)
update_crossing :: proc(g: ^Game, dt: f32) {
	t := g.psyche.step_t
	if crossed(t, dt, FERRY_TIME * FERRY_IN * 0.8) || crossed(t, dt, FERRY_TIME * (FERRY_OUT + (1 - FERRY_OUT) * 0.8)) {
		audio.play(.Thud, -20, 1.4)
	}
	if crossed(t, dt, FERRY_TIME * FERRY_IN) {
		audio.play(.Oar, -12, 0.85)
	}
	u := t / FERRY_TIME
	if _, under_way, heading := ferry_boat(g, g.ferry_crossing, u); under_way {
		g.psyche.target_yaw = heading
	} else if u > FERRY_OUT {
		face_toward(g, pl.stand_world(&g.palace, g.psyche.step_to) - g.psyche.pos)
	}
}

@(private)
update_ferry :: proc(g: ^Game, dt: f32) {
	t := g.phase_t
	from := pl.stand_world(&g.palace, g.data.boat.cell)
	seat := boat_point(g, BOAT_SEAT)
	u := fx.sine_in_out(fx.clamp01(t / BOAT_STEP))
	g.psyche.pos = fx.lerp(from, seat, u) + {0, 0, 0.12 * math.sin(math.PI * u)}
	if t > BOAT_STEP {
		g.psyche.pos = seat
	}
	if crossed(t, dt, BOAT_STEP * 0.8) {
		audio.play(.Thud, -20, 1.4)
	}
	if crossed(t, dt, BOAT_COIN + BOAT_COIN_TIME) {
		audio.play(.Good, -12, audio.semitones(12))
		lightning(g) // the sky over the underworld cracks as he takes the coin
	}
	if crossed(t, dt, BOAT_PUSH) {
		audio.play(.Oar, -12, 0.85)
	}
}

// --- Proserpina's box ------------------------------------------------------------------

// Timeline of the box opened at the exit of the act's last level (`box`): she
// takes it out, lifts its lid, the Stygian sleep pours out and wraps her, she
// sinks down on the path, the dark closes over her.
BOX_SHOW :: 0.5 // the box in her hands
BOX_OPEN :: 1.4 // the lid lifts...
BOX_OPEN_TIME :: 0.9
BOX_FALL :: 2.9 // she sinks down...
BOX_FALL_TIME :: 1.6
BOX_VEIL :: 5.0 // the dark closes...
BOX_VEIL_TIME :: 2.2
BOX_END :: 7.6

// Time into the box's scene (ok: it is playing, or over).
@(private)
box_time :: proc(g: ^Game) -> (t: f32, ok: bool) {
	if !g.boxed || !(g.phase == .Ending_Exit || g.phase == .Finished && g.ending == .Exit) {
		return
	}
	return g.phase == .Finished ? BOX_END : g.phase_t, true
}

// The box in her hands: where it is, how far its lid is open (0..1), how much
// of it is seen (it slips from her hands as she falls).
box_pose :: proc(g: ^Game) -> (pos: Vec3, lid, alpha: f32) {
	t, ok := box_time(g)
	if !ok {
		return
	}
	fwd := Vec3{math.cos(g.psyche.yaw), math.sin(g.psyche.yaw), 0}
	slip := fx.progress(t, BOX_FALL + 0.3, 0.9)
	pos = g.psyche.pos + fwd * (0.17 + 0.1 * slip) + {0, 0, 0.3 * (1 - fx.quad_in(slip)) + 0.05}
	lid = fx.sine_in_out(fx.progress(t, BOX_OPEN, BOX_OPEN_TIME))
	alpha = fx.progress(t, 0, BOX_SHOW)
	return
}

// How much of the Stygian sleep pours out of the box now (0..1).
sleep_mist :: proc(g: ^Game) -> f32 {
	t, ok := box_time(g)
	if !ok {
		return 0
	}
	return fx.progress(t, BOX_OPEN + 0.3, 0.6) * (1 - fx.progress(t, BOX_FALL + BOX_FALL_TIME, 1.4))
}

// How far the sleep has laid her down (0 standing .. 1 lying on the path).
sleep_fall :: proc(g: ^Game) -> f32 {
	t, ok := box_time(g)
	if !ok {
		return 0
	}
	return fx.sine_in_out(fx.progress(t, BOX_FALL, BOX_FALL_TIME))
}

@(private)
update_box :: proc(g: ^Game, dt: f32) {
	t := g.phase_t
	if crossed(t, dt, BOX_OPEN) {
		audio.play(.Thunder, -16, 0.55) // a dark breath out of the box
	}
	if crossed(t, dt, BOX_FALL + BOX_FALL_TIME * 0.8) {
		audio.play(.Thud, -16, 0.6)
	}
}

// --- lightning ------------------------------------------------------------------------

THUNDER_AFTER :: 0.45 // the thunder rolls in this long after the flash

// A flash of lightning over the place, the thunder after it (render draws the
// bolt in the sky and the flash).
lightning :: proc(g: ^Game) {
	g.lightning_t = 0
}

// How bright the lightning is now (0 none .. 1): a flash, a second flicker.
lightning_flash :: proc(g: ^Game) -> f32 {
	t := g.lightning_t
	if t < 0 {
		return 0
	}
	f := math.exp(-t * 9)
	if t > 0.2 {
		f = max(f, 0.75 * math.exp(-(t - 0.2) * 7))
	}
	return f
}

// Timeline of "the drop of oil".
OIL_DROP_START :: 1.4
OIL_DROP_LAND :: 2.0
OIL_COLLAPSE :: 2.8
OIL_LAMP_OFF :: 4.3
OIL_END :: 6.3

@(private)
update_ending_oil :: proc(g: ^Game, dt: f32) {
	t := g.phase_t
	g.amore.reveal = fx.clamp01(t / 1.4)
	g.amore.breath = fx.lerp(f32(1), 2.2, g.amore.reveal)
	if crossed(t, dt, OIL_DROP_LAND) {
		audio.play(.Drip, -2, 0.7)
		shake(g, 0.5)
		g.amore.fly_t = 0
	}
	if crossed(t, dt, OIL_COLLAPSE) {
		g.collapse_t = 0
		g.collapse_keep = g.psyche.cell
	}
	if crossed(t, dt, OIL_LAMP_OFF) {
		set_lamp(g, false)
	}
	if t >= OIL_END {
		g.ending = .Oil
		set_phase(g, .Finished)
	}
}

// The burning drop, between the lamp and Cupid's shoulder (nil when not falling).
oil_drop :: proc(g: ^Game) -> (pos: Vec3, ok: bool) {
	if g.phase != .Ending_Oil || g.phase_t < OIL_DROP_START || g.phase_t >= OIL_DROP_LAND {
		return
	}
	u := fx.quad_in((g.phase_t - OIL_DROP_START) / (OIL_DROP_LAND - OIL_DROP_START))
	return fx.lerp(lamp_world(g), amore_world(g) + {0, 0, 0.55}, u), true
}

TRUST_END :: 4.0

@(private)
update_ending_trust :: proc(g: ^Game) {
	t := g.phase_t
	g.amore.embrace = fx.sine_in_out(fx.clamp01(t / 3.0))
	g.amore.breath = fx.lerp(f32(1), 2.6, fx.sine_in_out(fx.clamp01(t / 2.5)))
	if t >= TRUST_END {
		g.ending = .Trust
		set_phase(g, .Finished)
	}
}

// --- effects ----------------------------------------------------------------------

@(private)
update_effects :: proc(g: ^Game, dt: f32) {
	for &t, k in g.rise_t {
		if t < 0 {
			continue
		}
		before := t
		t = min(t + dt, 1e3)
		// each stone the seal raises lands with a thud: the bridge forms stone by stone
		for e, i in g.data.rise {
			at := rise_landing(g, i)
			if int(e.seal) == k && before < at && t >= at {
				audio.play(.Thud, -5, 0.85 + 0.05 * f32(g.rise_rank[i]))
				shake(g, 0.3)
			}
		}
	}
	if g.collapse_t >= 0 {
		g.collapse_t += dt
	}
	if g.lightning_t >= 0 {
		before := g.lightning_t
		g.lightning_t = min(g.lightning_t + dt, 1e3)
		if before < THUNDER_AFTER && g.lightning_t >= THUNDER_AFTER {
			audio.play(.Thunder, -4)
		}
	}
	// stones that fell, dissolved or appeared: their animations run on this clock
	for &t in g.flip_t {
		if t >= 0 {
			t = min(t + dt, 1e3)
		}
	}
	if g.amore.fly_t >= 0 {
		g.amore.fly_t += dt
	}
	for &t in g.eagle_back {
		if t >= 0 {
			t = min(t + dt, 1e3)
		}
	}
	for &t in g.fragment_t {
		if t >= 0 {
			t += dt
		}
	}
	for &t in g.candelabrum_t {
		if t >= 0 {
			t += dt
		}
	}
	if g.teach_after >= 0 {
		g.teach_after += dt
	}
	if g.shake_t < g.shake_duration {
		g.shake_t += dt
	}
	for &m in g.markers {
		if m.active {
			m.t += dt
			m.active = m.t < MARKER_TIME
		}
	}
	for &d in g.drops {
		if !d.active {
			continue
		}
		d.t += dt
		if d.t >= 0.35 {
			d.active = false
			audio.play(.Drip, -18, fx.rand_range(&g.rng, 0.9, 1.15))
			g.stains[g.stain_next] = {d.to}
			g.stain_next = (g.stain_next + 1) % MAX_STAINS
			g.stain_count = min(g.stain_count + 1, MAX_STAINS)
		}
	}
}

drop_position :: proc(d: Drop) -> Vec3 {
	return fx.lerp(d.from, d.to, fx.quad_in(fx.clamp01(d.t / 0.35)))
}

// --- voices and hints ---------------------------------------------------------------

// Does this level teach `key` (a hint cue in its file)?
teaches :: proc(g: ^Game, key: Key) -> bool {
	for h in g.data.hints {
		if h.key == key {
			return true
		}
	}
	return false
}

// Psyche has done what a tutorial hint teaches: it goes away.
@(private)
learn :: proc(g: ^Game, key: Key) {
	g.learned[key] = true
	if g.hud.hint.active && g.hud.hint.key == key {
		hide(&g.hud.hint)
	}
}

@(private)
show :: proc(f: ^Fade_Text, key: Key, fade_in, hold, fade_out: f32) {
	f^ = {key, true, 0, fade_in, hold, fade_out, -1}
}

@(private)
hide :: proc(f: ^Fade_Text) {
	if f.active && f.hide_t < 0 {
		f.hide_t = 0
	}
}

fade_alpha :: proc(f: Fade_Text) -> f32 {
	if !f.active {
		return 0
	}
	a := f.hold < 0 ? fx.clamp01(f.t / f.fade_in) : fx.envelope(f.t, f.fade_in, f.hold, f.fade_out)
	if f.hide_t >= 0 {
		a *= fx.clamp01(1 - f.hide_t / 0.8)
	}
	return a
}

// The badge of the keys (Esc, R) comes once the basic tutorial is done:
// in a level that teaches turning, after the first turn; elsewhere at once.
keys_badge_alpha :: proc(g: ^Game) -> f32 {
	return fx.clamp01(g.hud.badge_t / 1.2)
}

@(private)
keys_badge_due :: proc(g: ^Game) -> bool {
	if g.phase != .Play || !g.hud.visible {
		return false
	}
	for h in g.data.hints {
		if h.key == .Hint_Turn && !g.learned[.Hint_Turn] {
			return false
		}
	}
	return true
}

@(private)
update_hud :: proc(g: ^Game, dt: f32) {
	if g.hud.badge_t > 0 || keys_badge_due(g) {
		g.hud.badge_t += dt
	}
	for f in ([]^Fade_Text{&g.hud.title, &g.hud.voice, &g.hud.hint}) {
		if !f.active {
			continue
		}
		f.t += dt
		if f == &g.hud.hint && is_tutorial(f.key) && f.hold >= 0 && f.t > f.fade_in + f.hold {
			hide(f) // a tutorial card with a time: it leaves as when its action is done
		}
		if f.hide_t >= 0 {
			f.hide_t += dt
		}
		done := f.hold >= 0 && f.t > f.fade_in + f.hold + f.fade_out
		if done || (f.hide_t >= 0.8) {
			f.active = false
		}
	}
	if !g.hud.voice.active && sa.len(g.hud.queued) > 0 {
		speak(g, sa.pop_front(&g.hud.queued))
	}
}

// Where is Psyche? A light comes down on her, until she walks.
point_at_psyche :: proc(g: ^Game) {
	if g.active && g.phase == .Play {
		g.pointer_on = true
		g.pointer_title = false
	}
}

@(private)
update_pointer :: proc(g: ^Game, dt: f32) {
	if g.psyche.walking {
		g.pointer_on = false
	}
	shown := g.pointer_on && g.phase == .Play && g.hud.visible && !(g.pointer_title && g.hud.title.active)
	g.pointer = fx.move_toward(g.pointer, shown ? 1 : 0, dt * (shown ? 0.8 : 1.2))
}

// The level that teaches the turn teaches the fragments once its card is
// gone (turning shows them): a card of their own until one is taken.
@(private)
teach_fragments :: proc(g: ^Game) {
	if g.hinted[.Hint_Fragment] || !g.learned[.Hint_Turn] || g.hud.hint.active || g.phase != .Play {
		return
	}
	if teaches(g, .Hint_Turn) && card(g.fragments_taken + g.fragments_known) < len(g.data.fragments) {
		hint(g, .Hint_Fragment, 0)
	}
}

// Every state of a level (its text) from which the goal cannot be reached
// any more, in `allocator`; none for a level with more than DEAD_END_LIMIT
// states, it is not searched. Long in a big level: the app runs it on a
// worker thread, on its own copy of the level.
search_dead_ends :: proc(text: string, allocator := context.allocator) -> []pl.State {
	scratch: virtual.Arena
	if virtual.arena_init_growing(&scratch) != nil {
		return nil
	}
	defer virtual.arena_destroy(&scratch)
	alloc := virtual.arena_allocator(&scratch)
	data, err := level.parse(text, alloc)
	if err != nil {
		return nil
	}
	p: pl.Palace
	pl.init(&p, &data, alloc)
	dead := make([dynamic]pl.State, alloc)
	sol := pl.solve(&p, pl.goal_cell(&p), nil, alloc, DEAD_END_LIMIT, &dead)
	if sol.given_up || !sol.solved || len(dead) == 0 {
		return nil
	}
	return slice.clone(dead[:], allocator)
}

// The level's dead ends (`search_dead_ends`): Psyche is told when she stands in one.
know_dead_ends :: proc(g: ^Game, dead: []pl.State) {
	g.dead_ends = make(map[pl.State]struct {}, len(dead), level_allocator(g))
	for st in dead {
		g.dead_ends[st] = {}
	}
}

DEAD_END_LIMIT :: 100_000

// Standing still in a dead end: the way out is the brazier, or the level
// again; said each time she walks into one, gone when she is out.
@(private)
update_dead_end :: proc(g: ^Game) {
	if len(g.dead_ends) == 0 || g.phase != .Play || g.psyche.walking || g.turning {
		return
	}
	st := pl.state_of(&g.palace, g.psyche.cell, g.lamp_on)
	dead := st in g.dead_ends
	if dead == g.dead_end {
		return
	}
	g.dead_end = dead
	if dead {
		hint(g, has_rest(g) ? .Hint_Dead_End : .Hint_Dead_End_No_Rest, 0, true)
	} else if g.hud.hint.key == .Hint_Dead_End || g.hud.hint.key == .Hint_Dead_End_No_Rest {
		hide(&g.hud.hint)
	}
}

// Cupid's voice: each line is spoken once per level.
say :: proc(g: ^Game, key: Key) {
	if g.heard[key] {
		return
	}
	g.heard[key] = true
	if g.hud.voice.active {
		sa.push_back(&g.hud.queued, key)
		return
	}
	speak(g, key)
}

@(private)
speak :: proc(g: ^Game, key: Key) {
	length := f32(utf8.rune_count_in_string(i18n.tr(key)))
	show(&g.hud.voice, key, 0.9, 2.8 + length * 0.045, 1.6)
}

// When the start cell's hints come: after the intro line, if there is one.
start_cues_time :: proc(g: ^Game) -> f32 {
	if !g.data.has_intro {
		return WELCOME_DELAY
	}
	length := f32(utf8.rune_count_in_string(i18n.tr(g.data.intro)))
	return INTRO_AT + 0.9 + 2.8 + length * 0.045 + 0.6
}

// Tutorial hints stay on screen until Psyche does what they teach.
CANDELABRUM_REACH :: 1.5 // cells from Psyche: the lamp's flame lights a candelabrum

FIRE_HEARD :: 4.5 // cells: how far off a fire is still heard

// The fire nearest Psyche, as heard: 0 (none within FIRE_HEARD, or its world
// hangs under the other) .. 1 (beside her), and where it is across the
// screen (-1 left .. 1 right).
fire_near :: proc(g: ^Game) -> (near, pan: f32) {
	best := f32(FIRE_HEARD)
	for prop in g.data.props {
		if level.PROPS[prop.kind].flame != .Fire || prop.under != g.palace.upside {
			continue
		}
		c := level.frame_cell(&g.data, prop.cell, prop.under, g.palace.upside)
		d := Vec3{f32(c.x) + 0.5, f32(c.y) + 0.5, f32(c.z)} - g.psyche.pos
		dist := math.sqrt(d.x * d.x + d.y * d.y + 2 * d.z * d.z)
		if dist >= best {
			continue
		}
		best = dist
		// across the screen in the current view: x' - y' (a delta turns as a cell does)
		dx, dy := d.x, d.y
		for _ in 0 ..< g.palace.rot {
			dx, dy = -dy, dx
		}
		pan = clamp((dx - dy) / 5, -0.7, 0.7)
	}
	k := 1 - math.smoothstep(f32(0.8), FIRE_HEARD, best)
	return k * k, pan
}

// Where candelabrum i stands, in world space (its foot, in the corner of its surface).
candelabrum_base :: proc(g: ^Game, i: int) -> Vec3 {
	c := g.data.candelabra[i]
	k := [2]f32{0.8, 0.8}
	switch c.dir {
	case .PX:
	case .PY: k = {1 - k.y, k.x}
	case .MX: k = {1 - k.x, 1 - k.y}
	case .MY: k = {k.y, 1 - k.x}
	}
	return {f32(c.cell.x) + k.x, f32(c.cell.y) + k.y, f32(c.cell.z)}
}

// The lamp lit beside an unlit candelabrum lights it, for good.
@(private)
light_candelabra :: proc(g: ^Game) {
	for c, i in g.data.candelabra {
		if i in g.candelabra_lit || c.guard || !upright(g, c.under) {
			continue
		}
		d := candelabrum_base(g, i) - g.psyche.pos
		if d.x * d.x + d.y * d.y <= CANDELABRUM_REACH * CANDELABRUM_REACH && abs(d.z) < 1.2 {
			g.candelabra_lit += {i}
			g.candelabrum_t[i] = 0
			audio.play(.Lamp_On, -9, audio.semitones(3))
		}
	}
}

// How bright candelabrum i burns now (0 unlit, 1 burning; it catches over a moment).
candelabrum_flame :: proc(g: ^Game, i: int) -> f32 {
	if i not_in g.candelabra_lit {
		return 0
	}
	if t := g.candelabrum_t[i]; t >= 0 {
		return fx.cubic_out(fx.clamp01(t / 0.9))
	}
	return 1
}

is_tutorial :: proc(key: Key) -> bool {
	#partial switch key {
	case .Hint_Move, .Hint_Turn, .Hint_Lamp, .Hint_Illusion, .Hint_Sigil, .Hint_Oil, .Hint_Rest,
	     .Hint_Veiled, .Hint_Trap, .Hint_Handle, .Hint_Sundial, .Hint_Pomegranate, .Hint_Eagle, .Hint_Boat, .Hint_Guard, .Hint_Fragment:
		return true
	}
	return false
}

// A hint, shown once per level unless `again`; seconds = 0 keeps it on screen.
hint :: proc(g: ^Game, key: Key, seconds: f32, again := false) {
	if g.hinted[key] && !again {
		return
	}
	if is_tutorial(key) && g.learned[key] {
		return // already done: nothing to teach
	}
	g.hinted[key] = true
	show(&g.hud.hint, key, 0.5, seconds > 0 ? seconds : -1, 1.0)
}
