# Automações em fluxo — B4.1 (agendamento de reuniões inteiro em sombra) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tudo que o `Ramon::ReuniaoAgendamento` faz — **marcar** (atividade, tarefa da reunião, etapa só para a frente, Closer automático, rascunho de confirmação nas notas do lead, sino para a conta e push), **remarcar** (atividade de→para, rascunho, sino, push), **cancelar** (atividade, tarefa apagada, sino, push) e os **5 lembretes de cada reunião** (24h · 8h · 1h · 30 min · 5 min, Closer + SDR) — ganha 3 fluxos de verdade que rodam **em sombra** ao lado do código, uma **comparação** legível código × fluxos da cadeia inteira, e **uma chave** (`RAMON_FLUXO_REUNIOES=on` + os 3 fluxos em modo `normal`) que, quando o Eduardo virar, faz os fluxos assumirem e o código parar. A chave nasce **desligada**: nada muda em produção até o Eduardo virar.

**Architecture:** 3 fluxos (`origem: usuario`, um por `sistema_chave`): **Reunião marcada** (gatilho `reuniao_marcada`, alvo o lead, `escolha` pelo `{evento}` marcada/remarcada, sem espera, roda **na hora**, dentro da requisição), **Reunião cancelada** (gatilho `reuniao_cancelada`, alvo o lead, na hora) e **Lembretes de reunião** (gatilho novo `reuniao_na_agenda`, **alvo a tarefa da reunião** — cada reunião tem o seu ciclo, que o índice único já separa sem migração). Cada evento do `ReuniaoAgendamento` decide **uma vez** quem faz (`Ramon::Fluxos::Reunioes.assumiu?`) e manda essa decisão (`assumido`) e os textos prontos do código no gatilho: código no comando → os fluxos ensaiam **antes** (veem o lead como estava) e o código faz tudo; fluxos no comando → o código só dispara. O motor ganha o mínimo para ser fiel: `esperar` antes da reunião, `{reuniao_de_pe}`, sino para Closer+SDR ou para a conta, etapa "só para a frente", responsável "só se não tem", atividade com tipo/de→para/quem marcou, tarefa "da reunião", rascunho nas notas do lead com o título do código, passo `apagar_reuniao`. Sem migração.

**Tech Stack:** Rails 7.1 / RSpec (só no CI), Postgres jsonb, Sidekiq (ActiveJob); Vue 3.5 `<script setup>`, vue-i18n 9, Vitest 3 + @vue/test-utils.

**Spec:** `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (§3 vocabulário — modo sombra, §4 peças, §6 motor — sombra = ensaio, §8 migração B4+, §13 notas da B2b, §14 notas da B3 — "B4: o fluxo em sombra é um fluxo próprio (origem `usuario`)…"). Plano de referência de estilo: `docs/superpowers/plans/2026-10-06-automacoes-fluxo-b3.md`.

## Escopo decidido pelo Eduardo em 06/10 (vence a spec e a 1ª versão deste plano)

1. **E1 — a cadeia inteira migra**, não só os lembretes: marcar, remarcar, cancelar e os 5 lembretes. O rascunho de confirmação continua **rascunho** nas notas do lead, com o texto **copiado do código**.
2. **E2 — textos internos (sino/push) podem mudar** (o sino de fluxo chega como "Automação: … (nome)").
3. **E3 — lembretes de CADA reunião aberta:** lead com 2 reuniões recebe os 2 ciclos; remarcar recomeça só o ciclo daquela reunião; cancelar para só o dela.
4. **E4 — critério:** ≥ 7 dias, ≥ 15 lembretes comparados e 0 divergência sem explicação — agora contando também agendamentos e cancelamentos comparados.
5. **E5 — chave:** uma env + modo normal em **todos** os fluxos migrados da conta; voltar = modo sombra, sem deploy.
6. **E6 — depois de assumir, os fluxos são editáveis por admin** (uma edição errada tira o efeito correspondente).
7. **E7 — limpeza** (apagar o código antigo, o desenho e a linha do sistema, a env) num PR separado, depois de 2 semanas em normal sem incidente.

## Global Constraints

- Base: produção **71e1ce0** (B1 motor, B2 quadro, B2b IA/ADVBOX/webhook/gatilhos externos/relógio e B3 aba Do sistema no ar); branch `feat/fluxos-b4-lembretes`, worktree `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-fluxos-b4`. Nunca `git push`, nunca abrir PR (gate do Eduardo / sessão principal).
- **Produção não muda até o Eduardo virar a chave.** Com `RAMON_FLUXO_REUNIOES` ausente/`off` (padrão) o código marca, remarca, cancela e lembra exatamente como hoje. Os fluxos só nascem quando alguém roda o rake `ramon:fluxos:reunioes:sombra` (depois do deploy) e, enquanto o código estiver no comando, só ensaiam (não escrevem nada fora da própria execução).
- **Não apagar nada do caminho antigo nesta fatia:** o código de `Ramon::ReuniaoAgendamento`, o `Ramon::MeetingReminderJob` e o desenho `db/seeds/ramon/fluxos/sistema/lembretes_reuniao.json` (e a linha `origem: sistema` dele) ficam (E7).
- **Sem migração.** `ramon_fluxos` já tem `origem`, `sistema_chave`, `modo`, `rascunho`, `ativo`; `ramon_fluxo_execucoes` já tem `ensaio`, `contexto`, `trilha` e `alvo_type/alvo_id` polimórfico (aceita `LeadTask`). O índice único parcial `index_ramon_fluxo_execucoes_unica_ativa` `(fluxo_id, alvo_type, alvo_id) WHERE status IN ('rodando','esperando') AND NOT ensaio` (`db/schema.rb:1511`) já separa um ciclo por tarefa de reunião. Se alguma task achar que precisa de coluna/índice: pare e pergunte (migração exigiria regenerar `db/schema.rb` por scratch DB na VPS — não há Postgres local).
- **Rubocop do fork** (o CI barra): `Metrics/AbcSize` 26, `Metrics/MethodLength` 19, `Metrics/CyclomaticComplexity` 7, `Metrics/PerceivedComplexity` 8, `Metrics/ClassLength` 175, `Metrics/ModuleLength` 100, `Metrics/BlockLength` 30 (fora de spec), linha 150, `Style/HashSyntax` `EnforcedShorthandSyntax: never` (sempre `chave: valor`), `rubocop-rspec` (`RSpec/MultipleExpectations` 7, `RSpec/ExampleLength` 50, `RSpec/SpecFilePathFormat`: spec de `A::B::C` em `spec/.../a/b/c_spec.rb`). **`app/models/lead.rb`, `app/services/ramon/advbox_event_processor.rb` e `app/finders/conversation_finder.rb` estão NO LIMITE de 175 linhas: nenhuma linha nova neles** (este plano não toca nenhum dos três). Tamanhos na base: `reuniao_agendamento.rb` 126 linhas (vai a ~160 com comentários; ~105 de código), `meeting_reminder_job.rb` 52 (~40), `contexto.rb` 87 (~120), `disparo.rb` 97 (~130), `executor.rb` 144 (~150), `passos/lead.rb` 81 (~120; ~80 de código < 100).
- **CI FOSS apaga `enterprise/`:** todo código que toque `Captain::*` fica atrás de `ChatwootApp.enterprise?` e o spec dele com `if: ChatwootApp.enterprise?`. A B4.1 não toca Captain — se precisar, pare.
- **Sem Ruby local:** specs Ruby são escritos e conferidos à mão (rastrear cada linha) e quem valida é o CI. Spec que viaja no tempo usa `travel_to`/`travel` em blocos **em sequência** (nunca um dentro do outro); código que o spec faz viajar nunca usa `NOW()` do SQL (só `Time.current`). Helper de spec que cria execução viva (`ctx` de `passos_spec.rb`, `execucao` de `contexto_spec.rb`) é chamado **uma vez por exemplo** (o índice único parcial barra 2 execuções `rodando/esperando` não-ensaio no mesmo fluxo+alvo).
- **Mensagem ao cliente SEMPRE rascunho; só admin edita.** O único texto ao cliente da cadeia é o rascunho de confirmação, que nasce como nota `RASCUNHO (revisar antes de enviar) — confirmação de reunião:` nas notas do lead, **texto copiado do código** (Task 7 confere caractere a caractere). Nenhum passo envia nada. A API de fluxos segue admin-only (`RamonFluxoPolicy#gerenciar?`).
- **Front:** i18n só dentro de `CAPTAIN_RAMON.FLUXOS` em `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json`, chaves novas na **mesma posição** nos dois arquivos (a trava `specs/i18n.spec.js` compara a ordem, cobre o catálogo e compila no vue-i18n de produção); strings sem `@`, `|`, `{`, `}` crus (só `{tempo}`); editar os JSON à mão (Edit). Tailwind only, kit `ramon/helpers/ui.js` (`TOM`, `ROTULO`, `CAMPO`, `SELECT`), evento custom camelCase, toda `<ul>/<ol>` nova com `list-none` (a B4.1 não cria lista), sem texto cru no template.
- **Vitest:** `node_modules` é junção para `ramon-hub-wt-fluxos-b2\node_modules` (nunca `rm -rf node_modules`). Config local **já criado e fora do git** `vitest.local.config.ts` na raiz do worktree (não commitar):
  `TZ=UTC npx vitest run <arquivos ou pastas> --config vitest.local.config.ts`
  Baseline medido na base 71e1ce0: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs` = **14 arquivos, 163 testes**. ESLint: `./node_modules/.bin/eslint <arquivos>` (erro `Delete ␍` = CRLF do checkout Windows, ignorar; warnings `@intlify/vue-i18n/no-dynamic-keys` já existem e são aceitos).
- **Commits:** Conventional Commits em pt-BR, sem citar Claude no assunto; corpo termina com:
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv`
  Commitar só os caminhos da task (`git add <arquivos>`), nunca `git add -A`.
- **PR #216 (outra sessão):** perda exige `lost_reason` (presença, `app/models/concerns/lead_comercial.rb` ~63-65) e a automação recebe "Automação: <fluxo>" sozinha. Em 06/10 ainda não estava em `origin/ramon` (topo `aefe23a6e1`): a Task 10 é escrita contra esse contrato e o executor **rebaseia sobre o #216** antes dela (e antes do merge).

## Review Focus

1. **A virada no meio de um evento** (alguém marca reunião no exato momento em que o rake vira os fluxos para normal, ou um dos 3 fluxos é desligado na tela) — o rascunho de confirmação, a tarefa e o sino saem **uma vez**: nem pelos dois, nem por nenhum. Teste: Task 6 ("o evento decide uma vez…", "com os fluxos no comando…") e Task 7 ("um fluxo desligado na tela devolve tudo ao código…").
2. **Lead com duas reuniões abertas** (painel com "forçar", ou Cal.com) e **remarcar/cancelar uma delas** — os dois ciclos de lembrete correm; remarcar recomeça só o daquela reunião; cancelar para só o dela. Teste: Task 3 ("cada reunião tem o seu ciclo…") e Task 7 ("cada reunião tem o seu ciclo; cancelar uma não mexe na outra").
3. **Lead que muda de etapa antes da reunião / reunião marcada em cima da hora** — os lembretes seguem (o código não cancela por etapa) e nenhum lembrete "atrasado" sai na hora da marcação. Teste: Task 2 ("horário já passado…") e Task 7 ("lead que muda de etapa…", ciclo de 10h com 4 lembretes).
4. **Ensaio que olha o lead depois do código** (etapa já movida, Closer já atribuído) — a sombra diria "já está adiante/já tem Closer" e a comparação acusaria divergência falsa; o ensaio tem de rodar **antes** dos efeitos do código. Teste: Task 6 ("…o ensaio dos fluxos vem antes") e Task 8 ("em sombra de verdade… marcar, remarcar e cancelar batem").
5. **Comparação desonesta** (aviso do sino apagado pelo teto de 300 por pessoa, "Testar com um lead…", evento que só um dos lados viu, efeito que só um dos lados fez) — não acusar divergência falsa nem esconder uma real. Teste: Task 8 (os 7 exemplos).

---

## Como os fluxos ficam fiéis ao código (decisões de desenho)

### O que o código faz × o que os fluxos fazem

| Evento | O código faz hoje (`Ramon::ReuniaoAgendamento`, `MeetingReminderJob`) | O fluxo faz (B4.1) |
|---|---|---|
| marcar | atividade `meeting_scheduled` (`user` = quem marcou, `to_value` = "Título em dd/mm/aaaa HH:MM") | **Reunião marcada** → caso "Marcada": `registrar_atividade {tipo: meeting_scheduled, texto: '{resumo}'}` (user = `quem_marcou_id` do gatilho) |
| | tarefa `meeting` (título = `task_title`, com o prefixo do Cal.com; vence na hora; dona = quem marcou) | `criar_tarefa {titulo: '{titulo_tarefa}', tipo: meeting, prazo: 'reuniao'}` (vence em `inicio`, dona = quem marcou) — e põe a reunião na agenda (dispara `reuniao_na_agenda` com a tarefa) |
| | etapa → "Reunião agendada", **só para a frente** | `mover_etapa {etapa_id: <da conta>, so_para_frente: true}` |
| | Closer automático **só se o lead não tem** (`Papeis.atribuir_closer!` → `Papeis.proximo`) | `trocar_responsavel {papel: closer, so_se_vazio: true}` (a mesma `Papeis.proximo`) |
| | rascunho de confirmação nas **notas do lead** (cabeçalho "RASCUNHO (revisar antes de enviar) — confirmação de reunião:") | `rascunho_texto {onde: notas_do_lead, titulo: 'confirmação de reunião', texto: <cópia do código com {primeiro_nome} e {quando}>}` |
| | sino `ramon_meeting_scheduled` para **toda a conta** + push "Reuniao marcada: Nome" / "quando — título" | `avisar_sino {para: conta}` + `avisar_push` (textos: E2) |
| | 5 jobs de lembrete (só os ainda futuros) | ver "lembretes" |
| remarcar | **move a tarefa** (`due_at`) + atividade `meeting_rescheduled` (de→para) + rascunho + lembretes do horário novo + sino/push "remarcada" | o **código continua movendo a tarefa** (é a remarcação em si — Decisão N1); **Reunião marcada** → caso "Remarcada": `registrar_atividade {tipo: meeting_rescheduled, de: '{resumo_antes}', texto: '{resumo}'}` + o mesmo rascunho, sino e push; o código dispara `reuniao_na_agenda` com a tarefa movida |
| cancelar (painel e Cal.com) | atividade `meeting_cancelled` + **apaga a(s) tarefa(s)** + sino `ramon_meeting_cancelled` + push | **Reunião cancelada**: `registrar_atividade {tipo: meeting_cancelled}` → `apagar_reuniao` (as tarefas do evento, `tarefa_ids` no gatilho) → sino conta → push |
| lembretes | por reunião: espera até 24h/8h/1h/30min/5min antes; descarta se a tarefa não segue aberta naquele horário (±60 s); Closer + SDR, sem nenhum → administradores; push | **Lembretes de reunião** (alvo = a tarefa): 5 × `esperar {antes_de: 'reuniao'}` → `se {reuniao_de_pe = sim E horario_passou = nao}` → sino `para: closer_e_sdr` → push. Remarcar = novo `reuniao_na_agenda` da mesma tarefa → cancela o ciclo que esperava e recomeça (só o dela). Cancelar = tarefa apagada → o ciclo dela é cancelado ao retomar ("o alvo foi apagado") |
| Cal.com remarcado | apaga as tarefas Cal.com abertas do lead e marca de novo | igual: o **apagar do Cal.com fica no controller** (é a integração — N1) e o "marcar" segue o caminho acima |

Regras únicas (uma função só, usada pelo código e pelos fluxos): `Ramon::Fluxos::Reunioes.reuniao_aberta?` (o guard do job = `{reuniao_de_pe}`) e `.destinatarios` (o sino do lembrete = `para: closer_e_sdr`). Os textos que dependem do código (`resumo`, `resumo_antes`, `quando`, `primeiro_nome`, `titulo`, `titulo_tarefa`) **vêm prontos no gatilho**, calculados pelo próprio `ReuniaoAgendamento` — o fluxo escreve igual sem lógica nova.

### Por que 3 fluxos, e por que o alvo dos lembretes é a tarefa (E3 sem migração)

- Um fluxo tem 1 gatilho (D2). Marcar e remarcar já chegam pelo mesmo gatilho (`reuniao_marcada`, nota B2b) → **um fluxo com `escolha` pelo `{evento}`**, os dois ramos se juntam no rascunho. Cancelar tem gatilho próprio (`reuniao_cancelada`, desde a B2b) → segundo fluxo. Os lembretes esperam horas → precisam de um alvo **por reunião** → terceiro fluxo.
- O índice único é `(fluxo, alvo_type, alvo_id)`. Com o **alvo = a tarefa da reunião** (`LeadTask`), duas reuniões do mesmo lead são dois alvos → dois ciclos vivos, sem coluna nova nem índice novo. Remarcar é a mesma tarefa → o novo disparo cancela só a espera daquele alvo (`Disparo::RECOMECA`). Cancelar apaga a tarefa → o `Executor` já cancela execução de alvo apagado. Alternativa descartada: coluna `chave` + índice novo (migração) — mais cara e, com a chave = horário, a ida e volta do remarcar engoliria os efeitos do 2º evento.
- O motor passa a aceitar `LeadTask` como alvo (lead e conversa vêm da tarefa) — Task 3.
- O gatilho novo `reuniao_na_agenda` nasce de quem pôs a reunião na agenda: o código (em sombra: ao criar a tarefa; sempre: ao mover a tarefa no remarcar) ou o passo `criar_tarefa {prazo: 'reuniao'}` (com os fluxos no comando). Não é um callback de `LeadTask`: tarefas de reunião criadas por fora (ex.: `CopilotSuggestion`) não têm lembrete no código e continuam sem.

### A decisão é do evento, não do fluxo (análise da virada)

- Cada evento (`call`, `remarcar`, `cancelar`) lê `Reunioes.assumiu?` **uma vez** e manda `'assumido' => true|false` no gatilho. Para os 3 fluxos migrados, o `Disparo` usa **essa** decisão para ensaiar ou agir (não o `modo` do fluxo). Assim: código e fluxos nunca agem os dois no mesmo evento, e nunca nenhum dos dois — mesmo se o rake virar os fluxos no meio da requisição, ou se alguém desligar um dos 3 na tela (aí `assumiu?` dá falso → o código faz tudo e os fluxos ligados ensaiam).
- `assumiu?` = env `RAMON_FLUXO_REUNIOES=on` **e** os 3 fluxos migrados ligados, publicados, em `modo: normal` e com o gatilho esperado. Qualquer peça fora → código no comando. Por isso qualquer volta é segura: rake `modo sombra`, env desligada ou um fluxo desligado na tela.
- **Ensaio antes do código:** com o código no comando, o gatilho dispara **antes** dos efeitos e os fluxos "Reunião marcada/cancelada" rodam **na hora** (dentro da requisição, `Disparo::NA_HORA`) → o ensaio vê o lead como estava (etapa, Closer), igual à decisão que o código toma logo em seguida. Com os fluxos no comando, rodar na hora mantém o painel igual (a tarefa existe quando a tela recarrega) e o `Current.user` da requisição (quem marcou) nas atividades automáticas.
- **Entre eventos de uma mesma reunião** (marcada num modo, remarcada/cancelada no outro): os jobs do código já na fila não consultam a chave e o guard deles (tarefa aberta no horário) descarta o que ficou órfão; o ciclo do fluxo que esperava é cancelado pelo novo `reuniao_na_agenda` (remarcar) ou pela tarefa apagada (cancelar); o ciclo novo nasce ensaio ou de verdade conforme a decisão do evento. Resultado: em todas as 4 combinações, um lembrete sai por um lado só.
- **Teto conhecido:** com os fluxos no comando, dois eventos do **mesmo lead** na mesma fração de segundo (ex.: duplo clique em "marcar") — o 2º bate no índice único do fluxo "Reunião marcada" e é ignorado (o código de hoje criaria 2 reuniões). E um passo que falhe na hora (ex.: banco fora) faz a execução tentar de novo em 1/5/15 min: a tarefa/rascunho aparece com atraso, não em dobro (o executor grava a cada passo). Decisão N2.

### Por que a comparação lê os rastros do código

O código não grava um "log de automação". Mas cada efeito deixa rastro próprio: atividades (`meeting_*`, `stage_changed`, `closer_changed`), tarefas, notas, sinos (`ramon_meeting_scheduled/cancelled/reminder`). A comparação põe cada efeito numa frase canônica e compara com a frase do ensaio (`faria: …`, sem o prefixo):

| Efeito | Frase do código (rastro) | Frase do ensaio |
|---|---|---|
| atividade de reunião | `atividade <kind>: [de → ]para` | `faria: atividade <tipo>: [de → ]texto` |
| tarefa | `tarefa "<título>" para dd/mm HH:MM` | `faria: tarefa "<título>" para dd/mm HH:MM` |
| etapa | atividade `stage_changed` → `mover para <etapa>` | `faria: mover para <etapa>` (só para a frente e já adiante: sem `faria:`) |
| Closer | atividade `closer_changed` → `closer → <nome>` | `faria: closer → <nome>` (já tem: sem `faria:`) |
| rascunho | nota "RASCUNHO … — confirmação de reunião:" → `rascunho "<corpo, 120>"` | `faria: rascunho "<texto, 120>"` |
| sino | avisos `ramon_meeting_scheduled/cancelled` → `sino para <nomes>` | `faria: sino para <nomes>: "…"` → `sino para <nomes>` |
| tarefas apagadas | as `tarefa_ids` do evento não existem mais → `apagar tarefas #id` | `faria: apagar tarefas #id` |
| lembrete | aviso `ramon_meeting_reminder` (lead, rótulo, pessoas) | linha `faria: sino para …` do ciclo (lead, horário ±3 min, pessoas) |

O push não deixa rastro no código → fica fora. Limites tratados: o Chatwoot apaga todo dia o que passa de 300 avisos por pessoa (`Notification::RemoveOldNotificationJob`) → a comparação começa depois do aviso mais antigo que sobrou de quem bateu o teto, e roda **todo dia** (operação); quem apaga um aviso na mão gera divergência (falso alarme, nunca falso "bateu").

## Mapa de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `app/services/ramon/fluxos/reunioes.rb` (novo) | regras únicas (`reuniao_aberta?`, `destinatarios`), os 3 fluxos (`GATILHOS`, `migrado?`, `fluxos`, `fluxo`, `semear`), `na_agenda`, a chave (`ligada?`, `assumiu?`, `mudar_modo!`, `descrever`) |
| `app/services/ramon/fluxos/passos/reuniao.rb` (novo) | passo `apagar_reuniao` |
| `app/services/ramon/fluxos/comparar_agendamentos.rb` (novo) | comparação marcar/remarcar/cancelar |
| `app/services/ramon/fluxos/comparar_lembretes.rb` (novo) | comparação dos lembretes + `inicio` (começo honesto) + `PESSOAS` |
| `db/seeds/ramon/fluxos/migrados/{reuniao_marcada,reuniao_cancelada,lembretes_reuniao}.json` (novos) | os 3 desenhos |
| `lib/tasks/ramon_fluxos.rake` (novo) | `ramon:fluxos:reunioes:{sombra,modo,comparar}` |
| `app/services/ramon/reuniao_agendamento.rb` | decisão por evento, gatilho com os textos prontos, ensaio antes, `cancelar_tarefas` |
| `app/controllers/public/api/v1/calcom_webhooks_controller.rb` | cancelamento do Cal.com passa pelo `ReuniaoAgendamento` |
| `app/jobs/ramon/meeting_reminder_job.rb` | usa as regras únicas (sem mudança de comportamento) |
| `app/services/ramon/fluxos/{contexto,disparo,executor,grafo}.rb`, `app/models/fluxo_execucao.rb` | motor: variáveis/gatilho, `LeadTask` como alvo, `reuniao_na_agenda`, recomeçar, na hora, decisão do evento, desligar a sombra |
| `app/services/ramon/fluxos/passos/{logica,aviso,lead,conversa}.rb` | esperar antes da reunião, sino para, etapa só para a frente, responsável só se vazio, atividade/tarefa da reunião, rascunho nas notas com título |
| `.env.example` | documenta `RAMON_FLUXO_REUNIOES` |
| `app/javascript/dashboard/routes/dashboard/captain/automacoes/{fluxo.js,validar.js,PainelPasso.vue,NoPasso.vue,Lista.vue}` + i18n `{en,pt_BR}/ramon.json` | o editor entende tudo isso |
| `app/services/ramon/fluxos/passos/lead.rb` + `PainelPasso.vue` (Task 10) | `mover_etapa` para etapa de perda com motivo (regra do PR #216) |
| `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` | §15 Notas da B4.1 |

---

### Task 1: Regras únicas das reuniões (`Ramon::Fluxos::Reunioes`) + o job usa elas

**Files:**
- Create: `app/services/ramon/fluxos/reunioes.rb`
- Modify: `app/jobs/ramon/meeting_reminder_job.rb` (arquivo inteiro)
- Test: `spec/services/ramon/fluxos/reunioes_spec.rb` (novo); `spec/jobs/ramon/meeting_reminder_job_spec.rb` (sem mudança — trava do refactor)

**Interfaces:**
- Produces: `Ramon::Fluxos::Reunioes::TOLERANCIA = 60.seconds`; `Ramon::Fluxos::Reunioes.reuniao_aberta?(lead, inicio) → Boolean` (`inicio` Time ou nil); `Ramon::Fluxos::Reunioes.destinatarios(lead) → Array<Integer>` (user_ids).

- [ ] **Step 1: Write the failing test** — criar `spec/services/ramon/fluxos/reunioes_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Reunioes do
  # A conta seeda o funil no after_create (Leads::SeedDefaultConfigService).
  let(:account) { create(:account) }
  let(:closer) { create(:user, account: account, name: 'Carla Closer') }
  let(:lead) do
    create(:lead, account: account, lead_stage: account.lead_stages.order(:position).first, closer: closer, name: 'João Pereira')
  end

  describe 'regras únicas (código e fluxos)' do
    it 'reunião de pé: tarefa de reunião aberta no horário, com 60 s de folga' do
      inicio = 2.days.from_now.change(usec: 0)
      task = create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'Reunião', due_at: inicio + 30.seconds)
      expect(described_class.reuniao_aberta?(lead, inicio)).to be(true)
      task.update!(completed_at: Time.current)
      expect(described_class.reuniao_aberta?(lead, inicio)).to be(false)
      expect(described_class.reuniao_aberta?(lead, nil)).to be(false)
    end

    it 'quem recebe o lembrete: Closer e SDR; sem nenhum dos dois, os administradores' do
      admin = create(:user, account: account, role: :administrator)
      expect(described_class.destinatarios(lead)).to eq([closer.id])
      lead.update!(closer: nil)
      expect(described_class.destinatarios(lead)).to eq([admin.id])
    end
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/reunioes_spec.rb`
Expected: FAIL — `uninitialized constant Ramon::Fluxos::Reunioes`.

- [ ] **Step 3: Implementation**

(a) Criar `app/services/ramon/fluxos/reunioes.rb`:

```ruby
# B4.1 (spec §8 e §15): o agendamento de reuniões (marcar, remarcar, cancelar e os 5 lembretes) saindo do código para
# fluxos. As regras de reunião moram aqui, uma vez só, e valem para os dois lados — o código (Ramon::MeetingReminderJob,
# Ramon::ReuniaoAgendamento) e os fluxos —, então a sombra compara exatamente a mesma regra.
module Ramon::Fluxos::Reunioes
  TOLERANCIA = 60.seconds

  module_function

  # A reunião segue de pé: a tarefa da reunião segue aberta naquele horário (±60 s).
  # Cancelou (tarefa apagada), concluiu ou remarcou (outro horário) → não.
  def reuniao_aberta?(lead, inicio)
    return false if inicio.blank?

    lead.lead_tasks.open_tasks.exists?(kind: 'meeting', due_at: (inicio - TOLERANCIA)..(inicio + TOLERANCIA))
  end

  # Closer e SDR do lead; lead sem nenhum dos dois avisa os administradores (nunca a conta toda).
  def destinatarios(lead)
    [lead.closer_id, lead.sdr_id].compact.uniq.presence || lead.account.account_users.administrator.pluck(:user_id)
  end
end
```

(b) Substituir `app/jobs/ramon/meeting_reminder_job.rb` inteiro por (mesmo comportamento; `TOLERANCE`, `destinatarios` e `meeting_open?` saem — conferido: nenhum outro arquivo usa):

```ruby
# Lembrete anti no-show (mapa comercial 23/07): agendado via set(wait_until:)
# pelo Ramon::ReuniaoAgendamento. Cancel/reschedule não desagenda nada — o guard da
# tarefa aberta mata o lembrete órfão. As regras (reunião de pé, quem recebe) moram em
# Ramon::Fluxos::Reunioes: são as mesmas do fluxo que vai substituir este job (B4.1).
class Ramon::MeetingReminderJob < ApplicationJob
  queue_as :low

  # offset → label pt-BR do push
  OFFSETS = {
    24.hours => '24h antes',
    8.hours => '8h antes',
    1.hour => '1h antes',
    30.minutes => '30min antes',
    5.minutes => '5min antes'
  }.freeze

  TIME_ZONE = 'America/Sao_Paulo'.freeze

  def perform(lead_id, start_at_iso, label)
    lead = Lead.find_by(id: lead_id)
    start_at = Time.zone.parse(start_at_iso)
    unless lead && Ramon::Fluxos::Reunioes.reuniao_aberta?(lead, start_at)
      return Rails.logger.info("MeetingReminderJob: lead #{lead_id} sem reunião aberta em #{start_at_iso} — lembrete órfão descartado")
    end
    # dedup: reschedule ida-e-volta re-enfileira os mesmos offsets — só o 1º apita
    return unless Rails.cache.write("ramon:reminder:#{lead_id}:#{start_at_iso}:#{label}", true, unless_exist: true, expires_in: 25.hours)

    hora = start_at.in_time_zone(TIME_ZONE).strftime('%d/%m %H:%M')
    # sino do hub só pra quem faz a reunião — o ntfy é opcional, o hub não
    destinatarios = Ramon::Fluxos::Reunioes.destinatarios(lead)
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_meeting_reminder', user_ids: destinatarios,
                                       meta: { 'quando' => hora, 'label' => label }).perform
    return if ENV.fetch('NTFY_TOPIC', nil).blank?

    # timing já resolvido pelo wait_until — push direto, sem re-enfileirar
    Ramon::NtfyPushJob.perform_now(lead_id, title: "Reunião #{lead.name} em #{label}",
                                            body: "#{hora} — hora de mandar a mensagem de confirmação pro cliente")
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/reunioes_spec.rb spec/jobs/ramon/meeting_reminder_job_spec.rb` e `bundle exec rubocop app/services/ramon/fluxos/reunioes.rb app/jobs/ramon/meeting_reminder_job.rb`
Expected: PASS (os exemplos do job seguem verdes: tolerância, tarefa concluída, remarcada, Closer+SDR, gestores), sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/reunioes.rb app/jobs/ramon/meeting_reminder_job.rb spec/services/ramon/fluxos/reunioes_spec.rb
git commit -m "refactor(fluxos): regras de reunião num lugar só (código e fluxos)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 2: Motor — textos do gatilho, "esperar antes da reunião" e "a reunião segue de pé"

**Files:**
- Modify: `app/services/ramon/fluxos/contexto.rb:7` (`DO_GATILHO`), `:9-11` (`RESERVADAS`), `:26-29` (`dados`), novos públicos `gatilho`, `reuniao_em`, `quem_marcou`; novos privados `dados_reuniao`, `proxima_reuniao`
- Modify: `app/services/ramon/fluxos/passos/logica.rb:18-25` (`esperar`) + novos `esperar_reuniao`, `duracao`, `hora`
- Test: `spec/services/ramon/fluxos/contexto_spec.rb`, `spec/services/ramon/fluxos/passos_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Fluxos::Reunioes.reuniao_aberta?` (Task 1).
- Produces: `Contexto::DO_GATILHO` += `evento titulo titulo_tarefa resumo resumo_antes primeiro_nome` (viram `{variáveis}`); `Contexto#gatilho(chave) → valor cru do gatilho` (ex.: `'inicio'`, `'quem_marcou_id'`, `'tarefa_ids'`, `'lead_id'`); `Contexto#reuniao_em → Time | nil` (gatilho `inicio`; sem ele, a próxima reunião aberta do lead); `Contexto#quem_marcou → User | nil`; `ctx.dados['reuniao_de_pe'] → 'sim' | 'nao' | nil`; `Passos::Logica.esperar` com `config['antes_de'] == 'reuniao'` → `{saida: 's', resumo:, esperar_ate: Time, vars: {'horario_passou' => 'nao'}}` ou, momento já passado, `{saida: 's', resumo:, vars: {'horario_passou' => 'sim'}}`; sem reunião → `PassoImpossivel`. `Passos::Logica.hora(momento) → 'dd/mm HH:MM'` (fuso SP). `RESERVADAS` inclui os novos + `reuniao_de_pe`, `horario_passou`.

- [ ] **Step 1: Write the failing tests**

(a) `spec/services/ramon/fluxos/contexto_spec.rb`, antes do `end` final:

```ruby
  describe 'reunião (B4.1)' do
    let(:inicio) { 2.days.from_now.change(usec: 0) }

    it 'os textos prontos do gatilho viram variáveis; quem marcou vem do id' do
      agente = create(:user, account: account)
      e = fluxo.execucoes.create!(account: account, alvo: lead, contexto: { 'gatilho' => {
                                    'evento' => 'marcada', 'resumo' => 'Primeiro Atendimento em 07/10/2026 19:00',
                                    'primeiro_nome' => 'Maria', 'quem_marcou_id' => agente.id
                                  } })
      ctx = described_class.new(e)
      expect(ctx.dados).to include('evento' => 'marcada', 'resumo' => 'Primeiro Atendimento em 07/10/2026 19:00', 'primeiro_nome' => 'Maria')
      expect(ctx.quem_marcou).to eq(agente)
    end

    it 'reuniao_de_pe: sim com a tarefa aberta no horário do gatilho; não depois de remarcada' do
      task = create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'Reunião', due_at: inicio)
      e = fluxo.execucoes.create!(account: account, alvo: lead, contexto: { 'gatilho' => { 'inicio' => inicio.iso8601 } })
      expect(described_class.new(e).dados['reuniao_de_pe']).to eq('sim')
      task.update!(due_at: inicio + 1.day)
      expect(described_class.new(e).dados['reuniao_de_pe']).to eq('nao')
    end

    it 'sem o horário no gatilho ("Testar com um lead…") usa a próxima reunião aberta do lead' do
      create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'Reunião', due_at: inicio)
      ctx = described_class.new(execucao(lead))
      expect(ctx.reuniao_em).to eq(inicio)
      expect(ctx.dados['reuniao_de_pe']).to eq('sim')
    end

    it 'lead sem reunião: nada a dizer' do
      expect(described_class.new(execucao(lead)).dados['reuniao_de_pe']).to be_nil
    end
  end
```

(b) `spec/services/ramon/fluxos/passos_spec.rb`: trocar o helper

```ruby
  def ctx(alvo: lead, ensaio: false)
    Ramon::Fluxos::Contexto.new(fluxo.execucoes.create!(account: account, alvo: alvo, ensaio: ensaio))
  end
```

por

```ruby
  def ctx(alvo: lead, ensaio: false, contexto: {})
    Ramon::Fluxos::Contexto.new(fluxo.execucoes.create!(account: account, alvo: alvo, ensaio: ensaio, contexto: contexto))
  end
```

e, depois do exemplo `'esperar devolve o momento de retomar'`:

```ruby
  describe 'esperar antes da reunião (B4.1)' do
    let(:config) { { 'antes_de' => 'reuniao', 'quantidade' => 8, 'unidade' => 'horas' } }
    let(:gatilho) { { 'gatilho' => { 'inicio' => '2026-10-07T22:00:00Z' } } }

    it 'conta para trás a partir da reunião do gatilho' do
      travel_to(Time.zone.parse('2026-10-07T12:00:00Z')) do
        r = Ramon::Fluxos::Passos::Logica.esperar(config, ctx(contexto: gatilho))
        expect(r[:esperar_ate]).to eq(Time.zone.parse('2026-10-07T14:00:00Z'))
        expect(r[:vars]).to eq('horario_passou' => 'nao')
      end
    end

    it 'horário já passado: segue sem esperar e marca horario_passou = sim (o código também não agenda)' do
      travel_to(Time.zone.parse('2026-10-07T15:00:00Z')) do
        r = Ramon::Fluxos::Passos::Logica.esperar(config, ctx(contexto: gatilho))
        expect(r[:esperar_ate]).to be_nil
        expect(r[:vars]).to eq('horario_passou' => 'sim')
        expect(r[:resumo]).to include('já passou')
      end
    end

    it 'sem reunião nenhuma é erro de configuração (não repete)' do
      expect { Ramon::Fluxos::Passos::Logica.esperar(config, ctx) }.to raise_error(Ramon::Fluxos::PassoImpossivel, /reunião/)
    end
  end
```

(O exemplo existente `'RESERVADAS cobre toda chave que o Contexto monta sozinho'` passa a cobrir as chaves novas automaticamente.)

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/contexto_spec.rb spec/services/ramon/fluxos/passos_spec.rb`
Expected: FAIL — `evento`/`resumo` ausentes de `dados`; `undefined method 'quem_marcou'`/`'reuniao_em'`; `reuniao_de_pe` nil; `esperar` com `antes_de` conta para a frente.

- [ ] **Step 3: Implementation**

(a) `app/services/ramon/fluxos/contexto.rb` — trocar `DO_GATILHO` e `RESERVADAS` (linhas 5-11) por:

```ruby
  # o que o gatilho traz e vira variável: {texto} da mensagem, {quando} da reunião,
  # {regra} do evento do ADVBOX, {documento} do anexo casado com o checklist;
  # B4.1: os textos prontos da reunião ({evento}, {titulo}, {titulo_tarefa}, {resumo}, {resumo_antes}, {primeiro_nome})
  DO_GATILHO = %w[texto quando regra documento evento titulo titulo_tarefa resumo resumo_antes primeiro_nome].freeze

  # chaves que o próprio hub monta em `dados`: preencher_campo recusa (o campo nunca apareceria)
  RESERVADAS = (DO_GATILHO + %w[nome nome_completo telefone responsavel responsavel_id etapa etapa_id tese tese_id origem canal
                                valor prioridade caixa caixa_id status etiquetas documentos_completos documentos_faltantes
                                resposta_ia reuniao_de_pe horario_passou]).freeze
```

trocar `dados` (linhas 26-29):

```ruby
  def dados
    @dados ||= campos_livres.merge(dados_lead, dados_funil, dados_conversa, dados_docs, dados_reuniao, dados_gatilho,
                                   execucao.contexto['vars'] || {})
  end
```

logo depois do método `interpolar` (antes de `private`), inserir:

```ruby
  # Valor cru que o gatilho trouxe (ids e horários que não viram texto: inicio, quem_marcou_id, tarefa_ids, lead_id).
  def gatilho(chave) = execucao.contexto.dig('gatilho', chave)

  # Horário da reunião (B4.1): o 'inicio' que o gatilho mandou; sem ele ("Testar com um lead…", Rodar na mão),
  # a próxima reunião aberta do lead.
  def reuniao_em
    return @reuniao_em if defined?(@reuniao_em)

    iso = gatilho('inicio')
    @reuniao_em = iso.present? ? Time.zone.parse(iso) : proxima_reuniao
  end

  # Quem marcou/remarcou/cancelou (o usuário do painel; Cal.com = ninguém) — dono da tarefa e da atividade, como no código.
  def quem_marcou
    id = gatilho('quem_marcou_id')
    return if id.blank? || lead.nil?

    lead.account.users.find_by(id: id)
  end
```

e, logo depois de `dados_gatilho` (seção `private`), inserir:

```ruby
  # {reuniao_de_pe}: a mesma regra do lembrete do código (Ramon::Fluxos::Reunioes.reuniao_aberta?), na hora do passo.
  # ponytail: 1 consulta por passo em fluxo de lead (a próxima reunião); cachear se virar gargalo.
  def dados_reuniao
    inicio = lead && reuniao_em
    return { 'reuniao_de_pe' => nil } unless inicio

    { 'reuniao_de_pe' => Ramon::Fluxos::Reunioes.reuniao_aberta?(lead, inicio) ? 'sim' : 'nao' }
  end

  def proxima_reuniao
    return if lead.nil?

    lead.lead_tasks.open_tasks.where(kind: 'meeting', due_at: Time.current..).minimum(:due_at)
  end
```

(b) `app/services/ramon/fluxos/passos/logica.rb` — trocar o `esperar` (linhas 18-25):

```ruby
  def esperar(config, _ctx)
    ate = if config['ate'] == 'horario_comercial'
            Ramon::Fluxos::Horario.proximo(Time.current)
          else
            Time.current + config['quantidade'].to_i.public_send(UNIDADES.fetch(config['unidade']))
          end
    { saida: 's', resumo: "espera até #{ate.in_time_zone(Fluxo::ZONA).strftime('%d/%m %H:%M')}", esperar_ate: ate }
  end
```

por

```ruby
  def esperar(config, ctx)
    return esperar_reuniao(config, ctx) if config['antes_de'] == 'reuniao'

    ate = config['ate'] == 'horario_comercial' ? Ramon::Fluxos::Horario.proximo(Time.current) : Time.current + duracao(config)
    { saida: 's', resumo: "espera até #{hora(ate)}", esperar_ate: ate }
  end

  # B4.1: conta para TRÁS a partir da reunião (lembretes). Momento já passado → não espera e marca
  # {horario_passou} = sim; o `se` seguinte pula o aviso — como o código, que só agenda os lembretes ainda futuros.
  def esperar_reuniao(config, ctx)
    inicio = ctx.reuniao_em || raise(Ramon::Fluxos::PassoImpossivel, 'sem reunião marcada para contar o tempo')
    ate = inicio - duracao(config)
    return { saida: 's', resumo: "#{hora(ate)} já passou: segue sem esperar", vars: { 'horario_passou' => 'sim' } } if ate.past?

    { saida: 's', resumo: "espera até #{hora(ate)}", esperar_ate: ate, vars: { 'horario_passou' => 'nao' } }
  end

  def duracao(config) = config['quantidade'].to_i.public_send(UNIDADES.fetch(config['unidade']))

  def hora(momento) = momento.in_time_zone(Fluxo::ZONA).strftime('%d/%m %H:%M')
```

Rastreio: (1) 12:00Z, início 22:00Z, 8 h → `ate` 14:00Z futuro → `esperar_ate` 14:00Z, `vars` `nao`. (2) 15:00Z → 14:00Z `past?` → sem `esperar_ate`, `vars` `sim`. (3) sem gatilho e sem tarefa → `PassoImpossivel` "sem reunião marcada…". O Executor já junta `resultado[:vars]` no contexto antes de esperar (`executor.rb:100`); ao retomar, o `se` lê `{horario_passou}`. `quem_marcou`: `lead.account.users` (o agente criado na conta) → acha.

- [ ] **Step 4: Run to verify they pass**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/contexto_spec.rb spec/services/ramon/fluxos/passos_spec.rb spec/services/ramon/fluxos/executor_spec.rb` e `bundle exec rubocop app/services/ramon/fluxos/contexto.rb app/services/ramon/fluxos/passos/logica.rb`
Expected: PASS (o executor_spec segue verde: `esperar` sem `antes_de` não mudou), sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/contexto.rb app/services/ramon/fluxos/passos/logica.rb spec/services/ramon/fluxos/contexto_spec.rb spec/services/ramon/fluxos/passos_spec.rb
git commit -m "feat(fluxos): textos da reunião no gatilho, esperar antes da reunião e reunião de pé" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 3: Motor — a reunião (tarefa) como alvo, gatilho `reuniao_na_agenda`, recomeçar, na hora e a decisão do evento

**Files:**
- Modify: `app/services/ramon/fluxos/reunioes.rb` (+ `GATILHOS`, `migrado?`, `na_agenda`)
- Modify: `app/services/ramon/fluxos/grafo.rb:7-10` (`GATILHOS`)
- Modify: `app/services/ramon/fluxos/disparo.rb:6` (constantes), `:61-71` (`iniciar`), `private` (`recomecar`, `sombra?`, `lead_do_alvo`; `atributos` e `contexto`)
- Modify: `app/models/fluxo_execucao.rb:17-31` (`lead`, `conversa`, `resumo_json`)
- Modify: `app/services/ramon/fluxos/executor.rb:59` (motivo), `:69` (`desligado?`)
- Test: `spec/services/ramon/fluxos/disparo_spec.rb`, `spec/services/ramon/fluxos/executor_spec.rb`

**Interfaces:**
- Consumes: `Ramon::ReuniaoAgendamento.quando(Time) → String` (já existe).
- Produces: `Ramon::Fluxos::Reunioes::GATILHOS = { 'reuniao_marcada' => 'reuniao_marcada', 'reuniao_cancelada' => 'reuniao_cancelada', 'lembretes_reuniao' => 'reuniao_na_agenda' }` (`sistema_chave` → gatilho esperado); `.migrado?(fluxo) → Boolean` (origem `usuario` e `sistema_chave` em `GATILHOS`); `.na_agenda(tarefa, assumido)` dispara `reuniao_na_agenda` com alvo = a tarefa e `dados = {'inicio', 'quando', 'lead_id', 'assumido'}`. `Grafo::GATILHOS` inclui `reuniao_na_agenda`. `Disparo::RECOMECA = %w[reuniao_na_agenda]`, `Disparo::NA_HORA = %w[reuniao_marcada reuniao_cancelada]` (só para fluxo migrado: roda o `Executor` na hora, dentro de quem disparou). Fluxo migrado: `ensaio = !dados['assumido']` (os outros: `modo == 'sombra'`). `FluxoExecucao#lead`/`#conversa` aceitam alvo `LeadTask`. `Executor`: alvo apagado → `'cancelado: o alvo foi apagado (lead, conversa ou reunião)'`; desligar o fluxo cancela também a sombra (não o "Testar…").

- [ ] **Step 1: Write the failing tests**

(a) `spec/services/ramon/fluxos/disparo_spec.rb`, depois de `'modo sombra cria execução de ensaio'`:

```ruby
  it 'cada reunião (tarefa) tem o seu ciclo; remarcar recomeça só o dela (normal e sombra)' do
    espera = ['esperar', { 'quantidade' => 1, 'unidade' => 'dias' }]
    normal = fluxo_publicado(account, grafo_linear({ 'tipo' => 'reuniao_na_agenda' }, espera))
    sombra = fluxo_publicado(account, grafo_linear({ 'tipo' => 'reuniao_na_agenda' }, espera), modo: 'sombra')
    t1 = create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'R1', due_at: 2.days.from_now)
    t2 = create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'R2', due_at: 3.days.from_now)
    [t1, t2, t1].each { |t| described_class.call('reuniao_na_agenda', t, { 'inicio' => t.due_at.iso8601 }) }
    [normal, sombra].each do |f|
      expect(f.execucoes.where(alvo: t1).order(:id).pluck(:status)).to eq(%w[cancelada esperando])
      expect(f.execucoes.where(alvo: t2).pluck(:status)).to eq(%w[esperando])
    end
    expect(normal.execucoes.where(alvo: t1).order(:id).first.trilha.last['resumo']).to eq('cancelado: a reunião foi remarcada')
  end

  it 'com a tarefa da reunião como alvo, o fluxo enxerga o lead e a conversa dela' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'reuniao_na_agenda' }, nota))
    tarefa = create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'R', due_at: 1.day.from_now)
    described_class.call('reuniao_na_agenda', tarefa, {})
    e = fluxo.execucoes.last
    expect([e.lead, e.conversa, e.contexto['etapa_inicial_id']]).to eq([lead, conversa, lead.lead_stage_id])
    expect(e.resumo_json[:alvo_nome]).to eq(lead.name)
  end

  it 'fluxo migrado do código: quem decide se age é o evento (assumido), e roda na hora' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'reuniao_cancelada' }, nota), sistema_chave: 'reuniao_cancelada')
    described_class.call('reuniao_cancelada', lead, { 'assumido' => false })
    described_class.call('reuniao_cancelada', lead, { 'assumido' => true })
    expect(fluxo.execucoes.order(:id).pluck(:ensaio, :status)).to eq([[true, 'concluida'], [false, 'concluida']])
    expect(conversa.messages.where(private: true, content: 'oi').count).to eq(1)
  end
```

(b) `spec/services/ramon/fluxos/executor_spec.rb`, depois de `'fluxo desligado durante a espera → cancelada'`:

```ruby
  it 'sombra: desligar o fluxo cancela quem espera (é assim que se para a sombra)' do
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'quantidade' => 1, 'unidade' => 'horas' }],
                             ['nota_privada', { 'texto' => 'x' }]), ensaio: true)
    avancar(e)
    e.fluxo.update!(ativo: false)
    travel(2.hours) { expect(avancar(e).status).to eq('cancelada') }
  end

  it '"Testar com um lead…" roda mesmo com o fluxo desligado' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' }, ['nota_privada', { 'texto' => 'x' }]), ativo: false)
    expect(Ramon::Fluxos::Disparo.ensaiar(fluxo, lead, usar: 'publicada').status).to eq('concluida')
  end

  it 'a reunião (tarefa) apagada durante a espera cancela o ciclo dela' do
    tarefa = create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'R', due_at: 2.days.from_now)
    e = iniciar(grafo_linear({ 'tipo' => 'reuniao_na_agenda' }, ['esperar', { 'quantidade' => 1, 'unidade' => 'horas' }],
                             ['nota_privada', { 'texto' => 'x' }]), alvo: tarefa)
    avancar(e)
    tarefa.destroy!
    travel(2.hours) { expect(avancar(e).status).to eq('cancelada') }
    expect(e.trilha.last['resumo']).to eq('cancelado: o alvo foi apagado (lead, conversa ou reunião)')
  end
```

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/disparo_spec.rb spec/services/ramon/fluxos/executor_spec.rb`
Expected: FAIL — `reuniao_na_agenda` não publica (gatilho desconhecido); `FluxoExecucao#lead` com `LeadTask` procura conversa; o migrado sai ensaio pelo `modo`; a sombra desligada termina `concluida`; motivo antigo "o lead/conversa foi apagado". (O "Testar…" já passa e fica como trava.)

- [ ] **Step 3: Implementation**

(a) `app/services/ramon/fluxos/reunioes.rb` — depois de `TOLERANCIA = 60.seconds`:

```ruby
  # Os 3 fluxos que substituem o código (spec §14: fluxo próprio, origem 'usuario'): sistema_chave → gatilho esperado.
  GATILHOS = { 'reuniao_marcada' => 'reuniao_marcada', 'reuniao_cancelada' => 'reuniao_cancelada',
               'lembretes_reuniao' => 'reuniao_na_agenda' }.freeze
```

e antes do `end` final:

```ruby
  def migrado?(fluxo) = fluxo.origem == 'usuario' && GATILHOS.key?(fluxo.sistema_chave)

  # A reunião entrou na agenda (tarefa criada ou movida): começa o ciclo de lembretes DESSA reunião (alvo = a tarefa).
  # 'assumido' = a decisão do evento que a pôs na agenda (código ou fluxos no comando).
  def na_agenda(tarefa, assumido)
    dados = { 'inicio' => tarefa.due_at.iso8601, 'quando' => Ramon::ReuniaoAgendamento.quando(tarefa.due_at),
              'lead_id' => tarefa.lead_id, 'assumido' => assumido }
    Ramon::Fluxos::Disparo.externo('reuniao_na_agenda', tarefa, dados)
  end
```

(b) `app/services/ramon/fluxos/grafo.rb` — em `GATILHOS`, trocar

```ruby
                lead_parado relogio reuniao_marcada reuniao_cancelada evento_advbox
```

por

```ruby
                lead_parado relogio reuniao_marcada reuniao_cancelada reuniao_na_agenda evento_advbox
```

(c) `app/services/ramon/fluxos/disparo.rb` — depois de `PROFUNDIDADE_MAX = 3`:

```ruby
  # B4.1: a mesma reunião de novo na agenda (remarcada) cancela a espera do ciclo dela e recomeça pelo horário novo.
  RECOMECA = %w[reuniao_na_agenda].freeze
  # B4.1: os fluxos migrados de marcar/cancelar rodam na hora, dentro da requisição (o painel vê a tarefa ao recarregar;
  # em sombra, o ensaio vê o lead antes de o código mexer).
  NA_HORA = %w[reuniao_marcada reuniao_cancelada].freeze
```

trocar o `iniciar` inteiro (linhas 61-71):

```ruby
  def iniciar
    return if @fluxo.origem == 'sistema' # D7: desenho só-leitura; quem roda é o código de hoje

    execucao = @fluxo.execucoes.create!(atributos)
    return Ramon::Fluxos::Executor.new(execucao).avancar! if @ensaio

    Ramon::FluxoAvancarJob.perform_later(execucao.id)
    execucao
  rescue ActiveRecord::RecordNotUnique
    nil # já existe execução viva desse fluxo nesse alvo
  end
```

por

```ruby
  def iniciar
    return if @fluxo.origem == 'sistema' # D7: desenho só-leitura; quem roda é o código de hoje

    recomecar if RECOMECA.include?(@fluxo.gatilho_tipo) && @ensaio.nil?
    execucao = @fluxo.execucoes.create!(atributos)
    return Ramon::Fluxos::Executor.new(execucao).avancar! if @ensaio || na_hora?

    Ramon::FluxoAvancarJob.perform_later(execucao.id)
    execucao
  rescue ActiveRecord::RecordNotUnique
    nil # já existe execução viva desse fluxo nesse alvo
  end
```

no `atributos`, trocar

```ruby
      ensaio: @ensaio.present? || @fluxo.modo == 'sombra', profundidade: @origem ? @origem.profundidade + 1 : 0,
```

por

```ruby
      ensaio: @ensaio.present? || sombra?, profundidade: @origem ? @origem.profundidade + 1 : 0,
```

no `contexto`, trocar

```ruby
    lead = @alvo.is_a?(Lead) ? @alvo : @fluxo.account.leads.where(conversation_id: @alvo.id).reorder(id: :desc).first
    base = { 'gatilho' => @dados, 'vars' => {}, 'etapa_inicial_id' => lead&.lead_stage_id }
```

por

```ruby
    base = { 'gatilho' => @dados, 'vars' => {}, 'etapa_inicial_id' => lead_do_alvo&.lead_stage_id }
```

e, na seção `private`, antes de `def atributos`:

```ruby
  def na_hora? = NA_HORA.include?(@fluxo.gatilho_tipo) && Ramon::Fluxos::Reunioes.migrado?(@fluxo)

  # Fluxo migrado do código (B4.1): quem decide se age é o evento ('assumido', lido 1 vez pelo código); os demais, o modo.
  def sombra? = Ramon::Fluxos::Reunioes.migrado?(@fluxo) ? !@dados['assumido'] : @fluxo.modo == 'sombra'

  def lead_do_alvo
    case @alvo
    when Lead then @alvo
    when LeadTask then @alvo.lead
    else @fluxo.account.leads.where(conversation_id: @alvo.id).reorder(id: :desc).first
    end
  end

  # Sem isto, em modo normal o índice único barraria o ciclo novo e os lembretes seguiriam o horário antigo.
  # ponytail: só 'esperando' — uma execução 'rodando' (milissegundos entre passos) ainda barra a nova.
  def recomecar
    @fluxo.execucoes.where(alvo: @alvo, status: 'esperando').find_each do |velha|
      velha.with_lock do
        next unless velha.status == 'esperando' # o relógio pode ter acabado de reivindicar

        linha = { 'no' => 'cancelado', 'tipo' => 'cancelado', 'em' => Time.current.iso8601, 'saida' => nil,
                  'resumo' => 'cancelado: a reunião foi remarcada', 'erro' => false }
        velha.update!(status: 'cancelada', trilha: velha.trilha + [linha])
      end
    end
  end
```

(d) `app/models/fluxo_execucao.rb` — trocar `lead`, `conversa` e a linha `alvo_nome` do `resumo_json`:

```ruby
  def lead
    return alvo if alvo.is_a?(Lead)
    return if alvo.nil?

    account.leads.where(conversation_id: alvo.id).reorder(id: :desc).first
  end

  def conversa = alvo.is_a?(Conversation) ? alvo : alvo&.conversation
```

por

```ruby
  # B4.1: o alvo também pode ser a tarefa da reunião (ciclo de lembretes) — lead e conversa vêm dela.
  def lead
    return alvo if alvo.is_a?(Lead)
    return alvo.lead if alvo.is_a?(LeadTask)
    return if alvo.nil?

    account.leads.where(conversation_id: alvo.id).reorder(id: :desc).first
  end

  def conversa = alvo.is_a?(Conversation) ? alvo : lead&.conversation
```

e, no `resumo_json`,

```ruby
      alvo_nome: alvo.try(:name) || alvo&.contact&.name, conversation_display_id: conversa&.display_id,
```

por

```ruby
      alvo_nome: alvo.try(:name) || alvo.try(:contact)&.name || lead&.name, conversation_display_id: conversa&.display_id,
```

(e) `app/services/ramon/fluxos/executor.rb` — linha 59, trocar `'o lead/conversa foi apagado'` por `'o alvo foi apagado (lead, conversa ou reunião)'`; linha 69, trocar

```ruby
  def desligado? = !@execucao.ensaio && !@execucao.fluxo&.ativo
```

por

```ruby
  # Vale para execução normal e para a sombra (B4.1: desligar é como se para a sombra); o "Testar com um lead…"
  # (pular_esperas) roda até com o fluxo desligado.
  def desligado? = !@execucao.contexto['pular_esperas'] && !@execucao.fluxo&.ativo
```

Rastreio (a1): `t1` → cada fluxo cria execução `esperando` (alvo `LeadTask` t1); `t2` idem; `t1` de novo → `recomecar` cancela a `esperando` de t1 (com a linha) e cria outra; o índice único (só o normal) não reclama: a antiga já não está viva. (a2) `lead_do_alvo` = `tarefa.lead`; `e.lead` → `alvo.lead`; `e.conversa` → `lead.conversation` = `conversa`; `alvo_nome`: `LeadTask` não tem `name` nem `contact` → `lead.name`. (a3) `sistema_chave: 'reuniao_cancelada'`, origem padrão `usuario` → migrado → `sombra?` = `!assumido`; `na_hora?` → `Executor` na hora → as duas `concluida`; só a não-ensaio escreveu a nota. (b3) tarefa apagada → `alvo` nil no `cancelar_se_preciso` → motivo novo.

- [ ] **Step 4: Run to verify they pass**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/ spec/models/fluxo_execucao_spec.rb spec/controllers/api/v1/accounts/ramon_fluxo_execucoes_controller_spec.rb` (os dois últimos só se existirem) e `bundle exec rubocop app/services/ramon/fluxos/disparo.rb app/services/ramon/fluxos/executor.rb app/services/ramon/fluxos/grafo.rb app/services/ramon/fluxos/reunioes.rb app/models/fluxo_execucao.rb`
Expected: PASS (inclusive `'fluxo desligado durante a espera → cancelada'` e `'rajada no mesmo alvo vira uma execução só'`), sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/reunioes.rb app/services/ramon/fluxos/grafo.rb app/services/ramon/fluxos/disparo.rb app/models/fluxo_execucao.rb app/services/ramon/fluxos/executor.rb spec/services/ramon/fluxos/disparo_spec.rb spec/services/ramon/fluxos/executor_spec.rb
git commit -m "feat(fluxos): um ciclo por reunião, remarcar recomeça, fluxos de reunião na hora e decididos pelo evento" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 4: Passos — sino para Closer+SDR ou para a conta, etapa só para a frente, Closer só se não tem

**Files:**
- Modify: `app/services/ramon/fluxos/passos/aviso.rb:5-21` (`avisar_sino`, `destinatarios`) + novo `nomes`
- Modify: `app/services/ramon/fluxos/passos/lead.rb:64-73` (`mover_etapa`), `:97-107` (`trocar_responsavel`) + novo `ja_tem`
- Test: `spec/services/ramon/fluxos/passos_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Fluxos::Reunioes.destinatarios(lead)` (Task 1).
- Produces: `avisar_sino {texto, para: 'closer_e_sdr'|'conta'}` (sem `para`: hoje — `user_ids` ou o responsável). Resumo do ensaio do sino: **exatamente** `faria: sino para <nomes em ordem alfabética, ", ">: "<texto até 80>"` (ninguém: `faria: sino para ninguém (sem responsável): "…"`) — lido pela comparação (`CompararLembretes::PESSOAS`). `mover_etapa {etapa_id, so_para_frente: true}`: lead já na etapa ou adiante → `{saida: 's', resumo: 'etapa: já está em <etapa> (só para a frente)'}` sem mexer (também no ensaio, sem `faria:`). `trocar_responsavel {papel, so_se_vazio: true}`: já tem → `{saida: 's', resumo: '<papel>: já tem <nome>'}`.

- [ ] **Step 1: Write the failing tests** — `spec/services/ramon/fluxos/passos_spec.rb`, depois de `'sino sem responsável não cai em todo mundo'`:

```ruby
  it 'sino para Closer e SDR (sem nenhum dos dois, os administradores) e para a conta toda' do
    closer = create(:user, account: account)
    sdr = create(:user, account: account)
    admin = create(:user, account: account, role: :administrator)
    c = ctx
    c.lead.update!(closer: closer, sdr: sdr)
    avisados = -> { Notification.where(notification_type: 'ramon_fluxo_aviso').pluck(:user_id) }
    Ramon::Fluxos::Passos::Aviso.avisar_sino({ 'texto' => 'Reunião', 'para' => 'closer_e_sdr' }, c)
    expect(avisados.call).to contain_exactly(closer.id, sdr.id)
    c.lead.update!(closer: nil, sdr: nil)
    Ramon::Fluxos::Passos::Aviso.avisar_sino({ 'texto' => 'Reunião', 'para' => 'closer_e_sdr' }, c)
    expect(avisados.call).to contain_exactly(closer.id, sdr.id, admin.id)
    Ramon::Fluxos::Passos::Aviso.avisar_sino({ 'texto' => 'Marcada', 'para' => 'conta' }, c)
    expect(avisados.call.count).to eq(3 + account.account_users.count)
  end

  it 'ensaio do sino diz quem receberia, sem gravar nada' do
    ana = create(:user, account: account, name: 'Ana')
    c = ctx(ensaio: true)
    c.lead.update!(closer: ana)
    r = nil
    expect { r = Ramon::Fluxos::Passos::Aviso.avisar_sino({ 'texto' => 'Ver {nome}' }, c) }.not_to change(Notification, :count)
    expect(r[:resumo]).to start_with('faria: sino para Ana: "Ver ')
  end

  it 'etapa só para a frente: quem já está adiante fica onde está' do
    atras = create(:lead_stage, account: account, position: 0)
    c = ctx
    r = Ramon::Fluxos::Passos::Lead.mover_etapa({ 'etapa_id' => atras.id, 'so_para_frente' => true }, c)
    expect(r[:resumo]).to eq("etapa: já está em #{lead.lead_stage.name} (só para a frente)")
    expect(lead.reload.lead_stage).not_to eq(atras)
  end

  it 'Closer só se o lead ainda não tem' do
    ana = create(:user, account: account, name: 'Ana')
    create(:team_member, team: create(:team, account: account, name: 'closer'), user: create(:user, account: account))
    c = ctx
    c.lead.update!(closer: ana)
    r = Ramon::Fluxos::Passos::Lead.trocar_responsavel({ 'papel' => 'closer', 'so_se_vazio' => true }, c)
    expect(r[:resumo]).to eq('closer: já tem Ana')
    expect(lead.reload.closer).to eq(ana)
  end
```

(`c.lead` é o mesmo objeto que o passo lê — `Contexto#lead` memoriza. A factory `:lead_stage` (`spec/factories/leads.rb:2`) dá `position 0` à etapa do lead; `atras` também tem 0 → "já está" (igual conta como adiante, como no código: `>=`).)

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/passos_spec.rb`
Expected: FAIL — `para` ignorado; ensaio sem nomes; `mover_etapa` move para trás; `trocar_responsavel` troca a Ana.

- [ ] **Step 3: Implementation**

(a) `app/services/ramon/fluxos/passos/aviso.rb` — trocar `avisar_sino` e `destinatarios` (linhas 5-21) por:

```ruby
  def avisar_sino(config, ctx)
    lead = Ramon::Fluxos::Passos::Lead.exigir_lead(ctx)
    texto = ctx.interpolar(config['texto'])
    ids = destinatarios(lead, config)
    return { saida: 's', resumo: "faria: sino para #{nomes(ids)}: \"#{texto.truncate(80)}\"" } if ctx.ensaio?
    return { saida: 's', resumo: 'sino: sem responsável' } if ids.empty?

    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_fluxo_aviso',
                                       meta: { 'label' => texto.truncate(200) }, user_ids: ids).perform
    { saida: 's', resumo: "sino: #{texto.truncate(80)}" }
  end

  # Só gente da conta. Lista vazia nunca chega ao builder: lá ela vira "todo mundo".
  # B4.1: para 'closer_e_sdr' = a regra do lembrete de reunião; 'conta' = todo mundo (o sino de reunião marcada/cancelada).
  def destinatarios(lead, config)
    ids = case config['para']
          when 'closer_e_sdr' then Ramon::Fluxos::Reunioes.destinatarios(lead)
          when 'conta' then lead.account.account_users.pluck(:user_id)
          else Array(config['user_ids']).map(&:to_i).presence || [(lead.closer || lead.sdr)&.id]
          end
    ids.compact & lead.account.account_users.pluck(:user_id)
  end

  # Ordem alfabética: a comparação da B4.1 (Ramon::Fluxos::CompararLembretes::PESSOAS) lê este texto.
  def nomes(ids) = User.where(id: ids).order(:name).pluck(:name).join(', ').presence || 'ninguém (sem responsável)'
```

(b) `app/services/ramon/fluxos/passos/lead.rb` — no `mover_etapa`, trocar

```ruby
    etapa = lead.account.lead_stages.find(config['etapa_id'])
    return { saida: 's', resumo: "faria: mover para #{etapa.name}" } if ctx.ensaio?
```

por

```ruby
    etapa = lead.account.lead_stages.find(config['etapa_id'])
    # B4.1: "só para a frente" (como a reunião marcada do código): quem já está adiante fica onde está
    if config['so_para_frente'] && lead.lead_stage.position >= etapa.position
      return { saida: 's', resumo: "etapa: já está em #{lead.lead_stage.name} (só para a frente)" }
    end
    return { saida: 's', resumo: "faria: mover para #{etapa.name}" } if ctx.ensaio?
```

no `trocar_responsavel`, trocar

```ruby
    coluna = Ramon::Papeis::COLUNA[papel] || raise(Ramon::Fluxos::PassoImpossivel, "papel desconhecido: #{papel}")
    pessoa =
```

por

```ruby
    coluna = Ramon::Papeis::COLUNA[papel] || raise(Ramon::Fluxos::PassoImpossivel, "papel desconhecido: #{papel}")
    feito = ja_tem(config, lead, coluna, papel)
    return feito if feito

    pessoa =
```

e, logo depois do `trocar_responsavel`:

```ruby
  # B4.1: "só se ainda não tem" (o Closer automático da reunião marcada não troca quem já está).
  def ja_tem(config, lead, coluna, papel)
    return unless config['so_se_vazio'] && lead[coluna].present?

    { saida: 's', resumo: "#{papel}: já tem #{User.find_by(id: lead[coluna])&.name}" }
  end
```

Rastreio: `para: 'conta'` → todos os usuários da conta (o `admin`, `closer`, `sdr` e quem a factory da conversa tiver criado) → `3 + account_users.count` avisos no total (3 dos dois primeiros). `ja_tem` mantém a complexidade do `trocar_responsavel` ≤ 7.

- [ ] **Step 4: Run to verify they pass**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/passos_spec.rb` e `bundle exec rubocop app/services/ramon/fluxos/passos/aviso.rb app/services/ramon/fluxos/passos/lead.rb`
Expected: PASS, sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/passos/aviso.rb app/services/ramon/fluxos/passos/lead.rb spec/services/ramon/fluxos/passos_spec.rb
git commit -m "feat(fluxos): sino para Closer e SDR ou para a conta, etapa só para a frente e Closer só se não tem" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 5: Passos — atividade de reunião, tarefa da reunião, rascunho nas notas do lead e `apagar_reuniao`

**Files:**
- Modify: `app/services/ramon/fluxos/passos/lead.rb` (`registrar_atividade`, `criar_tarefa`, `responsavel_da_tarefa`, novos `TIPOS_ATIVIDADE`, `prazo_da_tarefa`)
- Modify: `app/services/ramon/fluxos/passos/conversa.rb` (`rascunho_texto`, `escrever`, novo `cabecalho`)
- Create: `app/services/ramon/fluxos/passos/reuniao.rb`
- Modify: `app/services/ramon/fluxos/executor.rb:9-22` (`VISIVEIS`, `PASSOS`), `app/services/ramon/fluxos/grafo.rb:11-14` (`TIPOS_PASSO`)
- Test: `spec/services/ramon/fluxos/passos_spec.rb`

**Interfaces:**
- Consumes: `ctx.gatilho`, `ctx.reuniao_em`, `ctx.quem_marcou` (Task 2); `Reunioes.na_agenda` (Task 3); `Passos::Logica.hora` (Task 2).
- Produces: `registrar_atividade {texto, tipo?: 'fluxo'|'meeting_scheduled'|'meeting_rescheduled'|'meeting_cancelled', de?}` (user = quem marcou); ensaio `faria: atividade <tipo>: [de → ]texto`. `criar_tarefa {titulo, tipo, prazo: 'reuniao'}` = vence em `ctx.reuniao_em`, dona = quem marcou, e (não-ensaio, tipo `meeting`) chama `Reunioes.na_agenda(tarefa, true)`; ensaio de **toda** tarefa: `faria: tarefa "<título>" para dd/mm HH:MM`. `rascunho_texto {texto, onde?: 'notas_do_lead', titulo?}` → cabeçalho `RASCUNHO (revisar antes de enviar) — <titulo>:` (sem título: o `PREFIXO` de sempre); ensaio inalterado `faria: rascunho "<texto 120>"`. Passo novo `apagar_reuniao` (sem config): apaga as tarefas `meeting` do lead listadas em `gatilho['tarefa_ids']`; ensaio `faria: apagar tarefas #12, #13` (vazio: `(nenhuma)`).

- [ ] **Step 1: Write the failing tests** — `spec/services/ramon/fluxos/passos_spec.rb`, antes do `end` final:

```ruby
  describe 'passos da reunião (B4.1)' do
    let(:agente) { create(:user, account: account, name: 'Bia') }
    let(:gatilho) do
      { 'gatilho' => { 'inicio' => '2026-10-07T22:00:00Z', 'quem_marcou_id' => agente.id, 'titulo_tarefa' => 'Reunião Cal.com: Primeiro',
                       'resumo' => 'Primeiro em 07/10/2026 19:00', 'resumo_antes' => 'Primeiro em 06/10/2026 19:00' } }
    end

    it 'atividade de reunião com tipo, de → para e quem marcou' do
      config = { 'tipo' => 'meeting_rescheduled', 'de' => '{resumo_antes}', 'texto' => '{resumo}' }
      Ramon::Fluxos::Passos::Lead.registrar_atividade(config, ctx(contexto: gatilho))
      atividade = lead.lead_activities.find_by!(kind: 'meeting_rescheduled')
      expect([atividade.from_value, atividade.to_value, atividade.user])
        .to eq(['Primeiro em 06/10/2026 19:00', 'Primeiro em 07/10/2026 19:00', agente])
    end

    it 'tarefa da reunião: vence na hora, é de quem marcou e põe a reunião na agenda' do
      allow(Ramon::Fluxos::Reunioes).to receive(:na_agenda)
      config = { 'titulo' => '{titulo_tarefa}', 'tipo' => 'meeting', 'prazo' => 'reuniao' }
      Ramon::Fluxos::Passos::Lead.criar_tarefa(config, ctx(contexto: gatilho))
      tarefa = lead.lead_tasks.find_by!(kind: 'meeting')
      expect([tarefa.title, tarefa.due_at, tarefa.user]).to eq(['Reunião Cal.com: Primeiro', Time.zone.parse('2026-10-07T22:00:00Z'), agente])
      expect(Ramon::Fluxos::Reunioes).to have_received(:na_agenda).with(tarefa, true)
    end

    it 'ensaio da tarefa diz o prazo; da atividade, o tipo e o de → para' do
      c = ctx(ensaio: true, contexto: gatilho)
      tarefa = Ramon::Fluxos::Passos::Lead.criar_tarefa({ 'titulo' => '{titulo_tarefa}', 'tipo' => 'meeting', 'prazo' => 'reuniao' }, c)
      atividade = Ramon::Fluxos::Passos::Lead.registrar_atividade({ 'tipo' => 'meeting_cancelled', 'texto' => '{resumo}' }, c)
      expect(tarefa[:resumo]).to eq('faria: tarefa "Reunião Cal.com: Primeiro" para 07/10 19:00')
      expect(atividade[:resumo]).to eq('faria: atividade meeting_cancelled: Primeiro em 07/10/2026 19:00')
      expect(lead.lead_tasks.count + lead.lead_activities.where(kind: 'meeting_cancelled').count).to eq(0)
    end

    it 'rascunho nas notas do lead com o título do código, mesmo com conversa' do
      config = { 'onde' => 'notas_do_lead', 'titulo' => 'confirmação de reunião', 'texto' => 'Oi {nome}!' }
      expect { Ramon::Fluxos::Passos::Conversa.rascunho_texto(config, ctx) }.not_to(change { conversa.messages.count })
      expect(lead.lead_notes.last.body).to start_with("RASCUNHO (revisar antes de enviar) — confirmação de reunião:\nOi ")
    end

    it 'apagar a reunião: só as tarefas de reunião do evento, do próprio lead' do
      t1 = create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'R1', due_at: 1.day.from_now)
      t2 = create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'R2', due_at: 2.days.from_now)
      outra = create(:lead_task, account: account, lead: create(:lead, account: account), kind: 'meeting', title: 'X', due_at: 1.day.from_now)
      r = Ramon::Fluxos::Passos::Reuniao.apagar_reuniao({}, ctx(contexto: { 'gatilho' => { 'tarefa_ids' => [t1.id, outra.id] } }))
      expect(LeadTask.where(id: [t1.id, t2.id, outra.id]).pluck(:id)).to contain_exactly(t2.id, outra.id)
      expect(r[:resumo]).to eq("apagou tarefas ##{t1.id}") # lista o que apagou de fato
    end
  end
```

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/passos_spec.rb`
Expected: FAIL — atividade sai `fluxo` sem `from_value`/user; tarefa vence no fim do dia e é do responsável; ensaio da tarefa sem prazo; rascunho vai para a conversa; `uninitialized constant Ramon::Fluxos::Passos::Reuniao`.

- [ ] **Step 3: Implementation**

(a) `app/services/ramon/fluxos/passos/lead.rb` — logo abaixo de `module Ramon::Fluxos::Passos::Lead`:

```ruby
  # B4.1: tipos de atividade que um fluxo pode registrar (os de reunião aparecem como os do código).
  TIPOS_ATIVIDADE = %w[fluxo meeting_scheduled meeting_rescheduled meeting_cancelled].freeze
```

trocar o `criar_tarefa` inteiro por:

```ruby
  def criar_tarefa(config, ctx)
    lead = exigir_lead(ctx)
    titulo = ctx.interpolar(config['titulo']).truncate(255)
    prazo = prazo_da_tarefa(config, ctx)
    return { saida: 's', resumo: "faria: tarefa \"#{titulo}\" para #{Ramon::Fluxos::Passos::Logica.hora(prazo)}" } if ctx.ensaio?

    responsavel = responsavel_da_tarefa(lead, config, ctx)
    tarefa = lead.lead_tasks.create!(account: lead.account, kind: kind_da_tarefa(config), title: titulo, due_at: prazo, user: responsavel)
    # B4.1: a tarefa da própria reunião põe a reunião na agenda → começa o ciclo de lembretes dela (fluxos no comando)
    Ramon::Fluxos::Reunioes.na_agenda(tarefa, true) if config['prazo'] == 'reuniao' && tarefa.kind == 'meeting'
    { saida: 's', resumo: "tarefa \"#{titulo}\" · #{responsavel&.name || 'sem responsável'}" }
  end
```

trocar o `registrar_atividade` inteiro por:

```ruby
  # B4.1: tipo (as de reunião iguais às do código), "de" opcional (remarcada: de → para) e a pessoa que marcou.
  def registrar_atividade(config, ctx)
    lead = exigir_lead(ctx)
    tipo = TIPOS_ATIVIDADE.include?(config['tipo']) ? config['tipo'] : 'fluxo'
    texto = ctx.interpolar(config['texto']).truncate(255)
    de = ctx.interpolar(config['de']).truncate(255).presence
    return { saida: 's', resumo: "faria: atividade #{tipo}: #{[de, texto].compact.join(' → ')}" } if ctx.ensaio?

    lead.lead_activities.create!(account: lead.account, user: ctx.quem_marcou, kind: tipo, from_value: de, to_value: texto)
    { saida: 's', resumo: "atividade: #{texto.truncate(80)}" }
  end
```

e trocar o `responsavel_da_tarefa` por:

```ruby
  # B4.1: prazo 'reuniao' = vence na hora da reunião do gatilho; senão, N dias a partir de hoje (fim do dia, SP).
  def prazo_da_tarefa(config, ctx)
    return ctx.reuniao_em || raise(Ramon::Fluxos::PassoImpossivel, 'sem reunião marcada para o prazo') if config['prazo'] == 'reuniao'

    (Time.find_zone!(Fluxo::ZONA).now + config.fetch('prazo_dias', 1).to_i.days).end_of_day
  end

  # Tarefa da reunião é de quem marcou (como no código); as outras, a pessoa escolhida ou o responsável do lead.
  def responsavel_da_tarefa(lead, config, ctx)
    return ctx.quem_marcou if config['prazo'] == 'reuniao'

    config['responsavel_id'].present? ? usuario_da_conta(lead, config['responsavel_id']) : (lead.closer || lead.sdr)
  end
```

(b) `app/services/ramon/fluxos/passos/conversa.rb` — trocar `rascunho_texto` e `escrever`:

```ruby
  def rascunho_texto(config, ctx)
    texto = ctx.interpolar(config['texto'])
    return { saida: 's', resumo: "faria: rascunho \"#{texto.truncate(120)}\"" } if ctx.ensaio?

    escrever(ctx, "#{cabecalho(config)}\n#{texto}", onde: config['onde'])
    { saida: 's', resumo: "rascunho criado: #{texto.truncate(120)}" }
  end
```

e

```ruby
  def escrever(ctx, texto)
    if ctx.conversa
```

por

```ruby
  # "RASCUNHO (revisar antes de enviar):"; com título (B4.1), "RASCUNHO (revisar antes de enviar) — confirmação de reunião:"
  def cabecalho(config)
    titulo = config['titulo'].to_s.strip
    titulo.empty? ? Ramon::RascunhoCarimbo::PREFIXO : "#{Ramon::RascunhoCarimbo::PREFIXO.delete_suffix(':')} — #{titulo}:"
  end

  # onde 'notas_do_lead' (B4.1): como o rascunho de confirmação do código, mesmo se o lead tiver conversa.
  def escrever(ctx, texto, onde: nil)
    if ctx.conversa && onde != 'notas_do_lead'
```

(o resto do `escrever` fica igual; `nota_privada` continua chamando `escrever(ctx, texto)`).

(c) Criar `app/services/ramon/fluxos/passos/reuniao.rb`:

```ruby
# Passo da reunião cancelada (B4.1): apaga a(s) tarefa(s) de reunião do evento — as que o painel ou o Cal.com mandaram
# no gatilho ('tarefa_ids'), só do próprio lead. Apagar a tarefa também encerra o ciclo de lembretes dela (alvo apagado).
module Ramon::Fluxos::Passos::Reuniao
  module_function

  def apagar_reuniao(_config, ctx)
    lead = Ramon::Fluxos::Passos::Lead.exigir_lead(ctx)
    ids = Array(ctx.gatilho('tarefa_ids')).map(&:to_i).sort
    lista = ids.any? ? ids.map { |id| "##{id}" }.join(', ') : '(nenhuma)'
    return { saida: 's', resumo: "faria: apagar tarefas #{lista}" } if ctx.ensaio?

    apagadas = lead.lead_tasks.where(id: ids, kind: 'meeting').destroy_all.map(&:id).sort
    { saida: 's', resumo: "apagou tarefas #{apagadas.any? ? apagadas.map { |id| "##{id}" }.join(', ') : '(nenhuma)'}" }
  end
end
```

(d) `app/services/ramon/fluxos/executor.rb` — em `VISIVEIS` acrescentar `apagar_reuniao`:

```ruby
  VISIVEIS = %w[mover_etapa criar_tarefa acao_chatwoot avisar_sino avisar_push trocar_responsavel preencher_campo advbox webhook
                apagar_reuniao].freeze
```

e em `PASSOS`, depois da linha do `preencher_campo`:

```ruby
    'apagar_reuniao' => Ramon::Fluxos::Passos::Reuniao,
```

(e) `app/services/ramon/fluxos/grafo.rb` — em `TIPOS_PASSO`, trocar

```ruby
                   registrar_atividade trocar_responsavel preencher_campo].freeze
```

por

```ruby
                   registrar_atividade trocar_responsavel preencher_campo apagar_reuniao].freeze
```

Rastreio: (1) `{resumo_antes}`/`{resumo}` vêm do gatilho (`DO_GATILHO`) → from/to; `ctx.quem_marcou` = agente. (2) `prazo_da_tarefa` → `reuniao_em` = 22:00Z; dona = agente; `na_agenda(tarefa, true)` (stub). (3) ensaio: `hora(22:00Z)` = "07/10 19:00"; nada criado. (4) `cabecalho` = "RASCUNHO (revisar antes de enviar) — confirmação de reunião:"; `onde` → `lead_notes` mesmo com `conversa`. (5) só `t1` (do lead) sai. Complexidade: `criar_tarefa` = `if` ensaio + `if &&` + `||` + `&.` → 6.

- [ ] **Step 4: Run to verify they pass**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/` e `bundle exec rubocop app/services/ramon/fluxos/passos/ app/services/ramon/fluxos/executor.rb app/services/ramon/fluxos/grafo.rb`
Expected: PASS (inclusive `'todo tipo de passo do desenho tem quem execute'`, `'registrar atividade escreve na linha do tempo do lead'` e `'tarefa na Esteira com prazo relativo'`), sem ofensas (`Passos::Lead` fica < 100 linhas de código).

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/passos/lead.rb app/services/ramon/fluxos/passos/conversa.rb app/services/ramon/fluxos/passos/reuniao.rb app/services/ramon/fluxos/executor.rb app/services/ramon/fluxos/grafo.rb spec/services/ramon/fluxos/passos_spec.rb
git commit -m "feat(fluxos): atividade e tarefa da reunião, rascunho nas notas do lead e passo apagar reunião" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 6: `ReuniaoAgendamento` decide uma vez por evento + a chave

**Files:**
- Modify: `app/services/ramon/reuniao_agendamento.rb` (arquivo inteiro)
- Modify: `app/controllers/public/api/v1/calcom_webhooks_controller.rb:56-66` (`handle_cancelled`), `:68-79` (`handle_rescheduled`), privados (`calcom_tasks` no lugar de `purge_calcom_tasks`; saem `notify` e `meeting_summary`)
- Modify: `app/services/ramon/fluxos/reunioes.rb` (+ `ligada?`, `assumiu?`, `fluxos`, `mudar_modo!`, `descrever`)
- Modify: `.env.example`
- Test: `spec/services/ramon/reuniao_agendamento_spec.rb`, `spec/services/ramon/fluxos/reunioes_spec.rb`; `spec/requests/public/api/v1/calcom_webhooks_spec.rb` (sem mudança — trava)

**Interfaces:**
- Consumes: `Reunioes::GATILHOS`, `.na_agenda` (Task 3).
- Produces: gatilhos `reuniao_marcada` e `reuniao_cancelada` com `dados = {'evento' => 'marcada'|'remarcada'|'cancelada', 'assumido' => Boolean, 'quando', 'inicio' (ISO), 'titulo', 'resumo', 'primeiro_nome', 'quem_marcou_id'}` + `'titulo_tarefa'` (marcada) / `'resumo_antes'` (remarcada) / `'tarefa_ids'` (cancelada). Disparados **antes** dos efeitos do código. `Ramon::ReuniaoAgendamento.cancelar_tarefas(lead:, tarefas:, starts_at:, title:)` (Cal.com). `Reunioes.ligada? → Boolean` (`RAMON_FLUXO_REUNIOES == 'on'`); `.assumiu?(account) → Boolean`; `.fluxos(account) → Relation`; `.mudar_modo!(account, 'normal'|'sombra') → Array<Fluxo>` (`ArgumentError` sem os 3 ou `normal` sem a env); `.descrever(account) → String`. **A chave desliga a cadeia inteira em 3 pontos do mesmo arquivo** (`#call`, `#remarcar` — menos mover a tarefa —, `#cancelar`).

- [ ] **Step 1: Write the failing tests**

(a) `spec/services/ramon/reuniao_agendamento_spec.rb`, antes do `end` final:

```ruby
  describe 'B4.1: o evento decide uma vez quem faz' do
    it 'código no comando: o ensaio dos fluxos vem antes e leva os textos prontos' do
      tarefas_no_ensaio = nil
      allow(Ramon::Fluxos::Disparo).to receive(:externo) { |gatilho, *| tarefas_no_ensaio ||= lead.lead_tasks.count if gatilho == 'reuniao_marcada' }
      agendar
      expect(tarefas_no_ensaio).to eq(0)
      expect(Ramon::Fluxos::Disparo).to have_received(:externo).with(
        'reuniao_marcada', lead,
        hash_including('evento' => 'marcada', 'assumido' => false, 'inicio' => starts_at.iso8601, 'quem_marcou_id' => user.id,
                       'resumo' => 'Primeiro Atendimento em 15/07/2026 11:00', 'primeiro_nome' => 'João',
                       'titulo_tarefa' => 'Primeiro Atendimento')
      )
      expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('reuniao_na_agenda', lead.lead_tasks.last, hash_including('assumido' => false))
    end

    it 'remarcar leva o resumo de antes; cancelar leva as tarefas' do
      allow(Ramon::Fluxos::Disparo).to receive(:externo)
      agendar
      task = lead.lead_tasks.find_by!(kind: 'meeting')
      described_class.remarcar(task: task, starts_at: starts_at + 1.day, user: user)
      described_class.cancelar(task: task.reload, user: user)
      expect(Ramon::Fluxos::Disparo).to have_received(:externo)
        .with('reuniao_marcada', lead, hash_including('evento' => 'remarcada', 'resumo_antes' => 'Primeiro Atendimento em 15/07/2026 11:00'))
      expect(Ramon::Fluxos::Disparo).to have_received(:externo)
        .with('reuniao_cancelada', lead, hash_including('evento' => 'cancelada', 'tarefa_ids' => [task.id]))
    end

    context 'com os fluxos no comando (env + os 3 em modo normal)' do
      around { |ex| with_modified_env(RAMON_FLUXO_REUNIOES: 'on') { ex.run } }

      before do
        Ramon::Fluxos::Reunioes::GATILHOS.each do |chave, gatilho|
          fluxo_publicado(account, grafo_linear({ 'tipo' => gatilho }, ['parar', {}]), sistema_chave: chave, modo: 'normal')
        end
      end

      it 'marcar e cancelar: o código só dispara (quem faz é o fluxo — aqui, de teste, só "parar")' do
        travel_to(Time.zone.parse('2026-07-14T12:00:00Z')) do
          expect { agendar }.not_to have_enqueued_job(Ramon::MeetingReminderJob)
        end
        expect([lead.lead_tasks.count, lead.lead_activities.where(kind: 'meeting_scheduled').count, lead.lead_notes.count]).to eq([0, 0, 0])
        task = create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'Primeiro Atendimento', due_at: starts_at)
        described_class.cancelar(task: task, user: user)
        expect(LeadTask.exists?(task.id)).to be(true)
      end

      it 'remarcar: o código só move a tarefa' do
        task = create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'Primeiro Atendimento', due_at: starts_at)
        travel_to(Time.zone.parse('2026-07-14T12:00:00Z')) do
          expect { described_class.remarcar(task: task, starts_at: starts_at + 1.day, user: user) }
            .not_to have_enqueued_job(Ramon::MeetingReminderJob)
        end
        expect(task.reload.due_at).to eq(starts_at + 1.day)
        expect(lead.lead_activities.where(kind: 'meeting_rescheduled')).to be_empty
      end
    end
  end
```

(b) `spec/services/ramon/fluxos/reunioes_spec.rb`, antes do `end` final:

```ruby
  describe 'a chave (RAMON_FLUXO_REUNIOES=on + os 3 fluxos em modo normal)' do
    let!(:fluxos) do
      described_class::GATILHOS.to_h do |chave, gatilho|
        [chave, fluxo_publicado(account, grafo_linear({ 'tipo' => gatilho }, ['parar', {}]), sistema_chave: chave, modo: 'sombra')]
      end
    end

    it 'só assume com a env ligada e os 3 normais, ligados, publicados e com o gatilho certo' do
      expect(described_class.assumiu?(account)).to be(false)
      with_modified_env(RAMON_FLUXO_REUNIOES: 'on') do
        expect(described_class.assumiu?(account)).to be(false) # ainda em sombra
        described_class.mudar_modo!(account, 'normal')
        expect(described_class.assumiu?(account)).to be(true)
        fluxos['reuniao_cancelada'].update!(ativo: false)
        expect(described_class.assumiu?(account)).to be(false) # 1 desligado na tela devolve tudo ao código
      end
      fluxos['reuniao_cancelada'].update!(ativo: true)
      expect(described_class.assumiu?(account)).to be(false) # sem a env
    end

    it 'virar para normal sem a env é recusado; voltar para sombra vira os 3 juntos' do
      expect { described_class.mudar_modo!(account, 'normal') }.to raise_error(ArgumentError, /RAMON_FLUXO_REUNIOES/)
      with_modified_env(RAMON_FLUXO_REUNIOES: 'on') do
        described_class.mudar_modo!(account, 'normal')
        described_class.mudar_modo!(account, 'sombra')
      end
      expect(fluxos.values.map { |f| f.reload.modo }).to all(eq('sombra'))
      expect(described_class.descrever(account)).to include('o CÓDIGO faz o agendamento')
    end
  end
```

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/services/ramon/reuniao_agendamento_spec.rb spec/services/ramon/fluxos/reunioes_spec.rb`
Expected: FAIL — o gatilho só leva `quando` e sai depois dos efeitos; o código faz tudo mesmo com os fluxos normais; `undefined method 'assumiu?'`.

- [ ] **Step 3: Implementation**

(a) Substituir `app/services/ramon/reuniao_agendamento.rb` inteiro por:

```ruby
# Reunião marcada — mesmo efeito venha do Cal.com (webhook) ou do painel do
# lead ("+ Tarefa" → Reunião): tarefa kind meeting, lead anda pra "Reunião
# agendada" (só pra frente), Closer automático, rascunho de confirmação nas
# notas (NUNCA enviado — quem envia é a pessoa), lembretes internos (sino +
# ntfy), atividade e aviso no sino.
# B4.1: cada evento (marcar, remarcar, cancelar) decide UMA vez quem faz (Ramon::Fluxos::Reunioes.assumiu?) e dispara
# o gatilho com essa decisão ('assumido') e os textos prontos. Código no comando: os fluxos ensaiam ANTES (veem o lead
# como estava) e o código faz tudo. Fluxos no comando: o código só dispara (e, no remarcar, move a tarefa).
class Ramon::ReuniaoAgendamento
  # ponytail: fork single-tenant do escritório (Tubarão/SC) — fuso fixo para o
  # texto humano; parametrizar se um dia houver mais contas.
  TIME_ZONE = 'America/Sao_Paulo'.freeze
  DIAS_SEMANA = %w[domingo segunda terça quarta quinta sexta sábado].freeze
  STAGE_LABEL = 'fase-reuniao-agendada'.freeze
  # Prefixo do título da tarefa que veio do Cal.com (o webhook acha por ele).
  CALCOM_PREFIX = 'Reunião Cal.com'.freeze

  # title = nome da reunião (atividade, sino); task_title = título da tarefa
  # (o Cal.com prefixa "Reunião Cal.com:" — o cancel/reschedule acham por ele).
  def self.call(lead:, starts_at:, title:, task_title: title, user: nil)
    new(lead, starts_at, title, user).call(task_title)
  end

  # Remarcar (painel do lead): a mesma reunião em outro horário — lembretes do
  # horário novo (os do antigo viram órfãos e o job descarta), atividade
  # de→para, novo rascunho de confirmação (não enviado) e aviso no sino.
  def self.remarcar(task:, starts_at:, user: nil)
    new(task.lead, starts_at, titulo_de(task), user).remarcar(task)
  end

  # Cancelar (painel do lead): atividade meeting_cancelled, a tarefa sai e sino/ntfy. Os lembretes já
  # enfileirados viram órfãos e o guard do MeetingReminderJob descarta.
  def self.cancelar(task:, user: nil)
    new(task.lead, task.due_at, titulo_de(task), user).cancelar([task])
  end

  # Cancelar pelo Cal.com: as tarefas Cal.com abertas daquele horário (pode não haver nenhuma).
  def self.cancelar_tarefas(lead:, tarefas:, starts_at:, title:)
    new(lead, starts_at, title, nil).cancelar(tarefas)
  end

  # "Reunião Cal.com: Primeiro Atendimento" → "Primeiro Atendimento"
  def self.titulo_de(task)
    task.title.delete_prefix("#{CALCOM_PREFIX}: ")
  end

  # "quinta, 20/08 às 14:00" — texto único pra sino e rascunho.
  def self.quando(starts_at)
    local = starts_at.in_time_zone(TIME_ZONE)
    "#{DIAS_SEMANA[local.wday]}, #{local.strftime('%d/%m')} às #{local.strftime('%H:%M')}"
  end

  # Sino do hub pra todo mundo da conta + push no celular na hora (o job é
  # no-op sem NTFY_TOPIC); os lembretes têm o seu no MeetingReminderJob.
  def self.notify(lead, type, starts_at, title, verbo: nil)
    quando = starts_at ? quando(starts_at) : ''
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: type, meta: { 'quando' => quando }).perform
    verbo ||= type == 'ramon_meeting_cancelled' ? 'cancelada' : 'marcada'
    Ramon::NtfyPushJob.perform_later(lead.id, title: "Reuniao #{verbo}: #{lead.name}", body: "#{quando} — #{title}")
  end

  # "Primeiro Atendimento em 20/08/2026 14:00" — to_value da atividade.
  def self.resumo(title, starts_at)
    when_text = starts_at ? starts_at.in_time_zone(TIME_ZONE).strftime('%d/%m/%Y %H:%M') : ''
    "#{title} em #{when_text}".strip.truncate(255)
  end

  def initialize(lead, starts_at, title, user)
    @lead = lead
    @starts_at = starts_at
    @title = title
    @user = user
  end

  def call(task_title)
    assumido = assumido?
    disparar('reuniao_marcada', dados('marcada', assumido, 'titulo_tarefa' => task_title.truncate(255)))
    return @lead if assumido

    task = registrar(task_title)
    advance_stage
    Ramon::Papeis.atribuir_closer!(@lead)
    confirmation_draft
    enqueue_reminders
    self.class.notify(@lead, 'ramon_meeting_scheduled', @starts_at, @title)
    Ramon::Fluxos::Reunioes.na_agenda(task, false)
    @lead
  end

  # Mover a tarefa é a remarcação em si e fica sempre aqui; o resto é do código ou dos fluxos.
  def remarcar(task)
    de = task.due_at
    task.update!(due_at: @starts_at)
    assumido = assumido?
    disparar('reuniao_marcada', dados('remarcada', assumido, 'resumo_antes' => self.class.resumo(@title, de)))
    efeitos_da_remarcacao(de) unless assumido
    Ramon::Fluxos::Reunioes.na_agenda(task, assumido)
    task
  end

  def cancelar(tarefas)
    assumido = assumido?
    disparar('reuniao_cancelada', dados('cancelada', assumido, 'tarefa_ids' => tarefas.map(&:id)))
    return if assumido

    @lead.lead_activities.create!(account: @lead.account, user: @user, kind: 'meeting_cancelled',
                                  to_value: self.class.resumo(@title, @starts_at))
    tarefas.each(&:destroy!)
    self.class.notify(@lead, 'ramon_meeting_cancelled', @starts_at, @title)
  end

  private

  def assumido? = Ramon::Fluxos::Reunioes.assumiu?(@lead.account)

  def disparar(gatilho, dados) = Ramon::Fluxos::Disparo.externo(gatilho, @lead, dados)

  # O que o gatilho leva: a decisão do evento e os textos prontos, para o fluxo escrever igual ao código.
  def dados(evento, assumido, extra)
    {
      'evento' => evento, 'assumido' => assumido, 'quando' => @starts_at ? self.class.quando(@starts_at) : '',
      'inicio' => @starts_at&.iso8601, 'titulo' => @title, 'resumo' => self.class.resumo(@title, @starts_at),
      'primeiro_nome' => primeiro_nome, 'quem_marcou_id' => @user&.id
    }.merge(extra).compact
  end

  def primeiro_nome = @lead.name.to_s.split.first.presence || 'cliente'

  def registrar(task_title)
    @lead.lead_activities.create!(account: @lead.account, user: @user, kind: 'meeting_scheduled',
                                  to_value: self.class.resumo(@title, @starts_at))
    @lead.lead_tasks.create!(account: @lead.account, user: @user, title: task_title.truncate(255), kind: 'meeting', due_at: @starts_at)
  end

  def efeitos_da_remarcacao(de)
    @lead.lead_activities.create!(account: @lead.account, user: @user, kind: 'meeting_rescheduled',
                                  from_value: self.class.resumo(@title, de), to_value: self.class.resumo(@title, @starts_at))
    confirmation_draft
    enqueue_reminders
    # sino reaproveita o tipo "reunião marcada" (texto: com o horário novo)
    self.class.notify(@lead, 'ramon_meeting_scheduled', @starts_at, @title, verbo: 'remarcada')
  end

  # Nunca regride: quem já está em Negociação e remarcou fica onde está.
  def advance_stage
    stage = @lead.account.lead_stages.find_by(label: STAGE_LABEL)
    return if stage.blank? || @lead.lead_stage.position >= stage.position

    @lead.update!(lead_stage: stage)
  end

  # Rascunho de confirmação (gatilho do compromisso) — estático, sem LLM. O fluxo "Reunião marcada" copia este texto.
  def confirmation_draft
    @lead.lead_notes.create!(account: @lead.account, body: <<~NOTA.strip.truncate(1000))
      RASCUNHO (revisar antes de enviar) — confirmação de reunião:
      "Oi #{primeiro_nome}! Nossa conversa está confirmada pra #{self.class.quando(@starts_at)}. Vou te esperar, tá? Se não puder comparecer, me avise com antecedência que a gente remarca sem problema."
    NOTA
  end

  # Lembretes anti no-show: só offsets ainda no futuro; cancel/reschedule não
  # desagenda — o guard do job mata o lembrete órfão.
  def enqueue_reminders
    Ramon::MeetingReminderJob::OFFSETS.each do |offset, label|
      fire_at = @starts_at - offset
      next if fire_at.past?

      Ramon::MeetingReminderJob.set(wait_until: fire_at).perform_later(@lead.id, @starts_at.iso8601, label)
    end
  end
end
```

(O rascunho é o mesmo de antes: `first = @lead.name.to_s.split.first.presence || 'cliente'` virou `primeiro_nome`, o mesmo valor que vai no gatilho como `{primeiro_nome}`. A linha do heredoc já existia com esse comprimento.)

(b) `app/controllers/public/api/v1/calcom_webhooks_controller.rb` — trocar o corpo de `handle_cancelled`

```ruby
    purge_calcom_tasks(lead, due_at: start_at)
    lead.lead_activities.create!(account: account, kind: 'meeting_cancelled', to_value: meeting_summary)
    notify(lead, 'ramon_meeting_cancelled')
    :ok
```

por

```ruby
    # B4.1: o mesmo cancelar do painel (o código ou o fluxo "Reunião cancelada" faz, conforme a chave)
    Ramon::ReuniaoAgendamento.cancelar_tarefas(lead: lead, tarefas: calcom_tasks(lead, due_at: start_at).to_a,
                                               starts_at: start_at, title: event_title)
    :ok
```

no `handle_rescheduled`, trocar `purge_calcom_tasks(lead)` por `calcom_tasks(lead).destroy_all`; apagar os métodos privados `notify` e `meeting_summary`; e trocar `purge_calcom_tasks` por:

```ruby
  def calcom_tasks(lead, due_at: nil)
    tasks = lead.lead_tasks.open_tasks.where(kind: 'meeting').where('title LIKE ?', "#{TASK_TITLE_PREFIX}%")
    due_at.present? ? tasks.where(due_at: due_at) : tasks
  end
```

Conferir: `grep -n "meeting_summary\|purge_calcom_tasks\|notify(" app/controllers/public/api/v1/calcom_webhooks_controller.rb` → nada. Efeito idêntico ao de antes: mesmas tarefas apagadas (com ou sem horário), atividade `meeting_cancelled` sem usuário com `resumo(event_title, start_at)`, sino e push.

(c) `app/services/ramon/fluxos/reunioes.rb` — antes do `end` final:

```ruby
  def ligada? = ENV.fetch('RAMON_FLUXO_REUNIOES', nil) == 'on'

  # A chave (B4.1): os fluxos fazem o agendamento inteiro só com a env ligada E os 3 fluxos migrados ligados,
  # publicados, em modo normal e com o gatilho esperado. Qualquer peça fora → o código faz tudo e os fluxos ensaiam.
  def assumiu?(account)
    return false unless ligada?

    atuais = account.fluxos.executaveis.where(origem: 'usuario', modo: 'normal', sistema_chave: GATILHOS.keys)
                    .pluck(:sistema_chave, :gatilho_tipo)
    atuais.sort == GATILHOS.to_a.sort
  end

  def fluxos(account) = account.fluxos.where(origem: 'usuario', sistema_chave: GATILHOS.keys).order(:id)

  # normal = os fluxos assumem o agendamento inteiro; sombra = devolve ao código na hora. Os 3 juntos.
  def mudar_modo!(account, modo)
    lista = fluxos(account).to_a
    raise ArgumentError, 'Os fluxos de reunião ainda não existem: rode ramon:fluxos:reunioes:sombra' if lista.size < GATILHOS.size
    raise ArgumentError, 'Ligue RAMON_FLUXO_REUNIOES=on antes (sem ela o código continua fazendo tudo)' if modo == 'normal' && !ligada?

    Fluxo.transaction { lista.each { |fluxo| fluxo.update!(modo: modo) } }
    lista
  end

  def descrever(account)
    quem = assumiu?(account) ? 'os FLUXOS fazem o agendamento (o código não faz mais)' : 'o CÓDIGO faz o agendamento (os fluxos ensaiam)'
    linhas = fluxos(account).map { |f| "Fluxo ##{f.id} \"#{f.nome}\" — modo #{f.modo}, #{f.ativo ? 'ligado' : 'desligado'}" }
    [*linhas, "Agora #{quem}."].join("\n")
  end
```

(d) `.env.example` — depois das 2 linhas do `RAMON_COPILOTO_MODO_DEFAULT`:

```
# ramon: agendamento de reunioes pelos fluxos (B4.1). on + os 3 fluxos de reuniao em modo normal = os fluxos marcam,
# remarcam, cancelam e lembram, e o codigo para. Padrao desligado (o codigo faz). Virar/voltar: rake ramon:fluxos:reunioes:modo[conta,normal|sombra]
# RAMON_FLUXO_REUNIOES=off
```

Rastreio (a1): `Disparo.externo` é stub; no `call`, o 1º disparo (`reuniao_marcada`) acontece antes de `registrar` → 0 tarefas; o `na_agenda` usa `Disparo.externo` (stub) com a tarefa. (a2) `remarcar(task)` → `task.lead` (outro objeto Ruby, `==` por id); `cancelar(task:)` → `tarefa_ids` `[task.id]`. (a3) fluxos de teste com `parar`, migrados, env on → `assumiu?` true → `call` só dispara (o "Reunião marcada" de teste roda na hora e para); nenhum job, tarefa, atividade ou nota; `cancelar` não apaga. (a4) `remarcar` move a tarefa, não cria atividade nem job. (b) `assumiu?` compara os pares `[chave, gatilho]` dos 3 executáveis normais com `GATILHOS`.

- [ ] **Step 4: Run to verify they pass**

Run (CI): `bundle exec rspec spec/services/ramon/reuniao_agendamento_spec.rb spec/services/ramon/fluxos/reunioes_spec.rb spec/requests/public/api/v1/calcom_webhooks_spec.rb spec/jobs/ramon/meeting_reminder_job_spec.rb spec/controllers/api/v1/accounts/lead_reunioes_agendadas_controller_spec.rb` (o último só se existir) e `bundle exec rubocop app/services/ramon/reuniao_agendamento.rb app/controllers/public/api/v1/calcom_webhooks_controller.rb app/services/ramon/fluxos/reunioes.rb`
Expected: PASS (os exemplos antigos do `ReuniaoAgendamento` — tarefa, atividade, etapa, Closer, 3 e 5 lembretes, rascunho, sinos, cancelamento — seguem verdes com a env desligada; o request spec do Cal.com também), sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/reuniao_agendamento.rb app/controllers/public/api/v1/calcom_webhooks_controller.rb app/services/ramon/fluxos/reunioes.rb .env.example spec/services/ramon/reuniao_agendamento_spec.rb spec/services/ramon/fluxos/reunioes_spec.rb
git commit -m "feat(fluxos): agendamento decide uma vez por evento e chave RAMON_FLUXO_REUNIOES (desligada)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 7: Os 3 fluxos (desenhos fiéis) + rake que os cria + ponta a ponta em sombra e no comando

**Files:**
- Create: `db/seeds/ramon/fluxos/migrados/reuniao_marcada.json`, `reuniao_cancelada.json`, `lembretes_reuniao.json`
- Modify: `app/services/ramon/fluxos/reunioes.rb` (+ `PASTA`, `fluxo`, `semear`, `criar`, `com_etapa`)
- Create: `lib/tasks/ramon_fluxos.rake`
- Test: `spec/services/ramon/fluxos/reunioes_spec.rb`; `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/migrados.spec.js` (novo)

**Interfaces:**
- Consumes: Tasks 1–6.
- Produces: `Reunioes.fluxo(account, chave) → Fluxo | nil`; `Reunioes.semear(account) → Array<Fluxo>` (os 3, na ordem de `GATILHOS`; idempotente: existindo, não toca); `mover_etapa` recebe o `etapa_id` da etapa `fase-reuniao-agendada` da conta. Rake `ramon:fluxos:reunioes:sombra[account_id]` e `ramon:fluxos:reunioes:modo[account_id,normal|sombra]`. Ids dos passos: "Reunião marcada" `n1` gatilho, `n2` escolha (`c1` marcada → `n3` atividade → `n4` tarefa → `n5` etapa → `n6` Closer; `c2` remarcada → `n7` atividade), `n8` rascunho, `n9` sino, `n10` push; "Reunião cancelada" `n1`…`n5` (gatilho, atividade, apagar, sino, push); "Lembretes" `n1` gatilho e, para k=0..4 (24h, 8h, 1h, 30min, 5min), `n(2+4k)` esperar, `n(3+4k)` se, `n(4+4k)` sino, `n(5+4k)` push.

- [ ] **Step 1: Write the failing tests**

(a) `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/migrados.spec.js`:

```js
// Fluxos que substituem automações do código (B4.1, db/seeds/ramon/fluxos/migrados/*.json):
// o quadro abre e publica cada um (validação = espelho do Grafo; a etapa o semear põe) e o desenho é fiel ao código.
import { validar } from '../validar';
import marcada from '../../../../../../../../db/seeds/ramon/fluxos/migrados/reuniao_marcada.json';
import cancelada from '../../../../../../../../db/seeds/ramon/fluxos/migrados/reuniao_cancelada.json';
import lembretes from '../../../../../../../../db/seeds/ramon/fluxos/migrados/lembretes_reuniao.json';

const semEtapa = d =>
  validar(d.desenho).filter(
    e => !(e.codigo === 'FALTA' && e.params.campo === 'etapa_id')
  );
const doTipo = (d, tipo) => d.desenho.nos.filter(n => n.tipo === tipo);
const RASCUNHO =
  '"Oi {primeiro_nome}! Nossa conversa está confirmada pra {quando}. Vou te esperar, tá? Se não puder comparecer, me avise com antecedência que a gente remarca sem problema."';

describe('fluxos migrados: agendamento de reuniões (B4.1)', () => {
  it('os 3 publicam (só falta a etapa, que o semear põe por conta)', () => {
    [marcada, cancelada, lembretes].forEach(d => expect(semEtapa(d)).toEqual([]));
    expect(
      [marcada, cancelada, lembretes].map(d => d.desenho.nos[0].config)
    ).toEqual([
      { tipo: 'reuniao_marcada', cancelar_se_sair_da_etapa: false },
      { tipo: 'reuniao_cancelada', cancelar_se_sair_da_etapa: false },
      { tipo: 'reuniao_na_agenda', cancelar_se_sair_da_etapa: false },
    ]);
  });

  it('marcada faz tudo; remarcada só a atividade; os dois juntam no rascunho, sino e push', () => {
    const { setas } = marcada.desenho;
    const de = (id, saida) => setas.find(s => s.de === id && s.saida === saida)?.para;
    expect([de('n2', 'c1'), de('n3', 's'), de('n4', 's'), de('n5', 's'), de('n6', 's')]).toEqual(['n3', 'n4', 'n5', 'n6', 'n8']);
    expect([de('n2', 'c2'), de('n7', 's'), de('n8', 's'), de('n9', 's')]).toEqual(['n7', 'n8', 'n9', 'n10']);
    expect(doTipo(marcada, 'criar_tarefa')[0].config).toMatchObject({ tipo: 'meeting', prazo: 'reuniao' });
    expect(doTipo(marcada, 'mover_etapa')[0].config.so_para_frente).toBe(true);
    expect(doTipo(marcada, 'trocar_responsavel')[0].config).toMatchObject({ papel: 'closer', so_se_vazio: true });
  });

  it('o rascunho de confirmação é o texto do código, nas notas do lead e com o título do código', () => {
    expect(doTipo(marcada, 'rascunho_texto')[0].config).toMatchObject({
      onde: 'notas_do_lead',
      titulo: 'confirmação de reunião',
      texto: RASCUNHO,
    });
  });

  it('cancelada: atividade, apagar a tarefa, sino e push, nesta ordem', () => {
    expect(cancelada.desenho.nos.map(n => n.tipo)).toEqual([
      'gatilho',
      'registrar_atividade',
      'apagar_reuniao',
      'avisar_sino',
      'avisar_push',
    ]);
  });

  it('lembretes: 24h, 8h, 1h, 30 min e 5 min antes da reunião', () => {
    expect(
      doTipo(lembretes, 'esperar').map(n => [n.config.antes_de, n.config.quantidade, n.config.unidade])
    ).toEqual([
      ['reuniao', 24, 'horas'],
      ['reuniao', 8, 'horas'],
      ['reuniao', 1, 'horas'],
      ['reuniao', 30, 'minutos'],
      ['reuniao', 5, 'minutos'],
    ]);
  });

  it('lembretes: só com a reunião de pé e no horário, para o Closer e o SDR; o "não" pula para o próximo', () => {
    doTipo(lembretes, 'se').forEach(n =>
      expect(n.config.condicoes).toEqual([
        { campo: 'reuniao_de_pe', operador: 'igual', valor: 'sim' },
        { campo: 'horario_passou', operador: 'igual', valor: 'nao' },
      ])
    );
    doTipo(lembretes, 'avisar_sino').forEach(n => expect(n.config.para).toBe('closer_e_sdr'));
    const esperas = doTipo(lembretes, 'esperar').map(n => n.id);
    const naos = lembretes.desenho.setas.filter(s => s.saida === 'nao').map(s => s.para);
    expect(naos).toEqual(esperas.slice(1));
  });

  it('nenhum dos 3 fala com o cliente: o único texto ao cliente é o rascunho', () => {
    const tipos = [marcada, cancelada, lembretes].flatMap(d => d.desenho.nos.map(n => n.tipo));
    expect([...new Set(tipos)].sort()).toEqual([
      'apagar_reuniao',
      'avisar_push',
      'avisar_sino',
      'criar_tarefa',
      'escolha',
      'esperar',
      'gatilho',
      'mover_etapa',
      'rascunho_texto',
      'registrar_atividade',
      'se',
      'trocar_responsavel',
    ]);
  });
});
```

(b) `spec/services/ramon/fluxos/reunioes_spec.rb`, antes do `end` final:

```ruby
  describe 'os fluxos de reunião (semeados)' do
    let(:primeira) { account.lead_stages.order(:position).first }
    let(:agendada) { account.lead_stages.find_by!(label: 'fase-reuniao-agendada') }
    let(:inicio) { Time.zone.parse('2026-10-07T22:00:00Z') }
    let!(:fluxos) { described_class.semear(account).index_by(&:sistema_chave) }

    # O relógio dos fluxos (Ramon::FluxoRelogioJob) sem o resto: anda o que venceu.
    def relogio
      FluxoExecucao.where(status: 'esperando', retomar_em: ..Time.current).find_each { |e| Ramon::Fluxos::Executor.new(e).avancar! }
    end

    def trilha(chave) = FluxoExecucao.where(fluxo: fluxos[chave]).order(:id).flat_map(&:trilha).pluck('resumo')

    def sinos = trilha('lembretes_reuniao').grep(/\Afaria: sino/)

    def agendar(alvo = lead, starts_at = inicio)
      Ramon::ReuniaoAgendamento.call(lead: alvo, starts_at: starts_at, title: 'Primeiro Atendimento')
    end

    it 'semear cria os 3 em sombra, ligados e publicados, uma vez só, com a etapa do funil da conta' do
      expect(fluxos.values).to all(have_attributes(origem: 'usuario', modo: 'sombra', ativo: true))
      expect(fluxos.transform_values(&:gatilho_tipo)).to eq(described_class::GATILHOS)
      etapa = fluxos['reuniao_marcada'].versao_publicada.grafo['nos'].find { |n| n['tipo'] == 'mover_etapa' }
      expect(etapa['config']['etapa_id']).to eq(agendada.id)
      fluxos['reuniao_marcada'].update!(nome: 'Meu agendamento')
      expect(described_class.semear(account).map(&:id)).to match_array(fluxos.values.map(&:id))
      expect(fluxos['reuniao_marcada'].reload.nome).to eq('Meu agendamento')
    end

    it 'em sombra: o código agenda como sempre e o ensaio descreve o mesmo, antes de o código mexer' do
      travel_to(inicio - 10.hours) do
        expect { agendar }.to have_enqueued_job(Ramon::MeetingReminderJob).exactly(4).times
      end
      expect(lead.lead_tasks.where(kind: 'meeting').count).to eq(1) # só a do código
      expect(trilha('reuniao_marcada')).to include(
        'faria: atividade meeting_scheduled: Primeiro Atendimento em 07/10/2026 19:00',
        'faria: tarefa "Primeiro Atendimento" para 07/10 19:00',
        "faria: mover para #{agendada.name}",
        'closer: já tem Carla Closer',
        a_string_starting_with('faria: rascunho "\"Oi João! Nossa conversa está confirmada pra quarta, 07/10 às 19:00.'),
        a_string_starting_with('faria: sino para Carla Closer: "Reunião marcada com João Pereira')
      )
      expect(FluxoExecucao.where(fluxo: fluxos['lembretes_reuniao']).pluck(:alvo_type, :ensaio)).to eq([['LeadTask', true]])
    end

    it 'em sombra: cada reunião tem o seu ciclo; cancelar uma não mexe na outra (E3)' do
      travel_to(inicio - 10.hours) do
        agendar
        agendar(lead, inicio + 1.hour)
        relogio
        Ramon::ReuniaoAgendamento.cancelar(task: lead.lead_tasks.find_by!(kind: 'meeting', due_at: inicio))
      end
      [8.hours, 1.hour, 30.minutes, 5.minutes].each { |antes| travel_to(inicio + 1.hour - antes + 30.seconds) { relogio } }

      expect(FluxoExecucao.where(fluxo: fluxos['lembretes_reuniao']).order(:id).pluck(:status)).to eq(%w[cancelada concluida])
      expect(sinos.size).to eq(4)
      expect(sinos).to all(start_with('faria: sino para Carla Closer: "Reunião em '))
      expect(trilha('reuniao_cancelada')).to include(a_string_starting_with('faria: apagar tarefas #'))
    end

    it 'em sombra: remarcar recomeça só o ciclo daquela reunião, pelo horário novo' do
      travel_to(inicio - 10.hours) do
        agendar
        relogio
        Ramon::ReuniaoAgendamento.remarcar(task: lead.lead_tasks.find_by!(kind: 'meeting'), starts_at: inicio + 1.day)
        relogio
      end
      ciclos = FluxoExecucao.where(fluxo: fluxos['lembretes_reuniao']).order(:id)
      expect(ciclos.pluck(:status)).to eq(%w[cancelada esperando])
      expect(ciclos.last.retomar_em).to eq(inicio) # 24h antes da reunião nova
      expect(trilha('reuniao_marcada')).to include('faria: atividade meeting_rescheduled: Primeiro Atendimento em 07/10/2026 19:00 → ' \
                                                   'Primeiro Atendimento em 08/10/2026 19:00')
    end

    it 'em sombra: lead que muda de etapa antes da reunião continua lembrado (como o código)' do
      travel_to(inicio - 10.hours) do
        agendar
        relogio
        lead.update!(lead_stage: account.lead_stages.find_by!(label: 'fase-negociacao'))
      end
      travel_to(inicio - 8.hours + 30.seconds) { relogio }
      expect(sinos.size).to eq(1)
    end

    describe 'com os fluxos no comando (RAMON_FLUXO_REUNIOES=on + modo normal)' do
      around { |ex| with_modified_env(RAMON_FLUXO_REUNIOES: 'on') { ex.run } }

      before { described_class.mudar_modo!(account, 'normal') }

      it 'marcar: os fluxos fazem tudo que o código fazia, e o código nada' do
        admin = create(:user, account: account, role: :administrator)
        novo = create(:lead, account: account, lead_stage: primeira, name: 'Ana Souza')
        create(:team_member, team: create(:team, account: account, name: 'closer'), user: closer)
        travel_to(inicio - 10.hours) { expect { agendar(novo) }.not_to have_enqueued_job(Ramon::MeetingReminderJob) }
        tarefa = novo.lead_tasks.find_by!(kind: 'meeting')
        expect([tarefa.title, tarefa.due_at, novo.reload.lead_stage, novo.closer]).to eq(['Primeiro Atendimento', inicio, agendada, closer])
        expect(novo.lead_activities.find_by!(kind: 'meeting_scheduled').to_value).to eq('Primeiro Atendimento em 07/10/2026 19:00')
        expect(novo.lead_notes.last.body).to eq(
          "RASCUNHO (revisar antes de enviar) — confirmação de reunião:\n\"Oi Ana! Nossa conversa está confirmada pra quarta, " \
          '07/10 às 19:00. Vou te esperar, tá? Se não puder comparecer, me avise com antecedência que a gente remarca sem problema."'
        )
        expect(Notification.where(notification_type: 'ramon_fluxo_aviso').pluck(:user_id)).to contain_exactly(closer.id, admin.id)
        expect(FluxoExecucao.where(fluxo: fluxos['lembretes_reuniao'], alvo: tarefa).pluck(:ensaio)).to eq([false])
      end

      it 'remarcar e cancelar: os fluxos fazem; o código só move a tarefa' do
        travel_to(inicio - 10.hours) do
          agendar
          tarefa = lead.lead_tasks.find_by!(kind: 'meeting')
          Ramon::ReuniaoAgendamento.remarcar(task: tarefa, starts_at: inicio + 1.day)
          Ramon::ReuniaoAgendamento.cancelar(task: tarefa.reload)
          expect(LeadTask.exists?(tarefa.id)).to be(false)
        end
        expect(lead.lead_activities.find_by!(kind: 'meeting_rescheduled').from_value).to eq('Primeiro Atendimento em 07/10/2026 19:00')
        expect(lead.lead_activities.where(kind: 'meeting_cancelled').count).to eq(1)
        expect(lead.lead_notes.count).to eq(2) # confirmação da marcada e da remarcada
        expect(FluxoExecucao.where(fluxo: fluxos['lembretes_reuniao']).order(:id).pluck(:status)).to eq(%w[cancelada esperando])
      end

      it 'os lembretes saem pelo fluxo, de verdade, para o Closer' do
        travel_to(inicio - 10.hours) do
          agendar
          relogio
        end
        travel_to(inicio - 8.hours + 30.seconds) { relogio }
        rotulos = closer.notifications.where(notification_type: 'ramon_fluxo_aviso').map { |n| n.meta['label'] }
        expect(rotulos).to include(a_string_starting_with('Reunião em 8h antes'))
      end

      it 'um fluxo desligado na tela devolve tudo ao código, e os outros só ensaiam (nunca em dobro)' do
        fluxos['reuniao_cancelada'].update!(ativo: false)
        travel_to(inicio - 10.hours) { expect { agendar }.to have_enqueued_job(Ramon::MeetingReminderJob).exactly(4).times }
        expect(lead.lead_tasks.where(kind: 'meeting').count).to eq(1)
        expect(FluxoExecucao.where(fluxo: fluxos['reuniao_marcada']).pluck(:ensaio)).to eq([true])
      end
    end
  end
```

Rastreio dos principais: **sombra/marcar** — `call` lê `assumiu?` = falso (env desligada) → dispara `reuniao_marcada` com `assumido: false` → o "Reunião marcada" (migrado, `NA_HORA`) ensaia **na hora**: `escolha` → c1 → atividade, tarefa ("para 07/10 19:00"), etapa (o lead está na 1ª → `faria: mover para Reunião agendada`), Closer (já tem → `closer: já tem Carla Closer`), rascunho, sino (conta = só a Carla), push → depois o código faz tudo (4 jobs: o de 24h já passou) e chama `na_agenda(task, false)` → ciclo ensaio com alvo `LeadTask`. **E3** — duas tarefas (22:00 e 23:00) → 2 ciclos; o cancelamento apaga a 1ª → o ciclo dela é cancelado ao retomar (14:00 vencido, alvo nil); o da 2ª manda 8h/1h/30min/5min → 4 linhas de sino. **No comando/marcar** — `assumiu?` = verdadeiro → `call` só dispara com `assumido: true` → "Reunião marcada" age na hora: atividade (user nil — sem usuário), tarefa (vence às 22:00Z, dona nil) → `na_agenda(tarefa, true)` → ciclo de verdade (job do fluxo, não `MeetingReminderJob`), etapa → Reunião agendada, Closer → `Papeis.proximo` = Carla (time closer), rascunho idêntico ao do código (cabeçalho com título + texto com `{primeiro_nome}` = "Ana" e `{quando}`), sino para a conta (Carla e admin). **Um desligado** — `assumiu?` falso → código + 4 jobs; o "Reunião marcada" segue ligado e ensaia (`assumido: false`).

- [ ] **Step 2: Run to verify they fail**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/migrados.spec.js --config vitest.local.config.ts`
Expected: FAIL — `Failed to resolve import …/migrados/reuniao_marcada.json`.
Run (CI): `bundle exec rspec spec/services/ramon/fluxos/reunioes_spec.rb`
Expected: FAIL — `undefined method 'semear'`.

- [ ] **Step 3: Implementation**

(a) Criar os 3 JSON (UTF-8, exatamente):

`db/seeds/ramon/fluxos/migrados/reuniao_marcada.json`:

```json
{
  "nome": "Reunião marcada",
  "descricao": "Reunião marcada ou remarcada (painel do lead ou Cal.com), no lugar do código (B4.1): atividade, tarefa da reunião, etapa (só para a frente), Closer automático, rascunho de confirmação nas notas do lead, sino para a conta e push. Remarcar refaz a atividade, o rascunho e o sino, sem tarefa nova, etapa ou Closer. Enquanto o selo disser \"em sombra\", só ensaia: quem faz ainda é o código.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"reuniao_marcada","cancelar_se_sair_da_etapa":false},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"escolha","config":{"rotulo":"Marcada ou remarcada?","campo":"evento","casos":[{"chave":"c1","rotulo":"Marcada","valores":["marcada"]},{"chave":"c2","rotulo":"Remarcada","valores":["remarcada"]}]},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"registrar_atividade","config":{"rotulo":"Atividade: reunião agendada","tipo":"meeting_scheduled","texto":"{resumo}"},"posicao":{"x":-160,"y":280}},
      {"id":"n4","tipo":"criar_tarefa","config":{"rotulo":"Tarefa da reunião (vence na hora, fica com quem marcou)","titulo":"{titulo_tarefa}","tipo":"meeting","prazo":"reuniao"},"posicao":{"x":-160,"y":420}},
      {"id":"n5","tipo":"mover_etapa","config":{"rotulo":"Mover para Reunião agendada (só para a frente)","etapa_id":null,"so_para_frente":true},"posicao":{"x":-160,"y":560}},
      {"id":"n6","tipo":"trocar_responsavel","config":{"rotulo":"Closer automático (se o lead ainda não tem)","papel":"closer","so_se_vazio":true},"posicao":{"x":-160,"y":700}},
      {"id":"n7","tipo":"registrar_atividade","config":{"rotulo":"Atividade: reunião remarcada (de → para)","tipo":"meeting_rescheduled","de":"{resumo_antes}","texto":"{resumo}"},"posicao":{"x":200,"y":280}},
      {"id":"n8","tipo":"rascunho_texto","config":{"rotulo":"Rascunho de confirmação (nas notas do lead)","onde":"notas_do_lead","titulo":"confirmação de reunião","texto":"\"Oi {primeiro_nome}! Nossa conversa está confirmada pra {quando}. Vou te esperar, tá? Se não puder comparecer, me avise com antecedência que a gente remarca sem problema.\""},"posicao":{"x":0,"y":840}},
      {"id":"n9","tipo":"avisar_sino","config":{"rotulo":"Sino para toda a conta","para":"conta","texto":"Reunião {evento} com {nome_completo}: {quando}"},"posicao":{"x":0,"y":980}},
      {"id":"n10","tipo":"avisar_push","config":{"rotulo":"Push: reunião marcada/remarcada","titulo":"Reuniao {evento}: {nome_completo}","texto":"{quando} — {titulo}"},"posicao":{"x":0,"y":1120}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"c1","para":"n3"},
      {"de":"n3","saida":"s","para":"n4"},
      {"de":"n4","saida":"s","para":"n5"},
      {"de":"n5","saida":"s","para":"n6"},
      {"de":"n6","saida":"s","para":"n8"},
      {"de":"n2","saida":"c2","para":"n7"},
      {"de":"n7","saida":"s","para":"n8"},
      {"de":"n8","saida":"s","para":"n9"},
      {"de":"n9","saida":"s","para":"n10"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/migrados/reuniao_cancelada.json`:

```json
{
  "nome": "Reunião cancelada",
  "descricao": "Reunião cancelada (painel do lead ou Cal.com), no lugar do código (B4.1): atividade, a tarefa da reunião apagada (o que também encerra os lembretes dela), sino para a conta e push. Enquanto o selo disser \"em sombra\", só ensaia: quem faz ainda é o código.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"reuniao_cancelada","cancelar_se_sair_da_etapa":false},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"registrar_atividade","config":{"rotulo":"Atividade: reunião cancelada","tipo":"meeting_cancelled","texto":"{resumo}"},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"apagar_reuniao","config":{"rotulo":"Apagar a tarefa da reunião"},"posicao":{"x":0,"y":280}},
      {"id":"n4","tipo":"avisar_sino","config":{"rotulo":"Sino para toda a conta","para":"conta","texto":"Reunião com {nome_completo} cancelada ({quando})"},"posicao":{"x":0,"y":420}},
      {"id":"n5","tipo":"avisar_push","config":{"rotulo":"Push: reunião cancelada","titulo":"Reuniao cancelada: {nome_completo}","texto":"{quando} — {titulo}"},"posicao":{"x":0,"y":560}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"s","para":"n3"},
      {"de":"n3","saida":"s","para":"n4"},
      {"de":"n4","saida":"s","para":"n5"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/migrados/lembretes_reuniao.json`:

```json
{
  "nome": "Lembretes de reunião",
  "descricao": "Os 5 lembretes de cada reunião (24h, 8h, 1h, 30 min e 5 min antes), para o Closer e o SDR, no lugar do código (B4.1). Cada reunião tem o seu ciclo: remarcar recomeça o dela pelo horário novo; cancelar (tarefa apagada) ou concluir para os lembretes dela. Enquanto o selo disser \"em sombra\", só ensaia: quem avisa ainda é o código.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"reuniao_na_agenda","cancelar_se_sair_da_etapa":false},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"esperar","config":{"rotulo":"Até 24h antes da reunião","antes_de":"reuniao","quantidade":24,"unidade":"horas"},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"se","config":{"rotulo":"A reunião segue marcada e o horário não passou?","juncao":"e","condicoes":[{"campo":"reuniao_de_pe","operador":"igual","valor":"sim"},{"campo":"horario_passou","operador":"igual","valor":"nao"}]},"posicao":{"x":0,"y":280}},
      {"id":"n4","tipo":"avisar_sino","config":{"rotulo":"Lembrete 24h antes (sino do Closer e do SDR)","texto":"Reunião em 24h antes ({quando}) — hora de confirmar com o cliente","para":"closer_e_sdr"},"posicao":{"x":280,"y":420}},
      {"id":"n5","tipo":"avisar_push","config":{"rotulo":"Push 24h antes","titulo":"Reunião {nome_completo} em 24h antes","texto":"{quando} — hora de mandar a mensagem de confirmação pro cliente"},"posicao":{"x":280,"y":560}},
      {"id":"n6","tipo":"esperar","config":{"rotulo":"Até 8h antes da reunião","antes_de":"reuniao","quantidade":8,"unidade":"horas"},"posicao":{"x":0,"y":700}},
      {"id":"n7","tipo":"se","config":{"rotulo":"A reunião segue marcada e o horário não passou?","juncao":"e","condicoes":[{"campo":"reuniao_de_pe","operador":"igual","valor":"sim"},{"campo":"horario_passou","operador":"igual","valor":"nao"}]},"posicao":{"x":0,"y":840}},
      {"id":"n8","tipo":"avisar_sino","config":{"rotulo":"Lembrete 8h antes (sino do Closer e do SDR)","texto":"Reunião em 8h antes ({quando}) — hora de confirmar com o cliente","para":"closer_e_sdr"},"posicao":{"x":280,"y":980}},
      {"id":"n9","tipo":"avisar_push","config":{"rotulo":"Push 8h antes","titulo":"Reunião {nome_completo} em 8h antes","texto":"{quando} — hora de mandar a mensagem de confirmação pro cliente"},"posicao":{"x":280,"y":1120}},
      {"id":"n10","tipo":"esperar","config":{"rotulo":"Até 1h antes da reunião","antes_de":"reuniao","quantidade":1,"unidade":"horas"},"posicao":{"x":0,"y":1260}},
      {"id":"n11","tipo":"se","config":{"rotulo":"A reunião segue marcada e o horário não passou?","juncao":"e","condicoes":[{"campo":"reuniao_de_pe","operador":"igual","valor":"sim"},{"campo":"horario_passou","operador":"igual","valor":"nao"}]},"posicao":{"x":0,"y":1400}},
      {"id":"n12","tipo":"avisar_sino","config":{"rotulo":"Lembrete 1h antes (sino do Closer e do SDR)","texto":"Reunião em 1h antes ({quando}) — hora de confirmar com o cliente","para":"closer_e_sdr"},"posicao":{"x":280,"y":1540}},
      {"id":"n13","tipo":"avisar_push","config":{"rotulo":"Push 1h antes","titulo":"Reunião {nome_completo} em 1h antes","texto":"{quando} — hora de mandar a mensagem de confirmação pro cliente"},"posicao":{"x":280,"y":1680}},
      {"id":"n14","tipo":"esperar","config":{"rotulo":"Até 30min antes da reunião","antes_de":"reuniao","quantidade":30,"unidade":"minutos"},"posicao":{"x":0,"y":1820}},
      {"id":"n15","tipo":"se","config":{"rotulo":"A reunião segue marcada e o horário não passou?","juncao":"e","condicoes":[{"campo":"reuniao_de_pe","operador":"igual","valor":"sim"},{"campo":"horario_passou","operador":"igual","valor":"nao"}]},"posicao":{"x":0,"y":1960}},
      {"id":"n16","tipo":"avisar_sino","config":{"rotulo":"Lembrete 30min antes (sino do Closer e do SDR)","texto":"Reunião em 30min antes ({quando}) — hora de confirmar com o cliente","para":"closer_e_sdr"},"posicao":{"x":280,"y":2100}},
      {"id":"n17","tipo":"avisar_push","config":{"rotulo":"Push 30min antes","titulo":"Reunião {nome_completo} em 30min antes","texto":"{quando} — hora de mandar a mensagem de confirmação pro cliente"},"posicao":{"x":280,"y":2240}},
      {"id":"n18","tipo":"esperar","config":{"rotulo":"Até 5min antes da reunião","antes_de":"reuniao","quantidade":5,"unidade":"minutos"},"posicao":{"x":0,"y":2380}},
      {"id":"n19","tipo":"se","config":{"rotulo":"A reunião segue marcada e o horário não passou?","juncao":"e","condicoes":[{"campo":"reuniao_de_pe","operador":"igual","valor":"sim"},{"campo":"horario_passou","operador":"igual","valor":"nao"}]},"posicao":{"x":0,"y":2520}},
      {"id":"n20","tipo":"avisar_sino","config":{"rotulo":"Lembrete 5min antes (sino do Closer e do SDR)","texto":"Reunião em 5min antes ({quando}) — hora de confirmar com o cliente","para":"closer_e_sdr"},"posicao":{"x":280,"y":2660}},
      {"id":"n21","tipo":"avisar_push","config":{"rotulo":"Push 5min antes","titulo":"Reunião {nome_completo} em 5min antes","texto":"{quando} — hora de mandar a mensagem de confirmação pro cliente"},"posicao":{"x":280,"y":2800}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"s","para":"n3"},
      {"de":"n3","saida":"sim","para":"n4"},
      {"de":"n4","saida":"s","para":"n5"},
      {"de":"n5","saida":"s","para":"n6"},
      {"de":"n3","saida":"nao","para":"n6"},
      {"de":"n6","saida":"s","para":"n7"},
      {"de":"n7","saida":"sim","para":"n8"},
      {"de":"n8","saida":"s","para":"n9"},
      {"de":"n9","saida":"s","para":"n10"},
      {"de":"n7","saida":"nao","para":"n10"},
      {"de":"n10","saida":"s","para":"n11"},
      {"de":"n11","saida":"sim","para":"n12"},
      {"de":"n12","saida":"s","para":"n13"},
      {"de":"n13","saida":"s","para":"n14"},
      {"de":"n11","saida":"nao","para":"n14"},
      {"de":"n14","saida":"s","para":"n15"},
      {"de":"n15","saida":"sim","para":"n16"},
      {"de":"n16","saida":"s","para":"n17"},
      {"de":"n17","saida":"s","para":"n18"},
      {"de":"n15","saida":"nao","para":"n18"},
      {"de":"n18","saida":"s","para":"n19"},
      {"de":"n19","saida":"sim","para":"n20"},
      {"de":"n20","saida":"s","para":"n21"}
    ]
  }
}
```

Os textos que falam com o cliente e os internos copiam o código: rascunho = heredoc do `confirmation_draft` (cabeçalho pelo `titulo`, nome pelo `{primeiro_nome}` que o próprio `ReuniaoAgendamento` calcula); atividade = `resumo` do código; push = "Reuniao <verbo>: <nome>" / "<quando> — <título>" (o `{evento}` é o verbo: marcada/remarcada); lembrete = `label` do `MeetingReminderJob::OFFSETS` e o texto do `ramon_meeting_reminder`. Diferenças que sobram (prefixo "Automação:" do sino de fluxo, horário por extenso no lembrete, nome do contato no push) são as da E2.

(b) `app/services/ramon/fluxos/reunioes.rb` — depois de `GATILHOS`:

```ruby
  PASTA = Rails.root.join('db/seeds/ramon/fluxos/migrados')
```

e antes do `end` final:

```ruby
  def fluxo(account, chave) = account.fluxos.where(origem: 'usuario', sistema_chave: chave).order(:id).first

  # Cria os que faltam, em sombra, ligados e publicados. Já existe → devolve sem tocar (o Eduardo pode ter editado).
  def semear(account) = GATILHOS.keys.map { |chave| fluxo(account, chave) || criar(account, chave) }

  def criar(account, chave)
    dados = JSON.parse(PASTA.join("#{chave}.json").read)
    Fluxo.transaction do
      novo = account.fluxos.create!(nome: dados['nome'], descricao: dados['descricao'], origem: 'usuario', sistema_chave: chave,
                                    modo: 'sombra', ativo: true, rascunho: com_etapa(account, dados['desenho']))
      novo.publicar!(nil)
      novo.reload
    end
  end

  # mover_etapa vem sem etapa no JSON (a etapa é do funil de cada conta): a "Reunião agendada" desta conta.
  def com_etapa(account, desenho)
    return desenho if desenho['nos'].none? { |n| n['tipo'] == 'mover_etapa' }

    etapa_id = account.lead_stages.find_by!(label: Ramon::ReuniaoAgendamento::STAGE_LABEL).id
    desenho.merge('nos' => desenho['nos'].map { |n| n['tipo'] == 'mover_etapa' ? n.deep_merge('config' => { 'etapa_id' => etapa_id }) : n })
  end
```

(c) Criar `lib/tasks/ramon_fluxos.rake`:

```ruby
# frozen_string_literal: true

# B4.1 — agendamento de reuniões pelos fluxos, em sombra (spec §8 e §15).
# Operação: docs/superpowers/plans/2026-10-06-automacoes-fluxo-b4-lembretes.md (seção "Operação depois do deploy").
namespace :ramon do
  namespace :fluxos do
    namespace :reunioes do
      conta = ->(args) { Account.find(args[:account_id].presence || raise(ArgumentError, 'informe o account_id')) }

      desc 'Cria (uma vez) os 3 fluxos de reuniao em SOMBRA. Uso: rake ramon:fluxos:reunioes:sombra[account_id]'
      task :sombra, [:account_id] => :environment do |_task, args|
        account = conta.call(args)
        Ramon::Fluxos::Reunioes.semear(account)
        puts Ramon::Fluxos::Reunioes.descrever(account)
      end

      desc 'normal = os fluxos assumem o agendamento (exige RAMON_FLUXO_REUNIOES=on); sombra = devolve ao codigo. ' \
           'Uso: rake ramon:fluxos:reunioes:modo[account_id,normal]'
      task :modo, [:account_id, :modo] => :environment do |_task, args|
        account = conta.call(args)
        Ramon::Fluxos::Reunioes.mudar_modo!(account, args[:modo])
        puts Ramon::Fluxos::Reunioes.descrever(account)
      end
    end
  end
end
```

- [ ] **Step 4: Run to verify they pass**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts`
Expected: PASS — **15 arquivos / 170 testes** (163 + 7).
Run (CI): `bundle exec rspec spec/services/ramon/fluxos/ spec/services/ramon/reuniao_agendamento_spec.rb spec/jobs/ramon/meeting_reminder_job_spec.rb spec/requests/public/api/v1/calcom_webhooks_spec.rb` e `bundle exec rubocop app/services/ramon/fluxos/reunioes.rb lib/tasks/ramon_fluxos.rake`
Expected: PASS, sem ofensas (`Reunioes` < 100 linhas de código).

- [ ] **Step 5: Commit**

```bash
git add db/seeds/ramon/fluxos/migrados app/services/ramon/fluxos/reunioes.rb lib/tasks/ramon_fluxos.rake spec/services/ramon/fluxos/reunioes_spec.rb app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/migrados.spec.js
git commit -m "feat(fluxos): fluxos Reunião marcada, Reunião cancelada e Lembretes de reunião em sombra" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 8: Comparação código × sombra da cadeia inteira (só leitura) + rake

**Files:**
- Create: `app/services/ramon/fluxos/comparar_lembretes.rb`, `app/services/ramon/fluxos/comparar_agendamentos.rb`
- Modify: `lib/tasks/ramon_fluxos.rake` (+ task `comparar`)
- Test: `spec/services/ramon/fluxos/comparar_lembretes_spec.rb`, `spec/services/ramon/fluxos/comparar_agendamentos_spec.rb` (novos)

**Interfaces:**
- Consumes: `Reunioes.fluxo`, `.fluxos`, `.semear` (Task 7); formatos de ensaio das Tasks 4–5.
- Produces: `CompararLembretes.inicio(account, dias, ate) → Time` (o mais tarde entre `ate - dias`, o nascimento dos fluxos e o corte do sino); `CompararLembretes::PESSOAS` (regex do sino do ensaio). As duas classes: `.new(account, dias: 1, ate: Time.current)`, `#linhas` (em ordem de horário), `#divergencias → Integer`, `#relatorio → String`, `#de`, `#ate`. `CompararLembretes#linhas → [{situacao: 'igual'|'so_codigo'|'so_fluxo'|'pessoas', em:, lead_id:, lead:, codigo:, fluxo:}]`; `CompararAgendamentos#linhas → [{evento: 'marcada'|'remarcada'|'cancelada', situacao: 'igual'|'diferente'|'so_codigo'|'so_fluxo', em:, lead_id:, lead:, so_no_codigo: [String], so_no_fluxo: [String]}]`. Rake `ramon:fluxos:reunioes:comparar[account_id,dias]`.

- [ ] **Step 1: Write the failing tests**

(a) `spec/services/ramon/fluxos/comparar_lembretes_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::CompararLembretes do
  let(:account) { create(:account) }
  let(:closer) { create(:user, account: account, name: 'Carla Closer') }
  let(:sdr) { create(:user, account: account, name: 'Sérgio SDR') }
  let(:lead) { create(:lead, account: account, closer: closer, name: 'João Pereira') }
  let(:agora) { Time.zone.parse('2026-10-07T14:00:00Z') }

  before do
    travel_to(agora - 1.day) { Ramon::Fluxos::Reunioes.semear(account) }
    travel_to(agora - 2.hours) do
      lead.lead_activities.create!(account: account, kind: 'meeting_scheduled', to_value: 'Primeiro Atendimento em 07/10/2026 19:00')
    end
  end

  # O que o MeetingReminderJob grava: 1 sino por pessoa.
  def codigo_avisou(em, pessoas, rotulo: '8h antes', alvo: lead)
    travel_to(em) do
      pessoas.each do |pessoa|
        pessoa.notifications.create!(notification_type: 'ramon_meeting_reminder', account: account, primary_actor: alvo,
                                     meta: { 'quando' => '07/10 19:00', 'label' => rotulo })
      end
    end
  end

  # O que a sombra grava: a linha "faria: sino para …" do ciclo (execuções concluídas: fora do índice único).
  def fluxo_ensaiou(em, pessoas, contexto: {})
    resumo = "faria: sino para #{pessoas.map(&:name).sort.join(', ')}: \"Reunião em 8h antes\""
    linha = { 'no' => 'n8', 'tipo' => 'avisar_sino', 'em' => em.iso8601, 'saida' => 's', 'resumo' => resumo, 'erro' => false }
    travel_to(em) do
      Ramon::Fluxos::Reunioes.fluxo(account, 'lembretes_reuniao').execucoes.create!(
        account: account, alvo: lead, ensaio: true, status: 'concluida', trilha: [linha],
        contexto: contexto.merge('gatilho' => { 'lead_id' => lead.id })
      )
    end
  end

  def comparar = described_class.new(account, dias: 2, ate: agora + 6.hours)

  it 'mesmo lead e mesmas pessoas, até 3 min de diferença: igual' do
    codigo_avisou(agora, [closer])
    fluxo_ensaiou(agora + 50.seconds, [closer])
    c = comparar
    expect([c.linhas.pluck(:situacao), c.divergencias]).to eq([['igual'], 0])
    expect(c.relatorio).to include('Resultado: BATEU', 'João Pereira', '8h antes', 'código: Carla Closer · fluxo: Carla Closer')
  end

  it 'pessoas diferentes, só no código e só no fluxo aparecem e não batem' do
    codigo_avisou(agora, [closer, sdr])
    fluxo_ensaiou(agora + 1.minute, [closer])
    codigo_avisou(agora + 2.hours, [closer], rotulo: '1h antes')
    fluxo_ensaiou(agora + 5.hours, [closer])
    c = comparar
    expect(c.linhas.pluck(:situacao)).to eq(%w[pessoas so_codigo so_fluxo])
    expect(c.relatorio).to include('Resultado: NÃO BATEU', 'código: Carla Closer, Sérgio SDR · fluxo: Carla Closer')
  end

  it 'deixa de fora o "Testar com um lead…" e a reunião marcada antes da sombra existir' do
    antigo = travel_to(agora - 3.days) { create(:lead, account: account, name: 'Antigo') }
    codigo_avisou(agora, [closer], alvo: antigo)
    fluxo_ensaiou(agora, [closer], contexto: { 'pular_esperas' => true })
    expect(comparar.linhas).to eq([])
    expect(comparar.relatorio).to include('nada para comparar')
  end

  it 'sino que já apagou avisos (teto de 300 por pessoa): compara só depois do aviso mais antigo que sobrou' do
    stub_const('Notification::RemoveOldNotificationJob::NOTIFICATION_LIMIT', 2)
    fluxo_ensaiou(agora - 5.hours, [closer]) # o aviso do código desta hora o Chatwoot já apagou
    codigo_avisou(agora - 3.hours, [closer], rotulo: '24h antes')
    fluxo_ensaiou(agora - 3.hours + 30.seconds, [closer])
    codigo_avisou(agora, [closer])
    fluxo_ensaiou(agora + 30.seconds, [closer])
    expect(comparar.linhas.pluck(:situacao)).to eq(%w[igual igual])
  end
end
```

(b) `spec/services/ramon/fluxos/comparar_agendamentos_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::CompararAgendamentos do
  let(:account) { create(:account) }
  let(:closer) { create(:user, account: account, name: 'Carla Closer') }
  let(:lead) do
    create(:lead, account: account, lead_stage: account.lead_stages.order(:position).first, closer: closer, name: 'João Pereira')
  end
  let(:agora) { Time.zone.parse('2026-10-07T12:00:00Z') }
  let(:inicio) { agora + 10.hours }

  before do
    travel_to(agora - 1.day) { Ramon::Fluxos::Reunioes.semear(account) }
    travel_to(agora - 1.hour) { lead }
  end

  def comparar = described_class.new(account, dias: 2, ate: agora + 1.hour)

  def marcar = travel_to(agora) { Ramon::ReuniaoAgendamento.call(lead: lead, starts_at: inicio, title: 'Primeiro Atendimento') }

  it 'em sombra de verdade (código + ensaio), marcar, remarcar e cancelar batem' do
    marcar
    tarefa = lead.lead_tasks.find_by!(kind: 'meeting')
    travel_to(agora + 10.minutes) { Ramon::ReuniaoAgendamento.remarcar(task: tarefa, starts_at: inicio + 1.day) }
    travel_to(agora + 20.minutes) { Ramon::ReuniaoAgendamento.cancelar(task: tarefa.reload) }
    c = comparar
    expect(c.linhas.map { |l| [l[:evento], l[:situacao]] }).to eq([%w[marcada igual], %w[remarcada igual], %w[cancelada igual]])
    expect(c.relatorio).to include('Resultado: BATEU', '1 marcada(s) · 1 remarcada(s) · 1 cancelada(s)')
  end

  it 'o que só um dos lados fez aparece na linha (e não bate)' do
    marcar
    ensaio = FluxoExecucao.where(fluxo: Ramon::Fluxos::Reunioes.fluxo(account, 'reuniao_marcada')).last
    ensaio.update!(trilha: ensaio.trilha.reject { |t| t['tipo'] == 'rascunho_texto' })
    linha = comparar.linhas.first
    expect(linha[:situacao]).to eq('diferente')
    expect(linha[:so_no_codigo]).to contain_exactly(a_string_starting_with('rascunho "'))
    expect(comparar.relatorio).to include('Resultado: NÃO BATEU')
  end

  it 'evento que o fluxo não viu aparece como só no código' do
    travel_to(agora) { lead.lead_activities.create!(account: account, kind: 'meeting_cancelled', to_value: 'X em 07/10/2026 19:00') }
    expect(comparar.linhas.map { |l| [l[:evento], l[:situacao]] }).to eq([%w[cancelada so_codigo]])
  end
end
```

Rastreio do 1º de agendamentos (cada evento num minuto próprio, a janela é 1 min a partir do ensaio): **marcada** — ensaio (antes do código): `atividade meeting_scheduled: Primeiro Atendimento em 07/10/2026 19:00`, `tarefa "Primeiro Atendimento" para 07/10 19:00`, `mover para <Reunião agendada>`, `rascunho "<texto 120>"`, `sino para Carla Closer` (o `closer: já tem …` e o push ficam fora). Código na janela: atividade `meeting_scheduled` ✓, tarefa ✓, `stage_changed` → `mover para <Reunião agendada>` ✓, nota "RASCUNHO … — confirmação de reunião:" → mesma 2ª parte ✓, avisos `ramon_meeting_scheduled` para a conta (só a Carla) ✓; `task_created`/`created` ficam fora. **remarcada** — `atividade meeting_rescheduled: … 07/10 → … 08/10` + rascunho + sino nos dois lados. **cancelada** — atividade + `apagar tarefas #id` (o código apagou: o id não existe mais) + sino. O lead nasce antes (`agora - 1h`), então a criação dele não cai em janela nenhuma.

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/comparar_lembretes_spec.rb spec/services/ramon/fluxos/comparar_agendamentos_spec.rb`
Expected: FAIL — `uninitialized constant Ramon::Fluxos::CompararLembretes` / `CompararAgendamentos`.

- [ ] **Step 3: Implementation**

(a) Criar `app/services/ramon/fluxos/comparar_lembretes.rb`:

```ruby
# B4.1 (spec §8, passo 2): lembrete a lembrete, o que o código mandou (sino ramon_meeting_reminder) ao lado do que o
# fluxo "Lembretes de reunião" em sombra diz que mandaria (linhas "faria: sino para …" da trilha). Só leitura.
# Casa pelo lead e pelo horário (até 3 min: o relógio dos fluxos anda de minuto em minuto, o Sidekiq no segundo).
class Ramon::Fluxos::CompararLembretes
  JANELA = 3.minutes
  REUNIAO = %w[meeting_scheduled meeting_rescheduled].freeze
  # ponytail: lê o resumo do ensaio de Passos::Aviso#avisar_sino; mudou lá, muda aqui (os specs dos dois pegam)
  PESSOAS = /\Afaria: sino para (.*?): "/
  ROTULOS = { 'igual' => 'igual', 'so_codigo' => 'só no código', 'so_fluxo' => 'só no fluxo',
              'pessoas' => 'pessoas diferentes' }.freeze

  attr_reader :de, :ate

  # Começo honesto: o mais tarde entre (ate - dias), o nascimento dos fluxos e o corte do sino. O Chatwoot apaga todo dia
  # o que passa de 300 avisos por pessoa (Notification::RemoveOldNotificationJob): antes do aviso mais antigo de quem
  # bateu o teto, o código pode ter avisado e o registro sumido.
  def self.inicio(account, dias, ate)
    teto = Notification::RemoveOldNotificationJob::NOTIFICATION_LIMIT
    cheios = Notification.where(user_id: account.account_users.select(:user_id)).group(:user_id)
                         .having('COUNT(*) >= ?', teto).pluck(:user_id)
    corte = Notification.where(user_id: cheios).group(:user_id).minimum(:created_at).values.max
    [ate - dias.days, Ramon::Fluxos::Reunioes.fluxos(account).minimum(:created_at), corte].compact.max
  end

  def initialize(account, dias: 1, ate: Time.current)
    @account = account
    @fluxo = Ramon::Fluxos::Reunioes.fluxo(account, 'lembretes_reuniao') || raise(ArgumentError, 'Os fluxos de reunião ainda não existem')
    @ate = ate
    @de = self.class.inicio(account, dias, ate)
  end

  def linhas
    @linhas ||= begin
      sobra = do_fluxo
      casadas = do_codigo.map { |codigo| casar(codigo, sobra) }
      (casadas + sobra.map { |fluxo| linha('so_fluxo', fluxo, nil, fluxo) }).sort_by { |item| item[:em] }
    end
  end

  def divergencias = linhas.count { |item| item[:situacao] != 'igual' }

  def relatorio = [cabecalho, *linhas.map { |item| texto(item) }, total, resultado].join("\n")

  private

  def casar(codigo, sobra)
    par = sobra.find { |f| f[:lead_id] == codigo[:lead_id] && (f[:em] - codigo[:em]).abs <= JANELA }
    return linha('so_codigo', codigo, codigo, nil) unless par

    sobra.delete(par)
    linha(par[:pessoas] == codigo[:pessoas] ? 'igual' : 'pessoas', codigo, codigo, par)
  end

  def linha(situacao, base, codigo, fluxo)
    { situacao: situacao, em: base[:em], lead_id: base[:lead_id], lead: base[:lead], codigo: codigo, fluxo: fluxo }
  end

  # O sino do código: 1 aviso por pessoa → 1 lembrete por lead + rótulo + horário da reunião.
  def do_codigo
    avisos = Notification.where(account: @account, notification_type: 'ramon_meeting_reminder', primary_actor_type: 'Lead',
                                primary_actor_id: leads_em_sombra, created_at: de..ate).includes(:user, :primary_actor)
    avisos.group_by { |n| [n.primary_actor_id, n.meta['label'], n.meta['quando']] }.map do |(lead_id, rotulo, _quando), grupo|
      { lead_id: lead_id, lead: grupo.first.primary_actor&.name, em: grupo.map(&:created_at).min, rotulo: rotulo,
        pessoas: grupo.map { |n| n.user.name }.uniq.sort }
    end
  end

  # Só reuniões marcadas/remarcadas depois que a sombra nasceu: as de antes não têm ciclo para comparar.
  def leads_em_sombra
    @account.lead_activities.where(kind: REUNIAO, created_at: @fluxo.created_at..).distinct.pluck(:lead_id)
  end

  # O ensaio: as linhas "faria: sino para …" dos ciclos em sombra ("Testar com um lead…" fica de fora). O alvo é a
  # tarefa (pode ter sido apagada) — o lead vem do gatilho.
  def do_fluxo
    @fluxo.execucoes.where(ensaio: true, updated_at: de..).flat_map do |execucao|
      execucao.contexto['pular_esperas'] ? [] : execucao.trilha.filter_map { |t| do_trilha(execucao, t) }
    end
  end

  def do_trilha(execucao, passo)
    pessoas = passo['tipo'] == 'avisar_sino' && passo['resumo'].to_s[PESSOAS, 1]
    em = Time.zone.parse(passo['em'].to_s)
    return unless pessoas && em && (de..ate).cover?(em)

    lead_id = execucao.contexto.dig('gatilho', 'lead_id') || execucao.lead&.id
    { lead_id: lead_id, lead: nome(lead_id), em: em, rotulo: nil, pessoas: pessoas.split(', ').sort }
  end

  # ponytail: 1 consulta por lead (cacheada); agrupar se o relatório passar de centenas de lembretes.
  def nome(lead_id) = (@nomes ||= {})[lead_id] ||= Lead.find_by(id: lead_id)&.name

  def cabecalho
    "Lembretes de reunião — código × fluxo em sombra · conta #{@account.id} · #{hora(de)} até #{hora(ate)} (horário de Brasília)"
  end

  def texto(item)
    quem = [("código: #{item[:codigo][:pessoas].join(', ')}" if item[:codigo]),
            ("fluxo: #{item[:fluxo][:pessoas].join(', ')}" if item[:fluxo])].compact.join(' · ')
    "#{ROTULOS[item[:situacao]].ljust(18)} #{hora(item[:em])}  #{item[:lead]} (lead #{item[:lead_id]})  " \
      "#{item.dig(:codigo, :rotulo) || 'lembrete'}  #{quem}"
  end

  def total
    conta = ROTULOS.keys.index_with { |s| linhas.count { |item| item[:situacao] == s } }
    esperando = @fluxo.execucoes.where(ensaio: true, status: 'esperando').count
    "Total: #{linhas.size} lembrete(s) comparado(s) — #{conta['igual']} iguais · #{conta['so_codigo']} só no código · " \
      "#{conta['so_fluxo']} só no fluxo · #{conta['pessoas']} com pessoas diferentes · #{esperando} reunião(ões) com lembrete por vir"
  end

  def resultado
    return 'Resultado: nada para comparar ainda (nenhum lembrete no período)' if linhas.empty?

    divergencias.zero? ? 'Resultado: BATEU' : 'Resultado: NÃO BATEU — veja as linhas que não são "igual"'
  end

  def hora(momento) = momento.in_time_zone(Fluxo::ZONA).strftime('%d/%m %H:%M')
end
```

(b) Criar `app/services/ramon/fluxos/comparar_agendamentos.rb`:

```ruby
# B4.1 (spec §8, passo 2): evento a evento — reunião marcada, remarcada, cancelada —, os rastros que o código deixou
# ao lado do que os fluxos em sombra dizem que fariam (linhas "faria: …" da trilha). Só leitura.
# O ensaio roda na mesma requisição, logo ANTES do código: casa pelo lead e pelo minuto seguinte ao ensaio.
class Ramon::Fluxos::CompararAgendamentos
  JANELA = 1.minute
  KINDS = { 'marcada' => 'meeting_scheduled', 'remarcada' => 'meeting_rescheduled', 'cancelada' => 'meeting_cancelled' }.freeze
  SINOS = %w[ramon_meeting_scheduled ramon_meeting_cancelled].freeze
  RASCUNHO = 'RASCUNHO (revisar antes de enviar) — confirmação de reunião:'.freeze

  attr_reader :de, :ate

  def initialize(account, dias: 1, ate: Time.current)
    @account = account
    @ate = ate
    @de = Ramon::Fluxos::CompararLembretes.inicio(account, dias, ate)
  end

  def linhas
    @linhas ||= begin
      sobra = eventos_do_codigo
      casadas = ensaios.map { |execucao| casar(execucao, sobra) }
      (casadas + sobra.map { |atividade| so_codigo(atividade) }).sort_by { |item| item[:em] }
    end
  end

  def divergencias = linhas.count { |item| item[:situacao] != 'igual' }

  def relatorio = [cabecalho, *linhas.map { |item| texto(item) }, total, resultado].join("\n")

  private

  def ensaios
    fluxos = Ramon::Fluxos::Reunioes.fluxos(@account).where(sistema_chave: %w[reuniao_marcada reuniao_cancelada])
    FluxoExecucao.where(fluxo: fluxos, ensaio: true, alvo_type: 'Lead', created_at: de..ate).includes(:alvo)
                 .reject { |execucao| execucao.contexto['pular_esperas'] }
  end

  def eventos_do_codigo = @account.lead_activities.where(kind: KINDS.values, created_at: de..ate).includes(:lead).to_a

  def casar(execucao, sobra)
    evento = execucao.contexto.dig('gatilho', 'evento')
    janela = execucao.created_at..(execucao.created_at + JANELA)
    atividade = sobra.find { |a| a.lead_id == execucao.alvo_id && a.kind == KINDS[evento] && janela.cover?(a.created_at) }
    sobra.delete(atividade)
    fluxo = do_fluxo(execucao)
    codigo = atividade ? do_codigo(execucao, janela) : []
    { evento: evento, em: execucao.created_at, lead_id: execucao.alvo_id, lead: execucao.alvo&.name,
      situacao: situacao(atividade, codigo, fluxo), so_no_codigo: menos(codigo, fluxo), so_no_fluxo: menos(fluxo, codigo) }
  end

  def situacao(atividade, codigo, fluxo)
    return 'so_fluxo' unless atividade

    codigo.sort == fluxo.sort ? 'igual' : 'diferente'
  end

  def so_codigo(atividade)
    { evento: KINDS.key(atividade.kind), em: atividade.created_at, lead_id: atividade.lead_id, lead: atividade.lead&.name,
      situacao: 'so_codigo', so_no_codigo: [], so_no_fluxo: [] }
  end

  # O ensaio: as linhas "faria: …", menos o push (o código não deixa rastro dele); o sino vira "sino para <pessoas>".
  def do_fluxo(execucao)
    execucao.trilha.filter_map do |t|
      resumo = t['resumo'].to_s
      next unless resumo.start_with?('faria: ') && t['tipo'] != 'avisar_push'

      t['tipo'] == 'avisar_sino' ? "sino para #{resumo[Ramon::Fluxos::CompararLembretes::PESSOAS, 1]}" : resumo.delete_prefix('faria: ')
    end
  end

  # Os rastros do código na janela do evento, na mesma frase do ensaio.
  def do_codigo(execucao, janela)
    lead = execucao.alvo
    atividades(lead, janela) + tarefas(lead, janela) + rascunhos(lead, janela) + sinos(lead, janela) + apagadas(execucao)
  end

  def atividades(lead, janela)
    lead.lead_activities.where(created_at: janela, kind: KINDS.values + %w[stage_changed closer_changed]).map do |a|
      case a.kind
      when 'stage_changed' then "mover para #{a.to_value}"
      when 'closer_changed' then "closer → #{a.to_value}"
      else "atividade #{a.kind}: #{[a.from_value, a.to_value].compact.join(' → ')}"
      end
    end
  end

  def tarefas(lead, janela)
    lead.lead_tasks.where(kind: 'meeting', created_at: janela).map { |t| "tarefa \"#{t.title}\" para #{hora(t.due_at)}" }
  end

  def rascunhos(lead, janela)
    lead.lead_notes.where(created_at: janela).where('body LIKE ?', "#{RASCUNHO}%")
        .map { |n| "rascunho \"#{n.body.split("\n", 2).last.to_s.truncate(120)}\"" }
  end

  def sinos(lead, janela)
    avisos = Notification.where(account: @account, primary_actor: lead, notification_type: SINOS, created_at: janela).includes(:user)
    avisos.group_by(&:notification_type).map { |_tipo, grupo| "sino para #{grupo.map { |n| n.user.name }.uniq.sort.join(', ')}" }
  end

  # Cancelada: as tarefas do evento sumiram? (o código apaga; o ensaio diria "apagar tarefas …")
  def apagadas(execucao)
    return [] unless execucao.contexto.dig('gatilho', 'evento') == 'cancelada'

    ids = Array(execucao.contexto.dig('gatilho', 'tarefa_ids')).map(&:to_i).sort
    vivas = LeadTask.where(id: ids).pluck(:id)
    lista = ids.any? ? ids.map { |id| "##{id}" }.join(', ') : '(nenhuma)'
    ["apagar tarefas #{lista}#{" (ainda existem: #{vivas.join(', ')})" if vivas.any?}"]
  end

  # Diferença de listas com repetição (multiconjunto): o que está em `a` e falta em `b`.
  def menos(lista, outra) = outra.each_with_object(lista.dup) { |x, resto| (i = resto.index(x)) && resto.delete_at(i) }

  def cabecalho
    "Agendamentos — código × fluxos em sombra · conta #{@account.id} · #{hora(de)} até #{hora(ate)} (horário de Brasília)"
  end

  def texto(item)
    dif = [("só no código: #{item[:so_no_codigo].join(' | ')}" if item[:so_no_codigo].any?),
           ("só no fluxo: #{item[:so_no_fluxo].join(' | ')}" if item[:so_no_fluxo].any?)].compact.join(' · ')
    "#{item[:situacao].ljust(10)} #{hora(item[:em])}  #{item[:lead]} (lead #{item[:lead_id]})  #{item[:evento]}  #{dif}".rstrip
  end

  def total
    por_evento = KINDS.keys.map { |e| "#{linhas.count { |item| item[:evento] == e }} #{e}(s)" }.join(' · ')
    "Total: #{por_evento} — #{linhas.size - divergencias} iguais · #{divergencias} com diferença"
  end

  def resultado
    return 'Resultado: nada para comparar ainda (nenhum agendamento no período)' if linhas.empty?

    divergencias.zero? ? 'Resultado: BATEU' : 'Resultado: NÃO BATEU — veja as linhas que não são "igual"'
  end

  def hora(momento) = momento.in_time_zone(Fluxo::ZONA).strftime('%d/%m %H:%M')
end
```

(c) `lib/tasks/ramon_fluxos.rake` — dentro de `namespace :reunioes`, depois da task `:modo`:

```ruby

      desc 'SO LEITURA: agendamentos e lembretes do codigo x fluxos em sombra. ' \
           'Uso: rake ramon:fluxos:reunioes:comparar[account_id,dias] (padrao 1 dia; rodar todo dia)'
      task :comparar, [:account_id, :dias] => :environment do |_task, args|
        account = conta.call(args)
        dias = (args[:dias].presence || 1).to_i
        comparacoes = [Ramon::Fluxos::CompararAgendamentos, Ramon::Fluxos::CompararLembretes].map { |k| k.new(account, dias: dias) }
        puts comparacoes.map(&:relatorio).join("\n\n")
        geral = comparacoes.sum(&:divergencias).zero? ? 'BATEU' : 'NÃO BATEU'
        puts "\nResultado geral: #{geral} (#{comparacoes.sum { |c| c.linhas.size }} comparações)"
      end
```

- [ ] **Step 4: Run to verify they pass**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/comparar_lembretes_spec.rb spec/services/ramon/fluxos/comparar_agendamentos_spec.rb` e `bundle exec rubocop app/services/ramon/fluxos/comparar_lembretes.rb app/services/ramon/fluxos/comparar_agendamentos.rb lib/tasks/ramon_fluxos.rake`
Expected: PASS, sem ofensas (as duas classes < 175 linhas; o bloco externo do rake < 30).

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/comparar_lembretes.rb app/services/ramon/fluxos/comparar_agendamentos.rb lib/tasks/ramon_fluxos.rake spec/services/ramon/fluxos/comparar_lembretes_spec.rb spec/services/ramon/fluxos/comparar_agendamentos_spec.rb
git commit -m "feat(fluxos): comparação código × sombra do agendamento de reuniões" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 9: Front — o editor entende os fluxos de reunião

Sem isto, o Eduardo abriria os fluxos e o painel mostraria "Um tempo" no `esperar` (um clique apagaria o `antes_de`), campos em branco nas condições, "Quem recebe" vazio no sino e nada das opções novas (tarefa da reunião, só para a frente, só se não tem, atividade de reunião, rascunho nas notas, apagar reunião, gatilho "Reunião na agenda").

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js` (`GATILHOS`, `PASSOS`, `PALETA`, `VARIAVEIS`, `CAMPOS`, novo `TIPOS_ATIVIDADE`)
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/validar.js` (`RESERVADAS`)
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/PainelPasso.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/NoPasso.vue:99-102`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/Lista.vue:114-116`
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json`, `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`
- Test: `specs/PainelPasso.spec.js`, `specs/NoPasso.spec.js`, `specs/Lista.spec.js`, `specs/validar.spec.js` (em `…/captain/automacoes/specs/`)

**Interfaces:**
- Consumes: configs das Tasks 2–5 (`antes_de`, `para`, `so_para_frente`, `so_se_vazio`, `prazo: 'reuniao'`, `tipo`/`de` da atividade, `onde`/`titulo` do rascunho), passo `apagar_reuniao`, gatilho `reuniao_na_agenda`, campos `evento`/`reuniao_de_pe`/`horario_passou`, `fluxo.modo`.
- Produces: `TIPOS_ATIVIDADE` (= `Passos::Lead::TIPOS_ATIVIDADE`). `data-testid`: `espera-tempo|horario|reuniao`, `sino-para`, `so-para-frente`, `so-se-vazio`, `tarefa-da-reuniao`, `atividade-tipo`, `rascunho-onde`, `rascunho-titulo`. Desmarcar uma opção grava `undefined` (some do JSON).

- [ ] **Step 1: Write the failing tests**

(a) `specs/PainelPasso.spec.js`, antes do `});` final:

```js
  it('esperar: "Antes da reunião" conta para trás (quantidade e unidade continuam)', async () => {
    const wrapper = montar({
      id: 'n2',
      data: { tipo: 'esperar', config: { quantidade: 1, unidade: 'dias' } },
    });
    await wrapper.find('[data-testid="espera-reuniao"]').trigger('change');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { antes_de: 'reuniao', quantidade: 1, unidade: 'horas' },
    ]);
  });

  it('sino: "Quem recebe" troca a lista de pessoas por Closer e SDR ou pela conta', async () => {
    const wrapper = montar({
      id: 'n4',
      data: { tipo: 'avisar_sino', config: { texto: 'Oi' } },
    });
    await wrapper.find('[data-testid="sino-para"]').setValue('closer_e_sdr');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { texto: 'Oi', para: 'closer_e_sdr' },
    ]);
    const conta = montar({
      id: 'n4',
      data: { tipo: 'avisar_sino', config: { texto: 'Oi', para: 'conta' } },
    });
    expect(conta.text()).not.toContain('Ana');
  });

  it('rascunho: nas notas do lead e com título', async () => {
    const wrapper = montar({
      id: 'n8',
      data: { tipo: 'rascunho_texto', config: { texto: 'Oi' } },
    });
    await wrapper.find('[data-testid="rascunho-onde"]').setValue('notas_do_lead');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { texto: 'Oi', onde: 'notas_do_lead' },
    ]);
    await wrapper.find('[data-testid="rascunho-titulo"]').setValue('confirmação');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { texto: 'Oi', titulo: 'confirmação' },
    ]);
  });

  it('tarefa da reunião esconde prazo e responsável', async () => {
    const wrapper = montar({
      id: 'n3',
      data: { tipo: 'criar_tarefa', config: { titulo: 'T' } },
    });
    await wrapper.find('[data-testid="tarefa-da-reuniao"]').setValue(true);
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { titulo: 'T', prazo: 'reuniao' },
    ]);
    const daReuniao = montar({
      id: 'n3',
      data: { tipo: 'criar_tarefa', config: { titulo: 'T', prazo: 'reuniao' } },
    });
    expect(daReuniao.text()).not.toContain('Ana');
  });

  it('atividade: tipo de reunião; remarcada pede o "de"', async () => {
    const wrapper = montar({
      id: 'n7',
      data: { tipo: 'registrar_atividade', config: { texto: 'x' } },
    });
    await wrapper.find('[data-testid="atividade-tipo"]').setValue('meeting_rescheduled');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { texto: 'x', tipo: 'meeting_rescheduled' },
    ]);
    const remarcada = montar({
      id: 'n7',
      data: { tipo: 'registrar_atividade', config: { texto: 'x', tipo: 'meeting_rescheduled' } },
    });
    expect(remarcada.findAll('textarea')).toHaveLength(2);
  });

  it('etapa só para a frente e Closer só se não tem', async () => {
    const etapa = montar({ id: 'n5', data: { tipo: 'mover_etapa', config: {} } });
    await etapa.find('[data-testid="so-para-frente"]').setValue(true);
    expect(etapa.emitted('update:config').at(-1)).toEqual([{ so_para_frente: true }]);
    const closer = montar({
      id: 'n6',
      data: { tipo: 'trocar_responsavel', config: { papel: 'closer' } },
    });
    await closer.find('[data-testid="so-se-vazio"]').setValue(true);
    expect(closer.emitted('update:config').at(-1)).toEqual([
      { papel: 'closer', so_se_vazio: true },
    ]);
  });
```

(b) `specs/NoPasso.spec.js`, dentro de `describe('NoPasso — esperar', …)`, depois do teste existente:

```js
  it('antes da reunião diz que conta para trás', () => {
    const w = montar({
      tipo: 'esperar',
      config: { antes_de: 'reuniao', quantidade: 24, unidade: 'horas' },
    });
    expect(w.text()).toContain('24 hours before the meeting');
  });
```

(c) `specs/Lista.spec.js`, antes do `});` final do `describe`:

```js
  it('fluxo em sombra tem selo próprio', async () => {
    RamonFluxosAPI.get.mockResolvedValue({
      data: { payload: [{ ...FLUXO, modo: 'sombra' }], resumo: {} },
    });
    const wrapper = mount(Lista);
    await flushPromises();
    expect(wrapper.find('[data-testid="fluxo-linha"]').text()).toContain(
      'shadow'
    );
  });
```

(d) `specs/validar.spec.js`, antes do `});` final:

```js
  it('os nomes da reunião (B4.1) também são reservados no Preencher campo', () => {
    [
      'evento',
      'titulo',
      'titulo_tarefa',
      'resumo',
      'resumo_antes',
      'primeiro_nome',
      'reuniao_de_pe',
      'horario_passou',
    ].forEach(chave =>
      expect(
        codigos(linear(p('p1', 'preencher_campo', { chave, valor: 'x' })))
      ).toEqual([['p1', 'CAMPO_CHAVE']])
    );
  });
```

- [ ] **Step 2: Run to verify they fail**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts`
Expected: FAIL nos 9 novos (testids inexistentes, sem "before the meeting", sem selo "shadow", chaves aceitas). O `fluxo.spec` e o `i18n.spec` seguem verdes até o Step 3 (o catálogo ainda não tem `apagar_reuniao`).

- [ ] **Step 3: Implementation**

(a) `fluxo.js`:
- em `GATILHOS`, depois de `{ tipo: 'reuniao_cancelada', icone: 'i-lucide-calendar-x', alvo: 'lead' },` inserir `{ tipo: 'reuniao_na_agenda', icone: 'i-lucide-calendar-clock', alvo: 'lead' },`
- em `PASSOS`, depois do bloco `registrar_atividade: { … },` inserir:

```js
  apagar_reuniao: {
    grupo: 'LEAD',
    icone: 'i-lucide-calendar-x',
    tom: 'slate',
  },
```

- em `PALETA`, grupo `LEAD`, depois de `{ chave: 'registrar_atividade', tipo: 'registrar_atividade' },` inserir `{ chave: 'apagar_reuniao', tipo: 'apagar_reuniao' },`
- em `VARIAVEIS`, depois de `'documento',` inserir `'evento', 'titulo', 'titulo_tarefa', 'resumo', 'resumo_antes', 'primeiro_nome',` (um por linha, formato do arquivo)
- em `CAMPOS`, depois de `'regra',` inserir `'evento', 'reuniao_de_pe', 'horario_passou',` (um por linha)
- depois de `export const TIPOS_TAREFA = …` inserir:

```js
// = Ramon::Fluxos::Passos::Lead::TIPOS_ATIVIDADE (as de reunião aparecem como as do código)
export const TIPOS_ATIVIDADE = [
  'fluxo',
  'meeting_scheduled',
  'meeting_rescheduled',
  'meeting_cancelled',
];
```

(b) `validar.js` — em `RESERVADAS`, depois de `'resposta_ia',` inserir (um por linha) `'evento', 'titulo', 'titulo_tarefa', 'resumo', 'resumo_antes', 'primeiro_nome', 'reuniao_de_pe', 'horario_passou',`. (`DO_GATILHO` vem primeiro no Ruby; aqui a ordem não importa.)

(c) `PainelPasso.vue` — no import do `./fluxo`, trocar

```js
import { PAPEIS, PASSOS, TIPOS_TAREFA, UNIDADES, gatilhoInfo } from './fluxo';
```

por

```js
import {
  PAPEIS,
  PASSOS,
  TIPOS_ATIVIDADE,
  TIPOS_TAREFA,
  UNIDADES,
  gatilhoInfo,
} from './fluxo';
```

trocar a linha 47

```js
const esperaHorario = computed(() => config.value.ate === 'horario_comercial');
```

por

```js
// esperar: um tempo (do passo anterior), até o horário comercial, ou antes da reunião (B4.1: conta para trás)
const modoEspera = computed(() => {
  if (config.value.ate === 'horario_comercial') return 'horario';
  return config.value.antes_de === 'reuniao' ? 'reuniao' : 'tempo';
});
const OPCOES_ESPERA = [
  { modo: 'tempo', rotulo: 'ESPERAR_TEMPO' },
  { modo: 'horario', rotulo: 'ESPERAR_HORARIO' },
  { modo: 'reuniao', rotulo: 'ESPERAR_REUNIAO' },
];
const CONFIG_ESPERA = {
  tempo: { quantidade: 1, unidade: 'dias' },
  horario: { ate: 'horario_comercial' },
  reuniao: { antes_de: 'reuniao', quantidade: 1, unidade: 'horas' },
};
// sino (B4.1): pessoas marcadas (padrão), Closer e SDR do lead, ou a conta toda
const PARA_SINO = [
  { valor: '', rotulo: 'PARA_PESSOAS' },
  { valor: 'closer_e_sdr', rotulo: 'PARA_CLOSER_SDR' },
  { valor: 'conta', rotulo: 'PARA_CONTA' },
];
```

trocar as linhas 52-58 (`const modoEspera = horario => emit(…)`) por:

```js
const trocaEspera = modo =>
  emit('update:config', {
    rotulo: config.value.rotulo,
    ...CONFIG_ESPERA[modo],
  });
// opção liga/desliga: desligada some do JSON
const marca = (chave, ligada, valor = true) =>
  muda(chave, ligada ? valor : undefined);
```

no template:

1. trocar o bloco do `CampoTexto` compartilhado (linhas 142-151)

```vue
      <CampoTexto
        v-else-if="
          ['rascunho_texto', 'nota_privada', 'registrar_atividade'].includes(
            tipo
          )
        "
        :rotulo="t(`${K}.PAINEL.TEXTO`)"
        :model-value="config.texto || ''"
        @update:model-value="v => muda('texto', v)"
      />
```

por

```vue
      <CampoTexto
        v-else-if="tipo === 'nota_privada'"
        :rotulo="t(`${K}.PAINEL.TEXTO`)"
        :model-value="config.texto || ''"
        @update:model-value="v => muda('texto', v)"
      />

      <template v-else-if="tipo === 'rascunho_texto'">
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.ONDE_RASCUNHO`) }}
          <select
            data-testid="rascunho-onde"
            :class="SELECT"
            :value="config.onde || ''"
            @change="muda('onde', $event.target.value || undefined)"
          >
            <option value="">{{ t(`${K}.PAINEL.ONDE_CONVERSA`) }}</option>
            <option value="notas_do_lead">
              {{ t(`${K}.PAINEL.ONDE_NOTAS`) }}
            </option>
          </select>
        </label>
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.TITULO_RASCUNHO`) }}
          <input
            data-testid="rascunho-titulo"
            :class="CAMPO"
            :value="config.titulo || ''"
            @input="muda('titulo', $event.target.value)"
          />
        </label>
        <CampoTexto
          :rotulo="t(`${K}.PAINEL.TEXTO`)"
          :model-value="config.texto || ''"
          @update:model-value="v => muda('texto', v)"
        />
      </template>

      <template v-else-if="tipo === 'registrar_atividade'">
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.TIPO_ATIVIDADE`) }}
          <select
            data-testid="atividade-tipo"
            :class="SELECT"
            :value="config.tipo || 'fluxo'"
            @change="muda('tipo', $event.target.value)"
          >
            <option v-for="k in TIPOS_ATIVIDADE" :key="k" :value="k">
              {{ t(`${K}.TIPOS_ATIVIDADE.${k}`) }}
            </option>
          </select>
        </label>
        <CampoTexto
          v-if="config.tipo === 'meeting_rescheduled'"
          :rotulo="t(`${K}.PAINEL.DE`)"
          :linhas="2"
          :model-value="config.de || ''"
          @update:model-value="v => muda('de', v)"
        />
        <CampoTexto
          :rotulo="t(`${K}.PAINEL.TEXTO`)"
          :model-value="config.texto || ''"
          @update:model-value="v => muda('texto', v)"
        />
      </template>
```

2. trocar o `mover_etapa` (`<label v-else-if="tipo === 'mover_etapa'" …> … </label>`, linhas 153-167) por `<template v-else-if="tipo === 'mover_etapa'">` contendo o mesmo `<label :class="ROTULO">` (sem o `v-else-if`) seguido de:

```vue
        <label class="flex items-center gap-2 text-[13px] text-n-slate-12">
          <input
            data-testid="so-para-frente"
            type="checkbox"
            class="reset-base"
            :checked="!!config.so_para_frente"
            @change="marca('so_para_frente', $event.target.checked)"
          />
          {{ t(`${K}.PAINEL.SO_PARA_FRENTE`) }}
        </label>
      </template>
```

3. no `criar_tarefa` (linhas 169-213), logo depois do `CampoTexto` do título, inserir:

```vue
        <label class="flex items-center gap-2 text-[13px] text-n-slate-12">
          <input
            data-testid="tarefa-da-reuniao"
            type="checkbox"
            class="reset-base"
            :checked="config.prazo === 'reuniao'"
            @change="marca('prazo', $event.target.checked, 'reuniao')"
          />
          {{ t(`${K}.PAINEL.TAREFA_DA_REUNIAO`) }}
        </label>
```

e acrescentar `v-if="config.prazo !== 'reuniao'"` ao `<label :class="ROTULO">` do **prazo** (o 2º label do `grid grid-cols-2`) e ao `<label :class="ROTULO">` do **responsável** (o último do bloco).

4. trocar o bloco do `avisar_sino` inteiro (linhas 215-231) por:

```vue
      <template v-else-if="tipo === 'avisar_sino'">
        <CampoTexto
          :rotulo="t(`${K}.PAINEL.TEXTO`)"
          :linhas="2"
          :model-value="config.texto || ''"
          @update:model-value="v => muda('texto', v)"
        />
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.QUEM_RECEBE`) }}
          <select
            data-testid="sino-para"
            :class="SELECT"
            :value="config.para || ''"
            @change="muda('para', $event.target.value || undefined)"
          >
            <option v-for="o in PARA_SINO" :key="o.valor" :value="o.valor">
              {{ t(`${K}.PAINEL.${o.rotulo}`) }}
            </option>
          </select>
        </label>
        <div v-if="!config.para" :class="ROTULO">
          <ListaMarcar
            :opcoes="opcoesPessoas"
            :model-value="config.user_ids || []"
            @update:model-value="v => muda('user_ids', v)"
          />
          <span>{{ t(`${K}.PAINEL.QUEM_RECEBE_AJUDA`) }}</span>
        </div>
      </template>
```

5. no `trocar_responsavel`, depois do `</label>` do **papel** (antes do label da pessoa), inserir:

```vue
        <label class="flex items-center gap-2 text-[13px] text-n-slate-12">
          <input
            data-testid="so-se-vazio"
            type="checkbox"
            class="reset-base"
            :checked="!!config.so_se_vazio"
            @change="marca('so_se_vazio', $event.target.checked)"
          />
          {{ t(`${K}.PAINEL.SO_SE_VAZIO`) }}
        </label>
```

6. trocar o bloco do `esperar` inteiro (linhas 315-363) por:

```vue
      <template v-else-if="tipo === 'esperar'">
        <div class="flex flex-col gap-1.5 text-[13px] text-n-slate-12">
          <label
            v-for="o in OPCOES_ESPERA"
            :key="o.modo"
            class="flex items-center gap-2"
          >
            <input
              type="radio"
              class="reset-base"
              :data-testid="`espera-${o.modo}`"
              :checked="modoEspera === o.modo"
              @change="trocaEspera(o.modo)"
            />
            {{ t(`${K}.PAINEL.${o.rotulo}`) }}
          </label>
        </div>
        <div v-if="modoEspera !== 'horario'" class="grid grid-cols-2 gap-2">
          <label :class="ROTULO">
            {{ t(`${K}.PAINEL.QUANTIDADE`) }}
            <input
              :class="CAMPO"
              type="number"
              min="1"
              :value="config.quantidade ?? 1"
              @change="muda('quantidade', Number($event.target.value))"
            />
          </label>
          <label :class="ROTULO">
            {{ t(`${K}.PAINEL.UNIDADE`) }}
            <select
              :class="SELECT"
              :value="config.unidade || 'dias'"
              @change="muda('unidade', $event.target.value)"
            >
              <option v-for="u in UNIDADES" :key="u" :value="u">
                {{ t(`${K}.UNIDADES.${u}`) }}
              </option>
            </select>
          </label>
        </div>
        <p class="text-xs text-n-slate-10">
          {{
            t(
              `${K}.PAINEL.${modoEspera === 'reuniao' ? 'ESPERAR_REUNIAO_AJUDA' : 'ESPERAR_AJUDA'}`
            )
          }}
        </p>
      </template>
```

7. antes de `<p v-else-if="tipo === 'parar'" …>`, inserir:

```vue
      <p
        v-else-if="tipo === 'apagar_reuniao'"
        class="text-xs text-n-slate-10"
      >
        {{ t(`${K}.PAINEL.APAGAR_REUNIAO_AJUDA`) }}
      </p>
```

(d) `NoPasso.vue` — trocar o `case 'esperar'` (linhas 99-102) por:

```js
    case 'esperar': {
      if (c.ate === 'horario_comercial')
        return t(`${K}.PAINEL.ESPERAR_HORARIO`);
      const tempo = `${c.quantidade ?? ''} ${c.unidade ? t(`${K}.${Number(c.quantidade) === 1 ? 'UNIDADES_UM' : 'UNIDADES'}.${c.unidade}`) : ''}`;
      return c.antes_de === 'reuniao'
        ? t(`${K}.NO.ANTES_DA_REUNIAO`, { tempo })
        : tempo;
    }
```

(e) `Lista.vue` — no `selo`, depois do `if (!f.ativo) return { … DESLIGADO … };`, inserir:

```js
  // B4.1: em sombra só ensaia nos eventos reais (quem age ainda é o código)
  if (f.modo === 'sombra')
    return {
      classe: TOM.amber,
      icone: 'i-lucide-eye',
      texto: t(`${K}.SELO.SOMBRA`),
    };
```

(f) i18n — mesmas posições nos dois arquivos (Edit à mão):

| Onde | `en/ramon.json` | `pt_BR/ramon.json` |
|---|---|---|
| `SELO`, depois de `NO_CODIGO` | `"SOMBRA": "shadow"` | `"SOMBRA": "em sombra"` |
| `GATILHOS`, depois de `reuniao_cancelada` | `"reuniao_na_agenda": "Meeting on the calendar (task created or moved)",` | `"reuniao_na_agenda": "Reunião na agenda (tarefa criada ou remarcada)",` |
| `PASSOS`, depois de `"registrar_atividade": "Log activity",` (a linha seguinte é `"advbox": "ADVBOX",`) | `"apagar_reuniao": "Delete meeting task",` | (depois de `"registrar_atividade": "Registrar atividade",` + `"advbox": "ADVBOX",`) `"apagar_reuniao": "Apagar a tarefa da reunião",` |
| `CABECALHO`, depois de `"registrar_atividade": "Lead",` | `"apagar_reuniao": "Lead",` | `"apagar_reuniao": "Lead",` |
| `PALETA`, depois de `"registrar_atividade": …` (a linha seguinte é o `advbox` de tarefa/movimentação) | `"apagar_reuniao": "Delete meeting task",` | `"apagar_reuniao": "Apagar a tarefa da reunião",` |
| `NO`, depois de `QUALQUER_EVENTO` | `"ANTES_DA_REUNIAO": "{tempo} before the meeting"` | `"ANTES_DA_REUNIAO": "{tempo} antes da reunião"` |
| `PAINEL`, entre `PARAR_AJUDA` e `DUPLICAR` | ver bloco abaixo | ver bloco abaixo |
| `CAMPOS`, depois de `regra` | `"evento": "Meeting event (marcada, remarcada, cancelada)",` `"reuniao_de_pe": "Meeting still booked (yes or no)",` `"horario_passou": "Reminder time already passed (yes or no)"` | `"evento": "Evento da reunião (marcada, remarcada, cancelada)",` `"reuniao_de_pe": "Reunião segue marcada (sim ou não)",` `"horario_passou": "Horário do lembrete já passou (sim ou não)"` |
| novo objeto antes de `"TIPOS_TAREFA": {` | `"TIPOS_ATIVIDADE": { "fluxo": "Automation", "meeting_scheduled": "Meeting scheduled", "meeting_rescheduled": "Meeting rescheduled", "meeting_cancelled": "Meeting cancelled" },` | `"TIPOS_ATIVIDADE": { "fluxo": "Automação", "meeting_scheduled": "Reunião agendada", "meeting_rescheduled": "Reunião remarcada", "meeting_cancelled": "Reunião cancelada" },` |

(Vírgulas: ao inserir depois de uma última chave do objeto — `NO_CODIGO`, `QUALQUER_EVENTO`, `regra` —, acrescentar a vírgula nela.)

Bloco `PAINEL` (en), inserido depois de `"PARAR_AJUDA": "Ends the run here.",`:

```json
        "ESPERAR_REUNIAO": "Before the meeting",
        "ESPERAR_REUNIAO_AJUDA": "Counts back from the meeting time. If that moment has already passed, it does not wait and sets Reminder time already passed = yes.",
        "PARA_PESSOAS": "People checked below (none = lead owner)",
        "PARA_CLOSER_SDR": "Lead Closer and SDR (neither: the administrators)",
        "PARA_CONTA": "Everyone in the account",
        "SO_PARA_FRENTE": "Only forward (a lead already past this stage stays)",
        "SO_SE_VAZIO": "Only if the lead does not have one yet",
        "TAREFA_DA_REUNIAO": "Task of the meeting itself (due at the meeting time, owned by who booked it)",
        "TIPO_ATIVIDADE": "Activity type",
        "DE": "From (previous value)",
        "ONDE_RASCUNHO": "Where the draft goes",
        "ONDE_CONVERSA": "In the conversation (or the lead notes, without a conversation)",
        "ONDE_NOTAS": "In the lead notes",
        "TITULO_RASCUNHO": "Draft title (optional)",
        "APAGAR_REUNIAO_AJUDA": "Deletes the meeting task of the cancelled meeting (and stops its reminders).",
```

Bloco `PAINEL` (pt_BR), inserido depois de `"PARAR_AJUDA": "Encerra a execução aqui.",`:

```json
        "ESPERAR_REUNIAO": "Antes da reunião",
        "ESPERAR_REUNIAO_AJUDA": "Conta para trás a partir do horário da reunião. Se esse momento já passou, não espera e marca Horário do lembrete já passou = sim.",
        "PARA_PESSOAS": "As pessoas marcadas abaixo (ninguém = responsável do lead)",
        "PARA_CLOSER_SDR": "Closer e SDR do lead (sem nenhum dos dois: os administradores)",
        "PARA_CONTA": "Todo mundo da conta",
        "SO_PARA_FRENTE": "Só para a frente (quem já passou desta etapa fica onde está)",
        "SO_SE_VAZIO": "Só se o lead ainda não tem",
        "TAREFA_DA_REUNIAO": "Tarefa da própria reunião (vence na hora da reunião e fica com quem marcou)",
        "TIPO_ATIVIDADE": "Tipo da atividade",
        "DE": "De (valor anterior)",
        "ONDE_RASCUNHO": "Onde o rascunho fica",
        "ONDE_CONVERSA": "Na conversa (ou nas notas do lead, sem conversa)",
        "ONDE_NOTAS": "Nas notas do lead",
        "TITULO_RASCUNHO": "Título do rascunho (opcional)",
        "APAGAR_REUNIAO_AJUDA": "Apaga a tarefa da reunião cancelada (e para os lembretes dela).",
```

- [ ] **Step 4: Run to verify they pass**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts`
Expected: PASS — **15 arquivos / 179 testes** (170 + 9; o `i18n.spec.js` confere o catálogo novo e os rótulos de `CAMPOS`; o `fluxo.spec.js` confere `apagar_reuniao` na paleta).
Run: `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes`
Expected: sem `error` (só `Delete ␍`/`no-dynamic-keys` já conhecidos). Se o prettier reclamar da quebra de linha de algum trecho, `./node_modules/.bin/eslint --fix <arquivo>` e conferir o diff.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js app/javascript/dashboard/routes/dashboard/captain/automacoes/validar.js app/javascript/dashboard/routes/dashboard/captain/automacoes/PainelPasso.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/NoPasso.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/Lista.vue app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/PainelPasso.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/NoPasso.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/Lista.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/validar.spec.js
git commit -m "feat(fluxos): editor entende os fluxos de reunião (espera, sino, tarefa, atividade, rascunho, apagar, sombra)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 10: `mover_etapa` para etapa de perda com motivo (regra do PR #216)

**Contexto:** outra sessão entregou (PR #216) a regra "marcar lead como perdido exige `lost_reason`" — validação de presença em `app/models/concerns/lead_comercial.rb` (~linhas 63-65) — e, quando quem age é a automação (`Current.executed_by` preenchido ou sem `Current.user`), o `Lead` preenche sozinho `"Automação: <fluxo>"`. **Antes de começar esta task:** `git fetch origin ramon && git log --oneline origin/ramon | grep -i "#216"`. Se o #216 já estiver lá, `git rebase origin/ramon` (resolver conflitos só nos arquivos desta branch) e conferir a regra em `lead_comercial.rb`. Se ainda **não** estiver (em 06/10 o topo de `origin/ramon` era `aefe23a6e1`, sem o #216), escrever a task contra o contrato acima e **avisar no relatório que o executor tem de rebasear sobre o #216 antes do merge** — o exemplo "sem motivo" só passa com ele.

**Files:**
- Modify: `app/services/ramon/fluxos/passos/lead.rb` (`mover_etapa` inteiro)
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/PainelPasso.vue` (bloco do `mover_etapa` e `<script setup>`)
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json`, `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`
- Test: `spec/services/ramon/fluxos/passos_spec.rb`; `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/PainelPasso.spec.js`

**Interfaces:**
- Consumes: `LeadStage#is_lost`; `Account has_many :lost_reasons` (`{id, name}`, `app/models/account.rb:100`), lidos no front pelo getter `leadConfig/getLostReasons` (o mesmo que o `KanbanBoard.vue`/`LostReasonModal.vue` usam; o lead guarda o **texto** do motivo em `lost_reason`).
- Produces: `mover_etapa {etapa_id, so_para_frente?, motivo?}` — `motivo` (texto, aceita `{variáveis}`) só vale se a etapa de destino for de perda; aí vai no `update` como `lost_reason`. Sem motivo (ou etapa que não é de perda): `update` igual ao de hoje e o #216 preenche "Automação: <fluxo>". Ensaio/resumo: `faria: mover para <etapa> (motivo: <motivo>)` quando houver motivo. Sem checagem nova em `grafo.rb`/`validar.js` (o motivo é opcional). `data-testid`: `motivo-perda`, `motivo-outro`.

- [ ] **Step 1: Write the failing tests**

(a) `spec/services/ramon/fluxos/passos_spec.rb`, antes do `end` final:

```ruby
  describe 'mover para etapa de perda (motivo; regra do PR #216)' do
    let(:perdido) { create(:lead_stage, account: account, position: 99, is_lost: true) }

    it 'com motivo: grava o motivo escolhido' do
      r = Ramon::Fluxos::Passos::Lead.mover_etapa({ 'etapa_id' => perdido.id, 'motivo' => 'Sem interesse' }, ctx)
      expect(lead.reload.lost_reason).to eq('Sem interesse')
      expect(r[:resumo]).to eq("moveu para #{perdido.name} (motivo: Sem interesse)")
    end

    it 'sem motivo: o hub preenche "Automação: …" (quem age é a automação)' do
      Ramon::Fluxos::Passos::Lead.mover_etapa({ 'etapa_id' => perdido.id }, ctx)
      expect(lead.reload.lost_reason).to start_with('Automação:')
    end

    it 'motivo em etapa que não é de perda é ignorado' do
      comum = create(:lead_stage, account: account, position: 50)
      Ramon::Fluxos::Passos::Lead.mover_etapa({ 'etapa_id' => comum.id, 'motivo' => 'Sem interesse' }, ctx)
      expect(lead.reload).to have_attributes(lead_stage: comum, lost_reason: nil)
    end
  end
```

(b) `specs/PainelPasso.spec.js` — no `store` do topo, trocar os getters de `leadConfig` por:

```js
      getters: {
        getStages: () => [
          { id: 3, name: 'Contrato assinado' },
          { id: 9, name: 'Perdido', is_lost: true },
        ],
        getPriorities: () => [],
        getLostReasons: () => [{ id: 1, name: 'Sem interesse' }],
      },
```

e, antes do `});` final:

```js
  it('motivo da perda só aparece para etapa de perda (lista da conta + Outro)', async () => {
    const comum = montar({
      id: 'n5',
      data: { tipo: 'mover_etapa', config: { etapa_id: 3 } },
    });
    expect(comum.find('[data-testid="motivo-perda"]').exists()).toBe(false);
    const perda = montar({
      id: 'n5',
      data: { tipo: 'mover_etapa', config: { etapa_id: 9 } },
    });
    await perda.find('[data-testid="motivo-perda"]').setValue('Sem interesse');
    expect(perda.emitted('update:config').at(-1)).toEqual([
      { etapa_id: 9, motivo: 'Sem interesse' },
    ]);
    await perda.find('[data-testid="motivo-perda"]').setValue('__outro');
    await perda.find('[data-testid="motivo-outro"]').setValue('Mudou de cidade');
    expect(perda.emitted('update:config').at(-1)).toEqual([
      { etapa_id: 9, motivo: 'Mudou de cidade' },
    ]);
  });
```

(O exemplo antigo `'mover etapa usa as etapas do funil'` segue igual: o 1º `select` continua sendo o da etapa.)

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/passos_spec.rb`
Expected: FAIL — o motivo é ignorado (com o #216, o 1º grava "Automação: …"; sem o #216 o 2º também falha — rebasear).
Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/PainelPasso.spec.js --config vitest.local.config.ts`
Expected: FAIL — `motivo-perda` não existe.

- [ ] **Step 3: Implementation**

(a) `app/services/ramon/fluxos/passos/lead.rb` — trocar o `mover_etapa` inteiro (versão da Task 4) por:

```ruby
  def mover_etapa(config, ctx)
    lead = exigir_lead(ctx)
    etapa = lead.account.lead_stages.find(config['etapa_id'])
    # B4.1: "só para a frente" (como a reunião marcada do código): quem já está adiante fica onde está
    if config['so_para_frente'] && lead.lead_stage.position >= etapa.position
      return { saida: 's', resumo: "etapa: já está em #{lead.lead_stage.name} (só para a frente)" }
    end

    # PR #216: perda exige motivo. Com motivo no passo, vai ele; sem, o Lead preenche "Automação: <fluxo>".
    motivo = ctx.interpolar(config['motivo']).strip.presence if etapa.is_lost
    destino = motivo ? "#{etapa.name} (motivo: #{motivo})" : etapa.name
    return { saida: 's', resumo: "faria: mover para #{destino}" } if ctx.ensaio?

    lead.update!({ lead_stage: etapa, lost_reason: motivo }.compact)
    # a mudança feita pelo próprio fluxo não pode cancelá-lo na próxima espera
    ctx.execucao.contexto = ctx.execucao.contexto.merge('etapa_inicial_id' => etapa.id)
    { saida: 's', resumo: "moveu para #{destino}" }
  end
```

(Sem motivo, a frase do ensaio fica `faria: mover para <etapa>` — a mesma que a comparação da Task 8 usa. Complexidade: `if &&`, `if` (perda), `?:`, `if` (ensaio) → 6.)

(b) `PainelPasso.vue` — no `<script setup>`, trocar `import { computed } from 'vue';` por `import { computed, ref } from 'vue';` e, depois de `const pessoas = useMapGetter('agents/getAgents');`, inserir:

```js
// mover para etapa de perda (PR #216): motivo da lista da conta, "Outro" (texto livre) ou vazio = automático
const motivosPerda = useMapGetter('leadConfig/getLostReasons');
const OUTRO = '__outro';
const outroMotivo = ref(false);
const etapaPerda = computed(
  () => etapas.value.find(e => e.id === config.value.etapa_id)?.is_lost
);
const motivoEscolhido = computed(() => {
  const motivo = config.value.motivo;
  const daLista = motivosPerda.value.some(r => r.name === motivo);
  return outroMotivo.value || (motivo && !daLista) ? OUTRO : motivo || '';
});
const escolheMotivo = valor => {
  outroMotivo.value = valor === OUTRO;
  muda('motivo', outroMotivo.value || !valor ? undefined : valor);
};
```

no `<template v-else-if="tipo === 'mover_etapa'">` (Task 9), entre o `</label>` da etapa e o `<label …>` do `so-para-frente`, inserir:

```vue
        <template v-if="etapaPerda">
          <label :class="ROTULO">
            {{ t(`${K}.PAINEL.MOTIVO_PERDA`) }}
            <select
              data-testid="motivo-perda"
              :class="SELECT"
              :value="motivoEscolhido"
              @change="escolheMotivo($event.target.value)"
            >
              <option value="">{{ t(`${K}.PAINEL.MOTIVO_AUTOMATICO`) }}</option>
              <option v-for="m in motivosPerda" :key="m.id" :value="m.name">
                {{ m.name }}
              </option>
              <option :value="OUTRO">{{ t(`${K}.PAINEL.MOTIVO_OUTRO`) }}</option>
            </select>
          </label>
          <input
            v-if="motivoEscolhido === OUTRO"
            data-testid="motivo-outro"
            :class="CAMPO"
            :placeholder="t(`${K}.PAINEL.MOTIVO_OUTRO_PLACEHOLDER`)"
            :value="config.motivo || ''"
            @input="muda('motivo', $event.target.value)"
          />
        </template>
```

(ponytail: `outroMotivo` é estado local do painel; se o editor reaproveitar o mesmo `PainelPasso` ao trocar de passo, o "Outro" aberto pode aparecer no passo seguinte de perda — passar `:key="no.id"` no `<PainelPasso>` do `Editor.vue` se acontecer.)

(c) i18n — no bloco `PAINEL`, logo depois de `APAGAR_REUNIAO_AJUDA` (Task 9), nos dois arquivos:

en:

```json
        "MOTIVO_PERDA": "Loss reason",
        "MOTIVO_AUTOMATICO": "Automatic (Automation: flow name)",
        "MOTIVO_OUTRO": "Other…",
        "MOTIVO_OUTRO_PLACEHOLDER": "Describe it in a few words",
```

pt_BR:

```json
        "MOTIVO_PERDA": "Motivo da perda",
        "MOTIVO_AUTOMATICO": "Automático (Automação: nome do fluxo)",
        "MOTIVO_OUTRO": "Outro…",
        "MOTIVO_OUTRO_PLACEHOLDER": "Descreva em poucas palavras",
```

- [ ] **Step 4: Run to verify they pass**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts`
Expected: PASS — **15 arquivos / 180 testes** (179 + 1).
Run (CI): `bundle exec rspec spec/services/ramon/fluxos/passos_spec.rb spec/services/ramon/fluxos/reunioes_spec.rb` e `bundle exec rubocop app/services/ramon/fluxos/passos/lead.rb`; `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes/PainelPasso.vue`
Expected: PASS, sem ofensas/`error`.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/passos/lead.rb app/javascript/dashboard/routes/dashboard/captain/automacoes/PainelPasso.vue app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json spec/services/ramon/fluxos/passos_spec.rb app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/PainelPasso.spec.js
git commit -m "feat(fluxos): mover para etapa de perda com motivo (lista da conta ou outro)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 11: Verificação final + notas na spec (§15 Notas da B4.1) + texto do PR

**Files:**
- Modify: `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (acrescentar §15 no fim)

- [ ] **Step 1: Front inteiro**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts
./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes
```
Expected: 15 arquivos / 180 testes verdes; eslint sem `error`. `git status --short` não pode listar `vitest.local.config.ts`.

- [ ] **Step 2: Varredura de regras**

```bash
git diff 71e1ce0 --stat -- app/models/lead.rb app/services/ramon/advbox_event_processor.rb app/finders/conversation_finder.rb enterprise db/migrate db/schema.rb db/seeds/ramon/fluxos/sistema
git diff 71e1ce0 --stat
grep -rn "MeetingReminderJob::TOLERANCE\|meeting_open?\|purge_calcom_tasks\|meeting_summary\|RAMON_FLUXO_LEMBRETES" app spec lib
grep -rn "RAMON_FLUXO_REUNIOES" app lib .env.example
ls db/seeds/ramon/fluxos/migrados
```
Expected: o 1º vazio; o 3º vazio; a env aparece em `reunioes.rb`, no rake e no `.env.example`; 3 JSON.

- [ ] **Step 3: Notas da B4.1 na spec** — acrescentar ao fim de `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md`:

```markdown
## 15. Notas da B4.1 (06/10/2026) — agendamento de reuniões em sombra

- **Escopo (Eduardo, 06/10):** a cadeia inteira do `Ramon::ReuniaoAgendamento` migra — marcar (atividade, tarefa da reunião, etapa só para a frente, Closer automático, rascunho de confirmação nas notas do lead, sino para a conta, push), remarcar (atividade de→para, rascunho, sino, push), cancelar (atividade, tarefa apagada, sino, push) — e os 5 lembretes de **cada** reunião. Mover a tarefa no remarcar e o apagar do Cal.com no remarcado ficam no código (são o evento em si).
- **3 fluxos** (`origem: usuario`, `sistema_chave` = `reuniao_marcada`, `reuniao_cancelada`, `lembretes_reuniao`), criados pelo rake `ramon:fluxos:reunioes:sombra[conta]` a partir de `db/seeds/ramon/fluxos/migrados/*.json` (idempotente; existindo, não toca). "Reunião marcada" tem `escolha` pelo `{evento}` (marcada/remarcada). "Lembretes de reunião" usa o gatilho novo `reuniao_na_agenda` com **alvo = a tarefa da reunião**: um ciclo por reunião sem migração (o índice único já separa por alvo); remarcar recomeça só o ciclo dela (`Disparo::RECOMECA`); cancelar apaga a tarefa e o ciclo é cancelado ("o alvo foi apagado").
- **Motor ganhou:** `LeadTask` como alvo; `esperar {antes_de: 'reuniao'}` + `{horario_passou}`; `{reuniao_de_pe}`; variáveis `{evento}`, `{titulo}`, `{titulo_tarefa}`, `{resumo}`, `{resumo_antes}`, `{primeiro_nome}` (textos prontos que o código manda no gatilho); sino `para: closer_e_sdr | conta`; `mover_etapa {so_para_frente}`; `trocar_responsavel {so_se_vazio}`; `registrar_atividade {tipo, de}` com quem marcou; `criar_tarefa {prazo: 'reuniao'}` (vence na reunião, é de quem marcou, põe a reunião na agenda); `rascunho_texto {onde: notas_do_lead, titulo}`; passo `apagar_reuniao`; ensaios que dizem quem/quando (`faria: sino para …`, `faria: tarefa … para …`); desligar o fluxo cancela também a sombra.
- **A decisão é do evento:** cada marcar/remarcar/cancelar lê `Reunioes.assumiu?` uma vez e manda `assumido` no gatilho; para os 3 fluxos migrados o `Disparo` age ou ensaia por essa decisão (não pelo modo). "Reunião marcada/cancelada" rodam na hora, dentro da requisição; com o código no comando, o ensaio roda antes dos efeitos do código.
- **A chave:** `RAMON_FLUXO_REUNIOES=on` **e** os 3 fluxos ligados, publicados, em `modo: normal` e com o gatilho certo → o código só dispara; qualquer peça fora → o código faz tudo e os fluxos ensaiam. Virar = `rake ramon:fluxos:reunioes:modo[conta,normal]` (recusa sem a env); voltar = `…modo[conta,sombra]` (ou env desligada, ou um fluxo desligado na tela). Os lembretes já enfileirados pelo código saem pelo código (o job não consulta a chave).
- **Comparação:** `rake ramon:fluxos:reunioes:comparar[conta,dias]` (só leitura): agendamentos (cada evento: atividade, tarefa, etapa, Closer, rascunho, sino, tarefas apagadas, na frase do ensaio) e lembretes (lead, horário ±3 min, pessoas). Só eventos depois que a sombra nasceu; ignora o "Testar com um lead…"; respeita o teto de 300 avisos por pessoa — por isso roda todo dia.
- **Etapa de perda (PR #216):** `mover_etapa` aceita `motivo` opcional (lista de motivos da conta ou texto livre); só vale para etapa `is_lost` e vai como `lost_reason`; sem ele, o `Lead` preenche "Automação: <fluxo>".
- **Teto conhecido:** com os fluxos no comando, dois eventos do mesmo lead na mesma fração de segundo → o 2º é ignorado pelo índice único (duplo clique não cria 2 reuniões); passo que falha na hora tenta de novo em 1/5/15 min (aparece com atraso, não em dobro).
- **Fica para a limpeza (outro PR, 2 semanas depois de rodar em normal):** apagar os efeitos do código no `ReuniaoAgendamento` (fica só o disparo e o mover tarefa), o `Ramon::MeetingReminderJob`, o JSON `sistema/lembretes_reuniao.json` **e** a linha `origem: sistema` dele, e a env.
```

- [ ] **Step 4: Texto do PR (não abrir — gate do Eduardo)** — deixar no relatório final:

```markdown
Automações em fluxo — B4.1: o agendamento de reuniões inteiro ganha 3 fluxos de verdade — "Reunião marcada" (atividade, tarefa, etapa, Closer automático, rascunho de confirmação nas notas do lead, sino e push; remarcar refaz atividade, rascunho e sino), "Reunião cancelada" (atividade, tarefa apagada, sino e push) e "Lembretes de reunião" (24h, 8h, 1h, 30 min e 5 min antes, para o Closer e o SDR, um ciclo por reunião). Eles rodam **em sombra**: acompanham as reuniões reais e anotam o que fariam, sem escrever nada, enquanto o código continua fazendo tudo como hoje. Uma comparação diária mostra, evento a evento e lembrete a lembrete, o que o código fez e o que os fluxos fariam. Quando bater e o Eduardo aprovar, uma chave faz os fluxos assumirem e o código parar — e eles viram editáveis na tela. **A chave vem desligada: nada muda no uso até o Eduardo virar.** No editor: "Esperar antes da reunião", sino para "Closer e SDR" ou "Todo mundo da conta", "Só para a frente", "Só se ainda não tem", "Tarefa da própria reunião", atividade de reunião, rascunho nas notas do lead, passo "Apagar a tarefa da reunião", gatilho "Reunião na agenda", "Motivo da perda" no "Mover para etapa" de perda e o selo "em sombra".

## Closes
- Spec `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` §8 (B4+, migração 1 a 1 em sombra — 1ª: lembretes de reunião, ampliada pelo Eduardo para o agendamento inteiro) e §14 (nota da B4); notas novas em §15.

## How to test
1. Depois do deploy: `rake "ramon:fluxos:reunioes:sombra[2]"` → os 3 fluxos "modo sombra, ligado" e "Agora o CÓDIGO faz o agendamento (os fluxos ensaiam)".
2. Inteligência → Automações → Meus fluxos: "Reunião marcada", "Reunião cancelada" e "Lembretes de reunião" com o selo "em sombra". Abrir cada um e conferir os passos.
3. Num lead de teste, marcar reunião para daqui a ~40 min: tudo acontece como sempre (tarefa, atividade, etapa, rascunho, sino, lembrete de 30 min) e, em Execuções, "Reunião marcada" tem um ensaio com as mesmas coisas (`faria: …`) e "Lembretes de reunião" um ciclo ensaio. Remarcar e cancelar: idem.
4. `rake "ramon:fluxos:reunioes:comparar[2,1]"` → linhas "igual" e "Resultado geral: BATEU".

## What changed
- Motor: tarefa da reunião como alvo, gatilho `reuniao_na_agenda`, remarcar recomeça só o ciclo daquela reunião, fluxos de reunião na hora e decididos pelo evento, esperar antes da reunião, `{reuniao_de_pe}`, textos prontos da reunião como variáveis, opções novas nos passos (sino, etapa, Closer, atividade, tarefa, rascunho) e o passo "Apagar a tarefa da reunião"; desligar também para a sombra.
- `Ramon::ReuniaoAgendamento` decide uma vez por evento quem faz e dispara antes; o cancelamento do Cal.com passa por ele. `Ramon::Fluxos::Reunioes` (regras únicas, os 3 fluxos, a chave), `CompararAgendamentos` e `CompararLembretes`; rake `ramon:fluxos:reunioes:{sombra,modo,comparar}`; `MeetingReminderJob` usa as regras únicas (mesmo comportamento).
- Chave `RAMON_FLUXO_REUNIOES` (desligada). Front: editor e lista. Sem migração.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv
```

- [ ] **Step 5: Smoke em bloco (para o Eduardo, depois do deploy)** — anotar no relatório: (1) rodar o rake `sombra` e ver os 3 fluxos com o selo "em sombra"; (2) abrir cada fluxo e conferir passos e textos (aqui o Eduardo confirma os textos internos — E2); (3) num lead de teste: marcar para daqui a ~40 min (tudo como sempre + ensaios), remarcar (ciclo antigo cancelado, novo esperando), marcar uma 2ª reunião (2 ciclos), cancelar uma (só o ciclo dela some); (4) rodar o `comparar` e colar a saída; (5) apagar o lead de teste (apagar `LeadActivity` antes do lead).

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md
git commit -m "docs(fluxos): notas da B4.1 na spec" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

Sem push.

---

## Operação depois do deploy

Conta da banca = **2**; console = `docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "<task>"` (Eduardo roda via `!` e cola a saída). Deploy desta fatia = o de sempre (`docker compose pull chatwoot-web chatwoot-worker && docker compose up -d chatwoot-web chatwoot-worker`), **sem migração** e **sem env nova**.

**1. Ligar a sombra (dia 0).**
`docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:reunioes:sombra[2]"`
Saída esperada: os 3 fluxos "modo sombra, ligado" e "Agora o CÓDIGO faz o agendamento (os fluxos ensaiam)". A partir daqui, todo marcar/remarcar/cancelar gera um ensaio em "Reunião marcada"/"Reunião cancelada" e cada reunião ganha um ciclo ensaio em "Lembretes de reunião"; o código continua fazendo tudo. Rodar de novo não duplica.

**2. Quanto tempo (E4).** No mínimo **7 dias corridos** e até juntar **≥ 15 lembretes comparados** e, nos agendamentos, **≥ 3 marcadas, ≥ 1 remarcada e ≥ 1 cancelada comparadas** (se não acontecer naturalmente, provocar num lead de teste). Eventos de antes do dia 0 não entram.

**3. Comparar — todo dia** (o sino do Chatwoot guarda só os 300 avisos mais recentes por pessoa; olhar o dia anterior todo dia evita perder rastro):
`docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:reunioes:comparar[2,1]"`
Saem dois blocos — **Agendamentos** (uma linha por evento: `igual`, `diferente` com o que ficou "só no código"/"só no fluxo", `so_codigo`, `so_fluxo`) e **Lembretes** (uma linha por lembrete: `igual`, `só no código`, `só no fluxo`, `pessoas diferentes`) — e o "Resultado geral". No fim do período, `…comparar[2,7]` (as linhas antigas podem ter sumido do sino — vale a soma das diárias).

**4. Critério GO / NO-GO (E4):**
- **GO:** ≥ 7 dias; ≥ 15 lembretes, ≥ 3 marcadas, ≥ 1 remarcada e ≥ 1 cancelada comparadas; **0** linhas que não sejam `igual`, ou cada uma explicada e aceita pelo Eduardo (ex.: alguém apagou o aviso do sino; alguém mexeu no lead no mesmo minuto do evento; deploy no minuto do lembrete).
- **NO-GO:** qualquer divergência sem explicação → corrigir (código ou desenho; o desenho se edita na tela e se publica de novo) e **recomeçar a contagem**.

**5. Virar a chave (GO).** Nesta ordem — em nenhum momento um efeito sai em dobro ou deixa de sair (a decisão é por evento):
1. Acrescentar `RAMON_FLUXO_REUNIOES=on` ao `chatwoot.env` em `/opt/intranet-ramon` e recriar: `docker compose up -d chatwoot-web chatwoot-worker`. Nada muda ainda (os fluxos estão em sombra → o código segue).
2. `docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:reunioes:modo[2,normal]"` → "Agora os FLUXOS fazem o agendamento (o código não faz mais)". Daí em diante, todo evento novo é dos fluxos; as reuniões marcadas antes mantêm os lembretes do código que já estão na fila.
3. Smoke: num lead de teste, marcar para daqui a ~40 min → tarefa, atividade, etapa, Closer, rascunho (idêntico ao de sempre, nas notas), sino "Automação: Reunião marcada com …" para a conta; em Execuções, "Reunião marcada" **sem** o selo ensaio e um ciclo de verdade em "Lembretes"; aos 30 min, o sino "Automação: Reunião em 30min antes (…)" chega ao Closer/SDR; nenhum lembrete do código para essa reunião. Remarcar e cancelar: idem.
Os fluxos viram editáveis como qualquer outro (só admin — E6). A aba "Do sistema" ainda mostra "Lembretes de reunião — roda no código" até o PR de limpeza.

**6. Rollback (a qualquer momento, sem deploy).** Preferido:
`docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:reunioes:modo[2,sombra]"` → "Agora o CÓDIGO faz o agendamento". Eventos novos voltam para o código na hora; os ciclos de lembrete que já esperavam no fluxo (reuniões marcadas durante o período no comando) terminam pelo fluxo — sem dobra.
- Também é seguro desligar a env ou desligar "Reunião marcada"/"Reunião cancelada" na tela (o código volta e os fluxos só ensaiam). **Desligar "Lembretes de reunião" na tela cancela** os ciclos que esperavam — as reuniões marcadas no período do fluxo perdem os lembretes que faltavam; prefira o rake.
- Parar a sombra antes de virar: desligar os 3 na tela (os ensaios que esperavam são cancelados).

**7. Depois (outro PR, E7).** Com 2 semanas em normal sem incidente: tirar do `ReuniaoAgendamento` os efeitos do código (fica só o disparo e o mover tarefa), apagar o `Ramon::MeetingReminderJob`, o JSON `db/seeds/ramon/fluxos/sistema/lembretes_reuniao.json` **e** a linha `origem: sistema` dele (a sincronização não apaga linha cujo JSON sumiu), e a env `RAMON_FLUXO_REUNIOES`.

---

## Divergências registradas (spec × este plano)

| # | Onde | Divergência | Motivo |
|---|---|---|---|
| 1 | Spec §6 ("modo sombra cria execução com status ensaio") | Sombra = coluna `ensaio: true` com status normal, e **espera de verdade** (não pula esperas como o "Testar…") | Já é assim desde a B1; a sombra precisa esperar para comparar horários |
| 2 | Spec §6 (sombra pelo `modo` do fluxo) | Nos 3 fluxos migrados, ensaiar ou agir é decidido **pelo evento** (`assumido`), lido uma vez pelo código | Nem dobra nem buraco na virada ou com um fluxo desligado |
| 3 | Spec §6 (Disparo enfileira o avanço) | "Reunião marcada/cancelada" migrados rodam **na hora**, dentro da requisição | Painel igual (tarefa na hora), `Current.user` de quem marcou, ensaio antes do código |
| 4 | Spec §4.4 ("espera conta do passo anterior") | `esperar {antes_de: 'reuniao'}` conta para trás a partir da reunião | Os lembretes são 24h/8h/1h/30min/5min antes |
| 5 | Spec §5 (alvo Lead/Conversation) | Alvo também pode ser a tarefa da reunião (`LeadTask`) | Um ciclo por reunião (E3) sem migração |
| 6 | Spec §4.1 (gatilhos) | Gatilho novo `reuniao_na_agenda` | Começa o ciclo da reunião que entrou na agenda (criada ou movida) |
| 7 | Spec §8 passo 3 ("env/flag desliga o caminho do código, fluxo vira normal") | Chave dupla: env **e** os 3 em `modo: normal` (rake) | E5 |
| 8 | Spec §8 ("lembretes de reunião" primeiro) | A 1ª migração é o agendamento inteiro | E1 |

## Decisões do Eduardo (06/10/2026)

| # | Decisão | Onde no plano |
|---|---|---|
| E1 | **Decidido 06/10 — a cadeia inteira migra** (marcar, remarcar, cancelar e os lembretes); o rascunho de confirmação segue rascunho, nas notas do lead, com o texto copiado do código | Tasks 5–7 |
| E2 | **Decidido 06/10 — textos internos (sino/push) podem mudar** (o sino de fluxo chega como "Automação: … (nome)"; o push usa o nome do contato) | Task 7 |
| E3 | **Decidido 06/10 — lembretes de cada reunião aberta**; remarcar recomeça só a dela; cancelar para só a dela (alvo = a tarefa, sem migração) | Tasks 3, 7 |
| E4 | **Decidido 06/10 — ≥ 7 dias, ≥ 15 lembretes, 0 divergência sem explicação**, contando também ≥ 3 marcadas, ≥ 1 remarcada e ≥ 1 cancelada comparadas | Operação §2–§4 |
| E5 | **Decidido 06/10 — chave = 1 env (`RAMON_FLUXO_REUNIOES=on`) + os 3 fluxos em modo normal (rake); voltar = rake `modo sombra`, sem deploy** | Task 6, Operação §5–§6 |
| E6 | **Decidido 06/10 — depois de assumir, os fluxos são editáveis por admin** (uma edição errada tira o efeito correspondente) | — |
| E7 | **Decidido 06/10 — limpeza num PR separado, depois de 2 semanas em normal sem incidente** | Operação §7 |

## Decisões novas que dependem do Eduardo

| # | Decisão | Proposta do plano | Onde |
|---|---|---|---|
| N1 | No **remarcar**, mover a tarefa para o horário novo fica no código (é a remarcação em si, antes de qualquer fluxo); e no **Cal.com remarcado**, apagar as reuniões Cal.com antigas do lead fica no controller (é a integração) | **Aceito pelo Eduardo 06/10** — os fluxos recebem a reunião já movida e fazem todo o resto | Task 6 |
| N2 | Com os fluxos no comando, dois eventos do **mesmo lead** na mesma fração de segundo (ex.: duplo clique em "marcar") viram um só (o código de hoje criaria 2 reuniões); e se um passo falhar na hora (ex.: banco fora do ar), a tarefa/o rascunho aparecem com 1–15 min de atraso, não em dobro | **Aceito pelo Eduardo 06/10** (raro; mais seguro que o de hoje no duplo clique) | Análise da virada |
