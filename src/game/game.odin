// One playable level and its rules.
//   Dark (default): the illusion edges of the current view are walkable.
//   Lamp lit: only real edges, true depth shows, hidden seals appear, oil burns.
//   Q / E turn the diorama: every view has its own illusions.
// A seal lit by the lamp while Psyche stands on it raises hidden blocks.
// Lighting the lamp in Cupid's chamber ends the level (the myth's drop of oil);
// reaching him in the dark ends it with trust.
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
WELCOME_DELAY :: 1.6
MAX_STAINS :: 96
MAX_DROPS :: 8
MAX_MARKERS :: 4
MARKER_TIME :: 0.6

Phase :: enum u8 {
	Play,
	Sigil, // the seal is lit: blocks rise, input waits
	Ending_Bad,
	Ending_Good,
	Finished,
}

Ending :: enum u8 {
	None,
	Good,
	Bad,
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
	title:   Fade_Text,
	voice:   Fade_Text,
	hint:    Fade_Text,
}

Psyche :: struct {
	cell:          Cell,
	walking:       bool,
	step_from:     Cell,
	step_to:       Cell,
	step_t:        f32,
	step_illusion: bool,
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
	activated:      bool, // the seal has been lit

	angle:          f32, // continuous view angle in quarter turns (unbounded)
	turning:        bool,
	turn_from:      f32,
	turn_step:      int,
	turn_t:         f32,
	pending_turn:   int,
	reach_before:   []bool, // reachable nodes when a turn started

	path:           pl.Path,
	psyche:         Psyche,
	amore:          Amore,

	heard:          [Key]bool,
	hinted:         [Key]bool,
	begin_t:        f32, // time since begin(), < 0 before
	rise_t:         f32, // < 0 until the seal is lit
	rise_count:     int,
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

Load_Error :: level.Parse_Error

// (Re)load a level: frees everything from the previous one.
load :: proc(g: ^Game, index: int) -> (err: Maybe(Load_Error)) {
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
	alloc := virtual.arena_allocator(&g.arena)

	data, perr := level.parse(content.LEVELS[index].source, alloc)
	if perr != nil {
		return perr
	}
	g.data = data
	pl.init(&g.palace, &g.data, alloc)
	g.reach_before = make([]bool, len(g.palace.solid), alloc) // one per grid cell: enough for any node count
	g.rise_count = len(g.data.rise)

	g.oil = OIL_MAX
	g.flicker = 1
	g.begin_t = -1
	g.rise_t = -1
	g.collapse_t = -1
	g.amore = {fly_t = -1, breath = 1}
	g.psyche.cell = g.data.start
	g.psyche.pos = pl.node_world(&g.palace, g.data.start)
	g.psyche.yaw = math.PI * 0.75 // facing the camera
	g.psyche.target_yaw = g.psyche.yaw
	g.rng = fx.rng_init(u32(index) * 7919 + 17)
	g.loaded = true
	return nil
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

// Leave attract mode and start playing.
begin :: proc(g: ^Game) {
	g.active = true
	g.hud.visible = true
	show(&g.hud.title, title_key(g), 1.5, 3.5, 2.0)
	audio.start_music()
	g.begin_t = 0
}

rot :: proc(g: ^Game) -> int {
	return g.palace.rot
}

is_over :: proc(g: ^Game) -> bool {
	return g.phase == .Ending_Bad || g.phase == .Ending_Good || g.phase == .Finished
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
		g.oil = max(g.oil - dt, 0)
		g.drip += dt
		if g.drip >= DRIP_EVERY {
			g.drip = 0
			drop_oil(g)
		}
		if g.oil <= 0 {
			set_lamp(g, false)
			if !g.activated {
				hint(g, .Hint_No_Oil, 0, true)
			}
		}
	}

	if g.begin_t >= 0 {
		before := g.begin_t
		g.begin_t += dt
		if before < WELCOME_DELAY && g.begin_t >= WELCOME_DELAY && g.phase == .Play {
			say(g, .V_Welcome)
			hint(g, .Hint_Move, 6)
		}
	}

	update_turn(g, dt)
	update_walk(g, dt)
	update_effects(g, dt)
	update_hud(g, dt)
	audio.set_light(g.light)

	switch g.phase {
	case .Play:
		if !g.active {
			break
		}
		psy := g.psyche.cell
		if g.lamp_on && g.light > 0.6 && !g.activated && !g.psyche.walking && g.data.has_sigil && psy == g.data.sigil {
			activate_sigil(g)
		} else if g.lamp_on && g.light > 0.3 && in_chamber(g, psy) {
			start_ending(g, .Ending_Bad)
		}
	case .Sigil:
		if g.phase_t >= rise_duration(g) {
			set_phase(g, .Play)
			say(g, .V_Sigil)
		}
	case .Ending_Bad:
		update_ending_bad(g, dt)
	case .Ending_Good:
		update_ending_good(g)
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
	audio.play(.Turn, -4)
	pl.reachable(&g.palace, g.psyche.cell, !g.lamp_on, g.reach_before[:len(g.palace.nodes)])
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
	pl.reachable(&g.palace, g.psyche.cell, !g.lamp_on, after)
	for ok, i in after {
		if ok && !g.reach_before[i] {
			// a new way has opened in this view
			audio.play(.Seam, -6, 0.9)
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
	if !g.active || is_over(g) {
		return
	}
	if g.lamp_on {
		set_lamp(g, false)
	} else if g.oil > 0.05 {
		g.oil = max(g.oil - LIGHT_COST, 0)
		set_lamp(g, true)
		say(g, .V_First_Light)
	} else {
		audio.play(.Blocked, -6)
		hint(g, .Hint_No_Oil, 0, true)
	}
}

@(private)
set_lamp :: proc(g: ^Game, on: bool) {
	if g.lamp_on == on {
		return
	}
	g.lamp_on = on
	g.drip = DRIP_EVERY * 0.5
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
	// while a step is under way, plan from where that step will end
	from := g.psyche.walking ? g.psyche.step_to : g.psyche.cell
	path: pl.Path
	found := pl.find_path(&g.palace, from, target, !g.lamp_on, &path)
	if !found && target != from {
		add_marker(g, target, false)
		audio.play(.Blocked, -10)
		other: pl.Path
		if g.lamp_on && pl.find_path(&g.palace, from, target, true, &other) {
			hint(g, .Hint_Seam, 3, true)
		} else if !g.lamp_on && pl.find_path(&g.palace, from, target, false, &other) && crosses_hidden_stairs(g, from, other) {
			hint(g, .Hint_Hidden_Stairs, 4, true)
		}
		return
	}
	add_marker(g, target, true)
	audio.play(.Tap, -12)
	g.pending_turn = 0
	g.path = path
	if !g.psyche.walking {
		next_step(g)
	}
}

// Start walking to `target` as a click on it would (tests, scripted scenes).
walk_to :: proc(g: ^Game, target: Cell) -> bool {
	from := g.psyche.walking ? g.psyche.step_to : g.psyche.cell
	if !pl.find_path(&g.palace, from, target, !g.lamp_on, &g.path) {
		return false
	}
	if !g.psyche.walking {
		next_step(g)
	}
	return true
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
	if illusion && g.lamp_on {
		sa.clear(&g.path)
		audio.play(.Blocked, -8)
		hint(g, .Hint_Seam, 3, true)
		stop_walking(g)
		return
	}
	if !g.lamp_on && !pl.step_allowed(&g.palace, pl.node_index(&g.palace, psy.cell), pl.node_index(&g.palace, next), true) {
		// the lamp went out on the way: stairs hidden in this view are gone
		sa.clear(&g.path)
		audio.play(.Blocked, -8)
		hint(g, .Hint_Hidden_Stairs, 4, true)
		stop_walking(g)
		return
	}
	sa.pop_front(&g.path)
	psy.step_from = psy.cell
	psy.step_to = next
	psy.step_t = 0
	psy.step_illusion = illusion
	psy.walking = true
	if illusion {
		audio.play(.Seam, -8)
	}
	a, _ := step_points(g, 0)
	b, _ := step_points(g, 0.49)
	face_toward(g, b - a)
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
	if !psy.step_illusion {
		return fx.lerp(a, b, u), u >= 0.5
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

@(private)
update_walk :: proc(g: ^Game, dt: f32) {
	psy := &g.psyche
	// turn smoothly toward the target yaw, the short way round
	diff := math.mod(psy.target_yaw - psy.yaw + 3 * math.PI, 2 * math.PI) - math.PI
	psy.yaw += diff * min(dt * 14, 1)

	if !psy.walking {
		psy.pos = pl.node_world(&g.palace, psy.cell)
		return
	}
	psy.walk_anim += dt
	psy.step_t += dt
	u := min(psy.step_t / STEP_TIME, 1)
	psy.pos, _ = step_points(g, u)
	if u < 1 {
		return
	}
	psy.cell = psy.step_to
	psy.pos = pl.node_world(&g.palace, psy.cell)
	audio.play(.Step, -12, fx.rand_range(&g.rng, 0.85, 1.15))
	arrive(g, psy.cell)
	next_step(g)
}

@(private)
arrive :: proc(g: ^Game, n: Cell) {
	for v in g.data.voices {
		if v.cell == n {
			say(g, v.key)
		}
	}
	if g.heard[.V_Turn] {
		hint(g, .Hint_Turn, 7)
	}
	if g.heard[.V_Lamp] {
		hint(g, .Hint_Lamp, 7)
	}
	if !g.lamp_on && g.data.has_amore && adjacent_to_amore(g, n) && g.phase == .Play {
		start_ending(g, .Ending_Good)
	}
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

@(private)
activate_sigil :: proc(g: ^Game) {
	g.activated = true
	set_phase(g, .Sigil)
	sa.clear(&g.path)
	audio.play(.Rumble, -2)
	shake(g, 2.6)
	g.palace.risen = true
	pl.rebuild_graph(&g.palace)
	g.rise_t = 0
}

rise_duration :: proc(g: ^Game) -> f32 {
	return f32(max(g.rise_count - 1, 0)) * RISE_DELAY + RISE_TIME
}

shake :: proc(g: ^Game, seconds: f32) {
	g.shake_t = 0
	g.shake_duration = seconds
}

@(private)
start_ending :: proc(g: ^Game, p: Phase) {
	set_phase(g, p)
	sa.clear(&g.path)
	g.hud.visible = false
	hide(&g.hud.voice)
	face_point(g, amore_world(g))
	if p == .Ending_Bad {
		audio.play(.Reveal, -2)
	} else {
		audio.play(.Good, -2)
	}
}

// Timeline of "the drop of oil".
BAD_DROP_START :: 1.4
BAD_DROP_LAND :: 2.0
BAD_COLLAPSE :: 2.8
BAD_LAMP_OFF :: 4.3
BAD_END :: 6.3

@(private)
update_ending_bad :: proc(g: ^Game, dt: f32) {
	t := g.phase_t
	g.amore.reveal = fx.clamp01(t / 1.4)
	g.amore.breath = fx.lerp(f32(1), 2.2, g.amore.reveal)
	if crossed(t, dt, BAD_DROP_LAND) {
		audio.play(.Drop, 0, 0.7)
		shake(g, 0.5)
		g.amore.fly_t = 0
	}
	if crossed(t, dt, BAD_COLLAPSE) {
		g.collapse_t = 0
		g.collapse_keep = g.psyche.cell
	}
	if crossed(t, dt, BAD_LAMP_OFF) {
		set_lamp(g, false)
	}
	if t >= BAD_END {
		g.ending = .Bad
		set_phase(g, .Finished)
	}
}

// The burning drop, between the lamp and Cupid's shoulder (nil when not falling).
bad_drop :: proc(g: ^Game) -> (pos: Vec3, ok: bool) {
	if g.phase != .Ending_Bad || g.phase_t < BAD_DROP_START || g.phase_t >= BAD_DROP_LAND {
		return
	}
	u := fx.quad_in((g.phase_t - BAD_DROP_START) / (BAD_DROP_LAND - BAD_DROP_START))
	return fx.lerp(lamp_world(g), amore_world(g) + {0, 0, 0.55}, u), true
}

GOOD_END :: 4.0

@(private)
update_ending_good :: proc(g: ^Game) {
	t := g.phase_t
	g.amore.embrace = fx.sine_in_out(fx.clamp01(t / 3.0))
	g.amore.breath = fx.lerp(f32(1), 2.6, fx.sine_in_out(fx.clamp01(t / 2.5)))
	if t >= GOOD_END {
		g.ending = .Good
		set_phase(g, .Finished)
	}
}

// --- effects ----------------------------------------------------------------------

@(private)
update_effects :: proc(g: ^Game, dt: f32) {
	if g.rise_t >= 0 {
		g.rise_t += dt
	}
	if g.collapse_t >= 0 {
		g.collapse_t += dt
	}
	if g.amore.fly_t >= 0 {
		g.amore.fly_t += dt
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
			audio.play(.Drop, -16, fx.rand_range(&g.rng, 0.9, 1.15))
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

@(private)
update_hud :: proc(g: ^Game, dt: f32) {
	for f in ([]^Fade_Text{&g.hud.title, &g.hud.voice, &g.hud.hint}) {
		if !f.active {
			continue
		}
		f.t += dt
		if f.hide_t >= 0 {
			f.hide_t += dt
		}
		done := f.hold >= 0 && f.t > f.fade_in + f.hold + f.fade_out
		if done || (f.hide_t >= 0.8) {
			f.active = false
		}
	}
}

// Cupid's voice: each line is spoken once per level.
say :: proc(g: ^Game, key: Key) {
	if g.heard[key] {
		return
	}
	g.heard[key] = true
	length := f32(utf8.rune_count_in_string(i18n.tr(key)))
	show(&g.hud.voice, key, 0.9, 2.8 + length * 0.045, 1.6)
	audio.play(.Voice, -6)
}

// A hint, shown once per level unless `again`; seconds = 0 keeps it on screen.
hint :: proc(g: ^Game, key: Key, seconds: f32, again := false) {
	if g.hinted[key] && !again {
		return
	}
	g.hinted[key] = true
	show(&g.hud.hint, key, 0.5, seconds > 0 ? seconds : -1, 1.0)
}
