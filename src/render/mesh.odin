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

// A tube swept along `path` (at least two points), its radius at each point
// from `radius`; smooth around, faceted along, the ends left open.
tube :: proc(b: ^Mesh_Builder, path: []Vec3, radius: []f32, sides: int) {
	ring :: proc(path: []Vec3, radius: []f32, i, sides: int) -> (pts, nrm: [16]Vec3) {
		t := path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]
		t /= math.sqrt(t.x * t.x + t.y * t.y + t.z * t.z)
		// any vector not along the tangent makes the ring's frame
		up := abs(t.z) < 0.9 ? Vec3{0, 0, 1} : Vec3{1, 0, 0}
		u := linalg_cross(t, up)
		u /= math.sqrt(u.x * u.x + u.y * u.y + u.z * u.z)
		v := linalg_cross(t, u)
		for s in 0 ..< sides {
			a := f32(s) / f32(sides) * math.TAU
			n := u * math.cos(a) + v * math.sin(a)
			pts[s], nrm[s] = path[i] + n * radius[i], n
		}
		return
	}
	assert(sides <= 16)
	for i in 0 ..< len(path) - 1 {
		p0, n0 := ring(path, radius, i, sides)
		p1, n1 := ring(path, radius, i + 1, sides)
		for s in 0 ..< sides {
			k := (s + 1) % sides
			vertex(b, p0[s], n0[s])
			vertex(b, p0[k], n0[k])
			vertex(b, p1[k], n1[k])
			vertex(b, p0[s], n0[s])
			vertex(b, p1[k], n1[k])
			vertex(b, p1[s], n1[s])
		}
	}
}

@(private)
linalg_cross :: proc(a, b: Vec3) -> Vec3 {
	return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}

// Turn what was built since vertex `from` (counted in floats) from +z onto +x
// (a quarter about y): a lathe laid on its side.
lay_along_x :: proc(b: ^Mesh_Builder, from: int) {
	for i := from; i < len(b.verts); i += 3 {
		x, z := b.verts[i], b.verts[i + 2]
		b.verts[i], b.verts[i + 2] = z, -x
		nx, nz := b.norms[i], b.norms[i + 2]
		b.norms[i], b.norms[i + 2] = nz, -nx
	}
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
