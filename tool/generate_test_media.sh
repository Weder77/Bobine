#!/usr/bin/env bash
# Generates the test videos and images used by tool/fake_xtream.py.
# Requires ffmpeg and ImageMagick (convert). Usage: tool/generate_test_media.sh [output_dir]
set -euo pipefail
OUT="${1:-test_media}"
mkdir -p "$OUT/media" "$OUT/img"
cd "$OUT/media"

# 5 min movie: 720p H.264, two audio tracks (VF/VO) and French subtitles.
ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=1280x720:rate=25" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000" -f lavfi -i "sine=frequency=660:sample_rate=48000" -t 300 \
  -map 0:v -map 1:a -map 2:a -c:v libx264 -preset ultrafast -g 50 -b:v 2500k -c:a aac -b:a 96k \
  -metadata:s:a:0 language=fre -metadata:s:a:0 title=VF -metadata:s:a:1 language=eng -metadata:s:a:1 title=VO tmp.mkv
printf '1\n00:00:01,000 --> 00:00:30,000\nSous-titre de test Bobine\n\n2\n00:00:31,000 --> 00:04:59,000\nDeuxième sous-titre\n' > subs.srt
ffmpeg -loglevel error -y -i tmp.mkv -i subs.srt -map 0 -map 1 -c copy -c:s srt -metadata:s:s:0 language=fre movie.mkv
rm tmp.mkv subs.srt

# "Live" channel: MPEG-TS with AC3 audio, like many IPTV streams.
ffmpeg -loglevel error -y -f lavfi -i "testsrc=size=1280x720:rate=25" -f lavfi -i "sine=frequency=330:sample_rate=48000" \
  -t 120 -c:v libx264 -preset ultrafast -g 25 -b:v 2000k -c:a ac3 -b:a 192k -f mpegts live.ts

# Series episode.
ffmpeg -loglevel error -y -f lavfi -i "smptehdbars=size=1280x720:rate=25" -f lavfi -i "sine=frequency=550:sample_rate=48000" \
  -t 120 -c:v libx264 -preset ultrafast -g 50 -c:a aac episode.mp4

cd ../img
colors=("#3a1c71" "#d76d77" "#1f4037" "#355c7d" "#c06c84" "#0f2027" "#614385" "#134e5e" "#8e2de2" "#ff512f" "#11998e" "#373b44")
titles=("Horizon" "Le Phare" "Nuit Blanche" "Odyssée" "Brume" "Atlas" "Orbite" "Marée" "Vertige" "Solstice" "Rivage" "Éclipse")
for i in $(seq 0 11); do
  convert -size 300x450 gradient:"${colors[$i]}"-black -gravity center -fill white -pointsize 34 \
    -annotate +0-40 "${titles[$i]}" -depth 8 "PNG32:poster$i.png"
  convert -size 1280x720 gradient:"${colors[$i]}"-"#05060a" -quality 85 "backdrop$i.jpg" && mv "backdrop$i.jpg" "backdrop$i.png"
done
names=("TF" "F2" "SP" "CN" "AR" "M6" "NW" "KD")
for i in $(seq 0 7); do
  convert -size 128x128 xc:none -fill "${colors[$i]}" -draw "roundrectangle 0,0 127,127 24,24" \
    -gravity center -fill white -pointsize 52 -annotate +0+0 "${names[$i]}" -depth 8 "PNG32:logo$i.png"
done
echo "OK. Lance : python3 tool/fake_xtream.py $OUT 8765  puis ajoute le serveur http://127.0.0.1:8765 (identifiant/mot de passe quelconques) dans Bobine."
