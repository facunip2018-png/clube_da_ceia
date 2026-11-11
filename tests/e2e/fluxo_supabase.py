"""
Fluxo no navegador com o app em MODO SUPABASE (banco real): login pelo formulário, sessão por cookies,
proteção do /admin no servidor e leitura/gravação pelas telas.

Pré-requisito: rodar antes `SMOKE_KEEP=1 npm run test:hosted` (deixa no banco a ficha "zz-teste",
a temporada de teste e o acesso do cliente de teste). Depois rode `npm run test:hosted` (sem KEEP)
para desfazer.

  BASE_URL=http://127.0.0.1:3100 TEST_ADMIN_EMAIL=... TEST_CUSTOMER_EMAIL=... TEST_PASSWORD=... \
  python3 tests/e2e/fluxo_supabase.py
"""
import os
import re
import sys

from playwright.sync_api import sync_playwright

BASE = os.environ.get("BASE_URL", "http://127.0.0.1:3100")
ADMIN = os.environ["TEST_ADMIN_EMAIL"]
CUSTOMER = os.environ["TEST_CUSTOMER_EMAIL"]
PASSWORD = os.environ["TEST_PASSWORD"]
PAVE_ID = "480e2ce8-4ca0-5937-901c-dfd4635b091a"

results = []
problems = []


def check(name, ok, detail=""):
    results.append((name, bool(ok)))
    print(("✓ " if ok else "✗ ") + name + (f" — {detail}" if detail else ""))


def watch(page, who):
    page.on("console", lambda m: problems.append(f"[{who}] console: {m.text[:200]}") if m.type == "error" else None)
    page.on("pageerror", lambda e: problems.append(f"[{who}] erro de página: {str(e)[:200]}"))

    def on_response(response):
        url = response.url
        if response.status >= 400 and ("supabase.co" in url or "/api/" in url):
            problems.append(f"[{who}] {response.request.method} {url.split('?')[0][-70:]} → {response.status}")

    page.on("response", on_response)


def text(page, path):
    page.goto(BASE + path)
    page.wait_for_load_state("networkidle")
    page.wait_for_timeout(600)
    return page.inner_text("body").lower()


def login(page, email):
    page.goto(BASE + "/entrar")
    page.fill("#a-email", email)
    page.fill("#a-pass", PASSWORD)
    page.click("button[type=submit]")
    page.wait_for_url(lambda url: "/entrar" not in url, timeout=30000)
    page.wait_for_load_state("networkidle")


with sync_playwright() as p:
    browser = p.chromium.launch()

    # ---------------------------------------------------------------- visitante
    context = browser.new_context(viewport={"width": 1280, "height": 900})
    page = context.new_page()
    watch(page, "visitante")
    body = text(page, "/")
    check("visitante: início mostra as coleções do banco", "panetones" in body and "rabanadas" in body)
    page.goto(BASE + "/admin")
    check("visitante: /admin leva ao login", "/entrar" in page.url, page.url.replace(BASE, ""))
    body = text(page, "/receitas/pave-floresta-negra-com-creme-danete")
    check("visitante: ficha não publicada não vaza conteúdo", "leite condensado" not in body and "dilua o chocolate" not in body)
    context.close()

    # ---------------------------------------------------------------- cliente com acesso
    context = browser.new_context(viewport={"width": 1280, "height": 900})
    page = context.new_page()
    watch(page, "cliente")
    login(page, CUSTOMER)
    check("cliente: login pelo formulário", "/entrar" not in page.url, page.url.replace(BASE, "") or "/")
    cookies = [c["name"] for c in context.cookies() if c["name"].startswith("sb-")]
    check("cliente: sessão gravada em cookie", len(cookies) > 0, ", ".join(cookies)[:60])
    body = text(page, "/perfil")
    check("cliente: perfil mostra a conta", "teste cliente" in body or CUSTOMER in body)
    page.goto(BASE + "/admin")
    page.wait_for_load_state("networkidle")
    check("cliente: /admin bloqueado no servidor", not page.url.replace(BASE, "").startswith("/admin"), page.url.replace(BASE, "") or "/")
    body = text(page, "/receitas/zz-teste-receita")
    check("cliente: ficha publicada com ingredientes e etapas", "ingrediente de teste" in body and "etapa de teste" in body)
    body = text(page, "/receitas/pave-floresta-negra-com-creme-danete")
    check("cliente: ficha em revisão continua invisível", "leite condensado" not in body)
    page.goto(BASE + "/receitas/zz-teste-receita")
    page.wait_for_load_state("networkidle")
    favorite = page.get_by_role("button", name=re.compile("favorit", re.I)).first
    before = favorite.inner_text()
    favorite.click()
    page.wait_for_timeout(1500)
    middle = page.get_by_role("button", name=re.compile("favorit", re.I)).first.inner_text()
    page.get_by_role("button", name=re.compile("favorit", re.I)).first.click()
    page.wait_for_timeout(1500)
    after = page.get_by_role("button", name=re.compile("favorit", re.I)).first.inner_text()
    check("cliente: favoritar e desfavoritar grava no banco", before != middle and after == before, f"{before!r} → {middle!r} → {after!r}")
    body = text(page, "/minha-ceia")
    check("cliente: planejamento salvo aparece", "zz-teste ceia" in body)
    body = text(page, "/lista")
    check("cliente: lista de compras salva aparece", "zz-teste item" in body)
    page.goto(BASE + "/receitas/zz-teste-receita")
    page.wait_for_load_state("networkidle")
    page.get_by_role("button", name=re.compile("ingredientes na lista", re.I)).click()
    page.wait_for_timeout(2500)
    body = text(page, "/lista")
    check("cliente: ingredientes da ficha vão para a lista (inserção em lote)", "ingrediente de teste" in body)
    page.goto(BASE + "/minha-ceia")
    page.wait_for_load_state("networkidle")
    page.locator("button", has_text=re.compile(r"^\s*Novo\s*$")).first.click()
    page.fill("#plan-date", "2026-12-31")
    page.fill("#plan-title", "zz-teste réveillon")
    page.click("button[type=submit]")
    page.wait_for_timeout(3000)
    body = page.inner_text("body").lower()
    check("cliente: cria planejamento com checklist padrão (inserção em lote)", "zz-teste réveillon" in body)
    body = text(page, "/desafios")
    check("cliente: desafios calculados no servidor", "40" in body, "pontos da conta de teste")
    body = text(page, "/cozinhar/zz-teste-receita")
    check("cliente: modo cozinheiro carrega a etapa", "etapa de teste" in body)
    page.goto(BASE + "/chef")
    page.wait_for_load_state("networkidle")
    bubbles = page.locator(".bubble.bot").count()
    page.fill('input[aria-label="Sua pergunta"]', "Quais são as etapas da ZZ Receita de teste?")
    page.keyboard.press("Enter")
    try:
        page.wait_for_function("n => document.querySelectorAll('.bubble.bot').length > n && !document.querySelector('.typing')", arg=bubbles, timeout=30000)
        answer = page.locator(".bubble.bot").last.inner_text()
        check("cliente: Chef responde pela rota do servidor (sessão real)", len(answer) > 20, answer[:90].replace("\n", " "))
    except Exception as error:  # noqa: BLE001
        check("cliente: Chef responde pela rota do servidor (sessão real)", False, str(error)[:120])
    context.close()

    # ---------------------------------------------------------------- administração
    context = browser.new_context(viewport={"width": 1280, "height": 900})
    page = context.new_page()
    watch(page, "admin")
    login(page, ADMIN)
    page.goto(BASE + "/admin")
    page.wait_for_load_state("networkidle")
    check("admin: /admin liberado", page.url.replace(BASE, "").startswith("/admin"))
    body = text(page, "/admin/receitas")
    check("admin: lista o catálogo em revisão", "panetone tradicional" in body and "floresta negra" in body)
    body = text(page, f"/admin/receitas/{PAVE_ID}")
    check("admin: ficha do Pavê com partes e pontos de revisão", "creme danete" in body and "leite condensado" in body)
    body = text(page, "/admin/documentos")
    check("admin: documentos de origem", "rabanadas recheadas" in body and "tortas doces" in body)
    body = text(page, "/admin/temporadas")
    check("admin: temporadas", "natal & ano-novo 2026" in body and "zz temporada de teste" in body)
    body = text(page, "/admin/acessos")
    check("admin: acessos concedidos", CUSTOMER in body or "teste cliente" in body)
    body = text(page, "/admin/auditoria")
    check("admin: auditoria", "zz receita de teste" in body or "zz teste" in body)
    body = text(page, "/admin/catalogo")
    check("admin: indicadores do catálogo", "panetones" in body)
    context.close()
    browser.close()

check("nenhum erro de console ou resposta 4xx/5xx inesperada", not problems, f"{len(problems)} problema(s)")
for problem in problems[:12]:
    print("   ·", problem)
failed = [name for name, ok in results if not ok]
print(f"\n{len(results) - len(failed)} verificações OK · {len(failed)} falha(s)")
sys.exit(1 if failed else 0)
