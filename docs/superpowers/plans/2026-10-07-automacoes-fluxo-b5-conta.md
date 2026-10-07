# Automações em fluxo — B5-conta (gatilho "Horário da conta" + as 7 rotinas da conta + selo "regra fixa") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** As 7 rotinas da conta que hoje rodam no cron do código (resumo do dia, retrato do funil, fechamento do extrato, espelho do Painel, copiloto noturno, publicar peças no Instagram, avisos do Painel) viram **7 fluxos de verdade** num gatilho novo, **"Horário da conta"** (o alvo é a própria conta, não um lead), com horário/dias editáveis no quadro (ou "a cada N minutos"), liga/desliga e espaço para pôr um push antes/depois — cada um com a **chave de segurança da B4** (env + o fluxo em modo normal ⇒ o fluxo faz e o código para; qualquer peça fora ⇒ o código faz). As 5 regras de dado ficam no código e ganham o selo **"regra fixa (fica no código)"** na aba "Do sistema". Nada muda em produção até o Eduardo virar.

**Architecture:** Cada rotina vira um passo `rotina` que chama **o mesmo job de hoje, só para aquela conta** (`perform(account_id)`): a lógica de dentro e as travas não mudam. As rápidas rodam dentro do passo; as longas (espelho, copiloto, Instagram) vão para a fila. O gatilho novo (`Ramon::Fluxos::HorarioConta`, chamado a cada minuto pelo `Ramon::FluxoRelogioJob`) e o job do código **disputam a mesma "vez"** num UPDATE condicional em `ramon_fluxos.ultimo_disparo_em` (o "reivindicar o dia" da B4.3, generalizado): quem pega faz — nunca os dois, nunca nenhum. As rotinas novas entram num **registro por arquivo** (`Ramon::Fluxos::Rotinas` acha sozinho `app/services/ramon/fluxos/rotinas/*.rb`; o front acha `automacoes/rotinas/*.js`), que é o contrato dos planos irmãos B5-leads e B5-externos. Sem migração de banco.

**Tech Stack:** Rails 7.1 / RSpec (só no CI), Postgres jsonb, Sidekiq (ActiveJob) + sidekiq-cron; Vue 3.5 `<script setup>`, vue-i18n 9, Vitest 3 + @vue/test-utils, Vite `import.meta.glob`.

**Spec:** `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (§4 peças, §5 dados — índice único parcial (fluxo, alvo), §6 motor/relógio, §8 migração — **o "Resumo do dia fica no código" do §8 foi revogado pelo Eduardo em 07/10**, §13 `relogio`/`lead_parado` 1×/dia reivindicado, §14 aba "Do sistema" e selos, §16 `Migracao`, §17 B4.3 "virada no meio do dia", §18 passo `rotina` e a reserva). Plano modelo: `docs/superpowers/plans/2026-10-07-automacoes-fluxo-b44-ganho-advbox.md`. Desenhos de hoje: `db/seeds/ramon/fluxos/sistema/{resumo_do_dia,retrato_funil,fechamento_extrato,espelho_painel,copiloto_noturno,publicar_pecas,avisos_painel}.json` (a "descricao" de cada um diz o que o desenho não mostra).

---

## Decisões para o Eduardo

Cada uma muda algo que se vê (ou um risco). A recomendação está marcada; o plano está escrito com ela.

- **N1 — Desligar o fluxo na tela (ou deixá-lo "em sombra") devolve a rotina ao código, que segue rodando no horário de sempre.** É o padrão de todas as migrações até a limpeza (E7, 2 semanas depois): a rede de segurança é "qualquer peça fora ⇒ o código faz".
  - (a) **Desligar = volta para o código (recomendado)** — nunca fica sem resumo/espelho/publicação por engano.
  - (b) Desligar = a rotina para de vez já agora (mais intuitivo, mas sem rede: um clique errado e, por exemplo, o Instagram não publica).
- **N2 — Publicar peças no Instagram: com que frequência o fluxo confere a fila?** Hoje o código confere a cada minuto.
  - (a) **A cada minuto, mas só registra uma execução quando há peça vencida (ou presa) (recomendado)** — mesma pontualidade de hoje, sem 1.440 execuções vazias por dia na lista.
  - (b) A cada minuto, sempre com execução (1.440 por dia na lista do fluxo).
  - (c) A cada 5 minutos (até 5 min de atraso na publicação).
- **N3 — Espelho do Painel, copiloto noturno e publicar peças "vão para a fila":** o passo termina ao pôr a rotina na fila (a trilha diz "pôs na fila: …"); um push "depois" sai quando a rotina **começa**, não quando termina; um erro dentro dela aparece como hoje (log; a publicação já avisa no celular), não como "falhou" no fluxo.
  - (a) **Aceitar (recomendado)** — essas três podem passar de 10 min, e rodando dentro do passo o relógio acharia a execução "órfã" e repetiria o passo (espelho/Instagram em dobro).
  - (b) Rodar dentro do passo mesmo assim (o "depois" fica exato, com o risco acima).
  - As outras quatro (resumo, retrato, extrato, avisos) rodam dentro do passo: o "depois" é depois de verdade.
- **N4 — Avisos antes/depois num fluxo da conta: só push no celular.** O sino do hub precisa de um lead para existir; no "Horário da conta" o quadro só aceita Se, Escolha, Esperar, Parar, Push e Rotina pronta.
  - (a) **Aceitar (recomendado)**.
  - (b) Criar um "sino para a conta" (outro PR).
- **N5 — Teste ao vivo.** Os fluxos criados depois do horário de hoje só começam amanhã (assim nada roda 2× no dia da virada).
  - (a) **Virar logo depois do deploy; hoje mesmo rodar de novo pelo fluxo só o Resumo do dia (chega um 2º push/e-mail "seu dia" hoje) e o Retrato do funil (refaz a foto de hoje, sem efeito visível); os demais conferidos amanhã de manhã com 1 comando (recomendado).**
  - (b) Não repetir nada hoje: conferir tudo amanhã de manhã.
- **N6 — Avisos do Painel (e-mail direto ao cliente):** migra com a **mesma trava de hoje** (só envia com `PORTAL_AVISOS=on`, hoje desligado até aprovar os textos).
  - (a) **Virar junto com os outros (recomendado)** — o fluxo roda às 8h e a trilha diz "avisos do Painel desligados … — nada enviado" até você ligar `PORTAL_AVISOS`.
  - (b) Criar o fluxo, mas deixá-lo em sombra (o código segue) até aprovar os textos.

## Escolhas técnicas (decididas aqui, registradas)

- **T1 — Chaves: 1 grupo de migração por rotina (7), 3 envs por família de risco.** `RAMON_FLUXO_ROTINAS` (resumo, retrato, extrato, espelho, copiloto — internas), `RAMON_FLUXO_PUBLICAR_PECAS` (publica no Instagram), `RAMON_FLUXO_AVISOS_PAINEL` (fala com o cliente). Por quê: a env é só o freio de emergência do deploy; quem vira cada rotina é o `modo` do fluxo dela (`rake ramon:fluxos:migracao:modo[<rotina>,2,normal]`), independente das outras. 7 envs seria só mais linhas no `chatwoot.env` sem controle a mais; 1 env só misturaria "publica"/"fala com o cliente" com as internas. Grupo por rotina (e não por família) porque `Migracao.assumiu?` é tudo-ou-nada por grupo: num grupo de 5, desligar o copiloto na tela devolveria as 5 ao código.
- **T2 — O cron do código fica em `config/schedule.yml` até a limpeza (E7).** Cada job ganha `perform(account_id = nil)`: sem conta (o cron) atende as contas cujo fluxo **não** assumiu; com conta (o passo do fluxo ou a reserva) atende só aquela, sem perguntar. Mesma regra num lugar só: `Ramon::Fluxos::Rotinas::Conta.cada_conta`.
- **T3 — A "vez" (reaproveita o "reivindicar o dia" da B4.3):** UPDATE condicional em `ultimo_disparo_em`. Por dia: 1 vez no dia (SP) a partir da hora, e **fluxo que nasceu depois da hora de hoje começa amanhã** (nunca repete a vez que o código já fez antes de o fluxo existir). A cada N min: 1 vez por bloco de N minutos. O relógio e o job do código disputam a mesma vez quando o fluxo migrado existe: no comando ⇒ o fluxo faz (reserva: não começou ⇒ o código faz); fora do comando ⇒ quem pegou a vez faz pelo código. Trocar "a cada N min" ↔ "uma vez por dia" vale a partir da próxima vez (a coluna é a mesma) — teto aceito.
- **T4 — Em sombra, o fluxo da conta não ensaia sozinho** (como a cadência da B4.3): sem execuções de ensaio todo minuto/dia. Para conferir antes de virar: botão **"Testar na conta…"**.
- **T5 — Registro por arquivo (back e front)** para o rebase dos irmãos ser trivial: ninguém mexe em lista compartilhada; `Migracao::GRUPOS` junta os `GRUPOS` dos módulos do registro (nome repetido não sobe).
- **T6 — Publicar recusa** passo que precisa de lead no "Horário da conta", rotina de lead num fluxo da conta, rotina da conta num fluxo de lead e rotina desconhecida (back e front iguais).
- **T7 — Retrato do funil continua datado pelo relógio do servidor (UTC)**, como hoje: às 00:05 SP a data é a mesma; só se o horário for editado para 21:00–23:59 a foto sai com a data do dia seguinte. Teto aceito (não muda o serviço).
- **T8 — Por conta:** o expurgo de acessos do Painel (`PortalAcesso.expurgar!`, da instalação toda) fica no cron; o resumo da equipe dos avisos passa a ser 1 por conta (há 1 conta, a banca: igual a hoje).
- **T9 — Falhas:** rotina "agora" que levanta erro ⇒ o motor tenta de novo em 1/5/15 min e depois "falhou" + push aos admins (sem sino: não há lead). Resumo do dia e copiloto engolem o erro por conta, como hoje (log). Retrato, extrato e avisos são idempotentes na nova tentativa (retrato refaz a foto; extrato já fechado não refaz; aviso já marcado não sai de novo).

## Global Constraints

- **Branch/worktree:** `feat/fluxos-b5-conta` em `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-fluxos-b5-conta`, base `origin/ramon` **0a31e02** (B1–B4.5 no ar). Nunca `git push`, nunca abrir PR (gate do Eduardo / sessão principal), nunca `git stash`, nunca `git add -A`. Commitar só os caminhos da task.
- **Produção não muda até o Eduardo virar.** Com as 3 envs ausentes/`off` (padrão) e sem os fluxos criados, os 7 jobs rodam exatamente como hoje (mesmo horário, mesmas contas). Os fluxos só nascem pelo rake/runner da Operação.
- **Não apagar nada do caminho antigo (E7):** os 7 jobs e as entradas do `config/schedule.yml` ficam; os JSON `db/seeds/ramon/fluxos/sistema/*.json` e as linhas `origem: sistema` ficam.
- **Sem migração.** `ramon_fluxos.ultimo_disparo_em` e `created_at` já existem; `ramon_fluxo_execucoes.alvo_type/alvo_id` é polimórfico (aceita `Account`). Se alguma task achar que precisa de coluna/índice: pare e pergunte.
- **Rubocop do fork** (o CI barra): `Metrics/AbcSize` 26, `MethodLength` 19, `CyclomaticComplexity` 7, `PerceivedComplexity` 8, `ClassLength` 175, `ModuleLength` 100, `BlockLength` 30 (inclui `.rake`), linha 150, `Style/HashSyntax` sempre `chave: valor`, `Naming/MethodParameterName` ≥ 3 letras, `Naming/BlockForwarding` (use `&` anônimo, Ruby 3.4), `Layout/EmptyLineAfterGuardClause`, `RSpec/ContextWording` (só when/with/without — use `describe` para frases em pt-BR), `RSpec/SortMetadata`, `RSpec/SpecFilePathFormat` (`Ramon::Fluxos::Rotinas::Conta` → `spec/services/ramon/fluxos/rotinas/conta_spec.rb`), `RSpec/LeakyConstantDeclaration` (nada de `CONST =`/`class`/`module` dentro de bloco de spec — use `Module.new` + `const_set`), `Style/StringLiterals`, `Lint/RedundantDirGlobSort` (o `Pathname#glob(...).sort` já existe em `sistema.rb` e passa), `Performance/CollectionLiteralInLoop`. **`grafo.rb` está com 157 linhas de código (limite 175): só +2 linhas nele** (a validação nova mora em `horario_conta.rb`). Tamanhos na base: `disparo.rb` 98, `executor.rb` 117, `migracao.rb` 69, `passos/rotina.rb` 45, `relogio.rb` 54, `fluxo_execucao.rb` 27.
- **Sem Ruby local:** specs Ruby escritos e conferidos à mão; quem valida é o CI. `travel_to` em blocos **em sequência**, nunca aninhados; código de produção nunca usa `NOW()` do SQL. **1 execução viva por (fluxo, alvo) por exemplo** (índice único parcial `… WHERE status IN ('rodando','esperando') AND NOT ensaio`) — entre "vezes" no mesmo exemplo, marque `update_all(status: 'concluida')`; contexto de teste com `status: 'concluida'` não bate no índice. **Fluxo criado no exemplo "nasce agora" (data real do CI), depois das datas de outubro/2026 dos `travel_to`:** pela regra T3 ele só rodaria "amanhã" — use `update_column(:created_at, …)` para fazê-lo nascer antes (helper nas tasks). `.distinct.pluck` com `default_scope` ordenado quebra no Postgres (use `.pluck.uniq`). jsonb envenenado via `update!` dispara callbacks (use `update_column`). `with_modified_env` em vez de stub de `ENV`.
- **Mensagem ao cliente:** nenhum passo livre de "enviar ao cliente" entra no quadro. O único que fala com o cliente é a rotina `avisos_painel`, atrás de `PORTAL_AVISOS` (mesma trava do job). O Instagram só publica peça já agendada (o "pode postar" acontece antes, ao agendar). A API de fluxos segue admin-only.
- **Front:** i18n só dentro de `CAPTAIN_RAMON.FLUXOS` em `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json`, chaves novas **no fim** de cada objeto e na **mesma posição** nos dois arquivos (a trava `specs/i18n.spec.js` compara a ordem, cobre o catálogo e compila no vue-i18n de produção); strings sem `@`, `|`, `{`, `}` crus (só `{n}`/`{nome}` como placeholder); editar os JSON com Edit. Tailwind only, kit `ramon/helpers/ui.js`, evento custom camelCase, sem texto cru no template. Os specs de componente rodam em **en**.
- **Vitest:** `node_modules` é junção (nunca `rm -rf node_modules`); `vitest.local.config.ts` na raiz **existe e fica fora do git**:
  `TZ=UTC npx vitest run <arquivos ou pastas> --config vitest.local.config.ts`
  Baseline medido em 0a31e02: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs` = **15 arquivos, 208 testes** (chame de **B**). ESLint: `./node_modules/.bin/eslint <arquivos>` (`--fix` para o prettier; erro `Delete ␍` = CRLF do checkout Windows, ignorar; warnings `@intlify/vue-i18n/no-dynamic-keys` já existem e são aceitos).
- **Commits:** Conventional Commits em pt-BR, sem citar Claude no assunto; corpo termina com:
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR`
- **Planos irmãos (B5-leads, B5-externos) mexem nos mesmos arquivos compartilhados** (`executor.rb`, `grafo.rb`, `disparo.rb`, `fluxo.js`, `validar.js`, `PainelPasso.vue`, os dois `ramon.json`, `.env.example`, a spec). Esta fatia é a **primeira a mergear**: acrescente sempre **no fim** das listas/objetos e não reordene nada.

## Review Focus

1. **Virar/devolver a chave no meio do dia, ou criar o fluxo depois do horário** — o resumo (e cada rotina diária) sai **exatamente 1 vez** naquele dia, nem 0 nem 2. Teste: Task 5 ("fora do comando…", "virar a chave depois da hora…", "no comando mas ocupado…") e Task 2 ("fluxo que nasce depois da hora começa amanhã").
2. **Publicar peças a cada minuto com o fluxo no comando** — sem peça vencida não há execução nem a vez é gasta; com peça, o fluxo faz e o cron não; a mesma peça nunca é publicada 2× (a transição `agendado → publicando` continua sendo a trava). Teste: Task 5 ("publicar peças: sem peça vencida…") e Task 4 (`PublicarPecasJob`: "B5: …").
3. **A conta como alvo nunca é lida como conversa** — `FluxoExecucao#lead`/`Disparo#lead_do_alvo` tratavam qualquer alvo desconhecido como conversa (`leads.where(conversation_id: alvo.id)`): a conta 2 acharia o lead da conversa 2. Teste: Task 1 ("alvo = a conta: nem lead nem conversa, mesmo com uma conversa de mesmo id").
4. **Rotina/passo no gatilho errado** — rotina da conta num fluxo de lead, rotina de lead (ou passo que precisa de lead) no Horário da conta, rotina desconhecida: publicar recusa, com a mesma mensagem no back e no front. Teste: Task 2 (`grafo_spec`), Task 3 ("rotina da conta num fluxo de lead não publica"), Task 6 (`validar.spec`).
5. **Avisos do Painel pelo fluxo com `PORTAL_AVISOS` desligado** — nada é enviado e a trilha diz por quê; ligado, o mesmo job de hoje roda só para a conta. Teste: Task 3 ("avisos do Painel: com PORTAL_AVISOS desligado…").

---

## O que o código faz × o que o fluxo faz

| Rotina (`sistema_chave`) | Código hoje (cron SP) | Fluxo (B5-conta) | Modo do passo | Env |
|---|---|---|---|---|
| `resumo_do_dia` | `Ramon::DailyDigestJob` 08:00, todas as contas | Horário da conta 08:00 → `rotina resumo_do_dia` | agora | `RAMON_FLUXO_ROTINAS` |
| `retrato_funil` | `Ramon::DailyFunnelSnapshotJob` 00:05 | 00:05 → `rotina retrato_funil` | agora | idem |
| `fechamento_extrato` | `Ramon::ExtratoFechamentoJob` 00:20 (age no 3º dia útil) | 00:20 → `rotina fechamento_extrato` | agora | idem |
| `espelho_painel` | `Ramon::PortalSyncJob` 00:30 (+ expurgo de acessos) | 00:30 → `rotina espelho_painel` (expurgo fica no cron) | fila | idem |
| `copiloto_noturno` | `Ramon::NightCopilotJob` 05:00 | 05:00 → `rotina copiloto_noturno` | fila | idem |
| `publicar_pecas` | `Ramon::PublicarPecasJob` a cada minuto | a cada 1 min (só com peça vencida/presa) → `rotina publicar_pecas` | fila | `RAMON_FLUXO_PUBLICAR_PECAS` |
| `avisos_painel` | `Ramon::PortalAvisosJob` 08:00, só com `PORTAL_AVISOS=on` | 08:00 → `rotina avisos_painel` (mesma trava) | agora | `RAMON_FLUXO_AVISOS_PAINEL` |

Todos nascem sem `dias` (= todos os dias, como o cron) e sem limite do dia (limite devolve o comando ao código — padrão da `Migracao`).

## Contrato para os planos irmãos (B5-leads, B5-externos) — depende de B5-conta

**Back — registro de rotinas (`Ramon::Fluxos::Rotinas`, Task 1).** Cada plano cria **um arquivo seu** `app/services/ramon/fluxos/rotinas/<plano>.rb` com `module Ramon::Fluxos::Rotinas::<Plano>` (ex.: `rotinas/leads.rb` → `Ramon::Fluxos::Rotinas::Leads`). O registro acha o arquivo sozinho (glob da pasta, ordem alfabética) — **ninguém edita `passos/rotina.rb`, `executor.rb`, `grafo.rb` nem `migracao.rb` para registrar rotina ou migração.** O módulo define:

```ruby
module Ramon::Fluxos::Rotinas::Leads
  # obrigatório: nome (snake_case, único no hub — o registro recusa repetido, inclusive com as 5 da B4.4) → alvo
  #   'conta'    = só no gatilho "Horário da conta" (ctx.execucao.alvo é a Account; o registro confere)
  #   'lead'     = fluxos de lead/conversa; pegue o lead com Ramon::Fluxos::Passos::Lead.exigir_lead(ctx)
  #   'conversa' = idem, precisa da conversa (ctx.conversa || raise Ramon::Fluxos::PassoImpossivel, '…')
  ROTINAS = { 'criar_lead_da_conversa' => 'conversa' }.freeze

  # opcional: migrações deste plano — mesmo formato de Ramon::Fluxos::Migracao::GRUPOS; vai para lá sozinho
  # (grupo repetido não sobe). A decisão "assumiu?" segue Ramon::Fluxos::Migracao.assumiu?(account, '<grupo>').
  GRUPOS = { 'criar_lead' => { env: 'RAMON_FLUXO_CRIAR_LEAD', faz: 'a criação do lead', fluxos: { 'criar_lead_da_conversa' => 'conversa_criada' }.freeze } }.freeze

  # opcional (só faz sentido em 'conta'): o Horário da conta não começa o fluxo quando TODAS as suas rotinas dizem false.
  PENDENTE = {}.freeze

  module_function

  # obrigatório. Devolve String (o resumo da trilha) ou Hash { resumo: String, vars: { 'chave' => valor } }; saida é sempre 's'.
  # Ensaio (ctx.ensaio?) NUNCA tem efeito: devolve "faria: …". Erro passageiro: levante (o motor tenta de novo 1/5/15 min);
  # erro que não adianta repetir: raise Ramon::Fluxos::PassoImpossivel, '…' (falha na hora + push aos admins).
  def rodar(nome, ctx) = …
end
```

O registro expõe (para quem precisar): `Ramon::Fluxos::Rotinas.alvo(nome) → 'conta' | 'lead' | 'conversa' | nil`, `.rodar(nome, ctx) → { saida: 's', resumo:, vars:? }`, `.grupos → Hash`, `.pendente(nome, account) → true | false | nil`. O passo `rotina` (`Passos::Rotina.rotina`) cai no registro para todo nome que não é uma das 5 da B4.4. Publicar valida: nome conhecido; `'conta'` só no Horário da conta e o resto fora dele (`Ramon::Fluxos::HorarioConta.erros`).

**Front — catálogo (`automacoes/fluxo.js`, Task 6).** Cada plano cria `app/javascript/dashboard/routes/dashboard/captain/automacoes/rotinas/<plano>.js`:

```js
// = ROTINAS de Ramon::Fluxos::Rotinas::<Plano>
export default [{ chave: 'criar_lead_da_conversa', alvo: 'conversa' }];
```

`fluxo.js` junta sozinho (`import.meta.glob('./rotinas/*.js')`) em `ROTINAS_INFO`/`ROTINAS`/`rotinaAlvo`/`rotinasPara`; o select do passo e o `validar.js` já usam. Cada plano acrescenta, **no fim** de `CAPTAIN_RAMON.FLUXOS.ROTINAS` e `.ROTINAS_AJUDA` (en e pt_BR, mesma posição), o rótulo e a ajuda de cada rotina — a trava `i18n.spec.js` cobra. Se um irmão acrescentar rotinas de lead/conversa, o teste `fluxo.spec.js` "as 5 de lead da B4.4 + as 7 da conta" precisa da lista nova em `rotinasPara('lead')` (acréscimo no fim).

**Alvo = conta no motor (Task 1):** `FluxoExecucao#lead` e `#conversa` devolvem `nil` para alvo `Account`; o `Contexto` funciona sem lead (variáveis de lead/conversa vazias). Gatilhos de outros planos não precisam saber disso.

## Mapa de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `app/services/ramon/fluxos/rotinas.rb` (novo) | registro: acha os módulos de `rotinas/`, `alvo`, `rodar`, `grupos`, `pendente` |
| `app/services/ramon/fluxos/rotinas/conta.rb` (novo) | as 7 rotinas da conta: `JOBS`, `ROTINAS`, `GRUPOS`, `PENDENTE`, `rodar`, `cada_conta` (o cron), `decidir` (o relógio), `pelo_codigo` |
| `app/services/ramon/fluxos/horario_conta.rb` (novo) | gatilho "Horário da conta": `disparar` (a cada minuto), `na_hora?`, `reivindicar` (a vez), `tem_o_que_fazer?`, `erros` (validação) |
| `app/services/ramon/fluxos/{passos/rotina,migracao,disparo,grafo}.rb`, `app/models/fluxo_execucao.rb`, `app/jobs/ramon/fluxo_relogio_job.rb`, `app/controllers/api/v1/accounts/ramon_fluxos_controller.rb` | motor: passo `rotina` consulta o registro; `GRUPOS` junta os do registro; alvo = conta; gatilho novo; relógio; ensaio na conta |
| `app/jobs/ramon/{daily_digest,daily_funnel_snapshot,extrato_fechamento,portal_sync,night_copilot,publicar_pecas,portal_avisos}_job.rb` | `perform(account_id = nil)` via `cada_conta` |
| `db/seeds/ramon/fluxos/migrados/{resumo_do_dia,retrato_funil,fechamento_extrato,espelho_painel,copiloto_noturno,publicar_pecas,avisos_painel}.json` (novos) | os 7 desenhos |
| `db/seeds/ramon/fluxos/sistema/{historico_do_lead,docs_completos,contrato_limpo,contrato_limpo_cancelado,sdr_automatico}.json`, `resumo_do_dia.json`, `app/services/ramon/fluxos/sistema.rb` | selo "regra fixa"; tira o "fica no código" revogado |
| `.env.example` | as 3 envs |
| `app/javascript/dashboard/routes/dashboard/captain/automacoes/{fluxo.js,validar.js,rotinas/conta.js,ConfigHorarioConta.vue,ConfigGatilho.vue,PainelPasso.vue,Paleta.vue,NoPasso.vue,TestarComLead.vue,Editor.vue,Lista.vue}`, `app/javascript/dashboard/api/ramonFluxos.js`, i18n `{en,pt_BR}/ramon.json` | editor e lista |
| `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` | §19 Notas da B5-conta |

---

### Task 0: Conferir a base e medir (mecânica)

**Files:** nenhum. Sem commit.

- [ ] **Step 1: A base ainda é a de origin/ramon?**

```bash
git fetch origin
git log --oneline -1 origin/ramon
git status --short
```
Expected: `origin/ramon` em `0a31e02` (ou acima). Se andou: `git rebase origin/ramon` (a branch só tem o commit deste plano) e reconfira os tamanhos abaixo. `git status` só pode mostrar nada (o `vitest.local.config.ts` está fora do git).

- [ ] **Step 2: Baselines**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts
for f in app/services/ramon/fluxos/grafo.rb app/services/ramon/fluxos/disparo.rb app/services/ramon/fluxos/migracao.rb app/services/ramon/fluxos/passos/rotina.rb app/jobs/ramon/portal_avisos_job.rb app/jobs/ramon/publicar_pecas_job.rb; do echo "$f $(grep -cvE '^\s*(#|$)' $f)"; done
```
Expected: Vitest **15 arquivos / 208 testes** verdes (anote como **B**). `grafo.rb` ≤ 160 (se passar, avise antes da Task 2).

---

### Task 1: Registro de rotinas + alvo = conta no motor (julgamento)

**Files:**
- Create: `app/services/ramon/fluxos/rotinas.rb`
- Modify: `app/services/ramon/fluxos/passos/rotina.rb` (cai no registro)
- Modify: `app/services/ramon/fluxos/migracao.rb` (`GRUPOS` junta os do registro)
- Modify: `app/models/fluxo_execucao.rb` (`lead` com alvo conta)
- Modify: `app/services/ramon/fluxos/disparo.rb` (`lead_do_alvo` com alvo conta)
- Test: `spec/services/ramon/fluxos/rotinas_spec.rb` (novo); `spec/services/ramon/fluxos/disparo_spec.rb`

**Interfaces:**
- Produces: `Ramon::Fluxos::Rotinas.modulos → [Module]`, `.catalogo → { nome => Module }` (levanta `ArgumentError "rotina repetida: X"`), `.alvo(nome) → 'conta'|'lead'|'conversa'|nil` (as 5 da B4.4 = `'lead'`), `.rodar(nome, ctx) → { saida: 's', resumo: String, vars:? }` (levanta `Ramon::Fluxos::PassoImpossivel` para nome desconhecido ou rotina `'conta'` sem a conta de alvo), `.grupos → Hash` (levanta `ArgumentError "grupo de migração repetido: X"`), `.pendente(nome, account) → true|false|nil`. `Ramon::Fluxos::Migracao::GRUPOS` passa a incluir `Rotinas.grupos`. `FluxoExecucao#lead`/`#conversa` = `nil` com alvo `Account`; `Disparo` não procura lead com alvo `Account`.

- [ ] **Step 1: Write the failing tests**

(a) Criar `spec/services/ramon/fluxos/rotinas_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Rotinas do
  let(:account) { create(:account) }
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' })) }
  # um "plano" de mentira: módulo com o contrato (ROTINAS, PENDENTE, rodar)
  let(:plano) do
    Module.new.tap do |m|
      m.const_set(:ROTINAS, { 'da_conta' => 'conta', 'do_lead' => 'lead' }.freeze)
      m.const_set(:PENDENTE, { 'da_conta' => ->(_account) { false } }.freeze)
      m.define_singleton_method(:rodar) do |nome, ctx|
        ctx.ensaio? ? "faria: #{nome}" : { resumo: "fez: #{nome}", vars: { 'x' => '1' } }
      end
    end
  end

  before { allow(described_class).to receive(:modulos).and_return([plano]) }

  # status concluida: fora do índice único (várias por exemplo)
  def ctx(alvo, ensaio: false)
    Ramon::Fluxos::Contexto.new(fluxo.execucoes.create!(account: account, alvo: alvo, ensaio: ensaio, status: 'concluida'))
  end

  it 'acha a rotina de qualquer plano: alvo, pendente e rodar (texto ou Hash)' do
    expect([described_class.alvo('da_conta'), described_class.alvo('dossie_passagem'), described_class.alvo('xyz')])
      .to eq(['conta', 'lead', nil])
    expect([described_class.pendente('da_conta', account), described_class.pendente('do_lead', account)]).to eq([false, nil])
    expect(described_class.rodar('da_conta', ctx(account))).to eq(saida: 's', resumo: 'fez: da_conta', vars: { 'x' => '1' })
    expect(described_class.rodar('da_conta', ctx(account, ensaio: true))).to eq(saida: 's', resumo: 'faria: da_conta')
  end

  it 'rotina da conta com um lead de alvo e nome desconhecido são passo impossível' do
    lead_ctx = ctx(create(:lead, account: account))
    expect { described_class.rodar('da_conta', lead_ctx) }.to raise_error(Ramon::Fluxos::PassoImpossivel, /conta toda/)
    expect { described_class.rodar('xyz', lead_ctx) }.to raise_error(Ramon::Fluxos::PassoImpossivel, 'rotina desconhecida: xyz')
  end

  it 'o passo rotina cai no registro para o que não é da B4.4' do
    expect(Ramon::Fluxos::Passos::Rotina.rotina({ 'rotina' => 'da_conta' }, ctx(account)))
      .to eq(saida: 's', resumo: 'fez: da_conta', vars: { 'x' => '1' })
  end

  it 'nome repetido entre planos (ou com as 5 da B4.4) não sobe' do
    outro = Module.new.tap { |m| m.const_set(:ROTINAS, { 'da_conta' => 'conta' }.freeze) }
    allow(described_class).to receive(:modulos).and_return([plano, outro])
    expect { described_class.alvo('do_lead') }.to raise_error(ArgumentError, 'rotina repetida: da_conta')
    b44 = Module.new.tap { |m| m.const_set(:ROTINAS, { 'pesquisa_nps' => 'lead' }.freeze) }
    allow(described_class).to receive(:modulos).and_return([b44])
    expect { described_class.alvo('x') }.to raise_error(ArgumentError, 'rotina repetida: pesquisa_nps')
  end

  it 'junta os grupos de migração dos planos; grupo repetido não sobe' do
    grupo = { env: 'RAMON_FLUXO_X', faz: 'x', fluxos: { 'x' => 'horario_conta' } }
    com_grupo = lambda do |nome|
      Module.new.tap do |m|
        m.const_set(:ROTINAS, {}.freeze)
        m.const_set(:GRUPOS, { nome => grupo }.freeze)
      end
    end
    allow(described_class).to receive(:modulos).and_return([plano, com_grupo.call('x')])
    expect(described_class.grupos).to eq('x' => grupo)
    allow(described_class).to receive(:modulos).and_return([com_grupo.call('x'), com_grupo.call('x')])
    expect { described_class.grupos }.to raise_error(ArgumentError, 'grupo de migração repetido: x')
  end
end
```
(b) Em `spec/services/ramon/fluxos/disparo_spec.rb`, acrescentar no fim do `describe` principal:

```ruby
  it 'alvo = a conta (B5): nem lead nem conversa, mesmo com uma conversa de mesmo id' do
    account = create(:account)
    conversa = create(:conversation, account: account, id: account.id)
    create(:lead, account: account, conversation_id: conversa.id)
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' }, ['parar', {}]))
    execucao = described_class.new(fluxo, account, {}, nil).iniciar
    expect([execucao.alvo, execucao.lead, execucao.conversa]).to eq([account, nil, nil])
    expect(execucao.contexto).not_to have_key('etapa_inicial_id')
  end
```
(Se o `disparo_spec.rb` já tem `let(:account)`, use-o e tire a 1ª linha.)

- [ ] **Step 2: Conferir à mão que falham** — `Ramon::Fluxos::Rotinas` não existe; `execucao.lead` acharia o lead pela conversa de mesmo id.

- [ ] **Step 3: Implementar**

Criar `app/services/ramon/fluxos/rotinas.rb`:

```ruby
# B5 (decisão do Eduardo 07/10): registro das rotinas prontas do hub (passo `rotina`). Cada plano põe as suas num
# arquivo próprio, app/services/ramon/fluxos/rotinas/<plano>.rb (Ramon::Fluxos::Rotinas::<Plano>), achado aqui sozinho:
# plano novo não mexe em lista compartilhada. Contrato de cada módulo (plano B5-conta, "Contrato para os planos irmãos"):
# - ROTINAS = { 'nome' => 'conta' | 'lead' | 'conversa' } — o alvo; 'conta' só no gatilho Horário da conta;
# - rodar(nome, ctx) → String (o resumo da trilha) ou Hash { resumo:, vars: }; no ensaio só descreve ("faria: …");
# - opcional GRUPOS (formato de Migracao::GRUPOS — vai para lá) e PENDENTE = { 'nome' => ->(account) { Boolean } }.
# As 5 rotinas da B4.4 (Passos::Rotina::ROTINAS) seguem lá, de lead.
module Ramon::Fluxos::Rotinas
  PASTA = Rails.root.join('app/services/ramon/fluxos/rotinas')

  module_function

  def modulos
    @modulos ||= PASTA.glob('*.rb').sort.map { |arquivo| "Ramon::Fluxos::Rotinas::#{arquivo.basename('.rb').to_s.camelize}".constantize }
  end

  # nome → módulo. ponytail: refeito a cada chamada (poucos módulos, poucas rotinas); memoizar se aparecer em perfil.
  def catalogo
    modulos.each_with_object({}) do |modulo, lista|
      modulo::ROTINAS.each_key do |nome|
        raise ArgumentError, "rotina repetida: #{nome}" if lista.key?(nome) || Ramon::Fluxos::Passos::Rotina::ROTINAS.include?(nome)

        lista[nome] = modulo
      end
    end
  end

  def alvo(nome)
    return 'lead' if Ramon::Fluxos::Passos::Rotina::ROTINAS.include?(nome)

    catalogo[nome]&.then { |modulo| modulo::ROTINAS[nome] }
  end

  def grupos
    modulos.select { |modulo| modulo.const_defined?(:GRUPOS, false) }.map { |modulo| modulo::GRUPOS }
           .reduce({}) { |todos, grupo| todos.merge(grupo) { |chave| raise ArgumentError, "grupo de migração repetido: #{chave}" } }
  end

  # nil = a rotina não diz (conta como "tem o que fazer").
  def pendente(nome, account)
    modulo = catalogo[nome]
    return unless modulo&.const_defined?(:PENDENTE, false) && modulo::PENDENTE.key?(nome)

    modulo::PENDENTE[nome].call(account)
  end

  def rodar(nome, ctx)
    modulo = catalogo[nome] || raise(Ramon::Fluxos::PassoImpossivel, "rotina desconhecida: #{nome}")
    if modulo::ROTINAS[nome] == 'conta' && !ctx.execucao.alvo.is_a?(Account)
      raise Ramon::Fluxos::PassoImpossivel, 'esta rotina é da conta toda (gatilho Horário da conta)'
    end

    resultado = modulo.rodar(nome, ctx)
    { saida: 's' }.merge(resultado.is_a?(Hash) ? resultado : { resumo: resultado })
  end
end
```

Em `app/services/ramon/fluxos/passos/rotina.rb`, no topo de `rotina` trocar:

```ruby
    nome = config['rotina'].to_s
    raise Ramon::Fluxos::PassoImpossivel, "rotina desconhecida: #{nome}" unless ROTINAS.include?(nome)
```
por
```ruby
    nome = config['rotina'].to_s
    return Ramon::Fluxos::Rotinas.rodar(nome, ctx) unless ROTINAS.include?(nome) # B5: as rotinas dos planos (e o "desconhecida")
```
e acrescentar ao comentário do topo do arquivo a linha `# B5: os demais nomes vêm do registro Ramon::Fluxos::Rotinas (um arquivo por plano em rotinas/).`

Em `app/services/ramon/fluxos/migracao.rb`, trocar o fechamento de `GRUPOS`:

```ruby
      preparar: ->(account, desenho) { Ramon::Fluxos::Migracao.com_etapa(desenho, account.lead_stages.find_by!(is_won: true).id) }
    }
  }.freeze
```
por
```ruby
      preparar: ->(account, desenho) { Ramon::Fluxos::Migracao.com_etapa(desenho, account.lead_stages.find_by!(is_won: true).id) }
    }
    # B5: as migrações dos planos B5 vêm do registro de rotinas (o GRUPOS de cada Ramon::Fluxos::Rotinas::<Plano>).
  }.merge(Ramon::Fluxos::Rotinas.grupos) { |chave| raise ArgumentError, "Migração repetida: #{chave}" }.freeze
```

Em `app/models/fluxo_execucao.rb`, `lead`: trocar `return if alvo.nil?` por

```ruby
    return if alvo.nil? || alvo.is_a?(Account) # B5: o Horário da conta não tem lead
```

Em `app/services/ramon/fluxos/disparo.rb`, `lead_do_alvo`: acrescentar o ramo antes do `else`:

```ruby
    when Account then nil # B5: o Horário da conta não tem lead (e o id da conta não é de conversa)
```

- [ ] **Step 4: Conferir à mão** os 6 exemplos (traçar `catalogo` com o `plano` de mentira; `rodar('xyz')` levanta antes da checagem de alvo; o `Passos::Rotina` existente "rotina desconhecida falha na hora" continua passando — a mensagem é a mesma, `rotina desconhecida: apagar_tudo`). `rubocop` mental: `rotinas.rb` < 60 linhas; linha mais longa < 150.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/rotinas.rb app/services/ramon/fluxos/passos/rotina.rb app/services/ramon/fluxos/migracao.rb app/models/fluxo_execucao.rb app/services/ramon/fluxos/disparo.rb spec/services/ramon/fluxos/rotinas_spec.rb spec/services/ramon/fluxos/disparo_spec.rb
git commit -m "feat(fluxos): registro de rotinas por plano e a conta como alvo (B5-conta)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 2: Gatilho "Horário da conta" — disparo, a vez, validação, relógio e ensaio na conta (julgamento)

**Files:**
- Create: `app/services/ramon/fluxos/horario_conta.rb`
- Modify: `app/services/ramon/fluxos/grafo.rb` (`GATILHOS` + 1 linha em `erros`)
- Modify: `app/jobs/ramon/fluxo_relogio_job.rb`
- Modify: `app/controllers/api/v1/accounts/ramon_fluxos_controller.rb` (`alvo`)
- Test: `spec/services/ramon/fluxos/horario_conta_spec.rb` (novo); `spec/services/ramon/fluxos/grafo_spec.rb`; `spec/jobs/ramon/fluxo_relogio_job_spec.rb`; `spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Fluxos::Rotinas.alvo/pendente` (Task 1).
- Produces: `Ramon::Fluxos::HorarioConta::GATILHO = 'horario_conta'`, `::PASSOS = %w[se escolha esperar parar avisar_push rotina]`, `::QUANDO` (mensagem); `.disparar(agora = SP.now)`, `.disparar_fluxo(fluxo, agora)`, `.config(fluxo) → Hash`, `.na_hora?(config, agora) → Boolean`, `.reivindicar(fluxo, agora) → Boolean` (a vez; usada também pelo job do código na Task 3), `.tem_o_que_fazer?(fluxo) → Boolean`, `.erros(grafo) → [String]`. Ensaio na conta: `POST …/ramon_fluxos/:id/ensaio {conta: true, usar}`.

- [ ] **Step 1: Write the failing tests**

(a) Criar `spec/services/ramon/fluxos/horario_conta_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::HorarioConta do
  let(:account) { create(:account) }
  let(:push) { ['avisar_push', { 'texto' => 'oi' }] }

  def sp(texto) = Time.find_zone!('America/Sao_Paulo').parse(texto)

  # Fluxo que nasceu antes das datas do teste: o que nasce depois da hora de hoje só começa amanhã (T3).
  def fluxo_conta(gatilho, *passos)
    grafo = grafo_linear({ 'tipo' => 'horario_conta' }.merge(gatilho), *(passos.presence || [push]))
    fluxo_publicado(account, grafo).tap { |f| f.update_column(:created_at, sp('2026-10-01 00:00')) } # rubocop:disable Rails/SkipsModelValidations
  end

  def rodar(texto) = travel_to(sp(texto)) { described_class.disparar }

  def concluir(fluxo) = fluxo.execucoes.update_all(status: 'concluida') # rubocop:disable Rails/SkipsModelValidations

  it 'uma vez por dia a partir da hora, com a conta de alvo, e de novo no dia seguinte' do
    fluxo = fluxo_conta({ 'hora' => '08:00' })
    rodar('2026-10-06 07:59')
    expect(fluxo.execucoes.count).to eq(0)
    rodar('2026-10-06 08:00')
    rodar('2026-10-06 15:00')
    expect(fluxo.execucoes.pluck(:alvo_type, :alvo_id, :ensaio)).to eq([['Account', account.id, false]])
    concluir(fluxo)
    rodar('2026-10-07 08:01')
    expect(fluxo.execucoes.count).to eq(2)
  end

  it 'só nos dias marcados (0 = domingo)' do
    fluxo = fluxo_conta({ 'hora' => '08:00', 'dias' => [1, 2, 3, 4, 5] })
    rodar('2026-10-04 09:00') # domingo
    expect(fluxo.execucoes.count).to eq(0)
    rodar('2026-10-05 09:00') # segunda
    expect(fluxo.execucoes.count).to eq(1)
  end

  it 'a cada N minutos: 1 vez por bloco de N minutos' do
    fluxo = fluxo_conta({ 'a_cada_minutos' => 5 })
    %w[10:00:10 10:02:00 10:04:59 10:05:01 10:09:30].each do |hora|
      rodar("2026-10-06 #{hora}")
      concluir(fluxo)
    end
    expect(fluxo.execucoes.count).to eq(2)
  end

  it 'fluxo que nasce depois da hora começa amanhã (nunca repete a vez que o código já fez)' do
    grafo = grafo_linear({ 'tipo' => 'horario_conta', 'hora' => '08:00' }, push)
    fluxo = travel_to(sp('2026-10-06 10:00')) { fluxo_publicado(account, grafo) }
    rodar('2026-10-06 10:01')
    expect(fluxo.execucoes.count).to eq(0)
    rodar('2026-10-07 08:00')
    expect(fluxo.execucoes.count).to eq(1)
  end

  it 'roda sem lead: o push sai e a execução conclui' do
    fluxo = fluxo_conta({ 'hora' => '08:00' })
    rodar('2026-10-06 08:00')
    execucao = fluxo.execucoes.sole
    expect { Ramon::Fluxos::Executor.new(execucao).avancar! }.to have_enqueued_job(Ramon::NtfyPushJob)
    expect(execucao.reload.status).to eq('concluida')
    expect([execucao.lead, execucao.conversa]).to eq([nil, nil])
  end

  it 'erro num fluxo não derruba os outros' do
    quebrado = fluxo_conta({ 'hora' => '08:00' })
    bom = fluxo_conta({ 'hora' => '08:00' })
    allow(Ramon::Fluxos::Disparo).to receive(:new).and_call_original
    allow(Ramon::Fluxos::Disparo).to receive(:new).with(quebrado, account, {}, nil).and_raise(ActiveRecord::RecordInvalid)
    rodar('2026-10-06 08:00')
    expect([quebrado.execucoes.count, bom.execucoes.count]).to eq([0, 1])
  end
end
```

(b) Em `spec/services/ramon/fluxos/grafo_spec.rb`, acrescentar no fim:

```ruby
  describe 'Horário da conta (B5)' do
    def conta(gatilho, *passos) = grafo(grafo_linear({ 'tipo' => 'horario_conta' }.merge(gatilho), *passos)).erros

    it 'precisa de hora ou de a cada N minutos (1 a 1440) e de pelo menos um dia' do
      parar = ['parar', {}]
      expect([conta({ 'hora' => '08:00' }, parar), conta({ 'a_cada_minutos' => 1 }, parar)]).to eq([[], []])
      [{}, { 'a_cada_minutos' => 0 }, { 'a_cada_minutos' => 1441 }, { 'hora' => '08:00', 'dias' => [] },
       { 'hora' => '08:00', 'dias' => [7] }].each do |gatilho|
        expect(conta(gatilho, parar)).to eq([Ramon::Fluxos::HorarioConta::QUANDO])
      end
    end

    it 'só entram os passos que rodam sem lead; rotina de lead ou desconhecida não publica' do
      expect(conta({ 'hora' => '08:00' }, ['mover_etapa', { 'etapa_id' => 1 }]))
        .to eq(['Passo p1: precisa de um lead — no Horário da conta só entram Se, Escolha, Esperar, Parar, Push e Rotina pronta'])
      expect(conta({ 'hora' => '08:00' }, ['rotina', { 'rotina' => 'dossie_passagem' }]))
        .to eq(['Passo p1: esta rotina é de um lead — não roda no Horário da conta'])
      expect(grafo(grafo_linear({ 'tipo' => 'manual' }, ['rotina', { 'rotina' => 'xyz' }])).erros)
        .to eq(['Passo p1: rotina desconhecida (xyz)'])
    end
  end
```
(O `grafo_spec.rb` já tem um helper `grafo(d)` — ver linha 54/128. Se o nome for outro, use o dele.)

(c) Em `spec/jobs/ramon/fluxo_relogio_job_spec.rb`, acrescentar:

```ruby
  it 'dispara o Horário da conta (B5)' do
    allow(Ramon::Fluxos::HorarioConta).to receive(:disparar)
    described_class.perform_now
    expect(Ramon::Fluxos::HorarioConta).to have_received(:disparar)
  end
```

(d) Em `spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb`, acrescentar:

```ruby
  it 'ensaio do Horário da conta roda na conta toda (B5)' do
    grafo_conta = grafo_linear({ 'tipo' => 'horario_conta', 'hora' => '08:00' }, ['avisar_push', { 'texto' => 'oi' }])
    fluxo = fluxo_publicado(account, grafo_conta)
    post "#{url}/#{fluxo.id}/ensaio", params: { conta: true, usar: 'publicada' }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('status' => 'concluida', 'ensaio' => true, 'alvo_type' => 'Account', 'alvo_id' => account.id)
    expect(response.parsed_body['trilha'].last['resumo']).to eq('faria: push "oi"')
  end
```

- [ ] **Step 2: Conferir à mão que falham** — gatilho desconhecido no publicar; `HorarioConta` não existe; `alvo` do controller cairia em `find_by!(display_id: nil)` (404).

- [ ] **Step 3: Implementar**

Criar `app/services/ramon/fluxos/horario_conta.rb`:

```ruby
# B5-conta (spec §8, decisão do Eduardo 07/10): gatilho "Horário da conta" — o alvo é a própria conta, não um lead.
# Config: 'hora' (HH:MM — uma vez por dia a partir dela) OU 'a_cada_minutos' (1–1440); 'dias' (0 = domingo … 6 = sábado;
# sem a chave = todos). Fuso de São Paulo. Chamado a cada minuto pelo Ramon::FluxoRelogioJob.
# A vez é reivindicada ANTES de rodar, num UPDATE condicional em ultimo_disparo_em (o "reivindicar o dia" da B4.3):
# - por dia: 1 vez no dia; fluxo que nasceu depois da hora de hoje começa amanhã (nunca repete a vez que o código já fez);
# - a cada N min: 1 vez por bloco de N minutos.
# O job do código (Ramon::Fluxos::Rotinas::Conta.cada_conta) disputa a MESMA vez do fluxo migrado: quem pega faz.
module Ramon::Fluxos::HorarioConta
  GATILHO = 'horario_conta'.freeze
  PASSOS = %w[se escolha esperar parar avisar_push rotina].freeze # os que rodam sem lead
  DIAS = (0..6).to_a.freeze
  INTERVALO = (1..1440)
  QUANDO = 'O Horário da conta precisa de uma hora (HH:MM) ou de "a cada N minutos" (1 a 1440), e de pelo menos um dia'.freeze

  module_function

  def disparar(agora = Time.find_zone!(Fluxo::ZONA).now)
    Fluxo.executaveis.where(gatilho_tipo: GATILHO).includes(:versao_publicada).find_each do |fluxo|
      disparar_fluxo(fluxo, agora)
    rescue StandardError => e
      ChatwootExceptionTracker.new(e, account: fluxo.account).capture_exception
      Rails.logger.warn("[Ramon::Fluxos::HorarioConta] fluxo #{fluxo.id}: #{e.class}")
    end
  end

  def disparar_fluxo(fluxo, agora)
    return unless na_hora?(config(fluxo), agora) && tem_o_que_fazer?(fluxo) && reivindicar(fluxo, agora)
    return if fluxo.modo == 'normal' && fluxo.limite_atingido?

    Ramon::Fluxos::Disparo.new(fluxo, fluxo.account, {}, nil).iniciar
  end

  def config(fluxo) = Ramon::Fluxos::Grafo.new(fluxo.versao_publicada&.grafo).gatilho&.dig('config') || {}

  def na_hora?(config, agora)
    return false unless dias(config).include?(agora.wday)

    intervalo(config).present? || agora >= hora_de_hoje(config, agora)
  end

  def reivindicar(fluxo, agora)
    config = config(fluxo)
    n = intervalo(config)
    vez = Fluxo.where(id: fluxo.id)
    vez = if n
            vez.where('ultimo_disparo_em IS NULL OR ultimo_disparo_em < ?', agora.beginning_of_minute - (n - 1).minutes)
          else
            vez.where(created_at: ...hora_de_hoje(config, agora))
               .where('ultimo_disparo_em IS NULL OR ultimo_disparo_em < ?', agora.beginning_of_day)
          end
    vez.update_all(ultimo_disparo_em: agora) == 1 # rubocop:disable Rails/SkipsModelValidations
  end

  # Rotinas que dizem "nada a fazer" (Rotinas.pendente == false) em TODOS os passos rotina: o fluxo nem começa (nem gasta a vez).
  def tem_o_que_fazer?(fluxo)
    nomes = Ramon::Fluxos::Grafo.new(fluxo.versao_publicada.grafo).nos.select { |n| n['tipo'] == 'rotina' }.map { |n| n.dig('config', 'rotina') }
    nomes.empty? || nomes.any? { |nome| Ramon::Fluxos::Rotinas.pendente(nome, fluxo.account) != false }
  end

  def dias(config) = config.key?('dias') ? Array(config['dias']).map(&:to_i) : DIAS

  def intervalo(config) = config['a_cada_minutos'].presence&.to_i

  def hora_de_hoje(config, agora)
    hora, minuto = (config['hora'].presence || '00:00').split(':').map(&:to_i)
    agora.change(hour: hora, min: minuto)
  end

  # Publicar (Grafo#erros): o "quando" do Horário da conta, os passos que rodam sem lead e a rotina do alvo certo.
  def erros(grafo)
    gatilho = grafo.gatilho || {}
    conta = gatilho.dig('config', 'tipo') == GATILHO
    erros = conta && !quando_valido?(gatilho['config']) ? [QUANDO] : []
    erros + grafo.nos.flat_map { |no| erros_no(no, conta) }
  end

  def quando_valido?(config)
    n = config['a_cada_minutos']
    ok = n.present? ? n.to_s.match?(/\A\d+\z/) && INTERVALO.cover?(n.to_i) : config['hora'].present?
    ok && (!config.key?('dias') || (dias(config).any? && (dias(config) - DIAS).empty?))
  end

  def erros_no(no, conta)
    return [] if no['tipo'] == 'gatilho'
    if conta && PASSOS.exclude?(no['tipo'])
      return ["Passo #{no['id']}: precisa de um lead — no Horário da conta só entram Se, Escolha, Esperar, Parar, Push e Rotina pronta"]
    end

    nome = no.dig('config', 'rotina')
    no['tipo'] == 'rotina' && nome.present? ? erros_rotina(no['id'], nome, conta) : []
  end

  def erros_rotina(id, nome, conta)
    alvo = Ramon::Fluxos::Rotinas.alvo(nome)
    return ["Passo #{id}: rotina desconhecida (#{nome})"] if alvo.nil?
    return [] if (alvo == 'conta') == conta

    [conta ? "Passo #{id}: esta rotina é de um lead — não roda no Horário da conta" : "Passo #{id}: esta rotina é da conta toda — só roda no gatilho Horário da conta"]
  end
end
```
(Se a última linha passar de 150 colunas, quebre o ternário em `if/else`. Se `erros_no` passar de Cyclomatic 7, extraia o `if conta && …` para `passo_sem_lead?(no, conta)`.)

Em `app/services/ramon/fluxos/grafo.rb`:
- `GATILHOS`: acrescentar `horario_conta` **no fim** da lista `%w[…]` (depois de `documento_recebido`).
- `erros`: trocar `e + erros_setas + erros_alcance + nos.flat_map { |n| erros_passo(n) }` por
  ```ruby
      e + erros_setas + erros_alcance + nos.flat_map { |n| erros_passo(n) } + Ramon::Fluxos::HorarioConta.erros(self) # B5
  ```

Em `app/jobs/ramon/fluxo_relogio_job.rb`, depois de `Ramon::Fluxos::Relogio.disparar_do_dia`:

```ruby
    Ramon::Fluxos::HorarioConta.disparar # B5-conta: o gatilho "Horário da conta" (rotinas da conta)
```
e acrescentar ao comentário do topo `# e o Horário da conta (Ramon::Fluxos::HorarioConta).`.

No controller, `alvo`:

```ruby
  def alvo
    return Current.account if params[:conta].present? # B5: o ensaio do Horário da conta roda na conta toda
    return Current.account.leads.find(params[:lead_id]) if params[:lead_id].present?
```

- [ ] **Step 4: Conferir à mão** — traçar o exemplo "a cada N minutos" (a conta dos blocos está no comentário da Task: 10:00:10 pega; 10:02 e 10:04:59 não — `desde` 09:58 e 10:00; 10:05:01 pega — `desde` 10:01; 10:09:30 não — `desde` 10:05) e o "nasce depois da hora" (`created_at` 10:00 ≮ 08:00 de hoje; amanhã 10:00 de ontem < 08:00 ✓). `grafo.rb` +1 linha líquida.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/horario_conta.rb app/services/ramon/fluxos/grafo.rb app/jobs/ramon/fluxo_relogio_job.rb app/controllers/api/v1/accounts/ramon_fluxos_controller.rb spec/services/ramon/fluxos/horario_conta_spec.rb spec/services/ramon/fluxos/grafo_spec.rb spec/jobs/ramon/fluxo_relogio_job_spec.rb spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb
git commit -m "feat(fluxos): gatilho Horário da conta (B5-conta) — por dia ou a cada N min, alvo = a conta" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 3: As 7 rotinas da conta (registro, chaves, desenhos) (julgamento)

**Files:**
- Create: `app/services/ramon/fluxos/rotinas/conta.rb`
- Create: `db/seeds/ramon/fluxos/migrados/{resumo_do_dia,retrato_funil,fechamento_extrato,espelho_painel,copiloto_noturno,publicar_pecas,avisos_painel}.json`
- Modify: `.env.example`
- Test: `spec/services/ramon/fluxos/rotinas/conta_spec.rb` (novo)

**Interfaces:**
- Consumes: `Rotinas` (Task 1), `HorarioConta.reivindicar` (Task 2), `Migracao.semear/assumiu?/fluxo/mudar_modo!`.
- Produces: `Ramon::Fluxos::Rotinas::Conta::JOBS = { nome => [job_class_name, :agora|:fila, env, faz] }` (7), `::ROTINAS` (7 → `'conta'`), `::GRUPOS` (7, gatilho `horario_conta`), `::PENDENTE` (`publicar_pecas`); `.rodar(nome, ctx) → String`; `.migrado?(fluxo) → Boolean`; `.pelo_codigo(account, nome)` (enfileira o job da conta); `.cada_conta(nome, account_id = nil, &)` (o cron); `.decidir(fluxo)` (o relógio — Task 5 liga). **Os jobs só ganham `perform(account_id)` na Task 4** — até lá os specs desta task não rodam o job de verdade (stub).

- [ ] **Step 1: Write the failing tests** — criar `spec/services/ramon/fluxos/rotinas/conta_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Rotinas::Conta do
  let(:account) { create(:account) }
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'horario_conta', 'hora' => '08:00' })) }
  let(:todas) { described_class::JOBS.keys }

  def sp(texto) = Time.find_zone!('America/Sao_Paulo').parse(texto)

  # status concluida: fora do índice único (várias por exemplo)
  def ctx(ensaio: false)
    Ramon::Fluxos::Contexto.new(fluxo.execucoes.create!(account: account, alvo: account, ensaio: ensaio, status: 'concluida'))
  end

  it 'as 7 rotinas da conta: no registro, cada uma com a sua migração (3 chaves por família)' do
    expect(todas.map { |nome| Ramon::Fluxos::Rotinas.alvo(nome) }.uniq).to eq(['conta'])
    envs = Ramon::Fluxos::Migracao::GRUPOS.slice(*todas).transform_values { |g| g[:env] }
    expect(envs).to eq('resumo_do_dia' => 'RAMON_FLUXO_ROTINAS', 'retrato_funil' => 'RAMON_FLUXO_ROTINAS',
                       'fechamento_extrato' => 'RAMON_FLUXO_ROTINAS', 'espelho_painel' => 'RAMON_FLUXO_ROTINAS',
                       'copiloto_noturno' => 'RAMON_FLUXO_ROTINAS', 'publicar_pecas' => 'RAMON_FLUXO_PUBLICAR_PECAS',
                       'avisos_painel' => 'RAMON_FLUXO_AVISOS_PAINEL')
    expect(Ramon::Fluxos::Migracao.gatilhos('publicar_pecas')).to eq('publicar_pecas' => 'horario_conta')
  end

  it 'criar: os 7 nascem em sombra, ligados, publicados, no horário de hoje do código' do
    horarios = todas.to_h do |nome|
      novo = Ramon::Fluxos::Migracao.semear(account, nome).sole
      [nome, Ramon::Fluxos::Grafo.new(novo.versao_publicada.grafo).gatilho['config'].slice('hora', 'a_cada_minutos')]
    end
    expect(horarios).to eq('resumo_do_dia' => { 'hora' => '08:00' }, 'retrato_funil' => { 'hora' => '00:05' },
                           'fechamento_extrato' => { 'hora' => '00:20' }, 'espelho_painel' => { 'hora' => '00:30' },
                           'copiloto_noturno' => { 'hora' => '05:00' }, 'publicar_pecas' => { 'a_cada_minutos' => 1 },
                           'avisos_painel' => { 'hora' => '08:00' })
    expect(account.fluxos.where(sistema_chave: todas, origem: 'usuario').pluck(:modo, :ativo, :gatilho_tipo, :limite_dia).uniq)
      .to eq([['sombra', true, 'horario_conta', nil]])
  end

  it 'rodar: "agora" roda o job de hoje só para esta conta; o ensaio só descreve' do
    allow(Ramon::DailyDigestJob).to receive(:perform_now)
    expect(described_class.rodar('resumo_do_dia', ctx(ensaio: true))).to eq('faria: o resumo do dia')
    expect(Ramon::DailyDigestJob).not_to have_received(:perform_now)
    expect(described_class.rodar('resumo_do_dia', ctx)).to eq('fez: o resumo do dia')
    expect(Ramon::DailyDigestJob).to have_received(:perform_now).with(account.id)
  end

  it 'rodar: "fila" enfileira o job da conta (passaria de 10 min dentro do passo)' do
    expect(described_class.rodar('espelho_painel', ctx(ensaio: true))).to eq('faria: o espelho do Painel do Cliente (na fila)')
    expect { expect(described_class.rodar('publicar_pecas', ctx)).to eq('pôs na fila: a publicação das peças no Instagram') }
      .to have_enqueued_job(Ramon::PublicarPecasJob).with(account.id)
  end

  it 'avisos do Painel: com PORTAL_AVISOS desligado nada é chamado e a trilha diz por quê' do
    allow(Ramon::PortalAvisosJob).to receive(:perform_now)
    expect(described_class.rodar('avisos_painel', ctx)).to eq('avisos do Painel desligados até aprovar os textos (PORTAL_AVISOS) — nada enviado')
    expect(Ramon::PortalAvisosJob).not_to have_received(:perform_now)
    with_modified_env(PORTAL_AVISOS: 'on') { expect(described_class.rodar('avisos_painel', ctx)).to eq('fez: os avisos do Painel do Cliente') }
    expect(Ramon::PortalAvisosJob).to have_received(:perform_now).with(account.id)
  end

  it 'rotina da conta num fluxo de lead não publica' do
    grafo = Ramon::Fluxos::Grafo.new(grafo_linear({ 'tipo' => 'manual' }, ['rotina', { 'rotina' => 'resumo_do_dia' }]))
    expect(grafo.erros).to eq(['Passo p1: esta rotina é da conta toda — só roda no gatilho Horário da conta'])
  end

  describe 'cada_conta (o job do código)' do
    # let! na ordem: account nasce antes (find_each vai por id)
    let!(:account) { create(:account) }
    let!(:outra) { create(:account) }

    def contas(account_id = nil) = [].tap { |lista| described_class.cada_conta('resumo_do_dia', account_id) { |a| lista << a.id } }

    it 'sem o fluxo: todas as contas, como sempre; com o id: só aquela' do
      expect(contas).to eq([account.id, outra.id])
      expect(contas(outra.id)).to eq([outra.id])
    end

    it 'fluxo no comando: a conta fica de fora' do
      Ramon::Fluxos::Migracao.semear(account, 'resumo_do_dia')
      with_modified_env(RAMON_FLUXO_ROTINAS: 'on') do
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'resumo_do_dia', 'normal')
        expect(contas).to eq([outra.id])
      end
    end

    it 'fluxo criado mas fora do comando: o código faz se pegar a vez — 1 vez no dia' do
      novo = Ramon::Fluxos::Migracao.semear(account, 'resumo_do_dia').sole
      novo.update_column(:created_at, sp('2026-10-01 00:00')) # rubocop:disable Rails/SkipsModelValidations
      travel_to(sp('2026-10-06 08:00')) { expect(contas).to eq([account.id, outra.id]) }
      travel_to(sp('2026-10-06 08:00:40')) { expect(contas).to eq([outra.id]) } # a vez de hoje já foi
    end
  end
end
```

- [ ] **Step 2: Conferir à mão que falham** — `Ramon::Fluxos::Rotinas::Conta` não existe.

- [ ] **Step 3: Implementar**

Criar `app/services/ramon/fluxos/rotinas/conta.rb`:

```ruby
# B5-conta (spec §8, decisão do Eduardo 07/10): as 7 rotinas da conta como "Rotina pronta do hub" no gatilho Horário da
# conta. Cada uma chama o MESMO job de hoje, só para esta conta (perform(account_id)): a lógica e as travas não mudam
# (avisos do Painel só com PORTAL_AVISOS=on; o Instagram só publica peça já agendada com "pode postar").
# :agora roda dentro do passo (o "depois" do fluxo é depois de verdade); :fila vai para a fila — espelho, copiloto e
# Instagram podem passar de 10 min, e o relógio acharia a execução órfã e repetiria o passo.
# A chave de cada uma é a da migração genérica (Migracao junta os GRUPOS daqui): env do grupo =on E o fluxo (origem
# usuario, sistema_chave = o nome da rotina) ligado, publicado, em modo normal e no Horário da conta.
module Ramon::Fluxos::Rotinas::Conta
  # nome → [job de hoje, :agora | :fila, env da chave (T1: por família de risco), o que faz]
  JOBS = {
    'resumo_do_dia' => ['Ramon::DailyDigestJob', :agora, 'RAMON_FLUXO_ROTINAS', 'o resumo do dia'],
    'retrato_funil' => ['Ramon::DailyFunnelSnapshotJob', :agora, 'RAMON_FLUXO_ROTINAS', 'o retrato do funil'],
    'fechamento_extrato' => ['Ramon::ExtratoFechamentoJob', :agora, 'RAMON_FLUXO_ROTINAS', 'o fechamento do extrato'],
    'espelho_painel' => ['Ramon::PortalSyncJob', :fila, 'RAMON_FLUXO_ROTINAS', 'o espelho do Painel do Cliente'],
    'copiloto_noturno' => ['Ramon::NightCopilotJob', :fila, 'RAMON_FLUXO_ROTINAS', 'o copiloto noturno'],
    'publicar_pecas' => ['Ramon::PublicarPecasJob', :fila, 'RAMON_FLUXO_PUBLICAR_PECAS', 'a publicação das peças no Instagram'],
    'avisos_painel' => ['Ramon::PortalAvisosJob', :agora, 'RAMON_FLUXO_AVISOS_PAINEL', 'os avisos do Painel do Cliente']
  }.freeze
  ROTINAS = JOBS.transform_values { 'conta' }.freeze
  GRUPOS = JOBS.to_h { |nome, (_job, _modo, env, faz)| [nome, { env: env, faz: faz, fluxos: { nome => 'horario_conta' }.freeze }] }.freeze
  # N2: o fluxo "Publicar peças" (a cada minuto) só começa com peça vencida ou presa — sem 1.440 execuções vazias por dia.
  PENDENTE = { 'publicar_pecas' => ->(account) { Ramon::PublicarPecasJob.pendente?(account) } }.freeze
  AVISOS_DESLIGADOS = 'avisos do Painel desligados até aprovar os textos (PORTAL_AVISOS) — nada enviado'.freeze

  module_function

  def rodar(nome, ctx)
    job, modo, _env, faz = JOBS.fetch(nome)
    return AVISOS_DESLIGADOS if nome == 'avisos_painel' && ENV.fetch('PORTAL_AVISOS', nil) != 'on'
    return "faria: #{faz}#{' (na fila)' if modo == :fila}" if ctx.ensaio?

    job.constantize.public_send(modo == :fila ? :perform_later : :perform_now, ctx.execucao.alvo_id)
    modo == :fila ? "pôs na fila: #{faz}" : "fez: #{faz}"
  end

  def migrado?(fluxo) = fluxo.origem == 'usuario' && JOBS.key?(fluxo.sistema_chave)

  # O caminho de hoje para uma conta (a reserva do relógio).
  def pelo_codigo(account, nome) = JOBS.fetch(nome).first.constantize.perform_later(account.id)

  # O job do código, conta a conta. Com account_id (o passo do fluxo ou a reserva): só aquela, sem perguntar. No cron:
  # pula a conta cujo fluxo está no comando; com o fluxo criado e fora do comando, faz só se pegar a vez dele
  # (HorarioConta.reivindicar — o relógio pode ter feito pelo código primeiro). Sem o fluxo: como sempre.
  def cada_conta(nome, account_id = nil, &)
    return Account.where(id: account_id).find_each(&) if account_id

    agora = Time.find_zone!(Fluxo::ZONA).now
    Account.find_each { |account| yield account if do_codigo?(account, nome, agora) }
  end

  def do_codigo?(account, nome, agora)
    return false if Ramon::Fluxos::Migracao.assumiu?(account, nome)

    fluxo = Ramon::Fluxos::Migracao.fluxo(account, nome)
    fluxo.nil? || Ramon::Fluxos::HorarioConta.reivindicar(fluxo, agora)
  end

  # O relógio pegou a vez do fluxo migrado. No comando → o fluxo faz; não começou (ocupado — a execução de antes ainda
  # viva —, erro do motor) → o código faz (reserva). Fora do comando → o código faz nesta vez (o cron não a pega mais).
  def decidir(fluxo)
    nome = fluxo.sistema_chave
    feita = Ramon::Fluxos::Migracao.assumiu?(fluxo.account, nome) && iniciar(fluxo)
    pelo_codigo(fluxo.account, nome) unless feita
  end

  def iniciar(fluxo)
    Ramon::Fluxos::Disparo.new(fluxo, fluxo.account, { 'assumido' => true }, nil).iniciar
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: fluxo.account).capture_exception
    nil
  end
end
```
(`PENDENTE` chama `Ramon::PublicarPecasJob.pendente?`, que nasce na Task 4 — esta task não chama `PENDENTE`.)

Criar os 7 JSON em `db/seeds/ramon/fluxos/migrados/` (UTF-8, mesma forma do `lead_ganho.json`). Rodapé comum da descrição: ` Se este fluxo não começar (ocupado ou erro), o código faz aquela vez. Enquanto o selo disser "em sombra", quem faz é o código, no horário de sempre.` (escrito por extenso em cada arquivo).

`resumo_do_dia.json`:
```json
{
  "nome": "Resumo do dia",
  "descricao": "Todo dia às 08:00, no lugar do código (B5): o resumo do dia de sempre — push \"seu dia\" para a equipe (só se o dia tem algo e com o ntfy ligado) e o e-mail de gestão com os números de ontem (só com SMTP). Horário e dias editáveis no gatilho; dá para pôr um push antes ou depois. Se este fluxo não começar (ocupado ou erro), o código faz aquela vez. Enquanto o selo disser \"em sombra\", quem faz é o código, no horário de sempre.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"horario_conta","hora":"08:00"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"rotina","config":{"rotulo":"Resumo do dia (push e e-mail de gestão)","rotina":"resumo_do_dia"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [{"de":"n1","saida":"s","para":"n2"}]
  }
}
```
Os outros 6, mesma forma, mudando `nome`, a 1ª frase da `descricao`, o gatilho e o passo:

| arquivo | nome | 1ª frase da descricao (+ o rodapé comum) | gatilho `config` | `rotulo` do passo |
|---|---|---|---|---|
| `retrato_funil.json` | Retrato do funil | `Todo dia às 00:05, no lugar do código (B5): guarda a foto do funil do dia (etapas, teses e valores) para os relatórios — o mesmo serviço de hoje.` | `{"tipo":"horario_conta","hora":"00:05"}` | `Retrato do funil (para os relatórios)` |
| `fechamento_extrato.json` | Fechamento do extrato | `Todo dia às 00:20, no lugar do código (B5): no 3º dia útil fecha o extrato da variável do mês anterior (regulamento §6); nos outros dias não faz nada.` | `{"tipo":"horario_conta","hora":"00:20"}` | `Fechamento do extrato da variável` |
| `espelho_painel.json` | Espelho do Painel do Cliente | `Toda noite às 00:30, no lugar do código (B5): copia do ADVBOX processos, andamentos e pedidos de documento de todos os clientes do Painel. Vai para a fila (demora): o passo seguinte não espera terminar.` | `{"tipo":"horario_conta","hora":"00:30"}` | `Espelho do Painel do Cliente (ADVBOX)` |
| `copiloto_noturno.json` | Copiloto noturno | `Toda madrugada às 05:00, no lugar do código (B5): prepara sugestões para até 15 leads parados, que a equipe aprova de manhã no Cockpit — nada vai ao cliente. Vai para a fila.` | `{"tipo":"horario_conta","hora":"05:00"}` | `Copiloto noturno (sugestões no Cockpit)` |
| `publicar_pecas.json` | Publicar peças no Instagram | `A cada minuto, no lugar do código (B5): publica no Instagram só as peças já agendadas (com o \"pode postar\") cuja hora chegou — sem peça vencida, o fluxo nem começa. Falhou: aviso no celular, sem nova tentativa, como hoje. Vai para a fila.` | `{"tipo":"horario_conta","a_cada_minutos":1}` | `Publicar no Instagram as peças agendadas` |
| `avisos_painel.json` | Avisos do Painel do Cliente | `Todo dia às 08:00, no lugar do código (B5): e-mail DIRETO ao cliente com as novidades do espelho da noite (etapas delicadas nunca) e o resumo da equipe com o WhatsApp pronto. Segue DESLIGADO até o Eduardo aprovar os textos (PORTAL_AVISOS=on): até lá o passo só registra \"nada enviado\".` | `{"tipo":"horario_conta","hora":"08:00"}` | `Avisos do Painel do Cliente (e-mail ao cliente)` |

Em todos: `"rotina"` do passo `n2` = o nome do arquivo.

Em `.env.example`, no fim do bloco `RAMON_FLUXO_*` (depois de `RAMON_FLUXO_EVENTOS_ADVBOX`):

```
# ramon: rotinas da conta pelos fluxos (B5). on + o fluxo da rotina em modo normal = o fluxo faz (gatilho Horario da conta)
# e o cron do codigo pula a conta. Internas: resumo do dia, retrato do funil, fechamento do extrato, espelho do Painel e
# copiloto noturno. Padrao desligado. Virar/voltar cada uma: rake ramon:fluxos:migracao:modo[<rotina>,conta,normal|sombra]
# RAMON_FLUXO_ROTINAS=off

# ramon: publicar pecas no Instagram pelo fluxo (B5). Mesma regra; so publica peca ja agendada. Grupo: publicar_pecas
# RAMON_FLUXO_PUBLICAR_PECAS=off

# ramon: avisos do Painel do Cliente pelo fluxo (B5). Mesma regra; continua so enviando com PORTAL_AVISOS=on. Grupo: avisos_painel
# RAMON_FLUXO_AVISOS_PAINEL=off
```

- [ ] **Step 4: Conferir à mão** — `Migracao.semear` → `criar` lê `migrados/<nome>.json`, publica (o `Grafo#erros` passa: hora válida; passo `rotina` com nome do registro, alvo conta no Horário da conta). `cada_conta` "1 vez no dia": a 1ª chamada reivindica (`created_at` 01/10 < 08:00 de 06/10; `ultimo_disparo_em` nulo) e devolve as duas; a 2ª, no mesmo dia, não reivindica a conta → só `outra`. `ModuleLength` < 100.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/rotinas/conta.rb db/seeds/ramon/fluxos/migrados/resumo_do_dia.json db/seeds/ramon/fluxos/migrados/retrato_funil.json db/seeds/ramon/fluxos/migrados/fechamento_extrato.json db/seeds/ramon/fluxos/migrados/espelho_painel.json db/seeds/ramon/fluxos/migrados/copiloto_noturno.json db/seeds/ramon/fluxos/migrados/publicar_pecas.json db/seeds/ramon/fluxos/migrados/avisos_painel.json .env.example spec/services/ramon/fluxos/rotinas/conta_spec.rb
git commit -m "feat(fluxos): as 7 rotinas da conta como rotina pronta, com chave por rotina (B5-conta)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 4: Os 7 jobs atendem uma conta (`perform(account_id = nil)`) (mecânica)

**Files:**
- Modify: `app/jobs/ramon/{daily_digest_job,daily_funnel_snapshot_job,extrato_fechamento_job,portal_sync_job,night_copilot_job,publicar_pecas_job,portal_avisos_job}.rb`
- Test: os 6 specs existentes em `spec/jobs/ramon/` + `spec/jobs/ramon/portal_sync_job_spec.rb` (novo)

**Interfaces:**
- Consumes: `Ramon::Fluxos::Rotinas::Conta.cada_conta(nome, account_id, &)` (Task 3).
- Produces: cada job `perform(account_id = nil)` (sidekiq-cron chama sem argumento = como hoje); `Ramon::PublicarPecasJob.pendente?(account)`, `.vencidas(account)`, `.presas(account)`.

- [ ] **Step 1: Write the failing tests** — 1 exemplo novo em cada spec (stub de `assumiu?`: a regra de verdade já está provada na Task 3):

`spec/jobs/ramon/daily_digest_job_spec.rb` (dentro de `describe '#perform'`):
```ruby
    it 'B5: com o fluxo "Resumo do dia" no comando a conta fica de fora do cron; com o id, só ela' do
      create_overdue_task
      allow(Ramon::Fluxos::Migracao).to receive(:assumiu?).and_call_original
      allow(Ramon::Fluxos::Migracao).to receive(:assumiu?).with(account, 'resumo_do_dia').and_return(true)
      with_modified_env NTFY_TOPIC: 'ramon-leads' do
        expect { described_class.perform_now }.not_to have_enqueued_job(Ramon::NtfyPushJob)
        expect { described_class.perform_now(account.id) }.to have_enqueued_job(Ramon::NtfyPushJob).exactly(:once)
      end
    end
```

`spec/jobs/ramon/daily_funnel_snapshot_job_spec.rb`:
```ruby
  it 'B5: conta com o fluxo no comando fica de fora do cron; com o id, só ela' do
    account = create(:account)
    outra = create(:account)
    [account, outra].each { |a| create(:lead, account: a, lead_stage: a.lead_stages.find_by(name: 'Novo')) }
    allow(Ramon::Fluxos::Migracao).to receive(:assumiu?).and_call_original
    allow(Ramon::Fluxos::Migracao).to receive(:assumiu?).with(account, 'retrato_funil').and_return(true)
    described_class.perform_now
    expect([FunnelSnapshot.where(account: account).count, FunnelSnapshot.where(account: outra).count]).to eq([0, 1])
    described_class.perform_now(account.id)
    expect(FunnelSnapshot.where(account: account).count).to eq(1)
  end
```

`spec/jobs/ramon/extrato_fechamento_job_spec.rb`:
```ruby
  it 'B5: conta com o fluxo no comando fica de fora do cron; com o id, só ela' do
    allow(Ramon::Fluxos::Migracao).to receive(:assumiu?).and_call_original
    allow(Ramon::Fluxos::Migracao).to receive(:assumiu?).with(account, 'fechamento_extrato').and_return(true)
    travel_to(Time.zone.parse('2026-12-03 15:00:00 UTC')) { described_class.perform_now }
    expect(ExtratoFechado.count).to eq(0)
    travel_to(Time.zone.parse('2026-12-03 15:01:00 UTC')) { described_class.perform_now(account.id) }
    expect(ExtratoFechado.where(account: account).pluck(:user_id)).to eq([sdr.id])
  end
```

`spec/jobs/ramon/night_copilot_job_spec.rb`:
```ruby
  it 'B5: conta com o fluxo no comando fica de fora do cron; com o id, só ela' do
    service = instance_double(Ramon::NightCopilotService, perform: 0)
    allow(Ramon::NightCopilotService).to receive(:new).and_return(service)
    allow(Ramon::Fluxos::Migracao).to receive(:assumiu?).and_call_original
    allow(Ramon::Fluxos::Migracao).to receive(:assumiu?).with(account, 'copiloto_noturno').and_return(true)
    described_class.perform_now
    expect(Ramon::NightCopilotService).not_to have_received(:new).with(account: account)
    expect(Ramon::NightCopilotService).to have_received(:new).with(account: other_account)
    described_class.perform_now(account.id)
    expect(Ramon::NightCopilotService).to have_received(:new).with(account: account)
  end
```

`spec/jobs/ramon/publicar_pecas_job_spec.rb`:
```ruby
  it 'B5: pendente? só com peça vencida ou presa; fluxo no comando tira a conta do cron; com o id, só ela' do
    peca
    expect(described_class.pendente?(peca.account)).to be(true)
    allow(Ramon::Fluxos::Migracao).to receive(:assumiu?).and_call_original
    allow(Ramon::Fluxos::Migracao).to receive(:assumiu?).with(peca.account, 'publicar_pecas').and_return(true)
    described_class.perform_now
    expect(publisher).not_to have_received(:publicar)
    described_class.perform_now(peca.account_id)
    expect(peca.reload.status).to eq('publicado')
    expect(described_class.pendente?(peca.account)).to be(false)
  end
```

`spec/jobs/ramon/portal_avisos_job_spec.rb`:
```ruby
  it 'B5: conta com o fluxo no comando fica de fora do cron; com o id, só ela (mesma trava PORTAL_AVISOS)' do
    allow(Ramon::Fluxos::Migracao).to receive(:assumiu?).and_call_original
    allow(Ramon::Fluxos::Migracao).to receive(:assumiu?).with(cliente.account, 'avisos_painel').and_return(true)
    with_modified_env PORTAL_AVISOS: 'on' do
      described_class.perform_now
      expect(Ramon::PortalMailer).not_to have_received(:with)
      described_class.perform_now(cliente.account_id)
    end
    expect(Ramon::PortalMailer).to have_received(:with).with(cliente: cliente, itens: kind_of(Array))
  end
```

Criar `spec/jobs/ramon/portal_sync_job_spec.rb`:
```ruby
require 'rails_helper'

RSpec.describe Ramon::PortalSyncJob do
  let!(:cliente) { create(:portal_cliente, convidado_em: 1.day.ago) }
  let(:servico) { instance_double(Ramon::PortalSyncService, perform: true) }

  before { allow(Ramon::PortalSyncService).to receive(:new).and_return(servico) }

  it 'espelha os clientes convidados; ADVBOX fora do ar num cliente não derruba os outros' do
    outro = create(:portal_cliente, account: cliente.account, convidado_em: 1.day.ago)
    create(:portal_cliente, account: cliente.account, convidado_em: nil)
    allow(servico).to receive(:perform).and_raise(Ramon::AdvboxClient::UnavailableError, 'fora')
    expect { described_class.perform_now }.not_to raise_error
    expect(Ramon::PortalSyncService).to have_received(:new).twice
    expect(Ramon::PortalSyncService).to have_received(:new).with(outro)
  end

  it 'B5: conta com o fluxo no comando fica de fora do cron; com o id, só ela' do
    allow(Ramon::Fluxos::Migracao).to receive(:assumiu?).and_call_original
    allow(Ramon::Fluxos::Migracao).to receive(:assumiu?).with(cliente.account, 'espelho_painel').and_return(true)
    described_class.perform_now
    expect(Ramon::PortalSyncService).not_to have_received(:new)
    described_class.perform_now(cliente.account_id)
    expect(Ramon::PortalSyncService).to have_received(:new).with(cliente)
  end
end
```
(Se `Ramon::AdvboxClient::UnavailableError.new` exigir outros argumentos, copie a forma de levantar de `spec/services/ramon/fluxos/passos/rotina_spec.rb`.)

- [ ] **Step 2: Conferir à mão que falham** — `perform` hoje não aceita argumento (`ArgumentError`) e não pula conta.

- [ ] **Step 3: Implementar** (corpo de cada `perform`; o resto do arquivo fica):

`daily_digest_job.rb`:
```ruby
  # B5-conta: sem conta = o cron (as contas cujo fluxo "Resumo do dia" não assumiu); com conta = o fluxo ou a reserva
  # pediram aquela conta (Ramon::Fluxos::Rotinas::Conta.cada_conta).
  def perform(account_id = nil)
    Ramon::Fluxos::Rotinas::Conta.cada_conta('resumo_do_dia', account_id) do |account|
      deliver(account)
    rescue StandardError => e
      # uma conta com dado venenoso não pode abortar as demais nem virar retry-loop
      Rails.logger.error("DailyDigestJob: conta #{account.id} falhou (#{e.class}: #{e.message})")
    end
  end
```

`daily_funnel_snapshot_job.rb`:
```ruby
  # B5-conta: sem conta = o cron (as contas cujo fluxo "Retrato do funil" não assumiu); com conta = o fluxo ou a reserva.
  def perform(account_id = nil)
    Ramon::Fluxos::Rotinas::Conta.cada_conta('retrato_funil', account_id) do |account|
      Ramon::FunnelSnapshotService.new(account: account).perform
    end
  end
```

`extrato_fechamento_job.rb`:
```ruby
  # B5-conta: sem conta = o cron (as contas cujo fluxo "Fechamento do extrato" não assumiu); com conta = o fluxo ou a reserva.
  def perform(account_id = nil)
    mes = Ramon::ExtratoFechamento.hoje.prev_month.beginning_of_month
    return unless Ramon::ExtratoFechamento.fechado?(mes)

    Ramon::Fluxos::Rotinas::Conta.cada_conta('fechamento_extrato', account_id) do |account|
      Ramon::ExtratoFechamento.fechar!(account, mes)
    end
  end
```

`portal_sync_job.rb`:
```ruby
  # B5-conta: sem conta = o cron (as contas cujo fluxo "Espelho do Painel" não assumiu, + o expurgo de acessos, que é da
  # instalação toda); com conta = o fluxo ou a reserva pediram aquela conta.
  def perform(account_id = nil)
    PortalAcesso.expurgar! if account_id.nil?
    Ramon::Fluxos::Rotinas::Conta.cada_conta('espelho_painel', account_id) { |account| espelhar(account) }
  end

  private

  def espelhar(account)
    PortalCliente.where(account: account).where.not(convidado_em: nil).find_each do |cliente|
      Ramon::PortalSyncService.new(cliente).perform
    rescue Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError => e
      Rails.logger.warn("[Ramon::PortalSyncJob] cliente=#{cliente.id} #{e.class}: #{e.message}")
    end
  end
```

`night_copilot_job.rb`:
```ruby
  # B5-conta: sem conta = o cron (as contas cujo fluxo "Copiloto noturno" não assumiu); com conta = o fluxo ou a reserva.
  def perform(account_id = nil)
    Ramon::Fluxos::Rotinas::Conta.cada_conta('copiloto_noturno', account_id) do |account|
      Ramon::NightCopilotService.new(account: account).perform
    rescue StandardError => e
      # uma conta com dado venenoso não pode abortar as demais nem virar retry-loop
      Rails.logger.error("NightCopilotJob: conta #{account.id} falhou (#{e.class}: #{e.message})")
    end
  end
```

`publicar_pecas_job.rb` — trocar `perform` e apagar `marcar_interrompidas` (as presas passam a ser por conta, na mesma ordem: antes das vencidas):
```ruby
  # B5-conta: o Horário da conta só começa o fluxo "Publicar peças" quando há o que fazer (Rotinas::Conta::PENDENTE).
  def self.pendente?(account) = vencidas(account).exists? || presas(account).exists?

  def self.vencidas(account) = Peca.where(account: account, status: 'agendado').where(agendado_para: ..Time.current)

  def self.presas(account) = Peca.where(account: account, status: 'publicando').where(publicacao_iniciada_em: ...INTERROMPIDA.ago)

  # B5-conta: sem conta = o cron (as contas cujo fluxo "Publicar peças" não assumiu); com conta = o fluxo ou a reserva.
  def perform(account_id = nil)
    Ramon::Fluxos::Rotinas::Conta.cada_conta('publicar_pecas', account_id) do |account|
      self.class.presas(account).find_each { |peca| interromper(peca) }
      self.class.vencidas(account).find_each { |peca| publicar(peca) }
    end
  end
```

`portal_avisos_job.rb` — trocar `perform` (a trava `PORTAL_AVISOS` continua a 1ª linha):
```ruby
  def perform(account_id = nil)
    return unless ENV['PORTAL_AVISOS'] == 'on'

    # B5-conta: sem conta = o cron (as contas cujo fluxo "Avisos do Painel" não assumiu); com conta = o fluxo ou a reserva.
    Ramon::Fluxos::Rotinas::Conta.cada_conta('avisos_painel', account_id) { |account| avisar_conta(account) }
  end

  private

  # 1 resumo da equipe por conta (antes, 1 da instalação toda — há uma conta só, a banca: igual).
  def avisar_conta(account)
    linhas = []
    # Suspenso não recebe aviso (nem entra no resumo): o acesso dele está parado.
    clientes = PortalCliente.where(account: account).where.not(convidado_em: nil).where(suspenso_em: nil)
    clientes.find_each { |cliente| linhas.concat(avisar(cliente)) }
    return if linhas.empty?

    # ponytail: se o resumo falhar, as novidades já ficaram avisadas — o selo "Novo" segue no painel.
    Ramon::PortalMailer.with(linhas: linhas, para: ENV.fetch('PORTAL_AVISO_EQUIPE_EMAIL', EQUIPE_PADRAO)).resumo_equipe.deliver_now
  end
```
(O `private` que já existia abaixo de `perform` some — `avisar_conta` entra logo depois dele, antes de `avisar`.)

- [ ] **Step 4: Conferir à mão** — os specs existentes de cada job chamam `perform_now` sem argumento: `cada_conta` sem conta e sem fluxo criado = todas as contas, como hoje (o `PublicarPecasJob` agora filtra por conta, mas a peça do spec é da conta da factory). `publicar_pecas_job.rb` não passa de 175; `portal_avisos_job.rb` idem.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/ramon/daily_digest_job.rb app/jobs/ramon/daily_funnel_snapshot_job.rb app/jobs/ramon/extrato_fechamento_job.rb app/jobs/ramon/portal_sync_job.rb app/jobs/ramon/night_copilot_job.rb app/jobs/ramon/publicar_pecas_job.rb app/jobs/ramon/portal_avisos_job.rb spec/jobs/ramon/daily_digest_job_spec.rb spec/jobs/ramon/daily_funnel_snapshot_job_spec.rb spec/jobs/ramon/extrato_fechamento_job_spec.rb spec/jobs/ramon/portal_sync_job_spec.rb spec/jobs/ramon/night_copilot_job_spec.rb spec/jobs/ramon/publicar_pecas_job_spec.rb spec/jobs/ramon/portal_avisos_job_spec.rb
git commit -m "feat(fluxos): os 7 jobs da conta atendem uma conta e pulam a conta do fluxo no comando (B5-conta)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 5: O relógio decide pelos fluxos migrados (quem pega a vez faz, com reserva) (julgamento)

**Files:**
- Modify: `app/services/ramon/fluxos/horario_conta.rb` (`disparar_fluxo`: 1 linha)
- Test: `spec/services/ramon/fluxos/horario_conta_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Fluxos::Rotinas::Conta.migrado?/decidir` (Task 3), os jobs com `perform(account_id)` (Task 4).

- [ ] **Step 1: Write the failing tests** — acrescentar a `horario_conta_spec.rb`:

```ruby
  describe 'rotina da conta migrada: quem pega a vez faz, nunca os dois' do
    let(:resumo) do
      Ramon::Fluxos::Migracao.semear(account, 'resumo_do_dia').sole
                             .tap { |f| f.update_column(:created_at, sp('2026-10-01 00:00')) } # rubocop:disable Rails/SkipsModelValidations
    end

    def cron(texto) = [].tap { |l| travel_to(sp(texto)) { Ramon::Fluxos::Rotinas::Conta.cada_conta('resumo_do_dia') { |a| l << a.id } } }

    it 'no comando: o fluxo faz (de verdade, com assumido), chamando o mesmo job só para a conta; o cron pula' do
      resumo
      allow(Ramon::DailyDigestJob).to receive(:perform_now)
      with_modified_env(RAMON_FLUXO_ROTINAS: 'on') do
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'resumo_do_dia', 'normal')
        expect { rodar('2026-10-06 08:00') }.not_to have_enqueued_job(Ramon::DailyDigestJob)
        expect(cron('2026-10-06 08:00:30')).to eq([])
      end
      execucao = resumo.execucoes.sole
      expect([execucao.ensaio, execucao.contexto.dig('gatilho', 'assumido')]).to eq([false, true])
      Ramon::Fluxos::Executor.new(execucao).avancar!
      expect(Ramon::DailyDigestJob).to have_received(:perform_now).with(account.id)
      expect(execucao.reload.trilha.last['resumo']).to eq('fez: o resumo do dia')
    end

    it 'fora do comando (sombra): nenhuma execução; o relógio faz pelo código e o cron do mesmo dia não repete' do
      resumo
      expect { rodar('2026-10-06 08:00') }.to have_enqueued_job(Ramon::DailyDigestJob).with(account.id)
      expect(resumo.execucoes.count).to eq(0)
      expect(cron('2026-10-06 08:00:40')).to eq([])
    end

    it 'virar a chave depois da hora não roda a vez de novo (o cron já pegou)' do
      resumo
      expect(cron('2026-10-06 08:00')).to eq([account.id])
      with_modified_env(RAMON_FLUXO_ROTINAS: 'on') do
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'resumo_do_dia', 'normal')
        expect { rodar('2026-10-06 10:00') }.not_to have_enqueued_job(Ramon::DailyDigestJob)
      end
      expect(resumo.execucoes.count).to eq(0)
    end

    it 'no comando mas ocupado (a execução de ontem ainda viva): o código faz a vez de hoje (reserva)' do
      resumo.execucoes.create!(account: account, alvo: account, status: 'esperando', retomar_em: 1.hour.from_now)
      with_modified_env(RAMON_FLUXO_ROTINAS: 'on') do
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'resumo_do_dia', 'normal')
        expect { rodar('2026-10-06 08:00') }.to have_enqueued_job(Ramon::DailyDigestJob).with(account.id)
      end
      expect(resumo.execucoes.count).to eq(1)
    end

    it 'erro do motor ao criar a execução: o código faz (reserva)' do
      resumo
      allow(Ramon::Fluxos::Disparo).to receive(:new).and_raise(StandardError, 'motor')
      with_modified_env(RAMON_FLUXO_ROTINAS: 'on') do
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'resumo_do_dia', 'normal')
        expect { rodar('2026-10-06 08:00') }.to have_enqueued_job(Ramon::DailyDigestJob).with(account.id)
      end
    end

    it 'publicar peças: sem peça vencida o fluxo nem começa (nem gasta a vez); com peça, o fluxo faz' do
      publicar = Ramon::Fluxos::Migracao.semear(account, 'publicar_pecas').sole
      with_modified_env(RAMON_FLUXO_PUBLICAR_PECAS: 'on') do
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'publicar_pecas', 'normal')
        rodar('2026-10-06 12:00')
        expect([publicar.execucoes.count, publicar.reload.ultimo_disparo_em]).to eq([0, nil])
        create(:peca, account: account, status: 'agendado', agendado_para: sp('2026-10-06 11:59'), imagens: ['u1'])
        rodar('2026-10-06 12:01')
      end
      expect(publicar.execucoes.sole.ensaio).to be(false)
    end
  end
```

- [ ] **Step 2: Conferir à mão que falham** — sem a linha nova, o fluxo migrado no comando dispararia sem `assumido` (ensaio) e fora do comando rodaria como fluxo comum (execução de ensaio, sem chamar o código).

- [ ] **Step 3: Implementar** — em `HorarioConta.disparar_fluxo`, logo depois do `return unless … reivindicar(fluxo, agora)`:

```ruby
    return Ramon::Fluxos::Rotinas::Conta.decidir(fluxo) if Ramon::Fluxos::Rotinas::Conta.migrado?(fluxo) # B5: a vez é da rotina
```
e acrescentar ao comentário do topo: `# Fluxo migrado de uma rotina do código (Rotinas::Conta): no comando o fluxo faz; não começou ou fora do comando, o código faz.`

- [ ] **Step 4: Conferir à mão** — "fora do comando": relógio pega a vez (`created_at` 01/10, `ultimo` nulo) → `decidir` → `assumiu?` falso → `pelo_codigo` → `perform_later(account.id)`; `cron` às 08:00:40 → `do_codigo?` → `reivindicar` falha (a vez já é de hoje) → lista vazia. "Ocupado": `iniciar` → `RecordNotUnique` → `nil` → reserva. "Publicar": às 12:00 `tem_o_que_fazer?` = `pendente?` falso → não reivindica; às 12:01 com a peça → `decidir` → execução não-ensaio.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/horario_conta.rb spec/services/ramon/fluxos/horario_conta_spec.rb
git commit -m "feat(fluxos): relógio decide as rotinas migradas — quem pega a vez faz, reserva pelo código (B5-conta)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 6: Editor — catálogo, validação e textos (mecânica)

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/captain/automacoes/rotinas/conta.js`
- Modify: `…/automacoes/fluxo.js`, `…/automacoes/validar.js`, `app/javascript/dashboard/api/ramonFluxos.js` (comentário), `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json`
- Test: `…/automacoes/specs/{fluxo.spec.js,validar.spec.js,migrados.spec.js,i18n.spec.js}`

**Interfaces:**
- Produces (fluxo.js): `GATILHOS` com `{ tipo: 'horario_conta', icone: 'i-lucide-building-2', alvo: 'conta' }` no fim; `ROTINAS_INFO = [{ chave, alvo }]`; `ROTINAS` (as 5 + as dos planos); `rotinaAlvo(chave) → 'conta'|'lead'|'conversa'|undefined`; `rotinasPara(alvo) → [chave]`; `PASSOS_CONTA`. validar.js: códigos `CONTA_QUANDO`, `CONTA_PASSO`, `ROTINA_DESCONHECIDA` (`params.nome`), `ROTINA_DE_LEAD`, `ROTINA_DA_CONTA`.

- [ ] **Step 1: Write the failing tests**

`specs/fluxo.spec.js` — acrescentar (e somar `GATILHOS, PASSOS_CONTA, ROTINAS, rotinaAlvo, rotinasPara` ao import de `'../fluxo'`):
```js
describe('rotinas prontas (registro por plano, B5)', () => {
  it('as 5 de lead da B4.4 + as 7 da conta (rotinas/conta.js)', () => {
    expect(rotinasPara('lead')).toEqual([
      'dossie_passagem',
      'pesquisa_nps',
      'pesquisa_nps_exito',
      'abrir_caso_advbox',
      'concluir_tarefas',
    ]);
    expect(rotinasPara('conta')).toEqual([
      'resumo_do_dia',
      'retrato_funil',
      'fechamento_extrato',
      'espelho_painel',
      'copiloto_noturno',
      'publicar_pecas',
      'avisos_painel',
    ]);
    expect(new Set(ROTINAS).size).toBe(ROTINAS.length);
    expect(rotinaAlvo('xyz')).toBeUndefined();
  });

  it('o Horário da conta tem a conta de alvo e só os passos sem lead', () => {
    expect(GATILHOS.find(g => g.tipo === 'horario_conta').alvo).toBe('conta');
    expect(PASSOS_CONTA).toEqual(['se', 'escolha', 'esperar', 'parar', 'avisar_push', 'rotina']);
  });
});
```

`specs/validar.spec.js` — acrescentar dentro do `describe` principal:
```js
  describe('Horário da conta (espelho de Ramon::Fluxos::HorarioConta.erros)', () => {
    const conta = (config, ...passos) => ({
      nos: [g({ tipo: 'horario_conta', ...config }), ...passos],
      setas: passos.map((passo, i) => ({
        de: i ? passos[i - 1].id : 'g',
        saida: 's',
        para: passo.id,
      })),
    });

    it('hora ou a cada N minutos (1 a 1440) e pelo menos um dia', () => {
      expect(validar(conta({ hora: '08:00' }, p('p1', 'parar')))).toEqual([]);
      expect(validar(conta({ a_cada_minutos: 1 }, p('p1', 'parar')))).toEqual([]);
      [
        {},
        { a_cada_minutos: 0 },
        { a_cada_minutos: 1441 },
        { hora: '08:00', dias: [] },
        { hora: '08:00', dias: [7] },
      ].forEach(c =>
        expect(codigos(conta(c, p('p1', 'parar')))).toEqual([['g', 'CONTA_QUANDO']])
      );
    });

    it('só passos sem lead; rotina do alvo certo; desconhecida aponta o nome', () => {
      expect(codigos(conta({ hora: '08:00' }, p('p1', 'mover_etapa', { etapa_id: 1 })))).toEqual([['p1', 'CONTA_PASSO']]);
      expect(codigos(conta({ hora: '08:00' }, p('p1', 'rotina', { rotina: 'dossie_passagem' })))).toEqual([['p1', 'ROTINA_DE_LEAD']]);
      expect(codigos(conta({ hora: '08:00' }, p('p1', 'rotina', { rotina: 'resumo_do_dia' })))).toEqual([]);
      expect(codigos(linear(p('p1', 'rotina', { rotina: 'resumo_do_dia' })))).toEqual([['p1', 'ROTINA_DA_CONTA']]);
      expect(validar(linear(p('p1', 'rotina', { rotina: 'xyz' })))[0]).toMatchObject({
        codigo: 'ROTINA_DESCONHECIDA',
        params: { nome: 'xyz' },
      });
    });
  });
```

`specs/migrados.spec.js` — somar `rotinaAlvo` ao import de `'../fluxo'`, importar os 7 JSON (mesmo caminho relativo dos outros: `'../../../../../../../../db/seeds/ramon/fluxos/migrados/<nome>.json'`, como `resumoDoDia`, `retratoFunil`, `fechamentoExtrato`, `espelhoPainel`, `copilotoNoturno`, `publicarPecas`, `avisosPainel`) e acrescentar:
```js
const CONTA = {
  resumo_do_dia: resumoDoDia,
  retrato_funil: retratoFunil,
  fechamento_extrato: fechamentoExtrato,
  espelho_painel: espelhoPainel,
  copiloto_noturno: copilotoNoturno,
  publicar_pecas: publicarPecas,
  avisos_painel: avisosPainel,
};

describe('fluxos migrados: rotinas da conta (B5-conta)', () => {
  it.each(Object.entries(CONTA))(
    '%s: publica, no Horário da conta, com a rotina de mesmo nome',
    (chave, d) => {
      expect(validar(d.desenho)).toEqual([]);
      expect(d.desenho.nos.map(n => n.tipo)).toEqual(['gatilho', 'rotina']);
      expect(d.desenho.nos[0].config.tipo).toBe('horario_conta');
      expect(d.desenho.nos[1].config.rotina).toBe(chave);
      expect(rotinaAlvo(chave)).toBe('conta');
    }
  );

  it('no horário de hoje do código (config/schedule.yml, em São Paulo)', () => {
    const quandoRoda = Object.fromEntries(
      Object.entries(CONTA).map(([k, d]) => {
        const c = d.desenho.nos[0].config;
        return [k, c.hora || `${c.a_cada_minutos} min`];
      })
    );
    expect(quandoRoda).toEqual({
      resumo_do_dia: '08:00',
      retrato_funil: '00:05',
      fechamento_extrato: '00:20',
      espelho_painel: '00:30',
      copiloto_noturno: '05:00',
      publicar_pecas: '1 min',
      avisos_painel: '08:00',
    });
  });
});
```

`specs/i18n.spec.js` — na lista de códigos de `ERROS` cobrados (`'GATILHO_HORA', 'ADVBOX_ACAO', …, 'CAMPO_CHAVE'`), acrescentar no fim: `'CONTA_QUANDO', 'CONTA_PASSO', 'ROTINA_DESCONHECIDA', 'ROTINA_DE_LEAD', 'ROTINA_DA_CONTA'`. (A cobertura de `GATILHOS` e `ROTINAS` já existe e passa a cobrar as chaves novas.)

- [ ] **Step 2: Rodar e ver falhar**

`TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts` → falham os novos (`rotinasPara` não existe etc.).

- [ ] **Step 3: Implementar**

Criar `…/automacoes/rotinas/conta.js`:
```js
// B5-conta: = Ramon::Fluxos::Rotinas::Conta::ROTINAS (as 7 rotinas da conta, só no gatilho Horário da conta).
export default [
  { chave: 'resumo_do_dia', alvo: 'conta' },
  { chave: 'retrato_funil', alvo: 'conta' },
  { chave: 'fechamento_extrato', alvo: 'conta' },
  { chave: 'espelho_painel', alvo: 'conta' },
  { chave: 'copiloto_noturno', alvo: 'conta' },
  { chave: 'publicar_pecas', alvo: 'conta' },
  { chave: 'avisos_painel', alvo: 'conta' },
];
```

`fluxo.js`:
- `GATILHOS`: acrescentar no fim (depois de `manual`): `{ tipo: 'horario_conta', icone: 'i-lucide-building-2', alvo: 'conta' },`
- trocar o bloco `export const ROTINAS = [ … ];` (com o comentário de cima) por:
```js
// Rotinas prontas do hub (= Ramon::Fluxos::Rotinas): as 5 da B4.4/B4.5 (de lead) + as de cada plano B5, um arquivo por
// plano em ./rotinas/<plano>.js = [{ chave, alvo: 'conta' | 'lead' | 'conversa' }] (= ROTINAS do módulo do plano).
const PLANOS = import.meta.glob('./rotinas/*.js', {
  eager: true,
  import: 'default',
});
export const ROTINAS_INFO = [
  ...[
    'dossie_passagem',
    'pesquisa_nps',
    'pesquisa_nps_exito',
    'abrir_caso_advbox',
    'concluir_tarefas',
  ].map(chave => ({ chave, alvo: 'lead' })),
  ...Object.keys(PLANOS)
    .sort()
    .flatMap(arquivo => PLANOS[arquivo]),
];
export const ROTINAS = ROTINAS_INFO.map(r => r.chave);
export const rotinaAlvo = chave =>
  ROTINAS_INFO.find(r => r.chave === chave)?.alvo;
// o select do passo: no Horário da conta só as da conta; nos demais gatilhos, só as de lead/conversa
export const rotinasPara = alvo =>
  ROTINAS_INFO.filter(r => (r.alvo === 'conta') === (alvo === 'conta')).map(
    r => r.chave
  );
// = Ramon::Fluxos::HorarioConta::PASSOS — o que roda sem lead (gatilho Horário da conta)
export const PASSOS_CONTA = [
  'se',
  'escolha',
  'esperar',
  'parar',
  'avisar_push',
  'rotina',
];
```

`validar.js`: somar `PASSOS_CONTA, rotinaAlvo` ao import de `'./fluxo'` e acrescentar antes de `export const validar`:
```js
// = Ramon::Fluxos::HorarioConta.erros: o "quando" do Horário da conta, o que roda sem lead e a rotina do alvo certo
const quandoValido = c => {
  const n = c.a_cada_minutos;
  const ok =
    n != null && n !== ''
      ? /^\d+$/.test(String(n)) && Number(n) >= 1 && Number(n) <= 1440
      : !vazio(c.hora);
  if (!ok || !('dias' in c)) return ok;
  const dias = [].concat(c.dias ?? []).map(Number);
  return dias.length > 0 && dias.every(d => d >= 0 && d <= 6);
};

const errosNoConta = (no, conta) => {
  if (no.tipo === 'gatilho') return [];
  if (conta && !PASSOS_CONTA.includes(no.tipo))
    return [erro(no.id, 'CONTA_PASSO')];
  const nome = no.config?.rotina;
  if (no.tipo !== 'rotina' || vazio(nome)) return [];
  const alvo = rotinaAlvo(nome);
  if (!alvo) return [erro(no.id, 'ROTINA_DESCONHECIDA', { nome })];
  if ((alvo === 'conta') === conta) return [];
  return [erro(no.id, conta ? 'ROTINA_DE_LEAD' : 'ROTINA_DA_CONTA')];
};

const errosConta = (gatilho, nos) => {
  const c = gatilho.config || {};
  const conta = c.tipo === 'horario_conta';
  const quando =
    conta && !quandoValido(c) ? [erro(gatilho.id, 'CONTA_QUANDO')] : [];
  return [...quando, ...nos.flatMap(n => errosNoConta(n, conta))];
};
```
e, no `return` final de `validar`, acrescentar `...errosConta(gatilho, nos),` depois de `...nos.flatMap(n => errosPasso(n, setas)),`.

`api/ramonFluxos.js`: comentário do `ensaio` → `// params: { lead_id } | { conversation_id } | { conta: true } (B5: Horário da conta) (+ usar: 'rascunho'|'publicada')`.

i18n — `pt_BR/ramon.json` e `en/ramon.json`, dentro de `CAPTAIN_RAMON.FLUXOS`, **no fim** de cada objeto (mesma ordem nos dois):

| objeto | depois de | chave → pt_BR / en |
|---|---|---|
| `GATILHOS` | `relogio` | `horario_conta` → "Horário da conta (a conta toda)" / "Account schedule (whole account)" |
| `EDITOR` | `COMO_RODA` | `TESTAR_CONTA` → "Testar na conta…" / "Test on the account…" |
| `NO` | `DESDE_CONVERSA` | `A_CADA` → "a cada {n} min" / "every {n} min" |
| `PAINEL` | `DOCUMENTO_AJUDA` | `CONTA_QUANDO` → "Quando roda" / "When it runs"; `CONTA_UMA_VEZ` → "Uma vez por dia" / "Once a day"; `CONTA_INTERVALO` → "A cada N minutos" / "Every N minutes"; `CONTA_MINUTOS` → "A cada quantos minutos (1 a 1440)" / "Every how many minutes (1 to 1440)"; `CONTA_DIAS` → "Em que dias" / "On which days"; `CONTA_AJUDA` → "Roda para a conta toda (não para um lead). Horário de São Paulo. Um fluxo novo começa no próximo horário." / "Runs for the whole account (not for a lead). São Paulo time. A new flow starts at the next scheduled time." |
| `ROTINAS` | `concluir_tarefas` | `resumo_do_dia` → "Resumo do dia (push e e-mail de gestão)" / "Daily summary (push and management e-mail)"; `retrato_funil` → "Retrato do funil (para os relatórios)" / "Funnel snapshot (for reports)"; `fechamento_extrato` → "Fechamento do extrato da variável" / "Variable pay statement closing"; `espelho_painel` → "Espelho do Painel do Cliente (ADVBOX)" / "Client Portal mirror (ADVBOX)"; `copiloto_noturno` → "Copiloto noturno (sugestões no Cockpit)" / "Night copilot (suggestions in the Cockpit)"; `publicar_pecas` → "Publicar no Instagram as peças agendadas" / "Publish scheduled pieces on Instagram"; `avisos_painel` → "Avisos do Painel do Cliente (e-mail ao cliente)" / "Client Portal notices (e-mail to the client)" |
| `ROTINAS_AJUDA` | `concluir_tarefas` | `resumo_do_dia` → "O mesmo resumo do código: push \"seu dia\" para a equipe (só se o dia tem algo e com o ntfy ligado) e o e-mail de gestão com os números de ontem (só com SMTP)." / "The same summary as the code: \"your day\" push to the team (only if the day has something and ntfy is on) and the management e-mail with yesterday's numbers (only with SMTP)."; `retrato_funil` → "Guarda a foto do funil do dia (etapas, teses e valores) para os relatórios. Rodar de novo no mesmo dia refaz a foto." / "Saves the day's funnel snapshot (stages, theses and values) for reports. Running again on the same day redoes it."; `fechamento_extrato` → "No 3º dia útil, fecha o extrato da variável do mês anterior (regulamento §6). Nos outros dias não faz nada; já fechado, não refaz." / "On the 3rd business day, closes last month's variable pay statement. On other days it does nothing; once closed, it is not redone."; `espelho_painel` → "Copia do ADVBOX processos, andamentos e pedidos de documento de todos os clientes do Painel. Vai para a fila (demora): o passo seguinte não espera terminar." / "Copies cases, updates and document requests of all Portal clients from ADVBOX. Goes to the queue (slow): the next step does not wait for it to finish."; `copiloto_noturno` → "Prepara sugestões para até 15 leads parados (rascunho, mover etapa ou alerta), que a equipe aprova no Cockpit. Nada vai ao cliente. Vai para a fila." / "Prepares suggestions for up to 15 stalled leads (draft, move stage or alert) for the team to approve in the Cockpit. Nothing goes to the client. Goes to the queue."; `publicar_pecas` → "Publica no Instagram só as peças já agendadas (com o pode postar) cuja hora chegou. Sem peça vencida, o fluxo nem começa. Falhou: aviso no celular, sem nova tentativa. Vai para a fila." / "Publishes on Instagram only pieces already scheduled (approved to post) whose time has come. With no piece due, the flow does not start. Failed: phone alert, no retry. Goes to the queue."; `avisos_painel` → "E-mail DIRETO ao cliente com as novidades do espelho da noite (etapas delicadas nunca) e o resumo da equipe com o WhatsApp pronto. Só com PORTAL_AVISOS ligado — hoje desligado até aprovar os textos." / "DIRECT e-mail to the client with the news from the nightly mirror (sensitive stages never) and the team summary with the WhatsApp text ready. Only with PORTAL_AVISOS on — off until the texts are approved." |
| `ERROS` | `CAMPO_CHAVE` | `CONTA_QUANDO` → "Escolha uma hora ou \"a cada N minutos\" (1 a 1440) e pelo menos um dia." / "Choose a time or \"every N minutes\" (1 to 1440) and at least one day."; `CONTA_PASSO` → "Este passo precisa de um lead. No Horário da conta só entram Se, Escolha, Esperar, Parar, Push e Rotina pronta." / "This step needs a lead. On the account schedule only If, Choose, Wait, Stop, Push and Ready routine are allowed."; `ROTINA_DESCONHECIDA` → "Rotina desconhecida ({nome})." / "Unknown routine ({nome})."; `ROTINA_DE_LEAD` → "Esta rotina é de um lead: não roda no Horário da conta." / "This routine belongs to a lead: it does not run on the account schedule."; `ROTINA_DA_CONTA` → "Esta rotina é da conta toda: só roda no gatilho Horário da conta." / "This routine is for the whole account: it only runs on the Account schedule trigger." |
| `TESTAR` | `CANCELAR` | `TITULO_CONTA` → "Testar na conta" / "Test on the account"; `AJUDA_CONTA` → "Ensaio na conta toda: as rotinas só dizem o que fariam — nada é executado." / "Dry run on the whole account: routines only say what they would do — nothing is executed." |

(As chaves `SELO.REGRA_FIXA` e `SISTEMA.FIXA_DICA` entram na Task 8.)

- [ ] **Step 4: Rodar e ver passar**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts
./node_modules/.bin/eslint --fix app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js app/javascript/dashboard/routes/dashboard/captain/automacoes/validar.js app/javascript/dashboard/routes/dashboard/captain/automacoes/rotinas/conta.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs
```
Expected: B + 12 testes (2 fluxo, 2 validar, 8 migrados) verdes; eslint sem `error`.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js app/javascript/dashboard/routes/dashboard/captain/automacoes/validar.js app/javascript/dashboard/routes/dashboard/captain/automacoes/rotinas/conta.js app/javascript/dashboard/api/ramonFluxos.js app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/fluxo.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/validar.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/migrados.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/i18n.spec.js
git commit -m "feat(fluxos): editor conhece o Horário da conta e as rotinas por plano (B5-conta)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 7: Editor — telas do Horário da conta (julgamento leve)

**Files:**
- Create: `…/automacoes/ConfigHorarioConta.vue`
- Modify: `…/automacoes/{ConfigGatilho.vue,PainelPasso.vue,Paleta.vue,NoPasso.vue,TestarComLead.vue,Editor.vue}`
- Test: `…/automacoes/specs/{ConfigHorarioConta.spec.js (novo),Paleta.spec.js (novo),PainelPasso.spec.js,NoPasso.spec.js}`

**Interfaces:**
- Consumes: `rotinasPara`, `PASSOS_CONTA`, `gatilhoInfo` (Task 6).
- Produces: `ConfigHorarioConta` (`props.config`, emite `update:config`); `PainelPasso` e `Paleta` com prop `alvo` (`'lead'` padrão | `'conta'`); `TestarComLead` com prop `conta` (Boolean) que emite `{ conta: true }`.

- [ ] **Step 1: Write the failing tests**

Criar `specs/ConfigHorarioConta.spec.js`:
```js
import { mount } from '@vue/test-utils';
import ConfigHorarioConta from '../ConfigHorarioConta.vue';

const montar = config => mount(ConfigHorarioConta, { props: { config } });

describe('ConfigHorarioConta', () => {
  it('uma vez por dia: edita a hora', async () => {
    const w = montar({ tipo: 'horario_conta', hora: '08:00' });
    await w.find('[data-testid="conta-hora"]').setValue('07:30');
    expect(w.emitted('update:config').at(-1)).toEqual([
      { tipo: 'horario_conta', hora: '07:30' },
    ]);
  });

  it('trocar o modo tira a outra chave (a cada N min começa em 1; por dia volta às 08:00)', async () => {
    const w = montar({ tipo: 'horario_conta', hora: '08:00', dias: [1] });
    await w.find('[data-testid="conta-modo"]').setValue('intervalo');
    expect(w.emitted('update:config').at(-1)).toEqual([
      { tipo: 'horario_conta', dias: [1], a_cada_minutos: 1 },
    ]);
    const i = montar({ tipo: 'horario_conta', a_cada_minutos: 5 });
    expect(i.find('[data-testid="conta-minutos"]').element.value).toBe('5');
    await i.find('[data-testid="conta-modo"]').setValue('dia');
    expect(i.emitted('update:config').at(-1)).toEqual([
      { tipo: 'horario_conta', hora: '08:00' },
    ]);
  });

  it('dias: sem a chave = todos marcados; desmarcar grava a lista', async () => {
    const w = montar({ tipo: 'horario_conta', hora: '08:00' });
    await w.find('[data-testid="conta-dia-0"]').setValue(false);
    expect(w.emitted('update:config').at(-1)).toEqual([
      { tipo: 'horario_conta', hora: '08:00', dias: [1, 2, 3, 4, 5, 6] },
    ]);
  });
});
```

Criar `specs/Paleta.spec.js`:
```js
import { mount } from '@vue/test-utils';
import Paleta from '../Paleta.vue';

describe('Paleta', () => {
  it('no Horário da conta só os passos que rodam sem lead', () => {
    const w = mount(Paleta, { props: { alvo: 'conta' } });
    expect(
      w.findAll('[data-testid^="paleta-"]').map(b => b.attributes('data-testid'))
    ).toEqual([
      'paleta-se',
      'paleta-escolha',
      'paleta-rotina',
      'paleta-avisar_push',
      'paleta-esperar',
      'paleta-parar',
    ]);
  });
});
```

`specs/PainelPasso.spec.js` — acrescentar:
```js
  it('rotina no Horário da conta: só as rotinas da conta', () => {
    const wrapper = mount(PainelPasso, {
      props: {
        no: { id: 'n2', data: { tipo: 'rotina', config: {} } },
        erros: [],
        alvo: 'conta',
      },
      global: { plugins: [store] },
    });
    const opcoes = wrapper
      .findAll('[data-testid="rotina"] option')
      .map(o => o.attributes('value'))
      .filter(Boolean);
    expect(opcoes).toEqual([
      'resumo_do_dia',
      'retrato_funil',
      'fechamento_extrato',
      'espelho_painel',
      'copiloto_noturno',
      'publicar_pecas',
      'avisos_painel',
    ]);
  });
```

`specs/NoPasso.spec.js` — acrescentar:
```js
describe('NoPasso — Horário da conta', () => {
  it('diz a hora ou o intervalo', () => {
    const dia = montar({ tipo: 'gatilho', config: { tipo: 'horario_conta', hora: '08:00' } });
    const intervalo = montar({ tipo: 'gatilho', config: { tipo: 'horario_conta', a_cada_minutos: 5 } });
    expect(dia.text()).toContain('08:00');
    expect(intervalo.text()).toContain('every 5 min');
  });
});
```

- [ ] **Step 2: Rodar e ver falhar** (`ConfigHorarioConta.vue` não existe; Paleta sem `data-testid` nem filtro; PainelPasso lista as 12).

- [ ] **Step 3: Implementar**

Criar `ConfigHorarioConta.vue`:
```vue
<script setup>
// Gatilho "Horário da conta" (B5-conta, Ramon::Fluxos::HorarioConta): uma vez por dia a partir de HH:MM ou a cada N
// minutos, nos dias marcados (sem a chave = todos). Fuso de São Paulo. O alvo é a conta toda, não um lead.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  CAMPO,
  ROTULO,
  SELECT,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

const props = defineProps({ config: { type: Object, required: true } });
const emit = defineEmits(['update:config']);
const K = 'CAPTAIN_RAMON.FLUXOS.PAINEL';
const { t } = useI18n();
const DIAS = [0, 1, 2, 3, 4, 5, 6];

const modo = computed(() => (props.config.a_cada_minutos ? 'intervalo' : 'dia'));
const dias = computed(() => props.config.dias ?? DIAS);

const muda = (chave, valor) =>
  emit('update:config', { ...props.config, [chave]: valor });
// a outra chave sai: o back lê 'a_cada_minutos' antes de 'hora'
const semModo = () =>
  Object.fromEntries(
    Object.entries(props.config).filter(
      ([k]) => !['hora', 'a_cada_minutos'].includes(k)
    )
  );
const trocaModo = novo =>
  emit(
    'update:config',
    novo === 'intervalo'
      ? { ...semModo(), a_cada_minutos: 1 }
      : { ...semModo(), hora: '08:00' }
  );
const marcaDia = (d, ligado) =>
  muda(
    'dias',
    ligado
      ? [...dias.value, d].sort((a, b) => a - b)
      : dias.value.filter(x => x !== d)
  );
</script>

<template>
  <div class="flex flex-col gap-3">
    <label :class="ROTULO">
      {{ t(`${K}.CONTA_QUANDO`) }}
      <select
        data-testid="conta-modo"
        :class="SELECT"
        :value="modo"
        @change="trocaModo($event.target.value)"
      >
        <option value="dia">{{ t(`${K}.CONTA_UMA_VEZ`) }}</option>
        <option value="intervalo">{{ t(`${K}.CONTA_INTERVALO`) }}</option>
      </select>
    </label>
    <label v-if="modo === 'dia'" :class="ROTULO">
      {{ t(`${K}.HORA`) }}
      <input
        data-testid="conta-hora"
        :class="CAMPO"
        type="time"
        :value="config.hora || ''"
        @input="muda('hora', $event.target.value)"
      />
    </label>
    <label v-else :class="ROTULO">
      {{ t(`${K}.CONTA_MINUTOS`) }}
      <input
        data-testid="conta-minutos"
        :class="CAMPO"
        type="number"
        min="1"
        max="1440"
        :value="config.a_cada_minutos"
        @change="muda('a_cada_minutos', Number($event.target.value) || 1)"
      />
    </label>
    <span :class="ROTULO">{{ t(`${K}.CONTA_DIAS`) }}</span>
    <div class="flex flex-wrap gap-3 text-[13px] text-n-slate-12">
      <label v-for="d in DIAS" :key="d" class="flex items-center gap-1">
        <input
          type="checkbox"
          class="reset-base"
          :data-testid="`conta-dia-${d}`"
          :checked="dias.includes(d)"
          @change="marcaDia(d, $event.target.checked)"
        />
        {{ t(`${K}.DIA_${d}`) }}
      </label>
    </div>
    <p class="text-xs text-n-slate-10">{{ t(`${K}.CONTA_AJUDA`) }}</p>
  </div>
</template>
```

`ConfigGatilho.vue`:
- importar `import ConfigHorarioConta from './ConfigHorarioConta.vue';`
- `trocaTipo`: acrescentar ao objeto emitido `...(tipo === 'horario_conta' ? { hora: '08:00' } : {}),` (antes do `rotulo`).
- template: antes de `<p v-if="config.tipo === 'manual'" …>`, inserir
  ```vue
      <ConfigHorarioConta
        v-if="config.tipo === 'horario_conta'"
        :config="config"
        @update:config="c => emit('update:config', c)"
      />
  ```
- o `<div>` do `CANCELAR_ETAPA` ganha `v-if="alvo !== 'conta'"` (não há etapa na conta).

`PainelPasso.vue`:
- props: acrescentar `alvo: { type: String, default: 'lead' },` (B5: o alvo do gatilho do fluxo).
- import de `'./fluxo'`: trocar `ROTINAS,` por `rotinasPara,`.
- script: `const rotinas = computed(() => rotinasPara(props.alvo)); // B5: só as do alvo do gatilho`
- template do passo `rotina`: `v-for="r in ROTINAS"` → `v-for="r in rotinas"`.

`Paleta.vue`:
- `import { computed, ref } from 'vue';` e somar `PASSOS_CONTA` ao import de `'./fluxo'`.
- `const props = defineProps({ alvo: { type: String, default: 'lead' } });`
- ```js
  // B5: no Horário da conta só os passos que rodam sem lead (grupo vazio some)
  const grupos = computed(() =>
    props.alvo === 'conta'
      ? PALETA.map(g => ({
          ...g,
          itens: g.itens.filter(i => PASSOS_CONTA.includes(i.tipo)),
        })).filter(g => g.itens.length)
      : PALETA
  );
  ```
- template: `v-for="grupo in PALETA"` → `v-for="grupo in grupos"`; o `<button>` ganha `:data-testid="`paleta-${item.chave}`"`.

`NoPasso.vue`, `case 'gatilho':` — logo no começo:
```js
      if (c.tipo === 'horario_conta')
        return c.a_cada_minutos
          ? t(`${K}.NO.A_CADA`, { n: c.a_cada_minutos })
          : t(`${K}.NO.AS_HORA`, { quando: c.hora || '—' });
```

`TestarComLead.vue`:
- `defineProps({…})` vira `const props = defineProps({ …, conta: { type: Boolean, default: false } });` (B5: Horário da conta — ensaio na conta toda).
- `alvo`: primeira linha `if (props.conta) return { conta: true };`.
- template: título `t(`${K}.${conta ? 'TITULO_CONTA' : 'TITULO'}`)`, ajuda `t(`${K}.${conta ? 'AJUDA_CONTA' : 'AJUDA'}`)`; envolver as abas, a busca/lista de leads e o campo de conversa num `<template v-if="!conta">…</template>`.

`Editor.vue`:
- somar `gatilhoInfo` ao import de `'./fluxo'`.
- script (perto de `noSelecionado`):
  ```js
  // B5-conta: o alvo do gatilho (lead/conversa ou a conta toda) — muda a paleta, as rotinas e o "Testar"
  const alvoGatilho = computed(
    () =>
      gatilhoInfo(nodes.value.find(n => n.data.tipo === 'gatilho')?.data.config?.tipo)
        ?.alvo || 'lead'
  );
  ```
- `<PainelPasso … :alvo="alvoGatilho" …/>`, `<Paleta v-if="paleta" :alvo="alvoGatilho" …/>`, `<TestarComLead … :conta="alvoGatilho === 'conta'" …/>`.
- botão Testar: `:label="t(`${K}.EDITOR.${alvoGatilho === 'conta' ? 'TESTAR_CONTA' : 'TESTAR'}`)"`.

- [ ] **Step 4: Rodar e ver passar**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts
./node_modules/.bin/eslint --fix app/javascript/dashboard/routes/dashboard/captain/automacoes
```
Expected: B + 12 + 6 = **226 testes, 17 arquivos** verdes (anote o número real); eslint sem `error`.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/ConfigHorarioConta.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/ConfigGatilho.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/PainelPasso.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/Paleta.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/NoPasso.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/TestarComLead.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/Editor.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/ConfigHorarioConta.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/Paleta.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/PainelPasso.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/NoPasso.spec.js
git commit -m "feat(fluxos): telas do Horário da conta — quando roda, dias, paleta, rotinas e Testar na conta (B5-conta)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 8: Selo "regra fixa (fica no código)" na aba Do sistema (mecânica)

**Files:**
- Modify: `db/seeds/ramon/fluxos/sistema/{historico_do_lead,docs_completos,contrato_limpo,contrato_limpo_cancelado,sdr_automatico}.json` (`"fixa": true`)
- Modify: `db/seeds/ramon/fluxos/sistema/resumo_do_dia.json` (tira o "fica no código" revogado)
- Modify: `app/services/ramon/fluxos/sistema.rb` (`extras`)
- Modify: `…/automacoes/{Lista.vue,Editor.vue}`, i18n `{en,pt_BR}/ramon.json`
- Test: `spec/services/ramon/fluxos/sistema_spec.rb`; `…/automacoes/specs/{sistema.spec.js,Lista.spec.js}`

**Interfaces:**
- Produces: `Ramon::Fluxos::Sistema.extras(account, chave)[:fixa] → Boolean`; o JSON do sistema aceita `"fixa": true`.

- [ ] **Step 1: Write the failing tests**

`spec/services/ramon/fluxos/sistema_spec.rb`, acrescentar:
```ruby
  it 'as 5 regras de dado são "regra fixa" (ficam no código, decisão do Eduardo 07/10)' do
    account = create(:account)
    fixas = described_class.desenhos.keys.select { |chave| described_class.extras(account, chave)[:fixa] }
    expect(fixas).to eq(%w[contrato_limpo contrato_limpo_cancelado docs_completos historico_do_lead sdr_automatico])
  end
```

`specs/sistema.spec.js`, acrescentar:
```js
  it('as 5 regras de dado são regra fixa (decisão do Eduardo 07/10)', () => {
    expect(
      DESENHOS.filter(([, d]) => d.fixa)
        .map(([chave]) => chave)
        .sort()
    ).toEqual([
      'contrato_limpo',
      'contrato_limpo_cancelado',
      'docs_completos',
      'historico_do_lead',
      'sdr_automatico',
    ]);
    DESENHOS.forEach(([, d]) => expect([undefined, true]).toContain(d.fixa));
  });
```

`specs/Lista.spec.js`, acrescentar:
```js
  it('Do sistema: regra fixa ganha o selo próprio no lugar de "roda no código"', async () => {
    rota.query = { aba: 'sistema' };
    RamonFluxosAPI.get.mockResolvedValue({
      data: {
        payload: [
          { ...SISTEMA, id: 7, nome: 'Histórico do lead', sistema_chave: 'historico_do_lead', fixa: true },
          SISTEMA,
        ],
        resumo: {},
      },
    });
    const wrapper = mount(Lista);
    await flushPromises();
    const fixas = wrapper.findAll('[data-testid="sistema-fixa"]');
    expect(fixas).toHaveLength(1);
    expect(fixas[0].text()).toContain('fixed rule (stays in code)');
    expect(wrapper.text()).toContain('runs in code');
  });
```

- [ ] **Step 2: Rodar/conferir que falham.**

- [ ] **Step 3: Implementar**

- Nos 5 JSON, logo depois da linha `"grupo": "…",` acrescentar `  "fixa": true,`.
- `resumo_do_dia.json` (sistema): na `descricao`, apagar o trecho `Fica no código (spec §8): é relatório, não fluxo — o desenho é só para conferir.\n\n` (o resto fica; a 1ª linha continua "No código: …").
- `sistema.rb`:
  - comentário do topo: `({nome, grupo, alcance?, fixa?, descricao, limite_dia?, desenho})` e, em `extras`, `# fixa: regra de dado que fica no código de propósito (selo "regra fixa"; decisão do Eduardo 07/10).`
  - em `extras`, no Hash: `hoje: …, grupo: …, alcance: …, fixa: desenho['fixa'] == true, resumo: …,`
- `Lista.vue`, última coluna da linha do sistema — trocar o `<span>` do `SELO.NO_CODIGO` por:
  ```vue
                <span
                  v-if="f.fixa"
                  data-testid="sistema-fixa"
                  :class="[CHIP, TOM.slate]"
                  class="whitespace-nowrap font-mono"
                  :title="t(`${K}.SISTEMA.FIXA_DICA`)"
                >
                  {{ t(`${K}.SELO.REGRA_FIXA`) }}
                </span>
                <span
                  v-else
                  :class="[CHIP, TOM.blue]"
                  class="whitespace-nowrap font-mono"
                >
                  {{ t(`${K}.SELO.NO_CODIGO`) }}
                </span>
  ```
  e acrescentar ao comentário do topo do arquivo `// B5: regra de dado ganha o selo "regra fixa (fica no código)" — não migra.`
- `Editor.vue`, logo depois do `<span v-if="somenteLeitura && fluxo.alcance" …>…</span>`:
  ```vue
        <span
          v-if="somenteLeitura && fluxo.fixa"
          data-testid="sistema-fixa"
          :class="[CHIP, TOM.slate]"
          class="shrink-0 font-mono"
          :title="t(`${K}.SISTEMA.FIXA_DICA`)"
        >
          {{ t(`${K}.SELO.REGRA_FIXA`) }}
        </span>
  ```
- i18n (no fim do objeto, os dois arquivos): `SELO` depois de `SOMBRA`: `REGRA_FIXA` → "regra fixa (fica no código)" / "fixed rule (stays in code)"; `SISTEMA` depois de `ALCANCE` (o objeto): `FIXA_DICA` → "Regra de dado do hub: fica no código de propósito e não vira fluxo editável." / "Hub data rule: stays in code on purpose and does not become an editable flow."

- [ ] **Step 4: Rodar e ver passar**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts
./node_modules/.bin/eslint --fix app/javascript/dashboard/routes/dashboard/captain/automacoes/Lista.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/Editor.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/specs
```
Expected: +2 testes verdes (total anotado na Task 7 + 2).

- [ ] **Step 5: Commit**

```bash
git add db/seeds/ramon/fluxos/sistema/historico_do_lead.json db/seeds/ramon/fluxos/sistema/docs_completos.json db/seeds/ramon/fluxos/sistema/contrato_limpo.json db/seeds/ramon/fluxos/sistema/contrato_limpo_cancelado.json db/seeds/ramon/fluxos/sistema/sdr_automatico.json db/seeds/ramon/fluxos/sistema/resumo_do_dia.json app/services/ramon/fluxos/sistema.rb app/javascript/dashboard/routes/dashboard/captain/automacoes/Lista.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/Editor.vue app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json spec/services/ramon/fluxos/sistema_spec.rb app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/sistema.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/Lista.spec.js
git commit -m "feat(fluxos): selo regra fixa nas 5 regras de dado da aba Do sistema (B5-conta)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 9: Verificação final + notas na spec + texto do PR (mecânica)

**Files:**
- Modify: `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (seção nova no fim)

- [ ] **Step 1: Front inteiro**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts
./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes app/javascript/dashboard/api/ramonFluxos.js
git status --short
```
Expected: 17 arquivos, B + 20 testes verdes; eslint sem `error`; `vitest.local.config.ts` fora da lista.

- [ ] **Step 2: Varredura de regras**

```bash
BASE=$(git merge-base HEAD origin/ramon)
git diff $BASE --stat -- enterprise db/migrate db/schema.rb config/schedule.yml
grep -rn "RAMON_FLUXO_ROTINAS\|RAMON_FLUXO_PUBLICAR_PECAS\|RAMON_FLUXO_AVISOS_PAINEL" app lib .env.example
grep -rn "def perform(account_id = nil)" app/jobs/ramon | wc -l
for f in app/services/ramon/fluxos/grafo.rb app/services/ramon/fluxos/horario_conta.rb app/services/ramon/fluxos/rotinas.rb app/services/ramon/fluxos/rotinas/conta.rb app/jobs/ramon/publicar_pecas_job.rb app/jobs/ramon/portal_avisos_job.rb; do echo "$f $(grep -cvE '^\s*(#|$)' $f)"; done
```
Expected: o 1º vazio (sem migração, sem mexer no cron nem no enterprise); as envs em `rotinas/conta.rb` e no `.env.example`; `7`; `grafo.rb` ≤ 160, módulos ≤ 100.

- [ ] **Step 3: Notas na spec** — acrescentar ao fim do `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md`:

```markdown
## 19. Notas da B5-conta (07/10/2026) — Horário da conta, as 7 rotinas da conta e o selo "regra fixa"

- **Escopo (Eduardo, 07/10):** migrar todas as automações do código, exceto as regras de dado. Revoga o "Resumo do dia fica no código" do §8. As 7 rotinas da conta (resumo do dia, retrato do funil, fechamento do extrato, espelho do Painel, copiloto noturno, publicar peças, avisos do Painel) viram 7 fluxos (`origem: usuario`, `sistema_chave` = o nome da rotina), criados por `rake ramon:fluxos:migracao:criar[<rotina>,conta]` a partir de `db/seeds/ramon/fluxos/migrados/<rotina>.json`, no horário de hoje do código.
- **Gatilho novo `horario_conta` (alvo = a conta):** `hora` (1×/dia a partir dela) ou `a_cada_minutos` (1–1440), `dias` (0–6; sem = todos), fuso SP; chamado pelo `Ramon::FluxoRelogioJob` (`Ramon::Fluxos::HorarioConta`). No quadro só entram Se, Escolha, Esperar, Parar, Push e Rotina pronta (o sino precisa de lead). "Testar na conta…" ensaia com `{conta: true}`. `FluxoExecucao#lead/#conversa` = nil com alvo conta.
- **A vez (o "reivindicar o dia" da B4.3, generalizado):** UPDATE condicional em `ultimo_disparo_em`. Por dia: 1 vez no dia; fluxo que nasceu depois da hora de hoje começa amanhã. A cada N min: 1 vez por bloco. O relógio e o job do código disputam a mesma vez do fluxo migrado: no comando → o fluxo faz (não começou — ocupado, erro do motor — → o código faz, reserva); fora do comando → quem pegou a vez faz pelo código. Trocar "a cada N min" ↔ "uma vez por dia" vale a partir da próxima vez.
- **Rotina pronta = o job de hoje para a conta:** cada job ganhou `perform(account_id = nil)` (sem conta = o cron, pulando a conta do fluxo no comando; com conta = o fluxo ou a reserva). Resumo, retrato, extrato e avisos rodam dentro do passo; espelho, copiloto e Instagram vão para a fila (passariam de 10 min e o relógio repetiria o passo órfão). Publicar peças só começa com peça vencida/presa (`PENDENTE`). Avisos do Painel seguem atrás de `PORTAL_AVISOS`.
- **Chaves:** 1 grupo de migração por rotina; 3 envs por família — `RAMON_FLUXO_ROTINAS` (as 5 internas), `RAMON_FLUXO_PUBLICAR_PECAS`, `RAMON_FLUXO_AVISOS_PAINEL`. Virar/voltar cada rotina: `…migracao:modo[<rotina>,conta,normal|sombra]`, sem deploy. Em sombra o fluxo da conta não ensaia sozinho.
- **Registro de rotinas por plano:** `Ramon::Fluxos::Rotinas` acha `app/services/ramon/fluxos/rotinas/<plano>.rb` (`ROTINAS` nome → alvo, `rodar(nome, ctx)`, opcionais `GRUPOS` — juntados em `Migracao::GRUPOS` — e `PENDENTE`); o front acha `automacoes/rotinas/<plano>.js`. Publicar recusa rotina desconhecida e rotina do alvo errado.
- **Regras de dado ficam no código** com o selo "regra fixa (fica no código)" na aba Do sistema (`"fixa": true` no JSON): histórico do lead, documentos completos, contrato limpo, contrato limpo cancelado, SDR automático.
- **Tetos aceitos:** retrato do funil datado pelo relógio do servidor (UTC) — só muda de data se o horário for para 21:00–23:59; o resumo da equipe dos avisos é 1 por conta (há 1 conta); o expurgo de acessos do Painel fica no cron.
- **Fica para a limpeza (outro PR, 2 semanas depois em normal):** tirar as 7 entradas do `config/schedule.yml` e o ramo "cron" do `cada_conta` (os jobs ficam: são a rotina), os JSON `sistema/<rotina>.json` **e** as linhas `origem: sistema` deles, as 3 envs.
```

- [ ] **Step 4: Texto do PR (não abrir — gate do Eduardo)** — deixar no relatório final:

```markdown
Automações em fluxo — B5-conta: as 7 rotinas da conta (resumo do dia, retrato do funil, fechamento do extrato, espelho do Painel, copiloto noturno, publicar peças no Instagram e avisos do Painel) ganham 7 fluxos de verdade num gatilho novo, **"Horário da conta"** — horário e dias editáveis (ou "a cada N minutos"), liga/desliga e push antes/depois. Cada rotina chama exatamente o mesmo código de hoje, com as mesmas travas (avisos só com PORTAL_AVISOS; Instagram só publica peça já agendada). Com as chaves desligadas (padrão) tudo segue pelo código como hoje; ligada e com o fluxo em modo normal, o fluxo faz e o código pula a conta — nunca os dois, nunca nenhum, nem na virada no meio do dia. Voltar é um comando, sem deploy. Na aba "Do sistema", as 5 regras de dado ganham o selo "regra fixa (fica no código)".

## Closes
- Spec `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` §8 (B5: rotinas da conta; revoga "resumo do dia fica no código"); notas novas em §19.

## How to test
1. Depois do deploy: criar os 7 fluxos (seção "Operação") → "modo sombra, ligado" e "Agora o CÓDIGO faz …".
2. Inteligência → Automações → Meus fluxos: os 7 com o gatilho "Horário da conta" e o selo "em sombra"; abrir "Resumo do dia" → "Testar na conta…" → a trilha diz "faria: o resumo do dia".
3. Num fluxo novo, escolher "Horário da conta": "Quando roda" (uma vez por dia / a cada N minutos), dias, e a paleta só com os passos que rodam sem lead.
4. Aba "Do sistema": Histórico do lead, Documentos completos, Contrato limpo (e cancelado) e SDR automático com o selo "regra fixa".
5. Virar e conferir (seção "Operação").

## What changed
- Gatilho `horario_conta` (`Ramon::Fluxos::HorarioConta`) no relógio de 1 minuto, com a vez reivindicada no banco; alvo = a conta no motor; ensaio na conta.
- Registro de rotinas por plano (`Ramon::Fluxos::Rotinas` + `rotinas/conta.rb`); os 7 jobs com `perform(account_id = nil)`; 7 desenhos em `db/seeds/ramon/fluxos/migrados/`.
- Envs `RAMON_FLUXO_ROTINAS`, `RAMON_FLUXO_PUBLICAR_PECAS`, `RAMON_FLUXO_AVISOS_PAINEL` (desligadas). Sem migração; o cron não muda.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR
```

- [ ] **Step 5: Smoke em bloco** — anotar no relatório a seção "Operação depois do deploy" inteira.

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md
git commit -m "docs(fluxos): notas da B5-conta na spec" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

Sem push.

---

## Operação depois do deploy

Conta da banca = **2**; console = `docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "<task>"` / `… rails runner '<ruby>'` (o Eduardo roda via `!` e cola a saída). Deploy = o de sempre, **sem migração**. **Junto com o deploy**, acrescentar ao `chatwoot.env` em `/opt/intranet-ramon`: `RAMON_FLUXO_ROTINAS=on`, `RAMON_FLUXO_PUBLICAR_PECAS=on`, `RAMON_FLUXO_AVISOS_PAINEL=on` — seguro: sem os fluxos em modo normal, o código segue fazendo tudo. Recriar web **e** worker (o cron roda no worker).

**1. Criar os 7 fluxos (código ainda no comando).**
```
docker exec intranet-ramon-chatwoot-web-1 bundle exec rails runner '
a = Account.find(2)
Ramon::Fluxos::Rotinas::Conta::JOBS.each_key { |k| Ramon::Fluxos::Migracao.semear(a, k); puts Ramon::Fluxos::Migracao.descrever(a, k) }'
```
Esperado: 7 × "modo sombra, ligado" + "Agora o CÓDIGO faz …". Rodar de novo não duplica. Criados depois do horário de hoje, só começam amanhã (nada roda 2× hoje).

**2. Conferir na tela.** Automações → Meus fluxos: 7 fluxos com o gatilho "Horário da conta", selo "em sombra". Abrir "Resumo do dia" → **Testar na conta…** → **Ensaio**: trilha "faria: o resumo do dia". Abrir "Avisos do Painel do Cliente" → Testar: "avisos do Painel desligados … — nada enviado". Aba Do sistema: 5 com "regra fixa".

**3. Virar (N6: os 7 juntos).**
```
docker exec intranet-ramon-chatwoot-web-1 bundle exec rails runner '
a = Account.find(2)
Ramon::Fluxos::Rotinas::Conta::JOBS.each_key { |k| Ramon::Fluxos::Migracao.mudar_modo!(a, k, "normal"); puts Ramon::Fluxos::Migracao.descrever(a, k) }'
```
Esperado: 7 × "Agora os FLUXOS fazem …". (Uma só: `rake "ramon:fluxos:migracao:modo[resumo_do_dia,2,normal]"`.)

**4. Teste ao vivo de hoje (N5).** Faz o Resumo do dia e o Retrato do funil rodarem de novo hoje, pelo fluxo:
```
docker exec intranet-ramon-chatwoot-web-1 bundle exec rails runner '
a = Account.find(2)
%w[resumo_do_dia retrato_funil].each { |k| Ramon::Fluxos::Migracao.fluxo(a, k).update_columns(created_at: 2.days.ago, ultimo_disparo_em: nil) }
puts "ok — em até 1 minuto o relógio roda os 2"'
```
Esperar 2 minutos e rodar o **conferidor**:
```
docker exec intranet-ramon-chatwoot-web-1 bundle exec rails runner '
a = Account.find(2)
Ramon::Fluxos::Rotinas::Conta::JOBS.each_key do |k|
  f = Ramon::Fluxos::Migracao.fluxo(a, k)
  e = f.execucoes.where(ensaio: false).order(:id).last
  puts "#{k}: #{f.modo} · #{e ? e.created_at.in_time_zone("America/Sao_Paulo").strftime("%d/%m %H:%M") : "nenhuma"} #{e&.status} — #{e&.trilha&.last&.dig("resumo")}"
end'
```
Esperado agora: `resumo_do_dia: normal · <hoje HH:MM> concluida — fez: o resumo do dia` e `retrato_funil: … — fez: o retrato do funil`; no celular o push "Ramon Hub · seu dia" (se o dia tem algo) e o e-mail de gestão. Os outros: "nenhuma".

**5. Amanhã de manhã (depois das 08:05):** rodar o **conferidor** de novo. Esperado: `retrato_funil` 00:05, `fechamento_extrato` 00:20 ("fez: …" — fora do 3º dia útil o job não faz nada, como hoje), `espelho_painel` 00:30 ("pôs na fila: …"), `copiloto_noturno` 05:00 ("pôs na fila: …"), `resumo_do_dia` 08:00, `avisos_painel` 08:00 ("avisos do Painel desligados … — nada enviado"); `publicar_pecas`: só depois da próxima peça agendada (ter/qua/qui 12h) — "pôs na fila: a publicação das peças no Instagram" e a peça publicada **uma vez**. Conferir também: **um** push "seu dia" às 8h (não dois) e o Cockpit com as sugestões da madrugada uma vez só.

**6. Rollback (a qualquer momento, sem deploy, cada rotina independente).** `docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:migracao:modo[<rotina>,2,sombra]"` → "Agora o CÓDIGO faz …" (os 7 de uma vez: o runner do passo 3 com `"sombra"`). Também seguro: desligar o fluxo na tela (N1) ou tirar a env e recriar. A vez de hoje que o fluxo já pegou não é refeita pelo código (e vice-versa).

**7. Depois (outro PR, E7).** Com 2 semanas em normal sem incidente: tirar as 7 entradas do `config/schedule.yml` e o ramo "cron" de `Rotinas::Conta.cada_conta` (os jobs ficam: são a rotina), os JSON `db/seeds/ramon/fluxos/sistema/<rotina>.json` **e** as linhas `origem: sistema` deles (a sincronização não apaga linha cujo JSON sumiu), as 3 envs. Depois disso, desligar na tela = a rotina para (N1).

---

## Divergências registradas (spec × este plano)

| # | Onde | Divergência | Motivo |
|---|---|---|---|
| 1 | Spec §8 ("Resumo do dia fica no código") | O resumo do dia migra | Decisão do Eduardo, 07/10 |
| 2 | Spec §4.1 (alvos: conversa, lead, tarefa) | Alvo novo: a conta (`Account`) | as rotinas são da conta, não de um lead |
| 3 | Spec §6 (relógio dispara `relogio`/`lead_parado` 1×/dia) | `horario_conta` também a cada N minutos; e "fluxo que nasce depois da hora começa amanhã" (o `relogio` dispara no mesmo dia) | publicar peças roda a cada minuto; nascer depois da hora não pode repetir a vez que o código já fez |
| 4 | Spec §8 B4+ (sombra = ensaio nos eventos reais) | Fluxo da conta em sombra não ensaia sozinho | sem execuções de ensaio a cada minuto/dia (como a cadência, §17) |
| 5 | Desenho `sistema/espelho_painel.json` | O expurgo de acessos do Painel fica no cron | é da instalação toda, não de uma conta |
