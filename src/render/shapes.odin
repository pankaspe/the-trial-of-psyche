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
	Bed_PX, Bed_MX, Bed_PY, Bed_MY,
	Arch_PX, Arch_MX, Arch_PY, Arch_MY,
	Vase_PX, Vase_MX, Vase_PY, Vase_MY,
	Sconce_PX, Sconce_MX, Sconce_PY, Sconce_MY,
	Candle_PX, Candle_MX, Candle_PY, Candle_MY,
	Pillar,
	Plinth,
	Cypress,
	Urn,
	Brazier,
	Sigil_Off,
	Sigil_On,
	Robe,
	Robe_Cupid,
	Head,
	Lamp,
	Scroll,
}

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
}

PROP_MESH := [level.Prop_Kind]Mesh_Id {
	.Rail            = .Rail_PX,
	.Wall            = .Wall_PX,
	.Wall_Half       = .Wall_Half_PX,
	.Wall_Battlement = .Battlement_PX,
	.Fence           = .Fence_PX,
	.Pillar          = .Pillar,
	.Plinth          = .Plinth,
	.Cypress         = .Cypress,
	.Urn             = .Urn,
	.Brazier         = .Brazier,
	.Bed             = .Bed_PX,
	.Arch            = .Arch_PX,
	.Vase            = .Vase_PX,
	.Sconce          = .Sconce_PX,
}

PROP_MATERIAL := [level.Prop_Kind]Material {
	.Rail            = .Marble,
	.Wall            = .Masonry,
	.Wall_Half       = .Masonry,
	.Wall_Battlement = .Masonry,
	.Fence           = .Bronze,
	.Pillar          = .Marble,
	.Plinth          = .Marble,
	.Cypress         = .Foliage,
	.Urn             = .Bronze,
	.Brazier         = .Bronze,
	.Bed             = .Bronze,
	.Arch            = .Masonry,
	.Vase            = .Bronze,
	.Sconce          = .Bronze,
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
BATTLEMENT_PX := [?]Box {
	{{0.78, 0, 0}, {1, 1, 0.4}},
	{{0.78, 0, 0.4}, {1, 0.3, 0.62}},
	{{0.78, 0.7, 0.4}, {1, 1, 0.62}},
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
// arm and cup in bronze; the candle (unlit) is its own piece
@(private)
SCONCE_PX := [?]Box {
	{{1.0, 0.42, 0.38}, {1.03, 0.58, 0.68}},
	{{1.03, 0.47, 0.48}, {1.12, 0.53, 0.53}},
	{{1.06, 0.41, 0.53}, {1.18, 0.59, 0.58}},
}
@(private)
CANDLE_PX := [?]Box{{{1.095, 0.465, 0.58}, {1.145, 0.535, 0.8}}}
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

// --- figures -------------------------------------------------------------------------

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
	four(meshes, .Bed_PX, bed_px())
	four(meshes, .Arch_PX, ARCH_PX[:])
	four(meshes, .Sconce_PX, SCONCE_PX[:])
	four(meshes, .Candle_PX, CANDLE_PX[:])
	meshes[.Pillar] = one(PILLAR[:])
	meshes[.Plinth] = one(PLINTH[:])
	meshes[.Cypress] = one(cypress())
	meshes[.Urn] = one(URN[:])
	meshes[.Brazier] = one(BRAZIER[:])
	meshes[.Sigil_Off] = one(SIGIL_OFF[:])
	meshes[.Sigil_On] = one(SIGIL_ON[:])

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
