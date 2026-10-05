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
import "content"
import "game"
import "i18n"
import "progress"
import "render"
import "settings"
import "ui"

WINDOW_TITLE :: "The Trial of Psyche"
MENU_FADE :: 0.8
CARD_FADE :: 0.6
MAX_TOASTS :: 8

Screen :: enum u8 {
	Title,
	Levels,
	Book,
	Card, // the card before an act
	Play,
	Fragment, // a fragment of the tale just found: the game waits while it is read
	Pause,
	Settings,
	Ending,
}

Ending_Info :: ui.Ending_Info

// The card before an act, over the sleeping palace.
Act_Card :: struct {
	act:     content.Act,
	unbuilt: bool, // the act is not built yet: back to the title afterwards
	t:       f32,
	out_t:   f32, // < 0 unless fading out
}

App :: struct {
	cfg:             settings.Settings,
	prog:            progress.Progress,
	renderer:        render.Renderer,
	ui:              ui.Ui,
	game:            game.Game,
	scene:           render.Scene,
	screen:          Screen,
	settings_from:   Screen,
	menu_fade:       f32, // < 0 unless the title menu is fading out
	card_t:          f32, // time on the ending card
	ending:          Ending_Info,
	act_card:        Act_Card,
	book_page:       int,
	fragment_t:      f32, // time on the fragment card
	toasts:          [MAX_TOASTS]progress.Achievement, // achievements waiting to be announced
	toast_count:     int,
	toast_t:         f32,
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
	if !app.shooting {
		app.prog = progress.load()
	}
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
	if !new_level(app, progress.current_level(app.prog)) {
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
	g := &app.game
	if err, failed := game.load(g, index).?; failed {
		fmt.eprintfln("level %s, line %d: %s", content.LEVELS[index].id, err.line, err.message)
		return false
	}
	g.trust_allowed = progress.game_finished(app.prog)
	g.fragment_known = index in app.prog.fragments
	render.scene_build(&app.scene, g, game.level_allocator(g))
	return true
}

// Restart the current level at once (no act card, no prologue).
play_level :: proc(app: ^App) {
	if new_level(app, app.game.level_index) {
		game.begin(&app.game, prologue = false)
		app.screen = .Play
	}
}

// Start level `index`: the act card first when the level opens an act. A
// level not built yet shows only its act card, then the title.
// `from_title`: the sleeping palace behind the title is this level, wake it.
start_level :: proc(app: ^App, index: int, from_title := false) {
	if !content.is_built(index) {
		open_act_card(app, content.LEVELS[index].act, true)
		return
	}
	if !(from_title && app.game.level_index == index && !app.game.active) {
		if !new_level(app, index) {
			return
		}
	}
	// a level with a prologue opens its act with the cutscene, not the card
	if content.opens_act(index) && !app.game.data.has_prologue {
		open_act_card(app, content.LEVELS[index].act, false)
		return
	}
	game.begin(&app.game)
	app.screen = .Play
	if from_title {
		app.menu_fade = 0 // the title menu rises and fades as the palace wakes
	}
}

open_act_card :: proc(app: ^App, act: content.Act, unbuilt: bool) {
	app.act_card = {act = act, unbuilt = unbuilt, out_t = -1}
	app.screen = .Card
}

// The act card has been read: play, or back to the title if there is nothing to play yet.
@(private)
close_act_card :: proc(app: ^App) {
	if app.act_card.unbuilt {
		to_title(app)
		return
	}
	game.begin(&app.game)
	app.screen = .Play
}

// The level is over: record it, and show the ending card.
finish_level :: proc(app: ^App) {
	g := &app.game
	r := progress.Result {
		level     = g.level_index,
		trust     = g.ending == .Trust,
		lightings = g.lightings,
		lamp_par  = int(g.data.lamp_par),
	}
	unlocked := progress.complete_level(&app.prog, r)
	save_progress(app)
	app.ending = {
		ending       = g.ending,
		level        = g.level_index,
		unlocked     = unlocked,
		// the secret ending is outside the story: it leads nowhere
		can_continue = g.ending != .Trust && g.level_index + 1 < content.LEVEL_COUNT,
		outro        = g.data.outro,
		has_outro    = g.data.has_outro,
	}
	app.screen = .Ending
	app.card_t = 0
}

// Achievements to announce in the corner, one at a time.
announce :: proc(app: ^App, unlocked: progress.Achievements) {
	for a in unlocked {
		if app.toast_count < MAX_TOASTS {
			app.toasts[app.toast_count] = a
			app.toast_count += 1
		}
	}
}

@(private)
update_toasts :: proc(app: ^App, dt: f32) {
	if app.toast_count == 0 {
		return
	}
	app.toast_t += dt
	if app.toast_t >= ui.TOAST_TIME {
		app.toast_t = 0
		app.toast_count -= 1
		copy(app.toasts[:app.toast_count], app.toasts[1:app.toast_count + 1])
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
	paused := app.screen == .Pause || app.screen == .Fragment || (app.screen == .Settings && app.settings_from == .Pause)
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
	if g.fragment_new {
		g.fragment_new = false
		announce(app, progress.collect_fragment(&app.prog, g.level_index))
		save_progress(app)
		if app.screen == .Play {
			app.screen = .Fragment
			app.fragment_t = 0
		}
	}
	if app.screen == .Fragment {
		app.fragment_t += dt
	}
	if app.screen == .Play && g.phase == .Finished {
		finish_level(app)
	}
	if app.screen == .Ending {
		app.card_t += dt
	}
	if app.screen == .Card {
		update_act_card(app, dt)
	}
	update_toasts(app, dt)
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
		case .Levels, .Book:
			app.screen = .Title
		case .Card:
			dismiss_act_card(app)
		case .Fragment:
			close_fragment(app)
		case .Title, .Ending:
		}
	}
	if app.screen == .Book {
		if rl.IsKeyPressed(.LEFT) {
			app.book_page = max(app.book_page - 1, 0)
		}
		if rl.IsKeyPressed(.RIGHT) {
			app.book_page = min(app.book_page + 1, ui.BOOK_PAGES - 1)
		}
	}
	if app.screen == .Card && (rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.SPACE)) {
		dismiss_act_card(app)
	}
	if app.screen == .Fragment && (rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER)) {
		close_fragment(app)
	}
}

@(private)
close_fragment :: proc(app: ^App) {
	if app.fragment_t > 0.8 {
		app.screen = .Play
	}
}

@(private)
dismiss_act_card :: proc(app: ^App) {
	if app.act_card.out_t < 0 && app.act_card.t > 0.5 {
		app.act_card.out_t = 0
	}
}

@(private)
update_act_card :: proc(app: ^App, dt: f32) {
	c := &app.act_card
	c.t += dt
	if c.out_t >= 0 {
		c.out_t += dt
		if c.out_t >= CARD_FADE {
			close_act_card(app)
		}
	}
}

play_input :: proc(app: ^App) {
	g := &app.game
	if g.phase == .Prologue {
		// any key or click: skip the scene, then start
		if rl.GetKeyPressed() != .KEY_NULL || rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT) {
			game.prologue_advance(g)
		}
		return
	}
	if rl.IsKeyPressed(.R) {
		// back to the last brazier, or the whole level again
		if !game.return_to_rest(g) {
			play_level(app)
		}
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
	if rl.IsKeyPressed(.F) {
		game.use_handle(g)
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
			start_level(app, progress.current_level(app.prog), true)
		case .Levels:
			app.screen = .Levels
		case .Book:
			app.screen = .Book
		case .Settings:
			open_settings(app)
		case .Quit:
			app.quit = true
		case .None, .Resume, .Restart, .Main_Menu, .Retry, .Next, .Back:
		}
	case .Levels:
		chosen, back := ui.level_select(u, app.prog)
		if chosen >= 0 {
			start_level(app, chosen)
		} else if back {
			app.screen = .Title
		}
	case .Book:
		if ui.book(u, app.prog, &app.book_page) {
			app.screen = .Title
		}
	case .Card:
		c := app.act_card
		alpha: f32 = c.out_t >= 0 ? 1 - c.out_t / CARD_FADE : 1
		if ui.act_card(u, c.act, c.t, alpha, c.unbuilt) {
			dismiss_act_card(app)
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
	case .Fragment:
		ui.draw_hud(u, g)
		if ui.fragment_card(u, game.fragment_key(g), app.fragment_t) {
			close_fragment(app)
		}
	case .Pause:
		ui.draw_hud(u, g)
		switch ui.pause_menu(u, g.data.has_lamp) {
		case .Resume:
			app.screen = .Play
		case .Restart:
			play_level(app)
		case .Settings:
			open_settings(app)
		case .Main_Menu:
			to_title(app)
		case .None, .Play, .Levels, .Book, .Quit, .Retry, .Next, .Back:
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
		switch ui.ending_card(u, app.ending, app.card_t) {
		case .Next:
			start_level(app, app.ending.level + 1)
		case .Retry:
			play_level(app)
		case .Main_Menu:
			to_title(app)
		case .None, .Play, .Levels, .Book, .Settings, .Quit, .Resume, .Restart, .Back:
		}
	}
	if app.toast_count > 0 {
		ui.achievement_toast(u, app.toasts[0], app.toast_t)
	}
}

// Back to the title, over the level the player would continue from.
to_title :: proc(app: ^App) {
	if new_level(app, progress.current_level(app.prog)) {
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

save_progress :: proc(app: ^App) {
	if !app.shooting {
		progress.save(app.prog)
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
