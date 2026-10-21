import { load, save, params, setParam, resetParams } from '../settings.js';
import { Counter } from '../counter.js';
import { createTracker } from '../pose.js';
import { listSets } from '../db.js';
import { download, pct } from '../util.js';

export default function debugView(host) {
  const counter = new Counter(params());
  let tracker = null;
  let repLog = [];
  let frames = 0;
  let replaying = false;
  let lastT = 0;

  // replay must follow the video clock, and it must never go backwards when the clip loops
  function nowMs(f) {
    if (!replaying) return Date.now();
    let t = Math.round(f.stampMs != null ? f.stampMs : video.currentTime * 1000);
    if (t <= lastT) t = lastT + 33;
    lastT = t;
    return t;
  }

  host.innerHTML = `
    <div class="dbg">
      <div class="row"><a class="btn btn-quiet" href="#/train">← train</a>
        <span class="grow"></span><span id="mode">idle</span></div>

      <h3>live</h3>
      <table>
        <tr><th>state</th><td id="o-state">–</td></tr>
        <tr><th>armed</th><td id="o-armed">–</td></tr>
        <tr><th>side</th><td id="o-side">–</td></tr>
        <tr><th>elbow L / R</th><td id="o-elbow">–</td></tr>
        <tr><th>shoulder L / R</th><td id="o-shoulder">–</td></tr>
        <tr><th>hip offset</th><td id="o-hip">–</td></tr>
        <tr><th>body angle</th><td id="o-body">–</td></tr>
        <tr><th>plank reasons</th><td id="o-reasons">–</td></tr>
        <tr><th>quality / fps</th><td id="o-q">–</td></tr>
        <tr><th>reps det / clean</th><td id="o-reps">–</td></tr>
        <tr><th>frames</th><td id="o-frames">0</td></tr>
      </table>

      <h3>thresholds</h3>
      <div class="field"><label>top <b id="v-top"></b></label><input type="range" id="r-top" min="120" max="178"></div>
      <div class="field"><label>bottom <b id="v-bottom"></b></label><input type="range" id="r-bottom" min="70" max="130"></div>
      <div class="field"><label>min rep ms <b id="v-minRep"></b></label><input type="range" id="r-minRep" min="150" max="900" step="10"></div>
      <div class="field"><label>arm hold ms <b id="v-arm"></b></label><input type="range" id="r-arm" min="800" max="6000" step="100"></div>
      <div class="row"><button class="btn btn-quiet" id="b-reset">reset overrides</button>
        <span class="grow"></span><span id="ovl"></span></div>

      <h3>replay a recording instead of the camera</h3>
      <input type="file" id="f-file" accept="video/*">
      <video id="f-video" playsinline muted loop style="width:100%;margin-top:8px;background:#000"></video>
      <div class="row" style="margin-top:8px">
        <button class="btn btn-quiet" id="f-play">play</button>
        <button class="btn btn-quiet" id="f-stop">stop</button>
        <button class="btn btn-quiet" id="f-live">use camera</button>
        <span class="grow"></span>
        <button class="btn btn-quiet" id="f-clear">clear reps</button>
      </div>

      <h3>detected reps</h3>
      <table id="t-reps"><tr><th>#</th><th>t</th><th>min</th><th>max</th><th>drop</th><th>hip</th><th>flags</th></tr></table>

      <h3>detected vs corrected, all sets</h3>
      <div class="row" style="margin:6px 0">
        <button class="btn btn-quiet" id="b-export">export counter-lab json</button>
        <button class="btn btn-quiet" id="b-diff">show disagreement</button>
      </div>
      <table id="t-sets"><tr><th>date</th><th>det</th><th>fin</th><th>Δ</th><th>preset</th></tr></table>
      <div id="diffSum" class="st"></div>
    </div>`;

  const q = (s) => host.querySelector(s);
  const video = q('#f-video');

  const sliders = [
    ['top', 'top', '°'], ['bottom', 'bottom', '°'], ['minRepMs', 'minRep', ' ms'],
  ];
  function syncSliders() {
    const cur = load();
    const p = params();
    sliders.forEach(([key, id, unit]) => {
      q('#r-' + id).value = String(p[key]);
      q('#v-' + id).textContent = p[key] + unit;
    });
    q('#r-arm').value = String(cur.armHoldMs);
    q('#v-arm').textContent = cur.armHoldMs + ' ms';
    const o = Object.keys(cur.overrides);
    q('#ovl').textContent = o.length ? 'custom: ' + o.join(', ') : 'preset: ' + cur.preset;
  }
  sliders.forEach(([key, id]) => {
    q('#r-' + id).addEventListener('input', (e) => {
      setParam(key, Number(e.target.value));
      counter.setParams(params());
      syncSliders();
    });
  });
  q('#r-arm').addEventListener('input', (e) => {
    save({ armHoldMs: Number(e.target.value) });
    counter.setArmHold(Number(e.target.value));
    syncSliders();
  });
  q('#b-reset').addEventListener('click', () => { resetParams(); counter.setParams(params()); syncSliders(); });
  syncSliders();

  function onFrame(f) {
    frames += 1;
    const out = counter.addFrame(nowMs(f), f);
    paint(out, f);
    (out.events || []).forEach((ev) => {
      if (ev.type === 'rep') {
        repLog.push(ev.data && (ev.data.rep || ev.data));
        paintReps();
      }
    });
    q('#o-frames').textContent = String(frames);
  }

  function paint(out, f) {
    if (!out) return;
    q('#o-state').textContent = out.state;
    q('#o-armed').textContent = out.armed ? 'yes ' + Math.round((out.armMs || 0)) + 'ms' : 'no';
    q('#o-side').textContent = out.side || '–';
    const a = out.angles || {};
    const fmtA = (s) => {
      const v = a[s] && a[s].elbow;
      return v == null ? '–' : Math.round(v);
    };
    const fmtS = (s) => {
      const v = a[s] && a[s].shoulder;
      return v == null ? '–' : Math.round(v);
    };
    q('#o-elbow').textContent = fmtA('left') + ' / ' + fmtA('right');
    q('#o-shoulder').textContent = fmtS('left') + ' / ' + fmtS('right');
    q('#o-hip').textContent = out.hipOffset == null ? '–' : out.hipOffset.toFixed(3);
    q('#o-body').textContent = out.bodyAngle == null ? '–' : out.bodyAngle.toFixed(1) + '°';
    q('#o-reasons').textContent = (out.plank && out.plank.reasons || []).join(', ') || 'none';
    q('#o-q').textContent = pct(out.quality) + ' / ' + Math.round(f.fps || 0);
    q('#o-reps').textContent = out.repsDetected + ' / ' + out.cleanReps;
  }

  function paintReps() {
    const t = q('#t-reps');
    t.querySelectorAll('tr:not(:first-child)').forEach((r) => r.remove());
    repLog.slice(-40).forEach((r) => {
      const tr = document.createElement('tr');
      [r.n, Math.round((r.tEnd - r.tStart) / 10) / 100 + 's', Math.round(r.minElbow || 0) + '°',
        Math.round(r.maxElbow || 0) + '°', (r.shoulderDrop || 0).toFixed(2),
        (r.hipMin > 0.18 ? 'sag' : r.hipMax < -0.14 ? 'pike' : '–'), (r.flags || []).join(' ') || 'clean']
        .forEach((v) => {
          const td = document.createElement('td');
          td.textContent = String(v);
          tr.append(td);
        });
      t.append(tr);
    });
  }

  async function attachTracker(target) {
    if (tracker && tracker.dispose) tracker.dispose();
    repLog = [];
    frames = 0;
    counter.reset('debug');
    paintReps();
    tracker = await createTracker({
      video: target,
      model: load().model,
      fpsCap: load().fpsCap,
      onStatus: (k, d) => { q('#mode').textContent = 'engine · ' + k + (d ? ' ' + d : ''); },
      onFrame: (f) => { try { onFrame(f); } catch (e) { console.error(e); q('#mode').textContent = 'error ' + e.message; } },
      onError: (e) => { q('#mode').textContent = 'error: ' + e.message; },
    });
    tracker.start();
  }

  q('#f-file').addEventListener('change', (e) => {
    const file = e.target.files && e.target.files[0];
    if (!file) return;
    video.src = URL.createObjectURL(file);
    video.loop = true;
    q('#mode').textContent = 'loaded ' + file.name;
    video.addEventListener('loadeddata', () => {
      video.currentTime = 0;
      replaying = true;
      attachTracker(video);
      video.play();
      q('#mode').textContent = 'replaying ' + file.name;
    }, { once: true });
  });
  q('#f-play').addEventListener('click', () => {
    if (!video.src) return;
    if (tracker) tracker.start();
    video.play();
  });
  q('#f-stop').addEventListener('click', () => { if (tracker) tracker.stop(); video.pause(); });
  q('#f-clear').addEventListener('click', () => { counter.reset('debug'); repLog = []; frames = 0; paintReps(); });
  q('#f-live').addEventListener('click', async () => {
    video.pause();
    if (tracker) { tracker.dispose && tracker.dispose(); tracker = null; }
    const { openCamera } = await import('../camera.js');
    const cam = await openCamera(video, { facing: load().camera });
    replaying = false;
    attachTracker(video);
    q('#mode').textContent = 'camera · ' + (cam.settings.facing || load().camera);
  });

  q('#b-diff').addEventListener('click', async () => {
    const sets = await listSets();
    const t = q('#t-sets');
    t.querySelectorAll('tr:not(:first-child)').forEach((r) => r.remove());
    let det = 0;
    let fin = 0;
    let off = 0;
    sets.slice(-60).forEach((s) => {
      const d = (s.repsFinal || 0) - (s.repsDetected || 0);
      det += s.repsDetected || 0;
      fin += s.repsFinal || 0;
      if (d !== 0) off += 1;
      const tr = document.createElement('tr');
      [new Date(s.startedAt).toLocaleDateString(), s.repsDetected, s.repsFinal,
        (d > 0 ? '+' : '') + d, s.presetName].forEach((v) => {
        const td = document.createElement('td');
        td.textContent = String(v);
        tr.append(td);
      });
      t.append(tr);
    });
    q('#diffSum').textContent = sets.length + ' sets · camera ' + det + ' · kept ' + fin +
      ' · ' + off + ' sets disagreed (' + (sets.length ? Math.round((off / sets.length) * 100) : 0) + '%)';
  });

  q('#b-export').addEventListener('click', async () => {
    const sets = await listSets();
    download('counter-lab-' + Date.now() + '.json', JSON.stringify({
      at: new Date().toISOString(), params: params(), settings: load(),
      repLog, sets: sets.map((s) => ({
        day: s.day, det: s.repsDetected, fin: s.repsFinal, flags: s.flags,
        quality: s.qualityStats, preset: s.presetName, paramsUsed: s.paramsUsed,
      })),
    }, null, 2));
  });

  return {
    unmount() {
      if (tracker) { tracker.stop && tracker.stop(); tracker.dispose && tracker.dispose(); }
      video.pause();
    },
  };
}
