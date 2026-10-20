import { load } from './settings.js';
import { initUpdate, requestWakeLock, watchWakeLock, requestPersistent, isStandalone } from './upgrade.js';

const ROUTES = {
  today: () => import('./views/today.js'),
  train: () => import('./views/train.js'),
  progress: () => import('./views/progress.js'),
  badges: () => import('./views/badges.js'),
  settings: () => import('./views/settings.js'),
  debug: () => import('./views/debug.js'),
};

const host = document.getElementById('view');
const banner = document.getElementById('banner');
let current = null;

function routeName() {
  const h = (location.hash || '#/today').replace(/^#\//, '').split('?')[0];
  return ROUTES[h] ? h : 'today';
}

function markTab(name) {
  document.querySelectorAll('#tabs a').forEach((a) => {
    a.setAttribute('aria-current', a.dataset.tab === name ? 'true' : 'false');
  });
}

async function render() {
  const name = routeName();
  if (current && current.unmount) {
    try { await current.unmount(); } catch (e) { console.warn('unmount', e); }
  }
  current = null;
  host.replaceChildren();
  markTab(name);
  const mod = await ROUTES[name]();
  const view = mod.default ? mod.default : mod;
  current = await view(host, { route: name, render, params: new URLSearchParams(location.search) });
}

window.addEventListener('hashchange', render);

// ── update prompt ──
function showBanner(reload) {
  const box = document.createElement('div');
  box.textContent = 'Update available — tap to reload';
  box.addEventListener('click', () => {
    banner.replaceChildren();
    reload();
  });
  banner.replaceChildren(box);
}

// ── lifecycle ──
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') requestWakeLock('return-to-foreground');
});

function fail(err) {
  console.error(err);
  const p = document.createElement('p');
  p.className = 'h1';
  p.textContent = 'Startup failed';
  const s = document.createElement('p');
  s.className = 'sub';
  s.textContent = String(err && err.message ? err.message : err);
  const pad = document.createElement('div');
  pad.className = 'pad';
  pad.append(p, s);
  host.replaceChildren(pad);
}

async function boot() {
  load();
  if (window.__swReg) initUpdate({ swRegistration: window.__swReg, onPrompt: showBanner });
  watchWakeLock();
  if (isStandalone()) requestPersistent().catch(() => {});
  await render();
}

boot().catch(fail);
