#!/usr/bin/env bash
# A landscape trailer: segments of recorded levels joined by dissolves, a caption
# on each, the title over the first, an end card, the music over everything.
# Record each level and rebuild its sound first (English: LANG=en_US.UTF-8):
#   LANG=en_US.UTF-8 ./build/trial-of-psyche --shots D/iv_2 --size 1920x1080 --level IV.2 --plan --record
#   ./build/video_audio effects D/iv_2/sounds.txt D/iv_2.wav
#   ./build/video_audio music Title 75 D/music.wav
# Usage: tools/make_trailer.sh D LIST OUT.mp4
# LIST: one segment per line, "dir start_frame frames caption" (60 fps, dir in D;
# an empty caption: none). The first segment carries the title instead.
set -euo pipefail
D=$(realpath "$1"); LIST=$(realpath "$2"); OUT=$(realpath -m "$3")
F=$(realpath "$(dirname "$0")/../assets/fonts")
FPS=60
XF=0.6          # dissolve between segments (s)
END=6           # the end card (s)
TITLE=${TITLE:-The Trial of Psyche}
SUBTITLE=${SUBTITLE:-a puzzle tale from Apuleius}
END_LINES=${END_LINES:-Free and open source  ·  Linux|github.com/pankaspe/the-trial-of-psyche}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$D"

text() { printf '%s' "$2" > "$TMP/$1.txt"; echo "$TMP/$1.txt"; }
# alpha of a text shown from a to b (s), fading 0.5 s each way
alpha() { echo "alpha='min(min(max((t-$1)/0.5,0),1),min(max(($2-t)/0.5,0),1))'"; }
CAP="fontfile=$F/CormorantGaramond-MediumItalic.ttf:fontsize=58:fontcolor=0xFBEBC8:shadowcolor=0x000000@0.75:shadowx=0:shadowy=3"
# a caption on the game: a soft dark band under it, low on the left, clear of the HUD and the game's cards
BOX="box=1:boxcolor=0x07060c@0.45:boxborderw=22|40"

inputs=(); vf=""; af=""; n=0; durs=()
while read -r dir start frames caption; do
	[ -z "$dir" ] && continue
	dur=$(echo "$frames / $FPS" | bc -l); durs+=("$dur")
	inputs+=(-framerate $FPS -start_number "$start" -i "$dir/f%05d.png" -i "$dir.wav")
	vi=$((2*n + 1)); ai=$((2*n + 2))
	vf+="[$vi:v]trim=end_frame=$frames,setpts=PTS-STARTPTS,format=yuv420p"
	if [ $n -eq 0 ]; then
		vf+=",drawtext=fontfile=$F/MysteryQuest-Regular.ttf:textfile=$(text t0 "$TITLE"):fontsize=150:fontcolor=0xFBEBC8:shadowcolor=0x000000@0.7:shadowy=4:x=(w-tw)/2:y=h*0.17:$(alpha 0.6 "$(echo "$dur - 0.6" | bc -l)")"
		vf+=",drawtext=$CAP:textfile=$(text s0 "$SUBTITLE"):x=(w-tw)/2:y=h*0.17+180:$(alpha 1.3 "$(echo "$dur - 0.6" | bc -l)")"
	elif [ -n "$caption" ]; then
		vf+=",drawtext=$CAP:$BOX:textfile=$(text c$n "$caption"):x=110:y=h*0.865:$(alpha 0.7 "$(echo "$dur - 0.7" | bc -l)")"
	fi
	vf+="[v$n];"
	af+="[$ai:a]atrim=start=$(echo "$start / $FPS" | bc -l):duration=$dur,asetpts=PTS-STARTPTS[a$n];"
	n=$((n + 1))
done < "$LIST"

# the end card: the title on the dark, the lines below it
ec="color=c=0x07060c:s=1920x1080:r=$FPS:d=$END,format=yuv420p"
ec+=",drawtext=fontfile=$F/MysteryQuest-Regular.ttf:textfile=$(text te "$TITLE"):fontsize=130:fontcolor=0xFBEBC8:x=(w-tw)/2:y=h*0.33:$(alpha 0.3 $((END + 1)))"
y=0
IFS='|' read -ra lines <<< "$END_LINES"
for k in "${!lines[@]}"; do
	ec+=",drawtext=$CAP:fontsize=52:textfile=$(text e$k "${lines[$k]}"):x=(w-tw)/2:y=h*0.33+190+$y:$(alpha "$(echo "0.9 + 0.4 * $k" | bc -l)" $((END + 1)))"
	y=$((y + 72))
done
vf+="$ec[v$n];"
af+="anullsrc=r=44100:cl=mono,atrim=duration=$END[a$n];"
durs+=("$END")

# chain the dissolves
prev="v0"; aprev="a0"; off=0
for ((k = 1; k <= n; k++)); do
	off=$(echo "$off + ${durs[k-1]} - $XF" | bc -l)
	vf+="[$prev][v$k]xfade=transition=fade:duration=$XF:offset=$off[x$k];"
	af+="[$aprev][a$k]acrossfade=d=$XF[y$k];"
	prev="x$k"; aprev="y$k"
done
length=$(echo "$off + $END" | bc -l)
# the game's sound under the music, both fading out at the end
af+="[$aprev]volume=0.8[fx];"
af+="[0:a]atrim=duration=$length,asetpts=PTS-STARTPTS,afade=t=in:d=1.5,volume=1.4[mus];"
af+="[fx][mus]amix=inputs=2:duration=first:normalize=0,afade=t=out:st=$(echo "$length - 3" | bc -l):d=3,loudnorm=I=-14:TP=-1.5:LRA=11[aout]"
ffmpeg -v error -stats -y -i music.wav "${inputs[@]}" \
	-filter_complex "${vf%;};$af" -map "[$prev]" -map "[aout]" -t "$length" \
	-c:v libx264 -preset slow -crf 17 -profile:v high -pix_fmt yuv420p -r $FPS \
	-c:a aac -b:a 256k -ar 48000 -movflags +faststart "$OUT"
echo "$OUT: $length s"
