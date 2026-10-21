#!/usr/bin/env bash
# Hardens the camera path after the "camera not working" report on the iPhone.
#
# Three defects, all found by reading what the phone actually did rather than by guessing:
#
# 1. camFail() referenced an identifier that exists nowhere in the project (`dce`). A bare
#    undefined name throws a ReferenceError, so the camera error card was never rendered —
#    every camera failure produced a silent black rectangle with no explanation. This is why
#    "camera not working" gave us nothing to read.
# 2. The error card painted its title in --text, which is near-black in light mode, on a
#    surface that is always near-black. Unreadable even once (1) is fixed.
# 3. The instructions did not know about the one iOS rule that decides everything here: a web
#    app launched from a Home Screen icon cannot get the camera (WebKit bug 185448 is still
#    open). Only a Safari tab can. In standalone mode the advice has to lead with that.
#
# Also adds tools/loopcheck.mjs — a headless guard that fails the build if the pose loop
# delivers zero frames, which is the exact class of bug that hid the MediaPipe sync-return
# defect for three phases.
#
#   bash scripts/harden-camera-path.sh
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import pathlib, sys

def sub(path, old, new, count=1):
    p = pathlib.Path(path)
    text = p.read_text()
    if new in text and old not in text:
        print(f'skip (already applied): {path}')
        return
    if text.count(old) != count:
        sys.exit(f'FAIL {path}: anchor found {text.count(old)}x, expected {count}\n---\n{old}\n---')
    p.write_text(text.replace(old, new))
    print(f'patched {path}')

# ── 1 + 2 + 3: the failure card actually renders, and says the right thing ──
sub('js/views/train.js',
"""  function camFail(err) {
    const d = (dce || describeCameraError)(err);
    els.camoff.hidden = false;
    els.camoff.replaceChildren();
    const h3 = document.createElement('div');
    h3.style.color = 'var(--text)';
    h3.style.fontWeight = '600';
    h3.textContent = d.title;""",
"""  function camFail(err) {
    // `dce` used to be referenced here and exists nowhere — the ReferenceError it threw meant
    // no camera failure ever reached the screen.
    const d = describeCameraError(err, { standalone: isStandalone() });
    els.camoff.hidden = false;
    els.camoff.replaceChildren();
    const h3 = document.createElement('div');
    h3.style.color = 'var(--porcelain)';
    h3.style.fontWeight = '600';
    h3.textContent = d.title;""")

sub('js/views/train.js',
"""import { requestWakeLock, tryBadging } from '../upgrade.js';""",
"""import { requestWakeLock, tryBadging, isStandalone } from '../upgrade.js';""")

sub('js/camera.js',
"""export function describeCameraError(err) {
  const name = (err && err.name) || '';
  const message = (err && err.message) || '';""",
"""export function describeCameraError(err, opts = {}) {
  const name = (err && err.name) || '';
  const message = (err && err.message) || '';
  const standalone = !!(opts && opts.standalone);""")

sub('js/camera.js',
"""      title: 'Camera permission was blocked',
        steps: [
          'Tap the camera or page-info icon in the address bar and set Camera to Allow, then reload.',
          'If it still says blocked: Settings ▸ Safari ▸ Camera ▸ Allow (or "Ask"), then scroll back to the app.',
          'For a home-screen app: Settings ▸ pushups ▸ Camera ▸ Allow.',
          'Close other apps that may hold the camera (Photo Booth, FaceTime) and tap Start again.',
        ],""",
"""      title: 'Camera permission was blocked',
        steps: standalone ? [
          'iOS gives the camera to Safari tabs but never to a web app opened from its Home Screen icon — that is an Apple limitation, not a setting.',
          'Open this address in Safari and allow the camera there once.',
          'Reach it in one tap by adding it to Safari Favorites or Bookmarks instead of the Home Screen.',
          'If it still says blocked: Settings ▸ Safari ▸ Camera ▸ Allow or Ask, then reload the tab.',
        ] : [
          'Tap the camera or page-info icon in the address bar and set Camera to Allow, then reload.',
          'If it still says blocked: Settings ▸ Safari ▸ Camera ▸ Allow (or "Ask"), then scroll back to the app.',
          'For a home-screen app: Settings ▸ pushups ▸ Camera ▸ Allow.',
          'Close other apps that may hold the camera (Photo Booth, FaceTime) and tap Start again.',
        ],""")

# The http advice told people to Add to Home Screen — which is precisely what kills the camera.
sub('js/camera.js',
"""        'Open the app through its https:// address, or tap the Share button in Safari and choose Add to Home Screen so it loads over HTTPS.',""",
"""        'Open the app through its https:// address in Safari.',""")

sub('js/camera.js',
"""        title: 'The browser blocked camera access for security',
        steps: [
          'Confirm the page address starts with https:// (or localhost).',
          'Reload the page.',
          'If the app came from a Home Screen icon, delete it and add it again from the https:// page.',
        ],""",
"""        title: 'The browser blocked camera access for security',
        steps: standalone ? [
          'This page is running as a Home Screen web app, where iOS withholds the camera. Open the same address in Safari.',
          'Confirm the address starts with https:// (or localhost).',
        ] : [
          'Confirm the page address starts with https:// (or localhost).',
          'Reload the page.',
          'If the app came from a Home Screen icon, remove it and use the Safari tab.',
        ],""")

# ── a failed route swap used to leave the screen empty with only a console line ──
sub('js/main.js',
"""window.addEventListener('hashchange', render);""",
"""window.addEventListener('hashchange', () => { render().catch(fail); });""")

print('done')
PY

# ── the guard: prove the pose loop actually delivers frames ─────────────────
cat > tools/loopcheck.mjs <<'EOF'
// Regression guard for the bug that hid for three phases: the pose loop ran at 25 detections
// per second and delivered nothing, because detectForVideo() returns its result synchronously
// in MediaPipe 0.10.x while the loop only handled the promise form. The screen looked alive —
// camera light on, preview up — while the counter never saw one landmark.
//
//   node tools/loopcheck.mjs [base-url]     exit 0 = frames flowing
import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const BASE = process.argv[2] || 'http://127.0.0.1:8099';
const URL = `${BASE}/index.html?loopcheck=${Date.now()}#/train`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// Chrome binds an ephemeral port and records it in its own profile directory. A hard-coded port
// is a race that the previous run wins: the new Chrome cannot bind, and the CDP client attaches
// to the stale browser instead — with a different camera, a different cache and a different build.
const readPort = async () => {
  for (let i = 0; i < 120; i++) {
    try {
      const line = readFileSync(join(PROFILE, 'DevToolsActivePort'), 'utf8').trim().split('\n')[0];
      if (Number(line) > 0) return Number(line);
    } catch (err) { void err; }
    await sleep(250);
  }
  return 0;
};
let CDP_PORT = 0;


const PROFILE = mkdtempSync(join(tmpdir(), 'pushups-loop-'));
const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=0`,
  `--user-data-dir=${PROFILE}`,
  '--window-size=402,874', '--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream',
  '--mute-audio', 'about:blank',
], { stdio: ['ignore', 'ignore', 'pipe'] });
let chromeErr = '';
chrome.stderr.on('data', (d) => { chromeErr += d.toString(); });

// A harness that exits through an exception used to leave its Chrome running for hours, holding a
// debug port and a camera. This runs on every path out, including the ones that throw.
const teardown = () => { try { chrome.kill('SIGKILL'); } catch (err) { void err; } };
process.on('exit', teardown);
process.on('uncaughtException', () => { teardown(); process.exit(1); });
process.on('SIGINT', () => { teardown(); process.exit(130); });
process.on('SIGTERM', () => { teardown(); process.exit(143); });


let id = 0;
const pending = new Map();
let ws;
function send(method, params = {}) {
  const msgId = ++id;
  ws.send(JSON.stringify({ id: msgId, method, params }));
  return new Promise((resolve, reject) => pending.set(msgId, { resolve, reject }));
}
async function evalJs(expression) {
  const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || 'eval failed');
  return r.result?.value;
}

for (let i = 0; i < 80; i++) {
  try {
    if (!CDP_PORT) CDP_PORT = await readPort();
    const list = await (await fetch(`http://127.0.0.1:${CDP_PORT}/json/list`)).json();
    const page = list.find((t) => t.type === 'page');
    if (page) {
      ws = new WebSocket(page.webSocketDebuggerUrl);
      await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
      break;
    }
  } catch { /* starting */ }
  await sleep(250);
}
if (!ws) { console.error('chrome failed to start:\n' + chromeErr.slice(-1500)); process.exit(2); }

ws.onmessage = (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) {
    const { resolve, reject } = pending.get(m.id);
    pending.delete(m.id);
    if (m.error) reject(new Error(m.error.message)); else resolve(m.result);
  } else if (m.method === 'Runtime.exceptionThrown') {
    console.error('  [exception]', m.params.exceptionDetails.exception?.description || '');
  }
};

await send('Page.enable');
await send('Runtime.enable');
await send('Network.enable');
await send('Network.setBypassServiceWorker', { bypass: true });
// Bypassing the service worker does not bypass the HTTP cache: without this a patched ES module
// stays stale in the harness and a real fix looks like it had no effect.
await send('Network.setCacheDisabled', { cacheDisabled: true });
await send('Emulation.setDeviceMetricsOverride', { width: 402, height: 874, deviceScaleFactor: 2, mobile: true });
await send('Page.navigate', { url: URL });
await sleep(14000);

const read = () => evalJs(`(() => {
  const txt = (s) => (document.querySelector(s)?.textContent || '').trim();
  return JSON.stringify({ fps: txt('#fpstxt'), pill: txt('#pillText'), q: txt('#qtxt'),
    camoff: !document.querySelector('#camoff')?.hidden, manual: txt('#phaseLabel') });
})()`);
const first = JSON.parse(await read());
await sleep(2500);
const second = JSON.parse(await read());

const fps = Number.parseInt(second.fps, 10) || 0;
const problems = [];
if (first.pill === 'camera blocked' || second.camoff) problems.push('camFail card is showing');
if (second.pill === 'starting') problems.push('still "starting" — createTracker() never ran');
if (second.pill === 'loading pose model') problems.push('model never finished loading');
if (second.pill === 'pose error') problems.push('the landmarker reported an error');
if (fps < 8) problems.push(`only ${fps} fps — the loop is not delivering frames`);
if (second.pill === first.pill && second.pill === 'loading pose model') problems.push('pill never advanced');

console.log('build loopcheck @', BASE);
console.log('  t+14s', JSON.stringify(first));
console.log('  t+16s', JSON.stringify(second));
ws.close();
chrome.kill();
if (problems.length) {
  console.error('FAIL');
  problems.forEach((p) => console.error('  · ' + p));
  process.exit(1);
}
console.log('PASS — pose loop delivering frames at ' + fps + ' fps');
process.exit(0);
EOF
chmod +x tools/loopcheck.mjs

node --check tools/loopcheck.mjs
echo "wrote tools/loopcheck.mjs"
