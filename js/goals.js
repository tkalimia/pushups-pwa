/* Goals, streak mode and rest-day passes. Config lives in IndexedDB meta (not localStorage) so a
   JSON export carries the targets you trained against, and a restore on another phone brings the
   streak rules with it. */

import { getMeta, setMeta } from './db.js';
import { addDays, byDay, dailyGoalStreak, dayKey, weekStart, weeklyGoalStreak } from './stats.js';

export const GOAL_KEY = 'goals.v1';
export const STREAK_KEY = 'streak.v1';
export const PASS_KEY = 'passes.v1';

export const DEFAULT_GOALS = { daily: 50, weekly: 350, yearly: 10000 };
export const DEFAULT_STREAK = { mode: 'weekly', passesPerWeek: 1 };

const cache = new Map();

async function readKey(key, fallback) {
  if (cache.has(key)) return cache.get(key);
  let value = fallback;
  try {
    const raw = await getMeta(key);
    if (raw && typeof raw === 'object') value = { ...fallback, ...raw };
  } catch { /* cold or blocked db: fall back to defaults for this session only */ }
  cache.set(key, value);
  return value;
}

/** Drop the in-memory copy so the next read comes from the database (after a restore). */
export function forgetCache() {
  cache.clear();
}

async function writeKey(key, value) {
  cache.set(key, value);
  await setMeta(key, value);
  return value;
}

export async function loadGoals() { return readKey(GOAL_KEY, DEFAULT_GOALS); }

export async function saveGoals(patch) {
  const base = await loadGoals();
  const next = { ...base, ...(patch || {}) };
  for (const k of ['daily', 'weekly', 'yearly']) {
    const v = parseInt(next[k], 10);
    next[k] = Number.isFinite(v) && v >= 0 ? Math.min(100000, v) : DEFAULT_GOALS[k];
  }
  return writeKey(GOAL_KEY, next);
}

export async function loadStreak() {
  const base = await readKey(STREAK_KEY, DEFAULT_STREAK);
  if (base.mode !== 'daily' && base.mode !== 'weekly') base.mode = DEFAULT_STREAK.mode;
  base.passesPerWeek = Math.max(0, Math.min(3, parseInt(base.passesPerWeek, 10) || 0));
  return base;
}

export async function saveStreak(patch) {
  const base = await loadStreak();
  return writeKey(STREAK_KEY, { ...base, ...(patch || {}) });
}

/** Day keys that were covered by a rest pass. Only the last 12 weeks are kept. */
export async function loadPasses() {
  const raw = await readKey(PASS_KEY, {});
  return raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
}

export async function passesThisWeek(passes, fromKey) {
  const wk = weekStart(fromKey || dayKey(Date.now()));
  let n = 0;
  for (let i = 0; i < 7; i++) if (passes[addDays(wk, i)]) n += 1;
  return n;
}

/** Spend a rest pass on `day`. Returns { ok, reason } so the UI can say why it refused. */
export async function usePass(day) {
  const cfg = await loadStreak();
  const passes = await loadPasses();
  const key = day || dayKey(Date.now());
  if (passes[key]) return { ok: false, reason: 'already used', passes };
  if (cfg.passesPerWeek === 0) return { ok: false, reason: 'rest passes are off', passes };
  const used = await passesThisWeek(passes, key);
  if (used >= cfg.passesPerWeek) return { ok: false, reason: 'no passes left this week', passes };
  const next = { ...passes, [key]: true };
  const cutoff = addDays(dayKey(Date.now()), -84);
  for (const k of Object.keys(next)) if (k < cutoff) delete next[k];
  await writeKey(PASS_KEY, next);
  return { ok: true, passes: next };
}

export async function undoPass(day) {
  const passes = await loadPasses();
  if (!passes[day]) return { passes };
  const next = { ...passes };
  delete next[day];
  await writeKey(PASS_KEY, next);
  return { passes: next };
}

/** Everything the Today and Progress headers need, from one set list. */
export async function goalStatus(sets, todayKey) {
  const goals = await loadGoals();
  const cfg = await loadStreak();
  const passes = await loadPasses();
  const days = byDay(sets);
  const key = todayKey || dayKey(Date.now());
  const today = days.get(key);
  return {
    goals,
    streakCfg: cfg,
    passes,
    passesLeft: Math.max(0, cfg.passesPerWeek - await passesThisWeek(passes, key)),
    daily: { goal: goals.daily, reps: today ? today.reps : 0, pct: goals.daily ? Math.min(1, (today ? today.reps : 0) / goals.daily) : 0 },
    weekly: pctOf(days, goals.weekly, 'week', key),
    yearly: pctOf(days, goals.yearly, 'year', key),
    streak: cfg.mode === 'daily'
      ? { mode: 'daily', n: dailyGoalStreak(days, goals.daily, key, new Set(Object.keys(passes))), unit: 'days' }
      : { mode: 'weekly', n: weeklyGoalStreak(days, goals.weekly, key), unit: 'weeks' },
  };
}

function pctOf(days, goal, span, key) {
  const reps = span === 'week' ? weekToDate(days, key) : yearToDate(days, key);
  return { goal, reps, pct: goal ? Math.min(1, reps / goal) : 0, left: Math.max(0, goal - reps) };
}

function weekToDate(days, key) {
  const wk = weekStart(key);
  let n = 0;
  for (let i = 0; i < 7 && addDays(wk, i) <= key; i++) {
    const d = days.get(addDays(wk, i));
    if (d) n += d.reps;
  }
  return n;
}

function yearToDate(days, key) {
  const jan = key.slice(0, 4) + '-01-01';
  let n = 0;
  for (const [k, d] of days) if (k >= jan && k <= key) n += d.reps;
  return n;
}

/** For the reminder layer: has today's goal already been banked? */
export async function goalMetToday(sets, todayKey) {
  const goals = await loadGoals();
  const key = todayKey || dayKey(Date.now());
  const d = byDay(sets).get(key);
  return !!d && d.reps >= goals.daily;
}
