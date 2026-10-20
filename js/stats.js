/* Aggregation over saved sets + reps. Pure functions: every entry point takes plain arrays so the
   whole layer is testable without IndexedDB, and views decide what to fetch.
   Week = Monday..Sunday (local). All day keys are 'YYYY-MM-DD' from db.localDay. */

import { mean, sum } from './util.js';

const DAY_MS = 86400000;

/* ── calendar helpers ──────────────────────────────────────────── */

export function dayKey(ms) {
  const d = new Date(ms);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return y + '-' + m + '-' + day;
}

export function dayFromKey(key) {
  const [y, m, d] = String(key).split('-').map(Number);
  return new Date(y, (m || 1) - 1, d || 1).getTime();
}

export function addDays(key, n) {
  return dayKey(dayFromKey(key) + n * DAY_MS);
}

/** Monday of the week containing `key`. */
export function weekStart(key) {
  const t = dayFromKey(key);
  const dow = (new Date(t).getDay() + 6) % 7;   // 0 = Monday
  return dayKey(t - dow * DAY_MS);
}

export function monthKey(key) { return String(key).slice(0, 7); }
export function yearKey(key) { return String(key).slice(0, 4); }

export function daysBetween(a, b) {
  return Math.round((dayFromKey(b) - dayFromKey(a)) / DAY_MS);
}

/* ── per-day totals ────────────────────────────────────────────── */

/** Map of 'YYYY-MM-DD' -> { day, reps, sets, flagged, clean, minutes, best, manual }. */
export function byDay(sets) {
  const map = new Map();
  for (const s of sets || []) {
    const day = s.day || dayKey(s.startedAt || Date.now());
    let d = map.get(day);
    if (!d) {
      d = { day, reps: 0, sets: 0, flagged: 0, clean: 0, minutes: 0, best: 0, manual: 0, detected: 0 };
      map.set(day, d);
    }
    const reps = Number(s.repsFinal) || 0;
    d.reps += reps;
    d.detected += Number(s.repsDetected) || 0;
    d.sets += 1;
    d.minutes += (Number(s.durationMs) || 0) / 60000;
    d.best = Math.max(d.best, reps);
    if (s.source === 'manual' || s.mode === 'manual') d.manual += 1;
    const f = s.flags || {};
    const flagged = (f.sag || 0) + (f.pike || 0) + (f.half || 0) + (f.lockout || 0) + (f.lost || 0);
    d.flagged += flagged;
    d.clean += Math.max(0, reps - flagged);
  }
  return map;
}

export function dayTotals(sets, key) {
  return byDay(sets).get(key) || emptyDay(key);
}

function emptyDay(key) {
  return { day: key, reps: 0, sets: 0, flagged: 0, clean: 0, minutes: 0, best: 0, manual: 0, detected: 0 };
}

/** Contiguous run of days with reps > 0, counting back from `fromKey` (or from the last training day). */
export function trainingStreak(days, fromKey) {
  const has = (k) => { const d = days.get(k); return !!d && d.reps > 0; };
  let cursor = fromKey || dayKey(Date.now());
  if (!has(cursor)) cursor = addDays(cursor, -1);      // today not done yet does not kill yesterday's streak
  let n = 0;
  while (n < 4000 && has(cursor)) { n += 1; cursor = addDays(cursor, -1); }
  return n;
}

/**
 * Streak of weeks where the weekly goal was met, counting back from the current week.
 * The in-progress week only counts if it already reached the goal, so a fresh Monday
 * never shows a streak of zero just because the week is young.
 */
export function weeklyGoalStreak(days, goalReps, fromKey) {
  const start = weekStart(fromKey || dayKey(Date.now()));
  const weeks = weekBuckets(days, 260);
  const met = new Map(weeks.map((w) => [w.key, w.reps >= goalReps]));
  let n = 0;
  for (let i = 0; i < 260; i++) {
    const done = met.get(weekStart(addDays(start, -7 * i)));
    if (done) { n += 1; continue; }
    if (i === 0) continue;          // this week is still young — it neither counts nor breaks
    break;
  }
  return n;
}

/**
 * Consecutive days meeting the daily goal, walking back from today. A day with a rest pass
 * spent on it counts as met, which is how `passes` (a set of day keys) keeps a streak alive.
 */
export function dailyGoalStreak(days, goalReps, fromKey, passes) {
  const spent = passes instanceof Set ? passes : new Set(passes || []);
  const met = (k) => {
    const d = days.get(k);
    return (d && d.reps >= goalReps) || spent.has(k);
  };
  let cursor = fromKey || dayKey(Date.now());
  if (!met(cursor) && !spent.has(cursor)) cursor = addDays(cursor, -1);
  let n = 0;
  while (n < 4000 && (met(cursor) || spent.has(cursor))) { n += 1; cursor = addDays(cursor, -1); }
  return n;
}

/* ── bucketed series ───────────────────────────────────────────── */

function bucketize(days, count, keyOf, startOf, stepOf) {
  const out = [];
  const today = keyOf(Date.now());
  const anchor = startOf(today);
  for (let i = count - 1; i >= 0; i--) {
    const key = stepOf(anchor, -i);
    out.push({ key, from: key, to: key, reps: 0, sets: 0, minutes: 0, best: 0, days: 0, flagged: 0, clean: 0 });
  }
  const index = new Map(out.map((b, i) => [b.key, i]));
  for (const d of days.values()) {
    const k = index.get(keyOf(dayFromKey(d.day)));
    if (k === undefined) continue;
    const b = out[k];
    b.reps += d.reps;
    b.sets += d.sets;
    b.minutes += d.minutes;
    b.flagged += d.flagged;
    b.clean += d.clean;
    b.best = Math.max(b.best, d.best);
    if (d.reps > 0) b.days += 1;
  }
  for (const b of out) {
    b.minutes = Math.round(b.minutes);
    b.avgPerSet = b.sets ? Math.round(b.reps / b.sets) : 0;
  }
  return out;
}

/** Last `count` days, oldest first, including today. */
export function dayBuckets(days, count = 90) {
  return bucketize(days, count, (t) => dayKey(t), (todayKey) => todayKey, (k, n) => addDays(k, n));
}

/** Last `count` weeks keyed by their Monday, oldest first. */
export function weekBuckets(days, count = 52) {
  const out = bucketize(days, count, (t) => weekStart(dayKey(t)), (todayKey) => weekStart(todayKey), (k, n) => addDays(k, n * 7));
  for (const b of out) { b.to = addDays(b.key, 6); b.label = shortRange(b.key, b.to); }
  return out;
}

/** Last `count` calendar months, keyed 'YYYY-MM'. */
export function monthBuckets(days, count = 24) {
  const keyOf = (t) => monthKey(dayKey(t));
  const startOf = (todayKey) => monthKey(todayKey);
  const stepOf = (k, n) => {
    const [y, m] = k.split('-').map(Number);
    const d = new Date(y, m - 1 + n, 1);
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0');
  };
  const out = bucketize(days, count, keyOf, startOf, stepOf);
  for (const b of out) b.label = monthName(b.key);
  return out;
}

/** Last `count` calendar years, keyed 'YYYY'. */
export function yearBuckets(days, count = 6) {
  const keyOf = (t) => yearKey(dayKey(t));
  const out = bucketize(days, count, keyOf, (todayKey) => yearKey(todayKey), (k, n) => String(Number(k) + n));
  for (const b of out) b.label = b.key;
  return out;
}

function monthName(key) {
  const [y, m] = key.split('-').map(Number);
  const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return names[(m || 1) - 1] + (m === 1 ? ' ' + y : '');
}

function shortRange(a, b) {
  const pa = a.split('-'), pb = b.split('-');
  return Number(pa[1]) + '/' + Number(pa[2]) + '–' + Number(pb[1]) + '/' + Number(pb[2]);
}

/* ── sets-level series ─────────────────────────────────────────── */

/** Best single set per week — the number the 100-in-a-row plan actually tracks. */
export function bestSetPerWeek(sets, count = 52) {
  const weeks = weekBuckets(byDay(sets), count);
  for (const w of weeks) w.best = 0;
  const index = new Map(weeks.map((w, i) => [w.key, i]));
  for (const s of sets || []) {
    const k = index.get(weekStart(s.day || dayKey(s.startedAt)));
    if (k === undefined) continue;
    weeks[k].best = Math.max(weeks[k].best, Number(s.repsFinal) || 0);
  }
  return weeks;
}

/** Reps by hour of day, four buckets, as shares of total volume. */
export function timeOfDay(sets) {
  const buckets = [
    { key: 'night', label: '00–05', reps: 0, sets: 0 },
    { key: 'morning', label: '05–12', reps: 0, sets: 0 },
    { key: 'afternoon', label: '12–17', reps: 0, sets: 0 },
    { key: 'evening', label: '17–24', reps: 0, sets: 0 },
  ];
  for (const s of sets || []) {
    const h = new Date(s.startedAt || 0).getHours();
    const i = h < 5 ? 0 : h < 12 ? 1 : h < 17 ? 2 : 3;
    buckets[i].reps += Number(s.repsFinal) || 0;
    buckets[i].sets += 1;
  }
  const total = sum(buckets.map((b) => b.reps));
  for (const b of buckets) b.pct = total ? b.reps / total : 0;
  return buckets;
}

/* ── records ───────────────────────────────────────────────────── */

export function records(sets) {
  const list = (sets || []).filter((s) => (Number(s.repsFinal) || 0) > 0);
  const out = {
    bestSet: null, longestSet: null, bestDay: null, bestWeek: null, bestMonth: null, bestYear: null,
    lifetimeReps: 0, lifetimeSets: list.length, lifetimeMinutes: 0,
  };
  for (const s of list) {
    const reps = Number(s.repsFinal) || 0;
    if (!out.bestSet || reps > out.bestSet.reps) out.bestSet = { reps, at: s.startedAt, id: s.id, day: s.day };
    const dur = Number(s.durationMs) || 0;
    if (!out.longestSet || dur > out.longestSet.durationMs) out.longestSet = { durationMs: dur, reps, at: s.startedAt, id: s.id, day: s.day };
    out.lifetimeReps += reps;
    out.lifetimeMinutes += dur / 60000;
  }
  out.lifetimeMinutes = Math.round(out.lifetimeMinutes);
  const days = byDay(list);
  for (const d of days.values()) if (!out.bestDay || d.reps > out.bestDay.reps) out.bestDay = { day: d.day, reps: d.reps };
  const pick = (buckets) => {
    let best = null;
    for (const b of buckets) if (b.reps > 0 && (!best || b.reps > best.reps)) best = { key: b.key, reps: b.reps };
    return best;
  };
  out.bestWeek = pick(weekBuckets(days, 400));
  out.bestMonth = pick(monthBuckets(days, 120));
  out.bestYear = pick(yearBuckets(days, 40));
  return out;
}

/* ── estimates ─────────────────────────────────────────────────── */

/**
 * Estimated one-set max. A single all-out set is limited by the threshold you were counting
 * against, not by failure, so the best recent set is a floor rather than the answer. We take the
 * best set in the last `windowDays` and add a documented allowance: +12% of the set, never more
 * than +10 reps, and nothing added when the best set is older than the window.
 */
export function estimatedMax(sets, windowDays = 28, todayKey) {
  const from = addDays(todayKey || dayKey(Date.now()), -windowDays);
  let best = 0, bestAt = 0;
  for (const s of sets || []) {
    const day = s.day || dayKey(s.startedAt);
    if (day < from || day > (todayKey || dayKey(Date.now()))) continue;
    const reps = Number(s.repsFinal) || 0;
    if (reps > best) { best = reps; bestAt = s.startedAt || 0; }
  }
  if (!best) return { est: 0, basis: 0, windowDays, at: bestAt };
  return { est: best + Math.min(10, Math.round(best * 0.12)), basis: best, windowDays, at: bestAt };
}

/** Least-squares fit of weekly best-set values; projects the date a target is likely reached. */
export function projectTarget(sets, target, weeks = 12) {
  const series = bestSetPerWeek(sets, weeks).filter((w) => w.best > 0);
  if (series.length < 4) return { slope: 0, weeksTo: null, date: null, enough: false, points: series.length };
  const n = series.length;
  const xs = series.map((_, i) => i);
  const ys = series.map((w) => w.best);
  const mx = mean(xs), my = mean(ys);
  let num = 0, den = 0;
  for (let i = 0; i < n; i++) { num += (xs[i] - mx) * (ys[i] - my); den += (xs[i] - mx) ** 2; }
  const slope = den ? num / den : 0;
  const intercept = my - slope * mx;
  const now = ys[n - 1];
  if (now >= target) return { slope, weeksTo: 0, date: dayKey(Date.now()), enough: true, points: n, current: now };
  if (slope <= 0.05) return { slope, weeksTo: null, date: null, enough: true, current: now, points: n };
  const weeksTo = Math.ceil((target - intercept) / slope - (n - 1));
  if (weeksTo < 1 || weeksTo > 260) return { slope, weeksTo: null, date: null, enough: true, current: now, points: n };
  return { slope, weeksTo, date: addDays(weekStart(dayKey(Date.now())), weeksTo * 7), enough: true, current: now, points: n };
}

/* ── form quality over time ────────────────────────────────────── */

/**
 * Tempo and depth consistency from the per-rep rows of one set: coefficient of variation of rep
 * duration (tempo) and of minimum elbow angle (depth). Lower cv = more consistent. Returns nulls
 * when the set has fewer than three reps, because a cv of two numbers is not a signal.
 */
export function setConsistency(reps) {
  const list = (reps || []).filter((r) => r && Number.isFinite(r.durationMs));
  if (list.length < 3) return { reps: list.length, tempoCv: null, depthCv: null, medianMs: null, minElbow: null };
  const durs = list.map((r) => r.durationMs);
  const angles = list.map((r) => r.minElbow).filter((v) => Number.isFinite(v));
  const cv = (arr) => {
    const m = mean(arr);
    if (!m) return null;
    const sd = Math.sqrt(mean(arr.map((v) => (v - m) ** 2)));
    return sd / m;
  };
  const sorted = durs.slice().sort((a, b) => a - b);
  return {
    reps: list.length,
    tempoCv: cv(durs),
    depthCv: angles.length >= 3 ? cv(angles) : null,
    medianMs: sorted[Math.floor(sorted.length / 2)],
    minElbow: angles.length ? Math.min(...angles) : null,
  };
}

/**
 * Aggregate consistency across the most recent `count` sets, returned oldest→newest for charting.
 * Sorted defensively: listSets() hands back newest-first, and slice(-count) on that array would
 * otherwise read the oldest sets in the database.
 */
export function consistencySeries(sets, repsBySet, count = 30) {
  const ordered = (sets || []).slice().sort((a, b) => (a.startedAt || 0) - (b.startedAt || 0));
  const out = [];
  for (const s of ordered.slice(-count)) {
    const c = setConsistency(repsBySet[s.id] || []);
    if (c.tempoCv === null && c.depthCv === null) continue;
    out.push({ id: s.id, day: s.day, at: s.startedAt, reps: c.reps, tempoCv: c.tempoCv, depthCv: c.depthCv, medianMs: c.medianMs });
  }
  return out;
}

/** Flag mix across a window, for the "what is the camera catching" row. */
export function flagMix(sets, windowDays = 30, todayKey) {
  const from = addDays(todayKey || dayKey(Date.now()), -windowDays);
  const t = { sag: 0, pike: 0, half: 0, lockout: 0, lost: 0, reps: 0, sets: 0 };
  for (const s of sets || []) {
    const day = s.day || dayKey(s.startedAt);
    if (day < from) continue;
    const f = s.flags || {};
    t.sets += 1;
    t.reps += Number(s.repsFinal) || 0;
    for (const k of ['sag', 'pike', 'half', 'lockout', 'lost']) t[k] += Number(f[k]) || 0;
  }
  return t;
}

/* ── heatmap ───────────────────────────────────────────────────── */

/**
 * Calendar heatmap cells for the last `weeks` weeks, column-major; index 0..6 inside a column is
 * Monday..Sunday. `level` is 0 none, 1 some, 2 half the goal, 3 goal met, 4 fifty over.
 */
export function heatmap(days, weeks = 26, goal = 50, endKey) {
  const end = endKey || dayKey(Date.now());
  const endMonday = weekStart(end);
  const cols = [];
  for (let i = weeks - 1; i >= 0; i--) {
    const monday = addDays(endMonday, -7 * i);
    const col = [];
    for (let d = 0; d < 7; d++) {
      const key = addDays(monday, d);
      const rec = days.get(key);
      const reps = rec ? rec.reps : 0;
      col.push({
        day: key, reps, sets: rec ? rec.sets : 0,
        level: reps === 0 || goal <= 0 ? (reps > 0 ? 1 : 0)
          : reps >= goal * 1.5 ? 4 : reps >= goal ? 3 : reps >= goal * 0.5 ? 2 : 1,
        future: key > end,
      });
    }
    cols.push({ week: monday, cells: col });
  }
  return cols;
}

/** Missing days with at least one set on either side — what "add a missed day" offers. */
export function gaps(days, windowDays = 90) {
  const keys = [...days.keys()].filter((k) => days.get(k).reps > 0).sort();
  if (keys.length < 2) return [];
  const out = [];
  const from = addDays(keys[keys.length - 1], -windowDays);
  for (let i = 1; i < keys.length; i++) {
    for (let d = 1; d < daysBetween(keys[i - 1], keys[i]); d++) {
      const key = addDays(keys[i - 1], d);
      if (key >= from) out.push(key);
    }
  }
  return out.slice(-31);
}

/** Everything the Today screen needs, in one pass over the sets. */
export function summarize(sets, opts = {}) {
  const goal = opts.dailyGoal || 0;
  const days = byDay(sets);
  const todayKey = opts.todayKey || dayKey(Date.now());
  const rec = days.get(todayKey) || emptyDay(todayKey);
  return {
    todayKey,
    today: rec,
    goal,
    goalPct: goal ? Math.min(1, rec.reps / goal) : 0,
    goalLeft: Math.max(0, goal - rec.reps),
    week: weekBuckets(days, 1).pop() || emptyDay(todayKey),
    month: monthBuckets(days, 1).pop() || emptyDay(todayKey),
    year: yearBuckets(days, 1).pop() || emptyDay(todayKey),
    lifetime: records(sets).lifetimeReps,
    streak: trainingStreak(days, todayKey),
    days30: dayBuckets(days, 30),
    setsToday: rec.sets,
  };
}
