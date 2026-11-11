'use client';

import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { Suspense, useEffect, useState } from 'react';
import { CircleCheck, Clock, TriangleAlert } from 'lucide-react';
import { useSession } from '@/data/session';
import { Empty, usePageTitle } from '@/components/ui';

/**
 * Retorno do checkout. Esta página NUNCA libera acesso: ela apenas consulta se o
 * servidor já confirmou o pagamento (via webhook) e informa a situação.
 */
function Return() {
  usePageTitle('Retorno do pagamento');
  const params = useSearchParams();
  const hinted = params.get('status');
  const { access, refresh, ready } = useSession();
  const [attempts, setAttempts] = useState(0);

  useEffect(() => {
    if (!ready || access.has_access || attempts >= 8 || hinted === 'failure') return;
    const timer = window.setTimeout(async () => {
      await refresh();
      setAttempts((n) => n + 1);
    }, 4000);
    return () => window.clearTimeout(timer);
  }, [ready, access.has_access, attempts, hinted, refresh]);

  if (access.has_access) {
    return (
      <Empty icon={CircleCheck} title="Pagamento confirmado!" action={<Link href="/colecoes" className="btn primary">Explorar as coleções</Link>}>
        Seu acesso à temporada está liberado. Bom proveito!
      </Empty>
    );
  }
  if (hinted === 'failure') {
    return (
      <Empty icon={TriangleAlert} title="O pagamento não foi concluído" action={<Link href="/acesso" className="btn dark">Tentar novamente</Link>}>
        Nenhum valor foi confirmado. Você pode tentar de novo com outra forma de pagamento.
      </Empty>
    );
  }
  return (
    <Empty icon={Clock} title={attempts >= 8 ? 'Ainda aguardando a confirmação' : 'Confirmando seu pagamento…'} action={<Link href="/acesso" className="btn outline">Ver situação do pedido</Link>}>
      {attempts >= 8
        ? 'Pagamentos por Pix ou boleto podem levar alguns minutos (ou até dois dias úteis, no boleto). O acesso é liberado automaticamente assim que o Mercado Pago confirmar.'
        : 'Assim que o Mercado Pago confirmar, o acesso é liberado automaticamente. Isso costuma levar alguns segundos.'}
    </Empty>
  );
}

export default function ReturnPage() {
  return (
    <Suspense>
      <Return />
    </Suspense>
  );
}
