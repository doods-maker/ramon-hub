# Automações em fluxo — B4.4 (Lead ganho) + B4.5 (Eventos do ADVBOX) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O que o hub faz quando o **lead é ganho** (dossiê de passagem, caso aberto no ADVBOX, rascunho da pesquisa NPS) e o que faz quando o **ADVBOX avisa uma etapa** (as 10 regras do Flowter: contrato fechado, requerimento, INSS negou, decisão, exigência, benefício futuro, êxito, marco, concessão, arquivado) saem do código para **2 fluxos de verdade** — "Lead ganho" e "Eventos do ADVBOX" —, cada um com a **chave de segurança da B4.1** (env própria + o fluxo em modo normal ⇒ o fluxo faz e o código para; qualquer peça fora ⇒ o código faz). As chaves nascem **desligadas**: nada muda em produção até o Eduardo virar, logo depois do deploy, com o teste ao vivo.

**Architecture:** Um passo novo, **"rotina pronta do hub"** (`rotina`), chama o **mesmo código de hoje** com as mesmas travas (dossiê `Leads::HandoffNoteService`, NPS `Ramon::NpsDraftJob`, caso no ADVBOX `Ramon::AdvboxClosingService`, concluir tarefas) — o fluxo não reimplementa nada que grava no ADVBOX. Um módulo de **fluxos migrados** (`Ramon::Fluxos::Migrados`: registro por migração, chave, semear, modo, rake) — ou o da B4.2, se ela já o criou (Task 0). **A decisão é do evento, lida uma vez:** o callback do Lead chama `Ramon::Fluxos::LeadGanho.ganhou` e o `AdvboxEventProcessor` chama `Ramon::Fluxos::EventosAdvbox.processar`; cada um lê `assumiu?` uma vez, manda `assumido` no gatilho e só roda o código antigo se o fluxo não está no comando. **Contrato fechado** do ADVBOX só move o lead para o ganho (nos dois caminhos); dossiê/ADVBOX/NPS saem **sempre e só** do "Lead ganho", que decide sozinho — nunca em dobro. Os efeitos de hoje do processador mudam de arquivo (`Ramon::AdvboxEventRegras`), sem nenhuma linha nova no processador nem no `Lead`. Sem migração.

**Tech Stack:** Rails 7.1 / RSpec (só no CI), Postgres jsonb, Sidekiq (ActiveJob); Vue 3.5 `<script setup>`, vue-i18n 9, Vitest 3 + @vue/test-utils.

**Spec:** `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (§4 peças, §6 motor, §8 migração B4+, §13 notas da B2b — ADVBOX "pelo menos uma vez", `execucao_id`, `CAMPOS_WEBHOOK`; §14 notas da B3 — "Contrato fechado do ADVBOX dispara também o Lead ganho (a B4 não pode migrar os dois em dobro)", "um lead pode ter até 2 rascunhos de NPS"; §15 notas da B4.1 — a chave, "a decisão é do evento"). Desenhos de referência (o que o código faz e as lacunas do motor): `db/seeds/ramon/fluxos/sistema/lead_ganho.json` e `eventos_advbox.json`. Plano de referência de estilo: `docs/superpowers/plans/2026-10-06-automacoes-fluxo-b4-lembretes.md`.

## Escopo decidido pelo Eduardo (o mesmo da B4.2, 07/10 — vence a spec)

1. **E1 — DIRETO, sem sombra nem comparação:** os fluxos nascem pelo rake logo depois do deploy, o Eduardo vira a chave e faz o **teste ao vivo** na hora. Não há período de sombra, nem rake de comparação, nem critério de dias. (Enquanto o código está no comando o fluxo migrado só **ensaia** — é o motor de sempre, de graça, e ajuda a conferir antes de virar.)
2. **E2 — chave igual à da B4.1, uma por migração:** `RAMON_FLUXO_LEAD_GANHO=on` + o fluxo "Lead ganho" em modo normal; `RAMON_FLUXO_EVENTOS_ADVBOX=on` + o fluxo "Eventos do ADVBOX" em modo normal. Qualquer peça fora (env desligada, fluxo desligado na tela, em sombra, com limite do dia, gatilho trocado) ⇒ o código faz. Voltar = rake `modo …,sombra`, **sem deploy**. As duas chaves são independentes.
3. **E3 — textos internos (push, atividade, balão na conversa) podem mudar.**
4. **E4 — mensagem ao cliente SEMPRE rascunho** (nas notas do lead, como hoje), com o **texto copiado do código** caractere a caractere.
5. **E5 — nada grava no ADVBOX de verdade sem a mesma garantia de hoje:** só com `ADVBOX_API_TOKEN`; não abre de novo caso já aberto (`advbox.sincronizado_em`); cada id guardado assim que nasce (a nova tentativa retoma dali). O **teste ao vivo não cria nada no ADVBOX** (lead de teste com a trava pré-marcada; ver Operação).
6. **E6 — depois de assumir, os fluxos são editáveis por admin** (uma edição errada tira o efeito correspondente).
7. **E7 — limpeza** (apagar o código antigo, os JSON `sistema/lead_ganho.json` e `sistema/eventos_advbox.json` **e** as linhas `origem: sistema` deles, as envs) num PR separado, depois de 2 semanas em normal sem incidente.

## Global Constraints

- **Ordem das fatias:** esta roda **depois** da B4.2 (SLA, `wt-fluxos-b42`) e da B4.3 (cadência, `wt-fluxos-b43`), **rebaseada nelas** (Task 0). Branch `feat/fluxos-b44-ganho-advbox`, worktree `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-fluxos-b44`. Base escrita contra `origin/ramon` **079a04c** (B1–B3 + B4.1, #213–#218 no ar). Nunca `git push`, nunca abrir PR (gate do Eduardo / sessão principal), nunca `git stash`, nunca `git add -A`.
- **Produção não muda até o Eduardo virar a chave.** Com as duas envs ausentes/`off` (padrão) o lead ganho e os eventos do ADVBOX acontecem exatamente como hoje; os fluxos só nascem quando alguém roda o rake `semear`.
- **Não apagar nada do caminho antigo nesta fatia (E7):** os efeitos de hoje continuam no código, só mudam de arquivo (`Lead` → `Ramon::Fluxos::LeadGanho.pelo_codigo`; `AdvboxEventProcessor` → `Ramon::AdvboxEventRegras`, cópia literal). O Drive (`Lead#enqueue_drive_export`) **fica no código** (Decisão N1).
- **`app/models/lead.rb`, `app/services/ramon/advbox_event_processor.rb` e `app/finders/conversation_finder.rb` estão NO LIMITE de 175 linhas de código (Rubocop `Metrics/ClassLength`): nenhuma linha nova neles.** Esta fatia mexe nos dois primeiros só para **tirar** linhas (Lead: −14; processador: −70). `conversation_finder.rb` não é tocado.
- **Sem migração.** `ramon_fluxos` já tem `origem`, `sistema_chave`, `modo`, `ativo`, `limite_dia`, `versao_publicada_id`, `gatilho_tipo`; não há índice único em `sistema_chave` (o fluxo migrado `origem: usuario` convive com a linha `origem: sistema` da mesma chave, como na B4.1). Se alguma task achar que precisa de coluna/índice: pare e pergunte.
- **Rubocop do fork** (o CI barra): `Metrics/AbcSize` 26, `Metrics/MethodLength` 19, `Metrics/CyclomaticComplexity` 7, `Metrics/PerceivedComplexity` 8, `Metrics/ClassLength` 175, `Metrics/ModuleLength` 100, `Metrics/BlockLength` 30 (fora de spec), linha 150, `Style/HashSyntax` `EnforcedShorthandSyntax: never` (sempre `chave: valor`), `Naming/MethodParameterName` mínimo 3 letras, `rubocop-rspec` (`RSpec/MultipleExpectations` 7, `RSpec/ExampleLength` 50, `RSpec/SpecFilePathFormat`: spec de `A::B::C` em `spec/.../a/b/c_spec.rb`, **`RSpec/ContextWording` só aceita `context` começando com when/with/without — use `describe` para frases em pt-BR**, nada de constante dentro de bloco de spec — `RSpec/LeakyConstantDeclaration`). Tamanhos na base 079a04c (linhas de código): `disparo.rb` 97, `contexto.rb` 81, `executor.rb` 115, `grafo.rb` 150, `passos/lead.rb` 87 (módulo: limite 100), `reunioes.rb` 70.
- **CI FOSS apaga `enterprise/`:** esta fatia não toca Captain. Se precisar, pare.
- **Sem Ruby local:** specs Ruby são escritos e conferidos à mão (rastrear cada linha) e quem valida é o CI. `travel_to` em blocos **em sequência**, nunca aninhados; código de produção nunca usa `NOW()` do SQL. **1 execução viva por (fluxo, alvo) por exemplo** (índice único parcial `… WHERE status IN ('rodando','esperando') AND NOT ensaio`): helper que cria execução não-ensaio é chamado uma vez por exemplo. `.distinct.pluck` em modelo com `default_scope` ordenado quebra no Postgres (use `.pluck.uniq`). Notificações: o builder cria 1 linha por pessoa por chamada e o job de dedupe não roda no teste — nunca contar notificações acumuladas entre chamadas (esta fatia não usa sino). `with_modified_env` em vez de stub de `ENV`. **Travas que escondem dobra:** dossiê (5 min), NPS (1 vez por fase) e ADVBOX (`sincronizado_em`) fazem uma execução em dobro parecer única — o "nunca em dobro" se prova **contando as decisões** (`LeadGanho.pelo_codigo`, `AdvboxEventRegras.new`, execuções não-ensaio), não só os efeitos.
- **Mensagem ao cliente SEMPRE rascunho; só admin edita.** Os textos ao cliente desta fatia são os 4 rascunhos do ADVBOX (INSS negou, exigência, êxito, concessão) — `rascunho_texto {onde: notas_do_lead, titulo}` com o texto do código — e a pesquisa NPS (rotina: o próprio `NpsDraftJob`). Nenhum passo envia nada. A API de fluxos segue admin-only.
- **Front:** i18n só dentro de `CAPTAIN_RAMON.FLUXOS` em `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json`, chaves novas na **mesma posição** nos dois arquivos (a trava `specs/i18n.spec.js` compara a ordem, cobre o catálogo e compila no vue-i18n de produção); strings sem `@`, `|`, `{`, `}` crus; editar os JSON à mão (Edit). Tailwind only, kit `ramon/helpers/ui.js` (`ROTULO`, `SELECT`), evento custom camelCase, toda `<ul>/<ol>` nova com `list-none` (esta fatia não cria lista), sem texto cru no template.
- **Vitest:** `node_modules` é junção para `ramon-hub-wt-fluxos-b2\node_modules` (nunca `rm -rf node_modules`). Config local **já existe e fica fora do git** `vitest.local.config.ts` na raiz do worktree (não commitar):
  `TZ=UTC npx vitest run <arquivos ou pastas> --config vitest.local.config.ts`
  Baseline na base 079a04c: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs` = **15 arquivos, 180 testes** (o Task 0 mede de novo depois do rebase — chame de **B**). ESLint: `./node_modules/.bin/eslint <arquivos>` (erro `Delete ␍` = CRLF do checkout Windows, ignorar; warnings `@intlify/vue-i18n/no-dynamic-keys` já existem e são aceitos).
- **Commits:** Conventional Commits em pt-BR, sem citar Claude no assunto; corpo termina com:
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR`
  Commitar só os caminhos da task (`git add <arquivos>`).
- **Pontos de conflito com B4.2/B4.3 (mesmos arquivos):** `app/services/ramon/fluxos/disparo.rb` (listas `NA_HORA`/`PELO_EVENTO`, `da_vez?`, `na_hora?`, `sombra?`), `contexto.rb` (`DO_GATILHO`), `executor.rb` (`PASSOS`, `VISIVEIS`), `grafo.rb` (`TIPOS_PASSO`, `OBRIGATORIOS`), `passos/lead.rb` (`TIPOS_ATIVIDADE`), `lib/tasks/ramon_fluxos.rake`, `.env.example`, `fluxo.js`, `validar.js`, `PainelPasso.vue`, `NoPasso.vue`, os dois `ramon.json`, `specs/migrados.spec.js`, `specs/i18n.spec.js` e a spec (seção de notas). Como esta fatia roda **depois** e rebaseada, quem resolve é ela: acrescentar às listas/blocos que as outras deixaram, nunca reescrever o que elas puseram.

## Review Focus

1. **Contrato fechado do ADVBOX com as 4 combinações de chave** (eventos pelo código/fluxo × lead ganho pelo código/fluxo) — dossiê, NPS e caso no ADVBOX saem **uma vez**, nem 0 nem 2, e o "quem fez" é sempre um só. Teste: Task 5 ("contrato fechado nunca faz o Lead ganho em dobro (nem deixa de fazer)", 4 exemplos que contam as decisões).
2. **Dois avisos do ADVBOX do mesmo lead colados** (o Flowter manda etapa e tarefa no mesmo segundo, ou o fluxo do lead ainda espera nova tentativa) — o 2º evento não pode sumir no índice único nem sair em dobro. Teste: Task 4 ("fluxo no comando mas ocupado com o mesmo lead…").
3. **ADVBOX fora do ar ou recusando no lead ganho pelo fluxo** — não duplica cliente/processo (cada id guardado ao nascer), a recusa fica anotada no lead como hoje, e o resto (dossiê, NPS) não fica preso esperando o ADVBOX. Teste: Task 1 ("ADVBOX fora do ar…", "ADVBOX recusou…") e Task 3 ("…dossiê → NPS → ADVBOX (por último)").
4. **Rascunho ao cliente diferente do de hoje** (aspas, quebra de linha, título, "cliente" quando o lead não tem nome, emoji) — o Eduardo aprovou os textos do código, não outros. Teste: Task 4 (`primeiro_nome` sem nome → "cliente"), Task 5 (as 10 regras: o fluxo deixa no lead exatamente o que o código deixa) e Task 6 (os 4 textos no JSON).
5. **Virada / fluxo desligado na tela / limite do dia** — o código volta na hora, sem buraco e sem dobra. Teste: Task 2 (`assumiu?` peça a peça) e Task 3 ("um desligado na tela devolve ao código").

---

## Como os fluxos ficam fiéis ao código (decisões de desenho)

### O que o código faz × o que o fluxo faz

| Evento | Código hoje | Fluxo (B4.4/B4.5) |
|---|---|---|
| **Lead ganho** (`won_at` mudou e está preenchido) | `Lead#generate_handoff_note` (dossiê nas notas, sem repetir em 5 min) | `rotina {rotina: dossie_passagem}` → o mesmo `Leads::HandoffNoteService` |
| | `Lead#enqueue_nps_draft` → `NpsDraftJob` (rascunho nas notas, 1 vez: `nps.pedido_em`) | `rotina {rotina: pesquisa_nps}` → o mesmo `NpsDraftJob` (`perform_now`) |
| | `Lead#enqueue_advbox_closing` → `AdvboxClosingJob` (só com token; 3 tentativas) → `AdvboxClosingService` (cliente + processo em CONTRATO FECHADO + tarefa 1º CONTATO; trava `sincronizado_em`; id guardado a cada passo) | `rotina {rotina: abrir_caso_advbox}` → o mesmo `AdvboxClosingService`, **por último** (N2); sem token: anota e segue; fora do ar: o motor tenta de novo em 1/5/15 min e, na 4ª, falha + sino aos admins |
| | `Lead#enqueue_drive_export` (Drive; também a cada update de documentos) | **fica no código** (N1) |
| **ADVBOX** `contrato_fechado` | move para a etapa de ganho (se não está) → atividade `advbox_contrato_fechado` → push | `mover_etapa {etapa de ganho}` → `registrar_atividade {tipo: advbox_contrato_fechado}` → `avisar_push`. Mover para o ganho dispara o callback do Lead → **"Lead ganho" decide sozinho** |
| `requerimento_protocolado` | atividade "ADVBOX: … em dd/mm/aaaa" → tarefa follow-up 45 dias → push | atividade `'ADVBOX: {texto} em {hoje}'` → `criar_tarefa {follow_up, 45}` → push |
| `indeferimento` | atividade → tarefa 1 dia → rascunho "INSS negou" → push | atividade → tarefa → `rascunho_texto {notas_do_lead, titulo: 'INSS negou'}` → push |
| `decisao` | atividade → tarefa 2 dias → push | idem |
| `exigencia` | atividade → tarefa 2 dias → rascunho "exigência do INSS" → push | idem |
| `reativacao_futura` | atividade → tarefa 180 dias | idem |
| `exito` | atividade → rascunho "comunicado de êxito" → `NpsDraftJob(fase: exito)` → push | atividade → rascunho → `rotina {pesquisa_nps_exito}` → push |
| `marco` | atividade → push | idem |
| `concessao` | atividade → rascunho "benefício concedido" → NPS êxito → push | idem |
| `arquivado` | conclui as tarefas abertas → atividade | `rotina {concluir_tarefas}` → atividade |

Variáveis novas que o código manda prontas no gatilho (o fluxo escreve igual, sem lógica nova): `{primeiro_nome}` (= `lead.name` primeira palavra, ou "cliente" — o mesmo do código; já existe desde a B4.1) e `{hoje}` (= `Time.zone.today` em dd/mm/aaaa, o mesmo do código).

Diferenças aceitas (internas — E3, N3, N4): o push usa o nome do contato (`{nome_completo}`); as tarefas de follow-up vencem no fim do dia (SP) e ficam com o Closer/SDR do lead (hoje: hora exata, sem dono); cada passo visível deixa o balão "⚙ Fluxo …" na conversa do lead.

### A decisão é do evento (e o "não migrar em dobro")

- **Lead ganho** — o callback do `Lead` (`after_update_commit :ganhou, if: :saved_change_to_won_at?`) chama `Ramon::Fluxos::LeadGanho.ganhou(lead)`: lê `Migrados.assumiu?(account, 'lead_ganho')` **uma vez**, dispara `lead_ganho` com `assumido` (só o fluxo migrado responde — `Disparo.da_vez?`) e só roda o código antigo (`pelo_codigo`) se **não** assumido. O ouvinte de sempre (`RamonFluxoListener#lead_updated`) segue disparando `lead_ganho` **sem** `assumido` → só os fluxos comuns de usuário, como hoje.
- **Eventos do ADVBOX** — o processador acha a regra e o lead (como hoje) e chama `Ramon::Fluxos::EventosAdvbox.processar(lead, regra, nome)`: lê `assumiu?(account, 'eventos_advbox')` **uma vez**; dispara o fluxo migrado **na hora** (dentro do job do ADVBOX — `Disparo::NA_HORA`) com `assumido`; roda o código (`AdvboxEventRegras`) se não assumido **ou se o fluxo não pegou o evento** (lista vazia: execução viva do mesmo lead, motor com erro, fluxo desligado no meio — **nada se perde**, N6); por fim dispara os fluxos comuns de evento do ADVBOX **sem** `assumido`, como hoje.
- **Contrato fechado:** nos dois caminhos o ADVBOX só **move o lead para o ganho**; quem faz dossiê/ADVBOX/NPS é o "Lead ganho", pela chave dele, lida uma vez no callback do Lead. As 4 combinações dão exatamente 1 de cada (Review Focus 1).
- **Por que o "Eventos do ADVBOX" roda na hora:** o índice único admite 1 execução viva por (fluxo, lead). Rodando dentro do job do ADVBOX a execução vive milissegundos — dois eventos seguidos do mesmo lead quase nunca se encontram, e quando se encontram o código faz o 2º. Assíncrono, a janela seria o tempo de fila.
- **Por que o "Lead ganho" NÃO cai no código quando o fluxo não pega:** o único jeito comum de não pegar é o lead ser ganho de novo enquanto a execução anterior ainda vive (ex.: ADVBOX fora, esperando nova tentativa) — e essa execução já vai fazer tudo; cair no código aí correria o ADVBOX duas vezes em paralelo (o próprio serviço documenta esse teto). Teto aceito: um erro do motor antes de criar a execução (raro, vai para o rastreador de erros) deixa aquele ganho sem dossiê/NPS/caso — refazer à mão.
- **Rodar 4 rotinas como um passo só ("rotina pronta")**: o motor não sabe criar cliente+processo no ADVBOX (o passo `advbox` só cria tarefa/movimentação num processo que existe), nem a trava 1-vez do NPS, nem o dossiê, nem concluir tarefas. Em vez de 4 passos novos com lógica copiada, 1 passo chama o código que já roda hoje — mesmas travas, mesmo texto, mesma garantia do ADVBOX (E5). Contrapartida: o texto do NPS e do dossiê não é editável na tela (N5).

## Mapa de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `app/services/ramon/fluxos/passos/rotina.rb` (novo) | passo `rotina`: `dossie_passagem`, `pesquisa_nps`, `pesquisa_nps_exito`, `abrir_caso_advbox`, `concluir_tarefas` |
| `app/services/ramon/fluxos/migrados.rb` (novo; ou o módulo comum da B4.2 — Task 0) | registro das migrações, `migrado?`, a chave (`ligada?`, `assumiu?`), `semear`, `mudar_modo!`, `descrever` |
| `app/services/ramon/fluxos/lead_ganho.rb` (novo) | decisão do lead ganho + `pelo_codigo` (o caminho de hoje) |
| `app/services/ramon/fluxos/eventos_advbox.rb` (novo) | decisão do evento do ADVBOX, código-reserva, fluxos comuns depois |
| `app/services/ramon/advbox_event_regras.rb` (novo) | os 10 efeitos de hoje, cópia literal do processador |
| `db/seeds/ramon/fluxos/migrados/{lead_ganho,eventos_advbox}.json` (novos) | os 2 desenhos |
| `app/models/lead.rb` | 3 callbacks + 3 métodos viram 1 callback + 1 método (−14 linhas) |
| `app/services/ramon/advbox_event_processor.rb` | só detecta regra e lead; efeitos saem (−70 linhas) |
| `app/services/leads/handoff_note_service.rb` | `recent_dossier?` vira público |
| `app/services/ramon/fluxos/{disparo,contexto,executor,grafo}.rb`, `passos/lead.rb` | motor: `PELO_EVENTO`, evento do ADVBOX na hora, `migrado?` geral, `{hoje}`, passo `rotina`, tipos de atividade do ADVBOX |
| `lib/tasks/ramon_fluxos.rake`, `.env.example` | `ramon:fluxos:migrados:{semear,modo}`; as 2 envs |
| `app/javascript/dashboard/routes/dashboard/captain/automacoes/{fluxo.js,validar.js,PainelPasso.vue,NoPasso.vue}` + i18n `{en,pt_BR}/ramon.json` | o editor entende o passo `rotina`, as atividades do ADVBOX e `{hoje}` |
| `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` | seção "Notas da B4.4/B4.5" |

---

### Task 0: Alinhar com a B4.2 e a B4.3 (rebase + módulo comum + baselines)

**Files:** nenhum arquivo de código (só rebase). Sem commit, salvo conflito no próprio plano.

**Interfaces:**
- Produces: a decisão **A** (a B4.2 deixou um módulo comum de fluxos migrados) ou **B** (não deixou) — as Tasks 2–5 dizem o que muda em cada caso; o baseline **B** do Vitest; os tamanhos atuais dos arquivos do motor.

- [ ] **Step 1: As duas fatias anteriores estão em `origin/ramon`?**

```bash
git fetch origin
git log --oneline origin/ramon -15
```
Expected: commits da B4.2 (SLA) e da B4.3 (cadência) acima de `079a04c`. **Se alguma das duas não estiver lá: pare e avise** (esta fatia depende delas).

- [ ] **Step 2: Rebase**

```bash
git status --short          # só o vitest.local.config.ts (fora do git) pode aparecer
git rebase origin/ramon     # a branch só tem o commit deste plano
```
Expected: sem conflito.

- [ ] **Step 3: Achar o módulo comum de fluxos migrados**

```bash
ls app/services/ramon/fluxos/
grep -rn "RAMON_FLUXO_" app lib .env.example
grep -n "NA_HORA\|PELO_EVENTO\|def self.da_vez\|def na_hora\|def sombra\|migrado?" app/services/ramon/fluxos/disparo.rb
grep -rn "namespace :" lib/tasks/ramon_fluxos.rake
ls db/seeds/ramon/fluxos/migrados/
```
Ler a seção "Mapa de arquivos" do plano da B4.2 (`docs/superpowers/plans/*b42*` ou o nome que ela usou) e da B4.3.

- **Caso A** — existe um módulo com registro por migração (env própria + `sistema_chave` + JSON em `migrados/`), `assumiu?`, `semear`, `mudar_modo!` e rake genérico: **use-o.** Anote aqui a equivalência de nomes (ex.: `Ramon::Fluxos::Migrados.assumiu?(account, 'lead_ganho')` → `<o nome dele>`) e aplique-a em todas as tasks seguintes, inclusive nos specs. Na Task 2 você só **acrescenta** as 2 migrações ao registro dele (+ o preenchimento da etapa de ganho, se ele não tiver) e as listas do `Disparo` (se ele já generalizou `da_vez?`/`na_hora?`/`sombra?`, só some `lead_ganho` e `evento_advbox`).
- **Caso B** — não existe: a Task 2 cria `Ramon::Fluxos::Migrados` exatamente como está escrita.

- [ ] **Step 4: Baselines**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts
for f in app/models/lead.rb app/services/ramon/advbox_event_processor.rb app/services/ramon/fluxos/disparo.rb app/services/ramon/fluxos/contexto.rb app/services/ramon/fluxos/executor.rb app/services/ramon/fluxos/grafo.rb app/services/ramon/fluxos/passos/lead.rb; do echo "$f $(grep -cvE '^\s*(#|$)' $f)"; done
```
Expected: Vitest todo verde — anote arquivos/testes como **B** (na base 079a04c: 15/180). Se `passos/lead.rb` passar de 92 linhas de código, a Task 1 põe os tipos do ADVBOX numa constante em `passos/rotina.rb` em vez de `passos/lead.rb` (limite de módulo 100); se `disparo.rb` passar de 165, avise antes da Task 2.

---

### Task 1: Passo "rotina pronta do hub" + atividades do ADVBOX + `{hoje}` (motor)

**Files:**
- Create: `app/services/ramon/fluxos/passos/rotina.rb`
- Modify: `app/services/leads/handoff_note_service.rb` (`recent_dossier?` público)
- Modify: `app/services/ramon/fluxos/executor.rb` (`VISIVEIS`, `PASSOS`)
- Modify: `app/services/ramon/fluxos/grafo.rb` (`TIPOS_PASSO`, `OBRIGATORIOS`)
- Modify: `app/services/ramon/fluxos/passos/lead.rb` (`TIPOS_ATIVIDADE`)
- Modify: `app/services/ramon/fluxos/contexto.rb` (`DO_GATILHO`)
- Test: `spec/services/ramon/fluxos/passos/rotina_spec.rb` (novo); `spec/services/ramon/fluxos/passos_spec.rb`; `spec/services/ramon/fluxos/grafo_spec.rb`

**Interfaces:**
- Produces: `Ramon::Fluxos::Passos::Rotina::ROTINAS = %w[dossie_passagem pesquisa_nps pesquisa_nps_exito abrir_caso_advbox concluir_tarefas]`; `Ramon::Fluxos::Passos::Rotina.rotina(config, ctx) → {saida: 's', resumo: String}` (config `{'rotina' => <uma das ROTINAS>}`); passo `rotina` publicável (obrigatório: `rotina`) e visível (balão); `registrar_atividade` aceita os 10 tipos `advbox_*`; variável `{hoje}` vinda do gatilho; `Leads::HandoffNoteService#recent_dossier? → Boolean` público.

- [ ] **Step 1: Write the failing tests**

(a) Criar `spec/services/ramon/fluxos/passos/rotina_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Passos::Rotina do
  # A conta seeda o funil no after_create (Leads::SeedDefaultConfigService): 1 etapa is_won.
  let(:account) { create(:account) }
  let(:ganho) { account.lead_stages.find_by!(is_won: true) }
  let(:lead) { create(:lead, account: account, lead_stage: ganho, name: 'Maria da Silva') }
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' })) }

  # ensaio pode repetir no mesmo exemplo; execução de verdade, 1 por exemplo (índice único)
  def rodar(rotina, ensaio: false)
    ctx = Ramon::Fluxos::Contexto.new(fluxo.execucoes.create!(account: account, alvo: lead, ensaio: ensaio))
    described_class.rotina({ 'rotina' => rotina }, ctx)[:resumo]
  end

  def advbox_no_ar
    allow(Ramon::AdvboxClient).to receive_messages(create_customer: { 'customers_id' => 11 },
                                                    create_lawsuit: { 'lawsuits_id' => 22 }, create_post: { 'posts_id' => 33 })
  end

  describe 'dossiê de passagem' do
    it 'escreve o mesmo dossiê do código, não repete em 5 min, e o ensaio só descreve' do
      expect(rodar('dossie_passagem', ensaio: true)).to eq('faria: dossiê de passagem nas notas do lead')
      expect(lead.lead_notes.count).to eq(0)
      expect(rodar('dossie_passagem')).to eq('dossiê de passagem nas notas do lead')
      expect(lead.lead_notes.sole.body).to start_with('📋 DOSSIÊ')
      expect(rodar('dossie_passagem', ensaio: true)).to eq('dossiê: já há um dos últimos 5 min (não repete)')
    end
  end

  describe 'pesquisa NPS' do
    it 'o mesmo rascunho do código, uma vez por fase (ganho e êxito são travas separadas)' do
      expect(rodar('pesquisa_nps')).to eq('rascunho da pesquisa NPS (comercial) nas notas do lead')
      expect(lead.lead_notes.sole.body).to start_with('RASCUNHO (revisar antes de enviar) — pesquisa NPS:')
      expect(lead.reload.custom_attributes.dig('nps', 'pedido_em')).to be_present
      expect(rodar('pesquisa_nps', ensaio: true)).to start_with('pesquisa NPS (comercial): já pedida em ')
      expect(rodar('pesquisa_nps_exito', ensaio: true)).to eq('faria: rascunho da pesquisa NPS (exito) nas notas do lead')
    end
  end

  describe 'caso no ADVBOX (mesma garantia de hoje)' do
    it 'abre cliente, processo e tarefa pelo mesmo serviço do código; já aberto não chama de novo' do
      advbox_no_ar
      with_modified_env(ADVBOX_API_TOKEN: 'tok') do
        expect(rodar('abrir_caso_advbox', ensaio: true)).to start_with('faria: abrir o caso no ADVBOX')
        expect(rodar('abrir_caso_advbox')).to eq('caso aberto no ADVBOX (processo 22)')
        expect(rodar('abrir_caso_advbox', ensaio: true)).to start_with('ADVBOX: caso já aberto em ')
      end
      expect(Ramon::AdvboxClient).to have_received(:create_customer).once
      expect(lead.reload.custom_attributes['advbox']).to include('customers_id' => 11, 'lawsuits_id' => 22, 'posts_id' => 33)
    end

    it 'sem token não abre e segue (o código nem enfileirava); lead que saiu do ganho também não' do
      advbox_no_ar
      expect(rodar('abrir_caso_advbox', ensaio: true)).to eq('ADVBOX: sem token no hub, não abriu o caso (como o código)')
      with_modified_env(ADVBOX_API_TOKEN: 'tok') do
        lead.update!(lead_stage: account.lead_stages.order(:position).first)
        expect(rodar('abrir_caso_advbox')).to eq('ADVBOX: o lead não está mais ganho, não abriu o caso')
      end
      expect(Ramon::AdvboxClient).not_to have_received(:create_customer)
    end

    it 'ADVBOX fora do ar: sobe o erro para o motor tentar de novo, com o id já criado guardado (não duplica)' do
      allow(Ramon::AdvboxClient).to receive(:create_customer).and_return('customers_id' => 11)
      allow(Ramon::AdvboxClient).to receive(:create_lawsuit).and_raise(Ramon::AdvboxClient::UnavailableError, 'AdvBox indisponível')
      with_modified_env(ADVBOX_API_TOKEN: 'tok') do
        expect { rodar('abrir_caso_advbox') }.to raise_error(Ramon::AdvboxClient::UnavailableError)
      end
      expect(lead.reload.custom_attributes.dig('advbox', 'customers_id')).to eq(11)
    end

    it 'ADVBOX recusou (4xx): fica anotado no lead, como hoje, e o fluxo segue' do
      allow(Ramon::AdvboxClient).to receive(:create_customer).and_raise(Ramon::AdvboxClient::RequestError.new(422, { 'erro' => 'x' }))
      resumo = with_modified_env(ADVBOX_API_TOKEN: 'tok') { rodar('abrir_caso_advbox') }
      expect(resumo).to start_with('ADVBOX recusou: ')
      expect(lead.reload.custom_attributes.dig('advbox', 'erro')).to be_present
    end
  end

  describe 'concluir tarefas (ADVBOX arquivado)' do
    it 'conclui só as abertas do lead; o ensaio conta' do
      lead.lead_tasks.create!(account: account, kind: 'follow_up', title: 'Aberta', due_at: 1.day.from_now)
      lead.lead_tasks.create!(account: account, kind: 'other', title: 'Feita', due_at: 1.day.ago, completed_at: 1.hour.ago)
      expect(rodar('concluir_tarefas', ensaio: true)).to eq('faria: concluir 1 tarefa(s) aberta(s) do lead')
      expect(rodar('concluir_tarefas')).to eq('concluiu 1 tarefa(s) aberta(s) do lead')
      expect(lead.lead_tasks.open_tasks.count).to eq(0)
    end
  end

  it 'rotina desconhecida falha na hora (não adianta repetir)' do
    expect { rodar('apagar_tudo') }.to raise_error(Ramon::Fluxos::PassoImpossivel, /rotina desconhecida/)
  end
end
```

Rastreio: `with_modified_env` devolve o valor do bloco (`spec/spec_helper.rb`: `ClimateControl.modify(options, &)`). `rodar` não-ensaio aparece **uma** vez por exemplo, exceto no "ADVBOX fora do ar" (1) e "sem token" (1) — ok. A tarefa "Feita" tem `completed_at`, então `open_tasks` não a conta (`LeadTask.open_tasks` = `completed_at: nil`; conferir com `grep -n "open_tasks" app/models/lead_task.rb`).

(b) Em `spec/services/ramon/fluxos/passos_spec.rb`, acrescentar no fim do `RSpec.describe` (antes do `end` final):

```ruby
  it 'atividade com tipo do ADVBOX grava como o código: sem pessoa, texto com {texto} e {hoje} do gatilho (B4.5)' do
    gatilho = { 'gatilho' => { 'texto' => 'REQUERIMENTO PROTOCOLADO', 'hoje' => '07/10/2026' } }
    Ramon::Fluxos::Passos::Lead.registrar_atividade({ 'tipo' => 'advbox_inss_protocolado', 'texto' => 'ADVBOX: {texto} em {hoje}' },
                                                    ctx(contexto: gatilho))
    expect(lead.lead_activities.where(kind: 'advbox_inss_protocolado').pluck(:to_value, :user_id))
      .to eq([['ADVBOX: REQUERIMENTO PROTOCOLADO em 07/10/2026', nil]])
  end
```

(c) Em `spec/services/ramon/fluxos/grafo_spec.rb`, acrescentar dentro do `describe` de erros de passo (ou no fim do arquivo, antes do `end`):

```ruby
  it 'rotina pronta precisa dizer qual rotina' do
    erros = described_class.new(grafo_linear({ 'tipo' => 'manual' }, ['rotina', {}])).erros
    expect(erros).to eq(['Passo p1: falta rotina'])
  end
```

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/passos/rotina_spec.rb spec/services/ramon/fluxos/passos_spec.rb spec/services/ramon/fluxos/grafo_spec.rb`
Expected: FAIL — `uninitialized constant Ramon::Fluxos::Passos::Rotina`; a atividade grava `kind: 'fluxo'`; o grafo diz "tipo desconhecido (rotina)".

- [ ] **Step 3: Implementation**

(a) Criar `app/services/ramon/fluxos/passos/rotina.rb`:

```ruby
# B4.4/B4.5: rotinas prontas do hub como passo de fluxo — o MESMO código de hoje, com as mesmas travas:
# - dossie_passagem: Leads::HandoffNoteService (nas notas do lead; não repete se já há um dos últimos 5 min)
# - pesquisa_nps / pesquisa_nps_exito: Ramon::NpsDraftJob (rascunho nas notas; 1 vez por fase — nps.pedido_em /
#   nps.pedido_exito_em; link do Google = RAMON_GOOGLE_REVIEW_URL)
# - abrir_caso_advbox: Ramon::AdvboxClosingService (cliente + processo em CONTRATO FECHADO + tarefa 1º CONTATO). Grava no
#   ADVBOX de verdade, com a garantia de hoje: só com ADVBOX_API_TOKEN, nunca de novo com advbox.sincronizado_em, cada id
#   guardado assim que nasce (a nova tentativa do motor retoma dali). Fora do ar sobe o erro → o motor tenta de novo em
#   1/5/15 min; recusa (4xx) fica anotada no lead (advbox.erro), como hoje, e o fluxo segue.
# - concluir_tarefas: conclui as tarefas abertas do lead (ADVBOX arquivado)
module Ramon::Fluxos::Passos::Rotina
  ROTINAS = %w[dossie_passagem pesquisa_nps pesquisa_nps_exito abrir_caso_advbox concluir_tarefas].freeze
  FASE_NPS = { 'pesquisa_nps' => 'comercial', 'pesquisa_nps_exito' => 'exito' }.freeze

  module_function

  def rotina(config, ctx)
    nome = config['rotina'].to_s
    raise Ramon::Fluxos::PassoImpossivel, "rotina desconhecida: #{nome}" unless ROTINAS.include?(nome)

    lead = Ramon::Fluxos::Passos::Lead.exigir_lead(ctx)
    resumo = FASE_NPS.key?(nome) ? nps(lead, FASE_NPS[nome], ctx.ensaio?) : public_send(nome, lead, ctx.ensaio?)
    { saida: 's', resumo: resumo }
  end

  def dossie_passagem(lead, ensaio)
    servico = Leads::HandoffNoteService.new(lead: lead)
    return 'dossiê: já há um dos últimos 5 min (não repete)' if servico.recent_dossier?
    return 'faria: dossiê de passagem nas notas do lead' if ensaio

    servico.perform
    'dossiê de passagem nas notas do lead'
  end

  def nps(lead, fase, ensaio)
    pedido = lead.custom_attributes&.dig('nps', Ramon::NpsDraftJob::GUARD_KEYS.fetch(fase))
    return "pesquisa NPS (#{fase}): já pedida em #{pedido} (uma vez só)" if pedido.present?
    return "faria: rascunho da pesquisa NPS (#{fase}) nas notas do lead" if ensaio

    Ramon::NpsDraftJob.perform_now(lead.id, fase: fase)
    "rascunho da pesquisa NPS (#{fase}) nas notas do lead"
  end

  def abrir_caso_advbox(lead, ensaio)
    feito = lead.custom_attributes&.dig('advbox', 'sincronizado_em')
    return "ADVBOX: caso já aberto em #{feito} (não chama de novo)" if feito.present?
    return 'ADVBOX: sem token no hub, não abriu o caso (como o código)' if ENV.fetch('ADVBOX_API_TOKEN', nil).blank?
    return 'ADVBOX: o lead não está mais ganho, não abriu o caso' if lead.won_at.blank?
    return 'faria: abrir o caso no ADVBOX (cliente, processo em CONTRATO FECHADO e tarefa 1º CONTATO)' if ensaio

    Ramon::AdvboxClosingService.new(lead).perform
    advbox = lead.reload.custom_attributes['advbox'] || {}
    return "ADVBOX recusou: #{advbox['erro'].truncate(120)} (anotado no lead)" if advbox['erro'].present?

    "caso aberto no ADVBOX (processo #{advbox['lawsuits_id']})"
  end

  def concluir_tarefas(lead, ensaio)
    abertas = lead.lead_tasks.open_tasks
    return "faria: concluir #{abertas.count} tarefa(s) aberta(s) do lead" if ensaio

    concluidas = abertas.update_all(completed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    "concluiu #{concluidas} tarefa(s) aberta(s) do lead"
  end
end
```

Rastreio da complexidade de `abrir_caso_advbox`: 1 + `&.` + 5 `if` = 7 (limite 7). Não acrescentar ramo; se o Rubocop reclamar, mover as 2 primeiras guardas para `def advbox_parado(lead)` que devolve o texto ou nil.

(b) `app/services/leads/handoff_note_service.rb` — mover `recent_dossier?` para cima do `private` (sem mudar o corpo):

```ruby
  def perform
    return if recent_dossier?

    @lead.lead_notes.create!(account: @lead.account, user: nil, body: body)
  end

  # Público (B4.4): o passo "rotina" do fluxo pergunta antes, para o ensaio e a trilha.
  def recent_dossier?
    @lead.lead_notes
         .where('body LIKE ?', "#{DOSSIER_PREFIX}%")
         .exists?(created_at: DUPLICATE_WINDOW.ago..)
  end

  private
```
(e apagar a cópia antiga de `recent_dossier?` que ficava depois do `private`).

(c) `app/services/ramon/fluxos/executor.rb`:

```ruby
  VISIVEIS = %w[mover_etapa criar_tarefa acao_chatwoot avisar_sino avisar_push trocar_responsavel preencher_campo advbox webhook
                apagar_reuniao rotina].freeze
```
e no hash `PASSOS`, logo depois de `'apagar_reuniao' => Ramon::Fluxos::Passos::Reuniao,`:

```ruby
    'rotina' => Ramon::Fluxos::Passos::Rotina,
```
(Se a B4.2/B4.3 acrescentaram tipos a essas listas, só some `rotina` ao fim delas.)

(d) `app/services/ramon/fluxos/grafo.rb` — no fim de `TIPOS_PASSO` e de `OBRIGATORIOS`:

```ruby
                   registrar_atividade trocar_responsavel preencher_campo apagar_reuniao rotina].freeze
```
```ruby
    'registrar_atividade' => %w[texto], 'trocar_responsavel' => %w[papel], 'rotina' => %w[rotina]
```
(Linha ≤ 150; se a B4.2/B4.3 deixaram as linhas no limite, quebrar em linha nova dentro do `%w[]`/hash.)

(e) `app/services/ramon/fluxos/passos/lead.rb` — trocar `TIPOS_ATIVIDADE` (mantendo os que a B4.2/B4.3 tenham acrescentado):

```ruby
  # B4.1: tipos de atividade que um fluxo pode registrar (os de reunião aparecem como os do código);
  # B4.5: os do ADVBOX, idem (Ramon::AdvboxEventRegras).
  TIPOS_ATIVIDADE = %w[fluxo meeting_scheduled meeting_rescheduled meeting_cancelled
                       advbox_contrato_fechado advbox_inss_protocolado advbox_indeferido advbox_decisao advbox_exigencia
                       advbox_reativacao_futura advbox_exito advbox_marco advbox_concessao advbox_arquivado].freeze
```

(f) `app/services/ramon/fluxos/contexto.rb`:

```ruby
  # o que o gatilho traz e vira variável: {texto} da mensagem, {quando} da reunião,
  # {regra} do evento do ADVBOX, {documento} do anexo casado com o checklist;
  # B4.1: os textos prontos da reunião ({evento}, {titulo}, {titulo_tarefa}, {resumo}, {resumo_antes}, {primeiro_nome});
  # B4.5: {hoje} (dd/mm/aaaa, a data que o código do ADVBOX escreve)
  DO_GATILHO = %w[texto quando regra documento evento titulo titulo_tarefa resumo resumo_antes primeiro_nome hoje].freeze
```
(`RESERVADAS` inclui `DO_GATILHO` — `hoje` vira nome reservado sozinho; o espelho do front é a Task 6.)

- [ ] **Step 4: Run to verify they pass**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/passos/rotina_spec.rb spec/services/ramon/fluxos/passos_spec.rb spec/services/ramon/fluxos/grafo_spec.rb spec/services/ramon/fluxos/executor_spec.rb spec/services/leads` e `bundle exec rubocop app/services/ramon/fluxos/passos/rotina.rb app/services/leads/handoff_note_service.rb app/services/ramon/fluxos/executor.rb app/services/ramon/fluxos/grafo.rb app/services/ramon/fluxos/passos/lead.rb app/services/ramon/fluxos/contexto.rb spec/services/ramon/fluxos/passos/rotina_spec.rb`
Expected: PASS, sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/passos/rotina.rb app/services/leads/handoff_note_service.rb app/services/ramon/fluxos/executor.rb app/services/ramon/fluxos/grafo.rb app/services/ramon/fluxos/passos/lead.rb app/services/ramon/fluxos/contexto.rb spec/services/ramon/fluxos/passos/rotina_spec.rb spec/services/ramon/fluxos/passos_spec.rb spec/services/ramon/fluxos/grafo_spec.rb
git commit -m "feat(fluxos): passo rotina pronta do hub (dossiê, NPS, caso no ADVBOX, concluir tarefas) + atividades do ADVBOX + {hoje}" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 2: Fluxos migrados — a chave por migração, semear, modo, rake + o Disparo decide pelo evento

**Files:**
- Create (Caso B) / Modify (Caso A — o módulo da B4.2): `app/services/ramon/fluxos/migrados.rb`
- Modify: `app/services/ramon/fluxos/disparo.rb`
- Modify: `lib/tasks/ramon_fluxos.rake`, `.env.example`
- Test: `spec/services/ramon/fluxos/migrados_spec.rb` (novo no Caso B); `spec/services/ramon/fluxos/disparo_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Fluxos::Reunioes.migrado?(fluxo)` (B4.1, não muda).
- Produces: `Ramon::Fluxos::Migrados::REGISTRO` (`'lead_ganho' => {env: 'RAMON_FLUXO_LEAD_GANHO', gatilho: 'lead_ganho'}`, `'eventos_advbox' => {env: 'RAMON_FLUXO_EVENTOS_ADVBOX', gatilho: 'evento_advbox'}`); `.migrado?(fluxo) → Boolean` (estes 2 **e** os 3 das reuniões); `.ligada?(chave)`; `.assumiu?(account, chave) → Boolean`; `.fluxo(account, chave) → Fluxo|nil`; `.semear(account, chave) → Fluxo` (cria em sombra, ligado, publicado, a partir de `db/seeds/ramon/fluxos/migrados/<chave>.json`; `mover_etapa` sem etapa ganha a etapa de ganho da conta; existindo, devolve sem tocar); `.mudar_modo!(account, chave, modo) → Fluxo`; `.descrever(account, chave) → String`. `Ramon::Fluxos::Disparo::NA_HORA` inclui `evento_advbox`; `Disparo::PELO_EVENTO = NA_HORA + %w[lead_ganho]`. Rake `ramon:fluxos:migrados:semear[account_id,chave]` e `…:modo[account_id,chave,modo]`.

- [ ] **Step 1: Write the failing tests**

(a) Criar `spec/services/ramon/fluxos/migrados_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Migrados do
  let(:account) { create(:account) }

  def migrado(chave, gatilho)
    fluxo_publicado(account, grafo_linear({ 'tipo' => gatilho }), origem: 'usuario', sistema_chave: chave, modo: 'sombra')
  end

  describe 'a chave de cada migração (env própria + o fluxo em modo normal)' do
    it 'só assume com a env ligada e o fluxo normal, ligado, publicado, sem limite do dia e com o gatilho certo' do
      fluxo = migrado('lead_ganho', 'lead_ganho')
      with_modified_env(RAMON_FLUXO_LEAD_GANHO: 'on') do
        expect(described_class.assumiu?(account, 'lead_ganho')).to be(false) # ainda em sombra
        described_class.mudar_modo!(account, 'lead_ganho', 'normal')
        expect(described_class.assumiu?(account, 'lead_ganho')).to be(true)
        expect(described_class.assumiu?(account, 'eventos_advbox')).to be(false) # cada migração tem a sua chave
        fluxo.update!(limite_dia: 5) # com limite, o Disparo pularia o fluxo e ninguém faria
        expect(described_class.assumiu?(account, 'lead_ganho')).to be(false)
        fluxo.update!(limite_dia: nil, ativo: false) # desligado na tela
        expect(described_class.assumiu?(account, 'lead_ganho')).to be(false)
      end
      fluxo.update!(ativo: true)
      expect(described_class.assumiu?(account, 'lead_ganho')).to be(false) # sem a env
    end

    it 'normal sem a env é recusado; sombra sempre vale; migração desconhecida e fluxo que não existe também recusam' do
      expect { described_class.mudar_modo!(account, 'lead_ganho', 'normal') }.to raise_error(ArgumentError, /RAMON_FLUXO_LEAD_GANHO/)
      expect { described_class.mudar_modo!(account, 'lead_ganho', 'sombra') }.to raise_error(ArgumentError, /ainda não existe/)
      expect { described_class.assumiu?(account, 'cadencia_errada') }.to raise_error(ArgumentError, /migração desconhecida/)
      migrado('eventos_advbox', 'evento_advbox')
      expect(described_class.mudar_modo!(account, 'eventos_advbox', 'sombra').modo).to eq('sombra')
      expect(described_class.descrever(account, 'eventos_advbox')).to include('o CÓDIGO faz')
    end
  end

  it 'migrado? cobre estes 2 e os 3 das reuniões; fluxo comum e linha do sistema não' do
    expect(described_class.migrado?(migrado('lead_ganho', 'lead_ganho'))).to be(true)
    expect(described_class.migrado?(migrado('reuniao_cancelada', 'reuniao_cancelada'))).to be(true)
    expect(described_class.migrado?(fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_ganho' })))).to be(false)
    expect(described_class.migrado?(Fluxo.new(account: account, origem: 'sistema', sistema_chave: 'lead_ganho'))).to be(false)
  end
end
```

Rastreio: `migrado('reuniao_cancelada', …)` → `Reunioes.migrado?` = `origem == 'usuario' && GATILHOS.key?('reuniao_cancelada')` → true. `assumiu?(account, 'cadencia_errada')` — `ligada?` chama `registro` primeiro → `ArgumentError` antes do `ENV`. (Caso A: se o módulo da B4.2 já tem spec equivalente, acrescente lá só os exemplos destas 2 chaves.)

(b) Em `spec/services/ramon/fluxos/disparo_spec.rb`, acrescentar depois do exemplo "reunião marcada/cancelada: o disparo com assumido…":

```ruby
  it 'lead ganho (B4.4): o disparo com assumido é só do migrado; o do ouvinte (sem), só dos outros' do
    migrado = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_ganho' }, nota), sistema_chave: 'lead_ganho')
    comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_ganho' }, nota))
    expect(described_class.call('lead_ganho', lead, { 'assumido' => true }).map(&:fluxo)).to eq([migrado])
    expect(described_class.call('lead_ganho', lead, { 'para_etapa_id' => lead.lead_stage_id }).map(&:fluxo)).to eq([comum])
    expect(migrado.execucoes.sole.ensaio).to be(false) # assumido = age (não pelo modo)
  end

  it 'eventos do ADVBOX (B4.5): o migrado roda na hora, dentro do job do ADVBOX, e age ou ensaia pela decisão do evento' do
    migrado = fluxo_publicado(account, grafo_linear({ 'tipo' => 'evento_advbox' }, nota), sistema_chave: 'eventos_advbox')
    expect { described_class.call('evento_advbox', lead, { 'assumido' => false, 'regra' => 'marco' }) }
      .not_to have_enqueued_job(Ramon::FluxoAvancarJob)
    described_class.call('evento_advbox', lead, { 'assumido' => true, 'regra' => 'marco' })
    expect(migrado.execucoes.order(:id).pluck(:ensaio, :status)).to eq([[true, 'concluida'], [false, 'concluida']])
    expect(conversa.messages.where(private: true, content: 'oi').count).to eq(1)
  end
```
Rastreio: `fluxo_publicado` cria com `origem` padrão do modelo (`usuario` — o exemplo da B4.1 logo acima faz o mesmo). `sistema_chave: 'lead_ganho'` → `Migrados.migrado?` true. 1º `call` com `assumido` → `da_vez?` (lead_ganho ∈ `PELO_EVENTO`; migrado ⇔ tem `assumido`) só o migrado; não é `NA_HORA` → execução `esperando` + job; `sombra?` = `!true` = false. 2º `call` sem `assumido` → só o `comum`. No ADVBOX: `NA_HORA` + migrado → `Executor#avancar!` na hora → `nota_privada` 'oi' na conversa (ensaio não escreve; o de verdade escreve 1).

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/migrados_spec.rb spec/services/ramon/fluxos/disparo_spec.rb`
Expected: FAIL — `uninitialized constant Ramon::Fluxos::Migrados`; o lead ganho dispara os dois fluxos nas duas chamadas; o ADVBOX enfileira o job.

- [ ] **Step 3: Implementation**

(a) **Caso B** — criar `app/services/ramon/fluxos/migrados.rb`:

```ruby
# B4.4/B4.5 (spec §8): automações que saem do código para UM fluxo cada, com a chave da B4.1 por migração — a env da
# migração =on E o fluxo (origem 'usuario', sistema_chave = a chave) ligado, publicado, em modo normal, sem limite do dia
# e com o gatilho certo ⇒ o fluxo faz e o código para; qualquer peça fora ⇒ o código faz e o fluxo só ensaia.
# Voltar = rake ramon:fluxos:migrados:modo[conta,chave,sombra] (sem deploy). As reuniões (3 fluxos) seguem em
# Ramon::Fluxos::Reunioes.
module Ramon::Fluxos::Migrados
  REGISTRO = {
    'lead_ganho' => { env: 'RAMON_FLUXO_LEAD_GANHO', gatilho: 'lead_ganho' },
    'eventos_advbox' => { env: 'RAMON_FLUXO_EVENTOS_ADVBOX', gatilho: 'evento_advbox' }
  }.freeze
  PASTA = Rails.root.join('db/seeds/ramon/fluxos/migrados')

  module_function

  # Fluxo que substitui código (estes e os 3 das reuniões): age ou ensaia pela decisão do evento, não pelo modo.
  def migrado?(fluxo)
    Ramon::Fluxos::Reunioes.migrado?(fluxo) || (fluxo.origem == 'usuario' && REGISTRO.key?(fluxo.sistema_chave))
  end

  def registro(chave) = REGISTRO[chave] || raise(ArgumentError, "migração desconhecida: #{chave} (use #{REGISTRO.keys.join(' ou ')})")

  def ligada?(chave) = ENV.fetch(registro(chave)[:env], nil) == 'on'

  def assumiu?(account, chave)
    return false unless ligada?(chave)

    account.fluxos.executaveis.exists?(origem: 'usuario', sistema_chave: chave, modo: 'normal', limite_dia: nil,
                                       gatilho_tipo: registro(chave)[:gatilho])
  end

  def fluxo(account, chave) = account.fluxos.where(origem: 'usuario', sistema_chave: chave).order(:id).first

  # Cria em sombra, ligado e publicado. Já existe → devolve sem tocar (o Eduardo pode ter editado).
  def semear(account, chave)
    registro(chave)
    fluxo(account, chave) || criar(account, chave)
  end

  def mudar_modo!(account, chave, modo)
    raise ArgumentError, 'modo: normal ou sombra' unless Fluxo::MODOS.include?(modo)
    raise ArgumentError, "Ligue #{registro(chave)[:env]}=on antes (sem ela o código continua fazendo)" if modo == 'normal' && !ligada?(chave)

    alvo = fluxo(account, chave) || raise(ArgumentError, "O fluxo #{chave} ainda não existe: rode ramon:fluxos:migrados:semear")
    alvo.update!(modo: modo)
    alvo
  end

  def descrever(account, chave)
    atual = fluxo(account, chave)
    linha = atual ? "Fluxo ##{atual.id} \"#{atual.nome}\" — modo #{atual.modo}, #{atual.ativo ? 'ligado' : 'desligado'}" : "#{chave}: ainda não existe"
    quem = assumiu?(account, chave) ? 'o FLUXO faz (o código não faz mais)' : 'o CÓDIGO faz (o fluxo só ensaia)'
    "#{linha}\nAgora #{quem}."
  end

  def criar(account, chave)
    dados = JSON.parse(PASTA.join("#{chave}.json").read)
    Fluxo.transaction do
      novo = account.fluxos.create!(nome: dados['nome'], descricao: dados['descricao'], origem: 'usuario', sistema_chave: chave,
                                    modo: 'sombra', ativo: true, rascunho: com_etapa(account, dados['desenho']))
      novo.publicar!(nil)
      novo.reload
    end
  end

  # mover_etapa sem etapa no JSON = a etapa de ganho da conta (a mesma do código: lead_stages.find_by(is_won: true)).
  def com_etapa(account, desenho)
    vazios = desenho['nos'].select { |n| n['tipo'] == 'mover_etapa' && n.dig('config', 'etapa_id').blank? }
    return desenho if vazios.empty?

    etapa_id = account.lead_stages.find_by!(is_won: true).id
    desenho.merge('nos' => desenho['nos'].map { |n| vazios.include?(n) ? n.deep_merge('config' => { 'etapa_id' => etapa_id }) : n })
  end
end
```
(Linha do `descrever` ≤ 150 — se passar, quebrar o ternário em `if/else`.)

**Caso A** — no módulo da B4.2: acrescentar as 2 entradas ao registro dele (env, gatilho, JSON `lead_ganho`/`eventos_advbox`), o preenchimento da etapa de ganho para `mover_etapa` sem etapa (se o `semear` dele não tiver um equivalente, acrescentar `com_etapa` acima, só para estas chaves) e garantir que o `migrado?` dele cobre estas chaves.

(b) `app/services/ramon/fluxos/disparo.rb` (Caso B; no Caso A, só somar às listas que a B4.2 deixou):

```ruby
  # B4.1: os fluxos migrados de marcar/cancelar rodam na hora, dentro da requisição (o painel vê a tarefa ao recarregar;
  # em sombra, o ensaio vê o lead antes de o código mexer). B4.5: o de eventos do ADVBOX também, dentro do job do ADVBOX —
  # a execução vive só enquanto roda, então dois eventos seguidos do mesmo lead quase nunca se barram no índice único.
  NA_HORA = %w[reuniao_marcada reuniao_cancelada evento_advbox].freeze
  # Gatilhos que disparam 2 vezes: com 'assumido' (a decisão do evento, lida 1 vez pelo código) só os fluxos migrados;
  # sem, só os demais. B4.4: lead ganho (o callback do Lead manda com; o ouvinte de sempre, sem).
  PELO_EVENTO = (NA_HORA + %w[lead_ganho]).freeze
```
```ruby
  # Nos gatilhos PELO_EVENTO o evento dispara 2 vezes. Com 'assumido': só os fluxos migrados (Ramon::Fluxos::Migrados).
  # Sem 'assumido': só os demais (como sempre).
  def self.da_vez?(fluxo, dados)
    PELO_EVENTO.exclude?(fluxo.gatilho_tipo) || Ramon::Fluxos::Migrados.migrado?(fluxo) == dados.key?('assumido')
  end
```
```ruby
  def na_hora? = NA_HORA.include?(@fluxo.gatilho_tipo) && Ramon::Fluxos::Migrados.migrado?(@fluxo)

  # Fluxo migrado do código (B4.1+): quem decide se age é o evento ('assumido', lido 1 vez pelo código); os demais, o modo.
  def sombra? = Ramon::Fluxos::Migrados.migrado?(@fluxo) ? !@dados['assumido'] : @fluxo.modo == 'sombra'
```
(Os 3 fluxos das reuniões continuam iguais: `Migrados.migrado?` inclui `Reunioes.migrado?`; os 2 exemplos da B4.1 no `disparo_spec` seguem verdes.)

(c) `lib/tasks/ramon_fluxos.rake` — dentro de `namespace :fluxos do`, depois do `namespace :reunioes … end` (Caso A: use o rake da B4.2, se ele já for genérico, e pule este passo):

```ruby
    # B4.4/B4.5 — 1 fluxo por migração (lead_ganho, eventos_advbox), direto (spec §8; plano 2026-10-07 B4.4/B4.5).
    namespace :migrados do
      conta = ->(args) { Account.find(args[:account_id].presence || raise(ArgumentError, 'informe o account_id')) }

      desc 'Cria (uma vez) o fluxo de uma migracao em SOMBRA (o codigo segue fazendo). ' \
           'Uso: rake ramon:fluxos:migrados:semear[account_id,lead_ganho|eventos_advbox]'
      task :semear, [:account_id, :chave] => :environment do |_task, args|
        account = conta.call(args)
        Ramon::Fluxos::Migrados.semear(account, args[:chave])
        puts Ramon::Fluxos::Migrados.descrever(account, args[:chave])
      end

      desc 'normal = o fluxo assume (exige a env da migracao =on); sombra = devolve ao codigo na hora. ' \
           'Uso: rake ramon:fluxos:migrados:modo[account_id,lead_ganho,normal]'
      task :modo, [:account_id, :chave, :modo] => :environment do |_task, args|
        account = conta.call(args)
        Ramon::Fluxos::Migrados.mudar_modo!(account, args[:chave], args[:modo])
        puts Ramon::Fluxos::Migrados.descrever(account, args[:chave])
      end
    end
```

(d) `.env.example` — logo depois do bloco `RAMON_FLUXO_REUNIOES` (e dos que a B4.2/B4.3 puseram):

```
# ramon: lead ganho pelo fluxo (B4.4). on + o fluxo "Lead ganho" em modo normal = o fluxo faz dossie, NPS e o caso no
# ADVBOX, e o codigo para. Padrao desligado. Virar/voltar: rake ramon:fluxos:migrados:modo[conta,lead_ganho,normal|sombra]
# RAMON_FLUXO_LEAD_GANHO=off
# ramon: eventos do ADVBOX pelo fluxo (B4.5). on + o fluxo "Eventos do ADVBOX" em modo normal = o fluxo faz o que cada
# regra do Flowter fazia, e o codigo para. Padrao desligado. Virar/voltar: rake ramon:fluxos:migrados:modo[conta,eventos_advbox,normal|sombra]
# RAMON_FLUXO_EVENTOS_ADVBOX=off
```

- [ ] **Step 4: Run to verify they pass**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/migrados_spec.rb spec/services/ramon/fluxos/disparo_spec.rb spec/services/ramon/fluxos/reunioes_spec.rb spec/services/ramon/reuniao_agendamento_spec.rb spec/listeners` e `bundle exec rubocop app/services/ramon/fluxos/migrados.rb app/services/ramon/fluxos/disparo.rb lib/tasks/ramon_fluxos.rake spec/services/ramon/fluxos/migrados_spec.rb`
Expected: PASS (os da B4.1 seguem verdes), sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/migrados.rb app/services/ramon/fluxos/disparo.rb lib/tasks/ramon_fluxos.rake .env.example spec/services/ramon/fluxos/migrados_spec.rb spec/services/ramon/fluxos/disparo_spec.rb
git commit -m "feat(fluxos): fluxos migrados com chave própria (lead ganho, eventos do ADVBOX) e decisão pelo evento" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 3: B4.4 — "Lead ganho" (JSON + decisão no callback do Lead)

**Files:**
- Create: `db/seeds/ramon/fluxos/migrados/lead_ganho.json`
- Create: `app/services/ramon/fluxos/lead_ganho.rb`
- Modify: `app/models/lead.rb` (linhas 55–57 e 186–204 da base 079a04c — **só tira linhas**)
- Test: `spec/services/ramon/fluxos/lead_ganho_spec.rb` (novo); `spec/models/lead_spec.rb` (sem mudança — trava do caminho de hoje)

**Interfaces:**
- Consumes: `Ramon::Fluxos::Migrados.{assumiu?, semear, mudar_modo!}` (Task 2); passo `rotina` (Task 1).
- Produces: `Ramon::Fluxos::LeadGanho.ganhou(lead)` (dispara `lead_ganho` com `{'assumido' => Boolean, 'para_etapa_id' => Integer}`; roda `pelo_codigo` só se não assumido); `Ramon::Fluxos::LeadGanho.pelo_codigo(lead)` (dossiê já, `AdvboxClosingJob` com token, `NpsDraftJob`); `Lead#ganhou` (privado, callback).

- [ ] **Step 1: Write the failing test** — criar `spec/services/ramon/fluxos/lead_ganho_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::LeadGanho do
  let(:account) { create(:account) }
  let(:ganho) { account.lead_stages.find_by!(is_won: true) }
  let(:lead) { create(:lead, account: account, name: 'João Pereira') }

  def dossies = lead.lead_notes.where('body LIKE ?', '📋 DOSSIÊ%').count
  def pesquisas = lead.lead_notes.where('body LIKE ?', '%pesquisa NPS%').count

  before do
    allow(Ramon::AdvboxClient).to receive_messages(create_customer: { 'customers_id' => 11 },
                                                    create_lawsuit: { 'lawsuits_id' => 22 }, create_post: { 'posts_id' => 33 })
  end

  describe 'o fluxo "Lead ganho" (semeado)' do
    it 'nasce 1 vez, em sombra, ligado e publicado: dossiê → NPS → ADVBOX (por último, para não segurar o resto)' do
      fluxo = Ramon::Fluxos::Migrados.semear(account, 'lead_ganho')
      expect(Ramon::Fluxos::Migrados.semear(account, 'lead_ganho')).to eq(fluxo)
      expect([fluxo.origem, fluxo.modo, fluxo.ativo, fluxo.gatilho_tipo]).to eq(['usuario', 'sombra', true, 'lead_ganho'])
      rotinas = fluxo.versao_publicada.grafo['nos'].filter_map { |n| n.dig('config', 'rotina') }
      expect(rotinas).to eq(%w[dossie_passagem pesquisa_nps abrir_caso_advbox])
    end
  end

  describe 'a decisão é do evento (lida uma vez no callback do Lead)' do
    it 'código no comando (padrão): dossiê na hora, ADVBOX e NPS na fila — como sempre; o fluxo só ensaia' do
      fluxo = Ramon::Fluxos::Migrados.semear(account, 'lead_ganho')
      with_modified_env(ADVBOX_API_TOKEN: 'tok') do
        expect { lead.update!(lead_stage: ganho) }
          .to have_enqueued_job(Ramon::AdvboxClosingJob).with(lead.id).and have_enqueued_job(Ramon::NpsDraftJob).with(lead.id)
      end
      expect(dossies).to eq(1)
      expect(fluxo.execucoes.pluck(:ensaio)).to eq([true])
    end

    it 'fluxo no comando: o código não faz nada; o fluxo faz dossiê, NPS e abre o caso no ADVBOX, 1 vez cada' do
      with_modified_env(ADVBOX_API_TOKEN: 'tok', RAMON_FLUXO_LEAD_GANHO: 'on') do
        Ramon::Fluxos::Migrados.semear(account, 'lead_ganho')
        Ramon::Fluxos::Migrados.mudar_modo!(account, 'lead_ganho', 'normal')
        expect { lead.update!(lead_stage: ganho) }.not_to have_enqueued_job(Ramon::NpsDraftJob)
        expect(dossies).to eq(0) # o fluxo roda no job, não dentro do update
        perform_enqueued_jobs
      end
      expect([dossies, pesquisas]).to eq([1, 1])
      expect(Ramon::AdvboxClient).to have_received(:create_customer).once
      expect(lead.reload.custom_attributes.dig('advbox', 'lawsuits_id')).to eq(22)
    end

    it 'um desligado na tela devolve ao código, sem ensaio' do
      with_modified_env(ADVBOX_API_TOKEN: 'tok', RAMON_FLUXO_LEAD_GANHO: 'on') do
        fluxo = Ramon::Fluxos::Migrados.semear(account, 'lead_ganho')
        Ramon::Fluxos::Migrados.mudar_modo!(account, 'lead_ganho', 'normal')
        fluxo.update!(ativo: false)
        expect { lead.update!(lead_stage: ganho) }.to have_enqueued_job(Ramon::AdvboxClosingJob).with(lead.id)
        expect(fluxo.execucoes.count).to eq(0)
      end
      expect(dossies).to eq(1)
    end
  end
end
```

Rastreio: `create(:lead)` nasce na 1ª etapa (sem `won_at`); `update!(lead_stage: ganho)` → `track_stage_cycle` grava `won_at` → `after_update_commit :ganhou` (o teste transacional do Rails ≥ 5 dispara `after_commit`, como no `lead_spec`). "Fluxo no comando": `perform_enqueued_jobs` (sem bloco) roda o `FluxoAvancarJob` (e os de evento); dentro do fluxo, NPS é `perform_now` e o ADVBOX é síncrono — nada novo fica na fila. O `with_modified_env` envolve o `perform_enqueued_jobs` (o token é lido quando o passo roda). Desligado: `executaveis` exclui → `Disparo` acha 0 fluxos, `assumiu?` falso → código.

- [ ] **Step 2: Run to verify it fails**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/lead_ganho_spec.rb`
Expected: FAIL — `ENOENT … migrados/lead_ganho.json` / `uninitialized constant Ramon::Fluxos::LeadGanho`.

- [ ] **Step 3: Implementation**

(a) Criar `db/seeds/ramon/fluxos/migrados/lead_ganho.json`:

```json
{
  "nome": "Lead ganho",
  "descricao": "Quando o lead é ganho, no lugar do código (B4.4): dossiê de passagem nas notas do lead, rascunho da pesquisa NPS (uma vez só) e o caso aberto no ADVBOX — cliente, processo na etapa CONTRATO FECHADO e tarefa 1º CONTATO. O ADVBOX grava de verdade, só com o token, nunca abre de novo um caso já aberto e fica por último: se estiver fora do ar, tenta de novo sem segurar o resto. O Drive continua no código. Contrato fechado no ADVBOX também chega aqui (o evento move o lead para o ganho). Enquanto o selo disser \"em sombra\", só ensaia: quem faz ainda é o código.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"lead_ganho","cancelar_se_sair_da_etapa":false},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"rotina","config":{"rotulo":"Dossiê de passagem para o jurídico (nas notas do lead)","rotina":"dossie_passagem"},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"rotina","config":{"rotulo":"Rascunho: pesquisa NPS do ganho (nas notas do lead, 1 vez só)","rotina":"pesquisa_nps"},"posicao":{"x":0,"y":280}},
      {"id":"n4","tipo":"rotina","config":{"rotulo":"ADVBOX: cliente, processo e tarefa 1º contato (grava no ADVBOX, só com token)","rotina":"abrir_caso_advbox"},"posicao":{"x":0,"y":420}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"s","para":"n3"},
      {"de":"n3","saida":"s","para":"n4"}
    ]
  }
}
```

(b) Criar `app/services/ramon/fluxos/lead_ganho.rb`:

```ruby
# B4.4 (spec §8): o que o hub faz quando o lead é ganho — dossiê de passagem, caso no ADVBOX e rascunho da pesquisa NPS —
# pelo código (como sempre) ou pelo fluxo "Lead ganho", conforme a chave (RAMON_FLUXO_LEAD_GANHO + o fluxo em modo normal).
# A decisão é do evento: lida UMA vez aqui e mandada no gatilho. Contrato fechado no ADVBOX também chega aqui (o evento
# move o lead para o ganho), pelo caminho que for — por isso nunca roda em dobro.
# Fluxo ocupado com o mesmo lead (ganho de novo com a execução anterior viva) NÃO cai no código: a viva já faz tudo, e
# o ADVBOX não pode rodar em paralelo. O Drive fica no código (Lead#enqueue_drive_export: roda a cada atualização dos
# documentos, não só no ganho).
module Ramon::Fluxos::LeadGanho
  module_function

  def ganhou(lead)
    assumido = Ramon::Fluxos::Migrados.assumiu?(lead.account, 'lead_ganho')
    Ramon::Fluxos::Disparo.externo('lead_ganho', lead, { 'assumido' => assumido, 'para_etapa_id' => lead.lead_stage_id })
    pelo_codigo(lead) unless assumido
  end

  # O caminho de hoje, como morava nos callbacks do Lead (sai na limpeza, E7).
  def pelo_codigo(lead)
    Leads::HandoffNoteService.new(lead: lead).perform
    Ramon::AdvboxClosingJob.perform_later(lead.id) if ENV.fetch('ADVBOX_API_TOKEN', nil).present?
    Ramon::NpsDraftJob.perform_later(lead.id)
  end
end
```

(c) `app/models/lead.rb` — trocar as 3 linhas

```ruby
  after_update_commit :generate_handoff_note, if: :saved_change_to_won_at?
  after_update_commit :enqueue_advbox_closing, if: :saved_change_to_won_at?
  after_update_commit :enqueue_nps_draft, if: :saved_change_to_won_at?
```
por

```ruby
  after_update_commit :ganhou, if: :saved_change_to_won_at?
```
e trocar os 3 métodos privados `generate_handoff_note`, `enqueue_advbox_closing` e `enqueue_nps_draft` (com os comentários deles; da linha `def generate_handoff_note` até o `end` de `enqueue_nps_draft`) por

```ruby
  # Lead ganho (dossiê, caso no ADVBOX, NPS): pelo código ou pelo fluxo "Lead ganho" — decide Ramon::Fluxos::LeadGanho (B4.4).
  def ganhou
    Ramon::Fluxos::LeadGanho.ganhou(self) if won_at.present?
  end
```
`enqueue_drive_export` e o callback dele ficam como estão. Conferir: `grep -rn "generate_handoff_note\|enqueue_advbox_closing\|enqueue_nps_draft" app spec lib enterprise` → vazio.

- [ ] **Step 4: Run to verify it passes**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/lead_ganho_spec.rb spec/models/lead_spec.rb spec/services/leads` e `bundle exec rubocop app/models/lead.rb app/services/ramon/fluxos/lead_ganho.rb spec/services/ramon/fluxos/lead_ganho_spec.rb`
Expected: PASS (o `lead_spec` — "enfileira o job quando o lead vira ganho com token", "NpsDraftJob…", "não enfileira quando sai de ganho", Drive — segue verde sem mudança), sem ofensas; `grep -cvE '^\s*(#|$)' app/models/lead.rb` **menor** que o do Task 0.

- [ ] **Step 5: Commit**

```bash
git add db/seeds/ramon/fluxos/migrados/lead_ganho.json app/services/ramon/fluxos/lead_ganho.rb app/models/lead.rb spec/services/ramon/fluxos/lead_ganho_spec.rb
git commit -m "feat(fluxos): lead ganho pelo fluxo com chave própria (dossiê, NPS e caso no ADVBOX) — B4.4" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 4: B4.5 parte 1 — efeitos do ADVBOX saem do processador + decisão pelo evento (comportamento igual)

**Files:**
- Create: `app/services/ramon/advbox_event_regras.rb`
- Create: `app/services/ramon/fluxos/eventos_advbox.rb`
- Modify: `app/services/ramon/advbox_event_processor.rb` (**só tira linhas**)
- Test: `spec/services/ramon/fluxos/eventos_advbox_spec.rb` (novo); `spec/services/ramon/advbox_event_processor_spec.rb` (1º exemplo)

**Interfaces:**
- Consumes: `Ramon::Fluxos::Migrados.assumiu?` (Task 2); `Disparo::NA_HORA` com `evento_advbox` (Task 2).
- Produces: `Ramon::AdvboxEventRegras.new(account).<regra>(lead, nome)` — os 10 métodos públicos de sempre (`contrato_fechado`, `requerimento_protocolado`, `indeferimento`, `decisao`, `exigencia`, `reativacao_futura`, `exito`, `marco`, `concessao`, `arquivado`); `Ramon::Fluxos::EventosAdvbox.processar(lead, regra, nome)` (regra String); `Ramon::Fluxos::EventosAdvbox.primeiro_nome(lead) → String`.

- [ ] **Step 1: Write the failing tests**

(a) Criar `spec/services/ramon/fluxos/eventos_advbox_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::EventosAdvbox do
  # A conta seeda o funil no after_create (Novo ... Fechado is_won / Perdido is_lost).
  let(:account) { create(:account) }
  let(:lead) { novo_lead('+5548999000001') }

  def novo_lead(fone)
    contato = create(:contact, account: account, phone_number: fone)
    create(:lead, account: account, lead_stage: account.lead_stages.order(:position).first, contact: contato, name: 'Maria da Silva')
  end

  def migrado(modo: 'sombra')
    fluxo_publicado(account, grafo_linear({ 'tipo' => 'evento_advbox', 'cancelar_se_sair_da_etapa' => false },
                                          ['registrar_atividade', { 'texto' => 'pelo fluxo: {texto}' }]),
                    origem: 'usuario', sistema_chave: 'eventos_advbox', modo: modo)
  end

  def atividades(kinds) = lead.lead_activities.where(kind: kinds).order(:id).pluck(:kind)

  describe 'a decisão é do evento (lida uma vez)' do
    it 'código no comando (padrão): o código faz; o fluxo migrado só ensaia, antes, na hora' do
      fluxo = migrado
      described_class.processar(lead, 'marco', 'SENTENCA PROFERIDA')
      expect(atividades(%w[advbox_marco fluxo])).to eq(['advbox_marco'])
      expect(fluxo.execucoes.pluck(:ensaio, :status)).to eq([[true, 'concluida']])
    end

    it 'fluxo no comando: só o fluxo age, na hora (dentro do job do ADVBOX); o código não faz nada' do
      fluxo = migrado(modo: 'normal')
      with_modified_env(RAMON_FLUXO_EVENTOS_ADVBOX: 'on') { described_class.processar(lead, 'marco', 'SENTENCA PROFERIDA') }
      expect(atividades(%w[advbox_marco fluxo])).to eq(['fluxo'])
      expect(lead.lead_activities.find_by(kind: 'fluxo').to_value).to eq('pelo fluxo: SENTENCA PROFERIDA')
      expect(fluxo.execucoes.pluck(:ensaio, :status)).to eq([[false, 'concluida']])
    end

    it 'fluxo no comando mas ocupado com o mesmo lead (execução viva): o código faz este evento — nada se perde, nada em dobro' do
      fluxo = migrado(modo: 'normal')
      fluxo.execucoes.create!(account: account, alvo: lead, status: 'esperando', retomar_em: 5.minutes.from_now)
      with_modified_env(RAMON_FLUXO_EVENTOS_ADVBOX: 'on') { described_class.processar(lead, 'marco', 'SENTENCA PROFERIDA') }
      expect(atividades(%w[advbox_marco fluxo])).to eq(['advbox_marco'])
    end

    it 'os fluxos comuns de evento do ADVBOX seguem como sempre: depois, sem a decisão, com as variáveis do código' do
      comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'evento_advbox' }, ['registrar_atividade', { 'texto' => 'comum' }]))
      travel_to(Time.zone.parse('2026-10-07 13:00:00 UTC')) { described_class.processar(lead, 'marco', 'SENTENCA PROFERIDA') }
      expect(comum.execucoes.sole.contexto['gatilho'])
        .to eq('regra' => 'marco', 'texto' => 'SENTENCA PROFERIDA', 'primeiro_nome' => 'Maria', 'hoje' => '07/10/2026')
    end
  end

  it 'primeiro nome como o código escreve nos rascunhos: lead sem nome vira "cliente"' do
    expect([described_class.primeiro_nome(lead), described_class.primeiro_nome(Lead.new(name: nil))]).to eq(%w[Maria cliente])
  end
end
```

Rastreio: no "ocupado", a execução criada à mão (não-ensaio, `esperando`) ocupa o índice único → o `create!` do `Disparo#iniciar` levanta `RecordNotUnique` → `nil` → `filter_map` devolve `[]` → `feitas.empty?` → código. No "comum", o fluxo do usuário (gatilho sem `regras`) não é migrado → só responde ao 2º disparo (sem `assumido`); não é `NA_HORA`-migrado → fica `esperando` com o contexto gravado (`Disparo#contexto` → `'gatilho' => @dados`).

(b) Em `spec/services/ramon/advbox_event_processor_spec.rb`, trocar o 1º exemplo por:

```ruby
  it 'evento com regra passa pela decisão do ADVBOX (fluxo migrado com a decisão, e os comuns depois); sem regra, não' do
    allow(Ramon::Fluxos::Disparo).to receive(:externo).and_return([])
    travel_to(Time.zone.parse('2026-10-07 13:00:00 UTC')) { process({ 'stage' => 'SENTENCA PROFERIDA', 'cpf' => '52998224725' }) }
    dados = { 'regra' => 'marco', 'texto' => 'SENTENCA PROFERIDA', 'primeiro_nome' => 'Maria', 'hoje' => '07/10/2026' }
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('evento_advbox', lead, dados.merge('assumido' => false))
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('evento_advbox', lead, dados)
    process({ 'stage' => 'ETAPA QUE NAO EXISTE', 'cpf' => '52998224725' })
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).twice
  end
```
Os demais exemplos do arquivo **não mudam** (o código está no comando por padrão): eles são a trava de que a cópia para `AdvboxEventRegras` é literal.

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/eventos_advbox_spec.rb spec/services/ramon/advbox_event_processor_spec.rb`
Expected: FAIL — `uninitialized constant Ramon::Fluxos::EventosAdvbox`; o processador dispara 1 vez com `{'regra','texto'}`.

- [ ] **Step 3: Implementation**

(a) Criar `app/services/ramon/advbox_event_regras.rb` — **cópia literal** dos métodos de `app/services/ramon/advbox_event_processor.rb` (seção `# -- fluxos --` = os 10 handlers, públicos aqui; seção `# -- efeitos --` = `activity`, `follow_up`, `draft_note`, `nps_draft`, `notify`, `first_name`, `today_br`, privados):

```ruby
# Os efeitos de cada regra do ADVBOX como o código sempre fez — saíram do Ramon::AdvboxEventProcessor na B4.5 sem mudar
# nada. Quem chama é Ramon::Fluxos::EventosAdvbox: quando o fluxo "Eventos do ADVBOX" não está no comando, ou não pegou
# o evento. Sai na limpeza (E7), junto com o JSON sistema/eventos_advbox.json.
#
# Regra de aprovação: nenhum fluxo fala com o cliente — mensagens viram LeadNote "RASCUNHO" e quem envia é o Eduardo.
class Ramon::AdvboxEventRegras
  def initialize(account)
    @account = account
  end

  def contrato_fechado(lead, name)
    won_stage = @account.lead_stages.find_by(is_won: true)
    lead.update!(lead_stage: won_stage) if won_stage && !lead.lead_stage.is_won
    activity(lead, 'advbox_contrato_fechado', "ADVBOX: #{name}")
    notify(lead, 'Contrato fechado no ADVBOX', "#{lead.name}: lead marcado como ganho no hub")
  end

  def requerimento_protocolado(lead, name)
    activity(lead, 'advbox_inss_protocolado', "ADVBOX: #{name} em #{today_br}")
    follow_up(lead, 'Verificar decisão/exigência do INSS (protocolo ADVBOX)', 45.days)
    notify(lead, 'Requerimento protocolado no INSS', "#{lead.name}: follow-up de 45 dias criado")
  end

  def indeferimento(lead, name)
    activity(lead, 'advbox_indeferido', "ADVBOX: #{name}")
    follow_up(lead, 'Avaliar judicialização — INSS negou (ADVBOX)', 1.day)
    draft_note(lead, <<~NOTA)
      RASCUNHO (revisar antes de enviar) — INSS negou:
      "Oi #{first_name(lead)}, tudo bem? Saiu a decisão do INSS sobre o seu pedido e, infelizmente, foi negativa.
      Isso não é o fim: muitos casos como o seu são revertidos na Justiça. Posso te explicar os próximos passos?"
    NOTA
    notify(lead, 'INSS NEGOU - avaliar judicializacao', "#{lead.name}: tarefa na Esteira + rascunho de mensagem no caso")
  end

  def decisao(lead, name)
    activity(lead, 'advbox_decisao', "ADVBOX: #{name}")
    follow_up(lead, 'Analisar decisão registrada no ADVBOX', 2.days)
    notify(lead, 'Decisao proferida (ADVBOX)', "#{lead.name}: analisar e decidir comunicação")
  end

  def exigencia(lead, name)
    activity(lead, 'advbox_exigencia', "ADVBOX: #{name}")
    follow_up(lead, 'Cumprir exigência do INSS — prazo curto (ADVBOX)', 2.days)
    draft_note(lead, <<~NOTA)
      RASCUNHO (revisar antes de enviar) — exigência do INSS:
      "Oi #{first_name(lead)}! O INSS pediu um documento a mais no seu processo. Pode me mandar por aqui quando conseguir? Te ajudo com o que precisar."
    NOTA
    notify(lead, 'Carta de exigencias do INSS', "#{lead.name}: prazo curto — tarefa + rascunho criados")
  end

  def reativacao_futura(lead, name)
    activity(lead, 'advbox_reativacao_futura', "ADVBOX: #{name}")
    follow_up(lead, 'Reativação: benefício futuro — retomar contato', 180.days)
  end

  def exito(lead, name)
    activity(lead, 'advbox_exito', "ADVBOX: #{name}")
    draft_note(lead, <<~NOTA)
      RASCUNHO (revisar antes de enviar) — comunicado de êxito:
      "#{first_name(lead)}, ótima notícia! 🎉 Saiu o pagamento do seu processo. Foi uma alegria acompanhar seu caso até aqui.
      Se puder, sua avaliação no Google ajuda muito outras pessoas a nos encontrarem."
    NOTA
    nps_draft(lead)
    notify(lead, 'Exito: pagamento no ADVBOX', "#{lead.name}: rascunho de comunicado pronto no caso")
  end

  def concessao(lead, name)
    activity(lead, 'advbox_concessao', "ADVBOX: #{name}")
    draft_note(lead, <<~NOTA)
      RASCUNHO (revisar antes de enviar) — benefício concedido:
      "#{first_name(lead)}, notícia boa! 🎉 O INSS CONCEDEU o seu benefício. Agora vamos conferir a implantação e os valores — te aviso de cada passo."
    NOTA
    nps_draft(lead)
    notify(lead, 'Beneficio CONCEDIDO (ADVBOX)', "#{lead.name}: rascunho de boa notícia pronto no caso")
  end

  def marco(lead, name)
    activity(lead, 'advbox_marco', "ADVBOX: #{name}")
    notify(lead, 'Marco processual (ADVBOX)', "#{lead.name}: #{name}")
  end

  def arquivado(lead, name)
    lead.lead_tasks.open_tasks.update_all(completed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    activity(lead, 'advbox_arquivado', "ADVBOX: #{name} — follow-ups do hub encerrados")
  end

  private

  def activity(lead, kind, text)
    lead.lead_activities.create!(account: @account, kind: kind, to_value: text.truncate(255))
  end

  def follow_up(lead, title, due_in)
    lead.lead_tasks.create!(account: @account, kind: 'follow_up', title: title.truncate(255), due_at: due_in.from_now)
  end

  def draft_note(lead, body)
    lead.lead_notes.create!(account: @account, body: body.strip.truncate(1000))
  end

  # Pesquisa NPS da fase de êxito — o guard nps.pedido_exito_em (dentro do job)
  # garante que a fase pede uma vez só.
  def nps_draft(lead)
    Ramon::NpsDraftJob.perform_later(lead.id, fase: 'exito')
  end

  def notify(lead, title, body)
    return if ENV.fetch('NTFY_TOPIC', nil).blank?

    Ramon::NtfyPushJob.perform_later(lead.id, title: title, body: body)
  end

  def first_name(lead)
    lead.name.to_s.split.first.presence || 'cliente'
  end

  def today_br
    Time.zone.today.strftime('%d/%m/%Y')
  end
end
```
Conferir a cópia: `diff <(sed -n '/# -- fluxos/,/# -- extração/p' <processador na base>) …` — o jeito simples: antes de apagar do processador, `git show HEAD:app/services/ramon/advbox_event_processor.rb > /tmp/antes.rb` (use o scratchpad) e comparar método a método; nenhum texto muda.

(b) Criar `app/services/ramon/fluxos/eventos_advbox.rb`:

```ruby
# B4.5 (spec §8): o que o hub faz quando o ADVBOX avisa uma etapa/tarefa (Flowter → Ramon::AdvboxEventProcessor) — pelo
# código (Ramon::AdvboxEventRegras, como sempre) ou pelo fluxo "Eventos do ADVBOX", conforme a chave
# (RAMON_FLUXO_EVENTOS_ADVBOX + o fluxo em modo normal). A decisão é do evento: lida UMA vez aqui.
# 1) o fluxo migrado, na hora (Disparo::NA_HORA), com 'assumido' — age, ou ensaia antes do código;
# 2) o código, se o fluxo não está no comando OU não pegou o evento (o mesmo lead ainda numa execução viva, motor com
#    erro, fluxo desligado no meio) — nada se perde;
# 3) os fluxos comuns de evento do ADVBOX, sem 'assumido', como sempre.
# Contrato fechado só move o lead para o ganho; dossiê/ADVBOX/NPS são do Lead ganho, que decide sozinho (LeadGanho).
module Ramon::Fluxos::EventosAdvbox
  module_function

  def processar(lead, regra, nome)
    dados = { 'regra' => regra, 'texto' => nome, 'primeiro_nome' => primeiro_nome(lead), 'hoje' => Time.zone.today.strftime('%d/%m/%Y') }
    assumido = Ramon::Fluxos::Migrados.assumiu?(lead.account, 'eventos_advbox')
    feitas = Ramon::Fluxos::Disparo.externo('evento_advbox', lead, dados.merge('assumido' => assumido))
    Ramon::AdvboxEventRegras.new(lead.account).public_send(regra, lead, nome) if !assumido || feitas.empty?
    Ramon::Fluxos::Disparo.externo('evento_advbox', lead, dados)
  end

  # Como o código escreve nos rascunhos (Ramon::AdvboxEventRegras#first_name) — vai pronto no gatilho como {primeiro_nome}.
  def primeiro_nome(lead) = lead.name.to_s.split.first.presence || 'cliente'
end
```

(c) `app/services/ramon/advbox_event_processor.rb`:
- no cabeçalho, trocar as 2 linhas `# Regra de aprovação: nenhum fluxo fala com o cliente — mensagens viram` / `# LeadNote "RASCUNHO" e quem envia é o Eduardo.` por:

```ruby
# Os efeitos de cada regra: Ramon::AdvboxEventRegras (código) ou o fluxo "Eventos do ADVBOX" — quem decide, uma vez por
# evento, é Ramon::Fluxos::EventosAdvbox (B4.5).
```
- no `perform`, trocar

```ruby
    send(handler, lead, name)
    @event.update!(status: 'processed', note: "#{name} -> lead ##{lead.id}".truncate(255))
    Ramon::Fluxos::Disparo.externo('evento_advbox', lead, 'regra' => handler.to_s, 'texto' => name)
```
por

```ruby
    Ramon::Fluxos::EventosAdvbox.processar(lead, handler.to_s, name)
    @event.update!(status: 'processed', note: "#{name} -> lead ##{lead.id}".truncate(255))
```
- apagar inteira a seção `# -- fluxos ---…` (do comentário até a linha antes de `# -- extração defensiva ---`) e a seção `# -- efeitos ---…` (do comentário até a linha antes do `end` final da classe). `RULES`, `detect_rule`, `resolve_lead` e os auxiliares de extração ficam.

Conferir: `grep -n "def \(contrato_fechado\|activity\|notify\|today_br\)" app/services/ramon/advbox_event_processor.rb` → vazio; `grep -cvE '^\s*(#|$)' app/services/ramon/advbox_event_processor.rb` ≈ 105.

- [ ] **Step 4: Run to verify they pass**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/eventos_advbox_spec.rb spec/services/ramon/advbox_event_processor_spec.rb spec/jobs/ramon spec/requests` (o webhook do ADVBOX) e `bundle exec rubocop app/services/ramon/advbox_event_regras.rb app/services/ramon/fluxos/eventos_advbox.rb app/services/ramon/advbox_event_processor.rb spec/services/ramon/fluxos/eventos_advbox_spec.rb`
Expected: PASS — os 13 exemplos antigos do processador seguem verdes sem mudança (a cópia é literal), sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/advbox_event_regras.rb app/services/ramon/fluxos/eventos_advbox.rb app/services/ramon/advbox_event_processor.rb spec/services/ramon/fluxos/eventos_advbox_spec.rb spec/services/ramon/advbox_event_processor_spec.rb
git commit -m "refactor(advbox): efeitos das regras saem do processador e a decisão código × fluxo é do evento — B4.5" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 5: B4.5 parte 2 — o fluxo "Eventos do ADVBOX" (JSON) fiel às 10 regras + contrato fechado nunca em dobro

**Files:**
- Create: `db/seeds/ramon/fluxos/migrados/eventos_advbox.json`
- Test: `spec/services/ramon/fluxos/eventos_advbox_spec.rb` (acrescentar 2 `describe`)

**Interfaces:**
- Consumes: tudo das Tasks 1–4.
- Produces: o fluxo "Eventos do ADVBOX" semeável (`Migrados.semear(account, 'eventos_advbox')`), com a `escolha` pela `{regra}` e um ramo por regra.

- [ ] **Step 1: Write the failing tests** — em `spec/services/ramon/fluxos/eventos_advbox_spec.rb`, antes do exemplo `primeiro nome…`:

```ruby
  describe 'o fluxo faz o mesmo que o código, regra a regra (atividades, tarefas, rascunhos, etapa)' do
    let(:pelo_codigo) { novo_lead('+5548999000011') }
    let(:pelo_fluxo) { novo_lead('+5548999000012') }

    # o que fica no lead; o dossiê muda de lead para lead (link da ficha) — só o começo conta
    def rastro(alvo)
      alvo.reload
      { atividades: alvo.lead_activities.where.not(kind: 'created').order(:id).pluck(:kind, :to_value),
        tarefas: alvo.lead_tasks.order(:id).pluck(:kind, :title, :completed_at).map { |k, t, feita| [k, t, feita.present?] },
        notas: alvo.lead_notes.order(:id).pluck(:body).map { |b| b.start_with?('📋') ? '📋 DOSSIÊ' : b },
        etapa: alvo.lead_stage.name }
    end

    { 'contrato_fechado' => 'CONTRATO FECHADO', 'requerimento_protocolado' => 'REQUERIMENTO PROTOCOLADO',
      'indeferimento' => 'NEGADO / AVISAR CLIENTE', 'decisao' => 'DECISAO PROFERIDA', 'exigencia' => 'CARTA DE EXIGENCIAS',
      'reativacao_futura' => 'BENEFICIO FUTURO / ANOTAR NA AGENDA', 'exito' => 'PAGAMENTO RECEBIDO / PAGAR CLIENTE',
      'marco' => 'SENTENCA PROFERIDA', 'concessao' => 'BENEFICIO CONCEDIDO / IMPLANTACAO',
      'arquivado' => 'ARQUIVADO/ENCERRADO' }.each do |regra, nome|
      it "#{regra}: o lead fica igual pelos dois caminhos" do
        [pelo_codigo, pelo_fluxo].each { |l| l.lead_tasks.create!(account: account, kind: 'other', title: 'Aberta', due_at: 1.day.from_now) }
        perform_enqueued_jobs { described_class.processar(pelo_codigo, regra, nome) } # código no comando (sem env, sem fluxo)
        with_modified_env(RAMON_FLUXO_EVENTOS_ADVBOX: 'on') do
          Ramon::Fluxos::Migrados.semear(account, 'eventos_advbox')
          Ramon::Fluxos::Migrados.mudar_modo!(account, 'eventos_advbox', 'normal')
          perform_enqueued_jobs { described_class.processar(pelo_fluxo, regra, nome) }
        end
        expect(rastro(pelo_fluxo)).to eq(rastro(pelo_codigo))
      end
    end
  end

  describe 'contrato fechado nunca faz o Lead ganho em dobro (nem deixa de fazer)' do
    [[false, false], [true, false], [false, true], [true, true]].each do |advbox_flui, ganho_flui|
      it "eventos pelo #{advbox_flui ? 'fluxo' : 'código'}, lead ganho pelo #{ganho_flui ? 'fluxo' : 'código'}: 1 de cada" do
        allow(Ramon::AdvboxClient).to receive_messages(create_customer: { 'customers_id' => 11 },
                                                        create_lawsuit: { 'lawsuits_id' => 22 }, create_post: { 'posts_id' => 33 })
        allow(Ramon::Fluxos::LeadGanho).to receive(:pelo_codigo).and_call_original
        allow(Ramon::AdvboxEventRegras).to receive(:new).and_call_original
        with_modified_env(ADVBOX_API_TOKEN: 'tok', RAMON_FLUXO_EVENTOS_ADVBOX: 'on', RAMON_FLUXO_LEAD_GANHO: 'on') do
          %w[eventos_advbox lead_ganho].each { |chave| Ramon::Fluxos::Migrados.semear(account, chave) }
          Ramon::Fluxos::Migrados.mudar_modo!(account, 'eventos_advbox', 'normal') if advbox_flui
          Ramon::Fluxos::Migrados.mudar_modo!(account, 'lead_ganho', 'normal') if ganho_flui
          perform_enqueued_jobs { described_class.processar(lead, 'contrato_fechado', 'CONTRATO FECHADO') }
        end
        notas = lead.reload.lead_notes.pluck(:body)
        # as travas (5 min, 1 vez, sincronizado_em) escondem dobra nos efeitos: contar QUEM decidiu fazer
        expect(Ramon::AdvboxEventRegras).to have_received(:new).exactly(advbox_flui ? 0 : 1).times
        expect(Ramon::Fluxos::LeadGanho).to have_received(:pelo_codigo).exactly(ganho_flui ? 0 : 1).times
        expect(FluxoExecucao.where(alvo: lead, ensaio: false).count).to eq([advbox_flui, ganho_flui].count(true))
        expect([notas.count { |b| b.start_with?('📋') }, notas.count { |b| b.include?('pesquisa NPS') }]).to eq([1, 1])
        expect(Ramon::AdvboxClient).to have_received(:create_customer).once
        expect(lead.lead_activities.where(kind: 'advbox_contrato_fechado').count).to eq(1)
      end
    end
  end
```

Rastreio:
- Fidelidade: o lado código roda antes de existir o fluxo (sem env, sem semear) → `Regras`; dentro, `contrato_fechado` move para o ganho → `Lead#ganhou` → lead ganho pelo código (sem env de lead ganho) → dossiê + `NpsDraftJob` (o bloco `perform_enqueued_jobs` roda) → nota NPS. Lado fluxo: mesmo caminho do lead ganho; o resto pelo fluxo. Tarefas comparam `[tipo, título, concluída?]` (vencimento e dono diferem por desenho — N3; sem Closer/SDR no teste os dois dão `nil`). `exito`/`concessao`: código enfileira `NpsDraftJob(fase: exito)` (roda no bloco); fluxo chama `perform_now` → mesma nota. `requerimento_protocolado`: `{hoje}` e `today_br` no mesmo dia (mesmo exemplo). Push fora (sem `NTFY_TOPIC`). `stage_changed` sai do callback do Lead nos dois lados (`Current.user` nil). Dois leads com contatos de telefones diferentes; o `let` é preguiçoso: `pelo_codigo` e `pelo_fluxo` nascem na 1ª linha do exemplo, antes de qualquer fluxo existir.
- Nunca em dobro: `perform_enqueued_jobs` com bloco roda também o que os jobs enfileiram (FluxoAvancarJob do Lead ganho, `AdvboxClosingJob`, `NpsDraftJob`). Execuções não-ensaio: 1 do "Eventos do ADVBOX" se ele age + 1 do "Lead ganho" se ele age. `exactly(0).times` em `have_received` é aceito pelo rspec-mocks (equivale a `never`). 7 expectativas (limite 7).

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/eventos_advbox_spec.rb`
Expected: FAIL — `ENOENT … migrados/eventos_advbox.json`.

- [ ] **Step 3: Implementation** — criar `db/seeds/ramon/fluxos/migrados/eventos_advbox.json` (textos ao cliente copiados de `Ramon::AdvboxEventRegras`, com as aspas e a quebra de linha do código):

```json
{
  "nome": "Eventos do ADVBOX",
  "descricao": "Quando o ADVBOX avisa uma etapa ou tarefa do processo (Flowter), no lugar do código (B4.5): cada regra atualiza o lead e prepara os próximos passos — atividade, tarefa na Esteira, rascunho ao cliente nas notas do lead (nunca enviado), pesquisa NPS de êxito (uma vez só) e push. Contrato fechado só marca o lead como ganho: o dossiê, o caso no ADVBOX e a NPS do ganho são do fluxo \"Lead ganho\". Se este fluxo estiver ocupado com o mesmo lead, o código faz aquele evento (nada se perde) — por isso, para tirar um efeito, apague o passo do ramo (o filtro de regras do gatilho não desliga nada). Enquanto o selo disser \"em sombra\", só ensaia: quem faz ainda é o código.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"evento_advbox","cancelar_se_sair_da_etapa":false},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"escolha","config":{"rotulo":"Qual regra do ADVBOX?","campo":"regra","casos":[{"chave":"c1","rotulo":"Contrato fechado","valores":["contrato_fechado"]},{"chave":"c2","rotulo":"Requerimento protocolado","valores":["requerimento_protocolado"]},{"chave":"c3","rotulo":"INSS negou","valores":["indeferimento"]},{"chave":"c4","rotulo":"Decisão","valores":["decisao"]},{"chave":"c5","rotulo":"Exigência","valores":["exigencia"]},{"chave":"c6","rotulo":"Benefício futuro","valores":["reativacao_futura"]},{"chave":"c7","rotulo":"Êxito","valores":["exito"]},{"chave":"c8","rotulo":"Marco","valores":["marco"]},{"chave":"c9","rotulo":"Concessão","valores":["concessao"]},{"chave":"c10","rotulo":"Arquivado","valores":["arquivado"]}]},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"mover_etapa","config":{"rotulo":"Marca o lead como ganho (etapa de ganho da conta)","etapa_id":null},"posicao":{"x":-1350,"y":320}},
      {"id":"n4","tipo":"registrar_atividade","config":{"rotulo":"Atividade: contrato fechado","tipo":"advbox_contrato_fechado","texto":"ADVBOX: {texto}"},"posicao":{"x":-1350,"y":470}},
      {"id":"n5","tipo":"avisar_push","config":{"rotulo":"Push: contrato fechado","titulo":"Contrato fechado no ADVBOX","texto":"{nome_completo}: lead marcado como ganho no hub"},"posicao":{"x":-1350,"y":620}},
      {"id":"n6","tipo":"registrar_atividade","config":{"rotulo":"Atividade: requerimento protocolado","tipo":"advbox_inss_protocolado","texto":"ADVBOX: {texto} em {hoje}"},"posicao":{"x":-1050,"y":320}},
      {"id":"n7","tipo":"criar_tarefa","config":{"rotulo":"Follow-up de 45 dias","titulo":"Verificar decisão/exigência do INSS (protocolo ADVBOX)","tipo":"follow_up","prazo_dias":45},"posicao":{"x":-1050,"y":470}},
      {"id":"n8","tipo":"avisar_push","config":{"rotulo":"Push: requerimento protocolado","titulo":"Requerimento protocolado no INSS","texto":"{nome_completo}: follow-up de 45 dias criado"},"posicao":{"x":-1050,"y":620}},
      {"id":"n9","tipo":"registrar_atividade","config":{"rotulo":"Atividade: INSS negou","tipo":"advbox_indeferido","texto":"ADVBOX: {texto}"},"posicao":{"x":-750,"y":320}},
      {"id":"n10","tipo":"criar_tarefa","config":{"rotulo":"Avaliar judicialização em 1 dia","titulo":"Avaliar judicialização — INSS negou (ADVBOX)","tipo":"follow_up","prazo_dias":1},"posicao":{"x":-750,"y":470}},
      {"id":"n11","tipo":"rascunho_texto","config":{"rotulo":"Rascunho: INSS negou (nas notas do lead)","onde":"notas_do_lead","titulo":"INSS negou","texto":"\"Oi {primeiro_nome}, tudo bem? Saiu a decisão do INSS sobre o seu pedido e, infelizmente, foi negativa.\nIsso não é o fim: muitos casos como o seu são revertidos na Justiça. Posso te explicar os próximos passos?\""},"posicao":{"x":-750,"y":620}},
      {"id":"n12","tipo":"avisar_push","config":{"rotulo":"Push: INSS negou","titulo":"INSS NEGOU - avaliar judicializacao","texto":"{nome_completo}: tarefa na Esteira + rascunho de mensagem no caso"},"posicao":{"x":-750,"y":770}},
      {"id":"n13","tipo":"registrar_atividade","config":{"rotulo":"Atividade: decisão proferida","tipo":"advbox_decisao","texto":"ADVBOX: {texto}"},"posicao":{"x":-450,"y":320}},
      {"id":"n14","tipo":"criar_tarefa","config":{"rotulo":"Analisar a decisão em 2 dias","titulo":"Analisar decisão registrada no ADVBOX","tipo":"follow_up","prazo_dias":2},"posicao":{"x":-450,"y":470}},
      {"id":"n15","tipo":"avisar_push","config":{"rotulo":"Push: decisão","titulo":"Decisao proferida (ADVBOX)","texto":"{nome_completo}: analisar e decidir comunicação"},"posicao":{"x":-450,"y":620}},
      {"id":"n16","tipo":"registrar_atividade","config":{"rotulo":"Atividade: carta de exigências","tipo":"advbox_exigencia","texto":"ADVBOX: {texto}"},"posicao":{"x":-150,"y":320}},
      {"id":"n17","tipo":"criar_tarefa","config":{"rotulo":"Cumprir a exigência em 2 dias","titulo":"Cumprir exigência do INSS — prazo curto (ADVBOX)","tipo":"follow_up","prazo_dias":2},"posicao":{"x":-150,"y":470}},
      {"id":"n18","tipo":"rascunho_texto","config":{"rotulo":"Rascunho: exigência do INSS (nas notas do lead)","onde":"notas_do_lead","titulo":"exigência do INSS","texto":"\"Oi {primeiro_nome}! O INSS pediu um documento a mais no seu processo. Pode me mandar por aqui quando conseguir? Te ajudo com o que precisar.\""},"posicao":{"x":-150,"y":620}},
      {"id":"n19","tipo":"avisar_push","config":{"rotulo":"Push: exigência","titulo":"Carta de exigencias do INSS","texto":"{nome_completo}: prazo curto — tarefa + rascunho criados"},"posicao":{"x":-150,"y":770}},
      {"id":"n20","tipo":"registrar_atividade","config":{"rotulo":"Atividade: benefício futuro","tipo":"advbox_reativacao_futura","texto":"ADVBOX: {texto}"},"posicao":{"x":150,"y":320}},
      {"id":"n21","tipo":"criar_tarefa","config":{"rotulo":"Retomar contato em 180 dias","titulo":"Reativação: benefício futuro — retomar contato","tipo":"follow_up","prazo_dias":180},"posicao":{"x":150,"y":470}},
      {"id":"n22","tipo":"registrar_atividade","config":{"rotulo":"Atividade: êxito (pagamento)","tipo":"advbox_exito","texto":"ADVBOX: {texto}"},"posicao":{"x":450,"y":320}},
      {"id":"n23","tipo":"rascunho_texto","config":{"rotulo":"Rascunho: comunicado de êxito (nas notas do lead)","onde":"notas_do_lead","titulo":"comunicado de êxito","texto":"\"{primeiro_nome}, ótima notícia! 🎉 Saiu o pagamento do seu processo. Foi uma alegria acompanhar seu caso até aqui.\nSe puder, sua avaliação no Google ajuda muito outras pessoas a nos encontrarem.\""},"posicao":{"x":450,"y":470}},
      {"id":"n24","tipo":"rotina","config":{"rotulo":"Rascunho: pesquisa NPS de êxito (1 vez só)","rotina":"pesquisa_nps_exito"},"posicao":{"x":450,"y":620}},
      {"id":"n25","tipo":"avisar_push","config":{"rotulo":"Push: êxito","titulo":"Exito: pagamento no ADVBOX","texto":"{nome_completo}: rascunho de comunicado pronto no caso"},"posicao":{"x":450,"y":770}},
      {"id":"n26","tipo":"registrar_atividade","config":{"rotulo":"Atividade: marco processual","tipo":"advbox_marco","texto":"ADVBOX: {texto}"},"posicao":{"x":750,"y":320}},
      {"id":"n27","tipo":"avisar_push","config":{"rotulo":"Push: marco processual","titulo":"Marco processual (ADVBOX)","texto":"{nome_completo}: {texto}"},"posicao":{"x":750,"y":470}},
      {"id":"n28","tipo":"registrar_atividade","config":{"rotulo":"Atividade: benefício concedido","tipo":"advbox_concessao","texto":"ADVBOX: {texto}"},"posicao":{"x":1050,"y":320}},
      {"id":"n29","tipo":"rascunho_texto","config":{"rotulo":"Rascunho: benefício concedido (nas notas do lead)","onde":"notas_do_lead","titulo":"benefício concedido","texto":"\"{primeiro_nome}, notícia boa! 🎉 O INSS CONCEDEU o seu benefício. Agora vamos conferir a implantação e os valores — te aviso de cada passo.\""},"posicao":{"x":1050,"y":470}},
      {"id":"n30","tipo":"rotina","config":{"rotulo":"Rascunho: pesquisa NPS de êxito (1 vez só)","rotina":"pesquisa_nps_exito"},"posicao":{"x":1050,"y":620}},
      {"id":"n31","tipo":"avisar_push","config":{"rotulo":"Push: concessão","titulo":"Beneficio CONCEDIDO (ADVBOX)","texto":"{nome_completo}: rascunho de boa notícia pronto no caso"},"posicao":{"x":1050,"y":770}},
      {"id":"n32","tipo":"rotina","config":{"rotulo":"Conclui as tarefas abertas do lead","rotina":"concluir_tarefas"},"posicao":{"x":1350,"y":320}},
      {"id":"n33","tipo":"registrar_atividade","config":{"rotulo":"Atividade: arquivado","tipo":"advbox_arquivado","texto":"ADVBOX: {texto} — follow-ups do hub encerrados"},"posicao":{"x":1350,"y":470}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"c1","para":"n3"},{"de":"n3","saida":"s","para":"n4"},{"de":"n4","saida":"s","para":"n5"},
      {"de":"n2","saida":"c2","para":"n6"},{"de":"n6","saida":"s","para":"n7"},{"de":"n7","saida":"s","para":"n8"},
      {"de":"n2","saida":"c3","para":"n9"},{"de":"n9","saida":"s","para":"n10"},{"de":"n10","saida":"s","para":"n11"},{"de":"n11","saida":"s","para":"n12"},
      {"de":"n2","saida":"c4","para":"n13"},{"de":"n13","saida":"s","para":"n14"},{"de":"n14","saida":"s","para":"n15"},
      {"de":"n2","saida":"c5","para":"n16"},{"de":"n16","saida":"s","para":"n17"},{"de":"n17","saida":"s","para":"n18"},{"de":"n18","saida":"s","para":"n19"},
      {"de":"n2","saida":"c6","para":"n20"},{"de":"n20","saida":"s","para":"n21"},
      {"de":"n2","saida":"c7","para":"n22"},{"de":"n22","saida":"s","para":"n23"},{"de":"n23","saida":"s","para":"n24"},{"de":"n24","saida":"s","para":"n25"},
      {"de":"n2","saida":"c8","para":"n26"},{"de":"n26","saida":"s","para":"n27"},
      {"de":"n2","saida":"c9","para":"n28"},{"de":"n28","saida":"s","para":"n29"},{"de":"n29","saida":"s","para":"n30"},{"de":"n30","saida":"s","para":"n31"},
      {"de":"n2","saida":"c10","para":"n32"},{"de":"n32","saida":"s","para":"n33"}
    ]
  }
}
```
Rastreio da fidelidade dos rascunhos: `Passos::Conversa.rascunho_texto` escreve `"#{cabecalho}\n#{texto}".truncate(1000)` com `cabecalho` = `"RASCUNHO (revisar antes de enviar) — <titulo>:"` (o `PREFIXO` sem o `:` final + ` — título:`); o código escreve o heredoc `strip`ado = mesma 1ª linha + `\n` + o texto entre aspas (o `<<~` tira a indentação; a quebra de linha interna fica). `{primeiro_nome}` vem do gatilho (Task 4). `mover_etapa` sem `so_para_frente`: como o código, move qualquer lead que não está no ganho (um lead já no ganho fica igual — o update da mesma etapa não muda nada).

- [ ] **Step 4: Run to verify they pass**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/eventos_advbox_spec.rb spec/services/ramon/fluxos/lead_ganho_spec.rb spec/services/ramon/advbox_event_processor_spec.rb`
Expected: PASS — 10 exemplos "o lead fica igual pelos dois caminhos" e 4 "1 de cada".

- [ ] **Step 5: Commit**

```bash
git add db/seeds/ramon/fluxos/migrados/eventos_advbox.json spec/services/ramon/fluxos/eventos_advbox_spec.rb
git commit -m "feat(fluxos): fluxo Eventos do ADVBOX fiel às 10 regras, contrato fechado nunca em dobro — B4.5" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 6: Editor — passo "Rotina pronta do hub", atividades do ADVBOX, `{hoje}` e os 2 desenhos conferidos

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js`, `validar.js`, `PainelPasso.vue`, `NoPasso.vue`
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json`, `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`
- Test: `specs/PainelPasso.spec.js`, `specs/NoPasso.spec.js`, `specs/validar.spec.js`, `specs/i18n.spec.js`, `specs/migrados.spec.js` (todos em `app/javascript/dashboard/routes/dashboard/captain/automacoes/`)

**Interfaces:**
- Consumes: `Ramon::Fluxos::Passos::Rotina::ROTINAS`, `Passos::Lead::TIPOS_ATIVIDADE`, `Contexto::DO_GATILHO` (Task 1); os 2 JSON (Tasks 3, 5).
- Produces: `fluxo.js` exporta `ROTINAS` (= Ruby), `PASSOS.rotina`, item `rotina` na `PALETA` (grupo `LEAD`), `TIPOS_ATIVIDADE` com os 10 `advbox_*`, `VARIAVEIS` com `hoje`; `validar.js` `OBRIGATORIOS.rotina = ['rotina']`, `RESERVADAS` com `hoje`.

- [ ] **Step 1: Write the failing tests**

(a) `specs/PainelPasso.spec.js` — novo `it` no fim do `describe('PainelPasso')`:

```js
  it('rotina: escolhe da lista e explica o que ela faz', async () => {
    const wrapper = montar({ id: 'n3', data: { tipo: 'rotina', config: {} } });
    await wrapper.find('[data-testid="rotina"]').setValue('pesquisa_nps');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { rotina: 'pesquisa_nps' },
    ]);
    const advbox = montar({
      id: 'n4',
      data: { tipo: 'rotina', config: { rotina: 'abrir_caso_advbox' } },
    });
    expect(advbox.find('[data-testid="rotina-ajuda"]').text()).toContain(
      'Writes to ADVBOX for real'
    );
  });
```

(b) `specs/NoPasso.spec.js` — novo `describe` no fim:

```js
describe('NoPasso — rotina', () => {
  it('mostra o nome da rotina escolhida', () => {
    const w = montar({ tipo: 'rotina', config: { rotina: 'abrir_caso_advbox' } });
    expect(w.text()).toContain('Open the case in ADVBOX');
  });
});
```

(c) `specs/validar.spec.js` — novo `it` dentro do `describe('validar (espelho do Grafo#erros)')`:

```js
  it('rotina pronta precisa dizer qual rotina (espelho do Grafo)', () => {
    expect(codigos(linear(p('p1', 'rotina')))).toEqual([['p1', 'FALTA']]);
    expect(validar(linear(p('p1', 'rotina')))[0].params).toEqual({
      campo: 'rotina',
    });
  });
```

(d) `specs/i18n.spec.js` — importar `ROTINAS` e `TIPOS_ATIVIDADE` de `'../fluxo'` (na lista em ordem alfabética: `REGRAS_ADVBOX, ROTINAS, TIPOS_ATIVIDADE`) e, em "cobre todo o catálogo", logo depois de `PAPEIS.forEach(…)`:

```js
    ROTINAS.forEach(r => {
      expect(FLUXOS_PT.ROTINAS[r]).toBeTruthy();
      expect(FLUXOS_PT.ROTINAS_AJUDA[r]).toBeTruthy();
    });
    TIPOS_ATIVIDADE.forEach(k =>
      expect(FLUXOS_PT.TIPOS_ATIVIDADE[k]).toBeTruthy()
    );
```

(e) `specs/migrados.spec.js` — importar os 2 JSON no topo (mesmo caminho relativo dos da B4.1):

```js
import ganho from '../../../../../../../../db/seeds/ramon/fluxos/migrados/lead_ganho.json';
import eventos from '../../../../../../../../db/seeds/ramon/fluxos/migrados/eventos_advbox.json';
```
e acrescentar no fim do arquivo:

```js
// = Ramon::AdvboxEventRegras (o texto do código, com as aspas e a quebra de linha)
const RASCUNHOS_ADVBOX = {
  'INSS negou':
    '"Oi {primeiro_nome}, tudo bem? Saiu a decisão do INSS sobre o seu pedido e, infelizmente, foi negativa.\nIsso não é o fim: muitos casos como o seu são revertidos na Justiça. Posso te explicar os próximos passos?"',
  'exigência do INSS':
    '"Oi {primeiro_nome}! O INSS pediu um documento a mais no seu processo. Pode me mandar por aqui quando conseguir? Te ajudo com o que precisar."',
  'comunicado de êxito':
    '"{primeiro_nome}, ótima notícia! 🎉 Saiu o pagamento do seu processo. Foi uma alegria acompanhar seu caso até aqui.\nSe puder, sua avaliação no Google ajuda muito outras pessoas a nos encontrarem."',
  'benefício concedido':
    '"{primeiro_nome}, notícia boa! 🎉 O INSS CONCEDEU o seu benefício. Agora vamos conferir a implantação e os valores — te aviso de cada passo."',
};

describe('fluxos migrados: lead ganho e eventos do ADVBOX (B4.4/B4.5)', () => {
  it('os 2 publicam (só falta a etapa de ganho, que o semear põe)', () => {
    [ganho, eventos].forEach(d => expect(semEtapa(d)).toEqual([]));
    expect([ganho, eventos].map(d => d.desenho.nos[0].config)).toEqual([
      { tipo: 'lead_ganho', cancelar_se_sair_da_etapa: false },
      { tipo: 'evento_advbox', cancelar_se_sair_da_etapa: false },
    ]);
  });

  it('lead ganho: dossiê → NPS → ADVBOX por último (fora do ar não segura o resto); o Drive fica no código', () => {
    expect(ganho.desenho.nos.slice(1).map(n => n.config.rotina)).toEqual([
      'dossie_passagem',
      'pesquisa_nps',
      'abrir_caso_advbox',
    ]);
  });

  it('eventos: os 4 rascunhos ao cliente são o texto do código, nas notas do lead e com o título do código', () => {
    const rascunhos = Object.fromEntries(
      doTipo(eventos, 'rascunho_texto').map(n => [n.config.titulo, n.config])
    );
    Object.entries(RASCUNHOS_ADVBOX).forEach(([titulo, texto]) =>
      expect(rascunhos[titulo]).toMatchObject({ onde: 'notas_do_lead', texto })
    );
    expect(Object.keys(rascunhos)).toHaveLength(4);
  });

  it('eventos: uma saída por regra, cada uma com a atividade do código; contrato fechado só marca ganho', () => {
    const casos = eventos.desenho.nos[1].config.casos.map(c => c.valores[0]);
    expect(casos).toEqual(REGRAS_ADVBOX);
    expect(
      doTipo(eventos, 'registrar_atividade').map(n => n.config.tipo)
    ).toEqual(TIPOS_ATIVIDADE.filter(k => k.startsWith('advbox_')));
    const { setas } = eventos.desenho;
    const de = id => setas.find(s => s.de === id)?.para;
    expect([de('n3'), de('n4'), de('n5')]).toEqual(['n4', 'n5', undefined]);
  });

  it('eventos: êxito e concessão pedem a NPS de êxito; arquivado conclui as tarefas antes da atividade', () => {
    expect(doTipo(eventos, 'rotina').map(n => [n.id, n.config.rotina])).toEqual([
      ['n24', 'pesquisa_nps_exito'],
      ['n30', 'pesquisa_nps_exito'],
      ['n32', 'concluir_tarefas'],
    ]);
    expect(eventos.desenho.setas.find(s => s.de === 'n32').para).toBe('n33');
  });

  it('nenhum dos 2 fala com o cliente: o único texto ao cliente é rascunho (e a NPS, que é rascunho)', () => {
    const tipos = [ganho, eventos].flatMap(d => d.desenho.nos.map(n => n.tipo));
    expect([...new Set(tipos)].sort()).toEqual([
      'avisar_push',
      'criar_tarefa',
      'escolha',
      'gatilho',
      'mover_etapa',
      'rascunho_texto',
      'registrar_atividade',
      'rotina',
    ]);
  });
});
```
e importar `REGRAS_ADVBOX` e `TIPOS_ATIVIDADE` de `'../fluxo'` no topo. Rastreio: `doTipo(eventos, 'registrar_atividade')` sai na ordem dos nós (n4, n6, n9, n13, n16, n20, n22, n26, n28, n33) = a ordem de `REGRAS_ADVBOX` = a ordem dos `advbox_*` em `TIPOS_ATIVIDADE` (Step 3). Se a B4.2/B4.3 acrescentaram tipos de atividade **depois** dos de reunião, o filtro `startsWith('advbox_')` mantém o teste certo.

- [ ] **Step 2: Run to verify they fail**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts`
Expected: FAIL nos 5 arquivos acima (`rotina` desconhecido, chaves de i18n faltando, `ROTINAS` não exportado).

- [ ] **Step 3: Implementation**

(a) `fluxo.js`:
- em `PASSOS`, depois de `apagar_reuniao: {…},`:

```js
  rotina: { grupo: 'LEAD', icone: 'i-lucide-package-check', tom: 'slate' },
```
- na `PALETA`, grupo `LEAD`, depois de `{ chave: 'apagar_reuniao', tipo: 'apagar_reuniao' },`:

```js
      { chave: 'rotina', tipo: 'rotina' },
```
- `TIPOS_ATIVIDADE` (mantendo os que a B4.2/B4.3 acrescentaram):

```js
// = Ramon::Fluxos::Passos::Lead::TIPOS_ATIVIDADE (as de reunião e as do ADVBOX aparecem como as do código)
export const TIPOS_ATIVIDADE = [
  'fluxo',
  'meeting_scheduled',
  'meeting_rescheduled',
  'meeting_cancelled',
  'advbox_contrato_fechado',
  'advbox_inss_protocolado',
  'advbox_indeferido',
  'advbox_decisao',
  'advbox_exigencia',
  'advbox_reativacao_futura',
  'advbox_exito',
  'advbox_marco',
  'advbox_concessao',
  'advbox_arquivado',
];
// = Ramon::Fluxos::Passos::Rotina::ROTINAS (B4.4/B4.5: o mesmo código de hoje, com as mesmas travas)
export const ROTINAS = [
  'dossie_passagem',
  'pesquisa_nps',
  'pesquisa_nps_exito',
  'abrir_caso_advbox',
  'concluir_tarefas',
];
```
- em `VARIAVEIS`, depois de `'primeiro_nome',`: `'hoje',`

(b) `validar.js`: em `OBRIGATORIOS`, depois de `trocar_responsavel: ['papel'],` → `rotina: ['rotina'],`; em `RESERVADAS`, depois de `'primeiro_nome',` → `'hoje',`.

(c) `PainelPasso.vue`: importar `ROTINAS` de `'./fluxo'` (na lista em ordem: `PAPEIS, PASSOS, ROTINAS, TIPOS_ATIVIDADE, …`) e, antes de `<p v-else-if="tipo === 'apagar_reuniao'"…>`:

```vue
      <template v-else-if="tipo === 'rotina'">
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.ROTINA`) }}
          <select
            data-testid="rotina"
            :class="SELECT"
            :value="config.rotina || ''"
            @change="muda('rotina', $event.target.value)"
          >
            <option value="" disabled>{{ t(`${K}.PAINEL.ESCOLHA`) }}</option>
            <option v-for="r in ROTINAS" :key="r" :value="r">
              {{ t(`${K}.ROTINAS.${r}`) }}
            </option>
          </select>
        </label>
        <p
          v-if="config.rotina"
          data-testid="rotina-ajuda"
          class="text-xs text-n-slate-10"
        >
          {{ t(`${K}.ROTINAS_AJUDA.${config.rotina}`) }}
        </p>
      </template>
```
(`CAPTAIN_RAMON.FLUXOS.PAINEL.ESCOLHA` já existe — o `ConfigAdvbox.vue` usa.)

(d) `NoPasso.vue`, no `switch` do resumo, antes de `case 'parar':`:

```js
    case 'rotina':
      return c.rotina ? t(`${K}.ROTINAS.${c.rotina}`) : '';
```

(e) i18n — mesma posição nos dois arquivos (dentro de `CAPTAIN_RAMON.FLUXOS`):

| Bloco | Onde | en | pt_BR |
|---|---|---|---|
| `PASSOS` | depois de `"apagar_reuniao"` | `"rotina": "Hub routine"` | `"rotina": "Rotina pronta do hub"` |
| `CABECALHO` | depois de `"apagar_reuniao": "Lead"` | `"rotina": "Lead"` | `"rotina": "Lead"` |
| `PALETA` | depois de `"apagar_reuniao"` | `"rotina": "Hub routine (dossier, NPS, ADVBOX case…)"` | `"rotina": "Rotina pronta do hub (dossiê, NPS, caso no ADVBOX…)"` |
| `PAINEL` (o do editor, onde está `"MOTIVO_PERDA"`) | depois de `"MOTIVO_OUTRO_PLACEHOLDER"` | `"ROTINA": "Which routine"` | `"ROTINA": "Qual rotina"` |
| `CAMPOS_OBRIGATORIOS` | depois de `"responsavel_id"` (pôr vírgula nele) | `"rotina": "the routine"` | `"rotina": "a rotina"` |
| `TIPOS_ATIVIDADE` | depois de `"meeting_cancelled"` (e dos da B4.2/B4.3) | ver abaixo | ver abaixo |
| `ROTINAS` (bloco novo) | logo depois do bloco `TIPOS_ATIVIDADE` | ver abaixo | ver abaixo |
| `ROTINAS_AJUDA` (bloco novo) | logo depois de `ROTINAS` | ver abaixo | ver abaixo |

en:

```json
        "advbox_contrato_fechado": "ADVBOX: contract closed",
        "advbox_inss_protocolado": "ADVBOX: request filed",
        "advbox_indeferido": "ADVBOX: INSS denied",
        "advbox_decisao": "ADVBOX: decision",
        "advbox_exigencia": "ADVBOX: requirement letter",
        "advbox_reativacao_futura": "ADVBOX: future benefit",
        "advbox_exito": "ADVBOX: success",
        "advbox_marco": "ADVBOX: milestone",
        "advbox_concessao": "ADVBOX: benefit granted",
        "advbox_arquivado": "ADVBOX: archived"
      },
      "ROTINAS": {
        "dossie_passagem": "Handoff dossier for the legal team (in the lead notes)",
        "pesquisa_nps": "NPS survey after the win (draft, once)",
        "pesquisa_nps_exito": "NPS survey after the case success (draft, once)",
        "abrir_caso_advbox": "Open the case in ADVBOX (client, lawsuit and 1st contact task)",
        "concluir_tarefas": "Complete the open tasks of the lead"
      },
      "ROTINAS_AJUDA": {
        "dossie_passagem": "The same dossier the code writes. Not repeated if there is one from the last 5 minutes.",
        "pesquisa_nps": "Draft in the lead notes, with the usual text and Google link. Asked once per lead (the success one is separate).",
        "pesquisa_nps_exito": "Draft in the lead notes, with the usual text and Google link. Asked once per lead (the win one is separate).",
        "abrir_caso_advbox": "Writes to ADVBOX for real: client, lawsuit in the CONTRATO FECHADO stage and the 1º CONTATO COM O LEAD task. Only with the ADVBOX token; never opens a case twice; if ADVBOX is down, tries again in 1, 5 and 15 min.",
        "concluir_tarefas": "Completes every open task of the lead in the pipeline."
      },
```
pt_BR:

```json
        "advbox_contrato_fechado": "ADVBOX: contrato fechado",
        "advbox_inss_protocolado": "ADVBOX: requerimento protocolado",
        "advbox_indeferido": "ADVBOX: INSS negou",
        "advbox_decisao": "ADVBOX: decisão",
        "advbox_exigencia": "ADVBOX: carta de exigências",
        "advbox_reativacao_futura": "ADVBOX: benefício futuro",
        "advbox_exito": "ADVBOX: êxito",
        "advbox_marco": "ADVBOX: marco processual",
        "advbox_concessao": "ADVBOX: benefício concedido",
        "advbox_arquivado": "ADVBOX: arquivado"
      },
      "ROTINAS": {
        "dossie_passagem": "Dossiê de passagem para o jurídico (nas notas do lead)",
        "pesquisa_nps": "Pesquisa NPS do ganho (rascunho, 1 vez só)",
        "pesquisa_nps_exito": "Pesquisa NPS do êxito (rascunho, 1 vez só)",
        "abrir_caso_advbox": "Abrir o caso no ADVBOX (cliente, processo e tarefa 1º contato)",
        "concluir_tarefas": "Concluir as tarefas abertas do lead"
      },
      "ROTINAS_AJUDA": {
        "dossie_passagem": "O mesmo dossiê do código. Não repete se já há um dos últimos 5 minutos.",
        "pesquisa_nps": "Rascunho nas notas do lead, com o texto e o link do Google de sempre. Pede uma vez só por lead (a do êxito é outra).",
        "pesquisa_nps_exito": "Rascunho nas notas do lead, com o texto e o link do Google de sempre. Pede uma vez só por lead (a do ganho é outra).",
        "abrir_caso_advbox": "Grava no ADVBOX de verdade: cliente, processo na etapa CONTRATO FECHADO e a tarefa 1º CONTATO COM O LEAD. Só com o token do ADVBOX; nunca abre o mesmo caso duas vezes; ADVBOX fora do ar, tenta de novo em 1, 5 e 15 min.",
        "concluir_tarefas": "Conclui todas as tarefas abertas do lead na Esteira."
      },
```
(O `"meeting_cancelled"` ganha vírgula; o `}` que fechava `TIPOS_ATIVIDADE` é o do snippet. Editar à mão com Edit; nada de `@ | { }` cru.)

- [ ] **Step 4: Run to verify they pass**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts`
Expected: PASS — **mesmos arquivos de B, B + 9 testes** (PainelPasso +1, NoPasso +1, validar +1, migrados +6; o i18n só cresce dentro de um `it`).
Run: `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes`
Expected: sem `error`.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js app/javascript/dashboard/routes/dashboard/captain/automacoes/validar.js app/javascript/dashboard/routes/dashboard/captain/automacoes/PainelPasso.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/NoPasso.vue app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/PainelPasso.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/NoPasso.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/validar.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/i18n.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/migrados.spec.js
git commit -m "feat(fluxos): editor com rotina pronta do hub, atividades do ADVBOX e {hoje}; desenhos do lead ganho e do ADVBOX conferidos" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 7: Verificação final + notas na spec + texto do PR

**Files:**
- Modify: `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (seção nova no fim)

- [ ] **Step 1: Front inteiro**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts
./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes
git status --short
```
Expected: B + 9 testes verdes; eslint sem `error`; `vitest.local.config.ts` fora da lista.

- [ ] **Step 2: Varredura de regras**

```bash
BASE=$(git merge-base HEAD origin/ramon)
git diff $BASE --stat -- app/finders/conversation_finder.rb enterprise db/migrate db/schema.rb db/seeds/ramon/fluxos/sistema
git diff $BASE --numstat -- app/models/lead.rb app/services/ramon/advbox_event_processor.rb
grep -rn "generate_handoff_note\|enqueue_advbox_closing\|enqueue_nps_draft" app spec lib enterprise
grep -rn "RAMON_FLUXO_LEAD_GANHO\|RAMON_FLUXO_EVENTOS_ADVBOX" app lib .env.example
ls db/seeds/ramon/fluxos/migrados
```
Expected: o 1º vazio (sistema/*.json e linhas do sistema ficam — E7); no 2º, as colunas de remoção maiores que as de inclusão nos 2 arquivos do limite; o 3º vazio; as envs em `migrados.rb` (ou no módulo da B4.2) e no `.env.example`; `migrados/` com os 3 da B4.1, os da B4.2/B4.3 e `lead_ganho.json` + `eventos_advbox.json`.

- [ ] **Step 3: Notas na spec** — acrescentar ao fim de `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (número = a próxima seção livre depois das da B4.2/B4.3):

```markdown
## NN. Notas da B4.4/B4.5 (07/10/2026) — lead ganho e eventos do ADVBOX

- **Escopo (Eduardo, 07/10, o mesmo da B4.2):** direto, sem sombra nem comparação — deploy, semear, virar a chave e teste ao vivo. Chave por migração: `RAMON_FLUXO_LEAD_GANHO` / `RAMON_FLUXO_EVENTOS_ADVBOX` =on **e** o fluxo ("Lead ganho" / "Eventos do ADVBOX", `origem: usuario`, `sistema_chave` = `lead_ganho` / `eventos_advbox`) ligado, publicado, em modo normal, sem limite do dia e com o gatilho certo ⇒ o fluxo faz e o código para; qualquer peça fora ⇒ o código faz e o fluxo só ensaia. `rake ramon:fluxos:migrados:{semear,modo}[conta,chave(,modo)]`; voltar = `modo …,sombra`, sem deploy.
- **Passo novo "rotina pronta do hub" (`rotina`):** `dossie_passagem` (`Leads::HandoffNoteService`), `pesquisa_nps` / `pesquisa_nps_exito` (`Ramon::NpsDraftJob`), `abrir_caso_advbox` (`Ramon::AdvboxClosingService`: só com token, nunca de novo com `advbox.sincronizado_em`, id guardado ao nascer; fora do ar → o motor tenta de novo em 1/5/15 min; 4xx anotado no lead e segue), `concluir_tarefas`. É o mesmo código de hoje: o texto da NPS e do dossiê não se edita na tela.
- **A decisão é do evento:** o callback do Lead (`after_update_commit :ganhou`, `won_at` mudou) chama `Ramon::Fluxos::LeadGanho.ganhou`; o `AdvboxEventProcessor` chama `Ramon::Fluxos::EventosAdvbox.processar`. Cada um lê `assumiu?` uma vez e manda `assumido`; `lead_ganho` e `evento_advbox` entraram em `Disparo::PELO_EVENTO` (com `assumido` só os migrados; sem, só os comuns, como sempre). "Eventos do ADVBOX" roda **na hora** (dentro do job do ADVBOX). Se o fluxo do ADVBOX está no comando mas não pega o evento (mesmo lead numa execução viva, motor com erro), o código faz aquele evento — o filtro de regras do gatilho, por isso, não desliga efeito (apague o passo do ramo). O "Lead ganho" não tem essa reserva (a execução viva já faz tudo; o ADVBOX não pode rodar em paralelo).
- **Contrato fechado:** o ADVBOX só move o lead para o ganho (nos dois caminhos); dossiê/ADVBOX/NPS são sempre e só do "Lead ganho" — as 4 combinações de chave dão 1 de cada. Um lead pode ter 2 rascunhos de NPS (ganho e êxito), como antes.
- **Ficou no código:** o Drive (`Lead#enqueue_drive_export` — roda a cada atualização dos documentos, não só no ganho). Os efeitos de hoje mudaram de arquivo: `Ramon::Fluxos::LeadGanho.pelo_codigo` e `Ramon::AdvboxEventRegras` (cópia literal).
- **Motor ganhou:** `{hoje}` (dd/mm/aaaa do código) e `{primeiro_nome}` no gatilho do ADVBOX; `registrar_atividade` com os 10 tipos `advbox_*`; `Ramon::Fluxos::Migrados` (registro por migração).
- **Diferenças aceitas:** tarefas de follow-up do ADVBOX vencem no fim do dia (SP) e ficam com o Closer/SDR; push com o nome do contato; balão "⚙ Fluxo …" na conversa; ADVBOX do ganho por último no fluxo e, fora do ar, 4 tentativas em ~21 min + sino aos admins (antes: 3, em silêncio).
- **Fica para a limpeza (outro PR, 2 semanas depois em normal):** `LeadGanho.pelo_codigo`, os JSON `sistema/lead_ganho.json` e `sistema/eventos_advbox.json` **e** as linhas `origem: sistema` deles, as 2 envs; `Ramon::AdvboxEventRegras` só se o Eduardo decidir abrir mão da reserva "fluxo ocupado ⇒ código" (N6).
```

- [ ] **Step 4: Texto do PR (não abrir — gate do Eduardo)** — deixar no relatório final:

```markdown
Automações em fluxo — B4.4 + B4.5: o que o hub faz quando o **lead é ganho** (dossiê de passagem, caso aberto no ADVBOX, rascunho da pesquisa NPS) e quando o **ADVBOX avisa uma etapa** (as 10 regras do Flowter) ganha 2 fluxos de verdade — "Lead ganho" e "Eventos do ADVBOX" — editáveis na tela depois de assumirem. Cada um tem a sua chave: com ela desligada (padrão) tudo segue pelo código como hoje; ligada e com o fluxo em modo normal, o fluxo faz e o código para; voltar é um comando, sem deploy. O caso no ADVBOX continua com a garantia de hoje (só com token, nunca em dobro, retomando de onde parou) e o contrato fechado do ADVBOX nunca faz o dossiê/ADVBOX/NPS duas vezes, qualquer que seja a combinação de chaves. Mensagens ao cliente continuam rascunho, com o texto de sempre. No editor: passo "Rotina pronta do hub" (dossiê, NPS, caso no ADVBOX, concluir tarefas), atividades do ADVBOX e a variável {hoje}.

## Closes
- Spec `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` §8 (B4+: lead ganho e eventos do ADVBOX) e §14 ("não migrar em dobro"); notas novas no fim.

## How to test
1. Depois do deploy: `rake "ramon:fluxos:migrados:semear[2,lead_ganho]"` e `…[2,eventos_advbox]` → "modo sombra, ligado" e "Agora o CÓDIGO faz".
2. Inteligência → Automações → Meus fluxos: "Lead ganho" (3 rotinas) e "Eventos do ADVBOX" (uma saída por regra), com o selo "em sombra".
3. Lead de teste com a trava do ADVBOX pré-marcada → "Testar com um lead…" no "Lead ganho": a linha do ADVBOX diz "caso já aberto … (não chama de novo)".
4. Virar as 2 chaves e rodar o teste ao vivo da seção "Operação" (contrato fechado + as outras 9 regras no lead de teste): tudo pelo fluxo, nada no ADVBOX.

## What changed
- Passo `rotina` (o mesmo código de hoje como passo), `Ramon::Fluxos::Migrados` (chave por migração), `Ramon::Fluxos::LeadGanho` e `Ramon::Fluxos::EventosAdvbox` (decisão por evento), `Ramon::AdvboxEventRegras` (efeitos de hoje, mudados de arquivo); `Lead` e `AdvboxEventProcessor` ficaram menores. Eventos do ADVBOX migrados rodam na hora; `lead_ganho`/`evento_advbox` disparam com e sem a decisão.
- Rake `ramon:fluxos:migrados:{semear,modo}`; envs `RAMON_FLUXO_LEAD_GANHO` e `RAMON_FLUXO_EVENTOS_ADVBOX` (desligadas). Sem migração. Drive fica no código.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR
```

- [ ] **Step 5: Smoke em bloco** — anotar no relatório a seção "Operação depois do deploy" inteira (o Eduardo roda via `!` e cola as saídas).

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md
git commit -m "docs(fluxos): notas da B4.4/B4.5 na spec" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

Sem push.

---

## Operação depois do deploy

Conta da banca = **2**; console = `docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "<task>"` / `… rails runner '<ruby>'` (Eduardo roda via `!` e cola a saída). Deploy = o de sempre (`docker compose pull chatwoot-web chatwoot-worker && docker compose up -d chatwoot-web chatwoot-worker`), **sem migração**. **Junto com o deploy**, acrescentar ao `chatwoot.env` em `/opt/intranet-ramon`: `RAMON_FLUXO_LEAD_GANHO=on` e `RAMON_FLUXO_EVENTOS_ADVBOX=on` — seguro: sem os fluxos em modo normal, o código segue fazendo tudo.

**1. Semear (código ainda no comando).**
```
docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:migrados:semear[2,lead_ganho]"
docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:migrados:semear[2,eventos_advbox]"
```
Esperado: cada um "Fluxo #… — modo sombra, ligado" e "Agora o CÓDIGO faz (o fluxo só ensaia)". Rodar de novo não duplica.

**2. Lead de teste com a trava do ADVBOX pré-marcada (garante que o teste NÃO grava no ADVBOX).** Sem tese (o Drive não sobe nada), telefone que não existe:
```
docker exec intranet-ramon-chatwoot-web-1 bundle exec rails runner '
a = Account.find(2)
c = a.contacts.create!(name: "Teste Fluxo B44", phone_number: "+5548900004444")
l = a.leads.create!(name: "Teste Fluxo B44", contact: c, lead_stage: a.lead_stages.order(:position).first, source: "teste")
l.update!(custom_attributes: l.custom_attributes.to_h.merge("advbox" => { "sincronizado_em" => Time.current.iso8601, "teste" => "B4.4: trava para nao gravar no ADVBOX" }))
puts "lead #{l.id}"'
```

**3. Conferir antes de virar.** Automações → "Lead ganho" → **Testar com um lead…** → o lead de teste. A trilha precisa dizer: "faria: dossiê…", "faria: rascunho da pesquisa NPS (comercial)…" e **"ADVBOX: caso já aberto em … (não chama de novo)"**. **Se a linha do ADVBOX disser "faria: abrir o caso", PARE** (a trava não pegou — não vire a chave do lead ganho).

**4. Virar.**
```
docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:migrados:modo[2,lead_ganho,normal]"
docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:migrados:modo[2,eventos_advbox,normal]"
```
Esperado: "Agora o FLUXO faz (o código não faz mais)" nos dois.

**5. Teste ao vivo (eventos do ADVBOX fabricados no console, para o lead de teste — nada vem do Flowter, nada vai para o ADVBOX).** Contrato fechado primeiro (ele aciona o "Lead ganho"), depois as outras 9 regras:
```
docker exec intranet-ramon-chatwoot-web-1 bundle exec rails runner '
a = Account.find(2)
["CONTRATO FECHADO", "REQUERIMENTO PROTOCOLADO", "NEGADO / AVISAR CLIENTE", "DECISAO PROFERIDA", "CARTA DE EXIGENCIAS",
 "BENEFICIO FUTURO / ANOTAR NA AGENDA", "PAGAMENTO RECEBIDO / PAGAR CLIENTE", "SENTENCA PROFERIDA",
 "BENEFICIO CONCEDIDO / IMPLANTACAO", "ARQUIVADO/ENCERRADO"].each do |etapa|
  e = AdvboxEvent.create!(account: a, event_key: "teste-b45-#{SecureRandom.hex(6)}", payload: { "stage" => etapa, "telefone" => "48900004444" })
  Ramon::AdvboxEventJob.perform_now(e.id)
  puts "#{etapa}: #{e.reload.status} #{e.note}"
end'
```
Esperado: 10 × `processed -> lead #…`. Depois, conferir na tela (em bloco):
- Execuções de "Eventos do ADVBOX": 10, **sem** selo ensaio, cada uma no ramo da sua regra; nenhuma "falhou".
- Execuções de "Lead ganho": 1, sem selo ensaio: dossiê, NPS e "ADVBOX: caso já aberto … (não chama de novo)".
- Lead de teste: etapa = ganho; atividades "ADVBOX: …" (10) + a mudança de etapa; tarefas de 45, 1, 2, 2 e 180 dias — e todas concluídas pelo "arquivado" (o último); notas: 1 dossiê, 1 NPS do ganho, os 4 rascunhos (INSS negou, exigência, êxito, concedido) **com o texto de sempre**, 1 NPS de êxito (a concessão diz "já pedida"); pushes no celular (se o ntfy estiver ligado).
- ADVBOX: buscar "Teste Fluxo B44" → **nada**.

**6. Limpar o teste.**
```
docker exec intranet-ramon-chatwoot-web-1 bundle exec rails runner '
a = Account.find(2)
l = a.leads.find_by!(name: "Teste Fluxo B44")
l.lead_activities.delete_all
l.destroy!
a.contacts.find_by(phone_number: "+5548900004444")&.destroy!
AdvboxEvent.where(account: a).where("event_key LIKE ?", "teste-b45-%").delete_all
puts "ok"'
```

**7. Rollback (a qualquer momento, sem deploy, cada um independente).**
`docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:migrados:modo[2,lead_ganho,sombra]"` (e/ou `…[2,eventos_advbox,sombra]`) → "Agora o CÓDIGO faz". Também seguro: desligar o fluxo na tela, ou tirar a env do `chatwoot.env` e recriar. Uma execução do "Lead ganho" que já esperava nova tentativa do ADVBOX termina pelo fluxo — sem dobra (o código só age em ganhos novos).

**8. Depois (outro PR, E7).** Com 2 semanas em normal sem incidente: apagar `LeadGanho.pelo_codigo` (e a chamada), os JSON `db/seeds/ramon/fluxos/sistema/lead_ganho.json` e `eventos_advbox.json` **e** as linhas `origem: sistema` deles (a sincronização não apaga linha cujo JSON sumiu), as 2 envs; `Ramon::AdvboxEventRegras` conforme a N6.

---

## Divergências registradas (spec × este plano)

| # | Onde | Divergência | Motivo |
|---|---|---|---|
| 1 | Spec §8 B4+ ("modo sombra por alguns dias; comparar trilhas") | Direto: sem sombra nem comparação; teste ao vivo logo após o deploy | E1 (Eduardo, 07/10) |
| 2 | Spec §4.3 (catálogo de ações) | Passo novo `rotina` (5 rotinas prontas do código) | o motor não sabe abrir caso no ADVBOX, a trava 1-vez da NPS, o dossiê nem concluir tarefas; reaproveitar o código mantém a garantia do ADVBOX (E5) |
| 3 | Spec §6 (Disparo enfileira o avanço) | "Eventos do ADVBOX" migrado roda na hora, dentro do job do ADVBOX | evita que 2 eventos seguidos do mesmo lead se barrem no índice único |
| 4 | Spec §6 (sombra pelo `modo`) | Os 2 fluxos agem ou ensaiam pela decisão do evento (`assumido`) | igual à B4.1: nem dobra nem buraco na virada |
| 5 | Desenho `sistema/lead_ganho.json` (passo Drive) | O Drive fica no código | N1 |
| 6 | Spec §14 ("a B4 não pode migrar os dois em dobro") | Contrato fechado só move para o ganho nos dois caminhos; quem faz dossiê/ADVBOX/NPS é sempre o "Lead ganho", pela chave dele | um caminho só decide quem age |

## Decisões do Eduardo (07/10/2026, herdadas da B4.2)

| # | Decisão | Onde no plano |
|---|---|---|
| E1 | **Direto + teste ao vivo logo após o deploy, sem sombra nem comparação** | Operação §1–§5 |
| E2 | **Chave igual à da B4.1, uma env por migração** (`RAMON_FLUXO_LEAD_GANHO`, `RAMON_FLUXO_EVENTOS_ADVBOX`) + o fluxo em modo normal; voltar = rake, sem deploy | Task 2, Operação §4 e §7 |
| E3 | **Textos internos podem mudar** | Tasks 5, 6 |
| E4 | **Mensagem ao cliente SEMPRE rascunho**, texto do código | Tasks 5, 6 |
| E5 | **Nada grava no ADVBOX sem a garantia de hoje; o teste ao vivo não cria nada no ADVBOX** | Task 1, Operação §2–§3 |
| E6 | **Depois de assumir, editáveis por admin** | — |
| E7 | **Limpeza em PR separado após 2 semanas** | Operação §8 |

## Decisões novas que dependem do Eduardo

| # | Decisão | Proposta do plano | Onde |
|---|---|---|---|
| N1 | O **Drive** (subir os documentos conferidos do lead ganho) fica no código — ele roda a cada atualização dos documentos, não só no ganho | Ficar no código | Task 3 |
| N2 | No fluxo "Lead ganho", a ordem vira **dossiê → NPS → ADVBOX por último** (hoje os 3 correm em paralelo), para o ADVBOX fora do ar não atrasar a NPS. Fora do ar: 4 tentativas em ~21 min e, se não der, **sino + push aos admins** (hoje: 3 tentativas, sem aviso) | Aceitar | Tasks 1, 3 |
| N3 | Tarefas de retorno criadas pelo ADVBOX via fluxo **vencem no fim do dia** (horário de SP) e **ficam com o Closer/SDR do lead** (hoje: vencem na hora exata e ficam sem dono) | Aceitar | Task 5 |
| N4 | Com o fluxo, cada passo que mexe no lead deixa o **balão "⚙ Fluxo …" na conversa** do cliente (interno; hoje esses avisos do ADVBOX não aparecem na conversa) e o push usa o nome do contato | Aceitar | Task 5 |
| N5 | O texto da **pesquisa NPS** e do **dossiê** continua o de hoje e **não se edita na tela** (é rotina pronta; mudar = pedir um PR). Os 4 rascunhos do ADVBOX (INSS negou, exigência, êxito, concedido) ficam editáveis na tela | Aceitar | Tasks 1, 6 |
| N6 | Evento do ADVBOX que chega com o fluxo **ocupado com o mesmo lead** (dois avisos do Flowter no mesmo instante, ou o fluxo esperando nova tentativa) é feito **pelo código** — nada se perde. Consequência: o filtro "regras" do gatilho não desliga efeito (para tirar um efeito, apaga-se o passo do ramo). Na limpeza: **manter** esse código-reserva, ou apagar e aceitar perder esse evento raro | Agora: reserva ligada. Limpeza: manter | Tasks 4, 7 |
| N7 | O teste ao vivo usa um **lead de teste com a trava do ADVBOX pré-marcada** e **eventos do ADVBOX fabricados no console** (o caminho Flowter → webhook não muda e não é exercitado). O "abrir caso no ADVBOX de verdade" só será visto no 1º ganho real depois de virar (é o mesmo serviço de hoje) | Aceitar | Operação §2–§5 |


## Respostas do Eduardo (07/10/2026)

Todas as "Decisões novas que dependem do Eduardo" deste plano foram **ACEITAS como propostas** (formulário de 07/10).

**Decisão extra do Eduardo (07/10):** o Lead ganho TAMBÉM tem reserva — se o fluxo não começar (erro do motor antes de criar a execução, ou fluxo ocupado), o código faz o ganho como hoje (dossiê, NPS, caso no ADVBOX), com a mesma regra de decisão única do evento (nunca em dobro). A Task 3 deve implementar e testar isso.
