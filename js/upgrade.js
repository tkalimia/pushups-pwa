const POLL_MS = 5 * 60 * 1000;

let reg = null;
let pollTimer = 0;
let listenersAttached = false;
let promptedWorker = null;
let reloadRequested = false;
let onPromptRef = null;

let sentinel = null;
let wantLock = false;
let lockReason = '';
let lockWatchAttached = false;

function hasSW() {
  return typeof navigator !== 'undefined'
    && 'serviceWorker' in navigator
    && !!navigator.serviceWorker;
}

function doReload() {
  if (reloadRequested) return;
  reloadRequested = true;
  try {
    if (typeof location !== 'undefined') location.reload();
  } catch (err) {
    void err;
  }
}

function attachControllerListener() {
  if (!hasSW()) return;
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (reloadRequested) doReload();
  });
}

function promptWorker(worker) {
  if (!worker || promptedWorker === worker) return;
  promptedWorker = worker;
  const reload = () => {
    try {
      worker.postMessage('skip');
    } catch (err) {
      void err;
    }
    reloadRequested = true;
  };
  attachControllerListener();
  if (typeof onPromptRef === 'function') onPromptRef(reload);
}

function checkForWaiting() {
  if (reg && reg.waiting) promptWorker(reg.waiting);
}

function checkUpdate() {
  if (!reg || typeof reg.update !== 'function') return;
  try {
    Promise.resolve(reg.update()).catch(() => {});
  } catch (err) {
    void err;
  }
}

function onVisibility() {
  if (typeof document === 'undefined') return;
  if (document.visibilityState !== 'visible') return;
  checkUpdate();
  if (wantLock && !sentinel) void requestWakeLock(lockReason || 'resume');
}

export function initUpdate({ swRegistration, onPrompt } = {}) {
  if (!swRegistration) return false;
  reg = swRegistration;
  onPromptRef = typeof onPrompt === 'function' ? onPrompt : onPromptRef;

  if (!listenersAttached) {
    listenersAttached = true;
    if (typeof setInterval !== 'undefined') pollTimer = setInterval(checkUpdate, POLL_MS);
    if (typeof document !== 'undefined') document.addEventListener('visibilitychange', onVisibility);
    if (hasSW()) {
      navigator.serviceWorker.addEventListener('message', (ev) => {
        const data = ev && ev.data;
        const isReload = data === 'reload'
          || (data && (data.type === 'reload' || data.reload === true));
        if (isReload) doReload();
      });
    }
    swRegistration.addEventListener('updatefound', () => {
      const worker = swRegistration.installing;
      if (!worker) return;
      worker.addEventListener('statechange', () => {
        if (worker.state === 'installed' && reg && reg.waiting) promptWorker(reg.waiting);
        else if (worker.state === 'activated') promptedWorker = null;
      });
    });
  }

  if (reg.waiting) promptWorker(reg.waiting);
  checkUpdate();
  return true;
}

export function setUpdatePromptHandler(fn) {
  onPromptRef = typeof fn === 'function' ? fn : null;
  checkForWaiting();
}

export async function requestWakeLock(reason = '') {
  if (typeof navigator === 'undefined' || !navigator.wakeLock || typeof navigator.wakeLock.request !== 'function') {
    return false;
  }
  wantLock = true;
  lockReason = reason;
  if (typeof document !== 'undefined' && document.visibilityState !== 'visible') return false;
  if (sentinel) return true;
  try {
    sentinel = await navigator.wakeLock.request('screen');
    if (typeof sentinel.addEventListener === 'function') {
      sentinel.addEventListener('release', () => { sentinel = null; });
    }
    return true;
  } catch (err) {
    void err;
    sentinel = null;
    return false;
  }
}

export function releaseWakeLock() {
  wantLock = false;
  lockReason = '';
  const s = sentinel;
  sentinel = null;
  if (!s || typeof s.release !== 'function') return false;
  try {
    Promise.resolve(s.release()).catch(() => {});
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export function watchWakeLock() {
  if (typeof document === 'undefined' || lockWatchAttached) return lockWatchAttached;
  lockWatchAttached = true;
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState !== 'visible') return;
    if (wantLock && !sentinel) void requestWakeLock(lockReason || 'reacquire');
  });
  return true;
}

export async function requestPersistent() {
  try {
    if (typeof navigator === 'undefined' || !navigator.storage || typeof navigator.storage.persist !== 'function') {
      return false;
    }
    return !!(await navigator.storage.persist());
  } catch (err) {
    void err;
    return false;
  }
}

export async function persistentStatus() {
  try {
    if (typeof navigator === 'undefined' || !navigator.storage || typeof navigator.storage.persisted !== 'function') {
      return false;
    }
    return !!(await navigator.storage.persisted());
  } catch (err) {
    void err;
    return false;
  }
}

export function tryBadging(count) {
  if (typeof navigator === 'undefined' || typeof navigator.setAppBadge !== 'function') return false;
  try {
    const value = Number.isFinite(Number(count)) ? Math.max(0, Math.round(Number(count))) : undefined;
    Promise.resolve(value === undefined ? navigator.setAppBadge() : navigator.setAppBadge(value)).catch(() => {});
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export function isStandalone() {
  try {
    if (typeof window !== 'undefined' && typeof window.matchMedia === 'function') {
      if (window.matchMedia('(display-mode: standalone)').matches) return true;
      if (window.matchMedia('(display-mode: fullscreen)').matches) return true;
    }
    return navigator.standaloneMode === true || navigator.standalone === true;
  } catch (err) {
    void err;
    return false;
  }
}

export function platformInfo() {
  const ua = (typeof navigator !== 'undefined' && navigator.userAgent) || '';
  const ios = /iPad|iPhone|iPod/.test(ua)
    || (typeof navigator !== 'undefined' && navigator.platform === 'MacIntel'
      && typeof navigator !== 'undefined' && navigator.maxTouchPoints > 1);
  return {
    ios,
    safari: /AppleWebKit/.test(ua) && !/CriOS|FxiOS|EdgiOS|OPiOS|Chrome\/|Chromium/.test(ua),
    standalone: isStandalone(),
    secure: typeof window !== 'undefined' ? window.isSecureContext === true : true,
    wakeLock: typeof navigator !== 'undefined' && 'wakeLock' in navigator,
    badging: typeof navigator !== 'undefined' && typeof navigator.setAppBadge === 'function',
    persist: typeof navigator !== 'undefined' && !!navigator.storage && typeof navigator.storage.persist === 'function',
    vibrate: typeof navigator !== 'undefined' && typeof navigator.vibrate === 'function',
  };
}

export function stopUpdatePolling() {
  if (pollTimer && typeof clearInterval !== 'undefined') clearInterval(pollTimer);
  pollTimer = 0;
  if (typeof document !== 'undefined') document.removeEventListener('visibilitychange', onVisibility);
  return true;
}
