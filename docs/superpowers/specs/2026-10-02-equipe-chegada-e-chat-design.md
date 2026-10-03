# Equipe — Chegada de cliente + Chat interno (design)

**Data:** 2026-10-02 · **Status:** design aprovado em conversa pelo Eduardo; spec aguardando revisão.

## Contexto

Hoje a recepção avisa a chegada de cliente "no grito" ou por WhatsApp — o aviso se perde
quando a advogada está concentrada ou com o hub em outra aba. Não existe conversa interna
da equipe dentro do hub (o Buzz cumpriu esse papel 31/07–17/08 e foi pausado por falta de
uso; app separado não pegou). A Portaria vai trazer a equipe toda pra dentro do hub, então
o lugar natural da conversa interna é o próprio hub.

**Objetivo:** (1) chegada de cliente com alerta impossível de ignorar e resposta de volta à
recepção; (2) chat da equipe (1:1, setor, Geral) dentro do hub.

**Sucesso:** a Gabriela avisa uma chegada em ≤ 3 cliques e sabe, sem levantar, se a pessoa
viu e o que respondeu; ninguém precisa de WhatsApp pessoal pra falar com colega no expediente.

## Decisões (Eduardo, 02/10)

| # | Decisão |
|---|---|
| D1 | Tudo dentro do hub (não religar o Buzz). Módulo próprio, **isolado das conversas de cliente** — não usa inbox/conversation do Chatwoot (evita lead automático, Captain, SLA, relatórios). |
| D2 | Chegada nasce de **botão da Recepção** (time `recepção` + administradores). |
| D3 | Cliente identificado por: tarefas **ATENDIMENTO** do dia no ADVBOX ("quem vem hoje"), **busca de cliente no ADVBOX por nome**, ou **campo livre nome + motivo** (agenda não é padronizada). |
| D4 | Alerta vai pra **uma pessoa escolhida**; sem resposta em **3 min** → alerta volta pra quem avisou. |
| D5 | Resposta = **texto livre**, volta pra tela da recepção. |
| D6 | Alcance: hub **aberto em alguma aba, inclusive de fundo** — overlay + som em loop + notificação do sistema + título piscando. Push com navegador fechado = fora do escopo. |
| D7 | Chat completo: **1:1, canal por setor (times do hub), Geral**. Só texto. **(02/10) As advogadas ficam no time `advogados`** (canal do setor = membros do time) **e continuam chamáveis sozinhas** (1:1 e destinatária da chegada são por pessoa, nunca por time). |
| D8 | Mensagem comum de chat = **aviso discreto** (não-lido, som curto, notificação do sistema). Só chegada é alerta insistente. |
| D9 | **Administradores leem tudo**, inclusive 1:1 — e a tela avisa isso à equipe. |

## Fatia 1 — Chegada de cliente

### Dados
`ramon_chegadas`: `account_id`, `criado_por_id` (user), `destinatario_id` (user),
`cliente_nome` (obrigatório), `motivo` (opcional), `advbox_customer_id` (opcional),
`advbox_post_id` (opcional — a tarefa ATENDIMENTO de origem), `resposta` (texto),
`respondido_em`, `escalado_em`, timestamps. Estado derivado: aguardando (sem resposta) /
respondido / escalado (sem resposta e `escalado_em`).

### Back-end
- `Ramon::ChegadasController` (sob `api/v1/accounts/:id/ramon/`):
  `index` (do dia — recepção/admin veem todas; demais só as suas),
  `create` (só recepção/admin — `ChegadaPolicy`), `responder` (só o destinatário).
- `Ramon::AgendaHojeService`: `AdvboxClient.posts(date_start: hoje, date_end: hoje)`,
  filtra tarefa `ATENDIMENTO`, devolve `{cliente, advbox_customer_id, post_id,
  responsavel_advbox}`; casa responsável ADVBOX → user do hub por e-mail (ADVBOX
  `settings.users[].email`), sem casamento = sem sugestão. Cache curto (5 min).
  ADVBOX fora do ar → lista vazia + aviso; campo livre sempre funciona.
- Busca de cliente: REUSA o endpoint existente `GET ramon_calculos/advbox_customers?q=` (front `ramonCalculos.advboxCustomers`).
- Eventos ActionCable (padrão do `lead.created`: `lib/events/types.rb` →
  `ActionCableListener` → `actionCable.js`): `ramon.chegada.created` pro `pubsub_token`
  do destinatário; `ramon.chegada.updated` pro criador e destinatário.
- `Ramon::ChegadaEscalarJob` agendado com `set(wait: 3.minutes)` no create: se ainda sem
  resposta, grava `escalado_em` e emite `updated` (o front do criador toca o alerta).
- Sem `Notification` no sino: a lista de chegadas do dia já é o histórico (YAGNI).
- ADVBOX tem cota de **500 chamadas/dia** (compartilhada) → agenda em cache de 10 min,
  `settings` (e-mails dos usuários) em cache de 24 h.

### Front-end
- **Botão flutuante "Chegou cliente"** em todas as telas (ao lado do lançador do Copilot,
  mesmo padrão do `FloatingCallWidget`), só pra recepção/admin. Abre um painel com 3
  abas: *Quem vem hoje* (clique preenche cliente + sugere destinatário), *Buscar no
  ADVBOX*, *Livre* (nome + motivo). Seletor de destinatário (agentes da conta). Enviar.
- **`AlertaChegada.vue`** montado em `App.vue` (global, acima de tudo): ouve o evento,
  abre overlay com cliente/motivo/quem avisou, toca `public/audio/dashboard/ringtone.mp3`
  em loop, dispara `new Notification(..., { requireInteraction: true })`, pisca o título.
  Campo de resposta + Enviar → para tudo. Várias chegadas = fila no mesmo overlay.
- **Lista "Aguardando"** no painel da recepção: chegadas do dia com cronômetro, resposta
  quando chega; escalada toca o mesmo alerta pra ela ("Dra. X não respondeu").
- Permissão de notificação: pedida no 1º clique de cada pessoa no hub (navegador exige gesto); sem permissão o
  overlay + som continuam funcionando.
- ⚠️ Autoplay: navegador só toca som após 1 interação na aba — o hub já tem login/clique,
  então na prática ok; documentar no smoke.

## Fatia 2 — Chat da equipe

### Dados
- `ramon_chat_canais`: `account_id`, `tipo` (`direto`|`setor`|`geral`), `team_id`
  (setor), `nome`. Um `geral` por conta; um `setor` por time; `direto` único por par.
- `ramon_chat_membros`: `canal_id`, `user_id`, `lido_ate` (timestamp) — só pra `direto`
  e controle de não-lido; membros de `setor` = membros do time (fonte da verdade é o
  time), de `geral` = agentes da conta. Linha de membro criada sob demanda pro `lido_ate`.
- `ramon_chat_mensagens`: `canal_id`, `autor_id`, `conteudo` (texto), timestamps.

### Back-end
- `Ramon::ChatController`: listar canais visíveis com contagem de não-lidas; mensagens
  paginadas; enviar; marcar lido; abrir/criar `direto` com um colega.
- `ChatCanalPolicy`: participante vê/escreve; **administrador vê tudo** (lê qualquer
  canal; não aparece como membro).
- Evento `ramon.chat.message` pros `pubsub_token` dos membros + administradores.

### Front-end
- Item **"Equipe"** no menu → página com lista de canais (Geral, setores, diretos) à
  esquerda e conversa à direita; badge de não-lidas no item do menu.
- Mensagem nova fora da conversa aberta: badge + som curto + notificação do sistema
  (sem `requireInteraction`). Aviso fixo no topo: "Administradores podem ler as conversas."

## Fora do escopo
Anexos · push com navegador fechado (VAPID/service worker) · celular/ntfy · TV da
recepção · check-in pelo cliente · editar/apagar mensagem · reações.

## Testes
- RSpec: policy da chegada (recepção/admin criam; só destinatário responde), escalada
  (job não escala respondida), `AgendaHojeService` (filtro ATENDIMENTO + casamento de
  e-mail, com resposta do ADVBOX stubada), visibilidade do chat (participante × admin ×
  estranho), contagem de não-lidas.
- Vitest: `AlertaChegada` (abre no evento, para som ao responder, fila).
- Smoke do Eduardo: nova seção no `comercial\docs\2026-09-14-smoke-consolidado.md`.

## Gates do Eduardo
1. Criar logins de quem ainda não tem e colocar cada pessoa no time certo
   (`recepção`, `controladoria`, `advogados`, `comercial`).
2. Cada pessoa clicar "Permitir notificações" no navegador do trabalho.
3. Smoke da Fatia 1 antes de iniciar a Fatia 2.

## Ordem
Fatia 1 (PR próprio, migração à mão no deploy) → smoke → Fatia 2 (PR próprio).
