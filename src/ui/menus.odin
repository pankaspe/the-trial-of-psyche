// Full-screen menus: title, pause, level select, the Book, act and ending
// cards, settings, achievement notices, the debug overlay.
package ui

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

import "../audio"
import "../content"
import "../fx"
import "../game"
import "../i18n"
import "../input"
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
	rl.DrawRectangleRec({0, 0, u.width, u.height}, fade({8, 4, 3, 255}, alpha))
}

// The lamp's side of the screen: the left half warmed and darkened, for the
// title and the pause menu.
@(private)
lamp_side :: proc(u: ^Ui, alpha: f32) {
	rl.DrawRectangleGradientH(0, 0, i32(u.width * 0.55), i32(u.height), fade({26, 12, 10, 255}, 0.74 * alpha), {26, 12, 10, 0})
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
title_menu :: proc(u: ^Ui, alpha: f32 = 1, lift: f32 = 0) -> (act: Menu_Action) {
	s := u.scale
	lamp_side(u, alpha)
	x := 144 * s
	y := u.height * 0.5 - 315 * s - lift * s
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
	if menu_item(u, i18n.tr(.Play), {x, y}, 38, true, alpha) {
		act = .Play
	}
	y += 62 * s
	items := [?]Choice{{.Levels, .Levels}, {.Book, .Book}, {.Settings, .Settings}, {.Quit, .Quit}}
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

pause_menu :: proc(u: ^Ui, lamp: bool) -> (act: Menu_Action) {
	s := u.scale
	shade(u, 0.5)
	lamp_side(u, 1)
	x := 144 * s
	y := u.height * 0.5 - 230 * s
	text(u, i18n.tr(.Pause_Title), {x - 3 * s, y}, {size = 104, color = TITLE, face = .Display, glow = true, shadow = true}, .Left)
	y += 150 * s
	ornament(u, {x + 100 * s, y}, 100 * s)
	y += 62 * s
	items := [?]Choice{{.Resume, .Resume}, {.Restart, .Restart}, {.Settings, .Settings}, {.Menu, .Main_Menu}}
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

// The card after an ending; `t` is the time since it appeared.
ending_card :: proc(u: ^Ui, info: Ending_Info, t: f32) -> (act: Menu_Action) {
	s := u.scale
	// after an exit the card floats on the veil between the levels: a lighter shade
	veiled := info.ending == .Exit
	focus_shade(u, clamp(t / 1.2, 0, 1) * (veiled ? 0.4 : 1))
	shade(u, (veiled ? 0.08 : 0.25) * clamp(t / 1.5, 0, 1))
	a := clamp(t / 2, 0, 1)
	cx := u.width * 0.5
	body := Style{size = 36, color = TEXT, face = .Italic, shadow = true}

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
	extra := f32(card(info.unlocked)) * 40 * s
	bh := block_height(u, msg, body, 1100 * s, 1.3)
	y := u.height * 0.5 - (bh + 320 * s + extra) * 0.5
	text(u, title, {cx, y}, {size = 96, color = title_col, face = .Display, glow = true, shadow = true}, .Center, a)
	y += 126 * s
	ornament(u, {cx, y}, 160 * s, a)
	y += 30 * s
	y += paragraph(u, msg, {cx, y}, body, 1100 * s, a, 1.3)
	y += 40 * s
	text(u, note, {cx, y}, {size = 26, color = DIM, face = .Italic, shadow = true}, .Center, a)
	y += 50 * s
	a_ach := clamp((t - 1.5) / 1, 0, 1)
	for ach in info.unlocked {
		line := fmt.tprintf("%s · %s", i18n.tr(.Achievement), i18n.tr(progress.ACHIEVEMENT_NAME[ach]))
		text(u, line, {cx, y}, {size = 26, color = GOLD, face = .Semi, shadow = true}, .Center, a_ach)
		y += 40 * s
	}
	y += 40 * s
	all := [?]Choice{{.Next, .Next}, {.Retry, .Retry}, {.Menu, .Main_Menu}}
	buttons := info.can_continue ? all[:] : all[1:]
	gap := 300 * s
	x := cx - gap * f32(len(buttons) - 1) * 0.5
	for b in buttons {
		if button(u, i18n.tr(b.key), {x, y}, 32, a) {
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
	text(u, i18n.tr(.Levels_Title), {cx, u.height * 0.5 - 470 * s}, {size = 84, color = TITLE, face = .Display, glow = true, shadow = true})
	count := fmt.tprintf("%s  %d / %d", i18n.tr(.Fragments_Label), progress.fragment_count(prog), content.FRAGMENT_COUNT)
	rule_label(u, caps(count), {cx, u.height * 0.5 - 372 * s}, 20, 80 * s)

	TILE :: Vec2{150, 92}
	GAP :: 18
	row_y := u.height * 0.5 - 300 * s
	left := cx - 760 * s
	tiles_x := cx - 280 * s
	hovered := -1
	for act in content.Act {
		text(u, caps(i18n.tr(content.ACT_LABEL[act])), {left, row_y + 10 * s}, {size = 20, color = GOLD, face = .Semi, track = 0.18, shadow = true}, .Left, 0.9)
		text(u, i18n.tr(content.ACT_TITLE[act]), {left, row_y + 40 * s}, {size = 34, color = TEXT, shadow = true}, .Left)
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
			hover := focusable(u, r)
			if hover {
				hovered = i
			}
			alpha: f32 = open ? 1 : (built ? 0.55 : 0.3)
			rl.DrawRectangleRec(r, fade({13, 11, 20, 255}, (hover && open ? 0.88 : 0.66) * alpha))
			edge := done ? fade(GOLD, 0.65) : fade(GOLD, 0.22 * alpha)
			rl.DrawRectangleLinesEx(r, max(1.2 * s, 1), hover && open ? BRIGHT : edge)
			if hover && open {
				corner_frame(u, {r.x - 4 * s, r.y - 4 * s, r.width + 8 * s, r.height + 8 * s}, 1, s, BRIGHT)
			}
			col := done ? TEXT : DIM
			if hover && open {
				col = BRIGHT
			}
			label := info.act == .Epilogue ? "E" : info.id
			text(u, label, {r.x + r.width * 0.5, r.y + 10 * s}, {size = 34, color = col, face = .Semi, shadow = true}, .Center, alpha)
			if built {
				// a mark per fragment hidden in the level
				first, count := content.level_fragments(i)
				for k in 0 ..< count {
					dx := (f32(k) - f32(count - 1) * 0.5) * 22 * s
					diamond(u, {r.x + r.width * 0.5 + dx, r.y + r.height - 18 * s}, 8 * s, fade(GOLD, alpha * 0.9), first + k in prog.fragments)
				}
			}
			if open && activated(u, hover) {
				audio.play(.Tap, -14)
				chosen = i
			}
		}
		row_y += 128 * s
	}

	if hovered >= 0 {
		y := u.height * 0.5 + 345 * s
		text(u, level_name(hovered), {cx, y}, {size = 38, color = TEXT, shadow = true})
		status := ""
		if !content.is_built(hovered) {
			status = i18n.tr(.Level_Unbuilt)
		} else if !progress.is_unlocked(prog, hovered) {
			status = i18n.tr(.Level_Locked)
		}
		text(u, status, {cx, y + 50 * s}, {size = 26, color = DIM, face = .Italic, shadow = true})
	}
	back = button(u, i18n.tr(.Back), {cx, u.height * 0.5 + 460 * s}, 30)
	return
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
	labels := [BOOK_TABS]string{"I", "II", "III", "IV", "E", ""}
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
			text(u, labels[i], {c.x, c.y - measure(u, labels[i], st).y * 0.5}, st)
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
	hint_y := book_r.y + book_r.height + 26 * s
	st := Style{size = 22, color = DIM, face = .Semi, track = 0.1}
	if u.pad {
		x := cx - 260 * s
		x += pad_button(u, .LB, {x, hint_y}, 0.9) + 6 * s
		x += pad_button(u, .RB, {x, hint_y}, 0.9) + 12 * s
		text(u, i18n.tr(.Book_Turn), {x, hint_y + 2 * s}, st, .Left)
	} else {
		// key caps with drawn arrows (the fonts have none)
		turn_w := measure(u, i18n.tr(.Book_Turn), st).x
		choose_w := measure(u, i18n.tr(.Book_Choose), st).x
		cap := 30 * s
		reading := b.tab < BOOK_ACHIEVEMENTS
		total := reading ? 4 * cap + 3 * 6 * s + 2 * 12 * s + turn_w + choose_w + 50 * s : 2 * cap + 12 * s + turn_w
		x := cx - total * 0.5
		for d in ([4]int{0, 1, 2, 3}) {
			if d == 2 && !reading {
				break
			}
			arrow_cap(u, {x, hint_y}, cap, d)
			x += cap + 6 * s
			if d == 1 {
				x += 6 * s
				text(u, i18n.tr(.Book_Turn), {x, hint_y + 2 * s}, st, .Left)
				x += turn_w + 50 * s
			}
		}
		if reading {
			x += 6 * s
			text(u, i18n.tr(.Book_Choose), {x, hint_y + 2 * s}, st, .Left)
		}
	}
	back = button(u, i18n.tr(.Back), {cx, cy + 470 * s}, 30)
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

// A short notice in the top left corner: an achievement just unlocked.
achievement_toast :: proc(u: ^Ui, a: progress.Achievement, t: f32) {
	alpha := fx.envelope(t, 0.5, 3.5, 1.0)
	if alpha <= 0 {
		return
	}
	s := u.scale
	name := i18n.tr(progress.ACHIEVEMENT_NAME[a])
	nst := Style{size = 32, color = TEXT, face = .Semi}
	w := max(measure(u, name, nst).x, 220 * s) + 96 * s
	r := rl.Rectangle{32 * s, 32 * s, w, 96 * s}
	warm_card(u, r, alpha, 0.45)
	c := Vec2{r.x + 36 * s, r.y + r.height * 0.5}
	glow_dot(c, 9 * s, {255, 176, 77, 255}, alpha)
	diamond(u, c, 11 * s, fade(BRIGHT, alpha), true)
	text(u, caps(i18n.tr(.Achievement)), {r.x + 68 * s, r.y + 16 * s}, {size = 18, color = GOLD, face = .Semi, track = 0.16}, .Left, alpha)
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
}

Setting_Changes :: bit_set[Setting_Field]

// The pages of the settings panel.
Settings_Tab :: enum u8 {
	General,
	Graphics,
	Audio,
	Access,
}

@(private)
TAB_KEY := [Settings_Tab]i18n.Key {
	.General  = .Set_General,
	.Graphics = .Set_Graphics,
	.Audio    = .Set_Audio,
	.Access   = .Set_Access,
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

// The settings panel, in tabs: edits `cfg` in place and reports what changed.
// On the Graphics tab the game behind shows through, so the quality can be
// judged while it is changed.
settings_menu :: proc(u: ^Ui, cfg: ^settings.Settings, resolutions: [][2]i32, native: [2]i32) -> (changes: Setting_Changes, back: bool) {
	s := u.scale
	tab := &u.settings_tab
	// a sheet of dark glass on the left; the game stays in view on the right
	// (clear on the Graphics tab, so the visual style can be judged)
	sheet := 705 * s
	rl.DrawRectangleRec({sheet, 0, u.width - sheet, u.height}, fade({3, 3, 10, 255}, tab^ == .Graphics ? 0 : 0.3))
	glass_panel(u, {0, 0, sheet, u.height})
	left := 84 * s
	right := sheet - 72 * s
	text(u, i18n.tr(.Set_Title), {left, 76 * s}, {size = 80, color = TITLE, face = .Display, shadow = true}, .Left)

	// the tabs
	ty := 196 * s
	x := left
	for t in Settings_Tab {
		label := i18n.tr(TAB_KEY[t])
		st := Style{size = 30, color = t == tab^ ? BRIGHT : fade(TEXT, 0.6)}
		m := measure(u, label, st)
		r := rl.Rectangle{x - 12 * s, ty - 6 * s, m.x + 24 * s, m.y + 12 * s}
		add_hot(u, r)
		hover := mouse_over(u, r)
		if hover && t != tab^ {
			st.color = TEXT
		}
		text(u, label, {x, ty}, st, .Left)
		if t == tab^ {
			rl.DrawRectangleRec({x, ty + 50 * s, m.x, max(3 * s, 1)}, BRIGHT)
		}
		if hover && u.pressed && t != tab^ {
			audio.play(.Tap, -14)
			tab^ = t
			reset_focus(u)
		}
		x += m.x + 42 * s
	}
	// the pad's shoulders go through the tabs
	if u.pad {
		pad_button(u, .RB, {x - 20 * s, ty + 4 * s}, 0.9)
		pad_button(u, .LB, {left - pad_button_width(u, .LB) - 22 * s, ty + 4 * s}, 0.9)
		n := len(Settings_Tab)
		step := 0
		if input.take(.LB) {
			step = -1
		}
		if input.take(.RB) {
			step = 1
		}
		if step != 0 {
			audio.play(.Tap, -14)
			tab^ = Settings_Tab((int(tab^) + step + n) % n)
			reset_focus(u)
		}
	}
	hairline(u, left, ty + 52 * s, right - left, {255, 255, 255, 30})

	y := ty + 92 * s
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
		if step := option_row(u, i18n.tr(.Set_Endless_Oil), on_off(cfg.endless_oil), y, left, right); step != 0 {
			cfg.endless_oil = !cfg.endless_oil
			changes += {.Access}
		}
	}
	back = back_key(u, {left, u.height - 100 * s})
	return
}

// "[Esc] Back" at the foot of a panel; true when clicked.
@(private)
back_key :: proc(u: ^Ui, pos: Vec2) -> bool {
	s := u.scale
	label := i18n.tr(.Back)
	st := Style{size = 30, color = TEXT}
	m := measure(u, label, st)
	r := rl.Rectangle{pos.x - 8 * s, pos.y - 8 * s, m.x + 90 * s, 46 * s}
	add_hot(u, r)
	hover := focusable(u, r)
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
