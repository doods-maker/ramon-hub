# Inteligência A2 — Telas que passam a dizer a verdade — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A área Inteligência passa a mostrar o que existe de verdade: a tela **Assistentes** vira a lista real dos 2 assistentes (com caixas conectadas e modo das conversas), **Ferramentas** vira o catálogo das 42 ferramentas com uso real, e nasce a **Visão geral** como entrada da área (absorvendo o Vigia).

**Architecture:** Três endpoints de leitura: `GET captain/assistants/stats` e `GET captain/ferramentas` no overlay `enterprise/` (só tocam Captain), e `GET ramon_inteligencia` em `app/` (views `bi_ia_*`, `copilot_suggestions`, `agente_execucoes` — não toca `Captain::*`, roda no CI FOSS). Um campo novo `sistema` no `config/agents/tools.yml`. Três telas Vue no kit `ui.js` (`assistants/Index.vue` reescrita, `pages/Ferramentas.vue` e `pages/VisaoGeral.vue` novas); o `Watchdog.vue` vira o bloco `VigiaBloco.vue`. A Visão geral reaproveita `ramon_watchdog`, `captain_tool_runs` e `captain/assistants/stats` em vez de recalcular. Aprovação do Eduardo por prints antes/depois (story + harness Vite + Chrome headless, o mesmo do A1).

**Tech Stack:** Rails 7 (fork Chatwoot v4.15.1, overlay `enterprise/`), RSpec (só no CI), Vue 3 `<script setup>`, vitest, Tailwind, vue-i18n.

**Spec:** `C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-05-inteligencia-tela-a-tela.md` — "Resumo das ⭐ → 2. Telas que passam a dizer a verdade (M)": I-AS1, I-AS2, I-AS3/I-CX1, I-FE1, I-FE2, I-VG1, I-VG2, I-VG3 (+ seção 0 "Menu", seções 2, 4, 8, 10 e 12).

## Global Constraints

- Worktree `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-intel-a2`, branch `feat/inteligencia-a2`, **empilhada sobre `feat/inteligencia-a1-faxina` (PR #198, ainda não mergeado)**, base = `0b0c299198`. Todo `arquivo:linha` deste plano é desse commit; quando uma task mexe num arquivo que outra já mexeu, use o trecho citado como âncora. O PR do A2 abre com base `feat/inteligencia-a1-faxina` (ou `ramon`, se o #198 já tiver entrado).
- **Captain é enterprise.** O CI FOSS apaga `enterprise/` e `spec/enterprise/` (`.github/workflows/run_foss_spec.yml:103-106`). Endpoint só de Captain → em `enterprise/`. Código em `app/` não pode tocar `Captain::Assistant`, `Captain::Scenario`, `Captain::AssistantResponse`, `CaptainInbox`, `Ramon::CopilotoModo` (é `enterprise/lib`) sem guarda `ChatwootApp.enterprise?`; spec em `spec/` que use essas classes leva `if: ChatwootApp.enterprise?`. (`Captain::ToolRun` mora em `app/models` — pode.) **Specs em `spec/enterprise/` não rodam no CI** — são escritas mesmo assim (padrão do repo); a prova delas é o smoke pós-deploy (fim do plano). O CI roda RuboCop em tudo (inclusive `enterprise/`).
- RuboCop do repo: linha ≤ 150, `Metrics/MethodLength` ≤ 19, `Metrics/AbcSize` ≤ 26, `Style/HashSyntax EnforcedShorthandSyntax: never` (escrever `chave: chave`, nunca `chave:`), heredoc de SQL com `.squish`.
- Permissão: Visão geral, Ferramentas e Assistentes = **admin + agente** (mesmo padrão do Vigia/Execuções: `authorize(:ramon_dashboard, :show?)`; o `stats` usa `Captain::AssistantPolicy#stats?`, que já existe e é `true`).
- Visual: kit `app/javascript/dashboard/routes/dashboard/ramon/helpers/ui.js` (`CARTAO`, `CARTAO_STATUS`, `FILETE`, `SECAO`, `TITULO`, `CHIP`, `TOM`, `AVISO`, `LINHA`); dentro de cartão não há cartão (vira `SECAO`); fundos coloridos SEMPRE translúcidos; destaque azul `n-blue`. Tailwind only — sem CSS, sem `style` (as barras usam `<progress>` nativo pintado com variantes Tailwind). Claro e escuro.
- Cores de nível de ferramenta: só via `NIVEL_TOM` de `ramon/helpers/ferramentas.js` (azul consulta · âmbar sugestão · teal rascunho · neutro interna). A classificação mora no `tools.yml` (`nivel` e, a partir do A2, `sistema`), nunca numa lista solta no front.
- i18n: toda chave criada/apagada em **en E pt_BR** (`app/javascript/dashboard/i18n/locale/{en,pt_BR}/{settings,ramon}.json`). **Nunca** `@`, `{`, `}`, `|` crus no texto (quebra o vue-i18n em produção) — `{n}` só como parâmetro; plural sem `|` (frases do tipo "Skills ativas: {n}"). Nomes da área: "Ferramentas", "Testar", "Vigia", "Skills" — nunca "Cenário(s)".
- Vue: Composition API `<script setup>`, eventos camelCase, nada de texto cru no template (pontuação solta como " · " já existente pode ficar; texto novo vai por chave).
- Sem Ruby local: specs Ruby e RuboCop são validados no CI. JS local: `npx eslint <arquivos>` e `npx vitest run --config tmp/vitest.local.config.ts <spec>` (Task 1 cria o config).
- Commits: Conventional Commits, mensagem em pt-BR, sem citar Claude no assunto; corpo termina com
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>` e `Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv`.
- **Menu final:** Visão geral · (Automações — vem do PR da B2, **não criar**) · Assistentes · Skills · Ferramentas · FAQs · Documentos · Testar · Execuções · Configurações. Vigia e Caixas de Entrada saem do menu; `/captain/watchdog` redireciona para a Visão geral; `/captain` abre a Visão geral.
- **Não fazer push nem abrir PR** antes do "aprovado" do Eduardo nos prints (Task 8). Nenhuma migração, nenhum seed nesta entrega.

## Review Focus

- **Conta sem rascunho revisado nem conversa medida** (realidade de hoje: o Atendimento só está na caixa Teste) → Visão geral abre sem erro: régua "0 de 20", "Ainda não há rascunho revisado.", 1ª resposta "sem dados", nenhuma divisão por zero (`sem_correcao_pct: null`). Teste: Task 5, `ramon_inteligencia_controller_spec.rb` ("conta vazia").
- **Assistente sem caixa conectada** (Copiloto) → cartão "Fala com a equipe", sem seção de modo, "Nenhuma caixa conectada", `conversas_por_modo: {}`. Teste: Task 4, `assistants_controller_spec.rb` (stats, expectativa do Copiloto).
- **Conversa sem `copiloto_modo` (ou com valor inválido)** → conta no modo padrão do servidor (`RAMON_COPILOTO_MODO_DEFAULT`), como `Ramon::CopilotoModo.of`; conversa resolvida não conta. Teste: Task 4, stats com `with_modified_env RAMON_COPILOTO_MODO_DEFAULT: 'piloto_limitado'`.
- **Ferramenta nova no `tools.yml` sem `sistema`** (ou com sistema sem seção na tela) → ela sumiria do catálogo. Teste: Task 2, `ferramentas.spec.js` (lê o yml; roda no CI de front) + `captain_tools_helpers_spec.rb`.
- **"Hoje" do agente Claude à noite** (servidor em UTC; às 22h em Brasília o "hoje" UTC começou às 21h e perderia os pedidos da manhã) → conta pelo dia de Brasília. Teste: Task 5, spec com `travel_to` 22:00 BRT.

## Divergências conscientes do backlog (registradas)

1. **I-VG2 — a D7 já foi fechada (17/08, `RAMON_COPILOTO_MODO_DEFAULT=piloto_limitado` em produção; memória `inteligencia-area-completa.md`).** O bloco "Rumo ao piloto limitado" ficaria falso. Ele vira condicional pelo modo padrão do servidor (`modoDefault()`): com padrão `piloto_*` o título é **"Piloto com limites em vigor"** e a régua (X de 20 conversas revisadas · Y% sem correção) segue como acompanhamento de qualidade, com uma linha explicando; com padrão `rascunho`/`manual`, o título é o do backlog. → **decisão do Eduardo** (manter assim ou tirar o bloco).
2. **I-AS3/I-CX1 — Caixas dentro do cartão:** o cartão lista as caixas conectadas e tem o botão "Ver e conectar caixas", que abre a tela de caixas que já existe (com o aviso do A1/I-CX2 e o desconectar). A tela sai do menu, ganha "voltar" para Assistentes, mas a rota continua. Motivo: conectar/desconectar já funciona lá com diálogo e aviso; duplicar dentro do cartão é código repetido.
3. **"Pra quem fala (lead/equipe)"** é derivado de ter caixa conectada (com caixa = lead; sem caixa = só pela tela Testar = equipe). Não há campo pra isso, e um campo novo em `config` seria apagado ao salvar Configurações (mesmo bug da marca `ramon_modo_rascunho`, backlog §2).
4. **I-AS2 — "quantas conversas em cada modo hoje"** = conversas **abertas** nas caixas do assistente, pelo modo efetivo (atributo da conversa ou o padrão). Só leitura.
5. **I-FE1 — "sistema que toca"** não existia: entra o campo `sistema` no `tools.yml` (7 valores: funil, advbox, motor, zapsign, calcom, faq, conversa). O catálogo é agrupado por sistema (sem filtro/busca — 42 itens cabem).
6. **I-FE4 (não ⭐) / "HTTP vira Avançado se for trivial":** vira um aviso "Avançado" no fim do catálogo, só para admin, com botão que abre a tela de ferramentas HTTP que já existe. Não é aba.
7. **I-VG1 — tempo até a 1ª resposta usa mediana**, não média (uma conversa que chega de madrugada distorceria a média).
8. **I-VG1 — Transferências:** total de 30 dias + atalho para as 5 conversas mais novas (não a lista inteira).
9. **I-VG1 — Agente Claude:** "hoje" no fuso de Brasília; o teto 30 é constante na tela (o teto real é do runner na VPS — a tela só desenha a barra). Sem link (a aba "Agente Claude" em Execuções é I-EX4, pacote 3).
10. **I-VG3 — Aprovações:** sugestões agrupadas por tipo (ação em sistema — ZapSign, AdvBox, reunião, perdido — ou rascunho/mudar etapa/alerta); o atalho abre o Centro de Comando sem filtro (o filtro é I-WD2, pacote 3). FAQs pendentes levam às pendentes do assistente que tem mais.
11. **I-WD1 — bloco Vigia:** os contadores "Sugestões pendentes" e "Execuções 24h" saem do bloco (já estão em Aprovações e Ferramentas, na mesma tela); a lista de parados mostra 5 com "Ver todos (N)".
12. **Base de conhecimento** e as FAQs pendentes vêm do `captain/assistants/stats` (mesmo endpoint da tela Assistentes) — o endpoint da Visão geral fica sem `Captain::*`.
13. A rota `captain_assistants_create_index` (`/captain/assistants`) mantém o nome, agora com a lista real (renomear espalharia mudança por `AssistantsIndexPage.vue` sem ganho).

## Decisões que exigem o Eduardo

1. Bloco D7 (divergência 1): "Piloto com limites em vigor" como acompanhamento — ou tirar o bloco.
2. Visão geral visível para **agentes** (não só admin) — segui o padrão do Vigia/Execuções.
3. Prints antes/depois (Task 8) — "aprovado" libera push + PR.

## Mapa de arquivos

| Arquivo | Task | O que muda |
|---|---|---|
| `tmp/intel-harness/*` (copiado do wt-intel-a, não versionado), `tmp/vitest.local.config.ts` | 1, 8 | harness (porta 6195, plugin yaml), `shots-a2.sh`, `comparar-a2.mjs` |
| `config/agents/tools.yml` | 2 | campo `sistema` nas 42 ferramentas |
| `enterprise/app/models/concerns/captain_tools_helpers.rb:14,51-57` | 2 | `sistema` no catálogo |
| `app/javascript/dashboard/routes/dashboard/ramon/helpers/ferramentas.js` + `helpers/specs/ferramentas.spec.js` | 2 | `SISTEMAS`, `agruparPorSistema` |
| `spec/enterprise/models/concerns/captain_tools_helpers_spec.rb:107-131` | 2 | spec do `sistema` |
| `enterprise/app/controllers/api/v1/accounts/captain/ferramentas_controller.rb` (novo) + `spec/enterprise/controllers/api/v1/accounts/captain/ferramentas_controller_spec.rb` (novo) | 3 | catálogo com skills e execuções |
| `config/routes.rb:64-86` | 3, 4 | `captain/ferramentas`, `captain/assistants/stats` |
| `app/javascript/dashboard/api/captain/ferramentas.js` (novo) | 3 | API |
| `app/javascript/dashboard/routes/dashboard/captain/pages/Ferramentas.vue` (novo) | 3 | tela catálogo |
| `app/javascript/dashboard/routes/dashboard/captain/captain.routes.js:116-152` | 3, 6 | rotas novas + redirects |
| `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json` (`CAPTAIN_RAMON`) | 3, 4, 6 | textos |
| `app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue` | 3, 4, 6 | fixtures e variantes |
| `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb:41-46` + `spec/enterprise/controllers/api/v1/accounts/captain/assistants_controller_spec.rb` | 4 | ação `stats` |
| `app/javascript/dashboard/api/captain/assistant.js` | 4 | `stats()` |
| `app/javascript/dashboard/routes/dashboard/captain/assistants/Index.vue` (reescrita) | 4 | cartões reais |
| `app/javascript/dashboard/routes/dashboard/captain/assistants/inboxes/Index.vue:64-72` | 4 | "voltar" para Assistentes |
| `app/controllers/api/v1/accounts/ramon_inteligencia_controller.rb` (novo) + `spec/controllers/api/v1/accounts/ramon_inteligencia_controller_spec.rb` (novo) | 5 | endpoint da Visão geral |
| `config/routes.rb:337` | 5 | `resource :ramon_inteligencia` |
| `app/javascript/dashboard/api/ramonInteligencia.js` (novo) | 5 | API |
| `app/javascript/dashboard/routes/dashboard/captain/pages/VisaoGeral.vue` (novo) | 6 | tela |
| `app/javascript/dashboard/routes/dashboard/captain/pages/Watchdog.vue` → `VigiaBloco.vue` (`git mv`) | 6 | vira bloco |
| `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:444-534` | 7 | menu final |
| `app/javascript/dashboard/i18n/locale/{en,pt_BR}/settings.json` (`SIDEBAR`) | 7 | `CAPTAIN_VISAO_GERAL`; sai `CAPTAIN_WATCHDOG`, `CAPTAIN_INBOXES` |

### Verificação de i18n usada em várias tasks ("paridade")

Rodar na raiz do worktree (Bash). Esperado: 3 linhas, todas com `[]` e `[]`.

```bash
node -e "
const f=p=>JSON.parse(require('fs').readFileSync(p,'utf8'));
const keys=(o,p='')=>Object.entries(o).flatMap(([k,v])=>v&&typeof v==='object'?keys(v,p+k+'.'):[p+k]);
for (const arq of ['integrations','settings','ramon']) {
  const en=new Set(keys(f('app/javascript/dashboard/i18n/locale/en/'+arq+'.json')));
  const pt=new Set(keys(f('app/javascript/dashboard/i18n/locale/pt_BR/'+arq+'.json')));
  const so=(a,b)=>[...a].filter(k=>!b.has(k)&&/CAPTAIN/.test(k));
  console.log(arq,'so en:',JSON.stringify(so(en,pt)),'so pt_BR:',JSON.stringify(so(pt,en)));
}"
```

E a compilação das mensagens pelo mesmo compilador do vue-i18n (pega `@`, `{`, `}` crus, que quebram o build de produção) + caça a `|` (esperado: nenhuma linha impressa):

```bash
C=$(ls -d node_modules/.pnpm/@intlify+message-compiler@*/node_modules/@intlify/message-compiler | head -1)
node -e "
const {baseCompile}=require('./$C');
const f=p=>JSON.parse(require('fs').readFileSync(p,'utf8'));
const vals=(o,p='')=>Object.entries(o).flatMap(([k,v])=>v&&typeof v==='object'?vals(v,p+k+'.'):[[p+k,v]]);
for (const loc of ['en','pt_BR']) {
  const all=[...vals(f('app/javascript/dashboard/i18n/locale/'+loc+'/ramon.json').CAPTAIN_RAMON,'CAPTAIN_RAMON.'),
             ...vals(f('app/javascript/dashboard/i18n/locale/'+loc+'/settings.json').SIDEBAR,'SIDEBAR.')];
  for (const [k,v] of all) {
    try { baseCompile(v,{onError:e=>{throw e}}); } catch(e) { console.log(loc,k,'->',e.message); }
    if (v.includes('|')) console.log(loc,k,'-> tem |');
  }
}"
```

(Conferido na base: `baseCompile('a @ b')` acusa "Invalid linked format"; `Conversa #{id} · {n}%` compila.)

---

### Task 1: Harness + prints "antes"

Roda **antes de qualquer mudança de código** (o "antes" é o código da base).

**Files:**
- Create (não versionado — `tmp/` está no `.gitignore`): `tmp/intel-harness/` (cópia do wt-intel-a), `tmp/intel-harness/shots-a2.sh`, `tmp/vitest.local.config.ts`

**Interfaces:**
- Produces: harness em `http://localhost:6195/?variant=<Título>&tema=claro|escuro`, com plugin yaml (a story importa `config/agents/tools.yml` a partir da Task 3); `sh tmp/intel-harness/shots-a2.sh antes|depois` grava PNGs em `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-05-inteligencia-a2\`.

- [ ] **Step 1: Copiar harness e config do vitest** (Bash):

```bash
cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-intel-a2
mkdir -p tmp
cp -r ../ramon-hub-wt-intel-a/tmp/intel-harness tmp/
cp ../ramon-hub-wt-intel-a/tmp/vitest.local.config.ts tmp/
rm -f tmp/intel-harness/vite.log
ls tmp/intel-harness
```

Expected: `BackButtonStub.vue comparar.mjs ConversationBoxStub.vue index.html main.js shots.sh vite.config.mts`.

- [ ] **Step 2: Porta 6195 + plugin yaml no `tmp/intel-harness/vite.config.mts`** (Edit). Trocar

```ts
import vue from '@vitejs/plugin-vue';
```

por

```ts
import vue from '@vitejs/plugin-vue';
import yaml from '@rollup/plugin-yaml';
```

trocar `plugins: [vue(vueOptions)],` por `plugins: [vue(vueOptions), yaml()],` e `server: { port: 6194, fs: { strict: false } },` por `server: { port: 6195, fs: { strict: false } },`.

- [ ] **Step 3: Criar `tmp/intel-harness/shots-a2.sh`** (com a ferramenta Write — heredoc no Bash deste Windows come barra invertida):

```sh
#!/bin/sh
# uso: sh tmp/intel-harness/shots-a2.sh antes|depois
# PNGs em comercial/docs/mockups/2026-10-05-inteligencia-a2
fase=$1
out="C:/Users/dudsl/RAdvogados/comercial/docs/mockups/2026-10-05-inteligencia-a2"
mkdir -p "$out"
chrome="/c/Program Files/Google/Chrome/Application/chrome.exe"
if [ "$fase" = "antes" ]; then
  telas="Vigia:vigia:1440,1000 Assistentes:assistentes:1440,900 Ferramentas:ferramentas:1440,900 Caixas:caixas:1440,900"
else
  telas="Visao%20geral:visao-geral:1440,1900 Visao%20geral%20rascunho:visao-geral-rascunho:1440,1900 Assistentes:assistentes:1440,1300 Ferramentas:ferramentas:1440,4200 Ferramentas%20HTTP:ferramentas-http:1440,900 Caixas:caixas:1440,900"
fi
for v in $telas; do
  q=$(echo "$v" | cut -d: -f1); arq=$(echo "$v" | cut -d: -f2); tam=$(echo "$v" | cut -d: -f3)
  for tema in claro escuro; do
    "$chrome" --headless=new --disable-gpu --hide-scrollbars --window-size=$tam \
      --virtual-time-budget=15000 --screenshot="$out/$fase-$tema-$arq.png" \
      "http://localhost:6195/?variant=$q&tema=$tema" >/dev/null 2>&1 &
  done
  wait
done
ls "$out" | grep "^$fase"
```

- [ ] **Step 4: Subir o harness** (Bash, `run_in_background: true`): `npx vite --config tmp/intel-harness/vite.config.mts`. Conferir: `curl -s -o /dev/null -w "%{http_code}" http://localhost:6195/` → `200`.

- [ ] **Step 5: Prints "antes"** — `sh tmp/intel-harness/shots-a2.sh antes`. Expected: 8 arquivos `antes-{claro,escuro}-{vigia,assistentes,ferramentas,caixas}.png`. Abrir com Read `antes-claro-vigia.png` e `antes-escuro-assistentes.png`: tela desenhada, fonte Geist, nada de página branca. Se vier em branco, conferir o console do Vite (log do processo em background) antes de seguir.

- [ ] **Step 6: Sem commit** (nada versionado mudou). Registrar no relatório da task o caminho dos PNGs.

---

### Task 2: Campo `sistema` no catálogo de ferramentas

**Files:**
- Modify: `config/agents/tools.yml` (cabeçalho :1-11 + uma linha `sistema:` em cada uma das 42 ferramentas)
- Modify: `enterprise/app/models/concerns/captain_tools_helpers.rb:14` (doc) e `:51-57` (hash)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/helpers/ferramentas.js`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/ferramentas.spec.js`, `spec/enterprise/models/concerns/captain_tools_helpers_spec.rb`

**Interfaces:**
- Produces: `Captain::Assistant.built_in_agent_tools` → cada hash ganha `sistema: String` (um de `funil advbox motor zapsign calcom faq conversa`). JS: `export const SISTEMAS: string[]` (ordem das seções da tela) e `export const agruparPorSistema(ferramentas: {sistema}[]) => { sistema: string, ferramentas: object[] }[]` (na ordem de `SISTEMAS`, sem grupo vazio).

- [ ] **Step 1: Escrever os testes JS que falham** — em `ferramentas.spec.js`, trocar a linha de import

```js
import { NIVEL_TOM, ferramentaInfo } from '../ferramentas';
```

por

```js
import {
  NIVEL_TOM,
  SISTEMAS,
  agruparPorSistema,
  ferramentaInfo,
} from '../ferramentas';
```

e acrescentar, antes do `});` final do `describe`:

```js
  it('toda ferramenta do tools.yml tem um sistema com seção na tela', () => {
    tools.forEach(tool => {
      expect(SISTEMAS).toContain(tool.sistema);
    });
  });

  it('toda ferramenta *_advbox mexe no AdvBox', () => {
    tools
      .filter(tool => tool.id.endsWith('_advbox'))
      .forEach(tool => {
        expect(tool.sistema).toBe('advbox');
      });
  });

  it('agrupa na ordem da tela e omite sistema sem ferramenta', () => {
    const grupos = agruparPorSistema([
      { id: 'nota', sistema: 'conversa' },
      { id: 'a_advbox', sistema: 'advbox' },
      { id: 'b_advbox', sistema: 'advbox' },
    ]);
    expect(grupos.map(grupo => grupo.sistema)).toEqual(['advbox', 'conversa']);
    expect(grupos[0].ferramentas.map(tool => tool.id)).toEqual([
      'a_advbox',
      'b_advbox',
    ]);
  });
```

- [ ] **Step 2: Rodar e ver falhar** — `npx vitest run --config tmp/vitest.local.config.ts app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/ferramentas.spec.js`. Expected: FAIL (`SISTEMAS` undefined / `agruparPorSistema is not a function`).

- [ ] **Step 3: Helper JS** — acrescentar ao fim de `ferramentas.js`:

```js
// Seções da tela Ferramentas, na ordem da tela (campo `sistema` do tools.yml).
export const SISTEMAS = [
  'funil',
  'advbox',
  'motor',
  'zapsign',
  'calcom',
  'faq',
  'conversa',
];

export const agruparPorSistema = ferramentas =>
  SISTEMAS.map(sistema => ({
    sistema,
    ferramentas: ferramentas.filter(tool => tool.sistema === sistema),
  })).filter(grupo => grupo.ferramentas.length);
```

- [ ] **Step 4: `sistema` no yml** — criar `tmp/add-sistema.mjs` com a ferramenta Write:

```js
// uso único: põe `sistema:` logo depois do `nivel:` de cada ferramenta.
import { readFileSync, writeFileSync } from 'node:fs';

const ARQ = 'config/agents/tools.yml';
const SISTEMA = {
  add_contact_note: 'conversa',
  add_private_note: 'conversa',
  update_priority: 'conversa',
  add_label_to_conversation: 'conversa',
  handoff: 'conversa',
  faq_lookup: 'faq',
  buscar_processo_advbox: 'advbox',
  consultar_dossie_advbox: 'advbox',
  calcular_beneficio: 'motor',
  checar_prescricao: 'funil',
  linha_da_vida: 'funil',
  documentacao_faltante: 'funil',
  preparar_contrato_zapsign: 'zapsign',
  preparar_caso_advbox: 'advbox',
  agendar_reuniao: 'funil',
  mover_etapa: 'funil',
  playbook_da_tese: 'funil',
  simular_honorario: 'funil',
  historico_do_contato: 'funil',
  triagem_da_lp: 'funil',
  link_agendamento: 'calcom',
  agenda_do_escritorio: 'advbox',
  funil_hoje: 'funil',
  publicacoes_advbox: 'advbox',
  registrar_qualificacao: 'funil',
  criar_tarefa_esteira: 'funil',
  solicitar_documento: 'funil',
  enviar_link_portal: 'funil',
  marcar_perdido: 'funil',
  processo_advbox: 'advbox',
  movimentacoes_advbox: 'advbox',
  historico_tarefas_advbox: 'advbox',
  ultimas_movimentacoes_advbox: 'advbox',
  tarefas_advbox: 'advbox',
  buscar_cliente_advbox: 'advbox',
  cliente_advbox: 'advbox',
  documentos_advbox: 'advbox',
  link_documento_advbox: 'advbox',
  configuracoes_advbox: 'advbox',
  criar_tarefa_advbox: 'advbox',
  criar_movimentacao_advbox: 'advbox',
  criar_cliente_advbox: 'advbox',
};

let id = null;
const saida = [];
for (const linha of readFileSync(ARQ, 'utf8').split('\n')) {
  const achou = linha.match(/^- id: (\S+)/);
  if (achou) id = achou[1];
  saida.push(linha);
  if (/^ {2}nivel: /.test(linha)) {
    if (!SISTEMA[id]) throw new Error(`sem sistema: ${id}`);
    saida.push(`  sistema: ${SISTEMA[id]}`);
  }
}
writeFileSync(ARQ, saida.join('\n'));
```

Rodar `node tmp/add-sistema.mjs` e conferir `grep -c "^  sistema:" config/agents/tools.yml` → `42`. (Se aparecer "sem sistema: X", uma ferramenta nova entrou depois deste plano: decidir o sistema pelo que a classe em `enterprise/lib/captain/tools/X_tool.rb` chama e acrescentar no mapa.)

- [ ] **Step 5: Cabeçalho do yml** — no comentário de topo do `tools.yml`, depois do bloco `# nivel: ...` (linha `#   rascunho (verde) = devolve texto pronto pro cliente; quem envia é o humano`), acrescentar:

```yaml
# sistema: em qual sistema a ferramenta mexe — define a seção na tela Ferramentas:
#   funil (casos do hub) · advbox · motor (cálculos) · zapsign · calcom · faq · conversa
```

- [ ] **Step 6: Rodar os testes JS** — mesmo comando do Step 2. Expected: PASS (7 testes).

- [ ] **Step 7: `sistema` no Ruby** — em `captain_tools_helpers.rb`, linha 14, trocar `# @return [Array<Hash>] Array of tool hashes with :id, :title, :description, :icon, :nivel` por `# @return [Array<Hash>] Array of tool hashes with :id, :title, :description, :icon, :nivel, :sistema`; no hash de `load_agent_tools` (:51-57), trocar

```ruby
            icon: tool_config['icon'],
            nivel: tool_config['nivel']
```

por

```ruby
            icon: tool_config['icon'],
            nivel: tool_config['nivel'],
            sistema: tool_config['sistema']
```

- [ ] **Step 8: Spec Ruby** — em `spec/enterprise/models/concerns/captain_tools_helpers_spec.rb`, depois do `describe 'nivel das ferramentas (config/agents/tools.yml)'` (fecha na linha 130), acrescentar dentro do describe principal:

```ruby
  describe 'sistema das ferramentas (config/agents/tools.yml)' do
    let(:ferramentas) { Captain::Assistant.built_in_agent_tools }

    it 'toda ferramenta diz em qual sistema mexe' do
      expect(ferramentas.pluck(:sistema).uniq).to match_array(%w[funil advbox motor zapsign calcom faq conversa])
    end

    it 'toda ferramenta *_advbox mexe no AdvBox' do
      advbox = ferramentas.select { |tool| tool[:id].end_with?('_advbox') }
      expect(advbox.pluck(:sistema).uniq).to eq(['advbox'])
    end
  end
```

- [ ] **Step 9: Lint** — `npx eslint app/javascript/dashboard/routes/dashboard/ramon/helpers/ferramentas.js app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/ferramentas.spec.js` → sem erro. Apagar `tmp/add-sistema.mjs`.

- [ ] **Step 10: Commit**

```bash
git add config/agents/tools.yml enterprise/app/models/concerns/captain_tools_helpers.rb \
  app/javascript/dashboard/routes/dashboard/ramon/helpers/ferramentas.js \
  app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/ferramentas.spec.js \
  spec/enterprise/models/concerns/captain_tools_helpers_spec.rb
git commit -m "feat(inteligencia): sistema de cada ferramenta no catálogo

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 3: Tela Ferramentas = catálogo das 42 (I-FE1, I-FE2)

**Files:**
- Create: `enterprise/app/controllers/api/v1/accounts/captain/ferramentas_controller.rb`
- Create: `spec/enterprise/controllers/api/v1/accounts/captain/ferramentas_controller_spec.rb`
- Modify: `config/routes.rb:76` (dentro de `namespace :captain`, depois de `resources :assistant_responses`)
- Create: `app/javascript/dashboard/api/captain/ferramentas.js`
- Create: `app/javascript/dashboard/routes/dashboard/captain/pages/Ferramentas.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/captain.routes.js:116-123`
- Modify: `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json` (dentro de `CAPTAIN_RAMON`, depois do bloco `WATCHDOG`)
- Modify: `app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue`

**Interfaces:**
- Consumes: `built_in_agent_tools` com `sistema` (Task 2); `NIVEL_TOM`, `agruparPorSistema` (Task 2).
- Produces: `GET /api/v1/accounts/:account_id/captain/ferramentas` → `{ payload: [{ id, title, description, icon, nivel, sistema, skills: [{ id, title, assistant_id, assistant_name }], ultima_execucao_em: ISO|null, execucoes_7d: Integer, erros_7d: Integer }] }`, admin + agente. Rota Vue `captain_ferramentas_index` (`/captain/ferramentas`). Variantes da story `Ferramentas` (catálogo) e `Ferramentas HTTP` (tela antiga).

- [ ] **Step 1: Spec do endpoint** (não roda no CI — `spec/enterprise`; escrever mesmo assim). Criar `spec/enterprise/controllers/api/v1/accounts/captain/ferramentas_controller_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::Ferramentas', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:captain_assistant, account: account, name: 'Atendimento') }
  let(:url) { "/api/v1/accounts/#{account.id}/captain/ferramentas" }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  def registrar(tool_name, status:, quando:)
    Captain::ToolRun.create!(account_id: account.id, tool_name: tool_name, status: status, params: {},
                             resultado: 'ok', duration_ms: 5, created_at: quando)
  end

  it 'lista o catalogo com sistema, as skills ativas que usam e as execucoes de 7 dias' do
    skill = create(:captain_scenario, assistant: assistant, account: account, title: 'Lead aceitou a reuniao',
                                      instruction: 'Combinada a data, use [Mover](tool://mover_etapa).')
    create(:captain_scenario, assistant: assistant, account: account, enabled: false,
                              instruction: 'Use [Mover](tool://mover_etapa).')
    registrar('mover_etapa', status: 'erro', quando: 2.days.ago)
    registrar('mover_etapa', status: 'ok', quando: 1.hour.ago)
    registrar('mover_etapa', status: 'erro', quando: 10.days.ago)

    get url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    mover = json_response[:payload].find { |tool| tool[:id] == 'mover_etapa' }
    expect(mover).to include(nivel: 'sugestao', sistema: 'funil', execucoes_7d: 2, erros_7d: 1)
    expect(mover[:skills]).to eq([{ id: skill.id, title: 'Lead aceitou a reuniao', assistant_id: assistant.id,
                                    assistant_name: 'Atendimento' }])
    expect(Time.zone.parse(mover[:ultima_execucao_em])).to be_within(1.minute).of(1.hour.ago)
  end

  it 'ferramenta que nunca rodou nem e usada vem zerada' do
    get url, headers: agent.create_new_auth_token, as: :json

    faq = json_response[:payload].find { |tool| tool[:id] == 'faq_lookup' }
    expect(faq).to include(skills: [], ultima_execucao_em: nil, execucoes_7d: 0, erros_7d: 0)
  end

  it 'exige autenticacao' do
    get url, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
```

- [ ] **Step 2: Controller** — criar `enterprise/app/controllers/api/v1/accounts/captain/ferramentas_controller.rb`:

```ruby
# ramon: tela Ferramentas (I-FE1/I-FE2) — o catálogo do config/agents/tools.yml
# com as skills ativas que usam cada ferramenta e o que Execuções registrou
# (última vez, execuções e erros em 7 dias). Leitura pura; admin + agente.
class Api::V1::Accounts::Captain::FerramentasController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { authorize(:ramon_dashboard, :show?) }

  def index
    skills = skills_por_ferramenta
    runs = Captain::ToolRun.where(account_id: Current.account.id)
    ultimas = runs.group(:tool_name).maximum(:created_at)
    semana = runs.where(created_at: 7.days.ago..)
    execucoes = semana.group(:tool_name).count
    erros = semana.where(status: 'erro').group(:tool_name).count

    payload = Captain::Assistant.built_in_agent_tools.map do |tool|
      tool.merge(skills: skills.fetch(tool[:id], []), ultima_execucao_em: ultimas[tool[:id]],
                 execucoes_7d: execucoes.fetch(tool[:id], 0), erros_7d: erros.fetch(tool[:id], 0))
    end
    render json: { payload: payload }
  end

  private

  def skills_por_ferramenta
    escopo = Captain::Scenario.enabled.where(account_id: Current.account.id).includes(:assistant).order(:id)
    escopo.each_with_object({}) do |skill, mapa|
      Array(skill.tools).each do |id|
        (mapa[id] ||= []) << { id: skill.id, title: skill.title, assistant_id: skill.assistant_id,
                               assistant_name: skill.assistant.name }
      end
    end
  end
end
```

- [ ] **Step 3: Rota** — em `config/routes.rb`, logo depois de `resources :assistant_responses` (linha 76, dentro de `namespace :captain do`):

```ruby
            resources :ferramentas, only: [:index]
```

- [ ] **Step 4: API JS** — criar `app/javascript/dashboard/api/captain/ferramentas.js`:

```js
import ApiClient from '../ApiClient';

class CaptainFerramentas extends ApiClient {
  constructor() {
    super('captain/ferramentas', { accountScoped: true });
  }
}

export default new CaptainFerramentas();
```

- [ ] **Step 5: i18n** — em `pt_BR/ramon.json`, dentro de `CAPTAIN_RAMON`, logo depois do fechamento do bloco `"WATCHDOG": { ... },` (antes de `"MESSAGE_TEMPLATES": {`), acrescentar:

```json
    "FERRAMENTAS": {
      "TITLE": "Ferramentas",
      "SUBTITLE": "Tudo que os assistentes sabem fazer: o que cada ferramenta faz, em qual sistema mexe, onde é usada e quando rodou.",
      "GRUPO": "{sistema} · {n}",
      "SISTEMA": {
        "funil": "Funil e casos do hub",
        "advbox": "AdvBox",
        "motor": "Motor de cálculos",
        "zapsign": "ZapSign",
        "calcom": "Agenda online (Cal.com)",
        "faq": "FAQs",
        "conversa": "Conversa"
      },
      "USADA_EM": "Usada em:",
      "SKILL": "{skill} ({assistente})",
      "SEM_SKILL": "nenhuma skill ativa",
      "ULTIMA": "Última vez: {quando} · {n} em 7 dias",
      "NUNCA": "Nunca rodou",
      "ERROS_7D": "Erros em 7 dias: {n}",
      "AVANCADO_TITULO": "Avançado",
      "AVANCADO_TEXTO": "Ferramentas HTTP personalizadas: chamam um endereço externo. A banca não usa hoje.",
      "AVANCADO_BOTAO": "Abrir ferramentas HTTP"
    },
```

Em `en/ramon.json`, no mesmo lugar:

```json
    "FERRAMENTAS": {
      "TITLE": "Tools",
      "SUBTITLE": "Everything the assistants can do: what each tool does, which system it touches, where it is used and when it ran.",
      "GRUPO": "{sistema} · {n}",
      "SISTEMA": {
        "funil": "Funnel and hub cases",
        "advbox": "AdvBox",
        "motor": "Calculation engine",
        "zapsign": "ZapSign",
        "calcom": "Online scheduling (Cal.com)",
        "faq": "FAQs",
        "conversa": "Conversation"
      },
      "USADA_EM": "Used in:",
      "SKILL": "{skill} ({assistente})",
      "SEM_SKILL": "no active skill",
      "ULTIMA": "Last run: {quando} · {n} in 7 days",
      "NUNCA": "Never ran",
      "ERROS_7D": "Errors in 7 days: {n}",
      "AVANCADO_TITULO": "Advanced",
      "AVANCADO_TEXTO": "Custom HTTP tools: they call an external address. Not used by the firm today.",
      "AVANCADO_BOTAO": "Open HTTP tools"
    },
```

- [ ] **Step 6: Tela** — criar `app/javascript/dashboard/routes/dashboard/captain/pages/Ferramentas.vue`:

```vue
<script setup>
// Tela Ferramentas (I-FE1/I-FE2): o catálogo do config/agents/tools.yml — o
// que cada ferramenta faz, em qual sistema mexe, o nível (cor), em quais
// skills é usada e o que Execuções registrou. Leitura pura. As ferramentas
// HTTP personalizadas ficam na tela antiga, aberta pelo "Avançado" (admin).
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import Policy from 'dashboard/components/policy.vue';
import CaptainFerramentasAPI from 'dashboard/api/captain/ferramentas';
import {
  AVISO,
  CARTAO,
  CHIP,
  SECAO,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import {
  NIVEL_TOM,
  agruparPorSistema,
} from 'dashboard/routes/dashboard/ramon/helpers/ferramentas';

defineOptions({ name: 'CaptainFerramentas' });

const { t } = useI18n();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const ferramentas = ref([]);
const loading = ref(true);
const error = ref(false);

const fetchData = async () => {
  loading.value = true;
  error.value = false;
  try {
    const response = await CaptainFerramentasAPI.get();
    ferramentas.value = response.data.payload;
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(fetchData);

const grupos = computed(() => agruparPorSistema(ferramentas.value));

const fmtHora = value =>
  new Date(value).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });

const abrirSkill = skill =>
  router.push(
    accountScopedRoute('captain_assistants_scenarios_index', {
      assistantId: skill.assistant_id,
    })
  );
const abrirHttp = () =>
  router.push(
    accountScopedRoute('captain_assistants_index', {
      navigationPath: 'captain_tools_index',
    })
  );
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-auto bg-n-surface-1">
    <div class="w-full max-w-5xl px-6 py-6 mx-auto">
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('CAPTAIN_RAMON.FERRAMENTAS.TITLE') }}
      </h1>
      <p class="mt-1 text-sm text-n-slate-10">
        {{ t('CAPTAIN_RAMON.FERRAMENTAS.SUBTITLE') }}
      </p>
      <div class="flex flex-wrap gap-1.5 mt-3">
        <span
          v-for="(tom, nivel) in NIVEL_TOM"
          :key="nivel"
          :class="[CHIP, tom]"
        >
          {{ t(`CAPTAIN_RAMON.NIVEL.${nivel}`) }}
        </span>
      </div>

      <div
        v-if="error"
        data-testid="ferramentas-error"
        :class="[CARTAO, 'mt-4 text-sm']"
      >
        <p class="text-n-ruby-11">{{ t('CAPTAIN_RAMON.LOAD_ERROR') }}</p>
        <button
          type="button"
          class="mt-1 text-xs text-n-blue-11 hover:underline"
          @click="fetchData"
        >
          {{ t('CAPTAIN_RAMON.RETRY') }}
        </button>
      </div>
      <p v-else-if="loading" class="mt-6 text-sm text-n-slate-10">
        {{ t('CAPTAIN_RAMON.LOADING') }}
      </p>

      <template v-else>
        <section
          v-for="grupo in grupos"
          :key="grupo.sistema"
          class="mt-6"
          :data-testid="`ferramentas-${grupo.sistema}`"
        >
          <h2 :class="TITULO">
            {{
              t('CAPTAIN_RAMON.FERRAMENTAS.GRUPO', {
                sistema: t(`CAPTAIN_RAMON.FERRAMENTAS.SISTEMA.${grupo.sistema}`),
                n: grupo.ferramentas.length,
              })
            }}
          </h2>
          <div class="flex flex-col gap-2 mt-2">
            <article
              v-for="tool in grupo.ferramentas"
              :key="tool.id"
              data-testid="ferramenta"
              :class="CARTAO"
            >
              <div class="flex flex-wrap items-center gap-2">
                <h3 class="text-sm font-medium text-n-slate-12">
                  {{ tool.title }}
                </h3>
                <span :class="[CHIP, NIVEL_TOM[tool.nivel]]">
                  {{ t(`CAPTAIN_RAMON.NIVEL.${tool.nivel}`) }}
                </span>
                <span v-if="tool.erros_7d" :class="[CHIP, TOM.ruby, 'ml-auto']">
                  {{ t('CAPTAIN_RAMON.FERRAMENTAS.ERROS_7D', { n: tool.erros_7d }) }}
                </span>
              </div>
              <p class="mt-1 text-sm text-n-slate-11">{{ tool.description }}</p>
              <div
                :class="[
                  SECAO,
                  'mt-2 flex flex-wrap items-center gap-1.5 text-xs text-n-slate-10',
                ]"
              >
                <span>{{ t('CAPTAIN_RAMON.FERRAMENTAS.USADA_EM') }}</span>
                <button
                  v-for="skill in tool.skills"
                  :key="skill.id"
                  type="button"
                  :class="[CHIP, TOM.slate, 'hover:underline']"
                  @click="abrirSkill(skill)"
                >
                  {{
                    t('CAPTAIN_RAMON.FERRAMENTAS.SKILL', {
                      skill: skill.title,
                      assistente: skill.assistant_name,
                    })
                  }}
                </button>
                <span v-if="!tool.skills.length">
                  {{ t('CAPTAIN_RAMON.FERRAMENTAS.SEM_SKILL') }}
                </span>
                <span class="ml-auto">
                  {{
                    tool.ultima_execucao_em
                      ? t('CAPTAIN_RAMON.FERRAMENTAS.ULTIMA', {
                          quando: fmtHora(tool.ultima_execucao_em),
                          n: tool.execucoes_7d,
                        })
                      : t('CAPTAIN_RAMON.FERRAMENTAS.NUNCA')
                  }}
                </span>
              </div>
            </article>
          </div>
        </section>

        <Policy :permissions="['administrator']">
          <section
            data-testid="ferramentas-avancado"
            :class="[AVISO, TOM.slate, 'mt-6 flex flex-wrap items-center gap-3']"
          >
            <div class="flex-1 min-w-0">
              <p class="font-semibold">
                {{ t('CAPTAIN_RAMON.FERRAMENTAS.AVANCADO_TITULO') }}
              </p>
              <p>{{ t('CAPTAIN_RAMON.FERRAMENTAS.AVANCADO_TEXTO') }}</p>
            </div>
            <Button
              size="xs"
              variant="faded"
              color="slate"
              icon="i-lucide-arrow-right"
              :label="t('CAPTAIN_RAMON.FERRAMENTAS.AVANCADO_BOTAO')"
              @click="abrirHttp"
            />
          </section>
        </Policy>
      </template>
    </div>
  </section>
</template>
```

- [ ] **Step 7: Rota Vue** — em `captain.routes.js`, logo depois do comentário `// precisam vir ANTES do catch-all :navigationPath.` (linha 117), antes da rota `captain_execucoes_index`:

```js
  {
    path: frontendURL('accounts/:accountId/captain/ferramentas'),
    component: () => import('./pages/Ferramentas.vue'),
    name: 'captain_ferramentas_index',
    meta,
  },
```

- [ ] **Step 8: Story** — em `Inteligencia.story.vue`:
  1. Depois de `import Watchdog from './Watchdog.vue';` acrescentar:
     ```js
     import FerramentasPage from './Ferramentas.vue';
     import TOOLS_YML from '../../../../../../../config/agents/tools.yml';
     ```
  2. Depois da constante `RUNS` (antes de `const API = {`), acrescentar:
     ```js
     // Catálogo real (tools.yml) com as skills e execuções fictícias acima.
     const FERRAMENTAS = {
       payload: TOOLS_YML.map(tool => {
         const runs = RUNS.filter(run => run.tool_name === tool.id);
         return {
           ...tool,
           skills: SKILLS.filter(skill => (skill.tools || []).includes(tool.id)).map(
             skill => ({
               id: skill.id,
               title: skill.title,
               assistant_id: 1,
               assistant_name: ATENDIMENTO.name,
             })
           ),
           ultima_execucao_em: runs[0]?.created_at ?? null,
           execucoes_7d: runs.length,
           erros_7d: runs.filter(run => run.status === 'erro').length,
         };
       }),
     };
     ```
  3. Em `const API = {`, depois da linha `'captain/custom_tools': { payload: [], meta: { total_count: 0, page: 1 } },` acrescentar `'captain/ferramentas': FERRAMENTAS,`.
  4. Trocar a variante
     ```vue
         <Variant title="Ferramentas">
           <div class="h-screen"><CustomToolsIndex /></div>
         </Variant>
     ```
     por
     ```vue
         <Variant title="Ferramentas">
           <div class="h-screen"><FerramentasPage /></div>
         </Variant>
         <Variant title="Ferramentas HTTP">
           <div class="h-screen"><CustomToolsIndex /></div>
         </Variant>
     ```

- [ ] **Step 9: Lint + paridade** — `npx eslint app/javascript/dashboard/routes/dashboard/captain/pages/Ferramentas.vue app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue app/javascript/dashboard/routes/dashboard/captain/captain.routes.js app/javascript/dashboard/api/captain/ferramentas.js` → sem erro. Rodar as duas verificações de i18n do topo → `[]`/nenhuma linha.

- [ ] **Step 10: Conferir no harness** — com o Vite da Task 1 de pé, `"/c/Program Files/Google/Chrome/Application/chrome.exe" --headless=new --disable-gpu --hide-scrollbars --window-size=1440,4200 --virtual-time-budget=15000 --screenshot="C:/Users/dudsl/AppData/Local/Temp/claude/ferramentas-check.png" "http://localhost:6195/?variant=Ferramentas&tema=claro"`; abrir o PNG com Read: 7 seções (Funil e casos do hub · 15, AdvBox · 18, Motor de cálculos · 1, ZapSign · 1, Agenda online · 1, FAQs · 1, Conversa · 5), chips coloridos, "Mover de etapa" com "Lead aceitou a reunião (Atendimento (rascunho))", aviso "Avançado" no fim.

- [ ] **Step 11: Commit**

```bash
git add enterprise/app/controllers/api/v1/accounts/captain/ferramentas_controller.rb \
  spec/enterprise/controllers/api/v1/accounts/captain/ferramentas_controller_spec.rb config/routes.rb \
  app/javascript/dashboard/api/captain/ferramentas.js \
  app/javascript/dashboard/routes/dashboard/captain/pages/Ferramentas.vue \
  app/javascript/dashboard/routes/dashboard/captain/captain.routes.js \
  app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json \
  app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue
git commit -m "feat(inteligencia): tela Ferramentas vira o catálogo das 42 com uso real

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 4: Tela Assistentes = cartões reais (I-AS1, I-AS2, I-AS3/I-CX1)

**Files:**
- Modify: `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb:41-46`
- Modify: `config/routes.rb:70-72` (`collection do get :tools end`)
- Test: `spec/enterprise/controllers/api/v1/accounts/captain/assistants_controller_spec.rb`
- Modify: `app/javascript/dashboard/api/captain/assistant.js`
- Modify (reescrita): `app/javascript/dashboard/routes/dashboard/captain/assistants/Index.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/assistants/inboxes/Index.vue:64-72`
- Modify: `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue`

**Interfaces:**
- Consumes: `MODOS`, `modoDefault` de `ramon/helpers/copilotoModo.js`; chaves `RAMON.COPILOTO.MODOS.<modo>.NOME` (já existem).
- Produces: `GET /api/v1/accounts/:account_id/captain/assistants/stats` → `{ payload: [{ id, name, description, publico: 'lead'|'equipe', skills_ativas, faqs_aprovadas, faqs_pendentes, caixas: [{ id, name, channel_type }], conversas_por_modo: { <modo>: Integer } }] }`, ordenado por id, todos os papéis. JS: `CaptainAssistantAPI.stats()`. Chaves i18n `CAPTAIN_RAMON.ASSISTENTES.{SKILLS,FAQS,FAQS_PENDENTES}` (reusadas pela Visão geral na Task 6).

- [ ] **Step 1: Spec** — em `assistants_controller_spec.rb`, acrescentar dentro do `RSpec.describe` principal (antes do último `end`):

```ruby
  describe 'GET /api/v1/accounts/{account.id}/captain/assistants/stats' do
    it 'devolve um cartao por assistente com skills, FAQs, caixas e conversas abertas por modo' do
      atendimento = create(:captain_assistant, account: account, name: 'Atendimento')
      copiloto = create(:captain_assistant, account: account, name: 'Copiloto')
      inbox = create(:inbox, account: account)
      create(:captain_inbox, captain_assistant: atendimento, inbox: inbox)
      create(:captain_scenario, assistant: atendimento, account: account)
      create(:captain_scenario, assistant: atendimento, account: account, enabled: false)
      create(:captain_assistant_response, assistant: atendimento, account: account)
      create(:captain_assistant_response, assistant: atendimento, account: account, status: :pending)
      create(:conversation, account: account, inbox: inbox, custom_attributes: { 'copiloto_modo' => 'manual' })
      create(:conversation, account: account, inbox: inbox)
      create(:conversation, account: account, inbox: inbox, custom_attributes: { 'copiloto_modo' => 'xyz' })
      create(:conversation, account: account, inbox: inbox, status: :resolved)

      with_modified_env RAMON_COPILOTO_MODO_DEFAULT: 'piloto_limitado' do
        get "/api/v1/accounts/#{account.id}/captain/assistants/stats", headers: agent.create_new_auth_token, as: :json
      end

      expect(response).to have_http_status(:success)
      cartoes = json_response[:payload].index_by { |cartao| cartao[:id] }
      expect(cartoes[atendimento.id]).to include(publico: 'lead', skills_ativas: 1, faqs_aprovadas: 1, faqs_pendentes: 1,
                                                 conversas_por_modo: { manual: 1, piloto_limitado: 2 })
      expect(cartoes[atendimento.id][:caixas].pluck(:id)).to eq([inbox.id])
      expect(cartoes[copiloto.id]).to include(publico: 'equipe', skills_ativas: 0, caixas: [], conversas_por_modo: {})
    end

    it 'exige autenticacao' do
      get "/api/v1/accounts/#{account.id}/captain/assistants/stats", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
```

- [ ] **Step 2: Ação `stats`** — em `assistants_controller.rb`, depois do método `tools` (fecha na linha 44) e antes de `private`, acrescentar:

```ruby
  # ramon: tela Assistentes (I-AS1/I-AS2/I-AS3) — um cartão por assistente.
  # ponytail: ~5 consultas por assistente; são 2. Se passar de 10, agrupar.
  def stats
    render json: { payload: account_assistants.order(:id).map { |assistant| cartao(assistant) } }
  end
```

e, dentro do `private`, depois de `account_assistants`:

```ruby
  def cartao(assistant)
    caixas = assistant.inboxes.order(:id).pluck(:id, :name, :channel_type)
                      .map { |id, name, tipo| { id: id, name: name, channel_type: tipo } }
    {
      id: assistant.id, name: assistant.name, description: assistant.description,
      # ponytail: público pela caixa — com caixa fala com o lead; sem caixa, só pela tela Testar (equipe).
      publico: caixas.any? ? 'lead' : 'equipe',
      skills_ativas: assistant.scenarios.enabled.count,
      faqs_aprovadas: assistant.responses.approved.count, faqs_pendentes: assistant.responses.pending.count,
      caixas: caixas, conversas_por_modo: conversas_por_modo(caixas.pluck(:id))
    }
  end

  # Conversas abertas nas caixas do assistente pelo modo efetivo (como Ramon::CopilotoModo.of):
  # sem atributo ou com valor fora da lista conta no padrão do servidor.
  def conversas_por_modo(inbox_ids)
    abertas = Current.account.conversations.where(status: :open, inbox_id: inbox_ids)
    contagem = abertas.group(Arel.sql("custom_attributes->>'copiloto_modo'")).count
    contagem.each_with_object(Hash.new(0)) do |(modo, total), soma|
      soma[Ramon::CopilotoModo::MODOS.include?(modo) ? modo : Ramon::CopilotoModo.default] += total
    end
  end
```

(Se o RuboCop reclamar de `Layout/MultilineMethodCallIndentation` no `.map` do `cartao`, juntar numa linha só — cabe em 150.)

- [ ] **Step 3: Rota** — em `config/routes.rb`, trocar

```ruby
              collection do
                get :tools
              end
```

por

```ruby
              collection do
                get :tools
                get :stats
              end
```

- [ ] **Step 4: API JS** — em `app/javascript/dashboard/api/captain/assistant.js`, depois do método `playground(...) { ... }`:

```js

  stats() {
    return axios.get(`${this.url}/stats`);
  }
```

- [ ] **Step 5: i18n** — em `pt_BR/ramon.json`, dentro de `CAPTAIN_RAMON`, logo depois do bloco `"FERRAMENTAS": { ... },` (Task 3):

```json
    "ASSISTENTES": {
      "PUBLICO": {
        "lead": "Fala com o lead",
        "equipe": "Fala com a equipe"
      },
      "SKILLS": "Skills ativas: {n}",
      "FAQS": "FAQs aprovadas: {n}",
      "FAQS_PENDENTES": "FAQs pendentes: {n}",
      "CAIXAS_N": "Caixas: {n}",
      "MODO": {
        "TITULO": "Modo das conversas",
        "PADRAO": "Conversas novas começam em: {modo}",
        "CONTAGEM": "{modo}: {n}",
        "SEM_CONVERSAS": "Nenhuma conversa aberta nas caixas deste assistente.",
        "SO_LEITURA": "Só leitura. O modo de cada conversa se troca dentro da própria conversa."
      },
      "CAIXAS": {
        "TITULO": "Caixas de entrada",
        "NENHUMA": "Nenhuma caixa conectada: este assistente só conversa pela tela Testar.",
        "GERENCIAR": "Ver e conectar caixas"
      },
      "ATALHOS": {
        "SKILLS": "Skills",
        "FAQS": "FAQs",
        "TESTAR": "Testar",
        "CONFIGURAR": "Configurar"
      }
    },
```

Em `en/ramon.json`, no mesmo lugar:

```json
    "ASSISTENTES": {
      "PUBLICO": {
        "lead": "Talks to leads",
        "equipe": "Talks to the team"
      },
      "SKILLS": "Active skills: {n}",
      "FAQS": "Approved FAQs: {n}",
      "FAQS_PENDENTES": "Pending FAQs: {n}",
      "CAIXAS_N": "Inboxes: {n}",
      "MODO": {
        "TITULO": "Conversation mode",
        "PADRAO": "New conversations start in: {modo}",
        "CONTAGEM": "{modo}: {n}",
        "SEM_CONVERSAS": "No open conversation in this assistant's inboxes.",
        "SO_LEITURA": "Read only. Each conversation's mode is changed inside the conversation."
      },
      "CAIXAS": {
        "TITULO": "Inboxes",
        "NENHUMA": "No inbox connected: this assistant only talks through the Test screen.",
        "GERENCIAR": "View and connect inboxes"
      },
      "ATALHOS": {
        "SKILLS": "Skills",
        "FAQS": "FAQs",
        "TESTAR": "Test",
        "CONFIGURAR": "Configure"
      }
    },
```

- [ ] **Step 6: Tela** — substituir todo o conteúdo de `app/javascript/dashboard/routes/dashboard/captain/assistants/Index.vue` por:

```vue
<script setup>
// Tela Assistentes (I-AS1/I-AS2/I-AS3): um cartão por assistente real — pra
// quem fala, skills, FAQs, caixas conectadas (antes item do menu) e, pra quem
// fala com o lead, o modo das conversas (só leitura). Atalhos levam às telas.
import { computed, nextTick, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import CaptainAssistantAPI from 'dashboard/api/captain/assistant';
import Button from 'dashboard/components-next/button/Button.vue';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import CaptainPaywall from 'dashboard/components-next/captain/pageComponents/Paywall.vue';
import CreateAssistantDialog from 'dashboard/components-next/captain/pageComponents/assistant/CreateAssistantDialog.vue';
import AssistantPageEmptyState from 'dashboard/components-next/captain/pageComponents/emptyStates/AssistantPageEmptyState.vue';
import {
  AVISO,
  CARTAO,
  CHIP,
  SECAO,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import {
  MODOS,
  modoDefault,
} from 'dashboard/routes/dashboard/ramon/helpers/copilotoModo';

const { t } = useI18n();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const cartoes = ref([]);
const loading = ref(true);
const error = ref(false);
const dialogType = ref('');
const createAssistantDialog = ref(null);

const fetchData = async () => {
  loading.value = true;
  error.value = false;
  try {
    const response = await CaptainAssistantAPI.stats();
    cartoes.value = response.data.payload;
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(fetchData);

const isEmpty = computed(
  () => !loading.value && !error.value && !cartoes.value.length
);

// rascunho = azul (nada sai sem humano); piloto = âmbar/vermelho (a IA envia).
const MODO_TOM = {
  manual: TOM.slate,
  rascunho: TOM.blue,
  piloto_limitado: TOM.amber,
  piloto_total: TOM.ruby,
};
const modoNome = modo => t(`RAMON.COPILOTO.MODOS.${modo}.NOME`);
const modosDe = cartao =>
  MODOS.filter(modo => cartao.conversas_por_modo[modo]).map(modo => ({
    modo,
    n: cartao.conversas_por_modo[modo],
  }));

const ATALHOS = [
  {
    rota: 'captain_assistants_scenarios_index',
    rotulo: 'SKILLS',
    icone: 'i-lucide-list-checks',
  },
  {
    rota: 'captain_assistants_responses_index',
    rotulo: 'FAQS',
    icone: 'i-lucide-messages-square',
  },
  {
    rota: 'captain_assistants_playground_index',
    rotulo: 'TESTAR',
    icone: 'i-lucide-play',
  },
  {
    rota: 'captain_assistants_settings_index',
    rotulo: 'CONFIGURAR',
    icone: 'i-lucide-settings',
  },
];
const abrir = (name, assistantId) =>
  router.push(accountScopedRoute(name, { assistantId }));

const handleCreate = () => {
  dialogType.value = 'create';
  nextTick(() => createAssistantDialog.value.dialogRef.open());
};
const handleCreateClose = () => {
  dialogType.value = '';
};
const handleAfterCreate = newAssistant => {
  if (newAssistant?.id)
    abrir('captain_assistants_responses_index', newAssistant.id);
};
</script>

<template>
  <PageLayout
    :header-title="$t('CAPTAIN.ASSISTANTS.HEADER')"
    :button-label="$t('CAPTAIN.ASSISTANTS.ADD_NEW')"
    :button-policy="['administrator']"
    :show-assistant-switcher="false"
    :show-pagination-footer="false"
    :is-fetching="loading"
    :is-empty="isEmpty"
    :feature-flag="FEATURE_FLAGS.CAPTAIN"
    @click="handleCreate"
  >
    <template #emptyState>
      <AssistantPageEmptyState @click="handleCreate" />
    </template>

    <template #paywall>
      <CaptainPaywall />
    </template>

    <template #body>
      <div
        v-if="error"
        data-testid="assistentes-error"
        :class="[AVISO, TOM.ruby]"
      >
        {{ t('CAPTAIN_RAMON.LOAD_ERROR') }}
        <button
          type="button"
          class="ml-1 underline"
          @click="fetchData"
        >
          {{ t('CAPTAIN_RAMON.RETRY') }}
        </button>
      </div>
      <div v-else class="grid gap-3 lg:grid-cols-2">
        <article
          v-for="cartao in cartoes"
          :key="cartao.id"
          data-testid="assistente-cartao"
          :class="CARTAO"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <h2 class="text-base font-medium text-n-slate-12">
                {{ cartao.name }}
              </h2>
              <p class="mt-0.5 text-sm text-n-slate-11">
                {{ cartao.description }}
              </p>
            </div>
            <span
              :class="[CHIP, cartao.publico === 'lead' ? TOM.blue : TOM.slate]"
            >
              {{ t(`CAPTAIN_RAMON.ASSISTENTES.PUBLICO.${cartao.publico}`) }}
            </span>
          </div>

          <div class="flex flex-wrap gap-1.5 mt-3">
            <span :class="[CHIP, TOM.slate]">
              {{ t('CAPTAIN_RAMON.ASSISTENTES.SKILLS', { n: cartao.skills_ativas }) }}
            </span>
            <span :class="[CHIP, TOM.slate]">
              {{ t('CAPTAIN_RAMON.ASSISTENTES.FAQS', { n: cartao.faqs_aprovadas }) }}
            </span>
            <span v-if="cartao.faqs_pendentes" :class="[CHIP, TOM.amber]">
              {{
                t('CAPTAIN_RAMON.ASSISTENTES.FAQS_PENDENTES', {
                  n: cartao.faqs_pendentes,
                })
              }}
            </span>
            <span :class="[CHIP, TOM.slate]">
              {{ t('CAPTAIN_RAMON.ASSISTENTES.CAIXAS_N', { n: cartao.caixas.length }) }}
            </span>
          </div>

          <div v-if="cartao.publico === 'lead'" :class="[SECAO, 'mt-3']">
            <p :class="TITULO">{{ t('CAPTAIN_RAMON.ASSISTENTES.MODO.TITULO') }}</p>
            <p class="mt-1 text-sm text-n-slate-12">
              {{
                t('CAPTAIN_RAMON.ASSISTENTES.MODO.PADRAO', {
                  modo: modoNome(modoDefault()),
                })
              }}
            </p>
            <div class="flex flex-wrap gap-1.5 mt-2">
              <span
                v-for="item in modosDe(cartao)"
                :key="item.modo"
                :class="[CHIP, MODO_TOM[item.modo]]"
              >
                {{
                  t('CAPTAIN_RAMON.ASSISTENTES.MODO.CONTAGEM', {
                    modo: modoNome(item.modo),
                    n: item.n,
                  })
                }}
              </span>
              <span
                v-if="!modosDe(cartao).length"
                class="text-xs text-n-slate-10"
              >
                {{ t('CAPTAIN_RAMON.ASSISTENTES.MODO.SEM_CONVERSAS') }}
              </span>
            </div>
            <p class="mt-2 text-xs text-n-slate-10">
              {{ t('CAPTAIN_RAMON.ASSISTENTES.MODO.SO_LEITURA') }}
            </p>
          </div>

          <div :class="[SECAO, 'mt-3']" data-testid="assistente-caixas">
            <p :class="TITULO">{{ t('CAPTAIN_RAMON.ASSISTENTES.CAIXAS.TITULO') }}</p>
            <div v-if="cartao.caixas.length" class="flex flex-wrap gap-1.5 mt-1">
              <span
                v-for="caixa in cartao.caixas"
                :key="caixa.id"
                :class="[CHIP, TOM.blue]"
              >
                {{ caixa.name }}
              </span>
            </div>
            <p v-else class="mt-1 text-xs text-n-slate-10">
              {{ t('CAPTAIN_RAMON.ASSISTENTES.CAIXAS.NENHUMA') }}
            </p>
            <Button
              class="mt-2"
              size="xs"
              variant="ghost"
              color="slate"
              icon="i-lucide-inbox"
              :label="t('CAPTAIN_RAMON.ASSISTENTES.CAIXAS.GERENCIAR')"
              @click="abrir('captain_assistants_inboxes_index', cartao.id)"
            />
          </div>

          <div :class="[SECAO, 'mt-3 flex flex-wrap gap-2']">
            <Button
              v-for="atalho in ATALHOS"
              :key="atalho.rota"
              size="xs"
              variant="faded"
              color="slate"
              :icon="atalho.icone"
              :label="t(`CAPTAIN_RAMON.ASSISTENTES.ATALHOS.${atalho.rotulo}`)"
              @click="abrir(atalho.rota, cartao.id)"
            />
          </div>
        </article>
      </div>
    </template>

    <CreateAssistantDialog
      v-if="dialogType"
      ref="createAssistantDialog"
      :type="dialogType"
      @close="handleCreateClose"
      @created="handleAfterCreate"
    />
  </PageLayout>
</template>
```

(O `CreateAssistantDialog` antigo recebia `:selected-assistant="selectedAssistant"` sempre `null` — saiu; o prop tem `default: () => ({})`, `CreateAssistantDialog.vue:11-14`.)

- [ ] **Step 7: "Voltar" na tela de caixas** — em `assistants/inboxes/Index.vue`, no `<PageLayout` (linha 64), depois de `:header-title="$t('CAPTAIN.INBOXES.HEADER')"` acrescentar:

```vue
    :back-url="{ name: 'captain_assistants_create_index' }"
```

- [ ] **Step 8: Story** — em `Inteligencia.story.vue`:
  1. Logo depois de `locale.value = 'pt_BR';` acrescentar:
     ```js
     // Produção desde 17/08 (D7): conversas novas começam em Piloto com limites.
     window.chatwootConfig = { ramonCopilotoModoDefault: 'piloto_limitado' };
     ```
  2. Depois da constante `FERRAMENTAS` (Task 3), acrescentar:
     ```js
     const STATS = {
       payload: [
         {
           id: 1,
           name: ATENDIMENTO.name,
           description: ATENDIMENTO.description,
           publico: 'lead',
           skills_ativas: 6,
           faqs_aprovadas: 62,
           faqs_pendentes: 1,
           caixas: [
             { id: 7, name: 'WhatsApp Escritório', channel_type: 'Channel::Whatsapp' },
           ],
           conversas_por_modo: { rascunho: 2, piloto_limitado: 5 },
         },
         {
           id: 2,
           name: COPILOTO.name,
           description: COPILOTO.description,
           publico: 'equipe',
           skills_ativas: 9,
           faqs_aprovadas: 0,
           faqs_pendentes: 0,
           caixas: [],
           conversas_por_modo: {},
         },
       ],
     };
     ```
  3. Em `const API = {`, depois de `'captain/assistants/tools': CATALOGO,` acrescentar `'captain/assistants/stats': STATS,`.

- [ ] **Step 9: Lint + paridade + harness** — `npx eslint app/javascript/dashboard/routes/dashboard/captain/assistants/Index.vue app/javascript/dashboard/routes/dashboard/captain/assistants/inboxes/Index.vue app/javascript/dashboard/api/captain/assistant.js app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue` → sem erro; verificações de i18n → `[]`/nada. Print de conferência (`?variant=Assistentes&tema=escuro`, janela 1440,1300) aberto com Read: 2 cartões; Atendimento com "Fala com o lead", "Conversas novas começam em: Piloto com limites", chips "Rascunho: 2" (azul) e "Piloto com limites: 5" (âmbar), caixa "WhatsApp Escritório"; Copiloto com "Fala com a equipe", sem seção de modo, "Nenhuma caixa conectada…".

- [ ] **Step 10: Commit**

```bash
git add enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb config/routes.rb \
  spec/enterprise/controllers/api/v1/accounts/captain/assistants_controller_spec.rb \
  app/javascript/dashboard/api/captain/assistant.js \
  app/javascript/dashboard/routes/dashboard/captain/assistants/Index.vue \
  app/javascript/dashboard/routes/dashboard/captain/assistants/inboxes/Index.vue \
  app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json \
  app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue
git commit -m "feat(inteligencia): Assistentes mostra os assistentes reais, caixas e modo das conversas

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 5: Endpoint da Visão geral (I-VG1/2/3 — dados)

**Files:**
- Create: `app/controllers/api/v1/accounts/ramon_inteligencia_controller.rb`
- Create: `spec/controllers/api/v1/accounts/ramon_inteligencia_controller_spec.rb`
- Modify: `config/routes.rb:337` (depois de `resource :ramon_watchdog ...`)
- Create: `app/javascript/dashboard/api/ramonInteligencia.js`

**Interfaces:**
- Produces: `GET /api/v1/accounts/:account_id/ramon_inteligencia` (admin + agente) →
  ```
  {
    rascunhos: { <desfecho>: Integer },            // 30 dias; desfechos: igual editado descartado sem_resposta pendente
    piloto: { conversas: Integer, meta: 20, sem_correcao_pct: Integer|null },   // desde sempre
    primeira_resposta: { com_ia?: { conversas, mediana_min: Float }, sem_ia?: { conversas, mediana_min } },  // 30 dias
    transferencias: { total: Integer, conversas: [display_id, ...até 5] },      // 30 dias
    aprovacoes: { sugestoes: Integer, sugestoes_por_tipo: { <acao ou kind>: Integer } },
    agente: { hoje: Integer, teto: 30, problemas_hoje: Integer, ultima_em: ISO|null }
  }
  ```
  JS: `RamonInteligenciaAPI.get()`.

- [ ] **Step 1: Spec** (roda no CI FOSS — não usa `Captain::*`; a nota do Assistente entra por `insert_all`, como em `spec/db/bi_ia_views_spec.rb`). Criar `spec/controllers/api/v1/accounts/ramon_inteligencia_controller_spec.rb`:

```ruby
require 'rails_helper'

# Visão geral da Inteligência (I-VG1–3). A nota-rascunho do Assistente entra por
# insert_all (sender Captain::Assistant sem instanciar) — assim roda no CI FOSS.
RSpec.describe 'Ramon Inteligencia API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_inteligencia" }

  def visao
    get url, headers: agent.create_new_auth_token, as: :json
    response.parsed_body
  end

  # O cliente fala, o Assistente deixa a nota-rascunho e o humano responde `resposta`.
  def rascunho_respondido(resposta)
    conversa = create(:conversation, account: account, inbox: inbox)
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, content: 'oi',
                     created_at: 10.minutes.ago)
    # rubocop:disable Rails/SkipsModelValidations
    Message.insert_all([{ account_id: account.id, inbox_id: inbox.id, conversation_id: conversa.id, message_type: 1,
                          private: true, sender_type: 'Captain::Assistant', sender_id: 1,
                          content: "RASCUNHO (revisar antes de enviar):\nOla, tudo bem?", content_attributes: {},
                          created_at: 5.minutes.ago, updated_at: 5.minutes.ago }])
    # rubocop:enable Rails/SkipsModelValidations
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :outgoing, sender: agent,
                     content: resposta)
    conversa
  end

  it 'conta os rascunhos por desfecho, a regua da D7 e a 1a resposta com IA' do
    rascunho_respondido('Ola, tudo bem?')
    rascunho_respondido('Ola, tudo bem? Pode mandar o laudo')
    rascunho_respondido('Bom dia')

    body = visao

    expect(response).to have_http_status(:success)
    expect(body['rascunhos']).to include('igual' => 1, 'editado' => 1, 'descartado' => 1)
    expect(body['piloto']).to eq('conversas' => 3, 'meta' => 20, 'sem_correcao_pct' => 33)
    expect(body['primeira_resposta']['com_ia']['conversas']).to eq(3)
    expect(body['primeira_resposta']['com_ia']['mediana_min']).to be_between(9, 11)
  end

  it 'conta transferencias, sugestoes pendentes por tipo e o agente de hoje no fuso de Brasilia' do
    travel_to Time.find_zone('America/Sao_Paulo').local(2026, 10, 5, 22, 0) do
      conversa = rascunho_respondido('Bom dia')
      create(:reporting_event, account: account, inbox: inbox, conversation: conversa, name: 'conversation_bot_handoff')
      create(:copilot_suggestion, account: account, kind: 'move_stage')
      create(:copilot_suggestion, account: account, kind: 'acao', payload: { 'acao' => 'zapsign' })
      create(:copilot_suggestion, account: account, status: 'applied')
      account.agente_execucoes.create!(pedido: 'resumo do caso', status: 'ok')
      account.agente_execucoes.create!(pedido: 'falhou', status: 'erro')
      account.agente_execucoes.create!(pedido: 'de manha', status: 'ok', created_at: 12.hours.ago)
      account.agente_execucoes.create!(pedido: 'ontem', status: 'ok', created_at: 23.hours.ago)

      body = visao

      expect(body['transferencias']).to eq('total' => 1, 'conversas' => [conversa.display_id])
      expect(body['aprovacoes']).to eq('sugestoes' => 2, 'sugestoes_por_tipo' => { 'move_stage' => 1, 'zapsign' => 1 })
      expect(body['agente']).to include('hoje' => 3, 'teto' => 30, 'problemas_hoje' => 1)
    end
  end

  it 'conta vazia devolve zeros sem quebrar' do
    body = visao

    expect(body['rascunhos']).to eq({})
    expect(body['piloto']).to eq('conversas' => 0, 'meta' => 20, 'sem_correcao_pct' => nil)
    expect(body['primeira_resposta']).to eq({})
    expect(body['transferencias']).to eq('total' => 0, 'conversas' => [])
    expect(body['agente']).to include('hoje' => 0, 'ultima_em' => nil)
  end

  it 'exige autenticacao' do
    get url, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
```

(Às 22:00 BRT o "hoje" em UTC já começou às 21:00 BRT. "De manhã" = 10:00 BRT do mesmo dia: conta no "hoje" de Brasília e NÃO no de UTC — é o erro que o teste pega (UTC daria 2). "Ontem" = 23:00 BRT do dia anterior: fora dos dois.)

- [ ] **Step 2: Controller** — criar `app/controllers/api/v1/accounts/ramon_inteligencia_controller.rb`:

```ruby
# Visão geral da área Inteligência (I-VG1–3): junta o que o hub já grava —
# views bi_ia (rascunhos, 1ª resposta, transferências), sugestões pendentes da
# IA e a trilha do agente Claude. Leitura pura. Vigia, Ferramentas 24h e Base
# de conhecimento a tela busca nos endpoints que já existem (ramon_watchdog,
# captain_tool_runs, captain/assistants/stats) — este não toca Captain::* e
# roda igual no CI FOSS.
class Api::V1::Accounts::RamonInteligenciaController < Api::V1::Accounts::BaseController
  JANELA = 30.days
  # D7: o padrão vira piloto_limitado depois de ~20 conversas revisadas.
  META_PILOTO = 20
  # ponytail: o teto de verdade mora no runner da VPS (30/dia); aqui só desenha a barra.
  TETO_AGENTE = 30
  REVISADOS = %w[igual editado descartado].freeze

  SQL_RASCUNHOS = <<~SQL.squish.freeze
    SELECT desfecho, COUNT(*) AS total FROM bi_ia_rascunhos
    WHERE account_id = ? AND criado_em >= ? GROUP BY desfecho
  SQL
  SQL_PILOTO = <<~SQL.squish.freeze
    SELECT COUNT(DISTINCT conversation_id) AS conversas, COUNT(*) AS revisados,
           COUNT(*) FILTER (WHERE desfecho = 'igual') AS iguais
    FROM bi_ia_rascunhos WHERE account_id = ? AND desfecho IN (?)
  SQL
  # Mediana, não média: uma conversa que chegou de madrugada não distorce.
  SQL_RESPOSTA = <<~SQL.squish.freeze
    SELECT com_ia, COUNT(*) AS conversas,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY minutos_primeira_resposta) AS mediana
    FROM bi_ia_conversas
    WHERE account_id = ? AND iniciada_em >= ? AND minutos_primeira_resposta IS NOT NULL
    GROUP BY com_ia
  SQL
  SQL_TRANSFERENCIAS = <<~SQL.squish.freeze
    SELECT conversation_id FROM bi_ia_conversas
    WHERE account_id = ? AND iniciada_em >= ? AND handoffs > 0
    ORDER BY iniciada_em DESC
  SQL

  before_action :current_account
  before_action :check_authorization

  def show
    render json: {
      rascunhos: rascunhos, piloto: piloto, primeira_resposta: primeira_resposta,
      transferencias: transferencias, aprovacoes: aprovacoes, agente: agente
    }
  end

  private

  # Mesmas permissões do Centro de Comando e do Vigia (admin + agent).
  def check_authorization
    authorize(:ramon_dashboard, :show?)
  end

  def linhas(sql, *binds)
    ActiveRecord::Base.connection.select_all(ActiveRecord::Base.sanitize_sql_array([sql, *binds])).to_a
  end

  # desfecho => quantos: igual, editado, descartado, sem_resposta, pendente.
  def rascunhos
    linhas(SQL_RASCUNHOS, Current.account.id, JANELA.ago).to_h { |linha| [linha['desfecho'], linha['total'].to_i] }
  end

  # Régua da D7 (desde sempre): conversas com rascunho revisado e % enviado sem correção.
  def piloto
    linha = linhas(SQL_PILOTO, Current.account.id, REVISADOS).first
    revisados = linha['revisados'].to_i
    {
      conversas: linha['conversas'].to_i, meta: META_PILOTO,
      sem_correcao_pct: revisados.zero? ? nil : (linha['iguais'].to_i * 100.0 / revisados).round
    }
  end

  def primeira_resposta
    linhas(SQL_RESPOSTA, Current.account.id, JANELA.ago).to_h do |linha|
      [linha['com_ia'] ? 'com_ia' : 'sem_ia', { conversas: linha['conversas'].to_i, mediana_min: linha['mediana'].to_f.round(1) }]
    end
  end

  # handoffs é 0/1 por conversa (bi_ia_conversas); a tela linka as 5 mais novas.
  def transferencias
    ids = linhas(SQL_TRANSFERENCIAS, Current.account.id, JANELA.ago).pluck('conversation_id')
    { total: ids.size, conversas: Current.account.conversations.where(id: ids.first(5)).order(id: :desc).pluck(:display_id) }
  end

  # Tipo = a ação em sistema (zapsign, advbox, reuniao, perdido) ou o kind (draft, move_stage, alert).
  def aprovacoes
    pendentes = Current.account.copilot_suggestions.pending
    { sugestoes: pendentes.count, sugestoes_por_tipo: pendentes.group(Arel.sql("COALESCE(payload->>'acao', kind)")).count }
  end

  # "Hoje" no fuso de Brasília — o servidor roda em UTC.
  def agente
    execucoes = Current.account.agente_execucoes
    hoje = execucoes.where(created_at: Time.find_zone(Ramon::CockpitMetrics::TIME_ZONE).now.beginning_of_day..)
    {
      hoje: hoje.count, teto: TETO_AGENTE, problemas_hoje: hoje.where.not(status: 'ok').count,
      ultima_em: execucoes.maximum(:created_at)
    }
  end
end
```

- [ ] **Step 3: Rota** — em `config/routes.rb`, logo depois de `resource :ramon_watchdog, only: [:show], controller: 'ramon_watchdog'` (linha 337):

```ruby
          resource :ramon_inteligencia, only: [:show], controller: 'ramon_inteligencia'
```

- [ ] **Step 4: API JS** — criar `app/javascript/dashboard/api/ramonInteligencia.js`:

```js
import ApiClient from './ApiClient';

class RamonInteligenciaAPI extends ApiClient {
  constructor() {
    super('ramon_inteligencia', { accountScoped: true });
  }
}

export default new RamonInteligenciaAPI();
```

- [ ] **Step 5: Lint JS** — `npx eslint app/javascript/dashboard/api/ramonInteligencia.js` → sem erro. (Ruby: sem ambiente local — RuboCop e a spec rodam no CI; revisar à mão o tamanho das linhas ≤ 150 e `EnforcedShorthandSyntax: never`.)

- [ ] **Step 6: Commit**

```bash
git add app/controllers/api/v1/accounts/ramon_inteligencia_controller.rb \
  spec/controllers/api/v1/accounts/ramon_inteligencia_controller_spec.rb config/routes.rb \
  app/javascript/dashboard/api/ramonInteligencia.js
git commit -m "feat(inteligencia): endpoint da Visão geral (rascunhos, régua D7, 1ª resposta, aprovações, agente)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 6: Tela Visão geral + bloco Vigia + rotas (I-VG1/2/3, I-WD1)

**Files:**
- Move + modify: `app/javascript/dashboard/routes/dashboard/captain/pages/Watchdog.vue` → `pages/VigiaBloco.vue`
- Create: `app/javascript/dashboard/routes/dashboard/captain/pages/VisaoGeral.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/captain.routes.js:116-152`
- Modify: `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json` (`CAPTAIN_RAMON.WATCHDOG` e bloco novo `VISAO_GERAL`)
- Modify: `app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue`

**Interfaces:**
- Consumes: `RamonInteligenciaAPI.get()` (Task 5), `CaptainAssistantAPI.stats()` (Task 4), `CaptainToolRunsAPI.list()` + `RamonWatchdogAPI.get()` (existentes), `ferramentaInfo` e chaves `CAPTAIN_RAMON.ASSISTENTES.{SKILLS,FAQS,FAQS_PENDENTES}` (Task 4), `modoDefault`.
- Produces: rota `captain_visao_geral_index` (`/captain/visao-geral`); `/captain` e `/captain/watchdog` redirecionam pra ela; a rota `captain_watchdog_index` deixa de existir (Task 7 tira do menu). Variantes da story `Visao geral` e `Visao geral rascunho`; a variante `Vigia` sai.

- [ ] **Step 1: i18n do Vigia** — em `pt_BR/ramon.json`, bloco `CAPTAIN_RAMON.WATCHDOG` (linha 1630), trocar

```json
      "PARADOS": "Parados agora",
      "RETOMADAS_24H": "Retomadas 24h",
      "PENDENTES": "Sugestões pendentes",
      "EXECUCOES_24H": "Execuções 24h",
```

por

```json
      "PARADOS_N": "Parados agora: {n}",
      "RETOMADAS_N": "Retomadas em 24h: {n}",
```

e `"EMPTY": "Nenhum caso parado no funil agora."` por

```json
      "EMPTY": "Nenhum caso parado no funil agora.",
      "VER_TODOS": "Ver todos ({n})",
      "VER_MENOS": "Ver menos"
```

Em `en/ramon.json` (bloco na linha 1625), trocar

```json
      "PARADOS": "Stalled now",
      "RETOMADAS_24H": "Follow-ups 24h",
      "PENDENTES": "Pending suggestions",
      "EXECUCOES_24H": "Runs 24h",
```

por

```json
      "PARADOS_N": "Stalled now: {n}",
      "RETOMADAS_N": "Follow-ups in 24h: {n}",
```

e `"EMPTY": "No stalled cases in the funnel right now."` por

```json
      "EMPTY": "No stalled cases in the funnel right now.",
      "VER_TODOS": "See all ({n})",
      "VER_MENOS": "See less"
```

- [ ] **Step 2: i18n da Visão geral** — em `pt_BR/ramon.json`, dentro de `CAPTAIN_RAMON`, logo depois do bloco `"ASSISTENTES": { ... },` (Task 4):

```json
    "VISAO_GERAL": {
      "TITLE": "Visão geral",
      "SUBTITLE": "O que a IA fez nos últimos 30 dias e o que está esperando você.",
      "APROVACOES": {
        "TITULO": "Aprovações esperando você",
        "NADA": "Nada esperando você agora.",
        "SUGESTOES": "Sugestões da IA pendentes: {n}",
        "TIPO_N": "{tipo}: {n}",
        "TIPO": {
          "draft": "rascunho",
          "move_stage": "mudar etapa",
          "alert": "alerta",
          "acao": "ação em sistema",
          "zapsign": "contrato ZapSign",
          "advbox": "caso no AdvBox",
          "reuniao": "reunião",
          "perdido": "marcar perdido"
        },
        "ABRIR_SUGESTOES": "Abrir no Centro de Comando",
        "FAQS": "FAQs pendentes: {n}",
        "ABRIR_FAQS": "Revisar FAQs pendentes"
      },
      "PILOTO": {
        "TITULO_RUMO": "Rumo ao piloto limitado",
        "TITULO_EM_VIGOR": "Piloto com limites em vigor",
        "REGUA": "{conversas} de {meta} conversas com rascunho revisado",
        "SEM_CORRECAO": "{pct}% dos rascunhos enviados sem correção",
        "SEM_DADOS": "Ainda não há rascunho revisado.",
        "EM_VIGOR": "Conversas novas já começam em Piloto com limites (decisão D7). A régua continua aqui para acompanhar a qualidade dos rascunhos."
      },
      "RASCUNHOS": {
        "TITULO": "Rascunhos da IA · 30 dias",
        "GERADOS": "rascunhos gerados",
        "DESFECHO_N": "{desfecho}: {n}",
        "igual": "enviados sem edição",
        "editado": "editados",
        "descartado": "descartados",
        "sem_resposta": "ficaram sem uso",
        "pendente": "aguardando"
      },
      "RESPOSTA": {
        "TITULO": "Tempo até a 1ª resposta · 30 dias",
        "com_ia": "Com IA",
        "sem_ia": "Sem IA",
        "MEDIANA": "{min} min",
        "SEM_DADOS": "sem dados",
        "CONVERSAS": "Conversas: {n}",
        "NOTA": "Mediana: metade das conversas teve a 1ª resposta antes desse tempo."
      },
      "TRANSFERENCIAS": {
        "TITULO": "Transferências para humano · 30 dias",
        "TOTAL": "conversas em que a IA chamou alguém da equipe",
        "CONVERSA": "Conversa #{id}"
      },
      "FERRAMENTAS": {
        "TITULO": "Ferramentas · 24h",
        "EXECUCOES": "Execuções: {n}",
        "ERROS": "Erros: {n}",
        "NADA": "Nenhuma ferramenta rodou nas últimas 24h.",
        "VER": "Ver execuções"
      },
      "AGENTE": {
        "TITULO": "Agente Claude",
        "HOJE": "{n} de {teto} pedidos hoje",
        "PROBLEMAS": "Com problema hoje: {n}",
        "ULTIMA": "Último pedido: {quando}",
        "NUNCA": "Nenhum pedido registrado ainda."
      },
      "BASE": {
        "TITULO": "Base de conhecimento"
      }
    },
```

Em `en/ramon.json`, no mesmo lugar:

```json
    "VISAO_GERAL": {
      "TITLE": "Overview",
      "SUBTITLE": "What the AI did in the last 30 days and what is waiting for you.",
      "APROVACOES": {
        "TITULO": "Approvals waiting for you",
        "NADA": "Nothing waiting for you right now.",
        "SUGESTOES": "Pending AI suggestions: {n}",
        "TIPO_N": "{tipo}: {n}",
        "TIPO": {
          "draft": "draft",
          "move_stage": "move stage",
          "alert": "alert",
          "acao": "system action",
          "zapsign": "ZapSign contract",
          "advbox": "AdvBox case",
          "reuniao": "meeting",
          "perdido": "mark as lost"
        },
        "ABRIR_SUGESTOES": "Open in Command Center",
        "FAQS": "Pending FAQs: {n}",
        "ABRIR_FAQS": "Review pending FAQs"
      },
      "PILOTO": {
        "TITULO_RUMO": "Towards limited pilot",
        "TITULO_EM_VIGOR": "Limited pilot in effect",
        "REGUA": "{conversas} of {meta} conversations with a reviewed draft",
        "SEM_CORRECAO": "{pct}% of drafts sent without changes",
        "SEM_DADOS": "No reviewed draft yet.",
        "EM_VIGOR": "New conversations already start in Limited pilot (decision D7). The gauge stays here to track draft quality."
      },
      "RASCUNHOS": {
        "TITULO": "AI drafts · 30 days",
        "GERADOS": "drafts generated",
        "DESFECHO_N": "{desfecho}: {n}",
        "igual": "sent unchanged",
        "editado": "edited",
        "descartado": "discarded",
        "sem_resposta": "left unused",
        "pendente": "waiting"
      },
      "RESPOSTA": {
        "TITULO": "Time to first reply · 30 days",
        "com_ia": "With AI",
        "sem_ia": "Without AI",
        "MEDIANA": "{min} min",
        "SEM_DADOS": "no data",
        "CONVERSAS": "Conversations: {n}",
        "NOTA": "Median: half of the conversations got the first reply faster than this."
      },
      "TRANSFERENCIAS": {
        "TITULO": "Handoffs to a human · 30 days",
        "TOTAL": "conversations where the AI called someone from the team",
        "CONVERSA": "Conversation #{id}"
      },
      "FERRAMENTAS": {
        "TITULO": "Tools · 24h",
        "EXECUCOES": "Runs: {n}",
        "ERROS": "Errors: {n}",
        "NADA": "No tool ran in the last 24h.",
        "VER": "See executions"
      },
      "AGENTE": {
        "TITULO": "Claude agent",
        "HOJE": "{n} of {teto} requests today",
        "PROBLEMAS": "With problems today: {n}",
        "ULTIMA": "Last request: {quando}",
        "NUNCA": "No request recorded yet."
      },
      "BASE": {
        "TITULO": "Knowledge base"
      }
    },
```

- [ ] **Step 3: Watchdog vira bloco** — `git mv app/javascript/dashboard/routes/dashboard/captain/pages/Watchdog.vue app/javascript/dashboard/routes/dashboard/captain/pages/VigiaBloco.vue` e substituir todo o conteúdo por:

```vue
<script setup>
// Bloco Vigia da Visão geral (I-WD1): o vigia que já roda — retomada diária às
// 11:00 e copiloto noturno às 05:00 — com a régua e os casos parados.
// Sugestões pendentes e execuções ficam nos blocos Aprovações e Ferramentas da
// mesma tela. Não dispara nada.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import RamonWatchdogAPI from 'dashboard/api/ramonWatchdog';
import {
  CARTAO,
  CHIP,
  LINHA,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

defineOptions({ name: 'CaptainVigiaBloco' });

const VISIVEIS = 5;

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const data = ref(null);
const loading = ref(false);
const error = ref(false);
const mostrarTodos = ref(false);

const fetchData = async () => {
  loading.value = true;
  error.value = false;
  try {
    const response = await RamonWatchdogAPI.get();
    data.value = response.data;
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(fetchData);

const thresholds = computed(() => data.value?.thresholds ?? {});
const counters = computed(() => data.value?.counters ?? {});
const items = computed(() => data.value?.items ?? []);
const visiveis = computed(() =>
  mostrarTodos.value ? items.value : items.value.slice(0, VISIVEIS)
);

const fmtData = value =>
  value ? new Date(value).toLocaleDateString('pt-BR') : '—';

// Mesmo padrão das outras telas: abre o Funil e seleciona o caso.
const openLead = id => {
  router.push(accountScopedRoute('ramon_funil'));
  store.dispatch('leads/select', id);
};
</script>

<template>
  <section data-testid="vigia-bloco" :class="CARTAO">
    <h2 :class="TITULO">{{ t('CAPTAIN_RAMON.WATCHDOG.TITLE') }}</h2>
    <p class="mt-1 text-xs text-n-slate-10">
      {{ t('CAPTAIN_RAMON.WATCHDOG.SUBTITLE') }}
    </p>

    <p
      v-if="error"
      data-testid="watchdog-error"
      class="mt-3 text-sm text-n-ruby-11"
    >
      {{ t('CAPTAIN_RAMON.LOAD_ERROR') }}
      <button
        type="button"
        class="ml-1 text-xs text-n-blue-11 hover:underline"
        @click="fetchData"
      >
        {{ t('CAPTAIN_RAMON.RETRY') }}
      </button>
    </p>

    <template v-else>
      <div class="flex flex-wrap gap-1.5 mt-3">
        <span
          :class="[CHIP, counters.parados_agora ? TOM.amber : TOM.slate]"
        >
          {{
            t('CAPTAIN_RAMON.WATCHDOG.PARADOS_N', {
              n: counters.parados_agora ?? 0,
            })
          }}
        </span>
        <span :class="[CHIP, TOM.slate]">
          {{
            t('CAPTAIN_RAMON.WATCHDOG.RETOMADAS_N', {
              n: counters.retomadas_24h ?? 0,
            })
          }}
        </span>
      </div>
      <p class="mt-2 text-xs text-n-slate-10">
        {{
          t('CAPTAIN_RAMON.WATCHDOG.REGUA', {
            cap: thresholds.teto_diario,
            gap: thresholds.intervalo_minimo_dias,
            retomada: thresholds.horario_retomada,
            copiloto: thresholds.horario_copiloto,
          })
        }}
      </p>

      <p v-if="loading" class="mt-3 text-sm text-n-slate-10">
        {{ t('CAPTAIN_RAMON.LOADING') }}
      </p>
      <p
        v-else-if="!items.length"
        data-testid="watchdog-vazio"
        class="mt-3 text-sm text-n-slate-10"
      >
        {{ t('CAPTAIN_RAMON.WATCHDOG.EMPTY') }}
      </p>

      <div v-else class="flex flex-col mt-2">
        <button
          v-for="item in visiveis"
          :key="item.lead_id"
          type="button"
          data-testid="watchdog-linha"
          :class="LINHA"
          @click="openLead(item.lead_id)"
        >
          <div class="flex items-center gap-2">
            <span class="font-medium text-n-slate-12">{{ item.name }}</span>
            <span v-if="item.tentativas" :class="[CHIP, TOM.amber]">
              {{
                t('CAPTAIN_RAMON.WATCHDOG.TENTATIVAS', {
                  count: item.tentativas,
                })
              }}
            </span>
            <span class="ml-auto text-[11px] text-n-slate-9">
              {{
                t('CAPTAIN_RAMON.WATCHDOG.PARADO_HA', {
                  days: item.dias_parado,
                })
              }}
            </span>
          </div>
          <p class="mt-0.5 text-xs text-n-slate-11">
            {{ item.stage_name }} ·
            {{ t('CAPTAIN_RAMON.WATCHDOG.ULTIMA') }}
            {{ fmtData(item.ultima_retomada_em) }}
            <span v-if="item.tarefa_aberta">
              · {{ t('CAPTAIN_RAMON.WATCHDOG.COM_TAREFA') }}
            </span>
          </p>
        </button>
        <button
          v-if="items.length > VISIVEIS"
          type="button"
          class="self-start mt-1 text-xs text-n-blue-11 hover:underline"
          @click="mostrarTodos = !mostrarTodos"
        >
          {{
            mostrarTodos
              ? t('CAPTAIN_RAMON.WATCHDOG.VER_MENOS')
              : t('CAPTAIN_RAMON.WATCHDOG.VER_TODOS', { n: items.length })
          }}
        </button>
      </div>
    </template>
  </section>
</template>
```

- [ ] **Step 4: Tela** — criar `app/javascript/dashboard/routes/dashboard/captain/pages/VisaoGeral.vue`:

```vue
<script setup>
// Visão geral da Inteligência (I-VG1–3): a entrada da área. Junta o que o hub
// já grava — aprovações, régua da D7, rascunhos, 1ª resposta, transferências,
// ferramentas, agente Claude, base de conhecimento e o Vigia. Leitura pura;
// cada bloco leva à tela onde se age.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonInteligenciaAPI from 'dashboard/api/ramonInteligencia';
import CaptainAssistantAPI from 'dashboard/api/captain/assistant';
import CaptainToolRunsAPI from 'dashboard/api/captainToolRuns';
import {
  AVISO,
  CARTAO,
  CARTAO_STATUS,
  CHIP,
  FILETE,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { ferramentaInfo } from 'dashboard/routes/dashboard/ramon/helpers/ferramentas';
import { modoDefault } from 'dashboard/routes/dashboard/ramon/helpers/copilotoModo';
import VigiaBloco from './VigiaBloco.vue';

defineOptions({ name: 'CaptainVisaoGeral' });

const { t } = useI18n();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const visao = ref(null);
const assistentes = ref([]);
const execucoes = ref(null);
const loading = ref(true);
const error = ref(false);

const fetchData = async () => {
  loading.value = true;
  error.value = false;
  try {
    const [respVisao, respAssistentes, respExecucoes] = await Promise.all([
      RamonInteligenciaAPI.get(),
      CaptainAssistantAPI.stats(),
      CaptainToolRunsAPI.list(),
    ]);
    visao.value = respVisao.data;
    assistentes.value = respAssistentes.data.payload;
    execucoes.value = respExecucoes.data;
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(fetchData);

// <progress> nativo pintado só com Tailwind (sem style).
const BARRA =
  'mt-2 block h-2 w-full appearance-none overflow-hidden rounded-full bg-n-slate-9/10 [&::-webkit-progress-bar]:bg-n-slate-9/10 [&::-webkit-progress-value]:bg-n-blue-9 [&::-moz-progress-bar]:bg-n-blue-9';
const DESFECHOS = [
  { chave: 'igual', tom: TOM.teal },
  { chave: 'editado', tom: TOM.blue },
  { chave: 'descartado', tom: TOM.ruby },
  { chave: 'sem_resposta', tom: TOM.slate },
  { chave: 'pendente', tom: TOM.slate },
];
const LADOS = ['com_ia', 'sem_ia'];

const rascunhos = computed(() => visao.value.rascunhos);
const totalRascunhos = computed(() =>
  Object.values(rascunhos.value).reduce((soma, n) => soma + n, 0)
);
const piloto = computed(() => visao.value.piloto);
const pilotoEmVigor = computed(() => modoDefault().startsWith('piloto_'));
const resposta = computed(() => visao.value.primeira_resposta);
const transferencias = computed(() => visao.value.transferencias);
const aprovacoes = computed(() => visao.value.aprovacoes);
const agente = computed(() => visao.value.agente);

const faqsPendentes = computed(() =>
  assistentes.value.reduce((soma, item) => soma + item.faqs_pendentes, 0)
);
const assistenteComPendentes = computed(() =>
  [...assistentes.value].sort((a, b) => b.faqs_pendentes - a.faqs_pendentes)[0]
);
const temAprovacao = computed(
  () => aprovacoes.value.sugestoes > 0 || faqsPendentes.value > 0
);

const resumoTools = computed(() => execucoes.value.resumo);
const topTools = computed(() =>
  Object.entries(resumoTools.value.por_tool)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([id, total]) => ({
      ...ferramentaInfo(id, execucoes.value.catalogo),
      total,
    }))
);

const fmtHora = value =>
  new Date(value).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });

const ir = (name, params = {}) =>
  router.push(accountScopedRoute(name, params));
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-auto bg-n-surface-1">
    <div class="w-full max-w-5xl px-6 py-6 mx-auto">
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('CAPTAIN_RAMON.VISAO_GERAL.TITLE') }}
      </h1>
      <p class="mt-1 text-sm text-n-slate-10">
        {{ t('CAPTAIN_RAMON.VISAO_GERAL.SUBTITLE') }}
      </p>

      <div
        v-if="error"
        data-testid="visao-geral-error"
        :class="[CARTAO, 'mt-4 text-sm']"
      >
        <p class="text-n-ruby-11">{{ t('CAPTAIN_RAMON.LOAD_ERROR') }}</p>
        <button
          type="button"
          class="mt-1 text-xs text-n-blue-11 hover:underline"
          @click="fetchData"
        >
          {{ t('CAPTAIN_RAMON.RETRY') }}
        </button>
      </div>
      <p v-else-if="loading" class="mt-6 text-sm text-n-slate-10">
        {{ t('CAPTAIN_RAMON.LOADING') }}
      </p>

      <div v-else class="grid gap-3 mt-5 lg:grid-cols-2">
        <!-- I-VG3: aprovações esperando você -->
        <section
          data-testid="vg-aprovacoes"
          :class="[CARTAO_STATUS, temAprovacao ? FILETE.amber : FILETE.teal]"
        >
          <h2 :class="TITULO">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.APROVACOES.TITULO') }}
          </h2>
          <p v-if="!temAprovacao" class="mt-2 text-sm text-n-slate-11">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.APROVACOES.NADA') }}
          </p>
          <div v-if="aprovacoes.sugestoes" class="mt-2">
            <p class="text-sm text-n-slate-12">
              {{
                t('CAPTAIN_RAMON.VISAO_GERAL.APROVACOES.SUGESTOES', {
                  n: aprovacoes.sugestoes,
                })
              }}
            </p>
            <div class="flex flex-wrap gap-1.5 mt-1">
              <span
                v-for="(n, tipo) in aprovacoes.sugestoes_por_tipo"
                :key="tipo"
                :class="[CHIP, TOM.amber]"
              >
                {{
                  t('CAPTAIN_RAMON.VISAO_GERAL.APROVACOES.TIPO_N', {
                    tipo: t(`CAPTAIN_RAMON.VISAO_GERAL.APROVACOES.TIPO.${tipo}`),
                    n,
                  })
                }}
              </span>
            </div>
            <Button
              class="mt-2"
              size="xs"
              variant="faded"
              color="amber"
              icon="i-lucide-arrow-right"
              :label="t('CAPTAIN_RAMON.VISAO_GERAL.APROVACOES.ABRIR_SUGESTOES')"
              @click="ir('ramon_index')"
            />
          </div>
          <div v-if="faqsPendentes" class="mt-3">
            <p class="text-sm text-n-slate-12">
              {{
                t('CAPTAIN_RAMON.VISAO_GERAL.APROVACOES.FAQS', {
                  n: faqsPendentes,
                })
              }}
            </p>
            <Button
              class="mt-1"
              size="xs"
              variant="faded"
              color="amber"
              icon="i-lucide-arrow-right"
              :label="t('CAPTAIN_RAMON.VISAO_GERAL.APROVACOES.ABRIR_FAQS')"
              @click="
                ir('captain_assistants_responses_pending', {
                  assistantId: assistenteComPendentes.id,
                })
              "
            />
          </div>
        </section>

        <!-- I-VG2: régua da D7 -->
        <section data-testid="vg-piloto" :class="CARTAO">
          <h2 :class="TITULO">
            {{
              pilotoEmVigor
                ? t('CAPTAIN_RAMON.VISAO_GERAL.PILOTO.TITULO_EM_VIGOR')
                : t('CAPTAIN_RAMON.VISAO_GERAL.PILOTO.TITULO_RUMO')
            }}
          </h2>
          <p class="mt-2 text-sm text-n-slate-12">
            {{
              t('CAPTAIN_RAMON.VISAO_GERAL.PILOTO.REGUA', {
                conversas: piloto.conversas,
                meta: piloto.meta,
              })
            }}
          </p>
          <progress :class="BARRA" :value="piloto.conversas" :max="piloto.meta" />
          <p class="mt-2 text-xs text-n-slate-11">
            {{
              piloto.sem_correcao_pct === null
                ? t('CAPTAIN_RAMON.VISAO_GERAL.PILOTO.SEM_DADOS')
                : t('CAPTAIN_RAMON.VISAO_GERAL.PILOTO.SEM_CORRECAO', {
                    pct: piloto.sem_correcao_pct,
                  })
            }}
          </p>
          <p v-if="pilotoEmVigor" :class="[AVISO, TOM.teal, 'mt-2']">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.PILOTO.EM_VIGOR') }}
          </p>
        </section>

        <!-- rascunhos da IA -->
        <section data-testid="vg-rascunhos" :class="CARTAO">
          <h2 :class="TITULO">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.RASCUNHOS.TITULO') }}
          </h2>
          <p class="mt-2 text-2xl font-semibold text-n-slate-12">
            {{ totalRascunhos }}
          </p>
          <p class="text-xs text-n-slate-10">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.RASCUNHOS.GERADOS') }}
          </p>
          <div class="flex flex-wrap gap-1.5 mt-2">
            <span
              v-for="desfecho in DESFECHOS"
              :key="desfecho.chave"
              :class="[CHIP, desfecho.tom]"
            >
              {{
                t('CAPTAIN_RAMON.VISAO_GERAL.RASCUNHOS.DESFECHO_N', {
                  desfecho: t(
                    `CAPTAIN_RAMON.VISAO_GERAL.RASCUNHOS.${desfecho.chave}`
                  ),
                  n: rascunhos[desfecho.chave] ?? 0,
                })
              }}
            </span>
          </div>
        </section>

        <!-- tempo até a 1ª resposta -->
        <section data-testid="vg-resposta" :class="CARTAO">
          <h2 :class="TITULO">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.RESPOSTA.TITULO') }}
          </h2>
          <div class="grid grid-cols-2 gap-3 mt-2">
            <div v-for="lado in LADOS" :key="lado">
              <p class="text-xs text-n-slate-10">
                {{ t(`CAPTAIN_RAMON.VISAO_GERAL.RESPOSTA.${lado}`) }}
              </p>
              <p class="text-2xl font-semibold text-n-slate-12">
                {{
                  resposta[lado]
                    ? t('CAPTAIN_RAMON.VISAO_GERAL.RESPOSTA.MEDIANA', {
                        min: resposta[lado].mediana_min,
                      })
                    : t('CAPTAIN_RAMON.VISAO_GERAL.RESPOSTA.SEM_DADOS')
                }}
              </p>
              <p class="text-xs text-n-slate-10">
                {{
                  t('CAPTAIN_RAMON.VISAO_GERAL.RESPOSTA.CONVERSAS', {
                    n: resposta[lado]?.conversas ?? 0,
                  })
                }}
              </p>
            </div>
          </div>
          <p class="mt-2 text-xs text-n-slate-10">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.RESPOSTA.NOTA') }}
          </p>
        </section>

        <!-- transferências pra humano -->
        <section data-testid="vg-transferencias" :class="CARTAO">
          <h2 :class="TITULO">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.TRANSFERENCIAS.TITULO') }}
          </h2>
          <p class="mt-2 text-2xl font-semibold text-n-slate-12">
            {{ transferencias.total }}
          </p>
          <p class="text-xs text-n-slate-10">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.TRANSFERENCIAS.TOTAL') }}
          </p>
          <div
            v-if="transferencias.conversas.length"
            class="flex flex-wrap gap-1.5 mt-2"
          >
            <button
              v-for="id in transferencias.conversas"
              :key="id"
              type="button"
              :class="[CHIP, TOM.blue, 'hover:underline']"
              @click="ir('inbox_conversation', { conversation_id: id })"
            >
              {{ t('CAPTAIN_RAMON.VISAO_GERAL.TRANSFERENCIAS.CONVERSA', { id }) }}
            </button>
          </div>
        </section>

        <!-- ferramentas 24h -->
        <section data-testid="vg-ferramentas" :class="CARTAO">
          <h2 :class="TITULO">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.FERRAMENTAS.TITULO') }}
          </h2>
          <div class="flex flex-wrap gap-1.5 mt-2">
            <span :class="[CHIP, TOM.slate]">
              {{
                t('CAPTAIN_RAMON.VISAO_GERAL.FERRAMENTAS.EXECUCOES', {
                  n: resumoTools.total_24h,
                })
              }}
            </span>
            <span :class="[CHIP, resumoTools.erros_24h ? TOM.ruby : TOM.slate]">
              {{
                t('CAPTAIN_RAMON.VISAO_GERAL.FERRAMENTAS.ERROS', {
                  n: resumoTools.erros_24h,
                })
              }}
            </span>
          </div>
          <ul v-if="topTools.length" class="flex flex-col gap-1 mt-2">
            <li
              v-for="tool in topTools"
              :key="tool.id"
              class="flex items-center gap-2 text-sm text-n-slate-12"
            >
              <span class="truncate">{{ tool.title }}</span>
              <span v-if="tool.nivel" :class="[CHIP, tool.tom]">
                {{ t(`CAPTAIN_RAMON.NIVEL.${tool.nivel}`) }}
              </span>
              <span class="ml-auto text-xs text-n-slate-10">
                {{ tool.total }}
              </span>
            </li>
          </ul>
          <p v-else class="mt-2 text-sm text-n-slate-11">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.FERRAMENTAS.NADA') }}
          </p>
          <Button
            class="mt-2"
            size="xs"
            variant="ghost"
            color="slate"
            icon="i-lucide-arrow-right"
            :label="t('CAPTAIN_RAMON.VISAO_GERAL.FERRAMENTAS.VER')"
            @click="ir('captain_execucoes_index')"
          />
        </section>

        <!-- agente Claude -->
        <section data-testid="vg-agente" :class="CARTAO">
          <h2 :class="TITULO">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.AGENTE.TITULO') }}
          </h2>
          <p class="mt-2 text-sm text-n-slate-12">
            {{
              t('CAPTAIN_RAMON.VISAO_GERAL.AGENTE.HOJE', {
                n: agente.hoje,
                teto: agente.teto,
              })
            }}
          </p>
          <progress :class="BARRA" :value="agente.hoje" :max="agente.teto" />
          <span
            v-if="agente.problemas_hoje"
            :class="[CHIP, TOM.ruby, 'mt-2']"
          >
            {{
              t('CAPTAIN_RAMON.VISAO_GERAL.AGENTE.PROBLEMAS', {
                n: agente.problemas_hoje,
              })
            }}
          </span>
          <p class="mt-2 text-xs text-n-slate-10">
            {{
              agente.ultima_em
                ? t('CAPTAIN_RAMON.VISAO_GERAL.AGENTE.ULTIMA', {
                    quando: fmtHora(agente.ultima_em),
                  })
                : t('CAPTAIN_RAMON.VISAO_GERAL.AGENTE.NUNCA')
            }}
          </p>
        </section>

        <!-- base de conhecimento -->
        <section data-testid="vg-base" :class="CARTAO">
          <h2 :class="TITULO">
            {{ t('CAPTAIN_RAMON.VISAO_GERAL.BASE.TITULO') }}
          </h2>
          <ul class="flex flex-col gap-2 mt-2">
            <li v-for="assistente in assistentes" :key="assistente.id">
              <p class="text-sm font-medium text-n-slate-12">
                {{ assistente.name }}
              </p>
              <div class="flex flex-wrap gap-1.5 mt-1">
                <button
                  type="button"
                  :class="[CHIP, TOM.slate, 'hover:underline']"
                  @click="
                    ir('captain_assistants_scenarios_index', {
                      assistantId: assistente.id,
                    })
                  "
                >
                  {{
                    t('CAPTAIN_RAMON.ASSISTENTES.SKILLS', {
                      n: assistente.skills_ativas,
                    })
                  }}
                </button>
                <button
                  type="button"
                  :class="[CHIP, TOM.slate, 'hover:underline']"
                  @click="
                    ir('captain_assistants_responses_index', {
                      assistantId: assistente.id,
                    })
                  "
                >
                  {{
                    t('CAPTAIN_RAMON.ASSISTENTES.FAQS', {
                      n: assistente.faqs_aprovadas,
                    })
                  }}
                </button>
                <span
                  v-if="assistente.faqs_pendentes"
                  :class="[CHIP, TOM.amber]"
                >
                  {{
                    t('CAPTAIN_RAMON.ASSISTENTES.FAQS_PENDENTES', {
                      n: assistente.faqs_pendentes,
                    })
                  }}
                </span>
              </div>
            </li>
          </ul>
        </section>

        <VigiaBloco class="lg:col-span-2" />
      </div>
    </div>
  </section>
</template>
```

- [ ] **Step 5: Rotas** — em `captain.routes.js`:
  1. Trocar a rota do watchdog (linhas 124-129)
     ```js
       {
         path: frontendURL('accounts/:accountId/captain/watchdog'),
         component: () => import('./pages/Watchdog.vue'),
         name: 'captain_watchdog_index',
         meta,
       },
     ```
     por
     ```js
       {
         path: frontendURL('accounts/:accountId/captain/visao-geral'),
         component: () => import('./pages/VisaoGeral.vue'),
         name: 'captain_visao_geral_index',
         meta,
       },
       // O Vigia virou bloco da Visão geral: link antigo cai lá.
       {
         path: frontendURL('accounts/:accountId/captain/watchdog'),
         redirect: to => ({
           name: 'captain_visao_geral_index',
           params: to.params,
         }),
       },
     ```
  2. Trocar o `redirect` da rota raiz (linhas 142-150)
     ```js
         redirect: to => {
           return {
             name: 'captain_assistants_index',
             params: {
               navigationPath: 'captain_assistants_responses_index',
               ...to.params,
             },
           };
         },
     ```
     por
     ```js
         // A área abre na Visão geral (backlog §0).
         redirect: to => ({
           name: 'captain_visao_geral_index',
           params: to.params,
         }),
     ```

- [ ] **Step 6: Story** — em `Inteligencia.story.vue`:
  1. Trocar `import Watchdog from './Watchdog.vue';` por `import VisaoGeral from './VisaoGeral.vue';`.
  2. Em `const API = {`, depois do bloco `ramon_watchdog: { ... },` acrescentar:
     ```js
       ramon_inteligencia: {
         rascunhos: {
           igual: 9,
           editado: 6,
           descartado: 2,
           sem_resposta: 1,
           pendente: 1,
         },
         piloto: { conversas: 14, meta: 20, sem_correcao_pct: 53 },
         primeira_resposta: {
           com_ia: { conversas: 12, mediana_min: 3.5 },
           sem_ia: { conversas: 20, mediana_min: 42 },
         },
         transferencias: { total: 3, conversas: [482, 477, 470] },
         aprovacoes: {
           sugestoes: 3,
           sugestoes_por_tipo: { move_stage: 1, zapsign: 1, draft: 1 },
         },
         agente: {
           hoje: 4,
           teto: 30,
           problemas_hoje: 1,
           ultima_em: diasAtras(0.05),
         },
       },
     ```
  3. Depois de `const clicarEm = ...;` (fim do `<script setup>`), acrescentar:
     ```js
     // Visão geral com o padrão antigo (antes da D7): título "Rumo ao piloto".
     const modoRascunho = () => {
       window.chatwootConfig = { ramonCopilotoModoDefault: 'rascunho' };
     };
     ```
  4. No template, trocar
     ```vue
         <Variant title="Vigia">
           <div class="h-screen"><Watchdog /></div>
         </Variant>
     ```
     por
     ```vue
         <Variant title="Visao geral">
           <div class="h-screen"><VisaoGeral /></div>
         </Variant>
         <Variant title="Visao geral rascunho" :init-state="modoRascunho">
           <div class="h-screen"><VisaoGeral /></div>
         </Variant>
     ```

- [ ] **Step 7: Lint + paridade** — `npx eslint app/javascript/dashboard/routes/dashboard/captain/pages/VisaoGeral.vue app/javascript/dashboard/routes/dashboard/captain/pages/VigiaBloco.vue app/javascript/dashboard/routes/dashboard/captain/captain.routes.js app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue` → sem erro. `grep -rn "Watchdog.vue\|captain_watchdog_index\|WATCHDOG.PENDENTES\|WATCHDOG.EXECUCOES_24H\|WATCHDOG.PARADOS\"\|WATCHDOG.RETOMADAS_24H" app/javascript` → só `Sidebar.vue` (`captain_watchdog_index`, sai na Task 7). Verificações de i18n → `[]`/nada.

- [ ] **Step 8: Conferir no harness** — print `?variant=Visao%20geral&tema=claro` (1440,1900) e `?variant=Visao%20geral%20rascunho&tema=escuro`, abrir com Read: 9 blocos; Aprovações com filete âmbar e chips "mudar etapa: 1 · contrato ZapSign: 1 · rascunho: 1"; régua com barra azul em 14/20 e título "Piloto com limites em vigor" (no rascunho: "Rumo ao piloto limitado", sem o aviso teal); Vigia ocupando a largura toda no fim. Se a barra `<progress>` sair cinza-padrão do navegador, conferir se a classe `appearance-none` entrou.

- [ ] **Step 9: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/pages/VisaoGeral.vue \
  app/javascript/dashboard/routes/dashboard/captain/pages/VigiaBloco.vue \
  app/javascript/dashboard/routes/dashboard/captain/pages/Watchdog.vue \
  app/javascript/dashboard/routes/dashboard/captain/captain.routes.js \
  app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json \
  app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue
git commit -m "feat(inteligencia): Visão geral como entrada da área, com o Vigia virando bloco

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 7: Menu final da Inteligência

**Files:**
- Modify: `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:444-534`
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/settings.json:321-323`, `app/javascript/dashboard/i18n/locale/en/settings.json:332-334`

**Interfaces:**
- Consumes: rotas `captain_visao_geral_index` (Task 6), `captain_ferramentas_index` (Task 3).
- Produces: menu Visão geral · Assistentes · Skills · Ferramentas · FAQs · Documentos · Testar · Execuções · Configurações. (A B2 vai inserir "Automações" entre Visão geral e Assistentes — conflito esperado e trivial neste bloco do `Sidebar.vue`.)

- [ ] **Step 1: Sidebar** — no bloco `name: 'Captain'` do `Sidebar.vue`, trocar o comentário e os três primeiros filhos (de `// ponytail: Vigia no topo e Caixas logo após Assistentes = lugar da` até o fim do item `name: 'Inboxes'`):

```js
      // ponytail: Vigia no topo e Caixas logo após Assistentes = lugar da
      // Visão geral (I-VG1) e do cartão do assistente (I-AS3); saem do menu
      // quando esses destinos existirem.
      children: [
        {
          name: 'Watchdog',
          label: t('SIDEBAR.CAPTAIN_WATCHDOG'),
          activeOn: ['captain_watchdog_index'],
          to: accountScopedRoute('captain_watchdog_index'),
        },
        {
          name: 'Assistants',
          label: t('SIDEBAR.CAPTAIN_ASSISTANTS'),
          activeOn: ['captain_assistants_create_index'],
          to: accountScopedRoute('captain_assistants_create_index'),
        },
        {
          name: 'Inboxes',
          label: t('SIDEBAR.CAPTAIN_INBOXES'),
          activeOn: ['captain_assistants_inboxes_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_inboxes_index',
          }),
        },
```

por

```js
      // Vigia virou bloco da Visão geral; Caixas, seção do cartão do assistente.
      children: [
        {
          name: 'VisaoGeral',
          label: t('SIDEBAR.CAPTAIN_VISAO_GERAL'),
          activeOn: ['captain_visao_geral_index'],
          to: accountScopedRoute('captain_visao_geral_index'),
        },
        {
          name: 'Assistants',
          label: t('SIDEBAR.CAPTAIN_ASSISTANTS'),
          activeOn: [
            'captain_assistants_create_index',
            'captain_assistants_inboxes_index',
          ],
          to: accountScopedRoute('captain_assistants_create_index'),
        },
```

e o item `name: 'Tools'`:

```js
        {
          name: 'Tools',
          label: t('SIDEBAR.CAPTAIN_TOOLS'),
          activeOn: ['captain_tools_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_tools_index',
          }),
        },
```

por

```js
        {
          name: 'Tools',
          label: t('SIDEBAR.CAPTAIN_TOOLS'),
          activeOn: ['captain_ferramentas_index', 'captain_tools_index'],
          to: accountScopedRoute('captain_ferramentas_index'),
        },
```

- [ ] **Step 2: settings.json** — `pt_BR/settings.json`: trocar

```json
    "CAPTAIN_WATCHDOG": "Vigia",
    "CAPTAIN_INBOXES": "Caixas de Entrada",
```

por

```json
    "CAPTAIN_VISAO_GERAL": "Visão geral",
```

`en/settings.json`: trocar

```json
    "CAPTAIN_WATCHDOG": "Watchdog",
    "CAPTAIN_INBOXES": "Inboxes",
```

por

```json
    "CAPTAIN_VISAO_GERAL": "Overview",
```

- [ ] **Step 3: Conferir** — `grep -rn "CAPTAIN_WATCHDOG\|CAPTAIN_INBOXES\|captain_watchdog_index" app/javascript` → nada (a rota `/captain/watchdog` agora só existe como redirect sem nome). `npx eslint app/javascript/dashboard/components-next/sidebar/Sidebar.vue` → sem erro. Verificações de i18n → `[]`/nada.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/dashboard/components-next/sidebar/Sidebar.vue \
  app/javascript/dashboard/i18n/locale/en/settings.json app/javascript/dashboard/i18n/locale/pt_BR/settings.json
git commit -m "feat(inteligencia): menu com Visão geral; Vigia e Caixas saem do menu

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 8: Verificação final + prints "depois" + `comparar.html`

**Files:**
- Create (não versionado): `tmp/intel-harness/comparar-a2.mjs`
- Output: `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-05-inteligencia-a2\{depois-*.png,comparar.html}`

- [ ] **Step 1: Testes e lint completos (JS)**

```bash
npx vitest run --config tmp/vitest.local.config.ts app/javascript/dashboard/routes/dashboard/ramon/helpers/specs app/javascript/dashboard/components-next/captain
npx eslint app/javascript/dashboard/routes/dashboard/captain app/javascript/dashboard/routes/dashboard/ramon/helpers app/javascript/dashboard/api app/javascript/dashboard/components-next/sidebar/Sidebar.vue
```

Expected: tudo PASS, eslint sem erro. Rodar as duas verificações de i18n do topo → `[]`/nada.

- [ ] **Step 2: Imports e rotas órfãs** — `grep -rn "pages/Watchdog\|captain_watchdog_index\|CAPTAIN_INBOXES\|CAPTAIN_WATCHDOG" app/javascript` → nada. (O build de produção roda no CI/Docker; a compilação das mensagens do topo já cobre o que quebrou o build no A1.)

- [ ] **Step 3: Prints "depois"** — Vite do harness de pé (Task 1, Step 4); `sh tmp/intel-harness/shots-a2.sh depois` → 12 PNGs `depois-{claro,escuro}-{visao-geral,visao-geral-rascunho,assistentes,ferramentas,ferramentas-http,caixas}.png`. Abrir com Read pelo menos `depois-claro-visao-geral.png`, `depois-escuro-assistentes.png` e `depois-claro-ferramentas.png` (claro e escuro legíveis, fundos translúcidos, nada cortado).

- [ ] **Step 4: `comparar.html`** — criar `tmp/intel-harness/comparar-a2.mjs` (Write):

```js
import { writeFileSync } from 'node:fs';

const OUT = 'C:/Users/dudsl/RAdvogados/comercial/docs/mockups/2026-10-05-inteligencia-a2';
// [título, itens, legenda, arquivo antes (ou null), arquivo depois]
const TELAS = [
  ['Visão geral (padrão de hoje: Piloto com limites)', 'I-VG1, I-VG2, I-VG3, I-WD1', 'tela nova de entrada; o Vigia virou o último bloco', 'vigia', 'visao-geral'],
  ['Visão geral (se o padrão fosse Rascunho)', 'I-VG2', 'mesmo bloco da régua com o título do backlog', null, 'visao-geral-rascunho'],
  ['Assistentes', 'I-AS1, I-AS2, I-AS3', 'cartões reais: público, skills, FAQs, caixas e modo das conversas', 'assistentes', 'assistentes'],
  ['Ferramentas', 'I-FE1, I-FE2', 'catálogo das 42 por sistema, nível, skills, última vez e erros', 'ferramentas', 'ferramentas'],
  ['Ferramentas HTTP (Avançado)', 'I-FE4', 'a tela antiga continua, aberta pelo aviso Avançado (admin)', 'ferramentas', 'ferramentas-http'],
  ['Caixas de entrada', 'I-CX1', 'sai do menu; abre pelo cartão do assistente e tem Voltar', 'caixas', 'caixas'],
];
const MENU_ANTES = 'Vigia · Assistentes · Caixas de Entrada · Skills · Ferramentas · FAQs · Documentos · Testar · Execuções · Configurações';
const MENU_DEPOIS = 'Visão geral · (Automações, quando a B2 entrar) · Assistentes · Skills · Ferramentas · FAQs · Documentos · Testar · Execuções · Configurações';
const fig = (rotulo, arq, nome) =>
  arq ? `<figure><figcaption>${rotulo}</figcaption><img src="${arq}.png" alt="${rotulo}, ${nome}"></figure>` : '';
const secoes = TELAS.flatMap(([nome, itens, legenda, antes, depois]) =>
  ['claro', 'escuro'].map(
    tema =>
      `<section><h2>${nome} · ${itens} · tema ${tema}</h2><p class="leg">${legenda}</p><div class="par">${fig('Antes', antes && `antes-${tema}-${antes}`, nome)}${fig('Depois', `depois-${tema}-${depois}`, nome)}</div></section>`
  )
).join('');
const css = 'body{font:14px system-ui,sans-serif;margin:24px;background:#f4f4f4;color:#111}h1{font-size:20px}h2{font-size:15px;margin:28px 0 4px}.leg{margin:0 0 8px;color:#555}.par{display:flex;gap:24px;align-items:flex-start;flex-wrap:wrap}figure{margin:0;background:#fff;padding:8px;border:1px solid #ddd;border-radius:8px}figcaption{font-weight:600;margin-bottom:6px}img{width:700px;max-width:100%;display:block}';
writeFileSync(`${OUT}/comparar.html`,
  `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>Inteligência A2 — antes e depois</title><style>${css}</style></head><body><h1>Inteligência — pacote A2 (telas que dizem a verdade): antes e depois</h1><section><h2>Menu da Inteligência</h2><p><b>Antes:</b> ${MENU_ANTES}</p><p><b>Depois:</b> ${MENU_DEPOIS}</p><p>/captain abre a Visão geral; o link antigo do Vigia cai nela.</p></section><section><h2>Para decidir</h2><p>1) A D7 já foi fechada em 17/08: o bloco da régua aparece como "Piloto com limites em vigor" (acompanhamento). Manter assim ou tirar o bloco? 2) A Visão geral aparece também para agentes (não só admin), como o Vigia e Execuções.</p></section>${secoes}</body></html>`);
console.log(`ok ${OUT}/comparar.html`);
```

Rodar `node tmp/intel-harness/comparar-a2.mjs` → `ok …/comparar.html`. Abrir o HTML com Read (ou no Chrome) e conferir que todas as imagens existem (nenhum `<img>` quebrado).

- [ ] **Step 5: Parar o Vite do harness** (TaskStop no processo em background).

- [ ] **Step 6: Entregar pro Eduardo** — mandar o caminho clicável `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-05-inteligencia-a2\comparar.html` + as 2 decisões da seção "Decisões que exigem o Eduardo". **Parar aqui.** Push + PR (base `feat/inteligencia-a1-faxina`, ou `ramon` se o #198 já entrou) só depois do "aprovado"; ajustes pedidos viram commits novos nas tasks donas, com novo print.

---

## Roteiro de smoke pós-deploy (vai no corpo do PR)

Sem migração e sem seed. Depois do deploy na VPS:

1. Clicar em **Inteligência** → abre a **Visão geral**. Abrir `/app/accounts/<id>/captain/watchdog` → cai na Visão geral.
2. Menu: Visão geral · Assistentes · Skills · Ferramentas · FAQs · Documentos · Testar · Execuções · Configurações (sem Vigia, sem Caixas).
3. **Assistentes:** 2 cartões. Atendimento = "Fala com o lead", caixa Teste listada, "Conversas novas começam em: Piloto com limites", contagem por modo. Copiloto = "Fala com a equipe", sem caixa. Os 4 atalhos abrem a tela certa do assistente certo; "Ver e conectar caixas" abre a tela de caixas e o "voltar" retorna.
4. **Ferramentas:** 42 ferramentas em 7 seções; "Mover de etapa" lista as skills que a usam; "Avançado" só aparece logado como admin.
5. **Visão geral** logado como **agente** (não admin): abre sem erro; "Abrir no Centro de Comando" e "Ver execuções" navegam.
6. (Endpoints `enterprise/` não têm spec no CI.) Se algum cartão vier vazio, conferir no console do navegador a resposta de `/captain/assistants/stats` e `/captain/ferramentas`.
