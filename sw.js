// Page loads always try the network first, so the home-screen app gets the latest deploy.
// The last good copy is kept for offline use.
const CACHE = 'tee-sheet-pages';

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', ev => ev.waitUntil(self.clients.claim()));

self.addEventListener('fetch', ev => {
	if (ev.request.mode !== 'navigate') return;
	ev.respondWith(
		fetch(ev.request, {cache: 'no-store'})
			.then(res => {
				const copy = res.clone();
				caches.open(CACHE).then(cache => cache.put(ev.request, copy));
				return res;
			})
			.catch(() => caches.match(ev.request, {ignoreSearch: true})),
	);
});
