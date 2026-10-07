# Automações em fluxo — B4.3 (a cadência de retomada sai do código e vira fluxo) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A cadência de retomada (W4) — todo dia às 11h, para os leads parados que podem receber retomada, até 15 por conta: rascunho de retomada nº N escrito pela IA **nas notas do lead**, tarefa "Retomada nº N" para hoje, contador em `custom_attributes.follow_up`, balão na conversa e 1 push — passa a ser feita por **um fluxo de verdade** ("Cadência de retomada", editável por admin), e o botão "Preparar retomada" do painel passa pelo mesmo fluxo. Uma **chave** (`RAMON_FLUXO_CADENCIA=on` + o fluxo em modo `normal`) põe o fluxo no comando e para o código; qualquer peça fora devolve ao código, sem deploy.

**Architecture:** As regras da retomada (quem pode, nº da tentativa, dias parado, gravar o contador) saem do `Ramon::FollowUpDraftService` para um módulo único, `Ramon::Fluxos::Retomada`, que o código e o fluxo usam (como o `Ramon::Fluxos::Reunioes` da B4.1). O motor ganha o mínimo para ser fiel: gatilho "Lead parado" com a opção **retomada** (todo dia enquanto seguir parado, só quem pode receber retomada, na ordem do funil — o `limite_dia` 15 do fluxo é o teto do código), variáveis `{tentativa}` e `{dias_parado}`, `rascunho_ia` com `onde`/`titulo`/`reserva` (texto fixo se a IA falhar), passo novo **Registrar a retomada** (o contador) e push **uma vez por dia**. A chave é lida pelo `DailyFollowUpJob` (pula a conta), pelo `FollowUpDraftJob` (o botão roda o fluxo) e pelo `Ramon::Fluxos::Relogio` (o fluxo só dispara com ele no comando). Sem migração, sem sombra, sem comparação.

**Tech Stack:** Rails 7.1 / RSpec (só no CI), Postgres jsonb, Sidekiq (ActiveJob), Redis (`Redis::Alfred`); Vue 3.5 `<script setup>`, vue-i18n 9, Vitest 3 + @vue/test-utils.

**Spec:** `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (§4 peças, §6 motor, §8 migração B4+, §13 notas da B2b — "`lead_parado` dispara 1 vez por parada", §14 notas da B3 — "o fluxo em sombra é um fluxo próprio (origem `usuario`)… quando assumir, apagar o JSON **e** a linha do sistema", §15 notas da B4.1). O desenho de hoje (com a lista "O desenho não consegue mostrar", que são exatamente as lacunas que este plano fecha): `db/seeds/ramon/fluxos/sistema/cadencia.json`. Plano de referência de estilo e da chave: `docs/superpowers/plans/2026-10-06-automacoes-fluxo-b4-lembretes.md` (B4.1).

## Escopo (o mesmo que o Eduardo escolheu para a B4.2 em 07/10; vence a spec §8)

1. **E1 — DIRETO:** sem modo sombra e sem comparação código × fluxo. O teste é **ao vivo, logo depois do deploy** (botão "Preparar retomada" num lead de teste + o lote das 11h do dia seguinte).
2. **E2 — chave igual à da B4.1:** env própria **`RAMON_FLUXO_CADENCIA=on`** + o fluxo "Cadência de retomada" ligado, publicado, em `modo: normal` e com o gatilho "Lead parado" ⇒ o fluxo faz a cadência e o código para. Qualquer peça fora (env desligada, fluxo em `sombra`, desligado na tela, gatilho trocado) ⇒ o código faz e o fluxo **fica parado** (não ensaia). Voltar = rake (`…modo[conta,sombra]`), sem deploy.
3. **E3 — textos internos podem mudar:** balão na conversa ("⚙ Fluxo Cadência de retomada: …" em vez de "⟳ Cadência do hub…") e push ("Retomadas prontas pra revisar" sem o número do lote).
4. **E4 — mensagem ao cliente SEMPRE rascunho:** a retomada continua **nota RASCUNHO nas notas do lead** + tarefa na Esteira, com o mesmo cabeçalho do código (`RASCUNHO (revisar antes de enviar) — retomada nº N:`). Nenhum passo envia nada ao cliente.
5. **E5 — limpeza** (apagar o código antigo, o desenho e a linha do sistema, a env) num **PR separado, 2 semanas depois** de rodar em normal sem incidente.
6. **Horário comercial não entra:** o código roda todo dia às 11h de São Paulo (cron `0 14 * * *`, inclusive sábado e domingo) e não olha horário comercial; o fluxo faz igual (gatilho às 11:00, fuso SP). O passo de horário configurável da B4.2 **não é usado** aqui.

## Global Constraints

- **Ordem:** a B4.3 roda **depois da B4.2 (SLA)** e rebaseada nela (Task 0). Base de hoje: `origin/ramon` **079a04c** (B1–B3 + B4.1 no ar, #213–#218 no ar); branch `feat/fluxos-b43-cadencia`, worktree `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-fluxos-b43`. Nunca `git push`, nunca abrir PR, nunca `git stash`, nunca `git add -A` (gate do Eduardo / sessão principal).
- **Produção não muda até o Eduardo virar a chave.** Sem `RAMON_FLUXO_CADENCIA=on` (padrão) o `DailyFollowUpJob` e o botão fazem exatamente o que fazem hoje. O fluxo só nasce quando alguém roda `ramon:fluxos:cadencia:criar` (nasce em `modo: sombra` = parado) e só age depois de `…modo[conta,normal]`.
- **Não apagar nada do caminho antigo nesta fatia:** `Ramon::FollowUpDraftService`, `Ramon::DailyFollowUpJob` (+ a entrada em `config/schedule.yml`), o desenho `db/seeds/ramon/fluxos/sistema/cadencia.json` e a linha `origem: sistema` dele ficam (E5). O serviço só passa a **usar** as regras únicas (Task 1).
- **Sem migração.** `ramon_fluxos` já tem `origem`, `sistema_chave`, `modo`, `limite_dia`, `ativo`, `ultimo_disparo_em`; `ramon_fluxo_execucoes` já tem o índice único parcial `(fluxo_id, alvo_type, alvo_id) WHERE status IN ('rodando','esperando') AND NOT ensaio`. Se alguma task achar que precisa de coluna/índice: pare e pergunte (não há Postgres local para regenerar `db/schema.rb`).
- **Rubocop do fork** (o CI barra): `Metrics/AbcSize` 26, `Metrics/MethodLength` 19, `Metrics/CyclomaticComplexity` 7, `Metrics/PerceivedComplexity` 8, `Metrics/ClassLength` 175, `Metrics/ModuleLength` 100, `Metrics/BlockLength` 30 (fora de spec), linha 150, `Style/HashSyntax` `EnforcedShorthandSyntax: never` (sempre `chave: valor`), `Naming/MethodParameterName` mínimo 3 letras, `rubocop-rspec` (`RSpec/MultipleExpectations` 7, `RSpec/ExampleLength` 50, `RSpec/SpecFilePathFormat`: spec de `A::B::C` em `spec/.../a/b/c_spec.rb`, **`RSpec/ContextWording`: `context` só começando com when/with/without — frase em pt-BR vai em `describe`**). **`app/models/lead.rb`, `app/services/ramon/advbox_event_processor.rb` e `app/finders/conversation_finder.rb` estão NO LIMITE de 175 linhas: nenhuma linha nova neles** (este plano não toca nenhum dos três). Tamanhos na base 079a04c: `relogio.rb` 67, `contexto.rb` 123, `executor.rb` 148, `grafo.rb` 199 (≈150 de código), `passos/ia.rb` 108, `passos/aviso.rb` 39, `passos/conversa.rb` 49, `follow_up_draft_service.rb` 172 (vai a ~150).
- **CI FOSS apaga `enterprise/`:** nada desta fatia toca `Captain::*`. Se precisar, pare.
- **Sem Ruby local:** specs Ruby são escritos e conferidos à mão (rastrear cada linha) e quem valida é o CI. `travel_to` em blocos **em sequência**, nunca um dentro do outro; código que o spec faz viajar nunca usa `NOW()` do SQL (só `Time.current`/bind). Helper que cria execução viva é chamado **uma vez por exemplo e por alvo** (o índice único parcial barra 2 execuções `rodando/esperando` não-ensaio no mesmo fluxo+alvo). `.distinct.pluck` em modelo com `default_scope` ordenado (o `Lead` é: `order(:lead_stage_id, :position, :id)`) quebra no Postgres — use `.pluck.uniq`. Notificações: o builder cria 1 linha por pessoa por chamada e o job de dedupe não roda no teste — nunca contar notificações acumuladas entre chamadas.
- **Mensagem ao cliente SEMPRE rascunho; só admin edita.** A API de fluxos segue admin-only (`RamonFluxoPolicy#gerenciar?`).
- **Front:** i18n só dentro de `CAPTAIN_RAMON.FLUXOS` em `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json`, chaves novas na **mesma posição** nos dois arquivos (a trava `specs/i18n.spec.js` compara a ordem, cobre o catálogo e compila no vue-i18n de produção); strings sem `@`, `|`, `{`, `}` crus; editar os JSON à mão (Edit). Tailwind only, kit `ramon/helpers/ui.js` (`TOM`, `ROTULO`, `CAMPO`, `SELECT`), evento custom camelCase, toda `<ul>/<ol>` nova com `list-none` (a B4.3 não cria lista), sem texto cru no template.
- **Vitest:** `node_modules` é junção (nunca `rm -rf node_modules`). Config local **já criado e fora do git** `vitest.local.config.ts` na raiz do worktree (não commitar):
  `TZ=UTC npx vitest run <arquivos ou pastas> --config vitest.local.config.ts`
  Baseline medido em 079a04c: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs` = **15 arquivos, 180 testes** (remedir depois do rebase na B4.2 — Task 0). ESLint: `./node_modules/.bin/eslint <arquivos>` (erro `Delete ␍` = CRLF do checkout Windows, ignorar; warnings `@intlify/vue-i18n/no-dynamic-keys` já existem e são aceitos).
- **Bash heredoc come barras invertidas neste Windows:** criar/editar arquivos com Write/Edit, não com heredoc.
- **Commits:** Conventional Commits em pt-BR, sem citar Claude no assunto; corpo termina com:
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR`
  Commitar só os caminhos da task (`git add <arquivos>`).
- **Frentes em paralelo (pontos de conflito):** B4.2 (SLA) toca o mesmo `lib/tasks/ramon_fluxos.rake`, provavelmente `contexto.rb`/`relogio.rb`/`executor.rb`/`grafo.rb`/`passos/*`, `fluxo.js`, `validar.js`, `PainelPasso.vue`, `ConfigGatilho.vue`, os 2 `ramon.json` e a spec — por isso a B4.3 rebaseia **depois** dela (Task 0). B4.4+B4.5 (wt-fluxos-b44) rebaseiam depois desta. A3/A4 não tocam fluxos.

## Review Focus

1. **A chave meio ligada ou virada no meio do dia** (env ligada com o fluxo ainda parado; fluxo em `normal` com a env desligada; fluxo desligado na tela; rake às 11h30 depois de um lote já feito) — o lote do dia sai **por um lado só**: nunca pelos dois, nunca por nenhum quando a chave está inteira. Teste: Task 4 ("só assume com a env ligada…") e Task 5 ("fluxo em modo normal mas sem a env…", "às 11h o fluxo faz a retomada inteira e o código não faz nada").
2. **Lead que o código acabou de retomar, no dia da virada** (tarefa de retomada aberta ou última retomada há menos de 5 dias) — o fluxo lê a **mesma regra** (`custom_attributes.follow_up` + tarefa aberta), não o histórico de execuções, e não repete. Teste: Task 2 ("retomada: todo dia para quem segue parado e pode…") e Task 5 ("a virada não repete…").
3. **Data envenenada em `follow_up.ultima_em`** (a API grava qualquer coisa no jsonb) — conta como "nunca", não derruba o lote nem o relógio. Teste: Task 1 ("data envenenada…").
4. **IA fora do ar às 11h** — entra o texto fixo de reserva (como o código), a tarefa e o contador seguem; nada de 15 falhas com 15 sinos e 15 pushes de "Fluxo falhou". Teste: Task 3 ("IA fora do ar → o texto de reserva…") e Task 5 ("IA fora do ar: entra o texto fixo…").
5. **Clique duplo no "Preparar retomada"**, ou botão no mesmo minuto do lote — 1 rascunho só; o botão não respeita o teto (como hoje). Teste: Task 5 ("o botão Preparar retomada roda o fluxo para o lead, sem o teto; o clique duplo não gera 2").

---

## Como o fluxo fica fiel ao código (decisões de desenho)

### O que o código faz × o que o fluxo faz

| O código faz hoje (`Ramon::FollowUpDraftService`, `DailyFollowUpJob`, `FollowUpDraftJob`) | O fluxo "Cadência de retomada" faz (B4.3) |
|---|---|
| 11:00 SP, todo dia (cron `0 14 * * *`), toda conta | gatilho `lead_parado {hora: '11:00', retomada: true}` — o relógio dos fluxos, 1×/dia por fluxo (`ultimo_disparo_em`) |
| parados = `LeadRadar.stalled_leads` (leads abertos, regra de cada etapa), **todo dia enquanto seguirem parados** | `retomada: true` troca o "1 vez por parada" (§13) por "todo dia enquanto seguir parado" |
| elegível = tem conversa · nenhuma tarefa `follow_up` aberta · última retomada há ≥ 5 dias (data envenenada = nunca) | a mesma função, `Ramon::Fluxos::Retomada.motivo(lead)`, lead a lead, antes de disparar (lead inelegível nem vira execução — não come o teto nem enche a lista de execuções) |
| teto 15 por conta, na ordem do radar (`default_scope`: etapa, posição, id) | `limite_dia: 15` no fluxo (o relógio já para no limite) + a mesma ordem (o grupo da retomada não reordena por id) |
| rascunho LLM (prompt próprio, ângulo pela tentativa, tese, dias parado, conversa) → **nota do lead** `RASCUNHO (revisar antes de enviar) — retomada nº N:` | `rascunho_ia {onde: notas_do_lead, titulo: 'retomada nº {tentativa}', instrucao: <os ângulos do código com {tentativa} e {dias_parado}>}` |
| IA falhou → texto fixo "Oi <nome>, tudo bem? Passando pra saber…" | `rascunho_ia {reserva: 'Oi {nome}, tudo bem? Passando pra saber…'}` (mesmo texto) |
| tarefa `follow_up` "Retomada nº N", vence hoje | `criar_tarefa {tipo: follow_up, titulo: 'Retomada nº {tentativa}', prazo_dias: 0}` (vence 23:59 SP; dono = Closer, senão SDR — Decisão N2) |
| contador `custom_attributes.follow_up = {tentativas, ultima_em}` (relê antes, só a chave) | passo novo `registrar_retomada` (a mesma `Retomada.registrar!`) — devolve `{tentativa}` = o nº gravado aos passos seguintes |
| nota + tarefa + contador numa transação | ordem rascunho → **registrar** → tarefa: se a tarefa falhar 3×, o contador já protege de repetir por 5 dias; o executor grava a cada passo (queda não repete o feito) |
| balão de evento "⟳ Cadência do hub preparou o rascunho de retomada nº N — revise e envie pelo painel." | o executor já põe balão para os passos visíveis: `registrar_retomada` ("rascunho de retomada nº N pronto nas notas do lead — revise e envie pelo painel") e `criar_tarefa` (E3) |
| 1 push por conta no fim do lote, com o total, só com `NTFY_TOPIC` | `avisar_push {uma_vez_por_dia: true}`: só a 1ª execução do fluxo no dia avisa, sem o total (E3); o `NtfyPushJob` já não faz nada sem `NTFY_TOPIC` |
| botão "Preparar retomada" → `FollowUpDraftJob` → mesmas regras, **sem o teto** | com o fluxo no comando, o job roda o fluxo para aquele lead (`Retomada.disparar`), sem o teto, revendo a regra (clique duplo) — Decisão N1 |

O desenho do sistema dizia o que ele não conseguia mostrar; cada item fecha assim: "o Se só confere conversa" → a regra inteira mora no gatilho (`retomada`); "roda todo dia" → `retomada`; "teto 15 na ordem do radar" → `limite_dia` + ordem; "rascunho nas notas / texto fixo" → `onde` + `reserva`; "contador em `follow_up`" → `registrar_retomada`; "balão e 1 push" → executor + `uma_vez_por_dia`.

### A chave (direto, sem sombra)

- `Retomada.assumiu?(conta)` = `RAMON_FLUXO_CADENCIA=on` **e** existe o fluxo `origem: usuario`, `sistema_chave: 'cadencia'`, ligado, publicado, `modo: normal`, gatilho `lead_parado`. É lido em 3 lugares, sempre a mesma função: o `DailyFollowUpJob` (pula a conta), o `FollowUpDraftJob` (o botão vai para o fluxo) e o `Relogio` (o fluxo migrado só dispara com ela; senão nem ensaia — evita até 500 execuções-ensaio por dia).
- **O limite do dia é parte da cadência** (é o teto 15), ao contrário da B4.1 (lá um limite devolvia o comando ao código). Apagar o limite na tela = sem teto (até 500 leads/dia por fluxo; o teto de IA dos fluxos, `RAMON_FLUXO_IA_DIA` = 200, segura) — edição de admin (E6 da B4.1).
- **Virada no meio do dia:** o relógio reivindica o dia **antes** de olhar a chave. Se às 11h o código estava no comando, ele fez o lote e o fluxo marcou o dia sem disparar; virar às 11h30 não roda um 2º lote. Se às 11h o fluxo estava no comando, o código pulou a conta; voltar às 11h30 não roda o código de novo (o cron é das 11h). Mesmo num empate de segundos, a regra única (tarefa aberta + 5 dias) impede repetir o mesmo lead.
- `sistema_chave` = `'cadencia'` (o mesmo nome do desenho do sistema; a origem diferente separa). Enquanto parado, o fluxo aparece na lista com o selo "em sombra" da B4.1 (quer dizer "quem faz é o código") — Task 0 adota o selo que a B4.2 tiver criado para "migrado parado", se houver.

### Por que um passo novo e não o "Preencher campo"

`preencher_campo` grava em `custom_attributes['campos']` (nunca na raiz) e o contador da retomada mora em `custom_attributes['follow_up']` — que o card, o banner do painel (`follow_up_count`/`follow_up_last_at`), o Watchdog e a regra dos 5 dias leem. Um passo próprio (`registrar_retomada`, sem configuração, como o `apagar_reuniao` da B4.1) grava exatamente o que o código grava.

## Mapa de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `app/services/ramon/fluxos/retomada.rb` (novo) | regras únicas (`motivo`, `ultima_em`, `tentativa`, `dias_parado`, `registrar!`, `TETO`, `INTERVALO_DIAS`) + a chave (`ligada?`, `migrado?`, `fluxo`, `assumiu?`, `teto`, `disparar`, `semear`, `criar`, `mudar_modo!`, `descrever`) — ou delegações ao módulo comum da B4.2 (Task 0) |
| `app/services/ramon/fluxos/passos/retomada.rb` (novo) | passo `registrar_retomada` |
| `db/seeds/ramon/fluxos/migrados/cadencia.json` (novo) | o desenho fiel ao código |
| `app/services/ramon/follow_up_draft_service.rb` | usa as regras únicas (mesmo comportamento) |
| `app/controllers/api/v1/accounts/leads_controller.rb` | `follow_up_draft` lê `Retomada.motivo` (1 linha trocada) |
| `app/jobs/ramon/daily_follow_up_job.rb`, `app/jobs/ramon/follow_up_draft_job.rb` | obedecem a chave |
| `app/controllers/api/v1/accounts/ramon_watchdog_controller.rb` | teto e intervalo vêm de `Retomada` (o teto em vigor) |
| `app/services/ramon/fluxos/relogio.rb` | `lead_parado {retomada}` + o fluxo migrado só com a chave |
| `app/services/ramon/fluxos/contexto.rb` | `{tentativa}`, `{dias_parado}` |
| `app/services/ramon/fluxos/passos/{ia,conversa,aviso}.rb` | `rascunho_ia {onde, titulo, reserva}`, título com variável, push 1×/dia |
| `app/services/ramon/fluxos/{executor,grafo}.rb` | registram o passo novo |
| `lib/tasks/ramon_fluxos.rake` | `ramon:fluxos:cadencia:{criar,modo}` (ou o rake comum da B4.2) |
| `.env.example` | documenta `RAMON_FLUXO_CADENCIA` |
| `app/javascript/dashboard/routes/dashboard/captain/automacoes/{fluxo.js,validar.js,ConfigGatilho.vue,ConfigIa.vue,PainelPasso.vue}` + i18n `{en,pt_BR}/ramon.json` | o editor entende tudo isso |
| `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` | notas da B4.3 |

---

### Task 0: Alinhar com a B4.2

A B4.2 (SLA) foi planejada em paralelo e deve generalizar a chave/semeadura da B4.1 para "fluxos migrados". Esta task decide **qual variante** a Task 4 usa. Nenhuma outra task muda de interface: todas usam os nomes públicos de `Ramon::Fluxos::Retomada` listados no Mapa.

**Files:** nenhum (só leitura e rebase).

- [ ] **Step 1: Rebasear na B4.2**

```bash
git fetch origin
git log origin/ramon --oneline -15
```
Expected: o commit de merge da B4.2 (assunto com "B4.2" ou "SLA" em `feat(fluxos)`) aparece. **Se não aparecer, pare e avise:** a B4.3 não começa antes da B4.2 entrar. Com ela no ar:

```bash
git rebase origin/ramon
git log --oneline -3
```

- [ ] **Step 2: Ler o que a B4.2 deixou**

```bash
ls app/services/ramon/fluxos/ db/seeds/ramon/fluxos/migrados/
grep -rn "RAMON_FLUXO_" app lib .env.example
grep -n "namespace\|desc " lib/tasks/ramon_fluxos.rake
grep -n "^## " docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md
git diff 079a04c --stat -- app/services/ramon/fluxos app/javascript/dashboard/routes/dashboard/captain/automacoes lib/tasks
```
Ler por inteiro o módulo novo da B4.2 (provavelmente algo como `Ramon::Fluxos::Migrados`/`Migracao` ao lado de `reunioes.rb`), o rake e a seção nova da spec (§16).

- [ ] **Step 3: Escolher a variante**

**Variante A — existe módulo comum de "fluxos migrados":**
- Na Task 4, registrar a cadência nele (env `RAMON_FLUXO_CADENCIA`, `sistema_chave` `'cadencia'` → gatilho `'lead_parado'`, JSON `migrados/cadencia.json`, nasce com `limite_dia: 15`) e reduzir a parte "chave" de `Ramon::Fluxos::Retomada` a **delegações com os mesmos nomes** (`ligada?`, `migrado?`, `fluxo`, `assumiu?`, `semear`, `mudar_modo!`, `descrever`); `teto` e `disparar` ficam em `Retomada` (são da cadência). Exemplo (adaptar ao nome/assinatura reais):

```ruby
  def assumiu?(account) = Ramon::Fluxos::Migrados.assumiu?(account, :cadencia)
  def semear(account) = Ramon::Fluxos::Migrados.semear(account, :cadencia).first
```
- **Se o módulo comum copiou a regra da B4.1 "limite do dia devolve ao código" (`limite_dia: nil` no `assumiu?`), torná-la opção por registro** (a cadência aceita limite — é o teto 15) e acrescentar 1 exemplo no spec do módulo comum provando que a cadência com `limite_dia: 15` assume.
- Se a B4.2 criou rake genérico (ex.: `ramon:fluxos:migrados:{criar,modo}[conta,nome]`), **não** criar `namespace :cadencia` na Task 4: usar o genérico e trocar os comandos da Operação/PR (Task 7). Se a B4.2 criou um selo próprio para "migrado parado", não mexer no selo.
- Os specs da Task 4 continuam como estão (testam os nomes públicos de `Retomada`).

**Variante B — não existe módulo comum (a B4.2 fez o seu à parte, como a B4.1):**
- A Task 4 cria o mínimo em `Retomada` exatamente como escrito lá (espelho do `Reunioes`), com rake `ramon:fluxos:cadencia:{criar,modo}`.

Em ambas: se a B4.2 já gravou o passo de horário configurável, **não usar** (Escopo 6).

- [ ] **Step 4: Medir o baseline do front depois do rebase**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts
```
Anotar "N arquivos / M testes" (em 079a04c: 15 / 180). A Task 6 soma **+7 testes** a esse número.

- [ ] **Step 5: Anotar a decisão** — sem commit; a variante escolhida, o nome do módulo comum (se houver), o nº da seção livre da spec (§16 se a B4.2 não escreveu nenhuma; senão a seguinte) e o baseline vão no relatório final e na mensagem do commit da Task 4.

---

### Task 1: Regras únicas da retomada (`Ramon::Fluxos::Retomada`) + o código usa elas

**Files:**
- Create: `app/services/ramon/fluxos/retomada.rb`
- Modify: `app/services/ramon/follow_up_draft_service.rb` (constantes, `ineligibility`, `draft_for`, `user_prompt`; apagar `last_follow_up_at`, `days_stalled`, `register_attempt`)
- Modify: `app/controllers/api/v1/accounts/leads_controller.rb:46` (1 linha)
- Test: `spec/services/ramon/fluxos/retomada_spec.rb` (novo); `spec/services/ramon/follow_up_draft_service_spec.rb` e `spec/controllers/api/v1/accounts/leads_controller_spec.rb` (sem mudança — trava do refactor)

**Interfaces:**
- Produces: `Ramon::Fluxos::Retomada::TETO = 15`; `::INTERVALO_DIAS = 5`; `.motivo(lead) → nil | Hash` (`{reason: 'no_conversation'}`, `{reason: 'open_follow_up'}`, `{reason: 'recent_follow_up', last_at:, days_ago:, min_gap_days:}` — o mesmo hash do `ineligibility` de hoje); `.ultima_em(lead) → Time | nil`; `.tentativa(lead) → Integer` (a próxima: contadas + 1); `.dias_parado(lead) → Integer`; `.registrar!(lead) → Integer` (relê, grava `follow_up = {tentativas, ultima_em}` e devolve o nº gravado).

- [ ] **Step 1: Write the failing test** — criar `spec/services/ramon/fluxos/retomada_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Retomada do
  # A conta seeda o funil no after_create (Leads::SeedDefaultConfigService); 'Novo' tem stalled_after_days.
  let(:account) { create(:account) }
  let(:novo) { account.lead_stages.find_by(name: 'Novo') }
  let(:contato) { create(:contact, account: account, name: 'Maria da Silva') }
  let(:conversa) { create(:conversation, account: account, contact: contato) }
  let(:lead) { create(:lead, account: account, lead_stage: novo, name: 'Maria da Silva', contact: contato, conversation: conversa) }

  describe 'regras únicas (código e fluxo)' do
    it 'pode retomar: com conversa, sem retomada aberta e a última há 5 dias ou mais' do
      expect(described_class.motivo(lead)).to be_nil
      lead.update!(custom_attributes: { 'follow_up' => { 'tentativas' => 1, 'ultima_em' => 6.days.ago.iso8601 } })
      expect(described_class.motivo(lead)).to be_nil
      lead.update!(custom_attributes: { 'follow_up' => { 'tentativas' => 1, 'ultima_em' => 2.days.ago.iso8601 } })
      expect(described_class.motivo(lead)).to include(reason: 'recent_follow_up', days_ago: 2, min_gap_days: 5)
    end

    it 'não pode: sem conversa, ou com tarefa de retomada aberta' do
      expect(described_class.motivo(create(:lead, account: account))).to eq(reason: 'no_conversation')
      create(:lead_task, account: account, lead: lead, kind: 'follow_up', due_at: 1.day.from_now)
      expect(described_class.motivo(lead)).to eq(reason: 'open_follow_up')
    end

    it 'data envenenada no jsonb conta como "nunca" (não derruba o lote)' do
      lead.update!(custom_attributes: { 'follow_up' => { 'tentativas' => 2, 'ultima_em' => 'não é data' } })
      expect(described_class.ultima_em(lead)).to be_nil
      expect(described_class.motivo(lead)).to be_nil
      expect(described_class.tentativa(lead)).to eq(3)
    end

    it 'registrar conta a tentativa e a data sem apagar as outras chaves do lead' do
      lead.update!(custom_attributes: { 'follow_up' => { 'tentativas' => 1 }, 'campos' => { 'x' => '1' } })
      expect(described_class.registrar!(lead)).to eq(2)
      attrs = lead.reload.custom_attributes
      expect(attrs['follow_up']['tentativas']).to eq(2)
      expect(Time.zone.parse(attrs['follow_up']['ultima_em'])).to be_within(5.seconds).of(Time.current)
      expect(attrs['campos']).to eq('x' => '1')
    end

    it 'dias parado: dias desde que entrou na etapa (0 sem data)' do
      lead.update_columns(stage_entered_at: 4.days.ago) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.dias_parado(lead)).to eq(4)
      lead.update_columns(stage_entered_at: nil) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.dias_parado(lead)).to eq(0)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails** — sem Ruby local: rastrear à mão; o CI acusaria `NameError: uninitialized constant Ramon::Fluxos::Retomada`.

- [ ] **Step 3: Write minimal implementation** — criar `app/services/ramon/fluxos/retomada.rb`:

```ruby
# B4.3 (spec §8): a cadência de retomada (W4) saindo do código para um fluxo, direto (sem sombra). As regras da retomada
# moram aqui, uma vez só, e valem para os dois lados — o código (Ramon::FollowUpDraftService, o botão "Preparar retomada")
# e o fluxo (gatilho "Lead parado" com retomada + passo "Registrar a retomada").
module Ramon::Fluxos::Retomada
  TETO = 15 # retomadas por dia por conta (o limite do dia com que o fluxo nasce)
  INTERVALO_DIAS = 5 # entre uma retomada e a próxima do mesmo lead

  module_function

  # Por que o lead NÃO pode receber retomada agora (nil = pode) — o painel explica o motivo (422 do follow_up_draft).
  def motivo(lead)
    return { reason: 'no_conversation' } if lead.conversation_id.blank?
    return { reason: 'open_follow_up' } if lead.lead_tasks.open_tasks.exists?(kind: 'follow_up')

    ultima = ultima_em(lead)
    return if ultima.nil? || ultima <= INTERVALO_DIAS.days.ago

    { reason: 'recent_follow_up', last_at: ultima.iso8601,
      days_ago: (Time.zone.today - ultima.to_date).to_i, min_gap_days: INTERVALO_DIAS }
  end

  # Data venenosa (a API grava qualquer coisa no jsonb) → nil, tratada como "nunca".
  def ultima_em(lead)
    valor = lead.custom_attributes.dig('follow_up', 'ultima_em')
    return if valor.blank?

    Time.zone.parse(valor.to_s)
  rescue ArgumentError
    nil
  end

  # A próxima retomada do lead (as contadas + 1).
  def tentativa(lead) = lead.custom_attributes.dig('follow_up', 'tentativas').to_i + 1

  def dias_parado(lead) = lead.stage_entered_at.blank? ? 0 : (Time.zone.today - lead.stage_entered_at.to_date).to_i

  # Conta a retomada (o contador do card, do banner e do Watchdog). Lição lost update: relê e escreve SÓ a chave follow_up.
  def registrar!(lead)
    lead.reload
    numero = tentativa(lead)
    follow_up = { 'tentativas' => numero, 'ultima_em' => Time.current.iso8601 }
    lead.update!(custom_attributes: lead.custom_attributes.merge('follow_up' => follow_up))
    numero
  end
end
```

E em `app/services/ramon/follow_up_draft_service.rb`:
1. Trocar as constantes:

```ruby
  DAILY_CAP = Ramon::Fluxos::Retomada::TETO
  MIN_GAP_DAYS = Ramon::Fluxos::Retomada::INTERVALO_DIAS
```
2. Trocar o método público `ineligibility` (e o comentário acima dele) por:

```ruby
  # Por que o lead NÃO pode receber retomada agora (nil = pode). A regra mora em Ramon::Fluxos::Retomada (B4.3: a mesma
  # do fluxo da cadência); o controller checa antes de enfileirar.
  def ineligibility(lead) = Ramon::Fluxos::Retomada.motivo(lead)
```
3. Apagar `last_follow_up_at`, `days_stalled` e `register_attempt` (e os comentários deles).
4. Em `draft_for`, `attempt = Ramon::Fluxos::Retomada.tentativa(lead)` e, dentro da transação, `Ramon::Fluxos::Retomada.registrar!(lead)` no lugar de `register_attempt(lead, attempt)`.
5. Em `user_prompt`, `"Lead parado há #{Ramon::Fluxos::Retomada.dias_parado(lead)} dias sem avanço."`.

Em `app/controllers/api/v1/accounts/leads_controller.rb:46`:

```ruby
    motivo = Ramon::Fluxos::Retomada.motivo(@lead)
```

- [ ] **Step 4: Run test to verify it passes** — rastrear à mão os 5 exemplos novos e os 11 de `follow_up_draft_service_spec.rb` (mesmos textos, mesmo contador: `registrar!` relê dentro da transação, como o `register_attempt` fazia) e os 5 do `follow_up_draft` em `leads_controller_spec.rb` (o mesmo hash de motivo). Conferir: `grep -n "last_follow_up_at\|register_attempt\|days_stalled" app spec` → vazio.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/retomada.rb app/services/ramon/follow_up_draft_service.rb app/controllers/api/v1/accounts/leads_controller.rb spec/services/ramon/fluxos/retomada_spec.rb
git commit -m "refactor(fluxos): regras únicas da retomada (Ramon::Fluxos::Retomada) — o código passa a usá-las" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 2: Motor — "Lead parado" com retomada (todo dia, a regra do código, na ordem do funil) + `{tentativa}` e `{dias_parado}`

**Files:**
- Modify: `app/services/ramon/fluxos/relogio.rb` (`disparar_do_dia` → extrai `disparar_grupo`; `parados`)
- Modify: `app/services/ramon/fluxos/contexto.rb` (`RESERVADAS`, `dados`, `dados_retomada`)
- Test: `spec/services/ramon/fluxos/relogio_spec.rb`, `spec/services/ramon/fluxos/passos_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Fluxos::Retomada.motivo/tentativa/dias_parado` (Task 1).
- Produces: config de gatilho `lead_parado` `'retomada' => true`; `Ramon::Fluxos::Relogio.disparar_grupo(fluxo, config, agora)` (a Task 5 só acrescenta 1 linha antes dela); variáveis `'tentativa'` (Integer) e `'dias_parado'` (Integer) em `Contexto#dados` (as `vars` da execução continuam vencendo: o passo da Task 3 devolve `{'tentativa' => n}`).

- [ ] **Step 1: Write the failing tests** — em `spec/services/ramon/fluxos/relogio_spec.rb`, antes do último `end`:

```ruby
  describe 'lead parado com retomada (B4.3: a cadência)' do
    def parado_com_conversa(na_etapa = etapa)
      lead = create(:lead, account: account, lead_stage: na_etapa, conversation_id: create(:conversation, account: account).id)
      lead.update_columns(stage_entered_at: sp('2026-10-01 10:00')) # rubocop:disable Rails/SkipsModelValidations
      lead
    end

    it 'retomada: todo dia para quem segue parado e pode receber retomada (a regra do código, não 1 vez por parada)' do
      pode = parado_com_conversa
      create(:lead, account: account, lead_stage: etapa).update_columns(stage_entered_at: sp('2026-10-01 10:00')) # rubocop:disable Rails/SkipsModelValidations
      recente = parado_com_conversa
      recente.update!(custom_attributes: { 'follow_up' => { 'tentativas' => 1, 'ultima_em' => sp('2026-10-05 11:00').iso8601 } })
      fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_parado', 'retomada' => true }, nota))
      travel_to(sp('2026-10-07 11:00')) { described_class.disparar_do_dia }
      expect(fluxo.execucoes.pluck(:alvo_id)).to eq([pode.id]) # sem conversa e retomada há 2 dias ficam de fora
      fluxo.execucoes.update_all(status: 'concluida') # rubocop:disable Rails/SkipsModelValidations
      travel_to(sp('2026-10-10 11:00')) { described_class.disparar_do_dia }
      expect(fluxo.execucoes.where(alvo_id: pode.id).count).to eq(2) # segue parado (a nota não conta retomada) → de novo
      expect(fluxo.execucoes.where(alvo_id: recente.id).count).to eq(1) # 5 dias depois da última
    end

    it 'retomada: o limite do dia corta na ordem do funil (etapa, posição), como o radar do código' do
      cedo = etapa
      tarde = create(:lead_stage, account: account, stalled_after_days: 3, position: 1)
      parado_com_conversa(tarde) # lead de id menor, mas na etapa de id maior
      primeiro = parado_com_conversa(cedo)
      fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_parado', 'retomada' => true }, nota), limite_dia: 1)
      travel_to(sp('2026-10-07 11:00')) { described_class.disparar_do_dia }
      expect(fluxo.execucoes.pluck(:alvo_id)).to eq([primeiro.id])
    end

    it 'retomada: data envenenada no lead não derruba o relógio' do
      envenenado = parado_com_conversa
      envenenado.update!(custom_attributes: { 'follow_up' => { 'ultima_em' => 'não é data' } })
      fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_parado', 'retomada' => true }, nota))
      travel_to(sp('2026-10-07 11:00')) { described_class.disparar_do_dia }
      expect(fluxo.execucoes.pluck(:alvo_id)).to eq([envenenado.id])
    end
  end
```
Em `spec/services/ramon/fluxos/passos_spec.rb`, logo antes de `it 'RESERVADAS cobre toda chave que o Contexto monta sozinho'`:

```ruby
  it 'retomada: {tentativa} é a próxima (a contada + 1) e {dias_parado} os dias na etapa' do
    lead.update!(custom_attributes: { 'follow_up' => { 'tentativas' => 2 } })
    lead.update_columns(stage_entered_at: 4.days.ago) # rubocop:disable Rails/SkipsModelValidations
    expect(ctx.dados).to include('tentativa' => 3, 'dias_parado' => 4)
  end
```
(O exemplo `RESERVADAS cobre toda chave…` que já existe passa a exigir as duas chaves novas em `RESERVADAS`.)

- [ ] **Step 2: Run test to verify it fails** — rastrear: hoje `parados` aplica "1 vez por parada" e `reorder(:id)` (o 1º exemplo daria `[pode.id, <sem conversa>, recente.id]`; o 2º, o lead da etapa `tarde`); `dados` não tem `tentativa`.

- [ ] **Step 3: Write minimal implementation** — em `app/services/ramon/fluxos/relogio.rb`, trocar `disparar_do_dia` por:

```ruby
  def disparar_do_dia(agora = Time.find_zone!(Fluxo::ZONA).now)
    Fluxo.executaveis.where(gatilho_tipo: %w[relogio lead_parado]).includes(:versao_publicada).find_each do |fluxo|
      config = Ramon::Fluxos::Grafo.new(fluxo.versao_publicada.grafo).gatilho['config'] || {}
      next unless na_hora?(config, agora) && reivindicar_dia(fluxo, agora)

      disparar_grupo(fluxo, config, agora)
    end
  end

  def disparar_grupo(fluxo, config, agora)
    grupo(fluxo, config, agora).limit(MAX_LEADS).each do |lead|
      # ponytail: 1 count por lead; agregar se grupos grandes com limite virarem rotina
      break if fluxo.modo == 'normal' && fluxo.limite_atingido?
      # B4.3: retomada = a regra do código, lead a lead (em Ruby: a data do jsonb pode vir envenenada)
      next if config['retomada'] && Ramon::Fluxos::Retomada.motivo(lead)

      disparar(fluxo, lead)
    end
  end
```
E em `parados`, logo depois da linha `leads = dias.positive? ? … : Ramon::Cadencia.parados(leads, agora)`:

```ruby
    # B4.3: retomada = todo dia enquanto seguir parado (quem pode é decidido lead a lead) e na ordem do radar do código
    # (default_scope do Lead: etapa, posição, id) — sem o "1 vez por parada" e sem reordenar por id.
    return leads if config['retomada']

```
Atualizar o comentário do topo do arquivo: `# - lead_parado: … 1 vez por parada; com 'retomada' (B4.3), todo dia para quem pode receber retomada.`

Em `app/services/ramon/fluxos/contexto.rb`:
1. Em `RESERVADAS`, depois de `reuniao_de_pe horario_passou`, acrescentar `tentativa dias_parado` (quebrar a linha se passar de 150).
2. Em `dados`, incluir `dados_retomada` entre `dados_reuniao` e `dados_gatilho`:

```ruby
    @dados ||= campos_livres.merge(dados_lead, dados_funil, dados_conversa, dados_docs, dados_reuniao, dados_retomada, dados_gatilho,
                                   execucao.contexto['vars'] || {})
```
3. Método privado (depois de `dados_reuniao`):

```ruby
  # B4.3: {tentativa} = a próxima retomada do lead (as contadas + 1; o passo Registrar a retomada devolve, em vars, o nº que
  # gravou) e {dias_parado} = dias na etapa — as mesmas contas do código (Ramon::Fluxos::Retomada).
  def dados_retomada
    l = lead
    return {} if l.nil?

    { 'tentativa' => Ramon::Fluxos::Retomada.tentativa(l), 'dias_parado' => Ramon::Fluxos::Retomada.dias_parado(l) }
  end
```

- [ ] **Step 4: Run test to verify it passes** — rastrear: 1º exemplo, em 07/10 o grupo (sem "já") tem os 3 leads; o sem conversa e o `recente` (2 dias) saem pelo `motivo`; em 10/10 a execução antiga está `concluida`, `pode` entra de novo e `recente` (5 dias: `ultima <= 5.days.ago` em 10/10 11:00) entra. 2º: `default_scope` põe a etapa `cedo` (id menor) antes; limite 1 corta o resto. 3º: `ultima_em` nil → pode. Os exemplos antigos do relógio (sem `retomada`) não mudam. Complexidade de `disparar_do_dia` caiu (o `break`/`next` foram para `disparar_grupo`).

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/relogio.rb app/services/ramon/fluxos/contexto.rb spec/services/ramon/fluxos/relogio_spec.rb spec/services/ramon/fluxos/passos_spec.rb
git commit -m "feat(fluxos): gatilho Lead parado com retomada (todo dia, regra e ordem do código) + {tentativa} e {dias_parado}" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 3: Passos — "Registrar a retomada", rascunho da IA nas notas com título e texto de reserva, push uma vez por dia

**Files:**
- Create: `app/services/ramon/fluxos/passos/retomada.rb`
- Modify: `app/services/ramon/fluxos/passos/ia.rb` (`rascunho_ia`, novo `texto_da_ia`)
- Modify: `app/services/ramon/fluxos/passos/conversa.rb` (`rascunho_texto`, `cabecalho(config, ctx)`)
- Modify: `app/services/ramon/fluxos/passos/aviso.rb` (`avisar_push`, novo `primeiro_do_dia?`)
- Modify: `app/services/ramon/fluxos/executor.rb` (`VISIVEIS`, `PASSOS`), `app/services/ramon/fluxos/grafo.rb` (`TIPOS_PASSO`)
- Test: `spec/services/ramon/fluxos/passos_spec.rb`, `spec/services/ramon/fluxos/passos/ia_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Fluxos::Retomada.tentativa/registrar!` (Task 1), `{tentativa}` (Task 2).
- Produces: passo `registrar_retomada` (sem config) → `{saida: 's', vars: {'tentativa' => n}, resumo: "rascunho de retomada nº n pronto nas notas do lead — revise e envie pelo painel"}`; `rascunho_ia` aceita `onde` (`'notas_do_lead'`), `titulo` (com variáveis) e `reserva` (texto com variáveis); `Ramon::Fluxos::Passos::Conversa.cabecalho(config, ctx)` (agora com `ctx`); `avisar_push` aceita `uma_vez_por_dia: true` (chave Redis `RAMON::FLUXO_PUSH::<fluxo_id>::<AAAA-MM-DD SP>`, 2 dias).

- [ ] **Step 1: Write the failing tests** — em `spec/services/ramon/fluxos/passos_spec.rb`, antes do último `end`:

```ruby
  describe 'registrar a retomada (B4.3)' do
    it 'conta a tentativa no lead (o contador do painel) e devolve o nº aos passos seguintes' do
      lead.update!(custom_attributes: { 'follow_up' => { 'tentativas' => 1 } })
      r = Ramon::Fluxos::Passos::Retomada.registrar_retomada({}, ctx)
      expect(r[:vars]).to eq('tentativa' => 2)
      expect(r[:resumo]).to eq('rascunho de retomada nº 2 pronto nas notas do lead — revise e envie pelo painel')
      expect(lead.reload.custom_attributes['follow_up']['tentativas']).to eq(2)
    end

    it 'ensaio só descreve' do
      r = Ramon::Fluxos::Passos::Retomada.registrar_retomada({}, ctx(ensaio: true))
      expect(r[:resumo]).to eq('faria: registrar a retomada nº 1')
      expect(lead.reload.custom_attributes['follow_up']).to be_nil
    end
  end

  describe 'push uma vez por dia (B4.3)' do
    let(:dia) { Time.find_zone!('America/Sao_Paulo').parse('2026-10-07 11:00') }

    after { Redis::Alfred.delete("RAMON::FLUXO_PUSH::#{fluxo.id}::2026-10-07") }

    it 'só a 1ª execução do fluxo no dia avisa; as outras dizem que já saiu' do
      config = { 'texto' => 'Há rascunhos', 'uma_vez_por_dia' => true }
      outro = create(:lead, account: account)
      travel_to(dia) do
        expect { Ramon::Fluxos::Passos::Aviso.avisar_push(config, ctx) }.to have_enqueued_job(Ramon::NtfyPushJob)
        r = nil
        expect { r = Ramon::Fluxos::Passos::Aviso.avisar_push(config, ctx(alvo: outro)) }.not_to have_enqueued_job(Ramon::NtfyPushJob)
        expect(r[:resumo]).to eq('push: já saiu hoje (1 por dia)')
      end
    end
  end
```
Em `spec/services/ramon/fluxos/passos/ia_spec.rb`, antes do último `end`:

```ruby
  it 'rascunho_ia nas notas do lead, com título que aceita variável (a retomada da cadência)' do
    llm('Oi [nome], seguimos à disposição.')
    lead.update!(custom_attributes: { 'follow_up' => { 'tentativas' => 1 } })
    config = { 'instrucao' => 'retome', 'onde' => 'notas_do_lead', 'titulo' => 'retomada nº {tentativa}' }
    described_class.rascunho_ia(config, ctx)
    expect(lead.lead_notes.last.body).to eq("RASCUNHO (revisar antes de enviar) — retomada nº 2:\nOi Maria, seguimos à disposição.")
    expect(conversa.messages.where(private: true).count).to eq(0)
  end

  it 'rascunho_ia: IA fora do ar → o texto de reserva (como a cadência do código), sem nova tentativa' do
    allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::TransientError, 'timeout')
    r = described_class.rascunho_ia({ 'instrucao' => 'retome', 'reserva' => 'Oi {nome}, tudo bem?' }, ctx)
    expect(conversa.messages.last.content).to eq("#{Ramon::RascunhoCarimbo::PREFIXO}\nOi Maria, tudo bem?")
    expect(r[:saida]).to eq('s')
  end

  it 'rascunho_ia sem reserva: IA fora do ar sobe o erro (o executor tenta de novo em 1/5/15 min)' do
    allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::TransientError, 'timeout')
    expect { described_class.rascunho_ia({ 'instrucao' => 'retome' }, ctx) }.to raise_error(Ramon::LlmClient::TransientError)
  end
```

- [ ] **Step 2: Run test to verify it fails** — rastrear: `Passos::Retomada` não existe; `rascunho_ia` ignora `onde`/`titulo` (escreve na conversa com o prefixo puro) e não conhece `reserva`; `avisar_push` enfileira sempre.

- [ ] **Step 3: Write minimal implementation** — criar `app/services/ramon/fluxos/passos/retomada.rb`:

```ruby
# Passo da cadência de retomada (B4.3): conta a tentativa no lead — custom_attributes.follow_up, o mesmo contador do
# código (card, banner do painel, Watchdog e a regra dos 5 dias). Devolve o nº gravado em {tentativa} aos passos seguintes.
module Ramon::Fluxos::Passos::Retomada
  module_function

  def registrar_retomada(_config, ctx)
    lead = Ramon::Fluxos::Passos::Lead.exigir_lead(ctx)
    return { saida: 's', resumo: "faria: registrar a retomada nº #{Ramon::Fluxos::Retomada.tentativa(lead)}" } if ctx.ensaio?

    numero = Ramon::Fluxos::Retomada.registrar!(lead)
    { saida: 's', vars: { 'tentativa' => numero },
      resumo: "rascunho de retomada nº #{numero} pronto nas notas do lead — revise e envie pelo painel" }
  end
end
```
Em `app/services/ramon/fluxos/passos/conversa.rb`, o título passa a aceitar variável (`retomada nº {tentativa}`):

```ruby
    escrever(ctx, "#{cabecalho(config, ctx)}\n#{texto}", onde: config['onde'])
```
(em `rascunho_texto`) e

```ruby
  # "RASCUNHO (revisar antes de enviar):"; com título (B4.1; com variáveis desde a B4.3),
  # "RASCUNHO (revisar antes de enviar) — confirmação de reunião:" / "… — retomada nº 2:"
  def cabecalho(config, ctx)
    titulo = ctx.interpolar(config['titulo']).strip
    titulo.empty? ? Ramon::RascunhoCarimbo::PREFIXO : "#{Ramon::RascunhoCarimbo::PREFIXO.delete_suffix(':')} — #{titulo}:"
  end
```
Em `app/services/ramon/fluxos/passos/ia.rb`, trocar `rascunho_ia` por:

```ruby
  # B4.3: onde/título como o rascunho de texto (a retomada vai para as notas do lead, "— retomada nº N:") e `reserva`:
  # se a IA falhar, entra esse texto fixo na hora (como a cadência do código) em vez de tentar de novo.
  def rascunho_ia(config, ctx)
    instrucao = ctx.interpolar(config['instrucao'])
    return { saida: 's', resumo: "faria: rascunho da IA (#{instrucao.truncate(80)})" } if ctx.ensaio?

    cota!(ctx)
    texto = texto_da_ia(instrucao, config, ctx)
    conversa = Ramon::Fluxos::Passos::Conversa
    conversa.escrever(ctx, "#{conversa.cabecalho(config, ctx)}\n#{texto}", onde: config['onde'])
    { saida: 's', vars: { 'resposta_ia' => texto }, resumo: "rascunho da IA: #{texto.truncate(120)}" }
  end

  def texto_da_ia(instrucao, config, ctx)
    restaurar(perguntar(SISTEMA_RASCUNHO, "Instrução: #{instrucao}", ctx), ctx).strip
  rescue StandardError => e
    raise if config['reserva'].blank?

    Rails.logger.warn("[Ramon::Fluxos::Passos::Ia] rascunho_ia: IA falhou (#{e.class}) — texto de reserva")
    ctx.interpolar(config['reserva'])
  end
```
(O `cota!` fica fora do `rescue`: teto de IA estourado continua falhando na hora, com sino.)

Em `app/services/ramon/fluxos/passos/aviso.rb`, em `avisar_push`, depois da linha do ensaio:

```ruby
    return { saida: 's', resumo: 'push: já saiu hoje (1 por dia)' } if config['uma_vez_por_dia'] && !primeiro_do_dia?(ctx)
```
e o método:

```ruby
  # B4.3: "uma vez por dia" (a cadência do código mandava 1 push por lote): só a 1ª execução do fluxo no dia (fuso SP) avisa.
  def primeiro_do_dia?(ctx)
    chave = "RAMON::FLUXO_PUSH::#{ctx.execucao.fluxo_id}::#{Time.find_zone!(Fluxo::ZONA).today}"
    Redis::Alfred.set(chave, '1', nx: true, ex: 2.days.to_i)
  end
```
Em `app/services/ramon/fluxos/executor.rb`: `VISIVEIS` termina em `apagar_reuniao registrar_retomada].freeze`; em `PASSOS`, depois de `'apagar_reuniao' => Ramon::Fluxos::Passos::Reuniao,` acrescentar `'registrar_retomada' => Ramon::Fluxos::Passos::Retomada,`.
Em `app/services/ramon/fluxos/grafo.rb`: `TIPOS_PASSO` termina em `… preencher_campo apagar_reuniao registrar_retomada].freeze` (mesma linha; < 150).

- [ ] **Step 4: Run test to verify it passes** — rastrear: o `registrar_retomada` relê, grava 2 e devolve; no ensaio, `tentativa` = 1 e nada grava. `rascunho_ia` com `onde` cai em `lead_notes` (o lead tem conversa, mas `onde: notas_do_lead`); o título interpola `{tentativa}` = 2 (contadas 1 + 1). Reserva: `perguntar` levanta, `reserva` presente → `"Oi {nome}, tudo bem?"` com `{nome}` = 'Maria' (primeiro nome do contato) → nota privada na conversa (sem `onde`). Push: o 1º `set nx` devolve true; o 2º, false. Os exemplos antigos do `rascunho_texto`/`rascunho_ia` não mudam (título vazio → `PREFIXO`).

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/passos/retomada.rb app/services/ramon/fluxos/passos/ia.rb app/services/ramon/fluxos/passos/conversa.rb app/services/ramon/fluxos/passos/aviso.rb app/services/ramon/fluxos/executor.rb app/services/ramon/fluxos/grafo.rb spec/services/ramon/fluxos/passos_spec.rb spec/services/ramon/fluxos/passos/ia_spec.rb
git commit -m "feat(fluxos): passo Registrar a retomada, rascunho da IA nas notas com título e texto de reserva, push 1 vez por dia" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 4: O fluxo "Cadência de retomada" (desenho fiel) + a chave + o rake

**Files:**
- Create: `db/seeds/ramon/fluxos/migrados/cadencia.json`
- Modify: `app/services/ramon/fluxos/retomada.rb` (parte "chave" — Variante B abaixo; Variante A = delegações, Task 0)
- Modify: `lib/tasks/ramon_fluxos.rake` (namespace `cadencia` — só na Variante B sem rake genérico)
- Modify: `.env.example` (documenta `RAMON_FLUXO_CADENCIA`)
- Test: `spec/services/ramon/fluxos/retomada_spec.rb`

**Interfaces:**
- Consumes: Tasks 1–3 (o JSON só publica com `registrar_retomada`, `onde`/`titulo`/`reserva` e `uma_vez_por_dia` existindo).
- Produces: `Ramon::Fluxos::Retomada::CHAVE = 'cadencia'`, `::GATILHO = 'lead_parado'`, `::PASTA`; `.ligada? → Boolean`; `.migrado?(fluxo) → Boolean`; `.fluxo(account) → Fluxo | nil`; `.assumiu?(account) → Boolean`; `.teto(account) → Integer | nil`; `.disparar(lead) → FluxoExecucao | nil`; `.semear(account) → Fluxo`; `.criar(account) → Fluxo`; `.mudar_modo!(account, 'normal' | 'sombra') → Fluxo` (ArgumentError sem o fluxo, ou `normal` sem a env); `.descrever(account) → String`. Rake `ramon:fluxos:cadencia:criar[account_id]` e `ramon:fluxos:cadencia:modo[account_id,modo]`.

- [ ] **Step 1: Write the failing test** — em `spec/services/ramon/fluxos/retomada_spec.rb`, antes do último `end`:

```ruby
  describe 'a chave (RAMON_FLUXO_CADENCIA=on + o fluxo em modo normal)' do
    let!(:fluxo) { described_class.semear(account) }

    it 'semear cria o fluxo parado (modo sombra), ligado, publicado, com o teto do código — uma vez só' do
      expect(fluxo).to have_attributes(origem: 'usuario', sistema_chave: 'cadencia', modo: 'sombra', ativo: true,
                                       limite_dia: 15, gatilho_tipo: 'lead_parado')
      expect(fluxo.versao_publicada.grafo['nos'].first['config']).to eq('tipo' => 'lead_parado', 'hora' => '11:00', 'retomada' => true)
      fluxo.update!(nome: 'Minha cadência')
      expect(described_class.semear(account).id).to eq(fluxo.id)
      expect(fluxo.reload.nome).to eq('Minha cadência')
    end

    it 'só assume com a env ligada e o fluxo normal, ligado, publicado e com o gatilho Lead parado' do
      expect(described_class.assumiu?(account)).to be(false)
      with_modified_env(RAMON_FLUXO_CADENCIA: 'on') do
        expect(described_class.assumiu?(account)).to be(false) # ainda parado
        described_class.mudar_modo!(account, 'normal')
        expect(described_class.assumiu?(account)).to be(true)
        fluxo.update!(ativo: false)
        expect(described_class.assumiu?(account)).to be(false) # desligado na tela devolve ao código
      end
      fluxo.update!(ativo: true)
      expect(described_class.assumiu?(account)).to be(false) # sem a env
    end

    it 'virar para normal sem a env é recusado; voltar devolve ao código; o teto em vigor acompanha' do
      expect { described_class.mudar_modo!(account, 'normal') }.to raise_error(ArgumentError, /RAMON_FLUXO_CADENCIA/)
      with_modified_env(RAMON_FLUXO_CADENCIA: 'on') do
        described_class.mudar_modo!(account, 'normal')
        fluxo.reload.update!(limite_dia: 20)
        expect(described_class.teto(account)).to eq(20)
        expect(described_class.descrever(account)).to include('o FLUXO faz a cadência')
        described_class.mudar_modo!(account, 'sombra')
        expect(described_class.teto(account)).to eq(15)
        expect(described_class.descrever(account)).to include('o CÓDIGO faz a cadência')
      end
    end

    it 'o fluxo do sistema (desenho só-leitura) nunca é o migrado' do
      sistema = account.fluxos.create!(nome: 'x', origem: 'sistema', sistema_chave: 'cadencia', rascunho: {})
      expect(described_class.migrado?(sistema)).to be(false)
      expect(described_class.migrado?(fluxo)).to be(true)
    end
  end
```

- [ ] **Step 2: Run test to verify it fails** — rastrear: `semear` não existe.

- [ ] **Step 3: Write minimal implementation** — criar `db/seeds/ramon/fluxos/migrados/cadencia.json` (os textos ao cliente são cópia do código: os 3 ângulos de `FollowUpDraftService#angle_for` e o `fallback_message`):

```json
{
  "nome": "Cadência de retomada",
  "descricao": "Todo dia às 11h, para os leads parados que podem receber retomada (têm conversa, nenhuma tarefa de retomada aberta e a última retomada há 5 dias ou mais), até 15 por dia na ordem do funil: a IA escreve o rascunho de retomada nº N nas notas do lead (se a IA falhar, entra o texto fixo), conta a tentativa no lead, cria a tarefa Retomada nº N para hoje e avisa no celular uma vez por dia. O botão Preparar retomada do painel roda este mesmo fluxo para um lead, sem o teto. No lugar do código (B4.3): com o selo \"em sombra\", está parado e quem faz é o código.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"lead_parado","hora":"11:00","retomada":true},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"rascunho_ia","config":{"rotulo":"Rascunho de retomada nº N (nas notas do lead)","onde":"notas_do_lead","titulo":"retomada nº {tentativa}","instrucao":"Mensagem de retomada nº {tentativa} para um lead que parou de responder (parado há {dias_parado} dias sem avanço). Tom de médico de confiança: caloroso, acolhedor, simples, sem juridiquês e sem pressão. O ângulo muda com a tentativa — 1ª: lembrete leve e gentil de que estamos à disposição pra seguir com o caso; 2ª: agregue valor, traga UMA informação nova e útil sobre a tese/benefício em questão; 3ª em diante: faça uma pergunta direta sobre o interesse em seguir e deixe a porta aberta pra quando a pessoa quiser.","reserva":"Oi {nome}, tudo bem? Passando pra saber se você ainda tem interesse em olhar o seu caso com a gente. Qualquer coisa, estou por aqui!"},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"registrar_retomada","config":{"rotulo":"Conta a tentativa no lead"},"posicao":{"x":0,"y":300}},
      {"id":"n4","tipo":"criar_tarefa","config":{"rotulo":"Tarefa de retomada para hoje","titulo":"Retomada nº {tentativa}","tipo":"follow_up","prazo_dias":0},"posicao":{"x":0,"y":440}},
      {"id":"n5","tipo":"avisar_push","config":{"rotulo":"Push: retomadas prontas (1 por dia)","titulo":"Retomadas prontas pra revisar","texto":"Há rascunhos de retomada esperando revisão no hub","uma_vez_por_dia":true},"posicao":{"x":0,"y":580}}
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
**Variante B** — em `app/services/ramon/fluxos/retomada.rb`, acrescentar as constantes no topo (depois de `INTERVALO_DIAS`):

```ruby
  CHAVE = 'cadencia'.freeze # sistema_chave do fluxo (o mesmo nome do desenho só-leitura; a origem 'usuario' separa)
  GATILHO = 'lead_parado'.freeze
  PASTA = Rails.root.join('db/seeds/ramon/fluxos/migrados')
```
e, no fim do módulo (antes do último `end`):

```ruby
  # ---- A chave (B4.3, direto: sem sombra) -------------------------------------------------------------------------

  def ligada? = ENV.fetch('RAMON_FLUXO_CADENCIA', nil) == 'on'

  def migrado?(fluxo) = fluxo.origem == 'usuario' && fluxo.sistema_chave == CHAVE

  def fluxo(account) = account.fluxos.where(origem: 'usuario', sistema_chave: CHAVE).order(:id).first

  # O fluxo faz a cadência só com a env ligada E ele ligado, publicado, em modo normal e com o gatilho Lead parado.
  # Qualquer peça fora → o código faz e o relógio nem dispara o fluxo. O limite do dia é o teto da cadência (nasce 15).
  def assumiu?(account)
    ligada? && account.fluxos.executaveis.exists?(origem: 'usuario', sistema_chave: CHAVE, modo: 'normal', gatilho_tipo: GATILHO)
  end

  # O teto em vigor (Watchdog): com o fluxo no comando, o limite do dia dele (nil = sem teto); senão, o do código.
  def teto(account) = assumiu?(account) ? fluxo(account).limite_dia : TETO

  # Botão "Preparar retomada" com o fluxo no comando: roda o fluxo para ESTE lead, sem o teto (como o código), revendo a
  # regra (o clique duplo chega aqui 2 vezes). Execução viva no lead → nil (o índice único barra).
  def disparar(lead)
    return if motivo(lead)

    Ramon::Fluxos::Disparo.new(fluxo(lead.account), lead, {}, nil).iniciar
  end

  # normal = o fluxo assume a cadência; sombra = devolve ao código na hora (o fluxo fica parado — não ensaia).
  def mudar_modo!(account, modo)
    atual = fluxo(account) || raise(ArgumentError, 'O fluxo da cadência ainda não existe: rode ramon:fluxos:cadencia:criar')
    raise ArgumentError, 'Ligue RAMON_FLUXO_CADENCIA=on antes (sem ela o código continua fazendo a cadência)' if modo == 'normal' && !ligada?

    atual.update!(modo: modo)
    atual
  end

  def descrever(account)
    f = fluxo(account)
    quem = assumiu?(account) ? 'o FLUXO faz a cadência (o código não faz mais)' : 'o CÓDIGO faz a cadência (o fluxo fica parado)'
    return "O fluxo da cadência não existe.\nAgora #{quem}." if f.nil?

    "Fluxo ##{f.id} \"#{f.nome}\" — modo #{f.modo}, #{f.ativo ? 'ligado' : 'desligado'}, teto #{f.limite_dia || 'nenhum'}/dia\nAgora #{quem}."
  end

  # Cria (uma vez) parado (modo sombra), ligado, publicado e com o teto do código. Já existe → devolve sem tocar.
  def semear(account) = fluxo(account) || criar(account)

  def criar(account)
    dados = JSON.parse(PASTA.join("#{CHAVE}.json").read)
    Fluxo.transaction do
      novo = account.fluxos.create!(nome: dados['nome'], descricao: dados['descricao'], origem: 'usuario', sistema_chave: CHAVE,
                                    modo: 'sombra', ativo: true, limite_dia: TETO, rascunho: dados['desenho'])
      novo.publicar!(nil)
      novo.reload
    end
  end
```
Em `lib/tasks/ramon_fluxos.rake`, dentro de `namespace :fluxos`, depois do `namespace :reunioes … end`:

```ruby
    # B4.3 — a cadência de retomada pelo fluxo, direto (sem sombra). Operação: docs/superpowers/plans/2026-10-07-automacoes-fluxo-b43-cadencia.md
    namespace :cadencia do
      conta = ->(args) { Account.find(args[:account_id].presence || raise(ArgumentError, 'informe o account_id')) }

      desc 'Cria (uma vez) o fluxo da cadencia, PARADO (o codigo segue fazendo). Uso: rake ramon:fluxos:cadencia:criar[account_id]'
      task :criar, [:account_id] => :environment do |_task, args|
        account = conta.call(args)
        Ramon::Fluxos::Retomada.semear(account)
        puts Ramon::Fluxos::Retomada.descrever(account)
      end

      desc 'normal = o fluxo assume a cadencia (exige RAMON_FLUXO_CADENCIA=on); sombra = devolve ao codigo. ' \
           'Uso: rake ramon:fluxos:cadencia:modo[account_id,normal]'
      task :modo, [:account_id, :modo] => :environment do |_task, args|
        account = conta.call(args)
        Ramon::Fluxos::Retomada.mudar_modo!(account, args[:modo])
        puts Ramon::Fluxos::Retomada.descrever(account)
      end
    end
```
Em `.env.example`, ao lado de `RAMON_FLUXO_REUNIOES` (e da env da B4.2):

```
# B4.3: on + o fluxo "Cadência de retomada" em modo normal (rake ramon:fluxos:cadencia:modo) = o fluxo faz a cadência e o código para
RAMON_FLUXO_CADENCIA=
```
**Variante A** — no lugar da parte "chave" acima, registrar a cadência no módulo comum e delegar (Task 0, Step 3), mantendo `CHAVE`, `GATILHO`, `teto` e `disparar` em `Retomada`; o JSON e o `.env.example` são os mesmos.

- [ ] **Step 4: Run test to verify it passes** — rastrear: o JSON publica (gatilho válido com hora; `rascunho_ia` tem `instrucao`; `criar_tarefa` tem `titulo`; `avisar_push` tem `texto`; `registrar_retomada` está em `TIPOS_PASSO`; sem ciclo; tudo alcançável). `assumiu?` lê a coluna `gatilho_tipo` que o `publicar!` grava. No 3º exemplo, `fluxo.reload.update!(limite_dia: 20)` não desfaz o `modo: normal` (o reload pega o modo novo). `migrado?` recusa `origem: sistema`.

- [ ] **Step 5: Commit**

```bash
git add db/seeds/ramon/fluxos/migrados/cadencia.json app/services/ramon/fluxos/retomada.rb lib/tasks/ramon_fluxos.rake .env.example spec/services/ramon/fluxos/retomada_spec.rb
git commit -m "feat(fluxos): fluxo Cadência de retomada (desenho fiel ao código) + chave RAMON_FLUXO_CADENCIA + rake" -m "Variante da Task 0: <A com <módulo comum> | B>.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 5: O código obedece a chave + ponta a ponta

**Files:**
- Modify: `app/jobs/ramon/daily_follow_up_job.rb`, `app/jobs/ramon/follow_up_draft_job.rb`
- Modify: `app/services/ramon/fluxos/relogio.rb` (1 linha em `disparar_do_dia`)
- Modify: `app/controllers/api/v1/accounts/ramon_watchdog_controller.rb` (`thresholds`)
- Test: `spec/services/ramon/fluxos/retomada_spec.rb`; `spec/controllers/api/v1/accounts/ramon_watchdog_controller_spec.rb` (sem mudança — sem a chave, teto = 15)

**Interfaces:**
- Consumes: `Retomada.assumiu?/migrado?/disparar/teto/INTERVALO_DIAS` (Tasks 1 e 4), `Relogio.disparar_grupo` (Task 2).
- Produces: nada novo — comportamento.

- [ ] **Step 1: Write the failing test** — em `spec/services/ramon/fluxos/retomada_spec.rb`, antes do último `end`:

```ruby
  describe 'ponta a ponta' do
    let(:onze) { Time.find_zone!('America/Sao_Paulo').parse('2026-10-07 11:00') }
    let(:joao) { create(:contact, account: account, name: 'João Pereira') }
    let(:outro) do
      create(:lead, account: account, lead_stage: novo, name: 'João Pereira', contact: joao,
                    conversation: create(:conversation, account: account, contact: joao))
    end
    let!(:fluxo) { described_class.semear(account) }
    let(:reserva) do
      'Oi Maria, tudo bem? Passando pra saber se você ainda tem interesse em olhar o seu caso com a gente. Qualquer coisa, estou por aqui!'
    end

    before do
      [lead, outro].each { |l| l.update_columns(stage_entered_at: onze - 10.days) } # rubocop:disable Rails/SkipsModelValidations
      allow(Ramon::LlmClient).to receive(:complete)
        .and_return(Ramon::LlmClient::Result.new(content: 'Oi [nome], seguimos à disposição.', input_tokens: 1, output_tokens: 1))
    end

    after { Redis::Alfred.delete("RAMON::FLUXO_PUSH::#{fluxo.id}::2026-10-07") }

    # O relógio dos fluxos sem o resto: dispara o do dia e anda o que ficou na fila.
    def relogio
      Ramon::Fluxos::Relogio.disparar_do_dia
      andar
    end

    def andar = FluxoExecucao.where(status: 'esperando', retomar_em: ..Time.current).find_each { |e| Ramon::Fluxos::Executor.new(e).avancar! }

    def retomadas(alvo = lead) = alvo.lead_notes.where('body LIKE ?', 'RASCUNHO (revisar antes de enviar) — retomada%')

    describe 'com o fluxo no comando' do
      around { |ex| with_modified_env(RAMON_FLUXO_CADENCIA: 'on') { ex.run } }

      before { described_class.mudar_modo!(account, 'normal') }

      it 'às 11h o fluxo faz a retomada inteira e o código não faz nada' do
        allow(Ramon::FollowUpDraftService).to receive(:new).and_call_original
        travel_to(onze) do
          expect { relogio }.to have_enqueued_job(Ramon::NtfyPushJob).exactly(:once) # 2 leads, 1 push
          Ramon::DailyFollowUpJob.perform_now
        end
        expect(Ramon::FollowUpDraftService).not_to have_received(:new)
        expect(retomadas.pluck(:body)).to eq(["RASCUNHO (revisar antes de enviar) — retomada nº 1:\nOi Maria, seguimos à disposição."])
        expect(retomadas(outro).count).to eq(1)
        expect(lead.lead_tasks.where(kind: 'follow_up').pluck(:title)).to eq(['Retomada nº 1'])
        expect(lead.reload.custom_attributes['follow_up']['tentativas']).to eq(1)
        expect(fluxo.execucoes.where(ensaio: false).pluck(:status)).to eq(%w[concluida concluida])
      end

      it 'a virada não repete: respeita a retomada recente e a tarefa aberta que o código deixou' do
        lead.update!(custom_attributes: { 'follow_up' => { 'tentativas' => 2, 'ultima_em' => (onze - 2.days).iso8601 } })
        create(:lead_task, account: account, lead: outro, kind: 'follow_up', due_at: onze + 1.hour)
        travel_to(onze) { relogio }
        expect(retomadas.count + retomadas(outro).count).to eq(0)
        travel_to(onze + 3.days) { relogio }
        expect(retomadas.last.body).to start_with('RASCUNHO (revisar antes de enviar) — retomada nº 3:')
        expect(retomadas(outro).count).to eq(0) # a tarefa do código segue aberta
      end

      it 'o botão Preparar retomada roda o fluxo para o lead, sem o teto; o clique duplo não gera 2' do
        fluxo.reload.update!(limite_dia: 1)
        travel_to(onze - 2.hours) do
          Ramon::FollowUpDraftJob.perform_now(outro.id) # gasta o limite do dia
          2.times { Ramon::FollowUpDraftJob.perform_now(lead.id) }
          andar
          Ramon::FollowUpDraftJob.perform_now(lead.id) # já tem retomada aberta: nada
          andar
        end
        expect(retomadas.count).to eq(1)
        expect(retomadas(outro).count).to eq(1)
        expect(fluxo.execucoes.where(alvo: lead).count).to eq(1)
      end

      it 'IA fora do ar: entra o texto fixo de reserva e a retomada segue (contador e tarefa)' do
        allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::TransientError, 'timeout')
        travel_to(onze) { relogio }
        expect(retomadas.last.body).to eq("RASCUNHO (revisar antes de enviar) — retomada nº 1:\n#{reserva}")
        expect(lead.lead_tasks.where(kind: 'follow_up').count).to eq(1)
        expect(fluxo.execucoes.where(status: 'falhou').count).to eq(0)
      end
    end

    describe 'com o código no comando' do
      it 'fluxo em modo normal mas sem a env: o relógio nem dispara o fluxo; o lote e o botão são do código' do
        with_modified_env(RAMON_FLUXO_CADENCIA: 'on') { described_class.mudar_modo!(account, 'normal') }
        travel_to(onze) do
          relogio
          Ramon::DailyFollowUpJob.perform_now
        end
        expect(fluxo.execucoes.count).to eq(0)
        expect(retomadas.count).to eq(1) # o código fez
        expect(fluxo.reload.ultimo_disparo_em).to be_present # o dia ficou reivindicado: virar depois das 11h não roda 2º lote
      end
    end
  end
```

- [ ] **Step 2: Run test to verify it fails** — rastrear: sem as mudanças, o `DailyFollowUpJob` roda o código mesmo com a chave (1º exemplo: `FollowUpDraftService.new` recebido); o botão vai para o código; o relógio dispara o fluxo mesmo sem a env (último exemplo: 2 execuções).

- [ ] **Step 3: Write minimal implementation** — `app/jobs/ramon/daily_follow_up_job.rb`:

```ruby
class Ramon::DailyFollowUpJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_each do |account|
      next if Ramon::Fluxos::Retomada.assumiu?(account) # B4.3: o fluxo "Cadência de retomada" faz (Ramon::Fluxos::Relogio)

      Ramon::FollowUpDraftService.new(account: account).perform
    rescue StandardError => e
      # uma conta com dado venenoso não pode abortar as demais nem virar retry-loop
      Rails.logger.error("DailyFollowUpJob: conta #{account.id} falhou (#{e.class}: #{e.message})")
    end
  end
end
```
`app/jobs/ramon/follow_up_draft_job.rb`:

```ruby
class Ramon::FollowUpDraftJob < ApplicationJob
  queue_as :low

  def perform(lead_id)
    lead = Lead.find_by(id: lead_id)
    return if lead.blank?
    # B4.3: com o fluxo da cadência no comando, o botão "Preparar retomada" roda o fluxo para este lead
    return Ramon::Fluxos::Retomada.disparar(lead) if Ramon::Fluxos::Retomada.assumiu?(lead.account)

    Ramon::FollowUpDraftService.new(account: lead.account).perform_for(lead)
  end
end
```
`app/services/ramon/fluxos/relogio.rb`, em `disparar_do_dia`, entre o `next unless … reivindicar_dia(…)` e o `disparar_grupo(…)`:

```ruby
      # B4.3: o fluxo da cadência só roda com ele no comando; senão quem faz é o código (e o dia já ficou reivindicado:
      # virar a chave depois das 11h não roda um 2º lote no mesmo dia).
      next if Ramon::Fluxos::Retomada.migrado?(fluxo) && !Ramon::Fluxos::Retomada.assumiu?(fluxo.account)
```
`app/controllers/api/v1/accounts/ramon_watchdog_controller.rb`, em `thresholds`:

```ruby
      teto_diario: Ramon::Fluxos::Retomada.teto(Current.account),
      intervalo_minimo_dias: Ramon::Fluxos::Retomada::INTERVALO_DIAS,
```
e o comentário do topo: `# rascunho de retomada diário (Ramon::DailyFollowUpJob ou, desde a B4.3, o fluxo "Cadência de retomada", 11:00 BRT) e o copiloto`.

- [ ] **Step 4: Run test to verify it passes** — rastrear cada exemplo:
  1. Chave inteira: o relógio reivindica, `migrado?` e `assumiu?` → segue; os 2 leads entram (ordem do funil, limite 15); `andar` roda as 2 execuções: rascunho nas notas com "— retomada nº 1:", registrar (1), tarefa "Retomada nº 1" (com `{tentativa}` = 1 das vars), push só na 1ª. `DailyFollowUpJob` pula a conta → `FollowUpDraftService.new` nunca chamado.
  2. `lead`: retomada há 2 dias → fora; `outro`: tarefa aberta → fora. Em +3 dias (10/10): `lead` com 5 dias → entra, nº 3 (contadas 2 + 1); `outro` segue com a tarefa aberta (vence 07/10 12h, nunca concluída) → fora.
  3. Botão: `outro` cria a 1ª execução do dia (limite 1 atingido); `lead` 1ª vez cria a execução (`Disparo#iniciar` não olha limite); 2ª vez → `motivo` nil (ainda não andou) → `RecordNotUnique` → nil; `andar` faz as 2; 3ª vez → `open_follow_up` → nil. 1 rascunho por lead.
  4. IA fora: `texto_da_ia` cai na reserva com `{nome}` = 'Maria'; o resto segue; nenhuma execução falhou.
  5. Sem a env: o relógio reivindica o dia (`ultimo_disparo_em`) e pula o migrado; o código faz 1 retomada para `lead` (e outra para `outro`); o fluxo não tem execução.
  Conferir também `spec/controllers/api/v1/accounts/ramon_watchdog_controller_spec.rb:26` (`teto_diario == DAILY_CAP` = 15 sem a chave) e `spec/jobs/ramon/fluxo_relogio_job_spec.rb` (sem mudança).

- [ ] **Step 5: Commit**

```bash
git add app/jobs/ramon/daily_follow_up_job.rb app/jobs/ramon/follow_up_draft_job.rb app/services/ramon/fluxos/relogio.rb app/controllers/api/v1/accounts/ramon_watchdog_controller.rb spec/services/ramon/fluxos/retomada_spec.rb
git commit -m "feat(fluxos): a chave da cadência — lote das 11h, botão Preparar retomada e relógio obedecem RAMON_FLUXO_CADENCIA" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 6: Front — o editor entende a cadência

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js` (`PASSOS`, `PALETA`, `VARIAVEIS`)
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/validar.js` (`RESERVADAS`)
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/ConfigGatilho.vue` (caixa "Retomada")
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/ConfigIa.vue` (`rascunho_ia`: onde, título, reserva)
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/PainelPasso.vue` (push 1×/dia; ajuda do `registrar_retomada`)
- Modify: `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json`
- Test: `specs/PainelPasso.spec.js`, `specs/migrados.spec.js`, `specs/validar.spec.js` (pasta `app/javascript/dashboard/routes/dashboard/captain/automacoes/`)

**Interfaces:**
- Consumes: o contrato do back — gatilho `lead_parado.retomada` (Task 2), passo `registrar_retomada` sem config, `rascunho_ia.{onde,titulo,reserva}`, `avisar_push.uma_vez_por_dia` (Task 3), variáveis `tentativa`/`dias_parado` (Task 2), `db/seeds/ramon/fluxos/migrados/cadencia.json` (Task 4).
- Produces: nada para outras tasks.

- [ ] **Step 1: Write the failing tests** — em `specs/PainelPasso.spec.js`, antes do último `});`:

```js
  it('gatilho lead parado: retomada todo dia', async () => {
    const wrapper = montar({
      id: 'n1',
      data: { tipo: 'gatilho', config: { tipo: 'lead_parado' } },
    });
    await wrapper.find('[data-testid="gatilho-retomada"]').setValue(true);
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { tipo: 'lead_parado', retomada: true },
    ]);
  });

  it('rascunho da IA: nas notas do lead, com título e texto de reserva', async () => {
    const wrapper = montar({
      id: 'n2',
      data: { tipo: 'rascunho_ia', config: { instrucao: 'x' } },
    });
    await wrapper.find('[data-testid="ia-onde"]').setValue('notas_do_lead');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { instrucao: 'x', onde: 'notas_do_lead' },
    ]);
    await wrapper
      .find('[data-testid="ia-titulo"]')
      .setValue('retomada nº {tentativa}');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { instrucao: 'x', titulo: 'retomada nº {tentativa}' },
    ]);
    await wrapper.findAll('textarea').at(1).setValue('Oi {nome}');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { instrucao: 'x', reserva: 'Oi {nome}' },
    ]);
  });

  it('push: só uma vez por dia', async () => {
    const wrapper = montar({
      id: 'n5',
      data: { tipo: 'avisar_push', config: { texto: 'oi' } },
    });
    await wrapper.find('[data-testid="push-uma-vez"]').setValue(true);
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { texto: 'oi', uma_vez_por_dia: true },
    ]);
  });

  it('registrar a retomada: só explica (sem configuração)', () => {
    const wrapper = montar({
      id: 'n3',
      data: { tipo: 'registrar_retomada', config: {} },
    });
    expect(wrapper.text()).toContain('Conta a tentativa no lead');
  });
```
Em `specs/migrados.spec.js`: acrescentar o import junto dos outros

```js
import cadencia from '../../../../../../../../db/seeds/ramon/fluxos/migrados/cadencia.json';
```
e, no fim do arquivo:

```js
describe('fluxo migrado: cadência de retomada (B4.3)', () => {
  const RESERVA =
    'Oi {nome}, tudo bem? Passando pra saber se você ainda tem interesse em olhar o seu caso com a gente. Qualquer coisa, estou por aqui!';

  it('publica sem erro; gatilho Lead parado com retomada às 11h', () => {
    expect(validar(cadencia.desenho)).toEqual([]);
    expect(cadencia.desenho.nos[0].config).toEqual({
      tipo: 'lead_parado',
      hora: '11:00',
      retomada: true,
    });
  });

  it('rascunho da IA nas notas (título com o nº, reserva = texto fixo do código), conta, tarefa de hoje, push 1 por dia', () => {
    expect(cadencia.desenho.nos.map(n => n.tipo)).toEqual([
      'gatilho',
      'rascunho_ia',
      'registrar_retomada',
      'criar_tarefa',
      'avisar_push',
    ]);
    expect(doTipo(cadencia, 'rascunho_ia')[0].config).toMatchObject({
      onde: 'notas_do_lead',
      titulo: 'retomada nº {tentativa}',
      reserva: RESERVA,
    });
    expect(doTipo(cadencia, 'criar_tarefa')[0].config).toMatchObject({
      titulo: 'Retomada nº {tentativa}',
      tipo: 'follow_up',
      prazo_dias: 0,
    });
    expect(doTipo(cadencia, 'avisar_push')[0].config.uma_vez_por_dia).toBe(
      true
    );
  });
});
```
Em `specs/validar.spec.js`, depois do exemplo `'os nomes da reunião (B4.1) também são reservados no Preencher campo'` (dentro do mesmo `describe`):

```js
  it('os nomes da retomada (B4.3) também são reservados no Preencher campo', () => {
    ['tentativa', 'dias_parado'].forEach(chave =>
      expect(
        codigos(linear(p('p1', 'preencher_campo', { chave, valor: 'x' })))
      ).toEqual([['p1', 'CAMPO_CHAVE']])
    );
  });
```

- [ ] **Step 2: Run test to verify it fails**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/PainelPasso.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/migrados.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/validar.spec.js --config vitest.local.config.ts
```
Expected: FAIL — `gatilho-retomada`/`ia-onde`/`push-uma-vez` não existem; `validar(cadencia)` acusa tipo desconhecido `registrar_retomada`; `tentativa` não é reservada.

- [ ] **Step 3: Write minimal implementation**

`fluxo.js`:
1. Em `PASSOS`, depois de `apagar_reuniao: { … },`:

```js
  registrar_retomada: {
    grupo: 'LEAD',
    icone: 'i-lucide-repeat',
    tom: 'slate',
  },
```
2. Em `PALETA`, grupo `LEAD`, depois de `{ chave: 'apagar_reuniao', tipo: 'apagar_reuniao' },`:

```js
      { chave: 'registrar_retomada', tipo: 'registrar_retomada' },
```
3. Em `VARIAVEIS`, depois de `'primeiro_nome',`: `'tentativa',` e `'dias_parado',`.

`validar.js`: em `RESERVADAS`, depois de `'horario_passou',`: `'tentativa',` e `'dias_parado',` (espelho de `Contexto::RESERVADAS`).

`ConfigGatilho.vue`, logo depois do `<label v-if="config.tipo === 'lead_parado'" …>` do `DIAS_PARADO`:

```vue
    <template v-if="config.tipo === 'lead_parado'">
      <label class="flex items-center gap-2 text-[13px] text-n-slate-12">
        <input
          data-testid="gatilho-retomada"
          type="checkbox"
          class="reset-base"
          :checked="!!config.retomada"
          @change="muda('retomada', $event.target.checked || undefined)"
        />
        {{ t(`${K}.RETOMADA`) }}
      </label>
      <p class="text-xs text-n-slate-10">{{ t(`${K}.RETOMADA_AJUDA`) }}</p>
    </template>
```
(`trocaTipo` já descarta `retomada` ao trocar o gatilho.)

`ConfigIa.vue`: acrescentar `CAMPO` ao import de `dashboard/routes/dashboard/ramon/helpers/ui` e trocar o bloco `rascunho_ia` por:

```vue
    <template v-else-if="tipo === 'rascunho_ia'">
      <CampoTexto
        :rotulo="t(`${K}.INSTRUCAO`)"
        :model-value="config.instrucao || ''"
        @update:model-value="v => muda('instrucao', v)"
      />
      <p class="text-xs text-n-slate-10">{{ t(`${K}.INSTRUCAO_AJUDA`) }}</p>
      <label :class="ROTULO">
        {{ t(`${K}.ONDE_RASCUNHO`) }}
        <select
          data-testid="ia-onde"
          :class="SELECT"
          :value="config.onde || ''"
          @change="muda('onde', $event.target.value || undefined)"
        >
          <option value="">{{ t(`${K}.ONDE_CONVERSA`) }}</option>
          <option value="notas_do_lead">{{ t(`${K}.ONDE_NOTAS`) }}</option>
        </select>
      </label>
      <label :class="ROTULO">
        {{ t(`${K}.TITULO_RASCUNHO`) }}
        <input
          data-testid="ia-titulo"
          :class="CAMPO"
          :value="config.titulo || ''"
          @input="muda('titulo', $event.target.value)"
        />
      </label>
      <CampoTexto
        :rotulo="t(`${K}.RESERVA_IA`)"
        :linhas="2"
        :model-value="config.reserva || ''"
        @update:model-value="v => muda('reserva', v || undefined)"
      />
      <p class="text-xs text-n-slate-10">{{ t(`${K}.RESERVA_IA_AJUDA`) }}</p>
    </template>
```
`PainelPasso.vue`:
1. No `<template v-else-if="tipo === 'avisar_push'">`, depois do `CampoTexto`:

```vue
        <label class="flex items-center gap-2 text-[13px] text-n-slate-12">
          <input
            data-testid="push-uma-vez"
            type="checkbox"
            class="reset-base"
            :checked="!!config.uma_vez_por_dia"
            @change="marca('uma_vez_por_dia', $event.target.checked)"
          />
          {{ t(`${K}.PAINEL.UMA_VEZ_POR_DIA`) }}
        </label>
```
2. Depois do `<p v-else-if="tipo === 'apagar_reuniao'" …>…</p>`:

```vue
      <p
        v-else-if="tipo === 'registrar_retomada'"
        class="text-xs text-n-slate-10"
      >
        {{ t(`${K}.PAINEL.REGISTRAR_RETOMADA_AJUDA`) }}
      </p>
```
i18n — **mesma posição nos dois arquivos** (Edit, uma chave por vez):

| Bloco | Depois de | Chave | pt_BR | en |
|---|---|---|---|---|
| `FLUXOS.PASSOS` | `"apagar_reuniao"` | `registrar_retomada` | `Registrar a retomada` | `Log the follow-up` |
| `FLUXOS.CABECALHO` | `"apagar_reuniao"` | `registrar_retomada` | `Lead` | `Lead` |
| `FLUXOS.PALETA` | `"apagar_reuniao"` | `registrar_retomada` | `Registrar a retomada (conta a tentativa)` | `Log the follow-up (counts the attempt)` |
| `FLUXOS.PAINEL` | `"APAGAR_REUNIAO_AJUDA"` | `REGISTRAR_RETOMADA_AJUDA` | `Conta a tentativa no lead (o mesmo contador do painel e do botão Preparar retomada) e marca a data: a próxima retomada só depois de 5 dias. A variável tentativa segue com o número registrado.` | `Counts the attempt on the lead (the same counter as the panel and the Prepare follow-up button) and stamps the date: the next follow-up only after 5 days. The tentativa variable keeps the logged number.` |
| `FLUXOS.PAINEL` | `"REGISTRAR_RETOMADA_AJUDA"` | `UMA_VEZ_POR_DIA` | `Só uma vez por dia (a 1ª execução do dia avisa; as outras não)` | `Only once a day (the first run of the day notifies; the others do not)` |
| `FLUXOS.PAINEL` | `"INSTRUCAO_AJUDA"` | `RESERVA_IA` | `Texto se a IA falhar (opcional)` | `Text if the AI fails (optional)` |
| `FLUXOS.PAINEL` | `"RESERVA_IA"` | `RESERVA_IA_AJUDA` | `Vazio = tenta de novo em 1, 5 e 15 minutos e depois avisa a falha. Preenchido = usa este texto na hora, também como rascunho.` | `Empty = retries in 1, 5 and 15 minutes, then reports the failure. Filled = uses this text right away, also as a draft.` |
| `FLUXOS.PAINEL` | `"DIAS_PARADO_AJUDA"` | `RETOMADA` | `Retomada: todo dia enquanto seguir parado` | `Follow-up: every day while still stalled` |
| `FLUXOS.PAINEL` | `"RETOMADA"` | `RETOMADA_AJUDA` | `Só quem tem conversa, nenhuma tarefa de retomada aberta e a última retomada há 5 dias ou mais, na ordem do funil. Sem marcar: cada lead entra 1 vez por parada.` | `Only leads with a conversation, no open follow-up task and the last follow-up 5 or more days ago, in pipeline order. Unchecked: each lead enters once per stall.` |

- [ ] **Step 4: Run test to verify it passes**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts
./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes
```
Expected: baseline da Task 0 **+ 7 testes** (4 PainelPasso + 2 migrados + 1 validar), todos verdes — inclusive `i18n.spec.js` (ordem igual, sem `@ | { }`, compila), `fluxo.spec.js` ("todo passo que o motor roda está na paleta") e o `migrados.spec.js` antigo (a lista de tipos dos 3 fluxos de reunião não muda). ESLint sem `error`.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js app/javascript/dashboard/routes/dashboard/captain/automacoes/validar.js app/javascript/dashboard/routes/dashboard/captain/automacoes/ConfigGatilho.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/ConfigIa.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/PainelPasso.vue app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/PainelPasso.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/migrados.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/validar.spec.js
git commit -m "feat(fluxos): editor da cadência — Lead parado com retomada, rascunho da IA nas notas com reserva, push 1 vez por dia, Registrar a retomada" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 7: Verificação final + notas na spec + texto do PR

**Files:**
- Modify: `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (acrescentar a seção da B4.3 no fim, com o nº anotado na Task 0)

- [ ] **Step 1: Front inteiro**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts
./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes
git status --short
```
Expected: baseline + 7, verde; eslint sem `error`; `git status` não lista `vitest.local.config.ts`.

- [ ] **Step 2: Varredura de regras**

```bash
git diff origin/ramon --stat -- app/models/lead.rb app/services/ramon/advbox_event_processor.rb app/finders/conversation_finder.rb enterprise db/migrate db/schema.rb db/seeds/ramon/fluxos/sistema config/schedule.yml
grep -rn "last_follow_up_at\|register_attempt\|days_stalled" app spec
grep -rn "RAMON_FLUXO_CADENCIA" app lib .env.example
ls db/seeds/ramon/fluxos/migrados
```
Expected: o 1º vazio (nada nos 3 arquivos no limite, nada de migração, o desenho do sistema e o cron intactos — E5); o 2º vazio; a env em `retomada.rb` (ou no registro do módulo comum), no rake (se Variante B) e no `.env.example`; `cadencia.json` entre os migrados.

- [ ] **Step 3: Notas da B4.3 na spec** — acrescentar ao fim de `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (trocar `§N` pelo nº da Task 0):

```markdown
## §N. Notas da B4.3 (07/10/2026) — a cadência de retomada vira fluxo (direto)

- **Escopo (Eduardo, 07/10, o mesmo da B4.2):** direto, sem sombra nem comparação; teste ao vivo logo depois do deploy. Chave = `RAMON_FLUXO_CADENCIA=on` **e** o fluxo "Cadência de retomada" (`origem: usuario`, `sistema_chave: cadencia`) ligado, publicado, em `modo: normal`, gatilho `lead_parado` → o fluxo faz e o código para (o `DailyFollowUpJob` pula a conta; o botão "Preparar retomada" roda o fluxo). Qualquer peça fora → o código faz e o fluxo fica parado (o relógio nem o dispara). Virar = `rake ramon:fluxos:cadencia:modo[conta,normal]` (recusa sem a env); voltar = `…modo[conta,sombra]`, sem deploy. Horário comercial não entra (o código roda todo dia às 11h).
- **Regras únicas:** `Ramon::Fluxos::Retomada` (quem pode — conversa, nenhuma tarefa `follow_up` aberta, última retomada há ≥ 5 dias, data envenenada = nunca; nº da tentativa; dias parado; o contador `custom_attributes.follow_up`), usadas pelo código e pelo fluxo.
- **Motor ganhou:** `lead_parado {retomada: true}` = todo dia enquanto seguir parado, só quem pode receber retomada, na ordem do funil (`default_scope`), sem o "1 vez por parada" (§13); o `limite_dia` 15 do fluxo é o teto do código (aqui o limite **não** devolve o comando ao código); variáveis `{tentativa}` e `{dias_parado}`; `rascunho_ia {onde, titulo (com variáveis), reserva}` — `reserva` = texto fixo se a IA falhar, em vez de tentar de novo; passo `registrar_retomada`; `avisar_push {uma_vez_por_dia}` (Redis, 1ª execução do fluxo no dia SP).
- **Virada no meio do dia:** o relógio reivindica o dia antes de olhar a chave; o código e o fluxo leem a mesma regra, então a virada nunca roda 2 lotes nem repete um lead.
- **Mudou (textos internos, E3):** balões "⚙ Fluxo Cadência de retomada: …" (rascunho pronto e tarefa) no lugar de "⟳ Cadência do hub…"; push "Retomadas prontas pra revisar / Há rascunhos…" sem o número do lote. A retomada segue nota RASCUNHO nas notas do lead, com o mesmo cabeçalho.
- **Fica para a limpeza (outro PR, 2 semanas depois de rodar em normal):** apagar `Ramon::FollowUpDraftService`, `Ramon::DailyFollowUpJob` e a entrada `ramon_daily_follow_up_job` do `config/schedule.yml`, o ramo do código no `FollowUpDraftJob`, o JSON `sistema/cadencia.json` **e** a linha `origem: sistema` dele, o `HOJE['cadencia']` do `Ramon::Fluxos::Sistema`, o spec do serviço e a env.
```

- [ ] **Step 4: Texto do PR (não abrir — gate do Eduardo)** — deixar no relatório final:

```markdown
Automações em fluxo — B4.3: a cadência de retomada sai do código e vira o fluxo "Cadência de retomada", editável na tela. Todo dia às 11h, para os leads parados que podem receber retomada (têm conversa, nenhuma retomada aberta e a última há 5 dias ou mais), até 15 por dia: a IA escreve o rascunho de retomada nº N nas notas do lead (se a IA falhar, entra o texto fixo de sempre), conta a tentativa, cria a tarefa "Retomada nº N" para hoje e avisa no celular uma vez por dia. O botão "Preparar retomada" do painel passa pelo mesmo fluxo. **Direto, sem sombra:** uma chave (`RAMON_FLUXO_CADENCIA=on` + o fluxo em modo normal) põe o fluxo no comando e para o código; voltar é um rake, sem deploy. **A chave vem desligada: nada muda no uso até o Eduardo virar.** No editor: "Retomada: todo dia enquanto seguir parado" no gatilho Lead parado, "Onde o rascunho fica", "Título do rascunho" e "Texto se a IA falhar" no rascunho da IA, "Só uma vez por dia" no push, o passo "Registrar a retomada" e as variáveis tentativa e dias_parado.

## Closes
- Spec `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` §8 (B4+, 3ª migração: cadência — direto, decisão do Eduardo 07/10); notas novas em §N.

## How to test
1. Depois do deploy, com `RAMON_FLUXO_CADENCIA=on` no `chatwoot.env`: `rake "ramon:fluxos:cadencia:criar[2]"` → "modo sombra, ligado, teto 15/dia" e "Agora o CÓDIGO faz a cadência (o fluxo fica parado)". Abrir o fluxo em Inteligência → Automações e conferir os passos e textos.
2. `rake "ramon:fluxos:cadencia:modo[2,normal]"` → "Agora o FLUXO faz a cadência".
3. Num lead de teste com conversa e sem retomada aberta: painel → "Preparar retomada" → em segundos, nota "RASCUNHO (revisar antes de enviar) — retomada nº N:" nas notas do lead, tarefa "Retomada nº N" para hoje, balões "⚙ Fluxo Cadência de retomada" na conversa, push (se for o 1º do dia); em Execuções, concluída.
4. No dia seguinte, depois das 11h: Execuções do fluxo com até 15 leads, sem nenhum balão "⟳ Cadência do hub" (o código parou).

## What changed
- `Ramon::Fluxos::Retomada`: regras únicas da retomada (o serviço antigo passa a usá-las) e a chave; rake `ramon:fluxos:cadencia:{criar,modo}`; `DailyFollowUpJob`, `FollowUpDraftJob` e o relógio dos fluxos obedecem a chave; Watchdog mostra o teto em vigor.
- Motor: "Lead parado" com retomada (todo dia, regra e ordem do código), `{tentativa}`/`{dias_parado}`, rascunho da IA com onde/título/texto de reserva, push uma vez por dia, passo "Registrar a retomada". Desenho em `db/seeds/ramon/fluxos/migrados/cadencia.json`.
- Chave `RAMON_FLUXO_CADENCIA` (desligada). Front: editor. Sem migração.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR
```

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md
git commit -m "docs(fluxos): notas da B4.3 na spec" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

Sem push.

---

## Operação depois do deploy

Conta da banca = **2**; console = `docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "<task>"` (o Eduardo roda via `!` e cola a saída). Deploy = o de sempre (`docker compose pull chatwoot-web chatwoot-worker && docker compose up -d chatwoot-web chatwoot-worker`), **sem migração**. Na Variante A, trocar os comandos `ramon:fluxos:cadencia:*` pelo rake comum da B4.2.

**1. Env (junto do deploy).** Acrescentar `RAMON_FLUXO_CADENCIA=on` ao `chatwoot.env` em `/opt/intranet-ramon` e recriar (`docker compose up -d chatwoot-web chatwoot-worker`). Nada muda ainda: sem o fluxo em normal, o código segue.

**2. Criar o fluxo (parado).**
`docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:cadencia:criar[2]"`
Saída: `Fluxo #N "Cadência de retomada" — modo sombra, ligado, teto 15/dia` e `Agora o CÓDIGO faz a cadência (o fluxo fica parado).` Rodar de novo não duplica. Opcional: no fluxo, "Testar com um lead…" num lead parado (ensaio: diz o que faria, não grava).

**3. Virar (logo em seguida — escopo E1).**
`docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:cadencia:modo[2,normal]"` → `Agora o FLUXO faz a cadência (o código não faz mais).` De preferência **depois das 11h** (o lote de hoje já saiu pelo código; o relógio já reivindicou o dia, então o fluxo começa amanhã às 11h — sem 2º lote) ou **antes das 11h** (o lote de hoje sai pelo fluxo).

**4. Teste ao vivo (na hora).** Num lead de teste com conversa e sem retomada aberta: painel do lead → "Preparar retomada" → em segundos: nota `RASCUNHO (revisar antes de enviar) — retomada nº N:` nas **notas do lead** (não na conversa), tarefa "Retomada nº N" para hoje, balões "⚙ Fluxo Cadência de retomada: rascunho de retomada nº N pronto…" e "…: tarefa …" na conversa, push "Retomadas prontas pra revisar" (se for o 1º do dia); em Automações → Execuções do fluxo, "concluída". Clicar de novo → o painel diz que já há retomada aberta. Apagar a nota e a tarefa de teste (o contador do lead de teste fica +1).

**5. No dia seguinte, depois das 11h.** Execuções do fluxo: até 15, todas concluídas (alguma "falhou" → abrir, ver o passo; o sino de falha avisa os admins). Nas conversas, nenhum balão novo "⟳ Cadência do hub" (o código parou). Watchdog: teto 15.

**6. Voltar (a qualquer momento, sem deploy).**
`docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:cadencia:modo[2,sombra]"` → `Agora o CÓDIGO faz a cadência.` O botão volta ao código na hora; o lote volta ao código no próximo 11h (se o fluxo já fez o de hoje, não há 2º). Também volta desligando o fluxo na tela ou a env.

**7. Depois (outro PR, E5).** Com 2 semanas em normal sem incidente: o que está em "Fica para a limpeza" (§N da spec).

---

## Divergências registradas (spec × este plano)

| # | Onde | Divergência | Motivo |
|---|---|---|---|
| 1 | Spec §8 ("B4+ — migração 1 a 1, modo sombra… comparar trilhas") | Direto: sem sombra e sem comparação; o fluxo parado não ensaia | Escopo do Eduardo (07/10, igual à B4.2) |
| 2 | Spec §13 ("`lead_parado` dispara 1 vez por parada") | Opção `retomada`: todo dia enquanto seguir parado, filtrado pela regra do código | É o que a cadência faz hoje |
| 3 | Spec §15 / B4.1 ("um limite diário devolve o comando ao código") | Na cadência o limite do dia é o teto (15) e não devolve o comando | O teto é regra da cadência; sem limite, ninguém deixaria de agir |
| 4 | Spec §4.3 (`rascunho_ia` = nota na conversa) | `onde: notas_do_lead`, título com variáveis, `reserva` | A retomada nasce nas notas do lead, com texto fixo se a IA falhar |
| 5 | Spec §4.3 (passos) | Passo novo `registrar_retomada` | O contador mora em `custom_attributes.follow_up`, fora do alcance do "Preencher campo" |

## Decisões novas que dependem do Eduardo

| # | Decisão | Proposta do plano | Onde |
|---|---|---|---|
| N1 | Com o fluxo no comando, o botão **"Preparar retomada"** do painel também passa pelo fluxo (para aquele lead, sem o teto, como hoje) | **Sim** — senão o código antigo nunca pode ser apagado e haveria duas cadências diferentes | Task 5 |
| N2 | A tarefa **"Retomada nº N"** passa a ter dono (o Closer do lead; sem Closer, o SDR) e vence às 23:59 de São Paulo; hoje nasce sem dono e vence no fim do dia do servidor | **Aceitar** — a tarefa aparece na Esteira de quem cuida do lead | Task 4 (desenho) |
| N3 | O **texto da IA** passa a vir da instrução do fluxo (os mesmos 3 ângulos do código) + as regras gerais dos fluxos (OAB), com o modelo dos fluxos (DeepSeek), fora da escolha "Copiloto" da tela Uso e custo (o custo aparece como "fluxos"); a conversa vai pelos últimos ~8 mil caracteres (hoje, as últimas 200 mensagens). Continua rascunho | **Aceitar** — o texto muda pouco e sempre passa por revisão | Tasks 3–4 |
| N4 | O teto de **15 por dia** passa a contar também as retomadas do botão naquele dia (hoje o botão não gasta o teto do lote) | **Aceitar** — raro e o teto continua editável na tela | Task 5 |
