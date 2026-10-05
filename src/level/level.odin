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

Solid_Entry :: struct {
	cell:  Cell,
	solid: Solid,
}

Prop_Kind :: enum u8 {
	// edge props: close one side of the cell they stand in
	Rail,
	Wall,
	Wall_Half,
	Window,
	Wall_Battlement,
	Fence,
	// blocking props: nobody can stand in their cell
	Pillar,
	Plinth,
	Cypress,
	Urn,
	Brazier,
	Bed,
	// decoration only
	Arch,
}

EDGE_PROPS :: bit_set[Prop_Kind]{.Rail, .Wall, .Wall_Half, .Window, .Wall_Battlement, .Fence}
BLOCKING_PROPS :: bit_set[Prop_Kind]{.Pillar, .Plinth, .Cypress, .Urn, .Brazier, .Bed}
ORIENTED_PROPS :: EDGE_PROPS + bit_set[Prop_Kind]{.Bed, .Arch}

PROP_NAME := [Prop_Kind]string {
	.Rail            = "rail",
	.Wall            = "wall",
	.Wall_Half       = "wallHalf",
	.Window          = "window",
	.Wall_Battlement = "wallBattlement",
	.Fence           = "fence",
	.Pillar          = "pillar",
	.Plinth          = "plinth",
	.Cypress         = "cypress",
	.Urn             = "urn",
	.Brazier         = "brazier",
	.Bed             = "bed",
	.Arch            = "arch",
}

Prop :: struct {
	cell:     Cell,
	kind:     Prop_Kind,
	dir:      Dir,
	oriented: bool,
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
	fragment:     Cell, // the fragment of the tale (optional, never required)
	exit:         Cell, // reaching it completes the level
	has_sigil:    bool,
	has_amore:    bool,
	has_fragment: bool,
	has_exit:     bool,
	prologue:     Cell, // where the prologue's procession comes up onto the level
	has_prologue: bool, // the level opens with the prologue cutscene (I.1)
	outro:        i18n.Key, // the text of the ending card at the exit
	has_outro:    bool,
	has_lamp:     bool, // Psyche carries the lamp (from the end of Act I)
	lamp_par:     i32, // lightings that are enough to finish ("no wasted light"); 0 = none
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
	has_start := false
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

		case "block":
			v: [3]i32
			if !ints(args, v[:]) {
				return data, fail(line_no, "block: expected x y z")
			}
			append(&data.blocks, Solid_Entry{v, {kind = .Block}})
			max_z = max(max_z, v.z)

		case "column":
			v: [4]i32
			if !ints(args, v[:]) || v[3] < v[2] {
				return data, fail(line_no, "column: expected x y z0 z1 with z0 <= z1")
			}
			for z in v[2] ..= v[3] {
				append(&data.blocks, Solid_Entry{{v[0], v[1], z}, {kind = .Block}})
			}
			max_z = max(max_z, v[3])

		case "stairs":
			v: [3]i32
			if !ints(args, v[:]) || len(args) < 4 {
				return data, fail(line_no, "stairs: expected x y z dir")
			}
			d, ok := iso.dir_from_name(args[3])
			if !ok {
				return data, fail(line_no, "stairs: unknown direction '%s'", args[3])
			}
			append(&data.blocks, Solid_Entry{v, {.Stairs, d}})
			max_z = max(max_z, v.z)

		case "rise":
			v: [3]i32
			if !ints(args, v[:]) {
				return data, fail(line_no, "rise: expected x y z [stairs_dir]")
			}
			s := Solid{kind = .Block}
			if len(args) > 3 {
				d, ok := iso.dir_from_name(args[3])
				if !ok {
					return data, fail(line_no, "rise: unknown direction '%s'", args[3])
				}
				s = {.Stairs, d}
			}
			append(&data.rise, Solid_Entry{v, s})
			max_z = max(max_z, v.z)

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
			p := Prop{cell = v, kind = kind}
			if len(args) > 4 {
				d, ok := iso.dir_from_name(args[4])
				if !ok {
					return data, fail(line_no, "prop: unknown direction '%s'", args[4])
				}
				p.dir, p.oriented = d, true
			}
			if kind in EDGE_PROPS && !p.oriented {
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
			case "fragment": data.fragment, data.has_fragment = v, true
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

		case "outro":
			if len(args) < 1 {
				return data, fail(line_no, "outro: expected a text key")
			}
			key, ok := i18n.key_from_name(args[0])
			if !ok {
				return data, fail(line_no, "outro: unknown text key '%s'", args[0])
			}
			data.outro, data.has_outro = key, true

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
	for p in data.props {
		if !check(p.cell, data.size, data.height) {
			return data, fail(0, "prop %v outside the grid", p.cell)
		}
	}
	return data, nil
}
