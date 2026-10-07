# Automações em fluxo — B4.2 (SLA da 1ª resposta direto no fluxo) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O vigia do **SLA da 1ª resposta** (hoje `Ramon::FirstResponseSlaJob`, agendado pelo `RamonLeadListener`) vira um fluxo de verdade — "SLA da 1ª resposta" — que, com a chave ligada, vigia cada conversa nova das caixas com "Criar lead" e o código para; com a chave desligada, o código vigia como hoje e o fluxo só ensaia. De quebra, a peça que toda migração precisa (env por migração, fluxos migrados, chave, virar modo, criar dos JSON, rake) sai da B4.1 para um módulo comum, e o **horário comercial ganha janela própria por passo** (dias + das/até), reaproveitável pela cadência (B4.3).

**Architecture:** Um módulo novo `Ramon::Fluxos::Migracao` guarda o registro das migrações (`GRUPOS`: `reunioes` da B4.1 e `sla` da B4.2) e tudo que é genérico (`migrado?`, `ligada?`, `assumiu?`, `fluxos`, `fluxo`, `mudar_modo!`, `descrever`, `semear`, `criar`); `Ramon::Fluxos::Reunioes` vira cliente fino dele (API pública igual, specs da B4.1 intactas) e o rake genérico `ramon:fluxos:migracao:{criar,modo}` serve a qualquer grupo. O `RamonLeadListener` decide **uma vez** por conversa nova (`Migracao.assumiu?(account, 'sla')`), dispara o gatilho `conversa_criada` com `assumido` (só o fluxo migrado ouve esse disparo; os fluxos comuns de `conversa_criada` seguem ouvindo só o ouvinte geral) e só agenda o job se o fluxo não estiver no comando **ou** não tiver pegado a conversa. O motor ganha o mínimo para ser fiel: `esperar {desde: 'conversa'}` (com `prazo: 'sla_caixa'` = `Ramon::Cadencia.sla_minutes`), variáveis `{primeira_resposta}` e `{sla_minutos}`, sino `para: sdr_ou_gestores | gestores` e a janela de horário por passo em `Ramon::Fluxos::Horario`. Sem migração de banco, sem fase de sombra, sem comparação.

**Tech Stack:** Rails 7.1 / RSpec (só no CI), Postgres jsonb, Sidekiq (ActiveJob); Vue 3.5 `<script setup>`, vue-i18n 9, Vitest 3 + @vue/test-utils.

**Spec:** `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (§4.2 `em_horario_comercial`, §4.4 esperar, §6 motor, §8 migração B4+, §14 nota "B4: fluxo próprio, origem usuario", §15 notas da B4.1). Plano de referência de estilo: `docs/superpowers/plans/2026-10-06-automacoes-fluxo-b4-lembretes.md` (B4.1).

## Escopo decidido pelo Eduardo em 07/10/2026 (vence a spec §8)

1. **D1 — direto, sem sombra:** o SLA da 1ª resposta migra para um fluxo de verdade **sem fase de sombra e sem comparação**. Mesma chave da B4.1: env `RAMON_FLUXO_SLA=on` **e** o fluxo em modo normal → o fluxo vigia e o código para; qualquer peça fora → o código vigia. Voltar = rake `modo sombra` (ou env desligada), sem deploy. Teste ao vivo logo depois do deploy (smoke).
2. **D2 — horário configurável no fluxo:** a condição "agora é horário comercial" e o "esperar até o horário comercial" aceitam **a própria janela** (dias da semana + das/até), editável no editor. O fluxo migrado nasce com a janela do código de hoje (**7h–21h, todos os dias**, São Paulo) — nada muda na virada. Como hoje: a escalada de 60 min é esperada mesmo fora do horário; só o aviso respeita o horário.
3. **Fidelidade:** prazo = SLA da caixa (`Ramon::Cadencia.sla_minutes`, padrão do env); "ainda sem 1ª resposta" + "conversa aberta" + "conversa tem lead"; 1º aviso para o SDR do lead (sem SDR: gestores, `Ramon::Papeis.gestor_ids`) + push; escalada aos 60 min da criação da conversa para os gestores (sem push). Tipo/texto do sino pode mudar (precedente E2).
4. **Lições da B4.1:** uma decisão por evento (nem em dobro, nem ninguém); o gatilho fica onde o código dispara hoje; produção não muda até a chave virar; edição só por admin.
5. **E7 análogo:** apagar o código antigo é outro PR, 2 semanas depois de rodar em normal.
6. **Pedido do coordenador (07/10):** a chave/semeadura das migrações vira um módulo comum (B4.3 cadência e B4.4/B4.5 lead ganho + ADVBOX rebaseiam sobre esta fatia e usam ele), e a janela de horário por passo é reaproveitável. Ambos são tasks com interface explícita (Tasks 1 e 2).

## Global Constraints

- Base: **origin/ramon 079a04c** (B1–B3 e B4.1 no ar); branch `feat/fluxos-b42-sla`, worktree `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-fluxos-b42`. Nunca `git push`, nunca abrir PR (gate do Eduardo / sessão principal).
- **Produção não muda até o Eduardo virar a chave.** Com `RAMON_FLUXO_SLA` ausente/`off` (padrão) ou sem o fluxo em normal, o `RamonLeadListener` agenda o `Ramon::FirstResponseSlaJob` exatamente como hoje. O fluxo só nasce quando alguém roda `rake ramon:fluxos:migracao:criar[sla,<conta>]`. Fluxos sem janela no config continuam seg–sex 8h–18h.
- **Comportamento da B4.1 intacto:** `spec/services/ramon/fluxos/reunioes_spec.rb`, `spec/services/ramon/reuniao_agendamento_spec.rb`, `spec/services/ramon/fluxos/{disparo,passos,comparar_agendamentos,comparar_lembretes}_spec.rb` passam **sem edição**. O rake `ramon:fluxos:reunioes:{sombra,modo,comparar}` continua igual.
- **Não apagar nada do caminho antigo nesta fatia:** `Ramon::FirstResponseSlaJob`, o agendamento no `RamonLeadListener` e o desenho `db/seeds/ramon/fluxos/sistema/sla_primeira_resposta.json` (e a linha `origem: sistema` dele) ficam (E7).
- **Sem migração.** `ramon_fluxos` já tem `origem`, `sistema_chave`, `modo`; execução com alvo `Conversation` já existe. Se alguma task achar que precisa de coluna/índice: pare e pergunte (exigiria regenerar `db/schema.rb` por scratch DB na VPS).
- **Rubocop do fork** (o CI barra): `Metrics/AbcSize` 26, `Metrics/MethodLength` 19, `Metrics/CyclomaticComplexity` 7, `Metrics/PerceivedComplexity` 8, `Metrics/ClassLength` 175, `Metrics/ModuleLength` 100, `Metrics/BlockLength` 30 (fora de spec — **inclusive `lib/tasks`**: por isso o rake genérico vai em arquivo próprio), linha 150, `Style/HashSyntax` `EnforcedShorthandSyntax: never`, `rubocop-rspec` (`RSpec/MultipleExpectations` 7, `RSpec/ExampleLength` 50, `RSpec/SpecFilePathFormat`). `app/models/lead.rb`, `app/services/ramon/advbox_event_processor.rb` e `app/finders/conversation_finder.rb` estão no limite: **nenhuma linha nova** (este plano não toca nenhum). Linhas de código (sem comentário/branco) na base: `grafo.rb` **150** (limite 175 — este plano soma ~6), `disparo.rb` 97, `contexto.rb` 81, `reunioes.rb` 70 (cai para ~40), `ramon_lead_listener.rb` 76, `passos/logica.rb` 27, `passos/aviso.rb` 29, `horario.rb` 16.
- **Sem Ruby local:** specs Ruby são escritos e conferidos à mão; quem valida é o CI. `travel_to` sempre em blocos **em sequência** (nunca aninhados); código que o spec faz viajar só usa `Time.current`. O helper `ctx` de `passos_spec.rb` cria uma execução viva: **uma execução não-ensaio por alvo por exemplo** (o índice único parcial barra a 2ª); para a 2ª use `ensaio: true`.
- **Mensagem ao cliente SEMPRE rascunho; só admin edita.** Este fluxo não fala com o cliente (só sino e push internos). A API de fluxos segue admin-only.
- **Front:** i18n só dentro de `CAPTAIN_RAMON.FLUXOS` em `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json`, chaves novas na **mesma posição** nos dois (a trava `specs/i18n.spec.js` compara a ordem e compila no vue-i18n de produção); strings sem `@`, `|`, `{`, `}` crus (só placeholders `{tempo}`, `{h}`); editar os JSON à mão (Edit). Tailwind only, kit `ramon/helpers/ui.js` (`ROTULO`, `CAMPO`, `SELECT`), evento custom camelCase, sem texto cru no template.
- **Vitest:** `node_modules` é junção (nunca `rm -rf node_modules`); `vitest.local.config.ts` já existe na raiz do worktree, **fora do git** (está em `.git/info/exclude`; não commitar):
  `TZ=UTC npx vitest run <arquivos ou pastas> --config vitest.local.config.ts`
  Baseline medido em 079a04c: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs` = **15 arquivos, 180 testes**. ESLint: `./node_modules/.bin/eslint <arquivos>` (erro `Delete ␍` = CRLF do checkout Windows, ignorar; warnings `@intlify/vue-i18n/no-dynamic-keys` aceitos).
- **Commits:** Conventional Commits em pt-BR, sem citar Claude no assunto; corpo termina com:
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR`
  Commitar só os caminhos da task (`git add <arquivos>`), nunca `git add -A`.

## Review Focus

1. **Conversa nova no momento da virada, com o fluxo desligado na tela ou com o fluxo que não pega a conversa** (filtro de caixa editado, erro do motor) — vigiada **uma vez**, por um lado só; nunca por ninguém. Teste: Task 4 ("sem a chave…", "com a chave, o fluxo vigia e o código não…", "voltar para sombra…", "fluxo no comando que não pega a conversa…").
2. **Os fluxos comuns de "Conversa criada" do Eduardo** — continuam rodando uma vez por conversa (pelo ouvinte geral) e o fluxo do SLA nunca é iniciado pelo ouvinte geral (nem em caixas sem "Criar lead"). Teste: Task 4 ("o ouvinte geral não inicia o fluxo do SLA…").
3. **Fronteiras do horário** (20h59 × 21h00, sábado/domingo, madrugada; aviso fora do horário com escalada dentro) — mesmo resultado do código (7h–21h todo dia). Teste: Task 2 (`horario_spec`, `condicao_spec`) e Task 4 ("aviso só no horário do passo…").
4. **Caixa com SLA ≥ 60 min, conversa respondida antes do prazo** — sem escalada / sem nada, como o código. Teste: Task 4 ("caixa com SLA de 60 min…", "respondeu antes do prazo…").
5. **Janela mal configurada** (nenhum dia marcado, início depois do fim, fim > 24) — recusada ao publicar (back e front), e nunca trava o motor num laço. Teste: Task 2 (`janela_valida?`, `grafo_spec`) e Task 5 (`validar.spec.js`).

---

## Como o fluxo fica fiel ao código (decisões de desenho)

### O que o código faz × o que o fluxo faz

| Momento | Código hoje (`RamonLeadListener#enqueue_first_response_sla`, `Ramon::FirstResponseSlaJob`) | Fluxo "SLA da 1ª resposta" (B4.2) |
|---|---|---|
| conversa nova (caixa com Criar lead, com contato) | depois de criar/religar o lead, agenda o job para `sla_minutes(inbox)` min | o mesmo ponto dispara `conversa_criada` com `assumido` → alvo = a conversa |
| prazo | `set(wait: N.minutes)` a partir do evento | `esperar {desde: 'conversa', prazo: 'sla_caixa'}` = criação da conversa + `Ramon::Cadencia.sla_minutes(inbox)` |
| guardas | conversa existe, `first_reply_created_at` vazio, `open?`, `leads.find_by(conversation_id:)` existe | `se {primeira_resposta = nao E status = open E etapa existe}` (todo lead tem etapa; sem lead → `etapa` vazia); conversa apagada → execução cancelada ("o alvo foi apagado") |
| guardas falham | sai sem agendar a escalada | `nao` sem seta → termina (sem escalada) |
| aviso | só se `hour.between?(7, 20)` em SP | `se {agora é horário comercial, janela dias 0–6, 7h–21h}` |
| 1º aviso | sino `ramon_sla_breach` para SDR (sem SDR: gestores) + ntfy "Lead aguardando 1a resposta" / "Lead aguardando 1ª resposta há Nmin: nome" | `avisar_sino {para: sdr_ou_gestores, texto: "Lead aguardando 1ª resposta há {sla_minutos} min: {nome_completo}"}` + `avisar_push` (mesmo título; corpo com `{sla_minutos}min`) — sino vira `ramon_fluxo_aviso` (E2) |
| escalada | agendada **mesmo fora do horário**, para `created_at + 60 min` **se ainda for futuro** | fora do horário o `se` vai para a espera da escalada (não termina); `esperar {desde: 'conversa', quantidade: 60, unidade: 'minutos'}`: momento já passado → não espera e marca `{horario_passou} = sim` → o `se` seguinte termina (caixa com SLA ≥ 60 min: sem escalada, como o código) |
| na escalada | mesmas guardas; sino `ramon_sla_breach` para gestores (meta 60), **sem** ntfy | `se {horario_passou = nao E as 3 guardas}` → `se {horário 7–21}` → `avisar_sino {para: gestores, texto: "… há 60 min: …"}`, sem push |

O fluxo não cancela por mudança de etapa (`cancelar_se_sair_da_etapa: false` no gatilho): o código não cancela.

### A decisão é da conversa nova (análise da virada)

- O `RamonLeadListener` lê `Ramon::Fluxos::Migracao.assumiu?(account, 'sla')` **uma vez** e manda `'assumido' => true|false` no gatilho. No `Disparo`, `conversa_criada` passa a ser um gatilho "disparado 2 vezes" (como `reuniao_marcada/cancelada` na B4.1): **com** `assumido` só os fluxos migrados ouvem; **sem** `assumido` (o `RamonFluxoListener` de sempre) só os demais. O fluxo migrado age ou ensaia pela decisão do evento (`Disparo#sombra?`, já da B4.1).
- **Nunca ninguém:** o listener só deixa de agendar o job se a decisão foi "fluxo" **e** o disparo criou a execução (`Disparo.externo` devolve as execuções; filtro de caixa editado, índice único ou erro do motor → lista vazia → o código vigia aquela conversa). Decisão N2.
- **Nunca os dois:** com a decisão "código", o fluxo (se existir) só ensaia; com "fluxo" e execução criada, o job não é agendado. Conversas que nasceram antes da virada mantêm o job do código já na fila; as que nasceram com o fluxo no comando terminam pelo fluxo mesmo depois de voltar para sombra (a execução já nasceu "de verdade").
- **Precisão:** o fluxo acorda pelo relógio de minuto (`Ramon::FluxoRelogioJob`) → o aviso pode sair até ~1 min depois do prazo (o job do código sai no segundo). Decisão N1.

### Por que um módulo comum de migração (pedido do coordenador)

`reunioes.rb` já tem 70 linhas de código, das quais ~35 são a chave e a semeadura — exatamente o que SLA, cadência, lead ganho e ADVBOX também precisam. Em vez de copiar, `Ramon::Fluxos::Migracao` vira o dono dessa parte, com um registro `GRUPOS` (uma linha por migração: env, frase para o rake, fluxos `sistema_chave → gatilho`, ajuste opcional do desenho por conta). `Reunioes` mantém a mesma API pública chamando o módulo (zero mudança para `ReuniaoAgendamento`, `Passos::Lead`, comparações, rake e specs da B4.1). A B4.3+ entra com uma linha em `GRUPOS`, o(s) JSON em `db/seeds/ramon/fluxos/migrados/` e o código lendo `Migracao.assumiu?(account, '<grupo>')` uma vez por evento.

## Mapa de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `app/services/ramon/fluxos/migracao.rb` (novo) | registro `GRUPOS` + chave/semeadura genéricas de qualquer migração |
| `app/services/ramon/fluxos/reunioes.rb` | regras de reunião (como antes) + a chave delegada ao `Migracao` |
| `lib/tasks/ramon_fluxos_migracao.rake` (novo) | `ramon:fluxos:migracao:{criar,modo}[grupo,conta(,modo)]` |
| `app/services/ramon/fluxos/horario.rb` | janela por passo (`janela`, `janela_valida?`, `comercial?`/`proximo` com janela) |
| `app/services/ramon/fluxos/{condicao,grafo,disparo,contexto}.rb`, `passos/{logica,aviso}.rb` | condição/espera com janela, validação, `esperar desde a conversa`, `{primeira_resposta}`, `{sla_minutos}`, sino SDR/gestores, `conversa_criada` disparado 2 vezes |
| `db/seeds/ramon/fluxos/migrados/sla_primeira_resposta.json` (novo) | o desenho fiel |
| `app/listeners/ramon_lead_listener.rb` | a decisão por conversa nova |
| `.env.example` | documenta `RAMON_FLUXO_SLA` |
| `app/javascript/dashboard/routes/dashboard/captain/automacoes/{JanelaHorario.vue (novo),ConfigCondicoes.vue,PainelPasso.vue,NoPasso.vue,fluxo.js,validar.js}` + i18n `{en,pt_BR}/ramon.json` | o editor entende tudo isso |
| `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` | §16 Notas da B4.2 |

---

### Task 1: Módulo comum de migração (`Ramon::Fluxos::Migracao`) + Reunioes como 1º cliente + rake genérico

Refactor sem mudança de comportamento: a rede de segurança é a suíte da B4.1, que não muda.

**Files:**
- Create: `app/services/ramon/fluxos/migracao.rb`
- Modify: `app/services/ramon/fluxos/reunioes.rb` (arquivo inteiro)
- Modify: `app/services/ramon/fluxos/disparo.rb:41-45,87-90`
- Create: `lib/tasks/ramon_fluxos_migracao.rake`
- Test: `spec/services/ramon/fluxos/migracao_spec.rb` (novo); B4.1 sem edição: `spec/services/ramon/fluxos/reunioes_spec.rb`, `spec/services/ramon/reuniao_agendamento_spec.rb`, `spec/services/ramon/fluxos/{disparo,passos,comparar_agendamentos,comparar_lembretes}_spec.rb`

**Interfaces:**
- Produces (B4.2–B4.5 dependem disto; nome do grupo = `String`):
  - `Ramon::Fluxos::Migracao::GRUPOS` — `{ 'grupo' => { env: String, faz: String, fluxos: { sistema_chave => gatilho_tipo }, preparar: ->(account, desenho) { desenho } (opcional) } }`
  - `Migracao::PASTA` = `Rails.root.join('db/seeds/ramon/fluxos/migrados')` (desenho de cada fluxo em `<sistema_chave>.json`: `{nome, descricao, desenho}`)
  - `Migracao.grupo(nome) → Hash` (desconhecido → `ArgumentError` "Migração desconhecida: …")
  - `Migracao.gatilhos(nome) → Hash{String=>String}`
  - `Migracao.migrado?(fluxo) → Boolean` (origem `usuario` + `sistema_chave` de qualquer grupo)
  - `Migracao.ligada?(nome) → Boolean` (env do grupo `== 'on'`)
  - `Migracao.assumiu?(account, nome) → Boolean` (env ligada + todos os fluxos do grupo executáveis, `modo: normal`, `limite_dia: nil`, gatilho esperado)
  - `Migracao.fluxos(account, nome) → Relation`; `Migracao.fluxo(account, sistema_chave) → Fluxo|nil`
  - `Migracao.mudar_modo!(account, nome, modo) → Array<Fluxo>` (normal sem a env → `ArgumentError` com o nome da env)
  - `Migracao.descrever(account, nome) → String` ("Agora o CÓDIGO faz <faz> (os fluxos ensaiam)." / "Agora os FLUXOS fazem <faz> (o código não faz mais).")
  - `Migracao.semear(account, nome) → Array<Fluxo>` (cria em sombra, ligados e publicados; existente não é tocado)
  - rake `ramon:fluxos:migracao:criar[grupo,account_id]` e `ramon:fluxos:migracao:modo[grupo,account_id,modo]`
- Mantém (B4.1): `Reunioes::GATILHOS`, `Reunioes.assumiu?(account)`, `.fluxos(account)`, `.fluxo(account, chave)`, `.mudar_modo!(account, modo)`, `.descrever(account)`, `.semear(account)`, `.com_etapa(account, desenho)`, `.reuniao_aberta?`, `.destinatarios`, `.rastro!`, `.rastros`, `.na_agenda`. Saem (sem uso fora do próprio arquivo — conferido com grep): `Reunioes.migrado?` (o `Disparo` passa a usar `Migracao.migrado?`), `Reunioes.ligada?`, `Reunioes.criar`, `Reunioes::PASTA`.

- [ ] **Step 1: Write the failing test** — criar `spec/services/ramon/fluxos/migracao_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Migracao do
  let(:account) { create(:account) }

  it 'migração desconhecida é recusada com a lista das que existem' do
    expect { described_class.assumiu?(account, 'xyz') }.to raise_error(ArgumentError, /desconhecida: xyz.*reunioes/)
  end

  it 'migrado? = fluxo próprio (origem usuario) com a chave de uma migração; o desenho do sistema e os demais não' do
    expect(described_class.migrado?(Fluxo.new(origem: 'usuario', sistema_chave: 'lembretes_reuniao'))).to be(true)
    expect(described_class.migrado?(Fluxo.new(origem: 'sistema', sistema_chave: 'lembretes_reuniao'))).to be(false)
    expect(described_class.migrado?(Fluxo.new(origem: 'usuario', sistema_chave: nil))).to be(false)
  end

  it 'a API genérica e a das reuniões são a mesma coisa' do
    expect(described_class.gatilhos('reunioes')).to eq(Ramon::Fluxos::Reunioes::GATILHOS)
    expect(described_class.descrever(account, 'reunioes')).to eq('Agora o CÓDIGO faz o agendamento (os fluxos ensaiam).')
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/migracao_spec.rb`
Expected: FAIL — `uninitialized constant Ramon::Fluxos::Migracao`.

- [ ] **Step 3: Implementation**

(a) Criar `app/services/ramon/fluxos/migracao.rb`:

```ruby
# Migração 1 a 1 do código para fluxos (spec §8 B4+, §15 e §16): o que TODA migração precisa, num lugar só.
# Cada grupo é uma automação do código: a env que liga a troca, os fluxos que a substituem (sistema_chave → gatilho
# esperado; o desenho vem de db/seeds/ramon/fluxos/migrados/<sistema_chave>.json) e, se preciso, um ajuste do desenho
# por conta. A chave: env ligada E todos os fluxos do grupo ligados, publicados, em modo normal, com o gatilho esperado
# e sem limite do dia → os fluxos fazem e o código para; qualquer peça fora → o código faz e os fluxos só ensaiam.
# Migração nova (B4.3+): uma entrada em GRUPOS + o(s) JSON + o código lendo assumiu? UMA vez por evento.
module Ramon::Fluxos::Migracao
  PASTA = Rails.root.join('db/seeds/ramon/fluxos/migrados')
  GRUPOS = {
    'reunioes' => {
      env: 'RAMON_FLUXO_REUNIOES', faz: 'o agendamento',
      fluxos: { 'reuniao_marcada' => 'reuniao_marcada', 'reuniao_cancelada' => 'reuniao_cancelada',
                'lembretes_reuniao' => 'reuniao_na_agenda' },
      # mover_etapa vem sem etapa no JSON (a etapa é do funil de cada conta)
      preparar: ->(account, desenho) { Ramon::Fluxos::Reunioes.com_etapa(account, desenho) }
    }
  }.freeze

  module_function

  def grupo(nome) = GRUPOS.fetch(nome.to_s) { raise ArgumentError, "Migração desconhecida: #{nome} (há: #{GRUPOS.keys.join(', ')})" }

  def gatilhos(nome) = grupo(nome)[:fluxos]

  # Fluxo que substitui código (spec §14: fluxo próprio, origem 'usuario'), de qualquer migração.
  def migrado?(fluxo) = fluxo.origem == 'usuario' && GRUPOS.values.any? { |g| g[:fluxos].key?(fluxo.sistema_chave) }

  def ligada?(nome) = ENV.fetch(grupo(nome)[:env], nil) == 'on'

  # Sem limite do dia: com limite, o Disparo pularia o fluxo depois do N-ésimo evento e ninguém faria. Os filtros do
  # gatilho ficam a cargo do admin (E6: editar o fluxo pode tirar efeitos).
  def assumiu?(account, nome)
    return false unless ligada?(nome)

    atuais = account.fluxos.executaveis.where(origem: 'usuario', modo: 'normal', limite_dia: nil, sistema_chave: gatilhos(nome).keys)
                    .pluck(:sistema_chave, :gatilho_tipo)
    atuais.sort == gatilhos(nome).to_a.sort
  end

  def fluxos(account, nome) = account.fluxos.where(origem: 'usuario', sistema_chave: gatilhos(nome).keys).order(:id)

  def fluxo(account, chave) = account.fluxos.where(origem: 'usuario', sistema_chave: chave).order(:id).first

  # normal = os fluxos assumem; sombra = devolve ao código na hora. Todos os do grupo juntos.
  def mudar_modo!(account, nome, modo)
    lista = fluxos(account, nome).to_a
    raise ArgumentError, "Fluxos ainda não criados: rode ramon:fluxos:migracao:criar[#{nome},#{account.id}]" if lista.size < gatilhos(nome).size
    raise ArgumentError, "Ligue #{grupo(nome)[:env]}=on antes (sem ela o código continua fazendo tudo)" if modo == 'normal' && !ligada?(nome)

    Fluxo.transaction { lista.each { |fluxo| fluxo.update!(modo: modo) } }
    lista
  end

  def descrever(account, nome)
    faz = grupo(nome)[:faz]
    quem = assumiu?(account, nome) ? "os FLUXOS fazem #{faz} (o código não faz mais)" : "o CÓDIGO faz #{faz} (os fluxos ensaiam)"
    linhas = fluxos(account, nome).map { |f| "Fluxo ##{f.id} \"#{f.nome}\" — modo #{f.modo}, #{f.ativo ? 'ligado' : 'desligado'}" }
    [*linhas, "Agora #{quem}."].join("\n")
  end

  # Cria os que faltam, em sombra, ligados e publicados. Já existe → devolve sem tocar (o Eduardo pode ter editado).
  def semear(account, nome) = gatilhos(nome).keys.map { |chave| fluxo(account, chave) || criar(account, nome, chave) }

  def criar(account, nome, chave)
    dados = JSON.parse(PASTA.join("#{chave}.json").read)
    preparar = grupo(nome)[:preparar]
    desenho = preparar ? preparar.call(account, dados['desenho']) : dados['desenho']
    Fluxo.transaction do
      novo = account.fluxos.create!(nome: dados['nome'], descricao: dados['descricao'], origem: 'usuario', sistema_chave: chave,
                                    modo: 'sombra', ativo: true, rascunho: desenho)
      novo.publicar!(nil)
      novo.reload
    end
  end
end
```

(b) Substituir `app/services/ramon/fluxos/reunioes.rb` inteiro por (as regras de reunião e o rastro ficam iguais; a chave delega):

```ruby
# B4.1 (spec §8 e §15): o agendamento de reuniões (marcar, remarcar, cancelar e os 5 lembretes) saindo do código para
# fluxos. As regras de reunião moram aqui, uma vez só, e valem para os dois lados — o código (Ramon::MeetingReminderJob,
# Ramon::ReuniaoAgendamento) e os fluxos —, então a sombra compara exatamente a mesma regra.
# A chave e a semeadura são as de toda migração (Ramon::Fluxos::Migracao, grupo 'reunioes'); aqui só os atalhos.
module Ramon::Fluxos::Reunioes
  TOLERANCIA = 60.seconds
  GRUPO = 'reunioes'.freeze
  # Os 3 fluxos que substituem o código: sistema_chave → gatilho esperado.
  GATILHOS = Ramon::Fluxos::Migracao.gatilhos(GRUPO)
  RASTRO_RETENCAO = 8.days

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

  # Rastro do que o código avisou (a tabela notifications não serve: a deduplicação guarda só a última por pessoa).
  # Redis, 8 dias: grava o hash + 'em' (epoch) e apara o que passou da retenção.
  def rastro!(account, dados)
    agora = Time.current.to_f
    chave = chave_rastro(account)
    Redis::Alfred.zadd(chave, agora, dados.merge('em' => agora).to_json)
    Redis::Alfred.zremrangebyscore(chave, '-inf', "(#{agora - RASTRO_RETENCAO.to_f}")
    Redis::Alfred.expire(chave, RASTRO_RETENCAO.to_i)
  end

  # Entradas do rastro entre desde e ate (Time), da mais antiga para a mais nova.
  def rastros(account, desde, ate)
    Redis::Alfred.zrangebyscore(chave_rastro(account), desde.to_f, ate.to_f).map { |linha| JSON.parse(linha) }
  end

  def chave_rastro(account)
    "ramon:reunioes:rastro:#{account.id}"
  end

  # A reunião entrou na agenda (tarefa criada ou movida): começa o ciclo de lembretes DESSA reunião (alvo = a tarefa).
  # 'assumido' = a decisão do evento que a pôs na agenda (código ou fluxos no comando).
  def na_agenda(tarefa, assumido)
    dados = { 'inicio' => tarefa.due_at.iso8601, 'quando' => Ramon::ReuniaoAgendamento.quando(tarefa.due_at),
              'lead_id' => tarefa.lead_id, 'assumido' => assumido }
    Ramon::Fluxos::Disparo.externo('reuniao_na_agenda', tarefa, dados)
  end

  # A chave (B4.1): RAMON_FLUXO_REUNIOES=on E os 3 fluxos em modo normal (regras em Ramon::Fluxos::Migracao).
  def assumiu?(account) = Ramon::Fluxos::Migracao.assumiu?(account, GRUPO)

  def fluxos(account) = Ramon::Fluxos::Migracao.fluxos(account, GRUPO)

  def fluxo(account, chave) = Ramon::Fluxos::Migracao.fluxo(account, chave)

  def mudar_modo!(account, modo) = Ramon::Fluxos::Migracao.mudar_modo!(account, GRUPO, modo)

  def descrever(account) = Ramon::Fluxos::Migracao.descrever(account, GRUPO)

  def semear(account) = Ramon::Fluxos::Migracao.semear(account, GRUPO)

  # mover_etapa vem sem etapa no JSON (a etapa é do funil de cada conta): a "Reunião agendada" desta conta.
  def com_etapa(account, desenho)
    return desenho if desenho['nos'].none? { |n| n['tipo'] == 'mover_etapa' }

    etapa_id = account.lead_stages.find_by!(label: Ramon::ReuniaoAgendamento::STAGE_LABEL).id
    desenho.merge('nos' => desenho['nos'].map { |n| n['tipo'] == 'mover_etapa' ? n.deep_merge('config' => { 'etapa_id' => etapa_id }) : n })
  end
end
```

Conferência à mão do que a B4.1 testa: `GATILHOS` é o mesmo Hash congelado (`to_h`, `to_a`, `eq` no spec); `mudar_modo!(account, 'normal')` sem env → `ArgumentError` com "RAMON_FLUXO_REUNIOES" (regex do spec); `descrever` → "Agora o CÓDIGO faz o agendamento (os fluxos ensaiam)." (o spec usa `include('o CÓDIGO faz o agendamento')`); `semear` passa pelo `preparar` → `com_etapa` (o spec confere `etapa_id`); existente não é tocado.

(c) `app/services/ramon/fluxos/disparo.rb` — trocar as 3 referências a `Ramon::Fluxos::Reunioes.migrado?` por `Ramon::Fluxos::Migracao.migrado?`:

```ruby
  # B4.1: nos gatilhos NA_HORA o evento dispara 2 vezes. Antes dos efeitos, com 'assumido': só os fluxos migrados
  # (o ensaio vê o lead como estava). Depois dos efeitos, sem 'assumido': só os demais fluxos (veem o lead já mexido, como hoje).
  def self.da_vez?(fluxo, dados)
    NA_HORA.exclude?(fluxo.gatilho_tipo) || Ramon::Fluxos::Migracao.migrado?(fluxo) == dados.key?('assumido')
  end
```

```ruby
  def na_hora? = NA_HORA.include?(@fluxo.gatilho_tipo) && Ramon::Fluxos::Migracao.migrado?(@fluxo)

  # Fluxo migrado do código (B4+): quem decide se age é o evento ('assumido', lido 1 vez pelo código); os demais, o modo.
  def sombra? = Ramon::Fluxos::Migracao.migrado?(@fluxo) ? !@dados['assumido'] : @fluxo.modo == 'sombra'
```

(d) Criar `lib/tasks/ramon_fluxos_migracao.rake` (arquivo próprio: o `namespace :ramon` de `ramon_fluxos.rake` já está perto do `Metrics/BlockLength` 30; aquele arquivo **não muda**):

```ruby
# frozen_string_literal: true

# B4.2+: qualquer migração código → fluxo (Ramon::Fluxos::Migracao::GRUPOS — reunioes, sla, …).
# Operação de cada uma: o plano da fatia, seção "Operação depois do deploy".
namespace :ramon do
  namespace :fluxos do
    namespace :migracao do
      conta = ->(args) { Account.find(args[:account_id].presence || raise(ArgumentError, 'informe o account_id')) }

      desc 'Cria (uma vez) os fluxos de uma migracao, em SOMBRA. Uso: rake ramon:fluxos:migracao:criar[grupo,account_id]'
      task :criar, [:grupo, :account_id] => :environment do |_task, args|
        account = conta.call(args)
        Ramon::Fluxos::Migracao.semear(account, args[:grupo])
        puts Ramon::Fluxos::Migracao.descrever(account, args[:grupo])
      end

      desc 'normal = os fluxos assumem (exige a env do grupo =on); sombra = devolve ao codigo. ' \
           'Uso: rake ramon:fluxos:migracao:modo[grupo,account_id,normal]'
      task :modo, [:grupo, :account_id, :modo] => :environment do |_task, args|
        account = conta.call(args)
        Ramon::Fluxos::Migracao.mudar_modo!(account, args[:grupo], args[:modo])
        puts Ramon::Fluxos::Migracao.descrever(account, args[:grupo])
      end
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run (CI):
```bash
bundle exec rspec spec/services/ramon/fluxos/migracao_spec.rb spec/services/ramon/fluxos/reunioes_spec.rb spec/services/ramon/reuniao_agendamento_spec.rb spec/services/ramon/fluxos/disparo_spec.rb spec/services/ramon/fluxos/passos_spec.rb spec/services/ramon/fluxos/comparar_agendamentos_spec.rb spec/services/ramon/fluxos/comparar_lembretes_spec.rb
bundle exec rubocop app/services/ramon/fluxos/migracao.rb app/services/ramon/fluxos/reunioes.rb app/services/ramon/fluxos/disparo.rb lib/tasks/ramon_fluxos_migracao.rake
grep -rn "Reunioes\.\(migrado?\|ligada?\|criar\)\|Reunioes::PASTA" app lib spec
```
Expected: PASS (as specs da B4.1 sem nenhuma edição); rubocop sem ofensas; grep vazio.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/migracao.rb app/services/ramon/fluxos/reunioes.rb app/services/ramon/fluxos/disparo.rb lib/tasks/ramon_fluxos_migracao.rake spec/services/ramon/fluxos/migracao_spec.rb
git commit -m "refactor(fluxos): chave e semeadura das migrações num módulo comum (reuniões é o 1º cliente)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 2: Janela de horário por passo (`Ramon::Fluxos::Horario`) — condição, espera e validação

**Files:**
- Modify: `app/services/ramon/fluxos/horario.rb` (arquivo inteiro)
- Modify: `app/services/ramon/fluxos/condicao.rb` (linha `when 'em_horario_comercial'`)
- Modify: `app/services/ramon/fluxos/passos/logica.rb` (método `esperar`, linha do `ate`)
- Modify: `app/services/ramon/fluxos/grafo.rb` (`erros_se`, `erros_esperar`, novo `erros_janela`)
- Test: `spec/services/ramon/fluxos/horario_spec.rb`, `spec/services/ramon/fluxos/condicao_spec.rb`, `spec/services/ramon/fluxos/grafo_spec.rb`

**Interfaces:**
- Produces (a cadência da B4.3 reaproveita): janela = chaves `'dias'` (Array de 0–6, 0 = domingo), `'inicio'` (hora 0–23), `'fim'` (hora 1–24, exclusiva) **no próprio config** do passo `esperar {ate: 'horario_comercial'}` ou da condição `{operador: 'em_horario_comercial'}`; ausentes = padrão seg–sex 8h–18h.
  - `Ramon::Fluxos::Horario::DIAS = [1, 2, 3, 4, 5]`, `INICIO = 8`, `FIM = 18`, `ZONA = 'America/Sao_Paulo'`
  - `Horario.janela(config) → {dias: Array<Integer>, inicio: Integer, fim: Integer}` (config Hash de chaves String ou nil)
  - `Horario.janela_valida?(config) → Boolean`
  - `Horario.comercial?(momento, config = nil) → Boolean`; `Horario.proximo(momento, config = nil) → Time` (sem config = comportamento de hoje)
  - Grafo: mensagem `"Passo <id>: horário inválido (dias e início antes do fim)"`; front: código `JANELA_INVALIDA` (Task 5).

- [ ] **Step 1: Write the failing tests**

(a) Acrescentar a `spec/services/ramon/fluxos/horario_spec.rb`, antes do `end` final:

```ruby
  it 'janela própria do passo (B4.2): todos os dias, 7h–21h — como o SLA do código' do
    janela = { 'dias' => [0, 1, 2, 3, 4, 5, 6], 'inicio' => 7, 'fim' => 21 }
    expect(described_class.comercial?(sp('2026-10-10 07:00'), janela)).to be(true)  # sábado
    expect(described_class.comercial?(sp('2026-10-10 20:59'), janela)).to be(true)
    expect(described_class.comercial?(sp('2026-10-10 21:00'), janela)).to be(false)
    expect(described_class.comercial?(sp('2026-10-11 06:59'), janela)).to be(false) # domingo cedo
    expect(described_class.proximo(sp('2026-10-10 22:00'), janela)).to eq(sp('2026-10-11 07:00'))
    expect(described_class.proximo(sp('2026-10-10 05:00'), { 'dias' => [1], 'inicio' => 9, 'fim' => 12 })).to eq(sp('2026-10-12 09:00'))
  end

  it 'janela válida: ao menos 1 dia de 0 a 6, início antes do fim, fim até 24; sem chaves = o padrão' do
    expect(described_class.janela_valida?({})).to be(true)
    expect(described_class.janela_valida?({ 'dias' => [0, 6], 'inicio' => 0, 'fim' => 24 })).to be(true)
    expect(described_class.janela_valida?({ 'dias' => [] })).to be(false)
    expect(described_class.janela_valida?({ 'inicio' => 18, 'fim' => 8 })).to be(false)
    expect(described_class.janela_valida?({ 'dias' => [7] })).to be(false)
    expect(described_class.janela_valida?({ 'fim' => 25 })).to be(false)
  end
```

Rastreio: 2026-10-05 é segunda (o spec existente já usa) → 10 = sábado (wday 6), 11 = domingo (0), 12 = segunda (1). `proximo(sáb 22:00, todos 7–21)`: fora; 22 ≥ 7 → dia = 11; wday 0 está na lista → 11 às 07:00. `proximo(sáb 05:00, [1] 9–12)`: fora; 5 < 9 → dia = 10 (6) → 11 (0) → 12 (1) → 12 às 09:00. `janela_valida?({})`: sem 'dias' → DIAS; 8 ∈ 0...18 e 18 ≤ 24 → true. `{'dias' => []}` → `[].any?` false. `{18, 8}` → 18 ∉ 0...8. `{'dias' => [7]}` → `[7] - (0..6)` não vazio. `{'fim' => 25}` → 25 > 24.

(b) Acrescentar a `spec/services/ramon/fluxos/condicao_spec.rb`, antes do `end` final:

```ruby
  it 'agora é horário comercial: usa a janela da própria condição (B4.2)' do
    travel_to(Time.find_zone!('America/Sao_Paulo').parse('2026-10-10 20:30')) do # sábado, 20h30
      padrao = { 'campo' => 'status', 'operador' => 'em_horario_comercial', 'valor' => '' }
      expect(described_class.teste(padrao, {})).to be(false)
      expect(described_class.teste(padrao.merge('dias' => (0..6).to_a, 'inicio' => 7, 'fim' => 21), {})).to be(true)
    end
  end
```

(c) Acrescentar a `spec/services/ramon/fluxos/grafo_spec.rb`, antes do `end` final:

```ruby
  it 'janela de horário inválida no Se ou no Esperar até o horário recusa publicar (B4.2)' do
    hc = { 'campo' => 'status', 'operador' => 'em_horario_comercial', 'dias' => [], 'inicio' => 7, 'fim' => 21 }
    se = grafo(grafo_linear({ 'tipo' => 'manual' }, ['se', { 'condicoes' => [hc] }]))
    espera = grafo(grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'ate' => 'horario_comercial', 'inicio' => 20, 'fim' => 8 }]))
    boa = grafo(grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'ate' => 'horario_comercial', 'dias' => [0, 6], 'inicio' => 7, 'fim' => 21 }]))
    expect(se.erros).to include('Passo p1: horário inválido (dias e início antes do fim)')
    expect(espera.erros).to eq(['Passo p1: horário inválido (dias e início antes do fim)'])
    expect(boa.erros).to eq([])
  end
```

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/horario_spec.rb spec/services/ramon/fluxos/condicao_spec.rb spec/services/ramon/fluxos/grafo_spec.rb`
Expected: FAIL — `wrong number of arguments (given 2, expected 1)` em `comercial?`/`proximo`, `undefined method 'janela_valida?'`, e o grafo sem o erro de horário.

- [ ] **Step 3: Implementation**

(a) Substituir `app/services/ramon/fluxos/horario.rb` inteiro:

```ruby
# Horário comercial do escritório para fluxos (condição "agora é horário comercial" e "esperar até o horário comercial").
# B4.2: cada passo pode ter a SUA janela — 'dias' (0 = domingo … 6 = sábado), 'inicio' e 'fim' (horas; fim exclusivo,
# 24 = até a meia-noite) no config do passo ou da condição. Sem as chaves = o padrão seg–sex 8h–18h. Fuso de São Paulo.
module Ramon::Fluxos::Horario
  ZONA = 'America/Sao_Paulo'.freeze
  INICIO = 8
  FIM = 18
  DIAS = [1, 2, 3, 4, 5].freeze

  module_function

  # Dia fora de 0–6 é ignorado e lista vazia vira o padrão: o `until` de `proximo` nunca gira à toa.
  def janela(config)
    c = config || {}
    dias = Array(c['dias']).map(&:to_i) & (0..6).to_a
    { dias: dias.presence || DIAS, inicio: (c['inicio'] || INICIO).to_i, fim: (c['fim'] || FIM).to_i }
  end

  # Publicar recusa (Grafo#erros_janela): nenhum dia, dia fora de 0–6, início ≥ fim ou fim > 24.
  def janela_valida?(config)
    dias = config.key?('dias') ? Array(config['dias']).map(&:to_i) : DIAS
    j = janela(config)
    dias.any? && (dias - (0..6).to_a).empty? && (0...j[:fim]).cover?(j[:inicio]) && j[:fim] <= 24
  end

  def comercial?(momento, config = nil)
    j = janela(config)
    local = momento.in_time_zone(ZONA)
    j[:dias].include?(local.wday) && local.hour >= j[:inicio] && local.hour < j[:fim]
  end

  def proximo(momento, config = nil)
    return momento if comercial?(momento, config)

    j = janela(config)
    local = momento.in_time_zone(ZONA)
    dia = local.hour < j[:inicio] ? local.to_date : local.to_date + 1
    dia += 1 until j[:dias].include?(dia.wday)
    Time.find_zone!(ZONA).local(dia.year, dia.month, dia.day, j[:inicio])
  end
end
```

Rastreio do spec antigo (sem janela): `janela(nil)` = seg–sex 8–18 → mesmos resultados (`proximo(seg 07:10)` = seg 08:00; `seg 19:00` → ter 08:00; `sex 18:30` → seg 08:00; `seg 10:00` → ele mesmo).

(b) `app/services/ramon/fluxos/condicao.rb` — trocar a linha:

```ruby
    when 'em_horario_comercial' then Ramon::Fluxos::Horario.comercial?(Time.current)
```
por:
```ruby
    when 'em_horario_comercial' then Ramon::Fluxos::Horario.comercial?(Time.current, condicao) # B4.2: janela da condição
```

(c) `app/services/ramon/fluxos/passos/logica.rb` — no método `esperar`, trocar:

```ruby
    ate = config['ate'] == 'horario_comercial' ? Ramon::Fluxos::Horario.proximo(Time.current) : Time.current + duracao(config)
```
por:
```ruby
    ate = config['ate'] == 'horario_comercial' ? Ramon::Fluxos::Horario.proximo(Time.current, config) : Time.current + duracao(config)
```

(d) `app/services/ramon/fluxos/grafo.rb` — substituir `erros_se` e `erros_esperar` e acrescentar `erros_janela` logo abaixo de `erros_esperar`:

```ruby
  def erros_se(passo, config)
    erros = Array(config['condicoes']).empty? ? ["Passo #{passo['id']} (Se) precisa de condições"] : []
    horarios = Array(config['condicoes']).select { |c| c['operador'] == 'em_horario_comercial' }
    erros + horarios.flat_map { |c| erros_janela(passo, c) } + erros_saida(passo, config)
  end
```

```ruby
  def erros_esperar(passo, config)
    erros = espera_valida?(config) ? [] : ["Passo #{passo['id']}: falta o tempo de espera"]
    config['ate'] == 'horario_comercial' ? erros + erros_janela(passo, config) : erros
  end

  # B4.2: janela de horário do próprio passo (Ramon::Fluxos::Horario.janela_valida?)
  def erros_janela(passo, config)
    Ramon::Fluxos::Horario.janela_valida?(config) ? [] : ["Passo #{passo['id']}: horário inválido (dias e início antes do fim)"]
  end
```

Rastreio do spec (c): `se` com `dias: []` → erros = [] (tem condição) + ["…horário inválido…"] + ["Passo p1 (Se) precisa de pelo menos uma saída"] (p1 é o último) → `include` passa. `espera` `{inicio: 20, fim: 8}` → `espera_valida?` true (ate = horario_comercial) + janela inválida → exatamente 1 erro. `boa` → [].

- [ ] **Step 4: Run to verify they pass**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/horario_spec.rb spec/services/ramon/fluxos/condicao_spec.rb spec/services/ramon/fluxos/grafo_spec.rb spec/services/ramon/fluxos/passos_spec.rb` e `bundle exec rubocop app/services/ramon/fluxos/horario.rb app/services/ramon/fluxos/condicao.rb app/services/ramon/fluxos/passos/logica.rb app/services/ramon/fluxos/grafo.rb`
Expected: PASS; sem ofensas (`grafo.rb` ~155 linhas de código < 175; `janela_valida?` complexidade 6 ≤ 7).

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/horario.rb app/services/ramon/fluxos/condicao.rb app/services/ramon/fluxos/passos/logica.rb app/services/ramon/fluxos/grafo.rb spec/services/ramon/fluxos/horario_spec.rb spec/services/ramon/fluxos/condicao_spec.rb spec/services/ramon/fluxos/grafo_spec.rb
git commit -m "feat(fluxos): horário comercial com janela própria em cada passo (dias e das/até)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 3: Motor — esperar a partir da criação da conversa (SLA da caixa), `{primeira_resposta}`, `{sla_minutos}` e sino para SDR/gestores

**Files:**
- Modify: `app/services/ramon/fluxos/passos/logica.rb` (`esperar`, `esperar_reuniao`, novos `esperar_conversa` e `ate_ou_passou`)
- Modify: `app/services/ramon/fluxos/contexto.rb` (`DO_GATILHO`/`RESERVADAS`, `dados`, novo `dados_sla`)
- Modify: `app/services/ramon/fluxos/passos/aviso.rb` (`destinatarios` → tabela `PARA`)
- Modify: `app/services/ramon/fluxos/grafo.rb` (`espera_valida?`)
- Test: `spec/services/ramon/fluxos/passos_spec.rb`, `spec/services/ramon/fluxos/grafo_spec.rb`

**Interfaces:**
- Consumes: nada das tasks anteriores (independe da Task 2 exceto por tocar `grafo.rb`/`logica.rb` em linhas diferentes).
- Produces:
  - passo `esperar {desde: 'conversa', quantidade:, unidade:}` e `esperar {desde: 'conversa', prazo: 'sla_caixa'}` → `esperar_ate` = `conversa.created_at` + tempo; já passado → sem espera e `vars: {'horario_passou' => 'sim'}` (senão `'nao'`); sem conversa → `PassoImpossivel`.
  - variáveis de contexto `'primeira_resposta'` (`'sim'|'nao'`, `nil` sem conversa) e `'sla_minutos'` (Integer, `nil` sem conversa) — ambas em `Contexto::RESERVADAS`.
  - `Ramon::Fluxos::Passos::Aviso::PARA` — `{'closer_e_sdr', 'conta', 'sdr_ou_gestores', 'gestores'} → ->(lead) { user_ids }`; `Aviso.destinatarios(lead, config) → Array<Integer>` (mesma assinatura).

- [ ] **Step 1: Write the failing tests** — acrescentar a `spec/services/ramon/fluxos/passos_spec.rb`, antes do `end` final:

```ruby
  describe 'SLA da 1ª resposta (B4.2)' do
    it 'esperar a partir da criação da conversa: o SLA da caixa ou um tempo; já passou → segue e marca horario_passou' do
      conversa.inbox.update!(first_response_sla_minutes: 15)
      criada = conversa.reload.created_at
      c = ctx(alvo: conversa)
      sla = Ramon::Fluxos::Passos::Logica.esperar({ 'desde' => 'conversa', 'prazo' => 'sla_caixa' }, c)
      expect(sla).to include(esperar_ate: criada + 15.minutes, vars: { 'horario_passou' => 'nao' })
      travel_to(criada + 61.minutes) do
        tarde = Ramon::Fluxos::Passos::Logica.esperar({ 'desde' => 'conversa', 'quantidade' => 60, 'unidade' => 'minutos' }, c)
        expect(tarde).to include(vars: { 'horario_passou' => 'sim' })
        expect(tarde).not_to have_key(:esperar_ate)
      end
    end

    it 'variáveis {primeira_resposta} e {sla_minutos} (o SLA da caixa, como o código)' do
      conversa.inbox.update!(first_response_sla_minutes: 15)
      expect(ctx(alvo: conversa).dados.slice('primeira_resposta', 'sla_minutos')).to eq('primeira_resposta' => 'nao', 'sla_minutos' => 15)
      conversa.update!(first_reply_created_at: Time.current)
      expect(ctx(alvo: conversa, ensaio: true).dados['primeira_resposta']).to eq('sim')
    end

    it 'sino para o SDR do lead (sem SDR: gestores) e para os gestores' do
      sdr = create(:user, account: account, role: :agent)
      gestor = create(:user, account: account, role: :administrator)
      para = ->(quem) { Ramon::Fluxos::Passos::Aviso.destinatarios(lead.reload, { 'para' => quem }) }
      expect(para.call('sdr_ou_gestores')).to eq([gestor.id])
      lead.update!(sdr_id: sdr.id)
      expect(para.call('sdr_ou_gestores')).to eq([sdr.id])
      expect(para.call('gestores')).to eq([gestor.id])
    end
  end
```

E a `spec/services/ramon/fluxos/grafo_spec.rb`, antes do `end` final:

```ruby
  it 'esperar o SLA da caixa (a partir da criação da conversa) vale como tempo de espera (B4.2)' do
    expect(grafo(grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'desde' => 'conversa', 'prazo' => 'sla_caixa' }])).erros).to eq([])
  end
```

Rastreio: o 1º exemplo cria **uma** execução viva (`ctx` uma vez, reusada). `conversa.reload.created_at` = o que o `execucao.alvo` carrega do banco (mesma precisão). O 2º exemplo: 1 execução normal + 1 ensaio (o ensaio fica fora do índice único). A conversa da factory começa `open` e sem `first_reply_created_at`. `lead` (let) liga a conversa; `create(:user, account:, role:)` cria o `account_user` (como na B4.1).

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/passos_spec.rb spec/services/ramon/fluxos/grafo_spec.rb`
Expected: FAIL — `esperar` ignora `desde` (conta do passo anterior: `KeyError` em `UNIDADES.fetch(nil)` no 1º), `dados` sem as chaves novas, `destinatarios` cai no "responsável do lead", e o grafo acusa "falta o tempo de espera".

- [ ] **Step 3: Implementation**

(a) `app/services/ramon/fluxos/passos/logica.rb` — substituir `esperar` e `esperar_reuniao` (a linha do `ate` já vem da Task 2) por:

```ruby
  def esperar(config, ctx)
    return esperar_reuniao(config, ctx) if config['antes_de'] == 'reuniao'
    return esperar_conversa(config, ctx) if config['desde'] == 'conversa'

    ate = config['ate'] == 'horario_comercial' ? Ramon::Fluxos::Horario.proximo(Time.current, config) : Time.current + duracao(config)
    { saida: 's', resumo: "espera até #{hora(ate)}", esperar_ate: ate }
  end

  # B4.1: conta para TRÁS a partir da reunião (lembretes). Momento já passado → não espera e marca
  # {horario_passou} = sim; o `se` seguinte pula o aviso — como o código, que só agenda os lembretes ainda futuros.
  def esperar_reuniao(config, ctx)
    inicio = ctx.reuniao_em || raise(Ramon::Fluxos::PassoImpossivel, 'sem reunião marcada para contar o tempo')
    ate_ou_passou(inicio - duracao(config))
  end

  # B4.2: conta a partir da CRIAÇÃO da conversa (SLA da 1ª resposta). prazo 'sla_caixa' = o SLA da caixa da conversa
  # (Ramon::Cadencia.sla_minutes, a mesma regra do código). Já passou → segue e marca {horario_passou} = sim
  # (a escalada de 60 min do código só é agendada se ainda for futura).
  def esperar_conversa(config, ctx)
    conversa = ctx.conversa || raise(Ramon::Fluxos::PassoImpossivel, 'sem conversa para contar o tempo')
    tempo = config['prazo'] == 'sla_caixa' ? Ramon::Cadencia.sla_minutes(conversa.inbox).minutes : duracao(config)
    ate_ou_passou(conversa.created_at + tempo)
  end

  def ate_ou_passou(ate)
    return { saida: 's', resumo: "#{hora(ate)} já passou: segue sem esperar", vars: { 'horario_passou' => 'sim' } } if ate.past?

    { saida: 's', resumo: "espera até #{hora(ate)}", esperar_ate: ate, vars: { 'horario_passou' => 'nao' } }
  end
```

(`esperar_reuniao` devolve exatamente os mesmos hashes de antes — o spec da B4.1 que confere "já passou: segue sem esperar" continua igual.)

(b) `app/services/ramon/fluxos/contexto.rb`:

- em `RESERVADAS`, trocar `resposta_ia reuniao_de_pe horario_passou]).freeze` por `resposta_ia reuniao_de_pe horario_passou primeira_resposta sla_minutos]).freeze`;
- em `dados`, trocar `dados_reuniao, dados_gatilho,` por `dados_reuniao, dados_sla, dados_gatilho,`;
- acrescentar, logo abaixo de `dados_conversa`:

```ruby
  # B4.2: SLA da 1ª resposta — as mesmas regras do código (Ramon::FirstResponseSlaJob, Ramon::Cadencia.sla_minutes).
  def dados_sla
    c = conversa
    return { 'primeira_resposta' => nil, 'sla_minutos' => nil } if c.nil?

    { 'primeira_resposta' => c.first_reply_created_at.present? ? 'sim' : 'nao', 'sla_minutos' => Ramon::Cadencia.sla_minutes(c.inbox) }
  end
```

(c) `app/services/ramon/fluxos/passos/aviso.rb` — substituir o comentário e o método `destinatarios` por (a tabela mantém o `case` dentro do limite de complexidade 7):

```ruby
  # Quem recebe por papel. B4.1: 'closer_e_sdr' = a regra do lembrete de reunião; 'conta' = todo mundo (reunião
  # marcada/cancelada). B4.2: 'sdr_ou_gestores' / 'gestores' = o SLA da 1ª resposta (Ramon::Papeis.gestor_ids).
  PARA = {
    'closer_e_sdr' => ->(lead) { Ramon::Fluxos::Reunioes.destinatarios(lead) },
    'conta' => ->(lead) { lead.account.account_users.pluck(:user_id) },
    'sdr_ou_gestores' => ->(lead) { lead.sdr_id ? [lead.sdr_id] : Ramon::Papeis.gestor_ids(lead.account) },
    'gestores' => ->(lead) { Ramon::Papeis.gestor_ids(lead.account) }
  }.freeze

  # Só gente da conta. Lista vazia nunca chega ao builder: lá ela vira "todo mundo".
  def destinatarios(lead, config)
    regra = PARA[config['para']]
    ids = regra ? regra.call(lead) : Array(config['user_ids']).map(&:to_i).presence || [(lead.closer || lead.sdr)&.id]
    ids.compact & lead.account.account_users.pluck(:user_id)
  end
```

Coloque `PARA` logo abaixo de `module Ramon::Fluxos::Passos::Aviso` (antes de `module_function`). Precedência: `regra ? a : (b || c)` — o ternário tem precedência menor que `||`.

(d) `app/services/ramon/fluxos/grafo.rb` — `espera_valida?`:

```ruby
  def espera_valida?(config)
    config['ate'] == 'horario_comercial' || config['prazo'] == 'sla_caixa' ||
      (config['quantidade'].to_i.positive? && %w[minutos horas dias].include?(config['unidade']))
  end
```

- [ ] **Step 4: Run to verify they pass**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/passos_spec.rb spec/services/ramon/fluxos/grafo_spec.rb spec/services/ramon/fluxos/contexto_spec.rb spec/services/ramon/fluxos/reunioes_spec.rb` e `bundle exec rubocop app/services/ramon/fluxos/passos/logica.rb app/services/ramon/fluxos/contexto.rb app/services/ramon/fluxos/passos/aviso.rb app/services/ramon/fluxos/grafo.rb`
Expected: PASS (os sinos `closer_e_sdr`/`conta` da B4.1 seguem iguais); sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/passos/logica.rb app/services/ramon/fluxos/contexto.rb app/services/ramon/fluxos/passos/aviso.rb app/services/ramon/fluxos/grafo.rb spec/services/ramon/fluxos/passos_spec.rb spec/services/ramon/fluxos/grafo_spec.rb
git commit -m "feat(fluxos): esperar desde a criação da conversa (SLA da caixa), 1ª resposta e sino para SDR/gestores" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 4: O fluxo "SLA da 1ª resposta" + a decisão por conversa nova + ponta a ponta

**Files:**
- Create: `db/seeds/ramon/fluxos/migrados/sla_primeira_resposta.json`
- Modify: `app/services/ramon/fluxos/migracao.rb` (`GRUPOS` ganha `'sla'`)
- Modify: `app/services/ramon/fluxos/disparo.rb` (`DUAS_VEZES`, `da_vez?`)
- Modify: `app/listeners/ramon_lead_listener.rb` (`enqueue_first_response_sla`)
- Modify: `.env.example` (depois do bloco `RAMON_FLUXO_REUNIOES`, ~linha 304)
- Test: `spec/listeners/ramon_lead_listener_spec.rb`, `spec/services/ramon/fluxos/migracao_spec.rb`

**Interfaces:**
- Consumes: `Migracao.{semear,mudar_modo!,assumiu?,descrever}` (Task 1); janela por condição (Task 2); `esperar {desde, prazo}`, `{primeira_resposta}`, `{sla_minutos}`, `para: sdr_ou_gestores|gestores` (Task 3).
- Produces: grupo `'sla'` (`env: 'RAMON_FLUXO_SLA'`, fluxo `sla_primeira_resposta` → `conversa_criada`); `Ramon::Fluxos::Disparo::DUAS_VEZES = %w[reuniao_marcada reuniao_cancelada conversa_criada]`; gatilho `conversa_criada` com dados `{'caixa_id', 'assumido'}` vindo do `RamonLeadListener`.

- [ ] **Step 1: Write the failing tests**

(a) Acrescentar a `spec/services/ramon/fluxos/migracao_spec.rb`, antes do `end` final:

```ruby
  it 'SLA (B4.2): criar = 1 fluxo em sombra, ligado e publicado; virar exige RAMON_FLUXO_SLA; cada migração tem a sua chave' do
    fluxos = described_class.semear(account, 'sla')
    expect(fluxos.map { |f| [f.sistema_chave, f.gatilho_tipo, f.modo, f.ativo, f.versao_publicada_id.present?] })
      .to eq([['sla_primeira_resposta', 'conversa_criada', 'sombra', true, true]])
    expect { described_class.mudar_modo!(account, 'sla', 'normal') }.to raise_error(ArgumentError, /RAMON_FLUXO_SLA/)
    with_modified_env(RAMON_FLUXO_SLA: 'on') do
      expect(described_class.assumiu?(account, 'sla')).to be(false) # ainda em sombra
      described_class.mudar_modo!(account, 'sla', 'normal')
      expect(described_class.assumiu?(account, 'sla')).to be(true)
      expect(described_class.assumiu?(account, 'reunioes')).to be(false)
    end
    expect(described_class.descrever(account, 'sla')).to include('Agora o CÓDIGO faz o aviso de SLA da 1ª resposta')
  end
```

(b) Acrescentar a `spec/listeners/ramon_lead_listener_spec.rb`, antes do `end` final (usa os `let` do topo: `listener`, `account`, `inbox` com `auto_create_lead`, `contact` "Maria", `conversation`, `event` — a conversa nasce no primeiro uso, dentro do `travel_to`):

```ruby
  describe 'SLA da 1ª resposta pelo fluxo (B4.2)' do
    let(:sdr) { create(:user, account: account, role: :agent, name: 'Sara SDR') }
    let!(:gestor) { create(:user, account: account, role: :administrator, name: 'Gil Gestor') }
    let(:fluxo) { Ramon::Fluxos::Migracao.semear(account, 'sla').first }
    let(:dez) { Time.zone.parse('2026-10-05 13:00:00 UTC') } # segunda, 10h em São Paulo

    # O relógio dos fluxos (Ramon::FluxoRelogioJob) sem o resto: anda o que venceu.
    def relogio
      FluxoExecucao.where(status: 'esperando', retomar_em: ..Time.current).find_each { |e| Ramon::Fluxos::Executor.new(e).avancar! }
    end

    def avisos = Notification.where(notification_type: 'ramon_fluxo_aviso').order(:id).map { |n| [n.user_id, n.meta['label']] }

    def trilha = FluxoExecucao.where(fluxo: fluxo).order(:id).flat_map(&:trilha).pluck('resumo')

    def nascer(momento = dez)
      travel_to(momento) do
        listener.conversation_created(event)
        relogio
      end
    end

    it 'sem a chave: o código vigia como sempre e o fluxo só ensaia (nunca os dois)' do
      fluxo
      travel_to(dez) do
        expect { listener.conversation_created(event) }.to have_enqueued_job(Ramon::FirstResponseSlaJob).with(conversation.id)
        relogio
      end
      travel_to(dez + 5.minutes + 30.seconds) { relogio }
      expect(FluxoExecucao.where(fluxo: fluxo).pluck(:ensaio)).to eq([true])
      expect(trilha).to include('faria: sino para Gil Gestor: "Lead aguardando 1ª resposta há 5 min: Maria"')
      expect(avisos).to be_empty
    end

    it 'o ouvinte geral (Conversa criada) não inicia o fluxo do SLA; o disparo do SLA não inicia os fluxos comuns' do
      fluxo
      comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'conversa_criada' }, ['parar', {}]))
      travel_to(dez) do
        RamonFluxoListener.instance.conversation_created(event)
        listener.conversation_created(event)
      end
      expect(FluxoExecucao.where(fluxo: comum).count).to eq(1)
      expect(FluxoExecucao.where(fluxo: fluxo).count).to eq(1)
    end

    context 'com a chave (RAMON_FLUXO_SLA=on + o fluxo em modo normal)' do
      around { |ex| with_modified_env(RAMON_FLUXO_SLA: 'on') { ex.run } }

      before do
        fluxo
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'sla', 'normal')
      end

      it 'o fluxo vigia e o código não: SDR no prazo da caixa (com push), gestores aos 60 min (sem push)' do
        allow(Ramon::NtfyPushJob).to receive(:perform_later)
        travel_to(dez) do
          expect { listener.conversation_created(event) }.not_to have_enqueued_job(Ramon::FirstResponseSlaJob)
          account.leads.find_by!(conversation_id: conversation.id).update!(sdr_id: sdr.id)
          relogio
        end
        travel_to(dez + 5.minutes + 30.seconds) { relogio }
        travel_to(dez + 60.minutes + 30.seconds) { relogio }
        expect(avisos).to eq([[sdr.id, 'Lead aguardando 1ª resposta há 5 min: Maria'],
                              [gestor.id, 'Lead aguardando 1ª resposta há 60 min: Maria']])
        expect(Ramon::NtfyPushJob).to have_received(:perform_later)
          .with(title: 'Lead aguardando 1a resposta', body: 'Lead aguardando 1ª resposta há 5min: Maria').once
        expect(FluxoExecucao.where(fluxo: fluxo).pluck(:ensaio, :status)).to eq([[false, 'concluida']])
      end

      it 'respondeu antes do prazo: nada (nem aviso, nem escalada)' do
        nascer
        travel_to(dez + 2.minutes) { conversation.update!(first_reply_created_at: Time.current) }
        travel_to(dez + 5.minutes + 30.seconds) { relogio }
        expect(avisos).to be_empty
        expect(FluxoExecucao.where(fluxo: fluxo).pluck(:status)).to eq(['concluida'])
      end

      it 'aviso só no horário do passo (7h–21h, todo dia); a escalada é esperada mesmo fora dele' do
        cedo = Time.zone.parse('2026-10-05 09:30:00 UTC') # 6h30 em São Paulo
        nascer(cedo)
        travel_to(cedo + 5.minutes + 30.seconds) { relogio }  # 6h35: fora → sem aviso, segue para a escalada
        travel_to(cedo + 60.minutes + 30.seconds) { relogio } # 7h30: dentro → gestores
        expect(avisos).to eq([[gestor.id, 'Lead aguardando 1ª resposta há 60 min: Maria']])
      end

      it 'caixa com SLA de 60 min: aviso aos 60 e sem escalada (como o código)' do
        inbox.update!(first_response_sla_minutes: 60)
        nascer
        travel_to(dez + 60.minutes + 30.seconds) { relogio }
        expect(trilha.grep(/\Asino:/)).to eq(['sino: Lead aguardando 1ª resposta há 60 min: Maria'])
        expect(trilha).to include(a_string_ending_with('já passou: segue sem esperar'))
        expect(FluxoExecucao.where(fluxo: fluxo).pluck(:status)).to eq(['concluida'])
      end

      it 'voltar para sombra: conversa nova volta ao código na hora; a que o fluxo já vigiava termina pelo fluxo' do
        nascer
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'sla', 'sombra')
        travel_to(dez + 1.minute) do
          outra = create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account, name: 'Joana'))
          nova = Events::Base.new('conversation.created', Time.zone.now, conversation: outra)
          expect { listener.conversation_created(nova) }.to have_enqueued_job(Ramon::FirstResponseSlaJob).with(outra.id)
        end
        travel_to(dez + 5.minutes + 30.seconds) { relogio }
        expect(FluxoExecucao.where(fluxo: fluxo).order(:id).pluck(:ensaio)).to eq([false, true])
        expect(avisos).to eq([[gestor.id, 'Lead aguardando 1ª resposta há 5 min: Maria']])
      end

      it 'fluxo no comando que não pega a conversa (filtro de caixa editado) devolve aquela conversa ao código' do
        desenho = fluxo.reload.rascunho.deep_dup
        desenho['nos'].first['config']['caixa_ids'] = [inbox.id + 1]
        fluxo.update!(rascunho: desenho)
        fluxo.publicar!(nil)
        travel_to(dez) { expect { listener.conversation_created(event) }.to have_enqueued_job(Ramon::FirstResponseSlaJob) }
        expect(FluxoExecucao.where(fluxo: fluxo)).to be_empty
      end
    end
  end
```

Rastreio do exemplo principal (fluxo no comando, conversa às 10h00 de segunda):
1. `conversation_created` → lead criado na 1ª etapa; `assumiu?` = true (env + normal + sem limite + gatilho `conversa_criada`) → `Disparo.externo('conversa_criada', conversa, {'caixa_id', 'assumido' => true})` → `da_vez?` (`conversa_criada` ∈ `DUAS_VEZES`, migrado? true == key? true) → execução não-ensaio (`sombra?` = `!true`), `esperando`, `retomar_em` = agora; `FluxoAvancarJob` só enfileira. `vigias.any?` → true → **sem** job do código.
2. `relogio` às 10h00: n2 `esperar desde conversa, prazo sla_caixa` → `created_at + 5 min` (env de teste sem `RAMON_SLA_FIRST_RESPONSE_MINUTES` → padrão '5') → futuro → `esperando` até 10h05.
3. 10h05m30: n3 `se` — `primeira_resposta` 'nao', `status` 'open', `etapa` = nome da 1ª etapa (existe) → sim → n4 `em_horario_comercial` com janela 0–6/7–21 → 10h05 → sim → n5 sino `sdr_ou_gestores` → `[sdr.id]` → label "Lead aguardando 1ª resposta há 5 min: Maria" (`{sla_minutos}` = 5, `{nome_completo}` = nome do contato) → n6 push `perform_later(title: 'Lead aguardando 1a resposta', body: '…há 5min: Maria')` → n7 `esperar desde conversa 60 min` → 11h00 futuro → `horario_passou` 'nao', `esperando`.
4. 11h00m30: n8 (`horario_passou` nao, sem resposta, aberta, com lead) → n9 (11h00 dentro) → n10 sino `gestores` → `[gestor.id]` → fim → `concluida`.
`cancelar_se_sair_da_etapa: false` no gatilho → mudar a etapa não cancela. O `sdr` é `agent` da conta (está em `account_users`).

"Voltar para sombra": a 1ª conversa (Maria, 10h00) nasce com o fluxo no comando (execução real); depois do rake para sombra, `assumiu?` = false → a 2ª (Joana, 10h01) → ensaio + job do código. Às 10h05m30 a execução de Maria (real) avisa os gestores (sem SDR); a de Joana (ensaio, ainda não rodou o 1º passo — o relógio a pega e ela passa a esperar até 10h06) não avisa ninguém de verdade — `pluck(:ensaio)` = `[false, true]`; só 1 aviso.

"Filtro editado": `caixa_ids` = outra caixa → `filtro_ok?` falso → `Disparo.call` devolve `[]` → `assumido && [].any?` falso → o código agenda.

"O ouvinte geral": `RamonFluxoListener` dispara `conversa_criada` sem `assumido` → `da_vez?`: comum (migrado? false == key? false) ✓; SLA (true == false) ✗. O `RamonLeadListener` dispara com `assumido` → comum ✗; SLA ✓ (em sombra: ensaio). 1 execução cada.

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/listeners/ramon_lead_listener_spec.rb spec/services/ramon/fluxos/migracao_spec.rb`
Expected: FAIL — `Migração desconhecida: sla`.

- [ ] **Step 3: Implementation**

(a) Criar `db/seeds/ramon/fluxos/migrados/sla_primeira_resposta.json`:

```json
{
  "nome": "SLA da 1ª resposta",
  "descricao": "Migrado do código (B4.2). Conversa nova numa caixa com Criar lead → espera o SLA da caixa → se continua sem 1ª resposta, aberta e com lead, avisa o SDR do lead (sem SDR: os gestores) e manda o push, das 7h às 21h, todo dia → aos 60 min da criação da conversa, se continuar assim, avisa os gestores. Fora do horário o aviso é pulado, mas a escalada continua esperando. Quem dispara é o ouvinte de leads (onde o código agendava). Mudar o horário, os textos ou quem recebe muda o aviso de verdade.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"conversa_criada","cancelar_se_sair_da_etapa":false},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"esperar","config":{"rotulo":"SLA da caixa","desde":"conversa","prazo":"sla_caixa"},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"se","config":{"rotulo":"Ainda sem 1ª resposta, aberta e com lead?","juncao":"e","condicoes":[{"campo":"primeira_resposta","operador":"igual","valor":"nao"},{"campo":"status","operador":"igual","valor":"open"},{"campo":"etapa","operador":"existe","valor":""}]},"posicao":{"x":0,"y":280}},
      {"id":"n4","tipo":"se","config":{"rotulo":"Entre 7h e 21h?","juncao":"e","condicoes":[{"campo":"status","operador":"em_horario_comercial","valor":"","dias":[0,1,2,3,4,5,6],"inicio":7,"fim":21}]},"posicao":{"x":-130,"y":440}},
      {"id":"n5","tipo":"avisar_sino","config":{"rotulo":"Sino do SDR (sem SDR: gestores)","para":"sdr_ou_gestores","texto":"Lead aguardando 1ª resposta há {sla_minutos} min: {nome_completo}"},"posicao":{"x":-260,"y":600}},
      {"id":"n6","tipo":"avisar_push","config":{"rotulo":"Push: lead aguardando","titulo":"Lead aguardando 1a resposta","texto":"Lead aguardando 1ª resposta há {sla_minutos}min: {nome_completo}"},"posicao":{"x":-260,"y":740}},
      {"id":"n7","tipo":"esperar","config":{"rotulo":"Até 60 min da criação da conversa","desde":"conversa","quantidade":60,"unidade":"minutos"},"posicao":{"x":0,"y":880}},
      {"id":"n8","tipo":"se","config":{"rotulo":"A escalada ainda vale? Sem 1ª resposta, aberta e com lead?","juncao":"e","condicoes":[{"campo":"horario_passou","operador":"igual","valor":"nao"},{"campo":"primeira_resposta","operador":"igual","valor":"nao"},{"campo":"status","operador":"igual","valor":"open"},{"campo":"etapa","operador":"existe","valor":""}]},"posicao":{"x":0,"y":1020}},
      {"id":"n9","tipo":"se","config":{"rotulo":"Entre 7h e 21h?","juncao":"e","condicoes":[{"campo":"status","operador":"em_horario_comercial","valor":"","dias":[0,1,2,3,4,5,6],"inicio":7,"fim":21}]},"posicao":{"x":-130,"y":1180}},
      {"id":"n10","tipo":"avisar_sino","config":{"rotulo":"Escalada: sino dos gestores","para":"gestores","texto":"Lead aguardando 1ª resposta há 60 min: {nome_completo}"},"posicao":{"x":-260,"y":1340}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"s","para":"n3"},
      {"de":"n3","saida":"sim","para":"n4"},
      {"de":"n4","saida":"sim","para":"n5"},
      {"de":"n4","saida":"nao","para":"n7"},
      {"de":"n5","saida":"s","para":"n6"},
      {"de":"n6","saida":"s","para":"n7"},
      {"de":"n7","saida":"s","para":"n8"},
      {"de":"n8","saida":"sim","para":"n9"},
      {"de":"n9","saida":"sim","para":"n10"}
    ]
  }
}
```

Conferência do `Grafo#erros` (o `semear` publica): 1 gatilho conhecido; sem ciclo; todos alcançáveis; cada `se` com ≥ 1 seta; `avisar_sino`/`avisar_push` com `texto`; `esperar` n2 válido pelo `prazo: 'sla_caixa'` (Task 3) e n7 por `quantidade/unidade`; janelas 0–6/7–21 válidas (Task 2).

(b) `app/services/ramon/fluxos/migracao.rb` — `GRUPOS` inteiro passa a ser (entrada `'sla'` nova, sem `preparar`):

```ruby
  GRUPOS = {
    'reunioes' => {
      env: 'RAMON_FLUXO_REUNIOES', faz: 'o agendamento',
      fluxos: { 'reuniao_marcada' => 'reuniao_marcada', 'reuniao_cancelada' => 'reuniao_cancelada',
                'lembretes_reuniao' => 'reuniao_na_agenda' },
      # mover_etapa vem sem etapa no JSON (a etapa é do funil de cada conta)
      preparar: ->(account, desenho) { Ramon::Fluxos::Reunioes.com_etapa(account, desenho) }
    },
    # B4.2: o vigia do SLA da 1ª resposta (Ramon::FirstResponseSlaJob), disparado pelo RamonLeadListener.
    'sla' => {
      env: 'RAMON_FLUXO_SLA', faz: 'o aviso de SLA da 1ª resposta',
      fluxos: { 'sla_primeira_resposta' => 'conversa_criada' }
    }
  }.freeze
```

(c) `app/services/ramon/fluxos/disparo.rb` — acrescentar a constante abaixo de `NA_HORA` e trocar `da_vez?`:

```ruby
  # B4.1/B4.2: gatilhos que o código dispara 2 vezes — com 'assumido' (a decisão do evento) só os fluxos migrados ouvem;
  # sem (o ouvinte de sempre), só os demais. conversa_criada: o RamonLeadListener manda a decisão do SLA da 1ª resposta.
  DUAS_VEZES = (NA_HORA + %w[conversa_criada]).freeze
```

```ruby
  # Nos gatilhos DUAS_VEZES: com 'assumido' só os migrados; sem, só os demais. Em reuniao_marcada/cancelada o disparo
  # com 'assumido' vem antes dos efeitos do código (o ensaio vê o lead como estava).
  def self.da_vez?(fluxo, dados)
    DUAS_VEZES.exclude?(fluxo.gatilho_tipo) || Ramon::Fluxos::Migracao.migrado?(fluxo) == dados.key?('assumido')
  end
```

(d) `app/listeners/ramon_lead_listener.rb` — substituir o comentário e o método `enqueue_first_response_sla`:

```ruby
  # SLA de 1ª resposta (mapa comercial): o vigia dispara N min depois e só
  # apita se a conversa seguir aberta e sem resposta. N = SLA da inbox,
  # senão o padrão do env — mesma regra do job e do Lead#sla_info.
  # B4.2: a conversa decide UMA vez quem vigia (Ramon::Fluxos::Migracao, grupo 'sla'): com o fluxo "SLA da 1ª resposta"
  # no comando E vigiando esta conversa, o job não é agendado; senão o código vigia (e o fluxo, se existir, só ensaia).
  def enqueue_first_response_sla(conversation)
    assumido = Ramon::Fluxos::Migracao.assumiu?(conversation.account, 'sla')
    dados = { 'caixa_id' => conversation.inbox_id, 'assumido' => assumido }
    return if Ramon::Fluxos::Disparo.externo('conversa_criada', conversation, dados).any? && assumido

    minutes = Ramon::Cadencia.sla_minutes(conversation.inbox)
    Ramon::FirstResponseSlaJob.set(wait: minutes.minutes).perform_later(conversation.id)
  end
```

(`Disparo.externo` nunca lança — erro do motor vira `[]` → o código vigia.)

(e) `.env.example` — logo depois da linha `# RAMON_FLUXO_REUNIOES=off`:

```
# ramon: SLA da 1a resposta pelo fluxo (B4.2). on + o fluxo "SLA da 1a resposta" em modo normal = o fluxo vigia as
# conversas novas e o codigo para. Padrao desligado (o codigo vigia). Virar/voltar: rake ramon:fluxos:migracao:modo[sla,conta,normal|sombra]
# RAMON_FLUXO_SLA=off
```

- [ ] **Step 4: Run to verify they pass**

Run (CI):
```bash
bundle exec rspec spec/listeners/ramon_lead_listener_spec.rb spec/services/ramon/fluxos/migracao_spec.rb spec/listeners/ramon_fluxo_listener_spec.rb spec/services/ramon/fluxos/disparo_spec.rb spec/services/ramon/fluxos/reunioes_spec.rb spec/services/ramon/reuniao_agendamento_spec.rb spec/jobs/ramon/first_response_sla_job_spec.rb
bundle exec rubocop app/services/ramon/fluxos/migracao.rb app/services/ramon/fluxos/disparo.rb app/listeners/ramon_lead_listener.rb
```
Expected: PASS (os 4 exemplos antigos do listener seguem: sem fluxo, `externo` devolve `[]` e o job é agendado como sempre); sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add db/seeds/ramon/fluxos/migrados/sla_primeira_resposta.json app/services/ramon/fluxos/migracao.rb app/services/ramon/fluxos/disparo.rb app/listeners/ramon_lead_listener.rb .env.example spec/listeners/ramon_lead_listener_spec.rb spec/services/ramon/fluxos/migracao_spec.rb
git commit -m "feat(fluxos): SLA da 1ª resposta como fluxo, com a chave RAMON_FLUXO_SLA (B4.2)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 5: Front — janela de horário no editor, esperar desde a conversa / SLA da caixa, sino SDR/gestores

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/captain/automacoes/JanelaHorario.vue`
- Modify: `.../automacoes/ConfigCondicoes.vue`, `.../automacoes/PainelPasso.vue`, `.../automacoes/NoPasso.vue`, `.../automacoes/fluxo.js`, `.../automacoes/validar.js`
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json`, `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`
- Test: `.../automacoes/specs/{PainelPasso,NoPasso,validar,migrados}.spec.js`

**Interfaces:**
- Consumes: formato da janela (Task 2), `esperar {desde, prazo}`, `para: sdr_ou_gestores|gestores`, `primeira_resposta`, `sla_minutos` (Task 3), o JSON do SLA (Task 4).
- Produces: `JANELA_PADRAO` (fluxo.js) `= { dias: [1, 2, 3, 4, 5], inicio: 8, fim: 18 }`; componente `JanelaHorario` (`props: { config: Object }`, emite `update:config` com o config inteiro + `dias`, `inicio`, `fim`) — a cadência (B4.3) usa o mesmo componente; código de erro `JANELA_INVALIDA`.

- [ ] **Step 1: Write the failing tests**

(a) `specs/PainelPasso.spec.js` — acrescentar dentro do `describe('PainelPasso', …)`, depois do teste "esperar: \"Antes da reunião\"…":

```js
  it('esperar: "O SLA da caixa" conta da criação da conversa, sem quantidade; "Até o horário" abre a janela do passo', async () => {
    const wrapper = montar({
      id: 'n2',
      data: { tipo: 'esperar', config: { quantidade: 1, unidade: 'dias' } },
    });
    await wrapper.find('[data-testid="espera-sla"]').trigger('change');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { desde: 'conversa', prazo: 'sla_caixa' },
    ]);
    const horario = montar({
      id: 'n2',
      data: { tipo: 'esperar', config: { ate: 'horario_comercial' } },
    });
    await horario.find('[data-testid="janela-dia-0"]').setValue(true);
    expect(horario.emitted('update:config').at(-1)).toEqual([
      { ate: 'horario_comercial', dias: [0, 1, 2, 3, 4, 5], inicio: 8, fim: 18 },
    ]);
  });

  it('se: "agora é horário comercial" tem a janela da própria condição', async () => {
    const cond = { campo: 'status', operador: 'em_horario_comercial', valor: '' };
    const wrapper = montar({
      id: 'n3',
      data: { tipo: 'se', config: { juncao: 'e', condicoes: [cond] } },
    });
    await wrapper.find('[data-testid="janela-inicio"]').setValue('7');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      {
        juncao: 'e',
        condicoes: [{ ...cond, dias: [1, 2, 3, 4, 5], inicio: 7, fim: 18 }],
      },
    ]);
  });

  it('sino: "SDR do lead (sem SDR: gestores)" (B4.2)', async () => {
    const wrapper = montar({
      id: 'n4',
      data: { tipo: 'avisar_sino', config: { texto: 'Oi' } },
    });
    await wrapper.find('[data-testid="sino-para"]').setValue('sdr_ou_gestores');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { texto: 'Oi', para: 'sdr_ou_gestores' },
    ]);
  });
```

(b) `specs/NoPasso.spec.js` — dentro de `describe('NoPasso — esperar', …)`, depois do teste "antes da reunião…":

```js
  it('SLA da caixa e "depois da criação da conversa" (B4.2)', () => {
    const sla = montar({
      tipo: 'esperar',
      config: { desde: 'conversa', prazo: 'sla_caixa' },
    });
    const conversa = montar({
      tipo: 'esperar',
      config: { desde: 'conversa', quantidade: 60, unidade: 'minutos' },
    });
    expect(sla.text()).toContain('The inbox SLA');
    expect(conversa.text()).toContain(
      '60 minutes after the conversation was created'
    );
  });
```

(c) `specs/validar.spec.js` — depois do teste "esperar: quantidade > 0…":

```js
  it('janela de horário (B4.2): no Se e no Esperar até o horário; SLA da caixa vale como tempo', () => {
    const hc = { campo: 'status', operador: 'em_horario_comercial' };
    const se = c => ({
      nos: [g(), p('p1', 'se', { condicoes: [c] }), p('p2', 'parar')],
      setas: [
        { de: 'g', saida: 's', para: 'p1' },
        { de: 'p1', saida: 'sim', para: 'p2' },
      ],
    });
    expect(validar(se(hc))).toEqual([]);
    expect(validar(se({ ...hc, dias: [0, 6], inicio: 7, fim: 21 }))).toEqual([]);
    expect(codigos(se({ ...hc, dias: [] }))).toEqual([['p1', 'JANELA_INVALIDA']]);
    expect(
      codigos(
        linear(p('p1', 'esperar', { ate: 'horario_comercial', inicio: 20, fim: 8 }))
      )
    ).toEqual([['p1', 'JANELA_INVALIDA']]);
    expect(
      validar(linear(p('p1', 'esperar', { desde: 'conversa', prazo: 'sla_caixa' })))
    ).toEqual([]);
  });
```

(d) `specs/migrados.spec.js` — acrescentar o import e um `describe` no fim do arquivo:

```js
import sla from '../../../../../../../../db/seeds/ramon/fluxos/migrados/sla_primeira_resposta.json';
```

```js
describe('fluxo migrado: SLA da 1ª resposta (B4.2)', () => {
  const de = (id, saida) =>
    sla.desenho.setas.find(s => s.de === id && s.saida === saida)?.para;
  const VIVA = [
    { campo: 'primeira_resposta', operador: 'igual', valor: 'nao' },
    { campo: 'status', operador: 'igual', valor: 'open' },
    { campo: 'etapa', operador: 'existe', valor: '' },
  ];
  const HORARIO = {
    campo: 'status',
    operador: 'em_horario_comercial',
    valor: '',
    dias: [0, 1, 2, 3, 4, 5, 6],
    inicio: 7,
    fim: 21,
  };

  it('publica, nasce da conversa nova e não cancela por etapa', () => {
    expect(validar(sla.desenho)).toEqual([]);
    expect(sla.desenho.nos[0].config).toEqual({
      tipo: 'conversa_criada',
      cancelar_se_sair_da_etapa: false,
    });
  });

  it('espera o SLA da caixa; depois até 60 min da criação da conversa', () => {
    expect(doTipo(sla, 'esperar').map(n => n.config)).toEqual([
      { rotulo: 'SLA da caixa', desde: 'conversa', prazo: 'sla_caixa' },
      {
        rotulo: 'Até 60 min da criação da conversa',
        desde: 'conversa',
        quantidade: 60,
        unidade: 'minutos',
      },
    ]);
  });

  it('as guardas do código, a escalada só se ainda vale, e a janela 7h–21h todo dia', () => {
    const [primeiro, horario1, segundo, horario2] = doTipo(sla, 'se').map(
      n => n.config.condicoes
    );
    expect(primeiro).toEqual(VIVA);
    expect(segundo).toEqual([
      { campo: 'horario_passou', operador: 'igual', valor: 'nao' },
      ...VIVA,
    ]);
    expect([horario1, horario2]).toEqual([[HORARIO], [HORARIO]]);
  });

  it('fora do horário pula o aviso, mas segue para a escalada', () => {
    expect([de('n4', 'sim'), de('n4', 'nao'), de('n6', 's')]).toEqual([
      'n5',
      'n7',
      'n7',
    ]);
  });

  it('SDR (sem SDR: gestores) com push; a escalada só os gestores, sem push', () => {
    expect(doTipo(sla, 'avisar_sino').map(n => n.config.para)).toEqual([
      'sdr_ou_gestores',
      'gestores',
    ]);
    expect(doTipo(sla, 'avisar_push').map(n => n.config.titulo)).toEqual([
      'Lead aguardando 1a resposta',
    ]);
  });
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts`
Expected: FAIL nos testes novos (sem `espera-sla`, sem `janela-*`, sem `JANELA_INVALIDA`, `ESPERA_SEM_TEMPO` no SLA, opção de sino inexistente, textos do NoPasso).

- [ ] **Step 3: Implementation**

(a) `fluxo.js`:
- em `VARIAVEIS`, depois de `'primeiro_nome',` acrescentar `'sla_minutos',`;
- em `CAMPOS`, depois de `'horario_passou',` acrescentar `'primeira_resposta',`;
- depois de `export const UNIDADES = ['minutos', 'horas', 'dias'];` acrescentar:

```js
// Ramon::Fluxos::Horario (B4.2): janela padrão quando o passo não tem a sua (0 = domingo)
export const JANELA_PADRAO = { dias: [1, 2, 3, 4, 5], inicio: 8, fim: 18 };
```

(b) `validar.js`:
- import: trocar `UNIDADES,` por `JANELA_PADRAO,\n  UNIDADES,` (ordem alfabética do bloco);
- em `RESERVADAS`, depois de `'horario_passou',` acrescentar `'primeira_resposta',` e `'sla_minutos',`;
- trocar `esperaValida` e acrescentar a janela logo abaixo:

```js
const esperaValida = c =>
  c.ate === 'horario_comercial' ||
  c.prazo === 'sla_caixa' ||
  (Number.parseInt(c.quantidade, 10) > 0 && UNIDADES.includes(c.unidade));

// Ramon::Fluxos::Horario.janela_valida? — sem as chaves vale o padrão
const janelaValida = c => {
  const dias = 'dias' in c ? (c.dias || []).map(Number) : JANELA_PADRAO.dias;
  const inicio = Number(c.inicio ?? JANELA_PADRAO.inicio);
  const fim = Number(c.fim ?? JANELA_PADRAO.fim);
  return (
    dias.length > 0 &&
    dias.every(d => d >= 0 && d <= 6) &&
    inicio >= 0 &&
    inicio < fim &&
    fim <= 24
  );
};
const errosJanela = (id, c) =>
  janelaValida(c) ? [] : [erro(id, 'JANELA_INVALIDA')];
```

- em `errosEspecificos`, trocar os casos `'se'` e `'esperar'` (mesma ordem do `Grafo`: condições, janelas, saída):

```js
    case 'se':
      return [
        ...((config.condicoes || []).length
          ? []
          : [erro(no.id, 'SE_SEM_CONDICOES')]),
        ...(config.condicoes || [])
          .filter(c => c.operador === 'em_horario_comercial')
          .flatMap(c => errosJanela(no.id, c)),
        ...(temSaida(no.id, setas) ? [] : [erro(no.id, 'SE_SEM_SAIDA')]),
      ];
```

```js
    case 'esperar':
      return [
        ...(esperaValida(config) ? [] : [erro(no.id, 'ESPERA_SEM_TEMPO')]),
        ...(config.ate === 'horario_comercial'
          ? errosJanela(no.id, config)
          : []),
      ];
```

(c) Criar `JanelaHorario.vue`:

```vue
<script setup>
// Janela de horário do próprio passo (B4.2, Ramon::Fluxos::Horario.janela): dias da semana + das/até, em São Paulo.
// Sem as chaves vale o padrão (seg–sex, 8h–18h). Serve ao "Se → agora é horário comercial" e ao "Esperar até o horário".
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { ROTULO, SELECT } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { JANELA_PADRAO } from './fluxo';

const props = defineProps({ config: { type: Object, required: true } });
const emit = defineEmits(['update:config']);
const K = 'CAPTAIN_RAMON.FLUXOS.PAINEL';
const { t } = useI18n();
const DIAS = [0, 1, 2, 3, 4, 5, 6];
const INICIOS = [...Array(24).keys()]; // 0–23
const FINS = INICIOS.map(h => h + 1); // 1–24 (24 = até a meia-noite)

const dias = computed(() => props.config.dias ?? JANELA_PADRAO.dias);
const inicio = computed(() => props.config.inicio ?? JANELA_PADRAO.inicio);
const fim = computed(() => props.config.fim ?? JANELA_PADRAO.fim);

// grava a janela inteira assim que algo muda: o JSON diz exatamente o que vale
const muda = (chave, valor) =>
  emit('update:config', {
    ...props.config,
    dias: dias.value,
    inicio: inicio.value,
    fim: fim.value,
    [chave]: valor,
  });
const marcaDia = (d, ligado) =>
  muda(
    'dias',
    ligado
      ? [...dias.value, d].sort((a, b) => a - b)
      : dias.value.filter(x => x !== d)
  );
</script>

<template>
  <div class="flex flex-col gap-2">
    <span :class="ROTULO">{{ t(`${K}.JANELA_DIAS`) }}</span>
    <div class="flex flex-wrap gap-3 text-[13px] text-n-slate-12">
      <label v-for="d in DIAS" :key="d" class="flex items-center gap-1">
        <input
          type="checkbox"
          class="reset-base"
          :data-testid="`janela-dia-${d}`"
          :checked="dias.includes(d)"
          @change="marcaDia(d, $event.target.checked)"
        />
        {{ t(`${K}.DIA_${d}`) }}
      </label>
    </div>
    <div class="grid grid-cols-2 gap-2">
      <label :class="ROTULO">
        {{ t(`${K}.JANELA_INICIO`) }}
        <select
          data-testid="janela-inicio"
          :class="SELECT"
          :value="inicio"
          @change="muda('inicio', Number($event.target.value))"
        >
          <option v-for="h in INICIOS" :key="h" :value="h">
            {{ t(`${K}.HORA_N`, { h }) }}
          </option>
        </select>
      </label>
      <label :class="ROTULO">
        {{ t(`${K}.JANELA_FIM`) }}
        <select
          data-testid="janela-fim"
          :class="SELECT"
          :value="fim"
          @change="muda('fim', Number($event.target.value))"
        >
          <option v-for="h in FINS" :key="h" :value="h">
            {{ t(`${K}.HORA_N`, { h }) }}
          </option>
        </select>
      </label>
    </div>
    <p class="text-xs text-n-slate-10">{{ t(`${K}.JANELA_AJUDA`) }}</p>
  </div>
</template>
```
(d) `ConfigCondicoes.vue`:
- import: depois de `import { CAMPOS, OPERADORES, SEM_VALOR } from './fluxo';` acrescentar `import JanelaHorario from './JanelaHorario.vue';`;
- depois de `mudaCondicao` acrescentar:

```js
const trocaCondicao = (i, nova) =>
  muda(
    'condicoes',
    condicoes.value.map((c, j) => (j === i ? nova : c))
  );
```

- no template, logo depois de `</datalist>`:

```vue
      <JanelaHorario
        v-if="c.operador === 'em_horario_comercial'"
        :config="c"
        @update:config="nova => trocaCondicao(i, nova)"
      />
```

(e) `PainelPasso.vue`:
- import: depois de `import ConfigIa from './ConfigIa.vue';` acrescentar `import JanelaHorario from './JanelaHorario.vue';`;
- substituir o bloco de `// esperar: …` até o fim de `PARA_SINO` por:

```js
// esperar: um tempo (do passo anterior), até o horário comercial (B4.2: com a janela do passo), antes da reunião
// (B4.1: conta para trás) ou a partir da criação da conversa (B4.2: um tempo ou o SLA da caixa)
const modoEspera = computed(() => {
  const c = config.value;
  if (c.ate === 'horario_comercial') return 'horario';
  if (c.desde === 'conversa') return c.prazo === 'sla_caixa' ? 'sla' : 'conversa';
  return c.antes_de === 'reuniao' ? 'reuniao' : 'tempo';
});
const OPCOES_ESPERA = [
  { modo: 'tempo', rotulo: 'ESPERAR_TEMPO', ajuda: 'ESPERAR_AJUDA' },
  { modo: 'horario', rotulo: 'ESPERAR_HORARIO', ajuda: 'ESPERAR_AJUDA' },
  { modo: 'reuniao', rotulo: 'ESPERAR_REUNIAO', ajuda: 'ESPERAR_REUNIAO_AJUDA' },
  { modo: 'conversa', rotulo: 'ESPERAR_CONVERSA', ajuda: 'ESPERAR_CONVERSA_AJUDA' },
  { modo: 'sla', rotulo: 'ESPERAR_SLA', ajuda: 'ESPERAR_CONVERSA_AJUDA' },
];
const CONFIG_ESPERA = {
  tempo: { quantidade: 1, unidade: 'dias' },
  horario: { ate: 'horario_comercial' },
  reuniao: { antes_de: 'reuniao', quantidade: 1, unidade: 'horas' },
  conversa: { desde: 'conversa', quantidade: 60, unidade: 'minutos' },
  sla: { desde: 'conversa', prazo: 'sla_caixa' },
};
const ajudaEspera = computed(
  () => OPCOES_ESPERA.find(o => o.modo === modoEspera.value).ajuda
);
const pedeTempo = computed(() => !['horario', 'sla'].includes(modoEspera.value));
// sino: pessoas marcadas (padrão), Closer e SDR do lead, a conta toda (B4.1), SDR ou gestores, gestores (B4.2)
const PARA_SINO = [
  { valor: '', rotulo: 'PARA_PESSOAS' },
  { valor: 'closer_e_sdr', rotulo: 'PARA_CLOSER_SDR' },
  { valor: 'conta', rotulo: 'PARA_CONTA' },
  { valor: 'sdr_ou_gestores', rotulo: 'PARA_SDR_GESTORES' },
  { valor: 'gestores', rotulo: 'PARA_GESTORES' },
];
```

- no template do `esperar`: trocar `<div v-if="modoEspera !== 'horario'" class="grid grid-cols-2 gap-2">` por `<div v-if="pedeTempo" class="grid grid-cols-2 gap-2">`, e trocar o `<p class="text-xs text-n-slate-10">` com o `t(\`${K}.PAINEL.${modoEspera === 'reuniao' ? …}\`)` por:

```vue
        <JanelaHorario
          v-if="modoEspera === 'horario'"
          :config="config"
          @update:config="c => emit('update:config', c)"
        />
        <p class="text-xs text-n-slate-10">
          {{ t(`${K}.PAINEL.${ajudaEspera}`) }}
        </p>
```

(f) `NoPasso.vue` — trocar o `case 'esperar'`:

```js
    case 'esperar': {
      if (c.ate === 'horario_comercial')
        return t(`${K}.PAINEL.ESPERAR_HORARIO`);
      if (c.prazo === 'sla_caixa') return t(`${K}.PAINEL.ESPERAR_SLA`);
      const tempo = `${c.quantidade ?? ''} ${c.unidade ? t(`${K}.${Number(c.quantidade) === 1 ? 'UNIDADES_UM' : 'UNIDADES'}.${c.unidade}`) : ''}`;
      if (c.desde === 'conversa') return t(`${K}.NO.DESDE_CONVERSA`, { tempo });
      return c.antes_de === 'reuniao'
        ? t(`${K}.NO.ANTES_DA_REUNIAO`, { tempo })
        : tempo;
    }
```

(g) i18n — mesmas posições nos dois arquivos (Edit à mão):

`en/ramon.json`, objeto `NO`: trocar `"ANTES_DA_REUNIAO": "{tempo} before the meeting"` por
```json
        "ANTES_DA_REUNIAO": "{tempo} before the meeting",
        "DESDE_CONVERSA": "{tempo} after the conversation was created"
```
`pt_BR/ramon.json`, objeto `NO`: trocar `"ANTES_DA_REUNIAO": "{tempo} antes da reunião"` por
```json
        "ANTES_DA_REUNIAO": "{tempo} antes da reunião",
        "DESDE_CONVERSA": "{tempo} depois da criação da conversa"
```

`PAINEL` — en: trocar a linha `"ESPERAR_REUNIAO_AJUDA": "Counts back … Reminder time already passed = yes.",` por
```json
        "ESPERAR_REUNIAO_AJUDA": "Counts back from the meeting time. If that moment has already passed, it does not wait and sets Wait time already passed = yes.",
        "ESPERAR_CONVERSA": "An amount of time after the conversation was created",
        "ESPERAR_SLA": "The inbox SLA (first reply deadline)",
        "ESPERAR_CONVERSA_AJUDA": "Counts from when the conversation was created. If that moment has already passed, it does not wait and sets Wait time already passed = yes.",
```
pt: trocar `"ESPERAR_REUNIAO_AJUDA": "Conta para trás … Horário do lembrete já passou = sim.",` por
```json
        "ESPERAR_REUNIAO_AJUDA": "Conta para trás a partir do horário da reunião. Se esse momento já passou, não espera e marca Momento da espera já passou = sim.",
        "ESPERAR_CONVERSA": "Um tempo depois da criação da conversa",
        "ESPERAR_SLA": "O SLA da caixa (prazo da 1ª resposta)",
        "ESPERAR_CONVERSA_AJUDA": "Conta a partir da criação da conversa. Se esse momento já passou, não espera e marca Momento da espera já passou = sim.",
```

`PAINEL` — en: trocar `"PARA_CONTA": "Everyone in the account",` por
```json
        "PARA_CONTA": "Everyone in the account",
        "PARA_SDR_GESTORES": "Lead SDR (no SDR: the managers)",
        "PARA_GESTORES": "The managers (administrators)",
        "JANELA_DIAS": "Days of the week",
        "JANELA_INICIO": "From",
        "JANELA_FIM": "Until",
        "JANELA_AJUDA": "São Paulo time. Unchanged, the default applies: Monday to Friday, 8am to 6pm.",
        "HORA_N": "{h}h",
        "DIA_0": "Sun",
        "DIA_1": "Mon",
        "DIA_2": "Tue",
        "DIA_3": "Wed",
        "DIA_4": "Thu",
        "DIA_5": "Fri",
        "DIA_6": "Sat",
```
pt: trocar `"PARA_CONTA": "Todo mundo da conta",` por
```json
        "PARA_CONTA": "Todo mundo da conta",
        "PARA_SDR_GESTORES": "SDR do lead (sem SDR: os gestores)",
        "PARA_GESTORES": "Os gestores (administradores)",
        "JANELA_DIAS": "Dias da semana",
        "JANELA_INICIO": "Das",
        "JANELA_FIM": "Até",
        "JANELA_AJUDA": "Horário de São Paulo. Sem mudar nada vale o padrão: segunda a sexta, das 8h às 18h.",
        "HORA_N": "{h}h",
        "DIA_0": "Dom",
        "DIA_1": "Seg",
        "DIA_2": "Ter",
        "DIA_3": "Qua",
        "DIA_4": "Qui",
        "DIA_5": "Sex",
        "DIA_6": "Sáb",
```

`CAMPOS` — en: trocar `"horario_passou": "Reminder time already passed (yes or no)"` por
```json
        "horario_passou": "Wait time already passed (yes or no)",
        "primeira_resposta": "Conversation already got its first reply (yes or no)"
```
pt: trocar `"horario_passou": "Horário do lembrete já passou (sim ou não)"` por
```json
        "horario_passou": "Momento da espera já passou (sim ou não)",
        "primeira_resposta": "Conversa já teve a 1ª resposta (sim ou não)"
```

`ERROS` — en: depois de `"ESPERA_SEM_TEMPO": "The wait time is missing.",` acrescentar `"JANELA_INVALIDA": "Invalid hours: pick at least one day and a start before the end.",`; pt: depois de `"ESPERA_SEM_TEMPO": "Falta o tempo de espera.",` acrescentar `"JANELA_INVALIDA": "Horário inválido: marque pelo menos um dia e um início antes do fim.",`.

(Conferido: nenhum spec do front cita "Reminder time already passed"/"Horário do lembrete já passou"; o rótulo fica genérico porque `{horario_passou}` agora vale também para a espera da conversa.)

- [ ] **Step 4: Run to verify they pass**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts
./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes
```
Expected: 15 arquivos / **189** testes verdes (180 + 3 PainelPasso + 1 NoPasso + 1 validar + 5 migrados); eslint sem `error`.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/JanelaHorario.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/ConfigCondicoes.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/PainelPasso.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/NoPasso.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js app/javascript/dashboard/routes/dashboard/captain/automacoes/validar.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/PainelPasso.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/NoPasso.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/validar.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/migrados.spec.js app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit -m "feat(fluxos): editor com janela de horário por passo, espera do SLA da caixa e sino SDR/gestores" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 6: Verificação final + notas na spec (§16) + texto do PR

**Files:**
- Modify: `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (acrescentar §16 no fim)

- [ ] **Step 1: Front inteiro**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts
./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes
git status --short
```
Expected: 15 arquivos / 189 testes; eslint sem `error`; `git status` sem `vitest.local.config.ts`.

- [ ] **Step 2: Varredura de regras**

```bash
git diff 079a04c --stat -- app/models/lead.rb app/services/ramon/advbox_event_processor.rb app/finders/conversation_finder.rb enterprise db/migrate db/schema.rb db/seeds/ramon/fluxos/sistema app/jobs/ramon/first_response_sla_job.rb lib/tasks/ramon_fluxos.rake
git diff 079a04c --stat -- spec/services/ramon/fluxos/reunioes_spec.rb spec/services/ramon/reuniao_agendamento_spec.rb spec/services/ramon/fluxos/disparo_spec.rb spec/services/ramon/fluxos/comparar_agendamentos_spec.rb spec/services/ramon/fluxos/comparar_lembretes_spec.rb
grep -rn "RAMON_FLUXO_SLA" app lib .env.example
ls db/seeds/ramon/fluxos/migrados
```
Expected: os 2 primeiros vazios (nada do caminho antigo nem das specs da B4.1 mudou); a env aparece em `migracao.rb` e no `.env.example`; 4 JSON.

- [ ] **Step 3: Notas da B4.2 na spec** — acrescentar ao fim de `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md`:

```markdown
## 16. Notas da B4.2 (07/10/2026) — SLA da 1ª resposta direto no fluxo

- **Escopo (Eduardo, 07/10):** o vigia do SLA da 1ª resposta migra **direto**, sem fase de sombra e sem comparação. Fluxo "SLA da 1ª resposta" (`origem: usuario`, `sistema_chave: sla_primeira_resposta`, gatilho `conversa_criada`), criado por `rake ramon:fluxos:migracao:criar[sla,conta]` a partir de `db/seeds/ramon/fluxos/migrados/sla_primeira_resposta.json`.
- **Módulo comum das migrações:** `Ramon::Fluxos::Migracao` (`GRUPOS`: env, fluxos `sistema_chave → gatilho`, ajuste do desenho por conta) faz a chave e a semeadura de qualquer migração; `Ramon::Fluxos::Reunioes` usa ele (mesma API). Rake genérico `ramon:fluxos:migracao:{criar,modo}[grupo,conta(,modo)]`. B4.3+ = uma entrada em `GRUPOS` + JSON + o código lendo `assumiu?` uma vez por evento.
- **A decisão é da conversa nova:** o `RamonLeadListener` (onde o código agendava; só caixas com Criar lead e com contato) lê `Migracao.assumiu?(conta, 'sla')` uma vez e dispara `conversa_criada` com `assumido`. `conversa_criada` é gatilho "disparado 2 vezes" (`Disparo::DUAS_VEZES`): com `assumido` só o fluxo migrado ouve; sem (o `RamonFluxoListener`), só os demais. O job do código só não é agendado quando o fluxo está no comando **e** pegou a conversa (filtro editado ou erro → o código vigia).
- **A chave:** `RAMON_FLUXO_SLA=on` **e** o fluxo ligado, publicado, em modo normal, sem limite diário e com o gatilho `conversa_criada`. Virar = `…migracao:modo[sla,conta,normal]`; voltar = `…modo[sla,conta,sombra]` (ou env desligada). Desligar o fluxo na tela com ele no comando cancela as vigílias em andamento.
- **Motor ganhou:** janela de horário por passo (`dias` 0–6, `inicio`, `fim` no config da condição `em_horario_comercial` e do `esperar {ate: horario_comercial}`; sem as chaves = seg–sex 8h–18h; `Ramon::Fluxos::Horario.janela/janela_valida?`); `esperar {desde: 'conversa'}` (quantidade/unidade ou `prazo: 'sla_caixa'` = `Ramon::Cadencia.sla_minutes`; já passado → `{horario_passou} = sim`); variáveis `{primeira_resposta}` e `{sla_minutos}`; sino `para: sdr_ou_gestores | gestores`.
- **Fidelidade:** guardas = sem 1ª resposta + aberta + com lead (`etapa existe`); aviso 7h–21h todo dia; escalada aos 60 min da criação esperada mesmo fora do horário e só se ainda for futura (caixa com SLA ≥ 60: sem escalada); sem cancelar por etapa. Mudou: sino `ramon_fluxo_aviso` (era `ramon_sla_breach`), balão "⚙ Fluxo …" na conversa, precisão de ~1 min (relógio dos fluxos).
- **Fica para a limpeza (outro PR, 2 semanas depois de rodar em normal):** apagar `Ramon::FirstResponseSlaJob` e o agendamento dele no `RamonLeadListener` (fica só o disparo), o JSON `sistema/sla_primeira_resposta.json` **e** a linha `origem: sistema` dele, e a env.
```

- [ ] **Step 4: Texto do PR (não abrir — gate do Eduardo)** — deixar no relatório final:

```markdown
Automações em fluxo — B4.2: o aviso de "lead aguardando a 1ª resposta" vira um fluxo de verdade, o "SLA da 1ª resposta": conversa nova numa caixa com Criar lead → espera o SLA da caixa → se ninguém respondeu, avisa o SDR do lead (sem SDR, os gestores) e manda o push; aos 60 minutos, se continuar sem resposta, avisa os gestores. O horário do aviso agora é configurável no próprio fluxo (dias da semana e das/até) e o fluxo nasce com o horário de hoje (7h às 21h, todo dia). Uma chave faz o fluxo assumir e o código parar — **a chave vem desligada: nada muda até o Eduardo virar** — e voltar é um comando, sem deploy. No editor: janela de horário em "Se → agora é horário comercial" e em "Esperar até o horário comercial", "Esperar o SLA da caixa", "Esperar um tempo depois da criação da conversa", sino para "SDR do lead (sem SDR: gestores)" ou "Os gestores", e o campo "Conversa já teve a 1ª resposta".

## Closes
- Spec `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` §8 (B4+, 2ª migração: SLA, direto por decisão do Eduardo em 07/10); notas novas em §16.

## How to test
1. Depois do deploy (com `RAMON_FLUXO_SLA=on` no `chatwoot.env`): `rake "ramon:fluxos:migracao:criar[sla,2]"` → "SLA da 1ª resposta — modo sombra, ligado" e "Agora o CÓDIGO faz o aviso de SLA da 1ª resposta".
2. Inteligência → Automações → "SLA da 1ª resposta": conferir os passos, o horário 7h–21h todo dia e os textos.
3. `rake "ramon:fluxos:migracao:modo[sla,2,normal]"` → "Agora os FLUXOS fazem o aviso de SLA da 1ª resposta".
4. De um celular de teste, mandar mensagem para a caixa de leads e não responder: no prazo da caixa chega o sino "Lead aguardando 1ª resposta há N min" ao SDR (ou aos gestores) + push; aos 60 min, o sino dos gestores. Em Execuções, a do "SLA da 1ª resposta" sem o selo ensaio.

## What changed
- `Ramon::Fluxos::Migracao`: chave e semeadura de qualquer migração (reuniões e SLA); rake `ramon:fluxos:migracao:{criar,modo}`. `Ramon::Fluxos::Reunioes` usa ele, sem mudança de comportamento.
- Motor: janela de horário por passo; esperar desde a criação da conversa (inclui o SLA da caixa); `{primeira_resposta}` e `{sla_minutos}`; sino para SDR ou gestores; `conversa_criada` decidida pelo `RamonLeadListener` para o fluxo migrado.
- `RamonLeadListener` decide uma vez por conversa nova quem vigia. Chave `RAMON_FLUXO_SLA` (desligada). Front: editor. Sem migração de banco.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR
```

- [ ] **Step 5: Smoke em bloco (para o Eduardo, depois do deploy)** — anotar no relatório: a seção "Operação depois do deploy" §1–§4 inteira, de uma vez (criar → conferir → virar → teste ao vivo com e sem resposta → limpar).

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md
git commit -m "docs(fluxos): notas da B4.2 na spec" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

Sem push.

---

## Operação depois do deploy

Conta da banca = **2**; console = `docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "<task>"` (Eduardo roda via `!` e cola a saída). **Sem migração.** Sequência mais simples e segura para "direto + teste na hora":

**0. No deploy.** Acrescentar `RAMON_FLUXO_SLA=on` ao `chatwoot.env` em `/opt/intranet-ramon` **antes** do `docker compose up -d chatwoot-web chatwoot-worker` do próprio deploy (assim não precisa recriar de novo). A env sozinha não muda nada: sem o fluxo em normal, o código vigia.

**1. Criar o fluxo (em sombra).**
`docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:migracao:criar[sla,2]"`
Saída esperada: `Fluxo #N "SLA da 1ª resposta" — modo sombra, ligado` e `Agora o CÓDIGO faz o aviso de SLA da 1ª resposta (os fluxos ensaiam).` Rodar de novo não duplica. Entre este passo e o 2, conversas novas ganham um ensaio em Execuções (inofensivo).

**2. Conferir e virar (minutos depois).** Abrir Inteligência → Automações → "SLA da 1ª resposta": horário 7h–21h todo dia nos dois "Entre 7h e 21h?", textos do sino e do push. Então:
`docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:migracao:modo[sla,2,normal]"` → `Agora os FLUXOS fazem o aviso de SLA da 1ª resposta (o código não faz mais).`

**3. Teste ao vivo (smoke, logo em seguida, dentro do horário 7h–21h).**
- A — sem resposta: de um celular de teste, mandar "teste SLA" para a caixa de leads do WhatsApp (conversa nova, contato novo). Não responder. Em Execuções, "SLA da 1ª resposta" **sem** selo ensaio, esperando. No prazo da caixa (padrão 5 min; até ~1 min a mais): sino "Lead aguardando 1ª resposta há 5 min: <nome>" para o SDR do lead (sem SDR: gestores) + push "Lead aguardando 1a resposta"; balão "⚙ Fluxo SLA da 1ª resposta: sino: …" na conversa. Aos 60 min da conversa: sino "… há 60 min" para os gestores (sem push). Nenhum sino "SLA estourado" do código para essa conversa.
- B — com resposta: outro contato de teste manda mensagem; responder antes do prazo. No prazo: execução concluída com "não" no 1º Se, nenhum sino.
- Limpar: resolver as conversas de teste; apagar os leads de teste (apagar `LeadActivity` antes do lead).

**4. Rollback (a qualquer momento, sem deploy).** Preferido:
`docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:migracao:modo[sla,2,sombra]"` → `Agora o CÓDIGO faz…`. Conversas novas voltam para o código na hora; as que o fluxo já vigiava terminam pelo fluxo (sem dobra, sem buraco). Também é seguro tirar a env (exige recriar o container). **Evitar desligar o fluxo na tela como rollback:** cancela as vigílias em andamento (conversas da última hora ficam sem aviso).

**5. Depois (outro PR, E7 análogo).** Com 2 semanas em normal sem incidente: apagar `Ramon::FirstResponseSlaJob` e o agendamento dele no `RamonLeadListener` (fica só o disparo), o JSON `db/seeds/ramon/fluxos/sistema/sla_primeira_resposta.json` **e** a linha `origem: sistema` dele, e a env `RAMON_FLUXO_SLA` (com isso a entrada `'sla'` de `Migracao::GRUPOS` passa a não precisar de env — decidir no PR de limpeza).

---

## Divergências registradas (spec × este plano)

| # | Onde | Divergência | Motivo |
|---|---|---|---|
| 1 | Spec §8 (sombra por alguns dias + comparar) | Direto: sem fase de sombra, sem comparação | D1 (Eduardo, 07/10) |
| 2 | Spec §4.2/§4.4 + `Horario` (seg–sex 8h–18h fixo) | Janela por passo (condição e "esperar até o horário"); padrão inalterado | D2 |
| 3 | Spec §4.4 ("espera conta do passo anterior") | `esperar {desde: 'conversa'}` conta da criação da conversa | Prazo do SLA e escalada de 60 min contam da conversa |
| 4 | Spec §4.1 (`conversa_criada` vem do `RamonFluxoListener`) | O fluxo migrado ouve só o disparo do `RamonLeadListener` (caixas com Criar lead, com a decisão) | O gatilho fica onde o código dispara hoje |
| 5 | Spec §6 (sombra pelo `modo`) | Fluxo migrado age ou ensaia pela decisão do evento (`assumido`) | Igual à B4.1: nem dobra nem buraco na virada |

## Decisões do Eduardo (07/10/2026)

| # | Decisão | Onde no plano |
|---|---|---|
| D1 | **Direto, sem sombra nem comparação**; chave `RAMON_FLUXO_SLA` + modo normal; voltar = rake sombra; teste ao vivo logo após o deploy | Tasks 1, 4; Operação |
| D2 | **Horário configurável por passo no editor**; o fluxo nasce 7h–21h todo dia; escalada esperada mesmo fora do horário | Tasks 2, 4, 5 |
| — | Fidelidade (prazo da caixa, 3 guardas, SDR→gestores, escalada 60 min para gestores, push como hoje; texto/tipo do sino pode mudar) | Tasks 3, 4 |
| — | Limpeza do código antigo em outro PR, 2 semanas depois | Operação §5 |

## Decisões novas que dependem do Eduardo

| # | Decisão | Proposta do plano |
|---|---|---|
| N1 | O fluxo "acorda" pelo relógio de minuto em minuto: o aviso pode chegar **até ~1 min depois** do prazo (o código chega no segundo certo) | Aceitar |
| N2 | Se o fluxo estiver no comando mas **não pegar** uma conversa (ex.: alguém pôs filtro de caixa no gatilho, ou erro do sistema), o **código vigia aquela conversa**. Efeito colateral: filtro de caixa no fluxo não desliga o aviso daquela caixa | Aceitar (nunca fica sem aviso) |
| N3 | Com o fluxo no comando, **desligar o fluxo na tela** cancela as vigílias em andamento (conversas da última hora ficam sem aviso). A volta segura é o comando "modo sombra" | Aceitar (igual à B4.1) |


## Respostas do Eduardo (07/10/2026)

Todas as "Decisões novas que dependem do Eduardo" deste plano foram **ACEITAS como propostas** (formulário de 07/10).
