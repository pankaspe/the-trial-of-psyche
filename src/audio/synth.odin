// Procedural sound: the effects that are not recordings, and the ambience
// beds, synthesised at startup. Pure functions over f32 buffers; the reverb
// is baked into the samples, so playback needs no effect chain.
//
// The tuned effects (chimes, plucks, the wind's song) are written in A minor
// pentatonic (A C D E G), the key of Act I's soundtrack; `play` transposes
// them to the key of the act playing (set_key).
package audio

import "core:math"

import "../fx"

RATE :: 44100

Sound_Id :: enum u8 {
	Step_Grass, // recorded (assets/sfx)
	Step_Stone, // recorded (assets/sfx)
	Turn, // the world turns about Psyche: air, weight, a soft settle
	Seam, // a way opens where two stones meet in the view: a glass chime
	Lamp_On, // the wick catches: a breath of flame, crackle, a warm bloom
	Lamp_Off, // a puff, a thread of smoke
	Blocked, // no way: two soft knocks of wood
	Tap, // a button: a small pluck
	Rumble, // stone grinding against stone (the seal)
	Thud, // a stone settling into place
	Drip, // a drop (of oil)
	Reveal, // the face in the lamplight: a swelling chord, a bell
	Good, // something found: a harp, a pad
	Wind, // a gust (Zephyr, the exits): air and its song
}

// Effects drawn from recordings (loaded in audio.odin).
RECORDED :: bit_set[Sound_Id]{.Step_Grass, .Step_Stone}

// Effects in key: transposed with the act's soundtrack.
TUNED :: bit_set[Sound_Id]{.Seam, .Tap, .Reveal, .Good, .Wind, .Lamp_On}

// How many takes of each synthesised effect (a different random seed each),
// so repeated sounds are never quite the same.
VARIANTS := [Sound_Id]int {
	.Step_Grass = 0,
	.Step_Stone = 0,
	.Turn       = 2,
	.Seam       = 1,
	.Lamp_On    = 3,
	.Lamp_Off   = 2,
	.Blocked    = 2,
	.Tap        = 3,
	.Rumble     = 1,
	.Thud       = 4,
	.Drip       = 3,
	.Reveal     = 1,
	.Good       = 1,
	.Wind       = 2,
}

// The ambience of a place: a seamless stereo loop.
Bed :: enum u8 {
	None,
	Mountain, // high wind on the crag
	Dusk, // a breeze, the first crickets
	Night, // a still night full of crickets
	Deep_Night, // low wind, a few far crickets
}

BED_SECONDS :: 24

@(private)
CHIRP :: 970 // samples in one pulse of a cricket (22 ms)

// A semitone ratio (for pitch arguments in key: 3 = a minor third up).
semitones :: proc(n: f32) -> f32 {
	return math.pow(2, n / 12)
}

@(private)
buffer :: proc(seconds: f32, allocator := context.allocator) -> []f32 {
	return make([]f32, int(seconds * RATE), allocator)
}

@(private)
time_of :: proc(i: int) -> f32 {
	return f32(i) / RATE
}

@(private)
noise :: proc(rng: ^fx.Rng) -> f32 {
	return fx.rand_range(rng, -1, 1)
}

// One-pole smoothing coefficient for a cutoff in Hz.
@(private)
coef :: proc(hz: f32) -> f32 {
	return 1 - math.exp(-math.TAU * min(hz, RATE * 0.45) / RATE)
}

// State-variable filter (topology-preserving): low, band and high outputs.
@(private)
Svf :: struct {
	ic1, ic2: f32,
}

@(private)
svf :: proc(f: ^Svf, x, hz, q: f32) -> (lp, bp, hp: f32) {
	g := math.tan(math.PI * clamp(hz, 10, RATE * 0.45) / RATE)
	k := 1 / q
	a1 := 1 / (1 + g * (g + k))
	a2 := g * a1
	a3 := g * a2
	v3 := x - f.ic2
	v1 := a1 * f.ic1 + a2 * v3
	v2 := f.ic2 + a2 * f.ic1 + a3 * v3
	f.ic1 = 2 * v1 - f.ic1
	f.ic2 = 2 * v2 - f.ic2
	return v2, v1, x - k * v1 - v2
}

// Pink noise (Paul Kellet's economy filter).
@(private)
Pink :: struct {
	b0, b1, b2: f32,
}

@(private)
pink :: proc(p: ^Pink, rng: ^fx.Rng) -> f32 {
	w := noise(rng)
	p.b0 = 0.99765 * p.b0 + w * 0.0990460
	p.b1 = 0.96300 * p.b1 + w * 0.2965164
	p.b2 = 0.57000 * p.b2 + w * 1.0526913
	return (p.b0 + p.b1 + p.b2 + w * 0.1848) * 0.2
}

// A struck resonant body: damped partials (ratio, gain, decay per second),
// added into b from `start` seconds. The attack is a few samples, not a click.
@(private)
Partial :: struct {
	ratio, gain, decay: f32,
}

@(private)
modal :: proc(b: []f32, start, freq, amp: f32, partials: []Partial, attack: f32 = 0.002) {
	s0 := int(start * RATE)
	for p in partials {
		f := freq * p.ratio
		if f >= RATE * 0.45 {
			continue
		}
		w := math.TAU * f / RATE
		for i in s0 ..< len(b) {
			t := time_of(i - s0)
			env := math.exp(-t * p.decay)
			if env < 1e-4 {
				break
			}
			b[i] += math.sin(w * f32(i - s0)) * env * p.gain * amp * min(t / attack, 1)
		}
	}
}

// Glass and bronze: the chimes of the palace.
@(private)
GLASS := []Partial{{1, 1, 1.4}, {2.756, 0.32, 3.6}, {5.404, 0.12, 7}, {8.933, 0.05, 11}}
// A small block of wood.
@(private)
WOOD := []Partial{{1, 1, 28}, {2.57, 0.4, 45}, {4.3, 0.18, 70}}

// A plucked string (Karplus-Strong): a burst of noise in a damped delay line.
@(private)
pluck :: proc(b: []f32, start, freq, amp: f32, rng: ^fx.Rng, brightness: f32 = 0.5, sustain: f32 = 0.996) {
	n := int(RATE / freq)
	line := make([]f32, n, context.temp_allocator)
	lp: f32 = 0
	for &v in line {
		lp += (noise(rng) - lp) * brightness
		v = lp
	}
	s0 := int(start * RATE)
	prev: f32 = 0
	for i in s0 ..< len(b) {
		k := (i - s0) % n
		y := line[k]
		line[k] = (y + prev) * 0.5 * sustain
		prev = y
		b[i] += y * amp
	}
}

// Short bursts of filtered noise scattered in time: grit, crackle, debris.
// `density` grains per second at time t (seconds).
@(private)
grains :: proc(b: []f32, rng: ^fx.Rng, from, to: f32, density: proc(t: f32) -> f32, hz_lo, hz_hi, amp: f32, length: f32 = 0.004) {
	for t := from; t < to; t += 0.001 {
		if fx.randf(rng) > density(t) * 0.001 {
			continue
		}
		hz := fx.rand_range(rng, hz_lo, hz_hi)
		a := amp * fx.rand_range(rng, 0.2, 1)
		len_s := length * fx.rand_range(rng, 0.5, 1.5)
		f: Svf
		s0 := int(t * RATE)
		for i in s0 ..< min(s0 + int((len_s * 4) * RATE), len(b)) {
			u := time_of(i - s0)
			_, bp, _ := svf(&f, noise(rng), hz, 2)
			b[i] += bp * a * math.exp(-u / len_s)
		}
	}
}

PEAK :: 0.7

// The samples of one effect (take `variant`, a different seed each).
synthesize :: proc(id: Sound_Id, variant: int, allocator := context.allocator) -> []f32 {
	rng := fx.rng_init(u32(id) * 97 + u32(variant) * 13 + 5)
	b: []f32
	switch id {
	case .Step_Grass, .Step_Stone:
		// recordings: a tiny placeholder, only for headless use
		b = buffer(0.05, allocator)
		modal(b, 0, 180, 0.3, WOOD)

	case .Turn:
		b = buffer(1.4, allocator)
		DUR :: 0.8
		pk: Pink
		lo, hi: Svf
		for &s, i in b {
			t := time_of(i)
			u := min(t / DUR, 1)
			swell := math.pow(max(math.sin(math.PI * u), 0), 1.4)
			center := 260 + 900 * swell
			x := pink(&pk, &rng)
			_, air, _ := svf(&lo, x, center, 1.1)
			_, hiss, _ := svf(&hi, x, center * 2.6, 3)
			sub := math.sin(math.TAU * 55 * t) * 0.22 + math.sin(math.TAU * 82.41 * t) * 0.07
			bloom := min(t / 0.25, 1) * math.exp(-max(t - 0.5, 0) * 4)
			s = (air * 1.6 + hiss * 0.35) * swell + sub * bloom
		}
		grit :: proc(t: f32) -> f32 {return 120 * math.sin(math.PI * clamp((t - 0.1) / 0.6, 0, 1))}
		grains(b, &rng, 0.1, 0.7, grit, 1400, 3200, 0.06)
		// the view settles: a soft low knock
		modal(b, DUR - 0.04, 92, 0.22, WOOD[:1], 0.004)
		b = reverb(b, ROOM, 0.8, allocator)

	case .Seam:
		b = buffer(3.0, allocator)
		modal(b, 0, 880, 0.22, GLASS)
		modal(b, 0.11, 1318.51, 0.16, GLASS)
		// the air of the glass: a breath of noise tuned to the notes
		f1, f2: Svf
		for &s, i in b {
			t := time_of(i)
			x := noise(&rng)
			_, a, _ := svf(&f1, x, 1760, 40)
			_, c, _ := svf(&f2, x, 2637, 40)
			s += (a + c) * 0.25 * math.exp(-t * 5) * min(t / 0.03, 1)
		}
		b = reverb(b, HALL, 3.0, allocator)

	case .Lamp_On:
		b = buffer(1.8, allocator)
		pk: Pink
		f: Svf
		body: f32 = 0
		flick: f32 = 0
		for &s, i in b {
			t := time_of(i)
			// the catch: the flame climbs and opens
			cut := 300 + 2600 * min(t / 0.12, 1) * math.exp(-max(t - 0.12, 0) * 2.5)
			lp, _, _ := svf(&f, pink(&pk, &rng), cut, 0.8)
			whoomph := lp * math.sqrt(min(t / 0.06, 1)) * math.exp(-t * 4.5)
			// the steady flame: a low breath that flickers
			body += (noise(&rng) - body) * coef(380)
			flick += (fx.randf(&rng) - flick) * coef(9)
			steady := body * (0.6 + 0.8 * flick) * min(t / 0.2, 1) * math.exp(-t * 1.6)
			// the light, in key: A3 E4 A4 bloom under it
			bloom := (math.sin(math.TAU * 220 * t) + math.sin(math.TAU * 329.63 * t) * 0.7 + math.sin(math.TAU * 440 * t) * 0.4) *
				0.035 * min(t / 0.35, 1) * math.exp(-t * 1.4)
			s = whoomph * 0.9 + steady * 0.9 + bloom
		}
		crackle :: proc(t: f32) -> f32 {return 90 * math.exp(-t * 2.2) + 8}
		grains(b, &rng, 0.03, 1.5, crackle, 1800, 5200, 0.22, 0.0015)
		b = reverb(b, ROOM, 0.8, allocator)

	case .Lamp_Off:
		b = buffer(0.7, allocator)
		f, h: Svf
		for &s, i in b {
			t := time_of(i)
			x := noise(&rng)
			_, puff, _ := svf(&f, x, 1300 - 800 * min(t / 0.25, 1), 0.9)
			_, _, smoke := svf(&h, x, 4500, 0.7)
			thup := math.sin(math.TAU * (120 - 60 * min(t / 0.06, 1)) * t) * math.exp(-t * 40) * 0.25
			s = puff * min(t / 0.02, 1) * math.exp(-t * 9) * 0.9 + smoke * 0.025 * math.exp(-t * 3) + thup
		}
		b = reverb(b, ROOM, 0.6, allocator)

	case .Blocked:
		b = buffer(0.4, allocator)
		modal(b, 0, 196, 0.45, WOOD)
		modal(b, 0.085, 164.81, 0.32, WOOD)
		f: Svf
		for &s, i in b[:int(0.01 * RATE)] {
			lp, _, _ := svf(&f, noise(&rng), 1200, 0.7)
			s += lp * 0.2 * (1 - time_of(i) / 0.01)
		}
		b = reverb(b, ROOM, 0.5, allocator)

	case .Tap:
		b = buffer(0.5, allocator)
		pluck(b, 0, 880, 0.35, &rng, 0.35, 0.985)
		for &s, i in b {
			s *= math.exp(-time_of(i) * 7)
		}
		b = reverb(b, ROOM, 0.5, allocator)

	case .Rumble:
		b = buffer(3.2, allocator)
		brown, am, amt: f32
		for &s, i in b {
			t := time_of(i)
			brown = clamp(brown + noise(&rng) * 0.04, -1, 1) * 0.998
			amt += (fx.randf(&rng) - amt) * coef(6)
			env := min(t / 0.5, 1) * clamp((3.2 - t) / 1.2, 0, 1)
			am += (brown - am) * coef(170)
			s = (am * 2.4 * (0.6 + 0.8 * amt) + math.sin(math.TAU * 41.2 * t) * 0.18) * env
		}
		grind :: proc(t: f32) -> f32 {return 220 * min(t / 0.5, 1) * clamp((3 - t) / 1.2, 0, 1)}
		grains(b, &rng, 0.05, 3.0, grind, 700, 2200, 0.08, 0.006)
		b = reverb(b, HALL, 1.5, allocator)

	case .Thud:
		b = buffer(0.7, allocator)
		f: Svf
		for &s, i in b {
			t := time_of(i)
			hz := 45 + 70 * math.exp(-t * 25)
			body := math.sin(math.TAU * hz * t) * math.exp(-t * 9) * 0.7
			lp, _, _ := svf(&f, noise(&rng), 600, 0.7)
			s = body + lp * 0.5 * math.exp(-t * 60)
		}
		debris :: proc(t: f32) -> f32 {return 60 * math.exp(-t * 6)}
		grains(b, &rng, 0.03, 0.5, debris, 900, 3000, 0.08, 0.003)
		b = reverb(b, HALL, 1.2, allocator)

	case .Drip:
		b = buffer(0.25, allocator)
		f0 := fx.rand_range(&rng, 1000, 1200)
		phase: f32 = 0
		for &s, i in b {
			t := time_of(i)
			hz := f0 * (1 + 1.2 * (1 - math.exp(-t * 45)))
			phase += math.TAU * hz / RATE
			s = math.sin(phase) * math.exp(-t * 32) * 0.5 * min(t / 0.001, 1)
		}
		b = reverb(b, HALL, 2.0, allocator)

	case .Reveal:
		b = buffer(5.0, allocator)
		CHORD :: [5]f32{110, 164.81, 246.94, 261.63, 329.63} // A2 E3 B3 C4 E4: A minor, add 9
		for f, n in CHORD {
			for &s, i in b {
				t := time_of(i)
				env := min(t / 1.4, 1) * math.exp(-max(t - 2.0, 0) * 1.1) * (0.07 - f32(n) * 0.008)
				// two voices a few cents apart, slowly beating
				v := math.sin(math.TAU * f * t + math.sin(math.TAU * 4.5 * t) * 0.15) + math.sin(math.TAU * f * 1.003 * t)
				s += v * env
			}
		}
		modal(b, 1.2, 1760, 0.08, GLASS)
		modal(b, 1.45, 1318.51, 0.05, GLASS)
		b = reverb(b, HALL, 3.5, allocator)

	case .Good:
		b = buffer(5.0, allocator)
		HARP :: [5]f32{220, 261.63, 329.63, 440, 659.25} // A3 C4 E4 A4 E5
		for f, n in HARP {
			pluck(b, f32(n) * 0.075, f, 0.22, &rng, 0.45, 0.998)
		}
		for f in ([3]f32{110, 164.81, 220}) {
			for &s, i in b {
				t := time_of(i)
				s += math.sin(math.TAU * f * t) * 0.045 * min(t / 0.8, 1) * math.exp(-max(t - 1, 0) * 1.3)
			}
		}
		b = reverb(b, HALL, 3.0, allocator)

	case .Wind:
		b = buffer(4.2, allocator)
		pk: Pink
		f1, f2, song: Svf
		drift := fx.rand_range(&rng, -0.3, 0.3)
		for &s, i in b {
			t := time_of(i)
			u := min(t / 4.0, 1)
			gust := math.pow(max(math.sin(math.PI * u), 0), 1.3)
			x := pink(&pk, &rng)
			_, low, _ := svf(&f1, x, 350 + 400 * gust + 80 * math.sin(math.TAU * (0.7 + drift) * t), 0.7)
			_, high, _ := svf(&f2, x, 1000 + 900 * gust, 2.2)
			// the wind's song: a narrow resonance gliding between E5 and A5
			_, sing, _ := svf(&song, noise(&rng), 659.25 + 220.75 * (0.5 + 0.5 * math.sin(math.PI * (u - 0.3))), 60)
			s = (low * 1.4 + high * 0.4) * gust + sing * 0.6 * gust * gust
		}
		b = reverb(b, HALL, 2.0, allocator)
	}
	// every effect leaves at the same peak: the call sites set the levels
	peak: f32 = 0
	for v in b {
		peak = max(peak, abs(v))
	}
	if peak > 0 {
		for &v in b {
			v *= PEAK / peak
		}
	}
	return b
}

// One seamless stereo loop (interleaved) of BED_SECONDS for a place.
synthesize_bed :: proc(bed: Bed, allocator := context.allocator) -> []f32 {
	if bed == .None {
		return nil
	}
	rng := fx.rng_init(u32(bed) * 31 + 3)
	XF :: 3.0 // seconds crossfaded at the wrap
	n := int(BED_SECONDS * RATE)
	m := n + int(XF * RATE)
	raw := make([]f32, m * 2, context.temp_allocator)

	// wind: brown and pink noise through a gusting low-pass, each side its own
	Wind_Spec :: struct {
		level, low, high, gust: f32,
	}
	wind: Wind_Spec
	crickets := 0
	cricket_level: f32 = 0
	switch bed {
	case .None:
	case .Mountain:
		wind = {0.55, 250, 1400, 0.8}
	case .Dusk:
		wind = {0.22, 200, 700, 0.5}
		crickets, cricket_level = 3, 0.035
	case .Night:
		wind = {0.12, 180, 500, 0.4}
		crickets, cricket_level = 6, 0.04
	case .Deep_Night:
		wind = {0.25, 120, 420, 0.6}
		crickets, cricket_level = 2, 0.018
	}
	for ch in 0 ..< 2 {
		pk: Pink
		f, rumble: Svf
		brown: f32 = 0
		ph := fx.rand_range(&rng, 0, 10)
		for i in 0 ..< m {
			t := time_of(i)
			g := 0.5 + 0.5 * (math.sin(0.21 * t + ph) * 0.5 + math.sin(0.067 * t + 2 * ph) * 0.35 + math.sin(0.53 * t + ph * 3) * 0.15)
			g = 1 - wind.gust + wind.gust * g
			brown = clamp(brown + noise(&rng) * 0.03, -1, 1) * 0.999
			x := pink(&pk, &rng) * 0.7 + brown * 0.6
			lp, _, _ := svf(&f, x, wind.low + (wind.high - wind.low) * g * g, 0.6)
			// no rumble under the air: it would only press on the ears
			_, _, hp := svf(&rumble, lp, 90, 0.7)
			raw[2 * i + ch] = hp * wind.level * g
		}
	}
	// crickets: each a chirp of a few pulses of a high tone, repeated with
	// its own rhythm, placed somewhere left or right, near or far
	for c in 0 ..< crickets {
		hz := fx.rand_range(&rng, 3900, 4800)
		pan := fx.rand_range(&rng, -0.8, 0.8)
		far := fx.rand_range(&rng, 0.3, 1)
		period := fx.rand_range(&rng, 0.55, 1.3)
		pulses := 2 + int(fx.randf(&rng) * 3)
		left, right := math.sqrt(0.5 * (1 - pan)), math.sqrt(0.5 * (1 + pan))
		for start := fx.rand_range(&rng, 0, period); start < f32(m) / RATE - 0.3; start += period * fx.rand_range(&rng, 0.9, 1.1) {
			if fx.randf(&rng) < 0.15 {
				continue // a pause now and then
			}
			for p in 0 ..< pulses {
				s0 := int((start + f32(p) * 0.033) * RATE)
				for k in 0 ..< CHIRP {
					i := s0 + k
					if i >= m {
						break
					}
					u := f32(k) / CHIRP
					v := math.sin(math.TAU * hz * time_of(i)) * math.sin(math.PI * u) * cricket_level * far
					raw[2 * i] += v * left
					raw[2 * i + 1] += v * right
				}
			}
		}
		_ = c
	}
	// the wrap: the last XF seconds fade into the first, equal power
	out := make([]f32, n * 2, allocator)
	xf := m - n
	for i in 0 ..< n {
		for ch in 0 ..< 2 {
			v := raw[2 * i + ch]
			if i < xf {
				u := f32(i) / f32(xf)
				v = v * math.sin(u * math.PI / 2) + raw[2 * (n + i) + ch] * math.cos(u * math.PI / 2)
			}
			out[2 * i + ch] = v
		}
	}
	return out
}

// Feedback delay network reverb: 8 lines, Householder feedback, damping per
// line, two allpasses of diffusion in front.
Reverb_Params :: struct {
	rt60:     f32, // seconds for the tail to fall 60 dB
	damp_hz:  f32, // the tail darkens above this
	size:     f32, // scales the delay lengths
	wet, dry: f32,
	predelay: f32, // seconds
}

ROOM :: Reverb_Params{0.9, 4500, 0.6, 0.22, 1, 0.008}
HALL :: Reverb_Params{2.8, 3800, 1.2, 0.42, 1, 0.022}

// The input plus a tail of `tail` seconds.
reverb :: proc(input: []f32, params: Reverb_Params, tail: f32, allocator := context.allocator) -> []f32 {
	LENGTHS :: [8]int{1123, 1291, 1447, 1597, 1789, 1993, 2179, 2357}
	AP :: [2]int{347, 113}
	lengths := LENGTHS
	aps := AP
	n := len(input)
	out := make([]f32, n + int(tail * RATE), allocator)

	lines: [8][]f32
	pos: [8]int
	gains: [8]f32
	damp: [8]f32
	a := coef(params.damp_hz)
	for &l, k in lines {
		d := max(int(f32(lengths[k]) * params.size), 1)
		l = make([]f32, d, context.temp_allocator)
		gains[k] = math.pow(10, -3 * f32(d) / (params.rt60 * RATE))
	}
	ap_buf: [2][]f32
	ap_pos: [2]int
	for &buf, k in ap_buf {
		buf = make([]f32, aps[k], context.temp_allocator)
	}
	pre := make([]f32, max(int(params.predelay * RATE), 1), context.temp_allocator)
	pre_pos := 0

	// whatever is still sounding at the end of the input fades out, no click
	fade_from := max(n - int(0.05 * RATE), 0)
	end_fade :: proc(i, from, n: int) -> f32 {
		return i < from ? 1 : max(f32(n - i) / f32(n - from), 0)
	}
	for i in 0 ..< len(out) {
		x: f32 = i < n ? input[i] * end_fade(i, fade_from, n) : 0
		// predelay, then diffusion
		d := pre[pre_pos]
		pre[pre_pos] = x
		pre_pos = (pre_pos + 1) % len(pre)
		for &buf, k in ap_buf {
			y := buf[ap_pos[k]]
			v := d + y * 0.6
			buf[ap_pos[k]] = v
			d = y - v * 0.6
			ap_pos[k] = (ap_pos[k] + 1) % len(buf)
		}
		outs: [8]f32
		sum: f32 = 0
		for k in 0 ..< 8 {
			outs[k] = lines[k][pos[k]]
			damp[k] += (outs[k] - damp[k]) * a
			outs[k] = damp[k] * gains[k]
			sum += outs[k]
		}
		h := sum * 2 / 8
		wet: f32 = 0
		for k in 0 ..< 8 {
			lines[k][pos[k]] = outs[k] - h + d * 0.35
			pos[k] = (pos[k] + 1) % len(lines[k])
			wet += k % 2 == 0 ? outs[k] : -outs[k]
		}
		dry: f32 = i < n ? input[i] * end_fade(i, fade_from, n) : 0
		out[i] = dry * params.dry + wet * params.wet * 0.5
	}
	return out
}

// f32 samples -> signed 16-bit PCM.
to_pcm16 :: proc(samples: []f32, out: []i16) {
	for s, i in samples {
		out[i] = i16(clamp(s, -1, 1) * 32000)
	}
}
