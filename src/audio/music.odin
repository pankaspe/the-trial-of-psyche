// The bed under the game: the act's music and the ambience of the place,
// mixed on the audio thread into one stereo stream.
//
// The act's music is generative (generative.odin): a mood per act, played
// live; changing mood fades one generator out and the next in.
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
MOOD_FADE_S :: 4.0
GEN_TRIM :: 2.0 // +6 dB: the generators leave headroom
BED_FADE_S :: 2.0

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
	want_mood:  Mood_Id,
	want_bed:   Bed,
	music_gain: f32,
	bed_gain:   f32,
	duck:       f32,
	veil:       f32,
	// audio thread only
	bed:        Bed,
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
	mx = {}
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

@(private)
mixer_gains :: proc(music, bed: f32) {
	sync.guard(&mx.lock)
	mx.music_gain, mx.bed_gain = music, bed
}

@(private)
mix_callback :: proc "c" (buffer: rawptr, frames: c.uint) {
	context = runtime.default_context()
	out := ([^]f32)(buffer)[:frames * 2]
	for &s in out {
		s = 0
	}

	sync.lock(&mx.lock)
	want_bed, want_mood := mx.want_bed, mx.want_mood
	music_gain, bed_gain := mx.music_gain, mx.bed_gain
	duck, veil := mx.duck, mx.veil
	sync.unlock(&mx.lock)

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

	n := min(int(frames), BLOCK) // raylib asks at most the buffer size
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
