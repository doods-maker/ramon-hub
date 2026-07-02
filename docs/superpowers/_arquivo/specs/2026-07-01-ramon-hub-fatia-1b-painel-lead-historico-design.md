# Fatia 1b — Painel do Lead na conversa (aba Histórico + notas discretas) (design)

**Data:** 2026-07-01
**Roadmap pai:** `2026-07-01-ramon-hub-roadmap-p1-crm-completo-design.md` (fatia 1, parte b)
**Spec irmão:** `2026-07-01-ramon-hub-fatia-1-painel-lead-na-conversa-design.md` (a 1a entregou Resumo; esta entrega Histórico + transforma notas em discretas)
**Fonte visual:** `design-ref/CLAUDE.md` §4 (aba Histórico = timeline das interações)

---

## 1. Objetivo

Entregar a aba **Histórico** do Painel do Lead: uma **timeline cronológica** dos eventos do
lead (criação, mudanças de etapa, atribuição, prioridade, valor) **com autor**, intercalada
com **notas discretas**. Para isso, transformar o campo único `leads.notes` (blob) em notas
discretas com autor e data.

## 2. Estado atual (verificado no fork)

- A 1a entregou o `LeadConversationPanel` com casca de abas preparada para receber Histórico;
  hoje só a aba **Resumo** existe (via `LeadFields.vue`, que edita `leads.notes` como textarea).
- **Não existe** tracking de mudança de etapa nem log de atividades (confirmado: nenhuma
  tabela/model/callback de histórico). `leads.notes` é `text` (blob único).
- `Lead` já dispara `after_create_commit`/`after_update_commit` (eventos de realtime 2B).

## 3. Decisões (travadas no brainstorm 01/07)

- **Timeline rica com autor.** Eventos: `created`, `stage_changed`, `sdr_changed`,
  `closer_changed`, `priority_changed`, `value_changed`. Cada um guarda **quem fez** (usuário
  atual da requisição; ações do sistema, ex.: auto-criação, ficam sem autor).
- **Notas viram discretas.** Nova tabela `lead_notes` (autor + texto + data). O `leads.notes`
  blob é **migrado e depois removido**.
- **Onde as notas aparecem:** adicionar no **Resumo** (caixa "adicionar nota" + últimas notas);
  ver **intercaladas** na timeline do **Histórico**.
- **Marcos da conversa** (mensagens do Chatwoot) → **fora** (outro subsistema, não misturar).

## 4. Modelo de dados (2 tabelas novas)

### `lead_activities` (log do funil)
- `id`, `account_id` (null:false), `lead_id` (null:false, FK), `user_id` (nullable — autor;
  null = sistema), `kind` (string, null:false), `from_value` (string, nullable),
  `to_value` (string, nullable), `created_at`.
- `kind` ∈ {`created`, `stage_changed`, `sdr_changed`, `closer_changed`, `priority_changed`,
  `value_changed`, `note_added`}. (`note_added` referencia a nota — ver 5.2.)
- `from_value`/`to_value` guardam rótulos legíveis (ex.: nome da etapa, nome do agente, valor
  formatado) para a timeline não precisar re-resolver FKs históricas.
- Índice: `[lead_id, created_at]`.

### `lead_notes` (notas discretas)
- `id`, `account_id` (null:false), `lead_id` (null:false, FK), `user_id` (nullable — autor),
  `body` (text, null:false), `created_at`, `updated_at`.
- Índice: `[lead_id, created_at]`.

## 5. Captura dos eventos

### 5.1 Atividades do funil (no `Lead`)
- Um `after_update_commit` (ou callback dedicado) inspeciona `saved_changes` e grava uma
  `lead_activity` para cada campo relevante que mudou (`lead_stage_id`→stage_changed,
  `sdr_id`→sdr_changed, `closer_id`→closer_changed, `lead_priority_id`→priority_changed,
  `value`→value_changed), com `to_value`/`from_value` já resolvidos para rótulos.
- `after_create_commit` grava a atividade `created` (com origem/`source` se houver).
- **Autor:** ler o usuário atual do request (o Chatwoot expõe `Current.user`); se ausente
  (job/listener/sistema), `user_id` = null. NÃO falhar a operação se o autor não existir.

### 5.2 Notas
- Adicionar nota (endpoint novo) cria a `lead_note` E grava uma `lead_activity` `note_added`
  (com `to_value` = trecho/ref da nota) para a timeline. Autor = usuário atual.

## 6. Backend (API)

- `lead_notes`: `POST /accounts/:id/leads/:lead_id/notes` (criar), `GET .../notes` (listar),
  opcional `DELETE` (admin/autor) — YAGNI: começar com create+list. Pundit (admin/agent).
- `lead_activities`: expostas via `GET /accounts/:id/leads/:lead_id/activities` (listar,
  ordem cronológica) — read-only (nunca criadas via API; só pelos callbacks). Serializer com
  `kind`, `from_value`, `to_value`, `user_name` (desnormalizado), `created_at`.
- Rotas aninhadas sob `leads` (registrar em FORK-PONTOS: `config/routes.rb`).

## 7. Migração

- Criar `lead_activities` e `lead_notes`.
- **Backfill:** para cada `Lead` existente: (a) se `notes` preenchido → criar 1 `lead_note`
  (`user_id` null, `body` = notes, `created_at` = `lead.created_at`); (b) criar 1
  `lead_activity` `created` (`created_at` = `lead.created_at`) para a timeline não nascer vazia.
- **Depois** (mesma fatia, após o Resumo parar de usar o blob): **remover a coluna
  `leads.notes`** (migração separada, aplicada no deploy). O `LeadFields` deixa de ler/escrever
  `notes`; o serializer de lead deixa de expor `notes`.
- CI carrega schema via `db:schema:load` → **commitar `db/schema.rb` regenerado** (via scratch
  DB na VPS, padrão das fatias anteriores).

## 8. UI (Vue)

### Resumo (ajuste no `LeadFields`)
- Remover o textarea único de `notes`; no lugar, **lista das últimas notas** (autor + data +
  texto) + **caixa "adicionar nota"** que chama o endpoint de criar nota. Mantém o resto dos
  campos como está.

### Histórico (nova aba no `LeadConversationPanel`)
- Aba "Histórico" na casca de abas (já preparada na 1a). Componente novo
  `ramon/components/conversation/LeadHistory.vue` que busca atividades + notas e as renderiza
  **intercaladas em ordem cronológica** (mais recente no topo), cada linha com ícone/rótulo por
  `kind` e autor ("Fulano moveu para Negociação · há 2 dias"; "Fulano: <nota>").
- i18n `RAMON.LEAD_PANEL.TABS.HISTORY` + rótulos por `kind` em en + pt_BR.

## 9. Escopo / execução

Fatia com 2 tabelas + migração + mudança nas duas abas. Na fase de plano, **dividir em dois
planos** para deploys pequenos:
- **1b-i — Timeline de atividades:** tabela `lead_activities` + callbacks de captura + endpoint
  + backfill `created` + aba Histórico (só atividades do funil, sem notas).
- **1b-ii — Notas discretas:** tabela `lead_notes` + endpoints + migração do blob + remover
  `leads.notes` + Resumo (lista+adicionar) + notas intercaladas no Histórico.

Cada plano: feature branch → PR → CI (`run_foss_spec`) → deploy com OK do Eduardo (estes têm
migração → rodar `chatwoot-init`/`db:migrate` + restart, lição da 1a).

## 10. Riscos / decisões em aberto

- **Autor em callback:** confirmar que `Current.user` está disponível no `after_*_commit` do
  request (Chatwoot seta `Current.user` no ciclo de auth). Se não estiver de forma confiável,
  capturar o autor no controller e passar ao model (ex.: `lead.updated_by = Current.user`
  antes de salvar). Resolver no plano lendo o código real.
- **Remover coluna `leads.notes`:** irreversível; garantir que NADA mais lê/escreve `notes`
  (LeadFields, serializer, push_event_data, specs) antes de dropar. Fazer o drop na 1b-ii,
  depois do Resumo migrado.
- **Ruído da timeline:** editar valor/prioridade várias vezes gera muitas linhas; aceitável no
  v1, calibrar depois (ex.: agrupar) se incomodar.
- **Backfill de atividades:** só semeia `created` (não reconstrói o histórico de etapas
  passado, que não existe). Explícito.

## 11. Definição de pronto (Fatia 1b)

- Aba **Histórico** no ar com timeline cronológica: criação + etapa + atribuição +
  prioridade/valor, **com autor**, intercalada com **notas**.
- Notas discretas: adicionar no Resumo, ver no Histórico; blob `leads.notes` migrado e a coluna
  removida.
- Verificação = feature branch → PR → CI; deploy (com migração) com OK explícito do Eduardo.

## 12. Restrições (herdadas)

Fork merge-safe (namespace `ramon/`, registrar edições core em FORK-PONTOS, não tocar
enterprise); sem ambiente de teste local (CI valida); `db/schema.rb` regenerado via scratch DB;
deploy com migração exige `chatwoot-init`/`db:migrate` + restart; nada no ar sem OK do Eduardo.
