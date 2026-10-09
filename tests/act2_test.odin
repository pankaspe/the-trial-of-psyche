// Act II: the rules of the palace that changes (veiled blocks, parts turned
// by handles, braziers) on small hand-made palaces, and
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
lamp_reveals_veiled :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	LEVEL :: `size 9
block 0 0 0
block 1 0 0
block 2 0 0
veiled 3 0 0
block 4 0 0
veiled 7 0 0
start 0 0 1
exit 4 0 1
lamp
`
	if !load_text(t, &g, LEVEL) {
		return
	}
	testing.expect(t, walk(t, &g, {2, 0, 1}), "Psyche walks to the gap")
	testing.expect(t, !palace.is_node(&g.palace, {3, 0, 1}), "the veiled stone is not there in the dark")
	game.toggle_lamp(&g)
	run(&g, 1)
	testing.expect(t, palace.is_node(&g.palace, {3, 0, 1}), "the light makes the veiled stone real")
	testing.expect(t, !palace.is_node(&g.palace, {7, 0, 1}), "a veiled stone out of reach stays hidden")
	game.toggle_lamp(&g)
	run(&g, 1)
	testing.expect(t, palace.is_node(&g.palace, {3, 0, 1}), "for good: the veiled stone stays in the dark")
	testing.expect(t, g.flip_t[3] > game.DISSOLVE_TIME, "its appearing has played out")
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

// Two caves: walking into one, Psyche comes out of the other, far above, on
// a platform no path reaches; the dark of the rock hides her on the way.
@(test)
cave_leads_to_its_pair :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	LEVEL :: `size 8
block 0 0 0
block 1 0 0
block 2 0 0
column 3 0 0 2
cave 2 0 1 px
column 0 5 0 4
column 1 5 0 4
column 0 4 0 5
cave 1 5 5 mx
column 2 5 0 4
start 0 0 1
exit 2 5 5
`
	if !load_text(t, &g, LEVEL) {
		return
	}
	testing.expect(t, palace.is_passage(&g.palace, {2, 0, 1}, {1, 5, 5}), "the two mouths are joined")
	testing.expect(t, game.walk_to(&g, {1, 0, 1}), "a walk that does not use the cave")
	run(&g, 1)
	testing.expect(t, g.psyche.cell == iso.Cell{1, 0, 1} && game.psyche_alpha(&g) == 1, "goes by it")
	path: palace.Path
	testing.expect(t, !palace.find_path(&g.palace, g.psyche.cell, g.data.exit, true, &path), "a walk never goes into the rock by itself")
	testing.expect(t, walk(t, &g, {2, 0, 1}), "to the mouth")
	testing.expect(t, game.at_cave(&g), "she stands at the mouth")
	testing.expect(t, game.enter_cave(&g), "into the cave")
	// she walks into one mouth and out of the other at their own level: never through the air
	on_ground := true
	hidden := false
	for _ in 0 ..< int((game.PASSAGE_TIME + 0.2) / DT) {
		game.update(&g, DT)
		z := g.psyche.pos.z
		on_ground &&= abs(z - 1) < 0.01 || abs(z - 5) < 0.01
		hidden ||= game.psyche_alpha(&g) < 0.05
		free_all(context.temp_allocator)
	}
	testing.expect(t, on_ground, "the passage keeps her feet on the mouths' floors")
	testing.expect(t, hidden, "in the dark of the rock she is not seen")
	testing.expect(t, g.psyche.cell == iso.Cell{1, 5, 5} && game.psyche_alpha(&g) == 1, "out of the other mouth")
	testing.expect(t, walk(t, &g, g.data.exit), "on to the exit")
}

// The level that introduces a mechanic presents it once, before the intro;
// a restart does not.
@(test)
new_mechanic_is_presented :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if err := game.load(&g, 4); err != nil {
		testing.expect(t, false, "II.1 does not load")
		return
	}
	testing.expect(t, g.data.mechanic == .Veiled, "II.1 introduces the veiled stones")
	game.begin(&g)
	testing.expect(t, g.phase == .Prologue, "the act opens with its cutscene")
	game.prologue_advance(&g) // skip to its end...
	run(&g, game.PRO_PROMPT + 0.1)
	game.prologue_advance(&g) // ...and begin
	testing.expect(t, g.phase == .Play, "then the level begins")
	run(&g, game.TEACH_AT + 0.1)
	testing.expect(t, g.mechanic_new, "its card comes at the start")
	testing.expect(t, game.fade_alpha(g.hud.voice) == 0, "before the intro line")
	g.mechanic_new = false
	g.teach_card = true
	testing.expect(t, game.teach_glow(&g) == 1, "the veiled stones glow while the card is read")
	g.teach_card = false
	g.teach_after = 0
	run(&g, 6)
	testing.expect(t, game.teach_glow(&g) == 0, "and a few seconds after")
	if err := game.load(&g, 4); err != nil {
		return
	}
	game.begin(&g, prologue = false)
	run(&g, 2)
	testing.expect(t, !g.mechanic_new, "a restart does not present it again")
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

		testing.expectf(t, palace.check_dynamic(&g.palace, alloc), "%s can be solved", info.id)
		for _, f in g.data.fragments {
			reachable, optional := palace.check_dynamic_fragment(&g.palace, f, alloc)
			testing.expectf(t, reachable && optional, "%s: fragment %d is reachable (%v) and optional (%v)", info.id, f, reachable, optional)
		}
		sol := palace.solve(&g.palace, g.data.exit, nil, alloc)
		if g.data.has_lamp {
			left := palace.oil_left(&g.palace, sol.plan[:], game.oil_rules(&g.data))
			testing.expectf(t, left >= 0, "%s: the lamp's oil lasts the plan (%.1f s left)", info.id, left)
		}

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
