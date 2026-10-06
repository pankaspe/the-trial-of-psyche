// Loop finder for the act soundtracks: `tools/music_prep.sh` runs it.
//
// A track is longer than a song needs to be heard once, shorter than an act:
// when it ends, the player jumps from a late point A back to an earlier point
// B with a short crossfade, and the jump must not be heard as "the track
// starts again". The tool looks for the pair (A, B) where the music around A
// sounds most like the music around B: same harmony (chroma), same weight in
// every band, over several seconds on both sides; then it aligns B on A's
// pulse (onset envelope) to a few milliseconds.
//
// Input: raw mono f32 little-endian samples at RATE (ffmpeg -ac 1 -ar 11025
// -f f32le). Output: candidate pairs, best first, in seconds and in samples
// at 44100 Hz (the rate of the OGG files the game plays).
package music_loop

import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import "core:strconv"

RATE :: 11025
FRAME :: 2048 // FFT size (186 ms)
HOP :: 512 // feature hop (46 ms)
WINDOW :: 128 // frames compared on each side of the jump (6 s); a second argument sets it in seconds
BANDS :: 8
GAME_RATE :: 44100

Feature :: struct {
	chroma: [12]f32, // unit length
	bands:  [BANDS]f32, // dB
}

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprintln("usage: music_loop <mono f32le at 11025 Hz>")
		os.exit(2)
	}
	data, err := os.read_entire_file_from_path(os.args[1], context.allocator)
	if err != nil {
		fmt.eprintln("cannot read", os.args[1], err)
		os.exit(1)
	}
	samples := slice.reinterpret([]f32, data)
	length_s := f32(len(samples)) / RATE

	feats := features(samples)
	n := len(feats)
	frame_s :: f32(HOP) / RATE
	w := WINDOW
	if len(os.args) > 2 {
		if sec, ok := strconv.parse_f32(os.args[2]); ok {
			w = int(sec * RATE / HOP)
		}
	}

	// Where the music is: the outro fades, so A must stay before it.
	loud := make([]f32, n)
	for f, i in feats {
		bands := f.bands
		loud[i] = slice.max(bands[:])
	}
	peak := slice.max(loud)
	last_full := n - 1
	for last_full > 0 && loud[last_full] < peak - 12 {
		last_full -= 1
	}

	to_frame :: proc(sec: f32) -> int {return int(sec / frame_s)}
	a_lo, a_hi := to_frame(length_s * 0.55), min(last_full - w, n - w - 1)
	b_lo, b_hi := to_frame(10), to_frame(length_s * 0.45)
	min_span := to_frame(length_s * 0.4)

	Candidate :: struct {
		cost: f32,
		a, b: int,
	}
	cands: [dynamic]Candidate
	diag := make([]f32, n)
	prefix := make([]f32, n + 1)
	for lag in min_span ..= a_hi - b_lo {
		// distances along the diagonal i <-> i - lag
		for i in lag ..< n {
			diag[i] = distance(feats[i], feats[i - lag])
		}
		prefix[lag] = 0
		for i in lag ..< n {
			prefix[i + 1] = prefix[i] + diag[i]
		}
		for a in max(a_lo, b_lo + lag) ..= min(a_hi, b_hi + lag) {
			if a - w < lag {
				continue
			}
			cost := (prefix[a + w] - prefix[a - w]) / f32(2 * w)
			append(&cands, Candidate{cost, a, a - lag})
		}
	}
	slice.sort_by(cands[:], proc(x, y: Candidate) -> bool {return x.cost < y.cost})

	env := onset_envelope(samples)
	fmt.printfln("length %.2f s, music until %.2f s, %d pairs", length_s, f32(last_full) * frame_s, len(cands))
	fmt.println("rank  cost    A (s)    B (s)   shift(ms)  A (44100)  B (44100)")
	picked: [dynamic]Candidate
	outer: for c in cands {
		for p in picked {
			if abs(p.a - c.a) < to_frame(4) && abs(p.b - c.b) < to_frame(4) {
				continue outer
			}
		}
		append(&picked, c)
		a_smp := c.a * HOP + FRAME / 2
		b_smp := c.b * HOP + FRAME / 2
		shift := align(env, a_smp, b_smp)
		b_smp += shift
		fmt.printfln(
			"%2d   %.4f  %7.2f  %7.2f  %+6.1f   %9d  %9d",
			len(picked),
			c.cost,
			f32(a_smp) / RATE,
			f32(b_smp) / RATE,
			f32(shift) * 1000 / RATE,
			a_smp * (GAME_RATE / RATE),
			b_smp * (GAME_RATE / RATE),
		)
		if len(picked) == 8 {
			break
		}
	}
}

distance :: proc(x, y: Feature) -> f32 {
	dot: f32 = 0
	for k in 0 ..< 12 {
		dot += x.chroma[k] * y.chroma[k]
	}
	db: f32 = 0
	for k in 0 ..< BANDS {
		db += abs(x.bands[k] - y.bands[k])
	}
	return (1 - dot) + 0.04 * db / BANDS
}

features :: proc(samples: []f32) -> []Feature {
	n := max((len(samples) - FRAME) / HOP, 0)
	out := make([]Feature, n)
	re := make([]f32, FRAME)
	im := make([]f32, FRAME)
	hann := make([]f32, FRAME)
	for i in 0 ..< FRAME {
		hann[i] = 0.5 - 0.5 * math.cos(math.TAU * f32(i) / FRAME)
	}
	BAND_EDGES :: [BANDS + 1]f32{40, 80, 160, 320, 640, 1280, 2560, 4000, 5500}
	edges := BAND_EDGES
	for &f, fi in out {
		s0 := fi * HOP
		for i in 0 ..< FRAME {
			re[i] = samples[s0 + i] * hann[i]
			im[i] = 0
		}
		fft(re, im)
		for k in 1 ..< FRAME / 2 {
			hz := f32(k) * RATE / FRAME
			mag := math.sqrt(re[k] * re[k] + im[k] * im[k])
			if hz >= 65 && hz <= 2000 {
				// pitch class, A = 0
				pc := int(math.round(12 * math.log2(hz / 440))) %% 12
				f.chroma[pc] += mag
			}
			for b in 0 ..< BANDS {
				if hz >= edges[b] && hz < edges[b + 1] {
					f.bands[b] += mag * mag
				}
			}
		}
		norm: f32 = 0
		for v in f.chroma {
			norm += v * v
		}
		norm = math.sqrt(norm) + 1e-9
		for &v in f.chroma {
			v /= norm
		}
		for &v in f.bands {
			v = 10 * math.log10(v + 1e-9)
		}
	}
	return out
}

// In-place radix-2 FFT (len a power of two).
fft :: proc(re, im: []f32) {
	n := len(re)
	j := 0
	for i in 1 ..< n {
		bit := n >> 1
		for j & bit != 0 {
			j ~= bit
			bit >>= 1
		}
		j |= bit
		if i < j {
			re[i], re[j] = re[j], re[i]
			im[i], im[j] = im[j], im[i]
		}
	}
	for size := 2; size <= n; size <<= 1 {
		ang := -math.TAU / f32(size)
		for start := 0; start < n; start += size {
			for k in 0 ..< size / 2 {
				c, s := math.cos(ang * f32(k)), math.sin(ang * f32(k))
				a, b := start + k, start + k + size / 2
				tr := re[b] * c - im[b] * s
				ti := re[b] * s + im[b] * c
				re[b], im[b] = re[a] - tr, im[a] - ti
				re[a], im[a] = re[a] + tr, im[a] + ti
			}
		}
	}
}

ENV_HOP :: 32 // ~3 ms

// Positive changes of the energy: where notes and beats start.
onset_envelope :: proc(samples: []f32) -> []f32 {
	n := len(samples) / ENV_HOP
	energy := make([]f32, n)
	for i in 0 ..< n {
		e: f32 = 0
		for v in samples[i * ENV_HOP:][:ENV_HOP] {
			e += v * v
		}
		energy[i] = math.log10(e + 1e-6)
	}
	out := make([]f32, n)
	for i in 1 ..< n {
		out[i] = max(energy[i] - energy[i - 1], 0)
	}
	return out
}

// Shift (samples) to add to b so the pulse after b matches the pulse after a.
align :: proc(env: []f32, a, b: int) -> int {
	SPAN :: 4 * RATE / ENV_HOP
	MAX_SHIFT :: RATE / 4 / ENV_HOP
	ea, eb := a / ENV_HOP, b / ENV_HOP
	best, best_score := 0, f32(-1)
	for d in -MAX_SHIFT ..= MAX_SHIFT {
		score: f32 = 0
		for k in -SPAN ..< SPAN {
			i, j := ea + k, eb + d + k
			if i < 0 || j < 0 || i >= len(env) || j >= len(env) {
				continue
			}
			score += env[i] * env[j]
		}
		if score > best_score {
			best, best_score = d, score
		}
	}
	return best * ENV_HOP
}
