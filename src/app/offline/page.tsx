export const metadata = { title: 'Sem conexão' };

/** Página estática servida pelo service worker quando não há internet. Não contém conteúdo de receitas. */
export default function OfflinePage() {
  return (
    <div className="authform" style={{ minHeight: '100dvh' }}>
      <div className="authcard center" style={{ justifyItems: 'center' }}>
        <div className="brandmark" style={{ background: 'var(--forest)' }}>✦</div>
        <div className="eyebrow">Sem conexão</div>
        <h1>Você está offline.</h1>
        <p className="sub">As receitas do Clube ficam protegidas na sua conta e precisam de internet para abrir. Assim que a conexão voltar, é só recarregar.</p>
        <a href="/" className="btn dark">Tentar novamente</a>
      </div>
    </div>
  );
}
