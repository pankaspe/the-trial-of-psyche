// Drawing the world: night sky, far islands, sea of clouds, the palace in 3D,
// Psyche and Cupid, cracks of the illusions, oil, glows and particles.
//
// Renderer: GPU resources, created once.
// Scene: what one level needs to be drawn (pieces, framing, particle pools);
// its arrays come from the level arena, so they vanish with the level.
package render

import "core:math"
import "core:slice"
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
	Mist_Color,
	Daylight,
	Moonlight,
	Candles,
	Candle_Reach,
	Candle_Count,
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
	.Mist_Color    = "mist_color",
	.Daylight      = "daylight",
	.Moonlight     = "moonlight",
	.Candles       = "candles",
	.Candle_Reach  = "candle_reach",
	.Candle_Count  = "candle_count",
}

// Uniforms of the backdrop shaders (sky, ridges, clouds); each uses some of them.
Backdrop_Uniform :: enum u8 {
	Light_Amount,
	Shift,
	Time,
	Aspect,
	Tint,
	Density,
	Horizon,
	Sky_Top,
	Sky_Mid,
	Sky_Horizon,
	Orb_Pos,
	Orb_Radius,
	Orb_Color,
	Halo_Color,
	Halo_Width,
	Stars,
	Haze,
	Night_Clouds,
	Crest_Color,
	Color_Far,
	Color_Mid,
	Color_Near,
	Rim,
}

@(private)
BACKDROP_NAME := [Backdrop_Uniform]cstring {
	.Light_Amount = "light_amount",
	.Shift        = "shift",
	.Time         = "time",
	.Aspect       = "aspect",
	.Tint         = "tint",
	.Density      = "density",
	.Horizon      = "horizon",
	.Sky_Top      = "sky_top",
	.Sky_Mid      = "sky_mid",
	.Sky_Horizon  = "sky_horizon",
	.Orb_Pos      = "orb_pos",
	.Orb_Radius   = "orb_radius",
	.Orb_Color    = "orb_color",
	.Halo_Color   = "halo_color",
	.Halo_Width   = "halo_width",
	.Stars        = "stars",
	.Haze         = "haze",
	.Night_Clouds = "night_clouds",
	.Crest_Color  = "crest_color",
	.Color_Far    = "color_far",
	.Color_Mid    = "color_mid",
	.Color_Near   = "color_near",
	.Rim          = "rim",
}

// A backdrop shader and the locations of its uniforms (-1: not used by it).
Backdrop :: struct {
	shader: rl.Shader,
	loc:    [Backdrop_Uniform]i32,
}

Renderer :: struct {
	meshes:     [Mesh_Id]rl.Mesh,
	material:   rl.Material, // owns the palace shader
	loc:        [Uniform]i32,
	sky:        Backdrop,
	ridges:     Backdrop,
	clouds:     Backdrop,
	veil:       Backdrop, // between the levels (uses time, aspect and its own alpha)
	radial:     rl.Texture2D, // soft round gradient for glows and particles
	white:      rl.Texture2D, // 1x1, for full-rect shader passes
	veil_alpha: i32,
}

init :: proc(r: ^Renderer) {
	shader := rl.LoadShaderFromMemory(content.SHADER_PALACE_VS, content.SHADER_PALACE_FS)
	r.material = rl.LoadMaterialDefault()
	r.material.shader = shader
	for name, u in UNIFORM_NAME {
		r.loc[u] = rl.GetShaderLocation(shader, name)
	}
	load_backdrop :: proc(fs: cstring) -> (b: Backdrop) {
		b.shader = rl.LoadShaderFromMemory(nil, fs)
		for name, u in BACKDROP_NAME {
			b.loc[u] = rl.GetShaderLocation(b.shader, name)
		}
		return
	}
	r.sky = load_backdrop(content.SHADER_SKY_FS)
	r.ridges = load_backdrop(content.SHADER_RIDGES_FS)
	r.clouds = load_backdrop(content.SHADER_CLOUDS_FS)
	r.veil = load_backdrop(content.SHADER_VEIL_FS)
	r.veil_alpha = rl.GetShaderLocation(r.veil.shader, "alpha")
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
	rl.UnloadShader(r.sky.shader)
	rl.UnloadShader(r.ridges.shader)
	rl.UnloadShader(r.clouds.shader)
	rl.UnloadShader(r.veil.shader)
	rl.UnloadTexture(r.radial)
	rl.UnloadTexture(r.white)
	r^ = {}
}

// --- per level -----------------------------------------------------------------------

Piece :: struct {
	cell:       Cell,
	mesh:       Mesh_Id,
	material:   Material,
	cube:       bool, // marble on top, masonry when covered
	lawn:       bool, // a block with a grassy top
	ground:     bool, // living rock: earth sides, grass where uncovered
	rise_index: i32, // >= 0: raised by the seal, in this order
	block:      i32, // >= 0: its data.blocks entry (it may fall, dissolve, appear)
	part:       u8, // 0: fixed; n: turns with part n-1
	handle:     i32, // >= 0: the crank of this handle
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
	debris:     fx.Pool(160), // falling stones, dissolving phantoms (world)
	wind:       fx.Pool(96), // Zephyr's breath over the exit (world)
	rng:        fx.Rng,
	mote:       Color4, // the colour of the drifting motes (from the setting)
	moon_cover: f32, // how much the night clouds hide the moon now (0..1)
}

scene_build :: proc(s: ^Scene, g: ^game.Game, allocator := context.allocator) {
	s^ = {}
	s.pieces = make([dynamic]Piece, 0, len(g.data.blocks) + 2 * len(g.data.props) + 2 * len(g.data.candelabra) + len(g.data.rise) + len(g.data.handles) + 2, allocator)
	s.rng = fx.rng_init(1234)
	s.mote = look(g.data.setting).mote
	for e, i in g.data.blocks {
		p := solid_piece(e.cell, e.solid, -1)
		p.block = i32(i)
		p.part = e.part
		for c in g.data.lawn {
			p.lawn ||= c == e.cell && p.cube
		}
		for c in g.data.ground {
			p.ground ||= c == e.cell
		}
		if p.ground && !p.cube {
			p.material = .Lawn // steps cut in the rock: grassy treads, earth risers
		}
		if e.trait == .Phantom {
			p.material = .Phantom
		}
		append(&s.pieces, p)
	}
	for prop in g.data.props {
		mesh := PROP_MESH[prop.kind]
		if prop.kind in level.ORIENTED_PROPS {
			mesh = oriented_mesh(mesh, prop.dir)
		}
		append(&s.pieces, Piece{cell = prop.cell, mesh = mesh, material = PROP_MATERIAL[prop.kind], rise_index = -1, block = -1, handle = -1, part = prop.part})
		#partial switch prop.kind {
		case .Sconce:
			// the candle, in wax
			append(&s.pieces, Piece{cell = prop.cell, mesh = oriented_mesh(.Candle_PX, prop.dir), material = .Psyche, rise_index = -1, block = -1, handle = -1, part = prop.part})
		case .Pine:
			append(&s.pieces, Piece{cell = prop.cell, mesh = oriented_mesh(.Trunk_PX, prop.dir), material = .Wood, rise_index = -1, block = -1, handle = -1, part = prop.part})
		}
	}
	for c in g.data.candelabra {
		append(&s.pieces, Piece{cell = c.cell, mesh = oriented_mesh(.Candelabrum_PX, c.dir), material = .Bronze, rise_index = -1, block = -1, handle = -1})
		append(&s.pieces, Piece{cell = c.cell, mesh = oriented_mesh(.Candelabrum_Wax_PX, c.dir), material = .Psyche, rise_index = -1, block = -1, handle = -1})
	}
	for h, i in g.data.handles {
		append(&s.pieces, Piece{cell = h.cell, mesh = .Crank_Post, material = .Bronze, rise_index = -1, block = -1, handle = i32(i)})
	}
	for c in g.data.rests {
		append(&s.pieces, Piece{cell = c, mesh = .Altar, material = .Bronze, rise_index = -1, block = -1, handle = -1})
	}
	for e, i in g.data.rise {
		append(&s.pieces, solid_piece(e.cell, e.solid, i32(i)))
	}
	if g.data.has_sigil {
		append(&s.pieces, Piece{cell = g.data.sigil, mesh = .Sigil_Off, material = .Bronze, rise_index = -1, block = -1, handle = -1, sigil = .Off})
		append(&s.pieces, Piece{cell = g.data.sigil, mesh = .Sigil_On, material = .Bronze, rise_index = -1, block = -1, handle = -1, sigil = .On})
	}

	// framing: every piece from every view (as the prototype's fit_rect), parts in every position
	first := true
	for p in s.pieces {
		for turn in 0 ..< (p.part > 0 ? 4 : 1) {
			cell := p.cell
			if p.part > 0 {
				cell = level.part_cell(cell, g.data.parts[p.part - 1].pivot, turn)
			}
			for r in 0 ..< 4 {
				c := iso.floor_center(iso.to_view(cell, r, g.data.size))
				top: f32 = p.mesh == .Block ? -96 : -120
				rect := Rect{c.x - 64, c.y + top, 128, 152}
				s.fit = first ? rect : rect_merge(s.fit, rect)
				first = false
			}
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
		return {cell = c, mesh = oriented_mesh(.Stairs_PX, solid.dir), material = .Marble, rise_index = rise, block = -1, handle = -1}
	}
	return {cell = c, mesh = .Block, material = .Marble, cube = true, rise_index = rise, block = -1, handle = -1}
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

CINE_LOOK_UP :: 520 // proto px the prologue's camera starts above the level

scene_view :: proc(s: ^Scene, g: ^game.Game, width, height: f32) -> View {
	v := make_view(s.fit, width, height, g.angle, g.data.size, g.data.height, shake_offset(g))
	if lift := game.exit_lift(g); lift > 0 {
		// the camera follows her a little way up as the wind takes her
		v.center.y -= lift * 64 * 0.55
	}
	if g.phase == .Prologue {
		cam := game.cine(g)
		her := world_to_proto(v, g.psyche.pos + {0, 0, 0.3})
		v.center = fx.lerp(v.center, her, cam.focus) - {0, cam.look_up * CINE_LOOK_UP}
		v.zoom *= cam.zoom
	}
	return v
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
		color = s.mote,
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
	// the stones the seal raises: a trail of gold as they come up, a burst of dust as they land
	if g.rise_t >= 0 && g.rise_t < game.rise_duration(g) + 0.5 {
		for e, i in g.data.rise {
			k := fx.progress(g.rise_t, f32(i) * game.RISE_DELAY, game.RISE_TIME)
			c := Vec3{f32(e.cell.x) + 0.5, f32(e.cell.y) + 0.5, f32(e.cell.z)} + {0, 0, rise_lift(g, i)}
			if k > 0 && k < 0.6 && fx.randf(&s.rng) < dt * 50 {
				fx.emit(&s.debris, {
					pos   = c + {fx.rand_range(&s.rng, -0.45, 0.45), fx.rand_range(&s.rng, -0.45, 0.45), fx.rand_range(&s.rng, -0.2, 0.1)},
					vel   = {0, 0, fx.rand_range(&s.rng, -0.8, -0.2)},
					life  = 1.2,
					size  = 32 * fx.rand_range(&s.rng, 0.08, 0.18),
					color = {1.0, 0.82, 0.45, 0.85},
				})
			}
			land := game.rise_landing(i)
			if g.rise_t >= land && g.rise_t - dt < land {
				for n in 0 ..< 22 {
					a := f32(n) / 22 * math.TAU + fx.randf(&s.rng) * 0.3
					edge := Vec3{math.cos(a), math.sin(a), 0}
					edge /= max(abs(edge.x), abs(edge.y)) // on the square's rim
					fx.emit(&s.dust, {
						pos   = c + {edge.x * 0.5, edge.y * 0.5, 1.0},
						vel   = {edge.x * fx.rand_range(&s.rng, 0.3, 0.8), edge.y * fx.rand_range(&s.rng, 0.3, 0.8), fx.rand_range(&s.rng, 0.1, 0.5)},
						accel = {0, 0, -1.2},
						life  = 1.1,
						size  = 32 * fx.rand_range(&s.rng, 0.1, 0.2),
						color = {1.0, 0.9, 0.7, 0.8},
					})
				}
			}
		}
	}
	// stones that fall shed grit; phantoms dissolve into pale mist; veiled stones gather gold
	for t, i in g.flip_t {
		if t < 0 || t > 0.9 {
			continue
		}
		trait := g.data.blocks[i].trait
		if fx.randf(&s.rng) > dt * 40 {
			continue
		}
		c := block_world(g, int(i), {0.5, 0.5, 0.5})
		if trait == .Crumble {
			c.z -= 7 * fx.quad_in(fx.clamp01(t / game.FALL_TIME))
		}
		col := Color4{0.7, 0.72, 0.9, 0.7}
		vel := Vec3{fx.rand_range(&s.rng, -0.4, 0.4), fx.rand_range(&s.rng, -0.4, 0.4), fx.rand_range(&s.rng, -0.6, 0.2)}
		#partial switch trait {
		case .Phantom:
			col = {0.65, 0.8, 1.0, 0.8}
			vel.z = fx.rand_range(&s.rng, 0.2, 0.6)
		case .Veiled:
			col = {1.0, 0.82, 0.45, 0.85}
			vel = -vel * 0.5
		}
		fx.emit(&s.debris, {
			pos   = c + {fx.rand_range(&s.rng, -0.5, 0.5), fx.rand_range(&s.rng, -0.5, 0.5), fx.rand_range(&s.rng, -0.5, 0.5)},
			vel   = vel,
			accel = trait == .Crumble ? Vec3{0, 0, -3} : Vec3{},
			life  = 1.4,
			size  = 32 * fx.rand_range(&s.rng, 0.1, 0.22),
			color = col,
		})
	}
	fx.update(&s.debris, dt)
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
	lk := look(g.data.setting)
	draw_sky(r, s, g, v, time)
	if lk.islands {
		draw_islands(g, v, time)
	}
	if lk.ridges > 0 {
		draw_ridges(r, s, g, v)
	}
	draw_clouds(r, s, g, v, time, false)

	begin_3d(v)
	set_frame_uniforms(r, s, g, v)
	draw_pieces(r, s, g, false)
	draw_figures(r, g)
	draw_water(g, time)
	draw_pieces(r, s, g, true)
	draw_decals(g)
	draw_glows(r, s, g, v)
	end_3d()

	draw_clouds(r, s, g, v, time, true)
	draw_motes(r, s, v)
	draw_markers(g, v)
	draw_teach(g, v, time)
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
	lk := look(g.data.setting)
	set_v3(r, .Mist_Color, lk.mist)
	set_f(r, .Daylight, lk.daylight)
	set_f(r, .Moonlight, (1 - lk.gloom) * (1 - 0.45 * s.moon_cover))
	list, n := candle_lights(g)
	reach: [MAX_CANDLES]f32
	for k in 0 ..< n {
		reach[k] = 1.7
	}
	// the candelabra burning light far more of the palace than a candle
	for _, i in g.data.candelabra {
		f := game.candelabrum_flame(g, i)
		if f <= 0.003 || n == MAX_CANDLES {
			continue
		}
		p := candelabrum_world(g, i) + {0, 0, 1.0}
		fl := 0.9 + 0.07 * math.sin(g.time * 11 + f32(i) * 2.3) + 0.03 * math.sin(g.time * 29 + f32(i))
		list[n] = {p.x, p.y, p.z, 1.15 * f * fl}
		reach[n] = 1.2 + 1.6 * f
		n += 1
	}
	rl.SetShaderValueV(r.material.shader, r.loc[.Candles], &list, .VEC4, i32(max(n, 1)))
	rl.SetShaderValueV(r.material.shader, r.loc[.Candle_Reach], &reach, .FLOAT, i32(max(n, 1)))
	count := i32(n)
	rl.SetShaderValue(r.material.shader, r.loc[.Candle_Count], &count, .INT)
}

MAX_CANDLES :: 16 // as in palace.fs

// Where candelabrum i's foot is drawn now (it rises with the palace on arrival).
candelabrum_world :: proc(g: ^game.Game, i: int) -> Vec3 {
	p := game.candelabrum_base(g, i)
	if g.phase == .Arrival {
		d := g.data.candelabra[i].cell - g.data.start
		k := game.arrival_rise(g, math.sqrt(f32(d.x * d.x + d.y * d.y)) + f32(abs(d.z)) * 0.3, 1)
		p.z -= 9 * (1 - k)
	}
	return p
}

// The candles lit on the walls (where the setting lights them): their flames
// in the world and how bright each burns now (flickering; during the arrival,
// once its wall has risen into place).
candle_lights :: proc(g: ^game.Game) -> (list: [MAX_CANDLES][4]f32, n: int) {
	if !look(g.data.setting).candles {
		return
	}
	t := g.time
	for prop, i in g.data.props {
		if prop.kind != .Sconce || prop.part > 0 || n == MAX_CANDLES {
			continue
		}
		fp := Vec3{f32(prop.cell.x), f32(prop.cell.y), f32(prop.cell.z)} + candle_flame(prop.dir)
		a := f32(1)
		if g.phase == .Arrival {
			c := prop.cell - g.data.start
			k := game.arrival_rise(g, math.sqrt(f32(c.x * c.x + c.y * c.y)) + f32(abs(c.z)) * 0.3, 1)
			fp.z -= 9 * (1 - k)
			a = k * k
		}
		fl := 0.85 + 0.1 * math.sin(t * 13 + f32(i) * 1.7) + 0.05 * math.sin(t * 31 + f32(i))
		list[n] = {fp.x, fp.y, fp.z, fl * a}
		n += 1
	}
	return
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

// Where a point given in cell space of block entry i is in the world now
// (parts turn about their pivot, animated while a handle turns them).
block_world :: proc(g: ^game.Game, i: int, local: Vec3) -> Vec3 {
	e := g.data.blocks[i]
	return part_point(g, e.part, Vec3{f32(e.cell.x), f32(e.cell.y), f32(e.cell.z)} + local)
}

// A world point of part n-1 (n = 0: fixed) as the part is turned now.
part_point :: proc(g: ^game.Game, n: u8, w: Vec3) -> Vec3 {
	if n == 0 {
		return w
	}
	pv := g.data.parts[n - 1].pivot
	c := Vec3{f32(pv.x) + 0.5, f32(pv.y) + 0.5, 0}
	a := game.part_angle(g, int(n - 1)) * math.PI * 0.5
	d := w - c
	return c + {d.x * math.cos(a) - d.y * math.sin(a), d.x * math.sin(a) + d.y * math.cos(a), d.z}
}

@(private)
piece_matrix :: proc(g: ^game.Game, p: Piece, lift: f32) -> rl.Matrix {
	m := rl.MatrixTranslate(f32(p.cell.x), f32(p.cell.y), f32(p.cell.z) + lift)
	if p.part > 0 {
		pv := g.data.parts[p.part - 1].pivot
		c := Vec3{f32(pv.x) + 0.5, f32(pv.y) + 0.5, 0}
		a := game.part_angle(g, int(p.part - 1)) * math.PI * 0.5
		m = rl.MatrixTranslate(c.x, c.y, 0) * rl.MatrixRotateZ(a) * rl.MatrixTranslate(-c.x, -c.y, 0) * m
	}
	return m
}

// The cell a piece stands in now.
@(private)
piece_cell :: proc(g: ^game.Game, p: Piece) -> Cell {
	if p.block >= 0 {
		return pl.block_cell(&g.palace, int(p.block))
	}
	if p.part > 0 {
		return level.part_cell(p.cell, g.data.parts[p.part - 1].pivot, g.palace.part_rot[p.part - 1])
	}
	return p.cell
}

// Lift, opacity and visibility of piece i in this frame; `ghost`: drawn with
// the see-through pieces (phantoms, veiled blocks shown by the lamp).
@(private)
piece_state :: proc(g: ^game.Game, p: Piece, i: int) -> (lift, alpha: f32, visible, ghost, hidden: bool) {
	alpha = 1
	visible = true
	hidden = p.sigil == .Off
	switch p.sigil {
	case .None:
	case .Off:
		visible = !g.activated
	case .On:
		visible = g.activated
	}
	if p.rise_index >= 0 {
		if g.rise_t < 0 {
			return 0, 0, false, false, false
		}
		start := f32(p.rise_index) * game.RISE_DELAY
		lift = rise_lift(g, int(p.rise_index))
		alpha = fx.progress(g.rise_t, start, 0.8)
	}
	if p.block >= 0 {
		t := g.flip_t[p.block]
		switch g.data.blocks[p.block].trait {
		case .Stone:
		case .Crumble:
			if t >= 0 {
				lift -= 7 * fx.quad_in(fx.clamp01(t / game.FALL_TIME))
				alpha = 1 - fx.progress(t, game.FALL_TIME * 0.45, game.FALL_TIME * 0.55)
			}
		case .Phantom:
			ghost = true
			if t >= 0 {
				alpha = 1 - fx.progress(t, 0, game.DISSOLVE_TIME)
				lift += 0.35 * fx.cubic_out(fx.clamp01(t / game.DISSOLVE_TIME))
			}
		case .Veiled:
			if t < 0 {
				ghost, hidden = true, true
			} else {
				alpha = fx.progress(t, 0, game.DISSOLVE_TIME)
				lift -= 0.3 * (1 - fx.cubic_out(fx.clamp01(t / game.DISSOLVE_TIME)))
			}
		}
	}
	if g.arrive_t >= 0 && g.phase == .Arrival {
		// the palace rises into place, the stones nearest the start first
		c := p.cell - g.data.start
		d := math.sqrt(f32(c.x * c.x + c.y * c.y)) + f32(abs(c.z)) * 0.3
		k := game.arrival_rise(g, d, fx.hash01(u32(i) * 31 + 7))
		lift -= 9 * (1 - k)
		alpha *= fx.clamp01(k * 1.6)
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

// Opaque pieces first (transparent = false), then the see-through ones, far to near.
@(private)
draw_pieces :: proc(r: ^Renderer, s: ^Scene, g: ^game.Game, transparent: bool) {
	Drawn :: struct {
		index: int,
		depth: f32,
	}
	order := make([dynamic]Drawn, 0, len(s.pieces), context.temp_allocator)
	for p, i in s.pieces {
		_, alpha, visible, ghost, hidden := piece_state(g, p, i)
		if visible && (alpha < 1 || hidden || ghost) == transparent {
			c := piece_cell(g, p)
			d := iso.depth(iso.view_point({f32(c.x) + 0.5, f32(c.y) + 0.5, f32(c.z) + 0.5}, g.angle, g.data.size))
			append(&order, Drawn{i, d})
		}
	}
	if transparent {
		slice.sort_by(order[:], proc(a, b: Drawn) -> bool {return a.depth < b.depth})
	}
	for o in order {
		i := o.index
		p := s.pieces[i]
		lift, alpha, _, _, hidden := piece_state(g, p, i)
		material := p.material
		detail: f32 = 0
		if p.cube && material != .Phantom {
			covered := pl.solid_at(&g.palace, piece_cell(g, p) + {0, 0, 1}).kind != .None
			material = covered ? .Masonry : .Marble
			detail = covered ? 2 : 1
			if p.ground {
				material, detail = covered || !p.lawn ? .Rock : .Lawn, 0
			} else if p.lawn {
				material, detail = .Lawn, 0
			}
		}
		// a veiled stone shows as a faint golden ghost; the seal's panel glows full
		ghost_veil := hidden && p.block >= 0
		set_piece_uniforms(r, material, detail, hidden ? (ghost_veil ? 2 : 1) : 0, alpha, 0.25, 0)
		m := piece_matrix(g, p, lift)
		rl.DrawMesh(r.meshes[p.mesh], r.material, m)
		if p.handle >= 0 {
			// the wheel turns while the handle works its part
			part := g.data.handles[p.handle].part
			spin := game.part_angle(g, part) * math.PI
			ax := CRANK_AXIS
			wm := rl.MatrixTranslate(f32(p.cell.x) + ax.x, f32(p.cell.y) + ax.y, f32(p.cell.z) + ax.z) * rl.MatrixRotateZ(spin)
			rl.DrawMesh(r.meshes[.Crank_Wheel], r.material, wm)
		}
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

	draw_fragments(r, g)

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

// How visible fragment i's scroll is: faint when collected in an earlier
// play, rising and fading when picked up now.
@(private)
fragment_alpha :: proc(g: ^game.Game, i: int) -> (alpha, lift: f32) {
	if g.phase == .Prologue {
		return 0, 0
	}
	if i in g.fragments_known {
		return 0.28, 0
	}
	if i in g.fragments_taken {
		u := fx.clamp01(g.fragment_t[i] / 1.4)
		return 1 - u, fx.cubic_out(u) * 0.6
	}
	return 1, 0
}

@(private)
draw_fragments :: proc(r: ^Renderer, g: ^game.Game) {
	for _, i in g.data.fragments {
		alpha, lift := fragment_alpha(g, i)
		if alpha <= 0.003 {
			continue
		}
		p := game.fragment_world(g, i) + {0, 0, lift}
		set_piece_uniforms(r, .Psyche, 0, 0, alpha, 0.9, i in g.fragments_known ? 0 : 0.1)
		// laid on its side, turning slowly
		m := rl.MatrixTranslate(p.x, p.y, p.z) * rl.MatrixRotateZ(g.time * 0.5 + f32(i)) * rl.MatrixRotateX(math.PI / 2) * rl.MatrixTranslate(0, 0, -0.14)
		rl.DrawMesh(r.meshes[.Scroll], r.material, m)
	}
}

@(private)
cupid_fade :: proc(g: ^game.Game) -> f32 {
	if g.amore.fly_t < 0 {
		return 1
	}
	return 1 - fx.progress(g.amore.fly_t, 0.6, 2.2)
}

// How far below its place the i-th stone raised by the seal is now (<= 0).
rise_lift :: proc(g: ^game.Game, i: int) -> f32 {
	if g.rise_t < 0 {
		return -game.RISE_DEPTH
	}
	return -game.RISE_DEPTH * (1 - fx.cubic_out(fx.progress(g.rise_t, f32(i) * game.RISE_DELAY, game.RISE_TIME)))
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

WATER_Z :: 0.72 // the river's surface: just under the h1 platforms

// The river: a dark surface that fades out at the edges of its rectangle,
// glints of moonlight drifting with the current (along x), the lamp's warmth
// near Psyche, and a ring of foam around every stone standing in it.
@(private)
draw_water :: proc(g: ^game.Game, time: f32) {
	if len(g.data.water) == 0 {
		return
	}
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	lamp := game.lamp_world(g)
	warm := g.data.has_lamp ? g.light : 0
	for w in g.data.water {
		x0, y0 := f32(w[0]), f32(w[1])
		x1, y1 := f32(w[2] + 1), f32(w[3] + 1)
		edge :: proc(v, lo, hi: f32) -> f32 {
			return fx.clamp01(min(v - lo, hi - v) / 1.2)
		}
		point :: proc(x, y, x0, y0, x1, y1: f32, lamp: Vec3, warm: f32) {
			a := edge(x, x0, x1) * edge(y, y0, y1)
			a = a * a * (3 - 2 * a)
			d := Vec2{x - lamp.x, y - lamp.y}
			lit := warm * fx.clamp01(1 - math.sqrt(d.x * d.x + d.y * d.y) / 3)
			c := fx.lerp(Color4{0.08, 0.12, 0.27, 0.8}, Color4{0.4, 0.25, 0.1, 0.85}, lit)
			c.a *= a
			color(c)
			vtx({x, y, WATER_Z})
		}
		STEP :: 0.5
		rlgl.Begin(rlgl.TRIANGLES)
		for y := y0; y < y1 - 0.001; y += STEP {
			for x := x0; x < x1 - 0.001; x += STEP {
				point(x, y, x0, y0, x1, y1, lamp, warm)
				point(x + STEP, y, x0, y0, x1, y1, lamp, warm)
				point(x + STEP, y + STEP, x0, y0, x1, y1, lamp, warm)
				point(x, y, x0, y0, x1, y1, lamp, warm)
				point(x + STEP, y + STEP, x0, y0, x1, y1, lamp, warm)
				point(x, y + STEP, x0, y0, x1, y1, lamp, warm)
			}
		}
		rlgl.End()
		// glints of moonlight drifting with the current
		for cy in w[1] ..= w[3] {
			for cx in w[0] ..= w[2] {
				for k in 0 ..< 3 {
					h := u32(cx * 73 + cy * 151 + i32(k) * 31)
					u := math.mod(time * (0.08 + 0.05 * fx.hash01(h)) + fx.hash01(h + 1), 1)
					px := f32(cx) + u
					py := f32(cy) + 0.15 + 0.7 * fx.hash01(h + 2)
					a := edge(px, x0, x1) * edge(py, y0, y1) * math.sin(u * math.PI)
					len := 0.12 + 0.18 * fx.hash01(h + 3)
					floor_strip({px, py, WATER_Z + 0.003}, {px + len, py, WATER_Z + 0.003}, {0, 1, 0}, 0.022, {0.65, 0.75, 1.0, 0.4 * a})
				}
			}
		}
		// foam where the stones stand in the river
		for e, i in g.data.blocks {
			c := e.cell
			if c.z != 0 || c.x < w[0] || c.x > w[2] || c.y < w[1] || c.y > w[3] || !pl.block_present(&g.palace, i) {
				continue
			}
			t := math.mod(time * 0.35 + fx.hash01(u32(i) * 7), 1)
			floor_ring({f32(c.x) + 0.5, f32(c.y) + 0.5, WATER_Z + 0.002}, 0.68 + 0.12 * t, 0.025, {0.7, 0.8, 1.0, 0.3 * (1 - t)})
		}
	}
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
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

	// a few small flowers in the grass, pale in the moonlight
	FLOWER := [3]Color4{{0.92, 0.9, 1.0, 0.85}, {1.0, 0.9, 0.55, 0.8}, {0.8, 0.65, 1.0, 0.8}}
	for c, n in g.data.lawn {
		for k in 0 ..< 6 {
			h := u32(n * 31 + k * 7)
			p := Vec3{f32(c.x) + 0.12 + 0.76 * fx.hash01(h * 3 + 1), f32(c.y) + 0.12 + 0.76 * fx.hash01(h * 3 + 2), f32(c.z) + 1.006}
			if g.psyche.cell == c + {0, 0, 1} && linalg_dot(p - g.psyche.pos, p - g.psyche.pos) < 0.04 {
				continue // trodden under her feet
			}
			floor_ellipse(p, 0.028, 0.028, FLOWER[k % 3])
		}
	}

	// cracks on the stones that will fall; a bronze inlay on the parts that turn
	for e, i in g.data.blocks {
		if (e.trait != .Crumble && e.part == 0) || !pl.block_present(&g.palace, i) || g.flip_t[i] >= 0 {
			continue
		}
		if e.solid.kind != .Block || pl.solid_at(&g.palace, pl.block_cell(&g.palace, i) + {0, 0, 1}).kind != .None {
			continue
		}
		top :: proc(g: ^game.Game, i: int, x, y: f32) -> Vec3 {
			return block_world(g, i, {x, y, 1.006})
		}
		if e.part > 0 {
			col := Color4{0.62, 0.48, 0.26, 0.6}
			I :: 0.14
			W :: 0.035
			corners := [4][2]f32{{I, I}, {1 - I, I}, {1 - I, 1 - I}, {I, 1 - I}}
			for k in 0 ..< 4 {
				a, b := corners[k], corners[(k + 1) % 4]
				inward := top(g, i, 0.5, 0.5) - top(g, i, (a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
				inward /= math.sqrt(linalg_dot(inward, inward))
				floor_strip(top(g, i, a.x, a.y), top(g, i, b.x, b.y), inward, W, col)
			}
		}
		if e.trait == .Crumble {
			// three jagged cracks from near the centre to the edges
			for k in 0 ..< 3 {
				h := u32(i * 13 + k * 5)
				ang := f32(k) * math.TAU / 3 + fx.hash01(h) * 1.2
				prev := [2]f32{0.5 + 0.06 * math.cos(ang), 0.5 + 0.06 * math.sin(ang)}
				for step in 1 ..= 4 {
					rad := 0.06 + 0.4 * f32(step) / 4
					wob := (fx.hash01(h + u32(step) * 17) - 0.5) * 0.5
					next := [2]f32{0.5 + rad * math.cos(ang + wob), 0.5 + rad * math.sin(ang + wob)}
					a, b := top(g, i, prev.x, prev.y), top(g, i, next.x, next.y)
					d := b - a
					side := Vec3{-d.y, d.x, 0}
					side /= max(math.sqrt(linalg_dot(side, side)), 1e-4)
					floor_strip(a, b, side, 0.022 * (1 - f32(step) / 5), {0.02, 0.02, 0.06, 0.85})
					prev = next
				}
			}
		}
	}


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
	// the fragments' faint glow
	for _, i in g.data.fragments {
		if a, lift := fragment_alpha(g, i); a > 0.003 && i not_in g.fragments_known {
			c := game.fragment_world(g, i) + {0, 0, lift}
			glow(v, c, 58, {1.0, 0.86, 0.55, a * (0.3 + 0.08 * math.sin(t * 2.1 + f32(i)))})
			glow(v, c, 16, {1.0, 0.95, 0.8, a * 0.45})
		}
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
	// the candles on the walls, where the setting has them lit
	{
		list, n := candle_lights(g)
		for c in list[:n] {
			fp, fl := Vec3{c.x, c.y, c.z}, c.w
			glow(v, fp, 64, {1.0, 0.6, 0.26, 0.26 * fl})
			glow(v, fp, 18, {1.0, 0.7, 0.35, 0.35 * fl})
			glow(v, fp + {0, 0, 0.02}, 6, {1.0, 0.78, 0.42, fl}, 1.8)
			glow(v, fp + {0, 0, 0.02}, 2.6, {1.0, 0.96, 0.85, fl}, 1.6)
		}
	}
	// the candelabra: three flames each, a warm halo; one just lit flares up
	for _, i in g.data.candelabra {
		burn := game.candelabrum_flame(g, i)
		if burn <= 0.003 {
			continue
		}
		base := candelabrum_world(g, i)
		flare: f32 = 0
		if since := g.candelabrum_t[i]; since >= 0 {
			flare = math.exp(-since * 2.5)
		}
		glow(v, base + {0, 0, 1.0}, 90 * (1 + flare), {1.0, 0.62, 0.28, (0.22 + 0.3 * flare) * burn})
		for fp, k in CANDELABRUM_FLAMES {
			fl := (0.85 + 0.1 * math.sin(t * 13 + f32(i * 3 + k) * 1.7) + 0.05 * math.sin(t * 31 + f32(k))) * burn
			p := base + Vec3(fp)
			glow(v, p, 5, {1.0, 0.78, 0.42, fl}, 1.8)
			glow(v, p, 2.2, {1.0, 0.96, 0.85, fl}, 1.6)
		}
	}
	// the braziers Psyche has lit
	for c, i in g.data.rests {
		if !g.rests_lit[i] {
			continue
		}
		fp := Vec3{f32(c.x), f32(c.y), f32(c.z)} + ALTAR_FLAME
		fl := 0.85 + 0.1 * math.sin(t * 17 + f32(i) * 2.3) + 0.05 * math.sin(t * 29 + f32(i))
		glow(v, fp, 70, {1.0, 0.6, 0.25, 0.22 * fl})
		glow(v, fp + {0, 0, 0.03}, 8, {1.0, 0.75, 0.4, fl}, 1.6)
		glow(v, fp + {0, 0, 0.03}, 3.5, {1.0, 0.95, 0.8, fl}, 1.5)
	}
	// the stones the seal raises glow gold as they come up, and a while after
	if g.rise_t >= 0 {
		for e, i in g.data.rise {
			k := fx.progress(g.rise_t, f32(i) * game.RISE_DELAY, game.RISE_TIME)
			after := g.rise_t - game.rise_landing(i)
			a := k > 0 ? (after < 0 ? 0.55 * k + 0.2 : 0.75 * math.exp(-after * 1.3)) : 0
			if a < 0.01 {
				continue
			}
			c := Vec3{f32(e.cell.x) + 0.5, f32(e.cell.y) + 0.5, f32(e.cell.z) + 1.0} + {0, 0, rise_lift(g, i)}
			glow(v, c, 70, {1.0, 0.75, 0.35, a * 0.5})
			glow(v, c - {0, 0, 0.5}, 40, {1.0, 0.85, 0.5, a * 0.35}, 2.2)
		}
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
	for p in fx.alive(&s.debris) {
		col := p.color
		col.a *= fx.mote_alpha(p)
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
set_bf :: proc(b: Backdrop, u: Backdrop_Uniform, value: f32) {
	v := value
	rl.SetShaderValue(b.shader, b.loc[u], &v, .FLOAT)
}

@(private)
set_bv2 :: proc(b: Backdrop, u: Backdrop_Uniform, value: Vec2) {
	v := value
	rl.SetShaderValue(b.shader, b.loc[u], &v, .VEC2)
}

@(private)
set_bv3 :: proc(b: Backdrop, u: Backdrop_Uniform, value: Vec3) {
	v := value
	rl.SetShaderValue(b.shader, b.loc[u], &v, .VEC3)
}

// Where the sky meets the sea of clouds, in screen uv (the bottom of the
// screen when the setting has no ranges: the night sky as it always was).
@(private)
horizon_uv :: proc(s: ^Scene, g: ^game.Game, v: View) -> f32 {
	if look(g.data.setting).ridges == 0 {
		return 1
	}
	return proto_to_screen(v, {0, s.fit.y + s.fit.h - 430}).y / v.height
}

// The sky and the far ranges share the orb, the horizon and the turn.
@(private)
set_sky_uniforms :: proc(b: Backdrop, s: ^Scene, g: ^game.Game, v: View) {
	lk := look(g.data.setting)
	set_bf(b, .Shift, g.angle)
	set_bf(b, .Aspect, v.width / v.height)
	set_bf(b, .Horizon, horizon_uv(s, g, v))
	set_bv2(b, .Orb_Pos, lk.orb_pos)
	set_bv3(b, .Halo_Color, lk.halo_color)
	set_bf(b, .Halo_Width, lk.halo_width)
	set_bv3(b, .Haze, lk.haze)
}

// The veil between the levels, over the world (not over the interface).
draw_veil :: proc(r: ^Renderer, g: ^game.Game, width, height, time: f32) {
	a := game.veil(g)
	if a <= 0.003 {
		return
	}
	b := r.veil
	set_bf(b, .Time, time)
	set_bf(b, .Aspect, width / height)
	v := a
	rl.SetShaderValue(b.shader, r.veil_alpha, &v, .FLOAT)
	rl.BeginShaderMode(b.shader)
	full_rect(r, {0, 0, width, height})
	rl.EndShaderMode()
}

@(private)
draw_sky :: proc(r: ^Renderer, s: ^Scene, g: ^game.Game, v: View, time: f32) {
	b := r.sky
	lk := look(g.data.setting)
	set_sky_uniforms(b, s, g, v)
	set_bf(b, .Light_Amount, g.light * 0.8)
	set_bf(b, .Time, time)
	set_bv3(b, .Sky_Top, lk.sky_top)
	set_bv3(b, .Sky_Mid, lk.sky_mid)
	set_bv3(b, .Sky_Horizon, lk.sky_horizon)
	set_bf(b, .Orb_Radius, lk.orb_radius)
	set_bv3(b, .Orb_Color, lk.orb_color)
	set_bf(b, .Stars, lk.stars)
	set_bf(b, .Night_Clouds, lk.moon_clouds)
	s.moon_cover = moon_cover(lk, time, g.angle, v.width / v.height)
	rl.BeginShaderMode(b.shader)
	full_rect(r, {0, 0, v.width, v.height})
	rl.EndShaderMode()
}

// The mountain ranges between the sky and the sea of clouds.
@(private)
draw_ridges :: proc(r: ^Renderer, s: ^Scene, g: ^game.Game, v: View) {
	b := r.ridges
	lk := look(g.data.setting)
	set_sky_uniforms(b, s, g, v)
	set_bf(b, .Light_Amount, g.light * 0.8)
	set_bv3(b, .Color_Far, lk.ridge_color[0])
	set_bv3(b, .Color_Mid, lk.ridge_color[1])
	set_bv3(b, .Color_Near, lk.ridge_color[2])
	set_bv3(b, .Rim, lk.ridge_rim)
	rl.BeginShaderMode(b.shader)
	full_rect(r, {0, 0, v.width, v.height})
	rl.EndShaderMode()
}

@(private)
draw_clouds :: proc(r: ^Renderer, s: ^Scene, g: ^game.Game, v: View, time: f32, front: bool) {
	b := r.clouds
	lk := look(g.data.setting)
	top := s.fit.y + s.fit.h - (front ? 330 : 520)
	a := proto_to_screen(v, {s.fit.x - 1400, top})
	c := proto_to_screen(v, {s.fit.x + s.fit.w + 1400, top + 700})
	set_bf(b, .Light_Amount, g.light)
	set_bf(b, .Shift, g.angle * 0.8)
	set_bf(b, .Time, time)
	set_bf(b, .Density, front ? 0.9 : 1.0)
	set_bv3(b, .Tint, front ? lk.cloud_front : lk.cloud_back)
	set_bv3(b, .Crest_Color, lk.cloud_crest)
	rl.BeginShaderMode(b.shader)
	full_rect(r, {a.x, a.y, c.x - a.x, c.y - a.y})
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

// The pieces of the level's new mechanic, pointed out while its card is read
// (and a few seconds after): a pulsing golden diamond on each top. Veiled
// stones are shown where they would stand.
@(private)
draw_teach :: proc(g: ^game.Game, v: View, time: f32) {
	glow := game.teach_glow(g)
	if glow <= 0.003 {
		return
	}
	pulse := 0.6 + 0.4 * math.sin(time * 4)
	col := Color4{1.0, 0.82, 0.42, 0.9 * glow * pulse}
	outline :: proc(v: View, a, b, c, d: Vec3, col: Color4, width: f32) {
		pts := [4]Vec3{a, b, c, d}
		for i in 0 ..< 4 {
			p := world_to_screen(v, pts[i])
			q := world_to_screen(v, pts[(i + 1) % 4])
			rl.DrawLineEx(p, q, width, to_color(col))
		}
	}
	width := max(3 * v.zoom, 1)
	top :: proc(g: ^game.Game, i: int, x, y: f32) -> Vec3 {
		return block_world(g, i, {x, y, 1.01})
	}
	mech := g.data.mechanic
	for e, i in g.data.blocks {
		want := false
		switch mech {
		case .None:
		case .Crumble: want = e.trait == .Crumble && pl.block_present(&g.palace, i)
		case .Phantom: want = e.trait == .Phantom && pl.block_present(&g.palace, i)
		case .Veiled: want = e.trait == .Veiled && !g.palace.flipped[i]
		case .Handle: want = e.part > 0
		}
		if !want || pl.solid_at(&g.palace, pl.block_cell(&g.palace, i) + {0, 0, 1}).kind != .None {
			continue
		}
		I :: 0.06
		outline(v, top(g, i, I, I), top(g, i, 1 - I, I), top(g, i, 1 - I, 1 - I), top(g, i, I, 1 - I), col, width)
		J :: 0.3
		outline(v, top(g, i, J, J), top(g, i, 1 - J, J), top(g, i, 1 - J, 1 - J), top(g, i, J, 1 - J), {col.r, col.g, col.b, col.a * 0.5}, width * 0.7)
	}
	if mech == .Handle {
		for h in g.data.handles {
			c := Vec3{f32(h.cell.x), f32(h.cell.y), f32(h.cell.z) + 0.01}
			outline(v, c + {0.06, 0.06, 0}, c + {0.94, 0.06, 0}, c + {0.94, 0.94, 0}, c + {0.06, 0.94, 0}, col, width)
		}
	}
}
