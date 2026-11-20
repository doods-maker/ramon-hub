# Coexistência completa do WhatsApp (sincronização + importação silenciosa + desconexão)

**20/11/2026** · branch `feat/coexistencia-completa` · plano-mãe: `RAdvogados/comercial/docs/2026-11-20-plano-meta-pos-aprovacao.md` (passo 0.1)

## Por quê

O Embedded Signup com coexistência já funciona no fork (#160): ele pula o `/register`, aceita `FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING` e ingere `smb_message_echoes`. Faltam três coisas que a doc oficial exige ("Onboard WhatsApp Business app users", lida em 20/11):

1. assinar na WABA os campos `account_update`, `history`, `smb_app_state_sync` (além de `messages` e `smb_message_echoes`);
2. **até 24 h** depois do onboarding, chamar **uma única vez** `POST /<PHONE_NUMBER_ID>/smb_app_data` com `{"messaging_product":"whatsapp","sync_type":"smb_app_state_sync"}` (contatos) e depois com `sync_type: "history"` (até 6 meses de conversas). Repetir exige desconectar e refazer o fluxo;
3. digerir os webhooks `history`, `smb_app_state_sync` e `account_update`.

**Regra de negócio inegociável:** a importação do histórico e dos contatos é **silenciosa**. Não cria lead, não dispara funil, fluxo, automação ou webhook, a IA não responde, não reenvia nada ao WhatsApp e não manda notificação para o time.

## Payloads (da doc oficial)

**history** (`field: "history"`), `entry[].changes[].value`:
```json
{ "metadata": { "display_phone_number": "...", "phone_number_id": "..." },
  "history": [ { "metadata": { "phase": 0, "chunk_order": 1, "progress": 55 },
    "threads": [ { "id": "<user phone>", "context": { "wa_id": "...", "user_id": "<BSUID>", "username": "..." },
      "messages": [ { "from": "<business OR user phone>", "from_user_id": "<BSUID, só se do usuário>", "to": "<user, só em eco>",
        "id": "wamid...", "timestamp": "<unix>", "type": "text", "text": { "body": "..." },
        "history_context": { "status": "read" } } ] } ] } ] }
```
- Mensagem é **do escritório** quando `from` == número do canal (sem o `+`); senão é do contato.
- `type: "media_placeholder"` → mídia sem conteúdo. Pode chegar depois outro webhook `history` com `value.messages[]` (não `history[]`) trazendo o conteúdo da mídia (só para mensagens das 2 últimas semanas).
- Histórico recusado pelo escritório: `value.history[0].errors[0].code == 2593109`.
- Fases: 0 = dia 0–1, 1 = dia 1–90, 2 = dia 90–180; `progress` 0–100.

**smb_app_state_sync** (`field: "smb_app_state_sync"`):
```json
{ "metadata": {...}, "state_sync": [ { "type": "contact",
  "contact": { "full_name": "...", "first_name": "...", "phone_number": "...", "user_id": "<BSUID>" },
  "action": "add", "metadata": { "timestamp": "..." } } ] }
```
`action`: `add` (adicionou ou editou) ou `remove`.

**account_update** (`field: "account_update"`): **sem `metadata`**. `entry[0].id` é o ID do portfólio do parceiro (ou da WABA, no `ACCOUNT_OFFBOARDED`).
```json
{ "event": "PARTNER_REMOVED", "waba_info": { "waba_id": "...", "owner_business_id": "..." },
  "disconnection_info": { "reason": "PRIMARY_INACTIVITY", "initiated_by": "SYSTEM" } }
```
Outros eventos: `ACCOUNT_OFFBOARDED`, `ACCOUNT_RECONNECTED` (WABA em `entry[0].id`). Razões: `ACCOUNT_DISCONNECTED`, `BUSINESS_DOWNGRADE`, `CHANGE_NUMBER`, `COMPANION_INACTIVITY`, `PRIMARY_INACTIVITY`, `USER_RE_REGISTERED`.

## Desenho

### 1. Assinatura dos campos
`Whatsapp::WebhookSetupService#subscribed_fields` passa a ser `%w[messages smb_message_echoes account_update history smb_app_state_sync]` (+ `calls` se ligado). Atualizar `Whatsapp::FacebookApiClient::WEBHOOK_DEFAULT_FIELDS` igual.

### 2. Pedido de sincronização (uma vez só)
- `Whatsapp::FacebookApiClient#request_smb_app_data(phone_number_id, sync_type)` → `POST /<id>/smb_app_data`.
- `Whatsapp::Coexistencia::SincronizarJob` (fila `low`): para cada `sync_type` em `smb_app_state_sync` e depois `history`, só chama se `provider_config['coexistencia'][<sync_type>]` estiver vazio. No sucesso, grava `{ 'pedido_em' => iso8601, 'request_id' => ... }`. Nenhuma falha grava. 429/5xx (`Whatsapp::Coexistencia::ErroTransitorio`): retry `polynomially_longer` 6x (~20 min) e ntfy ao desistir. 4xx: ntfy uma vez e para. Canal com reautorização pendente: não pede e avisa no ntfy. Exceção de rede: retry do job (3x).
- Disparado pelo `Whatsapp::EmbeddedSignupService#perform` quando `@is_coexistence` e o canal é novo (`@inbox_id.blank?`), **depois** do `setup_webhooks`.
- Ponto de guarda: nunca chamar se o canal não for `provider == 'whatsapp_cloud'` e `source == 'embedded_signup'`.

### 3. Modo silencioso (`Ramon::Silencio`)
- `lib/current.rb`: novo atributo `importacao_silenciosa`.
- `Ramon::Silencio.executar { ... }` liga a flag, roda o bloco e desliga no `ensure`. Todo `create!` acontece **dentro** do bloco, fora de transação externa, para os `after_commit` rodarem com a flag ligada.
- `Dispatcher#dispatch`: `return if Current.importacao_silenciosa`. Isso cobre todos os listeners: lead (`RamonLeadListener`), fluxo, agente, automação, webhook, notificação, ActionCable, relatório, campanha e CSAT.
- `Message#execute_after_create_commit_callbacks`: com a flag ligada, **não** chama `reopen_conversation`, `mark_pending_conversation_as_open_for_human_response`, `dispatch_create_events`, `send_reply`, `execute_message_template_hooks` nem `update_contact_activity`. Chama só `set_conversation_activity`, ou deixa sem nada se ele sujar `last_activity_at`. O importador define `last_activity_at` pela última mensagem.
- Conferir no código se algum outro `after_create_commit` de `Conversation`, `Contact`, `ContactInbox` ou concern (inclusive `enterprise/`) dispara coisa fora do Dispatcher. Se existir, pôr guarda igual e listar no PR.
- Spec de guarda: dentro de `Ramon::Silencio.executar`, criar uma mensagem de entrada não enfileira `SendReplyJob`, não chama `MessageTemplates::HookExecutionService`, não cria `Lead` e o Dispatcher não repassa evento.

### 4. Importador de histórico
`Whatsapp::Coexistencia::ImportarHistoricoService.new(channel:, value:)`:
- Erro 2593109 → grava `coexistencia.historico_recusado_em`, ntfy "Histórico do WhatsApp não foi compartilhado" e termina.
- Para cada `thread`: acha ou cria o contato (por telefone `thread.id` ou `context.wa_id`; nome = `context.username` ou telefone), o `ContactInbox` (source_id = telefone, como o incoming normal) e **uma conversa por contato importada**, `status: :resolved`, com `additional_attributes['importado_coexistencia'] = true`. Se já existir conversa importada daquele contato na caixa, reaproveita.
- Cada mensagem: pula se já existir `Message` com aquele `source_id` (wamid; webhook pode vir repetido). Cria com `source_id`, `created_at` = timestamp, `message_type` outgoing (do escritório) ou incoming, `sender` contato (entrada) ou nil (saída), `content_attributes: { 'importado_coexistencia' => true }` e `content` pelo tipo:
  - `text` usa `body`;
  - `media_placeholder` e outras mídias sem conteúdo viram o texto fixo de i18n "[mídia do histórico — ver no celular]";
  - tipos desconhecidos viram "[tipo — conteúdo não importado]".
- Tudo dentro de `Ramon::Silencio.executar`.
- Webhook de conteúdo de mídia (`value.messages[]` no campo `history`): **fora do escopo** desta versão. Registrar no log e seguir. ponytail: anexar mídia de até 2 semanas fica para depois, se o escritório sentir falta.
- Log do progresso: `phase`, `chunk_order`, `progress`. No `progress == 100` da fase 2 (ou quando a doc indicar fim), ntfy "Histórico do WhatsApp importado".

### 5. Importador de contatos
`Whatsapp::Coexistencia::ImportarContatosService.new(channel:, value:)`:
- `add`: cria ou atualiza o contato (nome = `full_name`; telefone = `phone_number` com `+`) e o `ContactInbox`. **Não** sobrescreve um nome já editado no hub. Atualiza só se o nome atual for vazio ou igual ao telefone.
- `remove`: não apaga nada (só log).
- Dentro de `Ramon::Silencio.executar`.

### 6. Desconexão (`account_update`)
No `Webhooks::WhatsappEventsJob#perform`, **antes** de procurar o canal pelo `metadata` (que não existe nesse webhook), se `field == 'account_update'`:
- acha o canal por `provider_config['business_account_id'] == waba_info.waba_id` (ou `entry[0].id` nos eventos sem `waba_info`);
- `PARTNER_REMOVED` / `ACCOUNT_OFFBOARDED`: grava `coexistencia.desconectado_em`, `motivo`, `iniciado_por`, e manda ntfy "WhatsApp desconectado do hub (<motivo>) — reconectar pela caixa". Sem e-mail e sem `prompt_reauthorization!`;
- `ACCOUNT_RECONNECTED`: limpa `desconectado_em` e loga;
- outros eventos: só log.

Roteamento dos demais campos no mesmo job:
- `history` → importador de histórico;
- `smb_app_state_sync` → importador de contatos;
- **sem** passar pelo lock por remetente (não há `messages[]`).

### 7. Fora do escopo
- Front-end: nenhuma tela nova. O ES já existe; os extras v4 (`featureType: whatsapp_business_app_onboarding` + `sessionInfoVersion: '3'`) **seguem iguais ao exemplo atual da doc**, então não mexer.
- Mídia do histórico, edição e revogação de mensagem, tela de progresso da sincronização.

## Testes (RSpec; quem roda é o CI)
- `facebook_api_client_spec`: `request_smb_app_data` (corpo e URL certos).
- `webhook_setup_service_spec`: campos novos.
- `embedded_signup_service_spec`: coexistência + canal novo enfileira o `SincronizarJob`; reauth e não-coexistência não enfileiram.
- `coexistencia/sincronizar_job_spec`: chama as 2 sincronizações na ordem; não repete a que já tem `pedido_em`; erro HTTP não grava.
- `coexistencia/importar_historico_service_spec`: cria contato, conversa resolvida e mensagens com direção certa; idempotente por wamid; placeholder; erro 2593109; **não** cria Lead, **não** enfileira `SendReplyJob`, **não** chama o HookExecutionService.
- `coexistencia/importar_contatos_service_spec`: add cria e atualiza sem pisar nome editado; remove não apaga.
- `whatsapp_events_job_spec`: roteia `history`, `smb_app_state_sync` e `account_update` (PARTNER_REMOVED grava e manda ntfy).
- `ramon/silencio_spec`: Dispatcher calado dentro do bloco e volta ao normal depois, mesmo com exceção.

## FORK-PONTOS
Registrar em `docs/FORK-PONTOS-DE-REGISTRO.md`: `Dispatcher#dispatch`, `Message#execute_after_create_commit_callbacks`, `WhatsappEventsJob` (roteamento), `WebhookSetupService#subscribed_fields`, `EmbeddedSignupService#perform`.
