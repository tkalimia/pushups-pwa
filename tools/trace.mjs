import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const CLIP = process.argv[2] || '.repcheck/pushups_src.webm';
const SECS = Number(process.argv[3] || 40);
const HREF = '/' + CLIP.replace(/^\.\//, '');
const URL = `http://127.0.0.1:8099/index.html?trace=${Date.now()}#/debug`;
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


const PROFILE = mkdtempSync(join(tmpdir(), 'pushups-trace-'));
const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=0`,
  `--user-data-dir=${PROFILE}`,
  '--window-size=402,874', '--mute-audio', 'about:blank',
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


let mid = 0;
const pending = new Map();
let ws;
const send = (method, params = {}) => {
  const i = ++mid;
  ws.send(JSON.stringify({ id: i, method, params }));
  return new Promise((res, rej) => pending.set(i, { res, rej }));
};
const evalJs = async (expression) => {
  const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || 'eval failed');
  return r.result?.value;
};
for (let k = 0; k < 80; k++) {
  try {
    if (!CDP_PORT) CDP_PORT = await readPort();
    const l = await (await fetch(`http://127.0.0.1:${CDP_PORT}/json/list`)).json();
    const p = l.find((t) => t.type === 'page');
    if (p) {
      ws = new WebSocket(p.webSocketDebuggerUrl);
      await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
      break;
    }
  } catch { /* starting */ }
  await sleep(250);
}
if (!ws) { console.error('chrome failed:\n' + chromeErr.slice(-1200)); process.exit(2); }
ws.onmessage = (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) {
    const { res, rej } = pending.get(m.id);
    pending.delete(m.id);
    if (m.error) rej(new Error(m.error.message)); else res(m.result);
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
await sleep(6000);

// Hand the clip to the file input the same way a person would.
const loaded = await evalJs(`(async () => {
  const blob = await (await fetch('${HREF}')).blob();
  const f = new File([blob], 'clip.webm', { type: 'video/webm' });
  const dt = new DataTransfer();
  dt.items.add(f);
  const inp = document.querySelector('#f-file');
  if (!inp) return 'no #f-file';
  inp.files = dt.files;
  inp.dispatchEvent(new Event('change', { bubbles: true }));
  return 'dispatched ' + Math.round(blob.size / 1e6) + 'MB';
})()`);
console.log('  clip:', loaded);
await sleep(12000);

const READ = `(() => {
  const t = (s) => (document.querySelector(s)?.textContent || '').trim();
  return JSON.stringify({
    mode: t('#mode'), state: t('#o-state'), armed: t('#o-armed'), side: t('#o-side'),
    elbow: t('#o-elbow'), shoulder: t('#o-shoulder'), hip: t('#o-hip'), body: t('#o-body'),
    reasons: t('#o-reasons'), q: t('#o-q'), reps: t('#o-reps'), frames: t('#o-frames'),
    vt: (() => { const v = document.querySelector('#f-video'); return v ? Math.round(v.currentTime) + 's ' + v.videoWidth + 'x' + v.videoHeight : 'none'; })(),
  });
})()`;

const rows = [];
for (let i = 0; i < Math.round(SECS / 2); i++) {
  await sleep(2000);
  const s = JSON.parse(await evalJs(READ));
  rows.push([s.vt, s.state, s.armed, s.elbow, s.shoulder, s.hip, s.body, s.q, s.reps, s.reasons].join(' | '));
}
console.log('  t | state | armed | elbow L/R | shoulder L/R | hip | body | q/fps | det/clean | plank reasons');
console.log(rows.join('\n'));
const shot = await send('Page.captureScreenshot', { format: 'png' });
writeFileSync('/tmp/trace.png', Buffer.from(shot.data, 'base64'));
const last = JSON.parse(await evalJs(READ));
console.log('  final:', JSON.stringify(last));
const reps = parseInt((last.reps || '0').split('/')[0], 10) || 0;
console.log(reps > 0 ? `PASS — ${reps} reps detected in the clip` : 'FAIL — counter never fired on a real pushup clip');
process.exit(reps > 0 ? 0 : 1);
