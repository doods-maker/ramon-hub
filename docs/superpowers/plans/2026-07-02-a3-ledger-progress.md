# SDD Progress — A3 Filtros, busca e totais no Kanban

Plano: `intranet-ramon/docs/superpowers/plans/2026-07-01-ramon-hub-A3-filtros-busca-totais.md`
Worktree: `ramon-hub-wt-a3`, branch `feat/ramon-hub-a3-filtros` (base origin/ramon = b71ecf073)
Verificação: SEM teste local → PR/CI. SEM migração → deploy pull+up. Merge/deploy = gate do Eduardo.
Constraints-chave: filtro server-side; dono = sdr OU closer; sources do backend; persistência localStorage `ramon_lead_filters`; soma R$ por coluna dos leads filtrados; emits camelCase; specs controller com conta seedada (usar etapas seedadas, destroy_all se precisar); prettier só nos arquivos da A3.
Lições aplicáveis (da fatia do endpoint): Account seeda funil no after_create — nunca criar etapa 'Novo' etc.; Lead tem default_scope (lead_stage_id, position, id) — `.last` não é o mais recente; Rubocop Style/FetchEnvVar exige ENV.fetch.

## Tarefas
- [x] Task 1: backend filtros leads#index
- [x] Task 2: backend lead_config#show sources
- [x] Task 3: front API+store filtros+persistência
- [x] Task 4: front KanbanFilters.vue + sources + i18n
- [x] Task 5: front total R$ coluna + montar no board
- [x] Task 6: prettier + PR aberto + CI rodando (merge/deploy = Eduardo)

## Log
CI #2 do PR17 (pós-billing): shards de teste verdes; lint-backend/front vermelhos → fix do controller (AbcSize 33.91/26 → extraído apply_equality_filters), spec (Layout/HashAlignment ×4 → URL em linha própria) e leads.js (**no-shadow: NUNCA destruturar `state` cru em action Vuex — lição antiga violada de novo; usar `state: moduleState`**). Push (8bdf39943) → **CI #3 VERDE (20 checks). PR #17 PRONTO PARA MERGE — GATE DO EDUARDO.** Depois do merge: deploy pull+up (SEM migração) + smoke visual (barra de filtros no Kanban, busca, persistência ao recarregar, total R$ por coluna).
Task 5: complete (b25e21945, review Sonnet: Spec ✅ + Approved, 0 Critical/Important; dock/new-lead/dnd preservados; stage-count testid novo).
✅ REVIEW FINAL (opus, branch completa b71ecf073..e279c701b): **READY TO MERGE**, 0 Critical/Important; costura ponta-a-ponta consistente; todos Minors triados SHIP exceto 1 fix aplicado (caixa de busca reflete q restaurado do localStorage, com guard anti re-emit). Task 6: prettier (2 arquivos) + push + **PR #17 ABERTO**. ⚠️ CI #1 do PR17 NÃO RODOU: **billing do GitHub Actions** ("payments failed / spending limit") — todos os jobs morreram em 2-4s. Eduardo resolve billing → rerun com `gh run rerun 28602514865 --failed` (ou re-push). Código já passou por review final opus (READY TO MERGE). Merge/deploy = gate do Eduardo.
Task 4: complete (c3714ab48, review Sonnet: Spec ✅ + Quality Approved, 0 Critical/Important). Minors ship-as-is p/ review final: mock de store do spec diverge do padrão createStore dos vizinhos; watch sem clearTimeout no unmount; clearFilters agenda emit redundante de q ''.
Task 3: complete (29b9e94f3, review Sonnet: Spec ✅ + Quality Approved, 0 Critical/Important). Sem regressão de dock/MERGE_LEAD; specs antigos de get compatíveis (defaults). Minor ship-as-is: catch silencioso no localStorage (intencional do brief).
Task 2: complete (19c6b5ad9 + fix do controller: reorder(nil) antes de distinct.pluck — default_scope do Lead com ORDER BY quebraria o DISTINCT no PG; review direto do controller, diff 12 linhas).
Task 1: complete (378fd2c7f + testes extras do controller em commit seguinte; review Sonnet: Spec ✅ + Quality Approved). Important (falta teste source/baseline) → resolvido pelo controller (2 exemplos adicionados). Minors ship-as-is: %/_ sem sanitize_sql_like no q (padrão do core); sem .distinct no left_joins (belongs_to, sem risco atual); lead_priority_id sem teste direto (herdado do brief).
