// Act IV: Charon's boat at the exit (reaching the landing does not end the
// level: Space boards it), a level that goes down (the look at its foot
// follows her down), Proserpina's flip (the world turned over). On small hand-made palaces, through the game.
package tests

import "core:testing"

import "../src/game"
import "../src/level"
import "../src/palace"

// A row going down a step to the landing, the boat moored beyond it.
@(private)
BOAT_PALACE :: `size 8
setting tower_dusk
below taenarus
water 0 0 7 7
column 0 2 0 1
column 1 2 0 0
stairs 1 2 1 mx
column 2 2 0 0
column 3 2 0 0
start 0 2 2
exit 3 2 1
charon 3 2 1 px
`

@(test)
boat_ferries_her_away :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !load_text(t, &g, BOAT_PALACE, slot = 13) { // IV.1
		return
	}
	testing.expect(t, g.descent == 0 && game.setting_now(&g) == .Tower_Dusk, "at the top: the look of the top")
	testing.expect(t, !game.board_boat(&g), "no boat where she stands")
	testing.expect(t, walk(t, &g, {3, 2, 1}), "down to the landing")
	run(&g, game.DESCENT_TIME + 0.2)
	testing.expect(t, g.descent > 0.99 && game.setting_now(&g) == level.Setting.Taenarus, "at the foot: the look of the foot")
	testing.expect(t, !game.is_over(&g), "the landing does not end the level by itself")
	testing.expect(t, game.at_boat(&g) && g.hud.hint.key == .Hint_Boat, "Charon waits, and she is told how to board")
	testing.expect(t, game.board_boat(&g) && g.ferried, "Space: into the boat")
	testing.expect(t, game.exit_lift(&g) == 0, "no wind lifts her: the boat takes her")
	run(&g, game.BOAT_PUSH + 1)
	testing.expect(t, g.psyche.pos.x > 3.5 + game.BOAT_SEAT, "she goes with the boat, out over the water")
	testing.expect(t, g.lightning_t >= 0, "the sky cracks as he takes the coin")
	run(&g, game.BOAT_END)
	testing.expect(t, g.phase == .Finished && g.ending == .Exit, "the crossing ends the level")
	testing.expect(t, game.veil(&g) == 1, "behind the veil")
}

// A dark stretch: the stones to the exit appear only in the light of the
// guard candelabrum, which the lamp lights standing beside it.
@(private)
GUARD_PALACE :: `size 8
setting taenarus
column 0 2 0 0
column 1 2 0 0
rise 2 2 0 1
rise 3 2 0 1
column 4 2 0 0
candelabrum 1 2 1 px guard
start 0 2 1
exit 4 2 1
lamp
`

@(test)
guard_shows_the_way :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !load_text(t, &g, GUARD_PALACE, slot = 13) {
		return
	}
	testing.expect(t, 0 in g.data.guard_seals && len(g.data.sigils) == 1, "the guard is a seal of its own")
	testing.expect(t, walk(t, &g, {1, 2, 1}), "beside the candelabrum")
	path: palace.Path
	testing.expect(t, !palace.find_path(&g.palace, g.psyche.cell, g.data.exit, false, &path), "in the dark there is no way on")
	game.toggle_lamp(&g)
	run(&g, 3)
	testing.expect(t, 0 in g.activated && 0 in g.candelabra_lit, "the lamp lights the guard")
	game.toggle_lamp(&g)
	testing.expect(t, walk(t, &g, g.data.exit), "its light shows the stones to the exit, the lamp out")
}

@(test)
lightning_flashes_then_thunders :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !load_text(t, &g, BOAT_PALACE, slot = 13) {
		return
	}
	testing.expect(t, game.lightning_flash(&g) == 0, "no lightning before")
	game.lightning(&g)
	testing.expect(t, game.lightning_flash(&g) > 0.99, "a flash at once")
	run(&g, 0.25)
	testing.expect(t, game.lightning_flash(&g) > 0.4, "and a second flicker")
	run(&g, 2)
	testing.expect(t, game.lightning_flash(&g) < 0.01, "then the dark again")
}

// Three stones on the axle, a rock on the middle one above: the way across
// is under them, once the world is turned over; the exit is of that world.
@(private)
FLIP_PALACE :: `size 5
setting taenarus
upside dis
block 0 2 1
block 1 2 1
block 2 2 1
block 1 2 2
pomegranate 0 2 2
start 0 2 2
under
stairs 3 2 2 mx
block 3 2 1
exit 2 2 2
end
`

@(test)
pomegranate_turns_the_world_over :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !load_text(t, &g, FLIP_PALACE, slot = 14) { // IV.2
		return
	}
	path: palace.Path
	testing.expect(t, !palace.find_path(&g.palace, g.psyche.cell, g.data.exit, false, &path), "above, the rock bars the way")
	testing.expect(t, palace.solid_at(&g.palace, {3, 2, 0}).kind == .Block, "the stairs of the world below hang: flat stone")
	testing.expect(t, game.at_pomegranate(&g) && game.on_spindle(&g), "on the pomegranate the spindle is ready")
	game.use_spindle(&g)
	testing.expect(t, g.phase == .Overturn && g.palace.upside, "the world turns over")
	testing.expect(t, g.psyche.cell == (palace.Cell{0, 2, 2}), "she stays on her stone")
	run(&g, game.OVERTURN_TIME + 0.2)
	testing.expect(t, g.phase == .Play && g.overturn > 0.99 && game.setting_now(&g) == level.Setting.Dis, "turned over: the look of the world below")
	testing.expect(t, palace.solid_at(&g.palace, {3, 2, 2}).kind == .Stairs, "its stairs stand up")
	testing.expect(t, palace.solid_at(&g.palace, {1, 2, 0}).kind == .Block, "the rock hangs under the stones now")
	testing.expect(t, walk(t, &g, g.data.exit), "under the stones she walks to the exit")
	run(&g, game.EXIT_END + 0.5)
	testing.expect(t, g.phase == .Finished && g.ending == .Exit, "the exit of the world below ends the level")
}

@(test)
solver_turns_the_world_over :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !load_text(t, &g, FLIP_PALACE, slot = 14) {
		return
	}
	sol := palace.solve(&g.palace, palace.exit_spot(&g.data), nil, context.temp_allocator)
	testing.expect(t, sol.solved && sol.overturns == 1 && sol.steps == 2, "one turn of the world, two steps")
	testing.expect(t, !g.palace.upside, "the solver leaves the world as described")
	no := palace.solve(&g.palace, {g.data.exit, false}, nil, context.temp_allocator)
	testing.expect(t, !no.solved, "the same cell in the world above is out of reach")
}

// Two banks with the water between them; Charon's ferry waits at the west landing.
@(private)
FERRY_PALACE :: `size 8
setting taenarus
water 3 0 4 7
column 1 2 0 0
column 2 2 0 0
column 5 2 0 0
column 6 2 0 0
start 1 2 1
exit 6 2 1
ferry 2 2 1 px  5 2 1 mx
`

@(test)
ferry_takes_her_across :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !load_text(t, &g, FERRY_PALACE, slot = 16) { // IV.4
		return
	}
	sol := palace.solve(&g.palace, palace.exit_spot(&g.data), nil, context.temp_allocator)
	testing.expect(t, sol.solved && sol.crossings == 1, "the solver crosses once")
	path: palace.Path
	testing.expect(t, !palace.find_path(&g.palace, g.data.start, g.data.exit, false, &path), "walks never take the ferry")
	testing.expect(t, !game.board_ferry(&g), "no landing where she stands")
	testing.expect(t, walk(t, &g, {2, 2, 1}), "to the landing")
	testing.expect(t, game.at_ferry(&g) && g.hud.hint.key == .Hint_Boat, "Charon waits, and she is told how to board")
	testing.expect(t, game.board_ferry(&g) && g.psyche.step_ferry, "Space: into the boat")
	run(&g, game.FERRY_TIME * 0.5)
	testing.expect(t, g.psyche.pos.x > 3 && g.psyche.pos.x < 5, "out on the water, in the boat")
	run(&g, game.FERRY_TIME * 0.5 + 0.3)
	testing.expect(t, g.psyche.cell == {5, 2, 1} && !g.psyche.walking, "on the other landing")
	testing.expect(t, 0 in g.palace.boats && game.at_ferry(&g), "the boat stays where it left her")
	// as if she had come back to this bank another way, the boat left on the far one
	g.palace.boats -= {0}
	testing.expect(t, !game.at_ferry(&g), "no boat here")
	testing.expect(t, game.board_ferry(&g) && !g.psyche.walking && g.hud.hint.key == .Hint_Ferry_Away, "Space: nothing, she is told the boat is away")
	g.palace.boats += {0}
	testing.expect(t, walk(t, &g, {6, 2, 1}), "on to the exit")
	run(&g, 1)
	testing.expect(t, game.is_over(&g), "the exit ends the level")
}
