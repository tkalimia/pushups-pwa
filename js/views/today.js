import { listSetsForDay, deleteSet } from '../db.js';
import { today } from '../util.js';

export default async function todayView(host) {
  host.innerHTML = `
    <div class="todaytotal">
      <div class="num" id="tot">0</div>
      <div class="sub" id="dateline"></div>
    </div>
    <div class="rule" style="margin:0 16px"></div>
    <div class="list" id="list"></div>
    <div class="pad sub" id="foot"></div>`;

  host.querySelector('#dateline').textContent = new Date().toLocaleDateString(undefined, {
    weekday: 'long', day: 'numeric', month: 'long',
  });

  const list = host.querySelector('#list');
  const tot = host.querySelector('#tot');
  const foot = host.querySelector('#foot');

  async function refresh() {
    let sets = [];
    try { sets = await listSetsForDay(today()); } catch (e) { foot.textContent = 'database unreadable: ' + e.message; }
    sets.sort((a, b) => b.startedAt - a.startedAt);
    tot.textContent = String(sets.reduce((a, s) => a + (s.repsFinal || 0), 0));
    list.replaceChildren();
    if (!sets.length) {
      const p = document.createElement('p');
      p.className = 'soon';
      p.textContent = 'No sets yet today. Train → Start set.';
      list.append(p);
      foot.textContent = '';
      return;
    }
    sets.forEach((s) => {
      const row = document.createElement('div');
      row.className = 'item';
      const left = document.createElement('div');
      const n = document.createElement('div');
      n.className = 'num';
      n.textContent = String(s.repsFinal || 0);
      const m = document.createElement('div');
      m.className = 'sub';
      m.textContent = new Date(s.startedAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) +
        ' · ' + (s.source === 'manual' ? 'manual' : s.cameraUsed === 'user' ? 'front cam' : 'side cam');
      left.append(n, m);
      const right = document.createElement('button');
      right.className = 'btn btn-quiet';
      right.textContent = 'delete';
      right.addEventListener('click', async () => {
        if (!confirm('Delete this set?')) return;
        await deleteSet(s.id);
        refresh();
      });
      row.append(left, right);
      list.append(row);
    });
    const det = sets.reduce((a, s) => a + (s.repsDetected || 0), 0);
    const fin = sets.reduce((a, s) => a + (s.repsFinal || 0), 0);
    foot.textContent = sets.length + ' set' + (sets.length > 1 ? 's' : '') +
      ' · camera saw ' + det + ', you kept ' + fin + '.';
  }

  await refresh();
  return {};
}
