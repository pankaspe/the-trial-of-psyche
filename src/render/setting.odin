// The look of each setting (`setting name` in the level file): the sky, the
// layered backdrop, the sea of clouds, the mist and the light on the stones.
// Night is the palace of voices under the moon; the others follow the acts.
package render

import "core:math"

import "../fx"
import "../game"
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
	water:         Color4, // the river's surface (a = 0: the night's)
	glint:         Color4, // the light drifting on it
	daylight:      f32, // stones: 0 moonlit palette .. 1 the low sun
	candles:       bool, // the candles on the walls are lit
	gloom:         f32, // 0 .. 1: how much darker the stones are than under a clear moon
	moon_clouds:   f32, // 0 none .. 1 dark clouds drifting across the moon (they dim the stones)
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
	// the palace of voices by night, its candles lit for her
	.Night_Candles = {
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
		candles = true,
		mote = {0.9, 0.75, 0.6, 0.45},
	},
	// deep night in the palace of voices: candles out, clouds drifting across the moon
	.Deep_Night = {
		sky_top = {0.004, 0.006, 0.024},
		sky_mid = {0.022, 0.022, 0.066},
		sky_horizon = {0.04, 0.036, 0.1},
		orb_pos = {0.80, 0.2},
		orb_radius = 0.045,
		orb_color = {0.8, 0.83, 0.95},
		halo_color = {0.07, 0.08, 0.14},
		halo_width = 10,
		stars = 0.7,
		haze = {0.05, 0.05, 0.11},
		islands = true,
		cloud_back = {0.08, 0.08, 0.19},
		cloud_front = {0.12, 0.12, 0.25},
		mist = {0.04, 0.04, 0.11},
		daylight = 0,
		gloom = 0.4,
		moon_clouds = 1,
		mote = {0.55, 0.6, 0.9, 0.35},
	},
	// the dead of night in a forest of rock pillars: no palace in the sky, dark
	// wooded ranges, mist between the pillars, clouds across the moon, fireflies
	.Forest_Night = {
		sky_top = {0.004, 0.007, 0.022},
		sky_mid = {0.018, 0.026, 0.06},
		sky_horizon = {0.035, 0.05, 0.09},
		orb_pos = {0.78, 0.18},
		orb_radius = 0.04,
		orb_color = {0.82, 0.86, 0.95},
		halo_color = {0.06, 0.08, 0.13},
		halo_width = 10,
		stars = 0.8,
		haze = {0.04, 0.055, 0.09},
		islands = false,
		ridges = 1,
		ridge_color = {{0.05, 0.075, 0.11}, {0.035, 0.055, 0.075}, {0.02, 0.035, 0.045}},
		ridge_rim = {0.16, 0.2, 0.3},
		cloud_back = {0.06, 0.08, 0.13},
		cloud_front = {0.09, 0.115, 0.17},
		mist = {0.035, 0.05, 0.08},
		daylight = 0,
		gloom = 0.3,
		moon_clouds = 0.8,
		mote = {0.75, 0.95, 0.45, 0.6},
	},
	// dawn over Pan's river: the night withdrawing, a band of rose low in the
	// east, the morning star still bright, blue ranges, mist on the water
	.River_Dawn = {
		sky_top = {0.04, 0.06, 0.17},
		sky_mid = {0.20, 0.24, 0.42},
		sky_horizon = {0.86, 0.62, 0.55},
		orb_pos = {0.24, 0.52},
		orb_radius = 0.009,
		orb_color = {1.0, 0.97, 0.9},
		halo_color = {0.22, 0.22, 0.32},
		halo_width = 14,
		stars = 0.35,
		haze = {0.42, 0.36, 0.48},
		islands = false,
		ridges = 1,
		ridge_color = {{0.36, 0.38, 0.55}, {0.24, 0.27, 0.42}, {0.13, 0.17, 0.27}},
		ridge_rim = {0.9, 0.6, 0.5},
		cloud_back = {0.44, 0.42, 0.56},
		cloud_front = {0.55, 0.52, 0.64},
		cloud_crest = {0.45, 0.28, 0.2},
		mist = {0.30, 0.33, 0.46},
		water = {0.2, 0.25, 0.42, 0.85},
		glint = {1.0, 0.82, 0.72, 0.55},
		daylight = 0.45,
		mote = {1.0, 0.9, 0.75, 0.4},
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
	// the sisters' crag by day: a high clear sky, the sun to one side, blue
	// ranges far off, white clouds below; bare rock lit warm
	.Crag_Day = {
		sky_top = {0.16, 0.32, 0.62},
		sky_mid = {0.40, 0.58, 0.82},
		sky_horizon = {0.80, 0.86, 0.90},
		orb_pos = {0.22, 0.16},
		orb_radius = 0.03,
		orb_color = {1.0, 0.98, 0.9},
		halo_color = {0.55, 0.6, 0.62},
		halo_width = 4,
		stars = 0,
		haze = {0.70, 0.78, 0.86},
		islands = false,
		ridges = 1,
		ridge_color = {{0.56, 0.66, 0.80}, {0.42, 0.52, 0.66}, {0.30, 0.38, 0.48}},
		ridge_rim = {1.0, 0.94, 0.80},
		cloud_back = {0.80, 0.85, 0.92},
		cloud_front = {0.90, 0.92, 0.96},
		cloud_crest = {0.20, 0.18, 0.12},
		mist = {0.68, 0.75, 0.84},
		daylight = 1,
		mote = {1.0, 1.0, 0.95, 0.3},
	},
	// the temple of Ceres and Juno at dusk, among the ranges: the sun is gone,
	// a warm afterglow behind the far ridges, the first stars, a young moon;
	// mist over the sacred pool; the temple's candles are lit
	.Temple_Dusk = {
		sky_top = {0.03, 0.035, 0.12},
		sky_mid = {0.15, 0.11, 0.27},
		sky_horizon = {0.62, 0.33, 0.31},
		orb_pos = {0.24, 0.3},
		orb_radius = 0.026,
		orb_color = {0.95, 0.9, 0.8},
		halo_color = {0.14, 0.11, 0.2},
		halo_width = 9,
		stars = 0.55,
		haze = {0.30, 0.18, 0.28},
		islands = false,
		ridges = 1,
		ridge_color = {{0.30, 0.20, 0.34}, {0.18, 0.13, 0.25}, {0.09, 0.07, 0.15}},
		ridge_rim = {0.80, 0.45, 0.36},
		cloud_back = {0.30, 0.20, 0.34},
		cloud_front = {0.38, 0.26, 0.40},
		cloud_crest = {0.40, 0.20, 0.10},
		mist = {0.18, 0.13, 0.24},
		daylight = 0.35,
		candles = true,
		mote = {1.0, 0.82, 0.55, 0.42},
	},
	// the house of Venus above the clouds at evening: a rose sky, Venus's own
	// star bright over the far banks of cloud, the stones warm in the last
	// light, candles lit in her house
	.Venus_Evening = {
		sky_top = {0.07, 0.05, 0.20},
		sky_mid = {0.40, 0.23, 0.42},
		sky_horizon = {0.98, 0.66, 0.62},
		orb_pos = {0.25, 0.24},
		orb_radius = 0.0045,
		orb_color = {1.0, 0.97, 0.92},
		halo_color = {0.46, 0.30, 0.42},
		halo_width = 16,
		stars = 0.3,
		haze = {0.55, 0.32, 0.45},
		islands = false,
		ridges = 1,
		ridge_color = {{0.70, 0.50, 0.62}, {0.55, 0.38, 0.54}, {0.40, 0.26, 0.42}},
		ridge_rim = {1.0, 0.72, 0.62},
		cloud_back = {0.66, 0.44, 0.56},
		cloud_front = {0.78, 0.56, 0.64},
		cloud_crest = {0.52, 0.28, 0.20},
		mist = {0.46, 0.30, 0.44},
		water = {0.30, 0.22, 0.42, 0.85},
		glint = {1.0, 0.82, 0.86, 0.55},
		daylight = 0.8,
		candles = true,
		mote = {1.0, 0.76, 0.82, 0.45},
	},
	// the Sun's pastures at noon: a high hot sky, the sun overhead, green-blue
	// ranges in the haze, white clouds gilded below; pollen drifting
	.Pasture_Day = {
		sky_top = {0.18, 0.36, 0.68},
		sky_mid = {0.46, 0.62, 0.84},
		sky_horizon = {0.93, 0.89, 0.78},
		orb_pos = {0.72, 0.13},
		orb_radius = 0.034,
		orb_color = {1.0, 0.98, 0.88},
		halo_color = {0.72, 0.64, 0.46},
		halo_width = 4,
		stars = 0,
		haze = {0.82, 0.82, 0.74},
		islands = false,
		ridges = 1,
		ridge_color = {{0.60, 0.68, 0.66}, {0.46, 0.56, 0.48}, {0.33, 0.43, 0.32}},
		ridge_rim = {1.0, 0.93, 0.72},
		cloud_back = {0.86, 0.85, 0.82},
		cloud_front = {0.94, 0.93, 0.89},
		cloud_crest = {0.24, 0.19, 0.08},
		mist = {0.76, 0.78, 0.72},
		water = {0.24, 0.46, 0.60, 0.85},
		glint = {1.0, 0.96, 0.78, 0.6},
		daylight = 1,
		mote = {1.0, 0.94, 0.6, 0.35},
	},
	// the same at evening: the sun low on the far ranges, amber and violet, the
	// first stars; the rams' fleece burns gold in the last light
	.Pasture_Evening = {
		sky_top = {0.08, 0.08, 0.24},
		sky_mid = {0.44, 0.27, 0.42},
		sky_horizon = {1.0, 0.60, 0.34},
		orb_pos = {0.74, 0.78},
		orb_radius = 0.046,
		orb_color = {1.0, 0.82, 0.52},
		halo_color = {0.78, 0.40, 0.18},
		halo_width = 5,
		stars = 0.3,
		haze = {0.44, 0.26, 0.32},
		islands = false,
		ridges = 1,
		ridge_color = {{0.56, 0.38, 0.48}, {0.38, 0.25, 0.37}, {0.22, 0.15, 0.25}},
		ridge_rim = {0.98, 0.56, 0.30},
		cloud_back = {0.60, 0.38, 0.46},
		cloud_front = {0.70, 0.48, 0.54},
		cloud_crest = {0.58, 0.30, 0.12},
		mist = {0.42, 0.29, 0.39},
		water = {0.30, 0.24, 0.40, 0.85},
		glint = {1.0, 0.76, 0.52, 0.6},
		daylight = 0.9,
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

// The night clouds of sky.fs, as they cover the moon's centre at `time`
// (`angle`: the view turn, which pans the sky).
MOON_CLOUDS :: 3
@(private = "file")
C_SPEED := [MOON_CLOUDS]f32{0.009, 0.007, 0.011}
@(private = "file")
C_PHASE := [MOON_CLOUDS]f32{0.10, 0.55, 0.85}
@(private = "file")
C_DY := [MOON_CLOUDS]f32{0.0, -0.02, 0.025}
@(private = "file")
C_W := [MOON_CLOUDS]f32{0.22, 0.17, 0.2}
@(private = "file")
C_H := [MOON_CLOUDS]f32{0.07, 0.06, 0.075}
@(private = "file")
LOBE := [3][2]f32{{-0.55, 0.15}, {0.0, -0.3}, {0.5, 0.1}}
@(private = "file")
LOBE_S := [3]f32{0.7, 1.0, 0.75}

moon_cover :: proc(lk: ^Look, time, angle, aspect: f32) -> f32 {
	if lk.moon_clouds <= 0 {
		return 0
	}
	shift := angle
	mx := lk.orb_pos.x - shift * 0.03
	cover: f32 = 0
	for i in 0 ..< MOON_CLOUDS {
		t := C_PHASE[i] + time * C_SPEED[i]
		cx := (t - math.floor(t)) * 1.9 - 0.45 - shift * 0.03
		for l, j in LOBE {
			ox := cx + l.x * C_W[i] / aspect
			oy := C_DY[i] + l.y * C_H[i] // relative to the moon
			ex := (mx - ox) * aspect / (C_W[i] * LOBE_S[j])
			ey := -oy / (C_H[i] * LOBE_S[j])
			e := ex * ex + ey * ey
			u := clamp((1.0 - e) / 0.75, 0, 1)
			cover = max(cover, u * u * (3 - 2 * u))
		}
	}
	return cover * lk.moon_clouds * 0.93
}

look :: proc(s: level.Setting) -> ^Look {
	return &LOOKS[s]
}

// The look of the level now: in a level that turns between day and evening,
// the two settings blended as the sun goes down (or comes up).
look_of :: proc(g: ^game.Game) -> ^Look {
	if !game.has_time(g) {
		return &LOOKS[g.data.setting]
	}
	@(static) blended: Look
	blended = blend(LOOKS[g.data.setting], LOOKS[g.data.evening], fx.sine_in_out(g.evening))
	return &blended
}

// Two looks mixed: t = 0 is a, 1 is b (the switches flip half way).
blend :: proc(a, b: Look, t: f32) -> (o: Look) {
	mix3 :: proc(x, y: Vec3, t: f32) -> Vec3 {return x + (y - x) * t}
	mix4 :: proc(x, y: Color4, t: f32) -> Color4 {return x + (y - x) * t}
	mixf :: proc(x, y: f32, t: f32) -> f32 {return x + (y - x) * t}
	o = t < 0.5 ? a : b
	o.sky_top = mix3(a.sky_top, b.sky_top, t)
	o.sky_mid = mix3(a.sky_mid, b.sky_mid, t)
	o.sky_horizon = mix3(a.sky_horizon, b.sky_horizon, t)
	o.orb_pos = a.orb_pos + (b.orb_pos - a.orb_pos) * t
	o.orb_radius = mixf(a.orb_radius, b.orb_radius, t)
	o.orb_color = mix3(a.orb_color, b.orb_color, t)
	o.halo_color = mix3(a.halo_color, b.halo_color, t)
	o.halo_width = mixf(a.halo_width, b.halo_width, t)
	o.stars = mixf(a.stars, b.stars, t)
	o.haze = mix3(a.haze, b.haze, t)
	o.ridges = mixf(a.ridges, b.ridges, t)
	for k in 0 ..< 3 {
		o.ridge_color[k] = mix3(a.ridge_color[k], b.ridge_color[k], t)
	}
	o.ridge_rim = mix3(a.ridge_rim, b.ridge_rim, t)
	o.cloud_back = mix3(a.cloud_back, b.cloud_back, t)
	o.cloud_front = mix3(a.cloud_front, b.cloud_front, t)
	o.cloud_crest = mix3(a.cloud_crest, b.cloud_crest, t)
	o.mist = mix3(a.mist, b.mist, t)
	o.water = mix4(a.water, b.water, t)
	o.glint = mix4(a.glint, b.glint, t)
	o.daylight = mixf(a.daylight, b.daylight, t)
	o.gloom = mixf(a.gloom, b.gloom, t)
	o.moon_clouds = mixf(a.moon_clouds, b.moon_clouds, t)
	o.mote = mix4(a.mote, b.mote, t)
	return
}
