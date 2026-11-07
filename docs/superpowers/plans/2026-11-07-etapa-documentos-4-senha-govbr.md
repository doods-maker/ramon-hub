# Etapa Documentos · PR 4 — senha gov.br criptografada — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. **Nível de task: refinar antes de executar.** Caminho de segurança: nada de atalho.
> **Skills do Matt:** `mattpocock-skills:tdd` em toda task; `mattpocock-skills:codebase-design` na Task 2 (fluxo da senha: a IA nunca carrega o valor); `mattpocock-skills:code-review` antes do merge; `mattpocock-skills:pr` no corpo.

**Goal:** a IA pede a senha gov.br; o hub guarda criptografada, apaga da conversa e chama uma pessoa; só papéis autorizados veem.

**Spec:** seção 4. **Depende dos PRs 2 e 3.**

## Global Constraints

- `encrypts` do Active Record exige `Chatwoot.encryption_configured?` em produção (já é exigido pelo Google Agenda, `google_agenda_callbacks_controller.rb:54`); a coluna só aceita gravação com a cifra configurada — sem ela, o tool recusa e chama a pessoa.
- A senha nunca vai para: prompt, log (`Rails.logger`), exception tracker, push, ADVBOX, `push_event_data`/broadcast, JSON da API fora do endpoint de revelar.

## Review Focus

1. Cliente manda a senha junto com outro texto ("minha senha é X, obrigado") → o tool guarda só a mensagem indicada inteira e a apaga inteira; o agente pede de novo "só a senha" se for o caso.
2. A IA chama o tool com uma mensagem que não é do cliente (outgoing / de outra conversa) → recusa.
3. Agente sem permissão abre o painel → não vê nem o botão de revelar.
4. Resumo da conversa / memória / FAQ gerados depois → não contêm a senha (a mensagem já foi trocada).
5. Webhook de saída do Chatwoot (`message_updated`) → não reenvia o conteúdo original.

---

### Task 1: coluna criptografada e permissão de leitura

- **Files:** migração `add_column :leads, :senha_govbr, :text`; `app/models/lead.rb` (`encrypts :senha_govbr`; fora de `push_event_data` e dos jbuilders); Test model spec (valor não aparece em `attributes_before_type_cast` legível; `push_event_data` sem a chave).
- **Interfaces — Produces:** `Lead#senha_govbr` (string), `Ramon::Documentos::SenhaGovbr.pode_ver?(user, account) -> Boolean` = admin, time `sdr`, `closer` ou `advogados` (`Ramon::Papeis`).

### Task 2: tool `registrar_senha_govbr(message_id)`

- **Files:** Create `enterprise/lib/captain/tools/registrar_senha_govbr_tool.rb` (registrar no `tool_registry_service.rb` e só liberar no perfil da etapa Documentos), Create `app/services/ramon/documentos/senha_govbr.rb`; Tests.
- **Interfaces — Produces:** `Ramon::Documentos::SenhaGovbr.registrar!(conversation:, message_id:) -> :ok | :recusada` — mensagem precisa ser `incoming` da mesma conversa; grava `lead.senha_govbr`; troca `content` (e `processed_message_content`) por "senha recebida 🔒" sem disparar reenvio ao canal; registra no Registro de ações ("senha gov.br recebida", sem valor); dispara o gatilho `govbr_senha_recebida` (handoff do PR 3).
- **O argumento é o id, nunca a senha:** a descrição do tool diz isso; o modelo nunca repete o valor.
- **Tests:** os 5 do Review Focus que cabem em teste unitário (1, 2, 4 com um job de resumo stubado, 5 conferindo o evento disparado).

### Task 3: revelar no painel, com rastro

- **Files:** endpoint `GET .../leads/:id/senha_govbr` (só `pode_ver?`, grava atividade "senha vista por <usuário>" no Registro de ações); `LeadPanelBody.vue` (campo "Senha gov.br" com botão revelar/copiar, só para quem pode); i18n `en.json`/`pt_BR`; Tests request + vitest.

### Task 4: instruções e textos (gate do Eduardo)

- Rascunho em `comercial\docs\`: quando pedir a senha (depois do passo a passo não resolver), frase do pedido, frase de confirmação sem repetir o valor. Nada disso entra no código antes do "aprovado".

### Task 5: revisão e PR

`mattpocock-skills:code-review` com foco em vazamento (grep por `senha_govbr` em logs, serializers, jbuilders) → `rubocop-vps` → PR (`mattpocock-skills:pr`) → CI → merge → deploy com migração.
