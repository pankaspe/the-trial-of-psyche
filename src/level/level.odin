// Level files (assets/levels/*.txt): a plain list of commands, one per line.
// The format is documented at the top of assets/levels/level_04.txt.
package level

import "base:intrinsics"
import "core:fmt"
import "core:slice"
import "core:strconv"
import "core:strings"

import "../i18n"
import "../iso"

Cell :: iso.Cell
Dir :: iso.Dir

// The value a table of names (the `*_NAME` tables) gives the name `s`.
named :: proc(names: [$E]string, s: string) -> (E, bool) {
	for name, e in names {
		if name == s {
			return e, true
		}
	}
	return {}, false
}

// The same in a table of rows with a `name` (PROPS, BIOMES).
row_named :: proc(rows: [$E]$T, s: string) -> (E, bool) where intrinsics.type_has_field(T, "name") {
	for row, e in rows {
		if row.name == s {
			return e, true
		}
	}
	return {}, false
}

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
	Veiled,
	Handle,
	Time, // day and evening, turned at a sundial
	Eagle, // Jupiter's eagle: a flight one way, from its perch
	Flip, // Proserpina's flip: the world turned over, from her pomegranate
	Ferry, // Charon's ferry: his boat across the water, from one landing to the other
}

MECHANIC_NAME := [Mechanic]string {
	.None    = "none",
	.Veiled  = "veiled",
	.Handle  = "handle",
	.Time    = "time",
	.Eagle   = "eagle",
	.Flip    = "flip",
	.Ferry   = "ferry",
}

// The cutscene that opens a level (the first of each act has one).
Scene :: enum u8 {
	None,
	Oracle, // I.1: the oracle, the procession up the crag, Psyche left alone
	Flight, // II.1: Cupid flies away, Psyche clinging to him, and she falls into the forest
	Venus, // III.1: Venus pours the seeds and leaves on her doves; an ant takes pity on Psyche
	Tower, // IV.1: on the top of the tower Psyche looks down to throw herself off, and the tower speaks
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
	Temple_Dusk, // a temple at dusk among the ranges: the afterglow, the first stars, its candles lit
	Venus_Evening, // the house of Venus above the clouds at evening: rose light, her star bright
	Pasture_Day, // the Sun's pastures by a river at noon: a hot clear sky, the sun high
	Pasture_Evening, // the same at evening: the sun gone down, amber and violet, the first star
	Venus_Day, // the house of Venus above the clouds by day: a pale gold morning, the sun in a rose haze
	Styx_Night, // the gorge under the Styx's crag: no moon, faint stars, the black water falling
	Styx_Day, // the summit of the Styx's crag by day: a white sun hard on the black rock
	Styx_Evening, // the same at evening: a low red sun, the peaks black against it
	Tower_Dusk, // the top of the high tower at dusk: the sky still rose, a red glow rising from below
	Taenarus, // the foot of Taenarus, the mouth of the underworld: a red sky, ash, the dark water
	Asphodel, // the land of the dead over Proserpina's kingdom: a cold violet dusk, clouds of ash drifting
	Asphodel_Night, // the same by night: a violet dark, a cold pale moon, the ash over it
	Dis, // Proserpina's kingdom, the world turned over: a sky of fire over a sea of lava
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
	.Temple_Dusk  = "temple_dusk",
	.Venus_Evening = "venus_evening",
	.Pasture_Day   = "pasture_day",
	.Pasture_Evening = "pasture_evening",
	.Venus_Day     = "venus_day",
	.Styx_Night    = "styx_night",
	.Styx_Day      = "styx_day",
	.Styx_Evening  = "styx_evening",
	.Tower_Dusk    = "tower_dusk",
	.Taenarus      = "taenarus",
	.Asphodel      = "asphodel",
	.Asphodel_Night = "asphodel_night",
	.Dis           = "dis",
}

// How a block behaves (Act II): fixed stone, or one that changes for good.
Trait :: enum u8 {
	Stone,
	Veiled, // hidden in the dark: the lamp's light makes it real
	Sunlit, // there only by day: at evening it crumbles away (a level with sundials)
}

TRAIT_NAME := [Trait]string {
	.Stone  = "block",
	.Veiled = "veiled",
	.Sunlit = "sunlit",
}

Solid_Entry :: struct {
	cell:  Cell,
	solid: Solid,
	trait: Trait,
	part:  u8, // 0: fixed; n: turns with part n-1
	seal:  u8, // `rise` entries: the seal (data.sigils index) that raises it
	under: bool, // the world under the palace: `cell` is in its frame (see `flip_cell`)
	trap:  bool, // a veiled stone that, made real, closes the way (drawn corrupt)
}

// A golden ram of the Sun (Act III), on the surface `cell` (x, y, h): by day
// it stands there and nobody passes; at evening it lies down, and its back is
// a step up toward `dir` (stairs from h to h + 1).
Ram :: struct {
	cell: Cell,
	dir:  Dir,
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

// A standing candelabrum in a corner of a surface: lit from the start, or
// waiting for the lamp's flame. A guard (Act IV) is a seal of its own: the
// lamp lit beside it lights it, and its light shows the way through the
// dark (its `rise` blocks appear).
Candelabrum :: struct {
	cell:  Cell, // the surface it stands on (x, y, h)
	dir:   Dir, // its corner, as the vase's
	lit:   bool,
	guard: bool,
	seal:  u8, // a guard: its seal (data.sigils index)
	under: bool,
}

// The mouth of a cave: a dark opening in the rock on side `dir` of the
// surface `cell` (x, y, h). Caves come in pairs, in the order of the file
// (the first with the second, the third with the fourth...): walking into
// one, Psyche comes out of the other, wherever it is.
Cave :: struct {
	cell: Cell,
	dir:  Dir,
}

// What the diorama stands on (decoration: it holds nobody): a rectangle of
// cells (x0 y0 x1 y1) just under the surfaces of height `Level_Data.floor_h`.
Floor_Kind :: enum u8 {
	Water, // a river or a lake, its edges fading into the mist
	Basin, // a marble basin brimming with water, its rim just under the surfaces
}

FLOOR_NAME := [Floor_Kind]string {
	.Water = "water",
	.Basin = "basin",
}

// What a basin's rim and bottom are made of.
Rim :: enum u8 {
	Marble,
	Rock, // living rock
	Earth, // earth, grass on top
}

RIM_NAME := [Rim]string {
	.Marble = "marble",
	.Rock   = "rock",
	.Earth  = "earth",
}

// What fills a floor: its colour comes from the setting (night, day, the dead).
Fluid :: enum u8 {
	Water,
	Swamp, // still, green-brown, duckweed and slow bubbles
}

FLUID_NAME := [Fluid]string {
	.Water = "water",
	.Swamp = "swamp",
}

Floor :: struct {
	kind:  Floor_Kind,
	rim:   Rim, // a basin's
	fluid: Fluid,
	area:  [4]i32,
}

// Jupiter's eagle (Act III) waits on a perch on the surface `from`
// (x, y, h): standing there, Space calls it, and it carries Psyche to the
// surface `to`. One way only: nothing brings her back but another eagle.
Eagle :: struct {
	from, to: Cell,
}

// Charon's boat (Act IV), moored on side `dir` of the surface `cell`
// (x, y, h), the landing: standing there, Space boards it and he ferries
// Psyche away across the dark water (the landing is the level's exit).
Boat :: struct {
	cell: Cell,
	dir:  Dir,
}

// Charon's ferry (Act IV): one boat between two landings (`ends`, each
// moored on its side `dir`). It waits at the first; standing where it is
// moored, Space boards it and he poles her across to the other landing, where
// it stays: from a landing it has left, nothing brings it back but crossing
// again from the other.
Ferry :: struct {
	ends: [2]Boat,
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
	under:    bool,
}

// A text tied to a cell: a voice line or a hint, given when Psyche first
// stands there (the start cell: when the level begins).
Cue :: struct {
	cell:  Cell,
	key:   i18n.Key,
	under: bool,
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
	sigil:        Cell, // the first seal (I.4's: the canonical ending's level)
	sigils:       [dynamic]Cell, // every seal, in file order: each raises its own `rise` blocks
	guard_seals:  Seals, // the seals that are guard candelabra (their blocks appear in the light, not rising)
	amore:        Cell,
	fragments:    [dynamic]Cell, // the fragments of the tale (optional, never required), in content order
	exit:         Cell, // reaching it completes the level
	has_sigil:    bool,
	has_amore:    bool,
	has_exit:     bool,
	prologue:     Cell, // the scene's place: where the procession comes up (Oracle), the cypress Cupid flies over (Flight), the edge she looks down from (Tower)
	has_prologue: bool, // the level opens with a cutscene (`scene` says which)
	scene:        Scene,
	intro:        i18n.Key, // the line shown when the level begins
	has_intro:    bool,
	lawn:         [dynamic]Cell, // blocks with a grassy top
	candelabra:   [dynamic]Candelabrum,
	ground:       [dynamic]Cell, // blocks and stairs of living rock (earth, not masonry)
	planks:       [dynamic]Plank, // blocks that are the wooden deck of a rope bridge
	floors:       [dynamic]Floor, // what the diorama stands on, just under the `floor_h` surfaces
	floor_h:      i32, // the height of the surfaces the floors lie just under (1 unless given)
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
	setting:      Setting, // the sky, the backdrop, the light on the stones (by day, in a level with sundials)
	below:        Setting, // a level that goes down (`has_below`): the look at its foot, blended in as she descends
	has_below:    bool,
	boat:         Boat, // Charon's boat at the exit (`has_boat`): Space boards it
	has_boat:     bool,
	has_box:      bool, // the act's last level (`box`): at the exit she opens Proserpina's box and the sleep takes her
	evening:      Setting, // a level with sundials: the look at evening
	sundials:     [dynamic]Cell, // Act III: standing on one, the spindle turns the time (day <-> evening); the level starts by day
	rams:         [dynamic]Ram, // the Sun's rams: standing by day, lying (a step) at evening
	eagles:       [dynamic]Eagle, // Act III: from a perch, a flight one way
	ferries:      [dynamic]Ferry, // Act IV: Charon's boat between two landings
	// Proserpina's flip (Act IV): the world turned over about the axle, the
	// horizontal line along x through the middle of row size/2 at height `axle`
	// (`flip_cell`). The world under the palace (`under` lines) is described
	// in its own frame, as it stands once turned up.
	pomegranates: [dynamic]Cell, // her pomegranates, on the axle's stones (x, size/2, axle + 1): the same feet cell either way up
	axle:         i32,
	sigils_under: Seals, // the seals of the world under the palace
	fragments_under: bit_set[0 ..< MAX_FRAGMENTS],
	exit_under:   bool,
	upside:       Setting, // the look with the world turned over (`has_upside`)
	has_upside:   bool,
	duality:      bool, // the axle's floor shows bare rock to the world above, marble to the world under (`duality`)
	biome:        Biome, // the place (`has_biome`): its defaults, its props
	has_biome:    bool,
}

MAX_PARTS :: 8
MAX_FRAGMENTS :: 4
MAX_CANDELABRA :: 12
MAX_LIGHTS :: 16 // flames the stone shader takes at once: the nearest to Psyche
MAX_DYNAMIC :: 64 // veiled blocks in one level
MAX_TIERS :: 6
MAX_SEALS :: 4
Seals :: bit_set[0 ..< MAX_SEALS; u8] // which seals have been lit
MAX_SUNDIALS :: 8
MAX_RAMS :: 12
MAX_EAGLES :: 4
MAX_FERRIES :: 4
Boats :: bit_set[0 ..< MAX_FERRIES; u8] // the ferries whose boat is moored at their second landing

// A cell of one frame in the other: the world turned over about the axle
// (x, y, z) -> (x, size-1-y, 2 axle - z). Its own inverse; the axle's stones
// (x, size/2, axle) stay where they are.
flip_cell :: proc(d: ^Level_Data, c: Cell) -> Cell {
	return {c.x, d.size - 1 - c.y, 2 * d.axle - c.z}
}

// Where a cell of the world under the palace (`under`) or above it is in the
// frame of the world up now (`upside`: the world turned over).
frame_cell :: proc(d: ^Level_Data, c: Cell, under, upside: bool) -> Cell {
	return under == upside ? c : flip_cell(d, c)
}

// Where a cell of the world under the palace (or above it) stands with the
// world as described: its `lawn`, `ground` and `planks` marks are kept so.
world_cell :: proc(d: ^Level_Data, c: Cell, under: bool) -> Cell {
	return under ? flip_cell(d, c) : c
}

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
// A level slot's text may hold several dioramas played one after the other
// (one level in the level select): each is a level file of its own, and a
// line `diorama` starts the next. Every diorama but the last ends at an exit.
MAX_DIORAMAS :: 4

// The dioramas of a slot's text: slices of it, in order.
dioramas :: proc(text: string, allocator := context.temp_allocator) -> []string {
	parts := make([dynamic]string, 0, MAX_DIORAMAS, allocator)
	start := 0
	rest := text
	at := 0
	for line in strings.split_lines_iterator(&rest) {
		next := len(text) - len(rest)
		if strings.trim_space(line) == "diorama" {
			append(&parts, text[start:at])
			start = next
		}
		at = next
	}
	append(&parts, text[start:])
	return parts[:]
}

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
	data.floors = make([dynamic]Floor, 0, 2)
	data.floor_h = 1
	data.caves = make([dynamic]Cave, 0, 4)
	data.tiers = make([dynamic][2]i32, 0, MAX_TIERS)
	data.sigils = make([dynamic]Cell, 0, MAX_SEALS)
	data.parts = make([dynamic]Part, 0, 2)
	data.handles = make([dynamic]Handle, 0, 2)
	data.rests = make([dynamic]Cell, 0, 4)
	data.sundials = make([dynamic]Cell, 0, MAX_SUNDIALS)
	data.rams = make([dynamic]Ram, 0, MAX_RAMS)
	data.eagles = make([dynamic]Eagle, 0, MAX_EAGLES)
	data.ferries = make([dynamic]Ferry, 0, MAX_FERRIES)
	data.pomegranates = make([dynamic]Cell, 0, 4)
	has_setting := false
	has_evening := false
	has_start := false
	floor_given := make([dynamic][2]bool, context.temp_allocator) // each floor: its rim, its fluid written in the file
	part: u8 = 0 // the part being described (between `part` and `end`)
	under := false // between `under` and `end`: the world under the palace
	under_line := 0
	under_marks := make([dynamic][4]int, context.temp_allocator) // lawn and ground entries added under
	under_planks := make([dynamic][2]int, context.temp_allocator)
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
		fields: [9]string
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
		if under {
			switch fields[0] {
			case "block", "veiled", "column", "ground", "rock", "stairs", "steps", "rise", "prop", "candelabrum", "fragment", "exit", "sigil", "lawn", "voice", "hint", "end":
			case:
				return data, fail(line_no, "%s: not in the world under the palace", fields[0])
			}
		}
		// what this line adds: in an `under` section, it belongs to the world under the palace
		before := [?]int{len(data.blocks), len(data.rise), len(data.props), len(data.candelabra), len(data.voices), len(data.hints), len(data.sigils), len(data.fragments), len(data.lawn), len(data.ground), len(data.planks)}

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

		case "block", "veiled":
			v: [3]i32
			if !ints(args, v[:]) {
				return data, fail(line_no, "%s: expected x y z", fields[0])
			}
			trait, _ := named(TRAIT_NAME, fields[0])
			if trait == .Veiled {
				dynamic_count += 1
				if dynamic_count > MAX_DYNAMIC {
					return data, fail(line_no, "too many changing blocks (max %d)", MAX_DYNAMIC)
				}
			}
			append(&data.blocks, Solid_Entry{cell = v, solid = {kind = .Block}, trait = trait, part = part})
			for opt, k in args[3:] {
				switch {
				case opt == "trap" && trait == .Veiled:
					data.blocks[len(data.blocks) - 1].trap = true
				case k > 0:
					return data, fail(line_no, "%s: expected trap after the look", fields[0])
				case opt == "rock":
					append(&data.ground, v) // a stone of living rock, bare: no grass
				case opt == "ground":
					append(&data.ground, v) // living rock, its top grassy
					append(&data.lawn, v)
				case opt == "plank":
					append(&data.planks, Plank{v, false})
				case opt == "plank_y":
					append(&data.planks, Plank{v, true})
				case:
					return data, fail(line_no, "%s: expected rock, ground, plank or plank_y after x y z%s", fields[0], trait == .Veiled ? ", or trap" : "")
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
			if part == 0 && !under {
				return data, fail(line_no, "end: no part or under to close")
			}
			part = 0
			under = false

		case "under":
			if part != 0 || under {
				return data, fail(line_no, "under: close the part (or the last under) first")
			}
			under, under_line = true, line_no

		case "pomegranate":
			v: [3]i32
			if !ints(args, v[:]) {
				return data, fail(line_no, "pomegranate: expected x y h")
			}
			if part != 0 || under {
				return data, fail(line_no, "pomegranate: on the axle, not inside a part or under")
			}
			append(&data.pomegranates, v)
			max_z = max(max_z, v.z + 1)

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
			found: bool
			data.mechanic, found = named(MECHANIC_NAME, len(args) > 0 ? args[0] : "")
			if !found {
				return data, fail(line_no, "mechanic: expected veiled, handle, time, eagle, flip or ferry")
			}

		case "rest":
			v: [3]i32
			if !ints(args, v[:]) {
				return data, fail(line_no, "rest: expected x y h")
			}
			append(&data.rests, v)
			max_z = max(max_z, v.z)

		case "sundial":
			v: [3]i32
			if !ints(args, v[:]) {
				return data, fail(line_no, "sundial: expected x y h")
			}
			if part != 0 {
				return data, fail(line_no, "sundial: not inside a part")
			}
			if len(data.sundials) == MAX_SUNDIALS {
				return data, fail(line_no, "sundial: at most %d per level", MAX_SUNDIALS)
			}
			append(&data.sundials, v)
			max_z = max(max_z, v.z + 1)

		case "ram":
			v: [3]i32
			if !ints(args, v[:]) || len(args) < 4 {
				return data, fail(line_no, "ram: expected x y h dir")
			}
			d, ok := iso.dir_from_name(args[3])
			if !ok {
				return data, fail(line_no, "ram: unknown direction '%s'", args[3])
			}
			if part != 0 {
				return data, fail(line_no, "ram: not inside a part")
			}
			if len(data.rams) == MAX_RAMS {
				return data, fail(line_no, "ram: at most %d per level", MAX_RAMS)
			}
			append(&data.rams, Ram{v, d})
			max_z = max(max_z, v.z + 1)

		case "eagle":
			v: [6]i32
			if !ints(args, v[:]) {
				return data, fail(line_no, "eagle: expected x y h (the perch) and x y h (where it carries her)")
			}
			if part != 0 {
				return data, fail(line_no, "eagle: not inside a part")
			}
			if len(data.eagles) == MAX_EAGLES {
				return data, fail(line_no, "eagle: at most %d per level", MAX_EAGLES)
			}
			e := Eagle{{v[0], v[1], v[2]}, {v[3], v[4], v[5]}}
			if e.from == e.to {
				return data, fail(line_no, "eagle: it must carry her somewhere else")
			}
			for o in data.eagles {
				if o.from == e.from {
					return data, fail(line_no, "eagle: two eagles on the perch %v", e.from)
				}
			}
			append(&data.eagles, e)
			max_z = max(max_z, v[2] + 1, v[5])

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
				append(&data.blocks, Solid_Entry{cell = {v[0], v[1], z}, solid = {kind = .Block}, part = part})
			}
			max_z = max(max_z, v[3])

		case "ground", "rock":
			v: [4]i32
			if !ints(args, v[:]) || v[3] < v[2] {
				return data, fail(line_no, "%s: expected x y z0 z1 with z0 <= z1", fields[0])
			}
			for z in v[2] ..= v[3] {
				append(&data.blocks, Solid_Entry{cell = {v[0], v[1], z}, solid = {kind = .Block}, part = part})
				append(&data.ground, Cell{v[0], v[1], z})
			}
			if fields[0] == "ground" {
				append(&data.lawn, Cell{v[0], v[1], v[3]}) // rock: bare on top too
			}
			max_z = max(max_z, v[3])

		case "setting", "evening", "below", "upside":
			st, found := named(SETTING_NAME, len(args) == 1 ? args[0] : "")
			if !found {
				return data, fail(line_no, "%s: expected one of %s", fields[0], strings.join(slice.enumerated_array(&SETTING_NAME), ", ", context.temp_allocator))
			}
			switch fields[0] {
			case "setting": data.setting, has_setting = st, true
			case "evening": data.evening, has_evening = st, true
			case "below": data.below, data.has_below = st, true
			case "upside": data.upside, data.has_upside = st, true
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

		case "floor":
			f: Floor
			found: bool
			f.kind, found = named(FLOOR_NAME, len(args) > 0 ? args[0] : "")
			at := 1 // where the area begins: after a basin's rim and the fluid, if given
			given: [2]bool // the rim, the fluid
			if found && f.kind == .Basin && at < len(args) {
				if f.rim, given[0] = named(RIM_NAME, args[at]); given[0] {
					at += 1
				}
			}
			if found && at < len(args) {
				if f.fluid, given[1] = named(FLUID_NAME, args[at]); given[1] {
					at += 1
				}
			}
			if !found || !ints(args[at:], f.area[:]) || f.area[2] < f.area[0] || f.area[3] < f.area[1] {
				return data, fail(line_no, "floor: expected water [swamp] x0 y0 x1 y1 [h] or basin [marble|rock|earth] [water|swamp] x0 y0 x1 y1 [h], with x0 <= x1, y0 <= y1")
			}
			if len(args) > at + 4 {
				h: [1]i32
				if !ints(args[at + 4:], h[:]) || h[0] < 1 || len(data.floors) > 0 && h[0] != data.floor_h {
					return data, fail(line_no, "floor: h is the height of the surfaces it lies under, the same for every floor")
				}
				data.floor_h = h[0]
			}
			append(&data.floors, f)
			append(&floor_given, given)

		case "biome":
			data.biome, data.has_biome = row_named(BIOMES, len(args) == 1 ? args[0] : "")
			if !data.has_biome {
				names := make([dynamic]string, 0, len(Biome), context.temp_allocator)
				for info in BIOMES {
					append(&names, info.name)
				}
				return data, fail(line_no, "biome: expected one of %s", strings.join(names[:], ", ", context.temp_allocator))
			}

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

		case "charon":
			v: [3]i32
			if !ints(args, v[:]) || len(args) < 4 {
				return data, fail(line_no, "charon: expected x y h dir")
			}
			d, ok := iso.dir_from_name(args[3])
			if !ok {
				return data, fail(line_no, "charon: unknown direction '%s'", args[3])
			}
			if data.has_boat {
				return data, fail(line_no, "charon: one boat per level")
			}
			data.boat, data.has_boat = Boat{v, d}, true
			max_z = max(max_z, v.z + 1)

		case "ferry":
			v0, v1: [3]i32
			if len(args) < 8 || !ints(args[0:3], v0[:]) || !ints(args[4:7], v1[:]) {
				return data, fail(line_no, "ferry: expected x y h dir (where the boat waits) and x y h dir (the other landing)")
			}
			f: Ferry
			for v, k in ([2][3]i32{v0, v1}) {
				d, ok := iso.dir_from_name(args[3 + 4 * k])
				if !ok {
					return data, fail(line_no, "ferry: unknown direction '%s'", args[3 + 4 * k])
				}
				f.ends[k] = {v, d}
				max_z = max(max_z, v.z + 1)
			}
			if part != 0 || under {
				return data, fail(line_no, "ferry: of the world above, not inside a part")
			}
			if f.ends[0].cell == f.ends[1].cell {
				return data, fail(line_no, "ferry: it must take her somewhere else")
			}
			if len(data.ferries) == MAX_FERRIES {
				return data, fail(line_no, "ferry: at most %d per level", MAX_FERRIES)
			}
			append(&data.ferries, f)

		case "sunlit":
			// a block, or stairs toward dir, standing only by day
			v: [3]i32
			if !ints(args, v[:]) {
				return data, fail(line_no, "sunlit: expected x y z [stairs_dir]")
			}
			s := Solid{kind = .Block}
			if len(args) > 3 {
				d, ok := iso.dir_from_name(args[3])
				if !ok {
					return data, fail(line_no, "sunlit: unknown direction '%s'", args[3])
				}
				s = {.Stairs, d}
			}
			append(&data.blocks, Solid_Entry{cell = v, solid = s, trait = .Sunlit, part = part})
			max_z = max(max_z, v.z)

		case "stairs", "steps":
			v: [3]i32
			if !ints(args, v[:]) || len(args) < 4 {
				return data, fail(line_no, "%s: expected x y z dir", fields[0])
			}
			d, ok := iso.dir_from_name(args[3])
			if !ok {
				return data, fail(line_no, "%s: unknown direction '%s'", fields[0], args[3])
			}
			append(&data.blocks, Solid_Entry{cell = v, solid = {.Stairs, d}, part = part})
			if fields[0] == "steps" {
				append(&data.ground, v)
			}
			max_z = max(max_z, v.z)

		case "rise":
			v: [3]i32
			if !ints(args, v[:]) {
				return data, fail(line_no, "rise: expected x y z [stairs_dir] [rock|ground] [seal]")
			}
			s := Solid{kind = .Block}
			opts := args[3:]
			seal: u8 = 0
			if len(opts) > 0 {
				if k, ok := strconv.parse_int(opts[len(opts) - 1], 10); ok {
					if k < 1 || k > MAX_SEALS {
						return data, fail(line_no, "rise: the seal is a number 1..%d", MAX_SEALS)
					}
					seal = u8(k - 1)
					opts = opts[:len(opts) - 1]
				}
			}
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
			append(&data.rise, Solid_Entry{cell = v, solid = s, seal = seal})
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
			c := Candelabrum{cell = v, dir = d}
			if len(args) > 4 {
				switch args[4] {
				case "lit": c.lit = true
				case "guard":
					// a seal of its own, numbered with the sigils in file order
					if len(data.sigils) == MAX_SEALS {
						return data, fail(line_no, "candelabrum: at most %d seals and guards per level", MAX_SEALS)
					}
					if !data.has_sigil {
						data.sigil, data.has_sigil = v, true
					}
					c.guard, c.seal = true, u8(len(data.sigils))
					data.guard_seals += {len(data.sigils)}
					append(&data.sigils, v)
				case:
					return data, fail(line_no, "candelabrum: expected lit or guard after the direction")
				}
			}
			append(&data.candelabra, c)
			max_z = max(max_z, v.z + 1)

		case "prop":
			if len(args) < 4 {
				return data, fail(line_no, "prop: expected name x y z [dir]")
			}
			kind, found := row_named(PROPS, args[0])
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
			if PROPS[kind].dir == .Needed && !p.oriented {
				return data, fail(line_no, "prop: '%s' needs a direction", args[0])
			}
			append(&data.props, p)
			max_z = max(max_z, v.z + 1)

		case "start", "sigil", "amore", "fragment", "exit", "prologue", "flight", "venus", "tower":
			v: [3]i32
			if !ints(args, v[:]) {
				return data, fail(line_no, "%s: expected x y h", fields[0])
			}
			switch fields[0] {
			case "start": data.start, has_start = v, true
			case "sigil":
				if len(data.sigils) == MAX_SEALS {
					return data, fail(line_no, "sigil: at most %d per level", MAX_SEALS)
				}
				if !data.has_sigil {
					data.sigil, data.has_sigil = v, true
				}
				append(&data.sigils, v)
			case "amore": data.amore, data.has_amore = v, true
			case "fragment":
				if len(data.fragments) == MAX_FRAGMENTS {
					return data, fail(line_no, "fragment: at most %d per level", MAX_FRAGMENTS)
				}
				append(&data.fragments, v)
			case "exit": data.exit, data.has_exit = v, true
			case "prologue": data.prologue, data.has_prologue, data.scene = v, true, .Oracle
			case "flight": data.prologue, data.has_prologue, data.scene = v, true, .Flight
			case "venus": data.prologue, data.has_prologue, data.scene = v, true, .Venus
			case "tower": data.prologue, data.has_prologue, data.scene = v, true, .Tower
			}
			max_z = max(max_z, v.z)

		case "duality":
			data.duality = true

		case "box":
			data.has_box = true

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
			append(fields[0] == "voice" ? &data.voices : &data.hints, Cue{cell = v, key = key})

		case:
			return data, fail(line_no, "unknown command '%s'", fields[0])
		}
		if under {
			for &e in data.blocks[before[0]:] {
				e.under = true
			}
			for &e in data.rise[before[1]:] {
				e.under = true
			}
			for &e in data.props[before[2]:] {
				e.under = true
			}
			for &e in data.candelabra[before[3]:] {
				e.under = true
			}
			for &e in data.voices[before[4]:] {
				e.under = true
			}
			for &e in data.hints[before[5]:] {
				e.under = true
			}
			for k in before[6] ..< len(data.sigils) {
				data.sigils_under += {k}
			}
			for k in before[7] ..< len(data.fragments) {
				data.fragments_under += {k}
			}
			data.exit_under ||= fields[0] == "exit"
			// living rock, lawns and planks are looked up by the block's cell in the
			// world as it stands (`world_cell`): turned over once the axle is known
			append(&under_marks, [4]int{before[8], len(data.lawn), before[9], len(data.ground)})
			append(&under_planks, [2]int{before[10], len(data.planks)})
		}
	}

	if !has_start {
		return data, fail(line_no, "missing 'start'")
	}
	if part != 0 {
		return data, fail(line_no, "the last part has no 'end'")
	}
	if under {
		return data, fail(under_line, "under: no 'end'")
	}
	if len(data.pomegranates) > 0 {
		if data.size % 2 == 0 {
			return data, fail(0, "pomegranate: the world turns over about the middle row: the size must be odd")
		}
		data.axle = data.pomegranates[0].z - 1
		for f in data.pomegranates {
			if f.y != data.size / 2 || f.z != data.axle + 1 || f.x < 0 || f.x >= data.size {
				return data, fail(0, "pomegranate %v: the pomegranates lie on the axle (y %d, all at the same height)", f, data.size / 2)
			}
		}
		if len(data.sundials) > 0 {
			return data, fail(0, "pomegranate: the world does not turn over in a level with sundials")
		}
		// both worlds must fit the grid either way up
		for e in data.blocks {
			if e.cell.z > 2 * data.axle {
				return data, fail(0, "block %v: above twice the axle's height, the world turned over would leave the grid", e.cell)
			}
		}
		for e in data.rise {
			if e.cell.z > 2 * data.axle {
				return data, fail(0, "rise %v: above twice the axle's height", e.cell)
			}
		}
		for e in data.blocks {
			if e.under && e.part != 0 {
				return data, fail(0, "block %v: no parts under the palace", e.cell)
			}
		}
		for m in under_marks {
			for &c in data.lawn[m[0]:m[1]] {
				c = flip_cell(&data, c)
			}
			for &c in data.ground[m[2]:m[3]] {
				c = flip_cell(&data, c)
			}
		}
		for m in under_planks {
			for &pk in data.planks[m[0]:m[1]] {
				pk.cell = flip_cell(&data, pk.cell)
			}
		}
	} else if len(under_marks) > 0 {
		return data, fail(0, "under: a world under the palace needs a pomegranate to be reached")
	}
	if len(data.caves) % 2 != 0 {
		return data, fail(line_no, "cave: caves come in pairs (the last one has no other end)")
	}
	if data.has_biome {
		// the place's defaults, where the file says nothing
		b := BIOMES[data.biome]
		day, has_day := b.day.?
		if !has_setting {
			data.setting = has_day && len(data.sundials) > 0 ? day[0] : b.light
		}
		if has_day && len(data.sundials) > 0 && !has_evening {
			data.evening, has_evening = day[1], true
		}
		if below, ok := b.below.?; ok && !data.has_below {
			data.below, data.has_below = below, true
		}
		if under, ok := b.upside.?; ok && len(data.pomegranates) > 0 && !data.has_upside {
			data.upside, data.has_upside = BIOMES[under].light, true
		}
		for &f, i in data.floors {
			if !floor_given[i][0] {
				f.rim = b.rim
			}
			if !floor_given[i][1] {
				f.fluid = b.fluid
			}
		}
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
		if int(e.seal) >= len(data.sigils) {
			return data, fail(0, "rise %v: no seal %d raises it", e.cell, e.seal + 1)
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
	// a basin holds the whole diorama: nothing stands on or over its rim (a
	// part in any of its positions)
	for f in data.floors {
		if f.kind != .Basin {
			continue
		}
		inside :: proc(data: ^Level_Data, a: [4]i32, c: Cell, under: bool, part: u8) -> bool {
			for turn in 0 ..< (part > 0 ? 4 : 1) {
				w := world_cell(data, part > 0 ? part_cell(c, data.parts[part - 1].pivot, turn) : c, under)
				if w.x <= a[0] || w.x >= a[2] || w.y <= a[1] || w.y >= a[3] {
					return false
				}
			}
			return true
		}
		for e in data.blocks {
			if !inside(&data, f.area, e.cell, e.under, e.part) {
				return data, fail(0, "block %v on or past the basin's rim: the diorama stays inside it", e.cell)
			}
		}
		for e in data.rise {
			if !inside(&data, f.area, e.cell, e.under, 0) {
				return data, fail(0, "rise %v on or past the basin's rim: the diorama stays inside it", e.cell)
			}
		}
		for p in data.props {
			if !inside(&data, f.area, p.cell, p.under, p.part) {
				return data, fail(0, "prop %v on or past the basin's rim: the diorama stays inside it", p.cell)
			}
		}
		for c in data.candelabra {
			if !inside(&data, f.area, c.cell, c.under, 0) {
				return data, fail(0, "candelabrum %v on or past the basin's rim: the diorama stays inside it", c.cell)
			}
		}
	}
	if len(data.sundials) > 0 && !has_evening {
		return data, fail(0, "sundial: a level with sundials needs its 'evening' setting")
	}
	for e in data.blocks {
		if e.trait == .Sunlit && len(data.sundials) == 0 {
			return data, fail(0, "sunlit: stands only by day: the level needs a sundial")
		}
	}
	if data.has_boat && (!data.has_exit || data.boat.cell != data.exit) {
		return data, fail(0, "charon: the boat is moored at the exit (its landing is the exit cell)")
	}
	if data.has_below && len(data.sundials) > 0 {
		return data, fail(0, "below: a level that goes down does not turn between day and evening")
	}
	if len(data.rams) > 0 && len(data.sundials) == 0 {
		return data, fail(0, "ram: the rams lie down only at evening: the level needs a sundial")
	}
	for c in data.sundials {
		if !check(c, data.size, data.height) {
			return data, fail(0, "sundial %v outside the grid", c)
		}
	}
	for m in data.rams {
		if !check(m.cell, data.size, data.height) {
			return data, fail(0, "ram %v outside the grid", m.cell)
		}
	}
	for e in data.eagles {
		if !check(e.from, data.size, data.height) || !check(e.to, data.size, data.height) {
			return data, fail(0, "eagle %v -> %v outside the grid", e.from, e.to)
		}
	}
	for f in data.ferries {
		for e in f.ends {
			if !check(e.cell, data.size, data.height) {
				return data, fail(0, "ferry landing %v outside the grid", e.cell)
			}
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
