// node tests/counter.test.mjs
import { Counter, angleBetween, hipOffsetOf, bodyAngleOf, elbowAngle } from '../js/counter.js';

let failures = 0;
function check(name, cond) {
  const line = `${cond ? 'PASS' : 'FAIL'}  ${name}`;
  if (!cond) failures++;
  console.log(line);
}

const FPS = 40;
const STEP = 1000 / FPS;
const L = 0.37;
const ANKLE = { x: 0.72, y: 0.53 };
const HIP_X = 0.5;
const WRIST_R = 0.12;

// Plausible side-view plank: mid-shoulder / mid-hip / mid-ankle on a line that tilts with depth.
// phi (deg) is exactly what bodyAngleOf() reports, so tilt == 45 gives a kneeling-looking shape.
// The wrist is placed on a circle of radius 0.12 around the elbow, rotated by the requested
// elbow angle away from the upper arm — the landmarks really do produce that angle.
function makeLandmarks({ angle, depth = 0, hipOff = 0, tilt = null, vis = 0.95 }) {
  const phi = ((tilt === null ? 3 + 7 * depth : tilt)) * Math.PI / 180;
  const S = { x: ANKLE.x - L * Math.cos(phi), y: ANKLE.y + L * Math.sin(phi) };
  const dx = ANKLE.x - S.x;
  const dy = ANKLE.y - S.y;
  const len = Math.hypot(dx, dy);
  let nx = -dy, ny = dx;
  if (ny < 0) { nx = -nx; ny = -ny; }
  const t = (HIP_X - S.x) / dx;
  const hipY = S.y + (hipOff * len * len - (HIP_X - S.x) * nx) / ny;
  void t;
  const H = { x: HIP_X, y: hipY };
  const K = { x: S.x + 0.78 * dx, y: S.y + 0.78 * dy };

  const E = { x: S.x + 0.06, y: S.y + 0.11 };
  let ux = S.x - E.x, uy = S.y - E.y;
  const um = Math.hypot(ux, uy);
  ux /= um; uy /= um;
  const th = angle * Math.PI / 180;
  const W = {
    x: E.x + WRIST_R * (ux * Math.cos(th) - uy * Math.sin(th)),
    y: E.y + WRIST_R * (ux * Math.sin(th) + uy * Math.cos(th)),
  };
  const N = { x: S.x - 0.05, y: S.y - 0.02 };

  const lm = Array.from({ length: 33 }, () => ({ x: 0, y: 0, z: 0, visibility: 0 }));
  // left and right overlap in a true side view; the far side is slightly less visible
  const put = (i, p, v) => { lm[i] = { x: p.x, y: p.y, z: 0, visibility: v }; };
  const pairs = [[11, 12, S], [13, 14, E], [15, 16, W], [23, 24, H], [25, 26, K], [27, 28, ANKLE]];
  for (const [li, ri, p] of pairs) { put(li, p, vis); put(ri, p, vis * 0.97); }
  put(0, N, vis);
  return lm;
}

function makeFrame(opts) {
  const landmarks = makeLandmarks(opts);
  const visVals = [11, 12, 13, 14, 15, 16, 23, 24].map((i) => landmarks[i].visibility);
  const quality = visVals.reduce((a, b) => a + b, 0) / visVals.length;
  return { landmarks, present: opts.present !== false, quality, fps: FPS };
}

// angle/depth schedule for one full rep
function repFrames(t0, count, { topAngle = 178, bottomAngle = 92, downMs = 800, upMs = 700, topDwellMs = 300, depthFromAngle = true, forceDepth = null, hipSagFrames = null } = {}) {
  const frames = [];
  let t = t0;
  const downN = Math.round(downMs / STEP);
  const upN = Math.round(upMs / STEP);
  const dwellN = Math.round(topDwellMs / STEP);
  for (let r = 0; r < count; r++) {
    for (let i = 1; i <= downN; i++) {
      const a = topAngle + (bottomAngle - topAngle) * (i / downN);
      const d = depthFromAngle ? (topAngle - a) / (topAngle - bottomAngle) : forceDepth * (i / downN);
      const opt = { angle: a, depth: Math.max(0, Math.min(1, d)) };
      if (hipSagFrames && i > hipSagFrames.start && i <= hipSagFrames.end) opt.hipOff = hipSagFrames.value;
      frames.push({ t, opt });
      t += STEP;
    }
    for (let i = 1; i <= upN; i++) {
      const a = bottomAngle + (topAngle - bottomAngle) * (i / upN);
      const d = depthFromAngle ? (topAngle - a) / (topAngle - bottomAngle) : forceDepth * (1 - i / upN);
      frames.push({ t, opt: { angle: a, depth: Math.max(0, Math.min(1, d)) } });
      t += STEP;
    }
    for (let i = 0; i < dwellN; i++) {
      frames.push({ t, opt: { angle: topAngle, depth: 0 } });
      t += STEP;
    }
  }
  return { frames, tEnd: t };
}

function holdFrames(t0, count, opts = {}) {
  const out = [];
  let t = t0;
  for (let i = 0; i < count; i++) { out.push({ t, opt: { angle: 178, depth: 0, ...opts } }); t += STEP; }
  return { frames: out, tEnd: t };
}

function run(c, specList) {
  let last = null;
  const reps = [];
  let armBreaks = 0;
  for (const { t, opt, present } of specList) {
    const o = present === false ? { ...opt, present: false } : opt;
    last = c.addFrame(t, makeFrame(o));
    for (const e of last.events) {
      if (e.type === 'rep') reps.push(e.data);
      else armBreaks++;
    }
  }
  return { ...last, allReps: reps, armBreaks };
}

function freshCounter(extra = {}) {
  const c = new Counter({ top: 155, bottom: 100, minRepMs: 400, cleanOnly: false, secondarySignal: 'assist', ...extra });
  return c;
}

// Arm the counter with a clean, valid plank.
function arm(c, t0) {
  const { frames, tEnd } = holdFrames(t0, Math.ceil(3000 / STEP) + 20);
  const out = run(c, frames);
  return { out, t: tEnd };
}

/* ---------- sanity: the generator really produces the requested geometry ---------- */
{
  const lm = makeLandmarks({ angle: 123, depth: 0.5, hipOff: 0.09 });
  check('generator: landmarks produce the requested elbow angle', Math.abs(elbowAngle(lm, 'left') - 123) < 0.5);
  check('generator: requested hip offset is reproduced', Math.abs(hipOffsetOf(lm, 'left') - 0.09) < 0.005);
  check('generator: sag (hip below the shoulder-ankle line) is POSITIVE', hipOffsetOf(makeLandmarks({ angle: 160, hipOff: 0.2 }), 'left') > 0);
  check('generator: pike (hip above the line) is NEGATIVE', hipOffsetOf(makeLandmarks({ angle: 160, hipOff: -0.2 }), 'left') < 0);
  check('generator: body angle of the flat plank is small', Math.abs(bodyAngleOf(makeLandmarks({ angle: 178 }), 'left')) < 12);
  check('generator: 45 deg tilt reads 45 deg', Math.abs(bodyAngleOf(makeLandmarks({ angle: 178, tilt: 45 }), 'left') - 45) < 0.5);
  check('helper: angleBetween vertex maths', Math.abs(angleBetween({ x: 0, y: 1 }, { x: 0, y: 0 }, { x: 1, y: 0 }) - 90) < 1e-9);
}

/* ---------- 1. ten clean full-depth reps ---------- */
{
  const c = freshCounter();
  const a = arm(c, 0);
  check('setup: plank arms after 3s of valid frames', a.out.armed === true && a.out.reps === 0);
  const spec = repFrames(a.t, 10);
  const out = run(c, spec.frames);
  const flags = out.allReps.length ? out.allReps[out.allReps.length - 1].flags : ['<no reps>'];
  console.log('      T1 reps: ' + JSON.stringify(out.allReps.map((r) => ({ n: r.n, f: r.flags, dur: Math.round(r.durationMs), min: +r.minElbow.toFixed(1), mx: r.maxElbow === null ? null : +r.maxElbow.toFixed(1), drop: +r.shoulderDrop.toFixed(3), hipMax: r.hipMax === null ? null : +r.hipMax.toFixed(3) }))));
  check('T1 ten clean reps -> reps=10', out.reps === 10);
  check('T1 repsDetected=10 and cleanReps=10', out.repsDetected === 10 && out.cleanReps === 10);
  check('T1 zero flags on the last rep', flags.length === 0);
  console.log('      T1 detail: reps=' + out.reps + ' clean=' + out.cleanReps + ' detected=' + out.repsDetected + ' lastRepFlags=' + JSON.stringify(flags) + ' state=' + out.state + ' side=' + out.side);
  if (out.lastRep) console.log('      T1 lastRep: ' + JSON.stringify({ minElbow: +out.lastRep.minElbow.toFixed(1), maxElbow: +out.lastRep.maxElbow.toFixed(1), durationMs: Math.round(out.lastRep.durationMs), shoulderDrop: +out.lastRep.shoulderDrop.toFixed(3), hipMax: out.lastRep.hipMax === null ? null : +out.lastRep.hipMax.toFixed(3) }));
}

/* ---------- 2. walking into frame ---------- */
{
  const c = freshCounter();
  const spec = [];
  // 2 s of no pose while the elbows swing through a full rep shape
  let t = 0;
  for (let i = 0; i < Math.round(2000 / STEP); i++) {
    const phase = i / Math.round(2000 / STEP);
    const angle = 178 - 120 * Math.sin(phase * Math.PI);
    spec.push({ t, opt: { angle, depth: phase }, present: false });
    t += STEP;
  }
  // now a valid plank, held for 2 s (still under the 2.5 s arm hold) with one more rep shape
  for (let i = 0; i < Math.round(1000 / STEP); i++) { spec.push({ t, opt: { angle: 178, depth: 0 } }); t += STEP; }
  for (const f of repFrames(t, 1, { downMs: 400, upMs: 400 }).frames) spec.push(f);
  t += repFrames(t, 1, { downMs: 400, upMs: 400 }).tEnd - t;
  for (let i = 0; i < Math.round(2000 / STEP); i++) { spec.push({ t, opt: { angle: 178, depth: 0 } }); t += STEP; }
  const out = run(c, spec);
  check('T2 walking in + rep shape before arm -> 0 reps', out.reps === 0 && out.repsDetected === 0 && out.cleanReps === 0);
  check('T2 not armed during the invalid window', out.armed === false || out.reps === 0);
  console.log('      T2 detail: reps=' + out.reps + ' detected=' + out.repsDetected + ' armed=' + out.armed + ' reasons=' + JSON.stringify(out.plank.reasons) + ' state=' + out.state);
}

/* ---------- 3. kneeling / resting after 5 reps ---------- */
{
  const c = freshCounter();
  const a = arm(c, 0);
  run(c, repFrames(a.t, 5).frames);
  const before = { ...a };
  const afterReps = c.reps;
  check('T3 five reps counted before the rest', afterReps === 5);
  let sawArmBreak = false;
  let t = a.t + 300;
  for (let i = 0; i < 60; i++) {
    const out = c.addFrame(t, makeFrame({ angle: 170, depth: 0, tilt: 45 }));
    if (out.events.some((e) => e.type === 'armBreak')) sawArmBreak = true;
    t += STEP;
  }
  check('T3 kneeling emits armBreak', sawArmBreak);
  check('T3 kneeling adds zero reps', c.reps === 5);
  check('T3 counter disarms and stays idle', c.armed === false && c.state === 'idle');
  console.log('T3 before=' + JSON.stringify({ reps: before.out ? before.out.reps : null }) + ' now=' + c.reps + ' detected=' + c.repsDetected);
}

/* ---------- 4. double beat at the bottom counts one ---------- */
{
  const c = freshCounter();
  const a = arm(c, 0);
  let t = a.t;
  const spec = [];
  const push = (angle, depth, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) spec.push({ t, opt: { angle, depth } });
    t += STEP * n;
  };
  const pushRamp = (from, to, depth, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) {
      const a2 = from + (to - from) * (i / n);
      spec.push({ t, opt: { angle: a2, depth } });
      t += STEP;
    }
  };
  pushRamp(178, 90, 1, 800);
  pushRamp(90, 105, 0.85, 300);
  pushRamp(105, 92, 1, 300);
  pushRamp(92, 178, 0, 700);
  push(178, 0, 400);
  const out = run(c, spec);
  check('T4 double beat at the bottom counts ONE rep', out.reps === 1 && out.repsDetected === 1);
  console.log('      T4 detail: reps=' + out.reps + ' detected=' + out.repsDetected + ' flags=' + JSON.stringify(out.allReps.map((r) => r.flags)));
}

/* ---------- 5. shallow rep, bottom=100, bottoms at 118 ---------- */
{
  // documented rule: a descent only counts if it either (a) reaches bottom on the smoothed angle,
  // or (b) proves real depth with shoulder travel >= 0.10 (assist/confirm modes). Then minElbow >
  // bottom earns the 'half' flag.
  const c = freshCounter();
  const a = arm(c, 0);
  let t = a.t;
  const spec = [];
  const ramp = (from, to, depthFrom, depthTo, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) {
      const k = i / n;
      spec.push({ t, opt: { angle: from + (to - from) * k, depth: depthFrom + (depthTo - depthFrom) * k } });
      t += STEP;
    }
  };
  // shallow with NO body travel -> must not count
  ramp(178, 118, 0, 0.1, 800);
  ramp(118, 178, 0.1, 0, 700);
  for (let i = 0; i < 12; i++) { spec.push({ t, opt: { angle: 178, depth: 0 } }); t += STEP; }
  let out = run(c, spec);
  console.log('      T5a no-travel shallow: reps=' + out.reps + ' detected=' + out.repsDetected + ' clean=' + out.cleanReps);
  check('T5a shallow without shoulder travel counts 0', out.reps === 0 && out.repsDetected === 0);

  // shallow (118) but the body really travelled down (depth 1 -> ~0.12 normalised) -> counts, flagged half
  const spec2 = [];
  let t2 = t;
  const ramp2 = (from, to, depthFrom, depthTo, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) {
      const k = i / n;
      spec2.push({ t: t2, opt: { angle: from + (to - from) * k, depth: depthFrom + (depthTo - depthFrom) * k } });
      t2 += STEP;
    }
  };
  ramp2(178, 118, 0, 1, 800);
  ramp2(118, 178, 1, 0, 700);
  for (let i = 0; i < 12; i++) { spec2.push({ t: t2, opt: { angle: 178, depth: 0 } }); t2 += STEP; }
  out = run(c, spec2);
  const rep = out.allReps.length ? out.allReps[out.allReps.length - 1] : null;
  console.log('      T5b deep-travel shallow: reps=' + out.reps + ' detected=' + out.repsDetected + ' flags=' + JSON.stringify(rep ? rep.flags : null) + ' minElbow=' + (rep ? rep.minElbow.toFixed(1) : '-') + ' shoulderDrop=' + (rep ? rep.shoulderDrop.toFixed(3) : '-'));
  check('T5b shallow-with-travel counts 1 rep and flags it half', out.reps === 1 && !!rep && rep.flags.includes('half'));

  // same rep, cleanOnly -> the flagged rep must not raise `reps` but must raise `repsDetected`
  const c2 = freshCounter({ cleanOnly: true });
  const a2 = arm(c2, 0);
  const spec3 = [];
  let t3 = a2.t;
  const ramp3 = (from, to, d0, d1, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) {
      const k = i / n;
      spec3.push({ t: t3, opt: { angle: from + (to - from) * k, depth: d0 + (d1 - d0) * k } });
      t3 += STEP;
    }
  };
  ramp3(178, 118, 0, 1, 800);
  ramp3(118, 178, 1, 0, 700);
  for (let i = 0; i < 12; i++) { spec3.push({ t: t3, opt: { angle: 178, depth: 0 } }); }
  const out2 = run(c2, spec3);
  console.log('      T5c cleanOnly: reps=' + out2.reps + ' detected=' + out2.repsDetected + ' clean=' + out2.cleanReps + ' flags=' + JSON.stringify(out2.trace.length ? null : null));
  check('T5c cleanOnly keeps flagged reps out of `reps` but keeps repsDetected', out2.reps === 0 && out2.repsDetected === 1 && out2.cleanReps === 0);
}

/* ---------- 6. sagging hips ---------- */
{
  const c = freshCounter();
  const a = arm(c, 0);
  const spec = [];
  let t = a.t;
  const downN = Math.round(800 / STEP);
  for (let i = 1; i <= downN; i++) {
    const k = i / downN;
    const opt = { angle: 178 + (92 - 178) * k, depth: k };
    // a brief, real sag excursion (5 frames at +0.25) — sustained sag would disarm instead
    if (i >= 14 && i <= 18) opt.hipOff = 0.25;
    spec.push({ t, opt });
    t += STEP;
  }
  for (let i = 1; i <= Math.round(700 / STEP); i++) {
    const k = i / Math.round(700 / STEP);
    spec.push({ t, opt: { angle: 92 + (178 - 92) * k, depth: 1 - k } });
    t += STEP;
  }
  for (let i = 0; i < 12; i++) { spec.push({ t, opt: { angle: 178, depth: 0 } }); t += STEP; }
  const out = run(c, spec);
  const rep = out.allReps.length ? out.allReps[out.allReps.length - 1] : null;
  console.log('      T6 detail: reps=' + out.reps + ' flags=' + JSON.stringify(rep ? rep.flags : null) + ' hipMax=' + (rep && rep.hipMax !== null ? rep.hipMax.toFixed(3) : '-') + ' plankValid=' + out.plank.valid);
  check('T6 sag excursion flags the rep', out.reps === 1 && !!rep && rep.flags.includes('sag'));
  check('T6 a brief sag does not break the arm lock', c.armed === true);
}

/* ---------- 7. minRepMs rejects a bounce ---------- */
{
  const c = freshCounter();
  const a = arm(c, 0);
  let t = a.t;
  const spec = [];
  const ramp = (from, to, depth, ms) => {
    const n = Math.max(1, Math.round(ms / STEP));
    for (let i = 1; i <= n; i++) {
      spec.push({ t, opt: { angle: from + (to - from) * (i / n), depth } });
      t += STEP;
    }
  };
  ramp(178, 92, 1, 75);
  ramp(92, 178, 0, 75);
  for (let i = 0; i < 20; i++) { spec.push({ t, opt: { angle: 178, depth: 0 } }); t += STEP; }
  const out = run(c, spec);
  console.log('      T7 detail: reps=' + out.reps + ' detected=' + out.repsDetected + ' state=' + out.state + ' armed=' + out.armed + ' traceMinElbow=' + Math.min(...c.trace.map((x) => (x.elbowFiltered === null ? 999 : x.elbowFiltered))).toFixed(1));
  check('T7 150 ms bounce rejected (minRepMs=400)', out.reps === 0 && out.repsDetected === 0);

  // same rep shape but slow enough to bottom, with minRepMs raised -> the duration gate rejects it
  const c2 = freshCounter({ minRepMs: 2200 });
  const a2 = arm(c2, 0);
  let t2 = a2.t;
  const spec2 = [];
  const ramp2 = (from, to, depthFrom, depthTo, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) {
      const k = i / n;
      spec2.push({ t: t2, opt: { angle: from + (to - from) * k, depth: depthFrom + (depthTo - depthFrom) * k } });
      t2 += STEP;
    }
  };
  ramp2(178, 92, 0, 1, 800);
  ramp2(92, 178, 1, 0, 700);
  for (let i = 0; i < 12; i++) { spec2.push({ t: t2, opt: { angle: 178, depth: 0 } }); }
  const out2 = run(c2, spec2);
  const c3 = freshCounter();
  const a3 = arm(c3, 0);
  const out3 = run(c3, repFrames(a3.t, 1).frames);
  console.log('      T7b detail: minRepMs=2200 -> reps=' + out2.reps + ' detected=' + out2.repsDetected + ' | minRepMs=400 same rep -> reps=' + out3.reps + ' duration=' + (out3.lastRep ? Math.round(out3.lastRep.durationMs) : '-'));
  check('T7b duration gate rejects a 1500 ms rep when minRepMs=2200', out2.reps === 0 && out2.repsDetected === 0);
  check('T7c the same rep counts when minRepMs=400', out3.reps === 1);
}

/* ---------- extra: 'notSide' gate, armBreak on lost pose, reset ---------- */
{
  const c = freshCounter();
  const a = arm(c, 0);
  const out = c.addFrame(a.t, makeFrame({ angle: 178, depth: 0, tilt: 80 }));
  console.log('      extra: tilt 80 -> reasons=' + JSON.stringify(out.plank.reasons) + ' bodyAngle=' + out.bodyAngle.toFixed(1));
  check('extra: steep tilt reports bodyAngle', out.plank.reasons.includes('bodyAngle'));

  const c2 = freshCounter();
  const a2 = arm(c2, 0);
  let sawBreak = false;
  for (let i = 0; i < 5; i++) {
    const o = c2.addFrame(a2.t + i * STEP, makeFrame({ angle: 178, present: false }));
    if (o.events.some((e) => e.type === 'armBreak')) sawBreak = true;
  }
  check('extra: losing the pose while armed emits armBreak', sawBreak && c2.armed === false);

  const c3 = freshCounter();
  run(c3, arm(c3, 0).frames || []);
  const a3 = arm(c3, 0);
  run(c3, repFrames(a3.t, 3).frames);
  check('extra: reps counted before reset', c3.reps === 3);
  c3.reset('test');
  check('extra: reset zeros counts and state', c3.reps === 0 && c3.repsDetected === 0 && c3.cleanReps === 0 && c3.state === 'idle' && c3.armed === false && c3.trace.length === 0);

  const out4 = c3.addFrame(0, { landmarks: null, present: true, quality: 0, fps: 30 });
  check('extra: malformed frame does not throw', out4 && out4.reps === 0 && out4.plank.reasons.includes('noPose'));
  const out5 = c3.addFrame(1, { landmarks: new Array(10).fill({ x: 0.5, y: 0.5, z: 0, visibility: 1 }), present: true, quality: 1, fps: 30 });
  check('extra: short landmark array treated as noPose', out5.plank.reasons.includes('noPose'));
}

/* ---------- extra: lockout reversal, partial ascent discard, shoulder-travel maths ---------- */
{
  // rises to 148 (inside [top-12, top)) then descends again -> counts, flagged 'lockout'
  const c = freshCounter();
  const a = arm(c, 0);
  let t = a.t;
  const spec = [];
  const ramp = (from, to, d0, d1, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) {
      const k = i / n;
      spec.push({ t, opt: { angle: from + (to - from) * k, depth: d0 + (d1 - d0) * k } });
      t += STEP;
    }
  };
  ramp(178, 92, 0, 1, 800);
  ramp(92, 148, 1, 0.45, 500);
  ramp(148, 92, 0.45, 1, 500);
  ramp(92, 178, 1, 0, 700);
  for (let i = 0; i < 12; i++) spec.push({ t, opt: { angle: 178, depth: 0 } });
  const out = run(c, spec);
  console.log('      extra lockout: reps=' + out.reps + ' detected=' + out.repsDetected + ' flags=' + JSON.stringify(out.allReps.map((r) => r.flags)));
  check('extra: incomplete lockout counts and is flagged', out.reps === 1 && out.allReps.length === 1 && out.allReps[0].flags.includes('lockout'));

  // rises only to 130 (well short of top-12) -> not a rep at all
  const c2 = freshCounter();
  const a2 = arm(c2, 0);
  let t2 = a2.t;
  const spec2 = [];
  const ramp2 = (from, to, d0, d1, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) {
      const k = i / n;
      spec2.push({ t: t2, opt: { angle: from + (to - from) * k, depth: d0 + (d1 - d0) * k } });
      t2 += STEP;
    }
  };
  ramp2(178, 92, 0, 1, 800);
  ramp2(92, 130, 1, 0.6, 500);
  ramp2(130, 92, 0.6, 1, 500);
  ramp2(92, 178, 1, 0, 700);
  for (let i = 0; i < 12; i++) spec2.push({ t: t2, opt: { angle: 178, depth: 0 } });
  const out2 = run(c2, spec2);
  console.log('      extra short-ascent: reps=' + out2.reps + ' detected=' + out2.repsDetected + ' (the two half-movements merge into one rep)');
  check('extra: reversing short of top-12 is not a rep on its own', out2.repsDetected <= 1);

  // shoulder travel of a proper side-on rep lands in the documented 0.10-0.25 band
  const c3 = freshCounter();
  const a3 = arm(c3, 0);
  const out3 = run(c3, repFrames(a3.t, 3).frames);
  const drops = out3.allReps.map((r) => +r.shoulderDrop.toFixed(3));
  console.log('      extra travel: shoulderDrop per rep = ' + JSON.stringify(drops));
  check('extra: full-depth reps report 0.10-0.25 of normalised shoulder travel', drops.length === 3 && drops.every((d) => d >= 0.10 && d <= 0.25));
}

console.log(failures === 0 ? '\nALL CHECKS PASSED' : `\n${failures} CHECK(S) FAILED`);
process.exitCode = failures === 0 ? 0 : 1;
