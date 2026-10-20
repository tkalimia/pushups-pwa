export default function badgesView(host) {
  host.innerHTML = `
    <div class="pad">
      <h2 class="h1" style="margin:18px 0 6px">Badges</h2>
      <p class="sub">Phase 3 turns these on. The data they need is already being recorded:</p>
      <div class="rule"></div>
      <div id="grid"></div>
    </div>`;
  const ideas = [
    ['1,000 lifetime', 'total reps across every set'],
    ['Best set 30', 'one set, no flags'],
    ['Clean 20', '20 reps with nothing flagged'],
    ['Steady tempo', 'a set where every rep landed within 15% of the mean'],
    ['Weekly goal × 12', ' twelve weeks in a row'],
  ];
  const grid = host.querySelector('#grid');
  ideas.forEach(([name, why]) => {
    const row = document.createElement('div');
    row.className = 'chk bad';
    const mk = document.createElement('span');
    mk.className = 'mk';
    mk.textContent = '✦';
    const t = document.createElement('span');
    t.textContent = name;
    const w = document.createElement('span');
    w.className = 'why';
    w.textContent = why;
    row.append(mk, t, w);
    grid.append(row);
  });
  return {};
}
