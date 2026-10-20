import { load, save, params } from '../settings.js';
import { openCamera, closeCamera, resumePreview, describeCameraError, cameraSupports } from '../camera.js';
import { createTracker } from '../pose.js';
import { Counter } from '../counter.js';
import { saveSet, listSetsForDay } from '../db.js';
import { unlockAudio, speak, playBeep, playWarning, vibrate, announceRep, countdownVoice } from '../feedback.js';
import { requestWakeLock, tryBadging } from '../upgrade.js';
import { today, dayOf, fmtClock, fmtInt, clamp, pct, h } from '../util.js';

const LM = { HEAD: 0, SHOULDER: 11, ELBOW: 13, WRIST: 15, HIP: 23, ANKLE: 27 };
const EMPTY_OUT = {
  quality: 0, armed: false, armMs: 0, side: null, repsDetected: 0, cleanReps: 0, state: 'idle',
  plank: { valid: false, reasons: ['noPose'] }, angles: {}, hipOffset: null, bodyAngle: null,
  events: [], lastRep: null,
};

export default function train(host) {
  const st = load();
  const counter = new Counter(params());
  counter.setArmHold(st.armHoldMs);

  let phase = 'setup';
  let cam = null;
  let tracker = null;
  let mirror = st.camera === 'user';
  let setStart = 0;
  let lastFrameAt = 0;
  let lastRepAt = 0;
  let manualAdj = 0;
  let reps = [];
  let armBreaks = 0;
  let qualityLog = [];
  let fpsSamples = [];
  let lostSince = 0;
  let lostShown = false;
  let tickTimer = null;
  let cdTimer = null;
  let plankSince = 0;
  let lastOut = EMPTY_OUT;
  let summary = null;
  let dayBase = 0;
  let lightLevel = 120;

  const els = {};
  const CHECKS = [
    ['body', 'Full body in frame', 'head, hips and ankles visible'],
    ['vis', 'Landmarks visible', 'tracking above 50%'],
    ['plank', 'Plank detected', 'shoulder–hip–ankle in one line'],
    ['light', 'Lighting', 'you are not a silhouette'],
  ];
  const checkState = { body: false, vis: false, plank: false, light: false };
  const checkWhy = {};
  let poseSeen = false;

  host.innerHTML = `
    <div class="counter" data-phase="setup">
      <div class="topline">
        <span id="clock" class="clock">--:--</span>
        <h1 id="phaseLabel">set up</h1>
        <span class="endslot"><button class="btn btn-warn" id="endBtn" hidden>End</button></span>
      </div>
      <div class="hairline" id="hairline"></div>
      <div class="warnbox" id="warnbox" hidden></div>
      <div class="camwrap" id="camwrap">
        <video id="video" autoplay playsinline muted></video>
        <canvas id="overlay"></canvas>
        <div class="camoff" id="camoff" hidden></div>
        <div class="pill" id="pill"><i></i><span id="pillText">starting</span></div>
      </div>
      <div class="stage" id="stage"></div>
    </div>`;

  const q = (s) => host.querySelector(s);
  els.video = q('#video');
  els.overlay = q('#overlay');
  els.root = q('.counter');
  els.camwrap = q('#camwrap');
  els.camoff = q('#camoff');
  els.stage = q('#stage');
  els.pill = q('#pill');
  els.pillText = q('#pillText');
  els.warnbox = q('#warnbox');
  els.hairline = q('#hairline');
  els.clock = q('#clock');
  els.phaseLabel = q('#phaseLabel');
  els.endBtn = q('#endBtn');
  els.endBtn.addEventListener('click', () => endSet('button'));
  // Bound once: the stage keeps its listeners across every phase's innerHTML swap.
  els.stage.addEventListener('click', (e) => {
    if (phase !== 'set' || !load().manualMode) return;
    // The tap that opened the set bubbles through here too — it is not a rep.
    if (e.target.closest('#startBtn')) return;
    manualTap();
  });

  // ── luminance proxy for the lighting check ────────────────────
  const lumCanvas = document.createElement('canvas');
  lumCanvas.width = 32;
  lumCanvas.height = 24;
  const lumCtx = lumCanvas.getContext('2d', { willReadFrequently: true });
  let lumAt = 0;
  function measureLight() {
    const now = Date.now();
    if (now - lumAt < 800 || load().manualMode || els.video.videoWidth < 2) return;
    lumAt = now;
    try {
      lumCtx.drawImage(els.video, 0, 0, 32, 24);
      const d = lumCtx.getImageData(0, 0, 32, 24).data;
      let sum = 0;
      for (let i = 0; i < d.length; i += 4) sum += 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
      lightLevel = sum / (d.length / 4);
    } catch { lightLevel = 120; }
  }

  // ── setup ─────────────────────────────────────────────────────
  function setPhase(p) {
    phase = p;
    els.root.dataset.phase = p;
    /* Mid-set there is nothing else to navigate to, and the tab bar sits one thumb-slide from the
       End button. It goes away and the number takes the whole screen. */
    document.body.classList.toggle('in-set', p === 'set' || p === 'countdown');
  }

  function renderSetup() {
    setPhase('setup');
    els.overlay.style.display = '';
    lastOut = EMPTY_OUT;
    const manual = load().manualMode;
    els.phaseLabel.textContent = manual ? 'manual log' : 'set up';
    els.endBtn.hidden = true;
    els.camoff.hidden = true;
    clearWarn();
    /* Manual mode never opens the camera, so the readiness bar, the fps readout, the four framing
       checks, the depth preset and the flip button all describe a sensor that is switched off.
       Showing them at zero is a screen of instrumentation about nothing. */
    els.stage.innerHTML = `
      <div class="list${manual ? ' setuplist' : ''}">
        ${manual ? `
        <div class="setupbody">
          <div class="pad"><div class="setupnote">No camera. Tap <b>Start set</b>, then tap anywhere
            once per rep — the count is exactly what you tap.</div></div>
          <div id="manualCtx"></div>
          <div class="pad">
            <label class="tog" style="border-bottom:0"><span>Manual tap-to-log<span class="sub">no camera, count with your thumb</span></span>
              <input type="checkbox" id="manualChk"></label>
          </div>
        </div>` : `
        <div class="statusbar">
          <span class="bar grow"><i id="qbar"></i></span>
          <span class="mono" id="qtxt">0%</span>
          <span class="mono" id="fpstxt">0 fps</span>
        </div>
        <div class="pad"><div id="checks"></div></div>
        <div class="pad">
          <div class="rule"></div>
          <div class="row">
            <button class="btn btn-quiet" id="flipBtn">Use front camera</button>
            <span class="grow"></span>
            <select id="presetSel" style="width:auto">
              <option value="relaxed">Relaxed depth</option>
              <option value="standard">Standard depth</option>
              <option value="strict">Strict depth</option>
            </select>
          </div>
          <label class="tog" style="border-bottom:0"><span>Manual tap-to-log<span class="sub">skip the camera entirely</span></span>
            <input type="checkbox" id="manualChk"></label>
        </div>`}
      </div>
      <div class="cta">
        <button class="btn btn-primary btn-big" id="startBtn">Start set</button>
        <div class="sub" id="hint"></div>
      </div>`;
    els.qbar = q('#qbar');
    els.qtxt = q('#qtxt');
    els.fpstxt = q('#fpstxt');
    els.checks = q('#checks');
    els.camwrap.style.display = manual ? 'none' : '';
    q('#manualChk').checked = manual;
    q('#manualChk').addEventListener('change', (e) => {
      save({ manualMode: e.target.checked });
      els.camwrap.style.display = e.target.checked ? 'none' : '';
      if (e.target.checked) { closeCamera(cam); cam = null; els.pillText.textContent = 'manual'; }
      else if (!cam) startCamera(load().camera);
      renderSetup();
    });
    els.presetSel = q('#presetSel');
    if (els.presetSel) {
      els.presetSel.value = load().preset;
      els.presetSel.addEventListener('change', (e) => {
        save({ preset: e.target.value, overrides: {} });
        counter.setParams(params());
      });
      q('#flipBtn').addEventListener('click', () => {
        const next = load().camera === 'environment' ? 'user' : 'environment';
        save({ camera: next });
        startCamera(next);
      });
    }
    q('#startBtn').addEventListener('click', beginSet);
    q('#hint').textContent = manual
      ? 'Every tap on the screen is one rep. − and + fix a mis-tap.'
      : load().autoArm
        ? 'Auto-start is on: hold a steady plank and the countdown begins.'
        : 'Set the phone on the floor 1.5–2.5 m away, side-on. Tap Start set, then get into position.';
    paintChecks();
    if (manual) paintManualCtx();
  }

  /** What today already holds — without this the manual setup screen is an empty page with a button. */
  function paintManualCtx() {
    const box = q('#manualCtx');
    if (!box) return;
    listSetsForDay(today()).then((list) => {
      const sets = Array.isArray(list) ? list : [];
      const reps = sets.reduce((a, s) => a + (Number(s.repsFinal) || 0), 0);
      box.replaceChildren(h('div', { class: 'ctxhead' }, sets.length
        ? 'today · ' + sets.length + ' sets · ' + fmtInt(reps) + ' reps'
        : 'nothing logged today yet'));
      for (const s of sets.slice(-3).reverse()) {
        box.append(h('div', { class: 'ctxrow' },
          h('b', { class: 'ctxnum num' }, fmtInt(Number(s.repsFinal) || 0)),
          h('span', { class: 'ctxmeta' }, fmtClock(s.startedAt || 0)
            + ' · ' + ((s.source === 'manual' || s.mode === 'manual') ? 'manual' : 'camera'))));
      }
    }).catch(() => { box.replaceChildren(); });
  }

  const SVGNS = 'http://www.w3.org/2000/svg';
  function markIcon(state) {
    const mk = (tag, a) => {
      const e = document.createElementNS(SVGNS, tag);
      for (const k of Object.keys(a)) e.setAttribute(k, a[k]);
      return e;
    };
    const el = mk('svg', {
      viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', 'stroke-width': '1.8',
      'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'aria-hidden': 'true',
    });
    el.append(mk('circle', { cx: '12', cy: '12', r: '8.6' }));
    if (state === 'ok') el.append(mk('path', { d: 'M8.3 12.3l2.6 2.6 4.9-5.5' }));
    if (state === 'bad') el.append(mk('path', { d: 'M12 7.6v5.2' }), mk('path', { d: 'M12 16.2h.01' }));
    return el;
  }

  // Three states, not two: a gate you have not reached yet is not an error. Everything stays grey
  // until the camera is live AND has actually seen a body — then a failed gate goes rose.
  function paintChecks() {
    if (!els.checks) return;
    const judgeable = !!cam && poseSeen;
    els.checks.replaceChildren(...CHECKS.map(([k, label, hint]) => {
      const state = checkState[k] ? 'ok' : judgeable ? 'bad' : 'wait';
      const row = document.createElement('div');
      row.className = 'chk ' + state;
      const mk = document.createElement('span');
      mk.className = 'mk';
      mk.append(markIcon(state));
      const t = document.createElement('span');
      t.className = 't';
      t.textContent = label;
      const why = document.createElement('span');
      why.className = 'why';
      why.textContent = state === 'ok' ? '' : state === 'wait' ? 'not framed yet' : (checkWhy[k] || hint);
      row.append(mk, t, why);
      return row;
    }));
  }

  function reasonText(r) {
    return ({
      noPose: 'nothing detected yet',
      lowVis: 'too few landmarks',
      notSide: 'needs a side view',
      bodyAngle: 'body not level',
      hip: 'hips off the line',
    })[r] || r;
  }

  function evaluateChecks(f) {
    poseSeen = !!(f && f.present);
    if (!f || !f.present) {
      checkState.body = checkState.vis = checkState.plank = false;
      checkWhy.body = 'no pose yet';
      paintChecks();
      return;
    }
    const lm = f.landmarks;
    const inFrame = (p) => p.x > 0.02 && p.x < 0.98 && p.y > 0.02 && p.y < 0.98;
    checkState.body = inFrame(lm[LM.HEAD]) && inFrame(lm[LM.HIP]) && inFrame(lm[LM.ANKLE]);
    checkWhy.body = 'head, hips and ankles visible';
    checkState.vis = f.quality > 0.5;
    checkWhy.vis = pct(f.quality) + ' visible';
    const out = lastOut;
    checkState.plank = !!(out.plank && out.plank.valid);
    checkWhy.plank = out.plank && out.plank.reasons.length ? reasonText(out.plank.reasons[0]) : '';
    checkState.light = lightLevel > 26 && lightLevel < 236;
    checkWhy.light = lightLevel <= 26 ? 'too dark' : lightLevel >= 236 ? 'backlit' : '';
    paintChecks();
  }

  // ── lifecycle ─────────────────────────────────────────────────
  function beginSet() {
    unlockAudio();
    requestWakeLock('set-start');
    if (load().manualMode) return startManualSet();
    startCountdown(5);
  }

  function startCountdown(n) {
    setPhase('countdown');
    els.phaseLabel.textContent = 'into plank';
    let left = n;
    els.stage.innerHTML = `
      <div id="cdnum" class="num" style="font-size:min(70vw,38vh,320px);color:var(--brass)"></div>
      <div id="chip">counting starts after the countdown</div>`;
    const num = q('#cdnum');
    num.textContent = String(left);
    speak(countdownVoice(left));
    playBeep({ freq: 620, ms: 55, gain: 0.04 });
    els.endBtn.hidden = false;
    els.endBtn.textContent = 'Cancel';
    cdTimer = setInterval(() => {
      left -= 1;
      if (left <= 0) {
        clearInterval(cdTimer);
        cdTimer = null;
        num.textContent = 'go';
        speak('go');
        playBeep({ freq: 880, ms: 90, gain: 0.05 });
        setTimeout(startSet, 200);
      } else {
        num.textContent = String(left);
        speak(countdownVoice(left));
        playBeep({ freq: 620, ms: 55, gain: 0.04 });
      }
    }, 1000);
  }

  function startSet() {
    setPhase('set');
    counter.reset('set-start');
    counter.setParams(params());
    counter.setArmHold(load().armHoldMs);
    lastOut = EMPTY_OUT;
    setStart = Date.now();
    lastRepAt = setStart;
    manualAdj = 0;
    reps = [];
    armBreaks = 0;
    qualityLog = [];
    fpsSamples = [];
    lostSince = 0;
    clearWarn();
    els.endBtn.hidden = false;
    els.endBtn.textContent = 'End';
    els.phaseLabel.textContent = 'counting';
    renderCountFace();
    readDayBase();
    tickTimer = setInterval(tick, 250);
  }

  /* One face for both counting modes — the camera set and the tap set differ only in the chip. */
  const COUNT_FACE = `
      <div id="repnum" class="num">0</div>
      <div id="chip"></div>
      <div class="corr">
        <button class="step" id="minus" aria-label="one fewer">−</button>
        <span class="n" id="adj"></span>
        <button class="step" id="plus" aria-label="one more">+</button>
      </div>
      <div id="dayline" class="dayline"></div>`;

  function bindCountFace(chipText) {
    els.stage.innerHTML = COUNT_FACE;
    els.repnum = q('#repnum');
    els.chip = q('#chip');
    els.adj = q('#adj');
    els.dayline = q('#dayline');
    els.chip.textContent = chipText;
    q('#minus').addEventListener('click', (e) => { e.stopPropagation(); correct(-1); });
    q('#plus').addEventListener('click', (e) => { e.stopPropagation(); correct(1); });
  }

  /** The day total this set is being added to, so the count screen answers "how many today". */
  function readDayBase() {
    dayBase = 0;
    listSetsForDay(today()).then((list) => {
      dayBase = (list || []).reduce((a, s) => a + (Number(s.repsFinal) || 0), 0);
      paintCount();
    }).catch(() => { if (els.dayline) els.dayline.textContent = ''; });
  }

  function renderCountFace() {
    els.overlay.style.display = load().skeletonOnSet ? '' : 'none';
    bindCountFace('get into plank');
    paintCount();
  }

  function correct(d) {
    manualAdj += d;
    playBeep({ freq: d > 0 ? 720 : 460, ms: 45, gain: 0.04 });
    paintCount();
  }

  function detected() { return load().manualMode ? reps.length : lastOut.repsDetected; }

  function paintCount() {
    if (!els.repnum || phase !== 'set') return;
    const n = Math.max(0, detected() + manualAdj);
    els.repnum.style.setProperty('--nd', String(n).length);
    if (els.repnum.textContent !== String(n)) {
      els.repnum.textContent = String(n);
      els.repnum.classList.add('tick');
      setTimeout(() => els.repnum && els.repnum.classList.remove('tick'), 170);
    }
    if (els.adj) els.adj.textContent = manualAdj === 0 ? '' : (manualAdj > 0 ? '+' + manualAdj : String(manualAdj));
    if (els.dayline) els.dayline.textContent = 'today ' + fmtInt(dayBase + n);
    if (els.chip && !load().manualMode) {
      const flagged = lastOut.repsDetected - lastOut.cleanReps;
      els.chip.textContent = lastOut.armed
        ? lastOut.cleanReps + ' clean' + (flagged > 0 ? ' · ' + flagged + ' flagged' : '')
        : 'get into plank' + (lastOut.armMs > 200 ? ' (' + Math.round(lastOut.armMs / 1000) + 's)' : '');
    }
  }

  function startManualSet() {
    setPhase('set');
    setStart = Date.now();
    lastRepAt = setStart;
    manualAdj = 0;
    reps = [];
    els.endBtn.hidden = false;
    els.endBtn.textContent = 'End';
    els.phaseLabel.textContent = 'manual log';
    bindCountFace('tap here to log a rep');
    tickTimer = setInterval(tick, 500);
    readDayBase();
    paintCount();
  }

  function manualTap() {
    const t = Date.now() - setStart;
    const prev = reps.length ? reps[reps.length - 1].tMs : 0;
    reps.push({ n: reps.length + 1, tMs: t, durationMs: Math.max(0, t - prev), flags: [], manual: true });
    lastRepAt = Date.now();
    announceRep(reps.length, { mode: load().voice, beeps: load().beeps, haptics: load().haptics });
    paintCount();
  }

  function endSet(reason) {
    if (phase === 'summary') return;
    if (cdTimer) { clearInterval(cdTimer); cdTimer = null; }
    if (tickTimer) { clearInterval(tickTimer); tickTimer = null; }
    if (phase === 'countdown') { renderSetup(); return; }
    if (phase !== 'set') return;
    setPhase('summary');
    els.endBtn.hidden = true;
    const det = detected();
    const fin = Math.max(0, det + manualAdj);
    summary = {
      detected: det,
      final: fin,
      manualAdj,
      durationMs: Date.now() - setStart,
      reps: reps.slice(),
      flags: tally(reps),
      quality: qualityStats(),
      reason: reason || 'button',
      startedAt: setStart,
    };
    renderSummary();
  }

  function tally(list) {
    const t = { sag: 0, pike: 0, half: 0, lockout: 0, lost: 0, other: 0 };
    list.forEach((r) => (r.flags || []).forEach((f) => {
      if (f in t) t[f] += 1; else t.other += 1;
    }));
    if (list.some((r) => r.slow)) t.other += list.filter((r) => r.slow).length;
    return t;
  }

  function qualityStats() {
    const mean = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0);
    return {
      fpsMean: Math.round(mean(fpsSamples)),
      visMean: mean(qualityLog),
      frames: qualityLog.length,
      breaks: armBreaks,
    };
  }

  // ── summary ───────────────────────────────────────────────────
  function renderSummary() {
    const d = summary;
    const manual = load().manualMode;
    els.phaseLabel.textContent = 'summary';
    /* Manual sets have no camera, so "detected" is just the tap count and the tracking row would
       report the quality of a sensor that never ran. */
    els.stage.innerHTML = `
      <div class="sheet">
        <div class="finum"><input id="finalIn" type="number" inputmode="numeric" min="0" max="999"></div>
        <div class="sub" style="text-align:center;margin-top:-4px">${manual
    ? 'reps — fix it if you double-tapped'
    : 'final reps — correct it if the camera missed one'}</div>
        <div class="row" style="justify-content:center;margin:10px 0">
          <button class="step" id="sminus" aria-label="one fewer">−</button>
          <button class="step" id="splus" aria-label="one more">+</button>
        </div>
        <div class="kv"><span>${manual ? 'taps' : 'detected'}</span><b class="num" id="detOut"></b></div>
        <div class="kv"><span>adjustment</span><b class="num" id="adjOut"></b></div>
        <div class="kv"><span>duration</span><b class="num" id="durOut"></b></div>
        ${manual ? '' : '<div class="kv"><span>tracking</span><b class="num" id="qualOut"></b></div>'}
        <div class="kv"><span>today after this</span><b class="num" id="dayOut"></b></div>
        <div class="flags" id="flagRow"></div>
        <div class="field"><label for="notes">notes</label><textarea id="notes" rows="2" placeholder="optional"></textarea></div>
        <div class="sub" style="margin-top:4px;margin-bottom:12px" id="saveMsg"></div>
        <div class="row sumcta">
          <button class="btn btn-quiet grow" id="again">New set</button>
          <button class="btn btn-primary grow" id="save">Save set</button>
        </div>
      </div>`;
    const inp = q('#finalIn');
    inp.value = String(d.final);
    q('#detOut').textContent = String(d.detected);
    q('#durOut').textContent = Math.round(d.durationMs / 1000) + ' s';
    if (q('#qualOut')) {
      q('#qualOut').textContent = d.quality.fpsMean + ' fps · ' + pct(d.quality.visMean) +
        (d.quality.breaks ? ' · ' + d.quality.breaks + ' breaks' : '');
    }
    const adjOut = q('#adjOut');
    const dayOut = q('#dayOut');
    const sync = () => {
      const v = clamp(parseInt(inp.value, 10) || 0, 0, 999);
      d.final = v;
      const adj = v - d.detected;
      adjOut.textContent = (adj > 0 ? '+' : '') + adj;
      dayOut.textContent = fmtInt(dayBase + v);
    };
    inp.addEventListener('input', sync);
    q('#sminus').addEventListener('click', () => { inp.value = String(Math.max(0, (parseInt(inp.value, 10) || 0) - 1)); sync(); });
    q('#splus').addEventListener('click', () => { inp.value = String((parseInt(inp.value, 10) || 0) + 1); sync(); });
    sync();

    const row = q('#flagRow');
    const parts = Object.entries(d.flags).filter(([, v]) => v > 0);
    if (!parts.length) {
      const s = document.createElement('span');
      s.textContent = 'clean set';
      row.append(s);
    } else {
      parts.forEach(([k, v]) => {
        const s = document.createElement('span');
        s.className = ['sag', 'pike', 'half', 'lost'].includes(k) ? 'hard'
          : ['lockout', 'other'].includes(k) ? 'soft' : 'info';
        s.textContent = v + ' ' + (k === 'other' ? 'flagged' : k);
        row.append(s);
      });
    }

    q('#again').addEventListener('click', () => { summary = null; renderSetup(); });
    q('#save').addEventListener('click', async () => {
      const val = clamp(parseInt(inp.value, 10) || 0, 0, 999);
      const rec = {
        startedAt: d.startedAt,
        endedAt: d.startedAt + d.durationMs,
        durationMs: d.durationMs,
        mode: load().manualMode ? 'manual' : 'camera',
        source: load().manualMode ? 'manual' : 'camera',
        repsDetected: d.detected,
        repsFinal: val,
        flags: d.flags,
        cameraUsed: load().camera,
        qualityStats: d.quality,
        paramsUsed: params(),
        presetName: load().preset,
        model: load().model,
        notes: q('#notes').value.trim(),
        day: dayOf(d.startedAt),
        endReason: d.reason,
      };
      const msg = q('#saveMsg');
      try {
        const id = await saveSet(rec, d.reps);
        msg.textContent = 'Saved as set ' + id + '.';
        q('#save').disabled = true;
        const total = (await listSetsForDay(today())).reduce((a, s) => a + (s.repsFinal || 0), 0);
        tryBadging(total);
        setTimeout(() => { summary = null; renderSetup(); }, 900);
      } catch (e) {
        msg.textContent = 'Save failed: ' + (e && e.message ? e.message : e);
      }
    });
  }

  // ── frame pump ────────────────────────────────────────────────
  // The counter is fed in every phase (setup, countdown, set) so the checklist can show real plank
  // and angle numbers. It only counts once a set has started, because startSet() resets the machine
  // and the arm gate refuses to count until the plank has been held.
  function onFrame(f) {
    const now = Date.now();
    lastFrameAt = now;
    measureLight();
    if (load().manualMode) return;

    const before = lastOut.repsDetected;
    lastOut = counter.addFrame(now, f) || EMPTY_OUT;

    if (phase === 'setup') {
      if (els.qbar) {
        els.qbar.style.width = Math.round(f.quality * 100) + '%';
        els.qbar.className = f.quality < 0.4 ? 'bad' : '';
        els.qtxt.textContent = pct(f.quality);
        els.fpstxt.textContent = Math.round(f.fps) + ' fps';
      }
      evaluateChecks(f);
      if (load().autoArm && lastOut.plank && lastOut.plank.valid) {
        if (!plankSince) plankSince = now;
        else if (now - plankSince > load().armHoldMs + 400 && !cdTimer) startCountdown(5);
      } else plankSince = 0;
      /* The statusbar under the preview already carries fps and tracking, so the overlay on the
         video says what the numbers mean instead of repeating them. */
      paintPill(f, f.quality < 0.35 ? 'not seeing you yet' : f.quality < 0.6 ? 'partly in frame' : 'in frame');
      return;
    }

    if (phase === 'set') {
      qualityLog.push(lastOut.quality);
      if (f.fps) fpsSamples.push(f.fps);
      (lastOut.events || []).forEach((ev) => {
        if (ev.type === 'rep') {
          const rep = ev.data && (ev.data.rep || ev.data);
          reps.push({ ...rep, tMs: (rep.tEnd || ev.t) - setStart });
          lastRepAt = now;
          announceRep(lastOut.repsDetected, { mode: load().voice, beeps: load().beeps, haptics: load().haptics });
        } else if (ev.type === 'armBreak') armBreaks += 1;
      });
      paintCount();
      updateLost(now, lastOut);
      if (lastOut.repsDetected !== before && load().debug) console.log('rep', lastOut.repsDetected);
    }
    if (phase === 'countdown') paintPill(f);
  }

  function updateLost(now, out) {
    const stale = now - lastFrameAt > 600;
    const bad = stale || out.quality < 0.35;
    if (!bad) {
      lostSince = 0;
      if (lostShown) { lostShown = false; clearWarn(); }
      return;
    }
    if (!lostSince) lostSince = now;
    if (!lostShown && now - lostSince > 650) {
      lostShown = true;
      showWarn(stale ? 'Camera lost you — stay in frame' : 'Tracking weak — add light or move the phone closer');
      playWarning();
      vibrate([30, 60, 30]);
    }
  }

  function showWarn(text) {
    els.warnbox.hidden = false;
    els.warnbox.textContent = text;
    els.hairline.classList.add('on');
    els.stage.classList.add('dim');
  }

  function clearWarn() {
    els.warnbox.hidden = true;
    els.hairline.classList.remove('on');
    els.stage.classList.remove('dim');
    lostShown = false;
  }

  function paintPill(f, text) {
    els.pill.className = 'pill' + (f.quality < 0.35 ? ' bad' : f.quality < 0.6 ? ' warn' : '');
    els.pillText.textContent = text
      || (Math.round(f.fps) + ' fps · ' + pct(f.quality) + ' tracked');
  }

  function tick() {
    if (phase !== 'set') return;
    const secs = Math.round((Date.now() - setStart) / 1000);
    els.clock.textContent = Math.floor(secs / 60) + ':' + String(secs % 60).padStart(2, '0');
    const idle = (Date.now() - lastRepAt) / 1000;
    if (detected() > 0 && idle > load().endAfterIdleSec) endSet('idle');
  }

  // ── camera + pose ─────────────────────────────────────────────
  async function startCamera(facing) {
    if (load().manualMode) return;
    if (!cameraSupports()) return camFail({ name: 'SecurityError' });
    els.camoff.hidden = true;
    try {
      cam = await openCamera(els.video, { facing });
      mirror = (cam.settings && cam.settings.facing) === 'user';
      if (cam.settings && cam.settings.needsTap) {
        // iOS refused to autoplay outside a gesture: the next tap anywhere restarts the preview
        const wake = () => { resumePreview(els.video); els.camoff.hidden = true; };
        els.camoff.hidden = false;
        els.camoff.replaceChildren();
        const hint = document.createElement('div');
        hint.textContent = 'Tap to show the preview';
        els.camoff.append(hint);
        els.camoff.addEventListener('click', wake, { once: true });
      }
      if (tracker && tracker.setMirrored) tracker.setMirrored(mirror);
      els.phaseLabel.textContent = mirror ? 'front camera' : 'set up';
    } catch (err) {
      camFail(err);
    }
  }

  function camFail(err) {
    const d = (dce || describeCameraError)(err);
    els.camoff.hidden = false;
    els.camoff.replaceChildren();
    const h3 = document.createElement('div');
    h3.style.color = 'var(--text)';
    h3.style.fontWeight = '600';
    h3.textContent = d.title;
    const ol = document.createElement('ol');
    (d.steps || []).forEach((s) => {
      const li = document.createElement('li');
      li.textContent = s;
      ol.append(li);
    });
    els.camoff.append(h3, ol);
    els.pillText.textContent = 'camera blocked';
  }

  renderSetup();

  (async () => {
    if (load().manualMode) return;
    await startCamera(load().camera);
    tracker = await createTracker({
      video: els.video,
      canvas: els.overlay,
      model: load().model,
      fpsCap: load().fpsCap,
      mirrored: mirror,
      strokeStyle: (getComputedStyle(document.body).getPropertyValue('--track') || '#4FA3A5').trim(),
      onStatus: (kind, detail) => {
        if (kind === 'loading-model') els.pillText.textContent = 'loading pose model';
        else if (kind === 'delegate-downgrade') els.pillText.textContent = 'cpu mode · ' + (detail || '');
        else if (kind === 'ready' || kind === 'running') clearWarn();
      },
      onFrame: (f) => {
        try { onFrame(f); } catch (e) { console.error('frame', e); }
      },
      onError: (e) => {
        els.pillText.textContent = 'pose error';
        console.error('pose', e);
      },
    });
    await tracker.start();
  })();

  return {
    unmount() {
      document.body.classList.remove('in-set');
      if (cdTimer) clearInterval(cdTimer);
      if (tickTimer) clearInterval(tickTimer);
      if (tracker) { if (tracker.stop) tracker.stop(); if (tracker.dispose) tracker.dispose(); }
      if (cam) closeCamera(cam);
    },
  };
}
