# Etapa Documentos · PR 1 — várias etapas de ganho — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Pedido do Eduardo (07/11):** cada task segue `mattpocock-skills:tdd` (teste primeiro, vermelho → verde). Costura nova (Task 2) passa por `mattpocock-skills:codebase-design`. Antes do merge, `mattpocock-skills:code-review` no branch; corpo do PR com `mattpocock-skills:pr`.

**Goal:** a conta passa a aceitar mais de uma etapa de ganho, e nada do que hoje supõe "a" etapa de ganho quebra; ao fim, existem as etapas Documentos e Jurídico (por rake, sem lead nelas ainda).

**Architecture:** tira a trava de etapa de ganho única em `LeadStage`; todo código que precisa de "a etapa onde o ganho entra" passa por um ponto único (`Ramon::EtapaDeGanho`), que neste PR devolve sempre Fechado (o PR 2 desvia para Documentos). Andar entre etapas de ganho não é um ganho novo: `won_at` já é preservado; o listener dos fluxos e as telas passam a respeitar isso.

**Tech Stack:** Rails 7 (RSpec, CI), Vue 3 `<script setup>` (Vitest), Postgres.

**Spec:** `docs/superpowers/specs/2026-11-07-etapa-documentos-design.md` (seção 1).

## Global Constraints

- Sem Ruby local: quem valida é o CI do PR; lint Ruby com `rubocop-vps` antes do push (linha até 150).
- i18n: só `en.yml` (backend) e `en.json` (frontend); `pt_BR` segue o padrão do repo.
- Eventos custom Vue em camelCase; só classes Tailwind.
- Repo PÚBLICO: nada de e-mail, senha, token ou identificador de caixa.
- Labels novos: `fase-documentos` (nome "Documentos") e `fase-juridico` (nome "Jurídico"); a etapa de ganho atual é `fase-fechado` ("Fechado").
- Perdido continua único (`is_lost`).
- Commits em Conventional Commits; na worktree sem husky, `git -c core.hooksPath=/dev/null commit`.

## Review Focus

1. Arrastar um lead de Documentos para Jurídico (ganho → ganho) → nenhum modal de valor, nenhum "lead_ganho" de fluxo, nenhum `Purchase` novo na Meta, `won_at` igual. (Tasks 3 e 5.)
2. Contrato assinado no ZapSign / contrato fechado no ADVBOX / importação CSV com 3 etapas de ganho → o lead cai em **Fechado** (não na de maior ou menor id por acaso). (Task 2.)
3. Lead parado há mais de 90 dias em **Documentos** → continua visível no Kanban (a janela de "fechados" esconde ganhos antigos). (Task 4.)
4. Marcar uma etapa como "ganho" na tela de etapas → não desmarca as outras e não pede para "substituir a etapa de ganho atual"; marcar "perdido" continua substituindo. (Tasks 1 e 5.)
5. Rodar o rake duas vezes → nenhuma etapa duplicada, Perdido continua por último. (Task 6.)

---

### Task 1: `LeadStage` aceita várias etapas de ganho

**Files:**
- Modify: `app/models/lead_stage.rb` (`ensure_single_won_lost`)
- Test: `spec/models/lead_stage_spec.rb` (substituir o exemplo "mantém no máximo uma etapa de ganho")

**Interfaces:**
- Produces: `is_won` deixa de ser exclusivo por conta; `is_lost` continua exclusivo.

- [ ] **Step 1: Escrever o teste que falha** — trocar o exemplo atual por:

```ruby
it 'aceita várias etapas de ganho' do
  a = account.lead_stages.create!(name: 'Ganho A', is_won: true)
  b = account.lead_stages.create!(name: 'Ganho B', is_won: true)
  expect([a.reload.is_won, b.reload.is_won]).to eq([true, true])
end
```

(O exemplo "mantém no máximo uma etapa de perda" fica como está.)

- [ ] **Step 2: Rodar e ver falhar** — CI (`spec/models/lead_stage_spec.rb`): FAIL, `a.is_won` é `false`.
- [ ] **Step 3: Implementar** — `ensure_single_won_lost` só chama `unset_flag_on_others(:is_lost)`; renomear para `ensure_single_lost`. Atualizar o comentário do método.
- [ ] **Step 4: Rodar e ver passar** — CI verde no arquivo.
- [ ] **Step 5: Commit** — `feat(funil): várias etapas de ganho por conta`.

### Task 2: ponto único "onde o ganho entra" — `Ramon::EtapaDeGanho`

**Files:**
- Create: `app/services/ramon/etapa_de_ganho.rb`
- Modify: `app/services/ramon/funil_regras.rb:16` (`marcar_ganho`), `app/services/ramon/advbox_event_regras.rb:12` (`contrato_fechado`), `app/services/ramon/leads_csv_import.rb:95` (`target_stage`), `app/services/ramon/fluxos/migracao.rb:38` (`preparar` de `eventos_advbox`)
- Test: `spec/services/ramon/etapa_de_ganho_spec.rb` (novo), `spec/services/ramon/funil_regras_spec.rb`, `spec/services/ramon/leads_csv_import_spec.rb`, spec do `AdvboxEventRegras` onde ele é exercitado hoje (procurar `contrato_fechado` em `spec/`)

**Interfaces:**
- Produces:
  - `Ramon::EtapaDeGanho.principal(account) -> LeadStage | nil` — a etapa `label: 'fase-fechado'`; sem ela, a primeira `is_won` por `position`.
  - `Ramon::EtapaDeGanho.entrada(lead) -> LeadStage | nil` — onde um lead que acabou de ganhar deve cair. **Neste PR = `principal(lead.account)`**; o PR 2 a estende (Documentos para tese previdenciária).
  - `Ramon::EtapaDeGanho::DOCUMENTOS = 'fase-documentos'`, `JURIDICO = 'fase-juridico'`, `FECHADO = 'fase-fechado'`.

- [ ] **Step 1: Teste que falha** (`etapa_de_ganho_spec.rb`):

```ruby
it 'principal é Fechado mesmo com outras etapas de ganho antes dela' do
  docs = account.lead_stages.create!(name: 'Docs X', label: 'fase-documentos', is_won: true, position: -5)
  fechado = account.lead_stages.find_by(label: 'fase-fechado') ||
            account.lead_stages.create!(name: 'Fechado X', label: 'fase-fechado', is_won: true)
  expect(described_class.principal(account)).to eq(fechado)
  expect(described_class.entrada(build(:lead, account: account))).to eq(fechado)
  expect(docs).to be_is_won
end

it 'sem Fechado, a primeira etapa de ganho por posição' do
  account.lead_stages.where(label: 'fase-fechado').update_all(label: nil)
  primeira = account.lead_stages.create!(name: 'Ganho 1', is_won: true, position: -9)
  expect(described_class.principal(account)).to eq(primeira)
end
```

E nos specs dos chamadores, um exemplo cada: com uma etapa extra `is_won` de `position` menor que Fechado, `contrato_assinado` / `contrato_fechado` / importação com `won_at` levam o lead para **Fechado**.

- [ ] **Step 2: Rodar e ver falhar** — CI: `uninitialized constant Ramon::EtapaDeGanho`; nos chamadores, o lead cai na etapa extra.
- [ ] **Step 3: Implementar** o módulo (`module_function`, duas funções acima) e trocar `find_by(is_won: true)` / `find_by!(is_won: true)` nos 4 pontos: `marcar_ganho` e `contrato_fechado` usam `entrada(lead)`; `target_stage` e `preparar` usam `principal(account)` (o `find_by!` vira `principal(account) || raise(ActiveRecord::RecordNotFound)`).
- [ ] **Step 4: Rodar e ver passar.**
- [ ] **Step 5: Commit** — `refactor(funil): ponto único para a etapa de entrada do ganho`.

### Task 3: andar entre etapas de ganho não é um ganho novo (backend)

**Files:**
- Modify: `app/listeners/ramon_fluxo_listener.rb:39` (`lead_updated`)
- Test: `spec/listeners/ramon_fluxo_listener_spec.rb`, `spec/models/lead_spec.rb` (ou o spec onde `ganhou`/`won_at` já são cobertos)

**Interfaces:**
- Consumes: nada novo.
- Produces: o gatilho de fluxo `lead_ganho` só dispara quando a etapa **de origem** não era de ganho.

- [ ] **Step 1: Testes que falham**
  - Listener: lead em etapa `is_won` A muda para etapa `is_won` B → `Ramon::Fluxos::Disparo` **não** recebe `'lead_ganho'` (recebe `'lead_mudou_etapa'`).
  - Lead (prova de regressão, deve já passar e fica de guarda): mover de ganho A para ganho B mantém `won_at`, não chama `Ramon::Fluxos::LeadGanho.ganhou`, não enfileira `Ramon::DriveExportJob` por `won_at` e não cria `MetaEvento` `Purchase`.
- [ ] **Step 2: Rodar** — o do listener FALHA (dispara `lead_ganho`); os do lead passam.
- [ ] **Step 3: Implementar** — em `lead_updated`, `disparar('lead_ganho', ...) if etapa&.is_won && !LeadStage.find_by(id: de)&.is_won`.
- [ ] **Step 4: Rodar e ver passar.**
- [ ] **Step 5: Commit** — `fix(fluxos): ganho → ganho não dispara "lead ganho" de novo`.

### Task 4: Documentos não some do Kanban pela janela de fechados

**Files:**
- Modify: `app/services/ramon/lead_radar.rb:57` (`closed_window`)
- Test: `spec/services/ramon/lead_radar_spec.rb` (novo; se já houver spec do radar em outro caminho, usar o existente — `git grep -l "LeadRadar" spec`)

**Interfaces:**
- Consumes: `Ramon::EtapaDeGanho::DOCUMENTOS`.

- [ ] **Step 1: Teste que falha** — lead com `won_at` de 120 dias atrás numa etapa `is_won` de label `fase-documentos` aparece no resultado de `closed_window`; o mesmo lead em Fechado não aparece.
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar** — `closed_stage_ids` exclui as etapas com label `fase-documentos` (é trabalho em andamento, não fechado).
- [ ] **Step 4: Rodar e ver passar.**
- [ ] **Step 5: Commit** — `fix(funil): lead em Documentos fica visível no Kanban`.

### Task 5: telas — ganho → ganho sem modal; várias etapas de ganho na configuração e na conversão

**Files:**
- Modify:
  - `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanBoard.vue:156` (mover card) e `:396-414` (`applyStageType`/`onSetStageType`)
  - `app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadPanelBody.vue:343`
  - `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/BulkActionsBar.vue:73`
  - `app/javascript/dashboard/composables/commands/useRamonLeadHotKeys.js:73`
  - `app/javascript/dashboard/routes/dashboard/ramon/components/command/FunnelConversion.vue:21`
  - textos do diálogo de "substituir etapa de ganho" em `app/javascript/dashboard/i18n/locale/en/ramon.json` (+ `pt_BR`) se ficarem órfãos
- Test: `.../kanban/specs/KanbanBoard.spec.js`, `.../lead/specs/LeadPanelBody.spec.js`, `.../kanban/specs/BulkActionsBar.spec.js`, `app/javascript/dashboard/composables/commands/spec/useRamonLeadHotKeys.spec.js`, `.../command/specs/FunnelConversion.spec.js`

**Interfaces:**
- Produces (helper novo, reaproveitado pelos 4 pontos de "mover"): em `app/javascript/dashboard/routes/dashboard/ramon/helpers/stage.js`, `export const entraNoGanho = (destino, origem) => Boolean(destino?.is_won) && !origem?.is_won;`

- [ ] **Step 1: Testes que falham**
  - `stage.js`: `entraNoGanho({is_won:true},{is_won:true}) === false`; `entraNoGanho({is_won:true},{is_won:false}) === true`; `entraNoGanho({is_won:true}, undefined) === true`.
  - KanbanBoard: arrastar card de etapa ganho A para ganho B → `wonModalOpen` continua `false` e o update sai direto; de aberta para ganho → modal abre (já coberto, manter).
  - LeadPanelBody: lead em ganho A escolhe ganho B → sem `wonPrompt`.
  - BulkActionsBar: todos os selecionados já em ganho → sem modal; algum aberto → modal.
  - HotKeys: lead em ganho movido para outro ganho → não chama `leads/requestWon`.
  - KanbanBoard: marcar etapa como ganho com outra já ganho → **não** abre o diálogo de substituir (aplica direto); como perdido, abre (como hoje).
  - FunnelConversion: com 2 etapas de ganho, o total de ganhos exibido é a **soma** das duas.
- [ ] **Step 2: Rodar e ver falhar** — `pnpm vitest run <arquivos>` (na worktree com `node_modules`; sem ele, CI).
- [ ] **Step 3: Implementar** — os 4 pontos de "mover" usam `entraNoGanho(destino, etapaAtualDoLead)`; `onSetStageType` só pede confirmação para `lost`; comentário de `applyStageType` diz que o servidor só desmarca a de **perda**; `FunnelConversion` troca `wonStage` por `wonStages` (filter) e soma `count`.
- [ ] **Step 4: Rodar e ver passar** + `eslint` nos arquivos tocados.
- [ ] **Step 5: Commit** — `feat(funil): telas aceitam várias etapas de ganho`.

### Task 6: criar Documentos e Jurídico — `Ramon::EtapasPosVenda` + rake

**Files:**
- Create: `app/services/ramon/etapas_pos_venda.rb`, task em `lib/tasks/ramon_funil.rake` (`ramon:funil:etapas_pos_venda[account_id]`)
- Test: `spec/services/ramon/etapas_pos_venda_spec.rb`

**Interfaces:**
- Consumes: constantes de `Ramon::EtapaDeGanho`.
- Produces: `Ramon::EtapasPosVenda.criar!(account) -> [LeadStage, LeadStage]` — idempotente; cria (ou reaproveita, pelo label) "Documentos" (`fase-documentos`) e "Jurídico" (`fase-juridico`), `is_won: true`, `probability: 100`, logo depois de Fechado, empurrando as seguintes (Perdido) uma posição; sem `nome_cliente` (texto ao cliente é gate do Eduardo).

- [ ] **Step 1: Teste que falha** — numa conta semeada: depois de `criar!`, a ordem por `position` termina em `[..., 'Fechado', 'Documentos', 'Jurídico', 'Perdido']`, as três primeiras `is_won`; rodar de novo não muda a contagem de etapas nem as posições.
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar** o serviço (transação; `find_or_create_by!(label:)`; reposicionar com `update_columns(position:)` só onde muda) e a rake que o chama e imprime as etapas. Cores: hex no padrão do `seed_default_config_service.rb`. `# ponytail: conta nova não ganha as duas pelo seed — fork de uma conta só; levar ao seed se surgir 2ª conta.`
- [ ] **Step 4: Rodar e ver passar.**
- [ ] **Step 5: Commit** — `feat(funil): etapas Documentos e Jurídico por rake`.

### Task 7: ADR, revisão e PR

**Files:**
- Create: `docs/adr/0015-varias-etapas-de-ganho.md`
- Modify: `docs/adr/0001-pos-venda-como-estado-derivado.md` (status: "revogado em parte pelo 0015")

- [ ] **Step 1:** ADR 0015 — contexto (pedido do Eduardo 07/11: Documentos e Jurídico como colunas, agente escolhido pela etapa), decisão (várias `is_won`; entrada do ganho por `Ramon::EtapaDeGanho`; `won_at` preservado entre etapas de ganho; Perdido único), consequências (lista dos pontos revisados abaixo; métricas de ganho somam as etapas).
- [ ] **Step 2:** `mattpocock-skills:code-review` sobre o branch (eixos Standards e Spec); corrigir o que vier.
- [ ] **Step 3:** `rubocop-vps` nos `.rb` tocados; push; abrir o PR com corpo de `mattpocock-skills:pr` (se `gh pr create` for barrado, deixar o comando com `--body-file` pronto para o Eduardo rodar com `!`).
- [ ] **Step 4:** esperar `gh pr checks N` listar ≥ 1 check antes do `--watch`; CI 100% verde → merge e deploy (sem migração). **O rake da Task 6 NÃO roda neste deploy**: roda junto do PR 2 (etapas vazias sem agente só confundem o Kanban).
- [ ] **Step 5: Commit** do ADR — `docs(adr): 0015 várias etapas de ganho`.

## Pontos que supõem uma etapa de ganho única — levantamento de 07/11 (`git grep -n is_won`)

**Mudam neste PR**
- `app/models/lead_stage.rb:30` — trava de ganho único (Task 1).
- `app/services/ramon/funil_regras.rb:16` — ZapSign assinado → ganho (Task 2).
- `app/services/ramon/advbox_event_regras.rb:12` — contrato fechado no ADVBOX → ganho (Task 2).
- `app/services/ramon/leads_csv_import.rb:95` — importação com `won_at` (Task 2).
- `app/services/ramon/fluxos/migracao.rb:38` — etapa do `mover_etapa` dos eventos ADVBOX (Task 2).
- `app/listeners/ramon_fluxo_listener.rb:39` — `lead_ganho` em toda entrada em etapa ganha (Task 3).
- `app/services/ramon/lead_radar.rb:57` — janela de fechados esconde Documentos (Task 4).
- Frontend: `KanbanBoard.vue:156,397-414`, `LeadPanelBody.vue:343`, `BulkActionsBar.vue:73`, `useRamonLeadHotKeys.js:73`, `FunnelConversion.vue:21` (Task 5).

**Revisados, sem mudança (a semântica "está ganho = qualquer `is_won`" já serve)**
- `app/models/lead.rb:44` (`scope :open`), `:186` (`apply_stage_timestamps` preserva `won_at`).
- `app/controllers/api/v1/accounts/leads_controller.rb:173`, `public/portal_controller.rb:40`, `ramon_prescription_radar_controller.rb:41,61`, `ramon_dashboard_controller.rb:94,147,154`.
- `app/jobs/ramon/janela_whatsapp_job.rb:32` (só leads abertos — o PR 5 decide se Documentos entra).
- `app/models/copilot_suggestion.rb:56`, `ramon/night_copilot_service.rb:103`, `ramon/roteiro/efeitos.rb:52`, `ramon/roteiro/teste.rb:78`, `ramon/funil_observador/aplicar.rb:49`, `ramon/funil_regras.rb:20,38`, `ramon/cockpit_metrics.rb:30`, `ramon/funnel_snapshot_service.rb:38`, `ramon/dossie_service.rb:128`.
- `app/services/ramon/perfil_ia.rb:198,246` e `perfil_ia/{gravacao,historico,numeros,tela}.rb` — Documentos entra no PR 2.
- `app/services/ramon/meta_conversoes.rb` — `Purchase` depende de `saved_change_to_won_at?` (Task 3 prova).
- `db/views/bi_leads_v01.sql`, `bi_leads_v02.sql` — expõem `is_won` por lead; soma de ganhos continua certa.
- Frontend: `ListaAtividades.vue:64`, `ContatoLeadAberto.vue:26`, `EsteiraEtapas.vue:18,41`, `FilterChips.vue:123`, `KanbanColumn.vue:216`, `LeadCard.vue:263`, `NewLeadModal.vue:93`, `StageHeaderMenu.vue:110`, `LeadPanelBody.vue:536,544`, `RoteiroPassoForm.vue:43`, `helpers/stage.js:11`, `FunilConfig.vue:247`, `LinhaDaVida.vue:153-494`, `TvBoard.vue:210`.
- `app/javascript/.../conversation/LeadPlaybook.vue:41` mapeia `fase-fechado` → aba "documento": o PR 2 acrescenta `fase-documentos`.
- `enterprise/lib/captain/tools/mover_etapa_tool.rb` — conferir no PR 2 que a IA não move lead para etapa de ganho.
