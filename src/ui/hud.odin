// In-game overlay, squared, in the lamplight:
//   top left   Esc and the pause; achievements also land there;
//   left       the skills, one slot per number key (1 the lamp, 2 the
//              handle...; those still to learn show locked); a skill's name
//              slides out on hover (or always, by the settings);
//   bottom     right: the diorama's own buttons (Q, E turn it; R the brazier,
//              held: the level again, a ring filling);
//   over Psyche the action of the place (Space), when there is one.
// Titles, Cupid's voice, hints and tutorials as before. Everything but the
// titles follows the HUD size of the accessibility settings.
package ui

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

import "../content"
import "../fx"
import "../game"
import "../i18n"

// What the app tells the HUD each frame.
Hud_Input :: struct {
	psyche_screen: Vec2, // above Psyche's head, on screen: the action of the place floats there
	hold:          f32, // how far R has been held toward a restart, 0..1
	twice:         bool, // the restart is R pressed twice (accessibility)
}

Hud_Action :: struct {
	lamp:      bool,
	handle:    bool,
	place:     bool, // the action of the place (into the cave)
	turn:      int,
	rest_down: bool, // the brazier's button is held down with the mouse
}

draw_hud :: proc(u: ^Ui, g: ^game.Game, input: Hud_Input = {}) -> (act: Hud_Action) {
	s := u.scale
	k := hud_k(u)
	w, h := u.width, u.height
	hud := &g.hud
	if g.phase == .Prologue {
		draw_prologue(u, g)
		return
	}
	cinema_bars(u, game.cine(g).bars)

	// title and voice stay visible even when the rest of the HUD is hidden
	if a := game.fade_alpha(hud.title); a > 0 {
		// the level's name, and its act between two rules
		text(u, i18n.tr(content.LEVELS[g.level_index].title), {w * 0.5, 28 * s}, {size = 62, color = TITLE, face = .Display, glow = true, shadow = true}, .Center, a)
		rule_label(u, caps(i18n.tr(content.ACT_LABEL[content.LEVELS[g.level_index].act])), {w * 0.5, 100 * s}, 20, 100 * s, a)
	}
	if a := game.fade_alpha(hud.voice); a > 0 {
		st := Style{size = 38, color = TITLE, face = .Italic, shadow = true}
		msg := i18n.tr(hud.voice.key)
		bh := block_height(u, msg, st, 1300 * s)
		// centred in the band above the hints
		top := h - 250 * s - bh * 0.5
		paragraph(u, msg, {w * 0.5, top}, st, 1300 * s, a)
	}
	if !hud.visible {
		return
	}
	if a := game.keys_badge_alpha(g); a > 0 && !u.toast_visible {
		keys_badge(u, a)
	}
	teaching := hud.hint.active && game.is_tutorial(hud.hint.key) && hud.hint.hide_t < 0
	if hud.hint.active && game.is_tutorial(hud.hint.key) {
		draw_tutorial(u, g)
	} else if a := game.fade_alpha(hud.hint); a > 0 {
		draw_hint(u, g, i18n.tr(hud.hint.key), false, a)
	}

	draw_skills(u, g, &act)
	draw_diorama(u, g, input, &act)
	draw_place(u, g, input, &act)

	// the control a tutorial is about breathes until it is used
	if teaching {
		#partial switch hud.hint.key {
		case .Hint_Turn:
			q := diorama_button(u, 0)
			e := diorama_button(u, 1)
			point_at(u, g, {q.x, q.y, e.x + e.width - q.x, q.height})
		case .Hint_Lamp, .Hint_Oil:
			point_at(u, g, skill_slot(u, 0))
		case .Hint_Handle:
			point_at(u, g, skill_slot(u, 1))
		}
	}
	_ = k
	return
}

// The HUD's own scale: the UI's, times the size chosen in the settings.
@(private)
hud_k :: proc(u: ^Ui) -> f32 {
	return u.scale * u.hud_size
}

// Move `v` toward `target` at `rate` per second, or at once if motion is reduced.
@(private)
approach :: proc(u: ^Ui, v: ^f32, target, rate: f32) {
	if u.reduce_motion {
		v^ = target
		return
	}
	v^ = fx.move_toward(v^, target, u.dt * rate)
}

// --- the skills ----------------------------------------------------------------------

SLOT :: 84 // a skill's slot, 1080p px
SLOT_GAP :: 14

@(private)
Slot_Look :: enum u8 {
	Locked, // still to learn
	Off, // known, not usable here and now (the reason is its status)
	Ready,
	Active, // the lamp burns, the handle turns
}

@(private)
Slot :: struct {
	look:    Slot_Look,
	name:    i18n.Key,
	status:  string,
	warn:    bool, // the oil is running out
	oil:     f32, // the lamp: 0..1 of the oil, -1 for other skills
	action:  bool, // clicking the slot uses the skill
}

// Is there a skill to show in this level? (None in the first levels.)
@(private)
skills_shown :: proc(g: ^game.Game) -> bool {
	return game.has_skill(g, .Lamp) || game.has_skill(g, .Handle)
}

// Where slot i is on screen: down the left edge, around the middle.
@(private)
skill_slot :: proc(u: ^Ui, i: int) -> rl.Rectangle {
	k := hud_k(u)
	total := f32(content.MAX_SKILLS) * SLOT + f32(content.MAX_SKILLS - 1) * SLOT_GAP
	top := u.height * 0.5 - total * k * 0.5
	return {40 * k, top + f32(i) * (SLOT + SLOT_GAP) * k, SLOT * k, SLOT * k}
}

@(private)
slot_of :: proc(g: ^game.Game, i: int) -> (sl: Slot) {
	sl.oil = -1
	switch i {
	case 0:
		sl.name = .Lamp_Button
		if !game.has_skill(g, .Lamp) {
			if content.skill_known(g.level_index, .Lamp) {
				// known, but left behind here (by day there is nothing to light)
				sl.look = .Off
				sl.status = i18n.tr(.Skill_Lamp_Absent)
			}
			return
		}
		sl.oil = clamp(g.oil / g.oil_max, 0, 1)
		secs := int(math.ceil(g.oil))
		switch {
		case g.lamp_on:
			sl.look = .Active
			sl.status = fmt.tprintf(i18n.tr(.Skill_Lit), secs)
			sl.warn = !g.endless_oil && sl.oil < 0.25
			sl.action = true
		case g.oil <= 0.05:
			sl.look = .Off
			sl.status = i18n.tr(.Skill_No_Oil)
		case:
			sl.look = .Ready
			sl.status = g.oil < g.oil_max - 0.05 ? fmt.tprintf(i18n.tr(.Skill_Oil), secs) : i18n.tr(.Skill_Ready)
			sl.action = true
		}
	case 1:
		sl.name = .Handle_Button
		if !game.has_skill(g, .Handle) {
			return
		}
		switch {
		case g.phase == .Mechanism:
			sl.look = .Active
			sl.status = i18n.tr(.Skill_Handle_Turning)
		case game.on_handle(g):
			sl.look = .Ready
			sl.status = i18n.tr(.Skill_Handle_Here)
			sl.action = true
		case:
			sl.look = .Off
			sl.status = i18n.tr(.Skill_Handle_Away)
		}
	}
	return
}

// The sidebar of the skills: a square slot per number key, its key in the
// corner, its picture inside (the lamp's oil as a row of notches), its name
// and state sliding out beside it.
@(private)
draw_skills :: proc(u: ^Ui, g: ^game.Game, act: ^Hud_Action) {
	if !skills_shown(g) {
		return
	}
	k := hud_k(u)
	first := skill_slot(u, 0)
	text(u, caps(i18n.tr(.Skills_Label)), {first.x, first.y - 36 * k}, {size = 15 * k / u.scale, color = GOLD, face = .Semi, track = 0.22, shadow = true}, .Left)
	for i in 0 ..< content.MAX_SKILLS {
		r := skill_slot(u, i)
		sl := slot_of(g, i)
		add_hot(u, r)
		hover := rl.CheckCollisionPointRec(u.mouse, r)
		if hover && u.pressed && sl.action {
			switch i {
			case 0: act.lamp = true
			case 1: act.handle = true
			}
		}

		// what the slot says changed: its name slides out for a moment
		state := int(sl.look) * 16 + int(sl.warn)
		if u.skill_state[i] >= 0 && u.skill_state[i] != state && sl.look != .Locked {
			u.skill_flash[i] = 1.8
		}
		u.skill_state[i] = state
		u.skill_flash[i] = max(u.skill_flash[i] - u.dt, 0)
		label_hot := rl.Rectangle{r.x + r.width, r.y, 320 * k, r.height}
		over_label := u.skill_reveal[i] > 0.5 && rl.CheckCollisionPointRec(u.mouse, label_hot)
		want: f32 = (u.labels_always || hover || over_label || u.skill_flash[i] > 0) ? 1 : 0
		approach(u, &u.skill_reveal[i], want, 1 / 0.22)

		draw_slot(u, g, i, r, sl, hover)
		if reveal := u.skill_reveal[i]; reveal > 0.003 {
			draw_slot_label(u, r, sl, reveal)
		}
	}
}

@(private)
draw_slot :: proc(u: ^Ui, g: ^game.Game, i: int, r: rl.Rectangle, sl: Slot, hover: bool) {
	k := hud_k(u)
	t := g.time
	ink := TEXT
	switch sl.look {
	case .Locked:
		// hatched, a padlock: a skill still to come
		rl.DrawRectangleRec(r, fade({13, 11, 20, 255}, 0.78))
		rl.BeginScissorMode(i32(r.x), i32(r.y), i32(r.width + 1), i32(r.height + 1))
		for d := -r.height; d < r.width; d += 11 * k {
			rl.DrawLineEx({r.x + d, r.y + r.height}, {r.x + d + r.height, r.y}, max(1.5 * k, 1), {60, 52, 64, 200})
		}
		rl.EndScissorMode()
		rl.DrawRectangleLinesEx(r, max(k, 1), {156, 145, 126, 115})
		padlock(u, {r.x + r.width * 0.5, r.y + r.height * 0.5}, k, {142, 132, 114, 255})
		key_cap(u, fmt.tprintf("%d", i + 1), {r.x - 1 * k, r.y - 1 * k}, 0.6, k * 0.9)
		return
	case .Off:
		rl.DrawRectangleRec(r, fade({13, 11, 20, 255}, 0.82))
		dashed_rect(u, r, {156, 145, 126, 255}, k)
		ink = {156, 145, 126, 255}
	case .Ready:
		rl.DrawRectangleRec(r, fade({21, 18, 29, 255}, hover ? 0.98 : 0.9))
		rl.DrawRectangleLinesEx(r, max((hover ? 2 : 1.5) * k, 1), TEXT)
		if i == 1 {
			// standing on a handle: the slot calls
			ring := 2 + 2 * breathe(u, t, 3)
			rl.DrawRectangleLinesEx({r.x - ring * k, r.y - ring * k, r.width + 2 * ring * k, r.height + 2 * ring * k}, max(1.5 * k, 1), fade(TEXT, 0.35))
		}
	case .Active:
		glow_dot({r.x + r.width * 0.5, r.y + r.height * 0.45}, r.width * 0.3, {255, 170, 70, 255}, 0.8)
		rl.DrawRectangleRec(r, fade({40, 24, 14, 255}, 0.9))
		rl.DrawCircleGradient({r.x + r.width * 0.5, r.y + r.height * 0.42}, r.width * 0.5, fade({242, 165, 65, 255}, 0.42), fade({242, 165, 65, 255}, 0))
		rl.DrawRectangleLinesEx(r, max(2 * k, 1), BRIGHT)
		ink = {255, 233, 194, 255}
	}
	if sl.warn {
		// the oil is running out: an amber ring breathes around the slot
		g := 3 + 3 * breathe(u, t, 4)
		rl.DrawRectangleLinesEx({r.x - g * k, r.y - g * k, r.width + 2 * g * k, r.height + 2 * g * k}, max(2.5 * k, 1), fade({255, 138, 61, 255}, 0.75))
	}
	c := Vec2{r.x + r.width * 0.5, r.y + r.height * (sl.oil >= 0 ? 0.42 : 0.5)}
	switch i {
	case 0: lamp_icon(u, c, k, ink, sl.look == .Active, t)
	case 1: crank_icon(u, c, k, ink, sl.look == .Active ? f32(t) * 2 : 0)
	}
	if sl.oil >= 0 {
		// the oil: a row of notches across the slot's foot
		N :: 14
		x0 := r.x + 8 * k
		gap := 2 * k
		seg := (r.width - 16 * k - gap * (N - 1)) / N
		lit := int(math.ceil(sl.oil * N - 0.001))
		on := sl.warn ? rl.Color{255, 138, 61, 255} : (sl.look == .Active ? rl.Color{242, 180, 92, 255} : TEXT)
		for n in 0 ..< N {
			col := n < lit ? on : rl.Color{239, 230, 210, 46}
			rl.DrawRectangleRec({x0 + f32(n) * (seg + gap), r.y + r.height - 15 * k, seg, 6 * k}, col)
		}
	}
	key_cap(u, fmt.tprintf("%d", i + 1), {r.x - 1 * k, r.y - 1 * k}, 1, k * 0.9, sl.look == .Active)
}

// The skill's name and state, in a panel that slides out of the slot.
@(private)
draw_slot_label :: proc(u: ^Ui, r: rl.Rectangle, sl: Slot, reveal: f32) {
	k := hud_k(u)
	nst := Style{size = 18 * k / u.scale, color = sl.look == .Locked ? DIM : TEXT, face = .Semi, track = 0.2}
	sst := Style{size = 21 * k / u.scale, color = sl.look == .Active ? rl.Color{242, 201, 138, 255} : DIM}
	name := caps(i18n.tr(sl.look == .Locked ? .Skill_Locked : sl.name))
	status := sl.look == .Locked ? "" : sl.status
	nm := measure(u, name, nst)
	sm := measure(u, status, sst)
	full := max(nm.x, sm.x) + 40 * k
	e := fx.cubic_out(reveal)
	box := rl.Rectangle{r.x + r.width + 8 * k, r.y, full * e, r.height}
	rl.BeginScissorMode(i32(box.x), i32(box.y - 2), i32(box.width + 1), i32(box.height + 4))
	panel := rl.Rectangle{box.x - full * (1 - e), box.y, full, box.height}
	warm_card(u, panel, reveal, 0.3, k)
	if status == "" {
		text(u, name, {panel.x + 20 * k, panel.y + (panel.height - nm.y) * 0.5}, nst, .Left, reveal)
	} else {
		top := panel.y + (panel.height - nm.y - sm.y - 2 * k) * 0.5
		text(u, name, {panel.x + 20 * k, top}, nst, .Left, reveal)
		text(u, status, {panel.x + 20 * k, top + nm.y + 2 * k}, sst, .Left, reveal)
	}
	rl.EndScissorMode()
}

// 0..1, slowly in and out (0 when motion is reduced).
@(private)
breathe :: proc(u: ^Ui, t, speed: f32) -> f32 {
	return u.reduce_motion ? 0.5 : 0.5 + 0.5 * math.sin(t * speed)
}

// A rectangle drawn in dashes: a skill that cannot be used now.
@(private)
dashed_rect :: proc(u: ^Ui, r: rl.Rectangle, col: rl.Color, k: f32) {
	th := max(1.5 * k, 1)
	dash := 7 * k
	gap := 5 * k
	for x := r.x; x < r.x + r.width; x += dash + gap {
		l := min(dash, r.x + r.width - x)
		rl.DrawRectangleRec({x, r.y, l, th}, col)
		rl.DrawRectangleRec({x, r.y + r.height - th, l, th}, col)
	}
	for y := r.y; y < r.y + r.height; y += dash + gap {
		l := min(dash, r.y + r.height - y)
		rl.DrawRectangleRec({r.x, y, th, l}, col)
		rl.DrawRectangleRec({r.x + r.width - th, y, th, l}, col)
	}
}

// Lines through points given in a 48 x 48 box centred on c.
@(private)
strokes :: proc(c: Vec2, k: f32, pts: []Vec2, th: f32, col: rl.Color) {
	for i in 0 ..< len(pts) - 1 {
		a := c + (pts[i] - 24) * k
		b := c + (pts[i + 1] - 24) * k
		rl.DrawLineEx(a, b, th * k, col)
		rl.DrawCircleV(b, th * k * 0.5, col)
	}
}

// An oil lamp: its body, the spout, the foot; a flame when lit.
@(private)
lamp_icon :: proc(u: ^Ui, c: Vec2, k: f32, col: rl.Color, lit: bool, t: f32) {
	strokes(c, k, {{9, 31}, {11, 26}, {16, 22.5}, {22, 21}, {28, 22.5}, {32, 26}, {33, 31}}, 2.3, col)
	strokes(c, k, {{7, 31}, {35, 31}, {39, 30}, {42, 27.5}, {43, 25}, {31, 25}}, 2.3, col)
	strokes(c, k, {{17, 37}, {29, 37}}, 2.3, col)
	strokes(c, k, {{22, 31}, {22, 37}}, 2.3, col)
	if lit {
		f := 1 + (u.reduce_motion ? 0 : 0.12 * math.sin(t * 13))
		base := c + (Vec2{40, 22} - 24) * k
		glow_dot(base - {0, 4 * k}, 5 * k, {255, 176, 77, 255}, 1)
		tri(base + {-3.5 * k, 0}, base + {3.5 * k, 0}, base - {0, 11 * k * f}, {255, 214, 140, 255})
	} else {
		strokes(c, k, {{40, 22}, {40, 19}}, 2, fade(col, 0.6))
	}
}

// A handle's capstan: a ring, its hub, four spokes and the grip; `spin` turns it.
@(private)
crank_icon :: proc(u: ^Ui, c: Vec2, k: f32, col: rl.Color, spin: f32) {
	rl.DrawRing(c, 11 * k, 13.3 * k, 0, 360, 40, col)
	rl.DrawCircleV(c, 3.2 * k, col)
	for n in 0 ..< 4 {
		a := spin + f32(n) * math.PI * 0.5
		d := Vec2{math.cos(a), math.sin(a)}
		rl.DrawLineEx(c + d * 3 * k, c + d * 18 * k, 2.3 * k, col)
	}
	a := spin + math.PI * 0.25
	d := Vec2{math.cos(a), math.sin(a)}
	rl.DrawLineEx(c + d * 12 * k, c + d * 20 * k, 3 * k, col)
}

@(private)
padlock :: proc(u: ^Ui, c: Vec2, k: f32, col: rl.Color) {
	rl.DrawRectangleLinesEx({c.x - 9 * k, c.y - 3 * k, 18 * k, 14 * k}, max(2 * k, 1), col)
	rl.DrawRing(c - {0, 3 * k}, 4.5 * k, 6.5 * k, 180, 360, 20, col)
}

// --- the diorama: Q, E, R in the bottom right ---------------------------------------

DIO :: 60 // a button of the diorama, 1080p px
DIO_GAP :: 12

// Button i of the diorama (0 Q, 1 E, 2 R), from the bottom right corner.
@(private)
diorama_button :: proc(u: ^Ui, i: int) -> rl.Rectangle {
	k := hud_k(u)
	right := u.width - 36 * k
	x := right - f32(3 - i) * DIO * k - f32(2 - i) * DIO_GAP * k - (i < 2 ? 14 * k : 0)
	return {x, u.height - 36 * k - DIO * k, DIO * k, DIO * k}
}

@(private)
draw_diorama :: proc(u: ^Ui, g: ^game.Game, input: Hud_Input, act: ^Hud_Action) {
	k := hud_k(u)
	keys := [3]string{"Q", "E", "R"}
	for i in 0 ..< 3 {
		r := diorama_button(u, i)
		add_hot(u, r)
		hover := rl.CheckCollisionPointRec(u.mouse, r)
		held := i == 2 && input.hold > 0
		rl.DrawRectangleRec(r, fade({21, 18, 29, 255}, hover ? 0.95 : 0.78))
		rl.DrawRectangleLinesEx(r, max((hover ? 2 : 1.5) * k, 1), hover || held ? BRIGHT : fade(TEXT, 0.85))
		c := Vec2{r.x + r.width * 0.5, r.y + r.height * 0.5 + 2 * k}
		col := hover ? TITLE : TEXT
		switch i {
		case 0, 1:
			turn_arrow(u, c, k, i == 0 ? -1 : 1, col)
			if hover && u.pressed {
				act.turn = i == 0 ? -1 : 1
			}
		case 2:
			// the brazier's flame in a ring that fills while R is held
			rad := 21 * k
			rl.DrawRing(c, rad - 3 * k, rad, 0, 360, 48, {239, 230, 210, 50})
			if input.hold > 0 {
				rl.DrawRing(c, rad - 3 * k, rad, -90, -90 + 360 * input.hold, 48, input.hold >= 1 ? rl.Color{255, 211, 138, 255} : BRIGHT)
			}
			flame(u, c + {0, 2 * k}, k, {242, 180, 92, 255})
			if hover && u.down {
				act.rest_down = true
			}
		}
		key_cap(u, keys[i], {r.x - 1 * k, r.y - 1 * k}, 1, k * 0.8)

		// its name, above it, on hover
		approach(u, &u.tip_reveal[i], hover || held ? 1 : 0, 1 / 0.18)
		if a := u.tip_reveal[i]; a > 0.003 {
			label: i18n.Key
			switch i {
			case 0: label = .Turn_Left
			case 1: label = .Turn_Right
			case 2: label = input.twice ? .Rest_Button_Twice : .Rest_Button
			}
			st := Style{size = 20 * k / u.scale, color = TEXT}
			msg := i18n.tr(label)
			m := measure(u, msg, st)
			box := rl.Rectangle{min(r.x + r.width * 0.5 - m.x * 0.5 - 14 * k, u.width - 20 * k - m.x - 28 * k), r.y - m.y - 30 * k + (1 - fx.cubic_out(a)) * 8 * k, m.x + 28 * k, m.y + 14 * k}
			warm_card(u, box, a, 0.3, k)
			text(u, msg, {box.x + 14 * k, box.y + 7 * k}, st, .Left, a)
		}
	}
}

// A turning arrow: an open ring, its head at the end it runs toward
// (step -1: anticlockwise).
@(private)
turn_arrow :: proc(u: ^Ui, c: Vec2, k: f32, step: int, col: rl.Color) {
	ar := 13 * k
	th := 2.6 * k
	rl.DrawRing(c, ar - th, ar, -60, 240, 32, col)
	head: f32 = (step < 0 ? -60 : 240) * math.PI / 180
	d: f32 = step < 0 ? -1 : 1
	normal := Vec2{math.cos(head), math.sin(head)}
	tip := c + normal * (ar - th * 0.5)
	tangent := Vec2{-math.sin(head), math.cos(head)} * d
	h := 7 * k
	tri(tip + tangent * h, tip + normal * h * 0.8, tip - normal * h * 0.8, col)
}

// A small flame (the brazier).
@(private)
flame :: proc(u: ^Ui, c: Vec2, k: f32, col: rl.Color) {
	rl.DrawCircleV(c + {0, 4 * k}, 6 * k, col)
	tri(c + {-6 * k, 3 * k}, c + {6 * k, 3 * k}, c + {1 * k, -12 * k}, col)
	rl.DrawCircleV(c + {0, 5 * k}, 2.6 * k, {40, 24, 14, 255})
}

// The action of the place (Space): a card over Psyche when there is one.
@(private)
draw_place :: proc(u: ^Ui, g: ^game.Game, input: Hud_Input, act: ^Hud_Action) {
	k := hud_k(u)
	here := game.at_cave(g)
	approach(u, &u.place_reveal, here ? 1 : 0, 1 / 0.25)
	a := u.place_reveal
	if a <= 0.003 {
		return
	}
	st := Style{size = 22 * k / u.scale, color = TEXT, face = .Semi}
	msg := i18n.tr(.Place_Cave)
	m := measure(u, msg, st)
	cap_w := key_cap_width(u, i18n.tr(.Key_Space), k)
	wd := cap_w + m.x + 40 * k
	ht := 46 * k
	lift := (1 - fx.cubic_out(a)) * 10 * k
	p := input.psyche_screen
	box := rl.Rectangle{p.x - wd * 0.5, p.y - ht - 16 * k + lift, wd, ht}
	add_hot(u, box)
	hover := here && rl.CheckCollisionPointRec(u.mouse, box)
	warm_card(u, box, a, hover ? 0.8 : 0.4, k)
	key_cap(u, i18n.tr(.Key_Space), {box.x + 12 * k, box.y + (ht - 28 * k) * 0.5}, a, k)
	text(u, msg, {box.x + 24 * k + cap_w, box.y + (ht - m.y) * 0.5 - k}, {size = st.size, color = hover ? BRIGHT : TEXT, face = .Semi}, .Left, a)
	tip := Vec2{p.x, box.y + ht + 10 * k}
	tri(tip, tip + {-8 * k, -10 * k}, tip + {8 * k, -10 * k}, fade(GOLD, a))
	if hover && u.pressed {
		act.place = true
	}
}

@(private)
key_cap_width :: proc(u: ^Ui, key: string, k: f32) -> f32 {
	m := measure(u, key, {size = 21 * k / u.scale, face = .Semi})
	return max(m.x + 14 * k, 28 * k)
}

// Top left, quiet: the key for the pause (with the controls).
@(private)
keys_badge :: proc(u: ^Ui, a: f32) {
	k := hud_k(u)
	st := Style{size = 24 * k / u.scale, color = TEXT, face = .Semi, shadow = true}
	x := 40 * k
	y := 36 * k
	x += key_cap(u, "Esc", {x, y}, a, k) + 10 * k
	label := i18n.tr(.Badge_Pause)
	lm := measure(u, label, st)
	text(u, label, {x, y + (28 * k - lm.y) * 0.5 - k}, st, .Left, a * 0.9)
}

// A square frame breathing around the controls a tutorial points at.
@(private)
point_at :: proc(u: ^Ui, g: ^game.Game, r: rl.Rectangle) {
	k := hud_k(u)
	b := breathe(u, g.time, 4)
	grow := (5 + 5 * b) * k
	box := rl.Rectangle{r.x - grow, r.y - grow, r.width + 2 * grow, r.height + 2 * grow}
	rl.DrawRectangleLinesEx(box, max(2 * k, 1), fade(BRIGHT, 0.35 + 0.45 * b))
	corner_frame(u, {box.x - 4 * k, box.y - 4 * k, box.width + 8 * k, box.height + 8 * k}, 0.9, k, BRIGHT)
}

// The letterbox of the cutscenes: black bands at the top and the bottom, k = 0..1.
@(private)
cinema_bars :: proc(u: ^Ui, k: f32) -> (height: f32) {
	if k <= 0 {
		return 0
	}
	height = u.height * CINEMA_BAR * k
	rl.DrawRectangleRec({0, 0, u.width, height}, {0, 0, 0, 255})
	rl.DrawRectangleRec({0, u.height - height, u.width, height}, {0, 0, 0, 255})
	return
}

CINEMA_BAR :: 0.12 // of the screen height

// The prologue over the palace, filmed: the letterbox, the fade from black,
// the act's name in the upper band, the captions in the lower one, and at
// the end the invitation to begin.
@(private)
draw_prologue :: proc(u: ^Ui, g: ^game.Game) {
	s := u.scale
	w, h := u.width, u.height
	t := g.phase_t
	if t < game.PRO_WALK_START {
		rl.DrawRectangleRec({0, 0, w, h}, fade({3, 3, 10, 255}, 1 - t / game.PRO_WALK_START))
	}
	bar := cinema_bars(u, game.cine(g).bars)
	act := content.LEVELS[g.level_index].act
	if a := clamp((t - 0.6) / 1.2, 0, 1) * clamp((7.5 - t) / 1.5, 0, 1); a > 0 {
		label := Style{size = 20, face = .Semi, track = 0.18}
		title := Style{size = 54, face = .Display}
		lh := measure(u, "A", label).y
		th := measure(u, "A", title).y
		top := (bar - lh - th - 6 * s) * 0.5
		rule_label(u, caps(i18n.tr(content.ACT_LABEL[act])), {w * 0.5, top}, 20, 80 * s, a)
		text(u, i18n.tr(content.ACT_TITLE[act]), {w * 0.5, top + lh + 6 * s}, {size = 54, color = TITLE, face = .Display, glow = true}, .Center, a)
	}
	if key, a := game.prologue_caption(g); a > 0 {
		st := Style{size = 34, color = TITLE, face = .Italic}
		msg := i18n.tr(key)
		bh := block_height(u, msg, st, 1500 * s)
		paragraph(u, msg, {w * 0.5, h - bar * 0.5 - bh * 0.5}, st, 1500 * s, a)
	}
	if game.prologue_ready(g) {
		since := t - game.prologue_alone(g) - game.PRO_PROMPT
		blink := 0.6 + 0.3 * math.sin(t * 2.4)
		st := Style{size = 30, color = TEXT, face = .Italic}
		text(u, i18n.tr(.Pro_Start), {w * 0.5, bar * 0.5 - measure(u, "A", st).y * 0.5}, st, .Center, blink * clamp(since / 1, 0, 1))
	}
}

// A tutorial hint: a square card over the game on the left, above the skills, with a drawn sign of the
// mechanic. It slides in, stays until Psyche does what it teaches, then shows
// a tick and slides away. Each is shown only the first time.
@(private)
draw_tutorial :: proc(u: ^Ui, g: ^game.Game) {
	s := hud_k(u)
	z := u.hud_size // text sizes follow the HUD's size
	f := g.hud.hint
	done := f.hide_t >= 0 && g.learned[f.key]
	a: f32
	slide: f32
	if f.hide_t >= 0 {
		out := clamp((f.hide_t - (done ? 0.3 : 0)) / 0.5, 0, 1)
		a = 1 - out
		slide = -out * out * 60 * s
	} else {
		in_ := clamp(f.t / 0.6, 0, 1)
		a = in_
		slide = -(1 - in_) * (1 - in_) * (1 - in_) * 60 * s
	}
	if a <= 0.003 {
		return
	}
	msg := i18n.tr(f.key)
	st := Style{size = 32 * z, color = TEXT}
	lst := Style{size = 18 * z, color = GOLD, face = .Semi, track = 0.16}
	width := 620 * s
	text_w := width - 150 * s
	lines := wrap(u, msg, st, text_w)
	step := st.size * u.scale * 1.25
	label_h := measure(u, "A", lst).y
	height := max(f32(len(lines)) * step + label_h + 54 * s, 128 * s)
	// above the skills, clear of them
	card := rl.Rectangle{40 * s + slide, max(u.height * 0.5 - 340 * s - height, 120 * s), width, height}

	breath := 0.75 + 0.25 * breathe(u, g.time, 3)
	rl.DrawRectangleRec(card, fade({13, 11, 20, 255}, 0.86 * a))
	edge := done ? fade(TITLE, a) : fade(GOLD, a * (0.3 + 0.3 * breath))
	rl.DrawRectangleLinesEx(card, max(1.2 * s, 1), edge)
	corner_frame(u, card, a, s)

	// the sign of the mechanic, on a square plate
	c := Vec2{card.x + 68 * s, card.y + card.height * 0.5}
	rad := 38 * s
	plate := rl.Rectangle{c.x - rad, c.y - rad, rad * 2, rad * 2}
	rl.DrawRectangleRec(plate, fade({40, 24, 14, 255}, a))
	rl.DrawRectangleLinesEx(plate, max(1.5 * s, 1), fade(GOLD, a * (done ? 1 : 0.5 + 0.3 * breath)))
	if done {
		tick := fade({255, 226, 150, 255}, a)
		rl.DrawLineEx(c + Vec2{-15, 1} * s, c + Vec2{-4, 12} * s, 5 * s, tick)
		rl.DrawLineEx(c + Vec2{-4, 12} * s, c + Vec2{17, -11} * s, 5 * s, tick)
	} else {
		tutorial_sign(u, g, f.key, c, fade(GOLD, a))
	}

	x := card.x + 136 * s
	y := card.y + (card.height - (label_h + 8 * s + f32(len(lines)) * step)) * 0.5
	text(u, caps(i18n.tr(.Tutorial_Label)), {x, y}, lst, .Left, a * 0.9)
	y += label_h + 8 * s
	for line, i in lines {
		text(u, line, {x, y + f32(i) * step}, st, .Left, a)
	}
}

// A small drawing of what a tutorial teaches.
@(private)
tutorial_sign :: proc(u: ^Ui, g: ^game.Game, key: i18n.Key, c: Vec2, col: rl.Color) {
	s := u.scale
	tile :: proc(c: Vec2, r: f32, col: rl.Color, filled: bool) {
		pts := [4]Vec2{c + {0, -r * 0.5}, c + {r, 0}, c + {0, r * 0.5}, c + {-r, 0}}
		if filled {
			tri(pts[0], pts[1], pts[2], col)
			tri(pts[0], pts[2], pts[3], col)
		} else {
			for i in 0 ..< 4 {
				rl.DrawLineEx(pts[i], pts[(i + 1) % 4], 2 * u_scale_of(r), col)
			}
		}
	}
	#partial switch key {
	case .Hint_Move:
		// a tile and the ripple of a click on it
		tile(c + {0, 4 * s}, 24 * s, col, false)
		k := math.mod(g.time, 1.4) / 1.4
		rl.DrawRing(c + {0, 4 * s}, 4 * s + k * 14 * s, 6 * s + k * 14 * s, 0, 360, 32, fade(col, 1 - k))
		rl.DrawCircleV(c + {0, 4 * s}, 4 * s, col)
	case .Hint_Turn:
		// the turning arrow of the buttons
		r := 20 * s
		thick := 3.5 * s
		rl.DrawRing(c, r - thick, r, -60, 240, 32, col)
		head: f32 = -60 * math.PI / 180
		normal := Vec2{math.cos(head), math.sin(head)}
		tip := c + normal * (r - thick * 0.5)
		tangent := Vec2{-math.sin(head), math.cos(head)} * -1
		h := 10 * s
		tri(tip + tangent * h, tip + normal * h * 0.75, tip - normal * h * 0.75, col)
	case .Hint_Lamp, .Hint_Sigil:
		// a standing candelabrum, its three candles catching the flame one by one
		th := 2.5 * s
		rl.DrawLineEx(c + Vec2{0, 22} * s, c + Vec2{0, -6} * s, th, col)
		rl.DrawLineEx(c + Vec2{-10, 22} * s, c + Vec2{10, 22} * s, th, col)
		rl.DrawLineEx(c + Vec2{-14, -6} * s, c + Vec2{14, -6} * s, th, col)
		k := math.mod(g.time, 2.4) / 2.4
		for n in 0 ..< 3 {
			x := f32(n - 1) * 14
			rl.DrawLineEx(c + Vec2{x, -6} * s, c + Vec2{x, -12} * s, 3 * s, col)
			if k > f32(n) * 0.22 {
				flick := 1 + 0.12 * math.sin(g.time * 13 + f32(n))
				tri(c + Vec2{x - 3, -13} * s, c + Vec2{x + 3, -13} * s, c + Vec2{x, -13 - 9 * flick} * s, col)
			}
		}
	case .Hint_Oil:
		// a flame
		flick := 1 + 0.08 * math.sin(g.time * 13)
		rl.DrawCircleV(c + {0, 6 * s}, 10 * s, col)
		tri(c + {-10 * s, 4 * s}, c + {10 * s, 4 * s}, c + {0, -20 * s * flick}, col)
	case .Hint_Illusion:
		// two tiles that seem to touch
		tile(c + {-9 * s, 5 * s}, 15 * s, col, true)
		tile(c + {9 * s, -5 * s}, 15 * s, col, false)
	case:
		diamond(u, c, 14 * s, col, true)
	}
}

@(private)
u_scale_of :: proc(r: f32) -> f32 {
	return max(r / 24, 0.5)
}

// A hint on a squared band near the bottom; a
// tutorial hint (what to press) is brighter and breathes until it is done.
@(private)
draw_hint :: proc(u: ^Ui, g: ^game.Game, msg: string, tutorial: bool, a: f32) {
	k := hud_k(u)
	z := u.hud_size
	w, h := u.width, u.height
	st := Style{size = (tutorial ? 34 : 30) * z, color = tutorial ? TEXT : DIM}
	size := measure(u, msg, st)
	y := h - 150 * k
	pad := Vec2{32 * k, 14 * k}
	band := rl.Rectangle{w * 0.5 - size.x * 0.5 - pad.x, y - size.y * 0.5 - pad.y, size.x + 2 * pad.x, size.y + 2 * pad.y}
	warm_card(u, band, a, tutorial ? 0.3 + 0.4 * breathe(u, g.time, 3) : 0.25, k)
	text(u, msg, {w * 0.5, y - size.y * 0.5}, st, .Center, a)
}

// Darken the game toward the edges, for a card that wants all the attention.
focus_shade :: proc(u: ^Ui, a: f32) {
	rl.DrawRectangleRec({0, 0, u.width, u.height}, fade({3, 3, 10, 255}, 0.62 * a))
	edge := fade({0, 0, 4, 255}, 0.5 * a)
	clear_ := rl.Color{0, 0, 4, 0}
	band := u.height * 0.3
	rl.DrawRectangleGradientV(0, 0, i32(u.width), i32(band), edge, clear_)
	rl.DrawRectangleGradientV(0, i32(u.height - band), i32(u.width), i32(band) + 1, clear_, edge)
}

// A level's new mechanic, presented when the level begins: the game waits
// while it is read and its pieces glow in the palace. Reports a click once
// it has been on screen for a moment (Enter is read by the app).
mechanic_card :: proc(u: ^Ui, title, body: i18n.Key, t: f32) -> (clicked: bool) {
	s := u.scale
	w := u.width
	a := clamp(t / 0.6, 0, 1)
	// a lighter shade than the fragment's: the palace stays visible, its new pieces glowing
	rl.DrawRectangleRec({0, 0, u.width, u.height}, fade({3, 3, 10, 255}, 0.3 * a))
	st := Style{size = 34, color = TEXT, shadow = true}
	msg := i18n.tr(body)
	bw := 1150 * s
	bh := block_height(u, msg, st, bw, 1.3)
	// low on the screen, so that the palace and its glowing pieces stay in view
	y := u.height - bh - 130 * s
	band := rl.Rectangle{w * 0.5 - bw * 0.5 - 60 * s, y - 104 * s, bw + 120 * s, bh + 214 * s}
	warm_card(u, band, a, 0.4)
	rule_label(u, caps(i18n.tr(.Mech_New)), {w * 0.5, y - 88 * s}, 19, 70 * s, a)
	text(u, i18n.tr(title), {w * 0.5, y - 58 * s}, {size = 62, color = TITLE, face = .Display, glow = true, shadow = true}, .Center, a)
	paragraph(u, msg, {w * 0.5, y + 30 * s}, st, bw, a, 1.3)
	ready := t > 0.8
	if ready {
		blink := 0.8 + 0.2 * math.sin(t * 2.4)
		text(u, i18n.tr(.Fragment_Continue), {w * 0.5, y + 30 * s + bh + 30 * s}, {size = 25, color = DIM, face = .Italic}, .Center, blink * clamp((t - 0.8) / 0.6, 0, 1))
	}
	return ready && u.pressed
}

// The fragment just found: the game waits while it is read. Reports a click
// once it has been on screen for a moment (Enter is read by the app).
fragment_card :: proc(u: ^Ui, key: i18n.Key, t: f32) -> (clicked: bool) {
	s := u.scale
	w := u.width
	a := clamp(t / 0.8, 0, 1)
	// the palace sinks into the dark: only the tale is in focus
	focus_shade(u, a)
	st := Style{size = 38, color = TEXT, face = .Italic, shadow = true}
	msg := i18n.tr(key)
	bw := 1100 * s
	bh := block_height(u, msg, st, bw, 1.3)
	y := u.height * 0.5 - (bh + 110 * s) * 0.5
	band := rl.Rectangle{w * 0.5 - bw * 0.5 - 60 * s, y - 50 * s, bw + 120 * s, bh + 190 * s}
	warm_card(u, band, a * 0.85, 0.35)
	diamond(u, {w * 0.5, y - 18 * s}, 7 * s, fade(BRIGHT, a), true)
	rule_label(u, caps(i18n.tr(.Fragment_Found)), {w * 0.5, y}, 19, 70 * s, a)
	paragraph(u, msg, {w * 0.5, y + 44 * s}, st, bw, a, 1.3)
	ready := t > 0.8
	if ready {
		blink := 0.8 + 0.2 * math.sin(t * 2.4)
		text(u, i18n.tr(.Fragment_Continue), {w * 0.5, y + 44 * s + bh + 30 * s}, {size = 25, color = DIM, face = .Italic}, .Center, blink * clamp((t - 0.8) / 0.6, 0, 1))
	}
	return ready && u.pressed
}
