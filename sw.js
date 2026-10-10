// Page loads and config.js try the network first, so the home-screen app gets the latest deploy;
// the last good copy is kept for offline use. The pinned supabase-js build and fonts never change,
// so they're served from cache once fetched. Together these let the app open with no signal.
const PAGES = 'tee-sheet-pages';
const ASSETS = 'tee-sheet-assets-v1';
const CACHE_FIRST_HOSTS = ['cdn.jsdelivr.net', 'fonts.googleapis.com', 'fonts.gstatic.com'];

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', ev => ev.waitUntil(self.clients.claim()));

function networkFirst(request, cacheName) {
	return fetch(request, {cache: 'no-store'})
		.then(res => {
			if (res.ok) {
				const copy = res.clone();
				caches.open(cacheName).then(cache => cache.put(request, copy));
			}
			return res;
		})
		.catch(() => caches.match(request, {ignoreSearch: true}));
}

function cacheFirst(request) {
	return caches.match(request).then(hit => hit || fetch(request).then(res => {
		if (res.ok || res.type === 'opaque') {
			const copy = res.clone();
			caches.open(ASSETS).then(cache => cache.put(request, copy));
		}
		return res;
	}));
}

self.addEventListener('fetch', ev => {
	const url = new URL(ev.request.url);
	if (ev.request.method !== 'GET') return;
	if (ev.request.mode === 'navigate') {
		ev.respondWith(networkFirst(ev.request, PAGES));
	} else if (url.origin === location.origin && url.pathname.endsWith('/config.js')) {
		ev.respondWith(networkFirst(ev.request, ASSETS));
	} else if (CACHE_FIRST_HOSTS.includes(url.hostname)) {
		ev.respondWith(cacheFirst(ev.request));
	}
});
