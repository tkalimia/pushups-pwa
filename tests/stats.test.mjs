/* Node test for the aggregation layer. No DOM, no IndexedDB — stats.js is pure.
   Run: node tests/stats.test.mjs */

import assert from 'node:assert/strict';
import {
  addDays, bestSetPerWeek, byDay, consistencySeries, dayBuckets, dayKey, dailyGoalStreak,
  estimatedMax, flagMix, gaps, heatmap, monthBuckets, projectTarget, records, setConsistency,
  summarize, timeOfDay, trainingStreak, weekBuckets, weekStart, weeklyGoalStreak, yearBuckets,
} from '../js/stats.js';

let pass = 0, fail = 0;
function check(name, fn) {
  try { fn(); pass += 1; console.log('PASS  ' + name); }
  catch (err) { fail += 1; console.log('FAIL  ' + name + '\n      ' + (err.message || err)); }
}

const TODAY = dayKey(Date.now());
const MONDAY = weekStart(TODAY);

/** Place a set on an absolute day key so week-aligned fixtures stay week-aligned. */
function setOn(key, reps, opts = {}) {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  const ago = Math.round((d.getTime() - new Date(key + 'T12:00:00').getTime()) / 86400000);
  return set(ago, reps, opts);
}

/** Set builder: `ago` = whole days back from today, hour = local hour of day. */
function set(ago, reps, opts = {}) {
  const d = new Date();
  d.setDate(d.getDate() - ago);
  d.setHours(opts.hour ?? 8, opts.minute ?? 0, 0, 0);
  return {
    id: opts.id ?? 1000 + ago * 10, startedAt: d.getTime(), endedAt: d.getTime() + (opts.durationMs || reps * 3000),
    durationMs: opts.durationMs || reps * 3000, mode: opts.mode || 'camera', source: opts.source || 'camera',
    repsDetected: opts.detected ?? reps, repsFinal: reps, flags: opts.flags || {},
    day: dayKey(d.getTime()),
  };
}

/* ── calendar helpers ─────────────────────────────────────────── */

check('weekStart lands on Monday and is stable across the week', () => {
  assert.equal(weekStart(TODAY), MONDAY);
  assert.equal(weekStart(addDays(MONDAY, 6)), MONDAY);
});

check('addDays crosses month boundaries', () => {
  assert.equal(addDays('2026-01-31', 1), '2026-02-01');
  assert.equal(addDays('2026-03-01', -1), '2026-02-28');
  assert.equal(addDays('2028-02-28', 1), '2028-02-29');   // leap year
});

/* ── per-day totals ───────────────────────────────────────────── */

const twoSets = [set(0, 12, { id: 1, hour: 7 }), set(0, 8, { id: 2, hour: 19, flags: { half: 2 } })];

check('byDay adds reps and counts sets on the same day', () => {
  const d = byDay(twoSets).get(TODAY);
  assert.equal(d.reps, 20);
  assert.equal(d.sets, 2);
  assert.equal(d.best, 12);
  assert.equal(d.flagged, 2);
  assert.equal(d.clean, 18);
  assert.equal(d.detected, 20);
});

check('empty input yields no days and no crash', () => {
  assert.equal(byDay([]).size, 0);
  assert.equal(byDay(undefined).size, 0);
  const s = summarize([], { dailyGoal: 50 });
  assert.equal(s.today.reps, 0);
  assert.equal(s.goalPct, 0);
  assert.equal(s.streak, 0);
});

check('a set with repsFinal 0 still counts as a set but adds no reps', () => {
  const d = byDay([set(1, 0, { id: 5 })]).get(addDays(TODAY, -1));
  assert.equal(d.reps, 0);
  assert.equal(d.sets, 1);
});

/* ── streaks ──────────────────────────────────────────────────── */

check('trainingStreak counts consecutive training days back from today', () => {
  const days = byDay([set(0, 10), set(1, 10), set(2, 10, { id: 9 })]);
  assert.equal(trainingStreak(days, TODAY), 3);
});

check('trainingStreak skips nothing: a missed day ends it', () => {
  const days = byDay([set(0, 10), set(2, 10, { id: 9 }), set(3, 10, { id: 8 })]);
  assert.equal(trainingStreak(days, TODAY), 1);
});

check('today-not-yet-trained does not kill yesterday’s streak', () => {
  const days = byDay([set(1, 10, { id: 9 }), set(2, 10, { id: 8 })]);
  assert.equal(trainingStreak(days, TODAY), 2);
});

check('weeklyGoalStreak counts completed weeks, current week only if already met', () => {
  // three finished weeks at 400 reps each, current week untouched
  const sets = [];
  for (let w = 1; w <= 3; w++) {
    for (let d = 0; d < 5; d++) sets.push(setOn(addDays(weekStart(TODAY), -7 * w + d), 80, { id: w * 100 + d }));
  }
  assert.equal(weeklyGoalStreak(byDay(sets), 350, TODAY), 3);
  // meeting it in the current week extends the streak to 4
  sets.push(setOn(TODAY, 400, { id: 999 }));
  assert.equal(weeklyGoalStreak(byDay(sets), 350, TODAY), 4);
});

check('weeklyGoalStreak breaks on a short week', () => {
  const sets = [];
  for (let d = 0; d < 5; d++) sets.push(setOn(addDays(weekStart(TODAY), -14 + d), 80, { id: 200 + d }));
  for (let d = 0; d < 5; d++) sets.push(setOn(addDays(weekStart(TODAY), -7 + d), 20, { id: 300 + d }));
  assert.equal(weeklyGoalStreak(byDay(sets), 350, TODAY), 0);
});

check('dailyGoalStreak needs the daily goal, not just any training', () => {
  const days = byDay([set(0, 60), set(1, 5, { id: 7 }), set(2, 60, { id: 8 })]);
  assert.equal(dailyGoalStreak(days, 50, TODAY, new Set()), 1);
});

check('a rest pass bridges a day below goal', () => {
  const days = byDay([set(0, 60), set(1, 5, { id: 7 }), set(2, 60, { id: 8 })]);
  assert.equal(dailyGoalStreak(days, 50, TODAY, new Set([addDays(TODAY, -1)])), 3);
});

/* ── buckets ──────────────────────────────────────────────────── */

check('dayBuckets returns the requested window, oldest first, ending today', () => {
  const b = dayBuckets(byDay([set(0, 10), set(5, 20, { id: 3 })]), 30);
  assert.equal(b.length, 30);
  assert.equal(b[b.length - 1].key, TODAY);
  assert.equal(b[b.length - 1].reps, 10);
  assert.equal(b[b.length - 6].reps, 20);
  assert.equal(b.reduce((n, x) => n + x.reps, 0), 30);
});

check('weekBuckets totals a week and reports training days', () => {
  const sets = [set(0, 10), set(1, 10, { id: 4 })];
  const w = weekBuckets(byDay(sets), 4).pop();
  assert.equal(w.reps, 20);
  assert.equal(w.days, 2);
  assert.equal(w.key, MONDAY);
});

check('monthBuckets and yearBuckets key correctly', () => {
  const days = byDay([set(0, 10)]);
  assert.equal(monthBuckets(days, 3).pop().key, TODAY.slice(0, 7));
  assert.equal(yearBuckets(days, 2).pop().key, TODAY.slice(0, 4));
});

check('buckets ignore activity outside the window', () => {
  const b = dayBuckets(byDay([set(200, 500, { id: 11 })]), 30);
  assert.equal(b.reduce((n, x) => n + x.reps, 0), 0);
});

/* ── sets-level series ────────────────────────────────────────── */

check('bestSetPerWeek reports the single biggest set of the week', () => {
  const weeks = bestSetPerWeek([set(0, 15), set(1, 40, { id: 12 }), set(0, 9, { id: 13 })], 4).pop();
  assert.equal(weeks.best, 40);
});

check('timeOfDay splits volume into four buckets that sum to 1', () => {
  const t = timeOfDay([set(0, 10, { hour: 6 }), set(0, 10, { id: 14, hour: 13 }), set(0, 20, { id: 15, hour: 22 })]);
  assert.equal(t[1].reps, 10);
  assert.equal(t[2].reps, 10);
  assert.equal(t[3].reps, 20);
  assert.ok(Math.abs(t.reduce((n, b) => n + b.pct, 0) - 1) < 1e-9);
});

/* ── records ──────────────────────────────────────────────────── */

const recordSets = [
  set(0, 25, { id: 21, hour: 7 }),
  set(1, 30, { id: 22, durationMs: 90000 }),
  set(40, 12, { id: 23 }),
  set(400, 18, { id: 24 }),
];

check('records finds best set, longest set and lifetime totals', () => {
  const r = records(recordSets);
  assert.equal(r.bestSet.reps, 30);
  assert.equal(r.longestSet.durationMs, 90000);
  assert.equal(r.lifetimeReps, 85);
  assert.equal(r.lifetimeSets, 4);
  assert.equal(r.bestDay.reps, 30);
});

check('records on empty data returns zeros, not undefined', () => {
  const r = records([]);
  assert.equal(r.lifetimeReps, 0);
  assert.equal(r.bestSet, null);
  assert.equal(r.bestWeek, null);
});

/* ── estimates ────────────────────────────────────────────────── */

check('estimatedMax adds an allowance to a recent best set', () => {
  const e = estimatedMax([set(2, 40, { id: 31 })], 28, TODAY);
  assert.equal(e.basis, 40);
  assert.equal(e.est, 45);            // 40 + min(10, round(4.8)) = 45
});

check('estimatedMax ignores a best set outside the window', () => {
  const e = estimatedMax([set(60, 90, { id: 32 }), set(1, 20, { id: 33 })], 28, TODAY);
  assert.equal(e.basis, 20);
});

check('estimatedMax caps the allowance at ten reps', () => {
  assert.equal(estimatedMax([set(0, 200, { id: 34 })], 28, TODAY).est, 210);
});

check('estimatedMax with no data is zero', () => {
  assert.equal(estimatedMax([], 28, TODAY).est, 0);
});

check('projectTarget needs four data points before it guesses a date', () => {
  const sets = [];
  for (let w = 0; w < 3; w++) sets.push(set(w * 7 + 1, 20 + w * 5, { id: 40 + w }));
  assert.equal(projectTarget(sets, 100).enough, false);
});

check('projectTarget on a rising series gives a future date', () => {
  const sets = [];
  // w counts weeks back from now, so the newest week (w=0) has the most reps
  for (let w = 0; w < 8; w++) sets.push(set(w * 7 + 1, 60 - w * 5, { id: 50 + w }));
  const p = projectTarget(sets, 100);
  assert.equal(p.enough, true);
  assert.ok(p.slope > 0, 'slope should be positive, got ' + p.slope);
  assert.ok(p.weeksTo >= 1 && p.weeksTo <= 260, 'weeksTo=' + p.weeksTo);
  assert.ok(p.date > TODAY, 'projection must be in the future: ' + p.date);
});

check('projectTarget refuses to project on a flat or falling series', () => {
  const sets = [];
  for (let w = 0; w < 8; w++) sets.push(set(w * 7 + 1, 30, { id: 60 + w }));
  const p = projectTarget(sets, 100);
  assert.equal(p.weeksTo, null);
  assert.equal(p.date, null);
});

check('projectTarget says reached when already above the target', () => {
  const sets = [];
  for (let w = 0; w < 6; w++) sets.push(set(w * 7 + 1, 110, { id: 70 + w }));
  assert.equal(projectTarget(sets, 100).weeksTo, 0);
});

/* ── form consistency ─────────────────────────────────────────── */

check('setConsistency needs three reps to report anything', () => {
  const c = setConsistency([{ durationMs: 1000, minElbow: 95 }, { durationMs: 1400, minElbow: 100 }]);
  assert.equal(c.tempoCv, null);
  assert.equal(c.depthCv, null);
});

check('setConsistency measures tempo spread and median', () => {
  const reps = [900, 1000, 1100, 1000].map((d, i) => ({ durationMs: d, minElbow: 90 + i }));
  const c = setConsistency(reps);
  assert.equal(c.reps, 4);
  assert.equal(c.medianMs, 1000);
  assert.ok(c.tempoCv > 0.05 && c.tempoCv < 0.12, 'tempoCv=' + c.tempoCv);
  assert.ok(c.depthCv < 0.05, 'depthCv=' + c.depthCv);
});

check('identical reps give zero variation', () => {
  const c = setConsistency([1, 2, 3].map(() => ({ durationMs: 1000, minElbow: 95 })));
  assert.equal(c.tempoCv, 0);
  assert.equal(c.depthCv, 0);
});

check('consistencySeries skips sets without per-rep rows', () => {
  const sets = [set(0, 10, { id: 81 }), set(1, 10, { id: 82 })];
  const byId = { 81: [{ durationMs: 900, minElbow: 95 }, { durationMs: 1000, minElbow: 96 }, { durationMs: 950, minElbow: 94 }] };
  const s = consistencySeries(sets, byId);
  assert.equal(s.length, 1);
});

check('consistencySeries takes the NEWEST sets even when listSets() is newest-first', () => {
  // three sets; only the two newest carry per-rep rows. A slice(-count) on a newest-first array
  // would silently chart the oldest sets in the database instead.
  const old = set(30, 10, { id: 801 });
  const mid = set(2, 10, { id: 802 });
  const recent = set(0, 10, { id: 803 });
  const reps = (id) => [{ durationMs: 900, minElbow: 95 }, { durationMs: 1000, minElbow: 96 }, { durationMs: 950, minElbow: 94 }].map((r) => ({ ...r }));
  const byId = { [mid.id]: reps(), [recent.id]: reps() };
  const desc = consistencySeries([recent, mid, old], byId, 2);
  const asc = consistencySeries([old, mid, recent], byId, 2);
  assert.equal(desc.length, 2);
  assert.deepEqual(desc.map((d) => d.id), asc.map((d) => d.id));
  assert.deepEqual(desc.map((d) => d.id).sort(), [802, 803]);
});

check('flagMix adds flags over the window', () => {
  const f = flagMix([set(1, 20, { id: 90, flags: { sag: 3, half: 1 } }), set(0, 10, { id: 91, flags: { pike: 2 } })], 7, TODAY);
  assert.deepEqual({ sag: f.sag, pike: f.pike, half: f.half }, { sag: 3, pike: 2, half: 1 });
  assert.equal(f.reps, 30);
  assert.equal(f.sets, 2);
});

/* ── heatmap and gaps ─────────────────────────────────────────── */

check('heatmap returns 7 rows per week column, ending this week', () => {
  const cols = heatmap(byDay([set(0, 60)]), 10, 50, TODAY);
  assert.equal(cols.length, 10);
  assert.equal(cols[0].cells.length, 7);
  assert.equal(cols[9].cells.filter((c) => c.future).length >= 0, true);
  assert.equal(cols[9].cells.find((c) => c.day === TODAY).reps, 60);
});

check('heatmap levels step with the goal', () => {
  const levelFor = (reps) => heatmap(byDay([set(0, reps, { id: 95 })]), 4, 50, TODAY)
    .flatMap((c) => c.cells).find((c) => c.day === TODAY).level;
  assert.equal(levelFor(10), 1);        // some work, under half the goal
  assert.equal(levelFor(25), 2);        // half
  assert.equal(levelFor(50), 3);        // goal met
  assert.equal(levelFor(75), 4);        // 1.5x
  assert.equal(levelFor(200), 4);
  assert.equal(heatmap(byDay([]), 4, 50, TODAY).flatMap((c) => c.cells).find((c) => c.day === TODAY).level, 0);
});

check('gaps lists the empty days between two training days', () => {
  const g = gaps(byDay([set(0, 10), set(4, 10, { id: 97 })]), 30);
  assert.equal(g.length, 3);
  assert.equal(g[0], addDays(TODAY, -3));
});

check('gaps needs two anchors before it claims anything is missing', () => {
  assert.deepEqual(gaps(byDay([set(0, 10)]), 30), []);
});

/* ── summarize ────────────────────────────────────────────────── */

check('summarize reports today, week, month, year and streak together', () => {
  const sets = [set(0, 30), set(0, 20, { id: 101 }), set(8, 40, { id: 102 })];
  const s = summarize(sets, { dailyGoal: 50 });
  assert.equal(s.today.reps, 50);
  assert.equal(s.goalPct, 1);
  assert.equal(s.goalLeft, 0);
  assert.equal(s.week.reps + s.month.reps >= 50, true);
  assert.equal(s.lifetime, 90);
  assert.equal(s.setsToday, 2);
  assert.equal(s.streak, 1);
});

check('summarize with no goal does not divide by zero', () => {
  const s = summarize([set(0, 10)], { dailyGoal: 0 });
  assert.equal(s.goalPct, 0);
  assert.equal(s.goalLeft, 0);
});

console.log('\n' + (fail ? fail + ' FAILED' : 'ALL CHECKS PASSED') + ' — ' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
