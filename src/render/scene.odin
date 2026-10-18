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
import "../ui"

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
	Sun_Truth,
	Rock_Tint,
	Turned,
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
	.Sun_Truth     = "sun_truth",
	.Rock_Tint     = "rock_tint",
	.Turned        = "turned",
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
	sundial:    bool, // the crank of a sundial (its wheel turns with the time)
	sigil:      enum u8 {
		None,
		Off, // only the lamp shows it, until it is lit
		On,
	},
	seal:       u8, // the seal of a sigil piece (data.sigils index)
	under:      bool, // of the world under the palace: `cell` is in its frame
}

Scene :: struct {
	pieces:     [dynamic]Piece,
	see:        []f32, // per piece: 0 .. 1 faded, standing between the camera and Psyche
	see_through: bool, // the accessibility setting (fade them)
	fit:        Rect, // proto pixels that hold the palace from every view
	motes:      fx.Pool(64), // drifting in front of everything (proto px)
	sparks:     fx.Pool(64), // around Cupid (world)
	dust:       fx.Pool(192), // falling from the cracks (world)
	debris:     fx.Pool(160), // gold gathering where a veiled stone becomes real (world)
	embers:     fx.Pool(160), // rising from the pieces as the diorama breaks up (world)
	wind:       fx.Pool(96), // Zephyr's breath over the exit (world)
	mist:       fx.Pool(128), // the Stygian sleep out of Proserpina's box (world, dark)
	rng:        fx.Rng,
	mote:       Color4, // the colour of the drifting motes (from the setting)
	moon_cover: f32, // how much the night clouds hide the moon now (0..1)
	// a tall level (`tier` lines): the camera frames one band of heights at a
	// time and pans up or down when Psyche changes band
	frames:     [level.MAX_TIERS]Rect, // proto pixels that hold each band from every view
	frame_h:    f32, // the tallest band: the zoom is the same for all of them
	tier:       int, // the band the camera frames (or pans to)
	pan_from:   f32, // the centre's proto y where the pan began
	pan_t:      f32, // seconds since it began
	stage:      f32, // 0 .. 1: the level select shows the whole diorama on the right of the screen
}


PAN_TIME :: 1.8 // the camera moving from one band of a tall level to the next

scene_build :: proc(s: ^Scene, g: ^game.Game, allocator := context.allocator) {
	s^ = {}
	s.pieces = make([dynamic]Piece, 0, len(g.data.blocks) + 2 * len(g.data.props) + 2 * len(g.data.candelabra) + 2 * len(g.data.caves) + len(g.data.rise) + len(g.data.handles) + 2 * len(g.data.sigils) + len(g.data.sundials) + len(g.data.eagles), allocator)
	s.rng = fx.rng_init(1234)
	s.mote = look_of(g).mote
	for e, i in g.data.blocks {
		p := solid_piece(e.cell, e.solid, -1)
		p.block = i32(i)
		p.part = e.part
		p.under = e.under
		earth(g, &p)
		for pk in g.data.planks {
			if pk.cell == level.world_cell(&g.data, e.cell, e.under) {
				p.mesh = pk.along_y ? .Plank_Y : .Plank_X
				p.material, p.cube, p.lawn, p.ground = .Wood, false, false, false
			}
		}
		append(&s.pieces, p)
	}
	for prop in g.data.props {
		look := PROP_LOOK[prop.kind]
		for each in ([2]Maybe(Prop_Piece){look.body, look.extra}) {
			pc := each.? or_continue
			if level.PROPS[prop.kind].dir != .None {
				pc.mesh = oriented_mesh(pc.mesh, prop.dir)
			}
			append(&s.pieces, piece(prop.cell, pc.mesh, pc.material, prop.part, prop.under))
		}
	}
	for c in g.data.candelabra {
		append(&s.pieces, piece(c.cell, oriented_mesh(.Candelabrum_PX, c.dir), .Bronze, 0, c.under))
		append(&s.pieces, piece(c.cell, oriented_mesh(.Candelabrum_Wax_PX, c.dir), .Psyche, 0, c.under))
	}
	for c in g.data.pomegranates {
		// on both faces of its stone: one for each world
		for under in ([2]bool{false, true}) {
			append(&s.pieces, piece(c, .Pomegranate_Dish, .Bronze, 0, under))
			append(&s.pieces, piece(c, .Pomegranate, .Pomegranate, 0, under))
		}
	}
	for c in g.data.caves {
		append(&s.pieces, piece(c.cell, oriented_mesh(.Cave_PX, c.dir), .Rock))
		append(&s.pieces, piece(c.cell, oriented_mesh(.Cave_Dark_PX, c.dir), .Void))
	}
	for h, i in g.data.handles {
		append(&s.pieces, handle_piece(h.cell, i))
	}
	for c in g.data.sundials {
		append(&s.pieces, sundial_piece(c))
	}
	for e in g.data.eagles {
		append(&s.pieces, piece(e.from, .Perch, .Bronze))
	}
	for c in g.data.rests {
		append(&s.pieces, piece(c, .Altar, .Bronze))
	}
	for e, i in g.data.rise {
		p := solid_piece(e.cell, e.solid, i32(i))
		p.under = e.under
		earth(g, &p)
		append(&s.pieces, p)
	}
	for c, k in g.data.sigils {
		if k in g.data.guard_seals {
			continue // a guard candelabrum: no seal on the stone
		}
		append(&s.pieces, sigil_piece(c, .Sigil_Off, .Off, k, k in g.data.sigils_under))
		append(&s.pieces, sigil_piece(c, .Sigil_On, .On, k, k in g.data.sigils_under))
	}

	// framing: every piece from every view (as the prototype's fit_rect), parts in every position
	first := true
	for p in s.pieces {
		rect := piece_bounds(g, p, p.mesh == .Block ? -96 : -120)
		s.fit = first ? rect : rect_merge(s.fit, rect)
		first = false
	}
	// what the diorama stands on: after the framing, which holds the palace alone
	for f in g.data.floors {
		if f.kind != .Basin {
			continue
		}
		a := f.area
		for y in a[1] ..= a[3] {
			for x in a[0] ..= a[2] {
				c := Cell{x, y, g.data.floor_h - 1}
				if len(g.data.pomegranates) == 0 {
					// (no bottom where the world turns over: the other world hangs under it)
					append(&s.pieces, piece(c, .Basin_Floor, RIM_MATERIAL[f.rim]))
				}
				for d in iso.Dir {
					step := iso.DIR_VEC[d]
					if x + step.x < a[0] || x + step.x > a[2] || y + step.y < a[1] || y + step.y > a[3] {
						if boat_gap(g, c, d) {
							continue // the mouth Charon's boat leaves by
						}
						append(&s.pieces, piece(c, oriented_mesh(.Rim_PX, d), RIM_MATERIAL[f.rim]))
					}
				}
			}
		}
	}
	s.see = make([]f32, len(s.pieces), allocator)
	// a tall level: each band of heights framed from every view (the pieces of
	// the band, a little of the rock under it and the figure over it)
	for t, i in g.data.tiers {
		first = true
		for p in s.pieces {
			if p.cell.z < t[0] - 3 || p.cell.z > t[1] || p.under {
				continue
			}
			rect := piece_bounds(g, p, -120)
			s.frames[i] = first ? rect : rect_merge(s.frames[i], rect)
			first = false
		}
		s.frame_h = max(s.frame_h, s.frames[i].h)
	}
	s.tier = camera_tier(g)
	s.pan_t = PAN_TIME

	// ambient motes start mid-life, as if they had always been there
	for _ in 0 ..< 40 {
		emit_mote(s, true)
	}
}

// The rim's side `d` of cell c lies on the way Charon's boat leaves the level
// by (out from the exit's landing, along its side): it is left open.
@(private)
boat_gap :: proc(g: ^game.Game, c: Cell, d: iso.Dir) -> bool {
	if !g.data.has_boat || d != g.data.boat.dir {
		return false
	}
	b := g.data.boat.cell
	step := iso.DIR_VEC[d]
	along := (c.x - b.x) * step.x + (c.y - b.y) * step.y
	return along > 0 && (step.x != 0 ? c.y == b.y : c.x == b.x)
}

// A piece of decoration (or of a part, n > 0) at cell c.
@(private)
piece :: proc(c: Cell, mesh: Mesh_Id, material: Material, part: u8 = 0, under := false) -> Piece {
	return {cell = c, mesh = mesh, material = material, rise_index = -1, block = -1, handle = -1, part = part, under = under}
}

@(private)
handle_piece :: proc(c: Cell, i: int) -> Piece {
	p := piece(c, .Crank_Post, .Bronze)
	p.handle = i32(i)
	return p
}

// A sundial's crank: the handle's, in the Sun's gold (drawn larger).
@(private)
sundial_piece :: proc(c: Cell) -> Piece {
	p := piece(c, .Crank_Post, .Fleece)
	p.sundial = true
	return p
}

@(private)
sigil_piece :: proc(c: Cell, mesh: Mesh_Id, state: type_of(Piece{}.sigil), seal: int, under: bool) -> Piece {
	p := piece(c, mesh, .Bronze, 0, under)
	p.sigil, p.seal = state, u8(seal)
	return p
}

// Living rock and grass on a block or stairs (`ground`, `lawn` lines).
@(private)
earth :: proc(g: ^game.Game, p: ^Piece) {
	c := level.world_cell(&g.data, p.cell, p.under)
	for l in g.data.lawn {
		p.lawn ||= l == c && p.cube
	}
	for r in g.data.ground {
		p.ground ||= r == c
	}
	if p.ground && !p.cube {
		p.material = .Lawn // steps cut in the rock: grassy treads, earth risers
	}
}

// What a piece covers on screen (proto px) from every view, a part in every
// position, the world either way up; `top`: how far above its floor centre it reaches.
@(private)
piece_bounds :: proc(g: ^game.Game, p: Piece, top: f32) -> (bounds: Rect) {
	first := true
	for turn in 0 ..< (p.part > 0 ? 4 : 1) {
		cell := p.cell
		if p.part > 0 {
			cell = level.part_cell(cell, g.data.parts[p.part - 1].pivot, turn)
		}
		for upside in 0 ..< (len(g.data.pomegranates) > 0 ? 2 : 1) {
			here := level.frame_cell(&g.data, cell, p.under, upside == 1)
			for r in 0 ..< 4 {
				c := iso.floor_center(iso.to_view(here, r, g.data.size))
				rect := Rect{c.x - 64, c.y + top, 128, 152}
				bounds = first ? rect : rect_merge(bounds, rect)
				first = false
			}
		}
	}
	return
}

@(private)
solid_piece :: proc(c: Cell, solid: level.Solid, rise: i32) -> Piece {
	if solid.kind == .Stairs {
		return {cell = c, mesh = oriented_mesh(.Stairs_PX, solid.dir), material = .Marble, rise_index = rise, block = -1, handle = -1}
	}
	return {cell = c, mesh = .Block, material = .Marble, cube = true, rise_index = rise, block = -1, handle = -1}
}

// --- Proserpina's flip: the world turning over -----------------------------------------

// The half turn about the axle (game.turned_point) that brings a thing of one
// world (`under`: the world under the palace, described in its own frame) to
// where it is drawn now: none for the world up, a half turn for the one that
// hangs below, on the way between the two while the world turns over.
@(private)
turn_angle :: proc(g: ^game.Game, under: bool) -> f32 {
	if len(g.data.pomegranates) == 0 {
		return 0
	}
	return math.PI * (fx.sine_in_out(g.overturn) - (under ? 1 : 0))
}

// A point of one world (`under`), where it is drawn now. The game's own
// points (Psyche, her path) are of the world up now: `g.palace.upside`.
shown :: proc(g: ^game.Game, w: Vec3, under: bool) -> Vec3 {
	a := turn_angle(g, under)
	if a == 0 {
		return w
	}
	y0, z0 := f32(g.data.size) * 0.5, f32(g.data.axle) + 0.5
	c, s := math.cos(a), math.sin(a)
	dy, dz := w.y - y0, w.z - z0
	return {w.x, y0 + c * dy - s * dz, z0 + s * dy + c * dz}
}

// The same half turn for a piece of one world.
@(private)
turn_matrix :: proc(g: ^game.Game, under: bool) -> rl.Matrix {
	a := turn_angle(g, under)
	if a == 0 {
		return rl.Matrix(1)
	}
	y0, z0 := f32(g.data.size) * 0.5, f32(g.data.axle) + 0.5
	c, s := math.cos(a), math.sin(a)
	return rl.Matrix {
		1, 0, 0, 0,
		0, c, -s, y0 - c * y0 + s * z0,
		0, s, c, z0 - s * y0 - c * z0,
		0, 0, 0, 1,
	}
}

// Immediate-mode drawing that follows, as a thing of one world (`under`):
// turned with it. End it with `end_turn`.
@(private)
begin_turn :: proc(g: ^game.Game, under: bool) {
	rlgl.PushMatrix()
	if a := turn_angle(g, under); a != 0 {
		y0, z0 := f32(g.data.size) * 0.5, f32(g.data.axle) + 0.5
		rlgl.Translatef(0, y0, z0)
		rlgl.Rotatef(a * 180 / math.PI, 1, 0, 0)
		rlgl.Translatef(0, -y0, -z0)
	}
}

@(private)
end_turn :: proc() {
	rlgl.PopMatrix()
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

// The band of a tall level that holds Psyche (where she is going, while she
// walks: through a cave the camera pans while she is inside the rock).
camera_tier :: proc(g: ^game.Game) -> int {
	h := g.psyche.walking ? g.psyche.step_to.z : g.psyche.cell.z
	best, gap := 0, i32(1 << 30)
	for t, i in g.data.tiers {
		d := max(t[0] - h, h - t[1], 0)
		if d < gap {
			best, gap = i, d
		}
	}
	return best
}

// The proto y the camera centres on for band i.
@(private)
tier_center :: proc(s: ^Scene, i: int) -> f32 {
	return s.frames[i].y + s.frames[i].h * 0.5 + 40
}

scene_view :: proc(s: ^Scene, g: ^game.Game, width, height: f32) -> View {
	fit := s.fit
	if len(g.data.tiers) > 0 {
		// zoom for the tallest band, the width of the whole crag
		fit.y, fit.h = 0, s.frame_h
	}
	v := make_view(fit, width, height, g.angle, g.data.size, g.data.height, shake_offset(g))
	if len(g.data.tiers) > 0 {
		v.center.y = fx.lerp(s.pan_from, tier_center(s, s.tier), fx.sine_in_out(fx.clamp01(s.pan_t / PAN_TIME)))
	}
	if g.phase == .Prologue || g.boxed {
		cam := game.cine(g)
		her := world_to_proto(v, g.psyche.pos + {0, 0, 0.3})
		if cam.venus > 0 {
			// the goddess, where she stands
			there := world_to_proto(v, pl.stand_world(&g.palace, g.data.prologue) + {0, 0, 0.4})
			her = fx.lerp(her, there, cam.venus)
		}
		v.center = fx.lerp(v.center, her, cam.focus) - {0, cam.look_up * CINE_LOOK_UP}
		v.zoom *= cam.zoom
	}
	v.backdrop_center, v.backdrop_zoom = v.center, v.zoom // far away, the backdrop stays
	if s.stage > 0 {
		// a side panel (the level select, the settings): the whole diorama (every band of a tall level),
		// smaller, its middle right of the screen's, where the panel leaves room
		st := make_view(s.fit, width * ui.STAGE_SIZE.x, height * ui.STAGE_SIZE.y, g.angle, g.data.size, g.data.height, {})
		center := Vec2{s.fit.x + s.fit.w * 0.5, s.fit.y + s.fit.h * 0.5} - ui.STAGE_SHIFT * Vec2{width, height} / st.zoom
		k := fx.sine_in_out(s.stage)
		v.zoom = fx.lerp(v.zoom, st.zoom, k)
		v.center = fx.lerp(v.center, center, k)
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
	update_see_through(s, g, dt)
	if len(g.data.tiers) > 0 {
		s.pan_t += dt
		if t := camera_tier(g); t != s.tier {
			s.pan_from = fx.lerp(s.pan_from, tier_center(s, s.tier), fx.sine_in_out(fx.clamp01(s.pan_t / PAN_TIME)))
			s.tier, s.pan_t = t, 0
		}
	}
	if s.motes.count < 40 && fx.randf(&s.rng) < dt * 40 / 7 * 2 {
		emit_mote(s, false)
	}
	// golden motes around Cupid, more of them when he flies away
	if g.data.has_amore && g.collapse_t < 1.5 && game.assembly(g, g.data.amore, 1) >= 1 {
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
	// Zephyr's breath: motes spiralling up from the exit, a gust when he takes
	// Psyche from the Oracle's crag
	alone_wind := game.procession(g) && g.phase_t > game.prologue_alone(g) - 0.5
	if (g.data.has_exit && g.phase != .Finished && exit_alpha(g) > 0) || alone_wind {
		gust := alone_wind
		want := gust ? 60 : 40
		if s.wind.count < want && fx.randf(&s.rng) < dt * f32(want) / 3 * 2 {
			c := g.data.has_exit ? shown(g, exit_point(g), g.data.exit_under) : g.psyche.pos
			if gust && fx.randf(&s.rng) < 0.7 {
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
	// the stones that stand only by day crumble at evening: dust pours from them
	if g.evening > 0.02 && g.evening < 0.98 {
		for e in g.data.blocks {
			if e.trait != .Sunlit || fx.randf(&s.rng) > dt * 30 {
				continue
			}
			c := Vec3{f32(e.cell.x), f32(e.cell.y), f32(e.cell.z)}
			fx.emit(&s.dust, {
				pos   = c + {fx.randf(&s.rng), fx.randf(&s.rng), fx.rand_range(&s.rng, 0.2, 1.0)},
				vel   = {fx.rand_range(&s.rng, -0.2, 0.2), fx.rand_range(&s.rng, -0.2, 0.2), fx.rand_range(&s.rng, -0.4, 0)},
				accel = {0, 0, -1.4},
				life  = 1.3,
				size  = 32 * fx.rand_range(&s.rng, 0.08, 0.18),
				color = {0.95, 0.82, 0.66, 0.75},
			})
		}
	}
	// the stones the seal raises: a trail of gold as they come up, a burst of dust as they land
	for e, i in g.data.rise {
		rt := game.rise_time(g, i)
		if rt < 0 || rt > game.rise_duration(g, int(e.seal)) + 0.5 || int(e.seal) in g.data.guard_seals {
			continue
		}
		k := fx.progress(rt, game.rise_start(g, i), game.RISE_TIME)
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
		land := game.rise_landing(g, i)
		if rt >= land && rt - dt < land {
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
	// veiled stones gather gold as they become real
	for t, i in g.flip_t {
		if t < 0 || t > 0.9 {
			continue
		}
		if fx.randf(&s.rng) > dt * 40 {
			continue
		}
		c := block_world(g, int(i), {0.5, 0.5, 0.5})
		vel := Vec3{fx.rand_range(&s.rng, -0.4, 0.4), fx.rand_range(&s.rng, -0.4, 0.4), fx.rand_range(&s.rng, -0.6, 0.2)}
		fx.emit(&s.debris, {
			pos   = c + {fx.rand_range(&s.rng, -0.5, 0.5), fx.rand_range(&s.rng, -0.5, 0.5), fx.rand_range(&s.rng, -0.5, 0.5)},
			vel   = -vel * 0.5,
			life  = 1.4,
			size  = 32 * fx.rand_range(&s.rng, 0.1, 0.22),
			color = {1.0, 0.82, 0.45, 0.85},
		})
	}
	// sparks rising from the pieces as the diorama breaks up
	if g.parting && g.phase == .Ending_Exit {
		for p, i in s.pieces {
			c := piece_cell(g, p)
			k := game.assembly(g, c, fx.hash01(u32(i) * 31 + 7))
			if k < 0.1 || k > 0.85 || fx.randf(&s.rng) > dt * 1.2 {
				continue
			}
			fx.emit(&s.embers, {
				pos   = {f32(c.x) + fx.randf(&s.rng), f32(c.y) + fx.randf(&s.rng), f32(c.z) + 0.5 - 9 * (1 - k)},
				vel   = {fx.rand_range(&s.rng, -0.1, 0.1), fx.rand_range(&s.rng, -0.1, 0.1), fx.rand_range(&s.rng, 0.4, 0.9)},
				accel = {0, 0, 0.25},
				life  = 2.6,
				size  = 32 * fx.rand_range(&s.rng, 0.08, 0.2),
				color = {1.0, 0.8, 0.45, 0.85},
			})
		}
	}
	fx.update(&s.debris, dt)
	fx.update(&s.embers, dt)
	fx.update(&s.motes, dt)
	fx.update(&s.sparks, dt)
	fx.update(&s.dust, dt)
	fx.update(&s.wind, dt)
	// the Stygian sleep: a black cloud pouring out of the box, spreading over her
	if k := game.sleep_mist(g); k > 0 && fx.randf(&s.rng) < dt * 110 * k {
		box, _, _ := game.box_pose(g)
		a := fx.rand_range(&s.rng, 0, math.TAU)
		v := fx.rand_range(&s.rng, 0.08, 0.3)
		fx.emit(&s.mist, {
			pos   = box + {0, 0, 0.06},
			vel   = {math.cos(a) * v, math.sin(a) * v, fx.rand_range(&s.rng, 0.15, 0.4)},
			accel = {-math.cos(a) * v * 0.2, -math.sin(a) * v * 0.2, -0.12},
			life  = 3.2,
			size  = 32 * fx.rand_range(&s.rng, 0.6, 1.1),
			color = {0.02, 0.01, 0.04, 0.8},
		})
	}
	fx.update(&s.mist, dt)
}

// The exit's floor, in the frame of its world.
@(private)
exit_point :: proc(g: ^game.Game) -> Vec3 {
	c := g.data.exit
	return {f32(c.x) + 0.5, f32(c.y) + 0.5, f32(c.z)}
}

// The exit shows once Zephyr is there: in the prologue, only when Psyche is
// left alone; never where Charon's boat is the way on.
@(private)
exit_alpha :: proc(g: ^game.Game) -> f32 {
	if g.data.has_boat {
		return 0
	}
	if k := game.assembly(g, g.data.exit, 1); k < 1 {
		return k * k // with its stone, as the diorama rises or breaks up
	}
	if g.boxed {
		return 1 - fx.progress(g.phase_t, 0, 1) // the light goes out as she opens the box
	}
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
	p.z -= 9 * (1 - game.assembly(g, g.data.amore, 1))
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
	lk := look_of(g)
	draw_sky(r, s, g, v, time)
	draw_bolt(g, v)
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
	draw_floors(g, time)
	draw_pieces(r, s, g, true)
	draw_decals(g)
	draw_glows(r, s, g, v)
	draw_trace(s, g, v)
	draw_mist(r, s, v)
	end_3d()

	draw_clouds(r, s, g, v, time, true)
	draw_motes(r, s, v)
	draw_markers(g, v)
	draw_teach(g, v, time)
	if f := game.lightning_flash(g); f > 0.003 {
		// the flash over everything, warm under the red sky
		rl.BeginBlendMode(.ADDITIVE)
		rl.DrawRectangleV({0, 0}, {v.width, v.height}, to_color({1.0, 0.86, 0.8, 0.42 * f}))
		rl.EndBlendMode()
	}
}

// A bolt of lightning in the sky behind the level while it flashes
// (game.lightning): a jagged stroke from the top of the sky toward the
// horizon, a branch or two, drawn in light.
@(private)
draw_bolt :: proc(g: ^game.Game, v: View) {
	f := game.lightning_flash(g)
	if f <= 0.003 {
		return
	}
	SEGMENTS :: 9
	seed := u32(g.level_index) * 131 + 7
	// to one side of the sky, clear of the level in the middle
	x0 := v.width * (0.1 + 0.1 * fx.hash01(seed))
	if fx.hash01(seed + 5) > 0.5 {
		x0 = v.width - x0
	}
	pts: [SEGMENTS + 1]Vec2
	pts[0] = {x0, -10}
	for k in 1 ..= SEGMENTS {
		h := u32(k) * 17 + seed
		pts[k] = pts[k - 1] + {(fx.hash01(h) - 0.45) * v.width * 0.05, v.height * 0.055 * (0.7 + 0.6 * fx.hash01(h + 3))}
	}
	widths := [3]f32{14, 6, 2}
	alphas := [3]f32{0.12, 0.3, 0.9}
	rl.BeginBlendMode(.ADDITIVE)
	for layer in 0 ..< 3 {
		w := widths[layer] * v.height / 1080
		a := alphas[layer] * f
		col := to_color(layer == 2 ? Color4{1.0, 0.96, 0.92, a} : Color4{1.0, 0.7, 0.6, a})
		for k in 0 ..< SEGMENTS {
			rl.DrawLineEx(pts[k], pts[k + 1], w, col)
		}
		// a branch from the middle
		b := pts[4]
		for k in 0 ..< 3 {
			h := u32(k) * 29 + seed + 101
			e := b + {v.width * 0.03 * (1 + fx.hash01(h)), v.height * 0.05}
			rl.DrawLineEx(b, e, w * 0.7, col)
			b = e
		}
	}
	rl.EndBlendMode()
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
		c := piece_cell(g, p)
		d := linalg_dot(Vec3{f32(c.x) + 0.5, f32(c.y) + 0.5, f32(c.z)}, axis)
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
	lk := look_of(g)
	set_v3(r, .Mist_Color, lk.mist)
	set_f(r, .Daylight, lk.daylight)
	set_f(r, .Sun_Truth, game.has_time(g) ? 1 - g.evening : 0)
	set_v3(r, .Rock_Tint, lk.rock == {} ? {1, 1, 1} : lk.rock)
	set_f(r, .Moonlight, (1 - lk.gloom) * (1 - 0.45 * s.moon_cover))
	all := make([dynamic]Flame, 0, len(g.data.props) + len(g.data.candelabra), context.temp_allocator)
	append(&all, ..candle_lights(g))
	append(&all, ..fire_lights(g))
	// the candelabra burning light far more of the palace than a candle
	for _, i in g.data.candelabra {
		k := game.assembly(g, g.data.candelabra[i].cell, 1)
		f := game.candelabrum_flame(g, i) * k * k
		if f <= 0.003 {
			continue
		}
		p := shown(g, candelabrum_world(g, i) + {0, 0, 1.0}, g.data.candelabra[i].under)
		fl := 0.9 + 0.07 * math.sin(g.time * 11 + f32(i) * 2.3) + 0.03 * math.sin(g.time * 29 + f32(i))
		append(&all, Flame{p, 1.15 * f * fl, 1.2 + 1.6 * f})
	}
	// the stones take the flames nearest Psyche (heights weigh more: the
	// camera frames one band of a tall level)
	if len(all) > MAX_CANDLES {
		her := g.psyche.pos
		far :: proc(a: Flame, her: Vec3) -> f32 {
			d := a.pos - her
			return d.x * d.x + d.y * d.y + 4 * d.z * d.z
		}
		context.user_ptr = &her
		slice.sort_by(all[:], proc(a, b: Flame) -> bool {
			her := (^Vec3)(context.user_ptr)^
			return far(a, her) < far(b, her)
		})
	}
	list: [MAX_CANDLES][4]f32
	reach: [MAX_CANDLES]f32
	n := min(len(all), MAX_CANDLES)
	for f, k in all[:n] {
		list[k] = {f.pos.x, f.pos.y, f.pos.z, f.strength}
		reach[k] = f.reach
	}
	rl.SetShaderValueV(r.material.shader, r.loc[.Candles], &list, .VEC4, i32(max(n, 1)))
	rl.SetShaderValueV(r.material.shader, r.loc[.Candle_Reach], &reach, .FLOAT, i32(max(n, 1)))
	count := i32(n)
	rl.SetShaderValue(r.material.shader, r.loc[.Candle_Count], &count, .INT)
}

MAX_CANDLES :: level.MAX_LIGHTS // as in palace.fs

// Where candelabrum i's foot is drawn now (it rises with the palace on arrival).
candelabrum_world :: proc(g: ^game.Game, i: int) -> Vec3 {
	p := game.candelabrum_base(g, i)
	p.z -= 9 * (1 - game.assembly(g, g.data.candelabra[i].cell, 1))
	return p
}

// The candles lit on the walls (where the setting lights them): their flames
// in the world and how bright each burns now (flickering; during the arrival,
// once its wall has risen into place).
candle_lights :: proc(g: ^game.Game) -> []Flame {
	if !look_of(g).candles {
		return nil
	}
	list := make([dynamic]Flame, 0, len(g.data.props), context.temp_allocator)
	t := g.time
	for prop, i in g.data.props {
		if level.PROPS[prop.kind].flame != .Candle || prop.part > 0 {
			continue
		}
		fp, a := prop_flame(g, prop, candle_flame(prop.dir))
		fl := 0.85 + 0.1 * math.sin(t * 13 + f32(i) * 1.7) + 0.05 * math.sin(t * 31 + f32(i))
		append(&list, Flame{fp, fl * a, 1.7})
	}
	return list[:]
}

FIRE_STRENGTH :: 1.4 // a fire lights the stones more than a candle...
FIRE_REACH :: 2.8 // ...and further

// The fires (`prop fire`), burning in any setting: their flames, flickering.
fire_lights :: proc(g: ^game.Game) -> []Flame {
	list := make([dynamic]Flame, 0, 8, context.temp_allocator)
	t := g.time
	for prop, i in g.data.props {
		if level.PROPS[prop.kind].flame != .Fire || prop.part > 0 {
			continue
		}
		fp, a := prop_flame(g, prop, FIRE_FLAME)
		fl := 0.8 + 0.12 * math.sin(t * 9 + f32(i) * 2.1) + 0.08 * math.sin(t * 23 + f32(i) * 0.7)
		append(&list, Flame{fp, FIRE_STRENGTH * fl * a, FIRE_REACH})
	}
	return list[:]
}

// Where the flame of a prop burns now (`at`: in its cell), shown as its world
// is, and how much of it is seen: on arrival it comes up with its stone.
@(private)
prop_flame :: proc(g: ^game.Game, prop: level.Prop, at: Vec3) -> (pos: Vec3, seen: f32) {
	pos = Vec3{f32(prop.cell.x), f32(prop.cell.y), f32(prop.cell.z)} + at
	k := game.assembly(g, prop.cell, 1)
	pos.z -= 9 * (1 - k)
	seen = k * k
	return shown(g, pos, prop.under), seen
}

// A flame that lights the stones: where, how strong, how far it reaches.
Flame :: struct {
	pos:      Vec3,
	strength: f32,
	reach:    f32,
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
	set_f(r, .Turned, 0)
}

// Where a point given in cell space of block entry i is in the world now
// (parts turn about their pivot, animated while a handle turns them).
block_world :: proc(g: ^game.Game, i: int, local: Vec3) -> Vec3 {
	e := g.data.blocks[i]
	return shown(g, part_point(g, e.part, Vec3{f32(e.cell.x), f32(e.cell.y), f32(e.cell.z)} + local), e.under)
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
	return turn_matrix(g, p.under) * m
}

// The cell a piece stands in now.
@(private)
piece_cell :: proc(g: ^game.Game, p: Piece) -> Cell {
	if p.block >= 0 {
		return pl.block_cell(&g.palace, int(p.block))
	}
	c := p.cell
	if p.part > 0 {
		c = level.part_cell(c, g.data.parts[p.part - 1].pivot, g.palace.part_rot[p.part - 1])
	}
	return level.frame_cell(&g.data, c, p.under, g.palace.upside)
}

// Lift, opacity and visibility of piece i in this frame; `ghost`: drawn with
// the see-through pieces (veiled blocks shown by the lamp).
@(private)
piece_state :: proc(g: ^game.Game, p: Piece, i: int) -> (lift, alpha: f32, visible, ghost, hidden: bool) {
	alpha = 1
	visible = true
	hidden = p.sigil == .Off
	switch p.sigil {
	case .None:
	case .Off:
		visible = int(p.seal) not_in g.activated
	case .On:
		visible = int(p.seal) in g.activated
	}
	if p.rise_index >= 0 {
		rt := game.rise_time(g, int(p.rise_index))
		if rt < 0 {
			return 0, 0, false, false, false
		}
		lift = rise_lift(g, int(p.rise_index))
		alpha = fx.progress(rt, game.rise_start(g, int(p.rise_index)), 0.8)
	}
	if p.block >= 0 {
		t := g.flip_t[p.block]
		switch g.data.blocks[p.block].trait {
		case .Stone:
		case .Veiled:
			if t < 0 {
				ghost, hidden = true, true
			} else {
				alpha = fx.progress(t, 0, game.DISSOLVE_TIME)
				lift -= 0.3 * (1 - fx.cubic_out(fx.clamp01(t / game.DISSOLVE_TIME)))
			}
		case .Sunlit:
			// at evening it crumbles: each stone sinks and fades a little after
			// the one above it; by day it rises back
			k := sunlit_fall(g, p)
			lift -= 1.4 * fx.quad_in(k)
			alpha *= 1 - k * k * k
		}
	}
	if k := game.assembly(g, piece_cell(g, p), fx.hash01(u32(i) * 31 + 7)); k < 1 {
		// the palace rises into place on arrival, or breaks up for the level's next diorama
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

// How far a stone standing only by day has crumbled (0 by day .. 1 at evening),
// the higher ones first.
@(private)
sunlit_fall :: proc(g: ^game.Game, p: Piece) -> f32 {
	delay := 0.25 * fx.hash01(u32(p.cell.x * 73 + p.cell.y * 31)) + 0.08 * f32(p.cell.z % 4)
	return fx.clamp01((g.evening - delay) / 0.55)
}

// Accessibility: the pieces that stand between the camera and Psyche fade to
// a faint ghost (and back when she has passed), so she is never lost behind
// a wall. A piece hides her when its cube, seen from the camera, covers a
// point of her figure and is nearer; her own column (the floor, the stair
// under her) never fades.
@(private)
update_see_through :: proc(s: ^Scene, g: ^game.Game, dt: f32) {
	if len(s.see) != len(s.pieces) {
		return
	}
	psy := g.psyche
	// while the world turns over its pieces are not where their cells say: none fades
	on := s.see_through && g.phase != .Prologue && g.phase != .Overturn
	k := fx.clamp01(dt * 7)
	for p, i in s.pieces {
		target: f32 = 0
		c := piece_cell(g, p)
		mine := (c.x == psy.cell.x && c.y == psy.cell.y) || (psy.walking && c.x == psy.step_to.x && c.y == psy.step_to.y)
		// the floors at her feet and under them never hide her (only her
		// soles): faded, they would let the stones behind show through
		feet := psy.walking ? min(psy.cell.z, psy.step_to.z) : psy.cell.z
		if on && !mine && c.z >= feet {
			center := iso.view_point({f32(c.x) + 0.5, f32(c.y) + 0.5, f32(c.z) + 0.5}, g.angle, g.data.size)
			sc := iso.project(center)
			// her figure: three heights, each with her width on either side (proto px)
			test: for h in ([3]f32{0.1, 0.32, 0.55}) {
				q := iso.view_point(psy.pos + {0, 0, h}, g.angle, g.data.size)
				if iso.depth(center) < iso.depth(q) + 0.3 {
					continue // behind her
				}
				for side in ([3]f32{-10, 0, 10}) {
					d := iso.project(q) + {side, 0} - sc
					if abs(d.x) <= 64 && abs(d.y) <= 64 - abs(d.x) * 0.5 {
						target = 1
						break test
					}
				}
			}
		}
		s.see[i] += (target - s.see[i]) * k
	}
}

// What is left of a piece faded by the see-through: a faint ghost.
@(private)
see_alpha :: proc(s: ^Scene, i: int) -> f32 {
	if i >= len(s.see) {
		return 1
	}
	return 1 - 0.82 * s.see[i]
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
		alpha *= see_alpha(s, i)
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
		alpha *= see_alpha(s, i)
		material := p.material
		detail: f32 = 0
		if p.cube {
			// the face seen on top (the world turning over shows its undersides
			// from half way: then up is down in the frame of the world up now)
			up: i32 = (g.overturn > 0.5) == g.palace.upside ? 1 : -1
			covered := pl.solid_at(&g.palace, piece_cell(g, p) + {0, 0, up}).kind != .None
			material = covered ? .Masonry : .Marble
			detail = covered ? 2 : 1
			ground, lawn := p.ground, p.lawn
			if g.data.duality && level.world_cell(&g.data, p.cell, p.under).z == g.data.axle {
				// the floor of both worlds: rock to the dead, marble to her kingdom
				ground = g.overturn <= 0.5
				lawn &&= ground
			}
			if ground {
				material, detail = covered || !lawn ? .Rock : .Lawn, 0
			} else if lawn {
				material, detail = .Lawn, 0
			}
		}
		// a veiled stone shows as a faint golden ghost; the seal's panel glows full
		ghost_veil := hidden && p.block >= 0
		set_piece_uniforms(r, material, detail, hidden ? (ghost_veil ? 2 : 1) : 0, alpha, 0.25, 0)
		// hanging upside down (more than half turned): its courses and bevels turned with it
		if (p.under != (g.overturn > 0.5)) && len(g.data.pomegranates) > 0 {
			set_f(r, .Turned, 1)
		}
		m := piece_matrix(g, p, lift)
		if p.sundial {
			// the sundial's crank: the handle's, in the Sun's gold and larger
			m = m * rl.MatrixTranslate(CRANK_AXIS.x, CRANK_AXIS.y, 0) * rl.MatrixScale(SUNDIAL_SCALE, SUNDIAL_SCALE, SUNDIAL_SCALE) * rl.MatrixTranslate(-CRANK_AXIS.x, -CRANK_AXIS.y, 0)
		}
		rl.DrawMesh(r.meshes[p.mesh], r.material, m)
		if p.handle >= 0 || p.sundial {
			// the wheel turns while the handle works its part (or the sundial the time)
			spin := p.sundial ? g.evening * 2 * math.PI : game.part_angle(g, g.data.handles[p.handle].part) * math.PI
			ax := CRANK_AXIS
			size: f32 = p.sundial ? SUNDIAL_SCALE : 1
			wm := turn_matrix(g, p.under) * rl.MatrixTranslate(f32(p.cell.x) + ax.x, f32(p.cell.y) + ax.y, f32(p.cell.z) + ax.z * size) * rl.MatrixRotateZ(spin) * rl.MatrixScale(size, size, size)
			rl.DrawMesh(r.meshes[.Crank_Wheel], r.material, wm)
		}
	}
}

// How much the dark around Psyche asks for her own light: the night
// settings fully, the lit ones little, less while she holds the lamp lit.
@(private)
psyche_dark :: proc(g: ^game.Game) -> f32 {
	lk := look_of(g)
	return (1 - lk.daylight) * (0.75 + 0.25 * lk.gloom) * (1 - 0.6 * g.light)
}

@(private)
draw_figures :: proc(r: ^Renderer, g: ^game.Game) {
	psy := g.psyche
	bob: f32 = psy.walking ? math.abs(math.sin(psy.walk_anim * 11)) * 0.02 : 0
	// the Stygian sleep lays her down on the path, forward over the box
	fall := game.sleep_fall(g)
	base := psy.pos + {0, 0, bob + 0.1 * fall}
	rot := rl.MatrixRotateZ(psy.yaw) * rl.MatrixRotateY(1.42 * fall)
	body := rl.MatrixTranslate(base.x, base.y, base.z) * rot
	set_piece_uniforms(r, .Psyche, 0, 0, game.psyche_alpha(g), 0.9, 0.04 + 0.07 * psyche_dark(g))
	rl.DrawMesh(r.meshes[.Robe], r.material, body)
	rl.DrawMesh(r.meshes[.Head], r.material, body * rl.MatrixTranslate(0, 0, 0.548) * rl.MatrixScale(0.046, 0.046, 0.05))
	if g.data.has_lamp && g.phase != .Prologue && fall < 0.3 {
		lamp := game.lamp_world(g)
		set_piece_uniforms(r, .Bronze, 0, 0, game.psyche_alpha(g) * (1 - fall / 0.3), 0.9, 0)
		rl.DrawMesh(r.meshes[.Lamp], r.material, rl.MatrixTranslate(lamp.x, lamp.y, lamp.z - 0.05))
	}
	// Proserpina's box in her hands, its lid lifting
	if box, lid, alpha := game.box_pose(g); alpha > 0.003 {
		turn := rl.MatrixTranslate(box.x, box.y, box.z) * rl.MatrixRotateZ(psy.yaw)
		set_piece_uniforms(r, .Bronze, 0, 0, alpha, 0.9, 0.05)
		rl.DrawMesh(r.meshes[.Block], r.material, turn * rl.MatrixScale(0.13, 0.1, 0.08) * rl.MatrixTranslate(-0.5, -0.5, 0))
		// the lid hinged on the far side, swinging up toward her
		rl.DrawMesh(r.meshes[.Block], r.material, turn * rl.MatrixTranslate(0.065, 0, 0.08) * rl.MatrixRotateY(-1.9 * lid) * rl.MatrixScale(0.14, 0.11, 0.018) * rl.MatrixTranslate(-1, -0.5, 0))
	}

	draw_fragments(r, g)
	draw_rams(r, g)
	draw_eagles(r, g)
	draw_boats(r, g)

	// the prologue's procession: veiled mourners, a little taller than Psyche
	if game.procession(g) {
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

	// Venus among her doves (the opening of Act III)
	if v, alpha := game.venus_figure(g); alpha > 0.003 {
		set_piece_uniforms(r, .Venus, 0, 0, alpha, 0.9, 0.1)
		face := rl.MatrixRotateZ(math.atan2(g.psyche.pos.y - v.y, g.psyche.pos.x - v.x))
		rl.DrawMesh(r.meshes[.Robe], r.material, rl.MatrixTranslate(v.x, v.y, v.z) * face * rl.MatrixScale(1.15, 1.15, 1.18))
		rl.DrawMesh(r.meshes[.Head], r.material, rl.MatrixTranslate(v.x, v.y, v.z + 0.645) * rl.MatrixScale(0.052, 0.052, 0.058))
		for i in 0 ..< game.VE_DOVES {
			p, d, a := game.venus_dove(g, i)
			set_piece_uniforms(r, .Psyche, 0, 0, a, 0.9, 0.06)
			yaw := math.atan2(d.y, d.x)
			rl.DrawMesh(r.meshes[.Head], r.material, rl.MatrixTranslate(p.x, p.y, p.z) * rl.MatrixRotateZ(yaw) * rl.MatrixScale(0.05, 0.026, 0.026))
		}
	}
}

// The Sun's golden rams, carved like the palace (shapes.odin): a quilted block
// of golden fleece for the body (the neck and the tail smaller ones), the face
// and the legs in dark bronze, horns curling in gold; in the frame of the
// cell turned toward `dir`. Standing by day (as tall as Psyche's head, the
// head dipping now and then to graze); lying at evening, the legs folded, a
// broad flat block of fleece, the head laid forward against the next ledge:
// the step she climbs.
@(private)
draw_rams :: proc(r: ^Renderer, g: ^game.Game) {
	if len(g.data.rams) == 0 {
		return
	}
	lie := game.ram_lie(g)
	set_piece_uniforms(r, .Fleece, 0, 0, 1, 0.9, 0.05 + 0.04 * (1 - lie))
	// the golden wool left on the briars at the exit's height: tufts on the bushes
	if g.data.has_exit {
		for prop, n in g.data.props {
			if prop.kind != .Shrub || prop.cell.z != g.data.exit.z {
				continue
			}
			k := [2]f32{0.8, 0.8}
			#partial switch prop.dir {
			case .PY: k = {1 - k.y, k.x}
			case .MX: k = {1 - k.x, 1 - k.y}
			case .MY: k = {k.y, 1 - k.x}
			}
			for j in 0 ..< 3 {
				h := u32(n * 7 + j)
				p := Vec3{f32(prop.cell.x) + k.x + (fx.hash01(h * 3 + 1) - 0.5) * 0.22, f32(prop.cell.y) + k.y + (fx.hash01(h * 3 + 2) - 0.5) * 0.22, f32(prop.cell.z) + 0.12 + 0.12 * fx.hash01(h * 3 + 3)}
				rl.DrawMesh(r.meshes[.Head], r.material, rl.MatrixTranslate(p.x, p.y, p.z) * rl.MatrixScale(0.045, 0.04, 0.035))
			}
		}
	}
	Ram_Pose :: struct {
		frame: rl.Matrix, // the cell, turned toward dir
		body, neck, tail, head: rl.Matrix,
		leg_h, leg_z: f32,
	}
	poses := make([]Ram_Pose, len(g.data.rams), context.temp_allocator)
	mix :: proc(a, b: Vec3, t: f32) -> Vec3 {return a + (b - a) * t}
	place :: proc(at, size: Vec3) -> rl.Matrix {return rl.MatrixTranslate(at.x, at.y, at.z) * rl.MatrixScale(size.x, size.y, size.z)}
	for m, i in g.data.rams {
		c := m.cell
		d := iso.DIR_VEC[m.dir]
		yaw := math.atan2(f32(d.y), f32(d.x))
		pose := &poses[i]
		pose.frame = rl.MatrixTranslate(f32(c.x) + 0.5, f32(c.y) + 0.5, f32(c.z)) * rl.MatrixRotateZ(yaw)
		// grazing (by day): now and then the head goes down to the grass
		ph := g.time * 0.35 + f32(i) * 1.7
		graze := (1 - lie) * fx.sine_in_out(fx.clamp01((math.sin(ph) - 0.55) / 0.3))
		breath := 1 + 0.02 * math.sin(g.time * 1.3 + f32(i))
		// the legs fold under the fleece as it settles on the stone
		pose.leg_h = 0.24 * (1 - lie)
		body_at := mix({-0.05, 0, 0.47}, {-0.04, 0, 0.21}, lie)
		body_size := mix({0.68, 0.5, 0.46}, {0.86, 0.66, 0.44}, lie) * Vec3{1, 1, breath}
		pose.body = place(body_at, body_size)
		head_at := mix(Vec3{0.27, 0, 0.68} + Vec3{0.06, 0, -0.42} * graze, {0.33, 0, 0.42}, lie)
		pitch := 0.35 + 0.9 * graze - 0.15 * lie
		pose.head = rl.MatrixTranslate(head_at.x, head_at.y, head_at.z) * rl.MatrixRotateY(pitch) * rl.MatrixScale(1.3, 1.3, 1.3)
		neck_at := mix(body_at + {0.26, 0, 0.1}, head_at, 0.35)
		pose.neck = place(neck_at, {0.2, 0.2, 0.24})
		pose.tail = place(body_at + mix({-0.36, 0, 0.04}, {-0.45, 0, -0.06}, lie), {0.1, 0.1, 0.12})
	}
	// the wool and the horns in gold...
	for pose in poses {
		for part in ([3]rl.Matrix{pose.body, pose.neck, pose.tail}) {
			rl.DrawMesh(r.meshes[.Ram_Fleece], r.material, pose.frame * part)
		}
		rl.DrawMesh(r.meshes[.Ram_Horns], r.material, pose.frame * pose.head)
	}
	// ...the face and the legs in dark bronze
	set_piece_uniforms(r, .Bronze, 0, 0, 1, 0.9, 0)
	for pose in poses {
		rl.DrawMesh(r.meshes[.Ram_Head], r.material, pose.frame * pose.head)
		if pose.leg_h > 0.01 {
			for lx in ([2]f32{-0.24, 0.16}) {
				for ly in ([2]f32{-0.13, 0.13}) {
					rl.DrawMesh(r.meshes[.Ram_Leg], r.material, pose.frame * rl.MatrixTranslate(lx, ly, 0) * rl.MatrixScale(1.3, 1.3, pose.leg_h + 0.06))
				}
			}
		}
	}
}

// Jupiter's eagles, in gold: folded on their perches, spread while they
// carry her and fly home (game.eagle_pose).
@(private)
draw_eagles :: proc(r: ^Renderer, g: ^game.Game) {
	if len(g.data.eagles) == 0 {
		return
	}
	Eagle_Pose :: struct {
		body, head: rl.Matrix,
		wings:      [2]rl.Matrix,
		spread:     f32,
	}
	poses := make([]Eagle_Pose, len(g.data.eagles), context.temp_allocator)
	for &pose, i in poses {
		pos, yaw, spread := game.eagle_pose(g, i)
		breath := math.sin(g.time * 1.3 + f32(i) * 2.1)
		// perched it sits upright, its breast out; flying it lies level
		pitch := -1.05 * (1 - spread) - 0.08
		pose.spread = spread
		pose.body = rl.MatrixTranslate(pos.x, pos.y, pos.z) * rl.MatrixRotateZ(yaw) * rl.MatrixRotateY(pitch) * rl.MatrixTranslate(-0.16, 0, 0.1)
		pose.head = pose.body * rl.MatrixTranslate(0.37, 0, 0.05 + 0.005 * breath) * rl.MatrixRotateY(-pitch * 0.8)
		// wings: folded back along the body, or open and beating slowly
		beat := spread * (0.15 + 0.55 * math.sin(g.time * 5.2 + f32(i)))
		sweep := (1 - spread) * (math.PI * 0.5 - 0.12)
		droop := (1 - spread) * 0.25
		for side, k in ([2]f32{-1, 1}) {
			pose.wings[k] = pose.body * rl.MatrixTranslate(0.24, side * 0.07, 0.06) * rl.MatrixRotateX(side * (beat - droop)) * rl.MatrixRotateZ(side * sweep) * rl.MatrixScale(1, side * (0.5 + 0.5 * spread), 1)
		}
	}
	// the feathers in gold...
	set_piece_uniforms(r, .Fleece, 0, 0, 1, 0.9, 0.12)
	for pose in poses {
		rl.DrawMesh(r.meshes[.Eagle_Body], r.material, pose.body)
		rl.DrawMesh(r.meshes[.Eagle_Tail], r.material, pose.body * rl.MatrixRotateY(-0.15 * pose.spread))
		rl.DrawMesh(r.meshes[.Head], r.material, pose.head * rl.MatrixScale(0.06, 0.055, 0.058))
		for w in pose.wings {
			rl.DrawMesh(r.meshes[.Eagle_Wing], r.material, w)
		}
	}
	// ...the beak in dark bronze
	set_piece_uniforms(r, .Bronze, 0, 0, 1, 0.9, 0)
	for pose in poses {
		rl.DrawMesh(r.meshes[.Eagle_Beak], r.material, pose.head * rl.MatrixTranslate(0.045, 0, -0.005))
	}
}

// Charon's boats, in pale wood: at the exit and on the ferries (game.charons);
// Charon standing at the far end in his dark cloak, a pole in his hands:
// waiting, facing the landing; poling the boat across, or away into the mist.
@(private)
draw_boats :: proc(r: ^Renderer, g: ^game.Game) {
	for c in game.charons(g) {
		if c.alpha < 0.003 {
			continue
		}
		m := turn_matrix(g, false) // of the world above, in a level with pomegranates
		yaw := c.boat.yaw
		d := Vec3{math.cos(yaw), math.sin(yaw), 0}
		stern := game.boat_at(c.boat, game.BOAT_STERN)
		set_piece_uniforms(r, .Pale_Wood, 0, 0, c.alpha, 0.9, 0)
		rl.DrawMesh(r.meshes[.Boat], r.material, m * rl.MatrixTranslate(stern.x, stern.y, stern.z) * rl.MatrixRotateZ(yaw))
		// the pole: from the water beside him up past his shoulder, leaning
		// back as he thrusts
		side := Vec3{-d.y, d.x, 0}
		lean := 0.18 + 0.42 * c.pole
		up := Vec3{-d.x * math.sin(lean), -d.y * math.sin(lean), math.cos(lean)}
		foot := c.pos + side * 0.17 - up * 0.55 + {0, 0, 0.3}
		axis := Vec3{-up.y, up.x, 0}
		rl.DrawMesh(r.meshes[.Block], r.material, m * rl.MatrixTranslate(foot.x, foot.y, foot.z) * rl.MatrixRotate(axis, lean) * rl.MatrixScale(0.035, 0.035, 1.75) * rl.MatrixTranslate(-0.5, -0.5, 0))
		// Charon, a head taller than the mourners, his hood bowed
		set_piece_uniforms(r, .Mourner, 0, 0, c.alpha, 0.9, 0)
		rl.DrawMesh(r.meshes[.Robe], r.material, m * rl.MatrixTranslate(c.pos.x, c.pos.y, c.pos.z) * rl.MatrixRotateZ(c.face) * rl.MatrixScale(1.12, 1.12, 1.24))
		rl.DrawMesh(r.meshes[.Head], r.material, m * rl.MatrixTranslate(c.pos.x, c.pos.y, c.pos.z + 0.66) * rl.MatrixRotateZ(c.face) * rl.MatrixTranslate(0.012, 0, 0) * rl.MatrixScale(0.056, 0.054, 0.062))
	}
}

// How visible fragment i's scroll is: faint when collected in an earlier
// play, rising and fading when picked up now.
@(private)
fragment_alpha :: proc(g: ^game.Game, i: int) -> (alpha, lift: f32) {
	if g.phase == .Prologue {
		return 0, 0
	}
	if k := game.assembly(g, g.data.fragments[i], 1); k < 1 {
		// with its stone, as the diorama rises or breaks up
		a, l := fragment_alpha_placed(g, i)
		return a * k * k, l - 9 * (1 - k)
	}
	return fragment_alpha_placed(g, i)
}

@(private)
fragment_alpha_placed :: proc(g: ^game.Game, i: int) -> (alpha, lift: f32) {
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
		p := shown(g, game.fragment_world(g, i) + {0, 0, lift}, i in g.data.fragments_under)
		set_piece_uniforms(r, .Psyche, 0, 0, alpha, 0.9, i in g.fragments_known ? 0 : 0.1)
		// laid on its side, turning slowly
		m := rl.MatrixTranslate(p.x, p.y, p.z) * rl.MatrixRotateZ(g.time * 0.5 + f32(i)) * rl.MatrixRotateX(math.PI / 2) * rl.MatrixTranslate(0, 0, -0.14)
		rl.DrawMesh(r.meshes[.Scroll], r.material, m)
	}
}

@(private)
cupid_fade :: proc(g: ^game.Game) -> f32 {
	k := game.assembly(g, g.data.amore, 1) // he comes with his bed as the diorama rises
	if g.amore.fly_t < 0 {
		return k * k
	}
	return 1 - fx.progress(g.amore.fly_t, 0.6, 2.2)
}

// How far below its place the i-th stone raised by the seal is now (<= 0);
// the way a guard candelabrum shows does not rise: it appears in its light.
rise_lift :: proc(g: ^game.Game, i: int) -> f32 {
	rt := game.rise_time(g, i)
	if rt < 0 {
		return -game.RISE_DEPTH
	}
	if int(g.data.rise[i].seal) in g.data.guard_seals {
		return 0
	}
	return -game.RISE_DEPTH * (1 - fx.cubic_out(fx.progress(rt, game.rise_start(g, i), game.RISE_TIME)))
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
	ellipse_3d(center, {1, 0, 0}, {0, 1, 0}, rx, ry, 0, c, 16)
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

WATER_DEPTH :: 0.28 // the water's surface: this far under the platforms it lies by (level floor_h)

// What the diorama stands on (`floor` lines; a basin's marble is built as
// pieces): the water, a dark surface (fading out at the edges of a river's
// rectangle, brimming to a basin's rim), glints of moonlight drifting with the
// current (along x), the lamp's warmth near Psyche, and a ring of foam around
// every stone standing in it.
@(private)
draw_floors :: proc(g: ^game.Game, time: f32) {
	if len(g.data.floors) == 0 {
		return
	}
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	lamp := game.lamp_world(g)
	warm := g.data.has_lamp ? g.light : 0
	lk := look_of(g)
	surface := lk.water.a > 0 ? lk.water : Color4{0.08, 0.12, 0.27, 0.8}
	glint := lk.glint.a > 0 ? lk.glint : Color4{0.65, 0.75, 1.0, 0.4}
	present := game.floors_shown(g)
	glint.a *= present
	z := f32(g.data.floor_h) - WATER_DEPTH
	begin_turn(g, false) // of the world above, in a level with pomegranates
	for f in g.data.floors {
		w := f.area
		surface := surface
		if f.fluid == .Swamp {
			// the swamp's green-brown, as bright as the setting's water
			lum := 0.299 * surface.r + 0.587 * surface.g + 0.114 * surface.b
			surface = {SWAMP.r * lum, SWAMP.g * lum, SWAMP.b * lum, SWAMP.a}
		}
		surface.a *= present
		x0, y0 := f32(w[0]), f32(w[1])
		x1, y1 := f32(w[2] + 1), f32(w[3] + 1)
		// a river fades into the mist over its last 1.2 cells, a basin holds it to the rim
		fade: f32 = f.kind == .Water ? 1.2 : 0
		point :: proc(x, y, z, x0, y0, x1, y1, fade: f32, lamp: Vec3, warm: f32, surface: Color4) {
			a := water_edge(x, x0, x1, fade) * water_edge(y, y0, y1, fade)
			a = a * a * (3 - 2 * a)
			d := Vec2{x - lamp.x, y - lamp.y}
			lit := warm * fx.clamp01(1 - math.sqrt(d.x * d.x + d.y * d.y) / 3)
			c := fx.lerp(surface, Color4{0.4, 0.25, 0.1, 0.85}, lit)
			c.a *= a
			color(c)
			vtx({x, y, z})
		}
		STEP :: 0.5
		rlgl.Begin(rlgl.TRIANGLES)
		for y := y0; y < y1 - 0.001; y += STEP {
			for x := x0; x < x1 - 0.001; x += STEP {
				point(x, y, z, x0, y0, x1, y1, fade, lamp, warm, surface)
				point(x + STEP, y, z, x0, y0, x1, y1, fade, lamp, warm, surface)
				point(x + STEP, y + STEP, z, x0, y0, x1, y1, fade, lamp, warm, surface)
				point(x, y, z, x0, y0, x1, y1, fade, lamp, warm, surface)
				point(x + STEP, y + STEP, z, x0, y0, x1, y1, fade, lamp, warm, surface)
				point(x, y + STEP, z, x0, y0, x1, y1, fade, lamp, warm, surface)
			}
		}
		rlgl.End()
		if f.fluid == .Swamp {
			draw_swamp(f, z, time, surface, glint)
		} else if !g.reduce_motion {
			draw_fish(g, f, z, time, surface, glint, fade)
		}
		// glints of moonlight drifting with the current (a swamp has none)
		for cy in w[1] ..= w[3] {
			if f.fluid == .Swamp {
				break
			}
			for cx in w[0] ..= w[2] {
				for k in 0 ..< 3 {
					h := u32(cx * 73 + cy * 151 + i32(k) * 31)
					u := math.mod(time * (0.08 + 0.05 * fx.hash01(h)) + fx.hash01(h + 1), 1)
					px := f32(cx) + u
					py := f32(cy) + 0.15 + 0.7 * fx.hash01(h + 2)
					a := water_edge(px, x0, x1, fade) * water_edge(py, y0, y1, fade) * math.sin(u * math.PI)
					len := 0.12 + 0.18 * fx.hash01(h + 3)
					floor_strip({px, py, z + 0.003}, {px + len, py, z + 0.003}, {0, 1, 0}, 0.022, {glint.r, glint.g, glint.b, glint.a * a})
				}
			}
		}
		// foam where the stones stand in the river
		for e, i in g.data.blocks {
			c := e.cell
			if c.z != g.data.floor_h - 1 || e.under || c.x < w[0] || c.x > w[2] || c.y < w[1] || c.y > w[3] || !pl.block_present(&g.palace, i) {
				continue
			}
			t := math.mod(time * (f.fluid == .Swamp ? 0.12 : 0.35) + fx.hash01(u32(i) * 7), 1)
			foam := f.fluid == .Swamp ? Color4{0.55, 0.62, 0.35, 0.18} : Color4{0.7, 0.8, 1.0, 0.3}
			floor_ring({f32(c.x) + 0.5, f32(c.y) + 0.5, z + 0.002}, 0.68 + 0.12 * t, 0.025, {foam.r, foam.g, foam.b, foam.a * (1 - t) * game.assembly(g, c, 1)})
		}
	}
	end_turn()
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
}

// How far into a river's fade (`fade` cells at the edges of lo..hi) `v` lies: 0 at the edge, 1 inside.
@(private)
water_edge :: proc(v, lo, hi, fade: f32) -> f32 {
	return fade > 0 ? fx.clamp01(min(v - lo, hi - v) / fade) : 1
}

MAX_FISH :: 6

// Fish in the water of a place that has them (the biome's `fish`): dark shapes
// just under the surface, each about a home of open water at least a cell from
// the rim; it drifts, now and then darts off with a flick of its tail, and
// where it darts a ring spreads on the water. Under a stone it is hidden.
@(private)
draw_fish :: proc(g: ^game.Game, f: level.Floor, z: f32, time: f32, surface, glint: Color4, fade: f32) {
	weight := g.data.has_biome ? level.BIOMES[g.data.biome].fish : 0
	if weight == 0 {
		return
	}
	a := f.area
	w, h := int(a[2] - a[0] + 1), int(a[3] - a[1] + 1)
	if w < 3 || h < 3 {
		return
	}
	// open water: no stone standing over it
	open := make([]bool, w * h, context.temp_allocator)
	for &o in open {
		o = true
	}
	for e, i in g.data.blocks {
		c := e.cell
		if !e.under && c.x >= a[0] && c.x <= a[2] && c.y >= a[1] && c.y <= a[3] && pl.block_present(&g.palace, i) {
			open[int(c.y - a[1]) * w + int(c.x - a[0])] = false
		}
	}
	is_open :: proc(open: []bool, w, h, x, y: int) -> bool {
		return x >= 0 && y >= 0 && x < w && y < h && open[y * w + x]
	}
	// homes: open cells a cell in from the rim, the widest stretches of water
	// first (open cells in the 5×5 about them), three cells apart
	Home :: struct {
		at:    Vec2,
		score: f32,
	}
	cands: [dynamic]Home
	cands.allocator = context.temp_allocator
	for y in 1 ..< h - 1 {
		for x in 1 ..< w - 1 {
			if !is_open(open, w, h, x, y) {
				continue
			}
			around := 0
			for dy in -2 ..= 2 {
				for dx in -2 ..= 2 {
					around += is_open(open, w, h, x + dx, y + dy) ? 1 : 0
				}
			}
			if around >= 12 {
				at := Vec2{f32(int(a[0]) + x) + 0.5, f32(int(a[1]) + y) + 0.5}
				append(&cands, Home{at, f32(around) + fx.hash01(u32(x * 97 + y * 211) + u32(g.level_index))})
			}
		}
	}
	slice.sort_by(cands[:], proc(p, q: Home) -> bool {return p.score > q.score})
	count := min(int(weight) + len(cands) / 100, MAX_FISH)
	homes := make([dynamic]Vec2, 0, count, context.temp_allocator)
	for c in cands {
		if len(homes) == count {
			break
		}
		near := false
		for o in homes {
			near ||= abs(o.x - c.at.x) + abs(o.y - c.at.y) < 3
		}
		if !near {
			append(&homes, c.at)
		}
	}
	body := Color4{surface.r * 0.35, surface.g * 0.4, surface.b * 0.45, 0.6 * surface.a}
	x0, y0, x1, y1 := f32(a[0]), f32(a[1]), f32(a[2] + 1), f32(a[3] + 1)
	for home, k in homes {
		seed := u32(k) * 7919 + u32(g.level_index) * 131 + 17
		r := 0.45 + 0.3 * fx.hash01(seed + 1)
		tilt := math.TAU * fx.hash01(seed + 2)
		period := 7 + 5 * fx.hash01(seed + 3)
		size := 0.8 + 0.4 * fx.hash01(seed + 4)
		way: f32 = fx.hash01(seed + 5) < 0.5 ? 1 : -1
		// along a loop about its home: a slow drift, and once a period a dart
		phase :: proc(t, period, offset, way: f32) -> f32 {
			p := t / period + offset
			n := math.floor(p)
			dart := math.smoothstep(f32(0.62), 0.78, p - n)
			return way * (0.05 * t + math.TAU * 0.3 * (n + dart))
		}
		at :: proc(home: Vec2, r, tilt, s: f32) -> Vec2 {
			l := Vec2{math.cos(s) * r, math.sin(2 * s) * r * 0.5}
			ct, st := math.cos(tilt), math.sin(tilt)
			return home + {l.x * ct - l.y * st, l.x * st + l.y * ct}
		}
		offset := fx.hash01(seed + 6)
		s0 := phase(time, period, offset, way)
		s1 := phase(time + 0.05, period, offset, way)
		p := at(home, r, tilt, s0)
		ahead := at(home, r, tilt, s1) - p
		step := math.sqrt(ahead.x * ahead.x + ahead.y * ahead.y)
		if step < 1e-5 {
			continue
		}
		speed := step / 0.05
		d := ahead / step
		n := Vec2{-d.y, d.x}
		alpha := water_edge(p.x, x0, x1, fade) * water_edge(p.y, y0, y1, fade)
		c := body
		c.a *= alpha
		// the tail beats faster and wider as it darts
		beat := math.sin(time * (6 + 10 * min(speed, 1.5))) * (0.25 + 0.35 * min(speed, 1))
		dir := Vec3{d.x, d.y, 0}
		side := Vec3{n.x, n.y, 0}
		centre := Vec3{p.x, p.y, z + 0.0025}
		ellipse_3d(centre, dir, side, 0.15 * size, 0.05 * size, 0, c, 12)
		back := centre - dir * 0.12 * size
		tail := dir * math.cos(beat) + side * math.sin(beat)
		tail_side := Vec3{-tail.y, tail.x, 0}
		tip := back - tail * 0.12 * size
		rlgl.Begin(rlgl.TRIANGLES)
		color(c)
		vtx(back + tail * 0.02 * size)
		vtx(tip + tail_side * 0.065 * size)
		vtx(tip - tail_side * 0.065 * size)
		rlgl.End()
		// a ring where it darted off
		q := math.mod(time / period + offset, 1)
		if q > 0.62 && q < 0.95 {
			u := (q - 0.62) / 0.33
			start := at(home, r, tilt, phase((math.floor(time / period + offset) + 0.62 - offset) * period, period, offset, way))
			floor_ring({start.x, start.y, z + 0.003}, 0.05 + 0.25 * u, 0.012, {glint.r, glint.g, glint.b, glint.a * 0.7 * (1 - u) * alpha})
		}
	}
}

SWAMP :: Color4{0.46, 0.52, 0.30, 0.95} // a swamp's hue, times the brightness of the setting's water

// A swamp's still surface (`surface` its colour now): patches of algae and
// duckweed, the sky twinkling here and there on the still water, a bubble
// coming up now and then.
@(private)
draw_swamp :: proc(f: level.Floor, z: f32, time: f32, surface, glint: Color4) {
	s := surface
	algae := [2][3]f32{{0.75, 0.9, 0.6}, {1.25, 1.45, 0.8}} // darker mud, greener scum
	weed := Color4{s.r * 1.6, s.g * 2.0, s.b * 1.0, 0.75}
	a := f.area
	for cy in a[1] ..= a[3] {
		for cx in a[0] ..= a[2] {
			h := u32(cx * 97 + cy * 211)
			if fx.hash01(h + 11) < 0.4 {
				m := algae[fx.hash01(h + 12) < 0.5 ? 0 : 1]
				p := Vec3{f32(cx) + 0.5 + 0.3 * (fx.hash01(h + 13) - 0.5), f32(cy) + 0.5 + 0.3 * (fx.hash01(h + 14) - 0.5), z + 0.002}
				r := 0.35 + 0.3 * fx.hash01(h + 15)
				floor_ellipse(p, r, r * (0.7 + 0.3 * fx.hash01(h + 16)), {s.r * m.x, s.g * m.y, s.b * m.z, 0.55})
			}
			if fx.hash01(h) < 0.22 {
				for k in 0 ..< 4 {
					hk := h + u32(k) * 13
					p := Vec3{f32(cx) + 0.15 + 0.7 * fx.hash01(hk + 1), f32(cy) + 0.15 + 0.7 * fx.hash01(hk + 2), z + 0.003}
					r := 0.04 + 0.05 * fx.hash01(hk + 3)
					floor_ellipse(p, r, r * 0.8, weed)
				}
			}
			if fx.hash01(h + 17) < 0.3 {
				// the sky on the still water: a glint that comes and goes in place
				tw := math.sin(time * (0.5 + 0.4 * fx.hash01(h + 18)) + 6.3 * fx.hash01(h + 19))
				tw = max(tw, 0)
				tw *= tw * tw
				px, py := f32(cx) + 0.2 + 0.5 * fx.hash01(h + 20), f32(cy) + 0.2 + 0.6 * fx.hash01(h + 21)
				floor_strip({px, py, z + 0.004}, {px + 0.18, py, z + 0.004}, {0, 1, 0}, 0.02, {glint.r, glint.g, glint.b, glint.a * 0.8 * tw})
			}
			if fx.hash01(h + 5) < 0.25 {
				// a bubble: it rises (a dot), breaks, and its ring spreads
				period := 5 + 6 * fx.hash01(h + 6)
				t := math.mod(time / period + fx.hash01(h + 7), 1)
				p := Vec3{f32(cx) + 0.2 + 0.6 * fx.hash01(h + 8), f32(cy) + 0.2 + 0.6 * fx.hash01(h + 9), z + 0.005}
				if t < 0.08 {
					floor_ellipse(p, 0.035, 0.035, {weed.r, weed.g, weed.b, 0.6})
				} else if t < 0.4 {
					u := (t - 0.08) / 0.32
					floor_ring(p, 0.04 + 0.22 * u, 0.012, {weed.r, weed.g, weed.b, 0.45 * (1 - u)})
				}
			}
		}
	}
}

// Oil stains, Psyche's shadow and the cracks of the illusions.
@(private)
draw_decals :: proc(g: ^game.Game) {
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rlgl.SetTexture(rlgl.GetTextureIdDefault())

	stain_fade: f32 = g.collapse_t >= 0 ? 1 - fx.clamp01(g.collapse_t / 2) : 1
	begin_turn(g, g.palace.upside)
	for i in 0 ..< g.stain_count {
		st := g.stains[i]
		floor_ellipse(st.pos + {0, 0, 0.004}, 0.06, 0.06, {0.5, 0.3, 0.08, 0.55 * stain_fade})
	}
	end_turn()
	floor_ellipse(g.psyche.pos + {0, 0, 0.006}, 0.13, 0.13, {0, 0, 0.04, 0.4 * game.psyche_alpha(g)})

	// Proserpina's pomegranates: a ring of dark red on both faces of their stones
	for c, n in g.data.pomegranates {
		k := 0.6 + 0.4 * math.sin(g.time * 1.2 + f32(n))
		col := Color4{0.95, 0.3, 0.32, 0.3 * k}
		for under in ([2]bool{false, true}) {
			begin_turn(g, under)
			p := Vec3{f32(c.x) + 0.5, f32(c.y) + 0.5, f32(c.z) + 0.007}
			floor_ring(p, 0.32, 0.05, col)
			floor_ellipse(p - {0, 0, 0.001}, 0.3, 0.3, {col.r, col.g, col.b, col.a * 0.22})
			end_turn()
		}
	}

	// the world as described (lawns, sundials, perches, parts), turned with it
	begin_turn(g, false)
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

	// the sundials that turn the time: a soft ring of light on their stone,
	// golden by day, rose at evening, breathing slowly
	for c, n in g.data.sundials {
		k := 0.6 + 0.4 * math.sin(g.time * 1.4 + f32(n))
		col := fx.lerp(Color4{1.0, 0.92, 0.55, 0.32}, Color4{1.0, 0.62, 0.72, 0.32}, g.evening)
		col.a *= k
		floor_ring(pl.node_world(&g.palace, c) + {0, 0, 0.007}, 0.32, 0.05, col)
		floor_ellipse(pl.node_world(&g.palace, c) + {0, 0, 0.006}, 0.3, 0.3, {col.r, col.g, col.b, col.a * 0.25})
	}

	// Jupiter's eagles: a faint golden ring on each perch; standing on one,
	// the ring where it will set her down breathes brighter
	for e, n in g.data.eagles {
		k := 0.6 + 0.4 * math.sin(g.time * 1.4 + f32(n))
		col := Color4{1.0, 0.84, 0.5, 0.26 * k}
		floor_ring(pl.node_world(&g.palace, e.from) + {0, 0, 0.007}, 0.32, 0.04, col)
		if game.at_eagle(g) && g.psyche.cell == e.from {
			land := pl.node_world(&g.palace, e.to) + {0, 0, 0.007}
			floor_ring(land, 0.3 + 0.04 * k, 0.06, {1.0, 0.86, 0.5, 0.55 * k})
			floor_ellipse(land - {0, 0, 0.001}, 0.3, 0.3, {1.0, 0.86, 0.5, 0.14 * k})
		}
	}

	end_turn()

	// a bronze inlay on the parts that turn (block_world: turned with them)
	for e, i in g.data.blocks {
		if e.part == 0 || !pl.block_present(&g.palace, i) || g.flip_t[i] >= 0 {
			continue
		}
		if e.solid.kind != .Block || pl.solid_at(&g.palace, pl.block_cell(&g.palace, i) + {0, 0, 1}).kind != .None {
			continue
		}
		top :: proc(g: ^game.Game, i: int, x, y: f32) -> Vec3 {
			return block_world(g, i, {x, y, 1.006})
		}
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

	// the exit: rings of wind spreading on the stone
	if ea := exit_alpha(g); g.data.has_exit && g.phase != .Finished && ea > 0 {
		begin_turn(g, g.data.exit_under)
		c := exit_point(g) + {0, 0, 0.008}
		floor_ellipse(c, 0.3, 0.3, {0.55, 0.75, 1.0, 0.22 * ea})
		for k in 0 ..< 3 {
			u := math.mod(g.time / 2.2 + f32(k) / 3, 1)
			floor_ring(c, 0.08 + 0.36 * u, 0.025, {0.75, 0.9, 1.0, 0.7 * (1 - u) * ea})
		}
		end_turn()
	}

	if truth := game.truth(g); truth > 0.01 && !g.turning && g.collapse_t < 0 && g.phase != .Overturn {
		for e, n in g.palace.illusion.pairs {
			p0, p1, inward := seam_edge(g, e)
			lift := Vec3{0, 0, 0.005}
			// a dark band in the stone...
			floor_strip(p0 + lift, p1 + lift, inward, 0.1, {0.02, 0.01, 0.04, 0.35 * truth})
			// ...and a jagged crack along the joint
			prev := p0 + lift
			for k in 1 ..= 6 {
				t := f32(k) / 6
				jitter: f32 = k < 6 ? (fx.hash01(u32(n * 7 + k)) - 0.5) * 0.05 : 0
				next := fx.lerp(p0, p1, t) + lift + inward * (0.012 + jitter * 0.5)
				floor_strip(prev, next, inward, 0.028, {0.03, 0.02, 0.05, 0.9 * truth})
				prev = next
			}
		}
	}
	if g.phase == .Prologue && g.data.scene == .Venus {
		// the scene's ants: the first one, then the files coming to her
		if p, d, a := game.venus_first_ant(g); a > 0 {
			ant(p + {0, 0, 0.006}, d, a, true)
		}
		for r in 0 ..< g.prologue.ant_count {
			for j in 0 ..< game.VE_FILE {
				if p, d, a := game.venus_ant(g, r, j); a > 0 {
					ant(p + {0, 0, 0.006}, d, a, j % 3 == 0)
				}
			}
		}
	}
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
}

// One ant on the floor at pos, walking toward dir: a dark body and head, a
// grain on its back.
@(private)
ant :: proc(pos, dir: Vec3, alpha: f32, grain: bool) {
	d := dir
	l := math.sqrt(d.x * d.x + d.y * d.y)
	d = l > 1e-5 ? d / l : Vec3{1, 0, 0}
	ink := Color4{0.05, 0.03, 0.04, 0.92 * alpha}
	blob :: proc(c, d: Vec3, along, across: f32, col: Color4) {
		side := Vec3{-d.y, d.x, 0}
		N :: 8
		rlgl.Begin(rlgl.TRIANGLES)
		color(col)
		for i in 0 ..< N {
			a0 := f32(i) / N * math.TAU
			a1 := f32(i + 1) / N * math.TAU
			vtx(c)
			vtx(c + d * (math.cos(a0) * along) + side * (math.sin(a0) * across))
			vtx(c + d * (math.cos(a1) * along) + side * (math.sin(a1) * across))
		}
		rlgl.End()
	}
	blob(pos - d * 0.016, d, 0.022, 0.012, ink)
	blob(pos + d * 0.016, d, 0.011, 0.009, ink)
	if grain {
		blob(pos - d * 0.005, d, 0.016, 0.011, {0.98, 0.84, 0.5, 0.95 * alpha})
	}
}

// A soft round glow facing the camera; radius in proto pixels.
@(private)
glow :: proc(v: View, at: Vec3, radius: f32, c: Color4, stretch_y: f32 = 1, toward: f32 = 0) {
	right, up := billboard_axes(v)
	// `toward`: cells nearer the camera, the same spot on screen (a glow on a
	// wall would otherwise sink half into it, cut along a diagonal)
	center := at + depth_axis(v) * toward
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

// The Stygian sleep: dark puffs over everything (alpha, not light).
@(private)
draw_mist :: proc(r: ^Renderer, s: ^Scene, v: View) {
	if s.mist.count == 0 {
		return
	}
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	// darken the colour, keep the canvas opaque (its alpha untouched)
	rlgl.SetBlendFactorsSeparate(rlgl.SRC_ALPHA, rlgl.ONE_MINUS_SRC_ALPHA, rlgl.ZERO, rlgl.ONE, rlgl.FUNC_ADD, rlgl.FUNC_ADD)
	rl.BeginBlendMode(.CUSTOM_SEPARATE)
	rlgl.SetTexture(r.radial.id)
	rlgl.Begin(rlgl.QUADS)
	for p in fx.alive(&s.mist) {
		col := p.color
		col.a *= fx.mote_alpha(p)
		glow(v, p.pos, p.size * (0.6 + 0.6 * p.age / p.life), col)
	}
	rlgl.End()
	rlgl.SetTexture(0)
	rl.EndBlendMode()
	rlgl.EnableDepthMask()
}

// Additive light: lamp, aura, seal, Cupid, drops, wings and particles.
@(private)
draw_glows :: proc(r: ^Renderer, s: ^Scene, g: ^game.Game, v: View) {
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rl.BeginBlendMode(.ADDITIVE)

	draw_doves(g, v)

	rlgl.SetTexture(r.radial.id)
	rlgl.Begin(rlgl.QUADS)
	psy := g.psyche
	t := g.time
	// Psyche's faint inner light; in the dark a pale silver halo shows where
	// she is (cool, so it is never taken for the lamp, and fainter in its light)
	glow(v, psy.pos + {0, 0, 0.42}, 46, {0.55, 0.6, 1.0, (0.18 + 0.06 * math.sin(t * 1.7)) * game.psyche_alpha(g)})
	if dark := psyche_dark(g); dark > 0.01 {
		glow(v, psy.pos + {0, 0, 0.32}, 92, {0.62, 0.7, 1.0, 0.14 * dark * game.psyche_alpha(g)}, 1.25)
	}
	// her body a faint rose, her wings of energy small, violet to blue (the
	// soul's butterfly), quicker as she walks; gone as the sleep lays her down
	if pa := game.psyche_alpha(g) * (1 - game.sleep_fall(g)); pa > 0.003 {
		glow(v, psy.pos + {0, 0, 0.26}, 15, {1.0, 0.6, 0.78, 0.16 * pa}, 1.8, toward = 0.3)
		fwd := Vec3{math.cos(psy.yaw), math.sin(psy.yaw), 0}
		light_wings(v, psy.pos + {0, 0, 0.4} - fwd * 0.035, t, PSYCHE_WINGS, psy.walking ? 3.5 : 1, pa)
	}
	// where she is (game.point_at_psyche): a shaft of soft light coming down
	// on her, as over a fragment but orange-red (never taken for the diorama's
	// golds), motes drifting down it, a pool at her feet
	if a := fx.cubic_out(g.pointer); a > 0.003 {
		breath := 0.8 + 0.2 * math.sin(t * 1.3)
		for n in 0 ..< 7 {
			h := 1.1 + f32(n) * 0.42
			rise := f32(n) / 7
			glow(v, psy.pos + {0, 0, h}, 16 + f32(n) * 1.5, {1.0, 0.45, 0.2, a * 0.3 * (1 - rise) * (1 - rise) * breath}, 2.4)
		}
		for m in 0 ..< 4 {
			k := math.mod(t * 0.3 + f32(m) * 0.25, 1)
			glow(v, psy.pos + {0, 0, 3.4 - k * 2.3}, 5, {1.0, 0.68, 0.45, a * 0.75 * math.sin(k * math.PI)}, 1.4)
		}
		glow(v, psy.pos + {0, 0, 0.02}, 44, {1.0, 0.4, 0.15, a * 0.3 * breath}, 0.5)
	}
	// the procession's torches, and their smoke once put out
	if game.procession(g) {
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
	seen := game.psyche_alpha(g)
	glow(v, lamp, 150, {1.0, 0.68, 0.32, g.light * 0.32 * f * (0.4 + 0.6 * seen)})
	glow(v, lamp + {0, 0, 0.02}, 9 * (0.85 + 0.15 * f), {1.0, 0.75, 0.4, g.light * f * seen}, 1.7)
	glow(v, lamp + {0, 0, 0.02}, 4 * (0.85 + 0.15 * f), {1.0, 0.95, 0.8, g.light * f * seen}, 1.6)
	// the fragments' faint glow
	for _, i in g.data.fragments {
		if a, lift := fragment_alpha(g, i); a > 0.003 && i not_in g.fragments_known {
			under := i in g.data.fragments_under
			c := shown(g, game.fragment_world(g, i) + {0, 0, lift}, under)
			glow(v, c, 58, {1.0, 0.86, 0.55, a * (0.3 + 0.08 * math.sin(t * 2.1 + f32(i)))})
			glow(v, c, 16, {1.0, 0.95, 0.8, a * 0.45})
			// a shaft of soft light rising over it, fading upward, seen from afar
			// (only from a world up: under the stones it would shine into them)
			if !game.upright(g, under) || g.phase == .Overturn {
				continue
			}
			f := g.data.fragments[i]
			base := Vec3{f32(f.x) + 0.5, f32(f.y) + 0.5, f32(f.z)}
			breath := 0.8 + 0.2 * math.sin(t * 1.3 + f32(i) * 1.7)
			for n in 0 ..< 6 {
				h := f32(n) * 0.38
				fall := 1 - f32(n) / 6
				glow(v, base + {0, 0, 0.35 + h}, 20 - f32(n) * 1.5, {1.0, 0.88, 0.6, a * 0.26 * fall * fall * breath}, 2.4)
			}
			glow(v, base + {0, 0, 1.1}, 9, {1.0, 0.95, 0.82, a * 0.34 * breath}, 9)
			glow(v, base + {0, 0, 0.02}, 40, {1.0, 0.85, 0.5, a * 0.25 * breath}, 0.5)
		}
	}
	// the exit: a pale breath of wind on the stone (a column of light where its world is up)
	if ea := exit_alpha(g); g.data.has_exit && g.phase != .Finished && ea > 0 {
		under := g.data.exit_under
		c := exit_point(g) + {0, 0, 0.3}
		pulse := 0.85 + 0.15 * math.sin(t * 1.3)
		glow(v, shown(g, c, under), 130, {0.5, 0.7, 1.0, 0.3 * pulse * ea}, 1.2)
		if game.upright(g, under) && g.phase != .Overturn {
			// a column of pale light rising from the stone
			glow(v, c + {0, 0, 0.75}, 30, {0.7, 0.85, 1.0, 0.32 * pulse * ea}, 5.5)
			glow(v, c + {0, 0, 0.6}, 12, {0.92, 0.97, 1.0, 0.45 * pulse * ea}, 8)
		}
		glow(v, shown(g, c + {0, 0, -0.25}, under), 40, {0.85, 0.93, 1.0, 0.45 * ea})
	}
	// Proserpina's pomegranates: a dark red gleam on both faces of their stones
	for c, n in g.data.pomegranates {
		breath := 0.75 + 0.25 * math.sin(t * 1.2 + f32(n))
		for under in ([2]bool{false, true}) {
			f := POMEGRANATE_AT
			p := shown(g, Vec3{f32(c.x) + f.x, f32(c.y) + f.y, f32(c.z) + 0.16}, under)
			glow(v, p, 34, {1.0, 0.32, 0.3, 0.2 * breath})
		}
	}
	for p in fx.alive(&s.wind) {
		col := p.color
		col.a *= fx.mote_alpha(p)
		glow(v, p.pos, p.size * 0.5, col)
	}
	// the candles on the walls, where the setting has them lit
	{
		for c in candle_lights(g) {
			fp, fl := c.pos, c.strength
			// off the wall toward the camera, as far as each halo reaches
			glow(v, fp, 64, {1.0, 0.6, 0.26, 0.26 * fl}, toward = 1.6)
			glow(v, fp, 18, {1.0, 0.7, 0.35, 0.35 * fl}, toward = 0.5)
			glow(v, fp + {0, 0, 0.02}, 6, {1.0, 0.78, 0.42, fl}, 1.8, 0.2)
			glow(v, fp + {0, 0, 0.02}, 2.6, {1.0, 0.96, 0.85, fl}, 1.6, 0.2)
		}
	}
	// the fires: a wide warm halo, tongues of flame leaping
	for c, i in fire_lights(g) {
		fp, fl := c.pos, c.strength / FIRE_STRENGTH
		glow(v, fp, 130, {1.0, 0.48, 0.18, 0.28 * fl}, toward = 1.2)
		glow(v, fp, 34, {1.0, 0.6, 0.24, 0.45 * fl}, toward = 0.6)
		for k in 0 ..< 3 {
			ph := t * (6 + f32(k)) + f32(i * 5 + k) * 2.1
			tongue := fp + {0.07 * f32(k - 1), 0.05 * math.sin(ph * 0.7), 0.04 + 0.05 * math.sin(ph)}
			glow(v, tongue, 10, {1.0, 0.62, 0.22, 0.9 * fl}, 2.2, 0.4)
			glow(v, tongue + {0, 0, 0.03}, 4.5, {1.0, 0.92, 0.7, fl}, 2.0, 0.4)
		}
	}
	// the candelabra: three flames each, a warm halo; one just lit flares up
	for _, i in g.data.candelabra {
		k := game.assembly(g, g.data.candelabra[i].cell, 1)
		burn := game.candelabrum_flame(g, i) * k * k // out with its stone, as the diorama rises or breaks up
		if burn <= 0.003 {
			continue
		}
		base := candelabrum_world(g, i)
		under := g.data.candelabra[i].under
		flare: f32 = 0
		if since := g.candelabrum_t[i]; since >= 0 {
			flare = math.exp(-since * 2.5)
		}
		glow(v, shown(g, base + {0, 0, 1.0}, under), 90 * (1 + flare), {1.0, 0.62, 0.28, (0.22 + 0.3 * flare) * burn}, toward = 1.2)
		for fp, k in CANDELABRUM_FLAMES {
			fl := (0.85 + 0.1 * math.sin(t * 13 + f32(i * 3 + k) * 1.7) + 0.05 * math.sin(t * 31 + f32(k))) * burn
			p := shown(g, base + Vec3(fp), under)
			glow(v, p, 5, {1.0, 0.78, 0.42, fl}, 1.8)
			glow(v, p, 2.2, {1.0, 0.96, 0.85, fl}, 1.6)
		}
	}
	// the braziers Psyche has lit; over the last one (where R brings her back)
	// a column of warm light and embers rising, seen from afar
	for c, i in g.data.rests {
		if !g.rests_lit[i] {
			continue
		}
		fp := shown(g, Vec3{f32(c.x), f32(c.y), f32(c.z)} + ALTAR_FLAME, false)
		fl := 0.85 + 0.1 * math.sin(t * 17 + f32(i) * 2.3) + 0.05 * math.sin(t * 29 + f32(i))
		glow(v, fp, 90, {1.0, 0.6, 0.25, 0.28 * fl})
		glow(v, fp + {0, 0, 0.03}, 10, {1.0, 0.75, 0.4, fl}, 1.8)
		glow(v, fp + {0, 0, 0.03}, 4.5, {1.0, 0.95, 0.8, fl}, 1.6)
		if !g.rest.valid || g.rest.cell != c || !game.upright(g, false) || g.phase == .Overturn {
			continue
		}
		breath := 0.8 + 0.2 * math.sin(t * 1.1)
		for n in 0 ..< 7 {
			h := f32(n) * 0.4
			fall := 1 - f32(n) / 7
			glow(v, fp + {0, 0, 0.3 + h}, 24 - f32(n) * 1.8, {1.0, 0.62, 0.28, 0.42 * fall * fall * breath}, 2.4)
		}
		glow(v, fp + {0, 0, 0.02}, 46, {1.0, 0.55, 0.2, 0.3 * breath}, 0.5)
		for m in 0 ..< 5 {
			k := math.mod(t * 0.35 + f32(m) * 0.2, 1)
			sway := Vec3{math.sin(t * 1.7 + f32(m) * 2.4) * 0.08, math.cos(t * 1.3 + f32(m) * 1.9) * 0.08, 0.2 + k * 2.6}
			glow(v, fp + sway, 4, {1.0, 0.72, 0.38, 0.9 * math.sin(k * math.PI)}, 1.2)
		}
	}
	// the stones the seal raises glow gold as they come up, and a while after
	for e, i in g.data.rise {
		rt := game.rise_time(g, i)
		if rt < 0 {
			continue
		}
		k := fx.progress(rt, game.rise_start(g, i), game.RISE_TIME)
		after := rt - game.rise_landing(g, i)
		a := k > 0 ? (after < 0 ? 0.55 * k + 0.2 : 0.75 * math.exp(-after * 1.3)) : 0
		if a < 0.01 {
			continue
		}
		c := Vec3{f32(e.cell.x) + 0.5, f32(e.cell.y) + 0.5, f32(e.cell.z) + 1.0} + {0, 0, rise_lift(g, i)}
		glow(v, shown(g, c, e.under), 70, {1.0, 0.75, 0.35, a * 0.5})
		glow(v, shown(g, c - {0, 0, 0.5}, e.under), 40, {1.0, 0.85, 0.5, a * 0.35}, 2.2)
	}
	// the lit seals breathe
	for c0, k in g.data.sigils {
		if k not_in g.activated || k in g.data.guard_seals || g.collapse_t >= 0 {
			continue
		}
		c := shown(g, Vec3{f32(c0.x) + 0.5, f32(c0.y) + 0.5, f32(c0.z) + 0.05}, k in g.data.sigils_under)
		pulse := 0.25 + 0.55 * (0.5 + 0.5 * math.cos(g.rise_t[k] * math.PI / 1.4))
		glow(v, c, 70, {1.0, 0.75, 0.35, pulse * game.assembly(g, c0, 1)})
	}
	// an unlit seal near her in the dark: a faint warmth and motes of gold rising
	for c0, k in g.data.sigils {
		sense := game.seal_sense(g, k)
		if sense < 0.01 {
			continue
		}
		c := shown(g, Vec3{f32(c0.x) + 0.5, f32(c0.y) + 0.5, f32(c0.z) + 0.05}, k in g.data.sigils_under)
		glow(v, c, 50, {1.0, 0.7, 0.35, 0.3 * sense}, 0.5, toward = 1.0)
		if g.reduce_motion {
			continue
		}
		for m in 0 ..< 5 {
			h := u32(k) * 31 + u32(m) * 7
			u := math.mod(t * (0.22 + 0.08 * fx.hash01(h)) + fx.hash01(h + 1), 1)
			drift := Vec3{0.32 * (fx.hash01(h + 2) - 0.5) + 0.05 * math.sin(t * 1.4 + f32(m)), 0.32 * (fx.hash01(h + 3) - 0.5), 0.1 + 0.9 * u}
			glow(v, c + drift, 7, {1.0, 0.72, 0.35, sense * math.sin(u * math.PI)}, 1.2, toward = 0.4)
		}
	}
	// Jupiter's eagles: a golden light about them, brighter in flight
	for _, i in g.data.eagles {
		p, _, spread := game.eagle_pose(g, i)
		breath := 0.85 + 0.15 * math.sin(t * 1.3 + f32(i) * 2.1)
		glow(v, p + {0, 0, 0.15}, 70 + 50 * spread, {1.0, 0.78, 0.4, (0.16 + 0.12 * spread) * breath})
		glow(v, p + {0, 0, 0.15}, 20, {1.0, 0.92, 0.7, 0.3 * breath})
	}
	// where the eagle she stands under will set her down: a column of gold
	if game.at_eagle(g) {
		e := g.data.eagles[pl.eagle_at(&g.palace, g.psyche.cell)]
		c := pl.node_world(&g.palace, e.to)
		pulse := 0.8 + 0.2 * math.sin(t * 1.6)
		for n in 0 ..< 5 {
			glow(v, c + {0, 0, 0.3 + f32(n) * 0.35}, 18 - f32(n) * 2, {1.0, 0.85, 0.5, 0.22 * pulse * (1 - f32(n) / 5)}, 2.4)
		}
		glow(v, c + {0, 0, 0.02}, 44, {1.0, 0.8, 0.45, 0.28 * pulse}, 0.5)
	}
	// the tower speaking: lights rising through its stones under the brink
	for k in 0 ..< game.TW_LIGHTS {
		if p, a := game.tower_light(g, k); a > 0.003 {
			glow(v, p, 44, {1.0, 0.6, 0.38, 0.55 * a}, 1.6)
			glow(v, p, 12, {1.0, 0.9, 0.72, 0.85 * a})
		}
	}
	// Charon's boats: a pale lantern on each prow; the coin passing from her lips to his hand
	for c in game.charons(g) {
		p := shown(g, game.boat_at(c.boat, game.BOAT_STERN + game.BOAT_LENGTH) + {0, 0, 0.42}, false)
		breath := 0.85 + 0.15 * math.sin(t * 1.1)
		glow(v, p, 60, {0.9, 0.55, 0.45, 0.22 * breath * c.alpha})
		glow(v, p, 10, {1.0, 0.86, 0.72, 0.6 * breath * c.alpha})
	}
	if c, ok := game.boat_coin(g); ok {
		glow(v, c, 14, {1.0, 0.82, 0.4, 0.55})
		glow(v, c, 4, {1.0, 0.95, 0.8, 0.95})
	}
	// Venus: a rose light, her star's
	if vp, alpha := game.venus_figure(g); alpha > 0.003 {
		glow(v, vp + {0, 0, 0.35}, 160, {1.0, 0.55, 0.62, 0.32 * alpha})
		glow(v, vp + {0, 0, 0.4}, 46, {1.0, 0.82, 0.86, 0.45 * alpha})
	}
	// the little ant that pities her: a glint at her feet
	if p, _, a := game.venus_first_ant(g); a > 0.003 {
		fade := 1 - fx.progress(g.phase_t, game.VE_SWARM + 1.5, 1.5)
		glow(v, p + {0, 0, 0.02}, 12, {1.0, 0.85, 0.5, 0.8 * a * fade})
	}
	// Cupid flying away: his light in the night sky
	if c, alpha := game.flight_cupid(g); alpha > 0.003 {
		glow(v, c + {0, 0, 0.2}, 150, {1.0, 0.72, 0.35, 0.35 * alpha})
		draw_cupid(g, v, c, alpha, true)
	}
	// Cupid: a warm breathing presence in the dark; the lamp shows his figure
	if g.data.has_amore {
		c := amore_position(g)
		fade := cupid_fade(g)
		presence := (0.28 + 0.12 * math.sin(t * 1.25)) * g.amore.breath * fade
		radius := 80 * (1 + 1.2 * g.amore.embrace)
		glow(v, c + {0, 0, 0.19}, radius, {1.0, 0.72, 0.35, presence})
		if alpha := g.amore.reveal * fade; alpha > 0.003 {
			draw_cupid(g, v, c, alpha, g.amore.fly_t >= 0)
		}
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
	for p in fx.alive(&s.embers) {
		col := p.color
		col.a *= fx.mote_alpha(p)
		glow(v, p.pos, p.size * 0.5, col)
	}
	rlgl.End()
	rlgl.SetTexture(0)
	rl.EndBlendMode()
	rlgl.EnableDepthMask()
}

// Into focus between the levels: gold traces the edges of each block as it
// rises (from the start outward), a soft halo about each line, then fades
// once the diorama stands (game.trace).
TRACE_HALO :: 5 // the halo's half width (pixels of the projection at zoom 1)

@(private)
draw_trace :: proc(s: ^Scene, g: ^game.Game, v: View) {
	fade := game.trace(g)
	if fade <= 0.003 {
		return
	}
	// the cube's twelve edges, as pairs of corners (bit 0 x, bit 1 y, bit 2 z)
	EDGES :: [12][2]u8{{0, 1}, {2, 3}, {4, 5}, {6, 7}, {0, 2}, {1, 3}, {4, 6}, {5, 7}, {0, 4}, {1, 5}, {2, 6}, {3, 7}}
	GOLD :: Vec3{0.98, 0.76, 0.36}
	Edge :: struct {
		a, b:  Vec3,
		alpha: f32,
	}
	edges := make([dynamic]Edge, context.temp_allocator)
	for p, i in s.pieces {
		if p.mesh != .Block {
			continue
		}
		lift, _, visible, _, hidden := piece_state(g, p, i)
		k := game.assembly(g, piece_cell(g, p), fx.hash01(u32(i) * 31 + 7))
		if !visible || hidden || k <= 0.02 {
			continue
		}
		m := piece_matrix(g, p, lift)
		corner :: proc(m: rl.Matrix, b: u8) -> Vec3 {
			// a hair outside the cube, so its own faces do not hide its edges
			local := Vec3{b & 1 != 0 ? 1.004 : -0.004, b & 2 != 0 ? 1.004 : -0.004, b & 4 != 0 ? 1.004 : -0.004}
			return rl.Vector3Transform(local, m)
		}
		grow := fx.cubic_out(fx.clamp01(k * 1.2)) // each edge drawn out from its first corner
		alpha := fade * fx.sine_in_out(fx.clamp01(k / 0.7)) // each block's lines come up as it rises
		for e in EDGES {
			a := corner(m, e[0])
			append(&edges, Edge{a, fx.lerp(a, corner(m, e[1]), grow), alpha})
		}
	}
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	// the halo: light added about each line, bright at the line, nothing at its rim
	rl.BeginBlendMode(.ADDITIVE)
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	right, up := billboard_axes(v)
	rlgl.Begin(rlgl.TRIANGLES)
	for e in edges {
		d := world_to_screen(v, e.b) - world_to_screen(v, e.a)
		n := math.sqrt(d.x * d.x + d.y * d.y)
		if n < 0.001 {
			continue
		}
		d /= n
		side := (right * -d.y - up * d.x) * TRACE_HALO // across the line on screen
		core := Color4{GOLD.x, GOLD.y, GOLD.z, e.alpha * 0.35}
		rim := Color4{GOLD.x, GOLD.y, GOLD.z, 0}
		for sgn in ([2]f32{-1, 1}) {
			a2, b2 := e.a + side * sgn, e.b + side * sgn
			color(core); vtx(e.a)
			color(rim); vtx(a2)
			color(rim); vtx(b2)
			color(core); vtx(e.a)
			color(rim); vtx(b2)
			color(core); vtx(e.b)
		}
	}
	rlgl.End()
	rlgl.DrawRenderBatchActive()
	rlgl.SetTexture(0)
	// the lines themselves: gold on any stone, by day as by night
	rl.BeginBlendMode(.ALPHA)
	rlgl.Begin(rlgl.LINES)
	for e in edges {
		color({GOLD.x, GOLD.y, GOLD.z, e.alpha})
		vtx(e.a)
		vtx(e.b)
	}
	rlgl.End()
	rlgl.DrawRenderBatchActive()
	rl.EndBlendMode()
	rlgl.EnableDepthMask()
}

// An ellipse in the plane spanned by u and w, around `center`, in n slices.
@(private)
ellipse_3d :: proc(center, u, w: Vec3, rx, ry, tilt: f32, c: Color4, n := 18) {
	ct, st := math.cos(tilt), math.sin(tilt)
	point :: proc(center, u, w: Vec3, x, y, ct, st: f32) -> Vec3 {
		return center + u * (x * ct - y * st) + w * (x * st + y * ct)
	}
	rlgl.Begin(rlgl.TRIANGLES)
	for i in 0 ..< n {
		a0 := f32(i) / f32(n) * math.TAU
		a1 := f32(i + 1) / f32(n) * math.TAU
		color(c)
		vtx(center)
		vtx(point(center, u, w, math.cos(a0) * rx, math.sin(a0) * ry, ct, st))
		vtx(point(center, u, w, math.cos(a1) * rx, math.sin(a1) * ry, ct, st))
	}
	rlgl.End()
}

// The doves of Venus: white wings beating fast.
@(private)
draw_doves :: proc(g: ^game.Game, v: View) {
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	up := Vec3{0, 0, 1}
	for i in 0 ..< game.VE_DOVES {
		p, d, a := game.venus_dove(g, i)
		if a <= 0.003 {
			continue
		}
		l := math.sqrt(d.x * d.x + d.y * d.y)
		dfwd := l > 1e-5 ? Vec3{d.x / l, d.y / l, 0} : Vec3{1, 0, 0}
		dside := Vec3{-dfwd.y, dfwd.x, 0}
		beat := math.sin(g.time * 15 + f32(i) * 1.7)
		for sgn in ([2]f32{-1, 1}) {
			wing := dside * sgn * math.cos(beat * 0.9) + up * math.sin(beat * 0.9)
			ellipse_3d(p + wing * 0.05 + up * 0.012, wing, dfwd, 0.055, 0.022, 0, {1.0, 0.97, 0.94, 0.8 * a})
		}
	}
}

// Cupid as pure light (user, 2026-10-18): a figure of light that breathes, a
// robe narrowing to the shoulders, the head above, a white core; wings of
// energy (light_wings), longer and quicker in flight. Inside draw_glows' quads.
@(private)
draw_cupid :: proc(g: ^game.Game, v: View, c: Vec3, alpha: f32, flying: bool) {
	t := g.time
	a := alpha * (0.85 + 0.15 * math.sin(t * 2.1))
	glow(v, c + {0, 0, 0.16}, 13, {1.0, 0.74, 0.4, 0.75 * a}, 2.3) // the robe
	glow(v, c + {0, 0, 0.37}, 11, {1.0, 0.84, 0.56, 0.7 * a}, 0.9) // the shoulders
	glow(v, c + {0, 0, 0.54}, 7, {1.0, 0.93, 0.8, 1.0 * a}) // the head
	glow(v, c + {0, 0, 0.28}, 5, {1.0, 0.97, 0.9, 0.9 * a}, 3.2) // the core
	light_wings(v, c + {0, 0, 0.4}, t, CUPID_WINGS, flying ? 3.5 : 1, alpha, flying ? 1.3 : 1)
}

// Wings of energy: filaments of light sweeping out from the shoulders, spread
// across the screen, a ripple running along each and a bead of light flowing
// out to its tip. Cupid's broad and golden (a god), Psyche's small, violet to blue.
Wing_Look :: struct {
	filaments: int,
	reach:     f32, // the upper filament's length, in cells
	lift:      f32, // how high the upper filament arches
	fan:       f32, // each filament below arches this much less
	size:      f32, // a filament's thickness at the root
	root, tip: Vec3, // its colour at the root and at the tip
	alpha:     f32,
}

CUPID_WINGS :: Wing_Look{filaments = 5, reach = 0.95, lift = 0.36, fan = 0.12, size = 8, root = {1.0, 0.86, 0.58}, tip = {1.0, 0.68, 0.36}, alpha = 0.5}
PSYCHE_WINGS :: Wing_Look{filaments = 3, reach = 0.26, lift = 0.12, fan = 0.07, size = 3.5, root = {0.66, 0.52, 1.0}, tip = {0.45, 0.62, 1.0}, alpha = 0.45}

// `pace`: how quick the ripple runs; `stretch`: longer (in flight).
@(private)
light_wings :: proc(v: View, root: Vec3, t: f32, w: Wing_Look, pace, alpha: f32, stretch: f32 = 1) {
	right, _ := billboard_axes(v)
	side := right / math.sqrt(linalg_dot(right, right))
	up := Vec3{0, 0, 1}
	TRAIL :: 24
	for sgn in ([2]f32{-1, 1}) {
		for k in 0 ..< w.filaments {
			fk := f32(k)
			lift := w.lift - fk * w.fan // the upper filament arches most
			reach := w.reach * stretch * (1 - fk * 0.08)
			thin := 1 - fk * 0.12
			bead := math.mod(t * 0.45 * pace + fk * 0.37 + (sgn > 0 ? 0.5 : 0), 1)
			for j in 0 ..< TRAIL {
				u := f32(j + 1) / TRAIL
				wave := 0.03 * reach * math.sin(t * 1.6 * pace - u * 5 + fk)
				p := root + side * sgn * u * reach + up * (lift * math.sin(u * math.PI * 0.9) + wave - u * 0.05 * fk)
				col := fx.lerp(w.root, w.tip, u)
				flow := 1 + 1.6 * max(0, 1 - abs(u - bead) * 9)
				glow(v, p, w.size * (1 - 0.65 * u) * thin, {col.x, col.y, col.z, alpha * w.alpha * (1 - u) * thin * flow})
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
horizon_uv :: proc(s: ^Scene, g: ^game.Game, view: View) -> f32 {
	if look_of(g).ridges == 0 {
		return 1
	}
	v := backdrop_view(s, g, view, 0.25)
	return proto_to_screen(v, {0, s.fit.y + s.fit.h - 430}).y / v.height
}

// The sky and the far ranges share the orb, the horizon and the turn.
@(private)
set_sky_uniforms :: proc(b: Backdrop, s: ^Scene, g: ^game.Game, v: View) {
	lk := look_of(g)
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
	lk := look_of(g)
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
	lk := look_of(g)
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

// The far backdrop (not moved aside with the diorama for a side panel); in a
// tall level it follows the camera's pan only by `k` (0: not at all, 1: as the
// level): the horizon sinks slowly as she climbs.
@(private)
backdrop_view :: proc(s: ^Scene, g: ^game.Game, v: View, k: f32) -> View {
	out := v
	out.center, out.zoom = v.backdrop_center, v.backdrop_zoom
	if len(g.data.tiers) > 0 {
		base := tier_center(s, 0)
		out.center.y = base + (v.center.y - base) * k
	}
	return out
}

@(private)
draw_clouds :: proc(r: ^Renderer, s: ^Scene, g: ^game.Game, view: View, time: f32, front: bool) {
	v := backdrop_view(s, g, view, 0.5)
	b := r.clouds
	lk := look_of(g)
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

@(private)
quad_2d :: proc(a, b, c, d: Vec2, col: rl.Color) {
	ui.tri(a, b, c, col)
	ui.tri(a, c, d, col)
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
		case .Veiled: want = e.trait == .Veiled && !g.palace.flipped[i]
		case .Handle: want = e.part > 0
		case .Time, .Eagle, .Flip, .Ferry:
		}
		if !want || pl.solid_at(&g.palace, pl.block_cell(&g.palace, i) + {0, 0, 1}).kind != .None {
			continue
		}
		I :: 0.06
		outline(v, top(g, i, I, I), top(g, i, 1 - I, I), top(g, i, 1 - I, 1 - I), top(g, i, I, 1 - I), col, width)
		J :: 0.3
		outline(v, top(g, i, J, J), top(g, i, 1 - J, J), top(g, i, 1 - J, 1 - J), top(g, i, J, 1 - J), {col.r, col.g, col.b, col.a * 0.5}, width * 0.7)
	}
	// the floors the spindle works from (the sundials that turn the time, the
	// handles), the eagles' perches, the ferries' landings
	floors := make([dynamic]Cell, 0, 8, context.temp_allocator)
	#partial switch mech {
	case .Time:
		append(&floors, ..g.data.sundials[:])
	case .Handle:
		for h in g.data.handles {
			append(&floors, h.cell)
		}
	case .Eagle:
		for e in g.data.eagles {
			append(&floors, e.from)
		}
	case .Flip:
		append(&floors, ..g.data.pomegranates[:]) // either way up: they lie on the axle
	case .Ferry:
		for f in g.data.ferries {
			append(&floors, f.ends[0].cell, f.ends[1].cell)
		}
	}
	for c in floors {
		p := Vec3{f32(c.x), f32(c.y), f32(c.z) + 0.01}
		outline(v, p + {0.06, 0.06, 0}, p + {0.94, 0.06, 0}, p + {0.94, 0.94, 0}, p + {0.06, 0.94, 0}, col, width)
	}
}
