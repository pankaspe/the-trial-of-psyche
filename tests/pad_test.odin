// Playing with a pad: Psyche steered by the stick, the pad's texts.
package tests

import "core:strings"
import "core:testing"

import "../src/content"
import "../src/game"
import "../src/i18n"
import "../src/iso"
import "../src/palace"

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
		testing.expectf(t, strings.contains(i18n.tr(.Hint_Lamp), "X"), "%v: the lamp is X", l)
		i18n.set_pad(i18n.pad_playstation())
		testing.expectf(t, strings.contains(i18n.tr(.Hint_Turn), "L1"), "%v: PlayStation shoulders", l)
		i18n.set_pad(nil)
		testing.expectf(t, strings.contains(i18n.tr(.Controls), "Q / E"), "%v: the keyboard's controls again", l)
	}
	i18n.set_language(.Italian)
}
