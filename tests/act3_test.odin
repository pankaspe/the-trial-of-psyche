// Act III: the ants carry a stone of seeds along the way the current view
// shows (illusions too) into the nearest free hollow, where it stays for good;
// on a small hand-made palace, through the game and the solver.
package tests

import "core:mem/virtual"
import "core:testing"

import "../src/game"
import "../src/iso"
import "../src/palace"

ANTS_LEVEL :: 8 // III.1: the ants are known from here on

// A row at h1 ends in the seed; from there only an illusion of view 0 leads
// on, up to a walk at h2 broken by a hollow before the exit.
@(private)
SEED_PALACE :: `size 8
block 0 2 0
block 1 2 0
block 2 2 0
column 4 3 0 1
column 5 3 0 1
hollow 6 3 1
column 7 3 0 1
seed 2 2 1
start 0 2 1
rest 0 2 1
exit 7 3 2
`

@(private)
load_ants :: proc(t: ^testing.T, g: ^game.Game, text: string) -> bool {
	if err := game.load_text(g, ANTS_LEVEL, text); err != nil {
		testing.expectf(t, false, "test palace does not load: %v", err)
		return false
	}
	game.begin(g, prologue = false)
	run(g, 0.1)
	return true
}

@(test)
ants_carry_along_the_view :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !load_ants(t, &g, SEED_PALACE) {
		return
	}
	testing.expect(t, game.has_skill(&g, .Ants), "the ants are known in Act III")
	testing.expect(t, !game.at_seed(&g), "at the start she is not beside the seed")
	testing.expect(t, !game.call_ants(&g), "no seed beside her: nothing happens")
	testing.expect(t, walk(t, &g, {1, 2, 1}), "to the seed")
	testing.expect(t, game.at_seed(&g), "beside the seed")

	// view 1: the illusion is not there, the ants find no way and go back
	game.set_view(&g, 1)
	testing.expect(t, !game.call_ants(&g), "view 1: no way to a hollow")
	run(&g, game.ANTS_FAIL + 0.5)
	testing.expect(t, g.palace.seed_at[0] < 0 && g.phase == .Play, "the seed stays where it lay")

	// view 0: across the illusion to the walk, and into the hollow
	game.set_view(&g, 0)
	testing.expect(t, game.call_ants(&g), "view 0: the ants carry it")
	testing.expect(t, g.phase == .Carry, "the game waits while they carry it")
	testing.expect(t, g.carry.illusion[0], "its way starts across the illusion")
	run(&g, game.carry_end(&g) + 0.2)
	testing.expect(t, g.phase == .Play && g.palace.seed_at[0] == 0, "it dropped into the hollow")
	testing.expect(t, palace.is_real_edge(&g.palace, {5, 3, 2}, {6, 3, 2}) && palace.is_real_edge(&g.palace, {6, 3, 2}, {7, 3, 2}), "the hollow filled, the walk is whole: real, in every view")
	game.set_view(&g, 2)
	testing.expect(t, !game.at_seed(&g), "nothing left to carry")
	game.set_view(&g, 0)
	testing.expect(t, walk(t, &g, {6, 3, 2}), "across the illusion onto the filled hollow")

	// the brazier brings back the palace as it was: the seed where it lay
	testing.expect(t, game.return_to_rest(&g), "R: back to the brazier")
	testing.expect(t, g.palace.seed_at[0] < 0 && palace.solid_at(&g.palace, {2, 2, 1}).kind == .Block, "the seed lies where it was")
	testing.expect(t, palace.solid_at(&g.palace, {6, 3, 1}).kind == .None, "and the hollow is empty again")
}

// The ants never carry a seed over the cell where Psyche stands, and with
// the lamp lit they believe only real ways.
@(test)
ants_see_what_she_sees :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	LEVEL :: `size 8
block 0 2 0
block 1 2 0
block 2 2 0
block 1 3 0
column 4 3 0 1
column 5 3 0 1
hollow 6 3 1
column 7 3 0 1
seed 2 2 1
start 0 2 1
exit 7 3 2
lamp
`
	if !load_ants(t, &g, LEVEL) {
		return
	}
	testing.expect(t, walk(t, &g, {1, 2, 1}), "beside the seed")
	game.toggle_lamp(&g)
	run(&g, 1)
	testing.expect(t, !game.call_ants(&g), "in the light the illusion is not a way")
	game.toggle_lamp(&g)
	run(&g, 1)
	testing.expect(t, game.call_ants(&g), "in the dark they take it")
}

// The solver finds the plan through the right view, and the game plays it.
@(test)
ants_solved_and_played :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !load_ants(t, &g, SEED_PALACE) {
		return
	}
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	sol := palace.solve(&g.palace, g.data.exit, nil, virtual.arena_allocator(&arena))
	testing.expect(t, sol.solved && sol.ants == 1, "solved with the ants once")
	testing.expect(t, play_plan(t, &g, sol.plan[:]), "the game accepts every move")
	run(&g, game.EXIT_END + 0.5)
	testing.expectf(t, g.phase == .Finished && g.ending == .Exit, "the plan reaches the exit (Psyche at %v)", g.psyche.cell)
	_ = iso.Cell{}
}
