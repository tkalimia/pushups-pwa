#!/usr/bin/env bash
# repcheck reported "20 fps · 38% tracked" and 0 reps even after the gate fix, while the same
# frames replayed through the counter lab counted perfectly (4 reps, 98% quality at 480x360).
#
# The difference is not resolution — it is aspect ratio. Chrome's fake capture device always
# reports a 1280x720 stream, and a 4:3 y4m is delivered into that 16:9 frame with the edges lost.
# The app therefore sees a body cut off at head and feet, which is exactly what the 38% landmark
# visibility and the "partly in frame" warning said. The counter was refusing a half person; the
# harness was feeding it one.
#
# Fix: build the clip 16:9, at the same width the fake device claims, so nothing is cropped and
# the pixels that reach MediaPipe are the pixels in the source file.
#
#   bash scripts/fix-repcheck-clip.sh && bash scripts/fetch-rep-video.sh && bash scripts/repcheck.sh
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import pathlib, sys

def sub(path, old, new, marker=None, count=1):
    p = pathlib.Path(path)
    text = p.read_text()
    probe = new if marker is None else marker
    if probe in text:
        print(f'skip (already applied): {path}')
        return
    if text.count(old) != count:
        sys.exit(f'FAIL {path}: anchor found {text.count(old)}x, expected {count}\n---\n{old}\n---')
    p.write_text(text.replace(old, new))
    print(f'patched {path}')

# --- 1. fetch-rep-video.sh: also cut a 16:9 copy for the camera harness ---
sub('scripts/fetch-rep-video.sh',
"""OUT=.repcheck/pushups_rep.y4m""",
"""OUT=.repcheck/pushups_rep.y4m
OUT16=.repcheck/pushups_16x9.y4m""")

sub('scripts/fetch-rep-video.sh',
"""head -c 120 "$OUT" | tr -d '\\0' | head -1
ls -la "$OUT"
echo "ready: $OUT\"""",
"""# Chrome's fake capture device reports a 1280x720 stream regardless of what the file holds, and a
# 4:3 frame is delivered with its top and bottom cropped away — the app then genuinely sees only a
# torso, and correctly refuses to count. 16:9 keeps every pixel the model needs.
"$FFMPEG" -v error -i "$SRC" -ss 6 -t 20 -r 15 -vf "scale=640:360:force_original_aspect_ratio=decrease,pad=640:360:(ow-iw)/2:(oh-ih)/2" \\
  -pix_fmt yuv420p -c:v wrapped_avframe "$OUT16" -y
head -c 120 "$OUT" | tr -d '\\0' | head -1
ls -la "$OUT" "$OUT16"
echo "ready: $OUT16 (camera harness) and $OUT (frame sampling)\"""")

# --- 2. repcheck.sh: use it ---
sub('scripts/repcheck.sh',
"""Y4M=.repcheck/pushups_rep.y4m""",
"""# 16:9 on purpose: the fake device crops anything narrower and the app ends up staring at a torso.
Y4M=.repcheck/pushups_16x9.y4m""")

sub('scripts/repcheck.sh',
"""# This drives Chrome with --use-file-for-fake-video-capture so getUserMedia returns the Wikimedia
# pushup clip as if it were the phone camera.""",
"""# This drives Chrome with --use-file-for-fake-video-capture so getUserMedia returns the Wikimedia
# pushup clip as if it were the phone camera. The clip must be 16:9 — see fix-repcheck-clip.sh.""",
marker='must be 16:9')

# --- 3. deploy.sh runs `git add -A`; these clips are 250 MB and GitHub rejects files over 100 MB ---
sub('.gitignore',
""".DS_Store""",
""".DS_Store
# harness video clips — rebuilt by scripts/fetch-rep-video.sh, never committed
.repcheck/""",
marker='.repcheck/')

# --- 4. the harness must show what the model actually received, not just what it concluded ---
sub('scripts/repcheck.sh',
"""console.log('  setup  ', await evalJs(READ));""",
"""console.log('  setup  ', await evalJs(READ));

// Page.captureScreenshot never composites a camera frame in headless Chrome — the video area comes
// back black — so the only way to see what MediaPipe was handed is to draw the element onto a
// canvas from inside the page and pull the bytes out.
const GRAB = `(() => {
  const v = document.querySelector('video');
  if (!v || !v.videoWidth) return '';
  const c = document.createElement('canvas');
  c.width = v.videoWidth; c.height = v.videoHeight;
  c.getContext('2d').drawImage(v, 0, 0, c.width, c.height);
  return c.toDataURL('image/jpeg', 0.9);
})()`;
{
  const url = await evalJs(GRAB);
  if (url) {
    writeFileSync('/tmp/repcheck_frame.jpg', Buffer.from(url.split(',')[1], 'base64'));
    console.log('  frame   /tmp/repcheck_frame.jpg — exactly what the pose model sees');
  } else {
    console.log('  frame   no video element to sample');
  }
}""",
marker='repcheck_frame.jpg')

# --- 5. the verdict read a counter that only exists in the setup card ---
sub('scripts/repcheck.sh',
"""const ok = maxReps >= 3 && /fps/.test(last.fps) && !/not seeing/.test(last.pill);""",
"""// #fpstxt lives in the framing card, which the app replaces the moment counting starts — so the
// only honest proof that frames were still arriving at the end is the pill.
const fpsAlive = /fps/.test(last.pill) || /fps/.test(last.fps);
const ok = maxReps >= 3 && fpsAlive && !/not seeing/.test(last.pill);""",
marker='fpsAlive')

print('done')
PY
