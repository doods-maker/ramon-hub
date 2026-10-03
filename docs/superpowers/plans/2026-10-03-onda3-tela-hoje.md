# Onda 3 — Tela "Hoje" por papel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A primeira tela de cada pessoa responde "o que eu faço agora?", igual ao mockup v2 (tela Hoje), por papel: gestor, SDR, Closer, Recepção, Advogada (e "equipe").

**Architecture:** Um endpoint `GET /api/v1/accounts/:id/ramon_hoje` devolve `{ papel, data, ... }` montado por `Ramon::Hoje` (decide o papel no backend com `Ramon::Papeis.papel_de`) e delega a três montadores (`Gestor`, `Comercial`, `Escritorio`). A página `Hoje.vue` substitui o Centro de Comando na rota `ramon_index` (o Centro de Comando vai pra `ramon_painel`, no "Mais"), e escolhe o componente do papel. Componentes pequenos e reaproveitáveis (`SeloPrazo`, `Selo`, `AlertaCaixa`, `HojeBloco`) — o `SeloPrazo` volta nas Ondas 4 e 5.

**Tech Stack:** Rails 7.1 (service objects `pattr_initialize`, RSpec + FactoryBot), Vue 3 `<script setup>`, Tailwind, Vitest.

**Spec:** `docs/superpowers/specs/2026-10-03-redesign-v2-fiel-ao-mockup.md` · alvo visual `docs/superpowers/specs/mockups/2026-10-03-hub-v2.html` (tela `.t-hoje`, blocos `data-for`).

## Global Constraints

- Branch `feat/tela-hoje` empilhada em `feat/menu-unico` (Onda 2). Mesmo esquema de rebase após o squash.
- Sem Ruby local: RSpec/Rubocop só no CI. Escreva Ruby curto (Rubocop: método ≤ ~10 linhas, AbcSize, CyclomaticComplexity ≤ 7, ClassLength ≤ 175, linha ≤ 150).
- Fuso: `Chegada::ZONA` (`America/Sao_Paulo`) para "hoje" e "este mês".
- ADVBOX: cota 500/dia compartilhada → toda chamada nova com `Rails.cache` (≥ 30 min) e `rescue` que devolve vazio + `advbox_fora: true`.
- Front: Tailwind só, i18n (`RAMON.HOJE.*` em pt_BR e en), números/horários/valores com `font-mono`, fundos coloridos translúcidos (`bg-n-ruby-9/10`, `bg-n-amber-9/15`, `bg-n-blue-9/[0.08] dark:bg-n-blue-9/[0.16]`, `bg-n-teal-9/15`).
- Nada envia mensagem sozinho: "Preparar follow-up" só gera RASCUNHO (endpoint existente) e abre a conversa; "Lembrar cliente" só abre a conversa.
- Testes: `TZ=UTC ./node_modules/.bin/vitest --no-watch <arquivos>` (se faltar `postcss-import`: `export NODE_PATH=$PWD/node_modules/.pnpm/postcss-import@15.1.0_postcss@8.4.47/node_modules`).

## Review Focus

1. Pessoa sem nenhum dado (SDR no 1º dia, recepção sem conversa) → cada bloco mostra texto de vazio, nunca some a tela nem dá erro.
2. ADVBOX fora/estourou cota → Recepção e Advogada veem o resto da tela e um aviso "ADVBOX indisponível agora" no bloco.
3. Lead cuja conversa foi apagada ou não tem inbox → não quebra o `Prazo` (usa `joins`, então some da lista).
4. Virada do dia/mês no fuso de SP (servidor em UTC) → "hoje" e "este mês" corretos às 22h de SP.
5. Agente comum chamando `ramon_hoje` → nunca recebe o bloco do gestor (papel é decidido no backend, não pelo front).

---

### Task 1: Papel no backend + endpoint vazio

**Files:**
- Modify: `app/services/ramon/papeis.rb` (`papel_de`)
- Create: `app/services/ramon/hoje.rb`
- Create: `app/controllers/api/v1/accounts/ramon_hoje_controller.rb`
- Modify: `config/routes.rb` (junto do `resource :ramon_dashboard`)
- Test: `spec/services/ramon/papeis_spec.rb` (acrescentar — `git grep` antes; se não existir, criar), `spec/requests/api/v1/accounts/ramon_hoje_spec.rb`

**Interfaces:**
- Produces: `Ramon::Papeis.papel_de(account, user) → 'gestor'|'recepcao'|'closer'|'sdr'|'advogada'|'equipe'` (mesma regra de `helpers/papel.js`); `Ramon::Hoje.new(account:, user:).perform → Hash` com `papel`, `data` (ISO, hoje em SP) e as chaves do papel; rota `GET /api/v1/accounts/:account_id/ramon_hoje`.

- [ ] **Step 1: Specs que falham**

`spec/services/ramon/papeis_spec.rb` (bloco novo):

```ruby
describe '.papel_de' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }

  def no_time(nome)
    team = create(:team, account: account, name: nome)
    create(:team_member, team: team, user: user)
  end

  it 'administrador é gestor' do
    admin = create(:user, account: account, role: :administrator)
    expect(described_class.papel_de(account, admin)).to eq('gestor')
  end

  it 'recepção (com acento) e controladoria viram recepcao' do
    no_time('recepção')
    expect(described_class.papel_de(account, user)).to eq('recepcao')
  end

  it 'closer vence sdr' do
    no_time('sdr')
    no_time('closer')
    expect(described_class.papel_de(account, user)).to eq('closer')
  end

  it 'advogados vira advogada; sem time é equipe' do
    expect(described_class.papel_de(account, user)).to eq('equipe')
    no_time('advogados')
    expect(described_class.papel_de(account, user)).to eq('advogada')
  end
end
```

`spec/requests/api/v1/accounts/ramon_hoje_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Ramon Hoje API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  it 'exige login' do
    get "/api/v1/accounts/#{account.id}/ramon_hoje"
    expect(response).to have_http_status(:unauthorized)
  end

  it 'agente sem time recebe papel equipe e nunca o bloco do gestor' do
    get "/api/v1/accounts/#{account.id}/ramon_hoje", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['papel']).to eq('equipe')
    expect(body).not_to have_key('precisa')
  end

  it 'admin recebe papel gestor' do
    get "/api/v1/accounts/#{account.id}/ramon_hoje", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['papel']).to eq('gestor')
  end
end
```

(Confira os nomes das factories `:team`/`:team_member` em `spec/factories`.)

- [ ] **Step 2: Implementar**

`papeis.rb` — acrescentar dentro do módulo:

```ruby
  # Mesma regra do front (helpers/papel.js) — o backend decide o que a tela Hoje entrega.
  ORDEM_PAPEL = [%w[recepcao recepcao], %w[controladoria recepcao], %w[closer closer], %w[sdr sdr], %w[advogados advogada]].freeze

  def papel_de(account, user)
    return 'gestor' if account.account_users.find_by(user: user)&.administrator?

    times = user.teams.where(account: account).pluck(:name).map { |nome| I18n.transliterate(nome.to_s).strip.downcase }
    ORDEM_PAPEL.each { |time, papel| return papel if times.include?(time) }
    'equipe'
  end
```

`app/services/ramon/hoje.rb`:

```ruby
# Tela "Hoje" (redesign v2, Onda 3): o que cada papel precisa fazer agora.
# O papel é decidido aqui, nunca pelo front.
class Ramon::Hoje
  pattr_initialize [:account!, :user!]

  def perform
    papel = Ramon::Papeis.papel_de(account, user)
    { papel: papel, data: Time.find_zone!(Chegada::ZONA).today.iso8601 }.merge(blocos(papel))
  end

  private

  def blocos(_papel)
    {}
  end
end
```

`ramon_hoje_controller.rb`:

```ruby
class Api::V1::Accounts::RamonHojeController < Api::V1::Accounts::BaseController
  def show
    authorize(:ramon_dashboard, :show?)
    render json: Ramon::Hoje.new(account: Current.account, user: Current.user).perform
  end
end
```

`routes.rb`: ao lado de `resource :ramon_dashboard ...` → `resource :ramon_hoje, only: [:show], controller: 'ramon_hoje'`

- [ ] **Step 3: Commit** — `feat(hoje): endpoint ramon_hoje e papel decidido no backend`

---

### Task 2: Prazo de 1ª resposta (compartilhado)

**Files:**
- Create: `app/services/ramon/hoje/prazo.rb`
- Test: `spec/services/ramon/hoje/prazo_spec.rb`

**Interfaces:**
- Produces: `Ramon::Hoje::Prazo.sem_resposta(leads_scope) → relation` (leads com conversa aberta em inbox de lead, sem 1ª resposta, criada nas últimas 48 h); `Ramon::Hoje::Prazo.estourados(leads_scope) → relation`; `Ramon::Hoje::Prazo.linha(lead) → { lead_id, nome, tese, canal, conversa_id (display_id), prazo_em (ISO), ultima_mensagem }`.

- [ ] **Step 1: Spec que falha**

```ruby
require 'rails_helper'

RSpec.describe Ramon::Hoje::Prazo do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, auto_create_lead: true, first_response_sla_minutes: 5) }

  def lead_com_conversa(criada_ha:, respondida: false)
    conversation = create(:conversation, account: account, inbox: inbox, created_at: criada_ha.ago)
    conversation.update_columns(first_reply_created_at: Time.current) if respondida
    create(:lead, account: account, conversation: conversation)
  end

  it 'sem_resposta pega só quem não teve 1ª resposta nas últimas 48 h' do
    pendente = lead_com_conversa(criada_ha: 2.minutes)
    lead_com_conversa(criada_ha: 2.minutes, respondida: true)
    lead_com_conversa(criada_ha: 3.days)
    expect(described_class.sem_resposta(account.leads)).to contain_exactly(pendente)
  end

  it 'estourados = sem resposta além do SLA da inbox' do
    lead_com_conversa(criada_ha: 2.minutes)
    atrasado = lead_com_conversa(criada_ha: 10.minutes)
    expect(described_class.estourados(account.leads)).to contain_exactly(atrasado)
  end

  it 'linha traz o prazo = criação + SLA da inbox, e o display_id da conversa' do
    lead = lead_com_conversa(criada_ha: 2.minutes)
    linha = described_class.linha(lead)
    expect(Time.zone.parse(linha[:prazo_em])).to be_within(1.second).of(lead.conversation.created_at + 5.minutes)
    expect(linha[:conversa_id]).to eq(lead.conversation.display_id)
  end
end
```

(Confira a factory `:lead` — se ela cria conversa própria, passe `conversation:` como no spec; se `lead_stage` for obrigatório, a factory já resolve.)

- [ ] **Step 2: Implementar**

```ruby
# Prazo de 1ª resposta do lead (SLA da inbox, fallback 5 min — Ramon::Cadencia).
# Usado pelo SDR ("Responder agora") e pelo gestor ("passaram dos 5 minutos").
module Ramon::Hoje::Prazo
  module_function

  JANELA = 48.hours

  def sem_resposta(leads)
    leads.funil.joins(conversation: :inbox)
         .where(inboxes: { auto_create_lead: true })
         .where(conversations: { first_reply_created_at: nil, status: :open, created_at: JANELA.ago.. })
         .includes(:thesis, conversation: :inbox)
         .reorder('conversations.created_at')
  end

  def estourados(leads)
    sem_resposta(leads)
      .where("EXTRACT(EPOCH FROM (? - conversations.created_at)) / 60.0 > (#{Ramon::Cadencia.sla_threshold_sql})", Time.current)
  end

  def linha(lead)
    conversa = lead.conversation
    {
      lead_id: lead.id, nome: lead.name, tese: lead.thesis&.name, canal: lead.channel,
      conversa_id: conversa.display_id,
      prazo_em: (conversa.created_at + Ramon::Cadencia.sla_minutes(conversa.inbox).minutes).iso8601,
      ultima_mensagem: conversa.messages.incoming.last&.content.to_s.truncate(80)
    }
  end
end
```

- [ ] **Step 3: Commit** — `feat(hoje): prazo de 1ª resposta compartilhado (SDR e gestor)`

---

### Task 3: Montador do gestor

**Files:**
- Create: `app/services/ramon/hoje/gestor.rb`
- Modify: `app/services/ramon/hoje.rb` (`blocos`)
- Test: `spec/services/ramon/hoje/gestor_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Hoje::Prazo` (Task 2), `Ramon::LeadRadar.pos_venda`, `Ramon::Cadencia.parados`, `Peca`, `Chegada.de_hoje`, `MetaComercial`.
- Produces: `Ramon::Hoje::Gestor.new(account:).perform → { precisa: [alerta], time: { sdr: {respondidos, media_minutos}, closer: {reunioes, contratos}, recepcao: {chegadas} }, mes: { contratos, meta_contratos (Integer|nil), reunioes_qualificadas, docs_completos, ganhos_mes }, funil: [{ etapa, cor, count }] }`. `alerta = { tipo: 'sla'|'parado'|'docs'|'conteudo', nivel: 'bad'|'warn'|'act', count, nomes?: [String], etapa?: String, dias?: Integer }`.

- [ ] **Step 1: Spec que falha** (`gestor_spec.rb`)

```ruby
require 'rails_helper'

RSpec.describe Ramon::Hoje::Gestor do
  let(:account) { create(:account) }
  subject(:hoje) { described_class.new(account: account).perform }

  it 'sem nada acontecendo: precisa vazio, números zerados, sem meta' do
    expect(hoje[:precisa]).to eq([])
    expect(hoje[:mes]).to include(contratos: 0, meta_contratos: nil, reunioes_qualificadas: 0)
  end

  it 'peça em rascunho vira alerta de conteúdo com o gancho' do
    create(:peca, account: account, status: 'rascunho', gancho: 'Quem tem direito')
    alerta = hoje[:precisa].find { |a| a[:tipo] == 'conteudo' }
    expect(alerta).to include(count: 1, nivel: 'act', nomes: ['Quem tem direito'])
  end

  it 'meta do mês = soma das metas dos closers do mês' do
    closer = create(:user, account: account)
    MetaComercial.create!(account: account, user: closer, papel: 'closer', mes: Time.find_zone!('America/Sao_Paulo').today.beginning_of_month, meta: 13)
    expect(hoje[:mes][:meta_contratos]).to eq(13)
  end

  it 'funil lista só etapas abertas, com contagem' do
    etapa = create(:lead_stage, account: account, name: 'Novo', is_won: false, is_lost: false)
    create(:lead, account: account, lead_stage: etapa)
    expect(hoje[:funil]).to include(hash_including(etapa: 'Novo', count: 1))
  end
end
```

(Confira a factory `:peca` — se não existir, crie `spec/factories/pecas.rb` mínima com `slug`, `gancho`, `rodada`, `tipo: 'carrossel'`, `status: 'rascunho'`. Confira colunas de `MetaComercial` no schema antes.)

- [ ] **Step 2: Implementar** (`gestor.rb`)

```ruby
# Tela Hoje do gestor: o que precisa dele, o time no dia, o mês e o funil agora.
class Ramon::Hoje::Gestor
  pattr_initialize [:account!]

  def perform
    { precisa: precisa, time: time_hoje, mes: mes, funil: funil }
  end

  private

  def zona = Time.find_zone!(Chegada::ZONA)
  def hoje = zona.now.all_day
  def mes_atual = zona.now.all_month
  def leads = account.leads.funil.reorder(nil)

  def precisa
    [sla, parado, docs, conteudo].compact
  end

  def sla
    atrasados = Ramon::Hoje::Prazo.estourados(account.leads).to_a
    { tipo: 'sla', nivel: 'bad', count: atrasados.size, nomes: atrasados.first(3).map(&:name) } if atrasados.any?
  end

  def parado
    abertos = leads.joins(:lead_stage).where(lead_stages: { is_won: false, is_lost: false })
    grupos = Ramon::Cadencia.parados(abertos).group('lead_stages.name', 'lead_stages.stalled_after_days').count
    return if grupos.empty?

    (etapa, dias), count = grupos.max_by { |_chave, total| total }
    { tipo: 'parado', nivel: 'warn', count: count, etapa: etapa, dias: dias }
  end

  def docs
    count = Ramon::LeadRadar.pos_venda(account)[:pendentes].count { |lead| lead.won_at < 7.days.ago }
    { tipo: 'docs', nivel: 'warn', count: count } if count.positive?
  end

  def conteudo
    pecas = Peca.where(account: account, status: 'rascunho').order(:created_at)
    { tipo: 'conteudo', nivel: 'act', count: pecas.count, nomes: pecas.limit(2).pluck(:gancho) } if pecas.exists?
  end

  def time_hoje
    respondidas = Ramon::Cadencia.sla_conversations(account, hoje).where.not(first_reply_created_at: nil)
    {
      sdr: { respondidos: respondidas.count, media_minutos: Ramon::CockpitMetrics.new(account).sla_today[:avg_first_response_minutes] },
      closer: { reunioes: account.lead_tasks.where(kind: 'meeting', due_at: hoje).count, contratos: leads.where(won_at: hoje).count },
      recepcao: { chegadas: Chegada.where(account: account).de_hoje.count }
    }
  end

  def mes
    ganhos = leads.where(won_at: mes_atual)
    {
      contratos: ganhos.count, ganhos_mes: ganhos.count, docs_completos: ganhos.where.not(docs_completos_em: nil).count,
      reunioes_qualificadas: leads.where(reuniao_resultado: 'qualificada', reuniao_registrada_em: mes_atual).count,
      meta_contratos: MetaComercial.where(account: account, papel: Ramon::Papeis::CLOSER, mes: zona.today.beginning_of_month).sum(:meta).nonzero?
    }
  end

  def funil
    contagem = leads.group(:lead_stage_id).count
    account.lead_stages.where(is_won: false, is_lost: false).order(:position)
           .map { |etapa| { etapa: etapa.name, cor: etapa.color, count: contagem[etapa.id].to_i } }
  end
end
```

(`sum(...).nonzero?` devolve `nil` quando 0 — "sem meta" no front. Se `sla_today` do Cockpit for privado/pesado, calcule a média aqui com a mesma consulta.)

`hoje.rb` — `blocos`:

```ruby
  def blocos(papel)
    case papel
    when 'gestor' then Ramon::Hoje::Gestor.new(account: account).perform
    when 'recepcao', 'advogada' then Ramon::Hoje::Escritorio.new(account: account, user: user, papel: papel).perform
    else Ramon::Hoje::Comercial.new(account: account, user: user, papel: papel).perform
    end
  end
```

(Até as Tasks 4 e 5 existirem, deixe os dois `when`/`else` devolvendo `{}` — e troque quando elas chegarem.)

- [ ] **Step 3: Commit** — `feat(hoje): blocos do gestor`

---

### Task 4: Montador comercial (SDR, Closer, equipe)

**Files:**
- Create: `app/services/ramon/hoje/comercial.rb`
- Test: `spec/services/ramon/hoje/comercial_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Hoje::Prazo`, `Ramon::ExtratoVariavel`.
- Produces: SDR/equipe → `{ responder: [Prazo.linha], follow_ups: [{ lead_id, nome, tese, titulo, vence_em, conversa_id }], reunioes: [{ quando, nome, tese, closer }], mes: { meta, contagem, total, contratos } }`. Closer → `{ reunioes_hoje: [{ quando, lead_id, nome, tese, docs: { received, total } }], assinatura: [{ lead_id, nome, tese, enviado_em, conversa_id }], mes: { meta, contagem, total, contratos, fechamento (Integer|nil) } }`. `equipe` = mesmos blocos do SDR sem filtrar por dono.

- [ ] **Step 1: Spec que falha** (`comercial_spec.rb`)

```ruby
require 'rails_helper'

RSpec.describe Ramon::Hoje::Comercial do
  let(:account) { create(:account) }
  let(:sdr) { create(:user, account: account) }
  let(:outro) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account, auto_create_lead: true) }

  def lead_sem_resposta(dono)
    create(:lead, account: account, sdr: dono, conversation: create(:conversation, account: account, inbox: inbox))
  end

  it 'SDR só vê os próprios leads em "responder"' do
    meu = lead_sem_resposta(sdr)
    lead_sem_resposta(outro)
    blocos = described_class.new(account: account, user: sdr, papel: 'sdr').perform
    expect(blocos[:responder].pluck(:lead_id)).to eq([meu.id])
  end

  it 'equipe vê todos' do
    lead_sem_resposta(sdr)
    lead_sem_resposta(outro)
    blocos = described_class.new(account: account, user: sdr, papel: 'equipe').perform
    expect(blocos[:responder].size).to eq(2)
  end

  it 'follow-up vencido hoje do meu lead aparece' do
    lead = create(:lead, account: account, sdr: sdr)
    create(:lead_task, account: account, lead: lead, kind: 'follow_up', title: 'Retomada nº 1', due_at: 1.hour.ago)
    blocos = described_class.new(account: account, user: sdr, papel: 'sdr').perform
    expect(blocos[:follow_ups].first).to include(titulo: 'Retomada nº 1', lead_id: lead.id)
  end

  it 'closer: aguardando assinatura = zapsign enviado e ainda não ganho' do
    closer = create(:user, account: account)
    lead = create(:lead, account: account, closer: closer, custom_attributes: { 'zapsign' => { 'doc_token' => 'x', 'criado_em' => 1.day.ago.iso8601 } })
    blocos = described_class.new(account: account, user: closer, papel: 'closer').perform
    expect(blocos[:assinatura].pluck(:lead_id)).to eq([lead.id])
    expect(blocos[:mes]).to include(contagem: 0, fechamento: nil)
  end
end
```

- [ ] **Step 2: Implementar** (`comercial.rb`)

```ruby
# Tela Hoje do SDR e do Closer ("equipe" = sem time: vê como SDR, sem filtrar dono).
class Ramon::Hoje::Comercial
  pattr_initialize [:account!, :user!, :papel!]

  def perform
    papel == 'closer' ? closer : sdr
  end

  private

  def zona = Time.find_zone!(Chegada::ZONA)
  def hoje = zona.now.all_day
  def mes_atual = zona.now.all_month

  def meus(coluna)
    papel == 'equipe' ? account.leads : account.leads.where(coluna => user.id)
  end

  def sdr
    {
      responder: Ramon::Hoje::Prazo.sem_resposta(meus(:sdr_id)).limit(20).map { |lead| Ramon::Hoje::Prazo.linha(lead) },
      follow_ups: follow_ups, reunioes: reunioes_marcadas, mes: mes(Ramon::Papeis::SDR)
    }
  end

  def closer
    { reunioes_hoje: reunioes_hoje, assinatura: assinatura, mes: mes(Ramon::Papeis::CLOSER).merge(fechamento: fechamento) }
  end

  def tarefas(kind)
    account.lead_tasks.where(kind: kind, completed_at: nil).joins(:lead).includes(lead: [:thesis, :conversation]).order(:due_at)
  end

  def follow_ups
    tarefas('follow_up').where(due_at: ..zona.now.end_of_day).merge(meus(:sdr_id)).limit(20).map do |task|
      { lead_id: task.lead_id, nome: task.lead.name, tese: task.lead.thesis&.name, titulo: task.title,
        vence_em: task.due_at.iso8601, conversa_id: task.lead.conversation&.display_id }
    end
  end

  def reunioes_marcadas
    tarefas('meeting').where(due_at: zona.now.beginning_of_day..).merge(meus(:sdr_id)).includes(lead: :closer).limit(10).map do |task|
      { quando: task.due_at.iso8601, nome: task.lead.name, tese: task.lead.thesis&.name, closer: task.lead.closer&.name }
    end
  end

  def reunioes_hoje
    tarefas('meeting').where(due_at: hoje).merge(meus(:closer_id)).includes(lead: { thesis: :thesis_items }).map do |task|
      { quando: task.due_at.iso8601, lead_id: task.lead_id, nome: task.lead.name, tese: task.lead.thesis&.name, docs: task.lead.docs_counts }
    end
  end

  def assinatura
    meus(:closer_id).funil.where(won_at: nil, lost_at: nil).where("custom_attributes #>> '{zapsign,doc_token}' IS NOT NULL")
                    .includes(:thesis, :conversation).map do |lead|
      { lead_id: lead.id, nome: lead.name, tese: lead.thesis&.name,
        enviado_em: lead.custom_attributes.dig('zapsign', 'criado_em'), conversa_id: lead.conversation&.display_id }
    end
  end

  def mes(papel_meta)
    linha = Ramon::ExtratoVariavel.new(account: account, mes: zona.today.beginning_of_month).pessoas
                                  .find { |pessoa| pessoa[:user][:id] == user.id && pessoa[:papel] == papel_meta }
    return { meta: nil, contagem: 0, total: 0, contratos: 0 } unless linha

    { meta: linha[:meta], contagem: linha[:contagem], total: linha[:total],
      contratos: linha[:unidades].count { |u| u[:evento] == 'contrato_limpo' } }
  end

  def fechamento
    reunioes = meus(:closer_id).funil.where(reuniao_registrada_em: mes_atual).count
    return nil if reunioes.zero?

    (meus(:closer_id).funil.where(won_at: mes_atual).count * 100 / reunioes)
  end
end
```

(`merge(meus(...))` funciona porque `tarefas` já faz `joins(:lead)`. `docs_counts` vem do concern `LeadDocs`. Se Rubocop reclamar de tamanho/complexidade, quebre em privados — não desligue a regra.)

Atualize `hoje.rb` (`else` → `Ramon::Hoje::Comercial...`).

- [ ] **Step 3: Commit** — `feat(hoje): blocos do SDR e do Closer`

---

### Task 5: Montador do escritório (Recepção e Advogada) + semana no ADVBOX

**Files:**
- Create: `app/services/ramon/advbox_usuarios.rb` (extraído de `AgendaHojeService#emails_advbox`/`usuario_do_hub`)
- Modify: `app/services/ramon/agenda_hoje_service.rb` (usar o módulo; acrescentar `hora` na linha)
- Create: `app/services/ramon/semana_advbox_service.rb`
- Create: `app/services/ramon/hoje/escritorio.rb`
- Test: `spec/services/ramon/semana_advbox_service_spec.rb`, `spec/services/ramon/hoje/escritorio_spec.rb`, `spec/services/ramon/agenda_hoje_service_spec.rb` (continua verde)

**Interfaces:**
- Produces: `Ramon::AdvboxUsuarios.usuario(account, advbox_user_id) → User|nil`; `Ramon::AgendaHojeService` linha ganha `hora: 'HH:MM'|nil`; `Ramon::SemanaAdvboxService.new(account).para(user) → [{ data: 'YYYY-MM-DD', hora: 'HH:MM'|nil, tarefa, destaque: 'pericia'|'audiencia'|nil, cliente, processo, notas }]` (levanta erro se o ADVBOX falhar — quem chama trata); `Ramon::Hoje::Escritorio.new(account:, user:, papel:).perform` → Recepção `{ sem_responsavel: [conversa], atendimentos: [..]|nil, caixa: { sem_responsavel, controladoria, com_advogadas }, advbox_fora: bool }`; Advogada `{ atribuidas: [conversa], semana: [..]|nil, advbox_fora: bool }`. `conversa = { conversa_id (display_id), nome, telefone, cliente: bool, ultima_mensagem, esperando_desde }`.

Fatos reais do ADVBOX (lidos na VPS em 03/10): tarefa = `{ id, date: "2026-10-09 00:00:00", date_deadline, task: "ACOMPANHAR PERÍCIA", notes, local, lawsuits_id, lawsuit: { process_number, customers: [...] }, users: [{ user_id, name }] }`. Hora "00:00:00" = sem hora. Perícia/audiência aparecem como tarefas de acompanhamento ("ACOMPANHAR PERÍCIA"), muitas vezes da controladoria — por isso o bloco da advogada é "Sua semana no ADVBOX" (todas as tarefas dela nos próximos 7 dias), com perícia/audiência destacadas.

- [ ] **Step 1: Specs que falham**

`semana_advbox_service_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::SemanaAdvboxService do
  let(:account) { create(:account) }
  let(:tamires) { create(:user, account: account, email: 'tamires@banca.adv.br') }

  before do
    Rails.cache.clear
    allow(Ramon::AdvboxClient).to receive(:settings).and_return('users' => [{ 'id' => 7, 'email' => 'TAMIRES@banca.adv.br' }])
    allow(Ramon::AdvboxClient).to receive(:posts).and_return('data' => [
      { 'date' => '2026-10-07 09:00:00', 'task' => 'ACOMPANHAR PERÍCIA', 'notes' => 'INSS Tubarão', 'users' => [{ 'user_id' => 7 }],
        'lawsuit' => { 'process_number' => '5003412-18.2024.4.04.7207', 'customers' => [{ 'name' => 'MARIA', 'customers_origins_id' => 1 }] } },
      { 'date' => '2026-10-08 00:00:00', 'task' => 'ELABORAR PETIÇÃO INICIAL', 'users' => [{ 'user_id' => 99 }], 'lawsuit' => {} }
    ])
  end

  it 'traz só as tarefas da pessoa, com destaque e hora' do
    linhas = described_class.new(account).para(tamires)
    expect(linhas.size).to eq(1)
    expect(linhas.first).to include(destaque: 'pericia', hora: '09:00', cliente: 'MARIA', processo: '5003412-18.2024.4.04.7207')
  end

  it 'usa cache (uma chamada só pra duas pessoas)' do
    described_class.new(account).para(tamires)
    described_class.new(account).para(tamires)
    expect(Ramon::AdvboxClient).to have_received(:posts).once
  end
end
```

`escritorio_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Hoje::Escritorio do
  let(:account) { create(:account) }
  let(:caixa) { create(:inbox, account: account, portaria_enabled: true) }
  let(:gabriela) { create(:user, account: account) }
  let(:tamires) { create(:user, account: account) }

  before do
    allow(Ramon::AgendaHojeService).to receive(:new).and_return(instance_double(Ramon::AgendaHojeService, perform: []))
    allow(Ramon::SemanaAdvboxService).to receive(:new).and_return(instance_double(Ramon::SemanaAdvboxService, para: []))
  end

  it 'recepção: sem responsável = sem agente e sem time na caixa do escritório' do
    livre = create(:conversation, account: account, inbox: caixa)
    create(:conversation, account: account, inbox: caixa, assignee: tamires)
    blocos = described_class.new(account: account, user: gabriela, papel: 'recepcao').perform
    expect(blocos[:sem_responsavel].pluck(:conversa_id)).to eq([livre.display_id])
    expect(blocos[:caixa]).to include(sem_responsavel: 1, com_advogadas: 1)
  end

  it 'advogada: só as atribuídas a ela' do
    minha = create(:conversation, account: account, inbox: caixa, assignee: tamires)
    create(:conversation, account: account, inbox: caixa)
    blocos = described_class.new(account: account, user: tamires, papel: 'advogada').perform
    expect(blocos[:atribuidas].pluck(:conversa_id)).to eq([minha.display_id])
  end

  it 'ADVBOX fora: avisa e segue' do
    allow(Ramon::SemanaAdvboxService).to receive(:new).and_raise(StandardError)
    blocos = described_class.new(account: account, user: tamires, papel: 'advogada').perform
    expect(blocos).to include(semana: nil, advbox_fora: true)
  end
end
```

- [ ] **Step 2: Implementar**

`advbox_usuarios.rb`:

```ruby
# Usuário do ADVBOX → usuário do hub, casado por e-mail (settings em cache de 24 h — cota 500/dia).
module Ramon::AdvboxUsuarios
  module_function

  def usuario(account, advbox_user_id)
    email = emails[advbox_user_id]
    email && account.users.find_by('LOWER(users.email) = ?', email.downcase)
  end

  def emails
    Rails.cache.fetch('ramon/advbox_users_email', expires_in: 24.hours) do
      Array(Ramon::AdvboxClient.settings['users']).to_h { |user| [user['id'], user['email']] }
    end
  end
end
```

`agenda_hoje_service.rb`: troque `usuario_do_hub(...)` por `Ramon::AdvboxUsuarios.usuario(@account, ...)`, apague `usuario_do_hub`/`emails_advbox`, e acrescente na `linha`: `hora: Ramon::SemanaAdvboxService.hora(tarefa['date'])`.

`semana_advbox_service.rb`:

```ruby
# "Sua semana no ADVBOX" (tela Hoje da advogada): tarefas dos próximos 7 dias da
# pessoa, com perícia/audiência em destaque. Uma chamada a cada 30 min pra todo mundo.
class Ramon::SemanaAdvboxService
  DESTAQUE = { /PER[IÍ]CIA/i => 'pericia', /AUDI[EÊ]NCIA/i => 'audiencia' }.freeze

  def self.hora(data)
    hora = data.to_s[11, 5]
    hora unless hora.blank? || hora == '00:00'
  end

  def initialize(account)
    @account = account
  end

  def para(user)
    tarefas.select { |tarefa| da_pessoa?(tarefa, user) }.map { |tarefa| linha(tarefa) }.sort_by { |l| [l[:data], l[:hora].to_s] }
  end

  private

  def tarefas
    hoje = Time.find_zone!(Chegada::ZONA).today
    Rails.cache.fetch("ramon/semana_advbox/#{hoje.iso8601}", expires_in: 30.minutes) do
      resposta = Ramon::AdvboxClient.posts(date_start: hoje.iso8601, date_end: (hoje + 7).iso8601, limit: 300)
      Array(resposta.is_a?(Hash) ? resposta['data'] : resposta)
    end
  end

  def da_pessoa?(tarefa, user)
    Array(tarefa['users']).any? { |u| Ramon::AdvboxUsuarios.usuario(@account, u['user_id'])&.id == user.id }
  end

  def linha(tarefa)
    cliente = Array(tarefa.dig('lawsuit', 'customers')).find { |c| c['customers_origins_id'] != Ramon::AgendaHojeService::PARTE_CONTRARIA }
    {
      data: tarefa['date'].to_s[0, 10], hora: self.class.hora(tarefa['date']), tarefa: tarefa['task'],
      destaque: DESTAQUE.find { |regex, _| tarefa['task'].to_s.match?(regex) }&.last,
      cliente: cliente&.dig('name'), processo: tarefa.dig('lawsuit', 'process_number'), notas: tarefa['notes']
    }
  end
end
```

(`limit: 300` — confira no `AdvboxClient`/docs se a API aceita; se o máximo for menor, pagine com `offset` até acabar, ainda dentro do mesmo `cache.fetch`.)

`hoje/escritorio.rb`:

```ruby
# Tela Hoje da Recepção (fila sem responsável + atendimentos do ADVBOX) e da
# advogada (conversas atribuídas + semana no ADVBOX). Caixa = inbox com portaria_enabled.
class Ramon::Hoje::Escritorio
  pattr_initialize [:account!, :user!, :papel!]

  def perform
    papel == 'advogada' ? advogada : recepcao
  end

  private

  def caixa
    account.conversations.open.joins(:inbox).where(inboxes: { portaria_enabled: true })
  end

  def recepcao
    atendimentos, fora = advbox { atendimentos_de_hoje }
    { sem_responsavel: linhas(caixa.where(assignee_id: nil, team_id: nil)), atendimentos: atendimentos, caixa: contagem, advbox_fora: fora }
  end

  def advogada
    semana, fora = advbox { Ramon::SemanaAdvboxService.new(account).para(user) }
    { atribuidas: linhas(caixa.where(assignee_id: user.id)), semana: semana, advbox_fora: fora }
  end

  def advbox
    [yield, false]
  rescue StandardError
    [nil, true]
  end

  def linhas(scope)
    scope.includes(:contact).reorder('conversations.created_at').limit(20).map do |conversa|
      contato = conversa.contact
      { conversa_id: conversa.display_id, nome: contato&.name, telefone: contato&.phone_number, cliente: cliente?(contato),
        ultima_mensagem: conversa.messages.incoming.last&.content.to_s.truncate(80),
        esperando_desde: (conversa.waiting_since || conversa.created_at).iso8601 }
    end
  end

  def cliente?(contato)
    digitos = contato&.phone_number.to_s.gsub(/\D/, '')
    digitos.present? && PortalCliente.exists?(telefone: [digitos, digitos.last(11)])
  end

  def contagem
    controladoria = account.teams.find_by(name: 'controladoria')&.id
    {
      sem_responsavel: caixa.where(assignee_id: nil, team_id: nil).count,
      controladoria: controladoria ? caixa.where(team_id: controladoria).count : 0,
      com_advogadas: caixa.where.not(assignee_id: nil).where.not(team_id: controladoria).or(caixa.where.not(assignee_id: nil).where(team_id: nil)).count
    }
  end

  def atendimentos_de_hoje
    chegadas = Chegada.where(account: account).de_hoje.where.not(advbox_post_id: nil).index_by(&:advbox_post_id)
    Ramon::AgendaHojeService.new(account).perform.map do |linha|
      chegada = chegadas[linha[:advbox_post_id]]
      linha.merge(situacao: situacao(chegada))
    end
  end

  def situacao(chegada)
    return 'nao_chegou' unless chegada

    chegada.respondido_em ? 'atendido' : 'aguardando'
  end
end
```

(Se `PortalCliente` tiver `account_id`, acrescente `account: account` no `exists?`. `com_advogadas` pode ser escrito mais simples com SQL `team_id IS DISTINCT FROM ?` — o importante é não contar a controladoria duas vezes.)

Atualize `hoje.rb` (`when 'recepcao', 'advogada'`).

- [ ] **Step 3: Commit** — `feat(hoje): blocos da recepção e da advogada, semana no ADVBOX`

---

### Task 6: Front — API, rota, componentes base e página

**Files:**
- Create: `app/javascript/dashboard/api/ramonHoje.js`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/hoje/SeloPrazo.vue`, `Selo.vue`, `AlertaCaixa.vue`, `HojeBloco.vue`, `HojeMetrica.vue`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/pages/Hoje.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js` (`ramon_index` → Hoje; Centro de Comando → `ramon_painel`)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/helpers/navItems.js` (+ `{ key: 'painel', icon: 'i-lucide-layout-dashboard', rota: 'ramon_painel' }` no topo do MAIS; `hoje.names` = `['ramon_index']`) e o spec dele
- Modify: i18n pt_BR/en (`RAMON.HOJE.*`, `RAMON.MENU.PAINEL` = "Painel completo")
- Test: `components/hoje/specs/SeloPrazo.spec.js`, `pages/specs/Hoje.spec.js`

**Interfaces:**
- Produces: `RamonHojeAPI.get() → { data }`; `<SeloPrazo :prazo-em="iso" />`; `<Selo tom="ok|warn|bad|neutro|act">texto</Selo>`; `<AlertaCaixa nivel="bad|warn|act" icone titulo texto :acao="{ label, to }" />`; `<HojeBloco :titulo :total :dica><template #acao/>…</HojeBloco>`; `<HojeMetrica :rotulo :valor :meta :barra="ok|act|null" />`.

- [ ] **Step 1: `SeloPrazo` — spec que falha**

```js
import { mount } from '@vue/test-utils';
import SeloPrazo from '../SeloPrazo.vue';

describe('SeloPrazo', () => {
  beforeEach(() => { vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-03T13:00:00Z')); });
  afterEach(() => vi.useRealTimers());
  const prazo = segundos => new Date(Date.now() + segundos * 1000).toISOString();

  it('cinza com mais de 2 min', () => {
    const w = mount(SeloPrazo, { props: { prazoEm: prazo(252) } });
    expect(w.text()).toContain('4:12');
    expect(w.classes()).toContain('text-n-slate-11');
  });
  it('âmbar faltando 2 min ou menos', () => {
    const w = mount(SeloPrazo, { props: { prazoEm: prazo(108) } });
    expect(w.text()).toContain('1:48');
    expect(w.classes()).toContain('text-n-amber-11');
  });
  it('vermelho com +tempo depois do prazo, e anda sozinho', async () => {
    const w = mount(SeloPrazo, { props: { prazoEm: prazo(-185) } });
    expect(w.text()).toContain('+3:05');
    expect(w.classes()).toContain('text-n-ruby-11');
    vi.advanceTimersByTime(1000);
    await w.vm.$nextTick();
    expect(w.text()).toContain('+3:06');
  });
});
```

- [ ] **Step 2: Implementar os componentes base**

`SeloPrazo.vue`:

```vue
<script setup>
import { computed } from 'vue';
import { useNow } from '@vueuse/core';

// Prazo de 1ª resposta: cinza → âmbar (≤ 2 min) → vermelho (+m:ss). Mockup v2.
const props = defineProps({ prazoEm: { type: String, required: true } });
const agora = useNow({ interval: 1000 });
const segundos = computed(() => Math.round((new Date(props.prazoEm) - agora.value) / 1000));
const mmss = s => `${Math.floor(Math.abs(s) / 60)}:${String(Math.abs(s) % 60).padStart(2, '0')}`;
const tom = computed(() => {
  if (segundos.value < 0) return 'bg-n-ruby-9/10 text-n-ruby-11';
  if (segundos.value <= 120) return 'bg-n-amber-9/15 text-n-amber-11';
  return 'bg-n-slate-3 text-n-slate-11';
});
</script>

<template>
  <span
    class="inline-flex items-center gap-1 whitespace-nowrap rounded-full px-2 py-1 font-mono text-[11.5px] font-medium leading-none"
    :class="tom"
  >
    <span class="i-lucide-clock size-3" />
    {{ segundos < 0 ? `+${mmss(segundos)}` : mmss(segundos) }}
  </span>
</template>
```

`Selo.vue`:

```vue
<script setup>
const props = defineProps({ tom: { type: String, default: 'neutro' } });
const TONS = {
  ok: 'bg-n-teal-9/15 text-n-teal-11',
  warn: 'bg-n-amber-9/15 text-n-amber-11',
  bad: 'bg-n-ruby-9/10 text-n-ruby-11',
  act: 'bg-n-blue-9/[0.08] text-n-blue-11 dark:bg-n-blue-9/[0.16]',
  neutro: 'bg-n-slate-3 text-n-slate-11',
};
</script>

<template>
  <span
    class="inline-flex items-center gap-1 whitespace-nowrap rounded-full px-2 py-1 font-mono text-[11.5px] font-medium leading-none"
    :class="TONS[props.tom]"
  >
    <slot />
  </span>
</template>
```

`AlertaCaixa.vue`:

```vue
<script setup>
defineProps({
  nivel: { type: String, required: true },
  icone: { type: String, required: true },
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
  acao: { type: Object, default: null },
});
const CAIXA = {
  bad: 'bg-n-ruby-9/10 text-n-ruby-11',
  warn: 'bg-n-amber-9/15 text-n-amber-11',
  act: 'bg-n-blue-9/[0.08] text-n-blue-11 dark:bg-n-blue-9/[0.16]',
};
</script>

<template>
  <div class="mb-2 flex items-start gap-3 rounded-[10px] px-3.5 py-3" :class="CAIXA[nivel]">
    <span :class="icone" class="mt-0.5 size-[17px] flex-shrink-0" />
    <div class="min-w-0">
      <b class="block text-[13.5px] font-semibold">{{ titulo }}</b>
      <span v-if="texto" class="text-[12.5px] text-n-slate-12">{{ texto }}</span>
    </div>
    <router-link
      v-if="acao"
      :to="acao.to"
      class="ml-auto self-center whitespace-nowrap rounded-[7px] border border-n-strong bg-n-background px-2.5 py-1.5 text-[12.5px] text-n-slate-12 hover:bg-n-slate-3"
      >{{ acao.label }}</router-link
    >
  </div>
</template>
```

`HojeBloco.vue`:

```vue
<script setup>
defineProps({
  titulo: { type: String, required: true },
  total: { type: Number, default: null },
  dica: { type: String, default: '' },
  vazio: { type: String, default: '' },
});
</script>

<template>
  <section class="mb-8">
    <div class="mb-1 flex items-baseline gap-2.5">
      <h2 class="text-[14.5px] font-semibold text-n-slate-12">{{ titulo }}</h2>
      <span v-if="total !== null" class="font-mono text-xs text-n-slate-9">{{ total }}</span>
      <div class="ml-auto"><slot name="acao" /></div>
    </div>
    <p v-if="dica" class="mb-2 text-[12.5px] text-n-slate-9">{{ dica }}</p>
    <div v-if="total === 0 && vazio" class="border-t border-n-weak py-4 text-[13px] text-n-slate-9">{{ vazio }}</div>
    <div v-else class="border-t border-n-weak"><slot /></div>
  </section>
</template>
```

`HojeMetrica.vue`:

```vue
<script setup>
import { computed } from 'vue';
const props = defineProps({
  rotulo: { type: String, required: true },
  valor: { type: [Number, String], required: true },
  meta: { type: Number, default: null },
  barra: { type: String, default: null },
});
const pct = computed(() => (props.meta ? Math.min(100, Math.round((Number(props.valor) / props.meta) * 100)) : 0));
</script>

<template>
  <div class="mb-3.5 last:mb-0">
    <div class="flex items-baseline justify-between text-[13px] text-n-slate-12">
      {{ rotulo }}
      <b class="font-mono text-sm font-medium">
        {{ valor }}<small v-if="meta" class="text-xs font-normal text-n-slate-9"> / {{ meta }}</small>
      </b>
    </div>
    <div v-if="barra && meta" class="mt-1.5 h-1.5 overflow-hidden rounded-full bg-n-slate-4">
      <i class="block h-full rounded-full" :class="barra === 'ok' ? 'bg-n-teal-9' : 'bg-n-blue-9'" :style="{ width: `${pct}%` }" />
    </div>
  </div>
</template>
```

(O `:style` da largura é dado dinâmico, não estilo de layout — ok mesmo com a regra "Tailwind only".)

`api/ramonHoje.js`:

```js
/* global axios */
import ApiClient from './ApiClient';

class RamonHojeAPI extends ApiClient {
  constructor() {
    super('ramon_hoje', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }
}

export default new RamonHojeAPI();
```

- [ ] **Step 3: Página `Hoje.vue`** (casca + escolha por papel; os componentes de papel vêm na Task 7)

```vue
<script setup>
import { computed, onMounted, ref } from 'vue';
import { useIntervalFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import RamonHojeAPI from 'dashboard/api/ramonHoje';
import HojeGestor from '../components/hoje/HojeGestor.vue';
import HojeComercial from '../components/hoje/HojeComercial.vue';
import HojeRecepcao from '../components/hoje/HojeRecepcao.vue';
import HojeAdvogada from '../components/hoje/HojeAdvogada.vue';

const { t } = useI18n();
const dados = ref(null);
const erro = ref(false);

const POR_PAPEL = { gestor: HojeGestor, recepcao: HojeRecepcao, advogada: HojeAdvogada };
const componente = computed(() => POR_PAPEL[dados.value?.papel] || HojeComercial);
const dataLonga = computed(() =>
  dados.value
    ? new Date(`${dados.value.data}T12:00:00`).toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' })
    : ''
);

const carregar = async () => {
  try {
    const { data } = await RamonHojeAPI.get();
    dados.value = data;
    erro.value = false;
  } catch {
    erro.value = true;
  }
};

onMounted(carregar);
useIntervalFn(carregar, 60 * 1000);
</script>

<template>
  <div class="flex h-full w-full flex-col overflow-y-auto bg-n-background">
    <div class="flex h-14 flex-shrink-0 items-center gap-2.5 border-b border-n-weak px-7">
      <h1 class="text-[15px] font-semibold text-n-slate-12">{{ t('RAMON.HOJE.TITULO') }}</h1>
      <span class="text-[13px] text-n-slate-9">{{ dataLonga }}</span>
    </div>
    <div v-if="erro && !dados" class="p-7 text-[13px] text-n-slate-11">
      {{ t('RAMON.HOJE.ERRO') }}
      <button class="ml-2 text-n-blue-11 underline" @click="carregar">{{ t('RAMON.HOJE.TENTAR') }}</button>
    </div>
    <component :is="componente" v-else-if="dados" :dados="dados" @recarregar="carregar" />
  </div>
</template>
```

Layout de duas colunas (conteúdo + lateral de 300 px) fica dentro de cada componente de papel:
`<div class="grid w-full max-w-[1240px] grid-cols-1 gap-10 px-7 pb-12 pt-6 xl:grid-cols-[1fr_300px]">`.

- [ ] **Step 4: Rotas** — em `ramon.routes.js`: `ramon_index` passa a usar `() => import('./pages/Hoje.vue')`; nova rota `{ path: frontendURL('accounts/:accountId/ramon/painel'), name: 'ramon_painel', component: CommandCenter, meta: { permissions: ['administrator', 'agent'], world: 'intranet' } }`. `git grep -n "ramon_index"` — links que esperavam o Centro de Comando (ex.: TV, Esteira) devem apontar pra `ramon_painel` se o contexto for o painel.
- [ ] **Step 5: i18n** `RAMON.HOJE`: `TITULO` "Hoje", `ERRO` "Não deu pra carregar a tela agora.", `TENTAR` "Tentar de novo", e as chaves usadas na Task 7 (escreva todas lá). `RAMON.MENU.PAINEL` "Painel completo".
- [ ] **Step 6: Specs** — `SeloPrazo.spec.js` passa; `pages/specs/Hoje.spec.js`: mocka `RamonHojeAPI.get` com `{ papel: 'recepcao', data: '2026-10-03', sem_responsavel: [], atendimentos: [], caixa: {}, advbox_fora: false }` e confere que monta `HojeRecepcao`; com rejeição, mostra o texto de erro e o botão de tentar. navItems spec atualizado (Hoje names e Painel no Mais).
- [ ] **Step 7: Commit** — `feat(hoje): página Hoje e componentes base (selo de prazo, alertas, métricas)`

---

### Task 7: Front — telas de cada papel

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/hoje/HojeGestor.vue`, `HojeComercial.vue`, `HojeRecepcao.vue`, `HojeAdvogada.vue`
- Modify: i18n `RAMON.HOJE.*`
- Test: `components/hoje/specs/HojeComercial.spec.js`, `HojeRecepcao.spec.js`

**Interfaces:**
- Consumes: payloads das Tasks 3–5 via prop `dados`; componentes base da Task 6; `LeadsAPI.followUpDraft(leadId)`; store `leads/encaminharComercial({ conversationId })`; `useChegadasStore().pedirPainel()`.
- Produces: emite `recarregar` depois de ações que mudam a fila.

Navegação (todas via `useAccount().accountScopedRoute`):
conversa → `accountScopedRoute('inbox_conversation', { conversation_id: conversaId })`; ficha → `accountScopedRoute('ramon_lead_dossie', { leadId })`.

Cada componente segue o HTML do mockup (`.hoje[data-for=...]`) com estas classes de linha (iguais em todos):

```html
<!-- linha de fila -->
<div class="flex items-center gap-3.5 border-b border-n-weak px-1 py-[11px] hover:bg-n-slate-3"> ... </div>
<!-- quem -->
<div class="min-w-0 flex-1">
  <b class="block text-[13.5px] font-medium text-n-slate-12">{{ nome }}</b>
  <span class="block truncate text-[12.5px] text-n-slate-11">{{ detalhe }}</span>
</div>
<!-- coluna de selo (largura fixa) -->
<span class="w-[76px] flex-shrink-0"> <SeloPrazo …/> </span>
<!-- hora -->
<span class="w-11 flex-shrink-0 font-mono text-[12.5px] text-n-slate-11">10:00</span>
<!-- botão cheio -->
<button class="whitespace-nowrap rounded-[7px] bg-n-blue-9 px-2.5 py-1.5 text-[12.5px] font-medium text-white hover:brightness-110">
<!-- botão tint -->
<button class="inline-flex items-center gap-1.5 whitespace-nowrap rounded-[7px] bg-n-blue-9/[0.08] px-2.5 py-1.5 text-[12.5px] font-medium text-n-blue-11 dark:bg-n-blue-9/[0.16]">
<!-- caixa lateral -->
<div class="mb-4 rounded-xl border border-n-weak bg-n-slate-2 p-4"><h3 class="mb-2.5 text-xs font-medium text-n-slate-9">…</h3> … </div>
```

Linha com prazo estourado ganha `shadow-[inset_3px_0_0_rgb(var(--ruby-9))]`.

- [ ] **Step 1: `HojeComercial.vue`** (SDR, equipe e Closer — decide pelo formato: `dados.reunioes_hoje` ⇒ Closer)
  - SDR/equipe: bloco "Responder agora" (dica "Lead novo tem 5 minutos para a primeira resposta.", vazio "Ninguém esperando resposta.") com `SeloPrazo :prazo-em="l.prazo_em"`, detalhe `tese · canal · “ultima_mensagem”`, botão cheio "Responder" → conversa; bloco "Follow-ups de hoje" com `Selo tom="warn"` "N dias" (vencido há ≥1 dia) ou `neutro` "hoje", detalhe `tese · titulo`, botão tint "✦ Preparar follow-up" (`i-lucide-sparkles`) que chama `LeadsAPI.followUpDraft(lead_id)` e abre a conversa; bloco "Reuniões que você marcou" com dia da semana curto + hora em mono, detalhe `tese · com {closer}`, etiqueta `ramon-stage-pill` "Reunião marcada"? → não há etapa no payload: use `Selo tom="act"` com a data; lateral "Seu mês": `HojeMetrica` "Reuniões qualificadas" (`contagem`/`meta`, barra act), "Contratos dos seus leads" (`contratos`), "Variável até agora" (`R$ ${total}`), e link "Ver meu extrato" → `ramon_extrato`.
  - Closer: "Reuniões de hoje" (hora, nome, tese, `Selo ok` "✓ dossiê pronto" quando `docs.received === docs.total`, senão `Selo warn` "faltam N docs"; botão "Abrir dossiê" → ficha); "Aguardando assinatura" (`Selo` com tempo desde `enviado_em`: neutro < 1 dia, warn ≥ 1 dia; botão tint "Lembrar cliente" → conversa); lateral "Seu mês": "Contratos fechados" (`contagem`/`meta`), "Fechamento nas reuniões" (`fechamento`% ou "—"), "Variável até agora".
- [ ] **Step 2: `HojeRecepcao.vue`** — "Sem responsável" (dica do mockup; `Selo` com minutos de espera desde `esperando_desde`: neutro < 10 min, warn ≥ 10; detalhe `Cliente`/`Número novo` + `“ultima_mensagem”`; nome = `nome` ou telefone em mono; botão cheio "Atribuir a…" → conversa; se `!cliente`, botão tint "Encaminhar ao comercial" → `store.dispatch('leads/encaminharComercial', { conversationId })` e `emit('recarregar')`); "Atendimentos de hoje" + link "do ADVBOX" (hora em mono ou "—", `cliente_nome`, "com {responsavel_advbox}", selo: `atendido` ok "✓ atendido", `aguardando` warn, `nao_chegou` neutro "ainda não chegou"); se `advbox_fora`, no lugar da lista: "ADVBOX indisponível agora — a agenda volta sozinha."; lateral "Caixa do escritório": três `dado` (Sem responsável / Com a controladoria / Com as advogadas) com número em mono.
- [ ] **Step 3: `HojeAdvogada.vue`** — "Atribuídas a você" (selo `act` "nova" se espera < 30 min, `warn` com tempo se ≥ 1 dia, senão `neutro` com tempo; botão cheio "Responder" → conversa); "Sua semana no ADVBOX" (data dd/mm + hora em mono, `tarefa` em negrito — com `Selo tom="act"` "perícia"/"audiência" quando `destaque` —, detalhe `cliente · processo` com processo em mono, `notas` truncadas); `advbox_fora` → aviso; lateral "Chegou na recepção": chegadas pra ela de hoje vindas de `useChegadasStore().itens` filtradas por `destinatario.id === currentUserId` (getter `getCurrentUserID`), com selo `aguardando` warn / `respondido` ok; vazio "Ninguém na recepção pra você."
- [ ] **Step 4: `HojeGestor.vue`** — "Precisa de você" com `AlertaCaixa` por item de `precisa`:
  - `sla` → nivel bad, ícone `i-lucide-clock`, título "{count} leads passaram dos 5 minutos sem resposta", texto nomes juntados com " e ", ação "Ver fila" → `ramon_esteira`;
  - `parado` → warn, `i-lucide-hourglass`, "Funil parado em {etapa}", "{count} leads há mais de {dias} dias sem mudar de etapa.", "Abrir no funil" → `ramon_funil`;
  - `docs` → warn, `i-lucide-file-warning`, "{count} ganhos com documentos pendentes há +7 dias", "Sem documentação completa não entra no extrato.", "Ver pós-venda" → `ramon_pos_venda`;
  - `conteudo` → act, `i-lucide-image`, "{count} peças aguardando sua aprovação", nomes entre aspas, "Revisar" → `ramon_conteudo`;
  - vazio: "Nada pendente. Bom trabalho."
  "Time hoje": grade de 3 cartões (`grid grid-cols-3 gap-3`, cartão `rounded-[10px] border border-n-weak px-3.5 py-3`) — SDR (`respondidos` respondidos / tempo médio `media_minutos` min — "—" se nulo), Closer (reuniões / contratos assinados), Recepção (chegadas). Lateral: caixa "{mês por extenso}" com `HojeMetrica` Contratos (`contratos`/`meta_contratos`, barra act), Reuniões qualificadas, Documentação completa (`docs_completos`/`ganhos_mes`, barra ok); caixa "Funil agora" com cada etapa em `<span class="ramon-stage-pill" :style="{ '--stage-color': cor }">` (use a MESMA forma que a Onda 1 usa no Kanban — `git grep -n "ramon-stage-pill"` pra copiar o binding exato) + contagem em mono.
- [ ] **Step 5: i18n** — todas as frases acima em `RAMON.HOJE.*` pt_BR (texto exatamente como no mockup) e en; plural com `t('...', { count })`.
- [ ] **Step 6: Specs**
  - `HojeComercial.spec.js`: com `responder: [{ lead_id: 1, nome: 'Rosane', tese: 'BPC/LOAS', canal: 'indicacao', conversa_id: 9, prazo_em: <futuro>, ultima_mensagem: 'oi' }]` mostra "Rosane" e um `SeloPrazo`; clicar "Preparar follow-up" chama `LeadsAPI.followUpDraft(lead_id)`; com `reunioes_hoje` presente renderiza o bloco do Closer e "dossiê pronto" quando `docs.received === docs.total`; listas vazias mostram os textos de vazio.
  - `HojeRecepcao.spec.js`: `advbox_fora: true` mostra o aviso e mantém "Sem responsável"; número novo (`cliente: false`) mostra "Encaminhar ao comercial" e despacha `leads/encaminharComercial`.
- [ ] **Step 7: Verificar** — eslint nos arquivos tocados; vitest em `routes/dashboard/ramon`; `vite build`.
- [ ] **Step 8: Commit** — `feat(hoje): telas do gestor, SDR, Closer, recepção e advogada`

---

### Task 8: Smoke + PR (sessão principal)

- [ ] Seção "I — Tela Hoje" no smoke consolidado (por papel, o que conferir; dados reais: SDR/Closer ainda não admitidos → testar com um agente posto no time `sdr`/`closer`).
- [ ] Push pelo Eduardo, PR, CI verde (é aqui que RSpec/Rubocop rodam de verdade — corrigir até ficar verde), squash, deploy sem migração, `/app/login` 200, `GET ramon_hoje` 401 sem auth.
