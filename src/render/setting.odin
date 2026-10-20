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
	day_clouds:    f32, // 0 none .. 1 white clouds drifting across the sun (they dim the stones a little)
	morning:       f32, // 0 .. 1: by day, the stones in the morning light (cool shade, warm sun, pale tops)
	birds:         Birds, // flying far off in the sky (never with reduce motion)
	rock:          Vec3, // the living rock's tint (zero: its own earth colours)
	mote:          Color4,
}

// The birds of a sky (sky.fs `birds`): 1 swallows darting in a loose band,
// 2 white doves flying slowly in a flock, 3 a raptor circling high.
Birds :: enum u8 {
	None,
	Swallows,
	Doves,
	Raptor,
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
	.Night_Candles = {}, // the night with its candles lit: see night_candles
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
		water = {0.30, 0.24, 0.40, 0.85}, // the spring on the crag: the sunset in it
		glint = {1.0, 0.76, 0.52, 0.6},
		daylight = 1,
		mote = {1.0, 0.8, 0.5, 0.45},
	},
	// the sisters' crag by day: a clear morning sky, the sun to one side, white
	// clouds drifting by, swallows; blue ranges far off; bare rock lit warm
	.Crag_Day = {
		sky_top = {0.12, 0.30, 0.64},
		sky_mid = {0.36, 0.56, 0.84},
		sky_horizon = {0.80, 0.86, 0.90},
		orb_pos = {0.22, 0.3},
		orb_radius = 0.03,
		orb_color = {1.0, 0.98, 0.9},
		halo_color = {0.62, 0.58, 0.50},
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
		water = {0.20, 0.42, 0.60, 0.88}, // the sea at the foot of the crag
		glint = {1.0, 0.98, 0.88, 0.6},
		daylight = 1,
		mote = {1.0, 1.0, 0.95, 0.3},
		morning = 1,
		day_clouds = 1,
		birds = .Swallows,
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
	// the Sun's pastures in the morning: a deep blue sky, the sun still low, white
	// clouds drifting across it, swallows; green-blue ranges in the haze; pollen
	.Pasture_Day = {
		sky_top = {0.13, 0.33, 0.70},
		sky_mid = {0.40, 0.60, 0.88},
		sky_horizon = {0.93, 0.89, 0.78},
		orb_pos = {0.72, 0.3},
		orb_radius = 0.034,
		orb_color = {1.0, 0.98, 0.88},
		halo_color = {0.76, 0.62, 0.42},
		halo_width = 4,
		stars = 0,
		haze = {0.70, 0.72, 0.66},
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
		morning = 1,
		day_clouds = 1,
		birds = .Swallows,
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
	// the house of Venus in the morning: a blue sky warming to rose low down, the
	// sun in a soft halo, white clouds drifting, her doves; her candles out
	.Venus_Day = {
		sky_top = {0.20, 0.36, 0.72},
		sky_mid = {0.52, 0.62, 0.88},
		sky_horizon = {1.0, 0.86, 0.80},
		orb_pos = {0.28, 0.3},
		orb_radius = 0.03,
		orb_color = {1.0, 0.97, 0.90},
		halo_color = {0.84, 0.64, 0.58},
		halo_width = 4,
		stars = 0,
		haze = {0.80, 0.72, 0.76},
		islands = false,
		ridges = 1,
		ridge_color = {{0.76, 0.70, 0.80}, {0.64, 0.56, 0.70}, {0.52, 0.44, 0.60}},
		ridge_rim = {1.0, 0.92, 0.84},
		cloud_back = {0.90, 0.84, 0.88},
		cloud_front = {0.97, 0.92, 0.93},
		cloud_crest = {0.20, 0.14, 0.12},
		mist = {0.84, 0.78, 0.84},
		water = {0.34, 0.48, 0.66, 0.85},
		glint = {1.0, 0.94, 0.90, 0.6},
		daylight = 1,
		mote = {1.0, 0.86, 0.90, 0.4},
		morning = 1,
		day_clouds = 1,
		birds = .Doves,
	},
	// the gorge under the Styx's crag: no moon at all, a few cold stars, black
	// peaks against a sky barely lighter than they are, the black water below;
	// only her own light and the lamp's show the stones
	.Styx_Night = {
		sky_top = {0.003, 0.004, 0.014},
		sky_mid = {0.012, 0.013, 0.04},
		sky_horizon = {0.03, 0.028, 0.07},
		orb_pos = {0.80, 0.2},
		orb_radius = 0,
		orb_color = {0, 0, 0},
		halo_color = {0, 0, 0},
		halo_width = 10,
		stars = 0.55,
		haze = {0.03, 0.03, 0.07},
		islands = false,
		ridges = 1,
		ridge_color = {{0.03, 0.035, 0.07}, {0.018, 0.022, 0.048}, {0.008, 0.01, 0.024}},
		ridge_rim = {0.08, 0.09, 0.16},
		cloud_back = {0.04, 0.04, 0.09},
		cloud_front = {0.06, 0.06, 0.12},
		mist = {0.025, 0.025, 0.06},
		water = {0.03, 0.03, 0.06, 0.92},
		glint = {0.55, 0.6, 0.85, 0.18},
		daylight = 0,
		gloom = 0.6,
		mote = {0.55, 0.6, 0.9, 0.3},
	},
	// the summit of the Styx's crag by day: a pale blue sky, a small white sun,
	// a few clouds, a raptor circling; grey-blue peaks, the black water still black
	.Styx_Day = {
		sky_top = {0.18, 0.28, 0.52},
		sky_mid = {0.48, 0.56, 0.72},
		sky_horizon = {0.86, 0.84, 0.80},
		orb_pos = {0.30, 0.28},
		orb_radius = 0.026,
		orb_color = {1.0, 1.0, 0.96},
		halo_color = {0.70, 0.70, 0.66},
		halo_width = 3,
		stars = 0,
		haze = {0.74, 0.74, 0.72},
		islands = false,
		ridges = 1,
		ridge_color = {{0.46, 0.50, 0.58}, {0.32, 0.35, 0.43}, {0.20, 0.22, 0.28}},
		ridge_rim = {1.0, 0.96, 0.86},
		cloud_back = {0.78, 0.78, 0.78},
		cloud_front = {0.88, 0.88, 0.87},
		cloud_crest = {0.18, 0.16, 0.12},
		mist = {0.62, 0.64, 0.68},
		water = {0.04, 0.05, 0.08, 0.94},
		glint = {1.0, 1.0, 0.94, 0.5},
		daylight = 1,
		rock = {0.46, 0.48, 0.56},
		mote = {1.0, 1.0, 0.9, 0.25},
		morning = 1,
		day_clouds = 0.6,
		birds = .Raptor,
	},
	// the same at evening: the sun low and red behind the far peaks, the sky
	// darkening to violet above, the crags black against the glow
	.Styx_Evening = {
		sky_top = {0.04, 0.03, 0.10},
		sky_mid = {0.24, 0.10, 0.18},
		sky_horizon = {0.78, 0.30, 0.18},
		orb_pos = {0.70, 0.80},
		orb_radius = 0.05,
		orb_color = {1.0, 0.56, 0.34},
		halo_color = {0.62, 0.20, 0.10},
		halo_width = 5,
		stars = 0.35,
		haze = {0.30, 0.12, 0.16},
		islands = false,
		ridges = 1,
		ridge_color = {{0.22, 0.10, 0.14}, {0.12, 0.06, 0.10}, {0.05, 0.03, 0.06}},
		ridge_rim = {0.90, 0.38, 0.20},
		cloud_back = {0.30, 0.13, 0.17},
		cloud_front = {0.40, 0.18, 0.20},
		cloud_crest = {0.60, 0.24, 0.10},
		mist = {0.18, 0.08, 0.12},
		water = {0.03, 0.02, 0.04, 0.94},
		glint = {1.0, 0.50, 0.30, 0.45},
		daylight = 0.75,
		gloom = 0.25,
		rock = {0.62, 0.50, 0.56},
		mote = {1.0, 0.6, 0.4, 0.35},
	},
	// the top of the high tower at dusk (IV.1): the sun gone, the sky still
	// rose above, but low down a red glow comes up from the south, where the
	// way to the underworld opens; the first stars, the ranges violet
	.Tower_Dusk = {
		sky_top = {0.06, 0.04, 0.16},
		sky_mid = {0.34, 0.16, 0.30},
		sky_horizon = {0.92, 0.40, 0.30},
		orb_pos = {0.74, 0.22},
		orb_radius = 0.004,
		orb_color = {1.0, 0.95, 0.9},
		halo_color = {0.36, 0.16, 0.26},
		halo_width = 16,
		stars = 0.4,
		haze = {0.48, 0.20, 0.30},
		islands = false,
		ridges = 1,
		ridge_color = {{0.50, 0.26, 0.40}, {0.34, 0.17, 0.30}, {0.20, 0.10, 0.20}},
		ridge_rim = {0.98, 0.50, 0.36},
		cloud_back = {0.52, 0.26, 0.36},
		cloud_front = {0.62, 0.34, 0.42},
		cloud_crest = {0.60, 0.24, 0.14},
		mist = {0.34, 0.16, 0.28},
		water = {0.10, 0.05, 0.10, 0.9},
		glint = {1.0, 0.56, 0.42, 0.45},
		daylight = 0.6,
		rock = {0.66, 0.54, 0.58},
		candles = true,
		mote = {1.0, 0.66, 0.52, 0.4},
	},
	// the foot of Taenarus, the mouth of the underworld: a sky of red embers
	// under a pall of ash, a dull sun sunk in it, black crags, a red mist on
	// the dark water where Charon waits; down here the stones are dark, the
	// candelabra light them
	.Taenarus = {
		sky_top = {0.10, 0.02, 0.03},
		sky_mid = {0.36, 0.07, 0.06},
		sky_horizon = {0.80, 0.24, 0.10},
		orb_pos = {0.30, 0.66},
		orb_radius = 0.06,
		orb_color = {0.95, 0.36, 0.16},
		halo_color = {0.55, 0.12, 0.06},
		halo_width = 4,
		stars = 0,
		haze = {0.42, 0.12, 0.08},
		islands = false,
		ridges = 1,
		ridge_color = {{0.30, 0.09, 0.08}, {0.17, 0.05, 0.06}, {0.07, 0.02, 0.03}},
		ridge_rim = {0.95, 0.34, 0.14},
		cloud_back = {0.36, 0.10, 0.08},
		cloud_front = {0.46, 0.15, 0.10},
		cloud_crest = {0.60, 0.20, 0.06},
		mist = {0.26, 0.06, 0.06},
		water = {0.05, 0.015, 0.02, 0.94},
		glint = {1.0, 0.40, 0.20, 0.5},
		daylight = 0.5,
		gloom = 0.3,
		rock = {0.52, 0.40, 0.40},
		candles = true,
		mote = {1.0, 0.45, 0.25, 0.45},
	},
	// the land of the dead by night: the ash has swallowed the sun, a cold pale
	// moon, a few stars, embers glowing low on the horizon behind black crags;
	// the candles lit
	.Taenarus_Night = {
		sky_top = {0.012, 0.008, 0.02},
		sky_mid = {0.06, 0.025, 0.04},
		sky_horizon = {0.34, 0.09, 0.06},
		orb_pos = {0.72, 0.22},
		orb_radius = 0.018,
		orb_color = {0.80, 0.76, 0.72},
		halo_color = {0.12, 0.06, 0.06},
		halo_width = 5,
		stars = 0.35,
		haze = {0.16, 0.05, 0.05},
		islands = false,
		ridges = 1,
		ridge_color = {{0.14, 0.05, 0.06}, {0.08, 0.03, 0.04}, {0.035, 0.012, 0.02}},
		ridge_rim = {0.70, 0.22, 0.10},
		cloud_back = {0.14, 0.05, 0.05},
		cloud_front = {0.20, 0.07, 0.06},
		cloud_crest = {0.40, 0.12, 0.05},
		mist = {0.10, 0.03, 0.04},
		water = {0.03, 0.01, 0.02, 0.94},
		glint = {0.90, 0.72, 0.62, 0.4},
		daylight = 0.32,
		gloom = 0.3,
		rock = {0.56, 0.46, 0.48},
		candles = true,
		mote = {1.0, 0.45, 0.25, 0.4},
	},
	// Proserpina's kingdom, under the land of the dead (the world turned over):
	// a still violet dark, the pale sun of the dead low and cold, no stars to
	// speak of, lilac mist; the candles lit
	.Dis = {
		sky_top = {0.02, 0.014, 0.05},
		sky_mid = {0.09, 0.06, 0.16},
		sky_horizon = {0.30, 0.20, 0.36},
		orb_pos = {0.70, 0.26},
		orb_radius = 0.035,
		orb_color = {0.82, 0.76, 0.96},
		halo_color = {0.17, 0.11, 0.26},
		halo_width = 8,
		stars = 0.25,
		haze = {0.20, 0.14, 0.28},
		islands = false,
		ridges = 1,
		ridge_color = {{0.17, 0.12, 0.25}, {0.10, 0.07, 0.17}, {0.05, 0.035, 0.09}},
		ridge_rim = {0.62, 0.50, 0.82},
		cloud_back = {0.16, 0.11, 0.24},
		cloud_front = {0.22, 0.16, 0.30},
		cloud_crest = {0.30, 0.20, 0.40},
		mist = {0.12, 0.08, 0.18},
		water = {0.04, 0.03, 0.08, 0.92},
		glint = {0.8, 0.7, 1.0, 0.4},
		daylight = 0.25,
		gloom = 0.15,
		rock = {0.78, 0.72, 0.90},
		candles = true,
		mote = {0.85, 0.75, 1.0, 0.45},
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

// The clouds of sky.fs (by night or by day), as they cover the orb's centre at `time`
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

orb_cover :: proc(lk: ^Look, time, angle, aspect: f32) -> f32 {
	if lk.moon_clouds <= 0 && lk.day_clouds <= 0 {
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
	return cover * 0.93
}

// The palace of voices by night, its candles lit for her: the night's look,
// the candles burning, the motes warm.
@(init, private)
night_candles :: proc "contextless" () {
	LOOKS[.Night_Candles] = LOOKS[.Night]
	LOOKS[.Night_Candles].candles = true
	LOOKS[.Night_Candles].mote = {0.9, 0.75, 0.6, 0.45}
}

look :: proc(s: level.Setting) -> ^Look {
	return &LOOKS[s]
}

// The look of the level now: in a level that turns between day and evening,
// the two settings blended as the sun goes down (or comes up); in a level
// that goes down, the look at its foot blended in as she descends.
look_of :: proc(g: ^game.Game) -> ^Look {
	@(static) blended: Look
	switch {
	case game.has_time(g):
		blended = blend(LOOKS[g.data.setting], LOOKS[g.data.evening], fx.sine_in_out(g.evening))
	case g.data.has_below:
		blended = blend(LOOKS[g.data.setting], LOOKS[g.data.below], fx.sine_in_out(g.descent))
	case g.data.has_upside:
		blended = blend(LOOKS[g.data.setting], LOOKS[g.data.upside], fx.sine_in_out(g.overturn))
	case:
		return &LOOKS[g.data.setting]
	}
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
	o.day_clouds = mixf(a.day_clouds, b.day_clouds, t)
	o.morning = mixf(a.morning, b.morning, t)
	o.rock = mix3(a.rock, b.rock, t)
	o.mote = mix4(a.mote, b.mote, t)
	return
}
