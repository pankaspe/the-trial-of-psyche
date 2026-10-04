// Full-screen menus: title, pause, settings, the ending card, the debug overlay.
package ui

import "core:fmt"
import rl "vendor:raylib"

import "../game"
import "../i18n"
import "../settings"

Menu_Action :: enum u8 {
	None,
	Play,
	Settings,
	Quit,
	Resume,
	Restart,
	Main_Menu,
	Retry,
	Back,
}

@(private)
shade :: proc(u: ^Ui, alpha: f32) {
	rl.DrawRectangleRec({0, 0, u.width, u.height}, fade({3, 3, 10, 255}, alpha))
}

// Title screen over the sleeping palace. `alpha` and `lift` animate its exit.
title_menu :: proc(u: ^Ui, alpha: f32 = 1, lift: f32 = 0) -> (act: Menu_Action) {
	s := u.scale
	shade(u, 0.55 * alpha)
	cx := u.width * 0.5
	y := u.height * 0.5 - 300 * s - lift * s
	text(u, i18n.tr(.Title), {cx, y}, {size = 104, color = {255, 230, 179, 255}, shadow = true}, .Center, alpha)
	y += 140 * s
	text(u, i18n.tr(.Subtitle), {cx, y}, {size = 30, color = DIM, shadow = true}, .Center, alpha)
	y += 110 * s
	if button(u, i18n.tr(.Play), {cx, y}, 38, alpha) {
		act = .Play
	}
	y += 70 * s
	if button(u, i18n.tr(.Settings), {cx, y}, 26, alpha) {
		act = .Settings
	}
	y += 54 * s
	if button(u, i18n.tr(.Quit), {cx, y}, 26, alpha) {
		act = .Quit
	}
	y += 90 * s
	paragraph(u, i18n.tr(.Quote), {cx, y}, {size = 24, color = {191, 184, 230, 217}, italic = true, shadow = true}, 1400 * s, alpha)
	text(u, i18n.tr(.Footer), {cx, u.height - 48 * s}, {size = 18, color = FAINT, shadow = true}, .Center, alpha)
	return
}

pause_menu :: proc(u: ^Ui) -> (act: Menu_Action) {
	s := u.scale
	shade(u, 0.6)
	cx := u.width * 0.5
	y := u.height * 0.5 - 170 * s
	text(u, i18n.tr(.Pause_Title), {cx, y}, {size = 64, color = {255, 230, 179, 255}, shadow = true})
	y += 130 * s
	if button(u, i18n.tr(.Resume), {cx, y}, 34) {
		act = .Resume
	}
	y += 64 * s
	if button(u, i18n.tr(.Restart), {cx, y}, 26) {
		act = .Restart
	}
	y += 54 * s
	if button(u, i18n.tr(.Settings), {cx, y}, 26) {
		act = .Settings
	}
	y += 54 * s
	if button(u, i18n.tr(.Menu), {cx, y}, 26) {
		act = .Main_Menu
	}
	return
}

// The card after an ending; `t` is the time since it appeared.
ending_card :: proc(u: ^Ui, ending: game.Ending, t: f32) -> (act: Menu_Action) {
	s := u.scale
	shade(u, 0.7 * clamp(t / 1.5, 0, 1))
	a := clamp(t / 2, 0, 1)
	good := ending == .Good
	cx := u.width * 0.5
	body := Style{size = 32, color = TEXT, shadow = true}
	msg := i18n.tr(good ? .End_Good : .End_Bad)
	bh := block_height(u, msg, body, 1400 * s)
	y := u.height * 0.5 - (bh + 300 * s) * 0.5
	title_col := good ? GOLD : rl.Color{255, 179, 128, 255}
	text(u, i18n.tr(good ? .End_Good_Title : .End_Bad_Title), {cx, y}, {size = 72, color = title_col, shadow = true}, .Center, a)
	y += 110 * s
	y += paragraph(u, msg, {cx, y}, body, 1400 * s, a)
	y += 40 * s
	text(u, i18n.tr(.End_Note), {cx, y}, {size = 22, color = DIM, shadow = true}, .Center, a)
	y += 80 * s
	if button(u, i18n.tr(.Retry), {cx - 150 * s, y}, 30, a) {
		act = .Retry
	}
	if button(u, i18n.tr(.Menu), {cx + 150 * s, y}, 30, a) {
		act = .Main_Menu
	}
	return
}

Setting_Field :: enum u8 {
	Language,
	Fullscreen,
	Resolution,
	Vsync,
	Fps,
	Msaa,
	Volumes,
	Debug,
}

Setting_Changes :: bit_set[Setting_Field]

// The settings panel: edits `cfg` in place and reports what changed.
settings_menu :: proc(u: ^Ui, cfg: ^settings.Settings, resolutions: [][2]i32, native: [2]i32) -> (changes: Setting_Changes, back: bool) {
	s := u.scale
	shade(u, 0.7)
	cx := u.width * 0.5
	left := cx - 420 * s
	right := cx + 420 * s
	y := u.height * 0.5 - 430 * s
	text(u, i18n.tr(.Set_Title), {cx, y}, {size = 56, color = {255, 230, 179, 255}, shadow = true})
	y += 100 * s
	row := 46 * s
	section :: proc(u: ^Ui, key: i18n.Key, left: f32, y: ^f32) {
		text(u, i18n.tr(key), {left, y^}, {size = 22, color = GOLD, shadow = true}, .Left, 0.85)
		y^ += 38 * u.scale
	}
	on_off :: proc(v: bool) -> string {
		return i18n.tr(v ? .Set_On : .Set_Off)
	}

	section(u, .Set_General, left, &y)
	if step := option_row(u, i18n.tr(.Set_Language), i18n.tr(.Lang_Name), y, left, right); step != 0 {
		n := len(i18n.Language)
		cfg.language = i18n.Language((int(cfg.language) + step + n) % n)
		changes += {.Language}
	}
	y += row + 14 * s

	section(u, .Set_Video, left, &y)
	if step := option_row(u, i18n.tr(.Set_Display), i18n.tr(cfg.fullscreen ? .Set_Fullscreen : .Set_Windowed), y, left, right); step != 0 {
		cfg.fullscreen = !cfg.fullscreen
		changes += {.Fullscreen}
	}
	y += row
	// fullscreen always uses the monitor's own resolution
	res_label := cfg.fullscreen ? fmt.tprintf("%d × %d  (%s)", native.x, native.y, i18n.tr(.Set_Native)) : fmt.tprintf("%d × %d", cfg.resolution.x, cfg.resolution.y)
	if step := option_row(u, i18n.tr(.Set_Resolution), res_label, y, left, right, !cfg.fullscreen && len(resolutions) > 0); step != 0 {
		current := 0
		for r, i in resolutions {
			if r == cfg.resolution {
				current = i
			}
		}
		cfg.resolution = resolutions[(current + step + len(resolutions)) % len(resolutions)]
		changes += {.Resolution}
	}
	y += row
	if step := option_row(u, i18n.tr(.Set_Vsync), on_off(cfg.vsync), y, left, right); step != 0 {
		cfg.vsync = !cfg.vsync
		changes += {.Vsync}
	}
	y += row
	fps_label := cfg.fps_limit == 0 ? i18n.tr(.Set_Unlimited) : fmt.tprintf("%d", cfg.fps_limit)
	if step := option_row(u, i18n.tr(.Set_Fps), fps_label, y, left, right); step != 0 {
		limits := settings.FPS_LIMITS[:]
		current := 0
		for l, i in limits {
			if l == cfg.fps_limit {
				current = i
			}
		}
		cfg.fps_limit = limits[(current + step + len(limits)) % len(limits)]
		changes += {.Fps}
	}
	y += row
	msaa_label := fmt.tprintf("%s  %s", on_off(cfg.msaa), i18n.tr(.Set_Restart_Note))
	if step := option_row(u, i18n.tr(.Set_Msaa), msaa_label, y, left, right); step != 0 {
		cfg.msaa = !cfg.msaa
		changes += {.Msaa}
	}
	y += row + 14 * s

	section(u, .Set_Audio, left, &y)
	if slider(u, i18n.tr(.Set_Master), &cfg.master, y, left, right) {
		changes += {.Volumes}
	}
	y += row
	if slider(u, i18n.tr(.Set_Music), &cfg.music, y, left, right) {
		changes += {.Volumes}
	}
	y += row
	if slider(u, i18n.tr(.Set_Sfx), &cfg.sfx, y, left, right) {
		changes += {.Volumes}
	}
	y += row + 14 * s
	if step := option_row(u, i18n.tr(.Set_Debug), on_off(cfg.debug), y, left, right); step != 0 {
		cfg.debug = !cfg.debug
		changes += {.Debug}
	}
	y += row + 40 * s
	back = button(u, i18n.tr(.Back), {cx, y}, 30)
	return
}

Debug_Info :: struct {
	fps:         i32,
	frame_ms:    f32,
	level_bytes: uint, // level arena in use
	level_peak:  uint, // level arena reserved
	pieces:      int,
	nodes:       int,
	illusions:   int,
}

debug_overlay :: proc(u: ^Ui, info: Debug_Info) {
	s := u.scale
	lines := [?]string {
		fmt.tprintf("FPS %d   %.2f ms", info.fps, info.frame_ms),
		fmt.tprintf("level arena %.1f KiB used / %.1f KiB reserved", f32(info.level_bytes) / 1024, f32(info.level_peak) / 1024),
		fmt.tprintf("pieces %d   nodes %d   illusions %d", info.pieces, info.nodes, info.illusions),
	}
	rl.DrawRectangleRec({12 * s, 12 * s, 560 * s, f32(len(lines)) * 26 * s + 16 * s}, {0, 0, 10, 150})
	for line, i in lines {
		text(u, line, {24 * s, 20 * s + f32(i) * 26 * s}, {size = 19, color = {200, 220, 255, 255}}, .Left)
	}
}
