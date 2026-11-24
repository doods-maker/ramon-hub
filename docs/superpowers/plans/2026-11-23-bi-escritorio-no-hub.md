# BI do escritório no hub — plano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** aba "BI do escritório" (só admin) na Intranet → Resultados, onde o admin sobe o `bi-escritorio.html` e todos os admins o veem numa moldura isolada.

**Architecture:** `has_one_attached :ramon_bi` no `Account` (Active Storage → R2 privado, sem migração). `RamonBiController` (show/update) com policy admin-only devolve o HTML pela API autenticada; a página Vue põe o HTML em `<iframe sandbox="allow-scripts" :srcdoc>`.

**Tech Stack:** Rails (request spec RSpec), Vue 3 `<script setup>`, vitest.

**Spec:** `docs/superpowers/specs/2026-11-23-bi-escritorio-no-hub-design.md`

## Global Constraints

- **Skills do Matt em toda tarefa (ordem do Eduardo):** `mattpocock-skills:tdd` (teste primeiro), `mattpocock-skills:codebase-design` (onde fica a costura), revisão de cada tarefa e do PR com `mattpocock-skills:code-review` (nunca revisão genérica), corpo do PR com `mattpocock-skills:pr`.
- **Ver ≠ enviar:** policy com `show?` e `update?` separados; a regra de quem vê só em `RamonBiPolicy#show?` (vai abrir para sócios numa próxima fatia).

- O BI **nunca** entra no git (repo público): nada de HTML de exemplo com dado real em spec/fixture — use `<html><body>teste</body></html>`.
- Só administrador: rota `permissions: ['administrator']` + policy `@account_user.administrator?`.
- Upload: só `.html` com content-type `text/html`, até 5 MB; senão 422.
- iframe com `sandbox="allow-scripts"` e **sem** `allow-same-origin`.
- i18n só em `en.json`/`ramon.json` (frontend); sem `@` cru em string i18n.
- Lint: `rubocop-vps` (Ruby), eslint (JS/Vue). Commits Conventional.

## Review Focus

- Agente (não admin) chamando `GET`/`PUT` direto pela API → 401, e não vê a aba.
- Sem BI enviado ainda → página mostra "nenhuma versão enviada" e o botão, sem erro.
- Arquivo não-HTML ou > 5 MB → 422 com mensagem; a versão anterior continua.
- HTML com `<script>` tentando ler `parent.document` / `localStorage` → bloqueado pela sandbox (conferir o atributo no spec do componente).
- Novo upload substitui o anterior (só uma versão guardada).

---

### Task 1: Backend — anexo, policy, controller, rota

**Files:**
- Modify: `app/models/account.rb` (ao lado de `has_one_attached :contacts_export`)
- Create: `app/policies/ramon_bi_policy.rb`, `app/controllers/api/v1/accounts/ramon_bi_controller.rb`
- Modify: `config/routes.rb` (junto de `resource :ramon_relatorios`)
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md` (registrar a linha no `Account`)
- Test: `spec/requests/api/v1/accounts/ramon_bi_spec.rb`

**Interfaces:**
- Produces: `GET /api/v1/accounts/:id/ramon_bi` → `{ enviado: false }` ou `{ enviado: true, html:, enviado_em: iso8601, enviado_por: nome }`; `PUT` multipart `arquivo` → mesmo JSON do GET; 422 `{ error: }`.
- Quem enviou: `blob.metadata['enviado_por']` (nome do usuário) — sem coluna nova.

- [ ] **Step 1: request spec (modelo: `ramon_relatorios_spec.rb`)** — casos: sem auth 401; agente GET 401 e PUT 401; admin GET sem anexo → `enviado: false`; admin PUT `fixture_file_upload` de um `.html` mínimo → 200 e GET devolve `html` igual ao conteúdo, `enviado_por` = nome do admin; PUT de `.txt`/`text/plain` → 422 e anexo anterior intacto; PUT de > 5 MB (Tempfile) → 422; segundo PUT substitui (só 1 blob em `account.ramon_bi`).
- [ ] **Step 2:** push na branch, CI falha nos casos novos (sem Ruby local — o CI é o RED).
- [ ] **Step 3:** implementar. Policy `show?`/`update? = @account_user.administrator?`. Controller herda `Api::V1::Accounts::BaseController`, `authorize(:ramon_bi, :show?/:update?)`, lê com `Current.account.ramon_bi.download.force_encoding('UTF-8')`, grava com `attach(io:, filename: 'bi-escritorio.html', content_type: 'text/html', metadata: { enviado_por: Current.user.name })`. Rota: `resource :ramon_bi, only: [:show, :update], controller: 'ramon_bi'`.
- [ ] **Step 4:** `rubocop-vps` limpo; CI verde nos casos.
- [ ] **Step 5:** commit `feat(bi): BI do escritório guardado no hub, só admin`.

### Task 2: Frontend — aba, página, upload

**Files:**
- Create: `app/javascript/dashboard/api/ramonBi.js` (modelo `ramonRelatorios.js`: `get()`, `enviar(file)` com FormData + `PUT`)
- Create: `app/javascript/dashboard/routes/dashboard/ramon/pages/BiEscritorio.vue`
- Modify: `ramon.routes.js` (rota `ramon_bi_escritorio`, path `accounts/:accountId/ramon/bi-escritorio`, `permissions: ['administrator']`, `world: 'intranet'`)
- Modify: `helpers/navIntranet.js` (grupo `resultados`: `aba('ramon_bi_escritorio', 'BI_ESCRITORIO', { adminOnly: true })` depois de RELATORIOS)
- Modify: `i18n/locale/en/ramon.json` (`RAMON.NAV.BI_ESCRITORIO` = "BI do escritório"; `RAMON.BI_ESCRITORIO.{TITULO, ENVIAR, ENVIANDO, VAZIO, ENVIADO_EM ("Atualizado em {data} por {nome}"), ERRO_TIPO, ERRO_ENVIO}`)
- Test: `pages/specs/BiEscritorio.spec.js` + ajustar `helpers/specs/navIntranet.spec.js` se ele lista as abas

**Interfaces:** consome a API da Task 1.

- [ ] **Step 1: vitest** — com API mockada: (a) `enviado: false` → mostra VAZIO e botão, sem iframe; (b) `enviado: true` → iframe com `srcdoc` = html e `sandbox` exatamente `allow-scripts`; (c) escolher arquivo chama `enviar` e troca o `srcdoc` pelo novo html; (d) erro 422 mostra a mensagem e mantém o iframe anterior. navIntranet: aba aparece para admin, some para agente.
- [ ] **Step 2:** rodar `npx vitest run <arquivos>` → FAIL.
- [ ] **Step 3:** implementar a página: cabeçalho (título, "Atualizado em…", botão com `<input type="file" accept=".html,text/html">` escondido), iframe ocupando a altura (padrão visual do `Relatorios.vue`).
- [ ] **Step 4:** vitest PASS + eslint limpo nos arquivos tocados.
- [ ] **Step 5:** commit `feat(bi): aba BI do escritório na Intranet com envio da versão nova`.

### Task 3: BI funciona dentro da moldura isolada (fora do repo do hub)

**Files:** `C:\Users\dudsl\RAdvogados\juridico\projetos\bi-escritorio\bi_template.html:322`

- [ ] **Step 1:** abrir o BI atual num HTML de teste com `<iframe sandbox="allow-scripts" srcdoc>` no Edge headless e ver se troca de página quebra (erro de `replaceState`).
- [ ] **Step 2:** envolver `history.replaceState` em `try { } catch (e) {}`; `python montar.py`; repetir o teste → troca de página funciona, 0 erros no painel.

### Fechamento

- [ ] PR (skill `mattpocock-skills:pr`) + revisão `mattpocock-skills:code-review`; CI verde.
- [ ] Merge e deploy web+worker **com OK do Eduardo** (sem migração); login 200.
- [ ] Smoke (seção nova no consolidado): Eduardo sobe o BI; Ramon entra com o usuário dele e vê; advogada não vê a aba.
