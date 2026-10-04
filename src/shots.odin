// Scripted screenshots for visual checks: `trial-of-psyche --shots DIR` goes
// through the menus and plays a fixed sequence through level I.4, saves PNGs
// into DIR and quits. The user's settings and progress are neither read nor
// written in this mode.
package main

import "core:fmt"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

import "game"
import "iso"
import pl "palace"
import "ui"

Shot_Step :: struct {
	wait: f32, // seconds after the previous step
	name: string, // screenshot to take after the action ("" = none)
	action: proc(app: ^App),
}

@(private = "file")
BALCONY :: iso.Cell{3, 4, 3}
@(private = "file")
ROOF_ENTRY :: iso.Cell{5, 5, 5}

// Turn to a view that joins the balcony to the fragment's pillar and walk there.
@(private = "file")
walk_to_fragment :: proc(app: ^App) {
	g := &app.game
	place(app, BALCONY)
	for r in 0 ..< 4 {
		game.set_view(g, r)
		if game.walk_to(g, g.data.fragment) {
			return
		}
	}
}

@(private = "file")
place :: proc(app: ^App, c: iso.Cell) {
	g := &app.game
	g.psyche.cell = c
	g.psyche.pos = pl.node_world(&g.palace, c)
}

SHOT_SCRIPT := [?]Shot_Step {
	{1.5, "01_menu", nil},
	{0.1, "", proc(app: ^App) {open_settings(app)}},
	{0.6, "02_settings", nil},
	{0.1, "", proc(app: ^App) {close_settings(app)}},
	{0.1, "", proc(app: ^App) {app.prog.completed = {3}; app.prog.fragments = {3}; app.screen = .Levels}},
	{0.6, "02b_levels", nil},
	{0.1, "", proc(app: ^App) {app.prog.achievements = {.No_Wasted_Light}; app.book_page = 0; app.screen = .Book}},
	{0.6, "02c_book", nil},
	{0.1, "", proc(app: ^App) {app.book_page = ui.BOOK_PAGES - 1}},
	{0.6, "02d_achievements", nil},
	{0.1, "", proc(app: ^App) {app.prog = {}; app.screen = .Title}},
	{0.1, "", proc(app: ^App) {open_act_card(app, .I, false)}},
	{4.0, "02e_act_card", nil},
	{0.1, "", proc(app: ^App) {dismiss_act_card(app)}},
	{3.0, "03_view0_dark", nil},
	{0.1, "", proc(app: ^App) {game.request_turn(&app.game, -1)}},
	{0.37, "04_mid_turn", nil},
	{1.0, "05_view3_dark", proc(app: ^App) {place(app, BALCONY)}},
	{0.1, "", proc(app: ^App) {game.toggle_lamp(&app.game)}},
	{1.2, "06_view3_lamp", nil},
	{0.1, "", proc(app: ^App) {game.toggle_lamp(&app.game); walk_to_fragment(app)}},
	{3.5, "06b_fragment", proc(app: ^App) {announce(app, {.No_Wasted_Light})}},
	{1.0, "06c_toast", nil},
	{0.1, "", proc(app: ^App) {close_fragment(app); game.set_view(&app.game, 1)}},
	{0.8, "07_view1_dark", proc(app: ^App) {place(app, app.game.data.sigil)}},
	{0.1, "", proc(app: ^App) {game.toggle_lamp(&app.game)}},
	{1.5, "08_rising", nil},
	{3.0, "09_risen_lamp", nil},
	{0.1, "", proc(app: ^App) {game.toggle_lamp(&app.game); game.set_view(&app.game, 3)}},
	{1.0, "10_roof_path_dark", proc(app: ^App) {place(app, ROOF_ENTRY)}},
	{0.5, "", proc(app: ^App) {game.toggle_lamp(&app.game)}},
	{1.6, "11_reveal", nil},
	{1.6, "12_drop", nil},
	{2.0, "13_collapse", nil},
	{4.0, "14_end_card", nil},
	{0.1, "", proc(app: ^App) {start_level(app, app.ending.level + 1)}},
	{4.0, "14b_act2_unbuilt", nil},
	{0.1, "", proc(app: ^App) {dismiss_act_card(app)}},
	{1.0, "14c_back_to_title", nil},
	// window modes (skipped on an offscreen canvas)
	{0.1, "", proc(app: ^App) {window_mode(app, true, {1600, 900})}},
	{1.5, "15_fullscreen", nil},
	{0.1, "", proc(app: ^App) {window_mode(app, false, {1280, 720})}},
	{1.5, "16_window_1280", nil},
	{0.1, "", proc(app: ^App) {window_mode(app, true, {1280, 720})}},
	{1.0, "", proc(app: ^App) {window_mode(app, false, {1600, 900})}},
	{1.5, "17_window_1600", nil},
}

@(private = "file")
window_mode :: proc(app: ^App, fullscreen: bool, size: [2]i32) {
	if app.has_target {
		return
	}
	app.cfg.fullscreen = fullscreen
	app.cfg.resolution = size
	apply(app, {.Fullscreen, .Resolution})
}

Shots :: struct {
	dir:  string,
	size: [2]i32, // offscreen canvas size (--size WxH), 0 = the window
	step: int,
	t:    f32,
}

// Parse `--shots DIR [--size WxH]` from the command line.
shots_from_args :: proc(args: []string) -> (s: Shots, ok: bool) {
	for a, i in args {
		if i + 1 >= len(args) {
			break
		}
		switch a {
		case "--shots":
			s.dir, ok = args[i + 1], true
		case "--size":
			v := args[i + 1]
			if x := strings.index_byte(v, 'x'); x > 0 {
				w, _ := strconv.parse_int(v[:x], 10)
				h, _ := strconv.parse_int(v[x + 1:], 10)
				s.size = {i32(w), i32(h)}
			}
		}
	}
	return
}

// Advance the script; returns the screenshot name due this frame, if any.
shots_update :: proc(app: ^App, s: ^Shots, dt: f32) -> (name: string, done: bool) {
	if s.step >= len(SHOT_SCRIPT) {
		return "", true
	}
	s.t += dt
	step := SHOT_SCRIPT[s.step]
	if s.t < step.wait {
		return "", false
	}
	s.t = 0
	s.step += 1
	if step.action != nil {
		step.action(app)
	}
	return step.name, false
}

// Save the frame being drawn (call before EndDrawing).
shots_capture :: proc(s: ^Shots, name: string) {
	rlgl.DrawRenderBatchActive()
	img := rl.LoadImageFromScreen()
	defer rl.UnloadImage(img)
	path := strings.clone_to_cstring(fmt.tprintf("%s/%s.png", s.dir, name), context.temp_allocator)
	rl.ExportImage(img, path)
}

// Save the offscreen canvas (render textures are stored upside down).
shots_capture_texture :: proc(s: ^Shots, name: string, tex: rl.Texture2D) {
	img := rl.LoadImageFromTexture(tex)
	defer rl.UnloadImage(img)
	rl.ImageFlipVertical(&img)
	rl.ImageFormat(&img, .UNCOMPRESSED_R8G8B8) // blending leaves partial alpha in the texture
	path := strings.clone_to_cstring(fmt.tprintf("%s/%s.png", s.dir, name), context.temp_allocator)
	rl.ExportImage(img, path)
}
