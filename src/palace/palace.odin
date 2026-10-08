// The palace as a walk graph: surfaces, stairs, real edges, the illusions of
// the current view, visibility and path finding. Pure logic (no rendering).
//
// World cells never move; the view does. View r turns world (x, y) into
// (size-1-y, x) r times. Surfaces are "feet cells": (x, y, h) is walkable when a
// block sits at (x, y, h-1) and the cell itself is free. Stairs cells are nodes
// too. Real edges join neighbours at the same height (and stairs) unless a rail
// or wall closes that side. Illusion edges, walkable only in the dark, join
// surfaces that look adjacent in the current view, (x', y', h) and
// (x'+dx+k, y'+dy+k, h+k), when both tops are actually visible (not hidden by
// nearer cubes) and no rail closes either side.
// The same rule, read the other way: in the dark a flight of stairs hidden
// behind the palace leads nowhere. Stairs work in the dark only when every
// tread is visible in the current view; in the lamp light they always work.
//
// Caves come in pairs: walking into the mouth of one, Psyche comes out of the
// other. A passage is a real edge between the two mouths (it works in the
// dark and in the light, whatever the view).
//
// Act II: some blocks change for good (`flipped`): a crumbling block falls once
// Psyche steps off it, a phantom block (real only in the dark) dissolves when
// the lamp's light reaches it, a veiled block (hidden in the dark) becomes
// real there. Parts of the palace turn a quarter at a time about a pivot
// (`part_rot`). The graph is rebuilt after every change.
//
// Memory: every array is allocated once from the allocator given to `init`
// (the level arena) and reused; rebuilding the graph or the illusions does not
// allocate again once the arrays have grown. Scratch work uses the temp allocator.
package palace

import "core:math"
import "core:slice"
import sa "core:container/small_array"

import "../iso"
import "../level"

Cell :: iso.Cell
Dir :: iso.Dir

ILLUSION_REACH :: 8
MAX_PATH :: 512

Path :: sa.Small_Array(MAX_PATH, Cell)

Node :: struct {
	cell:  Cell,
	stair: bool,
	up:    Dir, // stairs only: the direction they rise toward
}

// Undirected edges in compressed form: the neighbours of node n are
// list[start[n]:start[n+1]].
Graph :: struct {
	pairs: [dynamic][2]i32, // unique, sorted (a < b)
	start: [dynamic]i32,
	list:  [dynamic]i32,
}

Palace :: struct {
	data:       ^level.Level_Data,
	size:       i32,
	height:     i32,
	rot:        int, // current view (0..3)
	risen:      bool,
	flipped:    []bool, // per data.blocks entry: changed for good (see the top)
	part_rot:   [level.MAX_PARTS]int, // quarter turns of each part
	overlap:    bool, // two blocks share a cell (a part turned into the palace)
	// world grid, indexed by cell_index
	solid:      []level.Solid,
	blocked:    []bool,
	fences:     []iso.Dirs,
	node_at:    []i32,
	block_at:   []i32, // index of the data.blocks entry in the cell, -1
	// view grid (same shape), for the current view
	view_node:  []i32,
	view_solid: []bool,
	stair_seen: []bool, // per node: stairs fully visible in the current view
	nodes:      [dynamic]Node,
	real:       Graph,
	illusion:   Graph,
}

init :: proc(p: ^Palace, data: ^level.Level_Data, allocator := context.allocator) {
	context.allocator = allocator
	p^ = {}
	p.data = data
	p.size = data.size
	p.height = data.height
	n := int(p.size * p.size * p.height)
	p.solid = make([]level.Solid, n)
	p.blocked = make([]bool, n)
	p.fences = make([]iso.Dirs, n)
	p.node_at = make([]i32, n)
	p.block_at = make([]i32, n)
	p.flipped = make([]bool, len(data.blocks))
	p.view_node = make([]i32, n)
	p.view_solid = make([]bool, n)
	p.stair_seen = make([]bool, n) // one per grid cell: enough for any node count
	p.nodes = make([dynamic]Node, 0, 256)
	for g in ([]^Graph{&p.real, &p.illusion}) {
		g.pairs = make([dynamic][2]i32, 0, 256)
		g.start = make([dynamic]i32, 0, 257)
		g.list = make([dynamic]i32, 0, 512)
	}
	rebuild_graph(p)
}

in_grid :: proc(p: ^Palace, c: Cell) -> bool {
	return c.x >= 0 && c.y >= 0 && c.z >= 0 && c.x < p.size && c.y < p.size && c.z < p.height
}

cell_index :: proc(p: ^Palace, c: Cell) -> int {
	return int((c.z * p.size + c.y) * p.size + c.x)
}

solid_at :: proc(p: ^Palace, c: Cell) -> level.Solid {
	return in_grid(p, c) ? p.solid[cell_index(p, c)] : {}
}

// Node index of cell c, or -1.
node_index :: proc(p: ^Palace, c: Cell) -> i32 {
	return in_grid(p, c) ? p.node_at[cell_index(p, c)] : -1
}

is_node :: proc(p: ^Palace, c: Cell) -> bool {
	return node_index(p, c) >= 0
}

is_surface :: proc(p: ^Palace, c: Cell) -> bool {
	i := node_index(p, c)
	return i >= 0 && !p.nodes[i].stair
}

is_stair :: proc(p: ^Palace, c: Cell) -> bool {
	i := node_index(p, c)
	return i >= 0 && p.nodes[i].stair
}

// Side d of cell c is open (no rail or wall stands there).
open :: proc(p: ^Palace, c: Cell, d: Dir) -> bool {
	return !in_grid(p, c) || d not_in p.fences[cell_index(p, c)]
}

// Is block entry i there now?
block_present :: proc(p: ^Palace, i: int) -> bool {
	return (p.data.blocks[i].trait == .Veiled) == p.flipped[i]
}

// Where block entry i is now (parts turn).
block_cell :: proc(p: ^Palace, i: int) -> Cell {
	e := p.data.blocks[i]
	if e.part == 0 {
		return e.cell
	}
	return level.part_cell(e.cell, p.data.parts[e.part - 1].pivot, p.part_rot[e.part - 1])
}

block_solid :: proc(p: ^Palace, i: int) -> level.Solid {
	e := p.data.blocks[i]
	s := e.solid
	if e.part != 0 && s.kind == .Stairs {
		s.dir = iso.rot_dir(s.dir, p.part_rot[e.part - 1])
	}
	return s
}

// Where a prop is now, and the side it closes.
prop_place :: proc(p: ^Palace, prop: level.Prop) -> (c: Cell, d: Dir) {
	if prop.part == 0 {
		return prop.cell, prop.dir
	}
	r := p.part_rot[prop.part - 1]
	return level.part_cell(prop.cell, p.data.parts[prop.part - 1].pivot, r), iso.rot_dir(prop.dir, r)
}

// The block entry Psyche stands on at feet cell c (-1: none, or stairs).
support :: proc(p: ^Palace, c: Cell) -> int {
	below := c - {0, 0, 1}
	if !in_grid(p, below) {
		return -1
	}
	return int(p.block_at[cell_index(p, below)])
}

// The lamp's light makes things true within this distance of Psyche's feet.
TRUTH_RADIUS :: 2.5

// Does the light of a lamp held by Psyche at feet cell `feet` reach block b?
in_truth :: proc(feet, b: Cell) -> bool {
	d := [3]f32{f32(b.x - feet.x), f32(b.y - feet.y), f32(b.z) + 0.5 - (f32(feet.z) + 0.4)}
	return d.x * d.x + d.y * d.y + d.z * d.z <= TRUTH_RADIUS * TRUTH_RADIUS
}

// The lamp cannot be lit over a phantom: it would vanish under Psyche's feet.
can_light :: proc(p: ^Palace, feet: Cell) -> bool {
	i := support(p, feet)
	return i < 0 || p.data.blocks[i].trait != .Phantom || !block_present(p, i)
}

// The lamp's light at feet cell `feet`: phantoms within reach dissolve, veiled
// blocks become real (never where Psyche stands: `keep` holds the feet cells
// she occupies). Returns true if anything changed (the graph is rebuilt).
lamp_touch :: proc(p: ^Palace, feet: Cell, keep: []Cell) -> bool {
	changed := false
	blocks: for e, i in p.data.blocks {
		if (e.trait != .Phantom && e.trait != .Veiled) || p.flipped[i] {
			continue
		}
		c := block_cell(p, i)
		if !in_truth(feet, c) {
			continue
		}
		for k in keep {
			if c == k || c == k - {0, 0, 1} {
				continue blocks
			}
		}
		p.flipped[i] = true
		changed = true
	}
	if changed {
		rebuild_graph(p)
	}
	return changed
}

// Psyche has left feet cell c: a crumbling block under it falls.
leave :: proc(p: ^Palace, c: Cell) -> (fell: int) {
	i := support(p, c)
	if i < 0 || p.data.blocks[i].trait != .Crumble || !block_present(p, i) {
		return -1
	}
	p.flipped[i] = true
	rebuild_graph(p)
	return i
}

// The handle at feet cell c, or -1.
handle_at :: proc(p: ^Palace, c: Cell) -> int {
	for h, i in p.data.handles {
		if h.cell == c {
			return i
		}
	}
	return -1
}

// Turn part n a quarter (counter-clockwise seen from above).
turn_part :: proc(p: ^Palace, n: int) {
	p.part_rot[n] = (p.part_rot[n] + 1) % 4
	rebuild_graph(p)
}

rebuild_graph :: proc(p: ^Palace) {
	slice.zero(p.solid)
	slice.zero(p.blocked)
	slice.zero(p.fences)
	slice.fill(p.node_at, -1)
	slice.fill(p.block_at, -1)
	p.overlap = false
	for _, i in p.data.blocks {
		if !block_present(p, i) {
			continue
		}
		c := cell_index(p, block_cell(p, i))
		p.overlap ||= p.solid[c].kind != .None
		p.solid[c] = block_solid(p, i)
		p.block_at[c] = i32(i)
	}
	if p.risen {
		for e in p.data.rise {
			p.solid[cell_index(p, e.cell)] = e.solid
		}
	}
	for prop in p.data.props {
		c, d := prop_place(p, prop)
		i := cell_index(p, c)
		if prop.kind in level.BLOCKING_PROPS {
			p.blocked[i] = true
		}
		if prop.kind in level.EDGE_PROPS {
			p.fences[i] += {d}
		}
	}

	clear(&p.nodes)
	for z in 0 ..< p.height {
		for y in 0 ..< p.size {
			for x in 0 ..< p.size {
				c := Cell{x, y, z}
				s := p.solid[cell_index(p, c)]
				switch s.kind {
				case .None:
				case .Stairs:
					add_node(p, {c, true, s.dir})
				case .Block:
					above := c + {0, 0, 1}
					if in_grid(p, above) && solid_at(p, above).kind == .None && !p.blocked[cell_index(p, above)] {
						add_node(p, {above, false, .PX})
					}
				}
			}
		}
	}

	clear(&p.real.pairs)
	for node, i in p.nodes {
		if node.stair {
			d := iso.DIR_VEC[node.up]
			bottom := node.cell - {d.x, d.y, 0}
			top := node.cell + {d.x, d.y, 1}
			for o in ([2]Cell{bottom, top}) {
				if is_surface(p, o) {
					add_pair(&p.real, i32(i), node_index(p, o))
				}
			}
			continue
		}
		for d in Dir {
			dv := iso.DIR_VEC[d]
			n := node.cell + {dv.x, dv.y, 0}
			if is_surface(p, n) && open(p, node.cell, d) && open(p, n, iso.opposite(d)) {
				add_pair(&p.real, i32(i), node_index(p, n))
			}
		}
	}
	for k := 0; k + 1 < len(p.data.caves); k += 2 {
		a, b := node_index(p, p.data.caves[k].cell), node_index(p, p.data.caves[k + 1].cell)
		if a >= 0 && b >= 0 && !p.nodes[a].stair && !p.nodes[b].stair {
			add_pair(&p.real, a, b)
		}
	}
	graph_build(&p.real, len(p.nodes))
	rebuild_illusions(p)
}

// The cave whose mouth is at surface c, or -1.
cave_at :: proc(p: ^Palace, c: Cell) -> int {
	for cave, i in p.data.caves {
		if cave.cell == c {
			return i
		}
	}
	return -1
}

// Is the step a-b a passage through the rock, from one cave's mouth to the other's?
is_passage :: proc(p: ^Palace, a, b: Cell) -> bool {
	i, j := cave_at(p, a), cave_at(p, b)
	return i >= 0 && j >= 0 && i / 2 == j / 2 && i != j
}

@(private)
add_node :: proc(p: ^Palace, n: Node) {
	p.node_at[cell_index(p, n.cell)] = i32(len(p.nodes))
	append(&p.nodes, n)
}

// Switch to view r (0..3) and recompute its illusions.
set_view :: proc(p: ^Palace, r: int) {
	p.rot = ((r % 4) + 4) % 4
	rebuild_illusions(p)
}

rebuild_illusions :: proc(p: ^Palace) {
	slice.fill(p.view_node, -1)
	slice.zero(p.view_solid)
	for node, i in p.nodes {
		if !node.stair {
			p.view_node[cell_index(p, iso.to_view(node.cell, p.rot, p.size))] = i32(i)
		}
	}
	for s, i in p.solid {
		if s.kind != .None {
			p.view_solid[cell_index(p, iso.to_view(cell_from_index(p, i), p.rot, p.size))] = true
		}
	}

	clear(&p.illusion.pairs)
	back := 4 - p.rot
	for node, a in p.nodes {
		if node.stair {
			continue
		}
		v := iso.to_view(node.cell, p.rot, p.size)
		for d in Dir {
			wd := iso.rot_dir(d, back) // the side of `a` in world terms
			if !open(p, node.cell, wd) || !edge_visible(p, v, d) {
				continue
			}
			dv := iso.DIR_VEC[d]
			for k in i32(-ILLUSION_REACH) ..= ILLUSION_REACH {
				if k == 0 {
					continue
				}
				bv := v + {dv.x + k, dv.y + k, k}
				if !in_grid(p, bv) {
					continue
				}
				b := p.view_node[cell_index(p, bv)]
				if b >= 0 && open(p, p.nodes[b].cell, iso.opposite(wd)) && edge_visible(p, bv, iso.opposite(d)) {
					add_pair(&p.illusion, i32(a), b)
				}
			}
		}
	}
	graph_build(&p.illusion, len(p.nodes))

	for node, i in p.nodes {
		p.stair_seen[i] = node.stair && stairs_visible(p, node)
	}
}

cell_from_index :: proc(p: ^Palace, i: int) -> Cell {
	s := int(p.size)
	return {i32(i % s), i32((i / s) % s), i32(i / (s * s))}
}

@(private)
view_solid_at :: proc(p: ^Palace, v: Cell) -> bool {
	return in_grid(p, v) && p.view_solid[cell_index(p, v)]
}

// The edge on side d (view terms) of the top of the surface at view cell v
// can be seen: no nearer cube covers the whole top, and none covers the half
// of it that holds this edge. A cube beside the diagonal, (1+k, k, k), hides
// the right half of the top (its +x and -y edges); (k, 1+k, k) the left half
// (+y and -x). Two surfaces look joined where their touching edges show, so
// an illusion needs that edge seen on both, not the whole top.
edge_visible :: proc(p: ^Palace, v: Cell, d: Dir) -> bool {
	right := d == .PX || d == .MY
	for k in i32(0) ..< p.size + 4 {
		if k >= 1 && view_solid_at(p, v + {k, k, k - 1}) {
			return false
		}
		if view_solid_at(p, v + {k, k, k}) {
			return false
		}
		if view_solid_at(p, right ? v + {1 + k, k, k} : v + {k, 1 + k, k}) {
			return false
		}
	}
	return true
}

// Every tread of the stairs can be seen: a ray from its centre toward the
// camera (direction (1, 1, 1) in view space) meets no other solid cell.
stairs_visible :: proc(p: ^Palace, node: Node) -> bool {
	own := iso.to_view(node.cell, p.rot, p.size)
	d := iso.DIR_VEC[node.up]
	for i in 0 ..< 4 {
		f := (f32(i) + 0.5) / 4 - 0.5
		w := iso.Vec3{f32(node.cell.x) + 0.5 + f32(d.x) * f, f32(node.cell.y) + 0.5 + f32(d.y) * f, f32(node.cell.z) + f32(i + 1) / 4 + 0.001}
		// walk the cells the ray crosses, one boundary at a time (the
		// direction is the same on every axis: the next boundary is that of
		// the axis with the largest fraction)
		q := iso.view_point(w, f32(p.rot), p.size) + 0.02
		c := Cell{i32(q.x), i32(q.y), i32(q.z)} // q is never negative here
		frac := q - {f32(c.x), f32(c.y), f32(c.z)}
		for in_grid(p, c) {
			if c != own && view_solid_at(p, c) {
				return false
			}
			frac += 1 - max(frac.x, frac.y, frac.z)
			for k in 0 ..< 3 {
				if frac[k] >= 1 - 1e-5 {
					frac[k] = 0
					c[k] += 1
				}
			}
		}
	}
	return true
}

// Can Psyche step along the edge a-b? Real edges always work in the light;
// in the dark, stairs must be visible.
step_allowed :: proc(p: ^Palace, a, b: i32, dark: bool) -> bool {
	if !dark {
		return true
	}
	for n in ([2]i32{a, b}) {
		if p.nodes[n].stair && !p.stair_seen[n] {
			return false
		}
	}
	return true
}

// --- graph storage -------------------------------------------------------------

@(private)
add_pair :: proc(g: ^Graph, a, b: i32) {
	if a == b {
		return
	}
	append(&g.pairs, [2]i32{min(a, b), max(a, b)})
}

@(private)
graph_build :: proc(g: ^Graph, node_count: int) {
	slice.sort_by(g.pairs[:], proc(x, y: [2]i32) -> bool {
		return x[0] < y[0] || (x[0] == y[0] && x[1] < y[1])
	})
	unique := 0
	for e, i in g.pairs {
		if i == 0 || e != g.pairs[unique - 1] {
			g.pairs[unique] = e
			unique += 1
		}
	}
	resize(&g.pairs, unique)

	resize(&g.start, node_count + 1)
	slice.zero(g.start[:])
	for e in g.pairs {
		g.start[e[0] + 1] += 1
		g.start[e[1] + 1] += 1
	}
	for i in 1 ..< len(g.start) {
		g.start[i] += g.start[i - 1]
	}
	resize(&g.list, 2 * unique)
	cursor := make([]i32, node_count, context.temp_allocator)
	copy(cursor, g.start[:node_count])
	for e in g.pairs {
		g.list[cursor[e[0]]] = e[1]
		cursor[e[0]] += 1
		g.list[cursor[e[1]]] = e[0]
		cursor[e[1]] += 1
	}
}

neighbours :: proc(g: ^Graph, n: i32) -> []i32 {
	if int(n) + 1 >= len(g.start) {
		return nil
	}
	return g.list[g.start[n]:g.start[n + 1]]
}

is_real_edge :: proc(p: ^Palace, a, b: Cell) -> bool {
	ia, ib := node_index(p, a), node_index(p, b)
	if ia < 0 || ib < 0 {
		return false
	}
	return slice.contains(neighbours(&p.real, ia), ib)
}

// Does Psyche stand on a crumbling block at node n?
on_crumble :: proc(p: ^Palace, n: i32) -> bool {
	if p.nodes[n].stair {
		return false
	}
	b := support(p, p.nodes[n].cell)
	return b >= 0 && p.data.blocks[b].trait == .Crumble
}

is_illusion :: proc(p: ^Palace, a, b: Cell) -> bool {
	ia, ib := node_index(p, a), node_index(p, b)
	if ia < 0 || ib < 0 {
		return false
	}
	return slice.contains(neighbours(&p.illusion, ia), ib)
}

// --- search --------------------------------------------------------------------

// Breadth-first path from `from` to `to` (excluding `from`) into `out`; it
// never goes through a cave (that is entered on purpose).
// Returns false (and an empty path) when unreachable. A path that crosses no
// crumbling block on the way is preferred: those fall behind her, so she
// crosses them only when there is no other way.
find_path :: proc(p: ^Palace, from, to: Cell, dark: bool, out: ^Path) -> bool {
	return search_path(p, from, to, dark, out, true) || search_path(p, from, to, dark, out, false)
}

@(private)
search_path :: proc(p: ^Palace, from, to: Cell, dark: bool, out: ^Path, careful: bool) -> bool {
	sa.clear(out)
	start, goal := node_index(p, from), node_index(p, to)
	if start < 0 || goal < 0 || start == goal {
		return false
	}
	n := len(p.nodes)
	parent := make([]i32, n, context.temp_allocator)
	slice.fill(parent, -1)
	queue := make([]i32, n, context.temp_allocator)
	head, tail := 0, 0
	parent[start] = start
	queue[tail] = start
	tail += 1
	search: for head < tail {
		cur := queue[head]
		head += 1
		for g in ([]^Graph{&p.real, &p.illusion}) {
			if g == &p.illusion && !dark {
				break
			}
			for nb in neighbours(g, cur) {
				if parent[nb] < 0 && step_allowed(p, cur, nb, dark) {
					if careful && nb != goal && on_crumble(p, nb) {
						continue
					}
					if is_passage(p, p.nodes[cur].cell, p.nodes[nb].cell) {
						continue // only on purpose: game.enter_cave
					}
					parent[nb] = cur
					if nb == goal {
						break search
					}
					queue[tail] = nb
					tail += 1
				}
			}
		}
	}
	if parent[goal] < 0 {
		return false
	}
	length := 0
	for s := goal; s != start; s = parent[s] {
		length += 1
	}
	if length > MAX_PATH {
		return false
	}
	sa.resize(out, length)
	i := length - 1
	for s := goal; s != start; s = parent[s] {
		sa.set(out, i, p.nodes[s].cell)
		i -= 1
	}
	return true
}

// Mark every node reachable from `from` (out has one entry per node).
// Returns how many nodes are reachable.
reachable :: proc(p: ^Palace, from: Cell, dark: bool, out: []bool) -> int {
	slice.zero(out)
	start := node_index(p, from)
	if start < 0 {
		return 0
	}
	out[start] = true
	flood(p, out, dark, -1)
	return slice.count(out, true)
}

// Grow the marked set with every node reachable from it in the current view;
// node `avoid` is never entered. Returns true if anything was added.
@(private)
flood :: proc(p: ^Palace, out: []bool, dark: bool, avoid: i32) -> (grew: bool) {
	queue := make([dynamic]i32, 0, len(p.nodes), context.temp_allocator)
	for ok, i in out {
		if ok {
			append(&queue, i32(i))
		}
	}
	for head := 0; head < len(queue); head += 1 {
		cur := queue[head]
		for g in ([]^Graph{&p.real, &p.illusion}) {
			if g == &p.illusion && !dark {
				break
			}
			for nb in neighbours(g, cur) {
				if !out[nb] && nb != avoid && step_allowed(p, cur, nb, dark) {
					out[nb] = true
					grew = true
					append(&queue, nb)
				}
			}
		}
	}
	return
}

// --- level analysis (level_check, tests) ------------------------------------------

// Mark every node reachable from `from` in the dark when Psyche may turn the
// palace freely: turning is free while standing still, so the illusions of
// the four views add up. Cell `avoid`, if any, is never entered. The palace
// is left in the view it was in.
reachable_turning :: proc(p: ^Palace, from: Cell, out: []bool, avoid: Maybe(Cell) = nil) -> int {
	slice.zero(out)
	start := node_index(p, from)
	if start < 0 {
		return 0
	}
	skip: i32 = -1
	if c, ok := avoid.?; ok {
		skip = node_index(p, c)
	}
	view := p.rot
	out[start] = true
	for grew := true; grew; {
		grew = false
		for r in 0 ..< 4 {
			set_view(p, r)
			grew ||= flood(p, out, true, skip)
		}
	}
	set_view(p, view)
	return slice.count(out, true)
}

// What can be reached from the start, in the light or in the dark turning freely.
Goals :: struct {
	sigil, amore, exit: bool,
	fragment:           [level.MAX_FRAGMENTS]bool,
}

reach_goals :: proc(p: ^Palace, avoid: Maybe(Cell) = nil) -> (goals: Goals) {
	d := p.data
	dark := make([]bool, len(p.nodes), context.temp_allocator)
	light := make([]bool, len(p.nodes), context.temp_allocator)
	reachable_turning(p, d.start, dark, avoid)
	if d.has_lamp {
		slice.zero(light)
		if s := node_index(p, d.start); s >= 0 {
			light[s] = true
			skip: i32 = -1
			if c, ok := avoid.?; ok {
				skip = node_index(p, c)
			}
			flood(p, light, false, skip)
		}
	}
	at :: proc(p: ^Palace, dark, light: []bool, c: Cell) -> bool {
		i := node_index(p, c)
		return i >= 0 && (dark[i] || light[i])
	}
	goals.sigil = d.has_sigil && at(p, dark, light, d.sigil)
	goals.exit = d.has_exit && at(p, dark, light, d.exit)
	for c, i in d.fragments {
		goals.fragment[i] = at(p, dark, light, c)
	}
	if d.has_amore {
		for v in iso.DIR_VEC {
			goals.amore ||= at(p, dark, light, d.amore + {v.x, v.y, 0})
		}
	}
	return
}

// Fragment i of the tale must be reachable and never required: blocking its
// cell must not cut the way to any goal, before or after the seal (for a
// palace that changes, the solver checks it).
// The palace is left with its blocks lowered.
check_fragment :: proc(p: ^Palace, i: int) -> (reachable, optional: bool) {
	if is_dynamic(p.data) {
		// the palace changes as she goes: only a full search can tell
		return check_dynamic_fragment(p, i, context.temp_allocator)
	}
	optional = true
	for risen in ([2]bool{false, true}) {
		if risen && len(p.data.rise) == 0 {
			break
		}
		p.risen = risen
		rebuild_graph(p)
		all := reach_goals(p)
		without := reach_goals(p, p.data.fragments[i])
		reachable ||= all.fragment[i]
		lost := (all.sigil && !without.sigil) || (all.amore && !without.amore) || (all.exit && !without.exit)
		optional &&= !lost
	}
	p.risen = false
	rebuild_graph(p)
	return
}

// --- geometry ------------------------------------------------------------------

// Where feet stand on node n, in world space.
node_world :: proc(p: ^Palace, c: Cell) -> iso.Vec3 {
	lift: f32 = is_stair(p, c) ? 0.5 : 0
	return {f32(c.x) + 0.5, f32(c.y) + 0.5, f32(c.z) + lift}
}

// Where a figure stands on a node: on stairs, on the middle tread (the node
// itself is half way up, inside the steps).
stand_world :: proc(p: ^Palace, c: Cell) -> iso.Vec3 {
	w := node_world(p, c)
	if is_stair(p, c) {
		w.z = stair_ground(p, c, w)
	}
	return w
}

// The ground under world point w on or beside the stairs at cell s: the tread
// under the feet, rising a little before each riser, so a figure walking the
// stairs climbs them step by step instead of cutting through them. Beyond the
// low end it is the lower floor, beyond the high end the upper one.
stair_ground :: proc(p: ^Palace, s: Cell, w: iso.Vec3) -> f32 {
	STEPS :: 4
	local := w.xy - {f32(s.x), f32(s.y)}
	f: f32
	switch solid_at(p, s).dir {
	case .PX: f = local.x
	case .MX: f = 1 - local.x
	case .PY: f = local.y
	case .MY: f = 1 - local.y
	}
	g := clamp(f * STEPS, -1, STEPS - 0.001)
	k := math.floor(g)
	lift := clamp((g - k - 0.7) / 0.3, 0, 1)
	lift = lift * lift * (3 - 2 * lift)
	return f32(s.z) + clamp((k + 1 + lift) / STEPS, 0, 1)
}

// Node position in proto pixels for the view angle.
node_screen :: proc(p: ^Palace, c: Cell, angle: f32) -> iso.Vec2 {
	return iso.project(iso.view_point(node_world(p, c), angle, p.size))
}

// The frontmost walkable node under a point given in proto pixels.
pick :: proc(p: ^Palace, point: iso.Vec2, angle: f32) -> (cell: Cell, ok: bool) {
	best_depth: f32 = -1e30
	for node in p.nodes {
		v := iso.view_point(node_world(p, node.cell), angle, p.size)
		pos := iso.project(v)
		on_top := iso.in_diamond(point, pos)
		if on_top || iso.in_diamond(point, pos + {0, iso.WALL * 0.5}, 0.8) {
			d := v.x + v.y - 1 + v.z + (on_top ? 0.5 : 0)
			if d > best_depth {
				best_depth = d
				cell, ok = node.cell, true
			}
		}
	}
	return
}
