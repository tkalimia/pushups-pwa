import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const URL = `http://127.0.0.1:8099/index.html?camfail=${Date.now()}#/train`;
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


const PROFILE = mkdtempSync(join(tmpdir(), 'pushups-camfail-'));
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

// Run as  CAMFAIL=tab node tools/camfailcheck.mjs  to emulate a plain Safari tab.
const TAB = process.env.CAMFAIL === 'tab';
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

// Deny the camera before any app script runs, the way iOS does in a Home Screen web app.
await send('Page.addScriptToEvaluateOnNewDocument', {
  source: `
    navigator.mediaDevices.getUserMedia = () =>
      Promise.reject(new DOMException('Permission denied', 'NotAllowedError'));
    ${TAB ? '' : `
    const _mm = window.matchMedia.bind(window);
    window.matchMedia = (q) =>
      String(q).includes('display-mode') ? { matches: true, media: q, addEventListener() {}, removeEventListener() {} } : _mm(q);`}
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
  const go = card?.querySelector('.act a');
  const cp = card?.querySelector('.act button');
  return JSON.stringify({
    visible: !!card && !card.hidden,
    title,
    steps,
    lines: steps.length,
    titleColor: t,
    safariLink: go ? { text: go.textContent.trim(), target: go.target, href: go.href } : null,
    copyBtn: cp ? cp.textContent.trim() : null,
  });
})()`));

await evalJs(`(() => { document.querySelector('#camoff .act button')?.click(); return 1 })()`);
await sleep(1200);
out.afterCopy = JSON.parse(await evalJs(`(() => {
  const b = document.querySelector('#camoff .act button');
  return JSON.stringify({ label: b?.textContent?.trim() || null, addr: document.querySelector('#camoff .addr')?.textContent || null });
})()`));

const shot = await send('Page.captureScreenshot', { format: 'png' });
writeFileSync(`/tmp/camfail-${TAB ? 'tab' : 'standalone'}.png`, Buffer.from(shot.data, 'base64'));

console.log(JSON.stringify(out, null, 2));
const ok = (TAB
  ? out.visible && out.title === 'Camera permission was blocked'
    && out.safariLink === null && out.copyBtn === null
    && out.steps[1].includes('address bar')
  : out.visible && out.title === 'Camera permission was blocked'
    && out.safariLink?.text === 'Open in Safari' && out.safariLink?.target === '_blank'
    && out.safariLink?.href?.includes('#/train') && out.copyBtn === 'Copy address'
    && !!(out.afterCopy?.label || out.afterCopy?.addr))
  && out.title === 'Camera permission was blocked'
  && out.lines >= 5
  && out.titleColor === 'rgb(233, 238, 234)';
if (!ok) console.error('  the failure did not reach the screen, or reached it without the Safari exits');
process.exit(ok ? 0 : 1);
