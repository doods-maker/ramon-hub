# Etapa Documentos · PR 6 — completo → Jurídico + ANÁLISE DO CASO — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. **Nível de task: refinar antes de executar.**
> **Skills do Matt:** `mattpocock-skills:tdd` em toda task; `mattpocock-skills:codebase-design` na Task 1 (passagem ao jurídico); `mattpocock-skills:code-review` antes do merge; `mattpocock-skills:pr` no corpo.

**Goal:** checklist completo em Documentos leva o lead a Jurídico, cria a tarefa ANÁLISE DO CASO no ADVBOX com o caminho da pasta da tese e encerra a conversa da IA; desmarcar depois avisa; o Ganho para de criar "1º CONTATO COM O LEAD" para quem vai a Documentos.

**Spec:** seções 8 e 9 (com os ajustes do Eduardo de 07/11). **Depende dos PRs 1–3 e 5.**

## Global Constraints

- ANÁLISE DO CASO = tipo ADVBOX **8745386**; "1º CONTATO COM O LEAD" = **8745394** (`Ramon::AdvboxClosingService::TASK_ID`).
- Responsável da ANÁLISE DO CASO enquanto a esteira está em teste: o Eduardo (`Ramon::AdvboxClosingService::USERS_ID`).
- Uma ANÁLISE DO CASO por caso (id guardado em `custom_attributes.advbox.analise_posts_id`).
- Toda mudança no que o Ganho faz vale também no fluxo "Lead ganho" (`Ramon::Fluxos::LeadGanho` / `Migracao 'lead_ganho'`).

## Review Focus

1. Checklist completa num lead em Fechado (legado) → nada muda (sem Jurídico, sem tarefa).
2. Lead sem `advbox.lawsuits_id` (ADVBOX falhou no ganho) → lead vai a Jurídico, a tarefa não é criada, aviso aos admins com o motivo, e uma nova tentativa quando o `lawsuits_id` aparecer.
3. Desmarcar e remarcar → nenhuma 2ª tarefa; aviso de desmarcação sai uma vez por desmarcação.
4. ADVBOX fora do ar → retry do job sem duplicar (padrão `step` do `AdvboxClosingService`).
5. Texto de encerramento sem aprovação (`nil`) → não manda nada ao cliente; o resto da passagem acontece.

---

### Task 1: passagem — `Ramon::Documentos::Passagem`

- **Files:** Create `app/services/ramon/documentos/passagem.rb` + job `app/jobs/ramon/documentos/passagem_job.rb`; gancho em `app/models/concerns/lead_comercial.rb` (after_commit quando `docs_completos_em` vai de nil a valor e a etapa é `fase-documentos`); Tests.
- **Interfaces — Produces:** `Passagem.call(lead)` — move para `fase-juridico`; cria a tarefa (Task 2); manda encerramento pelo `Envio` do PR 5 (chave `documentos.encerramento`); conversa sai da IA (`bot_handoff!`/não pendente; em Jurídico o `PerfilIa` já é `:fechado`).

### Task 2: ANÁLISE DO CASO no `AdvboxDocsTaskService`

- **Files:** `app/services/ramon/advbox_docs_task_service.rb` (hoje cria a tarefa de upload do controller com `RAMON_ADVBOX_DOCS_TASK_ID` e cita a pasta **do cliente** com "— COMPLETO", nome desatualizado desde o PR #318); Tests `spec/services/ramon/advbox_docs_task_service_spec.rb`.
- **Interfaces — Produces:** `AdvboxDocsTaskService#analise_do_caso` — `create_post` com `tasks_id: 8745386`, `from`/`guests` = USERS_ID, `lawsuits_id`, `comments` com `Clientes\<Nome — CPF>\<Tese> – MM.AA — COMPLETO\` (reaproveitar `DriveExportService#nome_tese`/`nome_cliente`, tornando-os públicos), id em `advbox.analise_posts_id`. Corrigir o nome da pasta na tarefa antiga do controller também.
- **Conferir antes:** se `RAMON_ADVBOX_CONTROLLER_ID`/`RAMON_ADVBOX_DOCS_TASK_ID` estão definidos na VPS (`docker inspect` passa); se não estão, a tarefa do controller já é no-op hoje.
- **Tests:** Review Focus 2, 3 e 4.

### Task 3: aviso ao desmarcar depois do Jurídico

- **Files:** `app/models/concerns/lead_comercial.rb` (`stamp_docs_completos` apaga o carimbo → se etapa `fase-juridico`, enfileira aviso); `Ramon::AvisoDaIa.avisar` para SDR (sem SDR, closer) + admins; nota privada na conversa e atividade no lead com quem desmarcou; push sem dado pessoal; Tests.
- **Texto (interno):** "<documento> foi desmarcado de <lead>, que já está no Jurídico: decidir se volta para Documentos". A tarefa no ADVBOX não é tocada.

### Task 4: fim do "1º CONTATO COM O LEAD" para quem vai a Documentos

- **Files:** `app/services/ramon/advbox_closing_service.rb` (`perform`: pular o `step('posts_id')` quando `lead.lead_stage.label == fase-documentos`); desenho do fluxo de sistema `lead_ganho` se ele cria a tarefa por passo próprio; Tests (Documentos → cliente + caso, sem post; Fechado → como hoje).

### Task 5: ajuste na esteira (outro repo — `juridico\projetos\esteira-agentes`)

- Fora deste PR, registrado aqui para não se perder: a Recepção lê a pasta indicada nas notas da ANÁLISE DO CASO, com fallback para `Clientes\<Nome — CPF>\`. Plano próprio no repo da esteira; vigília continua desligada até o Eduardo ligar.

### Task 6: textos e revisão

- **Encerramento APROVADO pelo Eduardo em 07/11:** seção 3.5 de `C:\Users\dudsl\RAdvogados\comercial\docs\2026-11-07-agente-documentos-textos-rascunho.md` (fora do repo), uma mensagem só, literal. Entra no `config/ramon/documentos_cobranca.yml` do PR 5 como `encerramento` e sai pelo `Envio`: janela aberta → texto; fechada → não manda (o modelo `documentos_pendentes` não serve para encerramento) e registra no histórico.
- `mattpocock-skills:code-review` → `rubocop-vps` → PR (`mattpocock-skills:pr`) → CI → merge → deploy. Depois: smoke ponta a ponta com lead de teste (retomar o smoke V do consolidado, conversa #35) e só então ligar `RAMON_ETAPA_DOCUMENTOS=on`.
