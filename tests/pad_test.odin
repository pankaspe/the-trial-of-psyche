// Playing with a pad: Psyche steered by the stick, the pad's texts.
package tests

import "core:strings"
import "core:testing"

import "../src/content"
import "../src/game"
import "../src/i18n"
import "../src/iso"
import "../src/palace"
import "../src/ui"

import rl "vendor:raylib"

// Held toward a neighbour, the stick walks her there and on without a stop
// between cells; let go, she stops at the end of the step.
@(test)
stick_steers_psyche :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !start_level(t, &g, 0) {
		return
	}
	p := &g.palace
	// three cells in a row, on the same floor
	start, first, second: iso.Cell
	found := false
	search: for node, n in p.nodes {
		for nb in palace.neighbours(&p.real, i32(n)) {
			a := p.nodes[nb].cell
			dir := game.step_dir(&g, node.cell, a)
			for nb2 in palace.neighbours(&p.real, nb) {
				b := p.nodes[nb2].cell
				if b != node.cell && game.step_dir(&g, a, b) == dir && !node.stair && !p.nodes[nb].stair && !p.nodes[nb2].stair {
					start, first, second, found = node.cell, a, b, true
					break search
				}
			}
		}
	}
	if !testing.expect(t, found, "I.1 has three cells in a row") {
		return
	}
	g.psyche.cell = start
	g.psyche.pos = palace.stand_world(p, start)
	dir := game.step_dir(&g, start, first)
	game.steer(&g, dir, true)
	testing.expect(t, g.psyche.walking && g.psyche.step_to == first, "the stick starts a step toward the neighbour")
	testing.expect(t, g.learned[i18n.Key.Hint_Move], "steering teaches walking")
	stopped := false
	for i := 0; i < 600 && g.psyche.cell != second; i += 1 {
		game.steer(&g, dir, false)
		game.update(&g, DT)
		if !g.psyche.walking {
			stopped = true
		}
	}
	testing.expect(t, g.psyche.cell == second, "held, it walks on")
	testing.expect(t, !stopped, "no stop between the cells")
	game.steer(&g, {}, false)
	run(&g, 2)
	testing.expect(t, !g.psyche.walking, "let go, she stops")
}

// In every level and view, each way out of a cell lies in its own direction
// on screen: the stick pointed at a neighbour picks that neighbour (in the
// dark, illusions included; in the light, real edges), or one that looks the
// same way (an illusion over a real step: the nearer, as a click picks).
@(test)
every_step_has_its_direction :: proc(t: ^testing.T) {
	for i in 0 ..< content.LEVEL_COUNT {
		if !content.is_built(i) {
			continue
		}
		g: game.Game
		defer game.destroy(&g)
		if err := game.load(&g, i); err != nil {
			continue
		}
		p := &g.palace
		ambiguous := 0
		for r in 0 ..< 4 {
			game.set_view(&g, r)
			for dark in ([2]bool{true, false}) {
				for node, a in p.nodes {
					for graph in ([]^palace.Graph{&p.real, &p.illusion}) {
						if graph == &p.illusion && !dark {
							break
						}
						for b in palace.neighbours(graph, i32(a)) {
							to := p.nodes[b].cell
							if !palace.step_allowed(p, i32(a), b, dark) || palace.is_passage(p, node.cell, to) {
								continue
							}
							dir := game.step_dir(&g, node.cell, to)
							next, ok := game.step_toward(&g, node.cell, dir, dark)
							// two ways the same on screen: the nearer to the camera, as a click
							if !ok || (next != to && game.step_dir(&g, node.cell, next) != dir) {
								ambiguous += 1
							}
						}
					}
				}
			}
		}
		testing.expectf(t, ambiguous == 0, "%s: %d steps the stick cannot point at", content.LEVELS[i].id, ambiguous)
	}
}

// With a pad in hand the texts that name keys name its buttons.
@(test)
pad_texts_name_its_buttons :: proc(t: ^testing.T) {
	defer i18n.set_pad(nil)
	for l in i18n.Language {
		i18n.set_language(l)
		i18n.set_pad(i18n.PAD_XBOX)
		s := i18n.tr(.Controls)
		testing.expectf(t, strings.contains(s, "LB") && !strings.contains(s, "{"), "%v: the pad's controls name LB: %s", l, s)
		for k in ([]i18n.Key{.Hint_Lamp, .Hint_Oil}) {
			// the lamp is LT, the button its slot shows
			testing.expectf(t, strings.contains(i18n.tr(k), "LT"), "%v: the lamp is LT: %s", l, i18n.tr(k))
		}
		for k in ([]i18n.Key{.Hint_Handle, .Hint_Sundial, .Mech_Handle, .Mech_Time}) {
			// the spindle is RT, the button its slot shows, not A
			testing.expectf(t, strings.contains(i18n.tr(k), "RT") && !strings.contains(i18n.tr(k), " A:"), "%v: the spindle is RT: %s", l, i18n.tr(k))
		}
		i18n.set_pad(i18n.pad_playstation())
		testing.expectf(t, strings.contains(i18n.tr(.Hint_Turn), "L1"), "%v: PlayStation shoulders", l)
		testing.expectf(t, strings.contains(i18n.tr(.Hint_Lamp), "L2"), "%v: PlayStation triggers", l)
		i18n.set_pad(nil)
		testing.expectf(t, strings.contains(i18n.tr(.Controls), "Q / E"), "%v: the keyboard's controls again", l)
	}
	i18n.set_language(.Italian)
}

// A stick held through a turn of the view (or of the world) does not carry
// her on: on screen it points where it did, through the palace another way
// (often back). Pushed again, it steers.
@(test)
stick_waits_after_a_turn :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !load_text(t, &g, BOAT_PALACE, slot = 13) {
		return
	}
	game.begin(&g, prologue = false)
	run(&g, 0.1)
	game.request_turn(&g, 1)
	run(&g, game.ROTATE_TIME + 0.1)
	dir := game.step_dir(&g, g.psyche.cell, {1, 2, 1})
	for _ in 0 ..< 3 {
		game.steer(&g, dir, false)
		run(&g, 0.05)
		testing.expect(t, !g.psyche.walking, "a stick held through the turn waits")
	}
	game.steer(&g, dir, true)
	testing.expect(t, g.psyche.walking, "pushed again, it steers")
}

// Down a lamplit menu the focus goes to the next entry, however wide each is:
// the pause's lit "Restart the diorama" over a short "Profile" over a longer
// "Settings" (the pad once skipped Profile).
@(test)
pad_walks_a_list_in_order :: proc(t: ^testing.T) {
	rects := []rl.Rectangle{{128, 400, 520, 56}, {128, 458, 160, 42}, {128, 516, 280, 42}, {128, 574, 120, 42}}
	for i in 0 ..< len(rects) - 1 {
		testing.expectf(t, ui.nearest(rects, i, {0, 1}) == i + 1, "down from %d goes to %d", i, ui.nearest(rects, i, {0, 1}))
		testing.expectf(t, ui.nearest(rects, i + 1, {0, -1}) == i, "up from %d goes to %d", i + 1, ui.nearest(rects, i + 1, {0, -1}))
	}
}
