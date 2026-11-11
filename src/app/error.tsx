'use client';

import { useEffect } from 'react';

export default function GlobalError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    console.error(error);
  }, [error]);
  return (
    <div className="authform" style={{ minHeight: '100dvh' }}>
      <div className="authcard center" style={{ justifyItems: 'center' }}>
        <div className="brandmark" style={{ background: 'var(--forest)' }}>✦</div>
        <div className="eyebrow">Algo não saiu como esperado</div>
        <h1>Tivemos um imprevisto na cozinha.</h1>
        <p className="sub">Tente novamente. Se o problema continuar, recarregue a página.</p>
        <div className="row" style={{ justifyContent: 'center' }}>
          <button type="button" className="btn dark" onClick={reset}>Tentar de novo</button>
          <a href="/" className="btn outline">Ir para o início</a>
        </div>
      </div>
    </div>
  );
}
