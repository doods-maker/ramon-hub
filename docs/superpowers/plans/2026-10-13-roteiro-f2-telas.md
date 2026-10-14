# F2 — Telas do roteiro da tese · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** o admin cadastra o roteiro da IA (passos comuns da conta e por tese) na tela Playbooks, a equipe vê o roteiro passo a passo no painel do lead (com "Reabrir roteiro") e o Testar da Inteligência conversa seguindo o roteiro de uma tese sem gravar nada.

**Architecture:** três endpoints novos em `app/` (testados no CI): `roteiro_passos` (CRUD + reorder; o salvar passa pela `Ramon::Roteiro::Conferencia`, que confere "vai para", campos de calculadora e chave), `leads/:id/roteiro` (o passo a passo montado pela `Ramon::Roteiro::Painel`) e `leads/:id/reabrir_roteiro` (chama `Ramon::Roteiro.reabrir` da F1 e descarta as sugestões pendentes do roteiro). O broadcast do lead ganha `roteiro_versao` (hash do estado) para o painel recarregar sozinho. O Testar com tese usa `Ramon::Roteiro::Teste`: o motor de verdade num lead descartável dentro de uma transação desfeita; o estado vai e volta pelo navegador a cada mensagem. No front: `RoteiroEditor` + `RoteiroPassoForm` (dentro de Playbooks), `RoteiroDoLead` (painel e Testar), tudo no kit `helpers/ui.js`.

**Tech Stack:** Rails 7.1 (fork Chatwoot 4.15.1), RSpec; Vue 3.5 `<script setup>`, Vuex 4, Tailwind, Vitest; Captain tools (`enterprise/lib/captain/tools/`).

**Spec:** `docs/superpowers/specs/2026-10-13-roteiro-da-tese-design.md` §3.6–3.8 e §6 (F2) + plano da F1 `docs/superpowers/plans/2026-10-13-roteiro-f1-motor.md` (decisões do grilling de 13/10 no topo valem sobre a spec).

## Decisões que tomei sem perguntar (revisar)

1. **Nome na tela = "Roteiro da IA"** (aba, cartão do painel, i18n `RAMON.ROTEIRO_IA`) — o Playbook já tem a seção "Roteiro da reunião"; "Roteiro" sozinho confundiria.
2. **Cadastro na tela Playbooks** (Intranet → Configurações → Playbooks, só admin): aba "Roteiro da IA" no detalhe da tese + cartão "Passos comuns" no topo da tela (spec §3.8.1–2). Não criei atalho na área Inteligência — a tese já é editada ali.
3. **Reordenar por setas ↑↓**, não arrastando (spec §3.8.1 diz "arrastando") — é o gesto que a tela Playbooks já usa; sem biblioteca nova.
4. **Passo abre "sanfona" na própria lista**, não gaveta lateral — mesmo padrão de edição inline do Playbooks, menos código.
5. **Salvar o passo por botão** "Salvar passo" (não no blur como os itens do Playbook) — as saídas são uma lista; salvar pela metade bateria na validação.
6. **Chave travada depois de criada** (sugerida do título ao criar) — respostas dos leads, "vai para" e campos de calculadora apontam pela chave; trocar quebraria leads em andamento.
7. **"Vai para" e campos da calculadora escolhidos numa lista dos passos que já existem**; passo comum só aponta para comum. Para apontar adiante, crie o destino antes.
8. **Validação no salvar da tela (controller), não no model** (desvio 6 da F1) — o seed da F4 cria os passos em ordem e um "vai para" adiante ainda não existe na hora.
9. **Chave não pode repetir entre passos comuns e passos de tese** — o motor junta as duas listas pela chave (resposta de um sobrescreveria a do outro).
10. **Remover passo que outro aponta é recusado** com a lista de quem aponta.
11. **Reabrir pelo painel:** lead ganho ou perdido não reabre por ali (perdido: tirar do Perdido no funil, que já reabre — F1); ao reabrir, as sugestões **pendentes do roteiro** no Cockpit (Perdido/etapa) são descartadas, senão aprovar depois mandaria para o Perdido um lead que voltou a ser qualificado. Qualquer um que edita o lead (admin ou agente) pode reabrir.
12. **Sem botão "reiniciar roteiro"** (F1 deixou "se fizer falta") — YAGNI.
13. **Painel com a mesma cara da Qualificação viva aprovada (R2 de 05/10):** à vista só o passo atual e os a perguntar; respondidos atrás do "✓ N respondidos"; pulados pelo "vai para" aparecem como "não perguntado". Tese só com passos comuns: mostra o roteiro comum **e** o checklist de sempre.
14. **Painel atualiza sozinho** pelo `roteiro_versao` (hash do estado) no broadcast do lead — o broadcast não leva o jsonb.
15. **Testar com tese:** lead descartável numa transação desfeita (o motor real roda); simula conversa **fora do piloto total** (Perdido vira sugestão → a IA ouve "aguardando a equipe"); trocar a tese no Testar zera o roteiro do teste.
16. **Palavras-chave:** campo no cabeçalho da tese, separado por vírgula. Só passa a ter efeito na F3 (tese automática).
17. **Aviso âmbar no formulário do passo:** orientação e base da resposta viram fala da IA com o cliente.
18. **Catálogo das calculadoras (campos + resultados) no Ruby**, servido pela API — uma fonte só para a tela e a validação.
19. **Fora desta fatia:** configurações da caixa (tese/modo padrão — F3, spec §6); selo "roteiro" nas sugestões do Cockpit; selo do desfecho no card do funil (viram sugestões na página de prints).

**Perguntas abertas:** nenhuma bloqueante. Dependência a confirmar no smoke: o Testar com tese só conversa pelo roteiro depois que a skill de triagem nova (texto da F1, gate do Eduardo) estiver ativada com o `seed[2]`.

## Global Constraints

- **Começar só com a F1 mergeada** em `origin/ramon`. Branch `feat/roteiro-f2-telas` criada de `origin/ramon` (`git fetch origin && git switch -c feat/roteiro-f2-telas origin/ramon`), no worktree `ramon-hub-wt-roteiro`. PR com base `ramon`.
- **Interfaces da F1 que esta fatia consome** — conferir no código mergeado antes da Task 1; se mudaram, adaptar as chamadas e anotar no PR: `RoteiroPasso` (`ramon_roteiro_passos`; `TIPOS`, `ACOES`, scope `comuns`, default order `position, id`, `normalizes :calculadora`), `Ramon::Roteiro.passos/estado/proximo/atual/registrar/reabrir(lead, se: nil)/descrever/resumo`, `Ramon::Roteiro::Calculadoras::NOMES`, tools `Captain::Tools::RoteiroPassoAtualTool` (`SEM_ROTEIRO`) e `RoteiroRegistrarTool`, colunas `theses.palavras_chave`, sugestões com `payload['origem'] = 'roteiro'`.
- **Sem migração nesta fatia** (as colunas vieram na F1). Deploy = só imagem.
- Sem Ruby local (Smart App Control): Ruby é validado pelo **CI**; lint antes do push com `rubocop-vps <arquivos>` (Git Bash, ~10 s). Limites: `Metrics/MethodLength` 19, `Metrics/AbcSize` 26, `Metrics/ClassLength` 175, linha 150, `RSpec/MultipleExpectations` 7, `RSpec/ExampleLength` 50.
- **Specs em `spec/enterprise` não rodam no CI** (o CI apaga `enterprise/`). Toda regra nova fica em `app/` (`app/services/ramon/roteiro/`, controllers em `app/controllers/api/v1/accounts/`); o que muda em `enterprise/` é fino e é provado pelo `rails runner` da Task 8.
- JS: `node_modules/.bin/eslint <arquivos>` e `node_modules/.bin/vitest run --no-cache <specs>`. Se o vitest reclamar de `server.fs.strict` (node_modules é junção), rodar com `--config tmp/vitest.local.config.ts` copiado de outro worktree do hub (`server.fs.strict=false`).
- Vue: Composition API `<script setup>`; **evento custom sempre camelCase** (`mudou`, `salvar`, `cancelar`, `reaberto`); Tailwind só; peles do kit `app/javascript/dashboard/routes/dashboard/ramon/helpers/ui.js` (`CARTAO`, `SECAO`, `CAMPO`, `SELECT`, `TEXTAREA`, `ROTULO`, `TITULO`, `CHIP`+`TOM`, `AVISO`, `ABA`); botões = `dashboard/components-next/button/Button.vue`; fundo colorido **sempre translúcido** (`TOM.*`); nada de creme/bege; dentro de cartão não há cartão (vira `SECAO`).
- i18n em `app/javascript/dashboard/i18n/locale/en/ramon.json` **e** `pt_BR/ramon.json`, bloco novo `RAMON.ROTEIRO_IA` (todo criado na Task 3).
- **Texto que fala com cliente só ativa com o aprovado do Eduardo:** as telas não trazem nenhum roteiro pronto (conteúdo real = F4). A story dos prints usa textos de exemplo marcados como fictícios.
- **Visual:** prints claro/escuro aprovados pelo Eduardo **antes do PR** (spec §3.8; método do hub: harness Vite + Chrome headless → `comparar.html`); deploy por pacote.
- Cadastro de passos = **admin**; leitura (index, painel) = admin e agente.
- Commits: Conventional Commits, sem citar Claude no assunto, terminando com o rodapé de atribuição da sessão que executar.

## Review Focus

1. **Admin salva "vai para" (ou campo de calculadora) apontando para passo que não existe, ou remove um passo que outro aponta** → recusa com a mensagem dizendo qual passo, e nada é salvo/removido (Task 1, request spec).
2. **Chave repetida entre passo comum e passo de tese, ou tentativa de trocar a chave de um passo salvo** → recusa na colisão; a chave do passo salvo não muda (Task 1, request spec; Task 3, campo travado).
3. **Reabrir com o Perdido do roteiro ainda pendente no Cockpit** → a sugestão é descartada junto (senão aprovar depois perderia um lead reaberto); lead ganho/perdido ou roteiro em andamento → 422 com a dica, nada muda (Task 2, request spec).
4. **A IA registra passos enquanto o painel está aberto; broadcasts de outras mudanças do lead chegam o tempo todo** → o painel recarrega só quando `roteiro_versao` muda, e resposta velha não sobrescreve a nova (Task 2, painel spec; Task 5, QualificacaoViva spec).
5. **Testar com tese, inclusive com valor inválido ou desfecho "equipe"** → nada fica gravado (lead, histórico, sugestão, sino) e o estado volta para a tela; erro de valor devolve o texto do erro e o estado não muda (Task 6, spec do `Teste`).

---

### Task 1: API do cadastro de passos (com conferência no salvar)

**Files:**
- Modify: `app/services/ramon/roteiro/calculadoras.rb` (catálogo)
- Create: `app/services/ramon/roteiro/conferencia.rb`
- Create: `app/policies/roteiro_passo_policy.rb`
- Create: `app/controllers/api/v1/accounts/roteiro_passos_controller.rb`
- Modify: `config/routes.rb` (depois do bloco `resources :theses … end`)
- Create: `spec/requests/api/v1/accounts/roteiro_passos_spec.rb`

**Interfaces:**
- Consumes: `RoteiroPasso` e factory `:roteiro_passo` (F1), `Ramon::Roteiro::Calculadoras` (F1)
- Produces:
  - `Ramon::Roteiro::Calculadoras::CATALOGO` — `{ 'periodo_de_graca' => { campos: [String], resultados: [String] }, … }`; `NOMES = CATALOGO.keys`
  - `Ramon::Roteiro::Conferencia.erros(passo) -> Array<String>` (vazio = pode salvar) e `.referencias(passo) -> Array<String>` (títulos de quem aponta)
  - `GET /api/v1/accounts/:account_id/roteiro_passos` → `{ payload: [passo], calculadoras: CATALOGO }`; `passo` = `{ id, thesis_id, position, chave, titulo, orientacao, tipo_resposta, opcoes, calculadora, calculadora_campos, saidas, edited }`
  - `POST …/roteiro_passos` (corpo: campos do passo + `thesis_id` ou nulo) → passo; `PATCH …/roteiro_passos/:id` → passo (ignora `chave`); `DELETE …/roteiro_passos/:id` → 200 ou 422 `{ error }`; `POST …/roteiro_passos/reorder { ids }` → 200
  - Erros de salvar: 422 `{ error: "…; …" }` (conferência) ou 422 `{ message }` (validação do model)

- [ ] **Step 1: Escrever o request spec (falha)**

`spec/requests/api/v1/accounts/roteiro_passos_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Roteiro passos API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:thesis) { create(:thesis, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/roteiro_passos" }

  def criar(params, user = admin)
    post url, params: params, headers: user.create_new_auth_token, as: :json
  end

  it 'lista os passos da conta e o catálogo das calculadoras (agente lê)' do
    create(:roteiro_passo, account: account, thesis: nil, chave: 'nome')
    get url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['payload'].pluck('chave')).to eq(['nome'])
    expect(response.parsed_body.dig('calculadoras', 'periodo_de_graca', 'campos')).to include('ultimo_vinculo')
  end

  it 'cria passo comum e passo da tese no fim do escopo, marcados como editados' do
    criar({ titulo: 'Nome', chave: 'nome', tipo_resposta: 'texto' })
    expect(response.parsed_body).to include('thesis_id' => nil, 'position' => 0, 'edited' => true)
    criar({ titulo: 'Recebeu', chave: 'recebeu', tipo_resposta: 'sim_nao', thesis_id: thesis.id })
    expect(response.parsed_body).to include('thesis_id' => thesis.id, 'position' => 0)
  end

  it 'barra agente no cadastro' do
    criar({ titulo: 'Nome', chave: 'nome' }, agent)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'recusa destino e campo de calculadora sem passo, e chave repetida entre comuns e tese' do
    create(:roteiro_passo, account: account, thesis: nil, chave: 'nome')
    criar({ titulo: 'X', chave: 'x', thesis_id: thesis.id, tipo_resposta: 'sim_nao',
            saidas: [{ id: 's1', quando: 'sim', acao: 'ir_para', alvo: 'sumiu' }] })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include("'sumiu' não existe")

    criar({ titulo: 'Graça', chave: 'graca', thesis_id: thesis.id, tipo_resposta: 'data', calculadora: 'periodo_de_graca',
            calculadora_campos: { ultimo_vinculo: 'graca', evento: 'acidente', idade: 'graca' } })
    expect(response.parsed_body['error']).to include("passo 'acidente'").and include("campo 'idade'")

    criar({ titulo: 'Nome', chave: 'nome', thesis_id: thesis.id })
    expect(response.parsed_body['error']).to include('já existe nos passos comuns')
    expect(RoteiroPasso.count).to eq(1)
  end

  it 'passo da tese aponta para comum e para si; passo comum não aponta para passo de tese' do
    create(:roteiro_passo, account: account, thesis: nil, chave: 'nome')
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'renda')
    criar({ titulo: 'X', chave: 'x', thesis_id: thesis.id, tipo_resposta: 'sim_nao',
            saidas: [{ id: 's1', quando: 'sim', acao: 'ir_para', alvo: 'nome' }, { id: 's2', quando: '*', acao: 'ir_para', alvo: 'x' }] })
    expect(response).to have_http_status(:success)

    criar({ titulo: 'Comum', chave: 'comum', tipo_resposta: 'sim_nao',
            saidas: [{ id: 's1', quando: '*', acao: 'ir_para', alvo: 'renda' }] })
    expect(response.parsed_body['error']).to include("'renda' não existe")
  end

  it 'erro do model volta 422 com a mensagem (motivo obrigatório)' do
    criar({ titulo: 'X', chave: 'x', tipo_resposta: 'sim_nao', saidas: [{ id: 's1', quando: 'sim', acao: 'humano' }] })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['message']).to include('motivo obrigatório')
  end

  it 'editar não troca a chave e marca editado' do
    passo = create(:roteiro_passo, account: account, thesis: thesis, chave: 'renda', titulo: 'Renda')
    patch "#{url}/#{passo.id}", params: { titulo: 'Renda da casa', chave: 'outra' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(passo.reload).to have_attributes(titulo: 'Renda da casa', chave: 'renda', edited: true)
  end

  it 'não remove passo apontado por outro; remove o livre' do
    alvo = create(:roteiro_passo, account: account, thesis: thesis, chave: 'renda', titulo: 'Renda')
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'recebeu', titulo: 'Recebeu',
                           saidas: [{ 'id' => 's1', 'quando' => 'sim', 'acao' => 'ir_para', 'alvo' => 'renda' }])
    delete "#{url}/#{alvo.id}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('Recebeu')

    livre = create(:roteiro_passo, account: account, thesis: thesis, chave: 'livre')
    delete "#{url}/#{livre.id}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(RoteiroPasso.exists?(livre.id)).to be(false)
  end

  it 'reordena pela lista de ids' do
    a = create(:roteiro_passo, account: account, thesis: thesis, position: 0)
    b = create(:roteiro_passo, account: account, thesis: thesis, position: 1)
    post "#{url}/reorder", params: { ids: [b.id, a.id] }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect([b.reload.position, a.reload.position]).to eq([0, 1])
  end
end
```

- [ ] **Step 2: Catálogo das calculadoras**

Em `app/services/ramon/roteiro/calculadoras.rb`, trocar a linha

```ruby
  NOMES = %w[periodo_de_graca renda_per_capita prescricao_5_anos meses_ate_65 data_prevista_parto prazo_inss].freeze
```

por:

```ruby
  # Campos que cada conta lê e resultados que devolve: a tela do roteiro (F2) mostra e a Conferencia valida.
  CATALOGO = {
    'periodo_de_graca' => { campos: %w[ultimo_vinculo evento mais_de_120 desemprego facultativa], resultados: %w[dentro fora depende] },
    'renda_per_capita' => { campos: %w[renda_total moradores], resultados: %w[abaixo acima depende] },
    'prescricao_5_anos' => { campos: %w[data], resultados: %w[dentro ultimo_ano prescrito depende] },
    'meses_ate_65' => { campos: %w[nascimento], resultados: %w[ja_tem_65 menos_de_65 depende] },
    'data_prevista_parto' => { campos: %w[semanas], resultados: %w[ja_pode_pedir aguardar depende] },
    'prazo_inss' => { campos: %w[requerimento pericia], resultados: %w[aguardar forcar_julgamento depende] }
  }.freeze
  NOMES = CATALOGO.keys.freeze
```

(Conferir contra o código da F1: os nomes dos campos são as chaves que cada método lê em `campos['…']`; os resultados, os `res('…')` que ele devolve. Se a F1 mudou algum, o catálogo segue o código.)

- [ ] **Step 3: Conferência**

`app/services/ramon/roteiro/conferencia.rb`:

```ruby
# Conferência do roteiro no salvar da tela (F2; desvio 6 da F1): "vai para" e campos da calculadora apontando para
# passos que existem, e chave sem repetir entre os comuns e a tese (o motor junta as duas listas pela chave).
# Fica fora do model porque o seed (F4) cria os passos em ordem — um "vai para" adiante ainda não existe na hora.
module Ramon::Roteiro::Conferencia
  module_function

  # @return [Array<String>] vazio = pode salvar
  def erros(passo)
    chaves = chaves_alcancaveis(passo)
    destinos = Array(passo.saidas).filter_map { |saida| saida['alvo'] if saida['acao'] == 'ir_para' }
    campos = (passo.calculadora_campos || {}).to_h
    [*(destinos.compact_blank - chaves).map { |chave| "o passo de destino '#{chave}' não existe neste roteiro" },
     *(campos.values.compact_blank - chaves).map { |chave| "a calculadora usa o passo '#{chave}', que não existe neste roteiro" },
     *campos_fora_da_calculadora(passo, campos.keys), colisao(passo)].compact.uniq
  end

  # Quem aponta para este passo ("vai para" ou campo da calculadora): remover quebraria o roteiro deles.
  def referencias(passo)
    escopo = RoteiroPasso.where(account_id: passo.account_id).where.not(id: passo.id)
    escopo = escopo.where(thesis_id: passo.thesis_id) if passo.thesis_id
    escopo.select { |outro| aponta?(outro, passo.chave) }.map(&:titulo)
  end

  # Passo comum só alcança os comuns (roda em toda tese); passo da tese alcança os comuns e os da tese.
  def chaves_alcancaveis(passo)
    escopo = RoteiroPasso.where(account_id: passo.account_id, thesis_id: [nil, passo.thesis_id].uniq)
    escopo.where.not(id: passo.id).pluck(:chave) << passo.chave
  end

  def campos_fora_da_calculadora(passo, nomes)
    return [] if passo.calculadora.blank?

    validos = Ramon::Roteiro::Calculadoras::CATALOGO.dig(passo.calculadora, :campos) || []
    (nomes.map(&:to_s) - validos).map { |nome| "a calculadora não tem o campo '#{nome}'" }
  end

  def colisao(passo)
    outros = RoteiroPasso.where(account_id: passo.account_id, chave: passo.chave).where.not(id: passo.id)
    return "a chave '#{passo.chave}' já existe nos passos comuns" if passo.thesis_id && outros.comuns.exists?

    "a chave '#{passo.chave}' já existe no roteiro de uma tese" if passo.thesis_id.nil? && outros.where.not(thesis_id: nil).exists?
  end

  def aponta?(outro, chave)
    Array(outro.saidas).any? { |saida| saida['acao'] == 'ir_para' && saida['alvo'] == chave } ||
      (outro.calculadora_campos || {}).value?(chave)
  end
end
```

- [ ] **Step 4: Policy, controller e rota**

`app/policies/roteiro_passo_policy.rb`:

```ruby
# Passos do roteiro da tese (F2): todos leem; só admin cadastra (mesma regra das teses).
class RoteiroPassoPolicy < ApplicationPolicy
  def index? = @account_user.administrator? || @account_user.agent?
  def create? = @account_user.administrator?
  def update? = @account_user.administrator?
  def destroy? = @account_user.administrator?
  def reorder? = @account_user.administrator?
end
```

`app/controllers/api/v1/accounts/roteiro_passos_controller.rb`:

```ruby
# Cadastro dos passos do roteiro da tese (F2) — tela Playbooks: passos comuns (thesis_id nulo) e por tese.
# Salvar passa pela Ramon::Roteiro::Conferencia; editado na tela = edited (o seed da F4 não sobrescreve).
# A chave não muda depois de criada: respostas dos leads e "vai para" apontam por ela.
class Api::V1::Accounts::RoteiroPassosController < Api::V1::Accounts::BaseController
  CAMPOS = %w[id thesis_id position chave titulo orientacao tipo_resposta opcoes calculadora calculadora_campos saidas edited].freeze

  before_action :check_authorization
  before_action :fetch_passo, only: [:update, :destroy]

  def index
    render json: { payload: escopo.map { |passo| passo.slice(*CAMPOS) }, calculadoras: Ramon::Roteiro::Calculadoras::CATALOGO }
  end

  def create
    salvar(escopo.new(passo_params.merge(thesis: tese, position: proxima_posicao, edited: true)))
  end

  def update
    @passo.assign_attributes(passo_params.except('chave').merge(edited: true))
    salvar(@passo)
  end

  def destroy
    usam = Ramon::Roteiro::Conferencia.referencias(@passo)
    return render_erro("Não dá para remover: #{usam.join(', ')} aponta para este passo.") if usam.any?

    @passo.destroy!
    head :ok
  end

  def reorder
    ActiveRecord::Base.transaction do
      Array(params[:ids]).each_with_index { |id, i| escopo.find(id).update!(position: i) }
    end
    head :ok
  end

  private

  def escopo
    RoteiroPasso.where(account_id: Current.account.id)
  end

  def fetch_passo
    @passo = escopo.find(params[:id])
  end

  def tese
    Current.account.theses.find(params[:thesis_id]) if params[:thesis_id].present?
  end

  def proxima_posicao
    (escopo.where(thesis_id: params[:thesis_id].presence).maximum(:position) || -1) + 1
  end

  def salvar(passo)
    erros = Ramon::Roteiro::Conferencia.erros(passo)
    return render_erro(erros.join('; ')) if erros.any?

    passo.save!
    render json: passo.slice(*CAMPOS)
  end

  def render_erro(texto)
    render json: { error: texto }, status: :unprocessable_entity
  end

  def passo_params
    params.permit(:titulo, :chave, :orientacao, :tipo_resposta, :calculadora,
                  opcoes: [], calculadora_campos: {},
                  saidas: [:id, :quando, :acao, :alvo, :motivo, :motivo_perda, :mensagem, { efeitos: %i[etiqueta etapa] }]).to_h
  end
end
```

(Se o `rubocop-vps -a` reformatar o `permit`, aceitar o formato dele.)

Em `config/routes.rb`, logo depois do bloco

```ruby
          resources :theses, except: [:new, :edit] do
            collection { post :reorder }
            resources :thesis_items, only: [:create, :update, :destroy] do
              collection { post :reorder }
            end
          end
```

acrescentar:

```ruby
          resources :roteiro_passos, only: [:index, :create, :update, :destroy] do
            collection { post :reorder }
          end
```

- [ ] **Step 5: Lint + commit** (o spec roda no CI — Task 8)

```bash
rubocop-vps app/services/ramon/roteiro/calculadoras.rb app/services/ramon/roteiro/conferencia.rb app/policies/roteiro_passo_policy.rb \
  app/controllers/api/v1/accounts/roteiro_passos_controller.rb config/routes.rb spec/requests/api/v1/accounts/roteiro_passos_spec.rb
git add app/services/ramon/roteiro/calculadoras.rb app/services/ramon/roteiro/conferencia.rb app/policies/roteiro_passo_policy.rb \
  app/controllers/api/v1/accounts/roteiro_passos_controller.rb config/routes.rb spec/requests/api/v1/accounts/roteiro_passos_spec.rb
git commit -m "feat(roteiro): API do cadastro de passos com conferência de destinos, campos e chave"
```

---

### Task 2: API do roteiro no painel do lead + reabrir + `roteiro_versao`

**Files:**
- Create: `app/services/ramon/roteiro/painel.rb`
- Create: `app/controllers/api/v1/accounts/lead_roteiros_controller.rb`
- Modify: `config/routes.rb` (bloco `member do` de `resources :leads`)
- Modify: `app/models/concerns/lead_comercial.rb` (`comercial_event_data` + `roteiro_versao`)
- Modify: `app/views/api/v1/accounts/leads/_lead.json.jbuilder`
- Create: `spec/services/ramon/roteiro/painel_spec.rb`
- Create: `spec/requests/api/v1/accounts/lead_roteiros_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Roteiro.atual/passos/registrar/reabrir` (F1)
- Produces:
  - `Ramon::Roteiro::Painel.montar(lead) -> Hash | nil` — `{ 'desfecho', 'motivo', 'decisivo', 'aguarda_equipe' (bool), 'so_comuns' (bool), 'passos' => [{ 'chave', 'titulo', 'comum' (bool), 'situacao' ('respondido'|'atual'|'pendente'|'fora'), 'valor', 'saida', 'calc' ({ 'resultado', 'detalhe' } | nil) }] }`; `nil` = lead sem roteiro
  - `GET /api/v1/accounts/:account_id/leads/:id/roteiro` → painel ou `null`
  - `POST /api/v1/accounts/:account_id/leads/:id/reabrir_roteiro` → painel novo; 422 `{ error }` se ganho/perdido ou sem desfecho
  - `Lead#roteiro_versao -> String | nil` (MD5 do estado); vai no broadcast (`push_event_data`) e no JSON do lead

- [ ] **Step 1: Specs (falham)**

`spec/services/ramon/roteiro/painel_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Roteiro::Painel do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }
  let(:novo) { account.lead_stages.find_by!(name: 'Novo') }
  let(:lead) { create(:lead, account: account, thesis: thesis, lead_stage: novo) }

  before do
    create(:roteiro_passo, account: account, thesis: nil, chave: 'tem_advogado', position: 0, titulo: 'Tem advogado',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'desqualificar', 'motivo' => 'tem advogado' },
                                    { 'id' => 'nao', 'quando' => 'nao', 'acao' => 'seguir' }])
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'recebeu', position: 1, titulo: 'Recebeu',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'ir_para', 'alvo' => 'renda' },
                                    { 'id' => 'nao', 'quando' => 'nao', 'acao' => 'seguir' }])
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'nascimento', position: 2, titulo: 'Nascimento',
                           tipo_resposta: 'data', calculadora: 'meses_ate_65', calculadora_campos: { 'nascimento' => 'nascimento' })
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'renda', position: 3, titulo: 'Renda', tipo_resposta: 'numero')
  end

  def situacoes
    described_class.montar(lead.reload)['passos'].to_h { |linha| [linha['chave'], linha['situacao']] }
  end

  it 'lead sem tese = sem roteiro' do
    expect(described_class.montar(create(:lead, account: account, lead_stage: novo))).to be_nil
  end

  it 'comuns e tese na ordem, com o passo atual e o resto a perguntar' do
    painel = described_class.montar(lead)
    expect(painel['passos'].pluck('chave')).to eq(%w[tem_advogado recebeu nascimento renda])
    expect(painel['passos'].first).to include('comum' => true, 'situacao' => 'atual')
    expect(painel).to include('desfecho' => nil, 'so_comuns' => false, 'aguarda_equipe' => false)
  end

  it 'pulado pelo "vai para" fica como não perguntado' do
    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'nao')
    Ramon::Roteiro.registrar(lead.reload, chave: 'recebeu', valor: 'sim')
    expect(situacoes).to eq('tem_advogado' => 'respondido', 'recebeu' => 'respondido', 'nascimento' => 'fora', 'renda' => 'atual')
  end

  it 'traz o valor e o resultado da calculadora' do
    Ramon::Roteiro.registrar(lead, chave: 'nascimento', valor: '13/10/1950')
    linha = described_class.montar(lead.reload)['passos'].find { |item| item['chave'] == 'nascimento' }
    expect(linha).to include('valor' => '1950-10-13', 'situacao' => 'respondido')
    expect(linha['calc']).to include('resultado' => 'ja_tem_65')
  end

  it 'desfecho com motivo, passo que decidiu, aguardando a equipe e o resto não perguntado' do
    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'sim') # lead sem conversa: Perdido vira sugestão
    painel = described_class.montar(lead.reload)
    expect(painel).to include('desfecho' => 'desqualificado', 'motivo' => 'tem advogado', 'decisivo' => 'tem_advogado',
                              'aguarda_equipe' => true)
    expect(painel['passos'].pluck('situacao')).to eq(%w[respondido fora fora fora])
  end

  it 'tese sem passos próprios: só os comuns (so_comuns)' do
    outro = create(:lead, account: account, thesis: create(:thesis, account: account), lead_stage: novo)
    expect(described_class.montar(outro)).to include('so_comuns' => true)
  end

  it 'roteiro_versao do lead muda a cada registro' do
    expect(lead.roteiro_versao).to be_nil
    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'nao')
    primeira = lead.reload.roteiro_versao
    Ramon::Roteiro.registrar(lead, chave: 'recebeu', valor: 'nao')
    expect(primeira).to be_present
    expect(lead.reload.roteiro_versao).not_to eq(primeira)
    expect(lead.push_event_data[:roteiro_versao]).to eq(lead.roteiro_versao)
  end
end
```

`spec/requests/api/v1/accounts/lead_roteiros_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Lead roteiro API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:thesis) { create(:thesis, account: account) }
  let(:novo) { account.lead_stages.find_by!(name: 'Novo') }
  let(:lead) { create(:lead, account: account, thesis: thesis, lead_stage: novo) }
  let(:base) { "/api/v1/accounts/#{account.id}/leads/#{lead.id}" }

  before do
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'tem_advogado', position: 0, titulo: 'Tem advogado',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'desqualificar', 'motivo' => 'tem advogado' },
                                    { 'id' => 'nao', 'quando' => 'nao', 'acao' => 'seguir' }])
  end

  it 'mostra o roteiro do lead; sem tese = null' do
    get "#{base}/roteiro", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['passos'].first).to include('chave' => 'tem_advogado', 'situacao' => 'atual')

    lead.update!(thesis: nil)
    get "#{base}/roteiro", headers: agent.create_new_auth_token
    expect(response.parsed_body).to be_nil
  end

  it 'reabrir volta no passo que decidiu e descarta só as sugestões do roteiro' do
    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'sim') # sem conversa: Perdido vira sugestão no Cockpit
    outra = account.copilot_suggestions.create!(lead: lead, kind: 'acao', status: 'pending', payload: { 'acao' => 'tarefa' })

    post "#{base}/reabrir_roteiro", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['passos'].first['situacao']).to eq('atual')
    expect(account.copilot_suggestions.pending.where(lead_id: lead.id)).to eq([outra])
  end

  it 'não reabre roteiro em andamento nem lead perdido' do
    post "#{base}/reabrir_roteiro", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('não está encerrado')

    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'sim')
    lead.reload.update!(lead_stage: account.lead_stages.find_by!(is_lost: true), lost_reason: 'Outro')
    post "#{base}/reabrir_roteiro", headers: agent.create_new_auth_token
    expect(response.parsed_body['error']).to include('ganho ou perdido')
    expect(Ramon::Roteiro.atual(lead.reload)[:estado]['desfecho']).to eq('desqualificado')
  end
end
```

- [ ] **Step 2: Painel**

`app/services/ramon/roteiro/painel.rb`:

```ruby
# Painel do lead e Testar (F2): o roteiro passo a passo — respondido, atual, a perguntar ou não perguntado (pulado
# pelo "vai para" ou depois do desfecho) — com o valor, o resultado da calculadora e o desfecho com motivo.
# nil = lead sem roteiro (o painel mostra a qualificação de sempre).
module Ramon::Roteiro::Painel
  module_function

  def montar(lead)
    atual = Ramon::Roteiro.atual(lead)
    return if atual.nil?

    est = atual[:estado]
    lista = Ramon::Roteiro.passos(lead)
    cursor = lista.index { |passo| passo.chave == est['cursor'] } || 0
    passos = lista.each_with_index.map { |passo, i| linha(passo, est, situacao(passo, i, cursor, atual[:passo], est)) }
    { 'desfecho' => est['desfecho'], 'motivo' => est['motivo'], 'decisivo' => est['decisivo'],
      'aguarda_equipe' => est['aguarda_equipe'] == true, 'so_comuns' => lista.none?(&:thesis_id), 'passos' => passos }
  end

  def situacao(passo, indice, cursor, passo_atual, est)
    return 'respondido' if est['respostas'].key?(passo.chave)
    return 'atual' if passo_atual&.chave == passo.chave
    return 'fora' if est['desfecho'] || indice < cursor

    'pendente'
  end

  def linha(passo, est, situacao)
    resposta = est['respostas'][passo.chave] || {}
    { 'chave' => passo.chave, 'titulo' => passo.titulo, 'comum' => passo.thesis_id.nil?, 'situacao' => situacao,
      'valor' => resposta['valor'], 'saida' => resposta['saida'], 'calc' => resposta['calc'] }
  end
end
```

- [ ] **Step 3: Controller e rotas**

`app/controllers/api/v1/accounts/lead_roteiros_controller.rb`:

```ruby
# Roteiro da tese no painel do lead (F2): o passo a passo e o "Reabrir roteiro".
class Api::V1::Accounts::LeadRoteirosController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  def show
    authorize(@lead, :show?)
    render json: Ramon::Roteiro::Painel.montar(@lead)
  end

  # Volta no passo que decidiu (Ramon::Roteiro.reabrir, F1). Lead ganho ou perdido não reabre por aqui — tirar do
  # Perdido no funil já reabre. Sugestões do roteiro pendentes no Cockpit deixam de valer (aprovar o Perdido depois
  # perderia um lead que voltou a ser qualificado).
  def reabrir
    authorize(@lead, :update?)
    return erro('Lead ganho ou perdido: o roteiro não reabre por aqui.') if @lead.won_at || @lead.lost_at
    return erro('O roteiro deste lead não está encerrado.') unless Ramon::Roteiro.reabrir(@lead)

    Current.account.copilot_suggestions.pending.where(lead_id: @lead.id).where("payload->>'origem' = 'roteiro'")
           .find_each { |sugestao| sugestao.update!(status: 'dismissed') }
    render json: Ramon::Roteiro::Painel.montar(@lead.reload)
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:id])
  end

  def erro(texto)
    render json: { error: texto }, status: :unprocessable_entity
  end
end
```

Em `config/routes.rb`, no `member do` de `resources :leads`, depois de `post :reuniao`:

```ruby
              get :roteiro, to: 'lead_roteiros#show'
              post :reabrir_roteiro, to: 'lead_roteiros#reabrir'
```

- [ ] **Step 4: `roteiro_versao` no broadcast e no JSON do lead**

Em `app/models/concerns/lead_comercial.rb`, trocar

```ruby
      zapsign_status: custom_attributes&.dig('zapsign', 'status'),
      zapsign_assinado_em: custom_attributes&.dig('zapsign', 'assinado_em')
    }
  end
```

por:

```ruby
      zapsign_status: custom_attributes&.dig('zapsign', 'status'),
      zapsign_assinado_em: custom_attributes&.dig('zapsign', 'assinado_em'),
      # o painel recarrega o roteiro quando muda (o broadcast não leva o jsonb)
      roteiro_versao: roteiro_versao
    }
  end

  # Assinatura do estado do roteiro da tese (F2): muda a cada resposta registrada ou roteiro reaberto.
  def roteiro_versao
    estado = custom_attributes&.dig('roteiro')
    estado && Digest::MD5.hexdigest(estado.to_json)
  end
```

Em `app/views/api/v1/accounts/leads/_lead.json.jbuilder`, logo depois de `json.custom_attributes lead.custom_attributes unless local_assigns[:slim]`:

```ruby
json.roteiro_versao lead.roteiro_versao
```

- [ ] **Step 5: Lint + commit**

```bash
rubocop-vps app/services/ramon/roteiro/painel.rb app/controllers/api/v1/accounts/lead_roteiros_controller.rb config/routes.rb \
  app/models/concerns/lead_comercial.rb app/views/api/v1/accounts/leads/_lead.json.jbuilder \
  spec/services/ramon/roteiro/painel_spec.rb spec/requests/api/v1/accounts/lead_roteiros_spec.rb
git add app/services/ramon/roteiro/painel.rb app/controllers/api/v1/accounts/lead_roteiros_controller.rb config/routes.rb \
  app/models/concerns/lead_comercial.rb app/views/api/v1/accounts/leads/_lead.json.jbuilder \
  spec/services/ramon/roteiro/painel_spec.rb spec/requests/api/v1/accounts/lead_roteiros_spec.rb
git commit -m "feat(roteiro): roteiro passo a passo do lead, reabrir pelo painel e versão no broadcast"
```

---

### Task 3: Editor de passos (componentes + i18n)

**Files:**
- Create: `app/javascript/dashboard/api/roteiroPassos.js`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/helpers/roteiro.js`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/roteiro.spec.js`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/roteiro/RoteiroPassoForm.vue`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/roteiro/RoteiroEditor.vue`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/roteiro/specs/RoteiroEditor.spec.js`
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`, `app/javascript/dashboard/i18n/locale/en/ramon.json` (bloco `ROTEIRO_IA` inteiro — usado também nas Tasks 4–6)

**Interfaces:**
- Consumes: API da Task 1; getters `leadConfig/getStages` (`{ id, name, is_won, is_lost }`) e `leadConfig/getLostReasons` (`{ id, name }`)
- Produces:
  - `RoteiroPassosAPI` (`get()`, `create(data)`, `update(id, data)`, `delete(id)`, `reorder(ids)`)
  - helpers: `TIPOS`, `ACOES`, `slugChave(texto)`, `textoParaLista(texto)`, `listaParaTexto(lista)`, `passosDe(todos, thesisId)`, `destinosDe(todos, thesisId)`, `sugestoesQuando(passo, calculadoras)`, `novaSaida(saidas)`, `limparSaida(saida)`, `payloadDoPasso(rascunho)`
  - `<RoteiroEditor :thesis-id="Number|null" :passos="Array (todos da conta)" :calculadoras="Object" @mudou />`
  - `<RoteiroPassoForm :passo="Object|null" :destinos="Array" :calculadoras="Object" :salvando="Boolean" @salvar="payload" @cancelar />`
  - testids: `roteiro-editor`, `roteiro-passo-linha`, `roteiro-passo-abrir`, `roteiro-passo-subir`, `roteiro-passo-descer`, `roteiro-passo-remover`, `roteiro-novo`, `roteiro-form`, `roteiro-titulo`, `roteiro-chave`, `roteiro-orientacao`, `roteiro-tipo`, `roteiro-opcoes`, `roteiro-calculadora`, `roteiro-campo-calculadora`, `roteiro-saida`, `roteiro-saida-quando`, `roteiro-saida-acao`, `roteiro-saida-alvo`, `roteiro-saida-motivo`, `roteiro-saida-motivo-perda`, `roteiro-saida-mensagem`, `roteiro-saida-etiqueta`, `roteiro-saida-etapa`, `roteiro-saida-remover`, `roteiro-nova-saida`, `roteiro-cancelar`, `roteiro-salvar`

- [ ] **Step 1: Specs (falham)**

`app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/roteiro.spec.js`:

```js
import {
  destinosDe,
  limparSaida,
  listaParaTexto,
  novaSaida,
  passosDe,
  payloadDoPasso,
  slugChave,
  sugestoesQuando,
  textoParaLista,
} from '../roteiro';

const TODOS = [
  { id: 1, thesis_id: null, position: 1, chave: 'nome' },
  { id: 2, thesis_id: null, position: 0, chave: 'tem_advogado' },
  { id: 3, thesis_id: 7, position: 0, chave: 'renda' },
  { id: 4, thesis_id: 8, position: 0, chave: 'outra' },
];

describe('helpers do roteiro da IA', () => {
  it('slugChave tira acento e vira a-z, 0-9 e _', () => {
    expect(slugChave('Recebeu auxílio-doença?')).toBe('recebeu_auxilio_doenca');
    expect(slugChave('  Já tem advogado  ')).toBe('ja_tem_advogado');
  });

  it('lista e texto separados por vírgula', () => {
    expect(textoParaLista(' a, b ,, c ')).toEqual(['a', 'b', 'c']);
    expect(listaParaTexto(['a', 'b'])).toBe('a, b');
    expect(listaParaTexto(null)).toBe('');
  });

  it('passos do escopo na ordem; destinos = comuns (+ os da tese)', () => {
    expect(passosDe(TODOS, null).map(p => p.chave)).toEqual(['tem_advogado', 'nome']);
    expect(destinosDe(TODOS, 7).map(p => p.chave)).toEqual(['tem_advogado', 'nome', 'renda']);
    expect(destinosDe(TODOS, null).map(p => p.chave)).toEqual(['tem_advogado', 'nome']);
  });

  it('sugestões do "quando": calculadora manda; senão o tipo', () => {
    const calcs = {
      meses_ate_65: { campos: ['nascimento'], resultados: ['ja_tem_65', 'menos_de_65', 'depende'] },
    };
    expect(sugestoesQuando({ tipo_resposta: 'sim_nao' }, calcs)).toEqual(['sim', 'nao', '*']);
    expect(sugestoesQuando({ tipo_resposta: 'escolha', opcoes: ['A', 'B'] }, calcs)).toEqual(['A', 'B', '*']);
    expect(sugestoesQuando({ tipo_resposta: 'data', calculadora: 'meses_ate_65' }, calcs)).toEqual([
      'ja_tem_65',
      'menos_de_65',
      'depende',
      '*',
    ]);
    expect(sugestoesQuando({ tipo_resposta: 'texto' }, calcs)).toEqual(['*']);
  });

  it('novaSaida pega o próximo id livre', () => {
    expect(novaSaida([])).toEqual({ id: 's1', quando: '', acao: 'seguir' });
    expect(novaSaida([{ id: 's2' }]).id).toBe('s3');
  });

  it('limparSaida deixa só o que a ação usa', () => {
    const cheia = {
      id: 's1',
      quando: ' sim ',
      acao: 'seguir',
      alvo: 'x',
      motivo: 'm',
      motivo_perda: 'Outro',
      mensagem: ' ',
      efeitos: { etiqueta: '', etapa: 'Qualificação' },
    };
    expect(limparSaida(cheia)).toEqual({
      id: 's1',
      quando: 'sim',
      acao: 'seguir',
      efeitos: { etapa: 'Qualificação' },
    });
    expect(limparSaida({ ...cheia, acao: 'desqualificar' })).toEqual({
      id: 's1',
      quando: 'sim',
      acao: 'desqualificar',
      motivo: 'm',
      motivo_perda: 'Outro',
      efeitos: { etapa: 'Qualificação' },
    });
    expect(limparSaida({ id: 's2', quando: '*', acao: 'ir_para', alvo: 'renda' })).toEqual({
      id: 's2',
      quando: '*',
      acao: 'ir_para',
      alvo: 'renda',
    });
  });

  it('payload: opções só em escolha, campos só com calculadora', () => {
    const base = {
      titulo: ' Renda ',
      chave: 'renda',
      orientacao: '',
      tipo_resposta: 'numero',
      opcoesTexto: 'a, b',
      calculadora: '',
      calculadora_campos: { x: 'y' },
      saidas: [],
    };
    expect(payloadDoPasso(base)).toEqual({
      titulo: 'Renda',
      chave: 'renda',
      orientacao: '',
      tipo_resposta: 'numero',
      opcoes: [],
      calculadora: '',
      calculadora_campos: {},
      saidas: [],
    });
    expect(
      payloadDoPasso({
        ...base,
        tipo_resposta: 'escolha',
        calculadora: 'renda_per_capita',
        calculadora_campos: { renda_total: 'renda', moradores: '' },
      })
    ).toEqual(
      expect.objectContaining({
        opcoes: ['a', 'b'],
        calculadora_campos: { renda_total: 'renda' },
      })
    );
  });
});
```

`app/javascript/dashboard/routes/dashboard/ramon/components/roteiro/specs/RoteiroEditor.spec.js`:

```js
import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import RoteiroPassosAPI from 'dashboard/api/roteiroPassos';
import RoteiroEditor from '../RoteiroEditor.vue';

vi.mock('dashboard/api/roteiroPassos', () => ({
  default: { create: vi.fn(), update: vi.fn(), delete: vi.fn(), reorder: vi.fn() },
}));
const alertSpy = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...a) => alertSpy(...a),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const passo = (id, thesisId, position, chave, extra = {}) => ({
  id,
  thesis_id: thesisId,
  position,
  chave,
  titulo: chave.toUpperCase(),
  orientacao: '',
  tipo_resposta: 'sim_nao',
  opcoes: [],
  calculadora: null,
  calculadora_campos: {},
  saidas: [],
  ...extra,
});
const PASSOS = [
  passo(1, null, 0, 'tem_advogado'),
  passo(2, 5, 1, 'renda', {
    tipo_resposta: 'numero',
    saidas: [{ id: 's1', quando: '< 1000', acao: 'seguir' }],
  }),
  passo(3, 5, 0, 'recebeu'),
  passo(4, 9, 0, 'outra'),
];
const CALCULADORAS = {
  renda_per_capita: {
    campos: ['renda_total', 'moradores'],
    resultados: ['abaixo', 'acima', 'depende'],
  },
};

const store = createStore({
  modules: {
    leadConfig: {
      namespaced: true,
      getters: {
        getStages: () => [
          { id: 1, name: 'Qualificação', is_won: false, is_lost: false },
          { id: 2, name: 'Perdido', is_won: false, is_lost: true },
        ],
        getLostReasons: () => [{ id: 1, name: 'Sem viabilidade' }],
      },
    },
  },
});

const montar = thesisId =>
  mount(RoteiroEditor, {
    props: { thesisId, passos: PASSOS, calculadoras: CALCULADORAS },
    global: { plugins: [store], mocks: { $t: k => k } },
  });
const titulos = w =>
  w.findAll('[data-testid="roteiro-passo-abrir"]').map(b => b.text());

describe('RoteiroEditor', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('lista só os passos do escopo, na ordem', () => {
    expect(titulos(montar(5))).toEqual(['RECEBEU', 'RENDA']);
    expect(titulos(montar(null))).toEqual(['TEM_ADVOGADO']);
  });

  it('passo novo da tese: a chave sai do título e vai com o thesis_id', async () => {
    RoteiroPassosAPI.create.mockResolvedValue({ data: {} });
    const wrapper = montar(5);
    await wrapper.find('[data-testid="roteiro-novo"]').trigger('click');
    const titulo = wrapper.find('[data-testid="roteiro-titulo"]');
    await titulo.setValue('Qual a renda da casa?');
    await titulo.trigger('blur');
    expect(wrapper.find('[data-testid="roteiro-chave"]').element.value).toBe(
      'qual_a_renda_da_casa'
    );
    await wrapper.find('[data-testid="roteiro-salvar"]').trigger('click');
    await flushPromises();
    expect(RoteiroPassosAPI.create).toHaveBeenCalledWith(
      expect.objectContaining({
        titulo: 'Qual a renda da casa?',
        chave: 'qual_a_renda_da_casa',
        thesis_id: 5,
      })
    );
    expect(wrapper.emitted('mudou')).toHaveLength(1);
  });

  it('editar: chave travada; "vai para" lista comuns e os da tese, sem o próprio passo', async () => {
    const wrapper = montar(5);
    await wrapper.findAll('[data-testid="roteiro-passo-abrir"]')[0].trigger('click');
    expect(
      wrapper.find('[data-testid="roteiro-chave"]').attributes()
    ).toHaveProperty('disabled');
    await wrapper.find('[data-testid="roteiro-nova-saida"]').trigger('click');
    await wrapper.find('[data-testid="roteiro-saida-acao"]').setValue('ir_para');
    const alvos = wrapper
      .findAll('[data-testid="roteiro-saida-alvo"] option')
      .map(o => o.element.value);
    expect(alvos).toEqual(['', 'tem_advogado', 'renda']);
  });

  it('salvar manda só o que a ação usa', async () => {
    RoteiroPassosAPI.update.mockResolvedValue({ data: {} });
    const wrapper = montar(5);
    await wrapper.findAll('[data-testid="roteiro-passo-abrir"]')[0].trigger('click');
    await wrapper.find('[data-testid="roteiro-nova-saida"]').trigger('click');
    await wrapper.find('[data-testid="roteiro-saida-quando"]').setValue('sim');
    await wrapper
      .find('[data-testid="roteiro-saida-acao"]')
      .setValue('desqualificar');
    await wrapper
      .find('[data-testid="roteiro-saida-motivo"]')
      .setValue('tem advogado');
    await wrapper.find('[data-testid="roteiro-salvar"]').trigger('click');
    await flushPromises();
    expect(RoteiroPassosAPI.update).toHaveBeenCalledWith(
      3,
      expect.objectContaining({
        saidas: [
          { id: 's1', quando: 'sim', acao: 'desqualificar', motivo: 'tem advogado' },
        ],
      })
    );
  });

  it('descer manda a ordem do escopo', async () => {
    RoteiroPassosAPI.reorder.mockResolvedValue({});
    const wrapper = montar(5);
    await wrapper.findAll('[data-testid="roteiro-passo-descer"]')[0].trigger('click');
    await flushPromises();
    expect(RoteiroPassosAPI.reorder).toHaveBeenCalledWith([2, 3]);
  });

  it('remoção recusada mostra o motivo do servidor', async () => {
    RoteiroPassosAPI.delete.mockRejectedValue({
      response: { data: { error: 'Não dá para remover: RECEBEU aponta' } },
    });
    const wrapper = montar(5);
    await wrapper.findAll('[data-testid="roteiro-passo-remover"]')[1].trigger('click');
    await wrapper.find('[data-testid="confirm-modal-confirm"]').trigger('click');
    await flushPromises();
    expect(RoteiroPassosAPI.delete).toHaveBeenCalledWith(2);
    expect(alertSpy).toHaveBeenCalledWith('Não dá para remover: RECEBEU aponta');
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `node_modules/.bin/vitest run --no-cache app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/roteiro.spec.js app/javascript/dashboard/routes/dashboard/ramon/components/roteiro/specs/RoteiroEditor.spec.js`
Expected: FAIL — `Failed to resolve import "../roteiro"` / `"../RoteiroEditor.vue"`.

- [ ] **Step 3: API e helpers**

`app/javascript/dashboard/api/roteiroPassos.js`:

```js
/* global axios */
import ApiClient from './ApiClient';

// Passos do roteiro da IA (F2): o index traz todos os da conta + o catálogo das calculadoras.
class RoteiroPassosAPI extends ApiClient {
  constructor() {
    super('roteiro_passos', { accountScoped: true });
  }

  reorder(ids) {
    return axios.post(`${this.url}/reorder`, { ids });
  }
}

export default new RoteiroPassosAPI();
```

`app/javascript/dashboard/routes/dashboard/ramon/helpers/roteiro.js`:

```js
// Regras puras das telas do roteiro da IA (F2). O servidor confere de novo no salvar (Conferencia).

export const TIPOS = ['sim_nao', 'escolha', 'numero', 'data', 'texto'];
export const ACOES = ['seguir', 'ir_para', 'desqualificar', 'humano', 'concluir'];

// "Recebeu auxílio-doença?" → "recebeu_auxilio_doenca" (mesma regra do model: a-z, 0-9 e _).
export const slugChave = texto =>
  (texto || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 40);

export const textoParaLista = texto =>
  (texto || '')
    .split(',')
    .map(item => item.trim())
    .filter(Boolean);

export const listaParaTexto = lista => (lista || []).join(', ');

const porPosicao = (a, b) => a.position - b.position || a.id - b.id;

// thesisId null = passos comuns da conta.
export const passosDe = (todos, thesisId) =>
  (todos || []).filter(p => p.thesis_id === thesisId).sort(porPosicao);

// Para onde um passo pode apontar ("vai para", campos da calculadora): comum só alcança os comuns (roda em toda
// tese); passo da tese alcança os comuns e os da tese.
export const destinosDe = (todos, thesisId) =>
  thesisId === null
    ? passosDe(todos, null)
    : [...passosDe(todos, null), ...passosDe(todos, thesisId)];

// Sugestões do "quando" (datalist): com calculadora casa o resultado dela; senão os valores do tipo.
export const sugestoesQuando = (passo, calculadoras) => {
  const calc = calculadoras?.[passo.calculadora];
  if (calc) return [...calc.resultados, '*'];
  if (passo.tipo_resposta === 'sim_nao') return ['sim', 'nao', '*'];
  if (passo.tipo_resposta === 'escolha') return [...(passo.opcoes || []), '*'];
  return ['*'];
};

// Próximo id livre (s1, s2…): a IA cita o id nas respostas de texto livre; ids do seed (sim, nao) ficam.
export const novaSaida = saidas => {
  const usados = new Set((saidas || []).map(s => s.id));
  let n = (saidas || []).length + 1;
  while (usados.has(`s${n}`)) n += 1;
  return { id: `s${n}`, quando: '', acao: 'seguir' };
};

// Só os campos que a ação usa; motivo vazio em desqualificar/humano vai vazio para o model recusar com a mensagem.
export const limparSaida = saida => {
  const efeitos = Object.fromEntries(
    Object.entries(saida.efeitos || {}).filter(([, valor]) => valor)
  );
  return {
    id: saida.id,
    quando: (saida.quando || '').trim(),
    acao: saida.acao,
    ...(saida.acao === 'ir_para' ? { alvo: saida.alvo } : {}),
    ...(['desqualificar', 'humano'].includes(saida.acao)
      ? { motivo: (saida.motivo || '').trim() }
      : {}),
    ...(saida.acao === 'desqualificar' && saida.motivo_perda
      ? { motivo_perda: saida.motivo_perda }
      : {}),
    ...(saida.mensagem?.trim() ? { mensagem: saida.mensagem.trim() } : {}),
    ...(Object.keys(efeitos).length ? { efeitos } : {}),
  };
};

export const payloadDoPasso = rascunho => ({
  titulo: rascunho.titulo.trim(),
  chave: rascunho.chave,
  orientacao: rascunho.orientacao,
  tipo_resposta: rascunho.tipo_resposta,
  opcoes:
    rascunho.tipo_resposta === 'escolha'
      ? textoParaLista(rascunho.opcoesTexto)
      : [],
  calculadora: rascunho.calculadora || '',
  calculadora_campos: rascunho.calculadora
    ? Object.fromEntries(
        Object.entries(rascunho.calculadora_campos || {}).filter(([, v]) => v)
      )
    : {},
  saidas: rascunho.saidas.map(limparSaida),
});
```

- [ ] **Step 4: Formulário do passo**

`app/javascript/dashboard/routes/dashboard/ramon/components/roteiro/RoteiroPassoForm.vue`:

```vue
<script setup>
// Formulário de um passo do roteiro da IA (F2): o que descobrir, como perguntar, tipo, calculadora e as saídas
// (quando → então). "Vai para" e campos da calculadora só apontam para passos que existem — a API confere de novo.
import { computed, reactive, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  ACOES,
  TIPOS,
  listaParaTexto,
  novaSaida,
  payloadDoPasso,
  slugChave,
  sugestoesQuando,
  textoParaLista,
} from '../../helpers/roteiro';
import {
  AVISO,
  CAMPO,
  ROTULO,
  SECAO,
  SELECT,
  TEXTAREA,
  TITULO,
  TOM,
} from '../../helpers/ui';

const props = defineProps({
  // passo salvo (edição) ou null (novo)
  passo: { type: Object, default: null },
  destinos: { type: Array, required: true },
  calculadoras: { type: Object, required: true },
  salvando: { type: Boolean, default: false },
});
const emit = defineEmits(['salvar', 'cancelar']);
const { t } = useI18n();

const stages = useMapGetter('leadConfig/getStages');
const lostReasons = useMapGetter('leadConfig/getLostReasons');
// só etapa aberta: ganho nunca; Perdido só pela saída "Desqualifica" (efeitos do motor)
const etapasAbertas = computed(() =>
  (stages.value || []).filter(s => !s.is_won && !s.is_lost)
);

const comPadroes = saida => ({
  alvo: '',
  motivo: '',
  motivo_perda: '',
  mensagem: '',
  ...saida,
  efeitos: { etiqueta: '', etapa: '', ...(saida.efeitos || {}) },
});

// cópia solta: editar não mexe na lista até salvar
const original = JSON.parse(JSON.stringify(props.passo || {}));
const novo = !props.passo;
const rascunho = reactive({
  titulo: original.titulo || '',
  chave: original.chave || '',
  orientacao: original.orientacao || '',
  tipo_resposta: original.tipo_resposta || 'sim_nao',
  opcoesTexto: listaParaTexto(original.opcoes),
  calculadora: original.calculadora || '',
  calculadora_campos: { ...(original.calculadora_campos || {}) },
  saidas: (original.saidas || []).map(comPadroes),
});

// a chave nasce do título; depois de salvo fica travada
const sugerirChave = () => {
  if (novo && !rascunho.chave) rascunho.chave = slugChave(rascunho.titulo);
};

const outrosPassos = computed(() =>
  props.destinos.filter(d => d.chave !== original.chave)
);
// campo da calculadora pode vir do próprio passo (ex.: a data respondida agora)
const opcoesDeCampo = computed(() => [
  ...outrosPassos.value,
  ...(rascunho.chave
    ? [{ chave: rascunho.chave, titulo: t('RAMON.ROTEIRO_IA.EDITOR.ESTE_PASSO') }]
    : []),
]);
const nomesCalculadoras = computed(() => Object.keys(props.calculadoras));
const camposDaCalculadora = computed(
  () => props.calculadoras[rascunho.calculadora]?.campos || []
);
const sugestoes = computed(() =>
  sugestoesQuando(
    { ...rascunho, opcoes: textoParaLista(rascunho.opcoesTexto) },
    props.calculadoras
  )
);
const ajudaSaidas = computed(() =>
  rascunho.tipo_resposta === 'texto' && !rascunho.calculadora
    ? 'RAMON.ROTEIRO_IA.EDITOR.SAIDAS_AJUDA_TEXTO'
    : 'RAMON.ROTEIRO_IA.EDITOR.SAIDAS_AJUDA'
);
const listaId = useId();
const podeSalvar = computed(
  () => !props.salvando && rascunho.titulo.trim() && rascunho.chave
);

const adicionarSaida = () =>
  rascunho.saidas.push(comPadroes(novaSaida(rascunho.saidas)));
const removerSaida = indice => rascunho.saidas.splice(indice, 1);
const salvar = () => emit('salvar', payloadDoPasso(rascunho));
</script>

<template>
  <div class="flex flex-col gap-3" :class="SECAO" data-testid="roteiro-form">
    <div class="grid gap-3 md:grid-cols-[1fr_16rem]">
      <label :class="ROTULO">
        {{ $t('RAMON.ROTEIRO_IA.EDITOR.TITULO') }}
        <input
          v-model="rascunho.titulo"
          data-testid="roteiro-titulo"
          :class="CAMPO"
          @blur="sugerirChave"
        />
      </label>
      <label :class="ROTULO" :title="$t('RAMON.ROTEIRO_IA.EDITOR.CHAVE_AJUDA')">
        {{ $t('RAMON.ROTEIRO_IA.EDITOR.CHAVE') }}
        <input
          v-model="rascunho.chave"
          data-testid="roteiro-chave"
          class="font-mono"
          :class="CAMPO"
          :disabled="!novo"
        />
      </label>
    </div>
    <p class="m-0" :class="[AVISO, TOM.amber]">
      {{ $t('RAMON.ROTEIRO_IA.EDITOR.FALA_COM_CLIENTE') }}
    </p>
    <label :class="ROTULO">
      {{ $t('RAMON.ROTEIRO_IA.EDITOR.ORIENTACAO') }}
      <textarea
        v-model="rascunho.orientacao"
        data-testid="roteiro-orientacao"
        rows="2"
        class="max-h-48 min-h-16 [field-sizing:content]"
        :class="TEXTAREA"
      />
    </label>
    <div class="grid gap-3 md:grid-cols-3">
      <label :class="ROTULO">
        {{ $t('RAMON.ROTEIRO_IA.EDITOR.TIPO') }}
        <select
          v-model="rascunho.tipo_resposta"
          data-testid="roteiro-tipo"
          :class="SELECT"
        >
          <option v-for="tipo in TIPOS" :key="tipo" :value="tipo">
            {{ $t(`RAMON.ROTEIRO_IA.EDITOR.TIPOS.${tipo.toUpperCase()}`) }}
          </option>
        </select>
      </label>
      <label
        v-if="rascunho.tipo_resposta === 'escolha'"
        class="md:col-span-2"
        :class="ROTULO"
      >
        {{ $t('RAMON.ROTEIRO_IA.EDITOR.OPCOES') }}
        <input
          v-model="rascunho.opcoesTexto"
          data-testid="roteiro-opcoes"
          :class="CAMPO"
        />
      </label>
    </div>
    <div class="grid gap-3 md:grid-cols-3">
      <label :class="ROTULO">
        {{ $t('RAMON.ROTEIRO_IA.EDITOR.CALCULADORA') }}
        <select
          v-model="rascunho.calculadora"
          data-testid="roteiro-calculadora"
          :class="SELECT"
        >
          <option value="">
            {{ $t('RAMON.ROTEIRO_IA.EDITOR.SEM_CALCULADORA') }}
          </option>
          <option v-for="nome in nomesCalculadoras" :key="nome" :value="nome">
            {{ $t(`RAMON.ROTEIRO_IA.EDITOR.CALCULADORAS.${nome.toUpperCase()}`) }}
          </option>
        </select>
      </label>
      <label v-for="campo in camposDaCalculadora" :key="campo" :class="ROTULO">
        {{
          $t('RAMON.ROTEIRO_IA.EDITOR.CAMPO_DA_CALCULADORA', {
            campo: campo.replaceAll('_', ' '),
          })
        }}
        <select
          v-model="rascunho.calculadora_campos[campo]"
          data-testid="roteiro-campo-calculadora"
          :class="SELECT"
        >
          <option value="">—</option>
          <option
            v-for="destino in opcoesDeCampo"
            :key="destino.chave"
            :value="destino.chave"
          >
            {{ destino.titulo }}
          </option>
        </select>
      </label>
    </div>

    <div class="flex flex-col gap-2" :class="SECAO">
      <p class="m-0" :class="TITULO">
        {{ $t('RAMON.ROTEIRO_IA.EDITOR.SAIDAS') }}
      </p>
      <p class="m-0 text-xs text-n-slate-10">{{ $t(ajudaSaidas) }}</p>
      <datalist :id="listaId">
        <option v-for="valor in sugestoes" :key="valor" :value="valor" />
      </datalist>
      <ul class="m-0 flex list-none flex-col divide-y divide-n-weak p-0">
        <li
          v-for="(saida, indice) in rascunho.saidas"
          :key="saida.id"
          data-testid="roteiro-saida"
          class="flex flex-col gap-2 py-2 first:pt-0"
        >
          <div class="flex flex-wrap items-end gap-2">
            <label class="w-36" :class="ROTULO">
              {{ $t('RAMON.ROTEIRO_IA.EDITOR.QUANDO') }}
              <input
                v-model="saida.quando"
                data-testid="roteiro-saida-quando"
                :list="listaId"
                class="font-mono"
                :class="CAMPO"
              />
            </label>
            <label class="w-48" :class="ROTULO">
              {{ $t('RAMON.ROTEIRO_IA.EDITOR.ACAO') }}
              <select
                v-model="saida.acao"
                data-testid="roteiro-saida-acao"
                :class="SELECT"
              >
                <option v-for="acao in ACOES" :key="acao" :value="acao">
                  {{ $t(`RAMON.ROTEIRO_IA.EDITOR.ACOES.${acao.toUpperCase()}`) }}
                </option>
              </select>
            </label>
            <label
              v-if="saida.acao === 'ir_para'"
              class="min-w-40 flex-1"
              :class="ROTULO"
            >
              {{ $t('RAMON.ROTEIRO_IA.EDITOR.ALVO') }}
              <select
                v-model="saida.alvo"
                data-testid="roteiro-saida-alvo"
                :class="SELECT"
              >
                <option value="">—</option>
                <option
                  v-for="destino in outrosPassos"
                  :key="destino.chave"
                  :value="destino.chave"
                >
                  {{ destino.titulo }}
                </option>
              </select>
            </label>
            <label
              v-if="['desqualificar', 'humano'].includes(saida.acao)"
              class="min-w-40 flex-1"
              :class="ROTULO"
            >
              {{ $t('RAMON.ROTEIRO_IA.EDITOR.MOTIVO') }}
              <input
                v-model="saida.motivo"
                data-testid="roteiro-saida-motivo"
                :class="CAMPO"
              />
            </label>
            <label
              v-if="saida.acao === 'desqualificar'"
              class="w-48"
              :class="ROTULO"
            >
              {{ $t('RAMON.ROTEIRO_IA.EDITOR.MOTIVO_PERDA') }}
              <select
                v-model="saida.motivo_perda"
                data-testid="roteiro-saida-motivo-perda"
                :class="SELECT"
              >
                <option value="">
                  {{ $t('RAMON.ROTEIRO_IA.EDITOR.MOTIVO_PERDA_PADRAO') }}
                </option>
                <option
                  v-for="motivo in lostReasons"
                  :key="motivo.id"
                  :value="motivo.name"
                >
                  {{ motivo.name }}
                </option>
              </select>
            </label>
            <Button
              data-testid="roteiro-saida-remover"
              xs
              ghost
              slate
              icon="i-lucide-trash-2"
              class="ms-auto"
              :aria-label="$t('RAMON.ROTEIRO_IA.EDITOR.REMOVER_SAIDA')"
              :title="$t('RAMON.ROTEIRO_IA.EDITOR.REMOVER_SAIDA')"
              @click="removerSaida(indice)"
            />
          </div>
          <div class="grid gap-2 md:grid-cols-3">
            <label :class="ROTULO">
              {{ $t('RAMON.ROTEIRO_IA.EDITOR.MENSAGEM') }}
              <input
                v-model="saida.mensagem"
                data-testid="roteiro-saida-mensagem"
                :class="CAMPO"
              />
            </label>
            <label :class="ROTULO">
              {{ $t('RAMON.ROTEIRO_IA.EDITOR.ETIQUETA') }}
              <input
                v-model="saida.efeitos.etiqueta"
                data-testid="roteiro-saida-etiqueta"
                class="font-mono"
                :class="CAMPO"
              />
            </label>
            <label :class="ROTULO">
              {{ $t('RAMON.ROTEIRO_IA.EDITOR.ETAPA') }}
              <select
                v-model="saida.efeitos.etapa"
                data-testid="roteiro-saida-etapa"
                :class="SELECT"
              >
                <option value="">
                  {{ $t('RAMON.ROTEIRO_IA.EDITOR.SEM_ETAPA') }}
                </option>
                <option
                  v-for="etapa in etapasAbertas"
                  :key="etapa.id"
                  :value="etapa.name"
                >
                  {{ etapa.name }}
                </option>
              </select>
            </label>
          </div>
        </li>
      </ul>
      <Button
        data-testid="roteiro-nova-saida"
        xs
        faded
        slate
        icon="i-lucide-plus"
        class="self-start"
        :label="$t('RAMON.ROTEIRO_IA.EDITOR.NOVA_SAIDA')"
        @click="adicionarSaida"
      />
    </div>

    <div class="flex justify-end gap-2">
      <Button
        data-testid="roteiro-cancelar"
        sm
        faded
        slate
        :label="$t('RAMON.ROTEIRO_IA.EDITOR.CANCELAR')"
        @click="emit('cancelar')"
      />
      <Button
        data-testid="roteiro-salvar"
        sm
        :label="$t('RAMON.ROTEIRO_IA.EDITOR.SALVAR')"
        :disabled="!podeSalvar"
        @click="salvar"
      />
    </div>
  </div>
</template>
```

- [ ] **Step 5: Lista do roteiro**

`app/javascript/dashboard/routes/dashboard/ramon/components/roteiro/RoteiroEditor.vue`:

```vue
<script setup>
// Roteiro da IA de um escopo (F2): passos comuns da conta (thesisId null) ou de uma tese. Lista em ordem, ↑↓ para
// reordenar, clique abre o passo em sanfona; salvar/remover/reordenar vão direto à API e avisam a tela (mudou).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import RoteiroPassosAPI from 'dashboard/api/roteiroPassos';
import ConfirmModal from '../ConfirmModal.vue';
import RoteiroPassoForm from './RoteiroPassoForm.vue';
import { mensagemErro } from '../../helpers/erro';
import { destinosDe, passosDe } from '../../helpers/roteiro';
import { CHIP, TOM } from '../../helpers/ui';

const props = defineProps({
  // null = passos comuns da conta
  thesisId: { type: Number, default: null },
  // todos os passos da conta (index da API)
  passos: { type: Array, required: true },
  calculadoras: { type: Object, required: true },
});
const emit = defineEmits(['mudou']);
const { t } = useI18n();

const lista = computed(() => passosDe(props.passos, props.thesisId));
const destinos = computed(() => destinosDe(props.passos, props.thesisId));
// id do passo aberto, 'novo' ou null
const aberto = ref(null);
const salvando = ref(false);

const falhou = e => useAlert(mensagemErro(e, t('RAMON.FUNIL.SAVE_ERROR')));

const salvar = async (passo, payload) => {
  if (salvando.value) return;
  salvando.value = true;
  try {
    if (passo) await RoteiroPassosAPI.update(passo.id, payload);
    else await RoteiroPassosAPI.create({ ...payload, thesis_id: props.thesisId });
    aberto.value = null;
    useAlert(t('RAMON.ROTEIRO_IA.EDITOR.SALVO'));
    emit('mudou');
  } catch (e) {
    falhou(e);
  } finally {
    salvando.value = false;
  }
};

const mover = async (indice, direcao) => {
  const ids = lista.value.map(p => p.id);
  const alvo = indice + direcao;
  if (alvo < 0 || alvo >= ids.length) return;
  [ids[indice], ids[alvo]] = [ids[alvo], ids[indice]];
  try {
    await RoteiroPassosAPI.reorder(ids);
    emit('mudou');
  } catch (e) {
    falhou(e);
  }
};

const aRemover = ref(null);
const remover = async () => {
  const passo = aRemover.value;
  // fecha antes do await: sem janela para duplo clique
  aRemover.value = null;
  try {
    await RoteiroPassosAPI.delete(passo.id);
    emit('mudou');
  } catch (e) {
    falhou(e);
  }
};

const alternar = passo => {
  aberto.value = aberto.value === passo.id ? null : passo.id;
};
</script>

<template>
  <div class="flex flex-col gap-2" data-testid="roteiro-editor">
    <p
      v-if="!lista.length && aberto !== 'novo'"
      class="m-0 text-xs text-n-slate-10"
    >
      {{ $t('RAMON.ROTEIRO_IA.EDITOR.VAZIO') }}
    </p>
    <ul class="m-0 flex list-none flex-col divide-y divide-n-weak p-0">
      <li
        v-for="(passo, indice) in lista"
        :key="passo.id"
        data-testid="roteiro-passo-linha"
        class="flex flex-col gap-2 py-2 first:pt-0"
      >
        <div class="flex items-center gap-2">
          <span class="w-5 shrink-0 text-right font-mono text-xs text-n-slate-10">
            {{ indice + 1 }}
          </span>
          <button
            type="button"
            data-testid="roteiro-passo-abrir"
            class="min-w-0 flex-1 truncate p-0 text-left text-sm font-medium text-n-slate-12 hover:text-n-blue-11"
            @click="alternar(passo)"
          >
            {{ passo.titulo }}
          </button>
          <span class="shrink-0 font-mono text-[11px] text-n-slate-10">
            {{ passo.chave }}
          </span>
          <span class="shrink-0" :class="[CHIP, TOM.slate]">
            {{
              $t(
                `RAMON.ROTEIRO_IA.EDITOR.TIPOS.${passo.tipo_resposta.toUpperCase()}`
              )
            }}
          </span>
          <span
            v-if="passo.calculadora"
            class="shrink-0"
            :class="[CHIP, TOM.iris]"
          >
            {{
              $t(
                `RAMON.ROTEIRO_IA.EDITOR.CALCULADORAS.${passo.calculadora.toUpperCase()}`
              )
            }}
          </span>
          <span
            v-if="passo.saidas.length"
            class="shrink-0"
            :class="[CHIP, TOM.blue]"
          >
            {{
              $t('RAMON.ROTEIRO_IA.EDITOR.N_SAIDAS', { n: passo.saidas.length })
            }}
          </span>
          <Button
            data-testid="roteiro-passo-subir"
            xs
            ghost
            slate
            icon="i-lucide-chevron-up"
            :aria-label="$t('RAMON.ROTEIRO_IA.EDITOR.MOVER_CIMA')"
            :disabled="indice === 0"
            @click="mover(indice, -1)"
          />
          <Button
            data-testid="roteiro-passo-descer"
            xs
            ghost
            slate
            icon="i-lucide-chevron-down"
            :aria-label="$t('RAMON.ROTEIRO_IA.EDITOR.MOVER_BAIXO')"
            :disabled="indice === lista.length - 1"
            @click="mover(indice, 1)"
          />
          <Button
            data-testid="roteiro-passo-remover"
            xs
            ghost
            slate
            icon="i-lucide-trash-2"
            :aria-label="$t('RAMON.ROTEIRO_IA.EDITOR.REMOVER')"
            :title="$t('RAMON.ROTEIRO_IA.EDITOR.REMOVER')"
            @click="aRemover = passo"
          />
        </div>
        <RoteiroPassoForm
          v-if="aberto === passo.id"
          :passo="passo"
          :destinos="destinos"
          :calculadoras="calculadoras"
          :salvando="salvando"
          @salvar="salvar(passo, $event)"
          @cancelar="aberto = null"
        />
      </li>
    </ul>
    <RoteiroPassoForm
      v-if="aberto === 'novo'"
      :passo="null"
      :destinos="destinos"
      :calculadoras="calculadoras"
      :salvando="salvando"
      @salvar="salvar(null, $event)"
      @cancelar="aberto = null"
    />
    <Button
      v-else
      data-testid="roteiro-novo"
      sm
      faded
      slate
      icon="i-lucide-plus"
      class="self-start"
      :label="$t('RAMON.ROTEIRO_IA.EDITOR.NOVO')"
      @click="aberto = 'novo'"
    />
    <ConfirmModal
      v-if="aRemover"
      :title="$t('RAMON.ROTEIRO_IA.EDITOR.REMOVER_CONFIRMA')"
      :confirm-label="$t('RAMON.ROTEIRO_IA.EDITOR.REMOVER')"
      @confirm="remover"
      @cancel="aRemover = null"
    />
  </div>
</template>
```

- [ ] **Step 6: i18n — bloco `ROTEIRO_IA` inteiro**

Em `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`, dentro de `RAMON`, logo **antes** da linha `    "NPS": {`:

```json
    "ROTEIRO_IA": {
      "TITULO": "Roteiro da IA",
      "CONTAGEM": "{ok}/{total}",
      "RESPONDIDOS": "✓ {count} respondidos",
      "SITUACAO": {
        "RESPONDIDO": "Respondido",
        "ATUAL": "Pergunta agora",
        "PENDENTE": "A perguntar",
        "FORA": "Não perguntado"
      },
      "DESFECHO": {
        "QUALIFICADO": "Qualificado",
        "DESQUALIFICADO": "Desqualificado",
        "HUMANO": "Passou para a equipe"
      },
      "AGUARDA_EQUIPE": "O Perdido está sugerido no Cockpit, aguardando a equipe confirmar.",
      "COMUNS_CONCLUIDOS": "Passos comuns respondidos — a IA segue a triagem de sempre.",
      "REABRIR": "Reabrir roteiro",
      "REABRIR_CONFIRMA": "Reabrir o roteiro deste lead?",
      "REABRIR_AJUDA": "A IA volta a perguntar a partir de \"{passo}\". As outras respostas ficam; as sugestões do roteiro pendentes no Cockpit são descartadas.",
      "REABERTO": "Roteiro reaberto.",
      "REABRIR_PERDIDO": "Para reabrir, tire o lead do Perdido no funil.",
      "REABRIR_GANHO": "Lead ganho: o roteiro não reabre.",
      "PALAVRAS_CHAVE": "Palavras-chave",
      "PALAVRAS_CHAVE_AJUDA": "Palavras da 1ª mensagem que indicam esta tese, separadas por vírgula",
      "EDITOR": {
        "COMUNS_TITULO": "Passos comuns do roteiro da IA",
        "COMUNS_AJUDA": "Valem para todas as teses e rodam antes do roteiro de cada uma.",
        "ABA_PLAYBOOK": "Playbook",
        "ABA_ROTEIRO": "Roteiro da IA",
        "ROTEIRO_AJUDA": "A IA pergunta um passo por vez, nesta ordem, depois dos passos comuns. O que acontece com cada resposta (saídas) é regra fixa — a IA não decide.",
        "VAZIO": "Nenhum passo. Sem passos, a IA segue a triagem de sempre.",
        "NOVO": "Novo passo",
        "SALVAR": "Salvar passo",
        "CANCELAR": "Cancelar",
        "SALVO": "Passo salvo.",
        "REMOVER": "Remover passo",
        "REMOVER_CONFIRMA": "Remover este passo do roteiro?",
        "MOVER_CIMA": "Subir",
        "MOVER_BAIXO": "Descer",
        "N_SAIDAS": "{n} saídas",
        "TITULO": "O que descobrir",
        "CHAVE": "Chave",
        "CHAVE_AJUDA": "Identificador fixo (minúsculas, números e _). Não muda depois de criado.",
        "FALA_COM_CLIENTE": "A orientação e a base da resposta viram fala da IA com o cliente.",
        "ORIENTACAO": "Como perguntar (vai para a IA)",
        "TIPO": "Tipo de resposta",
        "TIPOS": {
          "SIM_NAO": "Sim ou não",
          "ESCOLHA": "Escolha",
          "NUMERO": "Número",
          "DATA": "Data",
          "TEXTO": "Texto livre"
        },
        "OPCOES": "Opções (separe por vírgula)",
        "CALCULADORA": "Calculadora",
        "SEM_CALCULADORA": "Nenhuma",
        "CALCULADORAS": {
          "PERIODO_DE_GRACA": "Período de graça",
          "RENDA_PER_CAPITA": "Renda por pessoa",
          "PRESCRICAO_5_ANOS": "Prescrição de 5 anos",
          "MESES_ATE_65": "Meses até os 65",
          "DATA_PREVISTA_PARTO": "Data prevista do parto",
          "PRAZO_INSS": "Prazo do INSS"
        },
        "CAMPO_DA_CALCULADORA": "{campo} vem do passo",
        "ESTE_PASSO": "Este passo",
        "SAIDAS": "Saídas — a primeira que casa vale",
        "SAIDAS_AJUDA": "Quando: o valor, uma faixa (< 64, >= 65), o resultado da calculadora ou * para qualquer outro. Sem saídas, o passo só anota e segue.",
        "SAIDAS_AJUDA_TEXTO": "Texto livre: descreva cada saída em Quando — a IA escolhe a que melhor descreve a resposta.",
        "QUANDO": "Quando",
        "ACAO": "Então",
        "ACOES": {
          "SEGUIR": "Segue",
          "IR_PARA": "Vai para o passo",
          "DESQUALIFICAR": "Desqualifica",
          "HUMANO": "Passa para a equipe",
          "CONCLUIR": "Qualificado (fim)"
        },
        "ALVO": "Passo de destino",
        "MOTIVO": "Motivo (vai para o histórico)",
        "MOTIVO_PERDA": "Motivo de perda",
        "MOTIVO_PERDA_PADRAO": "Sem viabilidade (padrão)",
        "MENSAGEM": "Base da resposta da IA (opcional)",
        "ETIQUETA": "Etiqueta na conversa",
        "ETAPA": "Mover para a etapa",
        "SEM_ETAPA": "Não mover",
        "NOVA_SAIDA": "Saída",
        "REMOVER_SAIDA": "Remover saída"
      },
      "TESTAR": {
        "SEM_TESE": "Sem roteiro de tese",
        "AJUDA": "Escolha uma tese para a IA seguir o roteiro dela. O roteiro roda de verdade, mas nada fica gravado."
      }
    },
```

Em `app/javascript/dashboard/i18n/locale/en/ramon.json`, no mesmo lugar (antes de `    "NPS": {`):

```json
    "ROTEIRO_IA": {
      "TITULO": "AI script",
      "CONTAGEM": "{ok}/{total}",
      "RESPONDIDOS": "✓ {count} answered",
      "SITUACAO": {
        "RESPONDIDO": "Answered",
        "ATUAL": "Asking now",
        "PENDENTE": "To ask",
        "FORA": "Not asked"
      },
      "DESFECHO": {
        "QUALIFICADO": "Qualified",
        "DESQUALIFICADO": "Disqualified",
        "HUMANO": "Handed to the team"
      },
      "AGUARDA_EQUIPE": "Lost is suggested in the Cockpit, waiting for the team to confirm.",
      "COMUNS_CONCLUIDOS": "Shared steps answered — the AI follows the usual triage.",
      "REABRIR": "Reopen script",
      "REABRIR_CONFIRMA": "Reopen this lead's script?",
      "REABRIR_AJUDA": "The AI asks again from \"{passo}\". Other answers stay; pending script suggestions in the Cockpit are dismissed.",
      "REABERTO": "Script reopened.",
      "REABRIR_PERDIDO": "To reopen, move the lead out of Lost in the funnel.",
      "REABRIR_GANHO": "Won lead: the script does not reopen.",
      "PALAVRAS_CHAVE": "Keywords",
      "PALAVRAS_CHAVE_AJUDA": "Words in the first message that point to this thesis, comma-separated",
      "EDITOR": {
        "COMUNS_TITULO": "Shared AI script steps",
        "COMUNS_AJUDA": "Apply to every thesis and run before each thesis' own script.",
        "ABA_PLAYBOOK": "Playbook",
        "ABA_ROTEIRO": "AI script",
        "ROTEIRO_AJUDA": "The AI asks one step at a time, in this order, after the shared steps. What happens with each answer (outcomes) is a fixed rule — the AI does not decide.",
        "VAZIO": "No steps. Without steps, the AI follows the usual triage.",
        "NOVO": "New step",
        "SALVAR": "Save step",
        "CANCELAR": "Cancel",
        "SALVO": "Step saved.",
        "REMOVER": "Remove step",
        "REMOVER_CONFIRMA": "Remove this step from the script?",
        "MOVER_CIMA": "Move up",
        "MOVER_BAIXO": "Move down",
        "N_SAIDAS": "{n} outcomes",
        "TITULO": "What to find out",
        "CHAVE": "Key",
        "CHAVE_AJUDA": "Fixed identifier (lowercase, numbers and _). Cannot change after creation.",
        "FALA_COM_CLIENTE": "The guidance and the reply base become what the AI says to the client.",
        "ORIENTACAO": "How to ask (goes to the AI)",
        "TIPO": "Answer type",
        "TIPOS": {
          "SIM_NAO": "Yes or no",
          "ESCOLHA": "Choice",
          "NUMERO": "Number",
          "DATA": "Date",
          "TEXTO": "Free text"
        },
        "OPCOES": "Options (comma-separated)",
        "CALCULADORA": "Calculator",
        "SEM_CALCULADORA": "None",
        "CALCULADORAS": {
          "PERIODO_DE_GRACA": "Grace period",
          "RENDA_PER_CAPITA": "Income per person",
          "PRESCRICAO_5_ANOS": "5-year limitation",
          "MESES_ATE_65": "Months until 65",
          "DATA_PREVISTA_PARTO": "Expected birth date",
          "PRAZO_INSS": "INSS deadline"
        },
        "CAMPO_DA_CALCULADORA": "{campo} comes from step",
        "ESTE_PASSO": "This step",
        "SAIDAS": "Outcomes — the first match wins",
        "SAIDAS_AJUDA": "When: the value, a range (< 64, >= 65), the calculator result or * for anything else. Without outcomes, the step just records and moves on.",
        "SAIDAS_AJUDA_TEXTO": "Free text: describe each outcome in When — the AI picks the one that best describes the answer.",
        "QUANDO": "When",
        "ACAO": "Then",
        "ACOES": {
          "SEGUIR": "Continue",
          "IR_PARA": "Go to step",
          "DESQUALIFICAR": "Disqualify",
          "HUMANO": "Hand to the team",
          "CONCLUIR": "Qualified (end)"
        },
        "ALVO": "Target step",
        "MOTIVO": "Reason (goes to history)",
        "MOTIVO_PERDA": "Loss reason",
        "MOTIVO_PERDA_PADRAO": "Sem viabilidade (default)",
        "MENSAGEM": "AI reply base (optional)",
        "ETIQUETA": "Conversation label",
        "ETAPA": "Move to stage",
        "SEM_ETAPA": "Don't move",
        "NOVA_SAIDA": "Outcome",
        "REMOVER_SAIDA": "Remove outcome"
      },
      "TESTAR": {
        "SEM_TESE": "No thesis script",
        "AJUDA": "Pick a thesis for the AI to follow its script. The script really runs, but nothing is saved."
      }
    },
```

Conferir que os dois arquivos continuam JSON válido: `node -e "JSON.parse(require('fs').readFileSync('app/javascript/dashboard/i18n/locale/pt_BR/ramon.json','utf8'));JSON.parse(require('fs').readFileSync('app/javascript/dashboard/i18n/locale/en/ramon.json','utf8'))"` (sem saída = ok).

- [ ] **Step 7: Rodar e ver passar**

Run: `node_modules/.bin/vitest run --no-cache app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/roteiro.spec.js app/javascript/dashboard/routes/dashboard/ramon/components/roteiro/specs/RoteiroEditor.spec.js`
Expected: PASS (13 testes).

- [ ] **Step 8: Lint + commit**

```bash
node_modules/.bin/eslint --fix app/javascript/dashboard/api/roteiroPassos.js app/javascript/dashboard/routes/dashboard/ramon/helpers/roteiro.js \
  app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/roteiro.spec.js \
  app/javascript/dashboard/routes/dashboard/ramon/components/roteiro/
git add app/javascript/dashboard/api/roteiroPassos.js app/javascript/dashboard/routes/dashboard/ramon/helpers/roteiro.js \
  app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/roteiro.spec.js \
  app/javascript/dashboard/routes/dashboard/ramon/components/roteiro/ \
  app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit -m "feat(roteiro): editor de passos do roteiro da IA (saídas, calculadora, destinos)"
```

---

### Task 4: Playbooks — passos comuns, aba "Roteiro da IA" e palavras-chave

**Files:**
- Modify: `app/controllers/api/v1/accounts/theses_controller.rb` (`permitted_params`)
- Modify: `app/views/api/v1/accounts/theses/show.json.jbuilder`
- Modify: `spec/requests/api/v1/accounts/theses_controller_spec.rb`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/pages/Playbooks.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Playbooks.spec.js`

**Interfaces:**
- Consumes: `RoteiroPassosAPI.get()`, `<RoteiroEditor>`, `textoParaLista`, `listaParaTexto` (Task 3); action `leadConfig/get`
- Produces: tese com `palavras_chave` (Array de String) no show e no PATCH; testids `roteiro-comuns`, `playbooks-palavras-chave-input`, `playbooks-abas`, `playbooks-aba-playbook`, `playbooks-aba-roteiro`, `playbooks-roteiro`

- [ ] **Step 1: Specs (falham)**

Em `spec/requests/api/v1/accounts/theses_controller_spec.rb`, antes do último `end` do arquivo:

```ruby

  describe 'palavras-chave (roteiro da tese, F2)' do
    it 'grava a lista, devolve no show e aceita lista vazia' do
      thesis = account.theses.create!(name: 'Tese Palavras', position: 60)
      patch "/api/v1/accounts/#{account.id}/theses/#{thesis.id}", params: { palavras_chave: ['auxílio-acidente', 'sequela'] },
                                                                   headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['palavras_chave']).to eq(['auxílio-acidente', 'sequela'])

      patch "/api/v1/accounts/#{account.id}/theses/#{thesis.id}", params: { palavras_chave: [] },
                                                                   headers: admin.create_new_auth_token, as: :json
      expect(thesis.reload.palavras_chave).to eq([])
    end
  end
```

Em `app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Playbooks.spec.js`:

a) Logo depois de `import Playbooks from '../Playbooks.vue';`:

```js

vi.mock('dashboard/api/roteiroPassos', () => ({
  default: {
    get: vi.fn(() =>
      Promise.resolve({
        data: {
          calculadoras: {},
          payload: [
            {
              id: 1,
              thesis_id: null,
              position: 0,
              chave: 'tem_advogado',
              titulo: 'Tem advogado',
              tipo_resposta: 'sim_nao',
              opcoes: [],
              calculadora: null,
              calculadora_campos: {},
              saidas: [],
            },
            {
              id: 2,
              thesis_id: 1,
              position: 0,
              chave: 'sequela',
              titulo: 'Sequela',
              tipo_resposta: 'texto',
              opcoes: [],
              calculadora: null,
              calculadora_campos: {},
              saidas: [],
            },
          ],
        },
      })
    ),
  },
}));
```

b) Antes do `});` final do `describe('Playbooks.vue', …)`:

```js

  it('mostra os passos comuns no topo', async () => {
    const { wrapper } = mountPlaybooks();
    await flushPromises();
    const comuns = wrapper.find('[data-testid="roteiro-comuns"]');
    expect(comuns.text()).toContain('Tem advogado');
    expect(comuns.text()).not.toContain('Sequela');
  });

  it('aba Roteiro da IA mostra só os passos da tese', async () => {
    const { wrapper } = mountPlaybooks();
    await flushPromises();
    await wrapper.findAll('[data-testid="playbooks-item"]')[0].trigger('click');
    await wrapper.find('[data-testid="playbooks-aba-roteiro"]').trigger('click');
    const passos = wrapper.findAll(
      '[data-testid="playbooks-roteiro"] [data-testid="roteiro-passo-abrir"]'
    );
    expect(passos.map(p => p.text())).toEqual(['Sequela']);
    expect(
      wrapper.find('[data-testid="playbooks-section"]').exists()
    ).toBe(false);
  });

  it('salva as palavras-chave como lista', async () => {
    const { wrapper, store } = mountPlaybooks();
    await wrapper.findAll('[data-testid="playbooks-item"]')[0].trigger('click');
    const campo = wrapper.find('[data-testid="playbooks-palavras-chave-input"]');
    await campo.setValue('acidente, sequela ');
    await campo.trigger('blur');
    expect(store.dispatch).toHaveBeenLastCalledWith(
      'theses/update',
      expect.objectContaining({ id: 1, palavras_chave: ['acidente', 'sequela'] })
    );
  });
```

- [ ] **Step 2: Rodar o spec JS e ver falhar**

Run: `node_modules/.bin/vitest run --no-cache app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Playbooks.spec.js`
Expected: FAIL nos 3 testes novos (`roteiro-comuns` não existe).

- [ ] **Step 3: Backend das palavras-chave**

Em `app/controllers/api/v1/accounts/theses_controller.rb`, trocar `permitted_params` por:

```ruby
  def permitted_params
    params.permit(:name, :description, :area, :active, :honorario_percentual, :honorario_n_mensalidades,
                  :honorario_minimo_qtd, :honorario_minimo_base, :honorario_na_tabela, palavras_chave: [])
  end
```

Em `app/views/api/v1/accounts/theses/show.json.jbuilder`, depois de `json.honorario_na_tabela @thesis.honorario_na_tabela`:

```ruby
json.palavras_chave @thesis.palavras_chave
```

- [ ] **Step 4: Playbooks.vue**

a) Imports — trocar

```js
import { mensagemErro } from '../helpers/erro';
import {
  CARTAO,
  SECAO,
  TITULO,
  CAMPO,
  CAMPO_GRANDE,
  TEXTAREA,
  ROTULO,
  CHIP,
  TOM,
  AVISO,
} from '../helpers/ui';
```

por:

```js
import { mensagemErro } from '../helpers/erro';
import RoteiroPassosAPI from 'dashboard/api/roteiroPassos';
import RoteiroEditor from '../components/roteiro/RoteiroEditor.vue';
import { listaParaTexto, textoParaLista } from '../helpers/roteiro';
import {
  CARTAO,
  SECAO,
  TITULO,
  CAMPO,
  CAMPO_GRANDE,
  TEXTAREA,
  ROTULO,
  CHIP,
  TOM,
  AVISO,
  ABA,
  ABA_ATIVA,
  ABA_INATIVA,
} from '../helpers/ui';
```

b) No `reactive` do `detail`, depois de `honorarioNaTabela: false,`:

```js
  palavrasChave: '',
```

c) No `syncDetail`, depois de `detail.honorarioNaTabela = !!thesis.honorario_na_tabela;`:

```js
  detail.palavrasChave = listaParaTexto(thesis.palavras_chave);
```

d) No `saveDetail`, depois de `honorario_na_tabela: detail.honorarioNaTabela,`:

```js
      palavras_chave: textoParaLista(detail.palavrasChave),
```

e) Trocar `onMounted(() => store.dispatch('theses/get'));` por:

```js
// Roteiro da IA (F2): todos os passos da conta numa busca só; cada editor filtra o seu escopo.
const passos = ref([]);
const calculadoras = ref({});
const carregarPassos = async () => {
  try {
    const { data } = await RoteiroPassosAPI.get();
    passos.value = data.payload || [];
    calculadoras.value = data.calculadoras || {};
  } catch (e) {
    useAlert(mensagemErro(e, t('RAMON.FUNIL.SAVE_ERROR')));
  }
};
const abaDetalhe = ref('playbook');
const passosDaTese = computed(
  () => passos.value.filter(p => p.thesis_id === selectedId.value).length
);

onMounted(() => {
  store.dispatch('theses/get');
  // etapas e motivos de perda das saídas do roteiro
  store.dispatch('leadConfig/get');
  carregarPassos();
});
```

f) Template — cartão dos passos comuns: trocar

```html
      <RamonPageHeader class="!mb-0" :title="$t('RAMON.PLAYBOOKS.TITLE')" />
```

por:

```html
      <RamonPageHeader class="!mb-0" :title="$t('RAMON.PLAYBOOKS.TITLE')" />

      <section
        class="flex flex-col gap-3 !p-4"
        :class="CARTAO"
        data-testid="roteiro-comuns"
      >
        <div>
          <h2 class="m-0" :class="TITULO">
            {{ $t('RAMON.ROTEIRO_IA.EDITOR.COMUNS_TITULO') }}
          </h2>
          <p class="m-0 mt-1 text-xs text-n-slate-10">
            {{ $t('RAMON.ROTEIRO_IA.EDITOR.COMUNS_AJUDA') }}
          </p>
        </div>
        <RoteiroEditor
          :thesis-id="null"
          :passos="passos"
          :calculadoras="calculadoras"
          @mudou="carregarPassos"
        />
      </section>
```

g) Template — palavras-chave no cabeçalho da tese: trocar

```html
              <div class="grid gap-3 md:grid-cols-3">
                <label :class="ROTULO">
                  {{ $t('RAMON.PLAYBOOKS.AREA') }}
```

por:

```html
              <label
                :class="ROTULO"
                :title="$t('RAMON.ROTEIRO_IA.PALAVRAS_CHAVE_AJUDA')"
              >
                {{ $t('RAMON.ROTEIRO_IA.PALAVRAS_CHAVE') }}
                <input
                  v-model="detail.palavrasChave"
                  data-testid="playbooks-palavras-chave-input"
                  :class="CAMPO"
                  :placeholder="$t('RAMON.ROTEIRO_IA.PALAVRAS_CHAVE_AJUDA')"
                  @blur="saveDetail"
                />
              </label>
              <div class="grid gap-3 md:grid-cols-3">
                <label :class="ROTULO">
                  {{ $t('RAMON.PLAYBOOKS.AREA') }}
```

h) Template — abas do detalhe: trocar

```html
            <p
              data-testid="playbooks-nome-hint"
```

por:

```html
            <nav
              class="flex gap-1 border-b border-n-weak"
              data-testid="playbooks-abas"
            >
              <button
                type="button"
                data-testid="playbooks-aba-playbook"
                :class="[
                  ABA,
                  abaDetalhe === 'playbook' ? ABA_ATIVA : ABA_INATIVA,
                ]"
                @click="abaDetalhe = 'playbook'"
              >
                {{ $t('RAMON.ROTEIRO_IA.EDITOR.ABA_PLAYBOOK') }}
              </button>
              <button
                type="button"
                data-testid="playbooks-aba-roteiro"
                :class="[
                  ABA,
                  abaDetalhe === 'roteiro' ? ABA_ATIVA : ABA_INATIVA,
                ]"
                @click="abaDetalhe = 'roteiro'"
              >
                {{ $t('RAMON.ROTEIRO_IA.EDITOR.ABA_ROTEIRO') }}
                <span class="font-mono text-[11px]">{{ passosDaTese }}</span>
              </button>
            </nav>

            <section
              v-if="abaDetalhe === 'roteiro'"
              class="flex flex-col gap-3 !p-4"
              :class="CARTAO"
              data-testid="playbooks-roteiro"
            >
              <p class="m-0 text-xs text-n-slate-10">
                {{ $t('RAMON.ROTEIRO_IA.EDITOR.ROTEIRO_AJUDA') }}
              </p>
              <RoteiroEditor
                :thesis-id="selectedThesis.id"
                :passos="passos"
                :calculadoras="calculadoras"
                @mudou="carregarPassos"
              />
            </section>

            <template v-else>
            <p
              data-testid="playbooks-nome-hint"
```

i) Template — fechar o `v-else`: trocar

```html
              </section>
            </div>
          </template>
        </div>
      </div>
    </div>
    <ConfirmModal
      v-if="thesisToRemove"
```

por:

```html
              </section>
            </div>
            </template>
          </template>
        </div>
      </div>
    </div>
    <ConfirmModal
      v-if="thesisToRemove"
```

(o `eslint --fix` do Step 6 acerta a indentação do bloco embrulhado.)

- [ ] **Step 5: Rodar e ver passar**

Run: `node_modules/.bin/vitest run --no-cache app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Playbooks.spec.js`
Expected: PASS (todos, inclusive os 6 antigos).

- [ ] **Step 6: Lint + commit**

```bash
node_modules/.bin/eslint --fix app/javascript/dashboard/routes/dashboard/ramon/pages/Playbooks.vue \
  app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Playbooks.spec.js
rubocop-vps app/controllers/api/v1/accounts/theses_controller.rb app/views/api/v1/accounts/theses/show.json.jbuilder \
  spec/requests/api/v1/accounts/theses_controller_spec.rb
git add app/controllers/api/v1/accounts/theses_controller.rb app/views/api/v1/accounts/theses/show.json.jbuilder \
  spec/requests/api/v1/accounts/theses_controller_spec.rb app/javascript/dashboard/routes/dashboard/ramon/pages/Playbooks.vue \
  app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Playbooks.spec.js
git commit -m "feat(roteiro): Playbooks com passos comuns, aba Roteiro da IA e palavras-chave da tese"
```

---

### Task 5: Painel do lead — roteiro passo a passo e "Reabrir roteiro"

**Files:**
- Modify: `app/javascript/dashboard/api/leads.js`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/RoteiroDoLead.vue`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/RoteiroDoLead.spec.js`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/QualificacaoViva.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/QualificacaoViva.spec.js`

**Interfaces:**
- Consumes: endpoints e `roteiro_versao` da Task 2; `RAMON.ROTEIRO_IA.*` (Task 3)
- Produces:
  - `LeadsAPI.roteiro(leadId)`, `LeadsAPI.reabrirRoteiro(leadId)`
  - `<RoteiroDoLead :roteiro="painel" :lead-id="Number|null" :bloqueio="''|'ganho'|'perdido'" @reaberto="painel" />` — sem `leadId` (Testar) não mostra o reabrir; testids `panel-card-roteiro`, `roteiro-contagem`, `roteiro-desfecho`, `roteiro-passo`, `roteiro-calc`, `roteiro-respondidos`, `roteiro-reabrir`, `roteiro-bloqueio`
  - `QualificacaoViva` passa a mostrar `RoteiroDoLead` quando o lead tem roteiro (checklist só se não tem roteiro ou se a tese só tem passos comuns). `LeadPanelBody.vue` não muda.

- [ ] **Step 1: Specs (falham)**

`app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/RoteiroDoLead.spec.js`:

```js
import { mount, flushPromises } from '@vue/test-utils';
import LeadsAPI from 'dashboard/api/leads';
import RoteiroDoLead from '../RoteiroDoLead.vue';

vi.mock('dashboard/api/leads', () => ({ default: { reabrirRoteiro: vi.fn() } }));
const alertSpy = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...a) => alertSpy(...a),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const linha = (chave, situacao, extra = {}) => ({
  chave,
  titulo: chave.toUpperCase(),
  comum: false,
  situacao,
  valor: null,
  saida: null,
  calc: null,
  ...extra,
});
const EM_ANDAMENTO = {
  desfecho: null,
  motivo: null,
  decisivo: null,
  aguarda_equipe: false,
  so_comuns: false,
  passos: [
    linha('tem_advogado', 'respondido', { valor: 'nao' }),
    linha('recebeu', 'respondido', { valor: 'sim' }),
    linha('nascimento', 'fora'),
    linha('renda', 'atual'),
    linha('moradores', 'pendente'),
  ],
};
const ENCERRADO = {
  ...EM_ANDAMENTO,
  desfecho: 'desqualificado',
  motivo: 'fora do período de graça',
  decisivo: 'graca',
  aguarda_equipe: true,
  passos: [
    linha('tem_advogado', 'respondido', { valor: 'nao' }),
    linha('graca', 'respondido', {
      valor: '2022-01-01',
      calc: { resultado: 'fora', detalhe: 'mais de 36 meses' },
    }),
    linha('renda', 'fora'),
  ],
};

const montar = props =>
  mount(RoteiroDoLead, { props, global: { mocks: { $t: k => k } } });
const titulos = w =>
  w.findAll('[data-testid="roteiro-passo"]').map(l => l.text());

describe('RoteiroDoLead', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('à vista só o atual e os a perguntar; respondidos atrás do toggle', async () => {
    const wrapper = montar({ roteiro: EM_ANDAMENTO, leadId: 7 });
    expect(titulos(wrapper)).toEqual(['RENDA', 'MORADORES']);
    expect(wrapper.find('[data-testid="roteiro-reabrir"]').exists()).toBe(false);
    await wrapper.find('[data-testid="roteiro-respondidos"]').trigger('click');
    expect(titulos(wrapper)).toHaveLength(5);
    expect(titulos(wrapper)[1]).toContain('sim');
  });

  it('desfecho com motivo e conta; reabrir confirma e devolve o painel novo', async () => {
    LeadsAPI.reabrirRoteiro.mockResolvedValue({ data: EM_ANDAMENTO });
    const wrapper = montar({ roteiro: ENCERRADO, leadId: 7 });
    expect(wrapper.find('[data-testid="roteiro-desfecho"]').text()).toContain(
      'fora do período de graça'
    );
    await wrapper.find('[data-testid="roteiro-respondidos"]').trigger('click');
    expect(wrapper.find('[data-testid="roteiro-calc"]').text()).toBe('fora');
    await wrapper.find('[data-testid="roteiro-reabrir"]').trigger('click');
    await wrapper.find('[data-testid="confirm-modal-confirm"]').trigger('click');
    await flushPromises();
    expect(LeadsAPI.reabrirRoteiro).toHaveBeenCalledWith(7);
    expect(wrapper.emitted('reaberto')[0]).toEqual([EM_ANDAMENTO]);
  });

  it('lead perdido mostra a dica no lugar do botão; no Testar (sem lead) não há reabrir', () => {
    const perdido = montar({ roteiro: ENCERRADO, leadId: 7, bloqueio: 'perdido' });
    expect(perdido.find('[data-testid="roteiro-bloqueio"]').exists()).toBe(true);
    expect(perdido.find('[data-testid="roteiro-reabrir"]').exists()).toBe(false);
    const testar = montar({ roteiro: ENCERRADO });
    expect(testar.find('[data-testid="roteiro-reabrir"]').exists()).toBe(false);
    expect(testar.find('[data-testid="roteiro-bloqueio"]').exists()).toBe(false);
  });
});
```

Em `app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/QualificacaoViva.spec.js`:

a) Trocar `import { shallowMount } from '@vue/test-utils';` por `import { shallowMount, flushPromises } from '@vue/test-utils';` e, depois de `import QualificacaoViva from '../QualificacaoViva.vue';`:

```js
import LeadsAPI from 'dashboard/api/leads';
import RoteiroDoLead from '../RoteiroDoLead.vue';

vi.mock('dashboard/api/leads', () => ({
  default: { roteiro: vi.fn(() => Promise.resolve({ data: null })) },
}));
```

b) No `beforeEach` existente, acrescentar `LeadsAPI.roteiro.mockClear();`.

c) Antes do `});` final do `describe`:

```js

  it('com roteiro na tese mostra o roteiro no lugar do checklist', async () => {
    LeadsAPI.roteiro.mockResolvedValueOnce({
      data: {
        so_comuns: false,
        passos: [{ chave: 'a', titulo: 'A', situacao: 'atual' }],
      },
    });
    const wrapper = mountQualificacao(baseLead);
    await flushPromises();
    expect(LeadsAPI.roteiro).toHaveBeenCalledWith(3);
    expect(wrapper.findComponent(RoteiroDoLead).exists()).toBe(true);
    expect(
      wrapper.find('[data-testid="panel-card-qualificacao"]').exists()
    ).toBe(false);
  });

  it('tese só com passos comuns: roteiro e checklist juntos', async () => {
    LeadsAPI.roteiro.mockResolvedValueOnce({
      data: {
        so_comuns: true,
        passos: [{ chave: 'a', titulo: 'A', situacao: 'respondido' }],
      },
    });
    const wrapper = mountQualificacao(baseLead);
    await flushPromises();
    expect(wrapper.findComponent(RoteiroDoLead).exists()).toBe(true);
    expect(
      wrapper.find('[data-testid="panel-card-qualificacao"]').exists()
    ).toBe(true);
  });

  it('recarrega só quando a roteiro_versao muda', async () => {
    const wrapper = mountQualificacao({ ...baseLead, roteiro_versao: 'a' });
    await flushPromises();
    await wrapper.setProps({ lead: { ...baseLead, roteiro_versao: 'a', name: 'Ana Maria' } });
    await flushPromises();
    expect(LeadsAPI.roteiro).toHaveBeenCalledTimes(1);
    await wrapper.setProps({ lead: { ...baseLead, roteiro_versao: 'b' } });
    await flushPromises();
    expect(LeadsAPI.roteiro).toHaveBeenCalledTimes(2);
  });
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `node_modules/.bin/vitest run --no-cache app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/RoteiroDoLead.spec.js app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/QualificacaoViva.spec.js`
Expected: FAIL — `../RoteiroDoLead.vue` não existe.

- [ ] **Step 3: API**

Em `app/javascript/dashboard/api/leads.js`, logo depois do método `followUpDraft(leadId) { … }`:

```js

  // Roteiro da IA no painel (F2): passo a passo + desfecho; data null = lead sem roteiro.
  roteiro(leadId) {
    return axios.get(`${this.url}/${leadId}/roteiro`);
  }

  // Volta no passo que decidiu; devolve o painel novo (422 se ganho/perdido ou em andamento).
  reabrirRoteiro(leadId) {
    return axios.post(`${this.url}/${leadId}/reabrir_roteiro`);
  }
```

- [ ] **Step 4: RoteiroDoLead**

`app/javascript/dashboard/routes/dashboard/ramon/components/lead/RoteiroDoLead.vue`:

```vue
<script setup>
// Roteiro da IA no painel do lead e no Testar (F2): passo a passo (respondido / pergunta agora / a perguntar /
// não perguntado), resultado das calculadoras e o desfecho com motivo. Com leadId, "Reabrir roteiro".
// Mesma cara da Qualificação viva: à vista só o que falta; respondidos atrás do toggle.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import LeadsAPI from 'dashboard/api/leads';
import ConfirmModal from '../ConfirmModal.vue';
import { mensagemErro } from '../../helpers/erro';
import { AVISO, CARTAO, CHIP, TITULO, TOM } from '../../helpers/ui';

const props = defineProps({
  // painel montado pelo servidor (Ramon::Roteiro::Painel)
  roteiro: { type: Object, required: true },
  // sem leadId (Testar): só mostra, sem reabrir
  leadId: { type: Number, default: null },
  // 'ganho' | 'perdido' | '' — lead fechado não reabre por aqui
  bloqueio: { type: String, default: '' },
});
const emit = defineEmits(['reaberto']);
const { t } = useI18n();

const ICONE = {
  respondido: 'i-lucide-check text-n-teal-11',
  atual: 'i-lucide-arrow-right text-n-blue-11',
  pendente: 'i-lucide-circle-dashed text-n-slate-10',
  fora: 'i-lucide-minus text-n-slate-9',
};
const TOM_DESFECHO = {
  qualificado: TOM.teal,
  desqualificado: TOM.ruby,
  humano: TOM.amber,
};

const passos = computed(() => props.roteiro.passos || []);
const respondidos = computed(
  () => passos.value.filter(p => p.situacao === 'respondido').length
);
// a barra conta o que foi ou ainda vai ser perguntado (pulado pelo "vai para" não entra)
const total = computed(
  () => passos.value.filter(p => p.situacao !== 'fora').length
);
const faltam = computed(() =>
  passos.value.filter(p => ['atual', 'pendente'].includes(p.situacao))
);
const abertos = ref(false);
const visiveis = computed(() => (abertos.value ? passos.value : faltam.value));
const decisivo = computed(
  () => passos.value.find(p => p.chave === props.roteiro.decisivo)?.titulo || ''
);
const resposta = passo => passo.valor ?? passo.saida ?? '';

const confirmando = ref(false);
const reabrindo = ref(false);
const reabrir = async () => {
  confirmando.value = false;
  reabrindo.value = true;
  try {
    const { data } = await LeadsAPI.reabrirRoteiro(props.leadId);
    emit('reaberto', data);
    useAlert(t('RAMON.ROTEIRO_IA.REABERTO'));
  } catch (e) {
    useAlert(mensagemErro(e, t('RAMON.FUNIL.SAVE_ERROR')));
  } finally {
    reabrindo.value = false;
  }
};
</script>

<template>
  <div :class="CARTAO" data-testid="panel-card-roteiro">
    <div class="flex items-center gap-2">
      <p :class="TITULO">{{ $t('RAMON.ROTEIRO_IA.TITULO') }}</p>
      <div class="flex-1 h-1 overflow-hidden rounded-full bg-n-alpha-2">
        <div
          class="h-full bg-n-teal-9"
          :style="{ width: `${total ? (respondidos / total) * 100 : 0}%` }"
        />
      </div>
      <span
        class="font-mono text-xs font-semibold text-n-slate-12"
        data-testid="roteiro-contagem"
      >
        {{ $t('RAMON.ROTEIRO_IA.CONTAGEM', { ok: respondidos, total }) }}
      </span>
    </div>

    <div v-if="roteiro.desfecho" class="mt-2 flex flex-col gap-1">
      <p
        data-testid="roteiro-desfecho"
        class="m-0"
        :class="[AVISO, TOM_DESFECHO[roteiro.desfecho]]"
      >
        <span class="font-semibold">
          {{
            $t(`RAMON.ROTEIRO_IA.DESFECHO.${roteiro.desfecho.toUpperCase()}`)
          }}
        </span>
        <template v-if="roteiro.motivo"> — {{ roteiro.motivo }}</template>
      </p>
      <p v-if="roteiro.aguarda_equipe" class="m-0 text-xs text-n-slate-11">
        {{ $t('RAMON.ROTEIRO_IA.AGUARDA_EQUIPE') }}
      </p>
      <template v-if="leadId">
        <p
          v-if="bloqueio"
          data-testid="roteiro-bloqueio"
          class="m-0 text-xs text-n-slate-10"
        >
          {{ $t(`RAMON.ROTEIRO_IA.REABRIR_${bloqueio.toUpperCase()}`) }}
        </p>
        <Button
          v-else
          data-testid="roteiro-reabrir"
          link
          xs
          slate
          icon="i-lucide-rotate-ccw"
          class="self-start"
          :label="$t('RAMON.ROTEIRO_IA.REABRIR')"
          :disabled="reabrindo"
          @click="confirmando = true"
        />
      </template>
    </div>
    <p
      v-else-if="roteiro.so_comuns && !faltam.length"
      class="m-0 mt-2 text-xs text-n-slate-11"
    >
      {{ $t('RAMON.ROTEIRO_IA.COMUNS_CONCLUIDOS') }}
    </p>

    <div class="mt-1 flex flex-col">
      <div
        v-for="passo in visiveis"
        :key="passo.chave"
        data-testid="roteiro-passo"
        class="flex items-center gap-2 py-1 text-[12.5px]"
      >
        <span
          class="size-3.5 shrink-0"
          :class="ICONE[passo.situacao]"
          :title="
            $t(`RAMON.ROTEIRO_IA.SITUACAO.${passo.situacao.toUpperCase()}`)
          "
        />
        <span
          class="min-w-0 truncate"
          :class="
            passo.situacao === 'atual'
              ? 'font-medium text-n-slate-12'
              : 'text-n-slate-11'
          "
        >
          {{ passo.titulo }}
        </span>
        <span
          v-if="resposta(passo)"
          class="ml-auto max-w-[45%] shrink-0 truncate font-mono text-xs text-n-slate-12"
          :title="resposta(passo)"
        >
          {{ resposta(passo) }}
        </span>
        <span
          v-if="passo.calc"
          data-testid="roteiro-calc"
          class="shrink-0"
          :class="[CHIP, TOM.iris]"
          :title="passo.calc.detalhe"
        >
          {{ passo.calc.resultado }}
        </span>
      </div>
      <Button
        v-if="respondidos"
        data-testid="roteiro-respondidos"
        link
        slate
        xs
        trailing-icon
        class="self-start mt-1"
        :icon="abertos ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right'"
        :label="$t('RAMON.ROTEIRO_IA.RESPONDIDOS', { count: respondidos })"
        @click="abertos = !abertos"
      />
    </div>
    <ConfirmModal
      v-if="confirmando"
      :title="$t('RAMON.ROTEIRO_IA.REABRIR_CONFIRMA')"
      :message="$t('RAMON.ROTEIRO_IA.REABRIR_AJUDA', { passo: decisivo })"
      :confirm-label="$t('RAMON.ROTEIRO_IA.REABRIR')"
      confirm-color="blue"
      @confirm="reabrir"
      @cancel="confirmando = false"
    />
  </div>
</template>
```

- [ ] **Step 5: QualificacaoViva vira a porta do roteiro**

Em `QualificacaoViva.vue`:

a) Depois de `import Button from 'dashboard/components-next/button/Button.vue';`:

```js
import LeadsAPI from 'dashboard/api/leads';
import RoteiroDoLead from './RoteiroDoLead.vue';
```

b) Depois do `const criterios = computed(…);`:

```js

// Roteiro da IA (F2): com passos na tese, o card mostra o roteiro passo a passo no lugar do checklist (tese só com
// os passos comuns mostra os dois). Recarrega quando o broadcast do lead traz outra roteiro_versao — a chave em
// texto evita recarregar a cada broadcast que não mexeu no roteiro.
const roteiro = ref(null);
let pedido = 0;
const carregarRoteiro = async () => {
  pedido += 1;
  const meu = pedido;
  if (!props.lead?.id || !props.lead?.thesis_id) {
    roteiro.value = null;
    return;
  }
  try {
    const { data } = await LeadsAPI.roteiro(props.lead.id);
    if (meu === pedido) roteiro.value = data?.passos ? data : null;
  } catch {
    if (meu === pedido) roteiro.value = null;
  }
};
watch(
  () =>
    `${props.lead?.id}|${props.lead?.thesis_id}|${props.lead?.roteiro_versao}`,
  carregarRoteiro,
  { immediate: true }
);
const bloqueio = computed(() => {
  if (props.lead?.won_at) return 'ganho';
  return props.lead?.lost_at ? 'perdido' : '';
});
```

c) No template, trocar

```html
  <div
    v-if="lead?.thesis_id && criterios.length"
    :class="CARTAO"
    data-testid="panel-card-qualificacao"
  >
```

por:

```html
  <RoteiroDoLead
    v-if="roteiro"
    :roteiro="roteiro"
    :lead-id="lead.id"
    :bloqueio="bloqueio"
    @reaberto="roteiro = $event"
  />
  <div
    v-if="
      lead?.thesis_id && criterios.length && (!roteiro || roteiro.so_comuns)
    "
    :class="CARTAO"
    data-testid="panel-card-qualificacao"
  >
```

- [ ] **Step 6: Rodar e ver passar**

Run: `node_modules/.bin/vitest run --no-cache app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/RoteiroDoLead.spec.js app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/QualificacaoViva.spec.js app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadPanelBody.spec.js`
Expected: PASS (o `LeadPanelBody.spec` antigo continua verde; se ele montar `QualificacaoViva` de verdade e reclamar de `LeadsAPI.roteiro`, acrescentar `roteiro: vi.fn(() => Promise.resolve({ data: null }))` ao mock de `dashboard/api/leads` daquele spec).

- [ ] **Step 7: Lint + commit**

```bash
node_modules/.bin/eslint --fix app/javascript/dashboard/api/leads.js \
  app/javascript/dashboard/routes/dashboard/ramon/components/lead/RoteiroDoLead.vue \
  app/javascript/dashboard/routes/dashboard/ramon/components/lead/QualificacaoViva.vue \
  app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/RoteiroDoLead.spec.js \
  app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/QualificacaoViva.spec.js
git add app/javascript/dashboard/api/leads.js \
  app/javascript/dashboard/routes/dashboard/ramon/components/lead/RoteiroDoLead.vue \
  app/javascript/dashboard/routes/dashboard/ramon/components/lead/QualificacaoViva.vue \
  app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/
git commit -m "feat(roteiro): roteiro da IA passo a passo no painel do lead, com reabrir"
```

---

### Task 6: Testar com tese (roteiro em teste, nada gravado)

**Files:**
- Create: `app/services/ramon/roteiro/teste.rb`
- Create: `spec/services/ramon/roteiro/teste_spec.rb`
- Create: `enterprise/app/services/captain/assistant/playground_runner_service.rb`
- Modify: `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb` (`playground` + `playground_runner`)
- Modify: `enterprise/lib/captain/tools/roteiro_passo_atual_tool.rb`, `enterprise/lib/captain/tools/roteiro_registrar_tool.rb` (F1)
- Modify: `app/javascript/dashboard/api/captain/assistant.js` (`playground`)
- Modify: `app/javascript/dashboard/components-next/captain/assistant/testarConversas.js`
- Modify: `app/javascript/dashboard/components-next/captain/assistant/AssistantPlayground.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/assistants/playground/Index.vue`
- Modify: `app/javascript/dashboard/components-next/captain/assistant/specs/AssistantPlayground.spec.js`, `…/specs/testarConversas.spec.js`

**Interfaces:**
- Consumes: `Ramon::Roteiro.atual/registrar/descrever/resumo` (F1), `Ramon::Roteiro::Painel.montar` (Task 2), `<RoteiroDoLead>` (Task 5), `RAMON.ROTEIRO_IA.TESTAR.*` (Task 3)
- Produces:
  - `Ramon::Roteiro::Teste.de_params(account, roteiro_hash_ou_nil) -> { 'thesis_id' => Integer, 'estado' => Hash|nil } | nil` (só tese da conta)
  - `.atual(account, teste) -> String | nil`, `.registrar(account, teste, chave:, valor: nil, saida_id: nil) -> [String, Hash|nil]`, `.painel(account, teste) -> Hash|nil`, `.resposta(account, teste) -> { 'thesis_id', 'estado', 'painel' }`
  - Playground: corpo aceita `roteiro: { thesis_id, estado }`; resposta ganha `roteiro: { thesis_id, estado, painel }` quando há tese
  - `state[:roteiro_teste]` nas tools do roteiro (playground com tese)
  - `testarConversas`: `roteiroDe(id) -> { thesisId, estado, painel }` (criado por `garantirConversa`); `limparConversa` zera estado/painel e mantém a tese
  - testid `testar-roteiro-tese`

- [ ] **Step 1: Specs (falham)**

`spec/services/ramon/roteiro/teste_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Roteiro::Teste do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }
  let(:teste) { described_class.de_params(account, { 'thesis_id' => thesis.id.to_s }) }

  before do
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'recebeu', position: 0, titulo: 'Recebeu',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'humano', 'motivo' => 'recebeu' },
                                    { 'id' => 'nao', 'quando' => 'nao', 'acao' => 'seguir' }])
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'renda', position: 1, titulo: 'Renda', tipo_resposta: 'numero')
  end

  it 'roda o motor de verdade, devolve o estado e não grava nada' do
    expect(described_class.atual(account, teste)).to include('Passo atual: Recebeu')

    texto, estado = described_class.registrar(account, teste, chave: 'recebeu', valor: 'nao')
    expect(texto).to include('Passo atual: Renda')
    expect(estado.dig('respostas', 'recebeu', 'valor')).to eq('nao')
    expect(described_class.atual(account, teste.merge('estado' => estado))).to include('Passo atual: Renda')
    expect([Lead.count, LeadActivity.count, CopilotSuggestion.count]).to eq([0, 0, 0])
  end

  it 'equipe no teste: desfecho no estado e no painel, sem sino' do
    create(:user, account: account, role: :administrator)
    _texto, estado = described_class.registrar(account, teste, chave: 'recebeu', valor: 'sim')
    expect(estado).to include('desfecho' => 'humano', 'motivo' => 'recebeu')
    resposta = described_class.resposta(account, teste.merge('estado' => estado))
    expect(resposta).to include('thesis_id' => thesis.id, 'estado' => estado)
    expect(resposta['painel']).to include('desfecho' => 'humano')
    expect([Notification.count, Lead.count]).to eq([0, 0])
  end

  it 'valor inválido volta o erro para a IA e o estado não muda' do
    texto, estado = described_class.registrar(account, teste, chave: 'recebeu', valor: 'talvez')
    expect(texto).to eq('Responda sim ou nao.')
    expect(estado).to be_nil
  end

  it 'de_params: só tese da conta; sem tese = sem teste; estado vira Hash simples' do
    expect(described_class.de_params(account, { thesis_id: create(:thesis, account: create(:account)).id })).to be_nil
    expect(described_class.de_params(account, nil)).to be_nil
    expect(described_class.de_params(account, { thesis_id: thesis.id, estado: { 'respostas' => {} } }))
      .to eq('thesis_id' => thesis.id, 'estado' => { 'respostas' => {} })
  end
end
```

Em `app/javascript/dashboard/components-next/captain/assistant/specs/testarConversas.spec.js`:

a) Trocar o import por:

```js
import {
  conversaDe,
  garantirConversa,
  limparConversa,
  roteiroDe,
} from '../testarConversas';
```

b) Antes do `});` final:

```js

  it('roteiro do Testar: limpar a conversa zera o estado e mantém a tese', () => {
    garantirConversa(1);
    Object.assign(roteiroDe(1), {
      thesisId: 3,
      estado: { a: 1 },
      painel: { passos: [] },
    });
    limparConversa(1);
    expect(roteiroDe(1)).toEqual({ thesisId: 3, estado: null, painel: null });
    roteiroDe(1).thesisId = null;
  });
```

Em `app/javascript/dashboard/components-next/captain/assistant/specs/AssistantPlayground.spec.js`:

a) Trocar `import { conversaDe, limparConversa } from '../testarConversas';` por `import { conversaDe, limparConversa, roteiroDe } from '../testarConversas';`.

b) Antes do `});` final:

```js

  it('roteiro em teste: manda a tese e o estado, guarda o que volta', async () => {
    CaptainAssistant.playground.mockResolvedValue({
      data: {
        response: 'Você recebeu auxílio-doença?',
        roteiro: {
          thesis_id: 3,
          estado: { respostas: { tem_advogado: { valor: 'nao' } } },
          painel: { passos: [] },
        },
      },
    });
    const wrapper = mount(AssistantPlayground, { props: { assistantId: 1 } });
    roteiroDe(1).thesisId = 3;
    await enviar(wrapper, 'não tenho advogado');
    await flushPromises();
    expect(CaptainAssistant.playground).toHaveBeenCalledWith(
      expect.objectContaining({ roteiro: { thesis_id: 3, estado: null } })
    );
    expect(roteiroDe(1).estado).toEqual({
      respostas: { tem_advogado: { valor: 'nao' } },
    });
    expect(roteiroDe(1).painel).toEqual({ passos: [] });
    roteiroDe(1).thesisId = null;
  });
```

- [ ] **Step 2: Rodar os specs JS e ver falhar**

Run: `node_modules/.bin/vitest run --no-cache app/javascript/dashboard/components-next/captain/assistant/specs/`
Expected: FAIL — `roteiroDe` não é exportado.

- [ ] **Step 3: `Ramon::Roteiro::Teste`**

`app/services/ramon/roteiro/teste.rb`:

```ruby
# Testar com tese (spec §3.8.5): o motor de verdade num lead descartável, dentro de uma transação desfeita — nada
# fica gravado (lead, respostas, histórico, sugestões, sino). Sem conversa = fora do piloto total (Perdido vira
# sugestão, como em rascunho). O estado do roteiro vai e volta pelo Testar a cada mensagem.
# teste = { 'thesis_id' => id, 'estado' => estado do roteiro ou nil }
# ponytail: o push do ntfy (perform_later) sai da transação, acha o lead apagado e não envia.
module Ramon::Roteiro::Teste
  NOME = 'Teste do roteiro'.freeze

  module_function

  # Do corpo do playground: só tese da conta; estado vira Hash simples (chaves texto).
  def de_params(account, roteiro)
    roteiro = (roteiro || {}).to_h.with_indifferent_access
    tese = account.theses.find_by(id: roteiro[:thesis_id]) if roteiro[:thesis_id].present?
    tese && { 'thesis_id' => tese.id, 'estado' => roteiro[:estado].presence&.to_hash }
  end

  # Texto do passo atual para a IA; nil = a tese não tem roteiro.
  def atual(account, teste)
    rodar(account, teste) do |lead|
      atual = Ramon::Roteiro.atual(lead)
      Ramon::Roteiro.descrever(atual[:passo], atual[:estado]) if atual
    end.first
  end

  # @return [texto para a IA, estado depois]
  def registrar(account, teste, chave:, valor: nil, saida_id: nil)
    rodar(account, teste) do |lead|
      res = Ramon::Roteiro.registrar(lead, chave: chave, valor: valor, saida_id: saida_id)
      res[:erro] || Ramon::Roteiro.resumo(res)
    end
  end

  def painel(account, teste)
    rodar(account, teste) { |lead| Ramon::Roteiro::Painel.montar(lead) }.first
  end

  # O que o Testar recebe de volta: o estado (vai de novo na próxima mensagem) e o passo a passo para a tela.
  def resposta(account, teste)
    { 'thesis_id' => teste['thesis_id'], 'estado' => teste['estado'], 'painel' => painel(account, teste) }
  end

  # @return [resultado do bloco, estado do roteiro depois]
  def rodar(account, teste)
    saida = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      etapa = account.lead_stages.where(is_won: false, is_lost: false).order(:position).first
      lead = account.leads.create!(name: NOME, thesis_id: teste['thesis_id'], lead_stage: etapa,
                                   custom_attributes: { 'roteiro' => teste['estado'] }.compact)
      resultado = yield lead
      saida = [resultado, lead.reload.custom_attributes['roteiro']]
      raise ActiveRecord::Rollback
    end
    saida
  end
end
```

- [ ] **Step 4: Enterprise — runner, controller e tools** (sem spec no CI; prova na Task 8)

`enterprise/app/services/captain/assistant/playground_runner_service.rb`:

```ruby
# ramon (roteiro F2): Testar com tese — o roteiro em teste vai no state das tools (Ramon::Roteiro::Teste), que
# devolvem o estado novo nele. Subclasse para não mexer no AgentRunnerService (no teto do ClassLength).
class Captain::Assistant::PlaygroundRunnerService < Captain::Assistant::AgentRunnerService
  def initialize(roteiro_teste:, **)
    super(**)
    @roteiro_teste = roteiro_teste
  end

  private

  def build_state
    super.merge(roteiro_teste: @roteiro_teste)
  end
end
```

Em `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb`, trocar o método `playground` inteiro

```ruby
  def playground
    return render(json: playground_legado) unless captain_v2_enabled?

    # ramon (I-PG2): as ferramentas que rodaram nesta resposta vão junto, para o Testar mostrar debaixo dela.
    ferramentas = []
    coletor = ->(nome, retorno, *) { ferramentas << ferramenta_usada(nome, retorno) }
    runner = Captain::Assistant::AgentRunnerService.new(assistant: @assistant, source: 'playground',
                                                        callbacks: { on_tool_complete: coletor })
    render json: runner.generate_response(message_history: playground_message_history).merge('ferramentas' => ferramentas)
  end
```

por:

```ruby
  def playground
    return render(json: playground_legado) unless captain_v2_enabled?

    # ramon (I-PG2): as ferramentas que rodaram nesta resposta vão junto, para o Testar mostrar debaixo dela.
    # ramon (roteiro F2): com tese escolhida no Testar, o roteiro roda em teste e o estado novo volta junto.
    ferramentas = []
    teste = Ramon::Roteiro::Teste.de_params(Current.account, params[:roteiro]&.to_unsafe_h)
    coletor = lambda do |nome, retorno, contexto = nil, *|
      ferramentas << ferramenta_usada(nome, retorno)
      teste = contexto&.context&.dig(:state, :roteiro_teste) || teste
    end
    resposta = playground_runner(coletor, teste).generate_response(message_history: playground_message_history)
    resposta = resposta.merge('ferramentas' => ferramentas)
    render json: teste ? resposta.merge('roteiro' => Ramon::Roteiro::Teste.resposta(Current.account, teste)) : resposta
  end
```

E na seção `private`, logo depois de `playground_legado`:

```ruby

  def playground_runner(coletor, teste)
    opcoes = { assistant: @assistant, source: 'playground', callbacks: { on_tool_complete: coletor } }
    return Captain::Assistant::AgentRunnerService.new(**opcoes) if teste.nil?

    Captain::Assistant::PlaygroundRunnerService.new(roteiro_teste: teste, **opcoes)
  end
```

Em `enterprise/lib/captain/tools/roteiro_passo_atual_tool.rb` (arquivo da F1), no início do `perform`, trocar

```ruby
  def perform(tool_context, lead_id: nil)
    lead = resolver_lead(tool_context.state, lead_id)
```

por:

```ruby
  def perform(tool_context, lead_id: nil)
    # Testar com tese (F2): roteiro em teste, sem lead — nada é gravado.
    teste = tool_context.state&.dig(:roteiro_teste)
    return ::Ramon::Roteiro::Teste.atual(@assistant.account, teste) || SEM_ROTEIRO if teste

    lead = resolver_lead(tool_context.state, lead_id)
```

Em `enterprise/lib/captain/tools/roteiro_registrar_tool.rb` (arquivo da F1), trocar

```ruby
  def perform(tool_context, chave:, valor: nil, saida_id: nil, lead_id: nil)
    lead = resolver_lead(tool_context.state, lead_id)
```

por:

```ruby
  def perform(tool_context, chave:, valor: nil, saida_id: nil, lead_id: nil)
    teste = tool_context.state&.dig(:roteiro_teste)
    return registrar_em_teste(teste, chave: chave, valor: valor, saida_id: saida_id) if teste

    lead = resolver_lead(tool_context.state, lead_id)
```

e, antes do último `end` da classe:

```ruby

  private

  # Testar com tese (F2): o motor roda num lead descartável; o estado novo fica no state e o Testar devolve à tela.
  def registrar_em_teste(teste, **resposta)
    texto, teste['estado'] = ::Ramon::Roteiro::Teste.registrar(@assistant.account, teste, **resposta)
    texto
  end
```

- [ ] **Step 5: Front do Testar**

`app/javascript/dashboard/api/captain/assistant.js` — trocar o método `playground` por:

```js
  // ramon (roteiro F2): roteiro = { thesis_id, estado } quando o Testar escolheu uma tese.
  playground({ assistantId, messageContent, messageHistory, roteiro }) {
    return axios.post(`${this.url}/${assistantId}/playground`, {
      message_content: messageContent,
      message_history: messageHistory,
      ...(roteiro ? { roteiro } : {}),
    });
  }
```

`app/javascript/dashboard/components-next/captain/assistant/testarConversas.js` — trocar desde `const conversas = reactive({});` até o fim do arquivo por:

```js
const conversas = reactive({});
// Roteiro da tese em teste (F2): a tese escolhida e o estado que o servidor devolve a cada resposta (nada é gravado).
const roteiros = reactive({});

export const garantirConversa = id => {
  if (!conversas[id]) conversas[id] = [];
  if (!roteiros[id]) roteiros[id] = { thesisId: null, estado: null, painel: null };
};

export const conversaDe = id => conversas[id] || [];

export const roteiroDe = id => roteiros[id];

export const limparConversa = id => {
  conversas[id] = [];
  // a tese escolhida fica; o roteiro recomeça junto com a conversa
  if (roteiros[id]) Object.assign(roteiros[id], { estado: null, painel: null });
};
```

`app/javascript/dashboard/components-next/captain/assistant/AssistantPlayground.vue`:

a) Trocar o import

```js
import {
  conversaDe,
  garantirConversa,
  limparConversa,
} from './testarConversas';
```

por:

```js
import {
  conversaDe,
  garantirConversa,
  limparConversa,
  roteiroDe,
} from './testarConversas';
```

b) Em `sendMessage`, trocar

```js
  const conversa = conversaDe(assistantId);
  conversa.push(userMessage);
```

por:

```js
  const conversa = conversaDe(assistantId);
  // roteiro em teste (tese escolhida no Testar): vai o estado, volta o novo — nada é gravado (F2)
  const roteiro = roteiroDe(assistantId);
  conversa.push(userMessage);
```

c) Trocar

```js
    const { data } = await CaptainAssistant.playground({
      assistantId,
      messageContent: currentMessage,
      messageHistory: historico,
    });
```

por:

```js
    const { data } = await CaptainAssistant.playground({
      assistantId,
      messageContent: currentMessage,
      messageHistory: historico,
      roteiro: roteiro?.thesisId
        ? { thesis_id: roteiro.thesisId, estado: roteiro.estado }
        : null,
    });
    if (data.roteiro && roteiro) {
      Object.assign(roteiro, {
        estado: data.roteiro.estado,
        painel: data.roteiro.painel,
      });
    }
```

`app/javascript/dashboard/routes/dashboard/captain/assistants/playground/Index.vue` — conteúdo novo do arquivo inteiro:

```vue
<script setup>
// Testar: a conversa avulsa com o assistente (AssistantPlayground) + atalhos da A5 — falas das skills
// (as do seu papel primeiro, I-X5), "Testar com o caso…" (I-PG4) e a fala vinda de "Testar esta skill"
// (?fala=, I-SK6). Nada é enviado sozinho: os atalhos só escrevem no campo (N7).
// Roteiro da tese (F2): escolher a tese faz a IA seguir o roteiro dela; o roteiro roda de verdade, nada é
// gravado, e o passo a passo aparece ao lado da conversa.
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import AssistantPlayground from 'dashboard/components-next/captain/assistant/AssistantPlayground.vue';
import {
  garantirConversa,
  roteiroDe,
} from 'dashboard/components-next/captain/assistant/testarConversas';
import RoteiroDoLead from 'dashboard/routes/dashboard/ramon/components/lead/RoteiroDoLead.vue';
import AbasTestar from '../../casos/AbasTestar.vue';
import TestarComCaso from './TestarComCaso.vue';
import { referenciaCaso, skillsDoPapel } from './testar';
import {
  CHIP,
  SELECT,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

const VISIVEIS = 8;

const { t } = useI18n();
const route = useRoute();
const store = useStore();
const assistantId = computed(() => Number(route.params.assistantId));
const playground = ref(null);

const skills = useMapGetter('captainScenarios/getRecords');
const meusTimes = useMapGetter('teams/getMyTeams');
const teses = useMapGetter('theses/getTheses');
const sugestoes = computed(() =>
  skillsDoPapel(skills.value, meusTimes.value).slice(0, VISIVEIS)
);
const roteiro = computed(() => roteiroDe(assistantId.value));

watch(
  assistantId,
  id => {
    garantirConversa(id);
    store.dispatch('captainScenarios/get', { assistantId: id });
  },
  { immediate: true }
);

onMounted(async () => {
  store.dispatch('teams/get');
  store.dispatch('theses/get');
  await nextTick();
  if (route.query?.fala) playground.value?.escrever(String(route.query.fala));
});

const usarCaso = lead => playground.value?.anexar(referenciaCaso(lead));

// Trocar a tese recomeça o roteiro do teste (a conversa fica — limpe-a para começar do zero).
const escolherTese = evento => {
  Object.assign(roteiro.value, {
    thesisId: Number(evento.target.value) || null,
    estado: null,
    painel: null,
  });
};
</script>

<template>
  <PageLayout
    show-assistant-switcher
    :show-pagination-footer="false"
    class="h-full"
  >
    <template #subHeader>
      <AbasTestar ativa="conversa" />
    </template>
    <template #body>
      <div class="flex flex-col h-full gap-3">
        <div class="flex flex-wrap items-start gap-3">
          <TestarComCaso class="w-72 shrink-0" @escolher="usarCaso" />
          <select
            data-testid="testar-roteiro-tese"
            class="!w-60 shrink-0"
            :class="SELECT"
            :value="roteiro?.thesisId || ''"
            :title="t('RAMON.ROTEIRO_IA.TESTAR.AJUDA')"
            :aria-label="t('RAMON.ROTEIRO_IA.TESTAR.AJUDA')"
            @change="escolherTese"
          >
            <option value="">{{ t('RAMON.ROTEIRO_IA.TESTAR.SEM_TESE') }}</option>
            <option v-for="tese in teses" :key="tese.id" :value="tese.id">
              {{ tese.name }}
            </option>
          </select>
          <div
            v-if="sugestoes.length"
            data-testid="testar-sugestoes"
            class="flex flex-wrap items-center flex-1 min-w-0 gap-1.5"
          >
            <span :class="TITULO">{{ t('INTEL.TESTAR.SUGESTOES') }}</span>
            <button
              v-for="skill in sugestoes"
              :key="skill.id"
              type="button"
              data-testid="testar-sugestao"
              class="hover:brightness-110"
              :class="[CHIP, skill.meu ? TOM.blue : TOM.slate]"
              :title="skill.exemplo"
              @click="playground?.escrever(skill.exemplo)"
            >
              {{ skill.title }}
            </button>
          </div>
        </div>
        <div class="flex flex-1 min-h-0 gap-3">
          <AssistantPlayground
            ref="playground"
            :assistant-id="assistantId"
            class="flex-1 min-w-0 min-h-0 bg-n-solid-1"
          />
          <RoteiroDoLead
            v-if="roteiro?.painel"
            class="w-72 shrink-0 self-start"
            :roteiro="roteiro.painel"
          />
        </div>
      </div>
    </template>
  </PageLayout>
</template>
```

- [ ] **Step 6: Rodar os specs JS e ver passar**

Run: `node_modules/.bin/vitest run --no-cache app/javascript/dashboard/components-next/captain/assistant/specs/ app/javascript/dashboard/routes/dashboard/captain/assistants/playground/specs/`
Expected: PASS.

- [ ] **Step 7: Lint + commit**

```bash
rubocop-vps app/services/ramon/roteiro/teste.rb spec/services/ramon/roteiro/teste_spec.rb \
  enterprise/app/services/captain/assistant/playground_runner_service.rb \
  enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb \
  enterprise/lib/captain/tools/roteiro_passo_atual_tool.rb enterprise/lib/captain/tools/roteiro_registrar_tool.rb
node_modules/.bin/eslint --fix app/javascript/dashboard/api/captain/assistant.js \
  app/javascript/dashboard/components-next/captain/assistant/testarConversas.js \
  app/javascript/dashboard/components-next/captain/assistant/AssistantPlayground.vue \
  app/javascript/dashboard/routes/dashboard/captain/assistants/playground/Index.vue \
  app/javascript/dashboard/components-next/captain/assistant/specs/
git add app/services/ramon/roteiro/teste.rb spec/services/ramon/roteiro/teste_spec.rb \
  enterprise/app/services/captain/assistant/playground_runner_service.rb \
  enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb \
  enterprise/lib/captain/tools/roteiro_passo_atual_tool.rb enterprise/lib/captain/tools/roteiro_registrar_tool.rb \
  app/javascript/dashboard/api/captain/assistant.js app/javascript/dashboard/components-next/captain/assistant/ \
  app/javascript/dashboard/routes/dashboard/captain/assistants/playground/Index.vue
git commit -m "feat(roteiro): Testar com tese — a IA segue o roteiro em teste, sem gravar nada"
```

---

### Task 7: Prints claro/escuro para o aprovado do Eduardo (antes do PR)

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/pages/RoteiroTelas.story.vue`
- Create (não versionado): `tmp/roteiro-harness/` (cópia de `../ramon-hub-wt-conteudo-tv-relatorios/tmp/harness/`)
- Create (fora do repo): `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-roteiro-f2-telas\` (PNGs + `comparar.html`)

**Interfaces:**
- Consumes: `Playbooks.vue` (Task 4), `RoteiroDoLead.vue` (Task 5)
- Produces: página de aprovação; **parar e esperar o "aprovado" do Eduardo** antes da Task 8

- [ ] **Step 1: Story com dados fictícios**

`app/javascript/dashboard/routes/dashboard/ramon/pages/RoteiroTelas.story.vue`:

```vue
<script setup>
// Story das telas do roteiro da IA (F2) — aprovação visual por print, claro/escuro.
// Sem rede: window.axios responde com dados FICTÍCIOS por URL. Os textos são exemplo de tela,
// não o conteúdo dos roteiros (esse entra na F4, com o aprovado do Eduardo).
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import Playbooks from './Playbooks.vue';
import RoteiroDoLead from '../components/lead/RoteiroDoLead.vue';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

const TESE = {
  id: 1,
  name: 'Auxílio-acidente (exemplo)',
  area: 'previdenciario',
  active: true,
  position: 0,
  palavras_chave: ['acidente', 'sequela'],
  items: [],
};
const passo = (id, thesisId, position, chave, titulo, extra = {}) => ({
  id,
  thesis_id: thesisId,
  position,
  chave,
  titulo,
  orientacao: '',
  tipo_resposta: 'sim_nao',
  opcoes: [],
  calculadora: null,
  calculadora_campos: {},
  saidas: [],
  edited: true,
  ...extra,
});
const PASSOS = [
  passo(1, null, 0, 'tem_advogado', 'Já tem advogado no caso', {
    saidas: [
      {
        id: 'sim',
        quando: 'sim',
        acao: 'desqualificar',
        motivo: 'tem advogado',
        motivo_perda: 'Outro',
        efeitos: { etiqueta: 'TemAdvogado' },
      },
      { id: 'nao', quando: 'nao', acao: 'seguir' },
    ],
  }),
  passo(2, 1, 0, 'recebeu_auxilio', 'Recebeu auxílio-doença pelo acidente', {
    orientacao: '(exemplo) Pergunte se ficou afastado recebendo do INSS.',
    saidas: [
      { id: 'sim', quando: 'sim', acao: 'ir_para', alvo: 'sequela' },
      { id: 'nao', quando: 'nao', acao: 'seguir' },
    ],
  }),
  passo(3, 1, 1, 'data_acidente', 'Data do acidente', {
    tipo_resposta: 'data',
  }),
  passo(4, 1, 2, 'graca', 'Último emprego com carteira', {
    tipo_resposta: 'data',
    calculadora: 'periodo_de_graca',
    calculadora_campos: { ultimo_vinculo: 'graca', evento: 'data_acidente' },
    saidas: [
      { id: 's1', quando: 'dentro', acao: 'seguir' },
      {
        id: 's2',
        quando: 'fora',
        acao: 'desqualificar',
        motivo: 'fora do período de graça',
      },
      { id: 's3', quando: '*', acao: 'humano', motivo: 'graça depende' },
    ],
  }),
  passo(5, 1, 3, 'sequela', 'Ficou sequela', {
    tipo_resposta: 'texto',
    saidas: [
      {
        id: 's1',
        quando: 'ficou alguma limitação',
        acao: 'concluir',
        efeitos: { etapa: 'Qualificação' },
      },
      { id: 's2', quando: 'voltou 100%', acao: 'desqualificar', motivo: 'sem sequela' },
    ],
  }),
];
const CALCULADORAS = {
  periodo_de_graca: {
    campos: ['ultimo_vinculo', 'evento', 'mais_de_120', 'desemprego', 'facultativa'],
    resultados: ['dentro', 'fora', 'depende'],
  },
  renda_per_capita: { campos: ['renda_total', 'moradores'], resultados: ['abaixo', 'acima', 'depende'] },
  prescricao_5_anos: { campos: ['data'], resultados: ['dentro', 'ultimo_ano', 'prescrito', 'depende'] },
  meses_ate_65: { campos: ['nascimento'], resultados: ['ja_tem_65', 'menos_de_65', 'depende'] },
  data_prevista_parto: { campos: ['semanas'], resultados: ['ja_pode_pedir', 'aguardar', 'depende'] },
  prazo_inss: { campos: ['requerimento', 'pericia'], resultados: ['aguardar', 'forcar_julgamento', 'depende'] },
};
const API = {
  lead_config: {
    stages: [
      { id: 1, name: 'Novo', position: 0, is_won: false, is_lost: false },
      { id: 2, name: 'Qualificação', position: 1, is_won: false, is_lost: false },
      { id: 9, name: 'Perdido', position: 9, is_won: false, is_lost: true },
    ],
    lost_reasons: [
      { id: 1, name: 'Sem viabilidade' },
      { id: 2, name: 'Outro' },
    ],
  },
  theses: [TESE],
  'theses/1': TESE,
  roteiro_passos: { payload: PASSOS, calculadoras: CALCULADORAS },
};
const caminho = url => url.replace(/^\/api\/v1\/(accounts\/\d+\/)?/, '');
const responder = async url => ({ data: API[caminho(url)] ?? {} });
window.axios = {
  get: responder,
  post: responder,
  patch: responder,
  put: responder,
  delete: responder,
};

const store = useStore();
// sem router: getCurrentAccountId lê a conta de rootState.route
store.registerModule('route', { state: { params: { accountId: 1 } } });

const clicar = (testid, n = 0) =>
  document.querySelectorAll(`[data-testid="${testid}"]`)[n]?.click();
const abrirRoteiro = then => () =>
  setTimeout(() => {
    clicar('playbooks-item');
    setTimeout(() => {
      clicar('playbooks-aba-roteiro');
      if (then) setTimeout(then, 300);
    }, 400);
  }, 1200);
const roteiroDaTese = abrirRoteiro();
// índice 3 = 1 passo comum + 3º passo da tese (Último emprego com carteira)
const passoAberto = abrirRoteiro(() => clicar('roteiro-passo-abrir', 3));

const linha = (chave, titulo, situacao, extra = {}) => ({
  chave,
  titulo,
  comum: false,
  situacao,
  valor: null,
  saida: null,
  calc: null,
  ...extra,
});
const PAINEL_ANDAMENTO = {
  desfecho: null,
  motivo: null,
  decisivo: null,
  aguarda_equipe: false,
  so_comuns: false,
  passos: [
    linha('tem_advogado', 'Já tem advogado no caso', 'respondido', { comum: true, valor: 'nao' }),
    linha('recebeu_auxilio', 'Recebeu auxílio-doença pelo acidente', 'respondido', { valor: 'nao' }),
    linha('data_acidente', 'Data do acidente', 'respondido', { valor: '2026-01-10' }),
    linha('graca', 'Último emprego com carteira', 'atual'),
    linha('sequela', 'Ficou sequela', 'pendente'),
  ],
};
const PAINEL_DESQUALIFICADO = {
  desfecho: 'desqualificado',
  motivo: 'fora do período de graça',
  decisivo: 'graca',
  aguarda_equipe: true,
  so_comuns: false,
  passos: [
    linha('tem_advogado', 'Já tem advogado no caso', 'respondido', { comum: true, valor: 'nao' }),
    linha('recebeu_auxilio', 'Recebeu auxílio-doença pelo acidente', 'respondido', { valor: 'nao' }),
    linha('data_acidente', 'Data do acidente', 'respondido', { valor: '2026-01-10' }),
    linha('graca', 'Último emprego com carteira', 'respondido', {
      valor: '2022-01-01',
      calc: { resultado: 'fora', detalhe: 'mais de 36 meses sem contribuir' },
    }),
    linha('sequela', 'Ficou sequela', 'fora'),
  ],
};
</script>

<template>
  <Story title="Ramon/Roteiro da IA" :layout="{ type: 'single' }">
    <Variant title="Passos comuns">
      <div class="h-screen"><Playbooks /></div>
    </Variant>
    <Variant title="Roteiro da tese" :init-state="roteiroDaTese">
      <div class="h-screen"><Playbooks /></div>
    </Variant>
    <Variant title="Passo aberto" :init-state="passoAberto">
      <div class="h-screen"><Playbooks /></div>
    </Variant>
    <Variant title="Painel em andamento">
      <div class="h-screen bg-n-background py-6">
        <div class="mx-auto w-[400px]">
          <RoteiroDoLead :roteiro="PAINEL_ANDAMENTO" :lead-id="42" />
        </div>
      </div>
    </Variant>
    <Variant title="Painel desqualificado">
      <div class="h-screen bg-n-background py-6">
        <div class="mx-auto w-[400px]">
          <RoteiroDoLead :roteiro="PAINEL_DESQUALIFICADO" :lead-id="42" />
        </div>
      </div>
    </Variant>
  </Story>
</template>
```

- [ ] **Step 2: Harness e prints**

```bash
cp -r ../ramon-hub-wt-conteudo-tv-relatorios/tmp/harness tmp/roteiro-harness
sed -i "s#pages/ConteudoTvRelatorios.story.vue#pages/RoteiroTelas.story.vue#; s#|| 'Conteudo'#|| 'Passos comuns'#" tmp/roteiro-harness/main.js
sed -i "s#port: 6209#port: 6213#" tmp/roteiro-harness/vite.config.mts
```

`tmp/roteiro-harness/shots.sh` (substitui o copiado):

```sh
#!/bin/sh
# uso: sh tmp/roteiro-harness/shots.sh depois  → PNGs em comercial/docs/mockups/2026-10-roteiro-f2-telas
fase=$1
out="C:/Users/dudsl/RAdvogados/comercial/docs/mockups/2026-10-roteiro-f2-telas"
mkdir -p "$out"
chrome="/c/Program Files/Google/Chrome/Application/chrome.exe"
for v in "Passos comuns:passos-comuns:1440,1000" "Roteiro da tese:roteiro-da-tese:1440,1400" \
         "Passo aberto:passo-aberto:1440,1800" "Painel em andamento:painel-andamento:520,520" \
         "Painel desqualificado:painel-desqualificado:520,520"; do
  nome=$(echo "$v" | cut -d: -f1); arq=$(echo "$v" | cut -d: -f2); tam=$(echo "$v" | cut -d: -f3)
  q=$(echo "$nome" | sed 's/ /%20/g')
  for tema in claro escuro; do
    "$chrome" --headless=new --disable-gpu --hide-scrollbars --window-size=$tam \
      --virtual-time-budget=15000 --screenshot="$out/$fase-$tema-$arq.png" \
      "http://localhost:6213/?variant=$q&tema=$tema" >/dev/null 2>&1 &
  done
done
wait
ls "$out" | grep "^$fase"
```

Run (dois terminais): `node_modules/.bin/vite --config tmp/roteiro-harness/vite.config.mts` e depois `sh tmp/roteiro-harness/shots.sh depois`
Expected: 10 PNGs `depois-{claro,escuro}-*.png`. Abrir cada um e conferir: fonte Geist (não Courier — se cair, subir o `--virtual-time-budget`), nada cortado, fundos coloridos translúcidos, botões do components-next.

- [ ] **Step 3: Página de aprovação**

Em `comercial\docs\mockups\2026-10-roteiro-f2-telas\comparar.html`, seguindo a estrutura de `comercial\docs\mockups\2026-10-06-padrao-playbooks-config\comparar.html` (claro e escuro lado a lado, uma seção por variante), incluir:
- as 5 variantes (claro/escuro), com uma linha dizendo o que cada tela faz;
- o "antes" de referência: `2026-10-06-padrao-playbooks-config\depois-claro-tese-aberta.png` (Playbooks hoje);
- a lista das **Decisões que tomei sem perguntar** deste plano (copiar a seção do topo), para o Eduardo marcar o que muda;
- **sugestões conferidas** (o Eduardo escolhe; cada uma vira PR separado se escolhida): (1) selo "roteiro" nas sugestões do Cockpit que vêm do roteiro; (2) selo do desfecho do roteiro no card do funil; (3) arrastar para reordenar os passos.

- [ ] **Step 4: Parar** — mandar ao Eduardo o caminho clicável da pasta `comercial\docs\mockups\2026-10-roteiro-f2-telas\` e esperar o "aprovado". Ajustes pedidos → corrigir, reprintar, repetir. Commit da story só depois:

```bash
node_modules/.bin/eslint --fix app/javascript/dashboard/routes/dashboard/ramon/pages/RoteiroTelas.story.vue
git add app/javascript/dashboard/routes/dashboard/ramon/pages/RoteiroTelas.story.vue
git commit -m "chore(roteiro): story das telas do roteiro da IA para aprovação por print"
```

---

### Task 8: PR, CI, merge, deploy, prova e registro

**Files:**
- Create (fora do repo): `C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-roteiro-f2-smoke.md`
- Modify: `C:\Users\dudsl\.claude\projects\C--Users-dudsl-RAdvogados\memory\roteiro-da-tese.md`

- [ ] **Step 1: Suite JS inteira das áreas tocadas**

Run: `node_modules/.bin/vitest run --no-cache app/javascript/dashboard/routes/dashboard/ramon/ app/javascript/dashboard/components-next/captain/assistant/ app/javascript/dashboard/routes/dashboard/captain/assistants/`
Expected: PASS.

- [ ] **Step 2: Push e PR** (push = Eduardo via `!` se o classificador barrar)

```bash
git push -u origin feat/roteiro-f2-telas
gh pr create --base ramon --title "feat(roteiro): telas do roteiro da tese (F2)" --body-file <corpo>
```

Corpo: parágrafo de produto ("o admin cadastra o roteiro da IA na tela Playbooks — passos comuns e por tese —, a equipe vê o roteiro passo a passo no painel do lead e pode reabrir, e o Testar conversa seguindo o roteiro de uma tese sem gravar nada; sem passos cadastrados nada muda"); as decisões do topo deste plano; "Como testar" = o smoke do Step 6; o aviso de que conteúdo de roteiro (F4) e a skill de triagem (F1) dependem do aprovado do Eduardo; rodapé de atribuição.

- [ ] **Step 3: CI 100% verde** — spec/lint vermelho → corrigir, `rubocop-vps`, novo commit (sem amend). 429/503 baixando actions = re-rodar o job; jobs cancelados sem runner = conferir githubstatus antes de mexer no código.

- [ ] **Step 4: Merge (squash) e deploy** — regime autônomo com CI verde (CLAUDE.md do ramon-hub); se o classificador barrar o `gh pr merge`, o Eduardo roda via `!`. **Sem migração.** Na VPS (`ssh root@185.194.216.67`, `/opt/intranet-ramon`): `docker pull ghcr.io/doods-maker/ramon-hub:sha-<7>` + `docker tag ghcr.io/doods-maker/ramon-hub:sha-<7> ghcr.io/doods-maker/ramon-hub:v4.15.1-ramon` + `docker compose up -d chatwoot-web chatwoot-worker`. Conferir a label da imagem (`docker inspect`) e login 200 em https://chat.ramonantonio.adv.br.

- [ ] **Step 5: Prova em produção sem deixar rastro** (tudo numa transação desfeita). Rodar via `cat prova.rb | ssh root@185.194.216.67 'cd /opt/intranet-ramon && docker compose exec -T chatwoot-web bundle exec rails runner "eval(STDIN.read)"'`:

```ruby
ActiveRecord::Base.transaction do
  a = Account.find(2)
  t = a.theses.create!(name: "Prova F2 #{Time.now.to_i}")
  RoteiroPasso.create!(account: a, thesis: t, position: 0, chave: 'recebeu', titulo: 'Recebeu auxilio',
                       saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'humano', 'motivo' => 'prova' },
                                { 'id' => 'nao', 'quando' => 'nao', 'acao' => 'seguir' }])
  RoteiroPasso.create!(account: a, thesis: t, position: 1, chave: 'renda', titulo: 'Renda', tipo_resposta: 'numero')

  # Conferência do salvar da tela
  p Ramon::Roteiro::Conferencia.erros(RoteiroPasso.new(account: a, thesis: t, chave: 'x', titulo: 'X',
                                                       saidas: [{ 'id' => 's1', 'quando' => '*', 'acao' => 'ir_para', 'alvo' => 'sumiu' }]))
  # => ["o passo de destino 'sumiu' não existe neste roteiro"]

  # Testar com tese pelas tools (sem LLM): nada gravado
  asst = Captain::Assistant.find_by(account: a, name: 'Atendimento')
  ctx = Struct.new(:state).new({ roteiro_teste: Ramon::Roteiro::Teste.de_params(a, { thesis_id: t.id }) })
  antes = [Lead.count, LeadActivity.count, Notification.count]
  puts Captain::Tools::RoteiroPassoAtualTool.new(asst).perform(ctx)                          # Passo atual: Recebeu auxilio
  puts Captain::Tools::RoteiroRegistrarTool.new(asst).perform(ctx, chave: 'recebeu', valor: 'nao') # ... Passo atual: Renda
  p ctx.state[:roteiro_teste]['estado']['respostas'].keys                                    # ["recebeu"]
  p [Lead.count, LeadActivity.count, Notification.count] == antes                            # true

  # Painel + reabrir
  etapa = a.lead_stages.where(is_won: false, is_lost: false).order(:position).first
  lead = a.leads.create!(name: 'Prova F2', thesis: t, lead_stage: etapa)
  Ramon::Roteiro.registrar(lead, chave: 'recebeu', valor: 'sim')
  p Ramon::Roteiro::Painel.montar(lead.reload).slice('desfecho', 'motivo', 'decisivo')       # humano / prova / recebeu
  p lead.roteiro_versao.present?                                                              # true
  p Ramon::Roteiro.reabrir(lead)                                                              # true
  p Ramon::Roteiro::Painel.montar(lead.reload)['passos'].first['situacao']                    # "atual"
  raise ActiveRecord::Rollback
end
puts RoteiroPasso.where("titulo LIKE 'Recebeu auxilio%'").count # => 0
```

- [ ] **Step 6: Smoke para o Eduardo** — criar `comercial\docs\2026-10-roteiro-f2-smoke.md` em blocos por tela (regra: smoke em bloco por seção, nunca pergunta a pergunta):
  - **A. Playbooks:** o cartão "Passos comuns do roteiro da IA" aparece no topo; criar um passo comum de teste (ex.: "Teste — pode apagar", sim/não, sem saídas) → aparece; ↑↓ e remover funcionam; abrir uma tese → aba "Roteiro da IA" com contador; criar um passo com "Vai para" apontando para outro → salva; tentar remover o passo apontado → recusa dizendo quem aponta; campo Palavras-chave salva e volta ao reabrir a tese. Apagar os passos de teste no fim.
  - **B. Painel do lead:** (só depois de existir um roteiro numa tese — F4 ou passo de teste numa tese de teste) lead dessa tese na caixa Teste mostra o cartão "Roteiro da IA" no lugar da Qualificação; respondendo pela IA o cartão atualiza sozinho; com desfecho, "Reabrir roteiro" confirma e volta no passo que decidiu; lead no Perdido mostra a dica em vez do botão.
  - **C. Testar:** Inteligência → Testar → escolher a tese no seletor "Sem roteiro de tese" → conversar: o passo a passo aparece ao lado e nenhum lead novo surge no funil. **Depende** da skill de triagem nova (texto da F1) estar ativada com o `seed[2]`; sem ela a IA não chama o roteiro.

- [ ] **Step 7: Registro** — atualizar `memory\roteiro-da-tese.md`: PR, squash, VPS sha, prova OK, smoke aguardando Eduardo (doc acima), pasta de prints aprovada, decisões aprovadas/alteradas na revisão; próximo = plano F3 (tese automática + modos "sozinho até…" + configurações da caixa).
