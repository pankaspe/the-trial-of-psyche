// Immediate-mode UI: fonts, text, buttons, option rows and sliders.
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

TEXT :: rl.Color{230, 230, 255, 255}
DIM :: rl.Color{158, 168, 217, 255}
GOLD :: rl.Color{255, 209, 128, 255}
FAINT :: rl.Color{128, 133, 179, 204}
SHADOW :: rl.Color{0, 0, 13, 204}

// Font atlases are rebuilt for the UI scale (1080p sizes below): text stays
// crisp from 720p to 4K. The largest text (the title) is drawn from the atlas
// with little or no upscaling, everything else is mipmapped down.
FONT_SIZE :: 112
ITALIC_SIZE :: 56
MAX_HOT :: 48

Ui :: struct {
	font:      rl.Font,
	italic:    rl.Font,
	scale:     f32, // screen height / 1080
	width:     f32,
	height:    f32,
	settings_tab: Settings_Tab, // the page of the settings panel on screen
	toast_visible: bool, // an achievement notice is in the top left corner
	mouse:     Vec2,
	pressed:   bool, // left button went down this frame
	down:      bool,
	hot:       [MAX_HOT]rl.Rectangle,
	hot_count: int,
	prev_hot:  [MAX_HOT]rl.Rectangle,
	prev_count: int,
	active_slider: rawptr, // the value being dragged
	runes:     []rune, // every glyph the fonts must hold
	font_px:   i32, // atlas sizes currently loaded
	italic_px: i32,
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
			}
		}
	}
	u.runes = make([]rune, len(runes))
	copy(u.runes, runes[:])
	u.scale = 1
	ensure_fonts(u)
}

// (Re)build the font atlases when the UI scale moves to another size step.
@(private)
ensure_fonts :: proc(u: ^Ui) {
	step :: proc(base: f32, scale: f32) -> i32 {
		px := i32(base * scale + 15) / 16 * 16 // multiples of 16 px: few rebuilds
		return clamp(px, 32, 256)
	}
	want, want_italic := step(FONT_SIZE, u.scale), step(ITALIC_SIZE, u.scale)
	if want != u.font_px {
		if u.font_px != 0 {
			rl.UnloadFont(u.font)
		}
		u.font = load_font(content.FONT_SERIF, want, u.runes)
		u.font_px = want
	}
	if want_italic != u.italic_px {
		if u.italic_px != 0 {
			rl.UnloadFont(u.italic)
		}
		u.italic = load_font(content.FONT_SERIF_ITALIC, want_italic, u.runes)
		u.italic_px = want_italic
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
	rl.UnloadFont(u.font)
	rl.UnloadFont(u.italic)
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
	italic: bool,
	shadow: bool,
}

@(private)
font_of :: proc(u: ^Ui, st: Style) -> rl.Font {
	return st.italic ? u.italic : u.font
}

@(private)
spacing :: proc(size: f32) -> f32 {
	return size * 0.02
}

measure :: proc(u: ^Ui, text: string, st: Style) -> Vec2 {
	size := st.size * u.scale
	cs := strings.clone_to_cstring(text, context.temp_allocator)
	return rl.MeasureTextEx(font_of(u, st), cs, size, spacing(size))
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
	font := font_of(u, st)
	cs := strings.clone_to_cstring(s, context.temp_allocator)
	w := rl.MeasureTextEx(font, cs, size, spacing(size)).x
	p := pos
	switch align {
	case .Center: p.x -= w * 0.5
	case .Left:
	case .Right: p.x -= w
	}
	if st.shadow {
		// a soft dark halo under the letters, for legibility over the sky
		o := max(1.5 * u.scale, 1)
		sh := fade(SHADOW, alpha * 0.35)
		for d in ([4]Vec2{{-o, 0}, {o, 0}, {0, -o}, {0, o}}) {
			rl.DrawTextEx(font, cs, p + d + {0, 2 * u.scale}, size, spacing(size), sh)
		}
		rl.DrawTextEx(font, cs, p + {0, 2 * u.scale}, size, spacing(size), fade(SHADOW, alpha * 0.6))
	}
	rl.DrawTextEx(font, cs, p, size, spacing(size), fade(st.color, alpha))
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

// Wrapped, centred text block; returns its height. `pos` is the top centre.
paragraph :: proc(u: ^Ui, s: string, pos: Vec2, st: Style, max_width: f32, alpha: f32 = 1, line_gap: f32 = 1.25) -> f32 {
	lines := wrap(u, s, st, max_width)
	step := st.size * u.scale * line_gap
	for line, i in lines {
		text(u, line, pos + {0, f32(i) * step}, st, .Center, alpha)
	}
	return f32(len(lines)) * step
}

block_height :: proc(u: ^Ui, s: string, st: Style, max_width: f32, line_gap: f32 = 1.25) -> f32 {
	return f32(len(wrap(u, s, st, max_width))) * st.size * u.scale * line_gap
}

// --- widgets -------------------------------------------------------------------------

// A text button centred on `center`; returns true when clicked.
button :: proc(u: ^Ui, label: string, center: Vec2, size: f32, alpha: f32 = 1, enabled := true) -> bool {
	st := Style{size = size, color = DIM, shadow = true}
	m := measure(u, label, st)
	pad := Vec2{22, 6} * u.scale
	r := rl.Rectangle{center.x - m.x * 0.5 - pad.x, center.y - m.y * 0.5 - pad.y, m.x + pad.x * 2, m.y + pad.y * 2}
	hover := enabled && alpha > 0.5 && rl.CheckCollisionPointRec(u.mouse, r)
	if alpha > 0.5 {
		add_hot(u, r)
	}
	if hover {
		rl.DrawRectangleRec(r, fade({26, 26, 64, 90}, alpha))
		rl.DrawRectangleRec({r.x, r.y + r.height - max(u.scale, 1), r.width, max(u.scale, 1)}, fade({255, 209, 128, 128}, alpha))
		st.color = u.down ? rl.Color{255, 242, 204, 255} : GOLD
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

// "Label ......  < value >": clicking the value or the arrows steps through
// the options. Returns -1, 0 or +1.
option_row :: proc(u: ^Ui, label, value: string, y, left, right: f32, enabled := true) -> int {
	st := Style{size = 26, color = TEXT, shadow = true}
	text(u, label, {left, y}, st, .Left, enabled ? 1 : 0.45)
	vst := Style{size = 26, color = GOLD, shadow = true}
	vw := measure(u, value, vst).x
	cx := right - 170 * u.scale
	text(u, value, {cx, y}, vst, .Center, enabled ? 1 : 0.45)
	h := 26 * u.scale * 1.3
	step := 0
	arrows := [2]struct {
		label: string,
		x:     f32,
		dir:   int,
	}{{"‹", cx - vw * 0.5 - 40 * u.scale, -1}, {"›", cx + vw * 0.5 + 40 * u.scale, 1}}
	for a in arrows {
		r := rl.Rectangle{a.x - 22 * u.scale, y - 4 * u.scale, 44 * u.scale, h}
		add_hot(u, r)
		hover := enabled && rl.CheckCollisionPointRec(u.mouse, r)
		text(u, a.label, {a.x, y - 9 * u.scale}, {size = 38, color = hover ? GOLD : DIM, shadow = true}, .Center, enabled ? 1 : 0.3)
		if hover && u.pressed {
			step = a.dir
		}
	}
	vr := rl.Rectangle{cx - vw * 0.5 - 10 * u.scale, y - 4 * u.scale, vw + 20 * u.scale, h}
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
	st := Style{size = 26, color = TEXT, shadow = true}
	text(u, label, {left, y}, st, .Left)
	w := 280 * u.scale
	cx := right - 170 * u.scale
	bar := rl.Rectangle{cx - w * 0.5, y + 16 * u.scale, w, 6 * u.scale}
	hit := rl.Rectangle{bar.x - 10 * u.scale, y - 4 * u.scale, bar.width + 20 * u.scale, 40 * u.scale}
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
	rl.DrawRectangleRec(bar, {38, 38, 77, 180})
	rl.DrawRectangleRec({bar.x, bar.y, bar.width * value^, bar.height}, {255, 179, 77, 230})
	rl.DrawCircleV({bar.x + bar.width * value^, bar.y + bar.height * 0.5}, 9 * u.scale, GOLD)
	return changed
}

// A round turn button with a curved arrow (step -1: anticlockwise).
turn_button :: proc(u: ^Ui, center: Vec2, step: int, alpha: f32 = 1) -> bool {
	radius := 26 * u.scale
	r := rl.Rectangle{center.x - radius * 1.3, center.y - radius * 1.3, radius * 2.6, radius * 2.6}
	add_hot(u, r)
	hover := rl.CheckCollisionPointRec(u.mouse, r)
	col := fade(hover ? GOLD : DIM, alpha)
	if hover {
		rl.DrawCircleV(center, radius * 1.25, fade({26, 26, 64, 90}, alpha))
	}
	thick := 3.5 * u.scale
	// an open ring (gap at the top); the head sits at the end the arrow runs
	// toward: top right for anticlockwise, top left for clockwise
	rl.DrawRing(center, radius - thick, radius, -60, 240, 32, col)
	head: f32 = (step < 0 ? -60 : 240) * math.PI / 180
	dir: f32 = step < 0 ? -1 : 1
	normal := Vec2{math.cos(head), math.sin(head)}
	tip := center + normal * (radius - thick * 0.5)
	tangent := Vec2{-math.sin(head), math.cos(head)} * dir
	h := 11 * u.scale
	a := tip + tangent * h
	b := tip + normal * h * 0.75
	c := tip - normal * h * 0.75
	tri(a, b, c, col)
	if hover && u.pressed {
		audio.play(.Tap, -10)
		return true
	}
	return false
}

tri :: proc(a, b, c: Vec2, col: rl.Color) {
	cross := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
	if cross < 0 {
		rl.DrawTriangle(a, b, c, col)
	} else {
		rl.DrawTriangle(a, c, b, col)
	}
}
