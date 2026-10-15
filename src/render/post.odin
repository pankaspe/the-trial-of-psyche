// The canvas: at some graphics qualities the world is drawn into an offscreen
// canvas instead of the screen, then drawn onto it: smaller than the screen
// (Low: cheaper), as large (Medium) or twice as large (Ultra: supersampling,
// every edge smooth). High draws straight to the screen, with the window's
// MSAA. The UI is drawn after, untouched.
package render

import rl "vendor:raylib"

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
	size:   [2]i32, // of the canvas; 0 until the first frame
	scene:  rl.RenderTexture2D, // the canvas, with depth
	loaded: bool,
}

@(private)
post_free_targets :: proc(p: ^Post) {
	if p.loaded {
		rl.UnloadRenderTexture(p.scene)
		p.loaded = false
	}
}

post_shutdown :: proc(p: ^Post) {
	post_free_targets(p)
	p^ = {}
}

// (Re)create the canvases when the size changes.
@(private)
post_fit :: proc(p: ^Post, w, h: i32) {
	if p.loaded && p.size == {w, h} {
		return
	}
	post_free_targets(p)
	p.scene = rl.LoadRenderTexture(max(w, 1), max(h, 1))
	rl.SetTextureFilter(p.scene.texture, .BILINEAR)
	rl.SetTextureWrap(p.scene.texture, .CLAMP)
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

// Draw the canvas onto whatever is being drawn to now (the screen or the
// screenshot canvas), at w x h: bilinear, so twice the size averages four
// pixels into one.
post_draw :: proc(p: ^Post, w, h: f32) {
	tw, th := f32(p.scene.texture.width), f32(p.scene.texture.height)
	rl.DrawTexturePro(p.scene.texture, {0, 0, tw, -th}, {0, 0, w, h}, {}, 0, rl.WHITE)
}
