# Inteligência — Ondas 1 (Fundação) + 2 (Tools de leitura) — plano de execução

> Spec: `docs/superpowers/specs/2026-08-16-inteligencia-completa-design.md`.
> Worktree `ramon-hub-wt-inteligencia`, branch `feat/inteligencia-onda1` (sobre origin/ramon).
> Sem Ruby local: specs rodam só no CI (`spec/enterprise` NÃO roda no CI — só rubocop; specs que
> precisam rodar vão em `spec/` fora de enterprise, ex. `spec/lib/captain/tools/`). Front: vitest.
> Ordem de deploy: PR Onda 1 + PR Onda 2 → deploy → `rake ramon:inteligencia:seed[2]` na VPS.

## Fatos de arquitetura que mandam no desenho

- Captain **Documents** só servem para GERAR FAQ (`Captain::Documents::ResponseBuilderJob` →
  `FaqGeneratorService`, json_object — DeepSeek OK). O Assistente não lê Documents direto; ele
  consulta FAQ via `faq_lookup`. Referência de comportamento vai em `response_guidelines`/skills.
- `Captain::AssistantResponse.search(query, account_id: nil)` é vetorial (OpenAI). Chamadores:
  `FaqLookupTool:9`, `search_reply_documentation_service.rb:35,37`,
  `search_documentation_service.rb:16`. `ConversationFaqService#find_similar_faqs` usa
  `nearest_neighbors` direto. `after_commit :update_response_embedding` → `UpdateEmbeddingJob`.
- `Captain::Assistant#agent_tools` (fork) só instancia `handoff` (+ `faq_lookup` se houver FAQ).
  Tools entram por Skill (`Captain::Scenario#tools`, materializado de `[x](tool://id)`; ids
  validados contra `config/agents/tools.yml`; `tool_id.classify` SINGULARIZA a última palavra).
- Fórmula do honorário: `lead_simulacoes_controller.rb:80-89` (único lugar).
- Cockpit: `Ramon::CockpitMetrics.new(account)` → `goal/conversion/team_week/agenda_today/
  losses_by_thesis/sla_today`. `LeadTask` scopes `due_today/overdue`, kind `meeting`.
- AdvBox: `Ramon::AdvboxClient.publications(lawsuit_id, limit:)`, `.posts(deadline_start:,
  deadline_end:, user_name:)` (tarefas), `.lawsuits(name:)`.
- Contato: `account.leads.where(contact_id:)`, `contact.conversations`, `lead.lead_notes`.
- Triagem de Iniciais: entradas em `LeadPanelBody.vue` (aba `ia`, l.286/868-884, imports 19-20,
  dot 262-264), `BulkActionsBar.vue:88,198-204`, `IntranetSidebar.vue:131-153`,
  `ramon.routes.js:47-52`, página `pages/TriageAgents.vue`. Consumo passivo (fica): Dossie.vue,
  LeadCard badge, LeadKit.

## Onda 1

### T1.1 FAQ textual (backend) — arquivo novo `lib/ramon/faq_busca.rb` + fork-pontos
- `Ramon::FaqBusca.textual?` = `ENV.fetch('RAMON_FAQ_BUSCA','texto') == 'texto'`.
- `Captain::AssistantResponse.search(query, account_id: nil)`: se textual →
  `where("to_tsvector('portuguese', question || ' ' || answer) @@ websearch_to_tsquery('portuguese', ?)", q)`
  ordenado por `ts_rank`, `limit(5)`; se vazio, segunda tentativa com OR das palavras
  (`to_tsquery('portuguese', palavras.join(' | '))`, palavras ≥3 letras, sanitizadas). Senão,
  comportamento vetorial original. Comentário `# FORK-PONTO (ramon)`.
- `update_response_embedding`: `return if Ramon::FaqBusca.textual?` no topo.
- `ConversationFaqService#find_similar_faqs` (ou o `perform` que chama embedding): se textual,
  não chama embedding — dedupe por `question` igual (case-insensitive) e segue.
- `config/agents/tools.yml`: descrição de `faq_lookup` → "Busca textual nas FAQs aprovadas"
  (**NÃO mexer no resto do yml — a T2.x é dona das outras linhas**).
- Spec em `spec/models/captain/assistant_response_ramon_spec.rb` (fora de enterprise): cria 3
  FAQs, busca "posso continuar trabalhando" acha a certa; busca sem match volta vazio; embedding
  não enfileira job em modo texto (`have_enqueued_job` negado).

### T1.2 Documento com conteúdo direto (backend)
- `documents_controller#document_params` permite `:content`.
- `Captain::Document`: se `content` presente na criação e sem `external_link`/pdf, `status:
  :available` e **não** enfileira `CrawlJob` (o `enqueue_response_builder_job` já dispara com
  content). Validação de `external_link` — conferir se é obrigatória; se for, relaxar quando
  `content` presente (fork-ponto). Spec em `spec/models/captain/document_ramon_spec.rb`.

### T1.3 Seed idempotente — `lib/tasks/ramon_inteligencia.rake`
`rake ramon:inteligencia:seed[account_id]`:
- Lê `db/seeds/ramon/inteligencia/assistentes.yml`: upsert `Captain::Assistant` por `name`
  (description, config merge, response_guidelines, guardrails); para cada skill upsert
  `Captain::Scenario` por (assistant, title) — description, instruction, enabled true. Skill
  existente na conta que NÃO está no yml: **desabilita** (`enabled: false`), não apaga.
- Lê `db/seeds/ramon/inteligencia/faq/*.md`: front matter `tese:` (só informativo), blocos
  `## Pergunta` + resposta; upsert `Captain::AssistantResponse` por (assistant Atendimento,
  question) com status approved, `documentable: nil`. Resposta existente **editada na UI**
  (`edited: true`) NÃO é sobrescrita. Imprime contagens.
- Idempotente: rodar 2× não duplica. Spec em `spec/lib/tasks/rake/task_ramon_inteligencia_spec.rb`
  (carregar a task, rodar contra account de factory, contar).

### T1.4 Triagem de Iniciais — remover pontos de entrada (front)
- `LeadPanelBody.vue`: tirar aba `ia` (TABS + LEAD_PANEL_TABS whitelist se houver no back —
  conferir `LEAD_PANEL_TABS` em app/), o render `<LeadTriage>`/`<LeadKit>`, imports, `iaDot`.
- `BulkActionsBar.vue`: tirar botão/ação triage. `IntranetSidebar.vue`: tirar itens
  `triagem` (placeholder) e `Agentes`. `ramon.routes.js`: tirar rota `ramon_triage_agents`;
  apagar `pages/TriageAgents.vue` e o store `triageAgents` se só ele usava. Strings i18n órfãs
  podem ficar. Ajustar specs vitest afetadas. **Não** tocar em models/controllers/jobs de
  triagem nem em Dossie.vue/LeadCard/LeadKit.

### T1.5 Conteúdo (já escrito, revisar apenas): `db/seeds/ramon/inteligencia/faq/*.md`,
`assistentes.yml`.

## Onda 2 — tools de leitura (`enterprise/lib/captain/tools/*_tool.rb`, base `RamonBaseTool`
salvo quando dito; specs em `spec/enterprise/lib/captain/tools/` — rubocop-only no CI — E um
smoke real no console da VPS após deploy)

| id | classe | entrada | saída (texto pro LLM) |
|---|---|---|---|
| `playbook_da_tese` | `PlaybookDaTeseTool < BasePublicTool` | `tese` (nome/parte) ou `lead_id`; `secao` opcional | nome, honorário (`X% dos atrasados + N mensalidades`), itens por seção (title/content) da tese; sem tese → lista as teses ativas |
| `simular_honorario` | `SimularHonorarioTool < RamonBaseTool` | `lead_id`, `mensal`, `atrasados` (números) | usa `Ramon::Honorario.calcular(thesis, atrasados:, mensal:)` (serviço NOVO extraído de `lead_simulacoes_controller#honorario`; controller passa a usar o serviço — zero mudança de resposta) |
| `historico_do_contato` | `HistoricoDoContatoTool < RamonBaseTool` | `lead_id` ou `contact_id` | leads da pessoa (tese, etapa, criado, ganho/perdido), conversas (data, inbox, status, 1ª linha), últimas 5 notas |
| `link_agendamento` | `LinkAgendamentoTool < BasePublicTool` | — | `ENV['RAMON_CALCOM_URL']` + frase sugerida; sem env → diz que o link não está configurado e que o humano deve combinar |
| `agenda_do_escritorio` | `AgendaDoEscritorioTool < BasePublicTool` | `data` opcional (AAAA-MM-DD, default hoje BRT) | reuniões (`lead_tasks kind meeting` do dia), tarefas do hub do dia + atrasadas (`overdue`, máx 20), tarefas AdvBox com prazo no dia (`AdvboxClient.posts(deadline_start:, deadline_end:)`, rescue → "AdvBox indisponível") |
| `funil_hoje` | `FunilHojeTool < BasePublicTool` | — | `CockpitMetrics`: goal, conversion (com gargalo = menor rate), sla_today, losses_by_thesis (top 3 + motivo) — em texto |
| `publicacoes_advbox` | `PublicacoesAdvboxTool < BasePublicTool` | `processo_id`, `limite` (default 5) | `AdvboxClient.publications` formatado (data, tipo, trecho ≤ 400 chars) |

- `config/agents/tools.yml`: adicionar os 7 (title/description/icon) e **remover
  `resolve_conversation`** (D11). `docs/FORK-PONTOS-DE-REGISTRO.md`: 1 linha por fork-ponto novo.
- Todas tools: account-scoped, `rescue` de indisponibilidade devolvendo String; nunca levantar.
- Env nova documentada em `.env.example`: `RAMON_CALCOM_URL`, `RAMON_FAQ_BUSCA`.

## Depois do merge (eu)
1. Deploy imagem; `docker compose exec chatwoot-web bundle exec rake ramon:inteligencia:seed[2]`.
2. Smoke real no console: `faq_lookup` textual, cada tool nova no caso 1/3.
3. Caderno de provas + smoke doc em `comercial\docs\2026-08-16-smoke-inteligencia-ondas-1-2.md`.
