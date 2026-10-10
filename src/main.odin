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
import "input"
import "level"
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
	Mechanic, // the level's new mechanic presented: the game waits while it is read
	Pause,
	Settings,
	Ending,
}

Ending_Info :: ui.Ending_Info
Book_State :: ui.Book_State

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
	book:            Book_State,
	fragment_t:      f32, // time on the fragment card
	mechanic_t:      f32, // time on the mechanic card
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
	post:            render.Post,
	black_t:         f32, // < 0, or time since the screen began to fade to black (end of an act)
	black_next:      int, // the level that follows the black
	rest_t:          f32, // how long R (or the brazier's button) has been held, < 0 when up
	rest_fired:      bool, // this hold has already restarted the level
	rest_tap_t:      f32, // time since the last tap of R (pressed twice: the level again)
	east_block:      bool, // the pad's East closed a menu: it is not the brazier until let go
	focus_screen:    Screen, // the screen the UI's focus belongs to
}

REST_TAP :: 0.25 // a press of R shorter than this is a tap: back to the brazier
REST_TWICE :: 1.5 // R pressed twice within this restarts the level (accessibility)

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
	if l, ok := app.shots.pad.?; ok && app.shooting {
		input.force(l)
	}
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
	// MSAA serves the High quality (drawn straight to the screen); the
	// others draw through a canvas, so the quality changes without a restart
	flags := rl.ConfigFlags{.WINDOW_RESIZABLE, .MSAA_4X_HINT}
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
	render.post_init(&app.post)
	if app.shots.has_quality {
		app.cfg.quality = app.shots.quality
	}
	ui.init(&app.ui)
	if !new_level(app, progress.current_level(app.prog)) {
		return false
	}
	app.screen = .Title
	app.menu_fade = -1
	app.black_t = -1
	app.rest_t = -1
	app.rest_tap_t = 1e3
	return true
}

shutdown :: proc(app: ^App) {
	save_settings(app)
	game.destroy(&app.game)
	if app.has_target {
		rl.UnloadRenderTexture(app.target)
	}
	ui.shutdown(&app.ui)
	render.post_shutdown(&app.post)
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
	source := content.LEVELS[index].source
	if app.shooting && app.shots.file != "" && index == app.shots.level {
		source = app.shots.file
	}
	if err, failed := game.load_text(g, index, source).?; failed {
		fmt.eprintfln("level %s, line %d: %s", content.LEVELS[index].id, err.line, err.message)
		return false
	}
	g.trust_allowed = progress.game_finished(app.prog)
	for _, i in g.data.fragments {
		if game.fragment_index(g, i) in app.prog.fragments {
			g.fragments_known += {i}
		}
	}
	render.scene_build(&app.scene, g, game.level_allocator(g))
	return true
}

// The music of each act (generative), and its key (in-key effects follow it).
ACT_MOOD := [content.Act]audio.Mood_Id {
	.I        = .Palace,
	.II       = .Abandonment,
	.III      = .Trials,
	.IV       = .Underworld,
	.Epilogue = .Palace,
}
ACT_KEY := [content.Act]f32 {
	.I        = 0, // A minor
	.II       = -2, // G minor
	.III      = 5, // D minor
	.IV       = -5, // E Phrygian
	.Epilogue = 0,
}
// The ambience of each place.
SETTING_BED := [level.Setting]audio.Bed {
	.Night         = .Night,
	.Crag_Sunset   = .Mountain,
	.Dusk          = .Dusk,
	.Night_Candles = .Night,
	.Deep_Night    = .Deep_Night,
	.Forest_Night  = .Forest,
	.River_Dawn    = .River,
	.Crag_Day      = .Mountain,
	.Temple_Dusk   = .Dusk,
	.Venus_Evening = .Garden,
	.Pasture_Day   = .Pasture_Day,
	.Pasture_Evening = .Pasture_Evening,
}

// What the mixer plays: the act's music (silent while the screen goes
// black at the end of an act), the place's ambience, the music ducked under
// cards and menus.
update_sound :: proc(app: ^App) {
	audio.update()
	g := &app.game
	act := content.LEVELS[g.level_index].act
	going_black := app.black_t >= 0 && app.black_t < BLACK_OUT
	// the title theme while the palace sleeps behind the menus, the act's music in play
	mood := g.active ? ACT_MOOD[act] : audio.Mood_Id.Title
	audio.set_mood(going_black ? .None : mood)
	audio.set_key(ACT_KEY[act])
	audio.set_bed(going_black ? .None : SETTING_BED[game.setting_now(g)])
	duck: f32 = 0
	#partial switch app.screen {
	case .Fragment, .Mechanic, .Pause, .Settings, .Ending, .Card, .Levels, .Book:
		duck = 1
	}
	audio.set_duck(duck)
}

// BLACK_OUT: the screen goes black at the end of an act; BLACK_IN: it comes back.
BLACK_OUT :: 1.0
BLACK_IN :: 0.8

// On to the next level. Within an act Psyche flies on through the veil and
// arrives in the next level; at the end of an act the screen goes black and
// the next act opens with its own card or cutscene.
continue_story :: proc(app: ^App) {
	next := app.ending.level + 1
	if app.ending.ending != .Exit || content.closes_act(app.ending.level) || !content.is_built(next) {
		app.black_t = 0
		app.black_next = next
		return
	}
	if new_level(app, next) {
		game.begin(&app.game, arrival = true)
		app.screen = .Play
	}
}

@(private)
update_black :: proc(app: ^App, dt: f32) {
	if app.black_t < 0 {
		return
	}
	before := app.black_t
	app.black_t += dt
	if before < BLACK_OUT && app.black_t >= BLACK_OUT {
		start_level(app, app.black_next)
	}
	if app.black_t >= BLACK_OUT + BLACK_IN {
		app.black_t = -1
	}
}

@(private)
draw_black :: proc(app: ^App, w, h: f32) {
	if app.black_t < 0 {
		return
	}
	t := app.black_t
	a := t < BLACK_OUT ? t / BLACK_OUT : 1 - (t - BLACK_OUT) / BLACK_IN
	rl.DrawRectangleRec({0, 0, w, h}, {0, 0, 0, u8(clamp(a, 0, 1) * 255)})
}

// Restart the current level at once (no act card, no prologue).
// What the HUD needs from the app: where Psyche is on screen, how far R is held.
hud_input :: proc(app: ^App) -> ui.Hud_Input {
	g := &app.game
	w, h := canvas_size(app)
	view := render.scene_view(&app.scene, g, w, h)
	in_: ui.Hud_Input
	in_.psyche_screen = render.world_to_screen(view, g.psyche.pos + {0, 0, 0.8})
	in_.twice = app.cfg.restart_twice
	if !in_.twice && app.rest_t > REST_TAP && !app.rest_fired {
		in_.hold = clamp((app.rest_t - REST_TAP) / max(app.cfg.hold_time - REST_TAP, 0.1), 0, 1)
	}
	return in_
}

// R, or the brazier's button: a tap goes back to the last brazier lit;
// held for the time chosen in the settings (or pressed twice, if so chosen),
// the level starts again. Let go half way, nothing happens.
update_rest :: proc(app: ^App, button_down: bool) {
	g := &app.game
	dt := rl.GetFrameTime()
	app.rest_tap_t += dt
	twice := app.cfg.restart_twice
	if !input.down(.East) {
		app.east_block = false
	}
	pad_down := input.down(.East) && !app.east_block
	held := (rl.IsKeyDown(.R) || button_down || pad_down) && g.active && g.phase != .Prologue
	if held {
		if app.rest_t < 0 {
			app.rest_t = 0
			app.rest_fired = false
		} else {
			app.rest_t += dt
		}
		if !twice && !app.rest_fired && app.rest_t >= app.cfg.hold_time {
			app.rest_fired = true
			play_level(app)
		}
		return
	}
	if app.rest_t < 0 {
		return
	}
	tap := !app.rest_fired && (twice || app.rest_t < REST_TAP)
	app.rest_t = -1
	if !tap {
		return
	}
	if twice && app.rest_tap_t < REST_TWICE {
		app.rest_tap_t = 1e3
		play_level(app)
		return
	}
	app.rest_tap_t = 0
	switch {
	case !game.has_rest(g):
		game.hint(g, twice ? .Hint_No_Rest_Twice : .Hint_No_Rest, 4, true)
	case game.return_to_rest(g):
		if twice {
			game.hint(g, .Hint_Again_Twice, 2.5, true)
		}
	case:
		// already at the brazier, nothing changed
		game.hint(g, twice ? .Hint_Again_Twice : .Hint_Hold, 3, true)
	}
}

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
	if app.shooting && app.shots.record {
		dt = 1.0 / RECORD_FPS // a steady clock for a video, however slow the capture
		// the sounds of this frame, at the video's clock (frame 0 once the plan plays)
		if app.shots.step >= 1 {
			audio.start_log()
		}
		audio.set_log_time(f32(app.shots.frame) / RECORD_FPS)
	}
	app.time += dt
	g := &app.game
	u := &app.ui
	update_window_size(app)
	w, h := canvas_size(app)
	input.update(dt, app.shooting)
	switch app.cfg.pad_glyphs {
	case .Auto: input.choose_layout(nil)
	case .Xbox: input.choose_layout(.Xbox)
	case .PlayStation: input.choose_layout(.PlayStation)
	case .Nintendo: input.choose_layout(.Nintendo)
	}
	pad_names(app)
	if app.screen != app.focus_screen {
		// a new screen: the pad's focus starts on its first choice (the
		// level to continue from, in the level select)
		app.focus_screen = app.screen
		ui.reset_focus(u, app.screen == .Levels ? progress.current_level(app.prog) : 0)
	}
	ui.begin_frame(u, w, h)
	global_keys(app)

	// input that drives the game
	if app.screen == .Play && app.menu_fade < 0 {
		play_input(app)
	}
	paused := app.screen == .Pause || app.screen == .Fragment || app.screen == .Mechanic || (app.screen == .Settings && app.settings_from == .Pause)
	if !paused {
		game.update(g, dt)
		app.scene.see_through = app.cfg.see_through
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
		announce(app, progress.collect_fragment(&app.prog, game.fragment_index(g, g.fragment_last)))
		save_progress(app)
		if app.screen == .Play {
			app.screen = .Fragment
			app.fragment_t = 0
		}
	}
	if app.screen == .Fragment {
		app.fragment_t += dt
	}
	if g.mechanic_new {
		g.mechanic_new = false
		if app.screen == .Play {
			app.screen = .Mechanic
			app.mechanic_t = 0
			g.teach_card = true
		}
	}
	if app.screen == .Mechanic {
		app.mechanic_t += dt
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
	update_black(app, dt)
	update_sound(app)
	shot := ""
	if app.shooting {
		done: bool
		shot, done = shots_update(app, &app.shots, dt)
		app.quit ||= done
	}

	// drawing (widgets also report their clicks here)
	rl.BeginDrawing()
	// the graphics quality draws the world through a canvas (smaller, or twice
	// the size), or straight to the screen (High, with the window's MSAA)
	k := render.canvas_scale(app.cfg.quality, w, h)
	// the settings sheet is glass: the world frosted under it comes from the
	// canvas (drawn there apart at High, so the picture beside the sheet keeps
	// its MSAA while the quality is judged)
	app.ui.has_glass = app.screen == .Settings
	if app.ui.has_glass && k == 0 {
		render.post_begin(&app.post, w, h)
		draw_world(app, w, h)
		render.post_end(&app.post)
		app.ui.glass = render.post_glass(&app.post)
	}
	if k > 0 {
		render.post_begin(&app.post, w * k, h * k)
	} else if app.has_target {
		rl.BeginTextureMode(app.target)
	}
	draw_world(app, k > 0 ? w * k : w, k > 0 ? h * k : h)
	if k > 0 {
		render.post_end(&app.post)
		if app.ui.has_glass {
			app.ui.glass = render.post_glass(&app.post)
		}
		if app.has_target {
			rl.BeginTextureMode(app.target)
		}
		reset_canvas(w, h)
		render.post_draw(&app.post, w, h)
	}
	render.draw_veil(&app.renderer, g, w, h, app.time)
	if !(app.shooting && app.shots.no_ui) {
		draw_screens(app)
	}
	draw_black(app, w, h)
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

// The world, at w x h pixels, into whatever is being drawn to now.
draw_world :: proc(app: ^App, w, h: f32) {
	reset_canvas(w, h)
	rl.ClearBackground({5, 5, 15, 255})
	render.draw_world(&app.renderer, &app.scene, &app.game, render.scene_view(&app.scene, &app.game, w, h), app.time)
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

// The texts that name keys follow the device in hand (and the pad's family).
pad_names :: proc(app: ^App) {
	if !input.using_pad() {
		i18n.set_pad(nil)
		return
	}
	switch input.layout() {
	case .Xbox: i18n.set_pad(i18n.PAD_XBOX)
	case .PlayStation: i18n.set_pad(i18n.pad_playstation())
	case .Nintendo: i18n.set_pad(i18n.PAD_NINTENDO)
	}
}

// The pad's Start and East (back) over the screens, as Esc and Enter.
pad_keys :: proc(app: ^App) {
	if input.take(.Start) {
		#partial switch app.screen {
		case .Play:
			app.screen = .Pause
		case .Pause:
			app.screen = .Play
		case .Settings:
			close_settings(app)
		case .Card:
			dismiss_act_card(app)
		case .Fragment:
			close_fragment(app)
		case .Mechanic:
			close_mechanic(app)
		}
	}
	if app.screen != .Play && input.pressed(.East) {
		used := true
		#partial switch app.screen {
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
		case .Mechanic:
			close_mechanic(app)
		case:
			used = false
		}
		if used {
			input.consume(.East)
			app.east_block = true
		}
	}
}

global_keys :: proc(app: ^App) {
	pad_keys(app)
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
		case .Mechanic:
			close_mechanic(app)
		case .Title, .Ending:
		}
	}
	if app.screen == .Card && (rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.SPACE)) {
		dismiss_act_card(app)
	}
	if app.screen == .Fragment && (rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER)) {
		close_fragment(app)
	}
	if app.screen == .Mechanic && (rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) || rl.IsKeyPressed(.SPACE)) {
		close_mechanic(app)
	}
}

close_mechanic :: proc(app: ^App) {
	if app.mechanic_t > 0.8 {
		app.screen = .Play
		app.game.teach_card = false
		app.game.teach_after = 0
	}
}

MECHANIC_CARD := [level.Mechanic][2]i18n.Key {
	.None    = {.Mech_New, .Mech_New},
	.Veiled  = {.Mech_Veiled_Title, .Mech_Veiled},
	.Handle  = {.Mech_Handle_Title, .Mech_Handle},
	.Ants    = {.Mech_Ants_Title, .Mech_Ants},
	.Time    = {.Mech_Time_Title, .Mech_Time},
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
		// any key, click or button: skip the scene, then start
		if rl.GetKeyPressed() != .KEY_NULL || rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT) || input.any_pressed() {
			game.prologue_advance(g)
		}
		return
	}
	// R (the brazier, held: the level again) is read with the HUD: update_rest
	// the skills on their number keys, Space for the action of the place
	if rl.IsKeyPressed(.ONE) || rl.IsKeyPressed(.KP_1) || rl.IsKeyPressed(.L) || rl.IsMouseButtonPressed(.RIGHT) {
		game.toggle_lamp(g)
	}
	if (rl.IsKeyPressed(.TWO) || rl.IsKeyPressed(.KP_2) || rl.IsKeyPressed(.F)) && game.has_skill(g, .Handle) {
		game.use_handle(g)
	}
	if (rl.IsKeyPressed(.THREE) || rl.IsKeyPressed(.KP_3)) && game.has_skill(g, .Ants) {
		game.call_ants(g)
	}
	if rl.IsKeyPressed(.SPACE) {
		place(g)
	}
	if rl.IsKeyPressed(.Q) || rl.IsKeyPressed(.LEFT) {
		game.request_turn(g, -1)
	}
	if rl.IsKeyPressed(.E) || rl.IsKeyPressed(.RIGHT) {
		game.request_turn(g, 1)
	}
	pad_play(app)
	if app.ui.pressed && !ui.over_ui(&app.ui) {
		w, h := canvas_size(app)
		view := render.scene_view(&app.scene, g, w, h)
		game.click(g, render.screen_to_proto(view, app.ui.mouse))
	}
}

// The action of the place: into the cave at her feet, or the ants called to
// the seed beside her.
place :: proc(g: ^game.Game) -> bool {
	if game.enter_cave(g) {
		return true
	}
	return game.at_seed(g) && game.call_ants(g)
}

// The pad in play: the stick (or the d-pad) steers Psyche; each skill on its
// own button, as its slot shows (West the lamp, North the handle, LT the
// ants; RT waits for the last skill), South into the cave at her feet; the
// shoulders or a flick of the right stick turn the palace. East, the brazier,
// is read with the HUD (update_rest). One button, one thing: South does not
// stand in for a skill, so a button never does what another one shows.
pad_play :: proc(app: ^App) {
	g := &app.game
	dir, fresh := input.steer()
	game.steer(g, dir, fresh)
	if input.take(.West) {
		game.toggle_lamp(g)
	}
	if input.take(.North) && game.has_skill(g, .Handle) {
		game.use_handle(g)
	}
	if input.take(.LT) && game.has_skill(g, .Ants) {
		game.call_ants(g)
	}
	if input.take(.South) {
		game.enter_cave(g)
	}
	turn := input.flick()
	if input.take(.LB) {
		turn = -1
	}
	if input.take(.RB) {
		turn = 1
	}
	if turn != 0 {
		game.request_turn(g, turn)
	}
}

draw_screens :: proc(app: ^App) {
	g := &app.game
	u := &app.ui
	// the accessibility settings, for the HUD and the game
	u.hud_size = app.cfg.hud_size
	u.labels_always = app.cfg.skill_labels == .Always
	u.reduce_motion = app.cfg.reduce_motion
	g.endless_oil = app.cfg.endless_oil
	g.reduce_motion = app.cfg.reduce_motion
	u.toast_visible = app.toast_count > 0
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
			ui.book_open(&app.book)
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
		if ui.book(u, app.prog, &app.book) {
			app.screen = .Title
		}
	case .Card:
		c := app.act_card
		alpha: f32 = c.out_t >= 0 ? 1 - c.out_t / CARD_FADE : 1
		if ui.act_card(u, c.act, c.t, alpha, c.unbuilt) {
			dismiss_act_card(app)
		}
	case .Play:
		act := ui.draw_hud(u, g, hud_input(app))
		if act.lamp {
			game.toggle_lamp(g)
		}
		if act.handle {
			game.use_handle(g)
		}
		if act.ants {
			game.call_ants(g)
		}
		if act.place {
			place(g)
		}
		if act.turn != 0 {
			game.request_turn(g, act.turn)
		}
		update_rest(app, act.rest_down)
		if app.menu_fade >= 0 {
			// the title menu rises and fades away as the game begins
			k := app.menu_fade / MENU_FADE
			ui.title_menu(u, 1 - k, 40 * k)
		}
	case .Fragment:
		ui.draw_hud(u, g)
		if ui.fragment_card(u, game.fragment_key(g, g.fragment_last), app.fragment_t) {
			close_fragment(app)
		}
	case .Mechanic:
		ui.draw_hud(u, g)
		keys := MECHANIC_CARD[g.data.mechanic]
		if ui.mechanic_card(u, keys[0], keys[1], app.mechanic_t) {
			close_mechanic(app)
		}
	case .Pause:
		// the pause stands alone over the game: no HUD under its menu
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
			if app.black_t < 0 {
				continue_story(app)
			}
		case .Retry:
			if app.ending.ending == .Exit {
				// back through the veil into the same level
				if new_level(app, app.ending.level) {
					game.begin(g, prologue = false, arrival = true)
					app.screen = .Play
				}
			} else {
				play_level(app)
			}
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
	// sliders are saved when the panel closes, not on every step of a drag
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
