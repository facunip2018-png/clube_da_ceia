"""
Verificações complementares de ponta a ponta (modo demonstração): busca, montador de rabanadas,
edição no painel, coleções, concessão/revogação de acesso, tela de compra e reinício da demonstração.
Uso: BASE_URL=http://localhost:3000 python tests/e2e/fluxo_admin.py   (com o banco da demonstração zerado)
"""
import os
import asyncio, json, sys
from playwright.async_api import async_playwright
BASE=os.environ.get("BASE_URL","http://localhost:3000"); SHOTS=os.environ.get("SHOTS_DIR","/tmp/shots"); os.makedirs(SHOTS, exist_ok=True); SLUG="pave-floresta-negra-com-creme-danete"
results=[]
def ok(name, cond=True, extra=""):
    results.append((name,bool(cond))); print(("PASS " if cond else "FAIL ")+name+(f" — {extra}" if extra else ""), flush=True)
async def main():
    async with async_playwright() as p:
        b=await p.chromium.launch(args=["--no-sandbox"])
        ctx=await b.new_context(viewport={"width":1440,"height":900}, locale="pt-BR", timezone_id="America/Sao_Paulo")
        pg=await ctx.new_page(); errors=[]
        pg.on("console", lambda m: errors.append(m.text[:300]) if m.type=="error" else None)
        pg.on("pageerror", lambda e: errors.append("PAGEERROR "+str(e)[:300]))
        async def go(path, wait=800):
            await pg.goto(BASE+path, wait_until="networkidle"); await pg.wait_for_timeout(wait)
        async def toast():
            await pg.wait_for_timeout(350); return " | ".join(await pg.locator(".toast").all_inner_texts())

        # busca global
        await go("/")
        await pg.locator(".search input").fill("floresta"); await pg.locator(".search input").press("Enter")
        await pg.wait_for_url("**/colecoes?q=floresta"); await pg.wait_for_timeout(700)
        ok("busca global encontra a receita", await pg.locator(".recipe").count()==1, str(await pg.locator(".recipe").count()))

        # ficha catalogada (sem PDF) para a administradora
        await go("/receitas/panetone-tradicional")
        t=await pg.locator(".content").inner_text()
        ok("item sem PDF mostra 'ficha em preparação' e nenhum ingrediente", "Ficha interativa em preparação" in t and await pg.locator("#ingredientes").count()==0 and await pg.locator(".inglist").count()==0)

        # montador de rabanadas (prévia admin)
        await go("/colecoes/rabanadas-recheadas", 1000)
        t=await pg.locator(".content").inner_text()
        ok("montador: aparece com aviso de combinações não verificadas", "Monte sua rabanada" in t and "Prévia para a administração" in t)
        await pg.get_by_role("button", name="Pão para Rabanada Salgada").click(); await pg.wait_for_timeout(300)
        t=await pg.locator("section.panel", has_text="Monte sua rabanada").inner_text()
        ok("montador: base salgada só oferece recheios salgados", "Gorgonzola" in t and "Peito de Peru" in t and "Nutella" not in t and "Doce de Leite" not in t)
        await pg.get_by_role("button", name="Rabanada Salgada com Salame e Ricota").click(); await pg.wait_for_timeout(300)
        t=await pg.locator("section.panel", has_text="Monte sua rabanada").inner_text()
        ok("montador: mostra a combinação escolhida", "SUA COMBINAÇÃO" in t.upper() and "Preparação da Calda" in t)
        await pg.screenshot(path=f"{SHOTS}/d-rabanadas.png", full_page=True)

        # editor: alterar ingrediente e etapa
        await go("/admin/receitas"); await pg.get_by_role("button", name="Só com ficha").click()
        await pg.locator("table.table tbody tr").first.click(); await pg.wait_for_url("**/admin/receitas/**"); await pg.wait_for_timeout(900)
        row=pg.locator(".editrow").first
        await row.locator("input[aria-label=Quantidade]").fill("610"); await row.get_by_role("button", name="Salvar").click()
        ok("editor: ingrediente salvo", "Ingrediente atualizado" in await toast())
        await pg.reload(wait_until="networkidle"); await pg.wait_for_timeout(900)
        ok("editor: alteração persistiu", await pg.locator(".editrow").first.locator("input[aria-label=Quantidade]").input_value()=="610")
        await pg.locator(".editrow").first.locator("input[aria-label=Quantidade]").fill("600"); await pg.locator(".editrow").first.get_by_role("button", name="Salvar").click(); await pg.wait_for_timeout(500)
        await pg.locator("#r-serv").fill("12"); await pg.get_by_role("button", name="Salvar dados").click()
        ok("editor: dados gerais salvos", "Dados da receita salvos" in await toast())
        await go(f"/receitas/{SLUG}", 1000)
        t=await pg.locator(".content").inner_text()
        ok("receita: com porções informadas pelo admin, a calculadora passa a usar porções", "12 porções" in t and "A ficha rende 12 porções" in t)
        # volta ao original (porções não informadas no material)
        await go("/admin/receitas"); await pg.get_by_role("button", name="Só com ficha").click()
        await pg.locator("table.table tbody tr").first.click(); await pg.wait_for_url("**/admin/receitas/**"); await pg.wait_for_timeout(900)
        await pg.locator("#r-serv").fill(""); await pg.get_by_role("button", name="Salvar dados").click(); await pg.wait_for_timeout(500)

        # coleções e desafios
        await go("/admin/catalogo")
        first=pg.locator("table.table").first.locator("tbody tr").first
        await first.locator("input[aria-label='Descrição']").fill("Descrição editada no painel"); await first.get_by_role("button", name="Salvar").click()
        ok("catálogo: coleção salva", "Coleção salva" in await toast())

        # pessoas: revogar a cortesia da cliente e simular pagamento
        await go("/admin/temporadas"); await pg.locator("#s-status").select_option("active"); await pg.locator("#s-price").fill("59,90")
        await pg.get_by_role("button", name="Salvar temporada").click(); await pg.wait_for_timeout(700)
        await go("/admin/acessos")
        row=pg.locator("table.table").first.locator("tbody tr", has_text="cliente@demo.clube")
        ok("pessoas: cliente demo com cortesia liberada", await row.locator(".pill", has_text="Liberado").count()==1)
        await row.get_by_role("button", name="Revogar").click(); await pg.get_by_role("button", name="Revogar", exact=True).last.click(); await pg.wait_for_timeout(600)
        row=pg.locator("table.table").first.locator("tbody tr", has_text="cliente@demo.clube")
        ok("pessoas: acesso revogado com bloqueio manual", await row.locator(".pill", has_text="Revogado").count()==1 and await row.locator(".pill", has_text="bloqueio manual").count()==1)
        await pg.locator(".demobar .seg button", has_text="Cliente").click(); await go("/acesso", 900)
        t=await pg.locator(".content").inner_text()
        ok("acesso: com bloqueio manual, a compra não é oferecida", "59,90" in t and "suspenso pela administração" in t and await pg.get_by_role("button", name="Simular pagamento aprovado").count()==0)
        await pg.screenshot(path=f"{SHOTS}/d-acesso.png", full_page=True)

        await pg.locator(".demobar .seg button", has_text="Administradora").click(); await go("/admin/acessos")
        row=pg.locator("table.table").first.locator("tbody tr", has_text="cliente@demo.clube")
        await row.get_by_role("button", name="Conceder cortesia").click(); await pg.wait_for_timeout(600)
        await pg.locator(".demobar .seg button", has_text="Cliente").click(); await go("/acesso", 900)
        ok("acesso: liberado de novo após o admin reabrir", "Bom proveito" in await pg.locator(".content").inner_text())
        # compra simulada: admin revoga SEM bloqueio (via reabrir + revogar não se aplica); usa uma cliente sem acesso
        await pg.locator(".demobar .seg button", has_text="Administradora").click(); await go("/admin/acessos")
        row=pg.locator("table.table").first.locator("tbody tr", has_text="cliente@demo.clube")
        await row.get_by_role("button", name="Revogar").click(); await pg.get_by_role("button", name="Revogar", exact=True).last.click(); await pg.wait_for_timeout(600)
        await go("/admin/auditoria")
        ok("auditoria: revogações e concessões registradas", "memberships.revoked" in await pg.locator(".content").inner_text() and "memberships.active" in await pg.locator(".content").inner_text())

        # reiniciar demonstração (diálogo do próprio app)
        await pg.locator(".demobar .link").click(); await pg.wait_for_timeout(300)
        ok("diálogo de confirmação é do próprio app", await pg.locator(".sheet", has_text="Reiniciar a demonstração?").count()==1)
        await pg.get_by_role("button", name="Reiniciar", exact=True).last.click(); await pg.wait_for_load_state("networkidle"); await pg.wait_for_timeout(1200)
        await go("/admin/acessos", 900)
        ok("demonstração reiniciada (volta ao estado inicial)", await pg.locator("table.table").first.locator("tbody tr", has_text="cliente@demo.clube").locator(".pill", has_text="Liberado").count()==1 and "Administradora" in await pg.locator(".demobar .seg button.active").inner_text())
        print("console errors:", json.dumps(errors[:10], ensure_ascii=False))
        failed=[r for r in results if not r[1]]; print(f"{len(results)-len(failed)}/{len(results)} verificações ok")
        await b.close(); sys.exit(1 if failed else 0)
asyncio.run(main())
