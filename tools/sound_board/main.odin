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
			write_wav(fmt.tprintf("%s/%v_%d.wav", dir, id, v), b, 2)
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
	_ = os.write_entire_file(path, audio.wav_file(samples, channels, context.temp_allocator))
}
