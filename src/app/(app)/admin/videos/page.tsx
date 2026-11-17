'use client';

import { useState, type FormEvent } from 'react';
import { Archive, Check, Clapperboard, Pencil, Plus, Save, Video as VideoIcon, X } from 'lucide-react';
import { useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { useAdminAction } from '@/components/admin';
import { Empty, Loading, PageHead } from '@/components/ui';
import { VideoPlayer } from '@/components/video-player';
import type { Video } from '@/lib/types';

const slugify = (value: string) => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const safeUrl = (value: string) => {
  if (!value.trim()) return null;
  try { const parsed = new URL(value.trim()); return parsed.protocol === 'https:' ? parsed.toString() : null; }
  catch { return null; }
};
const blank = {
  title: '', description: '', hls_url: '', mp4_url: '', thumbnail_url: '',
  duration_seconds: '', collection_id: '', recipe_id: '', status: 'draft' as Video['status'],
};

export default function AdminVideosPage() {
  const { store, user } = useSession();
  const act = useAdminAction();
  const { rows: videos, loading, mutate } = useTable('videos', { order: [['position', 'asc'], ['created_at', 'desc']] });
  const { rows: collections } = useTable('collections', { order: [['position', 'asc']] });
  const { rows: recipes } = useTable('recipes', { order: [['title', 'asc']] });
  const [editing, setEditing] = useState<string | null>(null);
  const [form, setForm] = useState(blank);
  const [saving, setSaving] = useState(false);

  function startNew() { setEditing(null); setForm(blank); }
  function edit(video: Video) {
    setEditing(video.id);
    setForm({
      title: video.title, description: video.description ?? '', hls_url: video.hls_url ?? '',
      mp4_url: video.mp4_url ?? '', thumbnail_url: video.thumbnail_url ?? '',
      duration_seconds: video.duration_seconds ? String(video.duration_seconds) : '',
      collection_id: video.collection_id ?? '', recipe_id: video.recipe_id ?? '', status: video.status,
    });
  }

  async function save(event: FormEvent) {
    event.preventDefault();
    const title = form.title.trim();
    const hls = safeUrl(form.hls_url);
    const mp4 = safeUrl(form.mp4_url);
    const thumbnail = safeUrl(form.thumbnail_url);
    if (title.length < 2) return;
    if (!hls && !mp4) { window.alert('Informe uma URL HLS ou MP4 válida, começando com https://.'); return; }
    if (form.hls_url.trim() && !hls) { window.alert('A URL HLS precisa ser um endereço HTTPS válido.'); return; }
    if (form.mp4_url.trim() && !mp4) { window.alert('A URL MP4 precisa ser um endereço HTTPS válido.'); return; }
    if (form.thumbnail_url.trim() && !thumbnail) { window.alert('A imagem de capa precisa ser um endereço HTTPS válido.'); return; }

    const baseSlug = slugify(title) || 'video';
    const used = new Set((videos ?? []).filter((item) => item.id !== editing).map((item) => item.slug));
    let slug = editing ? (videos ?? []).find((item) => item.id === editing)?.slug ?? baseSlug : baseSlug;
    let suffix = 2;
    while (!editing && used.has(slug)) slug = baseSlug + '-' + suffix++;
    const duration = form.duration_seconds.trim() ? Math.round(Number(form.duration_seconds)) : null;
    if (duration !== null && (!Number.isFinite(duration) || duration < 1)) { window.alert('Informe a duração em segundos usando um número maior que zero.'); return; }

    const patch = {
      title, slug, description: form.description.trim() || null, hls_url: hls, mp4_url: mp4,
      thumbnail_url: thumbnail, duration_seconds: duration,
      collection_id: form.collection_id || null, recipe_id: form.recipe_id || null, status: form.status,
    };
    setSaving(true);
    const ok = editing
      ? await act(() => store.update('videos', { id: editing }, patch), { tables: ['videos', 'admin_audit_logs'], success: 'Vídeo atualizado.' })
      : await act(async () => {
          const [created] = await store.insert('videos', {
            ...patch, position: (videos ?? []).reduce((max, item) => Math.max(max, item.position), 0) + 1,
            created_by: user?.id ?? null,
          });
          if (created) setEditing(created.id);
          return created;
        }, { tables: ['videos', 'admin_audit_logs'], success: 'Vídeo cadastrado.' });
    setSaving(false);
    if (ok) await mutate();
  }

  async function archive(video: Video) {
    const ok = await act(
      () => store.update('videos', { id: video.id }, { status: 'archived' }),
      { tables: ['videos', 'admin_audit_logs'], success: 'Vídeo arquivado. Ele não aparece mais para os assinantes.' },
    );
    if (ok) { if (editing === video.id) startNew(); await mutate(); }
  }

  if (loading || !videos || !collections || !recipes) return <Loading />;
  const selected = videos.find((video) => video.id === editing) ?? null;
  const published = videos.filter((video) => video.status === 'published').length;

  return (
    <>
      <PageHead eyebrow="Conteúdo em vídeo" title="Biblioteca de vídeos." sub="Cadastre os links do Gumlet, teste o player e escolha onde cada vídeo será exibido.">
        <button type="button" className="btn primary" onClick={startNew}><Plus /> Novo vídeo</button>
      </PageHead>
      <div className="admin-video-banner">
        <div className="admin-video-banner-icon"><Clapperboard aria-hidden /></div>
        <div>
          <div className="eyebrow">Gumlet · HLS + MP4</div>
          <h2>Seus vídeos, organizados em um só lugar.</h2>
          <p>Cadastre o endereço de streaming HLS e, se tiver, uma versão MP4 para compatibilidade adicional. Salve como rascunho, confira o player e publique quando estiver pronto.</p>
        </div>
      </div>
      <div className="adminstats" style={{ marginBottom: 18 }}>
        <div className="adminstat"><span className="eyebrow">Vídeos cadastrados</span><strong>{videos.filter((video) => video.status !== 'archived').length}</strong></div>
        <div className="adminstat"><span className="eyebrow">Publicados</span><strong>{published}</strong></div>
        <div className="adminstat"><span className="eyebrow">Rascunhos</span><strong>{videos.filter((video) => video.status === 'draft').length}</strong></div>
      </div>
      <div className="twocol" style={{ alignItems: 'start' }}>
        <form className="panel stack" onSubmit={save}>
          <div className="panelhead">
            <div><div className="eyebrow">{editing ? 'Editar cadastro' : 'Novo cadastro'}</div><h2 style={{ marginTop: 5 }}>{editing ? 'Editar vídeo' : 'Adicionar vídeo'}</h2></div>
            {editing && <button type="button" className="iconbtn" onClick={startNew} aria-label="Cancelar edição"><X /></button>}
          </div>
          <div className="group">
            <label htmlFor="video-title">Título do vídeo</label>
            <input id="video-title" className="field" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} placeholder="Ex.: Como preparar a massa do panetone" required minLength={2} maxLength={160} />
          </div>
          <div className="group">
            <label htmlFor="video-description">Descrição</label>
            <textarea id="video-description" className="textarea" value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} placeholder="Explique o que o assinante vai aprender." />
          </div>
          <div className="group">
            <label htmlFor="video-hls">URL HLS do Gumlet (.m3u8)</label>
            <input id="video-hls" className="field" type="url" inputMode="url" value={form.hls_url} onChange={(e) => setForm({ ...form, hls_url: e.target.value })} placeholder="https://video.gumlet.io/.../main.m3u8" />
            <span className="hint">Formato recomendado para streaming adaptativo.</span>
          </div>
          <div className="group">
            <label htmlFor="video-mp4">URL MP4 (opcional)</label>
            <input id="video-mp4" className="field" type="url" inputMode="url" value={form.mp4_url} onChange={(e) => setForm({ ...form, mp4_url: e.target.value })} placeholder="https://video.gumlet.io/.../main.mp4" />
            <span className="hint">Cadastre a URL MP4 se o Gumlet disponibilizar essa versão para o vídeo.</span>
          </div>
          <div className="group">
            <label htmlFor="video-thumbnail">Imagem de capa (URL HTTPS, opcional)</label>
            <input id="video-thumbnail" className="field" type="url" inputMode="url" value={form.thumbnail_url} onChange={(e) => setForm({ ...form, thumbnail_url: e.target.value })} placeholder="https://..." />
          </div>
          <div className="formgrid">
            <div className="group">
              <label htmlFor="video-duration">Duração em segundos</label>
              <input id="video-duration" className="field" type="number" min="1" step="1" value={form.duration_seconds} onChange={(e) => setForm({ ...form, duration_seconds: e.target.value })} placeholder="Ex.: 420" />
            </div>
            <div className="group">
              <label htmlFor="video-status">Publicação</label>
              <select id="video-status" className="select" value={form.status} onChange={(e) => setForm({ ...form, status: e.target.value as Video['status'] })}>
                <option value="draft">Rascunho</option><option value="published">Publicado para assinantes</option><option value="archived">Arquivado</option>
              </select>
            </div>
          </div>
          <div className="group">
            <label htmlFor="video-collection">Exibir na coleção (opcional)</label>
            <select id="video-collection" className="select" value={form.collection_id} onChange={(e) => setForm({ ...form, collection_id: e.target.value })}>
              <option value="">Sem coleção específica</option>
              {collections.map((collection) => <option key={collection.id} value={collection.id}>{collection.name}</option>)}
            </select>
          </div>
          <div className="group">
            <label htmlFor="video-recipe">Associar a uma receita (opcional)</label>
            <select id="video-recipe" className="select" value={form.recipe_id} onChange={(e) => setForm({ ...form, recipe_id: e.target.value })}>
              <option value="">Sem receita específica</option>
              {recipes.filter((recipe) => recipe.kind === 'recipe').map((recipe) => <option key={recipe.id} value={recipe.id}>{recipe.title}</option>)}
            </select>
          </div>
          <div className="row">
            <button type="submit" className="btn dark" disabled={saving}><Save /> {saving ? 'Salvando…' : editing ? 'Salvar alterações' : 'Cadastrar vídeo'}</button>
            {editing && <button type="button" className="btn outline" onClick={startNew}>Cancelar</button>}
          </div>
          <p className="muted small">Vídeos publicados ficam disponíveis somente para contas autenticadas com acesso ativo à temporada. Rascunhos e arquivados não aparecem para assinantes.</p>
        </form>
        <div className="stack">
          <section className="panel">
            <div className="panelhead"><div><div className="eyebrow">Pré-visualização</div><h2 style={{ marginTop: 5 }}>Teste do player</h2></div><span className="pill gold">{selected?.status === 'published' ? 'Publicado' : 'Prévia admin'}</span></div>
            {form.hls_url || form.mp4_url
              ? <VideoPlayer hlsUrl={safeUrl(form.hls_url)} mp4Url={safeUrl(form.mp4_url)} poster={safeUrl(form.thumbnail_url)} title={form.title || 'Prévia do vídeo'} />
              : <Empty icon={VideoIcon} title="Nenhum link informado">Cole a URL HLS ou MP4 para visualizar o vídeo aqui.</Empty>}
          </section>
          <section className="panel">
            <div className="panelhead"><div><div className="eyebrow">Sua biblioteca</div><h2 style={{ marginTop: 5 }}>Vídeos cadastrados</h2></div><span className="pill">{videos.length}</span></div>
            <div className="video-admin-list">
              {videos.map((video) => (
                <article key={video.id} className="video-admin-row">
                  <div className="video-admin-thumb"><VideoIcon aria-hidden /></div>
                  <div className="grow">
                    <strong>{video.title}</strong>
                    <div className="row">
                      <span className={video.status === 'published' ? 'pill ok' : video.status === 'draft' ? 'pill warn' : 'pill muted'}>{video.status === 'published' ? 'Publicado' : video.status === 'draft' ? 'Rascunho' : 'Arquivado'}</span>
                      {video.hls_url && <span className="pill">HLS</span>}{video.mp4_url && <span className="pill">MP4</span>}
                    </div>
                  </div>
                  <div className="row">
                    <button type="button" className="iconbtn" onClick={() => edit(video)} aria-label={'Editar ' + video.title}><Pencil /></button>
                    {video.status !== 'archived' && <button type="button" className="iconbtn" onClick={() => void archive(video)} aria-label={'Arquivar ' + video.title}><Archive /></button>}
                    {video.status === 'published' && <Check color="var(--green)" aria-label="Publicado" />}
                  </div>
                </article>
              ))}
              {!videos.length && <Empty icon={Clapperboard} title="Sua biblioteca está vazia">Cadastre seu primeiro vídeo usando o formulário ao lado.</Empty>}
            </div>
          </section>
        </div>
      </div>
    </>
  );
}
