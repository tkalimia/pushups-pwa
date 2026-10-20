/* Today: the day's number, the goal ring, the streak, and the sets behind them.
   All numbers come from stats.js / goals.js over one listSets() read; nothing here recomputes
   totals by hand except the today filter, so the screen and the Progress screen can never disagree. */

import { deleteSet, listSets, saveSet, updateSet } from '../db.js';
import { goalStatus, usePass } from '../goals.js';
import { byDay, dayFromKey, gaps, records } from '../stats.js';
import { clamp, dayOf, fmtClock, fmtDay, h, pct, sum, today } from '../util.js';

const NS = 'http://www.w3.org/2000/svg';
const SIZE = 88;
const STROKE = 7;
const R = (SIZE - STROKE) / 2 - 2;
const C = 2 * Math.PI * R;

const SKELETON = `
  <div class="list">
    <div class="tg-hero">
      <div class="tg-heronum">
        <div class="tg-total" id="tgTotal">0</div>
        <h1 class="tg-date" id="tgDate"></h1>
        <div class="tg-unit">reps today</div>
        <div class="tg-note" id="tgNote"></div>
      </div>
      <div class="tg-ringwrap" id="tgRing"></div>
    </div>
    <div class="tg-goalnote" id="tgGoalNote"></div>
    <div class="row tg-streak" id="tgStreak"></div>
    <div class="rule" style="margin:6px 16px 10px"></div>
    <div id="tgMinis"></div>
    <div id="tgSetsHead"></div>
    <div id="tgSets"></div>
    <div id="tgFoot"></div>
    <div id="tgMissed"></div>
    <a class="tg-prog" href="#/progress"><span class="grow">progress and history</span><span class="chev" aria-hidden="true">›</span></a>
    <div style="height:12px"></div>
  </div>`;

/* ── small builders ────────────────────────────────────────────── */

function svg(tag, attrs) {
  const el = document.createElementNS(NS, tag);
  for (const k of Object.keys(attrs || {})) {
    const v = attrs[k];
    if (v === null || v === undefined || v === false) continue;
    el.setAttribute(k, String(v));
  }
  return el;
}

/** Hand-rolled ring: one track circle, one arc whose stroke-dasharray is the arc length. */
function ringEl(frac, met) {
  const shown = clamp(Number(frac) || 0, 0, 1) * C;
  const half = SIZE / 2;
  const arc = svg('circle', {
    class: 'tg-arc', cx: half, cy: half, r: R, fill: 'none', 'stroke-width': STROKE,
    'stroke-dasharray': shown.toFixed(2) + ' ' + (C - shown).toFixed(2),
  });
  if (shown > 0.5) arc.setAttribute('stroke-linecap', 'round');
  const el = svg('svg', {
    class: 'tg-ring' + (met ? ' met' : ''), width: SIZE, height: SIZE,
    viewBox: '0 0 ' + SIZE + ' ' + SIZE, 'aria-hidden': 'true', focusable: 'false',
  });
  el.append(svg('circle', {
    class: 'tg-track', cx: half, cy: half, r: R, fill: 'none', 'stroke-width': STROKE,
  }), arc);
  return el;
}

function errText(e) {
  return (e && e.message) ? e.message : String(e);
}

function flagCount(s) {
  const f = (s && s.flags) || {};
  return (Number(f.sag) || 0) + (Number(f.pike) || 0) + (Number(f.half) || 0)
    + (Number(f.lockout) || 0) + (Number(f.lost) || 0);
}

function sourceLabel(s) {
  if (s.source === 'manual' || s.mode === 'manual') return 'manual';
  return s.cameraUsed === 'user' ? 'front cam' : 'side cam';
}

function repsOf(s) {
  return Number(s && s.repsFinal) || 0;
}

function detectedOf(s) {
  return Number(s && s.repsDetected) || 0;
}

/** '2026-10-20' -> that noon, local. Manual backfills land at midday so they sort inside the day. */
function noonOf(dayKeyStr) {
  const d = new Date(dayFromKey(dayKeyStr));
  d.setHours(12, 0, 0, 0);
  return d.getTime();
}

function parseReps(raw) {
  const n = parseInt(String(raw).trim(), 10);
  if (!Number.isFinite(n)) return null;
  return clamp(n, 0, 999);
}

/* ── the view ──────────────────────────────────────────────────── */

export default async function todayView(host, ctx) {
  const key = today();
  const rerender = () => {
    if (ctx && typeof ctx.render === 'function') return ctx.render();
    return null;
  };
  let scrim = null;

  host.innerHTML = SKELETON;
  const q = (sel) => host.querySelector(sel);
  const els = {
    total: q('#tgTotal'), date: q('#tgDate'), note: q('#tgNote'), ring: q('#tgRing'),
    goalNote: q('#tgGoalNote'), streak: q('#tgStreak'), minis: q('#tgMinis'),
    setsHead: q('#tgSetsHead'), sets: q('#tgSets'), foot: q('#tgFoot'), missed: q('#tgMissed'),
  };

  els.date.textContent = new Date().toLocaleDateString(undefined, {
    weekday: 'long', day: 'numeric', month: 'long',
  });

  // ── read everything once, guarded ─────────────────────────────
  let sets = [];
  let status = null;
  let setsError = '';      // no sets at all -> lists and gaps are meaningless
  let goalsError = '';     // sets are fine, goals meta is not -> header rows degrade to lifetime only
  try {
    sets = await listSets();
    if (!Array.isArray(sets)) sets = [];
  } catch (e) {
    setsError = 'database unreadable: ' + errText(e);
    sets = [];
  }
  if (!setsError) {
    try {
      status = await goalStatus(sets, key);
    } catch (e) {
      goalsError = 'goals unreadable: ' + errText(e);
    }
  }
  const failed = setsError || goalsError;
  if (failed) els.note.textContent = failed;

  let rec = null;
  let days = byDay([]);
  if (!setsError) {
    try {
      days = byDay(sets);
      rec = records(sets);
    } catch (e) {
      els.note.textContent = errText(e);
    }
  }

  const mine = sets
    .filter((s) => s && ((s.day || dayOf(s.startedAt || 0)) === key))
    .sort((a, b) => (b.startedAt || 0) - (a.startedAt || 0));
  const dayReps = sum(mine.map(repsOf));

  els.total.textContent = String(dayReps);

  const daily = status ? status.daily : null;
  const goal = daily ? daily.goal : 0;
  const met = !!daily && goal > 0 && daily.reps >= goal;

  paintRing(daily, met);
  paintStreak(status, met, key);
  paintMinis(status, days, rec, key);
  paintSets(mine, setsError);
  paintMissed(days, status, key);

  // ── painters ──────────────────────────────────────────────────

  function paintRing(d, wasMet) {
    els.ring.replaceChildren();
    if (!d) {
      els.goalNote.textContent = failed ? '' : 'no goal on record';
      return;
    }
    if (d.goal <= 0) {
      els.goalNote.textContent = 'daily goal is off — set one in Settings';
      return;
    }
    els.ring.append(ringEl(d.pct, wasMet));
    els.ring.append(h('div', { class: 'tg-ringtext' },
      h('div', { class: 'tg-ringnum' }, String(d.goal)),
      h('div', { class: 'tg-ringlbl' }, wasMet ? 'met' : 'goal')));
    const left = Math.max(0, d.goal - d.reps);
    els.goalNote.className = 'tg-goalnote' + (wasMet ? ' met' : '');
    els.goalNote.textContent = wasMet
      ? 'goal met'
      : left + ' to go · goal ' + d.goal;
  }

  function paintStreak(st, wasMet, dayKeyStr) {
    els.streak.replaceChildren();
    if (!st) return;
    const s = st.streak;
    const txt = s.n > 0
      ? (s.mode === 'daily'
        ? s.n + (s.n === 1 ? ' day in a row' : ' days in a row')
        : s.n + (s.n === 1 ? ' week on target' : ' weeks on target'))
      : (s.mode === 'daily' ? 'no streak yet' : 'no full week on target yet');
    const line = h('span', { class: 'tg-streakline' },
      h('span', { class: 'tg-streaktxt' }, txt));
    if (s.mode === 'weekly' && st.goals.weekly > 0) {
      line.append(h('span', { class: 'tg-streaktxt dim' }, ' · ' + pct(st.weekly.pct) + ' of this week'));
    }
    els.streak.append(line);

    const passes = st.passes || {};
    const hasPasses = st.passesLeft > 0 || !!passes[dayKeyStr];
    if (!hasPasses) return;
    if (passes[dayKeyStr]) {
      els.streak.append(h('span', { class: 'tg-donetag' }, 'rest taken today'));
      return;
    }
    if (wasMet) return;
    // on a phone with no history there is no streak to keep alive — the pass is offered
    // from the missed-day sheet instead
    if (!rec || rec.lifetimeSets === 0) return;

    const why = h('span', { class: 'tg-streakwhy' });
    const btn = h('button', { class: 'tg-linkbtn', type: 'button' }, 'use a rest pass');
    btn.addEventListener('click', async () => {
      btn.disabled = true;
      why.textContent = '';
      try {
        const res = await usePass(dayKeyStr);
        if (res && res.ok) { await rerender(); return; }
        why.textContent = (res && res.reason) || 'the pass was not used';
        btn.disabled = false;
      } catch (e) {
        why.textContent = errText(e);
        btn.disabled = false;
      }
    });
    els.streak.append(btn, why);
  }

  function paintMinis(st, dayMap, hist, dayKeyStr) {
    const rows = [];
    if (st) {
      rows.push(['this week', st.weekly.reps + ' of ' + st.weekly.goal + ' · ' + pct(st.weekly.pct)]);
      let month = 0;
      for (const [k, d] of dayMap) if (k.slice(0, 7) === dayKeyStr.slice(0, 7)) month += d.reps;
      rows.push(['this month', String(month) + ' reps']);
      rows.push(['this year', st.yearly.reps + ' of ' + st.yearly.goal + ' · ' + pct(st.yearly.pct)]);
    }
    if (hist) {
      rows.push(['lifetime', hist.lifetimeReps + ' reps · ' + hist.lifetimeSets + ' sets']);
    }
    els.minis.replaceChildren();
    if (!rows.length) return;   // the note under the date already says what failed
    const box = h('div', { class: 'tg-minis' });
    rows.forEach(([label, value]) => {
      box.append(h('div', { class: 'kv' },
        h('span', { class: 'tg-key' }, label),
        h('b', { class: 'tg-val' }, value)));
    });
    els.minis.append(box);
  }

  function paintSets(list, dbFailed) {
    els.setsHead.replaceChildren();
    els.sets.replaceChildren();
    els.foot.replaceChildren();
    if (dbFailed) {
      els.setsHead.append(h('div', { class: 'tg-head' }, 'sets'));
      els.sets.append(h('p', { class: 'soon tg-empty' }, 'nothing to list — the saved sets could not be read.'));
      return;
    }
    els.setsHead.append(h('div', { class: 'tg-head' },
      'today’s sets' + (list.length ? ' · ' + list.length : '')));
    if (!list.length) {
      els.sets.append(h('p', { class: 'soon tg-empty' },
        'no sets yet today. Train → start set, or add a missed day below.'));
      return;
    }
    els.sets.replaceChildren(...list.map(setRow));
    const det = sum(list.map(detectedOf));
    const kept = sum(list.map(repsOf));
    els.foot.append(h('div', { class: 'tg-foot' },
      'camera saw ' + det + ', you kept ' + kept + '.'));
  }

  function setRow(s) {
    const box = h('div', { class: 'tg-set' });
    const line = h('div', { class: 'tg-setmain' });
    const flagged = flagCount(s);
    const meta = fmtClock(s.startedAt || 0) + ' · ' + sourceLabel(s)
      + (flagged ? ' · ' + flagged + ' flagged' : '');
    const num = h('span', { class: 'tg-setnum' }, String(repsOf(s)));
    const open = h('button', { class: 'tg-editbtn', type: 'button' },
      num, h('span', { class: 'tg-setmeta' }, meta));
    const del = h('button', { class: 'btn btn-quiet tg-mini', type: 'button' }, 'delete');
    line.append(open, del);

    const editline = h('div', { class: 'tg-editline', hidden: true });
    const inp = h('input', {
      class: 'tg-in', type: 'number', inputmode: 'numeric', min: '0', max: '999',
      'aria-label': 'reps for this set',
    });
    const err = h('span', { class: 'tg-err' });
    const saveBtn = h('button', { class: 'btn btn-primary tg-mini', type: 'button' }, 'save');
    const cancelBtn = h('button', { class: 'btn btn-quiet tg-mini', type: 'button' }, 'cancel');
    editline.append(inp, saveBtn, cancelBtn, err);

    function openEditor() {
      err.textContent = '';
      inp.value = String(repsOf(s));
      editline.hidden = false;
      del.hidden = true;
      num.hidden = true;          // the meta line stays, so you can see which set you are fixing
      try { inp.focus({ preventScroll: false }); } catch { inp.focus(); }
    }
    function closeEditor() {
      editline.hidden = true;
      del.hidden = false;
      num.hidden = false;
    }

    open.addEventListener('click', () => { if (editline.hidden) openEditor(); else closeEditor(); });
    cancelBtn.addEventListener('click', closeEditor);
    saveBtn.addEventListener('click', async () => {
      const v = parseReps(inp.value);
      if (v === null) { err.textContent = 'enter a number'; return; }
      err.textContent = '';
      saveBtn.disabled = true;
      try {
        await updateSet(s.id, { repsFinal: v });   // repsDetected is left alone on purpose
        await rerender();
      } catch (e) {
        err.textContent = 'could not save: ' + errText(e);
        saveBtn.disabled = false;
      }
    });
    del.addEventListener('click', async () => {
      if (!confirm('Delete this set?')) return;
      del.disabled = true;
      try {
        await deleteSet(s.id);
        await rerender();
      } catch (e) {
        del.disabled = false;
        err.textContent = 'could not delete: ' + errText(e);
        openEditor();
      }
    });

    box.append(line, editline);
    return box;
  }

  function paintMissed(dayMap, st, dayKeyStr) {
    els.missed.replaceChildren();
    if (setsError || !dayMap || dayMap.size < 2) return;
    let list = [];
    try {
      list = gaps(dayMap, 30).filter((k) => k < dayKeyStr);
    } catch { list = []; }
    if (!list.length) return;
    const month = dayKeyStr.slice(0, 7);
    const allThisMonth = list.every((k) => k.slice(0, 7) === month);
    const span = allThisMonth ? 'this month' : 'in the last 30 days';
    const btn = h('button', { class: 'tg-quietrow', type: 'button' },
      list.length + ' missed ' + (list.length === 1 ? 'day' : 'days') + ' ' + span);
    btn.addEventListener('click', () => openGapSheet(list, st));
    els.missed.append(btn);
  }

  // ── missed-day sheet ──────────────────────────────────────────

  function closeSheet() {
    if (scrim && scrim.parentNode) scrim.parentNode.removeChild(scrim);
    scrim = null;
  }

  function openGapSheet(list, st) {
    closeSheet();
    const passes = (st && st.passes) || {};
    const panel = h('div', { class: 'tg-panel', role: 'dialog', 'aria-modal': 'true', 'aria-label': 'missed days' });
    panel.append(h('div', { class: 'tg-panelhead' },
      h('div', { class: 'tg-paneltitle' }, 'missed days'),
      h('button', { class: 'tg-linkbtn dim', type: 'button', onclick: closeSheet }, 'done')));
    panel.append(h('span', { class: 'tg-panellbl' },
      'log a set you actually did, or spend a rest pass. neither changes what the camera saw.'));
    list.slice(-14).reverse().forEach((day) => panel.append(gapRow(day, passes[day])));
    scrim = h('div', { class: 'tg-scrim' }, panel);
    scrim.addEventListener('click', (ev) => { if (ev.target === scrim) closeSheet(); });
    document.body.append(scrim);
  }

  function gapRow(day, alreadyPassed) {
    const row = h('div', { class: 'tg-gaprow' });
    row.append(h('div', { class: 'tg-gapday' }, fmtDay(day)));
    const err = h('span', { class: 'tg-err' });

    if (alreadyPassed) {
      row.append(h('span', { class: 'tg-donetag' }, 'rest taken'));
      row.append(err);
      return row;
    }

    const addBtn = h('button', { class: 'tg-linkbtn', type: 'button' }, 'add');
    const restBtn = h('button', { class: 'tg-linkbtn dim', type: 'button' }, 'rest');
    const inp = h('input', { class: 'tg-in', type: 'number', inputmode: 'numeric', min: '0', max: '999', 'aria-label': 'reps for ' + fmtDay(day) });
    const saveBtn = h('button', { class: 'btn btn-primary tg-mini', type: 'button' }, 'save');
    const cancelBtn = h('button', { class: 'btn btn-quiet tg-mini', type: 'button' }, 'cancel');
    const editor = h('div', { class: 'tg-gapedit', hidden: true }, inp, saveBtn, cancelBtn);

    addBtn.addEventListener('click', () => {
      err.textContent = '';
      inp.value = '';
      addBtn.hidden = true;
      restBtn.hidden = true;
      editor.hidden = false;
      try { inp.focus(); } catch { /* focus is a nicety */ }
    });
    cancelBtn.addEventListener('click', () => {
      editor.hidden = true;
      addBtn.hidden = false;
      restBtn.hidden = false;
    });
    saveBtn.addEventListener('click', async () => {
      const v = parseReps(inp.value);
      if (v === null) { err.textContent = 'enter a number'; return; }
      saveBtn.disabled = true;
      err.textContent = '';
      try {
        // manual backfill: detected 0, no rep rows — the app never claims the camera saw this
        await saveSet({
          startedAt: noonOf(day),
          day,
          mode: 'manual',
          source: 'manual',
          repsDetected: 0,
          repsFinal: v,
          flags: {},
        }, []);
        await rerender();
      } catch (e) {
        err.textContent = 'could not save: ' + errText(e);
        saveBtn.disabled = false;
      }
    });
    restBtn.addEventListener('click', async () => {
      restBtn.disabled = true;
      err.textContent = '';
      try {
        const res = await usePass(day);
        if (res && res.ok) { await rerender(); return; }
        err.textContent = (res && res.reason) || 'the pass was not used';
        restBtn.disabled = false;
      } catch (e) {
        err.textContent = errText(e);
        restBtn.disabled = false;
      }
    });

    row.append(addBtn, restBtn, editor, err);
    return row;
  }

  return {
    unmount() { closeSheet(); },
  };
}
