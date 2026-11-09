# 00 Atendimento.md na passagem para o jurídico — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Skills do Matt (regra do Eduardo):** `mattpocock-skills:tdd` em toda task; `mattpocock-skills:code-review` antes do merge; `mattpocock-skills:pr` no corpo.

**Goal:** na passagem Documentos → Jurídico, o hub grava `00 Atendimento.md` (a colheita em texto, com a data de cada fato e trechos do relato) na pasta da tese do cliente no Drive, antes da tarefa ANÁLISE DO CASO, para a esteira de agentes usar.

**Architecture:** a colheita passa a registrar de onde saiu cada fato (`fontes`: caminho → dd/mm) e trechos literais curtos; um renderizador puro (`Ramon::Colheita::Atendimento`) transforma a colheita em markdown; um gravador (`Ramon::Colheita::ArquivoAtendimento`) reextrai, renderiza e sobe o arquivo na pasta da tese, sem sobrescrever e sem duplicar no retry; o `Documentos::Passagem` chama o gravador entre `passar` e `analise`.

**Tech Stack:** Rails 7.1 / RSpec (CI), Google Drive via `Ramon::DriveClient`.

**Spec:** `juridico/projetos/esteira-agentes/docs/2026-11-08-atendimento-na-esteira-design.md` (item 2 "O que muda", item 3 senha; decisões de 09/11 no topo) + `docs/superpowers/specs/2026-11-09-colheita-por-tese.md` (forma da colheita).

## Global Constraints

- Gravar **antes** de criar a ANÁLISE DO CASO (evita a esteira rodar sem o arquivo).
- Nome `00 Atendimento.md`; se já existir na pasta, `00 Atendimento (AAAA-MM-DD).md`; **nunca sobrescreve**.
- Retry do `PassagemJob` (ADVBOX fora) **não** grava de novo: marca `custom_attributes['atendimento_md'] = { 'file_id', 'gravado_em' }` e só grava outra vez se `docs_completos_em` for posterior a `gravado_em` (passagem repetida).
- Pasta: `Ramon::DriveExportService.new(lead).pasta_tese_id`. Drive não configurado (`Ramon::DriveClient.configured?` falso) → não grava, registra no histórico, a passagem segue.
- Falha ao gravar (Drive, LLM) nunca impede a passagem nem a ANÁLISE DO CASO: loga e registra "00 Atendimento.md não foi gravado: <classe do erro>".
- Dono do caso = `colheita.dados.cliente` (autor); quem conversou vai como representante.
- Senha: o markdown final passa por `Ramon::Pseudonymizer.sem_senha` antes de subir.
- O arquivo é **relato, não prova**: o cabeçalho diz isso; nada de inventar campo vazio (campo vazio não aparece; lacuna vai na seção de lacunas).
- Sem Ruby local: testes no CI (PR); `rubocop-vps` antes do commit; `HUSKY=0`.

## Review Focus

1. **Retry do job** (ADVBOX fora, PassagemJob roda 3×) → um arquivo só → teste na Task 3.
2. **Passagem repetida** (lead volta a Documentos e completa de novo) → segundo arquivo com data no nome, o primeiro intacto → teste na Task 3.
3. **Lead sem colheita** (tese nova, conversa curta) → arquivo com cabeçalho + "Nada colhido da conversa" em vez de erro → teste na Task 2.
4. **Senha no relato/trecho** → `[senha]` no arquivo → teste na Task 2.
5. **Colheita antiga sem `fontes`/`trechos`** (B36 já gravado) → renderiza sem as datas → teste na Task 2.

---

### Task 1: a colheita registra fontes (dd/mm) e trechos

**Files:**
- Modify: `app/services/ramon/colheita_extraction_service.rb`, `app/services/ramon/colheita/esquema.rb` (`modelo_json` ganha `fontes` e `trechos`)
- Test: `spec/services/ramon/colheita_extraction_service_spec.rb`, `spec/services/ramon/colheita/esquema_spec.rb`

**Interfaces:**
- Produces: `colheita` gravada com `'fontes' => { 'bloco.campo' => 'dd/mm' }` e `'trechos' => [{ 'campo' => 'bloco.campo', 'texto' => String }]` ao lado de `lacunas`/`confirmar` (fora de `dados`).

- [ ] **Step 1: testes**
  - esquema: `JSON.parse(modelo_json(qualquer)).keys` inclui `'fontes'` e `'trechos'`.
  - service: resposta da IA com `fontes: { 'acidente.data' => '14/08' }` e `trechos: [{ campo: 'acidente.descricao', texto: 'a prensa desceu na minha mão' }]` → `colheita['fontes']` e `colheita['trechos']` gravados; `dados` não contém essas chaves.
  - service: o transcript enviado ao LLM traz o carimbo de data (`include('[')` + `'Cliente: '`), via `Ramon::Transcricao.de(conversa, com_hora: true)`.
- [ ] **Step 2:** CI → FAIL.
- [ ] **Step 3: implementar.** `conversation_transcript` passa a usar `Ramon::Transcricao.de(@lead.conversation, limite: MAX_MESSAGES, com_hora: true)` (sai o código duplicado). Prompt: duas regras novas — "`fontes`: para cada campo preenchido, a data `dd/mm` da mensagem de onde ele saiu (o carimbo da linha)"; "`trechos`: no máximo 3, literais e curtos (até 300 caracteres), só onde o relato decide — como o acidente/doença aconteceu, a limitação concreta, a queixa principal". `colheita_payload` grava `fontes` (Hash de String → String, só chaves String) e `trechos` (até 3, `texto` truncado em 300) e tira os dois de `dados`.
- [ ] **Step 4:** `rubocop-vps`; CI PASS.
- [ ] **Step 5: Commit** `feat(colheita): fontes (dd/mm) e trechos do relato`

---

### Task 2: `Ramon::Colheita::Atendimento` — colheita → markdown

**Files:**
- Create: `app/services/ramon/colheita/atendimento.rb`
- Test: `spec/services/ramon/colheita/atendimento_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Colheita::Esquema::BLOCOS` (ordem dos blocos), colheita da Task 1.
- Produces: `Ramon::Colheita::Atendimento.markdown(lead) -> String`

Formato (fixo):

```markdown
# Atendimento — <cliente.nome_completo || lead.name>

> Relato do lead no WhatsApp, extraído pela IA do hub em <dd/mm/aaaa hh:mm>. É dado, não prova:
> conferir cada fato com documento antes de usar na peça.

- **Tese:** <thesis.name>
- **Conversa:** <dd/mm/aaaa> a <dd/mm/aaaa>        (1ª e última mensagem pública)
- **Quem conversou:** <representante.nome> (<parentesco>) — <motivo>     (só se houver representante)

## <Bloco humanizado>            (um por bloco com algo preenchido, na ordem de BLOCOS)
- <Campo humanizado>: <valor> (dd/mm)        ("(dd/mm)" só se houver fonte; "(confirmar)" se o caminho estiver em confirmar)

## Trechos do relato
> "<texto>" — <campo humanizado> (dd/mm)

## Sinais de outra tese
- <tese>: <motivo>

## O que falta
- <campo humanizado>: <como_obter>
```

Humanizar = `chave.tr('_', ' ').capitalize`; datas ISO → `dd/mm/aaaa`; objeto aninhado → `chave: valor` separados por ` · `; lista de objetos → um item por linha (sub-bullet). Seção sem conteúdo não aparece. Sem colheita → cabeçalho + `Nada colhido da conversa ainda.` Saída final passa por `Ramon::Pseudonymizer.sem_senha`.

- [ ] **Step 1: testes** (lead B31 com colheita fictícia): título com `cliente.nome_completo`; linha `- Parou em: 15/05/2024 (02/06)` (fonte); linha com `(confirmar)`; seção `Quem conversou` só com representante; trecho com `Tx9#kLm2` sai `[senha]`; colheita antiga sem `fontes`/`trechos` renderiza sem datas; lead sem colheita → `Nada colhido da conversa ainda.`; bloco vazio não gera título.
- [ ] **Step 2:** CI → FAIL. **Step 3:** implementar. **Step 4:** `rubocop-vps`; CI PASS.
- [ ] **Step 5: Commit** `feat(colheita): 00 Atendimento.md a partir da colheita`

---

### Task 3: gravar na passagem

**Files:**
- Create: `app/services/ramon/colheita/arquivo_atendimento.rb`
- Modify: `app/services/ramon/documentos/passagem.rb` (`call`: `Ramon::Colheita::ArquivoAtendimento.gravar(lead)` depois de `passar`, antes de `analise`, só quando `no_juridico?`)
- Test: `spec/services/ramon/colheita/arquivo_atendimento_spec.rb`, `spec/services/ramon/documentos/passagem_spec.rb`

**Interfaces:**
- Consumes: `Atendimento.markdown(lead)` (Task 2), `ColheitaExtractionService#perform`, `DriveExportService#pasta_tese_id`, `DriveClient.conteudo_da_pasta/upload/configured?`
- Produces: `Ramon::Colheita::ArquivoAtendimento.gravar(lead) -> :gravado | :ja_gravado | :sem_drive | :falhou`

- [ ] **Step 1: testes** (DriveClient stubado):
  - grava `00 Atendimento.md` (`content_type: 'text/markdown'`) na pasta da tese e marca `atendimento_md.file_id`/`gravado_em`; chama a extração antes (`ColheitaExtractionService` recebe `perform`).
  - segunda chamada sem nova passagem → `:ja_gravado`, `upload` não chamado.
  - `docs_completos_em` depois de `gravado_em` e já existe `00 Atendimento.md` na pasta → sobe `00 Atendimento (AAAA-MM-DD).md`.
  - Drive não configurado → `:sem_drive`, sem erro; `upload` levanta → `:falhou`, registra no histórico, não propaga.
  - passagem: ordem — o arquivo é gravado antes de `AdvboxDocsTaskService#analise_do_caso` (`expect(...).to receive(:gravar).ordered` / `receive(:analise_do_caso).ordered`); falha do gravador não impede a ANÁLISE.
- [ ] **Step 2:** CI → FAIL. **Step 3:** implementar (registro no histórico via `Ramon::Documentos::Entrada.registrar`, textos: "00 Atendimento.md gravado na pasta da tese", "00 Atendimento.md não foi gravado: <ErroClasse>", "00 Atendimento.md: Drive não configurado"). **Step 4:** `rubocop-vps`; CI PASS.
- [ ] **Step 5: Commit** `feat(documentos): grava 00 Atendimento.md na passagem para o jurídico`

---

### Task 4: revisão, PR, merge

- [ ] `mattpocock-skills:code-review` desde `origin/ramon`.
- [ ] PR (`mattpocock-skills:pr`); Merge Danger: uma chamada de LLM a mais por passagem (reextração); arquivo novo no Drive do cliente.
- [ ] CI verde → merge → deploy pelo Eduardo com `!` → smoke na seção AH do consolidado: lead de teste completa Documentos → `00 Atendimento.md` na pasta da tese, antes da ANÁLISE; rodar a passagem de novo → nada duplica.
