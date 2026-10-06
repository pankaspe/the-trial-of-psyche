// The bed under the game: the act's music and the ambience of the place,
// mixed on the audio thread into one stereo stream.
//
// The act's music is generative (generative.odin): a mood per act, played
// live; changing mood fades one generator out and the next in. Recorded
// soundtracks can play instead (set_track): the player below.
//
// Soundtracks are OGG files embedded at compile time (assets/music, prepared
// by tools/music_prep.sh) and decoded while they play. A track is shorter
// than an act: when it reaches its loop point A it crossfades into the same
// track at the earlier point B, where the music sounds the same (found by
// tools/music_loop), so it never seems to start again. Changing track fades
// the old one out and the new one in.
// In the dark, in levels where Psyche carries the lamp, the music is veiled
// (low-passed, a little quieter); her light opens it. Cards and menus duck it.
// Ambience beds are seamless loops synthesised at startup (synth.odin).
package audio

import "base:runtime"
import "core:c"
import "core:math"
import "core:sync"
import rl "vendor:raylib"

MUSIC_RATE :: 44100
CROSSFADE_S :: 1.5 // the jump from A back to B
TRACK_FADE_IN_S :: 2.0
TRACK_FADE_OUT_S :: 2.5
MOOD_FADE_S :: 4.0
GEN_TRIM :: 2.0 // the generators are quieter than mastered tracks (+6 dB)
BED_FADE_S :: 2.0

Track :: enum u8 {
	None,
	Suspended_Light,
	Fragile_Light,
	Midway_Through,
	Sombras_De_Cristal,
}

Track_Info :: struct {
	data:      []u8,
	loop_from: int, // A: where the jump starts (samples at 44100)
	loop_to:   int, // B: where it lands
}

// Loop points from tools/music_prep.sh (the best pair of each track).
TRACKS := [Track]Track_Info {
	.None               = {},
	.Suspended_Light    = {#load("../../assets/music/suspended_light.ogg"), 8392704, 2856064},
	.Fragile_Light      = {#load("../../assets/music/fragile_light.ogg"), 8415232, 3787776},
	.Midway_Through     = {#load("../../assets/music/midway_through.ogg"), 8257536, 3673728},
	.Sombras_De_Cristal = {#load("../../assets/music/sombras_de_cristal.ogg"), 7890944, 2618368},
}

// stb_vorbis comes with raylib (it decodes raylib's own OGG music), so the
// game links it from there.
@(private)
Vorbis :: struct {}

when ODIN_OS == .Windows {
	foreign import vorbis_lib "vendor:raylib/windows/raylib.lib"
} else when ODIN_OS == .Darwin {
	foreign import vorbis_lib "vendor:raylib/macos/libraylib.a"
} else {
	foreign import vorbis_lib "vendor:raylib/linux/libraylib.a"
}

@(private, default_calling_convention = "c", link_prefix = "stb_vorbis_")
foreign vorbis_lib {
	open_memory :: proc(data: [^]u8, len: c.int, error: ^c.int, alloc_buffer: rawptr) -> ^Vorbis ---
	close :: proc(f: ^Vorbis) ---
	seek :: proc(f: ^Vorbis, sample_number: c.uint) -> c.int ---
	get_samples_float_interleaved :: proc(f: ^Vorbis, channels: c.int, buffer: [^]f32, num_floats: c.int) -> c.int ---
}

@(private)
Voice :: struct {
	dec:      ^Vorbis,
	track:    Track,
	pos:      int, // next sample to decode
	fade:     f32, // 0..1, heard as sin(fade * pi/2): equal-power crossfades
	target:   f32,
	step:     f32, // fade change per sample
	spawned:  bool, // its loop jump has started
}

@(private)
Bed_Voice :: struct {
	bed:    Bed,
	pos:    int,
	fade:   f32,
	target: f32,
}

BLOCK :: 4096 // frames per callback at most

@(private)
Mixer :: struct {
	lock:       sync.Mutex,
	// asked by the game (under lock)
	want_track: Track,
	want_mood:  Mood_Id,
	want_bed:   Bed,
	music_gain: f32,
	bed_gain:   f32,
	duck:       f32,
	veil:       f32,
	skip:       bool, // debug: jump to a few seconds before the loop point
	// audio thread only
	track:      Track,
	bed:        Bed,
	voices:     [3]Voice,
	mood:       Mood_Id,
	gens:       [2]Generator,
	gen_mood:   [2]Mood_Id,
	gen_fade:   [2]f32,
	gen_target: [2]f32,
	beds:       [2]Bed_Voice,
	duck_now:   f32,
	veil_now:   f32,
	lp:         [2][2]f32, // two one-pole stages per channel
	scratch:    [BLOCK * 2]f32,
	stream:     rl.AudioStream,
	running:    bool,
}

@(private)
mx: Mixer

@(private)
mixer_start :: proc() {
	mx.music_gain, mx.bed_gain = 0, 0
	rl.SetAudioStreamBufferSizeDefault(BLOCK)
	mx.stream = rl.LoadAudioStream(MUSIC_RATE, 32, 2)
	rl.SetAudioStreamCallback(mx.stream, mix_callback)
	rl.PlayAudioStream(mx.stream)
	mx.running = true
}

@(private)
mixer_stop :: proc() {
	if !mx.running {
		return
	}
	rl.StopAudioStream(mx.stream)
	rl.UnloadAudioStream(mx.stream)
	for &v in mx.voices {
		if v.dec != nil {
			close(v.dec)
		}
	}
	mx = {}
}

// The act soundtrack (.None fades it out).
set_track :: proc(t: Track) {
	sync.guard(&mx.lock)
	mx.want_track = t
}

// The act's generative music (.None fades it out).
set_mood :: proc(m: Mood_Id) {
	sync.guard(&mx.lock)
	mx.want_mood = m
}

// The ambience of the place.
set_bed :: proc(b: Bed) {
	sync.guard(&mx.lock)
	mx.want_bed = b
}

// 0: the music as it is; 1: under a card or a menu.
set_duck :: proc(amount: f32) {
	sync.guard(&mx.lock)
	mx.duck = amount
}

// 0: open; 1: Psyche in the dark with the lamp out.
set_veil :: proc(amount: f32) {
	sync.guard(&mx.lock)
	mx.veil = amount
}

// Debug: hear the loop jump now (a few seconds before it).
skip_to_loop :: proc() {
	sync.guard(&mx.lock)
	mx.skip = true
}

@(private)
mixer_gains :: proc(music, bed: f32) {
	sync.guard(&mx.lock)
	mx.music_gain, mx.bed_gain = music, bed
}

@(private)
open_voice :: proc(t: Track, at: int, fade, target: f32, seconds: f32) -> bool {
	for &v in mx.voices {
		if v.dec != nil {
			continue
		}
		info := TRACKS[t]
		err: c.int
		dec := open_memory(raw_data(info.data), c.int(len(info.data)), &err, nil)
		if dec == nil {
			return false
		}
		if at > 0 {
			seek(dec, c.uint(at))
		}
		v = {dec = dec, track = t, pos = at, fade = fade, target = target, step = 1 / (seconds * MUSIC_RATE)}
		return true
	}
	return false
}

@(private)
mix_callback :: proc "c" (buffer: rawptr, frames: c.uint) {
	context = runtime.default_context()
	out := ([^]f32)(buffer)[:frames * 2]
	for &s in out {
		s = 0
	}

	sync.lock(&mx.lock)
	want_track, want_bed, want_mood := mx.want_track, mx.want_bed, mx.want_mood
	music_gain, bed_gain := mx.music_gain, mx.bed_gain
	duck, veil := mx.duck, mx.veil
	skip := mx.skip
	mx.skip = false
	sync.unlock(&mx.lock)

	if want_track != mx.track {
		for &v in mx.voices {
			if v.dec != nil {
				v.target, v.step = 0, 1 / (TRACK_FADE_OUT_S * MUSIC_RATE)
			}
		}
		mx.track = want_track
		if want_track != .None {
			open_voice(want_track, 0, 0, 1, TRACK_FADE_IN_S)
		}
	}
	if skip && mx.track != .None {
		for &v in mx.voices {
			if v.dec != nil && v.track == mx.track && v.target > 0 && !v.spawned {
				v.pos = TRACKS[v.track].loop_from - int(CROSSFADE_S * MUSIC_RATE) / 2 - 6 * MUSIC_RATE
				seek(v.dec, c.uint(v.pos))
			}
		}
	}
	if want_bed != mx.bed {
		for &b in mx.beds {
			b.target = 0
		}
		mx.bed = want_bed
		if want_bed != .None {
			for &b in mx.beds {
				if b.fade <= 0 {
					b = {bed = want_bed, target = 1}
					break
				}
			}
		}
	}

	n := int(frames)
	if want_mood != mx.mood {
		mx.mood = want_mood
		for &t in mx.gen_target {
			t = 0
		}
		if want_mood != .None {
			// the quieter slot takes the new mood
			k := mx.gen_fade[0] <= mx.gen_fade[1] ? 0 : 1
			gen_init(&mx.gens[k], want_mood, u32(rl.GetRandomValue(1, 1 << 20)))
			mx.gen_mood[k], mx.gen_fade[k], mx.gen_target[k] = want_mood, 0, 1
		}
	}
	gen_step := f32(n) / (MOOD_FADE_S * MUSIC_RATE)
	for k in 0 ..< 2 {
		if mx.gen_mood[k] == .None {
			continue
		}
		// the generator plays into scratch, then into the music bus at its fade
		buf := mx.scratch[:n * 2]
		for &v in buf {
			v = 0
		}
		gen_process(&mx.gens[k], buf)
		from := mx.gen_fade[k]
		to := mx.gen_target[k] > from ? min(from + gen_step, 1) : max(from - gen_step, 0)
		for i in 0 ..< n {
			f := from + (to - from) * f32(i) / f32(n)
			g := math.sin(f * math.PI / 2) * music_gain * GEN_TRIM
			out[2 * i] += buf[2 * i] * g
			out[2 * i + 1] += buf[2 * i + 1] * g
		}
		mx.gen_fade[k] = to
		if to <= 0 && mx.gen_target[k] <= 0 {
			mx.gen_mood[k] = .None
		}
	}
	half := int(CROSSFADE_S * MUSIC_RATE) / 2
	// the loop jump: a twin voice already at B, in step with this one (opened
	// before any decoding, so both play this block)
	for &v in mx.voices {
		info := TRACKS[v.track]
		if v.dec != nil && !v.spawned && v.target > 0 && v.pos + n >= info.loop_from - half {
			v.spawned = true
			at, track := v.pos - (info.loop_from - info.loop_to), v.track
			if open_voice(track, at, 0, 1, CROSSFADE_S) {
				v.target, v.step = 0, 1 / (CROSSFADE_S * MUSIC_RATE)
			}
		}
	}
	for &v in mx.voices {
		if v.dec == nil {
			continue
		}
		got := int(get_samples_float_interleaved(v.dec, 2, raw_data(mx.scratch[:]), c.int(n * 2)))
		for i in 0 ..< got {
			v.fade = v.target > v.fade ? min(v.fade + v.step, v.target) : max(v.fade - v.step, v.target)
			g := math.sin(v.fade * math.PI / 2) * music_gain
			out[2 * i] += mx.scratch[2 * i] * g
			out[2 * i + 1] += mx.scratch[2 * i + 1] * g
		}
		v.pos += got
		if got < n || (v.fade <= 0 && v.target <= 0) {
			close(v.dec)
			v = {}
		}
	}

	// veil and duck, smoothed per sample
	smooth := f32(1) / (0.25 * MUSIC_RATE)
	for i in 0 ..< n {
		mx.duck_now += clamp(duck - mx.duck_now, -smooth, smooth)
		mx.veil_now += clamp(veil - mx.veil_now, -smooth * 0.6, smooth * 0.6)
		cutoff := 16000 * math.pow(f32(1500) / 16000, mx.veil_now)
		a := 1 - math.exp(-math.TAU * cutoff / MUSIC_RATE)
		gain := (1 - 0.65 * mx.duck_now) * (1 - 0.2 * mx.veil_now)
		for ch in 0 ..< 2 {
			x := out[2 * i + ch]
			mx.lp[ch][0] += (x - mx.lp[ch][0]) * a
			mx.lp[ch][1] += (mx.lp[ch][0] - mx.lp[ch][1]) * a
			out[2 * i + ch] = (x + (mx.lp[ch][1] - x) * min(mx.veil_now * 20, 1)) * gain
		}
	}

	// ambience, under everything (ducked less than the music)
	bed_step := f32(1) / (BED_FADE_S * MUSIC_RATE)
	for &b in mx.beds {
		if b.bed == .None {
			continue
		}
		if !sync.atomic_load(&beds_ready) {
			break // still being synthesised: the bed fades in when ready
		}
		loop := beds[b.bed] // interleaved stereo
		if len(loop) == 0 {
			b = {}
			continue
		}
		for i in 0 ..< n {
			b.fade = b.target > b.fade ? min(b.fade + bed_step, b.target) : max(b.fade - bed_step, b.target)
			g := b.fade * bed_gain * (1 - 0.4 * mx.duck_now) / 32768
			out[2 * i] += f32(loop[b.pos]) * g
			out[2 * i + 1] += f32(loop[b.pos + 1]) * g
			b.pos = (b.pos + 2) % len(loop)
		}
		if b.fade <= 0 && b.target <= 0 {
			b = {}
		}
	}
}
