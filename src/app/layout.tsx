import type { Metadata, Viewport } from 'next';
import { Inter, Playfair_Display } from 'next/font/google';
import type { ReactNode } from 'react';
import './globals.css';
import { Providers } from './providers';

const inter = Inter({ subsets: ['latin'], variable: '--font-inter', display: 'swap' });
const playfair = Playfair_Display({ subsets: ['latin'], variable: '--font-playfair', display: 'swap' });

const siteUrl =
  process.env.NEXT_PUBLIC_SITE_URL ??
  (process.env.VERCEL_PROJECT_PRODUCTION_URL ? `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}` : 'http://localhost:3000');

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: { default: 'Clube da Ceia Perfeita — Natal & Ano-Novo', template: '%s · Clube da Ceia Perfeita' },
  description: 'Receitas, planejamento da ceia, lista de compras, modo cozinheiro e Chef IA para o seu Natal e Ano-Novo.',
  applicationName: 'Clube da Ceia Perfeita',
  appleWebApp: { capable: true, title: 'Ceia Perfeita', statusBarStyle: 'default' },
  formatDetection: { telephone: false },
  openGraph: {
    title: 'Clube da Ceia Perfeita — Natal & Ano-Novo',
    description: 'As melhores memórias começam à mesa.',
    images: ['/images/hero-ceia.jpg'],
    locale: 'pt_BR',
    type: 'website',
  },
};

export const viewport: Viewport = {
  themeColor: '#173d2c',
  width: 'device-width',
  initialScale: 1,
  viewportFit: 'cover',
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="pt-BR" className={`${inter.variable} ${playfair.variable}`}>
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
