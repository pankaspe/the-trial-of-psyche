// Immediate-mode UI: fonts, text, buttons, option rows and sliders.
//
// The look is "lamplight", squared: titles in Mystery Quest with a warm halo,
// text in Cormorant Garamond, warm gold and ivory; cards and key caps are
// square, framed by four small gold corners (`corner_frame`); the settings
// sheet is dark glass over the game (`glass_panel`).
//
// Layout is designed for a 1920 x 1080 screen and scaled by `scale`.
// Widgets record their rectangles every frame; the game asks `over_ui` (with
// the previous frame's rectangles) before treating a click as a walk order.
//
// With a pad in hand the cursor hides and menus are walked with a focus: the
// widgets that can be chosen register (`focusable`) in drawing order, the
// d-pad or the stick moves the focus to the nearest one that way (on last
// frame's rectangles), South chooses it; option rows and sliders take left
// and right for themselves.
package ui

import "core:math"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"

import "../audio"
import "../content"
import "../i18n"
import "../input"
import "../iso"

Vec2 :: iso.Vec2

TEXT :: rl.Color{241, 230, 208, 255} // ivory
DIM :: rl.Color{204, 189, 163, 255} // parchment
GOLD :: rl.Color{240, 196, 120, 255}
BRIGHT :: rl.Color{255, 213, 142, 255} // the gold of what is chosen
TITLE :: rl.Color{251, 235, 200, 255}
FAINT :: rl.Color{196, 178, 150, 200}
SHADOW :: rl.Color{8, 3, 0, 204}
HALO :: rl.Color{240, 160, 70, 255} // the warm glow around titles
WARM :: rl.Color{38, 20, 12, 255} // the tint of cards and buttons
NIGHT :: rl.Color{16, 12, 34, 255} // the tint of the glass sheet

// The faces of the UI. Atlases are rebuilt for the UI scale (sizes at 1080p):
// text stays crisp from 720p to 4K. Titles are drawn from a large atlas with
// little upscaling, text is mipmapped down.
Face :: enum u8 {
	Body, // Cormorant Garamond Medium
	Semi, // Cormorant Garamond SemiBold: labels in capitals, values, buttons
	Italic, // Cormorant Garamond Medium Italic: the tale's voice
	Display, // Mystery Quest: titles
}

@(private)
FACE_BASE := [Face]f32 {
	.Body    = 64,
	.Semi    = 48,
	.Italic  = 64,
	.Display = 128,
}

MAX_HOT :: 48
MAX_FOCUS :: 48

Ui :: struct {
	fonts:     [Face]rl.Font,
	font_px:   [Face]i32, // atlas sizes currently loaded
	scale:     f32, // screen height / 1080
	width:     f32,
	height:    f32,
	settings_tab: Settings_Tab, // the page of the settings panel on screen
	toast_visible: bool, // an achievement notice is in the top left corner
	glass:     rl.Texture2D, // the picture frosted (upside down), when a glass panel is up
	has_glass: bool,
	mouse:     Vec2,
	pressed:   bool, // left button went down this frame
	down:      bool,
	hot:       [MAX_HOT]rl.Rectangle,
	hot_count: int,
	prev_hot:  [MAX_HOT]rl.Rectangle,
	prev_count: int,
	active_slider: rawptr, // the value being dragged
	// the pad's focus (see the top)
	pad:         bool, // the pad is in hand: focus, not the mouse; its buttons on the HUD
	layout:      input.Layout,
	focus:       int, // the focused widget, by its place in drawing order
	focus_rects: [MAX_FOCUS]rl.Rectangle,
	focus_wide:  [MAX_FOCUS]bool, // takes left and right for itself
	focus_count: int,
	prev_focus:  [MAX_FOCUS]rl.Rectangle,
	prev_wide:   [MAX_FOCUS]bool,
	prev_focus_count: int,
	accept:      bool, // South went down: the focused widget is chosen
	nav_x:       int, // left or right for the focused option row or slider
	runes:     []rune, // every glyph the fonts must hold
	// set by the app from the settings (accessibility)
	hud_size:      f32, // the in-game HUD's size factor
	labels_always: bool, // the skills' names always beside their slots
	reduce_motion: bool, // nothing pulses or breathes
	// the HUD's animations
	dt:            f32,
	skill_reveal:  [content.MAX_SKILLS]f32, // each skill's name sliding out (0..1)
	skill_flash:   [content.MAX_SKILLS]f32, // seconds its name stays out after a change
	skill_state:   [content.MAX_SKILLS]int, // what each slot said last frame (-1: nothing yet)
	tip_reveal:    [3]f32, // the names of the diorama's buttons (Q, E, R)
	place_reveal:  f32, // the action of the place, over Psyche
	place_key:     i18n.Key, // what it says (kept while it fades out)
}

init :: proc(u: ^Ui) {
	// every glyph used by any language, plus printable ASCII
	runes := make([dynamic]rune, 0, 256, context.temp_allocator)
	seen := make(map[rune]bool, 256, context.temp_allocator)
	add :: proc(runes: ^[dynamic]rune, seen: ^map[rune]bool, r: rune) {
		if r >= 32 && !seen[r] {
			seen[r] = true
			append(runes, r)
		}
	}
	for r in rune(32) ..= 126 {
		add(&runes, &seen, r)
	}
	for extra in "«»“”‘’…—–·×‹›àèéìòùÀÈÉÌÒÙ" {
		add(&runes, &seen, extra)
	}
	for l in i18n.Language {
		for k in i18n.Key {
			for r in i18n.tr_in(l, k) {
				add(&runes, &seen, r)
				// labels are also drawn in capitals
				for up in strings.to_upper(utf8.runes_to_string({r}, context.temp_allocator), context.temp_allocator) {
					add(&runes, &seen, up)
				}
			}
		}
	}
	u.runes = make([]rune, len(runes))
	copy(u.runes, runes[:])
	u.scale = 1
	u.hud_size = 1
	for &st in u.skill_state {
		st = -1
	}
	ensure_fonts(u)
}

// (Re)build the font atlases when the UI scale moves to another size step.
@(private)
ensure_fonts :: proc(u: ^Ui) {
	step :: proc(base: f32, scale: f32) -> i32 {
		px := i32(base * scale + 15) / 16 * 16 // multiples of 16 px: few rebuilds
		return clamp(px, 32, 288)
	}
	DATA := [Face][]u8 {
		.Body    = content.FONT_BODY,
		.Semi    = content.FONT_BODY_SEMI,
		.Italic  = content.FONT_BODY_ITALIC,
		.Display = content.FONT_DISPLAY,
	}
	for face in Face {
		want := step(FACE_BASE[face], u.scale)
		if want == u.font_px[face] {
			continue
		}
		if u.font_px[face] != 0 {
			rl.UnloadFont(u.fonts[face])
		}
		u.fonts[face] = load_font(DATA[face], want, u.runes)
		u.font_px[face] = want
	}
}

@(private)
load_font :: proc(data: []u8, size: i32, runes: []rune) -> rl.Font {
	f := rl.LoadFontFromMemory(".ttf", raw_data(data), i32(len(data)), size, raw_data(runes), i32(len(runes)))
	rl.GenTextureMipmaps(&f.texture)
	rl.SetTextureFilter(f.texture, .TRILINEAR)
	return f
}

shutdown :: proc(u: ^Ui) {
	for f in u.fonts {
		rl.UnloadFont(f)
	}
	delete(u.runes)
	u^ = {}
}

// Start of a frame on a canvas of width x height pixels: read the mouse,
// rotate the hot rectangles, follow the UI scale.
begin_frame :: proc(u: ^Ui, width, height: f32) {
	u.width = width
	u.height = height
	// 1080p layout; on very wide or narrow windows the width limits it too
	u.scale = min(height / 1080, width / 1600)
	ensure_fonts(u)
	u.dt = min(rl.GetFrameTime(), 0.1)
	u.mouse = rl.GetMousePosition()
	u.pressed = rl.IsMouseButtonPressed(.LEFT)
	u.down = rl.IsMouseButtonDown(.LEFT)
	if !u.down {
		u.active_slider = nil
	}
	u.prev_hot = u.hot
	u.prev_count = u.hot_count
	u.hot_count = 0
	update_focus(u)
}

// The pad's focus for this frame, from last frame's widgets.
@(private)
update_focus :: proc(u: ^Ui) {
	u.pad = input.using_pad()
	u.layout = input.layout()
	u.prev_focus = u.focus_rects
	u.prev_wide = u.focus_wide
	u.prev_focus_count = u.focus_count
	u.focus_count = 0
	u.nav_x = 0
	u.accept = false
	if !u.pad {
		return
	}
	u.pressed = false
	u.down = false
	// South also closes the cards that wait to be read (no widgets on them)
	u.accept = input.pressed(.South)
	n := u.prev_focus_count
	if n == 0 {
		return
	}
	u.focus = clamp(u.focus, 0, n - 1)
	step := input.nav()
	if u.prev_wide[u.focus] && step.x != 0 {
		u.nav_x = step.x
		step.x = 0
	}
	if step != {} {
		if next := nearest(u.prev_focus[:n], u.focus, step); next != u.focus {
			u.focus = next
			audio.play(.Tap, -22)
		}
	}
}

// The widget nearest to `from` the way `step` points; past the last one, round
// to the far side.
@(private)
nearest :: proc(rects: []rl.Rectangle, from: int, step: [2]int) -> int {
	centre :: proc(r: rl.Rectangle) -> Vec2 {
		return {r.x + r.width * 0.5, r.y + r.height * 0.5}
	}
	d := Vec2{f32(step.x), f32(step.y)}
	c := centre(rects[from])
	best, wrap := -1, -1
	best_score, wrap_score: f32 = 1e30, 1e30
	for r, i in rects {
		if i == from {
			continue
		}
		v := centre(r) - c
		along := v.x * d.x + v.y * d.y
		across := abs(v.x * d.y - v.y * d.x)
		score := along + across * 2.5
		if along > 1 && score < best_score {
			best, best_score = i, score
		} else if along < -1 && across * 2.5 + along < wrap_score {
			wrap, wrap_score = i, across * 2.5 + along
		}
	}
	if best >= 0 {
		return best
	}
	return wrap >= 0 ? wrap : from
}

// A new screen: the focus goes back to its first widget (or `first`).
reset_focus :: proc(u: ^Ui, first := 0) {
	u.focus = first
	u.prev_focus_count = 0
}

// Register a widget that can be chosen at `r` (in drawing order); is it
// hovered: the mouse over it, or the pad's focus on it? `wide`: it takes left
// and right for itself (option rows, sliders).
focusable :: proc(u: ^Ui, r: rl.Rectangle, wide := false) -> bool {
	i := u.focus_count
	if i < MAX_FOCUS {
		u.focus_rects[i] = r
		u.focus_wide[i] = wide
		u.focus_count += 1
	}
	if u.pad {
		return i == u.focus
	}
	if rl.CheckCollisionPointRec(u.mouse, r) {
		u.focus = i // the pad, picked up again, starts from here
		return true
	}
	return false
}

// A hovered widget chosen this frame: clicked, or South on the pad.
activated :: proc(u: ^Ui, hover: bool) -> bool {
	if !hover {
		return false
	}
	if u.pad && u.accept {
		input.consume(.South)
		u.accept = false
		return true
	}
	return u.pressed
}

// Is the mouse over `r`? Never while the pad is in hand (the cursor is hidden
// where it was left).
mouse_over :: proc(u: ^Ui, r: rl.Rectangle) -> bool {
	return !u.pad && rl.CheckCollisionPointRec(u.mouse, r)
}

// The soft band behind the option row the pad's focus is on.
focus_band :: proc(u: ^Ui, r: rl.Rectangle) {
	s := u.scale
	rl.DrawRectangleRec(r, fade(GOLD, 0.07))
	rl.DrawRectangleRec({r.x, r.y, max(3 * s, 1), r.height}, BRIGHT)
}

// Is the mouse over a widget drawn last frame?
over_ui :: proc(u: ^Ui) -> bool {
	for r in u.prev_hot[:u.prev_count] {
		if rl.CheckCollisionPointRec(u.mouse, r) {
			return true
		}
	}
	return u.active_slider != nil
}

@(private)
add_hot :: proc(u: ^Ui, r: rl.Rectangle) {
	if u.hot_count < MAX_HOT {
		u.hot[u.hot_count] = r
		u.hot_count += 1
	}
}

// --- text --------------------------------------------------------------------------

Align :: enum u8 {
	Center,
	Left,
	Right,
}

Style :: struct {
	size:   f32, // in 1080p units
	color:  rl.Color,
	face:   Face,
	shadow: bool, // a soft dark halo, for legibility over the sky
	glow:   bool, // a warm halo (titles)
	track:  f32, // extra letter spacing, in ems (labels in capitals)
}

@(private)
spacing :: proc(size: f32, st: Style) -> f32 {
	return size * (0.02 + st.track)
}

measure :: proc(u: ^Ui, text: string, st: Style) -> Vec2 {
	size := st.size * u.scale
	cs := strings.clone_to_cstring(text, context.temp_allocator)
	return rl.MeasureTextEx(u.fonts[st.face], cs, size, spacing(size, st))
}

fade :: proc(c: rl.Color, alpha: f32) -> rl.Color {
	out := c
	out.a = u8(f32(c.a) * clamp(alpha, 0, 1))
	return out
}

// One line of text; `pos` is the anchor (top centre, top left or top right).
text :: proc(u: ^Ui, s: string, pos: Vec2, st: Style, align := Align.Center, alpha: f32 = 1) {
	if alpha <= 0.003 || s == "" {
		return
	}
	size := st.size * u.scale
	font := u.fonts[st.face]
	sp := spacing(size, st)
	cs := strings.clone_to_cstring(s, context.temp_allocator)
	w := rl.MeasureTextEx(font, cs, size, sp).x
	p := pos
	switch align {
	case .Center: p.x -= w * 0.5
	case .Left:
	case .Right: p.x -= w
	}
	if st.glow {
		// a lamp's halo: rings of faint copies around the letters
		for ring in 1 ..= 3 {
			r := f32(ring) * size * 0.035
			col := fade(HALO, alpha * 0.045 / f32(ring))
			for k in 0 ..< 12 {
				ang := f32(k) * math.TAU / 12 + f32(ring) * 0.26
				rl.DrawTextEx(font, cs, p + {math.cos(ang), math.sin(ang)} * r, size, sp, col)
			}
		}
	}
	if st.shadow {
		o := max(1.5 * u.scale, 1)
		sh := fade(SHADOW, alpha * 0.35)
		for d in ([4]Vec2{{-o, 0}, {o, 0}, {0, -o}, {0, o}}) {
			rl.DrawTextEx(font, cs, p + d + {0, 2 * u.scale}, size, sp, sh)
		}
		rl.DrawTextEx(font, cs, p + {0, 2 * u.scale}, size, sp, fade(SHADOW, alpha * 0.6))
	}
	rl.DrawTextEx(font, cs, p, size, sp, fade(st.color, alpha))
}

// A label in spaced capitals ("ATTO I").
caps :: proc(s: string) -> string {
	return strings.to_upper(s, context.temp_allocator)
}

// Split text into lines no wider than max_width (screen px); '\n' forces a break.
wrap :: proc(u: ^Ui, s: string, st: Style, max_width: f32) -> []string {
	lines := make([dynamic]string, 0, 8, context.temp_allocator)
	rest := s
	for paragraph in strings.split_lines_iterator(&rest) {
		start := 0
		last_space := -1
		i := 0
		for i < len(paragraph) {
			r, n := utf8.decode_rune_in_string(paragraph[i:])
			if r == ' ' {
				if measure(u, paragraph[start:i], st).x > max_width && last_space > start {
					append(&lines, paragraph[start:last_space])
					start = last_space + 1
				}
				last_space = i
			}
			i += n
		}
		if measure(u, paragraph[start:], st).x > max_width && last_space > start {
			append(&lines, paragraph[start:last_space])
			start = last_space + 1
		}
		append(&lines, paragraph[start:])
	}
	return lines[:]
}

// Wrapped text block; returns its height. `pos` is the top centre (or the
// top left / top right corner with another alignment).
paragraph :: proc(u: ^Ui, s: string, pos: Vec2, st: Style, max_width: f32, alpha: f32 = 1, line_gap: f32 = 1.25, align := Align.Center) -> f32 {
	lines := wrap(u, s, st, max_width)
	step := st.size * u.scale * line_gap
	for line, i in lines {
		text(u, line, pos + {0, f32(i) * step}, st, align, alpha)
	}
	return f32(len(lines)) * step
}

block_height :: proc(u: ^Ui, s: string, st: Style, max_width: f32, line_gap: f32 = 1.25) -> f32 {
	return f32(len(wrap(u, s, st, max_width))) * st.size * u.scale * line_gap
}

// --- ornaments -----------------------------------------------------------------------

// A small diamond (filled or drawn); also the mark of a fragment.
diamond :: proc(u: ^Ui, c: Vec2, radius: f32, col: rl.Color, filled: bool) {
	pts := [4]Vec2{c + {0, -radius}, c + {radius * 0.7, 0}, c + {0, radius}, c + {-radius * 0.7, 0}}
	if filled {
		tri(pts[0], pts[1], pts[2], col)
		tri(pts[0], pts[2], pts[3], col)
		return
	}
	for i in 0 ..< 4 {
		rl.DrawLineEx(pts[i], pts[(i + 1) % 4], max(1.5 * u.scale, 1), col)
	}
}

// A lamp's glow around a point (a diamond lit, a bead of oil).
glow_dot :: proc(c: Vec2, radius: f32, col: rl.Color, alpha: f32) {
	inner := fade(col, alpha * 0.35)
	outer := fade(col, 0)
	rl.DrawCircleGradient(c, radius * 3, inner, outer)
}

// ── ◆ ──: a rule with a diamond in the middle, centred on `c`.
ornament :: proc(u: ^Ui, c: Vec2, half: f32, alpha: f32 = 1) {
	s := u.scale
	th := max(1.2 * s, 1)
	gap := 14 * s
	rl.DrawRectangleRec({c.x - half, c.y - th * 0.5, half - gap, th}, fade(GOLD, 0.6 * alpha))
	rl.DrawRectangleRec({c.x + gap, c.y - th * 0.5, half - gap, th}, fade(GOLD, 0.6 * alpha))
	diamond(u, c, 7 * s, fade(GOLD, alpha), true)
}

// ─── ATTO I ───: a label in spaced capitals between two rules; `pos` is the top centre.
rule_label :: proc(u: ^Ui, label: string, pos: Vec2, size: f32, line: f32, alpha: f32 = 1) {
	s := u.scale
	st := Style{size = size, color = GOLD, face = .Semi, track = 0.18, shadow = true}
	m := measure(u, label, st)
	text(u, label, pos, st, .Center, alpha)
	y := pos.y + m.y * 0.52
	th := max(1.2 * s, 1)
	gap := 18 * s
	rl.DrawRectangleRec({pos.x - m.x * 0.5 - gap - line, y, line, th}, fade(GOLD, 0.55 * alpha))
	rl.DrawRectangleRec({pos.x + m.x * 0.5 + gap, y, line, th}, fade(GOLD, 0.55 * alpha))
}

// A square key cap ("Esc") with its top left corner at `pos`; returns its
// width. `k` is the scale (default: the UI's); `lit` fills it with gold.
key_cap :: proc(u: ^Ui, key: string, pos: Vec2, alpha: f32 = 1, k: f32 = 0, lit := false) -> f32 {
	s := k > 0 ? k : u.scale
	// Cormorant's figures are old style (small): a key's number is set larger
	big := len(key) == 1 && key[0] >= '0' && key[0] <= '9'
	st := Style{size = (big ? 26 : 21) * s / u.scale, color = lit ? rl.Color{26, 18, 8, 255} : TITLE, face = .Semi}
	m := measure(u, key, st)
	r := rl.Rectangle{pos.x, pos.y, max(m.x + 14 * s, 28 * s), 28 * s}
	rl.DrawRectangleRec(r, lit ? fade(BRIGHT, alpha) : fade({21, 18, 29, 255}, 0.95 * alpha))
	rl.DrawRectangleLinesEx(r, max(1.5 * s, 1), lit ? fade(BRIGHT, alpha) : fade(TEXT, 0.8 * alpha))
	text(u, key, {r.x + r.width * 0.5, r.y + (r.height - m.y) * 0.5 - s}, st, .Center, alpha)
	return r.width
}

// A pad's button, the size of a key cap, its top left corner at `pos`:
// the face buttons round (a letter, or the PlayStation's marks), the
// shoulders and Start rounded tabs. Returns its width; `k` and `lit` as for
// `key_cap`.
pad_button :: proc(u: ^Ui, b: input.Button, pos: Vec2, alpha: f32 = 1, k: f32 = 0, lit := false) -> f32 {
	s := k > 0 ? k : u.scale
	h := 28 * s
	fill := lit ? fade(BRIGHT, alpha) : fade({21, 18, 29, 255}, 0.95 * alpha)
	ink := lit ? fade({26, 18, 8, 255}, alpha) : fade(TITLE, alpha)
	edge := lit ? fade(BRIGHT, alpha) : fade(TEXT, 0.8 * alpha)
	th := max(1.8 * s, 1)
	st := Style{size = 19 * s / u.scale, color = lit ? rl.Color{26, 18, 8, 255} : TITLE, face = .Semi}
	switch b {
	case .South, .East, .West, .North:
		c := pos + {h * 0.5, h * 0.5}
		r := h * 0.5
		rl.DrawCircleV(c, r, fill)
		rl.DrawRing(c, r - th, r, 0, 360, 32, edge)
		if u.layout == .PlayStation {
			m := 5.5 * s
			lw := max(1.8 * s, 1)
			switch b {
			case .South:
				rl.DrawLineEx(c - {m, m}, c + {m, m}, lw, ink)
				rl.DrawLineEx(c + {-m, m}, c + {m, -m}, lw, ink)
			case .East:
				rl.DrawRing(c, m - lw * 0.5, m + lw * 0.5, 0, 360, 24, ink)
			case .West:
				rl.DrawRectangleLinesEx({c.x - m, c.y - m, 2 * m, 2 * m}, lw, ink)
			case .North:
				a, bb, cc := c + {0, -m * 1.1}, c + {m * 1.05, m * 0.75}, c + {-m * 1.05, m * 0.75}
				rl.DrawLineEx(a, bb, lw, ink)
				rl.DrawLineEx(bb, cc, lw, ink)
				rl.DrawLineEx(cc, a, lw, ink)
			case .LB, .RB, .LT, .RT, .Start, .Select, .Up, .Down, .Left, .Right:
			}
		} else {
			names := PAD_LETTERS[u.layout == .Nintendo ? 1 : 0]
			letter := names[b]
			st.size = 20 * s / u.scale
			m := measure(u, letter, st)
			text(u, letter, {c.x, c.y - m.y * 0.5 - s}, st, .Center, alpha)
		}
		return h
	case .LB, .RB, .LT, .RT:
		label := PAD_SHOULDER[u.layout][b]
		m := measure(u, label, st)
		r := rl.Rectangle{pos.x, pos.y + 2 * s, max(m.x + 16 * s, 34 * s), h - 4 * s}
		rl.DrawRectangleRounded(r, 0.5, 8, fill)
		rl.DrawRectangleRoundedLinesEx(r, 0.5, 8, th, edge)
		text(u, label, {r.x + r.width * 0.5, r.y + (r.height - m.y) * 0.5 - s}, st, .Center, alpha)
		return r.width
	case .Start, .Select:
		r := rl.Rectangle{pos.x, pos.y + 3 * s, 36 * s, h - 6 * s}
		rl.DrawRectangleRounded(r, 0.6, 8, fill)
		rl.DrawRectangleRoundedLinesEx(r, 0.6, 8, th, edge)
		c := Vec2{r.x + r.width * 0.5, r.y + r.height * 0.5}
		for n in -1 ..= 1 {
			rl.DrawRectangleRec({c.x - 7 * s, c.y + f32(n) * 4.5 * s - 0.8 * s, 14 * s, max(1.6 * s, 1)}, ink)
		}
		return r.width
	case .Up, .Down, .Left, .Right:
		// a d-pad, the arm pressed lit
		c := pos + {h * 0.5, h * 0.5}
		arm := 4.5 * s
		long := 12 * s
		rl.DrawRectangleRec({c.x - arm, c.y - long, 2 * arm, 2 * long}, fade(TEXT, 0.75 * alpha))
		rl.DrawRectangleRec({c.x - long, c.y - arm, 2 * long, 2 * arm}, fade(TEXT, 0.75 * alpha))
		d: Vec2
		#partial switch b {
		case .Up: d = {0, -1}
		case .Down: d = {0, 1}
		case .Left: d = {-1, 0}
		case .Right: d = {1, 0}
		}
		hit := c + d * long * 0.6
		rl.DrawRectangleRec({hit.x - arm * 0.8, hit.y - arm * 0.8, arm * 1.6, arm * 1.6}, fade(BRIGHT, alpha))
		return h
	}
	return h
}

// The width `pad_button` will take.
pad_button_width :: proc(u: ^Ui, b: input.Button, k: f32 = 0) -> f32 {
	s := k > 0 ? k : u.scale
	#partial switch b {
	case .LB, .RB, .LT, .RT:
		m := measure(u, PAD_SHOULDER[u.layout][b], {size = 19 * s / u.scale, face = .Semi})
		return max(m.x + 16 * s, 34 * s)
	case .Start, .Select:
		return 36 * s
	}
	return 28 * s
}

// The control of an action, for the device in hand: a key cap or a pad's button.
control :: proc(u: ^Ui, key: string, b: input.Button, pos: Vec2, alpha: f32 = 1, k: f32 = 0, lit := false) -> f32 {
	return u.pad ? pad_button(u, b, pos, alpha, k, lit) : key_cap(u, key, pos, alpha, k, lit)
}

@(private)
PAD_LETTERS := [2][input.Button]string {
	#partial {.South = "A", .East = "B", .West = "X", .North = "Y"}, // Xbox
	#partial {.South = "B", .East = "A", .West = "Y", .North = "X"}, // Nintendo, by place
}

@(private)
PAD_SHOULDER := [input.Layout][input.Button]string {
	.Xbox        = #partial {.LB = "LB", .RB = "RB", .LT = "LT", .RT = "RT"},
	.PlayStation = #partial {.LB = "L1", .RB = "R1", .LT = "L2", .RT = "R2"},
	.Nintendo    = #partial {.LB = "L", .RB = "R", .LT = "ZL", .RT = "ZR"},
}

// Four small gold corners around `r`: the frame of every card.
corner_frame :: proc(u: ^Ui, r: rl.Rectangle, alpha: f32, k: f32 = 0, col: rl.Color = GOLD) {
	s := k > 0 ? k : u.scale
	l := 12 * s
	t := max(1.5 * s, 1)
	c := fade(col, alpha)
	rl.DrawRectangleRec({r.x, r.y, l, t}, c)
	rl.DrawRectangleRec({r.x, r.y, t, l}, c)
	rl.DrawRectangleRec({r.x + r.width - l, r.y, l, t}, c)
	rl.DrawRectangleRec({r.x + r.width - t, r.y, t, l}, c)
	rl.DrawRectangleRec({r.x, r.y + r.height - t, l, t}, c)
	rl.DrawRectangleRec({r.x, r.y + r.height - l, t, l}, c)
	rl.DrawRectangleRec({r.x + r.width - l, r.y + r.height - t, l, t}, c)
	rl.DrawRectangleRec({r.x + r.width - t, r.y + r.height - l, t, l}, c)
}

// A card: a square of dark warm glass, framed by its gold corners and a faint
// hairline. `edge` is how bright the hairline is.
warm_card :: proc(u: ^Ui, r: rl.Rectangle, alpha: f32, edge: f32 = 0.3, k: f32 = 0) {
	s := k > 0 ? k : u.scale
	rl.DrawRectangleRec(r, fade({13, 11, 20, 255}, 0.82 * alpha))
	rl.DrawRectangleLinesEx(r, max(s, 1), fade(GOLD, edge * 0.5 * alpha))
	corner_frame(u, r, alpha, s)
}

// Dark glass: the picture under `r` frosted, darkened and tinted night blue,
// with a hairline on its right edge and a soft shadow beyond it.
glass_panel :: proc(u: ^Ui, r: rl.Rectangle) {
	s := u.scale
	if u.has_glass {
		tw, th := f32(u.glass.width), f32(u.glass.height)
		kx, ky := tw / u.width, th / u.height
		src := rl.Rectangle{r.x * kx, (u.height - r.y - r.height) * ky, r.width * kx, -r.height * ky}
		rl.DrawTexturePro(u.glass, src, r, {}, 0, rl.WHITE)
		rl.DrawRectangleRec(r, fade(NIGHT, 0.52))
	} else {
		rl.DrawRectangleRec(r, fade(NIGHT, 0.9))
	}
	// the light catching the glass at the top, the edge, the shadow it casts
	rl.DrawRectangleGradientV(i32(r.x), i32(r.y), i32(r.width), i32(220 * s), {255, 255, 255, 10}, {255, 255, 255, 0})
	right := r.x + r.width
	rl.DrawRectangleRec({right - max(s, 1), r.y, max(s, 1), r.height}, {255, 255, 255, 34})
	rl.DrawRectangleGradientH(i32(right), i32(r.y), i32(70 * s), i32(r.height), {0, 0, 0, 90}, {0, 0, 0, 0})
}

// A hairline across a panel.
hairline :: proc(u: ^Ui, x, y, w: f32, col: rl.Color = {255, 255, 255, 20}) {
	rl.DrawRectangleRec({x, y, w, max(u.scale, 1)}, col)
}

// --- widgets -------------------------------------------------------------------------

// A text button centred on `center`; returns true when clicked.
// `focus`: the pad's focus can land on it (false where the pad has its own
// buttons for it).
button :: proc(u: ^Ui, label: string, center: Vec2, size: f32, alpha: f32 = 1, enabled := true, focus := true) -> bool {
	st := Style{size = size, color = TEXT, face = .Semi, shadow = true}
	m := measure(u, label, st)
	pad := Vec2{22, 6} * u.scale
	r := rl.Rectangle{center.x - m.x * 0.5 - pad.x, center.y - m.y * 0.5 - pad.y, m.x + pad.x * 2, m.y + pad.y * 2}
	hover := false
	if alpha > 0.5 {
		add_hot(u, r)
		hover = (focus ? focusable(u, r) : mouse_over(u, r)) && enabled
	}
	if hover {
		st.color = u.down ? TITLE : BRIGHT
		diamond(u, {r.x + 4 * u.scale, center.y}, 5 * u.scale, fade(BRIGHT, alpha), true)
		diamond(u, {r.x + r.width - 4 * u.scale, center.y}, 5 * u.scale, fade(BRIGHT, alpha), true)
	}
	if !enabled {
		st.color = fade(DIM, 0.4)
	}
	text(u, label, {center.x, center.y - m.y * 0.5}, st, .Center, alpha)
	if activated(u, hover) {
		audio.play(.Tap, -14)
		return true
	}
	return false
}

// An entry of a menu in the lamplight: a diamond, then the label; `pos` is
// its left end, on the line's middle. The main entry is lit; hovering lights
// any. Returns true when clicked.
menu_item :: proc(u: ^Ui, label: string, pos: Vec2, size: f32, main := false, alpha: f32 = 1) -> bool {
	s := u.scale
	st := Style{size = size, color = TEXT, face = main ? .Semi : .Body, shadow = true}
	m := measure(u, label, st)
	r := rl.Rectangle{pos.x - 12 * s, pos.y - m.y * 0.5 - 6 * s, m.x + 52 * s, m.y + 12 * s}
	hover := false
	if alpha > 0.5 {
		add_hot(u, r)
		hover = focusable(u, r)
	}
	// with the pad, only the focus is lit
	lit := hover || (main && !u.pad)
	c := Vec2{pos.x + 6 * s, pos.y}
	if lit {
		glow_dot(c, 6 * s, {255, 176, 77, 255}, alpha)
		diamond(u, c, 7 * s, fade(BRIGHT, alpha), true)
		st.color = BRIGHT
	} else {
		diamond(u, c, 7 * s, fade(GOLD, 0.55 * alpha), false)
	}
	text(u, label, {pos.x + 32 * s, pos.y - m.y * 0.5}, st, .Left, alpha)
	if activated(u, hover) {
		audio.play(.Tap, -14)
		return true
	}
	return false
}

ROW_SIZE :: 28

// "Label ......  ‹ value ›": clicking the value or the arrows steps through
// the options. Returns -1, 0 or +1.
option_row :: proc(u: ^Ui, label, value: string, y, left, right: f32, enabled := true) -> int {
	s := u.scale
	a: f32 = enabled ? 1 : 0.45
	text(u, label, {left, y}, {size = ROW_SIZE, color = TEXT}, .Left, a)
	vst := Style{size = ROW_SIZE - 1, color = BRIGHT, face = .Semi}
	vw := measure(u, value, vst).x
	cx := right - 150 * s
	text(u, value, {cx, y}, vst, .Center, a)
	h := ROW_SIZE * s * 1.3
	row := rl.Rectangle{left - 18 * s, y - 12 * s, right - left + 30 * s, h + 18 * s}
	focused := focusable(u, row, true) && u.pad
	if focused {
		focus_band(u, row)
	}
	step := 0
	if focused && enabled {
		step = u.nav_x
		if activated(u, true) {
			step = 1
		}
	}
	arrows := [2]struct {
		label: string,
		x:     f32,
		dir:   int,
	}{{"‹", cx - vw * 0.5 - 34 * s, -1}, {"›", cx + vw * 0.5 + 34 * s, 1}}
	for ar in arrows {
		r := rl.Rectangle{ar.x - 22 * s, y - 4 * s, 44 * s, h}
		add_hot(u, r)
		hover := enabled && (mouse_over(u, r) || (focused && u.nav_x == ar.dir))
		text(u, ar.label, {ar.x, y - 6 * s}, {size = 34, color = hover || focused ? BRIGHT : fade(GOLD, 0.7), face = .Semi}, .Center, enabled ? 1 : 0.3)
		if hover && u.pressed {
			step = ar.dir
		}
	}
	vr := rl.Rectangle{cx - vw * 0.5 - 10 * s, y - 4 * s, vw + 20 * s, h}
	add_hot(u, vr)
	if enabled && u.pressed && mouse_over(u, vr) {
		step = 1
	}
	if step != 0 {
		audio.play(.Tap, -14)
	}
	return step
}

// A horizontal slider for a 0..1 value; returns true while it changes.
slider :: proc(u: ^Ui, label: string, value: ^f32, y, left, right: f32) -> bool {
	s := u.scale
	text(u, label, {left, y}, {size = ROW_SIZE, color = TEXT}, .Left)
	w := 250 * s
	cx := right - 150 * s
	bar := rl.Rectangle{cx - w * 0.5, y + 19 * s, w, 4 * s}
	hit := rl.Rectangle{bar.x - 12 * s, y - 4 * s, bar.width + 24 * s, 44 * s}
	add_hot(u, hit)
	row := rl.Rectangle{left - 18 * s, y - 12 * s, right - left + 30 * s, ROW_SIZE * s * 1.3 + 18 * s}
	focused := focusable(u, row, true) && u.pad
	if focused {
		focus_band(u, row)
	}
	if u.pressed && mouse_over(u, hit) {
		u.active_slider = value
	}
	changed := false
	if focused && u.nav_x != 0 {
		v := clamp(math.round(value^ * 20 + f32(u.nav_x)) / 20, 0, 1)
		if abs(v - value^) > 0.0001 {
			value^ = v
			changed = true
			audio.play(.Tap, -20)
		}
	}
	if u.active_slider == value && u.down {
		v := clamp((u.mouse.x - bar.x) / bar.width, 0, 1)
		if abs(v - value^) > 0.0001 {
			value^ = v
			changed = true
		}
	}
	rl.DrawRectangleRec(bar, {255, 255, 255, 40})
	rl.DrawRectangleRec({bar.x, bar.y, max(bar.width * value^, bar.height), bar.height}, GOLD)
	knob := Vec2{bar.x + bar.width * value^, bar.y + bar.height * 0.5}
	glow_dot(knob, 9 * s, GOLD, 1)
	rl.DrawRectangleRec({knob.x - 8 * s, knob.y - 11 * s, 16 * s, 22 * s}, {251, 231, 188, 255})
	return changed
}

tri :: proc(a, b, c: Vec2, col: rl.Color) {
	cross := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
	if cross < 0 {
		rl.DrawTriangle(a, b, c, col)
	} else {
		rl.DrawTriangle(a, c, b, col)
	}
}
