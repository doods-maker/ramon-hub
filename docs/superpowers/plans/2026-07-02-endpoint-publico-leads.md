# Endpoint Público de Leads (LPs → Funil Kanban) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lead enviado pelo formulário das landing pages nasce direto no funil Kanban nativo do fork (etapa de menor `position`, "Novo"), via `POST /public/api/v1/ramon_leads/:capture_token`.

**Architecture:** Controller público novo em `app/controllers/public/api/v1/` herdando de `PublicController` (sem sessão, CSRF off), autenticado por token de captação em ENV comparado em tempo constante. Contact find-or-create por telefone escopado na conta; dedup de lead ABERTO (etapa não won/lost) vira nota no lead existente. Rate limit por IP no Rack::Attack.

**Tech Stack:** Rails (fork Chatwoot v4.15.1), RSpec request specs, FactoryBot, Rack::Attack.

## Global Constraints

- **Sem teste local — PR/CI valida** (lição registrada do fork). Os passos "rodar teste" significam: commit → push → CI. Nunca declarar verde sem CI verde.
- **Deploy em prod SÓ com OK explícito do Eduardo.** Este plano termina no PR.
- Regra de ouro do fork: **adicionar, quase nunca editar core; nunca tocar `enterprise/`**. Únicos arquivos core editados aqui: `config/routes.rb` (1 rota) e `config/initializers/rack_attack.rb` (1 throttle). Registrar tudo em `docs/FORK-PONTOS-DE-REGISTRO.md`.
- Payload que as LPs JÁ enviam (código pronto em `landing-pages/src/lib/enviarLead.ts`): `{nome, telefone (dígitos E.164 sem "+", 12–13 dígitos), campanha, mensagem?, website? (honeypot)}`.
- Contact do Chatwoot guarda `phone_number` com prefixo `+` (E.164). O endpoint converte `554899…` → `+554899…`.
- `Current.user` é `nil` no contexto público — o callback `record_created_activity` do `Lead` grava a activity `created` com `user: nil` (aceito, `user` é optional). Não tentar setar autor.
- Working tree atual do repo está na branch `feat/dock-toggle` com 4 arquivos do kanban modificados (trabalho em andamento de outra frente). **NÃO tocar nesses arquivos; trabalhar em worktree isolado** (skill superpowers:using-git-worktrees).

---

### Task 0: Worktree e branch

**Files:** nenhum (setup).

- [ ] **Step 1: Confirmar a branch base do fork**

Run: `git -C <repo> remote show origin | grep "HEAD branch"`
Esperado: a branch default (histórico do projeto indica `ramon` como base do fork; PRs anteriores foram mesclados nela — confirmar no output).

- [ ] **Step 2: Criar worktree isolado a partir da base**

```bash
git -C <repo> worktree add ../ramon-hub-wt-leads -b feat/ramon-public-leads origin/<base>
```

Todo o trabalho das tasks seguintes acontece dentro de `ramon-hub-wt-leads`.

---

### Task 1: Rota + Controller + Request Spec (TDD)

**Files:**
- Modify: `config/routes.rb` (dentro do `namespace :public > :api > :v1`, linha ~606, ao lado de `resources :csat_survey`)
- Create: `app/controllers/public/api/v1/ramon_leads_controller.rb`
- Test: `spec/requests/public/api/v1/ramon_leads_controller_spec.rb`

**Interfaces:**
- Consumes: `Lead`, `LeadStage`, `LeadNote` (models existentes do fork); `PublicController`; factories `:lead`, `:lead_stage`, `:contact`, `:account`.
- Produces: rota `POST /public/api/v1/ramon_leads/:capture_token` → controller `Public::Api::V1::RamonLeadsController#create`. Config por ENV: `RAMON_LEAD_CAPTURE_TOKEN` (segredo da URL) e `RAMON_LEAD_CAPTURE_ACCOUNT_ID` (conta destino). Ambos ausentes/errados → 401.

- [ ] **Step 1: Escrever a request spec (falhando)**

`spec/requests/public/api/v1/ramon_leads_controller_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Public Ramon Leads API', type: :request do
  let(:account) { create(:account) }
  let!(:stage_novo) { create(:lead_stage, account: account, name: 'Novo', position: 0) }
  let!(:stage_reuniao) { create(:lead_stage, account: account, name: 'Reunião', position: 1) }
  let(:token) { 'tok-secreto' }
  let(:payload) { { nome: 'Maria da Silva', telefone: '5548999887766', campanha: 'auxilio-acidente', mensagem: 'Sofri acidente em 2023' } }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('RAMON_LEAD_CAPTURE_TOKEN').and_return(token)
    allow(ENV).to receive(:[]).with('RAMON_LEAD_CAPTURE_ACCOUNT_ID').and_return(account.id.to_s)
  end

  describe 'POST /public/api/v1/ramon_leads/:capture_token' do
    it 'cria contact + lead na primeira etapa por position, com source e nota da mensagem' do
      expect do
        post "/public/api/v1/ramon_leads/#{token}", params: payload, as: :json
      end.to change(Lead, :count).by(1).and change(Contact, :count).by(1)

      expect(response).to have_http_status(:created)
      lead = Lead.last
      expect(lead.account).to eq account
      expect(lead.lead_stage).to eq stage_novo
      expect(lead.name).to eq 'Maria da Silva'
      expect(lead.source).to eq 'auxilio-acidente'
      expect(lead.contact.phone_number).to eq '+5548999887766'
      expect(lead.lead_notes.pluck(:body)).to include('Sofri acidente em 2023')
    end

    it 'honeypot preenchido devolve 200 sem criar nada' do
      expect do
        post "/public/api/v1/ramon_leads/#{token}", params: payload.merge(website: 'http://spam'), as: :json
      end.not_to change(Lead, :count)
      expect(response).to have_http_status(:ok)
    end

    it 'token errado devolve 401' do
      post '/public/api/v1/ramon_leads/token-errado', params: payload, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(Lead.count).to eq 0
    end

    it 'token não configurado no servidor devolve 401' do
      allow(ENV).to receive(:[]).with('RAMON_LEAD_CAPTURE_TOKEN').and_return(nil)
      post "/public/api/v1/ramon_leads/#{token}", params: payload, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'telefone inválido devolve 422' do
      post "/public/api/v1/ramon_leads/#{token}", params: payload.merge(telefone: '999'), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Lead.count).to eq 0
    end

    it 'telefone repetido reusa o Contact e, com lead ABERTO existente, cria nota em vez de duplicar' do
      contact = create(:contact, account: account, phone_number: '+5548999887766')
      lead = create(:lead, account: account, lead_stage: stage_reuniao, contact: contact)

      post "/public/api/v1/ramon_leads/#{token}", params: payload, as: :json

      expect(Lead.count).to eq 1
      expect(Contact.count).to eq 1
      expect(response).to have_http_status(:created)
      expect(lead.reload.lead_notes.pluck(:body).join).to include('auxilio-acidente')
    end

    it 'lead do contato em etapa ganha/perdida NÃO bloqueia lead novo' do
      stage_ganho = create(:lead_stage, account: account, name: 'Ganho', position: 2, is_won: true)
      contact = create(:contact, account: account, phone_number: '+5548999887766')
      create(:lead, account: account, lead_stage: stage_ganho, contact: contact)

      expect do
        post "/public/api/v1/ramon_leads/#{token}", params: payload, as: :json
      end.to change(Lead, :count).by(1)
      expect(Lead.last.lead_stage).to eq stage_novo
    end
  end
end
```

- [ ] **Step 2: Rodar a spec para vê-la falhar (routing error)**

Run local se disponível: `bundle exec rspec spec/requests/public/api/v1/ramon_leads_controller_spec.rb`
Sem ambiente local: commit + push e deixar o CI acusar a falha esperada (`No route matches`). O commit do step 2 pode ser combinado com o step 5 num push só — mas a spec DEVE ser escrita antes da implementação.

- [ ] **Step 3: Adicionar a rota**

Em `config/routes.rb`, dentro de `namespace :public > :api > :v1`, logo após `resources :csat_survey, only: [:show, :update]`:

```ruby
        # Ramon — captação de leads das landing pages
        post 'ramon_leads/:capture_token', to: 'ramon_leads#create'
```

- [ ] **Step 4: Implementar o controller**

`app/controllers/public/api/v1/ramon_leads_controller.rb`:

```ruby
class Public::Api::V1::RamonLeadsController < PublicController
  before_action :verify_capture_token

  def create
    return head :ok if params[:website].present?

    phone = normalized_phone
    return head :unprocessable_entity if phone.blank?

    contact = find_or_create_contact(phone)
    lead = open_lead_for(contact)
    if lead
      lead.lead_notes.create!(account: account, body: recapture_note_body)
    else
      lead = create_lead(contact, phone)
      lead.lead_notes.create!(account: account, body: params[:mensagem].to_s.truncate(1000)) if params[:mensagem].present?
    end

    head :created
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_entity
  end

  private

  def verify_capture_token
    expected = ENV['RAMON_LEAD_CAPTURE_TOKEN']
    return head :unauthorized if expected.blank? || account.blank?
    return if ActiveSupport::SecurityUtils.secure_compare(params[:capture_token].to_s, expected)

    head :unauthorized
  end

  def account
    @account ||= Account.find_by(id: ENV['RAMON_LEAD_CAPTURE_ACCOUNT_ID'])
  end

  def normalized_phone
    digits = params[:telefone].to_s.gsub(/\D/, '')
    return unless [12, 13].include?(digits.length) && digits.start_with?('55')

    "+#{digits}"
  end

  def find_or_create_contact(phone)
    account.contacts.find_by(phone_number: phone) ||
      account.contacts.create!(name: params[:nome].to_s.strip.presence || phone, phone_number: phone)
  end

  def open_lead_for(contact)
    account.leads
           .joins(:lead_stage)
           .where(contact_id: contact.id, lead_stages: { is_won: false, is_lost: false })
           .first
  end

  def create_lead(contact, phone)
    account.leads.create!(
      name: params[:nome].to_s.strip.presence || phone,
      lead_stage: account.lead_stages.order(:position).first,
      contact_id: contact.id,
      source: params[:campanha].to_s.presence
    )
  end

  def recapture_note_body
    body = "Novo envio pela landing page (campanha: #{params[:campanha].presence || 'desconhecida'})."
    body += " Mensagem: #{params[:mensagem]}" if params[:mensagem].present?
    body.truncate(1000)
  end
end
```

Pontos de desenho (não mudar sem motivo):
- Token via ENV + `ActiveSupport::SecurityUtils.secure_compare` — mesmo padrão dos webhooks TikTok/Shopify do core. Não existe padrão Ramon prévio; `InstallationConfig` foi descartado por não ter precedente público no fork.
- Conta resolvida por `RAMON_LEAD_CAPTURE_ACCOUNT_ID` (sem fallback `Account.first` — fechado por padrão; sem ENV → 401).
- Dedup por lead **aberto** (etapa não won/lost), refinando o padrão do `RamonLeadListener` (que dedupa por qualquer lead): reenvio vira nota no lead existente; lead ganho/perdido não bloqueia captação nova.
- Contact criado direto na conta (sem `ContactInboxWithContactBuilder`): não há inbox/conversa nesse fluxo; quando o lead chamar no WhatsApp, o `RamonLeadListener` religa a conversa ao lead pelo contato.
- `mensagem` vai para `lead_notes` (tabela própria; `body` máx. 1000 — truncar), nunca para `custom_attributes`.

- [ ] **Step 5: Commit e push; CI valida**

```bash
git add config/routes.rb app/controllers/public/api/v1/ramon_leads_controller.rb spec/requests/public/api/v1/ramon_leads_controller_spec.rb
git commit -m "feat(ramon): endpoint publico de captacao de leads das landing pages"
git push -u origin feat/ramon-public-leads
```

Esperado no CI: specs novas passam; rubocop limpo (atenção a Metrics — se `create` estourar, extrair método privado, nunca desligar cop inline sem registrar).

---

### Task 2: Rate limit (Rack::Attack)

**Files:**
- Modify: `config/initializers/rack_attack.rb` (junto dos throttles path-based existentes)

**Interfaces:**
- Consumes: rota da Task 1.
- Produces: throttle `public/ramon_leads` — 5 POST/min por IP.

- [ ] **Step 1: Adicionar o throttle**

Ao lado do throttle `api/v1/widget/conversations` (padrão mais próximo — anti-bombing de endpoint público):

```ruby
    throttle('public/ramon_leads', limit: 5, period: 1.minute) do |req|
      req.ip if req.path.start_with?('/public/api/v1/ramon_leads') && req.post?
    end
```

Sem spec: `Rack::Attack.enabled` é falso fora de produção (padrão do arquivo); os throttles existentes do core também não têm spec própria. Validação = leitura no review do PR.

- [ ] **Step 2: Commit**

```bash
git add config/initializers/rack_attack.rb
git commit -m "feat(ramon): rate limit no endpoint publico de leads"
git push
```

---

### Task 3: Registro no FORK-PONTOS-DE-REGISTRO.md

**Files:**
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md`

- [ ] **Step 1: Adicionar as linhas nas duas tabelas**

Na tabela **"Arquivos do core editados"**:

```markdown
| `config/routes.rb` | `post 'ramon_leads/:capture_token'` no namespace `public/api/v1` (ao lado de `csat_survey`) | captação de leads das landing pages | A-leads |
| `config/initializers/rack_attack.rb` | throttle `public/ramon_leads` (5 POST/min por IP) | anti-abuso do endpoint público | A-leads |
```

Na tabela **"Arquivos NOVOS"**:

```markdown
| `app/controllers/public/api/v1/ramon_leads_controller.rb` | endpoint público de captação: honeypot, token ENV (`RAMON_LEAD_CAPTURE_TOKEN` + `RAMON_LEAD_CAPTURE_ACCOUNT_ID`), contact find-or-create por telefone, dedup de lead aberto → nota | leads das LPs nascem no funil | A-leads |
| `spec/requests/public/api/v1/ramon_leads_controller_spec.rb` | request spec do endpoint (criação, honeypot, 401, 422, dedup, won/lost) | cobertura CI | A-leads |
```

- [ ] **Step 2: Commit, push e abrir o PR**

```bash
git add docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "docs(ramon): registrar endpoint publico de leads"
git push
gh pr create --base <base> --title "feat(ramon): endpoint público de captação de leads das LPs" --body "..."
```

Corpo do PR: resumo do fluxo (LP → POST → contact → lead etapa Novo → nota), as duas ENVs novas que a VPS precisa, e a nota de que deploy só com OK do Eduardo. Aguardar CI verde e review.

---

### Task 4: Atualizar a doc de integração no repo landing-pages

**Files (repo `comercial\projetos\landing-pages`):**
- Modify: `docs/integracao-intranet-endpoint-leads.md` (descreve a integração ANTIGA via intranet)
- Modify: `CLAUDE.md` (seção "Integração com a Intranet" e env `PUBLIC_LEADS_ENDPOINT`)

- [ ] **Step 1: Reescrever a doc de integração**

Substituir o alvo intranet pelo novo endpoint: `PUBLIC_LEADS_ENDPOINT=https://chat.ramonantonio.adv.br/public/api/v1/ramon_leads/<token>` (preencher o secret no GitHub liga o POST sozinho — código de `enviarLead.ts` já pronto, sem mudança). Anotar que o token é o valor de `RAMON_LEAD_CAPTURE_TOKEN` da VPS.

- [ ] **Step 2: Commit no repo landing-pages (branch própria, sem deploy — doc não afeta build)**

```bash
git add docs/integracao-intranet-endpoint-leads.md CLAUDE.md
git commit -m "docs: integracao de leads agora aponta pro ramon-hub"
```

---

## Pós-plano (Eduardo, fora deste chat)

1. Merge do PR → deploy na VPS (com OK explícito) + definir `RAMON_LEAD_CAPTURE_TOKEN` (gerar valor forte) e `RAMON_LEAD_CAPTURE_ACCOUNT_ID` no env do container.
2. Preencher o secret `PUBLIC_LEADS_ENDPOINT` no repo `ramonantonio-landing-pages` → push/re-run do deploy → testar o form no browser (curl não funciona no HostGator).
3. Conferir o lead chegando na etapa "Novo" do Kanban.
