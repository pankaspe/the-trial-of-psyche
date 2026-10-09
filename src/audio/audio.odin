// Playback through raylib: effects, the act soundtrack, the ambience.
//
// Effects are recordings (the footsteps, assets/sfx, embedded at compile
// time) or synthesised at startup (synth.odin) on a thread of their own, so
// the game starts at once (an effect asked before its samples are ready is
// skipped), each in a few takes; a play
// picks a take at random, never the same twice in a row, so repeated sounds
// stay alive. The soundtrack and the ambience go through the mixer
// (music.odin). Calls are no-ops when there is no audio device (headless
// tests), so game code never has to check.
package audio

import "base:runtime"
import "core:math"
import "core:sync"
import "core:thread"
import rl "vendor:raylib"

import "../fx"

SLOTS :: 6 // sounds per effect: its takes, then aliases so they can overlap
MUSIC_BASE_DB :: -10.0
BED_BASE_DB :: -6.0
SFX_BASE_DB :: -3.0 // the effects sit softly under the music

STEPS_GRASS := [?][]u8 {
	#load("../../assets/sfx/step_grass_0.ogg"),
	#load("../../assets/sfx/step_grass_1.ogg"),
	#load("../../assets/sfx/step_grass_2.ogg"),
	#load("../../assets/sfx/step_grass_3.ogg"),
	#load("../../assets/sfx/step_grass_4.ogg"),
}
STEPS_STONE := [?][]u8 {
	#load("../../assets/sfx/step_stone_0.ogg"),
	#load("../../assets/sfx/step_stone_1.ogg"),
	#load("../../assets/sfx/step_stone_2.ogg"),
	#load("../../assets/sfx/step_stone_3.ogg"),
	#load("../../assets/sfx/step_stone_4.ogg"),
	#load("../../assets/sfx/step_stone_5.ogg"),
}

@(private)
State :: struct {
	ready:  bool,
	sounds: [Sound_Id][SLOTS]rl.Sound,
	owned:  [Sound_Id][SLOTS]bool, // owns its samples (else an alias)
	count:  [Sound_Id]int, // 0 until its samples are loaded
	last:   [Sound_Id]int,
	rng:    fx.Rng,
	key:    f32, // pitch ratio of the act's key against A
	master: f32,
	music:  f32,
	sfx:    f32,
	worker: ^thread.Thread,
	baked:  [Sound_Id][SLOTS][]i16, // the worker's samples, until uploaded
	done:   bool, // the worker has finished (atomic)
}

@(private)
s: State

// The ambience loops, interleaved stereo 16-bit (read by the mixer thread
// once beds_ready is set).
@(private)
beds: [Bed][]i16
@(private)
beds_ready: bool

db_to_linear :: proc(db: f32) -> f32 {
	return math.pow(10, db / 20)
}

// Open the device, load the recordings, start the mixer and the worker that
// synthesises the rest. Samples are allocated from the heap (the worker has
// its own context): effects until update uploads them, the ambience loops
// until shutdown.
init :: proc() {
	s = {}
	s.master, s.music, s.sfx, s.key = 1, 1, 1, 1
	s.rng = fx.rng_init(11)
	rl.InitAudioDevice()
	if !rl.IsAudioDeviceReady() {
		return
	}
	s.ready = true

	for id in RECORDED {
		files := id == .Step_Grass ? STEPS_GRASS[:] : STEPS_STONE[:]
		takes := 0
		for f in files[:min(len(files), SLOTS)] {
			samples := step_take(f, context.temp_allocator)
			pcm := make([]i16, len(samples), context.temp_allocator)
			to_pcm16(samples, pcm)
			wave := rl.Wave{frameCount = u32(len(pcm) / 2), sampleRate = RATE, sampleSize = 16, channels = 2, data = raw_data(pcm)}
			s.sounds[id][takes] = rl.LoadSoundFromWave(wave) // copies the samples
			s.owned[id][takes] = true
			takes += 1
		}
		finish_slots(id, takes)
	}
	mixer_start()
	apply_volumes()
	s.worker = thread.create_and_start(bake)
}

// A recorded footstep (OGG) as the game plays it: its highs rounded off, in a
// small room, interleaved stereo at RATE.
step_take :: proc(ogg: []u8, allocator := context.allocator) -> []f32 {
	w := rl.LoadWaveFromMemory(".ogg", raw_data(ogg), i32(len(ogg)))
	defer rl.UnloadWave(w)
	rl.WaveFormat(&w, RATE, 32, 1)
	raw := rl.LoadWaveSamples(w)
	defer rl.UnloadWaveSamples(raw)
	dry := make([]f32, int(w.frameCount), context.temp_allocator)
	copy(dry, raw[:w.frameCount])
	soften(dry, SOFT_HZ)
	return reverb(dry, STEP_ROOM, 0.35, allocator)
}

// The worker: every synthesised take, then the ambience loops.
@(private)
bake :: proc() {
	heap := runtime.heap_allocator()
	for id in Sound_Id {
		if id in RECORDED {
			continue
		}
		for v in 0 ..< min(VARIANTS[id], SLOTS) {
			samples := synthesize(id, v, context.temp_allocator)
			s.baked[id][v] = make([]i16, len(samples), heap)
			to_pcm16(samples, s.baked[id][v])
			free_all(context.temp_allocator)
		}
	}
	sync.atomic_store(&s.done, true)
	for bed in Bed {
		samples := synthesize_bed(bed, context.temp_allocator)
		if len(samples) > 0 {
			beds[bed] = make([]i16, len(samples), heap)
			to_pcm16(samples, beds[bed])
		}
		free_all(context.temp_allocator)
	}
	sync.atomic_store(&beds_ready, true)
}

// Call once per frame: the effects become playable when the worker is done.
update :: proc() {
	if !s.ready || s.worker == nil || !sync.atomic_load(&s.done) {
		return
	}
	for id in Sound_Id {
		if id in RECORDED {
			continue
		}
		takes := 0
		for pcm in s.baked[id] {
			if pcm == nil {
				continue
			}
			wave := rl.Wave {
				frameCount = u32(len(pcm) / 2),
				sampleRate = RATE,
				sampleSize = 16,
				channels   = 2,
				data       = raw_data(pcm),
			}
			s.sounds[id][takes] = rl.LoadSoundFromWave(wave) // copies the samples
			s.owned[id][takes] = true
			takes += 1
			delete(pcm, runtime.heap_allocator())
		}
		s.baked[id] = {}
		finish_slots(id, takes)
	}
	thread.join(s.worker)
	thread.destroy(s.worker)
	s.worker = nil
}

// The slots after the takes replay them, so an effect can overlap itself.
@(private)
finish_slots :: proc(id: Sound_Id, takes: int) {
	for k in takes ..< SLOTS {
		s.sounds[id][k] = rl.LoadSoundAlias(s.sounds[id][k % takes])
	}
	s.count[id] = SLOTS
	s.last[id] = -1
}

shutdown :: proc() {
	delete(log.events)
	log = {}
	if s.worker != nil {
		thread.join(s.worker)
		thread.destroy(s.worker)
		for &takes in s.baked {
			for pcm in takes {
				delete(pcm, runtime.heap_allocator())
			}
		}
	}
	if s.ready {
		mixer_stop()
		for id in Sound_Id {
			if s.count[id] == 0 {
				continue
			}
			for k in 0 ..< SLOTS {
				if !s.owned[id][k] {
					rl.UnloadSoundAlias(s.sounds[id][k])
				}
			}
			for k in 0 ..< SLOTS {
				if s.owned[id][k] {
					rl.UnloadSound(s.sounds[id][k])
				}
			}
		}
		rl.CloseAudioDevice()
	}
	for b in beds {
		delete(b, runtime.heap_allocator())
	}
	beds = {}
	beds_ready = false
	s = {}
}

// An effect played, as written to the log of a recorded video.
Event :: struct {
	t:         f32, // seconds into the video
	id:        Sound_Id,
	volume_db: f32,
	pitch:     f32, // with the act's key applied
	pan:       f32,
}

// The log of a recorded video (--shots --record): every effect played, at
// the video's clock, so tools/video_audio can rebuild the sound in sync.
@(private)
log: struct {
	on:     bool,
	t:      f32,
	events: [dynamic]Event,
}

start_log :: proc() {
	log.on = true
}

// The video's clock (set every frame while recording).
set_log_time :: proc(t: f32) {
	log.t = t
}

// The effects played so far; the log stays until shutdown.
logged :: proc() -> []Event {
	return log.events[:]
}

// Play an effect; volume in dB on top of the effects volume, pitch as a
// ratio (in-key effects follow the act's key), pan -1 (left) .. 1 (right).
play :: proc(id: Sound_Id, volume_db: f32 = 0, pitch: f32 = 1, pan: f32 = 0) {
	if log.on {
		append(&log.events, Event{log.t, id, volume_db, id in TUNED ? pitch * s.key : pitch, pan})
	}
	if !s.ready || s.count[id] == 0 {
		return
	}
	k := int(fx.randf(&s.rng) * f32(s.count[id])) % s.count[id]
	if k == s.last[id] {
		k = (k + 1) % s.count[id]
	}
	s.last[id] = k
	snd := s.sounds[id][k]
	rl.SetSoundVolume(snd, db_to_linear(volume_db + SFX_BASE_DB) * s.sfx)
	rl.SetSoundPitch(snd, id in TUNED ? pitch * s.key : pitch)
	rl.SetSoundPan(snd, clamp(pan, -1, 1))
	rl.PlaySound(snd)
}

// The key of the soundtrack, in semitones from A (Act I: 0; G minor: -2).
set_key :: proc(semis: f32) {
	s.key = semitones(semis)
}

// Player-facing volumes, 0..1.
set_volumes :: proc(master, music_volume, sfx: f32) {
	s.master, s.music, s.sfx = master, music_volume, sfx
	apply_volumes()
}

@(private)
apply_volumes :: proc() {
	if !s.ready {
		return
	}
	rl.SetMasterVolume(s.master)
	mixer_gains(db_to_linear(MUSIC_BASE_DB) * s.music, db_to_linear(BED_BASE_DB) * s.sfx)
}
