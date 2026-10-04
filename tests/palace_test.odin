// Rules of level I.4 on the walk graph (no window needed): `./build.sh test`.
package tests

import "core:mem/virtual"
import "core:testing"

import "../src/content"
import "../src/iso"
import "../src/level"
import "../src/palace"

BALCONY :: iso.Cell{3, 4, 3}
TERRACE :: iso.Cell{3, 7, 2} // foot of the stairs
ROOF_ENTRY :: iso.Cell{5, 5, 5}
BRIDGE :: iso.Cell{6, 3, 4}
LAMP_LEVEL :: 3 // I.4, "The Lamp and the Razor": the prototype's level

// Parse level I.4 and build its palace inside `arena`.
@(private)
load_level_1 :: proc(t: ^testing.T, arena: ^virtual.Arena, data: ^level.Level_Data, p: ^palace.Palace) -> bool {
	alloc := virtual.arena_allocator(arena)
	d, err := level.parse(content.LEVELS[LAMP_LEVEL].source, alloc)
	if e, failed := err.?; failed {
		testing.expectf(t, false, "level 1 does not parse: line %d: %s", e.line, e.message)
		return false
	}
	data^ = d
	palace.init(p, data, alloc)
	return true
}

@(private)
reach :: proc(p: ^palace.Palace, from, to: iso.Cell, dark: bool) -> bool {
	path: palace.Path
	return palace.find_path(p, from, to, dark, &path)
}

@(test)
every_level_parses :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	for info in content.LEVELS {
		if info.source == "" {
			continue // not built yet
		}
		data, err := level.parse(info.source, virtual.arena_allocator(&arena))
		if e, failed := err.?; failed {
			testing.expectf(t, false, "level %s: line %d: %s", info.id, e.line, e.message)
			continue
		}
		// the fragment of the tale: reachable, never required
		p: palace.Palace
		palace.init(&p, &data, virtual.arena_allocator(&arena))
		reachable, optional := palace.check_fragment(&p)
		testing.expectf(t, data.has_fragment, "level %s hides a fragment of the tale", info.id)
		testing.expectf(t, reachable && optional, "level %s: the fragment is reachable (%v) and optional (%v)", info.id, reachable, optional)
	}
}

@(test)
parse_errors_are_reported :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	alloc := virtual.arena_allocator(&arena)
	_, err := level.parse("size 4\nblock 1 1\nstart 0 0 1\n", alloc)
	e, failed := err.?
	testing.expect(t, failed && e.line == 2, "a short 'block' line is an error on line 2")
	_, err = level.parse("size 4\nvoice 0 0 1 v_nothing\nstart 0 0 1\n", alloc)
	testing.expect(t, err != nil, "an unknown voice key is an error")
	_, err = level.parse("size 4\nblock 0 0 0\n", alloc)
	testing.expect(t, err != nil, "a level without start is an error")
}

@(test)
every_surface_can_be_clicked :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	data: level.Level_Data
	p: palace.Palace
	if !load_level_1(t, &arena, &data, &p) {
		return
	}
	for r in 0 ..< 4 {
		palace.set_view(&p, r)
		angle := f32(r)
		for node in p.nodes {
			if node.stair {
				continue
			}
			pos := palace.node_screen(&p, node.cell, angle)
			ok := false
			// clickable somewhere on its visible top (stairs and walls may cover
			// part of it); a nearer surface on the same screen spot counts too,
			// since the two look like one
			for off in ([5]iso.Vec2{{0, 0}, {-32, 0}, {32, 0}, {0, 12}, {0, -12}}) {
				got, hit := palace.pick(&p, pos + off, angle)
				if hit {
					d := palace.node_screen(&p, got, angle) - pos
					ok ||= d.x * d.x + d.y * d.y < 1
				}
			}
			testing.expectf(t, ok, "view %d: surface %v cannot be clicked", r, node.cell)
		}
	}
}

@(test)
level_1_walkthrough :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	data: level.Level_Data
	p: palace.Palace
	if !load_level_1(t, &arena, &data, &p) {
		return
	}
	start, sigil := data.start, data.sigil

	palace.set_view(&p, 0)
	testing.expect(t, !reach(&p, start, TERRACE, true), "view 0: the walkway ends in a gap")
	palace.set_view(&p, 3)
	testing.expect(t, reach(&p, start, TERRACE, true), "view 3: the gap closes in the dark")
	testing.expect(t, !reach(&p, start, TERRACE, false), "view 3: but not in the light")
	testing.expect(t, !reach(&p, TERRACE, BALCONY, true), "view 3: the stairs are hidden, they lead nowhere in the dark")
	testing.expect(t, reach(&p, TERRACE, BALCONY, false), "view 3: the lamp shows the hidden stairs")
	for r in ([2]int{0, 2}) {
		palace.set_view(&p, r)
		testing.expectf(t, reach(&p, TERRACE, BALCONY, true), "view %d: the stairs are in sight and can be climbed", r)
	}
	palace.set_view(&p, 1)
	testing.expect(t, !reach(&p, TERRACE, BALCONY, true), "view 1: the stairs are half hidden")
	palace.set_view(&p, 3)
	testing.expect(t, !reach(&p, BALCONY, sigil, true), "view 3: the seal's pillar is out of reach")
	palace.set_view(&p, 1)
	testing.expect(t, reach(&p, BALCONY, sigil, true), "view 1: the seal's pillar joins the balcony")
	testing.expect(t, !reach(&p, sigil, ROOF_ENTRY, true), "view 1: the chamber is sealed before the lamp")
	for r in 0 ..< 4 {
		palace.set_view(&p, r)
		testing.expectf(t, !reach(&p, sigil, ROOF_ENTRY, true), "view %d: no way to the roof before the seal", r)
	}

	// the lamp on the seal raises the last stone
	p.risen = true
	palace.rebuild_graph(&p)
	palace.set_view(&p, 3)
	testing.expect(t, reach(&p, sigil, ROOF_ENTRY, true), "view 3: the bridge reaches the roof in the dark")
	testing.expect(t, !reach(&p, sigil, ROOF_ENTRY, false), "...and never in the light")
	testing.expect(t, reach(&p, sigil, BRIDGE, false), "the risen stone is really joined to the seal")
}

@(test)
illusions_need_the_dark :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	data: level.Level_Data
	p: palace.Palace
	if !load_level_1(t, &arena, &data, &p) {
		return
	}
	for r in 0 ..< 4 {
		palace.set_view(&p, r)
		for e in p.illusion.pairs {
			a, b := p.nodes[e[0]].cell, p.nodes[e[1]].cell
			testing.expectf(t, palace.is_illusion(&p, a, b) && palace.is_illusion(&p, b, a), "view %d: illusion %v-%v is symmetric", r, a, b)
			testing.expectf(t, a.z != b.z || iso.manhattan2(a, b) != 1, "view %d: illusion %v-%v is not a plain neighbour", r, a, b)
		}
	}
}
