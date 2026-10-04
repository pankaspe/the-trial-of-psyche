// The Trial of Psyche: an isometric puzzle about seeing and trusting, from
// Apuleius' tale of Cupid and Psyche (Metamorphoses IV-VI).
//
// Memory:
//   - context.allocator: the few things that live as long as the program
//     (audio WAV buffers); in debug builds it is wrapped in a tracking
//     allocator that reports leaks at exit.
//   - the level arena (inside game.Game): everything a level needs, freed in
//     one go when the level restarts or changes.
//   - context.temp_allocator: per-frame scratch, freed at the end of every frame.
package main

import "core:fmt"
@(require) import "core:mem" // tracking allocator, debug builds only
import "core:os"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

import "audio"
import "game"
import "i18n"
import "render"
import "settings"
import "ui"

WINDOW_TITLE :: "The Trial of Psyche"
MENU_FADE :: 0.8

Screen :: enum u8 {
	Title,
	Play,
	Pause,
	Settings,
	Ending,
}

App :: struct {
	cfg:             settings.Settings,
	renderer:        render.Renderer,
	ui:              ui.Ui,
	game:            game.Game,
	scene:           render.Scene,
	screen:          Screen,
	settings_from:   Screen,
	menu_fade:       f32, // < 0 unless the title menu is fading out
	card_t:          f32,
	time:            f32,
	quit:            bool,
	resolutions:     [len(settings.RESOLUTIONS)][2]i32,
	resolution_count: int,
	shots:           Shots,
	shooting:        bool, // scripted screenshot mode (--shots DIR)
	resize_wait:     int, // frames before (re)applying the window size; 0 = nothing pending
	resize_tries:    int,
	target:          rl.RenderTexture2D, // offscreen canvas (--shots DIR --size WxH)
	has_target:      bool,
}

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
		defer {
			for _, leak in track.allocation_map {
				fmt.eprintfln("leak: %v bytes at %v", leak.size, leak.location)
			}
			for bad in track.bad_free_array {
				fmt.eprintfln("bad free at %v", bad.location)
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	app := new(App)
	defer free(app)
	app.shots, app.shooting = shots_from_args(os.args)
	if !startup(app) {
		os.exit(1)
	}
	for !rl.WindowShouldClose() && !app.quit {
		frame(app)
		free_all(context.temp_allocator)
	}
	shutdown(app)
}

startup :: proc(app: ^App) -> bool {
	app.cfg = app.shooting ? settings.defaults() : settings.load()
	i18n.set_language(app.cfg.language)

	rl.SetTraceLogLevel(.WARNING)
	flags := rl.ConfigFlags{.WINDOW_RESIZABLE}
	if app.cfg.msaa {
		flags += {.MSAA_4X_HINT}
	}
	if app.cfg.vsync {
		flags += {.VSYNC_HINT}
	}
	rl.SetConfigFlags(flags)
	rl.InitWindow(app.cfg.resolution.x, app.cfg.resolution.y, WINDOW_TITLE)
	if !rl.IsWindowReady() {
		fmt.eprintln("cannot open a window")
		return false
	}
	rl.SetExitKey(.KEY_NULL) // Esc pauses, it does not quit
	rl.SetWindowMinSize(960, 540)
	rl.SetTargetFPS(app.cfg.fps_limit)
	find_resolutions(app)
	if app.cfg.fullscreen {
		set_fullscreen(true)
	}

	if app.shooting && app.shots.size.x > 0 {
		app.target = rl.LoadRenderTexture(app.shots.size.x, app.shots.size.y)
		app.has_target = true
	}
	audio.init()
	audio.set_volumes(app.cfg.master, app.cfg.music, app.cfg.sfx)
	render.init(&app.renderer)
	ui.init(&app.ui)
	if !new_level(app, 0) {
		return false
	}
	app.screen = .Title
	app.menu_fade = -1
	audio.start_music()
	return true
}

shutdown :: proc(app: ^App) {
	save_settings(app)
	game.destroy(&app.game)
	if app.has_target {
		rl.UnloadRenderTexture(app.target)
	}
	ui.shutdown(&app.ui)
	render.shutdown(&app.renderer)
	audio.shutdown()
	rl.CloseWindow()
}

// Window sizes that fit the monitor with room for the title bar.
find_resolutions :: proc(app: ^App) {
	m := rl.GetCurrentMonitor()
	mw, mh := rl.GetMonitorWidth(m), rl.GetMonitorHeight(m)
	app.resolution_count = 0
	for r in settings.RESOLUTIONS {
		if r.x <= mw && r.y <= mh - 80 {
			app.resolutions[app.resolution_count] = r
			app.resolution_count += 1
		}
	}
	if app.resolution_count == 0 {
		app.resolutions[0] = settings.RESOLUTIONS[0]
		app.resolution_count = 1
	}
}

// (Re)load a level; the palace sleeps (attract mode) until game.begin.
new_level :: proc(app: ^App, index: int) -> bool {
	if err, failed := game.load(&app.game, index).?; failed {
		fmt.eprintfln("level %d, line %d: %s", index + 1, err.line, err.message)
		return false
	}
	render.scene_build(&app.scene, &app.game, game.level_allocator(&app.game))
	return true
}

play_level :: proc(app: ^App) {
	if new_level(app, app.game.level_index) {
		game.begin(&app.game)
		app.screen = .Play
	}
}

// --- frame -------------------------------------------------------------------------

frame :: proc(app: ^App) {
	dt := min(rl.GetFrameTime(), 0.1)
	app.time += dt
	g := &app.game
	u := &app.ui
	update_window_size(app)
	w, h := canvas_size(app)
	ui.begin_frame(u, w, h)
	global_keys(app)

	// input that drives the game
	if app.screen == .Play && app.menu_fade < 0 {
		play_input(app)
	}
	paused := app.screen == .Pause || (app.screen == .Settings && app.settings_from == .Pause)
	if !paused {
		game.update(g, dt)
		render.scene_update(&app.scene, g, dt)
	}
	if app.menu_fade >= 0 {
		app.menu_fade += dt
		if app.menu_fade >= MENU_FADE {
			app.menu_fade = -1
		}
	}
	if app.screen == .Play && g.phase == .Finished {
		app.screen = .Ending
		app.card_t = 0
	}
	if app.screen == .Ending {
		app.card_t += dt
	}
	audio.update()
	shot := ""
	if app.shooting {
		done: bool
		shot, done = shots_update(app, &app.shots, dt)
		app.quit ||= done
	}

	// drawing (widgets also report their clicks here)
	view := render.scene_view(&app.scene, g, w, h)
	rl.BeginDrawing()
	if app.has_target {
		rl.BeginTextureMode(app.target)
	}
	reset_canvas(w, h)
	rl.ClearBackground({5, 5, 15, 255})
	render.draw_world(&app.renderer, &app.scene, g, view, app.time)
	draw_screens(app)
	if app.cfg.debug {
		debug(app)
	}
	if app.has_target {
		rl.EndTextureMode()
		if shot != "" {
			shots_capture_texture(&app.shots, shot, app.target.texture)
		}
		show_target(app)
	} else if shot != "" {
		shots_capture(&app.shots, shot)
	}
	rl.EndDrawing()
}

// The size we really draw to. raylib's screen size can lag behind the
// window (a resize refused by the compositor, a maximised window): the
// framebuffer is the truth. In screenshot mode it can be an offscreen canvas.
canvas_size :: proc(app: ^App) -> (w, h: f32) {
	if app.has_target {
		return f32(app.target.texture.width), f32(app.target.texture.height)
	}
	return f32(max(rl.GetRenderWidth(), 1)), f32(max(rl.GetRenderHeight(), 1))
}

// Point the viewport and the 2D projection at the whole canvas, whatever
// raylib last set up.
reset_canvas :: proc(w, h: f32) {
	rlgl.DrawRenderBatchActive()
	rlgl.Viewport(0, 0, i32(w), i32(h))
	rlgl.MatrixMode(rlgl.PROJECTION)
	rlgl.LoadIdentity()
	rlgl.Ortho(0, f64(w), f64(h), 0, 0, 1)
	rlgl.MatrixMode(rlgl.MODELVIEW)
	rlgl.LoadIdentity()
}

// The offscreen canvas, letterboxed in the window.
show_target :: proc(app: ^App) {
	ww, wh := f32(max(rl.GetRenderWidth(), 1)), f32(max(rl.GetRenderHeight(), 1))
	reset_canvas(ww, wh)
	rl.ClearBackground(rl.BLACK)
	tw, th := f32(app.target.texture.width), f32(app.target.texture.height)
	k := min(ww / tw, wh / th)
	dest := rl.Rectangle{(ww - tw * k) * 0.5, (wh - th * k) * 0.5, tw * k, th * k}
	rl.DrawTexturePro(app.target.texture, {0, 0, tw, -th}, dest, {}, 0, rl.WHITE)
}

// Fullscreen at the monitor's own resolution (no video mode change). Tested on
// GNOME (Wayland/XWayland): raylib's borderless mode cannot be left there, the
// window stays monitor-sized and ignores every resize; true fullscreen can.
set_fullscreen :: proc(on: bool) {
	if on == rl.IsWindowFullscreen() {
		return
	}
	if on {
		m := rl.GetCurrentMonitor()
		rl.SetWindowSize(rl.GetMonitorWidth(m), rl.GetMonitorHeight(m))
	}
	rl.ToggleFullscreen()
}

// Pending window resize (see apply).
update_window_size :: proc(app: ^App) {
	if app.resize_wait == 0 || app.cfg.fullscreen {
		app.resize_wait = 0
		return
	}
	app.resize_wait -= 1
	if app.resize_wait > 0 {
		return
	}
	want := app.cfg.resolution
	if rl.GetRenderWidth() == want.x && rl.GetRenderHeight() == want.y {
		return
	}
	if app.resize_tries == 0 {
		return // the window manager insists: we draw at whatever size we get
	}
	app.resize_tries -= 1
	if rl.IsWindowMaximized() {
		rl.RestoreWindow()
	}
	m := rl.GetCurrentMonitor()
	rl.SetWindowSize(want.x, want.y)
	rl.SetWindowPosition((rl.GetMonitorWidth(m) - want.x) / 2, (rl.GetMonitorHeight(m) - want.y) / 2)
	app.resize_wait = 10 // check again shortly
}

global_keys :: proc(app: ^App) {
	if rl.IsKeyPressed(.F11) {
		app.cfg.fullscreen = !app.cfg.fullscreen
		apply(app, {.Fullscreen})
	}
	if rl.IsKeyPressed(.F3) {
		app.cfg.debug = !app.cfg.debug
		save_settings(app)
	}
	if rl.IsKeyPressed(.ESCAPE) {
		switch app.screen {
		case .Play:
			app.screen = .Pause
		case .Pause:
			app.screen = .Play
		case .Settings:
			close_settings(app)
		case .Title, .Ending:
		}
	}
}

play_input :: proc(app: ^App) {
	g := &app.game
	if rl.IsKeyPressed(.R) {
		play_level(app)
		return
	}
	if rl.IsKeyPressed(.SPACE) || rl.IsKeyPressed(.L) || rl.IsMouseButtonPressed(.RIGHT) {
		game.toggle_lamp(g)
	}
	if rl.IsKeyPressed(.Q) || rl.IsKeyPressed(.LEFT) {
		game.request_turn(g, -1)
	}
	if rl.IsKeyPressed(.E) || rl.IsKeyPressed(.RIGHT) {
		game.request_turn(g, 1)
	}
	if app.ui.pressed && !ui.over_ui(&app.ui) {
		w, h := canvas_size(app)
		view := render.scene_view(&app.scene, g, w, h)
		game.click(g, render.screen_to_proto(view, app.ui.mouse))
	}
}

draw_screens :: proc(app: ^App) {
	g := &app.game
	u := &app.ui
	switch app.screen {
	case .Title:
		act := ui.title_menu(u)
		if rl.IsKeyPressed(.ENTER) {
			act = .Play
		}
		switch act {
		case .Play:
			app.screen = .Play
			app.menu_fade = 0
			game.begin(g)
		case .Settings:
			open_settings(app)
		case .Quit:
			app.quit = true
		case .None, .Resume, .Restart, .Main_Menu, .Retry, .Back:
		}
	case .Play:
		act := ui.draw_hud(u, g)
		if act.lamp {
			game.toggle_lamp(g)
		}
		if act.turn != 0 {
			game.request_turn(g, act.turn)
		}
		if app.menu_fade >= 0 {
			// the title menu rises and fades away as the game begins
			k := app.menu_fade / MENU_FADE
			ui.title_menu(u, 1 - k, 40 * k)
		}
	case .Pause:
		ui.draw_hud(u, g)
		switch ui.pause_menu(u) {
		case .Resume:
			app.screen = .Play
		case .Restart:
			play_level(app)
		case .Settings:
			open_settings(app)
		case .Main_Menu:
			to_title(app)
		case .None, .Play, .Quit, .Retry, .Back:
		}
	case .Settings:
		m := rl.GetCurrentMonitor()
		native := [2]i32{rl.GetMonitorWidth(m), rl.GetMonitorHeight(m)}
		changes, back := ui.settings_menu(u, &app.cfg, app.resolutions[:app.resolution_count], native)
		if changes != {} {
			apply(app, changes)
		}
		if back {
			close_settings(app)
		}
	case .Ending:
		switch ui.ending_card(u, g.ending, app.card_t) {
		case .Retry:
			play_level(app)
		case .Main_Menu:
			to_title(app)
		case .None, .Play, .Settings, .Quit, .Resume, .Restart, .Back:
		}
	}
}

to_title :: proc(app: ^App) {
	if new_level(app, app.game.level_index) {
		app.screen = .Title
	}
}

open_settings :: proc(app: ^App) {
	app.settings_from = app.screen
	app.screen = .Settings
	find_resolutions(app)
}

close_settings :: proc(app: ^App) {
	app.screen = app.settings_from
	save_settings(app)
}

// Apply changed settings to the window and the audio.
apply :: proc(app: ^App, changes: ui.Setting_Changes) {
	c := app.cfg
	if .Language in changes {
		i18n.set_language(c.language)
	}
	if .Fullscreen in changes {
		set_fullscreen(c.fullscreen)
	}
	// back in a window (or a new size): the window manager drops a resize
	// asked right after leaving fullscreen, so it is applied a few frames
	// later and retried until the framebuffer really has that size
	if (.Resolution in changes || .Fullscreen in changes) && !c.fullscreen {
		app.resize_wait = 4
		app.resize_tries = 4
	}
	if .Vsync in changes {
		if c.vsync {
			rl.SetWindowState({.VSYNC_HINT})
		} else {
			rl.ClearWindowState({.VSYNC_HINT})
		}
	}
	if .Fps in changes {
		rl.SetTargetFPS(c.fps_limit)
	}
	if .Volumes in changes {
		audio.set_volumes(c.master, c.music, c.sfx)
	}
	if changes - {.Volumes} != {} {
		save_settings(app)
	}
}

save_settings :: proc(app: ^App) {
	if !app.shooting {
		settings.save(app.cfg)
	}
}

debug :: proc(app: ^App) {
	g := &app.game
	ui.debug_overlay(&app.ui, {
		fps = rl.GetFPS(),
		frame_ms = rl.GetFrameTime() * 1000,
		level_bytes = g.arena.total_used,
		level_peak = g.arena.total_reserved,
		pieces = len(app.scene.pieces),
		nodes = len(g.palace.nodes),
		illusions = len(g.palace.illusion.pairs),
	})
}
