// The pieces of the palace and the figures, as boxes and lathes.
// Oriented pieces exist in the four directions, in Dir order (px, mx, py, my);
// they are designed facing +x and rotated about the cell centre.
package render

import rl "vendor:raylib"

import "../iso"
import "../level"

Mesh_Id :: enum u8 {
	Block,
	Stairs_PX, Stairs_MX, Stairs_PY, Stairs_MY,
	Rail_PX, Rail_MX, Rail_PY, Rail_MY,
	Wall_PX, Wall_MX, Wall_PY, Wall_MY,
	Wall_Half_PX, Wall_Half_MX, Wall_Half_PY, Wall_Half_MY,
	Battlement_PX, Battlement_MX, Battlement_PY, Battlement_MY,
	Fence_PX, Fence_MX, Fence_PY, Fence_MY,
	Rope_PX, Rope_MX, Rope_PY, Rope_MY,
	Log_PX, Log_MX, Log_PY, Log_MY,
	Lip_PX, Lip_MX, Lip_PY, Lip_MY,
	Bed_PX, Bed_MX, Bed_PY, Bed_MY,
	Arch_PX, Arch_MX, Arch_PY, Arch_MY,
	Vase_PX, Vase_MX, Vase_PY, Vase_MY,
	Reeds_PX, Reeds_MX, Reeds_PY, Reeds_MY,
	Sconce_PX, Sconce_MX, Sconce_PY, Sconce_MY,
	Candle_PX, Candle_MX, Candle_PY, Candle_MY,
	Pine_PX, Pine_MX, Pine_PY, Pine_MY, // the crown, leaning toward dir...
	Trunk_PX, Trunk_MX, Trunk_PY, Trunk_MY, // ...on its bent trunk
	Boulder_PX, Boulder_MX, Boulder_PY, Boulder_MY,
	Shrub_PX, Shrub_MX, Shrub_PY, Shrub_MY,
	Cairn_PX, Cairn_MX, Cairn_PY, Cairn_MY,
	Rose_PX, Rose_MX, Rose_PY, Rose_MY, // a rose bush in a corner...
	Rose_Bloom_PX, Rose_Bloom_MX, Rose_Bloom_PY, Rose_Bloom_MY, // ...and its flowers
	Myrtle_PX, Myrtle_MX, Myrtle_PY, Myrtle_MY, // a myrtle's crown...
	Myrtle_Pot_PX, Myrtle_Pot_MX, Myrtle_Pot_PY, Myrtle_Pot_MY, // ...in its pot
	Statue_PX, Statue_MX, Statue_PY, Statue_MY,
	Candelabrum_PX, Candelabrum_MX, Candelabrum_PY, Candelabrum_MY, // a standing candelabrum in a corner...
	Candelabrum_Wax_PX, Candelabrum_Wax_MX, Candelabrum_Wax_PY, Candelabrum_Wax_MY, // ...and its three candles
	Pillar,
	Plinth,
	Cypress,
	Spruce, // the crown in tiers...
	Spruce_Trunk, // ...on its straight trunk
	Heap, // a mound of mixed seeds
	Plank_X, // the deck of a rope bridge running along x...
	Plank_Y, // ...or along y
	Urn,
	Brazier,
	Sigil_Off,
	Sigil_On,
	Robe,
	Robe_Cupid,
	Head,
	Lamp,
	Scroll,
	Crank_Post, // a handle: a bronze post in the (+x, +y) corner...
	Crank_Wheel, // ...and its wheel, turning about its own centre
	Altar, // a small brazier in the (-x, -y) corner: a resting place
	Cave_PX, Cave_MX, Cave_PY, Cave_MY, // the stones framing a cave's mouth on the +x side...
	Cave_Dark_PX, Cave_Dark_MX, Cave_Dark_PY, Cave_Dark_MY, // ...and the dark inside it
}

// Where the resting brazier's flame burns, in cell space.
ALTAR_FLAME :: [3]f32{0.2, 0.2, 0.42}

// Where the crank's wheel turns, in cell space.
CRANK_AXIS :: [3]f32{0.8, 0.8, 0.42}

oriented_mesh :: proc(base: Mesh_Id, d: iso.Dir) -> Mesh_Id {
	return Mesh_Id(u8(base) + u8(d))
}

Material :: enum u8 {
	Marble,
	Masonry,
	Foliage,
	Bronze,
	Psyche,
	Cupid,
	Mourner,
	Lawn, // grass on top, earth on the sides
	Rock, // living rock under the meadows: brown earth in rough strata
	Wood, // bark
	Void, // the dark inside a cave
	Seeds, // grains of five kinds, mixed (detail: how far up they are sorted into layers)
	Blossom, // roses
	Venus, // the goddess: a figure of rose light
}

PROP_MESH := [level.Prop_Kind]Mesh_Id {
	.Rail            = .Rail_PX,
	.Wall            = .Wall_PX,
	.Wall_Half       = .Wall_Half_PX,
	.Wall_Battlement = .Battlement_PX,
	.Fence           = .Fence_PX,
	.Rope            = .Rope_PX,
	.Log             = .Log_PX,
	.Lip             = .Lip_PX,
	.Pillar          = .Pillar,
	.Plinth          = .Plinth,
	.Cypress         = .Cypress,
	.Urn             = .Urn,
	.Brazier         = .Brazier,
	.Bed             = .Bed_PX,
	.Statue          = .Statue_PX,
	.Spruce          = .Spruce,
	.Heap            = .Heap,
	.Arch            = .Arch_PX,
	.Vase            = .Vase_PX,
	.Reeds           = .Reeds_PX,
	.Sconce          = .Sconce_PX,
	.Pine            = .Pine_PX,
	.Boulder         = .Boulder_PX,
	.Shrub           = .Shrub_PX,
	.Cairn           = .Cairn_PX,
	.Rose            = .Rose_PX,
	.Myrtle          = .Myrtle_PX,
}

PROP_MATERIAL := [level.Prop_Kind]Material {
	.Rail            = .Marble,
	.Wall            = .Masonry,
	.Wall_Half       = .Masonry,
	.Wall_Battlement = .Masonry,
	.Fence           = .Bronze,
	.Rope            = .Wood,
	.Log             = .Wood,
	.Lip             = .Rock,
	.Pillar          = .Marble,
	.Plinth          = .Marble,
	.Cypress         = .Foliage,
	.Urn             = .Bronze,
	.Brazier         = .Bronze,
	.Bed             = .Bronze,
	.Statue          = .Marble,
	.Spruce          = .Foliage,
	.Heap            = .Seeds,
	.Arch            = .Masonry,
	.Vase            = .Bronze,
	.Reeds           = .Foliage,
	.Sconce          = .Bronze,
	.Pine            = .Foliage,
	.Boulder         = .Rock,
	.Shrub           = .Foliage,
	.Cairn           = .Rock,
	.Rose            = .Foliage,
	.Myrtle          = .Foliage,
}

// --- box lists ---------------------------------------------------------------------

@(private)
stairs_px :: proc() -> []Box {
	// four steps that do not overlap (overlapping slices would fight in depth)
	out := make([]Box, 4, context.temp_allocator)
	for i in 0 ..< 4 {
		a, b := f32(i) / 4, f32(i + 1) / 4
		out[i] = {{a, 0, 0}, {b, 1, b}}
	}
	return out
}

@(private)
bed_px :: proc() -> []Box {
	out := make([dynamic]Box, 0, 9, context.temp_allocator)
	append(&out, Box{{0.08, 0.15, 0}, {0.92, 0.85, 0.22}})
	append(&out, Box{{0.12, 0.2, 0.22}, {0.66, 0.8, 0.3}})
	append(&out, Box{{0.66, 0.2, 0.22}, {0.88, 0.8, 0.3}})
	append(&out, Box{{0.7, 0.24, 0.3}, {0.86, 0.76, 0.38}})
	for p in ([4][2]f32{{0.08, 0.15}, {0.84, 0.15}, {0.08, 0.77}, {0.84, 0.77}}) {
		append(&out, Box{{p.x, p.y, 0.22}, {p.x + 0.08, p.y + 0.08, 1.5}})
	}
	append(&out, Box{{0.04, 0.11, 1.5}, {0.96, 0.89, 1.58}})
	return out[:]
}

// Low balustrade along the +x edge of the cell.
@(private)
rail_px :: proc() -> []Box {
	out := make([dynamic]Box, 0, 4, context.temp_allocator)
	for y in ([3]f32{0.04, 0.37, 0.7}) {
		append(&out, Box{{0.86, y, 0}, {0.96, y + 0.08, 0.32}})
	}
	append(&out, Box{{0.84, 0, 0.32}, {0.98, 1, 0.38}})
	return out[:]
}

@(private)
WALL_PX := [?]Box{{{0.78, 0, 0}, {1, 1, 1}}}
@(private)
WALL_HALF_PX := [?]Box{{{0.78, 0, 0}, {1, 1, 0.5}}}
@(private)
// a slender parapet with two small merlons
BATTLEMENT_PX := [?]Box {
	{{0.9, 0, 0}, {0.98, 1, 0.26}},
	{{0.9, 0.08, 0.26}, {0.98, 0.3, 0.4}},
	{{0.9, 0.7, 0.26}, {0.98, 0.92, 0.4}},
}
@(private)
FENCE_PX := [?]Box {
	{{0.88, 0.02, 0}, {0.96, 0.1, 0.45}},
	{{0.88, 0.9, 0}, {0.96, 0.98, 0.45}},
	{{0.9, 0, 0.18}, {0.94, 1, 0.24}},
	{{0.9, 0, 0.34}, {0.94, 1, 0.4}},
}
// a slender arch spanning the cell along x (posts at the y edges)
@(private)
ARCH_PX := [?]Box {
	{{0.43, 0, 0}, {0.57, 0.09, 1.32}},
	{{0.43, 0.91, 0}, {0.57, 1, 1.32}},
	{{0.41, 0, 1.32}, {0.59, 1, 1.42}},
}
// a candle holder on the +x face of a block, below its top: back plate,
// arm and cup in bronze; the candle is its own piece (lit by the setting: `candle_flame`)
@(private)
SCONCE_PX := [?]Box {
	{{1.0, 0.42, 0.38}, {1.03, 0.58, 0.68}},
	{{1.03, 0.47, 0.48}, {1.12, 0.53, 0.53}},
	{{1.06, 0.41, 0.53}, {1.18, 0.59, 0.58}},
}
@(private)
CANDLE_PX := [?]Box{{{1.095, 0.465, 0.58}, {1.145, 0.535, 0.8}}}
// Where a sconce's candle burns, in cell space, on the side d of its block.
candle_flame :: proc(d: iso.Dir) -> Vec3 {
	switch d {
	case .PX: return {1.12, 0.5, 0.86}
	case .MX: return {-0.12, 0.5, 0.86}
	case .PY: return {0.5, 1.12, 0.86}
	case .MY: return {0.5, -0.12, 0.86}
	}
	return {}
}
// a small vase, turned: it stands in the (+x, +y) corner of the cell
@(private)
VASE_PROFILE := [?][2]f32 {
	{0.0, 0.0}, {0.04, 0.0}, {0.058, 0.04}, {0.068, 0.1}, {0.058, 0.165}, {0.033, 0.2}, {0.03, 0.225}, {0.045, 0.25}, {0.0, 0.25},
}
@(private)
PILLAR := [?]Box {
	{{0.3, 0.3, 0}, {0.7, 0.7, 0.15}},
	{{0.36, 0.36, 0.15}, {0.64, 0.64, 1.85}},
	{{0.28, 0.28, 1.85}, {0.72, 0.72, 2.0}},
}
@(private)
PLINTH := [?]Box{{{0.2, 0.2, 0}, {0.8, 0.8, 0.3}}}
@(private)
URN := [?]Box {
	{{0.4, 0.4, 0}, {0.6, 0.6, 0.06}},
	{{0.36, 0.36, 0.06}, {0.64, 0.64, 0.34}},
	{{0.42, 0.42, 0.34}, {0.58, 0.58, 0.42}},
	{{0.38, 0.38, 0.42}, {0.62, 0.62, 0.46}},
}
@(private)
BRAZIER := [?]Box{{{0.44, 0.44, 0}, {0.56, 0.56, 0.45}}, {{0.3, 0.3, 0.45}, {0.7, 0.7, 0.58}}}
// the seal: a plate on the floor with a raised panel (lit: the panel sinks)
@(private)
SIGIL_OFF := [?]Box{{{0.1, 0.1, 0}, {0.9, 0.9, 0.035}}, {{0.24, 0.24, 0.035}, {0.76, 0.76, 0.07}}}
@(private)
SIGIL_ON := [?]Box{{{0.1, 0.1, 0}, {0.9, 0.9, 0.035}}, {{0.24, 0.24, 0.02}, {0.76, 0.76, 0.045}}}

// a clump of reeds in the (+x, +y) corner: thin stalks of different heights,
// some with a dark head (Pan's syrinx was cut from them)
@(private)
reeds_px :: proc() -> []Box {
	stalks := [?][3]f32 {
		{0.86, 0.84, 0.62}, {0.78, 0.9, 0.48}, {0.92, 0.74, 0.55}, {0.7, 0.8, 0.36},
		{0.84, 0.66, 0.42}, {0.9, 0.93, 0.7}, {0.74, 0.7, 0.3}, {0.64, 0.9, 0.4},
	}
	out := make([dynamic]Box, 0, 12, context.temp_allocator)
	for st, i in stalks {
		W :: 0.012
		append(&out, Box{{st.x - W, st.y - W, 0}, {st.x + W, st.y + W, st.z}})
		if i % 3 == 0 {
			append(&out, Box{{st.x - 0.022, st.y - 0.022, st.z - 0.1}, {st.x + 0.022, st.y + 0.022, st.z - 0.02}})
		}
	}
	return out[:]
}

@(private)
cypress :: proc() -> []Box {
	out := make([dynamic]Box, 0, 10, context.temp_allocator)
	append(&out, Box{{0.38, 0.38, 0}, {0.62, 0.62, 0.25}}) // pot
	w: f32 = 0.2
	z: f32 = 0.25
	for k in 0 ..< 9 {
		fk := f32(k)
		s := k < 3 ? w * (1 - abs(fk - 2.5) / 7.5) : w * (1 - (fk - 2) / 8)
		append(&out, Box{{0.5 - s, 0.5 - s, z}, {0.5 + s, 0.5 + s, z + 0.2}})
		z += 0.2
	}
	return out[:]
}

// The mountain's pieces, designed for the (+x) direction or the (+x, +y) corner.
// A pine bent by the wind: the trunk leans toward +x, the crown in flat pads.
@(private)
PINE_TRUNK_PX := [?]Box {
	{{0.4, 0.43, 0}, {0.54, 0.57, 0.36}},
	{{0.45, 0.44, 0.36}, {0.58, 0.56, 0.7}},
	{{0.51, 0.45, 0.7}, {0.63, 0.55, 1.0}},
	{{0.28, 0.47, 0.78}, {0.5, 0.53, 0.84}}, // a branch to the lee side
}
@(private)
PINE_PX := [?]Box {
	{{0.3, 0.2, 0.96}, {0.98, 0.8, 1.14}},
	{{0.42, 0.3, 1.14}, {0.88, 0.7, 1.28}},
	{{0.54, 0.38, 1.28}, {0.78, 0.6, 1.36}},
	{{0.1, 0.36, 0.8}, {0.4, 0.64, 0.94}},
}
// fallen rocks, three of them, with a small one aside
@(private)
BOULDER_PX := [?]Box {
	{{0.12, 0.18, 0}, {0.6, 0.68, 0.36}},
	{{0.5, 0.32, 0}, {0.88, 0.84, 0.26}},
	{{0.26, 0.3, 0.36}, {0.54, 0.58, 0.54}},
	{{0.64, 0.12, 0}, {0.84, 0.3, 0.14}},
}
@(private)
SHRUB_PX := [?]Box {
	{{0.66, 0.66, 0}, {0.95, 0.95, 0.13}},
	{{0.71, 0.71, 0.13}, {0.91, 0.91, 0.22}},
	{{0.56, 0.8, 0}, {0.68, 0.96, 0.09}},
}
// A rose bush in the (+x, +y) corner, and its flowers (their own piece, in blossom).
@(private)
ROSE_PX := [?]Box {
	{{0.62, 0.62, 0}, {0.95, 0.95, 0.16}},
	{{0.66, 0.66, 0.16}, {0.93, 0.93, 0.27}},
	{{0.71, 0.7, 0.27}, {0.89, 0.9, 0.34}},
	{{0.54, 0.78, 0}, {0.66, 0.95, 0.12}},
}
@(private)
ROSE_BLOOM_PX := [?]Box {
	{{0.595, 0.73, 0.08}, {0.65, 0.79, 0.14}},
	{{0.74, 0.595, 0.06}, {0.8, 0.65, 0.12}},
	{{0.635, 0.85, 0.2}, {0.685, 0.9, 0.25}},
	{{0.85, 0.635, 0.21}, {0.9, 0.685, 0.26}},
	{{0.77, 0.77, 0.33}, {0.83, 0.83, 0.385}},
	{{0.685, 0.71, 0.26}, {0.735, 0.76, 0.31}},
	{{0.515, 0.84, 0.08}, {0.565, 0.89, 0.13}},
	{{0.885, 0.8, 0.12}, {0.955, 0.86, 0.18}},
}
// A myrtle, Venus's tree, clipped round in a bronze pot in the (+x, +y) corner.
@(private)
MYRTLE_PX := [?]Box {
	{{0.785, 0.785, 0.16}, {0.815, 0.815, 0.3}},
	{{0.67, 0.67, 0.28}, {0.93, 0.93, 0.44}},
	{{0.7, 0.7, 0.44}, {0.9, 0.9, 0.51}},
	{{0.64, 0.72, 0.31}, {0.96, 0.88, 0.41}},
}
@(private)
MYRTLE_POT_PX := [?]Box {
	{{0.69, 0.69, 0}, {0.91, 0.91, 0.03}},
	{{0.67, 0.67, 0.03}, {0.93, 0.93, 0.15}},
	{{0.65, 0.65, 0.15}, {0.95, 0.95, 0.18}},
}
@(private)
CAIRN_PX := [?]Box {
	{{0.68, 0.68, 0}, {0.94, 0.94, 0.07}},
	{{0.71, 0.72, 0.07}, {0.9, 0.9, 0.13}},
	{{0.74, 0.75, 0.13}, {0.87, 0.86, 0.19}},
	{{0.77, 0.78, 0.19}, {0.84, 0.84, 0.27}},
}

// The forest's pieces.
// The hand ropes of a rope bridge along the +x side of the cell: a hand rope,
// a foot rope along the deck, two hangers between them.
@(private)
ROPE_PX := [?]Box {
	{{0.92, 0, 0.6}, {0.96, 1, 0.64}},
	{{0.93, 0, 0.0}, {0.96, 1, 0.035}},
	{{0.935, 0.24, 0.0}, {0.95, 0.26, 0.6}},
	{{0.935, 0.74, 0.0}, {0.95, 0.76, 0.6}},
}
// a fallen trunk lying along the +x side, a broken branch toward the cell
@(private)
LOG_PX := [?]Box {
	{{0.7, 0.02, 0}, {0.94, 0.98, 0.2}},
	{{0.73, 0.0, 0.02}, {0.91, 0.04, 0.18}},
	{{0.58, 0.3, 0.07}, {0.7, 0.36, 0.13}},
	{{0.76, 0.62, 0.2}, {0.84, 0.7, 0.26}},
}
// the crag's pieces: a low lip of broken rock along the +x side
@(private)
LIP_PX := [?]Box {
	{{0.74, 0.0, 0}, {0.97, 0.36, 0.22}},
	{{0.77, 0.32, 0}, {0.98, 0.7, 0.15}},
	{{0.72, 0.66, 0}, {0.96, 1.0, 0.25}},
	{{0.8, 0.42, 0.15}, {0.95, 0.6, 0.23}},
}
// a fir: a straight trunk, the crown in tiers narrowing to the tip
@(private)
SPRUCE_TRUNK := [?]Box{{{0.44, 0.44, 0}, {0.56, 0.56, 0.42}}}
@(private)
spruce :: proc() -> []Box {
	out := make([dynamic]Box, 0, 16, context.temp_allocator)
	z: f32 = 0.3
	for k in 0 ..< 6 {
		w := 0.4 - f32(k) * 0.058
		append(&out, Box{{0.5 - w, 0.5 - w, z}, {0.5 + w, 0.5 + w, z + 0.13}})
		v := w * 0.62
		append(&out, Box{{0.5 - v, 0.5 - v, z + 0.13}, {0.5 + v, 0.5 + v, z + 0.25}})
		z += 0.25
	}
	append(&out, Box{{0.47, 0.47, z}, {0.53, 0.53, z + 0.14}})
	return out[:]
}
// the deck of a rope bridge running along x: four slats across it on two
// stringers, the top flush with the surface
@(private)
plank_x :: proc() -> []Box {
	out := make([dynamic]Box, 0, 8, context.temp_allocator)
	append(&out, Box{{0, 0.1, 0.8}, {1, 0.18, 0.88}})
	append(&out, Box{{0, 0.82, 0.8}, {1, 0.9, 0.88}})
	for i in 0 ..< 4 {
		a := f32(i) * 0.25 + 0.02
		append(&out, Box{{a, 0.04, 0.88}, {a + 0.21, 0.96, 1.0}})
	}
	return out[:]
}

// The mouth of a cave in the rock face on the +x side of the cell (the face
// at x = 1): rough stones around an arched opening, a fallen one at its foot.
@(private)
CAVE_PX := [?]Box {
	{{0.88, 0.13, 0}, {1.0, 0.26, 0.56}}, // the jambs
	{{0.9, 0.16, 0.56}, {1.0, 0.3, 0.7}},
	{{0.88, 0.74, 0}, {1.0, 0.87, 0.5}},
	{{0.9, 0.7, 0.5}, {1.0, 0.84, 0.68}},
	{{0.89, 0.2, 0.68}, {1.0, 0.37, 0.8}}, // the arch
	{{0.89, 0.63, 0.66}, {1.0, 0.8, 0.78}},
	{{0.86, 0.3, 0.76}, {1.0, 0.7, 0.88}},
	{{0.7, 0.1, 0}, {0.84, 0.25, 0.11}}, // a fallen stone
	{{0.76, 0.78, 0}, {0.86, 0.9, 0.07}},
}
@(private)
CAVE_DARK_PX := [?]Box {
	{{0.955, 0.26, 0}, {1.0, 0.74, 0.54}},
	{{0.955, 0.3, 0.54}, {1.0, 0.7, 0.68}},
	{{0.955, 0.36, 0.68}, {1.0, 0.64, 0.77}},
}

// A standing candelabrum about its own foot (0, 0): a round foot, a slender
// shaft with a knot, a bar with three cups; the candles are their own piece.
@(private)
CANDELABRUM := [?]Box {
	{{-0.08, -0.08, 0}, {0.08, 0.08, 0.025}},
	{{-0.05, -0.05, 0.025}, {0.05, 0.05, 0.05}},
	{{-0.016, -0.016, 0.05}, {0.016, 0.016, 0.86}},
	{{-0.032, -0.032, 0.42}, {0.032, 0.032, 0.47}},
	{{-0.14, -0.012, 0.84}, {0.14, 0.012, 0.865}},
	{{-0.165, -0.03, 0.865}, {-0.105, 0.03, 0.885}},
	{{-0.03, -0.03, 0.865}, {0.03, 0.03, 0.885}},
	{{0.105, -0.03, 0.865}, {0.165, 0.03, 0.885}},
}
@(private)
CANDELABRUM_WAX := [?]Box {
	{{-0.15, -0.014, 0.885}, {-0.12, 0.014, 0.97}},
	{{-0.015, -0.015, 0.885}, {0.015, 0.015, 1.0}},
	{{0.12, -0.014, 0.885}, {0.15, 0.014, 0.97}},
}
// Where its three flames burn, about its foot.
CANDELABRUM_FLAMES :: [3][3]f32{{-0.135, 0, 0.995}, {0, 0, 1.025}, {0.135, 0, 0.995}}

@(private)
at_corner :: proc(list: []Box, c: [2]f32) -> []Box {
	out := make([]Box, len(list), context.temp_allocator)
	for b, i in list {
		o := [3]f32{c.x, c.y, 0}
		out[i] = {b.lo + o, b.hi + o}
	}
	return out
}

// --- figures -------------------------------------------------------------------------

// A sister of Psyche in marble: Psyche's robed figure, larger, on a plinth,
// one arm raised toward d as if calling from the crag.
@(private)
statue :: proc(d: iso.Dir) -> rl.Mesh {
	S :: 1.45 // larger than life
	BASE :: 0.26
	b := builder_make()
	boxes(&b, oriented({{{0.22, 0.22, 0}, {0.78, 0.78, 0.07}}, {{0.27, 0.27, 0.07}, {0.73, 0.73, BASE}}}, d))
	robe: [len(ROBE_PROFILE)][2]f32
	for p, i in ROBE_PROFILE {
		robe[i] = p * S
	}
	lathe(&b, robe[:], 14, {0.5, 0.5, BASE})
	sphere(&b, {0.5, 0.5, BASE + 0.548 * S}, 0.048 * S, 7, 12)
	// the arm: out from the shoulder, then the forearm raised
	sh: f32 = BASE + 0.42 * S
	boxes(&b, oriented({{{0.55, 0.47, sh - 0.03}, {0.74, 0.53, sh + 0.02}}, {{0.7, 0.47, sh + 0.02}, {0.75, 0.53, sh + 0.2}}}, d))
	return upload(&b)
}

// Psyche: a slender robed figure about 0.6 cells tall, abstract on purpose.
@(private)
ROBE_PROFILE := [?][2]f32 {
	{0.0, 0.0}, {0.115, 0.0}, {0.1, 0.06}, {0.078, 0.2}, {0.058, 0.32}, {0.05, 0.36},
	{0.062, 0.4}, {0.066, 0.44}, {0.056, 0.47}, {0.03, 0.49}, {0.02, 0.5}, {0.0, 0.5},
}
// Cupid: broader shoulders, a little taller.
@(private)
ROBE_CUPID_PROFILE := [?][2]f32 {
	{0.0, 0.0}, {0.1, 0.0}, {0.09, 0.08}, {0.07, 0.24}, {0.062, 0.36}, {0.074, 0.44},
	{0.084, 0.5}, {0.07, 0.53}, {0.03, 0.55}, {0.022, 0.56}, {0.0, 0.56},
}
// The fragment of the tale: a papyrus roll with wider ends, along z (laid down when drawn).
@(private)
SCROLL_PROFILE := [?][2]f32 {
	{0.0, 0.0}, {0.06, 0.0}, {0.06, 0.03}, {0.045, 0.035}, {0.045, 0.245}, {0.06, 0.25}, {0.06, 0.28}, {0.0, 0.28},
}
@(private)
LAMP_PROFILE := [?][2]f32{{0.0, 0.0}, {0.02, 0.0}, {0.045, 0.02}, {0.05, 0.035}, {0.03, 0.04}, {0.0, 0.04}}

// Build every mesh once.
build_meshes :: proc(meshes: ^[Mesh_Id]rl.Mesh) {
	one :: proc(list: []Box) -> rl.Mesh {
		b := builder_make()
		boxes(&b, list)
		return upload(&b)
	}
	four :: proc(meshes: ^[Mesh_Id]rl.Mesh, base: Mesh_Id, list: []Box) {
		for d in iso.Dir {
			meshes[oriented_mesh(base, d)] = one(oriented(list, d))
		}
	}
	meshes[.Block] = one({{{0, 0, 0}, {1, 1, 1}}})
	four(meshes, .Stairs_PX, stairs_px())
	four(meshes, .Rail_PX, rail_px())
	four(meshes, .Wall_PX, WALL_PX[:])
	four(meshes, .Wall_Half_PX, WALL_HALF_PX[:])
	four(meshes, .Battlement_PX, BATTLEMENT_PX[:])
	four(meshes, .Fence_PX, FENCE_PX[:])
	four(meshes, .Rope_PX, ROPE_PX[:])
	four(meshes, .Log_PX, LOG_PX[:])
	four(meshes, .Lip_PX, LIP_PX[:])
	four(meshes, .Bed_PX, bed_px())
	four(meshes, .Arch_PX, ARCH_PX[:])
	four(meshes, .Sconce_PX, SCONCE_PX[:])
	four(meshes, .Reeds_PX, reeds_px())
	four(meshes, .Candle_PX, CANDLE_PX[:])
	four(meshes, .Pine_PX, PINE_PX[:])
	four(meshes, .Trunk_PX, PINE_TRUNK_PX[:])
	four(meshes, .Boulder_PX, BOULDER_PX[:])
	four(meshes, .Shrub_PX, SHRUB_PX[:])
	four(meshes, .Cairn_PX, CAIRN_PX[:])
	four(meshes, .Rose_PX, ROSE_PX[:])
	four(meshes, .Rose_Bloom_PX, ROSE_BLOOM_PX[:])
	four(meshes, .Myrtle_PX, MYRTLE_PX[:])
	four(meshes, .Myrtle_Pot_PX, MYRTLE_POT_PX[:])
	four(meshes, .Cave_PX, CAVE_PX[:])
	four(meshes, .Cave_Dark_PX, CAVE_DARK_PX[:])
	meshes[.Pillar] = one(PILLAR[:])
	meshes[.Plinth] = one(PLINTH[:])
	meshes[.Cypress] = one(cypress())
	meshes[.Spruce] = one(spruce())
	meshes[.Spruce_Trunk] = one(SPRUCE_TRUNK[:])
	{
		// the heap of seeds Venus poured out: a low round mound
		hb := builder_make()
		lathe(&hb, {{0.0, 0.0}, {0.45, 0.0}, {0.42, 0.07}, {0.35, 0.17}, {0.25, 0.27}, {0.13, 0.35}, {0.04, 0.39}, {0.0, 0.4}}, 18, {0.5, 0.5, 0})
		meshes[.Heap] = upload(&hb)
	}
	meshes[.Plank_X] = one(plank_x())
	meshes[.Plank_Y] = one(oriented(plank_x(), .PY))
	meshes[.Urn] = one(URN[:])
	meshes[.Brazier] = one(BRAZIER[:])
	meshes[.Sigil_Off] = one(SIGIL_OFF[:])
	meshes[.Sigil_On] = one(SIGIL_ON[:])
	{
		// a tripod brazier: three thin legs under a wide shallow bowl
		a := builder_make()
		f := ALTAR_FLAME
		boxes(&a, {
			{{f.x - 0.1, f.y - 0.015, 0}, {f.x - 0.07, f.y + 0.015, 0.3}},
			{{f.x + 0.04, f.y + 0.05, 0}, {f.x + 0.07, f.y + 0.08, 0.3}},
			{{f.x + 0.04, f.y - 0.08, 0}, {f.x + 0.07, f.y - 0.05, 0.3}},
		})
		lathe(&a, {{0.0, 0.28}, {0.07, 0.28}, {0.15, 0.34}, {0.15, 0.37}, {0.12, 0.36}, {0.0, 0.33}}, 14, {f.x, f.y, 0})
		meshes[.Altar] = upload(&a)
	}
	meshes[.Crank_Post] = one({{{0.76, 0.76, 0}, {0.84, 0.84, 0.42}}, {{0.7, 0.7, 0}, {0.9, 0.9, 0.05}}})
	{
		// a capstan: a ring on four spokes, with four upright grips
		w := builder_make()
		lathe(&w, {{0.14, 0.0}, {0.19, 0.0}, {0.19, 0.04}, {0.14, 0.04}, {0.14, 0.0}}, 20)
		lathe(&w, {{0.0, 0.0}, {0.045, 0.0}, {0.045, 0.06}, {0.0, 0.06}}, 10)
		boxes(&w, {
			{{-0.17, -0.012, 0.01}, {0.17, 0.012, 0.035}},
			{{-0.012, -0.17, 0.01}, {0.012, 0.17, 0.035}},
			{{0.19, -0.015, 0.0}, {0.22, 0.015, 0.12}},
			{{-0.22, -0.015, 0.0}, {-0.19, 0.015, 0.12}},
			{{-0.015, 0.19, 0.0}, {0.015, 0.22, 0.12}},
			{{-0.015, -0.22, 0.0}, {0.015, -0.19, 0.12}},
		})
		meshes[.Crank_Wheel] = upload(&w)
	}

	lathe_mesh :: proc(profile: [][2]f32, segments: int) -> rl.Mesh {
		b := builder_make()
		lathe(&b, profile, segments)
		return upload(&b)
	}
	meshes[.Robe] = lathe_mesh(ROBE_PROFILE[:], 14)
	meshes[.Robe_Cupid] = lathe_mesh(ROBE_CUPID_PROFILE[:], 14)
	meshes[.Lamp] = lathe_mesh(LAMP_PROFILE[:], 10)
	meshes[.Scroll] = lathe_mesh(SCROLL_PROFILE[:], 12)
	for d in iso.Dir {
		// the (+x, +y) corner, turned with the piece like the oriented boxes
		c := [2]f32{0.8, 0.8}
		switch d {
		case .PX:
		case .PY: c = {1 - c.y, c.x}
		case .MX: c = {1 - c.x, 1 - c.y}
		case .MY: c = {c.y, 1 - c.x}
		}
		vb := builder_make()
		lathe(&vb, VASE_PROFILE[:], 12, {c.x, c.y, 0})
		meshes[oriented_mesh(.Vase_PX, d)] = upload(&vb)
		meshes[oriented_mesh(.Statue_PX, d)] = statue(d)
		cb := builder_make()
		boxes(&cb, at_corner(CANDELABRUM[:], c))
		meshes[oriented_mesh(.Candelabrum_PX, d)] = upload(&cb)
		wb := builder_make()
		boxes(&wb, at_corner(CANDELABRUM_WAX[:], c))
		meshes[oriented_mesh(.Candelabrum_Wax_PX, d)] = upload(&wb)
	}
	b := builder_make()
	sphere(&b, {}, 1, 7, 12)
	meshes[.Head] = upload(&b)
}

unload_meshes :: proc(meshes: ^[Mesh_Id]rl.Mesh) {
	for &m in meshes {
		rl.UnloadMesh(m)
		m = {}
	}
}
