// Playing a solver's plan (palace.solve) through the game, move by move, as
// a player would: the walkthrough tests and the screenshot tour use it, so
// they also prove that the game and the solver follow the same rules.
package game

import pl "../palace"

// Give the game one move of a plan. False if the game refuses it.
apply_move :: proc(g: ^Game, st: pl.Plan_Step) -> bool {
	switch st.move {
	case .Start:
	case .Step:
		if pl.is_passage(&g.palace, g.psyche.cell, st.cell) {
			return enter_cave(g)
		}
		return walk_to(g, st.cell)
	case .Turn_Left:
		request_turn(g, -1)
	case .Turn_Right:
		request_turn(g, 1)
	case .Light, .Douse:
		before := g.lamp_on
		toggle_lamp(g)
		return g.lamp_on != before
	case .Handle:
		use_handle(g)
		return g.phase == .Mechanism
	case .Ants:
		return call_ants(g)
	}
	return true
}

// Nothing is moving: the next move can be given.
idle :: proc(g: ^Game) -> bool {
	settled := g.light == (g.lamp_on ? 1 : 0)
	return !g.psyche.walking && !g.turning && settled && (g.phase == .Play || is_over(g))
}
