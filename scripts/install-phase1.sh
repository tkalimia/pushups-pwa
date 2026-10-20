#!/usr/bin/env bash
# Pushups PWA — phase 1 installer. Self-contained: writes every source file, then downloads
# the MediaPipe wasm + pose models + fonts and generates the icons. Re-runnable; overwrites
# only files inside the app folder. Nothing here touches your saved sets (they live on the phone).
set -euo pipefail
ROOT="${1:-$HOME/Projects/pushups}"
mkdir -p "$ROOT"; cd "$ROOT"
umask 022

mkdir -p .
cat > '.gitignore' <<'__EOF__gitignore__'
.DS_Store
*.mov
*.mp4
tools/base-url
tools/stamp.txt
tools/precache.txt
__EOF__gitignore__

mkdir -p 'css'
cat > 'css/app.css' <<'__EOF_css_app_css__'
@font-face{font-family:"Barlow Semi Condensed";font-style:normal;font-weight:100 900;font-display:swap;src:url(../fonts/barlow-semi-condensed.woff2) format("woff2")}
@font-face{font-family:"IBM Plex Sans";font-style:normal;font-weight:100 700;font-display:swap;src:url(../fonts/ibm-plex-sans.woff2) format("woff2")}

:root{
  --ink:#0E1A18;
  --porcelain:#E9EEEA;
  --track:#4FA3A5;
  --brass:#C9922F;
  --rose:#D0566B;
  --plum:#6E5A78;

  --bg:#0E1A18;
  --sheet:#13211F;
  --text:#DCE6E2;
  --muted:#7F918C;
  --hair:rgba(220,230,226,.14);
  --tint:rgba(220,230,226,.05);
  --num:#DCE6E2;

  --display:"Barlow Semi Condensed","Helvetica Neue",sans-serif;
  --ui:"IBM Plex Sans",-apple-system,"Helvetica Neue",sans-serif;

  --sat:env(safe-area-inset-top,0px);
  --sab:env(safe-area-inset-bottom,0px);
  --sar:env(safe-area-inset-right,0px);
  --sal:env(safe-area-inset-left,0px);
  color-scheme:dark light;
}

@media (prefers-color-scheme:light){
  :root{
    --bg:#E9EEEA;
    --sheet:#F2F5F2;
    --text:#0E1A18;
    --muted:#5B6965;
    --hair:rgba(14,26,24,.16);
    --tint:rgba(14,26,24,.045);
    --num:#0E1A18;
  }
}

*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html,body{margin:0;height:100%;overflow:hidden;overscroll-behavior:none}
body{background:var(--bg);color:var(--text);font:16px/1.45 var(--ui);transition:background .2s linear,color .2s linear}
button,input,select,textarea{font:inherit;color:inherit}
a{color:inherit;text-decoration:none}
:focus-visible{outline:2px solid var(--track);outline-offset:2px}

#view{position:fixed;top:calc(var(--sat));left:var(--sal);right:var(--sar);bottom:calc(54px + var(--sab));
  display:flex;flex-direction:column}

.pad{padding-left:16px;padding-right:16px}
.row{display:flex;align-items:center;gap:12px}
.col{display:flex;flex-direction:column}
.grow{flex:1;min-height:0}
.center{align-items:center;justify-content:center;text-align:center}
.h1{font:600 21px/1.25 var(--ui);margin:0}
.sub{color:var(--muted);font-size:13px}
.mono{font:12px/1.5 ui-monospace,"SF Mono",Menlo,monospace}
.num{font-family:var(--display);font-weight:700;font-variant-numeric:tabular-nums}
.rule{height:1px;background:var(--hair);margin:12px 0}
.spacer{height:14px}

/* ── tab bar ── */
#tabs{position:fixed;left:0;right:0;bottom:0;display:flex;align-items:flex-end;
  padding:7px 2px calc(7px + var(--sab));background:var(--sheet);border-top:1px solid var(--hair);
  font-size:11px;line-height:1.05;text-align:center;z-index:60}
#tabs a{flex:1;color:var(--muted);transition:color .15s linear}
#tabs a .ic{display:block;font-size:16px;margin-bottom:3px}
#tabs a[aria-current="true"]{color:var(--text)}
#tabs a.todo{opacity:.45}

/* ── update banner ── */
#banner:empty{display:none}
#banner>div{margin:0 var(--sal) 0 var(--sar);padding:11px 16px;background:var(--brass);color:#14110A;
  font-weight:600;font-size:15px;cursor:pointer}

/* ── controls ── */
.btn{border:1px solid var(--hair);background:var(--tint);color:var(--text);border-radius:999px;
  padding:12px 22px;font-weight:600;font-size:16px;transition:opacity .12s linear,transform .12s ease-out}
.btn:active{transform:scale(.97)}
.btn-primary{background:var(--text);color:var(--bg);border-color:transparent}
.btn-warn{background:var(--rose);color:#fff;border-color:transparent}
.btn-quiet{background:none;border-color:transparent;color:var(--muted)}
.btn-big{width:100%;padding:17px;font-size:17px}
.btn[disabled]{opacity:.4}
.step{width:76px;height:60px;border-radius:14px;background:var(--tint);border:1px solid var(--hair);
  font:700 30px/1 var(--display);color:var(--text)}
.step:active{background:var(--hair)}
select,input[type=text],input[type=number],textarea{background:var(--tint);border:1px solid var(--hair);
  border-radius:10px;padding:10px 12px;width:100%;appearance:none}
input[type=range]{width:100%}
input[type=checkbox]{width:22px;height:22px;accent-color:var(--track)}
label.tog{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:11px 0;
  border-bottom:1px solid var(--hair);font-size:15px}
label.tog .sub{display:block;font-size:12px}

/* ── camera + overlay ── */
.camwrap{position:relative;background:#050A09;flex:1;min-height:0;overflow:hidden}
.camwrap video{display:block;width:100%;height:100%;object-fit:cover}
.camwrap canvas{position:absolute;inset:0;width:100%;height:100%}
.camoff{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;
  gap:14px;padding:24px;text-align:center;color:var(--muted);font-size:14px;background:#050A09}
.pill{position:absolute;left:10px;bottom:10px;display:flex;align-items:center;gap:8px;
  padding:6px 12px;border-radius:999px;background:rgba(5,10,9,.62);color:#DCE6E2;font-size:13px;
  font-variant-numeric:tabular-nums}
.pill i{width:7px;height:7px;border-radius:50%;background:var(--track)}
.pill.bad i{background:var(--rose)}
.pill.warn i{background:var(--brass)}

/* ── setup ── */
.statusbar{display:flex;align-items:center;gap:10px;padding:8px 16px;border-bottom:1px solid var(--hair);font-size:13px}
.statusbar .bar{flex:1}
.bar{height:5px;background:var(--tint);border-radius:3px;overflow:hidden}
.bar i{display:block;height:100%;background:var(--track);transition:width .3s linear}
.bar i.bad{background:var(--rose)}
.chk{display:flex;gap:10px;align-items:baseline;padding:8px 0;border-bottom:1px solid var(--hair);font-size:14px}
.chk .mk{width:16px;flex:none;text-align:center;font-weight:700;color:var(--muted)}
.chk.ok .mk{color:var(--track)}
.chk.bad .mk{color:var(--rose)}
.chk .why{color:var(--muted);font-size:12px;margin-left:auto;text-align:right}
.recos{padding:10px 16px;background:var(--sheet);border-top:1px solid var(--hair);font-size:14px}
.recos h3{margin:0 0 6px;font-size:14px;font-weight:600}
.recos ol{margin:0;padding-left:18px;color:var(--muted)}
.recos li{margin:3px 0}

/* ── counter ── */
.counter{position:relative;display:flex;flex-direction:column;flex:1;min-height:0}
.counter .camwrap{flex:none;height:26%}
.stage{flex:1;min-height:0;display:flex;flex-direction:column;align-items:center;justify-content:center;
  transition:opacity .25s linear}
.stage.dim{opacity:.35}
#repnum{font-family:var(--display);font-weight:700;font-variant-numeric:tabular-nums;letter-spacing:-.02em;
  font-size:min(88vw,46vh,400px);line-height:.88;color:var(--num);transition:color .16s linear}
#repnum.tick{color:var(--brass)}
#cdnum{font-family:var(--display);font-weight:700;font-size:min(70vw,38vh,320px);line-height:.9;color:var(--brass)}
#chip{font-size:14px;color:var(--muted);text-align:center;min-height:20px;margin-top:6px}
.hairline{height:3px;background:transparent;transition:background .2s linear}
.hairline.on{background:var(--rose)}
.corr{display:flex;align-items:center;justify-content:center;gap:16px;padding:8px 0 4px}
.corr .n{font:700 20px/1 var(--display);min-width:44px;text-align:center;font-variant-numeric:tabular-nums}
.topline{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:8px 14px;font-size:13px;
  color:var(--muted);font-variant-numeric:tabular-nums}
.warnbox{padding:9px 14px;background:rgba(208,86,107,.14);color:var(--rose);font-size:14px;border-top:1px solid var(--rose)}
.warnbox[hidden]{display:none}

/* ── summary ── */
.sheet{flex:1;min-height:0;overflow:auto;background:var(--sheet);padding:14px 16px calc(16px + var(--sab))}
.finum{font:700 92px/1 var(--display);text-align:center;font-variant-numeric:tabular-nums;color:var(--num)}
.finum input{all:unset;display:block;width:100%;text-align:center;font:inherit;color:inherit}
.kv{display:flex;justify-content:space-between;gap:10px;padding:9px 0;border-bottom:1px solid var(--hair);font-size:14px}
.kv b{font-weight:600;font-variant-numeric:tabular-nums}
.kv .num{font-size:15px}
.flags{display:flex;flex-wrap:wrap;gap:8px;padding:10px 0}
.flags span{padding:5px 10px;border-radius:8px;background:var(--tint);border:1px solid var(--hair);font-size:13px}
.flags .hard{border-color:var(--rose);color:var(--rose)}
.flags .soft{border-color:var(--brass);color:var(--brass)}
.flags .info{border-color:var(--plum);color:var(--plum)}

/* ── lists ── */
.list{flex:1;min-height:0;overflow:auto;padding-bottom:calc(14px + var(--sab))}
.item{display:flex;justify-content:space-between;align-items:baseline;gap:10px;padding:12px 16px;
  border-bottom:1px solid var(--hair)}
.item .num{font-size:21px}
.item .meta{color:var(--muted);font-size:13px;text-align:right}
.todaytotal{padding:18px 16px 8px}
.todaytotal .num{font-size:80px;line-height:.9}
.soon{padding:26px 16px;color:var(--muted);font-size:15px}

/* ── debug ── */
.dbg{flex:1;min-height:0;overflow:auto;padding:10px 14px calc(20px + var(--sab));
  font:12px/1.45 ui-monospace,"SF Mono",Menlo,monospace}
.dbg h3{font:600 14px var(--ui);margin:14px 0 6px}
.dbg table{width:100%;border-collapse:collapse}
.dbg td,.dbg th{padding:3px 5px;border-bottom:1px solid var(--hair);text-align:right;font-weight:400}
.dbg th{text-align:left;color:var(--muted)}
.dbg .st{color:var(--brass)}
.field{margin:9px 0}
.field>label{display:flex;justify-content:space-between;font-size:13px;color:var(--muted);margin-bottom:3px}
.field>label b{color:var(--text);font-variant-numeric:tabular-nums}
__EOF_css_app_css__

mkdir -p .
cat > 'index.html' <<'__EOF_index_html__'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover,user-scalable=no">
<meta name="theme-color" content="#0E1A18" media="(prefers-color-scheme: dark)">
<meta name="theme-color" content="#E9EEEA" media="(prefers-color-scheme: light)">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Pushups">
<title>Pushups</title>
<link rel="manifest" href="manifest.webmanifest">
<link rel="apple-touch-icon" href="icons/apple-touch-icon.png">
<link rel="icon" href="icons/icon-192.png">
<link rel="stylesheet" href="css/app.css">
</head>
<body>
<div id="banner"></div>
<main id="view"></main>
<nav id="tabs" aria-label="Sections">
  <a href="#/today" data-tab="today"><span class="ic">◍</span>Today</a>
  <a href="#/train" data-tab="train"><span class="ic">↑</span>Train</a>
  <a class="todo" href="#/progress" data-tab="progress"><span class="ic">◠</span>Progress</a>
  <a class="todo" href="#/badges" data-tab="badges"><span class="ic">✦</span>Badges</a>
  <a href="#/settings" data-tab="settings"><span class="ic">⚙</span>Settings</a>
</nav>
<script>
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js').then(function (r) { window.__swReg = r; });
}
</script>
<script type="module" src="js/main.js"></script>
</body>
</html>
__EOF_index_html__

mkdir -p 'js'
cat > 'js/camera.js' <<'__EOF_js_camera_js__'
const METADATA_TIMEOUT_MS = 5000;

export function cameraSupports(videoEl) {
  void videoEl;
  return !!(typeof navigator !== 'undefined'
    && navigator.mediaDevices
    && typeof navigator.mediaDevices.getUserMedia === 'function');
}

function waitMetadata(videoEl) {
  return new Promise((resolve, reject) => {
    if (videoEl.readyState >= 1 && videoEl.videoWidth > 0) {
      resolve();
      return;
    }
    let done = false;
    const finish = (err) => {
      if (done) return;
      done = true;
      videoEl.removeEventListener('loadedmetadata', ok);
      clearTimeout(timer);
      if (err) reject(err);
      else resolve();
    };
    const ok = () => finish(null);
    const timer = setTimeout(() => {
      finish(new Error('Camera preview timed out after 5 seconds. Close other apps using the camera, then tap Start again.'));
    }, METADATA_TIMEOUT_MS);
    videoEl.addEventListener('loadedmetadata', ok, { once: true });
  });
}

function describeTrack(track, fallbackFacing) {
  if (!track || typeof track.getSettings !== 'function') {
    return { facingMode: fallbackFacing, width: 0, height: 0, deviceId: '' };
  }
  const s = track.getSettings();
  return {
    facingMode: s.facingMode || fallbackFacing,
    width: s.width || 0,
    height: s.height || 0,
    deviceId: s.deviceId || '',
  };
}

export async function openCamera(videoEl, opts = {}) {
  const { facing = 'environment', deviceId = null, width = 1280, height = 720 } = opts;

  if (!videoEl) throw new Error('No video element to attach the camera to.');
  if (!cameraSupports(videoEl)) {
    const err = new Error('This browser cannot open a camera.');
    err.name = 'NotSupportedError';
    throw err;
  }

  const video = {
    facingMode: deviceId ? undefined : facing,
    width: { ideal: width },
    height: { ideal: height },
    frameRate: { ideal: 30 },
  };
  if (deviceId) video.deviceId = { exact: deviceId };

  const stream = await navigator.mediaDevices.getUserMedia({ video, audio: false });

  videoEl.setAttribute('playsinline', '');
  videoEl.setAttribute('webkit-playsinline', '');
  videoEl.muted = true;
  videoEl.srcObject = stream;

  await waitMetadata(videoEl);

  const track = stream.getVideoTracks()[0];
  const info = describeTrack(track, facing);
  const settings = {
    facingMode: info.facingMode,
    width: info.width,
    height: info.height,
    deviceId: info.deviceId,
    facing: info.facingMode === 'user' ? 'user' : facing,
    needsTap: false,
  };

  try {
    await videoEl.play();
  } catch (err) {
    void err;
    settings.needsTap = true;
  }

  return { stream, settings, track, videoEl };
}

export async function closeCamera(state) {
  if (!state) return;
  try {
    const stream = state.stream;
    if (stream && typeof stream.getTracks === 'function') {
      for (const track of stream.getTracks()) {
        try { track.stop(); } catch (err) { void err; }
      }
    }
    if (state.videoEl) state.videoEl.srcObject = null;
  } catch (err) {
    void err;
  }
}

export async function resumePreview(videoEl) {
  if (!videoEl) return false;
  try {
    await videoEl.play();
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export async function switchCamera(videoEl, facing, state) {
  await closeCamera(state);
  return openCamera(videoEl, { facing, deviceId: null });
}

export async function listCameras() {
  try {
    if (!cameraSupports(null)) return [];
    const devices = await navigator.mediaDevices.enumerateDevices();
    return devices
      .filter((d) => d.kind === 'videoinput')
      .map((d, i) => ({
        deviceId: d.deviceId,
        label: d.label || `Camera ${i + 1}`,
        kind: d.kind,
      }));
  } catch (err) {
    void err;
    return [];
  }
}

export function describeCameraError(err) {
  const name = (err && err.name) || '';
  const message = (err && err.message) || '';

  if (typeof window !== 'undefined' && window.isSecureContext === false) {
    return {
      title: 'The camera needs a secure (HTTPS) address',
      steps: [
        'iOS and macOS block the camera on plain http:// pages, and on any address other than localhost.',
        'Open the app through its https:// address, or tap the Share button in Safari and choose Add to Home Screen so it loads over HTTPS.',
        'If you are testing on your own machine, use https://localhost or a TLS tunnel, then reload.',
      ],
    };
  }

  switch (name) {
    case 'NotAllowedError':
    case 'PermissionDeniedError':
      return {
        title: 'Camera permission was blocked',
        steps: [
          'Tap the camera or page-info icon in the address bar and set Camera to Allow, then reload.',
          'If it still says blocked: Settings ▸ Safari ▸ Camera ▸ Allow (or "Ask"), then scroll back to the app.',
          'For a home-screen app: Settings ▸ pushups ▸ Camera ▸ Allow.',
          'Close other apps that may hold the camera (Photo Booth, FaceTime) and tap Start again.',
        ],
      };
    case 'NotFoundError':
    case 'DevicesNotFoundError':
      return {
        title: 'No camera found for this choice',
        steps: [
          'The selected camera is gone (headset, external cam, or a back/front switch on a device with one camera).',
          'Open Settings in the app and pick the other camera, or reload the page to re-list cameras.',
        ],
      };
    case 'NotReadableError':
    case 'InUseError':
    case 'TrackStartError':
      return {
        title: 'Another app or tab is using the camera',
        steps: [
          'Close the other browser tab that has the camera open.',
          'Quit any app recording video, then relaunch the app from the Home Screen.',
          'If it keeps happening, restart the iPhone: the camera service on iOS sometimes stays locked.',
        ],
      };
    case 'OverconstrainedError':
      return {
        title: 'The camera cannot do the settings we asked for',
        steps: [
          'Lower the resolution in Settings (try 640 x 480) or switch facing mode.',
          'Tap Start again.',
        ],
      };
    case 'SecurityError':
      return {
        title: 'The browser blocked camera access for security',
        steps: [
          'Confirm the page address starts with https:// (or localhost).',
          'Reload the page.',
          'If the app came from a Home Screen icon, delete it and add it again from the https:// page.',
        ],
      };
    case 'NotSupportedError':
      return {
        title: 'This browser has no camera access',
        steps: [
          'Open the app in Safari (Chrome and in-app browsers on iOS cannot always reach the camera).',
          'Update iOS to the current release, then reload.',
        ],
      };
    case 'AbortError':
      return {
        title: 'Camera start was interrupted',
        steps: ['Tap Start again.', 'If it repeats, close other camera apps and reload.'],
      };
    default:
      return {
        title: 'The camera did not open',
        steps: [
          message ? `Details: ${message}` : 'No details from the browser.',
          'Tap Start again.',
          'Reload the page, then check Settings ▸ Safari ▸ Camera ▸ Allow.',
        ],
      };
  }
}

export async function setTorch(track, on) {
  if (!track || typeof track.applyConstraints !== 'function') return false;
  try {
    const caps = typeof track.getCapabilities === 'function' ? track.getCapabilities() : null;
    if (!caps || !caps.torch) return false;
    await track.applyConstraints({ advanced: [{ torch: !!on }] });
    if (!on) await track.applyConstraints({ advanced: [{}] });
    return true;
  } catch (err) {
    void err;
    return false;
  }
}
__EOF_js_camera_js__

mkdir -p 'js'
cat > 'js/counter.js' <<'__EOF_js_counter_js__'
import { OneEuro } from './one-euro.js';

export const LANDMARKS = {
  NOSE: 0, L_SHOULDER: 11, R_SHOULDER: 12, L_ELBOW: 13, R_ELBOW: 14,
  L_WRIST: 15, R_WRIST: 16, L_HIP: 23, R_HIP: 24, L_KNEE: 25, R_KNEE: 26,
  L_ANKLE: 27, R_ANKLE: 28,
};

const SIDE_PTS = {
  left: { shoulder: 11, elbow: 13, wrist: 15, hip: 23, knee: 25, ankle: 27 },
  right: { shoulder: 12, elbow: 14, wrist: 16, hip: 24, knee: 26, ankle: 28 },
};

const MIN_LM_VIS = 0.1;
const QUALITY_EMA_ALPHA = 0.2;
const SIDE_SWITCH_MARGIN = 0.08;
const QUALITY_MIN = 0.35;
const QUALITY_LOST = 0.15;
const QUALITY_REP_MIN = 0.4;
const BODY_ANGLE_MAX = 12;
const HIP_GATE = 0.16;
const HIP_GATE_EMA_ALPHA = 0.12;
// Landmarks are normalised per-axis, so the frame diagonal is unknown. A 4:3 sensor is assumed.
const FRAME_DIAGONAL = Math.hypot(1, 0.75);
const NOTSIDE_MIN_DX = 0.15 * FRAME_DIAGONAL;
const HYST = 8;
const BOTTOM_ZONE = 15;
const LOCKOUT_ZONE = 12;
const ASSIST_DEPTH = 0.10;
const SHALLOW_DROP_GATE = 0.08;
const SAG_LIMIT = 0.18;
const PIKE_LIMIT = -0.14;
const FAST_SLACK_MS = 120;
const SLOW_MS = 6000;
const REVERSAL_HYST = 10;
const TRACE_LEN = 45;

function num(v) {
  return typeof v === 'number' && Number.isFinite(v);
}

function point(lm, i) {
  if (!Array.isArray(lm) || lm.length <= i) return null;
  const p = lm[i];
  if (!p || !num(p.x) || !num(p.y)) return null;
  if ((num(p.visibility) ? p.visibility : 0) < MIN_LM_VIS) return null;
  return p;
}

function midPoint(lm, i, j) {
  const a = point(lm, i);
  const b = point(lm, j);
  if (!a || !b) return null;
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
}

function hipPoint(lm, side) {
  const k = side ? SIDE_PTS[side] : null;
  if (k) {
    const p = point(lm, k.hip);
    if (p) return p;
  }
  return midPoint(lm, LANDMARKS.L_HIP, LANDMARKS.R_HIP);
}

function bodyLine(lm, side) {
  const k = side ? SIDE_PTS[side] : null;
  let S = k ? point(lm, k.shoulder) : null;
  let A = k ? point(lm, k.ankle) : null;
  // Prefer the measured side's own endpoints: when the body folds toward vertical only that
  // side's shoulder and ankle travel together, the far side would keep the line horizontal.
  if (!S) S = midPoint(lm, LANDMARKS.L_SHOULDER, LANDMARKS.R_SHOULDER);
  if (!A) A = midPoint(lm, LANDMARKS.L_ANKLE, LANDMARKS.R_ANKLE);
  if (!S || !A) return null;
  const dx = A.x - S.x;
  const dy = A.y - S.y;
  const len = Math.hypot(dx, dy);
  if (!(len > 1e-6)) return null;
  return { S, A, dx, dy, len };
}

export function angleBetween(a, b, c) {
  if (!a || !b || !c) return null;
  const v1x = a.x - b.x, v1y = a.y - b.y;
  const v2x = c.x - b.x, v2y = c.y - b.y;
  const m1 = Math.hypot(v1x, v1y);
  const m2 = Math.hypot(v2x, v2y);
  if (!(m1 > 1e-6) || !(m2 > 1e-6)) return null;
  let cos = (v1x * v2x + v1y * v2y) / (m1 * m2);
  cos = Math.max(-1, Math.min(1, cos));
  return Math.acos(cos) * 180 / Math.PI;
}

export function elbowAngle(lm, side) {
  const k = SIDE_PTS[side];
  if (!k) return null;
  return angleBetween(point(lm, k.shoulder), point(lm, k.elbow), point(lm, k.wrist));
}

export function shoulderAngle(lm, side) {
  const k = SIDE_PTS[side];
  if (!k) return null;
  return angleBetween(point(lm, k.elbow), point(lm, k.shoulder), point(lm, k.hip));
}

// Signed, line-length-normalised perpendicular distance of the hip from the shoulder-ankle line.
// The normal is forced to point toward larger image y (the floor), so sagging hips are POSITIVE
// and piked hips NEGATIVE for both facing directions.
export function hipOffsetOf(lm, side = null) {
  const g = bodyLine(lm, side);
  if (!g) return null;
  const H = hipPoint(lm, side);
  if (!H) return null;
  let nx = -g.dy;
  let ny = g.dx;
  if (ny < 0) { nx = -nx; ny = -ny; }
  const m = Math.hypot(nx, ny);
  if (!(m > 1e-6)) return null;
  nx /= m; ny /= m;
  return ((H.x - g.S.x) * nx + (H.y - g.S.y) * ny) / g.len;
}

// atan2(-dy, dx) folded into (-90, 90] so a horizontal plank reads near 0 whichever way the
// subject faces. Sign of dx is kept available through dxOf(); 'notSide' uses |dx|.
export function bodyAngleOf(lm, side = null) {
  const g = bodyLine(lm, side);
  if (!g) return null;
  let deg = Math.atan2(-g.dy, g.dx) * 180 / Math.PI;
  if (deg > 90) deg -= 180;
  else if (deg < -90) deg += 180;
  return deg;
}

export function dxOf(lm, side = null) {
  const g = bodyLine(lm, side);
  return g ? g.dx : null;
}

// (shoulder.y - ankle.y) / |shoulder->ankle|. Grows as the body travels down: a proper side-on
// pushup moves this by roughly 0.10-0.25 between the top and the bottom position.
export function shoulderNormOf(lm, side = null) {
  const g = bodyLine(lm, side);
  if (!g) return null;
  return (g.S.y - g.A.y) / g.len;
}

// A 2-tap median is just a mean, so the spike killer is 3 taps wide.
class MedianFilter {
  constructor(size = 3) {
    this.size = Math.max(1, size);
    this.buf = [];
  }
  reset() { this.buf = []; }
  push(v) {
    if (!num(v)) return null;
    this.buf.push(v);
    if (this.buf.length > this.size) this.buf.shift();
    const s = this.buf.slice().sort((a, b) => a - b);
    const k = (s.length - 1) / 2;
    const lo = Math.floor(k);
    const hi = Math.ceil(k);
    return s[lo] + (s[hi] - s[lo]) * (k - lo);
  }
}

function cleanParams(params) {
  const p = params || {};
  return {
    top: num(p.top) ? p.top : 155,
    bottom: num(p.bottom) ? p.bottom : 100,
    minRepMs: num(p.minRepMs) ? p.minRepMs : 400,
    cleanOnly: !!p.cleanOnly,
    secondarySignal: p.secondarySignal === 'off' || p.secondarySignal === 'confirm'
      ? p.secondarySignal : 'assist',
  };
}

function emptyRep() {
  return {
    tStart: null, tCrossBottom: null, minElbow: null, maxElbow: null,
    dropBase: null, normMin: null, normMax: null, shoulderDrop: 0,
    hipMax: null, hipMin: null,
    lowQuality: false, halfByTravel: false, side: null,
  };
}

export class Counter {
  constructor(params) {
    this.params = cleanParams(params);
    this.armHoldMs = 2500;
    this.reset('init');
  }

  setParams(params) {
    this.params = cleanParams({ ...this.params, ...params });
  }

  setArmHold(ms) {
    this.armHoldMs = num(ms) && ms >= 0 ? ms : 2500;
  }

  reset(reason) {
    this.lastResetReason = reason || null;
    this.reps = 0;
    this.repsDetected = 0;
    this.cleanReps = 0;
    this.state = 'idle';
    this.armed = false;
    this.armStreakStart = null;
    this.armLockedAt = null;
    this.side = null;
    this.qVis = { left: null, right: null };
    this.quality = 0;
    this.euro = new OneEuro({ minCutoff: 1.1, beta: 0.02, dCutoff: 1.0 });
    this.medElbow = new MedianFilter(3);
    this.medHip = new MedianFilter(3);
    this.hipEma = null;
    this.angle = null;
    this.rep = emptyRep();
    this.lastRep = null;
    this.events = [];
    this.trace = [];
    this.normBaseline = null;
    this.lastActiveMs = null;
    this.lastT = null;
  }

  _touch(t) { this.lastActiveMs = t; }

  _clearFilters() {
    this.euro.reset();
    this.medElbow.reset();
    this.medHip.reset();
    this.hipEma = null;
    this.angle = null;
    this.normBaseline = null;
  }

  _dropInFlight() {
    this.rep = emptyRep();
    this.state = 'idle';
  }

  _updateSideQuality(lm) {
    if (!lm) return;
    for (const side of ['left', 'right']) {
      const k = SIDE_PTS[side];
      const ids = [k.shoulder, k.elbow, k.wrist, k.hip, k.ankle];
      let sum = 0;
      let n = 0;
      for (const i of ids) {
        const p = Array.isArray(lm) && lm.length > i ? lm[i] : null;
        if (p && num(p.visibility)) { sum += p.visibility; n++; }
      }
      if (!n) continue;
      const mean = sum / n;
      const prev = this.qVis[side];
      this.qVis[side] = prev === null
        ? mean
        : prev + QUALITY_EMA_ALPHA * (mean - prev);
    }

    const L = this.qVis.left;
    const R = this.qVis.right;
    if (this.side === null) {
      if (L !== null || R !== null) this.side = (R !== null && L !== null && R > L) ? 'right' : 'left';
    } else {
      const cur = this.qVis[this.side];
      const other = this.side === 'left' ? 'right' : 'left';
      const oth = this.qVis[other];
      if (oth !== null && cur !== null && oth > cur + SIDE_SWITCH_MARGIN) this.side = other;
    }
    this.quality = this.side ? (this.qVis[this.side] || 0) : 0;
  }

  _plank(present, quality, dx, bodyAngle, hipForGate) {
    const reasons = [];
    if (!present || !num(dx) || !num(bodyAngle) || quality <= 0) {
      reasons.push('noPose');
    } else {
      if (quality < QUALITY_MIN) reasons.push('lowVis');
      if (Math.abs(dx) < NOTSIDE_MIN_DX) reasons.push('notSide');
      if (Math.abs(bodyAngle) > BODY_ANGLE_MAX) reasons.push('bodyAngle');
      if (num(hipForGate) && Math.abs(hipForGate) > HIP_GATE) reasons.push('hip');
    }
    return { valid: reasons.length === 0, reasons };
  }

  _startRep(t, e, side, shoulderNorm) {
    this.rep = emptyRep();
    this.rep.tStart = t;
    this.rep.minElbow = e;
    this.rep.side = side;
    // Travel is measured from the held top position, not from the (lagging) moment the angle
    // crosses top-8, otherwise smoothing eats a fifth of every rep's measured depth.
    let base = num(this.normBaseline) ? this.normBaseline : null;
    if (num(shoulderNorm)) base = base === null ? shoulderNorm : Math.min(base, shoulderNorm);
    this.rep.dropBase = base;
    this.rep.normMin = base;
    this.rep.normMax = base;
    this.state = 'down';
    this._touch(t);
  }

  _observeRep(e, quality, hip, shoulderNorm) {
    const r = this.rep;
    if (r.tStart === null) return;
    if (num(e)) {
      if (r.minElbow === null || e < r.minElbow) r.minElbow = e;
      // maxElbow belongs to the up phase only; seeding it at the top of the descent would
      // make every rep look like it reversed straight out of the bottom.
      if (this.state === 'up' && (r.maxElbow === null || e > r.maxElbow)) r.maxElbow = e;
    }
    if (quality < QUALITY_REP_MIN) r.lowQuality = true;
    if (num(hip)) {
      if (r.hipMax === null || hip > r.hipMax) r.hipMax = hip;
      if (r.hipMin === null || hip < r.hipMin) r.hipMin = hip;
    }
    if (num(shoulderNorm)) {
      if (r.normMin === null || shoulderNorm < r.normMin) r.normMin = shoulderNorm;
      if (r.normMax === null || shoulderNorm > r.normMax) r.normMax = shoulderNorm;
      const d = r.normMax - r.normMin;
      if (d > r.shoulderDrop) r.shoulderDrop = d;
    }
  }

  _complete(t, e, lockout) {
    const p = this.params;
    const r = this.rep;
    const hadDescent = r.tStart !== null;
    const durationMs = hadDescent ? t - r.tStart : 0;
    const minElbow = num(r.minElbow) ? r.minElbow : e;
    const maxElbow = num(r.maxElbow) ? r.maxElbow : e;
    const bottomed = r.tCrossBottom !== null || r.halfByTravel;

    this.state = 'hold';
    this.rep = emptyRep();

    if (!hadDescent || !bottomed || durationMs < p.minRepMs) {
      this._touch(t);
      return null;
    }

    const flags = [];
    if (minElbow > p.bottom) flags.push('half');
    if (lockout) flags.push('lockout');
    if (num(r.hipMax) && r.hipMax > SAG_LIMIT) flags.push('sag');
    if (num(r.hipMin) && r.hipMin < PIKE_LIMIT) flags.push('pike');
    if (r.lowQuality || this.quality < QUALITY_REP_MIN) flags.push('lost');
    if (durationMs < p.minRepMs + FAST_SLACK_MS) flags.push('fast');
    if (durationMs > SLOW_MS) flags.push('slow');
    if (p.secondarySignal === 'confirm' && r.normMin !== null) {
      if (r.shoulderDrop < SHALLOW_DROP_GATE) flags.push('shallow');
    }

    this.repsDetected++;
    if (flags.length === 0) this.cleanReps++;
    if (flags.length === 0 || !p.cleanOnly) this.reps++;

    const rep = {
      n: this.repsDetected,
      tStart: r.tStart,
      tEnd: t,
      durationMs,
      minElbow,
      maxElbow,
      shoulderDrop: num(r.shoulderDrop) ? r.shoulderDrop : 0,
      hipMax: num(r.hipMax) ? r.hipMax : null,
      hipMin: num(r.hipMin) ? r.hipMin : null,
      flags,
      side: r.side || this.side,
    };
    // spec spells these hipMin/hipMax the other way round; the values themselves are
    // (max positive = sag, most negative = pike), so keep both names meaning min/max.
    this.lastRep = rep;
    this.events.push({ type: 'rep', t, data: rep });
    this._touch(t);
    return rep;
  }

  _step(t, e, hip, shoulderNorm, sideTravelAllowed) {
    const p = this.params;
    const top = p.top;
    const bottom = p.bottom;
    const r = this.rep;

    switch (this.state) {
      case 'idle':
        if (e < top - HYST) this._startRep(t, e, this.side, shoulderNorm);
        break;

      case 'hold':
        if (e < top - HYST) this._startRep(t, e, this.side, shoulderNorm);
        break;

      case 'down': {
        this._observeRep(e, this.quality, hip, shoulderNorm);
        if (r.tCrossBottom === null && e <= bottom + BOTTOM_ZONE) r.tCrossBottom = t;

        if (e <= bottom) {
          this.state = 'bottom';
          this._touch(t);
          break;
        }
        // shoulder travel proves real depth even when the elbow never reaches `bottom`:
        // the rep stays alive and earns 'half' on completion. Checked before the
        // back-to-top discard so a genuine shallow rep is not thrown away.
        if (sideTravelAllowed && !r.halfByTravel
            && r.shoulderDrop >= ASSIST_DEPTH
            && r.minElbow !== null && e >= r.minElbow + REVERSAL_HYST) {
          r.halfByTravel = true;
          if (r.maxElbow === null) r.maxElbow = e;
          this.state = 'up';
          this._touch(t);
          break;
        }
        if (e >= top - HYST) {
          // never got deep: not a rep, arms are back up
          this.rep = emptyRep();
          this.state = 'hold';
          this._touch(t);
          break;
        }
        break;
      }

      case 'bottom':
        this._observeRep(e, this.quality, hip, shoulderNorm);
        if (r.tCrossBottom === null && e <= bottom + BOTTOM_ZONE) r.tCrossBottom = t;
        if (e > bottom + HYST) {
          if (r.maxElbow === null) r.maxElbow = e;
          this.state = 'up';
          this._touch(t);
        }
        break;

      case 'up': {
        this._observeRep(e, this.quality, hip, shoulderNorm);
        if (e >= top) {
          this._complete(t, e, false);
          break;
        }
        if (e <= bottom) {
          this.state = 'bottom';
          break;
        }
        const nearBottomZone = e <= bottom + BOTTOM_ZONE && r.maxElbow !== null
          && r.maxElbow < top - LOCKOUT_ZONE;
        if (nearBottomZone) {
          this.state = 'bottom';
          break;
        }
        if (r.maxElbow !== null && e <= r.maxElbow - HYST) {
          if (r.maxElbow >= top - LOCKOUT_ZONE) this._complete(t, e, true);
          else {
            this.rep = emptyRep();
            this.state = 'idle';
            this._touch(t);
          }
        }
        break;
      }

      default:
        this.state = 'idle';
    }
  }

  addFrame(tMs, frame) {
    try {
      return this._addFrame(tMs, frame);
    } catch (err) {
      const ev = this.events;
      this.events = [];
      return {
        reps: this.reps, repsDetected: this.repsDetected, cleanReps: this.cleanReps,
        state: 'idle', armed: false, armMs: 0, quality: 0, side: this.side,
        angles: { left: { elbow: null, shoulder: null }, right: { elbow: null, shoulder: null } },
        hipOffset: null, bodyAngle: null,
        plank: { valid: false, reasons: ['noPose'] },
        lastRep: null, events: ev, trace: this.trace,
        lastActiveMs: this.lastActiveMs, error: err && err.message ? err.message : String(err),
      };
    }
  }

  _addFrame(tMs, frame) {
    const p = this.params;
    this.events = [];
    this.lastRep = null;

    const lm = frame && Array.isArray(frame.landmarks) ? frame.landmarks : null;
    const present = !!(frame && frame.present && lm && lm.length > LANDMARKS.R_ANKLE);
    const t = num(tMs) ? tMs : (this.lastT === null ? 0 : this.lastT);

    this._updateSideQuality(present ? lm : null);
    const side = this.side;

    const rawElbow = present ? elbowAngle(lm, side) : null;
    const angles = {
      left: { elbow: present ? elbowAngle(lm, 'left') : null, shoulder: present ? shoulderAngle(lm, 'left') : null },
      right: { elbow: present ? elbowAngle(lm, 'right') : null, shoulder: present ? shoulderAngle(lm, 'right') : null },
    };
    const rawHip = present ? hipOffsetOf(lm, side) : null;
    const bodyAngle = present ? bodyAngleOf(lm, side) : null;
    const dx = present ? dxOf(lm, side) : null;
    const rawNorm = present ? shoulderNormOf(lm, side) : null;

    let elbow = null;
    let hip = null;
    let shoulderNorm = null;
    if (present) {
      shoulderNorm = num(rawNorm) ? rawNorm : null;
      if (num(rawHip)) {
        const m = this.medHip.push(rawHip);
        hip = num(m) ? m : null;
        if (hip !== null) {
          this.hipEma = this.hipEma === null ? hip : this.hipEma + HIP_GATE_EMA_ALPHA * (hip - this.hipEma);
        }
      }
      if (num(rawElbow)) {
        const m = this.medElbow.push(rawElbow);
        if (m !== null) {
          const f = this.euro.filter(t, m);
          if (num(f)) elbow = f;
        }
      }
    } else {
      this.medHip.reset();
      this.medElbow.reset();
      this.hipEma = null;
      this.euro.reset();
    }

    const plank = this._plank(present, this.quality, dx, bodyAngle, this.hipEma);

    if (!plank.valid) {
      this.armStreakStart = null;
      if (this.armed) {
        this.armed = false;
        this.armLockedAt = null;
        this._dropInFlight();
        this._clearFilters();
        this.events.push({ type: 'armBreak', t, data: { reason: plank.reasons[0] || 'noPose', t } });
        this._touch(t);
      } else {
        this._dropInFlight();
        if (!present) this._clearFilters();
      }
    } else {
      if (this.armStreakStart === null) this.armStreakStart = t;
      if (!this.armed) {
        if (t - this.armStreakStart >= this.armHoldMs) {
          this.armed = true;
          this.armLockedAt = t;
          this._clearFilters();
          this._dropInFlight();
          this._touch(t);
        }
      } else {
        this._touch(t);
      }

      if (this.armed && elbow !== null) {
        this._step(t, elbow, hip, shoulderNorm, p.secondarySignal !== 'off');
      }
      if (this.armed && num(shoulderNorm)) {
        // Top-of-rep reference for shoulder travel: snaps down to a new high body position and
        // creeps back up slowly, so filter lag at the start of a descent cannot eat the depth.
        if (this.normBaseline === null || shoulderNorm < this.normBaseline) this.normBaseline = shoulderNorm;
        else this.normBaseline += 0.004 * (shoulderNorm - this.normBaseline);
      }
    }

    this.lastT = t;

    this.trace.push({
      t,
      elbowRaw: rawElbow,
      elbowFiltered: elbow,
      hipOffset: hip,
      shoulderNorm,
      quality: this.quality,
    });
    if (this.trace.length > TRACE_LEN) this.trace.shift();

    const events = this.events;
    this.events = [];

    return {
      reps: this.reps,
      repsDetected: this.repsDetected,
      cleanReps: this.cleanReps,
      state: this.state,
      armed: this.armed,
      armMs: this.armed && this.armLockedAt !== null ? t - this.armLockedAt : 0,
      quality: this.quality,
      side,
      angles,
      hipOffset: hip,
      bodyAngle,
      plank,
      lastRep: this.lastRep,
      events,
      trace: this.trace,
      lastActiveMs: this.lastActiveMs,
    };
  }
}
__EOF_js_counter_js__

mkdir -p 'js'
cat > 'js/db.js' <<'__EOF_js_db_js__'
/* schema
set  { id, startedAt (epoch ms), endedAt, durationMs, mode:'camera'|'manual', source:'camera'|'manual',
       repsDetected, repsFinal, flags:{ sag, pike, half, lockout, lost }, cameraUsed:'environment'|'user',
       qualityStats:{ fpsMean, visMean, frames }, paramsUsed:{...thresholds }, presetName, model, notes,
       day:'YYYY-MM-DD', schema:1 }
rep  { id, setId, tMs (relative to set start), durationMs, minElbow, maxElbow, shoulderDrop, hipOffset,
       side, flags:[], n }
meta { k, v }
DB pushups v1: stores 'sets' (keyPath id autoIncrement, indexes startedAt, day),
'reps' (keyPath id autoIncrement, index setId), 'meta' (keyPath k).
*/

const DB_NAME = 'pushups';
const DB_VERSION = 1;
const SCHEMA = 1;

let dbPromise = null;

function toPromise(req) {
  return new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error || new Error('IndexedDB request failed'));
  });
}

function finish(tx) {
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onabort = () => reject(tx.error || new Error('IndexedDB transaction aborted'));
    tx.onerror = () => reject(tx.error || new Error('IndexedDB transaction failed'));
  });
}

function idb() {
  if (typeof indexedDB === 'undefined' || indexedDB === null) {
    throw new Error('IndexedDB is not available in this browser/context');
  }
  return indexedDB;
}

export function open() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = idb().open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = (ev) => {
      const db = req.result;
      if (!db.objectStoreNames.contains('sets')) {
        const sets = db.createObjectStore('sets', { keyPath: 'id', autoIncrement: true });
        sets.createIndex('startedAt', 'startedAt');
        sets.createIndex('day', 'day');
      }
      if (!db.objectStoreNames.contains('reps')) {
        const reps = db.createObjectStore('reps', { keyPath: 'id', autoIncrement: true });
        reps.createIndex('setId', 'setId');
      }
      if (!db.objectStoreNames.contains('meta')) {
        db.createObjectStore('meta', { keyPath: 'k' });
      }
      void ev;
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error || new Error('could not open ' + DB_NAME));
    req.onblocked = () => reject(new Error('IndexedDB open blocked by another tab'));
  });
  return dbPromise;
}

export async function resetForTest() {
  if (dbPromise) {
    const db = await dbPromise.catch(() => null);
    if (db) db.close();
  }
  dbPromise = null;
  await new Promise((resolve, reject) => {
    const req = idb().deleteDatabase(DB_NAME);
    req.onsuccess = () => resolve();
    req.onerror = () => reject(req.error || new Error('deleteDatabase failed'));
    req.onblocked = () => resolve();
  });
  return open();
}

export function localDay(ms) {
  const d = new Date(ms === undefined || ms === null ? Date.now() : ms);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function normalizeSet(set) {
  const rec = { ...(set || {}) };
  delete rec.id;
  if (typeof rec.startedAt !== 'number') rec.startedAt = Date.now();
  if (!rec.day) rec.day = localDay(rec.startedAt);
  rec.schema = SCHEMA;
  return rec;
}

function normalizeRep(rep, setId) {
  const rec = { ...(rep || {}) };
  delete rec.id;
  rec.setId = setId;
  return rec;
}

export async function saveSet(set, repsArray) {
  const db = await open();
  const rec = normalizeSet(set);
  const reps = Array.isArray(repsArray) ? repsArray : [];
  let id = null;
  const tx = db.transaction(['sets', 'reps'], 'readwrite');
  id = await toPromise(tx.objectStore('sets').add(rec));
  for (const rep of reps) {
    tx.objectStore('reps').add(normalizeRep(rep, id));
  }
  await finish(tx);
  return id;
}

export async function getSet(id) {
  const db = await open();
  const tx = db.transaction('sets', 'readonly');
  const rec = await toPromise(tx.objectStore('sets').get(id));
  await finish(tx);
  return rec || null;
}

export async function listReps(setId) {
  const db = await open();
  const tx = db.transaction('reps', 'readonly');
  const reps = await toPromise(tx.objectStore('reps').index('setId').getAll(setId));
  await finish(tx);
  return (reps || []).sort((a, b) => (a.tMs || 0) - (b.tMs || 0));
}

function collectAll(storeName, indexer) {
  return open().then((db) => {
    const tx = db.transaction(storeName, 'readonly');
    const src = indexer ? indexer(tx.objectStore(storeName)) : tx.objectStore(storeName);
    return toPromise(src.getAll()).then((rows) => finish(tx).then(() => rows || []));
  });
}

export async function listSets() {
  const rows = await collectAll('sets');
  return rows.sort((a, b) => (b.startedAt || 0) - (a.startedAt || 0));
}

export async function listSetsForDay(day) {
  const db = await open();
  const tx = db.transaction('sets', 'readonly');
  const rows = await toPromise(tx.objectStore('sets').index('day').getAll(day));
  await finish(tx);
  return (rows || []).sort((a, b) => (b.startedAt || 0) - (a.startedAt || 0));
}

export async function updateSet(id, patch) {
  const db = await open();
  const tx = db.transaction('sets', 'readwrite');
  const store = tx.objectStore('sets');
  const current = await toPromise(store.get(id));
  if (!current) {
    await finish(tx).catch(() => {});
    return null;
  }
  const next = { ...current, ...(patch || {}), id: current.id };
  await toPromise(store.put(next));
  await finish(tx);
  return next;
}

export async function deleteSet(id) {
  const db = await open();
  const tx = db.transaction(['sets', 'reps'], 'readwrite');
  tx.objectStore('sets').delete(id);
  const keys = await toPromise(tx.objectStore('reps').index('setId').getAllKeys(id));
  for (const k of keys || []) tx.objectStore('reps').delete(k);
  await finish(tx);
  return true;
}

export async function countSets() {
  const db = await open();
  const tx = db.transaction('sets', 'readonly');
  const n = await toPromise(tx.objectStore('sets').count());
  await finish(tx);
  return n || 0;
}

export async function getMeta(k) {
  const db = await open();
  const tx = db.transaction('meta', 'readonly');
  const rec = await toPromise(tx.objectStore('meta').get(k));
  await finish(tx);
  return rec && 'v' in rec ? rec.v : undefined;
}

export async function setMeta(k, v) {
  const db = await open();
  const tx = db.transaction('meta', 'readwrite');
  await toPromise(tx.objectStore('meta').put({ k, v }));
  await finish(tx);
  return v;
}

export async function exportJSON() {
  const [sets, reps] = await Promise.all([collectAll('sets'), collectAll('reps')]);
  return JSON.stringify({
    app: 'pushups',
    schema: SCHEMA,
    exportedAt: Date.now(),
    sets: sets || [],
    reps: reps || [],
  });
}

function isIdKey(key) {
  return typeof key === 'number' || typeof key === 'string';
}

async function idIsFree(store, id) {
  if (!isIdKey(id)) return false;
  const existing = await toPromise(store.get(id));
  return !existing;
}

export async function importJSON(text) {
  let payload;
  try {
    payload = typeof text === 'string' ? JSON.parse(text) : text;
  } catch (e) {
    return { ok: false, added: 0, error: 'Not valid JSON: ' + (e && e.message ? e.message : String(e)) };
  }
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    return { ok: false, added: 0, error: 'Backup file is not an object' };
  }
  if (payload.app !== 'pushups') {
    return { ok: false, added: 0, error: 'This backup is not from Pushups (missing app:"pushups")' };
  }
  if (payload.schema !== SCHEMA) {
    return { ok: false, added: 0, error: 'Unsupported backup schema ' + String(payload.schema) };
  }
  if (!Array.isArray(payload.sets)) {
    return { ok: false, added: 0, error: 'Backup has no sets array' };
  }
  if (payload.reps !== undefined && !Array.isArray(payload.reps)) {
    return { ok: false, added: 0, error: 'Backup has a reps field that is not an array' };
  }

  const db = await open();
  const incomingSets = payload.sets;
  const incomingReps = Array.isArray(payload.reps) ? payload.reps : [];
  const tx = db.transaction(['sets', 'reps'], 'readwrite');
  const setStore = tx.objectStore('sets');
  const repStore = tx.objectStore('reps');
  const idMap = new Map();
  let addedSets = 0;
  let addedReps = 0;

  for (const s of incomingSets) {
    if (!s || typeof s !== 'object') continue;
    const oldId = s.id;
    const rec = { ...s };
    delete rec.id;
    if (typeof rec.startedAt !== 'number') rec.startedAt = Date.now();
    if (!rec.day) rec.day = localDay(rec.startedAt);
    rec.schema = SCHEMA;
    let key;
    if (isIdKey(oldId) && await idIsFree(setStore, oldId)) {
      rec.id = oldId;
      key = await toPromise(setStore.put(rec));
    } else {
      key = await toPromise(setStore.add(rec));
    }
    if (oldId !== undefined) idMap.set(oldId, key);
    addedSets++;
  }

  for (const r of incomingReps) {
    if (!r || typeof r !== 'object') continue;
    const rec = { ...r };
    const oldRepId = rec.id;
    delete rec.id;
    if (rec.setId !== undefined) {
      if (idMap.has(rec.setId)) rec.setId = idMap.get(rec.setId);
    }
    if (isIdKey(oldRepId) && await idIsFree(repStore, oldRepId)) {
      rec.id = oldRepId;
      await toPromise(repStore.put(rec));
    } else {
      await toPromise(repStore.add(rec));
    }
    addedReps++;
  }

  await finish(tx);
  return {
    ok: true,
    added: addedSets,
    addedSets,
    addedReps,
    error: null,
  };
}
__EOF_js_db_js__

mkdir -p 'js'
cat > 'js/feedback.js' <<'__EOF_js_feedback_js__'
let ctx = null;
let lastTickAt = 0;
let voicesWarmed = false;

const ONES = [
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine',
  'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen',
  'seventeen', 'eighteen', 'nineteen',
];
const TENS = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];

export const NUMBER_WORDS = [...ONES, 'twenty'];

const MIN_TICK_GAP_MS = 45;

export async function unlockAudio() {
  try {
    if (!ctx) {
      const AC = (typeof window !== 'undefined' && (window.AudioContext || window.webkitAudioContext)) || null;
      if (!AC) return false;
      ctx = new AC();
    }
    if (ctx.state === 'suspended' && typeof ctx.resume === 'function') await ctx.resume();
    return ctx.state === 'running';
  } catch (err) {
    void err;
    return false;
  }
}

function blip(freq, startAt, ms, gain, type) {
  if (!ctx || ctx.state !== 'running') return false;
  if (gain <= 0 || ms <= 0) return false;
  try {
    const dur = ms / 1000;
    const osc = ctx.createOscillator();
    const g = ctx.createGain();
    osc.type = type || 'sine';
    osc.frequency.setValueAtTime(freq, startAt);
    const peak = Math.max(gain, 0.0005);
    const attack = Math.min(0.008, dur * 0.3);
    const holdEnd = startAt + Math.max(dur - attack, dur * 0.7);
    g.gain.setValueAtTime(0.0001, startAt);
    g.gain.exponentialRampToValueAtTime(peak, startAt + attack);
    g.gain.setValueAtTime(peak, holdEnd);
    g.gain.exponentialRampToValueAtTime(0.0001, startAt + dur);
    osc.connect(g);
    g.connect(ctx.destination);
    osc.start(startAt);
    osc.stop(startAt + dur + 0.02);
    osc.onended = () => {
      try { osc.disconnect(); g.disconnect(); } catch (err) { void err; }
    };
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export function playBeep({ freq = 880, ms = 60, gain = 0.05, type = 'sine' } = {}) {
  if (!ctx || ctx.state !== 'running') return false;
  return blip(freq, ctx.currentTime, ms, gain, type);
}

export function playCountTick() {
  const now = (typeof performance !== 'undefined' ? performance.now() : Date.now());
  if (now - lastTickAt < MIN_TICK_GAP_MS) return false;
  lastTickAt = now;
  return blip(440, ctx ? ctx.currentTime : 0, 45, 0.045, 'triangle');
}

export function playWarning() {
  if (!ctx || ctx.state !== 'running') return false;
  const t = ctx.currentTime;
  const a = blip(392, t, 80, 0.035, 'sine');
  const b = blip(294, t + 0.11, 110, 0.03, 'sine');
  return a || b;
}

export function playGo() {
  if (!ctx || ctx.state !== 'running') return false;
  const t = ctx.currentTime;
  const a = blip(659, t, 90, 0.05, 'sine');
  const b = blip(988, t + 0.12, 160, 0.05, 'sine');
  return a || b;
}

function warmVoices() {
  if (voicesWarmed || typeof window === 'undefined' || !window.speechSynthesis) return;
  voicesWarmed = true;
  try {
    window.speechSynthesis.getVoices();
    window.speechSynthesis.addEventListener('voiceschanged', () => {
      window.speechSynthesis.getVoices();
    }, { once: true });
  } catch (err) {
    void err;
  }
}

export function voiceSupported() {
  return typeof window !== 'undefined'
    && 'speechSynthesis' in window
    && typeof window.SpeechSynthesisUtterance === 'function';
}

export function speak(text, { interrupt = true, rate = 1, pitch = 1 } = {}) {
  if (!voiceSupported() || text === undefined || text === null || text === '') return false;
  warmVoices();
  const syn = window.speechSynthesis;
  try {
    if (interrupt) {
      if (syn.speaking || syn.pending) syn.cancel();
    } else if (syn.speaking) {
      return false;
    }
    const u = new window.SpeechSynthesisUtterance(String(text));
    u.rate = rate;
    u.pitch = pitch;
    u.volume = 1;
    u.lang = (navigator.language || 'en-US');
    syn.speak(u);
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export function stopSpeaking() {
  if (!voiceSupported()) return false;
  try {
    window.speechSynthesis.cancel();
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export function vibrate(pattern) {
  if (typeof navigator === 'undefined' || typeof navigator.vibrate !== 'function') return false;
  try {
    navigator.vibrate(pattern === undefined ? 12 : pattern);
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export function countWord(n) {
  const num = Math.trunc(Number(n));
  if (!Number.isFinite(num) || num < 0 || num > 999) return String(n);
  if (num < 20) return ONES[num];
  const tens = Math.floor(num / 10);
  const rest = num % 10;
  if (tens < 10) return rest === 0 ? TENS[tens] : `${TENS[tens]}-${ONES[rest]}`;
  const hundreds = Math.floor(num / 100);
  const tail = num % 100;
  if (tail === 0) return `${ONES[hundreds]} hundred`;
  return `${ONES[hundreds]} hundred ${countWord(tail)}`;
}

export function announceRep(n, { mode = 'every', voice = true, beeps = true, haptics = true } = {}) {
  const count = Math.trunc(Number(n)) || 0;
  let spoke = false;
  if (voice && mode !== 'off' && (mode === 'every' || count % 5 === 0)) {
    spoke = speak(countWord(count), { interrupt: true });
  }
  const ticked = beeps ? playCountTick() : false;
  const buzzed = haptics ? vibrate(count % 5 === 0 ? [18, 40, 18] : 12) : false;
  return { spoke, ticked, buzzed };
}

export function countdownVoice(secondsLeft) {
  const words = { 5: 'five', 4: 'four', 3: 'three', 2: 'two', 1: 'one' };
  const s = Math.trunc(Number(secondsLeft));
  if (!Number.isFinite(s) || s <= 0) return 'go';
  return words[s] || countWord(s);
}
__EOF_js_feedback_js__

mkdir -p 'js'
cat > 'js/main.js' <<'__EOF_js_main_js__'
import { load } from './settings.js';
import { initUpdate, requestWakeLock, watchWakeLock, requestPersistent, isStandalone } from './upgrade.js';

const ROUTES = {
  today: () => import('./views/today.js'),
  train: () => import('./views/train.js'),
  progress: () => import('./views/progress.js'),
  badges: () => import('./views/badges.js'),
  settings: () => import('./views/settings.js'),
  debug: () => import('./views/debug.js'),
};

const host = document.getElementById('view');
const banner = document.getElementById('banner');
let current = null;

function routeName() {
  const h = (location.hash || '#/today').replace(/^#\//, '').split('?')[0];
  return ROUTES[h] ? h : 'today';
}

function markTab(name) {
  document.querySelectorAll('#tabs a').forEach((a) => {
    a.setAttribute('aria-current', a.dataset.tab === name ? 'true' : 'false');
  });
}

async function render() {
  const name = routeName();
  if (current && current.unmount) {
    try { await current.unmount(); } catch (e) { console.warn('unmount', e); }
  }
  current = null;
  host.replaceChildren();
  markTab(name);
  const mod = await ROUTES[name]();
  const view = mod.default ? mod.default : mod;
  current = await view(host, { route: name, render, params: new URLSearchParams(location.search) });
}

window.addEventListener('hashchange', render);

// ── update prompt ──
function showBanner(reload) {
  const box = document.createElement('div');
  box.textContent = 'Update available — tap to reload';
  box.addEventListener('click', () => {
    banner.replaceChildren();
    reload();
  });
  banner.replaceChildren(box);
}

// ── lifecycle ──
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') requestWakeLock('return-to-foreground');
});

function fail(err) {
  console.error(err);
  const p = document.createElement('p');
  p.className = 'h1';
  p.textContent = 'Startup failed';
  const s = document.createElement('p');
  s.className = 'sub';
  s.textContent = String(err && err.message ? err.message : err);
  const pad = document.createElement('div');
  pad.className = 'pad';
  pad.append(p, s);
  host.replaceChildren(pad);
}

async function boot() {
  load();
  if (window.__swReg) initUpdate({ swRegistration: window.__swReg, onPrompt: showBanner });
  watchWakeLock();
  if (isStandalone()) requestPersistent().catch(() => {});
  await render();
}

boot().catch(fail);
__EOF_js_main_js__

mkdir -p 'js'
cat > 'js/one-euro.js' <<'__EOF_js_one_euro_js__'
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
__EOF_js_one_euro_js__

mkdir -p 'js'
cat > 'js/pose.js' <<'__EOF_js_pose_js__'
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
__EOF_js_pose_js__

mkdir -p 'js'
cat > 'js/settings.js' <<'__EOF_js_settings_js__'
export const PRESETS = {
  relaxed:  { top: 140, bottom: 112, minRepMs: 300 },
  standard: { top: 155, bottom: 100, minRepMs: 400 },
  strict:   { top: 168, bottom: 88,  minRepMs: 450 },
};

export const DEFAULTS = {
  preset: 'standard', overrides: {}, cleanOnly: false, autoArm: false, armHoldMs: 2500,
  endAfterIdleSec: 12, camera: 'environment', voice: 'every', beeps: true, haptics: true,
  skeletonOnSet: true, secondarySignal: 'assist', model: 'lite', fpsCap: 25, manualMode: false, debug: false,
};

const STORAGE_KEY = 'pushups.settings.v1';

let cached = null;

function readStored() {
  try {
    const raw = globalThis.localStorage?.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return null;
    return parsed;
  } catch {
    return null;
  }
}

function normalize(settings) {
  const out = { ...settings };
  if (!PRESETS[out.preset]) out.preset = DEFAULTS.preset;
  if (!out.overrides || typeof out.overrides !== 'object' || Array.isArray(out.overrides)) {
    out.overrides = {};
  }
  return out;
}

export function load() {
  if (cached) return cached;
  const stored = readStored();
  cached = normalize(stored ? { ...DEFAULTS, ...stored } : { ...DEFAULTS });
  return cached;
}

export function save(patch) {
  const base = load();
  const next = normalize({ ...base, ...(patch || {}) });
  cached = next;
  try {
    globalThis.localStorage?.setItem(STORAGE_KEY, JSON.stringify(next));
  } catch {
    // storage unavailable (private mode, quota) — keep the in-memory copy
  }
  return next;
}

export function params() {
  const s = load();
  const preset = PRESETS[s.preset] || PRESETS.standard;
  const overrides = {};
  for (const [k, v] of Object.entries(s.overrides || {})) {
    if (typeof v === 'number' && Number.isFinite(v)) overrides[k] = v;
  }
  return { ...preset, ...overrides };
}

export function setParam(k, v) {
  const s = load();
  const overrides = { ...s.overrides };
  if (v === null || v === undefined || (typeof v === 'number' && !Number.isFinite(v))) {
    delete overrides[k];
  } else {
    overrides[k] = v;
  }
  return save({ ...s, overrides });
}

export function resetParams() {
  return save({ ...load(), overrides: {} });
}

export function clearOverridesForPreset() {
  return resetParams();
}
__EOF_js_settings_js__

mkdir -p 'js'
cat > 'js/upgrade.js' <<'__EOF_js_upgrade_js__'
const POLL_MS = 5 * 60 * 1000;

let reg = null;
let pollTimer = 0;
let listenersAttached = false;
let promptedWorker = null;
let reloadRequested = false;
let onPromptRef = null;

let sentinel = null;
let wantLock = false;
let lockReason = '';
let lockWatchAttached = false;

function hasSW() {
  return typeof navigator !== 'undefined'
    && 'serviceWorker' in navigator
    && !!navigator.serviceWorker;
}

function doReload() {
  if (reloadRequested) return;
  reloadRequested = true;
  try {
    if (typeof location !== 'undefined') location.reload();
  } catch (err) {
    void err;
  }
}

function attachControllerListener() {
  if (!hasSW()) return;
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (reloadRequested) doReload();
  });
}

function promptWorker(worker) {
  if (!worker || promptedWorker === worker) return;
  promptedWorker = worker;
  const reload = () => {
    try {
      worker.postMessage('skip');
    } catch (err) {
      void err;
    }
    reloadRequested = true;
  };
  attachControllerListener();
  if (typeof onPromptRef === 'function') onPromptRef(reload);
}

function checkForWaiting() {
  if (reg && reg.waiting) promptWorker(reg.waiting);
}

function checkUpdate() {
  if (!reg || typeof reg.update !== 'function') return;
  try {
    Promise.resolve(reg.update()).catch(() => {});
  } catch (err) {
    void err;
  }
}

function onVisibility() {
  if (typeof document === 'undefined') return;
  if (document.visibilityState !== 'visible') return;
  checkUpdate();
  if (wantLock && !sentinel) void requestWakeLock(lockReason || 'resume');
}

export function initUpdate({ swRegistration, onPrompt } = {}) {
  if (!swRegistration) return false;
  reg = swRegistration;
  onPromptRef = typeof onPrompt === 'function' ? onPrompt : onPromptRef;

  if (!listenersAttached) {
    listenersAttached = true;
    if (typeof setInterval !== 'undefined') pollTimer = setInterval(checkUpdate, POLL_MS);
    if (typeof document !== 'undefined') document.addEventListener('visibilitychange', onVisibility);
    if (hasSW()) {
      navigator.serviceWorker.addEventListener('message', (ev) => {
        const data = ev && ev.data;
        const isReload = data === 'reload'
          || (data && (data.type === 'reload' || data.reload === true));
        if (isReload) doReload();
      });
    }
    swRegistration.addEventListener('updatefound', () => {
      const worker = swRegistration.installing;
      if (!worker) return;
      worker.addEventListener('statechange', () => {
        if (worker.state === 'installed' && reg && reg.waiting) promptWorker(reg.waiting);
        else if (worker.state === 'activated') promptedWorker = null;
      });
    });
  }

  if (reg.waiting) promptWorker(reg.waiting);
  checkUpdate();
  return true;
}

export function setUpdatePromptHandler(fn) {
  onPromptRef = typeof fn === 'function' ? fn : null;
  checkForWaiting();
}

export async function requestWakeLock(reason = '') {
  if (typeof navigator === 'undefined' || !navigator.wakeLock || typeof navigator.wakeLock.request !== 'function') {
    return false;
  }
  wantLock = true;
  lockReason = reason;
  if (typeof document !== 'undefined' && document.visibilityState !== 'visible') return false;
  if (sentinel) return true;
  try {
    sentinel = await navigator.wakeLock.request('screen');
    if (typeof sentinel.addEventListener === 'function') {
      sentinel.addEventListener('release', () => { sentinel = null; });
    }
    return true;
  } catch (err) {
    void err;
    sentinel = null;
    return false;
  }
}

export function releaseWakeLock() {
  wantLock = false;
  lockReason = '';
  const s = sentinel;
  sentinel = null;
  if (!s || typeof s.release !== 'function') return false;
  try {
    Promise.resolve(s.release()).catch(() => {});
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export function watchWakeLock() {
  if (typeof document === 'undefined' || lockWatchAttached) return lockWatchAttached;
  lockWatchAttached = true;
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState !== 'visible') return;
    if (wantLock && !sentinel) void requestWakeLock(lockReason || 'reacquire');
  });
  return true;
}

export async function requestPersistent() {
  try {
    if (typeof navigator === 'undefined' || !navigator.storage || typeof navigator.storage.persist !== 'function') {
      return false;
    }
    return !!(await navigator.storage.persist());
  } catch (err) {
    void err;
    return false;
  }
}

export async function persistentStatus() {
  try {
    if (typeof navigator === 'undefined' || !navigator.storage || typeof navigator.storage.persisted !== 'function') {
      return false;
    }
    return !!(await navigator.storage.persisted());
  } catch (err) {
    void err;
    return false;
  }
}

export function tryBadging(count) {
  if (typeof navigator === 'undefined' || typeof navigator.setAppBadge !== 'function') return false;
  try {
    const value = Number.isFinite(Number(count)) ? Math.max(0, Math.round(Number(count))) : undefined;
    Promise.resolve(value === undefined ? navigator.setAppBadge() : navigator.setAppBadge(value)).catch(() => {});
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export function isStandalone() {
  try {
    if (typeof window !== 'undefined' && typeof window.matchMedia === 'function') {
      if (window.matchMedia('(display-mode: standalone)').matches) return true;
      if (window.matchMedia('(display-mode: fullscreen)').matches) return true;
    }
    return navigator.standaloneMode === true || navigator.standalone === true;
  } catch (err) {
    void err;
    return false;
  }
}

export function platformInfo() {
  const ua = (typeof navigator !== 'undefined' && navigator.userAgent) || '';
  const ios = /iPad|iPhone|iPod/.test(ua)
    || (typeof navigator !== 'undefined' && navigator.platform === 'MacIntel'
      && typeof navigator !== 'undefined' && navigator.maxTouchPoints > 1);
  return {
    ios,
    safari: /AppleWebKit/.test(ua) && !/CriOS|FxiOS|EdgiOS|OPiOS|Chrome\/|Chromium/.test(ua),
    standalone: isStandalone(),
    secure: typeof window !== 'undefined' ? window.isSecureContext === true : true,
    wakeLock: typeof navigator !== 'undefined' && 'wakeLock' in navigator,
    badging: typeof navigator !== 'undefined' && typeof navigator.setAppBadge === 'function',
    persist: typeof navigator !== 'undefined' && !!navigator.storage && typeof navigator.storage.persist === 'function',
    vibrate: typeof navigator !== 'undefined' && typeof navigator.vibrate === 'function',
  };
}

export function stopUpdatePolling() {
  if (pollTimer && typeof clearInterval !== 'undefined') clearInterval(pollTimer);
  pollTimer = 0;
  if (typeof document !== 'undefined') document.removeEventListener('visibilitychange', onVisibility);
  return true;
}
__EOF_js_upgrade_js__

mkdir -p 'js'
cat > 'js/util.js' <<'__EOF_js_util_js__'
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
__EOF_js_util_js__

mkdir -p 'js/views'
cat > 'js/views/badges.js' <<'__EOF_js_views_badges_js__'
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
__EOF_js_views_badges_js__

mkdir -p 'js/views'
cat > 'js/views/debug.js' <<'__EOF_js_views_debug_js__'
import { load, save, params, setParam, resetParams } from '../settings.js';
import { Counter } from '../counter.js';
import { createTracker } from '../pose.js';
import { listSets } from '../db.js';
import { download, pct } from '../util.js';

export default function debugView(host) {
  const counter = new Counter(params());
  let tracker = null;
  let repLog = [];
  let frames = 0;
  let replaying = false;
  let lastT = 0;

  // replay must follow the video clock, and it must never go backwards when the clip loops
  function nowMs(f) {
    if (!replaying) return Date.now();
    let t = Math.round(f.stampMs != null ? f.stampMs : video.currentTime * 1000);
    if (t <= lastT) t = lastT + 33;
    lastT = t;
    return t;
  }

  host.innerHTML = `
    <div class="dbg">
      <div class="row"><a class="btn btn-quiet" href="#/train">← train</a>
        <span class="grow"></span><span id="mode">idle</span></div>

      <h3>live</h3>
      <table>
        <tr><th>state</th><td id="o-state">–</td></tr>
        <tr><th>armed</th><td id="o-armed">–</td></tr>
        <tr><th>side</th><td id="o-side">–</td></tr>
        <tr><th>elbow L / R</th><td id="o-elbow">–</td></tr>
        <tr><th>shoulder L / R</th><td id="o-shoulder">–</td></tr>
        <tr><th>hip offset</th><td id="o-hip">–</td></tr>
        <tr><th>body angle</th><td id="o-body">–</td></tr>
        <tr><th>plank reasons</th><td id="o-reasons">–</td></tr>
        <tr><th>quality / fps</th><td id="o-q">–</td></tr>
        <tr><th>reps det / clean</th><td id="o-reps">–</td></tr>
        <tr><th>frames</th><td id="o-frames">0</td></tr>
      </table>

      <h3>thresholds</h3>
      <div class="field"><label>top <b id="v-top"></b></label><input type="range" id="r-top" min="120" max="178"></div>
      <div class="field"><label>bottom <b id="v-bottom"></b></label><input type="range" id="r-bottom" min="70" max="130"></div>
      <div class="field"><label>min rep ms <b id="v-minRep"></b></label><input type="range" id="r-minRep" min="150" max="900" step="10"></div>
      <div class="field"><label>arm hold ms <b id="v-arm"></b></label><input type="range" id="r-arm" min="800" max="6000" step="100"></div>
      <div class="row"><button class="btn btn-quiet" id="b-reset">reset overrides</button>
        <span class="grow"></span><span id="ovl"></span></div>

      <h3>replay a recording instead of the camera</h3>
      <input type="file" id="f-file" accept="video/*">
      <video id="f-video" playsinline muted loop style="width:100%;margin-top:8px;background:#000"></video>
      <div class="row" style="margin-top:8px">
        <button class="btn btn-quiet" id="f-play">play</button>
        <button class="btn btn-quiet" id="f-stop">stop</button>
        <button class="btn btn-quiet" id="f-live">use camera</button>
        <span class="grow"></span>
        <button class="btn btn-quiet" id="f-clear">clear reps</button>
      </div>

      <h3>detected reps</h3>
      <table id="t-reps"><tr><th>#</th><th>t</th><th>min</th><th>max</th><th>drop</th><th>hip</th><th>flags</th></tr></table>

      <h3>detected vs corrected, all sets</h3>
      <div class="row" style="margin:6px 0">
        <button class="btn btn-quiet" id="b-export">export counter-lab json</button>
        <button class="btn btn-quiet" id="b-diff">show disagreement</button>
      </div>
      <table id="t-sets"><tr><th>date</th><th>det</th><th>fin</th><th>Δ</th><th>preset</th></tr></table>
      <div id="diffSum" class="st"></div>
    </div>`;

  const q = (s) => host.querySelector(s);
  const video = q('#f-video');

  const sliders = [
    ['top', 'top', '°'], ['bottom', 'bottom', '°'], ['minRepMs', 'minRep', ' ms'],
  ];
  function syncSliders() {
    const cur = load();
    const p = params();
    sliders.forEach(([key, id, unit]) => {
      q('#r-' + id).value = String(p[key]);
      q('#v-' + id).textContent = p[key] + unit;
    });
    q('#r-arm').value = String(cur.armHoldMs);
    q('#v-arm').textContent = cur.armHoldMs + ' ms';
    const o = Object.keys(cur.overrides);
    q('#ovl').textContent = o.length ? 'custom: ' + o.join(', ') : 'preset: ' + cur.preset;
  }
  sliders.forEach(([key, id]) => {
    q('#r-' + id).addEventListener('input', (e) => {
      setParam(key, Number(e.target.value));
      counter.setParams(params());
      syncSliders();
    });
  });
  q('#r-arm').addEventListener('input', (e) => {
    save({ armHoldMs: Number(e.target.value) });
    counter.setArmHold(Number(e.target.value));
    syncSliders();
  });
  q('#b-reset').addEventListener('click', () => { resetParams(); counter.setParams(params()); syncSliders(); });
  syncSliders();

  function onFrame(f) {
    frames += 1;
    const out = counter.addFrame(nowMs(f), f);
    paint(out, f);
    (out.events || []).forEach((ev) => {
      if (ev.type === 'rep') {
        repLog.push(ev.data && (ev.data.rep || ev.data));
        paintReps();
      }
    });
    q('#o-frames').textContent = String(frames);
  }

  function paint(out, f) {
    if (!out) return;
    q('#o-state').textContent = out.state;
    q('#o-armed').textContent = out.armed ? 'yes ' + Math.round((out.armMs || 0)) + 'ms' : 'no';
    q('#o-side').textContent = out.side || '–';
    const a = out.angles || {};
    const fmtA = (s) => {
      const v = a[s] && a[s].elbow;
      return v == null ? '–' : Math.round(v);
    };
    const fmtS = (s) => {
      const v = a[s] && a[s].shoulder;
      return v == null ? '–' : Math.round(v);
    };
    q('#o-elbow').textContent = fmtA('left') + ' / ' + fmtA('right');
    q('#o-shoulder').textContent = fmtS('left') + ' / ' + fmtS('right');
    q('#o-hip').textContent = out.hipOffset == null ? '–' : out.hipOffset.toFixed(3);
    q('#o-body').textContent = out.bodyAngle == null ? '–' : out.bodyAngle.toFixed(1) + '°';
    q('#o-reasons').textContent = (out.plank && out.plank.reasons || []).join(', ') || 'none';
    q('#o-q').textContent = pct(out.quality) + ' / ' + Math.round(f.fps || 0);
    q('#o-reps').textContent = out.repsDetected + ' / ' + out.cleanReps;
  }

  function paintReps() {
    const t = q('#t-reps');
    t.querySelectorAll('tr:not(:first-child)').forEach((r) => r.remove());
    repLog.slice(-40).forEach((r) => {
      const tr = document.createElement('tr');
      [r.n, Math.round((r.tEnd - r.tStart) / 10) / 100 + 's', Math.round(r.minElbow || 0) + '°',
        Math.round(r.maxElbow || 0) + '°', (r.shoulderDrop || 0).toFixed(2),
        (r.hipMin > 0.18 ? 'sag' : r.hipMax < -0.14 ? 'pike' : '–'), (r.flags || []).join(' ') || 'clean']
        .forEach((v) => {
          const td = document.createElement('td');
          td.textContent = String(v);
          tr.append(td);
        });
      t.append(tr);
    });
  }

  function attachTracker(target) {
    if (tracker && tracker.dispose) tracker.dispose();
    repLog = [];
    frames = 0;
    counter.reset('debug');
    paintReps();
    tracker = await createTracker({
      video: target,
      model: load().model,
      fpsCap: load().fpsCap,
      onStatus: (k, d) => { q('#mode').textContent = 'engine · ' + k + (d ? ' ' + d : ''); },
      onFrame: (f) => { try { onFrame(f); } catch (e) { console.error(e); q('#mode').textContent = 'error ' + e.message; } },
      onError: (e) => { q('#mode').textContent = 'error: ' + e.message; },
    });
    tracker.start();
  }

  q('#f-file').addEventListener('change', (e) => {
    const file = e.target.files && e.target.files[0];
    if (!file) return;
    video.src = URL.createObjectURL(file);
    video.loop = true;
    q('#mode').textContent = 'loaded ' + file.name;
    video.addEventListener('loadeddata', () => {
      video.currentTime = 0;
      replaying = true;
      attachTracker(video);
      video.play();
      q('#mode').textContent = 'replaying ' + file.name;
    }, { once: true });
  });
  q('#f-play').addEventListener('click', () => {
    if (!video.src) return;
    if (tracker) tracker.start();
    video.play();
  });
  q('#f-stop').addEventListener('click', () => { if (tracker) tracker.stop(); video.pause(); });
  q('#f-clear').addEventListener('click', () => { counter.reset('debug'); repLog = []; frames = 0; paintReps(); });
  q('#f-live').addEventListener('click', async () => {
    video.pause();
    if (tracker) { tracker.dispose && tracker.dispose(); tracker = null; }
    const { openCamera } = await import('../camera.js');
    const cam = await openCamera(video, { facing: load().camera });
    replaying = false;
    attachTracker(video);
    q('#mode').textContent = 'camera · ' + (cam.settings.facing || load().camera);
  });

  q('#b-diff').addEventListener('click', async () => {
    const sets = await listSets();
    const t = q('#t-sets');
    t.querySelectorAll('tr:not(:first-child)').forEach((r) => r.remove());
    let det = 0;
    let fin = 0;
    let off = 0;
    sets.slice(-60).forEach((s) => {
      const d = (s.repsFinal || 0) - (s.repsDetected || 0);
      det += s.repsDetected || 0;
      fin += s.repsFinal || 0;
      if (d !== 0) off += 1;
      const tr = document.createElement('tr');
      [new Date(s.startedAt).toLocaleDateString(), s.repsDetected, s.repsFinal,
        (d > 0 ? '+' : '') + d, s.presetName].forEach((v) => {
        const td = document.createElement('td');
        td.textContent = String(v);
        tr.append(td);
      });
      t.append(tr);
    });
    q('#diffSum').textContent = sets.length + ' sets · camera ' + det + ' · kept ' + fin +
      ' · ' + off + ' sets disagreed (' + (sets.length ? Math.round((off / sets.length) * 100) : 0) + '%)';
  });

  q('#b-export').addEventListener('click', async () => {
    const sets = await listSets();
    download('counter-lab-' + Date.now() + '.json', JSON.stringify({
      at: new Date().toISOString(), params: params(), settings: load(),
      repLog, sets: sets.map((s) => ({
        day: s.day, det: s.repsDetected, fin: s.repsFinal, flags: s.flags,
        quality: s.qualityStats, preset: s.presetName, paramsUsed: s.paramsUsed,
      })),
    }, null, 2));
  });

  return {
    unmount() {
      if (tracker) { tracker.stop && tracker.stop(); tracker.dispose && tracker.dispose(); }
      video.pause();
    },
  };
}
__EOF_js_views_debug_js__

mkdir -p 'js/views'
cat > 'js/views/progress.js' <<'__EOF_js_views_progress_js__'
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
__EOF_js_views_progress_js__

mkdir -p 'js/views'
cat > 'js/views/settings.js' <<'__EOF_js_views_settings_js__'
import { load, save, params, setParam, resetParams, PRESETS } from '../settings.js';
import { exportJSON, importJSON, countSets } from '../db.js';
import { download } from '../util.js';
import { platformInfo, persistentStatus, requestPersistent, tryBadging } from '../upgrade.js';

const SEL = (id, opts, val) => `<select id="${id}">` +
  opts.map(([v, l]) => `<option value="${v}"${v === val ? ' selected' : ''}>${l}</option>`).join('') + '</select>';

export default function settingsView(host) {
  const s = load();
  const p = params();

  host.innerHTML = `
    <div class="list">
      <div class="pad"><h2 class="h1" style="margin:14px 0 4px">Depth preset</h2>
        <p class="sub" style="margin:0 0 8px">Relaxed counts a shallower bend. Strict wants an almost straight arm at the top.</p>
        ${SEL('preset', [['relaxed', 'Relaxed'], ['standard', 'Standard'], ['strict', 'Strict']], s.preset)}
      </div>
      <div class="rule"></div>
      <div class="pad"><h2 class="h1" style="margin:0 0 8px">Thresholds</h2>
        <div class="field"><label for="top">Top (lockout) angle <b id="topOut"></b></label>
          <input type="range" id="top" min="120" max="178" step="1"></div>
        <div class="field"><label for="bottom">Bottom angle <b id="bottomOut"></b></label>
          <input type="range" id="bottom" min="70" max="130" step="1"></div>
        <div class="field"><label for="minRep">Minimum rep time <b id="minRepOut"></b></label>
          <input type="range" id="minRep" min="150" max="900" step="10"></div>
        <div class="row"><button class="btn btn-quiet" id="resetP">Back to preset</button>
          <span class="grow"></span><span class="sub" id="ovl"></span></div>
      </div>
      <div class="rule"></div>
      <div class="pad"><h2 class="h1" style="margin:0 0 6px">Counting</h2>
        <label class="tog"><span>Clean reps only<span class="sub">skip flagged reps in the count</span></span><input type="checkbox" id="cleanOnly"></label>
        <label class="tog"><span>Auto-start on plank<span class="sub">begin the countdown once the plank is held</span></span><input type="checkbox" id="autoArm"></label>
        <label class="tog"><span>End set after idle<span class="sub" id="idleLbl"></span></span>
          <input type="range" id="idle" min="5" max="60" step="1" style="width:120px"></label>
        <div class="field"><label for="armHold">Plank hold before counting <b id="armHoldOut"></b></label>
          <input type="range" id="armHold" min="800" max="6000" step="100"></div>
        <div class="field"><label for="secondary">Second signal (shoulder travel)</label>
          ${SEL('secondary', [['off', 'Off — elbow angle only'], ['assist', 'Assist — flag shallow reps'], ['confirm', 'Confirm — require both']], s.secondarySignal)}
        </div>
      </div>
      <div class="rule"></div>
      <div class="pad"><h2 class="h1" style="margin:0 0 6px">Feedback</h2>
        ${SEL('voice', [['every', 'Say every rep'], ['milestones', 'Say every fifth'], ['off', 'Silent']], s.voice)}
        <label class="tog"><span>Beeps</span><input type="checkbox" id="beeps"></label>
        <label class="tog"><span>Haptics<span class="sub" id="vibHint"></span></span><input type="checkbox" id="haptics"></label>
        <label class="tog"><span>Show skeleton during a set</span><input type="checkbox" id="skeletonOnSet"></label>
      </div>
      <div class="rule"></div>
      <div class="pad"><h2 class="h1" style="margin:0 0 6px">Camera and model</h2>
        ${SEL('camera', [['environment', 'Back camera (side view)'], ['user', 'Front camera']], s.camera)}
        <div class="spacer"></div>
        ${SEL('model', [['lite', 'Pose lite — fast, usually enough'], ['full', 'Pose full — better in bad light']], s.model)}
        <div class="spacer"></div>
        <div class="field"><label for="fps">Detection rate cap <b id="fpsOut"></b></label>
          <input type="range" id="fps" min="10" max="30" step="1"></div>
        <label class="tog"><span>Manual tap-to-log<span class="sub">no camera at all</span></span><input type="checkbox" id="manualMode"></label>
      </div>
      <div class="rule"></div>
      <div class="pad"><h2 class="h1" style="margin:0 0 6px">Data</h2>
        <div class="kv"><span>saved sets on this phone</span><b class="num" id="setCount">…</b></div>
        <div class="kv"><span>persistent storage</span><b id="persist">…</b></div>
        <div class="row" style="margin-top:10px">
          <button class="btn grow" id="exportBtn">Export JSON</button>
          <button class="btn grow" id="importBtn">Import</button>
        </div>
        <input type="file" id="importFile" accept="application/json,.json" hidden>
        <div class="sub" style="margin-top:8px" id="dataMsg"></div>
      </div>
      <div class="rule"></div>
      <div class="pad"><h2 class="h1" style="margin:0 0 6px">Diagnostics</h2>
        <div class="mono" id="plat" style="white-space:pre-wrap"></div>
        <div class="row" style="margin-top:10px">
          <a class="btn grow" href="#/debug">Counter lab</a>
          <button class="btn grow" id="badgeTest">Test icon badge</button>
        </div>
      </div>
      <div class="spacer"></div><div class="spacer"></div>
    </div>`;

  const q = (sel) => host.querySelector(sel);
  const num = (id) => q('#' + id + 'Out');
  const currentFor = (key) => {
    const cur = load();
    return key in cur.overrides ? cur.overrides[key] : PRESETS[cur.preset][key];
  };

  function bindRange(id, key, fmt) {
    const el = q('#' + id);
    const out = num(id);
    el.value = String(currentFor(key));
    out.textContent = fmt(Number(el.value));
    el.addEventListener('input', () => {
      out.textContent = fmt(Number(el.value));
      setParam(key, Number(el.value));
      renderOverrideNote();
    });
  }

  function renderOverrideNote() {
    const o = Object.keys(load().overrides);
    q('#ovl').textContent = o.length ? 'custom: ' + o.join(', ') : 'following preset';
  }

  q('#preset').addEventListener('change', (e) => {
    save({ preset: e.target.value, overrides: {} });
    syncAll();
  });
  q('#resetP').addEventListener('click', () => { resetParams(); syncAll(); });

  bindRange('top', 'top', (v) => v + '°');
  bindRange('bottom', 'bottom', (v) => v + '°');
  bindRange('minRep', 'minRepMs', (v) => v + ' ms');

  const toggles = {
    cleanOnly: 'cleanOnly', autoArm: 'autoArm', beeps: 'beeps', haptics: 'haptics',
    skeletonOnSet: 'skeletonOnSet', manualMode: 'manualMode',
  };
  Object.entries(toggles).forEach(([id, key]) => {
    const el = q('#' + id);
    el.checked = !!s[key];
    el.addEventListener('change', () => save({ [key]: el.checked }));
  });
  ['voice', 'camera', 'model', 'secondarySignal'].forEach((key) => {
    const el = q('#' + (key === 'secondarySignal' ? 'secondary' : key));
    el.value = s[key];
    el.addEventListener('change', () => save({ [key]: el.value }));
  });

  q('#idle').value = String(s.endAfterIdleSec);
  q('#idleLbl').textContent = 'auto-end after ' + s.endAfterIdleSec + ' s without a rep';
  q('#idle').addEventListener('input', (e) => {
    save({ endAfterIdleSec: Number(e.target.value) });
    q('#idleLbl').textContent = 'auto-end after ' + e.target.value + ' s without a rep';
  });

  q('#armHold').value = String(s.armHoldMs);
  q('#armHoldOut').textContent = (s.armHoldMs / 1000).toFixed(1) + ' s';
  q('#armHold').addEventListener('input', (e) => {
    save({ armHoldMs: Number(e.target.value) });
    q('#armHoldOut').textContent = (Number(e.target.value) / 1000).toFixed(1) + ' s';
  });

  q('#fps').value = String(s.fpsCap);
  q('#fpsOut').textContent = s.fpsCap + ' fps';
  q('#fps').addEventListener('input', (e) => {
    save({ fpsCap: Number(e.target.value) });
    q('#fpsOut').textContent = e.target.value + ' fps';
  });

  q('#vibHint').textContent = navigator.vibrate ? 'supported here' : 'not exposed by iOS Safari';

  function syncAll() {
    const cur = load();
    const cp = params();
    q('#preset').value = cur.preset;
    q('#top').value = String(cp.top); num('top').textContent = cp.top + '°';
    q('#bottom').value = String(cp.bottom); num('bottom').textContent = cp.bottom + '°';
    q('#minRep').value = String(cp.minRepMs); num('minRep').textContent = cp.minRepMs + ' ms';
    renderOverrideNote();
  }
  syncAll();

  countSets().then((n) => { q('#setCount').textContent = String(n); }).catch(() => { q('#setCount').textContent = '?'; });
  persistentStatus().then(async (ok) => {
    q('#persist').textContent = ok ? 'granted' : 'not granted';
    if (!ok) {
      q('#persist').addEventListener('click', async () => {
        const g = await requestPersistent();
        q('#persist').textContent = g ? 'granted' : 'denied';
      });
    }
  });
  q('#persist').style.cursor = 'pointer';

  const info = platformInfo();
  q('#plat').textContent = Object.entries(info).map(([k, v]) => k.padEnd(12) + (v ? 'yes' : 'no')).join('\n');

  q('#exportBtn').addEventListener('click', async () => {
    const text = await exportJSON();
    download('pushups-backup-' + new Date().toISOString().slice(0, 10) + '.json', text);
    q('#dataMsg').textContent = 'Downloaded. Keep one copy in Files or iCloud Drive.';
  });
  q('#importBtn').addEventListener('click', () => q('#importFile').click());
  q('#importFile').addEventListener('change', async (e) => {
    const file = e.target.files && e.target.files[0];
    if (!file) return;
    const text = await file.text();
    if (!confirm('Merge sets from ' + file.name + ' into this phone?')) return;
    const res = await importJSON(text);
    q('#dataMsg').textContent = res.ok ? 'Imported ' + res.added + ' sets.' : 'Import failed: ' + res.error;
    if (res.ok) countSets().then((n) => { q('#setCount').textContent = String(n); });
  });
  q('#badgeTest').addEventListener('click', () => {
    const ok = tryBadging(7);
    q('#plat').textContent += '\nbadging: ' + (ok ? 'shown on the icon' : 'not supported in this browser');
  });

  return {};
}
__EOF_js_views_settings_js__

mkdir -p 'js/views'
cat > 'js/views/today.js' <<'__EOF_js_views_today_js__'
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
__EOF_js_views_today_js__

mkdir -p 'js/views'
cat > 'js/views/train.js' <<'__EOF_js_views_train_js__'
import { load, save, params } from '../settings.js';
import { openCamera, closeCamera, resumePreview, describeCameraError, cameraSupports } from '../camera.js';
import { createTracker } from '../pose.js';
import { Counter } from '../counter.js';
import { saveSet, listSetsForDay } from '../db.js';
import { unlockAudio, speak, playBeep, playWarning, vibrate, announceRep, countdownVoice } from '../feedback.js';
import { requestWakeLock, tryBadging } from '../upgrade.js';
import { today, dayOf, fmtClock, clamp, pct } from '../util.js';

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

  host.innerHTML = `
    <div class="counter">
      <div class="topline">
        <span id="clock">--:--</span>
        <span class="grow" id="phaseLabel" style="text-align:center">set up</span>
        <button class="btn btn-warn" id="endBtn" hidden>End</button>
      </div>
      <div id="hairline" style="height:3px;background:transparent"></div>
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
  function renderSetup() {
    phase = 'setup';
    els.overlay.style.display = '';
    lastOut = EMPTY_OUT;
    els.phaseLabel.textContent = load().manualMode ? 'manual log' : 'set up';
    els.endBtn.hidden = true;
    els.camoff.hidden = true;
    clearWarn();
    els.stage.innerHTML = `
      <div class="list">
        <div class="statusbar">
          <span class="bar grow"><i id="qbar"></i></span>
          <span class="mono" id="qtxt">0%</span>
          <span class="mono" id="fpstxt">0 fps</span>
        </div>
        <div class="pad">
          <div id="checks"></div>
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
          <label class="tog" style="border-bottom:0"><span>Manual tap-to-log<span class="sub">no camera, count with your thumb</span></span>
            <input type="checkbox" id="manualChk"></label>
          <div class="spacer"></div>
          <button class="btn btn-primary btn-big" id="startBtn">Start set</button>
          <div class="sub" style="margin-top:8px" id="hint"></div>
        </div>
      </div>`;
    els.qbar = q('#qbar');
    els.qtxt = q('#qtxt');
    els.fpstxt = q('#fpstxt');
    els.checks = q('#checks');
    const manual = load().manualMode;
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
    q('#startBtn').addEventListener('click', beginSet);
    q('#hint').textContent = load().autoArm
      ? 'Auto-start is on: hold a steady plank and the countdown begins.'
      : 'Set the phone on the floor 1.5–2.5 m away, side-on. Tap Start set, then get into position.';
    paintChecks();
  }

  function paintChecks() {
    if (!els.checks) return;
    els.checks.replaceChildren(...CHECKS.map(([k, label, hint]) => {
      const row = document.createElement('div');
      row.className = 'chk ' + (checkState[k] ? 'ok' : 'bad');
      const mk = document.createElement('span');
      mk.className = 'mk';
      mk.textContent = checkState[k] ? '✓' : '·';
      const t = document.createElement('span');
      t.textContent = label;
      const why = document.createElement('span');
      why.className = 'why';
      why.textContent = checkState[k] ? '' : (checkWhy[k] || hint);
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
    phase = 'countdown';
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
    phase = 'set';
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
    tickTimer = setInterval(tick, 250);
  }

  function renderCountFace() {
    els.overlay.style.display = load().skeletonOnSet ? '' : 'none';
    els.stage.innerHTML = `
      <div id="repnum" class="num">0</div>
      <div id="chip">get into plank</div>
      <div class="corr">
        <button class="step" id="minus" aria-label="one fewer">−</button>
        <span class="n" id="adj"></span>
        <button class="step" id="plus" aria-label="one more">+</button>
      </div>`;
    els.repnum = q('#repnum');
    els.chip = q('#chip');
    els.adj = q('#adj');
    q('#minus').addEventListener('click', () => correct(-1));
    q('#plus').addEventListener('click', () => correct(1));
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
    if (els.repnum.textContent !== String(n)) {
      els.repnum.textContent = String(n);
      els.repnum.classList.add('tick');
      setTimeout(() => els.repnum && els.repnum.classList.remove('tick'), 170);
    }
    if (els.adj) els.adj.textContent = manualAdj === 0 ? '' : (manualAdj > 0 ? '+' + manualAdj : String(manualAdj));
    if (els.chip && !load().manualMode) {
      const flagged = lastOut.repsDetected - lastOut.cleanReps;
      els.chip.textContent = lastOut.armed
        ? lastOut.cleanReps + ' clean' + (flagged > 0 ? ' · ' + flagged + ' flagged' : '')
        : 'get into plank' + (lastOut.armMs > 200 ? ' (' + Math.round(lastOut.armMs / 1000) + 's)' : '');
    }
  }

  function startManualSet() {
    phase = 'set';
    setStart = Date.now();
    lastRepAt = setStart;
    manualAdj = 0;
    reps = [];
    els.endBtn.hidden = false;
    els.endBtn.textContent = 'End';
    els.phaseLabel.textContent = 'manual log';
    els.stage.innerHTML = `
      <div id="repnum" class="num">0</div>
      <div id="chip">tap here to log a rep</div>
      <div class="corr">
        <button class="step" id="minus" aria-label="one fewer">−</button>
        <span class="n" id="adj"></span>
        <button class="step" id="plus" aria-label="one more">+</button>
      </div>`;
    els.repnum = q('#repnum');
    els.chip = q('#chip');
    els.adj = q('#adj');
    q('#minus').addEventListener('click', (e) => { e.stopPropagation(); correct(-1); });
    q('#plus').addEventListener('click', (e) => { e.stopPropagation(); correct(1); });
    els.stage.addEventListener('click', manualTap);
    tickTimer = setInterval(tick, 500);
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
    phase = 'summary';
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
    els.phaseLabel.textContent = 'summary';
    els.stage.innerHTML = `
      <div class="sheet">
        <div class="finum"><input id="finalIn" type="number" inputmode="numeric" min="0" max="999"></div>
        <div class="sub" style="text-align:center;margin-top:-4px">final reps — correct it if the camera missed one</div>
        <div class="row" style="justify-content:center;margin:10px 0">
          <button class="step" id="sminus" aria-label="one fewer">−</button>
          <button class="step" id="splus" aria-label="one more">+</button>
        </div>
        <div class="kv"><span>detected</span><b class="num" id="detOut"></b></div>
        <div class="kv"><span>adjustment</span><b class="num" id="adjOut"></b></div>
        <div class="kv"><span>duration</span><b class="num" id="durOut"></b></div>
        <div class="kv"><span>tracking</span><b class="num" id="qualOut"></b></div>
        <div class="rule"></div>
        <div class="flags" id="flagRow"></div>
        <div class="field"><label for="notes">notes</label><textarea id="notes" rows="2" placeholder="optional"></textarea></div>
        <div class="row" style="margin-top:14px">
          <button class="btn btn-quiet grow" id="again">New set</button>
          <button class="btn btn-primary grow" id="save">Save set</button>
        </div>
        <div class="sub" style="margin-top:10px" id="saveMsg"></div>
      </div>`;
    const inp = q('#finalIn');
    inp.value = String(d.final);
    q('#detOut').textContent = String(d.detected);
    q('#durOut').textContent = Math.round(d.durationMs / 1000) + ' s';
    q('#qualOut').textContent = d.quality.fpsMean + ' fps · ' + pct(d.quality.visMean) +
      (d.quality.breaks ? ' · ' + d.quality.breaks + ' breaks' : '');
    const adjOut = q('#adjOut');
    const sync = () => {
      const v = clamp(parseInt(inp.value, 10) || 0, 0, 999);
      d.final = v;
      const adj = v - d.detected;
      adjOut.textContent = (adj > 0 ? '+' : '') + adj;
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
      paintPill(f);
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
    els.hairline.style.background = 'var(--rose)';
    els.stage.classList.add('dim');
  }

  function clearWarn() {
    els.warnbox.hidden = true;
    els.hairline.style.background = 'transparent';
    els.stage.classList.remove('dim');
    lostShown = false;
  }

  function paintPill(f) {
    els.pill.className = 'pill' + (f.quality < 0.35 ? ' bad' : f.quality < 0.6 ? ' warn' : '');
    els.pillText.textContent = Math.round(f.fps) + ' fps · ' + pct(f.quality) + ' tracked';
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
      if (cdTimer) clearInterval(cdTimer);
      if (tickTimer) clearInterval(tickTimer);
      if (tracker) { if (tracker.stop) tracker.stop(); if (tracker.dispose) tracker.dispose(); }
      if (cam) closeCamera(cam);
    },
  };
}
__EOF_js_views_train_js__

mkdir -p .
cat > 'manifest.webmanifest' <<'__EOF_manifest_webmanifest__'
{
  "name": "Pushups",
  "short_name": "Pushups",
  "description": "Camera pushup counter and long-term progress tracker",
  "id": "/pushups-pwa/",
  "start_url": "./?source=pwa",
  "scope": "./",
  "display": "standalone",
  "display_override": ["standalone", "fullscreen"],
  "background_color": "#0E1A18",
  "theme_color": "#0E1A18",
  "orientation": "any",
  "icons": [
    { "src": "icons/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "icons/icon-512.png", "sizes": "512x512", "type": "image/png" },
    { "src": "icons/maskable-192.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable" },
    { "src": "icons/maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ]
}
__EOF_manifest_webmanifest__

mkdir -p .
cat > 'README.md' <<'__EOF_README_md__'
# Pushups

An installable iPhone web app that counts pushups with the camera and keeps your progress for years.
No App Store, no build step, no backend (until the optional push phase). Plain HTML, CSS and ES
modules served as static files over HTTPS.

Phase 1 is the counter: setup screen, set lifecycle, correction, local saving, voice, offline,
and a hidden counter lab for tuning.

## Install it on your iPhone

```bash
cd ~/Projects/pushups
./scripts/deploy.sh -m "phase 1: counter core"
```

That creates the GitHub repo, enables Pages, pushes, and prints the live URL
(`https://<you>.github.io/pushups-pwa/`). Then, on the phone:

1. Open that URL in **Safari** (Chrome on iOS cannot install PWAs).
2. Share ▸ **Add to Home Screen**.
3. Launch it from the icon — not from a Safari tab. The camera only works in the standalone window.
4. Allow the camera when asked. First launch downloads ~20 MB of model and WASM, so let it finish
   before you go offline.

Everything after that is on the phone: IndexedDB holds your sets, the service worker holds the code,
the pose model and the wasm, so the app counts with the laptop shut and the phone in airplane mode.

## Everyday use

- **Train** — set the phone on the floor, 1.5–2.5 m away, side-on to you. Fix the four checklist
  lines, tap Start set, hold the plank, count. `−` / `+` correct mid-set, End finishes it, and the
  summary lets you rewrite the number before saving. The saved record keeps both
  `repsDetected` (what the camera saw) and `repsFinal` (what you kept).
- **Today** — total for the day and the list of sets, with delete.
- **Settings** — depth preset, threshold sliders, clean-reps-only, auto-start, voice, camera,
  model, export/import, and diagnostics.
- **Counter lab** (Settings ▸ Counter lab, or `#/debug`) — live angles and state-machine state,
  threshold sliders you can move mid-set, and video-file replay so you can tune the counter while
  lying on the sofa instead of doing pushups.

## Backup

Sets live in the phone's IndexedDB, which iOS can wipe if storage pressure gets bad and you have
never opened the app. Settings ▸ Data ▸ **Export JSON** writes a file to Share — keep one in Files
or iCloud Drive. Import merges, it does not overwrite.

## Update

Change the code on the Mac, run `./scripts/deploy.sh -m "…"`. The next time the app is opened with
a network connection the service worker finds the new build and shows
*“Update available — tap to reload”*. Data survives; the database schema is versioned and
migrations run on open.

## Development

```bash
./scripts/dev.sh              # http://localhost:8080 — desktop only, the camera works there
./scripts/dev.sh --tunnel     # prints a trycloudflare.com URL an iPhone can reach
```

iOS refuses the camera on plain `http://` LAN addresses, so a phone needs real HTTPS. The tunnel is
fine for a quick check but the URL changes every restart, which resets the camera permission and the
offline cache. Test properly from the Pages URL.

```bash
bash tools/build-stamp.sh     # rewrite sw.js: new cache version + precache list
bash tools/fetch-assets.sh    # re-download MediaPipe wasm, models, fonts, regenerate icons
node tests/counter.test.mjs   # counter engine regression tests
```

## Layout

```
index.html            app shell, tab bar, service-worker registration
manifest.webmanifest  name, icons, standalone display
sw.js                 generated: versioned cache + precache list + update flow
css/app.css           palette, safe-area insets, dark and light
js/main.js            hash router, update prompt, wake-lock and storage sentinels
js/camera.js          getUserMedia lifecycle + human recovery copy
js/pose.js            MediaPipe landmarker, gpu→cpu fallback, 15–30 fps, skeleton overlay
js/counter.js         state machine: hysteresis, arm gate, flags, presets, one-tap debounce
js/one-euro.js        smoothing for elbow angle
js/workout.js         set lifecycle helpers (modes arrive in phase 3)
js/db.js              IndexedDB v1: sets, reps, meta + export/import
js/stats.js           aggregation (phase 2)
js/badges.js          rule engine (phase 3)
js/plans.js           progression plans (phase 3)
js/reminders.js       due-today card, Badging API, .ics (phase 3)
js/feedback.js        voice, beeps, haptics
js/upgrade.js         update prompt, wake lock, persistent storage, badging
js/util.js            small DOM/format helpers
js/views/*            today, train, progress, badges, settings, debug
vendor/mediapipe/     tasks-vision bundle + wasm, self-hosted
models/               pose_landmarker_lite.task, pose_landmarker_full.task
fonts/                Barlow Semi Condensed (the rep number), IBM Plex Sans (everything else)
icons/                generated app icons
tools/                asset fetcher, icon generator, sw stamper, dev server
scripts/              dev.sh, deploy.sh
```

## Roadmap

| phase | what |
|---|---|
| 1 | counter core, setup, lifecycle, correction, saving, voice, offline, counter lab |
| 2 | Today with goal ring, History heatmap, charts, records, goals, streaks, export/import polish |
| 3 | badge engine, workout modes, plans, Layer A reminders (in-app card, icon badge, `.ics`) |
| 4 | threshold tuning from your detected-vs-corrected data, performance, accessibility |
| 5 | optional Layer B Web Push via a Cloudflare Worker with VAPID + cron |

## Known limits in this build

- The counter reads a 2D skeleton. A side view in normal light is the reliable case; heavy shadows,
  a cluttered background behind your arms, or the phone closer than ~1.2 m will cost accuracy.
- `navigator.vibrate` is not exposed to iOS Safari, so haptics stay off on the phone even when
  enabled. Beeps and voice carry the feedback.
- The Badging API is used when present; in a plain Safari tab iOS ignores it, so the icon badge only
  appears for a Home Screen install.
- Offline is proven after a first successful load with the model fetched. Clearing Safari website
  data, or iOS deciding the app is stale, drops the cache — reopen it online once and it rebuilds.
- Phase 2/3 screens are placeholders: tabs exist, content arrives later. Recorded data is already in
  the final schema, so nothing needs re-entering.
__EOF_README_md__

mkdir -p 'scripts'
cat > 'scripts/deploy.sh' <<'__EOF_scripts_deploy_sh__'
#!/usr/bin/env bash
# Build stamp + commit + push to GitHub Pages. Safe to re-run after every phase.
#   ./scripts/deploy.sh -m "phase 1: counter core"
# Optional: REPO_NAME=whatever PRIVATE=1 ./scripts/deploy.sh -m "..."
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_NAME="${REPO_NAME:-pushups-pwa}"
MSG="update"
while [ $# -gt 0 ]; do
  case "$1" in
    -m) MSG="${2:-update}"; shift 2 ;;
    *) echo "ignoring arg: $1"; shift ;;
  esac
done

command -v gh >/dev/null 2>&1 || { echo "gh not found — brew install gh && gh auth login"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git not found"; exit 1; }

USER_LOGIN="$(gh api user -q .login)"
GIT_AUTHOR=()
if ! git config --get user.email >/dev/null 2>&1; then
  GIT_AUTHOR=(-c "user.name=${USER_LOGIN}" -c "user.email=${USER_LOGIN}@users.noreply.github.com")
fi

[ -d .git ] || git init -q -b main
BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo main)"

if ! git remote get-url origin >/dev/null 2>&1; then
  if gh repo view "$USER_LOGIN/$REPO_NAME" >/dev/null 2>&1; then
    echo "reusing existing repo $USER_LOGIN/$REPO_NAME"
  else
    echo "creating repo $USER_LOGIN/$REPO_NAME ($([ "${PRIVATE:-0}" = "1" ] && echo private || echo public))"
    if [ "${PRIVATE:-0}" = "1" ]; then
      gh repo create "$REPO_NAME" --private --source=. --description "Camera pushup counter PWA" >/dev/null
    else
      gh repo create "$REPO_NAME" --public --source=. --description "Camera pushup counter PWA" >/dev/null
    fi
  fi
fi
git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$USER_LOGIN/$REPO_NAME.git"

bash tools/build-stamp.sh

if ! gh api "repos/$USER_LOGIN/$REPO_NAME/pages" >/dev/null 2>&1; then
  echo "enabling GitHub Pages (branch $BRANCH, /)"
  printf '{"source":{"branch":"%s","path":"/"},"message":"enable pages"}' "$BRANCH" \
    | gh api --method POST "repos/$USER_LOGIN/$REPO_NAME/pages" --input - >/dev/null \
    || echo "  (could not enable Pages automatically — turn it on at Settings ▸ Pages, branch $BRANCH, folder /)"
fi

git add -A
if git diff --cached --quiet; then
  echo "nothing new to commit"
else
  git "${GIT_AUTHOR[@]+"${GIT_AUTHOR[@]}"}" commit -q -m "$MSG"
  echo "committed: $MSG"
fi
git push -q -u origin "$BRANCH"

URL="https://$USER_LOGIN.github.io/$REPO_NAME/"
echo
echo "pushed — waiting for Pages to serve $URL"
for _ in $(seq 1 24); do
  code=$(curl -sS -o /dev/null -w '%{http_code}' "$URL" || echo 000)
  if [ "$code" = "200" ]; then echo "LIVE  $URL"; exit 0; fi
  sleep 5
done
echo "last status $code — Pages can take a couple of minutes. Check with:"
echo "  gh api repos/$USER_LOGIN/$REPO_NAME/pages"
echo "  $URL"
__EOF_scripts_deploy_sh__

mkdir -p 'scripts'
cat > 'scripts/dev.sh' <<'__EOF_scripts_dev_sh__'
#!/usr/bin/env bash
# Local iteration: stamp the service worker, serve the folder, and (optionally) put it behind real
# HTTPS so an iPhone can reach it before you deploy.
#
#   ./scripts/dev.sh              # http://localhost:8080 — desktop testing only
#   ./scripts/dev.sh --tunnel     # also prints a throwaway https://<random>.trycloudflare.com URL
#
# iOS blocks the camera on a plain http:// LAN address, so a phone must reach the app over real
# HTTPS. The tunnel URL works but changes every time it restarts — treat it as a smoke test only.
# The stable install is the Pages URL from ./scripts/deploy.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
bash tools/build-stamp.sh
PORT="${PORT:-8080}"

if [ "${1:-}" = "--tunnel" ]; then
  if ! command -v cloudflared >/dev/null 2>&1; then
    echo "cloudflared not found — brew install cloudflared"; exit 1
  fi
  ( cloudflared tunnel --url "http://localhost:$PORT" 2>&1 \
    | sed -n 's/.*https:\/\/\([a-z0-9-]*\)\.trycloudflare\.com.*/CLOUDFLARE https:\/\/\1.trycloudflare.com/p' & )
fi

echo "serving $PWD at http://localhost:$PORT  (ctrl-c to stop)"
exec /usr/bin/python3 tools/serve.py "$PORT"
__EOF_scripts_dev_sh__

mkdir -p 'tests'
cat > 'tests/counter.test.mjs' <<'__EOF_tests_counter_test_mjs__'
// node tests/counter.test.mjs
import { Counter, angleBetween, hipOffsetOf, bodyAngleOf, elbowAngle } from '../js/counter.js';

let failures = 0;
function check(name, cond) {
  const line = `${cond ? 'PASS' : 'FAIL'}  ${name}`;
  if (!cond) failures++;
  console.log(line);
}

const FPS = 40;
const STEP = 1000 / FPS;
const L = 0.37;
const ANKLE = { x: 0.72, y: 0.53 };
const HIP_X = 0.5;
const WRIST_R = 0.12;

// Plausible side-view plank: mid-shoulder / mid-hip / mid-ankle on a line that tilts with depth.
// phi (deg) is exactly what bodyAngleOf() reports, so tilt == 45 gives a kneeling-looking shape.
// The wrist is placed on a circle of radius 0.12 around the elbow, rotated by the requested
// elbow angle away from the upper arm — the landmarks really do produce that angle.
function makeLandmarks({ angle, depth = 0, hipOff = 0, tilt = null, vis = 0.95 }) {
  const phi = ((tilt === null ? 3 + 7 * depth : tilt)) * Math.PI / 180;
  const S = { x: ANKLE.x - L * Math.cos(phi), y: ANKLE.y + L * Math.sin(phi) };
  const dx = ANKLE.x - S.x;
  const dy = ANKLE.y - S.y;
  const len = Math.hypot(dx, dy);
  let nx = -dy, ny = dx;
  if (ny < 0) { nx = -nx; ny = -ny; }
  const t = (HIP_X - S.x) / dx;
  const hipY = S.y + (hipOff * len * len - (HIP_X - S.x) * nx) / ny;
  void t;
  const H = { x: HIP_X, y: hipY };
  const K = { x: S.x + 0.78 * dx, y: S.y + 0.78 * dy };

  const E = { x: S.x + 0.06, y: S.y + 0.11 };
  let ux = S.x - E.x, uy = S.y - E.y;
  const um = Math.hypot(ux, uy);
  ux /= um; uy /= um;
  const th = angle * Math.PI / 180;
  const W = {
    x: E.x + WRIST_R * (ux * Math.cos(th) - uy * Math.sin(th)),
    y: E.y + WRIST_R * (ux * Math.sin(th) + uy * Math.cos(th)),
  };
  const N = { x: S.x - 0.05, y: S.y - 0.02 };

  const lm = Array.from({ length: 33 }, () => ({ x: 0, y: 0, z: 0, visibility: 0 }));
  // left and right overlap in a true side view; the far side is slightly less visible
  const put = (i, p, v) => { lm[i] = { x: p.x, y: p.y, z: 0, visibility: v }; };
  const pairs = [[11, 12, S], [13, 14, E], [15, 16, W], [23, 24, H], [25, 26, K], [27, 28, ANKLE]];
  for (const [li, ri, p] of pairs) { put(li, p, vis); put(ri, p, vis * 0.97); }
  put(0, N, vis);
  return lm;
}

function makeFrame(opts) {
  const landmarks = makeLandmarks(opts);
  const visVals = [11, 12, 13, 14, 15, 16, 23, 24].map((i) => landmarks[i].visibility);
  const quality = visVals.reduce((a, b) => a + b, 0) / visVals.length;
  return { landmarks, present: opts.present !== false, quality, fps: FPS };
}

// angle/depth schedule for one full rep
function repFrames(t0, count, { topAngle = 178, bottomAngle = 92, downMs = 800, upMs = 700, topDwellMs = 300, depthFromAngle = true, forceDepth = null, hipSagFrames = null } = {}) {
  const frames = [];
  let t = t0;
  const downN = Math.round(downMs / STEP);
  const upN = Math.round(upMs / STEP);
  const dwellN = Math.round(topDwellMs / STEP);
  for (let r = 0; r < count; r++) {
    for (let i = 1; i <= downN; i++) {
      const a = topAngle + (bottomAngle - topAngle) * (i / downN);
      const d = depthFromAngle ? (topAngle - a) / (topAngle - bottomAngle) : forceDepth * (i / downN);
      const opt = { angle: a, depth: Math.max(0, Math.min(1, d)) };
      if (hipSagFrames && i > hipSagFrames.start && i <= hipSagFrames.end) opt.hipOff = hipSagFrames.value;
      frames.push({ t, opt });
      t += STEP;
    }
    for (let i = 1; i <= upN; i++) {
      const a = bottomAngle + (topAngle - bottomAngle) * (i / upN);
      const d = depthFromAngle ? (topAngle - a) / (topAngle - bottomAngle) : forceDepth * (1 - i / upN);
      frames.push({ t, opt: { angle: a, depth: Math.max(0, Math.min(1, d)) } });
      t += STEP;
    }
    for (let i = 0; i < dwellN; i++) {
      frames.push({ t, opt: { angle: topAngle, depth: 0 } });
      t += STEP;
    }
  }
  return { frames, tEnd: t };
}

function holdFrames(t0, count, opts = {}) {
  const out = [];
  let t = t0;
  for (let i = 0; i < count; i++) { out.push({ t, opt: { angle: 178, depth: 0, ...opts } }); t += STEP; }
  return { frames: out, tEnd: t };
}

function run(c, specList) {
  let last = null;
  const reps = [];
  let armBreaks = 0;
  for (const { t, opt, present } of specList) {
    const o = present === false ? { ...opt, present: false } : opt;
    last = c.addFrame(t, makeFrame(o));
    for (const e of last.events) {
      if (e.type === 'rep') reps.push(e.data);
      else armBreaks++;
    }
  }
  return { ...last, allReps: reps, armBreaks };
}

function freshCounter(extra = {}) {
  const c = new Counter({ top: 155, bottom: 100, minRepMs: 400, cleanOnly: false, secondarySignal: 'assist', ...extra });
  return c;
}

// Arm the counter with a clean, valid plank.
function arm(c, t0) {
  const { frames, tEnd } = holdFrames(t0, Math.ceil(3000 / STEP) + 20);
  const out = run(c, frames);
  return { out, t: tEnd };
}

/* ---------- sanity: the generator really produces the requested geometry ---------- */
{
  const lm = makeLandmarks({ angle: 123, depth: 0.5, hipOff: 0.09 });
  check('generator: landmarks produce the requested elbow angle', Math.abs(elbowAngle(lm, 'left') - 123) < 0.5);
  check('generator: requested hip offset is reproduced', Math.abs(hipOffsetOf(lm, 'left') - 0.09) < 0.005);
  check('generator: sag (hip below the shoulder-ankle line) is POSITIVE', hipOffsetOf(makeLandmarks({ angle: 160, hipOff: 0.2 }), 'left') > 0);
  check('generator: pike (hip above the line) is NEGATIVE', hipOffsetOf(makeLandmarks({ angle: 160, hipOff: -0.2 }), 'left') < 0);
  check('generator: body angle of the flat plank is small', Math.abs(bodyAngleOf(makeLandmarks({ angle: 178 }), 'left')) < 12);
  check('generator: 45 deg tilt reads 45 deg', Math.abs(bodyAngleOf(makeLandmarks({ angle: 178, tilt: 45 }), 'left') - 45) < 0.5);
  check('helper: angleBetween vertex maths', Math.abs(angleBetween({ x: 0, y: 1 }, { x: 0, y: 0 }, { x: 1, y: 0 }) - 90) < 1e-9);
}

/* ---------- 1. ten clean full-depth reps ---------- */
{
  const c = freshCounter();
  const a = arm(c, 0);
  check('setup: plank arms after 3s of valid frames', a.out.armed === true && a.out.reps === 0);
  const spec = repFrames(a.t, 10);
  const out = run(c, spec.frames);
  const flags = out.allReps.length ? out.allReps[out.allReps.length - 1].flags : ['<no reps>'];
  console.log('      T1 reps: ' + JSON.stringify(out.allReps.map((r) => ({ n: r.n, f: r.flags, dur: Math.round(r.durationMs), min: +r.minElbow.toFixed(1), mx: r.maxElbow === null ? null : +r.maxElbow.toFixed(1), drop: +r.shoulderDrop.toFixed(3), hipMax: r.hipMax === null ? null : +r.hipMax.toFixed(3) }))));
  check('T1 ten clean reps -> reps=10', out.reps === 10);
  check('T1 repsDetected=10 and cleanReps=10', out.repsDetected === 10 && out.cleanReps === 10);
  check('T1 zero flags on the last rep', flags.length === 0);
  console.log('      T1 detail: reps=' + out.reps + ' clean=' + out.cleanReps + ' detected=' + out.repsDetected + ' lastRepFlags=' + JSON.stringify(flags) + ' state=' + out.state + ' side=' + out.side);
  if (out.lastRep) console.log('      T1 lastRep: ' + JSON.stringify({ minElbow: +out.lastRep.minElbow.toFixed(1), maxElbow: +out.lastRep.maxElbow.toFixed(1), durationMs: Math.round(out.lastRep.durationMs), shoulderDrop: +out.lastRep.shoulderDrop.toFixed(3), hipMax: out.lastRep.hipMax === null ? null : +out.lastRep.hipMax.toFixed(3) }));
}

/* ---------- 2. walking into frame ---------- */
{
  const c = freshCounter();
  const spec = [];
  // 2 s of no pose while the elbows swing through a full rep shape
  let t = 0;
  for (let i = 0; i < Math.round(2000 / STEP); i++) {
    const phase = i / Math.round(2000 / STEP);
    const angle = 178 - 120 * Math.sin(phase * Math.PI);
    spec.push({ t, opt: { angle, depth: phase }, present: false });
    t += STEP;
  }
  // now a valid plank, held for 2 s (still under the 2.5 s arm hold) with one more rep shape
  for (let i = 0; i < Math.round(1000 / STEP); i++) { spec.push({ t, opt: { angle: 178, depth: 0 } }); t += STEP; }
  for (const f of repFrames(t, 1, { downMs: 400, upMs: 400 }).frames) spec.push(f);
  t += repFrames(t, 1, { downMs: 400, upMs: 400 }).tEnd - t;
  for (let i = 0; i < Math.round(2000 / STEP); i++) { spec.push({ t, opt: { angle: 178, depth: 0 } }); t += STEP; }
  const out = run(c, spec);
  check('T2 walking in + rep shape before arm -> 0 reps', out.reps === 0 && out.repsDetected === 0 && out.cleanReps === 0);
  check('T2 not armed during the invalid window', out.armed === false || out.reps === 0);
  console.log('      T2 detail: reps=' + out.reps + ' detected=' + out.repsDetected + ' armed=' + out.armed + ' reasons=' + JSON.stringify(out.plank.reasons) + ' state=' + out.state);
}

/* ---------- 3. kneeling / resting after 5 reps ---------- */
{
  const c = freshCounter();
  const a = arm(c, 0);
  run(c, repFrames(a.t, 5).frames);
  const before = { ...a };
  const afterReps = c.reps;
  check('T3 five reps counted before the rest', afterReps === 5);
  let sawArmBreak = false;
  let t = a.t + 300;
  for (let i = 0; i < 60; i++) {
    const out = c.addFrame(t, makeFrame({ angle: 170, depth: 0, tilt: 45 }));
    if (out.events.some((e) => e.type === 'armBreak')) sawArmBreak = true;
    t += STEP;
  }
  check('T3 kneeling emits armBreak', sawArmBreak);
  check('T3 kneeling adds zero reps', c.reps === 5);
  check('T3 counter disarms and stays idle', c.armed === false && c.state === 'idle');
  console.log('T3 before=' + JSON.stringify({ reps: before.out ? before.out.reps : null }) + ' now=' + c.reps + ' detected=' + c.repsDetected);
}

/* ---------- 4. double beat at the bottom counts one ---------- */
{
  const c = freshCounter();
  const a = arm(c, 0);
  let t = a.t;
  const spec = [];
  const push = (angle, depth, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) spec.push({ t, opt: { angle, depth } });
    t += STEP * n;
  };
  const pushRamp = (from, to, depth, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) {
      const a2 = from + (to - from) * (i / n);
      spec.push({ t, opt: { angle: a2, depth } });
      t += STEP;
    }
  };
  pushRamp(178, 90, 1, 800);
  pushRamp(90, 105, 0.85, 300);
  pushRamp(105, 92, 1, 300);
  pushRamp(92, 178, 0, 700);
  push(178, 0, 400);
  const out = run(c, spec);
  check('T4 double beat at the bottom counts ONE rep', out.reps === 1 && out.repsDetected === 1);
  console.log('      T4 detail: reps=' + out.reps + ' detected=' + out.repsDetected + ' flags=' + JSON.stringify(out.allReps.map((r) => r.flags)));
}

/* ---------- 5. shallow rep, bottom=100, bottoms at 118 ---------- */
{
  // documented rule: a descent only counts if it either (a) reaches bottom on the smoothed angle,
  // or (b) proves real depth with shoulder travel >= 0.10 (assist/confirm modes). Then minElbow >
  // bottom earns the 'half' flag.
  const c = freshCounter();
  const a = arm(c, 0);
  let t = a.t;
  const spec = [];
  const ramp = (from, to, depthFrom, depthTo, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) {
      const k = i / n;
      spec.push({ t, opt: { angle: from + (to - from) * k, depth: depthFrom + (depthTo - depthFrom) * k } });
      t += STEP;
    }
  };
  // shallow with NO body travel -> must not count
  ramp(178, 118, 0, 0.1, 800);
  ramp(118, 178, 0.1, 0, 700);
  for (let i = 0; i < 12; i++) { spec.push({ t, opt: { angle: 178, depth: 0 } }); t += STEP; }
  let out = run(c, spec);
  console.log('      T5a no-travel shallow: reps=' + out.reps + ' detected=' + out.repsDetected + ' clean=' + out.cleanReps);
  check('T5a shallow without shoulder travel counts 0', out.reps === 0 && out.repsDetected === 0);

  // shallow (118) but the body really travelled down (depth 1 -> ~0.12 normalised) -> counts, flagged half
  const spec2 = [];
  let t2 = t;
  const ramp2 = (from, to, depthFrom, depthTo, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) {
      const k = i / n;
      spec2.push({ t: t2, opt: { angle: from + (to - from) * k, depth: depthFrom + (depthTo - depthFrom) * k } });
      t2 += STEP;
    }
  };
  ramp2(178, 118, 0, 1, 800);
  ramp2(118, 178, 1, 0, 700);
  for (let i = 0; i < 12; i++) { spec2.push({ t: t2, opt: { angle: 178, depth: 0 } }); t2 += STEP; }
  out = run(c, spec2);
  const rep = out.allReps.length ? out.allReps[out.allReps.length - 1] : null;
  console.log('      T5b deep-travel shallow: reps=' + out.reps + ' detected=' + out.repsDetected + ' flags=' + JSON.stringify(rep ? rep.flags : null) + ' minElbow=' + (rep ? rep.minElbow.toFixed(1) : '-') + ' shoulderDrop=' + (rep ? rep.shoulderDrop.toFixed(3) : '-'));
  check('T5b shallow-with-travel counts 1 rep and flags it half', out.reps === 1 && !!rep && rep.flags.includes('half'));

  // same rep, cleanOnly -> the flagged rep must not raise `reps` but must raise `repsDetected`
  const c2 = freshCounter({ cleanOnly: true });
  const a2 = arm(c2, 0);
  const spec3 = [];
  let t3 = a2.t;
  const ramp3 = (from, to, d0, d1, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) {
      const k = i / n;
      spec3.push({ t: t3, opt: { angle: from + (to - from) * k, depth: d0 + (d1 - d0) * k } });
      t3 += STEP;
    }
  };
  ramp3(178, 118, 0, 1, 800);
  ramp3(118, 178, 1, 0, 700);
  for (let i = 0; i < 12; i++) { spec3.push({ t: t3, opt: { angle: 178, depth: 0 } }); }
  const out2 = run(c2, spec3);
  console.log('      T5c cleanOnly: reps=' + out2.reps + ' detected=' + out2.repsDetected + ' clean=' + out2.cleanReps + ' flags=' + JSON.stringify(out2.trace.length ? null : null));
  check('T5c cleanOnly keeps flagged reps out of `reps` but keeps repsDetected', out2.reps === 0 && out2.repsDetected === 1 && out2.cleanReps === 0);
}

/* ---------- 6. sagging hips ---------- */
{
  const c = freshCounter();
  const a = arm(c, 0);
  const spec = [];
  let t = a.t;
  const downN = Math.round(800 / STEP);
  for (let i = 1; i <= downN; i++) {
    const k = i / downN;
    const opt = { angle: 178 + (92 - 178) * k, depth: k };
    // a brief, real sag excursion (5 frames at +0.25) — sustained sag would disarm instead
    if (i >= 14 && i <= 18) opt.hipOff = 0.25;
    spec.push({ t, opt });
    t += STEP;
  }
  for (let i = 1; i <= Math.round(700 / STEP); i++) {
    const k = i / Math.round(700 / STEP);
    spec.push({ t, opt: { angle: 92 + (178 - 92) * k, depth: 1 - k } });
    t += STEP;
  }
  for (let i = 0; i < 12; i++) { spec.push({ t, opt: { angle: 178, depth: 0 } }); t += STEP; }
  const out = run(c, spec);
  const rep = out.allReps.length ? out.allReps[out.allReps.length - 1] : null;
  console.log('      T6 detail: reps=' + out.reps + ' flags=' + JSON.stringify(rep ? rep.flags : null) + ' hipMax=' + (rep && rep.hipMax !== null ? rep.hipMax.toFixed(3) : '-') + ' plankValid=' + out.plank.valid);
  check('T6 sag excursion flags the rep', out.reps === 1 && !!rep && rep.flags.includes('sag'));
  check('T6 a brief sag does not break the arm lock', c.armed === true);
}

/* ---------- 7. minRepMs rejects a bounce ---------- */
{
  const c = freshCounter();
  const a = arm(c, 0);
  let t = a.t;
  const spec = [];
  const ramp = (from, to, depth, ms) => {
    const n = Math.max(1, Math.round(ms / STEP));
    for (let i = 1; i <= n; i++) {
      spec.push({ t, opt: { angle: from + (to - from) * (i / n), depth } });
      t += STEP;
    }
  };
  ramp(178, 92, 1, 75);
  ramp(92, 178, 0, 75);
  for (let i = 0; i < 20; i++) { spec.push({ t, opt: { angle: 178, depth: 0 } }); t += STEP; }
  const out = run(c, spec);
  console.log('      T7 detail: reps=' + out.reps + ' detected=' + out.repsDetected + ' state=' + out.state + ' armed=' + out.armed + ' traceMinElbow=' + Math.min(...c.trace.map((x) => (x.elbowFiltered === null ? 999 : x.elbowFiltered))).toFixed(1));
  check('T7 150 ms bounce rejected (minRepMs=400)', out.reps === 0 && out.repsDetected === 0);

  // same rep shape but slow enough to bottom, with minRepMs raised -> the duration gate rejects it
  const c2 = freshCounter({ minRepMs: 2200 });
  const a2 = arm(c2, 0);
  let t2 = a2.t;
  const spec2 = [];
  const ramp2 = (from, to, depthFrom, depthTo, ms) => {
    const n = Math.round(ms / STEP);
    for (let i = 1; i <= n; i++) {
      const k = i / n;
      spec2.push({ t: t2, opt: { angle: from + (to - from) * k, depth: depthFrom + (depthTo - depthFrom) * k } });
      t2 += STEP;
    }
  };
  ramp2(178, 92, 0, 1, 800);
  ramp2(92, 178, 1, 0, 700);
  for (let i = 0; i < 12; i++) { spec2.push({ t: t2, opt: { angle: 178, depth: 0 } }); }
  const out2 = run(c2, spec2);
  const c3 = freshCounter();
  const a3 = arm(c3, 0);
  const out3 = run(c3, repFrames(a3.t, 1).frames);
  console.log('      T7b detail: minRepMs=2200 -> reps=' + out2.reps + ' detected=' + out2.repsDetected + ' | minRepMs=400 same rep -> reps=' + out3.reps + ' duration=' + (out3.lastRep ? Math.round(out3.lastRep.durationMs) : '-'));
  check('T7b duration gate rejects a 1500 ms rep when minRepMs=2200', out2.reps === 0 && out2.repsDetected === 0);
  check('T7c the same rep counts when minRepMs=400', out3.reps === 1);
}

/* ---------- extra: 'notSide' gate, armBreak on lost pose, reset ---------- */
{
  const c = freshCounter();
  const a = arm(c, 0);
  const out = c.addFrame(a.t, makeFrame({ angle: 178, depth: 0, tilt: 80 }));
  console.log('      extra: tilt 80 -> reasons=' + JSON.stringify(out.plank.reasons) + ' bodyAngle=' + out.bodyAngle.toFixed(1));
  check('extra: steep tilt reports bodyAngle', out.plank.reasons.includes('bodyAngle'));

  const c2 = freshCounter();
  const a2 = arm(c2, 0);
  let sawBreak = false;
  for (let i = 0; i < 5; i++) {
    const o = c2.addFrame(a2.t + i * STEP, makeFrame({ angle: 178, present: false }));
    if (o.events.some((e) => e.type === 'armBreak')) sawBreak = true;
  }
  check('extra: losing the pose while armed emits armBreak', sawBreak && c2.armed === false);

  const c3 = freshCounter();
  run(c3, arm(c3, 0).frames || []);
  const a3 = arm(c3, 0);
  run(c3, repFrames(a3.t, 3).frames);
  check('extra: reps counted before reset', c3.reps === 3);
  c3.reset('test');
  check('extra: reset zeros counts and state', c3.reps === 0 && c3.repsDetected === 0 && c3.cleanReps === 0 && c3.state === 'idle' && c3.armed === false && c3.trace.length === 0);

  const out4 = c3.addFrame(0, { landmarks: null, present: true, quality: 0, fps: 30 });
  check('extra: malformed frame does not throw', out4 && out4.reps === 0 && out4.plank.reasons.includes('noPose'));
  const out5 = c3.addFrame(1, { landmarks: new Array(10).fill({ x: 0.5, y: 0.5, z: 0, visibility: 1 }), present: true, quality: 1, fps: 30 });
  check('extra: short landmark array treated as noPose', out5.plank.reasons.includes('noPose'));
}

console.log(failures === 0 ? '\nALL CHECKS PASSED' : `\n${failures} CHECK(S) FAILED`);
process.exitCode = failures === 0 ? 0 : 1;
__EOF_tests_counter_test_mjs__

mkdir -p 'tools'
cat > 'tools/build-stamp.sh' <<'__EOF_tools_build_stamp_sh__'
#!/usr/bin/env bash
# Regenerate sw.js from tools/sw.template.js with a fresh cache version + precache list.
set -euo pipefail
cd "$(dirname "$0")/.."

# Precache entries stay relative: the service worker lives next to index.html, so the browser
# resolves them against the app root wherever it is hosted (a Pages subpath or a domain root).

BUILD="$(date +%y%m%d%H%M)"
{ date -u +%FT%TZ; echo "$BUILD"; } > tools/stamp.txt

# The nosimd wasm pair is a desktop-Safari fallback, and pose_landmarker_full is an opt-in in
# Settings. Keeping all three out of the precache holds the phone's first download to ~11 MB;
# they are still cached permanently the first time they are used.
find . -type f \
  ! -path './.git/*' ! -name 'sw.js' ! -name 'serve.py' \
  ! -path './tools/*' ! -path './tests/*' ! -path './scripts/*' \
  ! -name '.DS_Store' ! -name '.*' ! -name '*.mov' ! -name 'config.json' \
  ! -name '*nosimd*' ! -name 'pose_landmarker_full.task' \
  | sed 's|^\./||' | sort > tools/precache.txt

/usr/bin/python3 - "$BUILD" <<'PY'
import pathlib, sys
build = sys.argv[1]
files = [f for f in pathlib.Path('tools/precache.txt').read_text().splitlines() if f.strip()]
items = ',\n  '.join('"%s"' % f for f in files)
tpl = pathlib.Path('tools/sw.template.js').read_text()
out = tpl.replace('__BUILD__', build).replace('__PRECACHE__', '[\n  %s\n]' % items)
pathlib.Path('sw.js').write_text(out)
print('sw.js stamped: build %s, %d files precached' % (build, len(files)))
PY
__EOF_tools_build_stamp_sh__

mkdir -p 'tools'
cat > 'tools/fetch-assets.sh' <<'__EOF_tools_fetch_assets_sh__'
#!/usr/bin/env bash
# Download every binary asset the app needs and self-host it. No build step, no CDN at runtime.
set -euo pipefail
cd "$(dirname "$0")/.."
MP="https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14"
MODEL="https://storage.googleapis.com/mediapipe-models/pose_landmarker"
UA="Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

get() { # get <url> <dest>
  if [ -s "$2" ]; then echo "ok   $2 (already there)"; return; fi
  echo ".. $2"
  curl -fL --retry 3 --retry-delay 1 -o "$2" "$1"
}

mkdir -p vendor/mediapipe/wasm models fonts icons

get "$MP/vision_bundle.mjs"                        vendor/mediapipe/vision_bundle.mjs
get "$MP/wasm/vision_wasm_internal.js"             vendor/mediapipe/wasm/vision_wasm_internal.js
get "$MP/wasm/vision_wasm_internal.wasm"           vendor/mediapipe/wasm/vision_wasm_internal.wasm
get "$MP/wasm/vision_wasm_nosimd_internal.js"      vendor/mediapipe/wasm/vision_wasm_nosimd_internal.js
get "$MP/wasm/vision_wasm_nosimd_internal.wasm"    vendor/mediapipe/wasm/vision_wasm_nosimd_internal.wasm
get "$MODEL/pose_landmarker_lite/float16/1/pose_landmarker_lite.task" models/pose_landmarker_lite.task
get "$MODEL/pose_landmarker_full/float16/1/pose_landmarker_full.task"  models/pose_landmarker_full.task

# Latin woff2 slices of the two faces, resolved through the Google Fonts CSS API with a Safari UA
# so we get woff2 rather than ttf.
slice() { # slice <family+weight url> <dest>
  local css="$1" dest="$2" u
  u=$(curl -fsS -A "$UA" "$css" | awk '/\/\* latin \*\//{f=1} f&&/url\(https/{match($0,/https:\/\/[^)]*woff2/); print substr($0,RSTART,RLENGTH); exit}')
  if [ -z "$u" ]; then echo "WARN no latin slice for $css — the app falls back to system fonts"; return; fi
  get "$u" "$dest"
}
slice "https://fonts.googleapis.com/css2?family=Barlow+Semi+Condensed:wght@500&display=swap" fonts/barlow-semi-condensed.woff2
slice "https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400&display=swap"        fonts/ibm-plex-sans.woff2

echo
echo "sizes:"
du -sh vendor models fonts | sed 's/\t/  /'
PYI=""
for p in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3 python3; do
  if command -v "$p" >/dev/null 2>&1 && "$p" -c 'import PIL' >/dev/null 2>&1; then PYI="$p"; break; fi
done
if [ -z "$PYI" ]; then
  echo "WARN Pillow missing — installing into Homebrew python"
  /opt/homebrew/bin/python3 -m pip install --quiet pillow || true
  PYI=/opt/homebrew/bin/python3
fi
"$PYI" tools/make-icons.py
ls -l icons
__EOF_tools_fetch_assets_sh__

mkdir -p 'tools'
cat > 'tools/make-icons.py' <<'__EOF_tools_make_icons_py__'
#!/usr/bin/env python3
"""Generate the app icons with Pillow: a side-view plank figure, elbow joint in brass."""
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("NEED PIL — run: /opt/homebrew/bin/python3 -m pip install pillow")

INK = (14, 26, 24)
PALE = (220, 230, 226)
FLOOR = (38, 60, 57)
BRASS = (201, 146, 47)
TRACK = (79, 163, 165)


def figure(size, inset=0.0):
    s = size
    img = Image.new("RGB", (s, s), INK)
    d = ImageDraw.Draw(img)
    pad = s * (0.10 + inset)
    w = s * 0.055

    floor_y = s * 0.80
    d.line([pad * 0.6, floor_y, s - pad * 0.6, floor_y], fill=FLOOR, width=int(s * 0.018))

    def P(xf, yf):
        x = pad + (s - 2 * pad) * xf
        y = pad + (s - 2 * pad) * yf
        return (x, y)

    shoulder = P(0.27, 0.44)
    hip = P(0.56, 0.50)
    knee = P(0.73, 0.53)
    ankle = P(0.90, 0.56)
    elbow = P(0.245, 0.63)
    wrist = P(0.34, 0.745)
    head = P(0.155, 0.385)

    d.line([hip, knee, ankle], fill=PALE, width=int(w), joint="curve")
    d.line([shoulder, hip], fill=PALE, width=int(w * 1.08), joint="curve")
    d.line([shoulder, elbow, wrist], fill=TRACK, width=int(w * 0.8), joint="curve")
    r = s * 0.085
    d.ellipse([head[0] - r, head[1] - r, head[0] + r, head[1] + r], fill=PALE)
    for pt, rad, col in ((elbow, 0.048, BRASS), (ankle, 0.030, PALE), (wrist, 0.030, TRACK)):
        rr = s * rad
        d.ellipse([pt[0] - rr, pt[1] - rr, pt[0] + rr, pt[1] + rr], fill=col)
    return img


def save(size, name, maskable=False):
    img = figure(size, inset=0.16 if maskable else 0.0)
    img.save("icons/" + name)
    print("wrote icons/%s (%dpx)" % (name, size))


save(512, "icon-512.png")
save(192, "icon-192.png")
save(512, "maskable-512.png", maskable=True)
save(192, "maskable-192.png", maskable=True)
save(180, "apple-touch-icon.png")
save(32, "favicon-32.png")
__EOF_tools_make_icons_py__

mkdir -p 'tools'
cat > 'tools/make-installer.sh' <<'__EOF_tools_make_installer_sh__'
#!/usr/bin/env bash
# Emit scripts/install-phase1.sh: one self-contained bash script that recreates the whole app from
# scratch (heredocs for text, curl for binaries). Keeps the paste-able artifact and the repo in sync.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="scripts/install-phase1.sh"
TMP="$(mktemp)"

FILES=$(find . -type f \
  ! -path './.git/*' ! -path './vendor/*' ! -path './models/*' ! -path './fonts/*' ! -path './icons/*' \
  ! -name 'sw.js' ! -name 'precache.txt' ! -name 'stamp.txt' ! -name 'base-url' ! -name 'install-phase1.sh' \
  ! -name '.DS_Store' ! -name '*.mov' ! -name '*.mp4' \
  | sed 's|^\./||' | sort)

{
  echo '#!/usr/bin/env bash'
  echo '# Pushups PWA — phase 1 installer. Self-contained: writes every source file, then downloads'
  echo '# the MediaPipe wasm + pose models + fonts and generates the icons. Re-runnable; overwrites'
  echo '# only files inside the app folder. Nothing here touches your saved sets (they live on the phone).'
  echo 'set -euo pipefail'
  echo 'ROOT="${1:-$HOME/Projects/pushups}"'
  echo 'mkdir -p "$ROOT"; cd "$ROOT"'
  echo 'umask 022'
  echo

  for f in $FILES; do
    dir=$(dirname "$f")
    if [ "$dir" = "." ]; then
      echo "mkdir -p ."
    else
      echo "mkdir -p '$dir'"
    fi
    marker="__EOF_${f//[^A-Za-z0-9]/_}__"
    echo "cat > '$f' <<'$marker'"
    cat "$f"
    echo "$marker"
    echo
  done

  echo 'chmod +x tools/*.sh scripts/*.py tools/make-icons.py 2>/dev/null || true'
  echo 'chmod +x tools/*.py 2>/dev/null || true'
  echo 'bash tools/fetch-assets.sh'
  echo 'echo "/pushups-pwa/" > tools/base-url'
  echo 'bash tools/build-stamp.sh'
  echo 'echo'
  echo 'echo "Phase 1 written to $ROOT"'
  echo 'echo "Next: ./scripts/deploy.sh -m \"phase 1: counter core\""'
} > "$TMP"

mv "$TMP" "$OUT"
chmod +x "$OUT"
lines=$(wc -l < "$OUT" | tr -d ' ')
bytes=$(wc -c < "$OUT" | tr -d ' ')
echo "scripts/install-phase1.sh: $lines lines, $bytes bytes, $(echo "$FILES" | wc -l | tr -d ' ') files embedded"
__EOF_tools_make_installer_sh__

mkdir -p 'tools'
cat > 'tools/serve.py' <<'__EOF_tools_serve_py__'
#!/usr/bin/env python3
"""Dev server: correct MIME types for wasm/mjs/woff2/task, and no caching of sw.js."""
import functools
import http.server
import socketserver
import sys

TYPES = {
    ".wasm": "application/wasm",
    ".mjs": "text/javascript",
    ".js": "text/javascript",
    ".css": "text/css",
    ".json": "application/json",
    ".task": "application/octet-stream",
    ".woff2": "font/woff2",
    ".webmanifest": "application/manifest+json",
    ".heic": "image/heic",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=".", **kw)

    def guess_type(self, path):
        for ext, mime in TYPES.items():
            if path.endswith(ext):
                return mime
        return super().guess_type(path)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("  %s\n" % (fmt % args))


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    with Server(("0.0.0.0", port), Handler) as httpd:
        print("listening on 0.0.0.0:%d" % port)
        httpd.serve_forever()


if __name__ == "__main__":
    main()
__EOF_tools_serve_py__

mkdir -p 'tools'
cat > 'tools/sw.template.js' <<'__EOF_tools_sw_template_js__'
const CACHE = 'pushups-v-__BUILD__';
const PRECACHE = __PRECACHE__;

self.addEventListener('install', (e) => {
  e.waitUntil((async () => {
    const c = await caches.open(CACHE);
    await Promise.allSettled(PRECACHE.map((u) => c.add(u)));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) if (k !== CACHE) await caches.delete(k);
    await self.clients.claim();
  })());
});

self.addEventListener('message', (e) => {
  if (e.data === 'skip') self.skipWaiting();
  if (e.data === 'reload-now') {
    self.clients.matchAll({ type: 'window' }).then((cs) => cs.forEach((c) => c.postMessage('reload')));
  }
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;

  if (req.mode === 'navigate') {
    e.respondWith((async () => {
      try {
        const net = await fetch(req);
        const c = await caches.open(CACHE);
        c.put('index.html', net.clone());
        return net;
      } catch {
        const c = await caches.open(CACHE);
        return (await c.match('index.html')) || (await c.match('./')) || Response.error();
      }
    })());
    return;
  }

  e.respondWith((async () => {
    const c = await caches.open(CACHE);
    const hit = await c.match(req, { ignoreSearch: true });
    if (hit) {
      const p = new URL(req.url).pathname;
      if (!/vendor|models|fonts/.test(p)) {
        fetch(req).then((n) => n.ok && c.put(req, n)).catch(() => {});
      }
      return hit;
    }
    try {
      const net = await fetch(req);
      if (net.ok) c.put(req, net.clone());
      return net;
    } catch {
      const stale = await c.match(req, { ignoreSearch: true });
      return stale || new Response('offline', { status: 503 });
    }
  })());
});
__EOF_tools_sw_template_js__

chmod +x tools/*.sh scripts/*.py tools/make-icons.py 2>/dev/null || true
chmod +x tools/*.py 2>/dev/null || true
bash tools/fetch-assets.sh
echo "/pushups-pwa/" > tools/base-url
bash tools/build-stamp.sh
echo
echo "Phase 1 written to $ROOT"
echo "Next: ./scripts/deploy.sh -m \"phase 1: counter core\""
