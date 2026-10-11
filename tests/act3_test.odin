// Act III: day and evening, turned by the spindle on a sundial; by day the
// sun shows the truth and the rams stand in the way, at evening the
// illusions are back and the rams lie down (steps). The sun shows, only the
// flame makes real: the lamp is lit only at evening. On small hand-made
// palaces, through the game and the solver.
package tests

import "core:mem/virtual"
import "core:testing"

import "../src/game"
import "../src/palace"

TIME_LEVEL :: 8 // III.1: the spindle is known (from II.3)

@(private)
load_time :: proc(t: ^testing.T, g: ^game.Game, text: string) -> bool {
	if err := game.load_text(g, TIME_LEVEL, text); err != nil {
		testing.expectf(t, false, "test palace does not load: %v", err)
		return false
	}
	game.begin(g, prologue = false)
	run(g, 0.1)
	return true
}

// A row at h1 with a sundial near the start; a ram stands in the way by day;
// lying at evening it is a step up to the ledge of the exit.
@(private)
TIME_PALACE :: `size 8
setting pasture_day
evening pasture_evening
column 0 2 0 0
column 1 2 0 0
column 2 2 0 0
column 3 2 0 0
column 4 2 0 1
column 5 2 0 1
sundial 1 2 1
ram 3 2 1 px
start 0 2 1
rest 0 2 1
exit 5 2 2
`

@(test)
sundial_turns_the_time :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !load_time(t, &g, TIME_PALACE) {
		return
	}
	testing.expect(t, g.palace.day && !game.dark(&g), "the level starts by day: the sun shows the truth")
	testing.expect(t, !game.walk_to(&g, {5, 2, 2}), "by day the ram stands in the way")
	testing.expect(t, !palace.is_node(&g.palace, {3, 2, 1}), "nobody stands where the ram is")
	game.use_spindle(&g)
	testing.expect(t, g.palace.day && g.phase == .Play, "off the sundial the spindle does nothing")

	// a walk passes over a sundial: only the spindle turns the time
	testing.expect(t, walk(t, &g, {2, 2, 1}), "over the sundial")
	testing.expect(t, g.palace.day, "walking over it does not turn the time")
	testing.expect(t, walk(t, &g, {1, 2, 1}), "back onto the sundial")
	testing.expect(t, game.on_spindle(&g) && game.at_sundial(&g), "on the sundial, the spindle ready")

	game.use_spindle(&g)
	testing.expect(t, g.phase == .Time && !g.palace.day, "the spindle turns the time: evening")
	run(&g, game.TIME_TURN + 0.2)
	testing.expect(t, g.phase == .Play && g.evening > 0.99, "the sun is down")
	testing.expect(t, palace.is_stair(&g.palace, {3, 2, 1}), "the ram lies down: a step")
	testing.expect(t, walk(t, &g, {2, 2, 1}), "off the sundial (the time stays)")
	testing.expect(t, !g.palace.day, "stepping off does not turn it back")

	// the brazier remembers the day
	testing.expect(t, game.return_to_rest(&g), "R: back to the brazier")
	testing.expect(t, g.palace.day && g.evening == 0, "back at the brazier it is day again")

	// the solver plays the same rules
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	sol := palace.solve(&g.palace, {5, 2, 2}, nil, virtual.arena_allocator(&arena))
	testing.expect(t, sol.solved && sol.times == 1, "the solver turns the time once")
	testing.expect(t, g.palace.day, "the solver leaves the palace as loaded (by day)")
	testing.expect(t, play_plan(t, &g, sol.plan[:]), "the game accepts every move")
	run(&g, game.EXIT_END + 0.5)
	testing.expect(t, game.is_over(&g), "the plan reaches the exit")
}

// The sun shows, only the flame makes real: a seal on the row raises the
// step to the exit, and the lamp is lit only at evening.
@(private)
FLAME_PALACE :: `size 8
setting pasture_day
evening pasture_evening
lamp
column 0 2 0 0
column 1 2 0 0
column 2 2 0 0
column 3 2 0 0
column 4 2 0 1
sundial 1 2 1
sigil 2 2 1
rise 3 2 1 px
start 0 2 1
exit 4 2 2
`

@(test)
the_flame_waits_for_evening :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !load_time(t, &g, FLAME_PALACE) {
		return
	}
	testing.expect(t, walk(t, &g, {2, 2, 1}), "onto the seal")
	game.toggle_lamp(&g)
	run(&g, 1)
	testing.expect(t, !g.lamp_on && g.activated == {}, "by day the lamp is not lit, the seal waits")

	testing.expect(t, walk(t, &g, {1, 2, 1}), "to the sundial")
	game.use_spindle(&g)
	run(&g, game.TIME_TURN + 0.2)
	testing.expect(t, !g.palace.day, "evening")
	game.toggle_lamp(&g)
	run(&g, 0.5)
	testing.expect(t, g.lamp_on, "at evening the lamp is lit")
	game.use_spindle(&g)
	testing.expect(t, g.palace.day && !g.lamp_on, "the sun coming up puts the lamp out")
	run(&g, game.TIME_TURN + 0.2)

	// the solver: evening, the lamp on the seal, up the risen step
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	h: game.Game
	defer game.destroy(&h)
	if !load_time(t, &h, FLAME_PALACE) {
		return
	}
	sol := palace.solve(&h.palace, h.data.exit, nil, virtual.arena_allocator(&arena))
	testing.expect(t, sol.solved && sol.times == 1 && sol.lightings == 1, "solved: the evening, then the flame")
	testing.expect(t, play_plan(t, &h, sol.plan[:]), "the game accepts every move")
	run(&h, game.EXIT_END + 0.5)
	testing.expect(t, game.is_over(&h), "the plan reaches the exit")
}
