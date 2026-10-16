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
// into the palace. For the designer, one more report: which pieces the level
// could do without (each sundial, ram, handle, eagle, ferry, pair of caves taken out in
// turn: a level still solved without one has a piece that does nothing, or a
// way round it). A level with Proserpina's pomegranates is reported either
// way up ("upside": the world turned over, reached from its pomegranates).
//
// `--try CANDIDATES`: is a decoration harmless? Each line of the file is a
// variant (level lines joined by `;`, `under LINE` for the world under the
// palace), added to the level alone: it is refused by the loader, neutral,
// or the tool says what it changes. A prop or candelabrum that only
// decorates is weighed by the checks' errors and warnings; anything else
// also by the illusions and stairs of every view and the solver's plans.
package level_check

import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:strconv"
import "core:strings"
import "base:runtime"

import "../../src/game"
import "../../src/iso"
import "../../src/level"
import pl "../../src/palace"

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
	if len(os.args) > 3 && os.args[2] == "--try" {
		try_report(string(text), os.args[3])
		return
	}
	p: pl.Palace
	pl.init(&p, &data, alloc)
	if len(os.args) > 2 && os.args[2] == "--brief" {
		brief(&p, &data, alloc)
		return
	}

	fmt.printfln("%s: %d x %d grid, %d blocks, %d props, %d rising", path, data.size, data.size, len(data.blocks), len(data.props), len(data.rise))
	frames := len(data.pomegranates) > 0 ? 2 : 1
	for k in 0 ..< 4 * frames {
		risen, evening, upside := k % 2 == 1, k % 4 >= 2, k >= 4
		if risen && len(data.rise) == 0 || evening && len(data.sundials) == 0 {
			continue
		}
		p.risen = risen ? pl.all_seals(&data) : {}
		p.day = len(data.sundials) > 0 && !evening
		p.upside = upside
		pl.rebuild_graph(&p)
		from := upside ? data.pomegranates[0] : data.start
		tag := risen ? "risen" : "base "
		if upside {
			tag = fmt.tprintf("%s upside", tag)
		}
		if len(data.sundials) > 0 {
			tag = fmt.tprintf("%s %s", tag, evening ? "evening" : "day    ")
		}
		if p.day {
			// by day the sun shows the truth: no illusions
			fmt.printfln("\n%s: %d surfaces and stairs", tag, len(p.nodes))
			reached := make([]bool, len(p.nodes), alloc)
			pl.reachable(&p, from, false, reached)
			report(&p, &data, fmt.tprintf("%s sun  ", tag), reached)
			continue
		}
		fmt.printfln("\n%s: %d surfaces and stairs", tag, len(p.nodes))
		reached := make([]bool, len(p.nodes), alloc)

		pl.reachable(&p, from, false, reached)
		report(&p, &data, fmt.tprintf("%s light       ", tag), reached)
		for r in 0 ..< 4 {
			pl.set_view(&p, r)
			pl.reachable(&p, from, true, reached)
			report(&p, &data, fmt.tprintf("%s dark  view %d", tag, r), reached)
		}
		pl.reachable_turning(&p, from, reached)
		report(&p, &data, fmt.tprintf("%s dark  turning", tag), reached)
	}
	p.risen = {}
	p.day = false // the illusions below are those of the dark (at evening)

	for upside in 0 ..< frames {
		p.upside = upside == 1
		pl.rebuild_graph(&p)
		side := p.upside ? " upside" : ""
		for r in 0 ..< 4 {
			pl.set_view(&p, r)
			fmt.printf("\nview %d%s stairs usable in the dark:", r, side)
			for node, i in p.nodes {
				if node.stair {
					fmt.printf(" %v:%v", node.cell, p.stair_seen[i])
				}
			}
			fmt.printf("\nview %d%s illusions (%d):", r, side, len(p.illusion.pairs))
			for e in p.illusion.pairs {
				fmt.printf(" %v-%v", p.nodes[e[0]].cell, p.nodes[e[1]].cell)
			}
			fmt.println()
		}
		if pl.is_dynamic(&data) {
			whole_illusions(&p, &data, alloc)
		}
	}
	p.upside = false
	p.day = len(data.sundials) > 0
	pl.rebuild_graph(&p)

	if !check_screen(&p, &data) || !check_props(&p, &data) {
		os.exit(1)
	}

	if pl.is_dynamic(&data) {
		solve_report(&p, &data, alloc)
		needed_report(string(text))
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

// Where the checks' errors and warnings go: printed (errors to stderr), or,
// while `--try` weighs a variant, gathered here.
capture: ^[dynamic]string

note :: proc(fatal: bool, format: string, args: ..any) {
	text := fmt.tprintf(format, ..args)
	switch {
	case capture != nil: append(capture, fmt.aprintf("%s %s", fatal ? "error:" : "warning:", text))
	case fatal: fmt.eprintln("error:", text)
	case: fmt.println("warning:", text)
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
			note(true, "the cave at %v has no rock on its side %v", cave.cell, cave.dir)
			ok = false
		}
	}
	for whole in ([2]bool{false, true}) {
		// as loaded (veiled stones hidden), then whole
		set_whole(p, data, whole)
		pl.rebuild_graph(p)
		for c, i in data.fragments {
			p.upside = i in data.fragments_under
			pl.rebuild_graph(p)
			for r in 0 ..< 4 {
				pl.set_view(p, r)
				w := pl.node_world(p, c) + {0, 0, 0.22}
				got, found := pl.pick(p, iso.project(iso.view_point(w, f32(r), p.size)), f32(r))
				if found && got != c {
					cave := pl.cave_at(p, got) >= 0 ? " (a cave's mouth!)" : ""
					note(false, "view %d%s: a click on the scroll at %v picks %v%s", r, whole ? "" : " (veiled hidden)", c, got, cave)
				}
			}
		}
	}
	as_loaded(p, data)
	return
}

// The palace whole (every veiled stone shown, every seal's blocks raised), or
// as loaded; the graph is the caller's to rebuild.
set_whole :: proc(p: ^pl.Palace, data: ^level.Level_Data, whole: bool) {
	for &f, i in p.flipped {
		f = whole && data.blocks[i].trait == .Veiled
	}
	p.risen = whole ? pl.all_seals(data) : {}
}

// Back to the palace as loaded: nothing changed, parts unturned, the world
// up as described, view 0.
as_loaded :: proc(p: ^pl.Palace, data: ^level.Level_Data) {
	set_whole(p, data, false)
	p.part_rot = {}
	p.upside = false
	pl.set_view(p, 0)
	pl.rebuild_graph(p)
}

// The illusions of the palace changed for good (veiled stones shown, every
// seal's blocks raised), parts as loaded: those not in the base listing.
whole_illusions :: proc(p: ^pl.Palace, data: ^level.Level_Data, alloc: runtime.Allocator) {
	upside := p.upside
	defer {
		p.upside = upside
		pl.rebuild_graph(p)
	}
	Pair :: [2]iso.Cell
	base := make(map[Pair]bool, 64, alloc)
	for r in 0 ..< 4 {
		pl.set_view(p, r)
		for e in p.illusion.pairs {
			base[{p.nodes[e[0]].cell, p.nodes[e[1]].cell}] = true
		}
	}
	set_whole(p, data, true)
	pl.rebuild_graph(p)
	for r in 0 ..< 4 {
		pl.set_view(p, r)
		fmt.printf("whole view %d%s, new illusions:", r, p.upside ? " upside" : "")
		for e in p.illusion.pairs {
			pair := Pair{p.nodes[e[0]].cell, p.nodes[e[1]].cell}
			if !base[pair] {
				fmt.printf(" %v-%v", pair[0], pair[1])
			}
		}
		fmt.println()
	}
	as_loaded(p, data)
}

// What would look wrong (an error) or odd (a warning), with the palace whole
// (veiled stones shown, the seals' blocks raised) and every part in each of
// its positions: a prop inside a block or hanging in the air, a candle with no
// wall, a candelabrum off a floor, a blocking prop on a cell the level needs,
// a handle on a part, a block given twice, a prop foreign to the biome.
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
			note(fatal, "%s", text)
		}
		ok^ &&= !fatal
	}
	// blocks by the cell they fill in the world as described (the world
	// under the palace turned over to it)
	seen := make(map[iso.Cell]bool, len(data.blocks), context.temp_allocator)
	for e in data.blocks {
		c := level.world_cell(data, e.cell, e.under)
		if e.part == 0 && seen[c] {
			say(&said, &ok, false, "two blocks at %v%s", e.cell, e.under ? " (under)" : "")
		}
		seen[c] = e.part == 0
	}
	for e in data.rise {
		if seen[level.world_cell(data, e.cell, e.under)] {
			say(&said, &ok, true, "a rising block at %v, turned a block stands already", e.cell)
		}
	}
	needed := make([dynamic]pl.Spot, 0, 32, context.temp_allocator)
	append(&needed, pl.Spot{data.start, false})
	if data.has_exit {
		append(&needed, pl.exit_spot(data))
	}
	for _, i in data.fragments {
		append(&needed, pl.fragment_spot(data, i))
	}
	for c, k in data.sigils {
		append(&needed, pl.Spot{c, k in data.sigils_under})
	}
	for c in data.rests {
		append(&needed, pl.Spot{c, false})
	}
	for h in data.handles {
		append(&needed, pl.Spot{h.cell, false})
	}
	for c in data.caves {
		append(&needed, pl.Spot{c.cell, false})
	}
	for c in data.sundials {
		append(&needed, pl.Spot{c, false})
	}
	for e in data.eagles {
		append(&needed, pl.Spot{e.from, false}, pl.Spot{e.to, false})
	}
	for f in data.ferries {
		append(&needed, pl.Spot{f.ends[0].cell, false}, pl.Spot{f.ends[1].cell, false})
	}
	for c in data.pomegranates {
		append(&needed, pl.Spot{c, false}, pl.Spot{c, true})
	}
	for prop in data.props {
		if level.PROPS[prop.kind].fill != .Cell {
			continue
		}
		for c in needed {
			if c.cell == prop.cell && c.under == prop.under {
				say(&said, &ok, true, "%v at %v stands on a cell the level needs", prop.kind, prop.cell)
			}
		}
	}
	// a pomegranate lies on a stone of the axle, with room on both sides
	for c in data.pomegranates {
		for upside in ([2]bool{false, true}) {
			p.upside = upside
			pl.rebuild_graph(p)
			if !pl.can_turn_over(p, c) {
				say(&said, &ok, true, "the pomegranate at %v cannot turn the world%s: no floor, or no room on the other side", c, upside ? " back" : " over")
			}
		}
	}
	p.upside = false
	combos := 1
	for _ in data.parts {
		combos *= 4
	}
	set_whole(p, data, true)
	frames := len(data.pomegranates) > 0 ? 2 : 1
	for k in 0 ..< combos * frames {
		n := k / frames
		for i in 0 ..< len(data.parts) {
			p.part_rot[i] = n % 4
			n /= 4
		}
		// each world checked while it is up
		p.upside = k % frames == 1
		pl.rebuild_graph(p)
		parts := p.part_rot[:len(data.parts)]
		turned := k >= frames ? fmt.tprintf(" (parts turned %v)", parts) : ""
		for prop in data.props {
			if prop.under != p.upside {
				continue
			}
			c, d := pl.prop_place(p, prop)
			v := iso.DIR_VEC[d]
			in_cell := pl.solid_at(p, c).kind
			below := pl.solid_at(p, c - {0, 0, 1}).kind
			switch {
			case level.PROPS[prop.kind].rest == .Wall:
				if in_cell != .Block {
					say(&said, &ok, true, "%v at %v has no wall%s", prop.kind, c, turned)
				} else if pl.solid_at(p, c + {v.x, v.y, 0}).kind != .None {
					say(&said, &ok, true, "%v at %v %v is inside a wall%s", prop.kind, c, d, turned)
				}
			case level.PROPS[prop.kind].fill == .Side:
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
			if !p.upside && !pl.is_surface(p, h.cell) {
				say(&said, &ok, true, "the handle at %v is not on a floor%s", h.cell, turned)
			}
		}
		for cd in data.candelabra {
			if cd.under != p.upside {
				continue
			}
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
			if c == (pl.Spot{m.cell, false}) {
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
			if prop.cell == m.cell && level.PROPS[prop.kind].fill != .Side {
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
	for c in data.sundials {
		if !pl.is_surface(p, c) {
			say(&said, &ok, true, "the sundial at %v is not on a floor", c)
		}
	}
	for e in data.eagles {
		if !pl.is_surface(p, e.from) {
			say(&said, &ok, true, "the eagle's perch at %v is not on a floor", e.from)
		}
		if !pl.is_surface(p, e.to) {
			say(&said, &ok, true, "the eagle from %v sets her down at %v, not on a floor", e.from, e.to)
		}
		for h in data.handles {
			if h.cell == e.from {
				say(&said, &ok, true, "a handle and an eagle's perch at %v", e.from)
			}
		}
		for c in data.sundials {
			if c == e.from {
				say(&said, &ok, true, "a sundial and an eagle's perch at %v", e.from)
			}
		}
	}
	p.upside = false
	pl.rebuild_graph(p)
	// the ferries are of the world above
	for f in data.ferries {
		for e in f.ends {
			if !pl.is_surface(p, e.cell) {
				say(&said, &ok, true, "the ferry's landing at %v is not on a floor", e.cell)
			}
			if w := e.cell + {iso.DIR_VEC[e.dir].x, iso.DIR_VEC[e.dir].y, -1}; pl.in_grid(p, w) && pl.solid_at(p, w).kind != .None {
				say(&said, &ok, true, "the ferry's boat at %v is moored into stone (%v)", e.cell, w)
			}
		}
	}
	// what stands on a veiled stone floats while it is hidden (what rests
	// elsewhere does not: a candle on its wall, the hand ropes of a bridge
	// between the posts)
	for prop in data.props {
		if prop.part != 0 || level.PROPS[prop.kind].rest != .Floor {
			continue
		}
		for e in data.blocks {
			if e.trait == .Veiled && e.under == prop.under && e.cell == prop.cell - {0, 0, 1} {
				say(&said, &ok, false, "%v at %v floats until the stone under it is shown", prop.kind, prop.cell)
			}
		}
	}
	// a prop foreign to the place: the level's biome, the world under it its own
	if data.has_biome {
		worlds := [2]level.Biome{data.biome, level.BIOMES[data.biome].upside.? or_else data.biome}
		strays: [2][level.Prop_Kind]int
		for prop in data.props {
			if level.BIOMES[worlds[int(prop.under)]].props[prop.kind] == 0 {
				strays[int(prop.under)][prop.kind] += 1
			}
		}
		for list, w in strays {
			for n, kind in list {
				if n > 0 {
					say(&said, &ok, false, "%v (%d) is foreign to the biome %s", kind, n, level.BIOMES[worlds[w]].name)
				}
			}
		}
	}
	as_loaded(p, data)
	return
}

report :: proc(p: ^pl.Palace, data: ^level.Level_Data, label: string, reached: []bool) {
	count := 0
	for ok in reached {
		count += int(ok)
	}
	fmt.printf("  %s  reach %d/%d", label, count, len(p.nodes))
	at :: proc(p: ^pl.Palace, reached: []bool, c: iso.Cell, under: bool) -> bool {
		i := pl.node_index(p, c)
		return i >= 0 && reached[i] && pl.upright(p, under)
	}
	for c, k in data.sigils {
		fmt.printf("  sigil:%v", at(p, reached, c, k in data.sigils_under))
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
		fmt.printf("  exit:%v", at(p, reached, data.exit, data.exit_under))
	}
	for c, i in data.fragments {
		fmt.printf("  fragment:%v", at(p, reached, c, i in data.fragments_under))
	}
	for c in data.pomegranates {
		fmt.printf("  pomegranate:%v", at(p, reached, c, p.upside))
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
	for c, i in data.fragments {
		spot := pl.fragment_spot(data, i)
		reach := pl.solve(p, spot, pl.exit_spot(data), alloc)
		optional := pl.solve(p, pl.exit_spot(data), spot, alloc)
		fmt.printfln("\nfragment %v%s: reachable %v, optional %v", c, spot.under ? " (under)" : "", reach.solved, optional.solved)
		if reach.solved {
			fmt.printfln("  fragment plan: %d steps, %d turns, %d lightings, %d handles, %d times turned, %d flights, %d overturns, %d crossings, %d decisions", reach.steps, reach.turns, reach.lightings, reach.handles, reach.times, reach.flights, reach.overturns, reach.crossings, decisions(reach))
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
	fmt.printfln("plan: %d steps (%d in the light), %d turns, %d lightings, %d handles, %d times turned, %d flights, %d overturns, %d crossings", sol.steps, sol.light_steps, sol.turns, sol.lightings, sol.handles, sol.times, sol.flights, sol.overturns, sol.crossings)
	fmt.printfln("decisions: %d (turns, lightings, handles, sundials, eagles, pomegranates, ferries)", decisions(sol))
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
	day := len(data.sundials) > 0
	for st, i in sol.plan {
		if st.move == .Step {
			walk += 1
			illusions += int(st.illusion)
			last = st.cell
			if st.changed > 0 {
				flush(&walk, &illusions, last)
				fmt.printfln("        %d blocks change", st.changed)
			}
			continue
		}
		flush(&walk, &illusions, last)
		switch st.move {
		case .Turn_Left, .Turn_Right: fmt.printfln("  turn to view %d", st.view)
		case .Light: fmt.printfln("  light the lamp at %v (%d blocks change)", st.cell, st.changed)
		case .Douse: fmt.printfln("  put the lamp out")
		case .Handle: fmt.printfln("  turn the handle at %v", st.cell)
		case .Time:
			day = !day
			fmt.printfln("  the sundial at %v: %s", st.cell, day ? "day (the rams stand)" : "evening (the rams lie down)")
		case .Flight:
			fmt.printfln("  the eagle carries her to %v%s", st.cell, st.changed > 0 ? fmt.tprintf(" (%d blocks change)", st.changed) : "")
		case .Overturn:
			fmt.printfln("  the pomegranate at %v: the world %s", st.cell, st.upside ? "turned over (the world under the palace up)" : "turned back")
		case .Ferry:
			fmt.printfln("  Charon ferries her across to %v%s", st.cell, st.changed > 0 ? fmt.tprintf(" (%d blocks change)", st.changed) : "")
		case .Start, .Step:
		}
		_ = i
	}
	flush(&walk, &illusions, last)
	return true
}

// Take out each piece of the puzzle in turn (a sundial, a handle, a pair
// of caves, a ferry; a ram's step: a block of rock takes its place, solid as the ram
// lying, with a boulder on it, as nobody passes the ram standing) and solve
// again: a level still solved without it
// has a piece that is not needed (a way round it, or a decoy: say which in
// the level's notes).
needed_report :: proc(text: string) {
	lines := strings.split_lines(text, context.temp_allocator)
	caves := make([dynamic]int, 0, 8, context.temp_allocator)
	tests := make([dynamic][2]int, 0, 32, context.temp_allocator)
	for line, i in lines {
		f := strings.fields(line, context.temp_allocator)
		if len(f) == 0 {
			continue
		}
		switch f[0] {
		case "sundial", "ram", "handle", "eagle", "pomegranate", "ferry":
			append(&tests, [2]int{i, -1})
		case "cave":
			append(&caves, i)
		}
	}
	for k := 0; k + 1 < len(caves); k += 2 {
		append(&tests, [2]int{caves[k], caves[k + 1]})
	}
	if len(tests) == 0 {
		return
	}
	fmt.println("\nwithout each piece:")
	for t in tests {
		arena: virtual.Arena
		alloc := virtual.arena_allocator(&arena)
		b := strings.builder_make(alloc)
		for line, i in lines {
			if i == t[0] && strings.has_prefix(line, "ram ") {
				f := strings.fields(line, context.temp_allocator)
				h, _ := strconv.parse_int(f[3])
				fmt.sbprintfln(&b, "column %s %s %d %d\nprop boulder %s %s %d", f[1], f[2], h, h, f[1], f[2], h + 1)
			} else if i != t[0] && i != t[1] {
				strings.write_string(&b, line)
				strings.write_byte(&b, '\n')
			}
		}
		what := strings.trim_space(lines[t[0]])
		if t[1] >= 0 {
			what = fmt.tprintf("%s + %s", what, strings.trim_space(lines[t[1]]))
		}
		data, err := level.parse(strings.to_string(b), alloc)
		switch {
		case err != nil:
			fmt.printfln("  %-36s needed (the level does not load: %s)", what, err.?.message)
		case:
			p: pl.Palace
			pl.init(&p, &data, alloc)
			sol := pl.solve(&p, pl.goal_cell(&p), nil, alloc)
			if sol.solved {
				fmt.printfln("  %-36s NOT needed: solved in %d steps, %d decisions", what, sol.steps, decisions(sol))
			} else {
				fmt.printfln("  %-36s needed", what)
			}
		}
		virtual.arena_destroy(&arena)
	}
}

// `--brief`: one line for the plan and one per fragment (scripts that try
// many variants of a design read these).
brief :: proc(p: ^pl.Palace, data: ^level.Level_Data, alloc: runtime.Allocator) {
	lines, steps := plans(p, data, alloc)
	fmt.println(lines[0])
	if len(os.args) > 3 && os.args[3] == "--steps" {
		fmt.println(steps)
	}
	for l in lines[1:] {
		fmt.println(l)
	}
}

// The solver's plans, one line each: the exit's, each fragment's, the exit
// without each fragment; and the exit plan's steps.
plans :: proc(p: ^pl.Palace, data: ^level.Level_Data, alloc: runtime.Allocator) -> (lines: [dynamic]string, steps: string) {
	line :: proc(tag: string, sol: pl.Solution) -> string {
		if !sol.solved {
			return fmt.aprintf("%s unsolved states %d", tag, sol.states)
		}
		// visits: runs of handle turns in one place (turning a part three
		// quarters is one decision, not three)
		visits := 0
		for st, i in sol.plan {
			visits += int(st.move == .Handle && (i == 0 || sol.plan[i - 1].move != .Handle))
		}
		return fmt.aprintf("%s steps %d turns %d handles %d visits %d times %d flights %d overturns %d crossings %d decisions %d states %d dead %d", tag, sol.steps, sol.turns, sol.handles, visits, sol.times, sol.flights, sol.overturns, sol.crossings, decisions(sol), sol.states, sol.dead)
	}
	context.allocator = alloc
	sol := pl.solve(p, pl.goal_cell(p), nil, alloc)
	append(&lines, line("exit", sol))
	b := strings.builder_make()
	for st in sol.plan {
		fmt.sbprintf(&b, " %v%v%s%s", st.move == .Step ? "" : fmt.tprintf("%v@", st.move), st.cell, st.upside ? "u" : "", st.illusion ? fmt.tprintf("~v%d", st.view) : "")
	}
	steps = strings.to_string(b)
	for _, i in data.fragments {
		spot := pl.fragment_spot(data, i)
		append(&lines, line(fmt.tprintf("fragment%d", i), pl.solve(p, spot, pl.exit_spot(data), alloc)))
		append(&lines, line(fmt.tprintf("without%d", i), pl.solve(p, pl.exit_spot(data), spot, alloc)))
	}
	return
}

// What the player decides along a plan: turns, lightings, handles, sundials,
// eagles, pomegranates, ferries.
decisions :: proc(sol: pl.Solution) -> int {
	return sol.turns + sol.lightings + sol.handles + sol.times + sol.flights + sol.overturns + sol.crossings
}

// `--try`: each candidate added to the level alone, weighed against it.
try_report :: proc(base: string, path: string) {
	list, read_err := os.read_entire_file_from_path(path, context.allocator)
	if read_err != nil {
		fmt.eprintfln("cannot read %s: %v", path, read_err)
		os.exit(1)
	}
	base_arena: virtual.Arena
	defer virtual.arena_destroy(&base_arena)
	base_alloc := virtual.arena_allocator(&base_arena)
	before: [2][dynamic]string // the level's: its checks only, everything
	have_full := false
	before[0], _ = signature(base, false, base_alloc)
	counts: [3]int // neutral, changes, refused
	rest := string(list)
	for raw in strings.split_lines_iterator(&rest) {
		line := strings.trim_space(strings.split_n(raw, "#", 2, context.temp_allocator)[0])
		if line == "" {
			continue
		}
		// the candidate's lines, and whether one of them may change the walk
		b := strings.builder_make(context.temp_allocator)
		strings.write_string(&b, base)
		full := false
		for part in strings.split(line, ";", context.temp_allocator) {
			l := strings.trim_space(part)
			under := strings.has_prefix(l, "under ")
			if under {
				l = l[len("under "):]
			}
			full ||= !decorates(l)
			fmt.sbprintf(&b, under ? "\nunder\n%s\nend" : "\n%s", l)
		}
		if full && !have_full {
			before[1], _ = signature(base, true, base_alloc)
			have_full = true
		}
		arena: virtual.Arena
		after, err := signature(strings.to_string(b), full, virtual.arena_allocator(&arena))
		if e, failed := err.?; failed {
			fmt.printfln("refused  %s: %s", line, e.message)
			counts[2] += 1
		} else {
			gone, came := differ(before[int(full)][:], after[:])
			if len(gone) + len(came) == 0 {
				fmt.printfln("neutral  %s", line)
				counts[0] += 1
			} else {
				fmt.printfln("changes  %s", line)
				print_changes(gone[:], came[:])
				counts[1] += 1
			}
		}
		virtual.arena_destroy(&arena)
		free_all(context.temp_allocator)
	}
	fmt.printfln("\n%d neutral, %d with changes, %d refused", counts[0], counts[1], counts[2])
}

// A level line that only decorates: a prop the walk ignores, a candelabrum
// that is not a guard.
decorates :: proc(line: string) -> bool {
	f := strings.fields(line, context.temp_allocator)
	switch {
	case len(f) > 1 && f[0] == "prop":
		for info in level.PROPS {
			if info.name == f[1] {
				return info.fill == .None
			}
		}
	case len(f) > 0 && f[0] == "candelabrum":
		return !strings.contains(line, "guard")
	}
	return false
}

// What a variant must leave as it was: the checks' errors and warnings and,
// in full, the stairs and illusions of every view (either way up) and the
// solver's plans.
signature :: proc(text: string, full: bool, alloc: runtime.Allocator) -> (sig: [dynamic]string, err: Maybe(level.Parse_Error)) {
	context.allocator = alloc
	data := new(level.Level_Data)
	data^ = level.parse(text, alloc) or_return
	p := new(pl.Palace)
	pl.init(p, data, alloc)
	if full {
		lines, steps := plans(p, data, alloc)
		append(&sig, ..lines[:])
		append(&sig, fmt.aprintf("plan%s", steps))
		for upside in 0 ..< (len(data.pomegranates) > 0 ? 2 : 1) {
			p.upside = upside == 1
			p.day = false // the illusions of the dark
			pl.rebuild_graph(p)
			for r in 0 ..< 4 {
				pl.set_view(p, r)
				side := p.upside ? " upside" : ""
				b := strings.builder_make()
				fmt.sbprintf(&b, "view %d%s stairs usable in the dark:", r, side)
				for node, i in p.nodes {
					if node.stair {
						fmt.sbprintf(&b, " %v:%v", node.cell, p.stair_seen[i])
					}
				}
				append(&sig, strings.to_string(b))
				b = strings.builder_make()
				fmt.sbprintf(&b, "view %d%s illusions:", r, side)
				for e in p.illusion.pairs {
					fmt.sbprintf(&b, " %v-%v", p.nodes[e[0]].cell, p.nodes[e[1]].cell)
				}
				append(&sig, strings.to_string(b))
			}
		}
		p.upside = false
		p.day = len(data.sundials) > 0
		as_loaded(p, data)
	}
	capture = &sig
	check_screen(p, data)
	check_props(p, data)
	capture = nil
	return
}

// What is in one list and not the other.
differ :: proc(before, after: []string) -> (gone, came: [dynamic]string) {
	gone = make([dynamic]string, context.temp_allocator)
	came = make([dynamic]string, context.temp_allocator)
	count := make(map[string]int, context.temp_allocator)
	for s in before {
		count[s] += 1
	}
	for s in after {
		count[s] -= 1
	}
	for s in before {
		if count[s] > 0 {
			append(&gone, s)
			count[s] -= 1
		}
	}
	for s in after {
		if count[s] < 0 {
			append(&came, s)
			count[s] += 1
		}
	}
	return
}

// What changed, readably: a line and its twin (the same tag: the words before
// its first colon, or its first word) as what differs between them; the
// checks' errors and warnings, and lines with no twin, as they are.
print_changes :: proc(gone, came: []string) {
	tag :: proc(s: string) -> string {
		if strings.has_prefix(s, "error:") || strings.has_prefix(s, "warning:") {
			return s // never paired
		}
		if i := strings.index_byte(s, ':'); i >= 0 {
			return s[:i]
		}
		return strings.fields(s, context.temp_allocator)[0]
	}
	paired := make([]bool, len(came), context.temp_allocator)
	outer: for g in gone {
		for c, j in came {
			if !paired[j] && tag(g) == tag(c) {
				paired[j] = true
				fmt.printfln("           ~ %s: %s", tag(g), between(tag(g), g, c))
				continue outer
			}
		}
		fmt.printfln("           - %s", g)
	}
	for c, j in came {
		if !paired[j] {
			fmt.printfln("           + %s", c)
		}
	}
}

// How two lines of one tag differ: a plan from where it parts; a view's
// stairs or illusions by what it lost and what it gained; a solve's line
// word by word (each change labelled by the word before it).
between :: proc(tag, a, b: string) -> string {
	wa, wb := words(a), words(b)
	out := strings.builder_make(context.temp_allocator)
	sep :: proc(out: ^strings.Builder) -> string {
		return strings.builder_len(out^) > 0 ? ", " : ""
	}
	switch {
	case len(wa) == len(wb) && !strings.has_prefix(tag, "view"):
		for w, i in wa {
			if w != wb[i] {
				fmt.sbprintf(&out, "%s%s %s -> %s", sep(&out), i > 0 ? wa[i - 1] : "", w, wb[i])
			}
		}
	case tag == "plan":
		i := 0
		for i < len(wa) && i < len(wb) && wa[i] == wb[i] {
			i += 1
		}
		few :: proc(w: []string, i: int) -> string {
			return strings.join(w[i:min(i + 3, len(w))], " ", context.temp_allocator)
		}
		fmt.sbprintf(&out, "from %s ... -> %s ...", few(wa, i), few(wb, i))
	case:
		gone, came := differ(wa, wb)
		if len(gone) > 0 {
			fmt.sbprintf(&out, "lost %s", strings.join(gone[:], " ", context.temp_allocator))
		}
		if len(came) > 0 {
			fmt.sbprintf(&out, "%sgained %s", sep(&out), strings.join(came[:], " ", context.temp_allocator))
		}
	}
	return strings.to_string(out)
}

// The words of a line, a cell (or a pair of cells) written [x, y, z] one word.
words :: proc(s: string) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	depth, start := 0, -1
	for c, i in s {
		switch {
		case c == '[': depth += 1
		case c == ']': depth -= 1
		}
		if c == ' ' && depth == 0 {
			if start >= 0 {
				append(&out, s[start:i])
			}
			start = -1
		} else if start < 0 {
			start = i
		}
	}
	if start >= 0 {
		append(&out, s[start:])
	}
	return out[:]
}
