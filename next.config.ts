import type { NextConfig } from 'next'

/**
 * Cabeçalhos de segurança.
 * Em produção o app NÃO pode ser embutido em iframes de outros sites (proteção contra clickjacking).
 * Para pré-visualizações que rodam dentro de um iframe (ex.: ambientes de preview), defina
 * ALLOW_IFRAME_EMBED=true no momento do build.
 */
const allowEmbed = process.env.ALLOW_IFRAME_EMBED === 'true'

const securityHeaders = [
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=(), browsing-topics=()' },
  ...(allowEmbed ? [] : [{ key: 'X-Frame-Options', value: 'SAMEORIGIN' }]),
]

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // Permite gerar um segundo build em outra pasta (usado nas verificações de segurança do modo produção).
  distDir: process.env.NEXT_DIST_DIR || '.next',
  poweredByHeader: false,
  // Origens extras autorizadas a falar com o servidor de desenvolvimento (túneis/previews).
  allowedDevOrigins: (process.env.ALLOWED_DEV_ORIGINS ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean),
  async headers() {
    return [
      { source: '/(.*)', headers: securityHeaders },
      {
        source: '/sw.js',
        headers: [
          { key: 'Content-Type', value: 'application/javascript; charset=utf-8' },
          { key: 'Cache-Control', value: 'no-cache, no-store, must-revalidate' },
          { key: 'Content-Security-Policy', value: "default-src 'self'; script-src 'self'" },
        ],
      },
    ]
  },
}

export default nextConfig
