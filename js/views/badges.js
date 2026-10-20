/* Badges is still a placeholder in this build. It should read as a deliberate blank page — the
   rules it will use, phrased as rules, and no invented progress. */
const SVGNS = 'http://www.w3.org/2000/svg';

function icon(paths) {
  const el = document.createElementNS(SVGNS, 'svg');
  el.setAttribute('viewBox', '0 0 24 24');
  el.setAttribute('fill', 'none');
  el.setAttribute('stroke', 'currentColor');
  el.setAttribute('stroke-width', '1.7');
  el.setAttribute('stroke-linecap', 'round');
  el.setAttribute('stroke-linejoin', 'round');
  el.setAttribute('aria-hidden', 'true');
  for (const d of paths) {
    const p = document.createElementNS(SVGNS, d.c === 'circle' ? 'circle' : 'path');
    if (d.c === 'circle') {
      p.setAttribute('cx', d.cx); p.setAttribute('cy', d.cy); p.setAttribute('r', d.r);
    } else {
      p.setAttribute('d', d.d);
    }
    el.append(p);
  }
  return el;
}

const MEDAL = [
  { c: 'circle', cx: '12', cy: '9', r: '5.4' },
  { d: 'M9.2 13.6L7.5 20l4.5-2.6L16.5 20l-1.7-6.4' },
];

// name → the exact condition that will light it up, stated as a condition
const UPCOMING = [
  ['1,000 lifetime', 'lifetime reps reach 1,000'],
  ['Best set 30', 'one set of 30 with nothing flagged'],
  ['Clean 20', '20 reps in a row with no form flags'],
  ['Steady tempo', 'every rep of a set within 15% of that set\u2019s mean'],
  ['Twelve weeks', 'weekly goal met 12 weeks running'],
];

export default function badgesView(host) {
  const head = document.createElement('div');
  head.className = 'pad';
  const h1 = document.createElement('h1');
  h1.className = 'h1';
  h1.textContent = 'Badges';
  const note = document.createElement('p');
  note.className = 'sub';
  note.textContent = 'Not wired up yet. Everything these will read is already being recorded, so they will retroactively light up the moment phase 3 lands.';
  head.append(h1, note);

  const list = document.createElement('div');
  list.className = 'bd-list';
  for (const [name, rule] of UPCOMING) {
    const row = document.createElement('div');
    row.className = 'bd-row';
    const ic = document.createElement('span');
    ic.className = 'bd-ic';
    ic.append(icon(MEDAL));
    const txt = document.createElement('span');
    txt.className = 'bd-txt';
    const strong = document.createElement('b');
    strong.textContent = name;
    const why = document.createElement('span');
    why.className = 'bd-rule';
    why.textContent = rule;
    txt.append(strong, why);
    row.append(ic, txt);
    list.append(row);
  }

  host.replaceChildren(head, list);
  return {};
}
