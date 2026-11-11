"""
Teste de ponta a ponta do MODO DEMONSTRAÇÃO (navegador real, via Playwright).

Percorre o fluxo completo: administradora revisa → aprova → confirma a permissão → publica →
ativa a temporada; cliente usa calculadora, lista de compras, planejador, modo cozinheiro,
temporizadores, desafios e Chef; visitante encontra os bloqueios; telas de celular sem rolagem lateral.

Como rodar (o banco da demonstração precisa estar "zerado": use uma janela nova ou "Reiniciar"):
    NEXT_PUBLIC_DEMO_MODE=true npm run build && NEXT_PUBLIC_DEMO_MODE=true npm start
    pip install playwright && python -m playwright install chromium
    BASE_URL=http://localhost:3000 SHOTS_DIR=./capturas python tests/e2e/fluxo_demo.py
"""
import os
import asyncio, json, sys
from playwright.async_api import async_playwright, expect

BASE = os.environ.get("BASE_URL", "http://localhost:3000")
SHOTS = os.environ.get("SHOTS_DIR", "/tmp/shots")
os.makedirs(SHOTS, exist_ok=True)
SLUG = "pave-floresta-negra-com-creme-danete"
results = []
def ok(name, cond=True, extra=""):
    results.append((name, bool(cond), extra))
    print(("PASS " if cond else "FAIL ") + name + (f" — {extra}" if extra else ""), flush=True)

async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(args=["--no-sandbox"])
        ctx = await b.new_context(viewport={"width":1440,"height":900}, locale="pt-BR", timezone_id="America/Sao_Paulo")
        pg = await ctx.new_page()
        errors=[]
        pg.on("console", lambda m: errors.append(m.text[:400]) if m.type=="error" else None)
        pg.on("pageerror", lambda e: errors.append("PAGEERROR "+str(e)[:400]))
        async def go(path, wait=700):
            await pg.goto(BASE+path, wait_until="networkidle")
            await pg.wait_for_timeout(wait)
        async def shot(name, full=True):
            await pg.screenshot(path=f"{SHOTS}/{name}.png", full_page=full)
        async def toast_text():
            await pg.wait_for_timeout(350)
            return " | ".join(await pg.locator(".toast").all_inner_texts())

        # ---------- A. administradora ----------
        await go("/admin/receitas")
        await pg.get_by_role("button", name="Só com ficha").click()
        rows = pg.locator("table.table tbody tr")
        ok("admin: filtro 'só com ficha' mostra 1 item", await rows.count() == 1, str(await rows.count()))
        await rows.first.click()
        await pg.wait_for_url("**/admin/receitas/**")
        await pg.wait_for_timeout(900)
        await pg.get_by_role("button", name="Aprovar ficha").click()
        t = await toast_text()
        ok("admin: aprovar com pontos em aberto é bloqueado", "pontos de revisão" in t, t)
        n = 0
        while await pg.get_by_role("button", name="Resolver").count() > 0 and n < 40:
            await pg.get_by_role("button", name="Resolver").first.click()
            await pg.get_by_role("button", name="Marcar como resolvido").click()
            await pg.wait_for_timeout(260)
            n += 1
        ok("admin: resolveu os pontos de revisão", n >= 10, f"{n} resolvidos")
        await pg.wait_for_timeout(3800)
        await pg.get_by_role("button", name="Aprovar ficha").click()
        await pg.wait_for_timeout(600)
        ok("admin: ficha aprovada", await pg.locator(".pagehead .pill", has_text="Aprovada").count() == 1)
        await pg.get_by_role("button", name="Publicar", exact=True).click()
        t = await toast_text()
        ok("admin: publicar sem permissão comercial é bloqueado", "permissão comercial" in t, t)
        await shot("d-admin-editor")
        editor_url = pg.url

        await go("/admin/documentos")
        card = pg.locator("section.panel", has_text="Pavê Floresta Negra")
        await card.locator("select").select_option("confirmed")
        await card.get_by_role("button", name="Salvar permissão").click()
        t = await toast_text()
        ok("admin: confirmar permissão exige registrar a origem", "Observações" in t, t)
        await card.locator("input.field").fill("Autorização registrada para teste de ponta a ponta")
        await card.get_by_role("button", name="Salvar permissão").click()
        await pg.wait_for_timeout(700)
        ok("admin: permissão confirmada", await pg.locator("section.panel", has_text="Pavê Floresta Negra").locator(".pill", has_text="Permissão: Confirmada").count() == 1)
        await shot("d-admin-documentos")

        await pg.goto(editor_url, wait_until="networkidle"); await pg.wait_for_timeout(800)
        await pg.get_by_role("button", name="Publicar", exact=True).click()
        await pg.wait_for_timeout(700)
        ok("admin: receita publicada", await pg.locator(".pagehead .pill", has_text="Publicada").count() == 1)

        await go("/admin/temporadas")
        await pg.locator("#s-status").select_option("active")
        await pg.locator("#s-price").fill("49,90")
        await pg.get_by_role("button", name="Salvar temporada").click()
        await pg.wait_for_timeout(900)
        ok("admin: temporada ativa e à venda", await pg.locator(".pill", has_text="À venda por").count() == 1, await pg.locator(".pill").nth(1).inner_text() if await pg.locator(".pill").count() > 1 else "")
        await shot("d-admin-temporada")
        await go("/admin/auditoria")
        ok("admin: auditoria registrou as ações", await pg.locator("table.table tbody tr").count() >= 4, str(await pg.locator("table.table tbody tr").count()))

        # ---------- B. cliente ----------
        await pg.locator(".demobar .seg button", has_text="Cliente").click()
        await go("/")
        stat = await pg.locator(".stats .stat b").first.inner_text()
        ok("cliente: início mostra 1 receita disponível", stat.strip() == "1", stat)
        await shot("d-home-cliente")
        await go("/acesso")
        ok("cliente: cortesia de demonstração já vale com a temporada ativa", await pg.get_by_text("Bom proveito").count() >= 1)

        await go(f"/receitas/{SLUG}")
        ok("cliente: vê a ficha completa", await pg.get_by_text("leite condensado").count() >= 1 and await pg.get_by_role("link", name="Iniciar modo cozinheiro").count() == 1)
        await pg.get_by_role("button", name="Aumentar").click()
        await pg.get_by_role("button", name="Aumentar").click()
        await pg.wait_for_timeout(300)
        body = await pg.locator("section.panel", has_text="Calculadora de porções").inner_text()
        ok("cliente: calculadora 2 travessas → 1.200 g, sem converter", "2 travessas" in body and "1.200 g" in body and "1.000 ml" in body and "2 pacotes" in body, "")
        ok("cliente: medidas textuais preservadas e validação sinalizada", "quantidade não informada" in body and "valide na prática" in body)
        await shot("d-receita-2x")
        await pg.get_by_role("button", name="Ingredientes na lista").click()
        t = await toast_text()
        ok("cliente: ingredientes enviados à lista", "11 itens" in t, t)
        await pg.get_by_role("button", name="Adicionar à minha ceia").click()
        await pg.wait_for_timeout(500)
        await shot("d-sheet-ceia", full=False)
        await pg.get_by_role("button", name="Criar e adicionar receita").click()
        t = await toast_text()
        ok("cliente: planejamento criado pela receita", "Planejamento criado" in t, t)

        await go("/minha-ceia", 1200)
        txt = await pg.locator(".content").inner_text()
        ok("cliente: planejamento com cardápio", "Minha Ceia em Família" in txt and "Pavê Floresta Negra" in txt and "2 travessas" in txt)
        ok("cliente: cronograma calculado (12:26 / 13:00 / 20:00)", "12:26" in txt and "13:00" in txt and "20:00" in txt, "")
        ok("cliente: checklist padrão com 6 tarefas", "0/6" in txt)
        await shot("d-minha-ceia")

        await go("/lista", 1000)
        txt = await pg.locator(".content").inner_text()
        ok("cliente: lista com 11 itens agrupados", "LATICÍNIOS" in txt.upper() and "1.200 g" in txt and "Granulé" in txt)
        await pg.locator(".shopitem input[type=checkbox]").first.check()
        await pg.wait_for_timeout(500)
        ok("cliente: marcar item como comprado", (await pg.locator(".stats .stat b").nth(1).inner_text()).strip() == "1")
        await pg.locator("#new-item").fill("guardanapos"); await pg.locator("#new-qty").fill("2 pacotes")
        await pg.get_by_role("button", name="Adicionar", exact=True).click()
        await pg.wait_for_timeout(600)
        txt = await pg.locator(".shoppinglist").first.inner_text()
        ok("cliente: item manual adicionado", "Guardanapos" in txt and "2 pacotes" in txt, "")
        await shot("d-lista")

        await go(f"/cozinhar/{SLUG}?f=2", 1300)
        ok("cozinheiro: abre na etapa 1 de 16", "etapa 1 de 16" in (await pg.locator(".cookhead").inner_text()).lower())
        first = await pg.locator(".cookbody").inner_text()
        ok("cozinheiro: mostra ingredientes da etapa com fator", "200 g" in first and "150 ml" in first, first[:160].replace("\n"," / "))
        await pg.get_by_role("button", name="Próxima etapa").click(); await pg.wait_for_timeout(250)
        await pg.get_by_role("button", name="Próxima etapa").click(); await pg.wait_for_timeout(350)
        await pg.locator(".cooktimer").first.click(); await pg.wait_for_timeout(1300)
        clock = await pg.locator(".cooktimer .clock").first.inner_text()
        ok("cozinheiro: temporizador de 4 min iniciado", clock.startswith("03:5"), clock)
        await shot("d-cozinhar", full=False)
        # sai e volta: retoma na etapa 3, com o temporizador correndo
        await go("/temporizadores", 900)
        ok("temporizador continua fora da receita", await pg.locator(".timerrow").count() == 1 and (await pg.locator(".timerrow .clock").first.inner_text()).startswith("03:"), "")
        await shot("d-temporizadores")
        await go(f"/cozinhar/{SLUG}", 1300)
        ok("cozinheiro: retoma de onde parou (etapa 3)", "etapa 3 de 16" in (await pg.locator(".cookhead").inner_text()).lower())
        for _ in range(13):
            await pg.get_by_role("button", name="Próxima etapa").click(); await pg.wait_for_timeout(120)
        await pg.get_by_role("button", name="Concluir receita").click(); await pg.wait_for_timeout(900)
        ok("cozinheiro: receita concluída", await pg.get_by_text("Receita concluída").count() >= 1)
        await shot("d-cozinhar-fim", full=False)

        await go("/desafios", 1200)
        big = await pg.locator(".scorecard .big").inner_text()
        ok("desafios: pontos concedidos (sobremesa + ceia = 40)", big.strip() == "40", big)
        await shot("d-desafios")

        await go(f"/chef?receita={SLUG}", 1000)
        await pg.locator(".compose input").fill("Quais os ingredientes do pavê?")
        await pg.locator(".compose button").click(); await pg.wait_for_timeout(1200)
        ans = await pg.locator(".bubble.bot").last.inner_text()
        ok("chef: responde pela ficha e cita a fonte", "600 g de leite condensado" in ans and "Fonte: ficha" in ans, ans[:120].replace("\n"," / "))
        await pg.locator(".compose input").fill("Posso trocar o creme de leite por iogurte?")
        await pg.locator(".compose button").click(); await pg.wait_for_timeout(1200)
        ans = await pg.locator(".bubble.bot").last.inner_text()
        ok("chef: avisa que substituição não é da receita original", "NÃO faz parte da receita original" in ans)
        await pg.locator(".compose input").fill("Como faço um peru assado?")
        await pg.locator(".compose button").click(); await pg.wait_for_timeout(1200)
        ans = await pg.locator(".bubble.bot").last.inner_text()
        ok("chef: diz quando não há informação", "Não encontrei essa informação" in ans)
        await shot("d-chef")
        await go("/perfil", 900); await shot("d-perfil")

        # persistência após recarregar
        await pg.reload(wait_until="networkidle"); await go("/lista", 900)
        ok("dados persistem após recarregar", "Guardanapos" in await pg.locator(".content").inner_text())

        # ---------- C. visitante ----------
        await pg.locator(".demobar .seg button", has_text="Visitante").click()
        await go(f"/receitas/{SLUG}", 900)
        txt = await pg.locator(".content").inner_text()
        ok("visitante: vê a capa mas não a ficha (paywall)", "Ficha completa para membros" in txt and "leite condensado" not in txt)
        await shot("d-paywall")
        await go("/minha-ceia", 700)
        ok("visitante: ferramentas pedem login", "Entre para continuar" in await pg.locator(".content").inner_text())
        await go(f"/cozinhar/{SLUG}", 900)
        ok("visitante: modo cozinheiro bloqueado", "faz parte do acesso" in await pg.locator(".cook").inner_text())
        await go("/admin", 700)
        ok("visitante: painel admin restrito", "Área restrita" in await pg.locator(".content").inner_text())
        await go("/colecoes/panetones-chocotones", 800)
        ok("visitante: coleção sem publicadas mostra 'em curadoria' (sem títulos)", "Coleção em curadoria" in await pg.locator(".content").inner_text() and "Panetone Tradicional" not in await pg.locator(".content").inner_text())
        await go("/colecoes/manjar-de-coco", 800)
        ok("visitante: coleção pendente mostra 'em breve'", "Conteúdo em breve" in await pg.locator(".content").inner_text())

        # ---------- D. celular ----------
        await pg.locator(".demobar .seg button", has_text="Cliente").click()
        m = await b.new_context(viewport={"width":390,"height":844}, device_scale_factor=2, is_mobile=True, has_touch=True, locale="pt-BR", timezone_id="America/Sao_Paulo", storage_state=await ctx.storage_state())
        mp = await m.new_page()
        mp.on("console", lambda msg: errors.append("[mobile] "+msg.text[:300]) if msg.type=="error" else None)
        mp.on("pageerror", lambda e: errors.append("[mobile] PAGEERROR "+str(e)[:300]))
        for path, name, full in [("/", "m-home", True), (f"/receitas/{SLUG}", "m-receita", True), ("/minha-ceia", "m-ceia", True), ("/lista", "m-lista", True), (f"/cozinhar/{SLUG}", "m-cozinhar", False), ("/desafios", "m-desafios", True), ("/chef", "m-chef", False), ("/colecoes", "m-colecoes", True)]:
            await mp.goto(BASE+path, wait_until="networkidle"); await mp.wait_for_timeout(1000)
            overflow = await mp.evaluate("document.documentElement.scrollWidth - document.documentElement.clientWidth")
            ok(f"celular {path}: sem rolagem horizontal", overflow <= 1, f"overflow {overflow}px")
            await mp.screenshot(path=f"{SHOTS}/{name}.png", full_page=full)
        ok("celular: navegação inferior visível", await mp.locator(".mobilenav").is_visible())

        print("\nconsole errors:", json.dumps(errors[:15], ensure_ascii=False))
        failed = [r for r in results if not r[1]]
        print(f"\n{len(results)-len(failed)}/{len(results)} verificações ok")
        await b.close()
        sys.exit(1 if failed else 0)
asyncio.run(main())
