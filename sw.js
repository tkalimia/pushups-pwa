const CACHE = 'pushups-v-2610210918';
const PRECACHE = [
  "css/app.css",
  "css/progress.css",
  "css/today.css",
  "fonts/barlow-semi-condensed.woff2",
  "fonts/ibm-plex-sans.woff2",
  "icons/apple-touch-icon.png",
  "icons/favicon-32.png",
  "icons/icon-192.png",
  "icons/icon-512.png",
  "icons/maskable-192.png",
  "icons/maskable-512.png",
  "index.html",
  "js/camera.js",
  "js/counter.js",
  "js/db.js",
  "js/feedback.js",
  "js/goals.js",
  "js/main.js",
  "js/one-euro.js",
  "js/pose.js",
  "js/settings.js",
  "js/stats.js",
  "js/upgrade.js",
  "js/util.js",
  "js/views/badges.js",
  "js/views/debug.js",
  "js/views/progress.js",
  "js/views/settings.js",
  "js/views/today.js",
  "js/views/train.js",
  "manifest.webmanifest",
  "models/pose_landmarker_lite.task",
  "README.md",
  "vendor/mediapipe/vision_bundle.mjs",
  "vendor/mediapipe/wasm/vision_wasm_internal.js",
  "vendor/mediapipe/wasm/vision_wasm_internal.wasm"
];

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
