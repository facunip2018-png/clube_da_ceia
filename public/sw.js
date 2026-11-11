/*
 * Service worker do Clube da Ceia Perfeita.
 *
 * Guarda em cache SOMENTE arquivos estáticos (código, fontes, ícones, imagens públicas).
 * Nunca guarda respostas da API, do Supabase ou páginas com dados de usuário: o conteúdo
 * premium não fica disponível offline para quem não tem acesso.
 */
const VERSION = 'ccp-static-v1';
const OFFLINE_URL = '/offline';
const STATIC_PREFIXES = ['/_next/static/', '/icons/', '/images/'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(VERSION)
      .then((cache) => cache.addAll([OFFLINE_URL, '/icons/icon-192.png']))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== VERSION).map((key) => caches.delete(key))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return; // Supabase, pagamentos etc. passam direto
  if (url.pathname.startsWith('/api/') || url.pathname.startsWith('/auth/')) return;

  if (STATIC_PREFIXES.some((prefix) => url.pathname.startsWith(prefix))) {
    event.respondWith(
      caches.open(VERSION).then(async (cache) => {
        const cached = await cache.match(request);
        if (cached) return cached;
        const response = await fetch(request);
        if (response.ok && response.type === 'basic') cache.put(request, response.clone());
        return response;
      }),
    );
    return;
  }

  if (request.mode === 'navigate') {
    event.respondWith(fetch(request).catch(async () => (await caches.match(OFFLINE_URL)) ?? Response.error()));
  }
});
