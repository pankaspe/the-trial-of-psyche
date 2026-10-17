// The canvas: at some graphics qualities the world is drawn into an offscreen
// canvas instead of the screen, then drawn onto it: smaller than the screen
// (Low: cheaper), as large (Medium) or twice as large (Ultra: supersampling,
// every edge smooth). High draws straight to the screen, with the window's
// MSAA. The UI is drawn after, untouched. Between two levels the world goes
// out of focus: the canvas is blurred on a small copy (`post_draw`'s `blur`),
// whatever the quality.
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
	size:      [2]i32, // of the canvas; 0 until the first frame
	scene:     rl.RenderTexture2D, // the canvas, with depth
	loaded:    bool,
	small:     [2]i32, // of the blurred copies; 0 until a blur
	blurred:   [2]rl.RenderTexture2D, // the world out of focus, and the other pass
	held:      rl.RenderTexture2D, // the last level out of focus, fading over the next
	hold:      bool, // keep the blurred world as it is now, before the next blur
	blur:      rl.Shader,
	blur_dir:  i32,
}

BLUR_SCALE :: 1.0 / 6 // the blurred copies, relative to the screen
BLUR_PASSES :: 2 // across and down, each wider than the last

@(private)
post_free_targets :: proc(p: ^Post) {
	if p.loaded {
		rl.UnloadRenderTexture(p.scene)
		p.loaded = false
	}
}

@(private)
post_free_blur :: proc(p: ^Post) {
	if p.small != {} {
		for t in p.blurred {
			rl.UnloadRenderTexture(t)
		}
		rl.UnloadRenderTexture(p.held)
		p.small = {}
	}
}

post_shutdown :: proc(p: ^Post) {
	post_free_targets(p)
	post_free_blur(p)
	if p.blur.id != 0 {
		rl.UnloadShader(p.blur)
	}
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
// pixels into one. `blur` (0 .. 1): how far the world is out of focus (as
// `post_blur` left it);
// `held` (0 .. 1): how much of the last level, out of focus, still covers it.
post_draw :: proc(p: ^Post, w, h: f32, blur: f32 = 0, held: f32 = 0) {
	stretch(p.scene.texture, w, h, 1)
	if blur > 0.003 && p.small != {} {
		stretch(p.blurred[0].texture, w, h, blur)
	}
	if held > 0.003 && p.small != {} {
		stretch(p.held.texture, w, h, held)
	}
}

// Keep the world out of focus as it is now: it covers the next level until
// `post_draw`'s `held` lets it go.
post_hold :: proc(p: ^Post) {
	p.hold = true
}

// A render texture drawn over the whole w x h target (they are stored upside down).
@(private)
stretch :: proc(t: rl.Texture2D, w, h, alpha: f32) {
	tw, th := f32(t.width), f32(t.height)
	rl.DrawTexturePro(t, {0, 0, tw, -th}, {0, 0, w, h}, {}, 0, rl.Fade(rl.WHITE, alpha))
}

// The canvas out of focus into `blurred[0]`, for a w x h screen: shrunk
// through its mipmaps, then blurred across and down on the small copy. Call
// it after `post_end`, before drawing to the screen (it leaves the target).
post_blur :: proc(p: ^Post, w, h: f32) {
	if p.blur.id == 0 {
		p.blur = rl.LoadShaderFromMemory(nil, content.SHADER_BLUR_FS)
		p.blur_dir = rl.GetShaderLocation(p.blur, "dir")
	}
	small := [2]i32{max(i32(w * BLUR_SCALE), 1), max(i32(h * BLUR_SCALE), 1)}
	if p.small != small {
		post_free_blur(p)
		for &t in p.blurred {
			t = rl.LoadRenderTexture(small.x, small.y)
		}
		p.held = rl.LoadRenderTexture(small.x, small.y)
		for t in ([3]rl.Texture2D{p.blurred[0].texture, p.blurred[1].texture, p.held.texture}) {
			rl.SetTextureFilter(t, .BILINEAR)
			rl.SetTextureWrap(t, .CLAMP)
		}
		p.small = small
	}
	sw, sh := f32(small.x), f32(small.y)
	if p.hold {
		rl.BeginTextureMode(p.held)
		stretch(p.blurred[0].texture, sw, sh, 1)
		rl.EndTextureMode()
		p.hold = false
	}
	rl.GenTextureMipmaps(&p.scene.texture)
	rl.SetTextureFilter(p.scene.texture, .TRILINEAR)
	rl.BeginTextureMode(p.blurred[0])
	stretch(p.scene.texture, sw, sh, 1)
	rl.EndTextureMode()
	// back to the canvas alone: with mipmaps raylib's bilinear samples them,
	// and they are not made again once the blur is over (a frozen picture)
	p.scene.texture.mipmaps = 1
	rl.SetTextureFilter(p.scene.texture, .BILINEAR)
	rl.BeginShaderMode(p.blur)
	for pass in 0 ..< BLUR_PASSES {
		spread := f32(pass + 1)
		for step in 0 ..< 2 {
			dir := step == 0 ? [2]f32{spread / sw, 0} : [2]f32{0, spread / sh}
			rl.SetShaderValue(p.blur, p.blur_dir, &dir, .VEC2)
			rl.BeginTextureMode(p.blurred[1 - step])
			stretch(p.blurred[step].texture, sw, sh, 1)
			rl.EndTextureMode()
		}
	}
	rl.EndShaderMode()
}
