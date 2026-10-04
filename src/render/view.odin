// The camera. The diorama is drawn in true 3D with a hand-made projection
// that is exactly the prototype's isometric formula:
//   X = (x' - y') * 64,  Y = (x' + y') * 32 - z' * 64   (proto pixels)
// where (x', y', z') is the world point turned by the view angle about the
// centre of the grid. Its kernel is the direction (1, 1, 1), so the 3D scene
// keeps every illusion of the 2D grid, while the z-buffer resolves overlaps
// and the rotation is continuous.
package render

import "core:math"
import rl "vendor:raylib"

import "../iso"

Rect :: struct {
	x, y, w, h: f32,
}

rect_merge :: proc(a, b: Rect) -> Rect {
	x0, y0 := min(a.x, b.x), min(a.y, b.y)
	x1, y1 := max(a.x + a.w, b.x + b.w), max(a.y + a.h, b.y + b.h)
	return {x0, y0, x1 - x0, y1 - y0}
}

View :: struct {
	width, height: f32, // screen size in pixels
	zoom:          f32, // screen pixels per proto pixel
	center:        Vec2, // proto pixel shown at the centre of the screen
	shake:         Vec2, // screen pixels
	angle:         f32, // view angle in quarter turns
	size:          i32, // grid size
	depth_mid:     f32,
	depth_range:   f32,
}

// Frame the diorama: it must fit the screen from all four views.
make_view :: proc(fit: Rect, width, height, angle: f32, size, height_cells: i32, shake: Vec2) -> View {
	z := min(width / (fit.w + 260), height / (fit.h + 300))
	return {
		width = width,
		height = height,
		zoom = clamp(z, 0.35, 4.0),
		center = {fit.x + fit.w * 0.5, fit.y + fit.h * 0.5 + 40},
		shake = shake,
		angle = angle,
		size = size,
		depth_mid = f32(size) + f32(height_cells) * 0.5,
		depth_range = 4 * f32(size) + 2 * f32(height_cells) + 40,
	}
}

proto_to_screen :: proc(v: View, q: Vec2) -> Vec2 {
	return (q - v.center) * v.zoom + Vec2{v.width, v.height} * 0.5 + v.shake
}

screen_to_proto :: proc(v: View, s: Vec2) -> Vec2 {
	return (s - Vec2{v.width, v.height} * 0.5 - v.shake) / v.zoom + v.center
}

world_to_proto :: proc(v: View, p: Vec3) -> Vec2 {
	return iso.project(iso.view_point(p, v.angle, v.size))
}

world_to_screen :: proc(v: View, p: Vec3) -> Vec2 {
	return proto_to_screen(v, world_to_proto(v, p))
}

@(private)
view_trig :: proc(v: View) -> (a, b: f32) {
	th := v.angle * math.PI * 0.5
	return math.cos(th), math.sin(th)
}

// World direction whose dot product grows toward the camera (painter's depth).
depth_axis :: proc(v: View) -> Vec3 {
	a, b := view_trig(v)
	return {a + b, a - b, 1}
}

// World xy direction that points right on screen.
screen_right_xy :: proc(v: View) -> Vec2 {
	a, b := view_trig(v)
	return Vec2{a - b, -(a + b)} / math.SQRT_TWO
}

// World vectors for one proto pixel right / up on screen, at constant depth:
// billboards are built from these.
billboard_axes :: proc(v: View) -> (right, up: Vec3) {
	a, b := view_trig(v)
	right = {(a - b) / 128, -(a + b) / 128, 0}
	up = {-(a + b) / 192, -(a - b) / 192, 1.0 / 96}
	return
}

// World -> clip space: the projection above, then zoom, framing and shake.
// Depth: nearer (larger x'+y'+z') maps to smaller clip z.
clip_matrix :: proc(v: View) -> rl.Matrix {
	a, b := view_trig(v)
	h := f32(v.size) * 0.5
	kx := v.zoom / (v.width * 0.5)
	ky := -v.zoom / (v.height * 0.5)
	dr := v.depth_range
	sx := v.shake.x / (v.width * 0.5)
	sy := -v.shake.y / (v.height * 0.5)
	return rl.Matrix {
		64 * (a - b) * kx, -64 * (a + b) * kx, 0, (128 * b * h - v.center.x) * kx + sx,
		32 * (a + b) * ky, 32 * (a - b) * ky, -64 * ky, (64 * h * (1 - a) - v.center.y) * ky + sy,
		-(a + b) / dr, -(a - b) / dr, -1 / dr, -(2 * h * (1 - a) - v.depth_mid) / dr,
		0, 0, 0, 1,
	}
}
