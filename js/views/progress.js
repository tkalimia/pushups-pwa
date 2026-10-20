/* Progress: the calendar heatmap is the one big thing; everything below it is a smaller read.
   All numbers come from stats.js / goals.js over a single listSets() read, so this screen and the
   Today screen cannot disagree. Charts are hand-rolled divs and inline SVG — no library, no build.
   Sets are sorted oldest-first once here, because stats.consistencySeries slices the tail. */

import { deleteSet, listReps, listSets, listSetsForDay, saveSet, updateSet } from '../db.js';
import { loadGoals } from '../goals.js';
import {
  bestSetPerWeek, byDay, consistencySeries, dayBuckets, dayFromKey, estimatedMax,
  flagMix, heatmap, monthBuckets, projectTarget, records, timeOfDay, weekBuckets, yearBuckets,
} from '../stats.js';
import { clamp, clear, fmtClock, fmtDay, h, mean, pct, sum, today } from '../util.js';

const NS = 'http://www.w3.org/2000/svg';
const HEAT_WEEKS = 26;      // half a year of columns — as much grid as a phone can hold
const REP_CAP = 30;         // per-rep fan-out: never read rep rows for more sets than this
const TARGET_KEY = 'pushups.target';
const DEFAULT_TARGET = 100;
const MAX_WINDOW = 28;      // estimatedMax look-back, days

const RANGES = {
  day: { label: 'Day', window: 'last 30 days', make: (d) => dayBuckets(d, 30) },
  week: { label: 'Week', window: 'last 26 weeks', make: (d) => weekBuckets(d, 26) },
  month: { label: 'Month', window: 'last 12 months', make: (d) => monthBuckets(d, 12) },
  year: { label: 'Year', window: 'last 5 years', make: (d) => yearBuckets(d, 5) },
};
const RANGE_ORDER = ['day', 'week', 'month', 'year'];
const DAY_GRAIN = ['month', 'year'];   // these buckets count days, not sets

const VOL_SERIES = {
  volume: { label: 'weekly volume', pick: (b) => b.reps, unit: 'reps this week' },
  avg: { label: 'reps per set', pick: (b) => b.avgPerSet, unit: 'per set this week' },
};

const FLAG_LABEL = {
  sag: 'hips sagging', pike: 'hips piking', half: 'shallow reps',
  lockout: 'no lockout', lost: 'tracking lost',
};
const FLAG_HARD = ['sag', 'pike', 'half', 'lost'];
const TOD_TONE = ['lv1', 'lv2', 'lv3', 'lv4'];
const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const SKELETON = `
  <div class="list">
    <div class="pg-top pad">
      <h2 class="h1">Progress</h2>
      <p class="pg-sum" id="pgSum"></p>
      <p class="pg-error" id="pgNote"></p>
    </div>
    <div class="pg-heatsec">
      <div class="pg-cap pad" id="pgHeatCap"></div>
      <div class="pad" id="pgHeat"></div>
      <div class="pg-capend pad" id="pgHeatLegend"></div>
    </div>
    <div class="pg-sec">
      <div class="pad" id="pgRangeHead"></div>
      <div class="pg-seg pad" id="pgRange"></div>
      <div class="pg-cap pad" id="pgChartCap"></div>
      <div id="pgChart"></div>
    </div>
    <div class="pg-box pad" id="pgBest"></div>
    <div class="pg-box pad" id="pgVol"></div>
    <div class="pg-sec">
      <div class="pad" id="pgMax"></div>
      <div class="rule" style="margin:10px 16px 6px"></div>
      <div class="pad" id="pgTarget"></div>
    </div>
    <div class="pg-box pad" id="pgConsist"></div>
    <div class="pg-sec">
      <div class="pad" id="pgRecHead"></div>
      <div class="pad" id="pgRecords"></div>
      <div id="pgFlags" class="pad"></div>
    </div>
    <div class="pg-box pad" id="pgTod"></div>
    <div class="pg-foot pad" id="pgFoot"></div>
    <div style="height:14px"></div>
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

/** CSS custom properties need setProperty — Object.assign onto style would be ignored. */
function vars(el, map) {
  for (const k of Object.keys(map || {})) el.style.setProperty(k, String(map[k]));
  return el;
}

function errText(e) {
  return e && e.message ? e.message : String(e);
}

function fmtDur(ms) {
  const t = Math.max(0, Math.round((Number(ms) || 0) / 1000));
  return Math.floor(t / 60) + ':' + String(t % 60).padStart(2, '0');
}

/** 'YYYY-MM-DD' at local midday, so a backfilled set sorts inside its own day. */
function noonOf(dayKeyStr) {
  const d = new Date(dayFromKey(dayKeyStr));
  d.setHours(12, 0, 0, 0);
  return d.getTime();
}

function parseReps(raw) {
  const n = parseInt(String(raw).trim(), 10);
  return Number.isFinite(n) ? clamp(n, 0, 999) : null;
}

function repsOf(s) {
  return Number(s && s.repsFinal) || 0;
}

function detectedOf(s) {
  return Number(s && s.repsDetected) || 0;
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

/** Tick text per grain: day number, week start as m/d, three-letter month, four-digit year. */
function bucketLabel(bucket, grain) {
  if (grain === 'day') return String(Number(bucket.key.slice(8, 10)));
  if (grain === 'week') return Number(bucket.key.slice(5, 7)) + '/' + Number(bucket.key.slice(8, 10));
  if (grain === 'month') return MONTH_NAMES[(Number(bucket.key.slice(5, 7)) || 1) - 1];
  return bucket.label || bucket.key;
}

function monthText(mk) {
  return MONTH_NAMES[(Number(mk.slice(5, 7)) || 1) - 1] + ' ' + String(mk).slice(0, 4);
}

/** 'Fri 9 Oct', but with the year when the date is not in the current one. */
function fmtDayYear(dayKeyStr, nowKey) {
  const text = fmtDay(dayKeyStr);
  return String(dayKeyStr).slice(0, 4) === String(nowKey).slice(0, 4) ? text : text + ' ' + String(dayKeyStr).slice(0, 4);
}

function peakCaption(bucket, grain) {
  const reps = bucket.reps;
  if (grain === 'day') return 'peak ' + reps + ' on ' + fmtDay(bucket.key);
  if (grain === 'week') return 'peak ' + reps + ' in the week of ' + fmtDay(bucket.key);
  if (grain === 'month') return 'peak ' + reps + ' in ' + monthText(bucket.key);
  return 'peak ' + reps + ' in ' + bucket.key;
}

function headBlock(title, sub) {
  const row = h('div', { class: 'pg-headrow' }, h('div', { class: 'pg-headtitle' }, title));
  if (sub) row.append(h('div', { class: 'pg-headsub' }, sub));
  return row;
}

function caption(text, cls) {
  return h('p', { class: 'sub pg-caption' + (cls ? ' ' + cls : '') }, text);
}

/* ── hand-rolled charts ────────────────────────────────────────── */

/**
 * Line or step chart in a 100-wide viewBox stretched to the container. non-scaling-stroke keeps the
 * line the same weight whatever the x/y stretch factors do, so nothing here needs measuring.
 */
function spark(vals, opts = {}) {
  const clean = (vals || []).map((v) => (Number.isFinite(v) ? v : 0));
  const n = clean.length;
  const height = Number(opts.height) || 56;
  const pad = 3;
  const el = svg('svg', {
    class: 'pg-spark' + (opts.tone ? ' ' + opts.tone : ''),
    viewBox: '0 0 100 ' + height, preserveAspectRatio: 'none',
    'aria-hidden': 'true', focusable: 'false',
  });
  el.style.setProperty('height', height + 'px');
  if (!n) return el;
  const top = Math.max(...clean) || 1;
  const x = (i) => (n === 1 ? 50 : (i * 100) / (n - 1));
  const y = (v) => height - pad - clamp(v / top, 0, 1) * (height - pad * 2);
  const parts = [];
  if (opts.step) {
    parts.push('M' + x(0).toFixed(2) + ' ' + y(clean[0]).toFixed(2));
    for (let i = 1; i < n; i++) {
      parts.push('H' + x(i).toFixed(2));
      parts.push('V' + y(clean[i]).toFixed(2));
    }
  } else {
    clean.forEach((v, i) => parts.push((i ? 'L' : 'M') + x(i).toFixed(2) + ' ' + y(v).toFixed(2)));
  }
  el.append(svg('path', { class: 'pg-base', d: 'M0 ' + (height - 0.6).toFixed(2) + ' H100' }));
  el.append(svg('path', {
    class: 'pg-area',
    d: parts.join(' ') + ' H' + x(n - 1).toFixed(2) + ' V' + height + ' H' + x(0).toFixed(2) + ' Z',
  }));
  el.append(svg('path', { class: 'pg-line', d: parts.join(' ') }));
  if (opts.dot !== false) {
    el.append(svg('circle', { class: 'pg-dot', cx: x(n - 1).toFixed(2), cy: y(clean[n - 1]).toFixed(2), r: '2.2' }));
  }
  return el;
}

/** Axis row with one slot per bucket so labels line up with their bars. */
function axisRow(buckets, grain) {
  const n = buckets.length;
  const every = n > 13 ? Math.ceil(n / 5) : n > 8 ? 2 : 1;
  const row = h('div', { class: 'pg-axis' });
  buckets.forEach((b, i) => {
    const show = every === 1 ? true : (i % every === 1 && i < n - 1);
    row.append(h('div', { class: 'pg-aslot' }, show ? h('span', { class: 'pg-atext' }, bucketLabel(b, grain)) : null));
  });
  return row;
}

/** Reps as bars; sets (or training days) as a quiet tick at the baseline. */
function barChart(buckets, opts) {
  const grain = opts.grain;
  const secOf = (b) => (DAY_GRAIN.indexOf(grain) >= 0 ? b.days : b.sets);
  const maxReps = Math.max(0, ...buckets.map((b) => b.reps));
  const maxSec = Math.max(0, ...buckets.map(secOf));
  const wrap = h('div', { class: 'pg-barchart' });
  if (!maxReps) {
    // a 112px void next to a caption that already says nothing happened is just a hole in the page
    wrap.append(h('div', { class: 'pg-plotempty' }, 'nothing logged in this window yet'));
    return wrap;
  }
  const plot = h('div', { class: 'pg-plot' });
  if (opts.goal > 0 && maxReps > 0 && opts.goal <= maxReps) {
    // 5px of the slot is the tick and its gap, so the goal line is measured against the bar area only
    const frac = clamp(opts.goal / maxReps, 0, 1).toFixed(4);
    const line = h('div', { class: 'pg-goalline' }, h('span', { class: 'pg-goaltag' }, 'goal ' + opts.goal));
    line.style.setProperty('bottom', 'calc((100% - 5px) * ' + frac + ' + 5px)');
    plot.append(line);
  }
  buckets.forEach((b) => {
    const sec = secOf(b);
    const bar = h('i', { class: 'pg-bar' + (maxReps > 0 && b.reps === maxReps ? ' hi' : ''), 'aria-hidden': 'true' });
    bar.style.setProperty('height', (maxReps > 0 ? clamp(b.reps / maxReps, 0, 1) * 100 : 0) + '%');
    const tick = h('i', { class: 'pg-tick', 'aria-hidden': 'true' });
    tick.style.setProperty('opacity', sec > 0 && maxSec > 0 ? (0.3 + 0.7 * (sec / maxSec)).toFixed(2) : '0');
    plot.append(h('div', { class: 'pg-slot' }, h('div', { class: 'pg-bint' }, bar), tick));
  });
  wrap.append(plot, axisRow(buckets, grain));
  return wrap;
}

/* ── the view ──────────────────────────────────────────────────── */

export default async function progressView(host, ctx) {
  const key = today();
  const rerender = () => (ctx && typeof ctx.render === 'function' ? ctx.render() : null);
  let scrim = null;
  let dirty = false;
  let resizeTimer = 0;

  host.innerHTML = SKELETON;
  const q = (sel) => host.querySelector(sel);
  const els = {
    sum: q('#pgSum'), note: q('#pgNote'),
    heatCap: q('#pgHeatCap'), heat: q('#pgHeat'), heatLegend: q('#pgHeatLegend'),
    rangeHead: q('#pgRangeHead'), range: q('#pgRange'), chartCap: q('#pgChartCap'), chart: q('#pgChart'),
    best: q('#pgBest'), vol: q('#pgVol'), max: q('#pgMax'), target: q('#pgTarget'),
    consist: q('#pgConsist'), recHead: q('#pgRecHead'), records: q('#pgRecords'), flags: q('#pgFlags'),
    tod: q('#pgTod'), foot: q('#pgFoot'),
  };

  // ── one read, guarded ─────────────────────────────────────────
  let sets = [];
  let dbError = '';
  try {
    const rows = await listSets();
    sets = Array.isArray(rows) ? rows.slice().sort((a, b) => (a.startedAt || 0) - (b.startedAt || 0)) : [];
  } catch (e) {
    dbError = errText(e);
  }
  if (dbError) {
    host.replaceChildren(h('div', { class: 'list' },
      h('div', { class: 'pg-top pad' },
        h('h2', { class: 'h1' }, 'Progress'),
        h('p', { class: 'pg-error' },
          'could not read your saved sets: ' + dbError + '. Nothing on this screen can be drawn until the database opens again.'))));
    return {};
  }

  let goals = null;
  try {
    goals = await loadGoals();
  } catch (e) {
    els.note.textContent = 'goals could not be read: ' + errText(e);
  }
  const dailyGoal = goals && Number(goals.daily) > 0 ? Number(goals.daily) : 0;

  let days = byDay([]);
  let rec = records([]);
  try {
    days = byDay(sets);
    rec = records(sets);
  } catch (e) {
    els.note.textContent = 'aggregation failed: ' + errText(e);
  }

  els.sum.textContent = sets.length
    ? sets.length + ' sets · ' + rec.lifetimeReps + ' reps · ' + days.size + ' days logged'
    : 'nothing logged yet';

  let range = 'week';
  let volKey = 'volume';
  let target = readTarget();

  paintHeat();
  paintRange();
  paintBest();
  paintVol();
  paintMax();
  paintTarget();
  paintRecords();
  paintTod();
  paintFoot();
  paintConsistency();          // async on its own: needs per-rep rows

  window.addEventListener('resize', onResize);

  function onResize() {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(paintHeat, 200);
  }

  // ── calendar heatmap: the hero ────────────────────────────────

  function paintHeat() {
    let cols = [];
    try {
      cols = heatmap(days, HEAT_WEEKS, dailyGoal, key);
    } catch (e) {
      els.note.textContent = 'heatmap failed: ' + errText(e);
    }
    clear(els.heat);
    clear(els.heatCap);
    clear(els.heatLegend);

    const first = cols.length ? cols[0].cells[0].day : key;
    els.heatCap.append(h('span', { class: 'pg-captxt' }, HEAT_WEEKS + ' weeks'),
      h('span', { class: 'pg-capdim' }, ' · ' + fmtDay(first) + ' to ' + fmtDay(key) + ' · rows Mon–Sun'));
    if (!sets.length) els.heatCap.append(h('span', { class: 'pg-capdim' }, ' · nothing here yet'));

    const avail = Math.max(200, (els.heat.clientWidth || 320) - 32);   // .pad is 16px each side
    const gap = avail < 340 ? 1 : 2;
    const cell = clamp(Math.floor((avail - gap * (HEAT_WEEKS - 1)) / HEAT_WEEKS), 5, 15);
    const row = vars(h('div', { class: 'pg-heatrow' }), { '--pg-cell': cell + 'px', '--pg-gap': gap + 'px' });
    for (const col of cols) {
      const isNow = col.cells.some((c) => c.day === key);
      const colEl = h('div', { class: 'pg-hcol' + (isNow ? ' now' : '') });
      for (const c of col.cells) {
        colEl.append(h('button', {
          class: 'pg-hcell' + (c.day === key ? ' today' : ''),
          type: 'button',
          disabled: c.future ? true : null,
          'aria-label': fmtDay(c.day) + ': ' + c.reps + ' reps in ' + c.sets + ' sets',
          onclick: c.future ? null : () => openDaySheet(c.day),
        }, h('span', { class: 'pg-hsq lv' + c.level })));
      }
      row.append(colEl);
    }
    els.heat.append(row);

    const legend = h('div', { class: 'pg-legend' }, h('span', { class: 'pg-capdim' }, 'less'));
    for (let lv = 0; lv <= 4; lv++) legend.append(h('span', { class: 'pg-hsq lv' + lv }));
    legend.append(h('span', { class: 'pg-capdim' }, 'more'),
      h('span', { class: 'pg-capdim' }, dailyGoal ? ' · full at ' + dailyGoal : ' · no goal set'));
    els.heatLegend.append(legend);
  }

  // ── range switcher + bar chart ────────────────────────────────

  function paintRange() {
    clear(els.rangeHead);
    clear(els.range);
    els.rangeHead.append(headBlock('Reps over time', 'bars are reps · the tick under each is sets'));
    RANGE_ORDER.forEach((name) => {
      const on = name === range;
      els.range.append(h('button', {
        class: 'pg-segb' + (on ? ' on' : ''),
        type: 'button',
        'aria-pressed': on ? 'true' : 'false',
        onclick: () => { if (!on) { range = name; paintRange(); } },
      }, RANGES[name].label));
    });
    paintChart();
  }

  function paintChart() {
    const spec = RANGES[range];
    clear(els.chartCap);
    clear(els.chart);
    let buckets = [];
    try {
      buckets = spec.make(days);
    } catch (e) {
      els.chartCap.append(h('span', { class: 'pg-error' }, 'chart failed: ' + errText(e)));
      return;
    }
    const total = sum(buckets.map((b) => b.reps));
    let peak = null;
    for (const b of buckets) if (!peak || b.reps > peak.reps) peak = b;
    els.chartCap.append(h('span', { class: 'pg-captxt' }, spec.window));
    els.chartCap.append(h('span', { class: 'pg-capdim' },
      peak && peak.reps > 0 ? ' · ' + peakCaption(peak, range) + ' · ' + total + ' logged' : ' · nothing logged'));
    els.chart.append(barChart(buckets, { grain: range, goal: range === 'day' ? dailyGoal : 0 }));
  }

  // ── best set over time ────────────────────────────────────────

  function paintBest() {
    clear(els.best);
    els.best.append(headBlock('Best set over time',
      'biggest single set in each of the last ' + HEAT_WEEKS + ' weeks'));
    let weeks = [];
    try {
      weeks = bestSetPerWeek(sets, HEAT_WEEKS);
    } catch (e) {
      els.best.append(h('p', { class: 'pg-error' }, 'failed: ' + errText(e)));
      return;
    }
    const live = weeks.filter((w) => w.best > 0);
    if (!live.length) {
      els.best.append(h('p', { class: 'sub' }, 'no sets yet — this line starts once you train.'));
      return;
    }
    const current = Math.max(...live.map((w) => w.best));
    const holder = weeks.filter((w) => w.best === current).pop();
    els.best.append(h('div', { class: 'pg-numrow' },
      h('div', { class: 'pg-num' }, String(current)),
      h('div', { class: 'pg-numsub' }, 'reps in one set · best week started ' + fmtDay(holder.key))));
    els.best.append(spark(weeks.map((w) => w.best), { step: true, tone: 'brass', height: 62 }));
    els.best.append(h('div', { class: 'pg-axisline' },
      h('span', { class: 'pg-capdim' }, 'week of ' + fmtDay(weeks[0].key)),
      h('span', { class: 'pg-capdim' }, 'this week')));
  }

  // ── weekly volume and average set size ────────────────────────

  function paintVol() {
    clear(els.vol);
    els.vol.append(headBlock('Weekly load', 'last 16 weeks'));
    const toggle = h('div', { class: 'pg-seg pg-segmini' });
    Object.keys(VOL_SERIES).forEach((name) => {
      const on = name === volKey;
      toggle.append(h('button', {
        class: 'pg-segb' + (on ? ' on' : ''), type: 'button', 'aria-pressed': on ? 'true' : 'false',
        onclick: () => { if (!on) { volKey = name; paintVol(); } },
      }, VOL_SERIES[name].label));
    });
    els.vol.append(toggle);
    let buckets = [];
    try {
      buckets = weekBuckets(days, 16);
    } catch (e) {
      els.vol.append(h('p', { class: 'pg-error' }, 'failed: ' + errText(e)));
      return;
    }
    const spec = VOL_SERIES[volKey];
    const live = buckets.filter((b) => b.reps > 0);
    if (!live.length) {
      els.vol.append(h('p', { class: 'sub pg-caption' }, 'nothing logged in these weeks.'));
      return;
    }
    els.vol.append(spark(buckets.map(spec.pick), { tone: 'track', height: 50 }));
    const last = live[live.length - 1];
    els.vol.append(h('div', { class: 'pg-axisline' },
      h('span', { class: 'pg-capdim' }, spec.pick(last) + ' ' + spec.unit),
      h('span', { class: 'pg-capdim' }, live.length + ' of ' + buckets.length + ' weeks trained')));
  }

  // ── estimated max ─────────────────────────────────────────────

  function paintMax() {
    clear(els.max);
    els.max.append(headBlock('Estimated one-set max', 'an estimate, not a measurement'));
    let est = { est: 0, basis: 0, at: 0 };
    try {
      est = estimatedMax(sets, MAX_WINDOW, key);
    } catch (e) {
      els.max.append(h('p', { class: 'pg-error' }, 'estimate failed: ' + errText(e)));
      return;
    }
    if (!est.basis) {
      els.max.append(h('p', { class: 'sub pg-caption' },
        'no set logged in the last ' + MAX_WINDOW + ' days — train once and this appears.'));
      return;
    }
    els.max.append(h('div', { class: 'pg-numrow' },
      h('div', { class: 'pg-num' }, String(est.est)),
      h('div', { class: 'pg-numsub' }, 'from your ' + est.basis + '-rep set on ' + fmtDay(est.at))));
    els.max.append(caption('A set ends when you stop, not when you fail, so this is your best recent '
      + 'set plus an allowance of ' + (est.est - est.basis) + ' reps. It is a floor with a guess on top.'));
  }

  // ── milestone projection ──────────────────────────────────────

  function paintTarget() {
    clear(els.target);
    els.target.append(headBlock('Road to a target set',
      'fitted over your last 12 weekly best sets'));
    const inp = h('input', {
      class: 'pg-tin', type: 'number', inputmode: 'numeric', min: '1', max: '999',
      'aria-label': 'target reps in one set',
    });
    inp.value = String(target);
    const err = h('span', { class: 'pg-err' });
    const apply = () => {
      const v = parseInt(inp.value, 10);
      if (!Number.isFinite(v) || v < 1 || v > 999) { err.textContent = 'pick a number from 1 to 999'; return; }
      err.textContent = '';
      target = v;
      writeTarget(v);
      paintProjection();
    };
    inp.addEventListener('change', apply);
    inp.addEventListener('blur', apply);
    els.target.append(h('div', { class: 'pg-targetrow' },
      h('span', { class: 'pg-capdim' }, 'target'), inp, h('span', { class: 'pg-capdim' }, 'reps in one set')), err);
    els.target.append(h('div', { id: 'pgProj' }));
    paintProjection();
  }

  function paintProjection() {
    const slot = q('#pgProj');
    if (!slot) return;
    clear(slot);
    let proj = { enough: false, weeksTo: null, date: null, slope: 0, points: 0 };
    try {
      proj = projectTarget(sets, target, 12);
    } catch (e) {
      slot.append(h('p', { class: 'pg-error' }, 'projection failed: ' + errText(e)));
      return;
    }
    if (!proj.enough) {
      slot.append(h('p', { class: 'pg-proj' }, 'log four weeks of sets first.'));
      slot.append(caption(proj.points
        ? 'Only ' + proj.points + ' week' + (proj.points === 1 ? '' : 's') + ' with a best set to fit a line to.'
        : 'There is nothing to fit a line to yet.'));
      return;
    }
    const nowLine = caption('Your best set now is ' + proj.current + ' reps.');
    if (proj.weeksTo === 0) {
      slot.append(h('p', { class: 'pg-proj done' }, 'already there — you have a ' + proj.current + '-rep set.'));
      slot.append(nowLine);
      return;
    }
    if (proj.weeksTo === null) {
      slot.append(h('p', { class: 'pg-proj' }, proj.slope <= 0
        ? 'your weekly best is flat or falling, so there is no date to give you.'
        : 'the slope is too shallow to name a date without lying.'));
      slot.append(nowLine);
      return;
    }
    slot.append(h('p', { class: 'pg-proj' },
      h('b', { class: 'num pg-projdate' }, fmtDayYear(proj.date, key)),
      ' — about ' + proj.weeksTo + ' week' + (proj.weeksTo === 1 ? '' : 's') + ' at this slope.'));
    slot.append(caption('The fit rises ' + proj.slope.toFixed(1) + ' reps a week over ' + proj.points
      + ' weeks. It assumes you keep training; one new real best set moves it more than one bad week does.'));
  }

  // ── form consistency ──────────────────────────────────────────

  async function paintConsistency() {
    clear(els.consist);
    els.consist.append(headBlock('Form consistency',
      'how even your pace and depth were — lower is steadier'));
    const recent = sets.slice(-REP_CAP);
    if (!recent.length) {
      els.consist.append(h('p', { class: 'sub' }, 'no sets yet.'));
      return;
    }
    const repsBySet = {};
    let lack = 0;
    let readError = '';
    for (const s of recent) {
      try {
        const rows = await listReps(s.id);
        repsBySet[s.id] = Array.isArray(rows) ? rows : [];
      } catch (e) {
        repsBySet[s.id] = [];
        readError = errText(e);
      }
      if ((repsBySet[s.id] || []).length < 3) lack += 1;
    }
    let series = [];
    try {
      series = consistencySeries(sets, repsBySet, REP_CAP);
    } catch (e) {
      els.consist.append(h('p', { class: 'pg-error' }, 'consistency failed: ' + errText(e)));
      return;
    }
    if (!series.length) {
      els.consist.append(h('p', { class: 'sub' },
        'no per-rep data on the last ' + recent.length + ' sets — they were logged by hand or recorded '
        + 'before the counter saved every rep.'));
      return;
    }
    if (lack) {
      els.consist.append(caption(lack + ' of the last ' + recent.length
        + ' sets have no per-rep rows and are left out' + (readError ? ' (' + readError + ')' : '') + '.'));
    }
    const tempo = series.filter((p) => p.tempoCv !== null).map((p) => p.tempoCv);
    const depth = series.filter((p) => p.depthCv !== null).map((p) => p.depthCv);
    const grid = h('div', { class: 'pg-consgrid' });
    grid.append(consistBlock('pace', tempo, 'spread of rep durations'));
    grid.append(consistBlock('depth', depth, 'spread of how deep each rep went'));
    els.consist.append(grid);
    els.consist.append(caption(series.length + ' sets measured. The number is the coefficient of '
      + 'variation: scatter around your own average, as a share of it. 15% means most reps landed within '
      + 'about a sixth of your usual rhythm.'));
  }

  function consistBlock(title, vals, foot) {
    const box = h('div', { class: 'pg-cons' });
    box.append(h('div', { class: 'pg-conshead' },
      h('span', { class: 'pg-conslbl' }, title),
      h('span', { class: 'num pg-consval' }, vals.length >= 3 ? pct(mean(vals)) : '–')));
    box.append(spark(vals, { tone: 'plum', height: 40, dot: false }));
    box.append(h('div', { class: 'pg-consfoot' }, vals.length >= 3 ? foot : 'needs three reps with data'));
    return box;
  }

  // ── records and flag mix ──────────────────────────────────────

  function paintRecords() {
    clear(els.recHead);
    clear(els.records);
    els.recHead.append(headBlock('Records', 'every set on this phone'));
    const dayOfEntry = (e) => (e && (e.day || e.at) ? fmtDay(e.day || e.at) : '');
    rows().forEach(([label, value, meta]) => {
      els.records.append(h('div', { class: 'kv' },
        h('span', { class: 'pg-key' }, label),
        h('span', { class: 'pg-valwrap' },
          h('b', { class: 'pg-val' }, value),
          meta ? h('span', { class: 'pg-valmeta' }, meta) : null)));
    });

    function rows() {
      const r = rec;
      return [
        ['best set', r.bestSet ? r.bestSet.reps + ' reps' : '–', dayOfEntry(r.bestSet)],
        ['longest set', r.longestSet ? fmtDur(r.longestSet.durationMs) : '–',
          r.longestSet ? r.longestSet.reps + ' reps · ' + dayOfEntry(r.longestSet) : ''],
        ['best day', r.bestDay ? r.bestDay.reps + ' reps' : '–', r.bestDay ? fmtDay(r.bestDay.day) : ''],
        ['best week', r.bestWeek ? r.bestWeek.reps + ' reps' : '–', r.bestWeek ? 'from ' + fmtDay(r.bestWeek.key) : ''],
        ['best month', r.bestMonth ? r.bestMonth.reps + ' reps' : '–', r.bestMonth ? monthText(r.bestMonth.key) : ''],
        ['best year', r.bestYear ? r.bestYear.reps + ' reps' : '–', r.bestYear ? String(r.bestYear.key) : ''],
        ['lifetime', r.lifetimeReps + ' reps', r.lifetimeSets + ' sets · ' + r.lifetimeMinutes + ' min'],
      ];
    }

    clear(els.flags);
    let mix = null;
    try {
      mix = flagMix(sets, 30, key);
    } catch (e) {
      els.flags.append(h('p', { class: 'pg-error' }, 'flag mix failed: ' + errText(e)));
      return;
    }
    els.flags.append(headBlock('What the camera is catching', 'last 30 days · ' + mix.sets + ' sets'));
    if (!mix.sets) {
      els.flags.append(h('p', { class: 'sub' }, 'no sets in the last 30 days.'));
      return;
    }
    const keys = Object.keys(FLAG_LABEL).filter((k) => (Number(mix[k]) || 0) > 0);
    const row = h('div', { class: 'flags' });
    if (!keys.length) {
      row.append(h('span', null, 'nothing flagged in ' + mix.reps + ' reps'));
    } else {
      keys.forEach((k) => row.append(h('span', {
        class: FLAG_HARD.indexOf(k) >= 0 ? 'hard' : 'soft',
      }, mix[k] + ' ' + FLAG_LABEL[k])));
      const flagged = sum(keys.map((k) => mix[k]));
      row.append(h('span', null, flagged + ' of ' + mix.reps + ' reps'));
    }
    els.flags.append(row);
    if (keys.length) {
      els.flags.append(caption('A flag is a rep the camera was unsure about, not a rep you did badly. '
        + 'Check the depth preset in Settings if shallow reps keep showing up.'));
    }
  }

  // ── time of day ───────────────────────────────────────────────

  function paintTod() {
    clear(els.tod);
    let buckets = [];
    try {
      buckets = timeOfDay(sets);
    } catch (e) {
      els.tod.append(headBlock('Time of day'), h('p', { class: 'pg-error' }, 'failed: ' + errText(e)));
      return;
    }
    const total = sum(buckets.map((b) => b.reps));
    els.tod.append(headBlock('Time of day', total ? 'share of every rep you logged' : 'no reps yet'));
    const bar = h('div', { class: 'pg-propbar' });
    if (!total) {
      bar.append(h('i', { class: 'pg-propseg empty lv0' }));
    } else {
      buckets.forEach((b, i) => {
        if (b.reps <= 0) return;
        bar.append(h('i', { class: 'pg-propseg ' + TOD_TONE[i], style: { flexGrow: String(b.reps) } },
          b.pct >= 0.16 ? h('span', { class: 'pg-propnum' }, pct(b.pct)) : null));
      });
    }
    els.tod.append(bar);
    buckets.forEach((b, i) => {
      els.tod.append(h('div', { class: 'pg-todrow' },
        h('span', { class: 'pg-hsq ' + TOD_TONE[i] }),
        h('span', { class: 'pg-todlbl' }, b.label),
        h('span', { class: 'pg-todsub' }, b.sets ? b.sets + ' sets · ' + b.reps + ' reps' : 'nothing'),
        h('b', { class: 'num pg-todpct' }, total ? pct(b.pct) : '0%')));
    });
  }

  function paintFoot() {
    clear(els.foot);
    els.foot.append(h('p', { class: 'sub' },
      'All of this is computed from the sets on this phone. Export a copy from Settings before you clear '
      + 'Safari website data — iOS can drop the database.'));
  }

  // ── day sheet ─────────────────────────────────────────────────

  function closeSheet() {
    if (scrim && scrim.parentNode) scrim.parentNode.removeChild(scrim);
    scrim = null;
  }

  async function openDaySheet(day) {
    closeSheet();
    const title = h('div', { class: 'pg-paneltitle' }, fmtDay(day));
    const totalLine = h('div', { class: 'pg-panellbl' }, 'loading…');
    const body = h('div', { class: 'pg-panelbody' });
    const panel = h('div', { class: 'pg-panel', role: 'dialog', 'aria-modal': 'true', 'aria-label': 'sets on ' + day },
      h('div', { class: 'pg-panelhead' }, title,
        h('button', { class: 'pg-close', type: 'button', onclick: () => dismiss() }, 'done')),
      totalLine, body);
    scrim = h('div', { class: 'pg-scrim' }, panel);
    scrim.addEventListener('click', (ev) => { if (ev.target === scrim) dismiss(); });
    document.body.append(scrim);

    let local = [];
    try {
      const rowsList = await listSetsForDay(day);
      local = Array.isArray(rowsList) ? rowsList : [];
    } catch (e) {
      body.append(h('p', { class: 'pg-error' }, 'could not read this day: ' + errText(e)));
      totalLine.textContent = '';
      return;
    }

    const repaint = () => {
      clear(body);
      if (!local.length) body.append(h('p', { class: 'sub pg-panelempty' }, 'nothing logged on this day.'));
      local.forEach((s) => body.append(sheetRow(s)));
      body.append(addRow(day));
      totalLine.textContent = local.length
        ? local.length + ' set' + (local.length === 1 ? '' : 's') + ' · ' + sum(local.map(repsOf))
          + ' reps kept · camera saw ' + sum(local.map(detectedOf))
        : 'no sets on this day';
    };
    const reload = async () => {
      try {
        const rowsList = await listSetsForDay(day);
        local = Array.isArray(rowsList) ? rowsList : [];
      } catch { /* keep what we have on screen */ }
      repaint();
    };
    repaint();

    function dismiss() {
      closeSheet();
      if (dirty) rerender();
    }
    function markSaved() { dirty = true; }

    // rows need the mutators, so hang them off the sheet's own scope
    function sheetRow(set) {
      const row = h('div', { class: 'pg-srow' });
      const num = h('span', { class: 'pg-snum' }, String(repsOf(set)));
      const info = h('span', { class: 'pg-smeta' },
        fmtClock(set.startedAt || 0) + ' · ' + sourceLabel(set) + ' · camera saw ' + detectedOf(set)
        + (flagCount(set) ? ' · ' + flagCount(set) + ' flagged' : ''));
      const open = h('button', { class: 'pg-sopen', type: 'button' }, num, info);
      const del = h('button', { class: 'btn btn-quiet pg-smini', type: 'button' }, 'delete');
      const err = h('span', { class: 'pg-err' });
      const inp = h('input', {
        class: 'pg-in', type: 'number', inputmode: 'numeric', min: '0', max: '999',
        'aria-label': 'final reps for this set',
      });
      const saveBtn = h('button', { class: 'btn btn-primary pg-smini', type: 'button' }, 'save');
      const cancelBtn = h('button', { class: 'btn btn-quiet pg-smini', type: 'button' }, 'cancel');
      const edit = h('div', { class: 'pg-sedit', hidden: true }, inp, saveBtn, cancelBtn, err);
      row.append(h('div', { class: 'pg-smain' }, open, del), edit);

      const showEdit = () => {
        err.textContent = '';
        inp.value = String(repsOf(set));
        edit.hidden = false;
        del.hidden = true;
        num.hidden = true;
        try { inp.focus(); } catch { /* focus is a nicety */ }
      };
      const hideEdit = () => {
        edit.hidden = true;
        del.hidden = false;
        num.hidden = false;
      };
      open.addEventListener('click', () => { if (edit.hidden) showEdit(); else hideEdit(); });
      cancelBtn.addEventListener('click', hideEdit);
      saveBtn.addEventListener('click', async () => {
        const v = parseReps(inp.value);
        if (v === null) { err.textContent = 'enter a number'; return; }
        saveBtn.disabled = true;
        err.textContent = '';
        try {
          const next = await updateSet(set.id, { repsFinal: v });   // repsDetected stays as recorded
          markSaved();
          local = local.map((s) => (s.id === set.id ? (next || { ...s, repsFinal: v }) : s));
          repaint();
        } catch (e) {
          err.textContent = 'could not save: ' + errText(e);
          saveBtn.disabled = false;
        }
      });
      del.addEventListener('click', async () => {
        if (!confirm('Delete this set of ' + repsOf(set) + ' reps?')) return;
        del.disabled = true;
        try {
          await deleteSet(set.id);
          markSaved();
          local = local.filter((s) => s.id !== set.id);
          repaint();
        } catch (e) {
          del.disabled = false;
          err.textContent = 'could not delete: ' + errText(e);
          showEdit();
        }
      });
      return row;
    }

    function addRow(dayKeyStr) {
      const btn = h('button', { class: 'pg-linkbtn', type: 'button' }, 'add a set here');
      const inp = h('input', {
        class: 'pg-in', type: 'number', inputmode: 'numeric', min: '0', max: '999',
        'aria-label': 'reps to add for ' + fmtDay(dayKeyStr),
      });
      const saveBtn = h('button', { class: 'btn btn-primary pg-smini', type: 'button' }, 'save');
      const cancelBtn = h('button', { class: 'btn btn-quiet pg-smini', type: 'button' }, 'cancel');
      const err = h('span', { class: 'pg-err' });
      const editor = h('div', { class: 'pg-sedit', hidden: true }, inp, saveBtn, cancelBtn, err);
      const box = h('div', { class: 'pg-sadd' },
        h('div', { class: 'pg-smain' }, btn, editor),
        h('p', { class: 'sub pg-addnote' }, 'logged as yours — detected reps stay zero, so nothing is claimed for the camera.'));
      btn.addEventListener('click', () => {
        err.textContent = '';
        inp.value = '';
        btn.hidden = true;
        editor.hidden = false;
        try { inp.focus(); } catch { /* ignore */ }
      });
      cancelBtn.addEventListener('click', () => { editor.hidden = true; btn.hidden = false; });
      saveBtn.addEventListener('click', async () => {
        const v = parseReps(inp.value);
        if (v === null) { err.textContent = 'enter a number'; return; }
        saveBtn.disabled = true;
        err.textContent = '';
        try {
          await saveSet({
            startedAt: noonOf(dayKeyStr), day: dayKeyStr, mode: 'manual', source: 'manual',
            repsDetected: 0, repsFinal: v, durationMs: 0, flags: {}, notes: '',
          }, []);
          markSaved();
          await reload();
        } catch (e) {
          err.textContent = 'could not save: ' + errText(e);
          saveBtn.disabled = false;
        }
      });
      return box;
    }
  }

  return {
    unmount() {
      window.removeEventListener('resize', onResize);
      clearTimeout(resizeTimer);
      closeSheet();
    },
  };
}

/* ── the target lives in localStorage: it is a wish, not a record ── */

function readTarget() {
  let raw = null;
  try {
    raw = localStorage.getItem(TARGET_KEY);
  } catch {
    return DEFAULT_TARGET;
  }
  const n = parseInt(raw, 10);
  return Number.isFinite(n) && n >= 1 && n <= 999 ? n : DEFAULT_TARGET;
}

function writeTarget(n) {
  try {
    localStorage.setItem(TARGET_KEY, String(n));
  } catch { /* private mode: keep it for this session only */ }
}
