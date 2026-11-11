'use client';

import Link from 'next/link';
import { useMemo, useState, type FormEvent } from 'react';
import { Check, Clock, ListChecks, Pencil, Plus, RotateCcw, Share2, ShoppingBasket, Trash2, X } from 'lucide-react';
import { invalidate, useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { ensureDefaultList, removeRecipeFromShoppingList } from '@/data/actions';
import { Guard } from '@/components/gates';
import { useToast } from '@/components/toast';
import { useDialog } from '@/components/dialogs';
import { Empty, Loading, PageHead, Sheet, usePageTitle } from '@/components/ui';
import { CATEGORY_LABELS, CATEGORY_ORDER, groupByCategory, itemQuantityLabel, parseManualItem, shareText } from '@/lib/shopping';
import type { ShoppingItem } from '@/lib/types';

function EditItem({ item, onClose }: { item: ShoppingItem; onClose: () => void }) {
  const { store } = useSession();
  const { fail } = useToast();
  const [name, setName] = useState(item.name);
  const [quantity, setQuantity] = useState(item.quantity != null ? String(item.quantity).replace('.', ',') : '');
  const [unit, setUnit] = useState(item.unit ?? '');
  const [category, setCategory] = useState(item.category);
  const [note, setNote] = useState(item.note ?? '');

  async function save(event: FormEvent) {
    event.preventDefault();
    const value = quantity.trim() ? Number(quantity.replace(',', '.')) : null;
    if (value != null && (!Number.isFinite(value) || value < 0)) return fail(new Error('Informe uma quantidade válida.'));
    try {
      await store.update('shopping_items', { id: item.id }, {
        name: name.trim() || item.name,
        quantity: value,
        unit: value == null ? null : unit.trim() || null,
        quantity_text: value == null ? item.quantity_text : null,
        category,
        note: note.trim() || null,
        quantity_edited: item.quantity_edited || value !== item.quantity,
      });
      await invalidate('shopping_items');
      onClose();
    } catch (error) {
      fail(error);
    }
  }

  return (
    <Sheet title="Editar item" onClose={onClose}>
      <form className="formgrid" onSubmit={save}>
        <div className="group full"><label htmlFor="i-name">Item</label><input id="i-name" className="field" value={name} onChange={(e) => setName(e.target.value)} maxLength={120} required /></div>
        <div className="group"><label htmlFor="i-qty">Quantidade</label><input id="i-qty" className="field" inputMode="decimal" value={quantity} onChange={(e) => setQuantity(e.target.value)} placeholder={item.quantity_text ?? 'Ex.: 500'} /></div>
        <div className="group"><label htmlFor="i-unit">Unidade</label><input id="i-unit" className="field" value={unit} onChange={(e) => setUnit(e.target.value)} placeholder="g, ml, pacote…" maxLength={30} /></div>
        <div className="group full">
          <label htmlFor="i-cat">Categoria</label>
          <select id="i-cat" className="select" value={category} onChange={(e) => setCategory(e.target.value)}>
            {CATEGORY_ORDER.map((c) => <option key={c} value={c}>{CATEGORY_LABELS[c]}</option>)}
          </select>
        </div>
        <div className="group full"><label htmlFor="i-note">Observação</label><input id="i-note" className="field" value={note} onChange={(e) => setNote(e.target.value)} placeholder="Marca, onde comprar…" maxLength={160} /></div>
        {item.sources.length > 0 && (
          <p className="muted small full">
            Vem de: {item.sources.map((s) => `${s.recipe_title}${s.quantity != null ? ` (${itemQuantityLabel({ quantity: s.quantity, unit: s.unit, quantity_text: null })})` : ''}`).join(' · ')}
          </p>
        )}
        <div className="group full"><button type="submit" className="btn dark">Salvar</button></div>
      </form>
    </Sheet>
  );
}

function ShoppingList() {
  const { store } = useSession();
  const { toast, fail } = useToast();
  const { confirm } = useDialog();
  const { rows: lists, loading: loadingLists } = useTable('shopping_lists', { order: [['created_at', 'asc']], limit: 1 });
  const list = lists?.[0];
  const { rows: items, loading: loadingItems } = useTable('shopping_items', list ? { eq: { list_id: list.id }, order: [['position', 'asc']] } : null);
  const [name, setName] = useState('');
  const [quantity, setQuantity] = useState('');
  const [editing, setEditing] = useState<ShoppingItem | null>(null);

  const all = useMemo(() => items ?? [], [items]);
  const groups = useMemo(() => groupByCategory(all), [all]);
  const done = all.filter((i) => i.is_checked).length;
  const sources = useMemo(() => {
    const map = new Map<string, string>();
    all.forEach((i) => i.sources.forEach((s) => map.set(s.recipe_id, s.recipe_title)));
    return [...map.entries()];
  }, [all]);

  const run = async (fn: () => Promise<unknown>) => {
    try {
      await fn();
      await invalidate('shopping_items', 'shopping_lists', 'refresh_my_challenges');
    } catch (error) {
      fail(error);
    }
  };

  async function add(event: FormEvent) {
    event.preventDefault();
    const parsed = parseManualItem(`${quantity.trim()} ${name.trim()}`.trim());
    if (!parsed || !name.trim()) return;
    setName('');
    setQuantity('');
    await run(async () => {
      const target = list ?? (await ensureDefaultList(store));
      // "500 g" sem número reconhecível vira observação textual, sem inventar quantidade
      const textual = parsed.quantity == null && quantity.trim() ? quantity.trim() : null;
      await store.insert('shopping_items', {
        list_id: target.id, name: textual ? name.trim().charAt(0).toUpperCase() + name.trim().slice(1) : parsed.name, quantity: parsed.quantity, unit: parsed.unit,
        quantity_text: textual, is_manual: true, category: 'outros', position: all.length + 1,
      });
    });
    toast('Item adicionado');
  }

  async function share() {
    const text = shareText(all, list?.title ?? 'Minha lista');
    try {
      if (navigator.share) await navigator.share({ title: 'Lista de compras', text });
      else {
        await navigator.clipboard.writeText(text);
        toast('Lista copiada para a área de transferência');
      }
    } catch (error) {
      if ((error as Error).name !== 'AbortError') {
        try {
          await navigator.clipboard.writeText(text);
          toast('Lista copiada para a área de transferência');
        } catch {
          fail(new Error('Não foi possível compartilhar neste aparelho.'));
        }
      }
    }
  }

  if (loadingLists || (list && loadingItems)) return <Loading />;

  return (
    <>
      <div className="stats">
        <div className="stat"><div className="stat-icon"><ListChecks /></div><div><b>{all.length}</b><small>itens na lista</small></div></div>
        <div className="stat"><div className="stat-icon"><Check /></div><div><b>{done}</b><small>comprados</small></div></div>
        <div className="stat"><div className="stat-icon"><Clock /></div><div><b>{all.length - done}</b><small>pendentes</small></div></div>
      </div>

      <div className="twocol" style={{ marginTop: 16 }}>
        <section className="panel">
          <div className="panelhead">
            <div><div className="eyebrow">Sua lista</div><h2 style={{ marginTop: 6 }}>Itens para comprar</h2></div>
            <div className="row">
              {done > 0 && <button type="button" className="textbtn" onClick={() => run(async () => { for (const i of all.filter((x) => x.is_checked)) await store.update('shopping_items', { id: i.id }, { is_checked: false, checked_at: null }); })}><RotateCcw /> Desmarcar</button>}
              {all.length > 0 && <button type="button" className="textbtn" onClick={share}><Share2 /> Compartilhar</button>}
            </div>
          </div>

          {sources.length > 0 && (
            <div className="chips" style={{ marginBottom: 6 }}>
              {sources.map(([id, title]) => (
                <span key={id} className="pill gold" style={{ padding: '6px 6px 6px 11px', fontSize: 12.5 }}>
                  {title}
                  <button type="button" className="iconbtn plain" style={{ width: 22, height: 22 }} aria-label={`Remover da lista os ingredientes de ${title}`}
                    onClick={() => run(() => removeRecipeFromShoppingList(store, id))}><X size={13} /></button>
                </span>
              ))}
            </div>
          )}

          {all.length ? (
            <div className="shoppinglist">
              {groups.map((group) => (
                <div key={group.category} className="shoppinglist">
                  <div className="categorylabel">{group.label}</div>
                  {group.items.map((item) => (
                    <div key={item.id} className={`shopitem ${item.is_checked ? 'done' : ''}`}>
                      <input type="checkbox" className="check" checked={item.is_checked} aria-label={`${item.name} comprado`}
                        onChange={() => run(() => store.update('shopping_items', { id: item.id }, { is_checked: !item.is_checked, checked_at: item.is_checked ? null : new Date().toISOString() }))} />
                      <span className="grow">
                        <span className="t">{item.name}</span>
                        {(item.note || item.sources.length > 0) && (
                          <small>{[item.note, item.sources.length ? item.sources.map((s) => s.recipe_title).join(', ') : null].filter(Boolean).join(' · ')}</small>
                        )}
                      </span>
                      <span className={`qty ${item.quantity == null ? 'textual' : ''}`}>{itemQuantityLabel(item)}</span>
                      <button type="button" className="iconbtn plain" onClick={() => setEditing(item)} aria-label={`Editar ${item.name}`}><Pencil /></button>
                      <button type="button" className="iconbtn plain" onClick={() => run(() => store.remove('shopping_items', { id: item.id }))} aria-label={`Remover ${item.name}`}><Trash2 /></button>
                    </div>
                  ))}
                </div>
              ))}
              {done > 0 && (
                <button type="button" className="btn outline sm" style={{ justifySelf: 'start', marginTop: 8 }}
                  onClick={async () => (await confirm({ title: 'Limpar itens comprados?', message: 'Os itens já marcados como comprados saem da lista.', confirmLabel: 'Limpar' })) && run(async () => { for (const i of all.filter((x) => x.is_checked)) await store.remove('shopping_items', { id: i.id }); })}>
                  <Trash2 /> Limpar comprados
                </button>
              )}
            </div>
          ) : (
            <Empty icon={ShoppingBasket} title="Sua lista está vazia" action={<Link href="/colecoes" className="btn dark">Explorar receitas</Link>}>
              Abra uma receita e toque em “Ingredientes na lista”, gere a lista a partir do cardápio da sua ceia ou adicione itens manualmente.
            </Empty>
          )}
        </section>

        <section className="panel">
          <div className="eyebrow">Adicione um item</div>
          <h2 style={{ margin: '6px 0 16px' }}>Faltou alguma coisa?</h2>
          <form className="stack" onSubmit={add}>
            <div className="group"><label htmlFor="new-item">Item</label><input id="new-item" className="field" value={name} onChange={(e) => setName(e.target.value)} placeholder="Ex.: chocolate em gotas" maxLength={120} /></div>
            <div className="group"><label htmlFor="new-qty">Quantidade</label><input id="new-qty" className="field" value={quantity} onChange={(e) => setQuantity(e.target.value)} placeholder="Ex.: 500 g" maxLength={40} /></div>
            <button type="submit" className="btn dark" disabled={!name.trim()}><Plus /> Adicionar</button>
          </form>
          <p className="muted small" style={{ marginTop: 16 }}>
            Ingredientes iguais só são somados quando estão na <b>mesma unidade</b>. Medidas diferentes (por exemplo, gramas e xícaras) ficam em linhas separadas — o Clube não converte unidades automaticamente.
          </p>
        </section>
      </div>
      {editing && <EditItem item={editing} onClose={() => setEditing(null)} />}
    </>
  );
}

export default function ShoppingPage() {
  usePageTitle('Lista de compras');
  return (
    <>
      <PageHead eyebrow="Tudo à mão na hora de comprar" title="Lista de compras." sub="Reúna os ingredientes das receitas e do cardápio da ceia, organizados por categoria." />
      <Guard what="A lista de compras">
        <ShoppingList />
      </Guard>
    </>
  );
}
