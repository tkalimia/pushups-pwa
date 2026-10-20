#!/usr/bin/env bash
# Download every binary asset the app needs and self-host it. No build step, no CDN at runtime.
set -euo pipefail
cd "$(dirname "$0")/.."
MP="https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14"
MODEL="https://storage.googleapis.com/mediapipe-models/pose_landmarker"
UA="Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

get() { # get <url> <dest>
  if [ -s "$2" ]; then echo "ok   $2 (already there)"; return; fi
  echo ".. $2"
  curl -fL --retry 3 --retry-delay 1 -o "$2" "$1"
}

mkdir -p vendor/mediapipe/wasm models fonts icons

get "$MP/vision_bundle.mjs"                        vendor/mediapipe/vision_bundle.mjs
get "$MP/wasm/vision_wasm_internal.js"             vendor/mediapipe/wasm/vision_wasm_internal.js
get "$MP/wasm/vision_wasm_internal.wasm"           vendor/mediapipe/wasm/vision_wasm_internal.wasm
get "$MP/wasm/vision_wasm_nosimd_internal.js"      vendor/mediapipe/wasm/vision_wasm_nosimd_internal.js
get "$MP/wasm/vision_wasm_nosimd_internal.wasm"    vendor/mediapipe/wasm/vision_wasm_nosimd_internal.wasm
get "$MODEL/pose_landmarker_lite/float16/1/pose_landmarker_lite.task" models/pose_landmarker_lite.task
get "$MODEL/pose_landmarker_full/float16/1/pose_landmarker_full.task"  models/pose_landmarker_full.task

# Latin woff2 slices of the two faces, resolved through the Google Fonts CSS API with a Safari UA
# so we get woff2 rather than ttf.
slice() { # slice <family+weight url> <dest>
  local css="$1" dest="$2" u
  u=$(curl -fsS -A "$UA" "$css" | awk '/\/\* latin \*\//{f=1} f&&/url\(https/{match($0,/https:\/\/[^)]*woff2/); print substr($0,RSTART,RLENGTH); exit}')
  if [ -z "$u" ]; then echo "WARN no latin slice for $css — the app falls back to system fonts"; return; fi
  get "$u" "$dest"
}
slice "https://fonts.googleapis.com/css2?family=Barlow+Semi+Condensed:wght@500&display=swap" fonts/barlow-semi-condensed.woff2
slice "https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400&display=swap"        fonts/ibm-plex-sans.woff2

echo
echo "sizes:"
du -sh vendor models fonts | sed 's/\t/  /'
PYI=""
for p in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3 python3; do
  if command -v "$p" >/dev/null 2>&1 && "$p" -c 'import PIL' >/dev/null 2>&1; then PYI="$p"; break; fi
done
if [ -z "$PYI" ]; then
  echo "WARN Pillow missing — installing into Homebrew python"
  /opt/homebrew/bin/python3 -m pip install --quiet pillow || true
  PYI=/opt/homebrew/bin/python3
fi
"$PYI" tools/make-icons.py
ls -l icons
