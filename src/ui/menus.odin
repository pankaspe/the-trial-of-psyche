// Full-screen menus: title, pause, level select, the Book, act and ending
// cards, settings, achievement notices, the debug overlay.
package ui

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

import "../audio"
import "../content"
import "../fx"
import "../game"
import "../i18n"
import "../progress"
import "../settings"

Menu_Action :: enum u8 {
	None,
	Play,
	Levels,
	Book,
	Settings,
	Quit,
	Resume,
	Restart,
	Main_Menu,
	Retry,
	Next,
	Back,
}

// A button of a menu: its label and what it does.
Choice :: struct {
	key: i18n.Key,
	act: Menu_Action,
}

@(private)
shade :: proc(u: ^Ui, alpha: f32) {
	rl.DrawRectangleRec({0, 0, u.width, u.height}, fade({3, 3, 10, 255}, alpha))
}

// "I.4", or "Epilogue" for the last level.
level_label :: proc(index: int) -> string {
	info := content.LEVELS[index]
	return info.act == .Epilogue ? i18n.tr(.Act_Epilogue) : info.id
}

// "I.4 · The Lamp and the Razor"
level_name :: proc(index: int) -> string {
	return fmt.tprintf("%s · %s", level_label(index), i18n.tr(content.LEVELS[index].title))
}

// A small diamond: the mark of a fragment (filled when found).
diamond :: proc(u: ^Ui, c: Vec2, radius: f32, col: rl.Color, filled: bool) {
	pts := [4]Vec2{c + {0, -radius}, c + {radius * 0.7, 0}, c + {0, radius}, c + {-radius * 0.7, 0}}
	if filled {
		tri(pts[0], pts[1], pts[2], col)
		tri(pts[0], pts[2], pts[3], col)
		return
	}
	for i in 0 ..< 4 {
		rl.DrawLineEx(pts[i], pts[(i + 1) % 4], max(1.5 * u.scale, 1), col)
	}
}

// Title screen over the sleeping palace. `alpha` and `lift` animate its exit.
title_menu :: proc(u: ^Ui, alpha: f32 = 1, lift: f32 = 0) -> (act: Menu_Action) {
	s := u.scale
	shade(u, 0.55 * alpha)
	cx := u.width * 0.5
	y := u.height * 0.5 - 330 * s - lift * s
	text(u, i18n.tr(.Title), {cx, y}, {size = 104, color = {255, 230, 179, 255}, shadow = true}, .Center, alpha)
	y += 140 * s
	text(u, i18n.tr(.Subtitle), {cx, y}, {size = 30, color = DIM, shadow = true}, .Center, alpha)
	y += 100 * s
	if button(u, i18n.tr(.Play), {cx, y}, 38, alpha) {
		act = .Play
	}
	y += 68 * s
	items := [?]Choice{{.Levels, .Levels}, {.Book, .Book}, {.Settings, .Settings}, {.Quit, .Quit}}
	for it in items {
		if button(u, i18n.tr(it.key), {cx, y}, 26, alpha) {
			act = it.act
		}
		y += 50 * s
	}
	y += 40 * s
	paragraph(u, i18n.tr(.Quote), {cx, y}, {size = 24, color = {191, 184, 230, 217}, italic = true, shadow = true}, 1400 * s, alpha)
	text(u, i18n.tr(.Footer), {cx, u.height - 48 * s}, {size = 18, color = FAINT, shadow = true}, .Center, alpha)
	return
}

pause_menu :: proc(u: ^Ui, lamp: bool) -> (act: Menu_Action) {
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
	// the controls live here, out of the way of the story
	text(u, i18n.tr(lamp ? .Controls : .Controls_Dark), {cx, u.height - 70 * s}, {size = 22, color = DIM, shadow = true})
	return
}

// The card before an act: its number, its title and a few lines of the tale.
// `alpha` fades it in and out; it reports a click once it has been read for a moment.
act_card :: proc(u: ^Ui, act: content.Act, t: f32, alpha: f32, unbuilt: bool) -> (clicked: bool) {
	s := u.scale
	shade(u, 0.8 * alpha)
	cx := u.width * 0.5
	body := Style{size = 32, color = {255, 236, 204, 255}, italic = true, shadow = true}
	msg := i18n.tr(content.ACT_CARD[act])
	bh := block_height(u, msg, body, 1100 * s, 1.35)
	y := u.height * 0.5 - (bh + 220 * s) * 0.5
	a := alpha * clamp(t / 1.5, 0, 1)
	text(u, strings.to_upper(i18n.tr(content.ACT_LABEL[act]), context.temp_allocator), {cx, y}, {size = 24, color = GOLD, shadow = true}, .Center, a)
	y += 46 * s
	text(u, i18n.tr(content.ACT_TITLE[act]), {cx, y}, {size = 72, color = TEXT, shadow = true}, .Center, a)
	y += 130 * s
	a2 := alpha * clamp((t - 0.8) / 1.5, 0, 1)
	y += paragraph(u, msg, {cx, y}, body, 1100 * s, a2, 1.35)
	if unbuilt {
		text(u, i18n.tr(.Card_Unbuilt), {cx, y + 40 * s}, {size = 24, color = DIM, shadow = true}, .Center, a2)
	}
	ready := t > 1.2
	if ready {
		blink := 0.55 + 0.35 * math.sin(t * 2.4)
		text(u, i18n.tr(.Card_Continue), {cx, u.height - 80 * s}, {size = 20, color = FAINT, shadow = true}, .Center, alpha * blink * clamp((t - 2.5) / 1, 0, 1))
	}
	return ready && u.pressed
}

Ending_Info :: struct {
	ending:       game.Ending,
	level:        int,
	unlocked:     progress.Achievements, // achievements earned by this ending
	can_continue: bool,
	outro:        i18n.Key, // the level's own ending text at the exit
	has_outro:    bool,
}

// The card after an ending; `t` is the time since it appeared.
ending_card :: proc(u: ^Ui, info: Ending_Info, t: f32) -> (act: Menu_Action) {
	s := u.scale
	focus_shade(u, clamp(t / 1.2, 0, 1))
	shade(u, 0.25 * clamp(t / 1.5, 0, 1))
	a := clamp(t / 2, 0, 1)
	cx := u.width * 0.5
	body := Style{size = 32, color = TEXT, shadow = true}

	title, msg, note: string
	title_col := GOLD
	switch info.ending {
	case .Trust:
		title, msg, note = i18n.tr(.End_Trust_Title), i18n.tr(.End_Trust), i18n.tr(.End_Trust_Note)
	case .Oil:
		title, msg = i18n.tr(.End_Oil_Title), i18n.tr(.End_Oil)
		title_col = {255, 179, 128, 255}
	case .Exit, .None:
		title, msg = i18n.tr(.End_Exit_Title), level_name(info.level)
		if info.has_outro {
			title, msg = i18n.tr(content.LEVELS[info.level].title), i18n.tr(info.outro)
		}
	}
	if note == "" && content.closes_act(info.level) {
		note = fmt.tprintf("%s%s", i18n.tr(.End_Of_Act), i18n.tr(content.ACT_LABEL[content.LEVELS[info.level].act]))
	}
	extra := f32(card(info.unlocked)) * 40 * s
	bh := block_height(u, msg, body, 1100 * s, 1.3)
	y := u.height * 0.5 - (bh + 300 * s + extra) * 0.5
	text(u, title, {cx, y}, {size = 72, color = title_col, shadow = true}, .Center, a)
	y += 100 * s
	rl.DrawRectangleRec({cx - 160 * s, y, 320 * s, max(1.5 * s, 1)}, fade(GOLD, 0.5 * a))
	diamond(u, {cx, y + 0.5 * s}, 5 * s, fade(GOLD, a), true)
	y += 26 * s
	y += paragraph(u, msg, {cx, y}, body, 1100 * s, a, 1.3)
	y += 40 * s
	text(u, note, {cx, y}, {size = 22, color = DIM, shadow = true}, .Center, a)
	y += 50 * s
	a_ach := clamp((t - 1.5) / 1, 0, 1)
	for ach in info.unlocked {
		line := fmt.tprintf("%s · %s", i18n.tr(.Achievement), i18n.tr(progress.ACHIEVEMENT_NAME[ach]))
		text(u, line, {cx, y}, {size = 24, color = GOLD, shadow = true}, .Center, a_ach)
		y += 40 * s
	}
	y += 40 * s
	all := [?]Choice{{.Next, .Next}, {.Retry, .Retry}, {.Menu, .Main_Menu}}
	buttons := info.can_continue ? all[:] : all[1:]
	gap := 300 * s
	x := cx - gap * f32(len(buttons) - 1) * 0.5
	for b in buttons {
		if button(u, i18n.tr(b.key), {x, y}, 30, a) {
			act = b.act
		}
		x += gap
	}
	return
}

// --- level select --------------------------------------------------------------------

// Levels by act: a tile per level with its fragment mark; the hovered level
// is named at the bottom. Returns the chosen level (-1: none).
level_select :: proc(u: ^Ui, prog: progress.Progress) -> (chosen: int, back: bool) {
	chosen = -1
	s := u.scale
	shade(u, 0.84)
	cx := u.width * 0.5
	text(u, i18n.tr(.Levels_Title), {cx, u.height * 0.5 - 450 * s}, {size = 56, color = {255, 230, 179, 255}, shadow = true})
	count := fmt.tprintf("%s  %d / %d", i18n.tr(.Fragments_Label), progress.fragment_count(prog), content.LEVEL_COUNT)
	text(u, count, {cx, u.height * 0.5 - 375 * s}, {size = 22, color = DIM, shadow = true})

	TILE :: Vec2{150, 92}
	GAP :: 18
	row_y := u.height * 0.5 - 300 * s
	left := cx - 760 * s
	tiles_x := cx - 280 * s
	hovered := -1
	for act in content.Act {
		text(u, strings.to_upper(i18n.tr(content.ACT_LABEL[act]), context.temp_allocator), {left, row_y + 14 * s}, {size = 20, color = GOLD, shadow = true}, .Left, 0.9)
		text(u, i18n.tr(content.ACT_TITLE[act]), {left, row_y + 44 * s}, {size = 28, color = TEXT, shadow = true}, .Left)
		x := tiles_x
		for info, i in content.LEVELS {
			if info.act != act {
				continue
			}
			r := rl.Rectangle{x, row_y, TILE.x * s, TILE.y * s}
			x += (TILE.x + GAP) * s
			built := content.is_built(i)
			open := progress.is_unlocked(prog, i)
			done := i in prog.completed
			add_hot(u, r)
			hover := rl.CheckCollisionPointRec(u.mouse, r)
			if hover {
				hovered = i
			}
			alpha: f32 = open ? 1 : (built ? 0.55 : 0.3)
			bg := rl.Color{20, 20, 52, 120}
			if hover && open {
				bg = {34, 34, 80, 170}
			}
			rl.DrawRectangleRec(r, fade(bg, alpha))
			edge := done ? fade(GOLD, 0.7) : fade(DIM, 0.35 * alpha)
			rl.DrawRectangleLinesEx(r, max(1.5 * s, 1), hover && open ? GOLD : edge)
			col := done ? TEXT : DIM
			if hover && open {
				col = GOLD
			}
			label := info.act == .Epilogue ? "E" : info.id
			text(u, label, {r.x + r.width * 0.5, r.y + 12 * s}, {size = 34, color = col, shadow = true}, .Center, alpha)
			if built {
				diamond(u, {r.x + r.width * 0.5, r.y + r.height - 18 * s}, 8 * s, fade(GOLD, alpha * 0.9), i in prog.fragments)
			}
			if hover && open && u.pressed {
				audio.play(.Tap, -10)
				chosen = i
			}
		}
		row_y += 128 * s
	}

	if hovered >= 0 {
		y := u.height * 0.5 + 345 * s
		text(u, level_name(hovered), {cx, y}, {size = 32, color = TEXT, shadow = true})
		status := ""
		if !content.is_built(hovered) {
			status = i18n.tr(.Level_Unbuilt)
		} else if !progress.is_unlocked(prog, hovered) {
			status = i18n.tr(.Level_Locked)
		}
		text(u, status, {cx, y + 48 * s}, {size = 22, color = DIM, shadow = true})
	}
	back = button(u, i18n.tr(.Back), {cx, u.height * 0.5 + 460 * s}, 30)
	return
}

// --- the Book -------------------------------------------------------------------------

FRAGMENTS_PER_PAGE :: 4
BOOK_PAGES :: (content.LEVEL_COUNT + FRAGMENTS_PER_PAGE - 1) / FRAGMENTS_PER_PAGE + 1 // + achievements

// The fragments in Apuleius' order, a few per page, then the achievements.
// `page` is changed by the arrows.
book :: proc(u: ^Ui, prog: progress.Progress, page: ^int) -> (back: bool) {
	s := u.scale
	shade(u, 0.86)
	cx := u.width * 0.5
	top := u.height * 0.5 - 450 * s
	text(u, i18n.tr(.Book), {cx, top}, {size = 56, color = {255, 230, 179, 255}, shadow = true})
	achievements := page^ == BOOK_PAGES - 1
	sub := achievements ? i18n.tr(.Book_Achievements) : i18n.tr(.Book_Fragments)
	text(u, sub, {cx, top + 82 * s}, {size = 24, color = GOLD, shadow = true}, .Center, 0.9)
	y := top + 160 * s

	if !achievements {
		cite := Style{size = 20, color = GOLD, shadow = true}
		body := Style{size = 27, color = TEXT, italic = true, shadow = true}
		first := page^ * FRAGMENTS_PER_PAGE
		for k in first ..< min(first + FRAGMENTS_PER_PAGE, content.LEVEL_COUNT) {
			i := content.BOOK_ORDER[k]
			info := content.LEVELS[i]
			text(u, fmt.tprintf("%d  ·  %s", k + 1, info.cite), {cx, y}, cite, .Center, 0.8)
			y += 34 * s
			if i in prog.fragments {
				y += paragraph(u, i18n.tr(info.fragment), {cx, y}, body, 1000 * s, 1, 1.3)
			} else {
				text(u, fmt.tprintf("—  %s  —", i18n.tr(.Book_Missing)), {cx, y}, {size = 22, color = FAINT, italic = true, shadow = true})
				y += 34 * s
			}
			y += 34 * s
		}
	} else {
		for a in progress.Achievement {
			got := a in prog.achievements
			secret := a in progress.SECRET && !got
			name := i18n.tr(secret ? .Book_Hidden : progress.ACHIEVEMENT_NAME[a])
			desc := i18n.tr(secret ? .Ach_Trust_Secret : progress.ACHIEVEMENT_DESC[a])
			alpha: f32 = got ? 1 : 0.55
			nst := Style{size = 28, color = got ? GOLD : DIM, shadow = true}
			w := measure(u, name, nst).x
			text(u, name, {cx, y}, nst, .Center, alpha)
			diamond(u, {cx - w * 0.5 - 24 * s, y + 18 * s}, 8 * s, fade(GOLD, alpha), got)
			text(u, desc, {cx, y + 38 * s}, {size = 20, color = DIM, shadow = true}, .Center, alpha)
			y += 82 * s
		}
	}

	ny := u.height * 0.5 + 370 * s
	text(u, fmt.tprintf("%d / %d", page^ + 1, BOOK_PAGES), {cx, ny}, {size = 22, color = DIM, shadow = true})
	if page^ > 0 && button(u, "‹", {cx - 110 * s, ny + 14 * s}, 40) {
		page^ -= 1
	}
	if page^ < BOOK_PAGES - 1 && button(u, "›", {cx + 110 * s, ny + 14 * s}, 40) {
		page^ += 1
	}
	back = button(u, i18n.tr(.Back), {cx, u.height * 0.5 + 460 * s}, 30)
	return
}

// A short notice in the top left corner: an achievement just unlocked.
achievement_toast :: proc(u: ^Ui, a: progress.Achievement, t: f32) {
	alpha := fx.envelope(t, 0.5, 3.5, 1.0)
	if alpha <= 0 {
		return
	}
	s := u.scale
	name := i18n.tr(progress.ACHIEVEMENT_NAME[a])
	nst := Style{size = 28, color = TEXT, shadow = true}
	w := max(measure(u, name, nst).x, 220 * s) + 90 * s
	r := rl.Rectangle{32 * s, 32 * s, w, 92 * s}
	rl.DrawRectangleRec(r, fade({8, 8, 26, 200}, alpha))
	rl.DrawRectangleRec({r.x, r.y + r.height - max(s, 1), r.width, max(2 * s, 1)}, fade(GOLD, alpha * 0.6))
	diamond(u, {r.x + 34 * s, r.y + r.height * 0.5}, 11 * s, fade(GOLD, alpha), true)
	text(u, i18n.tr(.Achievement), {r.x + 64 * s, r.y + 14 * s}, {size = 19, color = GOLD, shadow = true}, .Left, alpha)
	text(u, name, {r.x + 64 * s, r.y + 40 * s}, nst, .Left, alpha)
}

TOAST_TIME :: 5.0

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
