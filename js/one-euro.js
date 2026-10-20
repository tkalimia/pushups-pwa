// One Euro filter, Casal et al. 2017.
const TWO_PI = 2 * Math.PI;
const MIN_DT = 1e-4;
const MAX_DT = 0.25;

function alphaCoefficient(dt, fc) {
  const tau = 1 / (TWO_PI * fc);
  return 1 / (tau + 1);
}

export class OneEuro {
  constructor({ minCutoff = 1.0, beta = 0.0, dCutoff = 1.0 } = {}) {
    this.minCutoff = minCutoff;
    this.beta = beta;
    this.dCutoff = dCutoff;
    this.t = null;
    this.x = null;
    this.dx = 0;
  }

  reset() {
    this.t = null;
    this.x = null;
    this.dx = 0;
  }

  filter(tMs, value) {
    if (!Number.isFinite(tMs) || !Number.isFinite(value)) return this.x === null ? value : this.x;
    if (this.t === null || this.x === null) {
      this.t = tMs;
      this.x = value;
      this.dx = 0;
      return value;
    }

    let dt = (tMs - this.t) / 1000;
    if (dt <= 0) return this.x;
    if (dt > 1) {
      this.reset();
      this.t = tMs;
      this.x = value;
      this.dx = 0;
      return value;
    }
    if (dt > MAX_DT) dt = MAX_DT;

    const rawDx = (value - this.x) / dt;
    this.dx += alphaCoefficient(dt, this.dCutoff) * (rawDx - this.dx);

    const fc = Math.max(1e-3, this.minCutoff + this.beta * Math.abs(this.dx));
    const a = alphaCoefficient(dt, fc);
    this.x = this.x + a * (value - this.x);
    this.t = tMs;
    return this.x;
  }
}

export function smoothSeries(series, opts) {
  if (!Array.isArray(series)) return [];
  const f = new OneEuro(opts);
  const out = [];
  for (const pair of series) {
    if (!Array.isArray(pair) || pair.length < 2) continue;
    out.push([pair[0], f.filter(pair[0], pair[1])]);
  }
  return out;
}
