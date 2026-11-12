'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import type { ReactNode } from 'react';
import { AdminOnly } from '@/components/gates';
import { usePageTitle } from '@/components/ui';

const TABS = [
  { href: '/admin', label: 'Visão geral' },
  { href: '/admin/receitas', label: 'Receitas' },
  { href: '/admin/catalogo', label: 'Categorias' },
  { href: '/admin/documentos', label: 'Materiais e direitos' },
  { href: '/admin/apoio', label: 'Materiais de apoio' },
  { href: '/admin/temporadas', label: 'Temporada' },
  { href: '/admin/acessos', label: 'Pessoas e pagamentos' },
  { href: '/admin/auditoria', label: 'Auditoria' },
];

export default function AdminLayout({ children }: { children: ReactNode }) {
  usePageTitle('Painel administrativo');
  const pathname = usePathname();
  return (
    <AdminOnly>
      <nav className="adminnav noprint" aria-label="Painel administrativo">
        {TABS.map((tab) => {
          const active = tab.href === '/admin' ? pathname === '/admin' : pathname.startsWith(tab.href);
          return <Link key={tab.href} href={tab.href} className={`filter ${active ? 'active' : ''}`} aria-current={active ? 'page' : undefined}>{tab.label}</Link>;
        })}
      </nav>
      {children}
    </AdminOnly>
  );
}
