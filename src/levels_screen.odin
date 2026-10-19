// The level select (proposal B, 2026-10-15): the chosen level is loaded
// behind the panel as the palace sleeping in attract mode, framed on the right
// and turning slowly, with its own sky and sound; the act's levels below as
// pictures, drawn once per session from a level loaded apart.
package main

import rl "vendor:raylib"

import "content"
import "game"
import "progress"
import "render"
import "ui"

LEVEL_SPIN :: 0.035 // quarter turns a second: the diorama behind the level select
LEVEL_SWAP :: 0.2 // the world darkening out, then in, when the chosen level changes
THUMB_SIZE :: [2]i32{512, 288}

Levels_Screen :: struct {
	sel:      ui.Level_Select,
	from:     int, // the level behind the title when the screen opened: back to it on leaving
	from_diorama: int, // and its diorama
	swap_t:   f32, // < 0, or time since the world began to darken for another level
	thumbs:   [content.LEVEL_COUNT]rl.RenderTexture2D, // a picture per built level (made on demand)
	pictures: [content.LEVEL_COUNT]rl.Texture2D, // their textures, for the ui (id 0: none yet)
	tried:    [content.LEVEL_COUNT]bool,
	apart:    game.Game, // a level loaded only to draw its picture
	apart_scene: render.Scene,
}

// The screen opens on the level to continue from.
enter_levels :: proc(app: ^App) {
	l := &app.levels
	l.sel.level = progress.current_level(app.prog)
	l.from = app.game.level_index
	l.from_diorama = app.game.diorama
	l.swap_t = -1
}

// Leave the level select: to play (the level chosen is loaded anew), or back
// to the title, over the level that was behind it.
leave_levels :: proc(app: ^App, to_title: bool) {
	l := &app.levels
	l.swap_t = -1
	if !to_title {
		app.stage = 0 // the level chosen is framed for play at once
	}
	if to_title {
		app.screen = .Title
		new_level(app, l.from, l.from_diorama)
	}
}

// Each frame: the diorama turning; the chosen level loaded
// behind while the world is dark.
update_levels :: proc(app: ^App, dt: f32) {
	l := &app.levels
	if app.screen != .Levels {
		return
	}
	g := &app.game
	if !app.cfg.reduce_motion {
		g.angle += dt * LEVEL_SPIN
	}
	want := l.sel.level
	if content.is_built(want) && want != g.level_index {
		if l.swap_t < 0 {
			l.swap_t = 0
		} else if l.swap_t > LEVEL_SWAP {
			l.swap_t = 2 * LEVEL_SWAP - l.swap_t // coming back in: dark again from there
		}
		l.swap_t += dt
		if l.swap_t >= LEVEL_SWAP {
			new_level(app, want)
			l.swap_t = LEVEL_SWAP
		}
	} else if l.swap_t >= 0 {
		l.swap_t += dt
		if l.swap_t >= 2 * LEVEL_SWAP {
			l.swap_t = -1
		}
	}
}

// How dark the world is drawn under the level select.
levels_veil :: proc(app: ^App) -> f32 {
	l := &app.levels
	if !content.is_built(l.sel.level) {
		return 0.9
	}
	if l.swap_t < 0 {
		return 0
	}
	return l.swap_t < LEVEL_SWAP ? l.swap_t / LEVEL_SWAP : 2 - l.swap_t / LEVEL_SWAP
}

// One picture a frame while the level select is open: the level loaded
// apart, drawn whole into its texture.
draw_level_picture :: proc(app: ^App) {
	l := &app.levels
	if app.screen != .Levels {
		return
	}
	for i in 0 ..< content.LEVEL_COUNT {
		if l.tried[i] || !content.is_built(i) {
			continue
		}
		l.tried[i] = true
		g := &l.apart
		if _, failed := game.load_text(g, i, content.LEVELS[i].source).?; failed {
			return
		}
		render.scene_build(&l.apart_scene, g, game.level_allocator(g))
		render.scene_update(&l.apart_scene, g, 0)
		t := rl.LoadRenderTexture(THUMB_SIZE.x, THUMB_SIZE.y)
		rl.SetTextureFilter(t.texture, .BILINEAR)
		w, h := f32(THUMB_SIZE.x), f32(THUMB_SIZE.y)
		rl.BeginTextureMode(t)
		reset_canvas(w, h)
		rl.ClearBackground({5, 5, 15, 255})
		v := render.make_view(l.apart_scene.fit, w, h, g.angle, g.data.size, g.data.height, {})
		render.draw_world(&app.renderer, &l.apart_scene, g, v, 0)
		rl.EndTextureMode()
		l.thumbs[i] = t
		l.pictures[i] = t.texture
		return
	}
}

shutdown_levels :: proc(app: ^App) {
	l := &app.levels
	for t in l.thumbs {
		if t.id != 0 {
			rl.UnloadRenderTexture(t)
		}
	}
	game.destroy(&l.apart)
}
