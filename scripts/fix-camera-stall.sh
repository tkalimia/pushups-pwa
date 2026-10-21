#!/usr/bin/env bash
# Fixes the iPhone camera stall: the Train screen sat on "starting" with the camera light on
# and no preview, forever.
#
# Cause, observed on Tal's iPhone 18 Pro over iPhone Mirroring at 08:25 on 21 Oct:
#   openCamera() awaited waitMetadata() and then awaited videoEl.play(). Safari can leave
#   play() pending indefinitely when it cannot present the video. Because the function never
#   returned, the Train view never stored the stream (so nothing could stop it — the camera
#   stayed on across navigation), and createTracker() was never reached, so the pose model
#   never even started downloading. The pill stayed on its initial "starting" text.
#
# Fix: every await in the camera path now has a deadline and none of them are fatal, and the
# tracker boots in parallel with the permission prompt instead of after it.
#
#   bash scripts/fix-camera-stall.sh
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import pathlib, sys

def sub(path, old, new, count=1):
    p = pathlib.Path(path)
    text = p.read_text()
    if new in text and old not in text:
        print(f'skip (already applied): {path}')
        return
    if text.count(old) != count:
        sys.exit(f'FAIL {path}: anchor found {text.count(old)}x, expected {count}\n---\n{old}\n---')
    p.write_text(text.replace(old, new))
    print(f'patched {path}')

# ── js/camera.js ────────────────────────────────────────────────────────────
sub('js/camera.js',
"""const METADATA_TIMEOUT_MS = 5000;""",
"""const METADATA_TIMEOUT_MS = 3000;
/* Hard ceiling on the whole preview handshake. play() is what needs it: on iOS it can stay
   pending forever, and a pending await there used to strand the caller mid-function. */
const PREVIEW_DEADLINE_MS = 3500;

const sleep = (ms) => new Promise((resolve) => { setTimeout(resolve, ms); });""")

sub('js/camera.js',
"""function waitMetadata(videoEl) {
  return new Promise((resolve, reject) => {
    if (videoEl.readyState >= 1 && videoEl.videoWidth > 0) {
      resolve();
      return;
    }
    let done = false;
    const finish = (err) => {
      if (done) return;
      done = true;
      videoEl.removeEventListener('loadedmetadata', ok);
      clearTimeout(timer);
      if (err) reject(err);
      else resolve();
    };
    const ok = () => finish(null);
    const timer = setTimeout(() => {
      finish(new Error('Camera preview timed out after 5 seconds. Close other apps using the camera, then tap Start again.'));
    }, METADATA_TIMEOUT_MS);
    videoEl.addEventListener('loadedmetadata', ok, { once: true });
  });
}""",
"""// Resolves on the first frame's metadata or on the timeout, whichever comes first. It never
// rejects: a missing preview is a display problem, not a reason to abandon a live camera stream.
function waitMetadata(videoEl) {
  return new Promise((resolve) => {
    if (videoEl.readyState >= 1 && videoEl.videoWidth > 0) {
      resolve(false);
      return;
    }
    let done = false;
    const finish = (timedOut) => {
      if (done) return;
      done = true;
      videoEl.removeEventListener('loadedmetadata', ok);
      clearTimeout(timer);
      resolve(timedOut);
    };
    const ok = () => finish(false);
    const timer = setTimeout(() => finish(true), METADATA_TIMEOUT_MS);
    videoEl.addEventListener('loadedmetadata', ok, { once: true });
  });
}""")

sub('js/camera.js',
"""  const stream = await navigator.mediaDevices.getUserMedia({ video, audio: false });

  videoEl.setAttribute('playsinline', '');
  videoEl.setAttribute('webkit-playsinline', '');
  videoEl.muted = true;
  videoEl.srcObject = stream;

  await waitMetadata(videoEl);

  const track = stream.getVideoTracks()[0];
  const info = describeTrack(track, facing);
  const settings = {
    facingMode: info.facingMode,
    width: info.width,
    height: info.height,
    deviceId: info.deviceId,
    facing: info.facingMode === 'user' ? 'user' : facing,
    needsTap: false,
  };

  try {
    await videoEl.play();
  } catch (err) {
    void err;
    settings.needsTap = true;
  }

  return { stream, settings, track, videoEl };""",
"""  const stream = await navigator.mediaDevices.getUserMedia({ video, audio: false });

  videoEl.setAttribute('playsinline', '');
  videoEl.setAttribute('webkit-playsinline', '');
  videoEl.muted = true;
  videoEl.srcObject = stream;

  const track = stream.getVideoTracks()[0];
  const info = describeTrack(track, facing);
  const settings = {
    facingMode: info.facingMode,
    width: info.width,
    height: info.height,
    deviceId: info.deviceId,
    facing: info.facingMode === 'user' ? 'user' : facing,
    needsTap: false,
    stalled: false,
  };

  /* Safari will not feed frames to a srcObject <video> until play() is called, and play() can
     itself stay pending when the page cannot present video. So: kick play() without awaiting it,
     and wait for metadata behind a deadline. Awaiting play() used to hang here forever, which
     left the stream unreturned — nothing could stop it, the camera light stayed on across
     navigation, and the pose engine was never created. */
  const started = videoEl.play();
  if (started && typeof started.catch === 'function') {
    started.catch(() => { settings.needsTap = true; });
  }
  await Promise.race([waitMetadata(videoEl), sleep(PREVIEW_DEADLINE_MS)]);
  if (videoEl.readyState < 2 || videoEl.videoWidth === 0) {
    settings.stalled = true;
    settings.needsTap = true;
  }

  return { stream, settings, track, videoEl };""")

# ── js/views/train.js — boot the engine while the prompt is still up ────────
sub('js/views/train.js',
"""  (async () => {
    if (load().manualMode) return;
    await startCamera(load().camera);
    tracker = await createTracker({""",
"""  (async () => {
    if (load().manualMode) return;
    /* The engine is built first so the wasm and the .task file start downloading while the
       permission prompt is still on screen — they are ~15 MB, and waiting for the answer first
       meant half a minute of "starting" on mobile data after every Allow. */
    tracker = createTracker({""")

sub('js/views/train.js',
"""      onFrame: (f) => {
        try { onFrame(f); } catch (e) { console.error('frame', e); }
      },
      onError: (e) => {
        els.pillText.textContent = 'pose error';
        console.error('pose', e);
      },
    });
    await tracker.start();
  })();""",
"""      onFrame: (f) => {
        try { onFrame(f); } catch (e) { console.error('frame', e); }
      },
      onError: (e) => {
        els.pillText.textContent = 'pose error';
        console.error('pose', e);
      },
    });
    await startCamera(load().camera);
    await tracker.ready;
    if (tracker.getStatus().phase !== 'failed') tracker.start();
  })();""")

# Tell the user when the camera opened but the preview could not be presented.
sub('js/views/train.js',
"""      if (cam.settings && cam.settings.needsTap) {
        // iOS refused to autoplay outside a gesture: the next tap anywhere restarts the preview
        const wake = () => { resumePreview(els.video); els.camoff.hidden = true; };
        els.camoff.hidden = false;
        els.camoff.replaceChildren();
        const hint = document.createElement('div');
        hint.textContent = 'Tap to show the preview';
        els.camoff.append(hint);
        els.camoff.addEventListener('click', wake, { once: true });
      }""",
"""      if (cam.settings && cam.settings.needsTap) {
        // iOS refused to autoplay outside a gesture (or never presented a frame): the next tap
        // anywhere restarts the preview. The counting loop does not wait for it either way.
        const wake = () => { resumePreview(els.video); els.camoff.hidden = true; };
        els.camoff.hidden = false;
        els.camoff.replaceChildren();
        const hint = document.createElement('div');
        hint.style.color = 'var(--porcelain)';
        hint.style.fontWeight = '600';
        hint.textContent = cam.settings.stalled
          ? 'Camera is on, no preview'
          : 'Tap to show the preview';
        const sub = document.createElement('div');
        sub.textContent = cam.settings.stalled
          ? 'Tap the screen to wake it. Counting still needs the phone facing you.'
          : 'Tap anywhere on the black area.';
        els.camoff.append(hint, sub);
        els.camoff.addEventListener('click', wake, { once: true });
      }""")

# ── js/pose.js — the real root cause ────────────────────────────────────────
# MediaPipe Tasks Vision 0.10.x returns the result object from detectForVideo() synchronously.
# The loop treated a non-thenable as a failure and returned without delivering the frame, so the
# counter never received one landmark — on any browser, any platform. The camera appeared to work
# (light on, preview up) while the engine silently produced nothing.
sub('js/pose.js',
"""    const inst = landmarker;
    let promise = null;
    try {
      promise = inst.detectForVideo(video, ts);
    } catch (err) {
      st.pending = false;
      handleDetectFailure(err);
      return;
    }
    if (!promise || typeof promise.then !== 'function') {
      st.pending = false;
      return;
    }
    promise
      .then((res) => {
        st.pending = false;
        if (st.disposed) return;
        handleResult(res, ts);
        flushPendingClose();
      })
      .catch((err) => {
        st.pending = false;
        if (st.disposed) return;
        handleDetectFailure(err);
      });
  }""",
"""    const inst = landmarker;
    const settle = (res) => {
      st.pending = false;
      if (st.disposed) return;
      handleResult(res, ts);
      flushPendingClose();
    };
    const fail = (err) => {
      st.pending = false;
      if (st.disposed) return;
      handleDetectFailure(err);
    };
    let out = null;
    try {
      out = inst.detectForVideo(video, ts);
    } catch (err) {
      fail(err);
      return;
    }
    // Sync in 0.10.x, promise in older builds: accept either, and never drop the frame.
    if (out && typeof out.then === 'function') out.then(settle, fail);
    else settle(out);
  }""")

# ── js/pose.js — say which guard is eating the loop ─────────────────────────
sub('js/pose.js',
"""    gpuFailed: delegate === 'cpu',
    swapping: false,
    booting: false,
  };""",
"""    gpuFailed: delegate === 'cpu',
    swapping: false,
    booting: false,
    /* A loop that silently stops producing frames is undiagnosable from the outside — every
       early return below looks identical on screen. These counters ride along in getStatus(). */
    ticks: 0,
    detects: 0,
    skip: { pending: 0, swapping: 0, rate: 0, video: 0 },
  };""")

sub('js/pose.js',
"""  function loop() {
    if (!st.running || st.disposed) return;
    st.raf = requestAnimationFrame(loop);
    if (st.pending || st.swapping || !landmarker) return;
    const now = performance.now();
    if (now - st.lastDetect < 1000 / st.fpsCap) return;
    if (!video || video.readyState < 2 || video.videoWidth === 0) return;

    st.lastDetect = now;""",
"""  function loop() {
    if (!st.running || st.disposed) return;
    st.raf = requestAnimationFrame(loop);
    st.ticks += 1;
    if (st.pending) { st.skip.pending += 1; return; }
    if (st.swapping || !landmarker) { st.skip.swapping += 1; return; }
    const now = performance.now();
    if (now - st.lastDetect < 1000 / st.fpsCap) { st.skip.rate += 1; return; }
    if (!video || video.readyState < 2 || video.videoWidth === 0) { st.skip.video += 1; return; }

    st.lastDetect = now;
    st.detects += 1;""")

sub('js/pose.js',
"""        fps: st.fps,
        fpsCap: st.fpsCap,""",
"""        fps: st.fps,
        fpsCap: st.fpsCap,
        ticks: st.ticks,
        detects: st.detects,
        skip: st.skip,
        video: video ? video.readyState + '/' + video.videoWidth : 'none',""")

# ── js/views/debug.js — await inside a non-async function (module never loaded) ──
sub('js/views/debug.js',
"""  function attachTracker(target) {""",
"""  async function attachTracker(target) {""")

print('done')
PY

node --check js/camera.js 2>/dev/null || echo "(node --check skipped: ES module)"
TMP="$(mktemp -d)"
for f in js/camera.js js/views/train.js js/views/debug.js; do
  cp "$f" "$TMP/$(basename "$f" .js).mjs"
  node --check "$TMP/$(basename "$f" .js).mjs" || { echo "SYNTAX ERROR in $f"; rm -rf "$TMP"; exit 1; }
done
rm -rf "$TMP"
echo "syntax ok"
