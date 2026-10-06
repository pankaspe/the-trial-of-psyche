// Sound board: every synthesised effect (each take), every ambience bed and
// the generative music of each act, written as WAV files, to listen to them
// outside the game:
// `odin run tools/sound_board -- build/sounds`.
package sound_board

import "core:fmt"
import "core:os"
import "core:time"

import "../../src/audio"

main :: proc() {
	t0 := time.now()
	defer fmt.println("total", time.since(t0))
	dir := len(os.args) > 1 ? os.args[1] : "build/sounds"
	os.make_directory_all(dir)
	for id in audio.Sound_Id {
		if id in audio.RECORDED {
			continue
		}
		for v in 0 ..< audio.VARIANTS[id] {
			b := audio.synthesize(id, v, context.temp_allocator)
			write_wav(fmt.tprintf("%s/%v_%d.wav", dir, id, v), b, 1)
		}
		free_all(context.temp_allocator)
	}
	fmt.println("effects", time.since(t0))
	for bed in audio.Bed {
		if bed == .None {
			continue
		}
		b := audio.synthesize_bed(bed, context.temp_allocator)
		write_wav(fmt.tprintf("%s/bed_%v.wav", dir, bed), b, 2)
		free_all(context.temp_allocator)
	}
	// the generative music of each act: a few minutes, to hear it breathe
	DEMO_S :: 150
	for mood in audio.Mood_Id {
		if mood == .None {
			continue
		}
		g := new(audio.Generator, context.temp_allocator)
		audio.gen_init(g, mood)
		b := make([]f32, 2 * DEMO_S * audio.RATE, context.temp_allocator)
		for at := 0; at < len(b); at += 8192 {
			audio.gen_process(g, b[at:min(at + 8192, len(b))])
		}
		write_wav(fmt.tprintf("%s/music_%v.wav", dir, mood), b, 2)
		free_all(context.temp_allocator)
	}
	fmt.println("written to", dir)
}

write_wav :: proc(path: string, samples: []f32, channels: int) {
	pcm := make([]i16, len(samples), context.temp_allocator)
	audio.to_pcm16(samples, pcm)
	data_size := len(pcm) * 2
	out := make([]u8, 44 + data_size, context.temp_allocator)
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
	put_u16(out, 22, u16(channels))
	put_u32(out, 24, audio.RATE)
	put_u32(out, 28, u32(audio.RATE * 2 * channels))
	put_u16(out, 32, u16(2 * channels))
	put_u16(out, 34, 16)
	copy(out[36:], "data")
	put_u32(out, 40, u32(data_size))
	for v, i in pcm {
		put_u16(out, 44 + i * 2, u16(v))
	}
	_ = os.write_entire_file(path, out)
}
