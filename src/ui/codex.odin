// Psyche's Notebook: every mechanic met so far, in the side panel, in four
// tabs after the two tools (the world, the lamp, the spindle, the actions of
// the place). An entry shows once the level that brings it is reached; the
// others wait as "still to discover". What the level in play holds is in gold.
package ui

import rl "vendor:raylib"

import "../audio"
import "../content"
import "../game"
import "../i18n"
import "../input"
import "../level"

Codex_Tab :: enum u8 {
	World,
	Lamp,
	Spindle,
	Place,
}

@(private)
CODEX_TAB_KEY := [Codex_Tab]i18n.Key {
	.World   = .Codex_World,
	.Lamp    = .Lamp_Button,
	.Spindle = .Spindle_Button,
	.Place   = .Codex_Place,
}

Codex_Id :: enum u8 {
	Illusion,
	Turn,
	Stairs,
	Fragments,
	Rest,
	Dead_End,
	Lamp,
	Oil,
	Seal,
	Veiled,
	Trap,
	Guard,
	Handle,
	Time,
	Rams,
	Flip,
	Cave,
	Eagle,
	Boat,
	Ferry,
}

// The keys and buttons an entry is used with (none: count 0; `space`: the
// space bar, named in the language).
Codex_Control :: struct {
	keys:    [2]string,
	buttons: [2]input.Button,
	count:   int,
	space:   bool,
}

Codex_Entry :: struct {
	tab:     Codex_Tab,
	title:   i18n.Key,
	text:    i18n.Key,
	sign:    i18n.Key, // the drawing of `tutorial_sign`
	level:   string, // the id of the level that brings it
	control: Codex_Control,
}

@(private)
LAMP_CONTROL :: Codex_Control{{"1", ""}, {.LT, .LT}, 1, false}
@(private)
SPINDLE_CONTROL :: Codex_Control{{"2", ""}, {.RT, .RT}, 1, false}
@(private)
PLACE_CONTROL :: Codex_Control{{"", ""}, {.South, .South}, 1, true}

CODEX := [Codex_Id]Codex_Entry {
	.Illusion  = {.World, .Codex_Illusion_Title, .Codex_Illusion, .Hint_Illusion, "I.1", {}},
	.Turn      = {.World, .Codex_Turn_Title, .Codex_Turn, .Hint_Turn, "I.1", {{"Q", "E"}, {.LB, .RB}, 2, false}},
	.Stairs    = {.World, .Codex_Stairs_Title, .Codex_Stairs, .Codex_Stairs_Title, "I.3", {}},
	.Fragments = {.World, .Codex_Fragments_Title, .Codex_Fragments, .Hint_Fragment, "I.1", {}},
	.Rest      = {.World, .Codex_Rest_Title, .Codex_Rest, .Hint_Rest, "II.1", {{"R", ""}, {.East, .East}, 1, false}},
	.Dead_End  = {.World, .Codex_Dead_End_Title, .Codex_Dead_End, .Codex_Dead_End_Title, "II.1", {}},
	.Lamp      = {.Lamp, .Codex_Lamp_Title, .Codex_Lamp, .Codex_Lamp_Title, "I.4", LAMP_CONTROL},
	.Oil       = {.Lamp, .Codex_Oil_Title, .Codex_Oil, .Hint_Oil, "I.4", {}},
	.Seal      = {.Lamp, .Codex_Seal_Title, .Codex_Seal, .Hint_Sigil, "I.4", {}},
	.Veiled    = {.Lamp, .Codex_Veiled_Title, .Codex_Veiled, .Codex_Veiled_Title, "II.1", {}},
	.Trap      = {.Lamp, .Codex_Trap_Title, .Codex_Trap, .Hint_Trap, "II.1", {}},
	.Guard     = {.Lamp, .Codex_Guard_Title, .Codex_Guard, .Hint_Guard, "IV.1", {}},
	.Handle    = {.Spindle, .Codex_Handle_Title, .Codex_Handle, .Codex_Handle_Title, "II.3", SPINDLE_CONTROL},
	.Time      = {.Spindle, .Codex_Time_Title, .Codex_Time, .Hint_Sundial, "III.1", SPINDLE_CONTROL},
	.Rams      = {.Spindle, .Codex_Rams_Title, .Codex_Rams, .Codex_Rams_Title, "III.2", {}},
	.Flip      = {.Spindle, .Codex_Flip_Title, .Codex_Flip, .Hint_Pomegranate, "IV.2", SPINDLE_CONTROL},
	.Cave      = {.Place, .Codex_Cave_Title, .Codex_Cave, .Codex_Cave_Title, "II.2", PLACE_CONTROL},
	.Eagle     = {.Place, .Codex_Eagle_Title, .Codex_Eagle, .Hint_Eagle, "III.3", PLACE_CONTROL},
	.Boat      = {.Place, .Codex_Boat_Title, .Codex_Boat, .Hint_Boat, "IV.1", PLACE_CONTROL},
	.Ferry     = {.Place, .Codex_Ferry_Title, .Codex_Ferry, .Hint_Boat, "IV.4", PLACE_CONTROL},
}

// The index of the level that brings an entry.
codex_level :: proc(id: Codex_Id) -> int {
	for info, i in content.LEVELS {
		if info.id == CODEX[id].level {
			return i
		}
	}
	return content.LEVEL_COUNT
}

// Does the level hold this piece? (Only the pieces a level may have or not:
// the illusions, the turning and the like are everywhere.)
holds :: proc(d: ^level.Level_Data, id: Codex_Id) -> bool {
	guards := card(d.guard_seals)
	#partial switch id {
	case .Rest: return len(d.rests) > 0
	case .Lamp, .Oil: return d.has_lamp
	case .Seal: return len(d.sigils) > guards
	case .Veiled, .Trap:
		for e in d.blocks {
			if e.trait == .Veiled && (id == .Veiled || e.trap) {
				return true
			}
		}
	case .Guard: return guards > 0
	case .Handle: return len(d.handles) > 0
	case .Time: return len(d.sundials) > 0
	case .Rams: return len(d.rams) > 0
	case .Flip: return len(d.pomegranates) > 0
	case .Cave: return len(d.caves) > 0
	case .Eagle: return len(d.eagles) > 0
	case .Boat: return d.has_boat || len(d.ferries) > 0
	case .Ferry: return len(d.ferries) > 0
	}
	return false
}

// The Notebook over the game `g`: `reach` the furthest level reached (its
// entries and those before it show), `in_play` the level is being played
// (what it holds is in gold; not over the title's sleeping palace).
codex :: proc(u: ^Ui, g: ^game.Game, reach: int, in_play: bool) -> (back: bool) {
	s := u.scale
	tab := &u.codex_tab
	side_panel(u)
	left := PANEL_X * s
	width := CODEX_W * s

	labels: [len(Codex_Tab)]string
	for t in Codex_Tab {
		labels[int(t)] = caps(i18n.tr(CODEX_TAB_KEY[t]))
	}
	turn := 0
	if clicked, _ := tab_row(u, labels[:], int(tab^)); clicked >= 0 {
		turn = clicked - int(tab^)
	}
	if input.take(.LB) || rl.IsKeyPressed(.LEFT) {
		turn = -1
	}
	if input.take(.RB) || rl.IsKeyPressed(.RIGHT) {
		turn = 1
	}
	if turn != 0 {
		n := len(Codex_Tab)
		audio.play(.Tap, -14)
		tab^ = Codex_Tab((int(tab^) + turn + n) % n)
	}
	y := panel_head(u, caps(i18n.tr(.Codex_Title)), i18n.tr(CODEX_TAB_KEY[tab^])) + 6 * s

	title_st := Style{size = 30, color = BRIGHT, face = .Semi, shadow = true}
	body_st := Style{size = 22, color = DIM, face = .Body, shadow = true}
	tag_st := Style{size = 17, color = GOLD, face = .Semi, track = 0.16, shadow = true}
	plate :: 34 // half the sign's plate
	text_x := left + (2 * plate + 26) * s
	text_w := width - (2 * plate + 26) * s
	for e, id in CODEX {
		if e.tab != tab^ {
			continue
		}
		known := codex_level(id) <= reach
		in_level := known && in_play && holds(&g.data, id)
		c := Vec2{left + plate * s, y + plate * s}
		r := rl.Rectangle{c.x - plate * s, c.y - plate * s, 2 * plate * s, 2 * plate * s}
		rl.DrawRectangleRec(r, {40, 24, 14, 200})
		rl.DrawRectangleLinesEx(r, max(1.5 * s, 1), fade(GOLD, in_level ? 1 : 0.45))
		if !known {
			diamond(u, c, 12 * s, fade(DIM, 0.5), false)
			text(u, i18n.tr(.Codex_Locked), {text_x, c.y - 16 * s}, {size = 26, color = fade(DIM, 0.6), face = .Italic, shadow = true}, .Left)
			y += (2 * plate + 22) * s
			continue
		}
		tutorial_sign(u, g, e.sign, c, GOLD)
		st := title_st
		if in_level {
			st.color = TITLE
		}
		title := i18n.tr(e.title)
		text(u, title, {text_x, y - 4 * s}, st, .Left)
		if in_level {
			text(u, caps(i18n.tr(.Codex_Here)), {text_x + measure(u, title, st).x + 16 * s, y + 6 * s}, tag_st, .Left)
		}
		// its keys (or buttons), at the right end of the title's line
		ctl := e.control
		cx := left + width
		for k := ctl.count - 1; k >= 0; k -= 1 {
			key := ctl.space ? i18n.tr(.Key_Space) : ctl.keys[k]
			w := u.pad ? pad_button_width(u, ctl.buttons[k]) : key_cap_width(u, key, s)
			cx -= w
			control(u, key, ctl.buttons[k], {cx, y - 2 * s}, 0.9)
			cx -= 8 * s
		}
		h := paragraph(u, i18n.tr(e.text), {text_x, y + 34 * s}, body_st, text_w, 1, 1.22, .Left)
		y += max(2 * plate * s, 34 * s + h) + 20 * s
	}

	foot := Vec2{left, u.height - FOOT_Y * s}
	if u.pad {
		hint_row(u, foot, {{.Shoulders, .Set_Hint_Tab}})
	} else {
		hint_row(u, foot, {{.Left_Right, .Set_Hint_Tab}})
	}
	return panel_back(u)
}

CODEX_W :: PANEL_W + 20 // the Notebook's column (1080p units), clear of the diorama
