# Automações em fluxo — B2 (o quadro) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar ao hub a tela de Automações — lista de fluxos, editor tipo n8n (Vue Flow, vertical), versões, ensaio com um lead real, execução com caminho aceso e modelos prontos — em cima do motor e da API da B1 que já estão no ar.

**Architecture:** Tudo novo mora em `app/javascript/dashboard/routes/dashboard/captain/automacoes/` (3 telas + componentes do quadro) e num API client `api/ramonFluxos.js`. O desenho salvo (`{nos, setas}`, contrato da B1) é convertido de/para o formato do Vue Flow por funções puras (`fluxo.js`); a validação do front espelha `Ramon::Fluxos::Grafo#erros` (`validar.js`); o estado do editor é um composable (`useFluxoEditor.js`) que salva o rascunho sozinho 1 s depois da última mudança. Back: só 1 linha (a execução devolve o desenho em que rodou), sem migração.

**Tech Stack:** Vue 3.5 `<script setup>`, `@vue-flow/core` 1.48.2 + `@vue-flow/minimap` 1.5.4 (MIT, dependência nova), Vuex (getters já existentes), `@vueuse/core` 12 (`watchDebounced`, `onClickOutside`, `onKeyStroke`, `useDebounceFn`), Tailwind (tokens `n-*`, kit `ramon/helpers/ui.js`), vue-i18n 9 (en + pt_BR), Vitest 3 + @vue/test-utils, RSpec (só no CI).

**Spec:** `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (§7 Tela, §10 fatia B2). Alvo visual fiel: `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-05-inteligencia-fluxos\fluxos.html` (+ `print-{lista,editor,execucao,novo}-{light,dark}.png`).

## Global Constraints

- Base: `origin/ramon` em **29c73b0** (`feat(inteligencia): faxina da área (A1) (#198)`) — a branch `feat/fluxos-b2` já foi avançada (fast-forward) de d416f48 para 29c73b0 ao escrever este plano. O PR #198 JÁ ESTÁ MERGEADO: o menu Inteligência já tem "Vigia" no topo, logo a inserção de "Automações" logo depois dele não conflita com nada (se outra reordenação entrar antes do merge da B2, o conflito é de 1 bloco `{ name: 'Automacoes', … }` no array `children` do grupo `Captain` em `Sidebar.vue`).
- Dependência nova ÚNICA de runtime: `@vue-flow/core@1.48.2` e `@vue-flow/minimap@1.5.4` (ambas MIT, peer `vue ^3.3.0` — compatível com `vue ^3.5.12`). NÃO instalar `@vue-flow/controls` nem `@vue-flow/background` (3 botões de zoom próprios + fundo pontilhado Tailwind, como o mockup).
- `node_modules` deste worktree é uma JUNÇÃO para `ramon-hub-wt-funil-padrao\node_modules`. Antes de `pnpm add`: remover SÓ a junção (`cmd //c rmdir node_modules`) e rodar `npx --yes pnpm@10.2.0 install --frozen-lockfile` real no worktree. NUNCA `rm -rf node_modules` com a junção no lugar (apagaria o node_modules do outro worktree). Commitar `package.json` + `pnpm-lock.yaml`.
- pnpm não é global nesta máquina: sempre `npx --yes pnpm@10.2.0 …` (a 9 recusa por engines). Vitest: `TZ=UTC ./node_modules/.bin/vitest --no-watch <caminho>`. ESLint: `./node_modules/.bin/eslint <arquivos>` (erro `Delete ␍` = CRLF do checkout Windows, ignorar; CI Linux é limpo).
- Sem Ruby/Postgres local: specs Ruby só rodam no CI. Sem migração nesta fatia.
- Rotas novas na área Captain, ANTES do catch-all `:navigationPath` em `captain.routes.js`: `captain/automacoes` (lista), `captain/automacoes/:fluxoId` (editor), `captain/automacoes/:fluxoId/execucoes/:execId` (execução/ensaio). Meta = mesma `meta` da Captain com `permissions: ['administrator']` (a API é admin-only — `RamonFluxoPolicy#gerenciar?`).
- Só o que a B1 executa aparece: gatilhos = `Ramon::Fluxos::Grafo::GATILHOS` (10); passos = `TIPOS_PASSO` (11). Itens da B2b (IA, ADVBOX, webhook, preencher campo, trocar responsável, gatilhos externos, `lead_parado`, `relogio`) **não aparecem** (nem desabilitados).
- Desenho salvo = contrato da B1: `{ nos: [{id, tipo, config, posicao:{x,y}}], setas: [{de, saida, para}] }`, `saida ∈ s | sim | nao | <chave do caso> | outro`. Nó gatilho = `{ tipo: 'gatilho', config: { tipo: <GATILHO>, …filtros } }`. Chave extra opcional `config.rotulo` (nome do passo na tela) — o motor ignora chaves desconhecidas.
- Mensagem ao cliente SEMPRE rascunho: todo passo `rascunho_texto` mostra o selo "sai como rascunho" no quadro e o aviso âmbar no painel.
- Visual: kit do hub (`ramon/helpers/ui.js`: `CAMPO`, `SELECT`, `TEXTAREA`, `ROTULO`, `CHIP`, `TOM`, `AVISO`, `MENU`, `LINHA`, `ABA*`, `FUNDO_JANELA`, `JANELA`) + `components-next` (`Button`, `Switch`). Tailwind only; fundos coloridos translúcidos (`TOM.*`); claro e escuro. Únicas exceções: o CSS da própria biblioteca (`@vue-flow/core/dist/style.css`, `@vue-flow/minimap/dist/style.css`, precedente `floating-vue/dist/style.css`) e 1 `:style` de largura dinâmica da barrinha "hoje/limite" (precedente `FunnelConversion.vue`).
- Cores por categoria (mockup → kit): gatilho = `TOM.blue` + filete `border-l-4 border-l-n-blue-9`; condição (`se`, `escolha`) = `TOM.amber`; ações e controle = `TOM.slate`; ok/caminho aceso = **teal** (o kit não tem verde — `TOM.teal` é o "ok" do hub); erro = ruby; esperando = amber.
- i18n: chaves novas em `CAPTAIN_RAMON.FLUXOS` (`i18n/locale/{en,pt_BR}/ramon.json`) e `SIDEBAR.CAPTAIN_AUTOMACOES` (`i18n/locale/{en,pt_BR}/settings.json`). Strings SEM `@`, `|`, `{`, `}` crus — só placeholders `{nome}`; um spec trava isso.
- Lições do fork: evento custom Vue sempre camelCase (`update:config`, `selecionar`); listener de evento DA BIBLIOTECA fica em kebab no template (`@node-click`, regra `vue/v-on-event-hyphenation`); componente pesado (Vue Flow) só monta com dado pronto (`v-if`); página nova sempre `w-full h-full` na raiz; Action Vuex sem desestruturar `state`.
- Commits: Conventional Commits, sem citar Claude no assunto; corpo termina com:
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv`
- Sem push nem PR neste plano (gate do Eduardo); a última task deixa o texto do PR pronto.

## Review Focus

1. **Mudar e clicar "Publicar"/"Testar" antes do autosave de 1 s** — quem publica espera publicar o que está NA TELA. `publicar()`/`ensaiar()` sempre `await salvar()` antes (teste no Task 6: ordem update → publicar).
2. **Apagar um caso do `escolha` que já tinha seta** — a seta órfã some ao salvar, sem erro de "seta para porta inexistente" (teste do `deVueFlow` no Task 3).
3. **Ligar uma 2ª seta na mesma porta / fechar um laço** — a nova substitui a antiga; laço e ligação no próprio passo são recusados na hora (teste do `ligar` no Task 3).
4. **Erro do back no Publicar** — mensagem `Passo n7: …` acende o passo n7; mensagem sem passo vai para a faixa de erros do topo (teste do `idDoErro`/`nosComErro` nos Tasks 3 e 6).
5. **Fluxo sem `posicao` (criado pela API/B3) ou com `config` nulo** — abre sem quebrar, em (0,0) / `{}` (teste do `paraVueFlow` no Task 3).

---

## Mapa de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `package.json`, `pnpm-lock.yaml` | + `@vue-flow/core`, `@vue-flow/minimap` |
| `app/controllers/api/v1/accounts/ramon_fluxo_execucoes_controller.rb` | `show` devolve também `grafo` (desenho em que a execução rodou) |
| `spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb` | + 1 exemplo do `grafo` |
| `app/javascript/dashboard/api/ramonFluxos.js` | API client (CRUD + publicar, ensaio, rodar, execuções) |
| `…/captain/automacoes/fluxo.js` | catálogo (gatilhos, passos, paleta, ações do Chatwoot, campos, variáveis) + conversor desenho↔Vue Flow + operações puras do quadro |
| `…/captain/automacoes/validar.js` | espelho de `Ramon::Fluxos::Grafo#erros` |
| `…/captain/automacoes/modelos.js` | modelos prontos (só passos da B1) |
| `…/captain/automacoes/useFluxoEditor.js` | estado do editor: carregar, autosave, publicar, ensaiar, rodar |
| `…/captain/automacoes/Lista.vue` | tela 1 — lista + 4 números + liga/desliga |
| `…/captain/automacoes/NovoFluxo.vue` | modal "Novo fluxo" (em branco + modelos) |
| `…/captain/automacoes/Quadro.vue` | casca do Vue Flow (vertical, minimapa, zoom, estados) |
| `…/captain/automacoes/NoPasso.vue` | o cartão de um passo + portas |
| `…/captain/automacoes/Paleta.vue` | "+ Adicionar passo" por grupos |
| `…/captain/automacoes/PainelPasso.vue` | painel direito: config do passo selecionado |
| `…/captain/automacoes/ConfigGatilho.vue`, `ConfigCondicoes.vue`, `ConfigCasos.vue`, `ConfigAcoesChatwoot.vue`, `CampoTexto.vue`, `ListaMarcar.vue` | formulários do painel |
| `…/captain/automacoes/TestarComLead.vue` | modal "Testar com um lead…" (+ "Rodar de verdade" p/ gatilho manual) |
| `…/captain/automacoes/Editor.vue` | tela 2 — barra + quadro + painel + execuções recentes |
| `…/captain/automacoes/Execucao.vue` | tela 3 — caminho aceso + trilha |
| `…/captain/automacoes/Automacoes.story.vue` | story p/ prints (harness) |
| `…/captain/automacoes/specs/*.spec.js` | vitest |
| `…/captain/captain.routes.js` | 3 rotas |
| `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | item "Automações" após "Vigia" |
| `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json`, `…/settings.json` | textos |

(`…` = `app/javascript/dashboard/routes/dashboard`)

---

### Task 1: Dependência Vue Flow instalada de verdade no worktree

**Files:**
- Modify: `package.json`, `pnpm-lock.yaml`

**Interfaces:**
- Produces: `@vue-flow/core` (`VueFlow`, `useVueFlow`, `Handle`, `Position`, `Panel`) e `@vue-flow/minimap` (`MiniMap`) importáveis; `./node_modules/.bin/vitest` e `eslint` locais.

- [ ] **Step 1: Conferir a base**

Run: `git -C C:/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-fluxos-b2 log --oneline -1`
Expected: `29c73b0ecc feat(inteligencia): faxina da área (A1) (#198)` ou um commit acima dele. Se a branch ainda estiver em d416f48: `git fetch origin ramon && git merge --ff-only origin/ramon`.

- [ ] **Step 2: Trocar a junção por um node_modules real**

```bash
cd C:/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-fluxos-b2
cmd //c "dir /AL" | grep node_modules   # deve mostrar <JUNCTION> → ramon-hub-wt-funil-padrao
cmd //c rmdir node_modules              # remove SÓ a junção (nunca rm -rf aqui)
npx --yes pnpm@10.2.0 install --frozen-lockfile
```
Expected: install termina sem erro; `node_modules` agora é pasta real (`ls -la | grep node_modules` não mostra `->`).

- [ ] **Step 3: Adicionar as 2 dependências**

```bash
npx --yes pnpm@10.2.0 add @vue-flow/core@1.48.2 @vue-flow/minimap@1.5.4
grep -n '"@vue-flow' package.json
```
Expected: duas linhas em `dependencies` (`"@vue-flow/core": "1.48.2"` ou `"^1.48.2"`, idem minimap).

- [ ] **Step 4: Conferências do ambiente (lições do fork)**

```bash
node -e "require.resolve('postcss-import')" && echo postcss-ok
grep -c "update:nodes" node_modules/@vue-flow/core/dist/vue-flow-core.mjs
grep -n '"license"' node_modules/@vue-flow/core/package.json node_modules/@vue-flow/minimap/package.json
ls .husky/_/husky.sh
```
Expected: `postcss-ok`; contagem ≥ 1 (o componente `VueFlow` emite `update:nodes` → `v-model:nodes` funciona, base do editor); `"license": "MIT"` nas duas; `husky.sh` existe.
Se `postcss-import` falhar (lição 15/08: o pnpm 10 não hoisteia e o `postcss.config.js` exige na raiz):
```bash
p=$(ls -d node_modules/.pnpm/postcss-import@*/node_modules/postcss-import | head -1)
cmd //c mklink /J "node_modules\\postcss-import" "$(cygpath -w "$p")"
```
Se `.husky/_/husky.sh` faltar: `cp -r ../ramon-hub/.husky/_ .husky/` (lição: worktree novo precisa da cópia).

- [ ] **Step 5: Vitest roda local (sanidade)**

Run: `TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/ramon/helpers/specs`
Expected: PASS (specs já existentes).

- [ ] **Step 6: Commit**

```bash
git add package.json pnpm-lock.yaml
git commit -m "build(fluxos): vue flow (core + minimap) para o quadro de automações" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 2: Back — a execução devolve o desenho em que rodou

A tela de execução precisa desenhar a **versão** em que a execução rodou (ou o rascunho ensaiado), não o rascunho de agora. A B1 guarda isso (`contexto['grafo']` no ensaio do rascunho; `versao.grafo` no resto), mas o `show` não devolve.

**Files:**
- Modify: `app/controllers/api/v1/accounts/ramon_fluxo_execucoes_controller.rb:13-15`
- Test: `spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb` (novo exemplo no fim do `describe`)

**Interfaces:**
- Produces: `GET /api/v1/accounts/:account_id/ramon_fluxos/:id/execucoes/:exec_id` → `FluxoExecucao#resumo_json` + `grafo: {nos, setas}`.

- [ ] **Step 1: Escrever o exemplo (falha no CI até o Step 2)**

Adicionar antes do `end` final de `spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb`:

```ruby
  it 'uma execução devolve o desenho em que rodou' do
    fluxo = fluxo_publicado(account, grafo)
    execucao = Ramon::Fluxos::Disparo.ensaiar(fluxo, create(:lead, account: account), usar: 'publicada')
    fluxo.update!(rascunho: { nos: [], setas: [] }) # editar depois não muda o desenho da execução
    get "#{url}/#{fluxo.id}/execucoes/#{execucao.id}", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['grafo']['nos'].pluck('id')).to eq(%w[g p1])
  end
```

- [ ] **Step 2: Implementar**

Em `app/controllers/api/v1/accounts/ramon_fluxo_execucoes_controller.rb`, trocar o `show`:

```ruby
  def show
    execucao = fluxo.execucoes.find(params[:id])
    render json: execucao.resumo_json.merge(grafo: execucao.contexto['grafo'] || execucao.versao&.grafo)
  end
```

- [ ] **Step 3: Conferir sintaxe (sem Ruby local)**

Run: `git diff --stat` — só os 2 arquivos. O RSpec/RuboCop rodam no CI do PR.

- [ ] **Step 4: Commit**

```bash
git add app/controllers/api/v1/accounts/ramon_fluxo_execucoes_controller.rb spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb
git commit -m "feat(fluxos): execução devolve o desenho em que rodou" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 3: API client + catálogo + conversor desenho ↔ Vue Flow

**Files:**
- Create: `app/javascript/dashboard/api/ramonFluxos.js`
- Create: `app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js`
- Test: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/fluxo.spec.js`

**Interfaces:**
- Produces (`ramonFluxos.js`, default export singleton): `get()`, `show(id)`, `create(data)`, `update(id, data)`, `delete(id)`, `publicar(id)`, `ensaio(id, params)`, `rodar(id, params)`, `execucoes(id)`, `execucao(id, execId)` — todos retornam a promise do axios.
- Produces (`fluxo.js`):
  - `GATILHOS: Array<{tipo, icone, alvo: 'conversa'|'lead'}>`, `gatilhoInfo(tipo) → item|undefined`
  - `PASSOS: Record<tipo, {grupo, icone, tom, rascunho?}>`, `TIPOS_PASSO: string[]`
  - `PALETA: Array<{grupo, itens: Array<{chave, tipo, config?}>}>`
  - `ACOES_CHATWOOT: Array<{nome, parametro: null|'etiquetas'|'pessoa'|'time'|'prioridade'|'email_time'}>`, `CHATWOOT_PERMITIDAS: string[]`, `PRIORIDADES: string[]`
  - `VARIAVEIS`, `CAMPOS`, `OPERADORES`, `SEM_VALOR`, `TIPOS_TAREFA`, `UNIDADES`: `string[]`
  - `configInicial(tipo) → object`, `saidasDe(tipo, config) → string[]`, `idSeta(de, saida) → string`, `novaChave(casos) → 'cN'`
  - `paraVueFlow(desenho) → {nodes, edges}`, `deVueFlow(nodes, edges) → desenho`
  - `alcancaveis(setas, inicio) → Set<id>` (setas no formato `{de, para}`)
  - `ligar(edges, {source, sourceHandle, target}) → edges|null`
  - `proximoId(nodes) → 'nN'`, `adicionarPasso(nodes, edges, item, selecionadoId) → {nodes, edges, id}`, `duplicarPasso(nodes, id) → {nodes, id}`, `trocarConfig(nodes, id, config) → nodes`
  - `idDoErro(msg) → id|null`, `caminhoAceso(trilha, desenho) → {nos: Set, setas: Set}`, `quando(iso) → 'dd/mm HH:MM'`
  - Formato Vue Flow: node = `{ id, type: 'passo', position: {x,y}, data: {tipo, config}, deletable }`; edge = `{ id: '<de>:<saida>', source, sourceHandle, target, targetHandle: 'e' }`.

- [ ] **Step 1: Escrever os testes**

`app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/fluxo.spec.js`:

```js
import {
  adicionarPasso,
  caminhoAceso,
  deVueFlow,
  duplicarPasso,
  idDoErro,
  ligar,
  novaChave,
  paraVueFlow,
  saidasDe,
  trocarConfig,
} from '../fluxo';

const DESENHO = {
  nos: [
    { id: 'n1', tipo: 'gatilho', config: { tipo: 'lead_mudou_etapa', para_etapa_ids: [3] }, posicao: { x: 0, y: 0 } },
    { id: 'n2', tipo: 'se', config: { juncao: 'e', condicoes: [{ campo: 'tese', operador: 'igual', valor: 'BPC' }] }, posicao: { x: 0, y: 140 } },
    {
      id: 'n3',
      tipo: 'escolha',
      config: {
        campo: 'tese',
        casos: [
          { chave: 'c1', rotulo: 'BPC', valores: ['BPC'] },
          { chave: 'c2', rotulo: 'Acidente', valores: ['Auxílio-acidente'] },
        ],
      },
      posicao: { x: -130, y: 300 },
    },
    { id: 'n4', tipo: 'nota_privada', config: { texto: 'oi {nome}', rotulo: 'Aviso' }, posicao: { x: 130, y: 300 } },
    { id: 'n5', tipo: 'parar', config: {}, posicao: { x: -260, y: 460 } },
  ],
  setas: [
    { de: 'n1', saida: 's', para: 'n2' },
    { de: 'n2', saida: 'sim', para: 'n3' },
    { de: 'n2', saida: 'nao', para: 'n4' },
    { de: 'n3', saida: 'c2', para: 'n5' },
    { de: 'n3', saida: 'outro', para: 'n4' },
  ],
};

describe('conversor desenho ↔ Vue Flow', () => {
  it('salvar e reabrir devolve o mesmo desenho', () => {
    const { nodes, edges } = paraVueFlow(DESENHO);
    expect(deVueFlow(nodes, edges)).toEqual(DESENHO);
  });

  it('gera nós do tipo passo, gatilho não apagável e setas com id de porta', () => {
    const { nodes, edges } = paraVueFlow(DESENHO);
    expect(nodes[0]).toEqual({
      id: 'n1',
      type: 'passo',
      position: { x: 0, y: 0 },
      data: { tipo: 'gatilho', config: { tipo: 'lead_mudou_etapa', para_etapa_ids: [3] } },
      deletable: false,
    });
    expect(nodes[1].deletable).toBe(true);
    expect(edges[1]).toEqual({ id: 'n2:sim', source: 'n2', sourceHandle: 'sim', target: 'n3', targetHandle: 'e' });
  });

  it('desenho sem posicao/config/setas abre em (0,0) com config vazia', () => {
    const { nodes, edges } = paraVueFlow({ nos: [{ id: 'g', tipo: 'gatilho', config: null }] });
    expect(nodes[0].position).toEqual({ x: 0, y: 0 });
    expect(nodes[0].data.config).toEqual({});
    expect(edges).toEqual([]);
    expect(paraVueFlow(undefined)).toEqual({ nodes: [], edges: [] });
  });

  it('arredonda a posição ao salvar (arrasto com zoom dá fração)', () => {
    const { nodes, edges } = paraVueFlow(DESENHO);
    nodes[1] = { ...nodes[1], position: { x: 10.4, y: 139.6 } };
    expect(deVueFlow(nodes, edges).nos[1].posicao).toEqual({ x: 10, y: 140 });
  });

  it('seta de um caso apagado do escolha some ao salvar', () => {
    const { nodes, edges } = paraVueFlow(DESENHO);
    const semC2 = trocarConfig(nodes, 'n3', {
      campo: 'tese',
      casos: [
        { chave: 'c1', rotulo: 'BPC', valores: ['BPC'] },
        { chave: 'c3', rotulo: 'Idade', valores: ['Aposentadoria'] },
      ],
    });
    const setas = deVueFlow(semC2, edges).setas;
    expect(setas.find(s => s.saida === 'c2')).toBeUndefined();
    expect(setas.find(s => s.saida === 'outro')).toBeDefined();
  });
});

describe('portas de saída', () => {
  it('por tipo de passo', () => {
    expect(saidasDe('gatilho', {})).toEqual(['s']);
    expect(saidasDe('se', {})).toEqual(['sim', 'nao']);
    expect(saidasDe('escolha', { casos: [{ chave: 'c1' }, { chave: 'c2' }] })).toEqual(['c1', 'c2', 'outro']);
    expect(saidasDe('escolha', {})).toEqual(['outro']);
    expect(saidasDe('parar', {})).toEqual([]);
    expect(saidasDe('esperar', {})).toEqual(['s']);
  });

  it('nova chave de caso não repete', () => {
    expect(novaChave([{ chave: 'c1' }, { chave: 'c4' }])).toBe('c5');
    expect(novaChave([])).toBe('c1');
  });
});

describe('ligar', () => {
  const { edges } = paraVueFlow(DESENHO);

  it('2ª seta na mesma porta substitui a anterior', () => {
    const novas = ligar(edges, { source: 'n2', sourceHandle: 'nao', target: 'n5' });
    expect(novas.filter(e => e.source === 'n2' && e.sourceHandle === 'nao')).toEqual([
      { id: 'n2:nao', source: 'n2', sourceHandle: 'nao', target: 'n5', targetHandle: 'e' },
    ]);
    expect(novas).toHaveLength(edges.length);
  });

  it('recusa ligar o passo nele mesmo', () => {
    expect(ligar(edges, { source: 'n4', sourceHandle: 's', target: 'n4' })).toBeNull();
  });

  it('recusa fechar laço (voltar para um passo anterior)', () => {
    expect(ligar(edges, { source: 'n4', sourceHandle: 's', target: 'n2' })).toBeNull();
  });

  it('aceita dois ramos chegando no mesmo passo', () => {
    expect(ligar(edges, { source: 'n3', sourceHandle: 'c1', target: 'n4' })).toHaveLength(edges.length + 1);
  });
});

describe('adicionar, duplicar, trocar config', () => {
  it('com passo selecionado: entra embaixo dele e liga na 1ª porta livre', () => {
    const { nodes, edges } = paraVueFlow(DESENHO);
    const r = adicionarPasso(nodes, edges, { tipo: 'esperar' }, 'n3');
    expect(r.id).toBe('n6');
    const novo = r.nodes.find(n => n.id === 'n6');
    expect(novo.position).toEqual({ x: -130, y: 440 });
    expect(novo.data).toEqual({ tipo: 'esperar', config: { quantidade: 1, unidade: 'dias' } });
    expect(r.edges).toContainEqual({ id: 'n3:c1', source: 'n3', sourceHandle: 'c1', target: 'n6', targetHandle: 'e' });
  });

  it('sem seleção: entra abaixo do passo mais baixo, solto', () => {
    const { nodes, edges } = paraVueFlow(DESENHO);
    const r = adicionarPasso(nodes, edges, { tipo: 'acao_chatwoot', config: { acoes: [{ action_name: 'add_label', action_params: [] }] } }, null);
    expect(r.nodes.find(n => n.id === r.id).position).toEqual({ x: -260, y: 600 });
    expect(r.edges).toBe(edges);
  });

  it('a config do item da paleta é copiada (não compartilhada)', () => {
    const item = { tipo: 'acao_chatwoot', config: { acoes: [{ action_name: 'add_label', action_params: [] }] } };
    const { nodes, edges } = paraVueFlow(DESENHO);
    const r = adicionarPasso(nodes, edges, item, null);
    r.nodes.find(n => n.id === r.id).data.config.acoes[0].action_params.push('x');
    expect(item.config.acoes[0].action_params).toEqual([]);
  });

  it('duplicar cria cópia deslocada, sem setas', () => {
    const { nodes } = paraVueFlow(DESENHO);
    const r = duplicarPasso(nodes, 'n4');
    const copia = r.nodes.find(n => n.id === r.id);
    expect(r.id).toBe('n6');
    expect(copia.position).toEqual({ x: 170, y: 340 });
    expect(copia.data).toEqual(nodes.find(n => n.id === 'n4').data);
    expect(copia.data).not.toBe(nodes.find(n => n.id === 'n4').data);
  });
});

describe('erros do back e caminho aceso', () => {
  it('acha o passo na mensagem do back', () => {
    expect(idDoErro('Passo n3: falta texto')).toBe('n3');
    expect(idDoErro('Passo n3 (Se) precisa de condições')).toBe('n3');
    expect(idDoErro('Passo n12 não está ligado ao gatilho')).toBe('n12');
    expect(idDoErro('O fluxo precisa de exatamente 1 gatilho')).toBeNull();
  });

  it('acende os passos da trilha e as setas percorridas', () => {
    const trilha = [
      { no: 'n1', tipo: 'gatilho', saida: 's' },
      { no: 'n2', tipo: 'se', saida: 'nao' },
      { no: 'n4', tipo: 'nota_privada', saida: 's' },
    ];
    const { nos, setas } = caminhoAceso(trilha, DESENHO);
    expect([...nos]).toEqual(['n1', 'n2', 'n4']);
    expect([...setas]).toEqual(['n1:s', 'n2:nao']);
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/fluxo.spec.js`
Expected: FAIL — `Failed to resolve import "../fluxo"`.

- [ ] **Step 3: Implementar o API client**

`app/javascript/dashboard/api/ramonFluxos.js`:

```js
/* global axios */
import ApiClient from './ApiClient';

// Automações em fluxo (spec automacoes-em-fluxo §7) — admin-only.
class RamonFluxosAPI extends ApiClient {
  constructor() {
    super('ramon_fluxos', { accountScoped: true });
  }

  publicar(id) {
    return axios.post(`${this.url}/${id}/publicar`);
  }

  // params: { lead_id } | { conversation_id } (+ usar: 'rascunho'|'publicada')
  ensaio(id, params) {
    return axios.post(`${this.url}/${id}/ensaio`, params);
  }

  rodar(id, params) {
    return axios.post(`${this.url}/${id}/rodar`, params);
  }

  execucoes(id) {
    return axios.get(`${this.url}/${id}/execucoes`);
  }

  execucao(id, execId) {
    return axios.get(`${this.url}/${id}/execucoes/${execId}`);
  }
}

export default new RamonFluxosAPI();
```

- [ ] **Step 4: Implementar `fluxo.js`**

`app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js`:

```js
// Quadro de fluxos (B2): catálogo do que o motor da B1 executa
// (Ramon::Fluxos::Grafo::GATILHOS / TIPOS_PASSO) e as operações puras do
// quadro. Desenho salvo = { nos: [{id, tipo, config, posicao}], setas: [{de, saida, para}] }.

export const GATILHOS = [
  { tipo: 'conversa_criada', icone: 'i-lucide-message-square-plus', alvo: 'conversa' },
  { tipo: 'mensagem_recebida', icone: 'i-lucide-message-square', alvo: 'conversa' },
  { tipo: 'conversa_resolvida', icone: 'i-lucide-circle-check-big', alvo: 'conversa' },
  { tipo: 'conversa_reaberta', icone: 'i-lucide-rotate-ccw', alvo: 'conversa' },
  { tipo: 'conversa_atribuida', icone: 'i-lucide-user-round-check', alvo: 'conversa' },
  { tipo: 'lead_criado', icone: 'i-lucide-user-plus', alvo: 'lead' },
  { tipo: 'lead_mudou_etapa', icone: 'i-lucide-git-commit-horizontal', alvo: 'lead' },
  { tipo: 'lead_ganho', icone: 'i-lucide-trophy', alvo: 'lead' },
  { tipo: 'lead_perdido', icone: 'i-lucide-circle-x', alvo: 'lead' },
  { tipo: 'manual', icone: 'i-lucide-hand', alvo: 'lead' },
];
export const gatilhoInfo = tipo => GATILHOS.find(g => g.tipo === tipo);

// tom = chave do TOM do kit (ramon/helpers/ui.js); rascunho = selo "sai como rascunho"
export const PASSOS = {
  gatilho: { grupo: null, icone: 'i-lucide-zap', tom: 'blue' },
  se: { grupo: 'CONDICAO', icone: 'i-lucide-split', tom: 'amber' },
  escolha: { grupo: 'CONDICAO', icone: 'i-lucide-git-fork', tom: 'amber' },
  rascunho_texto: { grupo: 'MENSAGEM', icone: 'i-lucide-file-pen-line', tom: 'slate', rascunho: true },
  acao_chatwoot: { grupo: 'CONVERSA', icone: 'i-lucide-tag', tom: 'slate' },
  nota_privada: { grupo: 'CONVERSA', icone: 'i-lucide-sticky-note', tom: 'slate' },
  mover_etapa: { grupo: 'LEAD', icone: 'i-lucide-move-right', tom: 'slate' },
  criar_tarefa: { grupo: 'LEAD', icone: 'i-lucide-list-todo', tom: 'slate' },
  avisar_sino: { grupo: 'AVISAR', icone: 'i-lucide-bell', tom: 'slate' },
  avisar_push: { grupo: 'AVISAR', icone: 'i-lucide-smartphone', tom: 'slate' },
  esperar: { grupo: 'CONTROLE', icone: 'i-lucide-hourglass', tom: 'slate' },
  parar: { grupo: 'CONTROLE', icone: 'i-lucide-octagon-x', tom: 'slate' },
};
export const TIPOS_PASSO = Object.keys(PASSOS).filter(t => t !== 'gatilho');

// "+ Adicionar passo": só o que a B1 roda (B2b — IA, ADVBOX, webhook — entra com o motor dela).
export const PALETA = [
  { grupo: 'CONDICAO', itens: [{ chave: 'se', tipo: 'se' }, { chave: 'escolha', tipo: 'escolha' }] },
  { grupo: 'MENSAGEM', itens: [{ chave: 'rascunho_texto', tipo: 'rascunho_texto' }] },
  {
    grupo: 'CONVERSA',
    itens: [
      { chave: 'etiqueta', tipo: 'acao_chatwoot', config: { acoes: [{ action_name: 'add_label', action_params: [] }] } },
      { chave: 'atribuir', tipo: 'acao_chatwoot', config: { acoes: [{ action_name: 'assign_agent', action_params: [] }] } },
      { chave: 'acao_chatwoot', tipo: 'acao_chatwoot' },
      { chave: 'nota_privada', tipo: 'nota_privada' },
    ],
  },
  { grupo: 'LEAD', itens: [{ chave: 'mover_etapa', tipo: 'mover_etapa' }, { chave: 'criar_tarefa', tipo: 'criar_tarefa' }] },
  { grupo: 'AVISAR', itens: [{ chave: 'avisar_sino', tipo: 'avisar_sino' }, { chave: 'avisar_push', tipo: 'avisar_push' }] },
  { grupo: 'CONTROLE', itens: [{ chave: 'esperar', tipo: 'esperar' }, { chave: 'parar', tipo: 'parar' }] },
];

// Ações nativas editáveis na tela (parametro = que formulário abre).
// Mensagem ao cliente/transcript/webhook nunca (Grafo::PROIBIDAS_CHATWOOT);
// nota privada e "mudar status" já têm passo próprio / resolver-abrir-pendente.
export const ACOES_CHATWOOT = [
  { nome: 'add_label', parametro: 'etiquetas' },
  { nome: 'remove_label', parametro: 'etiquetas' },
  { nome: 'assign_agent', parametro: 'pessoa' },
  { nome: 'remove_assigned_agent', parametro: null },
  { nome: 'assign_team', parametro: 'time' },
  { nome: 'remove_assigned_team', parametro: null },
  { nome: 'change_priority', parametro: 'prioridade' },
  { nome: 'resolve_conversation', parametro: null },
  { nome: 'open_conversation', parametro: null },
  { nome: 'pending_conversation', parametro: null },
  { nome: 'snooze_conversation', parametro: null },
  { nome: 'mute_conversation', parametro: null },
  { nome: 'send_email_to_team', parametro: 'email_time' },
];
// = Grafo.permitidas_chatwoot (inclui as que vêm de regras convertidas na B3)
export const CHATWOOT_PERMITIDAS = [
  ...ACOES_CHATWOOT.map(a => a.nome),
  'change_status',
  'add_private_note',
  'add_sla',
];
export const PRIORIDADES = ['urgent', 'high', 'medium', 'low', 'nil'];

// Ramon::Fluxos::Contexto#dados — o que o {chave} dos textos e as condições enxergam.
export const VARIAVEIS = ['nome', 'nome_completo', 'telefone', 'responsavel', 'etapa', 'tese', 'origem', 'canal', 'prioridade', 'caixa', 'status', 'texto'];
export const CAMPOS = ['etapa', 'tese', 'origem', 'canal', 'prioridade', 'responsavel', 'caixa', 'status', 'etiquetas', 'valor', 'texto', 'nome', 'telefone'];
export const OPERADORES = ['igual', 'diferente', 'contem', 'nao_contem', 'maior', 'menor', 'existe', 'vazio', 'em_horario_comercial'];
export const SEM_VALOR = ['existe', 'vazio', 'em_horario_comercial'];
export const TIPOS_TAREFA = ['follow_up', 'document', 'meeting', 'other']; // LeadTask::KINDS
export const UNIDADES = ['minutos', 'horas', 'dias'];

const copia = obj => JSON.parse(JSON.stringify(obj));

const CONFIG_INICIAL = {
  se: { juncao: 'e', condicoes: [{ campo: 'etapa', operador: 'igual', valor: '' }] },
  escolha: {
    campo: 'tese',
    casos: [
      { chave: 'c1', rotulo: '', valores: [] },
      { chave: 'c2', rotulo: '', valores: [] },
    ],
  },
  esperar: { quantidade: 1, unidade: 'dias' },
  criar_tarefa: { titulo: '', tipo: 'other', prazo_dias: 1 },
  acao_chatwoot: { acoes: [] },
};
export const configInicial = tipo => copia(CONFIG_INICIAL[tipo] || {});

export const saidasDe = (tipo, config = {}) => {
  if (tipo === 'parar') return [];
  if (tipo === 'se') return ['sim', 'nao'];
  if (tipo === 'escolha') return [...(config.casos || []).map(c => c.chave), 'outro'];
  return ['s'];
};

export const idSeta = (de, saida) => `${de}:${saida}`;

const numero = id => Number(String(id).replace(/\D/g, '')) || 0;
export const novaChave = casos => `c${Math.max(0, ...casos.map(c => numero(c.chave))) + 1}`;
export const proximoId = nodes => `n${Math.max(0, ...nodes.map(n => numero(n.id))) + 1}`;

export const paraVueFlow = ({ nos = [], setas = [] } = {}) => ({
  nodes: nos.map(no => ({
    id: no.id,
    type: 'passo',
    position: { x: no.posicao?.x ?? 0, y: no.posicao?.y ?? 0 },
    data: { tipo: no.tipo, config: no.config ?? {} },
    deletable: no.tipo !== 'gatilho',
  })),
  edges: setas.map(seta => ({
    id: idSeta(seta.de, seta.saida),
    source: seta.de,
    sourceHandle: seta.saida,
    target: seta.para,
    targetHandle: 'e',
  })),
});

export const deVueFlow = (nodes, edges) => {
  const saidas = Object.fromEntries(nodes.map(n => [n.id, saidasDe(n.data.tipo, n.data.config)]));
  return {
    nos: nodes.map(n => ({
      id: n.id,
      tipo: n.data.tipo,
      config: n.data.config,
      posicao: { x: Math.round(n.position.x), y: Math.round(n.position.y) },
    })),
    // porta que sumiu (caso apagado do escolha) leva a seta junto
    setas: edges
      .filter(e => saidas[e.source]?.includes(e.sourceHandle))
      .map(e => ({ de: e.source, saida: e.sourceHandle, para: e.target })),
  };
};

export const alcancaveis = (setas, inicio) => {
  const vistos = new Set();
  const fila = [inicio];
  while (fila.length) {
    const id = fila.shift();
    if (!vistos.has(id)) {
      vistos.add(id);
      fila.push(...setas.filter(s => s.de === id).map(s => s.para));
    }
  }
  return vistos;
};

// Nova seta: troca a que já saía da mesma porta; recusa o próprio passo e laço (D2: sem laços).
export const ligar = (edges, { source, sourceHandle, target }) => {
  if (source === target) return null;
  const outras = edges.filter(e => !(e.source === source && e.sourceHandle === sourceHandle));
  const setas = outras.map(e => ({ de: e.source, para: e.target }));
  if (alcancaveis(setas, target).has(source)) return null;
  return [...outras, { id: idSeta(source, sourceHandle), source, sourceHandle, target, targetHandle: 'e' }];
};

const ESPACO_Y = 140;

export const adicionarPasso = (nodes, edges, { tipo, config }, selecionadoId) => {
  const id = proximoId(nodes);
  const pai = nodes.find(n => n.id === selecionadoId);
  const base = pai || nodes.reduce((a, n) => (n.position.y > a.position.y ? n : a), nodes[0]);
  const no = {
    id,
    type: 'passo',
    position: { x: base.position.x, y: base.position.y + ESPACO_Y },
    data: { tipo, config: config ? copia(config) : configInicial(tipo) },
    deletable: true,
  };
  const livre = pai && saidasDe(pai.data.tipo, pai.data.config).find(s => !edges.some(e => e.source === pai.id && e.sourceHandle === s));
  return {
    nodes: [...nodes, no],
    edges: livre ? [...edges, { id: idSeta(pai.id, livre), source: pai.id, sourceHandle: livre, target: id, targetHandle: 'e' }] : edges,
    id,
  };
};

export const duplicarPasso = (nodes, id) => {
  const original = nodes.find(n => n.id === id);
  const novoId = proximoId(nodes);
  const novo = {
    id: novoId,
    type: 'passo',
    position: { x: original.position.x + 40, y: original.position.y + 40 },
    data: copia(original.data),
    deletable: true,
  };
  return { nodes: [...nodes, novo], id: novoId };
};

export const trocarConfig = (nodes, id, config) =>
  nodes.map(n => (n.id === id ? { ...n, data: { ...n.data, config } } : n));

// Mensagens do Grafo#erros que apontam passo: "Passo n3: …", "Passo n3 (Se) …", "Passo n3 não …".
export const idDoErro = msg => /^Passo (\S+?)(?::|\s|$)/.exec(msg)?.[1] ?? null;

export const caminhoAceso = (trilha = [], { setas = [] } = {}) => {
  const ids = new Set();
  trilha.forEach((linha, i) => {
    const prox = trilha[i + 1];
    const seta = prox && setas.find(s => s.de === linha.no && s.saida === linha.saida && s.para === prox.no);
    if (seta) ids.add(idSeta(seta.de, seta.saida));
  });
  return { nos: new Set(trilha.map(l => l.no)), setas: ids };
};

const FORMATO = new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
export const quando = iso => (iso ? FORMATO.format(new Date(iso)).replace(',', '') : '');
```

- [ ] **Step 5: Rodar e ver passar**

Run: `TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/fluxo.spec.js`
Expected: PASS (todos).

- [ ] **Step 6: Lint**

Run: `./node_modules/.bin/eslint app/javascript/dashboard/api/ramonFluxos.js app/javascript/dashboard/routes/dashboard/captain/automacoes/`
Expected: sem erro (fora `Delete ␍`). Se o prettier reformatar linhas longas, aceitar o `--fix`.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/dashboard/api/ramonFluxos.js app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/fluxo.spec.js
git commit -m "feat(fluxos): api e conversor desenho <-> quadro" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 4: Validação no front espelhando o back

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/captain/automacoes/validar.js`
- Test: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/validar.spec.js`

**Interfaces:**
- Consumes: `GATILHOS`, `TIPOS_PASSO`, `CHATWOOT_PERMITIDAS`, `UNIDADES`, `alcancaveis` (Task 3).
- Produces: `validar(desenho) → Array<{ no: string|null, codigo: string, params: object }>`. Códigos (= chaves i18n `CAPTAIN_RAMON.FLUXOS.ERROS.*`, Task 7): `UM_GATILHO`, `GATILHO_DESCONHECIDO`, `SETA_FANTASMA {id}`, `SETA_REPETIDA {saida}`, `CICLO`, `SOLTO`, `TIPO_DESCONHECIDO {tipo}`, `FALTA {campo}`, `SE_SEM_CONDICOES`, `SE_SEM_SAIDA`, `ESCOLHA_POUCOS_CASOS`, `ESCOLHA_CHAVE_REPETIDA`, `ESCOLHA_VALOR_REPETIDO`, `ESPERA_SEM_TEMPO`, `CHATWOOT_SEM_ACAO`, `CHATWOOT_MENSAGEM`, `CHATWOOT_PROIBIDA {nome}`, `CHATWOOT_DESCONHECIDA {nome}`.

- [ ] **Step 1: Escrever os testes (1 por regra de `app/services/ramon/fluxos/grafo.rb`)**

`…/automacoes/specs/validar.spec.js`:

```js
import { validar } from '../validar';

const g = (config = { tipo: 'manual' }) => ({ id: 'g', tipo: 'gatilho', config, posicao: { x: 0, y: 0 } });
const p = (id, tipo, config = {}) => ({ id, tipo, config, posicao: { x: 0, y: 0 } });
const linear = (...passos) => ({
  nos: [g(), ...passos],
  setas: passos.map((passo, i) => ({ de: i ? passos[i - 1].id : 'g', saida: 's', para: passo.id })),
});
const codigos = desenho => validar(desenho).map(e => [e.no, e.codigo]);

describe('validar (espelho do Grafo#erros)', () => {
  it('desenho válido não tem erro', () => {
    expect(validar(linear(p('p1', 'nota_privada', { texto: 'oi' }), p('p2', 'parar')))).toEqual([]);
  });

  it('exatamente 1 gatilho (e para por aí)', () => {
    expect(codigos({ nos: [], setas: [] })).toEqual([[null, 'UM_GATILHO']]);
    expect(codigos({ nos: [g(), { ...g(), id: 'g2' }], setas: [] })).toEqual([[null, 'UM_GATILHO']]);
  });

  it('gatilho fora da lista da B1', () => {
    expect(codigos({ nos: [g({ tipo: 'relogio' })], setas: [] })).toEqual([['g', 'GATILHO_DESCONHECIDO']]);
  });

  it('seta para passo inexistente e duas setas na mesma porta', () => {
    const d = linear(p('p1', 'parar'));
    d.setas.push({ de: 'g', saida: 's', para: 'fantasma' });
    expect(validar(d)).toEqual(
      expect.arrayContaining([
        { no: null, codigo: 'SETA_FANTASMA', params: { id: 'fantasma' } },
        { no: 'g', codigo: 'SETA_REPETIDA', params: { saida: 's' } },
      ])
    );
  });

  it('laço vira só "CICLO" (sem listar soltos)', () => {
    const d = linear(p('p1', 'nota_privada', { texto: 'a' }), p('p2', 'nota_privada', { texto: 'b' }));
    d.setas.push({ de: 'p2', saida: 's', para: 'p1' });
    expect(codigos(d)).toEqual([[null, 'CICLO']]);
  });

  it('passo solto', () => {
    const d = linear(p('p1', 'parar'));
    d.nos.push(p('p9', 'parar'));
    expect(codigos(d)).toEqual([['p9', 'SOLTO']]);
  });

  it('tipo desconhecido (ex.: passo da B2b)', () => {
    expect(codigos(linear(p('p1', 'webhook', { url: 'x' })))).toEqual([['p1', 'TIPO_DESCONHECIDO']]);
  });

  it('obrigatórios em branco (blank? do Rails: nil, "", só espaço)', () => {
    expect(validar(linear(p('p1', 'rascunho_texto', { texto: '   ' })))).toEqual([{ no: 'p1', codigo: 'FALTA', params: { campo: 'texto' } }]);
    expect(codigos(linear(p('p1', 'mover_etapa', {})))).toEqual([['p1', 'FALTA']]);
    expect(codigos(linear(p('p1', 'criar_tarefa', { titulo: '' })))).toEqual([['p1', 'FALTA']]);
    expect(codigos(linear(p('p1', 'avisar_sino', {})))).toEqual([['p1', 'FALTA']]);
    expect(codigos(linear(p('p1', 'avisar_push', {})))).toEqual([['p1', 'FALTA']]);
  });

  it('se: sem condições e sem nenhuma saída', () => {
    const d = { nos: [g(), p('p1', 'se', { condicoes: [] })], setas: [{ de: 'g', saida: 's', para: 'p1' }] };
    expect(codigos(d)).toEqual([['p1', 'SE_SEM_CONDICOES'], ['p1', 'SE_SEM_SAIDA']]);
  });

  it('escolha: menos de 2 casos, chave repetida, valor repetido (sem caixa)', () => {
    const um = linear(p('p1', 'escolha', { campo: 'tese', casos: [{ chave: 'c1', valores: ['A'] }] }));
    expect(codigos(um)).toEqual([['p1', 'ESCOLHA_POUCOS_CASOS']]);
    const dup = linear(
      p('p1', 'escolha', {
        campo: 'tese',
        casos: [
          { chave: 'c1', valores: ['BPC'] },
          { chave: 'c1', valores: ['bpc'] },
        ],
      })
    );
    expect(codigos(dup)).toEqual([['p1', 'ESCOLHA_CHAVE_REPETIDA'], ['p1', 'ESCOLHA_VALOR_REPETIDO']]);
    expect(codigos(linear(p('p1', 'escolha', { casos: [{ chave: 'c1' }, { chave: 'c2' }] })))).toEqual([['p1', 'FALTA']]);
  });

  it('esperar: quantidade > 0 com unidade válida, ou até o horário comercial', () => {
    expect(validar(linear(p('p1', 'esperar', { quantidade: '2', unidade: 'dias' })))).toEqual([]);
    expect(validar(linear(p('p1', 'esperar', { ate: 'horario_comercial' })))).toEqual([]);
    expect(codigos(linear(p('p1', 'esperar', { quantidade: 0, unidade: 'dias' })))).toEqual([['p1', 'ESPERA_SEM_TEMPO']]);
    expect(codigos(linear(p('p1', 'esperar', { quantidade: 2, unidade: 'semanas' })))).toEqual([['p1', 'ESPERA_SEM_TEMPO']]);
  });

  it('ação do Chatwoot: vazia, mensagem ao cliente, proibida, desconhecida', () => {
    const acao = (...nomes) => linear(p('p1', 'acao_chatwoot', { acoes: nomes.map(action_name => ({ action_name, action_params: [] })) }));
    expect(codigos(acao())).toEqual([['p1', 'CHATWOOT_SEM_ACAO']]);
    expect(codigos(acao('add_label', 'send_message'))).toEqual([['p1', 'CHATWOOT_MENSAGEM']]);
    expect(validar(acao('send_webhook_event'))).toEqual([{ no: 'p1', codigo: 'CHATWOOT_PROIBIDA', params: { nome: 'send_webhook_event' } }]);
    expect(validar(acao('apagar_tudo'))).toEqual([{ no: 'p1', codigo: 'CHATWOOT_DESCONHECIDA', params: { nome: 'apagar_tudo' } }]);
    expect(validar(acao('add_label', 'add_sla', 'add_private_note'))).toEqual([]);
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/validar.spec.js`
Expected: FAIL — `Failed to resolve import "../validar"`.

- [ ] **Step 3: Implementar**

`…/automacoes/validar.js`:

```js
// Espelho de Ramon::Fluxos::Grafo#erros (app/services/ramon/fluxos/grafo.rb):
// mesmas regras, mesma ordem. Serve para acender o passo antes de chamar o
// back; quem decide no Publicar continua sendo o back.
import { CHATWOOT_PERMITIDAS, GATILHOS, TIPOS_PASSO, UNIDADES, alcancaveis } from './fluxo';

const OBRIGATORIOS = {
  rascunho_texto: ['texto'],
  nota_privada: ['texto'],
  mover_etapa: ['etapa_id'],
  criar_tarefa: ['titulo'],
  escolha: ['campo'],
  avisar_sino: ['texto'],
  avisar_push: ['texto'],
};
const MENSAGEM_CLIENTE = ['send_message', 'send_attachment'];
const PROIBIDAS = [...MENSAGEM_CLIENTE, 'send_email_transcript', 'send_webhook_event'];

const erro = (no, codigo, params = {}) => ({ no, codigo, params });

// blank? do Rails
const vazio = v =>
  v == null ||
  v === false ||
  (typeof v === 'string' && !v.trim()) ||
  (Array.isArray(v) && !v.length) ||
  (typeof v === 'object' && !Array.isArray(v) && !Object.keys(v).length);

const errosSetas = (nos, setas) => {
  const ids = new Set(nos.map(n => n.id));
  const fantasmas = [...new Set(setas.flatMap(s => [s.de, s.para]))].filter(id => !ids.has(id));
  const vistas = new Set();
  const repetidas = [];
  setas.forEach(s => {
    const chave = JSON.stringify([s.de, s.saida]);
    if (vistas.has(chave) && !repetidas.some(r => r.de === s.de && r.saida === s.saida)) repetidas.push(s);
    vistas.add(chave);
  });
  return [
    ...fantasmas.map(id => erro(null, 'SETA_FANTASMA', { id })),
    ...repetidas.map(s => erro(s.de, 'SETA_REPETIDA', { saida: s.saida })),
  ];
};

const temCiclo = (nos, setas) => {
  const estado = {};
  const visita = id => {
    if (estado[id] === 'aberto') return true;
    if (estado[id] === 'fechado') return false;
    estado[id] = 'aberto';
    const achou = setas.filter(s => s.de === id).some(s => visita(s.para));
    estado[id] = 'fechado';
    return achou;
  };
  return nos.some(n => visita(n.id));
};

const errosAlcance = (nos, setas, gatilhoId) => {
  if (temCiclo(nos, setas)) return [erro(null, 'CICLO')];
  const ok = alcancaveis(setas, gatilhoId);
  return nos.filter(n => !ok.has(n.id)).map(n => erro(n.id, 'SOLTO'));
};

const errosEscolha = (id, config) => {
  const casos = config.casos || [];
  if (casos.length < 2) return [erro(id, 'ESCOLHA_POUCOS_CASOS')];
  const erros = [];
  if (new Set(casos.map(c => c.chave)).size < casos.length) erros.push(erro(id, 'ESCOLHA_CHAVE_REPETIDA'));
  const valores = casos.flatMap(c => (c.valores || []).map(v => String(v).toLowerCase()));
  if (new Set(valores).size < valores.length) erros.push(erro(id, 'ESCOLHA_VALOR_REPETIDO'));
  return erros;
};

const esperaValida = c =>
  c.ate === 'horario_comercial' || (Number.parseInt(c.quantidade, 10) > 0 && UNIDADES.includes(c.unidade));

const errosChatwoot = (id, config) => {
  const nomes = (config.acoes || []).map(a => a.action_name);
  if (!nomes.length) return [erro(id, 'CHATWOOT_SEM_ACAO')];
  if (nomes.some(n => MENSAGEM_CLIENTE.includes(n))) return [erro(id, 'CHATWOOT_MENSAGEM')];
  return nomes.flatMap(nome => {
    if (PROIBIDAS.includes(nome)) return [erro(id, 'CHATWOOT_PROIBIDA', { nome })];
    if (!CHATWOOT_PERMITIDAS.includes(nome)) return [erro(id, 'CHATWOOT_DESCONHECIDA', { nome })];
    return [];
  });
};

const errosEspecificos = (no, config, setas) => {
  switch (no.tipo) {
    case 'se':
      return [
        ...((config.condicoes || []).length ? [] : [erro(no.id, 'SE_SEM_CONDICOES')]),
        ...(setas.some(s => s.de === no.id) ? [] : [erro(no.id, 'SE_SEM_SAIDA')]),
      ];
    case 'escolha':
      return errosEscolha(no.id, config);
    case 'esperar':
      return esperaValida(config) ? [] : [erro(no.id, 'ESPERA_SEM_TEMPO')];
    case 'acao_chatwoot':
      return errosChatwoot(no.id, config);
    default:
      return [];
  }
};

const errosPasso = (no, setas) => {
  if (no.tipo === 'gatilho') return [];
  if (!TIPOS_PASSO.includes(no.tipo)) return [erro(no.id, 'TIPO_DESCONHECIDO', { tipo: no.tipo })];
  const config = no.config || {};
  const faltas = (OBRIGATORIOS[no.tipo] || []).filter(k => vazio(config[k])).map(campo => erro(no.id, 'FALTA', { campo }));
  return [...faltas, ...errosEspecificos(no, config, setas)];
};

export const validar = ({ nos = [], setas = [] } = {}) => {
  const gatilhos = nos.filter(n => n.tipo === 'gatilho');
  if (gatilhos.length !== 1) return [erro(null, 'UM_GATILHO')];
  const [gatilho] = gatilhos;
  if (!GATILHOS.some(x => x.tipo === gatilho.config?.tipo)) return [erro(gatilho.id, 'GATILHO_DESCONHECIDO')];
  return [...errosSetas(nos, setas), ...errosAlcance(nos, setas, gatilho.id), ...nos.flatMap(n => errosPasso(n, setas))];
};
```

- [ ] **Step 4: Rodar e ver passar**

Run: `TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/validar.spec.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/validar.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/validar.spec.js
git commit -m "feat(fluxos): validação do quadro espelhando o back" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 5: Modelos prontos (só passos da B1)

Decisão: modelos em JS (não `db/seeds/ramon/fluxos/*.json` como diz a spec §7) — só o front os consome; JSON em `db/seeds` exigiria endpoint novo ou import de fora de `app/javascript`. Os 6 "fluxos do sistema" da B3 continuam em `db/seeds` (lá quem lê é o Ruby).

Modelos da spec/mockup que entram (todos os passos existem na B1): **Em branco**, **Pós-contrato: pedir documentos** (sem o "Se documentos completos?" — o contexto da B1 não tem campo de documentos; volta na B2b), **Fora do horário**, **Rodar na mão**, **Lead ganho** (sem ADVBOX/NPS — B2b). Ficam para a B2b: Cadência de lead parado, Lembretes de reunião, Evento do ADVBOX.

⚠️ Os textos de rascunho dos modelos falam com cliente → **gate do Eduardo** (o código sobe; o texto só vira fluxo publicado com aprovação dele). Ficam OAB-safe: sem promessa de resultado nem prazo.

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/captain/automacoes/modelos.js`
- Test: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/modelos.spec.js`

**Interfaces:**
- Consumes: `validar` (Task 4), `paraVueFlow`/`deVueFlow` (Task 3).
- Produces: `MODELOS: Array<{ chave, icone, limite_dia?: number, desenho }>` (chave ∈ `branco|pos_contrato|fora_do_horario|rodar_na_mao|lead_ganho`; nome/descrição = i18n `CAPTAIN_RAMON.FLUXOS.MODELOS.<chave>.{NOME,DESCRICAO}`).

- [ ] **Step 1: Escrever os testes**

`…/automacoes/specs/modelos.spec.js`:

```js
import { MODELOS } from '../modelos';
import { validar } from '../validar';
import { deVueFlow, paraVueFlow } from '../fluxo';

describe('modelos prontos', () => {
  it('são os 5 da B2, com "em branco" primeiro', () => {
    expect(MODELOS.map(m => m.chave)).toEqual(['branco', 'pos_contrato', 'fora_do_horario', 'rodar_na_mao', 'lead_ganho']);
  });

  it.each(MODELOS.map(m => [m.chave, m]))('%s publica sem erro e reabre idêntico', (_chave, modelo) => {
    expect(validar(modelo.desenho)).toEqual([]);
    const { nodes, edges } = paraVueFlow(modelo.desenho);
    expect(deVueFlow(nodes, edges)).toEqual(modelo.desenho);
  });

  it('todo texto ao cliente é rascunho_texto (nunca envio)', () => {
    const tipos = MODELOS.flatMap(m => m.desenho.nos.map(n => n.tipo));
    expect(tipos).not.toContain('acao_chatwoot');
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/modelos.spec.js`
Expected: FAIL — `Failed to resolve import "../modelos"`.

- [ ] **Step 3: Implementar**

`…/automacoes/modelos.js`:

```js
// Modelos do "Novo fluxo" (B2): só passos que a B1 executa. Textos ao cliente
// saem como RASCUNHO e passam pelo Eduardo antes de qualquer fluxo publicado.
const no = (id, tipo, config, x, y) => ({ id, tipo, config, posicao: { x, y } });
const seta = (de, saida, para) => ({ de, saida, para });

export const MODELOS = [
  {
    chave: 'branco',
    icone: 'i-lucide-plus',
    desenho: { nos: [no('n1', 'gatilho', { tipo: 'manual' }, 0, 0)], setas: [] },
  },
  {
    chave: 'pos_contrato',
    icone: 'i-lucide-file-check',
    limite_dia: 20,
    desenho: {
      nos: [
        no('n1', 'gatilho', { tipo: 'lead_mudou_etapa', para_etapa_ids: [] }, 0, 0),
        no('n2', 'rascunho_texto', {
          rotulo: 'Boas-vindas',
          texto: 'Olá, {nome}! Seja bem-vindo(a). Para darmos andamento ao seu caso, vamos precisar de alguns documentos — já te explico quais.',
        }, 0, 140),
        no('n3', 'criar_tarefa', { titulo: 'Conferir documentos de {nome}', tipo: 'document', prazo_dias: 1 }, 0, 300),
        no('n4', 'esperar', { quantidade: 2, unidade: 'dias' }, 0, 440),
        no('n5', 'rascunho_texto', {
          rotulo: 'Lembrete dos documentos',
          texto: 'Oi, {nome}! Passando para lembrar dos documentos do seu caso. Se tiver dúvida sobre algum deles, é só me chamar por aqui.',
        }, 0, 580),
        no('n6', 'avisar_push', { texto: 'Lembrete de documentos pronto para revisar: {nome}' }, 0, 740),
      ],
      setas: [seta('n1', 's', 'n2'), seta('n2', 's', 'n3'), seta('n3', 's', 'n4'), seta('n4', 's', 'n5'), seta('n5', 's', 'n6')],
    },
  },
  {
    chave: 'fora_do_horario',
    icone: 'i-lucide-moon',
    limite_dia: 50,
    desenho: {
      nos: [
        no('n1', 'gatilho', { tipo: 'mensagem_recebida', caixa_ids: [] }, 0, 0),
        no('n2', 'se', { juncao: 'e', condicoes: [{ campo: 'texto', operador: 'em_horario_comercial', valor: '' }] }, 0, 140),
        no('n3', 'rascunho_texto', {
          rotulo: 'Retorno fora do horário',
          texto: 'Oi, {nome}! Recebemos sua mensagem. Nosso atendimento é em horário comercial — assim que a equipe voltar, respondemos por aqui.',
        }, 130, 300),
      ],
      setas: [seta('n1', 's', 'n2'), seta('n2', 'nao', 'n3')],
    },
  },
  {
    chave: 'rodar_na_mao',
    icone: 'i-lucide-hand',
    desenho: {
      nos: [
        no('n1', 'gatilho', { tipo: 'manual' }, 0, 0),
        no('n2', 'rascunho_texto', {
          rotulo: 'Pedir documentos',
          texto: 'Oi, {nome}! Para seguirmos com o seu caso, ainda precisamos de alguns documentos. Pode me enviar por aqui quando puder?',
        }, 0, 140),
        no('n3', 'criar_tarefa', { titulo: 'Cobrar documentos de {nome}', tipo: 'document', prazo_dias: 2 }, 0, 300),
      ],
      setas: [seta('n1', 's', 'n2'), seta('n2', 's', 'n3')],
    },
  },
  {
    chave: 'lead_ganho',
    icone: 'i-lucide-trophy',
    desenho: {
      nos: [
        no('n1', 'gatilho', { tipo: 'lead_ganho' }, 0, 0),
        no('n2', 'nota_privada', { texto: 'Lead ganho: conferir a passagem do caso para o jurídico (responsável: {responsavel}).' }, 0, 140),
        no('n3', 'criar_tarefa', { titulo: 'Passagem para o jurídico: {nome}', tipo: 'other', prazo_dias: 1 }, 0, 280),
        no('n4', 'avisar_sino', { texto: 'Lead ganho: {nome}' }, 0, 420),
      ],
      setas: [seta('n1', 's', 'n2'), seta('n2', 's', 'n3'), seta('n3', 's', 'n4')],
    },
  },
];
```

- [ ] **Step 4: Rodar e ver passar**

Run: `TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/modelos.spec.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/modelos.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/modelos.spec.js
git commit -m "feat(fluxos): modelos prontos do novo fluxo" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 6: Estado do editor (`useFluxoEditor`) — carregar, autosave, publicar, ensaiar

Decisão: sem módulo Vuex novo. Os `ramon_*` com uma tela só (Vigia, Execuções, Esteira) guardam estado na página; aqui a página do editor usa este composable (testável sozinho). Vuex só para o que já existe (etapas, pessoas, caixas, etiquetas, times, teses).

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/captain/automacoes/useFluxoEditor.js`
- Test: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/useFluxoEditor.spec.js`

**Interfaces:**
- Consumes: `RamonFluxosAPI` (Task 3), `paraVueFlow`, `deVueFlow`, `idDoErro` (Task 3), `validar` (Task 4).
- Produces: `useFluxoEditor() → { fluxo: Ref<object|null>, nodes: Ref<Array>, edges: Ref<Array>, desenho: ComputedRef, sujo: ComputedRef<boolean>, salvando: Ref<boolean>, errosFront: ComputedRef<Array<{no,codigo,params}>>, errosServidor: Ref<string[]>, mostrarErros: Ref<boolean>, nosComErro: ComputedRef<Set<string>>, carregar(id): Promise, recarregarMeta(): Promise, salvar(): Promise, atualizar(attrs): Promise, publicar(): Promise<number|null>, ensaiar(alvo): Promise<execucao>, rodar(alvo): Promise<execucao> }`. `fluxo` = resposta do `show` (inclui `versoes`, `versao`, `ativo`, `limite_dia`, `nome`, `gatilho_tipo`). `alvo` = `{ lead_id }` ou `{ conversation_id }`. `ensaiar`/`rodar` deixam o erro do axios subir (o modal mostra `erros`).

- [ ] **Step 1: Escrever os testes**

`…/automacoes/specs/useFluxoEditor.spec.js`:

```js
import { nextTick } from 'vue';
import { flushPromises } from '@vue/test-utils';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import { useFluxoEditor } from '../useFluxoEditor';

vi.mock('dashboard/api/ramonFluxos', () => ({
  default: { show: vi.fn(), update: vi.fn(), publicar: vi.fn(), ensaio: vi.fn(), rodar: vi.fn() },
}));

const RASCUNHO = {
  nos: [
    { id: 'n1', tipo: 'gatilho', config: { tipo: 'manual' }, posicao: { x: 0, y: 0 } },
    { id: 'n2', tipo: 'nota_privada', config: { texto: 'oi' }, posicao: { x: 0, y: 140 } },
  ],
  setas: [{ de: 'n1', saida: 's', para: 'n2' }],
};
const comTexto = (nodes, texto) =>
  nodes.map(n => (n.id === 'n2' ? { ...n, data: { ...n.data, config: { texto } } } : n));

describe('useFluxoEditor', () => {
  beforeEach(() => {
    // só setTimeout: o flushPromises usa setImmediate
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
    RamonFluxosAPI.show.mockResolvedValue({ data: { id: 7, nome: 'F', versao: null, versoes: [], rascunho: RASCUNHO } });
    RamonFluxosAPI.update.mockResolvedValue({ data: { id: 7 } });
    RamonFluxosAPI.publicar.mockResolvedValue({ data: { versao: 1 } });
    RamonFluxosAPI.ensaio.mockResolvedValue({ data: { id: 99 } });
  });
  afterEach(() => vi.useRealTimers());

  it('carrega sem ficar sujo', async () => {
    const ed = useFluxoEditor();
    await ed.carregar(7);
    expect(ed.nodes.value).toHaveLength(2);
    expect(ed.edges.value).toHaveLength(1);
    expect(ed.sujo.value).toBe(false);
  });

  it('salva o rascunho 1 s depois da última mudança', async () => {
    const ed = useFluxoEditor();
    await ed.carregar(7);
    ed.nodes.value = comTexto(ed.nodes.value, 'novo');
    await nextTick();
    vi.advanceTimersByTime(999);
    expect(RamonFluxosAPI.update).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    await flushPromises();
    expect(RamonFluxosAPI.update).toHaveBeenCalledTimes(1);
    expect(RamonFluxosAPI.update.mock.calls[0][1].rascunho.nos[1].config).toEqual({ texto: 'novo' });
    expect(ed.sujo.value).toBe(false);
  });

  it('publicar salva a mudança pendente ANTES de publicar', async () => {
    const ed = useFluxoEditor();
    await ed.carregar(7);
    ed.nodes.value = comTexto(ed.nodes.value, 'antes de publicar');
    await nextTick();
    expect(await ed.publicar()).toBe(1);
    expect(RamonFluxosAPI.update.mock.invocationCallOrder[0]).toBeLessThan(
      RamonFluxosAPI.publicar.mock.invocationCallOrder[0]
    );
  });

  it('desenho inválido não chama o back e acende o passo', async () => {
    const ed = useFluxoEditor();
    await ed.carregar(7);
    ed.nodes.value = comTexto(ed.nodes.value, '');
    await nextTick();
    expect(await ed.publicar()).toBeNull();
    expect(RamonFluxosAPI.publicar).not.toHaveBeenCalled();
    expect(ed.mostrarErros.value).toBe(true);
    expect(ed.nosComErro.value.has('n2')).toBe(true);
  });

  it('erro 422 do back: passo apontado acende, o resto vai para a faixa', async () => {
    RamonFluxosAPI.publicar.mockRejectedValue({
      response: { status: 422, data: { erros: ['Passo n2: falta texto', 'O fluxo não pode voltar para um passo anterior'] } },
    });
    const ed = useFluxoEditor();
    await ed.carregar(7);
    expect(await ed.publicar()).toBeNull();
    expect(ed.errosServidor.value).toHaveLength(2);
    expect(ed.nosComErro.value.has('n2')).toBe(true);
  });

  it('ensaiar salva antes e devolve a execução', async () => {
    const ed = useFluxoEditor();
    await ed.carregar(7);
    ed.nodes.value = comTexto(ed.nodes.value, 'ensaio');
    await nextTick();
    const exec = await ed.ensaiar({ lead_id: 5 });
    expect(exec).toEqual({ id: 99 });
    expect(RamonFluxosAPI.ensaio).toHaveBeenCalledWith(7, { lead_id: 5, usar: 'rascunho' });
    expect(RamonFluxosAPI.update).toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/useFluxoEditor.spec.js`
Expected: FAIL — `Failed to resolve import "../useFluxoEditor"`.

- [ ] **Step 3: Implementar**

`…/automacoes/useFluxoEditor.js`:

```js
// Estado do editor de um fluxo (B2). O quadro (Vue Flow) é dono de nodes/edges;
// o rascunho salva sozinho 1 s depois da última mudança (só se o desenho mudou
// de fato — mexer em seleção/medidas do Vue Flow não salva). Publicar e ensaiar
// sempre salvam antes: o que vale é o que está na tela.
import { computed, ref, watch } from 'vue';
import { watchDebounced } from '@vueuse/core';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import { deVueFlow, idDoErro, paraVueFlow } from './fluxo';
import { validar } from './validar';

export const useFluxoEditor = () => {
  const fluxo = ref(null);
  const nodes = ref([]);
  const edges = ref([]);
  const salvo = ref('');
  const salvando = ref(false);
  const errosServidor = ref([]);
  const mostrarErros = ref(false);

  const desenho = computed(() => deVueFlow(nodes.value, edges.value));
  const json = computed(() => JSON.stringify(desenho.value));
  const sujo = computed(() => Boolean(fluxo.value) && json.value !== salvo.value);
  const errosFront = computed(() => validar(desenho.value));
  const nosComErro = computed(
    () =>
      new Set(
        [...(mostrarErros.value ? errosFront.value.map(e => e.no) : []), ...errosServidor.value.map(idDoErro)].filter(Boolean)
      )
  );

  const carregar = async id => {
    const { data } = await RamonFluxosAPI.show(id);
    const vf = paraVueFlow(data.rascunho);
    fluxo.value = data;
    nodes.value = vf.nodes;
    edges.value = vf.edges;
    salvo.value = JSON.stringify(deVueFlow(vf.nodes, vf.edges));
  };

  const recarregarMeta = async () => {
    const { data } = await RamonFluxosAPI.show(fluxo.value.id);
    fluxo.value = data;
  };

  const salvar = async () => {
    if (!sujo.value) return;
    const enviado = json.value;
    salvando.value = true;
    try {
      await RamonFluxosAPI.update(fluxo.value.id, { rascunho: JSON.parse(enviado) });
      salvo.value = enviado;
    } finally {
      salvando.value = false;
    }
  };
  watchDebounced(json, salvar, { debounce: 1000 });
  watch(json, () => {
    errosServidor.value = [];
  });

  const atualizar = async attrs => {
    const { data } = await RamonFluxosAPI.update(fluxo.value.id, attrs);
    fluxo.value = { ...fluxo.value, ...data };
  };

  const publicar = async () => {
    mostrarErros.value = true;
    errosServidor.value = [];
    if (errosFront.value.length) return null;
    await salvar();
    try {
      const { data } = await RamonFluxosAPI.publicar(fluxo.value.id);
      await recarregarMeta();
      mostrarErros.value = false;
      return data.versao;
    } catch (e) {
      if (e.response?.status !== 422) throw e;
      errosServidor.value = e.response.data.erros || [];
      return null;
    }
  };

  const ensaiar = async alvo => {
    await salvar();
    const { data } = await RamonFluxosAPI.ensaio(fluxo.value.id, { ...alvo, usar: 'rascunho' });
    return data;
  };

  const rodar = async alvo => (await RamonFluxosAPI.rodar(fluxo.value.id, alvo)).data;

  return {
    fluxo,
    nodes,
    edges,
    desenho,
    sujo,
    salvando,
    errosFront,
    errosServidor,
    mostrarErros,
    nosComErro,
    carregar,
    recarregarMeta,
    salvar,
    atualizar,
    publicar,
    ensaiar,
    rodar,
  };
};
```

- [ ] **Step 4: Rodar e ver passar**

Run: `TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/useFluxoEditor.spec.js`
Expected: PASS (6).

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/useFluxoEditor.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/useFluxoEditor.spec.js
git commit -m "feat(fluxos): estado do editor com rascunho salvo sozinho" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 7: Textos (i18n en + pt_BR) + trava de sintaxe

**Files:**
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` (nova chave `FLUXOS` dentro de `CAPTAIN_RAMON`, logo antes de `"MESSAGE_TEMPLATES": {` — linha 1645 hoje)
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json` (idem, antes de `"MESSAGE_TEMPLATES": {` — linha 1640 hoje)
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/settings.json:322` e `app/javascript/dashboard/i18n/locale/en/settings.json:333` (+ `CAPTAIN_AUTOMACOES` depois de `CAPTAIN_WATCHDOG`)
- Test: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/i18n.spec.js`

**Interfaces:**
- Produces: todas as chaves `CAPTAIN_RAMON.FLUXOS.*` usadas nos Tasks 8–12 e `SIDEBAR.CAPTAIN_AUTOMACOES`. Os códigos de `validar` (Task 4) são as chaves de `ERROS`; os tipos de `fluxo.js` são as chaves de `GATILHOS`, `PASSOS`, `CABECALHO`, `PALETA`, `GRUPOS`, `ACOES_CHATWOOT`, `CAMPOS`, `OPERADORES`, `TIPOS_TAREFA`, `UNIDADES`, `PRIORIDADES`, `STATUS`.

- [ ] **Step 1: Escrever o teste**

`…/automacoes/specs/i18n.spec.js`:

```js
import en from 'dashboard/i18n/locale/en/ramon.json';
import pt from 'dashboard/i18n/locale/pt_BR/ramon.json';
import enSettings from 'dashboard/i18n/locale/en/settings.json';
import ptSettings from 'dashboard/i18n/locale/pt_BR/settings.json';
import { ACOES_CHATWOOT, CAMPOS, GATILHOS, OPERADORES, PALETA, PASSOS } from '../fluxo';
import { MODELOS } from '../modelos';

const folhas = (obj, prefixo = '') =>
  Object.entries(obj).flatMap(([k, v]) => (typeof v === 'object' ? folhas(v, `${prefixo}${k}.`) : [[`${prefixo}${k}`, v]]));

describe('textos das automações', () => {
  const FLUXOS_EN = en.CAPTAIN_RAMON.FLUXOS;
  const FLUXOS_PT = pt.CAPTAIN_RAMON.FLUXOS;

  it('en e pt_BR têm as mesmas chaves', () => {
    expect(folhas(FLUXOS_PT).map(([k]) => k)).toEqual(folhas(FLUXOS_EN).map(([k]) => k));
    expect(ptSettings.SIDEBAR.CAPTAIN_AUTOMACOES).toBe('Automações');
    expect(enSettings.SIDEBAR.CAPTAIN_AUTOMACOES).toBe('Automations');
  });

  it.each([['en', FLUXOS_EN], ['pt_BR', FLUXOS_PT]])('%s: sem @ | e chaves soltas (quebra o vue-i18n de produção)', (_l, textos) => {
    folhas(textos).forEach(([chave, texto]) => {
      const semPlaceholders = texto.replace(/\{[a-z_]+\}/gi, '');
      expect([chave, /[@|{}]/.test(semPlaceholders)]).toEqual([chave, false]);
    });
  });

  it('cobre todo o catálogo', () => {
    GATILHOS.forEach(g => expect(FLUXOS_PT.GATILHOS[g.tipo]).toBeTruthy());
    Object.keys(PASSOS).forEach(t => expect([t, FLUXOS_PT.PASSOS[t], FLUXOS_PT.CABECALHO[t]].every(Boolean)).toBe(true));
    PALETA.forEach(g => {
      expect(FLUXOS_PT.GRUPOS[g.grupo]).toBeTruthy();
      g.itens.forEach(i => expect(FLUXOS_PT.PALETA[i.chave]).toBeTruthy());
    });
    ACOES_CHATWOOT.forEach(a => expect(FLUXOS_PT.ACOES_CHATWOOT[a.nome]).toBeTruthy());
    CAMPOS.forEach(c => expect(FLUXOS_PT.CAMPOS[c]).toBeTruthy());
    OPERADORES.forEach(o => expect(FLUXOS_PT.OPERADORES[o]).toBeTruthy());
    MODELOS.forEach(m => expect(FLUXOS_PT.MODELOS[m.chave].NOME).toBeTruthy());
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/i18n.spec.js`
Expected: FAIL — `Cannot read properties of undefined (reading ...FLUXOS)`.

- [ ] **Step 3: pt_BR — `ramon.json`**

Inserir em `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`, dentro de `"CAPTAIN_RAMON"`, imediatamente antes de `"MESSAGE_TEMPLATES": {` (o bloco `WATCHDOG` termina com `},` logo acima):

```json
    "FLUXOS": {
      "TITULO": "Automações",
      "DICA": "o que o hub faz sozinho — tudo que chega ao cliente sai como rascunho",
      "NOVO": "Novo fluxo",
      "FECHAR": "Fechar",
      "ABA_MEUS": "Meus fluxos",
      "VAZIO": "Nenhum fluxo ainda. Comece por um modelo pronto em Novo fluxo.",
      "ERRO_CRIAR": "Não consegui criar o fluxo.",
      "RESUMO": {
        "LIGADOS": "Ligados",
        "DE": "de {total}",
        "HOJE": "Execuções hoje",
        "ESPERANDO": "Esperando",
        "FALHARAM": "Falharam (24h)"
      },
      "TABELA": {
        "FLUXO": "Fluxo",
        "GATILHO": "Gatilho",
        "HOJE_LIMITE": "Hoje / limite",
        "ESPERANDO": "Esperando",
        "ULTIMA": "Última"
      },
      "VERSAO_EDITADO": "v{versao} · editado em {data}",
      "NUNCA_PUBLICADO": "rascunho, nunca publicado",
      "PUBLIQUE_ANTES": "Publique o fluxo antes de ligar",
      "SELO": {
        "OK": "ok",
        "FALHOU": "{n} falhou",
        "DESLIGADO": "desligado"
      },
      "GATILHOS": {
        "conversa_criada": "Nova conversa",
        "mensagem_recebida": "Mensagem recebida",
        "conversa_resolvida": "Conversa resolvida",
        "conversa_reaberta": "Conversa reaberta",
        "conversa_atribuida": "Conversa atribuída",
        "lead_criado": "Lead criado",
        "lead_mudou_etapa": "Lead mudou de etapa",
        "lead_ganho": "Lead ganho",
        "lead_perdido": "Lead perdido",
        "manual": "Rodar na mão"
      },
      "PASSOS": {
        "gatilho": "Gatilho",
        "se": "Se… (sim / não)",
        "escolha": "Escolha por valor",
        "rascunho_texto": "Rascunho com texto fixo",
        "acao_chatwoot": "Ação da conversa",
        "nota_privada": "Nota privada",
        "mover_etapa": "Mover etapa",
        "criar_tarefa": "Criar tarefa na Esteira",
        "avisar_sino": "Sino do hub",
        "avisar_push": "Push no celular",
        "esperar": "Esperar",
        "parar": "Parar"
      },
      "CABECALHO": {
        "gatilho": "Gatilho",
        "se": "Se",
        "escolha": "Escolha",
        "rascunho_texto": "Mensagem ao cliente",
        "acao_chatwoot": "Conversa",
        "nota_privada": "Conversa",
        "mover_etapa": "Lead",
        "criar_tarefa": "Lead",
        "avisar_sino": "Avisar",
        "avisar_push": "Avisar",
        "esperar": "Esperar",
        "parar": "Parar"
      },
      "GRUPOS": {
        "CONDICAO": "Condição",
        "MENSAGEM": "Mensagem ao cliente (sempre rascunho)",
        "CONVERSA": "Conversa",
        "LEAD": "Lead",
        "AVISAR": "Avisar",
        "CONTROLE": "Controle"
      },
      "PALETA": {
        "se": "Se… (sim / não)",
        "escolha": "Escolha por valor",
        "rascunho_texto": "Rascunho com texto fixo",
        "etiqueta": "Pôr / tirar etiqueta",
        "atribuir": "Atribuir pessoa / time",
        "acao_chatwoot": "Outra ação da conversa",
        "nota_privada": "Nota privada",
        "mover_etapa": "Mover etapa",
        "criar_tarefa": "Criar tarefa na Esteira",
        "avisar_sino": "Sino do hub",
        "avisar_push": "Push no celular",
        "esperar": "Esperar",
        "parar": "Parar"
      },
      "SAIDAS": {
        "sim": "sim",
        "nao": "não",
        "outro": "outro"
      },
      "EDITOR": {
        "VOLTAR": "Automações",
        "NOME": "Nome do fluxo",
        "SELO_PUBLICADA": "rascunho · v{versao} publicada",
        "SELO_NUNCA": "rascunho · nunca publicado",
        "SALVANDO": "salvando…",
        "LIGADO": "Ligado",
        "LIMITE": "limite",
        "POR_DIA": "/dia",
        "VERSOES": "Versões",
        "SEM_VERSOES": "Nenhuma versão publicada ainda.",
        "VERSAO_ITEM": "v{numero} · {data}",
        "NO_AR": "no ar",
        "TESTAR": "Testar com um lead…",
        "PUBLICAR": "Publicar v{versao}",
        "PUBLICADO": "Versão {versao} publicada.",
        "ERRO_SALVAR": "Não consegui salvar. Tente de novo.",
        "ADICIONAR": "Adicionar passo",
        "ERROS_TITULO": "Antes de publicar, corrija:",
        "ERROS_NOS": "{n} passo(s) marcado(s) em vermelho no quadro.",
        "ZOOM_IN": "Aproximar",
        "ZOOM_OUT": "Afastar",
        "AJUSTAR": "Ajustar à tela",
        "EXCLUIR_FLUXO": "Excluir fluxo",
        "EXCLUIR_TITULO": "Excluir este fluxo?",
        "EXCLUIR_MSG": "Some o desenho, as versões e o histórico de execuções. Não dá para desfazer.",
        "EXECUCOES": "Execuções recentes",
        "SEM_EXECUCOES": "Nenhuma execução ainda. Use Testar com um lead… para ver o caminho.",
        "SELECIONE": "Clique num passo para configurar."
      },
      "NO": {
        "SAI_RASCUNHO": "sai como rascunho",
        "PARA": "para {etapas}",
        "QUALQUER_ETAPA": "qualquer mudança de etapa",
        "CAIXAS": "caixas: {caixas}",
        "CONDICOES": "{n} condição(ões)",
        "PASSO_N": "passo {id}"
      },
      "PAINEL": {
        "ROTULO": "Nome do passo (opcional)",
        "AVISO_RASCUNHO": "Sai como nota RASCUNHO na conversa. Quem envia é uma pessoa.",
        "TEXTO": "Texto",
        "TITULO_TAREFA": "Título da tarefa",
        "TIPO_TAREFA": "Tipo",
        "PRAZO": "Prazo (dias a partir de hoje)",
        "RESPONSAVEL": "Responsável",
        "RESPONSAVEL_DO_LEAD": "Responsável do lead",
        "ETAPA": "Etapa de destino",
        "ESCOLHA_ETAPA": "Escolha a etapa",
        "QUEM_RECEBE": "Quem recebe",
        "QUEM_RECEBE_AJUDA": "Ninguém marcado = responsável do lead.",
        "TITULO_PUSH": "Título (opcional — padrão: nome do fluxo)",
        "VARIAVEIS_AJUDA": "Clique numa variável para inserir no texto.",
        "ESPERAR_TEMPO": "Um tempo",
        "ESPERAR_HORARIO": "Até o próximo horário comercial",
        "QUANTIDADE": "Quanto",
        "UNIDADE": "Unidade",
        "ESPERAR_AJUDA": "Conta a partir do passo anterior.",
        "PARAR_AJUDA": "Encerra a execução aqui.",
        "DUPLICAR": "Duplicar",
        "EXCLUIR": "Excluir passo",
        "GATILHO_TIPO": "Quando roda",
        "CAIXAS": "Só nestas caixas",
        "CAIXAS_AJUDA": "Nenhuma marcada = todas as caixas.",
        "DE_ETAPAS": "Saindo de",
        "PARA_ETAPAS": "Entrando em",
        "ETAPAS_AJUDA": "Nenhuma marcada = qualquer etapa.",
        "CANCELAR_ETAPA": "Cancelar se o lead sair da etapa",
        "MANUAL_AJUDA": "Roda quando alguém aciona — por enquanto em Testar com um lead…, botão Rodar de verdade.",
        "JUNCAO": "Combinar condições",
        "JUNCAO_E": "Todas (E)",
        "JUNCAO_OU": "Qualquer uma (OU)",
        "CAMPO": "Campo",
        "OPERADOR": "Operador",
        "VALOR": "Valor",
        "ADD_CONDICAO": "Adicionar condição",
        "REMOVER": "Remover",
        "CAMPO_ESCOLHA": "Olhar o campo",
        "CASO": "Caso",
        "ROTULO_CASO": "Nome da saída",
        "VALORES": "Valores (Enter para incluir)",
        "ADD_CASO": "Adicionar caso",
        "OUTRO_AJUDA": "A saída outro pega o que não bateu com nenhum caso.",
        "ACAO": "Ação",
        "ADD_ACAO": "Adicionar ação",
        "ETIQUETAS": "Etiquetas",
        "PESSOA": "Pessoa",
        "TIME": "Time",
        "TIMES": "Times",
        "PRIORIDADE": "Prioridade",
        "MENSAGEM_EMAIL": "Mensagem do e-mail",
        "ESCOLHA": "Escolha…"
      },
      "ACOES_CHATWOOT": {
        "add_label": "Pôr etiqueta",
        "remove_label": "Tirar etiqueta",
        "assign_agent": "Atribuir a uma pessoa",
        "remove_assigned_agent": "Tirar a pessoa atribuída",
        "assign_team": "Atribuir a um time",
        "remove_assigned_team": "Tirar o time atribuído",
        "change_priority": "Mudar a prioridade",
        "resolve_conversation": "Resolver a conversa",
        "open_conversation": "Reabrir a conversa",
        "pending_conversation": "Marcar como pendente",
        "snooze_conversation": "Adiar a conversa",
        "mute_conversation": "Silenciar a conversa",
        "send_email_to_team": "E-mail para um time"
      },
      "PRIORIDADES": {
        "urgent": "Urgente",
        "high": "Alta",
        "medium": "Média",
        "low": "Baixa",
        "nil": "Nenhuma"
      },
      "CAMPOS": {
        "etapa": "Etapa",
        "tese": "Tese",
        "origem": "Origem",
        "canal": "Canal",
        "prioridade": "Prioridade",
        "responsavel": "Responsável",
        "caixa": "Caixa de entrada",
        "status": "Status da conversa",
        "etiquetas": "Etiquetas",
        "valor": "Valor",
        "texto": "Texto da mensagem",
        "nome": "Nome",
        "telefone": "Telefone"
      },
      "OPERADORES": {
        "igual": "é igual a",
        "diferente": "é diferente de",
        "contem": "contém",
        "nao_contem": "não contém",
        "maior": "é maior que",
        "menor": "é menor que",
        "existe": "está preenchido",
        "vazio": "está vazio",
        "em_horario_comercial": "agora é horário comercial"
      },
      "TIPOS_TAREFA": {
        "follow_up": "Retorno",
        "document": "Documento",
        "meeting": "Reunião",
        "other": "Outra"
      },
      "UNIDADES": {
        "minutos": "minutos",
        "horas": "horas",
        "dias": "dias"
      },
      "CAMPOS_OBRIGATORIOS": {
        "texto": "o texto",
        "etapa_id": "a etapa",
        "titulo": "o título",
        "campo": "o campo"
      },
      "ERROS": {
        "UM_GATILHO": "O fluxo precisa de exatamente 1 gatilho.",
        "GATILHO_DESCONHECIDO": "Escolha quando o fluxo roda.",
        "SETA_FANTASMA": "Uma seta aponta para um passo que não existe ({id}).",
        "SETA_REPETIDA": "Mais de uma seta na mesma saída ({saida}).",
        "CICLO": "O fluxo não pode voltar para um passo anterior.",
        "SOLTO": "Este passo não está ligado ao gatilho.",
        "TIPO_DESCONHECIDO": "Tipo de passo desconhecido ({tipo}).",
        "FALTA": "Falta preencher {campo}.",
        "SE_SEM_CONDICOES": "Coloque pelo menos uma condição.",
        "SE_SEM_SAIDA": "Ligue pelo menos uma das saídas (sim ou não).",
        "ESCOLHA_POUCOS_CASOS": "Precisa de pelo menos 2 casos.",
        "ESCOLHA_CHAVE_REPETIDA": "Dois casos com a mesma saída.",
        "ESCOLHA_VALOR_REPETIDO": "O mesmo valor está em dois casos.",
        "ESPERA_SEM_TEMPO": "Falta o tempo de espera.",
        "CHATWOOT_SEM_ACAO": "Escolha pelo menos uma ação.",
        "CHATWOOT_MENSAGEM": "Mensagem ao cliente só como rascunho.",
        "CHATWOOT_PROIBIDA": "Ação não permitida no fluxo ({nome}).",
        "CHATWOOT_DESCONHECIDA": "Ação desconhecida ({nome})."
      },
      "TESTAR": {
        "TITULO": "Testar com um lead",
        "AJUDA": "Ensaio: roda o rascunho com dados reais, pula as esperas e só descreve as ações — nada é executado.",
        "LEAD": "Lead",
        "CONVERSA": "Conversa",
        "BUSCAR": "Buscar lead pelo nome ou telefone",
        "NUMERO_CONVERSA": "Número da conversa",
        "ENSAIAR": "Ensaiar",
        "RODAR": "Rodar de verdade",
        "RODAR_AJUDA": "Executa a versão publicada neste lead (os textos saem como rascunho).",
        "ERRO": "Não consegui rodar o ensaio.",
        "NAO_RODOU": "Não rodou: o fluxo precisa estar ligado, publicado e dentro do limite do dia.",
        "CANCELAR": "Cancelar"
      },
      "EXECUCAO": {
        "TITULO": "Execução #{id}",
        "ENSAIO": "ensaio",
        "VOLTAR_EDITAR": "Voltar a editar",
        "CAMINHO": "Caminho percorrido",
        "INTERVALO": "{versao} · {inicio} → {fim}",
        "RASCUNHO": "rascunho",
        "VERSAO": "v{versao}",
        "LEAD_N": "Lead #{id}",
        "CONVERSA_N": "Conversa #{id}",
        "ABRIR": "Abrir",
        "VER_CONVERSA": "Ver na conversa",
        "CANCELADO": "Cancelado",
        "ESPERANDO_ATE": "Esperando até {quando}",
        "ERRO": "Erro: {erro}",
        "NAO_ACHEI": "Não achei esta execução."
      },
      "STATUS": {
        "rodando": "rodando",
        "esperando": "esperando",
        "concluida": "concluída",
        "falhou": "falhou",
        "cancelada": "cancelada"
      },
      "MODELOS": {
        "branco": {
          "NOME": "Em branco",
          "DESCRICAO": "Começar só com o gatilho"
        },
        "pos_contrato": {
          "NOME": "Pós-contrato: pedir documentos",
          "DESCRICAO": "Mudou de etapa → boas-vindas → tarefa → espera 2 dias → lembrete + push"
        },
        "fora_do_horario": {
          "NOME": "Fora do horário",
          "DESCRICAO": "Mensagem recebida fora do expediente → rascunho de retorno"
        },
        "rodar_na_mao": {
          "NOME": "Rodar na mão",
          "DESCRICAO": "Você aciona num lead → rascunho pedindo documentos + tarefa"
        },
        "lead_ganho": {
          "NOME": "Lead ganho",
          "DESCRICAO": "Nota de passagem pro jurídico + tarefa + sino"
        }
      }
    },
```

- [ ] **Step 4: en — `ramon.json`**

Mesmo lugar em `app/javascript/dashboard/i18n/locale/en/ramon.json` (antes de `"MESSAGE_TEMPLATES": {`), mesmas chaves:

```json
    "FLUXOS": {
      "TITULO": "Automations",
      "DICA": "what the hub does on its own — everything that reaches the client is a draft",
      "NOVO": "New flow",
      "FECHAR": "Close",
      "ABA_MEUS": "My flows",
      "VAZIO": "No flows yet. Start from a template in New flow.",
      "ERRO_CRIAR": "Could not create the flow.",
      "RESUMO": {
        "LIGADOS": "On",
        "DE": "of {total}",
        "HOJE": "Runs today",
        "ESPERANDO": "Waiting",
        "FALHARAM": "Failed (24h)"
      },
      "TABELA": {
        "FLUXO": "Flow",
        "GATILHO": "Trigger",
        "HOJE_LIMITE": "Today / limit",
        "ESPERANDO": "Waiting",
        "ULTIMA": "Last"
      },
      "VERSAO_EDITADO": "v{versao} · edited on {data}",
      "NUNCA_PUBLICADO": "draft, never published",
      "PUBLIQUE_ANTES": "Publish the flow before turning it on",
      "SELO": {
        "OK": "ok",
        "FALHOU": "{n} failed",
        "DESLIGADO": "off"
      },
      "GATILHOS": {
        "conversa_criada": "New conversation",
        "mensagem_recebida": "Message received",
        "conversa_resolvida": "Conversation resolved",
        "conversa_reaberta": "Conversation reopened",
        "conversa_atribuida": "Conversation assigned",
        "lead_criado": "Lead created",
        "lead_mudou_etapa": "Lead changed stage",
        "lead_ganho": "Lead won",
        "lead_perdido": "Lead lost",
        "manual": "Run by hand"
      },
      "PASSOS": {
        "gatilho": "Trigger",
        "se": "If… (yes / no)",
        "escolha": "Choose by value",
        "rascunho_texto": "Draft with fixed text",
        "acao_chatwoot": "Conversation action",
        "nota_privada": "Private note",
        "mover_etapa": "Move stage",
        "criar_tarefa": "Create task in the Queue",
        "avisar_sino": "Hub bell",
        "avisar_push": "Phone push",
        "esperar": "Wait",
        "parar": "Stop"
      },
      "CABECALHO": {
        "gatilho": "Trigger",
        "se": "If",
        "escolha": "Choose",
        "rascunho_texto": "Message to client",
        "acao_chatwoot": "Conversation",
        "nota_privada": "Conversation",
        "mover_etapa": "Lead",
        "criar_tarefa": "Lead",
        "avisar_sino": "Notify",
        "avisar_push": "Notify",
        "esperar": "Wait",
        "parar": "Stop"
      },
      "GRUPOS": {
        "CONDICAO": "Condition",
        "MENSAGEM": "Message to client (always a draft)",
        "CONVERSA": "Conversation",
        "LEAD": "Lead",
        "AVISAR": "Notify",
        "CONTROLE": "Control"
      },
      "PALETA": {
        "se": "If… (yes / no)",
        "escolha": "Choose by value",
        "rascunho_texto": "Draft with fixed text",
        "etiqueta": "Add / remove label",
        "atribuir": "Assign person / team",
        "acao_chatwoot": "Other conversation action",
        "nota_privada": "Private note",
        "mover_etapa": "Move stage",
        "criar_tarefa": "Create task in the Queue",
        "avisar_sino": "Hub bell",
        "avisar_push": "Phone push",
        "esperar": "Wait",
        "parar": "Stop"
      },
      "SAIDAS": {
        "sim": "yes",
        "nao": "no",
        "outro": "other"
      },
      "EDITOR": {
        "VOLTAR": "Automations",
        "NOME": "Flow name",
        "SELO_PUBLICADA": "draft · v{versao} published",
        "SELO_NUNCA": "draft · never published",
        "SALVANDO": "saving…",
        "LIGADO": "On",
        "LIMITE": "limit",
        "POR_DIA": "/day",
        "VERSOES": "Versions",
        "SEM_VERSOES": "No published version yet.",
        "VERSAO_ITEM": "v{numero} · {data}",
        "NO_AR": "live",
        "TESTAR": "Test with a lead…",
        "PUBLICAR": "Publish v{versao}",
        "PUBLICADO": "Version {versao} published.",
        "ERRO_SALVAR": "Could not save. Try again.",
        "ADICIONAR": "Add step",
        "ERROS_TITULO": "Before publishing, fix:",
        "ERROS_NOS": "{n} step(s) marked in red on the board.",
        "ZOOM_IN": "Zoom in",
        "ZOOM_OUT": "Zoom out",
        "AJUSTAR": "Fit to screen",
        "EXCLUIR_FLUXO": "Delete flow",
        "EXCLUIR_TITULO": "Delete this flow?",
        "EXCLUIR_MSG": "The design, versions and run history go away. This cannot be undone.",
        "EXECUCOES": "Recent runs",
        "SEM_EXECUCOES": "No runs yet. Use Test with a lead… to see the path.",
        "SELECIONE": "Click a step to configure it."
      },
      "NO": {
        "SAI_RASCUNHO": "goes out as a draft",
        "PARA": "to {etapas}",
        "QUALQUER_ETAPA": "any stage change",
        "CAIXAS": "inboxes: {caixas}",
        "CONDICOES": "{n} condition(s)",
        "PASSO_N": "step {id}"
      },
      "PAINEL": {
        "ROTULO": "Step name (optional)",
        "AVISO_RASCUNHO": "Goes out as a DRAFT note in the conversation. A person sends it.",
        "TEXTO": "Text",
        "TITULO_TAREFA": "Task title",
        "TIPO_TAREFA": "Type",
        "PRAZO": "Due (days from today)",
        "RESPONSAVEL": "Owner",
        "RESPONSAVEL_DO_LEAD": "Lead owner",
        "ETAPA": "Target stage",
        "ESCOLHA_ETAPA": "Choose the stage",
        "QUEM_RECEBE": "Who gets it",
        "QUEM_RECEBE_AJUDA": "Nobody checked = lead owner.",
        "TITULO_PUSH": "Title (optional — default: flow name)",
        "VARIAVEIS_AJUDA": "Click a variable to insert it in the text.",
        "ESPERAR_TEMPO": "An amount of time",
        "ESPERAR_HORARIO": "Until the next business hours",
        "QUANTIDADE": "How long",
        "UNIDADE": "Unit",
        "ESPERAR_AJUDA": "Counts from the previous step.",
        "PARAR_AJUDA": "Ends the run here.",
        "DUPLICAR": "Duplicate",
        "EXCLUIR": "Delete step",
        "GATILHO_TIPO": "When it runs",
        "CAIXAS": "Only in these inboxes",
        "CAIXAS_AJUDA": "None checked = all inboxes.",
        "DE_ETAPAS": "Leaving",
        "PARA_ETAPAS": "Entering",
        "ETAPAS_AJUDA": "None checked = any stage.",
        "CANCELAR_ETAPA": "Cancel if the lead leaves the stage",
        "MANUAL_AJUDA": "Runs when someone triggers it — for now in Test with a lead…, Run for real button.",
        "JUNCAO": "Combine conditions",
        "JUNCAO_E": "All (AND)",
        "JUNCAO_OU": "Any (OR)",
        "CAMPO": "Field",
        "OPERADOR": "Operator",
        "VALOR": "Value",
        "ADD_CONDICAO": "Add condition",
        "REMOVER": "Remove",
        "CAMPO_ESCOLHA": "Look at field",
        "CASO": "Case",
        "ROTULO_CASO": "Output name",
        "VALORES": "Values (Enter to add)",
        "ADD_CASO": "Add case",
        "OUTRO_AJUDA": "The other output takes whatever matched no case.",
        "ACAO": "Action",
        "ADD_ACAO": "Add action",
        "ETIQUETAS": "Labels",
        "PESSOA": "Person",
        "TIME": "Team",
        "TIMES": "Teams",
        "PRIORIDADE": "Priority",
        "MENSAGEM_EMAIL": "Email message",
        "ESCOLHA": "Choose…"
      },
      "ACOES_CHATWOOT": {
        "add_label": "Add label",
        "remove_label": "Remove label",
        "assign_agent": "Assign to a person",
        "remove_assigned_agent": "Unassign the person",
        "assign_team": "Assign to a team",
        "remove_assigned_team": "Unassign the team",
        "change_priority": "Change priority",
        "resolve_conversation": "Resolve the conversation",
        "open_conversation": "Reopen the conversation",
        "pending_conversation": "Mark as pending",
        "snooze_conversation": "Snooze the conversation",
        "mute_conversation": "Mute the conversation",
        "send_email_to_team": "Email a team"
      },
      "PRIORIDADES": {
        "urgent": "Urgent",
        "high": "High",
        "medium": "Medium",
        "low": "Low",
        "nil": "None"
      },
      "CAMPOS": {
        "etapa": "Stage",
        "tese": "Thesis",
        "origem": "Source",
        "canal": "Channel",
        "prioridade": "Priority",
        "responsavel": "Owner",
        "caixa": "Inbox",
        "status": "Conversation status",
        "etiquetas": "Labels",
        "valor": "Value",
        "texto": "Message text",
        "nome": "Name",
        "telefone": "Phone"
      },
      "OPERADORES": {
        "igual": "equals",
        "diferente": "is not",
        "contem": "contains",
        "nao_contem": "does not contain",
        "maior": "is greater than",
        "menor": "is less than",
        "existe": "is filled",
        "vazio": "is empty",
        "em_horario_comercial": "it is business hours now"
      },
      "TIPOS_TAREFA": {
        "follow_up": "Follow-up",
        "document": "Document",
        "meeting": "Meeting",
        "other": "Other"
      },
      "UNIDADES": {
        "minutos": "minutes",
        "horas": "hours",
        "dias": "days"
      },
      "CAMPOS_OBRIGATORIOS": {
        "texto": "the text",
        "etapa_id": "the stage",
        "titulo": "the title",
        "campo": "the field"
      },
      "ERROS": {
        "UM_GATILHO": "The flow needs exactly 1 trigger.",
        "GATILHO_DESCONHECIDO": "Choose when the flow runs.",
        "SETA_FANTASMA": "An arrow points to a step that does not exist ({id}).",
        "SETA_REPETIDA": "More than one arrow on the same output ({saida}).",
        "CICLO": "The flow cannot go back to a previous step.",
        "SOLTO": "This step is not connected to the trigger.",
        "TIPO_DESCONHECIDO": "Unknown step type ({tipo}).",
        "FALTA": "Fill in {campo}.",
        "SE_SEM_CONDICOES": "Add at least one condition.",
        "SE_SEM_SAIDA": "Connect at least one output (yes or no).",
        "ESCOLHA_POUCOS_CASOS": "Needs at least 2 cases.",
        "ESCOLHA_CHAVE_REPETIDA": "Two cases with the same output.",
        "ESCOLHA_VALOR_REPETIDO": "The same value is in two cases.",
        "ESPERA_SEM_TEMPO": "The wait time is missing.",
        "CHATWOOT_SEM_ACAO": "Choose at least one action.",
        "CHATWOOT_MENSAGEM": "Messages to the client only as drafts.",
        "CHATWOOT_PROIBIDA": "Action not allowed in a flow ({nome}).",
        "CHATWOOT_DESCONHECIDA": "Unknown action ({nome})."
      },
      "TESTAR": {
        "TITULO": "Test with a lead",
        "AJUDA": "Dry run: runs the draft on real data, skips waits and only describes the actions — nothing is executed.",
        "LEAD": "Lead",
        "CONVERSA": "Conversation",
        "BUSCAR": "Search lead by name or phone",
        "NUMERO_CONVERSA": "Conversation number",
        "ENSAIAR": "Dry run",
        "RODAR": "Run for real",
        "RODAR_AJUDA": "Runs the published version on this lead (texts go out as drafts).",
        "ERRO": "Could not run the dry run.",
        "NAO_RODOU": "Did not run: the flow must be on, published and under today's limit.",
        "CANCELAR": "Cancel"
      },
      "EXECUCAO": {
        "TITULO": "Run #{id}",
        "ENSAIO": "dry run",
        "VOLTAR_EDITAR": "Back to editing",
        "CAMINHO": "Path taken",
        "INTERVALO": "{versao} · {inicio} → {fim}",
        "RASCUNHO": "draft",
        "VERSAO": "v{versao}",
        "LEAD_N": "Lead #{id}",
        "CONVERSA_N": "Conversation #{id}",
        "ABRIR": "Open",
        "VER_CONVERSA": "See in conversation",
        "CANCELADO": "Cancelled",
        "ESPERANDO_ATE": "Waiting until {quando}",
        "ERRO": "Error: {erro}",
        "NAO_ACHEI": "Could not find this run."
      },
      "STATUS": {
        "rodando": "running",
        "esperando": "waiting",
        "concluida": "done",
        "falhou": "failed",
        "cancelada": "cancelled"
      },
      "MODELOS": {
        "branco": {
          "NOME": "Blank",
          "DESCRICAO": "Start with just the trigger"
        },
        "pos_contrato": {
          "NOME": "After contract: ask for documents",
          "DESCRICAO": "Stage changed → welcome → task → wait 2 days → reminder + push"
        },
        "fora_do_horario": {
          "NOME": "After hours",
          "DESCRICAO": "Message received outside business hours → reply draft"
        },
        "rodar_na_mao": {
          "NOME": "Run by hand",
          "DESCRICAO": "You trigger it on a lead → draft asking for documents + task"
        },
        "lead_ganho": {
          "NOME": "Lead won",
          "DESCRICAO": "Handover note for legal + task + bell"
        }
      }
    },
```

- [ ] **Step 5: Menu — `settings.json`**

`app/javascript/dashboard/i18n/locale/pt_BR/settings.json`, logo após a linha `"CAPTAIN_WATCHDOG": "Vigia",`:
```json
    "CAPTAIN_AUTOMACOES": "Automações",
```
`app/javascript/dashboard/i18n/locale/en/settings.json`, logo após `"CAPTAIN_WATCHDOG": "Watchdog",`:
```json
    "CAPTAIN_AUTOMACOES": "Automations",
```

- [ ] **Step 6: Rodar e ver passar + JSON válido**

```bash
node -e "for (const f of ['en','pt_BR']) for (const a of ['ramon','settings']) JSON.parse(require('fs').readFileSync('app/javascript/dashboard/i18n/locale/'+f+'/'+a+'.json','utf8'))" && echo json-ok
TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/i18n.spec.js
```
Expected: `json-ok`; PASS.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/i18n/locale/en/settings.json app/javascript/dashboard/i18n/locale/pt_BR/settings.json app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/i18n.spec.js
git commit -m "feat(fluxos): textos das automações (en + pt-BR)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 8: Rotas + menu + Lista + Novo fluxo

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/captain.routes.js:122-129` (3 rotas depois de `captain_watchdog_index`, antes do catch-all) e topo do arquivo (`metaAdmin`)
- Modify: `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:458` (item novo depois do bloco `name: 'Watchdog'`)
- Create: `app/javascript/dashboard/routes/dashboard/captain/automacoes/Lista.vue`
- Create: `app/javascript/dashboard/routes/dashboard/captain/automacoes/NovoFluxo.vue`
- Create (stub até o Task 11/12): `…/automacoes/Editor.vue`, `…/automacoes/Execucao.vue`
- Test: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/Lista.spec.js`

**Interfaces:**
- Consumes: `RamonFluxosAPI` (Task 3), `gatilhoInfo` (Task 3), `MODELOS` (Task 5), i18n (Task 7).
- Produces: rotas `captain_automacoes_index`, `captain_automacoes_editor` (params `fluxoId`), `captain_automacoes_execucao` (params `fluxoId`, `execId`). `NovoFluxo` emite `criar(modelo)` e `fechar`.

- [ ] **Step 1: Escrever o teste da lista**

`…/automacoes/specs/Lista.spec.js`:

```js
import { mount, flushPromises } from '@vue/test-utils';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import Lista from '../Lista.vue';

const push = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: (name, params) => ({ name, params }) }),
}));
vi.mock('dashboard/api/ramonFluxos', () => ({ default: { get: vi.fn(), update: vi.fn(), create: vi.fn() } }));

const FLUXO = {
  id: 1,
  nome: 'Pós-contrato',
  gatilho_tipo: 'lead_mudou_etapa',
  ativo: true,
  limite_dia: 20,
  origem: 'usuario',
  versao: 3,
  editado_em: '2026-10-04T12:00:00Z',
  hoje: 3,
  esperando: 8,
  falharam_24h: 0,
  ultima_em: null,
};

describe('Lista de automações', () => {
  beforeEach(() => {
    RamonFluxosAPI.get.mockResolvedValue({
      data: {
        payload: [FLUXO, { ...FLUXO, id: 2, nome: 'Rascunho', ativo: false, versao: null, gatilho_tipo: null, falharam_24h: 1 }, { ...FLUXO, id: 3, origem: 'sistema' }],
        resumo: { ligados: 1, total: 3, hoje: 3, esperando: 8, falharam_24h: 1 },
      },
    });
    RamonFluxosAPI.update.mockResolvedValue({ data: {} });
  });

  it('mostra os 4 números e só "Meus fluxos" (sem os do sistema)', async () => {
    const wrapper = mount(Lista);
    await flushPromises();
    expect(wrapper.findAll('[data-testid="fluxo-linha"]')).toHaveLength(2);
    expect(wrapper.find('[data-testid="fluxos-resumo"]').text()).toContain('1');
    expect(wrapper.text()).toContain('3 / 20');
    expect(wrapper.text()).toContain('1 failed');
  });

  it('clicar na linha abre o editor', async () => {
    const wrapper = mount(Lista);
    await flushPromises();
    await wrapper.find('[data-testid="fluxo-linha"]').trigger('click');
    expect(push).toHaveBeenCalledWith({ name: 'captain_automacoes_editor', params: { fluxoId: 1 } });
  });

  it('a chave liga/desliga sem abrir o editor', async () => {
    const wrapper = mount(Lista);
    await flushPromises();
    await wrapper.find('[data-testid="fluxo-linha"] [role="switch"]').trigger('click');
    expect(RamonFluxosAPI.update).toHaveBeenCalledWith(1, { ativo: false });
    expect(push).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/Lista.spec.js`
Expected: FAIL — `Failed to resolve import "../Lista.vue"`.

- [ ] **Step 3: Rotas**

Em `app/javascript/dashboard/routes/dashboard/captain/captain.routes.js`, depois de `const metaV2 = {…};`:

```js
// ramon: Automações (fluxos) — a API é só de administrador.
const metaAdmin = { ...meta, permissions: ['administrator'] };
```

E depois do bloco `captain_watchdog_index` (antes do `:navigationPath`):

```js
  {
    path: frontendURL('accounts/:accountId/captain/automacoes'),
    component: () => import('./automacoes/Lista.vue'),
    name: 'captain_automacoes_index',
    meta: metaAdmin,
  },
  {
    path: frontendURL('accounts/:accountId/captain/automacoes/:fluxoId'),
    component: () => import('./automacoes/Editor.vue'),
    name: 'captain_automacoes_editor',
    meta: metaAdmin,
  },
  {
    path: frontendURL(
      'accounts/:accountId/captain/automacoes/:fluxoId/execucoes/:execId'
    ),
    component: () => import('./automacoes/Execucao.vue'),
    name: 'captain_automacoes_execucao',
    meta: metaAdmin,
  },
```

- [ ] **Step 4: Menu**

Em `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`, logo depois do item `name: 'Watchdog'` (que fecha em `},` na linha 458):

```js
        {
          name: 'Automacoes',
          label: t('SIDEBAR.CAPTAIN_AUTOMACOES'),
          activeOn: [
            'captain_automacoes_index',
            'captain_automacoes_editor',
            'captain_automacoes_execucao',
          ],
          to: accountScopedRoute('captain_automacoes_index'),
        },
```
(O `isAllowed` do `SidebarGroup` esconde o item de quem não é administrador — lê a `meta.permissions` da rota.)

- [ ] **Step 5: Stubs das telas 2 e 3 (para o import das rotas resolver)**

`…/automacoes/Editor.vue` e `…/automacoes/Execucao.vue`, cada um com:

```vue
<template>
  <section class="w-full h-full" />
</template>
```
(substituídos por inteiro nos Tasks 11 e 12)

- [ ] **Step 6: `NovoFluxo.vue`**

```vue
<script setup>
// Modal "Novo fluxo" (mockup tela 4): em branco + modelos prontos.
import { useI18n } from 'vue-i18n';
import { onKeyStroke } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import { FUNDO_JANELA, JANELA } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { MODELOS } from './modelos';

const emit = defineEmits(['criar', 'fechar']);
const { t } = useI18n();
onKeyStroke('Escape', () => emit('fechar'));
</script>

<template>
  <div :class="FUNDO_JANELA" @click.self="emit('fechar')">
    <div :class="JANELA" class="!w-[720px] !p-0">
      <div class="flex items-center border-b border-n-weak px-5 py-4">
        <h2 class="text-[15px] font-semibold text-n-slate-12">
          {{ t('CAPTAIN_RAMON.FLUXOS.NOVO') }}
        </h2>
        <Button
          class="ml-auto"
          ghost
          slate
          xs
          icon="i-lucide-x"
          :title="t('CAPTAIN_RAMON.FLUXOS.FECHAR')"
          @click="emit('fechar')"
        />
      </div>
      <div class="grid grid-cols-1 gap-2.5 p-5 sm:grid-cols-2">
        <button
          v-for="modelo in MODELOS"
          :key="modelo.chave"
          type="button"
          data-testid="fluxo-modelo"
          class="flex gap-3 rounded-xl border border-n-weak p-3 text-left hover:border-n-blue-9 hover:bg-n-blue-9/[0.08]"
          :class="modelo.chave === 'branco' ? 'border-dashed' : ''"
          @click="emit('criar', modelo)"
        >
          <span
            class="grid size-[30px] shrink-0 place-items-center rounded-lg bg-n-alpha-2 text-n-slate-11"
          >
            <i :class="modelo.icone" class="size-4" />
          </span>
          <span>
            <b class="block text-[13.5px] font-medium text-n-slate-12">
              {{ t(`CAPTAIN_RAMON.FLUXOS.MODELOS.${modelo.chave}.NOME`) }}
            </b>
            <span class="text-[12.5px] text-n-slate-11">
              {{ t(`CAPTAIN_RAMON.FLUXOS.MODELOS.${modelo.chave}.DESCRICAO`) }}
            </span>
          </span>
        </button>
      </div>
    </div>
  </div>
</template>
```

- [ ] **Step 7: `Lista.vue`**

```vue
<script setup>
// Automações (B2, mockup tela 1): 4 números, a lista de fluxos com liga/desliga
// e o que rodou hoje. A aba "Do sistema" chega na B3 (spec §8).
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import { ABA, ABA_ATIVA, CHIP, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { gatilhoInfo } from './fluxo';
import NovoFluxo from './NovoFluxo.vue';

defineOptions({ name: 'CaptainAutomacoes' });

const K = 'CAPTAIN_RAMON.FLUXOS';
const { t } = useI18n();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const fluxos = ref([]);
const resumo = ref({});
const erro = ref(false);
const novo = ref(false);

const carregar = async () => {
  erro.value = false;
  try {
    const { data } = await RamonFluxosAPI.get();
    fluxos.value = data.payload.filter(f => f.origem !== 'sistema');
    resumo.value = data.resumo;
  } catch (e) {
    erro.value = true;
  }
};
onMounted(carregar);

const abrir = id => router.push(accountScopedRoute('captain_automacoes_editor', { fluxoId: id }));

const ligar = async (fluxo, ativo) => {
  await RamonFluxosAPI.update(fluxo.id, { ativo });
  carregar();
};

const criar = async modelo => {
  try {
    const { data } = await RamonFluxosAPI.create({
      nome: t(`${K}.MODELOS.${modelo.chave}.NOME`),
      limite_dia: modelo.limite_dia ?? null,
      rascunho: modelo.desenho,
    });
    abrir(data.id);
  } catch (e) {
    useAlert(t(`${K}.ERRO_CRIAR`));
  }
};

const TRACO = '—';
const selo = f => {
  if (f.falharam_24h) return { classe: TOM.ruby, icone: 'i-lucide-triangle-alert', texto: t(`${K}.SELO.FALHOU`, { n: f.falharam_24h }) };
  if (!f.ativo) return { classe: TOM.slate, icone: '', texto: t(`${K}.SELO.DESLIGADO`) };
  return { classe: TOM.teal, icone: '', texto: t(`${K}.SELO.OK`) };
};
const subtitulo = f =>
  f.versao
    ? t(`${K}.VERSAO_EDITADO`, { versao: f.versao, data: new Date(f.editado_em).toLocaleDateString('pt-BR') })
    : t(`${K}.NUNCA_PUBLICADO`);
const hojeLimite = f => `${f.hoje} / ${f.limite_dia ?? TRACO}`;
const largura = f => `${Math.min(100, Math.round((f.hoje / f.limite_dia) * 100))}%`;
const ultima = iso => (iso ? dynamicTime(Math.floor(new Date(iso).getTime() / 1000)) : TRACO);
const gatilho = tipo => (tipo ? t(`${K}.GATILHOS.${tipo}`) : TRACO);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <div class="flex h-14 shrink-0 items-center gap-2.5 border-b border-n-weak px-7">
      <h1 class="text-[15px] font-semibold text-n-slate-12">{{ t(`${K}.TITULO`) }}</h1>
      <span class="hidden text-[13px] text-n-slate-10 md:inline">{{ t(`${K}.DICA`) }}</span>
      <Button class="ml-auto" sm icon="i-lucide-plus" :label="t(`${K}.NOVO`)" @click="novo = true" />
    </div>
    <div class="flex gap-1 border-b border-n-weak px-7 pt-3">
      <span :class="[ABA, ABA_ATIVA]">
        {{ t(`${K}.ABA_MEUS`) }}
        <span class="font-mono text-[11.5px] text-n-slate-10">{{ fluxos.length }}</span>
      </span>
    </div>

    <div class="flex-1 overflow-y-auto px-7 pb-12 pt-5">
      <div v-if="erro" class="text-sm text-n-ruby-11">
        {{ t('CAPTAIN_RAMON.LOAD_ERROR') }}
        <button type="button" class="ml-1 text-n-blue-11 hover:underline" @click="carregar">
          {{ t('CAPTAIN_RAMON.RETRY') }}
        </button>
      </div>

      <template v-else>
        <div data-testid="fluxos-resumo" class="mb-5 grid max-w-[1100px] grid-cols-2 gap-3 md:grid-cols-4">
          <div class="rounded-xl border border-n-weak px-3.5 py-3">
            <span class="block text-xs text-n-slate-10">{{ t(`${K}.RESUMO.LIGADOS`) }}</span>
            <b class="font-mono text-xl font-medium text-n-slate-12">
              {{ resumo.ligados ?? 0 }}
              <small class="text-xs font-normal text-n-slate-10">{{ t(`${K}.RESUMO.DE`, { total: fluxos.length }) }}</small>
            </b>
          </div>
          <div class="rounded-xl border border-n-weak px-3.5 py-3">
            <span class="block text-xs text-n-slate-10">{{ t(`${K}.RESUMO.HOJE`) }}</span>
            <b class="font-mono text-xl font-medium text-n-slate-12">{{ resumo.hoje ?? 0 }}</b>
          </div>
          <div class="rounded-xl border border-n-weak px-3.5 py-3">
            <span class="block text-xs text-n-slate-10">{{ t(`${K}.RESUMO.ESPERANDO`) }}</span>
            <b class="font-mono text-xl font-medium text-n-slate-12">{{ resumo.esperando ?? 0 }}</b>
          </div>
          <div class="rounded-xl border border-n-weak px-3.5 py-3">
            <span class="block text-xs text-n-slate-10">{{ t(`${K}.RESUMO.FALHARAM`) }}</span>
            <b class="font-mono text-xl font-medium" :class="resumo.falharam_24h ? 'text-n-ruby-11' : 'text-n-slate-12'">
              {{ resumo.falharam_24h ?? 0 }}
            </b>
          </div>
        </div>

        <p v-if="!fluxos.length" class="text-sm text-n-slate-10">{{ t(`${K}.VAZIO`) }}</p>

        <table v-else class="w-full max-w-[1100px] border-collapse">
          <thead>
            <tr class="border-b border-n-weak text-left text-xs font-medium text-n-slate-10">
              <th class="w-11 p-2" />
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.FLUXO`) }}</th>
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.GATILHO`) }}</th>
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.HOJE_LIMITE`) }}</th>
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.ESPERANDO`) }}</th>
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.ULTIMA`) }}</th>
              <th class="p-2" />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="f in fluxos"
              :key="f.id"
              data-testid="fluxo-linha"
              class="cursor-pointer border-b border-n-weak text-[13.5px] hover:bg-n-alpha-2"
              @click="abrir(f.id)"
            >
              <td class="p-2" @click.stop>
                <span
                  :title="f.versao ? '' : t(`${K}.PUBLIQUE_ANTES`)"
                  :class="f.versao ? '' : 'pointer-events-none opacity-50'"
                >
                  <Switch :model-value="f.ativo" @update:model-value="v => ligar(f, v)" />
                </span>
              </td>
              <td class="p-2">
                <b class="block font-medium text-n-slate-12">{{ f.nome }}</b>
                <span class="text-[12.5px] text-n-slate-11">{{ subtitulo(f) }}</span>
              </td>
              <td class="p-2">
                <span class="inline-flex items-center gap-1.5 text-[12.5px] text-n-slate-11">
                  <i v-if="f.gatilho_tipo" :class="gatilhoInfo(f.gatilho_tipo)?.icone" class="size-3.5 text-n-blue-11" />
                  {{ gatilho(f.gatilho_tipo) }}
                </span>
              </td>
              <td class="p-2 font-mono text-[12.5px]">
                {{ hojeLimite(f) }}
                <span v-if="f.limite_dia" class="ml-1.5 inline-block h-[5px] w-14 overflow-hidden rounded-full bg-n-alpha-2 align-middle">
                  <i class="block h-full bg-n-blue-9" :style="{ width: largura(f) }" />
                </span>
              </td>
              <td class="p-2 font-mono text-[12.5px]">{{ f.esperando }}</td>
              <td class="p-2 font-mono text-[12.5px]">{{ ultima(f.ultima_em) }}</td>
              <td class="p-2">
                <span :class="[CHIP, selo(f).classe]" class="font-mono">
                  <i v-if="selo(f).icone" :class="selo(f).icone" class="size-3" />
                  {{ selo(f).texto }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>

    <NovoFluxo v-if="novo" @criar="criar" @fechar="novo = false" />
  </section>
</template>
```

- [ ] **Step 8: Rodar e ver passar + lint**

```bash
TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/Lista.spec.js
./node_modules/.bin/eslint --fix app/javascript/dashboard/routes/dashboard/captain/ app/javascript/dashboard/components-next/sidebar/Sidebar.vue
```
Expected: PASS (3); eslint sem erro além de `Delete ␍`.

- [ ] **Step 9: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/captain.routes.js app/javascript/dashboard/components-next/sidebar/Sidebar.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/Lista.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/NovoFluxo.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/Editor.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/Execucao.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/Lista.spec.js
git commit -m "feat(fluxos): lista de automações, novo fluxo e item no menu" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 9: O quadro — Vue Flow vertical, cartões, portas, paleta

Sem teste unitário de `Quadro`/`NoPasso` (o Vue Flow mede DOM; jsdom não tem layout) — a prova é o print do Task 13 e o roteiro de smoke. A lógica (portas, ligar, adicionar) já está testada no Task 3.

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/captain/automacoes/Quadro.vue`
- Create: `app/javascript/dashboard/routes/dashboard/captain/automacoes/NoPasso.vue`
- Create: `app/javascript/dashboard/routes/dashboard/captain/automacoes/Paleta.vue`

**Interfaces:**
- Consumes: `PASSOS`, `gatilhoInfo`, `saidasDe`, `PALETA` (Task 3); getters Vuex `leadConfig/getStages`, `inboxes/getInboxes`, `agents/getAgents`.
- Produces:
  - `Quadro` — `v-model:nodes`, `v-model:edges`; props `somenteLeitura: Boolean`, `selecionado: String|null`, `erros: Set`, `acesos: Set|null` (passos acesos; `null` = modo editor), `atual: String|null` (passo onde a execução espera); emite `selecionar(id|null)`, `conectar({source, sourceHandle, target, targetHandle})`.
  - `NoPasso` — props `id`, `tipo`, `config`, `estado: ''|'selecionado'|'erro'|'aceso'|'atual'|'apagado'`, `somenteLeitura`.
  - `Paleta` — emite `escolher({chave, tipo, config?})`, `fechar`.

- [ ] **Step 1: `NoPasso.vue`**

```vue
<script setup>
// Um passo no quadro (mockup .no): ícone colorido por categoria, título,
// detalhe, selo "sai como rascunho"; porta de entrada em cima e uma porta de
// saída por saída possível (sim/não, um por caso + outro) embaixo.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { Handle, Position } from '@vue-flow/core';
import { useMapGetter } from 'dashboard/composables/store';
import { CHIP, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { PASSOS, gatilhoInfo, saidasDe } from './fluxo';

const props = defineProps({
  id: { type: String, required: true },
  tipo: { type: String, required: true },
  config: { type: Object, default: () => ({}) },
  estado: { type: String, default: '' },
  somenteLeitura: { type: Boolean, default: false },
});

const K = 'CAPTAIN_RAMON.FLUXOS';
const { t } = useI18n();
const etapas = useMapGetter('leadConfig/getStages');
const caixas = useMapGetter('inboxes/getInboxes');

const MOLDURA = {
  '': 'border-n-weak hover:border-n-slate-8',
  selecionado: 'border-n-blue-9 ring-4 ring-n-blue-9/10',
  erro: 'border-n-ruby-9 ring-4 ring-n-ruby-9/10',
  aceso: 'border-n-teal-9',
  atual: 'border-n-amber-9 ring-4 ring-n-amber-9/10',
  apagado: 'border-n-weak opacity-40',
};
const PORTA = '!h-2.5 !w-2.5 !min-h-0 !min-w-0 !rounded-full !border-2 !border-n-slate-7 !bg-n-solid-1';

const gatilho = computed(() => props.tipo === 'gatilho');
const info = computed(() => PASSOS[props.tipo] || PASSOS.parar);
const icone = computed(() => (gatilho.value ? gatilhoInfo(props.config.tipo)?.icone || info.value.icone : info.value.icone));
const saidas = computed(() => saidasDe(props.tipo, props.config));
const titulo = computed(() => {
  if (props.config.rotulo) return props.config.rotulo;
  if (gatilho.value) return props.config.tipo ? t(`${K}.GATILHOS.${props.config.tipo}`) : t(`${K}.PASSOS.gatilho`);
  return t(`${K}.PASSOS.${props.tipo}`);
});

const nomes = (lista, ids, campo = 'name') =>
  lista.filter(x => (ids || []).includes(x.id)).map(x => x[campo]).join(', ');
const curto = texto => (texto && texto.length > 48 ? `${texto.slice(0, 47)}…` : texto || '');

const detalhe = computed(() => {
  const c = props.config;
  switch (props.tipo) {
    case 'gatilho':
      if (c.tipo === 'lead_mudou_etapa') {
        return c.para_etapa_ids?.length ? t(`${K}.NO.PARA`, { etapas: nomes(etapas.value, c.para_etapa_ids) }) : t(`${K}.NO.QUALQUER_ETAPA`);
      }
      return c.caixa_ids?.length ? t(`${K}.NO.CAIXAS`, { caixas: nomes(caixas.value, c.caixa_ids) }) : '';
    case 'se':
      return t(`${K}.NO.CONDICOES`, { n: (c.condicoes || []).length });
    case 'escolha':
      return c.campo ? t(`${K}.CAMPOS.${c.campo}`) : '';
    case 'mover_etapa':
      return nomes(etapas.value, [c.etapa_id]);
    case 'criar_tarefa':
      return curto(c.titulo);
    case 'esperar':
      return c.ate === 'horario_comercial' ? t(`${K}.PAINEL.ESPERAR_HORARIO`) : `${c.quantidade ?? ''} ${c.unidade ? t(`${K}.UNIDADES.${c.unidade}`) : ''}`;
    case 'acao_chatwoot':
      return (c.acoes || []).map(a => t(`${K}.ACOES_CHATWOOT.${a.action_name}`, a.action_name)).join(', ');
    case 'parar':
      return '';
    default:
      return curto(c.texto);
  }
});

const rotuloSaida = saida => {
  if (['sim', 'nao', 'outro'].includes(saida)) return t(`${K}.SAIDAS.${saida}`);
  return (props.config.casos || []).find(c => c.chave === saida)?.rotulo || saida;
};
</script>

<template>
  <div
    class="relative w-[212px] rounded-xl border bg-n-solid-1 px-3 py-2.5 shadow-sm"
    :class="[MOLDURA[estado], gatilho ? 'border-l-4 !border-l-n-blue-9' : '']"
    :data-testid="`no-${id}`"
  >
    <Handle
      v-if="!gatilho"
      id="e"
      type="target"
      :position="Position.Top"
      :connectable="!somenteLeitura"
      :class="PORTA"
    />
    <div class="mb-1.5 flex items-center gap-2 text-[11.5px] text-n-slate-10">
      <span class="grid size-6 shrink-0 place-items-center rounded-md" :class="TOM[info.tom]">
        <i :class="icone" class="size-3.5" />
      </span>
      {{ t(`${K}.CABECALHO.${tipo}`, tipo) }}
      <i v-if="estado === 'aceso'" class="i-lucide-check ml-auto size-3.5 text-n-teal-11" />
    </div>
    <b class="block text-[13.5px] font-medium leading-snug text-n-slate-12">{{ titulo }}</b>
    <span v-if="detalhe" class="mt-0.5 block truncate text-xs text-n-slate-11">{{ detalhe }}</span>
    <span v-if="info.rascunho" :class="[CHIP, TOM.amber]" class="mt-1.5 font-mono">
      {{ t(`${K}.NO.SAI_RASCUNHO`) }}
    </span>

    <div v-if="saidas.length" class="absolute inset-x-0 top-full flex justify-around">
      <div v-for="saida in saidas" :key="saida" class="flex flex-col items-center">
        <Handle
          :id="saida"
          type="source"
          :position="Position.Bottom"
          :connectable="!somenteLeitura"
          :class="PORTA"
          class="!static !-mt-[5px] !transform-none"
        />
        <span
          v-if="saidas.length > 1"
          class="mt-0.5 max-w-[64px] truncate font-mono text-[10.5px]"
          :class="estado === 'aceso' ? 'text-n-teal-11' : 'text-n-slate-10'"
        >
          {{ rotuloSaida(saida) }}
        </span>
      </div>
    </div>
  </div>
</template>
```

- [ ] **Step 2: `Quadro.vue`**

```vue
<script setup>
// Casca do Vue Flow (spec §7): fluxo de cima para baixo, minimapa, zoom e
// fundo pontilhado como o mockup. Editor = arrasta/liga/apaga; execução =
// só leitura com o caminho aceso (acesos != null).
import { useI18n } from 'vue-i18n';
import { VueFlow, Panel, useVueFlow } from '@vue-flow/core';
import { MiniMap } from '@vue-flow/minimap';
import '@vue-flow/core/dist/style.css';
import '@vue-flow/minimap/dist/style.css';
import Button from 'dashboard/components-next/button/Button.vue';
import NoPasso from './NoPasso.vue';

const props = defineProps({
  somenteLeitura: { type: Boolean, default: false },
  selecionado: { type: String, default: null },
  erros: { type: Object, default: () => new Set() },
  acesos: { type: Object, default: null },
  atual: { type: String, default: null },
});
const emit = defineEmits(['selecionar', 'conectar']);
const nodes = defineModel('nodes', { type: Array, required: true });
const edges = defineModel('edges', { type: Array, required: true });

const { t } = useI18n();
const { zoomIn, zoomOut, fitView } = useVueFlow();

const estado = id => {
  if (props.erros.has(id)) return 'erro';
  if (props.acesos) {
    if (id === props.atual) return 'atual';
    return props.acesos.has(id) ? 'aceso' : 'apagado';
  }
  return id === props.selecionado ? 'selecionado' : '';
};
</script>

<template>
  <VueFlow
    v-model:nodes="nodes"
    v-model:edges="edges"
    class="h-full bg-n-surface-2 [background-image:radial-gradient(rgb(var(--slate-6))_1.2px,transparent_1.2px)] [background-size:20px_20px] [&_.vue-flow\_\_edge-path]:stroke-n-slate-7 [&_.vue-flow\_\_edge-path]:[stroke-width:2] [&_.aceso_.vue-flow\_\_edge-path]:stroke-n-teal-9 [&_.aceso_.vue-flow\_\_edge-path]:[stroke-width:2.5] [&_.selected_.vue-flow\_\_edge-path]:stroke-n-blue-9"
    :nodes-draggable="!somenteLeitura"
    :nodes-connectable="!somenteLeitura"
    :elements-selectable="!somenteLeitura"
    :delete-key-code="somenteLeitura ? null : ['Backspace', 'Delete']"
    :min-zoom="0.4"
    :max-zoom="1.5"
    fit-view-on-init
    @connect="emit('conectar', $event)"
    @node-click="({ node }) => emit('selecionar', node.id)"
    @pane-click="emit('selecionar', null)"
  >
    <template #node-passo="{ id, data }">
      <NoPasso
        :id="id"
        :tipo="data.tipo"
        :config="data.config"
        :estado="estado(id)"
        :somente-leitura="somenteLeitura"
      />
    </template>
    <Panel
      position="bottom-left"
      class="flex gap-0.5 rounded-lg border border-n-weak bg-n-solid-1 p-0.5"
    >
      <Button ghost slate xs icon="i-lucide-zoom-in" :title="t('CAPTAIN_RAMON.FLUXOS.EDITOR.ZOOM_IN')" @click="zoomIn()" />
      <Button ghost slate xs icon="i-lucide-zoom-out" :title="t('CAPTAIN_RAMON.FLUXOS.EDITOR.ZOOM_OUT')" @click="zoomOut()" />
      <Button ghost slate xs icon="i-lucide-maximize" :title="t('CAPTAIN_RAMON.FLUXOS.EDITOR.AJUSTAR')" @click="fitView()" />
    </Panel>
    <MiniMap
      pannable
      zoomable
      node-class-name="fill-n-slate-6"
      class="overflow-hidden rounded-lg border border-n-weak !bg-n-solid-1 [&_.vue-flow\_\_minimap-mask]:fill-n-blue-9/10"
    />
  </VueFlow>
</template>
```
Notas para quem implementa:
- `vue-flow__edge-path` tem dois `_`: dentro de classe arbitrária do Tailwind o `_` vira espaço, por isso `\_\_` (escapado). Conferir no print que as setas aparecem (cinza) e, na execução, o caminho em teal. Se o Tailwind não gerar a classe, trocar por `[&_path.vue-flow\_\_edge-path]` ou mover o seletor para um `class` no próprio edge (`edges[].class`) — sem CSS escrito à mão.
- Se `zoomIn` não responder (o `useVueFlow()` chamado no mesmo componente que renderiza `<VueFlow>` precisa compartilhar o store): passar `id="quadro-fluxo"` no `<VueFlow>` e `useVueFlow('quadro-fluxo')`.
- Listeners do Vue Flow em kebab (`@node-click`, `@pane-click`) por causa da regra `vue/v-on-event-hyphenation`; os eventos emitidos por NÓS (`selecionar`, `conectar`) seguem camelCase.

- [ ] **Step 3: `Paleta.vue`**

```vue
<script setup>
// "+ Adicionar passo" (mockup .paleta): grupos com só o que a B1 executa.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onClickOutside } from '@vueuse/core';
import { MENU, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { PALETA, PASSOS } from './fluxo';

const emit = defineEmits(['escolher', 'fechar']);
const { t } = useI18n();
const raiz = ref(null);
onClickOutside(raiz, () => emit('fechar'));

const iconeDo = item => (item.chave === 'atribuir' ? 'i-lucide-user-check' : PASSOS[item.tipo].icone);
</script>

<template>
  <div
    ref="raiz"
    :class="MENU"
    class="absolute left-3.5 top-14 z-10 max-h-[calc(100%-120px)] w-[270px] overflow-y-auto"
    data-testid="fluxo-paleta"
  >
    <template v-for="grupo in PALETA" :key="grupo.grupo">
      <h4 class="mx-1.5 mb-1 mt-2.5 text-[11.5px] font-medium text-n-slate-10 first:mt-1">
        {{ t(`CAPTAIN_RAMON.FLUXOS.GRUPOS.${grupo.grupo}`) }}
      </h4>
      <button
        v-for="item in grupo.itens"
        :key="item.chave"
        type="button"
        class="flex w-full items-center gap-2.5 rounded-lg p-1.5 text-left text-[13px] text-n-slate-12 hover:bg-n-alpha-2"
        @click="emit('escolher', item)"
      >
        <span class="grid size-6 place-items-center rounded-md" :class="TOM[PASSOS[item.tipo].tom]">
          <i :class="iconeDo(item)" class="size-3.5" />
        </span>
        {{ t(`CAPTAIN_RAMON.FLUXOS.PALETA.${item.chave}`) }}
      </button>
    </template>
  </div>
</template>
```

- [ ] **Step 4: Lint**

Run: `./node_modules/.bin/eslint --fix app/javascript/dashboard/routes/dashboard/captain/automacoes/`
Expected: sem erro além de `Delete ␍`.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/Quadro.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/NoPasso.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/Paleta.vue
git commit -m "feat(fluxos): quadro vertical com passos, portas e paleta" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 10: Painel do passo — formulários reais por tipo

**Files:**
- Create: `…/automacoes/ListaMarcar.vue`, `CampoTexto.vue`, `ConfigGatilho.vue`, `ConfigCondicoes.vue`, `ConfigCasos.vue`, `ConfigAcoesChatwoot.vue`, `PainelPasso.vue`
- Test: `…/automacoes/specs/PainelPasso.spec.js`

**Interfaces:**
- Consumes: catálogo (Task 3); getters `leadConfig/getStages`, `leadConfig/getPriorities`, `agents/getAgents`, `inboxes/getInboxes`, `labels/getLabels`, `teams/getTeams`, `theses/getTheses`.
- Produces:
  - `PainelPasso` — props `no: {id, data: {tipo, config}}` (node do Vue Flow), `erros: string[]` (já traduzidos); emite `update:config(config)`, `duplicar()`, `excluir()`.
  - Subformulários: props `config: Object`; emitem `update:config(novaConfig)` (sempre objeto novo).
  - `ListaMarcar` — props `opcoes: Array<{id, nome}>`, `modelValue: Array`; emite `update:modelValue`.
  - `CampoTexto` — props `modelValue: String`, `rotulo: String`, `linhas: Number`; emite `update:modelValue`; fichas de `VARIAVEIS` inserem `{chave}` na posição do cursor.

- [ ] **Step 1: Escrever o teste**

`…/automacoes/specs/PainelPasso.spec.js`:

```js
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import PainelPasso from '../PainelPasso.vue';

const store = createStore({
  modules: {
    leadConfig: { namespaced: true, getters: { getStages: () => [{ id: 3, name: 'Contrato assinado' }], getPriorities: () => [] } },
    agents: { namespaced: true, getters: { getAgents: () => [{ id: 1, name: 'Ana' }] } },
    inboxes: { namespaced: true, getters: { getInboxes: () => [{ id: 7, name: 'WhatsApp' }] } },
    labels: { namespaced: true, getters: { getLabels: () => [{ id: 1, title: 'urgente' }] } },
    teams: { namespaced: true, getters: { getTeams: () => [{ id: 2, name: 'Comercial' }] } },
    theses: { namespaced: true, getters: { getTheses: () => [{ id: 1, name: 'BPC' }] } },
  },
});
const montar = no => mount(PainelPasso, { props: { no, erros: [] }, global: { plugins: [store] } });

describe('PainelPasso', () => {
  it('rascunho: avisa que sai como rascunho e edita o texto', async () => {
    const wrapper = montar({ id: 'n2', data: { tipo: 'rascunho_texto', config: { texto: 'Oi' } } });
    expect(wrapper.find('[data-testid="painel-aviso-rascunho"]').exists()).toBe(true);
    await wrapper.find('textarea').setValue('Olá');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([{ texto: 'Olá' }]);
  });

  it('clicar numa variável insere {chave} no cursor', async () => {
    const wrapper = montar({ id: 'n2', data: { tipo: 'nota_privada', config: { texto: 'Oi ' } } });
    const area = wrapper.find('textarea').element;
    area.setSelectionRange(3, 3);
    await wrapper.find('[data-testid="var-nome"]').trigger('click');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([{ texto: 'Oi {nome}' }]);
  });

  it('mover etapa usa as etapas do funil', async () => {
    const wrapper = montar({ id: 'n3', data: { tipo: 'mover_etapa', config: {} } });
    await wrapper.find('select').setValue('3');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([{ etapa_id: 3 }]);
  });

  it('gatilho não tem Duplicar/Excluir', () => {
    const wrapper = montar({ id: 'n1', data: { tipo: 'gatilho', config: { tipo: 'manual' } } });
    expect(wrapper.find('[data-testid="painel-excluir"]').exists()).toBe(false);
  });

  it('erros do passo aparecem no topo', () => {
    const wrapper = mount(PainelPasso, {
      props: { no: { id: 'n2', data: { tipo: 'nota_privada', config: {} } }, erros: ['Falta preencher o texto.'] },
      global: { plugins: [store] },
    });
    expect(wrapper.text()).toContain('Falta preencher o texto.');
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/PainelPasso.spec.js`
Expected: FAIL — `Failed to resolve import "../PainelPasso.vue"`.

- [ ] **Step 3: `ListaMarcar.vue`**

```vue
<script setup>
// Lista de caixinhas (caixas, etapas, pessoas, etiquetas, times).
import { CAMPO } from 'dashboard/routes/dashboard/ramon/helpers/ui';

const props = defineProps({
  opcoes: { type: Array, required: true },
  modelValue: { type: Array, default: () => [] },
});
const emit = defineEmits(['update:modelValue']);

const alterna = id =>
  emit('update:modelValue', props.modelValue.includes(id) ? props.modelValue.filter(x => x !== id) : [...props.modelValue, id]);
</script>

<template>
  <div :class="CAMPO" class="!h-auto max-h-40 overflow-y-auto py-1.5">
    <label v-for="opcao in opcoes" :key="opcao.id" class="flex items-center gap-2 py-0.5 text-sm text-n-slate-12">
      <input type="checkbox" class="reset-base" :checked="modelValue.includes(opcao.id)" @change="alterna(opcao.id)" />
      {{ opcao.nome }}
    </label>
  </div>
</template>
```

- [ ] **Step 4: `CampoTexto.vue`**

```vue
<script setup>
// Texto com variáveis clicáveis (mockup .vars): insere {chave} onde está o cursor.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { ROTULO, TEXTAREA } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { VARIAVEIS } from './fluxo';

const props = defineProps({
  modelValue: { type: String, default: '' },
  rotulo: { type: String, required: true },
  linhas: { type: Number, default: 4 },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const area = ref(null);
const fichas = VARIAVEIS.map(v => ({ v, texto: `{${v}}` }));

const inserir = token => {
  const el = area.value;
  const valor = props.modelValue || '';
  const inicio = el.selectionStart ?? valor.length;
  const fim = el.selectionEnd ?? valor.length;
  emit('update:modelValue', valor.slice(0, inicio) + token + valor.slice(fim));
};
</script>

<template>
  <label :class="ROTULO">
    {{ rotulo }}
    <textarea
      ref="area"
      :class="TEXTAREA"
      :rows="linhas"
      :value="modelValue"
      @input="emit('update:modelValue', $event.target.value)"
    />
  </label>
  <div class="mt-2 flex flex-wrap gap-1">
    <button
      v-for="ficha in fichas"
      :key="ficha.v"
      type="button"
      :data-testid="`var-${ficha.v}`"
      class="rounded-md bg-n-alpha-2 px-1.5 py-0.5 font-mono text-[11.5px] text-n-slate-11 hover:bg-n-blue-9/[0.08] hover:text-n-blue-11"
      @click="inserir(ficha.texto)"
    >
      {{ ficha.texto }}
    </button>
  </div>
  <p class="mt-1.5 text-xs text-n-slate-10">{{ t('CAPTAIN_RAMON.FLUXOS.PAINEL.VARIAVEIS_AJUDA') }}</p>
</template>
```

- [ ] **Step 5: `ConfigGatilho.vue`**

```vue
<script setup>
// Gatilho: quando roda + filtros que o Disparo.filtro_ok? da B1 entende
// (caixa_ids, de_etapa_ids, para_etapa_ids) + cancelar se sair da etapa.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import { ROTULO, SELECT } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { GATILHOS, gatilhoInfo } from './fluxo';
import ListaMarcar from './ListaMarcar.vue';

const props = defineProps({ config: { type: Object, required: true } });
const emit = defineEmits(['update:config']);
const K = 'CAPTAIN_RAMON.FLUXOS.PAINEL';
const { t } = useI18n();
const etapas = useMapGetter('leadConfig/getStages');
const caixas = useMapGetter('inboxes/getInboxes');

const opcoesEtapas = computed(() => etapas.value.map(e => ({ id: e.id, nome: e.name })));
const opcoesCaixas = computed(() => caixas.value.map(c => ({ id: c.id, nome: c.name })));
const alvo = computed(() => gatilhoInfo(props.config.tipo)?.alvo);
const cancelar = computed(() => props.config.cancelar_se_sair_da_etapa !== false);

const muda = (chave, valor) => emit('update:config', { ...props.config, [chave]: valor });
// trocar o tipo zera os filtros que não valem mais
const trocaTipo = tipo =>
  emit('update:config', {
    tipo,
    ...(props.config.rotulo ? { rotulo: props.config.rotulo } : {}),
    ...(props.config.cancelar_se_sair_da_etapa === false ? { cancelar_se_sair_da_etapa: false } : {}),
  });
</script>

<template>
  <div class="flex flex-col gap-4">
    <label :class="ROTULO">
      {{ t(`${K}.GATILHO_TIPO`) }}
      <select :class="SELECT" :value="config.tipo" @change="trocaTipo($event.target.value)">
        <option v-for="g in GATILHOS" :key="g.tipo" :value="g.tipo">
          {{ t(`CAPTAIN_RAMON.FLUXOS.GATILHOS.${g.tipo}`) }}
        </option>
      </select>
    </label>

    <div v-if="alvo === 'conversa'" :class="ROTULO">
      {{ t(`${K}.CAIXAS`) }}
      <ListaMarcar :opcoes="opcoesCaixas" :model-value="config.caixa_ids || []" @update:model-value="v => muda('caixa_ids', v)" />
      <span>{{ t(`${K}.CAIXAS_AJUDA`) }}</span>
    </div>

    <template v-if="config.tipo === 'lead_mudou_etapa'">
      <div :class="ROTULO">
        {{ t(`${K}.DE_ETAPAS`) }}
        <ListaMarcar :opcoes="opcoesEtapas" :model-value="config.de_etapa_ids || []" @update:model-value="v => muda('de_etapa_ids', v)" />
      </div>
      <div :class="ROTULO">
        {{ t(`${K}.PARA_ETAPAS`) }}
        <ListaMarcar :opcoes="opcoesEtapas" :model-value="config.para_etapa_ids || []" @update:model-value="v => muda('para_etapa_ids', v)" />
        <span>{{ t(`${K}.ETAPAS_AJUDA`) }}</span>
      </div>
    </template>

    <p v-if="config.tipo === 'manual'" class="text-xs text-n-slate-10">{{ t(`${K}.MANUAL_AJUDA`) }}</p>

    <div class="flex items-center justify-between border-t border-n-weak py-2 text-[13px] text-n-slate-12">
      {{ t(`${K}.CANCELAR_ETAPA`) }}
      <Switch :model-value="cancelar" @update:model-value="v => muda('cancelar_se_sair_da_etapa', v)" />
    </div>
  </div>
</template>
```

- [ ] **Step 6: `ConfigCondicoes.vue` (passo `se`)**

```vue
<script setup>
// Se: lista de condições com E/OU (Ramon::Fluxos::Condicao.teste). Valores
// comparam sem acento e sem caixa; as sugestões vêm do que existe no hub.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import { CAMPO, ROTULO, SELECT } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { CAMPOS, OPERADORES, SEM_VALOR } from './fluxo';

const props = defineProps({ config: { type: Object, required: true } });
const emit = defineEmits(['update:config']);
const K = 'CAPTAIN_RAMON.FLUXOS';
const { t } = useI18n();
const etapas = useMapGetter('leadConfig/getStages');
const teses = useMapGetter('theses/getTheses');
const caixas = useMapGetter('inboxes/getInboxes');
const pessoas = useMapGetter('agents/getAgents');
const etiquetas = useMapGetter('labels/getLabels');
const prioridades = useMapGetter('leadConfig/getPriorities');

const sugestoes = computed(() => ({
  etapa: etapas.value.map(x => x.name),
  tese: teses.value.map(x => x.name),
  caixa: caixas.value.map(x => x.name),
  responsavel: pessoas.value.map(x => x.name),
  etiquetas: etiquetas.value.map(x => x.title),
  prioridade: prioridades.value.map(x => x.name),
  status: ['open', 'resolved', 'pending', 'snoozed'],
}));
const condicoes = computed(() => props.config.condicoes || []);

const muda = (chave, valor) => emit('update:config', { ...props.config, [chave]: valor });
const mudaCondicao = (i, chave, valor) =>
  muda('condicoes', condicoes.value.map((c, j) => (j === i ? { ...c, [chave]: valor } : c)));
const adicionar = () => muda('condicoes', [...condicoes.value, { campo: 'etapa', operador: 'igual', valor: '' }]);
const remover = i => muda('condicoes', condicoes.value.filter((_c, j) => j !== i));
</script>

<template>
  <div class="flex flex-col gap-4">
    <label :class="ROTULO">
      {{ t(`${K}.PAINEL.JUNCAO`) }}
      <select :class="SELECT" :value="config.juncao || 'e'" @change="muda('juncao', $event.target.value)">
        <option value="e">{{ t(`${K}.PAINEL.JUNCAO_E`) }}</option>
        <option value="ou">{{ t(`${K}.PAINEL.JUNCAO_OU`) }}</option>
      </select>
    </label>

    <div v-for="(c, i) in condicoes" :key="i" class="flex flex-col gap-2 border-t border-n-weak pt-3">
      <div class="grid grid-cols-2 gap-2">
        <select :class="SELECT" :aria-label="t(`${K}.PAINEL.CAMPO`)" :value="c.campo" @change="mudaCondicao(i, 'campo', $event.target.value)">
          <option v-for="campo in CAMPOS" :key="campo" :value="campo">{{ t(`${K}.CAMPOS.${campo}`) }}</option>
        </select>
        <select :class="SELECT" :aria-label="t(`${K}.PAINEL.OPERADOR`)" :value="c.operador" @change="mudaCondicao(i, 'operador', $event.target.value)">
          <option v-for="op in OPERADORES" :key="op" :value="op">{{ t(`${K}.OPERADORES.${op}`) }}</option>
        </select>
      </div>
      <input
        v-if="!SEM_VALOR.includes(c.operador)"
        :class="CAMPO"
        :aria-label="t(`${K}.PAINEL.VALOR`)"
        :placeholder="t(`${K}.PAINEL.VALOR`)"
        :list="`sug-${i}`"
        :value="c.valor"
        @input="mudaCondicao(i, 'valor', $event.target.value)"
      />
      <datalist :id="`sug-${i}`">
        <option v-for="s in sugestoes[c.campo] || []" :key="s" :value="s" />
      </datalist>
      <Button class="self-end" link ruby xs :label="t(`${K}.PAINEL.REMOVER`)" @click="remover(i)" />
    </div>

    <Button class="self-start" faded slate xs icon="i-lucide-plus" :label="t(`${K}.PAINEL.ADD_CONDICAO`)" @click="adicionar" />
  </div>
</template>
```

- [ ] **Step 7: `ConfigCasos.vue` (passo `escolha`)**

```vue
<script setup>
// Escolha: um campo e uma saída por caso ({chave, rotulo, valores}) + "outro".
// Apagar um caso leva a seta junto (deVueFlow poda a porta que sumiu).
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { CAMPO, CHIP, ROTULO, SELECT, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { CAMPOS, novaChave } from './fluxo';

const props = defineProps({ config: { type: Object, required: true } });
const emit = defineEmits(['update:config']);
const K = 'CAPTAIN_RAMON.FLUXOS';
const { t } = useI18n();
const novos = ref({});

const casos = () => props.config.casos || [];
const muda = (chave, valor) => emit('update:config', { ...props.config, [chave]: valor });
const mudaCaso = (i, chave, valor) => muda('casos', casos().map((c, j) => (j === i ? { ...c, [chave]: valor } : c)));
const incluirValor = i => {
  const v = (novos.value[i] || '').trim();
  if (!v) return;
  mudaCaso(i, 'valores', [...(casos()[i].valores || []), v]);
  novos.value[i] = '';
};
const tirarValor = (i, v) => mudaCaso(i, 'valores', casos()[i].valores.filter(x => x !== v));
const adicionar = () => muda('casos', [...casos(), { chave: novaChave(casos()), rotulo: '', valores: [] }]);
const remover = i => muda('casos', casos().filter((_c, j) => j !== i));
</script>

<template>
  <div class="flex flex-col gap-4">
    <label :class="ROTULO">
      {{ t(`${K}.PAINEL.CAMPO_ESCOLHA`) }}
      <select :class="SELECT" :value="config.campo" @change="muda('campo', $event.target.value)">
        <option v-for="campo in CAMPOS" :key="campo" :value="campo">{{ t(`${K}.CAMPOS.${campo}`) }}</option>
      </select>
    </label>

    <div v-for="(caso, i) in config.casos || []" :key="caso.chave" class="flex flex-col gap-2 border-t border-n-weak pt-3">
      <label :class="ROTULO">
        {{ t(`${K}.PAINEL.ROTULO_CASO`) }}
        <input :class="CAMPO" :value="caso.rotulo" @input="mudaCaso(i, 'rotulo', $event.target.value)" />
      </label>
      <label :class="ROTULO">
        {{ t(`${K}.PAINEL.VALORES`) }}
        <input v-model="novos[i]" :class="CAMPO" @keydown.enter.prevent="incluirValor(i)" />
      </label>
      <div class="flex flex-wrap gap-1">
        <button v-for="v in caso.valores || []" :key="v" type="button" :class="[CHIP, TOM.slate]" @click="tirarValor(i, v)">
          {{ v }}
          <i class="i-lucide-x size-3" />
        </button>
      </div>
      <Button class="self-end" link ruby xs :label="t(`${K}.PAINEL.REMOVER`)" @click="remover(i)" />
    </div>

    <Button class="self-start" faded slate xs icon="i-lucide-plus" :label="t(`${K}.PAINEL.ADD_CASO`)" @click="adicionar" />
    <p class="text-xs text-n-slate-10">{{ t(`${K}.PAINEL.OUTRO_AJUDA`) }}</p>
  </div>
</template>
```

- [ ] **Step 8: `ConfigAcoesChatwoot.vue`**

```vue
<script setup>
// Ação da conversa = ações nativas das regras do Chatwoot (mesma execução,
// AcaoChatwootService). action_params no formato do ActionService.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import { ROTULO, SELECT, TEXTAREA } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { ACOES_CHATWOOT, PRIORIDADES } from './fluxo';
import ListaMarcar from './ListaMarcar.vue';

const props = defineProps({ config: { type: Object, required: true } });
const emit = defineEmits(['update:config']);
const K = 'CAPTAIN_RAMON.FLUXOS';
const { t } = useI18n();
const pessoas = useMapGetter('agents/getAgents');
const times = useMapGetter('teams/getTeams');
const etiquetas = useMapGetter('labels/getLabels');

const opcoesEtiquetas = computed(() => etiquetas.value.map(l => ({ id: l.title, nome: l.title })));
const opcoesTimes = computed(() => times.value.map(x => ({ id: x.id, nome: x.name })));
const acoes = computed(() => props.config.acoes || []);
const parametro = nome => ACOES_CHATWOOT.find(a => a.nome === nome)?.parametro;
const conhecida = nome => ACOES_CHATWOOT.some(a => a.nome === nome);

const salvar = lista => emit('update:config', { ...props.config, acoes: lista });
const mudaAcao = (i, mudanca) => salvar(acoes.value.map((a, j) => (j === i ? { ...a, ...mudanca } : a)));
const trocaNome = (i, nome) =>
  mudaAcao(i, { action_name: nome, action_params: parametro(nome) === 'email_time' ? [{ message: '', team_ids: [] }] : [] });
const adicionar = () => salvar([...acoes.value, { action_name: 'add_label', action_params: [] }]);
const remover = i => salvar(acoes.value.filter((_a, j) => j !== i));
const email = a => a.action_params?.[0] || { message: '', team_ids: [] };
</script>

<template>
  <div class="flex flex-col gap-4">
    <div v-for="(acao, i) in acoes" :key="i" class="flex flex-col gap-2 border-t border-n-weak pt-3 first:border-0 first:pt-0">
      <label :class="ROTULO">
        {{ t(`${K}.PAINEL.ACAO`) }}
        <select :class="SELECT" :value="acao.action_name" @change="trocaNome(i, $event.target.value)">
          <option v-if="!conhecida(acao.action_name)" :value="acao.action_name">{{ acao.action_name }}</option>
          <option v-for="a in ACOES_CHATWOOT" :key="a.nome" :value="a.nome">{{ t(`${K}.ACOES_CHATWOOT.${a.nome}`) }}</option>
        </select>
      </label>

      <div v-if="parametro(acao.action_name) === 'etiquetas'" :class="ROTULO">
        {{ t(`${K}.PAINEL.ETIQUETAS`) }}
        <ListaMarcar :opcoes="opcoesEtiquetas" :model-value="acao.action_params || []" @update:model-value="v => mudaAcao(i, { action_params: v })" />
      </div>
      <label v-else-if="parametro(acao.action_name) === 'pessoa'" :class="ROTULO">
        {{ t(`${K}.PAINEL.PESSOA`) }}
        <select :class="SELECT" :value="acao.action_params?.[0] ?? ''" @change="mudaAcao(i, { action_params: [Number($event.target.value)] })">
          <option value="" disabled>{{ t(`${K}.PAINEL.ESCOLHA`) }}</option>
          <option v-for="p in pessoas" :key="p.id" :value="p.id">{{ p.name }}</option>
        </select>
      </label>
      <label v-else-if="parametro(acao.action_name) === 'time'" :class="ROTULO">
        {{ t(`${K}.PAINEL.TIME`) }}
        <select :class="SELECT" :value="acao.action_params?.[0] ?? ''" @change="mudaAcao(i, { action_params: [Number($event.target.value)] })">
          <option value="" disabled>{{ t(`${K}.PAINEL.ESCOLHA`) }}</option>
          <option v-for="x in times" :key="x.id" :value="x.id">{{ x.name }}</option>
        </select>
      </label>
      <label v-else-if="parametro(acao.action_name) === 'prioridade'" :class="ROTULO">
        {{ t(`${K}.PAINEL.PRIORIDADE`) }}
        <select :class="SELECT" :value="acao.action_params?.[0] ?? ''" @change="mudaAcao(i, { action_params: [$event.target.value] })">
          <option value="" disabled>{{ t(`${K}.PAINEL.ESCOLHA`) }}</option>
          <option v-for="p in PRIORIDADES" :key="p" :value="p">{{ t(`${K}.PRIORIDADES.${p}`) }}</option>
        </select>
      </label>
      <template v-else-if="parametro(acao.action_name) === 'email_time'">
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.MENSAGEM_EMAIL`) }}
          <textarea :class="TEXTAREA" rows="3" :value="email(acao).message" @input="mudaAcao(i, { action_params: [{ ...email(acao), message: $event.target.value }] })" />
        </label>
        <div :class="ROTULO">
          {{ t(`${K}.PAINEL.TIMES`) }}
          <ListaMarcar :opcoes="opcoesTimes" :model-value="email(acao).team_ids" @update:model-value="v => mudaAcao(i, { action_params: [{ ...email(acao), team_ids: v }] })" />
        </div>
      </template>

      <Button class="self-end" link ruby xs :label="t(`${K}.PAINEL.REMOVER`)" @click="remover(i)" />
    </div>
    <Button class="self-start" faded slate xs icon="i-lucide-plus" :label="t(`${K}.PAINEL.ADD_ACAO`)" @click="adicionar" />
  </div>
</template>
```

- [ ] **Step 9: `PainelPasso.vue`**

```vue
<script setup>
// Painel direito do editor (mockup .painel): config do passo selecionado.
// Sempre emite config NOVA (o editor troca no node do Vue Flow).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import { AVISO, CAMPO, ROTULO, SELECT, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { PASSOS, TIPOS_TAREFA, UNIDADES, gatilhoInfo } from './fluxo';
import CampoTexto from './CampoTexto.vue';
import ConfigAcoesChatwoot from './ConfigAcoesChatwoot.vue';
import ConfigCasos from './ConfigCasos.vue';
import ConfigCondicoes from './ConfigCondicoes.vue';
import ConfigGatilho from './ConfigGatilho.vue';
import ListaMarcar from './ListaMarcar.vue';

const props = defineProps({
  no: { type: Object, required: true },
  erros: { type: Array, default: () => [] },
});
const emit = defineEmits(['update:config', 'duplicar', 'excluir']);
const K = 'CAPTAIN_RAMON.FLUXOS';
const { t } = useI18n();
const etapas = useMapGetter('leadConfig/getStages');
const pessoas = useMapGetter('agents/getAgents');

const tipo = computed(() => props.no.data.tipo);
const config = computed(() => props.no.data.config || {});
const info = computed(() => PASSOS[tipo.value] || PASSOS.parar);
const gatilho = computed(() => tipo.value === 'gatilho');
const icone = computed(() => (gatilho.value ? gatilhoInfo(config.value.tipo)?.icone || info.value.icone : info.value.icone));
const opcoesPessoas = computed(() => pessoas.value.map(p => ({ id: p.id, nome: p.name })));
const esperaHorario = computed(() => config.value.ate === 'horario_comercial');

const muda = (chave, valor) => emit('update:config', { ...config.value, [chave]: valor });
const numeroOuNada = v => (v === '' ? null : Number(v));
const modoEspera = horario =>
  emit('update:config', horario ? { rotulo: config.value.rotulo, ate: 'horario_comercial' } : { rotulo: config.value.rotulo, quantidade: 1, unidade: 'dias' });
</script>

<template>
  <div class="flex h-full min-h-0 flex-col">
    <div class="flex items-center gap-2.5 border-b border-n-weak px-4 py-3.5">
      <span class="grid size-7 place-items-center rounded-lg" :class="TOM[info.tom]">
        <i :class="icone" class="size-4" />
      </span>
      <div>
        <b class="block text-sm font-semibold text-n-slate-12">{{ t(`${K}.PASSOS.${tipo}`, tipo) }}</b>
        <span class="text-xs text-n-slate-10">
          {{ t(`${K}.CABECALHO.${tipo}`, tipo) }} · {{ t(`${K}.NO.PASSO_N`, { id: no.id }) }}
        </span>
      </div>
    </div>

    <div class="flex flex-1 flex-col gap-4 overflow-y-auto px-4 py-3.5">
      <div v-if="erros.length" :class="[AVISO, TOM.ruby]">
        <p v-for="e in erros" :key="e">{{ e }}</p>
      </div>
      <div v-if="info.rascunho" data-testid="painel-aviso-rascunho" :class="[AVISO, TOM.amber]" class="flex gap-2.5">
        <i class="i-lucide-shield-check mt-0.5 size-4 shrink-0" />
        <span class="text-n-slate-12">{{ t(`${K}.PAINEL.AVISO_RASCUNHO`) }}</span>
      </div>

      <label v-if="!gatilho" :class="ROTULO">
        {{ t(`${K}.PAINEL.ROTULO`) }}
        <input :class="CAMPO" :value="config.rotulo || ''" @input="muda('rotulo', $event.target.value)" />
      </label>

      <ConfigGatilho v-if="gatilho" :config="config" @update:config="c => emit('update:config', c)" />
      <ConfigCondicoes v-else-if="tipo === 'se'" :config="config" @update:config="c => emit('update:config', c)" />
      <ConfigCasos v-else-if="tipo === 'escolha'" :config="config" @update:config="c => emit('update:config', c)" />
      <ConfigAcoesChatwoot v-else-if="tipo === 'acao_chatwoot'" :config="config" @update:config="c => emit('update:config', c)" />

      <CampoTexto
        v-else-if="['rascunho_texto', 'nota_privada'].includes(tipo)"
        :rotulo="t(`${K}.PAINEL.TEXTO`)"
        :model-value="config.texto || ''"
        @update:model-value="v => muda('texto', v)"
      />

      <label v-else-if="tipo === 'mover_etapa'" :class="ROTULO">
        {{ t(`${K}.PAINEL.ETAPA`) }}
        <select :class="SELECT" :value="config.etapa_id ?? ''" @change="muda('etapa_id', Number($event.target.value))">
          <option value="" disabled>{{ t(`${K}.PAINEL.ESCOLHA_ETAPA`) }}</option>
          <option v-for="e in etapas" :key="e.id" :value="e.id">{{ e.name }}</option>
        </select>
      </label>

      <template v-else-if="tipo === 'criar_tarefa'">
        <CampoTexto :rotulo="t(`${K}.PAINEL.TITULO_TAREFA`)" :linhas="2" :model-value="config.titulo || ''" @update:model-value="v => muda('titulo', v)" />
        <div class="grid grid-cols-2 gap-2">
          <label :class="ROTULO">
            {{ t(`${K}.PAINEL.TIPO_TAREFA`) }}
            <select :class="SELECT" :value="config.tipo || 'other'" @change="muda('tipo', $event.target.value)">
              <option v-for="k in TIPOS_TAREFA" :key="k" :value="k">{{ t(`${K}.TIPOS_TAREFA.${k}`) }}</option>
            </select>
          </label>
          <label :class="ROTULO">
            {{ t(`${K}.PAINEL.PRAZO`) }}
            <input :class="CAMPO" type="number" min="0" :value="config.prazo_dias ?? 1" @change="muda('prazo_dias', Number($event.target.value))" />
          </label>
        </div>
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.RESPONSAVEL`) }}
          <select :class="SELECT" :value="config.responsavel_id ?? ''" @change="muda('responsavel_id', numeroOuNada($event.target.value))">
            <option value="">{{ t(`${K}.PAINEL.RESPONSAVEL_DO_LEAD`) }}</option>
            <option v-for="p in pessoas" :key="p.id" :value="p.id">{{ p.name }}</option>
          </select>
        </label>
      </template>

      <template v-else-if="tipo === 'avisar_sino'">
        <CampoTexto :rotulo="t(`${K}.PAINEL.TEXTO`)" :linhas="2" :model-value="config.texto || ''" @update:model-value="v => muda('texto', v)" />
        <div :class="ROTULO">
          {{ t(`${K}.PAINEL.QUEM_RECEBE`) }}
          <ListaMarcar :opcoes="opcoesPessoas" :model-value="config.user_ids || []" @update:model-value="v => muda('user_ids', v)" />
          <span>{{ t(`${K}.PAINEL.QUEM_RECEBE_AJUDA`) }}</span>
        </div>
      </template>

      <template v-else-if="tipo === 'avisar_push'">
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.TITULO_PUSH`) }}
          <input :class="CAMPO" :value="config.titulo || ''" @input="muda('titulo', $event.target.value)" />
        </label>
        <CampoTexto :rotulo="t(`${K}.PAINEL.TEXTO`)" :linhas="2" :model-value="config.texto || ''" @update:model-value="v => muda('texto', v)" />
      </template>

      <template v-else-if="tipo === 'esperar'">
        <div class="flex flex-col gap-1.5 text-[13px] text-n-slate-12">
          <label class="flex items-center gap-2">
            <input type="radio" class="reset-base" :checked="!esperaHorario" @change="modoEspera(false)" />
            {{ t(`${K}.PAINEL.ESPERAR_TEMPO`) }}
          </label>
          <label class="flex items-center gap-2">
            <input type="radio" class="reset-base" :checked="esperaHorario" @change="modoEspera(true)" />
            {{ t(`${K}.PAINEL.ESPERAR_HORARIO`) }}
          </label>
        </div>
        <div v-if="!esperaHorario" class="grid grid-cols-2 gap-2">
          <label :class="ROTULO">
            {{ t(`${K}.PAINEL.QUANTIDADE`) }}
            <input :class="CAMPO" type="number" min="1" :value="config.quantidade ?? 1" @change="muda('quantidade', Number($event.target.value))" />
          </label>
          <label :class="ROTULO">
            {{ t(`${K}.PAINEL.UNIDADE`) }}
            <select :class="SELECT" :value="config.unidade || 'dias'" @change="muda('unidade', $event.target.value)">
              <option v-for="u in UNIDADES" :key="u" :value="u">{{ t(`${K}.UNIDADES.${u}`) }}</option>
            </select>
          </label>
        </div>
        <p class="text-xs text-n-slate-10">{{ t(`${K}.PAINEL.ESPERAR_AJUDA`) }}</p>
      </template>

      <p v-else-if="tipo === 'parar'" class="text-xs text-n-slate-10">{{ t(`${K}.PAINEL.PARAR_AJUDA`) }}</p>
    </div>

    <div v-if="!gatilho" class="flex gap-2 border-t border-n-weak px-4 py-3">
      <Button outline slate sm icon="i-lucide-copy" :label="t(`${K}.PAINEL.DUPLICAR`)" @click="emit('duplicar')" />
      <Button data-testid="painel-excluir" outline ruby sm icon="i-lucide-trash-2" :label="t(`${K}.PAINEL.EXCLUIR`)" @click="emit('excluir')" />
    </div>
  </div>
</template>
```

- [ ] **Step 10: Rodar e ver passar + lint**

```bash
TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/PainelPasso.spec.js
./node_modules/.bin/eslint --fix app/javascript/dashboard/routes/dashboard/captain/automacoes/
```
Expected: PASS (5); eslint limpo (fora `Delete ␍`). `·` e `#` soltos no template são permitidos (allowlist do `vue/no-bare-strings-in-template` em `.eslintrc.js`).

- [ ] **Step 11: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/ListaMarcar.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/CampoTexto.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/ConfigGatilho.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/ConfigCondicoes.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/ConfigCasos.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/ConfigAcoesChatwoot.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/PainelPasso.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/PainelPasso.spec.js
git commit -m "feat(fluxos): painel de configuração de cada passo" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 11: Editor — barra, quadro, painel, versões, publicar, testar

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/captain/automacoes/TestarComLead.vue`
- Modify (substituir o stub inteiro): `app/javascript/dashboard/routes/dashboard/captain/automacoes/Editor.vue`

**Interfaces:**
- Consumes: `useFluxoEditor` (Task 6), `Quadro`, `Paleta` (Task 9), `PainelPasso` (Task 10), `ligar`, `adicionarPasso`, `duplicarPasso`, `trocarConfig`, `idDoErro`, `quando` (Task 3), `ConfirmModal` (`ramon/components/ConfirmModal.vue`: props `title`, `message`, `confirmLabel`; emite `confirm`, `cancel`), `LeadsAPI.get({ q })` (`api/leads.js` → array de leads `{id, name}`).
- Produces: `TestarComLead` — props `erros: string[]`, `ocupado: Boolean`, `podeRodar: Boolean`; emite `ensaiar(alvo)`, `rodar(alvo)`, `fechar`. `alvo` = `{ lead_id }` | `{ conversation_id }`. Editor aceita `?no=<id>` na query (passo já selecionado — usado na story).

- [ ] **Step 1: `TestarComLead.vue`**

```vue
<script setup>
// "Testar com um lead…": ensaio do rascunho num lead/conversa real (spec §6).
// Fluxo de gatilho manual, publicado e ligado também pode "Rodar de verdade".
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onKeyStroke, useDebounceFn } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import LeadsAPI from 'dashboard/api/leads';
import { ABA, ABA_ATIVA, ABA_INATIVA, AVISO, CAMPO, FUNDO_JANELA, JANELA, LINHA, RODAPE_JANELA, TITULO_JANELA, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';

defineProps({
  erros: { type: Array, default: () => [] },
  ocupado: { type: Boolean, default: false },
  podeRodar: { type: Boolean, default: false },
});
const emit = defineEmits(['ensaiar', 'rodar', 'fechar']);
const K = 'CAPTAIN_RAMON.FLUXOS.TESTAR';
const { t } = useI18n();
onKeyStroke('Escape', () => emit('fechar'));

const modo = ref('lead');
const busca = ref('');
const leads = ref([]);
const lead = ref(null);
const conversa = ref('');

const buscar = useDebounceFn(async () => {
  if (busca.value.trim().length < 2) {
    leads.value = [];
    return;
  }
  const { data } = await LeadsAPI.get({ q: busca.value.trim() });
  leads.value = data.slice(0, 8);
}, 300);

const alvo = computed(() => {
  if (modo.value === 'lead') return lead.value ? { lead_id: lead.value.id } : null;
  return conversa.value ? { conversation_id: Number(conversa.value) } : null;
});
</script>

<template>
  <div :class="FUNDO_JANELA" @click.self="emit('fechar')">
    <div :class="JANELA" class="!w-[28rem]">
      <h3 :class="TITULO_JANELA">{{ t(`${K}.TITULO`) }}</h3>
      <p class="mb-3 text-xs text-n-slate-11">{{ t(`${K}.AJUDA`) }}</p>
      <div class="mb-3 flex border-b border-n-weak">
        <button type="button" :class="[ABA, modo === 'lead' ? ABA_ATIVA : ABA_INATIVA]" @click="modo = 'lead'">{{ t(`${K}.LEAD`) }}</button>
        <button type="button" :class="[ABA, modo === 'conversa' ? ABA_ATIVA : ABA_INATIVA]" @click="modo = 'conversa'">{{ t(`${K}.CONVERSA`) }}</button>
      </div>

      <template v-if="modo === 'lead'">
        <input v-model="busca" :class="CAMPO" :placeholder="t(`${K}.BUSCAR`)" @input="buscar" />
        <div class="mt-2 flex max-h-56 flex-col overflow-y-auto">
          <button
            v-for="l in leads"
            :key="l.id"
            type="button"
            :class="[LINHA, lead?.id === l.id ? TOM.blue : '']"
            @click="lead = l"
          >
            {{ l.name }} <span class="font-mono text-xs text-n-slate-10">#{{ l.id }}</span>
          </button>
        </div>
      </template>
      <input v-else v-model="conversa" :class="CAMPO" type="number" min="1" :placeholder="t(`${K}.NUMERO_CONVERSA`)" />

      <div v-if="erros.length" :class="[AVISO, TOM.ruby]" class="mt-3">
        <p v-for="e in erros" :key="e">{{ e }}</p>
      </div>
      <p v-if="podeRodar" class="mt-3 text-xs text-n-slate-10">{{ t(`${K}.RODAR_AJUDA`) }}</p>

      <div :class="RODAPE_JANELA">
        <Button slate faded sm :label="t(`${K}.CANCELAR`)" @click="emit('fechar')" />
        <Button v-if="podeRodar" amber outline sm :label="t(`${K}.RODAR`)" :disabled="!alvo || ocupado" @click="emit('rodar', alvo)" />
        <Button sm icon="i-lucide-flask-conical" :label="t(`${K}.ENSAIAR`)" :is-loading="ocupado" :disabled="!alvo" @click="emit('ensaiar', alvo)" />
      </div>
    </div>
  </div>
</template>
```

- [ ] **Step 2: `Editor.vue` (substituir o stub)**

```vue
<script setup>
// Editor de um fluxo (B2, mockup tela 2): barra (Ligado + limite, Versões,
// Testar com um lead…, Publicar vN), quadro vertical, paleta e painel do passo.
// Sem passo selecionado, o painel mostra as execuções recentes do fluxo.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onBeforeRouteLeave, useRoute, useRouter } from 'vue-router';
import { onClickOutside } from '@vueuse/core';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { dynamicTime } from 'shared/helpers/timeHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import ConfirmModal from 'dashboard/routes/dashboard/ramon/components/ConfirmModal.vue';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import { AVISO, CAMPO, CHIP, LINHA, MENU, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { adicionarPasso, duplicarPasso, idDoErro, ligar, quando, trocarConfig } from './fluxo';
import { useFluxoEditor } from './useFluxoEditor';
import Quadro from './Quadro.vue';
import Paleta from './Paleta.vue';
import PainelPasso from './PainelPasso.vue';
import TestarComLead from './TestarComLead.vue';

defineOptions({ name: 'CaptainAutomacaoEditor' });

const K = 'CAPTAIN_RAMON.FLUXOS';
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { accountScopedRoute } = useAccount();
const etapas = useMapGetter('leadConfig/getStages');
const pessoas = useMapGetter('agents/getAgents');
const teses = useMapGetter('theses/getTheses');

const {
  fluxo,
  nodes,
  edges,
  salvando,
  errosFront,
  errosServidor,
  mostrarErros,
  nosComErro,
  carregar,
  salvar,
  atualizar,
  publicar,
  ensaiar,
  rodar,
} = useFluxoEditor();

const selecionado = ref(route.query.no || null);
const paleta = ref(false);
const versoesAbertas = ref(false);
const versoesRef = ref(null);
const testando = ref(false);
const ocupadoTeste = ref(false);
const errosTeste = ref([]);
const excluindo = ref(false);
const execucoes = ref([]);
const publicando = ref(false);
onClickOutside(versoesRef, () => {
  versoesAbertas.value = false;
});

const fluxoId = computed(() => Number(route.params.fluxoId));
const carregarExecucoes = async () => {
  const { data } = await RamonFluxosAPI.execucoes(fluxoId.value);
  execucoes.value = data.payload.slice(0, 20);
};

onMounted(async () => {
  if (!etapas.value.length) store.dispatch('leadConfig/get');
  if (!pessoas.value.length) store.dispatch('agents/get');
  if (!teses.value.length) store.dispatch('theses/get');
  await carregar(fluxoId.value);
  carregarExecucoes();
});
onBeforeRouteLeave(() => salvar());

const noSelecionado = computed(() => nodes.value.find(n => n.id === selecionado.value) || null);

const textoErro = e =>
  e.codigo === 'FALTA'
    ? t(`${K}.ERROS.FALTA`, { campo: t(`${K}.CAMPOS_OBRIGATORIOS.${e.params.campo}`) })
    : t(`${K}.ERROS.${e.codigo}`, e.params);
const errosDoNo = computed(() => {
  if (!noSelecionado.value) return [];
  const id = noSelecionado.value.id;
  return [
    ...(mostrarErros.value ? errosFront.value.filter(e => e.no === id).map(textoErro) : []),
    ...errosServidor.value.filter(m => idDoErro(m) === id),
  ];
});
const errosGerais = computed(() => [
  ...(mostrarErros.value ? errosFront.value.filter(e => !e.no).map(textoErro) : []),
  ...errosServidor.value.filter(m => !idDoErro(m)),
]);

// quadro
const conectar = conexao => {
  const novas = ligar(edges.value, conexao);
  if (novas) edges.value = novas;
};
const adicionar = item => {
  const r = adicionarPasso(nodes.value, edges.value, item, selecionado.value);
  nodes.value = r.nodes;
  edges.value = r.edges;
  selecionado.value = r.id;
  paleta.value = false;
};
const mudarConfig = config => {
  nodes.value = trocarConfig(nodes.value, selecionado.value, config);
};
const duplicar = () => {
  const r = duplicarPasso(nodes.value, selecionado.value);
  nodes.value = r.nodes;
  selecionado.value = r.id;
};
const excluirPasso = () => {
  const id = selecionado.value;
  nodes.value = nodes.value.filter(n => n.id !== id);
  edges.value = edges.value.filter(e => e.source !== id && e.target !== id);
  selecionado.value = null;
};

// barra
const seloRascunho = computed(() =>
  fluxo.value?.versao ? t(`${K}.EDITOR.SELO_PUBLICADA`, { versao: fluxo.value.versao }) : t(`${K}.EDITOR.SELO_NUNCA`)
);
const salvarSeguro = async attrs => {
  try {
    await atualizar(attrs);
  } catch (e) {
    useAlert(t(`${K}.EDITOR.ERRO_SALVAR`));
  }
};
const mudarLimite = valor => salvarSeguro({ limite_dia: valor ? Number(valor) : null });
const mudarNome = nome => nome.trim() && salvarSeguro({ nome: nome.trim() });
const clicarPublicar = async () => {
  publicando.value = true;
  try {
    const versao = await publicar();
    if (versao) useAlert(t(`${K}.EDITOR.PUBLICADO`, { versao }));
  } catch (e) {
    useAlert(t(`${K}.EDITOR.ERRO_SALVAR`));
  } finally {
    publicando.value = false;
  }
};

// testar
const podeRodar = computed(() => fluxo.value?.gatilho_tipo === 'manual' && Boolean(fluxo.value?.versao) && fluxo.value?.ativo);
const abrirExecucao = execId =>
  router.push(accountScopedRoute('captain_automacoes_execucao', { fluxoId: fluxoId.value, execId }));
const testar = async (acao, alvo) => {
  ocupadoTeste.value = true;
  errosTeste.value = [];
  try {
    const exec = acao === 'rodar' ? await rodar(alvo) : await ensaiar(alvo);
    abrirExecucao(exec.id);
  } catch (e) {
    const dados = e.response?.data || {};
    if (dados.erro === 'FLUXO_NAO_RODOU') errosTeste.value = [t(`${K}.TESTAR.NAO_RODOU`)];
    else errosTeste.value = dados.erros || [t(`${K}.TESTAR.ERRO`)];
  } finally {
    ocupadoTeste.value = false;
  }
};

const excluirFluxo = async () => {
  await RamonFluxosAPI.delete(fluxoId.value);
  router.push(accountScopedRoute('captain_automacoes_index'));
};

const corStatus = { concluida: TOM.teal, esperando: TOM.amber, falhou: TOM.ruby, cancelada: TOM.slate, rodando: TOM.blue };
const haQuanto = iso => dynamicTime(Math.floor(new Date(iso).getTime() / 1000));
</script>

<template>
  <section class="flex flex-col w-full h-full bg-n-surface-1">
    <div class="flex h-14 shrink-0 items-center gap-2.5 border-b border-n-weak pl-5 pr-4">
      <router-link
        :to="accountScopedRoute('captain_automacoes_index')"
        class="flex items-center gap-1 text-[13px] text-n-slate-10 hover:text-n-slate-12"
      >
        <i class="i-lucide-chevron-left size-4" />
        {{ t(`${K}.EDITOR.VOLTAR`) }}
      </router-link>
      <template v-if="fluxo">
        <input
          class="reset-base min-w-0 max-w-xs flex-1 bg-transparent text-[15px] font-semibold text-n-slate-12 outline-none"
          :aria-label="t(`${K}.EDITOR.NOME`)"
          :value="fluxo.nome"
          @change="mudarNome($event.target.value)"
        />
        <span :class="[CHIP, TOM.slate]" class="font-mono">
          {{ salvando ? t(`${K}.EDITOR.SALVANDO`) : seloRascunho }}
        </span>

        <div class="ml-auto flex items-center gap-2">
          <span class="flex items-center gap-2 border-r border-n-weak pr-2.5 text-[12.5px] text-n-slate-11">
            <span :title="fluxo.versao ? '' : t(`${K}.PUBLIQUE_ANTES`)" :class="fluxo.versao ? '' : 'pointer-events-none opacity-50'">
              <Switch :model-value="fluxo.ativo" @update:model-value="v => salvarSeguro({ ativo: v })" />
            </span>
            {{ t(`${K}.EDITOR.LIGADO`) }} · {{ t(`${K}.EDITOR.LIMITE`) }}
            <input
              :class="CAMPO"
              class="!h-7 !w-14 !px-1.5 text-center"
              type="number"
              min="1"
              :value="fluxo.limite_dia ?? ''"
              @change="mudarLimite($event.target.value)"
            />
            {{ t(`${K}.EDITOR.POR_DIA`) }}
          </span>
          <div ref="versoesRef" class="relative">
            <Button outline slate sm icon="i-lucide-history" :label="t(`${K}.EDITOR.VERSOES`)" @click="versoesAbertas = !versoesAbertas" />
            <div v-if="versoesAbertas" :class="MENU" class="absolute right-0 top-full z-20 mt-1 w-56">
              <p v-if="!fluxo.versoes?.length" class="p-2 text-xs text-n-slate-10">{{ t(`${K}.EDITOR.SEM_VERSOES`) }}</p>
              <div v-for="v in fluxo.versoes" :key="v.numero" class="flex items-center justify-between px-2 py-1.5 text-[13px] text-n-slate-12">
                {{ t(`${K}.EDITOR.VERSAO_ITEM`, { numero: v.numero, data: quando(v.created_at) }) }}
                <span v-if="v.numero === fluxo.versao" :class="[CHIP, TOM.teal]">{{ t(`${K}.EDITOR.NO_AR`) }}</span>
              </div>
            </div>
          </div>
          <Button outline slate sm icon="i-lucide-flask-conical" :label="t(`${K}.EDITOR.TESTAR`)" @click="testando = true" />
          <Button
            sm
            icon="i-lucide-upload"
            :label="t(`${K}.EDITOR.PUBLICAR`, { versao: (fluxo.versao || 0) + 1 })"
            :is-loading="publicando"
            @click="clicarPublicar"
          />
          <Button ghost ruby sm icon="i-lucide-trash-2" :title="t(`${K}.EDITOR.EXCLUIR_FLUXO`)" @click="excluindo = true" />
        </div>
      </template>
    </div>

    <div class="flex min-h-0 flex-1">
      <div class="relative min-w-0 flex-1">
        <Quadro
          v-if="fluxo"
          v-model:nodes="nodes"
          v-model:edges="edges"
          :selecionado="selecionado"
          :erros="nosComErro"
          @selecionar="id => (selecionado = id)"
          @conectar="conectar"
        />
        <Button
          class="!absolute left-3.5 top-3.5 z-10"
          faded
          blue
          sm
          icon="i-lucide-plus"
          :label="t(`${K}.EDITOR.ADICIONAR`)"
          @click="paleta = true"
        />
        <Paleta v-if="paleta" @escolher="adicionar" @fechar="paleta = false" />
        <div
          v-if="errosGerais.length || (mostrarErros && nosComErro.size)"
          :class="[AVISO, TOM.ruby]"
          class="absolute left-1/2 top-3.5 z-10 max-w-lg -translate-x-1/2 shadow-sm"
          data-testid="editor-erros"
        >
          <b class="block">{{ t(`${K}.EDITOR.ERROS_TITULO`) }}</b>
          <p v-for="e in errosGerais" :key="e">{{ e }}</p>
          <p v-if="nosComErro.size">{{ t(`${K}.EDITOR.ERROS_NOS`, { n: nosComErro.size }) }}</p>
        </div>
      </div>

      <aside class="flex w-[340px] shrink-0 flex-col border-l border-n-weak bg-n-solid-1">
        <PainelPasso
          v-if="noSelecionado"
          :key="noSelecionado.id"
          :no="noSelecionado"
          :erros="errosDoNo"
          @update:config="mudarConfig"
          @duplicar="duplicar"
          @excluir="excluirPasso"
        />
        <div v-else class="flex min-h-0 flex-1 flex-col px-4 py-3.5">
          <p class="mb-3 text-xs text-n-slate-10">{{ t(`${K}.EDITOR.SELECIONE`) }}</p>
          <h4 class="mb-2 text-[11px] font-medium uppercase tracking-wider text-n-slate-10">{{ t(`${K}.EDITOR.EXECUCOES`) }}</h4>
          <p v-if="!execucoes.length" class="text-xs text-n-slate-10">{{ t(`${K}.EDITOR.SEM_EXECUCOES`) }}</p>
          <div class="flex flex-col overflow-y-auto">
            <button
              v-for="ex in execucoes"
              :key="ex.id"
              type="button"
              :class="LINHA"
              class="flex items-center gap-2"
              @click="abrirExecucao(ex.id)"
            >
              <span :class="[CHIP, corStatus[ex.status]]">{{ t(`${K}.STATUS.${ex.status}`) }}</span>
              <span class="min-w-0 flex-1 truncate">{{ ex.alvo_nome }}</span>
              <span v-if="ex.ensaio" class="font-mono text-[10.5px] text-n-slate-10">{{ t(`${K}.EXECUCAO.ENSAIO`) }}</span>
              <span class="font-mono text-[11px] text-n-slate-10">{{ haQuanto(ex.created_at) }}</span>
            </button>
          </div>
        </div>
      </aside>
    </div>

    <TestarComLead
      v-if="testando"
      :erros="errosTeste"
      :ocupado="ocupadoTeste"
      :pode-rodar="podeRodar"
      @ensaiar="alvo => testar('ensaiar', alvo)"
      @rodar="alvo => testar('rodar', alvo)"
      @fechar="testando = false"
    />
    <ConfirmModal
      v-if="excluindo"
      :title="t(`${K}.EDITOR.EXCLUIR_TITULO`)"
      :message="t(`${K}.EDITOR.EXCLUIR_MSG`)"
      :confirm-label="t(`${K}.EDITOR.EXCLUIR_FLUXO`)"
      @confirm="excluirFluxo"
      @cancel="excluindo = false"
    />
  </section>
</template>
```

Notas:
- `·` entre `LIGADO` e `LIMITE` é permitido pelo allowlist do eslint (`·`).
- "Adicionar passo" só ABRE a paleta (`paleta = true`): ela fecha sozinha no clique fora (`onClickOutside`); um toggle a reabriria no mesmo clique.
- O ensaio usa o rascunho SALVO (`ensaiar` faz `await salvar()`); erros de desenho voltam do back como `{erros: [...]}` e aparecem no modal.

- [ ] **Step 3: Rodar a suíte da pasta + lint**

```bash
TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/captain/automacoes
./node_modules/.bin/eslint --fix app/javascript/dashboard/routes/dashboard/captain/automacoes/
```
Expected: todos PASS; eslint limpo (fora `Delete ␍`).

- [ ] **Step 4: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/Editor.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/TestarComLead.vue
git commit -m "feat(fluxos): editor do fluxo com publicar, versões e ensaio" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 12: Execução / ensaio — caminho aceso + trilha

**Files:**
- Modify (substituir o stub inteiro): `app/javascript/dashboard/routes/dashboard/captain/automacoes/Execucao.vue`
- Test: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/Execucao.spec.js`

**Interfaces:**
- Consumes: `RamonFluxosAPI.show`, `RamonFluxosAPI.execucao` (Task 2 — traz `grafo`), `paraVueFlow`, `caminhoAceso`, `quando`, `PASSOS` (Task 3), `Quadro` (Task 9).
- Produces: tela da rota `captain_automacoes_execucao`.

- [ ] **Step 1: Escrever o teste (trilha e alvo; o quadro é stub)**

`…/automacoes/specs/Execucao.spec.js`:

```js
import { mount, flushPromises } from '@vue/test-utils';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import Execucao from '../Execucao.vue';

const push = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { fluxoId: '1', execId: '412' } }),
  useRouter: () => ({ push }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: (name, params) => ({ name, params }) }),
}));
vi.mock('dashboard/composables/store', () => ({ useStore: () => ({ dispatch: vi.fn() }) }));
vi.mock('dashboard/api/ramonFluxos', () => ({ default: { show: vi.fn(), execucao: vi.fn() } }));

const GRAFO = {
  nos: [
    { id: 'n1', tipo: 'gatilho', config: { tipo: 'manual' }, posicao: { x: 0, y: 0 } },
    { id: 'n2', tipo: 'nota_privada', config: { texto: 'oi', rotulo: 'Aviso' }, posicao: { x: 0, y: 140 } },
  ],
  setas: [{ de: 'n1', saida: 's', para: 'n2' }],
};

describe('Execução de fluxo', () => {
  beforeEach(() => {
    RamonFluxosAPI.show.mockResolvedValue({ data: { id: 1, nome: 'Pós-contrato' } });
    RamonFluxosAPI.execucao.mockResolvedValue({
      data: {
        id: 412,
        versao: 3,
        status: 'concluida',
        ensaio: true,
        alvo_type: 'Lead',
        alvo_id: 231,
        alvo_nome: 'Maria da Silva',
        lead_id: 231,
        conversation_display_id: 1802,
        created_at: '2026-10-02T17:31:00Z',
        updated_at: '2026-10-04T17:32:00Z',
        trilha: [
          { no: 'n1', tipo: 'gatilho', em: '2026-10-02T17:31:00Z', saida: 's', resumo: 'manual', erro: false },
          { no: 'n2', tipo: 'nota_privada', em: '2026-10-02T17:31:02Z', saida: 's', resumo: 'faria: nota "oi"', erro: false },
        ],
        grafo: GRAFO,
      },
    });
  });

  it('mostra alvo, a trilha com o nome do passo e o resumo', async () => {
    const wrapper = mount(Execucao, { global: { stubs: { Quadro: true } } });
    await flushPromises();
    expect(wrapper.text()).toContain('Maria da Silva');
    expect(wrapper.findAll('[data-testid="trilha-item"]')).toHaveLength(2);
    expect(wrapper.text()).toContain('Aviso');
    expect(wrapper.text()).toContain('faria: nota "oi"');
    expect(wrapper.text()).toContain('dry run');
  });

  it('"Voltar a editar" abre o editor do fluxo', async () => {
    const wrapper = mount(Execucao, { global: { stubs: { Quadro: true } } });
    await flushPromises();
    await wrapper.find('[data-testid="voltar-editar"]').trigger('click');
    expect(push).toHaveBeenCalledWith({ name: 'captain_automacoes_editor', params: { fluxoId: 1 } });
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/Execucao.spec.js`
Expected: FAIL — o stub não tem `trilha-item`.

- [ ] **Step 3: Implementar `Execucao.vue`**

```vue
<script setup>
// Execução / ensaio (B2, mockup tela 3): o desenho EM QUE a execução rodou,
// só leitura, caminho aceso (teal), passo onde espera em âmbar, erro em ruby;
// à direita o alvo e a trilha com horários.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import { AVISO, CHIP, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { PASSOS, caminhoAceso, paraVueFlow, quando } from './fluxo';
import Quadro from './Quadro.vue';

defineOptions({ name: 'CaptainAutomacaoExecucao' });

const K = 'CAPTAIN_RAMON.FLUXOS';
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { accountScopedRoute } = useAccount();

const fluxo = ref(null);
const exec = ref(null);
const erro = ref(false);
const nodes = ref([]);
const edges = ref([]);

const fluxoId = computed(() => Number(route.params.fluxoId));
const caminho = computed(() => caminhoAceso(exec.value?.trilha, exec.value?.grafo));
const errosTrilha = computed(() => new Set((exec.value?.trilha || []).filter(l => l.erro).map(l => l.no)));
const atual = computed(() => (exec.value?.status === 'esperando' ? exec.value.no_atual : null));

onMounted(async () => {
  try {
    const [f, e] = await Promise.all([RamonFluxosAPI.show(fluxoId.value), RamonFluxosAPI.execucao(fluxoId.value, route.params.execId)]);
    fluxo.value = f.data;
    exec.value = e.data;
    const vf = paraVueFlow(e.data.grafo);
    const acesas = caminhoAceso(e.data.trilha, e.data.grafo).setas;
    nodes.value = vf.nodes;
    edges.value = vf.edges.map(ed => (acesas.has(ed.id) ? { ...ed, class: 'aceso' } : ed));
  } catch (err) {
    erro.value = true;
  }
});

const COR_STATUS = { concluida: TOM.teal, esperando: TOM.amber, falhou: TOM.ruby, cancelada: TOM.slate, rodando: TOM.blue };
const noDe = id => (exec.value?.grafo?.nos || []).find(n => n.id === id);
const tituloLinha = linha => {
  if (linha.no === 'cancelado') return t(`${K}.EXECUCAO.CANCELADO`);
  const no = noDe(linha.no);
  if (no?.config?.rotulo) return no.config.rotulo;
  if (linha.tipo === 'gatilho') return t(`${K}.GATILHOS.${no?.config?.tipo}`, t(`${K}.PASSOS.gatilho`));
  return PASSOS[linha.tipo] ? t(`${K}.PASSOS.${linha.tipo}`) : linha.tipo;
};
const corLinha = linha => {
  if (linha.erro) return 'bg-n-ruby-9';
  if (linha.no === 'cancelado') return 'bg-n-slate-8';
  if (linha.tipo === 'esperar') return 'bg-n-amber-9';
  return 'bg-n-teal-9';
};
const iniciais = nome =>
  (nome || '?')
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map(p => p[0].toUpperCase())
    .join('');
const intervalo = computed(() =>
  t(`${K}.EXECUCAO.INTERVALO`, {
    versao: exec.value.versao ? t(`${K}.EXECUCAO.VERSAO`, { versao: exec.value.versao }) : t(`${K}.EXECUCAO.RASCUNHO`),
    inicio: quando(exec.value.created_at),
    fim: quando(exec.value.updated_at),
  })
);

const voltarEditar = () => router.push(accountScopedRoute('captain_automacoes_editor', { fluxoId: fluxoId.value }));
const abrirAlvo = () => {
  if (exec.value.lead_id) {
    router.push(accountScopedRoute('ramon_funil'));
    store.dispatch('leads/select', exec.value.lead_id);
  } else {
    router.push(accountScopedRoute('inbox_conversation', { conversation_id: exec.value.conversation_display_id }));
  }
};
const verConversa = () =>
  router.push(accountScopedRoute('inbox_conversation', { conversation_id: exec.value.conversation_display_id }));
</script>

<template>
  <section class="flex flex-col w-full h-full bg-n-surface-1">
    <div class="flex h-14 shrink-0 items-center gap-2.5 border-b border-n-weak pl-5 pr-4">
      <button type="button" class="flex items-center gap-1 text-[13px] text-n-slate-10 hover:text-n-slate-12" @click="voltarEditar">
        <i class="i-lucide-chevron-left size-4" />
        {{ fluxo?.nome }}
      </button>
      <template v-if="exec">
        <h1 class="text-[15px] font-semibold text-n-slate-12">{{ t(`${K}.EXECUCAO.TITULO`, { id: exec.id }) }}</h1>
        <span :class="[CHIP, COR_STATUS[exec.status]]" class="font-mono">{{ t(`${K}.STATUS.${exec.status}`) }}</span>
        <span v-if="exec.ensaio" :class="[CHIP, TOM.iris]" class="font-mono">{{ t(`${K}.EXECUCAO.ENSAIO`) }}</span>
      </template>
      <Button
        class="ml-auto"
        data-testid="voltar-editar"
        outline
        slate
        sm
        icon="i-lucide-pencil"
        :label="t(`${K}.EXECUCAO.VOLTAR_EDITAR`)"
        @click="voltarEditar"
      />
    </div>

    <p v-if="erro" class="p-6 text-sm text-n-ruby-11">{{ t(`${K}.EXECUCAO.NAO_ACHEI`) }}</p>

    <div v-else-if="exec" class="flex min-h-0 flex-1">
      <div class="relative min-w-0 flex-1">
        <Quadro
          v-model:nodes="nodes"
          v-model:edges="edges"
          somente-leitura
          :acesos="caminho.nos"
          :atual="atual"
          :erros="errosTrilha"
        />
      </div>

      <aside class="flex w-[340px] shrink-0 flex-col border-l border-n-weak bg-n-solid-1">
        <div class="flex items-center gap-2.5 border-b border-n-weak px-4 py-3.5">
          <span class="grid size-7 place-items-center rounded-lg" :class="TOM.teal"><i class="i-lucide-route size-4" /></span>
          <div>
            <b class="block text-sm font-semibold text-n-slate-12">{{ t(`${K}.EXECUCAO.CAMINHO`) }}</b>
            <span class="font-mono text-xs text-n-slate-10">{{ intervalo }}</span>
          </div>
        </div>

        <div class="flex-1 overflow-y-auto px-4 py-3.5">
          <div class="mb-4 flex items-center gap-2.5 rounded-xl border border-n-weak px-3 py-2.5">
            <span class="grid size-7 place-items-center rounded-full bg-n-alpha-2 text-[11px] font-semibold text-n-slate-12">
              {{ iniciais(exec.alvo_nome) }}
            </span>
            <div class="min-w-0">
              <b class="block truncate text-[13.5px] font-medium text-n-slate-12">{{ exec.alvo_nome }}</b>
              <span class="text-xs text-n-slate-11">
                {{
                  exec.lead_id
                    ? t(`${K}.EXECUCAO.LEAD_N`, { id: exec.lead_id })
                    : t(`${K}.EXECUCAO.CONVERSA_N`, { id: exec.conversation_display_id })
                }}
              </span>
            </div>
            <Button class="ml-auto" outline slate xs :label="t(`${K}.EXECUCAO.ABRIR`)" @click="abrirAlvo" />
          </div>

          <ol class="relative">
            <li
              v-for="(linha, i) in exec.trilha"
              :key="i"
              data-testid="trilha-item"
              class="relative pb-4 pl-6 last:pb-0"
            >
              <span class="absolute left-[5px] top-1.5 size-[9px] rounded-full" :class="corLinha(linha)" />
              <span v-if="i < exec.trilha.length - 1" class="absolute bottom-0 left-[9px] top-[18px] w-px bg-n-slate-6" />
              <span class="float-right font-mono text-xs text-n-slate-10">{{ quando(linha.em) }}</span>
              <b class="text-[13px] font-medium text-n-slate-12">{{ tituloLinha(linha) }}</b>
              <p class="mt-0.5 text-[12.5px] text-n-slate-11" :class="linha.erro ? 'text-n-ruby-11' : ''">{{ linha.resumo }}</p>
            </li>
          </ol>

          <p v-if="exec.status === 'esperando' && exec.retomar_em" :class="[AVISO, TOM.amber]" class="mt-4">
            {{ t(`${K}.EXECUCAO.ESPERANDO_ATE`, { quando: quando(exec.retomar_em) }) }}
          </p>
          <p v-if="exec.erro" :class="[AVISO, TOM.ruby]" class="mt-4">
            {{ t(`${K}.EXECUCAO.ERRO`, { erro: exec.erro }) }}
          </p>
        </div>

        <div v-if="exec.conversation_display_id" class="border-t border-n-weak px-4 py-3">
          <Button outline slate sm icon="i-lucide-message-square" :label="t(`${K}.EXECUCAO.VER_CONVERSA`)" @click="verConversa" />
        </div>
      </aside>
    </div>
  </section>
</template>
```

- [ ] **Step 4: Rodar e ver passar + lint**

```bash
TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/captain/automacoes
./node_modules/.bin/eslint --fix app/javascript/dashboard/routes/dashboard/captain/automacoes/
```
Expected: todos PASS; eslint limpo.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/Execucao.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/Execucao.spec.js
git commit -m "feat(fluxos): tela da execução com o caminho aceso e a trilha" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 13: Story + prints claro/escuro + página de comparação com o mockup

Referência do harness: `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-intel-a\tmp\intel-harness\` (index.html, main.js, vite.config.mts, shots.sh, comparar.mjs, stubs) e o relatório `…\ramon-hub-wt-intel-a\.superpowers\sdd\2026-10-05-inteligencia-a1-faxina\task-1-report.md` (lição: `BackButtonStub` evita ciclo de import; usuário fictício com `permissions: ['administrator','agent']`; fontes carregadas antes de montar).

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/captain/automacoes/Automacoes.story.vue` (versionado)
- Create (NÃO versionado, `tmp/` está no `.gitignore`): `tmp/fluxos-harness/{index.html,main.js,vite.config.mts,shots.sh,comparar.mjs,ConversationBoxStub.vue,BackButtonStub.vue}`
- Saída: `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-05-fluxos-b2\` — `{claro,escuro}-{lista,editor,execucao,novo}.png`, cópias `mockup-{lista,editor,execucao,novo}-{light,dark}.png` e `comparar.html`

**Interfaces:**
- Consumes: `Lista`, `Editor`, `Execucao` (Tasks 8, 11, 12).
- Produces: variantes `Lista`, `Editor`, `Execucao`, `Novo`.

- [ ] **Step 1: A story**

`…/automacoes/Automacoes.story.vue`:

```vue
<script setup>
// Story das Automações (B2) — prints de aprovação claro/escuro. Sem rede:
// window.axios responde com dados FICTÍCIOS por URL. Fluxo = o do mockup,
// só com passos da B1.
import { provide, reactive } from 'vue';
import { routeLocationKey, routerKey } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import types from 'dashboard/store/mutation-types';
import Lista from './Lista.vue';
import Editor from './Editor.vue';
import Execucao from './Execucao.vue';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

const DIA = 86400000;
const atras = ms => new Date(Date.now() - ms).toISOString();
const no = (id, tipo, config, x, y) => ({ id, tipo, config, posicao: { x, y } });
const GRAFO = {
  nos: [
    no('n1', 'gatilho', { tipo: 'lead_mudou_etapa', para_etapa_ids: [4] }, 300, 0),
    no('n2', 'rascunho_texto', { rotulo: 'Boas-vindas', texto: 'Olá, {nome}! Seja bem-vindo(a).' }, 300, 120),
    no('n3', 'criar_tarefa', { titulo: 'Conferir documentos', tipo: 'document', prazo_dias: 1 }, 300, 265),
    no('n4', 'esperar', { quantidade: 2, unidade: 'dias' }, 300, 385),
    no('n5', 'se', { rotulo: 'Documentos completos?', juncao: 'e', condicoes: [{ campo: 'etiquetas', operador: 'contem', valor: 'docs-ok' }] }, 300, 505),
    no('n6', 'mover_etapa', { etapa_id: 5 }, 80, 660),
    no('n7', 'rascunho_texto', { rotulo: 'Lembrete dos documentos', texto: 'Oi, {nome}! Passando para lembrar dos documentos.' }, 520, 660),
    no('n8', 'avisar_push', { texto: '{nome} ainda deve documentos' }, 520, 805),
  ],
  setas: [
    { de: 'n1', saida: 's', para: 'n2' },
    { de: 'n2', saida: 's', para: 'n3' },
    { de: 'n3', saida: 's', para: 'n4' },
    { de: 'n4', saida: 's', para: 'n5' },
    { de: 'n5', saida: 'sim', para: 'n6' },
    { de: 'n5', saida: 'nao', para: 'n7' },
    { de: 'n7', saida: 's', para: 'n8' },
  ],
};
const linha = (n, tipo, saida, resumo, h) => ({ no: n, tipo, em: atras(h * 3600000), saida, resumo, erro: false });
const EXEC = {
  id: 412, fluxo_id: 1, versao: 3, alvo_type: 'Lead', alvo_id: 231, alvo_nome: 'Maria da Silva', lead_id: 231,
  conversation_display_id: 1802, status: 'concluida', ensaio: false, no_atual: null, retomar_em: null, erro: null,
  created_at: atras(2 * DIA), updated_at: atras(0), grafo: GRAFO,
  trilha: [
    linha('n1', 'gatilho', 's', 'lead_mudou_etapa', 48),
    linha('n2', 'rascunho_texto', 's', 'rascunho criado: Olá, Maria! Seja bem-vindo(a).', 48),
    linha('n3', 'criar_tarefa', 's', 'tarefa "Conferir documentos" · Ana', 48),
    linha('n4', 'esperar', 's', 'espera até 04/10 14:31', 48),
    linha('n5', 'se', 'nao', 'não', 1),
    linha('n7', 'rascunho_texto', 's', 'rascunho criado: Oi, Maria! Passando para lembrar dos documentos.', 1),
    linha('n8', 'avisar_push', 's', 'push: Maria ainda deve documentos', 1),
  ],
};
const FLUXO = {
  id: 1, nome: 'Pós-contrato: pedir documentos', descricao: null, gatilho_tipo: 'lead_mudou_etapa', ativo: true,
  limite_dia: 20, origem: 'usuario', sistema_chave: null, modo: 'normal', versao: 3, editado_em: atras(DIA),
  hoje: 3, esperando: 8, falharam_24h: 0, ultima_em: atras(12 * 60000),
  rascunho: GRAFO, versoes: [3, 2, 1].map(n => ({ numero: n, created_at: atras(n * DIA) })),
};
const API = {
  ramon_fluxos: {
    payload: [
      FLUXO,
      { ...FLUXO, id: 2, nome: 'Fora do horário', gatilho_tipo: 'mensagem_recebida', versao: 2, limite_dia: 50, hoje: 14, esperando: 0, ultima_em: atras(4 * 60000) },
      { ...FLUXO, id: 3, nome: 'Lead ganho', gatilho_tipo: 'lead_ganho', versao: 1, limite_dia: null, hoje: 1, esperando: 0, falharam_24h: 1, ultima_em: atras(3600000) },
      { ...FLUXO, id: 4, nome: 'Rodar na mão: pedir documentos', gatilho_tipo: null, versao: null, ativo: false, hoje: 0, esperando: 0, ultima_em: null },
    ],
    resumo: { ligados: 3, total: 4, hoje: 18, esperando: 8, falharam_24h: 1 },
  },
  'ramon_fluxos/1': FLUXO,
  'ramon_fluxos/1/execucoes': { payload: [{ ...EXEC, grafo: undefined }, { ...EXEC, id: 411, ensaio: true, alvo_nome: 'João Pereira', created_at: atras(3 * DIA) }] },
  'ramon_fluxos/1/execucoes/412': EXEC,
};
const responder = async url => ({ data: API[url.replace(/^\/api\/v1\/(accounts\/\d+\/)?/, '')] ?? { payload: [] } });
window.axios = { get: responder, post: responder, patch: responder, put: responder, delete: responder };

const rota = reactive({ name: 'captain_automacoes_index', params: { accountId: 1, fluxoId: '1', execId: '412' }, query: {} });
provide(routeLocationKey, rota);
provide(routerKey, { push: () => {}, replace: () => {}, resolve: () => ({ href: '#' }), currentRoute: { value: rota } });

const store = useStore();
store.registerModule('route', { state: { params: { accountId: 1 } } });
store.commit(types.SET_CURRENT_USER, {
  id: 1, name: 'Eduardo Schlata', ui_settings: {},
  accounts: [{ id: 1, role: 'administrator', permissions: ['administrator', 'agent'] }],
});
// módulos namespaced: leadConfig, agents, theses, inboxes (store/modules/*)
store.commit(`leadConfig/${types.SET_LEAD_CONFIG}`, {
  stages: [
    { id: 4, name: 'Contrato assinado', position: 4 },
    { id: 5, name: 'Documentação OK', position: 5 },
  ],
  priorities: [],
});
store.commit(`inboxes/${types.SET_INBOXES}`, [{ id: 7, name: 'WhatsApp Escritório', channel_type: 'Channel::Whatsapp' }]);
store.commit(`agents/${types.SET_AGENTS}`, [{ id: 1, name: 'Ana Souza', confirmed: true }]);
store.commit(`theses/${types.SET_THESES}`, [{ id: 1, name: 'Auxílio-acidente', position: 0 }]);

const comNo = id => () => {
  rota.query = { no: id };
};
const clicarEm = texto => () =>
  setTimeout(() => [...document.querySelectorAll('button')].find(b => b.textContent.includes(texto))?.click(), 2000);
</script>

<template>
  <Story title="Captain/Automações" :layout="{ type: 'single', iframe: true }">
    <Variant title="Lista">
      <div class="h-screen"><Lista /></div>
    </Variant>
    <Variant title="Novo" :init-state="clicarEm('Novo fluxo')">
      <div class="h-screen"><Lista /></div>
    </Variant>
    <Variant title="Editor" :init-state="comNo('n7')">
      <div class="h-screen"><Editor /></div>
    </Variant>
    <Variant title="Execucao">
      <div class="h-screen"><Execucao /></div>
    </Variant>
  </Story>
</template>
```

A story pré-carrega etapas, pessoas e teses porque o `responder` devolve `{payload: []}` para `agents`/`theses` (quebraria o `SET_THESES`); o Editor só despacha `*/get` quando o getter está vazio.

- [ ] **Step 2: O harness (cópia do da A1, apontando para a story nova)**

```bash
mkdir -p tmp/fluxos-harness
cp ../ramon-hub-wt-intel-a/tmp/intel-harness/{index.html,main.js,vite.config.mts,ConversationBoxStub.vue,BackButtonStub.vue} tmp/fluxos-harness/
sed -i "s#dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue#dashboard/routes/dashboard/captain/automacoes/Automacoes.story.vue#; s#|| 'FAQs'#|| 'Lista'#" tmp/fluxos-harness/main.js
sed -i "s#port: 6194#port: 6195#" tmp/fluxos-harness/vite.config.mts
```

`tmp/fluxos-harness/shots.sh`:

```sh
#!/bin/sh
# uso: sh tmp/fluxos-harness/shots.sh  (vite de pé na 6195)
out="C:/Users/dudsl/RAdvogados/comercial/docs/mockups/2026-10-05-fluxos-b2"
mock="C:/Users/dudsl/RAdvogados/comercial/docs/mockups/2026-10-05-inteligencia-fluxos"
mkdir -p "$out"
chrome="/c/Program Files/Google/Chrome/Application/chrome.exe"
for v in "Lista:lista" "Novo:novo" "Editor:editor" "Execucao:execucao"; do
  nome=${v%%:*}; arq=${v##*:}
  for tema in claro escuro; do
    "$chrome" --headless=new --disable-gpu --hide-scrollbars --window-size=1440,900 \
      --virtual-time-budget=15000 --screenshot="$out/$tema-$arq.png" \
      "http://localhost:6195/?variant=$nome&tema=$tema" >/dev/null 2>&1 &
  done
  wait
  for t in light dark; do cp "$mock/print-$arq-$t.png" "$out/mockup-$arq-$t.png"; done
done
ls "$out"
```

`tmp/fluxos-harness/comparar.mjs`:

```js
import { writeFileSync } from 'node:fs';
const OUT = 'C:/Users/dudsl/RAdvogados/comercial/docs/mockups/2026-10-05-fluxos-b2';
const TELAS = [
  ['Lista', 'lista', 'só a aba "Meus fluxos" (Do sistema = B3); 4 números; chave liga/desliga; hoje/limite'],
  ['Novo fluxo', 'novo', 'em branco + 4 modelos só com passos da B1'],
  ['Editor', 'editor', 'quadro vertical, painel do passo, selo "sai como rascunho", barra Ligado/Versões/Testar/Publicar'],
  ['Execução / ensaio', 'execucao', 'caminho aceso (teal = ok do kit), trilha com horários, alvo'],
];
const fig = (rot, src) => `<figure><figcaption>${rot}</figcaption><img src="${src}" alt="${rot}"></figure>`;
const secoes = TELAS.flatMap(([nome, arq, leg]) =>
  [['claro', 'light'], ['escuro', 'dark']].map(
    ([tema, t]) =>
      `<section><h2>${nome} · tema ${tema}</h2><p class="leg">${leg}</p><div class="par">${fig('Mockup aprovado', `mockup-${arq}-${t}.png`)}${fig('Implementado (B2)', `${tema}-${arq}.png`)}</div></section>`
  )
).join('');
const css =
  'body{font:14px system-ui,sans-serif;margin:24px;background:#f4f4f4;color:#111}h1{font-size:20px}h2{font-size:15px;margin:28px 0 4px}.leg{margin:0 0 8px;color:#555}.par{display:flex;gap:24px;align-items:flex-start;flex-wrap:wrap}figure{margin:0;background:#fff;padding:8px;border:1px solid #ddd;border-radius:8px}figcaption{font-weight:600;margin-bottom:6px}img{width:700px;max-width:100%;display:block}';
writeFileSync(
  `${OUT}/comparar.html`,
  `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>Automações B2 — mockup × implementado</title><style>${css}</style></head><body><h1>Automações em fluxo — B2 (o quadro): mockup aprovado × implementado</h1><p>Menu: Inteligência → Vigia · <b>Automações</b> · Assistentes · …</p>${secoes}</body></html>`
);
console.log(`ok ${OUT}/comparar.html`);
```

- [ ] **Step 3: Subir o Vite e tirar os prints**

```bash
npx vite --config tmp/fluxos-harness/vite.config.mts > tmp/fluxos-harness/vite.log 2>&1 &
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:6195/
sh tmp/fluxos-harness/shots.sh
node tmp/fluxos-harness/comparar.mjs
```
Expected: `200`; 8 PNGs `{claro,escuro}-{lista,novo,editor,execucao}.png` + 8 `mockup-*.png`; `ok …/comparar.html`.

- [ ] **Step 4: Conferir os prints (Read em cada PNG)**

Checklist visual — corrigir o componente e repetir o Step 3 até bater:
- Lista: 4 cartões de número, tabela com chave, gatilho com ícone azul, barrinha hoje/limite, selos `ok` teal / `1 falhou` ruby / `desligado` cinza; escuro legível.
- Novo: modal 720px, "Em branco" tracejado + 4 modelos.
- Editor: 8 passos de cima para baixo, setas cinza visíveis nos DOIS temas, portas sim/não com rótulo, gatilho com filete azul, selo âmbar "sai como rascunho" em n2 e n7, n7 selecionado (anel azul) com o painel aberto e o aviso âmbar, minimapa e 3 botões de zoom embaixo, "Adicionar passo" no canto.
- Execução: caminho n1→n2→n3→n4→n5→n7→n8 aceso (borda teal + ✓, setas teal), n6 apagado, trilha à direita com 7 itens e horários.
Se as setas não aparecerem: ver nota do Task 9 (classe arbitrária do path).

- [ ] **Step 5: Commit (só a story; harness e PNGs ficam fora do repo)**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/Automacoes.story.vue
git commit -m "test(fluxos): story das automações para os prints de aprovação" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 14: Verificação final + texto do PR (sem push)

**Files:**
- Nenhum código novo. Saída: `tmp/fluxos-harness/pr-b2.md` (corpo do PR, não versionado).

- [ ] **Step 1: Suíte inteira do front que a B2 toca + lint**

```bash
TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/captain app/javascript/dashboard/components-next/sidebar
./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain app/javascript/dashboard/api/ramonFluxos.js app/javascript/dashboard/components-next/sidebar/Sidebar.vue
```
Expected: PASS; eslint só `Delete ␍` (CRLF) ou nada.

- [ ] **Step 2: i18n de produção (vue-i18n prod compila cada string)**

```bash
node -e "
process.env.NODE_ENV='production';
const { createI18n } = require('vue-i18n/dist/vue-i18n.cjs.prod.js');
const fs = require('fs');
let erros = 0;
const folhas = (o, p='') => Object.entries(o).flatMap(([k,v]) => typeof v === 'object' ? folhas(v, p+k+'.') : [[p+k, v]]);
for (const loc of ['en','pt_BR']) {
  const r = JSON.parse(fs.readFileSync('app/javascript/dashboard/i18n/locale/'+loc+'/ramon.json','utf8'));
  const msgs = { CAPTAIN_RAMON: { FLUXOS: r.CAPTAIN_RAMON.FLUXOS } };
  const errs = [];
  const i18n = createI18n({ legacy:false, locale:loc, messages:{[loc]:msgs}, missingWarn:false, fallbackWarn:false, onError:e=>errs.push(e.message) });
  for (const [k] of folhas(msgs)) { errs.length=0; const out = i18n.global.t(k, new Proxy({}, {get:()=>'X'})); if (errs.length || out===k) { erros++; console.log('ERR', loc, k, errs[0]); } }
}
console.log('erros:', erros);"
```
Expected: `erros: 0`.

- [ ] **Step 3: Diff final confere com o mapa de arquivos**

Run: `git diff --stat origin/ramon...HEAD`
Expected: só os arquivos do mapa (+ o plano). Nenhum arquivo de `enterprise/`, nenhuma migração, nenhum `db/schema.rb`.

- [ ] **Step 4: Texto do PR (para o Eduardo/sessão principal abrir)**

`tmp/fluxos-harness/pr-b2.md`:

```markdown
feat(fluxos): quadro de automações (B2)

A Inteligência ganha "Automações": a lista dos fluxos (4 números, liga/desliga, hoje/limite), o editor tipo n8n de cima para baixo (paleta por grupos, painel de cada passo, selo "sai como rascunho"), versões, "Testar com um lead…" (ensaio que não executa nada) e a tela de execução com o caminho aceso. Novo fluxo vem com modelos prontos. Só administradores veem.

## Closes
- Spec `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` §7 e §10 (fatia B2)

## How to test
1. Inteligência → Automações → Novo fluxo → "Lead ganho".
2. No editor: clique em cada passo e veja o painel; "+ Adicionar passo" → Esperar (entra ligado embaixo do passo selecionado).
3. Apague o texto de uma nota e clique Publicar: o passo fica vermelho e a faixa explica. Corrija e publique (v1).
4. "Testar com um lead…" → escolha um lead → Ensaiar: abre a execução com o caminho em verde-azulado e a trilha.
5. Volte à lista: a chave liga/desliga; "Hoje / limite" e "Última" refletem as execuções.

## What changed
- Front: `captain/automacoes/*` (3 telas, quadro Vue Flow, painel), `api/ramonFluxos.js`, item no menu, textos en/pt-BR.
- Back: a execução devolve o desenho em que rodou (`GET …/execucoes/:id` → `grafo`). Sem migração.
- Dependência nova: `@vue-flow/core` + `@vue-flow/minimap` (MIT).
- ⚠️ Textos de rascunho dos modelos = gate do Eduardo antes de publicar fluxos a partir deles.
- Prints: `comercial/docs/mockups/2026-10-05-fluxos-b2/comparar.html`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv
```

- [ ] **Step 5: Parar aqui** — sem push e sem PR (gate do Eduardo / sessão principal). Reportar: commits, resultado do vitest/eslint/i18n, caminho do `comparar.html`.

---

## Divergências registradas (mockup/spec × este plano)

| # | Onde | Divergência | Motivo |
|---|---|---|---|
| 1 | Lista | Sem a aba "Do sistema" (só "Meus fluxos"); a barra de abas fica pronta para a B3 | Fatia B3 (spec §8, §10) |
| 2 | Paleta/Modelos/Gatilhos | Itens da B2b (Perguntar à IA, Rascunho pela IA, Rodar skill, ADVBOX, Webhook, Preencher campo; gatilhos reunião/ADVBOX/ZapSign/documento/parado/relógio; modelos Cadência, Lembretes, Evento do ADVBOX) **não aparecem** (nem desabilitados) | O motor da B1 recusa esses tipos no Publicar; botão morto confunde. Entram com a B2b |
| 3 | Painel | Sem seletor de Assistente/Skill e sem a chave "Se falhar: tentar 3× e avisar no sino" | IA = B2b; o retry 1/5/15 min + sino é fixo no motor da B1 (não configurável) |
| 4 | Painel | "Cancelar se o lead sair da etapa" fica no painel do **gatilho**, não no passo | Na B1 é `config.cancelar_se_sair_da_etapa` do gatilho |
| 5 | Modelo Pós-contrato | Sem o "Se documentos completos?" (vira esperar → lembrete → push) | O contexto da B1 não tem campo de documentos |
| 6 | Lista | Linha sem "editado por <pessoa>" e gatilho sem o filtro ("→ Contrato assinado") | O `index` da B1 não devolve autor nem rascunho; só `gatilho_tipo` |
| 7 | Quadro | Rótulos sim/não/caso colados embaixo da porta (não no meio da seta) | Evita estilizar texto SVG do Vue Flow; visual equivalente |
| 8 | Cores | Verde "ok" do mockup = **teal** do kit | O kit do hub não tem verde; teal é o "ok" padrão (`TOM.teal`) |
| 9 | Spec §7 | Modelos em JS (`modelos.js`), não `db/seeds/ramon/fluxos/*.json` | Só o front consome; os fluxos do sistema (B3) continuam em `db/seeds` |
| 10 | Spec §7 | "Rodar na mão" pelo menu ⋯ do lead/conversa fica para a B2b; na B2 o gatilho manual roda pelo botão "Rodar de verdade" do modal Testar | Fora do escopo B2 da spec §10; o modal já tem o seletor de lead |
| 11 | Quadro | Sem `@vue-flow/controls`/`background` (spec citava controls): 3 botões próprios + pontilhado fixo como o mockup | Menos dependência; o mockup também não move o pontilhado |
| 12 | Versões | Só lista (número, data, "no ar"); sem abrir/restaurar versão antiga | A API não devolve o desenho de cada versão; YAGNI até pedirem |
| 13 | Editor | Execuções recentes do fluxo aparecem no painel direito quando nenhum passo está selecionado | O mockup não mostra onde; aproveita o painel vazio |
| 14 | Back | +1 linha: a execução devolve `grafo` | Sem isso a tela de execução desenharia o rascunho de agora, não a versão em que rodou |

## Decisões que exigem o Eduardo

1. **Textos de rascunho dos 4 modelos** (Pós-contrato ×2, Fora do horário, Rodar na mão) — falam com cliente → aprovar antes de publicar qualquer fluxo feito a partir deles.
2. **Itens da B2b escondidos** (em vez de "em breve" desabilitado) — confirmar.
3. **Pós-contrato sem "documentos completos?"** até a B2b — aceitar ou segurar o modelo.
4. **"Rodar de verdade" no modal Testar** como único jeito de acionar fluxo manual na B2 (o botão no lead vem na B2b).
5. **Excluir fluxo** (botão na barra do editor, com confirmação) — não está no mockup; a API já permite.
