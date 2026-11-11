import Link from 'next/link';

export default function NotFound() {
  return (
    <div className="authform" style={{ minHeight: '100dvh' }}>
      <div className="authcard center" style={{ justifyItems: 'center' }}>
        <div className="brandmark" style={{ background: 'var(--forest)' }}>✦</div>
        <div className="eyebrow">Erro 404</div>
        <h1>Esta página saiu do cardápio.</h1>
        <p className="sub">O endereço não existe ou foi movido.</p>
        <Link href="/" className="btn dark">Voltar ao início</Link>
      </div>
    </div>
  );
}
