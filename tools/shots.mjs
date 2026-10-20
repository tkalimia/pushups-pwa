// UI screenshot harness: headless Chrome at iPhone metrics, driven over CDP.
//   node tools/shots.mjs <url> <out.png> [--dark] [--light] [--step <js>] [--wait <ms>] [--click <selector>]
// Chrome flags include a fake camera device, so #/train reaches the real setup layout.
import { spawn } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const PORT = 9333;
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

const profile = join(tmpdir(), 'pushups-shot-profile');
const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`,
  `--window-size=${W},${H}`, `--user-agent=${UA}`,
  '--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream',
  '--hide-scrollbars', '--allow-running-insecure-content', '--mute-audio',
  'about:blank',
], { stdio: ['ignore', 'ignore', 'pipe'] });
let chromeErr = '';
chrome.stderr.on('data', (d) => { chromeErr += d.toString(); });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function target() {
  for (let i = 0; i < 60; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
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
await send('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: 2, mobile: true });
await send('Network.setUserAgentOverride', { userAgent: UA });
if (scheme) await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: scheme }] });
await send('Page.navigate', { url });
await sleep(3500);

for (const [kind, arg] of steps) {
  if (kind === 'wait') { await sleep(Number(arg)); continue; }
  const expr = kind === 'click'
    ? `(() => { const el = document.querySelector(${JSON.stringify(arg)}); if (!el) throw new Error('no element ' + ${JSON.stringify(arg)}); el.click(); return 'clicked'; })()`
    : `(async () => { const v = await (${arg}); return typeof v === 'string' ? v : JSON.stringify(v); })()`;
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
