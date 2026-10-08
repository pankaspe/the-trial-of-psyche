// Level analysis for designers: `./build.sh check assets/levels/level_04.txt`.
//
// For the base palace and after the seal has raised its blocks, it reports
// how much of the palace Psyche can reach from the start: in the light, in
// the dark for each view, and in the dark turning freely (turning is free
// while standing still, so the illusions of all four views add up). Then it
// lists the illusions of every view: watch out for unintended shortcuts.
// The fragment of the tale must be reachable and optional (the exit status
// is 1 otherwise).
// Levels whose palace changes (crumbling, phantom, veiled blocks, parts that
// turn) are also solved move by move: the tool prints the plan with the
// fewest decisions, how many states can be reached and how many of them are
// dead ends (the level must be restarted), and checks that no part turns
// into the palace.
package level_check

import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "base:runtime"

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
	p: pl.Palace
	pl.init(&p, &data, alloc)

	fmt.printfln("%s: %d x %d grid, %d blocks, %d props, %d rising", path, data.size, data.size, len(data.blocks), len(data.props), len(data.rise))
	for risen in ([2]bool{false, true}) {
		if risen && len(data.rise) == 0 {
			break
		}
		p.risen = risen ? pl.all_seals(&data) : {}
		pl.rebuild_graph(&p)
		tag := risen ? "risen" : "base "
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

	if !check_screen(&p, &data) {
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

// What the player sees and clicks: every cave has rock where its opening is
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
			fmt.printfln("  fragment plan: %d steps, %d turns, %d lightings, %d handles", reach.steps, reach.turns, reach.lightings, reach.handles)
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
	fmt.printfln("plan: %d steps (%d in the light), %d turns, %d lightings, %d handles", sol.steps, sol.light_steps, sol.turns, sol.lightings, sol.handles)
	walk := 0
	illusions := 0
	flush :: proc(walk, illusions: ^int, cell: iso.Cell) {
		if walk^ > 0 {
			fmt.printfln("  walk %2d to %v%s", walk^, cell, illusions^ > 0 ? fmt.tprintf(" (%d illusions)", illusions^) : "")
		}
		walk^, illusions^ = 0, 0
	}
	last := data.start
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
		case .Start, .Step:
		}
		_ = i
	}
	flush(&walk, &illusions, last)
	return true
}
