// The sound of a recorded video, rebuilt offline in sync with its frames.
//
// A video recorded with `--shots DIR --level ID --plan --record` runs on a
// steady clock, not in real time, so its sound cannot be captured live; the
// game writes DIR/sounds.txt instead (every effect played, at the video's
// clock). This tool mixes, at 44.1 kHz stereo:
//   video_audio effects DIR/sounds.txt OUT.wav   the place's ambience and the effects
//   video_audio music MOOD SECONDS OUT.wav       the generative music of a mood
// with the game's own levels (ambience and music as the mixer plays them).
package video_audio

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"

import "../../src/audio"
import "../../src/fx"

RATE :: audio.RATE

main :: proc() {
	args := os.args
	if len(args) == 5 && args[1] == "music" {
		mood, ok := enum_named(audio.Mood_Id, args[2])
		seconds, ok2 := strconv.parse_f32(args[3])
		if !ok || !ok2 {
			fail("unknown mood or length")
		}
		out := make([]f32, 2 * int(seconds * RATE))
		g := new(audio.Generator)
		audio.gen_init(g, mood, 3)
		for at := 0; at < len(out); at += 8192 {
			audio.gen_process(g, out[at:min(at + 8192, len(out))])
		}
		gain := audio.db_to_linear(audio.MUSIC_BASE_DB) * audio.GEN_TRIM
		for &v in out {
			v *= gain
		}
		write_wav(args[4], out)
		return
	}
	if len(args) == 4 && args[1] == "effects" {
		effects(args[2], args[3])
		return
	}
	fail("usage: video_audio effects SOUNDS.txt OUT.wav | video_audio music MOOD SECONDS OUT.wav")
}

fail :: proc(msg: string) -> ! {
	fmt.eprintln(msg)
	os.exit(2)
}

enum_named :: proc($E: typeid, name: string) -> (E, bool) {
	for v in E {
		if fmt.tprint(v) == name {
			return v, true
		}
	}
	return {}, false
}

effects :: proc(log_path, out_path: string) {
	data, err := os.read_entire_file_from_path(log_path, context.allocator)
	if err != nil {
		fail("cannot read the sound log")
	}
	bed := audio.Bed.None
	seconds: f32 = 0
	events: [dynamic]audio.Event
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		f := strings.fields(line, context.temp_allocator)
		switch {
		case len(f) == 2 && f[0] == "bed":
			bed, _ = enum_named(audio.Bed, f[1])
		case len(f) == 3 && f[0] == "frames":
			frames, _ := strconv.parse_f32(f[1])
			fps, _ := strconv.parse_f32(f[2])
			seconds = frames / fps
		case len(f) == 5:
			e: audio.Event
			e.t, _ = strconv.parse_f32(f[0])
			ok: bool
			e.id, ok = enum_named(audio.Sound_Id, f[1])
			e.volume_db, _ = strconv.parse_f32(f[2])
			e.pitch, _ = strconv.parse_f32(f[3])
			e.pan, _ = strconv.parse_f32(f[4])
			if ok {
				append(&events, e)
			}
		}
	}
	n := int((seconds + 1) * RATE)
	out := make([]f32, 2 * n)

	// the ambience, as the mixer plays it
	loop := audio.synthesize_bed(bed)
	if len(loop) > 0 {
		g := audio.db_to_linear(audio.BED_BASE_DB)
		for i in 0 ..< n {
			k := i % (len(loop) / 2)
			out[2 * i] += loop[2 * k] * g
			out[2 * i + 1] += loop[2 * k + 1] * g
		}
	}

	// the effects: a take at random, resampled for the pitch, panned
	takes: [audio.Sound_Id][dynamic][]f32
	rng := fx.rng_init(9)
	for e in events {
		if len(takes[e.id]) == 0 {
			load_takes(e.id, &takes[e.id])
		}
		list := takes[e.id][:]
		src := list[int(fx.randf(&rng) * f32(len(list))) % len(list)]
		gain := audio.db_to_linear(e.volume_db + audio.SFX_BASE_DB)
		left := gain * min(1 - e.pan, 1)
		right := gain * min(1 + e.pan, 1)
		start := int(e.t * RATE)
		frames := len(src) / 2
		for pos: f32 = 0; int(pos) + 1 < frames; pos += e.pitch {
			i := start + int(pos / e.pitch)
			if i >= n {
				break
			}
			k := int(pos)
			fr := pos - f32(k)
			l := src[2 * k] * (1 - fr) + src[2 * k + 2] * fr
			r := src[2 * k + 1] * (1 - fr) + src[2 * k + 3] * fr
			out[2 * i] += l * left
			out[2 * i + 1] += r * right
		}
	}
	write_wav(out_path, out)
	fmt.printfln("%s: %.2f s, %d effects, ambience %v", out_path, seconds, len(events), bed)
}

// Every take of an effect, interleaved stereo at RATE: the recordings decoded, or synthesised.
load_takes :: proc(id: audio.Sound_Id, list: ^[dynamic][]f32) {
	if id in audio.RECORDED {
		files := id == .Step_Grass ? audio.STEPS_GRASS[:] : audio.STEPS_STONE[:]
		for f in files {
			append(list, audio.step_take(f))
		}
		return
	}
	for v in 0 ..< max(audio.VARIANTS[id], 1) {
		append(list, audio.synthesize(id, v))
	}
}

// Interleaved stereo f32 -> 16-bit WAV.
write_wav :: proc(path: string, samples: []f32) {
	data_size := len(samples) * 2
	out := make([]u8, 44 + data_size)
	put_u32 :: proc(b: []u8, at: int, v: u32) {
		b[at], b[at + 1], b[at + 2], b[at + 3] = u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24)
	}
	put_u16 :: proc(b: []u8, at: int, v: u16) {
		b[at], b[at + 1] = u8(v), u8(v >> 8)
	}
	copy(out[0:], "RIFF")
	put_u32(out, 4, u32(36 + data_size))
	copy(out[8:], "WAVEfmt ")
	put_u32(out, 16, 16)
	put_u16(out, 20, 1)
	put_u16(out, 22, 2)
	put_u32(out, 24, RATE)
	put_u32(out, 28, RATE * 4)
	put_u16(out, 32, 4)
	put_u16(out, 34, 16)
	copy(out[36:], "data")
	put_u32(out, 40, u32(data_size))
	for v, i in samples {
		put_u16(out, 44 + i * 2, u16(i16(math.clamp(v, -1, 1) * 32000)))
	}
	if err := os.write_entire_file(path, out); err != nil {
		fail("cannot write the WAV")
	}
}
