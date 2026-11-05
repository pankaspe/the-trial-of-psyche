// The credits, after the wedding: the end of the tale, then who made the game
// and with what, rising slowly over the dark.
package ui

import "core:math"

import rl "vendor:raylib"

import "../i18n"

CREDITS_RISE :: 46.0 // 1080p units a second
CREDITS_LINGER :: 4.0 // the last line held in the middle of the screen

@(private = "file")
Credit_Kind :: enum u8 {
	Gap, // an empty line
	End, // "The End", large
	Title, // the game's title in its face
	Label, // a small heading in gold capitals
	Line, // a line of text
	Name, // a name, a little larger
}

@(private = "file")
Credit :: struct {
	kind: Credit_Kind,
	key:  i18n.Key, // the text (unless `raw`)
	raw:  string,
}

@(private = "file")
CREDITS := [?]Credit {
	{kind = .End, key = .Cr_End},
	{kind = .Gap},
	{kind = .Title, raw = "The Trial of Psyche"},
	{kind = .Line, key = .Cr_After},
	{kind = .Gap},
	{kind = .Label, key = .Cr_Made},
	{kind = .Name, raw = "pankaspe"},
	{kind = .Line, key = .Cr_Copilot},
	{kind = .Gap},
	{kind = .Label, key = .Cr_Built},
	{kind = .Line, key = .Cr_Engine},
	{kind = .Line, key = .Cr_Generated},
	{kind = .Gap},
	{kind = .Label, key = .Cr_Fonts},
	{kind = .Line, raw = "Mystery Quest · Cormorant Garamond"},
	{kind = .Line, key = .Cr_Ofl},
	{kind = .Gap},
	{kind = .Gap},
	{kind = .Name, key = .Cr_Thanks},
}

// Draws the credits `t` seconds in; done once they have run out, or when the
// player asks (after a moment, so a key still held from the play is not taken).
credits :: proc(u: ^Ui, t: f32) -> (done: bool) {
	s := u.scale
	rl.DrawRectangleRec({0, 0, u.width, u.height}, {3, 3, 10, 255})
	cx := u.width * 0.5
	// the column rises from under the screen; its last line stops in the middle
	total: f32
	for c in CREDITS {
		total += credit_height(c.kind)
	}
	travel := u.height * 0.5 / s + total
	y0 := u.height - min(t * CREDITS_RISE, travel) * s
	y := y0
	for c, i in CREDITS {
		h := credit_height(c.kind) * s
		msg := c.raw != "" ? c.raw : i18n.tr(c.key)
		// lines fade in from the bottom edge and out at the top
		edge := min(y / (u.height * 0.15), (u.height - y) / (u.height * 0.15))
		a := clamp(edge, 0, 1)
		if i == len(CREDITS) - 1 {
			a = clamp((u.height - y) / (u.height * 0.15), 0, 1) // the last stays
		}
		switch c.kind {
		case .Gap:
		case .End:
			text(u, msg, {cx, y}, {size = 120, color = TITLE, face = .Display, glow = true}, .Center, a)
		case .Title:
			text(u, msg, {cx, y}, {size = 64, color = TITLE, face = .Display, glow = true}, .Center, a)
		case .Label:
			rule_label(u, caps(msg), {cx, y}, 20, 90 * s, a)
		case .Line:
			text(u, msg, {cx, y}, {size = 30, color = DIM, face = .Italic}, .Center, a)
		case .Name:
			text(u, msg, {cx, y}, {size = 40, color = TITLE, face = .Italic}, .Center, a)
		}
		y += h
	}
	over := t * CREDITS_RISE >= travel
	if t > 3 {
		blink := 0.45 + 0.3 * math.sin(t * 2.4)
		text(u, i18n.tr(.Card_Continue), {cx, u.height - 60 * s}, {size = 22, color = FAINT, face = .Italic}, .Center, blink * clamp((t - 3) / 1, 0, 1))
	}
	if over && t * CREDITS_RISE >= travel + CREDITS_LINGER * CREDITS_RISE {
		return true
	}
	return t > 2 && (u.pressed || take_accept(u))
}

@(private = "file")
credit_height :: proc(k: Credit_Kind) -> f32 {
	switch k {
	case .Gap: return 70
	case .End: return 190
	case .Title: return 90
	case .Label: return 50
	case .Line: return 46
	case .Name: return 60
	}
	return 0
}
