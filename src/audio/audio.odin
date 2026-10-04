// Playback of the synthesised sounds through raylib.
//
// Every effect owns its samples once (raylib copies them at load) plus a few
// aliases, so the same effect can overlap itself. The two music layers (night,
// lamp) are looping streams that read from WAV files kept in memory; their
// mix follows the lamp. Calls are no-ops when there is no audio device
// (headless tests), so game code never has to check.
package audio

import "core:math"
import rl "vendor:raylib"

import "../fx"

VOICES :: 4 // simultaneous plays of one effect
MUSIC_BASE_DB :: -8.0
SFX_BASE_DB :: 0.0

@(private)
State :: struct {
	ready:         bool,
	sounds:        [Sound_Id][VOICES]rl.Sound, // [0] owns the samples, the rest are aliases
	next:          [Sound_Id]int,
	night, warm:   rl.Music,
	night_wav:     []u8, // must outlive the streams that read them
	warm_wav:      []u8,
	music_started: bool,
	master:        f32,
	music:         f32,
	sfx:           f32,
	light:         f32,
}

@(private)
s: State

db_to_linear :: proc(db: f32) -> f32 {
	return math.pow(10, db / 20)
}

// Open the device and synthesise everything. The WAV buffers of the music are
// the only lasting allocation (context.allocator), released by shutdown.
init :: proc() {
	s = {}
	s.master, s.music, s.sfx = 1, 1, 1
	rl.InitAudioDevice()
	if !rl.IsAudioDeviceReady() {
		return
	}
	s.ready = true
	rng := fx.rng_init(7)

	for id in Sound_Id {
		dry := synthesize(id, &rng, context.temp_allocator)
		wet := reverb(dry, SFX_REVERB, 1.2, false, context.temp_allocator)
		pcm := make([]i16, len(wet), context.temp_allocator)
		to_pcm16(wet, pcm)
		wave := rl.Wave {
			frameCount = u32(len(pcm)),
			sampleRate = RATE,
			sampleSize = 16,
			channels   = 1,
			data       = raw_data(pcm),
		}
		s.sounds[id][0] = rl.LoadSoundFromWave(wave)
		for v in 1 ..< VOICES {
			s.sounds[id][v] = rl.LoadSoundAlias(s.sounds[id][0])
		}
	}

	night := reverb(music(false, &rng, context.temp_allocator), MUSIC_REVERB, 0, true, context.temp_allocator)
	warm := reverb(music(true, &rng, context.temp_allocator), MUSIC_REVERB, 0, true, context.temp_allocator)
	s.night_wav = wav_file(night)
	s.warm_wav = wav_file(warm)
	s.night = rl.LoadMusicStreamFromMemory(".wav", raw_data(s.night_wav), i32(len(s.night_wav)))
	s.warm = rl.LoadMusicStreamFromMemory(".wav", raw_data(s.warm_wav), i32(len(s.warm_wav)))
	s.night.looping = true
	s.warm.looping = true
	apply_volumes()
}

shutdown :: proc() {
	if s.ready {
		rl.StopMusicStream(s.night)
		rl.StopMusicStream(s.warm)
		rl.UnloadMusicStream(s.night)
		rl.UnloadMusicStream(s.warm)
		for id in Sound_Id {
			for v in 1 ..< VOICES {
				rl.UnloadSoundAlias(s.sounds[id][v])
			}
			rl.UnloadSound(s.sounds[id][0])
		}
		rl.CloseAudioDevice()
	}
	delete(s.night_wav)
	delete(s.warm_wav)
	s = {}
}

// Play an effect; volume in dB on top of the effects volume.
play :: proc(id: Sound_Id, volume_db: f32 = 0, pitch: f32 = 1) {
	if !s.ready {
		return
	}
	v := s.next[id]
	s.next[id] = (v + 1) % VOICES
	snd := s.sounds[id][v]
	rl.SetSoundVolume(snd, db_to_linear(volume_db + SFX_BASE_DB) * s.sfx)
	rl.SetSoundPitch(snd, pitch)
	rl.PlaySound(snd)
}

start_music :: proc() {
	if !s.ready || s.music_started {
		return
	}
	s.music_started = true
	rl.PlayMusicStream(s.night)
	rl.PlayMusicStream(s.warm)
	apply_volumes()
}

// Feed the music streams; call once per frame.
update :: proc() {
	if !s.ready || !s.music_started {
		return
	}
	rl.UpdateMusicStream(s.night)
	rl.UpdateMusicStream(s.warm)
}

// 0 = night drone only, 1 = warm lamp layer on top.
set_light :: proc(amount: f32) {
	if s.light != amount {
		s.light = amount
		apply_volumes()
	}
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
	base := db_to_linear(MUSIC_BASE_DB) * s.music
	rl.SetMusicVolume(s.night, (1 - s.light * 0.5) * db_to_linear(-2) * base)
	rl.SetMusicVolume(s.warm, max(s.light, 0.001) * db_to_linear(-4) * base)
}
