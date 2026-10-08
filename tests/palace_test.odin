// Rules of level I.4 on the walk graph (no window needed): `./build.sh test`.
package tests

import "core:mem/virtual"
import "core:testing"

import "../src/content"
import "../src/iso"
import "../src/level"
import "../src/palace"

BALCONY :: iso.Cell{6, 5, 4} // top of the portico's stairs
TERRACE :: iso.Cell{6, 7, 3} // foot of the portico's stairs
GALLERY :: iso.Cell{11, 9, 5} // where the bridge ends
ROOF_ENTRY :: iso.Cell{13, 10, 6} // Cupid's chamber
BRIDGE :: iso.Cell{11, 4, 5} // the first stone the seal raises
LAMP_LEVEL :: 3 // I.4, "The Lamp and the Razor"

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
	for info, i in content.LEVELS {
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
		_, count := content.level_fragments(i)
		testing.expectf(t, len(data.fragments) == count && count > 0, "level %s hides its %d fragments of the tale (%d)", info.id, count, len(data.fragments))
		for _, f in data.fragments {
			reachable, optional := palace.check_fragment(&p, f)
			testing.expectf(t, reachable && optional, "level %s: fragment %d is reachable (%v) and optional (%v)", info.id, f, reachable, optional)
		}
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
	_, err = level.parse("size 4\ntier 5 2\nblock 0 0 0\nstart 0 0 1\n", alloc)
	testing.expect(t, err != nil, "a tier upside down is an error")
	d: level.Level_Data
	d, err = level.parse("size 4\ntier 1 3\ntier 6 9\nblock 0 0 0\nstart 0 0 1\n", alloc)
	testing.expect(t, err == nil && len(d.tiers) == 2 && d.tiers[1] == {6, 9}, "a tall level's bands of heights")
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
	testing.expect(t, !reach(&p, start, TERRACE, true), "view 0: the first stairs hide behind the candle post")
	palace.set_view(&p, 1)
	testing.expect(t, reach(&p, start, TERRACE, true), "view 1: up the stairs and across the seam, in the dark")
	testing.expect(t, !reach(&p, start, TERRACE, false), "view 1: but not in the light")
	for r in 0 ..< 4 {
		palace.set_view(&p, r)
		testing.expectf(t, !reach(&p, TERRACE, BALCONY, true), "view %d: the portico hides the stairs in the dark", r)
	}
	testing.expect(t, reach(&p, TERRACE, BALCONY, false), "the lamp shows the portico's stairs")
	for r in ([3]int{0, 2, 3}) {
		palace.set_view(&p, r)
		testing.expectf(t, !reach(&p, BALCONY, sigil, true), "view %d: the seal's pillar is out of reach", r)
	}
	palace.set_view(&p, 1)
	testing.expect(t, reach(&p, BALCONY, sigil, true), "view 1: the seal's pillar joins the balcony")
	for r in 0 ..< 4 {
		palace.set_view(&p, r)
		testing.expectf(t, !reach(&p, sigil, GALLERY, true) && !reach(&p, sigil, ROOF_ENTRY, true), "view %d: no way to the tower before the seal", r)
	}

	// the lamp on the seal raises a bridge of five stones
	p.risen = true
	palace.rebuild_graph(&p)
	testing.expect(t, reach(&p, sigil, GALLERY, false), "the bridge is real: it joins the seal to the gallery")
	testing.expect(t, reach(&p, sigil, BRIDGE, false), "the risen stone is really joined to the seal")
	palace.set_view(&p, 0)
	testing.expect(t, reach(&p, GALLERY, ROOF_ENTRY, true), "view 0: the gallery joins Cupid's chamber in the dark")
	testing.expect(t, !reach(&p, GALLERY, ROOF_ENTRY, false), "...and never in the light")
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
