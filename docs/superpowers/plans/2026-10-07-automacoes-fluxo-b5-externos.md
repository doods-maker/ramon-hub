# Automações em fluxo — B5-externos (assinatura e documento do Painel, contrato no ZapSign, chegada de cliente, ata da reunião, acervo das peças) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## Decisões para o Eduardo

(O controlador pergunta num formulário. Cada uma muda algo visível ou o risco; o resto está em "Escolhas técnicas".)

- **N1 — Chegada de cliente: o alerta "ninguém respondeu" pode tocar até 1 minuto mais tarde.** Hoje ele toca exatamente 3 min depois do aviso. Pelo fluxo, a espera de 3 min é a do motor, que confere as esperas de minuto em minuto: o alerta toca entre 3 e 4 min.
  - (a) Aceitar: 3 a 4 min, com a espera editável na tela. **← recomendado**
  - (b) Manter os 3 min exatos: o fluxo só decide e o código agenda a espera (a espera não aparece no desenho, nem dá para mudar na tela).
- **N2 — Contrato no ZapSign: o aviso continua o mesmo de hoje.** O selo no card do lead ("assinado"/"recusado") e a conferência no ZapSign ficam no código: são o evento em si e a trava que impede repetir. O fluxo faz a linha no histórico e o sino para todos.
  - (a) Sino e histórico como "rotina pronta" (o mesmo texto e o mesmo tipo de sino de hoje, "Contrato de X assinado no ZapSign"; quem desligou esse sino nas preferências continua sem ele). **← recomendado**
  - (b) Passos editáveis (histórico + sino com texto livre). O sino passa a ser "Automação: … (X)" e segue a preferência "Aviso de automação", não a de contrato.
- **N3 — Trabalho pesado continua na fila de hoje.** Transcrição e ata da reunião, Drive, ADVBOX, ZapSign e Notion: o fluxo *pede* ao mesmo job de hoje e segue. A trilha diz "pedido", não "feito"; as novas tentativas continuam as do código (ata 3×, ZapSign 5×, documento do Painel 5×, Drive 3×) e uma falha aparece onde aparece hoje (reunião com "erro" e o botão Refazer; log), não como "falhou" na tela de fluxos. Um passo que o senhor puser depois da rotina roda logo, sem esperar a ata ficar pronta.
  - (a) Aceitar. **← recomendado** (a transcrição de uma reunião longa passa de 10 min; o motor daria a execução por travada e transcreveria de novo)
  - (b) Rodar dentro do fluxo: falhas visíveis na tela de fluxos, mas risco de transcrever 2 vezes e tentativas diferentes das de hoje.
- **N4 — Teste ao vivo depois de virar as chaves.** Chegada e ata pela tela de verdade (o senhor avisa uma chegada para si mesmo e grava 10 s numa reunião). Os outros 4 com registros de teste e travas — nada vai ao ADVBOX nem ao ZapSign. Saem 3 coisas reais: (1) um sino "Contrato de Teste B5 assinado no ZapSign" para todos da conta (apagado na limpeza, minutos depois); (2) um push no seu celular ("Documento do cliente TESTE B5"); (3) uma pasta "… — TESTE B5" no Drive, em Posts Instagram/Carrossel, para o senhor apagar.
  - (a) Aceitar. **← recomendado**
  - (b) Pular o teste ao vivo do contrato e do Drive (só ensaio na tela) — nada sai, mas esses dois só serão vistos no 1º evento real.
- **N5 — Ritmo de virada.** São 6 chaves independentes (uma por automação). O "Testar com um lead…" não serve em 5 delas (o alvo não é lead: é a chegada, a reunião gravada, a peça, a assinatura ou o documento do Painel).
  - (a) Direto, como B4.2–B4.5: deploy, criar, virar e teste ao vivo no mesmo dia. **← recomendado**
  - (b) Deixar 1–2 dias em sombra (os fluxos só ensaiam nos eventos reais; o senhor confere as execuções e depois vira).

---

**Goal:** As 6 automações do código que começam **fora do funil** — conferência da **assinatura pelo Painel do Cliente** (webhook do ZapSign), **histórico e sino do contrato no ZapSign**, **documento enviado pelo Painel** (Drive + push + 2 tarefas no ADVBOX), **escalada da chegada de cliente** (3 min), **ata da reunião gravada** (whisper + IA) e **acervo das peças** (Drive depois de publicar + espelho no Notion) — viram **8 fluxos de verdade**, cada automação com a **chave da B4.1** (env própria + os fluxos do grupo em modo normal ⇒ o fluxo faz e o código para; qualquer peça fora ⇒ o código faz). As chaves nascem **desligadas**: nada muda em produção até o Eduardo virar.

**Architecture:** Um módulo só, `Ramon::Fluxos::Externos`, guarda os 6 grupos (mesclados em `Migracao::GRUPOS`) e a decisão de todos os pontos do código: `Externos.evento(grupo, gatilho, alvo, dados) { código de hoje }` lê `assumiu?` **uma vez**, dispara o fluxo migrado com `assumido`, roda o bloco se o fluxo não está no comando **ou não começou este evento** (reserva — nunca nenhum, nunca dois) e por fim dispara os fluxos comuns do gatilho, sem a decisão. O **alvo é o registro do evento** (`PortalAssinatura`, `PortalEnvio`, `Chegada`, `Reuniao`, `Peca`; o contrato é do lead) — o motor ganha `FluxoExecucao.lead_de`, que nunca adivinha lead pelo id de um alvo que não é conversa. A lógica de dentro vira **7 rotinas prontas** em `app/services/ramon/fluxos/rotinas/externos.rb` (registro de rotinas da B5-conta) que chamam **o mesmo código de hoje**: os pesados pedem o mesmo job (`perform_later`), a chegada escala depois de uma **espera do motor** de 3 min, o sino do contrato é o mesmo método do job. 6 gatilhos novos; o contrato reusa `contrato_assinado`/`contrato_recusado` (B2b). Sem migração de banco.

**Tech Stack:** Rails 7.1 / RSpec (só no CI), Postgres jsonb, Sidekiq (ActiveJob), ActionCable (alerta da chegada, inalterado); Vue 3.5 `<script setup>`, vue-i18n 9, Vitest 3.

**Spec:** `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (§4 peças, §6 motor — índice único, relógio a cada minuto, órfã de 10 min; §8 migração; §14 notas da B3 — os desenhos `sistema/*.json`; §15–§18 — a chave, "a decisão é do evento", reserva, `rotina`). Desenhos atuais (o que o código faz): `db/seeds/ramon/fluxos/sistema/{assinatura_painel,contrato_zapsign,documento_painel,chegada_cliente,ata_reuniao,acervo_pecas}.json` (campo `descricao`). Plano modelo: `docs/superpowers/plans/2026-10-07-automacoes-fluxo-b44-ganho-advbox.md`.

## Escopo decidido pelo Eduardo (07/10 — herdado da B4.2 + briefing B5)

1. **E1 — direto, sem sombra nem comparação** (salvo N5-b): criar logo depois do deploy, virar, teste ao vivo.
2. **E2 — uma chave por automação:** `RAMON_FLUXO_ASSINATURA_PAINEL`, `RAMON_FLUXO_CONTRATO_ZAPSIGN`, `RAMON_FLUXO_DOCUMENTO_PAINEL`, `RAMON_FLUXO_CHEGADA`, `RAMON_FLUXO_ATA_REUNIAO`, `RAMON_FLUXO_ACERVO_PECAS` =on **e** os fluxos do grupo ligados, publicados, em modo normal, sem limite do dia e com o gatilho certo. Voltar = rake `modo …,sombra`, sem deploy.
3. **E3 — textos internos podem mudar** (balão "⚙ Fluxo …", trilha).
4. **E4 — nada fala com o cliente:** nenhum destes 6 manda mensagem; nenhum passo livre de "enviar ao cliente" entra.
5. **E5 — nada grava fora do hub sem a garantia de hoje:** ADVBOX (documento do Painel), ZapSign, Drive e Notion seguem pelos jobs de hoje, com as mesmas travas e tentativas.
6. **E6 — depois de assumir, editáveis por admin.**
7. **E7 — limpeza em outro PR, 2 semanas depois em normal:** os JSON `sistema/<x>.json` **e** as linhas `origem: sistema` deles, os blocos de código-reserva que o Eduardo decidir apagar, as envs. Neste PR eles ficam.

## Escolhas técnicas (decididas no plano)

- **Alvo de cada fluxo** (índice único parcial `(fluxo, alvo_type, alvo_id)` para execução viva não-ensaio): assinatura → `PortalAssinatura`; documento → `PortalEnvio` (não o `PortalCliente`: dois envios seguidos do mesmo cliente seriam barrados); chegada → `Chegada`; ata → `Reuniao` (gravar e refazer: a execução da 1ª já terminou quando o Refazer aparece); acervo → `Peca`; contrato → `Lead` (como hoje). Dois eventos colados no mesmo registro (status da peça em rajada, webhook repetido) → o 2º cai na **reserva** (o código faz aquele), nunca some.
- **Grupos com 2 fluxos** (1 gatilho por fluxo): `contrato_zapsign` = `contrato_zapsign_assinado` (`contrato_assinado`) + `contrato_zapsign_recusado` (`contrato_recusado`); `acervo_pecas` = `acervo_pecas_drive` (`peca_publicada`, o ponto de hoje: `PublicarPecasJob#pos_publicacao`) + `acervo_pecas_notion` (`peca_mudou_status`, o ponto de hoje: `Peca` `after_update_commit` + a chamada explícita depois de `update_columns`). Cada ponto do código tem a sua decisão (um gatilho único com `se status = publicado` exigiria duas leituras da chave para o mesmo evento).
- **Gatilhos novos (6):** `assinatura_painel`, `documento_painel`, `chegada_cliente`, `reuniao_gravada` (`{evento}` = `gravada`|`refazer`), `peca_publicada`, `peca_mudou_status` (`{evento}` = o status novo). O `documento_recebido` da B2b é outro evento (a IA casou um anexo do lead) — não é o envio do Painel.
- **O selo do ZapSign fica no código** (`ZapsignLeadStatusJob`: conferência HTTP + `custom_attributes.zapsign.status`) — é o evento e a trava `atual?`. Só histórico + sino migram (N2).
- **Pesados pedem o mesmo job** (N3): `ZapsignStatusJob`, `PortalEnvioJob`, `ReuniaoAtaJob`, `ConteudoDriveJob`, `NotionEspelhoJob` via `perform_later`. Motivo duro: `Ramon::FluxoRelogioJob` devolve à fila a execução `rodando` há mais de 10 min — rodar o whisper de uma reunião longa dentro do passo repetiria a transcrição.
- **`FluxoExecucao.lead_de(alvo)`** substitui o `else` de `FluxoExecucao#lead` e de `Disparo#lead_do_alvo`, que tratava qualquer alvo como conversa (`leads.where(conversation_id: alvo.id)`) — com uma `Chegada` de id 42 acharia o lead da conversa 42 (balão e sino no cliente errado). `Reuniao` com lead vinculado → o lead (balão "⚙ Fluxo Ata da reunião: …" na conversa dele, E3); chegada, peça e Painel → sem lead.
- **`alvo_nome`** dos alvos de fora do funil leva o que é ("Chegada: Maria", "Peça: …", "Reunião gravada: …", "Assinatura do Painel: …", "Documento do Painel: …") — a lista e a tela de execução não têm outra coluna.
- **`PortalAssinatura`/`PortalEnvio` ganham `delegate :account, to: :portal_cliente`** (o `Disparo` lê `alvo.account`).
- **Grupos em `Ramon::Fluxos::Externos::GRUPOS`**, mesclados no fim de `Migracao::GRUPOS` (`}.merge(Ramon::Fluxos::Externos::GRUPOS).freeze`): `migracao.rb` tem 69 linhas de código (limite de módulo 100) e as irmãs também acrescentam grupos; e o rebase fica numa linha. `Disparo::DUAS_VEZES` soma `Externos.gatilhos` (derivado, sem lista repetida).
- **Pequenas extrações para a rotina chamar o MESMO código:** `Chegada#escalavel?`/`#escalar!` (o `ChegadaEscalarJob` passa a chamar), `Ramon::ZapsignLeadStatusJob.avisar(lead, status)` (público), `Peca#espelhar_notion` público (o `PublicarPecasJob` chama no lugar do `NotionEspelhoJob` direto).
- **"Testar com um lead…"** nos 5 de alvo não-lead: a rotina falha na hora dizendo com o que ela roda (`PassoImpossivel`); o painel do gatilho explica (`ALVO_OUTRO_AJUDA`). Conferência = execuções dos eventos reais (sombra) e o teste ao vivo.

## Global Constraints

- **Ordem de merge: B5-conta → B5-leads → B5-externos.** Esta fatia roda **por último**, rebaseada nas duas (Task 0). Branch `feat/fluxos-b5-externos`, worktree `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-intel-a3` (o nome da pasta é antigo). Base escrita contra `origin/ramon` **0a31e02** (B1–B4.5 no ar). Nunca `git push`, nunca abrir PR, nunca `git stash`, nunca `git add -A`.
- **Depende de B5-conta (registro de rotinas por arquivo).** Formato assumido (o controlador concilia se a B5-conta escolher outro):
  - cada plano tem `app/services/ramon/fluxos/rotinas/<plano>.rb` com `module Ramon::Fluxos::Rotinas::<Plano>`, uma constante `ROTINAS = %w[...]` e, para cada nome, um **método de módulo `nome(ctx) → String`** (o resumo da trilha; `ctx` = `Ramon::Fluxos::Contexto`; ensaio via `ctx.ensaio?`, só descreve; erro passageiro sobe; erro de configuração = `Ramon::Fluxos::PassoImpossivel`);
  - a B5-conta mantém uma lista `Ramon::Fluxos::Rotinas::MODULOS` (ou equivalente) e o `Ramon::Fluxos::Passos::Rotina.rotina(config, ctx)` acha o módulo cuja `ROTINAS` contém o nome **antes** de exigir lead e devolve `{ saida: 's', resumo: modulo.public_send(nome, ctx) }`; `Passos::Rotina::ROTINAS` (o espelho do front) inclui as dos módulos;
  - esta fatia só **acrescenta `Ramon::Fluxos::Rotinas::Externos` no fim** dessa lista e as 7 rotinas no fim de `ROTINAS` do front.
- **Produção não muda até o Eduardo virar.** Com as 6 envs ausentes/`off` (padrão) e sem rodar o rake `criar`, cada ponto faz exatamente o de hoje (os specs existentes desses pontos continuam verdes sem mudança, salvo o do contrato, que só troca o stub de `Disparo.externo`).
- **Sem migração.** `ramon_fluxo_execucoes.alvo_type/alvo_id` já é polimórfico (string). Se alguma task achar que precisa de coluna/índice: pare e pergunte.
- **Rubocop do fork** (o CI barra): AbcSize 26, MethodLength 19, Cyclomatic 7, Perceived 8, ClassLength 175, ModuleLength 100, BlockLength 30 (inclui `.rake`), linha 150, `Style/HashSyntax` `EnforcedShorthandSyntax: never`, `Layout/EmptyLineAfterGuardClause`, `RSpec/ContextWording` (só when/with/without — use `describe`), `RSpec/SortMetadata`, `Style/StringLiterals`, `RSpec/MultipleExpectations` 7, `RSpec/SpecFilePathFormat` (spec de `Ramon::Fluxos::Rotinas::Externos` em `spec/services/ramon/fluxos/rotinas/externos_spec.rb`), `RSpec/LeakyConstantDeclaration`. Tamanhos na base 0a31e02 (linhas de código): `disparo.rb` 98, `grafo.rb` 157, `migracao.rb` 69 (módulo), `fluxo_execucao.rb` 27, `peca.rb` 36, `publicar_pecas_job.rb` 57, `cliente/painel_controller.rb` 117, `ramon_reunioes_controller.rb` 84.
- **CI FOSS apaga `enterprise/`:** esta fatia não toca Captain.
- **Sem Ruby local:** specs Ruby escritos e conferidos à mão; quem valida é o CI. **1 execução viva não-ensaio por (fluxo, alvo) por exemplo** — `create!` sem status nasce `rodando` (default do schema) e conta para o índice; `travel`/`travel_to` em blocos em sequência, nunca aninhados; **`with_modified_env` nunca aninhado** (junte as envs num bloco só); notificações = 1 linha por pessoa por chamada (nunca somar entre chamadas); `.pluck.uniq` em vez de `.distinct.pluck`; código nunca usa `NOW()` do SQL. Stub de `Ramon::Fluxos::Disparo.externo` **tem de devolver `[]`** (o `evento` chama `.any?`).
- **Front:** i18n só dentro de `CAPTAIN_RAMON.FLUXOS` em `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json`, chaves novas na **mesma posição** nos dois (a trava `specs/i18n.spec.js` compara a ordem, cobre o catálogo e compila no vue-i18n de produção); sem `@`, `|`, `{`, `}` crus nas strings; editar com Edit. Tailwind only, sem texto cru no template.
- **Vitest:** `TZ=UTC npx vitest run <arquivos ou pastas> --config vitest.local.config.ts` (config local fora do git; se não existir na worktree, copiar de `..\ramon-hub-wt-fluxos-b44\vitest.local.config.ts`, sem commitar; `node_modules` = junção para `ramon-hub-wt-fluxos-b2\node_modules`). ESLint: `./node_modules/.bin/eslint <arquivos>` (`Delete ␍` = CRLF do checkout, ignorar; warnings `@intlify/vue-i18n/no-dynamic-keys` já existem).
- **Commits:** Conventional Commits em pt-BR, sem citar Claude no assunto; corpo termina com
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR`
  Commitar só os caminhos da task (`git add <arquivos>`).
- **Pontos de conflito com B5-conta/B5-leads (acréscimos só no fim):** `migracao.rb` (fim de `GRUPOS`), `disparo.rb` (`DUAS_VEZES`, `lead_do_alvo`), `fluxo_execucao.rb` (`lead`), `grafo.rb` (`GATILHOS`), `passos/rotina.rb` + registro de rotinas, `.env.example`, `fluxo.js` (`GATILHOS`, `ROTINAS`), `ConfigGatilho.vue`, os dois `ramon.json`, `specs/migrados.spec.js`, a spec (seção de notas). **A B5-conta também mexe no `else` de `lead_do_alvo`/`FluxoExecucao#lead`** (alvo = a conta): se já o trocou, só acrescente os ramos desta fatia (`Reuniao`, e nunca adivinhar por id).

## Review Focus

1. **Alvo de fora do funil confundido com conversa** (uma `Chegada`/`Peca` com o mesmo id de uma conversa) — o motor não pode achar o lead daquela conversa (balão, sino, "saiu da etapa" no cliente errado). Teste: Task 1 (`FluxoExecucao.lead_de` com `Chegada.new(id: conversa.id)`; `Disparo` com chegada de id igual ao da conversa do lead).
2. **Rajada no mesmo registro** (peça `agendado → publicando → publicado` no mesmo job; webhook do ZapSign repetido) — o 2º evento bate no índice único; tem de ir pelo código (reserva), nem sumir nem dobrar. Teste: Task 3 ("ocupado com o mesmo alvo… o código faz este evento") e Task 6 (publicar: 1 execução do espelho + a reserva).
3. **Chegada respondida dentro dos 3 min, ou já escalada** — a espera do motor acorda e não pode escalar. Teste: Task 2 ("respondida dentro dos 3 min: não escala"; "já escalada… não mexe").
4. **Grupo de 2 fluxos com um desligado na tela / em sombra** — os dois pontos do código voltam ao código na hora (sem buraco). Teste: Task 3 ("grupo de 2 fluxos… um desligado").
5. **Ata que falha com o fluxo no comando** — a reunião tem de ficar "erro" com o botão Refazer, e o Refazer tem de criar execução nova (não barrada). Teste: Task 2 (a rotina pede o mesmo `ReuniaoAtaJob`, que marca o erro como hoje) e Task 5 (Refazer com o fluxo no comando cria a execução com `{evento} = refazer`).

---

## O que o código faz × o que o fluxo faz

| Automação (grupo, env) | Ponto do código hoje | Fica no código (o evento em si) | Fluxo (no comando) |
|---|---|---|---|
| Assinatura pelo Painel (`assinatura_painel`, `RAMON_FLUXO_ASSINATURA_PAINEL`) | `Public::Api::V1::ZapsignWebhooksController#create` → `ZapsignStatusJob` | achar a assinatura pelo `doc_token` | gatilho `assinatura_painel` (alvo `PortalAssinatura`) → rotina `conferir_assinatura_painel` (= `ZapsignStatusJob.perform_later`) |
| Contrato no ZapSign (`contrato_zapsign`, `RAMON_FLUXO_CONTRATO_ZAPSIGN`) | `ZapsignLeadStatusJob#perform` (webhook e `ZapsignContractService`) | conferir no ZapSign + selo `zapsign.status`/data + trava `atual?` | gatilhos `contrato_assinado` / `contrato_recusado` (alvo `Lead`, 2 fluxos) → rotina `aviso_contrato` (= `ZapsignLeadStatusJob.avisar`: histórico `zapsign_*` + sino `ramon_contract_status` a todos) |
| Documento enviado pelo Painel (`documento_painel`, `RAMON_FLUXO_DOCUMENTO_PAINEL`) | `Cliente::PainelController#enviar` → `PortalEnvioJob` | gravar o envio + anexar o arquivo | gatilho `documento_painel` (alvo `PortalEnvio`) → rotina `processar_envio_painel` (= `PortalEnvioJob.perform_later`: Drive → push → 2 tarefas no ADVBOX, idempotentes, 5 tentativas) |
| Chegada de cliente (`chegada_cliente`, `RAMON_FLUXO_CHEGADA`) | `RamonChegadasController#create` → `ChegadaEscalarJob` em 3 min | criar a chegada (o alerta ao vivo é o `after_create_commit` do model) | gatilho `chegada_cliente` (alvo `Chegada`) → `esperar 3 minutos` → rotina `escalar_chegada` (= `Chegada#escalar!`; o `after_update_commit` transmite e o alerta volta ao vivo) |
| Ata da reunião (`ata_reuniao`, `RAMON_FLUXO_ATA_REUNIAO`) | `RamonReunioesController#create`/`#reprocessar` → `ReuniaoAtaJob` | gravar a reunião/anexar o áudio; Refazer volta o status para `transcrevendo` | gatilho `reuniao_gravada` (alvo `Reuniao`, `{evento}` gravada/refazer) → rotina `escrever_ata` (= `ReuniaoAtaJob.perform_later`) |
| Acervo das peças (`acervo_pecas`, `RAMON_FLUXO_ACERVO_PECAS`) | `PublicarPecasJob#pos_publicacao` → `ConteudoDriveJob`; `Peca#espelhar_notion` (callback) e `PublicarPecasJob#no_ar_apos_erro` → `NotionEspelhoJob` | a publicação e as transições da peça | `peca_publicada` → rotina `acervo_drive` (= `ConteudoDriveJob.perform_later`); `peca_mudou_status` (`{evento}` = status) → rotina `espelho_notion` (= `NotionEspelhoJob.perform_later`) |

## Mapa de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `app/models/fluxo_execucao.rb` | `FluxoExecucao.lead_de(alvo)` (nunca adivinha por id) e `alvo_nome` dos alvos de fora do funil |
| `app/services/ramon/fluxos/disparo.rb` | `lead_do_alvo` usa `lead_de`; `DUAS_VEZES` soma `Externos.gatilhos` |
| `app/services/ramon/fluxos/grafo.rb` | 6 gatilhos novos em `GATILHOS` |
| `app/models/portal_assinatura.rb`, `app/models/portal_envio.rb` | `delegate :account, to: :portal_cliente` |
| `app/services/ramon/fluxos/rotinas/externos.rb` (novo) | as 7 rotinas prontas (registro da B5-conta) |
| `app/services/ramon/fluxos/passos/rotina.rb` (ou o registro da B5-conta) | acrescentar `Ramon::Fluxos::Rotinas::Externos` à lista de módulos |
| `app/services/ramon/fluxos/externos.rb` (novo) | `GRUPOS` (6), `gatilhos`, `evento` (a decisão do evento + reserva + comuns) |
| `app/services/ramon/fluxos/migracao.rb` | `GRUPOS` mescla `Externos::GRUPOS` |
| `db/seeds/ramon/fluxos/migrados/{assinatura_painel,contrato_zapsign_assinado,contrato_zapsign_recusado,documento_painel,chegada_cliente,ata_reuniao,acervo_pecas_drive,acervo_pecas_notion}.json` (novos) | os 8 desenhos |
| `app/models/chegada.rb`, `app/jobs/ramon/chegada_escalar_job.rb` | `escalavel?`/`escalar!`; o job chama |
| `app/jobs/ramon/zapsign_lead_status_job.rb` | `self.avisar(lead, status)`; decisão pelo `evento` |
| `app/controllers/public/api/v1/zapsign_webhooks_controller.rb`, `app/controllers/cliente/painel_controller.rb`, `app/controllers/api/v1/accounts/ramon_chegadas_controller.rb`, `app/controllers/api/v1/accounts/ramon_reunioes_controller.rb` | o job de hoje passa a ser o bloco do `evento` |
| `app/models/peca.rb`, `app/jobs/ramon/publicar_pecas_job.rb` | `espelhar_notion` público pelo `evento`; Drive pelo `evento` |
| `.env.example` | as 6 envs (desligadas) |
| `app/javascript/dashboard/routes/dashboard/captain/automacoes/{fluxo.js,ConfigGatilho.vue}` + i18n `{en,pt_BR}/ramon.json` | gatilhos e rotinas no editor; aviso "não é de lead" |
| `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` | seção "Notas da B5-externos" |

---

### Task 0: Alinhar com a B5-conta e a B5-leads (rebase + registro de rotinas + baselines) — julgamento

**Files:** nenhum de código (só rebase). Sem commit, salvo conflito no próprio plano.

**Interfaces:**
- Produces: o nome real do registro de rotinas da B5-conta (aplicar nas Tasks 2 e 7); se a B5-conta/B5-leads já mexeram em `lead_do_alvo`/`FluxoExecucao#lead`, `DUAS_VEZES`, `GRUPOS`; baseline **B** do Vitest; tamanhos atuais.

- [ ] **Step 1: As duas irmãs estão em `origin/ramon`?**

```bash
git fetch origin
git log --oneline origin/ramon -10
```
Expected: commits da B5-conta e da B5-leads acima de `0a31e02`. **Se a B5-conta não estiver lá: pare e avise o controlador** (o passo `rotina` desta fatia depende do registro dela).

- [ ] **Step 2: Rebase**

```bash
git status --short          # só o vitest.local.config.ts (fora do git) pode aparecer
git rebase origin/ramon     # a branch só tem o commit deste plano
```
Expected: sem conflito.

- [ ] **Step 3: Conferir o registro de rotinas e os pontos compartilhados**

```bash
ls app/services/ramon/fluxos/ app/services/ramon/fluxos/rotinas/
sed -n 1,40p app/services/ramon/fluxos/passos/rotina.rb
grep -rn "MODULOS\|module Ramon::Fluxos::Rotinas" app/services/ramon/fluxos
grep -n "DUAS_VEZES\|def lead_do_alvo" -A6 app/services/ramon/fluxos/disparo.rb
grep -n "def lead\b\|def self.lead_de" -A8 app/models/fluxo_execucao.rb
grep -n "freeze$" app/services/ramon/fluxos/migracao.rb | head -3
grep -n "export const ROTINAS" -A30 app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js
```
- Anote o nome da lista de módulos de rotina e a assinatura que a B5-conta usa. **Se for diferente** do formato da seção Global Constraints (ex.: rotina recebe `(alvo, ensaio)` em vez de `(ctx)`), ajuste as Tasks 2 e 7 ao formato dela (é mecânico: os corpos das rotinas não mudam, só a assinatura e o lugar do registro).
- Se `lead_do_alvo`/`FluxoExecucao#lead` já não têm o `else` que trata o alvo como conversa, a Task 1 só acrescenta os ramos (`Reuniao`) e o `lead_de`.
- Se `Migracao::GRUPOS` já termina com um `.merge(...)` de outra irmã, a Task 3 encadeia o nosso depois dele.

- [ ] **Step 4: Baselines**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts
for f in app/services/ramon/fluxos/disparo.rb app/services/ramon/fluxos/grafo.rb app/services/ramon/fluxos/migracao.rb app/models/fluxo_execucao.rb app/models/peca.rb app/controllers/cliente/painel_controller.rb; do echo "$f $(grep -cvE '^\s*(#|$)' $f)"; done
```
Expected: Vitest verde — anote arquivos/testes como **B**. Se `grafo.rb` passar de 170 linhas de código, avise antes da Task 1.

---

### Task 1: O motor aceita alvos de fora do funil (lead_de, alvo_nome, conta do Painel, 6 gatilhos) — mecânica

**Files:**
- Modify: `app/models/fluxo_execucao.rb`
- Modify: `app/services/ramon/fluxos/disparo.rb` (`lead_do_alvo`)
- Modify: `app/services/ramon/fluxos/grafo.rb` (`GATILHOS`)
- Modify: `app/models/portal_assinatura.rb`, `app/models/portal_envio.rb`
- Test: `spec/models/fluxo_execucao_spec.rb` (novo); `spec/services/ramon/fluxos/disparo_spec.rb`

**Interfaces:**
- Produces: `FluxoExecucao.lead_de(alvo) → Lead|nil` (Lead → ele; LeadTask/Reuniao → `alvo.lead`; Conversation → o lead mais novo da conversa; qualquer outro → nil); `FluxoExecucao::NOMES_ALVO`; `Grafo::GATILHOS` com `assinatura_painel documento_painel chegada_cliente reuniao_gravada peca_publicada peca_mudou_status`; `PortalAssinatura#account`, `PortalEnvio#account`.

- [ ] **Step 1: Write the failing tests**

(a) Criar `spec/models/fluxo_execucao_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe FluxoExecucao do
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account) }
  let!(:lead) { create(:lead, account: account, conversation: conversa, contact: conversa.contact) }

  describe '.lead_de' do
    it 'lead, conversa e reunião gravada vinculada acham o lead; alvo de fora do funil nunca adivinha pelo id' do
      expect(described_class.lead_de(lead)).to eq(lead)
      expect(described_class.lead_de(conversa)).to eq(lead)
      expect(described_class.lead_de(create(:reuniao, account: account, lead: lead))).to eq(lead)
      expect(described_class.lead_de(create(:reuniao, account: account))).to be_nil
      # o mesmo id da conversa do lead: o "else" antigo acharia este lead por engano
      expect(described_class.lead_de(Chegada.new(id: conversa.id, account: account))).to be_nil
      expect(described_class.lead_de(Peca.new(id: conversa.id, account: account))).to be_nil
      expect(described_class.lead_de(nil)).to be_nil
    end
  end

  it 'a execução de um alvo de fora do funil diz o que ele é, sem lead nem conversa' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'peca_publicada' }))
    execucao = fluxo.execucoes.create!(account: account, alvo: create(:peca, account: account), ensaio: true)
    expect(execucao.resumo_json).to include(alvo_nome: 'Peça: Auxílio-acidente: quem tem direito', lead_id: nil,
                                            conversation_display_id: nil)
  end
end
```
Rastreio: `create(:reuniao, account:, lead:)` — a factory tem `account` e `status`; `belongs_to :lead, optional: true`. O gancho vem da factory `:peca`. `grafo_linear` sem passos publica (1 gatilho, nada mais) — o mesmo que `migracao_spec` faz.

(b) Em `spec/services/ramon/fluxos/disparo_spec.rb`, acrescentar no fim do `RSpec.describe` (antes do `end` final):

```ruby
  it 'alvo de fora do funil (B5): a execução é do próprio registro, sem lead nem etapa — mesmo com id igual ao de uma conversa' do
    lead # o lead da conversa existe
    chegada = account.chegadas.create!(id: conversa.id, criado_por: create(:user, account: account),
                                       destinatario: create(:user, account: account), cliente_nome: 'Maria')
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'chegada_cliente' }, nota))
    described_class.call('chegada_cliente', chegada)
    execucao = fluxo.execucoes.sole
    expect([execucao.alvo, execucao.lead, execucao.contexto['etapa_inicial_id']]).to eq([chegada, nil, nil])
  end

  it 'assinatura do Painel (B5): a conta vem do cliente do Painel' do
    assinatura = create(:portal_assinatura, portal_cliente: create(:portal_cliente, account: account))
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'assinatura_painel' }, nota))
    described_class.call('assinatura_painel', assinatura)
    expect(fluxo.execucoes.sole).to have_attributes(account_id: account.id, alvo_type: 'PortalAssinatura')
  end
```
Rastreio: `etapa_inicial_id` nil é removido pelo `.compact` do `contexto` → `contexto['etapa_inicial_id']` = nil. Antes da Task 1, `lead_do_alvo` cai no `else` e acha o `lead` (mesmo `conversation_id`) → falha. `assinatura.account` não existe antes → `NoMethodError`.

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/models/fluxo_execucao_spec.rb spec/services/ramon/fluxos/disparo_spec.rb`
Expected: FAIL — `undefined method 'lead_de'`; "Gatilho desconhecido: peca_publicada" ao publicar; `undefined method 'account' for PortalAssinatura`.

- [ ] **Step 3: Implementation**

(a) `app/models/fluxo_execucao.rb` — trocar `def lead … end` por:

```ruby
  # B5: alvos de fora do funil aparecem com o que são (a lista e a tela de execução não têm outra coluna).
  NOMES_ALVO = {
    'Chegada' => ->(alvo) { "Chegada: #{alvo.cliente_nome}" },
    'Peca' => ->(alvo) { "Peça: #{alvo.gancho}" },
    'Reuniao' => ->(alvo) { "Reunião gravada: #{alvo.titulo_exibicao}" },
    'PortalAssinatura' => ->(alvo) { "Assinatura do Painel: #{alvo.portal_cliente.nome}" },
    'PortalEnvio' => ->(alvo) { "Documento do Painel: #{alvo.portal_cliente.nome}" }
  }.freeze

  # B4.1: o alvo também pode ser a tarefa da reunião (ciclo de lembretes); B5: a reunião gravada (com lead, se vinculada).
  # Chegada, peça e Painel do Cliente não têm lead — nunca adivinhar pelo id (o id de uma chegada não é id de conversa).
  def self.lead_de(alvo)
    case alvo
    when Lead then alvo
    when LeadTask, Reuniao then alvo.lead
    when Conversation then alvo.account.leads.where(conversation_id: alvo.id).reorder(id: :desc).first
    end
  end

  def lead = self.class.lead_de(alvo)
```
e trocar o `alvo_nome` privado por:

```ruby
  def alvo_nome
    externo = NOMES_ALVO[alvo_type]
    return externo.call(alvo) if externo && alvo

    alvo.try(:name) || alvo.try(:contact)&.name || lead&.name
  end
```
(`NOMES_ALVO` fica no topo da classe, depois de `STATUS`.)

(b) `app/services/ramon/fluxos/disparo.rb` — trocar o método `lead_do_alvo` inteiro por:

```ruby
  def lead_do_alvo = FluxoExecucao.lead_de(@alvo)
```

(c) `app/services/ramon/fluxos/grafo.rb` — `GATILHOS` ganha uma linha no fim:

```ruby
  GATILHOS = %w[conversa_criada mensagem_recebida conversa_resolvida conversa_reaberta conversa_atribuida
                lead_criado lead_mudou_etapa lead_ganho lead_perdido manual
                lead_parado relogio reuniao_marcada reuniao_cancelada reuniao_na_agenda evento_advbox
                contrato_assinado contrato_recusado documento_recebido
                assinatura_painel documento_painel chegada_cliente reuniao_gravada peca_publicada peca_mudou_status].freeze
```
(Se a B5-conta/B5-leads acrescentaram gatilhos, a linha nova vai depois da deles.)

(d) `app/models/portal_assinatura.rb` e `app/models/portal_envio.rb`, logo depois de `belongs_to :portal_cliente`:

```ruby
  delegate :account, to: :portal_cliente # B5: o Disparo dos fluxos lê alvo.account
```

- [ ] **Step 4: Run to verify they pass**

Run (CI): `bundle exec rspec spec/models/fluxo_execucao_spec.rb spec/services/ramon/fluxos spec/models/portal_cliente_spec.rb` e `bundle exec rubocop app/models/fluxo_execucao.rb app/services/ramon/fluxos/disparo.rb app/services/ramon/fluxos/grafo.rb app/models/portal_assinatura.rb app/models/portal_envio.rb spec/models/fluxo_execucao_spec.rb spec/services/ramon/fluxos/disparo_spec.rb`
Expected: PASS (inclusive executor/contexto/reunioes, que usam `execucao.lead` com Lead, LeadTask e Conversation), sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/models/fluxo_execucao.rb app/services/ramon/fluxos/disparo.rb app/services/ramon/fluxos/grafo.rb app/models/portal_assinatura.rb app/models/portal_envio.rb spec/models/fluxo_execucao_spec.rb spec/services/ramon/fluxos/disparo_spec.rb
git commit -m "feat(fluxos): alvos de fora do funil (chegada, reunião gravada, peça, Painel) e 6 gatilhos novos; lead nunca adivinhado pelo id" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 2: As 7 rotinas prontas de fora do funil (o mesmo código de hoje) — mecânica (o registro: julgamento, depende de B5-conta)

**Files:**
- Create: `app/services/ramon/fluxos/rotinas/externos.rb`
- Modify: o registro de rotinas da B5-conta (Task 0) — acrescentar `Ramon::Fluxos::Rotinas::Externos` no fim
- Modify: `app/models/chegada.rb`, `app/jobs/ramon/chegada_escalar_job.rb`
- Modify: `app/jobs/ramon/zapsign_lead_status_job.rb` (só `self.avisar`; a decisão é a Task 4)
- Test: `spec/services/ramon/fluxos/rotinas/externos_spec.rb` (novo)

**Interfaces:**
- Consumes: `FluxoExecucao.lead_de` (Task 1); o registro da B5-conta (`Passos::Rotina.rotina` acha o módulo pelo nome e chama `modulo.public_send(nome, ctx)`).
- Produces: `Ramon::Fluxos::Rotinas::Externos::ROTINAS = %w[conferir_assinatura_painel aviso_contrato processar_envio_painel escalar_chegada escrever_ata acervo_drive espelho_notion]`; cada uma `nome(ctx) → String`; `Chegada#escalavel? → Boolean`, `Chegada#escalar! → true|false`; `Ramon::ZapsignLeadStatusJob.avisar(lead, status)` (status `'signed'|'refused'`).

- [ ] **Step 1: Write the failing test**

Criar `spec/services/ramon/fluxos/rotinas/externos_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Rotinas::Externos do
  let(:account) { create(:account) }
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' })) }
  let(:chegada) do
    account.chegadas.create!(criado_por: create(:user, account: account), destinatario: create(:user, account: account),
                             cliente_nome: 'Maria')
  end

  # ensaio pode repetir no mesmo exemplo; execução de verdade, 1 por alvo por exemplo (índice único)
  def rodar(rotina, alvo, ensaio: false)
    ctx = Ramon::Fluxos::Contexto.new(fluxo.execucoes.create!(account: account, alvo: alvo, ensaio: ensaio))
    described_class.public_send(rotina, ctx)
  end

  describe 'escalar a chegada' do
    it 'escala como o job (o alerta volta ao vivo para quem avisou); já escalada não mexe' do
      expect(rodar('escalar_chegada', chegada, ensaio: true)).to eq('faria: escalar — o alerta volta a tocar na tela de quem avisou')
      expect { rodar('escalar_chegada', chegada) }.to have_enqueued_job(ActionCableBroadcastJob)
      expect(chegada.reload.estado).to eq('escalado')
      expect(rodar('escalar_chegada', chegada, ensaio: true)).to eq('chegada já respondida (ou já escalada): não escala')
    end

    it 'respondida dentro dos 3 min: não escala' do
      chegada.update!(resposta: 'Já vou', respondido_em: Time.current)
      expect(rodar('escalar_chegada', chegada)).to eq('chegada já respondida (ou já escalada): não escala')
      expect(chegada.reload.escalado_em).to be_nil
    end
  end

  it 'os pesados pedem o MESMO job de hoje (fila e novas tentativas do código); o ensaio só descreve' do
    assinatura = create(:portal_assinatura, portal_cliente: create(:portal_cliente, account: account))
    envio = create(:portal_envio, portal_cliente: assinatura.portal_cliente)
    reuniao = create(:reuniao, account: account)
    peca = create(:peca, account: account)
    expect(rodar('escrever_ata', reuniao, ensaio: true)).to start_with('faria: transcrever o áudio e escrever a ata')
    expect { rodar('conferir_assinatura_painel', assinatura) }.to have_enqueued_job(Ramon::ZapsignStatusJob).with(assinatura.id)
    expect { rodar('processar_envio_painel', envio) }.to have_enqueued_job(Ramon::PortalEnvioJob).with(envio.id)
    expect { rodar('escrever_ata', reuniao) }.to have_enqueued_job(Ramon::ReuniaoAtaJob).with(reuniao.id)
    expect { rodar('acervo_drive', peca) }.to have_enqueued_job(Ramon::ConteudoDriveJob).with(peca.id)
    expect { rodar('espelho_notion', peca, ensaio: true) }.not_to have_enqueued_job(Ramon::NotionEspelhoJob)
  end

  describe 'aviso do contrato' do
    it 'o mesmo histórico e o mesmo sino de hoje, pelo status que o código gravou no selo' do
      user = create(:user, account: account)
      lead = create(:lead, account: account, custom_attributes: {
                      'zapsign' => { 'doc_token' => 'd1', 'status' => 'signed', 'template_name' => 'Contrato' }
                    })
      expect(rodar('aviso_contrato', lead, ensaio: true)).to eq('faria: histórico e sino a todos — contrato assinado')
      expect(rodar('aviso_contrato', lead)).to eq('histórico e sino a todos — contrato assinado')
      expect(lead.lead_activities.where(kind: 'zapsign_signed').pluck(:to_value)).to eq(['Contrato'])
      expect(Notification.where(notification_type: 'ramon_contract_status', user: user, primary_actor: lead).count).to eq(1)
    end

    it 'sem selo assinado/recusado não faz nada' do
      expect(rodar('aviso_contrato', create(:lead, account: account)))
        .to eq('contrato: o ZapSign não diz assinado nem recusado (sem status)')
    end
  end

  it 'com o alvo errado ("Testar com um lead…") falha na hora, dizendo com o que roda' do
    expect { rodar('escalar_chegada', create(:lead, account: account), ensaio: true) }
      .to raise_error(Ramon::Fluxos::PassoImpossivel, /uma chegada de cliente/)
  end

  it 'o passo Rotina pronta acha estas rotinas no registro (B5-conta) sem exigir lead' do
    ctx = Ramon::Fluxos::Contexto.new(fluxo.execucoes.create!(account: account, alvo: chegada, ensaio: true))
    expect(Ramon::Fluxos::Passos::Rotina.rotina({ 'rotina' => 'escalar_chegada' }, ctx))
      .to eq(saida: 's', resumo: 'faria: escalar — o alerta volta a tocar na tela de quem avisou')
  end
end
```
Rastreio: no 1º exemplo, `chegada` é criada na 1ª linha (o `after_create_commit` enfileira um `ActionCableBroadcastJob` **antes** do bloco do `expect`), então o `have_enqueued_job` só vê o do `update!` do `escalar!`. A `peca` tem 1 execução de verdade (acervo) e 1 ensaio; `reuniao` 1 ensaio + 1 de verdade — dentro do índice. `LeadNotificationBuilder` sem `user_ids` = todos da conta → 1 linha para `user`. `with(...)` do registro: o último exemplo prova a ligação com o registro da B5-conta (ajustar o formato se a Task 0 achou outro).

- [ ] **Step 2: Run to verify it fails**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/rotinas/externos_spec.rb`
Expected: FAIL — `uninitialized constant Ramon::Fluxos::Rotinas::Externos`.

- [ ] **Step 3: Implementation**

(a) Criar `app/services/ramon/fluxos/rotinas/externos.rb`:

```ruby
# B5-externos: rotinas prontas das automações que começam FORA do funil — o MESMO código de hoje.
# Registro de rotinas por arquivo (formato da B5-conta): ROTINAS + um método de módulo por nome, nome(ctx) → String (o
# resumo da trilha); o ensaio só descreve; alvo errado = PassoImpossivel (falha na hora, sem nova tentativa).
# Os pesados pedem o mesmo job de hoje (perform_later), com a fila, as travas e as novas tentativas do código (ata 3×,
# ZapSign 5×, documento do Painel 5×, Drive 3×): o Ramon::FluxoRelogioJob devolve à fila a execução 'rodando' há mais
# de 10 min — o whisper de uma reunião longa dentro do passo seria transcrito de novo.
module Ramon::Fluxos::Rotinas::Externos
  ROTINAS = %w[conferir_assinatura_painel aviso_contrato processar_envio_painel escalar_chegada escrever_ata acervo_drive
               espelho_notion].freeze
  ALVOS = { 'PortalAssinatura' => 'uma assinatura do Painel do Cliente', 'PortalEnvio' => 'um documento enviado pelo Painel',
            'Chegada' => 'uma chegada de cliente', 'Reuniao' => 'uma reunião gravada', 'Peca' => 'uma peça do Instagram' }.freeze

  module_function

  def conferir_assinatura_painel(ctx)
    assinatura = alvo!(ctx, PortalAssinatura)
    return "faria: conferir no ZapSign a assinatura \"#{assinatura.nome}\" e marcar no Painel" if ctx.ensaio?

    Ramon::ZapsignStatusJob.perform_later(assinatura.id)
    "conferência no ZapSign pedida (\"#{assinatura.nome}\")"
  end

  # O selo (custom_attributes.zapsign.status) é gravado pelo código antes do evento; aqui só o histórico e o sino de hoje.
  def aviso_contrato(ctx)
    lead = Ramon::Fluxos::Passos::Lead.exigir_lead(ctx)
    status = lead.custom_attributes&.dig('zapsign', 'status').to_s
    rotulo = Ramon::ZapsignLeadStatusJob::STATUS.dig(status, 2)
    return "contrato: o ZapSign não diz assinado nem recusado (#{status.presence || 'sem status'})" if rotulo.nil?
    return "faria: histórico e sino a todos — contrato #{rotulo}" if ctx.ensaio?

    Ramon::ZapsignLeadStatusJob.avisar(lead, status)
    "histórico e sino a todos — contrato #{rotulo}"
  end

  def processar_envio_painel(ctx)
    envio = alvo!(ctx, PortalEnvio)
    return "faria: guardar \"#{envio.item}\" no Drive, push no celular e as 2 tarefas no ADVBOX" if ctx.ensaio?

    Ramon::PortalEnvioJob.perform_later(envio.id)
    "documento \"#{envio.item}\": Drive, push e tarefas do ADVBOX pedidos"
  end

  def escalar_chegada(ctx)
    chegada = alvo!(ctx, Chegada)
    return 'chegada já respondida (ou já escalada): não escala' unless chegada.escalavel?
    return 'faria: escalar — o alerta volta a tocar na tela de quem avisou' if ctx.ensaio?

    chegada.escalar!
    'escalou: o alerta voltou a tocar na tela de quem avisou'
  end

  def escrever_ata(ctx)
    reuniao = alvo!(ctx, Reuniao)
    return "faria: transcrever o áudio e escrever a ata de \"#{reuniao.titulo_exibicao}\"" if ctx.ensaio?

    Ramon::ReuniaoAtaJob.perform_later(reuniao.id)
    'ata pedida (transcrição e IA na fila de sempre; a ata aparece na reunião)'
  end

  def acervo_drive(ctx)
    peca = alvo!(ctx, Peca)
    return "faria: copiar a peça \"#{peca.gancho}\" (imagens e legenda) para o Drive" if ctx.ensaio?

    Ramon::ConteudoDriveJob.perform_later(peca.id)
    "cópia no Drive pedida (\"#{peca.gancho}\")"
  end

  def espelho_notion(ctx)
    peca = alvo!(ctx, Peca)
    return "faria: espelhar o status \"#{peca.status}\" no Notion" if ctx.ensaio?

    Ramon::NotionEspelhoJob.perform_later(peca.id)
    "espelho do status \"#{peca.status}\" no Notion pedido"
  end

  def alvo!(ctx, classe)
    alvo = ctx.execucao.alvo
    return alvo if alvo.is_a?(classe)

    raise Ramon::Fluxos::PassoImpossivel, "esta rotina só roda com #{ALVOS.fetch(classe.name)} (o Testar com um lead não serve aqui)"
  end
end
```
Rastreio: `STATUS.dig('signed', 2)` = `'assinado'` (Hash#dig desce no Array); `dig('', 2)` = nil. Linhas ≤ 150. `aviso_contrato`: 1 + `&.` + `||` + 2 `if` = 5.

(b) Registro da B5-conta — no fim da lista de módulos (nome confirmado na Task 0), por ex.:

```ruby
  MODULOS = [..., Ramon::Fluxos::Rotinas::Externos].freeze # B5-externos: rotinas de fora do funil
```

(c) `app/models/chegada.rb` — antes do `private`:

```ruby
  # Sem resposta e ainda não escalada (Ramon::ChegadaEscalarJob e a rotina do fluxo "Chegada de cliente", B5).
  def escalavel? = respondido_em.blank? && escalado_em.blank?

  # O update transmite ramon.chegada.updated (after_update_commit): o alerta volta a tocar na tela de quem avisou.
  def escalar! = escalavel? && update!(escalado_em: Time.current)
```

(d) `app/jobs/ramon/chegada_escalar_job.rb` — corpo do `perform`:

```ruby
  def perform(chegada_id)
    Chegada.find_by(id: chegada_id)&.escalar!
  end
```

(e) `app/jobs/ramon/zapsign_lead_status_job.rb` — trocar o `avisar` privado por um método de classe público (antes do `private`), e a chamada no `perform` (`avisar(lead, kind, rotulo, zapsign['template_name'])`) por `self.class.avisar(lead, doc['status'])` (a Task 4 põe a decisão em volta):

```ruby
  # Público (B5): a rotina "aviso_contrato" do fluxo chama o mesmo — histórico + sino para todos da conta.
  def self.avisar(lead, status)
    kind, _chave, rotulo = STATUS.fetch(status)
    lead.lead_activities.create!(account: lead.account, kind: kind, to_value: lead.custom_attributes.dig('zapsign', 'template_name'))
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_contract_status', meta: { 'label' => rotulo }).perform
  end
```
e no `perform`: `kind, chave, rotulo, gatilho = STATUS[...]` vira `_kind, chave, _rotulo, gatilho = STATUS[doc['status'].to_s]` e `return if kind.nil? || …` vira `return if gatilho.nil? || !atual?(lead, doc_token)`. (`template_name` é o mesmo: o `zapsign` gravado logo antes é o de `custom_attributes`.)

- [ ] **Step 4: Run to verify it passes**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/rotinas/externos_spec.rb spec/jobs/ramon/chegada_escalar_job_spec.rb spec/jobs/ramon/zapsign_lead_status_job_spec.rb spec/models/chegada_spec.rb spec/services/ramon/fluxos/passos/rotina_spec.rb` e `bundle exec rubocop app/services/ramon/fluxos/rotinas/externos.rb app/models/chegada.rb app/jobs/ramon/chegada_escalar_job.rb app/jobs/ramon/zapsign_lead_status_job.rb spec/services/ramon/fluxos/rotinas/externos_spec.rb <arquivo do registro>`
Expected: PASS, sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/rotinas/externos.rb <arquivo do registro> app/models/chegada.rb app/jobs/ramon/chegada_escalar_job.rb app/jobs/ramon/zapsign_lead_status_job.rb spec/services/ramon/fluxos/rotinas/externos_spec.rb
git commit -m "feat(fluxos): rotinas prontas de fora do funil (assinatura e documento do Painel, contrato, chegada, ata, acervo) — o mesmo código de hoje" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 3: A decisão do evento (`Externos.evento`), os 6 grupos, os 8 desenhos e as envs — mecânica

**Files:**
- Create: `app/services/ramon/fluxos/externos.rb`
- Modify: `app/services/ramon/fluxos/migracao.rb` (fim de `GRUPOS`)
- Modify: `app/services/ramon/fluxos/disparo.rb` (`DUAS_VEZES`)
- Create: `db/seeds/ramon/fluxos/migrados/{assinatura_painel,contrato_zapsign_assinado,contrato_zapsign_recusado,documento_painel,chegada_cliente,ata_reuniao,acervo_pecas_drive,acervo_pecas_notion}.json`
- Modify: `.env.example`
- Test: `spec/services/ramon/fluxos/externos_spec.rb` (novo)

**Interfaces:**
- Consumes: `Migracao.assumiu?/semear/mudar_modo!/fluxo/descrever`; `Disparo.externo`; as rotinas (Task 2); os gatilhos (Task 1).
- Produces: `Ramon::Fluxos::Externos::GRUPOS` (6 grupos: `assinatura_painel`, `contrato_zapsign`, `documento_painel`, `chegada_cliente`, `ata_reuniao`, `acervo_pecas`); `Externos.gatilhos → Array<String>`; `Externos.evento(grupo, gatilho, alvo, dados = {}) { código }` (roda o bloco se o código deve fazer; sempre dispara os comuns depois); `Disparo::DUAS_VEZES` com os 8 gatilhos dos grupos.

- [ ] **Step 1: Write the failing test**

Criar `spec/services/ramon/fluxos/externos_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Externos do
  let(:account) { create(:account) }
  let(:recepcao) { create(:user, account: account) }
  let(:chegada) { account.chegadas.create!(criado_por: recepcao, destinatario: recepcao, cliente_nome: 'Maria') }
  let(:outra) { account.chegadas.create!(criado_por: recepcao, destinatario: recepcao, cliente_nome: 'Ana') }
  let(:codigo) { [] }

  def evento(alvo = chegada) = described_class.evento('chegada_cliente', 'chegada_cliente', alvo) { codigo << alvo.id }

  def no_comando
    Ramon::Fluxos::Migracao.semear(account, 'chegada_cliente')
    Ramon::Fluxos::Migracao.mudar_modo!(account, 'chegada_cliente', 'normal')
  end

  def migrado = Ramon::Fluxos::Migracao.fluxo(account, 'chegada_cliente')

  it 'criar = os 8 fluxos dos 6 grupos, em sombra, ligados, publicados, cada um com o seu gatilho' do
    fluxos = described_class::GRUPOS.keys.flat_map { |grupo| Ramon::Fluxos::Migracao.semear(account, grupo) }
    expect(fluxos.map { |f| [f.sistema_chave, f.gatilho_tipo] }).to eq(described_class::GRUPOS.values.flat_map { |g| g[:fluxos].to_a })
    expect(fluxos.map { |f| [f.origem, f.modo, f.ativo, f.versao_publicada.present?] }.uniq).to eq([['usuario', 'sombra', true, true]])
    expect(Ramon::Fluxos::Migracao.descrever(account, 'chegada_cliente')).to include('o CÓDIGO faz a escalada da chegada de cliente')
  end

  it 'código no comando (padrão): o código faz; o migrado só ensaia; o fluxo comum do gatilho ouve sem a decisão' do
    Ramon::Fluxos::Migracao.semear(account, 'chegada_cliente')
    comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'chegada_cliente' }))
    evento
    expect(codigo).to eq([chegada.id])
    expect(migrado.execucoes.pluck(:ensaio)).to eq([true])
    expect(comum.execucoes.map { |e| [e.ensaio, e.contexto['gatilho'].key?('assumido')] }).to eq([[false, false]])
  end

  it 'fluxo no comando: o código não faz; o migrado age' do
    with_modified_env(RAMON_FLUXO_CHEGADA: 'on') do
      no_comando
      evento
    end
    expect(codigo).to eq([])
    expect(migrado.execucoes.pluck(:ensaio, :status)).to eq([[false, 'esperando']])
  end

  it 'fluxo no comando mas ocupado com o mesmo alvo, ou o motor falhou: o código faz aquele evento — nunca nenhum, nunca dois' do
    with_modified_env(RAMON_FLUXO_CHEGADA: 'on') do
      no_comando
      migrado.execucoes.create!(account: account, alvo: chegada, status: 'esperando', retomar_em: 5.minutes.from_now)
      evento
      outra
      allow(Ramon::Fluxos::Disparo).to receive(:call).and_raise(StandardError, 'motor')
      evento(outra)
    end
    expect(codigo).to eq([chegada.id, outra.id])
    expect(migrado.execucoes.count).to eq(1) # só a viva; nenhum dos 2 eventos criou outra
  end

  it 'grupo de 2 fluxos (acervo das peças): um desligado na tela devolve os dois pontos ao código' do
    peca = create(:peca, account: account)
    feitos = []
    with_modified_env(RAMON_FLUXO_ACERVO_PECAS: 'on') do
      Ramon::Fluxos::Migracao.semear(account, 'acervo_pecas')
      Ramon::Fluxos::Migracao.mudar_modo!(account, 'acervo_pecas', 'normal')
      Ramon::Fluxos::Migracao.fluxo(account, 'acervo_pecas_notion').update!(ativo: false)
      described_class.evento('acervo_pecas', 'peca_publicada', peca) { feitos << 'drive' }
    end
    expect(feitos).to eq(['drive'])
  end
end
```
Rastreio: `semear` devolve na ordem de `gatilhos(nome).keys` = ordem do hash do grupo; o `flat_map` dos dois lados segue a mesma ordem. O fluxo comum não é migrado (sem `sistema_chave`) → só a 2ª chamada (sem `assumido`) o pega (`DUAS_VEZES` inclui `chegada_cliente` depois do Step 3). No "ocupado", o `create!` com `retomar_em` futuro fica vivo → o `Disparo#iniciar` do evento bate em `RecordNotUnique` → `nil` → lista vazia → bloco roda. Com `Disparo.call` estourando, `externo` engole e devolve `[]` → bloco roda; a 2ª chamada (comuns) também devolve `[]`. Acervo: 1 fluxo desligado → `assumiu?` compara 1 linha contra 2 esperadas → false → bloco roda.

- [ ] **Step 2: Run to verify it fails**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/externos_spec.rb`
Expected: FAIL — `uninitialized constant Ramon::Fluxos::Externos`.

- [ ] **Step 3: Implementation**

(a) Criar `app/services/ramon/fluxos/externos.rb`:

```ruby
# B5 (spec §8): as automações que começam FORA do funil — webhook do ZapSign, Painel do Cliente, recepção, gravação de
# reunião, peças do Instagram — cada uma com a chave da B4.1 (env própria + os fluxos do grupo em modo normal).
# A decisão é do evento, lida UMA vez em `evento`:
# 1) os fluxos migrados do grupo, com 'assumido' (agem, ou ensaiam);
# 2) o código (o bloco), se o fluxo não está no comando OU não começou este evento (ocupado com o mesmo alvo, erro do
#    motor, desligado no meio) — nada se perde, nada em dobro;
# 3) os fluxos comuns desse gatilho, sem 'assumido', como sempre.
# O alvo é o registro do evento (PortalAssinatura, PortalEnvio, Chegada, Reuniao, Peca) — só o contrato é do lead.
# Os grupos entram em Ramon::Fluxos::Migracao::GRUPOS (rake ramon:fluxos:migracao:{criar,modo}[grupo,conta]).
module Ramon::Fluxos::Externos
  GRUPOS = {
    'assinatura_painel' => { env: 'RAMON_FLUXO_ASSINATURA_PAINEL', faz: 'a conferência das assinaturas do Painel do Cliente',
                             fluxos: { 'assinatura_painel' => 'assinatura_painel' }.freeze },
    'contrato_zapsign' => { env: 'RAMON_FLUXO_CONTRATO_ZAPSIGN', faz: 'o histórico e o sino do contrato no ZapSign',
                            fluxos: { 'contrato_zapsign_assinado' => 'contrato_assinado',
                                      'contrato_zapsign_recusado' => 'contrato_recusado' }.freeze },
    'documento_painel' => { env: 'RAMON_FLUXO_DOCUMENTO_PAINEL', faz: 'os documentos enviados pelo Painel (Drive, push e ADVBOX)',
                            fluxos: { 'documento_painel' => 'documento_painel' }.freeze },
    'chegada_cliente' => { env: 'RAMON_FLUXO_CHEGADA', faz: 'a escalada da chegada de cliente',
                           fluxos: { 'chegada_cliente' => 'chegada_cliente' }.freeze },
    'ata_reuniao' => { env: 'RAMON_FLUXO_ATA_REUNIAO', faz: 'a ata das reuniões gravadas',
                       fluxos: { 'ata_reuniao' => 'reuniao_gravada' }.freeze },
    'acervo_pecas' => { env: 'RAMON_FLUXO_ACERVO_PECAS', faz: 'o acervo das peças (Drive e Notion)',
                        fluxos: { 'acervo_pecas_drive' => 'peca_publicada', 'acervo_pecas_notion' => 'peca_mudou_status' }.freeze }
  }.freeze

  module_function

  # Os gatilhos que estes pontos disparam duas vezes (Disparo::DUAS_VEZES).
  def gatilhos = GRUPOS.values.flat_map { |g| g[:fluxos].values }

  def evento(grupo, gatilho, alvo, dados = {})
    assumido = Ramon::Fluxos::Migracao.assumiu?(alvo.account, grupo)
    feitas = Ramon::Fluxos::Disparo.externo(gatilho, alvo, dados.merge('assumido' => assumido))
    yield unless assumido && feitas.any?
    Ramon::Fluxos::Disparo.externo(gatilho, alvo, dados)
  end
end
```

(b) `app/services/ramon/fluxos/migracao.rb` — o `}.freeze` que fecha `GRUPOS` vira (com um comentário na linha de cima):

```ruby
    # B5-externos: os 6 grupos de fora do funil moram em Ramon::Fluxos::Externos::GRUPOS (limite do módulo + rebase).
  }.merge(Ramon::Fluxos::Externos::GRUPOS).freeze
```
(Se a Task 0 achou outro `.merge(...)`, encadeie depois dele.)

(c) `app/services/ramon/fluxos/disparo.rb` — `DUAS_VEZES` (mantendo o que as irmãs acrescentaram):

```ruby
  # B5-externos: os gatilhos de fora do funil (Ramon::Fluxos::Externos.evento manda com e sem a decisão).
  DUAS_VEZES = (NA_HORA + %w[conversa_criada lead_ganho] + Ramon::Fluxos::Externos.gatilhos).freeze
```

(d) Os 8 JSON em `db/seeds/ramon/fluxos/migrados/` (posições x 0, y 0/140/280):

`assinatura_painel.json`
```json
{
  "nome": "Assinatura pelo Painel do Cliente",
  "descricao": "Quando o ZapSign avisa que um documento do Painel do Cliente mudou, no lugar do código (B5): pergunta ao ZapSign o status real e marca a assinatura no Painel — o mesmo de hoje, na mesma fila e com as mesmas novas tentativas. Assinatura cancelada no hub não muda. Se este fluxo não começar (ocupado com a mesma assinatura ou erro), o código faz aquele aviso, como antes. Enquanto o selo disser \"em sombra\", só ensaia: quem faz ainda é o código.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"assinatura_painel","cancelar_se_sair_da_etapa":false},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"rotina","config":{"rotulo":"Conferir no ZapSign e marcar a assinatura no Painel","rotina":"conferir_assinatura_painel"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`contrato_zapsign_assinado.json`
```json
{
  "nome": "Contrato assinado no ZapSign",
  "descricao": "Quando o contrato do lead é assinado no ZapSign, no lugar do código (B5): linha no histórico do lead e sino para todos da conta — o mesmo de hoje. A conferência no ZapSign e o selo \"assinado\" no card continuam no código (são o próprio evento). Nunca marca o lead como ganho. Se este fluxo não começar, o código faz, como antes. Enquanto o selo disser \"em sombra\", só ensaia.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"contrato_assinado","cancelar_se_sair_da_etapa":false},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"rotina","config":{"rotulo":"Histórico e sino: contrato assinado","rotina":"aviso_contrato"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`contrato_zapsign_recusado.json` — igual ao anterior com `"nome": "Contrato recusado no ZapSign"`, `descricao` trocando "assinado" por "recusado" (e "é assinado" por "é recusado"), gatilho `"tipo":"contrato_recusado"` e rótulo `"Histórico e sino: contrato recusado"`.

`documento_painel.json`
```json
{
  "nome": "Documento enviado pelo Painel",
  "descricao": "Quando o cliente envia um arquivo pelo Painel do Cliente, no lugar do código (B5): guarda no Drive (Clientes/<Nome — CPF>, se o Drive estiver configurado), push no celular e 2 tarefas no ADVBOX — ANALISAR DOCUMENTAÇÃO para o responsável do processo e ORGANIZAR DOCUMENTOS para a recepção. O mesmo de hoje: grava no ADVBOX de verdade, uma vez por documento, e tenta de novo até 5 vezes se o ADVBOX cair. Se este fluxo não começar, o código faz, como antes. Enquanto o selo disser \"em sombra\", só ensaia.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"documento_painel","cancelar_se_sair_da_etapa":false},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"rotina","config":{"rotulo":"Drive, push e 2 tarefas no ADVBOX (grava no ADVBOX)","rotina":"processar_envio_painel"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`chegada_cliente.json`
```json
{
  "nome": "Chegada de cliente",
  "descricao": "Quando a recepção avisa que um cliente chegou, no lugar do código (B5): espera 3 minutos e, se ninguém respondeu, o alerta volta a tocar na tela de quem avisou (ao vivo, não é o sino). O relógio dos fluxos anda de minuto em minuto: o alerta toca entre 3 e 4 minutos. Se este fluxo não começar, o código escala, como antes. Enquanto o selo disser \"em sombra\", só ensaia.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"chegada_cliente","cancelar_se_sair_da_etapa":false},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"esperar","config":{"rotulo":"3 minutos","quantidade":3,"unidade":"minutos"},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"rotina","config":{"rotulo":"Escalar a chegada (se ninguém respondeu)","rotina":"escalar_chegada"},"posicao":{"x":0,"y":280}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"s","para":"n3"}
    ]
  }
}
```

`ata_reuniao.json`
```json
{
  "nome": "Ata da reunião",
  "descricao": "Quando uma reunião é gravada no hub (ou alguém pede Refazer ata), no lugar do código (B5): transcreve o áudio no whisper e a IA escreve a ata na própria reunião — o mesmo de hoje, na mesma fila; tenta de novo até 3 vezes e, se não der, a reunião fica com erro e o botão Refazer. Se este fluxo não começar, o código pede a ata, como antes. Enquanto o selo disser \"em sombra\", só ensaia.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"reuniao_gravada","cancelar_se_sair_da_etapa":false},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"rotina","config":{"rotulo":"Transcrever e escrever a ata","rotina":"escrever_ata"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`acervo_pecas_drive.json`
```json
{
  "nome": "Acervo das peças no Drive",
  "descricao": "Quando uma peça é publicada no Instagram, no lugar do código (B5): copia as imagens e a legenda para Posts Instagram/<Carrossel|Estático>/<rodada — gancho> no Drive — o mesmo de hoje (tenta de novo até 3 vezes). Anda junto com o fluxo \"Espelho das peças no Notion\" (uma chave para os dois). Se este fluxo não começar, o código copia, como antes. Enquanto o selo disser \"em sombra\", só ensaia.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"peca_publicada","cancelar_se_sair_da_etapa":false},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"rotina","config":{"rotulo":"Copiar a peça publicada para o Drive","rotina":"acervo_drive"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`acervo_pecas_notion.json`
```json
{
  "nome": "Espelho das peças no Notion",
  "descricao": "Quando o status de uma peça muda, no lugar do código (B5): atualiza o status no quadro Peças do Notion (só com o token do Notion; \"montando\" fica de fora) — o mesmo de hoje. Anda junto com o fluxo \"Acervo das peças no Drive\" (uma chave para os dois). Se este fluxo não começar (por exemplo, duas mudanças de status no mesmo instante), o código espelha aquela, como antes. Enquanto o selo disser \"em sombra\", só ensaia.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"peca_mudou_status","cancelar_se_sair_da_etapa":false},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"rotina","config":{"rotulo":"Espelhar o status da peça no Notion","rotina":"espelho_notion"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

(e) `.env.example` — depois do bloco de `RAMON_FLUXO_EVENTOS_ADVBOX` (e dos que as irmãs puseram):

```
# ramon: automacoes de fora do funil pelos fluxos (B5-externos). Cada uma: on + os fluxos do grupo em modo normal = o
# fluxo faz e o codigo para. Padrao desligado (o codigo faz). Virar/voltar: rake ramon:fluxos:migracao:modo[grupo,conta,normal|sombra]
# grupos: assinatura_painel, contrato_zapsign, documento_painel, chegada_cliente, ata_reuniao, acervo_pecas
# RAMON_FLUXO_ASSINATURA_PAINEL=off
# RAMON_FLUXO_CONTRATO_ZAPSIGN=off
# RAMON_FLUXO_DOCUMENTO_PAINEL=off
# RAMON_FLUXO_CHEGADA=off
# RAMON_FLUXO_ATA_REUNIAO=off
# RAMON_FLUXO_ACERVO_PECAS=off
```

- [ ] **Step 4: Run to verify it passes**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos` e `bundle exec rubocop app/services/ramon/fluxos/externos.rb app/services/ramon/fluxos/migracao.rb app/services/ramon/fluxos/disparo.rb spec/services/ramon/fluxos/externos_spec.rb`
Expected: PASS (inclusive `migracao_spec`, `disparo_spec`, `lead_ganho_spec`, `eventos_advbox_spec`: `DUAS_VEZES` só cresceu), sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/externos.rb app/services/ramon/fluxos/migracao.rb app/services/ramon/fluxos/disparo.rb db/seeds/ramon/fluxos/migrados/assinatura_painel.json db/seeds/ramon/fluxos/migrados/contrato_zapsign_assinado.json db/seeds/ramon/fluxos/migrados/contrato_zapsign_recusado.json db/seeds/ramon/fluxos/migrados/documento_painel.json db/seeds/ramon/fluxos/migrados/chegada_cliente.json db/seeds/ramon/fluxos/migrados/ata_reuniao.json db/seeds/ramon/fluxos/migrados/acervo_pecas_drive.json db/seeds/ramon/fluxos/migrados/acervo_pecas_notion.json .env.example spec/services/ramon/fluxos/externos_spec.rb
git commit -m "feat(fluxos): decisão pelo evento para as 6 automações de fora do funil + os 8 desenhos (chaves desligadas)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 4: Painel do Cliente e ZapSign — assinatura, contrato e documento pela decisão do evento — mecânica

**Files:**
- Modify: `app/controllers/public/api/v1/zapsign_webhooks_controller.rb`
- Modify: `app/jobs/ramon/zapsign_lead_status_job.rb`
- Modify: `app/controllers/cliente/painel_controller.rb` (`enviar`)
- Test: `spec/requests/public/api/v1/zapsign_webhooks_spec.rb`, `spec/jobs/ramon/zapsign_lead_status_job_spec.rb`, `spec/requests/cliente/painel_spec.rb`

**Interfaces:**
- Consumes: `Externos.evento` (Task 3); `ZapsignLeadStatusJob.avisar` (Task 2).

- [ ] **Step 1: Write the failing tests**

(a) `spec/requests/public/api/v1/zapsign_webhooks_spec.rb` — novo `it` no fim:

```ruby
  it 'fluxo "Assinatura pelo Painel" no comando: o código não enfileira; o fluxo pede a mesma conferência' do
    account = assinatura.portal_cliente.account
    with_modified_env(ZAPSIGN_WEBHOOK_SECRET: secret, RAMON_FLUXO_ASSINATURA_PAINEL: 'on') do
      Ramon::Fluxos::Migracao.semear(account, 'assinatura_painel')
      Ramon::Fluxos::Migracao.mudar_modo!(account, 'assinatura_painel', 'normal')
      expect do
        post '/public/api/v1/zapsign_webhooks', params: { token: 'doc-1' }.to_json,
                                                headers: { 'CONTENT_TYPE' => 'application/json', 'X-Ramon-Secret' => secret }
      end.not_to have_enqueued_job(Ramon::ZapsignStatusJob)
    end
    expect(response).to have_http_status(:ok)
    expect { perform_enqueued_jobs(only: Ramon::FluxoAvancarJob) }.to have_enqueued_job(Ramon::ZapsignStatusJob).with(assinatura.id)
    expect(Ramon::Fluxos::Migracao.fluxo(account, 'assinatura_painel').execucoes.sole).to have_attributes(ensaio: false, status: 'concluida')
  end
```
(O `post_webhook` do arquivo já abre um `with_modified_env`; aqui o post é feito à mão para não aninhar.)

(b) `spec/jobs/ramon/zapsign_lead_status_job_spec.rb`:
- nos 2 primeiros exemplos, `allow(Ramon::Fluxos::Disparo).to receive(:externo)` vira `allow(Ramon::Fluxos::Disparo).to receive(:externo).and_return([])`;
- as expectativas `have_received(:externo).with('contrato_assinado', lead)` / `('contrato_recusado', lead)` viram (cada uma):

```ruby
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('contrato_assinado', lead, { 'assumido' => false })
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('contrato_assinado', lead, {})
```
(idem `contrato_recusado`; o 1º exemplo fica com 7 expectativas — o limite; se o Rubocop contar 8, juntar as duas `have_received` num `.twice` sem `with` + uma com o `{}`);
- novo `it` no fim:

```ruby
  it 'fluxo "Contrato assinado no ZapSign" no comando: o selo fica no código; histórico e sino saem pelo fluxo, 1 vez' do
    allow(Ramon::ZapsignClient).to receive(:doc).and_return('status' => 'signed', 'signers' => [])
    with_modified_env(RAMON_FLUXO_CONTRATO_ZAPSIGN: 'on') do
      Ramon::Fluxos::Migracao.semear(account, 'contrato_zapsign')
      Ramon::Fluxos::Migracao.mudar_modo!(account, 'contrato_zapsign', 'normal')
      described_class.perform_now(lead.id, 'doc-1')
    end
    expect(lead.reload.custom_attributes.dig('zapsign', 'status')).to eq('signed')
    expect(lead.lead_activities.where(kind: 'zapsign_signed')).to be_empty # ainda na fila do fluxo
    perform_enqueued_jobs(only: Ramon::FluxoAvancarJob)
    expect(lead.lead_activities.where(kind: 'zapsign_signed').pluck(:to_value)).to eq(['Contrato'])
    expect(Notification.where(notification_type: 'ramon_contract_status', user: user, primary_actor: lead).count).to eq(1)
  end
```

(c) `spec/requests/cliente/painel_spec.rb` — dentro do `describe 'POST /cliente/processos/:id/envios'`, novo `it`:

```ruby
    it 'fluxo "Documento enviado pelo Painel" no comando: o código não enfileira; o fluxo pede o mesmo job' do
      entrar
      with_modified_env(RAMON_FLUXO_DOCUMENTO_PAINEL: 'on') do
        Ramon::Fluxos::Migracao.semear(account, 'documento_painel')
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'documento_painel', 'normal')
        expect { post '/cliente/processos/1/envios', params: { file: pdf, item: 'CNIS atualizado', post_id: 9 } }
          .not_to have_enqueued_job(Ramon::PortalEnvioJob)
      end
      envio = PortalEnvio.last
      expect { perform_enqueued_jobs(only: Ramon::FluxoAvancarJob) }.to have_enqueued_job(Ramon::PortalEnvioJob).with(envio.id)
      expect(response).to redirect_to('/cliente/processos/1')
    end
```

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/requests/public/api/v1/zapsign_webhooks_spec.rb spec/jobs/ramon/zapsign_lead_status_job_spec.rb spec/requests/cliente/painel_spec.rb`
Expected: FAIL — os jobs ainda são enfileirados direto; `externo` chamado com 2 argumentos.

- [ ] **Step 3: Implementation**

(a) `zapsign_webhooks_controller.rb` — `Ramon::ZapsignStatusJob.perform_later(assinatura.id) if assinatura` vira `conferir(assinatura) if assinatura` e, no `private`:

```ruby
  # B5: pelo código (como sempre) ou pelo fluxo "Assinatura pelo Painel do Cliente" (RAMON_FLUXO_ASSINATURA_PAINEL).
  def conferir(assinatura)
    Ramon::Fluxos::Externos.evento('assinatura_painel', 'assinatura_painel', assinatura) { Ramon::ZapsignStatusJob.perform_later(assinatura.id) }
  end
```

(b) `zapsign_lead_status_job.rb` — no fim do `perform`, as linhas `self.class.avisar(lead, doc['status'])` e `Ramon::Fluxos::Disparo.externo(gatilho, lead)` viram:

```ruby
    # B5: o selo acima é o evento em si (e a trava contra repetir). Histórico e sino: pelo código ou pelo fluxo
    # "Contrato assinado/recusado no ZapSign" (RAMON_FLUXO_CONTRATO_ZAPSIGN); os fluxos comuns do gatilho, como sempre.
    Ramon::Fluxos::Externos.evento('contrato_zapsign', gatilho, lead) { self.class.avisar(lead, doc['status']) }
```
(e o comentário do topo do arquivo ganha: "Histórico e sino: pelo código ou pelo fluxo (B5).")

(c) `cliente/painel_controller.rb#enviar` — `Ramon::PortalEnvioJob.perform_later(envio.id)` vira:

```ruby
    # B5: pelo código (como sempre) ou pelo fluxo "Documento enviado pelo Painel" (RAMON_FLUXO_DOCUMENTO_PAINEL).
    Ramon::Fluxos::Externos.evento('documento_painel', 'documento_painel', envio) { Ramon::PortalEnvioJob.perform_later(envio.id) }
```

- [ ] **Step 4: Run to verify they pass**

Run (CI): os 3 specs do Step 2 + `bundle exec rspec spec/jobs/ramon/zapsign_status_job_spec.rb spec/jobs/ramon/portal_envio_job_spec.rb spec/services/ramon/zapsign_contract_service_spec.rb` e `bundle exec rubocop app/controllers/public/api/v1/zapsign_webhooks_controller.rb app/jobs/ramon/zapsign_lead_status_job.rb app/controllers/cliente/painel_controller.rb spec/requests/public/api/v1/zapsign_webhooks_spec.rb spec/jobs/ramon/zapsign_lead_status_job_spec.rb spec/requests/cliente/painel_spec.rb`
Expected: PASS (os exemplos antigos seguem: env desligada ⇒ o job de sempre), sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/public/api/v1/zapsign_webhooks_controller.rb app/jobs/ramon/zapsign_lead_status_job.rb app/controllers/cliente/painel_controller.rb spec/requests/public/api/v1/zapsign_webhooks_spec.rb spec/jobs/ramon/zapsign_lead_status_job_spec.rb spec/requests/cliente/painel_spec.rb
git commit -m "feat(fluxos): assinatura e documento do Painel e aviso do contrato no ZapSign pela decisão do evento (chaves desligadas)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 5: Chegada de cliente (espera do motor) e ata da reunião pela decisão do evento — mecânica

**Files:**
- Modify: `app/controllers/api/v1/accounts/ramon_chegadas_controller.rb` (`create`)
- Modify: `app/controllers/api/v1/accounts/ramon_reunioes_controller.rb` (`create`, `reprocessar`, novo `pedir_ata` privado)
- Test: `spec/controllers/api/v1/accounts/ramon_chegadas_controller_spec.rb`, `spec/requests/api/v1/accounts/ramon_reunioes_spec.rb`

**Interfaces:**
- Consumes: `Externos.evento` (Task 3); `escalar_chegada`, `escrever_ata` (Task 2); `Ramon::FluxoRelogioJob` (retoma esperas vencidas).

- [ ] **Step 1: Write the failing tests**

(a) `ramon_chegadas_controller_spec.rb` — novo `it` depois de 'recepção avisa e agenda a escalada':

```ruby
  it 'fluxo "Chegada de cliente" no comando: o código não agenda; o fluxo espera 3 min e escala (o alerta volta ao vivo)' do
    with_modified_env(RAMON_FLUXO_CHEGADA: 'on') do
      Ramon::Fluxos::Migracao.semear(account, 'chegada_cliente')
      Ramon::Fluxos::Migracao.mudar_modo!(account, 'chegada_cliente', 'normal')
      expect { avisar }.not_to have_enqueued_job(Ramon::ChegadaEscalarJob)
    end
    chegada = Chegada.find(response.parsed_body['id'])
    perform_enqueued_jobs(only: Ramon::FluxoAvancarJob)
    execucao = Ramon::Fluxos::Migracao.fluxo(account, 'chegada_cliente').execucoes.sole
    expect(execucao).to have_attributes(status: 'esperando', ensaio: false)
    expect(execucao.retomar_em).to be_within(10.seconds).of(3.minutes.from_now)
    travel(3.minutes + 1.second) do
      perform_enqueued_jobs(only: Ramon::FluxoAvancarJob) { Ramon::FluxoRelogioJob.perform_now }
    end
    expect(chegada.reload.estado).to eq('escalado')
  end
```
Rastreio: o 1º `FluxoAvancarJob` anda `esperar` (3 min a partir de agora) e solta com `retomar_em`. No `travel`, o relógio enfileira o avanço da execução vencida; o `perform_enqueued_jobs(only:)` com bloco roda esse job → `escalar_chegada` → `escalar!` (ninguém respondeu).

(b) `ramon_reunioes_spec.rb` — dentro do `describe 'POST /api/v1/accounts/:id/ramon_reunioes/:id/reprocessar'`, novo `it`:

```ruby
    it 'fluxo "Ata da reunião" no comando: Refazer não enfileira pelo código; o fluxo pede o mesmo job (execução nova)' do
      reuniao = create(:reuniao, account: account, status: 'erro', erro: 'boom')
      with_modified_env(RAMON_FLUXO_ATA_REUNIAO: 'on') do
        Ramon::Fluxos::Migracao.semear(account, 'ata_reuniao')
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'ata_reuniao', 'normal')
        expect do
          post "/api/v1/accounts/#{account.id}/ramon_reunioes/#{reuniao.id}/reprocessar", headers: agent.create_new_auth_token
        end.not_to have_enqueued_job(Ramon::ReuniaoAtaJob)
      end
      expect { perform_enqueued_jobs(only: Ramon::FluxoAvancarJob) }.to have_enqueued_job(Ramon::ReuniaoAtaJob).with(reuniao.id)
      execucao = Ramon::Fluxos::Migracao.fluxo(account, 'ata_reuniao').execucoes.sole
      expect([execucao.ensaio, execucao.status, execucao.contexto.dig('gatilho', 'evento')]).to eq([false, 'concluida', 'refazer'])
    end
```
(Conferir no arquivo os nomes `account`/`agent` do `let` — os exemplos vizinhos usam esses.)

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/controllers/api/v1/accounts/ramon_chegadas_controller_spec.rb spec/requests/api/v1/accounts/ramon_reunioes_spec.rb`
Expected: FAIL — os jobs ainda são enfileirados direto; nenhuma execução.

- [ ] **Step 3: Implementation**

(a) `ramon_chegadas_controller.rb#create` — `Ramon::ChegadaEscalarJob.set(wait: Chegada::ESCALAR_APOS).perform_later(chegada.id)` vira:

```ruby
    # B5: pelo código (como sempre) ou pelo fluxo "Chegada de cliente" — espera do motor (3 a 4 min) — (RAMON_FLUXO_CHEGADA).
    Ramon::Fluxos::Externos.evento('chegada_cliente', 'chegada_cliente', chegada) do
      Ramon::ChegadaEscalarJob.set(wait: Chegada::ESCALAR_APOS).perform_later(chegada.id)
    end
```

(b) `ramon_reunioes_controller.rb` — em `create`, `Ramon::ReuniaoAtaJob.perform_later(reuniao.id)` vira `pedir_ata(reuniao, 'gravada')`; em `reprocessar`, `Ramon::ReuniaoAtaJob.perform_later(@reuniao.id)` vira `pedir_ata(@reuniao, 'refazer')`; no `private`:

```ruby
  # B5: pelo código (como sempre) ou pelo fluxo "Ata da reunião" (RAMON_FLUXO_ATA_REUNIAO); {evento} = gravada | refazer.
  def pedir_ata(reuniao, evento)
    Ramon::Fluxos::Externos.evento('ata_reuniao', 'reuniao_gravada', reuniao, 'evento' => evento) do
      Ramon::ReuniaoAtaJob.perform_later(reuniao.id)
    end
  end
```

- [ ] **Step 4: Run to verify they pass**

Run (CI): os 2 specs do Step 2 + `bundle exec rspec spec/jobs/ramon/reuniao_ata_job_spec.rb spec/jobs/ramon/chegada_escalar_job_spec.rb` e `bundle exec rubocop app/controllers/api/v1/accounts/ramon_chegadas_controller.rb app/controllers/api/v1/accounts/ramon_reunioes_controller.rb spec/controllers/api/v1/accounts/ramon_chegadas_controller_spec.rb spec/requests/api/v1/accounts/ramon_reunioes_spec.rb`
Expected: PASS, sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/accounts/ramon_chegadas_controller.rb app/controllers/api/v1/accounts/ramon_reunioes_controller.rb spec/controllers/api/v1/accounts/ramon_chegadas_controller_spec.rb spec/requests/api/v1/accounts/ramon_reunioes_spec.rb
git commit -m "feat(fluxos): chegada de cliente (espera do motor) e ata da reunião pela decisão do evento (chaves desligadas)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 6: Acervo das peças (Drive depois de publicar + espelho no Notion) pela decisão do evento — mecânica

**Files:**
- Modify: `app/models/peca.rb` (`espelhar_notion` público)
- Modify: `app/jobs/ramon/publicar_pecas_job.rb` (`pos_publicacao`, `no_ar_apos_erro`)
- Test: `spec/models/peca_spec.rb`, `spec/jobs/ramon/publicar_pecas_job_spec.rb`

**Interfaces:**
- Consumes: `Externos.evento` (Task 3); `acervo_drive`, `espelho_notion` (Task 2).
- Produces: `Peca#espelhar_notion` público (callback + chamada depois de `update_columns`).

- [ ] **Step 1: Write the failing tests**

(a) `spec/models/peca_spec.rb` — novo `it` depois de 'enfileira o espelho do Notion só quando o status muda':

```ruby
  it 'fluxo "Espelho das peças no Notion" no comando: a mudança de status vai pelo fluxo, que pede o mesmo job' do
    peca = create(:peca)
    with_modified_env(RAMON_FLUXO_ACERVO_PECAS: 'on') do
      Ramon::Fluxos::Migracao.semear(peca.account, 'acervo_pecas')
      Ramon::Fluxos::Migracao.mudar_modo!(peca.account, 'acervo_pecas', 'normal')
      expect { peca.update!(status: 'reprovado') }.not_to have_enqueued_job(Ramon::NotionEspelhoJob)
    end
    expect { perform_enqueued_jobs(only: Ramon::FluxoAvancarJob) }.to have_enqueued_job(Ramon::NotionEspelhoJob).with(peca.id)
    execucao = Ramon::Fluxos::Migracao.fluxo(peca.account, 'acervo_pecas_notion').execucoes.sole
    expect(execucao.contexto.dig('gatilho', 'evento')).to eq('reprovado')
  end
```

(b) `spec/jobs/ramon/publicar_pecas_job_spec.rb` — novo `it` depois de 'publica a peça vencida e grava id e link':

```ruby
  it 'fluxos do acervo no comando: o Drive sai pelo fluxo; a rajada de status (publicando → publicado) não perde o Notion' do
    peca
    account = peca.account
    with_modified_env(RAMON_FLUXO_ACERVO_PECAS: 'on') do
      Ramon::Fluxos::Migracao.semear(account, 'acervo_pecas')
      Ramon::Fluxos::Migracao.mudar_modo!(account, 'acervo_pecas', 'normal')
      # 'publicando' cria a execução do espelho (ainda na fila); 'publicado' bate no índice único → o código espelha (reserva)
      expect { described_class.perform_now }
        .to have_enqueued_job(Ramon::NotionEspelhoJob).with(peca.id).exactly(:once)
    end
    expect(Ramon::Fluxos::Migracao.fluxo(account, 'acervo_pecas_notion').execucoes.count).to eq(1)
    expect { perform_enqueued_jobs(only: Ramon::FluxoAvancarJob) }
      .to have_enqueued_job(Ramon::ConteudoDriveJob).with(peca.id).and have_enqueued_job(Ramon::NotionEspelhoJob).with(peca.id)
    expect(peca.reload.status).to eq('publicado')
  end
```
Rastreio: `perform_now` não roda os jobs enfileirados (sem bloco de `perform_enqueued_jobs`): transição `agendado → publicando` (callback → evento → execução do espelho criada, `esperando`); `update!(ig_media_id)` (sem mudança de status); `update!(status: 'publicado')` (callback → evento → `RecordNotUnique` → reserva → `NotionEspelhoJob` direto, 1×); `pos_publicacao` → evento `peca_publicada` → execução do Drive (sem `ConteudoDriveJob` direto). Depois, os 2 avanços pedem `ConteudoDriveJob` e o `NotionEspelhoJob` da 1ª execução (o job lê o status atual, `publicado`).

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/models/peca_spec.rb spec/jobs/ramon/publicar_pecas_job_spec.rb`
Expected: FAIL — o código ainda enfileira direto (Notion 2× no publicar; Drive direto).

- [ ] **Step 3: Implementation**

(a) `app/models/peca.rb` — tirar `espelhar_notion` do `private` e pô-lo antes do `private`, assim:

```ruby
  # Público (B5): o PublicarPecasJob chama depois de update_columns (que pula o callback). Pelo código (como sempre) ou
  # pelo fluxo "Espelho das peças no Notion" (RAMON_FLUXO_ACERVO_PECAS); {evento} = o status novo.
  def espelhar_notion
    Ramon::Fluxos::Externos.evento('acervo_pecas', 'peca_mudou_status', self, 'evento' => status) { Ramon::NotionEspelhoJob.perform_later(id) }
  end
```

(b) `app/jobs/ramon/publicar_pecas_job.rb`:
- `pos_publicacao`: `Ramon::ConteudoDriveJob.perform_later(peca.id)` vira

```ruby
    # B5: pelo código (como sempre) ou pelo fluxo "Acervo das peças no Drive" (RAMON_FLUXO_ACERVO_PECAS).
    Ramon::Fluxos::Externos.evento('acervo_pecas', 'peca_publicada', peca) { Ramon::ConteudoDriveJob.perform_later(peca.id) }
```
- `no_ar_apos_erro`: `Ramon::NotionEspelhoJob.perform_later(peca.id) # update_columns pula …` vira `peca.espelhar_notion # update_columns pula o espelho do after_update_commit`.

- [ ] **Step 4: Run to verify they pass**

Run (CI): os 2 specs + `bundle exec rspec spec/jobs/ramon/notion_espelho_job_spec.rb spec/jobs/ramon/conteudo_drive_job_spec.rb` e `bundle exec rubocop app/models/peca.rb app/jobs/ramon/publicar_pecas_job.rb spec/models/peca_spec.rb spec/jobs/ramon/publicar_pecas_job_spec.rb`
Expected: PASS, sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/models/peca.rb app/jobs/ramon/publicar_pecas_job.rb spec/models/peca_spec.rb spec/jobs/ramon/publicar_pecas_job_spec.rb
git commit -m "feat(fluxos): acervo das peças (Drive e Notion) pela decisão do evento (chave desligada)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 7: Editor — 6 gatilhos, 7 rotinas, aviso "não é de lead" e os 8 desenhos conferidos — mecânica

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js` (`GATILHOS`, `ROTINAS`)
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/ConfigGatilho.vue`
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json`, `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`
- Test: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/migrados.spec.js` (o `i18n.spec.js` cobre o catálogo sozinho)

**Interfaces:**
- Consumes: `Grafo::GATILHOS` (Task 1), `Rotinas::Externos::ROTINAS` (Task 2), os 8 JSON (Task 3).
- Produces: `GATILHOS` com 6 entradas `alvo: 'outro'`; `ROTINAS` com as 7 no fim.

- [ ] **Step 1: Write the failing test**

`specs/migrados.spec.js` — importar no topo (mesmo caminho relativo dos outros) e trocar a importação de `'../fluxo'` para incluir `ROTINAS`:

```js
import { REGRAS_ADVBOX, ROTINAS, TIPOS_ATIVIDADE } from '../fluxo';
import assinaturaPainel from '../../../../../../../../db/seeds/ramon/fluxos/migrados/assinatura_painel.json';
import contratoAssinado from '../../../../../../../../db/seeds/ramon/fluxos/migrados/contrato_zapsign_assinado.json';
import contratoRecusado from '../../../../../../../../db/seeds/ramon/fluxos/migrados/contrato_zapsign_recusado.json';
import documentoPainel from '../../../../../../../../db/seeds/ramon/fluxos/migrados/documento_painel.json';
import chegada from '../../../../../../../../db/seeds/ramon/fluxos/migrados/chegada_cliente.json';
import ata from '../../../../../../../../db/seeds/ramon/fluxos/migrados/ata_reuniao.json';
import acervoDrive from '../../../../../../../../db/seeds/ramon/fluxos/migrados/acervo_pecas_drive.json';
import acervoNotion from '../../../../../../../../db/seeds/ramon/fluxos/migrados/acervo_pecas_notion.json';
```
e no fim do arquivo:

```js
// = Ramon::Fluxos::Externos::GRUPOS (a ordem do semear)
const EXTERNOS = [
  assinaturaPainel,
  contratoAssinado,
  contratoRecusado,
  documentoPainel,
  chegada,
  ata,
  acervoDrive,
  acervoNotion,
];

describe('fluxos migrados: automações de fora do funil (B5-externos)', () => {
  it('os 8 publicam, cada um com o seu gatilho e sem cancelar por etapa', () => {
    EXTERNOS.forEach(d => expect(validar(d.desenho)).toEqual([]));
    expect(EXTERNOS.map(d => d.desenho.nos[0].config.tipo)).toEqual([
      'assinatura_painel',
      'contrato_assinado',
      'contrato_recusado',
      'documento_painel',
      'chegada_cliente',
      'reuniao_gravada',
      'peca_publicada',
      'peca_mudou_status',
    ]);
    EXTERNOS.forEach(d =>
      expect(d.desenho.nos[0].config.cancelar_se_sair_da_etapa).toBe(false)
    );
  });

  it('cada um chama a rotina pronta de hoje; só a chegada espera (3 minutos) antes', () => {
    const rotinas = EXTERNOS.map(d =>
      doTipo(d, 'rotina').map(n => n.config.rotina)
    );
    expect(rotinas).toEqual([
      ['conferir_assinatura_painel'],
      ['aviso_contrato'],
      ['aviso_contrato'],
      ['processar_envio_painel'],
      ['escalar_chegada'],
      ['escrever_ata'],
      ['acervo_drive'],
      ['espelho_notion'],
    ]);
    expect(ROTINAS).toEqual(expect.arrayContaining(rotinas.flat()));
    expect(chegada.desenho.nos.map(n => n.tipo)).toEqual([
      'gatilho',
      'esperar',
      'rotina',
    ]);
    expect(doTipo(chegada, 'esperar')[0].config).toMatchObject({
      quantidade: 3,
      unidade: 'minutos',
    });
  });

  it('nenhum fala com o cliente nem tem passo livre que grava fora: só gatilho, espera e rotina pronta', () => {
    const tipos = EXTERNOS.flatMap(d => d.desenho.nos.map(n => n.tipo));
    expect([...new Set(tipos)].sort()).toEqual(['esperar', 'gatilho', 'rotina']);
  });
});
```
(Se `TIPOS_ATIVIDADE`/`REGRAS_ADVBOX` já estavam importados, só acrescente `ROTINAS` na mesma linha, em ordem alfabética.)

- [ ] **Step 2: Run to verify it fails**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts`
Expected: FAIL — `validar` acusa "gatilho desconhecido" nos 8 (o front ainda não conhece os gatilhos); `ROTINAS` sem as 7.

- [ ] **Step 3: Implementation**

(a) `fluxo.js` — no fim de `GATILHOS` (depois de `manual` e do que as irmãs puseram):

```js
  // B5-externos: o alvo é o registro do evento, não lead nem conversa (o "Testar com um lead…" não serve)
  { tipo: 'assinatura_painel', icone: 'i-lucide-pen-line', alvo: 'outro' },
  { tipo: 'documento_painel', icone: 'i-lucide-file-up', alvo: 'outro' },
  { tipo: 'chegada_cliente', icone: 'i-lucide-door-open', alvo: 'outro' },
  { tipo: 'reuniao_gravada', icone: 'i-lucide-mic', alvo: 'outro' },
  { tipo: 'peca_publicada', icone: 'i-lucide-image-up', alvo: 'outro' },
  { tipo: 'peca_mudou_status', icone: 'i-lucide-images', alvo: 'outro' },
```
e no fim de `ROTINAS` (depois das da B5-conta/B5-leads):

```js
  // B5-externos (= Ramon::Fluxos::Rotinas::Externos::ROTINAS)
  'conferir_assinatura_painel',
  'aviso_contrato',
  'processar_envio_painel',
  'escalar_chegada',
  'escrever_ata',
  'acervo_drive',
  'espelho_notion',
```
(Se o `validar.js` valida gatilho por uma lista própria em vez de `GATILHOS`, acrescente os 6 nela também — `grep -n "GATILHOS\|gatilho" validar.js`.)

(b) `ConfigGatilho.vue` — antes do `<p v-if="config.tipo === 'manual'" …>`:

```vue
    <p v-if="alvo === 'outro'" class="text-xs text-n-slate-10">
      {{ t(`${K}.ALVO_OUTRO_AJUDA`) }}
    </p>
```

(c) i18n — mesma posição nos dois arquivos, dentro de `CAPTAIN_RAMON.FLUXOS`:

| Bloco | Onde | en | pt_BR |
|---|---|---|---|
| `GATILHOS` | no fim (depois de `"relogio"` e do que as irmãs puseram; pôr vírgula no anterior) | ver abaixo | ver abaixo |
| `PAINEL` (o do gatilho, onde está `"DOCUMENTO_AJUDA"`) | depois de `"DOCUMENTO_AJUDA"` (pôr vírgula nele) | `"ALVO_OUTRO_AJUDA": "This trigger is not about a lead or a conversation: Test with a lead does not apply. Check the runs of the real events."` | `"ALVO_OUTRO_AJUDA": "Este gatilho não é de lead nem de conversa: o Testar com um lead não serve. Confira pelas execuções dos eventos reais."` |
| `ROTINAS` | no fim | ver abaixo | ver abaixo |
| `ROTINAS_AJUDA` | no fim | ver abaixo | ver abaixo |

`GATILHOS` en:
```json
        "assinatura_painel": "Client Portal signature changed (ZapSign)",
        "documento_painel": "Client sent a document through the Portal",
        "chegada_cliente": "Front desk announced a client arrival",
        "reuniao_gravada": "Meeting recorded (or Redo minutes)",
        "peca_publicada": "Post published on Instagram",
        "peca_mudou_status": "Post changed status"
```
`GATILHOS` pt_BR:
```json
        "assinatura_painel": "Assinatura do Painel do Cliente mudou (ZapSign)",
        "documento_painel": "Cliente enviou documento pelo Painel",
        "chegada_cliente": "Recepção avisou a chegada de um cliente",
        "reuniao_gravada": "Reunião gravada (ou Refazer ata)",
        "peca_publicada": "Peça publicada no Instagram",
        "peca_mudou_status": "Peça mudou de status"
```
`ROTINAS` en:
```json
        "conferir_assinatura_painel": "Check on ZapSign and mark the Portal signature",
        "aviso_contrato": "Contract history and bell (signed or refused)",
        "processar_envio_painel": "Portal document: Drive, push and ADVBOX tasks",
        "escalar_chegada": "Escalate the arrival (if nobody answered)",
        "escrever_ata": "Transcribe and write the meeting minutes",
        "acervo_drive": "Copy the published post to Drive",
        "espelho_notion": "Mirror the post status on Notion"
```
`ROTINAS` pt_BR:
```json
        "conferir_assinatura_painel": "Conferir no ZapSign e marcar a assinatura no Painel",
        "aviso_contrato": "Histórico e sino do contrato (assinado ou recusado)",
        "processar_envio_painel": "Documento do Painel: Drive, push e tarefas no ADVBOX",
        "escalar_chegada": "Escalar a chegada (se ninguém respondeu)",
        "escrever_ata": "Transcrever e escrever a ata da reunião",
        "acervo_drive": "Copiar a peça publicada para o Drive",
        "espelho_notion": "Espelhar o status da peça no Notion"
```
`ROTINAS_AJUDA` en:
```json
        "conferir_assinatura_painel": "Same as today: asks ZapSign for the real status and marks it on the Client Portal. A signature cancelled in the hub does not change. ZapSign down: tries again by itself. Only for the Portal signature trigger.",
        "aviso_contrato": "Same as today: a line in the lead history and a bell to everyone. Never marks the lead as won. The badge on the card and the ZapSign check stay in the code.",
        "processar_envio_painel": "Same as today: saves the file on Drive (if set up), push on the phone and 2 ADVBOX tasks. Writes to ADVBOX for real, once per document; ADVBOX down, tries again up to 5 times. Only for the Portal document trigger.",
        "escalar_chegada": "If nobody answered, the alert rings again on the screen of who announced it (live, not the bell). Already answered: does nothing. Put it after a wait. Only for the client arrival trigger.",
        "escrever_ata": "Same as today: transcribes the audio and the AI writes the minutes in the meeting, in the usual queue (tries up to 3 times; if it fails, the meeting shows the error and the Redo button). Only for the recorded meeting trigger.",
        "acervo_drive": "Same as today: images and caption in Posts Instagram, on Drive. Only for the published post trigger.",
        "espelho_notion": "Same as today: updates the post status on the Notion board (only with the Notion token). Only for the post triggers."
```
`ROTINAS_AJUDA` pt_BR:
```json
        "conferir_assinatura_painel": "O mesmo de hoje: pergunta ao ZapSign o status real e marca no Painel do Cliente. Assinatura cancelada no hub não muda. ZapSign fora do ar: tenta de novo sozinho. Só serve no gatilho Assinatura do Painel.",
        "aviso_contrato": "O mesmo de hoje: linha no histórico do lead e sino para todos. Nunca marca o lead como ganho. O selo no card e a conferência no ZapSign continuam no código.",
        "processar_envio_painel": "O mesmo de hoje: guarda o arquivo no Drive (se configurado), push no celular e 2 tarefas no ADVBOX. Grava no ADVBOX de verdade, uma vez por documento; ADVBOX fora do ar, tenta de novo até 5 vezes. Só serve no gatilho Documento do Painel.",
        "escalar_chegada": "Se ninguém respondeu, o alerta volta a tocar na tela de quem avisou (ao vivo, não é o sino). Já respondida: não faz nada. Ponha depois de uma espera. Só serve no gatilho Chegada de cliente.",
        "escrever_ata": "O mesmo de hoje: transcreve o áudio e a IA escreve a ata na reunião, na fila de sempre (tenta até 3 vezes; se não der, a reunião fica com erro e o botão Refazer). Só serve no gatilho Reunião gravada.",
        "acervo_drive": "O mesmo de hoje: imagens e legenda em Posts Instagram, no Drive. Só serve no gatilho Peça publicada.",
        "espelho_notion": "O mesmo de hoje: atualiza o status da peça no quadro Peças do Notion (só com o token do Notion). Só serve nos gatilhos de peça."
```
(Vírgula no último item que já existia em cada bloco; nada de `@ | { }`; editar à mão com Edit.)

- [ ] **Step 4: Run to verify it passes**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts`
Expected: PASS — **mesmos arquivos de B, B + 3 testes** (migrados +3; o i18n cobre os 6 gatilhos e as 7 rotinas dentro dos `it` que já existem).
Run: `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes`
Expected: sem `error`.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js app/javascript/dashboard/routes/dashboard/captain/automacoes/ConfigGatilho.vue app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/migrados.spec.js
git commit -m "feat(fluxos): editor com os gatilhos e as rotinas de fora do funil; desenhos B5-externos conferidos" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 8: Verificação final + notas na spec + texto do PR — julgamento

**Files:**
- Modify: `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (seção nova no fim)

- [ ] **Step 1: Front inteiro**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts
./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes
git status --short
```
Expected: B + 3 verdes; eslint sem `error`; `vitest.local.config.ts` fora da lista.

- [ ] **Step 2: Varredura de regras**

```bash
BASE=$(git merge-base HEAD origin/ramon)
git diff $BASE --stat -- enterprise db/migrate db/schema.rb db/seeds/ramon/fluxos/sistema
grep -rn "ChegadaEscalarJob.set\|ReuniaoAtaJob.perform_later\|PortalEnvioJob.perform_later\|ZapsignStatusJob.perform_later\|ConteudoDriveJob.perform_later\|NotionEspelhoJob.perform_later" app
grep -rn "RAMON_FLUXO_\(ASSINATURA_PAINEL\|CONTRATO_ZAPSIGN\|DOCUMENTO_PAINEL\|CHEGADA\|ATA_REUNIAO\|ACERVO_PECAS\)" app .env.example
for f in app/services/ramon/fluxos/disparo.rb app/services/ramon/fluxos/grafo.rb app/services/ramon/fluxos/migracao.rb app/services/ramon/fluxos/externos.rb app/services/ramon/fluxos/rotinas/externos.rb app/models/fluxo_execucao.rb; do echo "$f $(grep -cvE '^\s*(#|$)' $f)"; done
```
Expected: o 1º vazio (sistema/*.json ficam — E7; sem migração); no 2º, cada `perform_later` desses jobs aparece **só** dentro de um bloco de `Externos.evento` ou de uma rotina de `rotinas/externos.rb` (e o `ZapsignLeadStatusJob.perform_later` do `ZapsignContractService` não entra na lista — ele é o evento); no 3º, as 6 envs em `externos.rb` e no `.env.example`; tamanhos dentro dos limites (classe 175, módulo 100).

- [ ] **Step 3: Notas na spec** — acrescentar ao fim de `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (número = a próxima seção livre depois das da B5-conta/B5-leads):

```markdown
## NN. Notas da B5-externos (07/10/2026) — automações que começam fora do funil

- **Escopo (Eduardo, 07/10):** migram, com chave desligada + reserva pelo código, a conferência da assinatura do Painel (webhook do ZapSign), o histórico e o sino do contrato no ZapSign, o documento enviado pelo Painel (Drive, push, 2 tarefas no ADVBOX), a escalada da chegada de cliente, a ata da reunião gravada e o acervo das peças (Drive depois de publicar + espelho no Notion). 6 grupos em `Ramon::Fluxos::Externos::GRUPOS` (mesclados em `Migracao::GRUPOS`), 8 fluxos (`contrato_zapsign` e `acervo_pecas` têm 2, um por gatilho), 6 envs `RAMON_FLUXO_{ASSINATURA_PAINEL,CONTRATO_ZAPSIGN,DOCUMENTO_PAINEL,CHEGADA,ATA_REUNIAO,ACERVO_PECAS}`. `rake ramon:fluxos:migracao:{criar,modo}[grupo,conta]`.
- **A decisão é do evento:** `Ramon::Fluxos::Externos.evento(grupo, gatilho, alvo, dados) { código de hoje }` — lê `assumiu?` uma vez; fluxo migrado com `assumido`; o bloco roda se o fluxo não está no comando **ou não começou este evento** (ocupado com o mesmo alvo, erro do motor) — reserva; por fim os fluxos comuns, sem `assumido`. Os 8 gatilhos estão em `Disparo::DUAS_VEZES` (derivado de `Externos.gatilhos`).
- **Alvo = o registro do evento:** `PortalAssinatura`, `PortalEnvio`, `Chegada`, `Reuniao`, `Peca` (o contrato é do `Lead`). `FluxoExecucao.lead_de` nunca adivinha lead pelo id (o `else` antigo tratava qualquer alvo como conversa); `Reuniao` com lead vinculado traz o lead. Rajada no mesmo registro (status da peça, webhook repetido): o 2º evento bate no índice único e vai pela reserva.
- **Gatilhos novos:** `assinatura_painel`, `documento_painel`, `chegada_cliente`, `reuniao_gravada` (`{evento}` = gravada|refazer), `peca_publicada`, `peca_mudou_status` (`{evento}` = o status). O contrato reusa `contrato_assinado`/`contrato_recusado`. No editor, `alvo: 'outro'`: o "Testar com um lead…" não serve (a rotina falha dizendo com o que roda).
- **Rotinas prontas (`rotinas/externos.rb`, registro da B5-conta):** `conferir_assinatura_painel`, `aviso_contrato` (= `ZapsignLeadStatusJob.avisar`, o mesmo sino `ramon_contract_status`), `processar_envio_painel`, `escalar_chegada` (= `Chegada#escalar!`, depois de `esperar 3 minutos` do motor — 3 a 4 min, N1), `escrever_ata`, `acervo_drive`, `espelho_notion`. Os pesados pedem o **mesmo job** de hoje (fila e tentativas do código; o motor daria por órfã a execução `rodando` > 10 min — o whisper repetiria). A trilha diz "pedido"; falhas aparecem onde aparecem hoje (N3).
- **Ficou no código (o evento em si):** a conferência HTTP e o selo `zapsign.status` do contrato (e a trava `atual?`); gravar o envio, a chegada, a reunião; as transições da peça.
- **Fica para a limpeza (outro PR, 2 semanas depois em normal):** os JSON `sistema/{assinatura_painel,contrato_zapsign,documento_painel,chegada_cliente,ata_reuniao,acervo_pecas}.json` **e** as linhas `origem: sistema` deles; as 6 envs; os blocos de código-reserva dentro de `Externos.evento` só se o Eduardo abrir mão da reserva.
```

- [ ] **Step 4: Texto do PR (não abrir — gate do Eduardo)** — deixar no relatório final:

```markdown
Automações em fluxo — B5-externos: as 6 automações que começam fora do funil ganham fluxos de verdade, editáveis depois de assumirem: **assinatura pelo Painel do Cliente**, **contrato no ZapSign** (histórico e sino), **documento enviado pelo Painel** (Drive, push e tarefas no ADVBOX), **chegada de cliente** (o alerta volta se ninguém responder em 3 min), **ata da reunião gravada** e **acervo das peças** (Drive e Notion). Cada uma tem a sua chave: desligada (padrão), tudo segue pelo código como hoje; ligada e com os fluxos em modo normal, o fluxo faz e o código para — e, se o fluxo não começar um evento, o código faz aquele, nunca em dobro. O trabalho pesado (transcrição, Drive, ADVBOX, ZapSign, Notion) continua nos jobs de hoje, com as mesmas travas e tentativas. Nada fala com o cliente.

## Closes
- Spec `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` §8 (migração) — automações de fora do funil; notas novas no fim.

## How to test
1. Depois do deploy, para cada grupo: `rake "ramon:fluxos:migracao:criar[<grupo>,2]"` → "modo sombra, ligado" e "Agora o CÓDIGO faz …".
2. Inteligência → Automações → Meus fluxos: os 8 fluxos com o selo "em sombra"; o painel do gatilho avisa que o "Testar com um lead…" não serve.
3. Virar as chaves e rodar o teste ao vivo da seção "Operação" (chegada e ata pela tela; os outros com registros de teste).

## What changed
- `Ramon::Fluxos::Externos` (6 grupos + a decisão do evento), 7 rotinas prontas em `Ramon::Fluxos::Rotinas::Externos`, 6 gatilhos, `FluxoExecucao.lead_de`; os 6 pontos do código passam pela decisão; envs `RAMON_FLUXO_*` desligadas; sem migração.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR
```

- [ ] **Step 5: Smoke em bloco** — anotar no relatório a seção "Operação depois do deploy" inteira (o Eduardo roda via `!` e cola as saídas).

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md
git commit -m "docs(fluxos): notas da B5-externos na spec" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

Sem push.

---

## Operação depois do deploy

Conta da banca = **2**; console = `docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "<task>"` / `… rails runner '<ruby>'` (o Eduardo roda via `!` e cola a saída). Deploy = o de sempre, **sem migração**. **Junto com o deploy**, acrescentar ao `chatwoot.env` em `/opt/intranet-ramon` as 6 envs `=on` (`RAMON_FLUXO_ASSINATURA_PAINEL`, `RAMON_FLUXO_CONTRATO_ZAPSIGN`, `RAMON_FLUXO_DOCUMENTO_PAINEL`, `RAMON_FLUXO_CHEGADA`, `RAMON_FLUXO_ATA_REUNIAO`, `RAMON_FLUXO_ACERVO_PECAS`) — seguro: sem os fluxos em modo normal, o código segue fazendo tudo. Recriar web **e** worker.

**1. Checagem (somente leitura)** — fluxos comuns já ligados nos gatilhos do contrato (eles passam a receber também `{texto}` vazio, nada muda):
```
docker exec intranet-ramon-chatwoot-web-1 bundle exec rails runner 'p Account.find(2).fluxos.executaveis.where(gatilho_tipo: %w[contrato_assinado contrato_recusado]).pluck(:id, :nome)'
```

**2. Criar os 8 fluxos (código ainda no comando).**
```
for g in assinatura_painel contrato_zapsign documento_painel chegada_cliente ata_reuniao acervo_pecas; do docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:migracao:criar[$g,2]"; done
```
Esperado: cada um "modo sombra, ligado" e "Agora o CÓDIGO faz … (os fluxos ensaiam)". Rodar de novo não duplica. (N5-b: parar aqui 1–2 dias e conferir as execuções-ensaio dos eventos reais em Automações.)

**3. Virar** (todas, ou só as aprovadas):
```
for g in assinatura_painel contrato_zapsign documento_painel chegada_cliente ata_reuniao acervo_pecas; do docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:migracao:modo[$g,2,normal]"; done
```
Esperado: "Agora os FLUXOS fazem …" em cada um.

**4. Teste ao vivo pela tela (Eduardo):**
- **Chegada:** Equipe → avisar a chegada de "TESTE B5" **para você mesmo**; não responda. Entre **3 e 4 min** o alerta volta a tocar. Automações → "Chegada de cliente" → a execução (sem selo ensaio): espera → "escalou: o alerta voltou…".
- **Ata:** Reuniões → gravar ~10 s dizendo "teste da ata pelo fluxo" → a ata aparece em 1–2 min. Automações → "Ata da reunião" → execução "ata pedida…". Depois, apagar a reunião na tela.

**5. Teste ao vivo com registros de teste (nada vai ao ADVBOX nem ao ZapSign; N4):**
```
docker exec intranet-ramon-chatwoot-web-1 bundle exec rails runner '
a = Account.find(2)
x = Ramon::Fluxos::Externos
pc = PortalCliente.create!(account: a, nome: "TESTE B5", cpf: "00000000000", advbox_customer_id: 999_000_005)
s = pc.assinaturas.create!(doc_token: "teste-b5-#{SecureRandom.hex(4)}", signer_token: "teste", nome: "TESTE B5", status: "cancelado")
x.evento("assinatura_painel", "assinatura_painel", s) { puts "ASSINATURA: o CODIGO fez (nao devia)" }
e = pc.envios.create!(lawsuit_id: 1, item: "TESTE B5", drive_file_id: "teste", advbox_post_id: "teste", juntada_post_id: "teste")
e.arquivo.attach(io: StringIO.new("teste"), filename: "teste.txt", content_type: "text/plain")
x.evento("documento_painel", "documento_painel", e) { puts "DOCUMENTO: o CODIGO fez (nao devia)" }
c = a.contacts.create!(name: "Teste B5", phone_number: "+5548900005555")
l = a.leads.create!(name: "Teste B5", contact: c, lead_stage: a.lead_stages.order(:position).first, source: "teste")
l.update!(custom_attributes: l.custom_attributes.to_h.merge("zapsign" => { "doc_token" => "teste-b5", "status" => "signed", "template_name" => "TESTE B5" }))
x.evento("contrato_zapsign", "contrato_assinado", l) { puts "CONTRATO: o CODIGO fez (nao devia)" }
p = Peca.create!(account: a, slug: "teste-b5-#{SecureRandom.hex(3)}", rodada: Date.current, tipo: "carrossel", gancho: "TESTE B5", conteudo: {})
p.update!(status: "reprovado")
x.evento("acervo_pecas", "peca_publicada", p) { puts "ACERVO: o CODIGO fez (nao devia)" }
puts "ok lead=#{l.id} peca=#{p.id}"'
```
Esperado: só `ok …` (nenhuma linha "o CODIGO fez"). Conferir em bloco:
- Automações: "Assinatura pelo Painel" (1 execução, "conferência no ZapSign pedida" — o job vê "cancelado" e não chama o ZapSign); "Documento enviado pelo Painel" (1, "Drive, push e tarefas do ADVBOX pedidos" — as travas `teste` pulam Drive e ADVBOX; **chega 1 push no celular** "Documento do cliente TESTE B5"); "Contrato assinado no ZapSign" (1, "histórico e sino a todos — contrato assinado"; o lead "Teste B5" tem a linha no histórico e **todos recebem o sino** — a limpeza apaga); "Espelho das peças no Notion" (1, status "reprovado" — sem página no Notion, o job não faz nada); "Acervo das peças no Drive" (1, "cópia no Drive pedida" — **aparece a pasta "AAAA-MM-DD — TESTE B5"** em Posts Instagram/Carrossel no Drive, se `RAMON_DRIVE_POSTS_ID` estiver configurado; apagar à mão).
- ADVBOX: nada novo. ZapSign: nada.

**6. Limpar o teste.**
```
docker exec intranet-ramon-chatwoot-web-1 bundle exec rails runner '
a = Account.find(2)
l = a.leads.find_by!(name: "Teste B5")
Notification.where(primary_actor: l).delete_all
l.lead_activities.delete_all
l.destroy!
a.contacts.find_by(phone_number: "+5548900005555")&.destroy!
PortalCliente.find_by!(account: a, nome: "TESTE B5").destroy!
a.pecas.where(gancho: "TESTE B5").destroy_all
a.chegadas.where(cliente_nome: "TESTE B5").delete_all
puts "ok"'
```
(`Account` tem `pecas` e `chegadas`.) Pasta "TESTE B5" do Drive: apagar à mão.

**7. Rollback (a qualquer momento, sem deploy, cada grupo independente).** `docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "ramon:fluxos:migracao:modo[<grupo>,2,sombra]"` → "Agora o CÓDIGO faz". Também seguro: desligar um fluxo na tela (no grupo de 2, desligar um devolve os dois pontos ao código), ou tirar a env e recriar. **Atenção na chegada:** uma execução que já esperava os 3 min termina pelo fluxo (escala se ninguém respondeu); chegadas novas voltam ao job do código — sem dobra.

**8. Depois (outro PR, E7).** Com 2 semanas em normal sem incidente: apagar os JSON `sistema/{assinatura_painel,contrato_zapsign,documento_painel,chegada_cliente,ata_reuniao,acervo_pecas}.json` **e** as linhas `origem: sistema` deles (a sincronização não apaga linha cujo JSON sumiu), as 6 envs, e — se o Eduardo abrir mão da reserva — os blocos de código dentro de `Externos.evento`.

---

## Divergências registradas (spec × este plano)

| # | Onde | Divergência | Motivo |
|---|---|---|---|
| 1 | Spec §8 B4+ ("sombra por alguns dias; comparar") | Direto + teste ao vivo (salvo N5-b) | E1 |
| 2 | Spec §4.1 (alvo = lead ou conversa) | Alvo = o registro do evento (`PortalAssinatura`, `PortalEnvio`, `Chegada`, `Reuniao`, `Peca`) | "não é lead nem conversa" (os desenhos do sistema); um alvo por registro evita barrar 2 eventos de registros diferentes |
| 3 | Desenhos `sistema/*.json` (passos de push/ADVBOX/sino separados) | Uma rotina pronta por automação (o job de hoje) | N3: fidelidade (fila, travas, tentativas) e a órfã de 10 min do motor |
| 4 | Desenho `sistema/contrato_zapsign.json` (`preencher_campo` do selo) | O selo fica no código | é o evento e a trava `atual?` (N2) |
| 5 | Desenho `sistema/acervo_pecas.json` (1 gatilho) | 2 fluxos / 2 gatilhos (`peca_publicada`, `peca_mudou_status`) | uma decisão por ponto do código |
