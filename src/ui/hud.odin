// In-game overlay: level title, Cupid's voice, hints,
// controls, oil gauge and lamp button (when Psyche has the lamp), the two
// turn buttons.
package ui

import "core:math"
import rl "vendor:raylib"

import "../content"
import "../game"
import "../i18n"

Hud_Action :: struct {
	lamp: bool,
	turn: int,
}

draw_hud :: proc(u: ^Ui, g: ^game.Game) -> (act: Hud_Action) {
	s := u.scale
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
		// centred in the band between 210 and 120 px from the bottom
		top := h - 165 * s - bh * 0.5
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
	// the control a tutorial is about pulses until it is used
	if teaching {
		#partial switch hud.hint.key {
		case .Hint_Turn:
			point_at(u, g, {34 * s, h - 134 * s, 200 * s, 100 * s})
		case .Hint_Lamp:
			point_at(u, g, lamp_rect(u))
		}
	}
	if g.data.has_lamp {
		draw_oil(u, g)
		if lamp_button(u, g) {
			act.lamp = true
		}
	}
	if turn_button(u, {84 * s, h - 84 * s}, -1) {
		act.turn = -1
	}
	if turn_button(u, {184 * s, h - 84 * s}, 1) {
		act.turn = 1
	}
	return
}

// Where the lamp button sits: a pill in the bottom right corner.
@(private)
lamp_rect :: proc(u: ^Ui) -> rl.Rectangle {
	s := u.scale
	label := caps(i18n.tr(.Lamp_Button))
	m := measure(u, label, {size = 23, face = .Semi, track = 0.15})
	wd := m.x + 160 * s
	return {u.width - 44 * s - wd, u.height - 126 * s, wd, 84 * s}
}

// The lamp: a glowing diamond, its name, its key; brighter while it burns.
@(private)
lamp_button :: proc(u: ^Ui, g: ^game.Game) -> bool {
	s := u.scale
	r := lamp_rect(u)
	add_hot(u, r)
	hover := rl.CheckCollisionPointRec(u.mouse, r)
	lit := g.light
	cy := r.y + r.height * 0.5
	// the lamp's glow spills around the pill while it burns
	glow_dot({r.x + r.width * 0.5, cy}, r.height * 0.6, {255, 170, 70, 255}, 0.4 + 0.6 * lit)
	rl.DrawRectangleRounded(r, 1, 24, fade(WARM, hover ? 0.85 : 0.62))
	rl.DrawRectangleRoundedLinesEx(r, 1, 24, max(1.2 * s, 1), fade(GOLD, 0.45 + 0.4 * lit))
	c := Vec2{r.x + 40 * s, cy}
	glow_dot(c, 7 * s, {255, 176, 77, 255}, 0.6 + 0.4 * lit)
	diamond(u, c, 8 * s, BRIGHT, true)
	label := caps(i18n.tr(.Lamp_Button))
	st := Style{size = 23, color = hover ? TITLE : BRIGHT, face = .Semi, track = 0.15}
	m := measure(u, label, st)
	text(u, label, {r.x + 64 * s, cy - m.y * 0.5}, st, .Left)
	key_cap(u, i18n.tr(.Key_Space), {r.x + 64 * s + m.x + 14 * s, cy - 15 * s})
	if hover && u.pressed {
		return true
	}
	return false
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

// Top left, quiet: the keys for the pause (with the controls) and the restart.
@(private)
keys_badge :: proc(u: ^Ui, a: f32) {
	s := u.scale
	st := Style{size = 25, color = TEXT, shadow = true}
	x := 42 * s
	y := 36 * s
	items := [2]struct {
		key:   string,
		label: i18n.Key,
	}{{"Esc", .Badge_Pause}, {"R", .Badge_Restart}}
	for it in items {
		x += key_cap(u, it.key, {x, y}, a) + 10 * s
		label := i18n.tr(it.label)
		lm := measure(u, label, st)
		text(u, label, {x, y + (30 * s - lm.y) * 0.5}, st, .Left, a * 0.85)
		x += lm.x + 30 * s
	}
}

// A frame breathing around the controls the tutorial points at.
@(private)
point_at :: proc(u: ^Ui, g: ^game.Game, r: rl.Rectangle) {
	k := 0.5 + 0.5 * math.sin(g.time * 4)
	grow := 4 * u.scale * k
	box := rl.Rectangle{r.x - grow, r.y - grow, r.width + 2 * grow, r.height + 2 * grow}
	rl.DrawRectangleRoundedLinesEx(box, 1, 24, max(2 * u.scale, 1), fade(BRIGHT, 0.35 + 0.45 * k))
}

// A tutorial hint: a card over the game on the left, with a drawn sign of the
// mechanic. It slides in, stays until Psyche does what it teaches, then shows
// a tick and slides away. Each is shown only the first time.
@(private)
draw_tutorial :: proc(u: ^Ui, g: ^game.Game) {
	s := u.scale
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
	st := Style{size = 32, color = TEXT}
	lst := Style{size = 18, color = GOLD, face = .Semi, track = 0.16}
	width := 620 * s
	text_w := width - 150 * s
	lines := wrap(u, msg, st, text_w)
	step := st.size * s * 1.25
	label_h := measure(u, "A", lst).y
	height := max(f32(len(lines)) * step + label_h + 54 * s, 128 * s)
	card := rl.Rectangle{40 * s + slide, u.height * 0.3 - height * 0.5, width, height}

	breath := 0.75 + 0.25 * math.sin(g.time * 3)
	rl.DrawRectangleRounded(card, 0.18, 12, fade(WARM, 0.8 * a))
	edge := done ? fade(TITLE, a) : fade(GOLD, a * (0.3 + 0.3 * breath))
	rl.DrawRectangleRoundedLinesEx(card, 0.18, 12, max(1.2 * s, 1), edge)

	// the sign of the mechanic, in a ring
	c := Vec2{card.x + 68 * s, card.y + card.height * 0.5}
	rad := 40 * s
	rl.DrawCircleV(c, rad, fade({58, 32, 18, 255}, a))
	rl.DrawRing(c, rad - 2 * s, rad, 0, 360, 48, fade(GOLD, a * (done ? 1 : 0.5 + 0.3 * breath)))
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

// A hint on a dark band at the bottom; a tutorial hint (what to press) is
// brighter, marked with a diamond, and breathes until it is done.
@(private)
draw_hint :: proc(u: ^Ui, g: ^game.Game, msg: string, tutorial: bool, a: f32) {
	s := u.scale
	w, h := u.width, u.height
	st := Style{size = tutorial ? 34 : 30, color = tutorial ? TEXT : DIM}
	size := measure(u, msg, st)
	y := h - 62 * s
	pad := Vec2{36 * s, 16 * s}
	band := rl.Rectangle{w * 0.5 - size.x * 0.5 - pad.x, y - size.y * 0.5 - pad.y, size.x + 2 * pad.x, size.y + 2 * pad.y}
	breath: f32 = tutorial ? 0.75 + 0.25 * math.sin(g.time * 3) : 1
	warm_card(u, band, a, 1, 0.25)
	if tutorial {
		rl.DrawRectangleRoundedLinesEx(band, 0.5, 12, max(1.5 * s, 1), fade(GOLD, 0.55 * a * breath))
		diamond(u, {band.x + 18 * s, y}, 5 * s, fade(GOLD, a * breath), true)
		diamond(u, {band.x + band.width - 18 * s, y}, 5 * s, fade(GOLD, a * breath), true)
	}
	text(u, msg, {w * 0.5, y - size.y * 0.5}, st, .Center, a)
}

// The oil gauge: a thin upright line of light along the right edge; the oil
// is the lit part from the bottom, a bead of flame at its top that glows
// brighter while the lamp burns.
@(private)
draw_oil :: proc(u: ^Ui, g: ^game.Game) {
	s := u.scale
	x := u.width - 52 * s
	top := 48 * s
	bottom := u.height - 190 * s
	wd := 4 * s
	track := rl.Rectangle{x - wd * 0.5, top, wd, bottom - top}
	if g.hud.hint.active && g.hud.hint.key == .Hint_Oil {
		// the oil lesson points at the gauge
		pulse := 0.5 + 0.5 * math.sin(g.time * 4)
		ring := rl.Rectangle{track.x - 16 * s, track.y - 16 * s, track.width + 32 * s, track.height + 32 * s}
		rl.DrawRectangleRoundedLinesEx(ring, 1, 24, max(2 * s, 1), fade(BRIGHT, (0.4 + 0.5 * pulse) * game.fade_alpha(g.hud.hint)))
	}
	rl.DrawRectangleRounded(track, 1, 6, {255, 255, 255, 56})
	oil := clamp(g.oil / g.oil_max, 0, 1)
	lit := g.light
	h := track.height * oil
	fill := rl.Rectangle{track.x, bottom - h, wd, h}
	col := rl.Color{255, u8(214 + 20 * lit), u8(150 + 40 * lit), 255}
	if h > 0 {
		rl.DrawRectangleRounded(fill, 1, 6, col)
		// the light of the oil along the line
		rl.DrawRectangleRounded({fill.x - 3 * s, fill.y, fill.width + 6 * s, fill.height}, 1, 6, fade({255, 200, 110, 255}, 0.18 + 0.2 * lit))
	}
	bead := Vec2{x, bottom - h}
	glow_dot(bead, (8 + 4 * lit) * s, {255, 190, 100, 255}, 0.5 + 0.5 * lit)
	rl.DrawCircleV(bead, (6.5 + 1.5 * lit) * s, {255, 228, 170, 255})
	text(u, caps(i18n.tr(.Oil)), {x, bottom + 16 * s}, {size = 17, color = GOLD, face = .Semi, track = 0.14, shadow = true}, .Center, 0.85)
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
	warm_card(u, band, a, 0.12, 0.4)
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
	warm_card(u, band, a * 0.85, 0.08, 0.35)
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
