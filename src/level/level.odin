// Level files (assets/levels/*.txt): a plain list of commands, one per line.
// The format is documented at the top of assets/levels/level_04.txt.
package level

import "core:fmt"
import "core:strconv"
import "core:strings"

import "../i18n"
import "../iso"

Cell :: iso.Cell
Dir :: iso.Dir

Solid_Kind :: enum u8 {
	None,
	Block,
	Stairs,
}

// What fills a grid cell. Stairs rise toward `dir`.
Solid :: struct {
	kind: Solid_Kind,
	dir:  Dir,
}

// The mechanic a level introduces: a card presents it when the level begins.
Mechanic :: enum u8 {
	None,
	Crumble,
	Phantom,
	Veiled,
	Handle,
}

MECHANIC_NAME := [Mechanic]string {
	.None    = "none",
	.Crumble = "crumble",
	.Phantom = "phantom",
	.Veiled  = "veiled",
	.Handle  = "handle",
}

// Where a level takes place: the sky, the backdrop, the light on the stones.
Setting :: enum u8 {
	Night, // the palace of voices under the moon (the default)
	Crag_Sunset, // a mountain crag above a sea of clouds, the sun going down
	Dusk, // the palace of voices at twilight: the last light, its candles lit
	Night_Candles, // the palace of voices by night, its candles lit
	Deep_Night, // the dead of night: candles out, clouds drifting across the moon
	Forest_Night, // the dead of night in a forest of rock pillars, far from the palace
	River_Dawn, // the first light over a wide river, mist on the water, the morning star
	Crag_Day, // a crag of bare rock by day, the wind, the plain far below
}

SETTING_NAME := [Setting]string {
	.Night       = "night",
	.Crag_Sunset = "crag_sunset",
	.Dusk        = "dusk",
	.Night_Candles = "night_candles",
	.Deep_Night  = "deep_night",
	.Forest_Night = "forest_night",
	.River_Dawn   = "river_dawn",
	.Crag_Day     = "crag_day",
}

// How a block behaves (Act II): fixed stone, or one that changes for good.
Trait :: enum u8 {
	Stone,
	Crumble, // holds one crossing: falls when Psyche steps off it
	Phantom, // exists only in the dark: the lamp's light dissolves it
	Veiled, // hidden in the dark: the lamp's light makes it real
}

TRAIT_NAME := [Trait]string {
	.Stone   = "block",
	.Crumble = "crumble",
	.Phantom = "phantom",
	.Veiled  = "veiled",
}

Solid_Entry :: struct {
	cell:  Cell,
	solid: Solid,
	trait: Trait,
	part:  u8, // 0: fixed; n: turns with part n-1
}

// A part of the palace that a handle turns a quarter at a time, about the
// vertical axis through the centre of cell `pivot`.
Part :: struct {
	pivot: [2]i32,
}

// A crank on a surface: standing there, Psyche turns `part` a quarter.
Handle :: struct {
	cell: Cell,
	part: int,
}

Prop_Kind :: enum u8 {
	// edge props: close one side of the cell they stand in
	Rail,
	Wall,
	Wall_Half,
	Wall_Battlement,
	Fence,
	Rope, // the hand ropes of a rope bridge, along one side
	Log, // a fallen trunk lying along one side
	Lip, // a low lip of rock along one side: the parapet of a crag's ledge
	// blocking props: nobody can stand in their cell
	Pillar,
	Plinth,
	Cypress,
	Urn,
	Brazier,
	Bed,
	Statue, // a marble woman on a plinth, calling with her arm raised toward `dir`
	Spruce, // a tall fir of the forest
	// decoration only
	Arch,
	Vase, // small, in one corner of the cell: px (+x,+y), py (-x,+y), mx (-x,-y), my (+x,-y)
	Reeds, // a clump of reeds in one corner of the cell (as the vase)
	Sconce, // a candle on the side `dir` of the block at (x,y,z): lit where the setting lights them
	// the mountain: blocking
	Pine, // a wind-bent pine
	Boulder, // a heap of fallen rocks
	// the mountain: decoration only, in one corner of the cell (as the vase)
	Shrub, // a low bush
	Cairn, // a few stones piled up by passers-by
}

EDGE_PROPS :: bit_set[Prop_Kind]{.Rail, .Wall, .Wall_Half, .Wall_Battlement, .Fence, .Rope, .Log, .Lip}
BLOCKING_PROPS :: bit_set[Prop_Kind]{.Pillar, .Plinth, .Cypress, .Urn, .Brazier, .Bed, .Statue, .Spruce, .Pine, .Boulder}
ORIENTED_PROPS :: EDGE_PROPS + bit_set[Prop_Kind]{.Bed, .Statue, .Arch, .Vase, .Reeds, .Sconce, .Pine, .Boulder, .Shrub, .Cairn}
NEEDS_DIR :: EDGE_PROPS + bit_set[Prop_Kind]{.Statue, .Vase, .Reeds, .Sconce, .Shrub, .Cairn}

PROP_NAME := [Prop_Kind]string {
	.Rail            = "rail",
	.Wall            = "wall",
	.Wall_Half       = "wallHalf",
	.Wall_Battlement = "wallBattlement",
	.Fence           = "fence",
	.Rope            = "rope",
	.Log             = "log",
	.Lip             = "lip",
	.Pillar          = "pillar",
	.Plinth          = "plinth",
	.Cypress         = "cypress",
	.Urn             = "urn",
	.Brazier         = "brazier",
	.Bed             = "bed",
	.Statue          = "statue",
	.Spruce          = "spruce",
	.Arch            = "arch",
	.Vase            = "vase",
	.Reeds           = "reeds",
	.Sconce          = "sconce",
	.Pine            = "pine",
	.Boulder         = "boulder",
	.Shrub           = "shrub",
	.Cairn           = "cairn",
}

// A standing candelabrum in a corner of a surface: lit from the start, or
// waiting for the lamp's flame.
Candelabrum :: struct {
	cell: Cell, // the surface it stands on (x, y, h)
	dir:  Dir, // its corner, as the vase's
	lit:  bool,
}

// The mouth of a cave: a dark opening in the rock on side `dir` of the
// surface `cell` (x, y, h). Caves come in pairs, in the order of the file
// (the first with the second, the third with the fourth...): walking into
// one, Psyche comes out of the other, wherever it is.
Cave :: struct {
	cell: Cell,
	dir:  Dir,
}

// A block drawn as the deck of a rope bridge (it holds like any block).
Plank :: struct {
	cell:    Cell,
	along_y: bool, // the bridge runs along y (default: along x)
}

Prop :: struct {
	cell:     Cell,
	kind:     Prop_Kind,
	dir:      Dir,
	oriented: bool,
	part:     u8, // 0: fixed; n: turns with part n-1
}

// A text tied to a cell: a voice line or a hint, given when Psyche first
// stands there (the start cell: when the level begins).
Cue :: struct {
	cell: Cell,
	key:  i18n.Key,
}

Level_Data :: struct {
	size:      i32, // the diorama is size x size; it rotates about its centre
	height:    i32, // grid height (z) that holds every piece, with headroom
	blocks:    [dynamic]Solid_Entry,
	rise:      [dynamic]Solid_Entry, // raised when the sigil is lit
	props:     [dynamic]Prop,
	voices:    [dynamic]Cue,
	hints:     [dynamic]Cue,
	start:        Cell,
	sigil:        Cell,
	amore:        Cell,
	fragments:    [dynamic]Cell, // the fragments of the tale (optional, never required), in content order
	exit:         Cell, // reaching it completes the level
	has_sigil:    bool,
	has_amore:    bool,
	has_exit:     bool,
	prologue:     Cell, // where the prologue's procession comes up onto the level
	has_prologue: bool, // the level opens with the prologue cutscene (I.1)
	intro:        i18n.Key, // the line shown when the level begins
	has_intro:    bool,
	lawn:         [dynamic]Cell, // blocks with a grassy top
	candelabra:   [dynamic]Candelabrum,
	ground:       [dynamic]Cell, // blocks and stairs of living rock (earth, not masonry)
	planks:       [dynamic]Plank, // blocks that are the wooden deck of a rope bridge
	water:        [dynamic][4]i32, // rectangles of water (x0 y0 x1 y1), just under the h1 surfaces
	caves:        [dynamic]Cave, // in pairs: each leads to the other of its pair
	tiers:        [dynamic][2]i32, // a tall level: the camera frames one band of heights (h0 h1) at a time
	outro:        i18n.Key, // the text of the ending card at the exit
	has_outro:    bool,
	has_lamp:     bool, // Psyche carries the lamp (from the end of Act I)
	lamp_par:     i32, // lightings that are enough to finish ("no wasted light"); 0 = none
	oil:          f32, // seconds of oil in the lamp (0: the default)
	parts:        [dynamic]Part,
	handles:      [dynamic]Handle,
	rests:        [dynamic]Cell, // braziers: lit by passing, R brings Psyche back to the last one
	mechanic:     Mechanic, // the new mechanic this level introduces (a card at the start)
	setting:      Setting, // the sky, the backdrop, the light on the stones
}

MAX_PARTS :: 8
MAX_FRAGMENTS :: 4
MAX_CANDELABRA :: 12
MAX_DYNAMIC :: 64 // crumbling, phantom and veiled blocks in one level
MAX_TIERS :: 6

// The cell of a part's block after `r` quarter turns.
part_cell :: proc(c: Cell, pivot: [2]i32, r: int) -> Cell {
	v := iso.rot_vec({c.x - pivot.x, c.y - pivot.y}, r)
	return {pivot.x + v.x, pivot.y + v.y, c.z}
}

Parse_Error :: struct {
	line:    int,
	message: string, // allocated with the parse allocator
}

MAX_SIZE :: 64
MAX_HEIGHT :: 64

// Parse a level. Every allocation (arrays, error text) uses `allocator`,
// typically the level arena, so the whole level is freed at once.
parse :: proc(text: string, allocator := context.allocator) -> (data: Level_Data, err: Maybe(Parse_Error)) {
	context.allocator = allocator
	data.size = 12
	data.blocks = make([dynamic]Solid_Entry, 0, 128)
	data.rise = make([dynamic]Solid_Entry, 0, 8)
	data.props = make([dynamic]Prop, 0, 32)
	data.voices = make([dynamic]Cue, 0, 16)
	data.hints = make([dynamic]Cue, 0, 8)
	data.fragments = make([dynamic]Cell, 0, MAX_FRAGMENTS)
	data.lawn = make([dynamic]Cell, 0, 8)
	data.candelabra = make([dynamic]Candelabrum, 0, MAX_CANDELABRA)
	data.ground = make([dynamic]Cell, 0, 16)
	data.planks = make([dynamic]Plank, 0, 8)
	data.water = make([dynamic][4]i32, 0, 2)
	data.caves = make([dynamic]Cave, 0, 4)
	data.tiers = make([dynamic][2]i32, 0, MAX_TIERS)
	data.parts = make([dynamic]Part, 0, 2)
	data.handles = make([dynamic]Handle, 0, 2)
	data.rests = make([dynamic]Cell, 0, 4)
	has_start := false
	part: u8 = 0 // the part being described (between `part` and `end`)
	dynamic_count := 0
	max_z: i32 = 0

	fail :: proc(line: int, format: string, args: ..any) -> Maybe(Parse_Error) {
		return Parse_Error{line, fmt.aprintf(format, ..args)}
	}

	rest := text
	line_no := 0
	for raw in strings.split_lines_iterator(&rest) {
		line_no += 1
		line := raw
		if i := strings.index_byte(line, '#'); i >= 0 {
			line = line[:i]
		}
		fields: [8]string
		n := 0
		it := line
		for f in strings.fields_iterator(&it) {
			if n == len(fields) {
				return data, fail(line_no, "too many fields")
			}
			fields[n] = f
			n += 1
		}
		if n == 0 {
			continue
		}
		args := fields[1:n]

		ints :: proc(args: []string, out: []i32) -> bool {
			if len(args) < len(out) {
				return false
			}
			for &o, i in out {
				v, ok := strconv.parse_int(args[i], 10)
				if !ok {
					return false
				}
				o = i32(v)
			}
			return true
		}

		switch fields[0] {
		case "size":
			v: [1]i32
			if !ints(args, v[:]) || v[0] < 2 || v[0] > MAX_SIZE {
				return data, fail(line_no, "size: expected an integer in 2..%d", MAX_SIZE)
			}
			data.size = v[0]

		case "block", "crumble", "phantom", "veiled":
			v: [3]i32
			if !ints(args, v[:]) {
				return data, fail(line_no, "%s: expected x y z", fields[0])
			}
			trait := Trait.Stone
			for name, t in TRAIT_NAME {
				if name == fields[0] {
					trait = t
				}
			}
			if trait != .Stone {
				dynamic_count += 1
				if dynamic_count > MAX_DYNAMIC {
					return data, fail(line_no, "too many changing blocks (max %d)", MAX_DYNAMIC)
				}
			}
			append(&data.blocks, Solid_Entry{v, {kind = .Block}, trait, part})
			if len(args) > 3 {
				switch args[3] {
				case "rock":
					append(&data.ground, v) // a stone of living rock, bare: no grass
				case "ground":
					append(&data.ground, v) // living rock, its top grassy
					append(&data.lawn, v)
				case "plank":
					append(&data.planks, Plank{v, false})
				case "plank_y":
					append(&data.planks, Plank{v, true})
				case:
					return data, fail(line_no, "%s: expected rock, ground, plank or plank_y after x y z", fields[0])
				}
			}
			max_z = max(max_z, v.z)

		case "part":
			v: [2]i32
			if !ints(args, v[:]) {
				return data, fail(line_no, "part: expected the pivot x y")
			}
			if part != 0 {
				return data, fail(line_no, "part: the previous part has no 'end'")
			}
			if len(data.parts) == MAX_PARTS {
				return data, fail(line_no, "too many parts (max %d)", MAX_PARTS)
			}
			append(&data.parts, Part{v})
			part = u8(len(data.parts))

		case "end":
			if part == 0 {
				return data, fail(line_no, "end: no part to close")
			}
			part = 0

		case "handle":
			v: [4]i32
			if !ints(args, v[:3]) {
				return data, fail(line_no, "handle: expected x y h [part]")
			}
			index := len(data.parts) - 1
			if len(args) > 3 {
				if !ints(args[3:], v[3:]) {
					return data, fail(line_no, "handle: expected a part number")
				}
				index = int(v[3])
			}
			if index < 0 || index >= len(data.parts) {
				return data, fail(line_no, "handle: no such part")
			}
			append(&data.handles, Handle{v.xyz, index})
			max_z = max(max_z, v.z)

		case "mechanic":
			found := false
			for name, m in MECHANIC_NAME {
				if len(args) > 0 && name == args[0] {
					data.mechanic, found = m, true
				}
			}
			if !found {
				return data, fail(line_no, "mechanic: expected crumble, phantom, veiled or handle")
			}

		case "rest":
			v: [3]i32
			if !ints(args, v[:]) {
				return data, fail(line_no, "rest: expected x y h")
			}
			append(&data.rests, v)
			max_z = max(max_z, v.z)

		case "oil":
			v: [1]i32
			if !ints(args, v[:]) || v[0] < 1 {
				return data, fail(line_no, "oil: expected seconds >= 1")
			}
			data.oil = f32(v[0])

		case "column":
			v: [4]i32
			if !ints(args, v[:]) || v[3] < v[2] {
				return data, fail(line_no, "column: expected x y z0 z1 with z0 <= z1")
			}
			for z in v[2] ..= v[3] {
				append(&data.blocks, Solid_Entry{{v[0], v[1], z}, {kind = .Block}, .Stone, part})
			}
			max_z = max(max_z, v[3])

		case "ground", "rock":
			v: [4]i32
			if !ints(args, v[:]) || v[3] < v[2] {
				return data, fail(line_no, "%s: expected x y z0 z1 with z0 <= z1", fields[0])
			}
			for z in v[2] ..= v[3] {
				append(&data.blocks, Solid_Entry{{v[0], v[1], z}, {kind = .Block}, .Stone, part})
				append(&data.ground, Cell{v[0], v[1], z})
			}
			if fields[0] == "ground" {
				append(&data.lawn, Cell{v[0], v[1], v[3]}) // rock: bare on top too
			}
			max_z = max(max_z, v[3])

		case "setting":
			found := false
			for name, st in SETTING_NAME {
				if len(args) == 1 && name == args[0] {
					data.setting, found = st, true
				}
			}
			if !found {
				return data, fail(line_no, "setting: expected one of night, crag_sunset, dusk, night_candles, deep_night, forest_night, river_dawn, crag_day")
			}

		case "tier":
			v: [2]i32
			if !ints(args, v[:]) || v[1] < v[0] {
				return data, fail(line_no, "tier: expected h0 h1 with h0 <= h1")
			}
			if len(data.tiers) == MAX_TIERS {
				return data, fail(line_no, "too many tiers (max %d)", MAX_TIERS)
			}
			append(&data.tiers, v)

		case "water":
			v: [4]i32
			if !ints(args, v[:]) || v[2] < v[0] || v[3] < v[1] {
				return data, fail(line_no, "water: expected x0 y0 x1 y1 with x0 <= x1, y0 <= y1")
			}
			append(&data.water, v)

		case "cave":
			v: [3]i32
			if !ints(args, v[:]) || len(args) < 4 {
				return data, fail(line_no, "cave: expected x y h dir")
			}
			d, ok := iso.dir_from_name(args[3])
			if !ok {
				return data, fail(line_no, "cave: unknown direction '%s'", args[3])
			}
			append(&data.caves, Cave{v, d})
			max_z = max(max_z, v.z + 1)

		case "stairs", "steps":
			v: [3]i32
			if !ints(args, v[:]) || len(args) < 4 {
				return data, fail(line_no, "%s: expected x y z dir", fields[0])
			}
			d, ok := iso.dir_from_name(args[3])
			if !ok {
				return data, fail(line_no, "%s: unknown direction '%s'", fields[0], args[3])
			}
			append(&data.blocks, Solid_Entry{v, {.Stairs, d}, .Stone, part})
			if fields[0] == "steps" {
				append(&data.ground, v)
			}
			max_z = max(max_z, v.z)

		case "rise":
			v: [3]i32
			if !ints(args, v[:]) {
				return data, fail(line_no, "rise: expected x y z [stairs_dir] [rock|ground]")
			}
			s := Solid{kind = .Block}
			opts := args[3:]
			if len(opts) > 0 && (opts[len(opts) - 1] == "rock" || opts[len(opts) - 1] == "ground") {
				append(&data.ground, v) // living rock rising from the earth (ground: its top grassy)
				if opts[len(opts) - 1] == "ground" {
					append(&data.lawn, v)
				}
				opts = opts[:len(opts) - 1]
			}
			if len(opts) > 0 {
				d, ok := iso.dir_from_name(opts[0])
				if !ok {
					return data, fail(line_no, "rise: unknown direction '%s'", opts[0])
				}
				s = {.Stairs, d}
			}
			append(&data.rise, Solid_Entry{cell = v, solid = s})
			max_z = max(max_z, v.z)

		case "candelabrum":
			if len(args) < 4 {
				return data, fail(line_no, "candelabrum: expected x y h dir [lit]")
			}
			v: [3]i32
			if !ints(args[:3], v[:]) {
				return data, fail(line_no, "candelabrum: expected integer coordinates")
			}
			d, ok := iso.dir_from_name(args[3])
			if !ok {
				return data, fail(line_no, "candelabrum: unknown direction '%s'", args[3])
			}
			if len(data.candelabra) == MAX_CANDELABRA {
				return data, fail(line_no, "candelabrum: at most %d per level", MAX_CANDELABRA)
			}
			append(&data.candelabra, Candelabrum{cell = v, dir = d, lit = len(args) > 4 && args[4] == "lit"})
			max_z = max(max_z, v.z + 1)

		case "prop":
			if len(args) < 4 {
				return data, fail(line_no, "prop: expected name x y z [dir]")
			}
			kind, found := Prop_Kind(0), false
			for name, k in PROP_NAME {
				if name == args[0] {
					kind, found = k, true
				}
			}
			if !found {
				return data, fail(line_no, "prop: unknown prop '%s'", args[0])
			}
			v: [3]i32
			if !ints(args[1:], v[:]) {
				return data, fail(line_no, "prop: expected integer coordinates")
			}
			p := Prop{cell = v, kind = kind, part = part}
			if len(args) > 4 {
				d, ok := iso.dir_from_name(args[4])
				if !ok {
					return data, fail(line_no, "prop: unknown direction '%s'", args[4])
				}
				p.dir, p.oriented = d, true
			}
			if kind in NEEDS_DIR && !p.oriented {
				return data, fail(line_no, "prop: '%s' needs a direction", args[0])
			}
			append(&data.props, p)
			max_z = max(max_z, v.z + 1)

		case "start", "sigil", "amore", "fragment", "exit", "prologue":
			v: [3]i32
			if !ints(args, v[:]) {
				return data, fail(line_no, "%s: expected x y h", fields[0])
			}
			switch fields[0] {
			case "start": data.start, has_start = v, true
			case "sigil": data.sigil, data.has_sigil = v, true
			case "amore": data.amore, data.has_amore = v, true
			case "fragment":
				if len(data.fragments) == MAX_FRAGMENTS {
					return data, fail(line_no, "fragment: at most %d per level", MAX_FRAGMENTS)
				}
				append(&data.fragments, v)
			case "exit": data.exit, data.has_exit = v, true
			case "prologue": data.prologue, data.has_prologue = v, true
			}
			max_z = max(max_z, v.z)

		case "lamp":
			data.has_lamp = true
			if len(args) > 0 {
				v: [1]i32
				if !ints(args, v[:]) || v[0] < 1 {
					return data, fail(line_no, "lamp: expected an optional number of lightings >= 1")
				}
				data.lamp_par = v[0]
			}

		case "outro", "intro":
			if len(args) < 1 {
				return data, fail(line_no, "%s: expected a text key", fields[0])
			}
			key, ok := i18n.key_from_name(args[0])
			if !ok {
				return data, fail(line_no, "%s: unknown text key '%s'", fields[0], args[0])
			}
			if fields[0] == "outro" {
				data.outro, data.has_outro = key, true
			} else {
				data.intro, data.has_intro = key, true
			}

		case "lawn":
			v: [3]i32
			if !ints(args, v[:]) {
				return data, fail(line_no, "lawn: expected x y z")
			}
			append(&data.lawn, v)


		case "voice", "hint":
			v: [3]i32
			if !ints(args, v[:]) || len(args) < 4 {
				return data, fail(line_no, "%s: expected x y h key", fields[0])
			}
			key, ok := i18n.key_from_name(args[3])
			if !ok {
				return data, fail(line_no, "%s: unknown text key '%s'", fields[0], args[3])
			}
			append(fields[0] == "voice" ? &data.voices : &data.hints, Cue{v, key})

		case:
			return data, fail(line_no, "unknown command '%s'", fields[0])
		}
	}

	if !has_start {
		return data, fail(line_no, "missing 'start'")
	}
	if part != 0 {
		return data, fail(line_no, "the last part has no 'end'")
	}
	if len(data.caves) % 2 != 0 {
		return data, fail(line_no, "cave: caves come in pairs (the last one has no other end)")
	}
	data.height = max_z + 4
	if data.height > MAX_HEIGHT {
		return data, fail(line_no, "level too tall (max z %d)", MAX_HEIGHT - 4)
	}
	// every coordinate must sit inside the grid
	check :: proc(c: Cell, size, height: i32) -> bool {
		return c.x >= 0 && c.y >= 0 && c.z >= 0 && c.x < size && c.y < size && c.z < height
	}
	for e in data.blocks {
		if !check(e.cell, data.size, data.height) {
			return data, fail(0, "block %v outside the %d x %d grid", e.cell, data.size, data.size)
		}
	}
	for e in data.rise {
		if !check(e.cell, data.size, data.height) {
			return data, fail(0, "rise %v outside the grid", e.cell)
		}
	}
	for c in data.caves {
		if !check(c.cell, data.size, data.height) {
			return data, fail(0, "cave %v outside the grid", c.cell)
		}
	}
	for p in data.props {
		if !check(p.cell, data.size, data.height) {
			return data, fail(0, "prop %v outside the grid", p.cell)
		}
	}
	// a part must stay inside the grid in all four positions
	for e in data.blocks {
		if e.part == 0 {
			continue
		}
		for r in 1 ..< 4 {
			if c := part_cell(e.cell, data.parts[e.part - 1].pivot, r); !check(c, data.size, data.height) {
				return data, fail(0, "part block %v leaves the grid when turned", e.cell)
			}
		}
	}
	return data, nil
}
