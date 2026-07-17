# Cálculos por cliente + especial no Simulador — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Marcar atividade especial por vínculo no Simulador (F4 do motor já no ar) e criar a página interna "Cálculos" (menu → busca de pessoa → painel de possibilidades do lead).

**Architecture:** Front Vue 3 `<script setup>`/Tailwind no padrão ramon; `especiais` viaja como JSON string no POST `leads/:id/painel` (não exige re-upload do PDF), o `LeadPaineisController` funde por `seq` no `vinculos` e persiste em `lead.cnis['parametros']`; página nova `Calculos.vue` clona o padrão `LinhaDaVida.vue` (busca `ContactAPI.search` → leads do contato → `LeadSimulador` standalone, que só precisa do prop `lead`).

**Tech Stack:** Vue 3 Composition API, Tailwind, vitest (roda local: `npx vitest run <dir>`), Rails + RSpec (CI; sem ambiente local — validação final é PR+CI).

## Global Constraints (AGENTS.md do repo + spec)

- i18n obrigatório: nenhuma string solta em template; só `en.json`/`en.yml` (demais idiomas ficam pra comunidade).
- Vue: Composition API `<script setup>`, componentes PascalCase, eventos camelCase.
- Só Tailwind — zero CSS custom/scoped/inline.
- MVP/menor diff; sem defensive programming especulativo.
- Página nova: raiz `w-full h-full` (lição registrada — sem isso encolhe).
- Branch `feat/calculos-especial-ui` (já existe, spec commitada nela). PR pra `ramon`; merge só com OK do Eduardo na conversa.
- Graus válidos: 15/20/25. O motor valida e devolve 422 com mensagem pt (trecho fora do vínculo, graus sobrepostos, benefício marcado) — exibir no slot de erro existente do painel, sem tradução extra.
- Spec: `docs/superpowers/specs/2026-07-17-calculos-especial-ui-design.md`.

---

### Task 1: Backend — `especiais` no LeadPaineisController

**Files:**
- Modify: `app/controllers/api/v1/accounts/lead_paineis_controller.rb` (strong params linha ~26-28; `motor_payload` linhas ~77-87)
- Test: `spec/controllers/api/v1/accounts/lead_paineis_controller_spec.rb`

**Interfaces:**
- Consumes: `lead.cnis['entrada']['vinculos']` (itens com `seq`), `lead.cnis['parametros']` (jsonb já usado por excluir_seqs/mensalidades — conferir a chave exata de leitura no controller/spec do `/cnis`).
- Produces: POST `leads/:id/painel` aceita `especiais` (JSON string `{"<seq>": {"grau": 25, "inicio": "YYYY-MM-DD"|null, "fim": ...|null}}`) e `vinculos_extras[][especial]` (hash `{grau, inicio, fim}`); o corpo enviado ao motor tem `especial` dentro de cada vínculo marcado; `especiais` persistido em `lead.cnis['parametros']['especiais']` (string crua) quando presente.

- [ ] **Step 1: Specs que falham** — no spec do controller (seguir os stubs/WebMock existentes do arquivo; o mock do motor deve CAPTURAR o corpo enviado):

```ruby
it 'funde especiais nos vinculos por seq e persiste nos parametros' do
  # lead com cnis entrada contendo vinculo seq=3 (usar a factory/setup existente do arquivo)
  corpo_enviado = nil
  stub_request(:post, %r{/painel}).with { |req| corpo_enviado = JSON.parse(req.body); true }
    .to_return(status: 200, body: { resumo: {}, cartoes: [], avisos: [] }.to_json,
               headers: { 'Content-Type' => 'application/json' })
  post_painel(especiais: { '3' => { 'grau' => 25 } }.to_json)  # helper conforme o arquivo
  expect(response).to have_http_status(:success)
  v3 = corpo_enviado['vinculos'].find { |v| v['seq'] == 3 }
  expect(v3['especial']).to eq('grau' => 25, 'inicio' => nil, 'fim' => nil)
  expect(lead.reload.cnis.dig('parametros', 'especiais')).to be_present
end

it 'passa especial dos vinculos_extras adiante' do
  # vinculos_extras: [{inicio:, fim:, tipo: 'EMPREGO', especial: {grau: 15}}]
  # assert: corpo_enviado['vinculos'] inclui o extra com chave 'especial'
end

it 'especiais invalido (JSON quebrado) devolve 400/422 sem 500' do
  # post_painel(especiais: '{nao-e-json') → status 4xx, sem exception
end
```

(Adaptar `post_painel`/setup ao helper real do arquivo — LER o spec existente primeiro; os asserts acima são o contrato.)

- [ ] **Step 2: Implementar no controller**

Strong params: acrescentar `:especiais` e `vinculos_extras: [:inicio, :fim, :tipo, :salario, { especial: [:grau, :inicio, :fim] }]`. Em `motor_payload`:

```ruby
def especiais_map
  return {} if params[:especiais].blank?
  JSON.parse(params[:especiais])
rescue JSON::ParserError
  render json: { error: 'especiais: JSON inválido' }, status: :unprocessable_entity
  {}
end
```

(Ou o padrão de erro que o controller já usa — LER como o 422 do motor é propagado hoje e seguir igual; o rescue não pode deixar vazar 500.) Na montagem dos vínculos do CNIS: `v = v.merge('especial' => { 'grau' => e['grau'], 'inicio' => e['inicio'], 'fim' => e['fim'] }) if (e = mapa[v['seq'].to_s])`. Persistência: após sucesso do motor, se `params[:especiais].present?`, gravar `lead.cnis['parametros'] = (lead.cnis['parametros'] || {}).merge('especiais' => params[:especiais])` + `lead.save!` (mesmo estilo do `stored` do LeadCnisController — LER e espelhar).

- [ ] **Step 3: Rodar RSpec?** Sem ambiente local (constraint do repo) — validação dos specs é o CI do PR. Conferir sintaxe com `bundle exec rubocop` SE disponível local; senão, revisão manual dupla do diff. Registrar no relatório o que foi possível rodar.

- [ ] **Step 4: Commit** — `feat(ramon): especiais por vinculo no POST /painel (funde por seq + persiste em parametros)`

---

### Task 2: Front — UI de especial no Ajustar vínculos

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadSimulador.vue` (cards de vínculo linhas ~307-367; payload do painel linhas ~237-243; load dos parametros linhas ~74-82; vinculosExtras ~212-243)
- Modify: `app/javascript/dashboard/api/leads.js` (payload do `painel`)
- Modify: i18n `en.json` do dashboard (chaves novas sob o namespace já usado pelo Simulador — localizar com grep pelas chaves existentes do componente)
- Test: `.../specs/LeadSimulador.spec.js`

**Interfaces:**
- Consumes: Task 1 no ar (param `especiais`; `parametros.especiais` devolvido no `cnis_resumo`).
- Produces: estado `especiais = ref({})` (mapa seq→{grau, inicio, fim}); enviado como JSON string na chamada `LeadsAPI.painel`; `vinculosExtras[i].especial` opcional.

- [ ] **Step 1: Specs vitest que falham** (estender LeadSimulador.spec.js, padrão do arquivo):

```js
it('marca vínculo como especial e envia especiais no payload do painel', async () => {
  // setup igual ao teste existente de painel-com-CNIS;
  // agir: selecionar grau 25 no select data-testid="sim-especial-grau-3" (seq 3)
  // assert: LeadsAPI.painel chamado com especiais contendo {"3":{"grau":25,...}}
});
it('trecho parcial vai junto quando preenchido', async () => { /* inicio/fim nos inputs data-testid sim-especial-inicio-3/fim-3 */ });
it('parametros.especiais persistidos pré-populam os selects', async () => { /* cnis_resumo.parametros.especiais = '{"3":{"grau":15}}' → select mostra 15 */ });
```

Rodar: `npx vitest run app/javascript/dashboard/routes/dashboard/ramon/components/conversation` → FAIL.

- [ ] **Step 2: Implementar no LeadSimulador.vue**

No card do vínculo (após o bloco da mensalidade, dentro do v-for; NÃO renderizar pra `v.tipo === 'BENEFICIO'` — o motor rejeita):

```html
<div v-if="v.tipo !== 'BENEFICIO'" class="mt-2 flex flex-wrap items-center gap-2">
  <label class="text-xs text-n-slate-11">{{ $t('RAMON_SIMULADOR.ESPECIAL.LABEL') }}</label>
  <select v-model="especiais[v.seq]" :data-testid="`sim-especial-grau-${v.seq}`" class="...classes dos selects existentes...">
    <option :value="undefined">{{ $t('RAMON_SIMULADOR.ESPECIAL.NAO') }}</option>
    <option :value="15">15</option><option :value="20">20</option><option :value="25">25</option>
  </select>
  <template v-if="especiais[v.seq]">
    <input v-model="especiaisTrecho[v.seq].inicio" type="date" :data-testid="`sim-especial-inicio-${v.seq}`" class="..." />
    <input v-model="especiaisTrecho[v.seq].fim" type="date" :data-testid="`sim-especial-fim-${v.seq}`" class="..." />
  </template>
</div>
```

(Estrutura de estado: simplificar se preferir UM ref `especiais = ref({})` com objetos `{grau, inicio, fim}` — o snippet é o contrato de testids/i18n, não a implementação literal; reusar as classes Tailwind dos selects/inputs vizinhos.) Montagem: `especiaisJson()` espelhando `mensalidadesJson()` (filtra sem grau; datas vazias → null). Enviar em `LeadsAPI.painel({... , especiais: especiaisJson()})` e adaptar `leads.js`. Load: pré-popular de `parametros.especiais` no mesmo ponto onde excluir/mensalidades são lidos (linhas ~74-82). `vinculosExtras`: acrescentar os mesmos campos no card do vínculo manual (`especial: {grau, inicio, fim}` no objeto, incluído no filtro de envio). i18n: `RAMON_SIMULADOR.ESPECIAL.{LABEL: "Atividade especial", NAO: "Não"}` (namespace real = o do componente; conferir).

- [ ] **Step 3: Rodar vitest verde + eslint** (`npx vitest run <dir>`; `npx eslint app/javascript/dashboard/routes/dashboard/ramon --fix` se o repo tiver script — conferir package.json).

- [ ] **Step 4: Commit** — `feat(ramon): marcacao de atividade especial por vinculo no Simulador`

---

### Task 3: Página "Cálculos" (menu + busca + Simulador standalone)

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/pages/Calculos.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js` (rotas `ramon_calculos` e `ramon_calculos_lead`, padrão das linhas 53-65)
- Modify: `.../IntranetSidebar.vue` (item "calculos" na mesma seção de funil/pessoas, linhas ~25-54)
- Modify: `en.json` (título/menu/estados vazios)
- Backend SE necessário: endpoint leads-por-contato — VERIFICAR primeiro: `grep -n "contact_id" app/controllers/api/v1/accounts/leads_controller.rb app/models/lead.rb` e o que `LeadsAPI` (leads.js) já expõe. Se `Lead` tem `contact_id` e o index aceita filtro, usar; senão acrescentar `?contact_id=` no index (escopo mínimo) + request spec.
- Test: `.../pages/specs/Calculos.spec.js` (fumaça)

**Interfaces:**
- Consumes: `ContactAPI.search` (padrão LinhaDaVida.vue:46-84), `LeadSimulador` (prop única `lead`), endpoint leads-por-contato.
- Produces: rota `ramon_calculos` (busca) e `ramon_calculos_lead` (`:leadId` — abre direto), item de menu.

- [ ] **Step 1: Spec de fumaça que falha** — render da página, digitar busca → mock ContactAPI.search devolve 1 pessoa → clicar → mock leads-por-contato devolve 1 lead → assert que o stub do LeadSimulador recebeu `lead` (mockar o componente filho; o LeadSimulador tem specs próprios). Estado vazio: contato sem lead → texto de orientação (i18n).

- [ ] **Step 2: Implementar Calculos.vue** — clonar a estrutura do LinhaDaVida.vue (raiz `flex-1 w-full h-full p-6 overflow-y-auto bg-n-background`, busca com debounce 300ms + AbortController, resultados com `data-testid="pessoa-result"`); ao escolher pessoa: buscar leads do contato; 1 lead → renderizar `<LeadSimulador :lead="lead" />` direto; >1 → lista simples (tese + data) pra escolher; 0 → estado vazio i18n. Rota com `:leadId` opcional pra deep-link (mesmo padrão duplo do LinhaDaVida).

- [ ] **Step 3: Rota + menu** — registrar em ramon.routes.js e IntranetSidebar.vue espelhando o item "pessoas" (ícone: usar um da biblioteca já importada no sidebar — escolher um de cálculo/moeda existente; NADA de asset novo).

- [ ] **Step 4: vitest verde + eslint; commit** — `feat(ramon): pagina Calculos — busca de pessoa e painel de possibilidades por lead`

---

### Task 4: PR + coordenação

- [ ] Rebase sobre `origin/ramon` atual (outra sessão ativa hoje — se a `ramon` avançou, rebase e re-rodar vitest).
- [ ] `npx vitest run app/javascript/dashboard/routes/dashboard/ramon` inteiro + eslint no diff.
- [ ] Abrir PR pra `ramon` (gh CLI), corpo: o que muda, spec link, plano de smoke (marcar especial → cartões especial_* aparecem; página Cálculos → busca → painel; 422 amigável com trecho inválido), nota "não mergear sem OK do Eduardo".
- [ ] Reportar na conversa: link do PR + o que o CI precisa mostrar. **PARAR aqui — merge/deploy é gate do Eduardo.**

---

## Self-Review

- Spec coberta: fatia 1 → Tasks 1-2 (transporte via /painel corrigido pós-exploração, persistência em cnis.parametros); fatia 2 → Task 3 (padrão LinhaDaVida, LeadSimulador standalone via prop lead — confirmado que não depende de conversa); erros 422 → slot existente (Task 2 herda, teste 422 já existe no spec do componente); coordenação/deploy → Task 4.
- Sem placeholders: os pontos "LER primeiro" são instruções de descoberta com localização exata, não lacunas.
- Tipos: `especiais` JSON string no wire (padrão mensalidades); `especial` hash no item de vínculo (contrato do motor F4: `{grau, inicio?, fim?}`).
