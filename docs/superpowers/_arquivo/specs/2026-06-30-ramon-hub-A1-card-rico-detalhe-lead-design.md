# A1 — Card rico + gaveta de detalhe do Lead (design)

> Fork `ramon-hub` (Chatwoot v4.15.1, Rails 7.1 + Vue 3 / Vuex). Fatia A1 da trilha de melhorias do **Kanban de leads** (nativo). Pré-requisito: Fase 2C mergeada (PR #4). Supera nada; é aditivo.

## Objetivo

Transformar o card do funil (hoje minimalista) num **card rico** e dar um **painel de detalhe em gaveta lateral** onde o Eduardo vê e edita o lead sem sair do board. Editar a etapa na gaveta reaproveita o espelho `fase-*` da 2C de graça.

## Decisões travadas (brainstorm 30/06)

- **Padrão de abertura:** gaveta lateral (drawer) à direita; o board continua visível. Igual ao painel de contato do Chatwoot.
- **Dados novos = colunas NATIVAS** no `leads`: `value` (numeric), `source` (string), `notes` (text). Campos realmente variáveis/“custom” ficam pro A4 (2E). Motivo do nativo: o A3 vai **somar valor por coluna** (precisa de coluna real) e `source`/`notes` são universais.
- **Cor da etapa = coluna nativa** `lead_stages.color` (string hex), semeada a partir do `STAGES` que já tem a cor. O card e o chip usam essa cor. (Também prepara o A2, que vai deixar editar a cor da etapa na UI.)
- **Fora do escopo do A1** (fatias futuras): histórico de mudanças de etapa na gaveta (exige auditoria); filtros/busca/totais por coluna (A3); campos custom (A4/2E).

## Modelo de dados

### Migração `leads`: 3 colunas
- `value` — `:decimal, precision: 12, scale: 2, null: true` (valor estimado/causa, R$).
- `source` — `:string, null: true` (origem: “Meta Ads”, “Indicação”, etc. — texto livre no A1).
- `notes` — `:text, null: true`.

### Migração `lead_stages`: 1 coluna + backfill
- `color` — `:string, null: true` (hex, ex.: `#3b82f6`).
- Backfill: re-rodar `Leads::SeedDefaultConfigService` (idempotente) após adicionar a coluna; `seed_stages` passa a gravar `color` a partir de `STAGES` (analogamente ao que já faz com `label`).

`Lead`/`LeadStage` models: adicionar os atributos ao `permitted`/uso; sem novas associações.

## Backend (API)

### `Leads::SeedDefaultConfigService`
- `seed_stages`: ao criar/atualizar a etapa, gravar também `color` (espelha o padrão atual do `label`: set no bloco de create + `update!(color:)` se divergir). `STAGES` já tem `:color`.

### Serializer `_lead.json.jbuilder` (estender)
Expor, além do que já tem:
- `value`, `source`, `notes`.
- **Nomes desnormalizados p/ o card** (evita o front cruzar listas): `stage_name`, `stage_color`, `benefit_type_name`, `lead_priority_name`.
- **Dono:** `sdr_name`, `closer_name` (e ids já existem).
- **Contato (só leitura):** `contact_name`, `contact_phone`, `contact_email` (de `lead.contact`, se houver).

### `lead_config/show.json.jbuilder` (estender)
- Adicionar `color` em cada `stage` (p/ a coluna/chip e os seletores).

### `Lead#push_event_data` (estender)
Incluir os campos novos (`value`, `source`, `stage_color`, `stage_name`, `benefit_type_name`, `lead_priority_name`, `sdr_name`, `closer_name`, `contact_name`) para que o **upsert realtime da 2B** mantenha o card completo ao vivo, sem refetch.

### Controller `leads#update`
- `permitted_params` ganha `value`, `source`, `notes` (etapa/benefício/prioridade/sdr/closer já são editáveis). Mesma policy (admin/agent).
- **Lista de usuários p/ os seletores SDR/Closer:** reusar endpoint nativo de agents do Chatwoot (`/api/v1/accounts/:id/agents`) — não criar nada novo.

## Frontend (Vue / Vuex)

### `LeadCard.vue` (enriquecer)
Layout do card: nome (destaque) · **chip da fase** (fundo = `stage_color`) · benefício · prioridade · **valor** formatado (R$) · avatar/iniciais do dono · ícone “abrir conversa” (se houver `conversation_id`). Clique no **corpo** do card → emite `open-lead(lead)`. O botão “abrir conversa” continua com `@click.stop`.

### `LeadDrawer.vue` (novo)
- Painel lateral à direita (reusa componentes `components-next` de input/select/button; padrão visual do contact panel).
- **Editáveis (salvam via `leads/update`):** nome · etapa (select de `stages`) · benefício · prioridade · SDR · closer · valor · origem · notas.
- **Só leitura:** dados do contato (nome/telefone/e-mail) + botão “Abrir conversa”.
- Salvamento: por campo (on-change/blur) ou botão “Salvar” — **decisão de implementação no plano** (default proposto: botão “Salvar” único + “Cancelar”, pra evitar N requests). Estado de selecionado: no componente do board (prop `selectedLeadId`) ou no store `leads` (`selectedId`) — decidir no plano.
- Fechar: X, clique fora, ou Esc.

### Montagem (os dois mundos)
O board é compartilhado por `Funil.vue` (mundo Intranet) e `KanbanView.vue` (mundo Conversas). A gaveta vive no **componente do board** (KanbanBoard ou Funil/KanbanView) pra funcionar igual nos dois. `open-conversation` continua roteando como hoje.

### Vuex `leads`
- Reusar `update` (já existe). Garantir que a mutation de upsert (`EDIT_LEAD`/`setSingleRecord`) aceite os campos novos vindos do serializer e do realtime.

## Testes

- **Model/migração:** colunas presentes; seed grava `color`; `push_event_data` inclui os campos novos.
- **Serializer (request/specs):** `_lead` expõe value/source/notes + nomes desnormalizados + contato; `lead_config` expõe `color`.
- **Controller:** `update` aceita value/source/notes; rejeita o que não é permitido.
- **Front (vitest):** `LeadCard` renderiza chip com cor/valor/dono e emite `open-lead`; `LeadDrawer` carrega o lead, edita e dispara `leads/update` com o payload certo; abre/fecha.
- Verificação real = feature branch → PR → CI (`run_foss_spec`), como em 2A/2B/2C (sem env local). Schema regenerado via scratch DB.

## Riscos / notas

- **Sem env local:** todo o ciclo é CI. Atenção ao efeito-suíte (lição da 2C): as colunas novas são aditivas e não tocam enumerações globais, baixo risco.
- **`value` decimal no JS:** serializar como número/string e formatar no front (evitar float em dinheiro).
- **Realtime:** se `push_event_data` não trouxer os nomes desnormalizados, o card “empobrece” após um update ao vivo — por isso eles entram no `push_event_data`.

## Fora de escopo (próximas fatias)
- **A2 (2D):** configs geríveis na UI (criar/renomear/reordenar etapas + cor; gerenciar benefícios/prioridades; toggles).
- **A3:** filtros/busca + contador e **valor total por coluna** + quick-add no board.
- **A4 (2E):** campos custom do lead.
