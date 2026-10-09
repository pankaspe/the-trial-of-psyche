// The cutscenes that open a level (the first of each act), in phase
// Prologue: `data.scene` says which.
//
// The Oracle (level I.1, `prologue x y h` in the level file): Apollo's oracle; the wedding procession, Psyche at its head and veiled
// mourners with torches behind her, climbs from the edge of the crag to the
// summit; they leave her there and go back down, putting the torches out
// one by one; alone, she feels the first breath of Zephyr. Then a key starts
// the level (a key during the scene skips to its end).
//
// Like every scene, it is a timeline: each figure, caption and light is a
// function of the time spent in the phase. The procession follows the walk
// path from the entry cell to the start, measured in cells.
//
// The Flight (level II.1, `flight x y h`): the night sky; Cupid's light
// crosses it with Psyche clinging to his leg; her strength fails and she
// drifts down into the forest like a leaf; he flies on over the cypress and
// is lost among the stars. The camera opens on the sky and comes down with her.
package game

import "core:math"
import sa "core:container/small_array"

import "../audio"
import "../fx"
import pl "../palace"

MOURNERS :: 5
PRO_WALK_START :: 2.5 // the procession comes up after the fade from black
PRO_PACE :: 1.1 // seconds per cell, going up
PRO_GAP :: 1.0 // cells between the figures of the procession
PRO_HOLD :: 2.5 // standing below the summit before turning back
PRO_BACK_PACE :: 0.8 // seconds per cell, going back
PRO_RISE :: 0.6 // cells walked below the edge: they come up and sink out of sight
PRO_TORCH_FIRST :: 0.6 // after turning back, the last torch goes out first...
PRO_TORCH_EVERY :: 0.7 // ...then one after another
PRO_PROMPT :: 3.0 // the prompt, after Psyche is left alone
PRO_SPIN :: -0.25 // the view starts a little turned and comes round to view 0
MAX_ROUTE :: 32

Prologue :: struct {
	route: sa.Small_Array(MAX_ROUTE, Cell), // entry .. start
}

// A figure of the procession at this moment.
Mourner :: struct {
	pos:    Vec3,
	yaw:    f32,
	alpha:  f32, // 0 while below the edge
	torch:  f32, // 1 lit .. 0 out
	out_t:  f32, // time since the torch went out (< 0 while lit): its smoke
}

@(private)
prologue_start :: proc(g: ^Game) {
	sa.clear(&g.prologue.route)
	sa.push_back(&g.prologue.route, g.data.prologue)
	path: pl.Path
	if g.data.scene == .Oracle && pl.find_path(&g.palace, g.data.prologue, g.data.start, false, &path) {
		for i in 0 ..< min(sa.len(path), MAX_ROUTE - 1) {
			sa.push_back(&g.prologue.route, sa.get(path, i))
		}
	}
	set_phase(g, .Prologue)
	g.angle = PRO_SPIN
}

// Cells walked from the entry to the start.
@(private)
route_length :: proc(g: ^Game) -> f32 {
	return f32(sa.len(g.prologue.route) - 1)
}

// --- the timeline -------------------------------------------------------------

prologue_arrive :: proc(g: ^Game) -> f32 {
	return PRO_WALK_START + (route_length(g) + PRO_RISE) * PRO_PACE
}

prologue_back :: proc(g: ^Game) -> f32 {
	return prologue_arrive(g) + PRO_HOLD
}

// Where mourner i stops on the way up (cells from the entry).
@(private)
mourner_stop :: proc(g: ^Game, i: int) -> f32 {
	return max(route_length(g) - f32(i + 1) * PRO_GAP, 0)
}

// Psyche is alone: the last mourner has sunk out of sight (Cupid is gone).
prologue_alone :: proc(g: ^Game) -> f32 {
	if g.data.scene == .Flight {
		return FL_GONE
	}
	return prologue_back(g) + (mourner_stop(g, 0) + PRO_RISE) * PRO_BACK_PACE + 0.6
}

// How long the scene rises out of black.
prologue_fade_in :: proc(g: ^Game) -> f32 {
	return g.data.scene == .Flight ? FL_FADE : PRO_WALK_START
}

// Is the procession of the Oracle on the scene?
procession :: proc(g: ^Game) -> bool {
	return g.phase == .Prologue && g.data.scene == .Oracle
}

prologue_ready :: proc(g: ^Game) -> bool {
	return g.phase == .Prologue && g.phase_t >= prologue_alone(g) + PRO_PROMPT
}

@(private)
torch_out_time :: proc(g: ^Game, i: int) -> f32 {
	return prologue_back(g) + PRO_TORCH_FIRST + f32(MOURNERS - 1 - i) * PRO_TORCH_EVERY
}

// Psyche's distance along the route (negative: still below the edge).
@(private)
psyche_distance :: proc(g: ^Game) -> f32 {
	return min((g.phase_t - PRO_WALK_START) / PRO_PACE - PRO_RISE, route_length(g))
}

// Point at distance s along the route; below the edge for s < 0.
@(private)
route_point :: proc(g: ^Game, s: f32) -> (pos: Vec3, dir: Vec3) {
	r := &g.prologue.route
	n := sa.len(r^)
	if n < 2 {
		return pl.stand_world(&g.palace, g.data.start), {1, 0, 0}
	}
	if s < 0 {
		a := pl.stand_world(&g.palace, sa.get(r^, 0))
		b := pl.node_world(&g.palace, sa.get(r^, 1))
		return a + {0, 0, s * 0.8}, b - a
	}
	i := min(int(s), n - 2)
	u := min(s - f32(i), 1)
	a := pl.node_world(&g.palace, sa.get(r^, i))
	b := pl.node_world(&g.palace, sa.get(r^, i + 1))
	return walk_point(g, sa.get(r^, i), sa.get(r^, i + 1), u), b - a
}

@(private)
yaw_of :: proc(d: Vec3) -> f32 {
	return math.atan2(d.y, d.x)
}

// A slow walk: a small bob while moving.
@(private)
bob :: proc(t: f32, moving: bool, phase: f32) -> f32 {
	return moving ? math.abs(math.sin(t * 6 + phase)) * 0.015 : 0
}

prologue_mourner :: proc(g: ^Game, i: int) -> (m: Mourner) {
	t := g.phase_t
	back := prologue_back(g)
	stop := mourner_stop(g, i)
	s: f32
	going_back := t >= back
	moving: bool
	if !going_back {
		up := psyche_distance(g) - f32(i + 1) * PRO_GAP
		s = min(up, stop)
		moving = up < stop && t > PRO_WALK_START
	} else {
		s = stop - (t - back) / PRO_BACK_PACE
		moving = true
	}
	pos, dir := route_point(g, s)
	if going_back {
		dir = -dir
	}
	m.pos = pos + {0, 0, bob(t, moving, f32(i) * 1.7)}
	m.yaw = yaw_of(dir)
	m.alpha = fx.clamp01(1 + s / PRO_RISE)
	out := torch_out_time(g, i)
	m.out_t = t - out
	m.torch = fx.clamp01(1 - m.out_t / 0.4)
	if m.out_t < 0 {
		m.out_t = -1
	}
	return
}

// Psyche is drawn only once she has come up over the edge (and not while
// the dark of a cave hides her).
psyche_alpha :: proc(g: ^Game) -> f32 {
	if g.phase != .Prologue {
		return passage_alpha(g)
	}
	if g.data.scene == .Flight {
		return 1
	}
	return fx.clamp01(1 + psyche_distance(g) / PRO_RISE)
}

// Where the torch burns, held up in the right hand.
torch_world :: proc(m: Mourner) -> Vec3 {
	side := Vec3{math.sin(m.yaw), -math.cos(m.yaw), 0}
	return m.pos + side * 0.14 + {0, 0, 0.62}
}

// The caption of the moment and its opacity.
prologue_caption :: proc(g: ^Game) -> (key: Key, alpha: f32) {
	t := g.phase_t
	back := prologue_back(g)
	alone := prologue_alone(g)
	Caption :: struct {
		key:      Key,
		from, to: f32,
	}
	captions := [?]Caption {
		{.Pro_Oracle, 1.2, 7.2},
		{.Pro_Procession, 7.6, back},
		{.Pro_Leave, back + 0.3, alone - 0.3},
		{.Pro_Alone, alone, 1e9},
	}
	flight := [?]Caption {
		{.Fl_Wake, 1.0, 5.4},
		{.Fl_Cling, 5.7, FL_LET_GO + 1.5},
		{.Fl_Fall, FL_LET_GO + 1.8, alone - 0.3},
		{.Fl_Alone, alone, 1e9},
	}
	list := g.data.scene == .Flight ? flight[:] : captions[:]
	for c in list {
		if t >= c.from && t < c.to {
			return c.key, fx.clamp01((t - c.from) / 0.7) * fx.clamp01((c.to - t) / 0.7)
		}
	}
	return
}

@(private)
update_prologue :: proc(g: ^Game, dt: f32) {
	if g.data.scene == .Flight {
		update_flight(g, dt)
		return
	}
	t := g.phase_t
	g.angle = PRO_SPIN * (1 - fx.sine_in_out(fx.clamp01(t / (prologue_alone(g) + 1))))
	s := psyche_distance(g)
	pos, dir := route_point(g, s)
	moving := s > -PRO_RISE && s < route_length(g)
	g.psyche.pos = pos + {0, 0, bob(t, moving, 0)}
	if moving {
		g.psyche.target_yaw = yaw_of(dir)
	} else if t > prologue_back(g) {
		// she looks back at the procession going away
		m := prologue_mourner(g, 0)
		face_point(g, m.pos)
	}
	for i in 0 ..< MOURNERS {
		if crossed(t, dt, torch_out_time(g, i)) {
			audio.play(.Lamp_Off, -14, 0.8)
		}
	}
	if crossed(t, dt, prologue_alone(g)) {
		audio.play(.Wind, -6)
	}
}

// A key in the prologue: skip to Psyche alone, or, once the prompt is up, play.
prologue_advance :: proc(g: ^Game) {
	if g.phase != .Prologue {
		return
	}
	if !prologue_ready(g) {
		alone := prologue_alone(g) - 0.01
		if g.phase_t < alone {
			g.phase_t = alone
		}
		return
	}
	set_phase(g, .Play)
	set_view(g, 0)
	g.psyche.pos = pl.stand_world(&g.palace, g.data.start)
	start_play(g, true) // the first time: the new mechanic is presented
	g.cine_out = 0
}

// --- the camera -------------------------------------------------------------------

CINE_BARS_OUT :: 1.2 // seconds for the bars to withdraw once the play begins

// How the prologue is filmed at this moment: the camera opens on the sky and
// tilts down to the crag while the scene fades in, closes in on Psyche as the
// procession climbs, and draws back to the usual framing once she is alone.
Cine :: struct {
	look_up: f32, // 1: the sky above the level .. 0: the level framed as in play
	zoom:    f32, // times the usual framing
	focus:   f32, // 0 the level's centre .. 1 Psyche
	bars:    f32, // the letterbox, 0 .. 1
}

cine :: proc(g: ^Game) -> (c: Cine) {
	c.zoom = 1
	if g.phase != .Prologue {
		if g.cine_out >= 0 {
			c.bars = 1 - fx.sine_in_out(fx.clamp01(g.cine_out / CINE_BARS_OUT))
		}
		return
	}
	t := g.phase_t
	if g.data.scene == .Flight {
		// close on her across the sky and down into the forest, then back to
		// the usual framing, so he is seen over the cypress before he goes
		c.bars = 1
		closer := fx.sine_in_out(fx.progress(t, 0.2, 2.2)) * (1 - fx.sine_in_out(fx.progress(t, FL_LAND + 0.3, 2.5)))
		c.zoom = 1 + 0.5 * closer
		c.focus = 0.85 * closer
		// the camera lifts a little to the sky over the cypress while he goes
		c.look_up = 0.45 * fx.sine_in_out(fx.progress(t, FL_LAND + 0.3, 2.5)) * (1 - fx.sine_in_out(fx.progress(t, FL_GONE + 0.5, 2)))
		return
	}
	back := prologue_back(g)
	alone := prologue_alone(g)
	c.bars = 1
	c.look_up = 1 - fx.sine_in_out(fx.clamp01(t / (PRO_WALK_START + 4.5)))
	closer := fx.sine_in_out(fx.progress(t, PRO_WALK_START + 3, 4)) * (1 - fx.sine_in_out(fx.progress(t, back, alone + 0.5 - back)))
	c.zoom = 1 + 0.32 * closer
	c.focus = 0.55 * closer
	return
}

// --- the Flight ---------------------------------------------------------------------

FL_FADE :: 2.0 // out of black: the night sky
FL_CARRY :: 1.0 // Cupid's light comes into the sky, Psyche with him...
FL_LET_GO :: 8.0 // ...until her strength fails
FL_LAND :: 12.5 // she has drifted down onto the start
FL_GONE :: 17.0 // he is lost among the stars

// Where the flight goes: in from the far side of the sky, over the start,
// then on over the cypress and up.
@(private)
flight_points :: proc(g: ^Game) -> (a, b, c, d: Vec3) {
	s := pl.stand_world(&g.palace, g.data.start)
	mid := f32(g.data.size) * 0.5
	a = {mid + 5, mid - 4, s.z + 9}
	b = s + {0.3, -0.3, 6.5}
	p := g.data.prologue
	c = {f32(p.x) + 0.5, f32(p.y) + 0.5, f32(p.z) + 2.2} // just over the cypress
	d = c + {2.5, -2.5, 9}
	return
}

// Cupid in the flight: where he is and how much he is seen (0: gone).
flight_cupid :: proc(g: ^Game) -> (pos: Vec3, alpha: f32) {
	if g.phase != .Prologue || g.data.scene != .Flight {
		return
	}
	t := g.phase_t
	a, b, c, d := flight_points(g)
	switch {
	case t < FL_LET_GO:
		u := fx.sine_in_out(fx.clamp01((t - FL_CARRY) / (FL_LET_GO - FL_CARRY)))
		pos = fx.lerp(a, b, u) + {0, 0, 0.25 * math.sin(t * 1.3)}
	case t < FL_GONE - 2.5:
		u := fx.sine_in_out(fx.clamp01((t - FL_LET_GO) / (FL_GONE - 2.5 - FL_LET_GO)))
		pos = fx.lerp(b, c, u) + {0, 0, 0.25 * math.sin(t * 1.3)}
	case:
		// a moment over the cypress, then up and away
		u := fx.clamp01((t - (FL_GONE - 2.5)) / 3.5)
		pos = fx.lerp(c, d, fx.quad_in(u)) + {0, 0, 0.25 * math.sin(t * 1.3)}
	}
	alpha = fx.clamp01((t - FL_CARRY + 0.6) / 1.2) * (1 - fx.progress(t, FL_GONE - 1, 1.6))
	return
}

@(private)
update_flight :: proc(g: ^Game, dt: f32) {
	t := g.phase_t
	g.angle = PRO_SPIN * (1 - fx.sine_in_out(fx.clamp01(t / (FL_GONE + 1))))
	s := pl.stand_world(&g.palace, g.data.start)
	cupid, _ := flight_cupid(g)
	switch {
	case t < FL_LET_GO:
		// hanging from his leg
		g.psyche.pos = cupid - {0, 0, 0.75}
	case t < FL_LAND:
		// a leaf falling: slow, swaying
		_, b, _, _ := flight_points(g)
		from := b + {0, 0, 0.25 * math.sin(f32(FL_LET_GO) * 1.3) - 0.75}
		u := fx.sine_in_out(fx.clamp01((t - FL_LET_GO) / (FL_LAND - FL_LET_GO)))
		sway := math.sin(u * math.PI * 3) * 0.35 * (1 - u)
		g.psyche.pos = fx.lerp(from, s, u) + {sway, -sway, 0}
	case:
		g.psyche.pos = s
		face_point(g, cupid)
	}
	if crossed(t, dt, FL_CARRY) {
		audio.play(.Wind, -10, 0.9)
	}
	if crossed(t, dt, FL_LET_GO) {
		audio.play(.Wind, -12, 0.75)
	}
	if crossed(t, dt, FL_LAND) {
		audio.play(.Thud, -18, 1.3)
	}
	if crossed(t, dt, FL_GONE - 1) {
		audio.play(.Seam, -18, audio.semitones(5))
	}
}
