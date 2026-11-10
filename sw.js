/* Service worker WMS: agar bisa dipasang sebagai aplikasi dan halaman dasar terbuka cepat.
   Data (Supabase) TIDAK pernah disimpan di cache, selalu diambil langsung dari internet. */
const CACHE = 'wms-shell-v1';
const SHELL = ['./', './index.html', './manifest.webmanifest', './icon-192.png', './icon-512.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).catch(() => { })); self.skipWaiting(); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', e => {
  const r = e.request, u = new URL(r.url);
  if (r.method !== 'GET' || u.origin !== location.origin) return;           // supabase, CDN, font: langsung ke jaringan
  if (u.pathname.endsWith('config.js')) return;                              // konfigurasi selalu segar
  e.respondWith(fetch(r).then(res => { if (res.ok) { const cp = res.clone(); caches.open(CACHE).then(c => c.put(r, cp)); } return res; }).catch(() => caches.match(r).then(m => m || caches.match('./index.html'))));
});
