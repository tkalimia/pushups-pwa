import { load, save, params, setParam, resetParams, PRESETS } from '../settings.js';
import { exportJSON, importJSON, countSets } from '../db.js';
import { download } from '../util.js';
import { platformInfo, persistentStatus, requestPersistent, tryBadging } from '../upgrade.js';

const SEL = (id, opts, val) => `<select id="${id}">` +
  opts.map(([v, l]) => `<option value="${v}"${v === val ? ' selected' : ''}>${l}</option>`).join('') + '</select>';

export default function settingsView(host) {
  const s = load();
  const p = params();

  host.innerHTML = `
    <div class="list">
      <div class="pad"><h2 class="h1" style="margin:14px 0 4px">Depth preset</h2>
        <p class="sub" style="margin:0 0 8px">Relaxed counts a shallower bend. Strict wants an almost straight arm at the top.</p>
        ${SEL('preset', [['relaxed', 'Relaxed'], ['standard', 'Standard'], ['strict', 'Strict']], s.preset)}
      </div>
      <div class="rule"></div>
      <div class="pad"><h2 class="h1" style="margin:0 0 8px">Thresholds</h2>
        <div class="field"><label for="top">Top (lockout) angle <b id="topOut"></b></label>
          <input type="range" id="top" min="120" max="178" step="1"></div>
        <div class="field"><label for="bottom">Bottom angle <b id="bottomOut"></b></label>
          <input type="range" id="bottom" min="70" max="130" step="1"></div>
        <div class="field"><label for="minRep">Minimum rep time <b id="minRepOut"></b></label>
          <input type="range" id="minRep" min="150" max="900" step="10"></div>
        <div class="row"><button class="btn btn-quiet" id="resetP">Back to preset</button>
          <span class="grow"></span><span class="sub" id="ovl"></span></div>
      </div>
      <div class="rule"></div>
      <div class="pad"><h2 class="h1" style="margin:0 0 6px">Counting</h2>
        <label class="tog"><span>Clean reps only<span class="sub">skip flagged reps in the count</span></span><input type="checkbox" id="cleanOnly"></label>
        <label class="tog"><span>Auto-start on plank<span class="sub">begin the countdown once the plank is held</span></span><input type="checkbox" id="autoArm"></label>
        <label class="tog"><span>End set after idle<span class="sub" id="idleLbl"></span></span>
          <input type="range" id="idle" min="5" max="60" step="1" style="width:120px"></label>
        <div class="field"><label for="armHold">Plank hold before counting <b id="armHoldOut"></b></label>
          <input type="range" id="armHold" min="800" max="6000" step="100"></div>
        <div class="field"><label for="secondary">Second signal (shoulder travel)</label>
          ${SEL('secondary', [['off', 'Off — elbow angle only'], ['assist', 'Assist — flag shallow reps'], ['confirm', 'Confirm — require both']], s.secondarySignal)}
        </div>
      </div>
      <div class="rule"></div>
      <div class="pad"><h2 class="h1" style="margin:0 0 6px">Feedback</h2>
        ${SEL('voice', [['every', 'Say every rep'], ['milestones', 'Say every fifth'], ['off', 'Silent']], s.voice)}
        <label class="tog"><span>Beeps</span><input type="checkbox" id="beeps"></label>
        <label class="tog"><span>Haptics<span class="sub" id="vibHint"></span></span><input type="checkbox" id="haptics"></label>
        <label class="tog"><span>Show skeleton during a set</span><input type="checkbox" id="skeletonOnSet"></label>
      </div>
      <div class="rule"></div>
      <div class="pad"><h2 class="h1" style="margin:0 0 6px">Camera and model</h2>
        ${SEL('camera', [['environment', 'Back camera (side view)'], ['user', 'Front camera']], s.camera)}
        <div class="spacer"></div>
        ${SEL('model', [['lite', 'Pose lite — fast, usually enough'], ['full', 'Pose full — better in bad light']], s.model)}
        <div class="spacer"></div>
        <div class="field"><label for="fps">Detection rate cap <b id="fpsOut"></b></label>
          <input type="range" id="fps" min="10" max="30" step="1"></div>
        <label class="tog"><span>Manual tap-to-log<span class="sub">no camera at all</span></span><input type="checkbox" id="manualMode"></label>
      </div>
      <div class="rule"></div>
      <div class="pad"><h2 class="h1" style="margin:0 0 6px">Data</h2>
        <div class="kv"><span>saved sets on this phone</span><b class="num" id="setCount">…</b></div>
        <div class="kv"><span>persistent storage</span><b id="persist">…</b></div>
        <div class="row" style="margin-top:10px">
          <button class="btn grow" id="exportBtn">Export JSON</button>
          <button class="btn grow" id="importBtn">Import</button>
        </div>
        <input type="file" id="importFile" accept="application/json,.json" hidden>
        <div class="sub" style="margin-top:8px" id="dataMsg"></div>
      </div>
      <div class="rule"></div>
      <div class="pad"><h2 class="h1" style="margin:0 0 6px">Diagnostics</h2>
        <div class="mono" id="plat" style="white-space:pre-wrap"></div>
        <div class="row" style="margin-top:10px">
          <a class="btn grow" href="#/debug">Counter lab</a>
          <button class="btn grow" id="badgeTest">Test icon badge</button>
        </div>
      </div>
      <div class="spacer"></div><div class="spacer"></div>
    </div>`;

  const q = (sel) => host.querySelector(sel);
  const num = (id) => q('#' + id + 'Out');
  const currentFor = (key) => {
    const cur = load();
    return key in cur.overrides ? cur.overrides[key] : PRESETS[cur.preset][key];
  };

  function bindRange(id, key, fmt) {
    const el = q('#' + id);
    const out = num(id);
    el.value = String(currentFor(key));
    out.textContent = fmt(Number(el.value));
    el.addEventListener('input', () => {
      out.textContent = fmt(Number(el.value));
      setParam(key, Number(el.value));
      renderOverrideNote();
    });
  }

  function renderOverrideNote() {
    const o = Object.keys(load().overrides);
    q('#ovl').textContent = o.length ? 'custom: ' + o.join(', ') : 'following preset';
  }

  q('#preset').addEventListener('change', (e) => {
    save({ preset: e.target.value, overrides: {} });
    syncAll();
  });
  q('#resetP').addEventListener('click', () => { resetParams(); syncAll(); });

  bindRange('top', 'top', (v) => v + '°');
  bindRange('bottom', 'bottom', (v) => v + '°');
  bindRange('minRep', 'minRepMs', (v) => v + ' ms');

  const toggles = {
    cleanOnly: 'cleanOnly', autoArm: 'autoArm', beeps: 'beeps', haptics: 'haptics',
    skeletonOnSet: 'skeletonOnSet', manualMode: 'manualMode',
  };
  Object.entries(toggles).forEach(([id, key]) => {
    const el = q('#' + id);
    el.checked = !!s[key];
    el.addEventListener('change', () => save({ [key]: el.checked }));
  });
  ['voice', 'camera', 'model', 'secondarySignal'].forEach((key) => {
    const el = q('#' + (key === 'secondarySignal' ? 'secondary' : key));
    el.value = s[key];
    el.addEventListener('change', () => save({ [key]: el.value }));
  });

  q('#idle').value = String(s.endAfterIdleSec);
  q('#idleLbl').textContent = 'auto-end after ' + s.endAfterIdleSec + ' s without a rep';
  q('#idle').addEventListener('input', (e) => {
    save({ endAfterIdleSec: Number(e.target.value) });
    q('#idleLbl').textContent = 'auto-end after ' + e.target.value + ' s without a rep';
  });

  q('#armHold').value = String(s.armHoldMs);
  q('#armHoldOut').textContent = (s.armHoldMs / 1000).toFixed(1) + ' s';
  q('#armHold').addEventListener('input', (e) => {
    save({ armHoldMs: Number(e.target.value) });
    q('#armHoldOut').textContent = (Number(e.target.value) / 1000).toFixed(1) + ' s';
  });

  q('#fps').value = String(s.fpsCap);
  q('#fpsOut').textContent = s.fpsCap + ' fps';
  q('#fps').addEventListener('input', (e) => {
    save({ fpsCap: Number(e.target.value) });
    q('#fpsOut').textContent = e.target.value + ' fps';
  });

  q('#vibHint').textContent = navigator.vibrate ? 'supported here' : 'not exposed by iOS Safari';

  function syncAll() {
    const cur = load();
    const cp = params();
    q('#preset').value = cur.preset;
    q('#top').value = String(cp.top); num('top').textContent = cp.top + '°';
    q('#bottom').value = String(cp.bottom); num('bottom').textContent = cp.bottom + '°';
    q('#minRep').value = String(cp.minRepMs); num('minRep').textContent = cp.minRepMs + ' ms';
    renderOverrideNote();
  }
  syncAll();

  countSets().then((n) => { q('#setCount').textContent = String(n); }).catch(() => { q('#setCount').textContent = '?'; });
  persistentStatus().then(async (ok) => {
    q('#persist').textContent = ok ? 'granted' : 'not granted';
    if (!ok) {
      q('#persist').addEventListener('click', async () => {
        const g = await requestPersistent();
        q('#persist').textContent = g ? 'granted' : 'denied';
      });
    }
  });
  q('#persist').style.cursor = 'pointer';

  const info = platformInfo();
  q('#plat').textContent = Object.entries(info).map(([k, v]) => k.padEnd(12) + (v ? 'yes' : 'no')).join('\n');

  q('#exportBtn').addEventListener('click', async () => {
    const text = await exportJSON();
    download('pushups-backup-' + new Date().toISOString().slice(0, 10) + '.json', text);
    q('#dataMsg').textContent = 'Downloaded. Keep one copy in Files or iCloud Drive.';
  });
  q('#importBtn').addEventListener('click', () => q('#importFile').click());
  q('#importFile').addEventListener('change', async (e) => {
    const file = e.target.files && e.target.files[0];
    if (!file) return;
    const text = await file.text();
    if (!confirm('Merge sets from ' + file.name + ' into this phone?')) return;
    const res = await importJSON(text);
    q('#dataMsg').textContent = res.ok ? 'Imported ' + res.added + ' sets.' : 'Import failed: ' + res.error;
    if (res.ok) countSets().then((n) => { q('#setCount').textContent = String(n); });
  });
  q('#badgeTest').addEventListener('click', () => {
    const ok = tryBadging(7);
    q('#plat').textContent += '\nbadging: ' + (ok ? 'shown on the icon' : 'not supported in this browser');
  });

  return {};
}
