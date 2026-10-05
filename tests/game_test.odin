// Level I.4 played through the game rules, frame by frame, without a window.
package tests

import "core:testing"

import "../src/game"
import "../src/i18n"
import "../src/iso"
import "../src/palace"

BEDSIDE :: iso.Cell{6, 5, 5}
DT :: 1.0 / 60.0

@(private)
run :: proc(g: ^game.Game, seconds: f32) {
	for _ in 0 ..< int(seconds / DT) {
		game.update(g, DT)
		free_all(context.temp_allocator)
	}
}

// Walk to target and wait for the end of the walk (or 30 s).
@(private)
walk :: proc(t: ^testing.T, g: ^game.Game, target: iso.Cell) -> bool {
	if !game.walk_to(g, target) {
		testing.expectf(t, false, "no path from %v to %v", g.psyche.cell, target)
		return false
	}
	for i := 0; g.psyche.walking && i < 1800; i += 1 {
		game.update(g, DT)
		free_all(context.temp_allocator)
	}
	return g.psyche.cell == target
}

@(private)
start :: proc(t: ^testing.T, g: ^game.Game) -> bool {
	if err := game.load(g, LAMP_LEVEL); err != nil {
		testing.expect(t, false, "level I.4 does not load")
		return false
	}
	game.begin(g)
	return true
}

@(test)
lamp_level_rules :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !start(t, &g) {
		return
	}
	run(&g, 2)
	testing.expect(t, g.hud.voice.active && g.hud.voice.key == .Intro_I_4, "the level opens with its intro line")

	game.set_view(&g, 3)
	testing.expect(t, walk(t, &g, TERRACE), "Psyche crosses the gap to the west terrace in view 3")
	testing.expect(t, !game.walk_to(&g, BALCONY), "view 3: the hidden stairs do not lead up in the dark")
	game.request_turn(&g, 1)
	run(&g, 1)
	testing.expect(t, game.rot(&g) == 0, "turned to view 0, where the stairs show")
	testing.expect(t, walk(t, &g, BALCONY), "Psyche climbs the stairs to the balcony")
	game.set_view(&g, 3)

	game.request_turn(&g, -1)
	run(&g, 1)
	testing.expect(t, game.rot(&g) == 2 && !g.turning, "the animated turn ends on view 2")
	game.set_view(&g, 1)
	testing.expect(t, walk(t, &g, g.data.sigil), "Psyche reaches the seal in view 1")

	game.toggle_lamp(&g)
	testing.expect(t, g.lamp_on, "the lamp is lit")
	oil := g.oil
	run(&g, 0.5)
	testing.expect(t, g.activated && g.phase == .Sigil, "the lamp on the seal starts the rising")
	testing.expect(t, g.oil < oil, "oil burns while lit")
	run(&g, game.rise_duration(&g) + 0.2)
	testing.expect(t, g.phase == .Play && g.palace.risen, "the bridge has risen and play resumes")
	testing.expect(t, g.learned[i18n.Key.Hint_Sigil], "the seal's lesson is done")
	run(&g, 2)
	testing.expect(t, g.stain_count > 0, "the burning lamp drops oil")

	game.toggle_lamp(&g)
	game.set_view(&g, 3)
	path: palace.Path
	testing.expect(t, palace.find_path(&g.palace, g.psyche.cell, ROOF_ENTRY, true, &path), "view 3: the roof is reachable in the dark")
}

@(test)
oil_runs_out :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !start(t, &g) {
		return
	}
	game.toggle_lamp(&g)
	run(&g, game.OIL_MAX + 1)
	testing.expect(t, !g.lamp_on && g.oil <= 0, "the lamp goes out when the oil is gone")
	game.toggle_lamp(&g)
	testing.expect(t, !g.lamp_on, "an empty lamp cannot be lit")
}

@(private)
ending :: proc(t: ^testing.T, bad: bool) {
	g: game.Game
	defer game.destroy(&g)
	if !start(t, &g) {
		return
	}
	g.trust_allowed = true // the secret ending, after the game has been finished
	g.palace.risen = true
	palace.rebuild_graph(&g.palace)
	game.set_view(&g, 3)
	g.activated = true
	g.psyche.cell = BRIDGE
	testing.expect(t, walk(t, &g, ROOF_ENTRY), "Psyche reaches the roof")
	if bad {
		game.toggle_lamp(&g)
	} else {
		game.walk_to(&g, BEDSIDE)
	}
	run(&g, 12)
	want := bad ? game.Ending.Oil : game.Ending.Trust
	testing.expectf(t, g.phase == .Finished && g.ending == want, "ending %v (got %v, phase %v)", want, g.ending, g.phase)
	if bad {
		testing.expect(t, g.collapse_t > 0, "the palace collapses")
	}
}

@(test)
ending_trust :: proc(t: ^testing.T) {
	ending(t, false)
}

@(test)
ending_drop_of_oil :: proc(t: ^testing.T) {
	ending(t, true)
}

@(test)
every_text_is_translated :: proc(t: ^testing.T) {
	for l in i18n.Language {
		for k in i18n.Key {
			testing.expectf(t, i18n.tr_in(l, k) != "", "%v: %v is empty", l, k)
		}
	}
	k, ok := i18n.key_from_name("v_doubt")
	testing.expect(t, ok && k == .V_Doubt, "text keys are found by name")
}

// Crossing an illusion, Psyche jumps between two surfaces far apart in the
// world: on screen the walk must stay continuous.
@(test)
illusion_steps_look_continuous :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !start(t, &g) {
		return
	}
	game.set_view(&g, 3)
	a, b := iso.Cell{7, 9, 1}, iso.Cell{5, 10, 2}
	testing.expect(t, palace.is_illusion(&g.palace, a, b), "view 3 joins the walkway to the west terrace")
	g.psyche.step_from, g.psyche.step_to, g.psyche.step_illusion = a, b, true
	screen :: proc(g: ^game.Game, u: f32) -> iso.Vec2 {
		p, _ := game.step_points(g, u)
		return iso.project(iso.view_point(p, g.angle, g.data.size))
	}
	prev := screen(&g, 0)
	for i in 1 ..= 100 {
		cur := screen(&g, f32(i) / 100)
		d := cur - prev
		testing.expectf(t, d.x * d.x + d.y * d.y < 4 * 4, "step %d: the walk jumps by %v px", i, d)
		prev = cur
	}
	end, _ := game.step_points(&g, 1)
	testing.expect(t, end == palace.node_world(&g.palace, b), "the step ends on the second surface")
}
