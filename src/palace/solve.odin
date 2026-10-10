// A solver for levels whose palace changes (Act II on): it plays every move
// Psyche can make, one at a time, exactly as the game does: a step along a
// real edge (or, in the dark, an illusion of the current view, with the
// hidden-stairs rule), a turn of the view, lighting or putting out the lamp,
// a handle, the ants called beside a seed (it goes to the hollow its way in
// this view leads to). The lamp's light makes veiled blocks real within its
// reach; the lamp lit on a seal raises its `rise` blocks. A step onto a reed
// turns the time (by day the sun shows the truth and the rams stand in the
// way; at evening the illusions are back and the rams lie down, steps).
// A state is her cell, the view, the lamp and the palace's configuration
// (which blocks changed, how each part is turned, where each seed is). The search is a cheapest
// path (steps cost least; turns, lightings and handles more, so the plan it
// prints is the one with the fewest decisions; whatever is done in the light
// costs a little more, as the oil it burns, so the plan puts the lamp out when
// it can). Oil is not counted in the state: `oil_left` replays a plan.
//
// Memory: everything comes from the allocator given to `solve` (an arena).
package palace

import "core:slice"
import sa "core:container/small_array"

import "../iso"
import "../level"

Config :: struct {
	flips: u64, // bit k: the k-th changing block has changed
	rots:  u32, // 2 bits per part
	seeds: u16, // 3 bits per seed: 0 where it lay, k + 1 in hollow k
	risen: level.Seals, // the seals that have been lit
	day:   bool, // the sun is up (a level with reeds)
}

@(private = "file")
Search_State :: struct {
	cfg:  Config,
	cell: Cell,
	view: u8,
	lamp: bool,
}

Move :: enum u8 {
	Start,
	Step,
	Turn_Left,
	Turn_Right,
	Light,
	Douse,
	Handle,
	Ants,
}

COST := [Move]int {
	.Start      = 0,
	.Step       = 2,
	.Turn_Left  = 4,
	.Turn_Right = 4,
	.Light      = 8,
	.Douse      = 2,
	.Handle     = 6,
	.Ants       = 6,
}

// What a move costs more when the lamp burns through it (about a unit per
// 0.3 s of oil): a step, a passage through a cave, a turn, a handle.
LIT_COST := [Move]int {
	.Start      = 0,
	.Step       = 1,
	.Turn_Left  = 2,
	.Turn_Right = 2,
	.Light      = 0,
	.Douse      = 0,
	.Handle     = 3,
	.Ants       = 6,
}
LIT_PASSAGE_COST :: 8

Plan_Step :: struct {
	move:     Move,
	cell:     Cell, // where Psyche is after the move
	view:     int,
	illusion: bool, // a step across an illusion
	time:     bool, // a step onto a reed: the time turned
	changed:  int, // blocks that changed with this move
	carry:    int, // the ants: cells the seed was carried over
	hollow:   int, // the ants: the hollow it dropped into
}

Solution :: struct {
	solved:      bool,
	plan:        [dynamic]Plan_Step,
	steps:       int,
	light_steps: int,
	turns:       int,
	lightings:   int,
	handles:     int,
	ants:        int,
	times:       int, // the time turned (steps onto a reed)
	states:      int, // states reached from the start
	dead:        int, // ...of which cannot reach the goal any more (R restarts)
}

// The palace in one configuration, in every view.
@(private = "file")
Config_Graph :: struct {
	nodes:      []Node,
	index:      map[Cell]i32,
	real_start: []i32,
	real_list:  []i32,
	ill_start:  [4][]i32, // per view, filled when first needed (`view_of`)
	ill_list:   [4][]i32,
	stair_seen: [4][]bool,
	views:      bit_set[0 ..< 4],
}

@(private = "file")
Ants_Key :: struct {
	cfg:  Config,
	cell: Cell,
	view: u8,
	lamp: bool,
}

@(private = "file")
Ants_Result :: struct {
	cfg:          Config,
	carry, hollow: int,
	ok:           bool,
}

@(private = "file")
Solver :: struct {
	p:       ^Palace,
	changing: [dynamic]int, // block index of each changing block (bit order)
	cache:   map[Config]^Config_Graph,
	ants:    map[Ants_Key]Ants_Result,
}

@(private = "file")
configure :: proc(s: ^Solver, cfg: Config) {
	p := s.p
	for b, k in s.changing {
		p.flipped[b] = cfg.flips & (1 << u64(k)) != 0
	}
	for n in 0 ..< len(p.data.parts) {
		p.part_rot[n] = int((cfg.rots >> (2 * u32(n))) & 3)
	}
	for i in 0 ..< len(p.data.seeds) {
		p.seed_at[i] = i8((cfg.seeds >> (3 * u16(i))) & 7) - 1
	}
	p.seed_lifted = -1
	p.risen = cfg.risen
	p.day = cfg.day
	rebuild_real(p)
}

// The ants called by Psyche at `cell` in configuration cfg, view `view`: the
// seed beside her carried to its hollow (the new configuration), if there is
// a way.
@(private = "file")
call_ants :: proc(s: ^Solver, cfg: Config, cell: Cell, view: u8, lamp: bool) -> Ants_Result {
	// most places have no seed beside them: said without touching the palace
	near := false
	for c, i in s.p.data.seeds {
		lying := (cfg.seeds >> (3 * u16(i))) & 7 == 0
		near ||= lying && c.z == cell.z && abs(c.x - cell.x) + abs(c.y - cell.y) == 1
	}
	if !near {
		return {}
	}
	dark := !lamp && !cfg.day
	key := Ants_Key{cfg, cell, dark ? view : 0, dark} // in the light every view is the same
	if r, ok := s.ants[key]; ok {
		return r
	}
	p := s.p
	configure(s, cfg)
	set_view(p, int(view))
	r: Ants_Result
	if i := seed_beside(p, cell); i >= 0 {
		path: Path
		if k := seed_route(p, i, cell, dark, &path); k >= 0 {
			r.ok, r.hollow, r.carry = true, k, sa.len(path)
			r.cfg = cfg
			r.cfg.seeds = (cfg.seeds & ~(7 << (3 * u16(i)))) | (u16(k + 1) << (3 * u16(i)))
		}
	}
	s.ants[key] = r
	return r
}

@(private = "file")
graph_of :: proc(s: ^Solver, cfg: Config) -> ^Config_Graph {
	if g, ok := s.cache[cfg]; ok {
		return g
	}
	p := s.p
	configure(s, cfg)
	g := new(Config_Graph)
	g.nodes = slice.clone(p.nodes[:])
	g.index = make(map[Cell]i32, len(p.nodes))
	for n, i in p.nodes {
		g.index[n.cell] = i32(i)
	}
	g.real_start = slice.clone(p.real.start[:])
	g.real_list = slice.clone(p.real.list[:])
	s.cache[cfg] = g
	return g
}

// The illusions and the stairs seen of view r in configuration cfg (in the
// dark only: by day and in the lamp's light they are never asked for).
@(private = "file")
view_of :: proc(s: ^Solver, cfg: Config, g: ^Config_Graph, r: int) {
	if r in g.views {
		return
	}
	p := s.p
	configure(s, cfg)
	set_view(p, r)
	g.ill_start[r] = slice.clone(p.illusion.start[:])
	g.ill_list[r] = slice.clone(p.illusion.list[:])
	g.stair_seen[r] = slice.clone(p.stair_seen[:len(p.nodes)])
	g.views += {r}
}

@(private = "file")
Entry :: struct {
	state:    Search_State,
	parent:   i32,
	move:     Move,
	illusion: bool,
	changed:  int,
	carry:    int,
	hollow:   int,
	cost:     int,
	done:     bool,
}

@(private = "file")
Edge :: struct {
	from, to: i32,
}

// Search from the start to `goal`; `avoid` is never entered (to prove the
// fragment optional). The palace is left as loaded (nothing changed, view 0).
solve :: proc(p: ^Palace, goal: Cell, avoid: Maybe(Cell) = nil, allocator := context.allocator) -> (sol: Solution) {
	context.allocator = allocator
	s := Solver{p = p}
	s.cache = make(map[Config]^Config_Graph)
	s.ants = make(map[Ants_Key]Ants_Result)
	for e, i in p.data.blocks {
		if e.trait != .Stone {
			append(&s.changing, i)
		}
	}
	avoid_cell, has_avoid := avoid.?
	saved_view := p.rot

	entries := make([dynamic]Entry, 0, 4096)
	seen := make(map[Search_State]i32)
	edges := make([dynamic]Edge, 0, 16384)
	buckets := make([dynamic][dynamic]i32, 0, 256)

	push :: proc(entries: ^[dynamic]Entry, seen: ^map[Search_State]i32, buckets: ^[dynamic][dynamic]i32, edges: ^[dynamic]Edge, e: Entry) {
		if e.parent >= 0 {
			if id, ok := seen[e.state]; ok {
				append(edges, Edge{e.parent, id})
				if entries[id].done || entries[id].cost <= e.cost {
					return
				}
				entries[id].parent, entries[id].move, entries[id].cost = e.parent, e.move, e.cost
				entries[id].illusion, entries[id].changed = e.illusion, e.changed
				entries[id].carry, entries[id].hollow = e.carry, e.hollow
				for len(buckets) <= e.cost {
					append(buckets, make([dynamic]i32, 0, 64))
				}
				append(&buckets[e.cost], id)
				return
			}
		}
		id := i32(len(entries))
		append(entries, e)
		seen[e.state] = id
		if e.parent >= 0 {
			append(edges, Edge{e.parent, id})
		}
		for len(buckets) <= e.cost {
			append(buckets, make([dynamic]i32, 0, 64))
		}
		append(&buckets[e.cost], id)
	}

	start_cfg := Config{day = len(p.data.reeds) > 0}
	push(&entries, &seen, &buckets, &edges, Entry{state = {start_cfg, p.data.start, 0, false}, parent = -1, move = .Start})
	goal_id: i32 = -1
	for cost := 0; cost < len(buckets); cost += 1 {
		for k := 0; k < len(buckets[cost]); k += 1 {
			id := buckets[cost][k]
			if entries[id].done || entries[id].cost != cost {
				continue
			}
			entries[id].done = true
			st := entries[id].state
			if st.cell == goal && goal_id < 0 {
				goal_id = id
			}
			g := graph_of(&s, st.cfg)
			a, ok := g.index[st.cell]
			if !ok {
				continue
			}
			next :: proc(entries: ^[dynamic]Entry, seen: ^map[Search_State]i32, buckets: ^[dynamic][dynamic]i32, edges: ^[dynamic]Edge, from: i32, st: Search_State, move: Move, illusion := false, changed := 0, lit_extra := -1, carry := 0, hollow := -1) {
				e := Entry{state = st, parent = from, move = move, illusion = illusion, changed = changed, carry = carry, hollow = hollow}
				e.cost = entries[from].cost + COST[move]
				if entries[from].state.lamp && st.lamp {
					e.cost += lit_extra >= 0 ? lit_extra : LIT_COST[move]
				}
				push(entries, seen, buckets, edges, e)
			}

			// turning the view
			left, right := st, st
			left.view = (st.view + 3) % 4
			right.view = (st.view + 1) % 4
			next(&entries, &seen, &buckets, &edges, id, left, .Turn_Left)
			next(&entries, &seen, &buckets, &edges, id, right, .Turn_Right)

			// the lamp
			if p.data.has_lamp {
				if st.lamp {
					off := st
					off.lamp = false
					next(&entries, &seen, &buckets, &edges, id, off, .Douse)
				} else {
					on := st
					on.lamp = true
					cfg, changed := touch(&s, st.cfg, st.cell)
					cfg, changed = seal(p, cfg, st.cell, changed)
					on.cfg = cfg
					if _, still := graph_of(&s, cfg).index[st.cell]; still {
						next(&entries, &seen, &buckets, &edges, id, on, .Light, false, changed)
					}
				}
			}

			// a handle
			if h := handle_at_cell(p, st.cell); h >= 0 {
				turned := st
				part := p.data.handles[h].part
				r := (st.cfg.rots >> (2 * u32(part))) & 3
				turned.cfg.rots = (st.cfg.rots & ~(3 << (2 * u32(part)))) | (((r + 1) & 3) << (2 * u32(part)))
				if _, still := graph_of(&s, turned.cfg).index[st.cell]; still {
					next(&entries, &seen, &buckets, &edges, id, turned, .Handle)
				}
			}

			// the ants, beside a seed
			if len(p.data.seeds) > 0 {
				if r := call_ants(&s, st.cfg, st.cell, st.view, st.lamp); r.ok {
					carried := st
					carried.cfg = r.cfg
					if _, still := graph_of(&s, r.cfg).index[st.cell]; still {
						next(&entries, &seen, &buckets, &edges, id, carried, .Ants, false, 1, -1, r.carry, r.hollow)
					}
				}
			}

			// steps
			dark := !st.lamp && !st.cfg.day
			if dark {
				view_of(&s, st.cfg, g, int(st.view))
			}
			for pass in 0 ..< 2 {
				if pass == 1 && !dark {
					break
				}
				start, list := g.real_start, g.real_list
				if pass == 1 {
					start, list = g.ill_start[st.view], g.ill_list[st.view]
				}
				if int(a) + 1 >= len(start) {
					continue
				}
				for b in list[start[a]:start[a + 1]] {
					if dark && ((g.nodes[a].stair && !g.stair_seen[st.view][a]) || (g.nodes[b].stair && !g.stair_seen[st.view][b])) {
						continue
					}
					to := g.nodes[b].cell
					if has_avoid && to == avoid_cell {
						continue
					}
					moved := st
					moved.cell = to
					changed := 0
					if st.lamp {
						n := 0
						moved.cfg, n = touch(&s, moved.cfg, to)
						moved.cfg, changed = seal(p, moved.cfg, to, changed + n)
					}
					if reed_at(p, to) >= 0 {
						moved.cfg.day = !moved.cfg.day // a reed turns the time
					}
					if _, still := graph_of(&s, moved.cfg).index[to]; still {
						extra := is_passage(p, g.nodes[a].cell, to) ? LIT_PASSAGE_COST : -1
						next(&entries, &seen, &buckets, &edges, id, moved, .Step, pass == 1, changed, extra)
					}
				}
			}
		}
	}

	sol.states = len(entries)
	// states that can still reach the goal: backwards from every goal state
	alive := make([]bool, len(entries))
	back_start := make([]i32, len(entries) + 1)
	for e in edges {
		back_start[e.to + 1] += 1
	}
	for i in 1 ..< len(back_start) {
		back_start[i] += back_start[i - 1]
	}
	back := make([]i32, len(edges))
	cursor := slice.clone(back_start[:len(entries)])
	for e in edges {
		back[cursor[e.to]] = e.from
		cursor[e.to] += 1
	}
	queue := make([dynamic]i32, 0, len(entries))
	for e, i in entries {
		if e.state.cell == goal {
			alive[i] = true
			append(&queue, i32(i))
		}
	}
	for head := 0; head < len(queue); head += 1 {
		cur := queue[head]
		for from in back[back_start[cur]:back_start[cur + 1]] {
			if !alive[from] {
				alive[from] = true
				append(&queue, from)
			}
		}
	}
	sol.dead = slice.count(alive, false)

	if goal_id >= 0 {
		sol.solved = true
		chain := make([dynamic]i32, 0, 128)
		for id := goal_id; id >= 0; id = entries[id].parent {
			append(&chain, id)
		}
		slice.reverse(chain[:])
		for id in chain[1:] {
			e := entries[id]
			turned := e.move == .Step && e.state.cfg.day != entries[e.parent].state.cfg.day
			append(&sol.plan, Plan_Step{e.move, e.state.cell, int(e.state.view), e.illusion, turned, e.changed, e.carry, e.hollow})
			#partial switch e.move {
			case .Step:
				sol.steps += 1
				sol.times += int(turned)
				sol.light_steps += int(e.state.lamp)
			case .Turn_Left, .Turn_Right:
				sol.turns += 1
			case .Light:
				sol.lightings += 1
			case .Handle:
				sol.handles += 1
			case .Ants:
				sol.ants += 1
			}
		}
	}

	// leave the palace as loaded
	configure(&s, start_cfg)
	set_view(p, saved_view) // (the view's illusions too)
	return
}

@(private = "file")
handle_at_cell :: proc(p: ^Palace, c: Cell) -> int {
	return handle_at(p, c)
}

// The lamp's light at `feet` in configuration cfg: the new configuration and
// how many blocks changed.
@(private = "file")
touch :: proc(s: ^Solver, cfg: Config, feet: Cell) -> (out: Config, changed: int) {
	out = cfg
	d := s.p.data
	for b, k in s.changing {
		e := d.blocks[b]
		if e.trait != .Veiled || cfg.flips & (1 << u64(k)) != 0 {
			continue
		}
		c := e.cell
		if e.part != 0 {
			c = level.part_cell(c, d.parts[e.part - 1].pivot, int((cfg.rots >> (2 * u32(e.part - 1))) & 3))
		}
		if !in_truth(feet, c) || c == feet || c == feet - {0, 0, 1} {
			continue
		}
		out.flips |= 1 << u64(k)
		changed += 1
	}
	return
}

// The lamp lit on a seal raises its `rise` blocks for good.
@(private = "file")
seal :: proc(p: ^Palace, cfg: Config, feet: Cell, changed: int) -> (Config, int) {
	for c, k in p.data.sigils {
		if c != feet || k in cfg.risen {
			continue
		}
		out := cfg
		out.risen += {k}
		n := changed
		for e in p.data.rise {
			n += int(int(e.seal) == k)
		}
		return out, n
	}
	return cfg, changed
}

// Where the level is won: its exit, or a surface beside Cupid (the lamp is lit there).
goal_cell :: proc(p: ^Palace) -> Cell {
	d := p.data
	if d.has_exit || !d.has_amore {
		return d.exit
	}
	for v in iso.DIR_VEC {
		if c := d.amore + {v.x, v.y, 0}; is_surface(p, c) {
			return c
		}
	}
	return d.exit
}

// Is the level's goal (the exit) reachable? For levels whose palace changes.
check_dynamic :: proc(p: ^Palace, allocator := context.allocator) -> (solvable: bool) {
	d := p.data
	return d.has_exit && solve(p, d.exit, nil, allocator).solved
}

// Is fragment i reachable, and the exit reachable without it?
check_dynamic_fragment :: proc(p: ^Palace, i: int, allocator := context.allocator) -> (reachable, optional: bool) {
	d := p.data
	if !d.has_exit {
		return
	}
	c := d.fragments[i]
	return solve(p, c, d.exit, allocator).solved, solve(p, d.exit, c, allocator).solved
}

// Does the level have blocks that change or parts that turn?
is_dynamic :: proc(d: ^level.Level_Data) -> bool {
	if len(d.parts) > 0 || len(d.seeds) > 0 || len(d.reeds) > 0 {
		return true
	}
	if d.has_sigil && len(d.rise) > 0 && !d.has_amore {
		return true // the seal changes the palace on the way to the exit
	}
	for e in d.blocks {
		if e.trait != .Stone {
			return true
		}
	}
	return false
}

// How long things take in the game, for `oil_left` (the game's constants).
Oil_Rules :: struct {
	oil:        f32, // the lamp full (seconds)
	light_cost: f32, // lighting it
	step:       f32, // a step
	passage:    f32, // a step through a cave
	turn:       f32, // a turn of the view
	handle:     f32, // a part turning
	ants:       f32, // the ants gather, set the seed down...
	carry:      f32, // ...and carry it this long per cell
	rise_delay: f32, // a seal's stones come up one after the other...
	rise_time:  f32, // ...each taking this long
}

// Replay a plan counting the oil: the least left at any time (below zero: the
// lamp would go out before the plan is done).
oil_left :: proc(p: ^Palace, plan: []Plan_Step, rules: Oil_Rules) -> (least: f32) {
	d := p.data
	oil := rules.oil
	least = oil
	lamp := false
	risen: level.Seals
	at := d.start
	for st in plan {
		spent: f32
		switch st.move {
		case .Start:
		case .Light:
			lamp = true
			oil -= rules.light_cost
		case .Douse:
			lamp = false
		case .Turn_Left, .Turn_Right:
			spent = rules.turn
		case .Handle:
			spent = rules.handle
		case .Ants:
			spent = rules.ants + rules.carry * f32(st.carry)
		case .Step:
			spent = is_passage(p, at, st.cell) ? rules.passage : rules.step
		}
		at = st.cell
		if lamp {
			oil -= spent
			for c, k in d.sigils {
				if c == at && k not_in risen {
					// the stones rise while she waits, the lamp burning
					risen += {k}
					n := 0
					for e in d.rise {
						n += int(int(e.seal) == k)
					}
					oil -= f32(max(n - 1, 0)) * rules.rise_delay + rules.rise_time
				}
			}
		}
		least = min(least, oil)
	}
	return
}
