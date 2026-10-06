#!/usr/bin/env bash
# A YouTube Short: a portrait card ("flip your phone"), then the game in
# landscape turned 90 degrees in a 1080x1920 frame, with its sound.
# Works in build/video, where each level was recorded and its sound rebuilt:
#   ./build/trial-of-psyche --shots build/video/i3 --size 1920x1080 --level I.3 --plan --record
#   ./build/video_audio effects build/video/i3/sounds.txt build/video/i3.wav
#   ./build/video_audio music Title 45 build/video/music.wav
# Arguments: segments as DIR START_FRAME FRAMES (60 fps), joined by dissolves;
# BG=DIR/fNNNNN.png is the card's backdrop (blurred). Output: build/video/short.mp4.
#   tools/make_short.sh i1 180 300 i3 60 420 i4 1260 357
set -euo pipefail
cd "$(dirname "$0")/../build/video"
# the phone of the card: a gold outline, as a mask over gold
if [ ! -f phone.png ]; then
	ffmpeg -v error -y -f lavfi -i "color=c=black:s=300x540" -vf "drawbox=x=0:y=0:w=300:h=540:color=white:t=9,drawbox=x=115:y=26:w=70:h=9:color=white:t=fill,drawbox=x=125:y=492:w=50:h=12:color=white:t=fill,drawbox=x=30:y=60:w=240:h=410:color=0x2e2e2e:t=fill,format=gray" -frames:v 1 mask.png
	ffmpeg -v error -y -f lavfi -i "color=c=0xF0C478:s=300x540" -i mask.png -filter_complex "[0:v][1:v]alphamerge,format=rgba" -frames:v 1 phone.png
fi
F=../../assets/fonts
FPS=60
XF=0.5         # dissolve between segments (s)
INTRO=2.4      # the portrait card (s)
SEGS=("$@")    # triples: dir start frames

inputs=()
vf=""
af=""
n=$(( ${#SEGS[@]} / 3 ))
total=0
for ((k = 0; k < n; k++)); do
	d=${SEGS[3*k]}; s=${SEGS[3*k+1]}; c=${SEGS[3*k+2]}
	inputs+=(-framerate $FPS -start_number "$s" -i "$d/f%05d.png")
	inputs+=(-i "$d.wav")
	vi=$((2*k + 3)); ai=$((2*k + 4))
	ss=$(echo "$s / $FPS" | bc -l); dur=$(echo "$c / $FPS" | bc -l)
	vf+="[$vi:v]trim=end_frame=$c,setpts=PTS-STARTPTS,format=yuv420p[v$k];"
	af+="[$ai:a]atrim=start=$ss:duration=$dur,asetpts=PTS-STARTPTS[a$k];"
	total=$(echo "$total + $dur" | bc -l)
done
# the last segment carries the end title, fading in over its last 3 s
last=$((n - 1)); lastdur=$(echo "${SEGS[3*last+2]} / $FPS" | bc -l)
t0=$(echo "$lastdur - 3" | bc -l)
vf+="[v$last]drawtext=fontfile=$F/MysteryQuest-Regular.ttf:text='La prova di Psiche':fontsize=150:fontcolor=0xFBEBC8:x=(w-tw)/2:y=(h-th)/2-40:shadowcolor=0x000000@0.7:shadowy=4:alpha='min(max((t-$t0)/1.2,0),1)',drawtext=fontfile=$F/CormorantGaramond-MediumItalic.ttf:text='in sviluppo  ·  in development':fontsize=54:fontcolor=0xF1E6D0:x=(w-tw)/2:y=(h)/2+90:alpha='min(max((t-$t0-0.6)/1.2,0),1)'[v${last}t];"
# chain the dissolves
prev="v0"; aprev="a0"; off=0
for ((k = 1; k < n; k++)); do
	cur="v$k"; [ $k -eq $last ] && cur="v${last}t"
	d=$(echo "${SEGS[3*(k-1)+2]} / $FPS" | bc -l)
	[ $k -eq 1 ] && off=$(echo "$d - $XF" | bc -l) || off=$(echo "$off + $d - $XF" | bc -l)
	vf+="[$prev][$cur]xfade=transition=fade:duration=$XF:offset=$off[x$k];"
	af+="[$aprev][a$k]acrossfade=d=$XF[y$k];"
	prev="x$k"; aprev="y$k"
done
[ $n -eq 1 ] && prev="v0t"
game_len=$(echo "$total - $XF * ($n - 1)" | bc -l)
# the game turned a quarter (top to the right: the phone turns to the left)
vf+="[$prev]transpose=1,fps=$FPS[game];"
# the portrait card: the first frame blurred, the title, a phone that turns
vf+="[2:v]trim=duration=$INTRO,setpts=PTS-STARTPTS,scale=-2:1920,crop=1080:1920,boxblur=20:2,eq=brightness=-0.25:saturation=0.85,fps=$FPS[bg];"
vf+="[1:v]format=rgba,rotate=a='-PI/2*min(max((t-0.6)/0.9\,0)\,1)':c=black@0:ow=hypot(iw\,ih):oh=ow,fps=$FPS,trim=duration=$INTRO[ph];"
vf+="[bg][ph]overlay=x=(W-w)/2:y=(H-h)/2+60,drawtext=fontfile=$F/MysteryQuest-Regular.ttf:text='La prova di Psiche':fontsize=118:fontcolor=0xFBEBC8:x=(w-tw)/2:y=330:shadowcolor=0x000000@0.6:shadowy=3,drawtext=fontfile=$F/CormorantGaramond-SemiBold.ttf:text='FLIP YOUR PHONE':fontsize=66:fontcolor=0xFFD58E:x=(w-tw)/2:y=1520,drawtext=fontfile=$F/CormorantGaramond-MediumItalic.ttf:text='gira il telefono':fontsize=54:fontcolor=0xF1E6D0:x=(w-tw)/2:y=1610,format=yuv420p[intro];"
vf+="[intro][game]xfade=transition=fade:duration=0.4:offset=$(echo "$INTRO - 0.4" | bc -l)[vout]"
length=$(echo "$INTRO - 0.4 + $game_len" | bc -l)
# sound: the game's effects after the card, the music over everything
af+="[$aprev]adelay=$(echo "($INTRO - 0.4) * 1000" | bc -l | cut -d. -f1)|$(echo "($INTRO - 0.4) * 1000" | bc -l | cut -d. -f1),apad[fx];"
af+="[0:a]atrim=start=8:duration=$length,asetpts=PTS-STARTPTS,afade=t=in:d=0.8,afade=t=out:st=$(echo "$length - 2" | bc -l):d=2,volume=1.6[mus];"
af+="[fx][mus]amix=inputs=2:duration=shortest:normalize=0,loudnorm=I=-14:TP=-1.5:LRA=11[aout]"
ffmpeg -v error -y -i music.wav -loop 1 -framerate $FPS -i phone.png -loop 1 -framerate $FPS -i "${BG:-${SEGS[0]}/f00000.png}" "${inputs[@]}" \
	-filter_complex "$vf;$af" -map "[vout]" -map "[aout]" -t "$length" \
	-c:v libx264 -preset slow -crf 18 -profile:v high -pix_fmt yuv420p -r $FPS \
	-c:a aac -b:a 192k -ar 48000 -movflags +faststart short.mp4
echo "short.mp4: $length s"
