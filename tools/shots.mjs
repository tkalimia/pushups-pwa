// UI screenshot harness: headless Chrome at iPhone metrics, driven over CDP.
//   node tools/shots.mjs <url> <out.png> [--dark] [--light] [--step <js>] [--wait <ms>] [--click <selector>]
// Chrome flags include a fake camera device, so #/train reaches the real setup layout.
import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const W = Number(process.env.SHOT_W || 402), H = Number(process.env.SHOT_H || 874);
const UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';

const argv = process.argv.slice(2);
const url = argv.shift();
const out = argv.shift();
if (!url || !out) {
  console.error('usage: node tools/shots.mjs <url> <out.png> [--dark] [--step <js>] [--click <sel>] [--wait <ms>]');
  process.exit(2);
}
const steps = [];
let scheme = '';
while (argv.length) {
  const f = argv.shift();
  if (f === '--dark') scheme = 'dark';
  else if (f === '--light') scheme = 'light';
  else if (f === '--step' || f === '--click' || f === '--wait') steps.push([f.slice(2), argv.shift()]);
  else throw new Error('unknown flag ' + f);
}

// Fresh profile per run — a leftover service worker would serve its own stale precache.
const profile = mkdtempSync(join(tmpdir(), 'pushups-shot-'));
const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=0`, `--user-data-dir=${profile}`,
  `--window-size=${W},${H}`, `--user-agent=${UA}`,
  '--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream',
  '--hide-scrollbars', '--allow-running-insecure-content', '--mute-audio',
  'about:blank',
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


const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// Chrome binds an ephemeral port and records it in its own profile directory. A hard-coded port
// is a race that the previous run wins: the new Chrome cannot bind, and the CDP client attaches
// to the stale browser instead — with a different camera, a different cache and a different build.
const readPort = async () => {
  for (let i = 0; i < 120; i++) {
    try {
      const line = readFileSync(join(profile, 'DevToolsActivePort'), 'utf8').trim().split('\n')[0];
      if (Number(line) > 0) return Number(line);
    } catch (err) { void err; }
    await sleep(250);
  }
  return 0;
};
let CDP_PORT = 0;


async function target() {
  for (let i = 0; i < 60; i++) {
    try {
      if (!CDP_PORT) CDP_PORT = await readPort();
      const list = await (await fetch(`http://127.0.0.1:${CDP_PORT}/json/list`)).json();
      const page = list.find((t) => t.type === 'page');
      if (page) return page;
    } catch { /* still starting */ }
    await sleep(250);
  }
  throw new Error('chrome did not start:\n' + chromeErr.slice(-2000));
}

let id = 0;
const pending = new Map();
let ws;
function send(method, params = {}) {
  const msgId = ++id;
  ws.send(JSON.stringify({ id: msgId, method, params }));
  return new Promise((resolve, reject) => pending.set(msgId, { resolve, reject }));
}

const page = await target();
ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
ws.onmessage = (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) {
    const { resolve, reject } = pending.get(m.id);
    pending.delete(m.id);
    if (m.error) reject(new Error(m.error.message)); else resolve(m.result);
  } else if (m.method === 'Log.entryAdded' && m.params.entry.level === 'error') {
    console.error('  [console]', m.params.entry.text);
  } else if (m.method === 'Runtime.exceptionThrown') {
    const d = m.params.exceptionDetails;
    console.error('  [exception]', d.exception?.description || d.text);
  }
};

await send('Page.enable');
await send('Runtime.enable');
await send('Log.enable');
await send('Network.enable');
await send('Network.setCacheDisabled', { cacheDisabled: true });
await send('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: 2, mobile: true });
await send('Network.setUserAgentOverride', { userAgent: UA });
if (scheme) await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: scheme }] });
await send('Page.navigate', { url });
await sleep(3500);

for (const [kind, arg] of steps) {
  if (kind === 'wait') { await sleep(Number(arg)); continue; }
  const expr = kind === 'click'
    ? `(() => { const el = document.querySelector(${JSON.stringify(arg)}); if (!el) throw new Error('no element ' + ${JSON.stringify(arg)}); el.click(); return 'clicked'; })()`
    : `(async () => { let f = (${arg}); if (typeof f === 'function') f = f(); const v = await f; return typeof v === 'string' ? v : JSON.stringify(v); })()`;
  const res = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
  if (res.exceptionDetails) {
    console.error('  [step failed]', arg, res.exceptionDetails.exception?.description || '');
  } else if (process.env.SHOW_STEPS) {
    console.log('  [step]', arg, '=>', res.result?.value);
  }
  await sleep(700);
}

const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
writeFileSync(out, Buffer.from(shot.data, 'base64'));
console.log('wrote', out);
ws.close();
chrome.kill();
process.exit(0);
