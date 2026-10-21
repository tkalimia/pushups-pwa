#!/usr/bin/env bash
# Prove that a camera failure actually reaches the screen.
#
# The original defect: camFail() referenced an identifier that does not exist (`dce`), so the
# ReferenceError it threw swallowed every camera failure — the user saw a black rectangle and no
# explanation. A loopcheck cannot catch this because the loop was never the problem; the *report*
# was. So this check denies the camera on purpose and asserts the card renders with the right
# instructions, including the iOS Home-Screen-app rule.
#
#   bash scripts/verify-failure-card.sh
set -euo pipefail
cd "$(dirname "$0")/.."

run_case() {
  if ! curl -sf -o /dev/null http://127.0.0.1:8099/index.html; then
    python3 tools/serve.py >/dev/null 2>&1 &
    SERVE=$!
    trap 'kill $SERVE 2>/dev/null || true' EXIT
    sleep 1
  fi

cat > tools/camfailcheck.mjs <<'EOF'
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

// Run as  CAMFAIL=tab node tools/camfailcheck.mjs  to emulate a plain Safari tab.
const TAB = process.env.CAMFAIL === 'tab';
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
EOF

  if node tools/camfailcheck.mjs; then echo "PASS — $1"; else echo "FAIL — $1"; exit 1; fi
}

run_case "home-screen app: card renders with Safari exits"
CAMFAIL=tab run_case "safari tab: card renders without the Safari exits"
