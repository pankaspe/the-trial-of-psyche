// In-game overlay: level title, Cupid's voice, the fragment just found, hints,
// controls, oil gauge and lamp button (when Psyche has the lamp), the two
// turn buttons.
package ui

import rl "vendor:raylib"

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

	// title and voice stay visible even when the rest of the HUD is hidden
	if a := game.fade_alpha(hud.title); a > 0 {
		text(u, level_name(g.level_index), {w * 0.5, 48 * s}, {size = 46, color = TEXT, shadow = true}, .Center, a)
	}
	if a := game.fade_alpha(hud.fragment); a > 0 {
		// on a dark band, so it reads over the palace
		y := 150 * s
		st := Style{size = 30, color = {240, 232, 214, 255}, italic = true, shadow = true}
		msg := i18n.tr(hud.fragment.key)
		bw := 1100 * s
		bh := block_height(u, msg, st, bw, 1.3)
		band := rl.Rectangle{w * 0.5 - bw * 0.5 - 50 * s, y - 40 * s, bw + 100 * s, bh + 110 * s}
		rl.DrawRectangleRec(band, fade({6, 6, 20, 255}, 0.62 * a))
		rl.DrawRectangleRec({band.x, band.y + band.height - max(s, 1), band.width, max(2 * s, 1)}, fade(GOLD, 0.45 * a))
		diamond(u, {w * 0.5, y - 14 * s}, 7 * s, fade(GOLD, a), true)
		text(u, i18n.tr(.Fragment_Found), {w * 0.5, y}, {size = 22, color = GOLD, shadow = true}, .Center, a)
		paragraph(u, msg, {w * 0.5, y + 44 * s}, st, bw, a, 1.3)
	}
	if a := game.fade_alpha(hud.voice); a > 0 {
		st := Style{size = 34, color = {255, 230, 184, 255}, italic = true, shadow = true}
		msg := i18n.tr(hud.voice.key)
		bh := block_height(u, msg, st, 1300 * s)
		// centred in the band between 210 and 120 px from the bottom
		top := h - 165 * s - bh * 0.5
		paragraph(u, msg, {w * 0.5, top}, st, 1300 * s, a)
	}
	if !hud.visible {
		return
	}
	if a := game.fade_alpha(hud.hint); a > 0 {
		text(u, i18n.tr(hud.hint.key), {w * 0.5, h - 92 * s}, {size = 24, color = DIM, shadow = true}, .Center, a)
	}
	lamp := g.data.has_lamp
	text(u, i18n.tr(lamp ? .Controls : .Controls_Dark), {w * 0.5, h - 40 * s}, {size = 18, color = FAINT, shadow = true})

	if lamp {
		draw_oil(u, g)
		if button(u, i18n.tr(.Lamp_Button), {w - 150 * s, h - 83 * s}, 28) {
			act.lamp = true
		}
	}
	if turn_button(u, {78 * s, h - 83 * s}, -1) {
		act.turn = -1
	}
	if turn_button(u, {158 * s, h - 83 * s}, 1) {
		act.turn = 1
	}
	return
}

// The oil gauge: it empties from the left; a small flame lives at its end while lit.
@(private)
draw_oil :: proc(u: ^Ui, g: ^game.Game) {
	s := u.scale
	x0 := u.width - 330 * s
	bw := 290 * s
	y := 58 * s
	bar := rl.Rectangle{x0, y, bw, 8 * s}
	rl.DrawRectangleRec(bar, {38, 38, 77, 180})
	oil := clamp(g.oil / game.OIL_MAX, 0, 1)
	lit := g.light
	fill := rl.Rectangle{x0 + bw * (1 - oil), y, bw * oil, bar.height}
	col := rl.Color{255, u8(179 + 51 * lit), u8(77 + 51 * lit), 255}
	rl.DrawRectangleRec(fill, col)
	tip := Vec2{x0 + bw * (1 - oil), y + 4 * s}
	rl.DrawCircleV(tip, (6 + 3 * lit) * s, fade({255, 204, 102, 255}, 0.25 + 0.6 * lit))
	text(u, i18n.tr(.Oil), {u.width - 40 * s, 72 * s}, {size = 22, color = DIM, shadow = true}, .Right)
}
