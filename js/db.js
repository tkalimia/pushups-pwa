/* schema
set  { id, startedAt (epoch ms), endedAt, durationMs, mode:'camera'|'manual', source:'camera'|'manual',
       repsDetected, repsFinal, flags:{ sag, pike, half, lockout, lost }, cameraUsed:'environment'|'user',
       qualityStats:{ fpsMean, visMean, frames }, paramsUsed:{...thresholds }, presetName, model, notes,
       day:'YYYY-MM-DD', schema:1 }
rep  { id, setId, tMs (relative to set start), durationMs, minElbow, maxElbow, shoulderDrop, hipOffset,
       side, flags:[], n }
meta { k, v }
DB pushups v1: stores 'sets' (keyPath id autoIncrement, indexes startedAt, day),
'reps' (keyPath id autoIncrement, index setId), 'meta' (keyPath k).
*/

const DB_NAME = 'pushups';
const DB_VERSION = 1;
const SCHEMA = 1;

let dbPromise = null;

function toPromise(req) {
  return new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error || new Error('IndexedDB request failed'));
  });
}

function finish(tx) {
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onabort = () => reject(tx.error || new Error('IndexedDB transaction aborted'));
    tx.onerror = () => reject(tx.error || new Error('IndexedDB transaction failed'));
  });
}

function idb() {
  if (typeof indexedDB === 'undefined' || indexedDB === null) {
    throw new Error('IndexedDB is not available in this browser/context');
  }
  return indexedDB;
}

export function open() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = idb().open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = (ev) => {
      const db = req.result;
      if (!db.objectStoreNames.contains('sets')) {
        const sets = db.createObjectStore('sets', { keyPath: 'id', autoIncrement: true });
        sets.createIndex('startedAt', 'startedAt');
        sets.createIndex('day', 'day');
      }
      if (!db.objectStoreNames.contains('reps')) {
        const reps = db.createObjectStore('reps', { keyPath: 'id', autoIncrement: true });
        reps.createIndex('setId', 'setId');
      }
      if (!db.objectStoreNames.contains('meta')) {
        db.createObjectStore('meta', { keyPath: 'k' });
      }
      void ev;
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error || new Error('could not open ' + DB_NAME));
    req.onblocked = () => reject(new Error('IndexedDB open blocked by another tab'));
  });
  return dbPromise;
}

export async function resetForTest() {
  if (dbPromise) {
    const db = await dbPromise.catch(() => null);
    if (db) db.close();
  }
  dbPromise = null;
  await new Promise((resolve, reject) => {
    const req = idb().deleteDatabase(DB_NAME);
    req.onsuccess = () => resolve();
    req.onerror = () => reject(req.error || new Error('deleteDatabase failed'));
    req.onblocked = () => resolve();
  });
  return open();
}

export function localDay(ms) {
  const d = new Date(ms === undefined || ms === null ? Date.now() : ms);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function normalizeSet(set) {
  const rec = { ...(set || {}) };
  delete rec.id;
  if (typeof rec.startedAt !== 'number') rec.startedAt = Date.now();
  if (!rec.day) rec.day = localDay(rec.startedAt);
  rec.schema = SCHEMA;
  return rec;
}

function normalizeRep(rep, setId) {
  const rec = { ...(rep || {}) };
  delete rec.id;
  rec.setId = setId;
  return rec;
}

export async function saveSet(set, repsArray) {
  const db = await open();
  const rec = normalizeSet(set);
  const reps = Array.isArray(repsArray) ? repsArray : [];
  let id = null;
  const tx = db.transaction(['sets', 'reps'], 'readwrite');
  id = await toPromise(tx.objectStore('sets').add(rec));
  for (const rep of reps) {
    tx.objectStore('reps').add(normalizeRep(rep, id));
  }
  await finish(tx);
  return id;
}

export async function getSet(id) {
  const db = await open();
  const tx = db.transaction('sets', 'readonly');
  const rec = await toPromise(tx.objectStore('sets').get(id));
  await finish(tx);
  return rec || null;
}

export async function listReps(setId) {
  const db = await open();
  const tx = db.transaction('reps', 'readonly');
  const reps = await toPromise(tx.objectStore('reps').index('setId').getAll(setId));
  await finish(tx);
  return (reps || []).sort((a, b) => (a.tMs || 0) - (b.tMs || 0));
}

function collectAll(storeName, indexer) {
  return open().then((db) => {
    const tx = db.transaction(storeName, 'readonly');
    const src = indexer ? indexer(tx.objectStore(storeName)) : tx.objectStore(storeName);
    return toPromise(src.getAll()).then((rows) => finish(tx).then(() => rows || []));
  });
}

export async function listSets() {
  const rows = await collectAll('sets');
  return rows.sort((a, b) => (b.startedAt || 0) - (a.startedAt || 0));
}

export async function listSetsForDay(day) {
  const db = await open();
  const tx = db.transaction('sets', 'readonly');
  const rows = await toPromise(tx.objectStore('sets').index('day').getAll(day));
  await finish(tx);
  return (rows || []).sort((a, b) => (b.startedAt || 0) - (a.startedAt || 0));
}

export async function updateSet(id, patch) {
  const db = await open();
  const tx = db.transaction('sets', 'readwrite');
  const store = tx.objectStore('sets');
  const current = await toPromise(store.get(id));
  if (!current) {
    await finish(tx).catch(() => {});
    return null;
  }
  const next = { ...current, ...(patch || {}), id: current.id };
  await toPromise(store.put(next));
  await finish(tx);
  return next;
}

export async function deleteSet(id) {
  const db = await open();
  const tx = db.transaction(['sets', 'reps'], 'readwrite');
  tx.objectStore('sets').delete(id);
  const keys = await toPromise(tx.objectStore('reps').index('setId').getAllKeys(id));
  for (const k of keys || []) tx.objectStore('reps').delete(k);
  await finish(tx);
  return true;
}

export async function countSets() {
  const db = await open();
  const tx = db.transaction('sets', 'readonly');
  const n = await toPromise(tx.objectStore('sets').count());
  await finish(tx);
  return n || 0;
}

export async function getMeta(k) {
  const db = await open();
  const tx = db.transaction('meta', 'readonly');
  const rec = await toPromise(tx.objectStore('meta').get(k));
  await finish(tx);
  return rec && 'v' in rec ? rec.v : undefined;
}

export async function setMeta(k, v) {
  const db = await open();
  const tx = db.transaction('meta', 'readwrite');
  await toPromise(tx.objectStore('meta').put({ k, v }));
  await finish(tx);
  return v;
}

export async function exportJSON() {
  const [sets, reps] = await Promise.all([collectAll('sets'), collectAll('reps')]);
  return JSON.stringify({
    app: 'pushups',
    schema: SCHEMA,
    exportedAt: Date.now(),
    sets: sets || [],
    reps: reps || [],
  });
}

function isIdKey(key) {
  return typeof key === 'number' || typeof key === 'string';
}

async function idIsFree(store, id) {
  if (!isIdKey(id)) return false;
  const existing = await toPromise(store.get(id));
  return !existing;
}

export async function importJSON(text) {
  let payload;
  try {
    payload = typeof text === 'string' ? JSON.parse(text) : text;
  } catch (e) {
    return { ok: false, added: 0, error: 'Not valid JSON: ' + (e && e.message ? e.message : String(e)) };
  }
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    return { ok: false, added: 0, error: 'Backup file is not an object' };
  }
  if (payload.app !== 'pushups') {
    return { ok: false, added: 0, error: 'This backup is not from Pushups (missing app:"pushups")' };
  }
  if (payload.schema !== SCHEMA) {
    return { ok: false, added: 0, error: 'Unsupported backup schema ' + String(payload.schema) };
  }
  if (!Array.isArray(payload.sets)) {
    return { ok: false, added: 0, error: 'Backup has no sets array' };
  }
  if (payload.reps !== undefined && !Array.isArray(payload.reps)) {
    return { ok: false, added: 0, error: 'Backup has a reps field that is not an array' };
  }

  const db = await open();
  const incomingSets = payload.sets;
  const incomingReps = Array.isArray(payload.reps) ? payload.reps : [];
  const tx = db.transaction(['sets', 'reps'], 'readwrite');
  const setStore = tx.objectStore('sets');
  const repStore = tx.objectStore('reps');
  const idMap = new Map();
  let addedSets = 0;
  let addedReps = 0;

  for (const s of incomingSets) {
    if (!s || typeof s !== 'object') continue;
    const oldId = s.id;
    const rec = { ...s };
    delete rec.id;
    if (typeof rec.startedAt !== 'number') rec.startedAt = Date.now();
    if (!rec.day) rec.day = localDay(rec.startedAt);
    rec.schema = SCHEMA;
    let key;
    if (isIdKey(oldId) && await idIsFree(setStore, oldId)) {
      rec.id = oldId;
      key = await toPromise(setStore.put(rec));
    } else {
      key = await toPromise(setStore.add(rec));
    }
    if (oldId !== undefined) idMap.set(oldId, key);
    addedSets++;
  }

  for (const r of incomingReps) {
    if (!r || typeof r !== 'object') continue;
    const rec = { ...r };
    const oldRepId = rec.id;
    delete rec.id;
    if (rec.setId !== undefined) {
      if (idMap.has(rec.setId)) rec.setId = idMap.get(rec.setId);
    }
    if (isIdKey(oldRepId) && await idIsFree(repStore, oldRepId)) {
      rec.id = oldRepId;
      await toPromise(repStore.put(rec));
    } else {
      await toPromise(repStore.add(rec));
    }
    addedReps++;
  }

  await finish(tx);
  return {
    ok: true,
    added: addedSets,
    addedSets,
    addedReps,
    error: null,
  };
}
