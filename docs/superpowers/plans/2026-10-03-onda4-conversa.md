# Onda 4 — Conversa (lista, cabeçalho, bolhas, painel por caixa, chegada) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A tela de conversa fica igual ao mockup v2: lista enxuta com etiqueta de etapa + selo do prazo de 5 min, cabeçalho só com nome + Copiloto + Resolver, bolhas neutras/azul translúcido, painel lateral que muda conforme a caixa (lead no comercial; cliente ADVBOX + "Atribuir a…" no escritório) e o aviso de chegada em tela cheia.

**Architecture:** Backend ganha (1) um bloco slim `ramon_lead` no JSON da conversa (etapa/cor/tese, com preload), (2) o registro de quem atribuiu a conversa (`additional_attributes.ramon_atribuicao`) e (3) `GET conversations/:id/ramon_cliente` (cliente do painel ADVBOX por telefone, sem gastar cota). Front reaproveita `SeloPrazo`/`Selo` da Onda 3, mexe nos componentes nativos só nos pontos marcados `FORK(ramon)`, reorganiza o `LeadPanelBody` (abas → seções recolhíveis, nada some) e cria `ClientePanel.vue`.

**Tech Stack:** Rails 7.1 + RSpec; Vue 3, Vuex/Pinia, Tailwind, Vitest.

**Spec:** `docs/superpowers/specs/2026-10-03-redesign-v2-fiel-ao-mockup.md` · alvo `docs/superpowers/specs/mockups/2026-10-03-hub-v2.html` (tela `.t-conversa`, `.lista`, `.chat`, `.painel`, `#chegada`; papéis Gestor/SDR para o comercial e Recepção/Advogada para o escritório).

## Global Constraints

- Branch `feat/conversa` empilhada em `feat/tela-hoje` (Onda 3) — usa `components/hoje/SeloPrazo.vue` e `Selo.vue`.
- Sem Ruby local (CI valida); Rubocop do projeto; arquivos upstream (Chatwoot) mexidos só com comentário `FORK(ramon)` e o mínimo.
- Tailwind only, i18n pt_BR + en, `font-mono` em hora/telefone/nº de processo, fundos coloridos translúcidos.
- Bolhas: recebida `bg-n-slate-3 text-n-slate-12`; enviada `bg-n-blue-9/[0.08] dark:bg-n-blue-9/[0.16] text-n-slate-12`; nota privada `bg-n-amber-9/15 text-n-slate-12`.
- Nenhuma função atual some: abas do painel do lead viram linhas recolhíveis; multi-seleção da lista continua (checkbox no hover).
- Nada é enviado ao cliente sozinho: respostas rápidas da chegada vão pra quem AVISOU (interno), não pro cliente.

## Review Focus

1. Conversa sem lead (caixa do escritório, ou comercial antes do lead nascer) → lista sem etiqueta, sem selo, sem erro.
2. Conversa já respondida (`first_reply_created_at` > 0) → sem selo de prazo, mostra só a hora.
3. Cliente sem cadastro no painel (`PortalCliente` não acha o telefone) → painel do escritório mostra "Número novo" + "Encaminhar ao comercial" e o "Atribuir a…" continua funcionando.
4. Atribuição feita por automação (sem `Current.user`) → não grava `ramon_atribuicao` com nome vazio; a faixa da advogada some.
5. Tema escuro: bolhas, etiquetas e o overlay de chegada legíveis (contraste do texto sobre o translúcido).

---

### Task 1: Backend — lead slim na conversa + registro de atribuição

**Files:**
- Create: `app/models/concerns/ramon_conversa.rb`
- Modify: `app/models/conversation.rb` (uma linha `include RamonConversa  # FORK(ramon)`)
- Modify: `app/views/api/v1/conversations/partials/_conversation.json.jbuilder` (bloco `ramon_lead`)
- Modify: finder/controller que lista conversas — preload `:ramon_lead` (`app/finders/conversation_finder.rb`, onde já há `includes(...)`)
- Test: `spec/models/concerns/ramon_conversa_spec.rb` (ou no `spec/models/conversation_spec.rb` se houver padrão), `spec/requests/api/v1/accounts/conversations_spec.rb` (asserção nova, se o arquivo existir — `git grep` antes)

**Interfaces:**
- Produces: `conversation.ramon_lead` (has_one Lead); JSON da conversa ganha `ramon_lead: { id, stage_name, stage_color, thesis_name } | nil`; `additional_attributes.ramon_atribuicao = { por_id, por_nome, em }` gravado quando `assignee_id` ou `team_id` muda com `Current.user` presente.

- [ ] **Step 1: Spec que falha**

```ruby
require 'rails_helper'

RSpec.describe RamonConversa do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:gabriela) { create(:user, account: account, name: 'Gabriela') }
  let(:tamires) { create(:user, account: account) }

  after { Current.reset }

  it 'grava quem atribuiu e quando' do
    Current.user = gabriela
    conversation.update!(assignee: tamires)
    registro = conversation.reload.additional_attributes['ramon_atribuicao']
    expect(registro).to include('por_id' => gabriela.id, 'por_nome' => 'Gabriela')
    expect(Time.zone.parse(registro['em'])).to be_within(5.seconds).of(Time.current)
  end

  it 'sem usuário (automação) não grava' do
    conversation.update!(assignee: tamires)
    expect(conversation.reload.additional_attributes['ramon_atribuicao']).to be_nil
  end

  it 'expõe o lead da conversa' do
    lead = create(:lead, account: account, conversation: conversation)
    expect(conversation.reload.ramon_lead).to eq(lead)
  end
end
```

(Confira como o projeto zera `Current` nos specs — se `Current.reset` não existir, use `Current.user = nil`.)

- [ ] **Step 2: Implementar**

`app/models/concerns/ramon_conversa.rb`:

```ruby
# FORK(ramon): o que a tela de conversa do redesign v2 precisa da conversa —
# o lead (etiqueta de etapa na lista) e quem atribuiu (faixa "Atribuída a você
# por X · hh:mm" e "Atribuídas hoje" da Recepção).
module RamonConversa
  extend ActiveSupport::Concern

  included do
    has_one :ramon_lead, class_name: 'Lead', inverse_of: :conversation, dependent: nil
    before_update :registrar_atribuicao, if: -> { will_save_change_to_assignee_id? || will_save_change_to_team_id? }
  end

  private

  def registrar_atribuicao
    return if Current.user.blank?

    self.additional_attributes = (additional_attributes || {}).merge(
      'ramon_atribuicao' => { 'por_id' => Current.user.id, 'por_nome' => Current.user.name, 'em' => Time.current.iso8601 }
    )
  end
end
```

(Se `inverse_of: :conversation` reclamar porque `Lead belongs_to :conversation` não declara inverse, tire o `inverse_of`. `dependent: nil` deixa explícito que apagar conversa não mexe no lead — o `Lead` já é `optional`.)

`conversation.rb`: logo após os outros `include` → `include RamonConversa # FORK(ramon)`.

Jbuilder — no fim do partial:

```ruby
# FORK(ramon): etiqueta de etapa + tese na lista de conversas (redesign v2)
lead = conversation.ramon_lead
json.ramon_lead lead && { id: lead.id, stage_name: lead.lead_stage&.name, stage_color: lead.lead_stage&.color, thesis_name: lead.thesis&.name }
```

Preload: no `ConversationFinder` (e em qualquer outro lugar que renderize a lista — `git grep -n "includes(" app/finders/conversation_finder.rb`), acrescente `ramon_lead: [:lead_stage, :thesis]` ao `includes` existente.

- [ ] **Step 3: Commit** — `feat(conversa): lead slim no JSON da conversa e registro de quem atribuiu`

---

### Task 2: Backend — cliente do escritório (`ramon_cliente`)

**Files:**
- Create: `app/services/ramon/cliente_da_conversa.rb`
- Create: `app/controllers/api/v1/accounts/conversations/ramon_clientes_controller.rb`
- Modify: `config/routes.rb` (dentro do `resources :conversations ... do` existente: `resource :ramon_cliente, only: [:show]`)
- Test: `spec/services/ramon/cliente_da_conversa_spec.rb`, `spec/requests/api/v1/accounts/conversations/ramon_clientes_spec.rb`

**Interfaces:**
- Consumes: `PortalCliente` (`telefone` só dígitos, `processos` jsonb: `numero, tipo, inicio, responsavel, responsavel_id, etapa, fase, andamentos[{data, titulo}]`), `Ramon::AdvboxUsuarios.usuario` (Onda 3), `Ramon::SemanaAdvboxService` (Onda 3).
- Produces: `GET /api/v1/accounts/:account_id/conversations/:conversation_id/ramon_cliente` → `{ cliente: false }` ou `{ cliente: true, nome, desde ('YYYY-MM'), advogada: { nome, user_id|nil }, telefone, processos: [{ numero, tipo, fase, ultimo_andamento: { data, titulo } | nil }], compromisso: { tipo: 'pericia'|'audiencia', data, hora, notas } | nil, sugestao_user_id }`. ADVBOX fora só zera `compromisso`.

- [ ] **Step 1: Spec que falha** (`cliente_da_conversa_spec.rb`)

```ruby
require 'rails_helper'

RSpec.describe Ramon::ClienteDaConversa do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5548991203381') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  before { allow(Ramon::SemanaAdvboxService).to receive(:new).and_return(instance_double(Ramon::SemanaAdvboxService, tarefas_do_processo: [])) }

  it 'número que não está no painel do cliente → cliente: false' do
    expect(described_class.new(conversation).perform).to eq(cliente: false)
  end

  it 'acha pelo telefone (com ou sem 55) e monta processos e responsável' do
    create(:portal_cliente, account: account, telefone: '48991203381', nome: 'Maria',
                            processos: [{ 'numero' => '5003412-18.2024.4.04.7207', 'tipo' => 'Auxílio-doença', 'inicio' => '2023-03-10',
                                          'responsavel' => 'TAMIRES', 'responsavel_id' => 7, 'fase' => 'Perícia',
                                          'andamentos' => [{ 'data' => '2026-09-30', 'titulo' => 'Perícia designada' }] }])
    dados = described_class.new(conversation).perform
    expect(dados).to include(cliente: true, desde: '2023-03')
    expect(dados[:processos].first).to include(numero: '5003412-18.2024.4.04.7207', ultimo_andamento: { data: '2026-09-30', titulo: 'Perícia designada' })
  end
end
```

(Confira a factory `:portal_cliente` e as colunas reais do model — nome do campo de nome/CPF, se tem `account_id`. Ajuste.)

- [ ] **Step 2: Implementar**

Em `Ramon::SemanaAdvboxService` (Onda 3) acrescente um método público que reusa o mesmo cache:

```ruby
  def tarefas_do_processo(numero)
    tarefas.select { |tarefa| tarefa.dig('lawsuit', 'process_number') == numero }.map { |tarefa| linha(tarefa) }
  end
```

`app/services/ramon/cliente_da_conversa.rb`:

```ruby
# Painel do CLIENTE na caixa do escritório (redesign v2): quem é, desde quando,
# advogada responsável, processos e o próximo compromisso — sem chamar o ADVBOX
# por conversa (vem do espelho PortalCliente + cache semanal de tarefas).
class Ramon::ClienteDaConversa
  def initialize(conversation)
    @conversation = conversation
  end

  def perform
    cliente = portal_cliente
    return { cliente: false } unless cliente

    processos = Array(cliente.processos)
    principal = processos.first || {}
    {
      cliente: true, nome: cliente.nome, desde: processos.filter_map { |p| p['inicio'] }.min.to_s[0, 7].presence,
      advogada: { nome: principal['responsavel'], user_id: sugestao(principal)&.id }, telefone: @conversation.contact&.phone_number,
      processos: processos.map { |p| processo(p) }, compromisso: compromisso(processos), sugestao_user_id: sugestao(principal)&.id
    }
  end

  private

  def portal_cliente
    digitos = @conversation.contact&.phone_number.to_s.gsub(/\D/, '')
    return if digitos.blank?

    PortalCliente.where(account_id: @conversation.account_id).find_by(telefone: [digitos, digitos.last(11)])
  end

  def processo(proc)
    ultimo = Array(proc['andamentos']).max_by { |a| a['data'].to_s }
    { numero: proc['numero'], tipo: proc['tipo'], fase: proc['fase'],
      ultimo_andamento: ultimo && { data: ultimo['data'], titulo: ultimo['titulo'] } }
  end

  def sugestao(proc)
    @sugestao ||= proc['responsavel_id'] && Ramon::AdvboxUsuarios.usuario(@conversation.account, proc['responsavel_id'])
  end

  def compromisso(processos)
    servico = Ramon::SemanaAdvboxService.new(@conversation.account)
    tarefa = processos.flat_map { |p| servico.tarefas_do_processo(p['numero']) }.find { |t| t[:destaque] }
    tarefa && { tipo: tarefa[:destaque], data: tarefa[:data], hora: tarefa[:hora], notas: tarefa[:notas] }
  rescue StandardError
    nil
  end
end
```

(Se `PortalCliente` não tiver `account_id`, tire o `where`. Se o nome da pessoa estiver em outra coluna, ajuste `cliente.nome`.)

Controller (padrão dos controllers aninhados em conversa — veja `app/controllers/api/v1/accounts/conversations/base_controller.rb`; herde dele, ele já carrega `@conversation` e autoriza):

```ruby
class Api::V1::Accounts::Conversations::RamonClientesController < Api::V1::Accounts::Conversations::BaseController
  def show
    render json: Ramon::ClienteDaConversa.new(@conversation).perform
  end
end
```

Request spec: 401 sem login; 200 com `{ "cliente" => false }` para contato sem cadastro; agente sem acesso à conversa recebe 404/401 (mesmo comportamento dos irmãos — confira e afirme o que eles fazem).

- [ ] **Step 3: Commit** — `feat(conversa): cliente do escritório no painel (ramon_cliente)`

---

### Task 3: Lista de conversas igual ao mockup

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/helpers/prazoConversa.js`
- Modify: `app/javascript/dashboard/components/widgets/conversation/ConversationCard.vue` (`FORK(ramon)`)
- Modify: `app/javascript/dashboard/components/widgets/conversation/conversationCardComponents/CardLabels.vue` (esconder `fase-*`)
- Test: `ramon/helpers/specs/prazoConversa.spec.js`, `components/widgets/conversation/specs/ConversationCard.spec.js` (criar — não existe)

**Interfaces:**
- Produces: `prazoDaConversa(chat, inbox) → string ISO | null` — `null` se inbox sem `auto_create_lead`, se já respondida (`first_reply_created_at` truthy e ≠ 0) ou se faltam dados; senão `created_at(segundos) + (inbox.first_response_sla_minutes || 5) min`.

- [ ] **Step 1: Spec do helper**

```js
import { prazoDaConversa } from '../prazoConversa';

const inbox = { auto_create_lead: true, first_response_sla_minutes: null };
const criada = 1759496400; // 2025-10-03T13:00:00Z em segundos

describe('prazoDaConversa', () => {
  it('criação + 5 min por padrão', () => {
    expect(prazoDaConversa({ created_at: criada, first_reply_created_at: 0 }, inbox)).toBe('2025-10-03T13:05:00.000Z');
  });
  it('usa o SLA da caixa', () => {
    expect(prazoDaConversa({ created_at: criada, first_reply_created_at: 0 }, { ...inbox, first_response_sla_minutes: 60 })).toBe('2025-10-03T14:00:00.000Z');
  });
  it('respondida ou caixa sem lead → null', () => {
    expect(prazoDaConversa({ created_at: criada, first_reply_created_at: criada + 30 }, inbox)).toBeNull();
    expect(prazoDaConversa({ created_at: criada, first_reply_created_at: 0 }, { auto_create_lead: false })).toBeNull();
  });
});
```

- [ ] **Step 2: Implementar o helper**

```js
// Prazo de 1ª resposta na lista de conversas (mesma regra de Ramon::Cadencia:
// SLA da caixa, padrão 5 min; só em caixa que cria lead; some quando respondida).
const PADRAO_MINUTOS = 5;

export const prazoDaConversa = (chat, inbox) => {
  if (!inbox?.auto_create_lead || !chat?.created_at) return null;
  if (chat.first_reply_created_at) return null;
  const minutos = inbox.first_response_sla_minutes || PADRAO_MINUTOS;
  return new Date((chat.created_at + minutos * 60) * 1000).toISOString();
};
```

(Confira no payload real se `created_at` da conversa vem em segundos — no Chatwoot vem; e se `first_reply_created_at` sem resposta é `0` ou `null`. O helper aceita os dois.)

- [ ] **Step 3: `ConversationCard.vue` (FORK(ramon), mudanças mínimas)**
  - Sai o `<Avatar>` grande; no lugar, uma coluna estreita (`w-3 flex-shrink-0 relative`) com: bolinha azul `absolute left-[1px] top-[18px] size-1.5 rounded-full bg-n-blue-9` quando `hasUnread`; e o `<Checkbox v-model="selectedModel" />` aparecendo nesse lugar quando `hovered || selected` (mantém a multi-seleção). `mouseenter/leave` passam pro container.
  - Linha 1: nome (`text-[13.5px] font-medium`, `text-n-slate-12` se não lida) + à direita `<SeloPrazo v-if="prazo" :prazo-em="prazo" />` senão `TimeAgo` em `font-mono text-[11.5px] text-n-slate-9`.
  - Linha 2 (`flex items-center gap-2 text-xs text-n-slate-9 mt-[3px] mb-0.5`): se `chat.ramon_lead`, `<span class="ramon-stage-pill" …>{{ stage_name }}</span>` (copie o binding exato que a Onda 1 usa no `KanbanColumn`/`LeadCard`) + `thesis_name`; senão, nada.
  - Linha 3: `MessagePreview` como hoje (`text-[13px] text-n-slate-11`, `text-n-slate-12` se não lida).
  - Sai a meta row de `InboxName`/assignee/prioridade? **Não** — mantenha `InboxName` só quando `showInboxName` (gestor com várias caixas) numa linha discreta abaixo do nome; assignee e prioridade continuam quando presentes (são pequenos). `UnreadBadge` sai (a bolinha substitui).
  - Card ativo: `bg-n-slate-4 shadow-[inset_2px_0_0_rgb(var(--blue-9))]`; hover `bg-n-slate-3`; separador `border-b border-n-weak`; padding `px-4 py-3`.
  - `prazo = computed(() => prazoDaConversa(props.chat, inbox.value))`.
  - `CardLabels`: filtrar fora etiquetas que começam com `fase-` (a etapa já aparece como etiqueta própria). O `SLACardLabel` nativo sai do card (o selo de prazo substitui).
- [ ] **Step 4: Spec do card** — monta com um `chat` com `ramon_lead` e inbox com `auto_create_lead` → mostra a etiqueta com o nome da etapa e um `SeloPrazo`; chat respondido → sem `SeloPrazo`; etiqueta `fase-novo` não aparece no `CardLabels`. (Mocke store/getters que o card usa — leia o componente; use `shallowMount` com stubs nos filhos pesados.)
- [ ] **Step 5: Commit** — `feat(conversa): lista com etiqueta de etapa e selo do prazo de 5 min`

---

### Task 4: Cabeçalho enxuto e bolhas

**Files:**
- Modify: `app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue` (FORK)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/CopilotoModoSelector.vue` (gatilho em tint)
- Modify: `app/javascript/dashboard/components-next/message/bubbles/Base.vue` (`varaintBaseMap`)
- Test: specs existentes de `CopilotoModoSelector` e de bolhas (`components-next/message/bubbles/specs` ou `message/specs`) continuam verdes; ajuste só asserção de classe.

- [ ] **Step 1: Cabeçalho** — altura `h-14`, `px-5`, `border-b border-n-weak`, sem quebra (`whitespace-nowrap`):
  - esquerda: `BackButton` (mobile) + nome `text-[14.5px] font-semibold truncate` (sai o `Avatar`, sai a linha de `#id`/caixa; mantém o ícone de não verificado e o texto de soneca ao lado do nome quando houver);
  - direita: `CopilotoModoSelector` (gatilho com `bg-n-blue-9/[0.08] dark:bg-n-blue-9/[0.16] text-n-blue-11 border-transparent font-medium`, ícone `i-lucide-sparkles` e chevron), `LeadPanelToggle` (fica — esconde/mostra o painel), `MoreActions` (contém Resolver). Sai `SLACardLabel` e `ConversationCallButton` (não usamos ligação).
- [ ] **Step 2: Bolhas** — em `varaintBaseMap`: `AGENT` → `'bg-n-blue-9/[0.08] dark:bg-n-blue-9/[0.16] text-n-slate-12'`; `USER` → `'bg-n-slate-3 text-n-slate-12'`; `PRIVATE` → `'bg-n-amber-9/15 text-n-slate-12 [&_.prosemirror-mention-node]:font-semibold'`; `BOT`/`TEMPLATE` → mesmo do `AGENT`. Comentário `// FORK(ramon): redesign v2`.
- [ ] **Step 3: Rodar specs tocados; commit** — `feat(conversa): cabeçalho enxuto e bolhas no visual v2`

---

### Task 5: Painel do lead igual ao mockup (abas → seções recolhíveis)

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadPanelBody.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/composables/useLeadPanelSections.js` (aba ativa → seção aberta; chave de localStorage nova `ramon_lead_panel_abertas` com array)
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/SecaoRecolhivel.vue`
- Test: `components/lead/specs/LeadPanelBody.spec.js` (atualizar), `composables/specs/useLeadPanelSections.spec.js` (se existir — `git grep`)

**Interfaces:**
- Produces: `<SecaoRecolhivel :titulo :contagem="'3/5'|null" :aberta @alternar><slot/></SecaoRecolhivel>`; `useLeadPanelSecoes() → { abertas: Ref<string[]>, alternar(id) }`.

Estrutura final (de cima pra baixo, cada bloco `px-[18px] py-4 border-b border-n-weak`), igual ao mockup `.painel`:

1. **Etapa** — título pequeno "Etapa" + à direita "há N dias" (`font-mono text-xs text-n-slate-9`, de `stage_entered_at`); etiqueta grande `ramon-stage-pill text-[13px] px-3 py-1.5` com o seletor de etapa atual (o `select`/menu que já existe abre ao clicar na etiqueta — mantém o fluxo de ganho com confirmação de valor); `MiniEsteira` com o preenchido na cor da etapa; linha de apoio (próxima reunião "Quinta, 10h · com {closer}" se houver task meeting; senão tese).
2. **Próximo passo** — bloco `bg-n-blue-9/[0.08] dark:bg-n-blue-9/[0.16]`, título "Próximo passo" `text-n-blue-11 font-semibold text-xs`, conteúdo do `LeadNextAction` (texto grande + apoio), botões "Abrir ficha" (cheio azul → `ramon_lead_dossie`) e "Follow-up" (borda → o `TaskBellMenu`/ação de follow-up que já existe).
3. **Risco de esfriar** — só quando o card de risco atual aparece (`lead.stalled` ou a regra existente): bloco `bg-n-ruby-9/10 shadow-[inset_4px_0_0_rgb(var(--ruby-9))]`, título `text-n-ruby-11 font-semibold` com `i-lucide-triangle-alert`, texto `text-n-slate-12`.
4. **Recolhíveis** (`SecaoRecolhivel`, linha `px-[18px] py-3 border-b border-n-weak text-[13px] text-n-slate-11 hover:bg-n-slate-3`, contagem em `font-mono text-n-slate-9`, chevron `i-lucide-chevron-right` que gira 90° aberto), nesta ordem:
   - Qualificação `N/M` → `QualificacaoViva` (+ `LeadQuizResumo`)
   - Documentos `X/Y` → `DocChecklist`
   - Cálculos → `LeadSimulador`
   - Copiloto → `LeadCopilot`
   - Playbook → `LeadPlaybook`
   - Contrato → `LeadZapsignCard`
   - Notas → `LeadNotes`
   - Histórico → `LeadHistory`
   - Temperatura → o cartão Temperatura atual
   - Dados do contato → `LeadFields` (+ caso/tese)
5. Sai a barra de abas e o botão `ResolveAction` duplicado do painel (o Resolver está no cabeçalho). WhatsApp/Tarefa: Tarefa já está no Follow-up; o atalho WhatsApp vira item dentro de "Dados do contato".

Se o `LeadPanelBody` também é usado na gaveta do Kanban (`LeadDrawer`, prop `context`), a mesma estrutura vale lá.

- [ ] **Step 1: Spec** — atualize `LeadPanelBody.spec.js`: com um lead parado mostra "Risco de esfriar"; "Próximo passo" tem link pra ficha; clicar em "Documentos" abre o `DocChecklist`; não existe mais `role="tablist"`. Mantenha os testes de fluxo de ganho/etapa que já existem (adapte seletores, não apague).
- [ ] **Step 2: Implementar** `SecaoRecolhivel.vue`, o composable e a nova estrutura.
- [ ] **Step 3: Rodar `routes/dashboard/ramon` inteiro; commit** — `feat(conversa): painel do lead enxuto com seções recolhíveis`

---

### Task 6: Painel de cliente na caixa do escritório

**Files:**
- Create: `app/javascript/dashboard/api/ramonCliente.js`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/ClientePanel.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadConversationPanel.vue` (ramo `semLead` → `ClientePanel`)
- Test: `components/conversation/specs/ClientePanel.spec.js`, `LeadConversationPanel.spec.js` (ajuste)

**Interfaces:**
- Consumes: `GET .../conversations/:id/ramon_cliente` (Task 2); `additional_attributes.ramon_atribuicao` (Task 1); store nativa de atribuição (`assignAgent`/`assignTeam` — use as mesmas actions/API que o `ConversationAction` nativo usa: `git grep -n "assignAgent\|assignTeam" app/javascript/dashboard/store/modules/conversations`); getters `teams/getTeams`, `agents/getAgents`, `getCurrentUserID`; `leads/encaminharComercial`.

Estrutura (mockup `.painel[data-for="recepcao advogada"]`):

1. **Faixa da advogada** (só se `meta.assignee.id === currentUserId` e há `ramon_atribuicao`): `bg-n-blue-9/[0.08] dark:bg-n-blue-9/[0.16] text-n-blue-11 text-[12.5px] font-medium px-[18px] py-2.5`, ícone `i-lucide-user-check`, "Atribuída a você por {por_nome} · {hh:mm}", botão "Devolver" sublinhado à direita → tira agente e time (volta pra fila sem responsável).
2. **Atribuir a…** (quem não é o responsável atual — na prática Recepção/controladoria/gestor): botão cheio grande azul largura total com `i-lucide-user-plus`; ao clicar abre a lista (mesmo bloco, abaixo, `border border-n-strong rounded-[10px] p-1.5 shadow`): primeiro a sugestão (`sugestao_user_id`) com fundo tint e "do processo" à direita; depois os demais membros do time `advogados`; separador; "Controladoria (Thaís)" → atribui ao time `controladoria` (nome da pessoa vem dos membros do time). Avatares = iniciais em círculo `size-6 bg-n-slate-4 text-[10px] font-semibold`.
3. **Cliente** — título "Cliente desde {mm/aaaa}" (ou "Número novo" quando `cliente: false`); linhas `dado` (rótulo `text-n-slate-9` à esquerda, valor à direita): Advogada, Telefone (`font-mono`); bloco compromisso (`bg-n-blue-9/[0.08] … rounded-[10px] px-3.5 py-3`): "Perícia · 07/10, 09:00" em `text-n-blue-11 font-semibold` + notas.
4. **Processos no ADVBOX** `N` — número em `font-mono text-[12.5px] font-medium`, "tipo · fase", "Último andamento: dd/mm · título".
5. Linha "Ver no ADVBOX" com `i-lucide-external-link` → `https://app.advbox.com.br` (nova aba).
6. **Número novo** (`cliente: false`): sem 3/4/5; mostra "Encaminhar ao comercial" (botão tint) — o mesmo fluxo que o `semLead` já tinha.

- [ ] **Step 1: Spec** — `cliente: true` com sugestão → abre a lista e a sugestão vem primeiro com "do processo"; clicar numa pessoa chama a action de atribuir agente com o id; "Controladoria" chama atribuir time; advogada atribuída vê a faixa e "Devolver" chama tirar agente/time; `cliente: false` mostra "Número novo" e "Encaminhar ao comercial".
- [ ] **Step 2: Implementar.**
- [ ] **Step 3: Commit** — `feat(conversa): painel de cliente com Atribuir a… na caixa do escritório`

---

### Task 7: Chegada em tela cheia

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/equipe/AlertaChegada.vue`
- Test: `components/equipe/specs/AlertaChegada.spec.js` (ajustar; manter toque/título piscando/Notification)

Visual (mockup `#chegada`): fundo da tela inteira `bg-n-blue-9/20 backdrop-blur-md` (o `<dialog>` em `w-screen h-screen max-w-none max-h-none bg-transparent grid place-items-center`); cartão `w-[460px] max-w-[calc(100vw-32px)] rounded-[18px] bg-n-background p-7 text-center border border-n-blue-9/40 shadow-[0_24px_80px_rgb(37_99_235/0.35)]`; sino `size-[52px] rounded-full bg-n-blue-9/[0.08] text-n-blue-11` com `animate-pulse` (respeita `motion-reduce:animate-none`); "CLIENTE CHEGOU" `text-[12.5px] font-semibold text-n-blue-11`; nome `text-[28px] font-semibold tracking-tight`; "Atendimento das {hora} · avisado por {criado_por.name} às {hh:mm}" (hora do atendimento só se a chegada tiver — senão só o "avisado por"); recado em caixa âmbar translúcida à esquerda; botões empilhados: cheio "Vou atender agora", borda "Peça pra aguardar uns minutos", texto "Não posso atender"; cada um chama `chegadas.responder(id, <texto do botão>)`; link pequeno "Responder outra coisa" abre o textarea que já existe; rodapé "Sem resposta em {m:ss}, o aviso volta pra {criado_por.name}." com contagem a partir de `created_at + 3 min` (`useNow`). Para quem avisou e viu escalar, mantém o modo "Entendi" atual, no mesmo cartão.

- [ ] **Step 1: Spec** — os 3 botões chamam `responder` com o texto certo; a contagem mostra `2:41` com `created_at` 19 s atrás (fake timers); modo escalado continua com "Entendi".
- [ ] **Step 2: Implementar; rodar; commit** — `feat(equipe): aviso de chegada em tela cheia`

---

### Task 8: Verificação, smoke e PR (sessão principal)

- [ ] eslint (0 erros) nos arquivos tocados; vitest em `routes/dashboard/ramon`, `components/widgets/conversation`, `components-next/message`; `vite build`.
- [ ] Seção "J — Conversa v2" no smoke consolidado (comercial: lista/selo/etiqueta, cabeçalho, bolhas, painel com recolhíveis, ganho com valor; escritório: Recepção atribui com sugestão, advogada vê faixa e devolve, número novo encaminha; chegada em tela cheia nos dois temas).
- [ ] Push (Eduardo), PR, CI verde, squash, deploy **sem migração** (só código), `/app/login` 200.
