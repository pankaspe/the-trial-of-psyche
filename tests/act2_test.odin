// Act II: the rules of the palace that changes (crumbling, phantom and veiled
// blocks, parts turned by handles, braziers) on small hand-made palaces, and
// every built level of the act solved by palace.solve and played through
// the game move by move (so the game and the solver agree).
package tests

import "core:mem/virtual"
import "core:testing"

import "../src/content"
import "../src/game"
import "../src/iso"
import "../src/palace"

@(private)
load_text :: proc(t: ^testing.T, g: ^game.Game, text: string) -> bool {
	if err := game.load_text(g, 4, text); err != nil {
		testing.expectf(t, false, "test palace does not load: %v", err)
		return false
	}
	game.begin(g, prologue = false)
	run(g, 0.1)
	return true
}

// Play a solver plan through the game; true if every move was accepted.
@(private)
play_plan :: proc(t: ^testing.T, g: ^game.Game, plan: []palace.Plan_Step) -> bool {
	for st, i in plan {
		for n := 0; !game.idle(g) && n < 2000; n += 1 {
			game.update(g, DT)
			free_all(context.temp_allocator)
		}
		if game.is_over(g) {
			return true
		}
		if !game.apply_move(g, st) {
			testing.expectf(t, false, "move %d (%v to %v) refused", i, st.move, st.cell)
			return false
		}
	}
	for n := 0; !game.idle(g) && n < 2000; n += 1 {
		game.update(g, DT)
		free_all(context.temp_allocator)
	}
	return true
}

@(test)
crumbling_stone_falls_behind :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	LEVEL :: `size 6
block 0 0 0
crumble 1 0 0
block 2 0 0
start 0 0 1
exit 2 0 1
`
	if !load_text(t, &g, LEVEL) {
		return
	}
	testing.expect(t, walk(t, &g, {1, 0, 1}), "Psyche stands on the cracked stone")
	testing.expect(t, walk(t, &g, {0, 0, 1}), "and steps back")
	run(&g, 2)
	testing.expect(t, !palace.is_node(&g.palace, {1, 0, 1}), "the cracked stone has fallen")
	path: palace.Path
	testing.expect(t, !palace.find_path(&g.palace, g.psyche.cell, {2, 0, 1}, true, &path), "no way across any more")
	testing.expect(t, game.has_rest(&g) == false, "no brazier in this palace")
}

@(test)
lamp_dissolves_phantoms_and_reveals_veiled :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	LEVEL :: `size 8
block 0 0 0
phantom 1 0 0
block 2 0 0
veiled 3 0 0
block 4 0 0
phantom 6 0 0
start 0 0 1
exit 4 0 1
lamp
`
	if !load_text(t, &g, LEVEL) {
		return
	}
	testing.expect(t, walk(t, &g, {1, 0, 1}), "in the dark the phantom holds")
	game.toggle_lamp(&g)
	testing.expect(t, !g.lamp_on, "the lamp is not lit over a phantom")
	testing.expect(t, walk(t, &g, {2, 0, 1}), "on to real stone")
	testing.expect(t, !palace.is_node(&g.palace, {3, 0, 1}), "the veiled stone is not there in the dark")
	game.toggle_lamp(&g)
	run(&g, 1)
	testing.expect(t, !palace.is_node(&g.palace, {1, 0, 1}), "the light dissolves the phantom nearby")
	testing.expect(t, palace.is_node(&g.palace, {3, 0, 1}), "and makes the veiled stone real")
	testing.expect(t, palace.is_node(&g.palace, {6, 0, 1}), "a phantom out of reach stays")
	game.toggle_lamp(&g)
	run(&g, 1)
	testing.expect(t, palace.is_node(&g.palace, {3, 0, 1}), "for good: the veiled stone stays in the dark")
	testing.expect(t, walk(t, &g, g.data.exit), "the revealed stone leads to the exit")
}

@(test)
handle_turns_a_part :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	// an L-shaped bridge about (3, 3): it joins the handle's side to the exit's after a quarter turn
	LEVEL :: `size 8
block 0 3 0
block 1 3 0
part 3 3
block 2 3 0
block 3 3 0
block 3 4 0
end
block 3 1 0
block 3 0 0
handle 1 3 1
start 0 3 1
exit 3 0 1
rest 0 3 1
`
	if !load_text(t, &g, LEVEL) {
		return
	}
	testing.expect(t, walk(t, &g, {1, 3, 1}), "to the handle")
	path: palace.Path
	testing.expect(t, !palace.find_path(&g.palace, g.psyche.cell, g.data.exit, true, &path), "the bridge points the wrong way")
	game.use_handle(&g)
	testing.expect(t, g.phase == .Mechanism, "the handle turns the part")
	run(&g, game.PART_TIME + 0.2)
	testing.expect(t, g.phase == .Play && g.palace.part_rot[0] == 1, "a quarter turn")
	testing.expect(t, palace.find_path(&g.palace, g.psyche.cell, g.data.exit, true, &path), "the bridge now joins the handle to the exit")
	testing.expect(t, walk(t, &g, {3, 2, 1}), "onto the part")
	// the brazier brings back the palace as it was when she lit it
	testing.expect(t, game.return_to_rest(&g), "R: back to the brazier")
	testing.expect(t, !game.return_to_rest(&g), "R again, nothing changed: the whole level restarts")
	testing.expect(t, g.psyche.cell == iso.Cell{0, 3, 1} && g.palace.part_rot[0] == 0, "R: back to the brazier, the part as it was")
	testing.expect(t, !palace.find_path(&g.palace, g.psyche.cell, g.data.exit, true, &path), "and the bridge points the wrong way again")
}

// Every built level of Act II can be solved, and the solver's plan, played
// through the game, reaches the exit; the fragment is reachable and optional.
@(test)
act2_levels_solve_and_play :: proc(t: ^testing.T) {
	for info, index in content.LEVELS {
		if info.act != .II || !content.is_built(index) {
			continue
		}
		g: game.Game
		defer game.destroy(&g)
		if err := game.load(&g, index); err != nil {
			testing.expectf(t, false, "%s does not load: %v", info.id, err)
			continue
		}
		testing.expectf(t, palace.is_dynamic(&g.data), "%s uses the act's mechanics", info.id)
		arena: virtual.Arena
		testing.expect(t, virtual.arena_init_growing(&arena) == nil)
		defer virtual.arena_destroy(&arena)
		alloc := virtual.arena_allocator(&arena)

		solvable, reachable, optional := palace.check_dynamic(&g.palace, alloc)
		testing.expectf(t, solvable, "%s can be solved", info.id)
		testing.expectf(t, reachable && optional, "%s: the fragment is reachable (%v) and optional (%v)", info.id, reachable, optional)
		sol := palace.solve(&g.palace, g.data.exit, nil, alloc)

		game.begin(&g, prologue = false)
		run(&g, game.start_cues_time(&g) + 0.5)
		if !play_plan(t, &g, sol.plan[:]) {
			continue
		}
		run(&g, game.EXIT_END + 0.5)
		testing.expectf(t, g.phase == .Finished && g.ending == .Exit, "%s: the plan played through the game reaches the exit (Psyche at %v)", info.id, g.psyche.cell)
		testing.expectf(t, g.data.has_intro && g.data.has_outro, "%s has its intro and outro", info.id)
	}
}
