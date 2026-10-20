import { countSets } from '../db.js';

export default async function progressView(host) {
  let n = 0;
  try { n = await countSets(); } catch {}
  host.innerHTML = `
    <div class="pad">
      <h2 class="h1" style="margin:18px 0 6px">Progress</h2>
      <p class="sub">${n} set${n === 1 ? '' : 's'} recorded on this phone. Charts, heatmap, records and goals land in phase 2 —
      every set saved from now on is stored with the fields they will read, so nothing gets lost by installing this version first.</p>
      <div class="rule"></div>
      <p class="sub">Phase 2 adds: calendar heatmap, reps per day/week/month/year, best set over time,
      weekly volume, estimated max, time-of-day, tempo and depth consistency, daily/weekly/yearly goals and streaks.</p>
    </div>`;
  return {};
}
