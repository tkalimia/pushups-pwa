import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const PORT = 9335;
const URL = `http://127.0.0.1:8099/index.html?camfail=${Date.now()}#/train`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=${PORT}`,
  `--user-data-dir=${mkdtempSync(join(tmpdir(), 'pushups-camfail-'))}`,
  '--window-size=402,874', '--mute-audio', 'about:blank',
], { stdio: ['ignore', 'ignore', 'pipe'] });
let chromeErr = '';
chrome.stderr.on('data', (d) => { chromeErr += d.toString(); });

let id = 0;
const pending = new Map();
let ws;
const send = (method, params = {}) => {
  const mid = ++id;
  ws.send(JSON.stringify({ id: mid, method, params }));
  return new Promise((resolve, reject) => pending.set(mid, { resolve, reject }));
};
const evalJs = async (expression) => {
  const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || 'eval failed');
  return r.result?.value;
};

for (let i = 0; i < 80; i++) {
  try {
    const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
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
  }
};

await send('Page.enable');
await send('Runtime.enable');
await send('Network.enable');
await send('Network.setBypassServiceWorker', { bypass: true });
await send('Emulation.setDeviceMetricsOverride', { width: 402, height: 874, deviceScaleFactor: 2, mobile: true });

// Deny the camera before any app script runs, the way iOS does in a Home Screen web app.
await send('Page.addScriptToEvaluateOnNewDocument', {
  source: `
    navigator.mediaDevices.getUserMedia = () =>
      Promise.reject(new DOMException('Permission denied', 'NotAllowedError'));
    const _mm = window.matchMedia.bind(window);
    window.matchMedia = (q) =>
      String(q).includes('display-mode') ? { matches: true, media: q, addEventListener() {}, removeEventListener() {} } : _mm(q);
  `,
});

await send('Page.navigate', { url: URL });
await sleep(9000);
// The boot path starts the camera itself; if a setup screen is still up, tap Start.
await evalJs(`(() => { const b = document.querySelector('#startBtn'); if (b && !b.hidden) b.click(); return 1 })()`);
await sleep(4000);

const out = JSON.parse(await evalJs(`(() => {
  const card = document.querySelector('#camoff');
  const title = card?.querySelector('div')?.textContent?.trim() || '';
  const steps = [...(card?.querySelectorAll('li,div') || [])].map((n) => n.textContent.trim()).filter(Boolean);
  const t = getComputedStyle(card?.firstElementChild || card).color;
  return JSON.stringify({
    visible: !!card && !card.hidden,
    title,
    steps,
    lines: steps.length,
    titleColor: t,
  });
})()`));

const shot = await send('Page.captureScreenshot', { format: 'png' });
writeFileSync('/tmp/camfail.png', Buffer.from(shot.data, 'base64'));

console.log(JSON.stringify(out, null, 2));
const ok = out.visible
  && out.title === 'Camera permission was blocked'
  && out.lines >= 5
  && out.titleColor === 'rgb(233, 238, 234)';
if (!ok) console.error('  the failure did not reach the screen, or reached it unreadable');
process.exit(ok ? 0 : 1);
