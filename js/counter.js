import { OneEuro } from './one-euro.js';

export const LANDMARKS = {
  NOSE: 0, L_SHOULDER: 11, R_SHOULDER: 12, L_ELBOW: 13, R_ELBOW: 14,
  L_WRIST: 15, R_WRIST: 16, L_HIP: 23, R_HIP: 24, L_KNEE: 25, R_KNEE: 26,
  L_ANKLE: 27, R_ANKLE: 28,
};

const SIDE_PTS = {
  left: { shoulder: 11, elbow: 13, wrist: 15, hip: 23, knee: 25, ankle: 27 },
  right: { shoulder: 12, elbow: 14, wrist: 16, hip: 24, knee: 26, ankle: 28 },
};

const MIN_LM_VIS = 0.1;
const QUALITY_EMA_ALPHA = 0.2;
const SIDE_SWITCH_MARGIN = 0.08;
const QUALITY_MIN = 0.35;
const QUALITY_LOST = 0.15;
const QUALITY_REP_MIN = 0.4;
/* A phone lying on the floor — the setup this app asks for — sees a straight plank as a line
   tilted 30 degrees or more, because the body sits half a metre above the lens and perspective
   pulls the far end toward the horizon. Demanding "level" therefore rejects every real set. What
   the angle can still prove is that the subject is upright, so that is all it is used for;
   straightness is hipOffset's job, and a perpendicular deviation is tilt-invariant. */
const BODY_ANGLE_MAX = 70;
const HIP_GATE = 0.16;
const HIP_GATE_EMA_ALPHA = 0.12;
// Landmarks are normalised per-axis, so the frame diagonal is unknown. A 4:3 sensor is assumed.
const FRAME_DIAGONAL = Math.hypot(1, 0.75);
const NOTSIDE_MIN_DX = 0.15 * FRAME_DIAGONAL;
const HYST = 8;
const BOTTOM_ZONE = 15;
const LOCKOUT_ZONE = 12;
const ASSIST_DEPTH = 0.10;
const SHALLOW_DROP_GATE = 0.08;
const SAG_LIMIT = 0.18;
const PIKE_LIMIT = -0.14;
const FAST_SLACK_MS = 120;
const SLOW_MS = 6000;
const REVERSAL_HYST = 10;
const TRACE_LEN = 45;

function num(v) {
  return typeof v === 'number' && Number.isFinite(v);
}

function point(lm, i) {
  if (!Array.isArray(lm) || lm.length <= i) return null;
  const p = lm[i];
  if (!p || !num(p.x) || !num(p.y)) return null;
  if ((num(p.visibility) ? p.visibility : 0) < MIN_LM_VIS) return null;
  return p;
}

function midPoint(lm, i, j) {
  const a = point(lm, i);
  const b = point(lm, j);
  if (!a || !b) return null;
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
}

function hipPoint(lm, side) {
  const k = side ? SIDE_PTS[side] : null;
  if (k) {
    const p = point(lm, k.hip);
    if (p) return p;
  }
  return midPoint(lm, LANDMARKS.L_HIP, LANDMARKS.R_HIP);
}

function bodyLine(lm, side) {
  const k = side ? SIDE_PTS[side] : null;
  let S = k ? point(lm, k.shoulder) : null;
  let A = k ? point(lm, k.ankle) : null;
  // Prefer the measured side's own endpoints: when the body folds toward vertical only that
  // side's shoulder and ankle travel together, the far side would keep the line horizontal.
  if (!S) S = midPoint(lm, LANDMARKS.L_SHOULDER, LANDMARKS.R_SHOULDER);
  if (!A) A = midPoint(lm, LANDMARKS.L_ANKLE, LANDMARKS.R_ANKLE);
  if (!S || !A) return null;
  const dx = A.x - S.x;
  const dy = A.y - S.y;
  const len = Math.hypot(dx, dy);
  if (!(len > 1e-6)) return null;
  return { S, A, dx, dy, len };
}

export function angleBetween(a, b, c) {
  if (!a || !b || !c) return null;
  const v1x = a.x - b.x, v1y = a.y - b.y;
  const v2x = c.x - b.x, v2y = c.y - b.y;
  const m1 = Math.hypot(v1x, v1y);
  const m2 = Math.hypot(v2x, v2y);
  if (!(m1 > 1e-6) || !(m2 > 1e-6)) return null;
  let cos = (v1x * v2x + v1y * v2y) / (m1 * m2);
  cos = Math.max(-1, Math.min(1, cos));
  return Math.acos(cos) * 180 / Math.PI;
}

export function elbowAngle(lm, side) {
  const k = SIDE_PTS[side];
  if (!k) return null;
  return angleBetween(point(lm, k.shoulder), point(lm, k.elbow), point(lm, k.wrist));
}

export function shoulderAngle(lm, side) {
  const k = SIDE_PTS[side];
  if (!k) return null;
  return angleBetween(point(lm, k.elbow), point(lm, k.shoulder), point(lm, k.hip));
}

// Signed, line-length-normalised perpendicular distance of the hip from the shoulder-ankle line.
// The normal is forced to point toward larger image y (the floor), so sagging hips are POSITIVE
// and piked hips NEGATIVE for both facing directions.
export function hipOffsetOf(lm, side = null) {
  const g = bodyLine(lm, side);
  if (!g) return null;
  const H = hipPoint(lm, side);
  if (!H) return null;
  let nx = -g.dy;
  let ny = g.dx;
  if (ny < 0) { nx = -nx; ny = -ny; }
  const m = Math.hypot(nx, ny);
  if (!(m > 1e-6)) return null;
  nx /= m; ny /= m;
  return ((H.x - g.S.x) * nx + (H.y - g.S.y) * ny) / g.len;
}

// atan2(-dy, dx) folded into (-90, 90] so a horizontal plank reads near 0 whichever way the
// subject faces. Sign of dx is kept available through dxOf(); 'notSide' uses |dx|.
export function bodyAngleOf(lm, side = null) {
  const g = bodyLine(lm, side);
  if (!g) return null;
  let deg = Math.atan2(-g.dy, g.dx) * 180 / Math.PI;
  if (deg > 90) deg -= 180;
  else if (deg < -90) deg += 180;
  return deg;
}

export function dxOf(lm, side = null) {
  const g = bodyLine(lm, side);
  return g ? g.dx : null;
}

// (shoulder.y - ankle.y) / |shoulder->ankle|. Grows as the body travels down: a proper side-on
// pushup moves this by roughly 0.10-0.25 between the top and the bottom position.
export function shoulderNormOf(lm, side = null) {
  const g = bodyLine(lm, side);
  if (!g) return null;
  return (g.S.y - g.A.y) / g.len;
}

// A 2-tap median is just a mean, so the spike killer is 3 taps wide.
class MedianFilter {
  constructor(size = 3) {
    this.size = Math.max(1, size);
    this.buf = [];
  }
  reset() { this.buf = []; }
  push(v) {
    if (!num(v)) return null;
    this.buf.push(v);
    if (this.buf.length > this.size) this.buf.shift();
    const s = this.buf.slice().sort((a, b) => a - b);
    const k = (s.length - 1) / 2;
    const lo = Math.floor(k);
    const hi = Math.ceil(k);
    return s[lo] + (s[hi] - s[lo]) * (k - lo);
  }
}

function cleanParams(params) {
  const p = params || {};
  return {
    top: num(p.top) ? p.top : 155,
    bottom: num(p.bottom) ? p.bottom : 100,
    minRepMs: num(p.minRepMs) ? p.minRepMs : 400,
    cleanOnly: !!p.cleanOnly,
    secondarySignal: p.secondarySignal === 'off' || p.secondarySignal === 'confirm'
      ? p.secondarySignal : 'assist',
  };
}

function emptyRep() {
  return {
    tStart: null, tCrossBottom: null, minElbow: null, maxElbow: null,
    dropBase: null, normMin: null, normMax: null, shoulderDrop: 0,
    hipMax: null, hipMin: null,
    lowQuality: false, halfByTravel: false, side: null,
  };
}

export class Counter {
  constructor(params) {
    this.params = cleanParams(params);
    this.armHoldMs = 2500;
    this.reset('init');
  }

  setParams(params) {
    this.params = cleanParams({ ...this.params, ...params });
  }

  setArmHold(ms) {
    this.armHoldMs = num(ms) && ms >= 0 ? ms : 2500;
  }

  reset(reason) {
    this.lastResetReason = reason || null;
    this.reps = 0;
    this.repsDetected = 0;
    this.cleanReps = 0;
    this.state = 'idle';
    this.armed = false;
    this.armStreakStart = null;
    this.armLockedAt = null;
    this.side = null;
    this.qVis = { left: null, right: null };
    this.quality = 0;
    this.euro = new OneEuro({ minCutoff: 1.1, beta: 0.02, dCutoff: 1.0 });
    this.medElbow = new MedianFilter(3);
    this.medHip = new MedianFilter(3);
    this.hipEma = null;
    this.rep = emptyRep();
    this.lastRep = null;
    this.events = [];
    this.trace = [];
    this.normBaseline = null;
    this.lastActiveMs = null;
    this.lastT = null;
  }

  _touch(t) { this.lastActiveMs = t; }

  _clearFilters() {
    this.euro.reset();
    this.medElbow.reset();
    this.medHip.reset();
    this.hipEma = null;
    this.normBaseline = null;
  }

  _dropInFlight() {
    this.rep = emptyRep();
    this.state = 'idle';
  }

  _updateSideQuality(lm) {
    if (!lm) return;
    for (const side of ['left', 'right']) {
      const k = SIDE_PTS[side];
      const ids = [k.shoulder, k.elbow, k.wrist, k.hip, k.ankle];
      let sum = 0;
      let n = 0;
      for (const i of ids) {
        const p = Array.isArray(lm) && lm.length > i ? lm[i] : null;
        if (p && num(p.visibility)) { sum += p.visibility; n++; }
      }
      if (!n) continue;
      const mean = sum / n;
      const prev = this.qVis[side];
      this.qVis[side] = prev === null
        ? mean
        : prev + QUALITY_EMA_ALPHA * (mean - prev);
    }

    const L = this.qVis.left;
    const R = this.qVis.right;
    if (this.side === null) {
      if (L !== null || R !== null) this.side = (R !== null && L !== null && R > L) ? 'right' : 'left';
    } else {
      const cur = this.qVis[this.side];
      const other = this.side === 'left' ? 'right' : 'left';
      const oth = this.qVis[other];
      if (oth !== null && cur !== null && oth > cur + SIDE_SWITCH_MARGIN) this.side = other;
    }
    this.quality = this.side ? (this.qVis[this.side] || 0) : 0;
  }

  _plank(present, quality, dx, bodyAngle, hipForGate) {
    const reasons = [];
    if (!present || !num(dx) || !num(bodyAngle) || quality <= 0) {
      reasons.push('noPose');
    } else {
      if (quality < QUALITY_MIN) reasons.push('lowVis');
      if (Math.abs(dx) < NOTSIDE_MIN_DX) reasons.push('notSide');
      if (Math.abs(bodyAngle) > BODY_ANGLE_MAX) reasons.push('bodyAngle');
      if (num(hipForGate) && Math.abs(hipForGate) > HIP_GATE) reasons.push('hip');
    }
    return { valid: reasons.length === 0, reasons };
  }

  _startRep(t, e, side, shoulderNorm) {
    this.rep = emptyRep();
    this.rep.tStart = t;
    this.rep.minElbow = e;
    this.rep.side = side;
    // Travel is measured from the held top position, not from the (lagging) moment the angle
    // crosses top-8, otherwise smoothing eats a fifth of every rep's measured depth.
    let base = num(this.normBaseline) ? this.normBaseline : null;
    if (num(shoulderNorm)) base = base === null ? shoulderNorm : Math.min(base, shoulderNorm);
    this.rep.dropBase = base;
    this.rep.normMin = base;
    this.rep.normMax = base;
    this.state = 'down';
    this._touch(t);
  }

  _observeRep(e, quality, hip, shoulderNorm) {
    const r = this.rep;
    if (r.tStart === null) return;
    if (num(e)) {
      if (r.minElbow === null || e < r.minElbow) r.minElbow = e;
      // maxElbow belongs to the up phase only; seeding it at the top of the descent would
      // make every rep look like it reversed straight out of the bottom.
      if (this.state === 'up' && (r.maxElbow === null || e > r.maxElbow)) r.maxElbow = e;
    }
    if (quality < QUALITY_REP_MIN) r.lowQuality = true;
    if (num(hip)) {
      if (r.hipMax === null || hip > r.hipMax) r.hipMax = hip;
      if (r.hipMin === null || hip < r.hipMin) r.hipMin = hip;
    }
    if (num(shoulderNorm)) {
      if (r.normMin === null || shoulderNorm < r.normMin) r.normMin = shoulderNorm;
      if (r.normMax === null || shoulderNorm > r.normMax) r.normMax = shoulderNorm;
      const d = r.normMax - r.normMin;
      if (d > r.shoulderDrop) r.shoulderDrop = d;
    }
  }

  _complete(t, e, lockout) {
    const p = this.params;
    const r = this.rep;
    const hadDescent = r.tStart !== null;
    const durationMs = hadDescent ? t - r.tStart : 0;
    const minElbow = num(r.minElbow) ? r.minElbow : e;
    const maxElbow = num(r.maxElbow) ? r.maxElbow : e;
    const bottomed = r.tCrossBottom !== null || r.halfByTravel;

    this.state = 'hold';
    this.rep = emptyRep();

    if (!hadDescent || !bottomed || durationMs < p.minRepMs) {
      this._touch(t);
      return null;
    }

    const flags = [];
    if (minElbow > p.bottom) flags.push('half');
    if (lockout) flags.push('lockout');
    if (num(r.hipMax) && r.hipMax > SAG_LIMIT) flags.push('sag');
    if (num(r.hipMin) && r.hipMin < PIKE_LIMIT) flags.push('pike');
    if (r.lowQuality || this.quality < QUALITY_REP_MIN) flags.push('lost');
    if (durationMs < p.minRepMs + FAST_SLACK_MS) flags.push('fast');
    if (durationMs > SLOW_MS) flags.push('slow');
    if (p.secondarySignal === 'confirm' && r.normMin !== null) {
      if (r.shoulderDrop < SHALLOW_DROP_GATE) flags.push('shallow');
    }

    this.repsDetected++;
    if (flags.length === 0) this.cleanReps++;
    if (flags.length === 0 || !p.cleanOnly) this.reps++;

    const rep = {
      n: this.repsDetected,
      tStart: r.tStart,
      tEnd: t,
      durationMs,
      minElbow,
      maxElbow,
      shoulderDrop: num(r.shoulderDrop) ? r.shoulderDrop : 0,
      hipMax: num(r.hipMax) ? r.hipMax : null,
      hipMin: num(r.hipMin) ? r.hipMin : null,
      flags,
      side: r.side || this.side,
    };
    // spec spells these hipMin/hipMax the other way round; the values themselves are
    // (max positive = sag, most negative = pike), so keep both names meaning min/max.
    this.lastRep = rep;
    this.events.push({ type: 'rep', t, data: rep });
    this._touch(t);
    return rep;
  }

  _step(t, e, hip, shoulderNorm, sideTravelAllowed) {
    const p = this.params;
    const top = p.top;
    const bottom = p.bottom;
    const r = this.rep;

    switch (this.state) {
      case 'idle':
        if (e < top - HYST) this._startRep(t, e, this.side, shoulderNorm);
        break;

      case 'hold':
        if (e < top - HYST) this._startRep(t, e, this.side, shoulderNorm);
        break;

      case 'down': {
        this._observeRep(e, this.quality, hip, shoulderNorm);
        if (r.tCrossBottom === null && e <= bottom + BOTTOM_ZONE) r.tCrossBottom = t;

        if (e <= bottom) {
          this.state = 'bottom';
          this._touch(t);
          break;
        }
        // shoulder travel proves real depth even when the elbow never reaches `bottom`:
        // the rep stays alive and earns 'half' on completion. Checked before the
        // back-to-top discard so a genuine shallow rep is not thrown away.
        if (sideTravelAllowed && !r.halfByTravel
            && r.shoulderDrop >= ASSIST_DEPTH
            && r.minElbow !== null && e >= r.minElbow + REVERSAL_HYST) {
          r.halfByTravel = true;
          if (r.maxElbow === null) r.maxElbow = e;
          this.state = 'up';
          this._touch(t);
          break;
        }
        if (e >= top - HYST) {
          // never got deep: not a rep, arms are back up
          this.rep = emptyRep();
          this.state = 'hold';
          this._touch(t);
          break;
        }
        break;
      }

      case 'bottom':
        this._observeRep(e, this.quality, hip, shoulderNorm);
        if (r.tCrossBottom === null && e <= bottom + BOTTOM_ZONE) r.tCrossBottom = t;
        if (e > bottom + HYST) {
          if (r.maxElbow === null) r.maxElbow = e;
          this.state = 'up';
          this._touch(t);
        }
        break;

      case 'up': {
        this._observeRep(e, this.quality, hip, shoulderNorm);
        if (e >= top) {
          this._complete(t, e, false);
          break;
        }
        if (e <= bottom) {
          this.state = 'bottom';
          break;
        }
        const nearBottomZone = e <= bottom + BOTTOM_ZONE && r.maxElbow !== null
          && r.maxElbow < top - LOCKOUT_ZONE;
        if (nearBottomZone) {
          this.state = 'bottom';
          break;
        }
        if (r.maxElbow !== null && e <= r.maxElbow - HYST) {
          if (r.maxElbow >= top - LOCKOUT_ZONE) this._complete(t, e, true);
          else {
            this.rep = emptyRep();
            this.state = 'idle';
            this._touch(t);
          }
        }
        break;
      }

      default:
        this.state = 'idle';
    }
  }

  addFrame(tMs, frame) {
    try {
      return this._addFrame(tMs, frame);
    } catch (err) {
      const ev = this.events;
      this.events = [];
      return {
        reps: this.reps, repsDetected: this.repsDetected, cleanReps: this.cleanReps,
        state: 'idle', armed: false, armMs: 0, quality: 0, side: this.side,
        angles: { left: { elbow: null, shoulder: null }, right: { elbow: null, shoulder: null } },
        hipOffset: null, bodyAngle: null,
        plank: { valid: false, reasons: ['noPose'] },
        lastRep: null, events: ev, trace: this.trace,
        lastActiveMs: this.lastActiveMs, error: err && err.message ? err.message : String(err),
      };
    }
  }

  _addFrame(tMs, frame) {
    const p = this.params;
    this.events = [];
    this.lastRep = null;

    const lm = frame && Array.isArray(frame.landmarks) ? frame.landmarks : null;
    const present = !!(frame && frame.present && lm && lm.length > LANDMARKS.R_ANKLE);
    const t = num(tMs) ? tMs : (this.lastT === null ? 0 : this.lastT);

    this._updateSideQuality(present ? lm : null);
    const side = this.side;

    const rawElbow = present ? elbowAngle(lm, side) : null;
    const angles = {
      left: { elbow: present ? elbowAngle(lm, 'left') : null, shoulder: present ? shoulderAngle(lm, 'left') : null },
      right: { elbow: present ? elbowAngle(lm, 'right') : null, shoulder: present ? shoulderAngle(lm, 'right') : null },
    };
    const rawHip = present ? hipOffsetOf(lm, side) : null;
    const bodyAngle = present ? bodyAngleOf(lm, side) : null;
    const dx = present ? dxOf(lm, side) : null;
    const rawNorm = present ? shoulderNormOf(lm, side) : null;

    let elbow = null;
    let hip = null;
    let shoulderNorm = null;
    if (present) {
      shoulderNorm = num(rawNorm) ? rawNorm : null;
      if (num(rawHip)) {
        const m = this.medHip.push(rawHip);
        hip = num(m) ? m : null;
        if (hip !== null) {
          this.hipEma = this.hipEma === null ? hip : this.hipEma + HIP_GATE_EMA_ALPHA * (hip - this.hipEma);
        }
      }
      if (num(rawElbow)) {
        const m = this.medElbow.push(rawElbow);
        if (m !== null) {
          const f = this.euro.filter(t, m);
          if (num(f)) elbow = f;
        }
      }
    } else {
      this.medHip.reset();
      this.medElbow.reset();
      this.hipEma = null;
      this.euro.reset();
    }

    const plank = this._plank(present, this.quality, dx, bodyAngle, this.hipEma);

    if (!plank.valid) {
      this.armStreakStart = null;
      if (this.armed) {
        this.armed = false;
        this.armLockedAt = null;
        this._dropInFlight();
        this._clearFilters();
        this.events.push({ type: 'armBreak', t, data: { reason: plank.reasons[0] || 'noPose', t } });
        this._touch(t);
      } else {
        this._dropInFlight();
        if (!present) this._clearFilters();
      }
    } else {
      if (this.armStreakStart === null) this.armStreakStart = t;
      if (!this.armed) {
        if (t - this.armStreakStart >= this.armHoldMs) {
          this.armed = true;
          this.armLockedAt = t;
          this._clearFilters();
          this._dropInFlight();
          this._touch(t);
        }
      } else {
        this._touch(t);
      }

      if (this.armed && elbow !== null) {
        this._step(t, elbow, hip, shoulderNorm, p.secondarySignal !== 'off');
      }
      if (this.armed && num(shoulderNorm)) {
        // Top-of-rep reference for shoulder travel: snaps down to a new high body position and
        // creeps back up slowly, so filter lag at the start of a descent cannot eat the depth.
        if (this.normBaseline === null || shoulderNorm < this.normBaseline) this.normBaseline = shoulderNorm;
        else this.normBaseline += 0.004 * (shoulderNorm - this.normBaseline);
      }
    }

    this.lastT = t;

    this.trace.push({
      t,
      elbowRaw: rawElbow,
      elbowFiltered: elbow,
      hipOffset: hip,
      shoulderNorm,
      quality: this.quality,
    });
    if (this.trace.length > TRACE_LEN) this.trace.shift();

    const events = this.events;
    this.events = [];

    return {
      reps: this.reps,
      repsDetected: this.repsDetected,
      cleanReps: this.cleanReps,
      state: this.state,
      armed: this.armed,
      armMs: this.armed && this.armLockedAt !== null ? t - this.armLockedAt : 0,
      quality: this.quality,
      side,
      angles,
      hipOffset: hip,
      bodyAngle,
      plank,
      lastRep: this.lastRep,
      events,
      trace: this.trace,
      lastActiveMs: this.lastActiveMs,
    };
  }
}
