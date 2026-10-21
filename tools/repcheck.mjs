import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { resolve } from 'node:path';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const BASE = process.env.BASE || 'http://127.0.0.1:8099';
const Y4M = resolve(process.argv[2] || '.repcheck/pushups_rep.y4m');
const URL = `${BASE}/index.html?repcheck=${Date.now()}#/train`;
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


const PROFILE = mkdtempSync(join(tmpdir(), 'pushups-rep-'));
const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=0`,
  `--user-data-dir=${PROFILE}`,
  '--window-size=402,874',
  '--use-fake-ui-for-media-stream',
  // Both flags are required: with only the file flag Chrome quietly falls back to the real
  // webcam, which in headless mode yields a stream that never delivers a frame.
  '--use-fake-device-for-media-stream',
  `--use-file-for-fake-video-capture=${Y4M}`,
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
const send = (method, params = {}) => {
  const mid = ++id;
  ws.send(JSON.stringify({ id: mid, method, params }));
  return new Promise((resolve_, reject) => pending.set(mid, { resolve: resolve_, reject }));
};
const evalJs = async (expression) => {
  const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || 'eval failed');
  return r.result?.value;
};

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
if (!ws) { console.error('chrome failed:\n' + chromeErr.slice(-1200)); process.exit(2); }

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

const READ = `(() => {
  const txt = (s) => (document.querySelector(s)?.textContent || '').trim();
  return JSON.stringify({
    reps: txt('#repnum'), fps: txt('#fpstxt'), pill: txt('#pillText'),
    phase: txt('#phaseLabel'), warn: txt('#warn') || txt('#lost'),
    checks: [...document.querySelectorAll('.checkrow,.chk')].map((n) => n.textContent.trim().replace(/\\s+/g,' ')).slice(0,6),
    vid: (() => { const v = document.querySelector('video'); return v ? v.readyState + ' ' + v.videoWidth + 'x' + v.videoHeight : 'none'; })(),
  });
})()`;

await sleep(16000);
console.log('  setup  ', await evalJs(READ));

// Page.captureScreenshot never composites a camera frame in headless Chrome — the video area comes
// back black — so the only way to see what MediaPipe was handed is to draw the element onto a
// canvas from inside the page and pull the bytes out.
const GRAB = `(() => {
  const v = document.querySelector('video');
  if (!v || !v.videoWidth) return '';
  const c = document.createElement('canvas');
  c.width = v.videoWidth; c.height = v.videoHeight;
  c.getContext('2d').drawImage(v, 0, 0, c.width, c.height);
  return c.toDataURL('image/jpeg', 0.9);
})()`;
{
  const url = await evalJs(GRAB);
  if (url) {
    writeFileSync('/tmp/repcheck_frame.jpg', Buffer.from(url.split(',')[1], 'base64'));
    console.log('  frame   /tmp/repcheck_frame.jpg — exactly what the pose model sees');
  } else {
    console.log('  frame   no video element to sample');
  }
}

await evalJs(`(() => { const b = document.querySelector('#startBtn'); if (b) b.click(); return 1 })()`);

let maxReps = 0, sawPerson = 0, samples = [];
for (let i = 0; i < 24; i++) {
  await sleep(2500);
  const s = JSON.parse(await evalJs(READ));
  maxReps = Math.max(maxReps, parseInt(s.reps, 10) || 0);
  if (s.pill && !/not seeing|no person|starting|loading/i.test(s.pill)) sawPerson++;
  samples.push(`t+${(i + 1) * 2.5 | 0}s reps=${s.reps} fps=${s.fps} pill="${s.pill}" vid=${s.vid}`);
  if (i === 7 || i === 15) {
    const shot = await send('Page.captureScreenshot', { format: 'png' });
    writeFileSync(`/tmp/repcheck_${i}.png`, Buffer.from(shot.data, 'base64'));
  }
}
console.log(samples.filter((_, i) => i % 3 === 0).join('\n'));
const last = JSON.parse(await evalJs(READ));
console.log('  final  ', JSON.stringify(last));

console.log(`  max reps seen on screen: ${maxReps}   (clip contains ~8 in 24 s, looped)`);
// #fpstxt lives in the framing card, which the app replaces the moment counting starts — so the
// only honest proof that frames were still arriving at the end is the pill.
const fpsAlive = /fps/.test(last.pill) || /fps/.test(last.fps);
const ok = maxReps >= 3 && fpsAlive && !/not seeing/.test(last.pill);
console.log(ok ? 'PASS — real pushups counted through the camera path'
  : 'FAIL — frames arrive but the counter does not understand them');
process.exit(ok ? 0 : 1);
