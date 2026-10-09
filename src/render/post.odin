// The canvas: at some graphics qualities (and under the settings' glass
// sheet) the world is drawn into an offscreen canvas instead of the screen,
// then drawn onto it: smaller than the screen (Low: cheaper), as large
// (Medium) or twice as large (Ultra: supersampling, every edge smooth).
// High draws straight to the screen, with the window's MSAA.
// The glass sheet frosts the canvas: half size, then quarter size blurred wide.
// The UI is drawn after, untouched.
package render

import rl "vendor:raylib"

import "../content"
import "../settings"

// How large the canvas is, relative to the screen, at each quality (0: no canvas).
QUALITY_SCALE := [settings.Quality]f32 {
	.Low    = 0.67,
	.Medium = 1,
	.High   = 0,
	.Ultra  = 2,
}

MAX_CANVAS :: 8192 // pixels on the canvas's long side (Ultra at 4K: 7680)

// The canvas scale for this quality at a w x h screen (0: draw to the screen).
canvas_scale :: proc(q: settings.Quality, w, h: f32) -> f32 {
	k := QUALITY_SCALE[q]
	return k == 0 ? 0 : min(k, MAX_CANVAS / max(w, h, 1))
}

Post :: struct {
	size:    [2]i32, // of the canvas; 0 until the first frame
	scene:   rl.RenderTexture2D, // the canvas, with depth
	soft:    rl.RenderTexture2D, // half size
	glass_a: rl.RenderTexture2D, // quarter size: the picture frosted, under glass panels
	glass_b: rl.RenderTexture2D,
	blur:    rl.Shader,
	texel:   i32, // blur uniforms
	dir:     i32,
	loaded:  bool,
}

post_init :: proc(p: ^Post) {
	p.blur = rl.LoadShaderFromMemory(nil, content.SHADER_POST_BLUR_FS)
	p.texel = rl.GetShaderLocation(p.blur, "texel")
	p.dir = rl.GetShaderLocation(p.blur, "dir")
}

@(private)
post_free_targets :: proc(p: ^Post) {
	if p.loaded {
		rl.UnloadRenderTexture(p.scene)
		rl.UnloadRenderTexture(p.soft)
		rl.UnloadRenderTexture(p.glass_a)
		rl.UnloadRenderTexture(p.glass_b)
		p.loaded = false
	}
}

post_shutdown :: proc(p: ^Post) {
	post_free_targets(p)
	rl.UnloadShader(p.blur)
	p^ = {}
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
	p.soft = target(w / 2, h / 2)
	p.glass_a = target(w / 4, h / 4)
	p.glass_b = target(w / 4, h / 4)
	p.size = {w, h}
	p.loaded = true
}

// Start drawing the world into the canvas (instead of the screen), w x h pixels.
post_begin :: proc(p: ^Post, w, h: f32) {
	post_fit(p, i32(w), i32(h))
	rl.BeginTextureMode(p.scene)
}

// Finish drawing the world into the canvas.
post_end :: proc(p: ^Post) {
	rl.EndTextureMode()
}

// Draw `src` over the whole of `dst`, with a shader or plain (render textures are upside down).
@(private)
pass :: proc(src, dst: rl.RenderTexture2D, shader: Maybe(rl.Shader) = nil) {
	rl.BeginTextureMode(dst)
	if s, ok := shader.?; ok {
		rl.BeginShaderMode(s)
	}
	sw, sh := f32(src.texture.width), f32(src.texture.height)
	rl.DrawTexturePro(src.texture, {0, 0, sw, -sh}, {0, 0, f32(dst.texture.width), f32(dst.texture.height)}, {}, 0, rl.WHITE)
	if _, ok := shader.?; ok {
		rl.EndShaderMode()
	}
	rl.EndTextureMode()
}

@(private)
blur :: proc(p: ^Post, a, b: rl.RenderTexture2D, spread: f32) {
	texel := [2]f32{1 / f32(a.texture.width), 1 / f32(a.texture.height)}
	rl.SetShaderValue(p.blur, p.texel, &texel, .VEC2)
	dir := [2]f32{spread, 0}
	rl.SetShaderValue(p.blur, p.dir, &dir, .VEC2)
	pass(a, b, p.blur)
	dir = {0, spread}
	rl.SetShaderValue(p.blur, p.dir, &dir, .VEC2)
	pass(b, a, p.blur)
}

// The picture frosted for a glass panel (after post_end): the canvas at
// quarter size, blurred wide. Drawn upside down, like every render texture.
post_glass :: proc(p: ^Post) -> rl.Texture2D {
	pass(p.scene, p.soft)
	pass(p.soft, p.glass_a)
	blur(p, p.glass_a, p.glass_b, 2)
	blur(p, p.glass_a, p.glass_b, 4)
	return p.glass_a.texture
}

// Draw the canvas onto whatever is being drawn to now (the screen or the
// screenshot canvas), at w x h: bilinear, so twice the size averages four
// pixels into one.
post_draw :: proc(p: ^Post, w, h: f32) {
	tw, th := f32(p.scene.texture.width), f32(p.scene.texture.height)
	rl.DrawTexturePro(p.scene.texture, {0, 0, tw, -th}, {0, 0, w, h}, {}, 0, rl.WHITE)
}
