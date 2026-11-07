# Etapa Documentos · PR 2 — assistente por etapa + perfil Documentos — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. **Nível de task: refinar os passos (testes exatos) antes de executar.**
> **Skills do Matt (pedido do Eduardo):** `mattpocock-skills:tdd` em toda task; `mattpocock-skills:codebase-design` na Task 1 (costura nova: quem escolhe o assistente); `mattpocock-skills:code-review` antes do merge; `mattpocock-skills:pr` no corpo do PR.

**Goal:** lead em Documentos é atendido pelo assistente da etapa, que envia sozinho; o ganho de tese previdenciária passa a cair em Documentos.

**Architecture:** coluna `lead_stages.captain_assistant_id`; um ponto único escolhe o assistente da conversa (etapa do lead → caixa); `Ramon::PerfilIa` trata Documentos como etapa que a IA conduz; `Ramon::EtapaDeGanho.entrada` desvia para Documentos atrás de uma chave.

**Spec:** `docs/superpowers/specs/2026-11-07-etapa-documentos-design.md` (seções 1 e 2). **Depende do PR 1.**

## Global Constraints

As do PR 1, mais: migração nova → `db/schema.rb` regenerado via scratch DB na VPS; mudança em núcleo com par em `enterprise/`; chave `RAMON_ETAPA_DOCUMENTOS` (`on`/ausente) — desligada, tudo como hoje.

## Review Focus

1. Conversa sem lead, ou lead em etapa sem assistente → assistente da caixa, como hoje.
2. Lead em Documentos numa caixa SEM assistente (ex.: caixa do escritório antes do número oficial) → o assistente da etapa responde mesmo assim? **Não**: só se a caixa tem IA (`PerfilIa.com_ia?`); senão, fica com as pessoas.
3. Lead em Fechado ou Jurídico → continua `:fechado` (rascunho), como hoje.
4. Tese trabalhista / IR, lead sem tese, tese sem item de documento → ganho cai em Fechado.
5. Chave desligada → ganho cai em Fechado mesmo para previdenciária.

---

### Task 1: `Captain::AssistenteDaConversa` — ponto único

- **Files:** Create `enterprise/app/services/captain/assistente_da_conversa.rb`; migração `add_reference :lead_stages, :captain_assistant` (nullable, sem FK em cascata) + `belongs_to :captain_assistant, class_name: 'Captain::Assistant', optional: true` no par enterprise de `LeadStage` (concern em `enterprise/app/models/enterprise/concerns/`); Test `spec/enterprise/services/captain/assistente_da_conversa_spec.rb` **e** um espelho em `spec/services` que rode no CI CE (lição: `spec/enterprise` não roda em nenhum job — conferir em `.github/workflows` e incluir o arquivo num job que rode).
- **Interfaces — Produces:** `Captain::AssistenteDaConversa.para(conversation) -> Captain::Assistant | nil` — `nil` se a caixa não tem `captain_assistant`; senão `lead.lead_stage.captain_assistant || inbox.captain_assistant` (lead = `Lead.find_by(conversation_id:)`, o mesmo critério do `Ramon::PerfilIa.de`).
- **Tests:** sem lead → da caixa; etapa com assistente → o da etapa; caixa sem IA → nil.

### Task 2: trocar todas as leituras de `inbox.captain_assistant` no atendimento

- **Files (levantamento de 07/11):** `enterprise/app/services/enterprise/message_templates/hook_execution_service.rb:37,49,65,80`; `enterprise/app/listeners/captain_listener.rb:6`; `enterprise/app/jobs/captain/inbox_pending_conversations_resolution_job.rb:26,35,106,115,121,127,132` (por conversa); `enterprise/app/controllers/enterprise/api/v1/accounts/conversations_controller.rb:5`; `enterprise/lib/enterprise/captain/reply_suggestion_service.rb`; `enterprise/app/controllers/api/v1/accounts/conversations/faqs_controller.rb:25`; `app/services/ramon/reuniao_agendamento.rb:57` (sender).
- **Fica como está:** `Ramon::PerfilIa.com_ia?(inbox)` e `perfil_ia/tela.rb` (são "a caixa tem IA?").
- **Tests:** em `hook_execution_service`: lead em etapa com assistente → `Captain::Conversation::ResponseBuilderJob` recebe o assistente da etapa; handoff usa a `handoff_message` do assistente da etapa.

### Task 3: Perfil da IA conduz Documentos

- **Files:** `app/services/ramon/perfil_ia.rb:196-200` (`estado`), `:246` (`abertas`), `perfil_ia/{gravacao,historico,numeros,tela}.rb` (listas de etapas), `app/javascript/.../conversation/LeadPlaybook.vue:41` (`fase-documentos` → aba documento).
- **Interfaces — Produces:** `Ramon::PerfilIa::ETAPAS_CONDUZIDAS = [Ramon::EtapaDeGanho::DOCUMENTOS]`; `estado` devolve `:sozinha` para elas (envia); demais `is_won` seguem `:fechado`. A tela "Como a IA atende" lista Documentos depois das abertas, com permissões e gatilhos próprios.
- **Tests:** `estado` por etapa (Documentos `:sozinha`, Fechado/Jurídico `:fechado`, Perdido `:pausada`); `tela` inclui Documentos; pausa manual continua vencendo.

### Task 4: o ganho de tese marcada cai em Documentos (atrás da chave)

**Decisão (índice, 07/11):** em vez de `theses.area`, chave explícita por tese.

- **Files:** migração `add_column :theses, :passa_documentos, :boolean, default: false, null: false` (mesma migração da Task 1 ou uma segunda); `app/services/ramon/etapa_de_ganho.rb` (`entrada`); tela de teses (procurar o form de tese em `app/javascript/.../ramon/` — `git grep -n "honorario_na_tabela" app/javascript` acha o form) com a caixa "Passa pela etapa Documentos" (só admin); controller de teses permitindo o campo; jbuilder da tese expondo-o; i18n `en.json`/`pt_BR`. Test `spec/services/ramon/etapa_de_ganho_spec.rb`, request spec do controller de teses, vitest do form.
- **Interfaces — Produces:** `entrada(lead)` = Documentos se `ENV['RAMON_ETAPA_DOCUMENTOS'] == 'on'` **e** a etapa `fase-documentos` existe **e** `lead.thesis&.passa_documentos` **e** a tese tem item `section: 'documento'`; senão `principal`. **Não** depende de o lead ter conversa (decisão: ganho sem WhatsApp também vai para Documentos, com o SDR conduzindo — Task 5).
- **Tests:** as combinações do Review Focus 4–5 (trocar "trabalhista/IR" por "tese sem `passa_documentos`").

### Task 4b: arrastar para Fechado pede o motivo (decisão do Eduardo, 07/11)

- **Quando:** a pessoa move à mão (Kanban, painel, lote, atalho) para **Fechado** um lead cuja tese tem `passa_documentos` **e** a conta tem a etapa Documentos. A coluna escolhida vale, mas pede o motivo (obrigatório, como o motivo do Perdido) e grava como **nota do lead** ("Ganho direto em Fechado, sem passar por Documentos: <motivo>").
- **Files:** os 4 pontos de "mover" do PR 1 (já usam `entraNoGanho`); helper novo em `helpers/stage.js` (ex.: `pulaDocumentos(destino, lead, etapas, teses)`); reaproveitar o modal do motivo de perda se couber, senão um modal simples; nota pelo endpoint de notas que o painel já usa. i18n.
- **Tests (vitest):** previdenciária + Documentos existe + destino Fechado → pede motivo e cria nota; tese sem a chave, ou sem etapa Documentos → fluxo de hoje; motivo vazio não deixa confirmar.

### Task 5b: ganho sem conversa de WhatsApp

- Lead entra em Documentos **sem conversa**: nada de IA; sino para o SDR do lead (sem SDR: closer; sem nenhum: admins) "Lead em Documentos sem WhatsApp — conduzir os documentos" + linha no histórico. Push sem dado pessoal (`Ramon::NtfyPushJob.rotulo`). Usar o mecanismo de sino que o hub já tem (procurar como `Ramon::NtfyPushJob`/notificações são criadas hoje). Test no serviço da Task 5.

### Task 6c: BI

- Conferir as views `db/views/bi_*` e os painéis do Metabase descritos no repo (`git grep -n "bi_stage_transitions" -- db docs app`): se algo conta "ganhos" por transição para etapa `is_won`, ajustar para contar só a transição de etapa não-ganho → ganho (ou por `won_at`). Se exigir migração de view, fazer aqui com teste; se for só painel do Metabase (fora do repo), anotar no PR para o Eduardo.

### Task 5: entrar em Documentos devolve a conversa à IA

- **Files:** `app/models/concerns/lead_comercial.rb` (after_commit de mudança de etapa) ou serviço `Ramon::Documentos::Entrada`; Test correspondente.
- **Interfaces — Produces:** `Ramon::Documentos::Entrada.call(lead)` — conversa do lead → `pending`, tira `ia_pausa`, registra atividade "entrou em Documentos". **Não** manda mensagem (a abertura é do PR 5).
- **Tests:** lead entra em Documentos → conversa pendente e sem pausa; lead em Documentos sem conversa → Task 5b (aviso ao SDR), sem erro.
- **Atenção:** `contrato_fechado` com o fluxo de eventos ADVBOX no comando passa por `Ramon::Fluxos::Migracao` (`principal!`), não por `entrada` — decidir aqui se o fluxo também desvia para Documentos (deveria: mesmo critério de `entrada`).

### Task 6: tela para ligar etapa → assistente, assistente "Documentos" e rascunho do texto

- **Files:** `app/javascript/.../pages/FunilConfig.vue` (seletor "Assistente desta etapa", só admin, só etapas `is_won`), `lead_stages_controller.rb:81` (permitir `captain_assistant_id` só de assistente da conta), i18n `en.json`/`pt_BR`; Test vitest + request spec.
- **Conteúdo (gate do Eduardo):** instruções do assistente "Documentos" como rascunho em `comercial\docs\` (fora do repo público), a partir do resumo da pesquisa na spec §3. O assistente é criado pela tela Inteligência › Assistentes depois do "aprovado".
- **Release:** rodar `ramon:funil:etapas_pos_venda[2]` (PR 1) neste deploy; chave `RAMON_ETAPA_DOCUMENTOS` só liga depois dos PRs 3, 5 e 6 e dos textos aprovados.

### Task 7: revisão e PR

`mattpocock-skills:code-review` → `rubocop-vps` → PR com `mattpocock-skills:pr` → CI verde → merge → deploy com a migração (à mão, como nos PRs anteriores) → rake das etapas.
