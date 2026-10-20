export function clamp(v, lo, hi) {
  return v < lo ? lo : (v > hi ? hi : v);
}

export function lerp(a, b, t) {
  return a + (b - a) * t;
}

export function sum(arr) {
  let s = 0;
  for (let i = 0; i < arr.length; i++) s += Number(arr[i]) || 0;
  return s;
}

export function mean(arr) {
  return arr.length ? sum(arr) / arr.length : 0;
}

export function round(v, dp = 0) {
  const f = 10 ** dp;
  return Math.round((Number(v) || 0) * f) / f;
}

export function debounce(fn, ms = 250) {
  let t = 0;
  return (...args) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...args), ms);
  };
}

export function sleep(ms) {
  return new Promise((res) => setTimeout(res, ms));
}

export function uid() {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const pad = (n) => String(n).padStart(2, '0');

export function fmtTime(ms) {
  const total = Math.max(0, Math.floor(Number(ms) || 0));
  const s = Math.floor(total / 1000);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  return h > 0 ? `${h}:${pad(m)}:${pad(sec)}` : `${pad(m)}:${pad(sec)}`;
}

export function fmtClock(epoch) {
  const d = new Date(epoch);
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function toLocalDate(day) {
  if (day instanceof Date) return day;
  const m = typeof day === 'string' && /^(\d{4})-(\d{2})-(\d{2})$/.exec(day);
  if (m) return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return new Date(day);
}

export function fmtDay(day) {
  const d = toLocalDate(day);
  if (Number.isNaN(d.getTime())) return String(day);
  return `${DAYS[d.getDay()]} ${d.getDate()} ${MONTHS[d.getMonth()]}`;
}

export function today() {
  return dayOf(Date.now());
}

export function dayOf(epochMs) {
  const d = new Date(epochMs);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export function pct(v) {
  return `${Math.round(clamp(Number(v) || 0, 0, 1) * 100)}%`;
}

export function download(filename, text, mime = 'application/json') {
  const blob = new Blob([String(text ?? '')], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.rel = 'noopener';
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function clear(el) {
  if (!el) return el;
  while (el.firstChild) el.removeChild(el.firstChild);
  return el;
}

function appendKids(el, kids) {
  for (const kid of kids) {
    if (kid === null || kid === undefined || kid === false || kid === true) continue;
    if (Array.isArray(kid)) appendKids(el, kid);
    else if (kid instanceof Node) el.appendChild(kid);
    else el.appendChild(document.createTextNode(String(kid)));
  }
}

export function mount(el, ...kids) {
  appendKids(el, kids);
  return el;
}

export function h(tag, attrs = {}, ...kids) {
  const el = document.createElement(tag);
  for (const key of Object.keys(attrs || {})) {
    const v = attrs[key];
    if (v === undefined || v === null || v === false) continue;
    if (key === 'class' || key === 'className') el.className = String(v);
    else if (key === 'dataset' && typeof v === 'object') Object.assign(el.dataset, v);
    else if (key === 'html') el.innerHTML = String(v);
    else if (key === 'text') el.textContent = String(v);
    else if (key === 'style' && typeof v === 'object') Object.assign(el.style, v);
    else if (key.length > 2 && key.startsWith('on') && typeof v === 'function') {
      el.addEventListener(key.slice(2).toLowerCase(), v);
    } else if (v === true) el.setAttribute(key, '');
    else el.setAttribute(key, String(v));
  }
  appendKids(el, kids);
  return el;
}
