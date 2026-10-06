// The look of each setting (`setting name` in the level file): the sky, the
// layered backdrop, the sea of clouds, the mist and the light on the stones.
// Night is the palace of voices under the moon; the others follow the acts.
package render

import "../level"

Look :: struct {
	// the sky: a gradient from the zenith to the horizon
	sky_top, sky_mid, sky_horizon: Vec3,
	// the sun or the moon: where (screen uv), how big, its disc and halo
	orb_pos:       Vec2,
	orb_radius:    f32,
	orb_color:     Vec3,
	halo_color:    Vec3,
	halo_width:    f32, // larger: a tighter halo
	stars:         f32, // 0 none .. 1 a full night sky
	haze:          Vec3, // drifting bands low in the sky
	islands:       bool, // the far floating ruins
	// the mountain ranges, far to near (none when ridges = 0)
	ridges:        f32,
	ridge_color:   [3]Vec3,
	ridge_rim:     Vec3, // light on the slopes facing the orb
	// the sea of clouds under the level: back and front layers, crests
	cloud_back:    Vec3,
	cloud_front:   Vec3,
	cloud_crest:   Vec3, // light on the crests (sunlight)
	mist:          Vec3, // the foot of the level sinks into it
	daylight:      f32, // stones: 0 moonlit palette .. 1 the low sun
	candles:       bool, // the candles on the walls are lit
	mote:          Color4,
}

LOOKS := [level.Setting]Look {
	.Night = {
		sky_top = {0.012, 0.015, 0.05},
		sky_mid = {0.046, 0.042, 0.115},
		sky_horizon = {0.08, 0.07, 0.18},
		orb_pos = {0.80, 0.2},
		orb_radius = 0.049,
		orb_color = {0.86, 0.88, 1.0},
		halo_color = {0.105, 0.115, 0.19},
		halo_width = 9,
		stars = 1,
		haze = {0.088, 0.088, 0.176},
		islands = true,
		cloud_back = {0.13, 0.13, 0.29},
		cloud_front = {0.19, 0.19, 0.38},
		mist = {0.07, 0.07, 0.17},
		daylight = 0,
		mote = {0.6, 0.7, 1.0, 0.5},
	},
	// Zephyr's crag: the sun sets behind far ranges, the crag stands over the clouds
	.Crag_Sunset = {
		sky_top = {0.10, 0.11, 0.30},
		sky_mid = {0.52, 0.30, 0.42},
		sky_horizon = {1.0, 0.62, 0.36},
		orb_pos = {0.76, 0.8},
		orb_radius = 0.042,
		orb_color = {1.0, 0.86, 0.6},
		halo_color = {0.75, 0.42, 0.2},
		halo_width = 5,
		stars = 0.25,
		haze = {0.42, 0.24, 0.30},
		islands = false,
		ridges = 1,
		ridge_color = {{0.62, 0.40, 0.50}, {0.40, 0.25, 0.38}, {0.24, 0.15, 0.26}},
		ridge_rim = {0.95, 0.55, 0.30},
		cloud_back = {0.60, 0.36, 0.44}, // its body (x 0.7) is the haze: no seam at the horizon
		cloud_front = {0.68, 0.46, 0.54},
		cloud_crest = {0.55, 0.30, 0.12},
		mist = {0.42, 0.28, 0.38},
		daylight = 1,
		mote = {1.0, 0.8, 0.5, 0.45},
	},
	// the palace of voices at twilight: the sun is gone, its last light low on
	// the clouds, the first stars, the moon rising; the candles are lit
	.Dusk = {
		sky_top = {0.035, 0.045, 0.15},
		sky_mid = {0.17, 0.13, 0.30},
		sky_horizon = {0.58, 0.33, 0.34},
		orb_pos = {0.80, 0.3},
		orb_radius = 0.03,
		orb_color = {0.78, 0.72, 0.74},
		halo_color = {0.14, 0.11, 0.2},
		halo_width = 8,
		stars = 0.5,
		haze = {0.30, 0.19, 0.30},
		islands = true,
		cloud_back = {0.30, 0.21, 0.36},
		cloud_front = {0.40, 0.28, 0.42},
		cloud_crest = {0.40, 0.20, 0.10},
		mist = {0.20, 0.14, 0.25},
		daylight = 0.4,
		candles = true,
		mote = {1.0, 0.82, 0.55, 0.4},
	},
}

look :: proc(s: level.Setting) -> ^Look {
	return &LOOKS[s]
}
