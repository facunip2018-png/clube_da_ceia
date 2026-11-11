import Image from 'next/image';
import Link from 'next/link';
import type { ReactNode } from 'react';

export default function AuthLayout({ children }: { children: ReactNode }) {
  return (
    <div className="authwrap">
      <div className="authart">
        <Image src="/images/hero-ceia.jpg" alt="" fill priority sizes="(max-width: 900px) 100vw, 50vw" />
        <div className="eyebrow" style={{ color: '#e2c987' }}>✦ Natal &amp; Ano-Novo</div>
        <h1 style={{ marginTop: 12 }}>As melhores memórias começam à mesa.</h1>
        <p>Receitas, planejamento da ceia, lista de compras, modo cozinheiro e Chef IA em um só lugar.</p>
      </div>
      <div className="authform">
        <div className="authcard">
          <Link href="/" className="brandrow" aria-label="Clube da Ceia Perfeita — início">
            <div className="brandmark">✦</div>
            <div>
              <div className="brandtitle" style={{ color: 'var(--forest)' }}>CLUBE DA CEIA PERFEITA</div>
              <div className="brandsub" style={{ color: 'var(--gold-deep)' }}>NATAL &amp; ANO-NOVO</div>
            </div>
          </Link>
          {children}
        </div>
      </div>
    </div>
  );
}
