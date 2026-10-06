// Walkthroughs of the first three levels of Act I, played through the game
// rules frame by frame (no window): each one checks the intended route, the
// mechanic it teaches, the fragment and the exit.
package tests

import "core:testing"
import sa "core:container/small_array"

import "../src/game"
import "../src/i18n"
import "../src/iso"
import "../src/palace"

@(private)
start_level :: proc(t: ^testing.T, g: ^game.Game, index: int) -> bool {
	if err := game.load(g, index); err != nil {
		testing.expectf(t, false, "level %d does not load", index)
		return false
	}
	game.begin(g, prologue = false)
	run(g, game.WELCOME_DELAY + 0.1)
	return true
}

// Can Psyche go from her cell to c in the current view?
@(private)
can_reach :: proc(g: ^game.Game, c: iso.Cell) -> bool {
	path: palace.Path
	return palace.find_path(&g.palace, g.psyche.cell, c, !g.lamp_on, &path)
}

@(private)
exits :: proc(t: ^testing.T, g: ^game.Game) {
	run(g, game.EXIT_END + 0.5)
	testing.expect(t, g.phase == .Finished && g.ending == .Exit, "the exit ends the level")
	testing.expect(t, game.exit_lift(g) > 1, "the wind lifts Psyche")
	testing.expect(t, g.data.has_outro, "the level has its own ending text")
}

// I.1: walk down the crag; the rock where Zephyr waits joins the edge only
// when the crag is turned.
@(test)
level_I_1_zephyrs_crag :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !start_level(t, &g, 0) {
		return
	}
	testing.expect(t, !g.data.has_lamp, "no lamp on the crag")
	testing.expect(t, g.hud.hint.active && g.hud.hint.key == .Hint_Move, "the first hint at the start")
	run(&g, 15)
	testing.expect(t, game.fade_alpha(g.hud.hint) > 0.9, "a tutorial hint stays until it is done")
	game.click(&g, palace.node_screen(&g.palace, {4, 1, 5}, g.angle))
	run(&g, 1)
	testing.expect(t, game.fade_alpha(g.hud.hint) == 0 && g.learned[i18n.Key.Hint_Move], "a click on a tile moves Psyche and the hint goes")
	EDGE :: iso.Cell{4, 5, 3}
	testing.expect(t, walk(t, &g, EDGE), "the path down the crag needs no turn")
	testing.expect(t, g.hud.hint.key == .Hint_Turn, "at the edge: the turning hint")
	testing.expect(t, !can_reach(&g, g.data.exit), "the first view does not join Zephyr's rock")
	game.request_turn(&g, -1)
	run(&g, 1)
	testing.expect(t, game.rot(&g) == 3, "one turn")
	testing.expect(t, !g.hud.hint.active, "turning dismisses the turning hint")
	testing.expect(t, walk(t, &g, g.data.exit), "the turned crag joins the edge to the rock")
	exits(t, &g)
}

// I.2: three seams, each closed by its own view; the fragment from a fourth.
// It starts in the view that shows Psyche on the lawn, joined to nothing.
@(test)
level_I_2_invisible_palace :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !start_level(t, &g, 1) {
		return
	}
	testing.expect(t, !g.data.has_lamp, "no lamp in the palace of voices")
	COURT :: iso.Cell{5, 5, 2}
	BATHS :: iso.Cell{4, 2, 3}
	testing.expect(t, !can_reach(&g, COURT), "the first view joins the lawn to nothing")
	run(&g, game.start_cues_time(&g))
	testing.expect(t, g.hud.hint.key == .Hint_Illusion && game.fade_alpha(g.hud.hint) > 0, "after the intro: the lesson of the illusions")
	game.set_view(&g, 1)
	testing.expect(t, palace.is_illusion(&g.palace, g.psyche.cell, COURT), "the first seam, one turn away")
	testing.expect(t, walk(t, &g, COURT), "the lawn leads to the court")
	testing.expect(t, g.learned[i18n.Key.Hint_Illusion], "crossing a seam ends the lesson")
	testing.expect(t, !can_reach(&g, BATHS), "the baths are not joined yet")
	game.set_view(&g, 2)
	testing.expect(t, walk(t, &g, BATHS), "view 2 joins the court to the baths")
	testing.expect(t, !can_reach(&g, g.data.exit), "the bedchamber is not joined in view 2")
	game.set_view(&g, 0)
	testing.expect(t, walk(t, &g, g.data.exit), "the first view joins the baths to the bedchamber")
	exits(t, &g)

	// the fragment: from the court, in view 3
	h: game.Game
	defer game.destroy(&h)
	if !start_level(t, &h, 1) {
		return
	}
	game.set_view(&h, 1)
	testing.expect(t, walk(t, &h, COURT), "back to the court")
	for r in ([3]int{0, 1, 2}) {
		game.set_view(&h, r)
		testing.expectf(t, !can_reach(&h, h.data.fragment), "view %d does not join the fragment's column", r)
	}
	game.set_view(&h, 3)
	testing.expect(t, walk(t, &h, h.data.fragment) && h.fragment_taken, "view 3 does")
}

// I.3: hidden stairs. The first flight hides in the first view, the second
// in the view that joins the terrace to the crag.
@(test)
level_I_3_sisters :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !start_level(t, &g, 2) {
		return
	}
	TERRACE :: iso.Cell{4, 4, 2}
	LEDGE :: iso.Cell{5, 3, 3}
	STAIRS_TOP :: iso.Cell{7, 5, 4}
	DECOY :: iso.Cell{5, 6, 4}
	testing.expect(t, !can_reach(&g, TERRACE), "view 0: the first stairs are hidden")
	testing.expect(t, walk(t, &g, DECOY), "the decoy tower is joined to the garden")
	for r in 0 ..< 4 {
		game.set_view(&g, r)
		testing.expectf(t, !can_reach(&g, g.data.exit), "view %d: the tower leads nowhere", r)
	}
	game.set_view(&g, 0)
	testing.expect(t, walk(t, &g, g.data.start), "back down to the garden")
	game.set_view(&g, 1)
	testing.expect(t, walk(t, &g, TERRACE) && walk(t, &g, LEDGE), "view 1: up the stairs and across to the crag")
	testing.expect(t, g.learned[i18n.Key.Hint_Stairs], "climbing in the dark ends the lesson of the stairs")
	testing.expect(t, !can_reach(&g, STAIRS_TOP), "view 1: the second stairs are hidden")
	game.toggle_lamp(&g)
	testing.expect(t, !g.lamp_on, "no lamp to cheat with")
	game.set_view(&g, 2)
	testing.expect(t, walk(t, &g, STAIRS_TOP), "another view shows the stairs")
	game.set_view(&g, 1)
	testing.expect(t, walk(t, &g, g.data.fragment) && g.fragment_taken, "view 1 joins the stairs' top to the second tower")
	testing.expect(t, walk(t, &g, STAIRS_TOP), "and back")
	game.set_view(&g, 2)
	testing.expect(t, walk(t, &g, g.data.exit), "the top of the crag")
	exits(t, &g)
}

// The prologue of I.1: the procession climbs to the summit and goes back;
// a key skips to Psyche alone, the next one starts the level.
@(test)
prologue :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if err := game.load(&g, 0); err != nil {
		testing.expect(t, false, "I.1 does not load")
		return
	}
	testing.expect(t, g.data.has_prologue, "I.1 opens with the prologue")
	game.begin(&g)
	testing.expect(t, g.phase == .Prologue && !g.hud.visible, "the cutscene runs first, without the HUD")
	testing.expect(t, sa.len(g.prologue.route) >= 2 && sa.get(g.prologue.route, sa.len(g.prologue.route) - 1) == g.data.start, "the procession's route ends at the start")
	run(&g, game.prologue_arrive(&g) + 0.1)
	testing.expect(t, g.psyche.pos == palace.node_world(&g.palace, g.data.start), "Psyche reaches the summit")
	torches := 0
	for i in 0 ..< game.MOURNERS {
		m := game.prologue_mourner(&g, i)
		torches += int(m.torch > 0.99 && m.alpha > 0.99)
	}
	testing.expect(t, torches == game.MOURNERS, "the mourners stand behind her with their torches lit")
	game.toggle_lamp(&g)
	game.request_turn(&g, 1)
	testing.expect(t, !g.turning && !g.lamp_on, "no play during the cutscene")

	game.prologue_advance(&g)
	run(&g, 0.1)
	testing.expect(t, g.phase == .Prologue && !game.prologue_ready(&g), "a key skips to Psyche alone")
	for i in 0 ..< game.MOURNERS {
		m := game.prologue_mourner(&g, i)
		testing.expectf(t, m.alpha < 0.01 && m.torch < 0.01, "mourner %d is gone, torch out", i)
	}
	run(&g, game.PRO_PROMPT + 0.1)
	testing.expect(t, game.prologue_ready(&g), "then the invitation to begin")
	game.prologue_advance(&g)
	testing.expect(t, g.phase == .Play && g.hud.visible && game.rot(&g) == 0 && g.angle == 0, "the level starts in view 0")
	run(&g, game.WELCOME_DELAY + 0.1)
	testing.expect(t, g.hinted[i18n.Key.Hint_Move], "with its first hint")

	// a restart does not show it again
	h: game.Game
	defer game.destroy(&h)
	game.load(&h, 0)
	game.begin(&h, prologue = false)
	testing.expect(t, h.phase == .Play, "restart: straight to play")
}
