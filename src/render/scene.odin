// Drawing the world: night sky, far islands, sea of clouds, the palace in 3D,
// Psyche and Cupid, cracks of the illusions, oil, glows and particles.
//
// Renderer: GPU resources, created once.
// Scene: what one level needs to be drawn (pieces, framing, particle pools);
// its arrays come from the level arena, so they vanish with the level.
package render

import "core:math"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

import "../content"
import "../fx"
import "../game"
import "../iso"
import "../level"
import pl "../palace"

Cell :: iso.Cell
Color4 :: [4]f32

LAMP_RADIUS :: 6.5 // world units lit by the lamp

Uniform :: enum u8 {
	Light_Amount,
	Flicker,
	Lamp_Pos,
	Lamp_Radius,
	View_Right,
	Depth_Axis,
	Depth_Min,
	Depth_Max,
	Mist_Top,
	Mist_Bottom,
	Screen_Height,
	Material,
	Detail,
	Hidden,
	Alpha,
	Shade_Soft,
	Glow,
}

@(private)
UNIFORM_NAME := [Uniform]cstring {
	.Light_Amount  = "light_amount",
	.Flicker       = "flicker",
	.Lamp_Pos      = "lamp_pos",
	.Lamp_Radius   = "lamp_radius",
	.View_Right    = "view_right",
	.Depth_Axis    = "depth_axis",
	.Depth_Min     = "depth_min",
	.Depth_Max     = "depth_max",
	.Mist_Top      = "mist_top",
	.Mist_Bottom   = "mist_bottom",
	.Screen_Height = "screen_height",
	.Material      = "material",
	.Detail        = "detail",
	.Hidden        = "hidden",
	.Alpha         = "alpha",
	.Shade_Soft    = "shade_soft",
	.Glow          = "glow",
}

Backdrop_Uniform :: enum u8 {
	Light_Amount,
	Shift,
	Time,
	Aspect,
	Tint,
	Density,
}

@(private)
BACKDROP_NAME := [Backdrop_Uniform]cstring {
	.Light_Amount = "light_amount",
	.Shift        = "shift",
	.Time         = "time",
	.Aspect       = "aspect",
	.Tint         = "tint",
	.Density      = "density",
}

Renderer :: struct {
	meshes:     [Mesh_Id]rl.Mesh,
	material:   rl.Material, // owns the palace shader
	loc:        [Uniform]i32,
	sky:        rl.Shader,
	sky_loc:    [Backdrop_Uniform]i32,
	clouds:     rl.Shader,
	clouds_loc: [Backdrop_Uniform]i32,
	radial:     rl.Texture2D, // soft round gradient for glows and particles
	white:      rl.Texture2D, // 1x1, for full-rect shader passes
}

init :: proc(r: ^Renderer) {
	shader := rl.LoadShaderFromMemory(content.SHADER_PALACE_VS, content.SHADER_PALACE_FS)
	r.material = rl.LoadMaterialDefault()
	r.material.shader = shader
	for name, u in UNIFORM_NAME {
		r.loc[u] = rl.GetShaderLocation(shader, name)
	}
	r.sky = rl.LoadShaderFromMemory(nil, content.SHADER_SKY_FS)
	r.clouds = rl.LoadShaderFromMemory(nil, content.SHADER_CLOUDS_FS)
	for name, u in BACKDROP_NAME {
		r.sky_loc[u] = rl.GetShaderLocation(r.sky, name)
		r.clouds_loc[u] = rl.GetShaderLocation(r.clouds, name)
	}
	build_meshes(&r.meshes)

	// radial gradient: white centre, 0.45 alpha at 35%, transparent edge
	SIZE :: 128
	pixels := make([]u8, SIZE * SIZE * 4, context.temp_allocator)
	for y in 0 ..< SIZE {
		for x in 0 ..< SIZE {
			d := math.sqrt(math.pow(f32(x) + 0.5 - SIZE / 2, 2) + math.pow(f32(y) + 0.5 - SIZE / 2, 2)) / (SIZE / 2)
			a: f32 = d < 0.35 ? 1 - (1 - 0.45) * d / 0.35 : 0.45 * max(1 - (d - 0.35) / 0.65, 0)
			i := (y * SIZE + x) * 4
			pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3] = 255, 255, 255, u8(a * 255)
		}
	}
	img := rl.Image{raw_data(pixels), SIZE, SIZE, 1, .UNCOMPRESSED_R8G8B8A8}
	r.radial = rl.LoadTextureFromImage(img)
	rl.SetTextureFilter(r.radial, .BILINEAR)
	white := [4]u8{255, 255, 255, 255}
	r.white = rl.LoadTextureFromImage(rl.Image{&white, 1, 1, 1, .UNCOMPRESSED_R8G8B8A8})
}

shutdown :: proc(r: ^Renderer) {
	unload_meshes(&r.meshes)
	rl.UnloadMaterial(r.material) // also unloads its shader
	rl.UnloadShader(r.sky)
	rl.UnloadShader(r.clouds)
	rl.UnloadTexture(r.radial)
	rl.UnloadTexture(r.white)
	r^ = {}
}

// --- per level -----------------------------------------------------------------------

Piece :: struct {
	cell:       Cell,
	mesh:       Mesh_Id,
	material:   Material,
	block:      bool, // marble on top, masonry when covered
	rise_index: i32, // >= 0: raised by the seal, in this order
	sigil:      enum u8 {
		None,
		Off, // only the lamp shows it, until it is lit
		On,
	},
}

Scene :: struct {
	pieces:     [dynamic]Piece,
	fit:        Rect, // proto pixels that hold the palace from every view
	motes:      fx.Pool(64), // drifting in front of everything (proto px)
	sparks:     fx.Pool(64), // around Cupid (world)
	dust:       fx.Pool(192), // falling from the cracks (world)
	wind:       fx.Pool(96), // Zephyr's breath over the exit (world)
	rng:        fx.Rng,
}

scene_build :: proc(s: ^Scene, g: ^game.Game, allocator := context.allocator) {
	s^ = {}
	s.pieces = make([dynamic]Piece, 0, len(g.data.blocks) + len(g.data.props) + len(g.data.rise) + 2, allocator)
	s.rng = fx.rng_init(1234)
	for e in g.data.blocks {
		append(&s.pieces, solid_piece(e.cell, e.solid, -1))
	}
	for prop in g.data.props {
		base := PROP_MESH[prop.kind]
		mesh := base
		if base >= .Stairs_PX && base <= .Arch_MY {
			mesh = oriented_mesh(base, prop.dir)
		}
		append(&s.pieces, Piece{cell = prop.cell, mesh = mesh, material = PROP_MATERIAL[prop.kind], rise_index = -1})
	}
	for e, i in g.data.rise {
		append(&s.pieces, solid_piece(e.cell, e.solid, i32(i)))
	}
	if g.data.has_sigil {
		append(&s.pieces, Piece{cell = g.data.sigil, mesh = .Sigil_Off, material = .Bronze, rise_index = -1, sigil = .Off})
		append(&s.pieces, Piece{cell = g.data.sigil, mesh = .Sigil_On, material = .Bronze, rise_index = -1, sigil = .On})
	}

	// framing: every piece from every view (as the prototype's fit_rect)
	first := true
	for p in s.pieces {
		for r in 0 ..< 4 {
			c := iso.floor_center(iso.to_view(p.cell, r, g.data.size))
			top: f32 = p.mesh == .Block ? -96 : -120
			rect := Rect{c.x - 64, c.y + top, 128, 152}
			s.fit = first ? rect : rect_merge(s.fit, rect)
			first = false
		}
	}
	// ambient motes start mid-life, as if they had always been there
	for _ in 0 ..< 40 {
		emit_mote(s, true)
	}
}

@(private)
solid_piece :: proc(c: Cell, solid: level.Solid, rise: i32) -> Piece {
	if solid.kind == .Stairs {
		return {cell = c, mesh = oriented_mesh(.Stairs_PX, solid.dir), material = .Marble, rise_index = rise}
	}
	return {cell = c, mesh = .Block, material = .Marble, block = true, rise_index = rise}
}

// Screen shake offset for this frame.
shake_offset :: proc(g: ^game.Game) -> Vec2 {
	if g.shake_t >= g.shake_duration {
		return {}
	}
	k := 1 - g.shake_t / g.shake_duration
	step := u32(g.shake_t / 0.05)
	return Vec2{(fx.hash01(step * 2) * 2 - 1) * 4, (fx.hash01(step * 2 + 1) * 2 - 1) * 3} * k
}

scene_view :: proc(s: ^Scene, g: ^game.Game, width, height: f32) -> View {
	return make_view(s.fit, width, height, g.angle, g.data.size, g.data.height, shake_offset(g))
}

// --- particles -------------------------------------------------------------------

@(private)
emit_mote :: proc(s: ^Scene, aged: bool) {
	c := Vec2{s.fit.x + s.fit.w * 0.5, s.fit.y + s.fit.h * 0.5}
	a := fx.rand_range(&s.rng, 0, math.TAU)
	v := fx.rand_range(&s.rng, 2, 10)
	p := fx.Particle {
		pos   = {c.x + fx.rand_range(&s.rng, -1, 1) * s.fit.w * 0.5, c.y + fx.rand_range(&s.rng, -1, 1) * s.fit.h * 0.5, 0},
		vel   = {math.cos(a) * v, math.sin(a) * v, 0},
		accel = {0, -6, 0},
		life  = 7,
		size  = 32 * fx.rand_range(&s.rng, 0.12, 0.3),
		color = {0.6, 0.7, 1.0, 0.5},
	}
	if aged {
		p.age = fx.rand_range(&s.rng, 0, p.life)
		p.pos += p.vel * p.age
	}
	fx.emit(&s.motes, p)
}

scene_update :: proc(s: ^Scene, g: ^game.Game, dt: f32) {
	if s.motes.count < 40 && fx.randf(&s.rng) < dt * 40 / 7 * 2 {
		emit_mote(s, false)
	}
	// golden motes around Cupid, more of them when he flies away
	if g.data.has_amore && g.collapse_t < 1.5 {
		want := g.amore.fly_t >= 0 ? 40 : 14
		if s.sparks.count < want && fx.randf(&s.rng) < dt * f32(want) / 7 * 2 {
			c := amore_position(g)
			a := fx.rand_range(&s.rng, 0, math.TAU)
			v := fx.rand_range(&s.rng, 2, 10) / 64
			fx.emit(&s.sparks, {
				pos   = c + {fx.rand_range(&s.rng, -0.3, 0.3), fx.rand_range(&s.rng, -0.3, 0.3), fx.rand_range(&s.rng, 0, 0.3)},
				vel   = {math.cos(a) * v, math.sin(a) * v, v},
				accel = {0, 0, 8.0 / 64},
				life  = 7,
				size  = 32 * fx.rand_range(&s.rng, 0.12, 0.3),
				color = {1.0, 0.85, 0.4, 0.9},
			})
		}
	}
	// Zephyr's breath: motes spiralling up from the exit, a gust when it takes Psyche
	alone_wind := g.phase == .Prologue && g.phase_t > game.prologue_alone(g) - 0.5
	if (g.data.has_exit && g.phase != .Finished && exit_alpha(g) > 0) || alone_wind {
		gust := g.phase == .Ending_Exit || alone_wind
		want := gust ? 60 : 40
		if s.wind.count < want && fx.randf(&s.rng) < dt * f32(want) / 3 * 2 {
			c := g.data.has_exit ? pl.node_world(&g.palace, g.data.exit) : g.psyche.pos
			if gust && (g.phase == .Ending_Exit || fx.randf(&s.rng) < 0.7) {
				c = g.psyche.pos
			}
			a := fx.rand_range(&s.rng, 0, math.TAU)
			r := fx.rand_range(&s.rng, 0.15, 0.45)
			swirl := Vec3{-math.sin(a), math.cos(a), 0} * 0.35
			fx.emit(&s.wind, {
				pos   = c + {math.cos(a) * r, math.sin(a) * r, fx.rand_range(&s.rng, 0, 0.2)},
				vel   = swirl + {0, 0, fx.rand_range(&s.rng, 0.25, 0.55) * (gust ? 2 : 1)},
				accel = -swirl * 0.6,
				life  = 3,
				size  = 32 * fx.rand_range(&s.rng, 0.14, 0.3),
				color = {0.8, 0.92, 1.0, 0.9},
			})
		}
	}
	// dust falling from the cracks while the lamp shows them
	if g.light > 0.5 && !g.turning && g.collapse_t < 0 {
		for e in g.palace.illusion.pairs {
			if fx.randf(&s.rng) < dt * 6 / 1.6 {
				p0, p1, _ := seam_edge(g, e)
				fx.emit(&s.dust, {
					pos   = fx.lerp(p0, p1, fx.randf(&s.rng)) + {0, 0, 0.01},
					vel   = {0, 0, -0.05},
					accel = {0, 0, -40.0 / 64},
					life  = 1.6,
					size  = 32 * fx.rand_range(&s.rng, 0.08, 0.16),
					color = {1.0, 0.85, 0.6, 0.7},
				})
			}
		}
	}
	fx.update(&s.motes, dt)
	fx.update(&s.sparks, dt)
	fx.update(&s.dust, dt)
	fx.update(&s.wind, dt)
}

// The exit shows once Zephyr is there: in the prologue, only when Psyche is left alone.
@(private)
exit_alpha :: proc(g: ^game.Game) -> f32 {
	if g.phase != .Prologue {
		return 1
	}
	return fx.clamp01((g.phase_t - game.prologue_alone(g)) / 2.5)
}

// Where Cupid is drawn (he rises when he flies away).
amore_position :: proc(g: ^game.Game) -> Vec3 {
	p := game.amore_world(g)
	if g.amore.fly_t >= 0 {
		p.z += 760.0 / 64 * fx.quad_in(fx.clamp01(g.amore.fly_t / 2.6))
	}
	p.z += 10.0 / 64 * g.amore.reveal
	return p
}

// The crack of illusion pair e: a segment on the top edge of its first
// surface, facing the second, plus the inward direction of that surface.
seam_edge :: proc(g: ^game.Game, e: [2]i32) -> (p0, p1, inward: Vec3) {
	pal := &g.palace
	a, b := pal.nodes[e[0]].cell, pal.nodes[e[1]].cell
	r := pal.rot
	av := iso.to_view(a, r, pal.size)
	bv := iso.to_view(b, r, pal.size)
	k := bv.z - av.z
	d := Vec2{f32(bv.x - av.x - k), f32(bv.y - av.y - k)}
	perp := Vec2{abs(d.y), abs(d.x)} * 0.5
	mid := Vec3{f32(av.x) + 0.5 + d.x * 0.5, f32(av.y) + 0.5 + d.y * 0.5, f32(av.z)}
	angle := f32(r)
	p0 = iso.world_point(mid - Vec3{perp.x, perp.y, 0}, angle, pal.size)
	p1 = iso.world_point(mid + Vec3{perp.x, perp.y, 0}, angle, pal.size)
	inward = iso.world_vector({-d.x, -d.y, 0}, angle)
	return
}

// --- drawing -----------------------------------------------------------------------

draw_world :: proc(r: ^Renderer, s: ^Scene, g: ^game.Game, v: View, time: f32) {
	draw_sky(r, g, v, time)
	draw_islands(g, v, time)
	draw_clouds(r, s, g, v, time, false)

	begin_3d(v)
	set_frame_uniforms(r, s, g, v)
	draw_pieces(r, s, g, false)
	draw_figures(r, g)
	draw_pieces(r, s, g, true)
	draw_decals(g)
	draw_glows(r, s, g, v)
	end_3d()

	draw_clouds(r, s, g, v, time, true)
	draw_motes(r, s, v)
	draw_markers(g, v)
}

@(private)
begin_3d :: proc(v: View) {
	rlgl.DrawRenderBatchActive()
	rlgl.MatrixMode(rlgl.PROJECTION)
	rlgl.PushMatrix()
	rlgl.SetMatrixProjection(clip_matrix(v))
	rlgl.MatrixMode(rlgl.MODELVIEW)
	rlgl.LoadIdentity()
	rlgl.EnableDepthTest()
	rlgl.DisableBackfaceCulling() // the projection mirrors the winding; boxes are closed anyway
}

@(private)
end_3d :: proc() {
	rl.EndMode3D() // flushes, pops the projection, disables the depth test
	rlgl.EnableBackfaceCulling()
}

@(private)
set_f :: proc(r: ^Renderer, u: Uniform, value: f32) {
	v := value
	rl.SetShaderValue(r.material.shader, r.loc[u], &v, .FLOAT)
}

@(private)
set_v2 :: proc(r: ^Renderer, u: Uniform, value: Vec2) {
	v := value
	rl.SetShaderValue(r.material.shader, r.loc[u], &v, .VEC2)
}

@(private)
set_v3 :: proc(r: ^Renderer, u: Uniform, value: Vec3) {
	v := value
	rl.SetShaderValue(r.material.shader, r.loc[u], &v, .VEC3)
}

@(private)
set_frame_uniforms :: proc(r: ^Renderer, s: ^Scene, g: ^game.Game, v: View) {
	axis := depth_axis(v)
	dmin, dmax: f32 = 1e30, -1e30
	for p in s.pieces {
		d := linalg_dot(Vec3{f32(p.cell.x) + 0.5, f32(p.cell.y) + 0.5, f32(p.cell.z)}, axis)
		dmin = min(dmin, d)
		dmax = max(dmax, d + 1)
	}
	set_f(r, .Light_Amount, g.light)
	set_f(r, .Flicker, g.flicker)
	set_v3(r, .Lamp_Pos, game.lamp_world(g))
	set_f(r, .Lamp_Radius, LAMP_RADIUS)
	set_v2(r, .View_Right, screen_right_xy(v))
	set_v3(r, .Depth_Axis, axis)
	set_f(r, .Depth_Min, dmin)
	set_f(r, .Depth_Max, dmax)
	set_f(r, .Mist_Top, proto_to_screen(v, {0, s.fit.y + s.fit.h - 330}).y)
	set_f(r, .Mist_Bottom, proto_to_screen(v, {0, s.fit.y + s.fit.h + 60}).y)
	set_f(r, .Screen_Height, v.height)
}

@(private)
linalg_dot :: proc(a, b: Vec3) -> f32 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}

@(private)
set_piece_uniforms :: proc(r: ^Renderer, material: Material, detail, hidden, alpha, soft, glow: f32) {
	set_f(r, .Material, f32(material))
	set_f(r, .Detail, detail)
	set_f(r, .Hidden, hidden)
	set_f(r, .Alpha, alpha)
	set_f(r, .Shade_Soft, soft)
	set_f(r, .Glow, glow)
}

// Lift, opacity and visibility of piece i in this frame.
@(private)
piece_state :: proc(g: ^game.Game, p: Piece, i: int) -> (lift, alpha: f32, visible: bool) {
	alpha = 1
	visible = true
	switch p.sigil {
	case .None:
	case .Off:
		visible = !g.activated
	case .On:
		visible = g.activated
	}
	if p.rise_index >= 0 {
		if g.rise_t < 0 {
			return 0, 0, false
		}
		start := f32(p.rise_index) * game.RISE_DELAY
		lift = -game.RISE_DEPTH * (1 - fx.cubic_out(fx.progress(g.rise_t, start, game.RISE_TIME)))
		alpha = fx.progress(g.rise_t, start, 0.8)
	}
	if g.collapse_t >= 0 {
		keep := g.collapse_keep
		if !(p.cell.x == keep.x && p.cell.y == keep.y && p.cell.z < keep.z) {
			delay := fx.hash01(u32(i)) * 2.2
			fall := (500 + 400 * fx.hash01(u32(i) + 7919)) / 64
			lift -= fall * fx.quad_in(fx.progress(g.collapse_t, delay, 2.0))
			alpha *= 1 - fx.progress(g.collapse_t, delay + 0.4, 1.6)
		}
	}
	visible = visible && alpha > 0.003
	return
}

// Opaque pieces first (transparent = false), then the see-through ones.
@(private)
draw_pieces :: proc(r: ^Renderer, s: ^Scene, g: ^game.Game, transparent: bool) {
	for p, i in s.pieces {
		lift, alpha, visible := piece_state(g, p, i)
		hidden := p.sigil == .Off
		if !visible || (alpha < 1 || hidden) != transparent {
			continue
		}
		material := p.material
		detail: f32 = 0
		if p.block {
			covered := pl.solid_at(&g.palace, p.cell + {0, 0, 1}).kind != .None
			material = covered ? .Masonry : .Marble
			detail = covered ? 2 : 1
		}
		set_piece_uniforms(r, material, detail, hidden ? 1 : 0, alpha, 0.25, 0)
		m := rl.MatrixTranslate(f32(p.cell.x), f32(p.cell.y), f32(p.cell.z) + lift)
		rl.DrawMesh(r.meshes[p.mesh], r.material, m)
	}
}

@(private)
draw_figures :: proc(r: ^Renderer, g: ^game.Game) {
	psy := g.psyche
	bob: f32 = psy.walking ? math.abs(math.sin(psy.walk_anim * 11)) * 0.02 : 0
	base := psy.pos + {0, 0, bob}
	rot := rl.MatrixRotateZ(psy.yaw)
	set_piece_uniforms(r, .Psyche, 0, 0, game.psyche_alpha(g), 0.9, 0.04)
	rl.DrawMesh(r.meshes[.Robe], r.material, rl.MatrixTranslate(base.x, base.y, base.z) * rot)
	rl.DrawMesh(r.meshes[.Head], r.material, rl.MatrixTranslate(base.x, base.y, base.z + 0.548) * rl.MatrixScale(0.046, 0.046, 0.05))
	if g.data.has_lamp {
		lamp := game.lamp_world(g)
		set_piece_uniforms(r, .Bronze, 0, 0, 1, 0.9, 0)
		rl.DrawMesh(r.meshes[.Lamp], r.material, rl.MatrixTranslate(lamp.x, lamp.y, lamp.z - 0.05))
	}

	draw_fragment(r, g)

	// the prologue's procession: veiled mourners, a little taller than Psyche
	if g.phase == .Prologue {
		for i in 0 ..< game.MOURNERS {
			m := game.prologue_mourner(g, i)
			if m.alpha < 0.003 {
				continue
			}
			set_piece_uniforms(r, .Mourner, 0, 0, m.alpha, 0.9, 0)
			mrot := rl.MatrixRotateZ(m.yaw)
			rl.DrawMesh(r.meshes[.Robe], r.material, rl.MatrixTranslate(m.pos.x, m.pos.y, m.pos.z) * mrot * rl.MatrixScale(1.05, 1.05, 1.1))
			rl.DrawMesh(r.meshes[.Head], r.material, rl.MatrixTranslate(m.pos.x, m.pos.y, m.pos.z + 0.6) * rl.MatrixScale(0.05, 0.05, 0.056))
			// the torch: a bronze shaft under the flame
			tw := game.torch_world(m)
			set_piece_uniforms(r, .Bronze, 0, 0, m.alpha, 0.9, 0)
			rl.DrawMesh(r.meshes[.Lamp], r.material, rl.MatrixTranslate(tw.x, tw.y, tw.z - 0.06) * rl.MatrixScale(0.6, 0.6, 1.4))
		}
	}

	// Cupid: only a presence in the dark; the lamp shows him
	if g.data.has_amore && g.amore.reveal > 0.003 {
		alpha := g.amore.reveal * cupid_fade(g)
		if alpha > 0.003 {
			c := amore_position(g)
			set_piece_uniforms(r, .Cupid, 0, 0, alpha, 0.9, 0.12)
			rl.DrawMesh(r.meshes[.Robe_Cupid], r.material, rl.MatrixTranslate(c.x, c.y, c.z - 0.15))
			rl.DrawMesh(r.meshes[.Head], r.material, rl.MatrixTranslate(c.x, c.y, c.z + 0.455) * rl.MatrixScale(0.05, 0.05, 0.055))
		}
	}
}

// How visible the fragment's scroll is: faint when collected in an earlier
// play, rising and fading when picked up now.
@(private)
fragment_alpha :: proc(g: ^game.Game) -> (alpha, lift: f32) {
	if !g.data.has_fragment || g.phase == .Prologue {
		return 0, 0
	}
	if g.fragment_known {
		return 0.28, 0
	}
	if g.fragment_taken {
		u := fx.clamp01(g.fragment_t / 1.4)
		return 1 - u, fx.cubic_out(u) * 0.6
	}
	return 1, 0
}

@(private)
draw_fragment :: proc(r: ^Renderer, g: ^game.Game) {
	alpha, lift := fragment_alpha(g)
	if alpha <= 0.003 {
		return
	}
	p := game.fragment_world(g) + {0, 0, lift}
	set_piece_uniforms(r, .Psyche, 0, 0, alpha, 0.9, g.fragment_known ? 0 : 0.1)
	// laid on its side, turning slowly
	m := rl.MatrixTranslate(p.x, p.y, p.z) * rl.MatrixRotateZ(g.time * 0.5) * rl.MatrixRotateX(math.PI / 2) * rl.MatrixTranslate(0, 0, -0.14)
	rl.DrawMesh(r.meshes[.Scroll], r.material, m)
}

@(private)
cupid_fade :: proc(g: ^game.Game) -> f32 {
	if g.amore.fly_t < 0 {
		return 1
	}
	return 1 - fx.progress(g.amore.fly_t, 0.6, 2.2)
}

// --- immediate-mode helpers (3D) ----------------------------------------------------

@(private)
vtx :: proc(p: Vec3) {
	rlgl.Vertex3f(p.x, p.y, p.z)
}

@(private)
color :: proc(c: Color4) {
	rlgl.Color4f(clamp(c.r, 0, 1), clamp(c.g, 0, 1), clamp(c.b, 0, 1), clamp(c.a, 0, 1))
}

// Flat ellipse lying on the floor.
@(private)
floor_ellipse :: proc(center: Vec3, rx, ry: f32, c: Color4) {
	N :: 16
	rlgl.Begin(rlgl.TRIANGLES)
	for i in 0 ..< N {
		a0 := f32(i) / N * math.TAU
		a1 := f32(i + 1) / N * math.TAU
		color(c)
		vtx(center)
		vtx(center + {math.cos(a0) * rx, math.sin(a0) * ry, 0})
		vtx(center + {math.cos(a1) * rx, math.sin(a1) * ry, 0})
	}
	rlgl.End()
}

// A ring on the floor between radius r and r + width.
@(private)
floor_ring :: proc(center: Vec3, r, width: f32, c: Color4) {
	N :: 32
	rlgl.Begin(rlgl.TRIANGLES)
	color(c)
	for i in 0 ..< N {
		a0 := f32(i) / N * math.TAU
		a1 := f32(i + 1) / N * math.TAU
		d0 := Vec3{math.cos(a0), math.sin(a0), 0}
		d1 := Vec3{math.cos(a1), math.sin(a1), 0}
		vtx(center + d0 * r)
		vtx(center + d1 * r)
		vtx(center + d1 * (r + width))
		vtx(center + d0 * r)
		vtx(center + d1 * (r + width))
		vtx(center + d0 * (r + width))
	}
	rlgl.End()
}

// A thin strip on the floor from a to b, `width` wide toward `side`.
@(private)
floor_strip :: proc(a, b, side: Vec3, width: f32, c: Color4) {
	rlgl.Begin(rlgl.TRIANGLES)
	color(c)
	vtx(a)
	vtx(b)
	vtx(b + side * width)
	vtx(a)
	vtx(b + side * width)
	vtx(a + side * width)
	rlgl.End()
}

// Oil stains, Psyche's shadow and the cracks of the illusions.
@(private)
draw_decals :: proc(g: ^game.Game) {
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rlgl.SetTexture(rlgl.GetTextureIdDefault())

	stain_fade: f32 = g.collapse_t >= 0 ? 1 - fx.clamp01(g.collapse_t / 2) : 1
	for i in 0 ..< g.stain_count {
		st := g.stains[i]
		floor_ellipse(st.pos + {0, 0, 0.004}, 0.06, 0.06, {0.5, 0.3, 0.08, 0.55 * stain_fade})
	}
	floor_ellipse(g.psyche.pos + {0, 0, 0.006}, 0.13, 0.13, {0, 0, 0.04, 0.4 * game.psyche_alpha(g)})

	// the exit: rings of wind spreading on the stone
	if ea := exit_alpha(g); g.data.has_exit && g.phase != .Finished && ea > 0 {
		c := pl.node_world(&g.palace, g.data.exit) + {0, 0, 0.008}
		floor_ellipse(c, 0.3, 0.3, {0.55, 0.75, 1.0, 0.22 * ea})
		for k in 0 ..< 3 {
			u := math.mod(g.time / 2.2 + f32(k) / 3, 1)
			floor_ring(c, 0.08 + 0.36 * u, 0.025, {0.75, 0.9, 1.0, 0.7 * (1 - u) * ea})
		}
	}

	if g.light > 0.01 && !g.turning && g.collapse_t < 0 {
		for e, n in g.palace.illusion.pairs {
			p0, p1, inward := seam_edge(g, e)
			lift := Vec3{0, 0, 0.005}
			// a dark band in the stone...
			floor_strip(p0 + lift, p1 + lift, inward, 0.1, {0.02, 0.01, 0.04, 0.35 * g.light})
			// ...and a jagged crack along the joint
			prev := p0 + lift
			for k in 1 ..= 6 {
				t := f32(k) / 6
				jitter: f32 = k < 6 ? (fx.hash01(u32(n * 7 + k)) - 0.5) * 0.05 : 0
				next := fx.lerp(p0, p1, t) + lift + inward * (0.012 + jitter * 0.5)
				floor_strip(prev, next, inward, 0.028, {0.03, 0.02, 0.05, 0.9 * g.light})
				prev = next
			}
		}
	}
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
}

// A soft round glow facing the camera; radius in proto pixels.
@(private)
glow :: proc(v: View, center: Vec3, radius: f32, c: Color4, stretch_y: f32 = 1) {
	right, up := billboard_axes(v)
	rx := right * radius
	uy := up * radius * stretch_y
	color(c)
	rlgl.TexCoord2f(0, 0)
	vtx(center - rx + uy)
	rlgl.TexCoord2f(0, 1)
	vtx(center - rx - uy)
	rlgl.TexCoord2f(1, 1)
	vtx(center + rx - uy)
	rlgl.TexCoord2f(1, 0)
	vtx(center + rx + uy)
}

// Additive light: lamp, aura, seal, Cupid, drops, wings and particles.
@(private)
draw_glows :: proc(r: ^Renderer, s: ^Scene, g: ^game.Game, v: View) {
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rl.BeginBlendMode(.ADDITIVE)

	draw_wings(g, v)

	rlgl.SetTexture(r.radial.id)
	rlgl.Begin(rlgl.QUADS)
	psy := g.psyche
	t := g.time
	// Psyche's faint inner light
	glow(v, psy.pos + {0, 0, 0.42}, 46, {0.55, 0.6, 1.0, (0.18 + 0.06 * math.sin(t * 1.7)) * game.psyche_alpha(g)})
	// the procession's torches, and their smoke once put out
	if g.phase == .Prologue {
		for i in 0 ..< game.MOURNERS {
			m := game.prologue_mourner(g, i)
			tw := game.torch_world(m)
			fl := 0.85 + 0.1 * math.sin(t * 19 + f32(i) * 2.1) + 0.05 * math.sin(t * 31 + f32(i))
			a := m.torch * m.alpha * fl
			if a > 0.003 {
				glow(v, tw, 110, {1.0, 0.55, 0.22, 0.26 * a})
				glow(v, tw, 14, {1.0, 0.72, 0.36, a}, 1.6)
				glow(v, tw, 6, {1.0, 0.95, 0.8, a}, 1.5)
			}
			if m.out_t >= 0 && m.out_t < 2.4 {
				for k in 0 ..< 4 {
					u := m.out_t / 2.4 - f32(k) * 0.08
					if u <= 0 {
						continue
					}
					drift := Vec3{math.sin(f32(k) * 1.9 + m.out_t) * 0.06, math.cos(f32(k) * 1.3) * 0.04, u * 0.9}
					glow(v, tw + drift, 10 + 26 * u, {0.42, 0.42, 0.55, 0.22 * (1 - u) * m.alpha})
				}
			}
		}
	}
	// the lamp
	lamp := game.lamp_world(g)
	f := g.flicker
	glow(v, lamp, 150, {1.0, 0.68, 0.32, g.light * 0.32 * f})
	glow(v, lamp + {0, 0, 0.02}, 9 * (0.85 + 0.15 * f), {1.0, 0.75, 0.4, g.light * f}, 1.7)
	glow(v, lamp + {0, 0, 0.02}, 4 * (0.85 + 0.15 * f), {1.0, 0.95, 0.8, g.light * f}, 1.6)
	// the fragment's faint glow
	if a, lift := fragment_alpha(g); a > 0.003 && !g.fragment_known {
		c := game.fragment_world(g) + {0, 0, lift}
		glow(v, c, 58, {1.0, 0.86, 0.55, a * (0.3 + 0.08 * math.sin(t * 2.1))})
		glow(v, c, 16, {1.0, 0.95, 0.8, a * 0.45})
	}
	// the exit: a pale breath of wind on the stone
	if ea := exit_alpha(g); g.data.has_exit && g.phase != .Finished && ea > 0 {
		c := pl.node_world(&g.palace, g.data.exit) + {0, 0, 0.3}
		pulse := 0.85 + 0.15 * math.sin(t * 1.3)
		glow(v, c, 130, {0.5, 0.7, 1.0, 0.3 * pulse * ea}, 1.2)
		// a column of pale light rising from the stone
		glow(v, c + {0, 0, 0.75}, 30, {0.7, 0.85, 1.0, 0.32 * pulse * ea}, 5.5)
		glow(v, c + {0, 0, 0.6}, 12, {0.92, 0.97, 1.0, 0.45 * pulse * ea}, 8)
		glow(v, c + {0, 0, -0.25}, 40, {0.85, 0.93, 1.0, 0.45 * ea})
	}
	for p in fx.alive(&s.wind) {
		col := p.color
		col.a *= fx.mote_alpha(p)
		glow(v, p.pos, p.size * 0.5, col)
	}
	// the lit seal breathes
	if g.activated && g.collapse_t < 0 {
		c := pl.node_world(&g.palace, g.data.sigil) + {0, 0, 0.05}
		pulse := 0.25 + 0.55 * (0.5 + 0.5 * math.cos(g.rise_t * math.PI / 1.4))
		glow(v, c, 70, {1.0, 0.75, 0.35, pulse})
	}
	// Cupid: a warm breathing presence
	if g.data.has_amore {
		c := amore_position(g)
		fade := cupid_fade(g)
		presence := (0.28 + 0.12 * math.sin(t * 1.25)) * g.amore.breath * fade
		radius := 80 * (1 + 1.2 * g.amore.embrace)
		glow(v, c + {0, 0, 0.19}, radius, {1.0, 0.72, 0.35, presence})
	}
	// drops of oil, and the burning one
	for d in g.drops {
		if d.active {
			glow(v, game.drop_position(d), 3, {1.0, 0.8, 0.4, 0.9})
		}
	}
	if p, ok := game.oil_drop(g); ok {
		glow(v, p, 5, {1.0, 0.85, 0.45, 1})
		glow(v, p, 14, {1.0, 0.6, 0.25, 0.5})
	}
	for p in fx.alive(&s.sparks) {
		col := p.color
		col.a *= fx.mote_alpha(p) * cupid_fade(g)
		glow(v, p.pos, p.size * 0.5, col)
	}
	for p in fx.alive(&s.dust) {
		col := p.color
		col.a *= fx.mote_alpha(p) * g.light
		glow(v, p.pos, p.size * 0.5, col)
	}
	rlgl.End()
	rlgl.SetTexture(0)
	rl.EndBlendMode()
	rlgl.EnableDepthMask()
}

// An ellipse in the plane spanned by u and w, around `center`.
@(private)
ellipse_3d :: proc(center, u, w: Vec3, rx, ry, tilt: f32, c: Color4) {
	N :: 18
	ct, st := math.cos(tilt), math.sin(tilt)
	point :: proc(center, u, w: Vec3, x, y, ct, st: f32) -> Vec3 {
		return center + u * (x * ct - y * st) + w * (x * st + y * ct)
	}
	rlgl.Begin(rlgl.TRIANGLES)
	for i in 0 ..< N {
		a0 := f32(i) / N * math.TAU
		a1 := f32(i + 1) / N * math.TAU
		color(c)
		vtx(center)
		vtx(point(center, u, w, math.cos(a0) * rx, math.sin(a0) * ry, ct, st))
		vtx(point(center, u, w, math.cos(a1) * rx, math.sin(a1) * ry, ct, st))
	}
	rlgl.End()
}

// Psyche's butterfly wings of light (psyche = soul = butterfly) and Cupid's feathers.
@(private)
draw_wings :: proc(g: ^game.Game, v: View) {
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	psy := g.psyche
	fwd := Vec3{math.cos(psy.yaw), math.sin(psy.yaw), 0}
	side := Vec3{-fwd.y, fwd.x, 0}
	up := Vec3{0, 0, 1}
	speed: f32 = psy.walking ? 9 : 2.2
	open := 0.72 + 0.28 * math.sin(g.time * speed) // 1 = spread flat
	root := psy.pos + {0, 0, 0.4} - fwd * 0.035
	for sgn in ([2]f32{-1, 1}) {
		// the wing plane folds back from the side toward the back
		fold := (1 - open) * 1.2
		u := side * sgn * math.cos(fold) - fwd * math.sin(fold)
		pa := game.psyche_alpha(g)
		ellipse_3d(root + u * 0.12 + up * 0.06, u, up, 0.13, 0.085, sgn * 0.6, {0.62, 0.74, 1.0, 0.32 * pa})
		ellipse_3d(root + u * 0.09 - up * 0.08, u, up, 0.085, 0.055, -sgn * 0.5, {0.86, 0.7, 1.0, 0.26 * pa})
	}

	if g.data.has_amore && g.amore.reveal > 0.003 {
		alpha := g.amore.reveal * cupid_fade(g)
		c := amore_position(g)
		right, _ := billboard_axes(v)
		cside := right / math.sqrt(linalg_dot(right, right))
		flap: f32 = g.amore.fly_t >= 0 ? 1 : 0
		spread := 1 + 0.25 * math.sin(g.time * (2 + flap * 14)) * (0.3 + flap)
		wroot := c + {0, 0, 0.4}
		for sgn in ([2]f32{-1, 1}) {
			for i in 0 ..< 5 {
				length := (46 - f32(i) * 6) / 64
				a := -0.9 + f32(i) * 0.32
				dir := cside * sgn * math.cos(a) * spread + up * -math.sin(a)
				ellipse_3d(wroot + dir * length * 0.5, cside * sgn, up, length * 0.5, 5.0 / 64, -sgn * a, {1.0, 0.92, 0.75, 0.75 * alpha})
			}
		}
	}
}

// --- 2D layers ----------------------------------------------------------------------

@(private)
full_rect :: proc(r: ^Renderer, dest: rl.Rectangle) {
	rl.DrawTexturePro(r.white, {0, 0, 1, 1}, dest, {}, 0, rl.WHITE)
}

@(private)
set_bf :: proc(sh: rl.Shader, loc: i32, value: f32) {
	v := value
	rl.SetShaderValue(sh, loc, &v, .FLOAT)
}

@(private)
draw_sky :: proc(r: ^Renderer, g: ^game.Game, v: View, time: f32) {
	set_bf(r.sky, r.sky_loc[.Light_Amount], g.light * 0.8)
	set_bf(r.sky, r.sky_loc[.Shift], g.angle)
	set_bf(r.sky, r.sky_loc[.Time], time)
	set_bf(r.sky, r.sky_loc[.Aspect], v.width / v.height)
	rl.BeginShaderMode(r.sky)
	full_rect(r, {0, 0, v.width, v.height})
	rl.EndShaderMode()
}

@(private)
draw_clouds :: proc(r: ^Renderer, s: ^Scene, g: ^game.Game, v: View, time: f32, front: bool) {
	top := s.fit.y + s.fit.h - (front ? 330 : 520)
	a := proto_to_screen(v, {s.fit.x - 1400, top})
	b := proto_to_screen(v, {s.fit.x + s.fit.w + 1400, top + 700})
	tint := front ? Vec3{0.19, 0.19, 0.38} : Vec3{0.13, 0.13, 0.29}
	set_bf(r.clouds, r.clouds_loc[.Light_Amount], g.light)
	set_bf(r.clouds, r.clouds_loc[.Shift], g.angle * 0.8)
	set_bf(r.clouds, r.clouds_loc[.Time], time)
	set_bf(r.clouds, r.clouds_loc[.Density], front ? 0.9 : 1.0)
	rl.SetShaderValue(r.clouds, r.clouds_loc[.Tint], &tint, .VEC3)
	rl.BeginShaderMode(r.clouds)
	full_rect(r, {a.x, a.y, b.x - a.x, b.y - a.y})
	rl.EndShaderMode()
}

@(private)
Island :: struct {
	pos:   Vec2, // on a 1920 x 1080 screen
	scale: f32,
	cells: []Cell, // sorted back to front
}

@(private)
ISLANDS := [?]Island {
	{{260, 640}, 0.32, {{0, 0, 0}, {1, 0, 0}, {0, 1, 0}, {0, 0, 1}, {1, 1, 0}, {0, 0, 2}}},
	{{1620, 560}, 0.26, {{0, 0, 0}, {0, 1, 0}, {0, 0, 1}, {1, 1, 0}, {0, 0, 2}, {1, 1, 1}, {0, 0, 3}}},
	{{980, 300}, 0.18, {{0, 0, 0}, {1, 0, 0}, {0, 0, 1}}},
	{{-300, 420}, 0.22, {{0, 0, 0}, {0, 1, 0}, {1, 0, 0}, {0, 1, 1}}},
	{{2250, 380}, 0.2, {{0, 0, 0}, {1, 0, 0}, {0, 0, 1}, {1, 0, 1}}},
}

// Filled triangle in either winding (raylib wants counter-clockwise on screen).
@(private)
tri :: proc(a, b, c: Vec2, col: rl.Color) {
	cross := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
	if cross < 0 {
		rl.DrawTriangle(a, b, c, col)
	} else {
		rl.DrawTriangle(a, c, b, col)
	}
}

@(private)
quad_2d :: proc(a, b, c, d: Vec2, col: rl.Color) {
	tri(a, b, c, col)
	tri(a, c, d, col)
}

@(private)
to_color :: proc(c: Color4) -> rl.Color {
	return {u8(clamp(c.r, 0, 1) * 255), u8(clamp(c.g, 0, 1) * 255), u8(clamp(c.b, 0, 1) * 255), u8(clamp(c.a, 0, 1) * 255)}
}

// Far floating ruins in two hazy tones, drifting when the palace turns.
@(private)
draw_islands :: proc(g: ^game.Game, v: View, time: f32) {
	SHADOW :: Vec3{0.06, 0.06, 0.15}
	LIGHT :: Vec3{0.16, 0.17, 0.34}
	tone :: proc(t: f32) -> rl.Color {
		c := fx.lerp(SHADOW, LIGHT, t)
		return to_color({c.x, c.y, c.z, 1})
	}
	sx, sy := v.width / 1920, v.height / 1080
	for isl in ISLANDS {
		base := Vec2{isl.pos.x * sx, isl.pos.y * sy}
		base.x -= g.angle * 900 * isl.scale * sx
		base.y += math.sin(time * 0.3 + isl.pos.x) * 6 * sy
		k := isl.scale * sy
		pt :: proc(base: Vec2, k: f32, x, y, z: f32) -> Vec2 {
			return base + iso.project({x, y, z}) * k
		}
		// a hanging root of rock under the island, fading into the haze
		draw_island_tail(base, k)
		for c in isl.cells {
			x, y, z := f32(c.x), f32(c.y), f32(c.z)
			// cell floor centre sits at the island origin for (0, 0, 0)
			x -= 0.5
			y -= 0.5
			quad_2d(pt(base, k, x, y + 1, z), pt(base, k, x + 1, y + 1, z), pt(base, k, x + 1, y + 1, z + 1), pt(base, k, x, y + 1, z + 1), tone(0.075))
			quad_2d(pt(base, k, x + 1, y, z), pt(base, k, x + 1, y + 1, z), pt(base, k, x + 1, y + 1, z + 1), pt(base, k, x + 1, y, z + 1), tone(0.625))
			quad_2d(pt(base, k, x, y, z + 1), pt(base, k, x + 1, y, z + 1), pt(base, k, x + 1, y + 1, z + 1), pt(base, k, x, y + 1, z + 1), tone(0.9))
		}
	}
}

@(private)
draw_island_tail :: proc(base: Vec2, k: f32) {
	POINTS :: [7]Vec2{{-64, 30}, {-30, 90}, {-40, 150}, {6, 290}, {30, 170}, {58, 110}, {66, 30}}
	ALPHA :: [7]f32{1, 1, 0.7, 0, 0.6, 1, 1}
	pts := POINTS
	alpha := ALPHA
	centre := base + Vec2{4, 80} * k
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	for i in 0 ..< len(pts) - 1 {
		a, b := base + pts[i] * k, base + pts[i + 1] * k
		// the fan from the centre, coloured per vertex
		rlgl.Begin(rlgl.TRIANGLES)
		cross := (a.x - centre.x) * (b.y - centre.y) - (a.y - centre.y) * (b.x - centre.x)
		order := cross < 0 ? [2]int{i, i + 1} : [2]int{i + 1, i}
		rlgl.Color4f(0.07, 0.07, 0.17, 0.85)
		rlgl.Vertex2f(centre.x, centre.y)
		for j in order {
			p := base + pts[j] * k
			rlgl.Color4f(0.07, 0.07, 0.17, alpha[j])
			rlgl.Vertex2f(p.x, p.y)
		}
		rlgl.End()
	}
}

@(private)
draw_motes :: proc(r: ^Renderer, s: ^Scene, v: View) {
	rl.BeginBlendMode(.ADDITIVE)
	for p in fx.alive(&s.motes) {
		pos := proto_to_screen(v, p.pos.xy)
		size := p.size * v.zoom
		col := p.color
		col.a *= fx.mote_alpha(p)
		rl.DrawTexturePro(r.radial, {0, 0, f32(r.radial.width), f32(r.radial.height)}, {pos.x - size * 0.5, pos.y - size * 0.5, size, size}, {}, 0, to_color(col))
	}
	rl.EndBlendMode()
}

// Diamonds on the clicked surfaces: gold when reachable, rose when not.
@(private)
draw_markers :: proc(g: ^game.Game, v: View) {
	for m in g.markers {
		if !m.active {
			continue
		}
		u := m.t / game.MARKER_TIME
		w := pl.node_world(&g.palace, m.cell)
		corners := [4]Vec3{w + {-0.5, -0.5, 0}, w + {0.5, -0.5, 0}, w + {0.5, 0.5, 0}, w + {-0.5, 0.5, 0}}
		col := m.ok ? Color4{1.0, 0.85, 0.5, 0.8} : Color4{0.9, 0.4, 0.5, 0.6}
		col.a *= 1 - u
		width := (2.5 - 2 * u) * v.zoom
		for i in 0 ..< 4 {
			a := world_to_screen(v, corners[i])
			b := world_to_screen(v, corners[(i + 1) % 4])
			rl.DrawLineEx(a, b, max(width, 0.5), to_color(col))
		}
	}
}
