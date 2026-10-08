# Automações: 16 viram regra fixa + a ficha das 29 no hub — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Das 29 automações do sistema, 7 seguem no fluxo (já ligadas em produção) e as outras 22 ficam no código como "regra fixa" — as 16 que tinham andaimes de migração (nunca ligados) perdem os andaimes — e cada uma das 29 ganha uma **ficha** em linguagem simples dentro do hub (Automações → Do sistema → clicar).

**Architecture:** Três tasks de limpeza devolvem as 16 ao código de antes das B5 (os blocos `Migracao.decidir` / `Externos.evento` / `Conta.cada_conta` viram a linha original; grupos, rotinas prontas, JSON migrados, envs, gatilhos mortos e specs saem). A ficha é **dado**: um objeto `"ficha"` em cada `db/seeds/ramon/fluxos/sistema/<chave>.json` (texto no Anexo A deste plano), servido só no `show` da API por `Ramon::Fluxos::Sistema.ficha` (que troca as chaves dos fluxos pelos fluxos de verdade da conta) e desenhado por um componente novo `FichaSistema.vue` no painel direito do editor só-leitura. Nada muda nas 7 que rodam no fluxo (a limpeza E7 delas é outro PR).

**Tech Stack:** Rails 7.1 (RSpec, só no CI), Vue 3 `<script setup>` + Tailwind + kit `ramon/helpers/ui.js`, vue-i18n, Vitest, Chrome headless (prints).

**Spec:** `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (§8, §19–§21; esta fatia acrescenta o §22). Plano-modelo dos andaimes que saem: `docs/superpowers/plans/2026-10-07-automacoes-fluxo-b5-{conta,leads,externos}.md`.

---

## Decisões para o Eduardo

**N1 — Os 5 gatilhos que nasceram só para as migrações de "fora do funil" saem da paleta?**
São: *Assinatura do Painel do Cliente mudou*, *Cliente enviou documento pelo Painel*, *Reunião gravada*, *Peça publicada no Instagram* e *Peça mudou de status*. Com as automações deles voltando a ser regra fixa, o código não precisa mais avisar os fluxos nesses momentos.
- **A (recomendado):** tirar os 5 da paleta. Ninguém usa (só existiam para os fluxos migrados, que nunca foram criados em produção). Se um dia você quiser um fluxo seu nesses momentos, volta em 1 linha por ponto.
- **B:** manter os 5 como gatilhos comuns, para fluxos seus (o código continua fazendo tudo e só "avisa" o gatilho, sem decidir nada).
Este plano faz **A**. *Nota privada escrita* fica (já é usado por fluxos comuns e não depende da migração); *Chegada de cliente*, *Contrato assinado* e *Contrato recusado* ficam (a chegada roda no fluxo; os de contrato existiam antes das B5).

## Escopo decidido pelo Eduardo (08/10)

1. **7 no fluxo** (não mexer no caminho de código delas; a limpeza E7 é outro PR, ~2 semanas): reuniões (3 fluxos), SLA da 1ª resposta, cadência, lead ganho, eventos do ADVBOX, chegada de cliente, resumo do dia.
2. **22 regra fixa:** as 6 que já têm `"fixa": true` (histórico do lead, documentos completos, contrato limpo, contrato limpo cancelado, SDR automático, etiquetas de etapa e tese) **+ 16** que foram migradas mas nunca ligadas: criar lead da conversa, origem do lead, sugestão de documento, coach de objeção, agente do hub, retrato do funil, fechamento do extrato, espelho do Painel, copiloto noturno, publicar peças, avisos do Painel, assinatura pelo Painel, contrato no ZapSign, documento pelo Painel, ata da reunião, acervo das peças. Os andaimes das 16 **saem agora**.
3. **Ficha das 29** na tela (O QUE FAZ · QUANDO · O QUE MEXE · TRAVAS E GARANTIAS · POR QUE FICA NO CÓDIGO / NO FLUXO com "Abrir o fluxo" · SE QUISER MUDAR). Texto tirado do código real (Anexo A) — **é conteúdo que o Eduardo revisa nos prints de aprovação**.
4. Notas na spec: §22.

## Premissa de produção (conferir antes do deploy — ver "Operação")

O controlador afirma: **produção não tem fluxos nem envs das 16**. O código confirma que os andaimes só agem com env `=on` **e** fluxo criado por `rake ramon:fluxos:migracao:criar[...]` (`Migracao.assumiu?`), e que o `.env.example` traz todas `off`. O código não mostra o `chatwoot.env` da VPS: a seção Operação traz 1 comando só de leitura para o Eduardo confirmar. Se aparecer algum fluxo das 16, ele é excluído na tela **antes** do deploy (depois do deploy ele falharia com "rotina desconhecida").

## Escolhas técnicas (decididas no plano)

- **Volta ao código de antes, linha a linha.** Cada ponto de decisão das 16 volta ao que era antes das B5 (conferido com `git show 75dac9337c^`, `4ea35618cf^`, `b581fa76dc^`). Refatorações inofensivas que outras partes usam **ficam**: `Ramon::LeadDaConversa` (o ouvinte chama), `Ramon::AgenteNotifyJob.chamado?` (o ouvinte chama), `Chegada#escalar!`/`#escalavel?` (a chegada roda no fluxo), `Peca#espelhar_notion` pública (o `PublicarPecasJob` chama depois do `update_columns`; o corpo volta a ser só o job), `ZapsignLeadStatusJob.avisar` público, os `private` por conta de `PortalAvisosJob`/`PortalSyncJob` (o `perform` volta a `Account.find_each`), `delegate :account` em `PortalAssinatura`/`PortalEnvio`, `FluxoExecucao.lead_de` (com `Reuniao`, inofensivo). Sai: `LeadDaConversa.origem_pendente?` (só servia à decisão).
- **Gatilho mantido, decisão retirada:** o ZapSign volta a `avisar` + `Disparo.externo(gatilho, lead)` (os gatilhos *Contrato assinado/recusado* são de antes das B5 e seguem para fluxos comuns).
- **`Disparo::DUAS_VEZES`** perde `mensagem_recebida` e `nota_escrita` (ninguém mais manda `assumido` neles); `Externos.gatilhos` passa a ser só `chegada_cliente`. **`NA_HORA_CHAVES`** sai.
- **`Rotinas::Conta`** fica só com `resumo_do_dia` (é o caminho no fluxo: `rodar`, `cada_conta`, `decidir`, `iniciar` não mudam). Sai `PENDENTE`, `A_CADA_MINUTO`, `AVISOS_DESLIGADOS`; `disputa?` vira `intervalo(...).nil?` (equivalente para uma rotina diária; o spec "diária editada para a cada N min" segue provando). O mecanismo genérico `Rotinas.pendente`/`HorarioConta.tem_o_que_fazer?` **fica** (caminho do resumo do dia — não mexer).
- **`Rotinas::Leads`** sai inteiro (arquivo `.rb` e `.js`). **`Rotinas::Externos`** fica só com o grupo `chegada_cliente` e a rotina `escalar_chegada`.
- **`FluxoExecucao::NOMES_ALVO`** fica só com `Chegada` (os outros 4 alvos não têm mais gatilho).
- **Ficha = dado no JSON do sistema**, lida da memória (`Sistema.desenhos`), sem coluna nova nem migração; vai **só no `show`** (a lista não carrega 29 textos). `"fluxos"` no JSON lista as chaves dos fluxos migrados (só nas 7); a API troca por `[{id, nome, modo, ativo}]` dos fluxos de verdade da conta.
- **Aplicar as fichas por script** (`tmp/aplicar-fichas.mjs`, fora do git): insere `"fixa": true` depois de `"grupo"` nas 16 e o objeto `"ficha"` antes de `"desenho"` nas 29, sem reformatar o resto do arquivo (o desenho tem um nó por linha).
- **Tela:** o painel direito do desenho do sistema passa a ser a ficha (420 px, rola), e o "Como roda hoje" antigo vira um `<details>` no fim, "Como roda no código (detalhes técnicos)". O Editor passa a recarregar quando o `fluxoId` da rota muda (o "Abrir o fluxo" navega de um editor para outro — o Vue reaproveita o componente). Na lista, o selo das 7 deixa de dizer "roda no código" e passa a "roda no fluxo".

## Global Constraints

- PT-BR em tudo que o Eduardo lê; textos de tela simples. Ficha = dado (não i18n); só os títulos são i18n (`en` e `pt_BR`, mesmas chaves — `i18n.spec.js` trava).
- Sem Ruby local: specs RSpec rodam só no CI. Frontend: `TZ=UTC npx vitest run <arquivos>` e `./node_modules/.bin/eslint <arquivos>` rodam aqui.
- Rubocop do fork: AbcSize 26, MethodLength 19, Cyclomatic 7, Perceived 8, ClassLength 175, ModuleLength 100, BlockLength 30, linha 150, `RSpec/MultipleExpectations` 7, `RSpec/ExampleLength` 50; `RSpec/ContextWording` (when/with/without); `Layout/EmptyLineAfterGuardClause`.
- Tailwind só; kit `dashboard/routes/dashboard/ramon/helpers/ui.js` (`CARTAO`, `CARTAO_STATUS`, `FILETE`, `CHIP`, `TOM`, `AVISO`, `TITULO`); fundos coloridos **translúcidos**; evento Vue camelCase.
- Não tocar no caminho de código das 7 no fluxo (só comentários e a remoção de entradas das 16 em listas compartilhadas).
- Commits: Conventional Commits em PT-BR, sem citar o Claude no assunto, com as 2 linhas finais:
  ```
  Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR
  ```
- Não fazer push/merge/deploy nem tocar na VPS (o controlador cuida); merge só com o "aprovado" do Eduardo nos prints.

## Review Focus

1. **Alguma das 16 parar de acontecer.** Depois da limpeza, cada ponto tem de rodar o código de sempre sem condição: `grep -rn "Externos.evento\|Migracao.decidir\|cada_conta" app` só pode achar `sla` (ouvinte), `chegada_cliente` (controller da chegada) e `resumo_do_dia` (job do resumo). Task 10 roda esse grep.
2. **Gatilho comum que some sem querer.** *Contrato assinado/recusado* (ZapSign) e *Documento recebido* (sugestão de documento) continuam disparando para fluxos comuns; *Nota privada escrita* também. Cobertos por: `spec/services/ramon/doc_match_service_spec.rb` (não muda — `documento_recebido` nasce no serviço, não na decisão), Task 2 (`nota_escrita` dispara uma vez para os fluxos comuns) e Task 4 (`Disparo.externo('contrato_assinado', lead).once`; os 5 gatilhos mortos recusados e os vivos presentes no `Grafo`).
3. **Ficha com arquivo inexistente ou fluxo apontando chave sem migrado.** Spec Ruby da Task 6 confere `Rails.root.join(arquivo).exist?` e `Migracao::PASTA.join("#{chave}.json").exist?` para as 29.
4. **"Abrir o fluxo" não recarregar o editor** (mesmo componente, `fluxoId` novo). Spec do Editor na Task 8 (`watch` do `fluxoId`).
5. **Fluxo migrado das 16 já criado em alguma conta** (a premissa falha): o passo `rotina` acusaria "rotina desconhecida". Coberto pela checagem de leitura na Operação, antes do deploy.

---

## Mapa de arquivos

| Arquivo | Task | O quê |
|---|---|---|
| `app/listeners/ramon_lead_listener.rb`, `app/listeners/ramon_agente_listener.rb`, `app/services/ramon/lead_da_conversa.rb`, `app/jobs/ramon/agente_notify_job.rb` (comentário) | 2 | criar lead, origem, documento, coach e agente voltam direto ao código |
| `app/services/ramon/fluxos/rotinas/leads.rb` (apagar), `app/services/ramon/fluxos/disparo.rb` | 2 | sem grupos/rotinas de leads; `NA_HORA_CHAVES` e `DUAS_VEZES` |
| `app/jobs/ramon/{daily_funnel_snapshot,extrato_fechamento,night_copilot,portal_sync,portal_avisos,publicar_pecas}_job.rb`, `app/services/ramon/fluxos/rotinas/conta.rb`, `app/services/ramon/fluxos/horario_conta.rb` (comentário) | 3 | 6 rotinas da conta voltam ao cron; `Conta` só com o resumo |
| `app/controllers/public/api/v1/zapsign_webhooks_controller.rb`, `app/controllers/cliente/painel_controller.rb`, `app/controllers/api/v1/accounts/ramon_reunioes_controller.rb`, `app/jobs/ramon/zapsign_lead_status_job.rb`, `app/jobs/ramon/publicar_pecas_job.rb`, `app/models/peca.rb`, `app/models/fluxo_execucao.rb`, `app/services/ramon/fluxos/{grafo,externos}.rb`, `app/services/ramon/fluxos/rotinas/externos.rb` | 4 | 5 de fora do funil voltam ao código; 5 gatilhos saem |
| `db/seeds/ramon/fluxos/migrados/*.json` (18 apagados), `.env.example`, `app/javascript/.../automacoes/{fluxo.js,rotinas/*.js}`, i18n `ramon.json` (en/pt_BR), specs do front | 5 | o que sobrou dos andaimes, no front e nos dados |
| `db/seeds/ramon/fluxos/sistema/*.json` (29) | 6 | `"fixa": true` nas 16 + a ficha nas 29 |
| `app/services/ramon/fluxos/sistema.rb`, `app/controllers/api/v1/accounts/ramon_fluxos_controller.rb` | 7 | `Sistema.ficha` + `show` |
| `app/javascript/.../automacoes/{FichaSistema.vue (novo),Editor.vue,Lista.vue}`, i18n | 8 | a tela |
| `app/javascript/.../automacoes/Automacoes.story.vue`, `tmp/fichas-harness/*`, `comercial/docs/mockups/2026-10-08-fichas-automacoes/*` | 1, 9 | prints antes/depois + `comparar.html` |
| `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` | 10 | §22 |

Tasks **mecânicas** (código completo no plano): 1, 2, 3, 4, 5, 6, 7, 10. Tasks com **julgamento** (layout conferido no print): 8, 9.

Ordem: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 (2–5 são sequenciais: mexem em `disparo.rb`, `fluxo.spec.js` e nas mesmas specs de serviço).

---

### Task 1: Harness + prints "antes" (mecânica)

Roda **antes de qualquer mudança de código** (o "antes" é `origin/ramon` 76d9560).

**Files:**
- Create (não versionado — `tmp/` está no `.gitignore`): `tmp/fichas-harness/{index.html,ConversationBoxStub.vue,BackButtonStub.vue,main.js,vite.config.mts,shots.sh,telas-antes.txt}`
- Output: `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-08-fichas-automacoes\antes-*.png`

**Interfaces:**
- Produces: harness em `http://localhost:6198/?story=automacoes&variant=<Título>&tema=claro|escuro`; `sh tmp/fichas-harness/shots.sh antes|depois` lê `telas-<fase>.txt` (linhas `story:Variante:arquivo:LxA`). A Task 9 usa.

- [ ] **Step 1: Copiar o harness da A5** (Bash; o sed não tem barra invertida):

```bash
cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-fluxos-b5-conta
mkdir -p tmp/fichas-harness
H=../ramon-hub-wt-intel-a5/tmp/intel-a5-harness
cp $H/index.html $H/ConversationBoxStub.vue $H/BackButtonStub.vue $H/main.js $H/vite.config.mts $H/shots.sh tmp/fichas-harness/
sed -i 's/intel-a5-harness/fichas-harness/g; s/2026-10-07-inteligencia-a5/2026-10-08-fichas-automacoes/g; s/6197/6198/g' tmp/fichas-harness/shots.sh tmp/fichas-harness/vite.config.mts
grep -n "6198\|fichas-automacoes\|fichas-harness" tmp/fichas-harness/shots.sh tmp/fichas-harness/vite.config.mts
```
Expected: o grep mostra a porta 6198 no `vite.config.mts` e `fichas-automacoes`/`fichas-harness` no `shots.sh`. (Se o `vite.config.mts` citar caminhos da worktree da A5 — `ramon-hub-wt-intel-a5` —, trocar por `ramon-hub-wt-fluxos-b5-conta` com um `sed` igual.)

- [ ] **Step 2: Story das Automações no harness** — em `tmp/fichas-harness/main.js` (Edit), trocar

```js
  casos: () => import('dashboard/routes/dashboard/captain/casos/CasosTeste.story.vue'),
```
por
```js
  casos: () => import('dashboard/routes/dashboard/captain/casos/CasosTeste.story.vue'),
  automacoes: () => import('dashboard/routes/dashboard/captain/automacoes/Automacoes.story.vue'),
```

- [ ] **Step 3: `tmp/fichas-harness/telas-antes.txt`** (Write):

```
automacoes:DoSistema:do-sistema:1440,2200
automacoes:SistemaLembretes:sistema-lembretes:1440,1000
automacoes:SistemaAvisos:sistema-avisos:1440,1000
```

- [ ] **Step 4: Subir o harness** (Bash, `run_in_background: true`): `cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-fluxos-b5-conta && npx vite --config tmp/fichas-harness/vite.config.mts`. Conferir: `curl -s -o /dev/null -w "%{http_code}" "http://localhost:6198/?story=automacoes&variant=DoSistema"` → `200`.

- [ ] **Step 5: Prints "antes"** — `cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-fluxos-b5-conta && sh tmp/fichas-harness/shots.sh antes`. Expected: 6 arquivos `antes-{claro,escuro}-*.png`. Abrir com Read `antes-claro-do-sistema.png` e `antes-escuro-sistema-avisos.png`: tela desenhada, fonte Geist, nada de página branca (se vier branca: olhar o log do Vite em segundo plano — import que falta no alias é a causa típica).

- [ ] **Step 6: Sem commit** (nada versionado mudou). Deixar o harness no ar (a Task 9 usa).

---
### Task 2: Leads e conversas — criar lead, origem, documento, coach e agente voltam direto ao código (mecânica)

**Files:**
- Modify: `app/listeners/ramon_lead_listener.rb`, `app/listeners/ramon_agente_listener.rb`, `app/services/ramon/lead_da_conversa.rb`, `app/jobs/ramon/agente_notify_job.rb` (só comentário), `app/services/ramon/fluxos/disparo.rb`
- Delete: `app/services/ramon/fluxos/rotinas/leads.rb`, `spec/services/ramon/fluxos/rotinas/leads_spec.rb`
- Test (modify): `spec/listeners/ramon_lead_listener_spec.rb`, `spec/listeners/ramon_agente_listener_spec.rb`, `spec/services/ramon/fluxos/migracao_spec.rb`, `spec/services/ramon/fluxos/disparo_spec.rb`

**Interfaces:**
- Consumes: `Ramon::LeadDaConversa.{cabe?,criar_ou_ligar,origem}`, `Ramon::AgenteNotifyJob.chamado?`, `Ramon::Fluxos::Migracao.decidir(nome, gatilho, alvo, dados) { }` (segue existindo para `sla` e `chegada_cliente`).
- Produces: `Migracao::GRUPOS` sem `criar_lead/origem_lead/sugestao_doc/coach/agente`; `Disparo::DUAS_VEZES = NA_HORA + %w[conversa_criada lead_ganho] + Externos.gatilhos`; sem `Disparo::NA_HORA_CHAVES`. O front (`rotinas/leads.js`) sai na Task 5.

- [ ] **Step 1: Specs primeiro** (Edit).

`spec/listeners/ramon_agente_listener_spec.rb` — apagar o bloco inteiro `describe 'pelo fluxo (B5-leads: RAMON_FLUXO_AGENTE=on + o fluxo "Agente do hub" em modo normal)' do … end` (do `describe` até o `end` que o fecha, antes do `end` final do arquivo). Os 2 exemplos de cima ficam (provam o código de sempre).

`spec/services/ramon/fluxos/migracao_spec.rb`:
- apagar os exemplos `it 'leads e conversas (B5-leads): 5 migrações, cada uma com a sua chave e o seu gatilho' do … end` e `it 'leads e conversas (B5-leads): criar = 1 fluxo por grupo, em sombra, ligado, publicado, gatilho certo e 1 rotina pronta' do … end`;
- a decisão passa a ser provada com o grupo que segue vivo (o SLA). Substituir o bloco inteiro `describe '.decidir (B5-leads): a decisão do evento, lida uma vez, com reserva' do … end` por:

```ruby
  describe '.decidir: a decisão do evento, lida uma vez, com reserva (SLA e chegada usam)' do
    let(:conversa) { create(:conversation, account: account) }
    let(:fluxo) do
      fluxo_publicado(account, grafo_linear({ 'tipo' => 'conversa_criada' }, ['parar', {}]),
                      sistema_chave: 'sla_primeira_resposta', modo: 'normal')
    end

    it 'código no comando (chave desligada): o bloco roda e o fluxo do grupo só ensaia' do
      fluxo
      expect { |b| described_class.decidir('sla', 'conversa_criada', conversa, {}, &b) }.to yield_control.once
      expect(fluxo.execucoes.sole.ensaio).to be(true)
    end

    it 'fluxo no comando que pegou o evento: o bloco não roda (nunca em dobro)' do
      fluxo
      with_modified_env(RAMON_FLUXO_SLA: 'on') do
        expect { |b| described_class.decidir('sla', 'conversa_criada', conversa, {}, &b) }.not_to yield_control
      end
      expect(fluxo.execucoes.sole.ensaio).to be(false)
    end

    it 'fluxo no comando que NÃO pegou o evento (ocupado com a mesma conversa): o bloco roda (reserva, nunca nenhum)' do
      fluxo.execucoes.create!(account: account, alvo: conversa, status: 'esperando', retomar_em: 5.minutes.from_now)
      with_modified_env(RAMON_FLUXO_SLA: 'on') do
        expect { |b| described_class.decidir('sla', 'conversa_criada', conversa, {}, &b) }.to yield_control.once
      end
      expect(fluxo.execucoes.count).to eq(1)
    end

    it 'motor com erro: o bloco roda (o Disparo.externo engole o erro e devolve [])' do
      allow(Ramon::Fluxos::Disparo).to receive(:call).and_raise(StandardError, 'motor')
      with_modified_env(RAMON_FLUXO_SLA: 'on') do
        fluxo
        expect { |b| described_class.decidir('sla', 'conversa_criada', conversa, {}, &b) }.to yield_control.once
      end
    end
  end

  it 'as 16 regras fixas de 08/10 não são mais migração; sobram as 7 que rodam no fluxo' do
    fixas = %w[criar_lead origem_lead sugestao_doc coach agente retrato_funil fechamento_extrato espelho_painel
               copiloto_noturno publicar_pecas avisos_painel assinatura_painel contrato_zapsign documento_painel
               ata_reuniao acervo_pecas]
    expect(described_class::GRUPOS.keys & fixas).to eq([])
    expect(described_class::GRUPOS.keys)
      .to match_array(%w[reunioes sla cadencia lead_ganho eventos_advbox resumo_do_dia chegada_cliente])
  end
```
(Esse último exemplo só fica verde depois das Tasks 3 e 4 — é a trava final do pacote. O CI roda no PR inteiro.)

`spec/services/ramon/fluxos/disparo_spec.rb` — apagar os 3 exemplos `it 'B5-leads: dois grupos migrados no mesmo gatilho — cada decisão só inicia o fluxo do seu grupo'`, `it 'B5-leads: criar lead e origem migrados rodam na hora (dentro do ouvinte); coach, documento e SLA seguem pelo job'` e `it 'B5-leads: nota privada escrita dispara 2 vezes — com a decisão só o migrado; sem, só os comuns'`. Acrescentar, no fim do `RSpec.describe` (antes do `end` final):

```ruby
  it 'regra fixa (08/10): mensagem recebida e nota escrita disparam uma vez só, para todos os fluxos com o gatilho' do
    comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'nota_escrita' }, nota))
    expect(described_class::DUAS_VEZES).not_to include('mensagem_recebida', 'nota_escrita')
    expect(described_class.call('nota_escrita', conversa, { 'texto' => 'oi' }).map(&:fluxo)).to eq([comum])
  end
```
(`nota` e `conversa` já são `let` do arquivo — usados pelos exemplos B5 apagados.)

`spec/listeners/ramon_lead_listener_spec.rb` — substituir o bloco inteiro `describe 'leads e conversas — código ou fluxo (B5-leads)' do … end` (até o `end` que o fecha, antes do `end` final do arquivo) por:

```ruby
  describe 'a ordem de sempre (regra fixa, 08/10): o lead e a origem antes dos fluxos comuns' do
    let(:anuncio) { { 'source_id' => '12034', 'headline' => 'Machucou no trabalho?' } }

    # Os ouvintes do hub na ordem REAL do AsyncDispatcher (os nativos não mexem em lead nem em fluxo).
    def publicar(nome, dados)
      ev = Events::Base.new(nome, Time.zone.now, dados)
      AsyncDispatcher.new.listeners.select { |l| l.class.name.start_with?('Ramon') }
                     .each { |l| l.public_send(ev.method_name, ev) if l.respond_to?(ev.method_name) }
    end

    # Cada disparo de fluxo, na ordem: [gatilho, grupo que decidiu (nil = os fluxos comuns), o que `olhar` vê naquela hora].
    # Sem verificação: o verify_partial_doubles lê o Hash posicional `dados` como keywords do `origem:` (ver B5-leads).
    def gravar_disparos(&olhar)
      ver = olhar # Performance/RedundantBlockCall: o bloco é chamado depois que o método retorna
      disparos = []
      without_partial_double_verification do
        allow(Ramon::Fluxos::Disparo).to receive(:call).and_wrap_original do |original, gatilho, alvo, dados = {}, **opcoes|
          disparos << [gatilho, dados['migracao'], ver.call]
          original.call(gatilho, alvo, dados, **opcoes)
        end
      end
      disparos
    end

    def lead_da_conversa = account.leads.find_by(conversation_id: conversation.id)

    it 'o lead nasce antes do SLA e dos fluxos comuns de Conversa nova; lead.created sai 1 vez' do
      disparos = gravar_disparos { lead_da_conversa.present? }
      expect { publicar('conversation.created', conversation: conversation) }
        .to have_enqueued_job(Ramon::FirstResponseSlaJob).with(conversation.id)
        .and have_enqueued_job(EventDispatcherJob).with('lead.created', anything, anything).exactly(:once)
      expect(disparos).to eq([['conversa_criada', 'sla', true], ['conversa_criada', nil, true]])
    end

    it 'a origem é gravada antes dos fluxos comuns de Mensagem recebida' do
      create(:lead, account: account, contact: contact, conversation: conversation, channel: 'outro', source: nil)
      disparos = gravar_disparos { lead_da_conversa.source }
      msg = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'oi',
                             content_attributes: { referral: anuncio })
      publicar('message.created', message: msg)
      expect(disparos).to eq([['mensagem_recebida', nil, 'anuncio-meta: 12034']])
    end
  end
```
Os exemplos de cima do arquivo (`#message_created -> atribuição do referral da Meta`, `-> IA casa anexo…`, `-> coach de objeção`, `SLA da 1ª resposta pelo fluxo (B4.2)`) **ficam como estão** — eles já provam o código de sempre e o SLA.

Apagar `spec/services/ramon/fluxos/rotinas/leads_spec.rb` (`git rm`).

- [ ] **Step 2: `app/listeners/ramon_lead_listener.rb`** — trocar o cabeçalho, `conversation_created`, `message_created` e o `private` inteiro (Edit; `lead_created`, `lead_updated` e `conversation_updated` não mudam). Do topo do arquivo até o fim de `message_created`:

```ruby
# frozen_string_literal: true

# Leads e conversas (regra fixa, decisão do Eduardo 08/10): criar lead, origem, sugestão de documento e coach rodam aqui,
# no código, sempre. Só o SLA da 1ª resposta decide entre o código e o fluxo "SLA da 1ª resposta" (Migracao.decidir, com
# reserva). A ordem é a de sempre: o lead nasce ANTES do SLA e dos fluxos comuns de Conversa nova; a origem é gravada
# ANTES dos fluxos comuns de Mensagem recebida (o RamonFluxoListener vem depois deste no AsyncDispatcher).
class RamonLeadListener < BaseListener
  TIPOS_ANEXO = %w[image file].freeze # anexo que a IA tenta casar com o checklist

  def conversation_created(event)
    conversation = event.data[:conversation]
    return unless Ramon::LeadDaConversa.cabe?(conversation)

    Ramon::LeadDaConversa.criar_ou_ligar(conversation)
    # SLA da 1ª resposta (mapa comercial): o vigia dispara N min depois (SLA da caixa, senão o env) e só apita se a conversa
    # seguir aberta e sem resposta. B4.2: com o fluxo "SLA da 1ª resposta" no comando e vigiando a conversa, o job não é agendado.
    Ramon::Fluxos::Migracao.decidir('sla', 'conversa_criada', conversation, 'caixa_id' => conversation.inbox_id) do
      Ramon::FirstResponseSlaJob.set(wait: Ramon::Cadencia.sla_minutes(conversation.inbox).minutes).perform_later(conversation.id)
    end
  end

  # Mensagem do cliente numa conversa com lead: origem → sugestão de documento (anexo) → coach de objeção (texto com 20+
  # caracteres). Colheita NÃO é automática (decisão 20/07).
  def message_created(event)
    message = event.data[:message]
    return unless message.incoming?

    lead = message.account.leads.find_by(conversation_id: message.conversation_id)
    return if lead.blank?

    Ramon::LeadDaConversa.origem(lead, message)
    Ramon::DocMatchJob.perform_later(message.id) if message.attachments.any? { |a| TIPOS_ANEXO.include?(a.file_type) }
    Ramon::CoachObjecaoJob.perform_later(message.id) if message.content.to_s.strip.length >= Ramon::CoachObjecaoService::MIN_CHARS
  end
```
e apagar o bloco `private` inteiro do fim do arquivo (`decidir`, `efeitos_da_mensagem`, `dados_da_mensagem`) — o arquivo termina no `end` de `conversation_updated` + o `end` da classe.

- [ ] **Step 3: `app/listeners/ramon_agente_listener.rb`** (Write — arquivo inteiro):

```ruby
# frozen_string_literal: true

# Gatilho do agente do hub (regra fixa, decisão do Eduardo 08/10): nota privada começando com "@claude", escrita pelo
# Eduardo (Ramon::AgenteNotifyJob.chamado?). Webhook nativo não serve (Message#webhook_sendable? descarta private).
class RamonAgenteListener < BaseListener
  def message_created(event)
    message = event.data[:message]
    Ramon::AgenteNotifyJob.perform_later(message.id) if Ramon::AgenteNotifyJob.chamado?(message)
  end
end
```

- [ ] **Step 4: `app/jobs/ramon/agente_notify_job.rb`** — só o comentário de `chamado?` (Edit): trocar
`  # Quem chama o agente — a trava de sempre, num lugar só (RamonAgenteListener e a rotina agente_hub; a tela não a edita):`
por
`  # Quem chama o agente — a trava de sempre, num lugar só (o RamonAgenteListener; regra fixa, a tela não a edita):`

- [ ] **Step 5: `app/services/ramon/lead_da_conversa.rb`** (Edit):
- cabeçalho: trocar as 3 linhas de comentário depois de `# frozen_string_literal: true` (e da linha em branco) por
```ruby
# Criar lead da conversa e origem do lead — regra fixa (decisão do Eduardo 08/10), chamada pelo RamonLeadListener.
# É o código de sempre, que morava no ouvinte (mudou de arquivo na B5-leads, sem mudar nada).
```
- apagar o método `origem_pendente?` e as 2 linhas de comentário acima dele (só servia à decisão do fluxo; `origem` já não faz nada quando não há anúncio e o canal já foi derivado — como antes das B5).

- [ ] **Step 6: `app/services/ramon/fluxos/disparo.rb`** (Edit):
- apagar as 3 linhas de comentário `# B5-leads: fluxos migrados que rodam na hora pela CHAVE do fluxo …` e a constante `NA_HORA_CHAVES = %w[criar_lead_da_conversa origem_do_lead].freeze`;
- trocar as 5 linhas de comentário acima de `DUAS_VEZES` e a constante por:
```ruby
  # B4.1/B4.2/B4.4: gatilhos que o código dispara 2 vezes — com 'assumido' (a decisão do evento) só os fluxos migrados ouvem;
  # sem (o ouvinte de sempre), só os demais. conversa_criada: o RamonLeadListener manda a decisão do SLA da 1ª resposta;
  # lead_ganho: o callback do Lead (Ramon::Fluxos::LeadGanho) manda com, o RamonFluxoListener sem.
  # B5-externos: a chegada de cliente (Ramon::Fluxos::Externos.evento manda com e sem a decisão). Regra fixa (08/10):
  # mensagem_recebida e nota_escrita saíram — ninguém mais decide nelas.
  DUAS_VEZES = (NA_HORA + %w[conversa_criada lead_ganho] + Ramon::Fluxos::Externos.gatilhos).freeze
```
- trocar o método privado `na_hora?` (o `def` de 3 linhas) por:
```ruby
  def na_hora? = NA_HORA.include?(@fluxo.gatilho_tipo) && Ramon::Fluxos::Migracao.migrado?(@fluxo)
```

- [ ] **Step 7: Apagar `app/services/ramon/fluxos/rotinas/leads.rb`** (`git rm`). O registro (`Ramon::Fluxos::Rotinas.modulos`) acha os arquivos da pasta sozinho — nada a ajustar.

- [ ] **Step 8: Conferir** (sem Ruby local):
```bash
cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-fluxos-b5-conta
grep -rn "Rotinas::Leads\|NA_HORA_CHAVES\|origem_pendente\|RAMON_FLUXO_\(CRIAR_LEAD\|ORIGEM_LEAD\|SUGESTAO_DOC\|COACH\|AGENTE\)" app lib spec --include=*.rb
```
Expected: nada. Ler `ramon_lead_listener.rb` inteiro de novo: linha mais longa ≤ 150; `message_created` simples (AbcSize < 26).

- [ ] **Step 9: Commit**
```bash
git add -A app/listeners app/services/ramon/lead_da_conversa.rb app/jobs/ramon/agente_notify_job.rb app/services/ramon/fluxos/disparo.rb app/services/ramon/fluxos/rotinas spec/listeners spec/services/ramon/fluxos
git commit -m "refactor(fluxos): criar lead, origem, documento, coach e agente viram regra fixa (sem migração)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 3: Rotinas da conta — retrato, extrato, espelho, copiloto, publicar peças e avisos voltam ao cron (mecânica)

O **Resumo do dia** segue no fluxo: o caminho dele (`Rotinas::Conta.rodar/cada_conta/decidir/iniciar`, `HorarioConta`, `DailyDigestJob`) não muda.

**Files:**
- Modify: `app/services/ramon/fluxos/rotinas/conta.rb` (Write — inteiro), `app/jobs/ramon/{daily_funnel_snapshot,extrato_fechamento,night_copilot,portal_sync,portal_avisos,publicar_pecas}_job.rb`, `app/services/ramon/fluxos/horario_conta.rb` (só comentário)
- Test (modify): `spec/services/ramon/fluxos/rotinas/conta_spec.rb`, `spec/services/ramon/fluxos/horario_conta_spec.rb`, `spec/jobs/ramon/{daily_funnel_snapshot,extrato_fechamento,night_copilot,portal_sync,portal_avisos,publicar_pecas}_job_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Fluxos::HorarioConta.{intervalo,config,reivindicar}`, `Ramon::Fluxos::Migracao.{assumiu?,fluxo}`.
- Produces: `Rotinas::Conta::JOBS = { 'resumo_do_dia' => [...] }`; `Rotinas::Conta::ROTINAS = { 'resumo_do_dia' => 'conta' }`; `GRUPOS = { 'resumo_do_dia' => { env: 'RAMON_FLUXO_ROTINAS', … } }`; os 6 jobs com `perform` sem argumento (o cron de sempre, `config/schedule.yml` não muda); sem `PublicarPecasJob.pendente?`.

- [ ] **Step 1: Specs** (Edit).

`spec/services/ramon/fluxos/rotinas/conta_spec.rb`:
- trocar os 2 primeiros exemplos (`'as 7 rotinas da conta: …'` e `'criar: os 7 nascem em sombra, …'`) por:
```ruby
  it 'só o resumo do dia segue como rotina da conta no fluxo (as outras 6 são regra fixa, 08/10)' do
    expect(todas).to eq(['resumo_do_dia'])
    expect(Ramon::Fluxos::Rotinas.alvo('resumo_do_dia')).to eq('conta')
    expect(Ramon::Fluxos::Migracao.grupo('resumo_do_dia')).to include(env: 'RAMON_FLUXO_ROTINAS', fluxos: { 'resumo_do_dia' => 'horario_conta' })
    expect(Ramon::Fluxos::Rotinas.alvo('publicar_pecas')).to be_nil
  end

  it 'criar: nasce em sombra, ligado, publicado, às 08:00 (o horário do código)' do
    novo = Ramon::Fluxos::Migracao.semear(account, 'resumo_do_dia').sole
    expect(Ramon::Fluxos::Grafo.new(novo.versao_publicada.grafo).gatilho['config'].slice('hora', 'a_cada_minutos')).to eq('hora' => '08:00')
    expect([novo.modo, novo.ativo, novo.gatilho_tipo, novo.limite_dia]).to eq(['sombra', true, 'horario_conta', nil])
  end
```
- apagar os exemplos `it 'rodar: "fila" enfileira o job da conta …'` e `it 'avisos do Painel: com PORTAL_AVISOS desligado …'`;
- dentro de `describe 'cada_conta (o job do código)'`, apagar o exemplo `it 'publicar peças editado para "a cada 5 min", fora do comando: …'`.
(Os demais — `rodar: "agora"…`, `rotina da conta num fluxo de lead não publica`, os 4 de `cada_conta` com o resumo — ficam: provam o caminho do resumo, que não muda.)

`spec/services/ramon/fluxos/horario_conta_spec.rb` — dentro de `describe 'rotina da conta migrada: quem pega a vez faz, nunca os dois'`, apagar os 2 exemplos `it 'publicar peças: sem peça vencida o fluxo nem começa …'` e `it 'publicar peças em sombra: 1 vez por minuto …'`. O helper `def cron(texto, nome = 'resumo_do_dia')` fica (o padrão é o resumo).

Specs dos 6 jobs — apagar o exemplo B5 de cada um:
- `spec/jobs/ramon/daily_funnel_snapshot_job_spec.rb`: `it 'B5: conta com o fluxo no comando fica de fora do cron; com o id, só ela' do … end`
- `spec/jobs/ramon/extrato_fechamento_job_spec.rb`: o mesmo título
- `spec/jobs/ramon/night_copilot_job_spec.rb`: o mesmo título
- `spec/jobs/ramon/portal_sync_job_spec.rb`: o mesmo título (o exemplo `'espelha os clientes convidados; ADVBOX fora do ar num cliente não derruba os outros'` **fica**)
- `spec/jobs/ramon/portal_avisos_job_spec.rb`: `it 'B5: conta com o fluxo no comando fica de fora do cron; com o id, só ela (mesma trava PORTAL_AVISOS)' do … end`
- `spec/jobs/ramon/publicar_pecas_job_spec.rb`: `it 'B5: pendente? só com peça vencida ou presa; fluxo no comando tira a conta do cron; com o id, só ela' do … end` (o exemplo do acervo sai na Task 4)

E acrescentar no fim de `spec/jobs/ramon/daily_funnel_snapshot_job_spec.rb` (antes do `end` final) a trava de que o cron voltou a ser o de sempre:
```ruby
  it 'regra fixa (08/10): o cron roda todas as contas, sem perguntar a fluxo nenhum' do
    outra = create(:account)
    allow(Ramon::FunnelSnapshotService).to receive(:new).and_call_original
    described_class.perform_now
    expect(Ramon::FunnelSnapshotService).to have_received(:new).with(account: outra)
    expect(described_class.instance_method(:perform).arity).to eq(0) # sem "só esta conta": não há fluxo que peça
  end
```

- [ ] **Step 2: `app/services/ramon/fluxos/rotinas/conta.rb`** (Write — arquivo inteiro):

```ruby
# B5-conta (spec §8): o Resumo do dia como "Rotina pronta do hub" no gatilho Horário da conta — chama o MESMO job de hoje,
# só para esta conta (perform(account_id)). Decisão do Eduardo 08/10: é a única rotina da conta que roda no fluxo; as
# outras 6 (retrato do funil, fechamento do extrato, espelho e avisos do Painel, copiloto noturno, publicar peças) são
# regra fixa — ficam no cron de sempre (config/schedule.yml), sem chave.
# :agora roda dentro do passo (o "depois" do fluxo é depois de verdade).
# A chave é a da migração genérica (Migracao junta os GRUPOS daqui): RAMON_FLUXO_ROTINAS=on E o fluxo (origem usuario,
# sistema_chave = resumo_do_dia) ligado, publicado, em modo normal e no Horário da conta.
# Na carga este módulo não cita Ramon::Fluxos::Migracao (ela carrega este arquivo: autoload circular) — só dentro dos métodos.
module Ramon::Fluxos::Rotinas::Conta
  # nome → [job de hoje, :agora | :fila, env da chave, o que faz]
  JOBS = {
    'resumo_do_dia' => ['Ramon::DailyDigestJob', :agora, 'RAMON_FLUXO_ROTINAS', 'o resumo do dia']
  }.freeze
  ROTINAS = JOBS.transform_values { 'conta' }.freeze
  GRUPOS = JOBS.to_h { |nome, (_job, _modo, env, faz)| [nome, { env: env, faz: faz, fluxos: { nome => 'horario_conta' }.freeze }] }.freeze

  module_function

  def rodar(nome, ctx)
    job, modo, _env, faz = JOBS.fetch(nome)
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
    fluxo.nil? || !disputa?(fluxo) || Ramon::Fluxos::HorarioConta.reivindicar(fluxo, agora)
  end

  # O relógio pegou a vez do fluxo migrado. No comando → o fluxo faz; não começou (ocupado — a execução de antes ainda
  # viva —, erro do motor) → o código faz (reserva). Fora do comando → o código faz nesta vez (o cron não a pega mais),
  # se o fluxo tem o ritmo do código (disputa?).
  def decidir(fluxo)
    nome = fluxo.sistema_chave
    no_comando = Ramon::Fluxos::Migracao.assumiu?(fluxo.account, nome)
    return if no_comando && iniciar(fluxo)

    pelo_codigo(fluxo.account, nome) if no_comando || disputa?(fluxo)
  end

  # Ruling F3: fora do comando, o horário do fluxo só vale para o código quando é o ritmo do próprio código — "por dia".
  # Fluxo editado para "a cada N min" em sombra: nem o relógio faz pelo código nem o cron disputa a vez — o cron faz 1 vez no dia.
  def disputa?(fluxo) = Ramon::Fluxos::HorarioConta.intervalo(Ramon::Fluxos::HorarioConta.config(fluxo)).nil?

  def iniciar(fluxo)
    Ramon::Fluxos::Disparo.new(fluxo, fluxo.account, { 'assumido' => true }, nil).iniciar
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: fluxo.account).capture_exception
    nil
  end
end
```
(Saíram: as 6 entradas de `JOBS`, `PENDENTE`, `A_CADA_MINUTO`, `AVISOS_DESLIGADOS` e a linha dos avisos em `rodar`. O ramo `:fila` fica — é o formato do registro, e não mexer no caminho do resumo.)

- [ ] **Step 3: Os 6 jobs voltam ao cron de sempre** (Edit em cada um):

`app/jobs/ramon/daily_funnel_snapshot_job.rb` — trocar o comentário B5 + `def perform(account_id = nil)` + a linha do `cada_conta` por:
```ruby
  # Regra fixa (decisão do Eduardo 08/10): todas as contas, todo dia às 00:05 (config/schedule.yml).
  def perform
    Account.find_each do |account|
```

`app/jobs/ramon/extrato_fechamento_job.rb` — trocar o comentário B5 + `perform` inteiro por:
```ruby
  # Regra fixa (decisão do Eduardo 08/10): todas as contas, todo dia às 00:20 (config/schedule.yml).
  def perform
    mes = Ramon::ExtratoFechamento.hoje.prev_month.beginning_of_month
    return unless Ramon::ExtratoFechamento.fechado?(mes)

    Account.find_each { |account| Ramon::ExtratoFechamento.fechar!(account, mes) }
  end
```

`app/jobs/ramon/night_copilot_job.rb` — trocar o comentário B5 + `def perform(account_id = nil)` + a linha do `cada_conta` por:
```ruby
  # Regra fixa (decisão do Eduardo 08/10): todas as contas, todo dia às 05:00 (config/schedule.yml).
  def perform
    Account.find_each do |account|
```

`app/jobs/ramon/portal_sync_job.rb` — trocar o comentário B5 (2 linhas) + `perform` inteiro por:
```ruby
  # Regra fixa (decisão do Eduardo 08/10): o expurgo dos acessos (Marco Civil) e todas as contas, às 00:30.
  def perform
    PortalAcesso.expurgar!
    Account.find_each { |account| espelhar(account) }
  end
```

`app/jobs/ramon/portal_avisos_job.rb` — trocar `perform` inteiro (com o comentário B5 de dentro) por:
```ruby
  def perform
    return unless ENV['PORTAL_AVISOS'] == 'on'

    Account.find_each { |account| avisar_conta(account) } # regra fixa (08/10): todas as contas, às 08:00
  end
```

`app/jobs/ramon/publicar_pecas_job.rb` — trocar o bloco do comentário `# B5-conta: o Horário da conta só começa …` até o fim de `perform` (os 3 `def self.…` e o `perform`) por:
```ruby
  def perform
    marcar_interrompidas
    Peca.where(status: 'agendado').where(agendado_para: ..Time.current).find_each { |peca| publicar(peca) }
  end
```
e, logo antes de `def interromper(peca)` (na parte `private`), acrescentar:
```ruby
  def marcar_interrompidas
    Peca.where(status: 'publicando').where(publicacao_iniciada_em: ...INTERROMPIDA.ago).find_each { |peca| interromper(peca) }
  end

```
(Isso é exatamente o `perform` e o `marcar_interrompidas` de antes da B5-conta — `git show 75dac9337c^:app/jobs/ramon/publicar_pecas_job.rb`. O `pos_publicacao` muda na Task 4.)

- [ ] **Step 4: `app/services/ramon/fluxos/horario_conta.rb`** — só o comentário das linhas 7–8 (Edit): trocar
```ruby
# O job do código (Ramon::Fluxos::Rotinas::Conta.cada_conta) disputa a MESMA vez do fluxo migrado: quem pega faz.
# Fluxo migrado de uma rotina do código (Rotinas::Conta): no comando o fluxo faz; não começou ou fora do comando, o código faz.
```
por
```ruby
# O job do código (Ramon::Fluxos::Rotinas::Conta.cada_conta — hoje só o Resumo do dia) disputa a MESMA vez do fluxo
# migrado: quem pega faz. No comando o fluxo faz; não começou ou fora do comando, o código faz.
```

- [ ] **Step 5: Conferir**
```bash
cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-fluxos-b5-conta
grep -rn "cada_conta\|pendente?\|PENDENTE\|A_CADA_MINUTO\|AVISOS_DESLIGADOS\|RAMON_FLUXO_\(PUBLICAR_PECAS\|AVISOS_PAINEL\)" app spec --include=*.rb
```
Expected: só `daily_digest_job.rb` (o resumo), `rotinas/conta.rb` (`cada_conta`), `rotinas.rb` (o genérico `pendente`/`PENDENTE` do registro, que fica), `horario_conta.rb` (comentário) e `rotinas_spec.rb`/`horario_conta_spec.rb`/`conta_spec.rb` (resumo e o plano de mentira). Nenhum dos 6 jobs.

- [ ] **Step 6: Commit**
```bash
git add app/services/ramon/fluxos/rotinas/conta.rb app/services/ramon/fluxos/horario_conta.rb app/jobs/ramon spec/services/ramon/fluxos spec/jobs/ramon
git commit -m "refactor(fluxos): 6 rotinas da conta viram regra fixa — voltam ao cron de sempre; só o resumo do dia segue no fluxo" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 4: Fora do funil — assinatura e documento do Painel, contrato no ZapSign, ata e acervo voltam ao código (mecânica)

A **Chegada de cliente** segue no fluxo: `RamonChegadasController`, `Externos.evento`, `Rotinas::Externos#escalar_chegada`, `Chegada#escalar!` e o gatilho `chegada_cliente` não mudam.

**Files:**
- Modify: `app/controllers/public/api/v1/zapsign_webhooks_controller.rb`, `app/controllers/cliente/painel_controller.rb`, `app/controllers/api/v1/accounts/ramon_reunioes_controller.rb`, `app/jobs/ramon/zapsign_lead_status_job.rb`, `app/jobs/ramon/publicar_pecas_job.rb`, `app/models/peca.rb`, `app/models/fluxo_execucao.rb`, `app/services/ramon/fluxos/grafo.rb`, `app/services/ramon/fluxos/externos.rb` (comentário), `app/services/ramon/fluxos/rotinas/externos.rb` (Write — inteiro)
- Test (modify): `spec/services/ramon/fluxos/externos_spec.rb`, `spec/services/ramon/fluxos/rotinas/externos_spec.rb`, `spec/services/ramon/fluxos/disparo_spec.rb`, `spec/models/fluxo_execucao_spec.rb`, `spec/models/peca_spec.rb`, `spec/jobs/ramon/publicar_pecas_job_spec.rb`, `spec/jobs/ramon/zapsign_lead_status_job_spec.rb`, `spec/requests/public/api/v1/zapsign_webhooks_spec.rb`, `spec/requests/cliente/painel_spec.rb`, `spec/requests/api/v1/accounts/ramon_reunioes_spec.rb`

**Interfaces:**
- Consumes: `Ramon::ZapsignLeadStatusJob.avisar(lead, status)` (público, fica), `Peca#espelhar_notion` (público, fica), `Ramon::Fluxos::Disparo.externo(gatilho, alvo, dados = {})`.
- Produces: `Rotinas::Externos::GRUPOS = { 'chegada_cliente' => … }`, `ROTINAS = { 'escalar_chegada' => 'outro' }`; `Externos.gatilhos == ['chegada_cliente']`; `Grafo::GATILHOS` sem `assinatura_painel documento_painel reuniao_gravada peca_publicada peca_mudou_status`; `FluxoExecucao::NOMES_ALVO` só com `'Chegada'`.

- [ ] **Step 1: Specs** (Edit).

Apagar estes exemplos (do `it` até o `end` que o fecha):
- `spec/requests/public/api/v1/zapsign_webhooks_spec.rb`: `it 'fluxo "Assinatura pelo Painel" no comando: o código não enfileira; o fluxo pede a mesma conferência'`
- `spec/requests/cliente/painel_spec.rb`: `it 'fluxo "Documento enviado pelo Painel" no comando: o código não enfileira; o fluxo pede o mesmo job'`
- `spec/requests/api/v1/accounts/ramon_reunioes_spec.rb`: `it 'fluxo "Ata da reunião" no comando: Refazer não enfileira pelo código; o fluxo pede o mesmo job (execução nova)'`
- `spec/models/peca_spec.rb`: `it 'fluxo "Espelho das peças no Notion" no comando: a mudança de status vai pelo fluxo, que pede o mesmo job'`
- `spec/jobs/ramon/publicar_pecas_job_spec.rb`: `it 'fluxos do acervo no comando: o Drive sai pelo fluxo; a rajada de status (publicando → publicado) não perde o Notion'`
- `spec/jobs/ramon/zapsign_lead_status_job_spec.rb`: `it 'fluxo "Contrato assinado no ZapSign" no comando: o selo fica no código; histórico e sino saem pelo fluxo, 1 vez'`
- `spec/services/ramon/fluxos/externos_spec.rb`: `it 'grupo de 2 fluxos (acervo das peças): um desligado na tela devolve os dois pontos ao código'`
- `spec/services/ramon/fluxos/disparo_spec.rb`: `it 'assinatura do Painel (B5): a conta vem do cliente do Painel'`
- `spec/services/ramon/fluxos/rotinas/externos_spec.rb`: `it 'os pesados pedem o MESMO job de hoje (fila e novas tentativas do código); o ensaio só descreve'` e o bloco inteiro `describe 'aviso do contrato' do … end`

Ajustar:
- `spec/services/ramon/fluxos/externos_spec.rb`, título do 1º exemplo: `'criar = os 8 fluxos dos 6 grupos, …'` → `'criar = o fluxo da chegada (o único de fora do funil no fluxo, 08/10), em sombra, ligado e publicado'` (o corpo, genérico sobre `grupos`, não muda).
- `spec/services/ramon/fluxos/rotinas/externos_spec.rb`, no último exemplo (`'o passo Rotina pronta acha estas rotinas no registro …'`), trocar a linha `expect(Ramon::Fluxos::Rotinas.alvo('aviso_contrato')).to eq('lead')` por `expect(Ramon::Fluxos::Rotinas.alvo('aviso_contrato')).to be_nil # regra fixa (08/10)`.
- `spec/jobs/ramon/zapsign_lead_status_job_spec.rb`, no exemplo `'assinado: …'` trocar as 3 linhas
```ruby
    expect(Ramon::Fluxos::Disparo).to have_received(:externo)
      .with('contrato_assinado', lead, { 'assumido' => false, 'migracao' => 'contrato_zapsign' })
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('contrato_assinado', lead, {})
```
por
```ruby
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('contrato_assinado', lead).once # só os fluxos comuns
```
e no exemplo `'recusado: …'` as 3 linhas equivalentes por
```ruby
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('contrato_recusado', lead).once
```
- `spec/models/fluxo_execucao_spec.rb`, trocar o exemplo `it 'a execução de um alvo de fora do funil diz o que ele é, sem lead nem conversa' do … end` por:
```ruby
  it 'a execução da chegada de cliente diz o que ela é, sem lead nem conversa' do
    recepcao = create(:user, account: account)
    chegada = account.chegadas.create!(criado_por: recepcao, destinatario: recepcao, cliente_nome: 'Maria')
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'chegada_cliente' }))
    execucao = fluxo.execucoes.create!(account: account, alvo: chegada, ensaio: true)
    expect(execucao.resumo_json).to include(alvo_nome: 'Chegada: Maria', lead_id: nil, conversation_display_id: nil)
    expect(described_class::NOMES_ALVO.keys).to eq(['Chegada'])
  end
```
- `spec/services/ramon/fluxos/grafo_spec.rb`: acrescentar no fim (antes do `end` final):
```ruby
  it 'regra fixa (08/10): os 5 gatilhos de fora do funil que só serviam à migração não existem mais' do
    %w[assinatura_painel documento_painel reuniao_gravada peca_publicada peca_mudou_status].each do |tipo|
      expect(described_class.new(grafo_linear({ 'tipo' => tipo })).erros).to eq(["Gatilho desconhecido: #{tipo}"])
    end
    expect(described_class::GATILHOS).to include('chegada_cliente', 'contrato_assinado', 'contrato_recusado', 'nota_escrita')
  end
```

- [ ] **Step 2: Controllers** (Edit):

`app/controllers/public/api/v1/zapsign_webhooks_controller.rb` — trocar `conferir(assinatura) if assinatura` por `Ramon::ZapsignStatusJob.perform_later(assinatura.id) if assinatura` e apagar o método privado `conferir` com o comentário B5 acima dele (3 linhas + linha em branco).

`app/controllers/cliente/painel_controller.rb` — trocar
```ruby
    # B5: pelo código (como sempre) ou pelo fluxo "Documento enviado pelo Painel" (RAMON_FLUXO_DOCUMENTO_PAINEL).
    Ramon::Fluxos::Externos.evento('documento_painel', 'documento_painel', envio) { Ramon::PortalEnvioJob.perform_later(envio.id) }
```
por
```ruby
    Ramon::PortalEnvioJob.perform_later(envio.id)
```

`app/controllers/api/v1/accounts/ramon_reunioes_controller.rb` — trocar `pedir_ata(reuniao, 'gravada')` por `Ramon::ReuniaoAtaJob.perform_later(reuniao.id)`, `pedir_ata(@reuniao, 'refazer')` por `Ramon::ReuniaoAtaJob.perform_later(@reuniao.id)` e apagar o método privado `pedir_ata` com o comentário B5 acima dele (6 linhas + linha em branco).

- [ ] **Step 3: Jobs e modelos** (Edit):

`app/jobs/ramon/zapsign_lead_status_job.rb`:
- comentário do topo: trocar `# Histórico e sino: pelo código ou pelo fluxo (B5).` por `# Regra fixa (decisão do Eduardo 08/10): selo, histórico e sino sempre aqui; os fluxos comuns ouvem Contrato assinado/recusado.`
- trocar as 3 linhas
```ruby
    # B5: o selo acima é o evento em si (e a trava contra repetir). Histórico e sino: pelo código ou pelo fluxo
    # "Contrato assinado/recusado no ZapSign" (RAMON_FLUXO_CONTRATO_ZAPSIGN); os fluxos comuns do gatilho, como sempre.
    Ramon::Fluxos::Externos.evento('contrato_zapsign', gatilho, lead) { self.class.avisar(lead, doc['status']) }
```
por
```ruby
    self.class.avisar(lead, doc['status'])
    Ramon::Fluxos::Disparo.externo(gatilho, lead)
```
- comentário de `self.avisar`: `# Público (B5): a rotina "aviso_contrato" do fluxo chama o mesmo — histórico + sino para todos da conta.` → `# Histórico + sino para todos da conta.`

`app/jobs/ramon/publicar_pecas_job.rb` — em `pos_publicacao`, trocar
```ruby
    # B5: pelo código (como sempre) ou pelo fluxo "Acervo das peças no Drive" (RAMON_FLUXO_ACERVO_PECAS).
    Ramon::Fluxos::Externos.evento('acervo_pecas', 'peca_publicada', peca) { Ramon::ConteudoDriveJob.perform_later(peca.id) }
```
por
```ruby
    Ramon::ConteudoDriveJob.perform_later(peca.id)
```

`app/models/peca.rb` — trocar
```ruby
  # Público (B5): o PublicarPecasJob chama depois de update_columns (que pula o callback). Pelo código (como sempre) ou
  # pelo fluxo "Espelho das peças no Notion" (RAMON_FLUXO_ACERVO_PECAS); {evento} = o status novo.
  def espelhar_notion
    Ramon::Fluxos::Externos.evento('acervo_pecas', 'peca_mudou_status', self, 'evento' => status) { Ramon::NotionEspelhoJob.perform_later(id) }
  end
```
por
```ruby
  # Público: o PublicarPecasJob chama depois de update_columns (que pula o callback).
  def espelhar_notion = Ramon::NotionEspelhoJob.perform_later(id)
```

`app/models/fluxo_execucao.rb` — trocar o `NOMES_ALVO` (o comentário + o hash de 5 linhas) por:
```ruby
  # B5: o alvo de fora do funil (a chegada de cliente) aparece com o que é (a lista e a tela de execução não têm outra coluna).
  NOMES_ALVO = { 'Chegada' => ->(alvo) { "Chegada: #{alvo.cliente_nome}" } }.freeze
```

- [ ] **Step 4: Motor** (Edit):

`app/services/ramon/fluxos/grafo.rb` — em `GATILHOS`, trocar a linha
```ruby
                assinatura_painel documento_painel chegada_cliente reuniao_gravada peca_publicada peca_mudou_status].freeze
```
por
```ruby
                chegada_cliente].freeze
```

`app/services/ramon/fluxos/externos.rb` — trocar as 2 primeiras linhas do comentário
```ruby
# B5 (spec §8): as automações que começam FORA do funil — webhook do ZapSign, Painel do Cliente, recepção, gravação de
# reunião, peças do Instagram — cada uma com a chave da B4.1 (env própria + os fluxos do grupo em modo normal). Os 6
# grupos moram em Ramon::Fluxos::Rotinas::Externos::GRUPOS (o registro os junta em Migracao::GRUPOS).
```
por
```ruby
# B5 (spec §8): a automação que começa FORA do funil e roda no fluxo — a chegada de cliente (recepção), com a chave da
# B4.1 (env própria + o fluxo em modo normal). As outras 5 viraram regra fixa (decisão do Eduardo 08/10). O grupo mora em
# Ramon::Fluxos::Rotinas::Externos::GRUPOS (o registro o junta em Migracao::GRUPOS).
```
e, na última linha do comentário, `# O alvo é o registro do evento (PortalAssinatura, PortalEnvio, Chegada, Reuniao, Peca) — só o contrato é do lead.` → `# O alvo é o registro do evento (a Chegada).`

`app/services/ramon/fluxos/rotinas/externos.rb` (Write — arquivo inteiro):
```ruby
# B5-externos: a rotina pronta da chegada de cliente — o MESMO código de hoje (Chegada#escalar!). Decisão do Eduardo
# 08/10: a chegada é a única automação de fora do funil que roda no fluxo; assinatura e documento do Painel, contrato no
# ZapSign, ata da reunião e acervo das peças viraram regra fixa (código, sem chave).
# Contrato do registro Ramon::Fluxos::Rotinas: ROTINAS nome → alvo + rodar(nome, ctx) → String (o resumo da trilha); o
# ensaio só descreve; alvo errado = PassoImpossivel (falha na hora, sem nova tentativa). Na carga este módulo não cita
# Ramon::Fluxos::Migracao (autoload circular).
module Ramon::Fluxos::Rotinas::Externos
  # A migração da chegada (juntada em Migracao::GRUPOS pelo registro); quem decide cada evento é Ramon::Fluxos::Externos.evento.
  GRUPOS = {
    'chegada_cliente' => { env: 'RAMON_FLUXO_CHEGADA', faz: 'a escalada da chegada de cliente',
                           fluxos: { 'chegada_cliente' => 'chegada_cliente' }.freeze }
  }.freeze
  # 'outro' = o alvo é o registro do evento (a chegada), não lead nem conversa.
  ROTINAS = { 'escalar_chegada' => 'outro' }.freeze
  ALVOS = { 'Chegada' => 'uma chegada de cliente' }.freeze

  module_function

  def rodar(nome, ctx) = public_send(nome, ctx)

  def escalar_chegada(ctx)
    chegada = alvo!(ctx, Chegada)
    return 'chegada já respondida (ou já escalada): não escala' unless chegada.escalavel?
    return 'faria: escalar — o alerta volta a tocar na tela de quem avisou' if ctx.ensaio?

    chegada.escalar!
    'escalou: o alerta voltou a tocar na tela de quem avisou'
  end

  def alvo!(ctx, classe)
    alvo = ctx.execucao.alvo
    return alvo if alvo.is_a?(classe)

    raise Ramon::Fluxos::PassoImpossivel, "esta rotina só roda com #{ALVOS.fetch(classe.name)} (o Testar com um lead não serve aqui)"
  end
end
```

- [ ] **Step 5: Conferir**
```bash
cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-fluxos-b5-conta
grep -rn "Externos.evento\|Migracao.decidir\|cada_conta(" app --include=*.rb
grep -rn "assinatura_painel\|documento_painel\|reuniao_gravada\|peca_publicada\|peca_mudou_status\|acervo_pecas\|contrato_zapsign\|ata_reuniao\|aviso_contrato\|escrever_ata\|acervo_drive\|espelho_notion\|conferir_assinatura\|processar_envio" app spec --include=*.rb
```
Expected (1º grep): `ramon_lead_listener.rb` (sla), `ramon_chegadas_controller.rb` (chegada), `externos.rb` (a definição), `migracao.rb` (a definição), `daily_digest_job.rb` (resumo), `rotinas/conta.rb`. (2º grep): só `spec/services/ramon/fluxos/migracao_spec.rb` (a lista `fixas`), `spec/services/ramon/fluxos/grafo_spec.rb` (a lista dos 5) e `app/services/ramon/fluxos/sistema.rb`/`spec/services/ramon/fluxos/sistema_spec.rb` (as chaves dos desenhos do sistema, que ficam).

- [ ] **Step 6: Commit**
```bash
git add app/controllers app/jobs/ramon app/models/peca.rb app/models/fluxo_execucao.rb app/services/ramon/fluxos spec
git commit -m "refactor(fluxos): assinatura e documento do Painel, contrato no ZapSign, ata e acervo viram regra fixa; 5 gatilhos saem" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 5: O que sobrou dos andaimes — 18 desenhos migrados, envs, editor e textos (mecânica)

**Files:**
- Delete: 18 arquivos em `db/seeds/ramon/fluxos/migrados/`: `acervo_pecas_drive.json`, `acervo_pecas_notion.json`, `agente_hub.json`, `assinatura_painel.json`, `ata_reuniao.json`, `avisos_painel.json`, `coach_objecao.json`, `contrato_zapsign_assinado.json`, `contrato_zapsign_recusado.json`, `copiloto_noturno.json`, `criar_lead_da_conversa.json`, `documento_painel.json`, `espelho_painel.json`, `fechamento_extrato.json`, `origem_do_lead.json`, `publicar_pecas.json`, `retrato_funil.json`, `sugestao_documento.json`; `app/javascript/dashboard/routes/dashboard/captain/automacoes/rotinas/leads.js`
- Modify: `.env.example`, `app/javascript/dashboard/routes/dashboard/captain/automacoes/{fluxo.js,rotinas/conta.js,rotinas/externos.js}`, `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json`
- Test (modify): `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/{migrados,fluxo,PainelPasso}.spec.js`

**Interfaces:**
- Consumes: a pasta `migrados/` só é lida por `Migracao.criar` (Ruby) e pelo `migrados.spec.js` (front) — nenhum grupo restante aponta para os 18.
- Produces: `rotinasPara('conta') == ['resumo_do_dia']`; `rotinasPara('lead')` termina em `'escalar_chegada'`; `GATILHOS` (front) sem os 5 de fora do funil.

- [ ] **Step 1: Apagar os 18 desenhos migrados e o `rotinas/leads.js`**
```bash
cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-fluxos-b5-conta/db/seeds/ramon/fluxos/migrados
git rm -q acervo_pecas_drive.json acervo_pecas_notion.json agente_hub.json assinatura_painel.json ata_reuniao.json avisos_painel.json coach_objecao.json contrato_zapsign_assinado.json contrato_zapsign_recusado.json copiloto_noturno.json criar_lead_da_conversa.json documento_painel.json espelho_painel.json fechamento_extrato.json origem_do_lead.json publicar_pecas.json retrato_funil.json sugestao_documento.json
ls
cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-fluxos-b5-conta
git rm -q app/javascript/dashboard/routes/dashboard/captain/automacoes/rotinas/leads.js
```
Expected do `ls`: `cadencia.json chegada_cliente.json eventos_advbox.json lead_ganho.json lembretes_reuniao.json resumo_do_dia.json reuniao_cancelada.json reuniao_marcada.json sla_primeira_resposta.json` (9).

- [ ] **Step 2: `.env.example`** (Edit) — trocar o trecho do fim do arquivo que vai de `# ramon: rotinas da conta pelos fluxos (B5). on + o fluxo da rotina em modo normal = o fluxo faz (gatilho Horario da conta)` até a última linha `# RAMON_FLUXO_ACERVO_PECAS=off` (5 blocos: rotinas, publicar peças, avisos, leads, externos) por:
```
# ramon: resumo do dia pelo fluxo (B5). on + o fluxo "Resumo do dia" em modo normal = o fluxo faz (gatilho Horario da conta)
# e o cron do codigo pula a conta. As outras rotinas da conta sao regra fixa (decisao 08/10, sem chave).
# Virar/voltar: rake ramon:fluxos:migracao:modo[resumo_do_dia,conta,normal|sombra]
# RAMON_FLUXO_ROTINAS=off

# ramon: chegada de cliente pelo fluxo (B5-externos). on + o fluxo "Chegada de cliente" em modo normal = o fluxo escala e
# o codigo para. As outras automacoes de fora do funil sao regra fixa (decisao 08/10, sem chave).
# Virar/voltar: rake ramon:fluxos:migracao:modo[chegada_cliente,conta,normal|sombra]
# RAMON_FLUXO_CHEGADA=off
```

- [ ] **Step 3: Editor** (Edit):

`automacoes/fluxo.js`, em `GATILHOS`, trocar as 7 linhas do comentário `// B5-externos: …` até `{ tipo: 'peca_mudou_status', … },` por:
```js
  // B5-externos: o alvo é o registro do evento (a chegada), não lead nem conversa (o "Testar com um lead" não serve)
  { tipo: 'chegada_cliente', icone: 'i-lucide-door-open', alvo: 'outro' },
```

`automacoes/rotinas/conta.js` (Write — inteiro):
```js
// B5-conta: = Ramon::Fluxos::Rotinas::Conta::ROTINAS (só o resumo do dia; as outras 6 são regra fixa desde 08/10).
export default [{ chave: 'resumo_do_dia', alvo: 'conta' }];
```

`automacoes/rotinas/externos.js` (Write — inteiro):
```js
// B5-externos: = Ramon::Fluxos::Rotinas::Externos::ROTINAS (só a chegada; as outras 5 são regra fixa desde 08/10).
export default [{ chave: 'escalar_chegada', alvo: 'outro' }];
```

- [ ] **Step 4: Textos** (Edit) — em `i18n/locale/pt_BR/ramon.json` **e** `i18n/locale/en/ramon.json`, dentro de `CAPTAIN_RAMON.FLUXOS`:
- `GATILHOS`: apagar as chaves `assinatura_painel`, `documento_painel`, `reuniao_gravada`, `peca_publicada`, `peca_mudou_status` (fica `chegada_cliente` como a última — sem vírgula no fim);
- `ROTINAS` **e** `ROTINAS_AJUDA`: apagar as 17 chaves `retrato_funil`, `fechamento_extrato`, `espelho_painel`, `copiloto_noturno`, `publicar_pecas`, `avisos_painel`, `criar_lead`, `origem_do_lead`, `sugestao_documento`, `coach_objecao`, `agente_hub`, `conferir_assinatura_painel`, `aviso_contrato`, `processar_envio_painel`, `escrever_ata`, `acervo_drive`, `espelho_notion` (ficam as 5 da B4.4, `resumo_do_dia` e `escalar_chegada` — esta como a última, sem vírgula).
Conferir que os 2 arquivos continuam JSON válido:
```bash
cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-fluxos-b5-conta
node -e "for (const l of ['en','pt_BR']) { const j = require('./app/javascript/dashboard/i18n/locale/'+l+'/ramon.json').CAPTAIN_RAMON.FLUXOS; console.log(l, Object.keys(j.ROTINAS).length, Object.keys(j.ROTINAS_AJUDA).length, Object.keys(j.GATILHOS).includes('peca_publicada')) }"
```
Expected: `en 7 7 false` e `pt_BR 7 7 false`.

- [ ] **Step 5: Specs do front** (Edit):

`specs/fluxo.spec.js`, no `describe('rotinas prontas (registro por plano, B5)')`, trocar o 1º exemplo inteiro por:
```js
  it('as 5 de lead da B4.4 + a da chegada; da conta, só o resumo do dia (regra fixa, 08/10)', () => {
    expect(rotinasPara('lead')).toEqual([
      'dossie_passagem',
      'pesquisa_nps',
      'pesquisa_nps_exito',
      'abrir_caso_advbox',
      'concluir_tarefas',
      'escalar_chegada',
    ]);
    expect(rotinasPara('conta')).toEqual(['resumo_do_dia']);
    expect(new Set(ROTINAS).size).toBe(ROTINAS.length);
    expect(rotinaAlvo('xyz')).toBeUndefined();
    expect(GATILHOS.filter(g => g.alvo === 'outro').map(g => g.tipo)).toEqual([
      'chegada_cliente',
    ]);
  });
```

`specs/PainelPasso.spec.js`, no exemplo `it('rotina no Horário da conta: só as rotinas da conta', …)`, trocar o `toEqual([...7 nomes...])` por `toEqual(['resumo_do_dia'])`.

`specs/migrados.spec.js`:
- apagar as 18 linhas de `import` dos desenhos apagados (de `retratoFunil` a `acervoNotion`, menos `resumoDoDia` e `chegada`); ficam os imports de `marcada`, `cancelada`, `sla`, `lembretes`, `cadencia`, `ganho`, `eventos`, `resumoDoDia` e `chegada`;
- trocar tudo de `const CONTA = {` até o fim do arquivo por:
```js
// Decisão do Eduardo 08/10: das rotinas da conta, só o resumo do dia segue no fluxo.
describe('fluxo migrado: resumo do dia (B5-conta)', () => {
  it('publica no Horário da conta às 08:00 (o horário do código), com a rotina de mesmo nome', () => {
    expect(validar(resumoDoDia.desenho)).toEqual([]);
    expect(resumoDoDia.desenho.nos.map(n => n.tipo)).toEqual([
      'gatilho',
      'rotina',
    ]);
    expect(resumoDoDia.desenho.nos[0].config).toMatchObject({
      tipo: 'horario_conta',
      hora: '08:00',
    });
    expect(resumoDoDia.desenho.nos[1].config.rotina).toBe('resumo_do_dia');
    expect(rotinaAlvo('resumo_do_dia')).toBe('conta');
  });
});

// Decisão do Eduardo 08/10: de fora do funil, só a chegada de cliente segue no fluxo.
describe('fluxo migrado: chegada de cliente (B5-externos)', () => {
  it('publica, nasce da chegada sem cancelar por etapa, espera 3 minutos e escala', () => {
    expect(validar(chegada.desenho)).toEqual([]);
    expect(chegada.desenho.nos[0].config).toMatchObject({
      tipo: 'chegada_cliente',
      cancelar_se_sair_da_etapa: false,
    });
    expect(chegada.desenho.nos.map(n => n.tipo)).toEqual([
      'gatilho',
      'esperar',
      'rotina',
    ]);
    expect(doTipo(chegada, 'esperar')[0].config).toMatchObject({
      quantidade: 3,
      unidade: 'minutos',
    });
    expect(doTipo(chegada, 'rotina')[0].config.rotina).toBe('escalar_chegada');
    expect(ROTINAS).toContain('escalar_chegada');
  });
});

describe('regra fixa (08/10): sobram só os desenhos das 7 automações no fluxo', () => {
  it('a pasta tem os 9 desenhos (as reuniões são 3)', () => {
    const arquivos = Object.keys(
      import.meta.glob(
        '../../../../../../../../db/seeds/ramon/fluxos/migrados/*.json'
      )
    )
      .map(c => c.split('/').pop().replace('.json', ''))
      .sort();
    expect(arquivos).toEqual([
      'cadencia',
      'chegada_cliente',
      'eventos_advbox',
      'lead_ganho',
      'lembretes_reuniao',
      'resumo_do_dia',
      'reuniao_cancelada',
      'reuniao_marcada',
      'sla_primeira_resposta',
    ]);
  });
});
```

- [ ] **Step 6: Rodar o front**
```bash
cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-fluxos-b5-conta
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes
./node_modules/.bin/eslint --fix app/javascript/dashboard/routes/dashboard/captain/automacoes
./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes
```
Expected: vitest verde (inclui `i18n.spec.js`: en e pt_BR com as mesmas chaves; toda rotina com texto); eslint sem `error`.

- [ ] **Step 7: Commit**
```bash
git add -A db/seeds/ramon/fluxos/migrados .env.example app/javascript/dashboard/routes/dashboard/captain/automacoes app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit -m "chore(fluxos): tira os desenhos, envs, gatilhos e rotinas das 16 regras fixas do editor" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 6: As fichas e o selo "regra fixa" nos 29 desenhos do sistema (mecânica — o texto é do Anexo A)

**Files:**
- Modify: os 29 `db/seeds/ramon/fluxos/sistema/*.json` (por script)
- Create (fora do git): `tmp/fichas.json` (cópia do Anexo A), `tmp/aplicar-fichas.mjs`
- Test (modify): `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/sistema.spec.js`, `spec/services/ramon/fluxos/sistema_spec.rb`

**Interfaces:**
- Produces: em cada `sistema/<chave>.json`, a chave `"ficha"` (antes de `"desenho"`) com `{ o_que_faz: String, quando: String, o_que_mexe: [String], travas: [String], por_que: String, mudar: { pedido: String, arquivos: [String], impacto: String }, fluxos?: [String] }` — `fluxos` (chaves de `migrados/`) **só** nas 7 do fluxo; `"fixa": true` nas 22 regras fixas. `Sistema.extras(...)[:fixa]` já lê o `fixa` (não muda). A Task 7 lê `ficha`.

- [ ] **Step 1: Specs** (Edit).

`specs/sistema.spec.js` (front), trocar o exemplo `it('as 5 regras de dado e as etiquetas são regra fixa (decisão do Eduardo 07/10)', …)` inteiro por:
```js
  it('22 regras fixas; as 7 sem o selo são as que rodam no fluxo (decisão do Eduardo 08/10)', () => {
    expect(
      DESENHOS.filter(([, d]) => !d.fixa)
        .map(([chave]) => chave)
        .sort()
    ).toEqual([
      'cadencia',
      'chegada_cliente',
      'eventos_advbox',
      'lead_ganho',
      'lembretes_reuniao',
      'resumo_do_dia',
      'sla_primeira_resposta',
    ]);
    DESENHOS.forEach(([, d]) => expect([undefined, true]).toContain(d.fixa));
  });

  it.each(DESENHOS)(
    '%s: ficha completa — o que faz, quando, o que mexe, travas, por quê e como mudar',
    (_chave, d) => {
      const f = d.ficha;
      ['o_que_faz', 'quando', 'por_que'].forEach(k =>
        expect(f[k].length).toBeGreaterThan(20)
      );
      expect(f.o_que_mexe.length).toBeGreaterThan(0);
      expect(f.travas.length).toBeGreaterThan(0);
      expect(f.mudar.pedido).toMatch(/Claude|fluxo/);
      expect(f.mudar.arquivos.length).toBeGreaterThan(0);
      expect(f.mudar.impacto.length).toBeGreaterThan(10);
      // só as 7 do fluxo apontam os fluxos de verdade (o botão "Abrir o fluxo")
      expect(Array.isArray(f.fluxos)).toBe(!d.fixa);
    }
  );
```

`spec/services/ramon/fluxos/sistema_spec.rb`:
- no exemplo `'extras: grupo, selo de quem sai para fora e o rótulo do gatilho real'`, trocar `gatilho_rotulo: 'Todo dia às 08:00 (só com PORTAL_AVISOS=on)', fixa: false` por `gatilho_rotulo: 'Todo dia às 08:00 (só com PORTAL_AVISOS=on)', fixa: true`;
- trocar o exemplo `it 'as 5 regras de dado e as etiquetas são "regra fixa" …' do … end` por:
```ruby
  describe 'regra fixa e ficha (decisão do Eduardo 08/10)' do
    let(:no_fluxo) { %w[cadencia chegada_cliente eventos_advbox lead_ganho lembretes_reuniao resumo_do_dia sla_primeira_resposta] }

    it '22 regras fixas; as 7 sem o selo são as que rodam no fluxo' do
      fixas = described_class.desenhos.keys.reject { |chave| described_class.extras(account, chave)[:fixa] }
      expect(fixas).to eq(no_fluxo)
    end

    it 'cada ficha cita só arquivos que existem e, nas 7 do fluxo, só desenhos migrados que existem' do
      described_class.desenhos.each do |chave, d|
        ficha = d['ficha']
        sem_arquivo = ficha.dig('mudar', 'arquivos').reject { |a| Rails.root.join(a).exist? }
        sem_desenho = Array(ficha['fluxos']).reject { |c| Ramon::Fluxos::Migracao::PASTA.join("#{c}.json").exist? }
        expect([chave, sem_arquivo, sem_desenho, ficha.key?('fluxos')]).to eq([chave, [], [], no_fluxo.include?(chave)])
      end
    end
  end
```

- [ ] **Step 2: `tmp/fichas.json`** (Write) — copiar **exatamente** o bloco JSON do **Anexo A** deste plano (o objeto com as 29 chaves).

- [ ] **Step 3: `tmp/aplicar-fichas.mjs`** (Write):
```js
// Aplica as fichas (Anexo A do plano) e o "fixa": true das 16 nos JSON do sistema, sem reformatar o resto do
// arquivo (o desenho tem um nó por linha). Para no 1º problema. Uso: node tmp/aplicar-fichas.mjs
import { readFileSync, writeFileSync } from 'node:fs';

const PASTA = 'db/seeds/ramon/fluxos/sistema';
const FICHAS = JSON.parse(readFileSync('tmp/fichas.json', 'utf8'));
const NOVAS_FIXAS = [
  'criar_lead_da_conversa', 'origem_do_lead', 'sugestao_documento', 'coach_objecao', 'agente_hub', 'retrato_funil',
  'fechamento_extrato', 'espelho_painel', 'copiloto_noturno', 'publicar_pecas', 'avisos_painel', 'assinatura_painel',
  'contrato_zapsign', 'documento_painel', 'ata_reuniao', 'acervo_pecas',
];
// A descrição técnica (o "Como roda no código") deixa de falar da migração e corrige 3 frases que o código desmente.
const CORRECOES = [
  [/ \(decide: o código ou o fluxo migrado "[^"]+"\)/, ''],
  [/; decide: o código ou o fluxo migrado "[^"]+"/, ''],
  ['também logo depois do envio do contrato (Ramon::ZapsignContractService)',
    'também no "Gerar de novo", quando o documento anterior já estava assinado (Ramon::ZapsignContractService)'],
  ['no máximo 1 vez a cada 10 min por conversa', 'no máximo 1 vez a cada 10 min por lead (a janela começa mesmo sem objeção)'],
  ['(etapa, responsável, valor, motivo de perda…)', '(etapa, SDR, Closer, prioridade, tese, valor)'],
];
const falha = msg => { throw new Error(msg); };

if (Object.keys(FICHAS).length !== 29) falha('o Anexo A tem de ter 29 fichas');
for (const [chave, ficha] of Object.entries(FICHAS)) {
  const arquivo = `${PASTA}/${chave}.json`;
  let src = readFileSync(arquivo, 'utf8');
  const antes = JSON.parse(src);
  if (src.includes('\r\n') || antes.ficha) falha(`${chave}: CRLF ou ficha já aplicada`);
  if (NOVAS_FIXAS.includes(chave)) {
    if (antes.fixa) falha(`${chave}: já era fixa`);
    src = src.replace(/^( {2}"grupo": "[^"]+",\n)/m, '$1  "fixa": true,\n');
  }
  // as 7 do fluxo (sem "fixa") não mudam a descrição: a limpeza E7 delas é outro PR
  const fixa = NOVAS_FIXAS.includes(chave) || antes.fixa;
  const descricao = fixa ? CORRECOES.reduce((t, [de, para]) => t.replace(de, para), antes.descricao) : antes.descricao;
  if (descricao !== antes.descricao) src = src.replace(JSON.stringify(antes.descricao), JSON.stringify(descricao));
  const bloco = JSON.stringify(ficha, null, 2).replace(/\n/g, '\n  ');
  src = src.replace('\n  "desenho":', `\n  "ficha": ${bloco},\n  "desenho":`);
  const depois = JSON.parse(src);
  const fixaOk = NOVAS_FIXAS.includes(chave) ? depois.fixa === true : depois.fixa === antes.fixa;
  if (!depois.ficha || !fixaOk || depois.descricao !== descricao) falha(`${chave}: não aplicou`);
  if (JSON.stringify(depois.desenho) !== JSON.stringify(antes.desenho)) falha(`${chave}: mexeu no desenho`);
  writeFileSync(arquivo, src);
}
console.log('ok: 29 fichas, 16 regras fixas novas');
```

- [ ] **Step 4: Aplicar e conferir**
```bash
cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-fluxos-b5-conta
node tmp/aplicar-fichas.mjs
git diff --stat db/seeds/ramon/fluxos/sistema | tail -1
grep -c '"fixa": true' db/seeds/ramon/fluxos/sistema/*.json | grep -c ":1$"
grep -l "decide: o código" db/seeds/ramon/fluxos/sistema/*.json
```
Expected: `ok: 29 fichas, 16 regras fixas novas`; 29 arquivos mudados; `22`; o último grep lista só `eventos_advbox.json` e `lead_ganho.json` (do fluxo) — esses não mudam aqui (a limpeza E7 deles é outro PR). Abrir 2 arquivos (`agente_hub.json`, `cadencia.json`) e conferir a indentação da ficha (2 espaços a mais que o nível de cima).

- [ ] **Step 5: Rodar o front**
```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/sistema.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/migrados.spec.js
```
Expected: verde (os 29 com ficha completa; 22 fixas).

- [ ] **Step 6: Commit**
```bash
git add db/seeds/ramon/fluxos/sistema app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/sistema.spec.js spec/services/ramon/fluxos/sistema_spec.rb
git commit -m "feat(fluxos): ficha das 29 automações do sistema e o selo regra fixa nas 22 que ficam no código" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 7: A ficha pela API — `Sistema.ficha` e o `show` (mecânica)

**Files:**
- Modify: `app/services/ramon/fluxos/sistema.rb`, `app/controllers/api/v1/accounts/ramon_fluxos_controller.rb`
- Test (modify): `spec/services/ramon/fluxos/sistema_spec.rb`, `spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb`

**Interfaces:**
- Consumes: `Sistema.desenhos[chave]['ficha']` (Task 6).
- Produces: `Ramon::Fluxos::Sistema.ficha(account, chave) → Hash | nil` — o objeto do JSON com `'fluxos' => [{ 'id' => Integer, 'nome' => String, 'modo' => 'normal'|'sombra', 'ativo' => Boolean }]` (os fluxos `origem: usuario` da conta com aquelas `sistema_chave`, por id; `[]` nas regras fixas e quando o fluxo não foi criado). `GET /ramon_fluxos/:id` passa a trazer `ficha` (o `index` não traz). A Task 8 lê `fluxo.ficha` e `fluxo.fixa`.

- [ ] **Step 1: Specs**

`spec/services/ramon/fluxos/sistema_spec.rb` — acrescentar no fim (antes do `end` final):
```ruby
  it 'ficha: o texto do JSON; nas do fluxo, os fluxos de verdade da conta no lugar das chaves' do
    expect(described_class.ficha(account, 'contrato_limpo')).to include('o_que_faz' => be_present, 'fluxos' => [])
    expect(described_class.ficha(account, 'lembretes_reuniao')['fluxos']).to eq([]) # ainda não criados nesta conta
    marcada = fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' }), sistema_chave: 'reuniao_marcada')
    lembretes = fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' }), sistema_chave: 'lembretes_reuniao', ativo: false)
    expect(described_class.ficha(account, 'lembretes_reuniao')['fluxos']).to eq(
      [{ 'id' => marcada.id, 'nome' => 'Fluxo de teste', 'modo' => marcada.modo, 'ativo' => true },
       { 'id' => lembretes.id, 'nome' => 'Fluxo de teste', 'modo' => lembretes.modo, 'ativo' => false }]
    )
    expect(described_class.ficha(account, 'xyz')).to be_nil
  end
```

`spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb` — acrescentar no fim (antes do `end` final):
```ruby
  it 'o desenho do sistema aberto traz a ficha (a lista não); a do fluxo aponta o fluxo de verdade (decisão 08/10)' do
    get url, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].filter_map { |f| f['ficha'] }).to eq([])
    do_sistema = ->(chave) { account.fluxos.find_by!(origem: 'sistema', sistema_chave: chave) }

    get "#{url}/#{do_sistema.call('contrato_limpo').id}", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('fixa' => true, 'ficha' => include('travas' => be_present, 'fluxos' => []))

    proprio = fluxo_publicado(account, grafo, sistema_chave: 'lead_ganho', modo: 'normal')
    get "#{url}/#{do_sistema.call('lead_ganho').id}", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['ficha']['fluxos']).to eq([{ 'id' => proprio.id, 'nome' => 'Fluxo de teste', 'modo' => 'normal', 'ativo' => true }])

    get "#{url}/#{proprio.id}", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['ficha']).to be_nil
  end
```

- [ ] **Step 2: `app/services/ramon/fluxos/sistema.rb`** (Edit):
- no comentário do topo, trocar `# ({nome, grupo, alcance?, fixa?, descricao, limite_dia?, desenho}).` por `# ({nome, grupo, alcance?, fixa?, descricao, resumo, ficha, limite_dia?, desenho}).`
- logo depois do método `extras` (antes de `def em_dia?`), acrescentar:
```ruby
  # Decisão do Eduardo (08/10): a ficha de cada automação (texto do JSON, PT-BR) — só no desenho aberto. Nas 7 que rodam
  # no fluxo, 'fluxos' (chaves de migrados/) vira os fluxos de verdade da conta: o botão "Abrir o fluxo". Fixa: [].
  def ficha(account, chave)
    ficha = desenhos.dig(chave, 'ficha')
    return if ficha.nil?

    reais = account.fluxos.where(origem: 'usuario', sistema_chave: Array(ficha['fluxos'])).order(:id)
    ficha.merge('fluxos' => reais.map { |f| { 'id' => f.id, 'nome' => f.nome, 'modo' => f.modo, 'ativo' => f.ativo } })
  end
```

- [ ] **Step 3: `app/controllers/api/v1/accounts/ramon_fluxos_controller.rb`** (Edit) — trocar o `show` por:
```ruby
  def show
    render json: item(@fluxo).merge(rascunho: @fluxo.rascunho, ficha: ficha,
                                    versoes: @fluxo.versoes.order(numero: :desc).map { |v| { numero: v.numero, created_at: v.created_at } })
  end
```
e, no fim da parte `private` (depois de `resumo`), acrescentar:
```ruby
  # Decisão do Eduardo (08/10): a ficha da automação do sistema, só no desenho aberto (a lista não carrega 29 textos).
  def ficha = @fluxo.origem == 'sistema' ? Ramon::Fluxos::Sistema.ficha(Current.account, @fluxo.sistema_chave) : nil
```

- [ ] **Step 4: Conferir** — ler os 2 arquivos: linha ≤ 150, `Sistema` < 100 linhas de módulo (ModuleLength), `show` ≤ 19 linhas.

- [ ] **Step 5: Commit**
```bash
git add app/services/ramon/fluxos/sistema.rb app/controllers/api/v1/accounts/ramon_fluxos_controller.rb spec/services/ramon/fluxos/sistema_spec.rb spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb
git commit -m "feat(fluxos): a API do desenho do sistema traz a ficha e os fluxos de verdade das 7 que rodam no fluxo" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 8: A tela — a ficha no desenho do sistema, "Abrir o fluxo" e o selo "roda no fluxo" (julgamento: layout no print)

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/captain/automacoes/FichaSistema.vue`, `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/FichaSistema.spec.js`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/{Editor.vue,Lista.vue}`, `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json`
- Test (modify): `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/{Editor,Lista}.spec.js`

**Interfaces:**
- Consumes: `fluxo.ficha` e `fluxo.fixa` do `GET /ramon_fluxos/:id` (Task 7); rota `captain_automacoes_editor` com `params.fluxoId`.
- Produces: `<FichaSistema :fluxo="fluxo" />` (prop `fluxo` = o objeto do `show`); `data-testid`: `ficha`, `ficha-selo`, `ficha-o-que-faz`, `ficha-quando`, `ficha-o-que-mexe`, `ficha-travas`, `ficha-por-que`, `ficha-abrir-fluxo` (1 por fluxo), `ficha-sem-fluxo`, `ficha-mudar`, `sistema-descricao` (o `<details>` técnico — o mesmo testid de antes).

- [ ] **Step 1: Textos** (Edit) — em `i18n/locale/pt_BR/ramon.json`, dentro de `CAPTAIN_RAMON.FLUXOS`:
- `SISTEMA.EXPLICA` →
  `"Estas são as 29 automações que o hub faz sozinho. 7 rodam por fluxos seus (selo \"roda no fluxo\"): a ficha tem o botão Abrir o fluxo, para editar. As outras 22 são regra fixa e ficam no código de propósito (decisão de 08/10). Clique em qualquer uma para ver a ficha: o que faz, quando, o que mexe, as travas e como pedir uma mudança."`
- `SISTEMA.FIXA_DICA` → `"Fica no código de propósito (decisão de 08/10). Abra a ficha para ver por quê e como pedir uma mudança."`
- `SELO`: trocar `"NO_CODIGO": "roda no código",` por `"NO_FLUXO": "roda no fluxo",`
- `EDITOR.COMO_RODA` → `"Como roda no código (detalhes técnicos)"`
- acrescentar, depois do bloco `SISTEMA` (como irmão dele), o bloco:
```json
      "FICHA": {
        "SELO_FIXA": "regra fixa · fica no código",
        "SELO_FLUXO": "roda no fluxo",
        "O_QUE_FAZ": "O que faz",
        "QUANDO": "Quando",
        "O_QUE_MEXE": "O que mexe",
        "TRAVAS": "Travas e garantias",
        "POR_QUE_CODIGO": "Por que fica no código",
        "NO_FLUXO": "No fluxo",
        "ABRIR_FLUXO": "Abrir o fluxo",
        "SEM_FLUXO": "O fluxo ainda não foi criado nesta conta: quem faz é o código.",
        "MODO": { "normal": "no comando", "sombra": "em sombra" },
        "DESLIGADO": "desligado",
        "MUDAR": "Se quiser mudar",
        "ARQUIVOS": "Arquivos principais",
        "IMPACTO": "Impacto"
      },
```
Em `i18n/locale/en/ramon.json`, as mesmas chaves:
- `SISTEMA.EXPLICA` → `"These are the 29 automations the hub runs on its own. 7 run through your flows (\"runs in a flow\" badge): the sheet has an Open the flow button to edit it. The other 22 are fixed rules and stay in code on purpose (decision of 10/08). Click any of them to see its sheet: what it does, when, what it touches, its locks and how to ask for a change."`
- `SISTEMA.FIXA_DICA` → `"Stays in code on purpose (decision of 10/08). Open the sheet to see why and how to ask for a change."`
- `SELO`: `"NO_CODIGO": "runs in code",` → `"NO_FLUXO": "runs in a flow",`
- `EDITOR.COMO_RODA` → `"How it runs in code (technical details)"`
- bloco `FICHA`: `SELO_FIXA` "fixed rule · stays in code", `SELO_FLUXO` "runs in a flow", `O_QUE_FAZ` "What it does", `QUANDO` "When", `O_QUE_MEXE` "What it touches", `TRAVAS` "Locks and guarantees", `POR_QUE_CODIGO` "Why it stays in code", `NO_FLUXO` "In a flow", `ABRIR_FLUXO` "Open the flow", `SEM_FLUXO` "The flow has not been created in this account yet: the code does it.", `MODO` { `normal` "in command", `sombra` "in shadow" }, `DESLIGADO` "off", `MUDAR` "If you want to change it", `ARQUIVOS` "Main files", `IMPACTO` "Impact".

- [ ] **Step 2: Spec do componente** — `specs/FichaSistema.spec.js` (Write):
```js
import { mount } from '@vue/test-utils';
import FichaSistema from '../FichaSistema.vue';

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));

const FICHA = {
  o_que_faz: 'Faz uma coisa.',
  quando: 'Todo dia às 08:00.',
  o_que_mexe: ['Mexe aqui.', 'E ali.'],
  travas: ['Trava 1.', 'Trava 2.', 'Trava 3.'],
  por_que: 'Porque sim.',
  mudar: {
    pedido: 'Peça ao Claude: "mude".',
    arquivos: ['app/x.rb', 'app/y.rb'],
    impacto: 'Muda tudo.',
  },
  fluxos: [],
};
const RouterLink = {
  name: 'RouterLink',
  props: ['to'],
  template: '<a :data-para="JSON.stringify(to)"><slot /></a>',
};
const montar = fluxo =>
  mount(FichaSistema, {
    props: { fluxo: { descricao: 'No código: X', ...fluxo } },
    global: { stubs: { RouterLink } },
  });

describe('FichaSistema', () => {
  it('regra fixa: as 6 seções, o selo da regra fixa e sem botão de fluxo', () => {
    const w = montar({ fixa: true, ficha: FICHA });
    expect(w.get('[data-testid="ficha-selo"]').text()).toBe(
      'fixed rule · stays in code'
    );
    expect(w.get('[data-testid="ficha-o-que-faz"]').text()).toContain(
      'Faz uma coisa.'
    );
    expect(w.get('[data-testid="ficha-quando"]').text()).toContain('08:00');
    expect(w.findAll('[data-testid="ficha-o-que-mexe"] li')).toHaveLength(2);
    expect(w.findAll('[data-testid="ficha-travas"] li')).toHaveLength(3);
    expect(w.get('[data-testid="ficha-por-que"]').text()).toContain(
      'Why it stays in code'
    );
    expect(w.find('[data-testid="ficha-abrir-fluxo"]').exists()).toBe(false);
    expect(w.find('[data-testid="ficha-sem-fluxo"]').exists()).toBe(false);
    const mudar = w.get('[data-testid="ficha-mudar"]').text();
    ['Peça ao Claude', 'app/x.rb', 'app/y.rb', 'Muda tudo.'].forEach(t =>
      expect(mudar).toContain(t)
    );
    expect(w.get('[data-testid="sistema-descricao"]').text()).toContain(
      'No código: X'
    );
  });

  it('no fluxo: um botão por fluxo de verdade, com o modo; sem fluxo criado, avisa', () => {
    const fluxos = [
      { id: 7, nome: 'Reunião marcada', modo: 'normal', ativo: true },
      { id: 9, nome: 'Lembretes de reunião', modo: 'sombra', ativo: false },
    ];
    const w = montar({ fixa: false, ficha: { ...FICHA, fluxos } });
    expect(w.get('[data-testid="ficha-selo"]').text()).toBe('runs in a flow');
    expect(w.get('[data-testid="ficha-por-que"]').text()).toContain(
      'In a flow'
    );
    const botoes = w.findAll('[data-testid="ficha-abrir-fluxo"]');
    expect(botoes.map(b => JSON.parse(b.attributes('data-para')))).toEqual([
      { name: 'captain_automacoes_editor', params: { fluxoId: 7 } },
      { name: 'captain_automacoes_editor', params: { fluxoId: 9 } },
    ]);
    expect(botoes[0].text()).toContain('Reunião marcada');
    expect(botoes[0].text()).toContain('in command');
    expect(botoes[1].text()).toContain('off');

    const vazio = montar({ fixa: false, ficha: FICHA });
    expect(vazio.find('[data-testid="ficha-sem-fluxo"]').exists()).toBe(true);
  });

  it('sem ficha (desenho antigo): só os detalhes técnicos', () => {
    const w = montar({ fixa: false, ficha: null });
    expect(w.find('[data-testid="ficha-o-que-faz"]').exists()).toBe(false);
    expect(w.get('[data-testid="sistema-descricao"]').text()).toContain(
      'No código: X'
    );
  });
});
```

- [ ] **Step 3: Rodar e ver falhar** — `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/FichaSistema.spec.js` → FAIL (`Failed to resolve import "../FichaSistema.vue"`).

- [ ] **Step 4: `FichaSistema.vue`** (Write):
```vue
<script setup>
// Ficha da automação do sistema (decisão do Eduardo 08/10): o que faz, quando, o que mexe, travas, por que fica no
// código (regra fixa) ou no fluxo — com o botão para o fluxo de verdade — e como mudar. O texto vem do JSON
// (db/seeds/ramon/fluxos/sistema/<chave>.json → "ficha", em PT-BR); aqui só os títulos são i18n.
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import {
  AVISO,
  CARTAO,
  CARTAO_STATUS,
  CHIP,
  FILETE,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

defineProps({ fluxo: { type: Object, required: true } });

const K = 'CAPTAIN_RAMON.FLUXOS.FICHA';
const { t } = useI18n();
const { accountScopedRoute } = useAccount();
const tomDoFluxo = f => {
  if (!f.ativo) return TOM.slate;
  return f.modo === 'normal' ? TOM.teal : TOM.amber;
};
</script>

<template>
  <div
    data-testid="ficha"
    class="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto px-4 py-3.5"
  >
    <template v-if="fluxo.ficha">
      <span
        data-testid="ficha-selo"
        :class="[CHIP, fluxo.fixa ? TOM.slate : TOM.teal]"
        class="self-start font-mono"
      >
        {{ fluxo.fixa ? t(`${K}.SELO_FIXA`) : t(`${K}.SELO_FLUXO`) }}
      </span>

      <section data-testid="ficha-o-que-faz">
        <h4 :class="TITULO" class="mb-1">{{ t(`${K}.O_QUE_FAZ`) }}</h4>
        <p class="text-[13.5px] leading-relaxed text-n-slate-12">
          {{ fluxo.ficha.o_que_faz }}
        </p>
      </section>

      <section
        data-testid="ficha-quando"
        :class="[CARTAO_STATUS, FILETE.blue]"
      >
        <h4 :class="TITULO" class="mb-1 flex items-center gap-1">
          <i class="i-lucide-clock size-3" />{{ t(`${K}.QUANDO`) }}
        </h4>
        <p class="text-[13px] leading-relaxed text-n-slate-12">
          {{ fluxo.ficha.quando }}
        </p>
      </section>

      <section
        data-testid="ficha-o-que-mexe"
        :class="[CARTAO_STATUS, FILETE.blue]"
      >
        <h4 :class="TITULO" class="mb-1 flex items-center gap-1">
          <i class="i-lucide-database size-3" />{{ t(`${K}.O_QUE_MEXE`) }}
        </h4>
        <ul class="list-disc space-y-1 pl-4 text-[13px] text-n-slate-12">
          <li v-for="item in fluxo.ficha.o_que_mexe" :key="item">
            {{ item }}
          </li>
        </ul>
      </section>

      <section
        data-testid="ficha-travas"
        :class="[CARTAO_STATUS, FILETE.amber]"
      >
        <h4 :class="TITULO" class="mb-1 flex items-center gap-1">
          <i class="i-lucide-shield-check size-3" />{{ t(`${K}.TRAVAS`) }}
        </h4>
        <ul class="list-disc space-y-1 pl-4 text-[13px] text-n-slate-12">
          <li v-for="item in fluxo.ficha.travas" :key="item">{{ item }}</li>
        </ul>
      </section>

      <section
        data-testid="ficha-por-que"
        :class="[AVISO, fluxo.fixa ? TOM.slate : TOM.teal]"
        class="!text-[13px] leading-relaxed"
      >
        <b class="mb-1 block">
          {{ fluxo.fixa ? t(`${K}.POR_QUE_CODIGO`) : t(`${K}.NO_FLUXO`) }}
        </b>
        <p>{{ fluxo.ficha.por_que }}</p>
        <div v-if="!fluxo.fixa" class="mt-2 flex flex-wrap gap-1.5">
          <router-link
            v-for="f in fluxo.ficha.fluxos"
            :key="f.id"
            data-testid="ficha-abrir-fluxo"
            :to="accountScopedRoute('captain_automacoes_editor', { fluxoId: f.id })"
            :class="[CHIP, tomDoFluxo(f)]"
            class="hover:underline"
          >
            <i class="i-lucide-workflow size-3" />
            {{ t(`${K}.ABRIR_FLUXO`) }}: {{ f.nome }} ·
            {{ f.ativo ? t(`${K}.MODO.${f.modo}`) : t(`${K}.DESLIGADO`) }}
          </router-link>
          <span
            v-if="!fluxo.ficha.fluxos.length"
            data-testid="ficha-sem-fluxo"
            class="text-xs"
          >
            {{ t(`${K}.SEM_FLUXO`) }}
          </span>
        </div>
      </section>

      <section data-testid="ficha-mudar" :class="CARTAO">
        <h4 :class="TITULO" class="mb-1.5 flex items-center gap-1">
          <i class="i-lucide-message-square-text size-3" />
          {{ t(`${K}.MUDAR`) }}
        </h4>
        <p :class="[AVISO, TOM.blue]" class="!text-[13px] leading-relaxed">
          {{ fluxo.ficha.mudar.pedido }}
        </p>
        <h5 :class="TITULO" class="mb-1 mt-2.5">{{ t(`${K}.ARQUIVOS`) }}</h5>
        <ul class="space-y-0.5 font-mono text-[11.5px] text-n-slate-11">
          <li
            v-for="arquivo in fluxo.ficha.mudar.arquivos"
            :key="arquivo"
            class="break-all"
          >
            {{ arquivo }}
          </li>
        </ul>
        <h5 :class="TITULO" class="mb-1 mt-2.5">{{ t(`${K}.IMPACTO`) }}</h5>
        <p class="text-[13px] leading-relaxed text-n-slate-12">
          {{ fluxo.ficha.mudar.impacto }}
        </p>
      </section>
    </template>

    <details
      data-testid="sistema-descricao"
      class="text-[12.5px] text-n-slate-11"
    >
      <summary
        class="cursor-pointer text-[11px] font-medium uppercase tracking-wider text-n-slate-10"
      >
        {{ t('CAPTAIN_RAMON.FLUXOS.EDITOR.COMO_RODA') }}
      </summary>
      <p class="mt-2 whitespace-pre-line leading-relaxed">
        {{ fluxo.descricao }}
      </p>
    </details>
  </div>
</template>
```
(Se o `i18n.spec.js` acusar a chave `FICHA.MODO.*` por ser usada dinamicamente, não muda nada: ela só confere en = pt_BR e a sintaxe.)

- [ ] **Step 5: `Editor.vue`** (Edit):
- imports: depois de `import TestarComLead from './TestarComLead.vue';` acrescentar `import FichaSistema from './FichaSistema.vue';`
- logo depois de `onMounted(() => { … });`, acrescentar:
```js
// "Abrir o fluxo" (ficha do sistema) navega de um editor para outro: a rota é a mesma, o Vue reaproveita a tela.
watch(fluxoId, () => {
  selecionado.value = null;
  abrirFluxo();
});
```
- no cabeçalho, logo depois do `<span v-if="somenteLeitura && fluxo.fixa" data-testid="sistema-fixa" …>…</span>`, acrescentar:
```vue
        <span
          v-else-if="somenteLeitura"
          data-testid="sistema-no-fluxo"
          :class="[CHIP, TOM.teal]"
          class="shrink-0 font-mono"
        >
          {{ t(`${K}.SELO.NO_FLUXO`) }}
        </span>
```
- o `<aside class="flex w-[340px] shrink-0 flex-col border-l border-n-weak bg-n-solid-1">` passa a ter a largura pelo modo:
```vue
      <aside
        class="flex shrink-0 flex-col border-l border-n-weak bg-n-solid-1"
        :class="somenteLeitura ? 'w-[420px]' : 'w-[340px]'"
      >
```
- trocar o bloco `<div v-else-if="somenteLeitura" data-testid="sistema-descricao" …> … </div>` (o `h4` com `COMO_RODA` e o `p` com `fluxo.descricao`) por:
```vue
        <FichaSistema v-else-if="somenteLeitura" :fluxo="fluxo" />
```

- [ ] **Step 6: `Lista.vue`** (Edit) — no `v-else` do selo da aba Do sistema, trocar
```vue
                <span
                  v-else
                  :class="[CHIP, TOM.blue]"
                  class="whitespace-nowrap font-mono"
                >
                  {{ t(`${K}.SELO.NO_CODIGO`) }}
                </span>
```
por
```vue
                <span
                  v-else
                  data-testid="sistema-no-fluxo"
                  :class="[CHIP, TOM.teal]"
                  class="whitespace-nowrap font-mono"
                >
                  {{ t(`${K}.SELO.NO_FLUXO`) }}
                </span>
```
e, no comentário do topo, a linha `// B5: regra de dado ganha o selo "regra fixa (fica no código)" — não migra.` por `// 08/10: 22 com o selo "regra fixa (fica no código)"; as 7 do fluxo, "roda no fluxo". Clique = a ficha.`

- [ ] **Step 7: Specs do Editor e da Lista** (Edit):

`specs/Editor.spec.js`:
- trocar o mock de `vue-router` inteiro por um com a rota reativa (o `watch` do `fluxoId` precisa enxergar a troca; a fábrica do `vi.mock` é içada, então a rota nasce dentro dela):
```js
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ params: { fluxoId: '5' } });
  return {
    useRoute: () => rota,
    useRouter: () => ({ push: vi.fn() }),
    onBeforeRouteLeave: vi.fn(),
  };
});
```
e acrescentar `import { useRoute } from 'vue-router';` aos imports do topo (o teste pega a mesma rota com `useRoute()`).
- no `SISTEMA`, acrescentar `fixa: true,` e
```js
  ficha: {
    o_que_faz: 'Prepara rascunhos de retomada.',
    quando: 'Todo dia às 11:00.',
    o_que_mexe: ['Notas do lead.'],
    travas: ['Até 15 por dia.'],
    por_que: 'Porque sim.',
    mudar: { pedido: 'Peça ao Claude.', arquivos: ['app/x.rb'], impacto: 'Nenhum.' },
    fluxos: [],
  },
```
- no 1º exemplo, trocar `expect(descricao.text()).toContain('How it runs today');` por `expect(descricao.text()).toContain('How it runs in code (technical details)');` e acrescentar, no fim do exemplo:
```js
    expect(wrapper.get('[data-testid="ficha-o-que-faz"]').text()).toContain(
      'Prepara rascunhos de retomada.'
    );
```
- acrescentar um exemplo novo no `describe('Editor — desenho do sistema')`:
```js
  it('trocar de fluxo pela rota (Abrir o fluxo) recarrega o editor', async () => {
    RamonFluxosAPI.show.mockResolvedValue({ data: SISTEMA });
    RamonFluxosAPI.execucoes.mockResolvedValue({ data: { payload: [] } });
    mount(Editor, {
      global: {
        stubs: { Quadro: true, RouterLink: { template: '<a><slot /></a>' } },
      },
    });
    await flushPromises();
    RamonFluxosAPI.show.mockClear();
    useRoute().params.fluxoId = '9';
    await flushPromises();
    expect(RamonFluxosAPI.show).toHaveBeenCalledWith(9); // useFluxoEditor.carregar(id) → RamonFluxosAPI.show(id)
    useRoute().params.fluxoId = '5';
    await flushPromises();
  });
```

`specs/Lista.spec.js` — no exemplo que conta `[data-testid="sistema-fixa"]` (perto da linha 273), trocar a última linha `expect(wrapper.text()).toContain('runs in code');` por:
```js
    expect(wrapper.get('[data-testid="sistema-no-fluxo"]').text()).toBe(
      'runs in a flow'
    );
```

- [ ] **Step 8: Rodar**
```bash
cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-fluxos-b5-conta
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes
./node_modules/.bin/eslint --fix app/javascript/dashboard/routes/dashboard/captain/automacoes
./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes
grep -rn "NO_CODIGO" app/javascript
```
Expected: vitest verde; eslint sem `error`; o grep vazio.

- [ ] **Step 9: Commit**
```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit -m "feat(fluxos): ficha da automação na aba Do sistema — o que faz, quando, travas, por quê e Abrir o fluxo" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 9: Story + prints "depois" (as 29 fichas, claro e escuro) + `comparar.html` (julgamento: conferir cada print)

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/Automacoes.story.vue`
- Create (fora do git): `tmp/fichas-harness/{telas-depois.txt,comparar.mjs}`, `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-08-fichas-automacoes\{depois-*.png,comparar.html}`

**Interfaces:**
- Consumes: harness da Task 1 (porta 6198); `FichaSistema` (Task 8); os JSON com `ficha`/`fixa` (Task 6).
- Produces: variantes `Ficha <chave>` (uma por automação) na story; a página de aprovação.

- [ ] **Step 1: Story** (Edit em `Automacoes.story.vue`):
- logo antes de `const SISTEMA = Object.entries(DESENHOS_SISTEMA).map(` acrescentar:
```js
// 08/10: o "Abrir o fluxo" da ficha — fluxos FICTÍCIOS no lugar das chaves (a API troca pelos da conta).
const NOMES_FLUXO = {
  reuniao_marcada: 'Reunião marcada',
  reuniao_cancelada: 'Reunião cancelada',
  lembretes_reuniao: 'Lembretes de reunião',
};
const comFluxos = (d, i) =>
  d.ficha && {
    ...d.ficha,
    fluxos: (d.ficha.fluxos || []).map((chave, j) => ({
      id: 300 + i * 3 + j,
      nome: NOMES_FLUXO[chave] || d.nome,
      modo: 'normal',
      ativo: true,
    })),
  };
```
- dentro do objeto devolvido pelo `.map(([arquivo, d], i) => …)`, depois de `alcance: d.alcance ?? null,` acrescentar:
```js
    fixa: d.fixa === true,
    ficha: comFluxos(d, i),
```
- no `<template>`, depois da `<Variant title="SistemaAvisos" …>…</Variant>`, acrescentar:
```vue
    <Variant
      v-for="f in SISTEMA"
      :key="f.sistema_chave"
      :title="`Ficha ${f.sistema_chave}`"
      :init-state="abreSistema(f.sistema_chave)"
    >
      <div class="h-screen"><Editor /></div>
    </Variant>
```
- `./node_modules/.bin/eslint --fix app/javascript/dashboard/routes/dashboard/captain/automacoes/Automacoes.story.vue` e commit:
```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/Automacoes.story.vue
git commit -m "test(fluxos): story com a ficha de cada automação do sistema para os prints de aprovação" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

- [ ] **Step 2: `tmp/fichas-harness/telas-depois.txt`** (gerar — Bash):
```bash
cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-fluxos-b5-conta
{ printf 'automacoes:DoSistema:do-sistema:1440,2200\nautomacoes:SistemaLembretes:sistema-lembretes:1440,2200\nautomacoes:SistemaAvisos:sistema-avisos:1440,2200\n'
  for f in db/seeds/ramon/fluxos/sistema/*.json; do c=$(basename "$f" .json); printf 'automacoes:Ficha %s:ficha-%s:1440,2200\n' "$c" "$c"; done
} > tmp/fichas-harness/telas-depois.txt
wc -l tmp/fichas-harness/telas-depois.txt
```
Expected: `32`. (Altura 2200: a ficha mais longa cabe inteira no painel sem rolar.)

- [ ] **Step 3: Prints "depois"** — `sh tmp/fichas-harness/shots.sh depois` → 64 PNGs. Abrir com Read e conferir, claro **e** escuro: (1) `depois-claro-do-sistema.png`: o texto novo do aviso azul; as 7 do fluxo com o selo verde "roda no fluxo", as 22 com "regra fixa (fica no código)"; (2) `depois-*-sistema-lembretes.png`: 3 botões "Abrir o fluxo"; (3) `depois-*-ficha-contrato_limpo.png` e `depois-*-ficha-agente_hub.png`: as 6 seções inteiras, nada cortado embaixo, cartões e avisos **translúcidos** (nada de fundo chapado no escuro), nenhum roxo; (4) nada em inglês no pt_BR. Se algo falhar, corrigir na Task 8 (commit `fix(fluxos): …`) e tirar o print de novo. Se alguma ficha cortar embaixo, aumentar a altura dela no `telas-depois.txt`.

- [ ] **Step 4: `tmp/fichas-harness/comparar.mjs`** (Write):
```js
// Gera comparar.html: antes × depois das telas e as 29 fichas (print + o texto, para revisar) — aprovação do Eduardo.
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';

const OUT = 'C:/Users/dudsl/RAdvogados/comercial/docs/mockups/2026-10-08-fichas-automacoes';
const PASTA = 'db/seeds/ramon/fluxos/sistema';
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const fig = (rotulo, arq) =>
  `<figure><figcaption>${rotulo}</figcaption><a href="${arq}"><img src="${arq}" alt="${esc(rotulo)}"></a></figure>`;

const TELAS = [
  ['Automações → Do sistema (a lista)', 'do-sistema'],
  ['Desenho do sistema — Lembretes de reunião (no fluxo)', 'sistema-lembretes'],
  ['Desenho do sistema — Avisos do Painel (regra fixa)', 'sistema-avisos'],
];
const telas = TELAS.map(([nome, arq]) =>
  ['claro', 'escuro'].map(tema =>
    `<section><h2>${nome} · tema ${tema}</h2><div class="par">${fig('Antes', `antes-${tema}-${arq}.png`)}${fig('Depois', `depois-${tema}-${arq}.png`)}</div></section>`
  ).join('')
).join('');

const lista = items => `<ul>${items.map(i => `<li>${esc(i)}</li>`).join('')}</ul>`;
const desenhos = readdirSync(PASTA).sort().map(a => [a.replace('.json', ''), JSON.parse(readFileSync(`${PASTA}/${a}`, 'utf8'))]);
const ficha = ([chave, d]) => {
  const f = d.ficha;
  const texto = `<dl>
<dt>O que faz</dt><dd>${esc(f.o_que_faz)}</dd>
<dt>Quando</dt><dd>${esc(f.quando)}</dd>
<dt>O que mexe</dt><dd>${lista(f.o_que_mexe)}</dd>
<dt>Travas e garantias</dt><dd>${lista(f.travas)}</dd>
<dt>${d.fixa ? 'Por que fica no código' : 'No fluxo'}</dt><dd>${esc(f.por_que)}</dd>
<dt>Se quiser mudar</dt><dd>${esc(f.mudar.pedido)}${lista(f.mudar.arquivos)}<i>${esc(f.mudar.impacto)}</i></dd>
</dl>`;
  return `<section id="${chave}"><h3>${esc(d.nome)} <small>${d.fixa ? 'regra fixa' : 'roda no fluxo'}</small></h3><div class="par">${fig('Claro', `depois-claro-ficha-${chave}.png`)}${fig('Escuro', `depois-escuro-ficha-${chave}.png`)}<div class="texto">${texto}</div></div></section>`;
};
const noFluxo = desenhos.filter(([, d]) => !d.fixa);
const fixas = desenhos.filter(([, d]) => d.fixa);
const indice = grupo => grupo.map(([c, d]) => `<a href="#${c}">${esc(d.nome)}</a>`).join(' · ');

const semPrint =
  '<section><h2>O que não tem print</h2><ul>' +
  '<li><b>Gatilhos</b>: Assinatura do Painel, Documento pelo Painel, Reunião gravada, Peça publicada e Peça mudou de status saíram da lista de gatilhos (N1). Nota privada escrita, Chegada de cliente e Contrato assinado/recusado ficam.</li>' +
  '<li><b>Rotina pronta</b>: no passo "Rotina pronta" sobram as 5 do lead ganho/ADVBOX, o Resumo do dia (Horário da conta) e Escalar a chegada.</li>' +
  '<li><b>Nada muda no que o hub faz</b>: as 16 que viraram regra fixa continuam fazendo exatamente o que faziam (nunca tinham sido ligadas no fluxo). As 7 do fluxo não mudam.</li>' +
  '</ul></section>';
const css =
  'body{font:14px system-ui,sans-serif;margin:24px;background:#f4f4f4;color:#111}h1{font-size:20px}h2{font-size:15px;margin:28px 0 8px}h3{margin:32px 0 8px}small{font-weight:400;color:#666}.par{display:flex;gap:16px;align-items:flex-start;flex-wrap:wrap}figure{margin:0;background:#fff;padding:8px;border:1px solid #ddd;border-radius:8px}figcaption{font-weight:600;margin-bottom:6px}img{width:520px;max-width:100%;display:block}.texto{flex:1;min-width:280px;max-width:560px;background:#fff;border:1px solid #ddd;border-radius:8px;padding:12px}dt{font-weight:700;margin-top:10px}dd{margin:4px 0 0}ul{margin:4px 0;padding-left:18px}@media (max-width:760px){body{margin:16px}}';

writeFileSync(
  `${OUT}/comparar.html`,
  `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Fichas das automações</title><style>${css}</style></head><body>
<h1>Automações — 16 viram regra fixa + a ficha das 29</h1>
<p>Prints com dados fictícios (story). <b>Revise o TEXTO de cada ficha</b> (coluna da direita): é o que vai para a tela. Decisão N1 no topo do plano.</p>
${telas}
<h2>As 7 que rodam no fluxo</h2><p>${indice(noFluxo)}</p>${noFluxo.map(ficha).join('')}
<h2>As 22 regras fixas</h2><p>${indice(fixas)}</p>${fixas.map(ficha).join('')}
${semPrint}</body></html>`
);
console.log(`ok ${OUT}/comparar.html (${desenhos.length} fichas)`);
```
Rodar `node tmp/fichas-harness/comparar.mjs` (da raiz da worktree) → `ok …/comparar.html (29 fichas)`. Abrir no navegador e conferir que todas as imagens carregam.

- [ ] **Step 5:** entregar ao controlador o caminho `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-08-fichas-automacoes\comparar.html` (com a pasta clicável) para o Eduardo. **Merge só com o "aprovado" dele** — inclusive do texto das fichas (correções de texto = editar o `ficha` no JSON do sistema e tirar o print de novo).

---

### Task 10: Notas na spec (§22) + verificação final (mecânica)

**Files:**
- Modify: `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md`

- [ ] **Step 1: §22** — acrescentar no fim da spec (Edit, depois do §21):
```markdown
## 22. Notas de 08/10/2026 — 16 automações viram regra fixa; a ficha das 29

- **Decisão do Eduardo (08/10):** das 29 automações do sistema, **7 seguem no fluxo** (já ligadas em produção): reuniões (3 fluxos), SLA da 1ª resposta, cadência de retomada, lead ganho, eventos do ADVBOX, chegada de cliente, resumo do dia. As outras **22 são regra fixa** (ficam no código de propósito): as 6 que já tinham o selo (histórico do lead, documentos completos, contrato limpo, contrato limpo cancelado, SDR automático, etiquetas de etapa e tese) + **16** migradas nas B5 e nunca ligadas — criar lead da conversa, origem do lead, sugestão de documento, coach de objeção, agente do hub, retrato do funil, fechamento do extrato, espelho do Painel, copiloto noturno, publicar peças, avisos do Painel, assinatura pelo Painel, contrato no ZapSign, documento pelo Painel, ata da reunião, acervo das peças. Revoga, para essas 16, o "migrar todas" de 07/10 (§19–§21).
- **Andaimes retirados das 16:** os grupos em `Rotinas::{Conta,Leads,Externos}::GRUPOS` (sobram `resumo_do_dia` e `chegada_cliente`; `rotinas/leads.rb` saiu), os 18 `migrados/*.json`, 11 envs no `.env.example` (sobram `RAMON_FLUXO_ROTINAS` = só o resumo, e `RAMON_FLUXO_CHEGADA`), as rotinas prontas e os textos delas, os pontos de decisão (`Migracao.decidir`, `Externos.evento`, `Conta.cada_conta` → a linha de sempre; os 6 jobs da conta voltam a `perform` sem argumento + `Account.find_each`), `Disparo::NA_HORA_CHAVES`, `mensagem_recebida`/`nota_escrita` de `DUAS_VEZES`, `PublicarPecasJob.pendente?`, `Conta::{PENDENTE,A_CADA_MINUTO}`, 4 de `FluxoExecucao::NOMES_ALVO` e **5 gatilhos** (`assinatura_painel`, `documento_painel`, `reuniao_gravada`, `peca_publicada`, `peca_mudou_status` — N1). Ficam (inofensivos ou usados): `LeadDaConversa`, `AgenteNotifyJob.chamado?`, `Chegada#escalar!`, `Peca#espelhar_notion` pública, `ZapsignLeadStatusJob.avisar`, `FluxoExecucao.lead_de`, o gatilho `nota_escrita`, e o mecanismo genérico `Rotinas.pendente`/`HorarioConta.tem_o_que_fazer?`. Os gatilhos `contrato_assinado`/`contrato_recusado` seguem para fluxos comuns (`Disparo.externo`, como antes das B5).
- **Ficha:** objeto `"ficha"` em cada `sistema/<chave>.json` — `o_que_faz`, `quando`, `o_que_mexe[]`, `travas[]`, `por_que`, `mudar{pedido, arquivos[], impacto}` e, só nas 7 do fluxo, `fluxos[]` (chaves de `migrados/`). `Ramon::Fluxos::Sistema.ficha(account, chave)` troca as chaves pelos fluxos de verdade da conta (`{id, nome, modo, ativo}`); vai só no `GET /ramon_fluxos/:id` do desenho do sistema. Tela: `FichaSistema.vue` no painel direito do editor só-leitura (420 px); o "Como roda hoje" virou o `<details>` "Como roda no código (detalhes técnicos)"; "Abrir o fluxo" navega para o editor do fluxo (o Editor recarrega quando o `fluxoId` muda). Lista: as 7 com o selo "roda no fluxo", as 22 com "regra fixa (fica no código)". Texto das fichas tirado do código (08/10) e aprovado pelo Eduardo nos prints; specs travam que todo arquivo citado existe.
- **Fica para a limpeza E7 (outro PR, ~2 semanas):** os caminhos de código-reserva das 7 do fluxo, como já previsto em §15–§21.
```

- [ ] **Step 2: Verificação final**
```bash
cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-fluxos-b5-conta
grep -rn "Externos.evento\|Migracao.decidir\|cada_conta(" app --include=*.rb
grep -rln "RAMON_FLUXO_\(PUBLICAR_PECAS\|AVISOS_PAINEL\|CRIAR_LEAD\|ORIGEM_LEAD\|SUGESTAO_DOC\|COACH\|AGENTE\|ASSINATURA_PAINEL\|CONTRATO_ZAPSIGN\|DOCUMENTO_PAINEL\|ATA_REUNIAO\|ACERVO_PECAS\)" app lib spec config .env.example
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes app/javascript/dashboard/routes/dashboard/ramon
./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes
git status --short
```
Expected: 1º grep = só o ouvinte do lead (`sla`), o controller da chegada, as definições em `migracao.rb`/`externos.rb`/`rotinas/conta.rb` e o `daily_digest_job.rb`; 2º grep vazio; vitest verde; eslint sem `error`; `git status` limpo (o `tmp/` é ignorado).

- [ ] **Step 3: Commit**
```bash
git add docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md
git commit -m "docs(fluxos): §22 — 16 automações viram regra fixa e a ficha das 29" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

## Operação depois do deploy

Conta da banca = **2**; console = `docker exec intranet-ramon-chatwoot-web-1 bundle exec rails runner '<ruby>'` (o Eduardo roda via `!` e cola a saída — o ssh de escrita do Claude é barrado).

**Antes do deploy (só leitura) — confirmar a premissa:**
```bash
docker exec intranet-ramon-chatwoot-web-1 bundle exec rails runner '
fixas = %w[criar_lead_da_conversa origem_do_lead sugestao_documento coach_objecao agente_hub retrato_funil fechamento_extrato espelho_painel copiloto_noturno publicar_pecas avisos_painel assinatura_painel contrato_zapsign_assinado contrato_zapsign_recusado documento_painel ata_reuniao acervo_pecas_drive acervo_pecas_notion]
p migrados: Fluxo.where(origem: "usuario", sistema_chave: fixas).pluck(:id, :sistema_chave, :modo, :ativo)
p gatilhos: Fluxo.where.not(origem: "sistema").where(gatilho_tipo: %w[assinatura_painel documento_painel reuniao_gravada peca_publicada peca_mudou_status]).pluck(:id, :nome)'
grep -E "RAMON_FLUXO_(PUBLICAR_PECAS|AVISOS_PAINEL|CRIAR_LEAD|ORIGEM_LEAD|SUGESTAO_DOC|COACH|AGENTE|ASSINATURA_PAINEL|CONTRATO_ZAPSIGN|DOCUMENTO_PAINEL|ATA_REUNIAO|ACERVO_PECAS)" /opt/intranet-ramon/chatwoot.env
```
Esperado: `{:migrados=>[]}`, `{:gatilhos=>[]}` e o grep vazio. **Se vier algum fluxo:** excluir na tela (Automações → Meus fluxos → lixeira) antes do deploy. **Se vier env:** pode ficar (sem grupo no código, ninguém lê) — apagar da `chatwoot.env` quando for mexer nela.

**Deploy:** o de sempre, **sem migração** e **sem env nova**. Recriar web **e** worker.

**Depois do deploy (smoke, ~3 min, pelo Eduardo):**
1. Automações → aba **Do sistema**: o aviso azul novo; 7 linhas com "roda no fluxo" (verde) e 22 com "regra fixa (fica no código)".
2. Clicar **Contrato limpo**: à direita, a ficha com as 6 partes; embaixo, "Como roda no código (detalhes técnicos)" abre o texto antigo.
3. Clicar **Lembretes de reunião**: 3 botões "Abrir o fluxo: Reunião marcada / Reunião cancelada / Lembretes de reunião · no comando"; clicar um abre o fluxo de verdade (o quadro editável).
4. Abrir um fluxo seu → gatilho: a lista não tem mais Assinatura do Painel, Documento pelo Painel, Reunião gravada, Peça publicada nem Peça mudou de status.
5. Nada muda no dia a dia: conversa nova continua criando lead; anexo continua gerando sugestão; @claude continua respondendo; o resumo das 8h e a chegada continuam pelos fluxos.

**Voltar atrás:** reverter o PR (nada de dado foi migrado; as fichas são só texto).

## Divergências registradas (código × descrições antigas) — viraram texto da ficha, sem mudar comportamento

Achadas lendo o código em 08/10; as fichas dizem a verdade e 3 frases das descrições técnicas foram corrigidas (Task 6). Nenhuma muda o que o hub faz — se o Eduardo quiser mudar alguma, é pedido novo.
- **Coach de objeção:** a janela de 10 min é **por lead** (não por conversa) e começa mesmo quando não acha objeção. O `retry_on` do job é código morto (o serviço engole todo erro).
- **Sugestão de documento:** o gatilho *Documento recebido* nasce na **sugestão** da IA, antes de alguém confirmar; a IA vê só o **nome** do arquivo (não abre o arquivo), embora o balão diga "leu o anexo".
- **Histórico do lead:** motivo de perda, nome, canal e origem **não** viram linha de histórico (o motivo fica só na auditoria).
- **Agente do hub:** teto de 30 por dia, pode gravar .md no Drive e criar tarefa no ADVBOX; o contexto enviado não é mascarado (fica na VPS).
- **Contrato no ZapSign:** não roda "logo depois do envio do contrato" — só no "Gerar de novo" com o documento anterior já assinado.
- **Assinatura pelo Painel:** aviso repetido regrava a data da assinatura; **Documento pelo Painel:** o push pode repetir nas novas tentativas; **Acervo das peças:** nova tentativa do Drive pode duplicar arquivos.
- **Avisos do Painel:** com `PORTAL_AVISOS=on` e sem SMTP, as novidades são marcadas como avisadas sem e-mail sair.
- **Origem do lead:** lead de anúncio com origem vazia vira `meta_ads` mesmo com canal escolhido à mão.

---

## Anexo A — o texto das 29 fichas (conteúdo que o Eduardo revisa nos prints)

Copiar **exatamente** este JSON para `tmp/fichas.json` na Task 6 (o script aplica em cada `db/seeds/ramon/fluxos/sistema/<chave>.json`). Regras do texto: PT-BR simples, sem nome de classe no corpo (os caminhos ficam só em "arquivos"), sem prometer o que o código não faz. As 7 do fluxo têm `"fluxos"`; as 22 regras fixas não.

```json
{
  "historico_do_lead": {
    "o_que_faz": "Escreve no histórico do lead (aba Atividade) uma linha para cada mudança importante: lead criado; etapa, SDR, Closer, prioridade, tese e valor (de → para); nota nova; tarefa criada ou concluída. Quem mudou aparece com o nome; o que o hub fez sozinho aparece como \"Sistema\".",
    "quando": "Na hora, sempre que o lead, uma nota ou uma tarefa é gravado — por uma pessoa, por uma automação ou pela API.",
    "o_que_mexe": [
      "Linhas do histórico do lead.",
      "Não manda sino nem push."
    ],
    "travas": [
      "Só os campos da lista viram linha: mudar nome, canal, origem, motivo de perda ou o checklist de documentos não gera linha (o motivo de perda fica só na trilha interna de auditoria).",
      "Outras partes do hub também escrevem no mesmo histórico (reuniões, ZapSign, ADVBOX, retomadas, o passo \"Registrar atividade\" dos fluxos) — esta regra cuida só das linhas básicas.",
      "Linha gravada não é apagada nem editada depois."
    ],
    "por_que": "É o registro do próprio dado: tem de acontecer em toda gravação, sem exceção e sem depender de um fluxo ligado. Um fluxo pode ser desligado ou filtrado e deixaria buracos no histórico — e o histórico é a prova do que aconteceu com o caso.",
    "mudar": {
      "pedido": "Peça ao Claude: \"no histórico do lead, registre também quando mudar <campo>\" (ou \"pare de registrar <campo>\").",
      "arquivos": [
        "app/models/lead.rb",
        "app/models/lead_note.rb",
        "app/models/lead_task.rb",
        "app/javascript/dashboard/routes/dashboard/ramon/components/conversation/ListaAtividades.vue"
      ],
      "impacto": "Muda o que aparece na aba Atividade daqui para a frente; as linhas antigas ficam como estão."
    }
  },
  "docs_completos": {
    "o_que_faz": "Quando todos os documentos do checklist da tese do lead estão marcados como \"recebido\", grava a data em que o checklist ficou completo. Se algum item voltar a ficar pendente, apaga a data; completar de novo grava a data nova.",
    "quando": "Toda vez que o lead é gravado mexendo no checklist ou na tese — por exemplo, quando alguém marca um documento como recebido no painel do lead ou confirma a sugestão da IA.",
    "o_que_mexe": [
      "A data \"documentos completos\" do lead.",
      "Essa data alimenta o Contrato limpo, o Painel do Time (Closer) e o radar de prescrição."
    ],
    "travas": [
      "Só conta o que uma pessoa marcou como \"recebido\": documento enviado pelo Painel do Cliente ou sugerido pela IA não conta até alguém confirmar.",
      "Lead sem tese, ou tese sem itens de documento, nunca fica completo.",
      "Item novo acrescentado na tese só entra na conta na próxima gravação do lead.",
      "Não manda sino nem push."
    ],
    "por_que": "É regra de dado: a data precisa ser exata e sempre igual, porque decide o contrato limpo e, com ele, a variável do SDR e do Closer. Se fosse um fluxo, desligá-lo ou editá-lo mudaria o dinheiro de alguém.",
    "mudar": {
      "pedido": "Peça ao Claude: \"o checklist só conta como completo quando <regra nova>\".",
      "arquivos": [
        "app/models/concerns/lead_comercial.rb",
        "app/models/concerns/lead_docs.rb",
        "app/javascript/dashboard/routes/dashboard/ramon/components/lead/DocChecklist.vue"
      ],
      "impacto": "Muda quem entra no Contrato limpo e, portanto, o extrato da variável dos meses seguintes. Datas já gravadas não mudam sozinhas."
    }
  },
  "contrato_limpo": {
    "o_que_faz": "Marca como \"contrato limpo\" o lead ganho que passou 7 dias sem cancelar e está com os documentos completos. A data gravada é o momento exato em que ficou limpo: o mais tarde entre a data do ganho + 7 dias e a data dos documentos completos.",
    "quando": "De hora em hora, aos 10 minutos (09:10, 10:10…), para todos os leads ganhos.",
    "o_que_mexe": [
      "A data \"contrato limpo\" do lead.",
      "Extrato da variável: a unidade de contrato do Closer e do SDR (a do SDR só se a reunião foi registrada), no mês dessa data.",
      "Painel do Time (Closer): a coluna dos que aguardam."
    ],
    "travas": [
      "Carimba uma vez só e depois não muda mais — nem se os documentos voltarem a ficar incompletos.",
      "Cancelar antes dos 7 dias tira o lead de Fechado e ele nunca é carimbado; se fechar de novo, conta a partir da data nova.",
      "Casos de cálculo do ADVBOX ficam de fora.",
      "Não gera histórico, sino nem push."
    ],
    "por_que": "É regra de dado que mexe em dinheiro (regulamento da variável): tem de ser exata, igual para todos e não pode ser desligada sem querer numa tela.",
    "mudar": {
      "pedido": "Peça ao Claude: \"o contrato limpo passa a valer depois de <N> dias\" ou \"passa a exigir <condição>\".",
      "arquivos": [
        "app/jobs/ramon/contrato_limpo_job.rb",
        "config/schedule.yml",
        "app/services/ramon/extrato_variavel.rb"
      ],
      "impacto": "Muda o extrato da variável a partir do mês em que entrar no ar; meses já fechados não mudam. É regra do regulamento: combine antes com quem recebe a variável."
    }
  },
  "contrato_limpo_cancelado": {
    "o_que_faz": "Quando um lead que já era contrato limpo sai de Fechado (o ganho é desfeito), apaga a marca de limpo e grava a data do cancelamento. Se o mês em que aquele contrato foi pago já está fechado no extrato, o desconto entra na apuração seguinte.",
    "quando": "Na hora em que o lead sai da etapa de ganho para qualquer outra (inclusive Perdido).",
    "o_que_mexe": [
      "Apaga a data \"contrato limpo\" e grava a data \"contrato cancelado\" do lead.",
      "Extrato da variável: linha de desconto (o valor da unidade, negativo) e, se a saída derrubar bônus ou degrau do Closer, a linha de desconto do bônus.",
      "Separado disso, toda saída de Fechado (mesmo antes de limpo) deixa a linha \"contrato cancelado\" no histórico do lead."
    ],
    "travas": [
      "Só age se o lead já tinha a marca de contrato limpo.",
      "Nunca desconta em dobro: só desconta enquanto houver unidade paga sem desconto.",
      "Mês ainda aberto: o lead só sai da contagem, sem desconto.",
      "Se o lead voltar a fechar, ganha data nova de ganho e pode ser carimbado de novo."
    ],
    "por_que": "É o par do Contrato limpo e mexe em dinheiro: precisa acontecer sempre, junto com a mudança de etapa, sem depender de um fluxo ligado.",
    "mudar": {
      "pedido": "Peça ao Claude: \"quando um contrato limpo for cancelado, <regra nova de desconto>\".",
      "arquivos": [
        "app/models/concerns/lead_comercial.rb",
        "app/models/lead.rb",
        "app/services/ramon/extrato_descontos.rb"
      ],
      "impacto": "Muda os descontos do extrato a partir da próxima apuração. É regra do regulamento da variável."
    }
  },
  "sdr_automatico": {
    "o_que_faz": "Quando nasce um lead sem SDR, escolhe a pessoa do time \"sdr\" que tem menos leads abertos (empate: quem foi cadastrada antes no hub) e passa a conversa do lead para ela.",
    "quando": "Na criação de todo lead (conversa nova, landing page, cadastro à mão, API). A conversa também vai para o SDR quando o SDR do lead muda ou o lead ganha uma conversa.",
    "o_que_mexe": [
      "O SDR do lead.",
      "O responsável da conversa (com o aviso de atribuição de sempre do hub)."
    ],
    "travas": [
      "Lead que já nasce com SDR, caso de cálculo do ADVBOX e importação ficam de fora.",
      "Time \"sdr\" vazio: o lead fica sem SDR.",
      "Nunca tira a conversa de quem já é o responsável dela.",
      "Na criação, o histórico mostra só \"lead criado\" (não há uma linha separada de troca de SDR)."
    ],
    "por_que": "Roda no instante em que o lead é gravado, antes de ele existir — um fluxo só começaria depois. É regra de dado: todo lead precisa sair com dono, sem brecha.",
    "mudar": {
      "pedido": "Peça ao Claude: \"o SDR automático passa a escolher por <critério>\" (ex.: rodízio, por tese, por caixa).",
      "arquivos": [
        "app/models/concerns/lead_comercial.rb",
        "app/services/ramon/papeis.rb"
      ],
      "impacto": "Vale para os leads novos; os já distribuídos não mudam. Afeta a divisão do trabalho e os números por SDR."
    }
  },
  "etiquetas_etapa_tese": {
    "o_que_faz": "Mantém na conversa uma etiqueta da etapa do lead (fase-…, tirada do campo \"etiqueta\" da etapa) e uma da tese (tese-…), tirando as antigas. No sentido contrário, se alguém põe à mão uma etiqueta fase-… na conversa, o lead muda para aquela etapa.",
    "quando": "Toda vez que o lead é criado ou gravado (qualquer mudança, não só de etapa) e quando as etiquetas da conversa mudam.",
    "o_que_mexe": [
      "Etiquetas da conversa (cria a etiqueta se ainda não existir).",
      "A etapa do lead, quando alguém põe uma etiqueta fase-… à mão (se for Perdido, o motivo fica \"Automação: etiqueta … na conversa\")."
    ],
    "travas": [
      "Só etiqueta fase-… ACRESCENTADA move o lead; tirar uma não faz nada.",
      "Etiqueta tese-… mexida à mão não muda o lead: na próxima gravação a certa volta.",
      "Etiqueta sem etapa correspondente é ignorada.",
      "O hub compara antes de gravar, para não entrar em laço (lead ↔ conversa)."
    ],
    "por_que": "É sincronia de dado nos dois sentidos e roda a cada gravação do lead; o quadro de fluxos não tem gatilho de etiqueta, e um fluxo desligado deixaria conversa e funil desencontrados.",
    "mudar": {
      "pedido": "Peça ao Claude: \"as etiquetas da conversa passam a <regra nova>\" (ex.: incluir o SDR, não mexer na tese).",
      "arquivos": [
        "app/services/ramon/stage_label_sync.rb",
        "app/services/ramon/tese_label_sync.rb",
        "app/listeners/ramon_lead_listener.rb"
      ],
      "impacto": "Muda as etiquetas das conversas a partir da próxima gravação de cada lead; filtros e visões salvas que usam fase-… ou tese-… podem mudar."
    }
  },
  "criar_lead_da_conversa": {
    "o_que_faz": "Quando chega uma conversa nova numa caixa com \"Criar lead\" ligado, liga a conversa ao lead aberto do mesmo contato ou, se não houver, cria o lead na 1ª etapa do funil, com o nome do contato (sem nome: o telefone).",
    "quando": "Na hora em que a conversa nova é criada.",
    "o_que_mexe": [
      "Lead novo — ou a conversa nova ligada ao lead aberto (a conversa antiga perde o vínculo).",
      "No lead novo, as regras fixas de sempre: SDR automático, canal inicial \"outro\", histórico \"lead criado\", etiquetas."
    ],
    "travas": [
      "Só em caixa com \"Criar lead\" ligado e conversa com contato.",
      "Lead fechado (ganho ou perdido) não conta: o contato ganha um lead novo (pessoa ≠ caso).",
      "Caso de cálculo do ADVBOX não conta como lead aberto.",
      "Logo depois, no mesmo instante, começa o SLA da 1ª resposta (essa parte roda no fluxo)."
    ],
    "por_que": "É a porta de entrada do funil: todos os números do funil saem daqui. Precisa acontecer sempre e antes de tudo (antes do SLA e dos fluxos de Conversa nova). Fica no código por decisão do Eduardo (08/10).",
    "mudar": {
      "pedido": "Peça ao Claude: \"criar lead da conversa passa a <regra nova>\" (ex.: outra etapa inicial).",
      "arquivos": [
        "app/listeners/ramon_lead_listener.rb",
        "app/services/ramon/lead_da_conversa.rb",
        "app/models/lead.rb"
      ],
      "impacto": "Muda a entrada de todo lead novo das caixas — e, com ela, o funil, o SDR automático e os relatórios."
    }
  },
  "origem_do_lead": {
    "o_que_faz": "Na mensagem do cliente, descobre de onde o lead veio e anota: anúncio da Meta (clique para o WhatsApp) grava a origem \"anuncio-meta: …\" e o canal meta_ads; as frases das assinaturas do site, das landing pages, da triagem e do Instagram gravam o canal certo; sem nada disso, o canal vira indicação (ou instagram, se a caixa é do Instagram).",
    "quando": "A cada mensagem do cliente enquanto o canal do lead ainda não foi descoberto, e em toda mensagem que chega com dados de anúncio.",
    "o_que_mexe": [
      "Origem e canal do lead, e os dados do anúncio da Meta guardados no lead.",
      "Não gera linha no histórico nem aviso."
    ],
    "travas": [
      "Sem IA: é comparação do texto com as frases das assinaturas.",
      "Canal já descoberto não é refeito; origem já preenchida não é trocada (o anúncio só atualiza os dados guardados).",
      "Atenção: lead que chega por anúncio com a origem vazia fica com o canal meta_ads, mesmo que alguém tenha escolhido outro canal à mão.",
      "Mudar o texto dos botões de WhatsApp do site ou das LPs quebra a descoberta (as frases precisam bater)."
    ],
    "por_que": "É dado de atribuição — de onde vem cada cliente: alimenta o funil por origem e o retorno dos anúncios. Precisa ser igual para todos e acontecer antes dos fluxos de Mensagem recebida. Fica no código por decisão do Eduardo (08/10).",
    "mudar": {
      "pedido": "Peça ao Claude: \"inclua a frase <texto> como origem <canal>\" ou \"o canal padrão passa a ser <canal>\".",
      "arquivos": [
        "app/services/ramon/lead_da_conversa.rb",
        "app/services/ramon/source_catalog.rb",
        "app/listeners/ramon_lead_listener.rb"
      ],
      "impacto": "Vale para os leads novos; os antigos não são recalculados. Muda os relatórios por origem daqui para a frente."
    }
  },
  "sugestao_documento": {
    "o_que_faz": "Quando o cliente manda uma imagem ou um arquivo, a IA compara com os itens pendentes do checklist da tese e, se reconhecer, mostra na conversa o balão \"IA do hub leu o anexo e sugeriu: é ‹item›\", com Confirmar e Dispensar. Quem confirma é a equipe — no balão ou na aba Documentos.",
    "quando": "Na fila, logo depois da mensagem do cliente com anexo (imagem ou arquivo), se a conversa tem lead.",
    "o_que_mexe": [
      "Uma sugestão guardada no lead (só uma pendente por vez: a nova substitui a anterior).",
      "Balão na conversa (só a equipe vê).",
      "Dispara o gatilho \"Documento recebido\" dos fluxos — já na SUGESTÃO, antes de alguém confirmar.",
      "Ao confirmar: o item vira \"recebido\", com o anexo vinculado (pode completar o checklist e mandar ao Drive, se o lead já é ganho)."
    ],
    "travas": [
      "Só lead com tese e item de documento pendente.",
      "A IA não abre o arquivo: vê o nome e o tipo do arquivo e as últimas 10 mensagens, com nome, CPF, RG, telefone, e-mail e endereço mascarados.",
      "Na dúvida a IA não sugere nada; resposta estranha é ignorada.",
      "IA fora do ar: tenta de novo até 3 vezes; depois desiste em silêncio.",
      "Nada vai para o cliente."
    ],
    "por_que": "Decisão do Eduardo (08/10): fica no código como está. Já tem a pessoa no meio (é só sugestão), e a leitura com IA + checklist + balão com botões não cabe nos passos do quadro.",
    "mudar": {
      "pedido": "Peça ao Claude: \"a sugestão de documento passa a <mudança>\" (ex.: só disparar o gatilho Documento recebido depois da confirmação).",
      "arquivos": [
        "app/services/ramon/doc_match_service.rb",
        "app/jobs/ramon/doc_match_job.rb",
        "app/listeners/ramon_lead_listener.rb",
        "app/javascript/dashboard/routes/dashboard/ramon/composables/useDocSugestao.js"
      ],
      "impacto": "Muda o que a equipe vê ao receber anexos e, se mexer no gatilho, os fluxos que usam \"Documento recebido\". Custo de IA: 1 chamada por anexo (aparece em Uso e custo)."
    }
  },
  "coach_objecao": {
    "o_que_faz": "Quando o cliente escreve uma mensagem com objeção (ex.: \"vou pensar\", \"é caro\"), a IA reconhece e mostra na conversa o balão \"Coach do hub: objeção detectada\", com 2 respostas prontas do playbook da tese. \"Usar\" só coloca o texto no editor — quem envia é a pessoa.",
    "quando": "Na fila, depois de cada mensagem do cliente com 20 caracteres ou mais, se a conversa tem lead com tese.",
    "o_que_mexe": [
      "Balão na conversa (só a equipe vê).",
      "Guarda no lead a hora da última leitura do coach."
    ],
    "travas": [
      "Só tese com playbook de objeções cadastrado.",
      "No máximo 1 leitura a cada 10 minutos POR LEAD — e a janela começa mesmo quando não acha objeção.",
      "A IA vê só a mensagem atual, com nome e dados pessoais mascarados; o texto proíbe prometer resultado, valor ou prazo do INSS.",
      "Qualquer erro = silêncio, sem nova tentativa."
    ],
    "por_que": "Decisão do Eduardo (08/10): fica no código como está. Já é só sugestão para a equipe (nada vai ao cliente) e a regra de leitura não cabe nos passos do quadro.",
    "mudar": {
      "pedido": "Peça ao Claude: \"o coach de objeção passa a <mudança>\" (ex.: janela de 30 minutos, 3 respostas).",
      "arquivos": [
        "app/services/ramon/coach_objecao_service.rb",
        "app/jobs/ramon/coach_objecao_job.rb",
        "app/listeners/ramon_lead_listener.rb"
      ],
      "impacto": "Muda o balão que a equipe vê e o custo de IA (1 chamada por mensagem elegível; ver Uso e custo). As respostas vêm do playbook da tese, que se edita na Inteligência."
    }
  },
  "agente_hub": {
    "o_que_faz": "Quando o Eduardo escreve uma nota privada começando com @claude, o hub chama o assistente Claude na VPS; ele lê a conversa e o dossiê do lead e responde como nota privada (\"🤖 Claude · …\"). Ele também pode salvar um arquivo .md na pasta do cliente no Drive e criar uma tarefa no ADVBOX.",
    "quando": "Na hora da nota; a resposta chega em segundos ou minutos (um pedido por vez, em fila).",
    "o_que_mexe": [
      "Nota privada de resposta na conversa (sempre — também em erro ou limite atingido).",
      "Opcional: arquivo .md no Drive do cliente e tarefa no ADVBOX (padrão: ANÁLISE DO CASO, para o Eduardo).",
      "Registro da execução, com o custo."
    ],
    "travas": [
      "Trava fixa: só nota privada que começa com @claude, escrita pelo e-mail do Eduardo — nota de outra pessoa nunca chama o agente, e a resposta do próprio Claude não dispara de novo.",
      "Até 30 pedidos por dia; se a assinatura atingir o limite de uso, pausa até o dia seguinte.",
      "Ferramentas só de leitura (pasta da sede e ADVBOX); até 6 minutos por pedido. #pesado aumenta o esforço; #tese:… escolhe a tese.",
      "O contexto enviado ao agente NÃO é mascarado (inclui CPF) — fica dentro da VPS da banca.",
      "Falha de rede ao chamar o agente só vai para o log, sem nova tentativa."
    ],
    "por_que": "Decisão do Eduardo (08/10): fica no código. A trava (só o Eduardo, só @claude) é de segurança e não pode virar algo editável na tela.",
    "mudar": {
      "pedido": "Peça ao Claude: \"o agente do hub passa a <mudança>\" (ex.: outro limite por dia, aceitar @claude de outra pessoa).",
      "arquivos": [
        "app/listeners/ramon_agente_listener.rb",
        "app/jobs/ramon/agente_notify_job.rb",
        "app/services/ramon/agente_contexto_service.rb",
        "deploy/agente-hub/agente_hub.py"
      ],
      "impacto": "Mexe em quem pode acionar o agente e no custo dele. Mudança no agente_hub.py exige atualizar o serviço na VPS, não só o deploy do hub."
    }
  },
  "contrato_zapsign": {
    "o_que_faz": "Quando o ZapSign avisa que o contrato gerado pelo cartão do lead foi assinado ou recusado, o hub confere o status de verdade no ZapSign, grava o selo no card do lead (assinado ou recusado, com a data), escreve no histórico e toca o sino para todos da conta. Nunca marca o lead como ganho.",
    "quando": "Na fila, logo depois do aviso (webhook) do ZapSign.",
    "o_que_mexe": [
      "Selo do contrato no card do lead (status e data).",
      "Linha \"contrato assinado\" ou \"contrato recusado\" no histórico do lead.",
      "Sino para todos os usuários da conta (sem push).",
      "Dispara os gatilhos \"Contrato assinado\" e \"Contrato recusado\" para os seus fluxos."
    ],
    "travas": [
      "O aviso do ZapSign só é aceito com o segredo combinado (e até 60 por minuto).",
      "O status vem de uma consulta ao ZapSign, nunca do próprio aviso.",
      "Só o documento vigente do lead e só a 1ª mudança: documento trocado (\"Gerar de novo\"), cancelado ou já com selo não faz nada de novo.",
      "ZapSign fora do ar: tenta de novo até 5 vezes.",
      "Para o selo \"recusado\", o evento de recusa precisa estar cadastrado no ZapSign.",
      "Ganho continua sendo decisão do Closer."
    ],
    "por_que": "Decisão do Eduardo (08/10): fica no código. A conferência no ZapSign e o selo são o registro do contrato (dado); o histórico e o sino vão junto, para nunca haver contrato sem aviso.",
    "mudar": {
      "pedido": "Para acrescentar uma ação, crie um fluxo seu com o gatilho \"Contrato assinado\" (ou \"recusado\") — sem mexer no código. Para mudar o selo, o histórico ou o sino, peça ao Claude: \"quando o contrato for assinado no ZapSign, <mudança>\".",
      "arquivos": [
        "app/controllers/public/api/v1/zapsign_webhooks_controller.rb",
        "app/jobs/ramon/zapsign_lead_status_job.rb",
        "app/services/ramon/zapsign_contract_service.rb"
      ],
      "impacto": "Mexe no card do lead e no sino de todos. Não mexe em ganho nem no funil."
    }
  },
  "assinatura_painel": {
    "o_que_faz": "Quando o cliente assina pelo ZapSign um documento pedido no Painel do Cliente, o hub confere o status no ZapSign e atualiza a assinatura no Painel: ela sai das pendentes, vai para as assinadas e o download fica liberado.",
    "quando": "Na fila, logo depois do aviso (webhook) do ZapSign.",
    "o_que_mexe": [
      "A assinatura no Painel do Cliente (status e data da assinatura).",
      "Nada no lead: sem histórico, sino ou push."
    ],
    "travas": [
      "O aviso do ZapSign só é aceito com o segredo combinado.",
      "O status vem de uma consulta ao ZapSign, nunca do próprio aviso.",
      "Assinatura cancelada no hub não muda.",
      "ZapSign fora do ar: tenta de novo até 5 vezes.",
      "Aviso repetido de um documento já assinado regrava a data da assinatura com a hora nova."
    ],
    "por_que": "Decisão do Eduardo (08/10): fica no código. É a atualização de um registro do Painel do Cliente a partir do ZapSign, sem escolha a fazer — não há o que desenhar.",
    "mudar": {
      "pedido": "Peça ao Claude: \"quando o cliente assinar pelo Painel, também <ação>\" (ex.: tocar o sino do responsável).",
      "arquivos": [
        "app/controllers/public/api/v1/zapsign_webhooks_controller.rb",
        "app/jobs/ramon/zapsign_status_job.rb",
        "app/models/portal_assinatura.rb"
      ],
      "impacto": "Mexe no que o cliente vê no Painel do Cliente."
    }
  },
  "documento_painel": {
    "o_que_faz": "Quando o cliente envia um documento pelo Painel do Cliente, o hub guarda o arquivo no Drive (pasta Clientes/‹Nome — CPF›), avisa no celular e cria 2 tarefas no ADVBOX: \"ANALISAR DOCUMENTAÇÃO\" para o responsável do processo e \"ORGANIZAR DOCUMENTOS\" para a recepção.",
    "quando": "Na fila, logo depois do envio. O cliente vê na hora \"Recebemos seu documento. Obrigado!\".",
    "o_que_mexe": [
      "Arquivo no Drive (se o Drive estiver configurado).",
      "Push no celular (\"Documento do cliente …\").",
      "2 tarefas no ADVBOX, com o link do Drive no comentário — grava no ADVBOX de verdade.",
      "Nada no lead do hub nem no checklist: alguém confere e marca."
    ],
    "travas": [
      "Só PDF, JPG, PNG ou HEIC, até 10 MB, ligado a um pedido de documento.",
      "Processo sem responsável: a 1ª tarefa vai para o Eduardo.",
      "Drive e cada tarefa são feitos uma vez por envio; ADVBOX fora do ar: tenta de novo até 5 vezes; recusa do ADVBOX só vai para o log.",
      "O push pode se repetir a cada nova tentativa.",
      "Sem o Drive configurado, pula o Drive; sem o ntfy, não há push."
    ],
    "por_que": "Decisão do Eduardo (08/10): fica no código. Grava no ADVBOX e no Drive com travas de \"uma vez só\" por envio — mais seguro como regra fixa do que como passos editáveis.",
    "mudar": {
      "pedido": "Peça ao Claude: \"documento enviado pelo Painel passa a <mudança>\" (ex.: a tarefa vai para outra pessoa, outro tipo de tarefa).",
      "arquivos": [
        "app/controllers/cliente/painel_controller.rb",
        "app/jobs/ramon/portal_envio_job.rb",
        "lib/ramon/drive_client.rb"
      ],
      "impacto": "Grava no ADVBOX de verdade: mudar responsável ou tipo de tarefa muda a fila do jurídico."
    }
  },
  "ata_reuniao": {
    "o_que_faz": "Quando uma reunião é gravada na área Reuniões do hub (ou alguém clica \"Reprocessar\" numa reunião com erro), o hub transcreve o áudio no servidor da banca e a IA escreve a ata — Participantes, Resumo, Decisões, Pendências — na própria reunião.",
    "quando": "Na fila, logo depois de gravar (ou de \"Reprocessar\"). A tela avisa \"A transcrição e a ata chegam aqui em alguns minutos\".",
    "o_que_mexe": [
      "Transcrição e ata na própria reunião (não é nota de conversa).",
      "Situação da reunião: transcrevendo → pronta (ou erro, com o botão Reprocessar)."
    ],
    "travas": [
      "Áudio obrigatório, até 25 MB.",
      "A transcrição é feita no próprio servidor da banca; \"Reprocessar\" reaproveita a transcrição que já existe.",
      "Áudio sem fala: ata \"Nenhuma fala detectada no áudio.\", sem IA.",
      "IA fora do ar: tenta de novo até 3 vezes; qualquer outro erro (inclusive na transcrição) vai direto para \"erro\".",
      "A IA só roda num provedor liberado para dado sensível."
    ],
    "por_que": "Decisão do Eduardo (08/10): fica no código. É trabalho pesado e longo (a transcrição pode levar muitos minutos) e não fala com ninguém — não há o que editar no quadro.",
    "mudar": {
      "pedido": "Peça ao Claude: \"a ata da reunião passa a <mudança>\" (ex.: incluir a seção Próximos passos).",
      "arquivos": [
        "app/controllers/api/v1/accounts/ramon_reunioes_controller.rb",
        "app/jobs/ramon/reuniao_ata_job.rb",
        "app/services/ramon/reuniao_ata_service.rb",
        "app/javascript/dashboard/routes/dashboard/ramon/components/reunioes/ReuniaoDetalhe.vue"
      ],
      "impacto": "Muda as atas novas; as antigas ficam como estão (Reprocessar só existe para reunião com erro)."
    }
  },
  "acervo_pecas": {
    "o_que_faz": "Quando uma peça do Instagram é publicada, copia as imagens e um legenda.txt para o Drive (Posts Instagram/‹Carrossel ou Estático›/‹data — gancho›). E, a cada mudança de status da peça, atualiza o status no quadro Peças do Notion.",
    "quando": "Drive: logo depois de a peça virar publicada. Notion: a cada mudança de status.",
    "o_que_mexe": [
      "Pasta e arquivos no Drive; a peça guarda o endereço da pasta.",
      "Status da página da peça no Notion (agendado aparece como \"montado\"; montando, publicando, falhou e reprovado não são espelhados)."
    ],
    "travas": [
      "Drive só com as 3 chaves do Drive configuradas; tenta 3 vezes — uma nova tentativa depois de um envio pela metade pode duplicar arquivos na pasta.",
      "Notion só com o token do Notion e a peça ligada a uma página; erro só vai para o log.",
      "Não é lead nem conversa: não aparece no funil."
    ],
    "por_que": "Decisão do Eduardo (08/10): fica no código. É cópia de arquivo e espelho de status, sem escolha a fazer.",
    "mudar": {
      "pedido": "Peça ao Claude: \"o acervo das peças passa a <mudança>\" (ex.: outra pasta, espelhar também \"falhou\" no Notion).",
      "arquivos": [
        "app/jobs/ramon/conteudo_drive_job.rb",
        "app/jobs/ramon/notion_espelho_job.rb",
        "app/models/peca.rb",
        "lib/ramon/drive_client.rb"
      ],
      "impacto": "Muda onde o acervo fica no Drive e o que o quadro do Notion mostra; peças antigas não são movidas."
    }
  },
  "retrato_funil": {
    "o_que_faz": "Toda noite tira uma \"foto\" do funil: quantos leads e quanto valor há em cada etapa e tese. É dessas fotos que sai o gráfico \"Funil nos últimos 30 dias\" do Centro de Comando.",
    "quando": "Todo dia às 00:05 (horário de Brasília).",
    "o_que_mexe": [
      "O retrato do dia (rodar de novo no mesmo dia substitui o retrato).",
      "Nada no lead e nenhum aviso."
    ],
    "travas": [
      "Casos de cálculo do ADVBOX ficam de fora.",
      "Ganhos e perdidos são guardados, mas o gráfico mostra só as etapas abertas.",
      "A data do retrato é a do servidor: às 00:05 bate com o dia de Brasília (se o horário mudar para depois das 21:00, sai com a data do dia seguinte).",
      "Erro numa rodada: o servidor tenta de novo sozinho."
    ],
    "por_que": "Decisão do Eduardo (08/10): fica no código. É rotina de relatório, sem escolha a fazer e sem falar com ninguém; o horário faz parte da regra (o retrato tem de ser do dia).",
    "mudar": {
      "pedido": "Peça ao Claude: \"o retrato do funil passa a guardar também <dado>\" (ou \"rodar às <hora>\").",
      "arquivos": [
        "app/jobs/ramon/daily_funnel_snapshot_job.rb",
        "app/services/ramon/funnel_snapshot_service.rb",
        "config/schedule.yml",
        "app/javascript/dashboard/routes/dashboard/ramon/pages/CommandCenter.vue"
      ],
      "impacto": "Vale a partir do retrato seguinte; os dias passados não são refeitos — por um mês o gráfico mistura o antigo e o novo."
    }
  },
  "fechamento_extrato": {
    "o_que_faz": "No 3º dia útil do mês, fecha e guarda o extrato da variável do mês anterior de cada pessoa (SDR, Closer e quem teve meta lançada), com os valores do regulamento e os descontos. Depois de fechado, a tela Extrato mostra o que foi guardado e o mês não aceita meta nova.",
    "quando": "Todo dia às 00:20 (horário de Brasília); só age do 3º dia útil em diante (segunda a sexta, sem contar feriados) e só se o mês ainda não foi guardado. A tela Extrato também fecha o mês na 1ª vez que alguém a abre depois da data.",
    "o_que_mexe": [
      "O extrato fechado do mês anterior, um por pessoa.",
      "Trava o mês: lançar meta nele passa a dar \"mês fechado\"."
    ],
    "travas": [
      "Repetir não duplica nem recalcula um mês já guardado.",
      "Feriado não conta: o \"3º dia útil\" pode cair num feriado.",
      "Conta sem ninguém nos times não guarda nada.",
      "Erro inesperado: o servidor tenta de novo sozinho."
    ],
    "por_que": "Decisão do Eduardo (08/10): fica no código. É fechamento de dinheiro pelo regulamento (§6): tem de acontecer sempre, na data, igual para todos.",
    "mudar": {
      "pedido": "Peça ao Claude: \"o extrato passa a fechar no <N>º dia útil\" ou \"passa a pular feriados\".",
      "arquivos": [
        "app/jobs/ramon/extrato_fechamento_job.rb",
        "app/services/ramon/extrato_fechamento.rb",
        "app/services/ramon/extrato_variavel.rb",
        "config/schedule.yml"
      ],
      "impacto": "Mexe no pagamento da variável. Mês já fechado não é recalculado. Combine antes com quem recebe (regulamento)."
    }
  },
  "espelho_painel": {
    "o_que_faz": "Toda noite copia do ADVBOX, para cada cliente convidado do Painel do Cliente, os processos, andamentos e pedidos de documento; a IA traduz os pedidos \"SOLICITAR DOCUMENTOS\" numa lista simples para o cliente. Marca as novidades (etapa nova, marco novo) que os Avisos do Painel usam de manhã. Também apaga os registros de acesso ao Painel com mais de 6 meses (Marco Civil).",
    "quando": "Todo dia às 00:30 (horário de Brasília).",
    "o_que_mexe": [
      "O que o cliente vê no Painel do Cliente (processos, andamentos, documentos pedidos) e o telefone do cliente, se faltava.",
      "As novidades do caso (guardadas por 30 dias).",
      "Apaga os registros de acesso com mais de 6 meses."
    ],
    "travas": [
      "Precisa do token do ADVBOX; ADVBOX fora do ar num cliente: pula para o próximo.",
      "Cliente suspenso continua sendo espelhado (só os avisos o deixam de fora).",
      "Etapa interna não aparece para o cliente; o 1º espelho de um processo não gera novidade.",
      "A IA recebe os dados mascarados e roda uma vez por pedido (guarda o resultado); com os textos v2 ligados e sem o consentimento do cliente, mostra um item genérico em vez da IA.",
      "Gasta chamadas do ADVBOX (limite de 500 por dia por rota): 1 + 2 por processo, por cliente."
    ],
    "por_que": "Decisão do Eduardo (08/10): fica no código. É a cópia do ADVBOX para o Painel, longa e cheia de regras do dicionário de etapas; não há escolha a desenhar.",
    "mudar": {
      "pedido": "Peça ao Claude: \"o espelho do Painel passa a <mudança>\" (ex.: mostrar mais andamentos).",
      "arquivos": [
        "app/jobs/ramon/portal_sync_job.rb",
        "app/services/ramon/portal_sync_service.rb",
        "app/services/ramon/portal_novidades.rb",
        "app/services/ramon/portal_docs_service.rb",
        "lib/ramon/portal_texto.rb"
      ],
      "impacto": "Muda o que o cliente vê no Painel e o consumo do limite diário do ADVBOX. O expurgo de 6 meses é obrigação legal: não tire."
    }
  },
  "copiloto_noturno": {
    "o_que_faz": "Toda madrugada, a IA olha os leads parados (há mais dias na etapa do que o limite da etapa) e prepara uma sugestão para cada um: rascunho de mensagem de retomada, mudar de etapa ou um alerta. A equipe vê de manhã no Centro de Comando, no cartão \"Enquanto você dormia\", e aplica ou arquiva.",
    "quando": "Todo dia às 05:00 (horário de Brasília).",
    "o_que_mexe": [
      "Sugestões pendentes (até 15 por noite).",
      "Ao aplicar: o rascunho vira nota no lead (\"RASCUNHO (revisar antes de enviar) — copiloto noturno\"); mover etapa só para uma etapa aberta; alerta só arquiva."
    ],
    "travas": [
      "Nada vai para o cliente.",
      "Lead que já tem sugestão pendente fica de fora; etapa sem limite de \"parado\" nunca entra.",
      "A IA recebe os dados mascarados e o texto proíbe prometer resultado ou prazo do INSS. O modelo é o escolhido em Inteligência → Uso e custo (copiloto).",
      "\"Aplicar todas\" não move etapa.",
      "Falha da IA num lead: pula aquele lead."
    ],
    "por_que": "Decisão do Eduardo (08/10): fica no código. Já tem a pessoa no meio (tudo é sugestão a aprovar) e é uma varredura da conta inteira, não um evento de um lead.",
    "mudar": {
      "pedido": "Peça ao Claude: \"o copiloto noturno passa a <mudança>\" (ex.: até 30 leads, outro horário).",
      "arquivos": [
        "app/jobs/ramon/night_copilot_job.rb",
        "app/services/ramon/night_copilot_service.rb",
        "app/models/copilot_suggestion.rb",
        "app/javascript/dashboard/routes/dashboard/ramon/components/command/NightCopilot.vue"
      ],
      "impacto": "Mais leads = mais custo de IA (1 chamada por lead; ver Uso e custo). O limite de 15 também muda sem código, pela chave RAMON_NIGHT_COPILOT_LIMIT no servidor."
    }
  },
  "publicar_pecas": {
    "o_que_faz": "A cada minuto, publica no Instagram da banca (só no feed) as peças agendadas cuja hora chegou, pela API oficial da Meta. Também resolve peças presas em \"publicando\" há mais de 30 minutos.",
    "quando": "A cada minuto. Os botões \"Publicar agora\" e \"Tentar de novo\" da tela Conteúdo também chamam.",
    "o_que_mexe": [
      "Publica a peça no Instagram (com até 3 colaboradores citados na legenda).",
      "Status e link da peça; push \"Publicado no Instagram: …\" ou \"Publicação falhou: …\".",
      "Depois de publicada: o acervo no Drive e o espelho no Notion."
    ],
    "travas": [
      "Só publica peça que um administrador aprovou e agendou na tela Conteúdo (o \"pode postar\").",
      "Sem nova tentativa automática: falhou, fica \"falhou\" + push, e o Eduardo decide tentar de novo.",
      "Peça que já tem o número do Instagram nunca é enviada de novo; falha no último passo diz \"Pode ter ido ao ar — conferir no Instagram\" e exige marcar conferido.",
      "Presa há mais de 30 minutos sem o número do Instagram: vira \"falhou\", com o aviso de conferir.",
      "O token do Instagram fica na configuração do super admin e é renovado toda segunda."
    ],
    "por_que": "Decisão do Eduardo (08/10): fica no código. Publica para o público: a trava (só peça aprovada e agendada) não pode virar algo editável no quadro.",
    "mudar": {
      "pedido": "Peça ao Claude: \"a publicação das peças passa a <mudança>\" (ex.: publicar também nos stories).",
      "arquivos": [
        "app/jobs/ramon/publicar_pecas_job.rb",
        "app/services/ramon/instagram_publisher.rb",
        "app/models/peca.rb",
        "app/controllers/api/v1/accounts/ramon_conteudo_controller.rb"
      ],
      "impacto": "Fala com o público: qualquer mudança precisa do \"aprovado\" do Eduardo antes de ir ao ar."
    }
  },
  "avisos_painel": {
    "o_que_faz": "Todo dia de manhã, manda e-mail ao cliente com as novidades do caso que o espelho da noite achou (sem número de processo) e manda à equipe um e-mail de resumo com, para cada novidade, o texto pronto de WhatsApp e o link wa.me — quem manda o WhatsApp é uma pessoa. HOJE ESTÁ DESLIGADO, até o Eduardo aprovar os textos.",
    "quando": "Todo dia às 08:00 (horário de Brasília), só com a chave PORTAL_AVISOS ligada no servidor.",
    "o_que_mexe": [
      "E-mail DIRETO ao cliente, sem revisão de uma pessoa.",
      "E-mail de resumo para a equipe (padrão: ramonantonio.comercial@gmail.com).",
      "Marca as novidades como avisadas."
    ],
    "travas": [
      "Desligado até aprovar os textos (PORTAL_AVISOS).",
      "Só cliente convidado e não suspenso; e-mail só se o cliente tem e-mail cadastrado.",
      "Etapa delicada (decisão, sentença, recurso julgado…) e etapa sem e-mail no dicionário nunca vão por e-mail: aparecem só no resumo da equipe, com texto neutro (\"Temos uma atualização no seu caso… Qual o melhor horário para ligarmos?\").",
      "Erro num cliente: as novidades dele ficam para o dia seguinte.",
      "Atenção: sem o e-mail (SMTP) configurado no servidor, as novidades são marcadas como avisadas mesmo sem nenhum e-mail sair."
    ],
    "por_que": "Decisão do Eduardo (08/10): fica no código. Fala direto com o cliente: a trava dos textos (PORTAL_AVISOS) e a regra das etapas delicadas não podem virar algo editável no quadro.",
    "mudar": {
      "pedido": "Peça ao Claude: \"os avisos do Painel passam a <mudança>\". Para LIGAR: aprove os textos e peça \"ligue os avisos do Painel\".",
      "arquivos": [
        "app/jobs/ramon/portal_avisos_job.rb",
        "app/mailers/ramon/portal_mailer.rb",
        "lib/ramon/portal_texto.rb",
        "config/ramon/portal_etapas_v2.yml"
      ],
      "impacto": "Fala com o cliente: textos e regras só entram com o \"aprovado\" do Eduardo. A assinatura do WhatsApp (\"Gabriela\") e o e-mail da equipe estão fixos no código."
    }
  },
  "resumo_do_dia": {
    "o_que_faz": "Todo dia de manhã manda o push \"Ramon Hub · seu dia\" com o que precisa de atenção hoje (tarefas vencidas, conversas fora do SLA, reunião ainda hoje, valor de benefício em jogo) e o e-mail de gestão aos administradores com os números de ontem (leads novos, ganhos, perdidos e tempo médio da 1ª resposta).",
    "quando": "Todo dia às 08:00 (horário de Brasília) — é o horário do fluxo, que você muda na tela.",
    "o_que_mexe": [
      "Push no celular (um tópico para a banca toda; só sai se o dia tem algo).",
      "E-mail aos administradores da conta (sai mesmo num dia sem pendências).",
      "Não grava nada."
    ],
    "travas": [
      "Push só com o ntfy configurado; e-mail só com o SMTP configurado.",
      "Casos de cálculo do ADVBOX ficam de fora.",
      "\"Em jogo\" = soma do valor MENSAL do benefício dos leads com tarefa vencida ou parados.",
      "Se o fluxo não começar (erro do motor ou a execução anterior ainda viva), o código faz naquele dia (reserva)."
    ],
    "por_que": "Roda pelo fluxo \"Resumo do dia\" (gatilho Horário da conta): você muda o horário e os dias, liga e desliga e pode pôr avisos antes ou depois. O conteúdo do push e do e-mail é a rotina pronta \"Resumo do dia\" (código).",
    "mudar": {
      "pedido": "Horário, dias e liga/desliga: no fluxo (botão abaixo). Conteúdo: peça ao Claude \"o resumo do dia passa a mostrar <dado>\".",
      "arquivos": [
        "app/services/ramon/daily_digest_service.rb",
        "app/jobs/ramon/daily_digest_job.rb",
        "app/mailers/administrator_notifications/ramon_digest_mailer.rb",
        "app/views/mailers/administrator_notifications/ramon_digest_mailer/daily_digest.html.erb"
      ],
      "impacto": "Mudar o fluxo vale na hora, sem deploy. Desligar o fluxo devolve o resumo ao código (às 08:00) — nunca fica sem."
    },
    "fluxos": ["resumo_do_dia"]
  },
  "lembretes_reuniao": {
    "o_que_faz": "Quando uma reunião é marcada (painel do lead ou Cal.com): registra no histórico, cria a tarefa da reunião, move o lead para Reunião agendada (só para a frente), escolhe o Closer se o lead não tem, deixa nas notas o rascunho de confirmação para o cliente e avisa a conta (sino e push). Depois lembra o Closer e o SDR 24h, 8h, 1h, 30 min e 5 min antes. Remarcar refaz o aviso e os lembretes; cancelar registra, apaga a tarefa e avisa.",
    "quando": "Na hora em que alguém marca, remarca ou cancela (painel do lead ou Cal.com); os lembretes, no horário de cada um (até 1 minuto de atraso).",
    "o_que_mexe": [
      "Histórico do lead (reunião agendada, remarcada, cancelada).",
      "Tarefa da reunião (vence na hora marcada), etapa e Closer.",
      "Rascunho de confirmação nas notas do lead (quem envia ao cliente é uma pessoa).",
      "Sino para a conta toda e push; lembretes para o Closer e o SDR (sem nenhum dos dois: os administradores)."
    ],
    "travas": [
      "Lembrete só sai se a reunião continua de pé naquele horário e o horário ainda não passou.",
      "Um ciclo de lembretes por reunião; remarcar cancela o ciclo antigo e recomeça.",
      "Lead com reunião aberta: marcar outra pede confirmação.",
      "Cal.com: só aviso com assinatura válida, e o mesmo aviso uma vez por dia; contato novo vira lead novo (origem calcom-agenda).",
      "Sem reserva pelo código: se o fluxo não começar (ex.: outra execução viva no mesmo lead), ninguém faz — confira em Execuções.",
      "Push só com o ntfy configurado."
    ],
    "por_que": "Roda por 3 fluxos seus: \"Reunião marcada\", \"Reunião cancelada\" e \"Lembretes de reunião\". Textos, avisos, quem recebe e os horários dos lembretes se editam na tela. Mover a tarefa no remarcar e a ligação com o Cal.com continuam no código.",
    "mudar": {
      "pedido": "Textos, avisos e lembretes: nos fluxos (botões abaixo). Regras do Cal.com ou do \"reunião de pé\": peça ao Claude \"<mudança>\".",
      "arquivos": [
        "app/services/ramon/reuniao_agendamento.rb",
        "app/services/ramon/fluxos/reunioes.rb",
        "app/controllers/public/api/v1/calcom_webhooks_controller.rb",
        "app/controllers/api/v1/accounts/lead_reunioes_agendadas_controller.rb"
      ],
      "impacto": "Mudar os fluxos vale na hora. Desligar qualquer um dos 3 devolve as reuniões ao código (os 3 juntos), com os textos antigos do código."
    },
    "fluxos": ["reuniao_marcada", "reuniao_cancelada", "lembretes_reuniao"]
  },
  "sla_primeira_resposta": {
    "o_que_faz": "Quando chega uma conversa nova numa caixa que cria lead, espera o prazo de 1ª resposta da caixa; se ninguém respondeu e a conversa segue aberta, avisa o SDR do lead (sem SDR: os administradores) no sino e no celular. Aos 60 minutos da chegada, se ainda sem resposta, avisa os administradores no sino.",
    "quando": "Conta a partir da criação da conversa: o prazo da caixa (padrão 5 minutos) e depois 60 minutos. Avisos só das 7h às 21h, todos os dias.",
    "o_que_mexe": [
      "Sino do SDR (ou dos administradores) e push \"Lead aguardando 1ª resposta\".",
      "Sino dos administradores na escalada dos 60 minutos (sem push)."
    ],
    "travas": [
      "Respondeu antes do prazo ou a conversa foi fechada: nada.",
      "Fora do horário pula o aviso, mas ainda faz a escalada se ela cair dentro do horário.",
      "Só conversa com lead.",
      "Se o fluxo não pegar a conversa (filtro editado, erro do motor), o código vigia aquela conversa (reserva).",
      "Push só com o ntfy configurado."
    ],
    "por_que": "Roda pelo fluxo \"SLA da 1ª resposta\": prazos, horário e quem recebe se editam na tela. O prazo de cada caixa vem do cadastro da caixa.",
    "mudar": {
      "pedido": "Prazos, horário e avisos: no fluxo (botão abaixo); o prazo de uma caixa: no cadastro da caixa. Outra regra: peça ao Claude \"<mudança>\".",
      "arquivos": [
        "app/listeners/ramon_lead_listener.rb",
        "app/jobs/ramon/first_response_sla_job.rb",
        "app/services/ramon/cadencia.rb"
      ],
      "impacto": "Mudar o fluxo vale na hora para as conversas novas. Desligar o fluxo devolve o SLA ao código (mesma regra, textos do código)."
    },
    "fluxos": ["sla_primeira_resposta"]
  },
  "cadencia": {
    "o_que_faz": "Todo dia às 11h, para cada lead parado que pode ser retomado, a IA escreve nas notas do lead o rascunho da retomada nº N (tom de médico de confiança; o ângulo muda a cada tentativa), conta a tentativa e cria a tarefa \"Retomada nº N\" para hoje com o Closer (sem Closer: o SDR). Um push por dia avisa que há rascunhos para revisar. O botão \"Preparar retomada\" do painel do lead faz o mesmo só para aquele lead.",
    "quando": "Todo dia a partir das 11:00 (horário de Brasília); se o hub estava fora do ar, quando voltar, no mesmo dia. O botão, na hora.",
    "o_que_mexe": [
      "Rascunho nas notas do lead (quem envia ao cliente é uma pessoa).",
      "Contador de tentativas do lead.",
      "Tarefa de retomada para hoje.",
      "Push \"Retomadas prontas pra revisar\" (um por dia)."
    ],
    "travas": [
      "Só lead parado (há mais dias na etapa do que o limite da etapa), com conversa, sem tarefa de retomada aberta e com a última retomada há 5 dias ou mais.",
      "Até 15 por dia (o limite do fluxo; as do botão contam nesse limite).",
      "Se a IA falhar, entra o texto fixo de retomada; a cota de IA dos fluxos é de 200 por dia.",
      "Regras da OAB no texto: sem prometer resultado nem prazo.",
      "Sem reserva pelo código: com o fluxo ligado, o código não faz o lote."
    ],
    "por_que": "Roda pelo fluxo \"Cadência de retomada\" (gatilho Lead parado): horário, limite do dia, texto da IA e avisos se editam na tela.",
    "mudar": {
      "pedido": "Horário, limite, texto e avisos: no fluxo (botão abaixo). Quem pode ser retomado (5 dias, tarefa aberta): peça ao Claude \"<mudança>\".",
      "arquivos": [
        "app/services/ramon/fluxos/retomada.rb",
        "app/services/ramon/fluxos/relogio.rb",
        "app/jobs/ramon/daily_follow_up_job.rb",
        "app/services/ramon/follow_up_draft_service.rb"
      ],
      "impacto": "Mudar o fluxo vale no próximo lote. Desligar o fluxo devolve a cadência ao código (lote das 11h, texto do código)."
    },
    "fluxos": ["cadencia"]
  },
  "lead_ganho": {
    "o_que_faz": "Quando o lead vira ganho, faz em sequência: o dossiê de passagem para o jurídico (nota \"📋 DOSSIÊ\" no lead), o rascunho da pesquisa NPS nas notas (com o link do Google) e a abertura do caso no ADVBOX (cliente, processo na etapa CONTRATO FECHADO e a tarefa 1º CONTATO COM O LEAD). À parte, o código exporta ao Drive os documentos já conferidos.",
    "quando": "Na hora em que o lead entra numa etapa de ganho (inclusive pelo evento \"contrato fechado\" do ADVBOX). Lead criado já ganho não dispara.",
    "o_que_mexe": [
      "Nota do dossiê e rascunho da NPS no lead.",
      "ADVBOX: cliente, processo (tipo pela tese, valor do caso) e tarefa — grava de verdade.",
      "Drive (pelo código): documentos recebidos e, quando o checklist fecha, a pasta \"— COMPLETO\" e a tarefa de documentos no ADVBOX.",
      "Balão \"⚙ Fluxo Lead ganho\" na conversa."
    ],
    "travas": [
      "Cada passo confere antes se o lead ainda está ganho.",
      "Dossiê não se repete em 5 minutos; NPS do ganho uma vez só (a do êxito é outra); caso no ADVBOX uma vez só e só com o token do ADVBOX.",
      "ADVBOX fora do ar: o fluxo tenta de novo em 1, 5 e 15 minutos; recusa fica anotada no lead.",
      "Se o fluxo não começar, o código faz (reserva)."
    ],
    "por_que": "Roda pelo fluxo \"Lead ganho\": ordem, avisos e passos extras se editam na tela. Dossiê, NPS e ADVBOX são rotinas prontas (código). O Drive ficou no código porque roda a cada atualização dos documentos, não só no ganho.",
    "mudar": {
      "pedido": "Ordem e passos extras: no fluxo (botão abaixo). Texto do dossiê ou da NPS, ou os dados enviados ao ADVBOX: peça ao Claude \"<mudança>\".",
      "arquivos": [
        "app/services/ramon/fluxos/lead_ganho.rb",
        "app/services/ramon/fluxos/passos/rotina.rb",
        "app/services/ramon/advbox_closing_service.rb",
        "app/services/ramon/drive_export_service.rb"
      ],
      "impacto": "Grava no ADVBOX de verdade. Desligar o fluxo devolve tudo ao código (as 3 ações em paralelo, como antes)."
    },
    "fluxos": ["lead_ganho"]
  },
  "eventos_advbox": {
    "o_que_faz": "Quando o Flowter do ADVBOX avisa uma mudança de etapa ou tarefa num processo, o hub acha o lead (pelo CPF ou pelo telefone) e faz o que a regra daquela etapa manda: contrato fechado marca o lead como ganho; protocolo, decisão, exigência, indeferimento, benefício futuro, êxito, concessão e marcos viram histórico, tarefas de acompanhamento, rascunhos ao cliente nas notas e push; arquivado conclui as tarefas abertas do lead.",
    "quando": "Na fila, segundos depois do aviso do Flowter.",
    "o_que_mexe": [
      "Histórico do lead (um tipo para cada regra).",
      "Tarefas com prazo (45 dias no protocolo, 1 no indeferimento, 2 na decisão e na exigência, 180 no benefício futuro), com o Closer (sem Closer: o SDR).",
      "Rascunhos nas notas (INSS negou, exigência, êxito, concessão) e a pesquisa NPS de êxito — nada vai direto ao cliente.",
      "Etapa de ganho no contrato fechado (o que dispara o Lead ganho).",
      "Push por regra (sem sino)."
    ],
    "travas": [
      "Só aceita aviso com o token combinado; o mesmo aviso repetido não roda duas vezes.",
      "O nome da etapa precisa bater exatamente com a lista de cada regra; sem regra ou sem lead, o evento fica guardado e nada roda.",
      "Lead escolhido: o aberto do contato; senão, o mais recente do funil (pode ser ganho ou perdido).",
      "NPS de êxito uma vez só por lead.",
      "Se o fluxo não começar (ex.: outra execução viva no mesmo lead), o código faz aquele evento (reserva).",
      "Erro no processamento: o evento fica com situação \"erro\", sem nova tentativa."
    ],
    "por_que": "Roda pelo fluxo \"Eventos do ADVBOX\": textos, tarefas, prazos e avisos de cada regra se editam na tela. Achar a regra e o lead continua no código.",
    "mudar": {
      "pedido": "Textos, prazos e avisos: no fluxo (botão abaixo). Nome de etapa novo no ADVBOX ou outra forma de achar o lead: peça ao Claude \"<mudança>\".",
      "arquivos": [
        "app/services/ramon/advbox_event_processor.rb",
        "app/services/ramon/fluxos/eventos_advbox.rb",
        "app/services/ramon/advbox_event_regras.rb",
        "app/controllers/public/api/v1/advbox_webhooks_controller.rb"
      ],
      "impacto": "Mudar o fluxo vale no próximo evento. Etapa nova no ADVBOX só é reconhecida depois de o Claude acrescentar o nome na lista."
    },
    "fluxos": ["eventos_advbox"]
  },
  "chegada_cliente": {
    "o_que_faz": "Quando a recepção avisa no hub que um cliente chegou e, em 3 minutos, ninguém respondeu o aviso, o alerta volta a tocar na tela de quem avisou (\"sem resposta\") até a pessoa clicar \"Entendi\".",
    "quando": "3 a 4 minutos depois do aviso de chegada (o relógio dos fluxos anda de minuto em minuto).",
    "o_que_mexe": [
      "Marca a chegada como escalada e faz o alerta tocar ao vivo na tela de quem avisou (não é sino nem push)."
    ],
    "travas": [
      "Só escala se ninguém respondeu e se ainda não foi escalada (uma vez só).",
      "Se o fluxo não começar, o código escala em exatos 3 minutos (reserva).",
      "Falha do fluxo: só o push \"Fluxo falhou\" (a chegada não tem lead)."
    ],
    "por_que": "Roda pelo fluxo \"Chegada de cliente\": o tempo de espera e avisos extras se editam na tela. A escalada em si é a rotina pronta \"Escalar a chegada\" (código).",
    "mudar": {
      "pedido": "Tempo e avisos: no fluxo (botão abaixo). Quem recebe o alerta ou como ele toca: peça ao Claude \"<mudança>\".",
      "arquivos": [
        "app/models/chegada.rb",
        "app/controllers/api/v1/accounts/ramon_chegadas_controller.rb",
        "app/jobs/ramon/chegada_escalar_job.rb",
        "app/javascript/dashboard/stores/chegadas.js"
      ],
      "impacto": "Mudar o fluxo vale para os próximos avisos. Desligar o fluxo devolve a escalada ao código (3 minutos)."
    },
    "fluxos": ["chegada_cliente"]
  }
}
```
