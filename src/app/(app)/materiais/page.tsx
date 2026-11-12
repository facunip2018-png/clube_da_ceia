'use client';

import { useMemo } from 'react';
import { BookOpenText } from 'lucide-react';
import { useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { Empty, Loading, Notice, PageHead, usePageTitle } from '@/components/ui';
import type { SupportMaterial } from '@/lib/types';

const GROUPS: { kind: SupportMaterial['kind']; title: string; intro: string }[] = [
  { kind: 'utensilios', title: 'Utensílios básicos', intro: 'Ferramentas e equipamentos para facilitar o preparo.' },
  { kind: 'ingredientes', title: 'Ingredientes básicos', intro: 'Conheça ingredientes, medidas e cuidados de uso.' },
  { kind: 'dicas', title: 'Dicas', intro: 'Pequenos cuidados e técnicas que ajudam no resultado.' },
  { kind: 'orientacoes', title: 'Orientações gerais', intro: 'Informações de apoio para consultar sempre que precisar.' },
];

export default function SupportMaterialsPage() {
  usePageTitle('Guias e dicas');
  const { access } = useSession();
  const { rows, loading } = useTable('support_materials', { order: [['position', 'asc'], ['title', 'asc']] });
  const grouped = useMemo(() => GROUPS.map((g) => ({ ...g, items: (rows ?? []).filter((r) => r.kind === g.kind) })), [rows]);

  if (loading) return <Loading />;
  if (!access.has_access && !access.is_admin) {
    return (
      <>
        <PageHead eyebrow="Caderno de apoio" title="Guias e dicas." sub="Conteúdos complementares para consultar durante suas preparações." />
        <Notice>Esta área faz parte do conteúdo para assinantes. Libere seu acesso para consultar os materiais.</Notice>
      </>
    );
  }

  const total = rows?.length ?? 0;
  return (
    <>
      <PageHead eyebrow="Caderno de apoio" title="Guias e dicas." sub="Utensílios, ingredientes básicos, dicas e orientações reunidos em um só lugar." />
      {total ? (
        <div className="stack">
          {grouped.map((group) => group.items.length > 0 && (
            <section className="panel stack" key={group.kind}>
              <div>
                <h2 style={{ margin: '0 0 5px' }}>{group.title}</h2>
                <p className="muted small" style={{ margin: 0 }}>{group.intro}</p>
              </div>
              {group.items.map((item) => (
                <article key={item.id} style={{ borderTop: '1px solid var(--line)', paddingTop: 14 }}>
                  <h3 style={{ margin: '0 0 8px' }}>{item.title}</h3>
                  <p style={{ whiteSpace: 'pre-wrap', lineHeight: 1.7, margin: 0 }}>{item.body}</p>
                  {item.source_page && <p className="muted small" style={{ marginBottom: 0 }}>Referência: página {item.source_page}</p>}
                </article>
              ))}
            </section>
          ))}
        </div>
      ) : <Empty icon={BookOpenText} title="Os guias estão sendo organizados">Em breve, os materiais complementares estarão disponíveis aqui.</Empty>}
    </>
  );
}
