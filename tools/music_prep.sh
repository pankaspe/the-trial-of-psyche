#!/usr/bin/env bash
# Prepare the act soundtracks: tools/music_prep.sh SOURCE.mp3 NAME
#   -> assets/music/NAME.ogg (stereo 44.1 kHz Vorbis, loudness -16 LUFS, the
#      deep lows trimmed so the music sits under the steps and the stones)
#   and prints the loop candidates (tools/music_loop) to copy into
#   src/audio/tracks.odin.
set -euo pipefail
cd "$(dirname "$0")/.."
src="${1:?source audio}"
name="${2:?track name}"
mkdir -p assets/music build
ffmpeg -v error -y -i "$src" -map 0:a \
	-af "highpass=f=35,lowshelf=f=110:g=-4,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=44100" \
	-ar 44100 -ac 2 -c:a libvorbis -q:a 5 "assets/music/$name.ogg"
ffmpeg -v error -y -i "assets/music/$name.ogg" -ac 1 -ar 11025 -f f32le "build/$name.f32"
odin run tools/music_loop -out:build/music_loop -o:speed -vet -strict-style -- "build/$name.f32"
