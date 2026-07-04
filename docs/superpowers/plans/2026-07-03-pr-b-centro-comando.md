# PR B — Centro de Comando + jurídico embutido (Centro de Operações v2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Substituir o `RamonOverview` placeholder pelo Centro de Comando (Hoje/Funil/Semana + fila de retomada) e embutir o fluxo jurídico no lead (checklist de documentos por tese, dossiê de passagem no ganho, guidance por etapa).

**Architecture:** Um endpoint agregador (`ramon_dashboard#show`) alimenta a tela nova com contadores + listas top-N; o dossiê nasce como `lead_note` gerada por serviço quando o lead vira ganho; o checklist de documentos deriva dos `thesis_items` seção `documento` da tese do lead, com estado por item em `leads.custom_attributes.doc_status` (já liberado no PR A); a fila de retomada é navegação client-side sobre os dados do dashboard. Zero migração nova.

**Tech Stack:** Rails 7 (fork Chatwoot v4.15.1), Pundit, jbuilder, Vue 3 + Vuex, Tailwind tokens n-*.

## Global Constraints

- Base: `feat/ramon-cadencia-kanban` (PR A/#21). Branch nova: `feat/ramon-centro-comando`. Mesma worktree `ramon-hub-wt-v2` (checkout da branch nova) ou worktree própria.
- **Sem toolchain local** (nem Ruby nem node_modules): validação local = leitura; CI valida. Zero migração → NÃO precisa de regen de schema.
- Consome do PR A: `LeadTask` (scopes `open_tasks/overdue/due_today`), `Lead#stalled?`, `stage_entered_at/won_at/lost_at`, `lost_reason`, `LostReason`, `lead_stages.probability/stalled_after_days`, filtros de `leads#index` (`stalled`, `no_open_task`, `lead_stage_id`, período), store `leadTasks`, `TaskBellMenu`, payload do lead com chaves de cadência.
- Consome do PR #20: `Thesis`/`ThesisItem` (`SECTIONS = abertura apresentacao qualificacao objecao documento`), `leads.thesis_id`, aba Playbook no `LeadConversationPanel`.
- Regras do fork: eventos camelCase; Tailwind n-*; i18n espelhado en+pt_BR em `ramon.json` (namespace RAMON.COMMAND p/ tela nova; RAMON.FUNIL p/ o que vive no funil); actions Vuex sem `state` cru; máx 7 expectations/spec; etapas seedadas via find_by; Conventional Commits sem IA.
- Princípio de aprovação: dossiê e cobrança de documentos são SEMPRE rascunho (nota/clipboard) — nunca envio automático.
- NOTA do PR A: `leadTasks/getAccountTasks` mistura cache lead+agenda — a UI do dashboard filtra client-side por `due_at`/`completed_at`, nunca assume que o cache é só agenda.

---

### Task 1: Endpoint agregador `ramon_dashboard#show`

**Files:**
- Create: `app/controllers/api/v1/accounts/ramon_dashboard_controller.rb`
- Create: `app/policies/ramon_dashboard_policy.rb`
- Create: `app/views/api/v1/accounts/ramon_dashboard/show.json.jbuilder`
- Modify: `config/routes.rb` (bloco ramon: `resource :ramon_dashboard, only: [:show], controller: 'ramon_dashboard'`)
- Test: `spec/controllers/api/v1/accounts/ramon_dashboard_controller_spec.rb`

**Interfaces (Produces):** `GET /api/v1/accounts/:account_id/ramon_dashboard` →
```json
{
  "today": {
    "tasks_overdue": { "count": 2, "items": [{ "id": 1, "lead_id": 3, "lead_name": "…", "title": "…", "due_at": "…" }] },
    "tasks_today":   { "count": 1, "items": [ …mesmo shape… ] },
    "stalled":       { "count": 4, "items": [{ "id": 3, "name": "…", "stage_name": "…", "days_in_stage": 6 }] },
    "no_next_action":{ "count": 2, "items": [ …mesmo shape de lead… ] },
    "new_from_lp":   { "count": 1, "items": [ …lead shape + "source"… ] }
  },
  "funnel": [{ "stage_id": 1, "name": "Novo", "color": "…", "count": 3, "total_value": "1500.0", "weighted_value": "150.0", "is_won": false, "is_lost": false }],
  "week": {
    "created_by_source": [{ "source": "lp-auxilio-acidente", "count": 5 }],
    "won": 2, "lost": 1, "created": 8,
    "lost_reasons_30d": [{ "reason": "Sumiu / não respondeu", "count": 3 }]
  }
}
```

- [ ] **Step 1: Controller** — regras de composição (cada bloco em método privado; listas limitadas a `LIST_LIMIT = 10`, counts sempre totais):
  - `tasks_overdue/tasks_today`: `Current.account.lead_tasks.overdue/due_today.includes(:lead)`.
  - `stalled`: leads ativos (etapa nem won nem lost) com `stage_entered_at < stalled_after_days.days.ago` — reusar o SQL do filtro `stalled` do PR A (`joins(:lead_stage)` + interval); `days_in_stage` calculado em Ruby.
  - `no_next_action`: leads ativos `where.not(id: account.lead_tasks.open_tasks.select(:lead_id))`.
  - `new_from_lp`: leads com `source` presente, `conversation_id` nulo, `created_at > 48.hours.ago`, sem nota e sem task (subquery `where.not(id: LeadNote…)`).
  - `funnel`: 1 query agregada `account.leads.reorder(nil).group(:lead_stage_id).count` + `…group(:lead_stage_id).sum(:value)`, combinadas com as stages em memória (evita N+1; **atenção ao default_scope** — sempre `reorder(nil)` antes de group).
  - `week`: `created_at > 7.days.ago` group por source; `won_at/lost_at > 7.days.ago` counts; `lost_reasons_30d`: `where(lost_at: 30.days.ago..).reorder(nil).group(:lost_reason).count` ordenado desc.
- [ ] **Step 2: Policy** — `show?` = admin ou agent (padrão lead_policy).
- [ ] **Step 3: Jbuilder** — shape acima; leads das listas com `id, name, stage_name, days_in_stage, source, conversation_id, contact_phone`.
- [ ] **Step 4: Specs de request** — conta com leads seedados nos cenários: task vencida aparece em overdue; lead parado (update_column em stage_entered_at) aparece em stalled; lead won na semana conta em week.won; funnel soma value; agent autorizado, usuário de fora 401/404. Máx 7 expectations; usar `travel_to` se precisar congelar tempo (padrão do repo).
- [ ] **Step 5: Lint por leitura + commit** — `feat(ramon): endpoint agregador do Centro de Comando`

### Task 2: Dossiê de passagem no ganho (rascunho automático)

**Files:**
- Create: `app/services/leads/handoff_note_service.rb`
- Modify: `app/models/lead.rb` (callback `after_update_commit :generate_handoff_note, if: :saved_change_to_won_at?` — só quando won_at passou de nil→valor)
- Test: `spec/services/leads/handoff_note_service_spec.rb`

**Interfaces:** `Leads::HandoffNoteService.new(lead: lead).perform` cria `lead_note` (user: nil = sistema) com corpo markdown-lite ≤1000 chars.

- [ ] **Step 1: Serviço** — monta o texto do dossiê W3 (rascunho):
  ```
  📋 DOSSIÊ DE PASSAGEM (rascunho — revisar antes de enviar ao jurídico)
  Tese: <thesis.name ou benefit_type.name ou '—'>
  Origem: <source ou '—'> · Valor: <R$ value ou '—'> · Prioridade: <nome ou '—'>
  Telefone: <contact_phone ou '—'>
  Documentos (tese): <por item da seção documento: "• <content> [status]"> (status de custom_attributes['doc_status'][item.id.to_s] ∈ pendente|solicitado|recebido, default pendente)
  Etapas: criado <created_at dd/mm> → ganho <won_at dd/mm> (<n> dias)
  Últimas notas: <até 2 últimas lead_notes truncadas>
  ```
  Cortar em 1000 chars (limite do LeadNote) com sufixo "…".
- [ ] **Step 2: Callback no Lead** — `saved_change_to_won_at? && won_at.present?` → serviço em `after_update_commit` (guard: não duplicar se já existe nota começando com "📋 DOSSIÊ" criada nos últimos 5 minutos).
- [ ] **Step 3: Specs** — ganhar cria a nota com tese/documentos; re-salvar o lead ganho NÃO duplica; voltar a ativa e ganhar de novo cria nova; corpo ≤1000.
- [ ] **Step 4: Lint + commit** — `feat(ramon): dossiê de passagem em rascunho ao ganhar o lead`

### Task 3: Frontend — Centro de Comando (tela)

**Files:**
- Create: `app/javascript/dashboard/api/ramonDashboard.js`
- Create: `app/javascript/dashboard/store/modules/ramonDashboard.js` (+ registro em `store/index.js`, FORK-PONTOS)
- Create: `.../ramon/pages/CommandCenter.vue` + componentes `.../ramon/components/command/{StatBlock.vue, LeadList.vue}`
- Modify: `.../ramon/ramon.routes.js` (rota `ramon_index` passa a renderizar CommandCenter; RamonOverview.vue REMOVIDO)
- Modify: i18n `en/ramon.json` + `pt_BR/ramon.json` (RAMON.COMMAND.*)
- Test: spec de store + spec shallow do CommandCenter (padrão dos specs de página existentes, se houver; senão só store)

**Interfaces:** store `ramonDashboard` — state `{ data: null, uiFlags: { isFetching } }`, action `fetch`, getter `getData`. CommandCenter monta blocos:
- **Hoje** (grid de 5 StatBlocks: número grande + rótulo + LeadList clicável): tarefas vencidas, tarefas de hoje, parados, sem próxima ação, novos de LP.
- **Funil**: linha horizontal de etapas (nome, count, R$ ponderado) — clique navega pro Funil com `leads/setFilters({ leadStageId })`.
- **Semana**: criados × ganhos × perdidos + lista por origem + motivos de perda (30d).
- Clique em lead das listas → navega pro Funil e `leads/select(id)` (abre o drawer). Empty states com próximo passo (i18n, ex.: "Nenhuma tarefa vencida — o funil está em dia").

- [ ] **Step 1: API client + store** (padrão leadConfig; fetch único).
- [ ] **Step 2: Componentes** — números grandes (text-3xl), tokens n-*, sem gráfico; refresh no mounted + botão recarregar; loading skeleton simples.
- [ ] **Step 3: Rota/i18n/remoção do placeholder** — RamonOverview morre (git rm); rota aponta CommandCenter; IntranetSidebar: renomear rótulo "Overview"→"Centro de Comando" (i18n).
- [ ] **Step 4: Lint por leitura + commit** — `feat(ramon): Centro de Comando substitui o RamonOverview placeholder`

### Task 4: Fila de retomada (modo esteira)

**Files:**
- Create: `.../ramon/components/command/FollowUpQueue.vue`
- Modify: `.../ramon/pages/CommandCenter.vue` (botão "Rodar follow-ups (N)")
- Modify: i18n en+pt_BR

**Interfaces:** fila = união client-side de `today.tasks_overdue.items` + `today.stalled.items` (dedup por lead_id, tarefas primeiro). Modal fullscreen-lite que mostra 1 lead por vez: nome, etapa, dias, task vencida (se houver), telefone (wa.me/copiar), botões **Concluir tarefa** (dispatch `leadTasks/complete` + TaskBellMenu inline pra próxima), **Abrir conversa** (se `conversation_id` — navega pra conversa), **Pular**, **Encerrar fila**. Barra de progresso "3/9".

- [ ] **Step 1: Componente** — estado local `queue`/`index`; sem persistência; ações despacham stores existentes; ao terminar, mensagem de conclusão + refetch do dashboard.
- [ ] **Step 2: Lint + commit** — `feat(ramon): fila de retomada executável no Centro de Comando`

### Task 5: Checklist de documentos por tese + guidance por etapa (painel do lead)

**Files:**
- Create: `.../components/lead/DocChecklist.vue`
- Modify: `.../components/lead/LeadFields.vue` (montar DocChecklist quando lead tem `thesis_id`, entre Próximas ações e Notas)
- Modify: componente da aba Playbook do `LeadConversationPanel` (guidance: destacar seção conforme etapa)
- Modify: i18n en+pt_BR
- Test: spec do DocChecklist (shallow; interações de status)

**Interfaces:**
- DocChecklist lê os `thesis_items` da tese do lead (store `theses` do PR #20 — action/getter existentes; conferir nome real no módulo `store/modules/theses.js`) filtrando `section === 'documento'`; estado por item em `lead.custom_attributes.doc_status` (objeto `{ "<item_id>": "pendente|solicitado|recebido" }`, default pendente); mudar status → `leads/update({ id, custom_attributes: { ...atuais, doc_status } })` (merge — NUNCA sobrescrever outras chaves de custom_attributes).
- Botão **"Cobrar pendentes"**: monta rascunho de mensagem (i18n template: saudação + lista dos itens pendentes/solicitados + fecho) → clipboard + useAlert "Rascunho copiado — cole no WhatsApp" + marca itens pendentes como `solicitado`. NADA é enviado.
- Guidance: na aba Playbook, mapa estático etapa→seção destacada: Novo/Qualificação→`qualificacao`, Reunião agendada/realizada→`apresentacao`, Negociação/Última chance→`objecao`, Fechado→`documento`; a seção mapeada abre expandida/no topo com selo "nesta etapa"; demais continuam acessíveis.

- [ ] **Step 1: DocChecklist** (checkbox tri-estado simples: chip clicável cicla pendente→solicitado→recebido; cores n-amber/n-blue/n-teal).
- [ ] **Step 2: Wire no LeadFields + cobrar pendentes.**
- [ ] **Step 3: Guidance na aba Playbook** (prop etapa do lead; sem tocar a estrutura de dados).
- [ ] **Step 4: Spec + lint + commit** — `feat(ramon): checklist de documentos por tese, cobrança em rascunho e guidance por etapa`

### Task 6: PR e CI

- [ ] **Step 1: Push** `feat/ramon-centro-comando`; PR com base... **`feat/ramon-cadencia-kanban`** (empilhado; retarget pra `ramon` após merge do #21) — descrição formato AGENTS.md.
- [ ] **Step 2: CI pelos check-runs do commit exato** (N/N completed, zero não-success/skipped-ok). Corrigir até verde.

## Self-review
- Cobertura da spec §2-B: endpoint ✓ (T1), dossiê ✓ (T2), tela ✓ (T3), fila ✓ (T4), checklist+guidance ✓ (T5), PR ✓ (T6).
- Sem migração nova (doc_status em custom_attributes; won_at já existe). `LeadNote` limite 1000 chars respeitado no dossiê.
- Nomes: `ramon_dashboard` (controller/rota/policy/jbuilder/api client/store) uniformes; `doc_status` chave única.
