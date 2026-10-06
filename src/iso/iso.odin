// Isometric grid math shared by every package.
//
// Cell (x, y, z) spans [x, x+1] x [y, y+1] x [z, z+1]; +x runs down-right on
// screen, +y down-left, +z up. The projection maps the world direction (1, 1, 1)
// to zero, so (x+1, y+1, z+1) lands exactly on (x, y, z): the source of every
// illusion. Walls are as tall as the top diamond is high.
//
// "Proto pixels" are the screen units of this projection at zoom 1: a cell is
// 128 px wide, its top diamond 64 px tall, its wall 64 px tall.
package iso

import "core:math"

Cell :: [3]i32
Vec2 :: [2]f32
Vec3 :: [3]f32

HALF_W :: 64.0
HALF_H :: 32.0
WALL :: 64.0

// The four grid directions. Kenney-style names: px = +x, mx = -x, py = +y, my = -y.
Dir :: enum u8 {
	PX,
	MX,
	PY,
	MY,
}

Dirs :: bit_set[Dir;u8]

DIR_VEC := [Dir][2]i32 {
	.PX = {1, 0},
	.MX = {-1, 0},
	.PY = {0, 1},
	.MY = {0, -1},
}

DIR_NAME := [Dir]string {
	.PX = "px",
	.MX = "mx",
	.PY = "py",
	.MY = "my",
}

dir_from_name :: proc(name: string) -> (d: Dir, ok: bool) {
	for n, k in DIR_NAME {
		if n == name {
			return k, true
		}
	}
	return .PX, false
}

dir_from_vec :: proc(v: [2]i32) -> (d: Dir, ok: bool) {
	for dv, k in DIR_VEC {
		if dv == v {
			return k, true
		}
	}
	return .PX, false
}

opposite :: proc(d: Dir) -> Dir {
	switch d {
	case .PX: return .MX
	case .MX: return .PX
	case .PY: return .MY
	case .MY: return .PY
	}
	return d
}

// Rotate a grid vector by r quarter turns: (x, y) -> (-y, x) each turn.
rot_vec :: proc(v: [2]i32, r: int) -> [2]i32 {
	out := v
	for _ in 0 ..< ((r % 4) + 4) % 4 {
		out = {-out.y, out.x}
	}
	return out
}

rot_dir :: proc(d: Dir, r: int) -> Dir {
	out, _ := dir_from_vec(rot_vec(DIR_VEC[d], r))
	return out
}

// World cell -> view cell for view r: (x, y) -> (size-1-y, x), r times.
to_view :: proc(c: Cell, r: int, size: i32) -> Cell {
	x, y := c.x, c.y
	for _ in 0 ..< ((r % 4) + 4) % 4 {
		x, y = size - 1 - y, x
	}
	return {x, y, c.z}
}

// A world point seen from the continuous view angle (in quarter turns),
// rotated about the vertical axis through the centre of the size x size grid.
view_point :: proc(p: Vec3, angle: f32, size: i32) -> Vec3 {
	th := angle * math.PI * 0.5
	h := f32(size) * 0.5
	c, s := math.cos(th), math.sin(th)
	cx, cy := p.x - h, p.y - h
	return {cx * c - cy * s + h, cx * s + cy * c + h, p.z}
}

// Inverse of view_point.
world_point :: proc(v: Vec3, angle: f32, size: i32) -> Vec3 {
	return view_point(v, -angle, size)
}

// Rotate a world direction (no translation) into the view.
view_vector :: proc(v: Vec3, angle: f32) -> Vec3 {
	th := angle * math.PI * 0.5
	c, s := math.cos(th), math.sin(th)
	return {v.x * c - v.y * s, v.x * s + v.y * c, v.z}
}

world_vector :: proc(v: Vec3, angle: f32) -> Vec3 {
	return view_vector(v, -angle)
}

// View-space point -> proto pixels.
project :: proc(v: Vec3) -> Vec2 {
	return {(v.x - v.y) * HALF_W, (v.x + v.y) * HALF_H - v.z * WALL}
}

// Painter's depth of a view-space point: larger is nearer to the camera.
depth :: proc(v: Vec3) -> f32 {
	return v.x + v.y + v.z
}

// Screen position (proto px) of the centre of the floor of view cell v.
floor_center :: proc(v: Cell) -> Vec2 {
	return project({f32(v.x) + 0.5, f32(v.y) + 0.5, f32(v.z)})
}

in_diamond :: proc(point, center: Vec2, scale: f32 = 1) -> bool {
	d := point - center
	return abs(d.x) / (HALF_W * scale) + abs(d.y) / (HALF_H * scale) <= 1
}

manhattan2 :: proc(a, b: Cell) -> i32 {
	return abs(a.x - b.x) + abs(a.y - b.y)
}
