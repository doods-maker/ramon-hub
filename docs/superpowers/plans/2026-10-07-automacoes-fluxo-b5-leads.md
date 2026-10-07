# Automações em fluxo — B5-leads (leads e conversas) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** As 5 automações de lead/conversa que ainda moram nos ouvintes — **criar lead da conversa**, **origem do lead**, **sugestão de documento**, **coach de objeção** e **agente do hub (@claude)** — saem do código para **5 fluxos de verdade**, cada um com a chave da B4 (env própria + fluxo em modo normal ⇒ o fluxo faz e o código para; qualquer peça fora ⇒ o código faz) e **reserva pelo código** (fluxo no comando que não pega o evento ⇒ o código faz aquele evento). As **etiquetas de etapa/tese** ficam como regra fixa ou viram fluxo conforme a N1. Tudo nasce **desligado**: nada muda em produção até o Eduardo virar.

**Architecture:** Um ajudante novo, `Ramon::Fluxos::Migracao.decidir(grupo, gatilho, alvo, dados) { código }`, faz em 4 linhas o que `LeadGanho.ganhou` faz (lê `assumiu?` uma vez, dispara os migrados com `assumido`, roda o bloco `unless assumido && feitas.any?`) e marca o grupo no evento (`'migracao'`), porque agora há **vários grupos no mesmo gatilho** (`conversa_criada`: SLA + criar lead; `mensagem_recebida`: origem + documento + coach). O código de hoje muda de arquivo sem mudar nada (`Ramon::LeadDaConversa`, `Ramon::AgenteNotifyJob.chamado?`) e as **rotinas prontas** (`app/services/ramon/fluxos/rotinas/leads.rb`, registro do B5-conta) chamam exatamente esse código. Criar lead e origem migrados **rodam na hora**, dentro do ouvinte (`Disparo::NA_HORA_CHAVES`), para a **ordem de sempre** não mudar: o lead existe antes do SLA e dos fluxos comuns de Conversa nova; a origem existe antes dos fluxos comuns de Mensagem recebida. Gatilho novo **"Nota privada escrita"** (`nota_escrita`) para o agente. Sem migração de banco.

**Tech Stack:** Rails 7.1 / RSpec (só no CI), Postgres jsonb, Sidekiq (ActiveJob), Wisper (ouvintes do `AsyncDispatcher`); Vue 3.5 `<script setup>`, vue-i18n 9, Vitest 3.

**Spec:** `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (§4 peças, §6 motor, §8 migração B4+, §14 notas da B3 — fluxos do sistema, §16 B4.2 — "um novo grupo em `conversa_criada` precisa da sua própria chave de decisão", §18 B4.4/B4.5 — reserva, passo `rotina`). Desenhos de hoje: `db/seeds/ramon/fluxos/sistema/{criar_lead_da_conversa,origem_do_lead,etiquetas_etapa_tese,coach_objecao,sugestao_documento,agente_hub}.json` (a "descricao" de cada um). Plano-modelo: `docs/superpowers/plans/2026-10-07-automacoes-fluxo-b44-ganho-advbox.md`.

---

## Decisões para o Eduardo

> Só o que muda o que alguém vê ou o risco. O controlador pergunta num formulário; as tasks já estão escritas com a **recomendação** e dizem o que muda se a resposta for outra.

**N1 — Etiquetas `fase-…` e `tese-…` na conversa** (hoje o hub mantém a etiqueta da etapa e da tese do lead na conversa e, no sentido contrário, uma etiqueta `fase-…` posta à mão move o lead).
- **A (recomendado):** fica no código como **"regra fixa"** (selo na aba "Do sistema", igual a histórico do lead e SDR automático). É um espelho de dado: num fluxo editável, a única edição possível é a que quebra o espelho (filtro por etiqueta e por etapa deixam de bater).
- **B:** o sentido "lead → conversa" vira fluxo (gatilho novo **"Lead atualizado"**, que dispara só quando a etiqueta ficou fora do lugar); a etiqueta posta à mão continua movendo o lead pelo código (regra fixa).

**N2 — Agente do hub (@claude).**
- **A (recomendado):** vira fluxo, com um gatilho novo **"Nota privada escrita"** (que também fica disponível para outros fluxos seus — ex.: "nota com 'urgente' → push"). A trava "só nota que começa com @claude, só do seu e-mail, só com o agente configurado" fica **presa dentro do passo**: nenhuma edição na tela a tira, nem usando o passo noutro fluxo.
- **B:** fica no código como "regra fixa" (é segurança: quem chama o agente).

**N3 — Balão "⚙ Fluxo …" na conversa** (todo passo de fluxo que age deixa esse balão interno).
- **A (recomendado):** só no **Criar lead** (1 por conversa nova). Origem, sugestão de documento, coach e agente **não** põem balão: seriam 1 a cada mensagem do cliente, e o coach e a sugestão já mostram o próprio balão, como hoje.
- **B:** em todos (o padrão dos fluxos).
- **C:** em nenhum.

**N4 — IA fora do ar ao ler um anexo (sugestão de documento).**
- **A:** o fluxo tenta de novo em 1, 5 e 15 min e, se continuar, marca "falhou" e **avisa os administradores (sino + push) — um aviso por anexo**.
- **B (recomendado):** tenta de novo do mesmo jeito e, se continuar, **desiste em silêncio** (fica registrado na tela de execuções), como o código hoje.

**N5 — Várias fotos/mensagens do cliente de uma vez, com o fluxo no comando.** A 1ª passa pelo fluxo; as que chegam enquanto ela ainda roda (segundos da IA) são feitas **pelo código** (reserva). Nenhuma se perde nem sai em dobro, mas só a 1ª aparece na tela de execuções.
- **A (recomendado):** aceitar.
- **B:** rodar a sugestão de documento e o coach "na hora", dentro do evento: tudo aparece em Execuções, mas a IA passaria a segurar a fila de eventos do hub (mensagens, etiquetas, avisos) por segundos a cada anexo.

## Escolhas técnicas (decididas aqui)

- **T1 — Uma chave por automação** (5 envs, 5 grupos em `Migracao::GRUPOS`): virar e voltar uma de cada vez, sem deploy. Grupos: `criar_lead` (`RAMON_FLUXO_CRIAR_LEAD`), `origem_lead` (`RAMON_FLUXO_ORIGEM_LEAD`), `sugestao_doc` (`RAMON_FLUXO_SUGESTAO_DOC`), `coach` (`RAMON_FLUXO_COACH`), `agente` (`RAMON_FLUXO_AGENTE`).
- **T2 — `Migracao.decidir` + `'migracao'` no evento.** A §16 avisou: "um novo grupo em `conversa_criada` precisa da sua própria chave de decisão". O `Disparo.da_vez?` passa a aceitar `dados['migracao']`: com ele, só os migrados **daquele grupo** ouvem; sem ele (reuniões, lead ganho, ADVBOX), o comportamento de hoje. O SLA (B4.2) passa a usar o mesmo `decidir` (mesma lógica, 1 linha).
- **T3 — Criar lead e origem rodam na hora** (`Disparo::NA_HORA_CHAVES`, por chave do fluxo — não pelo gatilho, senão o SLA, o coach e o documento, nos mesmos gatilhos, também rodariam dentro do evento). Coach, documento e agente seguem pela fila (`FluxoAvancarJob`), como os jobs de hoje.
- **T4 — As guardas de hoje ficam antes da decisão, no ouvinte** (caixa com "Criar lead" + contato; há origem a anotar; anexo imagem/arquivo; texto com 20+ caracteres; nota @claude do Eduardo): o fluxo só começa quando há o que fazer — **1 execução de origem por lead, não por mensagem**. A rotina **confere de novo** a mesma guarda (mesma função): o passo usado noutro fluxo nunca faz o que o código não faria (ex.: chamar o agente para outra pessoa).
- **T5 — As rotinas chamam `Job.new.perform(id)`** (o corpo do job, na hora): nem `perform_later` (o fluxo não saberia o resultado) nem `perform_now` (o `retry_on` do job re-enfileiraria o job por fora do motor → dobra).
- **T6 — Gatilho `nota_escrita`** (não `nota_privada`, que já é nome de passo): nota privada com autor **pessoa** (`User`). Notas que os fluxos escrevem não têm autor e não disparam nada (sem laço).
- **T7 — `'mensagem_id'` no gatilho** de `mensagem_recebida` (também no `RamonFluxoListener`): as rotinas de mensagem funcionam em qualquer fluxo de Mensagem recebida, não só no migrado.
- **T8 — Direto, sem sombra nem comparação** (E1 herdado da B4.2): deploy → criar → virar → teste ao vivo. Enquanto o código está no comando, o fluxo só ensaia (de graça).
- **T9 — `cancelar_se_sair_da_etapa: false`** nos 5 gatilhos (coach/documento rodam segundos depois; uma mudança de etapa nesse meio não pode cancelar).
- **T10 — "Execução migrada que falha conta como feita"** (§18): o código não refaz; a falha fica na tela. Só "nenhuma execução criada" aciona a reserva. Criar lead e origem são idempotentes (lead aberto do contato é reaproveitado; canal já derivado não é sobrescrito), então reserva + nova tentativa nunca duplicam.

## Global Constraints

- **Depende do B5-conta** (ordem de merge B5-conta → B5-leads → B5-externos). O B5-conta cria o **registro de rotinas por arquivo** e o selo **"regra fixa"**. Esta branch (`feat/fluxos-b5-leads`, worktree `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-fluxos-b44`) parte de `origin/ramon` **0a31e02** (B4.1–B4.5 no ar) e é **rebaseada no B5-conta** na Task 0. Nunca `git push`, nunca abrir PR, nunca `git stash`, nunca `git add -A`.
- **Formato assumido do registro de rotinas (depende de B5-conta — o controlador concilia):** `Ramon::Fluxos::Passos::Rotina` acha a rotina pelo nome num registro de módulos (`Ramon::Fluxos::Rotinas::MODULOS`, uma lista; cada plano acrescenta o seu módulo **no fim**); cada módulo expõe `ROTINAS` (Array de nomes) e um método público por nome, `nome(ctx)`, que devolve o resultado do passo `{ saida: 's', resumo: String, sem_balao: true? }` e cuida do próprio alvo (o `exigir_lead` sai de antes do despacho). Se o formato do B5-conta for outro, muda só a **casca** (registro e assinatura); os corpos dos métodos ficam.
- **Formato assumido do selo "regra fixa" (depende de B5-conta):** uma chave no JSON do sistema (assumido `"regra_fixa": true` em `db/seeds/ramon/fluxos/sistema/<chave>.json`) + a lista das regras fixas no spec que o B5-conta criar.
- **Produção não muda até virar.** Com as 5 envs ausentes/`off` (padrão) tudo acontece como hoje; os fluxos só nascem pelo rake `criar`.
- **Não apagar o caminho antigo (E7):** o código de hoje fica, só muda de arquivo (`RamonLeadListener` → `Ramon::LeadDaConversa`; guarda do agente → `Ramon::AgenteNotifyJob.chamado?`). Os JSON `sistema/*.json` e as linhas `origem: sistema` ficam (saem na limpeza, outro PR, 2 semanas depois).
- **Sem migração de banco.** Se alguma task achar que precisa de coluna/índice: pare e pergunte.
- **Rubocop do fork** (o CI barra): `Metrics/AbcSize` 26, `MethodLength` 19, `CyclomaticComplexity` 7, `PerceivedComplexity` 8, `ClassLength` 175, `ModuleLength` 100, `BlockLength` 30 (fora de spec), linha 150; `Style/HashSyntax` `EnforcedShorthandSyntax: never`; `Layout/EmptyLineAfterGuardClause`; `RSpec/ContextWording` (só when/with/without — use `describe` para frases em pt-BR); `RSpec/SortMetadata`; `Style/StringLiterals`; `Performance/CollectionLiteralInLoop` (array literal dentro de bloco → constante); `RSpec/SpecFilePathFormat` (spec de `Ramon::Fluxos::Rotinas::Leads` em `spec/services/ramon/fluxos/rotinas/leads_spec.rb`). Tamanhos na base 0a31e02 (linhas de código): `migracao.rb` 69 (**módulo: limite 100** — os irmãos também acrescentam grupos; se passar de 100 depois do rebase, pare e avise), `disparo.rb` 98, `ramon_lead_listener.rb` 79, `rotina.rb` 45.
- **Sem Ruby local:** specs Ruby escritos e rastreados à mão; quem valida é o CI. **1 execução viva não-ensaio por (fluxo, alvo) por exemplo** (índice único parcial `… WHERE status IN ('rodando','esperando') AND NOT ensaio`; `status` tem padrão `'rodando'`). `with_modified_env`, nunca stub de `ENV`. `.pluck.uniq`, nunca `.distinct.pluck`. Notificações: 1 linha por pessoa por chamada.
- **A fábrica `:message` põe autor `User` em toda mensagem `outgoing`** (`spec/factories/messages.rb`): nota "sem autor" no spec = `nota.sender = nil` em memória.
- **CI FOSS apaga `enterprise/`:** esta fatia não toca Captain nem `enterprise/`.
- **Mensagem ao cliente:** nenhuma rotina desta fatia escreve ao cliente (o coach só sugere no balão; o agente responde em nota privada). A API de fluxos segue admin-only.
- **Front:** i18n só em `CAPTAIN_RAMON.FLUXOS` de `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json`, chaves novas **no fim** de cada objeto e na **mesma posição** nos dois arquivos (trava `specs/i18n.spec.js`); textos **sem `@`, `|`, `{`, `}`** (por isso "arroba claude" por extenso nos textos da tela); editar à mão (Edit). Tailwind only; evento custom camelCase.
- **Vitest:** `node_modules` é junção (nunca apagar). Config local fora do git: `TZ=UTC npx vitest run <arquivos> --config vitest.local.config.ts`. ESLint: `./node_modules/.bin/eslint <arquivos>` (erro `Delete ␍` = CRLF do checkout, ignorar).
- **Acréscimos só no fim das listas compartilhadas** (`GRUPOS`, `DUAS_VEZES`, `Grafo::GATILHOS`, `GATILHOS`/`ROTINAS` do `fluxo.js`, objetos do i18n, `.env.example`) — o rebase com os irmãos fica trivial.
- **Commits:** Conventional Commits em pt-BR, sem citar Claude no assunto; corpo termina com:
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR`
  `git add` só dos caminhos da task.

## Review Focus

1. **Conversa nova numa caixa com "Criar lead", com o fluxo no comando** — o lead tem de existir antes do disparo do SLA e antes dos fluxos comuns de Conversa nova, e `lead.created` sai **uma** vez (os relatórios contam leads por esse evento e pela atividade "created"). Teste: Task 4 ("fluxo no comando: a mesma ordem…") e Task 2 ("código no comando: o lead nasce antes…").
2. **Cliente manda 3 fotos de uma vez com o fluxo de documento no comando** — nenhuma se perde, nenhuma em dobro. Teste: Task 4 ("rajada de anexos…").
3. **1ª mensagem com anúncio da Meta** — a origem fica gravada antes dos fluxos comuns de Mensagem recebida (que podem ler `{origem}`/`{canal}`), nos dois modos; mensagens seguintes não criam execução. Teste: Task 2 ("a origem é gravada antes…", "sem nada a anotar…") e Task 4 ("origem pelo fluxo…").
4. **Nota @claude de outra pessoa, ou o passo do agente usado noutro fluxo** — o agente nunca é chamado. Teste: Task 3 ("a trava fica na rotina…") e Task 4 ("nota @claude de outra pessoa…").
5. **Dois grupos no mesmo gatilho com uma chave ligada e a outra não** (SLA × criar lead; origem × documento × coach) — cada decisão só inicia o fluxo do seu grupo; nada em dobro, nada esquecido. Teste: Task 1 ("dois grupos migrados no mesmo gatilho…") e Task 4 (as do coach/documento rodam com a origem desligada).

---

## A ordem de hoje (mapeada no código) e como ela fica

`Rails.configuration.dispatcher` = `Dispatcher` → `SyncDispatcher` (ActionCable, AgentBot) + `AsyncDispatcher` (1 `EventDispatcherJob` por evento, fila `critical`). No job, o Wisper chama os ouvintes **em sequência, na ordem de `AsyncDispatcher#listeners`**: …nativos… → **`RamonLeadListener` → `RamonAgenteListener` → `RamonFluxoListener`** (enterprise só acrescenta `CaptainListener` no fim).

| Evento | Hoje | Depois (código ou fluxo no comando) |
|---|---|---|
| `conversation.created` (caixa com Criar lead, conversa com contato) | 1. `RamonLeadListener`: liga ao lead aberto do contato **ou** cria o lead (síncrono; o `after_create_commit` do Lead grava a atividade `created` e enfileira `lead.created`) → 2. SLA (`decide` B4.2: `Disparo.externo('conversa_criada', assumido)` + job) → 3. `RamonFluxoListener`: fluxos comuns de `conversa_criada` | 1. `decidir('criar_lead')`: o fluxo migrado roda **na hora** (cria/liga pelo mesmo `Ramon::LeadDaConversa.criar_ou_ligar`) ou o código faz → 2. `decidir('sla')` (igual) → 3. igual. **O lead existe em 2 e 3 nos dois modos.** |
| `lead.created` (outro job) | `RamonLeadListener#lead_created` (etiquetas) → `RamonFluxoListener#lead_created` (`lead_criado`) | igual (N1=A) |
| `message.created` incoming, conversa com lead | 1. origem (síncrono: `apply_meta_referral` + `derive_channel_from_first_contact`) → 2. anexo → `DocMatchJob` (fila) → 3. 20+ caracteres → `CoachObjecaoJob` (fila) → 4. `RamonFluxoListener`: `mensagem_recebida` | 1. `decidir('origem_lead')` só se há o que anotar — o migrado roda **na hora** → 2. `decidir('sugestao_doc')` → 3. `decidir('coach')` (fluxos pela fila) → 4. igual (+ `mensagem_id`). **A origem existe em 4 nos dois modos.** |
| `message.created` nota privada | `RamonAgenteListener` (guarda @claude/Eduardo/URL) → `AgenteNotifyJob` (fila); `RamonFluxoListener`: nada | `RamonAgenteListener`: mesma guarda → `decidir('agente', 'nota_escrita')`; `RamonFluxoListener`: `nota_escrita` para os fluxos comuns (nota de pessoa) |
| `DocMatchService#gravar_sugestao` | `Disparo.externo('documento_recebido', lead)` | igual — a rotina chama o mesmo serviço, então o gatilho "Documento recebido" continua nascendo daqui |
| `conversation.updated` (etiqueta `fase-*` adicionada à mão) | `StageLabelSync.apply_to_lead` move o lead | igual (regra fixa nas duas opções da N1) |

Laços: nenhum novo. O fluxo de criar lead/origem grava o lead → `lead.updated` com `performed_by` = a execução (o `RamonFluxoListener` só dispara `lead_mudou_etapa` se a etapa mudou — não muda). Notas escritas por fluxo não têm autor → não disparam `nota_escrita`. Etiquetas (N1=B): fluxo põe a etiqueta → `conversation.updated` → `apply_to_lead` acha a etapa igual → não move → `set_conversation_fase` não grava (guardas de igualdade de hoje).

## Mapa de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `app/services/ramon/fluxos/migracao.rb` | +5 grupos (fim de `GRUPOS`) + `decidir` |
| `app/services/ramon/fluxos/disparo.rb` | `da_vez?` respeita `'migracao'`; `NA_HORA_CHAVES`; `DUAS_VEZES` += `mensagem_recebida`, `nota_escrita` |
| `app/services/ramon/fluxos/grafo.rb` | `GATILHOS` += `nota_escrita` |
| `app/listeners/ramon_fluxo_listener.rb` | `mensagem_id` no gatilho; nota de pessoa → `nota_escrita` |
| `app/services/ramon/lead_da_conversa.rb` (novo) | criar/ligar o lead e a origem — o código de hoje, mudado de arquivo |
| `app/jobs/ramon/agente_notify_job.rb` | `self.chamado?(message)` (a guarda de hoje, num lugar só) |
| `app/listeners/ramon_lead_listener.rb` | decide (`Migracao.decidir`) em vez de fazer direto; mesma ordem |
| `app/listeners/ramon_agente_listener.rb` | decide (`Migracao.decidir`) |
| `app/services/ramon/fluxos/rotinas/leads.rb` (novo) | 5 rotinas prontas (registro do B5-conta) |
| `db/seeds/ramon/fluxos/migrados/{criar_lead_da_conversa,origem_do_lead,sugestao_documento,coach_objecao,agente_hub}.json` (novos) | os 5 desenhos |
| `db/seeds/ramon/fluxos/sistema/{…5…}.json` | 1ª linha "No código:" atualizada; agente com o gatilho novo |
| `.env.example` | as 5 envs |
| `app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js` + `i18n/locale/{en,pt_BR}/ramon.json` | gatilho `nota_escrita`, 5 rotinas |
| `spec/…` | `migracao_spec`, `disparo_spec`, `ramon_fluxo_listener_spec`, `ramon_lead_listener_spec`, `ramon_agente_listener_spec`, `rotinas/leads_spec` (novo); front `specs/migrados.spec.js` |
| N1: `sistema/etiquetas_etapa_tese.json` (A) **ou** a Task 6B inteira (B) | etiquetas |
| `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` | seção "Notas da B5-leads" |

---

### Task 0: Alinhar com o B5-conta (rebase, registro de rotinas, regra fixa, baselines) — **exige julgamento**

**Files:** nenhum arquivo de código. Sem commit (salvo ajuste deste plano).

**Interfaces:**
- Produces: o **nome real** do registro de rotinas e do selo "regra fixa" do B5-conta (anotar aqui e aplicar nas Tasks 3 e 6); o baseline **B** do Vitest; os tamanhos atuais.

- [ ] **Step 1: O B5-conta está em `origin/ramon`?**

```bash
git fetch origin
git log --oneline origin/ramon -10
```
Expected: o merge do B5-conta acima de `0a31e02`. **Se não estiver: pare e avise** (esta fatia depende do registro de rotinas dele).

- [ ] **Step 2: Rebase**

```bash
git status --short          # só vitest.local.config.ts (fora do git) pode aparecer
git rebase origin/ramon     # a branch só tem o commit deste plano
```
Expected: sem conflito.

- [ ] **Step 3: Ler o formato do B5-conta**

```bash
ls app/services/ramon/fluxos/rotinas/ app/services/ramon/fluxos/
sed -n 1,80p app/services/ramon/fluxos/passos/rotina.rb
grep -rn "MODULOS\|regra_fixa\|def self.modulo\|def decidir" app/services/ramon/fluxos lib db/seeds/ramon/fluxos/sistema | head -30
grep -n "ROTINAS" app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js
```
Anote: (a) como o `Passos::Rotina` acha um módulo de rotinas (o formato assumido está nas Global Constraints); (b) se o `Passos::Rotina` ainda chama `exigir_lead` **antes** de despachar para os módulos (se sim, as rotinas de conversa desta fatia não funcionam — avise o controlador); (c) como o selo "regra fixa" é marcado no JSON do sistema e onde a lista das regras fixas é conferida nos specs; (d) se o B5-conta já trouxe um ajudante equivalente a `Migracao.decidir` — **se sim, use o dele** e pule o Step 3 da Task 1 (ajuste os nomes em todas as tasks).

- [ ] **Step 4: Baselines**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts
for f in app/services/ramon/fluxos/migracao.rb app/services/ramon/fluxos/disparo.rb app/listeners/ramon_lead_listener.rb app/services/ramon/fluxos/passos/rotina.rb; do echo "$f $(grep -cvE '^\s*(#|$)' $f)"; done
```
Expected: Vitest verde — anote arquivos/testes como **B**. Se `migracao.rb` passar de **88** linhas de código, os 5 grupos + `decidir` (~12) estouram o limite de 100: pare e avise.

---

### Task 1: Motor — `decidir`, os 5 grupos, `migracao` no Disparo, gatilho "Nota privada escrita" — **mecânica**

**Files:**
- Modify: `app/services/ramon/fluxos/migracao.rb` (fim de `GRUPOS`; `decidir` no fim do módulo)
- Modify: `app/services/ramon/fluxos/disparo.rb` (`NA_HORA_CHAVES`, `DUAS_VEZES`, `da_vez?`, `na_hora?`)
- Modify: `app/services/ramon/fluxos/grafo.rb` (`GATILHOS`)
- Modify: `app/listeners/ramon_fluxo_listener.rb` (`message_created`)
- Modify: `.env.example`
- Test: `spec/services/ramon/fluxos/migracao_spec.rb`, `spec/services/ramon/fluxos/disparo_spec.rb`, `spec/listeners/ramon_fluxo_listener_spec.rb`

**Interfaces:**
- Produces: `Ramon::Fluxos::Migracao.decidir(nome, gatilho, alvo, dados = {}) { código }` → roda o bloco `unless assumido && feitas.any?`; manda `'assumido'` e `'migracao' => nome` no gatilho. Grupos `criar_lead`, `origem_lead`, `sugestao_doc`, `coach`, `agente` (chaves `criar_lead_da_conversa`, `origem_do_lead`, `sugestao_documento`, `coach_objecao`, `agente_hub`). `Ramon::Fluxos::Disparo::NA_HORA_CHAVES = %w[criar_lead_da_conversa origem_do_lead]`. Gatilho `nota_escrita` (alvo conversa; dados `texto`, `mensagem_id`, `caixa_id`). `mensagem_recebida` passa a levar `mensagem_id`.

- [ ] **Step 1: Specs que falham**

Em `spec/services/ramon/fluxos/migracao_spec.rb`, antes do `end` final:

```ruby
  it 'leads e conversas (B5-leads): 5 migrações, cada uma com a sua chave e o seu gatilho' do
    esperado = {
      'criar_lead' => ['RAMON_FLUXO_CRIAR_LEAD', { 'criar_lead_da_conversa' => 'conversa_criada' }],
      'origem_lead' => ['RAMON_FLUXO_ORIGEM_LEAD', { 'origem_do_lead' => 'mensagem_recebida' }],
      'sugestao_doc' => ['RAMON_FLUXO_SUGESTAO_DOC', { 'sugestao_documento' => 'mensagem_recebida' }],
      'coach' => ['RAMON_FLUXO_COACH', { 'coach_objecao' => 'mensagem_recebida' }],
      'agente' => ['RAMON_FLUXO_AGENTE', { 'agente_hub' => 'nota_escrita' }]
    }
    expect(esperado.keys.to_h { |g| [g, [described_class.grupo(g)[:env], described_class.gatilhos(g)]] }).to eq(esperado)
  end

  describe '.decidir (B5-leads): a decisão do evento, lida uma vez, com reserva' do
    let(:conversa) { create(:conversation, account: account) }
    let(:fluxo) do
      fluxo_publicado(account, grafo_linear({ 'tipo' => 'mensagem_recebida' }, ['parar', {}]), sistema_chave: 'coach_objecao', modo: 'normal')
    end

    it 'código no comando (chave desligada): o bloco roda e o fluxo do grupo só ensaia' do
      fluxo
      expect { |b| described_class.decidir('coach', 'mensagem_recebida', conversa, {}, &b) }.to yield_control.once
      expect(fluxo.execucoes.sole.ensaio).to be(true)
    end

    it 'fluxo no comando que pegou o evento: o bloco não roda (nunca em dobro)' do
      fluxo
      with_modified_env(RAMON_FLUXO_COACH: 'on') do
        expect { |b| described_class.decidir('coach', 'mensagem_recebida', conversa, {}, &b) }.not_to yield_control
      end
      expect(fluxo.execucoes.sole.ensaio).to be(false)
    end

    it 'fluxo no comando que NÃO pegou o evento (ocupado com a mesma conversa): o bloco roda (reserva, nunca nenhum)' do
      fluxo.execucoes.create!(account: account, alvo: conversa, status: 'esperando', retomar_em: 5.minutes.from_now)
      with_modified_env(RAMON_FLUXO_COACH: 'on') do
        expect { |b| described_class.decidir('coach', 'mensagem_recebida', conversa, {}, &b) }.to yield_control.once
      end
      expect(fluxo.execucoes.count).to eq(1)
    end

    it 'motor com erro: o bloco roda (o Disparo.externo engole o erro e devolve [])' do
      allow(Ramon::Fluxos::Disparo).to receive(:call).and_raise(StandardError, 'motor')
      with_modified_env(RAMON_FLUXO_COACH: 'on') do
        fluxo
        expect { |b| described_class.decidir('coach', 'mensagem_recebida', conversa, {}, &b) }.to yield_control.once
      end
    end
  end
```

Em `spec/services/ramon/fluxos/disparo_spec.rb`, antes do `end` final:

```ruby
  it 'B5-leads: dois grupos migrados no mesmo gatilho — cada decisão só inicia o fluxo do seu grupo' do
    sla = fluxo_publicado(account, grafo_linear({ 'tipo' => 'conversa_criada' }, nota), sistema_chave: 'sla_primeira_resposta')
    criar = fluxo_publicado(account, grafo_linear({ 'tipo' => 'conversa_criada' }, nota), sistema_chave: 'criar_lead_da_conversa')
    comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'conversa_criada' }, nota))
    expect(described_class.call('conversa_criada', conversa, { 'assumido' => false, 'migracao' => 'sla' }).map(&:fluxo)).to eq([sla])
    expect(described_class.call('conversa_criada', conversa, { 'assumido' => false, 'migracao' => 'criar_lead' }).map(&:fluxo)).to eq([criar])
    expect(described_class.call('conversa_criada', conversa, { 'caixa_id' => conversa.inbox_id }).map(&:fluxo)).to eq([comum])
  end

  it 'B5-leads: criar lead e origem migrados rodam na hora (dentro do ouvinte); coach, documento e SLA seguem pelo job' do
    origem = fluxo_publicado(account, grafo_linear({ 'tipo' => 'mensagem_recebida' }, nota), sistema_chave: 'origem_do_lead')
    coach = fluxo_publicado(account, grafo_linear({ 'tipo' => 'mensagem_recebida' }, nota), sistema_chave: 'coach_objecao')
    described_class.call('mensagem_recebida', conversa, { 'assumido' => true, 'migracao' => 'origem_lead' })
    expect { described_class.call('mensagem_recebida', conversa, { 'assumido' => true, 'migracao' => 'coach' }) }
      .to have_enqueued_job(Ramon::FluxoAvancarJob)
    expect([origem.execucoes.sole.status, coach.execucoes.sole.status]).to eq(%w[concluida esperando])
  end

  it 'B5-leads: nota privada escrita dispara 2 vezes — com a decisão só o migrado; sem, só os comuns' do
    migrado = fluxo_publicado(account, grafo_linear({ 'tipo' => 'nota_escrita' }, nota), sistema_chave: 'agente_hub')
    comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'nota_escrita' }, nota))
    expect(described_class.call('nota_escrita', conversa, { 'assumido' => true, 'migracao' => 'agente' }).map(&:fluxo)).to eq([migrado])
    expect(described_class.call('nota_escrita', conversa, { 'texto' => 'oi' }).map(&:fluxo)).to eq([comum])
  end
```

Em `spec/listeners/ramon_fluxo_listener_spec.rb`, **substituir** o exemplo `'mensagem recebida dispara com o texto; nota privada não'` inteiro por:

```ruby
  it 'mensagem recebida dispara com o texto e a mensagem (B5-leads: as rotinas leem a mensagem pelo id)' do
    msg = create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :incoming, content: 'oi')
    expect(Ramon::Fluxos::Disparo).to receive(:call)
      .with('mensagem_recebida', conversa, hash_including('texto' => 'oi', 'mensagem_id' => msg.id, 'caixa_id' => conversa.inbox_id), origem: nil)
    listener.message_created(evento('message.created', message: msg))
  end

  it 'nota privada de alguém da equipe dispara nota_escrita (B5-leads); a nota sem autor (a dos fluxos), nada' do
    nota = create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :outgoing, private: true,
                            content: '@claude oi')
    expect(Ramon::Fluxos::Disparo).to receive(:call)
      .with('nota_escrita', conversa, hash_including('texto' => '@claude oi', 'mensagem_id' => nota.id), origem: nil)
    listener.message_created(evento('message.created', message: nota))

    do_fluxo = create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :outgoing, private: true)
    do_fluxo.sender = nil # a fábrica põe um User em toda outgoing; nota de fluxo nasce sem autor (Passos::Conversa#escrever)
    expect(Ramon::Fluxos::Disparo).not_to receive(:call)
    listener.message_created(evento('message.created', message: do_fluxo))
  end
```

- [ ] **Step 2: Rodar — falham** (CI; sem Ruby local). Esperado: `ArgumentError: Migração desconhecida: criar_lead`, `undefined method 'decidir'`, `Gatilho desconhecido: nota_escrita` (no `publicar!`), `mensagem_id` ausente.

- [ ] **Step 3: `migracao.rb`** — no fim de `GRUPOS` (depois do último grupo que estiver lá — o do B5-conta, se ele acrescentou), uma vírgula no grupo anterior e:

```ruby
    # B5-leads: leads e conversas — o ouvinte (RamonLeadListener / RamonAgenteListener) decide por Migracao.decidir, com reserva.
    'criar_lead' => { env: 'RAMON_FLUXO_CRIAR_LEAD', faz: 'a criação do lead', fluxos: { 'criar_lead_da_conversa' => 'conversa_criada' }.freeze },
    'origem_lead' => { env: 'RAMON_FLUXO_ORIGEM_LEAD', faz: 'a origem do lead', fluxos: { 'origem_do_lead' => 'mensagem_recebida' }.freeze },
    'sugestao_doc' => { env: 'RAMON_FLUXO_SUGESTAO_DOC', faz: 'a sugestão de documento',
                        fluxos: { 'sugestao_documento' => 'mensagem_recebida' }.freeze },
    'coach' => { env: 'RAMON_FLUXO_COACH', faz: 'o coach de objeção', fluxos: { 'coach_objecao' => 'mensagem_recebida' }.freeze },
    'agente' => { env: 'RAMON_FLUXO_AGENTE', faz: 'o aviso ao agente do hub', fluxos: { 'agente_hub' => 'nota_escrita' }.freeze }
```

E no fim do módulo (antes do `end` final, depois de `com_etapa`):

```ruby
  # B5-leads: a decisão de um evento, lida UMA vez — dispara os fluxos migrados do grupo com 'assumido' (só eles ouvem;
  # 'migracao' separa grupos que dividem o gatilho) e roda o código (o bloco) se o fluxo não está no comando OU não pegou
  # este evento (reserva: ocupado com o mesmo alvo, filtro editado, erro do motor). Nunca em dobro, nunca nenhum.
  def decidir(nome, gatilho, alvo, dados = {})
    assumido = assumiu?(alvo.account, nome)
    feitas = Ramon::Fluxos::Disparo.externo(gatilho, alvo, dados.merge('assumido' => assumido, 'migracao' => nome))
    yield unless assumido && feitas.any?
  end
```

- [ ] **Step 4: `disparo.rb`** — depois de `NA_HORA = …` acrescentar:

```ruby
  # B5-leads: fluxos migrados que rodam na hora pela CHAVE do fluxo (não pelo gatilho — o SLA, o coach e a sugestão de
  # documento dividem os gatilhos e seguem pelo job): o lead criado e a origem gravada precisam existir antes do SLA e
  # dos fluxos comuns do mesmo evento — a ordem de sempre.
  NA_HORA_CHAVES = %w[criar_lead_da_conversa origem_do_lead].freeze
```

Trocar a linha do `DUAS_VEZES` (acrescentando no fim e atualizando o comentário de cima — acrescente ao comentário: `# B5-leads: mensagem_recebida (origem, documento, coach) e nota_escrita (agente); 'migracao' no evento separa os grupos.`):

```ruby
  DUAS_VEZES = (NA_HORA + %w[conversa_criada lead_ganho mensagem_recebida nota_escrita]).freeze
```

Trocar `self.da_vez?` (e o comentário dele) por:

```ruby
  # Nos gatilhos DUAS_VEZES: com 'assumido' só os migrados (B5: do grupo que decidiu, quando o evento diz 'migracao' — vários
  # grupos dividem conversa_criada e mensagem_recebida); sem, só os demais. Em reuniao_marcada/cancelada o disparo com
  # 'assumido' vem antes dos efeitos do código (o ensaio vê o lead como estava).
  def self.da_vez?(fluxo, dados)
    return true if DUAS_VEZES.exclude?(fluxo.gatilho_tipo)
    return !dados.key?('assumido') unless Ramon::Fluxos::Migracao.migrado?(fluxo)

    dados.key?('assumido') && (dados['migracao'].nil? || Ramon::Fluxos::Migracao.gatilhos(dados['migracao']).key?(fluxo.sistema_chave))
  end
```

Trocar `na_hora?` por:

```ruby
  def na_hora?
    (NA_HORA.include?(@fluxo.gatilho_tipo) || NA_HORA_CHAVES.include?(@fluxo.sistema_chave)) && Ramon::Fluxos::Migracao.migrado?(@fluxo)
  end
```

- [ ] **Step 5: `grafo.rb`** — `GATILHOS`: acrescentar `nota_escrita` no fim da lista (`… contrato_assinado contrato_recusado documento_recebido nota_escrita].freeze`, ou depois do que o B5-conta pôs no fim).

- [ ] **Step 6: `ramon_fluxo_listener.rb`** — trocar `message_created` por:

```ruby
  # Mensagem do cliente → mensagem_recebida; nota privada de alguém da equipe (B5-leads) → nota_escrita. Notas escritas
  # pelos fluxos não têm autor (Passos::Conversa#escrever) e não disparam nada. mensagem_id: as rotinas prontas leem a mensagem.
  def message_created(event)
    message = event.data[:message]
    dados = { 'texto' => message.content.to_s.truncate(500), 'mensagem_id' => message.id }
    if message.incoming? && !message.private?
      disparar('mensagem_recebida', message.conversation, event, dados)
    elsif message.private? && message.sender.is_a?(User)
      disparar('nota_escrita', message.conversation, event, dados)
    end
  end
```

- [ ] **Step 7: `.env.example`** — depois da linha `# RAMON_FLUXO_EVENTOS_ADVBOX=off` (ou do último bloco `RAMON_FLUXO_*` que o B5-conta deixou), uma linha em branco e:

```
# ramon: leads e conversas pelos fluxos (B5-leads), uma chave por automacao. on + o fluxo dela em modo normal = o fluxo
# faz e o codigo para (com reserva: fluxo que nao pega o evento devolve aquele evento ao codigo). Padrao desligado.
# Virar/voltar: rake ramon:fluxos:migracao:modo[grupo,conta,normal|sombra] - grupos criar_lead, origem_lead, sugestao_doc, coach, agente
# RAMON_FLUXO_CRIAR_LEAD=off
# RAMON_FLUXO_ORIGEM_LEAD=off
# RAMON_FLUXO_SUGESTAO_DOC=off
# RAMON_FLUXO_COACH=off
# RAMON_FLUXO_AGENTE=off
```

- [ ] **Step 8: Rastrear à mão** (sem Ruby local): (a) os exemplos antigos do `disparo_spec` com `reuniao_*`, `lead_ganho`, `evento_advbox` não mandam `'migracao'` → `da_vez?` cai no `dados['migracao'].nil?` → igual a antes; (b) "rajada no mesmo alvo" usa fluxo comum de `mensagem_recebida` sem `assumido` → `!dados.key?('assumido')` → true, igual; (c) o spec do SLA (B4.2) no `ramon_lead_listener_spec` ainda chama o `Disparo.externo` sem `'migracao'` até a Task 2 — continua verde aqui. Contar linhas: `grep -cvE '^\s*(#|$)' app/services/ramon/fluxos/migracao.rb` ≤ 100.

- [ ] **Step 9: Commit**

```bash
git add app/services/ramon/fluxos/migracao.rb app/services/ramon/fluxos/disparo.rb app/services/ramon/fluxos/grafo.rb app/listeners/ramon_fluxo_listener.rb .env.example spec/services/ramon/fluxos/migracao_spec.rb spec/services/ramon/fluxos/disparo_spec.rb spec/listeners/ramon_fluxo_listener_spec.rb
git commit -m "feat(fluxos): decisão por evento com grupo, 5 chaves de leads/conversas e gatilho Nota privada escrita (B5-leads)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 2: O código de hoje muda de arquivo e os ouvintes passam a decidir (comportamento igual) — **mecânica**

**Files:**
- Create: `app/services/ramon/lead_da_conversa.rb`
- Modify: `app/jobs/ramon/agente_notify_job.rb` (`self.chamado?`)
- Modify: `app/listeners/ramon_lead_listener.rb`
- Modify: `app/listeners/ramon_agente_listener.rb`
- Test: `spec/listeners/ramon_lead_listener_spec.rb` (todos os exemplos de hoje continuam; +1 describe)

**Interfaces:**
- Consumes: `Ramon::Fluxos::Migracao.decidir` (Task 1).
- Produces: `Ramon::LeadDaConversa.cabe?(conversation) → bool`, `.criar_ou_ligar(conversation) → Lead` (o lead tem `previously_new_record?` true se criado), `.origem_pendente?(lead, message) → bool`, `.origem(lead, message)`; `Ramon::AgenteNotifyJob.chamado?(message) → bool`. No `ramon_lead_listener_spec.rb`: o describe `'leads e conversas — código ou fluxo (B5-leads)'` com os ajudantes `publicar`, `gravar_disparos`, `lead_da_conversa`, `mensagem`, `assumir` e o `let(:anuncio)` (a Task 4 acrescenta exemplos dentro dele).

- [ ] **Step 1: Spec — a ordem de hoje, provada pelo despachante real** (no fim de `spec/listeners/ramon_lead_listener_spec.rb`, antes do `end` final):

```ruby
  describe 'leads e conversas — código ou fluxo (B5-leads)' do
    # Chaves ligadas: sem os fluxos em modo normal, o código segue no comando (a chave é env + fluxo).
    around do |ex|
      with_modified_env(RAMON_FLUXO_CRIAR_LEAD: 'on', RAMON_FLUXO_ORIGEM_LEAD: 'on', RAMON_FLUXO_SUGESTAO_DOC: 'on', RAMON_FLUXO_COACH: 'on') { ex.run }
    end

    let(:anuncio) { { 'source_id' => '12034', 'headline' => 'Machucou no trabalho?' } }

    # Os ouvintes do hub na ordem REAL do AsyncDispatcher (os nativos não mexem em lead nem em fluxo).
    def publicar(nome, dados)
      ev = Events::Base.new(nome, Time.zone.now, dados)
      AsyncDispatcher.new.listeners.select { |l| l.class.name.start_with?('Ramon') }
                     .each { |l| l.public_send(ev.method_name, ev) if l.respond_to?(ev.method_name) }
    end

    # Cada disparo de fluxo, na ordem: [gatilho, grupo que decidiu (nil = os fluxos comuns), o que `olhar` vê naquela hora].
    def gravar_disparos(&olhar)
      disparos = []
      allow(Ramon::Fluxos::Disparo).to receive(:call).and_wrap_original do |original, gatilho, alvo, dados = {}, **opcoes|
        disparos << [gatilho, dados['migracao'], olhar.call]
        original.call(gatilho, alvo, dados, **opcoes)
      end
      disparos
    end

    def lead_da_conversa = account.leads.find_by(conversation_id: conversation.id)

    def mensagem(conteudo, *traits, **attrs)
      create(:message, *traits, account: account, conversation: conversation, message_type: :incoming, content: conteudo, **attrs)
    end

    # Cria os fluxos do grupo e põe no comando (a env já está ligada no around).
    def assumir(grupo)
      Ramon::Fluxos::Migracao.semear(account, grupo)
      Ramon::Fluxos::Migracao.mudar_modo!(account, grupo, 'normal').first
    end

    it 'código no comando: o lead nasce antes do SLA e dos fluxos comuns de Conversa nova; lead.created sai 1 vez' do
      disparos = gravar_disparos { lead_da_conversa.present? }
      expect { publicar('conversation.created', conversation: conversation) }
        .to have_enqueued_job(Ramon::FirstResponseSlaJob).with(conversation.id)
        .and have_enqueued_job(EventDispatcherJob).with('lead.created', anything, anything).exactly(:once)
      expect(disparos).to eq([['conversa_criada', 'criar_lead', false], ['conversa_criada', 'sla', true], ['conversa_criada', nil, true]])
    end

    it 'código no comando: a origem é gravada antes dos fluxos comuns de Mensagem recebida' do
      create(:lead, account: account, contact: contact, conversation: conversation, channel: 'outro', source: nil)
      disparos = gravar_disparos { lead_da_conversa.source }
      publicar('message.created', message: mensagem('oi', content_attributes: { referral: anuncio }))
      expect(disparos).to eq([['mensagem_recebida', 'origem_lead', nil], ['mensagem_recebida', nil, 'anuncio-meta: 12034']])
    end

    it 'sem nada a anotar (canal já derivado, sem anúncio), a origem nem é decidida — só os fluxos comuns' do
      create(:lead, account: account, contact: contact, conversation: conversation, channel: 'landing_page', source: 'auxilio-acidente')
      disparos = gravar_disparos { nil }
      publicar('message.created', message: mensagem('oi'))
      expect(disparos).to eq([['mensagem_recebida', nil, nil]])
    end
  end
```

(O `assumir` só é usado na Task 4; fica aqui para os ajudantes morarem num lugar só.)

- [ ] **Step 2: Rodar — falham** (CI): o 1º disparo hoje não tem `'migracao'` (`[['conversa_criada', nil, true], …]` — e o lead já existe nele, porque o SLA é o 1º disparo); a origem hoje não passa pelo Disparo.

- [ ] **Step 3: `app/services/ramon/lead_da_conversa.rb`** (novo — o código do ouvinte, sem mudar nada):

```ruby
# frozen_string_literal: true

# Criar lead da conversa e origem do lead — o código de sempre, que morava no RamonLeadListener (mudou de arquivo na
# B5-leads, sem mudar nada). Quem chama: o ouvinte (código no comando, ou a reserva) e as rotinas prontas criar_lead /
# origem_do_lead (Ramon::Fluxos::Rotinas::Leads), quando o fluxo migrado está no comando.
module Ramon::LeadDaConversa
  module_function

  # Só caixas com "Criar lead" ligado e conversa com contato.
  def cabe?(conversation) = conversation.inbox&.auto_create_lead? && conversation.contact.present?

  # Liga a conversa ao lead aberto do mesmo contato (pessoa ≠ caso: lead fechado não conta) ou cria o lead na 1ª etapa.
  def criar_ou_ligar(conversation)
    account = conversation.account
    contact = conversation.contact
    lead = account.leads.open.find_by(contact_id: contact.id)
    return lead.tap { |l| l.update!(conversation_id: conversation.id) } if lead

    account.leads.create!(
      name: contact.name.presence || contact.phone_number || contact.identifier,
      lead_stage: account.lead_stages.order(:position).first,
      contact_id: contact.id,
      conversation_id: conversation.id
    )
  end

  # Há o que anotar? Anúncio da Meta na mensagem, ou canal ainda não derivado ('outro'). Sem isso o código não faz nada —
  # e o fluxo de origem nem começa (1 execução por lead, não por mensagem).
  def origem_pendente?(lead, message) = referral_da(message).present? || lead.channel == 'outro'

  def origem(lead, message)
    apply_meta_referral(lead, message)
    derive_channel_from_first_contact(lead, message)
  end

  def referral_da(message) = message.content_attributes.with_indifferent_access[:referral]

  # Atribuição: o referral da Meta (click-to-WhatsApp) chega na primeira mensagem, depois do conversation_created.
  def apply_meta_referral(lead, message)
    referral = referral_da(message)
    return if referral.blank?

    meta = referral.slice('source_id', 'source_type', 'source_url', 'headline', 'ctwa_clid').compact_blank
    attrs = { custom_attributes: lead.custom_attributes.merge('meta_referral' => meta) }
    if lead.source.blank?
      attrs[:source] = referral_source_label(referral)
      attrs[:channel] = 'meta_ads'
    end
    lead.update!(attrs)
  end

  def referral_source_label(referral)
    detail = referral['source_id'].presence || referral['headline'].presence
    ['anuncio-meta', detail].compact.join(': ').truncate(255)
  end

  # Regra de negócio (13/08, design funil-estrategico): nos números da banca, quem chega sem anúncio e sem assinatura de
  # site/LP/bio veio por indicação. 'outro' é o sentinela de "não derivado" — canal manual ou já derivado (landing_page,
  # meta_ads) nunca é sobrescrito.
  def derive_channel_from_first_contact(lead, message)
    return unless lead.channel == 'outro'

    channel, source = Ramon::SourceCatalog.derive_from_message(message.content)
    channel ||= message.inbox&.channel_type == 'Channel::Instagram' ? 'instagram' : 'indicacao'
    attrs = { channel: channel }
    attrs[:source] = source if source.present? && lead.source.blank?
    lead.update!(attrs)
  end
end
```

- [ ] **Step 4: `app/jobs/ramon/agente_notify_job.rb`** — dentro da classe, antes de `def perform`:

```ruby
  # Quem chama o agente — a trava de sempre, num lugar só (RamonAgenteListener e a rotina agente_hub; a tela não a edita):
  # nota privada começando com "@claude", escrita pelo Eduardo (RAMON_AGENTE_EDUARDO_EMAIL), com o runner configurado.
  def self.chamado?(message)
    message.private? && message.content.to_s.lstrip.downcase.start_with?('@claude') &&
      ENV.fetch('RAMON_AGENTE_RUNNER_URL', nil).present? &&
      message.sender.is_a?(User) && message.sender.email.casecmp?(ENV.fetch('RAMON_AGENTE_EDUARDO_EMAIL', ''))
  end
```

- [ ] **Step 5: `app/listeners/ramon_agente_listener.rb`** — o arquivo inteiro:

```ruby
# frozen_string_literal: true

# Gatilho do agente do hub: nota privada começando com "@claude", escrita pelo Eduardo (Ramon::AgenteNotifyJob.chamado?).
# Webhook nativo não serve (Message#webhook_sendable? descarta private). B5-leads: a nota decide UMA vez entre o código
# (o job de sempre) e o fluxo migrado "Agente do hub" (gatilho Nota privada escrita), com reserva.
class RamonAgenteListener < BaseListener
  def message_created(event)
    message = event.data[:message]
    return unless Ramon::AgenteNotifyJob.chamado?(message)

    conversa = message.conversation
    dados = { 'caixa_id' => conversa.inbox_id, 'mensagem_id' => message.id, 'texto' => message.content.to_s.truncate(500) }
    Ramon::Fluxos::Migracao.decidir('agente', 'nota_escrita', conversa, dados) { Ramon::AgenteNotifyJob.perform_later(message.id) }
  end
end
```

- [ ] **Step 6: `app/listeners/ramon_lead_listener.rb`** — trocar o comentário de topo, `conversation_created`, `message_created` e a seção `private` inteira (os métodos `apply_meta_referral`, `referral_source_label`, `derive_channel_from_first_contact` e `enqueue_first_response_sla` saem daqui). `lead_created`, `lead_updated` e `conversation_updated` **não mudam**. Resultado:

```ruby
# frozen_string_literal: true

# Leads e conversas. B5-leads: cada efeito decide UMA vez, por evento, entre o código de sempre e o fluxo migrado
# (Ramon::Fluxos::Migracao.decidir — com reserva: fluxo no comando que não pega o evento devolve aquele evento ao código).
# A ordem é a de sempre (spec: "leads e conversas — código ou fluxo"): o lead nasce ANTES do SLA e dos fluxos comuns de
# Conversa nova; a origem é gravada ANTES dos fluxos comuns de Mensagem recebida — os migrados de criar lead e de origem
# rodam na hora (Disparo::NA_HORA_CHAVES) e o RamonFluxoListener vem depois deste no AsyncDispatcher.
class RamonLeadListener < BaseListener
  TIPOS_ANEXO = %w[image file].freeze # anexo que a IA tenta casar com o checklist

  def conversation_created(event)
    conversation = event.data[:conversation]
    return unless Ramon::LeadDaConversa.cabe?(conversation)

    dados = { 'caixa_id' => conversation.inbox_id }
    decidir('criar_lead', 'conversa_criada', conversation, dados) { Ramon::LeadDaConversa.criar_ou_ligar(conversation) }
    # SLA da 1ª resposta (mapa comercial): o vigia dispara N min depois (SLA da caixa, senão o env) e só apita se a conversa
    # seguir aberta e sem resposta. B4.2: com o fluxo "SLA da 1ª resposta" no comando e vigiando a conversa, o job não é agendado.
    decidir('sla', 'conversa_criada', conversation, dados) do
      Ramon::FirstResponseSlaJob.set(wait: Ramon::Cadencia.sla_minutes(conversation.inbox).minutes).perform_later(conversation.id)
    end
  end

  def message_created(event)
    message = event.data[:message]
    return unless message.incoming?

    lead = message.account.leads.find_by(conversation_id: message.conversation_id)
    efeitos_da_mensagem(lead, message) if lead
  end

  # (lead_created, lead_updated e conversation_updated: exatamente como estão)

  private

  def decidir(grupo, gatilho, alvo, dados, &) = Ramon::Fluxos::Migracao.decidir(grupo, gatilho, alvo, dados, &)

  # Mensagem do cliente numa conversa com lead, na ordem de sempre: origem (na hora) → sugestão de documento (anexo) →
  # coach de objeção (texto com 20+ caracteres). Colheita NÃO é automática (decisão 20/07).
  def efeitos_da_mensagem(lead, message)
    conversa = message.conversation
    dados = dados_da_mensagem(message)
    if Ramon::LeadDaConversa.origem_pendente?(lead, message)
      decidir('origem_lead', 'mensagem_recebida', conversa, dados) { Ramon::LeadDaConversa.origem(lead, message) }
    end
    if message.attachments.any? { |a| TIPOS_ANEXO.include?(a.file_type) }
      decidir('sugestao_doc', 'mensagem_recebida', conversa, dados) { Ramon::DocMatchJob.perform_later(message.id) }
    end
    return if message.content.to_s.strip.length < Ramon::CoachObjecaoService::MIN_CHARS

    decidir('coach', 'mensagem_recebida', conversa, dados) { Ramon::CoachObjecaoJob.perform_later(message.id) }
  end

  def dados_da_mensagem(message)
    { 'caixa_id' => message.conversation.inbox_id, 'mensagem_id' => message.id, 'texto' => message.content.to_s.truncate(500) }
  end
end
```

(Os 3 métodos `lead_created`, `lead_updated`, `conversation_updated` ficam entre `message_created` e `private`, copiados sem mudança.)

- [ ] **Step 7: Rastrear à mão os exemplos de hoje** (`ramon_lead_listener_spec.rb` e `ramon_agente_listener_spec.rb`, sem mudança): criar/não criar/re-apontar/lead novo com leads fechados → `cabe?` + `criar_ou_ligar` (mesmo código); referral/não sobrescreve/ignora sem referral/canais → `origem_pendente?` + `origem` (sem chave → `decidir` roda o bloco); `DocMatchJob`/`CoachObjecaoJob` enfileirados (ou não) igual; `lead_updated`/`conversation_updated` intocados; SLA B4.2 → `decidir('sla', …)` faz exatamente o `return if externo(...).any? && assumido` de antes (o exemplo "o ouvinte geral não inicia o fluxo do SLA" segue com 1 execução em cada); agente → `chamado?` igual à guarda antiga (m1 pública, m2 sem @claude, m3 de outro → nada).

- [ ] **Step 8: Commit**

```bash
git add app/services/ramon/lead_da_conversa.rb app/jobs/ramon/agente_notify_job.rb app/listeners/ramon_lead_listener.rb app/listeners/ramon_agente_listener.rb spec/listeners/ramon_lead_listener_spec.rb
git commit -m "refactor(fluxos): criar lead, origem e agente decidem por evento — código mudado de arquivo, mesma ordem (B5-leads)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 3: Rotinas prontas de leads e conversas — **exige julgamento (casca do registro do B5-conta)**

**Files:**
- Create: `app/services/ramon/fluxos/rotinas/leads.rb`
- Modify: o registro do B5-conta (assumido: `Ramon::Fluxos::Rotinas::MODULOS` — acrescentar `Ramon::Fluxos::Rotinas::Leads` **no fim**)
- Test: `spec/services/ramon/fluxos/rotinas/leads_spec.rb` (novo)

**Interfaces:**
- Consumes: `Ramon::LeadDaConversa` e `Ramon::AgenteNotifyJob.chamado?` (Task 2); `Contexto#gatilho('mensagem_id')`, `#conversa`, `#lead`, `#ensaio?`, `#execucao`; `Ramon::Fluxos::Executor::ESPERAS_ERRO`; o registro do B5-conta.
- Produces: rotinas `criar_lead`, `origem_do_lead`, `sugestao_documento`, `coach_objecao`, `agente_hub` (nomes usados nos JSON da Task 4 e no front da Task 5). Resumos exatos (os specs das Tasks 3–4 conferem):
  - ensaio: `'faria: criar o lead na 1ª etapa do funil (ou ligar a conversa ao lead aberto do contato)'`, `'faria: anotar a origem e o canal do lead (anúncio da Meta, site/LP/bio, instagram ou indicação)'`, `'faria: a IA compara o anexo com o checklist da tese e sugere o documento (a equipe confirma)'`, `'faria: o coach procura objeção na mensagem e sugere 2 respostas do playbook da tese'`, `'faria: avisar o agente do hub na VPS (só nota @claude do Eduardo)'`
  - de verdade: `"lead criado: #{nome} (#{etapa})"` / `"conversa ligada ao lead aberto: #{nome} (#{etapa})"` (com balão); `'a caixa não cria lead (ou a conversa não tem contato): nada feito'`; `"origem do lead: canal #{canal}, origem #{origem}"` (sem `, origem …` se vazia); `'a IA sugeriu um documento do checklist (a equipe confirma no painel)'` / `'a IA não reconheceu o anexo no checklist pendente'`; `"sugestão de documento: desistiu depois de 4 tentativas (TransientError)"`; `'coach de objeção: leu a mensagem (havendo objeção, as 2 respostas aparecem no balão do coach)'`; `'avisou o agente do hub (a resposta chega como nota privada)'` / `'não é nota @claude do Eduardo: o agente não foi chamado'`. Todas sem balão (`sem_balao: true`) exceto criar/ligar o lead (N3=A).

- [ ] **Step 1: Spec que falha** — `spec/services/ramon/fluxos/rotinas/leads_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Rotinas::Leads do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, auto_create_lead: true) }
  let(:contact) { create(:contact, account: account, name: 'Maria') }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' })) }

  def llm(conteudo) = Ramon::LlmClient::Result.new(content: conteudo, input_tokens: 1, output_tokens: 1)

  # Pelo passo de verdade (Passos::Rotina → registro do B5-conta → este módulo). Execução de verdade: 1 por exemplo.
  def rodar(rotina, mensagem: nil, ensaio: false, tentativas: 0)
    gatilho = mensagem ? { 'mensagem_id' => mensagem.id } : {}
    execucao = fluxo.execucoes.create!(account: account, alvo: conversa, ensaio: ensaio, tentativas: tentativas,
                                       contexto: { 'gatilho' => gatilho })
    Ramon::Fluxos::Passos::Rotina.rotina({ 'rotina' => rotina }, Ramon::Fluxos::Contexto.new(execucao))
  end

  describe 'criar_lead' do
    it 'ensaio só descreve; de verdade cria o lead na 1ª etapa (com balão: 1 por conversa nova)' do
      expect(rodar('criar_lead', ensaio: true)[:resumo])
        .to eq('faria: criar o lead na 1ª etapa do funil (ou ligar a conversa ao lead aberto do contato)')
      expect(account.leads.count).to eq(0)
      expect(rodar('criar_lead')).to eq(saida: 's', resumo: 'lead criado: Maria (Novo)')
      expect(account.leads.sole).to have_attributes(contact_id: contact.id, conversation_id: conversa.id)
    end

    it 'caixa sem "Criar lead": nada feito, sem balão' do
      inbox.update!(auto_create_lead: false)
      expect(rodar('criar_lead')).to eq(saida: 's', resumo: 'a caixa não cria lead (ou a conversa não tem contato): nada feito', sem_balao: true)
      expect(account.leads.count).to eq(0)
    end
  end

  describe 'origem_do_lead' do
    let!(:lead) { create(:lead, account: account, contact: contact, conversation: conversa, channel: 'outro', source: nil) }

    it 'anúncio da Meta: grava origem, canal e o anúncio — o mesmo do código; sem balão' do
      msg = create(:message, account: account, conversation: conversa, message_type: :incoming, content: 'oi',
                             content_attributes: { referral: { 'source_id' => '12034', 'ctwa_clid' => 'c1' } })
      expect(rodar('origem_do_lead', ensaio: true)[:resumo]).to start_with('faria: anotar a origem')
      expect(rodar('origem_do_lead', mensagem: msg))
        .to eq(saida: 's', resumo: 'origem do lead: canal meta_ads, origem anuncio-meta: 12034', sem_balao: true)
      expect(lead.reload.custom_attributes['meta_referral']).to include('ctwa_clid' => 'c1')
    end

    it 'de verdade sem a mensagem do gatilho é passo impossível (falha na hora, sem nova tentativa)' do
      expect { rodar('origem_do_lead') }.to raise_error(Ramon::Fluxos::PassoImpossivel, /mensagem do gatilho/)
    end
  end

  describe 'sugestao_documento' do
    let(:thesis) { create(:thesis, account: account) }
    let!(:rg) { create(:thesis_item, thesis: thesis, section: 'documento', content: 'RG') }
    let!(:lead) { create(:lead, account: account, contact: contact, conversation: conversa, thesis: thesis) }
    let(:anexo) { create(:message, :with_attachment, account: account, conversation: conversa, message_type: :incoming) }

    it 'ensaio não chama a IA; de verdade grava a sugestão e o gatilho Documento recebido continua nascendo' do
      allow(Ramon::LlmClient).to receive(:complete).and_return(llm(%({"item_id": #{rg.id}})))
      allow(Ramon::Fluxos::Disparo).to receive(:externo).and_call_original
      rodar('sugestao_documento', mensagem: anexo, ensaio: true)
      expect(Ramon::LlmClient).not_to have_received(:complete)
      expect(rodar('sugestao_documento', mensagem: anexo)[:resumo]).to eq('a IA sugeriu um documento do checklist (a equipe confirma no painel)')
      expect(lead.reload.custom_attributes.dig('doc_sugestao', 'item_id')).to eq(rg.id)
      expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('documento_recebido', lead, hash_including('documento' => 'RG'))
    end

    it 'IA fora do ar antes da última tentativa: sobe o erro (o motor tenta de novo em 1/5/15 min)' do
      allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::TransientError)
      expect { rodar('sugestao_documento', mensagem: anexo, tentativas: 2) }.to raise_error(Ramon::LlmClient::TransientError)
    end

    it 'IA fora do ar na última tentativa: desiste em silêncio (N4), sem sino' do
      allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::TransientError)
      expect(rodar('sugestao_documento', mensagem: anexo, tentativas: 3))
        .to eq(saida: 's', resumo: 'sugestão de documento: desistiu depois de 4 tentativas (TransientError)', sem_balao: true)
    end
  end

  describe 'coach_objecao' do
    let(:thesis) { create(:thesis, account: account) }
    let!(:lead) { create(:lead, account: account, contact: contact, conversation: conversa, thesis: thesis) }
    let(:msg) { create(:message, account: account, conversation: conversa, message_type: :incoming, content: 'achei caro, vou pensar mais um pouco') }

    before { create(:thesis_item, thesis: thesis, section: 'objecao', title: 'Caro', content: 'A análise é gratuita.') }

    it 'ensaio não chama a IA; de verdade o mesmo coach (balão do coach, e a trava de 10 min gravada)' do
      allow(Ramon::LlmClient).to receive(:complete).and_return(
        llm('{"objecao": "custo", "opcoes": [{"titulo": "A", "texto": "a"}, {"titulo": "B", "texto": "b"}]}')
      )
      expect(rodar('coach_objecao', mensagem: msg, ensaio: true)[:resumo]).to start_with('faria: o coach')
      expect(Ramon::LlmClient).not_to have_received(:complete)
      expect { rodar('coach_objecao', mensagem: msg) }.to have_enqueued_job(Conversations::ActivityMessageJob)
        .with(conversa, hash_including(content_attributes: hash_including('ramon_event' => 'coach')))
      expect(lead.reload.custom_attributes.dig('coach', 'ultima_em')).to be_present
    end
  end

  describe 'agente_hub' do
    let(:eduardo) { create(:user, account: account, email: 'edu@x.com') }

    around { |ex| with_modified_env(RAMON_AGENTE_RUNNER_URL: 'http://runner/hub', RAMON_AGENTE_EDUARDO_EMAIL: 'edu@x.com') { ex.run } }

    before { allow(HTTParty).to receive(:post) }

    it '@claude do Eduardo: avisa o runner (o mesmo job de hoje)' do
      nota = create(:message, account: account, conversation: conversa, message_type: :outgoing, private: true, sender: eduardo,
                              content: '@claude resume')
      expect(rodar('agente_hub', mensagem: nota)[:resumo]).to eq('avisou o agente do hub (a resposta chega como nota privada)')
      expect(HTTParty).to have_received(:post).with('http://runner/hub', anything).once
    end

    it 'a trava fica na rotina: nota @claude de outra pessoa não chama o agente, nem com o passo noutro fluxo' do
      outro = create(:user, account: account, email: 'o@x.com')
      nota = create(:message, account: account, conversation: conversa, message_type: :outgoing, private: true, sender: outro,
                              content: '@claude resume')
      expect(rodar('agente_hub', mensagem: nota)[:resumo]).to eq('não é nota @claude do Eduardo: o agente não foi chamado')
      expect(HTTParty).not_to have_received(:post)
    end
  end
end
```

- [ ] **Step 2: Rodar — falha** (CI): `uninitialized constant Ramon::Fluxos::Rotinas::Leads` / "rotina desconhecida".

- [ ] **Step 3: `app/services/ramon/fluxos/rotinas/leads.rb`**

```ruby
# frozen_string_literal: true

# B5-leads: rotinas prontas de leads e conversas — o MESMO código de hoje, com as mesmas travas. Registro (B5-conta):
# ROTINAS + um método público `nome(ctx)` por rotina, que devolve o resultado do passo. O ensaio só descreve (sem IA,
# sem gravar). As de mensagem leem a mensagem pelo 'mensagem_id' do gatilho (Mensagem recebida / Nota privada escrita).
# - criar_lead: Ramon::LeadDaConversa.criar_ou_ligar (só caixa com "Criar lead" e conversa com contato)
# - origem_do_lead: Ramon::LeadDaConversa.origem (anúncio da Meta; canal derivado; nunca sobrescreve canal já definido)
# - sugestao_documento: Ramon::DocMatchJob (a IA sugere o item do checklist; daqui nasce o gatilho Documento recebido)
# - coach_objecao: Ramon::CoachObjecaoJob (1 vez a cada 10 min por conversa; qualquer erro = silêncio)
# - agente_hub: Ramon::AgenteNotifyJob (só nota @claude do Eduardo — a trava fica aqui dentro; a tela não a tira)
# Job.new.perform (T5): o corpo do job, na hora — perform_now re-enfileiraria pelo retry_on dele (dobra com o motor).
# Sem balão "⚙ Fluxo" (N3), exceto criar_lead: as de mensagem seriam 1 por mensagem e o efeito já tem o seu balão.
module Ramon::Fluxos::Rotinas::Leads
  ROTINAS = %w[criar_lead origem_do_lead sugestao_documento coach_objecao agente_hub].freeze
  # IA fora do ar ou anexo ainda indisponível: o motor tenta de novo (1/5/15 min); na última, desiste em silêncio (N4).
  PASSAGEIROS = [Ramon::LlmClient::TransientError, ActiveStorage::FileNotFoundError].freeze

  module_function

  def criar_lead(ctx)
    conversa = ctx.conversa || raise(Ramon::Fluxos::PassoImpossivel, 'este passo precisa de uma conversa')
    return quieto('a caixa não cria lead (ou a conversa não tem contato): nada feito') unless Ramon::LeadDaConversa.cabe?(conversa)
    return feito('faria: criar o lead na 1ª etapa do funil (ou ligar a conversa ao lead aberto do contato)') if ctx.ensaio?

    lead = Ramon::LeadDaConversa.criar_ou_ligar(conversa)
    feito("#{lead.previously_new_record? ? 'lead criado' : 'conversa ligada ao lead aberto'}: #{lead.name} (#{lead.lead_stage.name})")
  end

  def origem_do_lead(ctx)
    return feito('faria: anotar a origem e o canal do lead (anúncio da Meta, site/LP/bio, instagram ou indicação)') if ctx.ensaio?

    lead = Ramon::Fluxos::Passos::Lead.exigir_lead(ctx)
    Ramon::LeadDaConversa.origem(lead, mensagem!(ctx))
    lead.reload
    quieto("origem do lead: canal #{lead.channel}#{", origem #{lead.source}" if lead.source.present?}")
  end

  def sugestao_documento(ctx)
    return feito('faria: a IA compara o anexo com o checklist da tese e sugere o documento (a equipe confirma)') if ctx.ensaio?

    msg = mensagem!(ctx)
    Ramon::DocMatchJob.new.perform(msg.id)
    casou = ctx.lead&.reload&.custom_attributes&.dig('doc_sugestao', 'message_id') == msg.id
    quieto(casou ? 'a IA sugeriu um documento do checklist (a equipe confirma no painel)' : 'a IA não reconheceu o anexo no checklist pendente')
  rescue *PASSAGEIROS => e
    raise if ctx.execucao.tentativas < Ramon::Fluxos::Executor::ESPERAS_ERRO.size

    quieto("sugestão de documento: desistiu depois de #{ctx.execucao.tentativas + 1} tentativas (#{e.class.name.demodulize})")
  end

  def coach_objecao(ctx)
    return feito('faria: o coach procura objeção na mensagem e sugere 2 respostas do playbook da tese') if ctx.ensaio?

    Ramon::CoachObjecaoJob.new.perform(mensagem!(ctx).id)
    quieto('coach de objeção: leu a mensagem (havendo objeção, as 2 respostas aparecem no balão do coach)')
  end

  def agente_hub(ctx)
    return feito('faria: avisar o agente do hub na VPS (só nota @claude do Eduardo)') if ctx.ensaio?

    msg = mensagem!(ctx)
    return quieto('não é nota @claude do Eduardo: o agente não foi chamado') unless Ramon::AgenteNotifyJob.chamado?(msg)

    Ramon::AgenteNotifyJob.new.perform(msg.id)
    quieto('avisou o agente do hub (a resposta chega como nota privada)')
  end

  def feito(resumo) = { saida: 's', resumo: resumo }

  def quieto(resumo) = feito(resumo).merge(sem_balao: true)

  # A mensagem que disparou o fluxo. Sem ela ("Testar com um lead…" vira ensaio, que não chega aqui): passo impossível.
  def mensagem!(ctx)
    id = ctx.gatilho('mensagem_id')
    (id && ctx.execucao.account.messages.find_by(id: id)) ||
      raise(Ramon::Fluxos::PassoImpossivel, 'este passo precisa da mensagem do gatilho (Mensagem recebida ou Nota privada escrita)')
  end
end
```

Se a resposta da **N3** for **B** (balão em todos): trocar todo `quieto(` por `feito(` e apagar `quieto`. Se for **C** (nenhum): `criar_lead` também devolve `quieto(…)`. Se a **N4** for **A**: apagar o `rescue *PASSAGEIROS …` (e a constante), e o 3º exemplo do describe `sugestao_documento` passa a esperar `raise_error` também com `tentativas: 3` (quem marca "falhou" e avisa é o Executor). Ajuste os specs na mesma medida.

- [ ] **Step 4: Registrar no registro do B5-conta** — no formato anotado na Task 0 (assumido: `MODULOS = [..., Ramon::Fluxos::Rotinas::Leads].freeze`, **no fim**). Se o `Passos::Rotina` do B5-conta chamar `exigir_lead` antes de despachar, isso tem de ficar só nas rotinas dele (as desta fatia rodam em conversa sem lead) — se não ficar, pare e avise o controlador.

- [ ] **Step 5: Rastrear à mão** cada exemplo (sem Ruby local): `create!` de execução com `tentativas`/`contexto` (colunas existem; `status` padrão `'rodando'` = viva → 1 por exemplo; ensaio fora do índice); `ctx.conversa` = alvo; `ctx.lead` = lead da conversa; no `coach`, o `ActivityMessageJob` vem do `EventoInline.registrar` do serviço; no agente, o corpo do `HTTParty.post` é o do job de hoje. Rubocop: `criar_lead` tem 2 guardas + 1 ternário (ciclomática 4); linhas ≤ 150 (a do `quieto(casou ? …)` tem ~145 — se passar, quebre o ternário em 2 linhas).

- [ ] **Step 6: Commit**

```bash
git add app/services/ramon/fluxos/rotinas/leads.rb spec/services/ramon/fluxos/rotinas/leads_spec.rb <arquivo do registro do B5-conta>
git commit -m "feat(fluxos): rotinas prontas de leads e conversas — criar lead, origem, documento, coach e agente (B5-leads)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 4: Os 5 desenhos migrados + "No código" atualizado + provas com o fluxo no comando — **mecânica**

**Files:**
- Create: `db/seeds/ramon/fluxos/migrados/{criar_lead_da_conversa,origem_do_lead,sugestao_documento,coach_objecao,agente_hub}.json`
- Modify: `db/seeds/ramon/fluxos/sistema/{criar_lead_da_conversa,origem_do_lead,sugestao_documento,coach_objecao,agente_hub}.json`
- Test: `spec/services/ramon/fluxos/migracao_spec.rb`, `spec/listeners/ramon_lead_listener_spec.rb` (dentro do describe da Task 2), `spec/listeners/ramon_agente_listener_spec.rb`

**Interfaces:**
- Consumes: Tasks 1–3 (grupos, `decidir`, `NA_HORA_CHAVES`, rotinas, ajudantes do describe).
- Produces: os 5 fluxos semeáveis por `rake "ramon:fluxos:migracao:criar[<grupo>,<conta>]"`.

- [ ] **Step 1: Specs que falham**

Em `spec/services/ramon/fluxos/migracao_spec.rb`, antes do `end` final:

```ruby
  it 'leads e conversas (B5-leads): criar = 1 fluxo por grupo, em sombra, ligado, publicado, gatilho certo e 1 rotina pronta' do
    rotinas = { 'criar_lead' => 'criar_lead', 'origem_lead' => 'origem_do_lead', 'sugestao_doc' => 'sugestao_documento',
                'coach' => 'coach_objecao', 'agente' => 'agente_hub' }
    rotinas.each do |grupo, rotina|
      fluxo = described_class.semear(account, grupo).sole
      expect(described_class.semear(account, grupo)).to eq([fluxo])
      expect([fluxo.origem, fluxo.modo, fluxo.ativo, fluxo.gatilho_tipo]).to eq(['usuario', 'sombra', true, described_class.gatilhos(grupo).values.sole])
      nos = fluxo.versao_publicada.grafo['nos']
      expect([nos.first.dig('config', 'cancelar_se_sair_da_etapa'), nos.filter_map { |n| n.dig('config', 'rotina') }]).to eq([false, [rotina]])
    end
  end
```

Dentro do describe `'leads e conversas — código ou fluxo (B5-leads)'` de `spec/listeners/ramon_lead_listener_spec.rb`, depois do último `it`:

```ruby
    it 'fluxo no comando: a mesma ordem — o fluxo cria o lead na hora, antes do SLA e dos fluxos comuns; lead.created 1 vez' do
      fluxo = assumir('criar_lead')
      disparos = gravar_disparos { lead_da_conversa.present? }
      expect { publicar('conversation.created', conversation: conversation) }
        .to have_enqueued_job(Ramon::FirstResponseSlaJob).with(conversation.id)
        .and have_enqueued_job(EventDispatcherJob).with('lead.created', anything, anything).exactly(:once)
      expect(disparos).to eq([['conversa_criada', 'criar_lead', false], ['conversa_criada', 'sla', true], ['conversa_criada', nil, true]])
      expect(fluxo.execucoes.pluck(:ensaio, :status)).to eq([[false, 'concluida']])
      expect(lead_da_conversa).to have_attributes(contact_id: contact.id, name: 'Maria', lead_stage: account.lead_stages.order(:position).first)
    end

    it 'em sombra (criado, ainda não virado): o código cria o lead e o fluxo só ensaia — 1 lead' do
      Ramon::Fluxos::Migracao.semear(account, 'criar_lead')
      publicar('conversation.created', conversation: conversation)
      trilha = Ramon::Fluxos::Migracao.fluxo(account, 'criar_lead_da_conversa').execucoes.sole.trilha.pluck('resumo')
      expect(trilha).to include('faria: criar o lead na 1ª etapa do funil (ou ligar a conversa ao lead aberto do contato)')
      expect(account.leads.where(contact_id: contact.id).count).to eq(1)
    end

    it 'fluxo no comando mas ocupado com a conversa: o código cria o lead (reserva) — nem 0 nem 2' do
      fluxo = assumir('criar_lead')
      fluxo.execucoes.create!(account: account, alvo: conversation, status: 'esperando', retomar_em: 5.minutes.from_now)
      publicar('conversation.created', conversation: conversation)
      expect(account.leads.where(conversation_id: conversation.id).count).to eq(1)
      expect(fluxo.execucoes.count).to eq(1)
    end

    it 'fluxo no comando: liga a conversa ao lead aberto do mesmo contato, sem lead novo (como o código)' do
      antiga = create(:conversation, account: account, inbox: inbox, contact: contact)
      aberto = create(:lead, account: account, name: 'Maria', contact: contact, conversation: antiga,
                             lead_stage: account.lead_stages.order(:position).first)
      fluxo = assumir('criar_lead')
      expect { publicar('conversation.created', conversation: conversation) }.not_to(change { account.leads.count })
      expect(aberto.reload.conversation_id).to eq(conversation.id)
      expect(fluxo.execucoes.sole.trilha.last['resumo']).to eq('conversa ligada ao lead aberto: Maria (Novo)')
    end

    it 'origem pelo fluxo: na hora, antes dos fluxos comuns de Mensagem recebida — a mesma origem do código' do
      create(:lead, account: account, contact: contact, conversation: conversation, channel: 'outro', source: nil)
      fluxo = assumir('origem_lead')
      disparos = gravar_disparos { lead_da_conversa.source }
      publicar('message.created', message: mensagem('oi', content_attributes: { referral: anuncio }))
      expect(disparos).to eq([['mensagem_recebida', 'origem_lead', nil], ['mensagem_recebida', nil, 'anuncio-meta: 12034']])
      expect(lead_da_conversa).to have_attributes(channel: 'meta_ads', source: 'anuncio-meta: 12034')
      expect(lead_da_conversa.custom_attributes['meta_referral']).to include('source_id' => '12034')
      expect(fluxo.execucoes.pluck(:ensaio, :status)).to eq([[false, 'concluida']])
    end

    describe 'coach e sugestão de documento pelo fluxo (pela fila, como o código)' do
      let(:thesis) { create(:thesis, account: account) }
      let!(:lead) { create(:lead, account: account, contact: contact, conversation: conversation, thesis: thesis, channel: 'landing_page') }

      def llm(conteudo) = Ramon::LlmClient::Result.new(content: conteudo, input_tokens: 1, output_tokens: 1)

      def ev(msg) = Events::Base.new('message.created', Time.zone.now, message: msg)

      before { allow(Ramon::EventoInline).to receive(:registrar).and_call_original }

      it 'coach: o ouvinte não enfileira o job; o fluxo roda o mesmo coach (balão do coach) sem balão ⚙ na conversa' do
        create(:thesis_item, thesis: thesis, section: 'objecao', title: 'Advogado é caro', content: 'A análise é gratuita.')
        allow(Ramon::LlmClient).to receive(:complete)
          .and_return(llm('{"objecao": "custo", "opcoes": [{"titulo": "A", "texto": "a"}, {"titulo": "B", "texto": "b"}]}'))
        fluxo = assumir('coach')
        msg = mensagem('achei caro, vou pensar mais um pouco antes de fechar')
        expect { listener.message_created(ev(msg)) }.not_to have_enqueued_job(Ramon::CoachObjecaoJob)
        perform_enqueued_jobs(only: Ramon::FluxoAvancarJob)
        expect(Ramon::EventoInline).to have_received(:registrar).with(conversation, anything, hash_including(tipo: 'coach')).once
        expect(Ramon::EventoInline).not_to have_received(:registrar).with(anything, anything, hash_including(tipo: 'fluxo'))
        expect(fluxo.execucoes.pluck(:ensaio, :status)).to eq([[false, 'concluida']])
      end

      it 'documento: o fluxo roda a mesma IA, grava a sugestão e o gatilho Documento recebido continua nascendo' do
        rg = create(:thesis_item, thesis: thesis, section: 'documento', content: 'RG')
        allow(Ramon::LlmClient).to receive(:complete).and_return(llm(%({"item_id": #{rg.id}})))
        comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'documento_recebido' }, ['parar', {}]))
        fluxo = assumir('sugestao_doc')
        msg = mensagem('segue', :with_attachment)
        expect { listener.message_created(ev(msg)) }.not_to have_enqueued_job(Ramon::DocMatchJob)
        perform_enqueued_jobs(only: Ramon::FluxoAvancarJob)
        expect(lead.reload.custom_attributes.dig('doc_sugestao', 'item_id')).to eq(rg.id)
        expect(comum.execucoes.count).to eq(1)
        expect(fluxo.execucoes.pluck(:ensaio, :status)).to eq([[false, 'concluida']])
      end

      it 'rajada de anexos com o fluxo no comando: o 1º vai pelo fluxo, os outros pelo código — nenhum se perde, nenhum em dobro' do
        fluxo = assumir('sugestao_doc')
        pelo_codigo = []
        allow(Ramon::DocMatchJob).to receive(:perform_later) { |id| pelo_codigo << id }
        msgs = Array.new(3) { mensagem('foto', :with_attachment) }
        msgs.each { |m| listener.message_created(ev(m)) }
        expect(fluxo.execucoes.sole.contexto.dig('gatilho', 'mensagem_id')).to eq(msgs[0].id)
        expect(pelo_codigo).to eq([msgs[1].id, msgs[2].id])
      end
    end
```

Em `spec/listeners/ramon_agente_listener_spec.rb`, antes do `end` final:

```ruby
  describe 'pelo fluxo (B5-leads: RAMON_FLUXO_AGENTE=on + o fluxo "Agente do hub" em modo normal)' do
    around { |ex| with_modified_env(RAMON_FLUXO_AGENTE: 'on') { ex.run } }

    before do
      Ramon::Fluxos::Migracao.semear(account, 'agente')
      Ramon::Fluxos::Migracao.mudar_modo!(account, 'agente', 'normal')
      allow(HTTParty).to receive(:post)
    end

    it 'o ouvinte não enfileira o job; o fluxo avisa o runner 1 vez, com a mesma mensagem' do
      msg = create(:message, account: account, conversation: conversation, private: true, sender: eduardo, content: '@claude resume')
      expect { listener.message_created(event_for(msg)) }.not_to have_enqueued_job(Ramon::AgenteNotifyJob)
      perform_enqueued_jobs(only: Ramon::FluxoAvancarJob)
      expect(HTTParty).to have_received(:post).with('http://runner/hub', hash_including(body: include(%("message_id":#{msg.id})))).once
    end

    it 'nota @claude de outra pessoa: nem fluxo nem job (a trava vem antes da decisão)' do
      outro = create(:user, account: account, email: 'o@x.com')
      msg = create(:message, account: account, conversation: conversation, private: true, sender: outro, content: '@claude x')
      expect { listener.message_created(event_for(msg)) }.not_to have_enqueued_job
      expect(FluxoExecucao.count).to eq(0)
    end
  end
```

- [ ] **Step 2: Rodar — falham** (CI): `No such file … migrados/criar_lead_da_conversa.json`.

- [ ] **Step 3: Os 5 JSON migrados** (`db/seeds/ramon/fluxos/migrados/`):

`criar_lead_da_conversa.json`
```json
{
  "nome": "Criar lead da conversa",
  "descricao": "Migrado do código (B5). Conversa nova numa caixa com \"Criar lead\" ligado (e com contato) → cria o lead na 1ª etapa do funil, com o nome (ou o telefone) do contato, ou liga a conversa ao lead aberto do mesmo contato. Roda na hora, antes do SLA da 1ª resposta e dos outros fluxos de conversa nova. Quem dispara é o ouvinte de leads, só nas caixas com Criar lead. Se este fluxo não começar (filtro editado, ocupado, erro), o código cria o lead, como antes. Os números do funil e dos relatórios saem deste lead: apagar o passo deixa as conversas novas sem lead.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"conversa_criada","cancelar_se_sair_da_etapa":false},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"rotina","config":{"rotulo":"Cria o lead (ou liga a conversa ao lead aberto do contato)","rotina":"criar_lead"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`origem_do_lead.json`
```json
{
  "nome": "Origem do lead",
  "descricao": "Migrado do código (B5). Mensagem do cliente numa conversa com lead, quando há o que anotar (anúncio da Meta na mensagem, ou canal ainda não descoberto) → grava a origem e o canal: anúncio da Meta (com o anúncio guardado no lead), assinatura de site/LP/bio, instagram (caixa do Instagram) ou indicação. Nunca troca um canal já definido. Roda na hora, antes dos outros fluxos de mensagem recebida. Se este fluxo não começar, o código anota, como antes.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"mensagem_recebida","cancelar_se_sair_da_etapa":false},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"rotina","config":{"rotulo":"Anota a origem e o canal do lead","rotina":"origem_do_lead"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`sugestao_documento.json`
```json
{
  "nome": "Sugestão de documento",
  "descricao": "Migrado do código (B5). Cliente manda um anexo (imagem ou arquivo) numa conversa com lead → a IA compara com o checklist da tese e grava uma sugestão; quem confirma é a equipe, no painel. Quando casa, nasce o gatilho Documento recebido. IA fora do ar: tenta de novo em 1, 5 e 15 min e depois desiste em silêncio. Vários anexos de uma vez: o que chega enquanto este roda é feito pelo código (nada se perde).",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"mensagem_recebida","cancelar_se_sair_da_etapa":false},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"rotina","config":{"rotulo":"IA sugere o item do checklist (a equipe confirma)","rotina":"sugestao_documento"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`coach_objecao.json`
```json
{
  "nome": "Coach de objeção",
  "descricao": "Migrado do código (B5). Mensagem do cliente com 20 caracteres ou mais, numa conversa com lead → se a tese tem playbook de objeções e a IA vê uma objeção, mostra 2 respostas num balão (Usar só coloca o texto no editor; quem envia é a pessoa). No máximo 1 vez a cada 10 min por conversa; qualquer erro = silêncio.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"mensagem_recebida","cancelar_se_sair_da_etapa":false},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"rotina","config":{"rotulo":"Balão com 2 respostas do playbook (Usar só preenche o editor)","rotina":"coach_objecao"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`agente_hub.json`
```json
{
  "nome": "Agente do hub (@claude)",
  "descricao": "Migrado do código (B5). Nota privada começando com @claude, escrita pelo Eduardo → avisa o agente do hub na VPS, que responde na própria conversa como nota privada. A trava (só @claude, só o e-mail do Eduardo, só com o agente configurado) é fixa: fica dentro do passo e nenhuma edição aqui a tira. Falha de rede só vai para o log.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"nota_escrita","cancelar_se_sair_da_etapa":false},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"rotina","config":{"rotulo":"Avisa o agente do hub na VPS","rotina":"agente_hub"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

- [ ] **Step 4: Os 5 JSON do sistema — só a 1ª linha da `descricao`** (Edit; o resto fica). Trocar:

| arquivo | de | para |
|---|---|---|
| `criar_lead_da_conversa.json` | `No código: RamonLeadListener#conversation_created (app/listeners/ramon_lead_listener.rb), só em caixas com Criar lead ligado.` | `No código: RamonLeadListener#conversation_created → Ramon::LeadDaConversa.criar_ou_ligar, só em caixas com Criar lead ligado (decide: o código ou o fluxo migrado \"Criar lead da conversa\").` |
| `origem_do_lead.json` | `No código: RamonLeadListener#message_created → apply_meta_referral e derive_channel_from_first_contact.` | `No código: RamonLeadListener#message_created → Ramon::LeadDaConversa.origem (apply_meta_referral e derive_channel_from_first_contact; decide: o código ou o fluxo migrado \"Origem do lead\").` |
| `coach_objecao.json` | `No código: RamonLeadListener#message_created → Ramon::CoachObjecaoJob` | `No código: RamonLeadListener#message_created (decide: o código ou o fluxo migrado \"Coach de objeção\") → Ramon::CoachObjecaoJob` |
| `sugestao_documento.json` | `No código: RamonLeadListener#message_created → Ramon::DocMatchJob` | `No código: RamonLeadListener#message_created (decide: o código ou o fluxo migrado \"Sugestão de documento\") → Ramon::DocMatchJob` |
| `agente_hub.json` | `No código: RamonAgenteListener#message_created → Ramon::AgenteNotifyJob.` | `No código: RamonAgenteListener#message_created → Ramon::AgenteNotifyJob (decide: o código ou o fluxo migrado \"Agente do hub\").` |

E no `sistema/agente_hub.json`: trocar `— os fluxos não têm gatilho de nota privada (aqui: Rodar na mão);` por `— trava fixa (Ramon::AgenteNotifyJob.chamado?), que a tela não edita;` e o gatilho `{"tipo":"manual","rotulo":"Nota privada @claude do Eduardo"}` por `{"tipo":"nota_escrita","rotulo":"Nota privada @claude do Eduardo"}`.

(No JSON as aspas internas já são `\"`, como no resto do arquivo. O `specs/sistema.spec.js` do front só volta a ficar verde com o gatilho `nota_escrita` no `fluxo.js` — Task 5; o Ruby já aceita desde a Task 1.)

- [ ] **Step 5: Rastrear à mão** (sem Ruby local):
  - "fluxo no comando: a mesma ordem": `decidir('criar_lead')` → `assumiu?` true (env on, 1 fluxo normal, gatilho certo, sem limite) → `Disparo.call` grava `[…, 'criar_lead', false]` → `da_vez?` (migrado, `'migracao' => 'criar_lead'` → chave do grupo) → `iniciar` → `na_hora?` (chave em `NA_HORA_CHAVES`) → `Executor#avancar!` → rotina cria o lead (balão `ActivityMessageJob`; `lead.created` enfileirado 1 vez) → `feitas.any?` → bloco não roda. `decidir('sla')`: `RAMON_FLUXO_SLA` desligada → job enfileirado; `Disparo.call` grava `[…, 'sla', true]`. `RamonAgenteListener`: não tem `conversation_created`. `RamonFluxoListener#conversation_created` → `[…, nil, true]`.
  - "em sombra": `assumiu?` false (modo sombra) → execução ensaio na hora ("faria: …") → bloco cria o lead.
  - "ocupado": `create!` da execução do evento bate no índice único → `RecordNotUnique` → `nil` → `[]` → bloco cria.
  - "rajada": msg0 → execução viva (FluxoAvancarJob não roda no teste) → msg1/msg2 batem no índice → reserva → `perform_later(id)` stubado. `contexto['gatilho']['mensagem_id']` = msg0.
  - Agente: `chamado?` (env do `around` de fora + `RAMON_FLUXO_AGENTE`) → `decidir('agente', 'nota_escrita')` → fluxo pela fila → `perform_enqueued_jobs(only: FluxoAvancarJob)` → rotina → `AgenteNotifyJob.new.perform` → `HTTParty.post(url, body: json, timeout:, headers:)`.

- [ ] **Step 6: Commit**

```bash
git add db/seeds/ramon/fluxos/migrados/criar_lead_da_conversa.json db/seeds/ramon/fluxos/migrados/origem_do_lead.json db/seeds/ramon/fluxos/migrados/sugestao_documento.json db/seeds/ramon/fluxos/migrados/coach_objecao.json db/seeds/ramon/fluxos/migrados/agente_hub.json db/seeds/ramon/fluxos/sistema/criar_lead_da_conversa.json db/seeds/ramon/fluxos/sistema/origem_do_lead.json db/seeds/ramon/fluxos/sistema/sugestao_documento.json db/seeds/ramon/fluxos/sistema/coach_objecao.json db/seeds/ramon/fluxos/sistema/agente_hub.json spec/services/ramon/fluxos/migracao_spec.rb spec/listeners/ramon_lead_listener_spec.rb spec/listeners/ramon_agente_listener_spec.rb
git commit -m "feat(fluxos): fluxos de criar lead, origem, documento, coach e agente — mesma ordem, reserva pelo código (B5-leads)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 5: Editor — gatilho "Nota privada escrita", as 5 rotinas e os desenhos conferidos — **mecânica**

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js` (`GATILHOS`, `ROTINAS`)
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`, `app/javascript/dashboard/i18n/locale/en/ramon.json` (`CAPTAIN_RAMON.FLUXOS.GATILHOS`, `.ROTINAS`, `.ROTINAS_AJUDA`)
- Test: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/migrados.spec.js` (a trava `specs/i18n.spec.js` e `specs/sistema.spec.js` cobrem o resto sem mudança)

**Interfaces:**
- Consumes: os nomes da Task 3 e os JSON da Task 4.
- Produces: o quadro abre, valida e publica os 5 desenhos; o gatilho e as rotinas aparecem na paleta.

- [ ] **Step 1: Spec que falha** — em `specs/migrados.spec.js`: na linha `import { REGRAS_ADVBOX, TIPOS_ATIVIDADE } from '../fluxo';` acrescentar `ROTINAS` (`import { REGRAS_ADVBOX, ROTINAS, TIPOS_ATIVIDADE } from '../fluxo';`); depois do último `import … .json` acrescentar:

```js
import criarLead from '../../../../../../../../db/seeds/ramon/fluxos/migrados/criar_lead_da_conversa.json';
import origemLead from '../../../../../../../../db/seeds/ramon/fluxos/migrados/origem_do_lead.json';
import sugestaoDoc from '../../../../../../../../db/seeds/ramon/fluxos/migrados/sugestao_documento.json';
import coach from '../../../../../../../../db/seeds/ramon/fluxos/migrados/coach_objecao.json';
import agente from '../../../../../../../../db/seeds/ramon/fluxos/migrados/agente_hub.json';
```

e no fim do arquivo:

```js
describe('fluxos migrados: leads e conversas (B5-leads)', () => {
  it.each([
    ['criar lead', criarLead, 'conversa_criada', 'criar_lead'],
    ['origem', origemLead, 'mensagem_recebida', 'origem_do_lead'],
    ['documento', sugestaoDoc, 'mensagem_recebida', 'sugestao_documento'],
    ['coach', coach, 'mensagem_recebida', 'coach_objecao'],
    ['agente', agente, 'nota_escrita', 'agente_hub'],
  ])(
    '%s: publica; gatilho certo sem cancelar por etapa; 1 rotina pronta do hub',
    (_nome, d, gatilho, rotina) => {
      expect(validar(d.desenho)).toEqual([]);
      expect(d.desenho.nos[0].config).toEqual({
        tipo: gatilho,
        cancelar_se_sair_da_etapa: false,
      });
      expect(d.desenho.nos.map(n => n.tipo)).toEqual(['gatilho', 'rotina']);
      expect(d.desenho.nos[1].config.rotina).toBe(rotina);
      expect(ROTINAS).toContain(rotina);
    }
  );
});
```

- [ ] **Step 2: Rodar — falha**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/migrados.spec.js --config vitest.local.config.ts
```
Expected: FAIL (`GATILHO_DESCONHECIDO` no do agente; `ROTINAS` sem as 5).

- [ ] **Step 3: `fluxo.js`** — no fim de `GATILHOS` (depois de `{ tipo: 'manual', … }` ou do último que o B5-conta pôs):

```js
  { tipo: 'nota_escrita', icone: 'i-lucide-sticky-note', alvo: 'conversa' },
```

No comentário de `ROTINAS`, acrescentar ` + Ramon::Fluxos::Rotinas::Leads::ROTINAS (B5-leads)` e, no fim da lista:

```js
  'criar_lead',
  'origem_do_lead',
  'sugestao_documento',
  'coach_objecao',
  'agente_hub',
```

- [ ] **Step 4: i18n** — no fim de cada objeto, na mesma posição nos dois arquivos (sem `@`, `|`, `{`, `}`):

`pt_BR/ramon.json`:
- `GATILHOS`: `"nota_escrita": "Nota privada escrita (pela equipe)"`
- `ROTINAS`:
  - `"criar_lead": "Criar o lead da conversa (ou ligar ao lead aberto do contato)"`
  - `"origem_do_lead": "Anotar a origem e o canal do lead"`
  - `"sugestao_documento": "Sugerir o documento do checklist (a IA lê o anexo)"`
  - `"coach_objecao": "Coach de objeção (2 respostas do playbook)"`
  - `"agente_hub": "Avisar o agente do hub (nota arroba claude do Eduardo)"`
- `ROTINAS_AJUDA`:
  - `"criar_lead": "O mesmo código de hoje: só em caixa com Criar lead ligado e conversa com contato. Liga a conversa ao lead aberto do mesmo contato ou cria o lead na 1ª etapa do funil. Os números do funil saem daqui."`
  - `"origem_do_lead": "Lê o anúncio da Meta que chega com a mensagem e grava origem e canal; sem anúncio e sem assinatura de site, LP ou bio, o canal vira indicação (ou instagram, na caixa do Instagram). Nunca troca um canal já definido. Precisa da mensagem do gatilho."`
  - `"sugestao_documento": "A IA compara o anexo com o checklist da tese e grava uma sugestão; quem confirma é a equipe, no painel. Quando casa, nasce o gatilho Documento recebido. IA fora do ar: tenta de novo em 1, 5 e 15 min e depois desiste em silêncio. Precisa da mensagem do gatilho."`
  - `"coach_objecao": "Se a mensagem tem objeção e a tese tem playbook, mostra 2 respostas num balão (Usar só coloca o texto no editor). No máximo 1 vez a cada 10 min por conversa; erro = silêncio. Precisa da mensagem do gatilho."`
  - `"agente_hub": "Avisa o agente do hub na VPS, que responde como nota privada. Trava fixa: só nota privada que começa com arroba claude, escrita pelo e-mail do Eduardo — nenhuma edição aqui tira isso."`

`en/ramon.json`:
- `GATILHOS`: `"nota_escrita": "Private note written (by the team)"`
- `ROTINAS`:
  - `"criar_lead": "Create the lead from the conversation (or link it to the contact open lead)"`
  - `"origem_do_lead": "Record the lead source and channel"`
  - `"sugestao_documento": "Suggest the checklist document (AI reads the attachment)"`
  - `"coach_objecao": "Objection coach (2 replies from the playbook)"`
  - `"agente_hub": "Notify the hub agent (Eduardo at-claude note)"`
- `ROTINAS_AJUDA`:
  - `"criar_lead": "Same code as today: only in inboxes with Create lead on and conversations with a contact. Links the conversation to the contact open lead or creates the lead in the first pipeline stage. The pipeline numbers come from here."`
  - `"origem_do_lead": "Reads the Meta ad that comes with the message and stores source and channel; with no ad and no site, LP or bio signature, the channel becomes referral (or instagram, in the Instagram inbox). Never changes a channel already set. Needs the trigger message."`
  - `"sugestao_documento": "AI compares the attachment with the case checklist and stores a suggestion; the team confirms it in the panel. When it matches, the Document received trigger fires. AI down: tries again in 1, 5 and 15 min, then gives up silently. Needs the trigger message."`
  - `"coach_objecao": "If the message has an objection and the case type has a playbook, shows 2 replies in a bubble (Use only fills the editor). At most once every 10 min per conversation; errors are silent. Needs the trigger message."`
  - `"agente_hub": "Notifies the hub agent on the VPS, which replies as a private note. Fixed lock: only private notes starting with at-claude, written by Eduardo e-mail — no edit here removes it."`

- [ ] **Step 5: Rodar tudo**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts
./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/migrados.spec.js
```
Expected: **B + 5** testes verdes (o `it.each` conta 5; `i18n.spec.js` "cobre todo o catálogo" já passa a exigir as chaves novas e passa; `sistema.spec.js` aceita o `nota_escrita` do agente); eslint sem `error`.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/migrados.spec.js
git commit -m "feat(fluxos): editor com o gatilho Nota privada escrita e as rotinas de leads e conversas (B5-leads)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 6A: Etiquetas de etapa e tese como "regra fixa" (N1 = A, recomendado) — **exige julgamento (formato do B5-conta)**

**Files:**
- Modify: `db/seeds/ramon/fluxos/sistema/etiquetas_etapa_tese.json`
- Modify: o spec do B5-conta que lista as regras fixas (anotado na Task 0)

- [ ] **Step 1:** No spec do B5-conta que confere a lista das regras fixas, acrescentar `'etiquetas_etapa_tese'` à lista esperada (no lugar certo da ordem que ele usar). Rodar (Vitest local, se o spec for do front; senão CI) — FAIL.
- [ ] **Step 2:** Marcar `sistema/etiquetas_etapa_tese.json` com o selo, no formato do B5-conta (assumido: `"regra_fixa": true` logo depois de `"grupo"`). Não mudar o desenho nem a descrição (o "No código:" continua certo: `RamonLeadListener#lead_created, #lead_updated e #conversation_updated → Ramon::StageLabelSync e Ramon::TeseLabelSync`).
- [ ] **Step 3:** Rodar o spec — PASS. Commit:

```bash
git add db/seeds/ramon/fluxos/sistema/etiquetas_etapa_tese.json <spec do B5-conta>
git commit -m "feat(fluxos): etiquetas de etapa e tese ficam como regra fixa (B5-leads, N1)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

### Task 6B: Etiquetas — o sentido "lead → conversa" vira fluxo (SÓ se N1 = B; nesse caso, pule a 6A) — **exige julgamento**

**Files:**
- Modify: `app/services/ramon/stage_label_sync.rb`, `app/services/ramon/tese_label_sync.rb` (`self.desalinhada?`)
- Modify: `app/listeners/ramon_lead_listener.rb` (`lead_created`, `lead_updated`), `app/listeners/ramon_fluxo_listener.rb` (`lead_updated`)
- Modify: `app/services/ramon/fluxos/migracao.rb` (grupo `etiquetas`), `disparo.rb` (`DUAS_VEZES` += `lead_atualizado`), `grafo.rb` (`GATILHOS` += `lead_atualizado`), `app/services/ramon/fluxos/rotinas/leads.rb` (rotina `etiquetas_do_lead`)
- Create: `db/seeds/ramon/fluxos/migrados/etiquetas_etapa_tese.json`
- Modify: `db/seeds/ramon/fluxos/sistema/etiquetas_etapa_tese.json` (1ª linha da descrição), `.env.example` (`# RAMON_FLUXO_ETIQUETAS=off` no bloco da Task 1), front (`fluxo.js` `GATILHOS`/`ROTINAS`, i18n `GATILHOS.lead_atualizado`, `ROTINAS(_AJUDA).etiquetas_do_lead`, `migrados.spec.js` +1 caso)
- Test: `spec/listeners/ramon_lead_listener_spec.rb`, `spec/listeners/ramon_fluxo_listener_spec.rb`, `spec/services/ramon/fluxos/rotinas/leads_spec.rb`

- [ ] **Step 1: Specs que falham** — no describe `'leads e conversas — código ou fluxo (B5-leads)'` do `ramon_lead_listener_spec.rb` (acrescentar `RAMON_FLUXO_ETIQUETAS: 'on'` no `around`):

```ruby
    describe 'etiquetas pelo fluxo (N1 = B)' do
      let!(:lead) { create(:lead, account: account, contact: contact, conversation: conversation, lead_stage: account.lead_stages.find_by!(label: 'fase-novo')) }

      def ev(lead) = Events::Base.new('lead.updated', Time.zone.now, lead: lead)

      it 'etiqueta fora do lugar: o fluxo põe a fase da etapa (pela fila); o código não' do
        fluxo = assumir('etiquetas')
        lead.update!(lead_stage: account.lead_stages.find_by!(label: 'fase-qualificacao'))
        listener.lead_updated(ev(lead))
        expect(conversation.reload.label_list).not_to include('fase-qualificacao') # ainda não: o fluxo roda pela fila
        perform_enqueued_jobs(only: Ramon::FluxoAvancarJob)
        expect(conversation.reload.label_list).to contain_exactly('fase-qualificacao')
        expect(fluxo.execucoes.pluck(:ensaio, :status)).to eq([[false, 'concluida']])
      end

      it 'etiquetas já no lugar: nada é decidido (nenhuma execução a cada atualização do lead)' do
        Ramon::StageLabelSync.apply_to_conversation(lead)
        fluxo = assumir('etiquetas')
        listener.lead_updated(ev(lead))
        expect(fluxo.execucoes.count).to eq(0)
      end

      it 'etiqueta fase-* posta à mão continua movendo o lead pelo código, sem laço (o eco acha tudo igual)' do
        fluxo = assumir('etiquetas')
        listener.conversation_updated(Events::Base.new('conversation.updated', Time.zone.now, conversation: conversation,
                                                       changed_attributes: { 'label_list' => [[], ['fase-qualificacao']] }))
        expect(lead.reload.lead_stage.label).to eq('fase-qualificacao')
        listener.lead_updated(ev(lead))
        expect(fluxo.execucoes.count).to eq(0)
      end
    end
```

No `ramon_fluxo_listener_spec.rb`, no exemplo `'etapa mudou dispara etapa + ganho…'`, acrescentar como 1ª linha `allow(Ramon::Fluxos::Disparo).to receive(:call)` (o `lead_atualizado` agora também é disparado) e um exemplo novo:

```ruby
  it 'lead atualizado (N1 = B) dispara para os fluxos comuns a cada atualização, mesmo sem mudança de etapa' do
    expect(Ramon::Fluxos::Disparo).to receive(:call).with('lead_atualizado', lead, {}, origem: nil)
    listener.lead_updated(evento('lead.updated', lead: lead, changed_attributes: {}))
  end
```

No `rotinas/leads_spec.rb`:

```ruby
  describe 'etiquetas_do_lead (N1 = B)' do
    let!(:lead) { create(:lead, account: account, contact: contact, conversation: conversa, lead_stage: account.lead_stages.find_by!(label: 'fase-novo')) }

    it 'ensaio só descreve; de verdade põe a fase da etapa e a tese do lead na conversa, sem balão' do
      expect(rodar('etiquetas_do_lead', ensaio: true)[:resumo]).to eq('faria: pôr na conversa as etiquetas da etapa e da tese do lead')
      expect(rodar('etiquetas_do_lead')).to eq(saida: 's', resumo: 'etiquetas da etapa e da tese na conversa', sem_balao: true)
      expect(conversa.reload.label_list).to contain_exactly('fase-novo')
    end
  end
```

- [ ] **Step 2: Rodar — falham** (CI).

- [ ] **Step 3: Código.**

`stage_label_sync.rb` (depois de `apply_to_conversation`):
```ruby
  # A conversa do lead está sem exatamente a fase-* da etapa? (o que apply_to_conversation corrigiria)
  def self.desalinhada?(lead)
    conversation = lead.conversation
    target = lead.lead_stage&.label
    conversation.present? && target.present? && conversation.label_list.select { |l| l.to_s.start_with?(FASE_PREFIX) } != [target]
  end
```

`tese_label_sync.rb` (depois de `apply_to_conversation`):
```ruby
  # A conversa do lead está sem exatamente a tese-* da tese do lead? (o que apply_to_conversation corrigiria)
  def self.desalinhada?(lead)
    conversation = lead.conversation
    return false if conversation.nil?

    alvo = lead.thesis && label_for(lead.thesis)
    conversation.label_list.select { |label| label.to_s.start_with?(PREFIX) } != [alvo].compact
  end
```

`ramon_lead_listener.rb` — trocar `lead_created` e `lead_updated` por:
```ruby
  def lead_created(event) = etiquetas(event.data[:lead])

  def lead_updated(event) = etiquetas(event.data[:lead])
```
e em `private`:
```ruby
  # Etiquetas fase-*/tese-* (N1 = B): só quando estão fora do lugar — senão nada a decidir (o lead muda o tempo todo).
  def etiquetas(lead)
    return unless Ramon::StageLabelSync.desalinhada?(lead) || Ramon::TeseLabelSync.desalinhada?(lead)

    decidir('etiquetas', 'lead_atualizado', lead, {}) do
      Ramon::StageLabelSync.apply_to_conversation(lead)
      Ramon::TeseLabelSync.apply_to_conversation(lead)
    end
  end
```

`ramon_fluxo_listener.rb` — `lead_updated` começa disparando o gatilho novo para os fluxos comuns:
```ruby
  def lead_updated(event)
    lead = event.data[:lead]
    disparar('lead_atualizado', lead, event)
    de, para = (event.data[:changed_attributes] || {})['lead_stage_id']
    return if para.nil?

    etapa = LeadStage.find_by(id: para) # a etapa do evento, não a de agora (o lead pode ter andado de novo)
    dados = { 'de_etapa_id' => de, 'para_etapa_id' => para }
    disparar('lead_mudou_etapa', lead, event, dados)
    disparar('lead_ganho', lead, event, dados) if etapa&.is_won
    disparar('lead_perdido', lead, event, dados) if etapa&.is_lost
  end
```

`migracao.rb` (fim de `GRUPOS`):
```ruby
    'etiquetas' => { env: 'RAMON_FLUXO_ETIQUETAS', faz: 'as etiquetas de etapa e tese',
                     fluxos: { 'etiquetas_etapa_tese' => 'lead_atualizado' }.freeze }
```
`disparo.rb`: `DUAS_VEZES = (NA_HORA + %w[conversa_criada lead_ganho mensagem_recebida nota_escrita lead_atualizado]).freeze`. `grafo.rb`: `GATILHOS` += `lead_atualizado` (no fim).

`rotinas/leads.rb`: `ROTINAS` += `etiquetas_do_lead` (no fim) e
```ruby
  def etiquetas_do_lead(ctx)
    return feito('faria: pôr na conversa as etiquetas da etapa e da tese do lead') if ctx.ensaio?

    lead = Ramon::Fluxos::Passos::Lead.exigir_lead(ctx)
    Ramon::StageLabelSync.apply_to_conversation(lead)
    Ramon::TeseLabelSync.apply_to_conversation(lead)
    quieto('etiquetas da etapa e da tese na conversa')
  end
```

`migrados/etiquetas_etapa_tese.json`:
```json
{
  "nome": "Etiquetas de etapa e tese",
  "descricao": "Migrado do código (B5). Quando a etiqueta da conversa fica diferente da etapa ou da tese do lead (lead novo, mudou de etapa ou de tese, conversa nova ligada) → põe na conversa a etiqueta fase-… da etapa e tese-… da tese, tirando a antiga. A etiqueta fase-… posta à mão continua movendo o lead (regra fixa do código). Se este fluxo não começar, o código põe as etiquetas, como antes.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"lead_atualizado","cancelar_se_sair_da_etapa":false},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"rotina","config":{"rotulo":"Etiquetas fase-… e tese-… na conversa","rotina":"etiquetas_do_lead"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`sistema/etiquetas_etapa_tese.json`, 1ª linha da descrição: `No código: RamonLeadListener#lead_created, #lead_updated e #conversation_updated → Ramon::StageLabelSync e Ramon::TeseLabelSync.` → `No código: RamonLeadListener#lead_created e #lead_updated (decide: o código ou o fluxo migrado \"Etiquetas de etapa e tese\") e #conversation_updated (etiqueta à mão move o lead: regra fixa) → Ramon::StageLabelSync e Ramon::TeseLabelSync.`

Front: `GATILHOS` += `{ tipo: 'lead_atualizado', icone: 'i-lucide-refresh-cw', alvo: 'lead' }`; `ROTINAS` += `'etiquetas_do_lead'`; i18n pt `GATILHOS.lead_atualizado` = `"Lead atualizado (qualquer mudança)"`, `ROTINAS.etiquetas_do_lead` = `"Etiquetas da etapa e da tese na conversa"`, `ROTINAS_AJUDA.etiquetas_do_lead` = `"Põe na conversa a etiqueta fase da etapa e a tese do lead, tirando a antiga. Só age quando estão fora do lugar."`; en `"Lead updated (any change)"`, `"Stage and case type labels on the conversation"`, `"Puts the stage and case type labels of the lead on the conversation, removing the old ones. Only acts when they are out of place."`; `migrados.spec.js`: import `etiquetas` do JSON novo e caso `['etiquetas', etiquetas, 'lead_atualizado', 'etiquetas_do_lead']` no `it.each`. Spec Ruby do grupo (Task 4, `migracao_spec`): acrescentar `'etiquetas' => 'etiquetas_do_lead'` ao hash `rotinas`, e `'etiquetas' => ['RAMON_FLUXO_ETIQUETAS', { 'etiquetas_etapa_tese' => 'lead_atualizado' }]` ao `esperado` da Task 1.

- [ ] **Step 4: Rastrear laços à mão:** fluxo põe a fase → `conversation.updated` → `apply_to_lead` acha a etapa igual → não move → `set_conversation_fase` vê `[target]` → não grava. Etiqueta à mão → `apply_to_lead` move o lead e já ajusta a conversa → `lead.updated` → `desalinhada?` false → nada. Vitest: B + 6.

- [ ] **Step 5: Commit** (todos os arquivos acima, mensagem `feat(fluxos): etiquetas de etapa e tese no sentido lead → conversa viram fluxo (B5-leads, N1=B)` + as 2 linhas de atribuição).

---

### Task 7: Verificação final + notas na spec + texto do PR — **mecânica**

**Files:**
- Modify: `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (seção nova no fim)

- [ ] **Step 1: Front inteiro**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts
./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes
git status --short
```
Expected: B + 5 (N1=B: + 6) verdes; eslint sem `error`; `vitest.local.config.ts` fora da lista.

- [ ] **Step 2: Varredura**

```bash
BASE=$(git merge-base HEAD origin/ramon)
git diff $BASE --stat -- enterprise db/migrate db/schema.rb app/models
grep -rn "apply_meta_referral\|derive_channel_from_first_contact\|enqueue_first_response_sla" app spec lib
grep -rn "RAMON_FLUXO_CRIAR_LEAD\|RAMON_FLUXO_ORIGEM_LEAD\|RAMON_FLUXO_SUGESTAO_DOC\|RAMON_FLUXO_COACH\|RAMON_FLUXO_AGENTE" app lib .env.example
for f in app/services/ramon/fluxos/migracao.rb app/services/ramon/fluxos/disparo.rb app/listeners/ramon_lead_listener.rb app/services/ramon/fluxos/rotinas/leads.rb app/services/ramon/lead_da_conversa.rb; do echo "$f $(grep -cvE '^\s*(#|$)' $f)"; done
```
Expected: o 1º vazio; o 2º só em `app/services/ramon/lead_da_conversa.rb`; as 5 envs em `migracao.rb` e `.env.example`; `migracao.rb` ≤ 100, os demais bem abaixo dos limites.

- [ ] **Step 3: Notas na spec** — acrescentar ao fim de `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (número = a próxima seção livre depois da do B5-conta):

```markdown
## NN. Notas da B5-leads (07/10/2026) — leads e conversas

- **Escopo (decisões do Eduardo de 07/10 + N1–N5 desta fatia):** criar lead da conversa, origem do lead, sugestão de documento, coach de objeção e agente do hub saem do código para 5 fluxos (`origem: usuario`; chaves `criar_lead_da_conversa`, `origem_do_lead`, `sugestao_documento`, `coach_objecao`, `agente_hub`), direto, sem sombra. Uma chave por automação: `RAMON_FLUXO_CRIAR_LEAD`, `…_ORIGEM_LEAD`, `…_SUGESTAO_DOC`, `…_COACH`, `…_AGENTE` (grupos `criar_lead`, `origem_lead`, `sugestao_doc`, `coach`, `agente`). Etiquetas de etapa/tese: N1 (regra fixa, ou o sentido lead → conversa como fluxo).
- **Decisão por evento com grupo:** `Ramon::Fluxos::Migracao.decidir(grupo, gatilho, alvo, dados) { código }` — lê `assumiu?` uma vez, dispara os migrados com `assumido` e `migracao` (vários grupos dividem `conversa_criada` e `mensagem_recebida`: o `Disparo.da_vez?` só inicia os do grupo que decidiu) e roda o código `unless assumido && feitas.any?` (reserva). O SLA (B4.2) usa o mesmo ajudante. `mensagem_recebida` e `nota_escrita` entraram em `DUAS_VEZES`.
- **A ordem de sempre:** criar lead e origem migrados rodam na hora, dentro do ouvinte (`Disparo::NA_HORA_CHAVES`, por chave do fluxo): o lead existe antes do SLA e dos fluxos comuns de Conversa nova; a origem, antes dos fluxos comuns de Mensagem recebida (provado pelo despachante real, nos dois modos). `lead.created` sai 1 vez.
- **Guardas antes da decisão, e de novo na rotina:** caixa com Criar lead + contato; há origem a anotar (1 execução por lead, não por mensagem); anexo imagem/arquivo; 20+ caracteres; nota @claude do Eduardo. A rotina confere a mesma guarda — a do agente (`Ramon::AgenteNotifyJob.chamado?`) é trava fixa que a tela não tira.
- **Motor ganhou:** gatilho `nota_escrita` (nota privada de pessoa; notas de fluxo não têm autor e não disparam); `mensagem_id` no gatilho de mensagem; rotinas prontas `criar_lead`, `origem_do_lead`, `sugestao_documento`, `coach_objecao`, `agente_hub` (`Ramon::Fluxos::Rotinas::Leads`, registro do B5-conta; chamam o corpo dos jobs de hoje, `Job.new.perform`). Código mudou de arquivo: `Ramon::LeadDaConversa`.
- **Diferenças aceitas:** balão "⚙ Fluxo" só no criar lead (N3); IA fora do ar ao ler anexo: 4 tentativas e desiste em silêncio (N4); rajada de anexos/mensagens: o que chega com o fluxo ocupado é feito pelo código e não aparece em Execuções (N5); coach e documento rodam na fila `default` (antes `low`).
- **Fica para a limpeza (outro PR, 2 semanas depois em normal):** os JSON `sistema/{criar_lead_da_conversa,origem_do_lead,sugestao_documento,coach_objecao,agente_hub}.json` **e** as linhas `origem: sistema` deles, as 5 envs; o código de reserva (`Ramon::LeadDaConversa` e os `perform_later` do ouvinte) fica enquanto houver reserva.
```

- [ ] **Step 4: Texto do PR (não abrir — gate do Eduardo)** — deixar no relatório final:

```markdown
Automações em fluxo — B5-leads: criar o lead da conversa, anotar a origem do lead, sugerir o documento do checklist, o coach de objeção e o agente do hub (@claude) ganham 5 fluxos de verdade, editáveis em Inteligência → Automações depois de assumirem. Cada um tem a sua chave: desligada (padrão), tudo segue pelo código como hoje; ligada e com o fluxo em modo normal, o fluxo faz e o código para; voltar é um comando, sem deploy. Se o fluxo no comando não pegar um evento (ocupado, filtro editado, erro), o código faz aquele evento — nada se perde, nada sai em dobro. A ordem não muda: o lead nasce antes do aviso de SLA e dos outros fluxos de conversa nova, e a origem é anotada antes dos fluxos de mensagem recebida. Gatilho novo "Nota privada escrita"; a trava do agente (só @claude do Eduardo) fica fixa.

## Closes
- Spec `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` §8 (B4+: migração 1 a 1) e §16 ("um novo grupo em conversa_criada precisa da sua própria chave de decisão"); notas novas no fim.

## How to test
1. Depois do deploy: `rake "ramon:fluxos:migracao:criar[criar_lead,2]"` (e `origem_lead`, `sugestao_doc`, `coach`, `agente`) → "modo sombra, ligado" e "Agora o CÓDIGO faz … (os fluxos ensaiam)".
2. Inteligência → Automações → Meus fluxos: os 5 fluxos novos, cada um com 1 "Rotina pronta do hub", selo "em sombra".
3. Virar as chaves e rodar o teste ao vivo da seção "Operação" (conversa de teste com o copiloto em manual): lead criado pelo fluxo, origem do anúncio, coach, sugestão de documento e a resposta do agente a uma nota @claude.

## What changed
- `Ramon::Fluxos::Migracao.decidir` (decisão por evento com grupo e reserva), `Disparo` com `migracao`/`NA_HORA_CHAVES`, gatilho `nota_escrita`, `mensagem_id` no gatilho de mensagem, `Ramon::Fluxos::Rotinas::Leads` (5 rotinas), `Ramon::LeadDaConversa` (o código do ouvinte, mudado de arquivo), `Ramon::AgenteNotifyJob.chamado?`.
- 5 envs `RAMON_FLUXO_*` desligadas; 5 desenhos em `db/seeds/ramon/fluxos/migrados/`. Sem migração de banco.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR
```

- [ ] **Step 5: Smoke em bloco** — anotar no relatório a seção "Operação depois do deploy" inteira (o Eduardo roda via `!` e cola as saídas).

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md
git commit -m "docs(fluxos): notas da B5-leads na spec" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

Sem push.

---

## Operação depois do deploy

Conta da banca = **2**; console = `docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "<task>"` / `… rails runner '<ruby>'` (o Eduardo roda via `!` e cola a saída). Deploy = o de sempre, **sem migração**. **Junto com o deploy**, acrescentar ao `chatwoot.env` em `/opt/intranet-ramon`: `RAMON_FLUXO_CRIAR_LEAD=on`, `RAMON_FLUXO_ORIGEM_LEAD=on`, `RAMON_FLUXO_SUGESTAO_DOC=on`, `RAMON_FLUXO_COACH=on`, `RAMON_FLUXO_AGENTE=on` (N1=B: + `RAMON_FLUXO_ETIQUETAS=on`) — seguro: sem os fluxos em modo normal, o código segue fazendo tudo. Recriar **web e worker** (os ouvintes rodam no worker).

**1. Checagem (somente leitura).** Fluxos comuns que vão disparar na conversa de teste; se algum tiver webhook/ADVBOX/e-mail, desligar na tela durante o teste ou PARAR:
```
docker exec intranet-ramon-chatwoot-web-1 bundle exec rails runner 'p Account.find(2).fluxos.executaveis.where(origem: "usuario", gatilho_tipo: %w[conversa_criada mensagem_recebida lead_criado documento_recebido nota_escrita]).map { |f| [f.id, f.nome, f.gatilho_tipo, f.sistema_chave] }'
```

**2. Criar os fluxos (código ainda no comando).**
```
for g in criar_lead origem_lead sugestao_doc coach agente; do docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:migracao:criar[$g,2]"; done
```
Esperado: 5 × "modo sombra, ligado" + "Agora o CÓDIGO faz … (os fluxos ensaiam)". Rodar de novo não duplica. Na tela: Automações → Meus fluxos → os 5, cada um gatilho + 1 rotina.

**3. Virar.**
```
for g in criar_lead origem_lead sugestao_doc coach agente; do docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:migracao:modo[$g,2,normal]"; done
```
Esperado: 5 × "Agora os FLUXOS fazem … (o código não faz mais)".

**4. Teste ao vivo — conversa de teste (copiloto em manual: a IA não responde; nada sai para fora; o aviso de SLA fica calado).** Cria contato e conversa numa caixa com Criar lead, espera o lead nascer pelo fluxo, põe uma tese com playbook e manda 3 mensagens fabricadas (anúncio, objeção, anexo):
```
docker exec intranet-ramon-chatwoot-web-1 bundle exec rails runner '
a = Account.find(2)
i = a.inboxes.where(auto_create_lead: true).where.not(channel_type: "Channel::Instagram").first
c = a.contacts.create!(name: "Teste Fluxo B5", phone_number: "+5548900005555")
ci = ContactInbox.create!(contact: c, inbox: i, source_id: "5548900005555")
conv = Conversation.create!(account: a, inbox: i, contact: c, contact_inbox: ci, custom_attributes: { "copiloto_modo" => "manual" })
20.times { break if a.leads.exists?(conversation_id: conv.id); sleep 1 }
l = a.leads.find_by!(conversation_id: conv.id)
conv.update_columns(first_reply_created_at: Time.current)
t = a.theses.detect { |x| x.thesis_items.where(section: "objecao").exists? && x.thesis_items.where(section: "documento").exists? }
l.update!(thesis: t) if t
conv.messages.create!(account: a, inbox: i, message_type: :incoming, sender: c, content: "Oi, vi o anúncio",
                      content_attributes: { "referral" => { "source_id" => "teste-b5", "headline" => "Teste B5" } })
sleep 5
conv.messages.create!(account: a, inbox: i, message_type: :incoming, sender: c, content: "Achei caro, vou pensar mais um pouco antes de fechar com vocês")
m = conv.messages.new(account: a, inbox: i, message_type: :incoming, sender: c, content: "segue o doc")
m.attachments.new(account_id: a.id, file_type: :image).file.attach(io: StringIO.new("teste"), filename: "rg-frente.jpg", content_type: "image/jpeg")
m.save!
sleep 40
l.reload
puts "caixa #{i.name} | conversa #{conv.display_id} | lead #{l.id} tese #{t&.name.inspect}"
puts "canal #{l.channel} | origem #{l.source} | doc_sugestao #{l.custom_attributes["doc_sugestao"].inspect}"
%w[criar_lead_da_conversa origem_do_lead coach_objecao sugestao_documento].each do |k|
  f = a.fluxos.find_by(origem: "usuario", sistema_chave: k)
  puts "#{k}: #{f.execucoes.where("created_at > ?", 10.minutes.ago).pluck(:ensaio, :status).inspect}"
end'
```
Esperado: `canal meta_ads | origem anuncio-meta: teste-b5`; cada um dos 4 com `[[false, "concluida"]]` (sem `true` = sem ensaio). `doc_sugestao` preenchido **ou** `nil` (a IA pode não reconhecer um "rg-frente.jpg" de mentira — o que importa é a execução concluída). Se a tese vier `nil` (nenhuma tese com playbook de objeção **e** checklist), o coach e o documento concluem sem efeito — anotar e seguir.

**5. Agente (o Eduardo, na tela).** Abrir a conversa de teste (nº acima) e escrever a nota privada `@claude teste do fluxo B5, responda só OK`. Esperado: em até ~1 min a resposta como nota privada; Automações → "Agente do hub (@claude)" → 1 execução concluída, "avisou o agente do hub…".

**6. Conferir na tela (em bloco).**
- Conversa de teste: o lead "Teste Fluxo B5" no funil (1ª etapa) e **1** balão "⚙ Fluxo Criar lead da conversa: lead criado…"; nenhum outro balão "⚙"; balão do coach (se a IA viu objeção) e/ou da sugestão de documento.
- Automações → cada um dos 5 fluxos: as execuções acima, nenhuma "falhou".
- Nenhum aviso de SLA chegou para a conversa de teste.

**7. Limpar o teste.**
```
docker exec intranet-ramon-chatwoot-web-1 bundle exec rails runner '
a = Account.find(2)
c = a.contacts.find_by!(phone_number: "+5548900005555")
a.leads.where(contact_id: c.id).find_each { |l| l.lead_activities.delete_all; l.destroy! }
a.conversations.where(contact_id: c.id).find_each(&:destroy!)
c.destroy!
puts "ok"'
```

**8. Rollback (a qualquer momento, sem deploy, cada um independente).**
`docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:migracao:modo[<grupo>,2,sombra]"` → "Agora o CÓDIGO faz". Também seguro: tirar a env do `chatwoot.env` e recriar. **Não** desligar o fluxo na tela como forma de voltar: para criar lead e origem, que rodam na hora, dá no mesmo; mas coach/documento/agente em andamento seriam cancelados ("o fluxo foi desligado") sem que o código refaça aquela mensagem.

**9. Depois (outro PR, E7).** Com 2 semanas em normal sem incidente: apagar os JSON `db/seeds/ramon/fluxos/sistema/{criar_lead_da_conversa,origem_do_lead,sugestao_documento,coach_objecao,agente_hub}.json` **e** as linhas `origem: sistema` deles (a sincronização não apaga linha cujo JSON sumiu) e as 5 envs (os fluxos passam a ser o caminho único — a reserva continua usando `Ramon::LeadDaConversa` e os jobs).

---

## Divergências registradas (spec × este plano)

| # | Onde | Divergência | Motivo |
|---|---|---|---|
| 1 | Spec §8 B4+ ("modo sombra por alguns dias; comparar") | Direto, teste ao vivo logo após o deploy | E1 (Eduardo, 07/10, herdado) |
| 2 | Spec §6 (Disparo enfileira o avanço) | Criar lead e origem migrados rodam na hora, dentro do ouvinte | a ordem de sempre (lead antes do SLA e dos fluxos comuns; origem antes dos fluxos de mensagem) |
| 3 | Spec §16 ("`.any?` do listener supõe o SLA único grupo em `conversa_criada`") | `'migracao'` no evento + `Migracao.decidir` | 2 grupos em `conversa_criada`, 3 em `mensagem_recebida` |
| 4 | Spec §4.1 (gatilhos) | Gatilho novo `nota_escrita` (N2) | o agente não tinha gatilho nos fluxos |
| 5 | Spec §6 ("cada ação executada registra balão") | Rotinas de mensagem sem balão "⚙" | N3 |
