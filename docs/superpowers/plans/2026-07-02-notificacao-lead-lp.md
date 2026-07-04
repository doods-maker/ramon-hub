# Notificação de lead novo da Landing Page — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Quando um lead entra pelo endpoint público das LPs (criação OU recaptura), todos os usuários da conta recebem uma notificação nativa no sino do Chatwoot, que ao ser clicada abre o Kanban.

**Architecture:** Novo `notification_type: ramon_lead_created (9)` no enum core (edição mínima e aditiva — as flags de e-mail/push são geradas automaticamente e nascem DESLIGADAS; não vamos expor o tipo em Perfil→Notificações, então e-mail/push nunca disparam e os services que quebrariam com `Lead` nunca rodam). Criação via builder próprio `Ramon::LeadNotificationBuilder` (NÃO usar o `NotificationBuilder` core — suas guardas de `contact.blocked?`/conversation quebram ou bloqueiam com `Lead`), chamado direto pelo `RamonLeadsController` (cobre criação e recaptura). Duas correções pontuais no frontend core: guarda defensiva no `NotificationTable.vue` (linha 111 lança TypeError com primary_actor sem `meta`) e branch de navegação no `NotificationsView.vue` (hard-coded para conversa).

**Tech Stack:** Rails 7 (fork Chatwoot v4.15.1), Vue 3/Vuex, RSpec. Sem ambiente local — CI do PR valida.

## Global Constraints

- Fork merge-safe: arquivos novos em namespace `ramon/`; edições de core mínimas e TODAS registradas em `docs/FORK-PONTOS-DE-REGISTRO.md`. NUNCA tocar `enterprise/` (verificado: zero referências a Notification lá).
- `create(:account)` SEEDA o funil (8 etapas Novo…Fechado/Perdido + benefícios + prioridades) — specs nunca criam etapa com nome já seedado.
- `Lead` tem `default_scope order(:lead_stage_id, :position, :id)` — `.last` NÃO é o mais recente; `DISTINCT`+`pluck` exige `reorder(nil)`.
- Rubocop exige `ENV.fetch` (não `ENV[]`); linha máx 150 chars; RSpec máx 7 expectations por exemplo.
- i18n: backend `config/locales/{en,pt_BR}.yml`; frontend `app/javascript/dashboard/i18n/locale/{en,pt_BR}/*.json` (fork mantém pt_BR junto, diferente da convenção upstream).
- Eventos Vue custom sempre camelCase (não se aplica aqui, mas é regra do fork).
- Commits Conventional Commits, sem referência a Claude no texto. `git add <paths>` específicos, nunca `git add -A`.
- Sem testes locais: cada task termina em commit; a validação roda no CI do PR ao final.

## Estrutura de arquivos

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `app/models/notification.rb` | Modificar (core, 3 pontos) | enum + título + corpo do novo tipo |
| `app/builders/ramon/lead_notification_builder.rb` | Criar | criar 1 Notification por usuário da conta |
| `spec/builders/ramon/lead_notification_builder_spec.rb` | Criar | specs do builder |
| `app/controllers/public/api/v1/ramon_leads_controller.rb` | Modificar (arquivo do fork) | chamar o builder na captação |
| `spec/requests/public/api/v1/ramon_leads_controller_spec.rb` | Modificar | specs de integração |
| `config/locales/en.yml` + `config/locales/pt_BR.yml` | Modificar (core) | título backend |
| `.../notifications/components/NotificationTable.vue` | Modificar (core, 1 linha) | guarda defensiva `meta` |
| `.../notifications/components/NotificationsView.vue` | Modificar (core) | navegação por tipo |
| `.../i18n/locale/{en,pt_BR}/generalSettings.json` | Modificar (core) | rótulo do tipo na lista |
| `docs/FORK-PONTOS-DE-REGISTRO.md` | Modificar | registrar as edições de core |

---

### Task 1: Backend — enum + títulos + `Ramon::LeadNotificationBuilder`

**Files:**
- Modify: `app/models/notification.rb` (3 pontos: ~linha 46, ~99, ~123)
- Modify: `config/locales/en.yml` (~linha 250, bloco `notifications.notification_title`)
- Modify: `config/locales/pt_BR.yml` (bloco equivalente — localizar com `grep -n "notification_title" config/locales/pt_BR.yml`; se o bloco não existir no pt_BR, criar `notifications: notification_title:` aninhado sob a raiz `pt_BR:`)
- Create: `app/builders/ramon/lead_notification_builder.rb`
- Test: `spec/builders/ramon/lead_notification_builder_spec.rb`

**Interfaces:**
- Produces: `Ramon::LeadNotificationBuilder.new(lead: <Lead>).perform` → cria `Notification(notification_type: 'ramon_lead_created', primary_actor: lead)` para cada usuário da conta. Task 2 chama exatamente essa assinatura.

- [ ] **Step 1: Escrever specs que falham**

```ruby
require 'rails_helper'

RSpec.describe Ramon::LeadNotificationBuilder do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:lead) { create(:lead, account: account, name: 'Maria da LP') }

  describe '#perform' do
    it 'cria uma notificação ramon_lead_created para cada usuário da conta' do
      expect { described_class.new(lead: lead).perform }.to change(Notification, :count).by(2)
      expect(Notification.pluck(:user_id)).to match_array([admin.id, agent.id])
    end

    it 'aponta o lead como primary_actor e usa o tipo novo' do
      described_class.new(lead: lead).perform
      notification = Notification.first
      expect(notification.notification_type).to eq('ramon_lead_created')
      expect(notification.primary_actor).to eq(lead)
    end

    it 'monta título com o nome do lead' do
      described_class.new(lead: lead).perform
      expect(Notification.first.push_message_title).to include('Maria da LP')
      expect(Notification.first.push_message_body).to include('Maria da LP')
    end
  end
end
```

Nota: confira em `spec/factories/` como as factories `:lead` e `:user` do fork funcionam (a `:user` do Chatwoot aceita `account:` e `role:` via transient — ver uso em outras specs, ex. `spec/builders/notification_builder_spec.rb`). Ajuste a sintaxe da factory se necessário, mantendo as asserções.

- [ ] **Step 2: Rodar para ver falhar** — sem ambiente local, valide por leitura dupla (o CI roda ao final). Confirme que `ramon_lead_created` ainda não existe: `grep -rn "ramon_lead_created" app/ config/` → vazio.

- [ ] **Step 3: Editar `app/models/notification.rb`**

(a) Enum (~linha 46), adicionar após `sla_missed_resolution: 8`:

```ruby
    sla_missed_resolution: 8,
    ramon_lead_created: 9
```

(b) `push_message_title` — adicionar entrada no hash `notification_title_map`:

```ruby
      'sla_missed_resolution' => 'notifications.notification_title.sla_missed_resolution',
      'ramon_lead_created' => 'notifications.notification_title.ramon_lead_created'
```

e um branch ANTES do `else` final (o `else` chama `primary_actor.display_id`, que `Lead` não tem):

```ruby
    elsif notification_type == 'ramon_lead_created'
      I18n.t(i18n_key, name: primary_actor.name)
    else
```

(c) `push_message_body` — o payload realtime do websocket usa `push_message_body` como título (TODO antigo do core em `primary_actor_data`, linha ~204); sem entrada aqui a notificação chega VAZIA em tempo real. Adicionar `when` antes do `else`:

```ruby
    when 'ramon_lead_created'
      I18n.t('notifications.notification_title.ramon_lead_created', name: primary_actor.name)
    else
```

- [ ] **Step 4: i18n backend**

`config/locales/en.yml`, dentro de `notifications: notification_title:` (após `sla_missed_resolution`):

```yaml
      ramon_lead_created: 'New lead from landing page: %{name}'
```

`config/locales/pt_BR.yml`, mesmo caminho de chaves:

```yaml
      ramon_lead_created: 'Novo lead da landing page: %{name}'
```

- [ ] **Step 5: Criar o builder** — `app/builders/ramon/lead_notification_builder.rb`:

```ruby
class Ramon::LeadNotificationBuilder
  # Builder próprio (não usar o NotificationBuilder core): as guardas de
  # contact.blocked?/conversation de lá assumem primary_actor Conversation.
  pattr_initialize [:lead!]

  def perform
    lead.account.users.distinct.find_each do |user|
      user.notifications.create!(
        notification_type: 'ramon_lead_created',
        account: lead.account,
        primary_actor: lead
      )
    end
  end
end
```

Nota: `pattr_initialize` (gem attr_extras) é o padrão dos builders do core — confirme a sintaxe em `app/builders/notification_builder.rb` e siga-a. `account.users` já é a união de agents+administrators via `account_users`.

- [ ] **Step 6: Commit**

```bash
git add app/models/notification.rb config/locales/en.yml config/locales/pt_BR.yml app/builders/ramon/lead_notification_builder.rb spec/builders/ramon/lead_notification_builder_spec.rb
git commit -m "feat(ramon): notificação nativa ramon_lead_created com builder próprio"
```

---

### Task 2: Controller — notificar na captação (criação e recaptura)

**Files:**
- Modify: `app/controllers/public/api/v1/ramon_leads_controller.rb` (~linhas 20-29, método `register_lead`)
- Test: `spec/requests/public/api/v1/ramon_leads_controller_spec.rb` (adicionar contexto)

**Interfaces:**
- Consumes: `Ramon::LeadNotificationBuilder.new(lead:).perform` (Task 1).

- [ ] **Step 1: Specs que falham** — adicionar ao spec de request existente (siga o setup de token/conta que já está lá — usa `with_modified_env` com `RAMON_LEAD_CAPTURE_TOKEN`/`RAMON_LEAD_CAPTURE_ACCOUNT_ID`):

```ruby
    it 'notifica os usuários da conta quando cria lead novo' do
      create(:user, account: account, role: :administrator)
      expect { post_captura(nome: 'Maria', telefone: '47999990000') }
        .to change(Notification.where(notification_type: 'ramon_lead_created'), :count).by(1)
    end

    it 'notifica também na recaptura de lead aberto existente' do
      create(:user, account: account, role: :administrator)
      post_captura(nome: 'Maria', telefone: '47999990000')
      expect { post_captura(nome: 'Maria', telefone: '47999990000') }
        .to change(Notification.where(notification_type: 'ramon_lead_created'), :count).by(1)
    end
```

Adapte `post_captura` ao helper/estilo REAL do spec existente (leia o arquivo primeiro; ele já tem exemplos de POST válido — reuse o mesmo caminho e params). Máx 7 expectations por exemplo.

- [ ] **Step 2: Implementar** — em `register_lead`, uma linha antes do retorno:

```ruby
  def register_lead(contact, phone)
    lead = open_lead_for(contact)
    if lead
      lead.lead_notes.create!(account: account, body: recapture_note_body)
    else
      lead = create_lead(contact, phone)
      lead.lead_notes.create!(account: account, body: params[:mensagem].to_s.truncate(1000)) if params[:mensagem].present?
    end
    Ramon::LeadNotificationBuilder.new(lead: lead).perform
    lead
  end
```

(Preserve o corpo atual EXATO do método — o trecho acima reflete o código de hoje; só a linha do builder é nova.)

- [ ] **Step 3: Commit**

```bash
git add app/controllers/public/api/v1/ramon_leads_controller.rb spec/requests/public/api/v1/ramon_leads_controller_spec.rb
git commit -m "feat(ramon): captação pela LP notifica usuários da conta"
```

---

### Task 3: Frontend — guarda defensiva, navegação e rótulos

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/notifications/components/NotificationTable.vue` (linha 111)
- Modify: `app/javascript/dashboard/routes/dashboard/notifications/components/NotificationsView.vue` (método `openConversation`, linhas 30-51)
- Modify: `app/javascript/dashboard/i18n/locale/en/generalSettings.json` (~linha 170, bloco `NOTIFICATIONS_PAGE.TYPE_LABEL`)
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/generalSettings.json` (bloco equivalente)

**Interfaces:**
- Consumes: `notification_type === 'ramon_lead_created'` (payload REST e websocket, Task 1). Rota nomeada `kanban_board` (já existe — registrada no fork, visível em `Sidebar.vue:441` como `accountScopedRoute('kanban_board')`).

- [ ] **Step 1: Guarda no `NotificationTable.vue`** — linha 111, trocar:

```html
              v-if="notificationItem.primary_actor.meta.assignee"
```

por:

```html
              v-if="notificationItem.primary_actor.meta?.assignee"
```

(Sem isso, UMA notificação com primary_actor `Lead` — que não tem `meta` — lança TypeError e quebra a lista INTEIRA.)

- [ ] **Step 2: Navegação no `NotificationsView.vue`** — no método `openConversation`, depois do dispatch de `notifications/read` e antes do `this.$router.push` atual, inserir:

```js
      if (notificationType === 'ramon_lead_created') {
        this.$router.push({
          name: 'kanban_board',
          params: { accountId: this.accountId },
        });
        return;
      }
```

(O push atual é hard-coded para `/conversations/:id`; para um Lead isso abriria uma conversa errada por coincidência de ID.)

- [ ] **Step 3: Rótulos** — `en/generalSettings.json`, dentro de `"TYPE_LABEL"` (vírgula na linha anterior):

```json
      "sla_missed_resolution": "SLA Missed",
      "ramon_lead_created": "New lead (LP)"
```

`pt_BR/generalSettings.json`, mesmo bloco (localizar `TYPE_LABEL`):

```json
      "ramon_lead_created": "Lead novo (LP)"
```

- [ ] **Step 4: Lint** — `pnpm eslint app/javascript/dashboard/routes/dashboard/notifications/components/NotificationTable.vue app/javascript/dashboard/routes/dashboard/notifications/components/NotificationsView.vue` (se pnpm indisponível, leitura dupla; CI valida).

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/notifications/components/NotificationTable.vue app/javascript/dashboard/routes/dashboard/notifications/components/NotificationsView.vue app/javascript/dashboard/i18n/locale/en/generalSettings.json app/javascript/dashboard/i18n/locale/pt_BR/generalSettings.json
git commit -m "feat(ramon): sino renderiza e navega notificação de lead da LP"
```

---

### Task 4: Registrar pontos de fork

**Files:**
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md`

- [ ] **Step 1:** Adicionar seção (siga o formato existente do arquivo) listando as edições de core desta fatia: `app/models/notification.rb` (enum +`ramon_lead_created: 9`, título, corpo), `config/locales/{en,pt_BR}.yml`, `NotificationTable.vue` (guarda `meta?.`), `NotificationsView.vue` (branch de navegação), `i18n/locale/{en,pt_BR}/generalSettings.json` (TYPE_LABEL). Registrar também a decisão: tipo NÃO exposto em Perfil→Notificações (`settings/profile/constants.js` intocado de propósito — e-mail/push quebrariam com `Lead` e devem permanecer indisponíveis para este tipo).

- [ ] **Step 2: Commit**

```bash
git add docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "docs: registra pontos de fork da notificação de lead da LP"
```

---

## Fora de escopo (explícito)

- E-mail/push para o tipo novo (quebrariam com `Lead`; tipo fica fora de Perfil→Notificações de propósito).
- `PRIMARY_ACTORS` allowlist do model (só afeta `read_all` filtrado; dispensável no MVP).
- Badge custom no rail, som de notificação, deep-link abrindo a gaveta do lead no Kanban (calibrar depois pelo uso).
- Bug pré-existente do `RemoveDuplicateNotificationJob` (dedupe por `primary_actor_id` sem checar type) — risco teórico monitorado, não bloqueante.

## Verificação final (pós-CI, no deploy)

Smoke em produção após merge+deploy autorizado: submeter o form de uma LP (ou POST com honeypot NÃO preenchido e telefone de teste) → sino mostra "Novo lead da landing page: <nome>" em tempo real → clique navega ao Kanban. Remover o lead de teste depois.
