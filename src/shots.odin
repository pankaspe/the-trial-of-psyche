// Scripted screenshots for visual checks: `trial-of-psyche --shots DIR` goes
// through the menus and plays a fixed sequence through level I.4, saves PNGs
// into DIR and quits. `--level ID` (e.g. I.2) tours that level instead: its
// act card, the four views in the dark, the lamp, the fragment and the end.
// The user's settings and progress are neither read nor written in this mode.
package main

import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

import "audio"
import "content"
import "game"
import "iso"
import "render"
import pl "palace"
import "settings"
import "ui"

Shot_Step :: struct {
	wait: f32, // seconds after the previous step
	name: string, // screenshot to take after the action ("" = none)
	action: proc(app: ^App),
}

@(private = "file")
LAMP_LEVEL :: 3 // I.4, the level of the lamp
@(private = "file")
BALCONY :: iso.Cell{6, 5, 4}
@(private = "file")
ROOF_ENTRY :: iso.Cell{13, 10, 6}
@(private = "file")
LAST_PILLAR :: iso.Cell{1, 10, 5} // the pillar before the fragment's

// Turn to a view that joins the last pillar to the fragment's and walk there.
@(private = "file")
walk_to_fragment :: proc(app: ^App) {
	g := &app.game
	place(app, LAST_PILLAR)
	for r in 0 ..< 4 {
		game.set_view(g, r)
		if game.walk_to(g, g.data.fragments[0]) {
			return
		}
	}
}

@(private = "file")
place :: proc(app: ^App, c: iso.Cell) {
	g := &app.game
	g.psyche.cell = c
	g.psyche.pos = pl.stand_world(&g.palace, c)
}

SHOT_SCRIPT := [?]Shot_Step {
	{1.5, "01_menu", nil},
	{0.1, "", proc(app: ^App) {open_settings(app)}},
	{0.6, "02_settings", nil},
	{0.1, "", proc(app: ^App) {app.ui.settings_tab = .Graphics}},
	{0.6, "02_settings_graphics", nil},
	{0.1, "", proc(app: ^App) {app.ui.settings_tab = .Audio}},
	{0.6, "02_settings_audio", nil},
	{0.1, "", proc(app: ^App) {app.ui.settings_tab = .Access}},
	{0.6, "02_settings_access", nil},
	{0.1, "", proc(app: ^App) {app.ui.settings_tab = .General}},
	{0.1, "", proc(app: ^App) {close_settings(app)}},
	{0.1, "", proc(app: ^App) {app.prog.completed = {3}; app.prog.fragments = {2, 3, 4}; app.screen = .Levels}},
	{0.6, "02b_levels", nil},
	{0.1, "", proc(app: ^App) {app.prog.achievements = {.No_Wasted_Light}; app.book_page = 0; app.screen = .Book}},
	{0.6, "02c_book", nil},
	{0.1, "", proc(app: ^App) {app.book_page = ui.BOOK_PAGES - 1}},
	{0.6, "02d_achievements", nil},
	{0.1, "", proc(app: ^App) {app.prog = {}; app.screen = .Title; new_level(app, LAMP_LEVEL)}},
	{0.1, "", proc(app: ^App) {open_act_card(app, .I, false)}},
	{4.0, "02e_act_card", nil},
	{0.1, "", proc(app: ^App) {dismiss_act_card(app)}},
	{3.0, "03_view0_dark", nil},
	{0.1, "", proc(app: ^App) {app.screen = .Pause}},
	{0.6, "03b_pause", nil},
	{0.1, "", proc(app: ^App) {app.screen = .Play}},
	{0.1, "", proc(app: ^App) {game.request_turn(&app.game, -1)}},
	{0.37, "04_mid_turn", nil},
	{0.1, "", proc(app: ^App) {game.set_view(&app.game, 0); place(app, {6, 9, 3}); game.walk_to(&app.game, {6, 7, 3})}},
	{3.0, "04b_candelabrum", nil},
	{0.1, "", proc(app: ^App) {game.set_view(&app.game, 3)}},
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
	{0.1, "", proc(app: ^App) {game.toggle_lamp(&app.game); game.set_view(&app.game, 0)}},
	{1.0, "10_roof_path_dark", proc(app: ^App) {place(app, ROOF_ENTRY)}},
	{0.5, "", proc(app: ^App) {game.toggle_lamp(&app.game)}},
	{1.6, "11_reveal", nil},
	{1.6, "12_drop", nil},
	{2.0, "13_collapse", nil},
	{4.0, "14_end_card", nil},
	{0.1, "", proc(app: ^App) {start_level(app, app.ending.level + 1)}},
	{4.0, "14b_act2_card", nil},
	{0.1, "", proc(app: ^App) {dismiss_act_card(app)}},
	{1.0, "14c_act2_begins", nil},
	// window modes (skipped on an offscreen canvas)
	{0.1, "", proc(app: ^App) {window_mode(app, true, {1600, 900})}},
	{1.5, "15_fullscreen", nil},
	{0.1, "", proc(app: ^App) {window_mode(app, false, {1280, 720})}},
	{1.5, "16_window_1280", nil},
	{0.1, "", proc(app: ^App) {window_mode(app, true, {1280, 720})}},
	{1.0, "", proc(app: ^App) {window_mode(app, false, {1600, 900})}},
	{1.5, "17_window_1600", nil},
}

// The tour of one level (--level ID): `Shots.level` is the slot.
LEVEL_TOUR := [?]Shot_Step {
	{0.5, "", proc(app: ^App) {start_level(app, app.shots.level)}},
	{1.5, "00a_start", nil},
	{2.5, "00b", nil},
	{3.0, "00c", nil},
	{3.5, "00d", nil},
	{3.0, "00e", nil},
	{3.0, "00f", nil},
	{3.0, "00g", nil},
	{4.0, "00h", nil},
	{2.0, "00i_prompt", nil},
	{0.1, "", proc(app: ^App) {
			if app.screen == .Card {dismiss_act_card(app)}
			for app.game.phase == .Prologue {game.prologue_advance(&app.game); if !game.prologue_ready(&app.game) {app.game.phase_t = 1e3}}
		}},
	{2.5, "01_view0", nil},
	{0.1, "", proc(app: ^App) {
			// walk to where the level teaches turning, if it does
			for h in app.game.data.hints {
				if h.key == .Hint_Turn {
					tour_walk(app, h.cell)
				}
			}
		}},
	{4.0, "01b_turn_hint", nil},
	{0.1, "", proc(app: ^App) {game.request_turn(&app.game, 1)}},
	{0.25, "01c_learned", nil}, // the tutorial card shows its tick
	{1.25, "02_view1", nil},
	{0.1, "", proc(app: ^App) {game.request_turn(&app.game, 1)}},
	{1.5, "03_view2", nil},
	{0.1, "", proc(app: ^App) {game.request_turn(&app.game, 1)}},
	{1.5, "04_view3", nil},
	{0.1, "", proc(app: ^App) {game.request_turn(&app.game, 1); game.toggle_lamp(&app.game)}},
	{1.5, "05_view0_lamp", nil},
	{0.1, "", proc(app: ^App) {if app.game.lamp_on {game.toggle_lamp(&app.game)}; tour_walk(app, app.game.data.fragments[0])}},
	{5.0, "06_fragment", nil},
	{0.1, "", proc(app: ^App) {if app.screen == .Fragment {close_fragment(app)}}},
	{0.1, "", proc(app: ^App) {tour_walk(app, app.game.data.exit)}},
	{0.8, "07_exit", nil},
	{1.0, "08_exit_wind", nil},
	{1.2, "08b_flight", nil},
	{3.5, "09_end_card", nil},
	// on through the veil into the next level (or to black at the end of an act)
	{0.1, "", proc(app: ^App) {
			if app.screen != .Ending {
				// a level the tour cannot finish (an ending, a puzzle): end it here
				app.game.ending = app.game.data.has_amore ? .Oil : .Exit
				finish_level(app)
			}
			continue_story(app)
		}},
	{0.8, "10a_arrival", nil},
	{0.5, "10b_arrival", nil},
	{0.6, "10c_arrival", nil},
	{2.0, "10d_arrived", nil},
}

// Walk to c from wherever Psyche is, trying every view (no animation).
@(private = "file")
tour_walk :: proc(app: ^App, c: iso.Cell) {
	g := &app.game
	for r in 0 ..< 4 {
		game.set_view(g, (g.palace.rot + r) % 4)
		if game.walk_to(g, c) {
			return
		}
	}
	// not reachable in one view: start from a neighbour, for the last step
	target := pl.node_index(&g.palace, c)
	if target < 0 {
		return // no such place (a level without an exit)
	}
	for r in 0 ..< 4 {
		game.set_view(g, r)
		for graph in ([]^pl.Graph{&g.palace.real, &g.palace.illusion}) {
			for nb in pl.neighbours(graph, target) {
				place(app, g.palace.nodes[nb].cell)
				if game.walk_to(g, c) {
					return
				}
			}
		}
	}
	place(app, c)
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
	level: int, // --level ID: the slot to tour, -1 = the full script
	quality: settings.Quality, // --quality NAME: the graphics quality (low, medium, high, ultra)
	has_quality: bool,
	plan:  bool, // --plan: play the solver's plan of the level, a shot after every decision
	record: bool, // --record (with --plan): every frame at RECORD_FPS instead, for a video
	cave_shot: int, // --plan: the last move shot at a cave's mouth (the action of the place shows)
	no_ui: bool, // --no-ui: the world only (backdrops for mockups and stills)
	survey: bool, // --survey: the level from the four views, band by band (a tall level), no walking
	frame: int,
	moves: [dynamic]pl.Plan_Step,
	arena: virtual.Arena,
	move:  int,
	shot:  int,
	step: int,
	t:    f32,
}

// Parse `--shots DIR [--size WxH]` from the command line.
shots_from_args :: proc(args: []string) -> (s: Shots, ok: bool) {
	s.level = -1
	for a in args {
		if a == "--plan" {
			s.plan = true
		}
		if a == "--record" {
			s.record = true
		}
		if a == "--no-ui" {
			s.no_ui = true
		}
		if a == "--survey" {
			s.survey = true
		}
	}
	for a, i in args {
		if i + 1 >= len(args) {
			break
		}
		switch a {
		case "--shots":
			s.dir, ok = args[i + 1], true
		case "--level":
			for info, n in content.LEVELS {
				if info.id == args[i + 1] {
					s.level = n
				}
			}
		case "--plan":
			s.plan = true
		case "--quality":
			for name, q in settings.QUALITY_CODE {
				if name == args[i + 1] {
					s.quality, s.has_quality = q, true
				}
			}
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
	if s.survey && s.level >= 0 {
		return survey_update(app, s, dt)
	}
	if s.plan && s.level >= 0 {
		name, done = plan_update(app, s, dt)
		if s.record {
			name = ""
			// from the level's start: its prologue, its title, then the plan
			if s.step >= 1 && !done {
				name = fmt.tprintf("f%05d", s.frame)
				s.frame += 1
			}
			if done {
				write_sound_log(app, s)
			}
		}
		return
	}
	if s.level >= 0 && app.screen == .Mechanic && app.mechanic_t > 1.6 {
		close_mechanic(app) // the card of the new mechanic would hide the tour
	}
	script := s.level >= 0 ? LEVEL_TOUR[:] : SHOT_SCRIPT[:]
	if s.step >= len(script) {
		return "", true
	}
	s.t += dt
	step := script[s.step]
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

// --plan: start the level, solve it, then play the plan; a shot at the start,
// after every decision (turn, lamp, handle), after every walk that changed
// the palace, and at the end.
@(private = "file")
plan_update :: proc(app: ^App, s: ^Shots, dt: f32) -> (name: string, done: bool) {
	g := &app.game
	s.t += dt
	if s.step == 0 {
		start_level(app, s.level)
		s.step = 1
		s.t = 0
		return "", false
	}
	if s.step == 1 {
		if g.phase == .Prologue {
			// the cutscene plays; at its invitation, a key starts the level
			if game.prologue_ready(g) && s.t > 2 {
				game.prologue_advance(g)
			}
			if !game.prologue_ready(g) {
				s.t = 0
			}
			return "", false
		}
		if app.screen == .Card {
			dismiss_act_card(app)
			s.t = 0
			return "", false
		}
		if app.screen == .Mechanic {
			// the card of the new mechanic: one shot, then on
			if app.mechanic_t > 1.6 && s.shot == 0 {
				s.shot = -1
				return "p000a_mechanic", false
			}
			if s.shot == -1 {
				close_mechanic(app)
				s.shot = 0
				s.t = 0
			}
			return "", false
		}
		if s.t < 6 {
			return "", false // the title and the intro line
		}
		// the plan lives as long as the program (this mode quits at the end)
		if virtual.arena_init_growing(&s.arena) != nil {
			return "", true
		}
		sol := pl.solve(&g.palace, pl.goal_cell(&g.palace), nil, virtual.arena_allocator(&s.arena))
		s.moves = sol.plan
		s.step = 2
		s.t = 0
		return "p000_start", false
	}
	if s.step == 3 {
		if s.t < 5 {
			return "", false
		}
		virtual.arena_destroy(&s.arena)
		return "", true
	}
	if !game.idle(g) || s.t < 0.15 {
		return "", false
	}
	if app.screen == .Fragment {
		close_fragment(app)
	}
	if s.move > 0 {
		prev := s.moves[s.move - 1]
		last_step := s.move == len(s.moves) || s.moves[s.move].move != .Step
		if (prev.move != .Step || prev.changed > 0 || last_step) && s.t >= 0.15 {
			// show what the move did, once
			if s.shot < s.move {
				s.shot = s.move
				s.t = 0
				return fmt.tprintf("p%03d_%v", s.move, prev.move), false
			}
			if s.t < 0.6 {
				return "", false
			}
		}
	}
	if s.move >= len(s.moves) && g.data.has_amore && !game.is_over(g) && !g.lamp_on {
		game.toggle_lamp(g) // beside Cupid: the lamp, the canonical ending
		s.t = 0
		return "", false
	}
	if s.move >= len(s.moves) || game.is_over(g) {
		s.step = 3
		s.t = 0
		return "", false
	}
	if next := s.moves[s.move]; next.move == .Step && pl.is_passage(&g.palace, g.psyche.cell, next.cell) && s.cave_shot <= s.move {
		// at a cave's mouth: a shot with the action of the place over her
		if s.t < 0.6 {
			return "", false
		}
		s.cave_shot = s.move + 1
		s.t = 0
		return fmt.tprintf("p%03d_cave", s.move), false
	}
	if !game.apply_move(g, s.moves[s.move]) {
		fmt.eprintfln("plan: the game refused move %d %v", s.move, s.moves[s.move])
	}
	s.move += 1
	s.t = 0
	return "", false
}

// --survey: start the level, then for each band of heights (the whole level
// when it has none) put Psyche on a surface of the band and take a shot from
// each of the four views: s<band>_v<view>.
@(private = "file")
survey_update :: proc(app: ^App, s: ^Shots, dt: f32) -> (name: string, done: bool) {
	g := &app.game
	s.t += dt
	switch {
	case s.step == 0:
		start_level(app, s.level)
		s.step, s.t = 1, 0
		return
	case app.screen == .Card:
		dismiss_act_card(app)
		return
	case app.screen == .Mechanic:
		close_mechanic(app)
		return
	case g.phase == .Prologue:
		g.phase_t = 1e3
		game.prologue_advance(g)
		return
	case s.step == 1:
		if s.t > 5 {
			s.step, s.t = 2, 0
		}
		return
	}
	bands := max(len(g.data.tiers), 1)
	k := s.step - 2
	if k >= bands * 4 {
		return "", true
	}
	if s.t < 0.5 {
		if s.t - dt <= 0 {
			// the surface nearest the middle of the band, in view k % 4
			if len(g.data.tiers) > 0 {
				t := g.data.tiers[k / 4]
				mid := (t[0] + t[1]) / 2
				best := g.data.start
				gap := i32(1 << 30)
				for node in g.palace.nodes {
					if d := abs(node.cell.z - mid); !node.stair && d < gap {
						best, gap = node.cell, d
					}
				}
				place(app, best)
				app.scene.tier = render.camera_tier(g)
				app.scene.pan_t = 1e3
			}
			game.set_view(g, k % 4)
		}
		return
	}
	s.step, s.t = s.step + 1, 0
	return fmt.tprintf("s%d_v%d", k / 4, k % 4), false
}

// --record: the effects played, one per line ("t id volume_db pitch pan",
// t in seconds from frame 0), after the place's ambience, the act's music
// and the frame count, for tools/video_audio.
@(private = "file")
write_sound_log :: proc(app: ^App, s: ^Shots) {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintfln(&b, "bed %v", SETTING_BED[app.game.data.setting])
	fmt.sbprintfln(&b, "mood %v", ACT_MOOD[content.LEVELS[app.game.level_index].act])
	fmt.sbprintfln(&b, "frames %d %d", s.frame, RECORD_FPS)
	for e in audio.logged() {
		fmt.sbprintfln(&b, "%.4f %v %.2f %.4f %.2f", e.t, e.id, e.volume_db, e.pitch, e.pan)
	}
	path := fmt.tprintf("%s/sounds.txt", s.dir)
	if err := os.write_entire_file(path, transmute([]u8)strings.to_string(b)); err != nil {
		fmt.eprintln("cannot write", path, err)
	}
}

// --record: frames per second of the captured video.
RECORD_FPS :: 60
