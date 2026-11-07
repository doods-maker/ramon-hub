# Etapa Documentos · PR 3 — marcação direta, avisos e gatilhos de humano — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. **Nível de task: refinar os passos antes de executar.**
> **Skills do Matt:** `mattpocock-skills:tdd` em toda task; `mattpocock-skills:codebase-design` na Task 3 (quem assume: SDR → closer); `mattpocock-skills:code-review` antes do merge; `mattpocock-skills:pr` no corpo.

**Goal:** em Documentos, a IA marca o documento direto (CNIS só o completo) e avisa quem confere; os gatilhos novos passam a conversa ao SDR, ou ao closer.

**Spec:** seções 5 e 6. **Depende dos PRs 1 e 2.**

## Review Focus

1. CNIS "Relações Previdenciárias" sem remunerações, ou "Ano Civil" → não marca; o agente pede de novo.
2. Lead sem SDR e sem closer → aviso vai aos admins (comportamento de `Ramon::AvisoDaIa.avisar`).
3. SDR offline → conversa vai ao closer; os dois offline → fica com o SDR do lead (alguém precisa ser dono) e aviso aos admins.
4. Push nunca leva nome, telefone ou número de processo (ntfy público).
5. Gatilho com texto `nil` (pendente de aprovação) não entra no prompt.

---

### Task 1: marcar direto em Documentos

- **Files:** `app/services/ramon/doc_match_service.rb:40` (`marcar_direto?`), prompt de classificação no mesmo serviço; Test `spec/services/ramon/doc_match_service_spec.rb`.
- **Interfaces — Produces:** `marcar_direto?(lead)` = `visao? && (lead.won_at.blank? || lead.lead_stage.label == Ramon::EtapaDeGanho::DOCUMENTOS)`. O classificador pode devolver o sinal `cnis_resumido` para item de título `/CNIS/i`; nesse caso não marca e grava `custom_attributes.doc_alertas.cnis_resumido = <iso8601>`.
- **Tests:** lead em Documentos + foto de RG → `doc_status` recebido e anexo vinculado; lead em Fechado → só sugestão (como hoje); CNIS resumido → nada marcado e alerta gravado.

### Task 2: o agente enxerga o CNIS resumido

- **Files:** `enterprise/lib/captain/tools/documentacao_faltante_tool.rb`; Test do tool.
- **Interfaces — Consumes:** `doc_alertas.cnis_resumido` da Task 1. **Produces:** a saída do tool inclui "o CNIS recebido é o resumido: pedir o completo (opção com 'remunerações')".

### Task 3: quem assume — `Ramon::Documentos::Responsavel`

- **Files:** Create `app/services/ramon/documentos/responsavel.rb`; Test.
- **Interfaces — Produces:** `Ramon::Documentos::Responsavel.de(lead) -> User | nil` — SDR do lead se online na conta (`OnlineStatusTracker`/`availability_status` do Chatwoot); senão closer online; senão SDR (ou closer) mesmo offline; senão nil. `# ponytail: online pelo status do Chatwoot; trocar por horário de trabalho se o status não for confiável na operação (spec §6).`
- **Tests:** as 4 combinações acima.

### Task 4: aviso "IA marcou: verificar"

- **Files:** `app/services/ramon/doc_match_service.rb` (após marcar), reaproveitar `Ramon::AvisoDaIa.avisar`; Test.
- **Interfaces — Consumes:** `Responsavel.de`. Ajustar `AvisoDaIa.avisar` para aceitar `user_ids:` explícitos (hoje usa `closer || sdr`), sem mudar os chamadores atuais.
- **Texto do sino (interno, não é gate):** "IA marcou <documento> de <lead>: verificar". Push: "IA marcou documento (<tese>)" via `Ramon::NtfyPushJob.rotulo`.
- **Tests:** marcação em Documentos → 1 notificação ao SDR; push sem nome.

### Task 5: gatilhos novos + handoff para o responsável

- **Files:** `app/services/ramon/perfil_ia/gatilhos.rb` (4 chaves com `'texto' => nil`: `govbr_senha_recebida`, `govbr_codigo`, `govbr_sem_acesso`, `sem_documento`), default de gatilhos da etapa Documentos em `perfil_ia.rb` (os 4 + `pediu_pessoa`, `irritado`, `juridica`); handoff em Documentos (no ponto do `bot_handoff!` do hook/tool) atribui a `Responsavel.de(lead)`, grava nota privada (gatilho + o que falta) e avisa.
- **Tests:** gatilho pendente fora do prompt; handoff em Documentos → conversa aberta, atribuída ao SDR online / closer, nota privada criada, aviso enviado; fora de Documentos o handoff é o de hoje.
- **Texto das linhas dos gatilhos:** rascunho em `comercial\docs\` para o Eduardo; só entram no código depois do "aprovado".

### Task 6: imagens do passo a passo — tool `enviar_passo_a_passo(tema)`

- **Files:** Create `enterprise/lib/captain/tools/enviar_passo_a_passo_tool.rb` (registrar no `tool_registry_service.rb`, liberado só no perfil Documentos); guarda das imagens por tema fora do git (ActiveStorage anexado ao assistente "Documentos", com nome `<tema>-<ordem>`; tela de upload em Inteligência › Assistentes, só admin); Tests.
- **Interfaces — Produces:** temas fixos `govbr_criar_conta`, `govbr_subir_nivel`, `govbr_desligar_duas_etapas`, `govbr_recuperar_senha`, `meu_inss_cnis`, `meu_inss_processo`, `meu_inss_cat` (lista em constante; tema sem imagem → o tool responde "sem imagem, explique em texto"). O tool manda as imagens do tema em ordem, numa mensagem com anexos, respeitando a janela de 24 h (fora dela não envia).
- **Tests:** tema com 3 imagens → 1 mensagem outgoing com 3 anexos em ordem; tema vazio → nenhuma mensagem; janela fechada → nenhuma mensagem.
- **Conteúdo (gate do Eduardo):** as fotos dele, conferidas com a pesquisa e recortadas (sem CPF, nome, telefone, rosto).

### Task 7: ficha do `docs_completos`

- **Files:** `db/seeds/ramon/fluxos/sistema/docs_completos.json` — trava "só conta o que uma pessoa marcou" passa a dizer que, na etapa Documentos, a marcação da IA conta (e alimenta Contrato limpo e a variável do SDR/Closer).
- **Tests:** o spec de sistema dos fluxos que valida os JSON continua verde.

### Task 8: revisão e PR

`mattpocock-skills:code-review` → `rubocop-vps` → PR (`mattpocock-skills:pr`) → CI → merge → deploy (sem migração).
