# Fase 2C — Espelho etapa ↔ label `fase-*` (ramon-hub)

**Data:** 2026-06-28
**Projeto:** ramon-hub (fork pesado do Chatwoot v4.15.1, branch `ramon`)
**Depende de:** Fase 2A (Lead nativo, `lead_stages`, seed `seed_lead_config`) e 2B
(listeners de lead + realtime). **Supera/continua:** roadmap do fork (2C do
`2026-06-26-ramon-hub-fork-pesado-design.md`).

## Objetivo

Espelhar, **nos dois sentidos**, a etapa do `Lead` no funil e uma etiqueta
`fase-*` na conversa do Chatwoot:

- Mover o lead no Kanban → a conversa ganha a label `fase-<etapa>` (e perde a antiga).
- Adicionar/trocar a label `fase-*` na conversa → o lead muda de etapa no Kanban.

Valor: operar e enxergar o estágio do funil **de dentro da conversa** (chip na
lista, filtro nativo por label), sem sair pro Kanban — e vice-versa.

## Decisões travadas (brainstorm 28/06)

1. **Bidirecional**, com mapa canônico fixo + guarda de igualdade anti-loop.
2. **Mapa canônico = coluna `lead_stages.label`** (string). Vínculo por chave
   armazenada, não pelo nome da etapa → renomear etapa (na 2D) não quebra a label.
3. As `fase-*` são **Labels nativas do Chatwoot** (cor, `show_on_sidebar`),
   semeadas junto das etapas. Eduardo mantém liberdade total sobre **qualquer
   outra** label; o espelho só governa o prefixo `fase-`.
4. **Exclusividade:** uma conversa tem **uma** `fase-*` por vez. Conflito
   (duas `fase-*` ao mesmo tempo) → **a adicionada vence**, a outra é removida
   (self-healing).
5. **Backfill no deploy:** rotina única aplica a label da etapa atual em cada
   lead que já tem conversa.
6. **Remover a única `fase-*`** → no-op no lead (continua na etapa); descompasso
   some na próxima movimentação.

## Convenção de nomes

- Título da Label do Chatwoot é validado por
  `UNICODE_CHARACTER_NUMBER_HYPHEN_UNDERSCORE` (`\A[\p{L}\p{N}]+[\p{L}\p{N}_-]+\Z`)
  e forçado a **minúsculas** (`Label#before_validation`). **`:` é inválido.**
- Logo o separador é **hífen**: `fase-novo`, `fase-qualificado`, etc.
- A chave é derivada do nome da etapa no momento da semente (slug com hífen) e
  **armazenada** em `lead_stages.label` — estável a renomeações posteriores.

## Arquitetura

### 1. Dados
- Migração: `add_column :lead_stages, :label, :string`. (Sem `null: false` no
  ato — backfill preenche; índice único opcional `(account_id, label)` se barato.)
- Semente: estende `Account#seed_lead_config` (2A) para gravar `label` em cada
  etapa e criar as 8 `Label` `fase-*` (cor distinta por etapa, `show_on_sidebar: true`).

### 2. Serviço puro — `Ramon::StageLabelSync`
Sem estado, testável isolado. Duas entradas:

- `apply_to_conversation(lead)` — sentido **Lead → conversa**:
  - retorna cedo se `lead.conversation` ou `lead.lead_stage.label` ausente;
  - `alvo = lead.lead_stage.label`;
  - `atuais_fase = conversation.label_list.select { |l| l.start_with?('fase-') }`;
  - **guarda:** se `atuais_fase == [alvo]`, não faz nada;
  - senão `keep = label_list.reject { fase-* }; conversation.update_labels(keep + [alvo])`.

- `apply_to_lead(conversation, added_labels)` — sentido **Conversa → lead**:
  - `nova_fase = added_labels.find { l.start_with?('fase-') }` (a adicionada =
    "mais recente vence"); se nenhuma `fase-*` foi adicionada → no-op;
  - acha `lead = account.leads.find_by(conversation_id: conversation.id)`; sem
    lead → no-op;
  - acha `stage = account.lead_stages.find_by(label: nova_fase)`; sem stage → no-op;
  - **guarda:** se `lead.lead_stage_id == stage.id`, não faz nada;
  - senão `lead.update!(lead_stage: stage)`;
  - **self-heal:** se a conversa tiver outras `fase-*` além de `nova_fase`,
    remove-as (`update_labels(keep_non_fase + [nova_fase])`).

### 3. Listeners (mesmo padrão da 2B; sem patch no core)
- **Lead → conversa:** método(s) `lead_created`/`lead_updated` (no
  `RamonLeadListener` ou serviço chamado por ele) → `StageLabelSync.apply_to_conversation(lead)`.
  Em `lead_updated`, agir só quando `lead_stage_id` mudou (checar o diff do evento).
- **Conversa → lead:** método `conversation_updated` → ler o diff de `label_list`
  do payload do evento (`previous_changes['label_list'] = [antiga, nova]`),
  `added = nova - antiga`, chamar `StageLabelSync.apply_to_lead(conversation, added)`.
  Confirmado: `Conversation#notify_conversation_updation` dispara
  `CONVERSATION_UPDATED` quando `label_list` muda (`list_of_keys` inclui
  `label_list`, `conversation.rb:311`).

### 4. Anti-loop (guarda de igualdade)
Lead→conversa dispara `CONVERSATION_UPDATED` → Conversa→lead roda, mas o lead já
está na etapa certa → no-op. Conversa→lead muda o lead → dispara `LEAD_UPDATED`
→ Lead→conversa roda, mas a conversa já tem a `fase-*` certa → no-op. Eco morre
em uma volta. Sem flags nem estado.

### 5. Backfill (migração de dados, 1× no deploy)
1. `add_column` + preencher `label` nas etapas existentes (slug do nome).
2. Criar as 8 `Label` `fase-*` por conta que tenha `lead_stages`.
3. Para cada `lead` com `conversation_id`, aplicar a `fase-*` da etapa atual via
   a mesma lógica de exclusividade do serviço.

Roda no padrão das fases anteriores (sem env local; schema via banco scratch
descartável na VPS, produção intacta).

## Casos de borda (decididos)
- Lead sem conversa → Lead→conversa pula.
- Conversa sem lead → Conversa→lead pula (não cria lead; isso é da flag 2B).
- Remover a única `fase-*` → no-op no lead; self-heal na próxima movimentação.
- Duas `fase-*` simultâneas → a adicionada vence, a outra removida.

## Testes (CI = feature branch → PR → `run_foss_spec`)
- **RSpec:**
  - `StageLabelSync` puro: ambos os sentidos, guarda de igualdade,
    exclusividade, diff "mais recente vence", retornos cedo (sem conversa / sem
    lead / sem stage / sem `fase-*` adicionada).
  - Listeners: `lead_updated` (mudança de etapa) etiqueta a conversa;
    `conversation_updated` com `fase-*` adicionada move o lead; eco não cria loop
    (uma única escrita por lado).
  - Semente: conta nova nasce com etapas com `label` + 8 Labels `fase-*`.
  - Migração de backfill: aplica `fase-*` nas conversas de leads existentes.
- **Front (Vitest):** nada novo nesta fase — Kanban (2A) e labels nativas já
  renderizam. (Chip de fase destacado no card do Kanban fica como melhoria futura.)
- Regenerar `db/schema.rb` via scratch DB na VPS e commitar (lição 2A/2B).
- Rodar `npx prettier@3.3.3 --write` em arquivos `ramon/` novos; zerar errors
  de eslint/rubocop (o build GHCR não roda lint).

## Fora de escopo (fatias futuras)
- **2D:** etapas/listas geríveis na UI — ao criar/renomear etapa, gerar/atualizar
  a Label `fase-*` correspondente (gancho previsto pelo mapa canônico).
- **2E:** campos custom do Lead.
- Chip de fase estilizado no card do Kanban.

## Pontos a confirmar no plano
- Em qual dispatcher os eventos `LEAD_CREATED/UPDATED` e `CONVERSATION_UPDATED`
  chegam ao `RamonLeadListener` (alinhar registro do listener — 2B usa
  AsyncDispatcher para `conversation_created`; ActionCableListener já trata
  `lead_*`).
- Formato exato do diff de `label_list` no payload do evento de
  `conversation_updated` (chave `changed_attributes`/`previous_changes`).
- Cores das 8 Labels `fase-*` (paleta; Eduardo pode recolorir depois).
