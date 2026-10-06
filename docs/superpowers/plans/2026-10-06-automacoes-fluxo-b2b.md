# Automações em fluxo — B2b (IA, ADVBOX e gatilhos externos) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Completar o catálogo do motor de fluxos: passos de IA (`perguntar_ia`, `rascunho_ia`, `rodar_skill`), `advbox`, `webhook`, `registrar_atividade`, `trocar_responsavel`, `preencher_campo`; gatilhos `reuniao_marcada`/`reuniao_cancelada`, `evento_advbox`, `contrato_assinado`/`contrato_recusado`, `documento_recebido`, `lead_parado`, `relogio`; a condição "Documentos completos?" — back, quadro e testes.

**Architecture:** Cada passo novo é um método de módulo em `app/services/ramon/fluxos/passos/` (contrato da B1: `tipo(config, ctx) → {saida:, vars:, resumo:}`), registrado no `Executor::PASSOS` e validado no `Grafo` (espelhado em `validar.js`). Os 4 gatilhos externos entram por **1 linha** em cada ponto de origem, chamando `Ramon::Fluxos::Disparo.externo` (que nunca derruba quem chamou). `lead_parado` e `relogio` rodam dentro do `Ramon::FluxoRelogioJob` (já é cron de 1 min) via um módulo novo `Ramon::Fluxos::Relogio`, com `ultimo_disparo_em` reivindicado por UPDATE condicional (1×/dia, fuso SP). Front: catálogo em `fluxo.js` ganha os itens (que até a B2 nem existiam no catálogo), 2 painéis novos (`ConfigIa.vue`, `ConfigAdvbox.vue`) + campos simples direto no `PainelPasso.vue` e no `ConfigGatilho.vue`. Sem migração (`ramon_fluxos.ultimo_disparo_em` já existe desde a B1).

**Tech Stack:** Rails 7.1 / RSpec (só no CI), `Ramon::LlmClient` (DeepSeek, `lib/ramon/llm_client.rb`), `Ramon::Pseudonymizer`, `LlmFormatter::ConversationLlmFormatter`, `Captain::Assistant::AgentRunnerService` (enterprise), `Ramon::AdvboxMcpService::FETCHERS` + `Ramon::AdvboxClient`, `SafeFetch` (anti-SSRF do Chatwoot), `Redis::Alfred`; Vue 3.5 `<script setup>`, vue-i18n 9, Vitest 3 + @vue/test-utils.

**Spec:** `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (§4 peças, §6 motor, §10 fatia B2b). Planos anteriores (estilo e decisões): `docs/superpowers/plans/2026-10-05-automacoes-fluxo-b1-motor.md`, `docs/superpowers/plans/2026-10-05-automacoes-fluxo-b2-quadro.md`.

## Global Constraints

- Base: `origin/ramon` em **4ac0ad6** (B1 motor + B2 quadro no ar); branch `feat/fluxos-b2b`, worktree `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-fluxos-b2b`.
- **Sem migração.** `ramon_fluxos.ultimo_disparo_em` já existe (`db/schema.rb:1537`). Se alguma task achar que precisa de coluna nova: pare e pergunte (versões em `db/migrate` vão até `20261006100001` — não colidir).
- **Rubocop do fork** (o CI barra): `Metrics/AbcSize` 26, `Metrics/MethodLength` 19, `Metrics/CyclomaticComplexity` 7, `Metrics/PerceivedComplexity` 8, `Metrics/ClassLength` 175, `Metrics/ModuleLength` 100, linha 150. `Naming/MethodParameterName` ≥ 3 letras. **`app/models/lead.rb` está NO LIMITE de 175 linhas: não adicione nenhuma linha a ele** (use `LeadDocs#doc_checklist`, `Ramon::Papeis`, `Ramon::Cadencia` que já existem).
- **Captain é enterprise:** todo código que toca `Captain::*` fica atrás de `ChatwootApp.enterprise?` e os specs dele com `if: ChatwootApp.enterprise?` (o CI FOSS apaga `enterprise/`). Constante `Captain::…` só dentro de corpo de método/bloco (resolvida em runtime), nunca em constante de classe.
- **Mensagem ao cliente SEMPRE rascunho:** `rascunho_ia` grava nota privada começando com `Ramon::RascunhoCarimbo::PREFIXO` (`'RASCUNHO (revisar antes de enviar):'`). Nenhum passo envia nada ao cliente. `rodar_skill` roda **sem conversa no estado do runner** (ver Task 5) — nenhuma ferramenta da skill age na conversa.
- **Só admin edita:** a API nova (`GET ramon_fluxos/opcoes_advbox`) passa pelo `check_authorization` do `RamonFluxosController` (`RamonFluxoPolicy#gerenciar?`).
- **LGPD:** texto que vai ao LLM passa por `Ramon::Pseudonymizer.mask(texto, names: …)`; `[nome]` volta como o primeiro nome (padrão `FollowUpDraftService`/`ConversationCopilotService`). O webhook leva só `ctx.dados` + IDs — nunca env, token ou config do hub.
- **Tom/OAB** (prompts e textos de exemplo): Provimento 205/2021 — nunca prometer resultado, prazo ou valor do INSS; sem pressão; honorário só "30% dos atrasados + 3 parcelas do benefício", o mesmo em todas as teses (texto igual ao guardrail de `db/seeds/ramon/inteligencia/assistentes.yml:27`).
- **i18n:** chaves novas só dentro de `CAPTAIN_RAMON.FLUXOS` em `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json` (+ `RAMON.LEAD_PANEL.HISTORY.KIND.FLUXO` para a atividade). Strings SEM `@`, `|`, `{`, `}` crus — só placeholders `{nome}`/`{quando}`; a trava `specs/i18n.spec.js` compila tudo no vue-i18n de **produção**. Editar os JSON à mão (Edit), nunca regravar o arquivo inteiro por script (diff gigante).
- **Front:** Tailwind only; kit `ramon/helpers/ui.js` (`CAMPO`, `SELECT`, `ROTULO`, `AVISO`, `TOM`); evento custom camelCase (`update:config`); toda `<ul>` nova com `list-none` (o global é `list-disc`); sem texto cru no template (inclusive `placeholder`).
- **Testes locais:** sem Ruby/Postgres local — specs Ruby só no CI. Front:
  - `node_modules` é **junção** para `ramon-hub-wt-fluxos-b2\node_modules` (tem `@vue-flow`). O Vitest com o config do repo falha (`Failed to load url …fake-indexeddb…`) porque o Vite barra arquivo fora da raiz. Use o config local **já criado e fora do git** (`vitest.local.config.ts`, listado em `.git/info/exclude`, = `vitest.config` + `server.fs.allow: ['..']`):
    `TZ=UTC ./node_modules/.bin/vitest --no-watch --config vitest.local.config.ts app/javascript/dashboard/routes/dashboard/captain/automacoes/specs`
    (baseline conferida: 9 arquivos, 67 testes verdes). Nunca commitar esse arquivo; nunca `rm -rf node_modules` (apagaria o da b2).
  - ESLint: `./node_modules/.bin/eslint <arquivos>` (erro `Delete ␍` = CRLF do checkout Windows, ignorar).
- **Commits:** Conventional Commits, sem citar Claude no assunto; corpo termina com:
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv`
  Commitar só os caminhos da task (`git add <arquivos>`), nunca `git add -A`. Sem push nem PR neste plano.

## Review Focus

1. **Ensaio de um fluxo com `perguntar_ia`** — o ensaio é síncrono no request (`RamonFluxosController#ensaio`) e a spec manda a condição de IA rodar de verdade: o admin espera alguns segundos (até 90 s no pior caso), não um erro. Já `rascunho_ia`/`rodar_skill`/`advbox`/`webhook` no ensaio só **descrevem** e não chamam ninguém. Teste: Task 5 ("no ensaio, rascunho_ia só descreve") e Task 4 ("ensaio não grava no ADVBOX nem chama o webhook").
2. **`documento_recebido` → "Documentos completos?"** — o gatilho vem da **sugestão** da IA (DocMatch), mas "completos" conta só o que a equipe **confirmou** (`doc_status = recebido`). Quem monta "documento chegou → se completos" vai ver "não" até alguém confirmar — comportamento esperado, nunca "sim" por causa de uma sugestão. Teste: Task 1 ("sugestão da IA não conta como recebido").
3. **Lead sem processo no ADVBOX** (ganho antigo, fechamento sem caso criado) — o passo `advbox` falha **na hora** com "o lead ainda não tem processo no ADVBOX" (sem 3 tentativas inúteis) e o sino de falha avisa os admins. Teste: Task 4.
4. **Webhook para endereço interno ou sem https** (`http://…`, `https://10.0.0.5`, `https://localhost`) — publicar recusa o que não é https; endereço que resolve para rede privada é recusado pelo `SafeFetch` e o passo falha na hora, sem repetir. Teste: Task 2 (https) e Task 4 (rede interna).
5. **`lead_parado` com o mesmo lead parado vários dias / hub fora do ar às 11:00** — dispara **uma vez por parada** (só volta se o lead andar e parar de novo) e, se o minuto exato passar, dispara quando o relógio voltar no mesmo dia (fuso SP); nunca 2× no mesmo dia. Teste: Task 7.

---

## Mapa de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `app/services/ramon/fluxos/contexto.rb` | + `documentos_completos`/`documentos_faltantes`, campos livres (`custom_attributes['campos']`), dados do gatilho (`quando`, `regra`, `documento`) |
| `app/services/ramon/fluxos/grafo.rb` | + 8 gatilhos, 8 passos, obrigatórios, regras próprias (webhook https e último, advbox, chave do campo, saída do `perguntar_ia`, hora do relógio) — despacho por tabela `ESPECIFICOS` |
| `app/services/ramon/fluxos/passos/lead.rb` | + `registrar_atividade`, `trocar_responsavel`, `preencher_campo` |
| `app/services/ramon/fluxos/passos/externo.rb` (novo) | `advbox`, `webhook` |
| `app/services/ramon/fluxos/passos/ia.rb` (novo) | `perguntar_ia`, `rascunho_ia`, `rodar_skill` + teto diário de IA |
| `app/services/ramon/fluxos/executor.rb` | mapa `PASSOS`/`VISIVEIS` + grava a trilha a cada passo |
| `app/services/ramon/fluxos/disparo.rb` | + `externo` (à prova de erro) + filtro `regras` do ADVBOX |
| `app/services/ramon/fluxos/relogio.rb` (novo) | `lead_parado` e `relogio` (1×/dia, SP) |
| `app/jobs/ramon/fluxo_relogio_job.rb` | chama `Ramon::Fluxos::Relogio.disparar_do_dia` |
| `app/services/ramon/reuniao_agendamento.rb` | 1 linha em `notify` → `reuniao_marcada`/`reuniao_cancelada` |
| `app/services/ramon/advbox_event_processor.rb` | 1 linha em `perform` → `evento_advbox` |
| `app/jobs/ramon/zapsign_lead_status_job.rb` | 1 linha (+ 4º item do `STATUS`) → `contrato_assinado`/`contrato_recusado` |
| `app/services/ramon/doc_match_service.rb` | 1 linha em `gravar_sugestao` → `documento_recebido` |
| `app/controllers/api/v1/accounts/ramon_fluxos_controller.rb` + `config/routes.rb` | `GET ramon_fluxos/opcoes_advbox` (admin) |
| `app/javascript/dashboard/api/ramonFluxos.js` | `opcoesAdvbox()` |
| `…/captain/automacoes/fluxo.js` | catálogo B2b (gatilhos, passos, paleta, `REGRAS_ADVBOX`, `PAPEIS`, campos, variáveis, saídas) |
| `…/captain/automacoes/validar.js` | espelho das regras novas do Grafo; exporta `OBRIGATORIOS` |
| `…/captain/automacoes/modelos.js` | Pós-contrato: `contrato_assinado` + Se "Documentos completos?" → rascunho IA + push |
| `…/captain/automacoes/ConfigIa.vue` (novo) | painel de `perguntar_ia`, `rascunho_ia`, `rodar_skill` |
| `…/captain/automacoes/ConfigAdvbox.vue` (novo) | painel do `advbox` |
| `…/captain/automacoes/PainelPasso.vue` | liga os 2 painéis + webhook, trocar responsável, preencher campo, registrar atividade |
| `…/captain/automacoes/ConfigGatilho.vue` | hora, dias parado, grupo do relógio, regras do ADVBOX, ajudas |
| `…/captain/automacoes/NoPasso.vue` | detalhe no cartão dos tipos novos |
| `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json` | textos |
| specs | `spec/services/ramon/fluxos/{contexto,grafo,passos,executor,disparo}_spec.rb`, `spec/services/ramon/fluxos/{passos_externo,passos_ia,relogio}_spec.rb` (novos), `spec/jobs/ramon/fluxo_relogio_job_spec.rb`, `spec/jobs/ramon/zapsign_lead_status_job_spec.rb`, `spec/services/ramon/{advbox_event_processor,reuniao_agendamento,doc_match_service}_spec.rb`, `spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb`; front `specs/{fluxo,validar,modelos,i18n,PainelPasso}.spec.js` + `specs/{ConfigIa,ConfigAdvbox}.spec.js` (novos) |

## Pontos de origem conferidos no código (arquivo:linha na base 4ac0ad6)

| Gatilho | Onde entra | Por quê ali |
|---|---|---|
| `reuniao_marcada` / `reuniao_cancelada` | `app/services/ramon/reuniao_agendamento.rb:52-57` (`self.notify`) | É o único funil comum: `call` (:80, painel e Cal.com created/rescheduled via `calcom_webhooks_controller.rb:82`), `remarcar` (:92) e `cancelar` (:36) chamam `notify`; o **cancel do Cal.com não passa por `.cancelar`** — o controller chama `notify(lead, 'ramon_meeting_cancelled')` direto (`calcom_webhooks_controller.rb:63` → :87-88). Remarcar conta como `reuniao_marcada`. |
| `evento_advbox` | `app/services/ramon/advbox_event_processor.rb:41-50` (`perform`, depois do `update!` processed :49) | Só eventos com regra e lead casado; dado `regra` = chave do handler (`contrato_fechado`, `indeferimento`, …). |
| `contrato_assinado` / `contrato_recusado` | `app/jobs/ramon/zapsign_lead_status_job.rb:10-13` (STATUS) e :27 | Depois do sino; o guard `atual?` (:34-37) já garante 1 vez por doc. |
| `documento_recebido` | `app/services/ramon/doc_match_service.rb:82-96` (`gravar_sugestao`, depois do `EventoInline` :90-95) | **Divergência da spec:** o `DocMatchJob` (`app/jobs/ramon/doc_match_job.rb:8-13`) não sabe se houve casamento — o service devolve `nil` em 4 saídas diferentes. O único ponto onde "anexo casado com o checklist" é verdade é `gravar_sugestao`. |
| `lead_parado` / `relogio` | `app/jobs/ramon/fluxo_relogio_job.rb:8-14` (cron 1 min, `config/schedule.yml:100-101`) | Reaproveita `Ramon::Cadencia.parados` (`app/services/ramon/cadencia.rb:10-14`, variante SQL da mesma regra do `parado?` :17-22). |

**IA lenta × lock (revisão final da B1) — confirmado:** `Executor#reivindicar` (`app/services/ramon/fluxos/executor.rb:41-50`) só troca `esperando→rodando` dentro de `with_lock` e solta; `andar` (:74-89) roda os passos **fora de transação**. Nenhum passo de IA segura lock. O risco que sobra é outro: o executor só grava no fim (`avancar!` :29), e o relógio devolve à fila execução `rodando` há > 10 min (`fluxo_relogio_job.rb:10-11`). Fluxo com várias chamadas de IA (90 s cada, `LlmClient::REQUEST_TIMEOUT`) pode passar de 10 min e ser andado 2×. A Task 3 grava a execução **a cada passo** (1 UPDATE por passo) — o "órfão" passa a medir 1 passo, não o fluxo inteiro.

---

### Task 1: Contexto — documentos, campos livres e dados do gatilho

**Files:**
- Modify: `app/services/ramon/fluxos/contexto.rb:1-58`
- Test: `spec/services/ramon/fluxos/contexto_spec.rb`

**Interfaces:**
- Consumes: `Lead#doc_checklist` (`app/models/concerns/lead_docs.rb:17-24`, devolve `[{id:, title:, status:}]`).
- Produces: `Contexto#dados` ganha `'documentos_completos'` (`'sim' | 'nao' | nil` — nil = lead sem checklist), `'documentos_faltantes'` (títulos separados por `, `), as chaves de `lead.custom_attributes['campos']` (nunca pisam nas do hub) e `'texto'`, `'quando'`, `'regra'`, `'documento'` vindas de `execucao.contexto['gatilho']` (sempre presentes, `nil` quando o gatilho não traz). Constante `Ramon::Fluxos::Contexto::DO_GATILHO`.

- [ ] **Step 1: Write the failing tests** (acrescentar ao fim do `describe` em `spec/services/ramon/fluxos/contexto_spec.rb`)

```ruby
  describe 'documentos do checklist' do
    let(:tese) { create(:thesis, account: account) }
    let!(:rg) { create(:thesis_item, thesis: tese, section: 'documento', title: 'RG', content: 'RG') }

    before { create(:thesis_item, thesis: tese, section: 'documento', title: 'CNIS', content: 'CNIS') }

    it 'diz se está completo e lista o que falta' do
      lead.update!(thesis: tese, custom_attributes: { 'doc_status' => { rg.id.to_s => 'recebido' } })
      expect(described_class.new(execucao(lead)).dados).to include('documentos_completos' => 'nao', 'documentos_faltantes' => 'CNIS')
    end

    it 'sugestão da IA não conta como recebido (só a confirmação da equipe)' do
      lead.update!(thesis: tese, custom_attributes: { 'doc_sugestao' => { 'item_id' => rg.id, 'resolvida' => false } })
      expect(described_class.new(execucao(lead)).dados).to include('documentos_completos' => 'nao', 'documentos_faltantes' => 'RG, CNIS')
    end
  end

  it 'sem checklist não diz que está completo' do
    expect(described_class.new(execucao(lead)).dados).to include('documentos_completos' => nil, 'documentos_faltantes' => '')
  end

  it 'campos preenchidos pelo fluxo viram variáveis, sem pisar nos do hub' do
    lead.update!(custom_attributes: { 'campos' => { 'beneficio' => 'BPC', 'nome' => 'Outro' } })
    expect(described_class.new(execucao(lead)).dados).to include('beneficio' => 'BPC', 'nome' => 'Maria')
  end

  it 'dados do gatilho viram variáveis' do
    e = fluxo.execucoes.create!(account: account, alvo: lead, contexto: { 'gatilho' => { 'quando' => 'quinta, 20/08 às 14:00', 'regra' => 'exito' } })
    expect(described_class.new(e).dados).to include('quando' => 'quinta, 20/08 às 14:00', 'regra' => 'exito', 'texto' => nil)
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/services/ramon/fluxos/contexto_spec.rb` (no CI — sem Ruby local; o executor da task sobe o commit e lê o CI, ou segue direto ao Step 3 se estiver em modo "sem Ruby").
Expected: FAIL — `documentos_completos`/`beneficio`/`quando` ausentes.

- [ ] **Step 3: Implementation** — substituir `dados` e acrescentar 3 métodos privados em `app/services/ramon/fluxos/contexto.rb`:

```ruby
# O que um passo enxerga: o alvo (lead/conversa) recarregado a cada passo + variáveis
# da execução. `dados` alimenta condições e o `{chave}` dos textos.
class Ramon::Fluxos::Contexto
  # o que o gatilho traz e vira variável: {texto} da mensagem, {quando} da reunião,
  # {regra} do evento do ADVBOX, {documento} do anexo casado com o checklist
  DO_GATILHO = %w[texto quando regra documento].freeze

  attr_reader :execucao

  def initialize(execucao)
    @execucao = execucao
  end

  def lead = @lead ||= execucao.lead

  def conversa = @conversa ||= execucao.conversa

  def ensaio? = execucao.ensaio

  # campos livres primeiro: um campo chamado "nome" nunca pisa no nome do lead
  def dados
    @dados ||= campos_livres.merge(dados_lead, dados_funil, dados_conversa, dados_docs, dados_gatilho,
                                   execucao.contexto['vars'] || {})
  end
```

(manter `interpolar`, `contato`, `dados_lead`, `dados_funil`, `dados_conversa` como estão) e, no fim da seção `private`:

```ruby
  def dados_gatilho
    gatilho = execucao.contexto['gatilho'] || {}
    DO_GATILHO.index_with { |chave| gatilho[chave] }
  end

  # preencher_campo grava em custom_attributes['campos'] (Passos::Lead)
  def campos_livres
    campos = lead&.custom_attributes&.dig('campos')
    campos.is_a?(Hash) ? campos : {}
  end

  # Checklist da tese (LeadDocs): conta só o que a equipe confirmou ('recebido');
  # sugestão da IA (doc_sugestao) não conta. Sem checklist → nil ("igual sim" dá não).
  def dados_docs
    lista = lead&.doc_checklist || []
    faltam = lista.reject { |doc| doc[:status] == 'recebido' }
    completos = faltam.empty? ? 'sim' : 'nao'
    { 'documentos_completos' => (completos if lista.any?), 'documentos_faltantes' => faltam.pluck(:title).join(', ') }
  end
```

- [ ] **Step 4: Run to verify it passes** — `bundle exec rspec spec/services/ramon/fluxos/contexto_spec.rb` → PASS (CI). O exemplo antigo `'texto' => 'oi'` continua passando (o `texto` agora vem de `DO_GATILHO`).

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/contexto.rb spec/services/ramon/fluxos/contexto_spec.rb
git commit -m "feat(fluxos): contexto com documentos, campos livres e dados do gatilho" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 2: Grafo — gatilhos e passos da B2b no desenho

**Files:**
- Modify: `app/services/ramon/fluxos/grafo.rb:7-14` (constantes), `:47-53` (`erros_gatilho`), `:104-135` (`erros_especificos`, `erros_se`, novos)
- Test: `spec/services/ramon/fluxos/grafo_spec.rb`

**Interfaces:**
- Produces: `Grafo::GATILHOS` (+ `lead_parado relogio reuniao_marcada reuniao_cancelada evento_advbox contrato_assinado contrato_recusado documento_recebido`), `Grafo::TIPOS_PASSO` (+ `perguntar_ia rascunho_ia rodar_skill advbox webhook registrar_atividade trocar_responsavel preencher_campo`), `Grafo::OBRIGATORIOS`, `Grafo::HORA`, `Grafo::CHAVE_CAMPO`. Mensagens exatas (o front acende o passo por `Passo <id>`):
  - `"Passo #{id} (Perguntar à IA) precisa de pelo menos uma saída"`
  - `"Passo #{id}: escolha tarefa ou movimentação do ADVBOX"`, `"Passo #{id}: falta tipo_tarefa_id"`, `"Passo #{id}: falta responsavel_id"`, `"Passo #{id}: a movimentação do ADVBOX precisa de pelo menos 10 letras"`
  - `"Passo #{id}: o webhook precisa de um endereço https://"`, `"Passo #{id} (Webhook) tem que ser o último passo"`
  - `"Passo #{id}: nome do campo só com letras minúsculas, números e _ (até 40)"`
  - `'O relógio precisa da hora (HH:MM)'`, `'Hora do gatilho inválida (use HH:MM)'`
- Config dos passos (contrato com Tasks 3-5 e 8-9):
  - `perguntar_ia {pergunta}`; `rascunho_ia {instrucao}`; `rodar_skill {assistente_id, skill_id, instrucao?}`
  - `advbox {acao: 'tarefa'|'movimentacao', tipo_tarefa_id?, responsavel_id?, prazo_dias?, descricao}`; `webhook {url}`
  - `registrar_atividade {texto}`; `trocar_responsavel {papel: 'sdr'|'closer', user_id?}`; `preencher_campo {chave, valor}`
  - gatilhos: `lead_parado {hora?, dias?}`, `relogio {hora, etapa_ids?, tese_ids?, responsavel_ids?}`, `evento_advbox {regras?: [chave do handler]}`

- [ ] **Step 1: Write the failing tests** (acrescentar em `spec/services/ramon/fluxos/grafo_spec.rb`)

```ruby
  it 'aceita os gatilhos e passos da B2b' do
    d = grafo_linear({ 'tipo' => 'relogio', 'hora' => '09:00' },
                     ['registrar_atividade', { 'texto' => 'a' }], ['trocar_responsavel', { 'papel' => 'closer' }],
                     ['preencher_campo', { 'chave' => 'beneficio', 'valor' => 'BPC' }],
                     ['rascunho_ia', { 'instrucao' => 'Lembre dos documentos' }],
                     ['advbox', { 'acao' => 'movimentacao', 'descricao' => 'Contrato assinado no hub' }],
                     ['webhook', { 'url' => 'https://hooks.exemplo.com.br/x' }])
    expect(grafo(d).erros).to eq([])
  end

  it 'webhook: só https e só como último passo' do
    d = grafo_linear({ 'tipo' => 'manual' }, ['webhook', { 'url' => 'http://hooks.exemplo.com.br' }], ['nota_privada', { 'texto' => 'a' }])
    expect(grafo(d).erros).to include('Passo p1: o webhook precisa de um endereço https://',
                                      'Passo p1 (Webhook) tem que ser o último passo')
  end

  it 'advbox: escolhe a ação e preenche o que cada uma pede' do
    sem_acao = grafo_linear({ 'tipo' => 'manual' }, ['advbox', {}])
    expect(grafo(sem_acao).erros).to eq(['Passo p1: escolha tarefa ou movimentação do ADVBOX'])
    tarefa = grafo_linear({ 'tipo' => 'manual' }, ['advbox', { 'acao' => 'tarefa' }])
    expect(grafo(tarefa).erros).to eq(['Passo p1: falta tipo_tarefa_id', 'Passo p1: falta responsavel_id'])
    curta = grafo_linear({ 'tipo' => 'manual' }, ['advbox', { 'acao' => 'movimentacao', 'descricao' => 'curta' }])
    expect(grafo(curta).erros).to eq(['Passo p1: a movimentação do ADVBOX precisa de pelo menos 10 letras'])
  end

  it 'perguntar à IA precisa de saída; preencher campo valida a chave; IA e skill têm obrigatórios' do
    d = grafo_linear({ 'tipo' => 'manual' }, ['perguntar_ia', { 'pergunta' => 'Mandou o CNIS?' }])
    expect(grafo(d).erros).to eq(['Passo p1 (Perguntar à IA) precisa de pelo menos uma saída'])
    c = grafo_linear({ 'tipo' => 'manual' }, ['preencher_campo', { 'chave' => 'Benefício' }], ['rodar_skill', {}])
    expect(grafo(c).erros).to eq(['Passo p1: nome do campo só com letras minúsculas, números e _ (até 40)',
                                  'Passo p2: falta assistente_id', 'Passo p2: falta skill_id'])
  end

  it 'relógio precisa da hora; hora torta é recusada; lead parado aceita sem hora' do
    expect(grafo(grafo_linear({ 'tipo' => 'relogio' })).erros).to eq(['O relógio precisa da hora (HH:MM)'])
    expect(grafo(grafo_linear({ 'tipo' => 'lead_parado', 'hora' => '25:00' })).erros).to eq(['Hora do gatilho inválida (use HH:MM)'])
    expect(grafo(grafo_linear({ 'tipo' => 'lead_parado' })).erros).to eq([])
  end
```

- [ ] **Step 2: Run to verify it fails** — `bundle exec rspec spec/services/ramon/fluxos/grafo_spec.rb` → FAIL ("Gatilho desconhecido: relogio", "tipo desconhecido").

- [ ] **Step 3: Implementation** — em `app/services/ramon/fluxos/grafo.rb`:

Constantes (substituem `:7-14`; o comentário do topo ganha "webhook só como último passo"):

```ruby
  GATILHOS = %w[conversa_criada mensagem_recebida conversa_resolvida conversa_reaberta conversa_atribuida
                lead_criado lead_mudou_etapa lead_ganho lead_perdido manual
                lead_parado relogio reuniao_marcada reuniao_cancelada evento_advbox
                contrato_assinado contrato_recusado documento_recebido].freeze
  TIPOS_PASSO = %w[se escolha esperar parar rascunho_texto nota_privada acao_chatwoot
                   mover_etapa criar_tarefa avisar_sino avisar_push
                   perguntar_ia rascunho_ia rodar_skill advbox webhook
                   registrar_atividade trocar_responsavel preencher_campo].freeze
  OBRIGATORIOS = {
    'rascunho_texto' => %w[texto], 'nota_privada' => %w[texto], 'mover_etapa' => %w[etapa_id],
    'criar_tarefa' => %w[titulo], 'escolha' => %w[campo], 'avisar_sino' => %w[texto], 'avisar_push' => %w[texto],
    'perguntar_ia' => %w[pergunta], 'rascunho_ia' => %w[instrucao], 'rodar_skill' => %w[assistente_id skill_id],
    'registrar_atividade' => %w[texto], 'trocar_responsavel' => %w[papel]
  }.freeze
  # tipo → método com as regras próprias do passo (além dos obrigatórios)
  ESPECIFICOS = {
    'se' => :erros_se, 'perguntar_ia' => :erros_saida, 'escolha' => :erros_escolha, 'esperar' => :erros_esperar,
    'acao_chatwoot' => :erros_chatwoot, 'advbox' => :erros_advbox, 'webhook' => :erros_webhook, 'preencher_campo' => :erros_campo
  }.freeze
  NOMES = { 'se' => 'Se', 'perguntar_ia' => 'Perguntar à IA' }.freeze
  HORA = /\A([01]\d|2[0-3]):[0-5]\d\z/
  CHAVE_CAMPO = /\A[a-z][a-z0-9_]{0,39}\z/
```

`erros_gatilho` (substitui `:47-53`) + `erros_hora`:

```ruby
  def erros_gatilho
    gatilhos = nos.select { |n| n['tipo'] == 'gatilho' }
    return ['O fluxo precisa de exatamente 1 gatilho'] unless gatilhos.one?

    config = gatilhos.first['config'] || {}
    return ["Gatilho desconhecido: #{config['tipo']}"] unless GATILHOS.include?(config['tipo'])

    erros_hora(config)
  end

  # relógio exige a hora; lead parado usa 11:00 (Relogio::HORA_PADRAO) se vier vazia
  def erros_hora(config)
    hora = config['hora'].to_s
    return ['O relógio precisa da hora (HH:MM)'] if config['tipo'] == 'relogio' && hora.empty?

    hora.empty? || hora.match?(HORA) ? [] : ['Hora do gatilho inválida (use HH:MM)']
  end
```

`erros_especificos` e `erros_se` (substituem `:104-119`; o `case` com 8 tipos passaria do `CyclomaticComplexity` 7 — por isso a tabela) + os novos, antes de `espera_valida?`:

```ruby
  def erros_especificos(passo, config)
    metodo = ESPECIFICOS[passo['tipo']]
    metodo ? send(metodo, passo, config) : []
  end

  def erros_se(passo, config)
    erros = Array(config['condicoes']).empty? ? ["Passo #{passo['id']} (Se) precisa de condições"] : []
    erros + erros_saida(passo, config)
  end

  def erros_saida(passo, _config)
    return [] if setas.any? { |s| s['de'] == passo['id'] }

    ["Passo #{passo['id']} (#{NOMES[passo['tipo']]}) precisa de pelo menos uma saída"]
  end

  def erros_esperar(passo, config) = espera_valida?(config) ? [] : ["Passo #{passo['id']}: falta o tempo de espera"]

  # IDs fixos escolhidos na tela (advbox_configuracoes) — escrita determinística, não é a IA decidindo
  def erros_advbox(passo, config)
    id = passo['id']
    case config['acao']
    when 'tarefa' then %w[tipo_tarefa_id responsavel_id].select { |k| config[k].blank? }.map { |k| "Passo #{id}: falta #{k}" }
    when 'movimentacao'
      config['descricao'].to_s.strip.length >= 10 ? [] : ["Passo #{id}: a movimentação do ADVBOX precisa de pelo menos 10 letras"]
    else ["Passo #{id}: escolha tarefa ou movimentação do ADVBOX"]
    end
  end

  # regra do Flowter: webhook só no fim; https só (o SafeFetch ainda barra rede interna na hora de rodar)
  def erros_webhook(passo, config)
    erros = []
    erros << "Passo #{passo['id']}: o webhook precisa de um endereço https://" unless config['url'].to_s.start_with?('https://')
    erros << "Passo #{passo['id']} (Webhook) tem que ser o último passo" if setas.any? { |s| s['de'] == passo['id'] }
    erros
  end

  def erros_campo(passo, config)
    config['chave'].to_s.match?(CHAVE_CAMPO) ? [] : ["Passo #{passo['id']}: nome do campo só com letras minúsculas, números e _ (até 40)"]
  end
```

(`erros_escolha`, `espera_valida?`, `erros_chatwoot` ficam como estão.) Conferir `ClassLength` ≤ 175 linhas de código (estimativa ~160).

- [ ] **Step 4: Run** — `bundle exec rspec spec/services/ramon/fluxos/grafo_spec.rb` → PASS (CI); os exemplos antigos (`(Se) precisa de pelo menos uma saída`, `falta o tempo de espera`) continuam com o mesmo texto.

- [ ] **Step 5: Commit** — `git add app/services/ramon/fluxos/grafo.rb spec/services/ramon/fluxos/grafo_spec.rb` → `feat(fluxos): gatilhos e passos da B2b no desenho (webhook só no fim, https)` + rodapé.

---

### Task 3: Passos de lead (atividade, responsável, campo) + trilha a cada passo

**Files:**
- Modify: `app/services/ramon/fluxos/passos/lead.rb` (acrescentar 3 métodos)
- Modify: `app/services/ramon/fluxos/executor.rb:1-17` (comentário, `VISIVEIS`, `PASSOS`), `:74-89` (`andar`)
- Modify: `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json` → `RAMON.LEAD_PANEL.HISTORY.KIND` + `"FLUXO"`
- Test: `spec/services/ramon/fluxos/passos_spec.rb`, `spec/services/ramon/fluxos/executor_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Papeis::COLUNA` (`{'sdr' => :sdr_id, 'closer' => :closer_id}`) e `Ramon::Papeis.proximo(account, papel)` (`app/services/ramon/papeis.rb:9,26-33`); o callback `record_change` do Lead já grava `sdr_changed`/`closer_changed`.
- Produces: `Passos::Lead.registrar_atividade/trocar_responsavel/preencher_campo(config, ctx)`; atividade `LeadActivity kind: 'fluxo'`; `custom_attributes['campos'][chave]`.

- [ ] **Step 1: Write the failing tests** — em `spec/services/ramon/fluxos/passos_spec.rb`:

```ruby
  it 'registrar atividade escreve na linha do tempo do lead' do
    Ramon::Fluxos::Passos::Lead.registrar_atividade({ 'texto' => 'Boas-vindas para {nome}' }, ctx)
    expect(lead.lead_activities.find_by(kind: 'fluxo').to_value).to start_with('Boas-vindas para')
  end

  it 'trocar responsável: a pessoa escolhida ou o próximo do time' do
    ana = create(:user, account: account)
    Ramon::Fluxos::Passos::Lead.trocar_responsavel({ 'papel' => 'closer', 'user_id' => ana.id }, ctx)
    expect(lead.reload.closer).to eq(ana)
    create(:team_member, team: create(:team, account: account, name: 'sdr'), user: ana)
    r = Ramon::Fluxos::Passos::Lead.trocar_responsavel({ 'papel' => 'sdr' }, ctx)
    expect(lead.reload.sdr).to eq(ana)
    expect(r[:resumo]).to eq("sdr → #{ana.name}")
  end

  it 'trocar responsável com time vazio não quebra' do
    r = Ramon::Fluxos::Passos::Lead.trocar_responsavel({ 'papel' => 'sdr' }, ctx)
    expect(r[:resumo]).to eq('sdr: ninguém no time')
  end

  it 'preencher campo relê o lead e junta só na chave campos' do
    c = ctx
    c.lead # carregado antes da escrita concorrente
    Lead.find(lead.id).update!(custom_attributes: { 'zapsign' => { 'status' => 'signed' } })
    Ramon::Fluxos::Passos::Lead.preencher_campo({ 'chave' => 'beneficio', 'valor' => 'BPC' }, c)
    expect(lead.reload.custom_attributes).to eq('zapsign' => { 'status' => 'signed' }, 'campos' => { 'beneficio' => 'BPC' })
  end

  it 'ensaio dos passos de lead não grava nada' do
    c = ctx(ensaio: true)
    expect do
      Ramon::Fluxos::Passos::Lead.registrar_atividade({ 'texto' => 'a' }, c)
      Ramon::Fluxos::Passos::Lead.preencher_campo({ 'chave' => 'x', 'valor' => 'y' }, c)
    end.not_to(change { [lead.lead_activities.count, lead.reload.custom_attributes] })
  end
```

Em `spec/services/ramon/fluxos/executor_spec.rb`:

```ruby
  it 'grava a execução a cada passo (passo lento não parece órfão ao relógio)' do
    vistos = []
    allow(Ramon::Fluxos::Passos::Lead).to receive(:registrar_atividade) do |_config, ctx|
      vistos << FluxoExecucao.find(ctx.execucao.id).trilha.size
      { saida: 's', resumo: 'ok' }
    end
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['nota_privada', { 'texto' => 'a' }], ['registrar_atividade', { 'texto' => 'b' }]))
    avancar(e)
    expect(vistos).to eq([1])
    expect(e.status).to eq('concluida')
  end
```

- [ ] **Step 2: Run** — `bundle exec rspec spec/services/ramon/fluxos/passos_spec.rb spec/services/ramon/fluxos/executor_spec.rb` → FAIL (`undefined method registrar_atividade`, `KeyError: key not found: "registrar_atividade"`).

- [ ] **Step 3: Implementation** — `app/services/ramon/fluxos/passos/lead.rb`, antes de `responsavel_da_tarefa`:

```ruby
  def registrar_atividade(config, ctx)
    lead = exigir_lead(ctx)
    texto = ctx.interpolar(config['texto']).truncate(255)
    return { saida: 's', resumo: "faria: atividade \"#{texto.truncate(80)}\"" } if ctx.ensaio?

    lead.lead_activities.create!(account: lead.account, kind: 'fluxo', to_value: texto)
    { saida: 's', resumo: "atividade: #{texto.truncate(80)}" }
  end

  # SDR/Closer (Ramon::Papeis): pessoa escolhida na tela ou o próximo do time (menos leads abertos).
  # A troca grava sdr_changed/closer_changed pelo callback do Lead.
  def trocar_responsavel(config, ctx)
    lead = exigir_lead(ctx)
    papel = config['papel']
    coluna = Ramon::Papeis::COLUNA.fetch(papel)
    pessoa = config['user_id'].present? ? lead.account.users.find(config['user_id']) : Ramon::Papeis.proximo(lead.account, papel)
    return { saida: 's', resumo: "#{papel}: ninguém no time" } if pessoa.nil?
    return { saida: 's', resumo: "faria: #{papel} → #{pessoa.name}" } if ctx.ensaio?

    lead.update!(coluna => pessoa.id)
    { saida: 's', resumo: "#{papel} → #{pessoa.name}" }
  end

  # Grava em custom_attributes['campos'] (nunca na raiz: zapsign/advbox/doc_status são do hub).
  # Lição lost update: relê e junta só a chave do fluxo.
  def preencher_campo(config, ctx)
    lead = exigir_lead(ctx)
    chave = config['chave']
    valor = ctx.interpolar(config['valor']).truncate(500)
    return { saida: 's', resumo: "faria: #{chave} = #{valor.truncate(60)}" } if ctx.ensaio?

    lead.reload
    campos = (lead.custom_attributes['campos'] || {}).merge(chave => valor)
    lead.update!(custom_attributes: lead.custom_attributes.to_h.merge('campos' => campos))
    { saida: 's', resumo: "#{chave} = #{valor.truncate(60)}" }
  end
```

`app/services/ramon/fluxos/executor.rb` — comentário do topo ganha a linha `# Passos lentos (IA, ADVBOX) também rodam fora de transação; a execução é gravada a cada passo.`; constantes:

```ruby
  VISIVEIS = %w[mover_etapa criar_tarefa acao_chatwoot avisar_sino avisar_push trocar_responsavel preencher_campo].freeze
  PASSOS = {
    'se' => Ramon::Fluxos::Passos::Logica, 'escolha' => Ramon::Fluxos::Passos::Logica,
    'esperar' => Ramon::Fluxos::Passos::Logica, 'parar' => Ramon::Fluxos::Passos::Logica,
    'rascunho_texto' => Ramon::Fluxos::Passos::Conversa, 'nota_privada' => Ramon::Fluxos::Passos::Conversa,
    'acao_chatwoot' => Ramon::Fluxos::Passos::Conversa,
    'mover_etapa' => Ramon::Fluxos::Passos::Lead, 'criar_tarefa' => Ramon::Fluxos::Passos::Lead,
    'registrar_atividade' => Ramon::Fluxos::Passos::Lead, 'trocar_responsavel' => Ramon::Fluxos::Passos::Lead,
    'preencher_campo' => Ramon::Fluxos::Passos::Lead,
    'avisar_sino' => Ramon::Fluxos::Passos::Aviso, 'avisar_push' => Ramon::Fluxos::Passos::Aviso
  }.freeze
```

`andar` — logo depois de `registrar(passo, resultado)`:

```ruby
      registrar(passo, resultado)
      @execucao.save! # a cada passo: o relógio só vê "órfã" se UM passo passar de 10 min
```

i18n (Edit à mão, dentro de `RAMON.LEAD_PANEL.HISTORY.KIND`, ao lado de `ZAPSIGN_REFUSED` — linha ~1014 nos dois arquivos):
- pt_BR: `"FLUXO": "registrou (automação)",`
- en: `"FLUXO": "logged (automation)",`

- [ ] **Step 4: Run** — specs da Step 2 → PASS (CI). `./node_modules/.bin/eslint` não se aplica a JSON; conferir que o JSON abre: `node -e "require('./app/javascript/dashboard/i18n/locale/pt_BR/ramon.json');require('./app/javascript/dashboard/i18n/locale/en/ramon.json')"`.

- [ ] **Step 5: Commit** — `git add app/services/ramon/fluxos/passos/lead.rb app/services/ramon/fluxos/executor.rb app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json spec/services/ramon/fluxos/passos_spec.rb spec/services/ramon/fluxos/executor_spec.rb` → `feat(fluxos): registrar atividade, trocar responsável e preencher campo` + rodapé.

---

### Task 4: Passos ADVBOX e webhook + opções do ADVBOX para a tela

**Files:**
- Create: `app/services/ramon/fluxos/passos/externo.rb`
- Modify: `app/services/ramon/fluxos/executor.rb` (`VISIVEIS` + `PASSOS`)
- Modify: `app/controllers/api/v1/accounts/ramon_fluxos_controller.rb:4` (before_action) + action nova; `config/routes.rb:343-350`
- Modify: `app/javascript/dashboard/api/ramonFluxos.js`
- Test: `spec/services/ramon/fluxos/passos_externo_spec.rb` (novo), `spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb`

**Interfaces:**
- Consumes: `Ramon::AdvboxMcpService::FETCHERS['advbox_criar_tarefa' | 'advbox_criar_movimentacao']` (`app/services/ramon/advbox_mcp_service.rb:199-204` — o mesmo caminho do MCP: `tarefa_payload` monta `from/guests/tasks_id/lawsuits_id/start_date/date_deadline/comments`; movimentação converte a data para DD/MM/YYYY); processo do lead = `lead.custom_attributes['advbox']['lawsuits_id']` (gravado por `AdvboxClosingService`, mesmo uso em `advbox_docs_task_service.rb:24`); `SafeFetch.fetch(url, method: :post, body:, headers:, open_timeout:, read_timeout:, validate_content_type: false) { |_r| nil }` (mesmo uso de `lib/webhooks/trigger.rb:42-51`); `Ramon::AdvboxClient.settings` (`users: [{id, name, email}]`, `tasks: [{id, task}]` — conferido na API real 06/10).
- Produces: `Passos::Externo.advbox(config, ctx)`, `Passos::Externo.webhook(config, ctx)`, `Passos::Externo.payload(ctx)`; `GET /api/v1/accounts/:id/ramon_fluxos/opcoes_advbox` → `{ usuarios: [{id, nome}], tipos_tarefa: [{id, nome}] }` (503 `{erro}` se o ADVBOX cair); front `RamonFluxosAPI.opcoesAdvbox()`.

- [ ] **Step 1: Write the failing tests** — `spec/services/ramon/fluxos/passos_externo_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Passos::Externo do
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account) }
  let(:lead) do
    create(:lead, account: account, conversation: conversa, contact: conversa.contact,
                  custom_attributes: { 'advbox' => { 'lawsuits_id' => 77 } })
  end
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' }), nome: 'Pós-contrato') }

  def ctx(alvo: lead, ensaio: false)
    Ramon::Fluxos::Contexto.new(fluxo.execucoes.create!(account: account, alvo: alvo, ensaio: ensaio))
  end

  describe 'advbox' do
    it 'cria tarefa FIXA no processo do lead com os IDs escolhidos na tela' do
      allow(Ramon::AdvboxClient).to receive(:create_post).and_return('posts_id' => 9)
      travel_to(Time.zone.parse('2026-10-06 13:00:00 UTC')) do
        described_class.advbox({ 'acao' => 'tarefa', 'tipo_tarefa_id' => 8_745_408, 'responsavel_id' => 266_778,
                                 'prazo_dias' => 2, 'descricao' => 'Conferir documentos' }, ctx)
      end
      expect(Ramon::AdvboxClient).to have_received(:create_post).with(
        hash_including(lawsuits_id: '77', tasks_id: '8745408', guests: [266_778], date_deadline: '2026-10-08', comments: 'Conferir documentos')
      )
    end

    it 'registra movimentação no processo do lead' do
      allow(Ramon::AdvboxClient).to receive(:create_movement)
      travel_to(Time.zone.parse('2026-10-06 13:00:00 UTC')) do
        described_class.advbox({ 'acao' => 'movimentacao', 'descricao' => 'Contrato assinado pelo cliente' }, ctx)
      end
      expect(Ramon::AdvboxClient).to have_received(:create_movement)
        .with(lawsuit_id: 77, description: 'Contrato assinado pelo cliente', date: '06/10/2026')
    end

    it 'lead sem processo no ADVBOX falha na hora (não adianta repetir)' do
      sem = create(:lead, account: account)
      expect { described_class.advbox({ 'acao' => 'movimentacao', 'descricao' => 'xxxxxxxxxxxx' }, ctx(alvo: sem)) }
        .to raise_error(Ramon::Fluxos::PassoImpossivel, /processo no ADVBOX/)
    end

    it 'recusa do ADVBOX (4xx) também não se repete' do
      allow(Ramon::AdvboxClient).to receive(:create_post).and_raise(Ramon::AdvboxClient::RequestError.new(422, { 'erro' => 'x' }))
      expect { described_class.advbox({ 'acao' => 'tarefa', 'tipo_tarefa_id' => 1, 'responsavel_id' => 2 }, ctx) }
        .to raise_error(Ramon::Fluxos::PassoImpossivel, /HTTP 422/)
    end
  end

  describe 'webhook' do
    let(:url) { 'https://hooks.exemplo.com.br/fluxo' }

    it 'POST JSON só com os dados do caso, timeout curto' do
      corpo = nil
      allow(SafeFetch).to receive(:fetch) { |_u, **opts| corpo = JSON.parse(opts[:body]) }
      described_class.webhook({ 'url' => url }, ctx)
      expect(SafeFetch).to have_received(:fetch).with(url, hash_including(method: :post, open_timeout: 2, read_timeout: 5))
      expect(corpo.keys).to match_array(%w[fluxo fluxo_id execucao_id alvo_tipo alvo_id lead_id enviado_em dados])
      expect(corpo).to include('fluxo' => 'Pós-contrato', 'lead_id' => lead.id)
    end

    it 'endereço de rede interna é recusado na hora' do
      allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::UnsafeUrlError, 'private network')
      expect { described_class.webhook({ 'url' => 'https://10.0.0.5/x' }, ctx) }
        .to raise_error(Ramon::Fluxos::PassoImpossivel, /webhook recusado/)
    end
  end

  it 'ensaio não grava no ADVBOX nem chama o webhook' do
    allow(Ramon::AdvboxClient).to receive(:create_post)
    allow(SafeFetch).to receive(:fetch)
    c = ctx(ensaio: true)
    expect(described_class.advbox({ 'acao' => 'tarefa', 'tipo_tarefa_id' => 1, 'responsavel_id' => 2 }, c)[:resumo]).to start_with('faria: ')
    expect(described_class.webhook({ 'url' => 'https://hooks.exemplo.com.br/x?token=segredo' }, c)[:resumo])
      .to eq('faria: POST para hooks.exemplo.com.br') # na trilha só o host, nunca o token da URL
    expect(Ramon::AdvboxClient).not_to have_received(:create_post)
    expect(SafeFetch).not_to have_received(:fetch)
  end
end
```

Em `spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb`:

```ruby
  it 'opções do ADVBOX para o passo (só admin, sem e-mail)' do
    allow(Ramon::AdvboxClient).to receive(:settings).and_return(
      'users' => [{ 'id' => 266_778, 'name' => 'EDUARDO SCHLATA', 'email' => 'nao-sai' }],
      'tasks' => [{ 'id' => 8_745_408, 'task' => 'AGUARDANDO DOCUMENTOS CLIENTE', 'reward' => 5 }]
    )
    get "#{url}/opcoes_advbox", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to eq('usuarios' => [{ 'id' => 266_778, 'nome' => 'EDUARDO SCHLATA' }],
                                       'tipos_tarefa' => [{ 'id' => 8_745_408, 'nome' => 'AGUARDANDO DOCUMENTOS CLIENTE' }])
    get "#{url}/opcoes_advbox", headers: agente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'ADVBOX fora do ar devolve 503' do
    allow(Ramon::AdvboxClient).to receive(:settings).and_raise(Ramon::AdvboxClient::UnavailableError, 'AdvBox indisponível')
    get "#{url}/opcoes_advbox", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:service_unavailable)
  end
```

- [ ] **Step 2: Run** — `bundle exec rspec spec/services/ramon/fluxos/passos_externo_spec.rb spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb` → FAIL (constante/rota inexistentes).

- [ ] **Step 3: Implementation** — `app/services/ramon/fluxos/passos/externo.rb`:

```ruby
# Passos que falam com sistemas de fora (spec §4.3):
# - advbox: tarefa ou movimentação FIXA no processo do lead, com IDs escolhidos na tela
#   (advbox_configuracoes) — escrita determinística pelo mesmo caminho do MCP, não é a IA decidindo.
# - webhook: POST JSON do contexto; só como último passo (Grafo#erros_webhook); SafeFetch barra
#   rede interna; nunca leva token/env/config do hub.
module Ramon::Fluxos::Passos::Externo
  FERRAMENTA = { 'tarefa' => 'advbox_criar_tarefa', 'movimentacao' => 'advbox_criar_movimentacao' }.freeze
  ABRIR = 2 # segundos
  LER = 5

  module_function

  def advbox(config, ctx)
    lead = Ramon::Fluxos::Passos::Lead.exigir_lead(ctx)
    processo = lead.custom_attributes&.dig('advbox', 'lawsuits_id')
    raise Ramon::Fluxos::PassoImpossivel, 'o lead ainda não tem processo no ADVBOX' if processo.blank?
    return { saida: 's', resumo: "faria: #{config['acao']} no ADVBOX (processo #{processo})" } if ctx.ensaio?

    Ramon::AdvboxMcpService::FETCHERS.fetch(FERRAMENTA.fetch(config['acao'])).call(argumentos(config, processo, ctx))
    { saida: 's', resumo: "ADVBOX: #{config['acao']} no processo #{processo}" }
  rescue Ramon::AdvboxClient::RequestError => e
    raise Ramon::Fluxos::PassoImpossivel, "ADVBOX recusou (HTTP #{e.code})"
  end

  def argumentos(config, processo, ctx)
    base = { 'processo_id' => processo, 'descricao' => ctx.interpolar(config['descricao']) }
    return base if config['acao'] == 'movimentacao'

    prazo = (Time.find_zone!(Fluxo::ZONA).today + config['prazo_dias'].to_i).iso8601 if config['prazo_dias'].present?
    base.merge('tipo_tarefa_id' => config['tipo_tarefa_id'], 'responsavel_id' => config['responsavel_id'], 'prazo' => prazo)
  end

  def webhook(config, ctx)
    url = config['url'].to_s
    return { saida: 's', resumo: "faria: POST para #{host(url)}" } if ctx.ensaio?

    SafeFetch.fetch(url, method: :post, body: payload(ctx).to_json, headers: { 'Content-Type' => 'application/json' },
                         open_timeout: ABRIR, read_timeout: LER, validate_content_type: false) { |_resposta| nil }
    { saida: 's', resumo: "webhook: POST para #{host(url)}" }
  rescue SafeFetch::InvalidUrlError, SafeFetch::UnsafeUrlError => e
    raise Ramon::Fluxos::PassoImpossivel, "endereço do webhook recusado (#{e.message.truncate(80)})"
  end

  # Só o caso — nada de token, env ou config do hub.
  def payload(ctx)
    execucao = ctx.execucao
    { fluxo: execucao.fluxo.nome, fluxo_id: execucao.fluxo_id, execucao_id: execucao.id, alvo_tipo: execucao.alvo_type,
      alvo_id: execucao.alvo_id, lead_id: ctx.lead&.id, enviado_em: Time.current.iso8601, dados: ctx.dados }
  end

  # a URL pode carregar token (ex.: hooks do Make/Zapier): na trilha só o host
  def host(url) = url[%r{\Ahttps?://([^/?#]+)}, 1] || '?'
end
```

Executor: `VISIVEIS` += `advbox webhook`; `PASSOS` += `'advbox' => Ramon::Fluxos::Passos::Externo, 'webhook' => Ramon::Fluxos::Passos::Externo,`.

Controller (`app/controllers/api/v1/accounts/ramon_fluxos_controller.rb`): linha 4 vira `before_action :fluxo, except: [:index, :create, :opcoes_advbox]`; depois de `rodar`:

```ruby
  # Selects do passo ADVBOX: usuários e tipos de tarefa da conta AdvBox (sem e-mail/telefone).
  def opcoes_advbox
    cfg = Ramon::AdvboxClient.settings
    render json: { usuarios: Array(cfg['users']).map { |u| { id: u['id'], nome: u['name'] } },
                   tipos_tarefa: Array(cfg['tasks']).map { |t| { id: t['id'], nome: t['task'] } } }
  rescue Ramon::AdvboxClient::UnavailableError => e
    render json: { erro: e.message }, status: :service_unavailable
  end
```

`config/routes.rb` (bloco `resources :ramon_fluxos`, :343-350) — depois do `member do … end`:

```ruby
            collection do
              get :opcoes_advbox
            end
```

`app/javascript/dashboard/api/ramonFluxos.js` — antes de `execucoes(id)`:

```js
  // { usuarios: [{id, nome}], tipos_tarefa: [{id, nome}] } — passo ADVBOX
  opcoesAdvbox() {
    return axios.get(`${this.url}/opcoes_advbox`);
  }
```

- [ ] **Step 4: Run** — specs da Step 2 → PASS (CI). `./node_modules/.bin/eslint app/javascript/dashboard/api/ramonFluxos.js` → limpo.

- [ ] **Step 5: Commit** — `git add app/services/ramon/fluxos/passos/externo.rb app/services/ramon/fluxos/executor.rb app/controllers/api/v1/accounts/ramon_fluxos_controller.rb config/routes.rb app/javascript/dashboard/api/ramonFluxos.js spec/services/ramon/fluxos/passos_externo_spec.rb spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb` → `feat(fluxos): passos ADVBOX e webhook` + rodapé.

---

### Task 5: Passos de IA (perguntar, rascunho, skill) + teto diário

**Files:**
- Create: `app/services/ramon/fluxos/passos/ia.rb`
- Modify: `app/services/ramon/fluxos/executor.rb` (`PASSOS`)
- Test: `spec/services/ramon/fluxos/passos_ia_spec.rb` (novo), `spec/services/ramon/fluxos/executor_spec.rb`

**Interfaces:**
- Consumes: `Ramon::LlmClient.complete(provider:, model:, system:, user:)` → `Result#content` (`lib/ramon/llm_client.rb:25-37`, timeout 90 s :42); `Ramon::Pseudonymizer.mask(texto, names:)`; `LlmFormatter::ConversationLlmFormatter.new(conversa).format(token_limit:)` (`app/services/llm_formatter/conversation_llm_formatter.rb:2-22`, sem notas privadas — os rascunhos não voltam pro prompt); `Ramon::Fluxos::Passos::Conversa.escrever(ctx, texto)`; `Ramon::Fluxos::Condicao.normal`; `Redis::Alfred.incr/expire`; enterprise: `Captain::Scenario` (skill; `enabled`, `title`, `assistant`), `Captain::Assistant::AgentRunnerService.new(assistant:, source:).generate_response(message_history:)` → `{'response', 'reasoning'}`; erro = `'response' => 'conversation_handoff'` com `reasoning` `"Error occurred: …"` (`enterprise/app/services/captain/assistant/agent_runner_service.rb:35-42,106-112`).
- Produces: `Passos::Ia.perguntar_ia/rascunho_ia/rodar_skill(config, ctx)`; todos devolvem `vars: {'resposta_ia' => …}`; env `RAMON_FLUXO_IA_DIA` (padrão 200).

**Decisão de produto embutida (rodar_skill):** o runner roda **sem `conversation:`** (igual ao "Testar"/playground). Assim nenhuma ferramenta da skill age na conversa — o `HandoffTool` (`enterprise/app/services/captain/tools/handoff_tool.rb`) abriria a conversa e poderia mandar a **mensagem de fora do horário ao cliente**; sem conversa no estado ele não acha a conversa e não faz nada. A conversa entra só como texto (pseudonimizado) no pedido. Efeito do passo = nota privada + `{resposta_ia}`.

- [ ] **Step 1: Write the failing tests** — `spec/services/ramon/fluxos/passos_ia_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Passos::Ia do
  let(:account) { create(:account) }
  let(:contato) { create(:contact, account: account, name: 'Maria da Silva') }
  let(:conversa) { create(:conversation, account: account, contact: contato) }
  let(:lead) { create(:lead, account: account, contact: contato, conversation: conversa, name: 'Maria da Silva') }
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' })) }

  def ctx(ensaio: false)
    Ramon::Fluxos::Contexto.new(fluxo.execucoes.create!(account: account, alvo: lead, ensaio: ensaio))
  end

  def llm(conteudo)
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(Ramon::LlmClient::Result.new(content: conteudo, input_tokens: 1, output_tokens: 1))
  end

  it 'perguntar_ia sai por sim/não, a justificativa vira {resposta_ia} e o nome não sai do hub' do
    llm(%(```json\n{"resposta": "Sim", "justificativa": "[nome] já mandou o CNIS"}\n```))
    r = described_class.perguntar_ia({ 'pergunta' => 'A {nome} mandou o CNIS?' }, ctx)
    expect(r).to include(saida: 'sim', vars: { 'resposta_ia' => 'Maria já mandou o CNIS' })
    expect(Ramon::LlmClient).to have_received(:complete)
      .with(hash_including(user: satisfy { |u| u.include?('[nome]') && u.exclude?('Maria') }))
  end

  it 'perguntar_ia: resposta que não é sim sai por não' do
    llm('{"resposta": "talvez", "justificativa": "não dá pra saber"}')
    expect(described_class.perguntar_ia({ 'pergunta' => 'x' }, ctx)[:saida]).to eq('nao')
  end

  it 'rascunho_ia grava nota RASCUNHO com o texto da IA (nunca mensagem pública)' do
    llm('Oi [nome], tudo bem? Falta só o CNIS.')
    r = described_class.rascunho_ia({ 'instrucao' => 'Lembre dos documentos: {documentos_faltantes}' }, ctx)
    nota = conversa.messages.last
    expect(nota.private).to be(true)
    expect(nota.content).to eq("#{Ramon::RascunhoCarimbo::PREFIXO}\nOi Maria, tudo bem? Falta só o CNIS.")
    expect(r[:vars]).to eq('resposta_ia' => 'Oi Maria, tudo bem? Falta só o CNIS.')
  end

  it 'no ensaio, rascunho_ia só descreve (não chama a IA)' do
    allow(Ramon::LlmClient).to receive(:complete)
    expect(described_class.rascunho_ia({ 'instrucao' => 'x' }, ctx(ensaio: true))[:resumo]).to start_with('faria: ')
    expect(Ramon::LlmClient).not_to have_received(:complete)
  end

  it 'teto diário de IA dos fluxos: estourou, o passo falha na hora' do
    llm('{"resposta": "sim", "justificativa": "ok"}')
    with_modified_env(RAMON_FLUXO_IA_DIA: '1') do
      described_class.perguntar_ia({ 'pergunta' => 'x' }, ctx)
      expect { described_class.perguntar_ia({ 'pergunta' => 'x' }, ctx) }.to raise_error(Ramon::Fluxos::PassoImpossivel, /teto/)
    end
  end

  it 'rodar_skill sem enterprise é impossível', unless: ChatwootApp.enterprise? do
    expect { described_class.rodar_skill({ 'assistente_id' => 1, 'skill_id' => 1 }, ctx) }
      .to raise_error(Ramon::Fluxos::PassoImpossivel, /enterprise/)
  end

  context 'rodar_skill', if: ChatwootApp.enterprise? do
    let(:assistente) { create(:captain_assistant, account: account) }
    let(:skill) { create(:captain_scenario, assistant: assistente, account: account, title: 'Resumo do caso') }
    let(:runner) { instance_double(Captain::Assistant::AgentRunnerService) }
    let(:config) { { 'assistente_id' => assistente.id, 'skill_id' => skill.id } }

    before { allow(Captain::Assistant::AgentRunnerService).to receive(:new).and_return(runner) }

    it 'roda sem conversa no estado e o resultado vira nota + {resposta_ia}' do
      allow(runner).to receive(:generate_response).and_return('response' => '[nome] tem 20 anos de CNIS.')
      r = described_class.rodar_skill(config, ctx)
      expect(Captain::Assistant::AgentRunnerService).to have_received(:new).with(assistant: assistente, source: 'fluxo')
      expect(r[:vars]).to eq('resposta_ia' => 'Maria tem 20 anos de CNIS.')
      expect(conversa.messages.last).to have_attributes(private: true, content: "⚙ Skill Resumo do caso:\nMaria tem 20 anos de CNIS.")
    end

    it 'erro do runner vira erro do passo (o executor tenta de novo)' do
      allow(runner).to receive(:generate_response).and_return('response' => 'conversation_handoff', 'reasoning' => 'Error occurred: timeout')
      expect { described_class.rodar_skill(config, ctx) }.to raise_error(RuntimeError, /skill falhou/)
    end

    it 'skill desligada ou de outro assistente é impossível' do
      skill.update!(enabled: false)
      expect { described_class.rodar_skill(config, ctx) }.to raise_error(Ramon::Fluxos::PassoImpossivel, /skill/)
    end
  end
end
```

Em `spec/services/ramon/fluxos/executor_spec.rb`:

```ruby
  it 'todo tipo de passo do desenho tem quem execute' do
    expect(described_class::PASSOS.keys).to match_array(Ramon::Fluxos::Grafo::TIPOS_PASSO)
  end
```

- [ ] **Step 2: Run** — `bundle exec rspec spec/services/ramon/fluxos/passos_ia_spec.rb spec/services/ramon/fluxos/executor_spec.rb` → FAIL.

- [ ] **Step 3: Implementation** — `app/services/ramon/fluxos/passos/ia.rb`:

```ruby
# Passos de IA (spec §4.2/§4.3): perguntar_ia (condição sim/não), rascunho_ia (nota RASCUNHO
# escrita pela IA) e rodar_skill (skill de um assistente do Captain — só enterprise).
# LGPD: o que vai ao LLM passa pelo Pseudonymizer; [nome] volta como o primeiro nome.
# Lock: o Executor reivindica a execução numa transação curta e anda FORA de transação —
# IA lenta (até 90 s, Ramon::LlmClient::REQUEST_TIMEOUT) não segura lock; a trilha é gravada a cada passo.
module Ramon::Fluxos::Passos::Ia
  PROVIDER = 'deepseek'.freeze
  LIMITE_CONVERSA = 8_000 # caracteres do fim da conversa
  # chamadas de IA de fluxo por conta por dia (env RAMON_FLUXO_IA_DIA) — valor é decisão do Eduardo
  TETO_PADRAO = 200
  REGRAS = <<~TXT.freeze
    Regras obrigatórias (Provimento 205/2021 da OAB): nunca prometa resultado, prazo ou valor do INSS; não pressione nem ofereça vantagem;
    não cite valor de honorário diferente de 30% dos atrasados + 3 parcelas do benefício (o mesmo em todas as teses).
    Não invente fatos que não estejam no contexto. Para o nome do cliente escreva exatamente [nome].
  TXT
  SISTEMA_PERGUNTA = <<~TXT.freeze
    Você analisa um caso de um escritório de advocacia previdenciária e responde a uma pergunta de sim ou não.
    Responda APENAS JSON válido (sem markdown): {"resposta": "sim" ou "nao", "justificativa": "<uma frase>"}. Na dúvida, "nao".
    #{REGRAS}
  TXT
  SISTEMA_RASCUNHO = <<~TXT.freeze
    Você redige uma mensagem de WhatsApp que um atendente de um escritório de advocacia previdenciária vai revisar e enviar.
    Tom acolhedor, simples, sem juridiquês; 2 a 4 frases. Responda APENAS com o texto da mensagem, sem aspas nem assinatura.
    #{REGRAS}
  TXT

  module_function

  # Condição: roda de verdade inclusive no ensaio (spec §6).
  def perguntar_ia(config, ctx)
    cota!(ctx)
    pedido = "Pergunta: #{ctx.interpolar(config['pergunta'])}"
    json = JSON.parse(limpar(perguntar(SISTEMA_PERGUNTA, pedido, ctx)))
    sim = Ramon::Fluxos::Condicao.normal(json['resposta']).start_with?('sim')
    justificativa = restaurar(json['justificativa'].to_s, ctx)
    { saida: sim ? 'sim' : 'nao', vars: { 'resposta_ia' => justificativa },
      resumo: "IA: #{sim ? 'sim' : 'não'} — #{justificativa.truncate(100)}" }
  end

  def rascunho_ia(config, ctx)
    instrucao = ctx.interpolar(config['instrucao'])
    return { saida: 's', resumo: "faria: rascunho da IA (#{instrucao.truncate(80)})" } if ctx.ensaio?

    cota!(ctx)
    texto = restaurar(perguntar(SISTEMA_RASCUNHO, "Instrução: #{instrucao}", ctx), ctx).strip
    Ramon::Fluxos::Passos::Conversa.escrever(ctx, "#{Ramon::RascunhoCarimbo::PREFIXO}\n#{texto}")
    { saida: 's', vars: { 'resposta_ia' => texto }, resumo: "rascunho da IA: #{texto.truncate(120)}" }
  end

  def rodar_skill(config, ctx)
    raise Ramon::Fluxos::PassoImpossivel, 'rodar skill precisa da edição enterprise (Captain)' unless ChatwootApp.enterprise?

    skill = Captain::Scenario.enabled.find_by(id: config['skill_id'], assistant_id: config['assistente_id'],
                                              account_id: ctx.execucao.account_id)
    raise Ramon::Fluxos::PassoImpossivel, 'skill não encontrada ou desligada' if skill.nil?
    return { saida: 's', resumo: "faria: skill \"#{skill.title}\" (#{skill.assistant.name})" } if ctx.ensaio?

    cota!(ctx)
    texto = restaurar(executar_skill(skill, config, ctx), ctx)
    Ramon::Fluxos::Passos::Conversa.escrever(ctx, "⚙ Skill #{skill.title}:\n#{texto}")
    { saida: 's', vars: { 'resposta_ia' => texto }, resumo: "skill #{skill.title}: #{texto.truncate(120)}" }
  end

  # Sem `conversation:` no runner (como o Testar): ferramentas que agem na conversa (handoff,
  # nota, prioridade) não acham a conversa e não fazem nada — nada chega ao cliente.
  def executar_skill(skill, config, ctx)
    pedido = "Use a skill \"#{skill.title}\". #{ctx.interpolar(config['instrucao'])}".strip
    mensagem = Ramon::Pseudonymizer.mask([pedido, dados_do_caso(ctx), transcricao(ctx)].compact_blank.join("\n\n"), names: nomes(ctx))
    resposta = Captain::Assistant::AgentRunnerService.new(assistant: skill.assistant, source: 'fluxo')
                                                     .generate_response(message_history: [{ role: 'user', content: mensagem }])
    raise "skill falhou: #{resposta['reasoning']}" if resposta['reasoning'].to_s.start_with?('Error occurred')

    resposta['response'].to_s
  end

  def perguntar(sistema, pedido, ctx)
    texto = [pedido, dados_do_caso(ctx), transcricao(ctx)].compact_blank.join("\n\n")
    Ramon::LlmClient.complete(provider: PROVIDER, model: ENV.fetch('RAMON_COPILOT_MODEL', 'deepseek-chat'), system: sistema,
                              user: Ramon::Pseudonymizer.mask(texto, names: nomes(ctx))).content.to_s
  end

  def dados_do_caso(ctx)
    d = ctx.dados
    "Caso: tese #{d['tese'] || 'não informada'}; etapa #{d['etapa'] || '—'}; origem #{d['origem'] || '—'}; " \
      "documentos que faltam: #{d['documentos_faltantes'].presence || 'nenhum'}."
  end

  def transcricao(ctx)
    return if ctx.conversa.blank?

    "Conversa:\n#{LlmFormatter::ConversationLlmFormatter.new(ctx.conversa).format(token_limit: LIMITE_CONVERSA)}"
  end

  def nomes(ctx) = [ctx.lead&.name, ctx.lead&.contact&.name, ctx.conversa&.contact&.name].compact.uniq

  def restaurar(texto, ctx) = texto.gsub('[nome]', ctx.dados['nome'].presence || 'cliente')

  def limpar(conteudo) = conteudo.to_s.strip.sub(/\A```(?:json)?\s*/, '').sub(/```\s*\z/, '')

  # Teto por conta/dia (fuso SP) contado no Redis; estourou → falha na hora + sino de falha.
  def cota!(ctx)
    teto = ENV.fetch('RAMON_FLUXO_IA_DIA', TETO_PADRAO).to_i
    chave = "RAMON::FLUXO_IA::#{ctx.execucao.account_id}::#{Time.find_zone!(Fluxo::ZONA).today}"
    usadas = Redis::Alfred.incr(chave)
    Redis::Alfred.expire(chave, 2.days.to_i) if usadas == 1
    raise Ramon::Fluxos::PassoImpossivel, "teto diário de IA dos fluxos atingido (#{teto})" if usadas > teto
  end
end
```

Executor `PASSOS` += `'perguntar_ia' => Ramon::Fluxos::Passos::Ia, 'rascunho_ia' => Ramon::Fluxos::Passos::Ia, 'rodar_skill' => Ramon::Fluxos::Passos::Ia,`.

Conferir no CI: `ModuleLength` ≤ 100 (estimativa ~85), `MethodLength`/`AbcSize` de `perguntar_ia` e `rodar_skill` (estimativa AbcSize ~20). Se `executar_skill` passar de 150 colunas, quebrar `mensagem` em 2 linhas.

- [ ] **Step 4: Run** — specs da Step 2 → PASS (CI; os do `context 'rodar_skill'` rodam só no job enterprise).

- [ ] **Step 5: Commit** — `git add app/services/ramon/fluxos/passos/ia.rb app/services/ramon/fluxos/executor.rb spec/services/ramon/fluxos/passos_ia_spec.rb spec/services/ramon/fluxos/executor_spec.rb` → `feat(fluxos): passos de IA (perguntar, rascunho, skill) com teto diário` + rodapé.

---

### Task 6: Gatilhos externos (reunião, ADVBOX, ZapSign, documento)

**Files:**
- Modify: `app/services/ramon/fluxos/disparo.rb:8-38` (`externo`, `filtro_ok?`)
- Modify: `app/services/ramon/reuniao_agendamento.rb:52-57`
- Modify: `app/services/ramon/advbox_event_processor.rb:41-50`
- Modify: `app/jobs/ramon/zapsign_lead_status_job.rb:9-13,19,27`
- Modify: `app/services/ramon/doc_match_service.rb:82-96`
- Test: `spec/services/ramon/fluxos/disparo_spec.rb`, `spec/services/ramon/reuniao_agendamento_spec.rb`, `spec/services/ramon/advbox_event_processor_spec.rb`, `spec/jobs/ramon/zapsign_lead_status_job_spec.rb`, `spec/services/ramon/doc_match_service_spec.rb`

**Interfaces:**
- Produces: `Ramon::Fluxos::Disparo.externo(gatilho_tipo, alvo, dados = {}) → Array` (nunca levanta); `filtro_ok?` entende `config['regras']` × `dados['regra']`. Dados por gatilho: reunião `{'quando' => 'quinta, 20/08 às 14:00'}`; ADVBOX `{'regra' => 'exito', 'texto' => 'PAGAMENTO RECEBIDO / PAGAR CLIENTE'}`; ZapSign `{}`; documento `{'documento' => <título do item>}`.

- [ ] **Step 1: Write the failing tests**

`spec/services/ramon/fluxos/disparo_spec.rb`:

```ruby
  it 'evento do ADVBOX filtra pela regra' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'evento_advbox', 'regras' => ['exito'] }, nota))
    expect(described_class.call('evento_advbox', lead, { 'regra' => 'marco' })).to eq([])
    described_class.call('evento_advbox', lead, { 'regra' => 'exito' })
    expect(fluxo.execucoes.count).to eq(1)
  end

  it 'externo nunca derruba quem chamou' do
    allow(described_class).to receive(:call).and_raise(StandardError, 'bug no motor')
    expect(described_class.externo('contrato_assinado', lead)).to eq([])
  end
```

`spec/jobs/ramon/zapsign_lead_status_job_spec.rb` (no `it 'assinado…'` e no `it 'recusado…'`, acrescentar antes do `perform_now` um `allow(Ramon::Fluxos::Disparo).to receive(:externo)` e depois):

```ruby
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('contrato_assinado', lead)
```
```ruby
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('contrato_recusado', lead)
```

`spec/services/ramon/advbox_event_processor_spec.rb`:

```ruby
  it 'evento com regra dispara os fluxos de evento do ADVBOX (sem regra, não)' do
    allow(Ramon::Fluxos::Disparo).to receive(:externo)
    process({ 'stage' => 'SENTENCA PROFERIDA', 'cpf' => '52998224725' })
    expect(Ramon::Fluxos::Disparo).to have_received(:externo)
      .with('evento_advbox', lead, { 'regra' => 'marco', 'texto' => 'SENTENCA PROFERIDA' })
    process({ 'stage' => 'ETAPA QUE NAO EXISTE', 'cpf' => '52998224725' })
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).once
  end
```

`spec/services/ramon/reuniao_agendamento_spec.rb`:

```ruby
  it 'marcar e cancelar disparam os fluxos de reunião' do
    allow(Ramon::Fluxos::Disparo).to receive(:externo)
    agendar
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('reuniao_marcada', lead, hash_including('quando'))
    described_class.cancelar(task: lead.lead_tasks.find_by!(kind: 'meeting'), user: user)
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('reuniao_cancelada', lead, hash_including('quando'))
  end
```

`spec/services/ramon/doc_match_service_spec.rb`:

```ruby
  it 'anexo casado com o checklist dispara documento_recebido' do
    allow(Ramon::Fluxos::Disparo).to receive(:externo)
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(Ramon::LlmClient::Result.new(content: %({"item_id": #{rg.id}}), input_tokens: 1, output_tokens: 1))
    described_class.new(message).perform
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('documento_recebido', lead, hash_including('documento'))
  end
```

- [ ] **Step 2: Run** — os 5 specs → FAIL (`externo` não existe / não chamado).

- [ ] **Step 3: Implementation**

`app/services/ramon/fluxos/disparo.rb` — depois de `self.ensaiar`:

```ruby
  # Gatilhos que nascem fora do ouvinte (reunião, ADVBOX, ZapSign, documento). Erro do motor
  # nunca derruba quem chamou: o job do ADVBOX/ZapSign repetiria e duplicaria atividade, nota e sino.
  def self.externo(gatilho_tipo, alvo, dados = {})
    call(gatilho_tipo, alvo, dados)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: alvo.try(:account)).capture_exception
    Rails.logger.warn("[Ramon::Fluxos::Disparo] #{gatilho_tipo}: #{e.class}: #{e.message}")
    []
  end
```

`filtro_ok?` (substitui :33-38):

```ruby
  def self.filtro_ok?(config, dados)
    regras = Array(config['regras'])
    return false unless regras.empty? || regras.include?(dados['regra'])

    { 'caixa_ids' => 'caixa_id', 'de_etapa_ids' => 'de_etapa_id', 'para_etapa_ids' => 'para_etapa_id' }.all? do |filtro, campo|
      lista = Array(config[filtro]).map(&:to_i)
      lista.empty? || lista.include?(dados[campo].to_i)
    end
  end
```

`app/services/ramon/reuniao_agendamento.rb` — última linha de `self.notify` (:56, depois do `NtfyPushJob`); cobre painel (marcar/remarcar/cancelar) e Cal.com (created/rescheduled/cancelled):

```ruby
    Ramon::Fluxos::Disparo.externo(type == 'ramon_meeting_cancelled' ? 'reuniao_cancelada' : 'reuniao_marcada', lead, 'quando' => quando)
```

`app/services/ramon/advbox_event_processor.rb` — última linha de `perform` (depois do `update!` processed, :49):

```ruby
    Ramon::Fluxos::Disparo.externo('evento_advbox', lead, 'regra' => handler.to_s, 'texto' => name)
```

`app/jobs/ramon/zapsign_lead_status_job.rb`:

```ruby
  # status do ZapSign => [kind da atividade, chave da data, rótulo do sino, gatilho de fluxo]
  STATUS = {
    'signed' => %w[zapsign_signed assinado_em assinado contrato_assinado],
    'refused' => %w[zapsign_refused recusado_em recusado contrato_recusado]
  }.freeze
```
:19 → `kind, chave, rotulo, gatilho = STATUS[doc['status'].to_s]`; depois do sino (:27):

```ruby
    Ramon::Fluxos::Disparo.externo(gatilho, lead)
```

`app/services/ramon/doc_match_service.rb` — última linha de `gravar_sugestao` (depois do `Ramon::EventoInline.registrar(...)`, :95):

```ruby
    Ramon::Fluxos::Disparo.externo('documento_recebido', lead, 'documento' => titulo)
```

- [ ] **Step 4: Run** — os 5 specs → PASS (CI). Os exemplos antigos desses arquivos continuam verdes (sem fluxo ligado, `externo` devolve `[]`).

- [ ] **Step 5: Commit** — `git add app/services/ramon/fluxos/disparo.rb app/services/ramon/reuniao_agendamento.rb app/services/ramon/advbox_event_processor.rb app/jobs/ramon/zapsign_lead_status_job.rb app/services/ramon/doc_match_service.rb spec/services/ramon/fluxos/disparo_spec.rb spec/services/ramon/reuniao_agendamento_spec.rb spec/services/ramon/advbox_event_processor_spec.rb spec/jobs/ramon/zapsign_lead_status_job_spec.rb spec/services/ramon/doc_match_service_spec.rb` → `feat(fluxos): gatilhos de reunião, ADVBOX, ZapSign e documento` + rodapé.

---

### Task 7: Gatilhos de relógio (`lead_parado`, `relogio`)

**Files:**
- Create: `app/services/ramon/fluxos/relogio.rb`
- Modify: `app/jobs/ramon/fluxo_relogio_job.rb:1-15`
- Test: `spec/services/ramon/fluxos/relogio_spec.rb` (novo), `spec/jobs/ramon/fluxo_relogio_job_spec.rb`

**Interfaces:**
- Consumes: `Fluxo.executaveis`, `Fluxo#limite_atingido?`, `Disparo.new(fluxo, alvo, dados, origem).iniciar` (público, `disparo.rb:40-56`), `Ramon::Cadencia.parados(leads)`, `Lead.open`/`Lead.funil`, coluna `ramon_fluxos.ultimo_disparo_em`.
- Produces: `Ramon::Fluxos::Relogio.disparar_do_dia(agora = Time.find_zone!(Fluxo::ZONA).now)`, `Relogio::HORA_PADRAO = '11:00'`.

**Decisão embutida (lead_parado):** dispara **uma vez por parada** — o lead só volta a disparar se mudar de etapa e parar de novo (senão a banca ganharia 1 rascunho por dia do mesmo lead). `dias` vazio = usa o "parado" de cada etapa (`lead_stages.stalled_after_days`, a mesma regra do card do funil); `dias` preenchido = parado há mais de N dias em qualquer etapa aberta.

- [ ] **Step 1: Write the failing tests** — `spec/services/ramon/fluxos/relogio_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Relogio do
  let(:account) { create(:account) }
  let(:etapa) { create(:lead_stage, account: account, stalled_after_days: 3) }
  let(:nota) { ['nota_privada', { 'texto' => 'oi' }] }

  def sp(texto) = Time.find_zone!('America/Sao_Paulo').parse(texto)

  it 'relógio: a partir da hora, 1 vez por dia (fuso SP), só no grupo filtrado' do
    alvo = create(:lead, account: account, lead_stage: etapa)
    create(:lead, account: account)
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'relogio', 'hora' => '22:00', 'etapa_ids' => [etapa.id] }, nota))
    travel_to(sp('2026-10-06 21:59')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.count).to eq(0)
    travel_to(sp('2026-10-06 22:30')) { described_class.disparar_do_dia } # 01:30 UTC do dia 7
    travel_to(sp('2026-10-06 23:59')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.pluck(:alvo_id)).to eq([alvo.id])
    fluxo.execucoes.update_all(status: 'concluida') # rubocop:disable Rails/SkipsModelValidations
    travel_to(sp('2026-10-07 22:00')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.count).to eq(2)
  end

  it 'relógio perdido no minuto exato dispara quando voltar, no mesmo dia' do
    create(:lead, account: account, lead_stage: etapa)
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'relogio', 'hora' => '09:00', 'etapa_ids' => [etapa.id] }, nota))
    travel_to(sp('2026-10-06 15:00')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.count).to eq(1)
  end

  it 'lead parado dispara 1 vez por parada (padrão 11:00, regra da etapa)' do
    parado = create(:lead, account: account, lead_stage: etapa)
    parado.update_columns(stage_entered_at: sp('2026-10-01 10:00')) # rubocop:disable Rails/SkipsModelValidations
    create(:lead, account: account, lead_stage: etapa).update_columns(stage_entered_at: sp('2026-10-05 10:00')) # rubocop:disable Rails/SkipsModelValidations
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_parado' }, nota))
    travel_to(sp('2026-10-06 10:59')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.count).to eq(0)
    travel_to(sp('2026-10-06 11:00')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.pluck(:alvo_id)).to eq([parado.id])
    fluxo.execucoes.update_all(status: 'concluida') # rubocop:disable Rails/SkipsModelValidations
    travel_to(sp('2026-10-07 11:00')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.count).to eq(1)
  end

  it 'lead parado com N dias ignora a regra da etapa' do
    lead = create(:lead, account: account, lead_stage: etapa)
    lead.update_columns(stage_entered_at: sp('2026-10-01 10:00')) # rubocop:disable Rails/SkipsModelValidations
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_parado', 'dias' => 10 }, nota))
    travel_to(sp('2026-10-06 11:00')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.count).to eq(0)
  end

  it 'respeita o limite do dia' do
    2.times { create(:lead, account: account, lead_stage: etapa) }
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'relogio', 'hora' => '09:00', 'etapa_ids' => [etapa.id] }, nota),
                            limite_dia: 1)
    travel_to(sp('2026-10-06 09:00')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.count).to eq(1)
  end
end
```

`spec/jobs/ramon/fluxo_relogio_job_spec.rb`:

```ruby
  it 'dispara os gatilhos de relógio do dia' do
    allow(Ramon::Fluxos::Relogio).to receive(:disparar_do_dia)
    described_class.perform_now
    expect(Ramon::Fluxos::Relogio).to have_received(:disparar_do_dia)
  end
```

- [ ] **Step 2: Run** — `bundle exec rspec spec/services/ramon/fluxos/relogio_spec.rb spec/jobs/ramon/fluxo_relogio_job_spec.rb` → FAIL.

- [ ] **Step 3: Implementation** — `app/services/ramon/fluxos/relogio.rb`:

```ruby
# Gatilhos de relógio (spec §4.1), chamados a cada minuto pelo Ramon::FluxoRelogioJob:
# - relogio: todo dia a partir de HH:MM, cada lead de um grupo (etapa/tese/responsável);
# - lead_parado: 1×/dia a partir de HH:MM (padrão 11:00), leads parados na etapa — 1 vez por parada.
# `ultimo_disparo_em` (fuso SP) garante 1 disparo por fluxo por dia; se o minuto exato passar
# (deploy, hub fora do ar), dispara quando o relógio voltar, no mesmo dia.
module Ramon::Fluxos::Relogio
  HORA_PADRAO = '11:00'.freeze
  MAX_LEADS = 500 # ponytail: por fluxo por dia; paginar se um grupo passar disso

  module_function

  def disparar_do_dia(agora = Time.find_zone!(Fluxo::ZONA).now)
    Fluxo.executaveis.where(gatilho_tipo: %w[relogio lead_parado]).includes(:versao_publicada).find_each do |fluxo|
      config = Ramon::Fluxos::Grafo.new(fluxo.versao_publicada.grafo).gatilho['config'] || {}
      next unless na_hora?(config, agora) && reivindicar_dia(fluxo, agora)

      grupo(fluxo, config).limit(MAX_LEADS).each do |lead|
        # ponytail: 1 count por lead; agregar se grupos grandes com limite virarem rotina
        break if fluxo.modo == 'normal' && fluxo.limite_atingido?

        Ramon::Fluxos::Disparo.new(fluxo, lead, {}, nil).iniciar
      end
    end
  end

  def na_hora?(config, agora)
    hora, minuto = (config['hora'].presence || HORA_PADRAO).split(':').map(&:to_i)
    agora >= agora.change(hour: hora, min: minuto)
  end

  # Marca o dia ANTES de disparar, num UPDATE condicional: dois relógios no mesmo minuto não duplicam.
  def reivindicar_dia(fluxo, agora)
    Fluxo.where(id: fluxo.id).where('ultimo_disparo_em IS NULL OR ultimo_disparo_em < ?', agora.beginning_of_day)
         .update_all(ultimo_disparo_em: agora) == 1 # rubocop:disable Rails/SkipsModelValidations
  end

  def grupo(fluxo, config)
    fluxo.gatilho_tipo == 'lead_parado' ? parados(fluxo, config) : filtrados(fluxo.account, config)
  end

  # Sem etapa marcada: leads abertos (nem ganho nem perdido). Com etapa: inclusive pós-ganho.
  def filtrados(account, config)
    etapas, teses, pessoas = %w[etapa_ids tese_ids responsavel_ids].map { |k| Array(config[k]).map(&:to_i) }
    leads = etapas.any? ? account.leads.funil.where(lead_stage_id: etapas) : account.leads.open
    leads = leads.where(thesis_id: teses) if teses.any?
    leads = leads.where(sdr_id: pessoas).or(leads.where(closer_id: pessoas)) if pessoas.any?
    leads.reorder(:id)
  end

  # 1 vez por parada: lead que já teve execução deste fluxo depois de entrar na etapa fica de fora.
  def parados(fluxo, config)
    dias = config['dias'].to_i
    leads = fluxo.account.leads.open
    leads = dias.positive? ? leads.where(stage_entered_at: ...dias.days.ago) : Ramon::Cadencia.parados(leads)
    ja = FluxoExecucao.where(fluxo_id: fluxo.id, alvo_type: 'Lead', ensaio: false)
                      .where('ramon_fluxo_execucoes.alvo_id = leads.id AND ramon_fluxo_execucoes.created_at >= leads.stage_entered_at')
    leads.where(ja.arel.exists.not).reorder(:id)
  end
end
```

`app/jobs/ramon/fluxo_relogio_job.rb` — comentário do topo ganha `# e dispara os gatilhos do dia (relogio, lead_parado — Ramon::Fluxos::Relogio).`; fim do `perform`:

```ruby
    Ramon::Fluxos::Relogio.disparar_do_dia
```

- [ ] **Step 4: Run** — specs da Step 2 → PASS (CI). Se o PG reclamar do `ja.arel.exists.not` com bind (ver no CI), trocar por `leads.where('NOT EXISTS (?)', ja.select(1))` (o AR embute a relation como subquery).

- [ ] **Step 5: Commit** — `git add app/services/ramon/fluxos/relogio.rb app/jobs/ramon/fluxo_relogio_job.rb spec/services/ramon/fluxos/relogio_spec.rb spec/jobs/ramon/fluxo_relogio_job_spec.rb` → `feat(fluxos): gatilhos lead parado e relógio` + rodapé.

---

### Task 8: Front — catálogo da B2b, validação espelhada, modelo Pós-contrato e textos

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js:1-216`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/validar.js`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/modelos.js:1-83`
- Modify: `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json` (bloco `CAPTAIN_RAMON.FLUXOS`, en :1838 / pt_BR :1843)
- Test: `…/automacoes/specs/{fluxo,validar,modelos,i18n}.spec.js`

**Interfaces:**
- Produces (exports de `fluxo.js`): `GATILHOS` (+8, todos `alvo: 'lead'`), `PASSOS` (+8), `PALETA` (grupos `CONDICAO MENSAGEM CONVERSA LEAD IA INTEGRACOES AVISAR CONTROLE`), `REGRAS_ADVBOX`, `PAPEIS = ['sdr', 'closer']`, `CAMPOS` (+ `documentos_completos`), `VARIAVEIS` (+ `documentos_faltantes resposta_ia quando`), `saidasDe` (`perguntar_ia` → `['sim','nao']`, `webhook` → `[]`); `validar.js` exporta `OBRIGATORIOS`; códigos de erro novos `GATILHO_HORA ADVBOX_ACAO ADVBOX_DESCRICAO WEBHOOK_HTTPS WEBHOOK_ULTIMO CAMPO_CHAVE` (falta de saída do `perguntar_ia` reaproveita `SE_SEM_SAIDA`).

- [ ] **Step 1: Write the failing tests**

`specs/fluxo.spec.js` (no `it` de `saidasDe` e um novo):

```js
    expect(saidasDe('perguntar_ia', {})).toEqual(['sim', 'nao']);
    expect(saidasDe('webhook', {})).toEqual([]);
```
```js
  it('todo passo que o motor roda está na paleta', () => {
    const naPaleta = PALETA.flatMap(g => g.itens.map(i => i.tipo));
    TIPOS_PASSO.forEach(t => expect([t, naPaleta.includes(t)]).toEqual([t, true]));
  });
```
(acrescentar `PALETA, TIPOS_PASSO` ao import do topo)

`specs/validar.spec.js` — o exemplo `tipo desconhecido (ex.: passo da B2b)` passa a usar `p('p1', 'inventado', {})` e o título vira `'tipo desconhecido'`; novos:

```js
  it('gatilhos e passos da B2b válidos', () => {
    const d = linear(
      p('p1', 'registrar_atividade', { texto: 'a' }),
      p('p2', 'preencher_campo', { chave: 'beneficio', valor: 'BPC' }),
      p('p3', 'advbox', { acao: 'movimentacao', descricao: 'Contrato assinado no hub' }),
      p('p4', 'webhook', { url: 'https://hooks.exemplo.com.br/x' })
    );
    d.nos[0].config = { tipo: 'relogio', hora: '09:00' };
    expect(codigos(d)).toEqual([]);
  });

  it('relógio sem hora / hora torta', () => {
    const d = linear();
    d.nos[0].config = { tipo: 'relogio' };
    expect(codigos(d)).toEqual([['g', 'GATILHO_HORA']]);
    d.nos[0].config = { tipo: 'lead_parado', hora: '25:00' };
    expect(codigos(d)).toEqual([['g', 'GATILHO_HORA']]);
    d.nos[0].config = { tipo: 'lead_parado' };
    expect(codigos(d)).toEqual([]);
  });

  it('webhook só https e só no fim; advbox; chave do campo; IA sem saída', () => {
    expect(
      codigos(linear(p('p1', 'webhook', { url: 'http://x.com' }), p('p2', 'nota_privada', { texto: 'a' })))
    ).toEqual([['p1', 'WEBHOOK_HTTPS'], ['p1', 'WEBHOOK_ULTIMO']]);
    expect(codigos(linear(p('p1', 'advbox', {})))).toEqual([['p1', 'ADVBOX_ACAO']]);
    expect(codigos(linear(p('p1', 'advbox', { acao: 'tarefa' })))).toEqual([
      ['p1', 'FALTA'],
      ['p1', 'FALTA'],
    ]);
    expect(codigos(linear(p('p1', 'advbox', { acao: 'movimentacao', descricao: 'curta' })))).toEqual([
      ['p1', 'ADVBOX_DESCRICAO'],
    ]);
    expect(codigos(linear(p('p1', 'preencher_campo', { chave: 'Benefício' })))).toEqual([['p1', 'CAMPO_CHAVE']]);
    expect(codigos(linear(p('p1', 'perguntar_ia', { pergunta: 'x' })))).toEqual([['p1', 'SE_SEM_SAIDA']]);
    expect(codigos(linear(p('p1', 'rodar_skill', {})))).toEqual([
      ['p1', 'FALTA'],
      ['p1', 'FALTA'],
    ]);
  });
```

`specs/modelos.spec.js`:

```js
  it('Pós-contrato: contrato assinado → … → se documentos completos, senão rascunho da IA + push', () => {
    const { desenho } = MODELOS.find(m => m.chave === 'pos_contrato');
    expect(desenho.nos[0].config.tipo).toBe('contrato_assinado');
    const se = desenho.nos.find(n => n.tipo === 'se');
    expect(se.config.condicoes).toEqual([{ campo: 'documentos_completos', operador: 'igual', valor: 'sim' }]);
    const nao = desenho.setas.find(s => s.de === se.id && s.saida === 'nao');
    expect(desenho.nos.find(n => n.id === nao.para).tipo).toBe('rascunho_ia');
  });
```
e o `it('todo texto ao cliente é rascunho…')` ganha `expect(tipos).not.toContain('webhook');`.

`specs/i18n.spec.js` — import `PAPEIS, REGRAS_ADVBOX` de `../fluxo` e `OBRIGATORIOS` de `../validar`; no `it('cobre todo o catálogo')`:

```js
    REGRAS_ADVBOX.forEach(r => expect(FLUXOS_PT.REGRAS_ADVBOX[r]).toBeTruthy());
    PAPEIS.forEach(p => expect(FLUXOS_PT.PAPEIS[p]).toBeTruthy());
    [...Object.values(OBRIGATORIOS).flat(), 'tipo_tarefa_id', 'responsavel_id'].forEach(c =>
      expect([c, Boolean(FLUXOS_PT.CAMPOS_OBRIGATORIOS[c])]).toEqual([c, true])
    );
    ['GATILHO_HORA', 'ADVBOX_ACAO', 'ADVBOX_DESCRICAO', 'WEBHOOK_HTTPS', 'WEBHOOK_ULTIMO', 'CAMPO_CHAVE'].forEach(
      c => expect(FLUXOS_PT.ERROS[c]).toBeTruthy()
    );
```

- [ ] **Step 2: Run** — `TZ=UTC ./node_modules/.bin/vitest --no-watch --config vitest.local.config.ts app/javascript/dashboard/routes/dashboard/captain/automacoes/specs` → FAIL nos 4 arquivos.

- [ ] **Step 3: Implementation**

`fluxo.js` — comentário do topo (:1-3) fica; o comentário da paleta (:65) vira `// "+ Adicionar passo": tudo que o motor roda (B1 + B2b).`. Acrescentar ao fim de `GATILHOS` (antes de `manual`):

```js
  { tipo: 'reuniao_marcada', icone: 'i-lucide-calendar-check', alvo: 'lead' },
  { tipo: 'reuniao_cancelada', icone: 'i-lucide-calendar-x', alvo: 'lead' },
  { tipo: 'contrato_assinado', icone: 'i-lucide-file-signature', alvo: 'lead' },
  { tipo: 'contrato_recusado', icone: 'i-lucide-file-x', alvo: 'lead' },
  { tipo: 'documento_recebido', icone: 'i-lucide-file-input', alvo: 'lead' },
  { tipo: 'evento_advbox', icone: 'i-lucide-scale', alvo: 'lead' },
  { tipo: 'lead_parado', icone: 'i-lucide-timer-off', alvo: 'lead' },
  { tipo: 'relogio', icone: 'i-lucide-alarm-clock', alvo: 'lead' },
```

`PASSOS` += (antes de `esperar`):

```js
  perguntar_ia: {
    grupo: 'IA',
    icone: 'i-lucide-message-circle-question',
    tom: 'amber',
  },
  rascunho_ia: {
    grupo: 'IA',
    icone: 'i-lucide-sparkles',
    tom: 'slate',
    rascunho: true,
  },
  rodar_skill: { grupo: 'IA', icone: 'i-lucide-wand-sparkles', tom: 'slate' },
  trocar_responsavel: {
    grupo: 'LEAD',
    icone: 'i-lucide-user-round-cog',
    tom: 'slate',
  },
  preencher_campo: {
    grupo: 'LEAD',
    icone: 'i-lucide-text-cursor-input',
    tom: 'slate',
  },
  registrar_atividade: { grupo: 'LEAD', icone: 'i-lucide-history', tom: 'slate' },
  advbox: { grupo: 'INTEGRACOES', icone: 'i-lucide-scale', tom: 'slate' },
  webhook: { grupo: 'INTEGRACOES', icone: 'i-lucide-webhook', tom: 'slate' },
```

`PALETA` — grupo `LEAD` ganha `trocar_responsavel`, `preencher_campo`, `registrar_atividade` (nessa ordem, depois de `criar_tarefa`); depois de `LEAD`:

```js
  {
    grupo: 'IA',
    itens: [
      { chave: 'perguntar_ia', tipo: 'perguntar_ia' },
      { chave: 'rascunho_ia', tipo: 'rascunho_ia' },
      { chave: 'rodar_skill', tipo: 'rodar_skill' },
    ],
  },
  {
    grupo: 'INTEGRACOES',
    itens: [
      { chave: 'advbox', tipo: 'advbox' },
      { chave: 'webhook', tipo: 'webhook' },
    ],
  },
```

Constantes novas (depois de `PRIORIDADES`):

```js
// = handlers do Ramon::AdvboxEventProcessor::RULES (chave do filtro do gatilho evento_advbox)
export const REGRAS_ADVBOX = [
  'contrato_fechado',
  'requerimento_protocolado',
  'indeferimento',
  'decisao',
  'exigencia',
  'reativacao_futura',
  'exito',
  'marco',
  'concessao',
  'arquivado',
];
export const PAPEIS = ['sdr', 'closer']; // Ramon::Papeis::COLUNA
```

`VARIAVEIS` += `'documentos_faltantes', 'resposta_ia', 'quando'`; `CAMPOS` += `'documentos_completos'`.

`CONFIG_INICIAL` += `advbox: { acao: 'tarefa', prazo_dias: 1 },` e `trocar_responsavel: { papel: 'closer' },`.

`saidasDe`:

```js
export const saidasDe = (tipo, config = {}) => {
  if (['parar', 'webhook'].includes(tipo)) return [];
  if (['se', 'perguntar_ia'].includes(tipo)) return ['sim', 'nao'];
  if (tipo === 'escolha')
    return [...(config.casos || []).map(c => c.chave), 'outro'];
  return ['s'];
};
```

`validar.js` — `OBRIGATORIOS` vira `export const` e ganha:

```js
  perguntar_ia: ['pergunta'],
  rascunho_ia: ['instrucao'],
  rodar_skill: ['assistente_id', 'skill_id'],
  registrar_atividade: ['texto'],
  trocar_responsavel: ['papel'],
```

e, depois de `PROIBIDAS`:

```js
const HORA = /^([01]\d|2[0-3]):[0-5]\d$/;
const CHAVE_CAMPO = /^[a-z][a-z0-9_]{0,39}$/;
const temSaida = (id, setas) => setas.some(s => s.de === id);

// relógio exige a hora; lead parado usa 11:00 se vier vazia (Grafo#erros_hora)
const errosHora = gatilho => {
  const c = gatilho.config || {};
  const hora = String(c.hora ?? '');
  if (c.tipo === 'relogio' && !hora) return [erro(gatilho.id, 'GATILHO_HORA')];
  return !hora || HORA.test(hora) ? [] : [erro(gatilho.id, 'GATILHO_HORA')];
};

const errosAdvbox = (id, c) => {
  if (c.acao === 'tarefa')
    return ['tipo_tarefa_id', 'responsavel_id']
      .filter(k => vazio(c[k]))
      .map(campo => erro(id, 'FALTA', { campo }));
  if (c.acao === 'movimentacao')
    return String(c.descricao ?? '').trim().length >= 10
      ? []
      : [erro(id, 'ADVBOX_DESCRICAO')];
  return [erro(id, 'ADVBOX_ACAO')];
};

const errosWebhook = (id, c, setas) => [
  ...(String(c.url ?? '').startsWith('https://')
    ? []
    : [erro(id, 'WEBHOOK_HTTPS')]),
  ...(temSaida(id, setas) ? [erro(id, 'WEBHOOK_ULTIMO')] : []),
];
```

`errosEspecificos` — o `case 'se'` usa `temSaida(no.id, setas)` no lugar do `setas.some(...)`, e entram:

```js
    case 'perguntar_ia':
      return temSaida(no.id, setas) ? [] : [erro(no.id, 'SE_SEM_SAIDA')];
    case 'advbox':
      return errosAdvbox(no.id, config);
    case 'webhook':
      return errosWebhook(no.id, config, setas);
    case 'preencher_campo':
      return CHAVE_CAMPO.test(config.chave || '')
        ? []
        : [erro(no.id, 'CAMPO_CHAVE')];
```

`validar` — depois do `GATILHO_DESCONHECIDO`:

```js
  const hora = errosHora(gatilho);
  if (hora.length) return hora;
```

`modelos.js` — comentário do topo vira `// Modelos do "Novo fluxo". Textos ao cliente saem como RASCUNHO e passam pelo Eduardo antes de qualquer fluxo publicado.`; o `pos_contrato` inteiro:

```js
  {
    chave: 'pos_contrato',
    icone: 'i-lucide-file-check',
    limite_dia: 20,
    desenho: {
      nos: [
        no('n1', 'gatilho', { tipo: 'contrato_assinado' }, 0, 0),
        no(
          'n2',
          'rascunho_texto',
          {
            rotulo: 'Boas-vindas',
            texto:
              'Olá, {nome}! Seja bem-vindo(a). Para darmos andamento ao seu caso, vamos precisar de alguns documentos — já te explico quais.',
          },
          0,
          140
        ),
        no(
          'n3',
          'criar_tarefa',
          {
            titulo: 'Conferir documentos de {nome}',
            tipo: 'document',
            prazo_dias: 1,
          },
          0,
          300
        ),
        no('n4', 'esperar', { quantidade: 2, unidade: 'dias' }, 0, 440),
        no(
          'n5',
          'se',
          {
            rotulo: 'Documentos completos?',
            juncao: 'e',
            condicoes: [
              { campo: 'documentos_completos', operador: 'igual', valor: 'sim' },
            ],
          },
          0,
          580
        ),
        no(
          'n6',
          'rascunho_ia',
          {
            rotulo: 'Lembrete dos documentos',
            instrucao:
              'Lembre {nome}, com gentileza, dos documentos que ainda faltam: {documentos_faltantes}. Ofereça ajuda para conseguir algum deles. Não prometa resultado nem prazo.',
          },
          130,
          740
        ),
        no(
          'n7',
          'avisar_push',
          { texto: 'Lembrete de documentos pronto para revisar: {nome}' },
          130,
          900
        ),
      ],
      setas: [
        seta('n1', 's', 'n2'),
        seta('n2', 's', 'n3'),
        seta('n3', 's', 'n4'),
        seta('n4', 's', 'n5'),
        seta('n5', 'nao', 'n6'),
        seta('n6', 's', 'n7'),
      ],
    },
  },
```

i18n — **Edit à mão** dentro de `CAPTAIN_RAMON.FLUXOS` nos dois arquivos (mesmas chaves, mesma ordem). pt_BR:

```json
"GATILHOS": { …existentes…,
  "reuniao_marcada": "Reunião marcada",
  "reuniao_cancelada": "Reunião cancelada",
  "contrato_assinado": "Contrato assinado (ZapSign)",
  "contrato_recusado": "Contrato recusado (ZapSign)",
  "documento_recebido": "Documento recebido (checklist)",
  "evento_advbox": "Evento do ADVBOX",
  "lead_parado": "Lead parado na etapa",
  "relogio": "Todo dia, num horário" },
"PASSOS": { …,
  "perguntar_ia": "Perguntar à IA", "rascunho_ia": "Rascunho escrito pela IA", "rodar_skill": "Rodar uma skill",
  "trocar_responsavel": "Trocar responsável", "preencher_campo": "Preencher campo", "registrar_atividade": "Registrar atividade",
  "advbox": "ADVBOX", "webhook": "Webhook" },
"CABECALHO": { …,
  "perguntar_ia": "Condição com IA", "rascunho_ia": "Mensagem ao cliente", "rodar_skill": "IA",
  "trocar_responsavel": "Lead", "preencher_campo": "Lead", "registrar_atividade": "Lead",
  "advbox": "Integração", "webhook": "Integração" },
"GRUPOS": { …, "IA": "Inteligência artificial", "INTEGRACOES": "Integrações" },
"PALETA": { …,
  "perguntar_ia": "Perguntar à IA (sim / não)", "rascunho_ia": "Rascunho escrito pela IA", "rodar_skill": "Rodar uma skill de assistente",
  "trocar_responsavel": "Trocar SDR / Closer", "preencher_campo": "Preencher campo do lead", "registrar_atividade": "Registrar atividade",
  "advbox": "Tarefa ou movimentação no ADVBOX", "webhook": "Webhook (último passo)" },
"NO": { …, "AS_HORA": "todo dia a partir de {quando}", "QUALQUER_EVENTO": "qualquer evento" },
"PAINEL": { …,
  "PERGUNTA": "Pergunta de sim ou não",
  "PERGUNTA_AJUDA": "A IA lê a conversa e o lead e responde sim ou não. A justificativa vira a variável resposta_ia.",
  "INSTRUCAO": "O que a IA deve escrever",
  "INSTRUCAO_AJUDA": "Sai como nota RASCUNHO. A IA segue as regras da OAB e nunca promete resultado, prazo ou valor.",
  "ASSISTENTE": "Assistente",
  "SKILL": "Skill",
  "INSTRUCAO_SKILL": "Pedido para a skill (opcional)",
  "SKILL_AJUDA": "A skill roda só para pensar: não age na conversa. O resultado vira nota privada e a variável resposta_ia.",
  "SEM_CAPTAIN": "Não consegui listar os assistentes do Captain.",
  "ADVBOX_AVISO": "Grava de verdade no ADVBOX, no processo do lead criado no fechamento.",
  "ADVBOX_ACOES": { "tarefa": "Criar tarefa", "movimentacao": "Registrar movimentação" },
  "ADVBOX_TIPO": "Tipo de tarefa",
  "ADVBOX_RESPONSAVEL": "Responsável no ADVBOX",
  "ADVBOX_PRAZO": "Prazo (dias a partir de hoje, vazio = sem prazo)",
  "ADVBOX_DESCRICAO": "Descrição",
  "ADVBOX_INDISPONIVEL": "O ADVBOX não respondeu. Tente de novo em instantes.",
  "WEBHOOK_URL": "Endereço (https)",
  "WEBHOOK_AJUDA": "Envia nome, telefone, etapa e tese do lead em JSON. É sempre o último passo.",
  "PAPEL": "Papel",
  "DISTRIBUIR_NO_TIME": "Distribuir no time (quem tem menos leads)",
  "CHAVE_CAMPO": "Nome do campo",
  "CHAVE_CAMPO_AJUDA": "Letras minúsculas, números e _. Depois vira variável com o mesmo nome.",
  "HORA": "A partir de que horas",
  "DIAS_PARADO": "Parado há mais de quantos dias",
  "DIAS_PARADO_AJUDA": "Vazio = o prazo de parado de cada etapa. Cada lead entra 1 vez por parada.",
  "GRUPO_ETAPAS": "Leads nestas etapas",
  "GRUPO_TESES": "Destas teses",
  "GRUPO_RESPONSAVEIS": "Destes responsáveis",
  "GRUPO_AJUDA": "Nenhuma etapa marcada = leads abertos. Roda 1 vez por dia.",
  "REGRAS": "Só nestes eventos",
  "REGRAS_AJUDA": "Nenhum marcado = qualquer evento reconhecido.",
  "REUNIAO_AJUDA": "Vale para o Cal.com e para o painel do lead. Remarcar conta como marcada.",
  "DOCUMENTO_AJUDA": "Quando a IA casa um anexo com um item do checklist. A confirmação continua com a equipe." },
"PAPEIS": { "sdr": "SDR", "closer": "Closer" },
"REGRAS_ADVBOX": {
  "contrato_fechado": "Contrato fechado", "requerimento_protocolado": "Requerimento protocolado no INSS",
  "indeferimento": "INSS negou", "decisao": "Decisão proferida", "exigencia": "Carta de exigências",
  "reativacao_futura": "Benefício futuro", "exito": "Pagamento recebido ou RPV", "marco": "Marco do processo",
  "concessao": "Benefício concedido", "arquivado": "Arquivado" },
"CAMPOS": { …, "documentos_completos": "Documentos completos (sim ou não)" },
"CAMPOS_OBRIGATORIOS": { …,
  "pergunta": "a pergunta", "instrucao": "a instrução", "assistente_id": "o assistente", "skill_id": "a skill",
  "papel": "o papel", "tipo_tarefa_id": "o tipo de tarefa", "responsavel_id": "o responsável no ADVBOX" },
"ERROS": { …,
  "GATILHO_HORA": "Informe a hora no formato HH:MM.",
  "ADVBOX_ACAO": "Escolha tarefa ou movimentação.",
  "ADVBOX_DESCRICAO": "A movimentação precisa de pelo menos 10 letras.",
  "WEBHOOK_HTTPS": "O endereço precisa começar com https.",
  "WEBHOOK_ULTIMO": "O webhook tem que ser o último passo.",
  "CAMPO_CHAVE": "Nome do campo só com letras minúsculas, números e _." }
```

en (mesmas chaves):

```json
"GATILHOS": { "reuniao_marcada": "Meeting scheduled", "reuniao_cancelada": "Meeting cancelled",
  "contrato_assinado": "Contract signed (ZapSign)", "contrato_recusado": "Contract refused (ZapSign)",
  "documento_recebido": "Document received (checklist)", "evento_advbox": "ADVBOX event",
  "lead_parado": "Lead stalled in stage", "relogio": "Every day at a set time" },
"PASSOS": { "perguntar_ia": "Ask the AI", "rascunho_ia": "AI-written draft", "rodar_skill": "Run a skill",
  "trocar_responsavel": "Change owner", "preencher_campo": "Fill a field", "registrar_atividade": "Log activity",
  "advbox": "ADVBOX", "webhook": "Webhook" },
"CABECALHO": { "perguntar_ia": "AI condition", "rascunho_ia": "Message to client", "rodar_skill": "AI",
  "trocar_responsavel": "Lead", "preencher_campo": "Lead", "registrar_atividade": "Lead",
  "advbox": "Integration", "webhook": "Integration" },
"GRUPOS": { "IA": "Artificial intelligence", "INTEGRACOES": "Integrations" },
"PALETA": { "perguntar_ia": "Ask the AI (yes / no)", "rascunho_ia": "AI-written draft", "rodar_skill": "Run an assistant skill",
  "trocar_responsavel": "Change SDR / Closer", "preencher_campo": "Fill a lead field", "registrar_atividade": "Log activity",
  "advbox": "Task or movement in ADVBOX", "webhook": "Webhook (last step)" },
"NO": { "AS_HORA": "every day from {quando}", "QUALQUER_EVENTO": "any event" },
"PAINEL": { "PERGUNTA": "Yes or no question",
  "PERGUNTA_AJUDA": "The AI reads the conversation and the lead and answers yes or no. The reason becomes the resposta_ia variable.",
  "INSTRUCAO": "What the AI should write",
  "INSTRUCAO_AJUDA": "Goes out as a DRAFT note. The AI follows the bar rules and never promises results, deadlines or amounts.",
  "ASSISTENTE": "Assistant", "SKILL": "Skill", "INSTRUCAO_SKILL": "Request for the skill (optional)",
  "SKILL_AJUDA": "The skill only thinks: it does not act on the conversation. The result becomes a private note and the resposta_ia variable.",
  "SEM_CAPTAIN": "Could not list the Captain assistants.",
  "ADVBOX_AVISO": "Really writes to ADVBOX, on the lead case created at closing.",
  "ADVBOX_ACOES": { "tarefa": "Create task", "movimentacao": "Log movement" },
  "ADVBOX_TIPO": "Task type", "ADVBOX_RESPONSAVEL": "Owner in ADVBOX",
  "ADVBOX_PRAZO": "Due (days from today, empty = no due date)", "ADVBOX_DESCRICAO": "Description",
  "ADVBOX_INDISPONIVEL": "ADVBOX did not answer. Try again in a moment.",
  "WEBHOOK_URL": "Address (https)",
  "WEBHOOK_AJUDA": "Sends the lead name, phone, stage and thesis as JSON. Always the last step.",
  "PAPEL": "Role", "DISTRIBUIR_NO_TIME": "Distribute in the team (fewest leads)",
  "CHAVE_CAMPO": "Field name", "CHAVE_CAMPO_AJUDA": "Lowercase letters, numbers and _. It becomes a variable with the same name.",
  "HORA": "From what time", "DIAS_PARADO": "Stalled for more than how many days",
  "DIAS_PARADO_AJUDA": "Empty = each stage stalled limit. Each lead enters once per stall.",
  "GRUPO_ETAPAS": "Leads in these stages", "GRUPO_TESES": "From these theses", "GRUPO_RESPONSAVEIS": "From these owners",
  "GRUPO_AJUDA": "No stage selected = open leads. Runs once a day.",
  "REGRAS": "Only these events", "REGRAS_AJUDA": "None selected = any recognized event.",
  "REUNIAO_AJUDA": "Works for Cal.com and the lead panel. Rescheduling counts as scheduled.",
  "DOCUMENTO_AJUDA": "When the AI matches an attachment to a checklist item. Confirmation stays with the team." },
"PAPEIS": { "sdr": "SDR", "closer": "Closer" },
"REGRAS_ADVBOX": { "contrato_fechado": "Contract closed", "requerimento_protocolado": "Request filed at INSS",
  "indeferimento": "INSS denied", "decisao": "Decision issued", "exigencia": "Requirements letter",
  "reativacao_futura": "Future benefit", "exito": "Payment received or RPV", "marco": "Case milestone",
  "concessao": "Benefit granted", "arquivado": "Archived" },
"CAMPOS": { "documentos_completos": "Documents complete (yes or no)" },
"CAMPOS_OBRIGATORIOS": { "pergunta": "the question", "instrucao": "the instruction", "assistente_id": "the assistant",
  "skill_id": "the skill", "papel": "the role", "tipo_tarefa_id": "the task type", "responsavel_id": "the ADVBOX owner" },
"ERROS": { "GATILHO_HORA": "Enter the time as HH:MM.", "ADVBOX_ACAO": "Choose task or movement.",
  "ADVBOX_DESCRICAO": "The movement needs at least 10 letters.", "WEBHOOK_HTTPS": "The address must start with https.",
  "WEBHOOK_ULTIMO": "The webhook must be the last step.", "CAMPO_CHAVE": "Field name only with lowercase letters, numbers and _." }
```

(Nada de `@`, `|`, `{`, `}` crus — "resposta_ia" aparece sem chaves de propósito.)

- [ ] **Step 4: Run** — vitest da Step 2 → PASS; `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes/{fluxo,validar,modelos}.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/{fluxo,validar,modelos,i18n}.spec.js` → limpo.

- [ ] **Step 5: Commit** — `git add` os 4 `.js`, os 4 specs e os 2 `ramon.json` → `feat(fluxos): catálogo da B2b no quadro (IA, ADVBOX, webhook, gatilhos externos)` + rodapé.

---

### Task 9: Front — painéis dos passos e gatilhos da B2b

**Files:**
- Create: `…/captain/automacoes/ConfigIa.vue`, `…/captain/automacoes/ConfigAdvbox.vue`
- Modify: `…/captain/automacoes/PainelPasso.vue:15-21` (imports), `:30-49` (setup), `:119-130` (ramos)
- Modify: `…/captain/automacoes/ConfigGatilho.vue`
- Modify: `…/captain/automacoes/NoPasso.vue:68-102` (`detalhe`)
- Test: `…/specs/ConfigIa.spec.js`, `…/specs/ConfigAdvbox.spec.js` (novos), `…/specs/PainelPasso.spec.js`

**Interfaces:**
- Consumes: `CaptainAssistantAPI.get()` → `{data: {payload: [{id, name}]}}` e `CaptainScenariosAPI.get({assistantId})` → `{data: {payload: [{id, title}]}}` (só skills ligadas — `enterprise/app/controllers/api/v1/accounts/captain/scenarios_controller.rb:7-9`); `RamonFluxosAPI.opcoesAdvbox()` (Task 4); `PAPEIS`, `REGRAS_ADVBOX` (Task 8).
- Produces: `ConfigIa` props `{tipo, config}`, `ConfigAdvbox` props `{config}`; ambos emitem `update:config` com config NOVA. `data-testid`: `ia-assistente`, `ia-skill`, `ia-sem-captain`, `advbox-tipo`, `advbox-responsavel`, `advbox-indisponivel`, `webhook-url`, `papel`, `campo-chave`, `gatilho-hora`.

- [ ] **Step 1: Write the failing tests**

`specs/ConfigIa.spec.js`:

```js
import { mount, flushPromises } from '@vue/test-utils';
import CaptainAssistantAPI from 'dashboard/api/captain/assistant';
import CaptainScenariosAPI from 'dashboard/api/captain/scenarios';
import ConfigIa from '../ConfigIa.vue';

vi.mock('dashboard/api/captain/assistant', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/captain/scenarios', () => ({ default: { get: vi.fn() } }));

const montar = (tipo, config = {}) => mount(ConfigIa, { props: { tipo, config } });

describe('ConfigIa', () => {
  it('perguntar_ia edita a pergunta e não chama o Captain', async () => {
    const w = montar('perguntar_ia', {});
    await w.find('textarea').setValue('Mandou o CNIS?');
    expect(w.emitted('update:config').at(-1)).toEqual([{ pergunta: 'Mandou o CNIS?' }]);
    expect(CaptainAssistantAPI.get).not.toHaveBeenCalled();
  });

  it('rodar_skill lista assistentes e skills; trocar o assistente limpa a skill', async () => {
    CaptainAssistantAPI.get.mockResolvedValue({
      data: { payload: [{ id: 1, name: 'Atendente' }, { id: 2, name: 'Analista' }] },
    });
    CaptainScenariosAPI.get.mockResolvedValue({
      data: { payload: [{ id: 5, title: 'Resumo do caso' }] },
    });
    const w = montar('rodar_skill', { assistente_id: 1, skill_id: 5 });
    await flushPromises();
    expect(CaptainScenariosAPI.get).toHaveBeenCalledWith({ assistantId: 1 });
    expect(w.find('[data-testid="ia-skill"]').text()).toContain('Resumo do caso');
    await w.find('[data-testid="ia-assistente"]').setValue('2');
    expect(w.emitted('update:config').at(-1)).toEqual([
      { assistente_id: 2, skill_id: null },
    ]);
  });

  it('sem Captain (FOSS): avisa e não quebra', async () => {
    CaptainAssistantAPI.get.mockRejectedValue(new Error('404'));
    const w = montar('rodar_skill', {});
    await flushPromises();
    expect(w.find('[data-testid="ia-sem-captain"]').exists()).toBe(true);
  });
});
```

`specs/ConfigAdvbox.spec.js`:

```js
import { mount, flushPromises } from '@vue/test-utils';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import ConfigAdvbox from '../ConfigAdvbox.vue';

vi.mock('dashboard/api/ramonFluxos', () => ({
  default: { opcoesAdvbox: vi.fn() },
}));

describe('ConfigAdvbox', () => {
  it('tarefa: carrega tipos e responsáveis do ADVBOX e grava os IDs', async () => {
    RamonFluxosAPI.opcoesAdvbox.mockResolvedValue({
      data: {
        usuarios: [{ id: 266778, nome: 'EDUARDO SCHLATA' }],
        tipos_tarefa: [{ id: 8745408, nome: 'AGUARDANDO DOCUMENTOS CLIENTE' }],
      },
    });
    const w = mount(ConfigAdvbox, { props: { config: { acao: 'tarefa' } } });
    await flushPromises();
    await w.find('[data-testid="advbox-tipo"]').setValue('8745408');
    expect(w.emitted('update:config').at(-1)).toEqual([
      { acao: 'tarefa', tipo_tarefa_id: 8745408 },
    ]);
    await w.find('[data-testid="advbox-responsavel"]').setValue('266778');
    expect(w.emitted('update:config').at(-1)).toEqual([
      { acao: 'tarefa', responsavel_id: 266778 },
    ]);
  });

  it('movimentação não pede tipo nem responsável', async () => {
    RamonFluxosAPI.opcoesAdvbox.mockResolvedValue({
      data: { usuarios: [], tipos_tarefa: [] },
    });
    const w = mount(ConfigAdvbox, { props: { config: { acao: 'movimentacao' } } });
    await flushPromises();
    expect(w.find('[data-testid="advbox-tipo"]').exists()).toBe(false);
    expect(w.find('textarea').exists()).toBe(true);
  });

  it('ADVBOX fora do ar: avisa', async () => {
    RamonFluxosAPI.opcoesAdvbox.mockRejectedValue(new Error('503'));
    const w = mount(ConfigAdvbox, { props: { config: { acao: 'tarefa' } } });
    await flushPromises();
    expect(w.find('[data-testid="advbox-indisponivel"]').exists()).toBe(true);
  });
});
```

`specs/PainelPasso.spec.js` — acrescentar:

```js
  it('webhook: só o endereço', async () => {
    const wrapper = montar({ id: 'n9', data: { tipo: 'webhook', config: {} } });
    await wrapper.find('[data-testid="webhook-url"]').setValue('https://hooks.exemplo.com.br/a');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { url: 'https://hooks.exemplo.com.br/a' },
    ]);
  });

  it('trocar responsável: papel + pessoa (vazio = distribuir no time)', async () => {
    const wrapper = montar({ id: 'n4', data: { tipo: 'trocar_responsavel', config: { papel: 'closer' } } });
    await wrapper.find('[data-testid="papel"]').setValue('sdr');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([{ papel: 'sdr' }]);
  });

  it('preencher campo: chave e valor', async () => {
    const wrapper = montar({ id: 'n5', data: { tipo: 'preencher_campo', config: {} } });
    await wrapper.find('[data-testid="campo-chave"]').setValue('beneficio');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([{ chave: 'beneficio' }]);
  });

  it('rascunho da IA mostra o aviso de rascunho', () => {
    const wrapper = montar({ id: 'n6', data: { tipo: 'rascunho_ia', config: {} } });
    expect(wrapper.find('[data-testid="painel-aviso-rascunho"]').exists()).toBe(true);
  });

  it('gatilho relógio: hora', async () => {
    const wrapper = montar({ id: 'n1', data: { tipo: 'gatilho', config: { tipo: 'relogio' } } });
    await wrapper.find('[data-testid="gatilho-hora"]').setValue('09:30');
    expect(wrapper.emitted('update:config').at(-1)).toEqual([{ tipo: 'relogio', hora: '09:30' }]);
  });

  it('gatilho evento do ADVBOX: marca as regras', async () => {
    const wrapper = montar({ id: 'n1', data: { tipo: 'gatilho', config: { tipo: 'evento_advbox' } } });
    await wrapper.find('input[type="checkbox"]').setValue(true);
    expect(wrapper.emitted('update:config').at(-1)).toEqual([
      { tipo: 'evento_advbox', regras: ['contrato_fechado'] },
    ]);
  });
```

- [ ] **Step 2: Run** — vitest (config local) → FAIL (componentes/ramos inexistentes).

- [ ] **Step 3: Implementation**

`ConfigIa.vue`:

```vue
<script setup>
// Passos de IA: perguntar (sim/não), rascunho escrito pela IA, rodar uma skill do Captain.
// Assistentes e skills vêm das APIs do Captain (enterprise); sem elas, aviso e nada quebra.
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import CaptainAssistantAPI from 'dashboard/api/captain/assistant';
import CaptainScenariosAPI from 'dashboard/api/captain/scenarios';
import {
  AVISO,
  ROTULO,
  SELECT,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import CampoTexto from './CampoTexto.vue';

const props = defineProps({
  tipo: { type: String, required: true },
  config: { type: Object, required: true },
});
const emit = defineEmits(['update:config']);
const K = 'CAPTAIN_RAMON.FLUXOS.PAINEL';
const { t } = useI18n();
const assistentes = ref([]);
const skills = ref([]);
const semCaptain = ref(false);

const muda = (chave, valor) =>
  emit('update:config', { ...props.config, [chave]: valor });
const numeroOuNada = v => (v === '' ? null : Number(v));

const carregarSkills = async id => {
  skills.value = [];
  if (!id) return;
  try {
    const { data } = await CaptainScenariosAPI.get({ assistantId: id });
    skills.value = data.payload || [];
  } catch {
    semCaptain.value = true;
  }
};

const trocaAssistente = id => {
  emit('update:config', { ...props.config, assistente_id: id, skill_id: null });
  carregarSkills(id);
};

onMounted(async () => {
  if (props.tipo !== 'rodar_skill') return;
  try {
    const { data } = await CaptainAssistantAPI.get();
    assistentes.value = data.payload || [];
  } catch {
    semCaptain.value = true;
    return;
  }
  carregarSkills(props.config.assistente_id);
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <template v-if="tipo === 'perguntar_ia'">
      <CampoTexto
        :rotulo="t(`${K}.PERGUNTA`)"
        :linhas="2"
        :model-value="config.pergunta || ''"
        @update:model-value="v => muda('pergunta', v)"
      />
      <p class="text-xs text-n-slate-10">{{ t(`${K}.PERGUNTA_AJUDA`) }}</p>
    </template>

    <template v-else-if="tipo === 'rascunho_ia'">
      <CampoTexto
        :rotulo="t(`${K}.INSTRUCAO`)"
        :model-value="config.instrucao || ''"
        @update:model-value="v => muda('instrucao', v)"
      />
      <p class="text-xs text-n-slate-10">{{ t(`${K}.INSTRUCAO_AJUDA`) }}</p>
    </template>

    <template v-else>
      <p
        v-if="semCaptain"
        data-testid="ia-sem-captain"
        :class="[AVISO, TOM.ruby]"
      >
        {{ t(`${K}.SEM_CAPTAIN`) }}
      </p>
      <label :class="ROTULO">
        {{ t(`${K}.ASSISTENTE`) }}
        <select
          data-testid="ia-assistente"
          :class="SELECT"
          :value="config.assistente_id ?? ''"
          @change="trocaAssistente(numeroOuNada($event.target.value))"
        >
          <option value="" disabled>{{ t(`${K}.ESCOLHA`) }}</option>
          <option v-for="a in assistentes" :key="a.id" :value="a.id">
            {{ a.name }}
          </option>
        </select>
      </label>
      <label :class="ROTULO">
        {{ t(`${K}.SKILL`) }}
        <select
          data-testid="ia-skill"
          :class="SELECT"
          :disabled="!config.assistente_id"
          :value="config.skill_id ?? ''"
          @change="muda('skill_id', numeroOuNada($event.target.value))"
        >
          <option value="" disabled>{{ t(`${K}.ESCOLHA`) }}</option>
          <option v-for="s in skills" :key="s.id" :value="s.id">
            {{ s.title }}
          </option>
        </select>
      </label>
      <CampoTexto
        :rotulo="t(`${K}.INSTRUCAO_SKILL`)"
        :linhas="2"
        :model-value="config.instrucao || ''"
        @update:model-value="v => muda('instrucao', v)"
      />
      <p class="text-xs text-n-slate-10">{{ t(`${K}.SKILL_AJUDA`) }}</p>
    </template>
  </div>
</template>
```

`ConfigAdvbox.vue`:

```vue
<script setup>
// Passo ADVBOX: tarefa ou movimentação FIXA no processo do lead (criado no fechamento).
// IDs vêm de advbox_configuracoes via GET ramon_fluxos/opcoes_advbox (admin).
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import {
  AVISO,
  CAMPO,
  ROTULO,
  SELECT,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import CampoTexto from './CampoTexto.vue';

const props = defineProps({ config: { type: Object, required: true } });
const emit = defineEmits(['update:config']);
const K = 'CAPTAIN_RAMON.FLUXOS.PAINEL';
const ACOES = ['tarefa', 'movimentacao'];
const { t } = useI18n();
const usuarios = ref([]);
const tipos = ref([]);
const indisponivel = ref(false);

const muda = (chave, valor) =>
  emit('update:config', { ...props.config, [chave]: valor });
const numeroOuNada = v => (v === '' ? null : Number(v));

onMounted(async () => {
  try {
    const { data } = await RamonFluxosAPI.opcoesAdvbox();
    usuarios.value = data.usuarios || [];
    tipos.value = data.tipos_tarefa || [];
  } catch {
    indisponivel.value = true;
  }
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <p :class="[AVISO, TOM.amber]">{{ t(`${K}.ADVBOX_AVISO`) }}</p>
    <div class="flex flex-col gap-1.5 text-[13px] text-n-slate-12">
      <label v-for="acao in ACOES" :key="acao" class="flex items-center gap-2">
        <input
          type="radio"
          class="reset-base"
          :checked="config.acao === acao"
          @change="muda('acao', acao)"
        />
        {{ t(`${K}.ADVBOX_ACOES.${acao}`) }}
      </label>
    </div>
    <p
      v-if="indisponivel"
      data-testid="advbox-indisponivel"
      :class="[AVISO, TOM.ruby]"
    >
      {{ t(`${K}.ADVBOX_INDISPONIVEL`) }}
    </p>

    <template v-if="config.acao === 'tarefa'">
      <label :class="ROTULO">
        {{ t(`${K}.ADVBOX_TIPO`) }}
        <select
          data-testid="advbox-tipo"
          :class="SELECT"
          :value="config.tipo_tarefa_id ?? ''"
          @change="muda('tipo_tarefa_id', numeroOuNada($event.target.value))"
        >
          <option value="" disabled>{{ t(`${K}.ESCOLHA`) }}</option>
          <option v-for="o in tipos" :key="o.id" :value="o.id">
            {{ o.nome }}
          </option>
        </select>
      </label>
      <label :class="ROTULO">
        {{ t(`${K}.ADVBOX_RESPONSAVEL`) }}
        <select
          data-testid="advbox-responsavel"
          :class="SELECT"
          :value="config.responsavel_id ?? ''"
          @change="muda('responsavel_id', numeroOuNada($event.target.value))"
        >
          <option value="" disabled>{{ t(`${K}.ESCOLHA`) }}</option>
          <option v-for="u in usuarios" :key="u.id" :value="u.id">
            {{ u.nome }}
          </option>
        </select>
      </label>
      <label :class="ROTULO">
        {{ t(`${K}.ADVBOX_PRAZO`) }}
        <input
          :class="CAMPO"
          type="number"
          min="0"
          :value="config.prazo_dias ?? ''"
          @change="muda('prazo_dias', numeroOuNada($event.target.value))"
        />
      </label>
    </template>

    <CampoTexto
      v-if="config.acao"
      :rotulo="t(`${K}.ADVBOX_DESCRICAO`)"
      :linhas="3"
      :model-value="config.descricao || ''"
      @update:model-value="v => muda('descricao', v)"
    />
  </div>
</template>
```

(O teste do responsável espera `{acao:'tarefa', responsavel_id}` sem o `tipo_tarefa_id` porque a prop `config` do teste não muda entre os `setValue` — comportamento normal do componente "emite config nova a partir da prop".)

`PainelPasso.vue`:
- imports: `import { PAPEIS, PASSOS, TIPOS_TAREFA, UNIDADES, gatilhoInfo } from './fluxo';`, `import ConfigAdvbox from './ConfigAdvbox.vue';`, `import ConfigIa from './ConfigIa.vue';`
- depois do `<ConfigAcoesChatwoot … />` (:119-123):

```vue
      <ConfigIa
        v-else-if="['perguntar_ia', 'rascunho_ia', 'rodar_skill'].includes(tipo)"
        :key="`${no.id}-${tipo}`"
        :tipo="tipo"
        :config="config"
        @update:config="c => emit('update:config', c)"
      />
      <ConfigAdvbox
        v-else-if="tipo === 'advbox'"
        :key="no.id"
        :config="config"
        @update:config="c => emit('update:config', c)"
      />
```

- o `CampoTexto` de texto (:125-130) passa a valer para `['rascunho_texto', 'nota_privada', 'registrar_atividade']`.
- antes do ramo `esperar` (:229):

```vue
      <template v-else-if="tipo === 'webhook'">
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.WEBHOOK_URL`) }}
          <input
            data-testid="webhook-url"
            :class="CAMPO"
            type="url"
            :value="config.url || ''"
            @input="muda('url', $event.target.value)"
          />
        </label>
        <p class="text-xs text-n-slate-10">{{ t(`${K}.PAINEL.WEBHOOK_AJUDA`) }}</p>
      </template>

      <template v-else-if="tipo === 'trocar_responsavel'">
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.PAPEL`) }}
          <select
            data-testid="papel"
            :class="SELECT"
            :value="config.papel || ''"
            @change="muda('papel', $event.target.value)"
          >
            <option v-for="p in PAPEIS" :key="p" :value="p">
              {{ t(`${K}.PAPEIS.${p}`) }}
            </option>
          </select>
        </label>
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.PESSOA`) }}
          <select
            :class="SELECT"
            :value="config.user_id ?? ''"
            @change="muda('user_id', numeroOuNada($event.target.value))"
          >
            <option value="">{{ t(`${K}.PAINEL.DISTRIBUIR_NO_TIME`) }}</option>
            <option v-for="p in pessoas" :key="p.id" :value="p.id">
              {{ p.name }}
            </option>
          </select>
        </label>
      </template>

      <template v-else-if="tipo === 'preencher_campo'">
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.CHAVE_CAMPO`) }}
          <input
            data-testid="campo-chave"
            :class="CAMPO"
            :value="config.chave || ''"
            @input="muda('chave', $event.target.value)"
          />
          <span>{{ t(`${K}.PAINEL.CHAVE_CAMPO_AJUDA`) }}</span>
        </label>
        <CampoTexto
          :rotulo="t(`${K}.PAINEL.VALOR`)"
          :linhas="2"
          :model-value="config.valor || ''"
          @update:model-value="v => muda('valor', v)"
        />
      </template>
```

`ConfigGatilho.vue`:
- imports: `CAMPO` no import do kit; `import { GATILHOS, REGRAS_ADVBOX, gatilhoInfo } from './fluxo';`; getters `const teses = useMapGetter('theses/getTheses');`, `const pessoas = useMapGetter('agents/getAgents');`
- computeds:

```js
const opcoesTeses = computed(() =>
  teses.value.map(x => ({ id: x.id, nome: x.name }))
);
const opcoesPessoas = computed(() =>
  pessoas.value.map(x => ({ id: x.id, nome: x.name }))
);
const opcoesRegras = computed(() =>
  REGRAS_ADVBOX.map(r => ({
    id: r,
    nome: t(`CAPTAIN_RAMON.FLUXOS.REGRAS_ADVBOX.${r}`),
  }))
);
const relogio = computed(() =>
  ['relogio', 'lead_parado'].includes(props.config.tipo)
);
```

- template, depois do bloco `lead_mudou_etapa` e antes do `MANUAL_AJUDA`:

```vue
    <label v-if="relogio" :class="ROTULO">
      {{ t(`${K}.HORA`) }}
      <input
        data-testid="gatilho-hora"
        :class="CAMPO"
        type="time"
        :value="config.hora || (config.tipo === 'lead_parado' ? '11:00' : '')"
        @input="muda('hora', $event.target.value)"
      />
    </label>

    <label v-if="config.tipo === 'lead_parado'" :class="ROTULO">
      {{ t(`${K}.DIAS_PARADO`) }}
      <input
        :class="CAMPO"
        type="number"
        min="1"
        :value="config.dias ?? ''"
        @change="
          muda(
            'dias',
            $event.target.value === '' ? null : Number($event.target.value)
          )
        "
      />
      <span>{{ t(`${K}.DIAS_PARADO_AJUDA`) }}</span>
    </label>

    <template v-if="config.tipo === 'relogio'">
      <div :class="ROTULO">
        {{ t(`${K}.GRUPO_ETAPAS`) }}
        <ListaMarcar
          :opcoes="opcoesEtapas"
          :model-value="config.etapa_ids || []"
          @update:model-value="v => muda('etapa_ids', v)"
        />
      </div>
      <div :class="ROTULO">
        {{ t(`${K}.GRUPO_TESES`) }}
        <ListaMarcar
          :opcoes="opcoesTeses"
          :model-value="config.tese_ids || []"
          @update:model-value="v => muda('tese_ids', v)"
        />
      </div>
      <div :class="ROTULO">
        {{ t(`${K}.GRUPO_RESPONSAVEIS`) }}
        <ListaMarcar
          :opcoes="opcoesPessoas"
          :model-value="config.responsavel_ids || []"
          @update:model-value="v => muda('responsavel_ids', v)"
        />
        <span>{{ t(`${K}.GRUPO_AJUDA`) }}</span>
      </div>
    </template>

    <div v-if="config.tipo === 'evento_advbox'" :class="ROTULO">
      {{ t(`${K}.REGRAS`) }}
      <ListaMarcar
        :opcoes="opcoesRegras"
        :model-value="config.regras || []"
        @update:model-value="v => muda('regras', v)"
      />
      <span>{{ t(`${K}.REGRAS_AJUDA`) }}</span>
    </div>

    <p
      v-if="['reuniao_marcada', 'reuniao_cancelada'].includes(config.tipo)"
      class="text-xs text-n-slate-10"
    >
      {{ t(`${K}.REUNIAO_AJUDA`) }}
    </p>
    <p
      v-if="config.tipo === 'documento_recebido'"
      class="text-xs text-n-slate-10"
    >
      {{ t(`${K}.DOCUMENTO_AJUDA`) }}
    </p>
```

`NoPasso.vue` — no `detalhe`, dentro de `case 'gatilho':` antes do `if (c.tipo === 'lead_mudou_etapa')`:

```js
      if (['relogio', 'lead_parado'].includes(c.tipo))
        return t(`${K}.NO.AS_HORA`, {
          quando: c.hora || (c.tipo === 'lead_parado' ? '11:00' : '—'),
        });
      if (c.tipo === 'evento_advbox')
        return (
          (c.regras || [])
            .map(r => t(`${K}.REGRAS_ADVBOX.${r}`))
            .join(', ') || t(`${K}.NO.QUALQUER_EVENTO`)
        );
```

e casos novos antes do `default`:

```js
    case 'perguntar_ia':
      return curto(c.pergunta);
    case 'rascunho_ia':
    case 'rodar_skill':
      return curto(c.instrucao);
    case 'advbox':
      return c.acao ? t(`${K}.PAINEL.ADVBOX_ACOES.${c.acao}`) : '';
    case 'webhook':
      return curto(c.url);
    case 'trocar_responsavel':
      return c.papel ? t(`${K}.PAPEIS.${c.papel}`) : '';
    case 'preencher_campo':
      return c.chave || '';
```

(`registrar_atividade` cai no `default: curto(c.texto)`.)

- [ ] **Step 4: Run** — `TZ=UTC ./node_modules/.bin/vitest --no-watch --config vitest.local.config.ts app/javascript/dashboard/routes/dashboard/captain/automacoes/specs` → todos verdes; `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes/` → limpo (só `Delete ␍` ignorável).

- [ ] **Step 5: Commit** — `git add` `ConfigIa.vue ConfigAdvbox.vue PainelPasso.vue ConfigGatilho.vue NoPasso.vue specs/ConfigIa.spec.js specs/ConfigAdvbox.spec.js specs/PainelPasso.spec.js` → `feat(fluxos): painéis dos passos e gatilhos da B2b` + rodapé.

---

### Task 10: Verificação final, notas na spec e texto do PR

**Files:**
- Modify: `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (acrescentar §13)

- [ ] **Step 1: Front inteiro** — `TZ=UTC ./node_modules/.bin/vitest --no-watch --config vitest.local.config.ts app/javascript/dashboard/routes/dashboard/captain/automacoes/specs` → verde; `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes app/javascript/dashboard/api/ramonFluxos.js` → limpo. `git status --short` não pode listar `vitest.local.config.ts`.

- [ ] **Step 2: Varredura de regras** — `git diff origin/ramon --stat -- app/models/lead.rb` → vazio; `grep -rn "Captain::" app/services/ramon/fluxos` → só dentro de `rodar_skill`/`executar_skill` (atrás de `ChatwootApp.enterprise?`); `grep -n "PREFIXO" app/services/ramon/fluxos/passos/ia.rb` → presente no `rascunho_ia`.

- [ ] **Step 3: Notas da B2b na spec** — acrescentar ao fim de `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md`:

```markdown
## 13. Notas da B2b (06/10/2026)

- `rascunho_ia` não tem assistente/skill opcional: para texto escrito por skill, `rodar_skill` → `rascunho_texto` com `{resposta_ia}`.
- `rodar_skill` roda sem conversa no estado do runner (como o Testar): ferramentas da skill não agem na conversa; resultado = nota privada + `{resposta_ia}`.
- `documento_recebido` nasce em `Ramon::DocMatchService#gravar_sugestao` (o `DocMatchJob` não sabe se houve casamento); é sugestão da IA — "Documentos completos?" conta só o confirmado pela equipe.
- Reunião: 1 linha em `Ramon::ReuniaoAgendamento.notify` (cobre painel e Cal.com, inclusive o cancel do Cal.com); remarcar = `reuniao_marcada`.
- `preencher_campo` grava em `custom_attributes['campos'][chave]` e o campo vira variável.
- `lead_parado` dispara 1 vez por parada; `relogio`/`lead_parado` 1×/dia por fluxo (`ultimo_disparo_em`, fuso SP).
- O executor grava a execução a cada passo (passo lento não parece órfão ao relógio).
- Teto próprio de IA: `RAMON_FLUXO_IA_DIA` (padrão 200 chamadas/conta/dia); estourou → passo falha + sino.
```

- [ ] **Step 4: Texto do PR (não abrir — gate do Eduardo)** — deixar no relatório final:

```markdown
Automações em fluxo — B2b: o quadro ganha os passos de IA (perguntar sim/não, rascunho escrito pela IA, rodar skill de assistente), ADVBOX (tarefa ou movimentação fixa no processo do lead), webhook (último passo, só https), registrar atividade, trocar SDR/Closer e preencher campo; e os gatilhos reunião marcada/cancelada, evento do ADVBOX, contrato assinado/recusado (ZapSign), documento recebido, lead parado e "todo dia num horário". O modelo Pós-contrato passa a começar no contrato assinado e pergunta "Documentos completos?". Tudo que fala com cliente continua saindo como RASCUNHO.

## How to test
- Inteligência → Automações → Novo fluxo → Pós-contrato: o quadro mostra contrato assinado → boas-vindas → tarefa → espera → Se documentos completos → (não) rascunho da IA → push.
- "+ Adicionar passo": grupos Inteligência artificial e Integrações aparecem; webhook não aceita seta de saída.
- Passo ADVBOX: os selects listam tipos de tarefa e pessoas do ADVBOX.
- Testar com um lead real (ensaio): Perguntar à IA responde de verdade; rascunho da IA, skill, ADVBOX e webhook só descrevem.

## What changed
- `Ramon::Fluxos::Passos::{Ia,Externo}` (novos), `Passos::Lead` (+3), `Ramon::Fluxos::Relogio` (novo), `Disparo.externo`, `GET ramon_fluxos/opcoes_advbox`.
- 1 linha em `ReuniaoAgendamento.notify`, `AdvboxEventProcessor#perform`, `ZapsignLeadStatusJob`, `DocMatchService#gravar_sugestao`.
- Sem migração. Env nova opcional: `RAMON_FLUXO_IA_DIA` (padrão 200).

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv
```

- [ ] **Step 5: Smoke em bloco (para o Eduardo, depois do deploy)** — anotar no relatório: (1) conta com `captain_integration_v2` ligado (o `rodar_skill` usa o runner V2); (2) `ADVBOX_API_TOKEN` presente (selects do passo ADVBOX); (3) fluxo de teste `relogio` com hora = agora+2 min num lead temporário → execução aparece; (4) ensaio do Pós-contrato num lead com checklist; (5) apagar `LeadActivity` antes do lead temporário.

- [ ] **Step 6: Commit** — `git add docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` → `docs(fluxos): notas da B2b na spec` + rodapé. Sem push.

---

## Decisões que dependem do Eduardo (o plano já segue a recomendação; mudar = trocar 1 constante/linha)

| # | Decisão | Recomendação no plano |
|---|---|---|
| E1 | Teto próprio de chamadas de IA dos fluxos por dia (além do `limite_dia` de execuções) | Sim: `RAMON_FLUXO_IA_DIA`, padrão **200**/conta/dia; estourou → passo falha na hora + sino (Task 5) |
| E2 | `rodar_skill` sem conversa no estado (ferramentas da skill não agem; handoff/mensagem de ausência nunca saem) | Sim (Task 5) |
| E3 | `preencher_campo` em `custom_attributes['campos']` (não na raiz) | Sim (Task 3) |
| E4 | `documento_recebido` na sugestão da IA (não na confirmação humana) | Manter a spec (Task 6); "completos" só conta o confirmado |
| E5 | Pós-contrato começa em `contrato_assinado` (antes: qualquer mudança de etapa) e ganha o Se "Documentos completos?" → rascunho da IA + push | Sim (Task 8) — textos do modelo passam pelo Eduardo antes de publicar |
| E6 | `lead_parado` 1 vez por parada (não todo dia) | Sim (Task 7) |
| E7 | Webhook leva nome e telefone do lead (dados do contexto) | Sim, admin-only + https + bloqueio de rede interna; tirar `telefone` do `payload` se preferir |
