// Act IV: Charon's boat at the exit (reaching the landing does not end the
// level: Space boards it), and a level that goes down (the look at its foot
// follows her down). On small hand-made palaces, through the game.
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
