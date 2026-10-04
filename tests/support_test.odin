// Settings files, synthesised audio and the camera projection.
package tests

import "core:math"
import "core:testing"

import "../src/audio"
import "../src/fx"
import "../src/i18n"
import "../src/iso"
import "../src/render"
import "../src/settings"

@(test)
settings_round_trip :: proc(t: ^testing.T) {
	s := settings.defaults()
	s.language = .English
	s.fullscreen = true
	s.resolution = {1920, 1080}
	s.fps_limit = 144
	s.music = 0.25
	text := settings.serialize(s, context.temp_allocator)
	back := settings.defaults()
	back.language = .Italian
	settings.parse(text, &back)
	testing.expectf(t, back == s, "settings survive a save and a load:\n%v\n%v", s, back)
}

@(test)
settings_ignore_bad_values :: proc(t: ^testing.T) {
	s := settings.defaults()
	before := s
	settings.parse("resolution = 12x5\nmusic = loud\nfps_limit = -3\nnonsense\nlanguage = xx\nmaster = 7\n", &s)
	before.master = 1 // clamped to 0..1
	testing.expect(t, s == before, "malformed lines keep the previous values")
	testing.expect(t, i18n.language_from_locale("it_IT.UTF-8") == .Italian, "Italian locale")
	testing.expect(t, i18n.language_from_locale("C") == .English, "English otherwise")
}

@(test)
synthesised_sounds_are_sane :: proc(t: ^testing.T) {
	rng := fx.rng_init(7)
	for id in audio.Sound_Id {
		dry := audio.synthesize(id, &rng, context.temp_allocator)
		wet := audio.reverb(dry, audio.SFX_REVERB, 1.2, false, context.temp_allocator)
		testing.expectf(t, len(dry) > 0 && len(wet) > len(dry), "%v has samples and a reverb tail", id)
		peak: f32 = 0
		for s in wet {
			if math.is_nan(s) || math.is_inf(s) {
				testing.expectf(t, false, "%v has a non-finite sample", id)
				break
			}
			peak = max(peak, abs(s))
		}
		testing.expectf(t, peak > 0.01 && peak < 4, "%v peak %v is audible and bounded", id, peak)
	}
	loop := audio.reverb(audio.music(true, &rng, context.temp_allocator), audio.MUSIC_REVERB, 0, true, context.temp_allocator)
	testing.expect(t, len(loop) == 8 * audio.RATE, "a looped reverb keeps the loop length")
	wav := audio.wav_file(loop[:100], context.temp_allocator)
	testing.expect(t, len(wav) == 44 + 200 && string(wav[:4]) == "RIFF" && string(wav[8:12]) == "WAVE", "WAV header")
}

// The GPU matrix must put every world point exactly where the 2D formula
// (used for picking) says, in every view and mid-turn.
@(test)
projection_matches_picking :: proc(t: ^testing.T) {
	fit := render.Rect{-700, -500, 1400, 1000}
	for angle in ([6]f32{0, 0.37, 1, 2, 2.5, 3}) {
		v := render.make_view(fit, 1600, 900, angle, 12, 9, {3, -2})
		m := render.clip_matrix(v)
		for p in ([4]iso.Vec3{{0, 0, 0}, {5.5, 6.5, 2}, {11, 3, 7}, {2.25, 9.75, 4.5}}) {
			clip := m * [4]f32{p.x, p.y, p.z, 1}
			screen := iso.Vec2{(clip.x + 1) * 0.5 * v.width, (1 - clip.y) * 0.5 * v.height}
			want := render.world_to_screen(v, p)
			d := screen - want
			testing.expectf(t, d.x * d.x + d.y * d.y < 1e-4, "angle %v, point %v: matrix %v vs formula %v", angle, p, screen, want)
			testing.expectf(t, clip.z > -1 && clip.z < 1, "angle %v, point %v: depth %v in range", angle, p, clip.z)
		}
		// nearer points (larger x'+y'+z') must get smaller depth
		near := m * [4]f32{6, 6, 3, 1}
		far := m * [4]f32{6, 6, 2, 1}
		testing.expect(t, near.z < far.z, "depth grows away from the camera")
		// billboard axes: one proto pixel right / up on screen, no depth change
		right, up := render.billboard_axes(v)
		o := render.world_to_proto(v, {6, 6, 2})
		r := render.world_to_proto(v, iso.Vec3{6, 6, 2} + right) - o
		u := render.world_to_proto(v, iso.Vec3{6, 6, 2} + up) - o
		testing.expectf(t, abs(r.x - 1) < 1e-3 && abs(r.y) < 1e-3, "right axis %v", r)
		testing.expectf(t, abs(u.x) < 1e-3 && abs(u.y + 1) < 1e-3, "up axis %v", u)
	}
}
