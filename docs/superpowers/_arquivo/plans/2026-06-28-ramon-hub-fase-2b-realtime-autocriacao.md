# Fase 2B — Realtime (ActionCable) + Auto-criação de Lead — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Quando um `Lead` é criado/atualizado, espelhar em tempo real para todos os clientes (board atualiza sozinho); e auto-criar um `Lead` nativo quando chega conversa nova numa inbox habilitada, com dedup por contato.

**Architecture:** Reusa a infra ActionCable do Chatwoot (Wisper roteia evento→método do listener por nome). O `Lead` dispara `lead.created`/`lead.updated` nos callbacks; `ActionCableListener` faz broadcast account-wide com `lead.push_event_data` (já existe da 2A); o front (`actionCable.js`) recebe e faz `dispatch('leads/upsert')` (action já existe da 2A). Auto-criação = novo `RamonLeadListener` inscrito em `conversation_created` no AsyncDispatcher, gated por uma flag `auto_create_lead` na inbox.

**Tech Stack:** Rails (RSpec) + ActionCable/Wisper + Vue/Vuex. Verificação = **CI no PR** (sem ambiente de teste local: nem Ruby/pnpm/Postgres). Feature branch → PR pro `ramon` → `run_foss_spec` roda rspec+vitest.

## Global Constraints

- Chatwoot v4.15.1 fork (`ramon-hub`). Fork-safe: arquivos novos preferencialmente; tocar core só nos pontos de registro; nunca `enterprise/`. Registrar toques de core em `docs/FORK-PONTOS-DE-REGISTRO.md`.
- **Sem teste local** → implementers escrevem código + specs e commitam; NÃO rodam rspec/migrations; CI valida. Não fabricar saída de teste.
- **CI carrega schema via `db:schema:load`** → toda migration nova EXIGE `db/schema.rb` regenerado e commitado (senão o suite quebra). Regeneração roda num ambiente Ruby+PG (controller faz via container scratch na VPS, como na 2A) — marcada como passo do controller, não do implementer.
- **Decisões travadas (Eduardo):** dedup **por contato** (1 lead/pessoa); contato que já tem lead numa conversa nova → **re-aponta** `conversation_id` (dispara `lead.updated`); auto-criação **gated por inbox** (flag `auto_create_lead`, default `false` = nada auto-cria até habilitar); conversa **sem contato → pula**; payload realtime = `push_event_data` (8 campos, suficiente pro board); nome do card = `contact.name` com fallback `phone_number`/`identifier`.
- **Reutilizar da 2A (NÃO recriar):** `Lead#push_event_data` (`app/models/lead.rb`), action `leads/upsert` (`store/modules/leads.js`), `account.leads`, `account.lead_stages`, `Leads::SeedDefaultConfigService` (etapa 'Novo' = menor `position`).
- Toggle UI da flag por inbox = **fora de escopo (vai pra 2D)**. Na 2B a flag default `false`; habilitar por inbox é ação de backend do Eduardo.

---

## File Structure

**Backend:**
- `db/migrate/20260628000002_add_auto_create_lead_to_inboxes.rb` — coluna boolean [CORE table].
- `lib/events/types.rb` — `LEAD_CREATED`/`LEAD_UPDATED` [CORE, aditivo].
- `app/models/lead.rb` — callbacks de dispatch [edit].
- `app/listeners/action_cable_listener.rb` — `lead_created`/`lead_updated` [CORE, aditivo].
- `app/listeners/ramon_lead_listener.rb` — auto-criação [FORK, novo].
- `app/dispatchers/async_dispatcher.rb` — registrar o listener novo [CORE, 1 linha].
- `db/schema.rb` — regenerado (controller).

**Frontend:**
- `app/javascript/dashboard/helper/actionCable.js` — handler `lead.created`/`lead.updated` [CORE, aditivo].

**Specs:** `spec/models/lead_spec.rb` (append), `spec/listeners/action_cable_listener_spec.rb` (append/novo), `spec/listeners/ramon_lead_listener_spec.rb` (novo).

---

## Task 1: Migration — flag `auto_create_lead` na inbox

**Files:**
- Create: `db/migrate/20260628000002_add_auto_create_lead_to_inboxes.rb`
- Test: `spec/models/inbox_spec.rb` (append, opcional)

**Interfaces:**
- Produces: coluna `inboxes.auto_create_lead` (boolean, default false, not null). Lida pelo `RamonLeadListener` (Task 5).

- [ ] **Step 1: Escrever a migration**

```ruby
class AddAutoCreateLeadToInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :inboxes, :auto_create_lead, :boolean, null: false, default: false
  end
end
```

- [ ] **Step 2: (não rodar) — sem Ruby local**

A migration NÃO é executada aqui. O `db/schema.rb` é regenerado pelo controller (container scratch na VPS) antes do PR. Não editar `schema.rb` à mão.

- [ ] **Step 3: Commit**

```bash
git add db/migrate/20260628000002_add_auto_create_lead_to_inboxes.rb
git commit -m "ramon(fase2b): flag auto_create_lead na inbox"
```

---

## Task 2: Constantes de evento

**Files:**
- Modify: `lib/events/types.rb` [CORE, aditivo]

**Interfaces:**
- Produces: `Events::Types::LEAD_CREATED` (`'lead.created'`), `LEAD_UPDATED` (`'lead.updated'`). O nome do método do listener é derivado por `Events::Base#method_name` (`tr('.', '_')`) → `lead_created`/`lead_updated`.

- [ ] **Step 1: Adicionar as constantes**

Em `lib/events/types.rb`, dentro do `module Events; module Types`, adicionar um bloco (perto do bloco de conversa, ~linha 35):
```ruby
    # Ramon — leads
    LEAD_CREATED = 'lead.created'.freeze
    LEAD_UPDATED = 'lead.updated'.freeze
```
> Conferir o estilo das constantes vizinhas (com/sem `.freeze`) e casar.

- [ ] **Step 2: Registrar ponto de fork + commit**

Atualizar `docs/FORK-PONTOS-DE-REGISTRO.md` (lib/events/types.rb: LEAD_*).
```bash
git add lib/events/types.rb docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "ramon(fase2b): eventos LEAD_CREATED/LEAD_UPDATED"
```

---

## Task 3: Callbacks de dispatch no model `Lead`

**Files:**
- Modify: `app/models/lead.rb`
- Test: `spec/models/lead_spec.rb` (append)

**Interfaces:**
- Consumes: `Events::Types::LEAD_CREATED/LEAD_UPDATED` (Task 2).
- Produces: `Lead` dispara o evento no commit de create/update via `Rails.configuration.dispatcher.dispatch`.

- [ ] **Step 1: Spec (append em `spec/models/lead_spec.rb`)**

```ruby
  it 'dispara LEAD_CREATED ao criar' do
    stage = create(:lead_stage, account: account, name: 'Etapa Disp')
    expect(Rails.configuration.dispatcher).to receive(:dispatch)
      .with(Events::Types::LEAD_CREATED, anything, hash_including(:lead))
    create(:lead, account: account, lead_stage: stage)
  end

  it 'dispara LEAD_UPDATED ao atualizar' do
    stage = create(:lead_stage, account: account, name: 'Etapa Disp2')
    lead = create(:lead, account: account, lead_stage: stage)
    expect(Rails.configuration.dispatcher).to receive(:dispatch)
      .with(Events::Types::LEAD_UPDATED, anything, hash_including(:lead))
    lead.update!(name: 'Novo Nome')
  end
```
> Nomes de etapa custom (não-semente) por causa do auto-seed da conta (lição da 2A).

- [ ] **Step 2: Implementar no `app/models/lead.rb`**

Adicionar (após o `default_scope`, antes do `push_event_data`):
```ruby
  after_create_commit :dispatch_create_event
  after_update_commit :dispatch_update_event
```
E os métodos privados (criar seção `private` se não houver):
```ruby
  private

  def dispatch_create_event
    Rails.configuration.dispatcher.dispatch(Events::Types::LEAD_CREATED, Time.zone.now, lead: self)
  end

  def dispatch_update_event
    Rails.configuration.dispatcher.dispatch(Events::Types::LEAD_UPDATED, Time.zone.now, lead: self)
  end
```
> `push_event_data` é público; mantê-lo acima do `private`.

- [ ] **Step 3: Commit**

```bash
git add app/models/lead.rb spec/models/lead_spec.rb
git commit -m "ramon(fase2b): Lead dispara eventos de create/update"
```

---

## Task 4: `ActionCableListener` — broadcast realtime

**Files:**
- Modify: `app/listeners/action_cable_listener.rb` [CORE, aditivo]
- Test: `spec/listeners/action_cable_listener_spec.rb` (append ou novo)

**Interfaces:**
- Consumes: evento com `event.data[:lead]`.
- Produces: enfileira `ActionCableBroadcastJob` com tokens da conta e payload `lead.push_event_data` (+ `account_id` injetado pelo `broadcast`). Eventos `lead.created`/`lead.updated`.

- [ ] **Step 1: Spec (append em `spec/listeners/action_cable_listener_spec.rb`)**

```ruby
  describe '#lead_created' do
    let(:lead) { create(:lead, account: account, lead_stage: create(:lead_stage, account: account, name: 'EtapaAC')) }
    let(:event) { Events::Base.new('lead.created', Time.zone.now, lead: lead) }

    it 'enfileira broadcast com push_event_data' do
      expect { listener.lead_created(event) }
        .to have_enqueued_job(ActionCableBroadcastJob)
    end
  end
```
> Conferir como o spec existente desse arquivo monta `listener`/`account`/`event` e espelhar (provável `described_class.instance`).

- [ ] **Step 2: Implementar os métodos**

Em `app/listeners/action_cable_listener.rb`, adicionar (perto de `contact_created`, que usa token account-wide):
```ruby
  def lead_created(event)
    lead = event.data[:lead]
    account = lead.account
    broadcast(account, [account_token(account)], LEAD_CREATED, lead.push_event_data)
  end

  def lead_updated(event)
    lead = event.data[:lead]
    account = lead.account
    broadcast(account, [account_token(account)], LEAD_UPDATED, lead.push_event_data)
  end
```
> `account_token`, `broadcast` e o uso de `LEAD_CREATED`/`LEAD_UPDATED` (constantes incluídas via `Events::Types` no topo do arquivo, como as outras) — conferir que o arquivo já referencia as constantes sem prefixo (ex.: `CONTACT_CREATED`); se sim, `LEAD_CREATED` funciona igual.

- [ ] **Step 3: Registrar fork + commit**

```bash
git add app/listeners/action_cable_listener.rb spec/listeners/action_cable_listener_spec.rb docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "ramon(fase2b): ActionCableListener broadcast de leads"
```

---

## Task 5: `RamonLeadListener` — auto-criação na conversa

**Files:**
- Create: `app/listeners/ramon_lead_listener.rb` [FORK, novo]
- Test: `spec/listeners/ramon_lead_listener_spec.rb` (novo)

**Interfaces:**
- Consumes: evento `conversation_created` (via Wisper); `conversation.inbox.auto_create_lead?` (Task 1), `account.leads`, `account.lead_stages`.
- Produces: cria/atualiza um `Lead` — que por sua vez dispara `lead.created`/`lead.updated` (Task 3) fechando o ciclo realtime.

- [ ] **Step 1: Spec (`spec/listeners/ramon_lead_listener_spec.rb`)**

```ruby
require 'rails_helper'

RSpec.describe RamonLeadListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, auto_create_lead: true) }
  let(:contact) { create(:contact, account: account, name: 'Maria') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:event) { Events::Base.new('conversation.created', Time.zone.now, conversation: conversation) }

  it 'cria um lead na etapa Novo linkado ao contato/conversa' do
    expect { listener.conversation_created(event) }.to change { account.leads.count }.by(1)
    lead = account.leads.last
    expect(lead.contact_id).to eq(contact.id)
    expect(lead.conversation_id).to eq(conversation.id)
    expect(lead.lead_stage).to eq(account.lead_stages.find_by(name: 'Novo'))
  end

  it 'não cria se a inbox não tem auto_create_lead' do
    inbox.update!(auto_create_lead: false)
    expect { listener.conversation_created(event) }.not_to change { account.leads.count }
  end

  it 're-aponta a conversa do lead existente (dedup por contato)' do
    first = create(:conversation, account: account, inbox: inbox, contact: contact)
    listener.conversation_created(Events::Base.new('conversation.created', Time.zone.now, conversation: first))
    expect { listener.conversation_created(event) }.not_to change { account.leads.count }
    expect(account.leads.last.conversation_id).to eq(conversation.id)
  end
end
```
> Conferir a factory `:conversation`/`:inbox`/`:contact` do Chatwoot (provavelmente exigem associações). Ajustar criação conforme as factories reais.

- [ ] **Step 2: Implementar o listener**

```ruby
class RamonLeadListener < BaseListener
  def conversation_created(event)
    conversation, account = extract_conversation_and_account(event)
    return unless conversation.inbox&.auto_create_lead?

    contact = conversation.contact
    return if contact.blank?

    lead = account.leads.find_by(contact_id: contact.id)
    if lead
      lead.update!(conversation_id: conversation.id)
    else
      account.leads.create!(
        name: contact.name.presence || contact.phone_number || contact.identifier,
        lead_stage: account.lead_stages.order(:position).first,
        contact_id: contact.id,
        conversation_id: conversation.id
      )
    end
  end
end
```
> `extract_conversation_and_account` vem de `BaseListener` (`base_listener.rb`). Confirmar a assinatura.

- [ ] **Step 3: Commit**

```bash
git add app/listeners/ramon_lead_listener.rb spec/listeners/ramon_lead_listener_spec.rb
git commit -m "ramon(fase2b): RamonLeadListener auto-cria lead na conversa"
```

---

## Task 6: Registrar o listener no AsyncDispatcher

**Files:**
- Modify: `app/dispatchers/async_dispatcher.rb` [CORE, 1 linha]

**Interfaces:**
- Consumes: `RamonLeadListener` (Task 5).
- Produces: o listener passa a receber `conversation_created` de forma assíncrona (não bloqueia a criação da conversa).

- [ ] **Step 1: Adicionar à lista de listeners**

Em `app/dispatchers/async_dispatcher.rb`, no array retornado por `listeners` (~linha 11-24), adicionar:
```ruby
      RamonLeadListener.instance,
```
> Conferir a forma exata dos itens (todos `XListener.instance`) e manter vírgulas.

- [ ] **Step 2: Registrar fork + commit**

```bash
git add app/dispatchers/async_dispatcher.rb docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "ramon(fase2b): registra RamonLeadListener no async dispatcher"
```

---

## Task 7: Front — handler ActionCable → `leads/upsert`

**Files:**
- Modify: `app/javascript/dashboard/helper/actionCable.js` [CORE, aditivo]

**Interfaces:**
- Consumes: eventos `lead.created`/`lead.updated` com payload `push_event_data` + `account_id`.
- Produces: `dispatch('leads/upsert', data)` → o board (Funil/Kanban) atualiza ao vivo.

- [ ] **Step 1: Adicionar ao mapa `this.events`**

No objeto `this.events` (`~:28-57`), adicionar:
```js
      'lead.created': this.onLeadUpsert,
      'lead.updated': this.onLeadUpsert,
```

- [ ] **Step 2: Adicionar o handler**

Junto aos outros handlers (ex.: perto de `onContactUpdate`):
```js
  onLeadUpsert = data => {
    this.app.$store.dispatch('leads/upsert', data);
  };
```
> O filtro multi-conta `isAValidEvent` (`~:70-72`) já compara `account_id`; o `broadcast` do backend injeta `account_id` no payload, então não precisa de tratamento extra.

- [ ] **Step 3: Registrar fork + commit**

```bash
git add app/javascript/dashboard/helper/actionCable.js docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "ramon(fase2b): front recebe leads via ActionCable e faz upsert"
```

---

## Self-Review

**Spec coverage (vs decisões travadas):**
- Realtime de create/update → Tasks 2,3,4,7 (evento→callback→broadcast→upsert no front). ✓
- Auto-criação gated por inbox → Tasks 1,5,6. ✓
- Dedup por contato + re-aponta conversa → Task 5 (`find_by(contact_id:)` + `update!(conversation_id:)`). ✓
- Conversa sem contato pula → Task 5 (`return if contact.blank?`). ✓
- Nome com fallback → Task 5 (`name.presence || phone_number || identifier`). ✓
- Etapa inicial 'Novo' → Task 5 (`lead_stages.order(:position).first`). ✓
- Default seguro (nada auto-cria) → Task 1 (`default: false`). ✓

**Fora de escopo (proposital):** toggle UI da flag por inbox (→ 2D); espelho etapa↔label (→ 2C); ampliar `push_event_data` (só se o board precisar de sdr/closer/custom em tempo real — hoje não).

**Pontos a confirmar na execução (CI valida):**
1. Estilo das constantes em `lib/events/types.rb` (`.freeze`?) e se o módulo é `Events::Types`.
2. Como o spec existente de `action_cable_listener_spec.rb` monta listener/account/event.
3. Assinatura de `extract_conversation_and_action`/`extract_conversation_and_account` em `BaseListener`.
4. Factories `:conversation`/`:inbox`/`:contact` (associações exigidas).
5. Forma exata do array de `listeners` no `async_dispatcher.rb`.
6. Que o `action_cable_listener.rb` referencia constantes de evento sem prefixo (senão usar `Events::Types::LEAD_CREATED`).

**Passo do controller (não-implementer):** após as tasks, regenerar `db/schema.rb` (container scratch na VPS, como na 2A) por causa da Task 1, e commitar — senão o CI quebra no `db:schema:load`.

**Placeholder scan:** sem TODO/TBD; cada passo tem código ou comando. As notas `>` são confirmações de caminho no fork real (não placeholders de implementação).
