#!/usr/bin/env bash
# The reason the camera "worked" and still counted nothing.
#
# Fed a real pushup clip through the production path, the elbow signal is textbook — 160° at the
# top, 30° at the bottom, 99% landmark quality, 20 fps — and the rep counter stayed at 0 forever,
# because the plank gate refused to arm with the reason "bodyAngle".
#
# The gate demanded that the shoulder-to-ankle line sit within 12° of horizontal. That demand is
# geometrically incompatible with the setup this app itself instructs: a phone lying flat on the
# floor, 1.5-2.5 m away. A camera at floor height sees a body that is 40-70 cm above it, and
# perspective tilts the image of a perfectly straight plank by 30-35° — the near end sits low, the
# far end climbs toward the horizon. Measured on the clip: -32.7°. Every real set fails a threshold
# that only a camera at exactly body height could satisfy, which is why Tal's own set showed 0 reps
# on a screen full of live landmarks.
#
# So the check is inverted to what it can actually detect: the body line may tilt by any amount a
# floor camera produces, and is rejected only when it is close to VERTICAL — the one thing that
# unambiguously means "you are standing up, not on the floor". Straightness is already measured by
# hipOffset, a perpendicular deviation and therefore tilt-invariant; that remains the real plank
# check. Every published pushup counter this repo studied (the 105°/155° elbow-hysteresis family)
# likewise never blocks counting on body tilt.
#
# The test suite's model of "kneeling" was also wrong: it bent nothing, just tilted a rigid body
# 45° — which is an incline plank, a legitimate pushup variation, held up against a wall. Kneeling
# folds at the hip, so the test now does that, and a new case proves a straight body at 45° arms
# and counts.
#
# Finally: the headless harnesses bypassed the service worker but not the browser's HTTP cache, so
# a patched js/counter.js could be served stale and a fix could read as "no effect". All four now
# disable the cache outright.
#
#   bash scripts/fix-plank-gate.sh
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import pathlib, re, sys

BODY_ANGLE_MAX = 70

def read(path):
    return pathlib.Path(path).read_text()

def write(path, text):
    pathlib.Path(path).write_text(text)
    print(f'patched {path}')

def sub(path, old, new, count=1, marker=None):
    """Replace `old` with `new`. `marker` names text that only exists once the patch is in —
       required whenever `new` contains `old` (an insertion), because then `old in text` never
       becomes false and a naive idempotency check re-applies on every run."""
    text = read(path)
    probe = new if marker is None else marker
    if probe in text:
        print(f'skip (already applied): {path}')
        return
    if text.count(old) != count:
        sys.exit(f'FAIL {path}: anchor found {text.count(old)}x, expected {count}\n---\n{old}\n---')
    write(path, text.replace(old, new))

# --- 1. the gate itself: idempotent from 12, from 55, or from any future value ---
COMMENT = """/* A phone lying on the floor — the setup this app asks for — sees a straight plank as a line
   tilted 30 degrees or more, because the body sits half a metre above the lens and perspective
   pulls the far end toward the horizon. Demanding "level" therefore rejects every real set. What
   the angle can still prove is that the subject is upright, so that is all it is used for;
   straightness is hipOffset's job, and a perpendicular deviation is tilt-invariant. */"""
path = 'js/counter.js'
text = read(path)
pat = re.compile(r'(?:/\*.*?\*/\n)?const BODY_ANGLE_MAX = \d+;', re.S)
hits = pat.findall(text)
if not hits:
    sys.exit(f'FAIL {path}: no BODY_ANGLE_MAX declaration found')
canon = f'{COMMENT}\nconst BODY_ANGLE_MAX = {BODY_ANGLE_MAX};'
if hits[0] == canon:
    print(f'skip (already applied): {path}')
else:
    write(path, pat.sub(canon, text, count=1))

# --- 2. the operator-facing words for that reason ---
sub('js/views/train.js',
"""      bodyAngle: 'body not level',""",
"""      bodyAngle: 'you look upright — get on the floor',""")

# The pill blamed the model when the camera was the thing that never produced a frame.
sub('js/views/train.js',
"""        else if (kind === 'ready' || kind === 'running') clearWarn();""",
"""        else if (kind === 'ready' || kind === 'running') {
          clearWarn();
          // The engine can be perfectly ready while the camera has handed over zero frames; the
          // pill used to keep saying "loading pose model" and sent everyone looking at the wrong
          // half of the pipeline.
          if (!lastFrameAt) els.pillText.textContent = 'engine ready · no video yet';
        }""")

# --- 3. the tests that encoded the wrong geometry ---
T = 'tests/counter.test.mjs'
sub(T,
"""// phi (deg) is exactly what bodyAngleOf() reports, so tilt == 45 gives a kneeling-looking shape.""",
"""// phi (deg) is exactly what bodyAngleOf() reports. A tilted-but-rigid body is an INCLINE plank
// (hands on a bench), which is a legal pushup; kneeling is a fold at the hip, expressed by hipOff.""")

# arm() with fixed geometry, so a test can hold a pose that is not the default floor plank.
sub(T,
"""// Arm the counter with a clean, valid plank.
function arm(c, t0) {
  const { frames, tEnd } = holdFrames(t0, Math.ceil(3000 / STEP) + 20);
  const out = run(c, frames);
  return { out, t: tEnd };
}""",
"""// Arm the counter with a clean, valid plank (optionally at a fixed body tilt).
function arm(c, t0, opts = {}) {
  const { frames, tEnd } = holdFrames(t0, Math.ceil(3000 / STEP) + 20, opts);
  const out = run(c, frames);
  return { out, t: tEnd };
}""")

# Kneeling folds at the hip: steep line AND a hip far off the shoulder-ankle line.
sub(T,
"""    const out = c.addFrame(t, makeFrame({ angle: 170, depth: 0, tilt: 45 }));""",
"""    const out = c.addFrame(t, makeFrame({ angle: 170, depth: 0, tilt: 78, hipOff: 0.4 }));""")

# The regression this whole fix exists for: an incline plank must arm and count.
sub(T,
"""/* ---------- 4.""",
"""/* ---------- 3b. incline plank: a straight body that a floor camera sees at 45 deg ---------- */
{
  const c = freshCounter();
  const a = arm(c, 0, { tilt: 45 });
  check('T3b incline plank arms (no bodyAngle refusal)', a.out.armed === true && a.out.plank.valid === true);
  const tilted = repFrames(a.t, 4).frames.map((f) => ({ t: f.t, opt: { ...f.opt, tilt: 45 } }));
  const out = run(c, tilted);
  check('T3b incline plank counts four reps', out.reps === 4);
  console.log('      T3b detail: reps=' + out.reps + ' detected=' + out.repsDetected +
    ' armed=' + out.armed + ' bodyAngle=' + out.bodyAngle.toFixed(1) +
    ' reasons=' + JSON.stringify(out.plank.reasons) + ' state=' + out.state);
}

/* ---------- 4.""",
    marker="T3b incline plank arms")

# A standing body is the one pose the angle gate must still refuse.
sub(T,
"""  check('extra: steep tilt reports bodyAngle', out.plank.reasons.includes('bodyAngle'));""",
"""  check('extra: steep tilt reports bodyAngle', out.plank.reasons.includes('bodyAngle'));

  const cT = freshCounter();
  const aT = arm(cT, 0, { tilt: 45 });
  const okT = cT.addFrame(aT.t, makeFrame({ angle: 178, depth: 0, tilt: 45 }));
  console.log('      extra: tilt 45 -> reasons=' + JSON.stringify(okT.plank.reasons) +
    ' bodyAngle=' + okT.bodyAngle.toFixed(1));
  check('extra: a 45 deg straight body is never refused for tilt', !okT.plank.reasons.includes('bodyAngle'));""",
    marker="never refused for tilt")

# --- 4. headless harnesses must not be served a stale module ---
# The .sh generators rewrite their .mjs on every run, so both halves get the fix.
CACHE_FIX = """
// Bypassing the service worker does not bypass the HTTP cache: without this a patched ES module
// stays stale in the harness and a real fix looks like it had no effect.
await send('Network.setCacheDisabled', { cacheDisabled: true });"""

for tool in ('scripts/trace-reps.sh', 'scripts/repcheck.sh', 'scripts/verify-failure-card.sh',
             'scripts/harden-camera-path.sh', 'tools/trace.mjs', 'tools/repcheck.mjs',
             'tools/camfailcheck.mjs', 'tools/loopcheck.mjs'):
    text = read(tool)
    anchor = "await send('Network.setBypassServiceWorker', { bypass: true });"
    if 'Network.setCacheDisabled' in text or anchor not in text:
        print(f'skip (already applied or not applicable): {tool}')
        continue
    head = anchor
    if "await send('Network.enable');" not in text:
        head = "await send('Network.enable');\n" + anchor
    write(tool, text.replace(anchor, head + CACHE_FIX))
PY

echo
echo 'run: node tests/counter.test.mjs'
