# Inteligência — Ondas 3 (Tools de escrita + qualificação) + 4 (Piloto por padrão + métrica) — plano de execução

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** dar ao Atendimento 5 tools de escrita seguras (qualificação, tarefa, perdido, docs, portal), carimbar toda mensagem humana que nasceu de rascunho da IA, tornar o modo do copiloto configurável por env e expor a métrica de IA em views `bi_ia_*` pro Metabase.

**Architecture:** tools novas seguem `RamonBaseTool` (escrita interna direta) ou `RamonEscritaTool` (→ `CopilotSuggestion` pendente); o carimbo é um `before_create` no `Message` (zero front pra medir); o default do modo vira `ENV` lido em `Ramon::CopilotoModo` e exposto ao front por `window.chatwootConfig`; métrica = 2 views scenic sobre `messages.content_attributes` + migração `create_view`.

**Tech Stack:** Rails 7 (fork Chatwoot), Captain tools (`enterprise/lib/captain/tools`), scenic, Vue 3 + vitest, Metabase (embed já no ar).

**Spec:** `docs/superpowers/specs/2026-08-16-inteligencia-completa-design.md` (Ondas 3 e 4; decisões D7, D8, D11, D13). Plano anterior: `docs/superpowers/plans/2026-08-16-inteligencia-ondas-1-2.md`.

## Global Constraints

- Worktree `ramon-hub-wt-inteligencia`, branch nova `feat/inteligencia-onda3` a partir de `origin/ramon` (d26166b já contém as ondas 1+2). PR único "Inteligência ondas 3+4" (D9: pares).
- Sem Ruby local: specs rodam só no CI. Specs de tools em `spec/enterprise/lib/captain/tools/` (rubocop-only no CI) **e** o que precisa RODAR vai fora de enterprise (`spec/models/`, `spec/services/ramon/`, `spec/lib/ramon/`). Specs de model que tocam `Ramon::CopilotoModo` (enterprise/lib) usam guard `if: ChatwootApp.enterprise?`.
- Toda tool: account-scoped, nunca levanta — devolve String; `lead_id` chega como string; `log_tool_usage('<id>', {...})` antes de agir.
- Nenhuma tool manda mensagem pública. "Rascunho na conversa" = a resposta do Assistente segue o modo da conversa (rascunho → nota privada `RASCUNHO (revisar antes de enviar):`).
- `tool_id.classify` singulariza a última palavra — ids terminam em singular (`registrar_qualificacao`, `criar_tarefa_cadencia`, `marcar_perdido`, `solicitar_documento`, `enviar_link_portal`).
- Envs novas documentadas em `.env.example` (bloco ramon) e fork-pontos em `docs/FORK-PONTOS-DE-REGISTRO.md`.
- Comentários em PT-BR sem acento nos `.rb` (padrão do fork). Editor: conferir que o arquivo saiu LF (autocrlf).
- Merge+deploy autorizados em pares (D9). Migração da view **à mão** na VPS (entrypoint não migra) + `\dv` no psql.

---

## Onda 3

### Task 1: `registrar_qualificacao` — escreve `qualificacao_status` do lead

**Files:**
- Create: `enterprise/lib/captain/tools/registrar_qualificacao_tool.rb`
- Create: `spec/enterprise/lib/captain/tools/registrar_qualificacao_tool_spec.rb`
- Modify: `config/agents/tools.yml` (append)

**Interfaces:**
- Consumes: `RamonBaseTool#resolver_lead(state, lead_id)`, `SEM_LEAD`; `lead.thesis.thesis_items` (`section`, `title`, `content`, `id`); `leads.custom_attributes['qualificacao_status'] = { "<thesis_item_id>" => 'ok'|'falta' }` (mesmo formato que `QualificacaoViva.vue` L33-61 lê/escreve).
- Produces: —

- [ ] **Step 1: spec**

```ruby
require 'rails_helper'

RSpec.describe Captain::Tools::RegistrarQualificacaoTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:thesis) { create(:thesis, account: account, name: 'Auxilio-acidente') }
  let(:lead) { create(:lead, account: account, thesis: thesis, name: 'Maria') }
  let!(:item) { create(:thesis_item, thesis: thesis, section: 'qualificacao', title: 'Sequela permanente') }
  let!(:outro) { create(:thesis_item, thesis: thesis, section: 'qualificacao', title: 'Trabalhava com carteira') }

  it 'marca o criterio pelo texto e devolve o placar' do
    out = tool.perform(tool_context, lead_id: lead.id.to_s, criterio: 'sequela', status: 'ok')

    expect(lead.reload.custom_attributes['qualificacao_status']).to eq(item.id.to_s => 'ok')
    expect(out).to include('Sequela permanente').and include('1 ok').and include('1 sem resposta')
  end

  it 'preserva o que ja estava marcado' do
    lead.update!(custom_attributes: { 'qualificacao_status' => { outro.id.to_s => 'falta' }, 'x' => 1 })
    tool.perform(tool_context, lead_id: lead.id.to_s, criterio: 'Sequela permanente', status: 'ok')

    expect(lead.reload.custom_attributes).to include('x' => 1,
                                                     'qualificacao_status' => { outro.id.to_s => 'falta', item.id.to_s => 'ok' })
  end

  it 'lista os criterios quando nao acha' do
    out = tool.perform(tool_context, lead_id: lead.id.to_s, criterio: 'xablau', status: 'ok')
    expect(out).to include('Sequela permanente').and include('Trabalhava com carteira')
    expect(lead.reload.custom_attributes['qualificacao_status']).to be_blank
  end

  it 'recusa status invalido e caso sem tese' do
    expect(tool.perform(tool_context, lead_id: lead.id.to_s, criterio: 'sequela', status: 'talvez')).to include('ok, falta ou limpar')
    sem_tese = create(:lead, account: account, thesis: nil)
    expect(tool.perform(tool_context, lead_id: sem_tese.id.to_s, criterio: 'sequela', status: 'ok')).to include('sem tese')
    expect(tool.perform(tool_context, lead_id: '999999', criterio: 'a', status: 'ok')).to eq(described_class::SEM_LEAD)
  end
end
```

- [ ] **Step 2: implementação**

```ruby
# Escrita INTERNA (nao sai pro mundo, D11): grava a qualificacao viva do caso —
# o mesmo custom_attributes.qualificacao_status que o painel QualificacaoViva
# le e escreve (chave = id do thesis_item, valor ok|falta).
class Captain::Tools::RegistrarQualificacaoTool < Captain::Tools::RamonBaseTool
  STATUS = %w[ok falta limpar].freeze

  description 'Registra no caso se um criterio de qualificacao da tese foi confirmado (ok) ou nao atendido (falta). ' \
              'So marca o painel do caso; nao manda nada ao cliente.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false
  param :criterio, type: 'string', desc: 'Nome (ou parte) do criterio de qualificacao da tese', required: true
  param :status, type: 'string', desc: 'ok, falta ou limpar', required: true

  def perform(tool_context, criterio: nil, status: nil, lead_id: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?
    return 'Status invalido: use ok, falta ou limpar.' unless STATUS.include?(status.to_s.strip.downcase)
    return "O caso #{lead.name} esta sem tese definida — nao ha criterios para marcar." if lead.thesis.blank?

    itens = lead.thesis.thesis_items.where(section: 'qualificacao').order(:position)
    item = achar(itens, criterio)
    return "Nao achei esse criterio. Os criterios da tese sao: #{itens.map { |i| rotulo(i) }.join(' | ')}." if item.blank?

    log_tool_usage('registrar_qualificacao', { lead_id: lead.id, item_id: item.id, status: status })
    gravar(lead, item, status.to_s.strip.downcase)
    "#{rotulo(item)} marcado como #{status}. Placar: #{placar(lead, itens)}."
  end

  private

  def rotulo(item) = item.title.presence || item.content.to_s.truncate(60)

  def normal(texto) = I18n.transliterate(texto.to_s).downcase.strip

  def achar(itens, criterio)
    alvo = normal(criterio)
    return nil if alvo.blank?

    itens.find { |i| normal(rotulo(i)) == alvo } || itens.find { |i| normal(rotulo(i)).include?(alvo) }
  end

  def gravar(lead, item, status)
    atual = (lead.custom_attributes || {}).dup
    mapa = (atual['qualificacao_status'] || {}).dup
    status == 'limpar' ? mapa.delete(item.id.to_s) : mapa[item.id.to_s] = status
    lead.update!(custom_attributes: atual.merge('qualificacao_status' => mapa))
  end

  def placar(lead, itens)
    mapa = lead.reload.custom_attributes['qualificacao_status'] || {}
    ok = itens.count { |i| mapa[i.id.to_s] == 'ok' }
    falta = itens.count { |i| mapa[i.id.to_s] == 'falta' }
    "#{ok} ok, #{falta} falta, #{itens.size - ok - falta} sem resposta"
  end
end
```

- [ ] **Step 3: `config/agents/tools.yml`** — append ao bloco ramon:

```yaml
- id: registrar_qualificacao
  title: 'Registrar qualificação'
  description: 'Marca no caso se um critério de qualificação da tese foi confirmado ou não atendido'
  icon: 'checkmark-circle'
```

- [ ] **Step 4: commit** `feat(inteligencia): tool registrar_qualificacao`

### Task 2: `criar_tarefa_cadencia` — tarefa interna na Esteira

**Files:**
- Create: `enterprise/lib/captain/tools/criar_tarefa_cadencia_tool.rb`
- Create: `spec/enterprise/lib/captain/tools/criar_tarefa_cadencia_tool_spec.rb`
- Modify: `config/agents/tools.yml`

**Interfaces:**
- Consumes: `LeadTask::KINDS = %w[follow_up document meeting other]`, `lead.lead_tasks.open_tasks`, `LeadTask` cria `lead_activities task_created` + broadcast sozinho (callbacks).
- Decisão de desenho: **escrita direta**, não Sugestão — tarefa é interna e reversível (o Cockpit já cria `lead_tasks` direto no "Subir na esteira"). Anotar no PR.

- [ ] **Step 1: spec**

```ruby
require 'rails_helper'

RSpec.describe Captain::Tools::CriarTarefaCadenciaTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:lead) { create(:lead, account: account, name: 'Joao') }

  it 'cria a tarefa follow_up com data e hora' do
    out = tool.perform(tool_context, lead_id: lead.id.to_s, titulo: 'Cobrar CNIS', quando: '2030-01-10 09:00')
    task = lead.lead_tasks.last

    expect(task).to have_attributes(kind: 'follow_up', title: 'Cobrar CNIS', user_id: nil)
    expect(task.due_at.in_time_zone('America/Sao_Paulo').strftime('%Y-%m-%d %H:%M')).to eq('2030-01-10 09:00')
    expect(out).to include('Cobrar CNIS').and include('10/01/2030')
  end

  it 'aceita so a data (assume 09:00) e o tipo document' do
    tool.perform(tool_context, lead_id: lead.id.to_s, titulo: 'Receber laudo', quando: '2030-01-10', tipo: 'document')
    expect(lead.lead_tasks.last).to have_attributes(kind: 'document')
    expect(lead.lead_tasks.last.due_at.in_time_zone('America/Sao_Paulo').hour).to eq(9)
  end

  it 'nao duplica tarefa aberta com o mesmo titulo' do
    2.times { tool.perform(tool_context, lead_id: lead.id.to_s, titulo: 'Cobrar CNIS', quando: '2030-01-10') }
    expect(lead.lead_tasks.count).to eq(1)
  end

  it 'recusa data passada, tipo invalido e caso inexistente' do
    expect(tool.perform(tool_context, lead_id: lead.id.to_s, titulo: 'x', quando: '2000-01-01')).to include('ja passou')
    expect(tool.perform(tool_context, lead_id: lead.id.to_s, titulo: 'x', quando: '2030-01-01', tipo: 'festa')).to include('follow_up')
    expect(tool.perform(tool_context, lead_id: '999999', titulo: 'x', quando: '2030-01-01')).to eq(described_class::SEM_LEAD)
    expect(lead.lead_tasks.count).to eq(0)
  end
end
```

- [ ] **Step 2: implementação**

```ruby
# Escrita INTERNA: cria a tarefa de cadencia do caso na Esteira (lead_tasks).
# Nada chega ao cliente — a tarefa e o lembrete do humano. Por isso nao passa
# por Sugestao pendente (mesma regra do "Subir na esteira" do Cockpit).
class Captain::Tools::CriarTarefaCadenciaTool < Captain::Tools::RamonBaseTool
  TZ = 'America/Sao_Paulo'.freeze

  description 'Cria uma tarefa de cadencia do caso na Esteira (lembrete interno para a equipe: cobrar documento, ' \
              'retomar contato, ligar). Nao envia nada ao cliente.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false
  param :titulo, type: 'string', desc: 'O que fazer, em uma linha', required: true
  param :quando, type: 'string', desc: 'AAAA-MM-DD ou AAAA-MM-DD HH:MM (sem hora, assume 09:00)', required: true
  param :tipo, type: 'string', desc: 'follow_up (padrao), document, meeting ou other', required: false

  def perform(tool_context, titulo: nil, quando: nil, lead_id: nil, tipo: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    kind = tipo.presence || 'follow_up'
    return "Tipo invalido. Use: #{LeadTask::KINDS.join(', ')}." unless LeadTask::KINDS.include?(kind)

    due = horario_de(quando)
    return 'Nao entendi a data. Use AAAA-MM-DD ou AAAA-MM-DD HH:MM.' if due.blank?
    return 'A data ja passou. Use uma data futura.' if due < Time.current

    nome = titulo.to_s.strip
    return 'Informe o titulo da tarefa.' if nome.blank?
    return "Ja existe a tarefa aberta \"#{nome}\" no caso #{lead.name}." if lead.lead_tasks.open_tasks.any? { |t| t.title.casecmp?(nome) }

    log_tool_usage('criar_tarefa_cadencia', { lead_id: lead.id, kind: kind, due_at: due.iso8601 })
    lead.lead_tasks.create!(account: lead.account, kind: kind, title: nome, due_at: due)
    "Tarefa \"#{nome}\" criada na Esteira do caso #{lead.name} para #{due.in_time_zone(TZ).strftime('%d/%m/%Y %H:%M')}."
  end

  private

  def horario_de(quando)
    texto = quando.to_s.strip
    texto = "#{texto} 09:00" if texto.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    ActiveSupport::TimeZone[TZ].parse(texto)
  rescue ArgumentError
    nil
  end
end
```

- [ ] **Step 3: tools.yml**

```yaml
- id: criar_tarefa_cadencia
  title: 'Criar tarefa de cadência'
  description: 'Cria um lembrete interno na Esteira do caso (cobrar, retomar, ligar) com data e hora'
  icon: 'calendar-clock'
```

- [ ] **Step 4: commit** `feat(inteligencia): tool criar_tarefa_cadencia`

### Task 3: `marcar_perdido` — Sugestão pendente `acao: 'perdido'` + aplicação

**Files:**
- Modify: `app/models/copilot_suggestion.rb` (L9 `ACOES`, L55-61 `executar_acao`, novo privado `marcar_perdido`)
- Modify: `spec/models/copilot_suggestion_spec.rb` (novo describe)
- Create: `enterprise/lib/captain/tools/marcar_perdido_tool.rb`
- Create: `spec/enterprise/lib/captain/tools/marcar_perdido_tool_spec.rb`
- Modify: `config/agents/tools.yml`

**Interfaces:**
- Consumes: `RamonEscritaTool#sugerir(lead, acao:, texto:, **extras)`; `account.lost_reasons` (`name`); `account.lead_stages.where(is_lost: true)`; `Lead#apply_stage_timestamps` (seta `lost_at` e mantém `lost_reason` quando a etapa é lost).
- Produces: payload `{ 'acao' => 'perdido', 'lost_reason' => '<nome do catalogo>' }`; o Cockpit já desenha `kind: 'acao'` (tag "Ação da IA" + `payload.texto` + botão Aplicar) — sem mudança de front.

- [ ] **Step 1: spec do model** — adicionar em `spec/models/copilot_suggestion_spec.rb`:

```ruby
  describe '#apply! com acao perdido' do
    let!(:aberta) { create(:lead_stage, account: account, name: 'Contato', is_lost: false, position: 1) }
    let!(:perdida) { create(:lead_stage, account: account, name: 'Perdido', is_lost: true, position: 9) }

    it 'move o caso para a etapa perdida com o motivo' do
      lead.update!(lead_stage: aberta)
      suggestion = sugestao('perdido', 'lost_reason' => 'Sem direito')

      expect(suggestion.apply!).to be(true)
      expect(lead.reload).to have_attributes(lead_stage_id: perdida.id, lost_reason: 'Sem direito')
      expect(lead.lost_at).to be_present
    end

    it 'recusa quando o caso ja esta ganho' do
      lead.update!(lead_stage: create(:lead_stage, account: account, name: 'Ganho', is_won: true, position: 8))
      suggestion = sugestao('perdido', 'lost_reason' => 'Sem direito')

      expect(suggestion.apply!).to be(false)
      expect(suggestion.motivo_da_recusa).to include('ganho')
    end

    it 'recusa sem etapa perdida configurada' do
      perdida.destroy!
      expect(sugestao('perdido', 'lost_reason' => 'x').apply!).to be(false)
    end
  end
```

(`attr_reader :motivo_da_recusa` já existe no model, L20.)

- [ ] **Step 2: model** — `ACOES = %w[zapsign advbox reuniao perdido]`; em `executar_acao` acrescentar `when 'perdido' then marcar_perdido`; privado:

```ruby
  # Perdido e reversivel no Kanban (arrastar de volta), mas so o humano decide.
  def marcar_perdido
    return recusar('O caso ja esta ganho — nao da para marcar perdido') if lead.won_at.present?
    return recusar('O caso ja esta marcado como perdido') if lead.lost_at.present?

    etapa = account.lead_stages.where(is_lost: true).order(:position).first
    return recusar('Nao ha etapa de perdido configurada no funil') if etapa.blank?

    lead.update!(lead_stage: etapa, lost_reason: payload['lost_reason'].presence || 'Sugerido pelo agente')
  end
```

- [ ] **Step 3: spec da tool**

```ruby
require 'rails_helper'

RSpec.describe Captain::Tools::MarcarPerdidoTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:lead) { create(:lead, account: account, name: 'Ana') }

  before { account.lost_reasons.create!(name: 'Sem direito', position: 1); account.lost_reasons.create!(name: 'Sem retorno', position: 2) }

  it 'cria a sugestao pendente com o motivo do catalogo, sem mover o caso' do
    out = tool.perform(tool_context, lead_id: lead.id.to_s, motivo: 'sem retorno')
    s = account.copilot_suggestions.pending.last

    expect(s.payload).to include('acao' => 'perdido', 'lost_reason' => 'Sem retorno')
    expect(lead.reload.lost_at).to be_nil
    expect(out).to include('pendente')
  end

  it 'lista os motivos quando nao casa e nao duplica pendente' do
    expect(tool.perform(tool_context, lead_id: lead.id.to_s, motivo: 'mudou de ideia')).to include('Sem direito').and include('Sem retorno')
    2.times { tool.perform(tool_context, lead_id: lead.id.to_s, motivo: 'Sem direito') }
    expect(account.copilot_suggestions.pending.count).to eq(1)
  end

  it 'recusa caso ganho' do
    lead.update!(won_at: Time.current)
    expect(tool.perform(tool_context, lead_id: lead.id.to_s, motivo: 'Sem direito')).to include('ganho')
    expect(account.copilot_suggestions.count).to eq(0)
  end
end
```

- [ ] **Step 4: tool**

```ruby
# Escrita com aprovacao: propoe marcar o caso como perdido. Perdido tira o caso
# do funil ativo — so o humano aplica, no Cockpit (CopilotSuggestion 'perdido').
class Captain::Tools::MarcarPerdidoTool < Captain::Tools::RamonEscritaTool
  description 'Propoe marcar o caso como perdido com um motivo do catalogo. NAO marca: cria uma sugestao pendente ' \
              'que o humano aprova no Cockpit.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false
  param :motivo, type: 'string', desc: 'Motivo da perda (nome do catalogo do funil, ou parte dele)', required: true

  def perform(tool_context, motivo: nil, lead_id: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?
    return "O caso #{lead.name} ja esta ganho — nao da para marcar perdido." if lead.won_at.present?
    return "O caso #{lead.name} ja esta marcado como perdido." if lead.lost_at.present?

    motivos = lead.account.lost_reasons.map(&:name)
    escolhido = casar(motivos, motivo)
    return "Motivo nao encontrado. Os motivos do funil sao: #{motivos.join(', ')}." if escolhido.blank?

    log_tool_usage('marcar_perdido', { lead_id: lead.id, motivo: escolhido })
    sugerir(lead, acao: 'perdido', texto: "Marcar #{lead.name} como perdido — motivo: #{escolhido}", lost_reason: escolhido)
  end

  private

  def casar(motivos, texto)
    alvo = I18n.transliterate(texto.to_s).downcase.strip
    return nil if alvo.blank?

    motivos.find { |m| I18n.transliterate(m).downcase == alvo } ||
      motivos.find { |m| I18n.transliterate(m).downcase.include?(alvo) }
  end
end
```

- [ ] **Step 5: tools.yml**

```yaml
- id: marcar_perdido
  title: 'Marcar como perdido'
  description: 'Sugere marcar o caso como perdido com o motivo — o humano aprova no Cockpit'
  icon: 'dismiss-circle'
```

- [ ] **Step 6: commit** `feat(inteligencia): tool marcar_perdido + acao perdido no CopilotSuggestion`

### Task 4: `solicitar_documento` + `enviar_link_portal` — texto pronto pro rascunho

**Files:**
- Create: `enterprise/lib/captain/tools/solicitar_documento_tool.rb`, `enterprise/lib/captain/tools/enviar_link_portal_tool.rb`
- Create: specs correspondentes em `spec/enterprise/lib/captain/tools/`
- Modify: `config/agents/tools.yml`

**Interfaces:**
- Consumes: `Ramon::DossieService.new(lead:).perform[:pendencias][:docs_missing]` → `[{ title:, status: }]`; `Lead#ensure_portal_token!` + `ENV['FRONTEND_URL']` (mesmo formato de `leads_controller#portal_link`: `"#{FRONTEND_URL}/portal/#{token}"`).
- Desenho: as duas tools **só devolvem o texto** pro Assistente incluir na resposta; a resposta segue o modo da conversa (rascunho = nota privada; piloto_limitado = envia, pois "lista de documentos" e "cobrança de pendentes" estão na lista D13). Não marcam `doc_status` (`# ponytail: nao sabemos se o rascunho foi enviado; marcar 'solicitado' fica pro DocChecklist do humano`).

- [ ] **Step 1: spec `solicitar_documento`**

```ruby
require 'rails_helper'

RSpec.describe Captain::Tools::SolicitarDocumentoTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:thesis) { create(:thesis, account: account) }
  let(:lead) { create(:lead, account: account, thesis: thesis, name: 'Maria das Dores') }

  before do
    create(:thesis_item, thesis: thesis, section: 'documento', title: 'CNIS')
    create(:thesis_item, thesis: thesis, section: 'documento', title: 'Laudo medico')
    create(:thesis_item, thesis: thesis, section: 'documento', title: 'RG').tap do |rg|
      lead.update!(custom_attributes: { 'doc_status' => { rg.id.to_s => 'recebido' } })
    end
  end

  it 'monta o pedido com os documentos pendentes da tese' do
    out = tool.perform(tool_context, lead_id: lead.id.to_s)
    expect(out).to include('Maria').and include('• CNIS').and include('• Laudo medico')
    expect(out).not_to include('RG')
  end

  it 'usa a lista informada quando vier' do
    out = tool.perform(tool_context, lead_id: lead.id.to_s, documentos: 'carteira de trabalho, comprovante de residencia')
    expect(out).to include('• carteira de trabalho').and include('• comprovante de residencia')
    expect(out).not_to include('CNIS')
  end

  it 'avisa quando nao ha pendencia' do
    lead.update!(custom_attributes: { 'doc_status' => thesis.thesis_items.to_h { |i| [i.id.to_s, 'recebido'] } })
    expect(tool.perform(tool_context, lead_id: lead.id.to_s)).to include('nenhum documento pendente')
  end
end
```

- [ ] **Step 2: tool**

```ruby
# Escrita "por rascunho": devolve o texto pronto do pedido de documentos para o
# Assistente colocar na resposta. Quem decide se sai (piloto) ou vira nota
# (rascunho) e o modo da conversa — a tool nao manda nada.
class Captain::Tools::SolicitarDocumentoTool < Captain::Tools::RamonBaseTool
  description 'Monta o texto pronto para pedir ao cliente os documentos que faltam no caso (ou uma lista informada). ' \
              'Devolve o texto para voce usar na resposta; nao envia sozinho.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false
  param :documentos, type: 'string', desc: 'Lista separada por virgula. Sem ela, usa os documentos pendentes da tese.', required: false

  def perform(tool_context, lead_id: nil, documentos: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    itens = lista(lead, documentos)
    return "O caso #{lead.name} nao tem nenhum documento pendente." if itens.empty?

    log_tool_usage('solicitar_documento', { lead_id: lead.id, quantidade: itens.size })
    # ponytail: nao marca doc_status 'solicitado' — nao sabemos se o rascunho vai sair; o DocChecklist do humano marca.
    ["Ola #{primeiro_nome(lead)}, tudo bem? Para dar andamento ao seu caso, ainda preciso destes documentos:",
     *itens.map { |d| "• #{d}" },
     'Pode mandar foto ou PDF por aqui mesmo. Assim que chegar, seguimos com o seu pedido. Obrigado!'].join("\n")
  end

  private

  def lista(lead, documentos)
    informados = documentos.to_s.split(',').map(&:strip).reject(&:blank?)
    return informados if informados.any?

    Ramon::DossieService.new(lead: lead).perform.dig(:pendencias, :docs_missing).to_a.map { |d| d[:title] }
  rescue StandardError => e
    Rails.logger.warn("[solicitar_documento] dossie falhou: #{e.message}")
    []
  end

  def primeiro_nome(lead) = lead.name.to_s.split.first.presence || 'tudo bem'
end
```

- [ ] **Step 3: spec `enviar_link_portal`**

```ruby
require 'rails_helper'

RSpec.describe Captain::Tools::EnviarLinkPortalTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:lead) { create(:lead, account: account, name: 'Jose') }

  it 'gera o token na primeira vez e devolve o link' do
    with_modified_env FRONTEND_URL: 'https://chat.exemplo.br' do
      out = tool.perform(tool_context, lead_id: lead.id.to_s)
      expect(lead.reload.portal_token).to be_present
      expect(out).to include("https://chat.exemplo.br/portal/#{lead.portal_token}")
    end
  end

  it 'reusa o token existente' do
    lead.update!(portal_token: 'abc123')
    expect(tool.perform(tool_context, lead_id: lead.id.to_s)).to include('/portal/abc123')
  end

  it 'sem FRONTEND_URL avisa que o link nao esta disponivel' do
    with_modified_env FRONTEND_URL: '' do
      expect(tool.perform(tool_context, lead_id: lead.id.to_s)).to include('nao esta configurado')
    end
  end
end
```

(`with_modified_env` existe em `spec/spec_helper.rb` L16.)

- [ ] **Step 4: tool**

```ruby
# Escrita "por rascunho": devolve o link magico do portal do cliente (upload de
# documentos) com uma frase pronta. O token nasce aqui se ainda nao existir —
# mesmo comportamento do botao "Link do portal" da ficha do lead.
class Captain::Tools::EnviarLinkPortalTool < Captain::Tools::RamonBaseTool
  SEM_URL = 'O link do portal nao esta configurado neste ambiente (FRONTEND_URL). Peca ao humano para enviar os documentos por aqui.'.freeze

  description 'Devolve o link do portal do cliente para ele enviar documentos pelo celular, com uma frase pronta. ' \
              'Nao envia sozinho: use o texto na resposta.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false

  def perform(tool_context, lead_id: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    base = ENV.fetch('FRONTEND_URL', '').strip
    return SEM_URL if base.blank?

    token = lead.ensure_portal_token!
    log_tool_usage('enviar_link_portal', { lead_id: lead.id })
    "Link do portal do cliente: #{base}/portal/#{token}\n" \
      "Frase sugerida: \"Para facilitar, voce pode enviar os documentos por este link seguro, direto do celular: #{base}/portal/#{token}\""
  end
end
```

- [ ] **Step 5: tools.yml**

```yaml
- id: solicitar_documento
  title: 'Pedir documentos'
  description: 'Texto pronto pedindo ao cliente os documentos pendentes do caso'
  icon: 'document-add'
- id: enviar_link_portal
  title: 'Link do portal do cliente'
  description: 'Link seguro para o cliente enviar documentos pelo celular, com frase pronta'
  icon: 'link'
```

- [ ] **Step 6: commit** `feat(inteligencia): tools solicitar_documento e enviar_link_portal`

### Task 5: Carimbo "veio de rascunho da IA" na mensagem humana

**Files:**
- Create: `app/services/ramon/rascunho_carimbo.rb`
- Modify: `app/models/message.rb` (após L137: `before_create :ramon_carimbar_rascunho, if: :ramon_candidata_a_carimbo?` — fork-ponto)
- Create: `spec/services/ramon/rascunho_carimbo_spec.rb`
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md` (1 linha)

**Interfaces:**
- Consumes: nota-rascunho = `messages` com `private: true`, `sender_type: 'Captain::Assistant'`, `content LIKE 'RASCUNHO (revisar antes de enviar):%'` (criada em `response_builder_job.rb#create_draft_note`).
- Produces: `message.content_attributes['ramon_rascunho_ia'] = { 'nota_id' => Integer, 'desfecho' => 'igual'|'editado'|'descartado', 'similaridade' => Float }` na mensagem **pública de saída** enviada por `User`. Task 6 mostra o chip; Task 8 (view) lê.
- Regra: candidata = `outgoing? && !private? && sender_type == 'User'`; nota elegível = última nota-rascunho da conversa criada **depois** da última mensagem `incoming` (ou desde sempre se não há incoming). `desfecho`: textos normalizados iguais → `igual`; Jaccard de palavras ≥ 0.3 → `editado`; senão `descartado` (o humano escreveu do zero, mas o rascunho existiu — conta como descartado). `# ponytail: Jaccard de palavras; se confundir editado x descartado, trocar por distancia de Levenshtein`.

- [ ] **Step 1: spec (roda no CI — fora de enterprise, sem dependência de enterprise/lib)**

```ruby
require 'rails_helper'

RSpec.describe Ramon::RascunhoCarimbo do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) { create(:user, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:prefixo) { 'RASCUNHO (revisar antes de enviar):' }

  def rascunho(texto)
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing,
                     private: true, sender: assistant, content: "#{prefixo}\n#{texto}")
  end

  def humano(texto)
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing,
                     private: false, sender: agent, content: texto)
  end

  it 'carimba igual quando o humano manda o rascunho como estava' do
    nota = rascunho('Ola Maria, tudo bem? Preciso do seu CNIS.')
    msg = humano("Ola Maria, tudo bem?  Preciso do seu CNIS. ")

    expect(msg.content_attributes['ramon_rascunho_ia']).to include('nota_id' => nota.id, 'desfecho' => 'igual')
  end

  it 'carimba editado quando muda parte e descartado quando escreve do zero' do
    rascunho('Ola Maria, tudo bem? Preciso do seu CNIS e do laudo medico para seguir.')
    expect(humano('Ola Maria, tudo bem? Preciso do seu CNIS e do laudo para seguir com o pedido.')
      .content_attributes.dig('ramon_rascunho_ia', 'desfecho')).to eq('editado')

    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'oi')
    rascunho('Bom dia! Podemos marcar para quinta?')
    expect(humano('Segue o contrato em anexo, qualquer duvida me chama.')
      .content_attributes.dig('ramon_rascunho_ia', 'desfecho')).to eq('descartado')
  end

  it 'nao carimba sem rascunho depois da ultima mensagem do cliente, nem nota privada, nem mensagem do bot' do
    rascunho('x')
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'oi')
    expect(humano('resposta').content_attributes['ramon_rascunho_ia']).to be_nil

    rascunho('y')
    nota = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing,
                            private: true, sender: agent, content: 'nota interna')
    expect(nota.content_attributes['ramon_rascunho_ia']).to be_nil
    bot = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing,
                           sender: assistant, content: 'y')
    expect(bot.content_attributes['ramon_rascunho_ia']).to be_nil
  end
end
```

- [ ] **Step 2: serviço**

```ruby
# Carimbo "veio de rascunho da IA" (spec Inteligencia, Onda 3): quando o humano
# manda uma mensagem publica e existe uma nota-rascunho do Assistente depois da
# ultima fala do cliente, a mensagem ganha content_attributes.ramon_rascunho_ia
# com o desfecho — base da metrica bi_ia (D8) e da decisao D7 (piloto por padrao).
module Ramon::RascunhoCarimbo
  PREFIXO = 'RASCUNHO (revisar antes de enviar):'.freeze
  CHAVE = 'ramon_rascunho_ia'.freeze

  module_function

  def candidata?(message)
    message.outgoing? && !message.private? && message.sender_type == 'User' && message.content.present?
  end

  # Muta content_attributes da mensagem AINDA NAO salva (before_create) — sem update extra.
  def aplicar(message)
    nota = nota_elegivel(message.conversation)
    return if nota.blank?

    sim = similaridade(nota.content.delete_prefix(PREFIXO), message.content)
    desfecho = if normal(nota.content.delete_prefix(PREFIXO)) == normal(message.content) then 'igual'
               elsif sim >= 0.3 then 'editado'
               else 'descartado'
               end
    message.content_attributes = (message.content_attributes || {}).merge(
      CHAVE => { 'nota_id' => nota.id, 'desfecho' => desfecho, 'similaridade' => sim.round(2) }
    )
  end

  def nota_elegivel(conversation)
    ultima_do_cliente = conversation.messages.incoming.maximum(:created_at)
    notas = conversation.messages.where(private: true, sender_type: 'Captain::Assistant')
                        .where('content LIKE ?', "#{PREFIXO}%")
    notas = notas.where('created_at > ?', ultima_do_cliente) if ultima_do_cliente
    notas.order(created_at: :desc).first
  end

  def normal(texto) = texto.to_s.downcase.gsub(/\s+/, ' ').strip

  # ponytail: Jaccard de palavras (>=3 letras); se confundir editado x descartado, trocar por Levenshtein.
  def similaridade(a, b)
    pa = palavras(a)
    pb = palavras(b)
    return 0.0 if pa.empty? || pb.empty?

    (pa & pb).size.to_f / (pa | pb).size
  end

  def palavras(texto) = I18n.transliterate(normal(texto)).scan(/[a-z0-9]{3,}/).uniq
end
```

- [ ] **Step 3: fork-ponto no `Message`** — logo após `after_create_commit :execute_after_create_commit_callbacks` (L137):

```ruby
  # FORK-PONTO (ramon): carimbo "veio de rascunho da IA" — Ramon::RascunhoCarimbo.
  before_create :ramon_carimbar_rascunho, if: -> { Ramon::RascunhoCarimbo.candidata?(self) }
```
e privado (fim da seção private):
```ruby
  def ramon_carimbar_rascunho
    Ramon::RascunhoCarimbo.aplicar(self)
  rescue StandardError => e
    Rails.logger.warn("[ramon_rascunho_ia] #{e.class}: #{e.message}")
  end
```
Conferir se `Message` já tem `enum message_type` com scope `incoming` (sim — `conversation.messages.incoming` é usado no Chatwoot).

- [ ] **Step 4: `docs/FORK-PONTOS-DE-REGISTRO.md`** — 1 linha: `app/models/message.rb before_create ramon_carimbar_rascunho → Ramon::RascunhoCarimbo`.
- [ ] **Step 5: commit** `feat(inteligencia): carimbo ramon_rascunho_ia na mensagem enviada a partir de rascunho`

### Task 6: Chip "de rascunho da IA" na bolha (front)

**Files:**
- Create: `app/javascript/dashboard/components-next/message/RascunhoCarimbo.vue`
- Create: `app/javascript/dashboard/components-next/message/specs/RascunhoCarimbo.spec.js`
- Modify: `app/javascript/dashboard/components-next/message/Message.vue` (L47 import; L573 condição; L582 render)
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` (bloco `RAMON.COPILOTO`)

**Interfaces:**
- Consumes: `contentAttributes.ramonRascunhoIa = { notaId, desfecho, similaridade }` (camelizado pelo provider, como `ramonPiloto`).

- [ ] **Step 1: spec (vitest, mesmo mock de i18n do `PilotoCarimbo.spec.js`)**

```js
import { mount } from '@vue/test-utils';
import RascunhoCarimbo from '../RascunhoCarimbo.vue';

const translations = {
  'RAMON.COPILOTO.RASCUNHO_IA.igual': () => 'rascunho da IA enviado como estava',
  'RAMON.COPILOTO.RASCUNHO_IA.editado': () => 'rascunho da IA, editado',
  'RAMON.COPILOTO.RASCUNHO_IA.descartado': () => 'rascunho da IA descartado',
};
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => (translations[k] ? translations[k]() : k) }) }));

const contentAttributes = { value: { ramonRascunhoIa: { notaId: 1, desfecho: 'editado' } } };
vi.mock('../provider.js', () => ({ useMessageContext: () => ({ contentAttributes }) }));

describe('RascunhoCarimbo', () => {
  it('mostra o desfecho', () => {
    const w = mount(RascunhoCarimbo);
    expect(w.text()).toContain('rascunho da IA, editado');
  });
  it('cai no texto de descartado', () => {
    contentAttributes.value = { ramonRascunhoIa: { notaId: 2, desfecho: 'descartado' } };
    expect(mount(RascunhoCarimbo).text()).toContain('descartado');
  });
});
```

- [ ] **Step 2: componente**

```vue
<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from './provider.js';

defineOptions({ name: 'RascunhoCarimbo' });
const { t } = useI18n();
const { contentAttributes } = useMessageContext();
const desfecho = computed(
  () => contentAttributes.value?.ramonRascunhoIa?.desfecho || 'editado'
);
</script>

<template>
  <span class="text-xs text-n-slate-10 italic">
    ✦ {{ t(`RAMON.COPILOTO.RASCUNHO_IA.${desfecho}`) }}
  </span>
</template>
```

- [ ] **Step 3: `Message.vue`** — import ao lado de `PilotoCarimbo`; L573 `v-if="contentAttributes.externalError || contentAttributes.ramonPiloto || contentAttributes.ramonRascunhoIa"`; após L582 `<RascunhoCarimbo v-if="contentAttributes.ramonRascunhoIa" />`.
- [ ] **Step 4: i18n** — dentro de `RAMON.COPILOTO`:
```json
"RASCUNHO_IA": { "igual": "rascunho da IA enviado como estava", "editado": "rascunho da IA, editado", "descartado": "rascunho da IA descartado" }
```
- [ ] **Step 5:** `npx pnpm@10.2.0 vitest run app/javascript/dashboard/components-next/message/specs/RascunhoCarimbo.spec.js` (lembrar da junction `postcss-import` do worktree se 5 specs ramon não carregarem — lição 16/08). Commit `feat(inteligencia): chip do carimbo de rascunho da IA`.

### Task 7: Skills — seed com as tools novas

**Files:**
- Modify: `db/seeds/ramon/inteligencia/assistentes.yml`

**Interfaces:** rake `ramon:inteligencia:seed[2]` é idempotente por (assistente, título) — não mudar títulos.

- [ ] **Step 1:** editar as instructions (adicionar parágrafo "Registrar/agir" com os links `[Rótulo](tool://id)`):
  - "Triagem e qualificação do lead novo": ao confirmar/descartar um critério, `[Registrar qualificação](tool://registrar_qualificacao)` com `status` ok|falta; nunca perguntar de novo o que já está ok.
  - "Dúvidas do lead e objeções": se o lead disser que desistiu/não tem interesse/já resolveu, `[Marcar como perdido](tool://marcar_perdido)` com o motivo mais próximo do catálogo (a sugestão fica pendente pro humano).
  - "Agendar conversa com o advogado": quando o lead pedir pra retomar depois ("me chama semana que vem"), `[Criar tarefa de cadência](tool://criar_tarefa_cadencia)` com a data que ele disse.
  - "Pós-venda — cobrar e receber documentos": usar `[Pedir documentos](tool://solicitar_documento)` pro texto da cobrança e `[Link do portal do cliente](tool://enviar_link_portal)` quando ele preferir mandar pelo celular; depois `[Criar tarefa de cadência](tool://criar_tarefa_cadencia)` "Conferir documentos de <nome>" pra 3 dias.
  - Copiloto "Revisao de documentos do caso": `[Pedir documentos](tool://solicitar_documento)` gera o texto pronto.
- [ ] **Step 2:** conferir que todo `tool://id` novo existe em `config/agents/tools.yml` (`grep -o 'tool://[a-z_]*' db/seeds/ramon/inteligencia/assistentes.yml | sort -u` vs `grep '^- id:' config/agents/tools.yml`).
- [ ] **Step 3: commit** `feat(inteligencia): skills usam as tools de escrita da onda 3`

## Onda 4

### Task 8: `RAMON_COPILOTO_MODO_DEFAULT` — back + front

**Files:**
- Modify: `enterprise/lib/ramon/copiloto_modo.rb` (L6 `DEFAULT`, L10-13 `of`)
- Create: `spec/enterprise/lib/ramon/copiloto_modo_spec.rb` (rubocop-only) **e** 1 caso em `spec/services/ramon/piloto_logistica_service_spec.rb`? não — criar `spec/lib/ramon/copiloto_modo_default_spec.rb` com guard `if: ChatwootApp.enterprise?` pra rodar no CI.
- Modify: `app/views/layouts/vueapp.html.erb` (L34-59, nova chave)
- Create: `app/javascript/dashboard/routes/dashboard/ramon/helpers/copilotoModo.js` (+ spec `helpers/specs/copilotoModo.spec.js`)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/CopilotoModoSelector.vue` (L11-18), `app/javascript/dashboard/components-next/message/PilotoCarimbo.vue` (L16-20)
- Modify: `.env.example`, `docs/FORK-PONTOS-DE-REGISTRO.md`

**Interfaces:**
- Produces: `Ramon::CopilotoModo.default` (String válida de `MODOS`, fallback `'rascunho'`); `window.chatwootConfig.ramonCopilotoModoDefault`; front `copilotoModoDe(chat) → string`.
- Ceiling (D7): quando o Eduardo virar a env pra `piloto_limitado`, conversas ANTIGAS sem atributo também mudam. Antes de virar: `rake` de uma linha no console carimbando `copiloto_modo: 'rascunho'` nas conversas abertas existentes (documentar no smoke doc, não codar agora).

- [ ] **Step 1: spec (`spec/lib/ramon/copiloto_modo_default_spec.rb`)**

```ruby
require 'rails_helper'

RSpec.describe 'Ramon::CopilotoModo default por env', if: ChatwootApp.enterprise? do
  let(:conversation) { create(:conversation) }

  it 'usa rascunho sem env' do
    with_modified_env RAMON_COPILOTO_MODO_DEFAULT: nil do
      expect(Ramon::CopilotoModo.of(conversation)).to eq('rascunho')
    end
  end

  it 'usa a env quando valida e ignora quando invalida' do
    with_modified_env RAMON_COPILOTO_MODO_DEFAULT: 'piloto_limitado' do
      expect(Ramon::CopilotoModo.of(conversation)).to eq('piloto_limitado')
    end
    with_modified_env RAMON_COPILOTO_MODO_DEFAULT: 'xablau' do
      expect(Ramon::CopilotoModo.of(conversation)).to eq('rascunho')
    end
  end

  it 'atributo da conversa vence a env' do
    conversation.update!(custom_attributes: { 'copiloto_modo' => 'manual' })
    with_modified_env RAMON_COPILOTO_MODO_DEFAULT: 'piloto_limitado' do
      expect(Ramon::CopilotoModo.of(conversation)).to eq('manual')
    end
  end
end
```

- [ ] **Step 2: módulo**

```ruby
  DEFAULT = 'rascunho'.freeze

  # D7: piloto_limitado vira padrao por env depois de ~20 conversas revisadas.
  # ponytail: a env vale pra TODA conversa sem atributo (antigas inclusive) — antes de virar,
  # carimbar copiloto_modo=rascunho nas abertas antigas pelo console.
  def default
    env = ENV.fetch('RAMON_COPILOTO_MODO_DEFAULT', DEFAULT).to_s.strip
    MODOS.include?(env) ? env : DEFAULT
  end

  def of(conversation)
    modo = conversation&.custom_attributes&.[]('copiloto_modo').to_s
    MODOS.include?(modo) ? modo : default
  end
```
Atualizar o comentário do topo ("default rascunho" → "default = RAMON_COPILOTO_MODO_DEFAULT, rascunho se vazia").

- [ ] **Step 3: `vueapp.html.erb`** — dentro de `window.chatwootConfig`, após `selectedLocale` (virar `selectedLocale: '...',`):
```erb
        ramonCopilotoModoDefault: '<%= ChatwootApp.enterprise? ? Ramon::CopilotoModo.default : 'rascunho' %>'
```

- [ ] **Step 4: helper front + spec**

```js
// app/javascript/dashboard/routes/dashboard/ramon/helpers/copilotoModo.js
export const MODOS = ['manual', 'rascunho', 'piloto_limitado', 'piloto_total'];

export const modoDefault = () => {
  const m = window.chatwootConfig?.ramonCopilotoModoDefault;
  return MODOS.includes(m) ? m : 'rascunho';
};

// Fonte unica do modo efetivo da conversa no front (espelha Ramon::CopilotoModo.of).
export const copilotoModoDe = chat => {
  const m = chat?.custom_attributes?.copiloto_modo;
  return MODOS.includes(m) ? m : modoDefault();
};
```
```js
// helpers/specs/copilotoModo.spec.js
import { copilotoModoDe, modoDefault } from '../copilotoModo';

describe('copilotoModo', () => {
  afterEach(() => { delete window.chatwootConfig; });
  it('cai em rascunho sem config', () => {
    expect(modoDefault()).toBe('rascunho');
    expect(copilotoModoDe({})).toBe('rascunho');
  });
  it('usa o default da config e ignora invalido', () => {
    window.chatwootConfig = { ramonCopilotoModoDefault: 'piloto_limitado' };
    expect(copilotoModoDe({ custom_attributes: {} })).toBe('piloto_limitado');
    expect(copilotoModoDe({ custom_attributes: { copiloto_modo: 'xablau' } })).toBe('piloto_limitado');
    window.chatwootConfig = { ramonCopilotoModoDefault: 'xablau' };
    expect(modoDefault()).toBe('rascunho');
  });
  it('atributo da conversa vence', () => {
    window.chatwootConfig = { ramonCopilotoModoDefault: 'piloto_limitado' };
    expect(copilotoModoDe({ custom_attributes: { copiloto_modo: 'manual' } })).toBe('manual');
  });
});
```

- [ ] **Step 5:** `CopilotoModoSelector.vue`: trocar `MODOS` local + `modo` computed por `import { MODOS, copilotoModoDe } from '../../helpers/copilotoModo'` e `const modo = computed(() => copilotoModoDe(currentChat.value))`; manter a comparação com o valor CRU no `escolher`. `PilotoCarimbo.vue` L16-20: `aindaEmPiloto = computed(() => copilotoModoDe(currentChat.value).startsWith('piloto_'))`. Rodar as specs existentes dos dois (`CopilotoModoSelector.spec.js` se existir + `PilotoCarimbo.spec.js`) — se algum mock de `window.chatwootConfig` faltar, o helper cai em `rascunho` (comportamento igual ao anterior).
- [ ] **Step 6:** `.env.example` (bloco ramon): `# ramon: modo padrao do copiloto em conversa sem escolha explicita — manual | rascunho (padrao) | piloto_limitado | piloto_total` / `# RAMON_COPILOTO_MODO_DEFAULT=rascunho`. Fork-ponto: `vueapp.html.erb ramonCopilotoModoDefault`.
- [ ] **Step 7: commit** `feat(inteligencia): RAMON_COPILOTO_MODO_DEFAULT (back+front)`

### Task 9: Views `bi_ia_rascunhos` + `bi_ia_conversas` (scenic)

**Files:**
- Create: `db/views/bi_ia_rascunhos_v01.sql`, `db/views/bi_ia_conversas_v01.sql`
- Create: `db/migrate/20260817000001_create_bi_ia_views.rb`
- Create: `spec/db/bi_ia_views_spec.rb` (roda no CI; `ActiveRecord::Base.connection.select_all`)
- Modify: `db/schema.rb` (o CI não regenera — editar à mão o bloco `create_view` no fim, mesmo padrão dos `bi_leads`/`bi_stage_transitions`)

**Interfaces:**
- Consumes: `messages.content_attributes` (json): `ramon_piloto`, `ramon_rascunho_ia.nota_id/desfecho`; `reporting_events.name = 'conversation_bot_handoff'`; nota-rascunho (Task 5).
- Produces (Metabase):
  - `bi_ia_rascunhos`: 1 linha por nota-rascunho: `nota_id, account_id, conversation_id, inbox_id, criado_em, desfecho ('igual'|'editado'|'descartado'|'sem_resposta'|'pendente'), mensagem_id (da humana carimbada), minutos_ate_envio`.
  - `bi_ia_conversas`: 1 linha por conversa com ≥1 incoming: `conversation_id, account_id, inbox_id, iniciada_em, primeira_resposta_em, minutos_primeira_resposta, com_ia (bool: existe ramon_piloto ou ramon_rascunho_ia), pilotos_enviados, rascunhos, handoffs`.

- [ ] **Step 1: SQL `bi_ia_rascunhos_v01.sql`**

```sql
-- Notas-rascunho do Assistente e o que o humano fez com elas (metrica D8 / decisao D7).
WITH notas AS (
  SELECT m.id AS nota_id, m.account_id, m.conversation_id, m.inbox_id, m.created_at AS criado_em
  FROM messages m
  WHERE m.private = true AND m.sender_type = 'Captain::Assistant'
    AND m.content LIKE 'RASCUNHO (revisar antes de enviar):%'
),
enviadas AS (
  SELECT ((m.content_attributes::jsonb)->'ramon_rascunho_ia'->>'nota_id')::bigint AS nota_id,
         m.id AS mensagem_id, m.created_at AS enviada_em,
         (m.content_attributes::jsonb)->'ramon_rascunho_ia'->>'desfecho' AS desfecho
  FROM messages m
  WHERE (m.content_attributes::jsonb) ? 'ramon_rascunho_ia'
)
SELECT n.nota_id, n.account_id, n.conversation_id, n.inbox_id, n.criado_em,
       COALESCE(e.desfecho,
                CASE WHEN EXISTS (SELECT 1 FROM messages i WHERE i.conversation_id = n.conversation_id
                                    AND i.message_type = 0 AND i.created_at > n.criado_em)
                     THEN 'sem_resposta' ELSE 'pendente' END) AS desfecho,
       e.mensagem_id,
       ROUND(EXTRACT(EPOCH FROM (e.enviada_em - n.criado_em)) / 60.0, 1) AS minutos_ate_envio
FROM notas n
LEFT JOIN enviadas e ON e.nota_id = n.nota_id;
```
(CONFIRMADO: `messages.content_attributes` é `json` (schema.rb L1236) — por isso o cast `::jsonb` em toda ocorrência; `?` e `->` não existem em `json`.)

- [ ] **Step 2: SQL `bi_ia_conversas_v01.sql`**

```sql
-- Tempo ate a 1a resposta com/sem IA + contagens por conversa (metrica D8).
WITH base AS (
  SELECT c.id AS conversation_id, c.account_id, c.inbox_id,
         MIN(CASE WHEN m.message_type = 0 THEN m.created_at END) AS iniciada_em,
         MIN(CASE WHEN m.message_type = 1 AND m.private = false THEN m.created_at END) AS primeira_resposta_em,
         COUNT(*) FILTER (WHERE (m.content_attributes::jsonb) ? 'ramon_piloto') AS pilotos_enviados,
         COUNT(*) FILTER (WHERE m.private = true AND m.sender_type = 'Captain::Assistant'
                            AND m.content LIKE 'RASCUNHO (revisar antes de enviar):%') AS rascunhos,
         COUNT(*) FILTER (WHERE (m.content_attributes::jsonb) ? 'ramon_rascunho_ia') AS rascunhos_usados
  FROM conversations c
  JOIN messages m ON m.conversation_id = c.id
  GROUP BY c.id, c.account_id, c.inbox_id
)
SELECT b.conversation_id, b.account_id, b.inbox_id, b.iniciada_em, b.primeira_resposta_em,
       ROUND(EXTRACT(EPOCH FROM (b.primeira_resposta_em - b.iniciada_em)) / 60.0, 1) AS minutos_primeira_resposta,
       (b.pilotos_enviados + b.rascunhos_usados) > 0 AS com_ia,
       b.pilotos_enviados, b.rascunhos, b.rascunhos_usados,
       (SELECT COUNT(*) FROM reporting_events r
         WHERE r.conversation_id = b.conversation_id AND r.name = 'conversation_bot_handoff') AS handoffs
FROM base b
WHERE b.iniciada_em IS NOT NULL;
```

- [ ] **Step 3: migração**

```ruby
class CreateBiIaViews < ActiveRecord::Migration[7.1]
  def change
    create_view :bi_ia_rascunhos
    create_view :bi_ia_conversas
  end
end
```
+ `db/schema.rb`: bump da versão e os dois `create_view "bi_ia_rascunhos", sql_definition: <<-SQL ... SQL` no fim (copiar o SQL literal — scenic dumpa assim; olhar como `bi_leads` está no schema).

- [ ] **Step 4: spec**

```ruby
require 'rails_helper'

RSpec.describe 'views bi_ia' do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) { create(:user, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }

  def sql(q) = ActiveRecord::Base.connection.select_all(q).to_a

  it 'bi_ia_rascunhos classifica a nota pelo carimbo' do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'oi')
    nota = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, private: true,
                            sender: assistant, content: "RASCUNHO (revisar antes de enviar):\nOla, tudo bem?")
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent,
                     content: 'Ola, tudo bem?')

    linha = sql("SELECT * FROM bi_ia_rascunhos WHERE nota_id = #{nota.id}").first
    expect(linha).to include('desfecho' => 'igual', 'conversation_id' => conversation.id)
    expect(linha['minutos_ate_envio']).to be_present
  end

  it 'bi_ia_conversas mede a primeira resposta e marca com_ia' do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'oi',
                     created_at: 10.minutes.ago)
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: assistant,
                     content: 'Ola!', content_attributes: { 'ramon_piloto' => { 'modo' => 'piloto_limitado' } })

    linha = sql("SELECT * FROM bi_ia_conversas WHERE conversation_id = #{conversation.id}").first
    expect(linha['com_ia']).to be(true)
    expect(linha['pilotos_enviados']).to eq(1)
    expect(linha['minutos_primeira_resposta'].to_f).to be_between(9, 11)
  end
end
```
(CONFIRMADO: o CI roda `db:schema:load` (`run_foss_spec.yml` L112) — o `schema.rb` PRECISA dos dois `create_view`, senão a spec falha.)

- [ ] **Step 5: commit** `feat(inteligencia): views bi_ia_rascunhos e bi_ia_conversas`

### Task 10: Docs de operação (no PR)

**Files:**
- Modify: `docs/superpowers/plans/2026-08-17-inteligencia-ondas-3-4.md` (seção "Depois do merge" abaixo já é a fonte)
- Create: `comercial\docs\2026-08-17-smoke-inteligencia-ondas-3-4.md` (fora do repo — escrever após o deploy, com o que foi provado no console)

## Depois do merge (eu, sessão que executa)
1. CI verde → merge squash → workflow "Publica imagem" → `docker compose pull && up -d` na VPS → conferir label da imagem = sha do squash + `/api` 200.
2. **Migração à mão**: `docker compose exec chatwoot-web bundle exec rails db:migrate` → psql `\dv bi_ia*` (2 views).
3. `bundle exec rake ramon:inteligencia:seed[2]` (skills atualizadas; idempotente).
4. Smoke no console (Playground V2 = `Captain::Assistant::AgentRunnerService.new(assistant:, source: 'playground').generate_response(message_history: [{role:'user',content:}])`): cada tool nova no caso de teste; `CopilotSuggestion` 'perdido' aplicada e revertida no Kanban; mandar 1 mensagem humana a partir de um RASCUNHO e ver `content_attributes.ramon_rascunho_ia`; `SELECT * FROM bi_ia_rascunhos LIMIT 5`.
5. Metabase (chave em arquivo server-side, como 14/08 — nunca em doc): 4 cards no dashboard "Análise Comercial", seção "Inteligência": (a) rascunhos por desfecho (7 d, barra) `SELECT desfecho, COUNT(*) FROM bi_ia_rascunhos WHERE criado_em > now() - interval '7 days' GROUP BY 1`; (b) % enviado sem edição (número) `SELECT ROUND(100.0*COUNT(*) FILTER (WHERE desfecho='igual')/NULLIF(COUNT(*) FILTER (WHERE desfecho IN ('igual','editado','descartado')),0),1) FROM bi_ia_rascunhos`; (c) minutos até 1ª resposta com × sem IA (barra) `SELECT com_ia, ROUND(AVG(minutos_primeira_resposta),1) FROM bi_ia_conversas WHERE iniciada_em > now() - interval '30 days' GROUP BY 1`; (d) handoffs por dia `SELECT date_trunc('day', iniciada_em), SUM(handoffs) FROM bi_ia_conversas GROUP BY 1 ORDER BY 1 DESC LIMIT 30`. Gate D7 = card (b) ≥ 20 rascunhos avaliados com "igual"+"editado" alto → Eduardo decide virar `RAMON_COPILOTO_MODO_DEFAULT`.
6. Smoke doc + atualizar caderno de provas (D8) com 1 conversa por tool nova; memória `inteligencia-area-completa.md`.

## Self-review (feito ao escrever)
- Spec Onda 3: registrar_qualificacao ✔ T1 · criar_tarefa_cadencia ✔ T2 · marcar_perdido (Sugestão) ✔ T3 · solicitar_documento/enviar_link_portal (rascunho) ✔ T4 · carimbo ✔ T5+T6 · skills ✔ T7. Onda 4: env ✔ T8 · `bi_ia` + bloco Metabase ✔ T9 + pós-merge 5. Objeções (D8) NÃO têm dado estruturado — fora (dito no plano; se quiser, kind novo em `lead_activities` numa onda futura).
- Nomes cruzados: `ramon_rascunho_ia` (T5/T6/T9), `Ramon::CopilotoModo.default` (T8), `copilotoModoDe` (T8), payload `lost_reason` (T3), prefixo `RASCUNHO (revisar antes de enviar):` (T5/T9 = `response_builder_job.rb`).
- Conferidos antes de executar: `content_attributes` é json → cast `::jsonb` (T9); `with_modified_env` (spec_helper L16); `motivo_da_recusa` reader (model L20); CI usa `db:schema:load`.
