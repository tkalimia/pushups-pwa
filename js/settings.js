export const PRESETS = {
  relaxed:  { top: 140, bottom: 112, minRepMs: 300 },
  standard: { top: 155, bottom: 100, minRepMs: 400 },
  strict:   { top: 168, bottom: 88,  minRepMs: 450 },
};

export const DEFAULTS = {
  preset: 'standard', overrides: {}, cleanOnly: false, autoArm: false, armHoldMs: 2500,
  endAfterIdleSec: 12, camera: 'environment', voice: 'every', beeps: true, haptics: true,
  skeletonOnSet: true, secondarySignal: 'assist', model: 'lite', fpsCap: 25, manualMode: false, debug: false,
};

const STORAGE_KEY = 'pushups.settings.v1';

let cached = null;

function readStored() {
  try {
    const raw = globalThis.localStorage?.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return null;
    return parsed;
  } catch {
    return null;
  }
}

function normalize(settings) {
  const out = { ...settings };
  if (!PRESETS[out.preset]) out.preset = DEFAULTS.preset;
  if (!out.overrides || typeof out.overrides !== 'object' || Array.isArray(out.overrides)) {
    out.overrides = {};
  }
  return out;
}

export function load() {
  if (cached) return cached;
  const stored = readStored();
  cached = normalize(stored ? { ...DEFAULTS, ...stored } : { ...DEFAULTS });
  return cached;
}

export function save(patch) {
  const base = load();
  const next = normalize({ ...base, ...(patch || {}) });
  cached = next;
  try {
    globalThis.localStorage?.setItem(STORAGE_KEY, JSON.stringify(next));
  } catch {
    // storage unavailable (private mode, quota) — keep the in-memory copy
  }
  return next;
}

export function params() {
  const s = load();
  const preset = PRESETS[s.preset] || PRESETS.standard;
  const overrides = {};
  for (const [k, v] of Object.entries(s.overrides || {})) {
    if (typeof v === 'number' && Number.isFinite(v)) overrides[k] = v;
  }
  return { ...preset, ...overrides };
}

export function setParam(k, v) {
  const s = load();
  const overrides = { ...s.overrides };
  if (v === null || v === undefined || (typeof v === 'number' && !Number.isFinite(v))) {
    delete overrides[k];
  } else {
    overrides[k] = v;
  }
  return save({ ...s, overrides });
}

export function resetParams() {
  return save({ ...load(), overrides: {} });
}

export function clearOverridesForPreset() {
  return resetParams();
}
