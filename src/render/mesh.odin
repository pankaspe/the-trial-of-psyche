// Mesh generation: every piece of the palace is a list of axis-aligned boxes
// in cell space (0..1 on x/y, z up from the cell floor), the same description
// the prototype's tools/bake_props.py used to paint its sprites. Figures are
// surfaces of revolution.
//
// Memory: vertices are built in the temp allocator and uploaded to the GPU;
// the CPU copies are then dropped (the mesh keeps only its VAO/VBO ids).
package render

import "core:math"
import rl "vendor:raylib"

import "../iso"

Vec2 :: iso.Vec2
Vec3 :: iso.Vec3

Box :: struct {
	lo, hi: Vec3,
}

Mesh_Builder :: struct {
	verts: [dynamic]f32,
	norms: [dynamic]f32,
}

builder_make :: proc() -> Mesh_Builder {
	return {make([dynamic]f32, 0, 1024, context.temp_allocator), make([dynamic]f32, 0, 1024, context.temp_allocator)}
}

@(private)
vertex :: proc(b: ^Mesh_Builder, p, n: Vec3) {
	append(&b.verts, p.x, p.y, p.z)
	append(&b.norms, n.x, n.y, n.z)
}

quad :: proc(b: ^Mesh_Builder, p0, p1, p2, p3, n: Vec3) {
	vertex(b, p0, n)
	vertex(b, p1, n)
	vertex(b, p2, n)
	vertex(b, p0, n)
	vertex(b, p2, n)
	vertex(b, p3, n)
}

// A box without its bottom face (the camera always looks down on the palace).
box :: proc(b: ^Mesh_Builder, bx: Box) {
	l, h := bx.lo, bx.hi
	quad(b, {l.x, l.y, h.z}, {h.x, l.y, h.z}, {h.x, h.y, h.z}, {l.x, h.y, h.z}, {0, 0, 1})
	quad(b, {h.x, l.y, l.z}, {h.x, h.y, l.z}, {h.x, h.y, h.z}, {h.x, l.y, h.z}, {1, 0, 0})
	quad(b, {l.x, l.y, l.z}, {l.x, h.y, l.z}, {l.x, h.y, h.z}, {l.x, l.y, h.z}, {-1, 0, 0})
	quad(b, {l.x, h.y, l.z}, {h.x, h.y, l.z}, {h.x, h.y, h.z}, {l.x, h.y, h.z}, {0, 1, 0})
	quad(b, {l.x, l.y, l.z}, {h.x, l.y, l.z}, {h.x, l.y, h.z}, {l.x, l.y, h.z}, {0, -1, 0})
}

boxes :: proc(b: ^Mesh_Builder, list: []Box) {
	for bx in list {
		box(b, bx)
	}
}

// Surface of revolution about the z axis; profile points are (radius, z) from
// bottom to top. Faceted along the profile, smooth around it.
lathe :: proc(b: ^Mesh_Builder, profile: [][2]f32, segments: int, center: Vec3 = {}) {
	for i in 0 ..< len(profile) - 1 {
		p, q := profile[i], profile[i + 1]
		// outward normal of the profile segment, in (radial, z)
		nr, nz := q.y - p.y, -(q.x - p.x)
		l := math.sqrt(nr * nr + nz * nz)
		if l < 1e-6 {
			continue
		}
		nr, nz = nr / l, nz / l
		for s in 0 ..< segments {
			a0 := f32(s) / f32(segments) * math.TAU
			a1 := f32(s + 1) / f32(segments) * math.TAU
			c0, s0 := math.cos(a0), math.sin(a0)
			c1, s1 := math.cos(a1), math.sin(a1)
			v00 := center + Vec3{p.x * c0, p.x * s0, p.y}
			v01 := center + Vec3{p.x * c1, p.x * s1, p.y}
			v10 := center + Vec3{q.x * c0, q.x * s0, q.y}
			v11 := center + Vec3{q.x * c1, q.x * s1, q.y}
			n0 := Vec3{nr * c0, nr * s0, nz}
			n1 := Vec3{nr * c1, nr * s1, nz}
			vertex(b, v00, n0)
			vertex(b, v01, n1)
			vertex(b, v11, n1)
			vertex(b, v00, n0)
			vertex(b, v11, n1)
			vertex(b, v10, n0)
		}
	}
}

// A sphere as a lathe of a half circle.
sphere :: proc(b: ^Mesh_Builder, center: Vec3, radius: f32, rings, segments: int) {
	profile := make([][2]f32, rings + 1, context.temp_allocator)
	for i in 0 ..= rings {
		a := f32(i) / f32(rings) * math.PI
		profile[i] = {math.sin(a) * radius, -math.cos(a) * radius}
	}
	lathe(b, profile, segments, center)
}

// Send the builder's triangles to the GPU.
upload :: proc(b: ^Mesh_Builder) -> rl.Mesh {
	m: rl.Mesh
	m.vertexCount = i32(len(b.verts) / 3)
	m.triangleCount = m.vertexCount / 3
	m.vertices = raw_data(b.verts)
	m.normals = raw_data(b.norms)
	rl.UploadMesh(&m, false)
	// the arrays belong to the temp allocator: raylib must not free or reuse them
	m.vertices = nil
	m.normals = nil
	return m
}

// Rotate boxes designed for +x into direction d (about the cell centre).
oriented :: proc(list: []Box, d: iso.Dir, allocator := context.temp_allocator) -> []Box {
	out := make([]Box, len(list), allocator)
	for bx, i in list {
		l, h := bx.lo, bx.hi
		switch d {
		case .PX:
			out[i] = bx
		case .PY: // (x, y) -> (1 - y, x)
			out[i] = {{1 - h.y, l.x, l.z}, {1 - l.y, h.x, h.z}}
		case .MX: // (x, y) -> (1 - x, 1 - y)
			out[i] = {{1 - h.x, 1 - h.y, l.z}, {1 - l.x, 1 - l.y, h.z}}
		case .MY: // (x, y) -> (y, 1 - x)
			out[i] = {{l.y, 1 - h.x, l.z}, {h.y, 1 - l.x, h.z}}
		}
	}
	return out
}
