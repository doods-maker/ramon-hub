# Rastreamento Meta no funil — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O hub avisa a Meta quando um lead de anúncio de WhatsApp avança no funil (API de Conversões). O hub também guarda o gasto por anúncio, para mostrar o custo por reunião e por contrato no Metabase. As duas peças nascem desligadas.

**Architecture:**
- **Peça A.** Um callback do `Lead` (mudança de etapa ou `won_at`) enfileira `Ramon::MetaConversaoJob`. O job monta o evento e o envia pela Graph API (`/{dataset_id}/events`). Cada envio vira uma linha em `ramon_meta_eventos`. O índice único por lead+evento faz de "uma vez só" e também de rastro.
- **Peça B.** Uma rotina diária (`Ramon::MetaGastoJob`) lê os insights por anúncio e dia e faz upsert em `ramon_meta_gastos`.
- **Metabase.** Views `bi_*` (scenic) e um script de cartões, no padrão de `scripts/metabase_bi_ia_cards.py`.

**Tech Stack:** Rails 7.1 (fork Chatwoot v4.15.1), HTTParty, Sidekiq-cron (`config/schedule.yml`), scenic, Python para os cartões do Metabase.

**Spec:** `docs/superpowers/specs/2026-10-16-meta-conversoes-funil-design.md`

## Global Constraints

- **Mapeamento:** etapa `fase-qualificacao` → `LeadSubmitted`; `fase-reuniao-agendada` → `QualifiedLead`; `fase-reuniao-realizada` → `InitiateCheckout`; `won_at` preenchido → `Purchase` com `value` = `lead.value` e `currency` = `BRL`. Se `value` for nulo, o evento vai sem value e sem currency.
- **Envio:** `action_source: 'business_messaging'`, `messaging_channel: 'whatsapp'`, `user_data: { whatsapp_business_account_id, ctwa_clid }`, `event_id` = `"lead-#{lead.id}-#{evento}"`, `event_time` = Unix do momento do avanço.
- **Uma vez por lead e evento.** Se o card for e voltar, nada é reenviado. Etapas puladas não disparam.
- **Só leads com `custom_attributes['meta_referral']['ctwa_clid']`.**
- **Nada sensível sai:** nem nome, telefone (nem com hash), CPF, tese, doença ou texto. Só os ids acima e o valor.
- **Último clique vence:** o `meta_referral` novo sobrescreve o anterior (já é assim hoje).
- **WABA e caixa gravados no clique:** `meta_referral['inbox_id']` e `meta_referral['waba_id']`. O envio usa esses dados, e não a conversa atual.
- **Chaves desligadas por padrão:** `RAMON_META_CAPI=on` (peça A) e `RAMON_META_GASTO=on` (peça B), lidas com `ENV.fetch` (nunca `GlobalConfigService.load`, que grava o default no banco). Quem liga é o Eduardo, quando o número oficial estiver no hub.
- **Configuração:**
  - `RAMON_META_AD_ACCOUNT_ID` (só o número, sem `act_`);
  - `RAMON_META_ADS_TOKEN`, opcional; sem ele, usa o token do canal WhatsApp;
  - `RAMON_META_DATASET_ID`, opcional; sem ele, descobre via `GET /{waba_id}/dataset`.
- **Graph API `v24.0`.** O host vem de `ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')`, como em `whatsapp_cloud_service.rb:93`.
- **Falha não trava o funil:** o job tem retry. O erro fica na linha do evento (`status 'erro'`, `erro` = classe + código HTTP) e o lead anda igual.
- **Logs:** só classe e ids, nunca token, payload ou corpo de resposta (LGPD).
- Ambiente: sem Ruby local. Specs só no CI. Lint com `rubocop-vps`. `db/schema.rb` editado à mão. Entradas novas em `config/schedule.yml` com `queue: scheduled_jobs`.

## Review Focus

1. Lead que vai de Qualificação para Reunião agendada, volta e vai de novo deve gerar 1 `QualifiedLead`, não 2. → spec na Task 3.
2. Lead de anúncio com `value` nulo que vira Ganho deve gerar `Purchase` sem `value` e sem `currency`, e não dar erro na Meta. → spec na Task 2.
3. Lead sem `waba_id` gravado (clique anterior a este deploy) deve usar o WABA do canal da conversa do lead como reserva, e não falhar. → spec na Task 3.
4. A Meta respondendo 400 (token sem permissão) deve gravar a linha com status `erro` e não tentar de novo para sempre. Já 429/5xx deve tentar de novo. → spec na Task 2.
5. Insights paginados (`paging.next`) devem ler todas as páginas, e a mesma data relida deve atualizar o valor, sem duplicar. → spec na Task 4.

---

## Task 0 (gate — Eduardo + controller, sem código)

O doc de entrega traz o passo a passo. Itens:
1. **Conta de anúncios:** o Eduardo informa o id. O controller grava `RAMON_META_AD_ACCOUNT_ID` no `chatwoot.env`, e só o nome aparece no terminal.
2. **Prova, depois do deploy:** `rake "ramon:meta:evento_teste[<lead_id>,<TEST_EVENT_CODE>]"` (Task 3). O evento tem que aparecer em "Eventos de teste" do Gerenciador de Eventos.
   - Se a Meta recusar por permissão (App Review), parar e avisar o Eduardo.
   - Prova do gasto: `rake "ramon:meta:gasto[1]"` (Task 4) e conferir as linhas.
3. **Alvo `QualifiedLead`:** o controller confere na documentação da Meta se ele pode ser escolhido como otimização em campanha click-to-WhatsApp.
   - Se não puder, levar ao Eduardo o mapeamento alternativo: reunião agendada → `LeadSubmitted`.

### Task 1: Tabelas, modelos e WABA/caixa no clique

**Files:**
- Create: `db/migrate/20261019120001_create_ramon_meta_tracking.rb`; `app/models/meta_evento.rb`; `app/models/meta_gasto.rb`
- Modify: `db/schema.rb`; `app/services/ramon/lead_da_conversa.rb:35-46` (`apply_meta_referral`)
- Test: `spec/models/meta_evento_spec.rb`; `spec/services/ramon/lead_da_conversa_spec.rb` (caso novo)

**Interfaces:**
- **Tabela `ramon_meta_eventos`:**
  - colunas: `account_id` (FK, cascade), `lead_id` (FK, cascade), `evento` (string, not null), `event_id` (string, not null), `status` (string, not null, default `'pendente'`, valores `pendente|enviado|erro|ignorado`), `erro` (string), `enviado_em` (datetime), `ocorrido_em` (datetime, not null), timestamps;
  - índice único `[lead_id, evento]`;
  - índice `[account_id, status]`.
- **Tabela `ramon_meta_gastos`:**
  - colunas: `account_id` (FK, cascade), `data` (date, not null), `ad_id` (string, not null), `ad_name`, `campaign_id`, `campaign_name`, `spend` (decimal 12,2, default 0), `impressions` (bigint, default 0), `clicks` (bigint, default 0), timestamps;
  - índice único `[account_id, ad_id, data]`.
- `MetaEvento` (`self.table_name = 'ramon_meta_eventos'`): `EVENTOS = %w[LeadSubmitted QualifiedLead InitiateCheckout Purchase]`, `STATUS = %w[pendente enviado erro ignorado]`, validações de inclusão, `belongs_to :lead`, `belongs_to :account`.
- `MetaGasto` (`self.table_name = 'ramon_meta_gastos'`): `belongs_to :account`.
- `apply_meta_referral` passa a gravar também `'inbox_id' => message.inbox_id` e `'waba_id' => message.inbox&.channel.try(:provider_config)&.dig('business_account_id')`, com `compact_blank`.

- [ ] **Passo 1: specs que falham.**
  - `MetaEvento` recusa um evento fora de `EVENTOS`.
  - Lead+evento repetido levanta `ActiveRecord::RecordNotUnique`.
  - `apply_meta_referral` com mensagem de uma caixa `Channel::Whatsapp` (`provider_config['business_account_id'] = 'waba1'`) grava `inbox_id` e `waba_id`.
- [ ] **Passo 2: migração + `schema.rb` (versão `2026_10_19_120001`) + modelos + `apply_meta_referral`.**
- [ ] **Passo 3: `rubocop-vps`.**
- [ ] **Passo 4: commit** `feat(meta): tabelas de eventos e gasto, WABA no clique`.

### Task 2: Cliente da API de Conversões

**Files:**
- Create: `lib/ramon/meta_capi/cliente.rb`
- Test: `spec/lib/ramon/meta_capi/cliente_spec.rb`

**Interfaces:**
- `Ramon::MetaCapi::Cliente.new(token:, waba_id:)`.
- `#dataset_id -> String`:
  - `ENV['RAMON_META_DATASET_ID'].presence`;
  - senão `GET /v24.0/#{waba_id}/dataset` → `data[0]['dataset_id']`; se vier vazio, `POST` no mesmo caminho → `id`;
  - `Rails.cache` por WABA, 1 dia.
- `#enviar(evento:, event_id:, event_time:, ctwa_clid:, value: nil, test_event_code: nil) -> true`:
  - `POST /v24.0/#{dataset_id}/events` com `access_token` e `data` (JSON) = `[{ event_name:, event_time:, event_id:, action_source: 'business_messaging', messaging_channel: 'whatsapp', user_data: { whatsapp_business_account_id: waba_id, ctwa_clid: }, custom_data: (value ? { currency: 'BRL', value: } : {}) }]`;
  - inclui `test_event_code` quando presente.
- Erros:
  - `Ramon::MetaCapi::Transitorio` para 429, 5xx e rede;
  - `Ramon::MetaCapi::Recusado` para outros 4xx, com mensagem = código HTTP + `error.code` da Meta, sem o corpo.

- [ ] **Passo 1: specs que falham (WebMock).**
  - O corpo enviado traz `action_source`, `messaging_channel`, `user_data` com `ctwa_clid` e o `event_id`.
  - Sem `value`, o corpo não traz `custom_data.value` nem `currency`.
  - `dataset_id` com env não chama a Graph API.
  - Sem env, faz o GET e, com lista vazia, faz o POST.
  - 503 → `Transitorio`; 400 → `Recusado`.
- [ ] **Passo 2: implementar** no padrão HTTParty de `lib/ramon/zapsign_client.rb`.
- [ ] **Passo 3: `rubocop-vps`.**
- [ ] **Passo 4: commit** `feat(meta): cliente da API de Conversões`.

### Task 3: Gatilho no funil, job e prova

**Files:**
- Create: `app/services/ramon/meta_conversoes.rb`; `app/jobs/ramon/meta_conversao_job.rb`; `lib/tasks/ramon_meta.rake`
- Modify: `app/models/lead.rb` (um `after_update_commit` novo, junto dos vizinhos das linhas 58-67)
- Test: `spec/services/ramon/meta_conversoes_spec.rb`; `spec/jobs/ramon/meta_conversao_job_spec.rb`

**Interfaces:**
- `Ramon::MetaConversoes.registrar(lead) -> MetaEvento | nil`:
  - chamado pelo callback quando `saved_change_to_lead_stage_id? || saved_change_to_won_at?`;
  - sai se `ENV.fetch('RAMON_META_CAPI', 'off') != 'on'` ou se não houver `ctwa_clid`;
  - acha o evento pelo label da etapa nova (`LABEL_EVENTO = { 'fase-qualificacao' => 'LeadSubmitted', 'fase-reuniao-agendada' => 'QualifiedLead', 'fase-reuniao-realizada' => 'InitiateCheckout' }`), ou `Purchase` quando `won_at` acabou de ser preenchido;
  - cria `MetaEvento` (`status 'pendente'`, `ocorrido_em: Time.current`) e enfileira o job;
  - `RecordNotUnique` → `nil`, sem enfileirar.
- `Ramon::MetaConversaoJob#perform(meta_evento_id)`, `queue_as :low`:
  - acha o lead e o referral; o WABA é `meta_referral['waba_id']` ou, de reserva, o `business_account_id` do canal WhatsApp da conversa do lead;
  - o token é o `provider_config['api_key']` do canal da caixa `meta_referral['inbox_id']` ou, de reserva, o da conversa;
  - sem WABA ou sem token → `status 'ignorado'`, com `erro` = motivo curto;
  - `enviar` OK → `status 'enviado'`, `enviado_em`;
  - `Recusado` → `status 'erro'`, sem retry;
  - `Transitorio` → `retry_on`, 5 tentativas; esgotou → `status 'erro'`.
- **Rake** `ramon:meta:evento_teste[lead_id,test_event_code]`: envia agora o `QualifiedLead` do lead com `test_event_code`, sem gravar `MetaEvento`, e imprime só `ok` ou a classe do erro. Funciona com a chave off, porque é a prova.

- [ ] **Passo 1: specs que falham.**
  - Chave off → nada.
  - Sem `ctwa_clid` → nada.
  - Qualificação → Reunião agendada → volta → Reunião agendada de novo → **1** `QualifiedLead` (Review Focus 1).
  - Pular direto de Novo para Reunião realizada → só `InitiateCheckout`.
  - Ganho com `value` → `Purchase`.
  - Job: referral sem `waba_id` usa o WABA da conversa (Review Focus 3).
  - Job: 400 → `erro` sem retry (Review Focus 4).
  - Job: sem canal → `ignorado`.
- [ ] **Passo 2: implementar.**
- [ ] **Passo 3: `rubocop-vps`.**
- [ ] **Passo 4: commit** `feat(meta): avisos de conversão do funil (desligados)`.

### Task 4: Gasto por anúncio

**Files:**
- Create: `lib/ramon/meta_capi/insights.rb`; `app/jobs/ramon/meta_gasto_job.rb`
- Modify: `config/schedule.yml` (`ramon_meta_gasto_job`, cron `'0 9 * * *'`, que é 6h em Brasília; `queue: scheduled_jobs`); `lib/tasks/ramon_meta.rake` (`ramon:meta:gasto[dias]`)
- Test: `spec/lib/ramon/meta_capi/insights_spec.rb`; `spec/jobs/ramon/meta_gasto_job_spec.rb`

**Interfaces:**
- `Ramon::MetaCapi::Insights.new(token:, ad_account_id:)#por_anuncio(desde:, ate:) -> Array<Hash>`:
  - `GET /v24.0/act_#{ad_account_id}/insights` com `level=ad`, `time_increment=1`, `fields=ad_id,ad_name,campaign_id,campaign_name,spend,impressions,clicks,date_start` e `time_range={"since":..,"until":..}`;
  - segue `paging.next` até o fim;
  - devolve `{ data: Date, ad_id:, ad_name:, campaign_id:, campaign_name:, spend: BigDecimal, impressions: Integer, clicks: Integer }`;
  - erros: os mesmos `Transitorio`/`Recusado` da Task 2.
- `Ramon::MetaGastoJob#perform(dias = 7)`:
  - sai se `ENV.fetch('RAMON_META_GASTO', 'off') != 'on'` ou se faltar `RAMON_META_AD_ACCOUNT_ID`;
  - token: `RAMON_META_ADS_TOKEN` ou o `api_key` do primeiro `Channel::Whatsapp` da conta 2. **Ruling:** a conta é uma só (single-tenant); use `Account.find(ENV.fetch('RAMON_META_ACCOUNT_ID', 2))`;
  - lê de `dias` atrás até ontem e faz `MetaGasto.upsert_all(..., unique_by: [:account_id, :ad_id, :data])`;
  - `Recusado` → log (classe + código), sem retry; `Transitorio` → `retry_on`, 3 tentativas.
- O rake `ramon:meta:gasto[dias]` roda o job na hora, ignorando a chave, e imprime só o número de linhas.

- [ ] **Passo 1: specs que falham (WebMock).**
  - 2 páginas → todas as linhas.
  - A mesma data relida com spend novo atualiza e não duplica (Review Focus 5).
  - Chave off → nenhuma chamada.
- [ ] **Passo 2: implementar.**
- [ ] **Passo 3: `rubocop-vps`.**
- [ ] **Passo 4: commit** `feat(meta): gasto por anúncio (desligado)`.

### Task 5: Metabase — views e cartões

**Files:**
- Create: `db/views/bi_leads_v02.sql`; `db/views/bi_meta_gastos_v01.sql`; `db/views/bi_meta_eventos_v01.sql`; `db/migrate/20261019120002_bi_meta_views.rb` (`update_view :bi_leads, version: 2, revert_to_version: 1`; `create_view :bi_meta_gastos`; `create_view :bi_meta_eventos`); `scripts/metabase_bi_meta_cards.py`
- Modify: `db/schema.rb` (as views, no formato que o scenic já deixa ali)

**Interfaces:**
- `bi_leads_v02` = v01 mais estas colunas:
  - `(l.custom_attributes #>> '{meta_referral,source_id}') AS meta_ad_id`;
  - `(l.custom_attributes #>> '{meta_referral,source_type}') AS meta_source_type`;
  - `(l.custom_attributes #>> '{meta_referral,ctwa_clid}') IS NOT NULL AS veio_de_anuncio_whatsapp`;
  - `l.lead_stage_id`;
  - mantenha o filtro `calculo-advbox` e a ordem das colunas v01, acrescentando as novas no fim.
- `bi_meta_gastos_v01`: as colunas da tabela.
- `bi_meta_eventos_v01`: `account_id`, `lead_id`, `evento`, `status`, `erro`, `ocorrido_em`, `enviado_em`.
- **Script** no padrão de `scripts/metabase_bi_ia_cards.py`: dashboard 3, database 2, coleção 7, conta 2, idempotente, `--apply`. Cartões:
  1. **"Meta: gasto × reuniões × contratos por anúncio (30d)"** (tabela): por `ad_id`/`ad_name`, gasto, leads, reuniões agendadas (leads que passaram por `fase-reuniao-agendada`, via `bi_stage_transitions`), contratos (`won_at`), custo por reunião e custo por contrato. Se `bi_stage_transitions` não tiver a etapa por label, use o `stage_name` que a view já expõe.
  2. **"Meta: gasto por campanha (30d)"** (barra).
  3. **"Meta: avisos enviados × com erro (7d)"** (barra por status), que é o rastro visível.

- [ ] **Passo 1: views + migração + `schema.rb`.**
- [ ] **Passo 2: script dos cartões.** Valide a sintaxe com `python -m py_compile scripts/metabase_bi_meta_cards.py`. O `--apply` roda no deploy, pelo controller, com as credenciais do ambiente.
- [ ] **Passo 3: `rubocop-vps` na migração.**
- [ ] **Passo 4: commit** `feat(meta): views e cartões do Metabase`. Abrir o PR, esperar o CI verde, fazer o merge e o deploy (migração na mão), aplicar os cartões e escrever o doc de entrega com a Task 0 e o smoke.

---

## Entrega

Doc `comercial/docs/2026-10-17-meta-conversoes-entrega.md` com:
- **O que está no ar:** PR, SHA, migrações.
- **Task 0:** conta de anúncios, prova com o evento de teste e conferência do alvo.
- **Como ligar (Eduardo, quando o número oficial estiver no hub):**
  - `RAMON_META_CAPI=on` e `RAMON_META_GASTO=on`;
  - no Gerenciador, trocar a otimização das campanhas para `QualifiedLead`.
- **Smoke em bloco:**
  - A: evento de teste em "Eventos de teste";
  - B: `rake ramon:meta:gasto[3]` com as linhas no Metabase;
  - C: lead de teste com `ctwa_clid` movido no kanban gera os eventos na tabela, uma vez cada.
