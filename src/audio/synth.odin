// Procedural sound: every effect and the two music layers are synthesised at
// startup (no audio files). Pure functions over f32 buffers; the reverb is
// baked into the samples, so playback needs no effect chain.
package audio

import "core:math"

import "../fx"

RATE :: 22050

Sound_Id :: enum u8 {
	Step,
	Lamp_On,
	Lamp_Off,
	Voice,
	Seam,
	Blocked,
	Turn,
	Tap,
	Rumble,
	Drop,
	Reveal,
	Good,
	Wind,
}

@(private)
buffer :: proc(seconds: f32, allocator := context.allocator) -> []f32 {
	return make([]f32, int(seconds * RATE), allocator)
}

@(private)
time_of :: proc(i: int) -> f32 {
	return f32(i) / RATE
}

// Bell: inharmonic partials with individual decays, added into b from `start` (seconds).
@(private)
bell :: proc(b: []f32, start, freq, amp, decay: f32) {
	PARTIALS :: [4][3]f32{{1.0, 1.0, 1.0}, {2.0, 0.5, 1.6}, {3.01, 0.25, 2.4}, {4.2, 0.12, 3.5}}
	partials := PARTIALS
	s0 := int(start * RATE)
	for i in s0 ..< len(b) {
		t := time_of(i - s0)
		v: f32 = 0
		for p in partials {
			v += math.sin(math.TAU * freq * p[0] * t) * p[1] * math.exp(-t * decay * p[2])
		}
		b[i] += v * amp * min(t * 200, 1)
	}
}

// Dry samples of one effect.
synthesize :: proc(id: Sound_Id, rng: ^fx.Rng, allocator := context.allocator) -> []f32 {
	noise :: proc(rng: ^fx.Rng) -> f32 {
		return fx.rand_range(rng, -1, 1)
	}
	b: []f32
	lp: f32 = 0
	switch id {
	case .Step:
		// a soft, low-passed tick
		b = buffer(0.09, allocator)
		for &s, i in b {
			lp += (noise(rng) - lp) * 0.25
			s = lp * math.exp(-time_of(i) * 60) * 0.5
		}
	case .Lamp_On:
		// a breath of flame with a rising tone
		b = buffer(0.8, allocator)
		for &s, i in b {
			t := time_of(i)
			lp += (noise(rng) - lp) * (0.02 + 0.2 * min(t / 0.3, 1))
			env := min(t / 0.06, 1) * math.exp(-t * 4)
			f := 180 + 260 * min(t / 0.4, 1)
			s = (lp * 0.7 + math.sin(math.TAU * f * t) * 0.18) * env
		}
	case .Lamp_Off:
		b = buffer(0.45, allocator)
		for &s, i in b {
			t := time_of(i)
			lp += (noise(rng) - lp) * (0.15 * math.exp(-t * 6) + 0.01)
			s = lp * min(t / 0.02, 1) * math.exp(-t * 7) * 0.8
		}
	case .Voice:
		b = buffer(3.0, allocator)
		bell(b, 0.0, 659.25, 0.18, 1.2)
		bell(b, 0.18, 987.77, 0.1, 1.4)
	case .Seam:
		b = buffer(1.2, allocator)
		bell(b, 0.0, 1318.5, 0.12, 3.0)
		bell(b, 0.09, 1975.5, 0.08, 3.5)
	case .Blocked:
		b = buffer(0.35, allocator)
		for &s, i in b {
			t := time_of(i)
			s = math.sin(math.TAU * (140 - t * 120) * t) * math.exp(-t * 14) * 0.4
		}
	case .Turn:
		// the diorama turning: stone grinding on stone, with a low swell
		b = buffer(0.9, allocator)
		lp2: f32 = 0
		for &s, i in b {
			t := time_of(i)
			lp += (noise(rng) - lp) * 0.06
			lp2 += (lp - lp2) * 0.3
			env := math.sin(math.PI * min(t / 0.8, 1)) * (0.8 + 0.2 * math.sin(math.TAU * 31 * t))
			s = (lp2 * 2.4 + math.sin(math.TAU * (70 + 20 * t) * t) * 0.12) * env * 0.7
		}
	case .Tap:
		b = buffer(0.3, allocator)
		bell(b, 0.0, 1760, 0.05, 8)
	case .Rumble:
		b = buffer(3.0, allocator)
		for &s, i in b {
			t := time_of(i)
			lp += (noise(rng) - lp) * 0.02
			env := min(t / 0.6, 1) * clamp((3 - t) / 1.2, 0, 1)
			s = (lp * 2.2 + math.sin(math.TAU * 46 * t) * 0.3) * env * 0.6
		}
	case .Drop:
		b = buffer(0.35, allocator)
		for &s, i in b {
			t := time_of(i)
			s = math.sin(math.TAU * (1700 - 900 * min(t / 0.05, 1)) * t) * math.exp(-t * 30) * 0.25 +
				noise(rng) * math.exp(-t * 18) * 0.05 * min(t / 0.03, 1)
		}
	case .Reveal:
		b = buffer(4.5, allocator)
		for f in ([5]f32{220.0, 277.18, 329.63, 440.0, 554.37}) {
			for &s, i in b {
				t := time_of(i)
				s += math.sin(math.TAU * f * t + math.sin(math.TAU * 5 * t) * 0.3) * 0.07 * min(t / 1.2, 1) * math.exp(-max(t - 1.5, 0) * 1.2)
			}
		}
		bell(b, 0.0, 880, 0.08, 0.8)
	case .Good:
		b = buffer(5.0, allocator)
		for f in ([5]f32{146.83, 220.0, 293.66, 369.99, 440.0}) {
			for &s, i in b {
				t := time_of(i)
				s += math.sin(math.TAU * f * t) * 0.07 * min(t / 1.5, 1) * math.exp(-max(t - 2, 0) * 1.0)
			}
		}
		bell(b, 0.4, 587.33, 0.08, 0.9)
		bell(b, 1.1, 739.99, 0.06, 0.9)
	case .Wind:
		// Zephyr: a gust of filtered noise that swells and passes, over a soft open fifth
		b = buffer(4.0, allocator)
		lp2: f32 = 0
		for &s, i in b {
			t := time_of(i)
			cut := 0.012 + 0.05 * math.sin(math.PI * min(t / 3.2, 1))
			lp += (noise(rng) - lp) * cut
			lp2 += (lp - lp2) * cut
			env := math.sin(math.PI * min(t / 3.8, 1))
			tone := (math.sin(math.TAU * 293.66 * t) + math.sin(math.TAU * 440.0 * t) * 0.7) * 0.035
			s = (lp2 * 5 + tone * min(t / 1.0, 1)) * env
		}
		bell(b, 0.6, 1174.66, 0.04, 1.2)
	}
	return b
}

// 8 s seamless loop: every frequency completes an integer number of cycles.
music :: proc(warm: bool, rng: ^fx.Rng, allocator := context.allocator) -> []f32 {
	b := buffer(8.0, allocator)
	notes := warm ? [5]f32{55.0, 110.0, 164.75, 220.0, 277.25} : [5]f32{55.0, 110.0, 164.75, 196.0, 261.625}
	AMPS :: [5]f32{0.16, 0.1, 0.07, 0.05, 0.035}
	amps := AMPS
	for f, n in notes {
		lfo_phase := f32(n) * 1.3
		for &s, i in b {
			t := time_of(i)
			lfo := 0.6 + 0.4 * math.sin(math.TAU * 0.125 * t + lfo_phase)
			v := math.sin(math.TAU * f * t)
			if warm {
				v += math.sin(math.TAU * f * 2 * t) * 0.3
			}
			s += v * amps[n] * lfo
		}
	}
	if warm {
		// a little crackle of flame
		for _ in 0 ..< 60 {
			start := int(fx.randf(rng) * f32(len(b) - 400))
			for j in 0 ..< 300 {
				b[start + j] += fx.rand_range(rng, -1, 1) * 0.05 * math.exp(-f32(j) / 40)
			}
		}
	}
	return b
}

Reverb_Params :: struct {
	room:    f32, // 0..1, comb feedback
	damping: f32, // 0..1
	wet:     f32,
	dry:     f32,
}

SFX_REVERB :: Reverb_Params{0.85, 0.4, 0.35, 0.9}
MUSIC_REVERB :: Reverb_Params{0.6, 0.4, 0.2, 0.9}

// Schroeder-style reverb (4 damped combs + 2 allpasses, Freeverb tunings at
// half rate). Returns the input plus a tail of `tail` seconds. With `looped`
// the input is a seamless loop: the result keeps the same length and the tail
// wraps around to the start.
reverb :: proc(input: []f32, params: Reverb_Params, tail: f32, looped: bool, allocator := context.allocator) -> []f32 {
	COMBS :: [4]int{558, 594, 638, 678}
	ALLPASSES :: [2]int{278, 220}
	combs := COMBS
	allpasses := ALLPASSES

	n := len(input)
	out_len := looped ? n : n + int(tail * RATE)
	out := make([]f32, out_len, allocator)

	comb_buf: [4][]f32
	comb_pos: [4]int
	comb_lp: [4]f32
	for d, i in combs {
		comb_buf[i] = make([]f32, d, context.temp_allocator)
	}
	ap_buf: [2][]f32
	ap_pos: [2]int
	for d, i in allpasses {
		ap_buf[i] = make([]f32, d, context.temp_allocator)
	}
	feedback := 0.7 + params.room * 0.28
	damp := params.damping * 0.4

	// a looped input runs twice: the first pass only warms the delay lines up
	passes := looped ? 2 : 1
	total := looped ? 2 * n : out_len
	for i in 0 ..< total {
		x: f32 = 0
		if looped {
			x = input[i % n]
		} else if i < n {
			x = input[i]
		}
		x *= 0.25
		acc: f32 = 0
		for &buf, c in comb_buf {
			y := buf[comb_pos[c]]
			comb_lp[c] = y * (1 - damp) + comb_lp[c] * damp
			buf[comb_pos[c]] = x + comb_lp[c] * feedback
			comb_pos[c] = (comb_pos[c] + 1) % len(buf)
			acc += y
		}
		for &buf, a in ap_buf {
			y := buf[ap_pos[a]]
			buf[ap_pos[a]] = acc + y * 0.5
			acc = y - acc
			ap_pos[a] = (ap_pos[a] + 1) % len(buf)
		}
		if passes == 2 && i < n {
			continue
		}
		j := looped ? i - n : i
		dry: f32 = j < n ? input[j] : 0
		out[j] = dry * params.dry + acc * params.wet
	}
	return out
}

// f32 samples -> signed 16-bit PCM.
to_pcm16 :: proc(samples: []f32, out: []i16) {
	for s, i in samples {
		out[i] = i16(clamp(s, -1, 1) * 32000)
	}
}

// A mono 16-bit WAV file in memory (for looping music streams).
wav_file :: proc(samples: []f32, allocator := context.allocator) -> []u8 {
	data_size := len(samples) * 2
	out := make([]u8, 44 + data_size, allocator)
	put_u32 :: proc(b: []u8, at: int, v: u32) {
		b[at], b[at + 1], b[at + 2], b[at + 3] = u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24)
	}
	put_u16 :: proc(b: []u8, at: int, v: u16) {
		b[at], b[at + 1] = u8(v), u8(v >> 8)
	}
	copy(out[0:], "RIFF")
	put_u32(out, 4, u32(36 + data_size))
	copy(out[8:], "WAVEfmt ")
	put_u32(out, 16, 16) // fmt chunk size
	put_u16(out, 20, 1) // PCM
	put_u16(out, 22, 1) // mono
	put_u32(out, 24, RATE)
	put_u32(out, 28, RATE * 2) // byte rate
	put_u16(out, 32, 2) // block align
	put_u16(out, 34, 16) // bits per sample
	copy(out[36:], "data")
	put_u32(out, 40, u32(data_size))
	for s, i in samples {
		v := u16(i16(clamp(s, -1, 1) * 32000))
		put_u16(out, 44 + i * 2, v)
	}
	return out
}
