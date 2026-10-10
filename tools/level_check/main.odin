// Level analysis for designers: `./build.sh check assets/levels/level_04.txt`.
//
// For the base palace and after the seal has raised its blocks, it reports
// how much of the palace Psyche can reach from the start: in the light, in
// the dark for each view, and in the dark turning freely (turning is free
// while standing still, so the illusions of all four views add up). Then it
// lists the illusions of every view: watch out for unintended shortcuts.
// The fragment of the tale must be reachable and optional (the exit status
// is 1 otherwise).
// Levels whose palace changes (veiled blocks, seals, parts that
// turn) are also solved move by move: the tool prints the plan with the
// fewest decisions, how many states can be reached and how many of them are
// dead ends (the level must be restarted), and checks that no part turns
// into the palace.
package level_check

import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:strings"
import "base:runtime"

import "../../src/game"
import "../../src/iso"
import "../../src/level"
import pl "../../src/palace"
import "../../src/render"

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprintln("usage: level_check <level file>")
		os.exit(2)
	}
	path := os.args[1]
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	alloc := virtual.arena_allocator(&arena)

	text, read_err := os.read_entire_file_from_path(path, alloc)
	if read_err != nil {
		fmt.eprintfln("cannot read %s: %v", path, read_err)
		os.exit(1)
	}
	data, err := level.parse(string(text), alloc)
	if e, failed := err.?; failed {
		fmt.eprintfln("%s:%d: %s", path, e.line, e.message)
		os.exit(1)
	}
	p: pl.Palace
	pl.init(&p, &data, alloc)

	fmt.printfln("%s: %d x %d grid, %d blocks, %d props, %d rising", path, data.size, data.size, len(data.blocks), len(data.props), len(data.rise))
	for k in 0 ..< 4 {
		risen, evening := k % 2 == 1, k >= 2
		if risen && len(data.rise) == 0 || evening && len(data.reeds) == 0 {
			continue
		}
		p.risen = risen ? pl.all_seals(&data) : {}
		p.day = len(data.reeds) > 0 && !evening
		pl.rebuild_graph(&p)
		tag := risen ? "risen" : "base "
		if len(data.reeds) > 0 {
			tag = fmt.tprintf("%s %s", tag, evening ? "evening" : "day    ")
		}
		if p.day {
			// by day the sun shows the truth: no illusions
			fmt.printfln("\n%s: %d surfaces and stairs", tag, len(p.nodes))
			reached := make([]bool, len(p.nodes), alloc)
			pl.reachable(&p, data.start, false, reached)
			report(&p, &data, fmt.tprintf("%s sun  ", tag), reached)
			continue
		}
		fmt.printfln("\n%s: %d surfaces and stairs", tag, len(p.nodes))
		reached := make([]bool, len(p.nodes), alloc)

		pl.reachable(&p, data.start, false, reached)
		report(&p, &data, fmt.tprintf("%s light       ", tag), reached)
		for r in 0 ..< 4 {
			pl.set_view(&p, r)
			pl.reachable(&p, data.start, true, reached)
			report(&p, &data, fmt.tprintf("%s dark  view %d", tag, r), reached)
		}
		pl.reachable_turning(&p, data.start, reached)
		report(&p, &data, fmt.tprintf("%s dark  turning", tag), reached)
	}
	p.risen = {}
	p.day = false // the illusions below are those of the dark (at evening)
	pl.rebuild_graph(&p)

	for r in 0 ..< 4 {
		pl.set_view(&p, r)
		fmt.printf("\nview %d stairs usable in the dark:", r)
		for node, i in p.nodes {
			if node.stair {
				fmt.printf(" %v:%v", node.cell, p.stair_seen[i])
			}
		}
		fmt.printf("\nview %d illusions (%d):", r, len(p.illusion.pairs))
		for e in p.illusion.pairs {
			fmt.printf(" %v-%v", p.nodes[e[0]].cell, p.nodes[e[1]].cell)
		}
		fmt.println()
	}
	if pl.is_dynamic(&data) {
		whole_illusions(&p, &data, alloc)
	}
	p.day = len(data.reeds) > 0
	pl.rebuild_graph(&p)

	if !check_screen(&p, &data) || !check_props(&p, &data) {
		os.exit(1)
	}

	if pl.is_dynamic(&data) {
		solve_report(&p, &data, alloc)
		return
	}
	for c, i in data.fragments {
		reachable, optional := pl.check_fragment(&p, i)
		fmt.printfln("\nfragment %v: reachable %v, optional %v", c, reachable, optional)
		if !reachable || !optional {
			fmt.eprintln("error: the fragment must be reachable and never required")
			os.exit(1)
		}
	}
	if len(data.fragments) == 0 {
		fmt.println("\nwarning: no fragment of the tale in this level")
	}
	if (data.has_exit || data.has_amore) && !print_plan(&p, &data, alloc) {
		os.exit(1)
	}
}

// What the player sees and clicks: every cave has rock turned its opening is
// (an error otherwise), and a click on a fragment's scroll picks the
// fragment's own cell in every view (a warning otherwise: the click would
// send Psyche somewhere else, in the worst case to a cave's mouth). The
// palace is checked as loaded and whole (veiled blocks shown, the seal's
// blocks raised).
check_screen :: proc(p: ^pl.Palace, data: ^level.Level_Data) -> (ok: bool) {
	ok = true
	for cave in data.caves {
		d := iso.DIR_VEC[cave.dir]
		if pl.solid_at(p, cave.cell + {d.x, d.y, 0}).kind != .Block {
			fmt.eprintfln("error: the cave at %v has no rock on its side %v", cave.cell, cave.dir)
			ok = false
		}
	}
	for whole in ([2]bool{false, true}) {
		// as loaded (veiled stones hidden), then whole
		for &f, i in p.flipped {
			f = whole && data.blocks[i].trait == .Veiled
		}
		p.risen = whole ? pl.all_seals(data) : {}
		pl.rebuild_graph(p)
		for c in data.fragments {
			for r in 0 ..< 4 {
				pl.set_view(p, r)
				w := pl.node_world(p, c) + {0, 0, 0.22}
				got, found := pl.pick(p, iso.project(iso.view_point(w, f32(r), p.size)), f32(r))
				if found && got != c {
					note := pl.cave_at(p, got) >= 0 ? " (a cave's mouth!)" : ""
					fmt.printfln("warning: view %d%s: a click on the scroll at %v picks %v%s", r, whole ? "" : " (veiled hidden)", c, got, note)
				}
			}
		}
	}
	for &f in p.flipped {
		f = false
	}
	p.risen = {}
	pl.set_view(p, 0)
	pl.rebuild_graph(p)
	return
}

// The illusions of the palace changed for good (veiled stones shown, every
// seal's blocks raised), parts as loaded: those not in the base listing.
whole_illusions :: proc(p: ^pl.Palace, data: ^level.Level_Data, alloc: runtime.Allocator) {
	Pair :: [2]iso.Cell
	base := make(map[Pair]bool, 64, alloc)
	for r in 0 ..< 4 {
		pl.set_view(p, r)
		for e in p.illusion.pairs {
			base[{p.nodes[e[0]].cell, p.nodes[e[1]].cell}] = true
		}
	}
	for &f, i in p.flipped {
		f = data.blocks[i].trait == .Veiled
	}
	p.risen = pl.all_seals(data)
	pl.rebuild_graph(p)
	for r in 0 ..< 4 {
		pl.set_view(p, r)
		fmt.printf("whole view %d, new illusions:", r)
		for e in p.illusion.pairs {
			pair := Pair{p.nodes[e[0]].cell, p.nodes[e[1]].cell}
			if !base[pair] {
				fmt.printf(" %v-%v", pair[0], pair[1])
			}
		}
		fmt.println()
	}
	for &f in p.flipped {
		f = false
	}
	p.risen = {}
	pl.set_view(p, 0)
	pl.rebuild_graph(p)
}

// What would look wrong (an error) or odd (a warning), with the palace whole
// (veiled stones shown, the seals' blocks raised) and every part in each of
// its positions: a prop inside a block or hanging in the air, a candle with no
// wall, a candelabrum off a floor, a blocking prop on a cell the level needs,
// a handle on a part, a block given twice, more flames than the stones show.
check_props :: proc(p: ^pl.Palace, data: ^level.Level_Data) -> (ok: bool) {
	ok = true
	said := make(map[string]bool, 16, context.temp_allocator)
	say :: proc(said: ^map[string]bool, ok: ^bool, fatal: bool, format: string, args: ..any) {
		text := fmt.tprintf(format, ..args)
		if i := strings.index(text, " (parts turned"); i >= 0 && said[text[:i]] {
			return // the same in every position: said once
		}
		if !said[text] {
			said[text] = true
			if fatal {
				fmt.eprintln("error:", text)
			} else {
				fmt.println("warning:", text)
			}
		}
		ok^ &&= !fatal
	}
	seen := make(map[iso.Cell]bool, len(data.blocks), context.temp_allocator)
	for e in data.blocks {
		if e.part == 0 && seen[e.cell] {
			say(&said, &ok, false, "two blocks at %v", e.cell)
		}
		seen[e.cell] = e.part == 0
	}
	for e in data.rise {
		if seen[e.cell] {
			say(&said, &ok, true, "a rising block at %v, turned a block stands already", e.cell)
		}
	}
	needed := make([dynamic]iso.Cell, 0, 32, context.temp_allocator)
	append(&needed, data.start)
	if data.has_exit {
		append(&needed, data.exit)
	}
	append(&needed, ..data.fragments[:])
	append(&needed, ..data.sigils[:])
	append(&needed, ..data.rests[:])
	for h in data.handles {
		append(&needed, h.cell)
	}
	for c in data.caves {
		append(&needed, c.cell)
	}
	append(&needed, ..data.reeds[:])
	for prop in data.props {
		if prop.kind not_in level.BLOCKING_PROPS {
			continue
		}
		for c in needed {
			if c == prop.cell {
				say(&said, &ok, true, "%v at %v stands on a cell the level needs", prop.kind, prop.cell)
			}
		}
	}
	lights := len(data.candelabra)
	if render.look(data.setting).candles {
		for prop in data.props {
			lights += int(prop.kind == .Sconce && prop.part == 0)
		}
	}
	if lights > level.MAX_LIGHTS {
		say(&said, &ok, false, "%d flames (candles, candelabra), the stones show the light of %d", lights, level.MAX_LIGHTS)
	}

	combos := 1
	for _ in data.parts {
		combos *= 4
	}
	for &f, i in p.flipped {
		f = data.blocks[i].trait == .Veiled
	}
	p.risen = pl.all_seals(data)
	for k in 0 ..< combos {
		n := k
		for i in 0 ..< len(data.parts) {
			p.part_rot[i] = n % 4
			n /= 4
		}
		pl.rebuild_graph(p)
		parts := p.part_rot[:len(data.parts)]
		turned := k > 0 ? fmt.tprintf(" (parts turned %v)", parts) : ""
		for prop in data.props {
			c, d := pl.prop_place(p, prop)
			v := iso.DIR_VEC[d]
			in_cell := pl.solid_at(p, c).kind
			below := pl.solid_at(p, c - {0, 0, 1}).kind
			switch {
			case prop.kind == .Sconce:
				if in_cell != .Block {
					say(&said, &ok, true, "the candle at %v has no wall%s", c, turned)
				} else if pl.solid_at(p, c + {v.x, v.y, 0}).kind != .None {
					say(&said, &ok, true, "the candle at %v %v is inside a wall%s", c, d, turned)
				}
			case prop.kind in level.EDGE_PROPS:
				// a rail beside a stair is its handrail; inside a block it is lost
				if in_cell == .Block {
					say(&said, &ok, false, "%v at %v is hidden in a block%s", prop.kind, c, turned)
				} else if below == .None && in_cell == .None {
					say(&said, &ok, true, "%v at %v hangs in the air%s", prop.kind, c, turned)
				}
			case in_cell != .None:
				say(&said, &ok, true, "%v at %v is inside a block%s", prop.kind, c, turned)
			case below != .Block:
				say(&said, &ok, true, "%v at %v hangs in the air%s", prop.kind, c, turned)
			}
		}
		for h in data.handles {
			if !pl.is_surface(p, h.cell) {
				say(&said, &ok, true, "the handle at %v is not on a floor%s", h.cell, turned)
			}
		}
		for cd in data.candelabra {
			if pl.solid_at(p, cd.cell).kind != .None || pl.solid_at(p, cd.cell - {0, 0, 1}).kind != .Block {
				say(&said, &ok, true, "the candelabrum at %v does not stand on a floor%s", cd.cell, turned)
			}
		}
	}
	for h in data.handles {
		for e in data.blocks {
			if e.cell == h.cell - {0, 0, 1} && e.part != 0 {
				say(&said, &ok, true, "the handle at %v stands on a part", h.cell)
			}
		}
	}
	// a ram stands on a floor, its cell free, never where the level needs her;
	// lying, it is a step from the floor behind it to the ledge it faces
	for m, i in data.rams {
		for c in needed {
			if c == m.cell {
				say(&said, &ok, true, "the ram at %v stands on a cell the level needs", m.cell)
			}
		}
		for o, j in data.rams {
			if o.cell == m.cell && j != i {
				say(&said, &ok, true, "two rams at %v", m.cell)
			}
		}
		for e in data.blocks {
			if e.cell == m.cell {
				say(&said, &ok, true, "the ram at %v is inside a block", m.cell)
			}
		}
		has_floor := false
		for e in data.blocks {
			has_floor ||= e.cell == m.cell - {0, 0, 1} && e.part == 0 && e.trait == .Stone
		}
		if !has_floor {
			say(&said, &ok, true, "the ram at %v does not stand on a fixed floor", m.cell)
		}
		for prop in data.props {
			if prop.cell == m.cell && prop.kind not_in level.EDGE_PROPS {
				say(&said, &ok, true, "%v at %v stands where a ram is", prop.kind, m.cell)
			}
		}
		v := iso.DIR_VEC[m.dir]
		p.day = false
		pl.rebuild_graph(p)
		if !pl.is_surface(p, m.cell + {v.x, v.y, 1}) {
			say(&said, &ok, false, "the ram at %v lying leads up to no floor at %v", m.cell, m.cell + {v.x, v.y, 1})
		}
		if !pl.is_surface(p, m.cell - {v.x, v.y, 0}) {
			say(&said, &ok, false, "the ram at %v lying is climbed from no floor at %v", m.cell, m.cell - {v.x, v.y, 0})
		}
		p.day = true
		pl.rebuild_graph(p)
	}
	for c in data.reeds {
		if !pl.is_surface(p, c) {
			say(&said, &ok, true, "the reed at %v is not on a floor", c)
		}
	}
	// the seeds rest on a floor, alone in their cell; a hollow is an empty
	// cell with a floor beside it at its own level (where the seed comes from)
	for c in data.seeds {
		for e in data.blocks {
			if e.cell == c {
				say(&said, &ok, true, "the seed at %v is inside a block", c)
			}
			if e.cell == c - {0, 0, 1} && (e.part != 0 || e.trait != .Stone) {
				say(&said, &ok, true, "the seed at %v rests on a part or a veiled stone", c)
			}
		}
		for prop in data.props {
			if prop.cell == c && prop.kind not_in level.EDGE_PROPS {
				say(&said, &ok, true, "%v at %v stands where a seed lies", prop.kind, c)
			}
		}
	}
	for h in data.hollows {
		for e in data.blocks {
			if e.cell == h {
				say(&said, &ok, true, "the hollow at %v is filled by a block already", h)
			}
		}
		floors := 0
		for d in iso.Dir {
			v := iso.DIR_VEC[d]
			for e in data.blocks {
				floors += int(e.cell == h + {v.x, v.y, 0} && e.part == 0)
			}
		}
		if floors == 0 {
			say(&said, &ok, false, "the hollow at %v has no floor beside it", h)
		}
	}
	// what stands on a veiled stone floats while it is hidden (the hand
	// ropes of a bridge do not: they hang between the posts)
	for prop in data.props {
		if prop.part != 0 || prop.kind == .Sconce || prop.kind == .Rope {
			continue
		}
		for e in data.blocks {
			if e.trait == .Veiled && e.cell == prop.cell - {0, 0, 1} {
				say(&said, &ok, false, "%v at %v floats until the stone under it is shown", prop.kind, prop.cell)
			}
		}
	}
	for &f in p.flipped {
		f = false
	}
	p.risen = {}
	p.part_rot = {}
	pl.set_view(p, 0)
	pl.rebuild_graph(p)
	return
}

report :: proc(p: ^pl.Palace, data: ^level.Level_Data, label: string, reached: []bool) {
	count := 0
	for ok in reached {
		count += int(ok)
	}
	fmt.printf("  %s  reach %d/%d", label, count, len(p.nodes))
	for c in data.sigils {
		i := pl.node_index(p, c)
		fmt.printf("  sigil:%v", i >= 0 && reached[i])
	}
	if data.has_amore {
		near := false
		for d in iso.Dir {
			v := iso.DIR_VEC[d]
			i := pl.node_index(p, data.amore + {v.x, v.y, 0})
			near ||= i >= 0 && reached[i]
		}
		fmt.printf("  amore:%v", near)
	}
	if data.has_exit {
		i := pl.node_index(p, data.exit)
		fmt.printf("  exit:%v", i >= 0 && reached[i])
	}
	for c in data.fragments {
		i := pl.node_index(p, c)
		fmt.printf("  fragment:%v", i >= 0 && reached[i])
	}
	fmt.println()
}

solve_report :: proc(p: ^pl.Palace, data: ^level.Level_Data, alloc: runtime.Allocator) {
	failed := false
	// parts must never turn into the palace, in any combination
	combos := 1
	for _ in data.parts {
		combos *= 4
	}
	for c in 0 ..< combos {
		k := c
		for n in 0 ..< len(data.parts) {
			p.part_rot[n] = k % 4
			k /= 4
		}
		pl.rebuild_graph(p)
		if p.overlap {
			fmt.eprintfln("error: parts turned %v overlap the palace", p.part_rot[:len(data.parts)])
			failed = true
		}
	}
	p.part_rot = {}
	pl.rebuild_graph(p)

	if !data.has_exit {
		fmt.eprintln("error: a level whose palace changes needs an exit")
		os.exit(1)
	}
	if !print_plan(p, data, alloc) {
		os.exit(1)
	}
	for c in data.fragments {
		reach := pl.solve(p, c, data.exit, alloc)
		optional := pl.solve(p, data.exit, c, alloc)
		fmt.printfln("\nfragment %v: reachable %v, optional %v", c, reach.solved, optional.solved)
		if reach.solved {
			fmt.printfln("  fragment plan: %d steps, %d turns, %d lightings, %d handles, %d ants, %d times turned", reach.steps, reach.turns, reach.lightings, reach.handles, reach.ants, reach.times)
		}
		if !reach.solved || !optional.solved {
			fmt.eprintln("error: the fragment must be reachable and never required")
			failed = true
		}
	}
	if len(data.fragments) == 0 {
		fmt.println("\nwarning: no fragment of the tale in this level")
	}
	if failed {
		os.exit(1)
	}
}

// The plan to the exit (or to Cupid's side) with the fewest decisions, step by step.
print_plan :: proc(p: ^pl.Palace, data: ^level.Level_Data, alloc: runtime.Allocator) -> bool {
	goal := pl.goal_cell(p)
	sol := pl.solve(p, goal, nil, alloc)
	fmt.printfln("\nsolver: %d states reached, %d dead ends", sol.states, sol.dead)
	if !sol.solved {
		fmt.eprintln("error: the exit cannot be reached")
		return false
	}
	fmt.printfln("plan: %d steps (%d in the light), %d turns, %d lightings, %d handles, %d ants, %d times turned", sol.steps, sol.light_steps, sol.turns, sol.lightings, sol.handles, sol.ants, sol.times)
	if data.has_lamp {
		rules := game.oil_rules(data)
		least := pl.oil_left(p, sol.plan[:], rules)
		fmt.printfln("oil: %.1f s in the lamp, at least %.1f s left along the plan", rules.oil, least)
		if least < 0 {
			fmt.eprintln("error: the lamp runs dry before the plan is done")
			return false
		}
	}
	walk := 0
	illusions := 0
	flush :: proc(walk, illusions: ^int, cell: iso.Cell) {
		if walk^ > 0 {
			fmt.printfln("  walk %2d to %v%s", walk^, cell, illusions^ > 0 ? fmt.tprintf(" (%d illusions)", illusions^) : "")
		}
		walk^, illusions^ = 0, 0
	}
	last := data.start
	day := len(data.reeds) > 0
	for st, i in sol.plan {
		if st.move == .Step {
			walk += 1
			illusions += int(st.illusion)
			last = st.cell
			if st.changed > 0 {
				flush(&walk, &illusions, last)
				fmt.printfln("        %d blocks change", st.changed)
			}
			if st.time {
				day = !day
				flush(&walk, &illusions, last)
				fmt.printfln("        the reed: %s", day ? "day (the rams stand)" : "evening (the rams lie down)")
			}
			continue
		}
		flush(&walk, &illusions, last)
		switch st.move {
		case .Turn_Left, .Turn_Right: fmt.printfln("  turn to view %d", st.view)
		case .Light: fmt.printfln("  light the lamp at %v (%d blocks change)", st.cell, st.changed)
		case .Douse: fmt.printfln("  put the lamp out")
		case .Handle: fmt.printfln("  turn the handle at %v", st.cell)
		case .Ants: fmt.printfln("  view %d: call the ants at %v, the seed goes %d cells into the hollow %v", st.view, st.cell, st.carry - 1, data.hollows[st.hollow])
		case .Start, .Step:
		}
		_ = i
	}
	flush(&walk, &illusions, last)
	return true
}
