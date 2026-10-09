// Generative music: each act has a mood, and the music is played live from
// it, never the same twice. Slow pads breathe through a few chords, a lyre
// plucks short phrases now and then, a flute sings long notes, glass bells
// ring far away, all in a vast, soft hall: music heard as in a dream.
// Each act gives its voices a different part: the lyre leads Act I, the
// flute alone Act II, the two answer each other in Act III, a low flute
// barely moves in Act IV. Nothing pulses: there is no beat to follow, only
// space (the music of a place, not of a song).
//
// `gen_process` adds the next frames to an interleaved stereo buffer; the
// mixer calls it on the audio thread, tools/sound_board renders it offline.
package audio

import "core:math"

import "../fx"

Mood_Id :: enum u8 {
	None,
	Title, // the title screen: Psyche's theme on the lyre, tender (A minor)
	Palace, // Act I: the palace of voices, wonder and quiet (A minor)
	Abandonment, // Act II: the land without the palace, colder, sparser (G minor)
	Trials, // Act III: Venus' trials, the helpers busy around her (D minor)
	Underworld, // Act IV: Proserpina's realm, deep and still (E, Phrygian)
}

Chord :: [4]f32 // semitones from the mood's root

// A note of a written phrase: semitones over the lyre's lowest note, and the
// seconds to the next note.
Phrase_Note :: struct {
	semis, wait: f32,
}

Mood :: struct {
	root:        f32, // Hz: the pads' root (octave 2)
	chords:      []Chord,
	chord_s:     [2]f32, // seconds a chord lasts
	scale:       []f32, // the lyre's notes: semitones from the root, one octave
	pad_level:   f32,
	pad_bright:  f32, // Hz: the pads' filter
	drone_level: f32,
	lyre_gap:    [2]f32, // seconds between phrases
	lyre_level:  f32,
	lyre_octave: f32, // the lyre's lowest note, as a ratio over the root
	bell_gap:    [2]f32,
	bell_level:  f32,
	bell_octave: f32,
	flute_gap:    [2]f32, // seconds between the flute's phrases
	flute_level:  f32, // 0: no flute
	flute_octave: f32, // the flute's lowest note, as a ratio over the root
	flute_note:   [2]f32, // seconds a note is held
	motif:       [][]Phrase_Note, // written phrases played in turn (else the lyre wanders)
}

// Psyche's theme: a question that rises and falls back, and its answer.
@(private)
THEME_ASK := []Phrase_Note{{7, 0.55}, {12, 0.55}, {14, 0.55}, {15, 1.1}, {14, 0.55}, {12, 0.55}, {7, 1.6}}
@(private)
THEME_ANSWER := []Phrase_Note{{5, 0.55}, {7, 0.55}, {3, 0.8}, {2, 0.55}, {0, 1.8}}
@(private)
THEME_HIGH := []Phrase_Note{{19, 0.7}, {17, 0.7}, {15, 0.7}, {14, 1.2}, {12, 2}}

MOODS := [Mood_Id]Mood {
	.None = {},
	.Title = {
		root = 110,
		chords = {{-4, 3, 7, 12}, {3, 10, 14, 19}, {0, 7, 14, 15}, {-2, 5, 9, 14}}, // Fmaj7 Cadd9 Am9 G6
		chord_s = {14, 20},
		scale = {0, 3, 5, 7, 10},
		pad_level = 0.1,
		pad_bright = 1700,
		drone_level = 0.04,
		lyre_gap = {7, 10},
		lyre_level = 0.32,
		lyre_octave = 2,
		bell_gap = {18, 30},
		bell_level = 0.05,
		bell_octave = 8,
		flute_gap = {24, 40},
		flute_level = 0.05,
		flute_octave = 4,
		flute_note = {2.2, 3.4},
		motif = {THEME_ASK, THEME_ANSWER, THEME_ASK, THEME_HIGH},
	},
	.Palace = {
		root = 110,
		chords = {{0, 7, 14, 15}, {-4, 3, 7, 12}, {3, 10, 17, 19}, {7, 14, 17, 22}}, // Am9 Fmaj7 Cadd9 Em7
		chord_s = {22, 34},
		scale = {0, 3, 5, 7, 10},
		pad_level = 0.1,
		pad_bright = 1400,
		drone_level = 0.05,
		lyre_gap = {5, 11},
		lyre_level = 0.28,
		lyre_octave = 2,
		bell_gap = {14, 26},
		bell_level = 0.05,
		bell_octave = 8,
		flute_gap = {28, 48},
		flute_level = 0.06,
		flute_octave = 4,
		flute_note = {1.8, 3},
	},
	.Abandonment = {
		root = 98,
		chords = {{0, 7, 14, 15}, {-4, 3, 7, 10}, {3, 10, 14, 17}, {-2, 5, 9, 12}}, // Gm9 Ebmaj9 Bbmaj9 Fmaj9: wide, open
		chord_s = {28, 40},
		scale = {0, 2, 3, 7, 10}, // G A Bb D F: a lonely, open scale
		pad_level = 0.09,
		pad_bright = 1000,
		drone_level = 0.05,
		lyre_gap = {16, 30},
		lyre_level = 0.15,
		lyre_octave = 2,
		bell_gap = {12, 22},
		bell_level = 0.05,
		bell_octave = 8,
		flute_gap = {8, 15},
		flute_level = 0.1,
		flute_octave = 4,
		flute_note = {1.6, 2.8},
	},
	.Trials = {
		root = 73.42,
		chords = {{0, 7, 14, 15}, {5, 12, 14, 19}, {-4, 3, 10, 14}, {-2, 5, 9, 14}}, // Dm9 G6/9 Bbmaj9 C6
		chord_s = {18, 28},
		scale = {0, 3, 5, 7, 10},
		pad_level = 0.09,
		pad_bright = 1700,
		drone_level = 0.05,
		lyre_gap = {4, 9},
		lyre_level = 0.26,
		lyre_octave = 4,
		bell_gap = {16, 30},
		bell_level = 0.04,
		bell_octave = 8,
		flute_gap = {12, 22},
		flute_level = 0.08,
		flute_octave = 4,
		flute_note = {1.2, 2.2},
	},
	.Underworld = {
		root = 82.41,
		chords = {{0, 7, 12, 15}, {1, 8, 13, 17}, {0, 7, 10, 15}, {-2, 5, 10, 14}}, // Em Fmaj Em7 D
		chord_s = {34, 50},
		scale = {0, 1, 5, 7, 8}, // E F A B C: dark, still
		pad_level = 0.1,
		pad_bright = 650,
		drone_level = 0.08,
		lyre_gap = {14, 28},
		lyre_level = 0.14,
		lyre_octave = 2,
		bell_gap = {12, 24},
		bell_level = 0.05,
		bell_octave = 4,
		flute_gap = {12, 22},
		flute_level = 0.09,
		flute_octave = 2,
		flute_note = {3, 5},
	},
}

PAD_HARMONICS :: 6
PAD_FADE_S :: 9.0
LYRE_VOICES :: 8
LYRE_MAX_DELAY :: 1200
BELL_VOICES :: 6
FLUTE_VOICES :: 3

@(private)
Pad_Tone :: struct {
	freq:     f32,
	phase:    [2]f32, // two copies a few cents apart, one per side
	lfo:      f32, // breathing
	lfo_rate: f32,
}

@(private)
Pad_Set :: struct {
	tones:        [4]Pad_Tone,
	fade, target: f32,
}

@(private)
Lyre_Voice :: struct {
	line:   [LYRE_MAX_DELAY]f32,
	length: int,
	pos:    int,
	prev:   f32,
	keep:   f32, // energy kept per round trip
	amp:    f32,
	pan:    f32,
	life:   int, // samples left
}

@(private)
Bell_Voice :: struct {
	freq:  f32,
	phase: [4]f32,
	amp:   f32,
	pan:   f32,
	t:     int,
	life:  int,
}

// The flute: a near-sine with a breath, slow to speak, a late vibrato.
@(private)
Flute_Voice :: struct {
	freq:   f32,
	phase:  f32,
	vib:    f32, // the vibrato's phase
	breath: Svf,
	amp:    f32,
	pan:    f32,
	t:      int, // samples since the note began
	hold:   int, // samples it is held, then it dies away
	life:   int, // samples left
}

// A stereo hall: 8 delay lines with Householder feedback, even lines to the
// left, odd to the right.
@(private)
Hall :: struct {
	lines: [8][4096]f32,
	len:   [8]int,
	pos:   [8]int,
	damp:  [8]f32,
	gain:  [8]f32,
	a:     f32,
}

Generator :: struct {
	mood:       Mood,
	rng:        fx.Rng,
	sets:       [2]Pad_Set,
	current:    int,
	chord:      int,
	next_chord: int, // samples to the next chord
	bright:     f32, // 0..1 breathing of the pads' filter
	bright_ph:  f32,
	lp:         [2][2]f32,
	drone_ph:   f32,
	lyre:       [LYRE_VOICES]Lyre_Voice,
	next_phrase: int,
	phrase_left: int,
	next_note:  int,
	degree:     int,
	motif_i:    int, // the next written phrase
	phrase:     []Phrase_Note, // the written phrase playing (nil: wandering)
	note_i:     int,
	bells:      [BELL_VOICES]Bell_Voice,
	next_bell:  int,
	flutes:     [FLUTE_VOICES]Flute_Voice,
	next_flute_phrase: int,
	flute_left: int, // notes left in the flute's phrase
	next_flute: int,
	flute_degree: int,
	hall:       Hall,
}

@(private)
seconds :: proc(g: ^Generator, r: [2]f32) -> int {
	return int(fx.rand_range(&g.rng, r[0], r[1]) * RATE)
}

gen_init :: proc(g: ^Generator, mood: Mood_Id, seed: u32 = 1) {
	g^ = {}
	g.mood = MOODS[mood]
	g.rng = fx.rng_init(seed + u32(mood) * 101)
	set_chord(g, 0, 0, 1)
	g.sets[0].fade = 0 // fades in from silence
	g.next_chord = seconds(g, g.mood.chord_s)
	g.next_phrase = seconds(g, {3, 6})
	g.next_bell = seconds(g, g.mood.bell_gap)
	g.next_flute_phrase = seconds(g, {g.mood.flute_gap[0] * 0.5, g.mood.flute_gap[1] * 0.5})
	g.degree = 5
	g.flute_degree = 4

	LENGTHS :: [8]int{1777, 2039, 2297, 2549, 2833, 3121, 3389, 3671}
	lengths := LENGTHS
	RT60 :: 8.5 // a vast, soft hall
	for k in 0 ..< 8 {
		g.hall.len[k] = lengths[k]
		g.hall.gain[k] = math.pow(10, -3 * f32(lengths[k]) / (RT60 * RATE))
	}
	g.hall.a = coef(2600)
}

@(private)
set_chord :: proc(g: ^Generator, set, chord: int, target: f32) {
	s := &g.sets[set]
	for &tone, k in s.tones {
		tone.freq = g.mood.root * semitones(g.mood.chords[chord][k])
		tone.lfo = fx.rand_range(&g.rng, 0, math.TAU)
		tone.lfo_rate = math.TAU / fx.rand_range(&g.rng, 11, 29) / RATE
	}
	s.target = target
	g.chord = chord
}

@(private)
lyre_note :: proc(g: ^Generator, written: Maybe(f32) = nil) {
	semis: f32
	if w, ok := written.?; ok {
		semis = w
	} else {
		// a gentle random walk over two octaves of the scale
		n := len(g.mood.scale)
		step := [?]int{-2, -1, -1, 1, 1, 2}
		g.degree = clamp(g.degree + step[int(fx.randf(&g.rng) * len(step)) % len(step)], 0, 2 * n - 1)
		semis = g.mood.scale[g.degree % n] + 12 * f32(g.degree / n)
	}
	freq := g.mood.root * g.mood.lyre_octave * semitones(semis)
	for &v in g.lyre {
		if v.life > 0 {
			continue
		}
		v.length = clamp(int(RATE / freq), 2, LYRE_MAX_DELAY)
		v.pos, v.prev = 0, 0
		lp: f32 = 0
		for k in 0 ..< v.length {
			lp += (noise(&g.rng) - lp) * 0.22 // a soft finger, not a pick
			v.line[k] = lp
		}
		v.keep = 0.9965
		v.amp = g.mood.lyre_level * fx.rand_range(&g.rng, 0.55, 1)
		v.pan = fx.rand_range(&g.rng, -0.4, 0.4)
		v.life = 5 * RATE
		return
	}
}

@(private)
bell_note :: proc(g: ^Generator) {
	pick := [?]f32{0, 7, 12, 3}
	semis := pick[int(fx.randf(&g.rng) * len(pick)) % len(pick)]
	for &b in g.bells {
		if b.life > 0 {
			continue
		}
		b = {}
		b.freq = g.mood.root * g.mood.bell_octave * semitones(semis)
		b.amp = g.mood.bell_level * fx.rand_range(&g.rng, 0.6, 1)
		b.pan = fx.rand_range(&g.rng, -0.7, 0.7)
		b.life = 6 * RATE
		return
	}
}

// The flute's next note: a slow walk over the scale, held a long time.
@(private)
flute_note :: proc(g: ^Generator) {
	n := len(g.mood.scale)
	step := [?]int{-1, -1, 1, 1, 2, -2, 0}
	g.flute_degree = clamp(g.flute_degree + step[int(fx.randf(&g.rng) * len(step)) % len(step)], 0, 2 * n - 1)
	semis := g.mood.scale[g.flute_degree % n] + 12 * f32(g.flute_degree / n)
	for &v in g.flutes {
		if v.life > 0 {
			continue
		}
		v = {}
		v.freq = g.mood.root * g.mood.flute_octave * semitones(semis)
		v.vib = fx.rand_range(&g.rng, 0, math.TAU)
		v.amp = g.mood.flute_level * fx.rand_range(&g.rng, 0.75, 1)
		v.pan = fx.rand_range(&g.rng, -0.35, 0.35)
		v.hold = seconds(g, g.mood.flute_note)
		v.life = v.hold + 3 * RATE
		return
	}
}

// Add `frames` stereo frames of music to out (interleaved).
gen_process :: proc(g: ^Generator, out: []f32) {
	m := &g.mood
	frames := len(out) / 2
	fade_step := f32(1) / (PAD_FADE_S * RATE)
	for i in 0 ..< frames {
		// --- the score: chords, phrases, bells
		g.next_chord -= 1
		if g.next_chord <= 0 {
			next := (g.chord + 1 + int(fx.randf(&g.rng) * f32(len(m.chords) - 1))) % len(m.chords)
			g.sets[g.current].target = 0
			g.current = 1 - g.current
			set_chord(g, g.current, next, 1)
			g.next_chord = seconds(g, m.chord_s)
		}
		g.next_phrase -= 1
		if g.next_phrase <= 0 {
			if len(m.motif) > 0 {
				g.phrase = m.motif[g.motif_i % len(m.motif)]
				g.motif_i += 1
				g.note_i = 0
				g.phrase_left = len(g.phrase)
			} else {
				g.phrase = nil
				g.phrase_left = 1 + int(fx.randf(&g.rng) * 4)
			}
			g.next_note = 0
			g.next_phrase = seconds(g, m.lyre_gap)
		}
		if g.phrase_left > 0 {
			g.next_note -= 1
			if g.next_note <= 0 {
				if g.phrase != nil {
					// a written note, played a little freely (rubato)
					note := g.phrase[g.note_i]
					lyre_note(g, note.semis)
					g.note_i += 1
					g.next_note = int(note.wait * fx.rand_range(&g.rng, 0.92, 1.12) * RATE)
				} else {
					lyre_note(g)
					g.next_note = seconds(g, {0.35, 0.9})
				}
				g.phrase_left -= 1
			}
		}
		g.next_bell -= 1
		if g.next_bell <= 0 {
			bell_note(g)
			g.next_bell = seconds(g, m.bell_gap)
		}
		if m.flute_level > 0 {
			g.next_flute_phrase -= 1
			if g.next_flute_phrase <= 0 {
				g.flute_left = 2 + int(fx.randf(&g.rng) * 3)
				g.next_flute = 0
				g.next_flute_phrase = seconds(g, m.flute_gap)
			}
			if g.flute_left > 0 {
				g.next_flute -= 1
				if g.next_flute <= 0 {
					flute_note(g)
					g.flute_left -= 1
					// legato: the next note begins as this one is let go
					g.next_flute = int(fx.rand_range(&g.rng, m.flute_note[0], m.flute_note[1]) * RATE)
				}
			}
		}

		// --- pads: additive tones, slightly detuned left and right
		pad: [2]f32
		for &s in g.sets {
			s.fade = s.target > s.fade ? min(s.fade + fade_step, s.target) : max(s.fade - fade_step, s.target)
			if s.fade <= 0 {
				continue
			}
			level := math.sin(s.fade * math.PI / 2) * m.pad_level
			for &tone in s.tones {
				tone.lfo += tone.lfo_rate
				breath := 0.55 + 0.45 * math.sin(tone.lfo)
				for side in 0 ..< 2 {
					detune: f32 = side == 0 ? 0.9988 : 1.0012 // two cents each way
					tone.phase[side] += math.TAU * tone.freq * detune / RATE
					if tone.phase[side] > math.TAU {
						tone.phase[side] -= math.TAU
					}
					s1, c1 := math.sin(tone.phase[side]), math.cos(tone.phase[side])
					prev, cur: f32 = 0, s1
					v: f32 = 0
					for n in 1 ..= PAD_HARMONICS {
						v += cur / math.pow(f32(n), 1.6)
						prev, cur = cur, 2 * c1 * cur - prev
					}
					pad[side] += v * breath * level
				}
			}
		}
		g.bright_ph += math.TAU / (37 * RATE)
		cutoff := m.pad_bright * (0.75 + 0.35 * math.sin(g.bright_ph))
		a := coef(cutoff)
		for side in 0 ..< 2 {
			g.lp[side][0] += (pad[side] - g.lp[side][0]) * a
			g.lp[side][1] += (g.lp[side][0] - g.lp[side][1]) * a
			pad[side] = g.lp[side][1]
		}

		// --- drone: the ground under everything
		g.drone_ph += math.TAU * m.root * 0.5 / RATE
		if g.drone_ph > math.TAU {
			g.drone_ph -= math.TAU
		}
		drone := (math.sin(g.drone_ph) + math.sin(2 * g.drone_ph) * 0.25) * m.drone_level

		// --- lyre
		lyre: [2]f32
		for &v in g.lyre {
			if v.life <= 0 {
				continue
			}
			y := v.line[v.pos]
			v.line[v.pos] = (y + v.prev) * 0.5 * v.keep
			v.prev = y
			v.pos = (v.pos + 1) % v.length
			v.life -= 1
			x := y * v.amp
			lyre[0] += x * (1 - v.pan) * 0.5
			lyre[1] += x * (1 + v.pan) * 0.5
		}

		// --- bells: glass partials
		bell: [2]f32
		for &b in g.bells {
			if b.life <= 0 {
				continue
			}
			t := f32(b.t) / RATE
			v: f32 = 0
			for p, k in GLASS {
				b.phase[k] += math.TAU * b.freq * p.ratio / RATE
				v += math.sin(b.phase[k]) * p.gain * math.exp(-t * p.decay * 0.6)
			}
			v *= b.amp * min(t / 0.004, 1)
			bell[0] += v * (1 - b.pan) * 0.5
			bell[1] += v * (1 + b.pan) * 0.5
			b.t += 1
			b.life -= 1
		}

		// --- flute
		flute: [2]f32
		for &v in g.flutes {
			if v.life <= 0 {
				continue
			}
			t := f32(v.t) / RATE
			rise := min(t / 0.35, 1)
			env := rise * rise * (3 - 2 * rise)
			if v.t > v.hold {
				env *= math.exp(-f32(v.t - v.hold) / RATE * 2.2)
			}
			depth := 0.0045 * clamp((t - 0.5) / 1.0, 0, 1)
			v.vib += math.TAU * 4.8 / RATE
			v.phase += math.TAU * v.freq * (1 + depth * math.sin(v.vib)) / RATE
			if v.phase > math.TAU {
				v.phase -= math.TAU
			}
			_, br, _ := svf(&v.breath, noise(&g.rng), v.freq * 2, 3)
			x := (math.sin(v.phase) + 0.1 * math.sin(2 * v.phase) + br * (0.04 + 0.2 * math.exp(-t * 6))) * env * v.amp
			flute[0] += x * (1 - v.pan) * 0.5
			flute[1] += x * (1 + v.pan) * 0.5
			v.t += 1
			v.life -= 1
		}

		// --- the hall
		send := (pad[0] + pad[1]) * 0.25 + (lyre[0] + lyre[1]) * 0.45 + (bell[0] + bell[1]) * 0.6 + (flute[0] + flute[1]) * 0.55
		h := &g.hall
		outs: [8]f32
		sum: f32 = 0
		for k in 0 ..< 8 {
			o := h.lines[k][h.pos[k]]
			h.damp[k] += (o - h.damp[k]) * h.a
			outs[k] = h.damp[k] * h.gain[k]
			sum += outs[k]
		}
		hh := sum * 2 / 8
		wet: [2]f32
		for k in 0 ..< 8 {
			h.lines[k][h.pos[k]] = outs[k] - hh + send * 0.3
			h.pos[k] = (h.pos[k] + 1) % h.len[k]
			wet[k % 2] += outs[k]
		}
		for side in 0 ..< 2 {
			out[2 * i + side] += pad[side] * 0.55 + drone * 0.6 + lyre[side] * 1.0 + bell[side] * 0.6 + flute[side] * 0.9 + wet[side] * 0.45
		}
	}
}
