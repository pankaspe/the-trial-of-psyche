// Post-processing: the world is drawn into an offscreen canvas, then
//   bright pass (half size) -> blur  -> bloom (wide)
//   downsample  (half size) -> blur  -> the soft scene (tilt-shift, glow)
// and composed with a grade. The UI is drawn after, untouched.
// A style is a set of numbers for one shader (Post_Params); Off skips it all.
package render

import rl "vendor:raylib"

import "../content"
import "../settings"
import "../game"

Post_Params :: struct {
	threshold:  f32, // what blooms
	bloom:      f32,
	rays:       f32,
	tilt:       f32,
	orton:      f32,
	paint:      f32, // brush radius in pixels (0: none)
	ink:        f32,
	paper:      f32,
	exposure:   f32,
	tonemap:    f32,
	contrast:   f32,
	saturation: f32,
	lift:       Vec3,
	gain:       Vec3,
	chroma:     f32,
	vignette:   f32,
	grain:      f32,
}

LOOKS_POST := [settings.Look]Post_Params {
	.Off = {exposure = 1, contrast = 1, saturation = 1, gain = {1, 1, 1}},
	.Clean = {
		threshold = 0.55, bloom = 0.7,
		exposure = 1.0, tonemap = 0.25, contrast = 1.1, saturation = 1.15,
		gain = {1, 1, 1}, vignette = 0.25, grain = 0.01,
	},
	.Miniature = {
		threshold = 0.65, bloom = 0.45, tilt = 1,
		exposure = 1.05, tonemap = 0.2, contrast = 1.15, saturation = 1.35,
		gain = {1, 1, 1}, vignette = 0.28,
	},
	.Film = {
		threshold = 0.55, bloom = 0.6,
		exposure = 1.0, tonemap = 0.5, contrast = 1.2, saturation = 1.1,
		lift = {0.0, 0.035, 0.06}, gain = {1.1, 1.0, 0.86},
		chroma = 2.5, vignette = 0.5, grain = 0.045,
	},
	.Dream = {
		threshold = 0.5, bloom = 0.85, rays = 0.6, orton = 0.18,
		exposure = 1.0, tonemap = 0.3, contrast = 1.0, saturation = 1.0,
		lift = {0.03, 0.02, 0.05}, gain = {1, 0.98, 0.98}, vignette = 0.3,
	},
	.Painted = {
		threshold = 0.65, bloom = 0.3, paint = 5, ink = 0.5, paper = 1,
		exposure = 1.0, tonemap = 0.2, contrast = 1.08, saturation = 1.15,
		gain = {1, 0.98, 0.94}, vignette = 0.3,
	},
}

Post_Uniform :: enum u8 {
	Texel, Threshold, Dir,
	Bloom_Tex, Soft_Tex, Resolution, Time,
	Bloom, Rays, Sun, Tilt, Focus, Orton, Paint, Ink, Paper,
	Exposure, Tonemap, Contrast, Saturation, Lift, Gain, Chroma, Vignette, Grain,
}

@(private)
POST_NAME := [Post_Uniform]cstring {
	.Texel = "texel", .Threshold = "threshold", .Dir = "dir",
	.Bloom_Tex = "bloom_tex", .Soft_Tex = "soft_tex", .Resolution = "resolution", .Time = "time",
	.Bloom = "bloom", .Rays = "rays", .Sun = "sun", .Tilt = "tilt", .Focus = "focus", .Orton = "orton",
	.Paint = "paint", .Ink = "ink", .Paper = "paper",
	.Exposure = "exposure", .Tonemap = "tonemap", .Contrast = "contrast", .Saturation = "saturation",
	.Lift = "lift", .Gain = "gain", .Chroma = "chroma", .Vignette = "vignette", .Grain = "grain",
}

Post_Shader :: struct {
	shader: rl.Shader,
	loc:    [Post_Uniform]i32,
}

Post :: struct {
	size:        [2]i32, // of the canvas; 0 until the first frame
	scene:       rl.RenderTexture2D, // full size, with depth
	bloom_a:     rl.RenderTexture2D, // quarter size
	bloom_b:     rl.RenderTexture2D,
	soft_a:      rl.RenderTexture2D, // half size
	soft_b:      rl.RenderTexture2D,
	glass_a:     rl.RenderTexture2D, // quarter size: the picture frosted, under glass panels
	glass_b:     rl.RenderTexture2D,
	bright:      Post_Shader,
	blur:        Post_Shader,
	compose:     Post_Shader,
	loaded:      bool,
}

post_init :: proc(p: ^Post) {
	load :: proc(fs: cstring) -> (s: Post_Shader) {
		s.shader = rl.LoadShaderFromMemory(nil, fs)
		for name, u in POST_NAME {
			s.loc[u] = rl.GetShaderLocation(s.shader, name)
		}
		return
	}
	p.bright = load(content.SHADER_POST_BRIGHT_FS)
	p.blur = load(content.SHADER_POST_BLUR_FS)
	p.compose = load(content.SHADER_POST_FS)
}

@(private)
post_free_targets :: proc(p: ^Post) {
	if p.loaded {
		rl.UnloadRenderTexture(p.scene)
		rl.UnloadRenderTexture(p.bloom_a)
		rl.UnloadRenderTexture(p.bloom_b)
		rl.UnloadRenderTexture(p.soft_a)
		rl.UnloadRenderTexture(p.soft_b)
		rl.UnloadRenderTexture(p.glass_a)
		rl.UnloadRenderTexture(p.glass_b)
		p.loaded = false
	}
}

post_shutdown :: proc(p: ^Post) {
	post_free_targets(p)
	rl.UnloadShader(p.bright.shader)
	rl.UnloadShader(p.blur.shader)
	rl.UnloadShader(p.compose.shader)
	p^ = {}
}

// The numbers of a look applied at `amount` (0: none .. 1: in full).
post_params :: proc(look: settings.Look, amount: f32) -> (k: Post_Params) {
	a := LOOKS_POST[.Off]
	b := LOOKS_POST[look]
	t := clamp(amount, 0, 1)
	mixf :: proc(x, y, t: f32) -> f32 {return x + (y - x) * t}
	k = b
	k.bloom = mixf(a.bloom, b.bloom, t)
	k.rays = mixf(a.rays, b.rays, t)
	k.tilt = mixf(a.tilt, b.tilt, t)
	k.orton = mixf(a.orton, b.orton, t)
	k.paint = t < 0.25 ? 0 : b.paint * min(t * 1.5, 1)
	k.ink = mixf(a.ink, b.ink, t)
	k.paper = mixf(a.paper, b.paper, t)
	k.exposure = mixf(a.exposure, b.exposure, t)
	k.tonemap = mixf(a.tonemap, b.tonemap, t)
	k.contrast = mixf(a.contrast, b.contrast, t)
	k.saturation = mixf(a.saturation, b.saturation, t)
	k.lift = a.lift + (b.lift - a.lift) * t
	k.gain = a.gain + (b.gain - a.gain) * t
	k.chroma = mixf(a.chroma, b.chroma, t)
	k.vignette = mixf(a.vignette, b.vignette, t)
	k.grain = mixf(a.grain, b.grain, t)
	return
}

// (Re)create the canvases when the size changes.
@(private)
post_fit :: proc(p: ^Post, w, h: i32) {
	if p.loaded && p.size == {w, h} {
		return
	}
	post_free_targets(p)
	target :: proc(w, h: i32) -> rl.RenderTexture2D {
		t := rl.LoadRenderTexture(max(w, 1), max(h, 1))
		rl.SetTextureFilter(t.texture, .BILINEAR)
		rl.SetTextureWrap(t.texture, .CLAMP)
		return t
	}
	p.scene = target(w, h)
	p.soft_a = target(w / 2, h / 2)
	p.soft_b = target(w / 2, h / 2)
	p.bloom_a = target(w / 4, h / 4)
	p.bloom_b = target(w / 4, h / 4)
	p.glass_a = target(w / 4, h / 4)
	p.glass_b = target(w / 4, h / 4)
	p.size = {w, h}
	p.loaded = true
}

// Start drawing the world into the canvas (instead of the screen).
post_begin :: proc(p: ^Post, w, h: f32) {
	post_fit(p, i32(w), i32(h))
	rl.BeginTextureMode(p.scene)
}

@(private)
pf :: proc(s: Post_Shader, u: Post_Uniform, value: f32) {
	v := value
	rl.SetShaderValue(s.shader, s.loc[u], &v, .FLOAT)
}

@(private)
pv2 :: proc(s: Post_Shader, u: Post_Uniform, value: Vec2) {
	v := value
	rl.SetShaderValue(s.shader, s.loc[u], &v, .VEC2)
}

@(private)
pv3 :: proc(s: Post_Shader, u: Post_Uniform, value: Vec3) {
	v := value
	rl.SetShaderValue(s.shader, s.loc[u], &v, .VEC3)
}

// Draw `src` over the whole of `dst` with a shader (render textures are upside down).
@(private)
pass :: proc(s: Post_Shader, src, dst: rl.RenderTexture2D) {
	rl.BeginTextureMode(dst)
	rl.BeginShaderMode(s.shader)
	sw, sh := f32(src.texture.width), f32(src.texture.height)
	rl.DrawTexturePro(src.texture, {0, 0, sw, -sh}, {0, 0, f32(dst.texture.width), f32(dst.texture.height)}, {}, 0, rl.WHITE)
	rl.EndShaderMode()
	rl.EndTextureMode()
}

@(private)
blur :: proc(p: ^Post, a, b: rl.RenderTexture2D, spread: f32) {
	texel := Vec2{1 / f32(a.texture.width), 1 / f32(a.texture.height)}
	pv2(p.blur, .Texel, texel)
	pv2(p.blur, .Dir, {spread, 0})
	pass(p.blur, a, b)
	pv2(p.blur, .Dir, {0, spread})
	pass(p.blur, b, a)
}

// Finish the world and run the passes; post_draw then composes the picture.
post_end :: proc(p: ^Post, k: Post_Params) {
	rl.EndTextureMode()
	// the soft scene: half size, blurred
	pv2(p.bright, .Texel, {1 / f32(p.size.x), 1 / f32(p.size.y)})
	pf(p.bright, .Threshold, 0)
	pass(p.bright, p.scene, p.soft_a)
	blur(p, p.soft_a, p.soft_b, 1.5)
	// the bloom: the bright parts, quarter size, blurred twice
	pf(p.bright, .Threshold, k.threshold)
	pass(p.bright, p.soft_a, p.bloom_a)
	blur(p, p.bloom_a, p.bloom_b, 1.5)
	blur(p, p.bloom_a, p.bloom_b, 3)
}

// The picture frosted for a glass panel (after post_end): the soft scene at
// quarter size, blurred wide. Drawn upside down, like every render texture.
post_glass :: proc(p: ^Post) -> rl.Texture2D {
	pf(p.bright, .Threshold, 0)
	pv2(p.bright, .Texel, {1 / f32(p.soft_a.texture.width), 1 / f32(p.soft_a.texture.height)})
	pass(p.bright, p.soft_a, p.glass_a)
	blur(p, p.glass_a, p.glass_b, 2)
	blur(p, p.glass_a, p.glass_b, 4)
	return p.glass_a.texture
}

// Compose the picture into whatever is being drawn to now (the screen or the
// screenshot canvas), at w x h. `sun`: the orb on screen (uv), for the shafts.
post_draw :: proc(p: ^Post, k: Post_Params, w, h: f32, sun: Vec2, focus: f32, time: f32) {
	s := p.compose
	pv2(s, .Resolution, {w, h})
	pf(s, .Time, time)
	pf(s, .Bloom, k.bloom)
	pf(s, .Rays, k.rays)
	pv2(s, .Sun, sun)
	pf(s, .Tilt, k.tilt)
	pf(s, .Focus, focus)
	pf(s, .Orton, k.orton)
	pf(s, .Paint, k.paint)
	pf(s, .Ink, k.ink)
	pf(s, .Paper, k.paper)
	pf(s, .Exposure, k.exposure)
	pf(s, .Tonemap, k.tonemap)
	pf(s, .Contrast, k.contrast)
	pf(s, .Saturation, k.saturation)
	pv3(s, .Lift, k.lift)
	pv3(s, .Gain, k.gain)
	pf(s, .Chroma, k.chroma)
	pf(s, .Vignette, k.vignette)
	pf(s, .Grain, k.grain)
	rl.BeginShaderMode(s.shader)
	rl.SetShaderValueTexture(s.shader, s.loc[.Bloom_Tex], p.bloom_a.texture)
	rl.SetShaderValueTexture(s.shader, s.loc[.Soft_Tex], p.soft_a.texture)
	tw, th := f32(p.scene.texture.width), f32(p.scene.texture.height)
	rl.DrawTexturePro(p.scene.texture, {0, 0, tw, -th}, {0, 0, w, h}, {}, 0, rl.WHITE)
	rl.EndShaderMode()
}

// Where Psyche is on screen (uv height): the band the tilt-shift keeps sharp.
focus_uv :: proc(g: ^game.Game, v: View) -> f32 {
	return clamp(world_to_screen(v, g.psyche.pos + {0, 0, 0.3}).y / v.height, 0.2, 0.8)
}

// Where the orb of the setting is on screen (uv), for the light shafts.
sun_uv :: proc(s: ^Scene, g: ^game.Game, v: View) -> Vec2 {
	lk := look(g.data.setting)
	return {lk.orb_pos.x - g.angle * 0.03, lk.orb_pos.y * horizon_uv(s, g, v)}
}
