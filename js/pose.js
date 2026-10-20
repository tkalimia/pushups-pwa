import { FilesetResolver, PoseLandmarker } from '../vendor/mediapipe/vision_bundle.mjs';
import { clamp } from './util.js';

// Absolute URLs: MediaPipe injects the wasm loader with <script src> and Emscripten then resolves
// the .wasm against that script's own folder, which would double the path on a hosted subfolder.
const abs = (p) => (typeof location === 'undefined' ? p : new URL(p, location.href).href);

export const MODEL_PATHS = {
  lite: abs('models/pose_landmarker_lite.task'),
  full: abs('models/pose_landmarker_full.task'),
};

const WASM_BASE_PATH = abs('vendor/mediapipe/wasm');
const NUM_LANDMARKS = 33;
const QUALITY_IDX = [11, 12, 13, 14, 15, 23, 24, 25, 26, 27, 28];
const MIN_VIS_TO_DRAW = 0.5;

const CONNECTIONS = [
  [0, 2], [0, 5], [2, 3], [3, 7], [5, 4], [8, 5],
  [11, 12], [11, 13], [13, 15], [12, 14], [14, 16],
  [11, 23], [12, 24], [23, 24],
  [23, 25], [25, 27], [24, 26], [26, 28],
  [27, 29], [29, 31], [27, 31], [28, 30], [30, 32], [28, 32],
];

let filesetPromise = null;

function getFileset() {
  if (!filesetPromise) {
    try {
      filesetPromise = Promise.resolve(FilesetResolver.forVisionTasks(WASM_BASE_PATH));
    } catch (err) {
      return Promise.reject(err);
    }
    filesetPromise.catch(() => { filesetPromise = null; });
  }
  return filesetPromise;
}

const cache = new Map();
const cacheKey = (model, delegate) => `${model}|${delegate}`;

function closeInstance(inst) {
  if (!inst) return;
  try {
    // tasks-vision frees the graph runner through close(); there is no dispose() in 0.10.x
    if (typeof inst.close === 'function') inst.close();
    else if (typeof inst.dispose === 'function') inst.dispose();
  } catch (err) {
    void err;
  }
}

function removeCached(key, inst) {
  if (cache.get(key) === inst) cache.delete(key);
}

async function createInstance(model, delegate) {
  const fileset = await getFileset();
  const key = cacheKey(model, delegate);
  const hit = cache.get(key);
  if (hit) {
    cache.delete(key);
    cache.set(key, hit);
    return hit;
  }
  const inst = await PoseLandmarker.createFromOptions(fileset, {
    baseOptions: {
      modelAssetPath: MODEL_PATHS[model] || model,
      delegate: delegate === 'cpu' ? 'CPU' : 'GPU',
    },
    runningMode: 'VIDEO',
    numPoses: 1,
    minPoseDetectionConfidence: 0.5,
    minPosePresenceConfidence: 0.5,
    minTrackingConfidence: 0.5,
  });
  cache.set(key, inst);
  while (cache.size > 2) {
    const oldest = cache.keys().next().value;
    const victim = cache.get(oldest);
    cache.delete(oldest);
    if (victim !== inst) closeInstance(victim);
  }
  return inst;
}

// Returns the tracker synchronously so the UI can call start()/stop() before the model has
// finished loading. `await createTracker(...)` yields the same object, so both work.
export function createTracker(options = {}) {
  const {
    video,
    model = 'lite',
    delegate = 'gpu',
    fpsCap = 25,
    canvas = null,
    onFrame,
    onStatus,
    onError,
    strokeStyle = '#2dd4bf',
    lineWidth = 2,
    mirrored = false,
  } = options;

  // Reused across frames: iOS Safari jitters badly if 33 objects are allocated 25x/second.
  // Consumers must copy values out of `frame`/`frame.landmarks` if they keep them.
  const landmarkBuf = new Array(NUM_LANDMARKS);
  for (let i = 0; i < NUM_LANDMARKS; i++) landmarkBuf[i] = { x: 0, y: 0, z: 0, visibility: 0 };

  const frame = { landmarks: landmarkBuf, present: false, quality: 0, fps: 0, stampMs: 0 };
  const stamps = [];

  const st = {
    model,
    delegate: delegate === 'cpu' ? 'cpu' : 'gpu',
    fpsCap: clamp(Math.round(Number(fpsCap) || 25), 8, 30),
    mirrored: !!mirrored,
    phase: 'idle',
    running: false,
    disposed: false,
    fps: 0,
    lastTs: 0,
    lastDetect: 0,
    firstStamp: 0,
    raf: 0,
    pending: false,
    pendingClose: [],
    gpuFailed: delegate === 'cpu',
    swapping: false,
    booting: false,
  };

  let landmarker = null;

  function emit(fn, ...args) {
    if (typeof fn !== 'function') return;
    try { fn(...args); } catch (err) { void err; }
  }

  function status(phase, detail) {
    st.phase = phase;
    emit(onStatus, phase, detail);
  }

  function fatal(err) {
    if (st.disposed) return;
    st.running = false;
    st.pending = false;
    if (st.raf) cancelAnimationFrame(st.raf);
    st.raf = 0;
    st.phase = 'failed';
    emit(onError, err);
  }

  function flushPendingClose() {
    if (st.pending || !st.pendingClose.length) return;
    for (const inst of st.pendingClose) closeInstance(inst);
    st.pendingClose.length = 0;
  }

  async function build(prefer) {
    const order = (prefer === 'cpu' || st.gpuFailed) ? ['cpu'] : ['gpu', 'cpu'];
    let lastErr = null;
    for (const d of order) {
      try {
        const inst = await createInstance(st.model, d);
        if (d === 'cpu' && st.delegate === 'gpu') status('delegate-downgrade', 'cpu');
        st.delegate = d;
        if (d === 'cpu') st.gpuFailed = true;
        return inst;
      } catch (err) {
        lastErr = err;
        if (d === 'gpu') st.gpuFailed = true;
      }
    }
    throw lastErr || new Error('pushups: pose landmarker could not be created');
  }

  function measureFps(now) {
    stamps.push(now);
    while (stamps.length && now - stamps[0] > 3000) stamps.shift();
    if (!st.firstStamp) st.firstStamp = now;
    if (stamps.length < 3 || now - st.firstStamp < 3000) {
      st.fps = 0;
      return 0;
    }
    const span = now - stamps[0];
    st.fps = span > 0 ? ((stamps.length - 1) * 1000) / span : 0;
    return st.fps;
  }

  function fillLandmarks(src) {
    const n = Math.min(src.length, NUM_LANDMARKS);
    const flip = st.mirrored;
    for (let i = 0; i < NUM_LANDMARKS; i++) {
      const out = landmarkBuf[i];
      if (i < n) {
        const p = src[i];
        // mirrored front-cam: the preview is shown flipped, so the counter AND the overlay
        // both use 1-x; the counter therefore always sees the same left/right as the user.
        out.x = flip ? 1 - (p.x || 0) : (p.x || 0);
        out.y = p.y || 0;
        out.z = p.z || 0;
        const vis = p.visibility === undefined ? p.presence : p.visibility;
        out.visibility = typeof vis === 'number' ? vis : 1;
      } else {
        out.x = 0;
        out.y = 0;
        out.z = 0;
        out.visibility = 0;
      }
    }
  }

  function computeQuality() {
    let sum = 0;
    for (let i = 0; i < QUALITY_IDX.length; i++) sum += landmarkBuf[QUALITY_IDX[i]].visibility;
    return clamp(sum / QUALITY_IDX.length, 0, 1);
  }

  function draw() {
    if (!canvas || !video || typeof canvas.getContext !== 'function') return;
    const boxW = canvas.clientWidth || video.videoWidth;
    const boxH = canvas.clientHeight || video.videoHeight;
    if (!boxW || !boxH) return;
    if (canvas.width !== boxW || canvas.height !== boxH) {
      canvas.width = boxW;
      canvas.height = boxH;
    }
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.clearRect(0, 0, boxW, boxH);
    if (!frame.present || !video.videoWidth) return;
    // the video is shown with object-fit:cover, so map normalised landmarks through the same
    // crop or the skeleton slides off the body
    const s = Math.max(boxW / video.videoWidth, boxH / video.videoHeight);
    const ox = (boxW - video.videoWidth * s) / 2;
    const oy = (boxH - video.videoHeight * s) / 2;
    const px = (p) => p.x * video.videoWidth * s + ox;
    const py = (p) => p.y * video.videoHeight * s + oy;
    ctx.strokeStyle = strokeStyle;
    ctx.lineWidth = lineWidth * Math.max(1, boxW / 360);
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.beginPath();
    for (let i = 0; i < CONNECTIONS.length; i++) {
      const a = landmarkBuf[CONNECTIONS[i][0]];
      const b = landmarkBuf[CONNECTIONS[i][1]];
      if (a.visibility < MIN_VIS_TO_DRAW || b.visibility < MIN_VIS_TO_DRAW) continue;
      ctx.moveTo(px(a), py(a));
      ctx.lineTo(px(b), py(b));
    }
    ctx.stroke();
  }

  function handleResult(res, ts) {
    const sets = res && Array.isArray(res.landmarks) ? res.landmarks : [];
    const src = sets.length ? sets[0] : null;
    const present = !!(src && src.length);
    frame.present = present;
    if (present) fillLandmarks(src);
    else for (let i = 0; i < NUM_LANDMARKS; i++) landmarkBuf[i].visibility = 0;
    frame.quality = present ? computeQuality() : 0;
    frame.stampMs = ts;
    frame.fps = measureFps(performance.now());
    draw();
    emit(onFrame, frame, res);
  }

  async function recoverOnCPU(failedInst) {
    removeCached(cacheKey(st.model, st.delegate), failedInst);
    if (failedInst === landmarker) st.pendingClose.push(failedInst);
    else closeInstance(failedInst);
    landmarker = null;
    try {
      landmarker = await build('cpu');
      flushPendingClose();
      if (st.running) status('running', 'cpu');
      return true;
    } catch (err) {
      fatal(err);
      return false;
    }
  }

  function handleDetectFailure(err) {
    if (st.delegate === 'gpu' && !st.gpuFailed) {
      void recoverOnCPU(landmarker);
      return;
    }
    fatal(err);
  }

  function loop() {
    if (!st.running || st.disposed) return;
    st.raf = requestAnimationFrame(loop);
    if (st.pending || st.swapping || !landmarker) return;
    const now = performance.now();
    if (now - st.lastDetect < 1000 / st.fpsCap) return;
    if (!video || video.readyState < 2 || video.videoWidth === 0) return;

    st.lastDetect = now;
    st.pending = true;
    let ts = Math.round(now);
    if (ts <= st.lastTs) ts = st.lastTs + 1;
    st.lastTs = ts;

    const inst = landmarker;
    let promise = null;
    try {
      promise = inst.detectForVideo(video, ts);
    } catch (err) {
      st.pending = false;
      handleDetectFailure(err);
      return;
    }
    if (!promise || typeof promise.then !== 'function') {
      st.pending = false;
      return;
    }
    promise
      .then((res) => {
        st.pending = false;
        if (st.disposed) return;
        handleResult(res, ts);
        flushPendingClose();
      })
      .catch((err) => {
        st.pending = false;
        if (st.disposed) return;
        handleDetectFailure(err);
      });
  }

  async function warmUp() {
    if (!landmarker || !video || video.readyState < 2 || video.videoWidth === 0) return;
    let ts = Math.round(performance.now());
    if (ts <= st.lastTs) ts = st.lastTs + 1;
    st.lastTs = ts;
    st.pending = true;
    const inst = landmarker;
    try {
      const res = await inst.detectForVideo(video, ts);
      st.pending = false;
      handleResult(res, ts);
    } catch (err) {
      st.pending = false;
      if (st.delegate === 'gpu' && !st.gpuFailed) await recoverOnCPU(inst);
      else fatal(err);
    }
  }

  async function boot() {
    st.booting = true;
    status('loading-model', st.model);
    try {
      landmarker = await build(st.delegate);
    } catch (err) {
      st.booting = false;
      fatal(err);
      return;
    }
    st.booting = false;
    if (st.disposed || st.phase === 'failed') return;
    status('warming-up', st.delegate);
    await warmUp();
    if (st.disposed || st.phase === 'failed') return;
    status(st.running ? 'running' : 'ready', st.delegate);
  }

  const api = {
    start() {
      if (st.disposed || st.running) return false;
      st.running = true;
      st.lastDetect = 0;
      st.firstStamp = 0;
      stamps.length = 0;
      if (!st.booting) status('running', st.delegate);
      st.raf = requestAnimationFrame(loop);
      return true;
    },

    stop() {
      if (st.raf) cancelAnimationFrame(st.raf);
      st.raf = 0;
      const was = st.running;
      st.running = false;
      st.pending = false;
      if (was) status('stopped');
      return was;
    },

    setMirrored(v) {
      st.mirrored = !!v;
      return st.mirrored;
    },

    setFpsCap(v) {
      st.fpsCap = clamp(Math.round(Number(v) || 0), 8, 30);
      return st.fpsCap;
    },

    async setModel(next) {
      if (st.disposed || !MODEL_PATHS[next] || next === st.model || st.booting) return st.model;
      const prevModel = st.model;
      const prevInst = landmarker;
      st.swapping = true;
      st.model = next;
      let inst = null;
      try {
        inst = await build(st.gpuFailed ? 'cpu' : 'gpu');
        landmarker = inst;
        st.firstStamp = 0;
        stamps.length = 0;
      } catch (err) {
        st.model = prevModel;
        fatal(err);
        st.swapping = false;
        return prevModel;
      }
      st.swapping = false;
      if (prevInst && prevInst !== inst) {
        removeCached(cacheKey(prevModel, st.delegate), prevInst);
        if (st.pending) st.pendingClose.push(prevInst);
        else closeInstance(prevInst);
      }
      flushPendingClose();
      return st.model;
    },

    dispose() {
      if (st.disposed) return false;
      st.disposed = true;
      st.running = false;
      if (st.raf) cancelAnimationFrame(st.raf);
      st.raf = 0;
      const inst = landmarker;
      landmarker = null;
      if (inst) removeCached(cacheKey(st.model, st.delegate), inst);
      for (const pending of st.pendingClose) closeInstance(pending);
      st.pendingClose.length = 0;
      closeInstance(inst);
      status('stopped', 'disposed');
      return true;
    },

    getStatus() {
      return {
        phase: st.phase,
        running: st.running,
        model: st.model,
        delegate: st.delegate,
        fps: st.fps,
        fpsCap: st.fpsCap,
        mirrored: st.mirrored,
        present: frame.present,
        quality: frame.quality,
        disposed: st.disposed,
      };
    },
  };

  const bootPromise = boot();
  bootPromise.catch(() => {});
  api.ready = bootPromise;
  return api;
}
