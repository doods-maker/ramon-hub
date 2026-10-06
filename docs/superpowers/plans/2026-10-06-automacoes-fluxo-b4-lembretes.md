# Automações em fluxo — B4.1 (lembretes de reunião em sombra) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Os 5 lembretes de reunião (24h · 8h · 1h · 30 min · 5 min antes, sino do Closer e do SDR + push) ganham um **fluxo de verdade** que roda **em sombra** (ensaio nos eventos reais) ao lado do código, uma **comparação** legível código × fluxo, e uma **chave** (`RAMON_FLUXO_LEMBRETES=on` + fluxo em modo `normal`) que, quando o Eduardo virar, faz o fluxo assumir e o código parar de agendar. A chave nasce **desligada**: nada muda em produção até o Eduardo virar.

**Architecture:** O motor ganha o mínimo para ser fiel ao código: `esperar` com `antes_de: 'reuniao'` (conta para trás a partir do horário da reunião, que agora viaja em ISO no gatilho; horário já passado → não espera e marca `{horario_passou}=sim`), a variável `{reuniao_de_pe}` (a mesma regra do guard do `MeetingReminderJob`), o sino `para: 'closer_e_sdr'` (a mesma regra de destinatários do job) e "remarcar = recomeçar" no `Disparo` para o gatilho `reuniao_marcada`. As regras de reunião aberta e destinatários passam a morar num módulo só (`Ramon::Fluxos::Lembretes`), usado pelo código e pelo fluxo — a sombra compara a mesma regra. O fluxo é criado por um rake idempotente a partir de um JSON (`origem: usuario`, `sistema_chave: lembretes_reuniao`, `modo: sombra`). A comparação é um serviço só-leitura + rake que põe lado a lado o sino `ramon_meeting_reminder` (o que o código mandou) e as linhas `faria: sino para …` das execuções em sombra. A chave fica em **um** ponto: `ReuniaoAgendamento#enqueue_reminders`. Sem migração.

**Tech Stack:** Rails 7.1 / RSpec (só no CI), Postgres jsonb, Sidekiq (ActiveJob); Vue 3.5 `<script setup>`, vue-i18n 9, Vitest 3 + @vue/test-utils.

**Spec:** `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (§3 vocabulário — modo sombra, §4.4 esperar, §6 motor — sombra = ensaio, §8 migração B4+, §13 notas da B2b, §14 notas da B3 — "B4: o fluxo em sombra é um fluxo próprio (origem `usuario`)…"). Plano de referência de estilo: `docs/superpowers/plans/2026-10-06-automacoes-fluxo-b3.md`.

## Global Constraints

- Base: produção **71e1ce0** (B1 motor, B2 quadro, B2b IA/ADVBOX/webhook/gatilhos externos/relógio e B3 aba Do sistema no ar); branch `feat/fluxos-b4-lembretes`, worktree `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-fluxos-b4`. Nunca `git push`, nunca abrir PR (gate do Eduardo / sessão principal).
- **Produção não muda até o Eduardo virar a chave.** Com `RAMON_FLUXO_LEMBRETES` ausente/`off` (padrão) o código agenda e manda os lembretes exatamente como hoje. O fluxo em sombra só nasce quando alguém roda o rake `ramon:fluxos:lembretes:sombra` (depois do deploy) e, em sombra, só ensaia (não avisa ninguém).
- **Não apagar nada do caminho antigo nesta fatia:** `Ramon::MeetingReminderJob`, `ReuniaoAgendamento#enqueue_reminders` e o desenho `db/seeds/ramon/fluxos/sistema/lembretes_reuniao.json` (e a linha `origem: sistema` dele) ficam. A limpeza é outro PR, depois de rodar em `normal` (Decisão E7).
- **Sem migração.** `ramon_fluxos` já tem `origem`, `sistema_chave`, `modo`, `rascunho`, `ativo`; `ramon_fluxo_execucoes` já tem `ensaio`, `contexto`, `trilha`. O índice único parcial `index_ramon_fluxo_execucoes_unica_ativa` vale só para `NOT ensaio` (`db/schema.rb:1511`). Se alguma task achar que precisa de coluna/índice: pare e pergunte (migração exigiria regenerar `db/schema.rb` por scratch DB na VPS — não há Postgres local).
- **Rubocop do fork** (o CI barra): `Metrics/AbcSize` 26, `Metrics/MethodLength` 19, `Metrics/CyclomaticComplexity` 7, `Metrics/PerceivedComplexity` 8, `Metrics/ClassLength` 175, `Metrics/BlockLength` 30 (fora de spec), linha 150, `Style/HashSyntax` `EnforcedShorthandSyntax: never` (sempre `chave: valor`), `rubocop-rspec` (`RSpec/MultipleExpectations` 7, `RSpec/ExampleLength` 50, `RSpec/SpecFilePathFormat`: spec de `A::B::C` em `spec/.../a/b/c_spec.rb`). **`app/models/lead.rb`, `app/services/ramon/advbox_event_processor.rb` e `app/finders/conversation_finder.rb` estão NO LIMITE de 175 linhas: nenhuma linha nova neles** (este plano não toca nenhum dos três). Tamanhos conferidos na base: `reuniao_agendamento.rb` 126 linhas (vai a ~131), `meeting_reminder_job.rb` 52 (vai a ~40), `contexto.rb` 87 (~110), `disparo.rb` 97 (~115), `executor.rb` 144 (~146).
- **CI FOSS apaga `enterprise/`:** todo código que toque `Captain::*` fica atrás de `ChatwootApp.enterprise?` e o spec dele com `if: ChatwootApp.enterprise?`. A B4.1 não toca Captain — se precisar, pare.
- **Sem Ruby local:** specs Ruby são escritos e conferidos à mão (rastrear cada linha) e quem valida é o CI. Spec que viaja no tempo usa `travel_to`/`travel`; código que o spec faz viajar nunca usa `NOW()` do SQL (só `Time.current`). Helper de spec que cria execução viva (`ctx` de `passos_spec.rb`, `execucao` de `contexto_spec.rb`) é chamado **uma vez por exemplo** (o índice único parcial barra 2 execuções `rodando/esperando` não-ensaio no mesmo fluxo+alvo).
- **Mensagem ao cliente SEMPRE rascunho; só admin edita.** O ciclo de lembretes não tem nenhum texto ao cliente — só sino e push internos (o push diz "hora de mandar a mensagem de confirmação pro cliente": é para a equipe). O rascunho de confirmação ao cliente continua no código (Decisão E1). A API de fluxos segue admin-only (`RamonFluxoPolicy#gerenciar?`).
- **Front:** i18n só dentro de `CAPTAIN_RAMON.FLUXOS` em `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json`, chaves novas na **mesma posição** nos dois arquivos (a trava `specs/i18n.spec.js` compara a ordem e compila no vue-i18n de produção); strings sem `@`, `|`, `{`, `}` crus (só `{tempo}`); editar os JSON à mão (Edit). Tailwind only, kit `ramon/helpers/ui.js` (`TOM`, `ROTULO`, `CAMPO`, `SELECT`, `CHIP`), evento custom camelCase, toda `<ul>/<ol>` nova com `list-none` (a B4.1 não cria lista), sem texto cru no template.
- **Vitest:** `node_modules` é junção para `ramon-hub-wt-fluxos-b2\node_modules` (nunca `rm -rf node_modules`). Config local **já criado e fora do git** `vitest.local.config.ts` na raiz do worktree (não commitar):
  `TZ=UTC npx vitest run <arquivos ou pastas> --config vitest.local.config.ts`
  Baseline medido na base 71e1ce0: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs` = **14 arquivos, 163 testes**. ESLint: `./node_modules/.bin/eslint <arquivos>` (erro `Delete ␍` = CRLF do checkout Windows, ignorar; warnings `@intlify/vue-i18n/no-dynamic-keys` já existem e são aceitos).
- **Commits:** Conventional Commits em pt-BR, sem citar Claude no assunto; corpo termina com:
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv`
  Commitar só os caminhos da task (`git add <arquivos>`), nunca `git add -A`.

## Review Focus

1. **Remarcar enquanto o fluxo espera** (painel do lead, Cal.com `BOOKING_RESCHEDULED`, ida e volta para o mesmo horário) — os lembretes seguem o horário novo, nunca saem no antigo e nunca em dobro; em modo normal o índice único não pode engolir a remarcação. Teste: Task 4 ("remarcar recomeça… normal e sombra") e Task 5 ("remarcar recomeça pelo horário novo…").
2. **Lead que muda de etapa antes da reunião** (vai para Negociação, volta para Qualificação) — o código continua lembrando; o fluxo não pode cancelar por "saiu da etapa". Teste: Task 5 ("lead que muda de etapa antes da reunião continua lembrado").
3. **Reunião marcada em cima da hora** (daqui a 10h, daqui a 7 min) — nenhum lembrete "atrasado" sai na hora da marcação; saem só os que o código também mandaria. Teste: Task 2 ("horário já passado…") e Task 5 ("reunião daqui a 10h: ensaia os 4 lembretes…").
4. **Chave meio virada** (env ligada com o fluxo ainda em sombra/desligado; fluxo em normal sem a env; voltar para sombra) — nunca ficar sem lembrete nem lembrar em dobro. Teste: Task 6 (os 4 exemplos de "a chave").
5. **Comparação desonesta** (aviso do sino apagado pelo teto de 300 por pessoa, "Testar com um lead…", reunião marcada antes da sombra existir) — não acusar divergência falsa nem esconder uma real. Teste: Task 7 (exemplos 3 e 4).

---

## Como o fluxo fica fiel ao código (decisões de desenho)

| O código faz hoje | O fluxo faz (B4.1) | Onde |
|---|---|---|
| `ReuniaoAgendamento#enqueue_reminders` agenda 5 jobs (`OFFSETS` 24h/8h/1h/30min/5min) **só os ainda no futuro** | 5 × `esperar {antes_de: 'reuniao', quantidade, unidade}`; momento já passado → não espera e devolve `vars: {horario_passou: 'sim'}`; o `se` seguinte só deixa passar com `horario_passou = nao` | Task 2, desenho na Task 5 |
| O horário da reunião vai no argumento do job (`start_at.iso8601`) | O gatilho `reuniao_marcada` passa a levar `'inicio' => starts_at.iso8601` além do `'quando'` formatado; `Contexto#reuniao_em` lê dele (sem ele — "Testar com um lead…" — usa a próxima reunião aberta do lead) | Tasks 1 e 2 |
| Guard do job: tarefa `meeting` aberta em `start_at ± 60 s` (`meeting_open?`); cancelou/concluiu/remarcou → lembrete órfão descartado | `{reuniao_de_pe}` (sim/nao) calculado **na hora do passo** com a **mesma função** `Ramon::Fluxos::Lembretes.reuniao_aberta?` | Tasks 1 e 2 |
| Dedupe por cache (`ramon:reminder:<lead>:<início>:<label>`) para remarcar ida e volta | **Remarcar = recomeçar**: um novo `reuniao_marcada` cancela a execução `esperando` do mesmo fluxo+lead antes de criar a nova (vale em normal e em sombra). Sem isso, em modo normal o índice único barraria a execução nova e os lembretes seguiriam o horário antigo | Task 4 |
| Sino `ramon_meeting_reminder` para Closer + SDR; sem nenhum, administradores | `avisar_sino {para: 'closer_e_sdr'}` com a **mesma função** `Ramon::Fluxos::Lembretes.destinatarios`; no ensaio a trilha diz quem receberia (`faria: sino para Ana, Bruno: "…"`) | Tasks 1 e 3 |
| Push ntfy só com `NTFY_TOPIC` | `avisar_push` (o `Ramon::NtfyPushJob` já é no-op sem `NTFY_TOPIC`) | — (já existe) |
| Não cancela se o lead muda de etapa | gatilho com `cancelar_se_sair_da_etapa: false` | Task 5 |
| Atividade, tarefa da reunião, etapa, Closer automático, rascunho de confirmação, sino/push "reunião marcada/cancelada" | **ficam no código** (são o registro da reunião, não o lembrete) — Decisão E1 | — |

**Por que "remarcar = recomeçar" e não "a espera relê a reunião ao retomar":** reler ao retomar exigiria recalcular a espera (a reunião pode ter ido para mais tarde → a execução acordaria cedo demais) e, em modo normal, o índice único continuaria engolindo o segundo `reuniao_marcada`. Cancelar a espera antiga e começar de novo é uma linha de regra no `Disparo`, faz o fluxo contar sempre da reunião vigente e reproduz o efeito do dedupe do código. Custo conhecido: um lead com **duas** reuniões abertas ao mesmo tempo fica com lembretes só da última marcada (o código lembra das duas) — raro, vai para o Eduardo (Decisão E3), e a sombra faz igual, então a comparação acusaria se acontecer.

**Por que a comparação lê o sino:** o código não grava outro rastro dos lembretes (só `Rails.logger` e uma chave de cache de 25h). O sino `ramon_meeting_reminder` é gravado por pessoa (`Notification`, `primary_actor` = Lead, `meta` = `quando` + `label`) — rastro real, sem migração, sem mexer no código. Limites tratados: o Chatwoot apaga todo dia o que passa de 300 avisos por pessoa (`Notification::RemoveOldNotificationJob`) → a comparação só olha depois do aviso mais antigo que sobrou de quem bateu o teto, e roda **todo dia** (operação); quem apaga um aviso na mão gera "só no fluxo" (falso alarme, nunca falso "bateu").

**Por que a chave é dupla (env + modo normal):** o código só deixa de agendar quando `RAMON_FLUXO_LEMBRETES=on` **e** existe o fluxo `lembretes_reuniao` (origem usuário) ligado, publicado e em `modo: normal`. Assim: env ligada com o fluxo em sombra/desligado → o código segue (nunca fica sem lembrete); virar o fluxo para normal sem a env é recusado pelo rake (senão código e fluxo lembrariam em dobro); voltar para sombra (rake) devolve os lembretes ao código na hora, sem deploy. As reuniões marcadas antes da virada mantêm os jobs que já estão na fila do Sidekiq (o job **não** consulta a chave) → nem buraco nem dobra na transição.

## Mapa de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `app/services/ramon/fluxos/lembretes.rb` (novo) | regras únicas (`reuniao_aberta?`, `destinatarios`), o fluxo dos lembretes (`fluxo`, `semear`), a chave (`ligada?`, `assumiu?`, `mudar_modo!`, `descrever`) |
| `app/services/ramon/fluxos/comparar_lembretes.rb` (novo) | comparação só-leitura código × sombra (`linhas`, `bateu?`, `relatorio`) |
| `db/seeds/ramon/fluxos/migrados/lembretes_reuniao.json` (novo) | desenho do fluxo (21 passos), nome e descrição |
| `lib/tasks/ramon_fluxos.rake` (novo) | `ramon:fluxos:lembretes:sombra[account_id]`, `:comparar[account_id,dias]`, `:modo[account_id,normal\|sombra]` |
| `app/jobs/ramon/meeting_reminder_job.rb` | usa `Lembretes.reuniao_aberta?` e `Lembretes.destinatarios` (refactor sem mudança de comportamento) |
| `app/services/ramon/reuniao_agendamento.rb` | `notify` manda `'inicio'` ISO ao gatilho; `enqueue_reminders` respeita a chave |
| `app/services/ramon/fluxos/contexto.rb` | `reuniao_em` (público), `{reuniao_de_pe}`, `RESERVADAS` + `reuniao_de_pe`, `horario_passou` |
| `app/services/ramon/fluxos/passos/logica.rb` | `esperar` com `antes_de: 'reuniao'` |
| `app/services/ramon/fluxos/passos/aviso.rb` | sino `para: 'closer_e_sdr'`; ensaio diz quem receberia |
| `app/services/ramon/fluxos/disparo.rb` | `reuniao_marcada` recomeça (cancela a espera antiga) |
| `app/services/ramon/fluxos/executor.rb` | desligar o fluxo cancela também a sombra que espera |
| `.env.example` | documenta `RAMON_FLUXO_LEMBRETES` |
| `app/javascript/dashboard/routes/dashboard/captain/automacoes/{fluxo.js,validar.js,PainelPasso.vue,NoPasso.vue,Lista.vue}` | o editor entende "antes da reunião", os 2 campos novos, o sino para Closer e SDR, o selo "em sombra" |
| `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json` | textos novos |
| `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` | §15 Notas da B4.1 |

---

### Task 1: Regras únicas dos lembretes + horário da reunião em ISO no gatilho

**Files:**
- Create: `app/services/ramon/fluxos/lembretes.rb`
- Modify: `app/jobs/ramon/meeting_reminder_job.rb` (arquivo inteiro)
- Modify: `app/services/ramon/reuniao_agendamento.rb:50-58` (`self.notify`)
- Test: `spec/services/ramon/reuniao_agendamento_spec.rb` (1 exemplo novo); `spec/jobs/ramon/meeting_reminder_job_spec.rb` (sem mudança — é a trava do refactor)

**Interfaces:**
- Produces: `Ramon::Fluxos::Lembretes::CHAVE = 'lembretes_reuniao'`, `TOLERANCIA = 60.seconds`; `Ramon::Fluxos::Lembretes.reuniao_aberta?(lead, inicio) → Boolean` (`inicio` = Time ou nil); `Ramon::Fluxos::Lembretes.destinatarios(lead) → Array<Integer>` (user_ids). O gatilho `reuniao_marcada`/`reuniao_cancelada` passa a receber `dados = { 'quando' => String, 'inicio' => String ISO8601 | nil }`.

- [ ] **Step 1: Write the failing test** — em `spec/services/ramon/reuniao_agendamento_spec.rb`, logo depois do exemplo `'marcar e cancelar disparam os fluxos de reunião'`:

```ruby
  it 'manda aos fluxos o horário da reunião em ISO (os lembretes contam para trás a partir dele)' do
    allow(Ramon::Fluxos::Disparo).to receive(:externo)
    agendar
    expect(Ramon::Fluxos::Disparo).to have_received(:externo)
      .with('reuniao_marcada', lead, hash_including('inicio' => starts_at.iso8601, 'quando' => 'quarta, 15/07 às 11:00'))
  end
```

- [ ] **Step 2: Run to verify it fails**

Run (CI): `bundle exec rspec spec/services/ramon/reuniao_agendamento_spec.rb`
Expected: FAIL — `received :externo with unexpected arguments` (o hash só tem `'quando'`).

- [ ] **Step 3: Implementation**

(a) Criar `app/services/ramon/fluxos/lembretes.rb`:

```ruby
# B4.1 (spec §8 e §15): os lembretes de reunião saindo do código para um fluxo. As regras moram aqui, uma vez
# só, e valem para os dois lados — o código (Ramon::MeetingReminderJob) e o fluxo (Contexto {reuniao_de_pe},
# sino "para: closer_e_sdr") —, então a sombra compara exatamente a mesma regra.
module Ramon::Fluxos::Lembretes
  CHAVE = 'lembretes_reuniao'.freeze # a mesma do desenho do sistema (B3) que este fluxo vai substituir
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

(b) Substituir `app/jobs/ramon/meeting_reminder_job.rb` inteiro por (mesmo comportamento; `TOLERANCE`, `destinatarios` e `meeting_open?` saem — conferido: nenhum outro arquivo usa `MeetingReminderJob::TOLERANCE`):

```ruby
# Lembrete anti no-show (mapa comercial 23/07): agendado via set(wait_until:)
# pelo Ramon::ReuniaoAgendamento. Cancel/reschedule não desagenda nada — o guard da
# tarefa aberta mata o lembrete órfão. As regras (reunião de pé, quem recebe) moram em
# Ramon::Fluxos::Lembretes: são as mesmas do fluxo que vai substituir este job (B4.1).
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
    unless lead && Ramon::Fluxos::Lembretes.reuniao_aberta?(lead, start_at)
      return Rails.logger.info("MeetingReminderJob: lead #{lead_id} sem reunião aberta em #{start_at_iso} — lembrete órfão descartado")
    end
    # dedup: reschedule ida-e-volta re-enfileira os mesmos offsets — só o 1º apita
    return unless Rails.cache.write("ramon:reminder:#{lead_id}:#{start_at_iso}:#{label}", true, unless_exist: true, expires_in: 25.hours)

    hora = start_at.in_time_zone(TIME_ZONE).strftime('%d/%m %H:%M')
    # sino do hub só pra quem faz a reunião — o ntfy é opcional, o hub não
    destinatarios = Ramon::Fluxos::Lembretes.destinatarios(lead)
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_meeting_reminder', user_ids: destinatarios,
                                       meta: { 'quando' => hora, 'label' => label }).perform
    return if ENV.fetch('NTFY_TOPIC', nil).blank?

    # timing já resolvido pelo wait_until — push direto, sem re-enfileirar
    Ramon::NtfyPushJob.perform_now(lead_id, title: "Reunião #{lead.name} em #{label}",
                                            body: "#{hora} — hora de mandar a mensagem de confirmação pro cliente")
  end
end
```

(c) Em `app/services/ramon/reuniao_agendamento.rb`, trocar o bloco do `notify` (linhas 50-58):

```ruby
  # Sino do hub pra todo mundo da conta + push no celular na hora (o job é
  # no-op sem NTFY_TOPIC); os lembretes têm o seu no MeetingReminderJob.
  def self.notify(lead, type, starts_at, title, verbo: nil)
    quando = starts_at ? quando(starts_at) : ''
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: type, meta: { 'quando' => quando }).perform
    verbo ||= type == 'ramon_meeting_cancelled' ? 'cancelada' : 'marcada'
    Ramon::NtfyPushJob.perform_later(lead.id, title: "Reuniao #{verbo}: #{lead.name}", body: "#{quando} — #{title}")
    Ramon::Fluxos::Disparo.externo(type == 'ramon_meeting_cancelled' ? 'reuniao_cancelada' : 'reuniao_marcada', lead, 'quando' => quando)
  end
```

por

```ruby
  # Sino do hub pra todo mundo da conta + push no celular na hora (o job é
  # no-op sem NTFY_TOPIC); os lembretes têm o seu no MeetingReminderJob.
  # 'inicio' (ISO) vai para os fluxos: os lembretes do fluxo contam para trás a partir dele (B4.1).
  def self.notify(lead, type, starts_at, title, verbo: nil)
    quando = starts_at ? quando(starts_at) : ''
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: type, meta: { 'quando' => quando }).perform
    verbo ||= type == 'ramon_meeting_cancelled' ? 'cancelada' : 'marcada'
    Ramon::NtfyPushJob.perform_later(lead.id, title: "Reuniao #{verbo}: #{lead.name}", body: "#{quando} — #{title}")
    gatilho = type == 'ramon_meeting_cancelled' ? 'reuniao_cancelada' : 'reuniao_marcada'
    Ramon::Fluxos::Disparo.externo(gatilho, lead, 'quando' => quando, 'inicio' => starts_at&.iso8601)
  end
```

Rastreio do spec: `starts_at` = `2026-07-15T14:00:00Z` (UTC) → `starts_at.iso8601` = `"2026-07-15T14:00:00Z"` dos dois lados (mesmo objeto); `quando` = `"quarta, 15/07 às 11:00"` (já conferido pelo exemplo do rascunho). Complexidade do `notify`: `?:` ×3 + `||=` + `&.` = 6 ≤ 7.

- [ ] **Step 4: Run to verify it passes**

Run (CI): `bundle exec rspec spec/services/ramon/reuniao_agendamento_spec.rb spec/jobs/ramon/meeting_reminder_job_spec.rb` e `bundle exec rubocop app/services/ramon/fluxos/lembretes.rb app/jobs/ramon/meeting_reminder_job.rb app/services/ramon/reuniao_agendamento.rb`
Expected: PASS (os 8 exemplos do job seguem verdes: tolerância de 60 s, tarefa concluída, remarcada, Closer+SDR, gestores), sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/lembretes.rb app/jobs/ramon/meeting_reminder_job.rb app/services/ramon/reuniao_agendamento.rb spec/services/ramon/reuniao_agendamento_spec.rb
git commit -m "refactor(fluxos): regras dos lembretes de reunião num lugar só e horário ISO no gatilho" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 2: Motor — "esperar antes da reunião" e "a reunião segue de pé"

**Files:**
- Modify: `app/services/ramon/fluxos/contexto.rb:9-11` (`RESERVADAS`), `:26-29` (`dados`), novo método público `reuniao_em`, novos privados `dados_reuniao` e `proxima_reuniao`
- Modify: `app/services/ramon/fluxos/passos/logica.rb:18-25` (`esperar`) + novos `esperar_reuniao`, `duracao`, `hora`
- Test: `spec/services/ramon/fluxos/contexto_spec.rb`, `spec/services/ramon/fluxos/passos_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Fluxos::Lembretes.reuniao_aberta?(lead, inicio)` (Task 1); `contexto['gatilho']['inicio']` ISO (Task 1).
- Produces: `Ramon::Fluxos::Contexto#reuniao_em → Time | nil`; `ctx.dados['reuniao_de_pe'] → 'sim' | 'nao' | nil`; `Passos::Logica.esperar(config, ctx)` com `config['antes_de'] == 'reuniao'` devolve `{saida: 's', resumo:, esperar_ate: Time, vars: {'horario_passou' => 'nao'}}` ou, com o momento já passado, `{saida: 's', resumo:, vars: {'horario_passou' => 'sim'}}` (sem `esperar_ate`); sem reunião → `Ramon::Fluxos::PassoImpossivel`. `Contexto::RESERVADAS` inclui `reuniao_de_pe` e `horario_passou`.

- [ ] **Step 1: Write the failing tests**

(a) `spec/services/ramon/fluxos/contexto_spec.rb`, antes do `end` final:

```ruby
  describe 'reunião (B4.1)' do
    let(:inicio) { 2.days.from_now.change(usec: 0) }

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

(O exemplo existente `'RESERVADAS cobre toda chave que o Contexto monta sozinho'` passa a cobrir `reuniao_de_pe` automaticamente.)

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/contexto_spec.rb spec/services/ramon/fluxos/passos_spec.rb`
Expected: FAIL — `dados['reuniao_de_pe']` é `nil`; `undefined method 'reuniao_em'`; `esperar` com `antes_de` conta para a frente (`esperar_ate` = 20:00, não 14:00) e não devolve `vars`.

- [ ] **Step 3: Implementation**

(a) `app/services/ramon/fluxos/contexto.rb` — trocar `RESERVADAS` (linhas 9-11):

```ruby
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
  # Horário da reunião (B4.1): o 'inicio' que o gatilho reuniao_marcada mandou; sem ele ("Testar com um lead…",
  # Rodar na mão), a próxima reunião aberta do lead.
  def reuniao_em
    return @reuniao_em if defined?(@reuniao_em)

    iso = execucao.contexto.dig('gatilho', 'inicio')
    @reuniao_em = iso.present? ? Time.zone.parse(iso) : proxima_reuniao
  end
```

e, logo depois de `dados_gatilho` (seção `private`), inserir:

```ruby
  # {reuniao_de_pe}: a mesma regra do lembrete do código (Ramon::Fluxos::Lembretes.reuniao_aberta?), na hora do passo.
  # ponytail: 1 consulta por passo em fluxo de lead (a próxima reunião); cachear se virar gargalo.
  def dados_reuniao
    inicio = lead && reuniao_em
    return { 'reuniao_de_pe' => nil } unless inicio

    { 'reuniao_de_pe' => Ramon::Fluxos::Lembretes.reuniao_aberta?(lead, inicio) ? 'sim' : 'nao' }
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

Rastreio: (1) 12:00Z, início 22:00Z, 8 h → `ate` 14:00Z, futuro → `esperar_ate` 14:00Z, `vars` `nao`. (2) 15:00Z → `ate` 14:00Z `past?` → sem `esperar_ate`, `vars` `sim`, resumo "`07/10 11:00 já passou: …`". (3) `ctx` sem gatilho e sem tarefa → `proxima_reuniao` = `nil` → `PassoImpossivel` "sem reunião marcada…" (casa `/reunião/`). O Executor já junta `resultado[:vars]` no contexto antes de esperar (`executor.rb:100`) e, ao retomar, o `se` lê `{horario_passou}` dos `vars`. "Testar com um lead…" (`pular_esperas`) não espera de qualquer jeito.

- [ ] **Step 4: Run to verify they pass**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/contexto_spec.rb spec/services/ramon/fluxos/passos_spec.rb spec/services/ramon/fluxos/executor_spec.rb` e `bundle exec rubocop app/services/ramon/fluxos/contexto.rb app/services/ramon/fluxos/passos/logica.rb`
Expected: PASS (o executor_spec segue verde: `esperar` sem `antes_de` não mudou), sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/contexto.rb app/services/ramon/fluxos/passos/logica.rb spec/services/ramon/fluxos/contexto_spec.rb spec/services/ramon/fluxos/passos_spec.rb
git commit -m "feat(fluxos): esperar até X antes da reunião e condição reunião segue de pé" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 3: Sino "para o Closer e o SDR" + ensaio diz quem receberia

**Files:**
- Modify: `app/services/ramon/fluxos/passos/aviso.rb:5-21` (`avisar_sino`, `destinatarios`) + novo `nomes`
- Test: `spec/services/ramon/fluxos/passos_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Fluxos::Lembretes.destinatarios(lead)` (Task 1).
- Produces: config `avisar_sino {texto, para: 'closer_e_sdr'}` (sem `para`: comportamento de hoje — `user_ids` ou o responsável). Resumo do ensaio: **exatamente** `faria: sino para <nomes em ordem alfabética, separados por ", ">: "<texto até 80>"` (sem ninguém: `faria: sino para ninguém (sem responsável): "…"`). A Task 7 lê esse formato (`CompararLembretes::PESSOAS`).

- [ ] **Step 1: Write the failing tests** — em `spec/services/ramon/fluxos/passos_spec.rb`, depois de `'sino sem responsável não cai em todo mundo'`:

```ruby
  it 'sino para Closer e SDR do lead; sem nenhum dos dois, os administradores (regra do lembrete do código)' do
    closer = create(:user, account: account)
    sdr = create(:user, account: account)
    admin = create(:user, account: account, role: :administrator)
    c = ctx
    c.lead.update!(closer: closer, sdr: sdr)
    Ramon::Fluxos::Passos::Aviso.avisar_sino({ 'texto' => 'Reunião', 'para' => 'closer_e_sdr' }, c)
    expect(Notification.where(notification_type: 'ramon_fluxo_aviso').pluck(:user_id)).to contain_exactly(closer.id, sdr.id)
    c.lead.update!(closer: nil, sdr: nil)
    Ramon::Fluxos::Passos::Aviso.avisar_sino({ 'texto' => 'Reunião', 'para' => 'closer_e_sdr' }, c)
    expect(Notification.where(notification_type: 'ramon_fluxo_aviso').pluck(:user_id)).to contain_exactly(closer.id, sdr.id, admin.id)
  end

  it 'ensaio do sino diz quem receberia, sem gravar nada' do
    ana = create(:user, account: account, name: 'Ana')
    c = ctx(ensaio: true)
    c.lead.update!(closer: ana)
    r = nil
    expect { r = Ramon::Fluxos::Passos::Aviso.avisar_sino({ 'texto' => 'Ver {nome}' }, c) }.not_to change(Notification, :count)
    expect(r[:resumo]).to start_with('faria: sino para Ana: "Ver ')
  end
```

(`c.lead` é o mesmo objeto que o passo lê — `Contexto#lead` memoriza; atualizar o `lead` do `let` deixaria o do contexto velho.)

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/passos_spec.rb`
Expected: FAIL — o 1º avisa só o Closer (`para` é ignorado: `closer || sdr`); o 2º devolve `faria: sino "Ver …"` (sem os nomes).

- [ ] **Step 3: Implementation** — trocar o `avisar_sino` e o `destinatarios` de `app/services/ramon/fluxos/passos/aviso.rb` (linhas 5-21) por:

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
  # para 'closer_e_sdr' = a regra do lembrete de reunião do código (B4.1, Ramon::Fluxos::Lembretes.destinatarios).
  def destinatarios(lead, config)
    ids = if config['para'] == 'closer_e_sdr' then Ramon::Fluxos::Lembretes.destinatarios(lead)
          else Array(config['user_ids']).map(&:to_i).presence || [(lead.closer || lead.sdr)&.id]
          end
    ids.compact & lead.account.account_users.pluck(:user_id)
  end

  # Ordem alfabética: a comparação da B4.1 (Ramon::Fluxos::CompararLembretes::PESSOAS) lê este texto.
  def nomes(ids) = User.where(id: ids).order(:name).pluck(:name).join(', ').presence || 'ninguém (sem responsável)'
```

Rastreio: (1) `para` → `[closer.id, sdr.id]` ∩ usuários da conta → 2 avisos; sem Closer/SDR → `[admin.id]` → total `closer, sdr, admin`. (2) ensaio → `ids = [ana.id]` → `faria: sino para Ana: "Ver Maria…"` sem criar `Notification`. O exemplo antigo `'sino sem responsável não cai em todo mundo'` (não-ensaio, sem ninguém) continua `sino: sem responsável`.

- [ ] **Step 4: Run to verify they pass**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/passos_spec.rb` e `bundle exec rubocop app/services/ramon/fluxos/passos/aviso.rb`
Expected: PASS, sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/passos/aviso.rb spec/services/ramon/fluxos/passos_spec.rb
git commit -m "feat(fluxos): sino para o Closer e o SDR do lead e ensaio que diz quem receberia" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 4: Remarcar recomeça o fluxo + desligar vale também para a sombra

**Files:**
- Modify: `app/services/ramon/fluxos/disparo.rb:6` (constante), `:61-71` (`iniciar`), seção `private` (novo `recomecar`)
- Modify: `app/services/ramon/fluxos/executor.rb:69` (`desligado?`)
- Test: `spec/services/ramon/fluxos/disparo_spec.rb`, `spec/services/ramon/fluxos/executor_spec.rb`

**Interfaces:**
- Produces: `Ramon::Fluxos::Disparo::RECOMECA = %w[reuniao_marcada]`. Um disparo (evento, não ensaio do botão) de fluxo com gatilho em `RECOMECA` cancela antes, sob lock, as execuções `esperando` do mesmo fluxo+alvo (ensaio ou não), com a linha de trilha `{'no' => 'cancelado', 'tipo' => 'cancelado', 'resumo' => 'cancelado: a reunião foi remarcada', …}`. `Executor`: execução **sem** `contexto['pular_esperas']` (normal **e** sombra) é cancelada ao retomar se o fluxo foi desligado; o "Testar com um lead…" (`pular_esperas`) nunca.

- [ ] **Step 1: Write the failing tests**

(a) `spec/services/ramon/fluxos/disparo_spec.rb`, depois de `'modo sombra cria execução de ensaio'`:

```ruby
  it 'remarcar recomeça: a execução que esperava a reunião antiga é cancelada e nasce outra (normal e sombra)' do
    espera = ['esperar', { 'quantidade' => 1, 'unidade' => 'dias' }]
    normal = fluxo_publicado(account, grafo_linear({ 'tipo' => 'reuniao_marcada' }, espera))
    sombra = fluxo_publicado(account, grafo_linear({ 'tipo' => 'reuniao_marcada' }, espera), modo: 'sombra')
    2.times { described_class.call('reuniao_marcada', lead, { 'inicio' => 1.day.from_now.iso8601 }) }
    expect(normal.execucoes.order(:id).pluck(:status)).to eq(%w[cancelada esperando])
    expect(sombra.execucoes.order(:id).pluck(:status)).to eq(%w[cancelada esperando])
    expect(normal.execucoes.order(:id).first.trilha.last['resumo']).to eq('cancelado: a reunião foi remarcada')
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
```

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/disparo_spec.rb spec/services/ramon/fluxos/executor_spec.rb`
Expected: FAIL — (a) normal fica `['esperando']` (o 2º disparo bate no índice único e é ignorado) e sombra fica `['esperando','esperando']`; (b) a sombra desligada termina `concluida` (`desligado?` ignora ensaio). O exemplo do "Testar…" já passa e fica como trava.

- [ ] **Step 3: Implementation**

(a) `app/services/ramon/fluxos/disparo.rb` — depois de `PROFUNDIDADE_MAX = 3` (linha 6):

```ruby
  # Remarcar = recomeçar (B4.1): o novo disparo cancela a espera da reunião antiga e conta da nova.
  RECOMECA = %w[reuniao_marcada].freeze
```

no `iniciar` (linhas 61-71), trocar

```ruby
    return if @fluxo.origem == 'sistema' # D7: desenho só-leitura; quem roda é o código de hoje

    execucao = @fluxo.execucoes.create!(atributos)
```

por

```ruby
    return if @fluxo.origem == 'sistema' # D7: desenho só-leitura; quem roda é o código de hoje

    recomecar if RECOMECA.include?(@fluxo.gatilho_tipo) && @ensaio.nil?
    execucao = @fluxo.execucoes.create!(atributos)
```

e, na seção `private`, antes de `def atributos`:

```ruby
  # Sem isto, em modo normal o índice único barraria a execução nova e os lembretes seguiriam o horário antigo.
  # ponytail: só 'esperando' — uma execução 'rodando' (milissegundos entre passos) ainda barra a nova; e um lead
  # com 2 reuniões abertas ao mesmo tempo fica com a última marcada (Decisão E3 do plano B4.1).
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

(b) `app/services/ramon/fluxos/executor.rb:69` — trocar

```ruby
  def desligado? = !@execucao.ensaio && !@execucao.fluxo&.ativo
```

por

```ruby
  # Vale para execução normal e para a sombra (B4.1: desligar é como se para a sombra); o "Testar com um lead…"
  # (pular_esperas) roda até com o fluxo desligado.
  def desligado? = !@execucao.contexto['pular_esperas'] && !@execucao.fluxo&.ativo
```

Rastreio (a): 1º `call` → cada fluxo cria uma execução `esperando` (nasce assim, `retomar_em` agora; o job só foi enfileirado). 2º `call` → `recomecar` acha a `esperando`, trava, cancela com a linha; `create!` passa (a antiga já não está viva) → `[cancelada, esperando]` nos dois. `with_lock` recarrega a linha (mesmo padrão do `Executor#reivindicar`). Gatilhos fora de `RECOMECA` (o exemplo `'rajada no mesmo alvo vira uma execução só'`) não mudam.

- [ ] **Step 4: Run to verify they pass**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/` e `bundle exec rubocop app/services/ramon/fluxos/disparo.rb app/services/ramon/fluxos/executor.rb`
Expected: PASS (inclusive o antigo `'fluxo desligado durante a espera → cancelada'`), sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/disparo.rb app/services/ramon/fluxos/executor.rb spec/services/ramon/fluxos/disparo_spec.rb spec/services/ramon/fluxos/executor_spec.rb
git commit -m "feat(fluxos): reunião remarcada recomeça o fluxo e desligar também para a sombra" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 5: O fluxo "Lembretes de reunião" em sombra — desenho fiel + rake que o cria

**Files:**
- Create: `db/seeds/ramon/fluxos/migrados/lembretes_reuniao.json`
- Modify: `app/services/ramon/fluxos/lembretes.rb` (+ `DESENHO`, `fluxo`, `semear`, `criar`)
- Create: `lib/tasks/ramon_fluxos.rake`
- Test: `spec/services/ramon/fluxos/lembretes_spec.rb` (novo); `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/migrados.spec.js` (novo)

**Interfaces:**
- Consumes: Tasks 1–4 (`antes_de`, `reuniao_de_pe`, `horario_passou`, `para: 'closer_e_sdr'`, `RECOMECA`).
- Produces: `Ramon::Fluxos::Lembretes.fluxo(account) → Fluxo | nil` (origem `usuario`, `sistema_chave: 'lembretes_reuniao'`); `Ramon::Fluxos::Lembretes.semear(account) → Fluxo` (idempotente: existindo, devolve sem tocar). Rake `ramon:fluxos:lembretes:sombra[account_id]`. Ids dos passos do desenho: `n1` gatilho; para cada lembrete k=0..4 (24h, 8h, 1h, 30min, 5min): `n(2+4k)` esperar, `n(3+4k)` se, `n(4+4k)` sino, `n(5+4k)` push.

- [ ] **Step 1: Write the failing tests**

(a) `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/migrados.spec.js`:

```js
// Fluxos que substituem automações do código (B4+, db/seeds/ramon/fluxos/migrados/*.json):
// o quadro abre e publica cada um (validação = espelho do Grafo) e o desenho é fiel ao código.
import { validar } from '../validar';
import lembretes from '../../../../../../../../db/seeds/ramon/fluxos/migrados/lembretes_reuniao.json';

describe('fluxo migrado: lembretes de reunião (B4.1)', () => {
  const { nos, setas } = lembretes.desenho;
  const doTipo = tipo => nos.filter(n => n.tipo === tipo);

  it('publica sem erro', () => {
    expect(validar(lembretes.desenho)).toEqual([]);
  });

  it('reunião marcada, sem cancelar quando o lead muda de etapa (o código não cancela)', () => {
    expect(nos[0].config).toEqual({
      tipo: 'reuniao_marcada',
      cancelar_se_sair_da_etapa: false,
    });
  });

  it('os 5 lembretes do código: 24h, 8h, 1h, 30 min e 5 min antes da reunião', () => {
    expect(
      doTipo('esperar').map(n => [
        n.config.antes_de,
        n.config.quantidade,
        n.config.unidade,
      ])
    ).toEqual([
      ['reuniao', 24, 'horas'],
      ['reuniao', 8, 'horas'],
      ['reuniao', 1, 'horas'],
      ['reuniao', 30, 'minutos'],
      ['reuniao', 5, 'minutos'],
    ]);
  });

  it('cada lembrete só sai com a reunião de pé e no horário, para o Closer e o SDR; o "não" pula para o próximo', () => {
    doTipo('se').forEach(n =>
      expect(n.config.condicoes).toEqual([
        { campo: 'reuniao_de_pe', operador: 'igual', valor: 'sim' },
        { campo: 'horario_passou', operador: 'igual', valor: 'nao' },
      ])
    );
    doTipo('avisar_sino').forEach(n =>
      expect(n.config.para).toBe('closer_e_sdr')
    );
    const esperas = doTipo('esperar').map(n => n.id);
    const naos = setas.filter(s => s.saida === 'nao').map(s => s.para);
    expect(naos).toEqual(esperas.slice(1));
  });

  it('não fala com o cliente (só espera, condição, sino e push)', () => {
    expect([...new Set(nos.map(n => n.tipo))].sort()).toEqual([
      'avisar_push',
      'avisar_sino',
      'esperar',
      'gatilho',
      'se',
    ]);
  });
});
```

(b) `spec/services/ramon/fluxos/lembretes_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Lembretes do
  # A conta seeda o funil no after_create (Leads::SeedDefaultConfigService).
  let(:account) { create(:account) }
  let(:closer) { create(:user, account: account, name: 'Carla Closer') }
  let(:lead) do
    create(:lead, account: account, lead_stage: account.lead_stages.order(:position).first, closer: closer, name: 'João Pereira')
  end
  let(:inicio) { Time.zone.parse('2026-10-07T22:00:00Z') }

  # O relógio dos fluxos (Ramon::FluxoRelogioJob) sem o resto: anda o que venceu.
  def relogio
    FluxoExecucao.where(status: 'esperando', retomar_em: ..Time.current).find_each { |e| Ramon::Fluxos::Executor.new(e).avancar! }
  end

  def sinos(fluxo)
    FluxoExecucao.where(fluxo: fluxo).order(:id).flat_map(&:trilha).select { |t| t['tipo'] == 'avisar_sino' }.pluck('resumo')
  end

  def agendar(starts_at = inicio)
    Ramon::ReuniaoAgendamento.call(lead: lead, starts_at: starts_at, title: 'Primeiro Atendimento')
  end

  describe '.semear' do
    it 'cria o fluxo em sombra, ligado e publicado, uma vez só, sem pisar na edição do Eduardo' do
      fluxo = described_class.semear(account)
      expect(fluxo).to have_attributes(origem: 'usuario', sistema_chave: 'lembretes_reuniao', modo: 'sombra', ativo: true,
                                       gatilho_tipo: 'reuniao_marcada')
      expect(fluxo.versao_publicada).to be_present
      fluxo.update!(nome: 'Meus lembretes')
      expect(described_class.semear(account)).to eq(fluxo)
      expect(account.fluxos.where(origem: 'usuario', sistema_chave: 'lembretes_reuniao').count).to eq(1)
      expect(fluxo.reload.nome).to eq('Meus lembretes')
    end
  end

  describe 'o fluxo em sombra, de ponta a ponta' do
    let!(:fluxo) { described_class.semear(account) }

    it 'reunião daqui a 10h: ensaia os 4 lembretes que o código manda (8h, 1h, 30 min, 5 min) e não avisa ninguém' do
      travel_to(inicio - 10.hours) do
        expect { agendar }.to have_enqueued_job(Ramon::MeetingReminderJob).exactly(4).times
        relogio
      end
      [8.hours, 1.hour, 30.minutes, 5.minutes].each { |antes| travel_to(inicio - antes + 30.seconds) { relogio } }

      expect(sinos(fluxo).size).to eq(4)
      expect(sinos(fluxo)).to all(start_with('faria: sino para Carla Closer: "Reunião em '))
      expect(sinos(fluxo).first).to include('8h antes')
      expect(Notification.where(notification_type: 'ramon_fluxo_aviso')).to be_empty
      expect(FluxoExecucao.where(fluxo: fluxo).pluck(:status)).to eq(['concluida'])
    end

    it 'remarcar recomeça pelo horário novo e o lembrete do horário antigo nunca sai' do
      travel_to(inicio - 10.hours) do
        agendar
        relogio
        Ramon::ReuniaoAgendamento.remarcar(task: lead.lead_tasks.find_by!(kind: 'meeting'), starts_at: inicio + 1.day)
        relogio
      end
      travel_to(inicio - 8.hours + 30.seconds) { relogio }

      execucoes = FluxoExecucao.where(fluxo: fluxo).order(:id)
      expect(execucoes.pluck(:status)).to eq(%w[cancelada esperando])
      expect(execucoes.last.retomar_em).to eq(inicio) # 24h antes da reunião nova
      expect(sinos(fluxo)).to be_empty
    end

    it 'reunião cancelada: os lembretes seguintes não saem' do
      travel_to(inicio - 10.hours) do
        agendar
        relogio
        Ramon::ReuniaoAgendamento.cancelar(task: lead.lead_tasks.find_by!(kind: 'meeting'))
      end
      [8.hours, 1.hour, 30.minutes, 5.minutes].each { |antes| travel_to(inicio - antes + 30.seconds) { relogio } }

      expect(sinos(fluxo)).to be_empty
      expect(FluxoExecucao.where(fluxo: fluxo).pluck(:status)).to eq(['concluida'])
    end

    it 'lead que muda de etapa antes da reunião continua lembrado (como o código)' do
      travel_to(inicio - 10.hours) do
        agendar
        relogio
        lead.update!(lead_stage: account.lead_stages.find_by!(label: 'fase-negociacao'))
      end
      travel_to(inicio - 8.hours + 30.seconds) { relogio }

      expect(sinos(fluxo).size).to eq(1)
    end
  end
end
```

Rastreio do 1º de ponta a ponta (início 22:00Z, agora 12:00Z): `agendar` → `enqueue_reminders` agenda 8h/1h/30min/5min (24h já passou) = 4 jobs; `notify` → `Disparo.externo('reuniao_marcada', lead, quando, inicio)` → fluxo em sombra → `recomecar` (nada) → execução `ensaio: true`, `esperando`, vencida. `relogio` (12:00) → `n2` 24h antes = 22:00Z de ontem, passado → `horario_passou=sim` → `n3` se: `reuniao_de_pe=sim` E `horario_passou=nao` falha → `nao` → `n6` esperar 8h → 14:00Z, espera. 14:00:30 → `n7` sim → `n8` `faria: sino para Carla Closer: "Reunião em 8h antes (quarta, 07/10 às 19:00) — hora de con…"` → `n9` `faria: push` → `n10` 1h → 21:00Z. 21:00:30 → sino 1h → 21:30Z. 21:30:30 → sino 30min → 21:55Z. 21:55:30 → sino 5min → push → sem seta → `concluida`. 4 sinos, nenhum `Notification` de fluxo (ensaio). `cancelar_se_sair_da_etapa: false` → a mudança de etapa do `advance_stage` (e a do 4º exemplo) não cancela. Cancelada: `cancelar` apaga a tarefa → cada `se` dá `nao` → a última (`n19`) não tem seta no `nao` → `concluida`.

- [ ] **Step 2: Run to verify they fail**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/migrados.spec.js --config vitest.local.config.ts`
Expected: FAIL — `Failed to resolve import …/migrados/lembretes_reuniao.json`.
Run (CI): `bundle exec rspec spec/services/ramon/fluxos/lembretes_spec.rb`
Expected: FAIL — `undefined method 'semear' for module Ramon::Fluxos::Lembretes`.

- [ ] **Step 3: Implementation**

(a) Criar `db/seeds/ramon/fluxos/migrados/lembretes_reuniao.json` (UTF-8, exatamente):

```json
{
  "nome": "Lembretes de reunião",
  "descricao": "Os 5 lembretes de reunião do Closer e do SDR (24h, 8h, 1h, 30 min e 5 min antes), no lugar do código (B4.1). Enquanto o selo disser \"em sombra\", ele só ensaia nas reuniões de verdade: quem avisa ainda é o código. Remarcar recomeça pelo horário novo; reunião cancelada ou concluída para os lembretes.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"reuniao_marcada","cancelar_se_sair_da_etapa":false},"posicao":{"x":0,"y":0}},
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

Os textos internos copiam o código: o rótulo do lembrete é o `label` do `MeetingReminderJob::OFFSETS` ("24h antes"…), o sino segue o `ramon_meeting_reminder` ("… — hora de confirmar com o cliente", `config/locales/pt_BR.yml:232`) e o push é literal do job (título "Reunião <nome> em <label>", corpo "<hora> — hora de mandar a mensagem de confirmação pro cliente"). Diferenças que sobram (formato do horário, prefixo "Automação:" do sino de fluxo, nome do contato no push) estão na Decisão E2.

(b) `app/services/ramon/fluxos/lembretes.rb` — depois de `TOLERANCIA = 60.seconds`:

```ruby
  DESENHO = Rails.root.join('db/seeds/ramon/fluxos/migrados/lembretes_reuniao.json')
```

e, antes do `end` final do módulo:

```ruby
  # O fluxo que substitui o código (spec §14: fluxo próprio, origem 'usuario' — o motor recusa 'sistema').
  def fluxo(account) = account.fluxos.where(origem: 'usuario', sistema_chave: CHAVE).order(:id).first

  # Cria uma vez, em sombra, ligado e publicado. Já existe → devolve sem tocar (o Eduardo pode ter editado).
  def semear(account) = fluxo(account) || criar(account)

  def criar(account)
    dados = JSON.parse(DESENHO.read)
    Fluxo.transaction do
      novo = account.fluxos.create!(nome: dados['nome'], descricao: dados['descricao'], origem: 'usuario', sistema_chave: CHAVE,
                                    modo: 'sombra', ativo: true, rascunho: dados['desenho'])
      novo.publicar!(nil)
      novo.reload
    end
  end
```

(c) Criar `lib/tasks/ramon_fluxos.rake`:

```ruby
# frozen_string_literal: true

# B4.1 — lembretes de reunião em sombra (spec §8 e §15).
# Operação: docs/superpowers/plans/2026-10-06-automacoes-fluxo-b4-lembretes.md (seção "Operação depois do deploy").
namespace :ramon do
  namespace :fluxos do
    namespace :lembretes do
      conta = ->(args) { Account.find(args[:account_id].presence || raise(ArgumentError, 'informe o account_id')) }

      desc 'Cria (uma vez) o fluxo Lembretes de reuniao em SOMBRA. Uso: rake ramon:fluxos:lembretes:sombra[account_id]'
      task :sombra, [:account_id] => :environment do |_task, args|
        fluxo = Ramon::Fluxos::Lembretes.semear(conta.call(args))
        puts "Fluxo ##{fluxo.id} \"#{fluxo.nome}\" — modo #{fluxo.modo}, #{fluxo.ativo ? 'ligado' : 'desligado'}, " \
             "versão #{fluxo.versao_publicada&.numero}"
      end
    end
  end
end
```

- [ ] **Step 4: Run to verify they pass**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts`
Expected: PASS — **15 arquivos / 168 testes** (163 + 5).
Run (CI): `bundle exec rspec spec/services/ramon/fluxos/lembretes_spec.rb spec/jobs/ramon/meeting_reminder_job_spec.rb spec/services/ramon/reuniao_agendamento_spec.rb` e `bundle exec rubocop app/services/ramon/fluxos/lembretes.rb lib/tasks/ramon_fluxos.rake`
Expected: PASS, sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add db/seeds/ramon/fluxos/migrados/lembretes_reuniao.json app/services/ramon/fluxos/lembretes.rb lib/tasks/ramon_fluxos.rake spec/services/ramon/fluxos/lembretes_spec.rb app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/migrados.spec.js
git commit -m "feat(fluxos): fluxo Lembretes de reunião em sombra e rake que o cria" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 6: A chave — `RAMON_FLUXO_LEMBRETES=on` + fluxo em modo normal

**Files:**
- Modify: `app/services/ramon/fluxos/lembretes.rb` (+ `ligada?`, `assumiu?`, `mudar_modo!`, `descrever`)
- Modify: `app/services/ramon/reuniao_agendamento.rb:116-125` (`enqueue_reminders`)
- Modify: `lib/tasks/ramon_fluxos.rake` (+ task `modo`)
- Modify: `.env.example` (depois do bloco `RAMON_COPILOTO_MODO_DEFAULT`)
- Test: `spec/services/ramon/fluxos/lembretes_spec.rb`

**Interfaces:**
- Consumes: `Lembretes.fluxo/semear` (Task 5).
- Produces: `Ramon::Fluxos::Lembretes.ligada? → Boolean` (`ENV['RAMON_FLUXO_LEMBRETES'] == 'on'`); `.assumiu?(account) → Boolean` (env ligada **e** fluxo `executaveis` com `sistema_chave: 'lembretes_reuniao'`, `modo: 'normal'`, `gatilho_tipo: 'reuniao_marcada'`); `.mudar_modo!(account, 'normal'|'sombra') → Fluxo` (`ArgumentError` sem fluxo ou em `normal` sem a env; `ActiveRecord::RecordInvalid` com modo inválido); `.descrever(fluxo) → String`. **O único ponto que a chave desliga:** `Ramon::ReuniaoAgendamento#enqueue_reminders` (chamado por `#call` — painel e Cal.com created/rescheduled — e por `#remarcar`). O `MeetingReminderJob` não consulta a chave (os já enfileirados antes da virada saem normalmente).

- [ ] **Step 1: Write the failing tests** — em `spec/services/ramon/fluxos/lembretes_spec.rb`, antes do `end` final:

```ruby
  describe 'a chave (RAMON_FLUXO_LEMBRETES=on + fluxo em modo normal)' do
    let!(:fluxo) { described_class.semear(account) }

    it 'só assume com a env ligada E o fluxo normal, ligado e publicado' do
      with_modified_env(RAMON_FLUXO_LEMBRETES: 'on') do
        expect(described_class.assumiu?(account)).to be(false) # ainda em sombra
        described_class.mudar_modo!(account, 'normal')
        expect(described_class.assumiu?(account)).to be(true)
      end
      expect(described_class.assumiu?(account)).to be(false) # sem a env
      with_modified_env(RAMON_FLUXO_LEMBRETES: 'on') do
        fluxo.update!(ativo: false)
        expect(described_class.assumiu?(account)).to be(false) # desligado na tela
      end
    end

    it 'virar para normal sem a env ligada é recusado (código e fluxo lembrariam em dobro)' do
      expect { described_class.mudar_modo!(account, 'normal') }.to raise_error(ArgumentError, /RAMON_FLUXO_LEMBRETES/)
      expect(fluxo.reload.modo).to eq('sombra')
    end

    it 'assumido: o código não agenda e o fluxo avisa de verdade o Closer' do
      with_modified_env(RAMON_FLUXO_LEMBRETES: 'on') do
        described_class.mudar_modo!(account, 'normal')
        travel_to(inicio - 10.hours) do
          expect { agendar }.not_to have_enqueued_job(Ramon::MeetingReminderJob)
          relogio
        end
        travel_to(inicio - 8.hours + 30.seconds) { relogio }
      end
      aviso = closer.notifications.find_by!(notification_type: 'ramon_fluxo_aviso')
      expect(aviso.meta['label']).to start_with('Reunião em 8h antes')
    end

    it 'voltar para sombra devolve os lembretes ao código na hora' do
      with_modified_env(RAMON_FLUXO_LEMBRETES: 'on') do
        described_class.mudar_modo!(account, 'normal')
        described_class.mudar_modo!(account, 'sombra')
        travel_to(inicio - 10.hours) { expect { agendar }.to have_enqueued_job(Ramon::MeetingReminderJob).exactly(4).times }
      end
    end
  end
```

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/lembretes_spec.rb`
Expected: FAIL — `undefined method 'assumiu?'` / `'mudar_modo!'`.

- [ ] **Step 3: Implementation**

(a) `app/services/ramon/fluxos/lembretes.rb`, antes do `end` final:

```ruby
  # A chave (B4.1): o código só para de agendar com a env ligada E o fluxo normal, ligado e publicado.
  # Env ligada com o fluxo em sombra/desligado → o código segue (nunca fica sem lembrete).
  def ligada? = ENV.fetch('RAMON_FLUXO_LEMBRETES', nil) == 'on'

  def assumiu?(account)
    ligada? && account.fluxos.executaveis.exists?(sistema_chave: CHAVE, modo: 'normal', gatilho_tipo: 'reuniao_marcada')
  end

  # normal = o fluxo assume; sombra = devolve ao código na hora (quem já esperava no fluxo normal termina por ele).
  def mudar_modo!(account, modo)
    alvo = fluxo(account) || raise(ArgumentError, 'O fluxo dos lembretes ainda não existe: rode ramon:fluxos:lembretes:sombra')
    raise ArgumentError, 'Ligue RAMON_FLUXO_LEMBRETES=on antes: sem ela código e fluxo lembrariam em dobro' if modo == 'normal' && !ligada?

    alvo.update!(modo: modo)
    alvo
  end

  def descrever(alvo)
    quem = assumiu?(alvo.account) ? 'o FLUXO manda os lembretes (o código não agenda mais)' : 'o CÓDIGO manda os lembretes'
    "Fluxo ##{alvo.id} \"#{alvo.nome}\" — modo #{alvo.modo}, #{alvo.ativo ? 'ligado' : 'desligado'}. Agora #{quem}."
  end
```

(b) `app/services/ramon/reuniao_agendamento.rb` — trocar

```ruby
  # Lembretes anti no-show: só offsets ainda no futuro; cancel/reschedule não
  # desagenda — o guard do job mata o lembrete órfão.
  def enqueue_reminders
    Ramon::MeetingReminderJob::OFFSETS.each do |offset, label|
```

por

```ruby
  # Lembretes anti no-show: só offsets ainda no futuro; cancel/reschedule não
  # desagenda — o guard do job mata o lembrete órfão. Com o fluxo "Lembretes de reunião"
  # no comando (B4.1: RAMON_FLUXO_LEMBRETES=on + fluxo normal) quem lembra é o fluxo.
  def enqueue_reminders
    return if Ramon::Fluxos::Lembretes.assumiu?(@lead.account)

    Ramon::MeetingReminderJob::OFFSETS.each do |offset, label|
```

(c) `lib/tasks/ramon_fluxos.rake` — dentro de `namespace :lembretes`, depois da task `:sombra`:

```ruby

      desc 'normal = o fluxo assume os lembretes (exige RAMON_FLUXO_LEMBRETES=on); sombra = devolve ao codigo. ' \
           'Uso: rake ramon:fluxos:lembretes:modo[account_id,normal]'
      task :modo, [:account_id, :modo] => :environment do |_task, args|
        puts Ramon::Fluxos::Lembretes.descrever(Ramon::Fluxos::Lembretes.mudar_modo!(conta.call(args), args[:modo]))
      end
```

(d) `.env.example` — depois das 2 linhas do `RAMON_COPILOTO_MODO_DEFAULT`:

```
# ramon: lembretes de reuniao pelo fluxo (B4.1). on + fluxo "Lembretes de reuniao" em modo normal = o fluxo lembra e o
# codigo para de agendar. Padrao desligado (o codigo lembra). Virar/voltar: rake ramon:fluxos:lembretes:modo[conta,normal|sombra]
# RAMON_FLUXO_LEMBRETES=off
```

Rastreio do "assumido": `mudar_modo!` (env on) → `normal`. `agendar` → `enqueue_reminders` → `assumiu?` = true → nenhum job. `notify` → execução **não-ensaio** (índice único vale; não há outra viva). 12:00 → espera até 14:00. 14:00:30 → `n8` sino real → `LeadNotificationBuilder` para `[closer.id]` com `meta['label']` = "Reunião em 8h antes (quarta, 07/10 às 19:00) — hora de confirmar com o cliente"; `EventoInline.registrar(nil, …)` volta cedo (lead sem conversa). "Voltar para sombra": `assumiu?` false → 4 jobs.

- [ ] **Step 4: Run to verify they pass**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/lembretes_spec.rb spec/services/ramon/reuniao_agendamento_spec.rb` e `bundle exec rubocop app/services/ramon/fluxos/lembretes.rb app/services/ramon/reuniao_agendamento.rb lib/tasks/ramon_fluxos.rake`
Expected: PASS (o `reuniao_agendamento_spec` roda sem a env: `'enfileira só os lembretes internos ainda futuros'` e o de remarcar seguem 3 e 5 jobs), sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/lembretes.rb app/services/ramon/reuniao_agendamento.rb lib/tasks/ramon_fluxos.rake .env.example spec/services/ramon/fluxos/lembretes_spec.rb
git commit -m "feat(fluxos): chave RAMON_FLUXO_LEMBRETES para o fluxo assumir os lembretes (desligada)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 7: Comparação código × sombra (só leitura) + rake

**Files:**
- Create: `app/services/ramon/fluxos/comparar_lembretes.rb`
- Modify: `lib/tasks/ramon_fluxos.rake` (+ task `comparar`)
- Test: `spec/services/ramon/fluxos/comparar_lembretes_spec.rb` (novo)

**Interfaces:**
- Consumes: `Lembretes.fluxo(account)` (Task 5); formato do resumo do ensaio do sino (Task 3).
- Produces: `Ramon::Fluxos::CompararLembretes.new(account, dias: 1, ate: Time.current)`; `#linhas → Array<{situacao: 'igual'|'so_codigo'|'so_fluxo'|'pessoas', em: Time, lead_id:, lead: String, codigo: Hash|nil, fluxo: Hash|nil}>` em ordem de horário; `#bateu? → Boolean` (há linha e todas `igual`); `#relatorio → String`; `#de`, `#ate`. Rake `ramon:fluxos:lembretes:comparar[account_id,dias]`.

- [ ] **Step 1: Write the failing test** — `spec/services/ramon/fluxos/comparar_lembretes_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::CompararLembretes do
  let(:account) { create(:account) }
  let(:closer) { create(:user, account: account, name: 'Carla Closer') }
  let(:sdr) { create(:user, account: account, name: 'Sérgio SDR') }
  let(:lead) { create(:lead, account: account, closer: closer, name: 'João Pereira') }
  let(:agora) { Time.zone.parse('2026-10-07T14:00:00Z') }

  before do
    travel_to(agora - 1.day) { Ramon::Fluxos::Lembretes.semear(account) }
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

  # O que a sombra grava: a linha "faria: sino para …" na trilha (execuções concluídas: fora do índice único).
  def fluxo_ensaiou(em, pessoas, contexto: {})
    resumo = "faria: sino para #{pessoas.map(&:name).sort.join(', ')}: \"Reunião em 8h antes\""
    linha = { 'no' => 'n8', 'tipo' => 'avisar_sino', 'em' => em.iso8601, 'saida' => 's', 'resumo' => resumo, 'erro' => false }
    travel_to(em) do
      Ramon::Fluxos::Lembretes.fluxo(account).execucoes.create!(account: account, alvo: lead, ensaio: true, status: 'concluida',
                                                                contexto: contexto, trilha: [linha])
    end
  end

  def comparar = described_class.new(account, dias: 2, ate: agora + 6.hours)

  it 'mesmo lead e mesmas pessoas, até 3 min de diferença: igual e BATEU' do
    codigo_avisou(agora, [closer])
    fluxo_ensaiou(agora + 50.seconds, [closer])
    c = comparar
    expect(c.linhas.pluck(:situacao)).to eq(['igual'])
    expect(c.relatorio).to include('Resultado: BATEU', 'João Pereira', '8h antes', 'código: Carla Closer · fluxo: Carla Closer')
  end

  it 'pessoas diferentes, só no código e só no fluxo aparecem e não batem' do
    codigo_avisou(agora, [closer, sdr])
    fluxo_ensaiou(agora + 1.minute, [closer])
    codigo_avisou(agora + 2.hours, [closer], rotulo: '1h antes')
    fluxo_ensaiou(agora + 5.hours, [closer])
    c = comparar
    expect(c.linhas.pluck(:situacao)).to eq(%w[pessoas so_codigo so_fluxo])
    expect(c.bateu?).to be(false)
    expect(c.relatorio).to include('Resultado: NÃO BATEU', 'código: Carla Closer, Sérgio SDR · fluxo: Carla Closer')
  end

  it 'deixa de fora o "Testar com um lead…" e a reunião marcada antes da sombra existir' do
    antigo = travel_to(agora - 3.days) { create(:lead, account: account, name: 'Antigo') }
    codigo_avisou(agora, [closer], alvo: antigo)
    fluxo_ensaiou(agora, [closer], contexto: { 'pular_esperas' => true })
    c = comparar
    expect(c.linhas).to eq([])
    expect(c.relatorio).to include('nada para comparar')
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

Rastreio: o fluxo nasce em `agora - 1 dia`; a atividade de reunião em `agora - 2h` põe o `lead` no escopo; `de = max(agora + 6h - 2 dias, agora - 1 dia, corte)`. Ex. 4: o Closer tem exatamente 2 avisos (≥ teto 2) → `corte` = o mais antigo dele (`agora - 3h`) → a execução de `agora - 5h` (`updated_at` < `de`) sai; sobram 2 pares `igual`. Ex. 3: `antigo` não tem atividade depois da sombra (fora do escopo); a execução com `pular_esperas` é ignorada. Nenhum aviso automático é criado pela factory de lead (só os controllers chamam o `LeadNotificationBuilder` de lead novo), então os avisos do Closer são só os do spec.

- [ ] **Step 2: Run to verify it fails**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/comparar_lembretes_spec.rb`
Expected: FAIL — `uninitialized constant Ramon::Fluxos::CompararLembretes`.

- [ ] **Step 3: Implementation**

(a) Criar `app/services/ramon/fluxos/comparar_lembretes.rb`:

```ruby
# B4.1 (spec §8, passo 2): lembrete a lembrete, o que o código mandou (sino ramon_meeting_reminder) ao lado do que
# o fluxo em sombra diz que mandaria (linhas "faria: sino para …" da trilha). Só leitura.
# Casa pelo lead e pelo horário (até 3 min: o relógio dos fluxos anda de minuto em minuto, o Sidekiq no segundo).
class Ramon::Fluxos::CompararLembretes
  JANELA = 3.minutes
  REUNIAO = %w[meeting_scheduled meeting_rescheduled].freeze
  # ponytail: lê o resumo do ensaio de Passos::Aviso#avisar_sino; mudou lá, muda aqui (os specs dos dois pegam)
  PESSOAS = /\Afaria: sino para (.*?): "/
  ROTULOS = { 'igual' => 'igual', 'so_codigo' => 'só no código', 'so_fluxo' => 'só no fluxo',
              'pessoas' => 'pessoas diferentes' }.freeze

  attr_reader :de, :ate

  def initialize(account, dias: 1, ate: Time.current)
    @account = account
    @fluxo = Ramon::Fluxos::Lembretes.fluxo(account) || raise(ArgumentError, 'O fluxo dos lembretes ainda não existe')
    @ate = ate
    @de = [ate - dias.days, @fluxo.created_at, corte_do_sino].compact.max
  end

  def linhas
    @linhas ||= begin
      sobra = do_fluxo
      casadas = do_codigo.map { |codigo| casar(codigo, sobra) }
      (casadas + sobra.map { |fluxo| linha('so_fluxo', fluxo, nil, fluxo) }).sort_by { |item| item[:em] }
    end
  end

  def bateu? = linhas.any? && linhas.all? { |item| item[:situacao] == 'igual' }

  def relatorio = [cabecalho, *linhas.map { |item| texto(item) }, '', total, resultado].join("\n")

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

  # Só reuniões marcadas/remarcadas depois que a sombra nasceu: as de antes não têm execução para comparar.
  def leads_em_sombra
    @account.lead_activities.where(kind: REUNIAO, created_at: @fluxo.created_at..).distinct.pluck(:lead_id)
  end

  # O ensaio: as linhas "faria: sino para …" das execuções em sombra ("Testar com um lead…" fica de fora).
  def do_fluxo
    @fluxo.execucoes.where(ensaio: true, alvo_type: 'Lead', updated_at: de..).includes(:alvo).flat_map do |execucao|
      execucao.contexto['pular_esperas'] ? [] : execucao.trilha.filter_map { |t| do_trilha(execucao, t) }
    end
  end

  def do_trilha(execucao, passo)
    pessoas = passo['tipo'] == 'avisar_sino' && passo['resumo'].to_s[PESSOAS, 1]
    em = Time.zone.parse(passo['em'].to_s)
    return unless pessoas && em && (de..ate).cover?(em)

    { lead_id: execucao.alvo_id, lead: execucao.alvo&.name, em: em, rotulo: nil, pessoas: pessoas.split(', ').sort }
  end

  # O Chatwoot apaga todo dia o que passa de 300 avisos por pessoa (Notification::RemoveOldNotificationJob): antes do
  # aviso mais antigo de quem bateu o teto, o código pode ter avisado e o registro sumido — compara só dali em diante.
  def corte_do_sino
    teto = Notification::RemoveOldNotificationJob::NOTIFICATION_LIMIT
    cheios = Notification.where(user_id: @account.account_users.select(:user_id)).group(:user_id)
                         .having('COUNT(*) >= ?', teto).pluck(:user_id)
    Notification.where(user_id: cheios).group(:user_id).minimum(:created_at).values.max
  end

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
    "Total: #{conta['igual']} iguais · #{conta['so_codigo']} só no código · #{conta['so_fluxo']} só no fluxo · " \
      "#{conta['pessoas']} com pessoas diferentes · #{esperando} reunião(ões) com lembrete ainda por vir"
  end

  def resultado
    return 'Resultado: nada para comparar ainda (nenhum lembrete no período)' if linhas.empty?

    bateu? ? 'Resultado: BATEU' : 'Resultado: NÃO BATEU — veja as linhas que não são "igual"'
  end

  def hora(momento) = momento.in_time_zone(Fluxo::ZONA).strftime('%d/%m %H:%M')
end
```

(b) `lib/tasks/ramon_fluxos.rake` — dentro de `namespace :lembretes`, depois da task `:modo`:

```ruby

      desc 'SO LEITURA: lembretes do codigo x fluxo em sombra. Uso: rake ramon:fluxos:lembretes:comparar[account_id,dias] ' \
           '(padrao 1 dia; rodar todo dia)'
      task :comparar, [:account_id, :dias] => :environment do |_task, args|
        puts Ramon::Fluxos::CompararLembretes.new(conta.call(args), dias: (args[:dias].presence || 1).to_i).relatorio
      end
```

(Bloco externo do rake fica com ~25 linhas < `BlockLength` 30.)

- [ ] **Step 4: Run to verify it passes**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/comparar_lembretes_spec.rb` e `bundle exec rubocop app/services/ramon/fluxos/comparar_lembretes.rb lib/tasks/ramon_fluxos.rake`
Expected: PASS, sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/comparar_lembretes.rb lib/tasks/ramon_fluxos.rake spec/services/ramon/fluxos/comparar_lembretes_spec.rb
git commit -m "feat(fluxos): comparação código × sombra dos lembretes de reunião" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 8: Front — o editor entende o fluxo novo (antes da reunião, campos, sino para Closer e SDR, selo "em sombra")

Sem isto, o Eduardo abriria o fluxo e o painel do `esperar` mostraria "Um tempo" (e um clique apagaria o `antes_de`), as condições mostrariam campo em branco e o sino "Quem recebe" vazio.

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js:244-260` (`CAMPOS`)
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/validar.js` (`RESERVADAS`)
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/PainelPasso.vue:47`, `:52-58`, `:215-231`, `:315-363`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/NoPasso.vue:99-102`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/Lista.vue:114-116`
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json`, `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`
- Test: `specs/PainelPasso.spec.js`, `specs/NoPasso.spec.js`, `specs/Lista.spec.js`, `specs/validar.spec.js` (todos em `…/captain/automacoes/specs/`)

**Interfaces:**
- Consumes: config `esperar {antes_de: 'reuniao', quantidade, unidade}`, `avisar_sino {para: 'closer_e_sdr'}`, campos `reuniao_de_pe` e `horario_passou`, `fluxo.modo` (Tasks 2–5).
- Produces: `PainelPasso` emite `{rotulo, antes_de: 'reuniao', quantidade: 1, unidade: 'horas'}` ao escolher "Antes da reunião"; `{…config, para: 'closer_e_sdr'}` ao marcar a caixinha (desmarcar = `para: undefined`, some no JSON). `data-testid`: `espera-tempo`, `espera-horario`, `espera-reuniao`, `sino-closer-sdr`.

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

  it('sino: "Closer e SDR do lead" troca a lista de pessoas', async () => {
    const wrapper = montar({
      id: 'n4',
      data: { tipo: 'avisar_sino', config: { texto: 'Oi' } },
    });
    await wrapper.find('[data-testid="sino-closer-sdr"]').setValue(true);
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { texto: 'Oi', para: 'closer_e_sdr' },
    ]);
    const marcado = montar({
      id: 'n4',
      data: { tipo: 'avisar_sino', config: { texto: 'Oi', para: 'closer_e_sdr' } },
    });
    expect(marcado.text()).not.toContain('Ana');
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
    ['reuniao_de_pe', 'horario_passou'].forEach(chave =>
      expect(
        codigos(linear(p('p1', 'preencher_campo', { chave, valor: 'x' })))
      ).toEqual([['p1', 'CAMPO_CHAVE']])
    );
  });
```

- [ ] **Step 2: Run to verify they fail**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts`
Expected: FAIL nos 5 novos (testid inexistente, texto "24 hours" sem "before the meeting", sem selo "shadow", chave aceita).

- [ ] **Step 3: Implementation**

(a) `fluxo.js` — em `CAMPOS`, trocar

```js
  'documentos_completos',
  'regra',
];
```

por

```js
  'documentos_completos',
  'regra',
  'reuniao_de_pe', // B4.1: a reunião segue marcada (sim/nao), lida na hora do passo
  'horario_passou', // B4.1: o "esperar antes da reunião" chegou tarde (sim/nao)
];
```

(b) `validar.js` — em `RESERVADAS`, trocar

```js
  'documentos_faltantes',
  'resposta_ia',
];
```

por

```js
  'documentos_faltantes',
  'resposta_ia',
  'reuniao_de_pe',
  'horario_passou',
];
```

(c) `PainelPasso.vue` — no `<script setup>`, trocar a linha 47

```js
const esperaHorario = computed(() => config.value.ate === 'horario_comercial');
```

por

```js
// esperar: um tempo (conta do passo anterior), até o horário comercial, ou antes da reunião (B4.1: conta para trás)
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
```

e trocar as linhas 52-58

```js
const modoEspera = horario =>
  emit(
    'update:config',
    horario
      ? { rotulo: config.value.rotulo, ate: 'horario_comercial' }
      : { rotulo: config.value.rotulo, quantidade: 1, unidade: 'dias' }
  );
```

por

```js
const trocaEspera = modo =>
  emit('update:config', {
    rotulo: config.value.rotulo,
    ...CONFIG_ESPERA[modo],
  });
```

no template, trocar o bloco do `avisar_sino` (linhas 215-231)

```vue
      <template v-else-if="tipo === 'avisar_sino'">
        <CampoTexto
          :rotulo="t(`${K}.PAINEL.TEXTO`)"
          :linhas="2"
          :model-value="config.texto || ''"
          @update:model-value="v => muda('texto', v)"
        />
        <div :class="ROTULO">
```

por

```vue
      <template v-else-if="tipo === 'avisar_sino'">
        <CampoTexto
          :rotulo="t(`${K}.PAINEL.TEXTO`)"
          :linhas="2"
          :model-value="config.texto || ''"
          @update:model-value="v => muda('texto', v)"
        />
        <label class="flex items-center gap-2 text-[13px] text-n-slate-12">
          <input
            data-testid="sino-closer-sdr"
            type="checkbox"
            class="reset-base"
            :checked="config.para === 'closer_e_sdr'"
            @change="
              muda('para', $event.target.checked ? 'closer_e_sdr' : undefined)
            "
          />
          {{ t(`${K}.PAINEL.PARA_CLOSER_SDR`) }}
        </label>
        <div v-if="config.para !== 'closer_e_sdr'" :class="ROTULO">
```

(o resto do bloco — `ListaMarcar`, ajuda, `</div>`, `</template>` — fica igual), e trocar o bloco do `esperar` (linhas 315-363) inteiro por:

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

(d) `NoPasso.vue` — trocar o `case 'esperar'` (linhas 99-102)

```js
    case 'esperar':
      return c.ate === 'horario_comercial'
        ? t(`${K}.PAINEL.ESPERAR_HORARIO`)
        : `${c.quantidade ?? ''} ${c.unidade ? t(`${K}.${Number(c.quantidade) === 1 ? 'UNIDADES_UM' : 'UNIDADES'}.${c.unidade}`) : ''}`;
```

por

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

(e) `Lista.vue` — no `selo`, trocar

```js
  if (!f.ativo)
    return { classe: TOM.slate, icone: '', texto: t(`${K}.SELO.DESLIGADO`) };
  return { classe: TOM.teal, icone: '', texto: t(`${K}.SELO.OK`) };
```

por

```js
  if (!f.ativo)
    return { classe: TOM.slate, icone: '', texto: t(`${K}.SELO.DESLIGADO`) };
  // B4.1: em sombra só ensaia nos eventos reais (quem age ainda é o código)
  if (f.modo === 'sombra')
    return {
      classe: TOM.amber,
      icone: 'i-lucide-eye',
      texto: t(`${K}.SELO.SOMBRA`),
    };
  return { classe: TOM.teal, icone: '', texto: t(`${K}.SELO.OK`) };
```

(f) i18n — mesmas posições nos dois arquivos (Edit à mão):

`en/ramon.json`:
- `"NO_CODIGO": "runs in code"` → `"NO_CODIGO": "runs in code",` + nova linha `"SOMBRA": "shadow"`
- `"QUALQUER_EVENTO": "any event"` → `"QUALQUER_EVENTO": "any event",` + nova linha `"ANTES_DA_REUNIAO": "{tempo} before the meeting"`
- depois de `"QUEM_RECEBE_AJUDA": "Nobody checked = lead owner.",` inserir `"PARA_CLOSER_SDR": "Lead Closer and SDR (neither: the administrators)",`
- depois de `"ESPERAR_HORARIO": "Until the next business hours",` inserir `"ESPERAR_REUNIAO": "Before the meeting",`
- depois de `"ESPERAR_AJUDA": "Counts from the previous step.",` inserir `"ESPERAR_REUNIAO_AJUDA": "Counts back from the meeting time. If that moment has already passed, it does not wait and sets Reminder time already passed = yes.",`
- `"regra": "ADVBOX rule (event)"` → `"regra": "ADVBOX rule (event)",` + novas linhas `"reuniao_de_pe": "Meeting still booked (yes or no)",` e `"horario_passou": "Reminder time already passed (yes or no)"`

`pt_BR/ramon.json`:
- `"NO_CODIGO": "roda no código"` → `"NO_CODIGO": "roda no código",` + `"SOMBRA": "em sombra"`
- `"QUALQUER_EVENTO": "qualquer evento"` → `"QUALQUER_EVENTO": "qualquer evento",` + `"ANTES_DA_REUNIAO": "{tempo} antes da reunião"`
- depois de `"QUEM_RECEBE_AJUDA": "Ninguém marcado = responsável do lead.",` → `"PARA_CLOSER_SDR": "Closer e SDR do lead (sem nenhum dos dois: os administradores)",`
- depois de `"ESPERAR_HORARIO": "Até o próximo horário comercial",` → `"ESPERAR_REUNIAO": "Antes da reunião",`
- depois de `"ESPERAR_AJUDA": "Conta a partir do passo anterior.",` → `"ESPERAR_REUNIAO_AJUDA": "Conta para trás a partir do horário da reunião. Se esse momento já passou, não espera e marca Horário do lembrete já passou = sim.",`
- `"regra": "Regra do ADVBOX (evento)"` → `"regra": "Regra do ADVBOX (evento)",` + `"reuniao_de_pe": "Reunião segue marcada (sim ou não)",` e `"horario_passou": "Horário do lembrete já passou (sim ou não)"`

- [ ] **Step 4: Run to verify they pass**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts`
Expected: PASS — **15 arquivos / 173 testes** (168 + 5; o `i18n.spec.js` confere as chaves novas e os rótulos de `CAMPOS`).
Run: `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes`
Expected: sem `error` (só `Delete ␍`/`no-dynamic-keys` já conhecidos). Se o prettier reclamar da quebra de linha de algum trecho acima, rodar `./node_modules/.bin/eslint --fix <arquivo>` e conferir o diff.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js app/javascript/dashboard/routes/dashboard/captain/automacoes/validar.js app/javascript/dashboard/routes/dashboard/captain/automacoes/PainelPasso.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/NoPasso.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/Lista.vue app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/PainelPasso.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/NoPasso.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/Lista.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/validar.spec.js
git commit -m "feat(fluxos): editor com espera antes da reunião, sino para Closer e SDR e selo em sombra" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 9: Verificação final + notas na spec (§15 Notas da B4.1) + texto do PR

**Files:**
- Modify: `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (acrescentar §15 no fim)

- [ ] **Step 1: Front inteiro**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts
./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes
```
Expected: 15 arquivos / 173 testes verdes; eslint sem `error`. `git status --short` não pode listar `vitest.local.config.ts`.

- [ ] **Step 2: Varredura de regras**

```bash
git diff 71e1ce0 --stat -- app/models/lead.rb app/services/ramon/advbox_event_processor.rb app/finders/conversation_finder.rb enterprise db/migrate db/schema.rb db/seeds/ramon/fluxos/sistema
git diff 71e1ce0 --stat
grep -rn "MeetingReminderJob::TOLERANCE\|meeting_open?" app spec lib
grep -n "RAMON_FLUXO_LEMBRETES" -r app lib .env.example
wc -l app/services/ramon/reuniao_agendamento.rb app/services/ramon/fluxos/contexto.rb app/services/ramon/fluxos/disparo.rb app/services/ramon/fluxos/comparar_lembretes.rb
```
Expected: o 1º vazio (nada em lead/processor/finder/enterprise/migração/schema/desenhos do sistema); o 3º vazio; a env aparece só em `lembretes.rb`, no rake (`desc`), no comentário de `reuniao_agendamento.rb` e no `.env.example`; todos os arquivos < 175 linhas de classe.

- [ ] **Step 3: Notas da B4.1 na spec** — acrescentar ao fim de `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md`:

```markdown
## 15. Notas da B4.1 (06/10/2026) — lembretes de reunião em sombra

- **Escopo:** só os 5 lembretes (24h · 8h · 1h · 30 min · 5 min, sino do Closer e do SDR + push) viram fluxo. Atividade, tarefa da reunião, etapa, Closer automático, rascunho de confirmação ao cliente e sino/push de "reunião marcada/cancelada" continuam no `Ramon::ReuniaoAgendamento` (são o registro da reunião).
- **Motor ganhou:** `esperar {antes_de: 'reuniao', quantidade, unidade}` (conta para trás a partir da reunião; momento já passado → não espera e `{horario_passou}` = sim); a variável `{reuniao_de_pe}` (sim/nao, lida na hora do passo); o sino `para: 'closer_e_sdr'` (sem nenhum dos dois: administradores); o ensaio do sino diz quem receberia (`faria: sino para Ana, Bruno: "…"`). O gatilho `reuniao_marcada`/`reuniao_cancelada` leva `inicio` (ISO) além de `quando`.
- **Regras num lugar só:** `Ramon::Fluxos::Lembretes.reuniao_aberta?` e `.destinatarios` valem para o `MeetingReminderJob` e para o fluxo — a sombra compara a mesma regra.
- **Remarcar = recomeçar:** um novo `reuniao_marcada` cancela a execução que esperava (mesmo fluxo e lead, normal ou sombra) antes de criar a nova (`Disparo::RECOMECA`). Consequência aceita: lead com 2 reuniões abertas ao mesmo tempo é lembrado só da última marcada.
- **Desligar o fluxo cancela também a sombra que espera** (o "Testar com um lead…" roda até com o fluxo desligado).
- **O fluxo:** 1 por conta, `origem: usuario`, `sistema_chave: lembretes_reuniao`, criado pelo rake `ramon:fluxos:lembretes:sombra[conta]` a partir de `db/seeds/ramon/fluxos/migrados/lembretes_reuniao.json` (idempotente; existindo, não toca — o Eduardo pode editar). Gatilho com `cancelar_se_sair_da_etapa: false` (o código não cancela por etapa).
- **Comparação:** `rake ramon:fluxos:lembretes:comparar[conta,dias]` (só leitura) põe lado a lado o sino `ramon_meeting_reminder` (o que o código mandou) e as linhas `faria: sino` da sombra, casando por lead e horário (até 3 min). Só reuniões marcadas depois que a sombra nasceu; ignora o "Testar com um lead…"; respeita o teto de 300 avisos por pessoa do Chatwoot (compara só depois do aviso mais antigo que sobrou) — por isso roda todo dia.
- **A chave:** o código só para de agendar (`ReuniaoAgendamento#enqueue_reminders`, único ponto) com `RAMON_FLUXO_LEMBRETES=on` **e** o fluxo ligado, publicado e em `modo: normal`. Virar = `rake ramon:fluxos:lembretes:modo[conta,normal]` (recusa sem a env); voltar = `…modo[conta,sombra]`. Os lembretes já enfileirados antes da virada saem pelo código (o job não consulta a chave).
- **Fica para a limpeza (outro PR, depois de rodar em normal):** apagar `enqueue_reminders` e o `Ramon::MeetingReminderJob`, o JSON `sistema/lembretes_reuniao.json` **e** a linha `origem: sistema` dele, e a env.
```

- [ ] **Step 4: Texto do PR (não abrir — gate do Eduardo)** — deixar no relatório final:

```markdown
Automações em fluxo — B4.1: os lembretes de reunião (24h, 8h, 1h, 30 min e 5 min antes, no sino do Closer e do SDR e no push) ganham um fluxo de verdade, "Lembretes de reunião", que o hub pode rodar **em sombra**: ele acompanha as reuniões reais e anota o que faria, sem avisar ninguém, enquanto o código continua mandando os lembretes como hoje. Uma comparação diária mostra, lembrete a lembrete, o que o código mandou e o que o fluxo faria. Quando bater e o Eduardo aprovar, uma chave faz o fluxo assumir e o código parar de agendar — e o fluxo vira editável na tela. **A chave vem desligada: nada muda no uso até o Eduardo virar.** No editor, o passo "Esperar" ganhou "Antes da reunião", o sino ganhou "Closer e SDR do lead" e a lista mostra o selo "em sombra".

## Closes
- Spec `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` §8 (B4+, migração 1 a 1 em sombra — 1ª: lembretes de reunião) e §14 (nota da B4); notas novas em §15.

## How to test
1. Depois do deploy: `rake "ramon:fluxos:lembretes:sombra[2]"` → "Fluxo #N "Lembretes de reunião" — modo sombra, ligado, versão 1".
2. Inteligência → Automações → Meus fluxos: "Lembretes de reunião" com o selo "em sombra". Abrir: 5 esperas "… antes da reunião", 5 condições "Reunião segue marcada / Horário do lembrete já passou", sinos com "Closer e SDR do lead" marcado. "Do sistema → Lembretes de reunião" segue igual ("roda no código").
3. Marcar uma reunião de teste (painel do lead) para daqui a ~40 min: o lembrete de 30 min chega no sino como sempre (código) e, em Execuções do fluxo, aparece uma execução "ensaio" com `faria: sino para …` no mesmo minuto. Remarcar: a execução antiga fica "cancelada: a reunião foi remarcada" e nasce outra.
4. `rake "ramon:fluxos:lembretes:comparar[2,1]"` → linha "igual" para o lembrete de teste e "Resultado: BATEU".

## What changed
- Motor: `esperar` antes da reunião, variáveis `{reuniao_de_pe}`/`{horario_passou}`, sino para Closer e SDR, ensaio do sino com os nomes, remarcar recomeça o fluxo, desligar também para a sombra; gatilho de reunião com o horário em ISO.
- `Ramon::Fluxos::Lembretes` (regras únicas, criação do fluxo, chave) e `Ramon::Fluxos::CompararLembretes` (comparação); rake `ramon:fluxos:lembretes:{sombra,comparar,modo}`; `MeetingReminderJob` usa as regras únicas (mesmo comportamento).
- Chave `RAMON_FLUXO_LEMBRETES` (desligada) + fluxo em modo normal → o código não agenda; único ponto: `ReuniaoAgendamento#enqueue_reminders`.
- Front: editor e lista entendem o fluxo novo. Sem migração.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv
```

- [ ] **Step 5: Smoke em bloco (para o Eduardo, depois do deploy)** — anotar no relatório: (1) rodar o rake `sombra` e ver o fluxo com o selo "em sombra" na lista; (2) abrir o fluxo e conferir os 21 passos e os textos do sino/push (é aqui que o Eduardo aprova a Decisão E2); (3) marcar uma reunião de teste para daqui a ~40 min num lead de teste, conferir o lembrete de 30 min do código no sino e a execução "ensaio" com `faria: sino para …`; remarcar e ver a antiga cancelada; cancelar e ver que nada mais sai; (4) rodar o `comparar` e colar a saída; (5) apagar o lead de teste (apagar `LeadActivity` antes do lead).

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
`docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:lembretes:sombra[2]"`
Saída esperada: `Fluxo #N "Lembretes de reunião" — modo sombra, ligado, versão 1`. A partir daqui, toda reunião marcada/remarcada gera uma execução "ensaio" no fluxo; o código continua mandando tudo. Rodar de novo não duplica.

**2. Quanto tempo.** No mínimo **7 dias corridos** e até juntar **≥ 15 lembretes comparados** (≈ 3–4 reuniões com os lembretes saindo), idealmente com **1 remarcação e 1 cancelamento** de verdade (ou provocados num lead de teste). Reuniões marcadas antes do dia 0 não entram na comparação.

**3. Comparar — todo dia** (o sino do Chatwoot guarda só os 300 avisos mais recentes por pessoa; olhar o dia anterior todo dia evita perder rastro):
`docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:lembretes:comparar[2,1]"`
No fim do período, a visão inteira: `…comparar[2,7]` (as linhas antigas podem ter sumido do sino — vale a soma das diárias). Cada linha é `igual`, `só no código`, `só no fluxo` ou `pessoas diferentes`; o fim diz `Resultado: BATEU` ou `NÃO BATEU`.

**4. Critério GO / NO-GO para virar a chave** (Decisão E4):
- **GO:** ≥ 7 dias e ≥ 15 lembretes comparados; **0** linhas que não sejam `igual`, ou cada uma explicada e aceita pelo Eduardo (ex.: alguém apagou o aviso do sino → `só no fluxo`; deploy no minuto do lembrete); e o Eduardo aprovou os textos (Decisão E2).
- **NO-GO:** qualquer divergência sem explicação → corrigir (código ou desenho; o desenho se edita na tela e se publica de novo) e **recomeçar a contagem** dos 7 dias.

**5. Virar a chave (GO).** Nesta ordem — em nenhum momento fica sem lembrete ou em dobro:
1. Acrescentar `RAMON_FLUXO_LEMBRETES=on` ao `chatwoot.env` em `/opt/intranet-ramon` e recriar: `docker compose up -d chatwoot-web chatwoot-worker`. Nada muda ainda (o fluxo está em sombra → o código segue).
2. `docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:lembretes:modo[2,normal]"` → saída "… modo normal, ligado. Agora o FLUXO manda os lembretes (o código não agenda mais)". A partir desse instante, reunião nova/remarcada = fluxo; as marcadas antes continuam com os lembretes do código que já estão na fila.
3. Smoke: reunião de teste para daqui a ~40 min → em Execuções do fluxo, uma execução **sem** o selo ensaio; aos 30 min, o sino "Automação: Reunião em 30min antes (…) — hora de confirmar com o cliente (…)" chega ao Closer/SDR (e o push, se `NTFY_TOPIC`); nenhum "Reunião com … em 30min antes" do código para essa reunião.
O fluxo vira editável como qualquer outro (só admin). A aba "Do sistema" ainda mostra "Lembretes de reunião — roda no código" até o PR de limpeza.

**6. Rollback (a qualquer momento, sem deploy).**
`docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:lembretes:modo[2,sombra]"` → saída "Agora o CÓDIGO manda os lembretes". Reuniões novas voltam para o código na hora; quem já esperava no fluxo (reuniões marcadas durante o período em normal) termina pelo fluxo — sem dobra. A env pode ficar ligada.
- **Não** desligar só a env com o fluxo em normal: o código voltaria a agendar **e** o fluxo seguiria lembrando (dobra). Sempre `modo[2,sombra]` primeiro.
- Desligar o fluxo na tela também devolve ao código, mas **cancela** os lembretes que o fluxo ainda ia mandar para reuniões já marcadas — prefira o rake.
- Parar a sombra antes de virar: desligar o fluxo na tela (as execuções "ensaio" que esperavam são canceladas).

**7. Depois (outro PR, Decisão E7).** Rodando em normal pelo prazo combinado sem incidente: apagar `ReuniaoAgendamento#enqueue_reminders` e `Ramon::MeetingReminderJob` (e as regras que só ele usa), o JSON `db/seeds/ramon/fluxos/sistema/lembretes_reuniao.json` **e** a linha `origem: sistema` dele (a sincronização não apaga linha cujo JSON sumiu), e a env `RAMON_FLUXO_LEMBRETES`.

---

## Divergências registradas (spec × este plano)

| # | Onde | Divergência | Motivo |
|---|---|---|---|
| 1 | Spec §6 ("Fluxo em `modo: sombra` cria execução com `status: ensaio`") | Sombra = coluna `ensaio: true` com status normal (`esperando`/`concluida`), e **espera de verdade** (não pula esperas como o "Testar…") | Já é assim desde a B1 (`Disparo#atributos`); a sombra precisa esperar para comparar horários |
| 2 | Spec §4.4 ("espera conta do passo anterior") | `esperar` ganha o modo `antes_de: 'reuniao'`, que conta para trás a partir da reunião | Sem isso o fluxo não reproduz 24h/8h/1h/30min/5min antes |
| 3 | Spec §6 (índice único "não roda 2× para o mesmo alvo") | Gatilho `reuniao_marcada` **recomeça**: cancela a espera antiga antes de criar a nova | Remarcar tem de seguir o horário novo; o código faz o equivalente pelo guard + dedupe |
| 4 | Spec §8 passo 3 ("env/flag desliga o caminho do código, fluxo vira normal") | Chave dupla: env **e** `modo: normal` (rake); voltar = rake `sombra` | Nem buraco nem dobra se uma das duas estiver errada; rollback sem deploy |
| 5 | Spec §8 / B3 desenho do sistema `lembretes_reuniao` (cobre a reunião toda) | O fluxo da B4.1 cobre só os 5 lembretes; o resto da reunião marcada fica no código | Decisão E1 (a ser confirmada) |

## Decisões que dependem do Eduardo

| # | Decisão | Proposta do plano | Onde |
|---|---|---|---|
| E1 | Escopo da B4.1: só os 5 lembretes viram fluxo; atividade, tarefa da reunião, etapa, Closer automático, rascunho de confirmação ao cliente e sino/push de "reunião marcada/cancelada" ficam no código | Sim — são o registro da reunião, não o lembrete; o rascunho de confirmação pode ser uma B4.1b se ele quiser editá-lo na tela | Tasks 5, 6 |
| E2 | Texto do lembrete muda um pouco: hoje "Reunião com Maria em 1h antes (20/08 14:00) — hora de confirmar com o cliente"; pelo fluxo "Automação: Reunião em 1h antes (quinta, 20/08 às 14:00) — hora de confirmar com o cliente (Maria)". O push usa o nome do contato em vez do nome do lead | Aprovar como está ou ditar outro (editável na tela depois de assumir) | Task 5, Operação §4 |
| E3 | Lead com 2 reuniões abertas ao mesmo tempo: o fluxo lembra só da última marcada (o código lembra das duas) | Aceitar (raro; a sombra faz igual, então a comparação acusaria se acontecer) | Task 4 |
| E4 | Tempo de sombra e critério para virar | ≥ 7 dias e ≥ 15 lembretes comparados, 0 divergência sem explicação; comparação diária | Operação §2–§4 |
| E5 | Chave dupla (env `RAMON_FLUXO_LEMBRETES=on` + rake `modo[2,normal]`) e rollback pelo rake `modo[2,sombra]`, sem deploy | Aprovar | Task 6, Operação §5–§6 |
| E6 | Depois de assumir, o fluxo é editável por admin como qualquer outro; uma edição errada (ex.: apagar um sino) tira aquele lembrete | Ciente; quem publica é admin | — |
| E7 | Quando fazer a limpeza (apagar o código antigo, o desenho e a linha do sistema, a env) | 2 semanas rodando em normal sem incidente | Operação §7 |
