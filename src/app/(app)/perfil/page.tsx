'use client';

import Link from 'next/link';
import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { Heart, LogOut, Settings, ShieldCheck, ShoppingBasket, Smartphone, Timer, Trophy } from 'lucide-react';
import { useCatalog, useFavoriteIds, useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { RecipeCard } from '@/components/cards';
import { Guard } from '@/components/gates';
import { useToast } from '@/components/toast';
import { Empty, Notice, PageHead, usePageTitle } from '@/components/ui';
import { formatDate } from '@/lib/format';

interface InstallPrompt extends Event {
  prompt: () => Promise<void>;
}

function Profile() {
  const { user, access, store, signOut, refresh, mode } = useSession();
  const { toast, fail } = useToast();
  const { rows: profiles } = useTable('profiles', user ? { eq: { id: user.id } } : null);
  const { recipes, collections } = useCatalog();
  const favorites = useFavoriteIds();
  const [name, setName] = useState(user?.name ?? '');
  const [install, setInstall] = useState<InstallPrompt | null>(null);
  const favoriteRecipes = useMemo(() => recipes.filter((r) => favorites.has(r.id)), [recipes, favorites]);

  useEffect(() => {
    if (profiles?.[0]) setName(profiles[0].full_name);
  }, [profiles]);
  useEffect(() => {
    const onPrompt = (event: Event) => {
      event.preventDefault();
      setInstall(event as InstallPrompt);
    };
    window.addEventListener('beforeinstallprompt', onPrompt);
    return () => window.removeEventListener('beforeinstallprompt', onPrompt);
  }, []);

  async function save(event: FormEvent) {
    event.preventDefault();
    if (!user) return;
    try {
      await store.update('profiles', { id: user.id }, { full_name: name.trim() });
      await refresh();
      toast('Perfil atualizado');
    } catch (error) {
      fail(error);
    }
  }

  return (
    <>
      <div className="twocol">
        <section className="panel">
          <div className="spread">
            <div>
              <h2>{user?.name}</h2>
              <p className="sub">{access.is_admin ? 'Administração do Clube' : access.has_access ? 'Membro da temporada' : 'Conta do Clube'}</p>
            </div>
            {access.is_admin && <span className="pill dark"><ShieldCheck /> ADMIN</span>}
          </div>
          <form className="stack" style={{ marginTop: 16 }} onSubmit={save}>
            <div className="group"><label htmlFor="p-name">Nome</label><input id="p-name" className="field" value={name} onChange={(e) => setName(e.target.value)} maxLength={80} required /></div>
            <div className="group"><label htmlFor="p-email">E-mail</label><input id="p-email" className="field" value={user?.email ?? ''} disabled /></div>
            <div className="row">
              <button type="submit" className="btn dark" disabled={!name.trim() || name.trim() === (profiles?.[0]?.full_name ?? user?.name)}>Salvar</button>
              <button type="button" className="btn outline" onClick={() => signOut()}><LogOut /> Sair</button>
            </div>
          </form>
        </section>

        <section className="panel">
          <div className="eyebrow">Sua temporada</div>
          <h2 style={{ margin: '6px 0' }}>{access.season_name ?? 'Natal & Ano-Novo'}</h2>
          {access.is_admin && !access.season_name ? (
            <p className="sub">Como administradora, você tem acesso a todo o conteúdo, inclusive rascunhos.</p>
          ) : access.has_access ? (
            <p className="sub">Seu acesso está liberado{access.access_until ? ` até ${formatDate(access.access_until)}` : ''}. Bom proveito!</p>
          ) : (
            <>
              <p className="sub">Você ainda não tem o acesso desta temporada.</p>
              <Link href="/acesso" className="btn primary" style={{ marginTop: 14 }}>Liberar meu acesso</Link>
            </>
          )}
          <hr className="divider" />
          <div className="row">
            <Link href="/lista" className="btn outline sm"><ShoppingBasket /> Lista de compras</Link>
            <Link href="/desafios" className="btn outline sm"><Trophy /> Desafios</Link>
            <Link href="/temporizadores" className="btn outline sm"><Timer /> Temporizadores</Link>
            {access.is_admin && <Link href="/admin" className="btn outline sm"><Settings /> Painel admin</Link>}
          </div>
        </section>
      </div>

      <div className="sectionhead">
        <div><div className="eyebrow">Sua seleção</div><h2>Receitas favoritas</h2></div>
      </div>
      {favoriteRecipes.length ? (
        <div className="recipegrid">
          {favoriteRecipes.map((recipe) => <RecipeCard key={recipe.id} recipe={recipe} collection={collections.find((c) => c.id === recipe.collection_id)} favorite />)}
        </div>
      ) : (
        <Empty icon={Heart} title="Nenhuma favorita ainda" action={<Link href="/colecoes" className="btn dark">Explorar receitas</Link>}>
          Toque no coração de uma receita para guardá-la aqui.
        </Empty>
      )}

      <div className="sectionhead">
        <div><div className="eyebrow">No seu celular</div><h2>Instale o app</h2></div>
      </div>
      <div className="panel">
        <div className="row" style={{ alignItems: 'flex-start' }}>
          <div className="stat-icon"><Smartphone /></div>
          <div className="grow">
            <p className="sub">
              <b>Android (Chrome):</b> menu ⋮ → “Instalar app”. <b>iPhone (Safari):</b> botão Compartilhar → “Adicionar à Tela de Início”.
              O Clube abre em tela cheia, como um aplicativo.
            </p>
            {install && <button type="button" className="btn dark sm" style={{ marginTop: 12 }} onClick={() => install.prompt().then(() => setInstall(null))}>Instalar agora</button>}
          </div>
        </div>
      </div>
      {mode === 'demo' && (
        <div style={{ marginTop: 16 }}>
          <Notice>Você está no <b>modo demonstração</b>: os dados ficam apenas neste navegador. Com o Supabase conectado, cada pessoa entra com e-mail e senha e tem seus dados guardados na conta.</Notice>
        </div>
      )}
    </>
  );
}

export default function ProfilePage() {
  usePageTitle('Meu perfil');
  return (
    <>
      <PageHead eyebrow="Seu espaço no Clube" title="Meu perfil." sub="Seus dados, seu acesso da temporada e suas receitas favoritas." />
      <Guard what="O seu perfil">
        <Profile />
      </Guard>
    </>
  );
}
