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
//
// Memory: every array is allocated once from the allocator given to `init`
// (the level arena) and reused; rebuilding the graph or the illusions does not
// allocate again once the arrays have grown. Scratch work uses the temp allocator.
package palace

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
	// world grid, indexed by cell_index
	solid:      []level.Solid,
	blocked:    []bool,
	fences:     []iso.Dirs,
	node_at:    []i32,
	// view grid (same shape), for the current view
	view_node:  []i32,
	view_solid: []bool,
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
	p.view_node = make([]i32, n)
	p.view_solid = make([]bool, n)
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

rebuild_graph :: proc(p: ^Palace) {
	slice.zero(p.solid)
	slice.zero(p.blocked)
	slice.zero(p.fences)
	slice.fill(p.node_at, -1)
	for e in p.data.blocks {
		p.solid[cell_index(p, e.cell)] = e.solid
	}
	if p.risen {
		for e in p.data.rise {
			p.solid[cell_index(p, e.cell)] = e.solid
		}
	}
	for prop in p.data.props {
		i := cell_index(p, prop.cell)
		if prop.kind in level.BLOCKING_PROPS {
			p.blocked[i] = true
		}
		if prop.kind in level.EDGE_PROPS {
			p.fences[i] += {prop.dir}
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
	graph_build(&p.real, len(p.nodes))
	rebuild_illusions(p)
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
		if !visible(p, v) {
			continue
		}
		for d in Dir {
			wd := iso.rot_dir(d, back) // the side of `a` in world terms
			if !open(p, node.cell, wd) {
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
				if b >= 0 && open(p, p.nodes[b].cell, iso.opposite(wd)) && visible(p, bv) {
					add_pair(&p.illusion, i32(a), b)
				}
			}
		}
	}
	graph_build(&p.illusion, len(p.nodes))
}

cell_from_index :: proc(p: ^Palace, i: int) -> Cell {
	s := int(p.size)
	return {i32(i % s), i32((i / s) % s), i32(i / (s * s))}
}

@(private)
view_solid_at :: proc(p: ^Palace, v: Cell) -> bool {
	return in_grid(p, v) && p.view_solid[cell_index(p, v)]
}

// The top of the surface at view cell v is visible when no nearer cube covers it.
visible :: proc(p: ^Palace, v: Cell) -> bool {
	for k in i32(0) ..< p.size + 4 {
		if k >= 1 && view_solid_at(p, v + {k, k, k - 1}) {
			return false
		}
		if view_solid_at(p, v + {k, k, k}) || view_solid_at(p, v + {1 + k, k, k}) || view_solid_at(p, v + {k, 1 + k, k}) {
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

is_illusion :: proc(p: ^Palace, a, b: Cell) -> bool {
	ia, ib := node_index(p, a), node_index(p, b)
	if ia < 0 || ib < 0 {
		return false
	}
	return slice.contains(neighbours(&p.illusion, ia), ib)
}

// --- search --------------------------------------------------------------------

// Breadth-first path from `from` to `to` (excluding `from`) into `out`.
// Returns false (and an empty path) when unreachable.
find_path :: proc(p: ^Palace, from, to: Cell, dark: bool, out: ^Path) -> bool {
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
				if parent[nb] < 0 {
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
	queue := make([]i32, len(p.nodes), context.temp_allocator)
	head, tail := 0, 1
	queue[0] = start
	out[start] = true
	for head < tail {
		cur := queue[head]
		head += 1
		for g in ([]^Graph{&p.real, &p.illusion}) {
			if g == &p.illusion && !dark {
				break
			}
			for nb in neighbours(g, cur) {
				if !out[nb] {
					out[nb] = true
					queue[tail] = nb
					tail += 1
				}
			}
		}
	}
	return tail
}

// --- geometry ------------------------------------------------------------------

// Where feet stand on node n, in world space.
node_world :: proc(p: ^Palace, c: Cell) -> iso.Vec3 {
	lift: f32 = is_stair(p, c) ? 0.5 : 0
	return {f32(c.x) + 0.5, f32(c.y) + 0.5, f32(c.z) + lift}
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
