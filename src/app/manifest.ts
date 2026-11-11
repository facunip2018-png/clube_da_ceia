import type { MetadataRoute } from 'next';

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'Clube da Ceia Perfeita — Natal & Ano-Novo',
    short_name: 'Ceia Perfeita',
    description: 'Receitas, planejamento da ceia, lista de compras, modo cozinheiro e Chef IA.',
    lang: 'pt-BR',
    start_url: '/',
    scope: '/',
    display: 'standalone',
    orientation: 'portrait',
    background_color: '#173d2c',
    theme_color: '#173d2c',
    categories: ['food', 'lifestyle'],
    icons: [
      { src: '/icons/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
      { src: '/icons/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
      { src: '/icons/maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
    ],
    shortcuts: [
      { name: 'Minha ceia', url: '/minha-ceia' },
      { name: 'Lista de compras', url: '/lista' },
      { name: 'Temporizadores', url: '/temporizadores' },
    ],
  };
}
