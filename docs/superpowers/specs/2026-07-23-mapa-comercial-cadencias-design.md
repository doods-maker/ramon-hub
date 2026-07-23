# Cadências comerciais do mapa mental — design (23/07/2026)

Origem: mapa "Implementação Comercial" aprovado pelo Eduardo em 23/07.
Aprovado: follow-up com contador (1), lembretes de reunião (2), brecha do
motivo de perda (3), SLA 1ª resposta (4), Copilot/playbooks (5), NPS (7).
Rejeitado: gerador de proposta 3 ofertas (6).

Princípios: ZERO migração de schema (tudo em custom_attributes/lead_tasks/
lead_notes/jobs); nada é enviado ao cliente — todo texto nasce rascunho
(lead_note padrão "RASCUNHO (revisar antes de enviar)"); reuso máximo dos
padrões existentes (AdvboxEventProcessor: task+nota+ntfy; Copilot: LlmClient+
Pseudonymizer; sidekiq-cron: DailyFunnelSnapshotJob).

## A. Cadência de follow-up (Vigia de retomada)

- **Job novo** `Ramon::DailyFollowUpJob` (schedule.yml, cron `0 14 * * *` UTC
  = 11:00 BRT, queue scheduled_jobs, molde do DailyFunnelSnapshotJob).
- **Service novo** `Ramon::FollowUpDraftService.new(account:).perform`:
  - Candidatos: `Ramon::LeadRadar.stalled_leads(account)` (cadência por etapa
    já existente via `stalled_after_days`).
  - Pula lead se: tem lead_task `follow_up` aberta; OU
    `custom_attributes.follow_up.ultima_em` < 5 dias atrás (espaçamento da
    cadência do mapa: 5–10 dias); OU sem conversa vinculada.
  - Por lead elegível (teto 15/dia por conta — log quando estourar):
    1. Gera rascunho de retomada via `Ramon::LlmClient` (deepseek, mesmo
       mecanismo do ConversationCopilotService: transcript ≤200 msgs
       não-privadas + Pseudonymizer.mask + restore_name). Prompt: retomada
       WhatsApp voz "médico de confiança", 2–4 frases, varia o ângulo pelo
       nº da tentativa (1ª lembrete leve / 2ª valor novo / 3ª+ pergunta
       direta+porta aberta), proíbe prometer resultado/prazo. Falha de LLM →
       nota estática de fallback (não derruba o lote).
    2. `lead.lead_notes.create!` "RASCUNHO (revisar antes de enviar) —
       retomada nº N: ..." (truncate 1000, padrão draft_note).
    3. `lead.lead_tasks.create!(kind: 'follow_up', title: "Retomada nº N",
       due_at: Time.current.end_of_day)` → já entra na Esteira/Agenda.
    4. Incrementa `custom_attributes.follow_up` = `{"tentativas": N,
       "ultima_em": ISO8601}` (reload antes do merge — lição lost update;
       merge só na chave própria).
  - 1 push ntfy resumo por conta ao final: "X retomadas prontas pra revisar"
    (não 1 por lead).
- **Contador exposto**: `_lead.json.jbuilder` ganha `follow_up_count` e
  `follow_up_last_at` (lidos de custom_attributes; presentes TAMBÉM no slim —
  campos escalares, não o jsonb inteiro).

## B. Lembretes de reunião (anti no-show, 24h/8h/1h/30min/5min)

- No `register_meeting` do CalcomWebhooksController (e no re-registro do
  reschedule): além do que já faz,
  1. cria lead_note rascunho de CONFIRMAÇÃO (template estático com data/hora
     formatada pt-BR: mensagem de confirmação + "se não puder, me avisa
     antes" — gatilho do compromisso). Sem LLM.
  2. enfileira `Ramon::MeetingReminderJob.set(wait_until: start_at - offset)
     .perform_later(lead_id, start_at.iso8601, label)` para cada offset em
     [24h, 8h, 1h, 30min, 5min] cujo horário ainda esteja no futuro.
- **Job novo** `Ramon::MeetingReminderJob` (queue low): no fire, guard —
  lead existe E existe lead_task ABERTA kind 'meeting' com due_at == start_at
  (tolerância 60s). Falhou o guard (cancelada/remarcada) → no-op silencioso
  com log. Passou → `Ramon::NtfyPushJob`-style push direto (title "Reunião
  {lead} em {label}", body com horário + lembrete de mandar confirmação).
  Reuso: chamar NtfyPushJob.perform_now(lead_id, title:, body:) por dentro.
- Cancel/reschedule não precisa desagendar nada: o guard mata o lembrete
  órfão (padrão do próprio controller: recompute, não rastrear uid).

## C. Motivo de perda — fechar brecha de UI + ranking no Placar

- Backend já obriga (`ensure_lost_reason!`, 422 LOST_REASON_REQUIRED).
- **LeadFields.vue**: mudar etapa para uma etapa `is_lost` pelo select da
  gaveta/painel deve abrir o `LostReasonModal` existente (mesmo fluxo do
  KanbanBoard#onMove) antes do PATCH; cancelou o modal → select volta ao
  valor anterior.
- **CommandCenter**: conferir se `week.lost_reasons_30d` já é exibido; se
  não, card "Por que perdemos (30d)" com ranking (motivo × contagem).

## D. SLA de primeira resposta

- Hook: `RamonLeadListener#conversation_created` (já existente) — quando a
  conversa nasce em inbox `auto_create_lead?`, enfileirar
  `Ramon::FirstResponseSlaJob.set(wait: N.minutes).perform_later(conversation_id)`.
  N = `ENV['RAMON_SLA_FIRST_RESPONSE_MINUTES']` default 15.
- **Job novo**: no fire — conversa existe, `first_reply_created_at` nil,
  status open → push ntfy "Lead aguardando 1ª resposta há Nmin: {nome}".
  Guard de horário: só push entre 07–21 America/Sao_Paulo (fora disso,
  no-op; o /bom-dia cobre a manhã seguinte). Senão no-op.

## E. Frontend — badges e aviso na conversa

- **LeadCard (Kanban)**: badge compacto "↻ N" quando `follow_up_count > 0`
  (tooltip "N retomadas · última DD/MM"). Ao lado dos badges existentes.
- **Conversa**: `LeadFollowUpBanner.vue` novo, renderizado pelo
  `LeadPanelToggle` (MESMO fork-ponto do ConversationHeader, sem ponto novo):
  pílula/aviso quando lead stalled OU follow_up_count>0 — "Parado há Xd ·
  N retomadas" (âmbar), clicável → abre o painel do lead. Some quando não
  aplicável. Dados: `leads/getLeadByConversationId` + dispatch
  `ensureForConversation` se ausente.
- **CommandCenter**: card NPS (média + nº respostas) — ver F.
- i18n pt_BR + en em ramon.json (RAMON.FOLLOW_UP.*, RAMON.NPS.*).

## F. NPS pós-encerramento

- **Gatilho 1 (fechamento comercial)**: `Lead` after_update_commit
  `:enqueue_nps_draft, if: :saved_change_to_won_at?` (espelho do
  enqueue_advbox_closing; só quando won_at ficou preenchido) → job low que
  cria lead_note rascunho: pergunta NPS 0–10 do atendimento + (se nota boa)
  pedir avaliação no Google (`ENV['RAMON_GOOGLE_REVIEW_URL']`, placeholder
  "[link do Google]" quando ausente).
- **Gatilho 2 (êxito do caso)**: no AdvboxEventProcessor, nos eventos de
  êxito/concessão que já geram draft_note, acrescentar o mesmo rascunho NPS
  (uma linha no fluxo existente; sem duplicar se já pedimos — guard
  `custom_attributes.nps.pedido_em` por fase).
- **Registro**: input 0–10 "NPS" no LeadFields (grava
  `custom_attributes.nps = {score, em}`); dashboard `week` ganha
  `nps: {media, respostas}` (média all-time dos leads com score; SQL jsonb).

## G. Copilot + playbooks (conteúdo do mapa)

- **ConversationCopilotService**: SUMMARY ganha linha "Perfil de comunicação"
  (intuitivo/pessoal/funcional/analítico + como agir, 1 linha). DRAFT ganha:
  adaptar tom ao perfil detectado; se a última msg do cliente contém objeção,
  aplicar contorno em 4 passos (concordar → amenizar com empatia/prova social
  → contornar com segurança → avançar); usar no máx 1 gatilho mental
  adequado; manter proibições existentes.
- **theses_seed.yml** (tese Auxílio-acidente; find_or_create_by idempotente,
  re-rodar seeder na VPS conta 2 pós-deploy):
  - section `qualificacao`: +4 itens "Perfil comunicador — {intuitivo,
    pessoal, funcional, analítico}" (como reconhecer + como agir, resumido)
    e +1 item "Perguntas SPIN" (as 4 adaptadas à tese).
  - section `objecao`: +7 itens com os scripts do mapa ADAPTADOS à régua da
    banca (honorário auxílio-acidente = 30% dos atrasados + 3 benefícios,
    SEM valor de entrada — a objeção "tá caro" responde com isso, não com
    parcelamento; nunca prometer resultado/prazo): não tenho tempo · tá
    caro · medo de golpe · falar com outra pessoa · preciso pensar · medo
    de não dar certo · quer deixar pra depois. +1 item "Sem direito →
    pedir que salve o contato" (fase 02 do mapa).

## Contratos/lições a respeitar

- custom_attributes: reload antes de merge; escrever só a própria chave
  (follow_up / nps). PATCH agora faz deep_merge server-side.
- Specs: create(:account) seeda funil; Lead tem default_scope; ENV.fetch;
  máx 7 expectations; perform_enqueued_jobs sempre com only:.
- Vue: eventos camelCase; página nova w-full h-full (não se aplica);
  action não destrutura state cru.
- ramon.json/FORK-PONTOS: PR único, merge=union no FORK-PONTOS.
- Sem migração de schema → deploy sem db:migrate; seeder re-run na VPS.
