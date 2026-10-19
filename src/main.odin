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
import "fx"
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
Notice :: ui.Notice // a field of App is named ui

Screen :: enum u8 {
	Title,
	Levels,
	Games, // the games side by side: continue one, start one, erase one
	Book,
	Codex, // Psyche's Notebook: the mechanics met so far
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
	prog:            progress.Progress, // the game in play (the slot `cfg.slot`)
	playing:         bool, // that game has begun (its slot holds a save)
	slots:           [progress.SLOTS]progress.Slot_Info, // read when the list of games opens
	games:           ui.Games_State,
	renderer:        render.Renderer,
	ui:              ui.Ui,
	game:            game.Game,
	scene:           render.Scene,
	screen:          Screen,
	settings_from:   Screen,
	codex_from:      Screen,
	menu_fade:       f32, // < 0 unless the title menu is fading out
	card_t:          f32, // time on the ending card
	ending:          Ending_Info,
	act_card:        Act_Card,
	book:            Book_State,
	fragment_t:      f32, // time on the fragment card
	mechanic_t:      f32, // time on the mechanic card
	toasts:          [MAX_TOASTS]Notice, // notices waiting to be shown
	toast_count:     int,
	toast_t:         f32,
	carried:         struct {
		lightings, lamp_par: int, // the level's dioramas already played (its lamp achievement)
	},
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
	passage_t:       f32, // < 0, or time since Continue (or Retry) left the card over a level that broke up
	passage_next:    int, // the level that rises after it
	rest_t:          f32, // how long R (or the brazier's button) has been held, < 0 when up
	rest_fired:      bool, // this hold has already restarted the level
	rest_tap_t:      f32, // time since the last tap of R (pressed twice: the level again)
	east_block:      bool, // the pad's East closed a menu: it is not the brazier until let go
	skip_t:          f32, // how long the cutscene's skip has been held, < 0 when up
	lamp_down:       bool, // the lamp's key, button or slot was held last frame
	dead_ends:       Dead_Ends,
	focus_screen:    Screen, // the screen the UI's focus belongs to
	levels:          Levels_Screen,
	stage:           f32, // 0 .. 1: the diorama moved to the right for a side panel (the level select, the settings)
}

STAGE_TIME :: 0.7 // the diorama moving aside for a side panel, and back

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
		progress.migrate()
		app.prog, app.playing = progress.load(app.cfg.slot)
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
	if app.shots.has_quality {
		app.cfg.quality = app.shots.quality
	}
	ui.init(&app.ui)
	if !load_current(app) {
		return false
	}
	app.screen = .Title
	app.menu_fade = -1
	app.black_t = -1
	app.passage_t = -1
	app.rest_t = -1
	app.rest_tap_t = 1e3
	app.skip_t = -1
	return true
}

shutdown :: proc(app: ^App) {
	save_settings(app)
	game.destroy(&app.game)
	shutdown_levels(app)
	if app.has_target {
		rl.UnloadRenderTexture(app.target)
	}
	ui.shutdown(&app.ui)
	render.post_shutdown(&app.post)
	render.shutdown(&app.renderer)
	audio.shutdown()
	drop_dead_ends(&app.dead_ends)
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
new_level :: proc(app: ^App, index: int, diorama := 0) -> bool {
	g := &app.game
	source := content.LEVELS[index].source
	if app.shooting && app.shots.file != "" && index == app.shots.level {
		source = app.shots.file
	}
	if err, failed := game.load_text(g, index, source, diorama).?; failed {
		fmt.eprintfln("level %s, line %d: %s", content.LEVELS[index].id, err.line, err.message)
		return false
	}
	g.trust_allowed = progress.game_finished(app.prog)
	for _, i in g.data.fragments {
		if game.fragment_index(g, i) in app.prog.fragments {
			g.fragments_known += {i}
		}
	}
	want_dead_ends(app, index, diorama, level.dioramas(source)[diorama], keep = source == content.LEVELS[index].source)
	if diorama == 0 {
		app.carried = {}
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
	.Venus_Day     = .Garden,
	.Styx_Night    = .Styx,
	.Styx_Day      = .Styx,
	.Styx_Evening  = .Styx,
	.Tower_Dusk    = .Mountain,
	.Taenarus      = .Styx,
	.Taenarus_Night = .Styx,
	.Dis           = .Deep_Night,
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
	fire, pan := game.fire_near(g)
	audio.set_near(.Fire, g.active && !going_black ? fire : 0, pan)
	duck: f32 = 0
	#partial switch app.screen {
	case .Fragment, .Mechanic, .Pause, .Settings, .Ending, .Card, .Levels, .Games, .Book, .Codex:
		duck = 1
	}
	audio.set_duck(duck)
}

// BLACK_OUT: the screen goes black at the end of an act; BLACK_IN: it comes back.
BLACK_OUT :: 1.0
BLACK_IN :: 0.8

// On to the next level. Within an act the next level comes into focus
// where the last broke up, and rises (after the boat, Psyche arrives
// through the veil); at the end of an act the screen goes black and the next
// act opens with its own card or cutscene.
continue_story :: proc(app: ^App) {
	next := app.ending.level + 1
	if app.ending.ending != .Exit || content.closes_act(app.ending.level) || !content.is_built(next) {
		app.black_t = 0
		app.black_next = next
		return
	}
	arrive_at(app, next)
}

// Into level `index` after an exit: into focus where the one played broke
// up, through the veil if the boat took her.
arrive_at :: proc(app: ^App, index: int) {
	if app.game.parting {
		start_passage(app, index)
		return
	}
	if new_level(app, index) {
		game.begin(&app.game, prologue = index != app.ending.level, arrival = true)
		app.screen = .Play
	}
}

// Between two levels: as the level breaks up the world goes out of focus
// under the ending card (PASSAGE_BLUR); once the player goes on the card
// fades (PASSAGE_CLOSE), the next level is loaded out of focus, the last one
// fading over it (PASSAGE_HELD), and comes into focus as it rises
// (PASSAGE_FOCUS). The dioramas of one level have none: one breaks up, the
// next rises, in the open.
PASSAGE_BLUR :: 0.9 // into the break up, when the world starts to blur
PASSAGE_CLOSE :: 0.45
PASSAGE_HELD :: 0.6
PASSAGE_FOCUS :: 1.1

// Leave the card over the level that broke up, on into level `index`.
@(private)
start_passage :: proc(app: ^App, index: int) {
	app.passage_t = 0
	app.passage_next = index
	audio.play(.Wind, -18, 1.4)
}

@(private)
update_passage :: proc(app: ^App, dt: f32) {
	if app.passage_t < 0 {
		return
	}
	before := app.passage_t
	app.passage_t += dt
	if before < PASSAGE_CLOSE && app.passage_t >= PASSAGE_CLOSE {
		render.post_hold(&app.post)
		if new_level(app, app.passage_next) {
			game.begin(&app.game, prologue = app.passage_next != app.ending.level, arrival = true, veiled = false)
			app.game.arrive_traced = true
			app.screen = .Play
		}
	}
	if app.passage_t >= PASSAGE_CLOSE + max(PASSAGE_HELD, PASSAGE_FOCUS) {
		app.passage_t = -1
	}
}

// How far the world is out of focus between the levels (0 .. 1), and how
// much of the last level, out of focus, still covers the next.
@(private)
passage_blur :: proc(app: ^App) -> (blur, held: f32) {
	g := &app.game
	if t := app.passage_t; t >= 0 {
		if t < PASSAGE_CLOSE {
			return 1, 0
		}
		blur = 1 - fx.sine_in_out(fx.progress(t, PASSAGE_CLOSE, PASSAGE_FOCUS))
		held = 1 - fx.sine_in_out(fx.progress(t, PASSAGE_CLOSE, PASSAGE_HELD))
		return
	}
	if g.parting && !game.leads_on(g) && (g.phase == .Ending_Exit || g.phase == .Finished) {
		t := g.phase == .Finished ? game.PART_END : g.phase_t
		blur = fx.sine_in_out(fx.progress(t, PASSAGE_BLUR, game.PART_END - PASSAGE_BLUR))
	}
	return
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
	in_.skip = max(app.skip_t, 0) / app.cfg.hold_time
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
		game.hint(g, .Hint_No_Rest, 4, true)
	case game.return_to_rest(g):
		if twice {
			game.hint(g, .Hint_Again_Twice, 2.5, true)
		}
	case:
		// already at the brazier, nothing changed
		game.hint(g, twice ? .Hint_Again_Twice : .Hint_Hold, 3, true)
	}
}

// Start the level again: the diorama being played (the dioramas before it are done).
play_level :: proc(app: ^App) {
	carried := app.carried
	if new_level(app, app.game.level_index, app.game.diorama) {
		app.carried = carried
		game.begin(&app.game, prologue = false)
		app.screen = .Play
	}
}

// Start level `index`: the act card first when the level opens an act. A
// level not built yet shows only its act card, then the title. A level of
// several dioramas left half way starts again from the diorama reached,
// unless `from_start`.
// `from_title`: the sleeping palace behind the title is this level, wake it.
start_level :: proc(app: ^App, index: int, from_title := false, from_start := false) {
	if !content.is_built(index) {
		open_act_card(app, content.LEVELS[index].act, true)
		return
	}
	if from_start && app.prog.resume.level == index && app.prog.resume.diorama > 0 {
		app.prog.resume = {}
		save_progress(app)
	}
	diorama := progress.resume_at(app.prog, index)
	if !(from_title && app.game.level_index == index && app.game.diorama == diorama && !app.game.active) {
		if !new_level(app, index, diorama) {
			return
		}
	}
	if diorama > 0 {
		app.carried = {app.prog.resume.lightings, app.prog.resume.lamp_par}
	}
	// a level with a prologue opens its act with the cutscene, not the card
	if content.opens_act(index) && diorama == 0 && !app.game.data.has_prologue {
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

// The exit of a diorama that is not the level's last: it has broken up, the
// next one rises into place in the open (no card, no blur between them).
next_diorama :: proc(app: ^App) {
	g := &app.game
	carried := app.carried
	carried.lightings += g.lightings
	carried.lamp_par += int(g.data.lamp_par)
	if new_level(app, g.level_index, g.diorama + 1) {
		app.carried = carried
		game.begin(g, arrival = true, veiled = false)
		// a game left now starts again from this diorama
		app.prog.resume = {g.level_index, g.diorama, carried.lightings, carried.lamp_par}
		save_progress(app)
	}
}

// The level is over: record it, and show the ending card.
finish_level :: proc(app: ^App) {
	g := &app.game
	r := progress.Result {
		level     = g.level_index,
		trust     = g.ending == .Trust,
		lightings = app.carried.lightings + g.lightings,
		lamp_par  = app.carried.lamp_par + int(g.data.lamp_par),
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
		notify(app, a)
	}
}

// A notice queued for the corner.
notify :: proc(app: ^App, n: ui.Notice) {
	if app.toast_count < MAX_TOASTS {
		app.toasts[app.toast_count] = n
		app.toast_count += 1
	}
}

// Toasts wait while a fragment card is open, and each comes in with a soft chime.
@(private)
update_toasts :: proc(app: ^App, dt: f32) {
	if app.toast_count == 0 || app.screen == .Fragment {
		return
	}
	if app.toast_t == 0 {
		audio.play(.Seam, -20, audio.semitones(12))
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
		ui.reset_focus(u)
		if app.screen == .Levels {
			enter_levels(app)
		}
		if app.screen == .Games {
			read_slots(app)
		}
	}
	ui.begin_frame(u, w, h)
	global_keys(app)

	// input that drives the game
	if app.screen == .Play && app.menu_fade < 0 {
		play_input(app)
	}
	paused := app.screen == .Pause || app.screen == .Fragment || app.screen == .Mechanic || (app.screen == .Settings && app.settings_from == .Pause) || (app.screen == .Codex && app.codex_from != .Title)
	if !paused {
		poll_dead_ends(app)
		game.update(g, dt)
		app.scene.see_through = app.cfg.see_through
		app.scene.highlight = app.cfg.highlight
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
		fragment := game.fragment_index(g, g.fragment_last)
		unlocked, new_page := progress.collect_fragment(&app.prog, fragment)
		if new_page {
			act := content.LEVELS[content.FRAGMENTS[fragment].level].act
			found, total := progress.act_fragments(app.prog, act)
			notify(app, ui.Page_Notice{act, found, total})
		}
		announce(app, unlocked)
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
		if g.ending == .Exit && game.leads_on(g) {
			next_diorama(app)
		} else {
			finish_level(app)
		}
	}
	if app.screen == .Ending {
		app.card_t += dt
	}
	if app.screen == .Card {
		update_act_card(app, dt)
	}
	update_toasts(app, dt)
	update_black(app, dt)
	update_passage(app, dt)
	update_levels(app, dt)
	side := app.screen == .Levels || app.screen == .Games || app.screen == .Settings || app.screen == .Codex
	app.stage = clamp(app.stage + (side ? dt : -dt) / STAGE_TIME, 0, 1)
	app.scene.stage = app.stage
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
	blur, held := passage_blur(app)
	if k == 0 && (blur > 0 || held > 0) {
		k = 1 // out of focus: through a canvas, whatever the quality
	}
	draw_level_picture(app)
	if k > 0 {
		render.post_begin(&app.post, w * k, h * k)
	} else if app.has_target {
		rl.BeginTextureMode(app.target)
	}
	draw_world(app, k > 0 ? w * k : w, k > 0 ? h * k : h)
	if k > 0 {
		render.post_end(&app.post)
		if blur > 0 || held > 0 {
			render.post_blur(&app.post, w, h)
		}
		if app.has_target {
			rl.BeginTextureMode(app.target)
		}
		reset_canvas(w, h)
		render.post_draw(&app.post, w, h, blur, held)
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

// Back out of the screen on top (Esc, or the pad's Start or East): true if
// there was one to leave.
back :: proc(app: ^App) -> bool {
	#partial switch app.screen {
	case .Pause:
		app.screen = .Play
	case .Settings:
		close_settings(app)
	case .Levels:
		leave_levels(app, true)
	case .Games:
		app.screen = .Title
	case .Book:
		app.screen = .Title
	case .Codex:
		app.screen = app.codex_from
	case .Card:
		dismiss_act_card(app)
	case .Fragment:
		close_fragment(app)
	case .Mechanic:
		close_mechanic(app)
	case:
		return false
	}
	return true
}

// Esc, or the pad's Start: the pause in play, back anywhere else.
pause_or_back :: proc(app: ^App) {
	if app.screen == .Play {
		app.screen = .Pause
	} else {
		back(app)
	}
}

// The pad's Start and East (back) over the screens, as Esc.
pad_keys :: proc(app: ^App) {
	if input.take(.Start) {
		pause_or_back(app)
	}
	if app.screen != .Play && input.pressed(.East) && back(app) {
		input.consume(.East)
		app.east_block = true
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
		pause_or_back(app)
	}
	if app.screen == .Card && (rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.SPACE)) {
		dismiss_act_card(app)
	}
	if app.screen == .Codex && (rl.IsKeyPressed(.C) || input.take(.West)) {
		back(app) // the key that opened it closes it
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
	.Time    = {.Mech_Time_Title, .Mech_Time},
	.Eagle   = {.Mech_Eagle_Title, .Mech_Eagle},
	.Ferry   = {.Mech_Ferry_Title, .Mech_Ferry},
	.Flip    = {.Mech_Flip_Title, .Mech_Flip},
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
		skip_input(app)
		return
	}
	// R (the brazier, held: the level again) is read with the HUD: update_rest
	// the two tools on their number keys (the lamp is read with the HUD:
	// update_lamp), Space for the action of the place
	if rl.IsKeyPressed(.TWO) || rl.IsKeyPressed(.KP_2) || rl.IsKeyPressed(.F) {
		game.use_spindle(g)
	}
	if rl.IsKeyPressed(.SPACE) {
		place(g)
	}
	if rl.IsKeyPressed(.TAB) {
		game.point_at_psyche(g)
	}
	if rl.IsKeyPressed(.C) {
		open_codex(app)
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

SKIP_STEPS :: 4 // the skip's ring fills in steps: a pluck and a shake at each, higher and stronger

// The cutscene: held down (Space, Enter, the left button, the pad's South or
// East) for the hold time of the settings, it is skipped to its end, the ring
// filling with plucks and the pad shaking more at each step; let go half way,
// nothing. With the restart pressed twice (accessibility) a press skips it.
// Once the prompt is up, any key, click or button starts the play.
@(private)
skip_input :: proc(app: ^App) {
	g := &app.game
	if game.prologue_ready(g) {
		app.skip_t = -1
		if rl.GetKeyPressed() != .KEY_NULL || rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT) || input.any_pressed() {
			game.prologue_advance(g)
		}
		return
	}
	down := rl.IsKeyDown(.SPACE) || rl.IsKeyDown(.ENTER) || rl.IsMouseButtonDown(.LEFT) || input.down(.South) || input.down(.East)
	if app.cfg.restart_twice {
		if rl.GetKeyPressed() != .KEY_NULL || rl.IsMouseButtonPressed(.LEFT) || input.any_pressed() {
			game.prologue_advance(g)
		}
		return
	}
	if !down {
		app.skip_t = -1
		return
	}
	was := max(app.skip_t, 0) / app.cfg.hold_time
	app.skip_t = max(app.skip_t, 0) + rl.GetFrameTime()
	now := app.skip_t / app.cfg.hold_time
	if now >= 1 {
		audio.play(.Wind, -12)
		input.rumble(0.6, 0.25)
		game.prologue_advance(g)
		app.skip_t = -1
		return
	}
	if step := int(now * SKIP_STEPS); step > int(was * SKIP_STEPS) {
		audio.play(.Tap, -18, SKIP_PITCH[step - 1])
		input.rumble(0.12 * f32(step), 0.08)
	}
}

@(private)
SKIP_PITCH := [SKIP_STEPS - 1]f32{1, 5.0 / 4, 3.0 / 2}

// The lamp burns while its key (1, L, the right button), the pad's LT or its
// slot is held, and goes out when let go; in the accessibility setting a
// press lights it and the next one puts it out.
update_lamp :: proc(app: ^App, slot_down: bool) {
	g := &app.game
	down := rl.IsKeyDown(.ONE) || rl.IsKeyDown(.KP_1) || rl.IsKeyDown(.L) || rl.IsMouseButtonDown(.RIGHT) || input.down(.LT) || slot_down
	was := app.lamp_down
	app.lamp_down = down
	if app.menu_fade >= 0 || g.phase == .Prologue {
		return
	}
	if down && !was && (app.cfg.lamp_toggle || !g.lamp_on) {
		game.toggle_lamp(g)
	} else if !down && was && !app.cfg.lamp_toggle && g.lamp_on {
		game.toggle_lamp(g)
	}
}

// The action of the place: into the cave at her feet, the eagle called,
// Charon's boat boarded (at the exit, or a ferry's).
place :: proc(g: ^game.Game) -> bool {
	return game.enter_cave(g) || game.call_eagle(g) || game.board_boat(g) || game.board_ferry(g)
}

// The pad in play: the stick (or the d-pad) steers Psyche; the two tools on
// the triggers, as their slots show (LT the lamp, read with the HUD:
// update_lamp; RT the spindle), South the action of the place (into the cave
// at her feet, the eagle called), North the arrow over Psyche; the shoulders or a flick
// of the right stick turn the palace. East, the brazier, is read with the HUD
// (update_rest). One button, one thing: South does not stand in for a tool,
// so a button never does what another one shows.
pad_play :: proc(app: ^App) {
	g := &app.game
	dir, fresh := input.steer()
	game.steer(g, dir, fresh)
	if input.take(.RT) {
		game.use_spindle(g)
	}
	if input.take(.South) {
		place(g)
	}
	if input.take(.North) {
		game.point_at_psyche(g)
	}
	if input.take(.West) {
		open_codex(app)
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
	i18n.set_variant(.Lamp_Toggle, app.cfg.lamp_toggle)
	i18n.set_variant(.Restart_Twice, app.cfg.restart_twice)
	g.reduce_motion = app.cfg.reduce_motion
	u.toast_visible = app.toast_count > 0 && app.screen != .Fragment
	switch app.screen {
	case .Title:
		act := ui.title_menu(u, app.playing)
		if rl.IsKeyPressed(.ENTER) {
			act = .Play
		}
		switch act {
		case .Play:
			start_level(app, progress.current_level(app.prog), true)
		case .Levels:
			app.screen = .Levels
		case .Games:
			app.screen = .Games
		case .Book:
			ui.book_open(&app.book)
			app.screen = .Book
		case .Codex:
			open_codex(app)
		case .Settings:
			open_settings(app)
		case .Quit:
			app.quit = true
		case .None, .Resume, .Restart, .Main_Menu, .Retry, .Next, .Back:
		}
	case .Games:
		chosen, erase, back := ui.games_menu(u, app.slots[:], app.cfg.slot, &app.games)
		if erase > 0 {
			erase_game(app, erase)
		} else if chosen > 0 {
			play_game(app, chosen)
		} else if back {
			app.screen = .Title
		}
	case .Levels:
		chosen, from_start, back := ui.level_select(u, app.prog, &app.levels.sel, app.levels.pictures[:], g, levels_veil(app))
		if chosen >= 0 {
			leave_levels(app, false)
			start_level(app, chosen, from_start = from_start)
		} else if back {
			leave_levels(app, true)
		}
	case .Book:
		if ui.book(u, app.prog, &app.book) {
			app.screen = .Title
		}
	case .Codex:
		in_play := app.codex_from != .Title
		reach := progress.current_level(app.prog)
		if in_play {
			reach = max(reach, g.level_index)
		}
		if ui.codex(u, g, reach, in_play) {
			back(app)
		}
	case .Card:
		c := app.act_card
		alpha: f32 = c.out_t >= 0 ? 1 - c.out_t / CARD_FADE : 1
		if ui.act_card(u, c.act, c.t, alpha, c.unbuilt) {
			dismiss_act_card(app)
		}
	case .Play:
		act := ui.draw_hud(u, g, hud_input(app))
		update_lamp(app, act.lamp_down)
		if act.spindle {
			game.use_spindle(g)
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
			ui.title_menu(u, app.playing, 1 - k, 40 * k)
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
		switch ui.pause_menu(u, g.data.has_lamp, g.level_index, g.diorama, g.dioramas) {
		case .Resume:
			app.screen = .Play
		case .Restart:
			play_level(app)
		case .Codex:
			open_codex(app)
		case .Settings:
			open_settings(app)
		case .Main_Menu:
			to_title(app)
		case .None, .Play, .Levels, .Games, .Book, .Quit, .Retry, .Next, .Back:
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
		going := app.passage_t >= 0 || app.black_t >= 0
		gone := app.passage_t >= 0 ? fx.progress(app.passage_t, 0, PASSAGE_CLOSE) : 0
		act := ui.ending_card(u, app.ending, app.prog, app.card_t, gone)
		if going {
			act = .None // on its way out
		}
		switch act {
		case .Next:
			continue_story(app)
		case .Retry:
			if app.ending.ending == .Exit {
				arrive_at(app, app.ending.level) // the same level rises again
			} else {
				play_level(app)
			}
		case .Main_Menu:
			to_title(app)
		case .None, .Play, .Levels, .Games, .Book, .Codex, .Settings, .Quit, .Resume, .Restart, .Back:
		}
	}
	if u.toast_visible {
		ui.toast(u, app.toasts[0], app.toast_t)
	}
}

// Back to the title, over the level the player would continue from.
to_title :: proc(app: ^App) {
	if load_current(app) {
		app.screen = .Title
	}
}

// Load the level the player would continue from, at the diorama reached.
load_current :: proc(app: ^App) -> bool {
	index := progress.current_level(app.prog)
	return new_level(app, index, progress.resume_at(app.prog, index))
}

open_codex :: proc(app: ^App) {
	app.codex_from = app.screen
	app.screen = .Codex
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
		app.playing = progress.save(app.prog, app.cfg.slot) || app.playing
	}
}

// --- the games ----------------------------------------------------------------------

@(private)
read_slots :: proc(app: ^App) {
	app.games = {sel = app.cfg.slot}
	for &info, i in app.slots {
		info = app.shooting ? {} : progress.peek(i + 1)
	}
	if app.shooting {
		app.slots[0] = {used = true, prog = app.prog} // the shots' own game, never on disk
	}
}

// Play the game of a slot (an empty one: a new game), from where it stands.
@(private)
play_game :: proc(app: ^App, slot: int) {
	app.cfg.slot = slot
	save_settings(app)
	app.prog, app.playing = app.slots[slot - 1].prog, app.slots[slot - 1].used
	start_level(app, progress.current_level(app.prog), true)
}

// A game erased for good; the one in play starts again from nothing.
@(private)
erase_game :: proc(app: ^App, slot: int) {
	if !app.shooting {
		progress.erase(slot)
	}
	app.slots[slot - 1] = {}
	if slot == app.cfg.slot {
		app.prog, app.playing = {}, false
		load_current(app)
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
