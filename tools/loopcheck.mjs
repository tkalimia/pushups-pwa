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
