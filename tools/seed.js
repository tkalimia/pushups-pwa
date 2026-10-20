/* Dev-only fixture writer. Seeds a plausible training history so the Today and Progress screens can
   be screenshot without doing pushups. Never imported by the app; excluded from the service worker.
   From the console:   import('/tools/seed.js').then(m => m.seed())        // 90 days
                      import('/tools/seed.js').then(m => m.seed(14))       // 14 days
                      import('/tools/seed.js').then(m => m.clear())        // remove the fixtures */

const TAG = 'seed';

function dayKey(ms) {
  const d = new Date(ms);
  return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
}

function mulberry(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export async function seed(days = 90, seedValue = 7) {
  const db = await import('../js/db.js');
  const rnd = mulberry(seedValue);
  const now = new Date();
  let added = 0;
  for (let back = days - 1; back >= 0; back--) {
    const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - back, 7, 0, 0, 0);
    const key = dayKey(d.getTime());
    const weekday = d.getDay();
    if (weekday === 6) continue;                       // Saturday off
    if (back > 40 && rnd() < 0.25) continue;           // patchier history further back
    const fitness = 18 + (days - back) * 0.22;         // slow upward trend
    const sets = 1 + Math.floor(rnd() * 2);
    for (let s = 0; s < sets; s++) {
      const reps = Math.max(3, Math.round(fitness * (0.7 + rnd() * 0.6)));
      const startedAt = d.getTime() + s * 900000 + Math.floor(rnd() * 300000);
      const flagged = rnd() < 0.25 ? 1 + Math.floor(rnd() * 2) : 0;
      const id = await db.saveSet({
        startedAt, endedAt: startedAt + reps * 3200, durationMs: reps * 3200,
        mode: 'camera', source: 'camera', repsDetected: reps + flagged, repsFinal: reps,
        flags: { sag: flagged, pike: 0, half: flagged, lockout: 0, lost: 0 },
        cameraUsed: 'environment', qualityStats: { fpsMean: 22, visMean: 0.82, frames: 400, breaks: 0 },
        paramsUsed: { top: 155, bottom: 100, minRepMs: 400 }, presetName: 'standard', model: 'lite',
        notes: '', day: key, [TAG]: true,
      }, makeReps(reps + flagged, rnd));
      added += 1;
      void id;
    }
  }
  return { added, days };
}

function makeReps(n, rnd) {
  const out = [];
  for (let i = 0; i < n; i++) {
    out.push({
      tMs: i * (2600 + Math.floor(rnd() * 500)),
      durationMs: 2200 + Math.floor(rnd() * 900),
      minElbow: 88 + Math.floor(rnd() * 22),
      maxElbow: 158 + Math.floor(rnd() * 14),
      shoulderDrop: 0.12 + rnd() * 0.1,
      hipOffset: (rnd() - 0.45) * 0.2,
      side: rnd() < 0.5 ? 'left' : 'right',
      flags: [],
      n: i + 1,
    });
  }
  return out;
}

export async function clear() {
  const db = await import('../js/db.js');
  const all = await db.listSets();
  let n = 0;
  for (const s of all) {
    if (s && s[TAG]) { await db.deleteSet(s.id); n += 1; }
  }
  return { removed: n, left: (await db.listSets()).length };
}
