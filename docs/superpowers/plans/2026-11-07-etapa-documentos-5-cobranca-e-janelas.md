# Etapa Documentos · PR 5 — abertura, cobrança e janelas — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. **Nível de task: refinar antes de executar.**
> **Skills do Matt:** `mattpocock-skills:tdd` em toda task; `mattpocock-skills:codebase-design` na Task 1 (relógio da cobrança como função pura); `mattpocock-skills:code-review` antes do merge; `mattpocock-skills:pr` no corpo.

**Goal:** a abertura, os 2 lembretes, o aviso de acompanhamento e os gatilhos de silêncio e travado saem sozinhos, em horário comercial, por texto livre dentro da janela de 24 h e por modelo aprovado fora dela.

**Spec:** seção 7 (ritmo com os ajustes do Eduardo de 07/11). **Depende dos PRs 2 e 3.**

## Global Constraints

- Ritmo (configurável, sem código): abertura ao entrar; lembrete 1 com **3 h úteis** sem resposta; lembrete 2 na **manhã do dia útil seguinte**; **silêncio → SDR** 4 h úteis depois do lembrete 2; **acompanhamento** (sino ao SDR, IA segue) com **1 dia útil** sem documento novo; **travado → SDR assume** com **2 dias úteis** sem documento novo. Teto: 2 lembretes até uma pessoa agir.
- Permissão de envio = só a janela de 24 h (`Conversations::MessageWindowService#can_reply?`). A janela grátis de anúncio muda só preço.
- Modelo da Meta: categoria utility, puramente informativo; nome e variáveis em configuração; texto = gate do Eduardo.
- Caixa sem modelo aprovado (antes do número oficial) → fora da janela não envia; vira silêncio direto.
- Só leads na etapa `fase-documentos` (os de Fechado nunca entram).
- `LeadRadar#active_leads` filtra `is_won: false`: Documentos fica fora de parados/cadência — decidir aqui.

## Review Focus

1. Cliente responde às 23h → a IA responde (permissão `fora_do_horario`), mas o próximo lembrete só sai em horário comercial e o relógio zera.
2. Documento chega pelo Painel do Cliente (não pela conversa) → conta como "documento novo" para acompanhamento/travado.
3. Lead sai de Documentos no meio (completo, perdido, arrastado) → nenhuma cobrança pendente sai depois.
4. Job roda duas vezes no mesmo minuto → um lembrete só (idempotência por marca no lead).
5. Feriado nacional → conta como dia não útil se a janela de horário dos fluxos já souber; se não souber, registrar a limitação (não inventar calendário).

---

### Task 1: relógio puro — `Ramon::Documentos::Relogio`

- **Files:** Create `app/services/ramon/documentos/relogio.rb`; Test.
- **Interfaces — Produces:** `Relogio.proximo_passo(estado:, agora:, horario:) -> { passo: Symbol, em: Time } | nil`, passos `:abertura, :lembrete_1, :lembrete_2, :silencio, :acompanhamento, :travado`; `estado` = hash de `custom_attributes.documentos_cobranca` (`entrou_em`, `ultima_resposta_em`, `ultimo_documento_em`, `abertura_em`, `lembrete_1_em`, `lembrete_2_em`, `acompanhamento_em`, `silencio_em`, `travado_em`); `horario` = a janela de horário dos fluxos (`Ramon::Fluxos::Horario` — reaproveitar a conta de "hora útil").
- **Tests:** tabela de casos cobrindo o ritmo inteiro, o teto de 2, a resposta que zera e o Review Focus 1 e 5.

### Task 2: canal de envio — texto livre ou modelo

- **Files:** Create `app/services/ramon/documentos/envio.rb`; Test.
- **Interfaces — Produces:** `Envio.mandar(lead, passo) -> :texto | :modelo | :sem_permissao` — dentro da janela, texto do passo (configuração do assistente Documentos, chaves `documentos.abertura`, `documentos.lembrete_1`, `documentos.lembrete_2`; `nil` = desligado); fora, modelo configurado (`documentos.modelo_nome` + variáveis nome e "o que falta") pelo mesmo caminho que o hub já usa para mandar modelos (PR #166); sem modelo → `:sem_permissao`.
- **Tests:** janela aberta → mensagem de texto; fechada com modelo → mensagem de modelo com as variáveis; fechada sem modelo → nada enviado.

### Task 3: job recorrente — `Ramon::Documentos::CobrancaJob`

- **Files:** Create `app/jobs/ramon/documentos/cobranca_job.rb`; agenda em `config/schedule.yml` (a cada 15 min); Test.
- **Interfaces — Consumes:** `Relogio`, `Envio`, `Responsavel` e o handoff do PR 3. **Produces:** grava as marcas em `documentos_cobranca` com `update_column` (lição do B4.3: `update!` em jsonb dispara callbacks de cadência), sob `with_lock`.
- **Passos:** abertura/lembretes → `Envio`; `:sem_permissao` → silêncio; `:acompanhamento` → `AvisoDaIa.avisar` ao responsável, IA segue; `:silencio`/`:travado` → handoff ao responsável.
- **Tests:** Review Focus 3 e 4; os marcadores certos depois de cada passo.

### Task 4: relógio alimentado pelos eventos

- **Files:** listener de mensagem recebida (`ultima_resposta_em`) e o ponto onde `doc_status` vira recebido — conversa, Painel do Cliente, pessoa (`ultimo_documento_em`); entrada em Documentos (`entrou_em`, PR 2 Task 5); Tests.

### Task 5: registro e regra fixa

- **Files:** atividade no lead a cada envio (passo, canal); custo do modelo registrado em Uso e custo como linha de WhatsApp (valor da tabela em configuração: US$ 0,0068 utility BR, jul/2026); `db/seeds/ramon/fluxos/sistema/cobranca_documentos.json` (regra fixa, para aparecer na aba "Do sistema"); Tests.

### Task 6: textos (gate do Eduardo)

- Rascunho em `comercial\docs\`: abertura, lembrete 1, lembrete 2 e o modelo `cobranca_documentos` (utility, sem oferta). Submissão do modelo à Meta só depois do "aprovado".

### Task 7: revisão e PR

`mattpocock-skills:code-review` → `rubocop-vps` → PR (`mattpocock-skills:pr`) → CI → merge → deploy.
