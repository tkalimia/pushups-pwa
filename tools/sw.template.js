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
