# Botão "Painel do lead" + colheita automática da conversa — design

**Data:** 2026-07-20 · **Aprovado por:** Eduardo (na conversa)

## Problema

1. O acesso ao painel do lead na conversa é uma pílula flutuante solta na borda
   direita (`SidepanelSwitch.vue`), ícone de pessoa, tooltip "Contatos" — não
   comunica que ali vive o painel do lead (resumo, kit, simulador, histórico).
2. O checklist da colheita (`ColheitaChecklist.vue`) é 100% manual, mas a
   extração por IA (`Ramon::ColheitaExtractionService`) já lê a conversa
   inteira — só que dispara apenas pós-transcrição de áudio e não toca o
   checklist.

## Decisões (AskUserQuestion 20/07)

- Botão **com texto** no cabeçalho da conversa ("Painel do lead"), pílula some.
- Colheita **automática com marca verde** + selo ✨ IA; humano sempre vence.

## Design

### 1. Botão no cabeçalho

- `ConversationHeader.vue` (core → registrar no FORK-PONTOS): botão com ícone
  user + rótulo `CONVERSATION.SIDEBAR.CONTACT`, ao lado do Resolver; estado
  aceso quando `is_contact_sidebar_open`; clique alterna (fecha copilot).
- pt_BR `CONVERSATION.SIDEBAR.CONTACT`: "Contatos" → "Painel do lead" (título
  do `ContactPanel` muda junto, mesma chave).
- `SidepanelSwitch.vue`: prop `hideContact`; `ConversationView.vue` passa
  `true` — grupo inteiro some quando não há Copilot (flag CAPTAIN). InboxView
  fica intocada. Atalho Alt+O preservado.

### 2. Colheita automática

- **Gatilho:** `RamonLeadListener#message_created` — mensagem `incoming` de
  conversa com lead de tese auxílio-acidente agenda
  `Ramon::ColheitaExtractionJob.set(wait: 3.minutes).perform_later(message.id,
  debounce: true)`.
- **Debounce:** no job, se existir mensagem incoming mais nova que a do
  gatilho, retorna (a rajada converge pro job da última). Caminho
  pós-transcrição continua sem debounce.
- **Prompt:** ganha a lista de itens `section: colheita` da tese (id + título)
  e a chave `"checklist_ok": [ids]` no JSON de saída — só ids realmente
  respondidos na conversa.
- **Escrita:** ids validados contra a tese; grava `'ia'` em
  `custom_attributes.colheita_status` **apenas em chave ausente**. Veto
  humano: marcar = `true`, desmarcar = `false` explícito; IA nunca sobrescreve
  chave existente. `checklist_ok` não entra em `colheita.dados`.
- **UI (`ColheitaChecklist.vue`):** desmarcar grava `false` (não deleta mais a
  chave); item com valor `'ia'` mostra selo ✨ IA com tooltip.

## Fora do escopo

- Outras teses (schema de colheita só existe pra auxílio-acidente).
- Preencher campos do cadastro do lead com os dados extraídos (fatia futura).

## Testes

- Listener: agenda com debounce só pra incoming com lead; specs do referral
  intactas.
- Job: pula quando há incoming mais nova; roda quando é a última.
- Service: `checklist_ok` validado, merge respeita `true`/`false` existentes.
- Componente: selo IA, desmarcar → `false`, contagem soma `'ia'`.
