# Onda E — Espalhar o Visual Material Claro — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Levar o tema Material claro (tokens bronze + cartões `shadow-sm` + Fraunces) às telas restantes do ramon — Funil, Pós-venda, Reuniões, Relatórios, Cálculos (spec Onda E) — consertar os hardcodes dark que quebram no tema claro (Esteira, Cockpit e componentes) e fechar os 4 minors deferidos da Onda A.

**Architecture:** Nenhuma mudança de comportamento — só classes Tailwind (hex → tokens da paleta), o padrão de cartão da Ficha (`rounded-xl border border-n-weak bg-n-solid-1 shadow-sm`) e `font-cormorant` onde falta. Backend: 3 consertos pontuais (mailer/portal Fraunces, tradução FICHA.en, `includes` no index de reuniões) + 1 fix visual de lógica (EsteiraEtapas × lead perdido).

**Tech Stack:** Vue 3 + Tailwind tokens, ERB (mailer/portal), Rails controller, vitest, RSpec (CI).

**Spec:** `docs/superpowers/specs/2026-08-14-redesign-ux-copiloto-design.md` (Onda E :84-85) + padrão de referência: `pages/Dossie.vue:237,352,397` e `LeadPanelBody.vue:124` (`CARD`).

## Global Constraints

- **Zero mudança de comportamento** (exceto o fix do EsteiraEtapas, que é correção visual de lógica). Nenhuma chave i18n nova — **NÃO tocar em `ramon.json`** (zona quente de conflito com a Onda D em CI).
- **TvBoard FICA FORA** (ruling: spec não o lista; página standalone de TV com visual escuro proposital — hex força o visual em qualquer tema, coerente pra parede do escritório). NÃO tocar em `pages/TvBoard.vue`.
- Hex que são DADO ficam: `helpers/leadBoards.js`, `helpers/stage.js` DEFAULT_STAGE_COLOR, swatches do `StageHeaderMenu.vue`, fallbacks inline-style de `BulkActionsBar.vue:139`/`SavedViews.vue:231`, `TvBoard DOT_COLORS`.
- Tokens de destino (paleta): primário `bg-n-iris-9`/hover `-10`, acento texto `text-n-iris-11`, tint `bg-n-iris-3`, cartão `bg-n-solid-1 border-n-weak shadow-sm`, trilhos `bg-n-alpha-1/2`, estados `n-teal-*`/`n-amber-*`/`n-ruby-*` (3 tint / 9 sólido / 11 texto), texto `text-n-slate-10/11/12`.
- Gradientes bronze → sólido `bg-n-iris-9` (o gradiente era truque do tema escuro). Sombras pretas calibradas (`shadow-[0_8px_28px_rgba(0,0,0,0.4)]` etc.) → `shadow-sm`.
- `kbd` `border-white/25 bg-white/10` DENTRO de botão `bg-n-iris-9` sólido é legítimo — manter (`Esteira.vue:512,526`).
- Front: `TZ=UTC ./node_modules/.bin/vitest --no-watch <path>`; eslint por arquivo; specs EXTENDIDOS nunca recriados; grep antes de criar spec. Sem Ruby local (CI valida RSpec). Conventional commit; sem `--no-verify`.
- **Paralelismo:** Onda D (PR #128) está em CI — esta onda NÃO toca nenhum arquivo da D (conferido: interseção vazia; nem `ramon.json`, nem `LeadPanelBody.vue`, nem `RamonEvent.vue`).

---

### Task 1: Consertar hardcodes dark no tema claro (Esteira, Cockpit, componentes)

**Files (Modify):**
- `app/javascript/dashboard/routes/dashboard/ramon/pages/Esteira.vue` (:289, :383, :433, :534)
- `app/javascript/dashboard/routes/dashboard/ramon/pages/CommandCenter.vue` (:393, :396, :516, :528, :554, :568, :576)
- `.../components/command/NightCopilot.vue` (:41, :156, :195)
- `.../components/command/AgendaToday.vue` (:47) **+ o spec `components/command/specs/AgendaToday.spec.js` (:47, :50) que assere a classe literal `bg-\[\#c9a97c\]\/\[\.12\]` — atualizar o assert pro token novo**
- `.../components/command/TeamWeek.vue` (:48)
- `.../components/command/LossesByThesis.vue` (:52-55)
- `.../components/lead/LeadNotes.vue` (:74)
- `.../components/lead/LeadZapsignCard.vue` (:78)

**Interfaces:** nenhuma — classes CSS apenas.

- [ ] **Step 1: Aplicar as trocas, arquivo a arquivo (tabela é o contrato):**

| Arquivo:linha | De | Para |
|---|---|---|
| Esteira.vue:289 | `bg-gradient-to-r from-[#8a5c33] to-[#c9a97c]` | `bg-n-iris-9` |
| Esteira.vue:383 | `border border-[#c9a97c]/25 bg-gradient-to-br from-n-solid-3 to-n-surface-1 shadow-[0_8px_28px_rgba(0,0,0,0.4)]` | `border border-n-weak bg-n-solid-1 shadow-sm` |
| Esteira.vue:433 | `border-[#c9a97c]/10` | `border-n-weak` |
| Esteira.vue:534 | `border-[#c9a97c]/20` | `border-n-weak` |
| CommandCenter.vue:393 | `bg-[#c9a97c]/[.15]` | `bg-n-alpha-2` |
| CommandCenter.vue:396 | `from-[#8a5c33] to-[#c9a97c]` (gradiente) | `bg-n-iris-9` |
| CommandCenter.vue:516 | `border border-[#c9a97c]/[.28] bg-gradient-to-br from-[#33302c] to-[#2e2b27] shadow-[0_4px_16px_rgba(0,0,0,0.3)]` | `border border-n-weak bg-n-solid-1 shadow-sm` |
| CommandCenter.vue:528 | `bg-[#c9a97c]/[.14] … border-[#c9a97c]/[.25]` | `bg-n-iris-3 border-n-weak` (manter os `text-*` que já forem token) |
| CommandCenter.vue:554 | `border-t border-[#c9a97c]/[.12]` | `border-t border-n-weak` |
| CommandCenter.vue:568/:576 | `border-[#c9a97c]/[.2]` | `border-n-weak` |
| NightCopilot.vue:41 | `bg-[#c9a97c]/[.16]` | `bg-n-iris-3` |
| NightCopilot.vue:156 | `bg-gradient-to-br from-[#463528] to-[#8a5c33]` | `bg-n-iris-9` |
| NightCopilot.vue:195 | `border-[#c9a97c]/[.12]` | `border-n-weak` |
| AgendaToday.vue:47 | `bg-[#c9a97c]/[.12]` | `bg-n-iris-3` |
| TeamWeek.vue:48 | `bg-[#463528]` | `bg-n-iris-3` |
| LossesByThesis.vue:52 | `bg-[#e54666]` | `bg-n-ruby-9` |
| LossesByThesis.vue:53 | `bg-[#e54666]/[.55]` | `bg-n-ruby-7` |
| LossesByThesis.vue:54 | `bg-[#e54666]/[.30] text-[#ffd2e1]` | `bg-n-ruby-5 text-n-ruby-11` |
| LossesByThesis.vue:55 | `bg-[#9399b0]/[.18]` | `bg-n-alpha-2` |
| LeadNotes.vue:74 | `border-l-2 border-[#c9a97c]/[.3]` | `border-l-2 border-n-iris-9/40` |
| LeadZapsignCard.vue:78 | `bg-gradient-to-br from-[#332e28] to-[#2e2b27] border border-n-iris-11/30` | `bg-n-solid-1 border border-n-weak` |

Ao trocar, LER a linha em volta: se o elemento tinha `text-*` hex na mesma classe, trocar junto pela coluna de tokens das Global Constraints. Conferir com grep no fim: `grep -rEn "\[#[0-9a-fA-F]{6}" app/javascript/dashboard/routes/dashboard/ramon --include="*.vue" | grep -v TvBoard` deve devolver só os casos-DADO listados (BulkActionsBar/SavedViews inline-style) e os kbd legítimos.

- [ ] **Step 2: Atualizar o assert literal do `AgendaToday.spec.js` (:47,:50) pra classe token nova; rodar:**

```bash
TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/ramon
```

Esperado: tudo verde (só classes mudaram; nenhum outro spec assere as classes trocadas — o implementer confirma com grep das classes antigas em `--include="*.spec.js"`).

- [ ] **Step 3: eslint nos arquivos tocados + commit**

```bash
git add -A app/javascript
git commit -m "fix(ramon): tokens da paleta no lugar de hex dark na esteira, cockpit e componentes"
```

---

### Task 2: Padrão de cartão + Fraunces nas telas da spec (Funil, Pós-venda, Reuniões, Relatórios, Cálculos)

**Files (Modify):**
- `.../components/kanban/LeadCard.vue` (:260)
- `.../pages/PosVenda.vue` (:103, :153, :67)
- `.../pages/Reunioes.vue` (:103 wrapper da lista)
- `.../components/reunioes/ReuniaoDetalhe.vue` (:69, :72, :112, :123, :130)
- `.../components/reunioes/ReuniaoRecorder.vue` (:130, :153, :178, :195)
- `.../pages/Relatorios.vue` (:42, :49-54)
- `.../pages/Calculos.vue` (:376)

**Interfaces:** nenhuma — visual apenas. `RamonPageHeader` já existe (`components/RamonPageHeader.vue`, título com `font-cormorant`).

- [ ] **Step 1: Aplicar por tela (deltas mínimos — ponytail):**

1. **Funil/LeadCard** (:260): `rounded-[10px] bg-n-solid-2` → `rounded-xl bg-n-solid-1 shadow-sm` (resto igual — o hover `hover:border-n-iris-8` fica).
2. **Pós-venda**: linhas :103 e :153 `bg-n-solid-2` → `bg-n-solid-1 shadow-sm` (mantém o `border-l-[3px]` de acento); skeleton :67 fica.
3. **Reuniões (lista)** :103: envolver o `<ul>` num cartão `rounded-xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden` (o `divide-y` interno fica).
4. **ReuniaoDetalhe**: título :72 ganha `font-cormorant text-2xl` (mantendo `font-semibold text-n-slate-12`); as `<section>` de ata (:112), áudio (:123) e transcrição (:130) viram cartões `rounded-xl border border-n-weak bg-n-solid-1 shadow-sm p-4` (conteúdo interno intocado).
5. **ReuniaoRecorder**: :130 `rounded-lg … bg-n-solid-2` → `rounded-xl … bg-n-solid-1 shadow-sm`; botões :153/:178/:195 `bg-n-brand` → `bg-n-iris-9` (+hover `hover:bg-n-iris-10` se houver hover de brand).
6. **Relatórios**: retry :42 `text-n-brand` → `text-n-iris-11`; iframe :49-54 ganha wrapper `rounded-xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden` (iframe interno mantém `border-0 rounded-lg` → simplificar pra `border-0 w-full flex-1`).
7. **Cálculos**: histórico :376 `bg-n-alpha-1` → `bg-n-solid-1 shadow-sm` (mantém `rounded-xl border border-n-weak`).

- [ ] **Step 2: Grep de regressão de specs** — as classes alteradas não aparecem em asserts (`grep -n "solid-2\|n-brand\|rounded-\[10px\]" app/javascript --include="*.spec.js" -r` nos componentes tocados); rodar a suíte ramon + qualquer spec de reuniões/kanban:

```bash
TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/ramon
```

- [ ] **Step 3: eslint + commit**

```bash
git add -A app/javascript
git commit -m "feat(ramon): padrao de cartao material claro no funil, pos-venda, reunioes, relatorios e calculos"
```

---

### Task 3: Minors da Onda A (mailer/portal, FICHA.en, N+1, esteira × perdido)

**Files:**
- Modify: `app/views/layouts/ramon_portal.html.erb` (:11, :21, :28, :32)
- Modify: `app/views/mailers/administrator_notifications/ramon_digest_mailer/daily_digest.html.erb` (:15, :24, :28, :32, :36)
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json` (:669-683 — bloco FICHA **apenas**; NÃO tocar em mais nada do arquivo — zona de conflito com a Onda D)
- Modify: `app/controllers/api/v1/accounts/ramon_reunioes_controller.rb` (:12)
- Modify: `.../components/ficha/EsteiraEtapas.vue` + EXTENDER `.../ficha/specs/EsteiraEtapas.spec.js` (fixture já tem os flags :17,:26)

**Interfaces:** nenhuma externa.

- [ ] **Step 1: Fraunces no portal e no digest**

`ramon_portal.html.erb:11`: trocar o `<link>` do Google Fonts de `Cormorant+Garamond:...` por `Fraunces:opsz,wght@9..144,500;9..144,600` (formato igual ao do mockup: `https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,500;9..144,600&family=Manrope:wght@400;500;600;700;800&display=swap` — manter as outras famílias que o link atual carrega). Em `:21` (`.serif`), `:28` (`.brand-name`), `:32` (`h1`): `'Cormorant Garamond'` → `'Fraunces'`. No `daily_digest.html.erb` (5 pontos `:15,:24,:28,:32,:36`): `font-family:'Cormorant Garamond',Georgia,serif` → `font-family:'Fraunces',Georgia,serif` (e-mail cai no fallback Georgia onde Fraunces não carrega — aceitável e igual ao comportamento atual).

- [ ] **Step 2: Traduzir o bloco FICHA do `en/ramon.json`**

```json
"FICHA": {
  "TITLE": "Client File",
  "PROBABILITY": "probability",
  "ESTIMATED": "estimated",
  "OPEN_CONVERSATION": "Open conversation",
  "NEXT_TITLE": "Next step",
  "NEXT_EMPTY": "No open task — set the next step.",
  "DOCS_TITLE": "Documents",
  "CALCULOS_TITLE": "Calculations",
  "CALCULOS_EMPTY": "No calculations yet.",
  "REUNIOES_TITLE": "Meetings",
  "REUNIOES_EMPTY": "No meetings yet. Record one and the minutes will appear here.",
  "RECORD_MEETING": "Record meeting",
  "OPEN_FULL": "Open full file"
}
```

- [ ] **Step 3: N+1 do index de reuniões**

`ramon_reunioes_controller.rb:12`: `Current.account.reunioes.recentes.limit(LIMIT)` → `Current.account.reunioes.includes(:user, :lead).recentes.limit(LIMIT)`. Estender o request/controller spec existente (grep `grep -rl "ramon_reunioes" spec/`) só se ele já testar o index — sem spec novo de N+1 (YAGNI; o `linha` :79,:81 é a prova de uso).

- [ ] **Step 4: EsteiraEtapas × lead perdido (fix visual de lógica)**

Em `EsteiraEtapas.vue:11-19`, usar os flags que o backend já manda:

```js
const currentIndex = computed(() =>
  props.stages.findIndex(stage => stage.current)
);
const currentIsLost = computed(
  () => props.stages[currentIndex.value]?.is_lost === true
);
```

E no cálculo por item: `done` vira `currentIndex >= 0 && index < currentIndex && !(currentIsLost && stage.is_won)` — ou seja, com lead PERDIDO a etapa de ganho nunca aparece "concluída". Além disso, quando a etapa ATUAL é `is_lost`, o selo atual usa tom ruby: no template, a classe do selo/nome da etapa atual troca `bg-n-iris-9 border-n-iris-9` por `bg-n-ruby-9 border-n-ruby-9` quando `currentIsLost` (mesma estrutura, só cor). Testes novos no spec existente: (a) lead em etapa perdida → item `is_won` NÃO tem check/done; (b) etapa atual perdida → selo com classe ruby. Seguir o estilo dos 4 testes existentes.

- [ ] **Step 5: vitest da ficha + eslint + commit**

```bash
TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/ramon/components/ficha
git add -A app/views app/controllers app/javascript
git commit -m "fix(ramon): fraunces no portal e digest, ficha.en traduzida, includes nas reunioes e esteira honesta com lead perdido"
```

---

## Self-Review (feito na escrita)

- **Cobertura:** spec Onda E (5 telas) → Task 2; hardcodes que quebram o tema claro → Task 1; minors Onda A (a-e) → Task 3 (o item "TvBoard×Fraunces" já está resolvido de graça — Fraunces ativo via chave tailwind; TvBoard fora por ruling registrado).
- **Zero i18n novo; `en/ramon.json` só no bloco FICHA** (linhas 669-683, longe dos hunks da Onda D ~889/~1177) — conflito improvável; se houver, resolve por bloco.
- **Interseção com Onda D: vazia** (nenhum arquivo em comum nas 3 tasks — conferido contra o diffstat da D).
- **Specs afetados mapeados:** AgendaToday.spec (assert literal — Task 1 atualiza), EsteiraEtapas.spec (Task 3 estende). Grep de classes antigas em specs é step explícito nas Tasks 1 e 2.
- **Sem placeholder:** todas as trocas têm linha e valor exatos; código do EsteiraEtapas e do JSON completos.
