// Procedural sound: the effects that are not recordings, and the ambience
// beds, synthesised at startup. Pure functions over f32 buffers; the reverb
// is baked into the samples (stereo), so playback needs no effect chain.
// The effects are meant to sound like a dream: soft, rounded, far.
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
	Forest, // the night wind in the trees, crickets in the grass
	River, // a wide river flowing, a breeze, the first birds of the morning
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
// Glass struck with felt, wood wrapped in cloth: the effects' soft bodies.
@(private)
SOFT_GLASS := []Partial{{1, 1, 1.2}, {2.756, 0.14, 3.2}, {5.404, 0.04, 6}}
@(private)
SOFT_WOOD := []Partial{{1, 1, 22}, {2.57, 0.18, 40}}

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

// Every effect is shaped to sound like a dream: soft attacks, no clicks or
// grit, the highs rounded off (`SOFT_HZ`), and a long stereo tail.
SOFT_HZ :: 6500

// A soft flute: a near-sine that speaks slowly, with a breath on its onset
// and a vibrato that comes in late. Added into b from `start` seconds; it
// holds `dur` seconds, then dies away over `release`.
@(private)
flute :: proc(b: []f32, start, freq, dur, amp: f32, rng: ^fx.Rng, attack: f32 = 0.09, release: f32 = 0.8) {
	s0 := int(start * RATE)
	f: Svf
	phase: f32 = 0
	vib := fx.rand_range(rng, 0, math.TAU)
	rate := fx.rand_range(rng, 4.6, 5.4)
	for k in 0 ..< int((dur + release) * RATE) {
		i := s0 + k
		if i >= len(b) {
			break
		}
		t := f32(k) / RATE
		a := min(t / attack, 1)
		env := a * a * (3 - 2 * a)
		if t > dur {
			env *= math.exp(-(t - dur) * 5 / release)
		}
		depth := 0.004 * clamp((t - 0.3) / 0.6, 0, 1)
		phase += math.TAU * freq * (1 + depth * math.sin(math.TAU * rate * t + vib)) / RATE
		if phase > math.TAU {
			phase -= math.TAU
		}
		tone := math.sin(phase) + 0.12 * math.sin(2 * phase) + 0.03 * math.sin(3 * phase)
		_, breath, _ := svf(&f, noise(rng), freq * 2, 3)
		chiff := math.exp(-t * 22)
		b[i] += (tone * 0.9 + breath * (0.05 + 0.3 * chiff)) * env * amp
	}
}

// A slow chord of sines, two voices a few cents apart (a pad of light).
@(private)
glow :: proc(b: []f32, freqs: []f32, amp, rise, hold, fall: f32) {
	for f, n in freqs {
		g := amp / (1 + f32(n) * 0.35)
		for &s, i in b {
			t := time_of(i)
			env := min(t / rise, 1)
			env = env * env * (3 - 2 * env) * math.exp(-max(t - rise - hold, 0) / fall)
			s += (math.sin(math.TAU * f * t) + math.sin(math.TAU * f * 1.003 * t)) * env * g
		}
	}
}

// The samples of one effect (take `variant`, a different seed each), stereo
// interleaved.
synthesize :: proc(id: Sound_Id, variant: int, allocator := context.allocator) -> []f32 {
	rng := fx.rng_init(u32(id) * 97 + u32(variant) * 13 + 5)
	b: []f32
	room := DREAM
	tail: f32 = 3
	switch id {
	case .Step_Grass, .Step_Stone:
		// recordings: a tiny placeholder, only for headless use
		b = buffer(0.05, context.temp_allocator)
		modal(b, 0, 180, 0.3, SOFT_WOOD)
		room, tail = ROOM, 0.2

	case .Turn:
		// the world turns: a breath of air rising and settling, a low warmth under it
		b = buffer(1.4, context.temp_allocator)
		DUR :: 0.9
		pk: Pink
		lo: Svf
		for &s, i in b {
			t := time_of(i)
			u := min(t / DUR, 1)
			swell := math.pow(max(math.sin(math.PI * u), 0), 1.6)
			_, air, _ := svf(&lo, pink(&pk, &rng), 240 + 520 * swell, 0.9)
			sub := math.sin(math.TAU * 55 * t) * 0.16 * min(t / 0.3, 1) * math.exp(-max(t - 0.5, 0) * 3)
			s = air * 1.3 * swell + sub
		}
		modal(b, DUR - 0.05, 110, 0.12, SOFT_WOOD[:1], 0.02)
		room, tail = HALL, 1.6

	case .Seam:
		// a way opens: two soft glass notes, far away
		b = buffer(2.0, context.temp_allocator)
		modal(b, 0, 880, 0.2, SOFT_GLASS, 0.012)
		modal(b, 0.14, 1318.51, 0.13, SOFT_GLASS, 0.012)
		tail = 3.5

	case .Lamp_On:
		// the wick catches: a soft breath of flame, a few sparks, the light swells in key
		b = buffer(2.2, context.temp_allocator)
		pk: Pink
		f: Svf
		for &s, i in b {
			t := time_of(i)
			lp, _, _ := svf(&f, pink(&pk, &rng), 260 + 1100 * min(t / 0.15, 1) * math.exp(-max(t - 0.15, 0) * 3), 0.7)
			a := min(t / 0.05, 1)
			s = lp * a * a * math.exp(-t * 3.5) * 0.7
		}
		crackle :: proc(t: f32) -> f32 {return 22 * math.exp(-t * 3)}
		grains(b, &rng, 0.05, 1.0, crackle, 1500, 3500, 0.05, 0.002)
		glow(b, {220, 329.63, 440}, 0.03, 0.45, 0.3, 0.7)
		flute(b, 0.25, 880, 0.35, 0.05, &rng, 0.12, 0.9)
		room, tail = DREAM, 3

	case .Lamp_Off:
		// a soft puff, a thread of smoke
		b = buffer(0.8, context.temp_allocator)
		f, h: Svf
		for &s, i in b {
			t := time_of(i)
			x := noise(&rng)
			_, puff, _ := svf(&f, x, 1000 - 600 * min(t / 0.25, 1), 0.8)
			_, _, smoke := svf(&h, x, 3500, 0.7)
			a := min(t / 0.025, 1)
			s = puff * a * a * math.exp(-t * 8) * 0.8 + smoke * 0.015 * math.exp(-t * 3)
		}
		room, tail = HALL, 1.2

	case .Blocked:
		// no way: two soft knocks of felt
		b = buffer(0.5, context.temp_allocator)
		modal(b, 0, 196, 0.4, SOFT_WOOD, 0.006)
		modal(b, 0.11, 164.81, 0.3, SOFT_WOOD, 0.006)
		room, tail = HALL, 0.9

	case .Tap:
		// a button: a small round drop of sound
		b = buffer(0.4, context.temp_allocator)
		modal(b, 0, 880, 0.3, {{1, 1, 14}, {2, 0.12, 30}}, 0.004)
		room, tail = ROOM, 0.6

	case .Rumble:
		// the seal: stone moving far below, more felt than heard
		b = buffer(3.2, context.temp_allocator)
		brown, am, amt: f32
		for &s, i in b {
			t := time_of(i)
			brown = clamp(brown + noise(&rng) * 0.04, -1, 1) * 0.998
			amt += (fx.randf(&rng) - amt) * coef(4)
			env := min(t / 0.8, 1) * clamp((3.2 - t) / 1.4, 0, 1)
			am += (brown - am) * coef(120)
			s = (am * 1.8 * (0.6 + 0.6 * amt) + math.sin(math.TAU * 41.2 * t) * 0.22) * env
		}
		glow(b, {110, 164.81}, 0.02, 1.2, 1.0, 0.8)
		room, tail = HALL, 2

	case .Thud:
		// a stone settles into place: a soft, deep touch
		b = buffer(0.8, context.temp_allocator)
		f: Svf
		for &s, i in b {
			t := time_of(i)
			hz := 48 + 40 * math.exp(-t * 20)
			a := min(t / 0.008, 1)
			lp, _, _ := svf(&f, noise(&rng), 380, 0.7)
			s = (math.sin(math.TAU * hz * t) * 0.7 + lp * 0.25 * math.exp(-t * 30)) * a * math.exp(-t * 8)
		}
		room, tail = HALL, 1.6

	case .Drip:
		// a drop of oil: a soft rising note in a deep well
		b = buffer(0.3, context.temp_allocator)
		f0 := fx.rand_range(&rng, 900, 1050)
		phase: f32 = 0
		for &s, i in b {
			t := time_of(i)
			phase += math.TAU * f0 * (1 + 0.6 * (1 - math.exp(-t * 30))) / RATE
			s = math.sin(phase) * math.exp(-t * 24) * 0.5 * min(t / 0.003, 1)
		}
		tail = 2.5

	case .Reveal:
		// the face in the lamplight: a chord swells, a flute answers
		b = buffer(5.5, context.temp_allocator)
		glow(b, {110, 164.81, 246.94, 261.63, 329.63}, 0.06, 1.5, 0.8, 1.2) // A minor, add 9
		flute(b, 1.2, 659.25, 0.9, 0.09, &rng, 0.2, 1.2)
		flute(b, 2.1, 880, 1.4, 0.08, &rng, 0.25, 1.6)
		tail = 4.5

	case .Good:
		// something found: a flute arpeggio, legato, over a pad of light
		b = buffer(4.0, context.temp_allocator)
		NOTES :: [5]f32{440, 523.25, 659.25, 880, 1046.5} // A4 C5 E5 A5 C6
		for f, n in NOTES {
			flute(b, f32(n) * 0.17, f, 0.5, 0.1 - f32(n) * 0.012, &rng, 0.07, 1.1)
		}
		glow(b, {220, 329.63, 440}, 0.035, 0.7, 0.8, 1.0)
		tail = 4.5

	case .Wind:
		// Zephyr: soft air and its song, a flute-like voice gliding in the gust
		b = buffer(4.4, context.temp_allocator)
		pk: Pink
		f1, f2: Svf
		drift := fx.rand_range(&rng, -0.3, 0.3)
		for &s, i in b {
			t := time_of(i)
			u := min(t / 4.2, 1)
			gust := math.pow(max(math.sin(math.PI * u), 0), 1.5)
			x := pink(&pk, &rng)
			_, low, _ := svf(&f1, x, 300 + 300 * gust + 60 * math.sin(math.TAU * (0.6 + drift) * t), 0.7)
			_, high, _ := svf(&f2, x, 900 + 500 * gust, 1.6)
			s = (low * 1.0 + high * 0.15) * gust
		}
		// the wind's song: a breathy voice gliding E5 -> A5 -> E5
		song: Svf
		phase: f32 = 0
		for &s, i in b {
			t := time_of(i)
			u := min(t / 4.2, 1)
			gust := math.pow(max(math.sin(math.PI * u), 0), 2)
			freq := 659.25 + 220.75 * (0.5 + 0.5 * math.sin(math.PI * (u - 0.3)))
			phase += math.TAU * freq / RATE
			if phase > math.TAU {
				phase -= math.TAU
			}
			_, breath, _ := svf(&song, noise(&rng), freq, 25)
			s += (math.sin(phase) * 0.05 + breath * 0.5) * gust
		}
		tail = 3.5
	}
	soften(b, SOFT_HZ)
	out := reverb(b, room, tail, allocator)
	// every effect leaves at the same peak: the call sites set the levels
	peak: f32 = 0
	for v in out {
		peak = max(peak, abs(v))
	}
	if peak > 0 {
		for &v in out {
			v *= PEAK / peak
		}
	}
	return out
}

// Round off the highs: two one-pole low-passes.
soften :: proc(b: []f32, hz: f32) {
	a := coef(hz)
	l1, l2: f32
	for &s in b {
		l1 += (s - l1) * a
		l2 += (l1 - l2) * a
		s = l2
	}
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
	case .Forest:
		wind = {0.2, 260, 1100, 0.7}
		crickets, cricket_level = 4, 0.026
	case .River:
		wind = {0.1, 220, 700, 0.5}
		crickets, cricket_level = 1, 0.01
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
	if bed == .River {
		river(raw, m, &rng)
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

// The river: a broad wash of water (pink noise through a slow, wandering
// band), the babble of the current over stones (many small bubbles, each a
// short rising tone), and now and then a bird of the first light.
@(private)
river :: proc(raw: []f32, m: int, rng: ^fx.Rng) {
	for ch in 0 ..< 2 {
		pk: Pink
		f: Svf
		ph := fx.rand_range(rng, 0, 10)
		for i in 0 ..< m {
			t := time_of(i)
			sway := 0.5 + 0.5 * math.sin(0.31 * t + ph) * math.sin(0.13 * t + 2 * ph)
			_, bp, _ := svf(&f, pink(&pk, rng), 520 + 380 * sway, 0.9)
			raw[2 * i + ch] += bp * 0.22
		}
	}
	// bubbles: a few hundred per second would be a torrent; this is a calm river
	for b := 0; b < int(f32(m) / RATE * 26); b += 1 {
		start := int(fx.randf(rng) * f32(m))
		hz := fx.rand_range(rng, 380, 1300)
		dur := fx.rand_range(rng, 0.012, 0.035)
		level := fx.rand_range(rng, 0.004, 0.018)
		pan := fx.rand_range(rng, -0.9, 0.9)
		left, right := math.sqrt(0.5 * (1 - pan)), math.sqrt(0.5 * (1 + pan))
		length := int(dur * RATE)
		phase: f32 = 0
		for k in 0 ..< length {
			i := start + k
			if i >= m {
				break
			}
			u := f32(k) / f32(length)
			phase += math.TAU * hz * (1 + 0.8 * u) / RATE // the pitch rises as the bubble bursts
			v := math.sin(phase) * math.sin(math.PI * u) * (1 - u) * level
			raw[2 * i] += v * left
			raw[2 * i + 1] += v * right
		}
	}
	// the first birds: short whistled phrases, far off
	for start := fx.rand_range(rng, 1, 4); start < f32(m) / RATE - 2; start += fx.rand_range(rng, 3.5, 8) {
		pan := fx.rand_range(rng, -0.85, 0.85)
		left, right := math.sqrt(0.5 * (1 - pan)), math.sqrt(0.5 * (1 + pan))
		base := fx.rand_range(rng, 2600, 3800)
		notes := 2 + int(fx.randf(rng) * 4)
		at := start
		phase: f32 = 0
		for _ in 0 ..< notes {
			dur := fx.rand_range(rng, 0.06, 0.16)
			from := base * fx.rand_range(rng, 0.85, 1.15)
			to := from * fx.rand_range(rng, 0.8, 1.3)
			s0 := int(at * RATE)
			length := int(dur * RATE)
			for k in 0 ..< length {
				i := s0 + k
				if i >= m {
					break
				}
				u := f32(k) / f32(length)
				phase += math.TAU * (from + (to - from) * u) / RATE
				v := math.sin(phase) * math.sin(math.PI * u) * 0.012
				raw[2 * i] += v * left
				raw[2 * i + 1] += v * right
			}
			at += dur + fx.rand_range(rng, 0.03, 0.12)
		}
	}
}

// Feedback delay network reverb: 8 lines, Householder feedback, damping per
// line, two allpasses of diffusion in front; the even lines make the left
// tail, the odd the right, so the space opens wide around a mono source.
Reverb_Params :: struct {
	rt60:     f32, // seconds for the tail to fall 60 dB
	damp_hz:  f32, // the tail darkens above this
	size:     f32, // scales the delay lengths
	wet, dry: f32,
	predelay: f32, // seconds
}

ROOM :: Reverb_Params{0.9, 4000, 0.6, 0.25, 1, 0.008}
STEP_ROOM :: Reverb_Params{0.7, 3500, 0.5, 0.12, 1, 0.006} // the footsteps: barely a room
HALL :: Reverb_Params{2.8, 3400, 1.2, 0.45, 1, 0.022}
DREAM :: Reverb_Params{4.8, 2900, 1.5, 0.6, 0.85, 0.035} // a vast, soft space

// The mono input plus a tail of `tail` seconds, as interleaved stereo.
reverb :: proc(input: []f32, params: Reverb_Params, tail: f32, allocator := context.allocator) -> []f32 {
	LENGTHS :: [8]int{1123, 1291, 1447, 1597, 1789, 1993, 2179, 2357}
	AP :: [2]int{347, 113}
	lengths := LENGTHS
	aps := AP
	n := len(input)
	frames := n + int(tail * RATE)
	out := make([]f32, frames * 2, allocator)

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
	// the tail itself fades out over its last half second
	tail_from := max(frames - int(0.5 * RATE), n)
	for i in 0 ..< frames {
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
		wet: [2]f32
		for k in 0 ..< 8 {
			lines[k][pos[k]] = outs[k] - h + d * 0.35
			pos[k] = (pos[k] + 1) % len(lines[k])
			wet[k % 2] += outs[k]
		}
		fade: f32 = i < tail_from ? 1 : f32(frames - i) / f32(frames - tail_from)
		for side in 0 ..< 2 {
			out[2 * i + side] = (x * params.dry + wet[side] * params.wet * 0.5) * fade
		}
	}
	return out
}

// f32 samples -> signed 16-bit PCM.
to_pcm16 :: proc(samples: []f32, out: []i16) {
	for s, i in samples {
		out[i] = i16(clamp(s, -1, 1) * 32000)
	}
}
