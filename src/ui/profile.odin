package ui

// The profile of the game in play: what Psyche has gathered (the levels, the
// fragments, the achievements, the Notebook's entries, each act's fragments)
// and, lit by the lamp below, the doors to the Book, the Notebook, the
// achievements and the games.

import "core:fmt"
import rl "vendor:raylib"

import "../content"
import "../i18n"
import "../progress"

Profile_Action :: enum u8 {
	None,
	Book,
	Codex,
	Achievements,
	Games,
}

// `slot` the game in play (1-based), `reach` the furthest level reached.
profile :: proc(u: ^Ui, prog: progress.Progress, slot: int, reach: int) -> (act: Profile_Action, back: bool) {
	s := u.scale
	side_panel(u)
	x := PANEL_X * s
	w := PANEL_W * s
	diff := i18n.tr(.Difficulty_Custom)
	if d, ok := progress.difficulty_of(prog.aids); ok {
		diff = i18n.tr(DIFFICULTY_NAME[d])
	}
	y := panel_head(u, caps(fmt.tprintf(i18n.tr(.Profile_Eyebrow), slot, diff)), i18n.tr(.Profile_Title))
	text(u, fmt.tprintf(i18n.tr(.Profile_Next), level_name(reach)), {x, y - 14 * s}, {size = 24, color = DIM, face = .Italic, shadow = true}, .Left)
	y += 34 * s

	// the tally, in four tiles
	known := 0
	for _, id in CODEX {
		if codex_level(id) <= reach {
			known += 1
		}
	}
	Tile :: struct {
		n, of: int,
		label: i18n.Key,
	}
	tiles := [?]Tile {
		{card(prog.completed), content.LEVEL_COUNT, .Profile_Levels},
		{progress.fragment_count(prog), content.FRAGMENT_COUNT, .Profile_Fragments},
		{card(prog.achievements), len(progress.Achievement), .Profile_Achievements},
		{known, len(CODEX), .Profile_Notes},
	}
	GAP :: 14
	tw := (w - 3 * GAP * s) / 4
	th := 96 * s
	for t, i in tiles {
		r := rl.Rectangle{x + f32(i) * (tw + GAP * s), y, tw, th}
		rl.DrawRectangleRec(r, {24, 14, 10, 170})
		rl.DrawRectangleLinesEx(r, max(1.2 * s, 1), fade(GOLD, 0.35))
		num := fmt.tprintf("%d", t.n)
		nst := Style{size = 44, color = BRIGHT, face = .Display, shadow = true}
		text(u, num, {r.x + 14 * s, r.y + 8 * s}, nst, .Left)
		text(u, fmt.tprintf("/ %d", t.of), {r.x + 22 * s + measure(u, num, nst).x, r.y + 26 * s}, {size = 22, color = DIM, face = .Semi, shadow = true}, .Left)
		text(u, i18n.tr(t.label), {r.x + 14 * s, r.y + 60 * s}, {size = 21, color = DIM, face = .Italic, shadow = true}, .Left)
	}
	y += th + 34 * s

	// each act's fragments
	for a in content.Act {
		found, total := progress.act_fragments(prog, a)
		if total == 0 {
			continue
		}
		text(u, caps(i18n.tr(content.ACT_LABEL[a])), {x, y - 11 * s}, {size = 18, color = GOLD, face = .Semi, track = 0.18, shadow = true}, .Left)
		text(u, fmt.tprintf("%d / %d", found, total), {x + 130 * s, y - 12 * s}, {size = 20, color = DIM, face = .Semi, shadow = true}, .Left)
		bx := x + 212 * s
		bw := w - 212 * s - 120 * s // clear of the diorama
		rl.DrawRectangleRec({bx, y - 2 * s, bw, 4 * s}, fade(GOLD, 0.18))
		rl.DrawRectangleRec({bx, y - 2 * s, bw * f32(found) / f32(total), 4 * s}, fade(BRIGHT, 0.9))
		y += 36 * s
	}
	y += 40 * s

	// the doors, lit by the lamp
	Door :: struct {
		key: i18n.Key,
		act: Profile_Action,
	}
	doors := [?]Door{{.Book, .Book}, {.Codex, .Codex}, {.Book_Achievements, .Achievements}, {.Games, .Games}}
	lamp_keys(u, &u.profile_lit, len(doors), true)
	for d, i in doors {
		if lamp_choice(u, &u.profile_lit, i, i18n.tr(d.key), "", {x, y}, 30, 1) {
			act = d.act
		}
		y += 58 * s
	}

	foot := Vec2{x, u.height - FOOT_Y * s}
	if u.pad {
		hint_row(u, foot, {{.South, .Profile_Open}})
	} else {
		hint_row(u, foot, {{.Up_Down, .Set_Hint_Choose}, {.Enter, .Profile_Open}})
	}
	back = panel_back(u)
	return
}
