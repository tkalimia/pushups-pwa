// Design rubric audit, measured in a real Chromium at iPhone metrics.
// Checks OpenDesign's craft rules that are machine-verifiable: WCAG contrast, tap targets,
// accent discipline, heading structure, focus styling, chart text alternatives, state coverage.
//   node tools/audit.mjs [base-url]            # default http://127.0.0.1:8099
//   SCHEMES=dark SHOTS=0 node tools/audit.mjs
import { spawn } from 'node:child_process';
import { writeFileSync, mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const W = Number(process.env.SHOT_W || 402), H = Number(process.env.SHOT_H || 874);
const BASE = process.argv[2] || 'http://127.0.0.1:8099';
const SCHEMES = (process.env.SCHEMES || 'dark,light').split(',');
const SHOTS = process.env.SHOTS !== '0';
const ROUTES = (process.env.ROUTES || '/today,/train,/train@count,/train@summary,/progress,/badges,/settings').split(',');
// Set EXPECTED=<stamp> when auditing a deployment: a stale CDN copy of the build is not the build.
const EXPECTED = process.env.EXPECTED || '';
// A route can carry a state suffix — /train@count walks the view into the counting screen before
// measuring it, so the rubric covers the phases a static hash navigation never reaches.
const STATES = {
  count: `(async () => {
    const q = (s) => document.querySelector(s);
    const nap = (ms) => new Promise((r) => setTimeout(r, ms));
    const m = q('#manualChk'); if (m && !m.checked) { m.click(); await nap(500); }
    if (q('#startBtn')) { q('#startBtn').click(); await nap(500); }
    for (let i = 0; i < 12; i++) q('#chip').click();
    return 'rep=' + q('#repnum').textContent;
  })()`,
  summary: `(async () => {
    const q = (s) => document.querySelector(s);
    const nap = (ms) => new Promise((r) => setTimeout(r, ms));
    const m = q('#manualChk'); if (m && !m.checked) { m.click(); await nap(500); }
    if (q('#startBtn')) { q('#startBtn').click(); await nap(500); }
    if (q('#chip')) for (let i = 0; i < 12; i++) q('#chip').click();
    q('#endBtn').click();
    return 'summary';
  })()`,
};
const UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';

// Fresh profile every run: a service worker left over from a previous run would serve its own precache.
const profile = mkdtempSync(join(tmpdir(), 'pushups-audit-'));
const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=0`, `--user-data-dir=${profile}`,
  `--window-size=${W},${H}`, `--user-agent=${UA}`,
  '--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream',
  '--hide-scrollbars', '--allow-running-insecure-content', '--mute-audio', 'about:blank',
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


async function firstTarget() {
  for (let i = 0; i < 80; i++) {
    try {
      if (!CDP_PORT) CDP_PORT = await readPort();
      const list = await (await fetch(`http://127.0.0.1:${CDP_PORT}/json/list`)).json();
      const page = list.find((t) => t.type === 'page');
      if (page) return page;
    } catch { /* starting */ }
    await sleep(250);
  }
  throw new Error('chrome did not start:\n' + chromeErr.slice(-1500));
}

let id = 0;
const pending = new Map();
let ws;
let consoleErrors = [];
function send(method, params = {}) {
  const mid = ++id;
  ws.send(JSON.stringify({ id: mid, method, params }));
  return new Promise((resolve, reject) => pending.set(mid, { resolve, reject }));
}
async function evalJs(expr, label) {
  const res = await send('Runtime.evaluate', { expression: `(async () => { return (${expr}); })()`, awaitPromise: true, returnByValue: true });
  if (res.exceptionDetails) throw new Error(`${label}: ${res.exceptionDetails.exception?.description || res.exceptionDetails.text}`);
  return res.result?.value;
}

const page = await firstTarget();
ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
ws.onmessage = (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) {
    const { resolve, reject } = pending.get(m.id);
    pending.delete(m.id);
    if (m.error) reject(new Error(m.error.message)); else resolve(m.result);
  } else if (m.method === 'Log.entryAdded' && m.params.entry.level === 'error') {
    // Headless has no user activation, so haptics log a warning the phone never would.
    if (/Blocked call to navigator\.vibrate/i.test(m.params.entry.text)) return;
    consoleErrors.push(m.params.entry.text);
  } else if (m.method === 'Runtime.exceptionThrown') {
    const d = m.params.exceptionDetails;
    consoleErrors.push('exception: ' + (d.exception?.description || d.text));
  }
};

await send('Page.enable');
await send('Runtime.enable');
await send('Log.enable');
await send('Network.enable');
// This is a design audit of the files on disk, so nothing may come from a cache: the service
// worker precaches every asset and would happily serve last night's build.
await send('Network.setCacheDisabled', { cacheDisabled: true });
// The app's own service worker would answer every request from its precache, hiding what is on the server.
await send('Network.setBypassServiceWorker', { bypass: true }).catch(() => {});

// The in-page probe: one pass over the rendered DOM, returns every finding.
const PROBE = `(() => {
  const px = (c) => {
    const m = /rgba?\\(([^)]+)\\)/.exec(c) || /oklab\\(([^)]+)\\)/.exec(c);
    if (!m) return null;
    const p = m[1].split(/[\\s,/]+/).filter(Boolean);
    if (/oklab/.test(c)) return null;
    const n = p.map((v, i) => i === 3 ? parseFloat(v) : (v.endsWith('%') ? parseFloat(v) / (i ? 1 : 2.55) : parseFloat(v)));
    return { r: n[0], g: n[1], b: n[2], a: n.length > 3 ? n[3] : 1 };
  };
  const over = (c, b) => c.a >= 1 ? c : { r: c.r * c.a + b.r * (1 - c.a), g: c.g * c.a + b.g * (1 - c.a), b: c.b * c.a + b.b * (1 - c.a), a: 1 };
  const lum = (c) => { const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.93 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b); };
  const ratio = (a, b) => { const l1 = lum(a), l2 = lum(b); return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05); };
  const hex = (c) => '#' + [c.r, c.g, c.b].map((v) => Math.round(v).toString(16).padStart(2, '0')).join('');
  const bgOf = (el) => {
    let out = [];
    for (let n = el; n; n = n.parentElement) {
      const c = px(getComputedStyle(n).backgroundColor);
      if (c && c.a > 0) { out.push(c); if (c.a >= 1) break; }
    }
    let acc = { r: 0, g: 0, b: 0, a: 1 };
    for (let i = out.length - 1; i >= 0; i--) acc = over(out[i], acc);
    return acc;
  };
  const shown = (el) => {
    const r = el.getBoundingClientRect();
    if (r.width < 1 || r.height < 1) return false;
    const s = getComputedStyle(el);
    if (s.display === 'none' || s.visibility === 'hidden' || Number(s.opacity) < 0.05) return false;
    if (r.bottom < 0 || r.top > innerHeight || r.right < 0 || r.left > innerWidth) return false;
    return true;
  };
  const root = getComputedStyle(document.documentElement);
  const tokens = {};
  for (const k of ['--track', '--brass', '--rose', '--plum', '--ink', '--porcelain', '--bg', '--sheet', '--text', '--muted']) {
    const v = root.getPropertyValue(k).trim();
    const m = /^#([0-9a-f]{6})$/i.exec(v);
    if (m) tokens[k.slice(2)] = { r: parseInt(m[1].slice(0, 2), 16), g: parseInt(m[1].slice(2, 4), 16), b: parseInt(m[1].slice(4, 6), 16), a: 1 };
  }
  const near = (c, t) => c && Math.abs(c.r - t.r) + Math.abs(c.g - t.g) + Math.abs(c.b - t.b) < 24;

  const findings = [];
  const accents = {};
  const seen = new Set();

  // 1. text contrast, per visible text run
  for (const el of document.querySelectorAll('body *')) {
    if (!el.parentElement || !shown(el)) continue;
    let text = '';
    for (const n of el.childNodes) if (n.nodeType === 3) text += n.nodeValue;
    text = text.trim();
    if (!text) continue;
    const s = getComputedStyle(el);
    if (Number(s.opacity) < 0.5 && !el.closest('[data-counting]')) { /* faded on purpose */ }
    const fg = over(px(s.color) || { r: 0, g: 0, b: 0, a: 1 }, bgOf(el));
    const bg = bgOf(el);
    const size = parseFloat(s.fontSize), weight = Number(s.fontWeight) || 400;
    const large = size >= 24 || (size >= 18.5 && weight >= 700);
    const min = large ? 3 : 4.5;
    const r = ratio(fg, bg);
    if (r < min) findings.push({ kind: 'contrast', worst: +r.toFixed(2), need: min, where: text.slice(0, 34), color: hex(fg), on: hex(bg), px: Math.round(size * 10) / 10, w: weight, sel: el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') + (el.className && typeof el.className === 'string' ? '.' + el.className.trim().split(/\\s+/).join('.') : '') });
    // 2. accent flood: saturated token used as text or fill
    for (const [name, tok] of Object.entries(tokens)) {
      if (!['track', 'brass', 'rose', 'plum'].includes(name)) continue;
      if (near(px(s.color), tok)) { accents[name] = (accents[name] || 0) + 1; (accents[name + '_ex'] = accents[name + '_ex'] || []).push(text.slice(0, 20)); }
      const fill = px(s.backgroundColor), stroke = px(s.borderTopColor);
      if (fill && fill.a > 0.3 && near(fill, tok)) { accents[name] = (accents[name] || 0) + 1; }
      else if (stroke && stroke.a > 0.3 && near(stroke, tok)) { accents[name] = (accents[name] || 0) + 1; }
    }
  }

  // 3. tap targets — measured against the real hit area: a control inside a <label> is tapped
  // through the label, so the label box is the target.
  const targets = [];
  for (const el of document.querySelectorAll('a[href],button,input,select,textarea,[role="button"],[tabindex]:not([tabindex="-1"])')) {
    if (!shown(el) || el.disabled) continue;
    const lab = el.matches('input,select,textarea') ? el.closest('label') : null;
    const hit = lab || el;
    const r = hit.getBoundingClientRect();
    const w = Math.round(r.width), h = Math.round(r.height);
    if (w >= 44 && h >= 44) continue;
    const label = (el.getAttribute('aria-label') || hit.textContent || el.type || '').trim().replace(/\\s+/g, ' ').slice(0, 26);
    targets.push({ label, w, h, aa_fail: w < 24 || h < 24, sel: el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') + (el.className && typeof el.className === 'string' ? '.' + el.className.trim().split(/\\s+/).slice(0, 2).join('.') : '') });
  }

  // 4. headings + landmarks + chart alternatives
  const heads = [...document.querySelectorAll('h1,h2,h3,h4')].map((h) => h.tagName + ' ' + h.textContent.trim().slice(0, 30));
  const skipped = heads.some((h, i) => i > 0 && Number(h[1]) - Number(heads[i - 1][1]) > 1);
  const svgNoAlt = [...document.querySelectorAll('svg')].filter((s) => {
    const r = s.getBoundingClientRect();
    return r.width > 60 && r.height > 60 && !s.getAttribute('aria-label') && !s.querySelector('title')
      && !s.closest('[aria-label]') && s.getAttribute('aria-hidden') !== 'true' && !s.closest('[aria-hidden="true"]');
  }).length;
  const zoomBlocked = /user-scalable\s*=\s*no|maximum-scale/i.test((document.querySelector('meta[name=viewport]') || {}).content || '');
  const imgsNoAlt = [...document.querySelectorAll('img')].filter((i) => i.getAttribute('alt') === null).length;

  // 5. focus styling killed anywhere?
  let outlineKilled = false, reducedMotion = 0;
  for (const sheet of document.styleSheets) {
    let rules; try { rules = sheet.cssRules; } catch { continue; }
    for (const rule of rules || []) {
      const t = rule.cssText || '';
      if (/outline\\s*:\\s*(none|0)/.test(t) || /outline-width\\s*:\\s*0/.test(t)) outlineKilled = true;
      if (rule.media && /prefers-reduced-motion/.test(rule.media.mediaText)) reducedMotion++;
      for (const inner of rule.cssRules || []) if (/prefers-reduced-motion/.test(inner.conditionText || '')) reducedMotion++;
    }
  }

  return JSON.stringify({
    findings, accents, targets, heads, skipped, svgNoAlt, imgsNoAlt, outlineKilled, reducedMotion, zoomBlocked,
    tokens: Object.fromEntries(Object.entries(tokens).map(([k, v]) => [k, hex(v)])),
    viewport: { w: innerWidth, h: innerHeight, dpr: devicePixelRatio },
    scroll: { client: document.querySelector('#view')?.scrollHeight, visible: innerHeight },
  });
})()`;

const report = {};
for (const scheme of SCHEMES) {
  for (const [i, spec] of ROUTES.entries()) {
    const [route, state] = spec.split('@');
    // A distinct query string per route forces a real document load. Changing only the hash would keep
    // the first document alive for the whole run, so every route after the first would measure one build.
    const url = `${BASE}/index.html?audit=${Date.now()}${i}#${route}`;
    consoleErrors = [];
    await send('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: 2, mobile: true });
    await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: scheme }] });
    await send('Page.navigate', { url });
    await sleep(2500);
    // The app's own service worker answers from its precache, which can be an older build than the server's.
    await evalJs(`(async () => {
      const rs = await navigator.serviceWorker.getRegistrations();
      await Promise.all(rs.map((r) => r.unregister()));
      if (window.caches) for (const k of await caches.keys()) await caches.delete(k);
      return rs.length;
    })()`, 'sw-clear');
    await evalJs(`import('${BASE}/tools/seed.js').then(m => m.seed(90))`, 'seed');
    await sleep(1200);
    await evalJs(`location.hash = ${JSON.stringify(route)}`, 'route');
    await sleep(1200);
    if (state) { await evalJs(STATES[state], state); await sleep(700); }
    const raw = await evalJs(PROBE, 'probe');
    const data = JSON.parse(raw);
    data.build = await evalJs(
      `fetch('sw.js?bust=' + Date.now()).then((r) => r.text()).then((t) => (t.match(/pushups-v-(\\d+)/) || [])[1] || 'none')`,
      'build');
    data.consoleErrors = consoleErrors.slice();
    report[`${scheme}:${spec}`] = data;
    if (SHOTS) {
      const shot = await send('Page.captureScreenshot', { format: 'png' });
      const file = `/tmp/audit_${scheme}${spec.replace(/[\/@]/g, '_')}.png`;
      writeFileSync(file, Buffer.from(shot.data, 'base64'));
    }
  }
}
await send('Emulation.clearDeviceMetricsOverride').catch(() => {});
ws.close();
chrome.kill();

writeFileSync('/tmp/pushups-audit.json', JSON.stringify(report, null, 2));

// ── human report ──
let fails = 0;
const SEV = (n) => n;
for (const [key, d] of Object.entries(report)) {
  const contrast = d.findings.filter((f) => f.kind === 'contrast');
  const worst = [...contrast].sort((a, b) => a.worst - b.worst).slice(0, 6);
  const aa = d.targets.filter((t) => t.aa_fail);
  const hig = d.targets.filter((t) => !t.aa_fail);
  const accentTotal = Object.entries(d.accents).filter(([k]) => !k.endsWith('_ex'));
  const issues = [];
  if (EXPECTED && d.build !== EXPECTED) issues.push(`build ${d.build} != ${EXPECTED}`);
  if (contrast.length) issues.push(`contrast ${contrast.length}`);
  if (aa.length) issues.push(`AA-target ${aa.length}`);
  if (hig.length) issues.push(`44pt-target ${hig.length}`);
  if (!d.heads.some((h) => h.startsWith('H1'))) issues.push('no-h1');
  if (d.skipped) issues.push('heading-skip');
  if (d.svgNoAlt) issues.push(`svg-no-alt ${d.svgNoAlt}`);
  if (d.outlineKilled) issues.push('outline-killed');
  if (!d.reducedMotion) issues.push('no-reduced-motion');
  if (d.zoomBlocked) issues.push('zoom-blocked');
  if (d.consoleErrors.length) issues.push(`console ${d.consoleErrors.length}`);
  fails += issues.length;
  console.log(`\n${key}${issues.length ? '   ✗ ' + issues.join('  ') : '   ✓ clean'}`);
  console.log(`   accents: ${accentTotal.map(([k, v]) => `${k}×${v}`).join(' ') || 'none'} · headings: ${d.heads.map((h) => h.split(' ')[0]).join('>') || 'none'}`);
  for (const f of worst) console.log(`   [contrast ${f.worst}/${f.need}] "${f.where}" ${f.color} on ${f.on} @${f.px}px/${f.w} — ${f.sel}`);
  const tally = (list) => {
    const m = new Map();
    for (const t of list) {
      const k = t.sel + ' ' + t.w + '×' + t.h;
      m.set(k, (m.get(k) || 0) + 1);
      if (!m.has(k + '|ex')) m.set(k + '|ex', t.label);
    }
    return [...m].filter(([k]) => !k.endsWith('|ex')).slice(0, 6)
      .map(([k, n]) => `   ${k} ×${n}  "${m.get(k + '|ex')}"`);
  };
  for (const line of tally(aa)) console.log('   [AA target]' + line);
  for (const line of tally(hig)) console.log('   [under 44pt]' + line);
  for (const e of d.consoleErrors.slice(0, 3)) console.log(`   [console] ${e}`);
}
console.log(`\n${fails ? 'FAIL' : 'PASS'} — ${fails} issue groups. Full data: /tmp/pushups-audit.json${SHOTS ? ' · shots /tmp/audit_*.png' : ''}`);
process.exit(0);
