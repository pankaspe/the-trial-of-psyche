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
package ui

import "core:math"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"

import "../audio"
import "../content"
import "../i18n"
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
button :: proc(u: ^Ui, label: string, center: Vec2, size: f32, alpha: f32 = 1, enabled := true) -> bool {
	st := Style{size = size, color = TEXT, face = .Semi, shadow = true}
	m := measure(u, label, st)
	pad := Vec2{22, 6} * u.scale
	r := rl.Rectangle{center.x - m.x * 0.5 - pad.x, center.y - m.y * 0.5 - pad.y, m.x + pad.x * 2, m.y + pad.y * 2}
	hover := enabled && alpha > 0.5 && rl.CheckCollisionPointRec(u.mouse, r)
	if alpha > 0.5 {
		add_hot(u, r)
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
	if hover && u.pressed {
		audio.play(.Tap, -10)
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
	hover := alpha > 0.5 && rl.CheckCollisionPointRec(u.mouse, r)
	if alpha > 0.5 {
		add_hot(u, r)
	}
	lit := main || hover
	c := Vec2{pos.x + 6 * s, pos.y}
	if lit {
		glow_dot(c, 6 * s, {255, 176, 77, 255}, alpha)
		diamond(u, c, 7 * s, fade(BRIGHT, alpha), true)
		st.color = BRIGHT
	} else {
		diamond(u, c, 7 * s, fade(GOLD, 0.55 * alpha), false)
	}
	text(u, label, {pos.x + 32 * s, pos.y - m.y * 0.5}, st, .Left, alpha)
	if hover && u.pressed {
		audio.play(.Tap, -10)
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
	step := 0
	arrows := [2]struct {
		label: string,
		x:     f32,
		dir:   int,
	}{{"‹", cx - vw * 0.5 - 34 * s, -1}, {"›", cx + vw * 0.5 + 34 * s, 1}}
	for ar in arrows {
		r := rl.Rectangle{ar.x - 22 * s, y - 4 * s, 44 * s, h}
		add_hot(u, r)
		hover := enabled && rl.CheckCollisionPointRec(u.mouse, r)
		text(u, ar.label, {ar.x, y - 6 * s}, {size = 34, color = hover ? BRIGHT : fade(GOLD, 0.7), face = .Semi}, .Center, enabled ? 1 : 0.3)
		if hover && u.pressed {
			step = ar.dir
		}
	}
	vr := rl.Rectangle{cx - vw * 0.5 - 10 * s, y - 4 * s, vw + 20 * s, h}
	add_hot(u, vr)
	if enabled && u.pressed && rl.CheckCollisionPointRec(u.mouse, vr) {
		step = 1
	}
	if step != 0 {
		audio.play(.Tap, -10)
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
	if u.pressed && rl.CheckCollisionPointRec(u.mouse, hit) {
		u.active_slider = value
	}
	changed := false
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
