# Painel do Cliente — cliente.ramonantonio.adv.br (design)

**Data:** 08/09/2026 · **Dono:** Eduardo · **Status:** aprovado (grill de 20 perguntas + 2 de
arquitetura + 4 seções de desenho, todas aprovadas na sessão de 08/09).

## 1. Problema e resultado esperado

O cliente da banca não tem onde ver o próprio processo. Hoje pergunta por WhatsApp, e a
resposta depende de memória da equipe (POPs ATD-01/ATD-02 inexistentes). O painel dá ao
cliente, com login próprio, **só o que é dele** no ADVBOX: etapa em linguagem simples,
marcos, pendências de documentos com upload pela câmera do celular, e assinatura de
documentos pelo ZapSign, tudo numa página.

Isto **reverte** a decisão de 13/08 ("portal do cliente segue como apoio, WhatsApp em
primeiro") — o painel vira produto. Regras herdadas do hub: nada sai automático para o
cliente; sem valores; rodapé de compliance OAB.

## 2. O que já existe e é reaproveitado

| Peça | Onde | Uso no painel |
|---|---|---|
| Portal por link mágico (lead) | `app/controllers/public/portal_controller.rb`, layout `ramon_portal` | Molde de controller, layout e validação de upload. Continua existindo para leads. |
| Cliente ADVBOX | `lib/ramon/advbox_client.rb` | `lawsuits(identification:)`, `movements`, `posts`, `create_post`. Limite 500/dia/rota. |
| ZapSign | `lib/ramon/zapsign_client.rb`, `app/services/ramon/zapsign_contract_service.rb` | `create_doc_from_template`; novos `doc(token)` e `update_signer`. |
| Google Drive | `lib/ramon/drive_client.rb`, `app/services/ramon/drive_export_service.rb` | Pasta `Clientes/<Nome — CPF>/` (ou `… — COMPLETO`). |
| Busca de cliente ADVBOX | `GET /api/v1/accounts/:id/ramon_calculos/advbox_customers?q=` | Tela de convite no hub. |
| Aviso ao Eduardo | `Ramon::NtfyPushJob.perform_later(nil, title:, body:)` | Upload recebido. |
| Página ramon no dashboard | `ramon_reunioes_controller.rb`, `pages/Reunioes.vue`, `api/reunioes.js`, `reuniao_policy.rb` | Molde da tela "Painel do cliente". |
| Webhook público | `app/controllers/public/api/v1/advbox_webhooks_controller.rb` | Molde do webhook ZapSign. |

## 3. Decisões fechadas

| # | Decisão |
|---|---|
| Q1 | Só cliente com processo no ADVBOX tem conta (customer identificado por CPF). |
| Q2/Q7 | Andamentos **curados**: dicionário etapa→texto simples + só marcos reconhecidos; "recado ao cliente" opcional por processo, escrito no hub. |
| Q3 | Login = e-mail + código de 6 dígitos (10 min), sem senha. Sessão 30 dias no aparelho. |
| Q4 | Entrega única (consulta + documentos + assinatura). |
| Q5/Q13 | Evoluir o hub, servido em `cliente.ramonantonio.adv.br` (Caddy → mesmo container). |
| Q6 | Espelho sincronizado 1x/noite + botão "Atualizar" (máx. 1 a cada 6 h por cliente). |
| Q8 | Nenhum download. Cliente só faz upload (câmera/galeria/PDF). |
| Q9/Q14/Q20 | Assinatura de docs criados **pelo hub** (cliente + modelo ZapSign + variáveis); widget embutido; `assinaturaTela`; webhook marca assinado. |
| Q10 | Upload → Drive + tarefa ADVBOX "ANALISAR DOCUMENTAÇÃO ENVIADA PELO CLIENTE" (tasks_id 9502039) + aviso ntfy. |
| Q11/Q17 | Pedido = tarefa ADVBOX "SOLICITAR DOCUMENTOS" (tasks_id 8745528) no processo; cada linha das observações = 1 item; some quando `users[].completed` preenchido. |
| Q12 | Convite manual pelo hub (por cliente ou lote). Sem e-mail de novidade no v1. |
| Q15 | Tela do processo: etapa traduzida + "o que esperar"; timeline de marcos; nº/tipo/data/responsável; botão WhatsApp. Sem financeiro. |
| Q16/Q18 | Encerrados = `step == 'ARQUIVAMENTO'`, seção separada. |
| Q19 | Aceite de termos no 1º acesso (timestamp) + política de privacidade nova no site. |
| Arq. 1 | Espelho = um retrato JSON por cliente (`portal_clientes.processos`), refeito à noite no Sidekiq. Sem IA, sem custo novo. |
| Arq. 2 | Tela do escritório = página "Painel do cliente" no menu lateral do hub. |

## 4. Desenho

### 4.1 Entrada e tela do processo
`cliente.ramonantonio.adv.br` → `/cliente` (form e-mail) → código por e-mail → cookie
criptografado 30 dias → termos no 1º acesso → lista (ativos / encerrados) → processo:
etapa traduzida + "o que esperar", marcos (perícia, audiência, protocolo, sentença,
benefício concedido), identificação, recado, WhatsApp, pendências, "Atualizar".
E-mail desconhecido recebe resposta neutra (não revela se existe conta).

### 4.2 Documentos
Pendências = linhas de `notes` das tarefas SOLICITAR DOCUMENTOS abertas no processo.
Upload (PDF/JPG/PNG/HEIC ≤10 MB, tipo real por magic bytes, `accept="image/*,application/pdf"`
sem `capture` para não bloquear a galeria no iOS) → `PortalEnvio` → job: Drive → tarefa
ADVBOX ANALISAR DOCUMENTAÇÃO para o responsável do processo (comentário com link do Drive)
→ ntfy → item "Enviado, em conferência" até a tarefa de solicitação ser concluída no ADVBOX.

### 4.3 Assinatura
Hub: cliente + modelo + variáveis → `create_doc_from_template` (`send_automatic_email: false`)
→ `PortalAssinatura` (doc_token, signer_token). Painel: card "Assinatura pendente" → iframe
`https://app.zapsign.com.br/verificar/<signer_token>` (`allow="camera"`). Webhook
`doc_signed` (header secreto, `secure_compare`) → job re-GET `/docs/{token}/` → `signed`.

### 4.4 Espelho e tela do hub
`Ramon::PortalSyncJob` 00:30 BRT: por cliente `lawsuits(identification: cpf)` + por
processo `movements` + `posts`. Orçamento ≈ 3 chamadas/processo/dia; cabe até ~250
clientes sem otimizar (depois: varrer `/last_movements` e re-buscar só o que mudou).
Tela "Painel do cliente": busca cliente ADVBOX → convidar (e-mail do ADVBOX, editável) →
lista com status/sync/envios → "Reenviar convite", "Recado", "Enviar pra assinatura".

## 5. Modelo de dados

- `portal_clientes`: `account_id`, `advbox_customer_id`, `nome`, `cpf`, `email`,
  `codigo_digest`, `codigo_expira_em`, `convidado_em`, `termos_aceitos_em`, `sincronizado_em`,
  `atualizacao_pedida_em`, `processos jsonb []`, `recados jsonb {}`. Únicos:
  `[account_id, advbox_customer_id]`, `[account_id, email]`.
- `portal_assinaturas`: `portal_cliente_id`, `doc_token` (unique), `signer_token`, `nome`,
  `status`, `assinado_em`.
- `portal_envios`: `portal_cliente_id`, `lawsuit_id`, `item`, `drive_file_id`,
  `advbox_post_id`, `has_one_attached :arquivo`.

Namespace `Cliente::` (o model `Portal` do help center já existe). Rotas por path
`/cliente/...`; o Caddy redireciona `/` → `/cliente` no subdomínio.

## 6. Erros e limites
- ADVBOX fora: sync loga e segue para o próximo cliente; "Atualizar" mostra aviso e mantém
  o espelho antigo. `retry_on UnavailableError` nos jobs de escrita.
- Código: 5/15 min por e-mail, 10/15 min por IP; envios 20/h por IP; webhook 60/min.
- Drive não configurado: envio fica só no hub (ActiveStorage) e a tarefa ADVBOX avisa.
- Cookie host-only: sessão do painel não vaza para `chat.`.

## 7. Entrega (6 PRs) e gates
PR1 modelos → PR2 dicionário + sync → PR3 portal (leitura) → PR4 tela do hub → PR5 upload
→ PR6 ZapSign. Plano detalhado em `docs/superpowers/plans/2026-09-08-painel-do-cliente.md`.

Gates do Eduardo: DNS + bloco Caddy + envs (`PORTAL_URL`, `ZAPSIGN_WEBHOOK_SECRET`);
`db:migrate` na VPS; webhook no painel ZapSign; aprovar dicionário de etapas, e-mails,
termos, política de privacidade e textos do painel; entrada no `comercial/decision-log.md`.

## 8. Não confirmado (testar no 1º sync real)
Filtro `/lawsuits?identification=<CPF>`; endpoint de modelo do ZapSign aceitar
`auth_mode`/`signer_email`; nome do header customizado do webhook ZapSign.
