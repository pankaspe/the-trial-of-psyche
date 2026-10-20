// Full-screen menus: title, pause, level select, the Book, act and ending
// cards, settings, achievement notices, the debug overlay.
package ui

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:time"
import rl "vendor:raylib"

import "../audio"
import "../content"
import "../fx"
import "../game"
import "../i18n"
import "../input"
import "../level"
import "../progress"
import "../settings"

Menu_Action :: enum u8 {
	None,
	Play,
	Levels,
	Games,
	Book,
	Codex,
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
	rl.DrawRectangleRec({0, 0, u.width, u.height}, fade({8, 4, 3, 255}, alpha))
}

// The lamp's side of the screen: the left half warmed and darkened, for the
// title and the pause menu.
@(private)
lamp_side :: proc(u: ^Ui, alpha: f32, reach: f32 = 0.55) {
	rl.DrawRectangleGradientH(0, 0, i32(u.width * reach), i32(u.height), fade({26, 12, 10, 255}, min(0.74 * alpha, 1)), {26, 12, 10, 0})
}

// --- the side panel (the level select, the settings) ------------------------------------
//
// The world clear on the right (the diorama moved there, `Scene.stage`); on
// the left the lamp's side, darker, and on it: tabs along the top, an eyebrow
// in capitals and a title, the panel's content, and at the foot how to move
// about it, "Back" in the right corner.

PANEL_X :: 120 // the panel's left edge (1080p units)
STAGE_SIZE :: [2]f32{0.6, 0.66} // the part of the screen the diorama is framed in beside the panel
STAGE_SHIFT :: [2]f32{0.14, -0.06} // and where its middle is, from the screen's (fractions of it)
PANEL_W :: 680
TABS_Y :: 64
HEAD_Y :: 168
FOOT_Y :: 66 // from the bottom

side_panel :: proc(u: ^Ui) {
	lamp_side(u, 1.26, 0.6)
}

// The tabs along the top: the one on is lit and underlined; returns the one
// clicked (-1: none) and where the row ends.
tab_row :: proc(u: ^Ui, labels: []string, on: int, sealed: []bool = nil) -> (clicked: int, end: f32) {
	clicked = -1
	s := u.scale
	x := PANEL_X * s
	y := TABS_Y * s
	for label, i in labels {
		st := Style{size = 24, color = i == on ? BRIGHT : fade(DIM, 0.7), face = .Semi, track = 0.18, shadow = true}
		m := measure(u, label, st)
		r := rl.Rectangle{x - 12 * s, y - 8 * s, m.x + 24 * s, m.y + 16 * s}
		add_hot(u, r)
		if mouse_over(u, r) {
			st.color = BRIGHT
			if u.pressed && i != on {
				audio.play(.Tap, -14)
				clicked = i
			}
		}
		text(u, label, {x, y}, st, .Left)
		if i == on {
			rl.DrawRectangleRec({x, y + m.y + 4 * s, m.x, max(1.5 * s, 1)}, BRIGHT)
		}
		if i < len(sealed) && sealed[i] {
			// a small seal of gold over the tab's corner
			c := Vec2{x + m.x + 9 * s, y + 2 * s}
			glow_dot(c, 5 * s, {255, 176, 77, 255}, 0.9)
			diamond(u, c, 7 * s, BRIGHT, true)
		}
		x += m.x + 40 * s
	}
	return clicked, x
}

// The eyebrow and the title at the head of the panel; returns the y below them.
panel_head :: proc(u: ^Ui, eyebrow, title: string) -> f32 {
	s := u.scale
	x := PANEL_X * s
	y := HEAD_Y * s
	text(u, eyebrow, {x, y}, {size = 20, color = GOLD, face = .Semi, track = 0.22, shadow = true}, .Left)
	y += 42 * s
	st := Style{size = 64, color = TITLE, face = .Display, glow = true, shadow = true}
	if w := measure(u, title, st).x; w > PANEL_W * s {
		st.size *= PANEL_W * s / w
	}
	text(u, title, {x, y}, st, .Left)
	return y + (st.size + 22) * s
}

// What a hint's keys are: the keyboard's caps, or the pad's buttons.
Hint_Keys :: enum u8 {
	Left_Right,
	Up_Down,
	Enter,
	Shoulders,
	South,
	Erase, // Delete on the keyboard, West on the pad
	Restart, // R on the keyboard, West on the pad
}

Hint :: struct {
	keys:  Hint_Keys,
	label: i18n.Key,
}

// How to move about a screen, in a row at `pos` (its left end, or its middle).
hint_row :: proc(u: ^Ui, pos: Vec2, hints: []Hint, centred := false) {
	s := u.scale
	st := Style{size = 22, color = DIM, face = .Semi, track = 0.1, shadow = true}
	keys_width :: proc(u: ^Ui, k: Hint_Keys) -> f32 {
		s := u.scale
		switch k {
		case .Left_Right, .Up_Down: return 66 * s
		case .Enter: return key_cap_width(u, "Enter", s)
		case .Shoulders: return pad_button_width(u, .LB) + 6 * s + pad_button_width(u, .RB)
		case .South: return pad_button_width(u, .South)
		case .Erase: return u.pad ? pad_button_width(u, .West) : key_cap_width(u, i18n.tr(.Key_Delete), s)
		case .Restart: return u.pad ? pad_button_width(u, .West) : key_cap_width(u, "R", s)
		}
		return 0
	}
	x := pos.x
	if centred {
		total: f32 = 0
		for h in hints {
			total += keys_width(u, h.keys) + 12 * s + measure(u, i18n.tr(h.label), st).x + 44 * s
		}
		x -= (total - 44 * s) * 0.5
	}
	for h in hints {
		switch h.keys {
		case .Left_Right, .Up_Down:
			d := h.keys == .Left_Right ? 0 : 2
			arrow_cap(u, {x, pos.y}, 30 * s, d)
			arrow_cap(u, {x + 36 * s, pos.y}, 30 * s, d + 1)
		case .Enter:
			key_cap(u, "Enter", {x, pos.y}, 0.9)
		case .Shoulders:
			pad_button(u, .RB, {x + pad_button_width(u, .LB) + 6 * s, pos.y}, 0.9)
			pad_button(u, .LB, {x, pos.y}, 0.9)
		case .South:
			pad_button(u, .South, {x, pos.y}, 0.9)
		case .Erase:
			control(u, i18n.tr(.Key_Delete), .West, {x, pos.y}, 0.9)
		case .Restart:
			control(u, "R", .West, {x, pos.y}, 0.9)
		}
		x += keys_width(u, h.keys) + 12 * s
		text(u, i18n.tr(h.label), {x, pos.y + 2 * s}, st, .Left)
		x += measure(u, i18n.tr(h.label), st).x + 44 * s
	}
}

// "[Esc] Back" in the panel's bottom right corner.
panel_back :: proc(u: ^Ui, focus := true) -> bool {
	return back_key(u, {u.width - PANEL_X * u.scale, u.height - FOOT_Y * u.scale}, .Right, focus)
}

// The acts' tabs (the level select, the Book).
@(private)
ACT_NUMERAL := [len(content.Act)]string{"I", "II", "III", "IV", "E"} // by content.Act

// "I.4", or "Epilogue" for the last level.
level_label :: proc(index: int) -> string {
	info := content.LEVELS[index]
	return info.act == .Epilogue ? i18n.tr(.Act_Epilogue) : info.id
}

// "I.4 · The Lamp and the Razor"
level_name :: proc(index: int) -> string {
	return fmt.tprintf("%s · %s", level_label(index), i18n.tr(content.LEVELS[index].title))
}

// The title in two lines, broken at the space nearest its middle.
@(private)
split_title :: proc(t: string) -> (string, string) {
	best := -1
	for c, i in t {
		if c == ' ' && (best < 0 || abs(i - len(t) / 2) < abs(best - len(t) / 2)) {
			best = i
		}
	}
	if best < 0 {
		return t, ""
	}
	return t[:best], t[best + 1:]
}

// Title screen over the sleeping palace, like the cover of a book: on the
// lamp's side, the source, the title, an ornament and the menu; the oracle's
// words in the corner. `alpha` and `lift` animate its exit.
// `playing`: the game in play has begun (Continue), else a new one starts.
title_menu :: proc(u: ^Ui, playing: bool, alpha: f32 = 1, lift: f32 = 0) -> (act: Menu_Action) {
	s := u.scale
	lamp_side(u, alpha)
	x := 144 * s
	y := u.height * 0.5 - 340 * s - lift * s
	text(u, caps(i18n.tr(.Footer)), {x, y}, {size = 22, color = GOLD, face = .Semi, track = 0.14, shadow = true}, .Left, alpha)
	y += 36 * s
	tst := Style{size = 132, color = TITLE, face = .Display, glow = true, shadow = true}
	first, second := split_title(i18n.tr(.Title))
	text(u, first, {x - 4 * s, y}, tst, .Left, alpha)
	y += 126 * s
	text(u, second, {x - 4 * s, y}, tst, .Left, alpha)
	y += 172 * s
	ornament(u, {x + 100 * s, y}, 100 * s, alpha)
	y += 62 * s
	if menu_item(u, i18n.tr(playing ? .Play : .New_Game), {x, y}, 38, true, alpha) {
		act = .Play
	}
	y += 62 * s
	items := [?]Choice{{.Games, .Games}, {.Levels, .Levels}, {.Book, .Book}, {.Codex, .Codex}, {.Settings, .Settings}, {.Quit, .Quit}}
	for it in items {
		if menu_item(u, i18n.tr(it.key), {x, y}, 36, false, alpha) {
			act = it.act
		}
		y += 58 * s
	}
	qst := Style{size = 28, color = {250, 232, 205, 220}, face = .Italic, shadow = true}
	quote := i18n.tr(.Quote)
	qh := block_height(u, quote, qst, 900 * s, 1.35)
	paragraph(u, quote, {u.width - 84 * s, u.height - 60 * s - qh}, qst, 900 * s, alpha, 1.35, .Right)
	return
}

// The pause names where she is, at the top: the act and the level, its title
// in the titles' face (and which of its dioramas); "Paused" over the menu.
pause_menu :: proc(u: ^Ui, lamp: bool, level: int, diorama, dioramas: int) -> (act: Menu_Action) {
	s := u.scale
	shade(u, 0.5)
	lamp_side(u, 1)
	x := 144 * s
	info := content.LEVELS[level]
	y := 80 * s
	eyebrow := fmt.tprintf("%s  ·  %s", caps(i18n.tr(content.ACT_LABEL[info.act])), level_label(level))
	if dioramas > 1 {
		eyebrow = fmt.tprintf("%s  ·  %s", eyebrow, caps(fmt.tprintf(i18n.tr(.Pause_Diorama), diorama + 1, dioramas)))
	}
	text(u, eyebrow, {x, y}, {size = 22, color = GOLD, face = .Semi, track = 0.18, shadow = true}, .Left)
	y += 40 * s
	text(u, i18n.tr(info.title), {x - 3 * s, y}, {size = 76, color = TITLE, face = .Display, glow = true, shadow = true}, .Left)
	y = u.height * 0.5 - 200 * s
	text(u, i18n.tr(.Pause_Title), {x - 3 * s, y}, {size = 64, color = TEXT, face = .Display, shadow = true}, .Left)
	y += 104 * s
	ornament(u, {x + 100 * s, y}, 100 * s)
	y += 62 * s
	items := [?]Choice{{.Resume, .Resume}, {.Restart, .Restart}, {.Codex, .Codex}, {.Settings, .Settings}, {.Menu, .Main_Menu}}
	for it, i in items {
		if menu_item(u, i18n.tr(it.key), {x, y}, i == 0 ? 38 : 34, i == 0) {
			act = it.act
		}
		y += 60 * s
	}
	// the controls live here, out of the way of the story
	y += 40 * s
	paragraph(u, i18n.tr(lamp ? .Controls : .Controls_Dark), {x, y}, {size = 26, color = DIM, face = .Italic, shadow = true}, 900 * s, 1, 1.3, .Left)
	return
}

// The card before an act: its number between rules, its title and a few
// lines of the tale. `alpha` fades it in and out; it reports a click once it
// has been read for a moment.
act_card :: proc(u: ^Ui, act: content.Act, t: f32, alpha: f32, unbuilt: bool) -> (clicked: bool) {
	s := u.scale
	shade(u, 0.8 * alpha)
	cx := u.width * 0.5
	body := Style{size = 36, color = {255, 238, 210, 255}, face = .Italic, shadow = true}
	msg := i18n.tr(content.ACT_CARD[act])
	bh := block_height(u, msg, body, 1100 * s, 1.35)
	y := u.height * 0.5 - (bh + 250 * s) * 0.5
	a := alpha * clamp(t / 1.5, 0, 1)
	rule_label(u, caps(i18n.tr(content.ACT_LABEL[act])), {cx, y}, 24, 120 * s, a)
	y += 48 * s
	text(u, i18n.tr(content.ACT_TITLE[act]), {cx, y}, {size = 104, color = TITLE, face = .Display, glow = true, shadow = true}, .Center, a)
	y += 160 * s
	a2 := alpha * clamp((t - 0.8) / 1.5, 0, 1)
	y += paragraph(u, msg, {cx, y}, body, 1100 * s, a2, 1.35)
	if unbuilt {
		text(u, i18n.tr(.Card_Unbuilt), {cx, y + 40 * s}, {size = 26, color = DIM, face = .Italic, shadow = true}, .Center, a2)
	}
	ready := t > 1.2
	if ready {
		blink := 0.55 + 0.35 * math.sin(t * 2.4)
		text(u, i18n.tr(.Card_Continue), {cx, u.height - 80 * s}, {size = 24, color = FAINT, face = .Italic, shadow = true}, .Center, alpha * blink * clamp((t - 2.5) / 1, 0, 1))
	}
	return ready && (u.pressed || take_accept(u))
}

Ending_Info :: struct {
	ending:       game.Ending,
	level:        int,
	unlocked:     progress.Achievements, // achievements earned by this ending
	can_continue: bool,
	outro:        i18n.Key, // the level's own ending text at the exit
	has_outro:    bool,
}

// The card after an ending, in a frame of gold: the act and the level, the
// title, the tale, the level's fragments, achievements, the way on. `t` is
// the time since it appeared, `gone` (0 .. 1) how far it has faded out as
// the game goes on.
ending_card :: proc(u: ^Ui, info: Ending_Info, prog: progress.Progress, t: f32, gone: f32 = 0) -> (act: Menu_Action) {
	s := u.scale
	// after an exit the world behind is already out of focus: a lighter shade
	veiled := info.ending == .Exit
	stay := 1 - gone
	focus_shade(u, clamp(t / 1.2, 0, 1) * (veiled ? 0.4 : 1) * stay)
	a := clamp(t / 1.2, 0, 1) * stay
	cx := u.width * 0.5
	body := Style{size = 34, color = TEXT, face = .Italic, shadow = true}

	title, msg, note: string
	title_col := TITLE
	switch info.ending {
	case .Trust:
		title, msg, note = i18n.tr(.End_Trust_Title), i18n.tr(.End_Trust), i18n.tr(.End_Trust_Note)
	case .Oil:
		title, msg = i18n.tr(.End_Oil_Title), i18n.tr(.End_Oil)
		title_col = {255, 196, 150, 255}
	case .Exit, .None:
		title, msg = i18n.tr(.End_Exit_Title), level_name(info.level)
		if info.has_outro {
			title, msg = i18n.tr(content.LEVELS[info.level].title), i18n.tr(info.outro)
		}
	}
	if note == "" && content.closes_act(info.level) {
		note = fmt.tprintf("%s%s", i18n.tr(.End_Of_Act), i18n.tr(content.ACT_LABEL[content.LEVELS[info.level].act]))
	}
	first, fragments := content.level_fragments(info.level)
	bw := 1000 * s
	bh := block_height(u, msg, body, bw, 1.3)
	h := 64 + 116 + 34 + 44 + 40 + 64 + 40
	if note != "" {
		h += 46
	}
	if fragments > 0 {
		h += 54
	}
	h += 40 * card(info.unlocked)
	height := bh + f32(h) * s
	y := u.height * 0.5 - height * 0.5
	warm_card(u, {cx - bw * 0.5 - 70 * s, y, bw + 140 * s, height}, a, 0.4)
	y += 44 * s
	rule_label(u, fmt.tprintf("%s  ·  %s", caps(i18n.tr(content.ACT_LABEL[content.LEVELS[info.level].act])), level_label(info.level)), {cx, y}, 19, 70 * s, a)
	y += 46 * s
	text(u, title, {cx, y}, {size = 80, color = title_col, face = .Display, glow = true, shadow = true}, .Center, a)
	y += 116 * s
	ornament(u, {cx, y}, 140 * s, a)
	y += 34 * s
	// the tale follows the title in
	a_tale := clamp((t - 0.5) / 1.2, 0, 1) * stay
	y += paragraph(u, msg, {cx, y}, body, bw, a_tale, 1.3)
	y += 44 * s
	if note != "" {
		text(u, note, {cx, y}, {size = 26, color = DIM, face = .Italic, shadow = true}, .Center, a_tale)
		y += 46 * s
	}
	// then what was found: the level's fragments, the achievements
	a_found := clamp((t - 1.2) / 1, 0, 1) * stay
	if fragments > 0 {
		label := fmt.tprintf("%d / %d  %s", progress.level_fragments(prog, info.level), fragments, i18n.tr(.Fragments_Label))
		st := Style{size = 22, color = DIM, face = .Semi, track = 0.06, shadow = true}
		row := f32(fragments) * 26 * s + 12 * s + measure(u, label, st).x
		x := cx - row * 0.5
		for k in 0 ..< fragments {
			diamond(u, {x + 9 * s + f32(k) * 26 * s, y + 14 * s}, 10 * s, fade(GOLD, a_found), first + k in prog.fragments)
		}
		text(u, label, {x + f32(fragments) * 26 * s + 12 * s, y + s}, st, .Left, a_found)
		y += 54 * s
	}
	for ach in info.unlocked {
		line := fmt.tprintf("%s · %s", i18n.tr(.Achievement), i18n.tr(progress.ACHIEVEMENT_NAME[ach]))
		text(u, line, {cx, y}, {size = 26, color = GOLD, face = .Semi, shadow = true}, .Center, a_found)
		y += 40 * s
	}
	y += 40 * s
	all := [?]Choice{{.Next, .Next}, {.Retry, .Retry}, {.Menu, .Main_Menu}}
	buttons := info.can_continue ? all[:] : all[1:]
	gap := 280 * s
	x := cx - gap * f32(len(buttons) - 1) * 0.5
	for b in buttons {
		if button(u, i18n.tr(b.key), {x, y}, 30, a_found) {
			act = b.act
		}
		x += gap
	}
	return
}

// --- level select --------------------------------------------------------------------

// The pluck of each act in the level select: rising degrees of the scale.
ACT_TAP_PITCH := [content.Act]f32{.I = 1, .II = 9.0 / 8, .III = 5.0 / 4, .IV = 4.0 / 3, .Epilogue = 3.0 / 2}

// The level select: the chosen level's diorama turns behind (main draws it,
// framed on the right); on the left, a panel tells where it is and what it
// holds; below, the act's levels in a row of pictures. ← → (the stick) choose
// the level, ↑ ↓ (LB RB) the act, Enter (South) or a click plays it.
Level_Select :: struct {
	level: int, // the chosen level (LEVELS index)
	graph: bool, // the act's levels as a constellation, not a row of pictures
	t:     f32, // the stars' twinkle
}

// `thumbs`: a picture per level (id 0: none yet); `shown`: the level drawn
// behind, whose data the panel reads once it is the chosen one; `veil`: how
// dark the world is drawn (the picture changing, a level not built).
level_select :: proc(u: ^Ui, prog: progress.Progress, ls: ^Level_Select, thumbs: []rl.Texture2D, shown: ^game.Game, veil: f32) -> (chosen: int, from_start, back: bool) {
	chosen = -1
	s := u.scale
	// another act (LB RB, ↑ ↓, a tab): a pluck, a step higher for each act
	was := content.LEVELS[ls.level].act
	defer if now := content.LEVELS[ls.level].act; now != was {
		audio.play(.Tap, -14, ACT_TAP_PITCH[now])
	}
	rl.DrawRectangleRec({0, 0, u.width, u.height}, fade({3, 2, 6, 255}, veil))
	// the panel's side and the row's foot darkened, the diorama left clear
	side_panel(u)
	rl.DrawRectangleGradientV(0, i32(u.height - 380 * s), i32(u.width), i32(380 * s), {5, 4, 9, 0}, fade({5, 4, 9, 255}, 0.9))

	act := content.LEVELS[ls.level].act
	choose_act :: proc(ls: ^Level_Select, act: content.Act) {
		ls.level = act_first(act)
	}
	// the keys and the pad
	step := input.nav()
	if rl.IsKeyPressed(.LEFT) {
		step.x = -1
	}
	if rl.IsKeyPressed(.RIGHT) {
		step.x = 1
	}
	if rl.IsKeyPressed(.UP) || input.take(.LB) {
		step.y = -1
	}
	if rl.IsKeyPressed(.DOWN) || input.take(.RB) {
		step.y = 1
	}
	if step.y != 0 {
		next := int(act) + step.y
		if next >= 0 && next < len(content.Act) {
			choose_act(ls, content.Act(next))
		}
	} else if next := ls.level + step.x; step.x != 0 && next >= 0 && next < content.LEVEL_COUNT && content.LEVELS[next].act == act {
		ls.level = next
	}
	act = content.LEVELS[ls.level].act
	play := rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.SPACE)
	if u.pad && u.accept {
		input.consume(.South)
		u.accept = false
		play = true
	}

	// the acts, as tabs, and the fragments found
	x0 := PANEL_X * s
	// an act whose fragments are all in the Book is sealed
	sealed: [len(content.Act)]bool
	for a in content.Act {
		found, total := progress.act_fragments(prog, a)
		sealed[a] = total > 0 && found == total
	}
	clicked, tabs_end := tab_row(u, ACT_NUMERAL[:], int(act), sealed[:])
	if clicked >= 0 {
		choose_act(ls, content.Act(clicked))
	}
	count := fmt.tprintf("·   %s  %d / %d", caps(i18n.tr(.Fragments_Label)), progress.fragment_count(prog), content.FRAGMENT_COUNT)
	text(u, count, {tabs_end, TABS_Y * s + 3 * s}, {size = 18, color = fade(DIM, 0.8), face = .Semi, track = 0.16, shadow = true}, .Left)

	// the act's whole tale in the Book: a gilt plaque over the diorama
	if sealed[act] {
		act_plaque(u, caps(fmt.tprintf(i18n.tr(.Act_Sealed), i18n.tr(content.ACT_LABEL[act]))))
	}

	// the panel: the chosen level
	info := content.LEVELS[ls.level]
	built := content.is_built(ls.level)
	open := progress.is_unlocked(prog, ls.level)
	done := ls.level in prog.completed
	loaded := built && shown.level_index == ls.level
	w := PANEL_W * s
	eyebrow := fmt.tprintf("%s  ·  %s", caps(i18n.tr(content.ACT_LABEL[act])), level_label(ls.level))
	y := panel_head(u, eyebrow, i18n.tr(info.title))
	y += paragraph(u, i18n.tr(info.place), {x0, y}, {size = 30, color = DIM, face = .Italic, shadow = true}, w, 1, 1.2, .Left)
	y += 14 * s
	text(u, fmt.tprintf("MET.  %s", info.cite), {x0, y}, {size = 19, color = GOLD, face = .Semi, track = 0.2, shadow = true}, .Left)
	y += 58 * s
	if loaded && shown.data.has_intro {
		y += paragraph(u, i18n.tr(shown.data.intro), {x0, y}, {size = 28, color = TEXT, face = .Italic, shadow = true}, w, 1, 1.3, .Left) + 30 * s
	}
	if built {
		first, n := content.level_fragments(ls.level)
		for k in 0 ..< n {
			diamond(u, {x0 + 9 * s + f32(k) * 26 * s, y + 14 * s}, 10 * s, GOLD, first + k in prog.fragments)
		}
		found := fmt.tprintf("%d / %d  %s", progress.level_fragments(prog, ls.level), n, i18n.tr(.Fragments_Label))
		cst := Style{size = 22, color = DIM, face = .Semi, track = 0.06, shadow = true}
		cx := x0 + f32(n) * 26 * s + 12 * s
		text(u, found, {cx, y + 1 * s}, cst, .Left)
		y += 52 * s
	}
	if loaded {
		// what the place holds: the lamp, the devices of the spindle, the actions of the place
		devices := [?]struct {
			id:  Codex_Id,
			key: i18n.Key,
		} {
			{.Lamp, .Lamp_Button},
			{.Seal, .Device_Seals},
			{.Guard, .Device_Guard},
			{.Veiled, .Device_Veiled},
			{.Handle, .Device_Handles},
			{.Time, .Device_Sundials},
			{.Rams, .Device_Rams},
			{.Flip, .Device_Pomegranates},
			{.Cave, .Device_Caves},
			{.Eagle, .Device_Eagle},
			{.Boat, .Device_Boat},
			{.Rest, .Device_Braziers},
		}
		labels := make([dynamic]string, context.temp_allocator)
		if shown.dioramas > 1 {
			append(&labels, fmt.tprintf(i18n.tr(.Device_Dioramas), shown.dioramas))
		}
		for h in devices {
			if holds(&shown.data, h.id) {
				append(&labels, i18n.tr(h.key))
			}
		}
		hx := x0
		for label in labels {
			pw := plaque_size(u, label).x
			if hx + pw > x0 + w {
				hx = x0
				y += plaque_size(u, label).y + 12 * s
			}
			hx += plaque(u, label, {hx, y}) + 12 * s
		}
		if hx > x0 {
			y += 34 * s + 24 * s
		}
	}
	status := !built ? i18n.tr(.Level_Unbuilt) : (!open ? i18n.tr(.Level_Locked) : (done ? i18n.tr(.Levels_Done) : i18n.tr(.Levels_Open)))
	// a level of several dioramas left half way: it goes on from the one reached
	reached := progress.resume_at(prog, ls.level)
	resumes := open && reached > 0 && loaded
	if resumes {
		status = fmt.tprintf(i18n.tr(.Levels_Resume), reached + 1, shown.dioramas)
	}
	text(u, status, {x0, y}, {size = 24, color = done || resumes ? GOLD : DIM, face = .Italic, shadow = true}, .Left)
	if resumes && (rl.IsKeyPressed(.R) || input.take(.West)) {
		from_start = true
		play = true
	}

	// the act's levels: a row of pictures, or a constellation (Tab, the pad's North)
	if rl.IsKeyPressed(.TAB) || input.take(.North) || view_toggle(u, ls.graph) {
		ls.graph = !ls.graph
		audio.play(.Tap, -14, ls.graph ? 1.25 : 1)
	}
	ls.t += u.dt
	if ls.graph {
		play ||= level_stars(u, prog, ls, act)
	} else {
		play ||= level_row(u, prog, ls, act, thumbs)
	}
	if play && open {
		audio.play(.Tap, -14)
		chosen = ls.level
	}

	// how to move about it
	foot := Vec2{x0, u.height - FOOT_Y * s}
	switch {
	case u.pad && resumes:
		hint_row(u, foot, {{.Shoulders, .Levels_Act}, {.South, .Levels_Play}, {.Restart, .Levels_From_Start}})
	case u.pad:
		hint_row(u, foot, {{.Shoulders, .Levels_Act}, {.South, .Levels_Play}})
	case resumes:
		hint_row(u, foot, {{.Left_Right, .Levels_Level}, {.Up_Down, .Levels_Act}, {.Enter, .Levels_Play}, {.Restart, .Levels_From_Start}})
	case:
		hint_row(u, foot, {{.Left_Right, .Levels_Level}, {.Up_Down, .Levels_Act}, {.Enter, .Levels_Play}})
	}
	back = panel_back(u, focus = false)
	return
}

// The act's levels in a row of pictures; true when one is clicked (to play).
@(private)
level_row :: proc(u: ^Ui, prog: progress.Progress, ls: ^Level_Select, act: content.Act, thumbs: []rl.Texture2D) -> (play: bool) {
	s := u.scale
	TILE :: Vec2{256, 144}
	GAP :: 22
	tx := PANEL_X * s
	ty := u.height - 236 * s
	for i in 0 ..< content.LEVEL_COUNT {
		if content.LEVELS[i].act != act {
			continue
		}
		on := i == ls.level
		r := rl.Rectangle{tx, ty - (on ? 12 * s : 0), TILE.x * s, TILE.y * s}
		tx += (TILE.x + GAP) * s
		hot := rl.Rectangle{r.x, ty - 12 * s, r.width, r.height + 12 * s}
		add_hot(u, hot)
		hover := mouse_over(u, hot)
		if hover && !on && u.mouse_moved {
			ls.level = i
		}
		tile_open := progress.is_unlocked(prog, i)
		if hover && u.pressed {
			ls.level = i
			play = true
		}
		if thumbs[i].id != 0 {
			tint := tile_open ? rl.WHITE : rl.Color{90, 84, 96, 255}
			tw, th := f32(thumbs[i].width), f32(thumbs[i].height)
			rl.DrawTexturePro(thumbs[i], {0, 0, tw, -th}, r, {}, 0, tint)
		} else {
			rl.DrawRectangleRec(r, fade({13, 11, 20, 255}, 0.85))
			if !content.is_built(i) {
				text(u, i18n.tr(.Level_Unbuilt), {r.x + r.width * 0.5, r.y + r.height * 0.38}, {size = 19, color = fade(DIM, 0.6), face = .Italic}, .Center)
			}
		}
		rl.DrawRectangleGradientV(i32(r.x), i32(r.y + r.height * 0.45), i32(r.width), i32(r.height * 0.55), {5, 4, 9, 0}, {5, 4, 9, 210})
		text(u, level_label(i), {r.x + 14 * s, r.y + r.height - 40 * s}, {size = 26, color = on ? BRIGHT : TEXT, face = .Semi, shadow = true}, .Left)
		if content.is_built(i) {
			if nd := len(level.dioramas(content.LEVELS[i].source)); nd > 1 {
				for k in 0 ..< nd {
					p := rl.Rectangle{r.x + r.width - 16 * s - f32(nd - k) * 14 * s, r.y + 10 * s, 10 * s, 10 * s}
					rl.DrawRectangleRec(p, fade({13, 11, 20, 255}, 0.8))
					rl.DrawRectangleLinesEx(p, max(s, 1), GOLD)
				}
			}
			first, n := content.level_fragments(i)
			for k in 0 ..< n {
				diamond(u, {r.x + r.width - 18 * s - f32(n - 1 - k) * 20 * s, r.y + r.height - 22 * s}, 7 * s, GOLD, first + k in prog.fragments)
			}
		}
		edge := on ? BRIGHT : (i in prog.completed ? fade(GOLD, 0.6) : fade(GOLD, 0.22))
		rl.DrawRectangleLinesEx(r, max((on ? 2 : 1.2) * s, 1), edge)
		if on {
			corner_frame(u, {r.x - 6 * s, r.y - 6 * s, r.width + 12 * s, r.height + 12 * s}, 1, s, BRIGHT)
		}
	}
	return
}

// The act's levels as a constellation: a star each, joined in the order of
// the tale (the line lit where the level before is finished); the dioramas
// of a level hang from its star as small ones, not chosen apart. Bright and
// filled: finished; breathing: open; dim: locked; a faint outline: not built.
// True when one is clicked (to play).
@(private)
level_stars :: proc(u: ^Ui, prog: progress.Progress, ls: ^Level_Select, act: content.Act) -> (play: bool) {
	s := u.scale
	first := act_first(act)
	n := 0
	for i in first ..< content.LEVEL_COUNT {
		if content.LEVELS[i].act != act {
			break
		}
		n += 1
	}
	x0 := PANEL_X * s + 40 * s
	span := min(u.width - x0 - 260 * s, 300 * s * f32(max(n - 1, 1)))
	base := u.height - 205 * s
	// each act's figure: the stars rise and fall along the line
	SHAPE := [?]f32{0.2, -0.9, 0.5, -0.4, 0.9, -0.7, 0.3}
	star_at :: proc(k, n: int, act: content.Act, x0, span, base, s: f32, shape: []f32) -> Vec2 {
		x := x0 + (n > 1 ? span * f32(k) / f32(n - 1) : 0)
		return {x, base + shape[(k + int(act) * 2) % len(shape)] * 58 * s}
	}
	// the sky behind: a scatter of faint stars
	for k in 0 ..< 70 {
		h := u32(k) * 2654435761 + u32(act) * 40503
		px := x0 - 40 * s + f32(h % 1000) / 1000 * (span + 120 * s)
		py := base - 120 * s + f32((h / 1000) % 1000) / 1000 * 210 * s
		tw := 0.25 + 0.2 * math.sin(ls.t * (0.6 + f32(k % 5) * 0.2) + f32(k))
		rl.DrawCircleV({px, py}, (0.8 + f32(k % 3) * 0.5) * s, fade(TEXT, u.reduce_motion ? 0.3 : tw))
	}
	// the lines of the tale, then the stars over them
	for k in 0 ..< n - 1 {
		a := star_at(k, n, act, x0, span, base, s, SHAPE[:])
		b := star_at(k + 1, n, act, x0, span, base, s, SHAPE[:])
		if first + k in prog.completed {
			rl.DrawLineEx(a, b, 1.6 * s, fade(GOLD, 0.7))
		} else {
			d := b - a
			steps := int(linalg.length(d) / (10 * s))
			for j in 0 ..< steps {
				if j % 2 == 0 {
					rl.DrawLineEx(a + d * f32(j) / f32(steps), a + d * f32(j + 1) / f32(steps), 1.2 * s, fade(GOLD, 0.25))
				}
			}
		}
	}
	for k in 0 ..< n {
		i := first + k
		c := star_at(k, n, act, x0, span, base, s, SHAPE[:])
		on := i == ls.level
		built := content.is_built(i)
		done := i in prog.completed
		open := progress.is_unlocked(prog, i)
		hot := rl.Rectangle{c.x - 40 * s, c.y - 40 * s, 80 * s, 80 * s}
		add_hot(u, hot)
		hover := mouse_over(u, hot)
		if hover && !on && u.mouse_moved {
			ls.level = i
		}
		if hover && u.pressed {
			ls.level = i
			play = true
		}
		// its dioramas after the first: small stars rising from it
		if built {
			nd := len(level.dioramas(content.LEVELS[i].source))
			prev := c
			for d in 1 ..< nd {
				p := c + Vec2{f32(d) * 16, -24 - f32(d) * 22} * s
				rl.DrawLineEx(prev, p, 1 * s, fade(GOLD, done ? 0.5 : 0.22))
				glow_dot(p, 7 * s, {255, 214, 150, 255}, done ? 0.7 : 0.2)
				diamond(u, p, 7 * s, done ? BRIGHT : fade(GOLD, 0.5), done)
				prev = p
			}
		}
		breath := breathe(u, ls.t + f32(k), 2.2)
		switch {
		case done:
			glow_dot(c, 16 * s, {255, 196, 110, 255}, 0.9)
			diamond(u, c, 13 * s, BRIGHT, true)
		case open:
			glow_dot(c, 14 * s, {255, 196, 110, 255}, 0.35 + 0.35 * breath)
			diamond(u, c, 13 * s, GOLD, false)
			diamond(u, c, 5 * s, fade(BRIGHT, 0.5 + 0.5 * breath), true)
		case built:
			diamond(u, c, 9 * s, fade(DIM, 0.6), true)
		case:
			diamond(u, c, 9 * s, fade(DIM, 0.35), false)
		}
		if on {
			rl.DrawRing(c, 24 * s, 25.5 * s, 0, 360, 48, BRIGHT)
		}
		// its name, and its fragments
		ly := c.y + 30 * s
		text(u, level_label(i), {c.x, ly}, {size = on ? 26 : 22, color = on ? BRIGHT : (built ? TEXT : fade(DIM, 0.6)), face = .Semi, shadow = true}, .Center)
		if built {
			f0, nf := content.level_fragments(i)
			for q in 0 ..< nf {
				diamond(u, {c.x + (f32(q) - f32(nf - 1) * 0.5) * 16 * s, ly + 40 * s}, 5 * s, GOLD, f0 + q in prog.fragments)
			}
		}
	}
	return
}

// The button that changes the view of the act's levels, above them on the
// right: what the other view is, with its key.
@(private)
view_toggle :: proc(u: ^Ui, graph: bool) -> bool {
	s := u.scale
	st := Style{size = 21, color = TEXT, face = .Semi, track = 0.1, shadow = true}
	label := i18n.tr(graph ? .Levels_Pictures : .Levels_Stars)
	m := measure(u, label, st)
	cw := u.pad ? pad_button_width(u, .North) : key_cap_width(u, "Tab", s)
	x := u.width - PANEL_X * s - m.x
	y := u.height - 300 * s
	r := rl.Rectangle{x - cw - 22 * s, y - 8 * s, m.x + cw + 30 * s, 44 * s}
	add_hot(u, r)
	hover := mouse_over(u, r)
	if hover {
		st.color = BRIGHT
	}
	rl.DrawRectangleRec(r, fade({13, 11, 20, 255}, 0.7))
	rl.DrawRectangleLinesEx(r, max(s, 1), fade(GOLD, hover ? 0.7 : 0.35))
	control(u, "Tab", .North, {x - cw - 12 * s, y - 2 * s}, 0.9)
	text(u, label, {x, y}, st, .Left)
	return hover && u.pressed
}

// --- the Book -------------------------------------------------------------------------

// An open book of dark glass, like the cards of the interface. Tabs on the
// right edge open each act and, last, the achievements. In an act the left
// page is its index (each level, a diamond for every fragment it hides, lit
// once found) and the right page reads the fragments of the level chosen.
// ← → (LB RB) change the tab, a page turning; ↑ ↓ choose the level; a click
// does both.
Book_State :: struct {
	tab:    int, // an act (content.Act), or BOOK_ACHIEVEMENTS
	level:  int, // the level read on the right page (LEVELS index)
	flip_t: f32, // since the page turned (< 0: none)
	flip:   int, // the way it turned: +1 forward, -1 back
	read_t: f32, // since the level on the right page was chosen
}

BOOK_ACHIEVEMENTS :: len(content.Act) // the last tab
@(private)
BOOK_TABS :: BOOK_ACHIEVEMENTS + 1
@(private)
FLIP_TIME :: 0.5

// The first level of an act.
@(private)
act_first :: proc(act: content.Act) -> int {
	for info, i in content.LEVELS {
		if info.act == act {
			return i
		}
	}
	return 0
}

// Open the Book at an act's first level (or keep where it was).
book_open :: proc(b: ^Book_State) {
	if b.tab == 0 && b.level == 0 {
		b.flip_t = -1
	}
	b.read_t = 1
}

book :: proc(u: ^Ui, prog: progress.Progress, b: ^Book_State) -> (back: bool) {
	s := u.scale
	shade(u, 0.86)
	cx := u.width * 0.5
	cy := u.height * 0.5
	if b.flip_t >= 0 {
		b.flip_t += u.dt
		if b.flip_t >= FLIP_TIME {
			b.flip_t = -1
		}
	}
	b.read_t += u.dt

	turn :: proc(b: ^Book_State, want: int) {
		to := clamp(want, 0, BOOK_TABS - 1)
		if to == b.tab {
			return
		}
		b.flip = to > b.tab ? 1 : -1
		b.flip_t = 0
		b.tab = to
		if to < BOOK_ACHIEVEMENTS {
			b.level = act_first(content.Act(to))
			b.read_t = 0
		}
	}
	choose :: proc(b: ^Book_State, level: int) {
		if level != b.level {
			b.level = level
			b.read_t = 0
		}
	}
	// the keys and the pad
	step := 0
	if rl.IsKeyPressed(.LEFT) || input.take(.LB) {
		step = -1
	}
	if rl.IsKeyPressed(.RIGHT) || input.take(.RB) {
		step = 1
	}
	if step != 0 {
		turn(b, b.tab + step)
	}
	if b.tab < BOOK_ACHIEVEMENTS {
		act := content.Act(b.tab)
		dy := input.nav().y
		if rl.IsKeyPressed(.UP) {
			dy = -1
		}
		if rl.IsKeyPressed(.DOWN) {
			dy = 1
		}
		next := b.level + dy
		if dy != 0 && next >= 0 && next < content.LEVEL_COUNT && content.LEVELS[next].act == act {
			choose(b, next)
		}
	}

	// the title over the book
	text(u, i18n.tr(.Book), {cx, cy - 515 * s}, {size = 72, color = TITLE, face = .Display, glow = true, shadow = true})

	// the book: two pages of dark glass, the spine in shadow
	W :: 1500
	H :: 780
	book_r := rl.Rectangle{cx - W * 0.5 * s, cy - 410 * s, W * s, H * s}
	left := rl.Rectangle{book_r.x, book_r.y, book_r.width * 0.5, book_r.height}
	right := rl.Rectangle{cx, book_r.y, book_r.width * 0.5, book_r.height}
	rl.DrawRectangleRec({book_r.x + 10 * s, book_r.y + 16 * s, book_r.width, book_r.height}, fade({0, 0, 0, 255}, 0.45))
	for pg in ([2]rl.Rectangle{left, right}) {
		rl.DrawRectangleGradientV(i32(pg.x), i32(pg.y), i32(pg.width), i32(pg.height), {28, 21, 33, 250}, {18, 13, 24, 250})
		rl.DrawRectangleLinesEx(pg, max(s, 1), fade(GOLD, 0.16))
	}
	sh := 70 * s
	rl.DrawRectangleGradientH(i32(cx - sh), i32(book_r.y), i32(sh), i32(book_r.height), {0, 0, 0, 0}, {0, 0, 0, 150})
	rl.DrawRectangleGradientH(i32(cx), i32(book_r.y), i32(sh), i32(book_r.height), {0, 0, 0, 150}, {0, 0, 0, 0})
	rl.DrawRectangleGradientV(i32(cx - s), i32(book_r.y), i32(2 * s), i32(book_r.height * 0.5), fade(GOLD, 0.6), fade(GOLD, 0))
	rl.DrawRectangleGradientV(i32(cx - s), i32(book_r.y + book_r.height * 0.5), i32(2 * s), i32(book_r.height * 0.5), fade(GOLD, 0), fade(GOLD, 0.6))
	corner_frame(u, {book_r.x - 6 * s, book_r.y - 6 * s, book_r.width + 12 * s, book_r.height + 12 * s}, 1)

	// the tabs, out of the right page's edge
	for i in 0 ..< BOOK_TABS {
		r := rl.Rectangle{right.x + right.width, right.y + 50 * s + f32(i) * 66 * s, 60 * s, 54 * s}
		add_hot(u, r)
		hover := mouse_over(u, r)
		on := i == b.tab
		rl.DrawRectangleRec(r, on ? GOLD : fade({26, 20, 32, 255}, hover ? 1 : 0.95))
		rl.DrawRectangleLinesEx(r, max(s, 1), fade(GOLD, on ? 1 : (hover ? 0.8 : 0.4)))
		ink := on ? rl.Color{26, 20, 32, 255} : (hover ? BRIGHT : DIM)
		c := Vec2{r.x + r.width * 0.5 + 3 * s, r.y + r.height * 0.5}
		if i == BOOK_ACHIEVEMENTS {
			diamond(u, c, 10 * s, ink, true)
		} else {
			st := Style{size = 24, color = ink, face = .Semi}
			label := ACT_NUMERAL[i]
			text(u, label, {c.x, c.y - measure(u, label, st).y * 0.5}, st)
		}
		if hover && u.pressed {
			turn(b, i)
		}
	}

	PAD :: 70
	if b.tab < BOOK_ACHIEVEMENTS {
		act := content.Act(b.tab)
		// the left page: the act and its index
		lx := left.x + PAD * s
		lw := left.width - 2 * PAD * s
		y := left.y + 56 * s
		rule_label(u, caps(i18n.tr(content.ACT_LABEL[act])), {left.x + left.width * 0.5, y}, 20, 70 * s)
		y += 34 * s
		text(u, i18n.tr(content.ACT_TITLE[act]), {left.x + left.width * 0.5, y}, {size = 48, color = TITLE, face = .Display, glow = true})
		y += 100 * s
		for info, i in content.LEVELS {
			if info.act != act {
				continue
			}
			row := rl.Rectangle{lx - 16 * s, y - 8 * s, lw + 32 * s, 58 * s}
			add_hot(u, row)
			hover := mouse_over(u, row)
			sel := i == b.level
			if sel {
				rl.DrawRectangleRec(row, fade(GOLD, 0.12))
				rl.DrawRectangleLinesEx(row, max(s, 1), fade(GOLD, 0.55))
			} else if hover {
				rl.DrawRectangleRec(row, fade(GOLD, 0.06))
			}
			built := content.is_built(i)
			ink := sel ? BRIGHT : (built ? TEXT : FAINT)
			text(u, level_label(i), {lx, y + 6 * s}, {size = 22, color = GOLD, face = .Semi, track = 0.08}, .Left, built ? 1 : 0.6)
			text(u, i18n.tr(info.title), {lx + 76 * s, y}, {size = 32, color = ink, face = built ? .Body : .Italic}, .Left)
			// a diamond for each fragment it hides, lit once found
			first, count := content.level_fragments(i)
			for k in 0 ..< count {
				found := (first + k) in prog.fragments
				c := Vec2{lx + lw - f32(count - 1 - k) * 26 * s - 8 * s, y + 21 * s}
				if found {
					glow_dot(c, 9 * s, {255, 176, 77, 255}, 0.6)
				}
				diamond(u, c, 9 * s, found ? BRIGHT : fade(FAINT, 0.8), found)
			}
			if hover && u.pressed {
				choose(b, i)
			}
			y += 66 * s
		}
		// the count, at the foot of the page
		total := fmt.tprintf("%s  %d / %d", caps(i18n.tr(.Fragments_Label)), progress.fragment_count(prog), content.FRAGMENT_COUNT)
		text(u, total, {left.x + left.width * 0.5, left.y + left.height - 56 * s}, {size = 18, color = DIM, face = .Semi, track = 0.16})

		// the right page: the fragments of the level chosen
		a := clamp(b.read_t / 0.3, 0, 1)
		rx := right.x + PAD * s
		rw := right.width - 2 * PAD * s
		ry := right.y + 62 * s
		text(u, level_label(b.level), {right.x + right.width * 0.5, ry}, {size = 20, color = GOLD, face = .Semi, track = 0.18}, .Center, a)
		ry += 30 * s
		ry += paragraph(u, i18n.tr(content.LEVELS[b.level].title), {right.x + right.width * 0.5, ry}, {size = 44, color = TITLE, face = .Display, glow = true}, rw, a, 1.1)
		ornament(u, {right.x + right.width * 0.5, ry + 22 * s}, 60 * s, a)
		ry += 56 * s
		first, count := content.level_fragments(b.level)
		cite := Style{size = 20, color = GOLD, face = .Semi, track = 0.12}
		body := Style{size = 29, color = TEXT, face = .Italic}
		for k in 0 ..< count {
			i := first + k
			info := content.FRAGMENTS[i]
			found := i in prog.fragments
			diamond(u, {rx + 6 * s, ry + 11 * s}, 7 * s, found ? BRIGHT : fade(FAINT, 0.8), found)
			text(u, fmt.tprintf("Met. %s", info.cite), {rx + 24 * s, ry}, cite, .Left, a * 0.9)
			ry += 32 * s
			if found {
				ry += paragraph(u, i18n.tr(info.key), {rx, ry}, body, rw, a, 1.3, .Left)
			} else {
				text(u, i18n.tr(.Book_Missing), {rx, ry}, {size = 26, color = FAINT, face = .Italic}, .Left, a)
				ry += 34 * s
			}
			ry += 26 * s
		}
		if !content.is_built(b.level) {
			text(u, i18n.tr(.Level_Unbuilt), {rx, ry}, {size = 24, color = FAINT, face = .Italic}, .Left, a)
		}
	} else {
		// the achievements, half on each page
		list := make([dynamic]progress.Achievement, 0, 16, context.temp_allocator)
		for ach in progress.Achievement {
			append(&list, ach)
		}
		half := (len(list) + 1) / 2
		rule_label(u, caps(i18n.tr(.Book_Achievements)), {left.x + left.width * 0.5, left.y + 56 * s}, 20, 70 * s)
		for ach, n in list {
			pg := n < half ? left : right
			row := n < half ? n : n - half
			x := pg.x + PAD * s
			y := pg.y + 130 * s + f32(row) * 150 * s
			got := ach in prog.achievements
			secret := ach in progress.SECRET && !got
			name := i18n.tr(secret ? .Book_Hidden : progress.ACHIEVEMENT_NAME[ach])
			desc := i18n.tr(secret ? .Ach_Trust_Secret : progress.ACHIEVEMENT_DESC[ach])
			alpha: f32 = got ? 1 : 0.55
			if got {
				glow_dot({x + 10 * s, y + 18 * s}, 12 * s, {255, 176, 77, 255}, 0.7)
			}
			diamond(u, {x + 10 * s, y + 18 * s}, 10 * s, fade(GOLD, alpha), got)
			text(u, name, {x + 38 * s, y}, {size = 32, color = got ? BRIGHT : DIM, face = .Semi}, .Left, alpha)
			paragraph(u, desc, {x + 38 * s, y + 44 * s}, {size = 24, color = DIM, face = .Italic}, pg.width - 2 * PAD * s - 38 * s, alpha, 1.25, .Left)
		}
	}

	// a page turning over the spine
	if b.flip_t >= 0 {
		k := b.flip_t / FLIP_TIME
		e := k * k * (3 - 2 * k)
		w := right.width * abs(math.cos(e * math.PI))
		fwd := b.flip > 0
		on_right := fwd ? e < 0.5 : e >= 0.5
		x := on_right ? cx : cx - w
		sheet := rl.Rectangle{x, right.y - 4 * s, w, right.height + 8 * s}
		lit := u8(40 + 50 * math.sin(e * math.PI))
		inner := rl.Color{lit, u8(f32(lit) * 0.78), u8(f32(lit) * 0.95), 255}
		outer := rl.Color{30, 23, 36, 255}
		if on_right {
			rl.DrawRectangleGradientH(i32(sheet.x), i32(sheet.y), i32(sheet.width), i32(sheet.height), inner, outer)
		} else {
			rl.DrawRectangleGradientH(i32(sheet.x), i32(sheet.y), i32(sheet.width), i32(sheet.height), outer, inner)
		}
		edge := on_right ? sheet.x + sheet.width : sheet.x
		rl.DrawRectangleRec({edge - s, sheet.y, 2 * s, sheet.height}, fade(GOLD, 0.7))
	}

	// how to move about it
	foot := Vec2{cx, book_r.y + book_r.height + 26 * s}
	if u.pad {
		hint_row(u, foot, {{.Shoulders, .Book_Turn}}, centred = true)
	} else if b.tab < BOOK_ACHIEVEMENTS {
		hint_row(u, foot, {{.Left_Right, .Book_Turn}, {.Up_Down, .Book_Choose}}, centred = true)
	} else {
		hint_row(u, foot, {{.Left_Right, .Book_Turn}}, centred = true)
	}
	back = panel_back(u, focus = false)
	return
}

// A key cap with an arrow drawn in it: 0 left, 1 right, 2 up, 3 down.
@(private)
arrow_cap :: proc(u: ^Ui, pos: Vec2, size: f32, dir: int) {
	r := rl.Rectangle{pos.x, pos.y, size, size}
	rl.DrawRectangleRec(r, fade({21, 18, 29, 255}, 0.9))
	rl.DrawRectangleLinesEx(r, max(u.scale, 1), DIM)
	c := Vec2{r.x + size * 0.5, r.y + size * 0.5}
	h := size * 0.22
	pts: [3]Vec2
	switch dir {
	case 0: pts = {c + {-h, 0}, c + {h, -h}, c + {h, h}}
	case 1: pts = {c + {h, 0}, c + {-h, h}, c + {-h, -h}}
	case 2: pts = {c + {0, -h}, c + {h, h}, c + {-h, h}}
	case: pts = {c + {0, h}, c + {-h, -h}, c + {h, -h}}
	}
	tri(pts[0], pts[1], pts[2], DIM)
}

// The seal at the end of an act's row: every fragment of the act found.
@(private)
PLAQUE_STYLE :: Style{size = 21, color = DIM, face = .Semi, track = 0.08}

plaque_size :: proc(u: ^Ui, label: string) -> Vec2 {
	m := measure(u, label, PLAQUE_STYLE)
	return {m.x + 26 * u.scale, m.y + 12 * u.scale}
}

// A small plaque: a label on a dark plate edged in gold (what a place holds).
// Returns its width.
plaque :: proc(u: ^Ui, label: string, pos: Vec2) -> f32 {
	s := u.scale
	size := plaque_size(u, label)
	r := rl.Rectangle{pos.x, pos.y, size.x, size.y}
	rl.DrawRectangleRec(r, fade({13, 11, 20, 255}, 0.7))
	rl.DrawRectangleLinesEx(r, max(s, 1), fade(GOLD, 0.35))
	text(u, label, {r.x + 13 * s, r.y + 6 * s}, PLAQUE_STYLE, .Left)
	return size.x
}

// The plaque of an act whose whole tale is in the Book: gilt, over the
// diorama of the level select, on the line of the act tabs.
@(private)
act_plaque :: proc(u: ^Ui, label: string) {
	s := u.scale
	st := Style{size = 20, color = GOLD, face = .Semi, track = 0.18}
	m := measure(u, label, st)
	cx := u.width * (0.5 + STAGE_SHIFT.x)
	r := rl.Rectangle{cx - m.x * 0.5 - 44 * s, TABS_Y * s - 10 * s, m.x + 88 * s, m.y + 20 * s}
	glow_dot({cx, r.y + r.height * 0.5}, r.width * 0.35, {255, 176, 77, 255}, 0.25)
	rl.DrawRectangleRec(r, fade({40, 24, 14, 255}, 0.9))
	rl.DrawRectangleLinesEx(r, max(1.5 * s, 1), GOLD)
	corner_frame(u, {r.x - 5 * s, r.y - 5 * s, r.width + 10 * s, r.height + 10 * s}, 1, s, BRIGHT)
	for side in ([]f32{-1, 1}) {
		diamond(u, {cx + side * (m.x * 0.5 + 24 * s), r.y + r.height * 0.5}, 5 * s, BRIGHT, true)
	}
	text(u, label, {cx - m.x * 0.5, r.y + 10 * s}, st, .Left)
}

// A fragment just added to the Book, with how many of its act are there now.
Page_Notice :: struct {
	act:          content.Act,
	found, total: int,
}

// What a toast announces: an achievement just unlocked, or a new page of the Book.
Notice :: union {
	progress.Achievement,
	Page_Notice,
}

// A short notice in the top left corner.
toast :: proc(u: ^Ui, n: Notice, t: f32) {
	alpha := fx.envelope(t, 0.5, 3.5, 1.0)
	if alpha <= 0 {
		return
	}
	s := u.scale
	head, name: string
	switch v in n {
	case progress.Achievement:
		head = i18n.tr(.Achievement)
		name = i18n.tr(progress.ACHIEVEMENT_NAME[v])
	case Page_Notice:
		head = i18n.tr(.Notice_Page)
		name = fmt.tprintf(i18n.tr(.Notice_Page_Count), i18n.tr(content.ACT_LABEL[v.act]), v.found, v.total)
	}
	nst := Style{size = 32, color = TEXT, face = .Semi}
	w := max(measure(u, name, nst).x, 220 * s) + 96 * s
	r := rl.Rectangle{32 * s, 32 * s, w, 96 * s}
	warm_card(u, r, alpha, 0.45)
	c := Vec2{r.x + 36 * s, r.y + r.height * 0.5}
	glow_dot(c, 9 * s, {255, 176, 77, 255}, alpha)
	diamond(u, c, 11 * s, fade(BRIGHT, alpha), true)
	text(u, caps(head), {r.x + 68 * s, r.y + 16 * s}, {size = 18, color = GOLD, face = .Semi, track = 0.16}, .Left, alpha)
	text(u, name, {r.x + 68 * s, r.y + 42 * s}, nst, .Left, alpha)
}

TOAST_TIME :: 5.0

Setting_Field :: enum u8 {
	Language,
	Fullscreen,
	Resolution,
	Vsync,
	Fps,
	Volumes,
	Debug,
	Quality,
	Access, // the accessibility options (read by the app every frame)
	Aids, // the game's aids (kept in its save)
}

Setting_Changes :: bit_set[Setting_Field]

// The pages of the settings panel.
Settings_Tab :: enum u8 {
	General,
	Aids,
	Graphics,
	Audio,
	Access,
}

@(private)
TAB_KEY := [Settings_Tab]i18n.Key {
	.General  = .Set_General,
	.Aids     = .Set_Aids,
	.Graphics = .Set_Graphics,
	.Audio    = .Set_Audio,
	.Access   = .Set_Access,
}

DIFFICULTY_NAME := [progress.Difficulty]i18n.Key {
	.Story  = .Difficulty_Story,
	.Normal = .Difficulty_Normal,
	.Puzzle = .Difficulty_Puzzle,
}

DIFFICULTY_DESC := [progress.Difficulty]i18n.Key {
	.Story  = .Difficulty_Story_Desc,
	.Normal = .Difficulty_Normal_Desc,
	.Puzzle = .Difficulty_Puzzle_Desc,
}

// The aids one by one, in the settings.
@(private)
AID_NAME := [progress.Aid]i18n.Key {
	.Highlight   = .Set_Highlight,
	.Sense       = .Set_Sense,
	.Dead_Ends   = .Set_Dead_Ends,
	.Endless_Oil = .Set_Endless_Oil,
	.Guide       = .Set_Guide,
}

@(private)
QUALITY_NAME := [settings.Quality]i18n.Key {
	.Low    = .Quality_Low,
	.Medium = .Quality_Medium,
	.High   = .Quality_High,
	.Ultra  = .Quality_Ultra,
}

@(private)
PAD_GLYPHS_NAME := [settings.Pad_Glyphs]i18n.Key {
	.Auto        = .Glyphs_Auto,
	.Xbox        = .Glyphs_Xbox,
	.PlayStation = .Glyphs_PlayStation,
	.Nintendo    = .Glyphs_Nintendo,
}

@(private)
QUALITY_DESC := [settings.Quality]i18n.Key {
	.Low    = .Quality_Low_Desc,
	.Medium = .Quality_Medium_Desc,
	.High   = .Quality_High_Desc,
	.Ultra  = .Quality_Ultra_Desc,
}

// The settings panel, in tabs: edits `cfg` and the game's `aids` in place and
// reports what changed. On the Graphics tab the game behind shows through, so
// the quality can be judged while it is changed.
settings_menu :: proc(u: ^Ui, cfg: ^settings.Settings, aids: ^progress.Aids, resolutions: [][2]i32, native: [2]i32) -> (changes: Setting_Changes, back: bool) {
	s := u.scale
	tab := &u.settings_tab
	// the lamp's side, the game clear on the right (the diorama moved there)
	side_panel(u)
	left := PANEL_X * s
	right := left + PANEL_W * s

	// the tabs; the pad's shoulders go through them
	labels: [len(Settings_Tab)]string
	for t in Settings_Tab {
		labels[int(t)] = caps(i18n.tr(TAB_KEY[t]))
	}
	turn := 0
	if clicked, _ := tab_row(u, labels[:], int(tab^)); clicked >= 0 {
		turn = clicked - int(tab^)
	}
	if input.take(.LB) {
		turn = -1
	}
	if input.take(.RB) {
		turn = 1
	}
	if turn != 0 {
		n := len(Settings_Tab)
		audio.play(.Tap, -14)
		tab^ = Settings_Tab((int(tab^) + turn + n) % n)
		reset_focus(u)
	}
	y := panel_head(u, caps(i18n.tr(.Set_Title)), i18n.tr(TAB_KEY[tab^])) + 10 * s
	row := 72 * s
	// a hairline under each row
	line :: proc(u: ^Ui, left, right, y: f32) {
		hairline(u, left, y + 50 * u.scale, right - left)
	}
	section :: proc(u: ^Ui, key: i18n.Key, left: f32, y: ^f32) {
		text(u, caps(i18n.tr(key)), {left, y^}, {size = 19, color = GOLD, face = .Semi, track = 0.16}, .Left, 0.9)
		y^ += 40 * u.scale
	}
	on_off :: proc(v: bool) -> string {
		return i18n.tr(v ? .Set_On : .Set_Off)
	}

	switch tab^ {
	case .General:
		if step := option_row(u, i18n.tr(.Set_Language), i18n.tr(.Lang_Name), y, left, right); step != 0 {
			n := len(i18n.Language)
			cfg.language = i18n.Language((int(cfg.language) + step + n) % n)
			changes += {.Language}
		}
		line(u, left, right, y)
		y += row
		if step := option_row(u, i18n.tr(.Set_Pad_Glyphs), i18n.tr(PAD_GLYPHS_NAME[cfg.pad_glyphs]), y, left, right); step != 0 {
			n := len(settings.Pad_Glyphs)
			cfg.pad_glyphs = settings.Pad_Glyphs((int(cfg.pad_glyphs) + step + n) % n)
			changes += {.Access}
		}
		line(u, left, right, y)
		y += row
		if step := option_row(u, i18n.tr(.Set_Debug), on_off(cfg.debug), y, left, right); step != 0 {
			cfg.debug = !cfg.debug
			changes += {.Debug}
		}

	case .Graphics:
		section(u, .Set_Picture, left, &y)
		if step := option_row(u, i18n.tr(.Set_Quality), i18n.tr(QUALITY_NAME[cfg.quality]), y, left, right); step != 0 {
			n := len(settings.Quality)
			cfg.quality = settings.Quality((int(cfg.quality) + step + n) % n)
			changes += {.Quality}
		}
		line(u, left, right, y)
		y += row
		y += paragraph(u, i18n.tr(QUALITY_DESC[cfg.quality]), {left, y - 6 * s}, {size = 26, color = DIM, face = .Italic}, right - left, 1, 1.2, .Left)
		y += 36 * s

		section(u, .Set_Screen, left, &y)
		if step := option_row(u, i18n.tr(.Set_Display), i18n.tr(cfg.fullscreen ? .Set_Fullscreen : .Set_Windowed), y, left, right); step != 0 {
			cfg.fullscreen = !cfg.fullscreen
			changes += {.Fullscreen}
		}
		line(u, left, right, y)
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
		line(u, left, right, y)
		y += row
		if step := option_row(u, i18n.tr(.Set_Vsync), on_off(cfg.vsync), y, left, right); step != 0 {
			cfg.vsync = !cfg.vsync
			changes += {.Vsync}
		}
		line(u, left, right, y)
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

	case .Audio:
		if slider(u, i18n.tr(.Set_Master), &cfg.master, y, left, right) {
			changes += {.Volumes}
		}
		line(u, left, right, y)
		y += row
		if slider(u, i18n.tr(.Set_Music), &cfg.music, y, left, right) {
			changes += {.Volumes}
		}
		line(u, left, right, y)
		y += row
		if slider(u, i18n.tr(.Set_Sfx), &cfg.sfx, y, left, right) {
			changes += {.Volumes}
		}

	case .Aids:
		// the difficulty sets every aid; changed one by one it is no longer one of them
		d, chosen := progress.difficulty_of(aids^)
		name := i18n.tr(chosen ? DIFFICULTY_NAME[d] : .Difficulty_Custom)
		if step := option_row(u, i18n.tr(.Set_Difficulty), name, y, left, right); step != 0 {
			n := len(progress.Difficulty)
			next := chosen ? progress.Difficulty((int(d) + step + n) % n) : .Normal
			aids^ = progress.DIFFICULTY_AIDS[next]
			changes += {.Aids}
		}
		line(u, left, right, y)
		y += row
		for key, a in AID_NAME {
			if step := option_row(u, i18n.tr(key), on_off(a in aids), y, left, right); step != 0 {
				aids^ ~= {a}
				changes += {.Aids}
			}
			line(u, left, right, y)
			y += row
		}
	case .Access:
		// the next value in a list, `step` places on, wrapping
		pick :: proc(list: []f32, value: f32, step: int) -> f32 {
			current := 0
			for v, i in list {
				if abs(v - value) < 0.001 {
					current = i
				}
			}
			return list[(current + step + len(list)) % len(list)]
		}
		if step := option_row(u, i18n.tr(.Set_Hud_Size), fmt.tprintf("%d%%", int(cfg.hud_size * 100 + 0.5)), y, left, right); step != 0 {
			cfg.hud_size = pick(settings.HUD_SIZES[:], cfg.hud_size, step)
			changes += {.Access}
		}
		line(u, left, right, y)
		y += row
		labels := i18n.tr(cfg.skill_labels == .Always ? .Labels_Always : .Labels_Hover)
		if step := option_row(u, i18n.tr(.Set_Skill_Labels), labels, y, left, right); step != 0 {
			cfg.skill_labels = cfg.skill_labels == .Always ? .Hover : .Always
			changes += {.Access}
		}
		line(u, left, right, y)
		y += row
		if step := option_row(u, i18n.tr(.Set_Restart_Twice), on_off(cfg.restart_twice), y, left, right); step != 0 {
			cfg.restart_twice = !cfg.restart_twice
			changes += {.Access}
		}
		line(u, left, right, y)
		y += row
		hold := fmt.tprintf("%.1f s", cfg.hold_time)
		if step := option_row(u, i18n.tr(.Set_Hold), hold, y, left, right, !cfg.restart_twice); step != 0 {
			cfg.hold_time = pick(settings.HOLD_TIMES[:], cfg.hold_time, step)
			changes += {.Access}
		}
		line(u, left, right, y)
		y += row
		if step := option_row(u, i18n.tr(.Set_Reduce_Motion), on_off(cfg.reduce_motion), y, left, right); step != 0 {
			cfg.reduce_motion = !cfg.reduce_motion
			changes += {.Access}
		}
		line(u, left, right, y)
		y += row
		if step := option_row(u, i18n.tr(.Set_See_Through), on_off(cfg.see_through), y, left, right); step != 0 {
			cfg.see_through = !cfg.see_through
			changes += {.Access}
		}
		line(u, left, right, y)
		y += row
		if step := option_row(u, i18n.tr(.Set_Lamp_Toggle), on_off(cfg.lamp_toggle), y, left, right); step != 0 {
			cfg.lamp_toggle = !cfg.lamp_toggle
			changes += {.Access}
		}
	}
	foot := Vec2{left, u.height - FOOT_Y * s}
	if u.pad {
		hint_row(u, foot, {{.Shoulders, .Set_Hint_Tab}})
	} else {
		hint_row(u, foot, {{.Up_Down, .Set_Hint_Choose}, {.Left_Right, .Set_Hint_Change}})
	}
	back = panel_back(u)
	return
}

// --- the games -----------------------------------------------------------------------

// The list of games: `confirm` is the slot whose erasing waits for a second press (0: none).
Games_State :: struct {
	sel:     int, // the slot chosen with the keys or the mouse (the pad has the focus)
	confirm: int,
}

// The games side by side (progress.SLOTS), in the side panel: each its place
// in the tale, its fragments and the day it was last saved, the one in play
// marked. Enter (South) or a click plays one (an empty one: a new game);
// Delete (West) or its × erases one, pressed twice.
games_menu :: proc(u: ^Ui, slots: []progress.Slot_Info, current: int, gs: ^Games_State) -> (chosen, erase: int, back: bool) {
	s := u.scale
	side_panel(u)
	x0 := PANEL_X * s
	w := PANEL_W * s
	y := panel_head(u, caps(i18n.tr(.Title)), i18n.tr(.Games)) + 10 * s
	ROW :: 112
	erase_key := rl.IsKeyPressed(.DELETE) || rl.IsKeyPressed(.BACKSPACE) || input.take(.West)
	if gs.sel == 0 {
		gs.sel = current
	}
	if rl.IsKeyPressed(.UP) {
		gs.sel = max(gs.sel - 1, 1)
	}
	if rl.IsKeyPressed(.DOWN) {
		gs.sel = min(gs.sel + 1, len(slots))
	}
	enter := !u.pad && (rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.SPACE))
	for info, i in slots {
		slot := i + 1
		r := rl.Rectangle{x0 - 20 * s, y, w + 40 * s, (ROW - 14) * s}
		add_hot(u, r)
		focus := focusable(u, r)
		over := mouse_over(u, r)
		if over && u.mouse_moved {
			gs.sel = slot
		}
		hover := u.pad ? focus : gs.sel == slot
		asking := gs.confirm == slot
		if hover {
			rl.DrawRectangleRec(r, fade({40, 24, 14, 255}, 0.55))
			corner_frame(u, r, 1, s, asking ? TITLE : BRIGHT)
		} else {
			rl.DrawRectangleRec(r, fade({13, 11, 20, 255}, 0.45))
			rl.DrawRectangleLinesEx(r, max(s, 1), fade(GOLD, 0.25))
		}
		if gs.confirm == slot && !hover {
			gs.confirm = 0 // the focus moved on: the question is withdrawn
		}
		head := caps(fmt.tprintf(i18n.tr(.Game_Slot), slot))
		if slot == current {
			head = fmt.tprintf("%s  ·  %s", head, caps(i18n.tr(.Game_Current)))
		}
		top := r.y + 16 * s
		text(u, head, {x0, top}, {size = 19, color = GOLD, face = .Semi, track = 0.2, shadow = true}, .Left)
		line_y := top + 32 * s
		if asking {
			text(u, i18n.tr(.Game_Erase_Ask), {x0, line_y}, {size = 28, color = TITLE, face = .Italic, shadow = true}, .Left)
		} else if info.used {
			level := progress.current_level(info.prog)
			text(u, level_name(level), {x0, line_y}, {size = 30, color = hover ? BRIGHT : TEXT, face = .Semi, shadow = true}, .Left)
			when_ := fmt.tprintf("%d / %d  %s", progress.fragment_count(info.prog), content.FRAGMENT_COUNT, i18n.tr(.Fragments_Label))
			if info.saved != {} {
				yy, mm, dd := time.date(info.saved)
				when_ = fmt.tprintf("%s   ·   %02d.%02d.%d", when_, dd, int(mm), yy)
			}
			text(u, when_, {r.x + r.width - 64 * s, top + 2 * s}, {size = 20, color = DIM, face = .Semi, track = 0.06}, .Right)
		} else {
			text(u, i18n.tr(.Game_Empty), {x0, line_y}, {size = 28, color = fade(DIM, 0.8), face = .Italic, shadow = true}, .Left)
		}
		// the × that erases a game (the mouse's way)
		if info.used {
			c := Vec2{r.x + r.width - 30 * s, r.y + r.height * 0.5}
			xr := rl.Rectangle{c.x - 16 * s, c.y - 16 * s, 32 * s, 32 * s}
			add_hot(u, xr)
			on_x := mouse_over(u, xr)
			col := fade(on_x || asking ? TITLE : GOLD, on_x || asking ? 1 : 0.5)
			rl.DrawLineEx(c + Vec2{-7, -7} * s, c + Vec2{7, 7} * s, 2 * s, col)
			rl.DrawLineEx(c + Vec2{-7, 7} * s, c + Vec2{7, -7} * s, 2 * s, col)
			if on_x && u.pressed {
				over = false // not also a choice of the row
				erase_key = true
				hover = true
			}
		}
		if hover && erase_key && info.used {
			audio.play(.Tap, -14, asking ? 0.75 : 1)
			if asking {
				erase = slot
				gs.confirm = 0
			} else {
				gs.confirm = slot
			}
		} else if (u.pad && activated(u, focus)) || (over && u.pressed) || (hover && enter) {
			audio.play(.Tap, -14)
			chosen = slot
			gs.confirm = 0
		}
		y += ROW * s
	}
	foot := Vec2{x0, u.height - FOOT_Y * s}
	if u.pad {
		hint_row(u, foot, {{.South, .Levels_Play}, {.Erase, .Game_Erase}})
	} else {
		hint_row(u, foot, {{.Up_Down, .Set_Hint_Choose}, {.Enter, .Levels_Play}, {.Erase, .Game_Erase}})
	}
	back = panel_back(u, focus = false)
	return
}

// A new game's difficulty, in the side panel: the three side by side as the
// games are, each its name and what it gives. `sel` the one chosen with the
// keys or the mouse (the pad has the focus); `chosen` ok when one is taken.
difficulty_menu :: proc(u: ^Ui, sel: ^progress.Difficulty) -> (chosen: progress.Difficulty, ok, back: bool) {
	s := u.scale
	side_panel(u)
	x0 := PANEL_X * s
	w := PANEL_W * s
	y := panel_head(u, caps(i18n.tr(.New_Game)), i18n.tr(.Difficulty_Head)) + 10 * s
	ROW :: 150
	if rl.IsKeyPressed(.UP) {
		sel^ = progress.Difficulty(max(int(sel^) - 1, 0))
	}
	if rl.IsKeyPressed(.DOWN) {
		sel^ = progress.Difficulty(min(int(sel^) + 1, len(progress.Difficulty) - 1))
	}
	enter := !u.pad && (rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.SPACE))
	for d in progress.Difficulty {
		r := rl.Rectangle{x0 - 20 * s, y, w + 40 * s, (ROW - 14) * s}
		add_hot(u, r)
		focus := focusable(u, r)
		over := mouse_over(u, r)
		if over && u.mouse_moved {
			sel^ = d
		}
		hover := u.pad ? focus : sel^ == d
		if hover {
			rl.DrawRectangleRec(r, fade({40, 24, 14, 255}, 0.55))
			corner_frame(u, r, 1, s, BRIGHT)
		} else {
			rl.DrawRectangleRec(r, fade({13, 11, 20, 255}, 0.45))
			rl.DrawRectangleLinesEx(r, max(s, 1), fade(GOLD, 0.25))
		}
		top := r.y + 16 * s
		text(u, i18n.tr(DIFFICULTY_NAME[d]), {x0, top}, {size = 32, color = hover ? BRIGHT : TEXT, face = .Semi, shadow = true}, .Left)
		desc := Style{size = 22, color = hover ? TEXT : DIM, face = .Italic, shadow = true}
		paragraph(u, i18n.tr(DIFFICULTY_DESC[d]), {x0, top + 46 * s}, desc, w - 20 * s, 1, 1.25, .Left)
		if (u.pad && activated(u, focus)) || (over && u.pressed) || (hover && enter) {
			audio.play(.Tap, -14)
			chosen, ok = d, true
		}
		y += ROW * s
	}
	text(u, i18n.tr(.Difficulty_Note), {x0, y + 6 * s}, {size = 22, color = DIM, face = .Italic, shadow = true}, .Left)
	foot := Vec2{x0, u.height - FOOT_Y * s}
	if u.pad {
		hint_row(u, foot, {{.South, .Levels_Play}})
	} else {
		hint_row(u, foot, {{.Up_Down, .Set_Hint_Choose}, {.Enter, .Levels_Play}})
	}
	back = panel_back(u, focus = false)
	return
}

// "[Esc] Back" at the foot of a panel; true when clicked.
@(private)
back_key :: proc(u: ^Ui, at: Vec2, align := Align.Left, focus := true) -> bool {
	s := u.scale
	label := i18n.tr(.Back)
	st := Style{size = 30, color = TEXT, shadow = true}
	m := measure(u, label, st)
	pos := at
	if align == .Right {
		pos.x -= (u.pad ? pad_button_width(u, .East) : key_cap_width(u, "Esc", s)) + 14 * s + m.x
	}
	r := rl.Rectangle{pos.x - 8 * s, pos.y - 8 * s, m.x + 90 * s, 46 * s}
	add_hot(u, r)
	hover := focus ? focusable(u, r) : mouse_over(u, r)
	cw := control(u, "Esc", .East, pos)
	if hover {
		st.color = BRIGHT
	}
	text(u, label, {pos.x + cw + 14 * s, pos.y + (30 * s - m.y) * 0.5}, st, .Left)
	if activated(u, hover) {
		audio.play(.Tap, -14)
		return true
	}
	return false
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
