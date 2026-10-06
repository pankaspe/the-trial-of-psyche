// Settings files, synthesised audio and the camera projection.
package tests

import "core:fmt"
import "core:math"
import "core:testing"

import "../src/audio"
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
	s.look = .Painted
	s.look_amount = 0.5
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
	settings.parse("resolution = 12x5\nmusic = loud\nfps_limit = -3\nnonsense\nlanguage = xx\nmaster = 7\nlook = sepia\n", &s)
	before.master = 1 // clamped to 0..1
	testing.expect(t, s == before, "malformed lines keep the previous values")
	testing.expect(t, i18n.language_from_locale("it_IT.UTF-8") == .Italian, "Italian locale")
	testing.expect(t, i18n.language_from_locale("C") == .English, "English otherwise")
}

@(test)
synthesised_sounds_are_sane :: proc(t: ^testing.T) {
	for id in audio.Sound_Id {
		for v in 0 ..< max(audio.VARIANTS[id], 1) {
			b := audio.synthesize(id, v, context.temp_allocator)
			testing.expectf(t, len(b) > 0, "%v has samples", id)
			check_samples(t, b, fmt.tprint(id))
		}
	}
	for bed in audio.Bed {
		b := audio.synthesize_bed(bed, context.temp_allocator)
		if bed == .None {
			testing.expect(t, b == nil, "no bed, no samples")
			continue
		}
		testing.expectf(t, len(b) == 2 * audio.BED_SECONDS * audio.RATE, "%v is a stereo loop of the bed's length", bed)
		check_samples(t, b, fmt.tprint(bed))
		// seamless: the wrap is no louder a step than the samples around it
		jump := abs(b[0] - b[len(b) - 2])
		testing.expectf(t, jump < 0.05, "%v loops without a click (jump %v)", bed, jump)
	}
	for info, track in audio.TRACKS {
		if track == .None {
			continue
		}
		testing.expectf(t, len(info.data) > 0 && string(info.data[:4]) == "OggS", "%v is an embedded OGG", track)
		testing.expectf(t, info.loop_to > 0 && info.loop_to < info.loop_from, "%v jumps back from A to an earlier B", track)
	}
}

check_samples :: proc(t: ^testing.T, b: []f32, name: string) {
	peak: f32 = 0
	for s in b {
		if math.is_nan(s) || math.is_inf(s) {
			testing.expectf(t, false, "%s has a non-finite sample", name)
			return
		}
		peak = max(peak, abs(s))
	}
	testing.expectf(t, peak > 0.005 && peak < 1.5, "%s peak %v is audible and bounded", name, peak)
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
