# Inteligência — A3 (funções que destravam uso) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar a terceira fatia da área Inteligência: **colar texto** em Documentos, **FAQ por tese** (guardar, filtrar, etiquetar), **Testar pergunta** nas FAQs, **liga/desliga de skill** com aba "Desligadas", **seed que respeita a skill editada**, **links** (caso, conversa, assistente) nas Execuções, a **trilha do agente Claude** como aba das Execuções e o **I-WD2** (as sugestões pendentes da Visão geral abrem o "Enquanto você dormia" do Centro já aberto e filtrado) — sem refazer o que os PRs #213–#218 já entregaram.

**Architecture:** Backend pequeno e local a cada tela: 2 migrações de coluna (`captain_assistant_responses.tese`; `captain_scenarios.edited` + `seed_titulo`), 1 ação nova de leitura no `AssistantsController` (`buscar_faq`, a mesma busca do `faq_lookup`), 1 controller novo FOSS (`ramon_agente_execucoes`, leitura de `agente_execucoes`) e ajustes em controllers/jbuilders existentes. O seed (`Ramon::InteligenciaSeed`) passa a gravar a tese pelo nome do arquivo e a pular skill editada/renomeada/criada na tela; um rake só-de-teses preenche a produção sem rodar o seed inteiro. No front, todas as chaves novas vão num arquivo i18n **novo** (`ramonIntel.json`, raiz `INTEL`) para não disputar `ramon.json` com a A4; telas no kit `ramon/helpers/ui.js`. Aprovação por prints antes × depois (story + harness Vite + Chrome headless).

**Tech Stack:** Rails 7.1 / RSpec (só no CI), Postgres (tsvector `portuguese` da busca de FAQ); Vue 3.5 `<script setup>`, vue-router 4, vue-i18n 9, Vuelidate, Vitest 3 + @vue/test-utils, Histoire (story dos prints).

**Spec:** `C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-05-inteligencia-tela-a-tela.md` (backlog de 67 itens; os desta fatia: I-DO1, I-FQ1, I-FQ2, I-PG1, I-SK4, I-SK5, I-EX2, I-EX4, I-WD2). Entregas anteriores: `comercial\docs\2026-10-05-smoke-inteligencia-a1.md` (PR #198) e `…-a2.md` (PR #201). Plano de referência de estilo: `docs/superpowers/plans/2026-10-06-automacoes-fluxo-b4-lembretes.md`.

## Escopo da A3 (lista registrada com o Eduardo) × o que já foi feito

Conferido no código da base **079a04c** (diffs de #213 Registro de ações, #214 Casos de teste da IA, #215 Uso e custo da IA, #218 skills de rotina dos POPs):

| Item da A3 | Backlog | Situação na base 079a04c | O que este plano faz |
|---|---|---|---|
| Colar texto (Documentos) | I-DO1 | **Parcial.** O backend já aceita: `documents_controller.rb` permite `:content` (FORK-PONTO) e `Captain::Document#set_external_link_for_text` cria o documento `TEXT: …` já disponível, que gera FAQs pendentes. Falta o formulário (só URL, `DocumentForm.vue`), o cartão (mostra "TEXT: nome_2026…" e status de sincronização) e o filtro (fonte "PDFs", que não funciona aqui) | Task 2 |
| FAQ por tese | I-FQ1 | **A fazer.** A tese está no cabeçalho dos `db/seeds/ramon/inteligencia/faq/*.md`, mas `Ramon::InteligenciaSeed#seed_faq` descarta; não há coluna | Tasks 3 e 4 |
| Testar pergunta | I-FQ2 | **A fazer.** O #214 (Casos de teste) roda o assistente inteiro em modo seguro e julga a resposta; **não** mostra o que a busca de FAQ acharia para uma pergunta | Task 5 |
| Caderno de provas | I-PG1 | **Já entregue pelo #214**: `rake ramon:ia:importar_caderno` trouxe 43 casos do caderno de 16/08 (grupo = tese), aba "Casos de teste" no Testar (só admin) com Rodar todos, ✅/❌ por caso, histórico e o que piorou/melhorou | Nada (ver Decisão N2) |
| Liga/desliga skill | I-SK4 | **A fazer.** `scenarios_controller#index` só devolve as ligadas; não há chave na tela | Tasks 6 e 7 |
| Seed respeita edição | I-SK5 | **A fazer** (e mais urgente depois do #218, que pôs skills novas no `assistentes.yml`: rodar o seed hoje sobrescreve a skill editada, religa a desligada e desliga a criada na tela) | Task 6 |
| Links nas Execuções | I-EX2 | **A fazer.** A API já manda `lead_id`, `conversation_id` (id interno, não o nº da conversa) e `assistant_id`; a tela mostra "caso #123" sem link e não mostra conversa nem assistente | Task 8 |
| Trilha do agente Claude | I-EX4 | **Parcial.** A2 (#201) pôs na Visão geral só o contador de hoje; #215 gravou tokens/custo e mostra o custo em Uso e custo (admin). A trilha (pedido, resposta, ações, duração) não aparece em lugar nenhum | Task 9 |
| I-WD2 (sugestões pendentes clicáveis → Cockpit filtrado) | I-WD2 | **Parcial.** A2 (I-VG3) pôs "Abrir no Centro de Comando" na Visão geral, mas cai no Centro com o "Enquanto você dormia" **recolhido** (preferência do navegador) e sem filtro; os chips por tipo não são clicáveis | Task 10 |

#213 (Registro de ações) e #215 (Uso e custo) não tocam nenhum item acima além do já dito.

## Global Constraints

- Base: produção **079a04c** (B1–B3 + B4.1 no ar, #213–#218 no ar); branch `feat/inteligencia-a3`, worktree `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-intel-a3`. Nunca `git push`, nunca abrir PR, nunca `git stash`, nunca `git add -A` (gate do Eduardo / sessão principal).
- **Migrações (2, só colunas):** `20261007500001_add_tese_to_captain_assistant_responses.rb` (Task 3) e `20261007500002_add_edicao_to_captain_scenarios.rb` (Task 6). O `CLAUDE.md` do projeto pede regenerar o `db/schema.rb` por scratch DB na VPS; como o ssh de escrita é barrado para o Claude e são só 3 colunas, o executor edita o `db/schema.rb` **à mão no formato exato do dump** (colunas no fim do bloco da tabela, na ordem do `add_column`; linha `define(version: …)` = a maior migração — mesmo jeito dos #214/#215: conferir com `git show 3d375a754c -- db/schema.rb`). Se a sessão principal tiver o scratch DB à mão antes do merge, regenerar e comparar. Faixa de timestamps reservada à A3: `2026100750xxxx`.
- **Rubocop do fork** (o CI barra): `Metrics/AbcSize` 26, `Metrics/MethodLength` 19, `Metrics/CyclomaticComplexity` 7, `Metrics/PerceivedComplexity` 8, `Metrics/ClassLength` 175, `Metrics/ModuleLength` 100, `Metrics/BlockLength` 30 (fora de spec), linha 150, `Style/HashSyntax` `EnforcedShorthandSyntax: never` (sempre `chave: valor`), `Naming/MethodParameterName` mínimo 3 letras, `rubocop-rspec` (`RSpec/MultipleExpectations` 7, `RSpec/ExampleLength` 50, `RSpec/SpecFilePathFormat`, **`RSpec/ContextWording`: `context` só começa com when/with/without — frase em pt-BR vai em `describe`**). **`app/models/lead.rb`, `app/services/ramon/advbox_event_processor.rb` e `app/finders/conversation_finder.rb` estão NO LIMITE de 175 linhas: nenhuma linha nova neles** (este plano não toca nenhum dos três). `enterprise/app/models/captain/scenario.rb` tem 177 linhas: **não tocar** (colunas novas não exigem mudança no modelo). Tamanhos na base: `assistants_controller.rb` 130 (→ ~140), `scenarios_controller.rb` 47 (→ ~58), `lib/ramon/inteligencia_seed.rb` 70 (→ ~100), `captain_tool_runs_controller.rb` 40 (→ ~58).
- **Postgres:** `.distinct.pluck` em modelo com `default_scope` ordenado quebra (`Lead` tem `default_scope { order(...) }`) — usar `.pluck(...)` sem `distinct` (`.pluck.uniq` se precisar). Nada de `NOW()` no SQL (só `Time.current` / `Time.find_zone(...)`). `travel_to` em sequência, nunca aninhado.
- **CI FOSS apaga `enterprise/`:** todo código em `app/` que toque `Captain::*` fica atrás de `ChatwootApp.enterprise?`, e o spec dele com `if: ChatwootApp.enterprise?`. Specs em `spec/enterprise/` já só rodam no enterprise.
- **Sem Ruby local:** specs Ruby escritos e conferidos à mão (rastrear cada linha); quem valida é o CI.
- **Mensagem ao cliente SEMPRE rascunho; honorário 30% + 3 nas FAQs; DeepSeek é o motor; FAQ por busca de texto em português (sem embeddings).** Nada nesta fatia envia mensagem; `buscar_faq` usa exatamente `responses.approved.search(...)` do `Captain::Tools::FaqLookupTool`.
- **Front — i18n:** toda chave nova vai em `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramonIntel.json` (raiz `INTEL`, criado na Task 2; mesma ordem nos dois; a trava `captain/pages/specs/IntelI18n.spec.js` compara a ordem e compila no vue-i18n de produção). **Não adicionar chave em `ramon.json`** (A4 em paralelo). Exceção: 2 valores em `integrations.json` (`CAPTAIN.DOCUMENTS.FORM_DESCRIPTION` e a chave nova `CAPTAIN.DOCUMENTS.FILTERS.SOURCE.TEXT`, Task 2). Strings sem `@`, `|`, `{`, `}` crus (só placeholders `{n}`, `{id}`, `{nome}`, `{teto}`, `{tipo}`); editar JSON à mão (Edit). Chaves `CAPTAIN_RAMON.EXECUCOES.STATUS_OK/STATUS_ERRO/CASO` ficam sem uso depois da Task 8 — **não apagar** (`ramon.json` fica intocado; ponytail).
- **Front — visual:** Tailwind only, kit `ramon/helpers/ui.js` (`CARTAO`, `CHIP`, `TOM`, `ABA*`, `SELECT`, `CAMPO`, `TITULO`, `AVISO`, `ROTULO`), destaque azul (`text-n-blue-11`, nunca `iris` em coisa nova), fundos translúcidos, evento custom camelCase, toda `<ul>/<ol>` nova com `list-none`, sem texto cru no template (montar no script).
- **Vitest:** `node_modules` é junção para `ramon-hub-wt-fluxos-b2\node_modules` (nunca `rm -rf node_modules`). Config local já existe e é ignorado pelo git (`.git/info/exclude`): `vitest.local.config.ts` na raiz do worktree.
  `TZ=UTC npx vitest run <arquivos ou pastas> --config vitest.local.config.ts`
  Baseline medido na base 079a04c: `app/javascript/dashboard/components-next/captain app/javascript/dashboard/routes/dashboard/captain app/javascript/dashboard/routes/dashboard/ramon/components/command/specs app/javascript/dashboard/routes/dashboard/ramon/pages/specs/CommandCenter.spec.js` = **28 arquivos, 250 testes**. ESLint: `./node_modules/.bin/eslint <arquivos>` (erro `Delete ␍` = CRLF do checkout Windows, ignorar; warnings `@intlify/vue-i18n/no-dynamic-keys` já existem e são aceitos).
- **Bash deste Windows come barra invertida em heredoc:** arquivos (inclusive `.sh`/`.mjs` do harness) são criados com a ferramenta Write.
- **Commits:** Conventional Commits em pt-BR, sem citar Claude no assunto; corpo termina com:
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR`
  Commitar só os caminhos da task (`git add <arquivos>`).
- **Um PR só (A3).** O rito "funcional em PR separado do visual" não se aplica bem aqui: cada mudança visual é o próprio elemento novo da função (chave, aba, campo, link). O único retoque puramente visual (Execuções no kit, sem roxo) vai junto porque a tela é reescrita na Task 8.

## Pontos de conflito com as frentes em paralelo

| Arquivo | Quem mais pode tocar | Como resolver |
|---|---|---|
| `app/javascript/dashboard/i18n/locale/{en,pt_BR}/index.js` | **A4** (se também criar arquivo i18n próprio) | Conflito trivial de linhas vizinhas (1 `import` + 1 spread depois de `ramonIaUso`): manter as duas. **Avisar a A4: não usar o nome `ramonIntel.json` nem a raiz `INTEL`** (o spread é raso — duas raízes iguais se apagam) |
| `ramon.json` | **A4** | A3 **não toca** |
| `Sidebar.vue`, `captain.routes.js` | **A4** | A3 **não toca** (tudo entra em telas existentes; Execuções ganha aba por `?aba=agente`) |
| `integrations.json` (`CAPTAIN.DOCUMENTS.*`) | A4, se mexer em Documentos | Manter as duas edições; `FILTERS.SOURCE.TEXT` é chave nova |
| `config/routes.rb` | B4.2/B4.3/B4.4 (rotas novas) | A3 acrescenta 1 linha depois de `resources :captain_tool_runs` e `get :buscar_faq` no `member` de `captain/assistants` — manter todas |
| `db/schema.rb` | qualquer frente com migração | Linha `define(version:)` = a maior das duas; blocos de tabela não se cruzam (A3 só mexe em `captain_assistant_responses` e `captain_scenarios`) |
| `VisaoGeral.vue`, `Execucoes.vue`, `Inteligencia.story.vue`, `CommandCenter.vue`/`NightCopilot.vue` | A4 (se tocar Visão geral/Execuções) | Merge manual; A3 muda o `ir()` da Visão geral (ganha `query`), os chips de tipo e o bloco do agente |
| `lib/ramon/inteligencia_seed.rb`, `db/seeds/ramon/inteligencia/*` | qualquer frente que mexa no seed/skills (como o #218) | A3 reescreve `seed_skills`/`seed_faq`; quem vier depois rebaseia |

## Review Focus

1. **Desligar uma skill antiga cuja instrução cita uma ferramenta que saiu do catálogo** — esperado: desliga (hoje o `update!` revalida a instrução e devolveria 422, e a pessoa não conseguiria tirar do ar justamente a skill quebrada); religar sem corrigir continua barrado. Teste: Task 6 ("desliga mesmo assim", "nao religa sem corrigir").
2. **Rodar o seed depois de editar, renomear, desligar ou criar skill na tela** — esperado: nada muda, nada duplica, nada é religado nem desligado. Teste: Task 6 ("respeita skill editada, renomeada, desligada ou criada na tela").
3. **FAQ editada na tela sem tese, ou com a tese trocada na tela, e o seed roda** — esperado: tese vazia é preenchida pelo arquivo; tese escolhida na tela nunca é sobrescrita; resposta editada não muda. Teste: Task 3 ("grava a tese pelo arquivo e so preenche tese vazia").
4. **"Testar pergunta" com texto vazio, só espaços ou sem nada parecido** — esperado: lista vazia com aviso "não acharia nenhuma FAQ", sem erro e sem chamar embeddings. Teste: Task 5 (backend "pergunta vazia…" e front "em branco não chama a API", "nenhuma FAQ").
5. **Sugestões filtradas por tipo no Centro com "Aprovar todas" à vista** — esperado: com filtro, "Aprovar todas" some (não aprova o que não se vê); tipo sem sugestão mostra aviso e "ver todas". Teste: Task 10 (NightCopilot "foco num tipo…").

---

## Mapa de arquivos

| Arquivo | Task | Responsabilidade |
|---|---|---|
| `tmp/intel-a3-harness/*` (não versionado) | 1, 12 | harness Vite (porta 6196, yaml), `shots.sh`, `telas-{antes,depois}.txt`, `comparar.mjs` |
| `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramonIntel.json` (novos) + `index.js` | 2 (cria), 4–10 (usam) | textos da A3, raiz `INTEL` |
| `app/javascript/dashboard/routes/dashboard/captain/pages/specs/IntelI18n.spec.js` (novo) | 2, 4 | trava do i18n novo + teses × arquivos do seed |
| `app/javascript/dashboard/components-next/captain/pageComponents/document/DocumentForm.vue` (+ spec novo) | 2 | modos Link / Colar texto |
| `app/javascript/dashboard/components-next/captain/assistant/{DocumentCard,DocumentFiltersBar}.vue`, `captain/documents/Index.vue` | 2 | cartão "Texto colado", filtro de fonte texto |
| `enterprise/app/controllers/api/v1/accounts/captain/documents_controller.rb`, `enterprise/app/views/api/v1/models/captain/_document.json.jbuilder` | 2 | fonte `text`, `text_document` |
| `app/javascript/dashboard/i18n/locale/{en,pt_BR}/integrations.json` | 2 | descrição do formulário, `SOURCE.TEXT` |
| `db/migrate/20261007500001_add_tese_to_captain_assistant_responses.rb` (novo), `db/schema.rb` | 3 | coluna `tese` |
| `enterprise/app/models/captain/assistant_response.rb` | 3 | `TESES`, validação, `normalizes` |
| `lib/ramon/inteligencia_seed.rb`, `lib/tasks/ramon_inteligencia.rake` | 3, 6 | tese pelo arquivo; rake `teses`; skill editada |
| `enterprise/app/controllers/api/v1/accounts/captain/assistant_responses_controller.rb`, `…/models/captain/_assistant_response.json.jbuilder` | 3 | filtro e gravação da tese |
| `app/javascript/dashboard/routes/dashboard/captain/responses/teses.js` (novo) | 4 | lista das teses no front |
| `app/javascript/dashboard/api/captain/response.js`, `captain/responses/{Index,Pending}.vue`, `components-next/captain/assistant/ResponseCard.vue`, `components-next/captain/pageComponents/response/ResponseForm.vue` (+ spec novo) | 4 | filtro, chip e campo de tese |
| `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb`, `enterprise/app/policies/captain/assistant_policy.rb`, `config/routes.rb` | 5 | `GET captain/assistants/:id/buscar_faq` |
| `app/javascript/dashboard/api/captain/assistant.js`, `captain/responses/TestarPergunta.vue` (novo, + spec) | 5 | cartão "Testar pergunta" |
| `db/migrate/20261007500002_add_edicao_to_captain_scenarios.rb` (novo) | 6 | `edited`, `seed_titulo` |
| `enterprise/app/controllers/api/v1/accounts/captain/scenarios_controller.rb`, `…/models/captain/_scenario.json.jbuilder` | 6 | todas as skills, edição marcada, desligar sem revalidar |
| `captain/assistants/scenarios/Index.vue`, `components-next/captain/assistant/ScenariosCard.vue` (+ spec) | 7 | abas Ligadas/Desligadas, chave, "Editada aqui" |
| `app/controllers/api/v1/accounts/captain_tool_runs_controller.rb`, `app/views/api/v1/accounts/captain_tool_runs/index.json.jbuilder` | 8 | nome do caso, nº da conversa, assistente |
| `captain/pages/execucoes.js` (novo), `captain/pages/Execucoes.vue` (+ spec novo) | 8, 9 | links, kit visual, abas |
| `app/models/agente_execucao.rb`, `app/controllers/api/v1/accounts/ramon_inteligencia_controller.rb` | 9 | `scope :de_hoje` (uma regra só) |
| `app/controllers/api/v1/accounts/ramon_agente_execucoes_controller.rb` (novo), `config/routes.rb`, `app/javascript/dashboard/api/ramonAgenteExecucoes.js` (novo), `captain/pages/ExecucoesAgente.vue` (novo, + spec) | 9 | aba Agente Claude |
| `captain/pages/VisaoGeral.vue` | 9, 10 | "Ver a trilha do agente"; chips de tipo clicáveis |
| `ramon/components/command/NightCopilot.vue` (+ spec), `ramon/pages/CommandCenter.vue` (+ spec) | 10 | `?sugestoes=` abre e filtra |
| `captain/pages/Inteligencia.story.vue`, `ramon/pages/CentroComando.story.vue` | 11 | fixtures e variantes dos prints |

---

### Task 1: Harness + prints "antes"

Roda **antes de qualquer mudança de código** (o "antes" é a base 079a04c).

**Files:**
- Create (não versionado — `tmp/` está no `.gitignore`): `tmp/intel-a3-harness/{index.html,ConversationBoxStub.vue,BackButtonStub.vue,main.js,vite.config.mts,shots.sh,telas-antes.txt}`
- Output: `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-07-inteligencia-a3\antes-*.png`

**Interfaces:**
- Produces: harness em `http://localhost:6196/?story=intel|centro&variant=<Título>&tema=claro|escuro`; `sh tmp/intel-a3-harness/shots.sh antes|depois` lê `telas-<fase>.txt` (linhas `story:Variante:arquivo:LxA`).

- [ ] **Step 1: Copiar a casca do harness** (Bash):

```bash
cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-intel-a3
mkdir -p tmp/intel-a3-harness
cp ../ramon-hub-wt-conteudo-tv-relatorios/tmp/harness/index.html ../ramon-hub-wt-conteudo-tv-relatorios/tmp/harness/ConversationBoxStub.vue tmp/intel-a3-harness/
cp tmp/intel-a3-harness/ConversationBoxStub.vue tmp/intel-a3-harness/BackButtonStub.vue
ls tmp/intel-a3-harness
```

Expected: `BackButtonStub.vue ConversationBoxStub.vue index.html`.

- [ ] **Step 2: `tmp/intel-a3-harness/vite.config.mts`** (Write):

```ts
// Harness local (não versionado): renderiza um *.story.vue sem a coleta SSR do
// Histoire (quebra neste repo com Node 22+). yaml: a story da Inteligência
// importa config/agents/tools.yml.
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import yaml from '@rollup/plugin-yaml';
import path from 'path';
import { aliases, vueOptions } from '../../vite.shared';

export default defineConfig({
  root: __dirname,
  plugins: [vue(vueOptions), yaml()],
  resolve: {
    alias: [
      {
        find: 'dashboard/components/widgets/conversation/ConversationBox.vue',
        replacement: path.resolve(__dirname, 'ConversationBoxStub.vue'),
      },
      {
        find: 'dashboard/components/widgets/BackButton.vue',
        replacement: path.resolve(__dirname, 'BackButtonStub.vue'),
      },
      ...Object.entries(aliases).map(([find, replacement]) => ({ find, replacement })),
    ],
  },
  css: { preprocessorOptions: { scss: { api: 'modern-compiler' } } },
  server: { port: 6196, fs: { strict: false } },
});
```

- [ ] **Step 3: `tmp/intel-a3-harness/main.js`** (Write):

```js
import { createApp, defineAsyncComponent, h } from 'vue';
import { setupVue3 } from '../../app/javascript/histoire.setup.ts';

const STORIES = {
  intel: () => import('dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue'),
  centro: () => import('dashboard/routes/dashboard/ramon/pages/CentroComando.story.vue'),
};
const params = new URLSearchParams(window.location.search);
if (params.get('tema') === 'escuro') document.documentElement.classList.add('dark');
const alvo = params.get('variant') || '';
const StoryFile = defineAsyncComponent(STORIES[params.get('story') || 'intel']);

const Story = { setup: (_, { slots }) => () => slots.default?.() };
const Variant = {
  props: { title: String, initState: Function },
  setup(props, { slots }) {
    const ativo = props.title === alvo;
    if (ativo && props.initState) props.initState();
    return () => (ativo ? slots.default?.() : null);
  },
};
// sem router no harness: router-link vira <a> (ou slot custom com navigate)
const RouterLink = {
  props: { to: [Object, String], custom: Boolean },
  setup(props, { slots }) {
    return () =>
      props.custom
        ? slots.default?.({ navigate: () => {}, href: '#' })
        : h('a', { href: '#' }, slots.default?.());
  },
};

const app = createApp({ render: () => h(StoryFile) });
app.component('RouterLink', RouterLink);
app.component('Story', Story);
app.component('Variant', Variant);
setupVue3({ app });
// fontes antes de montar: o print sai com Geist, não com o fallback
Promise.all(
  ['400 14px Geist', '600 14px Geist', '400 14px "Geist Mono"'].map(f => document.fonts.load(f))
).finally(() => app.mount('#app'));
```

- [ ] **Step 4: `tmp/intel-a3-harness/shots.sh`** (Write):

```sh
#!/bin/sh
# uso: sh tmp/intel-a3-harness/shots.sh antes|depois
# Lê tmp/intel-a3-harness/telas-<fase>.txt (story:Variante:arquivo:LxA) e grava
# PNGs em comercial/docs/mockups/2026-10-07-inteligencia-a3.
fase=$1
out="C:/Users/dudsl/RAdvogados/comercial/docs/mockups/2026-10-07-inteligencia-a3"
mkdir -p "$out"
chrome="/c/Program Files/Google/Chrome/Application/chrome.exe"
while IFS=: read -r story nome arq tam; do
  [ -z "$story" ] && continue
  q=$(echo "$nome" | sed 's/ /%20/g')
  for tema in claro escuro; do
    "$chrome" --headless=new --disable-gpu --hide-scrollbars --window-size=$tam \
      --virtual-time-budget=15000 --screenshot="$out/$fase-$tema-$arq.png" \
      "http://localhost:6196/?story=$story&variant=$q&tema=$tema" </dev/null >/dev/null 2>&1 &
  done
  wait
done < "tmp/intel-a3-harness/telas-$fase.txt"
ls "$out" | grep "^$fase"
```

(`</dev/null` no Chrome: sem ele o Chrome come as linhas do `while read`.)

- [ ] **Step 5: `tmp/intel-a3-harness/telas-antes.txt`** (Write):

```
intel:FAQs:faqs:1440,1100
intel:FAQs pendentes:faqs-pendentes:1440,900
intel:Documentos:documentos:1440,900
intel:Documentos novo:documentos-novo:1440,900
intel:Skills:skills:1440,1400
intel:Execucoes:execucoes:1440,1100
intel:Visao geral:visao-geral:1440,1900
centro:Centro copiloto aberto:centro-sugestoes:1440,1400
```

- [ ] **Step 6: Subir o harness** (Bash, `run_in_background: true`): `cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-intel-a3 && npx vite --config tmp/intel-a3-harness/vite.config.mts`. Conferir: `curl -s -o /dev/null -w "%{http_code}" "http://localhost:6196/?story=intel&variant=FAQs"` → `200`.

- [ ] **Step 7: Prints "antes"** — `cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-intel-a3 && sh tmp/intel-a3-harness/shots.sh antes`. Expected: 16 arquivos `antes-{claro,escuro}-{faqs,faqs-pendentes,documentos,documentos-novo,skills,execucoes,visao-geral,centro-sugestoes}.png`. Abrir com Read `antes-claro-faqs.png`, `antes-escuro-execucoes.png` e `antes-claro-centro-sugestoes.png`: tela desenhada, fonte Geist, nada de página branca (se vier branca: olhar o log do Vite em segundo plano — import que falta no alias é a causa típica).

- [ ] **Step 8: Sem commit** (nada versionado mudou). Registrar no relatório o caminho dos PNGs. Deixar o harness no ar (as Tasks 11–12 usam).

---

### Task 2: Documentos — "Colar texto" (+ arquivo i18n da A3)

**Files:**
- Create: `app/javascript/dashboard/i18n/locale/pt_BR/ramonIntel.json`, `app/javascript/dashboard/i18n/locale/en/ramonIntel.json`, `app/javascript/dashboard/routes/dashboard/captain/pages/specs/IntelI18n.spec.js`, `app/javascript/dashboard/components-next/captain/pageComponents/document/specs/DocumentForm.spec.js`
- Modify: `app/javascript/dashboard/i18n/locale/{en,pt_BR}/index.js`, `app/javascript/dashboard/i18n/locale/{en,pt_BR}/integrations.json`, `app/javascript/dashboard/components-next/captain/pageComponents/document/DocumentForm.vue`, `app/javascript/dashboard/components-next/captain/assistant/DocumentCard.vue`, `app/javascript/dashboard/components-next/captain/assistant/DocumentFiltersBar.vue`, `app/javascript/dashboard/routes/dashboard/captain/documents/Index.vue`, `enterprise/app/controllers/api/v1/accounts/captain/documents_controller.rb`, `enterprise/app/views/api/v1/models/captain/_document.json.jbuilder`
- Test: `spec/enterprise/controllers/api/v1/accounts/captain/documents_controller_spec.rb`

**Interfaces:**
- Consumes: `POST captain/documents` com `document[content]` + `document[name]` (já existe: `Captain::Document#set_external_link_for_text` cria `external_link = "TEXT: <nome>_<timestamp>"`, `status: available`, e o `after_commit` enfileira `Captain::Documents::ResponseBuilderJob` → FAQs **pendentes** desde a A1).
- Produces: arquivo i18n `ramonIntel.json` (raiz `INTEL`, **todas** as chaves da A3 — as tasks seguintes só usam); JSON do documento ganha `text_document: Boolean`; `GET captain/documents?source=text` devolve só os de texto colado.

- [ ] **Step 1: Spec Ruby (falha)** — acrescentar no fim de `spec/enterprise/controllers/api/v1/accounts/captain/documents_controller_spec.rb`, antes do `end` final do `RSpec.describe`:

```ruby
  describe 'texto colado (ramon, I-DO1)' do
    let(:texto) { { document: { assistant_id: assistant.id, name: 'Honorários', content: 'O honorário é 30% dos atrasados + 3 benefícios.' } } }

    it 'cria documento de texto ja disponivel, sem link, que gera FAQs' do
      expect do
        post "/api/v1/accounts/#{account.id}/captain/documents", params: texto, headers: admin.create_new_auth_token, as: :json
      end.to have_enqueued_job(Captain::Documents::ResponseBuilderJob)

      expect(response).to have_http_status(:success)
      expect(json_response).to include(name: 'Honorários', status: 'available', text_document: true)
      expect(json_response[:external_link]).to start_with('TEXT: Honorários_')
    end

    it 'filtra pela fonte texto colado' do
      post "/api/v1/accounts/#{account.id}/captain/documents", params: texto, headers: admin.create_new_auth_token, as: :json
      create(:captain_document, assistant: assistant, account: account, external_link: 'https://example.com/pagina')

      get "/api/v1/accounts/#{account.id}/captain/documents", params: { source: 'text' }, headers: admin.create_new_auth_token, as: :json

      expect(json_response[:payload].pluck(:name)).to eq(['Honorários'])
      expect(json_response[:payload].first[:text_document]).to be(true)
    end
  end
```

(Rastrear: `set_external_link_for_text` roda `on: :create` porque `content` presente e `external_link` em branco; `normalize_external_link` só tira `/` do fim; `enqueue_crawl_job` não roda — status `available`; `should_enqueue_response_builder?` = `saved_change_to_status?` verdadeiro na criação e `content.present?`. O limite de plano só vale com `CAPTAIN_CLOUD_PLAN_LIMITS` gravado — não é o caso aqui.)

- [ ] **Step 2: Backend** — em `documents_controller.rb`, no `apply_source_filter`, trocar

```ruby
    when 'pdf' then scope.pdf_documents
```

por

```ruby
    when 'pdf' then scope.pdf_documents
    # FORK-PONTO (ramon): texto colado (I-DO1) — documento 'TEXT:' sem link nem PDF.
    when 'text' then scope.where("captain_documents.external_link LIKE 'TEXT:%'")
```

Em `enterprise/app/views/api/v1/models/captain/_document.json.jbuilder`, depois de `json.pdf_document resource.pdf_document?`:

```ruby
json.text_document resource.text_document?
```

- [ ] **Step 3: Arquivo i18n da A3** — criar `app/javascript/dashboard/i18n/locale/pt_BR/ramonIntel.json` (Write; **todas** as chaves da fatia de uma vez):

```json
{
  "INTEL": {
    "TESE": {
      "auxilio-acidente": "Auxílio-acidente",
      "auxilio-doenca": "Auxílio-doença",
      "aposentadoria-invalidez": "Aposentadoria por invalidez",
      "bpc-loas": "BPC/LOAS",
      "acrescimo-25": "Acréscimo de 25%",
      "geral": "Geral"
    },
    "DOCUMENTOS": {
      "MODO_LINK": "Link de página",
      "MODO_TEXTO": "Colar texto",
      "TITULO_LABEL": "Título",
      "TITULO_PLACEHOLDER": "Ex.: Regras do BPC — resumo da equipe",
      "TITULO_ERRO": "Dê um título ao texto",
      "TEXTO_LABEL": "Texto",
      "TEXTO_PLACEHOLDER": "Cole aqui o texto (de um PDF, e-mail, manual...)",
      "TEXTO_ERRO": "Cole o texto (até 200 mil caracteres)",
      "TEXTO_COLADO": "Texto colado"
    },
    "FAQ": {
      "TESE_LABEL": "Tese",
      "TODAS_TESES": "Todas as teses",
      "SEM_TESE": "Sem tese",
      "TESTAR": {
        "TITULO": "Testar pergunta",
        "AJUDA": "Escreva como o lead perguntaria. A lista mostra as FAQs que o assistente acharia, na ordem em que ele recebe.",
        "PLACEHOLDER": "Ex.: posso trabalhar recebendo auxílio-acidente?",
        "BOTAO": "Testar",
        "NADA": "O assistente não acharia nenhuma FAQ para essa pergunta. Vale criar uma.",
        "ERRO": "Não foi possível testar agora. Tente de novo."
      }
    },
    "SKILLS": {
      "ABA_LIGADAS": "Ligadas ({n})",
      "ABA_DESLIGADAS": "Desligadas ({n})",
      "NENHUMA_DESLIGADA": "Nenhuma skill desligada.",
      "LIGAR": "Ligar ou desligar esta skill",
      "LIGADA": "Skill ligada: o assistente volta a usar.",
      "DESLIGADA": "Skill desligada: o assistente para de usar.",
      "EDITADA": "Editada aqui",
      "EDITADA_AJUDA": "Editada na tela: a carga automática das skills não muda nem desliga esta."
    },
    "EXECUCOES": {
      "ABA_FERRAMENTAS": "Ferramentas da IA",
      "ABA_AGENTE": "Agente Claude",
      "STATUS": {
        "ok": "OK",
        "erro": "Erro",
        "limite": "Limite",
        "cap": "Teto do dia",
        "timeout": "Tempo esgotado"
      },
      "CASO": "Caso #{id}",
      "CASO_NOME": "Caso #{id} · {nome}",
      "CONVERSA": "Conversa #{id}",
      "AGENTE": {
        "SUBTITULO": "Cada pedido feito ao agente numa nota: o que pediu, o que ele respondeu e fez, e quanto demorou. O custo fica em Uso e custo.",
        "HOJE": "Hoje: {n} de {teto} pedidos",
        "PROBLEMAS": "Com problema hoje: {n}",
        "VAZIO": "Nenhum pedido ao agente ainda.",
        "VER_RESULTADO": "ver o que o agente respondeu",
        "ESCONDER": "esconder",
        "SEM_RESUMO": "Sem resposta registrada.",
        "ACOES": "O que o agente fez",
        "NENHUMA_ACAO": "Nenhuma escrita (só respondeu na nota)."
      }
    },
    "VISAO_GERAL": {
      "VER_TRILHA": "Ver a trilha do agente"
    },
    "SUGESTOES": {
      "SO_TIPO": "Só: {tipo}",
      "VER_TODAS": "ver todas",
      "NENHUMA_DO_TIPO": "Nenhuma sugestão desse tipo agora."
    }
  }
}
```

e `app/javascript/dashboard/i18n/locale/en/ramonIntel.json` (mesma ordem):

```json
{
  "INTEL": {
    "TESE": {
      "auxilio-acidente": "Accident benefit",
      "auxilio-doenca": "Sickness benefit",
      "aposentadoria-invalidez": "Disability retirement",
      "bpc-loas": "BPC/LOAS",
      "acrescimo-25": "25% supplement",
      "geral": "General"
    },
    "DOCUMENTOS": {
      "MODO_LINK": "Page link",
      "MODO_TEXTO": "Paste text",
      "TITULO_LABEL": "Title",
      "TITULO_PLACEHOLDER": "E.g.: BPC rules — team summary",
      "TITULO_ERRO": "Give the text a title",
      "TEXTO_LABEL": "Text",
      "TEXTO_PLACEHOLDER": "Paste the text here (from a PDF, e-mail, manual...)",
      "TEXTO_ERRO": "Paste the text (up to 200 thousand characters)",
      "TEXTO_COLADO": "Pasted text"
    },
    "FAQ": {
      "TESE_LABEL": "Thesis",
      "TODAS_TESES": "All theses",
      "SEM_TESE": "No thesis",
      "TESTAR": {
        "TITULO": "Test a question",
        "AJUDA": "Write it the way a lead would ask. The list shows the FAQs the assistant would find, in the order it gets them.",
        "PLACEHOLDER": "E.g.: can I keep working while on accident benefit?",
        "BOTAO": "Test",
        "NADA": "The assistant would not find any FAQ for this question. Consider creating one.",
        "ERRO": "Could not test right now. Try again."
      }
    },
    "SKILLS": {
      "ABA_LIGADAS": "On ({n})",
      "ABA_DESLIGADAS": "Off ({n})",
      "NENHUMA_DESLIGADA": "No skill is off.",
      "LIGAR": "Turn this skill on or off",
      "LIGADA": "Skill on: the assistant uses it again.",
      "DESLIGADA": "Skill off: the assistant stops using it.",
      "EDITADA": "Edited here",
      "EDITADA_AJUDA": "Edited on screen: the automatic skill load does not change or turn off this one."
    },
    "EXECUCOES": {
      "ABA_FERRAMENTAS": "AI tools",
      "ABA_AGENTE": "Claude agent",
      "STATUS": {
        "ok": "OK",
        "erro": "Error",
        "limite": "Limit",
        "cap": "Daily cap",
        "timeout": "Timed out"
      },
      "CASO": "Case #{id}",
      "CASO_NOME": "Case #{id} · {nome}",
      "CONVERSA": "Conversation #{id}",
      "AGENTE": {
        "SUBTITULO": "Every request made to the agent in a note: what was asked, what it answered and did, and how long it took. Cost lives in Usage and cost.",
        "HOJE": "Today: {n} of {teto} requests",
        "PROBLEMAS": "With problems today: {n}",
        "VAZIO": "No agent requests yet.",
        "VER_RESULTADO": "show what the agent answered",
        "ESCONDER": "hide",
        "SEM_RESUMO": "No answer recorded.",
        "ACOES": "What the agent did",
        "NENHUMA_ACAO": "No writes (only answered in the note)."
      }
    },
    "VISAO_GERAL": {
      "VER_TRILHA": "See the agent trail"
    },
    "SUGESTOES": {
      "SO_TIPO": "Only: {tipo}",
      "VER_TODAS": "see all",
      "NENHUMA_DO_TIPO": "No suggestion of this kind right now."
    }
  }
}
```

Registrar nos dois `index.js` (Edit; em cada um):
- trocar `import ramonIaUso from './ramonIaUso.json';` por
  ```js
  import ramonIaUso from './ramonIaUso.json';
  import ramonIntel from './ramonIntel.json';
  ```
- trocar `  ...ramonIaUso,` por
  ```js
    ...ramonIaUso,
    ...ramonIntel,
  ```

- [ ] **Step 4: Trava do i18n novo** — criar `app/javascript/dashboard/routes/dashboard/captain/pages/specs/IntelI18n.spec.js`:

```js
import { createI18n } from 'vue-i18n/dist/vue-i18n.cjs.prod.js';
import en from 'dashboard/i18n/locale/en/ramonIntel.json';
import pt from 'dashboard/i18n/locale/pt_BR/ramonIntel.json';

const folhas = (obj, prefixo = '') =>
  Object.entries(obj).flatMap(([k, v]) =>
    typeof v === 'object'
      ? folhas(v, `${prefixo}${k}.`)
      : [[`${prefixo}${k}`, v]]
  );

describe('textos da Inteligência (A3)', () => {
  it('en e pt_BR têm as mesmas chaves, na mesma ordem', () => {
    expect(folhas(pt).map(([k]) => k)).toEqual(folhas(en).map(([k]) => k));
  });

  it.each([
    ['en', en],
    ['pt_BR', pt],
  ])('%s: sem @ | e chaves soltas', (_l, raiz) => {
    folhas(raiz).forEach(([chave, texto]) => {
      const semPlaceholders = texto.replace(/\{[a-z_]+\}/gi, '');
      expect([chave, /[@|{}]/.test(semPlaceholders)]).toEqual([chave, false]);
    });
  });

  // Trava de sintaxe: o compilador de PRODUÇÃO lança em "@" cru (linked message).
  it.each([
    ['en', en],
    ['pt_BR', pt],
  ])('%s: todas as chaves compilam no vue-i18n de produção', (loc, raiz) => {
    const i18n = createI18n({
      legacy: false,
      locale: loc,
      messages: { [loc]: raiz },
      missingWarn: false,
      fallbackWarn: false,
    });
    const params = { n: 1, id: 1, nome: 'x', teto: 30, tipo: 'x' };
    const erros = [];
    folhas(raiz).forEach(([chave]) => {
      try {
        if (i18n.global.t(chave, params) === chave) erros.push(chave);
      } catch (e) {
        erros.push(`${chave}: ${e.message}`);
      }
    });
    expect(erros).toEqual([]);
  });
});
```

- [ ] **Step 5: `integrations.json`** (Edit, nos dois locales):
  - `pt_BR` linha ~801: trocar o valor de `"FORM_DESCRIPTION": "Cole o link de uma página. A Inteligência lê a página e gera FAQs pendentes; o assistente só usa o que você aprovar."` por `"Cole o link de uma página ou um texto. A Inteligência lê e gera FAQs pendentes; o assistente só usa o que você aprovar."`; e trocar `"PDF": "PDF's"` por `"PDF": "PDF's",` + nova linha `"TEXT": "Texto colado"` (mesma indentação).
  - `en` linha ~801: `"Paste a page link. Captain reads the page and generates pending FAQs; the assistant only uses what you approve."` → `"Paste a page link or some text. Captain reads it and generates pending FAQs; the assistant only uses what you approve."`; `"PDF": "PDFs"` → `"PDF": "PDFs",` + `"TEXT": "Pasted text"`.

- [ ] **Step 6: Spec do formulário (falha)** — criar `app/javascript/dashboard/components-next/captain/pageComponents/document/specs/DocumentForm.spec.js`:

```js
import { mount, flushPromises } from '@vue/test-utils';
import DocumentForm from '../DocumentForm.vue';

// objeto simples (não ref): o form só lê uiFlags.value.creatingItem
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: { creatingItem: false } }),
}));

const montar = () => mount(DocumentForm, { props: { assistantId: 1 } });
const enviar = async wrapper => {
  await wrapper.find('form').trigger('submit');
  await flushPromises();
};

describe('DocumentForm.vue', () => {
  it('colar texto: manda título e texto, sem link', async () => {
    const wrapper = montar();
    await wrapper.find('[data-testid="documento-modo-texto"]').trigger('click');
    await wrapper.findAll('input')[0].setValue('Honorários');
    await wrapper
      .find('textarea')
      .setValue('O honorário é 30% dos atrasados + 3 benefícios.');
    await enviar(wrapper);

    const [dados] = wrapper.emitted('submit')[0];
    expect(dados.get('document[name]')).toBe('Honorários');
    expect(dados.get('document[content]')).toContain('30%');
    expect(dados.get('document[external_link]')).toBeNull();
    expect(dados.get('document[assistant_id]')).toBe('1');
  });

  it('colar texto sem título ou sem texto não envia', async () => {
    const wrapper = montar();
    await wrapper.find('[data-testid="documento-modo-texto"]').trigger('click');
    await wrapper.find('textarea').setValue('só o texto');
    await enviar(wrapper);
    expect(wrapper.emitted('submit')).toBeUndefined();
  });

  it('link continua igual: usa o link como nome quando o nome fica vazio', async () => {
    const wrapper = montar();
    await wrapper
      .findAll('input')[0]
      .setValue('https://ramonantonio.adv.br/bpc');
    await enviar(wrapper);

    const [dados] = wrapper.emitted('submit')[0];
    expect(dados.get('document[external_link]')).toBe(
      'https://ramonantonio.adv.br/bpc'
    );
    expect(dados.get('document[name]')).toBe('https://ramonantonio.adv.br/bpc');
    expect(dados.get('document[content]')).toBeNull();
  });
});
```

Run: `TZ=UTC npx vitest run app/javascript/dashboard/components-next/captain/pageComponents/document app/javascript/dashboard/routes/dashboard/captain/pages/specs/IntelI18n.spec.js --config vitest.local.config.ts` → DocumentForm FAIL (`documento-modo-texto` não existe); IntelI18n PASS.

- [ ] **Step 7: `DocumentForm.vue`** — substituir o arquivo inteiro (Write):

```vue
<script setup>
import { reactive, ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, url, maxLength } from '@vuelidate/validators';
import { useMapGetter } from 'dashboard/composables/store';

import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  ABA,
  ABA_ATIVA,
  ABA_INATIVA,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

const props = defineProps({
  assistantId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['submit', 'cancel']);

const { t } = useI18n();
const uiFlags = useMapGetter('captainDocuments/getUIFlags');

// ponytail: sem PDF — ia para a OpenAI (pdf_processing_service) e aqui só há
// DeepSeek. "Colar texto" (I-DO1) cobre o caso: copie o texto do PDF e cole.
// Mesmo teto do modelo (Captain::Document validates :content, maximum: 200_000).
const MAX_TEXTO = 200000;
const MODOS = ['link', 'texto'];

const modo = ref('link');
const state = reactive({ name: '', url: '', texto: '' });
const ehTexto = computed(() => modo.value === 'texto');
const rules = computed(() =>
  ehTexto.value
    ? {
        name: { required },
        texto: { required, maxLength: maxLength(MAX_TEXTO) },
      }
    : { url: { required, url } }
);
const v$ = useVuelidate(rules, state);

const isLoading = computed(() => uiFlags.value.creatingItem);
const urlError = computed(() =>
  v$.value.url?.$error ? t('CAPTAIN.DOCUMENTS.FORM.URL.ERROR') : ''
);
const tituloError = computed(() =>
  v$.value.name?.$error ? t('INTEL.DOCUMENTOS.TITULO_ERRO') : ''
);
const textoError = computed(() =>
  v$.value.texto?.$error ? t('INTEL.DOCUMENTOS.TEXTO_ERRO') : ''
);
const rotuloModo = item =>
  item === 'texto'
    ? t('INTEL.DOCUMENTOS.MODO_TEXTO')
    : t('INTEL.DOCUMENTOS.MODO_LINK');

const trocarModo = novo => {
  modo.value = novo;
  v$.value.$reset();
};

const handleSubmit = async () => {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) return;

  const formData = new FormData();
  formData.append('document[assistant_id]', props.assistantId);
  if (ehTexto.value) {
    formData.append('document[name]', state.name.trim());
    formData.append('document[content]', state.texto);
  } else {
    formData.append('document[external_link]', state.url);
    formData.append('document[name]', state.name || state.url);
  }
  emit('submit', formData);
};
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="handleSubmit">
    <nav class="flex gap-1 border-b border-n-weak">
      <button
        v-for="item in MODOS"
        :key="item"
        type="button"
        :data-testid="`documento-modo-${item}`"
        :class="[ABA, modo === item ? ABA_ATIVA : ABA_INATIVA]"
        @click="trocarModo(item)"
      >
        {{ rotuloModo(item) }}
      </button>
    </nav>

    <template v-if="ehTexto">
      <Input
        v-model="state.name"
        :label="t('INTEL.DOCUMENTOS.TITULO_LABEL')"
        :placeholder="t('INTEL.DOCUMENTOS.TITULO_PLACEHOLDER')"
        :message="tituloError"
        :message-type="tituloError ? 'error' : 'info'"
      />
      <TextArea
        v-model="state.texto"
        :label="t('INTEL.DOCUMENTOS.TEXTO_LABEL')"
        :placeholder="t('INTEL.DOCUMENTOS.TEXTO_PLACEHOLDER')"
        :max-length="MAX_TEXTO"
        show-character-count
        resize
        min-height="12rem"
        max-height="20rem"
        :message="textoError"
        :message-type="textoError ? 'error' : 'info'"
      />
    </template>
    <template v-else>
      <Input
        v-model="state.url"
        :label="t('CAPTAIN.DOCUMENTS.FORM.URL.LABEL')"
        :placeholder="t('CAPTAIN.DOCUMENTS.FORM.URL.PLACEHOLDER')"
        :message="urlError"
        :message-type="urlError ? 'error' : 'info'"
      />
      <Input
        v-model="state.name"
        :label="t('CAPTAIN.DOCUMENTS.FORM.NAME.LABEL')"
        :placeholder="t('CAPTAIN.DOCUMENTS.FORM.NAME.PLACEHOLDER')"
      />
    </template>

    <div class="flex gap-3 justify-between items-center w-full">
      <Button
        type="button"
        variant="faded"
        color="slate"
        :label="t('CAPTAIN.FORM.CANCEL')"
        class="w-full bg-n-alpha-2 text-n-blue-11 hover:bg-n-alpha-3"
        @click="emit('cancel')"
      />
      <Button
        type="submit"
        :label="t('CAPTAIN.FORM.CREATE')"
        class="w-full"
        :is-loading="isLoading"
        :disabled="isLoading"
      />
    </div>
  </form>
</template>
```

- [ ] **Step 8: Cartão e filtro** — `DocumentCard.vue` (Edit):
  - nos `defineProps`, depois do bloco `pdfDocument: { type: Boolean, default: false },` acrescentar `textDocument: { type: Boolean, default: false },`;
  - trocar
    ```js
    const canSync = computed(
      () => canManage.value && !isPdf.value && isAvailable.value
    );
    ```
    por
    ```js
    // texto colado (I-DO1) não tem página para sincronizar
    const canSync = computed(
      () =>
        canManage.value && !isPdf.value && !props.textDocument && isAvailable.value
    );
    ```
  - trocar `const showSyncStatus = computed(() => !isPdf.value);` por `const showSyncStatus = computed(() => !isPdf.value && !props.textDocument);`;
  - trocar os computeds `displayLink` e `linkIcon` por:
    ```js
    const displayLink = computed(() => {
      if (props.textDocument) return t('INTEL.DOCUMENTOS.TEXTO_COLADO');
      return isPdf.value
        ? formatDocumentLink(props.externalLink)
        : getDocumentDisplayPath(props.externalLink);
    });
    const linkIcon = computed(() => {
      if (props.textDocument) return 'i-lucide-text';
      return isPdf.value ? 'i-ph-file-pdf' : 'i-ph-link-simple';
    });
    ```
  (`TEXT: …` não é link http → o template já cai no `<span v-else>`; sem status de sincronização, o cartão mostra a data de criação.)

  `documents/Index.vue` (Edit): trocar `          :pdf-document="doc.pdf_document"` por
  ```html
            :pdf-document="doc.pdf_document"
            :text-document="doc.text_document"
  ```

  `DocumentFiltersBar.vue` (Edit): trocar `      { labelKey: 'SOURCE.PDF', value: 'pdf', icon: 'i-lucide-file-text' },` por `      { labelKey: 'SOURCE.TEXT', value: 'text', icon: 'i-lucide-text' },` (PDF não funciona aqui — Decisão N6).

- [ ] **Step 9: Rodar** — `TZ=UTC npx vitest run app/javascript/dashboard/components-next/captain app/javascript/dashboard/routes/dashboard/captain/pages/specs/IntelI18n.spec.js --config vitest.local.config.ts` → PASS (DocumentForm 3, IntelI18n 5, ScenariosCard e ConnectInboxForm seguem verdes). `./node_modules/.bin/eslint app/javascript/dashboard/components-next/captain/pageComponents/document app/javascript/dashboard/components-next/captain/assistant/DocumentCard.vue app/javascript/dashboard/components-next/captain/assistant/DocumentFiltersBar.vue app/javascript/dashboard/routes/dashboard/captain/documents/Index.vue app/javascript/dashboard/routes/dashboard/captain/pages/specs/IntelI18n.spec.js` → sem `error`.

- [ ] **Step 10: Commit**

```bash
git add app/javascript/dashboard/i18n/locale/en/ramonIntel.json app/javascript/dashboard/i18n/locale/pt_BR/ramonIntel.json app/javascript/dashboard/i18n/locale/en/index.js app/javascript/dashboard/i18n/locale/pt_BR/index.js app/javascript/dashboard/i18n/locale/en/integrations.json app/javascript/dashboard/i18n/locale/pt_BR/integrations.json app/javascript/dashboard/routes/dashboard/captain/pages/specs/IntelI18n.spec.js app/javascript/dashboard/components-next/captain/pageComponents/document/DocumentForm.vue app/javascript/dashboard/components-next/captain/pageComponents/document/specs/DocumentForm.spec.js app/javascript/dashboard/components-next/captain/assistant/DocumentCard.vue app/javascript/dashboard/components-next/captain/assistant/DocumentFiltersBar.vue app/javascript/dashboard/routes/dashboard/captain/documents/Index.vue enterprise/app/controllers/api/v1/accounts/captain/documents_controller.rb enterprise/app/views/api/v1/models/captain/_document.json.jbuilder spec/enterprise/controllers/api/v1/accounts/captain/documents_controller_spec.rb
git commit -m "feat(ia): Documentos aceita colar texto (vira FAQs pendentes) e filtra por texto colado" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 3: FAQ por tese — coluna, seed e API

**Files:**
- Create: `db/migrate/20261007500001_add_tese_to_captain_assistant_responses.rb`
- Modify: `db/schema.rb`, `enterprise/app/models/captain/assistant_response.rb`, `lib/ramon/inteligencia_seed.rb`, `lib/tasks/ramon_inteligencia.rake`, `enterprise/app/controllers/api/v1/accounts/captain/assistant_responses_controller.rb`, `enterprise/app/views/api/v1/models/captain/_assistant_response.json.jbuilder`
- Test: `spec/lib/tasks/rake/task_ramon_inteligencia_spec.rb`, `spec/enterprise/controllers/api/v1/accounts/captain/assistant_responses_controller_spec.rb`

**Interfaces:**
- Produces: `Captain::AssistantResponse::TESES = %w[auxilio-acidente auxilio-doenca aposentadoria-invalidez bpc-loas acrescimo-25 geral]` (= nomes dos arquivos `db/seeds/ramon/inteligencia/faq/*.md`); JSON da FAQ ganha `tese: String|null`; `GET captain/assistant_responses?tese=<tese>|sem`; `PATCH/POST` aceitam `assistant_response[tese]` ('' vira nulo; tese fora da lista → 422); `Ramon::InteligenciaSeed#preencher_teses → Integer`; `rake ramon:inteligencia:teses[account_id]`.

- [ ] **Step 1: Specs (falham)** — em `spec/lib/tasks/rake/task_ramon_inteligencia_spec.rb`, dentro do `describe 'ramon:inteligencia:seed'`, depois do último `it`:

```ruby
    it 'grava a tese pelo arquivo e so preenche tese vazia (editada ou nao)' do
      rodar
      arquivos = Dir[Rails.root.join('db/seeds/ramon/inteligencia/faq/*.md')].map { |arquivo| File.basename(arquivo, '.md') }
      expect(arquivos).to match_array(Captain::AssistantResponse::TESES)
      expect(atendimento.responses.where(tese: nil)).to be_empty

      editada = atendimento.responses.find_by!(tese: 'bpc-loas')
      editada.update!(answer: 'Editada pelo Eduardo', tese: nil)
      trocada = atendimento.responses.find_by!(tese: 'geral')
      trocada.update!(tese: 'auxilio-doenca')
      rodar

      expect(editada.reload).to have_attributes(answer: 'Editada pelo Eduardo', tese: 'bpc-loas')
      expect(trocada.reload.tese).to eq('auxilio-doenca')
    end

    it 'rake de teses so preenche a tese que falta e nao mexe em mais nada' do
      rodar
      faq = atendimento.responses.find_by!(tese: 'acrescimo-25')
      faq.update_columns(tese: nil, answer: 'Resposta mexida') # rubocop:disable Rails/SkipsModelValidations
      teses = described_class['ramon:inteligencia:teses']
      teses.reenable

      expect { teses.invoke(account.id.to_s) }.to output(/faq_com_tese_preenchida: 1/).to_stdout
      expect(faq.reload).to have_attributes(tese: 'acrescimo-25', answer: 'Resposta mexida')
    end
```

(Rastrear: `editada.update!(answer: …)` marca `edited` (`mark_as_edited`); a tese escolhida em `trocada` não marca `edited` — por isso o seed precisa de `faq.tese || tese`, senão sobrescreveria.)

Em `spec/enterprise/controllers/api/v1/accounts/captain/assistant_responses_controller_spec.rb`, antes do `end` final do `RSpec.describe`:

```ruby
  describe 'tese da FAQ (ramon, I-FQ1)' do
    let(:url) { "/api/v1/accounts/#{account.id}/captain/assistant_responses" }

    before do
      create(:captain_assistant_response, assistant: assistant, account: account, question: 'BPC?', tese: 'bpc-loas')
      create(:captain_assistant_response, assistant: assistant, account: account, question: 'Geral?', tese: 'geral')
      create(:captain_assistant_response, assistant: assistant, account: account, question: 'Sem?')
    end

    it 'filtra por tese e por sem tese' do
      get url, params: { tese: 'bpc-loas' }, headers: agent.create_new_auth_token, as: :json
      expect(json_response[:payload].pluck(:question)).to eq(['BPC?'])
      expect(json_response[:payload].first[:tese]).to eq('bpc-loas')

      get url, params: { tese: 'sem' }, headers: agent.create_new_auth_token, as: :json
      expect(json_response[:payload].pluck(:question)).to eq(['Sem?'])
    end

    it 'grava a tese escolhida na tela; vazio vira sem tese; tese desconhecida e recusada' do
      faq = assistant.responses.find_by!(question: 'Sem?')
      patch "#{url}/#{faq.id}", params: { assistant_response: { tese: 'auxilio-acidente' } }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(faq.reload.tese).to eq('auxilio-acidente')

      patch "#{url}/#{faq.id}", params: { assistant_response: { tese: '' } }, headers: admin.create_new_auth_token, as: :json
      expect(faq.reload.tese).to be_nil

      patch "#{url}/#{faq.id}", params: { assistant_response: { tese: 'trabalhista' } }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
```

- [ ] **Step 2: Migração + schema** — criar `db/migrate/20261007500001_add_tese_to_captain_assistant_responses.rb`:

```ruby
# FAQ por tese (I-FQ1): a tese que já está no nome do arquivo do seed
# (db/seeds/ramon/inteligencia/faq/<tese>.md) passa a ficar na FAQ — filtro e
# etiqueta na tela. Nula = sem tese (ex.: FAQ gerada de documento).
class AddTeseToCaptainAssistantResponses < ActiveRecord::Migration[7.1]
  def change
    add_column :captain_assistant_responses, :tese, :string
  end
end
```

`db/schema.rb` (Edit): `ActiveRecord::Schema[7.1].define(version: 2026_10_06_400001) do` → `ActiveRecord::Schema[7.1].define(version: 2026_10_07_500001) do`; no bloco `create_table "captain_assistant_responses"`, trocar `    t.boolean "edited", default: false, null: false` (a 1ª ocorrência — a do bloco de `captain_assistant_responses`, logo antes de `t.index ["account_id"], name: "index_captain_assistant_responses_on_account_id"`) por

```ruby
    t.boolean "edited", default: false, null: false
    t.string "tese"
```

(Conferir com `grep -n 't.string "tese"' -B3 -A2 db/schema.rb` que caiu no bloco certo.)

- [ ] **Step 3: Modelo** — em `enterprise/app/models/captain/assistant_response.rb` (Edit), trocar

```ruby
  validates :question, presence: true
  validates :answer, presence: true
```

por

```ruby
  # FORK-PONTO (ramon): tese da FAQ (I-FQ1) = nome do arquivo do seed; nil = sem tese.
  # Mesma lista e ordem de captain/responses/teses.js (front).
  TESES = %w[auxilio-acidente auxilio-doenca aposentadoria-invalidez bpc-loas acrescimo-25 geral].freeze

  validates :question, presence: true
  validates :answer, presence: true
  validates :tese, inclusion: { in: TESES }, allow_nil: true
  normalizes :tese, with: ->(valor) { valor.presence }
```

- [ ] **Step 4: Seed** — em `lib/ramon/inteligencia_seed.rb` (Edit):
  - trocar `    Dir[DIR.join('faq', '*.md').to_s].each { |arquivo| seed_faq(arquivo) }` por `    faqs_do_seed.each { |tese, pergunta, resposta| upsert_faq(pergunta, resposta, tese) }`;
  - logo depois do `end` do `run` (antes de `  private`), acrescentar:

```ruby

  # So preenche a tese das FAQs do seed que ainda nao tem (rake ramon:inteligencia:teses).
  # Nao toca em resposta, status nem nas skills — pode rodar em producao sem medo.
  # @return [Integer] quantas FAQs ganharam tese
  def preencher_teses
    faqs_do_seed.sum do |tese, pergunta, _resposta|
      atendimento.responses.where(question: pergunta, tese: nil).update_all(tese: tese) # rubocop:disable Rails/SkipsModelValidations
    end
  end
```

  - trocar o método `seed_faq` inteiro e o `upsert_faq` inteiro por:

```ruby
  # [[tese, pergunta, resposta], ...] — tese = nome do arquivo (faq/<tese>.md).
  def faqs_do_seed
    Dir[DIR.join('faq', '*.md').to_s].sort.flat_map do |arquivo|
      tese = File.basename(arquivo, '.md')
      File.read(arquivo).sub(FRONT_MATTER, '').split(/^## /).drop(1).map do |bloco|
        pergunta, resposta = bloco.split("\n", 2)
        [tese, pergunta.strip, resposta.to_s.strip]
      end
    end
  end

  # Tese: so preenche se vazia (a escolhida na tela vale, editada ou nao).
  def upsert_faq(pergunta, resposta, tese)
    faq = atendimento.responses.find_or_initialize_by(question: pergunta)
    if faq.persisted? && faq.edited?
      faq.update_column(:tese, tese) if faq.tese.nil? # rubocop:disable Rails/SkipsModelValidations
      return @contagem[:faq_puladas_editadas] += 1
    end

    @contagem[faq.new_record? ? :faq_criadas : :faq_atualizadas] += 1
    faq.update!(answer: resposta, status: :approved, documentable: nil, tese: faq.tese || tese)
    # O before_validation marca edited=true em qualquer update; seed nao conta como edicao na UI.
    faq.update_column(:edited, false) if faq.edited? # rubocop:disable Rails/SkipsModelValidations
  end
```

  - no comentário do topo, trocar `# (db/seeds/ramon/inteligencia/assistentes.yml) e FAQ aprovada (faq/*.md).` por `# (db/seeds/ramon/inteligencia/assistentes.yml) e FAQ aprovada (faq/<tese>.md, tese = nome do arquivo).`

- [ ] **Step 5: Rake só-de-teses** — em `lib/tasks/ramon_inteligencia.rake`, depois do `task :seed … end`:

```ruby

    desc 'Preenche so a tese das FAQs do seed que ainda nao tem (nao mexe em mais nada). ' \
         'Uso: rake ramon:inteligencia:teses[account_id]'
    task :teses, [:account_id] => :environment do |_task, args|
      raise ArgumentError, 'Uso: rake ramon:inteligencia:teses[account_id]' if args[:account_id].blank?

      total = Ramon::InteligenciaSeed.new(Account.find(args[:account_id])).preencher_teses
      puts "faq_com_tese_preenchida: #{total}"
    end
```

- [ ] **Step 6: API** — em `assistant_responses_controller.rb` (Edit):
  - no `apply_filters`, trocar a última linha `    base_query` (antes do `end` do método) por
    ```ruby
        filtrar_tese(base_query)
    ```
  - logo depois do `end` de `apply_filters`, acrescentar:
    ```ruby

      # ramon: filtro por tese (I-FQ1); 'sem' = FAQ sem tese.
      def filtrar_tese(scope)
        return scope if permitted_params[:tese].blank?

        scope.where(tese: permitted_params[:tese] == 'sem' ? nil : permitted_params[:tese])
      end
    ```
  - `params.permit(:id, :assistant_id, :page, :document_id, :account_id, :status, :search)` → `params.permit(:id, :assistant_id, :page, :document_id, :account_id, :status, :search, :tese)`;
  - em `response_params`, trocar `      :status` por `      :status,` + nova linha `      :tese`.

  Em `_assistant_response.json.jbuilder`, depois de `json.edited resource.edited`: `json.tese resource.tese`.

- [ ] **Step 7: Rastrear à mão** (sem Ruby local): `faqs_do_seed` lê os 6 arquivos (`geral.md` tem `tese: ~` no cabeçalho, mas a tese vem do nome → `'geral'`); `TESES` bate com os 6 nomes; `apply_filters` continua com 4 `if` (Cyclomatic 5) e o `filtrar_tese` tem 2 desvios; `update!` com tese de arquivo desconhecido levantaria `RecordInvalid` (guarda boa: arquivo novo exige linha em `TESES`). Linhas ≤ 150.

- [ ] **Step 8: Commit**

```bash
git add db/migrate/20261007500001_add_tese_to_captain_assistant_responses.rb db/schema.rb enterprise/app/models/captain/assistant_response.rb lib/ramon/inteligencia_seed.rb lib/tasks/ramon_inteligencia.rake enterprise/app/controllers/api/v1/accounts/captain/assistant_responses_controller.rb enterprise/app/views/api/v1/models/captain/_assistant_response.json.jbuilder spec/lib/tasks/rake/task_ramon_inteligencia_spec.rb spec/enterprise/controllers/api/v1/accounts/captain/assistant_responses_controller_spec.rb
git commit -m "feat(ia): FAQ guarda a tese do arquivo do seed, filtra por tese e rake que só preenche teses" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 4: FAQ por tese — filtro, etiqueta e campo na tela

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/captain/responses/teses.js`, `app/javascript/dashboard/components-next/captain/pageComponents/response/specs/ResponseForm.spec.js`
- Modify: `app/javascript/dashboard/api/captain/response.js`, `app/javascript/dashboard/routes/dashboard/captain/responses/Index.vue`, `app/javascript/dashboard/routes/dashboard/captain/responses/Pending.vue`, `app/javascript/dashboard/components-next/captain/assistant/ResponseCard.vue`, `app/javascript/dashboard/components-next/captain/pageComponents/response/ResponseForm.vue`, `app/javascript/dashboard/routes/dashboard/captain/pages/specs/IntelI18n.spec.js`

**Interfaces:**
- Consumes: Task 3 (`tese` no JSON, `?tese=`, `assistant_response[tese]`); Task 2 (`INTEL.TESE.*`, `INTEL.FAQ.*`).
- Produces: `TESES` e `SEM_TESE` em `captain/responses/teses.js`; `CaptainResponseAPI.get({ ..., tese })`; prop `tese` no `ResponseCard`; `ResponseForm` emite `{ question, answer, tese: String|null }`.

- [ ] **Step 1: `teses.js`** (Write):

```js
// Teses das FAQs (I-FQ1) — mesma lista e ordem de Captain::AssistantResponse::TESES
// (= arquivos db/seeds/ramon/inteligencia/faq/<tese>.md; a trava IntelI18n confere).
export const TESES = [
  'auxilio-acidente',
  'auxilio-doenca',
  'aposentadoria-invalidez',
  'bpc-loas',
  'acrescimo-25',
  'geral',
];
// Valor do filtro para as FAQs sem tese (ex.: geradas de documento).
export const SEM_TESE = 'sem';
```

- [ ] **Step 2: Specs (falham)** — em `IntelI18n.spec.js`, acrescentar depois dos imports (no topo do módulo — o `import.meta.glob` é transformado estaticamente pelo Vite):

```js
import { TESES } from '../../responses/teses';

// 8 níveis acima de pages/specs = raiz do repo (só lista os nomes; não lê o conteúdo)
const SEED = import.meta.glob(
  '../../../../../../../../db/seeds/ramon/inteligencia/faq/*.md'
);
```

e, dentro do `describe`, depois do 1º `it`:

```js
  it('cada tese tem rótulo e a lista bate com os arquivos do seed', () => {
    const arquivos = Object.keys(SEED)
      .map(caminho => caminho.split('/').pop().replace('.md', ''))
      .sort();
    expect([...TESES].sort()).toEqual(arquivos);
    TESES.forEach(tese => {
      expect([tese, Boolean(pt.INTEL.TESE[tese])]).toEqual([tese, true]);
      expect([tese, Boolean(en.INTEL.TESE[tese])]).toEqual([tese, true]);
    });
  });
```

Criar `app/javascript/dashboard/components-next/captain/pageComponents/response/specs/ResponseForm.spec.js`:

```js
import { mount, flushPromises } from '@vue/test-utils';
import ResponseForm from '../ResponseForm.vue';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: { creatingItem: false } }),
}));

const montar = response =>
  mount(ResponseForm, {
    props: { mode: 'edit', response },
    global: { stubs: { Editor: true } },
  });
const enviar = async wrapper => {
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  return wrapper.emitted('submit')[0][0];
};

describe('ResponseForm.vue — tese (I-FQ1)', () => {
  it('mostra a tese da FAQ e manda nulo quando vira "Sem tese"', async () => {
    const wrapper = montar({
      question: 'O que é o BPC?',
      answer: 'Benefício assistencial.',
      tese: 'bpc-loas',
    });
    const campo = wrapper.find('[data-testid="faq-tese"]');
    expect(campo.element.value).toBe('bpc-loas');
    await campo.setValue('');
    expect(await enviar(wrapper)).toEqual({
      question: 'O que é o BPC?',
      answer: 'Benefício assistencial.',
      tese: null,
    });
  });

  it('FAQ sem tese pode ganhar uma', async () => {
    const wrapper = montar({ question: 'Horário?', answer: '8h às 18h.', tese: null });
    await wrapper.find('[data-testid="faq-tese"]').setValue('geral');
    expect((await enviar(wrapper)).tese).toBe('geral');
  });
});
```

Run: `TZ=UTC npx vitest run app/javascript/dashboard/components-next/captain/pageComponents/response app/javascript/dashboard/routes/dashboard/captain/pages/specs/IntelI18n.spec.js --config vitest.local.config.ts` → ResponseForm FAIL (sem `faq-tese`); IntelI18n PASS (teses.js já existe).

- [ ] **Step 3: `ResponseForm.vue`** (Edit):
  - depois de `import Button from 'dashboard/components-next/button/Button.vue';` acrescentar
    ```js
    import {
      ROTULO,
      SELECT,
    } from 'dashboard/routes/dashboard/ramon/helpers/ui';
    import { TESES } from 'dashboard/routes/dashboard/captain/responses/teses';
    ```
  - `const initialState = { question: '', answer: '', };` → acrescentar `tese: '',` (o objeto passa a ter `question`, `answer`, `tese`);
  - `prepareDocumentDetails` passa a devolver `({ question: state.question, answer: state.answer, tese: state.tese || null })`;
  - em `updateStateFromResponse`, trocar `const { question, answer } = response;` + `Object.assign(state, { question, answer, });` por
    ```js
      const { question, answer, tese } = response;
      Object.assign(state, { question, answer, tese: tese || '' });
    ```
  - no template, depois do `<Input v-model="state.question" … />`:
    ```html
    <label :class="ROTULO">
      {{ t('INTEL.FAQ.TESE_LABEL') }}
      <select v-model="state.tese" data-testid="faq-tese" :class="SELECT">
        <option value="">{{ t('INTEL.FAQ.SEM_TESE') }}</option>
        <option v-for="tese in TESES" :key="tese" :value="tese">
          {{ t(`INTEL.TESE.${tese}`) }}
        </option>
      </select>
    </label>
    ```

- [ ] **Step 4: Cartão** — `ResponseCard.vue` (Edit):
  - nos `defineProps`, depois do bloco `documentable: { type: Object, default: null, },` acrescentar `tese: { type: String, default: null },`;
  - depois de `import Icon from 'dashboard/components-next/icon/Icon.vue';` acrescentar `import { CHIP, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';`;
  - no template, trocar `        <div class="inline-flex items-center gap-3 min-w-0">` por
    ```html
            <div class="inline-flex items-center gap-3 min-w-0">
              <span
                v-if="tese"
                data-testid="faq-tese-chip"
                class="shrink-0"
                :class="[CHIP, TOM.blue]"
              >
                {{ t(`INTEL.TESE.${tese}`) }}
              </span>
    ```

  `Pending.vue` e `Index.vue` (responses): no `<ResponseCard`, trocar `:documentable="response.documentable"` por
  ```html
            :documentable="response.documentable"
            :tese="response.tese"
  ```

- [ ] **Step 5: Filtro na lista** — `api/captain/response.js` (Edit): `get({ page = 1, search, assistantId, documentId, status } = {})` → `get({ page = 1, search, assistantId, documentId, status, tese } = {})` e, em `params`, depois de `status,` acrescentar `tese,`.

  `responses/Index.vue` (Edit):
  - depois de `import ResponsePageEmptyState …;` acrescentar
    ```js
    import { SELECT } from 'dashboard/routes/dashboard/ramon/helpers/ui';
    import { TESES, SEM_TESE } from './teses';
    ```
  - depois de `const searchQuery = ref('');` acrescentar `const teseFiltro = ref('');`;
  - trocar o `updateURLWithFilters` inteiro por
    ```js
    const updateURLWithFilters = (page, search, tese) => {
      const query = { page: page || 1 };
      if (search) query.search = search;
      if (tese) query.tese = tese;
      router.replace({ query });
    };
    ```
  - em `fetchResponses`, depois do bloco `if (searchQuery.value) { … }` acrescentar `if (teseFiltro.value) filterParams.tese = teseFiltro.value;` e trocar `updateURLWithFilters(page, searchQuery.value);` por `updateURLWithFilters(page, searchQuery.value, teseFiltro.value);`;
  - em `initializeFromURL`, depois do `if (route.query.search) { … }` acrescentar `if (route.query.tese) teseFiltro.value = route.query.tese;`;
  - no template `#search`, trocar o `<Input … @input="debouncedSearch" />` por
    ```html
            <div class="flex items-center gap-2">
              <Input
                v-model="searchQuery"
                :placeholder="$t('CAPTAIN.RESPONSES.SEARCH_PLACEHOLDER')"
                class="w-64"
                size="sm"
                type="search"
                autofocus
                @input="debouncedSearch"
              />
              <select
                v-model="teseFiltro"
                data-testid="faq-filtro-tese"
                class="!w-52"
                :class="SELECT"
                @change="fetchResponses(1)"
              >
                <option value="">{{ $t('INTEL.FAQ.TODAS_TESES') }}</option>
                <option v-for="tese in TESES" :key="tese" :value="tese">
                  {{ $t(`INTEL.TESE.${tese}`) }}
                </option>
                <option :value="SEM_TESE">{{ $t('INTEL.FAQ.SEM_TESE') }}</option>
              </select>
            </div>
    ```

- [ ] **Step 6: Rodar** — `TZ=UTC npx vitest run app/javascript/dashboard/components-next/captain app/javascript/dashboard/routes/dashboard/captain --config vitest.local.config.ts` → PASS. `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/responses app/javascript/dashboard/components-next/captain/assistant/ResponseCard.vue app/javascript/dashboard/components-next/captain/pageComponents/response app/javascript/dashboard/api/captain/response.js app/javascript/dashboard/routes/dashboard/captain/pages/specs/IntelI18n.spec.js` → sem `error`.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/responses/teses.js app/javascript/dashboard/routes/dashboard/captain/responses/Index.vue app/javascript/dashboard/routes/dashboard/captain/responses/Pending.vue app/javascript/dashboard/api/captain/response.js app/javascript/dashboard/components-next/captain/assistant/ResponseCard.vue app/javascript/dashboard/components-next/captain/pageComponents/response/ResponseForm.vue app/javascript/dashboard/components-next/captain/pageComponents/response/specs/ResponseForm.spec.js app/javascript/dashboard/routes/dashboard/captain/pages/specs/IntelI18n.spec.js
git commit -m "feat(ia): FAQs com etiqueta, filtro e campo de tese" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 5: "Testar pergunta" nas FAQs

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/captain/responses/TestarPergunta.vue`, `app/javascript/dashboard/routes/dashboard/captain/responses/specs/TestarPergunta.spec.js`
- Modify: `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb`, `enterprise/app/policies/captain/assistant_policy.rb`, `config/routes.rb`, `app/javascript/dashboard/api/captain/assistant.js`, `app/javascript/dashboard/routes/dashboard/captain/responses/Index.vue`
- Test: `spec/enterprise/controllers/api/v1/accounts/captain/assistants_controller_spec.rb`

**Interfaces:**
- Consumes: `Captain::AssistantResponse.search` (busca textual `portuguese`, até 5, já usada por `Captain::Tools::FaqLookupTool#perform`: `@assistant.responses.approved.search(query)`); `tese` (Task 3); `INTEL.FAQ.TESTAR.*`, `INTEL.TESE.*` (Task 2).
- Produces: `GET /api/v1/accounts/:account_id/captain/assistants/:id/buscar_faq?q=<texto>` → `{ payload: [{ id, question, answer, tese }] }` (admin e agente); `CaptainAssistantAPI.buscarFaq(assistantId, pergunta)`.

- [ ] **Step 1: Spec Ruby (falha)** — em `assistants_controller_spec.rb`, antes do `end` final do `RSpec.describe`:

```ruby
  describe 'GET /api/v1/accounts/{account.id}/captain/assistants/{id}/buscar_faq' do
    let(:assistant) { create(:captain_assistant, account: account) }

    around { |example| with_modified_env(RAMON_FAQ_BUSCA: 'texto') { example.run } }

    before do
      create(:captain_assistant_response, assistant: assistant, account: account, tese: 'auxilio-acidente',
                                          question: 'Posso continuar trabalhando recebendo auxílio-acidente?',
                                          answer: 'Pode, é compatível com o trabalho.')
      create(:captain_assistant_response, assistant: assistant, account: account, question: 'Quanto custa?',
                                          answer: '30% dos atrasados + 3 benefícios.')
      create(:captain_assistant_response, assistant: assistant, account: account, status: :pending,
                                          question: 'Posso continuar trabalhando e receber o BPC?', answer: 'Depende da renda.')
    end

    def buscar(pergunta)
      get "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/buscar_faq",
          params: { q: pergunta }, headers: agent.create_new_auth_token, as: :json
      json_response[:payload]
    end

    it 'devolve as FAQs aprovadas deste assistente que a busca do faq_lookup acharia' do
      faqs = buscar('posso continuar trabalhando')

      expect(response).to have_http_status(:success)
      expect(faqs.pluck(:question)).to eq(['Posso continuar trabalhando recebendo auxílio-acidente?'])
      expect(faqs.first).to include(tese: 'auxilio-acidente', answer: 'Pode, é compatível com o trabalho.')
    end

    it 'pergunta vazia ou sem nada parecido volta lista vazia' do
      expect(buscar('   ')).to eq([])
      expect(buscar('foguete lunar')).to eq([])
    end
  end
```

(Rastrear: a pendente fica fora por `.approved`; "posso continuar trabalhando" casa no `websearch_to_tsquery` só a 1ª aprovada — mesmo caso do `spec/models/captain/assistant_response_ramon_spec.rb`; "foguete lunar" não casa nem no OR das palavras.)

- [ ] **Step 2: Backend** — `assistants_controller.rb` (Edit):
  - `before_action :set_assistant, only: [:show, :update, :destroy, :playground]` → `before_action :set_assistant, only: [:show, :update, :destroy, :playground, :buscar_faq]`;
  - depois do `end` do método `stats`, acrescentar:

```ruby

  # ramon: "Testar pergunta" (I-FQ2) — as FAQs que a ferramenta faq_lookup deste
  # assistente acharia para a pergunta, na mesma ordem (mesma busca, até 5).
  # Pergunta em branco não busca (no modo vetorial chamaria embedding à toa).
  def buscar_faq
    pergunta = params[:q].to_s.strip
    faqs = pergunta.present? ? @assistant.responses.approved.search(pergunta).to_a : []
    render json: { payload: faqs.map { |faq| faq.slice(:id, :question, :answer, :tese) } }
  end
```

  `assistant_policy.rb` (Edit): depois do `def stats? … end` acrescentar

```ruby

  def buscar_faq?
    true
  end
```

  `config/routes.rb` (Edit): no `member do` de `resources :assistants` (dentro de `namespace :captain`), trocar

```ruby
              member do
                post :playground
              end
```

por

```ruby
              member do
                post :playground
                get :buscar_faq
              end
```

- [ ] **Step 3: Spec do cartão (falha)** — criar `app/javascript/dashboard/routes/dashboard/captain/responses/specs/TestarPergunta.spec.js`:

```js
import { mount, flushPromises } from '@vue/test-utils';
import CaptainAssistantAPI from 'dashboard/api/captain/assistant';
import TestarPergunta from '../TestarPergunta.vue';

vi.mock('dashboard/api/captain/assistant', () => ({
  default: { buscarFaq: vi.fn() },
}));

const montar = () => mount(TestarPergunta, { props: { assistantId: 1 } });
const perguntar = async (wrapper, texto) => {
  await wrapper.find('[data-testid="testar-pergunta-campo"]').setValue(texto);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
};

describe('TestarPergunta.vue', () => {
  it('mostra as FAQs que o assistente acharia, na ordem da busca', async () => {
    CaptainAssistantAPI.buscarFaq.mockResolvedValue({
      data: {
        payload: [
          {
            id: 7,
            question: 'Posso trabalhar recebendo auxílio-acidente?',
            answer: 'Pode.',
            tese: 'auxilio-acidente',
          },
          { id: 3, question: 'Quanto custa?', answer: '30% + 3.', tese: null },
        ],
      },
    });
    const wrapper = montar();
    await perguntar(wrapper, '  posso trabalhar?  ');

    expect(CaptainAssistantAPI.buscarFaq).toHaveBeenCalledWith(
      1,
      'posso trabalhar?'
    );
    const itens = wrapper.findAll('[data-testid="testar-pergunta-faq"]');
    expect(itens).toHaveLength(2);
    expect(itens[0].text()).toContain('Posso trabalhar recebendo');
    expect(itens[0].text()).toContain('Accident benefit');
    expect(itens[1].text()).toContain('Quanto custa?');
  });

  it('nenhuma FAQ: avisa que vale criar uma', async () => {
    CaptainAssistantAPI.buscarFaq.mockResolvedValue({ data: { payload: [] } });
    const wrapper = montar();
    await perguntar(wrapper, 'foguete lunar');
    expect(wrapper.find('[data-testid="testar-pergunta-nada"]').exists()).toBe(
      true
    );
  });

  it('em branco não chama a API', async () => {
    const wrapper = montar();
    await perguntar(wrapper, '   ');
    expect(CaptainAssistantAPI.buscarFaq).not.toHaveBeenCalled();
  });

  it('erro da API: mensagem, sem lista', async () => {
    CaptainAssistantAPI.buscarFaq.mockRejectedValue(new Error('500'));
    const wrapper = montar();
    await perguntar(wrapper, 'posso trabalhar?');
    expect(wrapper.text()).toContain('Could not test right now');
    expect(wrapper.findAll('[data-testid="testar-pergunta-faq"]')).toHaveLength(
      0
    );
  });
});
```

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/responses --config vitest.local.config.ts` → FAIL (arquivo não existe).

- [ ] **Step 4: API JS** — `api/captain/assistant.js` (Edit): depois do método `stats() { … }` acrescentar

```js

  // ramon: "Testar pergunta" (I-FQ2) — mesma busca do faq_lookup.
  buscarFaq(assistantId, pergunta) {
    return axios.get(`${this.url}/${assistantId}/buscar_faq`, {
      params: { q: pergunta },
    });
  }
```

- [ ] **Step 5: `TestarPergunta.vue`** (Write):

```vue
<script setup>
// "Testar pergunta" (I-FQ2): digite como o lead perguntaria e veja as FAQs que
// a ferramenta faq_lookup do assistente acharia, na mesma ordem (até 5).
// Leitura pura: não grava nada, não chama a IA.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import CaptainAssistantAPI from 'dashboard/api/captain/assistant';
import {
  AVISO,
  CAMPO,
  CARTAO,
  CHIP,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

const props = defineProps({
  assistantId: { type: Number, required: true },
});

const { t } = useI18n();
const pergunta = ref('');
const resultado = ref(null); // null = ainda não testou
const testando = ref(false);
const erro = ref(false);
const vazio = computed(() => !pergunta.value.trim());

const testar = async () => {
  const texto = pergunta.value.trim();
  if (!texto || testando.value) return;
  testando.value = true;
  erro.value = false;
  try {
    const { data } = await CaptainAssistantAPI.buscarFaq(
      props.assistantId,
      texto
    );
    resultado.value = data.payload;
  } catch (e) {
    erro.value = true;
    resultado.value = null;
  } finally {
    testando.value = false;
  }
};
</script>

<template>
  <section data-testid="testar-pergunta" class="mb-4" :class="CARTAO">
    <h2 :class="TITULO">{{ t('INTEL.FAQ.TESTAR.TITULO') }}</h2>
    <p class="mt-1 text-xs text-n-slate-10">
      {{ t('INTEL.FAQ.TESTAR.AJUDA') }}
    </p>
    <form class="flex items-center gap-2 mt-2" @submit.prevent="testar">
      <input
        v-model="pergunta"
        data-testid="testar-pergunta-campo"
        :class="CAMPO"
        :placeholder="t('INTEL.FAQ.TESTAR.PLACEHOLDER')"
      />
      <Button
        type="submit"
        size="sm"
        :label="t('INTEL.FAQ.TESTAR.BOTAO')"
        :is-loading="testando"
        :disabled="vazio || testando"
      />
    </form>
    <p v-if="erro" class="mt-2 text-sm text-n-ruby-11">
      {{ t('INTEL.FAQ.TESTAR.ERRO') }}
    </p>
    <p
      v-else-if="resultado && !resultado.length"
      data-testid="testar-pergunta-nada"
      class="mt-2"
      :class="[AVISO, TOM.amber]"
    >
      {{ t('INTEL.FAQ.TESTAR.NADA') }}
    </p>
    <ol v-else-if="resultado" class="flex flex-col gap-2 mt-3 list-none">
      <li
        v-for="(faq, posicao) in resultado"
        :key="faq.id"
        data-testid="testar-pergunta-faq"
        class="flex items-start gap-2"
      >
        <span class="shrink-0" :class="[CHIP, TOM.blue]">
          {{ posicao + 1 }}
        </span>
        <div class="min-w-0">
          <p class="flex flex-wrap items-center gap-1.5 text-sm text-n-slate-12">
            <span class="font-medium">{{ faq.question }}</span>
            <span v-if="faq.tese" :class="[CHIP, TOM.slate]">
              {{ t(`INTEL.TESE.${faq.tese}`) }}
            </span>
          </p>
          <p class="text-xs text-n-slate-11 line-clamp-2">{{ faq.answer }}</p>
        </div>
      </li>
    </ol>
  </section>
</template>
```

- [ ] **Step 6: Pôr na tela de FAQs** — `responses/Index.vue` (Edit): depois de `import { TESES, SEM_TESE } from './teses';` acrescentar `import TestarPergunta from './TestarPergunta.vue';`; no template `#body`, logo depois do `</Banner>` do aviso de pendentes:

```html
      <TestarPergunta
        v-if="selectedAssistantId"
        :assistant-id="selectedAssistantId"
      />
```

- [ ] **Step 7: Rodar** — `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain --config vitest.local.config.ts` → PASS. `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/responses app/javascript/dashboard/api/captain/assistant.js` → sem `error`.

- [ ] **Step 8: Commit**

```bash
git add enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb enterprise/app/policies/captain/assistant_policy.rb config/routes.rb spec/enterprise/controllers/api/v1/accounts/captain/assistants_controller_spec.rb app/javascript/dashboard/api/captain/assistant.js app/javascript/dashboard/routes/dashboard/captain/responses/TestarPergunta.vue app/javascript/dashboard/routes/dashboard/captain/responses/specs/TestarPergunta.spec.js app/javascript/dashboard/routes/dashboard/captain/responses/Index.vue
git commit -m "feat(ia): Testar pergunta nas FAQs (o que o assistente acharia, na ordem)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 6: Skills — liga/desliga na API e seed que respeita a tela

**Files:**
- Create: `db/migrate/20261007500002_add_edicao_to_captain_scenarios.rb`
- Modify: `db/schema.rb`, `enterprise/app/controllers/api/v1/accounts/captain/scenarios_controller.rb`, `enterprise/app/views/api/v1/models/captain/_scenario.json.jbuilder`, `lib/ramon/inteligencia_seed.rb`
- Test: `spec/enterprise/controllers/api/v1/accounts/captain/scenarios_controller_spec.rb`, `spec/lib/tasks/rake/task_ramon_inteligencia_spec.rb`

**Interfaces:**
- Produces: `GET …/scenarios` devolve **ligadas e desligadas** (ligadas primeiro, depois por id); JSON da skill ganha `edited: Boolean`; `POST`/`PATCH` pela tela marcam `edited = true`; `PATCH { scenario: { enabled: false } }` desliga sem revalidar a instrução. O agente segue usando só `scenarios.enabled` (`agent_runner_service.rb:139`, `assistant.rb:120` — intocados).

- [ ] **Step 1: Specs (falham)** — `scenarios_controller_spec.rb` (Edit):
  - trocar o exemplo `it 'returns only enabled scenarios' do … end` inteiro por:

```ruby
      it 'devolve ligadas e desligadas, ligadas primeiro (I-SK4)' do
        desligada = create(:captain_scenario, assistant: assistant, account: account, enabled: false)
        ligada = create(:captain_scenario, assistant: assistant, account: account, enabled: true)
        get "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/scenarios",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response[:payload].pluck(:id)).to eq([ligada.id, desligada.id])
        expect(json_response[:payload].pluck(:enabled)).to eq([true, false])
      end
```

  - no exemplo `it 'creates a new scenario and returns success status'`, depois de `expect(json_response[:assistant_id]).to eq(assistant.id)` acrescentar `expect(json_response[:edited]).to be(true)`;
  - no `context 'when it is an admin'` do `describe 'PATCH …'`, depois do exemplo `it 'updates the scenario and returns success status' do … end`, acrescentar:

```ruby
      it 'marca a skill como editada na tela (o seed nao sobrescreve)' do
        patch "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/scenarios/#{scenario.id}",
              params: update_attributes, headers: admin.create_new_auth_token, as: :json

        expect(scenario.reload).to be_edited
      end

      describe 'skill antiga cuja instrucao cita ferramenta que saiu do catalogo (ramon)' do
        let(:url) { "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/scenarios/#{scenario.id}" }

        before do
          scenario.update_column(:instruction, 'Use [Antiga](tool://ferramenta_que_saiu)') # rubocop:disable Rails/SkipsModelValidations
        end

        it 'desliga mesmo assim' do
          patch url, params: { scenario: { enabled: false } }, headers: admin.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
          expect(scenario.reload).not_to be_enabled
        end

        it 'nao religa sem corrigir a instrucao' do
          scenario.update_column(:enabled, false) # rubocop:disable Rails/SkipsModelValidations
          patch url, params: { scenario: { enabled: true } }, headers: admin.create_new_auth_token, as: :json

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
```

  `task_ramon_inteligencia_spec.rb`, dentro do `describe 'ramon:inteligencia:seed'`, depois do último `it`:

```ruby
    it 'respeita skill editada, renomeada, desligada ou criada na tela' do
      rodar
      editada, renomeada, desligada = atendimento.scenarios.order(:id).first(3)
      editada.update!(instruction: 'Como o Eduardo quer', edited: true)
      renomeada.update!(title: 'Nome novo na tela', edited: true)
      desligada.update!(enabled: false, edited: true)
      criada = create(:captain_scenario, assistant: atendimento, account: account, title: 'Criada na tela', edited: true)

      expect { rodar }.not_to change(Captain::Scenario, :count)
      expect(editada.reload.instruction).to eq('Como o Eduardo quer')
      expect(renomeada.reload.title).to eq('Nome novo na tela')
      expect(desligada.reload).not_to be_enabled
      expect(criada.reload).to be_enabled
    end
```

(O exemplo existente "desabilita skill que nao esta no yml…" continua valendo: a `Skill antiga` do factory nasce `edited: false` → é desligada.)

- [ ] **Step 2: Migração + schema** — criar `db/migrate/20261007500002_add_edicao_to_captain_scenarios.rb`:

```ruby
# Skills (I-SK4/I-SK5): editada na tela = a carga do seed não sobrescreve, não
# religa e não desliga; seed_titulo = o título do assistentes.yml que criou a
# skill (renomear na tela não faz o seed criar outra). As existentes nasceram
# do seed: seed_titulo = título atual.
class AddEdicaoToCaptainScenarios < ActiveRecord::Migration[7.1]
  def change
    add_column :captain_scenarios, :edited, :boolean, default: false, null: false
    add_column :captain_scenarios, :seed_titulo, :string
    reversible { |dir| dir.up { execute('UPDATE captain_scenarios SET seed_titulo = title') } }
  end
end
```

`db/schema.rb` (Edit): `define(version: 2026_10_07_500001)` → `define(version: 2026_10_07_500002)`; no bloco `create_table "captain_scenarios"`, trocar

```ruby
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_captain_scenarios_on_account_id"
```

por

```ruby
    t.datetime "updated_at", null: false
    t.boolean "edited", default: false, null: false
    t.string "seed_titulo"
    t.index ["account_id"], name: "index_captain_scenarios_on_account_id"
```

- [ ] **Step 3: Controller** — `scenarios_controller.rb` (Edit):
  - `    @scenarios = assistant_scenarios.enabled` → 
    ```ruby
        # ramon: ligadas e desligadas (I-SK4) — a tela separa em abas; o agente segue só com as ligadas.
        @scenarios = assistant_scenarios.order(enabled: :desc, id: :asc)
    ```
  - `    @scenario = assistant_scenarios.create!(scenario_params.merge(account: Current.account))` → `    @scenario = assistant_scenarios.create!(scenario_params.merge(account: Current.account, edited: true))`;
  - trocar o `def update … end` por
    ```ruby
      # ramon: tudo que passa pela tela é "editada" (I-SK5: o seed não mexe mais).
      # Desligar nunca esbarra na validação: instrução antiga pode citar ferramenta que saiu do catálogo.
      def update
        @scenario.assign_attributes(scenario_params.merge(edited: true))
        @scenario.save!(validate: !so_desligando?)
      end
    ```
  - depois de `def assistant_scenarios … end` (em `private`), acrescentar
    ```ruby

      def so_desligando?
        scenario_params.keys == ['enabled'] && !@scenario.enabled
      end
    ```

  `_scenario.json.jbuilder`: depois de `json.enabled scenario.enabled` acrescentar `json.edited scenario.edited`.

- [ ] **Step 4: Seed** — `lib/ramon/inteligencia_seed.rb` (Edit): trocar o método `seed_skills` inteiro por

```ruby
  def seed_skills(assistant, skills)
    skills.each { |skill| seed_skill(assistant, skill) }
    # Skill que saiu do yml: desabilita sem revalidar (a instrucao antiga pode citar tool que ja nao existe).
    # Editada ou criada na tela fica como esta (I-SK5).
    # rubocop:disable Rails/SkipsModelValidations
    @contagem[:skills_desabilitadas] += assistant.scenarios.enabled.where(edited: false)
                                                 .where.not(title: skills.pluck('title')).update_all(enabled: false)
    # rubocop:enable Rails/SkipsModelValidations
  end

  # Acha pela origem no yml (sobrevive a renomear na tela) e, nas antigas, pelo título.
  def seed_skill(assistant, skill)
    scenario = assistant.scenarios.find_by(seed_titulo: skill['title']) ||
               assistant.scenarios.find_or_initialize_by(title: skill['title'])
    return @contagem[:skills_puladas_editadas] += 1 if scenario.edited?

    @contagem[scenario.new_record? ? :skills_criadas : :skills_atualizadas] += 1
    scenario.update!(account: @account, description: skill['description'], instruction: skill['instruction'],
                     enabled: true, seed_titulo: skill['title'])
  end
```

e, no comentário do topo, trocar `# Chaves: assistente por name; skill por (assistant, title); FAQ por (assistant Atendimento, question).` por `# Chaves: assistente por name; skill por (assistant, seed_titulo|title), editada na tela fica; FAQ por (assistant Atendimento, question).`

- [ ] **Step 5: Rastrear à mão** — `so_desligando?`: `ActionController::Parameters#keys` devolve strings; `{ title: '', enabled: false }` (spec "with invalid parameters") tem 2 chaves → valida → 422 como antes; `save!(validate: false)` ainda roda o `before_save :resolve_tool_references`. Seed: 1ª rodada depois do deploy acha cada skill por `seed_titulo` (preenchido pela migração); a skill renomeada é achada por `seed_titulo` e pulada por `edited`; a `criada` não casa nenhum título do yml e é excluída do desligar por `edited`. `seed_skill` tem Cyclomatic 3. `scenarios_controller.rb` ≈ 58 linhas.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/20261007500002_add_edicao_to_captain_scenarios.rb db/schema.rb enterprise/app/controllers/api/v1/accounts/captain/scenarios_controller.rb enterprise/app/views/api/v1/models/captain/_scenario.json.jbuilder lib/ramon/inteligencia_seed.rb spec/enterprise/controllers/api/v1/accounts/captain/scenarios_controller_spec.rb spec/lib/tasks/rake/task_ramon_inteligencia_spec.rb
git commit -m "feat(ia): skills ligadas e desligadas na API; seed não mexe em skill editada, renomeada ou criada na tela" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 7: Skills — abas Ligadas/Desligadas, chave e "Editada aqui"

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/assistants/scenarios/Index.vue`, `app/javascript/dashboard/components-next/captain/assistant/ScenariosCard.vue`
- Test: `app/javascript/dashboard/components-next/captain/assistant/specs/ScenariosCard.spec.js`

**Interfaces:**
- Consumes: Task 6 (`enabled`, `edited` no JSON; `PATCH { enabled }`); store `captainScenarios/update({ id, assistantId, ...campos })` (já existe; faz `EDIT` do registro); `INTEL.SKILLS.*` (Task 2).
- Produces: `ScenariosCard` props `enabled` (Boolean, true), `edited` (Boolean, false), `podeLigar` (Boolean, false); evento `toggle(ligar: Boolean)`.

- [ ] **Step 1: Spec (falha)** — `ScenariosCard.spec.js` (Edit):
  - trocar `const montar = tools => {` por `const montar = (tools, extra = {}) => {` e, nos `props` do `mount`, depois de `tools,` acrescentar `...extra,`;
  - acrescentar no fim do `describe`:

```js
  it('chave liga/desliga emite toggle com o novo estado', async () => {
    const wrapper = montar([], { enabled: true, podeLigar: true });
    await wrapper.find('[data-testid="skill-chave"]').trigger('click');
    expect(wrapper.emitted('toggle')[0]).toEqual([false]);
  });

  it('sem permissão não mostra a chave; editada mostra a marca', () => {
    const wrapper = montar([], { edited: true });
    expect(wrapper.find('[data-testid="skill-chave"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="skill-editada"]').text()).toBe(
      'INTEL.SKILLS.EDITADA'
    );
  });
```

Run: `TZ=UTC npx vitest run app/javascript/dashboard/components-next/captain/assistant --config vitest.local.config.ts` → FAIL.

- [ ] **Step 2: `ScenariosCard.vue`** (Edit):
  - depois de `import Icon from 'dashboard/components-next/icon/Icon.vue';` acrescentar `import Switch from 'dashboard/components-next/switch/Switch.vue';`;
  - `import { CHIP } from 'dashboard/routes/dashboard/ramon/helpers/ui';` → `import { CHIP, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';`;
  - nos `defineProps`, depois do bloco `isSelected: { … },` acrescentar
    ```js
      // ramon: liga/desliga (I-SK4) e "editada na tela" (I-SK5)
      enabled: { type: Boolean, default: true },
      edited: { type: Boolean, default: false },
      podeLigar: { type: Boolean, default: false },
    ```
  - `const emit = defineEmits(['select', 'hover', 'delete', 'update']);` → `const emit = defineEmits(['select', 'hover', 'delete', 'update', 'toggle']);`;
  - no template, trocar
    ```html
            <div class="flex flex-col items-start">
              <span class="text-sm text-n-slate-12 font-medium">{{ title }}</span>
    ```
    por
    ```html
            <div class="flex flex-col items-start">
              <div class="flex flex-wrap items-center gap-2">
                <span class="text-sm text-n-slate-12 font-medium">{{ title }}</span>
                <span
                  v-if="edited"
                  data-testid="skill-editada"
                  :class="[CHIP, TOM.slate]"
                  :title="t('INTEL.SKILLS.EDITADA_AJUDA')"
                >
                  {{ t('INTEL.SKILLS.EDITADA') }}
                </span>
              </div>
    ```
  - trocar
    ```html
              <!-- <Button label="Test" slate xs ghost class="!text-sm" />
              <span class="w-px h-4 bg-n-weak" /> -->
    ```
    por
    ```html
              <Switch
                v-if="podeLigar"
                data-testid="skill-chave"
                :model-value="enabled"
                :title="t('INTEL.SKILLS.LIGAR')"
                @update:model-value="ligar => emit('toggle', ligar)"
              />
              <span v-if="podeLigar" class="w-px h-4 bg-n-weak" />
    ```

- [ ] **Step 3: `scenarios/Index.vue`** (Edit):
  - depois de `import { useMessageFormatter } from 'shared/composables/useMessageFormatter';` acrescentar `import { useAdmin } from 'dashboard/composables/useAdmin';`;
  - `import { CHIP } from 'dashboard/routes/dashboard/ramon/helpers/ui';` → `import { ABA, ABA_ATIVA, ABA_INATIVA, CHIP } from 'dashboard/routes/dashboard/ramon/helpers/ui';`;
  - depois de `const assistantId = computed(() => Number(route.params.assistantId));` acrescentar `const { isAdmin } = useAdmin();`;
  - trocar o computed `filteredScenarios` inteiro por
    ```js
    // I-SK4: a API devolve ligadas e desligadas; a tela separa em abas.
    const aba = ref('ligadas');
    const ligadas = computed(() => scenarios.value.filter(item => item.enabled));
    const desligadas = computed(() =>
      scenarios.value.filter(item => !item.enabled)
    );
    const daAba = computed(() =>
      aba.value === 'ligadas' ? ligadas.value : desligadas.value
    );
    const abas = computed(() => [
      {
        id: 'ligadas',
        label: t('INTEL.SKILLS.ABA_LIGADAS', { n: ligadas.value.length }),
      },
      {
        id: 'desligadas',
        label: t('INTEL.SKILLS.ABA_DESLIGADAS', { n: desligadas.value.length }),
      },
    ]);
    const mensagemVazia = computed(() =>
      aba.value === 'desligadas'
        ? t('INTEL.SKILLS.NENHUMA_DESLIGADA')
        : t('CAPTAIN.ASSISTANTS.SCENARIOS.EMPTY_MESSAGE')
    );

    const filteredScenarios = computed(() => {
      const query = searchQuery.value.trim();
      if (!query) return daAba.value;
      return picoSearch(daAba.value, query, ['title', 'description', 'instruction']);
    });
    ```
  - depois do `const deleteScenario = async id => { … };` acrescentar
    ```js

    const alternarSkill = async (scenario, ligar) => {
      try {
        await store.dispatch('captainScenarios/update', {
          id: scenario.id,
          assistantId: assistantId.value,
          enabled: ligar,
        });
        useAlert(
          ligar ? t('INTEL.SKILLS.LIGADA') : t('INTEL.SKILLS.DESLIGADA')
        );
      } catch (error) {
        useAlert(
          error?.message || t('CAPTAIN.ASSISTANTS.SCENARIOS.API.UPDATE.ERROR')
        );
      }
    };
    ```
  - no `buildSelectedCountLabel`, `const count = scenarios.value.length || 0;` → `const count = daAba.value.length || 0;`;
  - no template, logo depois de `      <div class="flex mt-7 flex-col gap-4">` (o 2º, o da lista — o que contém o `<BulkSelectBar`), acrescentar como primeiro filho
    ```html
            <nav data-testid="skills-abas" class="flex gap-1 border-b border-n-weak">
              <button
                v-for="item in abas"
                :key="item.id"
                type="button"
                :class="[ABA, aba === item.id ? ABA_ATIVA : ABA_INATIVA]"
                @click="aba = item.id"
              >
                {{ item.label }}
              </button>
            </nav>
    ```
  - `:all-items="scenarios"` (no `BulkSelectBar`) → `:all-items="daAba"`;
  - trocar
    ```html
            <div v-if="scenarios.length === 0" class="mt-1 mb-2">
              <span class="text-n-slate-11 text-sm">
                {{ t('CAPTAIN.ASSISTANTS.SCENARIOS.EMPTY_MESSAGE') }}
              </span>
    ```
    por
    ```html
            <div v-if="daAba.length === 0" class="mt-1 mb-2">
              <span class="text-n-slate-11 text-sm">
                {{ mensagemVazia }}
              </span>
    ```
  - no `<ScenariosCard`, depois de `:tools="scenario.tools"` acrescentar
    ```html
                :enabled="scenario.enabled"
                :edited="scenario.edited"
                :pode-ligar="isAdmin"
    ```
    e depois de `@update="updateScenario"` acrescentar `@toggle="ligar => alternarSkill(scenario, ligar)"`.

- [ ] **Step 4: Rodar** — `TZ=UTC npx vitest run app/javascript/dashboard/components-next/captain app/javascript/dashboard/routes/dashboard/captain --config vitest.local.config.ts` → PASS. `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/assistants/scenarios/Index.vue app/javascript/dashboard/components-next/captain/assistant/ScenariosCard.vue app/javascript/dashboard/components-next/captain/assistant/specs/ScenariosCard.spec.js` → sem `error`.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/assistants/scenarios/Index.vue app/javascript/dashboard/components-next/captain/assistant/ScenariosCard.vue app/javascript/dashboard/components-next/captain/assistant/specs/ScenariosCard.spec.js
git commit -m "feat(ia): Skills com abas Ligadas/Desligadas, chave liga/desliga e marca de editada" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 8: Execuções — caso, conversa e assistente clicáveis (+ kit visual)

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/captain/pages/execucoes.js`, `app/javascript/dashboard/routes/dashboard/captain/pages/specs/Execucoes.spec.js`
- Modify: `app/controllers/api/v1/accounts/captain_tool_runs_controller.rb`, `app/views/api/v1/accounts/captain_tool_runs/index.json.jbuilder`, `app/javascript/dashboard/routes/dashboard/captain/pages/Execucoes.vue`
- Test: `spec/controllers/api/v1/accounts/captain_tool_runs_controller_spec.rb`

**Interfaces:**
- Produces: cada item de `GET captain_tool_runs` ganha `lead_nome: String|null`, `conversa_display_id: Integer|null` (o nº que a rota `inbox_conversation` usa — `conversation_id` gravado é o id interno), `assistente_nome: String|null`. Helper `captain/pages/execucoes.js`: `STATUS_TOM`, `LINK`, `fmtHora(iso)`, `rotuloCaso(t, item)`, `useAbrir() → { abrirCaso(leadId), abrirConversa(displayId) }`.

- [ ] **Step 1: Spec Ruby (falha)** — em `captain_tool_runs_controller_spec.rb`, antes do `it 'exige autenticacao'`:

```ruby
  it 'devolve o nome do caso e o numero da conversa de cada linha (I-EX2)' do
    lead = create(:lead, account: account, name: 'Maria Souza')
    conversa = create(:conversation, account: account)
    Captain::ToolRun.create!(account_id: account.id, tool_name: 'mover_etapa', status: 'ok',
                             lead_id: lead.id, conversation_id: conversa.id)

    get url, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['items'].first).to include('lead_nome' => 'Maria Souza',
                                                           'conversa_display_id' => conversa.display_id)
  end

  it 'devolve o nome do assistente', if: ChatwootApp.enterprise? do
    assistente = create(:captain_assistant, account: account, name: 'Atendimento')
    Captain::ToolRun.create!(account_id: account.id, assistant_id: assistente.id, tool_name: 'faq_lookup', status: 'ok')

    get url, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['items'].first['assistente_nome']).to eq('Atendimento')
  end
```

- [ ] **Step 2: Backend** — `captain_tool_runs_controller.rb` (Edit):
  - trocar o `def index … end` por
    ```ruby
      def index
        @tool_runs = escopo.recentes.limit(LIST_LIMIT).to_a
        @resumo = resumo
        # nome e nivel de cada ferramenta pra tela: o endpoint de ferramentas e so admin
        @catalogo = ChatwootApp.enterprise? ? Captain::Assistant.built_in_agent_tools : []
        @nomes = nomes(@tool_runs)
      end
    ```
  - antes do `def resumo`, acrescentar
    ```ruby
      # I-EX2: nome do caso, nº da conversa (o que a rota da tela usa) e assistente
      # de cada linha — 3 consultas para as 100 linhas.
      def nomes(runs)
        {
          leads: Current.account.leads.where(id: runs.filter_map(&:lead_id)).pluck(:id, :name).to_h,
          conversas: Current.account.conversations.where(id: runs.filter_map(&:conversation_id)).pluck(:id, :display_id).to_h,
          assistentes: assistentes
        }
      end

      def assistentes
        return {} unless ChatwootApp.enterprise?

        Captain::Assistant.for_account(Current.account.id).pluck(:id, :name).to_h
      end

    ```

  `index.json.jbuilder` (Edit): depois de `  json.assistant_id run.assistant_id` acrescentar

```ruby
  json.lead_nome @nomes[:leads][run.lead_id]
  json.conversa_display_id @nomes[:conversas][run.conversation_id]
  json.assistente_nome @nomes[:assistentes][run.assistant_id]
```

- [ ] **Step 3: Helper** — criar `app/javascript/dashboard/routes/dashboard/captain/pages/execucoes.js` (Write):

```js
// Peças comuns das abas das Execuções (ferramentas da IA e agente Claude).
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';

// ok/erro (ferramentas) + limite, cap e timeout (agente_execucoes.status).
export const STATUS_TOM = {
  ok: TOM.teal,
  erro: TOM.ruby,
  timeout: TOM.amber,
  limite: TOM.amber,
  cap: TOM.slate,
};
export const LINK = 'text-xs text-n-blue-11 hover:underline';

export const fmtHora = value =>
  new Date(value).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });

export const rotuloCaso = (t, item) =>
  item.lead_nome
    ? t('INTEL.EXECUCOES.CASO_NOME', { id: item.lead_id, nome: item.lead_nome })
    : t('INTEL.EXECUCOES.CASO', { id: item.lead_id });

// Mesmo padrão do Vigia: abre o Funil e seleciona o caso; a conversa pelo nº.
export const useAbrir = () => {
  const router = useRouter();
  const store = useStore();
  const { accountScopedRoute } = useAccount();
  return {
    abrirCaso: id => {
      router.push(accountScopedRoute('ramon_funil'));
      store.dispatch('leads/select', id);
    },
    abrirConversa: displayId =>
      router.push(
        accountScopedRoute('inbox_conversation', { conversation_id: displayId })
      ),
  };
};
```

- [ ] **Step 4: Spec da tela (falha)** — criar `app/javascript/dashboard/routes/dashboard/captain/pages/specs/Execucoes.spec.js`:

```js
import { mount, flushPromises } from '@vue/test-utils';
import CaptainToolRunsAPI from 'dashboard/api/captainToolRuns';
import Execucoes from '../Execucoes.vue';

const push = vi.fn();
const dispatch = vi.fn();
let query = {};
vi.mock('vue-router', () => ({
  useRouter: () => ({ push }),
  useRoute: () => ({ query }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params, q) => ({ name, params, query: q }),
  }),
}));
vi.mock('dashboard/api/captainToolRuns', () => ({ default: { list: vi.fn() } }));

const RUN = {
  id: 1,
  tool_name: 'mover_etapa',
  status: 'ok',
  duration_ms: 420,
  params: { etapa: 'Reunião' },
  resultado: 'movido',
  lead_id: 123,
  lead_nome: 'Maria Souza',
  conversation_id: 9,
  conversa_display_id: 482,
  assistant_id: 1,
  assistente_nome: 'Atendimento (rascunho)',
  created_at: '2026-10-07T12:00:00Z',
};
const montar = async () => {
  CaptainToolRunsAPI.list.mockResolvedValue({
    data: {
      resumo: {
        total_24h: 2,
        erros_24h: 0,
        por_tool: { mover_etapa: 2 },
        tools: ['mover_etapa'],
      },
      items: [
        RUN,
        {
          ...RUN,
          id: 2,
          lead_id: null,
          lead_nome: null,
          conversa_display_id: null,
          assistente_nome: null,
        },
      ],
      catalogo: [{ id: 'mover_etapa', title: 'Mover de etapa', nivel: 'sugestao' }],
    },
  });
  const wrapper = mount(Execucoes);
  await flushPromises();
  return wrapper;
};

describe('Execucoes.vue', () => {
  beforeEach(() => {
    query = {};
  });

  it('caso clicável abre o Funil com o caso selecionado', async () => {
    const wrapper = await montar();
    const caso = wrapper.find('[data-testid="execucoes-caso"]');
    expect(caso.text()).toContain('Maria Souza');
    await caso.trigger('click');
    expect(push).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'ramon_funil' })
    );
    expect(dispatch).toHaveBeenCalledWith('leads/select', 123);
  });

  it('conversa clicável abre a conversa pelo nº; assistente aparece', async () => {
    const wrapper = await montar();
    await wrapper.find('[data-testid="execucoes-conversa"]').trigger('click');
    expect(push).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'inbox_conversation',
        params: { conversation_id: 482 },
      })
    );
    expect(wrapper.find('[data-testid="execucoes-assistente"]').text()).toBe(
      'Atendimento (rascunho)'
    );
  });

  it('linha sem caso nem conversa não mostra os links', async () => {
    const wrapper = await montar();
    const linha = wrapper.findAll('[data-testid="execucoes-linha"]')[1];
    expect(linha.find('[data-testid="execucoes-caso"]').exists()).toBe(false);
    expect(linha.find('[data-testid="execucoes-conversa"]').exists()).toBe(false);
  });
});
```

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/pages/specs/Execucoes.spec.js --config vitest.local.config.ts` → FAIL.

- [ ] **Step 5: `Execucoes.vue`** — substituir o arquivo inteiro (Write):

```vue
<script setup>
// Tela Execuções: o log auditável do que a IA executou — ferramenta, dados, o
// que voltou, duração — com o caso, a conversa e o assistente de cada linha
// (I-EX2). Leitura pura.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import CaptainToolRunsAPI from 'dashboard/api/captainToolRuns';
import {
  CARTAO,
  CHIP,
  SELECT,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { ferramentaInfo } from 'dashboard/routes/dashboard/ramon/helpers/ferramentas';
import { LINK, STATUS_TOM, fmtHora, rotuloCaso, useAbrir } from './execucoes';

defineOptions({ name: 'CaptainExecucoes' });

const { t } = useI18n();
const { abrirCaso, abrirConversa } = useAbrir();

const data = ref(null);
const loading = ref(false);
const error = ref(false);
const filtroTool = ref('');
const filtroStatus = ref('');
const aberto = ref(null);

const fetchData = async () => {
  loading.value = true;
  error.value = false;
  try {
    const params = {};
    if (filtroTool.value) params.tool_name = filtroTool.value;
    if (filtroStatus.value) params.status = filtroStatus.value;
    const response = await CaptainToolRunsAPI.list(params);
    data.value = response.data;
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(fetchData);

const resumo = computed(() => data.value?.resumo ?? {});
const items = computed(() => data.value?.items ?? []);
const tools = computed(() => resumo.value.tools ?? []);
const catalogo = computed(() => data.value?.catalogo ?? []);
const ferramenta = id => ferramentaInfo(id, catalogo.value);
const nivelLabel = nivel =>
  ({
    consulta: t('CAPTAIN_RAMON.NIVEL.consulta'),
    sugestao: t('CAPTAIN_RAMON.NIVEL.sugestao'),
    rascunho: t('CAPTAIN_RAMON.NIVEL.rascunho'),
    interna: t('CAPTAIN_RAMON.NIVEL.interna'),
  })[nivel];

const paramsResumo = run => {
  const entries = Object.entries(run.params || {});
  if (!entries.length) return '—';
  return entries.map(([k, v]) => `${k}: ${v}`).join(' · ');
};

const toggle = id => {
  aberto.value = aberto.value === id ? null : id;
};

// texto montado no script: o template não aceita string crua (eslint i18n)
const linhaTempo = run => `${fmtHora(run.created_at)} · ${run.duration_ms}ms`;
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-auto bg-n-surface-1">
    <div class="w-full max-w-5xl px-6 py-6 mx-auto">
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('CAPTAIN_RAMON.EXECUCOES.TITLE') }}
      </h1>
      <p class="mt-1 text-sm text-n-slate-10">
        {{ t('CAPTAIN_RAMON.EXECUCOES.SUBTITLE') }}
      </p>

      <div
        v-if="error"
        data-testid="execucoes-error"
        class="mt-4 text-sm"
        :class="CARTAO"
      >
        <p class="text-n-ruby-11">{{ t('CAPTAIN_RAMON.LOAD_ERROR') }}</p>
        <button type="button" class="mt-1" :class="LINK" @click="fetchData">
          {{ t('CAPTAIN_RAMON.RETRY') }}
        </button>
      </div>

      <template v-else>
        <div class="grid grid-cols-2 gap-3 mt-5 sm:grid-cols-3">
          <div :class="CARTAO">
            <p :class="TITULO">{{ t('CAPTAIN_RAMON.EXECUCOES.TOTAL_24H') }}</p>
            <p class="mt-1 text-2xl font-semibold text-n-slate-12">
              {{ resumo.total_24h ?? 0 }}
            </p>
          </div>
          <div :class="CARTAO">
            <p :class="TITULO">{{ t('CAPTAIN_RAMON.EXECUCOES.ERROS_24H') }}</p>
            <p
              class="mt-1 text-2xl font-semibold"
              :class="resumo.erros_24h ? 'text-n-ruby-11' : 'text-n-slate-12'"
            >
              {{ resumo.erros_24h ?? 0 }}
            </p>
          </div>
          <div :class="CARTAO">
            <p :class="TITULO">
              {{ t('CAPTAIN_RAMON.EXECUCOES.TOOLS_USADAS') }}
            </p>
            <p class="mt-1 text-2xl font-semibold text-n-slate-12">
              {{ Object.keys(resumo.por_tool || {}).length }}
            </p>
          </div>
        </div>

        <div class="flex flex-wrap gap-2 mt-5">
          <select
            v-model="filtroTool"
            data-testid="execucoes-filtro-tool"
            class="!w-60"
            :class="SELECT"
            @change="fetchData"
          >
            <option value="">
              {{ t('CAPTAIN_RAMON.EXECUCOES.ALL_TOOLS') }}
            </option>
            <option v-for="tool in tools" :key="tool" :value="tool">
              {{ ferramenta(tool).title }}
            </option>
          </select>
          <select
            v-model="filtroStatus"
            class="!w-44"
            :class="SELECT"
            @change="fetchData"
          >
            <option value="">
              {{ t('CAPTAIN_RAMON.EXECUCOES.ALL_STATUS') }}
            </option>
            <option value="ok">{{ t('INTEL.EXECUCOES.STATUS.ok') }}</option>
            <option value="erro">{{ t('INTEL.EXECUCOES.STATUS.erro') }}</option>
          </select>
        </div>

        <p v-if="loading" class="mt-6 text-sm text-n-slate-10">
          {{ t('CAPTAIN_RAMON.LOADING') }}
        </p>
        <p
          v-else-if="!items.length"
          data-testid="execucoes-vazio"
          class="mt-6 text-sm text-n-slate-10"
        >
          {{ t('CAPTAIN_RAMON.EXECUCOES.EMPTY') }}
        </p>

        <ul v-else class="flex flex-col gap-2 mt-4 list-none">
          <li
            v-for="run in items"
            :key="run.id"
            data-testid="execucoes-linha"
            :class="CARTAO"
          >
            <div class="flex flex-wrap items-center gap-2">
              <span :class="[CHIP, STATUS_TOM[run.status] || TOM.slate]">
                {{ t(`INTEL.EXECUCOES.STATUS.${run.status}`) }}
              </span>
              <span class="text-sm font-medium text-n-slate-12">
                {{ ferramenta(run.tool_name).title }}
              </span>
              <span
                v-if="ferramenta(run.tool_name).nivel"
                data-testid="execucoes-nivel"
                :class="[CHIP, ferramenta(run.tool_name).tom]"
              >
                {{ nivelLabel(ferramenta(run.tool_name).nivel) }}
              </span>
              <span
                v-if="run.assistente_nome"
                data-testid="execucoes-assistente"
                :class="[CHIP, TOM.slate]"
              >
                {{ run.assistente_nome }}
              </span>
              <span class="ml-auto text-[11px] text-n-slate-10">
                {{ linhaTempo(run) }}
              </span>
            </div>
            <p class="mt-1 text-xs text-n-slate-11">{{ paramsResumo(run) }}</p>
            <div class="flex flex-wrap items-center gap-3 mt-1">
              <button
                v-if="run.lead_id"
                type="button"
                data-testid="execucoes-caso"
                :class="LINK"
                @click="abrirCaso(run.lead_id)"
              >
                {{ rotuloCaso(t, run) }}
              </button>
              <button
                v-if="run.conversa_display_id"
                type="button"
                data-testid="execucoes-conversa"
                :class="LINK"
                @click="abrirConversa(run.conversa_display_id)"
              >
                {{ t('INTEL.EXECUCOES.CONVERSA', { id: run.conversa_display_id }) }}
              </button>
              <button type="button" :class="LINK" @click="toggle(run.id)">
                {{
                  aberto === run.id
                    ? t('CAPTAIN_RAMON.EXECUCOES.HIDE_RESULT')
                    : t('CAPTAIN_RAMON.EXECUCOES.SHOW_RESULT')
                }}
              </button>
            </div>
            <div
              v-if="aberto === run.id"
              class="p-2 mt-2 overflow-auto font-mono text-[11px] whitespace-pre-wrap rounded-lg bg-n-alpha-2 text-n-slate-11 max-h-64"
            >
              {{ run.resultado }}
            </div>
          </li>
        </ul>
      </template>
    </div>
  </section>
</template>
```

- [ ] **Step 6: Rodar** — `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain --config vitest.local.config.ts` → PASS. `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/pages/Execucoes.vue app/javascript/dashboard/routes/dashboard/captain/pages/execucoes.js app/javascript/dashboard/routes/dashboard/captain/pages/specs/Execucoes.spec.js` → sem `error`.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/api/v1/accounts/captain_tool_runs_controller.rb app/views/api/v1/accounts/captain_tool_runs/index.json.jbuilder spec/controllers/api/v1/accounts/captain_tool_runs_controller_spec.rb app/javascript/dashboard/routes/dashboard/captain/pages/execucoes.js app/javascript/dashboard/routes/dashboard/captain/pages/Execucoes.vue app/javascript/dashboard/routes/dashboard/captain/pages/specs/Execucoes.spec.js
git commit -m "feat(ia): Execuções com caso, conversa e assistente clicáveis, no kit visual" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 9: Execuções — aba "Agente Claude" (trilha de `agente_execucoes`)

**Files:**
- Create: `app/controllers/api/v1/accounts/ramon_agente_execucoes_controller.rb`, `spec/controllers/api/v1/accounts/ramon_agente_execucoes_controller_spec.rb`, `app/javascript/dashboard/api/ramonAgenteExecucoes.js`, `app/javascript/dashboard/routes/dashboard/captain/pages/ExecucoesAgente.vue`, `app/javascript/dashboard/routes/dashboard/captain/pages/specs/ExecucoesAgente.spec.js`
- Modify: `app/models/agente_execucao.rb`, `app/controllers/api/v1/accounts/ramon_inteligencia_controller.rb`, `config/routes.rb`, `app/javascript/dashboard/routes/dashboard/captain/pages/Execucoes.vue`, `app/javascript/dashboard/routes/dashboard/captain/pages/specs/Execucoes.spec.js`, `app/javascript/dashboard/routes/dashboard/captain/pages/VisaoGeral.vue`

**Interfaces:**
- Consumes: `AgenteExecucao` (`pedido`, `status` ∈ ok/erro/limite/cap/timeout, `resumo`, `acoes` = `[{tipo, ref}]` gravado pelo runner, `modelo`, `esforco`, `duracao_ms`, `lead`, `conversation`, `scope :consumiu_cota`, `TETO_DIA`); Task 8 (`execucoes.js`).
- Produces: `AgenteExecucao.de_hoje` (dia de Brasília); `GET /api/v1/accounts/:account_id/ramon_agente_execucoes` (admin + agente) → `{ resumo: { hoje, teto, problemas_hoje }, items: [{ id, pedido, status, resumo, acoes, modelo, esforco, duracao_ms, lead_id, created_at, lead_nome, conversa_display_id }] }` (100 mais novas); rota da tela `captain_execucoes_index?aba=agente`; na Visão geral, `ir(name, params = {}, query = {})`.

- [ ] **Step 1: Spec Ruby (falha)** — criar `spec/controllers/api/v1/accounts/ramon_agente_execucoes_controller_spec.rb`:

```ruby
require 'rails_helper'

# Aba "Agente Claude" das Execuções (I-EX4): a trilha de agente_execucoes, mais
# nova primeiro, e o uso do teto de hoje (dia de Brasília). Roda no CI FOSS.
RSpec.describe 'Ramon Agente Execucoes API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_agente_execucoes" }

  it 'lista a trilha mais nova primeiro, com caso, conversa e acoes, e o uso de hoje' do
    lead = create(:lead, account: account, name: 'Maria Souza')
    conversa = create(:conversation, account: account)
    travel_to Time.zone.parse('2026-10-07 13:00:00') do # 10:00 em Brasília
      account.agente_execucoes.create!(pedido: 'ontem', status: 'ok', created_at: 1.day.ago)
      account.agente_execucoes.create!(pedido: 'sem cota', status: 'cap', resumo: 'Cap diário atingido (30)')
      account.agente_execucoes.create!(pedido: 'resuma o caso', status: 'erro', resumo: 'falhou', lead: lead,
                                       conversation: conversa, acoes: [{ 'tipo' => 'drive', 'ref' => 'https://drive/x' }],
                                       duracao_ms: 4200, modelo: 'opus', esforco: 'low')
      get url, headers: agent.create_new_auth_token, as: :json
    end

    body = response.parsed_body
    expect(response).to have_http_status(:success)
    expect(body['items'].pluck('pedido')).to eq(['resuma o caso', 'sem cota', 'ontem'])
    expect(body['items'].first).to include('lead_id' => lead.id, 'lead_nome' => 'Maria Souza',
                                           'conversa_display_id' => conversa.display_id, 'duracao_ms' => 4200,
                                           'acoes' => [{ 'tipo' => 'drive', 'ref' => 'https://drive/x' }])
    expect(body['resumo']).to eq('hoje' => 1, 'teto' => 30, 'problemas_hoje' => 2)
  end

  it 'nao vaza execucao de outra conta' do
    create(:account).agente_execucoes.create!(pedido: 'de outra conta', status: 'ok')

    get url, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['items']).to be_empty
  end

  it 'exige autenticacao' do
    get url, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
```

(Rastrear: "sem cota" tem `resumo LIKE 'Cap diário atingido%'` → fora do `consumiu_cota` → `hoje` = 1 (só "resuma o caso"); `problemas_hoje` = status ≠ ok de hoje = cap + erro = 2; "ontem" = 06/10 13:00 UTC, fora do dia 07/10 de Brasília. "sem cota" e "resuma o caso" têm o mesmo `created_at` congelado → desempate por `id: :desc`.)

- [ ] **Step 2: Backend** — `app/models/agente_execucao.rb` (Edit): depois da linha do `scope :consumiu_cota, …` acrescentar

```ruby
  # "Hoje" no fuso de Brasília — o servidor roda em UTC. Visão geral e aba Agente Claude.
  scope :de_hoje, -> { where(created_at: Time.find_zone(Ramon::CockpitMetrics::TIME_ZONE).now.beginning_of_day..) }
```

`ramon_inteligencia_controller.rb` (Edit): trocar `    hoje = execucoes.where(created_at: Time.find_zone(Ramon::CockpitMetrics::TIME_ZONE).now.beginning_of_day..)` por `    hoje = execucoes.de_hoje` (e o comentário `# "Hoje" no fuso de Brasília — o servidor roda em UTC.` acima do método pode ficar; o spec existente "o agente de hoje no fuso de Brasilia" cobre).

Criar `app/controllers/api/v1/accounts/ramon_agente_execucoes_controller.rb`:

```ruby
# Aba "Agente Claude" das Execuções (I-EX4): a trilha que o runner da VPS grava em
# agente_execucoes (pedido, status, resumo, ações, duração) e o uso do teto de hoje.
# Leitura pura; o custo (nominal, da assinatura) fica na tela Uso e custo, só admin.
class Api::V1::Accounts::RamonAgenteExecucoesController < Api::V1::Accounts::BaseController
  LIMITE = 100

  before_action :current_account
  before_action :check_authorization

  def index
    execucoes = Current.account.agente_execucoes.includes(:lead, :conversation)
                       .order(created_at: :desc, id: :desc).limit(LIMITE)
    render json: { resumo: resumo, items: execucoes.map { |execucao| linha(execucao) } }
  end

  private

  # Mesmas permissões das Execuções das ferramentas (admin + agent).
  def check_authorization
    authorize(:ramon_dashboard, :show?)
  end

  def resumo
    hoje = Current.account.agente_execucoes.de_hoje
    { hoje: hoje.consumiu_cota.count, teto: AgenteExecucao::TETO_DIA, problemas_hoje: hoje.where.not(status: 'ok').count }
  end

  def linha(execucao)
    execucao.slice(:id, :pedido, :status, :resumo, :acoes, :modelo, :esforco, :duracao_ms, :lead_id, :created_at)
            .merge(lead_nome: execucao.lead&.name, conversa_display_id: execucao.conversation&.display_id)
  end
end
```

`config/routes.rb` (Edit): trocar `          resources :captain_tool_runs, only: [:index]` por

```ruby
          resources :captain_tool_runs, only: [:index]
          resources :ramon_agente_execucoes, only: [:index], controller: 'ramon_agente_execucoes'
```

- [ ] **Step 3: Specs do front (falham)** — criar `app/javascript/dashboard/routes/dashboard/captain/pages/specs/ExecucoesAgente.spec.js`:

```js
import { mount, flushPromises } from '@vue/test-utils';
import RamonAgenteExecucoesAPI from 'dashboard/api/ramonAgenteExecucoes';
import ExecucoesAgente from '../ExecucoesAgente.vue';

const push = vi.fn();
const dispatch = vi.fn();
vi.mock('vue-router', () => ({
  useRouter: () => ({ push }),
  useRoute: () => ({ query: {} }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
vi.mock('dashboard/api/ramonAgenteExecucoes', () => ({
  default: { list: vi.fn() },
}));

const ITEM = {
  id: 5,
  pedido: 'resuma o caso da Maria',
  status: 'erro',
  resumo: 'Não achei o processo no AdvBox.',
  acoes: [{ tipo: 'drive', ref: 'https://drive.google.com/x' }],
  modelo: 'opus',
  esforco: 'low',
  duracao_ms: 4200,
  lead_id: 123,
  lead_nome: 'Maria Souza',
  conversa_display_id: 482,
  created_at: '2026-10-07T12:00:00Z',
};
const montar = async (items = [ITEM]) => {
  RamonAgenteExecucoesAPI.list.mockResolvedValue({
    data: { resumo: { hoje: 4, teto: 30, problemas_hoje: 1 }, items },
  });
  const wrapper = mount(ExecucoesAgente);
  await flushPromises();
  return wrapper;
};

describe('ExecucoesAgente.vue', () => {
  it('mostra o uso de hoje e cada pedido com status, duração e modelo', async () => {
    const wrapper = await montar();
    expect(wrapper.find('[data-testid="agente-hoje"]').text()).toBe(
      'Today: 4 of 30 requests'
    );
    const linha = wrapper.find('[data-testid="agente-linha"]');
    expect(linha.text()).toContain('resuma o caso da Maria');
    expect(linha.text()).toContain('Error');
    expect(linha.text()).toContain('4 s');
    expect(linha.text()).toContain('opus · low');
  });

  it('ver resultado mostra a resposta e as ações', async () => {
    const wrapper = await montar();
    await wrapper.find('[data-testid="agente-ver"]').trigger('click');
    const detalhe = wrapper.find('[data-testid="agente-detalhe"]');
    expect(detalhe.text()).toContain('Não achei o processo no AdvBox.');
    expect(detalhe.text()).toContain('drive → https://drive.google.com/x');
  });

  it('caso clicável abre o Funil', async () => {
    const wrapper = await montar();
    await wrapper.find('[data-testid="execucoes-caso"]').trigger('click');
    expect(dispatch).toHaveBeenCalledWith('leads/select', 123);
  });

  it('sem pedidos: aviso', async () => {
    const wrapper = await montar([]);
    expect(wrapper.find('[data-testid="agente-vazio"]').exists()).toBe(true);
  });
});
```

Em `Execucoes.spec.js` (Edit): depois do `vi.mock('dashboard/api/captainToolRuns', …);` acrescentar

```js
vi.mock('../ExecucoesAgente.vue', () => ({
  default: { template: '<div data-testid="aba-agente-conteudo" />' },
}));
```

e, no fim do `describe`:

```js
  it('?aba=agente abre a aba do agente Claude; a aba de ferramentas volta', async () => {
    query = { aba: 'agente' };
    const wrapper = await montar();
    expect(wrapper.find('[data-testid="aba-agente-conteudo"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-testid="execucoes-linha"]').exists()).toBe(false);
    await wrapper
      .find('[data-testid="execucoes-aba-ferramentas"]')
      .trigger('click');
    expect(wrapper.findAll('[data-testid="execucoes-linha"]')).toHaveLength(2);
  });
```

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/pages/specs --config vitest.local.config.ts` → FAIL.

- [ ] **Step 4: API JS** — criar `app/javascript/dashboard/api/ramonAgenteExecucoes.js`:

```js
/* global axios */
import ApiClient from './ApiClient';

// Aba "Agente Claude" das Execuções (I-EX4).
class RamonAgenteExecucoesAPI extends ApiClient {
  constructor() {
    super('ramon_agente_execucoes', { accountScoped: true });
  }

  list() {
    return axios.get(this.url);
  }
}

export default new RamonAgenteExecucoesAPI();
```

- [ ] **Step 5: `ExecucoesAgente.vue`** (Write):

```vue
<script setup>
// Aba "Agente Claude" das Execuções (I-EX4): a trilha que o runner da VPS grava
// em agente_execucoes a cada pedido numa nota — pedido, resposta, ações,
// duração — e o uso do teto do dia. Leitura pura; o custo fica em Uso e custo.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import RamonAgenteExecucoesAPI from 'dashboard/api/ramonAgenteExecucoes';
import {
  CARTAO,
  CHIP,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { LINK, STATUS_TOM, fmtHora, rotuloCaso, useAbrir } from './execucoes';

defineOptions({ name: 'CaptainExecucoesAgente' });

const { t } = useI18n();
const { abrirCaso, abrirConversa } = useAbrir();

const data = ref(null);
const loading = ref(true);
const error = ref(false);
const aberto = ref(null);

const fetchData = async () => {
  loading.value = true;
  error.value = false;
  try {
    const response = await RamonAgenteExecucoesAPI.list();
    data.value = response.data;
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(fetchData);

const resumo = computed(
  () => data.value?.resumo ?? { hoje: 0, teto: 0, problemas_hoje: 0 }
);
const items = computed(() => data.value?.items ?? []);

// texto montado no script: o template não aceita string crua (eslint i18n)
const meta = item =>
  [
    fmtHora(item.created_at),
    item.duracao_ms == null ? null : `${Math.round(item.duracao_ms / 1000)} s`,
    [item.modelo, item.esforco].filter(Boolean).join(' · ') || null,
  ]
    .filter(Boolean)
    .join(' · ');
const acaoTexto = acao => `${acao.tipo} → ${acao.ref}`;
const toggle = id => {
  aberto.value = aberto.value === id ? null : id;
};
</script>

<template>
  <div>
    <p class="text-sm text-n-slate-10">
      {{ t('INTEL.EXECUCOES.AGENTE.SUBTITULO') }}
    </p>

    <div
      v-if="error"
      data-testid="agente-erro"
      class="mt-4 text-sm"
      :class="CARTAO"
    >
      <p class="text-n-ruby-11">{{ t('CAPTAIN_RAMON.LOAD_ERROR') }}</p>
      <button type="button" class="mt-1" :class="LINK" @click="fetchData">
        {{ t('CAPTAIN_RAMON.RETRY') }}
      </button>
    </div>
    <p v-else-if="loading" class="mt-4 text-sm text-n-slate-10">
      {{ t('CAPTAIN_RAMON.LOADING') }}
    </p>

    <template v-else>
      <div class="flex flex-wrap gap-1.5 mt-4">
        <span data-testid="agente-hoje" :class="[CHIP, TOM.blue]">
          {{
            t('INTEL.EXECUCOES.AGENTE.HOJE', {
              n: resumo.hoje,
              teto: resumo.teto,
            })
          }}
        </span>
        <span v-if="resumo.problemas_hoje" :class="[CHIP, TOM.ruby]">
          {{
            t('INTEL.EXECUCOES.AGENTE.PROBLEMAS', { n: resumo.problemas_hoje })
          }}
        </span>
      </div>

      <p
        v-if="!items.length"
        data-testid="agente-vazio"
        class="mt-4 text-sm text-n-slate-10"
      >
        {{ t('INTEL.EXECUCOES.AGENTE.VAZIO') }}
      </p>
      <ul v-else class="flex flex-col gap-2 mt-4 list-none">
        <li
          v-for="item in items"
          :key="item.id"
          data-testid="agente-linha"
          :class="CARTAO"
        >
          <div class="flex flex-wrap items-center gap-2">
            <span :class="[CHIP, STATUS_TOM[item.status] || TOM.slate]">
              {{ t(`INTEL.EXECUCOES.STATUS.${item.status}`) }}
            </span>
            <span class="ml-auto text-[11px] text-n-slate-10">
              {{ meta(item) }}
            </span>
          </div>
          <p class="mt-1 text-sm text-n-slate-12 whitespace-pre-line line-clamp-3">
            {{ item.pedido }}
          </p>
          <div class="flex flex-wrap items-center gap-3 mt-1">
            <button
              v-if="item.lead_id"
              type="button"
              data-testid="execucoes-caso"
              :class="LINK"
              @click="abrirCaso(item.lead_id)"
            >
              {{ rotuloCaso(t, item) }}
            </button>
            <button
              v-if="item.conversa_display_id"
              type="button"
              data-testid="execucoes-conversa"
              :class="LINK"
              @click="abrirConversa(item.conversa_display_id)"
            >
              {{
                t('INTEL.EXECUCOES.CONVERSA', { id: item.conversa_display_id })
              }}
            </button>
            <button
              type="button"
              data-testid="agente-ver"
              :class="LINK"
              @click="toggle(item.id)"
            >
              {{
                aberto === item.id
                  ? t('INTEL.EXECUCOES.AGENTE.ESCONDER')
                  : t('INTEL.EXECUCOES.AGENTE.VER_RESULTADO')
              }}
            </button>
          </div>
          <div
            v-if="aberto === item.id"
            data-testid="agente-detalhe"
            class="flex flex-col gap-2 mt-2"
          >
            <p
              class="p-2 overflow-auto text-xs whitespace-pre-wrap rounded-lg bg-n-alpha-2 text-n-slate-11 max-h-64"
            >
              {{ item.resumo || t('INTEL.EXECUCOES.AGENTE.SEM_RESUMO') }}
            </p>
            <p :class="TITULO">{{ t('INTEL.EXECUCOES.AGENTE.ACOES') }}</p>
            <ul
              v-if="(item.acoes || []).length"
              class="flex flex-col gap-1 list-none"
            >
              <li
                v-for="(acao, posicao) in item.acoes"
                :key="posicao"
                class="text-xs break-all text-n-slate-11"
              >
                {{ acaoTexto(acao) }}
              </li>
            </ul>
            <p v-else class="text-xs text-n-slate-10">
              {{ t('INTEL.EXECUCOES.AGENTE.NENHUMA_ACAO') }}
            </p>
          </div>
        </li>
      </ul>
    </template>
  </div>
</template>
```

- [ ] **Step 6: Abas na tela** — `Execucoes.vue` (Edit):
  - `import { useI18n } from 'vue-i18n';` → `import { useI18n } from 'vue-i18n';` + nova linha `import { useRoute } from 'vue-router';`;
  - no import do kit, acrescentar `ABA, ABA_ATIVA, ABA_INATIVA,` antes de `CARTAO,`;
  - depois de `import { LINK, STATUS_TOM, fmtHora, rotuloCaso, useAbrir } from './execucoes';` acrescentar `import ExecucoesAgente from './ExecucoesAgente.vue';`;
  - depois de `const { abrirCaso, abrirConversa } = useAbrir();` acrescentar
    ```js
    // I-EX4: a Visão geral abre direto a aba do agente com ?aba=agente.
    const route = useRoute();
    const ABAS = ['ferramentas', 'agente'];
    const aba = ref(route?.query?.aba === 'agente' ? 'agente' : 'ferramentas');
    const rotuloAba = item =>
      item === 'agente'
        ? t('INTEL.EXECUCOES.ABA_AGENTE')
        : t('INTEL.EXECUCOES.ABA_FERRAMENTAS');
    ```
  - no template, trocar
    ```html
          <p class="mt-1 text-sm text-n-slate-10">
            {{ t('CAPTAIN_RAMON.EXECUCOES.SUBTITLE') }}
          </p>
    ```
    por
    ```html
          <nav class="flex gap-1 mt-3 border-b border-n-weak">
            <button
              v-for="item in ABAS"
              :key="item"
              type="button"
              :data-testid="`execucoes-aba-${item}`"
              :class="[ABA, aba === item ? ABA_ATIVA : ABA_INATIVA]"
              @click="aba = item"
            >
              {{ rotuloAba(item) }}
            </button>
          </nav>

          <ExecucoesAgente v-if="aba === 'agente'" class="mt-4" />
          <p v-else class="mt-4 text-sm text-n-slate-10">
            {{ t('CAPTAIN_RAMON.EXECUCOES.SUBTITLE') }}
          </p>
    ```
  - envolver o bloco de ferramentas existente: logo antes do `<div v-if="error" data-testid="execucoes-error" …>` abrir `<template v-if="aba === 'ferramentas'">`, e fechar `</template>` logo depois do `</template>` que fecha o `<template v-else>` dos contadores/lista (antes do `</div>` do `max-w-5xl`). O `<div v-if="error">` e o `<template v-else>` ficam como estão, só um nível mais para dentro.

  VisaoGeral.vue (Edit):
  - `const ir = (name, params = {}) => router.push(accountScopedRoute(name, params));` → `const ir = (name, params = {}, query = {}) => router.push(accountScopedRoute(name, params, query));`;
  - no bloco `data-testid="vg-agente"`, depois do `</p>` do parágrafo `AGENTE.ULTIMA`/`AGENTE.NUNCA` (último filho antes do `</section>`), acrescentar
    ```html
              <Button
                class="mt-2"
                size="xs"
                variant="ghost"
                color="slate"
                icon="i-lucide-arrow-right"
                data-testid="vg-agente-trilha"
                :label="t('INTEL.VISAO_GERAL.VER_TRILHA')"
                @click="ir('captain_execucoes_index', {}, { aba: 'agente' })"
              />
    ```

- [ ] **Step 7: Rodar** — `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain --config vitest.local.config.ts` → PASS. `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/pages app/javascript/dashboard/api/ramonAgenteExecucoes.js` → sem `error`. Rastrear à mão o Ruby: `slice` devolve hash com chaves string, `merge` com símbolos vira string no JSON; `includes(:lead)` com o `default_scope` ordenado de `Lead` é seguro (sem `distinct`); método `index` com AbcSize < 15.

- [ ] **Step 8: Commit**

```bash
git add app/models/agente_execucao.rb app/controllers/api/v1/accounts/ramon_inteligencia_controller.rb app/controllers/api/v1/accounts/ramon_agente_execucoes_controller.rb config/routes.rb spec/controllers/api/v1/accounts/ramon_agente_execucoes_controller_spec.rb app/javascript/dashboard/api/ramonAgenteExecucoes.js app/javascript/dashboard/routes/dashboard/captain/pages/ExecucoesAgente.vue app/javascript/dashboard/routes/dashboard/captain/pages/specs/ExecucoesAgente.spec.js app/javascript/dashboard/routes/dashboard/captain/pages/Execucoes.vue app/javascript/dashboard/routes/dashboard/captain/pages/specs/Execucoes.spec.js app/javascript/dashboard/routes/dashboard/captain/pages/VisaoGeral.vue
git commit -m "feat(ia): aba Agente Claude nas Execuções com a trilha dos pedidos e o uso do dia" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 10: I-WD2 — sugestões da Visão geral abrem o Centro já aberto e filtrado

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/command/NightCopilot.vue`, `app/javascript/dashboard/routes/dashboard/ramon/pages/CommandCenter.vue`, `app/javascript/dashboard/routes/dashboard/captain/pages/VisaoGeral.vue`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/components/command/specs/NightCopilot.spec.js`, `app/javascript/dashboard/routes/dashboard/ramon/pages/specs/CommandCenter.spec.js`

**Interfaces:**
- Consumes: `ir(name, params, query)` da Visão geral (Task 9); tipo da sugestão = `payload.acao || kind` (mesma regra do `ramon_inteligencia_controller#aprovacoes`: `COALESCE(payload->>'acao', kind)`); rótulos `CAPTAIN_RAMON.VISAO_GERAL.APROVACOES.TIPO.<tipo>` (já existem).
- Produces: rota `ramon_index?sugestoes=todas|<tipo>`; `NightCopilot` prop `foco: String` ('' = comportamento de hoje; `'todas'` = abre; `<tipo>` = abre e filtra).

- [ ] **Step 1: Specs (falham)** — `NightCopilot.spec.js` (Edit):
  - trocar o `mountBlock` por
    ```js
    const mountBlock = async (props = {}) => {
      const wrapper = mount(NightCopilot, {
        props,
        global: { mocks: { $t: k => k } },
      });
      await flushPromises();
      return wrapper;
    };
    ```
  - acrescentar no fim do `describe`:
    ```js
      it('foco "todas" abre o bloco mesmo recolhido no navegador, sem gravar', async () => {
        localStorage.setItem('ramon_night_copilot_expanded', '0');
        const wrapper = await mountBlock({ foco: 'todas' });
        expect(
          wrapper.findAll('[data-testid="night-copilot-card"]')
        ).toHaveLength(3);
        expect(localStorage.getItem('ramon_night_copilot_expanded')).toBe('0');
      });

      it('foco num tipo filtra, esconde Aprovar todas e "ver todas" volta', async () => {
        const wrapper = await mountBlock({ foco: 'move_stage' });
        const cards = wrapper.findAll('[data-testid="night-copilot-card"]');
        expect(cards).toHaveLength(1);
        expect(cards[0].text()).toContain('Ivone Castro Dias');
        expect(
          wrapper.find('[data-testid="night-copilot-filtro"]').text()
        ).toContain('INTEL.SUGESTOES.SO_TIPO');
        expect(
          wrapper.find('[data-testid="night-copilot-apply-all"]').exists()
        ).toBe(false);

        await wrapper
          .find('[data-testid="night-copilot-ver-todas"]')
          .trigger('click');
        expect(
          wrapper.findAll('[data-testid="night-copilot-card"]')
        ).toHaveLength(3);
        expect(
          wrapper.find('[data-testid="night-copilot-apply-all"]').exists()
        ).toBe(true);
      });

      it('foco num tipo sem sugestão avisa', async () => {
        const wrapper = await mountBlock({ foco: 'zapsign' });
        expect(wrapper.findAll('[data-testid="night-copilot-card"]')).toHaveLength(0);
        expect(wrapper.text()).toContain('INTEL.SUGESTOES.NENHUMA_DO_TIPO');
      });
    ```

  `CommandCenter.spec.js` (Edit):
  - trocar `vi.mock('vue-router', () => ({ useRouter: () => ({ push: routerPush }) }));` por
    ```js
    let routeQuery = {};
    vi.mock('vue-router', () => ({
      useRouter: () => ({ push: routerPush }),
      useRoute: () => ({ query: routeQuery }),
    }));
    ```
  - no `beforeEach` do `describe('CommandCenter.vue'`, acrescentar `routeQuery = {};`;
  - acrescentar no fim do `describe`:
    ```js
      it('passes ?sugestoes from the Visão geral to the night copilot block', async () => {
        routeQuery = { sugestoes: 'move_stage' };
        const wrapper = await mountPage();
        expect(wrapper.find('night-copilot-stub').attributes('foco')).toBe(
          'move_stage'
        );
      });
    ```

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/ramon/components/command/specs/NightCopilot.spec.js app/javascript/dashboard/routes/dashboard/ramon/pages/specs/CommandCenter.spec.js --config vitest.local.config.ts` → FAIL nos novos.

- [ ] **Step 2: `NightCopilot.vue`** (Edit):
  - `import { computed, onMounted, ref } from 'vue';` → `import { computed, nextTick, onMounted, ref, watch } from 'vue';`;
  - depois de `const getters = useStoreGetters();` acrescentar
    ```js
    // I-WD2: a Visão geral abre o Centro com ?sugestoes=todas|<tipo> — o bloco já
    // vem aberto (sem gravar a preferência), rolado até aqui e, com tipo, filtrado.
    const props = defineProps({ foco: { type: String, default: '' } });
    ```
  - trocar `const expanded = ref(readExpanded());` por `const expanded = ref(props.foco ? true : readExpanded());`;
  - depois do computed `bulkCount`, acrescentar
    ```js

    // Tipo = a ação em sistema ou o kind (igual ao contador da Visão geral).
    const tipoDe = s => s.payload?.acao || s.kind;
    const tipoFiltro = ref(props.foco && props.foco !== 'todas' ? props.foco : '');
    const visiveis = computed(() =>
      tipoFiltro.value
        ? suggestions.value.filter(s => tipoDe(s) === tipoFiltro.value)
        : suggestions.value
    );
    const rotuloTipo = computed(() =>
      t(`CAPTAIN_RAMON.VISAO_GERAL.APROVACOES.TIPO.${tipoFiltro.value}`)
    );

    // Rola até o bloco quando as sugestões chegam (o bloco só existe com > 0).
    const raiz = ref(null);
    let rolou = false;
    watch(
      () => suggestions.value.length,
      total => {
        if (!total || !props.foco || rolou) return;
        rolou = true;
        nextTick(() =>
          raiz.value?.scrollIntoView?.({ behavior: 'smooth', block: 'start' })
        );
      },
      { immediate: true }
    );
    ```
  - no template, na `<section v-else-if="suggestions.length" data-testid="night-copilot" …>`, acrescentar o atributo `ref="raiz"`;
  - no `<Button v-if="bulkCount" data-testid="night-copilot-apply-all" …>`, trocar `v-if="bulkCount"` por `v-if="bulkCount && !tipoFiltro"` (com filtro, "Aprovar todas" aprovaria o que não se vê);
  - trocar `    <div v-if="expanded" class="flex flex-col gap-3">` por
    ```html
        <div v-if="expanded" class="flex flex-col gap-3">
          <div
            v-if="tipoFiltro"
            data-testid="night-copilot-filtro"
            class="flex items-center gap-2 mt-2"
          >
            <span :class="[CHIP, TOM.amber]">
              {{ t('INTEL.SUGESTOES.SO_TIPO', { tipo: rotuloTipo }) }}
            </span>
            <Button
              data-testid="night-copilot-ver-todas"
              link
              xs
              :label="t('INTEL.SUGESTOES.VER_TODAS')"
              @click="tipoFiltro = ''"
            />
          </div>
          <p
            v-if="tipoFiltro && !visiveis.length"
            class="text-xs text-n-slate-10"
          >
            {{ t('INTEL.SUGESTOES.NENHUMA_DO_TIPO') }}
          </p>
    ```
  - trocar `v-for="suggestion in suggestions"` (o dos cartões) por `v-for="suggestion in visiveis"`.

- [ ] **Step 3: `CommandCenter.vue`** (Edit): `import { useRouter } from 'vue-router';` → `import { useRoute, useRouter } from 'vue-router';`; depois de `const router = useRouter();` acrescentar

```js
// I-WD2: ?sugestoes=todas|<tipo> vindo da Visão geral abre e filtra o bloco.
const route = useRoute();
const focoSugestoes = computed(() => String(route?.query?.sugestoes || ''));
```

e no template trocar `    <NightCopilot />` por `    <NightCopilot :foco="focoSugestoes" />`.

- [ ] **Step 4: `VisaoGeral.vue`** (Edit): no bloco `vg-aprovacoes`, trocar

```html
              <span
                v-for="(n, tipo) in aprovacoes.sugestoes_por_tipo"
                :key="tipo"
                :class="[CHIP, TOM.amber]"
              >
```

por

```html
              <button
                v-for="(n, tipo) in aprovacoes.sugestoes_por_tipo"
                :key="tipo"
                type="button"
                data-testid="vg-sugestao-tipo"
                class="hover:underline"
                :class="[CHIP, TOM.amber]"
                @click="ir('ramon_index', {}, { sugestoes: tipo })"
              >
```

(fechar com `</button>` no lugar do `</span>` correspondente) e, no `<Button … :label="t('CAPTAIN_RAMON.VISAO_GERAL.APROVACOES.ABRIR_SUGESTOES')"`, trocar `@click="ir('ramon_index')"` por `@click="ir('ramon_index', {}, { sugestoes: 'todas' })"`.

- [ ] **Step 5: Rodar** — `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/ramon/components/command/specs app/javascript/dashboard/routes/dashboard/ramon/pages/specs/CommandCenter.spec.js app/javascript/dashboard/routes/dashboard/captain --config vitest.local.config.ts` → PASS. `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/ramon/components/command/NightCopilot.vue app/javascript/dashboard/routes/dashboard/ramon/pages/CommandCenter.vue app/javascript/dashboard/routes/dashboard/captain/pages/VisaoGeral.vue` → sem `error`.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/components/command/NightCopilot.vue app/javascript/dashboard/routes/dashboard/ramon/components/command/specs/NightCopilot.spec.js app/javascript/dashboard/routes/dashboard/ramon/pages/CommandCenter.vue app/javascript/dashboard/routes/dashboard/ramon/pages/specs/CommandCenter.spec.js app/javascript/dashboard/routes/dashboard/captain/pages/VisaoGeral.vue
git commit -m "feat(ia): sugestões pendentes da Visão geral abrem o Centro já aberto e filtrado por tipo" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 11: Story — fixtures e variantes para os prints

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue`, `app/javascript/dashboard/routes/dashboard/ramon/pages/CentroComando.story.vue`

**Interfaces:**
- Produces: variantes `FAQs` (com tese), `FAQs testar pergunta`, `Documentos` (com texto colado), `Documentos novo` (abas), `Documentos novo texto`, `Skills` (chaves + "Editada aqui"), `Skills desligadas`, `Execucoes` (links), `Execucoes agente`, `Visao geral` (chips clicáveis + "Ver a trilha"), `Centro sugestoes filtradas`. Dados **fictícios** (só story).

- [ ] **Step 1: `Inteligencia.story.vue`** (Edit):
  - nos `FAQS`, acrescentar `tese: 'geral',` no item `id: 1` e `tese: 'auxilio-acidente',` no item `id: 2`; nos `PENDENTES`, `tese: null,`;
  - nos `SKILLS`, acrescentar `enabled: true,` em cada um dos 4, `edited: true,` no `id: 2`, e um 5º:
    ```js
      {
        id: 5,
        title: 'Lead pediu desconto no honorário',
        description: 'Quando o lead pede para baixar o 30% + 3.',
        instruction: 'Explique com calma que o honorário é fixo e só é pago se o benefício sair.',
        tools: null,
        enabled: false,
        edited: false,
      },
    ```
  - nos `DOCS`, acrescentar um 2º:
    ```js
      {
        id: 2,
        name: 'Honorários — resumo da equipe',
        external_link: 'TEXT: Honorários — resumo da equipe_20261007093000000',
        text_document: true,
        status: 'available',
        sync_status: null,
        assistant: ASSISTENTE_FAQ,
        created_at: unix(1),
        updated_at: unix(1),
      },
    ```
  - no `.map(...)` dos `RUNS`, depois de `assistant_id: 1,` acrescentar
    ```js
      lead_nome: i === 3 ? null : 'Maria Souza',
      conversa_display_id: i === 3 ? null : 482,
      assistente_nome: ATENDIMENTO.name,
    ```
    e trocar `lead_id: 123,` por `lead_id: i === 3 ? null : 123,`;
  - depois do `const RUNS = …;`, acrescentar
    ```js
    const AGENTE = [
      {
        id: 3,
        pedido: 'resuma o caso da Maria e veja se tem perícia marcada',
        status: 'ok',
        resumo: 'Caso 123: auxílio-acidente, perícia marcada para 14/10 às 9h. Anotei na tarefa do AdvBox.',
        acoes: [{ tipo: 'advbox_tarefa', ref: 'resp=12 {"id": 991}' }],
        modelo: 'claude-opus',
        esforco: 'low',
        duracao_ms: 48000,
        lead_id: 123,
        lead_nome: 'Maria Souza',
        conversa_display_id: 482,
        created_at: diasAtras(0.05),
      },
      {
        id: 2,
        pedido: 'gere o PDF do cálculo e suba no Drive',
        status: 'erro',
        resumo: 'O motor de cálculos não respondeu.',
        acoes: [],
        modelo: 'claude-opus',
        esforco: 'medium',
        duracao_ms: 120000,
        lead_id: 77,
        lead_nome: 'José Ribeiro',
        conversa_display_id: 470,
        created_at: diasAtras(0.2),
      },
      {
        id: 1,
        pedido: 'quais documentos faltam?',
        status: 'cap',
        resumo: 'Cap diário atingido (30)',
        acoes: [],
        modelo: null,
        esforco: null,
        duracao_ms: null,
        lead_id: null,
        lead_nome: null,
        conversa_display_id: 455,
        created_at: diasAtras(1.1),
      },
    ];
    ```
  - no objeto `API`, acrescentar
    ```js
      'captain/assistants/1/buscar_faq': {
        payload: FAQS.map(({ id, question, answer, tese }) => ({
          id,
          question,
          answer,
          tese,
        })),
      },
      ramon_agente_execucoes: {
        resumo: { hoje: 4, teto: 30, problemas_hoje: 1 },
        items: AGENTE,
      },
    ```
  - trocar o helper `clicarEm` por
    ```js
    // Clica no botão cujo texto contém `texto`, depois de a tela montar.
    const clicar = texto =>
      [...document.querySelectorAll('button')]
        .find(botao => botao.textContent.includes(texto))
        ?.click();
    const clicarEm = texto => () => setTimeout(() => clicar(texto), 2000);
    // Vários cliques em sequência (abrir diálogo e trocar de aba).
    const clicarNaOrdem = textos => () =>
      textos.forEach((texto, i) =>
        setTimeout(() => clicar(texto), 2000 + i * 600)
      );
    // Digita no "Testar pergunta" e clica em Testar.
    const testarPergunta = texto => () =>
      setTimeout(() => {
        const campo = document.querySelector(
          '[data-testid="testar-pergunta-campo"]'
        );
        if (!campo) return;
        campo.value = texto;
        campo.dispatchEvent(new Event('input'));
        setTimeout(
          () =>
            [...document.querySelectorAll('button')]
              .find(botao => botao.textContent.trim() === 'Testar')
              ?.click(),
          200
        );
      }, 2000);
    const abaAgente = () => {
      rota.query = { aba: 'agente' };
    };
    ```
  - no template, depois da variante `FAQs pendentes`, acrescentar
    ```html
        <Variant
          title="FAQs testar pergunta"
          :init-state="testarPergunta('posso trabalhar recebendo auxílio-acidente?')"
        >
          <div class="h-screen"><ResponsesIndex /></div>
        </Variant>
    ```
    depois da variante `Documentos novo` (o bloco inteiro dela), acrescentar
    ```html
        <Variant
          title="Documentos novo texto"
          :init-state="clicarNaOrdem(['Criar um novo documento', 'Colar texto'])"
        >
          <div class="h-screen"><DocumentsIndex /></div>
        </Variant>
    ```
    depois da variante `Skills`, acrescentar
    ```html
        <Variant title="Skills desligadas" :init-state="clicarEm('Desligadas')">
          <div class="h-screen"><ScenariosIndex /></div>
        </Variant>
    ```
    e depois da variante `Execucoes`, acrescentar
    ```html
        <Variant title="Execucoes agente" :init-state="abaAgente">
          <div class="h-screen"><Execucoes /></div>
        </Variant>
    ```
  (A variante `Documentos novo` já existente abre o diálogo pelo texto do botão `Criar um novo documento`; conferir no print que é esse o rótulo — se não for, usar o rótulo que a variante existente usa.)

- [ ] **Step 2: `CentroComando.story.vue`** (Edit):
  - `import { useI18n } from 'vue-i18n';` → 
    ```js
    import { provide, reactive } from 'vue';
    import { routeLocationKey } from 'vue-router';
    import { useI18n } from 'vue-i18n';
    ```
  - depois de `locale.value = 'pt_BR';` acrescentar
    ```js
    // I-WD2: o Centro lê ?sugestoes= da rota (vindo da Visão geral).
    const rota = reactive({ query: {} });
    provide(routeLocationKey, rota);
    const sugestoesFiltradas = () => {
      localStorage.setItem('ramon_night_copilot_expanded', '0');
      rota.query = { sugestoes: 'move_stage' };
    };
    ```
  - no template, depois da variante `Centro copiloto aberto`, acrescentar
    ```html
        <Variant title="Centro sugestoes filtradas" :init-state="sugestoesFiltradas">
          <div class="h-screen">
            <CommandCenter />
          </div>
        </Variant>
    ```

- [ ] **Step 3: Lint** — `./node_modules/.bin/eslint --fix app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue app/javascript/dashboard/routes/dashboard/ramon/pages/CentroComando.story.vue` e depois sem `--fix` → sem `error`.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue app/javascript/dashboard/routes/dashboard/ramon/pages/CentroComando.story.vue
git commit -m "test(ia): story da A3 (tese, testar pergunta, texto colado, skills desligadas, agente, sugestões filtradas)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 12: Verificação final + prints "depois" + `comparar.html` + texto do PR

**Files:**
- Create (não versionado): `tmp/intel-a3-harness/telas-depois.txt`, `tmp/intel-a3-harness/comparar.mjs`
- Output: `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-07-inteligencia-a3\{depois-*.png,comparar.html}`

- [ ] **Step 1: Suíte JS** — `TZ=UTC npx vitest run app/javascript/dashboard/components-next/captain app/javascript/dashboard/routes/dashboard/captain app/javascript/dashboard/routes/dashboard/ramon/components/command/specs app/javascript/dashboard/routes/dashboard/ramon/pages/specs/CommandCenter.spec.js --config vitest.local.config.ts` → **34 arquivos** (28 da base + `IntelI18n`, `DocumentForm`, `ResponseForm`, `TestarPergunta`, `Execucoes`, `ExecucoesAgente`), todos verdes, mais de 250 testes. `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain app/javascript/dashboard/components-next/captain app/javascript/dashboard/routes/dashboard/ramon/components/command/NightCopilot.vue app/javascript/dashboard/routes/dashboard/ramon/pages/CommandCenter.vue app/javascript/dashboard/api` → sem `error`.

- [ ] **Step 2: Conferências de texto e de escopo**
  - `git diff origin/ramon --stat -- app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/components-next/sidebar/Sidebar.vue app/javascript/dashboard/routes/dashboard/captain/captain.routes.js` → **vazio** (não tocamos);
  - `grep -n "@" app/javascript/dashboard/i18n/locale/pt_BR/ramonIntel.json app/javascript/dashboard/i18n/locale/en/ramonIntel.json` → nada;
  - `grep -n "define(version" db/schema.rb` → `2026_10_07_500002`;
  - `grep -rn "text-n-iris" app/javascript/dashboard/routes/dashboard/captain/pages/Execucoes.vue app/javascript/dashboard/routes/dashboard/captain/pages/ExecucoesAgente.vue app/javascript/dashboard/routes/dashboard/captain/responses/TestarPergunta.vue` → nada.

- [ ] **Step 3: Prints "depois"** — criar `tmp/intel-a3-harness/telas-depois.txt` (Write):

```
intel:FAQs:faqs:1440,1300
intel:FAQs testar pergunta:faqs-testar:1440,1300
intel:FAQs pendentes:faqs-pendentes:1440,900
intel:Documentos:documentos:1440,900
intel:Documentos novo:documentos-novo:1440,900
intel:Documentos novo texto:documentos-novo-texto:1440,1000
intel:Skills:skills:1440,1600
intel:Skills desligadas:skills-desligadas:1440,900
intel:Execucoes:execucoes:1440,1100
intel:Execucoes agente:execucoes-agente:1440,1100
intel:Visao geral:visao-geral:1440,1900
centro:Centro sugestoes filtradas:centro-sugestoes:1440,1400
```

Com o harness no ar (Task 1; se caiu, subir de novo): `sh tmp/intel-a3-harness/shots.sh depois` → 24 arquivos `depois-*`. Abrir com Read pelo menos: `depois-claro-faqs.png` (filtro de tese + cartão Testar pergunta + chips azuis de tese), `depois-escuro-faqs-testar.png` (lista numerada), `depois-claro-documentos-novo-texto.png` (abas Link/Colar texto, campo grande), `depois-claro-documentos.png` (cartão "Texto colado" sem status de sincronização), `depois-claro-skills.png` (abas, chaves, "Editada aqui"), `depois-escuro-execucoes.png` (links azuis, chip do assistente, sem roxo), `depois-claro-execucoes-agente.png`, `depois-claro-centro-sugestoes.png` (bloco aberto, chip "Só: mudar etapa", sem "Aprovar todas"). Fundo de chip/aviso translúcido nos dois temas; nada de texto cobrindo texto.

- [ ] **Step 4: `comparar.html`** — criar `tmp/intel-a3-harness/comparar.mjs` (Write):

```js
// Gera comparar.html (antes × depois, claro/escuro) na pasta dos prints da A3.
import { writeFileSync } from 'node:fs';

const OUT =
  'C:/Users/dudsl/RAdvogados/comercial/docs/mockups/2026-10-07-inteligencia-a3';
// [nome, arquivo antes (null = tela nova), arquivo depois, itens do backlog]
const TELAS = [
  ['FAQs — tese e Testar pergunta', 'faqs', 'faqs', 'I-FQ1, I-FQ2'],
  ['FAQs — Testar pergunta com resultado', null, 'faqs-testar', 'I-FQ2'],
  ['FAQs pendentes', 'faqs-pendentes', 'faqs-pendentes', 'I-FQ1'],
  ['Documentos', 'documentos', 'documentos', 'I-DO1'],
  ['Documentos — novo (link)', 'documentos-novo', 'documentos-novo', 'I-DO1'],
  ['Documentos — novo (colar texto)', null, 'documentos-novo-texto', 'I-DO1'],
  ['Skills', 'skills', 'skills', 'I-SK4, I-SK5'],
  ['Skills — desligadas', null, 'skills-desligadas', 'I-SK4'],
  ['Execuções', 'execucoes', 'execucoes', 'I-EX2'],
  ['Execuções — Agente Claude', null, 'execucoes-agente', 'I-EX4'],
  ['Visão geral', 'visao-geral', 'visao-geral', 'I-WD2, I-EX4'],
  ['Centro — sugestões da IA', 'centro-sugestoes', 'centro-sugestoes', 'I-WD2'],
];

const fig = (rotulo, arq, nome, tema) =>
  `<figure><figcaption>${rotulo}</figcaption><img src="${arq}" alt="${rotulo}, ${nome}, tema ${tema}"></figure>`;
const secoes = TELAS.flatMap(([nome, antes, depois, itens]) =>
  ['claro', 'escuro'].map(tema => {
    const figAntes = antes
      ? fig('Antes', `antes-${tema}-${antes}.png`, nome, tema)
      : '<figure><figcaption>Antes</figcaption><p>Tela nova.</p></figure>';
    return `<section><h2>${nome} · ${itens} · tema ${tema}</h2><div class="par">${figAntes}${fig('Depois (A3)', `depois-${tema}-${depois}.png`, nome, tema)}</div></section>`;
  })
).join('');
const css =
  'body{font:14px system-ui,sans-serif;margin:24px;background:#f4f4f4;color:#111}h1{font-size:20px}h2{font-size:15px;margin:28px 0 8px}.par{display:flex;gap:24px;align-items:flex-start;flex-wrap:wrap}figure{margin:0;background:#fff;padding:8px;border:1px solid #ddd;border-radius:8px}figcaption{font-weight:600;margin-bottom:6px}img{width:700px;max-width:100%;display:block}';

writeFileSync(
  `${OUT}/comparar.html`,
  `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>Inteligência A3 — antes e depois</title><style>${css}</style></head><body><h1>Inteligência — pacote A3: antes e depois</h1><p>Sem mockup aprovado para a A3 (telas existentes ganhando função): a aprovação é por antes × depois, como na A1 e na A2. Dados das telas são fictícios (story).</p>${secoes}</body></html>`
);
console.log(`ok ${OUT}/comparar.html`);
```

Run: `node tmp/intel-a3-harness/comparar.mjs` → `ok …/comparar.html`.

- [ ] **Step 5: Derrubar o harness** (parar o `npx vite` em segundo plano) e conferir `git status`: limpo (só `tmp/`, ignorado).

- [ ] **Step 6: Texto do PR** (para a sessão principal abrir depois do "aprovado"):

```markdown
# feat(ia): Inteligência A3 — colar texto, FAQ por tese, testar pergunta, skills liga/desliga, Execuções com links e agente Claude

## O que muda
- **Documentos:** opção "Colar texto" (título + texto, até 200 mil caracteres) → vira FAQs pendentes; cartão "Texto colado"; filtro de fonte "Texto colado" no lugar de "PDFs" (PDF não funciona aqui).
- **FAQs:** cada FAQ guarda a **tese** (do nome do arquivo do seed; editável na tela); filtro por tese (e "Sem tese"); etiqueta azul no cartão; cartão **"Testar pergunta"** mostra as FAQs que o assistente acharia, na ordem (a mesma busca do `faq_lookup`).
- **Skills:** abas **Ligadas / Desligadas**, chave liga/desliga (admin), marca "Editada aqui". Desligar sempre funciona (mesmo skill antiga com ferramenta que saiu do catálogo). O **seed não sobrescreve, não religa, não desliga e não duplica** skill editada, renomeada ou criada na tela.
- **Execuções:** caso, conversa e assistente em cada linha, clicáveis; tela no kit visual. Nova aba **Agente Claude** com a trilha dos pedidos (pedido, resposta, ações, duração, uso do teto do dia); a Visão geral ganhou "Ver a trilha do agente".
- **Visão geral → Centro (I-WD2):** clicar num tipo de sugestão (ou em "Abrir no Centro de Comando") abre o "Enquanto você dormia" **já aberto**, rolado até ele e filtrado pelo tipo; com filtro, "Aprovar todas" some.
- Já entregue antes e não refeito: caderno de provas = Casos de teste (#214).

## Migrações
- `20261007500001_add_tese_to_captain_assistant_responses` (coluna `tese`)
- `20261007500002_add_edicao_to_captain_scenarios` (`edited`, `seed_titulo` = título atual nas existentes)

## Prints
`comercial/docs/mockups/2026-10-07-inteligencia-a3/comparar.html`

## Operação depois do deploy
1. Migrar à mão: `docker compose run --rm --no-deps chatwoot-web bundle exec rails db:migrate` (em `/opt/intranet-ramon`).
2. Preencher a tese das FAQs que já estão em produção, **sem rodar o seed inteiro**: `docker compose run --rm --no-deps chatwoot-web bundle exec rake 'ramon:inteligencia:teses[<id da conta>]'` (conferir o id com `rails runner 'p Account.pluck(:id, :name)'`). Saída esperada: `faq_com_tese_preenchida: ~62`.

## Smoke (bloco único)
1. **Documentos** → Criar → aba "Colar texto": título + texto → salvar → cartão "Texto colado"; em instantes, FAQs novas em FAQs → Pendentes. Filtro de fonte tem "Texto colado".
2. **FAQs:** etiqueta de tese nos cartões; filtro "Auxílio-acidente" mostra só essas; "Sem tese" mostra as de documento; editar uma FAQ e trocar a tese salva.
3. **FAQs → Testar pergunta:** "posso trabalhar recebendo auxílio-acidente?" → lista numerada; "foguete lunar" → aviso "não acharia nenhuma FAQ".
4. **Skills:** abas Ligadas/Desligadas; desligar uma → vai para Desligadas com aviso; religar → volta; editar uma → aparece "Editada aqui".
5. **Execuções:** cada linha com "Caso #… · nome" (abre o Funil no caso) e "Conversa #…" (abre a conversa) e o assistente; aba **Agente Claude** com os pedidos de hoje e "ver o que o agente respondeu".
6. **Visão geral:** clicar em "mudar etapa: N" → Centro com o "Enquanto você dormia" aberto só com as de mudar etapa e sem "Aprovar todas"; "ver todas" volta. "Ver a trilha do agente" → Execuções na aba Agente Claude.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR
```

- [ ] **Step 7: Parar aqui** — sem push e sem PR (gate do Eduardo / sessão principal). Reportar: commits, resultado do vitest/eslint, caminho clicável `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-07-inteligencia-a3\comparar.html` + a pasta, e a tabela de decisões abaixo. Lembrete: o CI valida os specs Ruby (Tasks 2, 3, 5, 6, 8, 9) e o rubocop — sem Ruby local. **Push/PR só depois do "aprovado".**

---

## Decisões novas que dependem do Eduardo

| # | Decisão | Proposta do plano | Onde |
|---|---|---|---|
| N1 | **Lista de teses das FAQs** = as 6 dos arquivos de hoje: auxílio-acidente, auxílio-doença, aposentadoria por invalidez, BPC/LOAS, acréscimo de 25% e geral. Tese nova (ex.: aposentadoria por idade, trabalhista) = um arquivo novo de FAQ + uma linha no código | Aceitar as 6 agora; as outras entram quando houver FAQs delas | Tasks 3, 4 |
| N2 | **"Caderno de provas"** já virou a aba "Casos de teste" (#214: 43 casos, Rodar todos, ✅/❌, histórico). O backlog falava também em "1 clique manda a fala no Testar (conversa)" | Considerar entregue; não fazer o botão extra (o caso de teste já roda a fala em modo seguro e mostra o resultado) | Escopo |
| N3 | **Quem liga/desliga skill:** só administrador (agente vê as abas e as skills, sem a chave) | Só admin (igual a editar/excluir skill hoje) | Task 7 |
| N4 | **O seed também sobrescreve** a descrição, as Proteções e as Diretrizes do assistente quando roda inteiro (só as skills e FAQs ganham a regra "editada fica") | Não mexer agora; **não rodar o seed inteiro em produção** sem conferir — para as teses, usar o rake só-de-teses. Se quiser a mesma proteção nas Proteções/Diretrizes, vira item da próxima fatia | Operação |
| N5 | **Aba Agente Claude visível para agentes** (pedido e resposta do @claude), sem custo | Sim, mesma permissão das Execuções; custo continua só em Uso e custo (admin) | Task 9 |
| N6 | **Filtro de fonte dos Documentos:** sai "PDFs", entra "Texto colado" | Aceitar (PDF não funciona aqui; quem tiver PDF cola o texto) | Task 2 |
| N7 | **Aprovação visual por antes × depois** (como A1/A2) — a A3 não tem mockup prévio, são telas existentes ganhando função | Aceitar; se preferir ver mockup antes de implementar alguma tela (ex.: aba Agente Claude), dizer qual | Task 12 |


## Respostas do Eduardo (07/10/2026)

Todas as "Decisões novas que dependem do Eduardo" deste plano foram **ACEITAS como propostas** (formulário de 07/10).
