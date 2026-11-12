'use client';

import Link from 'next/link';
import { useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { Loading, Notice, PageHead } from '@/components/ui';

export default function AdminHome() {
  const { mode } = useSession();
  const { rows: recipes } = useTable('recipes');
  const { rows: collections } = useTable('collections');
  if (!recipes || !collections) return <Loading />;

  const published = recipes.filter((recipe) => recipe.status === 'published').length;
  const structured = recipes.filter((recipe) => recipe.content_state === 'structured').length;

  return (
    <>
      <PageHead eyebrow="Área restrita" title="Biblioteca de receitas." sub="Gerencie as categorias e receitas do Clube em poucos passos." />
      {mode === 'demo' && <div style={{ marginBottom: 16 }}><Notice>Modo demonstração: as alterações ficam apenas neste navegador. Em produção, os dados são protegidos pelo Supabase.</Notice></div>}
      <div className="adminstats">
        <div className="adminstat"><span className="eyebrow">Categorias</span><strong>{collections.length}</strong></div>
        <div className="adminstat"><span className="eyebrow">Receitas cadastradas</span><strong>{recipes.length}</strong></div>
        <div className="adminstat"><span className="eyebrow">Receitas no ar</span><strong>{published}</strong><span className="sub small">{structured} com ficha estruturada</span></div>
      </div>
      <div className="gridcards" style={{ marginTop: 18 }}>
        <Link href="/admin/catalogo" className="panel cardlink">
          <div className="eyebrow">Organização</div>
          <h2 style={{ margin: '6px 0' }}>Categorias</h2>
          <p className="sub">Crie e organize Panetones, Manjares, Tortas, Rabanadas e outras categorias.</p>
          <b>Gerenciar categorias →</b>
        </Link>
        <Link href="/admin/receitas" className="panel cardlink">
          <div className="eyebrow">Conteúdo</div>
          <h2 style={{ margin: '6px 0' }}>Receitas</h2>
          <p className="sub">Cadastre receitas, escolha a categoria e complete ingredientes e modo de preparo.</p>
          <b>Gerenciar receitas →</b>
        </Link>
        <Link href="/admin/documentos" className="panel cardlink">
          <div className="eyebrow">Fontes e autorização</div>
          <h2 style={{ margin: '6px 0' }}>Materiais de origem</h2>
          <p className="sub">Consulte os materiais usados e mantenha registrada a autorização de uso.</p>
          <b>Consultar materiais →</b>
        </Link>
        <Link href="/admin/temporadas" className="panel cardlink">
          <div className="eyebrow">Assinatura</div>
          <h2 style={{ margin: '6px 0' }}>Temporada e acesso</h2>
          <p className="sub">Mantenha preço, período de acesso e configuração da assinatura.</p>
          <b>Configurar assinatura →</b>
        </Link>
      </div>
    </>
  );
}
