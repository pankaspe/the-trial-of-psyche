#!/usr/bin/env bash
# Prepare the recorded footsteps: tools/sfx_prep.sh KENNEY_DIR
# KENNEY_DIR holds the unzipped Kenney packs (CC0, www.kenney.nl):
#   impact-sounds/Audio/footstep_grass_00N.ogg -> assets/sfx/step_grass_N.ogg
#   rpg-audio/Audio/footstep0N.ogg             -> assets/sfx/step_stone_N.ogg
# Mono 44.1 kHz, trimmed to the footfall, rumble and hiss filtered out, a
# little lighter (Psyche walks barefoot), peaks at -3 dBFS.
set -euo pipefail
cd "$(dirname "$0")/.."
k="${1:?Kenney packs directory}"
mkdir -p assets/sfx

# prep IN OUT FILTERS: filter, then normalise the peak to -3 dBFS
prep() {
	local tmp="build/sfx_tmp.wav"
	ffmpeg -v error -y -i "$1" -ac 1 -af "$3" -ar 44100 "$tmp"
	local peak
	peak=$(ffmpeg -nostats -i "$tmp" -af astats=measure_overall=Peak_level:measure_perchannel=0 -f null - 2>&1 |
		grep -oE "Peak level dB: -?[0-9.]+" | grep -oE -- "-?[0-9.]+$")
	ffmpeg -v error -y -i "$tmp" -af "volume=$(echo "-3 - ($peak)" | bc -l)dB" -c:a libvorbis -q:a 6 "$2"
}
mkdir -p build
for n in 0 1 2 3 4; do
	prep "$k/impact-sounds/Audio/footstep_grass_00$n.ogg" "assets/sfx/step_grass_$n.ogg" \
		"atrim=0:0.24,highpass=f=110,lowpass=f=9000,afade=t=out:st=0.16:d=0.08"
done
n=0
for src in 00 01 02 03 06 07; do
	prep "$k/rpg-audio/Audio/footstep$src.ogg" "assets/sfx/step_stone_$n.ogg" \
		"asetrate=48000*1.06,aresample=44100,atrim=0:0.24,highpass=f=140,lowpass=f=7000,afade=t=out:st=0.17:d=0.07"
	n=$((n + 1))
done
rm -f build/sfx_tmp.wav
