// Level analysis for designers: `./build.sh check assets/levels/level_01.txt`.
//
// For the base palace and after the seal has raised its blocks, it reports
// how much of the palace Psyche can reach from the start: in the light, in
// the dark for each view, and in the dark turning freely (turning is free
// while standing still, so the illusions of all four views add up). Then it
// lists the illusions of every view: watch out for unintended shortcuts.
package level_check

import "core:fmt"
import "core:mem/virtual"
import "core:os"

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
		p.risen = risen
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
		// turning freely: grow the reached set view after view until it settles
		pl.reachable(&p, data.start, true, reached)
		for changed := true; changed; {
			changed = false
			for r in 0 ..< 4 {
				pl.set_view(&p, r)
				changed ||= expand(&p, reached)
			}
		}
		report(&p, &data, fmt.tprintf("%s dark  turning", tag), reached)
	}

	for r in 0 ..< 4 {
		pl.set_view(&p, r)
		fmt.printf("\nview %d illusions (%d):", r, len(p.illusion.pairs))
		for e in p.illusion.pairs {
			fmt.printf(" %v-%v", p.nodes[e[0]].cell, p.nodes[e[1]].cell)
		}
		fmt.println()
	}
}

// Add every node reachable in the dark (current view) from the reached set.
expand :: proc(p: ^pl.Palace, reached: []bool) -> (changed: bool) {
	queue := make([dynamic]i32, 0, len(p.nodes), context.temp_allocator)
	for ok, i in reached {
		if ok {
			append(&queue, i32(i))
		}
	}
	for head := 0; head < len(queue); head += 1 {
		cur := queue[head]
		for g in ([]^pl.Graph{&p.real, &p.illusion}) {
			for nb in pl.neighbours(g, cur) {
				if !reached[nb] {
					reached[nb] = true
					changed = true
					append(&queue, nb)
				}
			}
		}
	}
	return
}

report :: proc(p: ^pl.Palace, data: ^level.Level_Data, label: string, reached: []bool) {
	count := 0
	for ok in reached {
		count += int(ok)
	}
	fmt.printf("  %s  reach %d/%d", label, count, len(p.nodes))
	if data.has_sigil {
		i := pl.node_index(p, data.sigil)
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
	fmt.println()
}
