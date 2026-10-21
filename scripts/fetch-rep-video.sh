#!/usr/bin/env bash
# Downloads a real pushup clip and turns it into the y4m Chrome's fake capture device accepts.
#
# Source: "Interval Push-ups.webm" from Wikimedia Commons — a service member doing pushups
# side-on at ground level, which is exactly the geometry this app expects (phone on the floor,
# 1.5-2.5 m away, camera perpendicular to the body). Public domain US military footage.
#
#   bash scripts/fetch-rep-video.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .repcheck
SRC=.repcheck/pushups_src.webm
OUT=.repcheck/pushups_rep.y4m
OUT16=.repcheck/pushups_16x9.y4m
URL='https://upload.wikimedia.org/wikipedia/commons/9/98/Interval_Push-ups.webm'

[ -s "$SRC" ] || curl -sL --retry 3 -o "$SRC" "$URL"
ls -la "$SRC"

# 24 s from the middle of the clip, 480x360 — small enough to keep the harness fast, big enough
# for the lite model to lock onto the body.
FFMPEG=$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)
"$FFMPEG" -v error -i "$SRC" -ss 6 -t 24 -r 24 -vf "scale=480:360" -pix_fmt yuv420p \
  -c:v wrapped_avframe "$OUT" -y
# Chrome's fake capture device reports a 1280x720 stream regardless of what the file holds, and a
# 4:3 frame is delivered with its top and bottom cropped away — the app then genuinely sees only a
# torso, and correctly refuses to count. 16:9 keeps every pixel the model needs.
"$FFMPEG" -v error -i "$SRC" -ss 6 -t 20 -r 15 -vf "scale=640:360:force_original_aspect_ratio=decrease,pad=640:360:(ow-iw)/2:(oh-ih)/2" \
  -pix_fmt yuv420p -c:v wrapped_avframe "$OUT16" -y
head -c 120 "$OUT" | tr -d '\0' | head -1
ls -la "$OUT" "$OUT16"
echo "ready: $OUT16 (camera harness) and $OUT (frame sampling)"
