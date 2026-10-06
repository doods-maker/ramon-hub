# Automações em fluxo — B3 (aba "Do sistema" com as 29 automações, Rodar fluxo… e saída de Configurações → Automação) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Em Inteligência → Automações, a aba **"Do sistema"** mostra, em 5 grupos, as **29 automações que hoje rodam no código** desenhadas como fluxos só-leitura que o motor nunca executa (com selo nas 2 que saem para fora sem uma pessoa no meio); o painel do lead e o cabeçalho da conversa ganham **"Rodar fluxo…"** no menu ⋯ (só admin); e "Configurações → Automação" sai do menu (o link antigo cai em Automações).

**Architecture:** Os 29 desenhos são JSON versionados em `db/seeds/ramon/fluxos/sistema/<chave>.json` (`{nome, grupo, alcance?, descricao, limite_dia?, desenho}`). Um módulo novo `Ramon::Fluxos::Sistema` cria/atualiza, por conta, 1 `Fluxo` `origem: 'sistema'` por arquivo (`sistema_chave` = nome do arquivo) quando a lista abre (`GET ramon_fluxos`), sob o lock da conta, e devolve os "extras" que não têm coluna (Hoje, grupo, selo, rótulo do gatilho) lidos do JSON em memória. O motor nunca os roda: `Fluxo.executaveis` já exclui a origem, e a B3 põe **uma** guarda em `Disparo#iniciar` (funil comum de evento, relógio, "Rodar" e ensaio) + `ensaio` no `bloquear_sistema` da API. Front: abas e grupos na `Lista.vue`, painel "Como roda hoje" + selo no `Editor.vue` (que já é só-leitura para `origem: sistema` e já esconde Testar/Publicar), modal novo `RodarFluxo.vue` aberto pelo ⋯ do `LeadPanelBody.vue` e do `MoreActions.vue`, item do menu de Configurações removido e rota antiga redirecionando. Sem migração.

**Tech Stack:** Rails 7.1 / RSpec (só no CI), Postgres jsonb; Vue 3.5 `<script setup>`, vue-router 4, vue-i18n 9, Vitest 3 + @vue/test-utils, Histoire (story dos prints).

**Spec:** `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (§2 D6/D7, §7 tela, §8 migração, §10 fatia B3, §13 notas da B2b). Planos anteriores (estilo e decisões): `docs/superpowers/plans/2026-10-05-automacoes-fluxo-b1-motor.md`, `docs/superpowers/plans/2026-10-05-automacoes-fluxo-b2-quadro.md`, `docs/superpowers/plans/2026-10-06-automacoes-fluxo-b2b.md`.

## Escopo decidido pelo Eduardo em 06/10 (vence a spec)

1. **Sem conversor das regras nativas.** O rake `ramon:fluxos:converter_regras` da spec §8 **foi descartado**: produção tem **0 linhas** em `AutomationRule`, não há o que converter. Nenhuma task cria rake, `origem: 'convertido'` ou mapeamento `send_message → rascunho_texto`. A nota entra na spec (§14, Task 10).
2. **"Configurações → Automação" sai do menu** e a rota antiga redireciona para Inteligência → Automações. O motor nativo do Chatwoot (`AutomationRuleListener`; `AutomationRules::ActionService` continua servindo o passo `acao_chatwoot`) fica no código, sem tela. Pontos de entrada conferidos: só o item do `Sidebar.vue` e a rota `automation_list`; **não há** atalho no command bar (`useGoToCommandHotKeys.js` não tem automação), tecla, busca ou outro `router.push` para `automation_list`.
3. **Aba "Do sistema" com TODAS as 29 automações do código** (as 6 da spec + 23 menores), em 5 grupos: *Leads e conversas* · *Contrato e documentos* · *Painel do Cliente* · *Rotinas e relatórios* · *Instagram*. Onde os tipos de hoje não desenham com honestidade: gatilho → 1 passo descritivo (o tipo mais próximo, rótulo claro). As 2 que saem para fora sem uma pessoa no meio levam selo na linha e no desenho: **Avisos do Painel do Cliente** = "fala com o cliente" (desligado até o Eduardo aprovar os textos, `PORTAL_AVISOS`), **Publicar peças no Instagram** = "publica". "Hoje" só onde já existe fonte barata; senão "—".
4. **Lembretes de reunião**: 1 ciclo com rótulo "24h · 8h · 1h · 30 min · 5 min".
5. **Ensaio bloqueado** nos fluxos do sistema até cada um migrar (B4+): 403 na API, guarda no motor, e o botão "Testar com um lead…" escondido no desenho (já é `v-if="!somenteLeitura"` — conferido em `Editor.vue`, mantido).
6. **"Rodar fluxo…"** no menu ⋯ do painel do lead e do cabeçalho da conversa (spec §7), só admin.

## Global Constraints

- Base: produção **9cdd5c6** (B1 motor, B2 quadro e B2b no ar); branch `feat/fluxos-b3`, worktree `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-fluxos-b3`. Nunca `git push`, nunca abrir PR (gate do Eduardo / sessão principal).
- **Sem migração.** `ramon_fluxos` já tem `origem`, `sistema_chave`, `descricao`, `limite_dia`, `rascunho` (`db/schema.rb:1525-1542`); `grupo`, `alcance` e o rótulo do gatilho **não** viram coluna — saem do JSON em memória (`Sistema.extras`). Se alguma task achar que precisa de coluna/índice novo: pare e pergunte (última versão em `db/migrate`: `20261006100001`).
- **Rubocop do fork** (o CI barra): `Metrics/AbcSize` 26, `Metrics/MethodLength` 19, `Metrics/CyclomaticComplexity` 7, `Metrics/PerceivedComplexity` 8, `Metrics/ClassLength` 175, linha 150, `rubocop-rspec` (`RSpec/MultipleExpectations` 7, `RSpec/ExampleLength` 50). `RSpec/SpecFilePathFormat`: spec de `A::B::C` fica em `spec/.../a/b/c_spec.rb` (ex.: `Ramon::Fluxos::Sistema` → `spec/services/ramon/fluxos/sistema_spec.rb`). **`app/models/lead.rb`, `app/services/ramon/advbox_event_processor.rb` e `app/finders/conversation_finder.rb` estão NO LIMITE de 175 linhas de classe: nenhuma linha nova neles** (este plano não toca nenhum dos três).
- **CI FOSS apaga `enterprise/`:** todo código que toque `Captain::*` fica atrás de `ChatwootApp.enterprise?` e o spec dele com `if: ChatwootApp.enterprise?`. A B3 não toca Captain — se precisar, pare.
- **Mensagem ao cliente SEMPRE rascunho.** Os textos ao cliente que aparecem nos desenhos do sistema são **cópia literal** do que o código já escreve hoje; não são textos novos e nunca são enviados nem executados (é só desenho). "Rodar fluxo…" só roda fluxos do usuário, que já são rascunho por construção (B1/B2b). Nenhuma task cria texto novo ao cliente.
- **Só admin:** a API de fluxos inteira passa pelo `check_authorization` (`RamonFluxoPolicy#gerenciar?` = `administrator?`), inclusive `index` e `rodar` — por isso "Rodar fluxo…" só aparece para admin (`useAdmin`/`isAdmin`). Fluxo do sistema não aceita `update`/`destroy`/`publicar`/`rodar`/`ensaio` (403).
- **i18n:** chaves novas só dentro de `CAPTAIN_RAMON.FLUXOS` em `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json`, inseridas na **mesma posição** nos dois arquivos (a trava `specs/i18n.spec.js` compara a lista de chaves em ordem e compila tudo no vue-i18n de **produção**). Strings sem `@`, `|`, `{`, `}` crus (só `{nome}`); sem apóstrofo. Editar os JSON à mão (Edit), nunca regravar o arquivo inteiro por script.
- **Front:** Tailwind only (sem CSS próprio/scoped/inline, exceto o `:style` de largura que já existe); kit `ramon/helpers/ui.js` (`ABA`, `ABA_ATIVA`, `ABA_INATIVA`, `AVISO`, `CHIP`, `TOM`, `FUNDO_JANELA`, `JANELA`, `TITULO_JANELA`, `LINHA`); evento custom em camelCase (`fechar`); toda `<ul>/<ol>` nova com `list-none` (a B3 não cria lista); sem texto cru no template; **não usar `watchDebounced` do vueuse**. Arquivo do upstream (`MoreActions.vue`, `Sidebar.vue`, `automation.routes.js`) só com mudança mínima e comentário `FORK(ramon)`. `LeadPanelBody.vue` já tem 1529 linhas: entra só o item do menu e o modal (o resto mora no componente novo).
- **Visual:** hub minimalista branco (claro) / preto (escuro), botões e etapas coloridos, fundos coloridos **translúcidos** (`TOM.*` do kit). Aba Do sistema: aviso `TOM.blue`, cabeçalho de grupo em cinza maiúsculo pequeno, selo "roda no código" `TOM.blue`, selo de alcance `TOM.amber` com ícone de alerta, sem chave liga/desliga.
- **Testes locais:** não há Ruby nem Postgres local — specs Ruby são escritos e conferidos à mão (rastrear cada linha) e quem valida é o CI. Ao escrever spec que cria execução por helper `ctx` (padrão de `spec/services/ramon/fluxos/passos_spec.rb`), chame o `ctx` **uma vez por exemplo**: o índice único parcial `(fluxo_id, alvo_type, alvo_id) WHERE status IN ('rodando','esperando')` barra 2 execuções vivas no mesmo fluxo+alvo. Front:
  - `node_modules` é **junção** para `ramon-hub-wt-fluxos-b2\node_modules` (nunca `rm -rf node_modules`). Use o config local **já criado e fora do git** `vitest.local.config.ts` (raiz do worktree; não commitar):
    `TZ=UTC npx vitest run <arquivos ou pastas> --config vitest.local.config.ts`
    Baseline na base: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs` = 11 arquivos, 86 testes; `…/ramon/components/lead/specs/LeadPanelBody.spec.js` = 87 testes.
  - ESLint: `./node_modules/.bin/eslint <arquivos>` (erro `Delete ␍` = CRLF do checkout Windows, ignorar; warnings `@intlify/vue-i18n/no-dynamic-keys` já existem e são aceitos).
- **Commits:** Conventional Commits em pt-BR, sem citar Claude no assunto; corpo termina com:
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv`
  Commitar só os caminhos da task (`git add <arquivos>`), nunca `git add -A`.

## Review Focus

1. **Duas abas (ou duas pessoas) abrindo a lista ao mesmo tempo logo depois do deploy** — os 29 fluxos do sistema aparecem uma vez só, e os 4 números (e o "de N") continuam contando só os Meus fluxos. Teste: Task 3 ("cria… e não duplica", "nada mudou: não trava a conta") e Task 4 ("os 4 números contam só os meus").
2. **Alguém liga ou publica um fluxo do sistema** (console, API antiga, B4 distraída), ou um desenho do sistema com gatilho "Rodar na mão" aparece para rodar — nada roda: nem evento, nem relógio, nem "Rodar"/"Rodar fluxo…", nem ensaio. Teste: Task 4 (Disparo, Relógio e API) e Task 7 ("lista só os manuais publicados e ligados" exclui `origem: sistema`).
3. **Agente (não admin) no painel do lead/conversa** — não vê "Rodar fluxo…" (a API devolveria 401). Teste: Task 7 (LeadPanelBody "só para admin").
4. **Virada do dia** — um lead ganho às 23:30 de ontem em São Paulo (02:30 UTC de hoje) não entra no "Hoje" de hoje; e toda fonte de "Hoje" responde número (coluna errada = erro no CI, não na tela). Teste: Task 3 ("o dia é o de São Paulo", "toda fonte de Hoje…").
5. **Link salvo e caminho de volta** — quem tem `/settings/automation/list` nos favoritos cai em Automações; o "Voltar" de um desenho do sistema volta para a aba Do sistema; o toast do "Rodar fluxo…" leva à execução. Teste: Task 8 (rotas), Task 5 (`?aba=sistema`), Task 7 (link do toast).

---

## Como os desenhos do sistema são guardados (decisão)

**Linhas `ramon_fluxos` `origem: 'sistema'` por conta, sincronizadas a partir dos JSON em `db/seeds/ramon/fluxos/sistema/` quando a lista abre.** Por quê:

- A B2 já construiu tudo em volta de linhas: o `Editor.vue` abre por `GET ramon_fluxos/:id` e já é só-leitura para `origem === 'sistema'` (`Editor.vue:113` `somenteLeitura`; `useFluxoEditor.js:27` nunca fica "sujo"; Testar/Publicar com `v-if="!somenteLeitura"`; Excluir escondido `Editor.vue:405`); a API já recusa `update/destroy/publicar/rodar` (`ramon_fluxos_controller.rb:5`, `:79-81`); `Fluxo.executaveis` já exclui a origem (`app/models/fluxo.rb:23`, usado por `Disparo.call` `disparo.rb:10` e `Relogio` `relogio.rb:13`); a `Lista.vue:39` já filtrava `origem !== 'sistema'` esperando por eles. E a B4 precisa de `sistema_chave` numa linha para casar o fluxo em sombra com o código.
- **Não** como os modelos (`modelos.js`, "modelos = conteúdo semente em JS" da B2): modelos só o front consome; aqui quem lê é o Ruby (API, "Hoje", trava no Grafo) — a própria B2 registrou "os fluxos do sistema (B3) continuam em `db/seeds`" (divergência #9 do plano da B2). O app já lê `db/seeds/ramon` em produção (`Leads::SeedDefaultConfigService::THESES_SEED_PATH`, `Ramon::InteligenciaSeed::DIR`) e o `.dockerignore` não exclui `db/`.
- **Não** por rake no deploy (passo manual do Eduardo; conta nova ficaria sem) e **não** como entradas "virtuais" na API (id falso, rota/endpoint novos no editor). A sincronização custa 1 SELECT quando nada mudou e se conserta sozinha quando o JSON muda.
- `grupo`, `alcance` e o rótulo do gatilho **não** viram coluna: o controller junta `Sistema.extras(account, chave)` (JSON já em memória) no `index` e no `show`.

**Motor nunca executa — verificado e travado:** `Disparo.call` e `Relogio` passam por `executaveis`; `Disparo.manual` e `Disparo.ensaiar` **não** checavam a origem (só a API barrava `rodar`, e `ensaio` nem isso). A Task 4 põe 1 guarda em `Disparo#iniciar` (todos os caminhos passam por ele) e `ensaio` no `bloquear_sistema`, com spec.

**Convenção dos desenhos:** 1ª linha da `descricao` = "No código: …" (onde vive; aparece na lista); o resto = "O desenho não consegue mostrar: …" (aparece no painel "Como roda hoje"). Quando o gatilho real não existe nos fluxos (cron de hora em hora/a cada minuto, webhook do ZapSign do Painel, envio pelo Painel, aviso de chegada, nota @claude, gravação de reunião, gravação do lead), o desenho usa **`manual` ("Rodar na mão") com `config.rotulo` dizendo o evento real** — a lista mostra esse rótulo no lugar do nome do gatilho; crons diários usam `relogio` com a hora real e o rótulo "1 vez por conta/todos os clientes". Ações sem passo (Drive, Notion, e-mail, carimbos de coluna, criar lead) usam o tipo mais próximo (`nota_privada`, `preencher_campo`, `webhook`) com rótulo claro. Único erro de validação aceito: `mover_etapa` sem `etapa_id` (a etapa é do funil de cada conta — a B4 escolhe ao migrar).

## As 29 automações (arquivo:linha na base 9cdd5c6) e o "Hoje"

| Grupo | Chave | Nome | Onde vive | Gatilho do desenho | "Hoje" (fonte barata) |
|---|---|---|---|---|---|
| Leads e conversas | `cadencia` | Cadência de retomada | `config/schedule.yml:87-90` → `Ramon::DailyFollowUpJob` → `Ramon::FollowUpDraftService` (`:27`, teto `:6`, `draft_for` `:75`) | `lead_parado` 11:00 | notas "RASCUNHO … — retomada" de hoje |
| | `sla_primeira_resposta` | SLA da 1ª resposta | `ramon_lead_listener.rb:21,72` → `Ramon::FirstResponseSlaJob` (`:12`) | `conversa_criada` | `Ramon::Cadencia.sla_conversations(conta, hoje)` |
| | `lembretes_reuniao` | Lembretes de reunião | `Ramon::ReuniaoAgendamento` (`:17`, `#call` `:73`, `notify` `:52`) + `Ramon::MeetingReminderJob` (`:19`) | `reuniao_marcada` | atividades `meeting_scheduled/rescheduled` |
| | `criar_lead_da_conversa` | Criar lead da conversa | `RamonLeadListener#conversation_created` | `conversa_criada` | — |
| | `origem_do_lead` | Origem do lead | `RamonLeadListener#message_created` (`apply_meta_referral`, `derive_channel_from_first_contact`) | `mensagem_recebida` | — |
| | `coach_objecao` | Coach de objeção | `RamonLeadListener:39` → `Ramon::CoachObjecaoJob` → `Ramon::CoachObjecaoService` | `mensagem_recebida` | — |
| | `etiquetas_etapa_tese` | Etiquetas de etapa e tese | `RamonLeadListener` → `Ramon::StageLabelSync`, `Ramon::TeseLabelSync` | `lead_mudou_etapa` | — |
| | `historico_do_lead` | Histórico do lead | `lead.rb:49-50`, `lead_note.rb:10`, `lead_task.rb:17` | `lead_mudou_etapa` | — |
| | `sdr_automatico` | SDR automático | `lead_comercial.rb:11,14` (`assign_sdr`, `assign_conversation_to_sdr`) | `lead_criado` | — |
| | `chegada_cliente` | Chegada de cliente | `ramon_chegadas_controller.rb:17` → `Ramon::ChegadaEscalarJob` | `manual` (rótulo: recepção avisa) | chegadas escaladas hoje (`escalado_em`) |
| | `agente_hub` | Agente do hub (@claude) | `RamonAgenteListener` → `Ramon::AgenteNotifyJob` | `manual` (rótulo: nota @claude) | — |
| | `ata_reuniao` | Ata da reunião | `ramon_reunioes_controller.rb:35,56` → `Ramon::ReuniaoAtaJob` | `manual` (rótulo: reunião gravada) | — |
| Contrato e documentos | `lead_ganho` | Lead ganho | `lead.rb:51-54` (dossiê, ADVBOX, NPS, Drive) | `lead_ganho` | `won_at` hoje |
| | `eventos_advbox` | Eventos do ADVBOX | `Ramon::AdvboxEventJob` → `Ramon::AdvboxEventProcessor` (`:40`, `RULES` `:15-31`) | `evento_advbox` + `escolha` por `regra` | `AdvboxEvent` `processed` hoje |
| | `sugestao_documento` | Sugestão de documento | `RamonLeadListener:36` → `Ramon::DocMatchJob` → `Ramon::DocMatchService` | `mensagem_recebida` | — |
| | `docs_completos` | Documentos completos | `lead_comercial.rb:12,80-84` (`stamp_docs_completos`) | `manual` (rótulo: equipe confirma documento) | `docs_completos_em` hoje |
| | `contrato_zapsign` | Contrato no ZapSign | `zapsign_webhooks_controller.rb:16`, `zapsign_contract_service.rb:74` → `Ramon::ZapsignLeadStatusJob` | `contrato_assinado` | — |
| | `contrato_limpo` | Contrato limpo | `config/schedule.yml:139-143` → `Ramon::ContratoLimpoJob` | `manual` (rótulo: toda hora) | `contrato_limpo_em` hoje |
| | `contrato_limpo_cancelado` | Contrato limpo cancelado | `lead_comercial.rb:13` (`cancelar_contrato_limpo`) | `lead_mudou_etapa` | — |
| Painel do Cliente | `assinatura_painel` | Assinatura pelo Painel do Cliente | `zapsign_webhooks_controller.rb:13` → `Ramon::ZapsignStatusJob` | `manual` (rótulo: ZapSign do Painel) | — |
| | `documento_painel` | Documento enviado pelo Painel | `cliente/painel_controller.rb:85` → `Ramon::PortalEnvioJob` (`TASKS_ID_*` `:12-14`) | `manual` (rótulo: cliente envia) | — |
| | `espelho_painel` | Espelho do Painel do Cliente | `config/schedule.yml:115-118` → `Ramon::PortalSyncJob` | `relogio` 00:30 | — |
| | `avisos_painel` | Avisos do Painel do Cliente — **selo "fala com o cliente"** | `config/schedule.yml:127-130` → `Ramon::PortalAvisosJob` (só com `PORTAL_AVISOS=on`) | `relogio` 08:00 | — |
| Rotinas e relatórios | `resumo_do_dia` | Resumo do dia | `config/schedule.yml:108-111` → `Ramon::DailyDigestJob` | `relogio` 08:00 | — |
| | `copiloto_noturno` | Copiloto noturno | `config/schedule.yml:95-98` → `Ramon::NightCopilotJob` → `Ramon::NightCopilotService` | `lead_parado` 05:00 | `CopilotSuggestion` criadas hoje |
| | `fechamento_extrato` | Fechamento do extrato | `config/schedule.yml:146-149` → `Ramon::ExtratoFechamentoJob` | `relogio` 00:20 | — |
| | `retrato_funil` | Retrato do funil | `config/schedule.yml:80-83` → `Ramon::DailyFunnelSnapshotJob` | `relogio` 00:05 | — |
| Instagram | `publicar_pecas` | Publicar peças no Instagram — **selo "publica"** | `config/schedule.yml:121-124` → `Ramon::PublicarPecasJob` | `manual` (rótulo: a cada minuto) | peças com `publicacao_iniciada_em` hoje |
| | `acervo_pecas` | Acervo das peças (Drive e Notion) | `publicar_pecas_job.rb:41` → `Ramon::ConteudoDriveJob`; `peca.rb:24` → `Ramon::NotionEspelhoJob` | `manual` (rótulo: peça publicada) | — |

**Deixados de fora por serem encanamento** (não são automação de negócio): `Ramon::FluxoRelogioJob` (o próprio motor), `Ramon::IgTokenRefreshJob`, `Ramon::StageMergeJob` e `Ramon::LeadBulkActionJob` (movimentação em lote atrás de botão), `Ramon::ColheitaExtractionJob` (sob demanda / fim de transcrição), `Ramon::NtfyPushJob` (transporte), `LeadTask#touch_lead`, transmissões da `Chegada`, crons nativos do Chatwoot.

## Mapa de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `db/seeds/ramon/fluxos/sistema/*.json` (29 novos) | desenho + nome + grupo + alcance? + onde vive/lacunas (+ `limite_dia` 15 na cadência e no copiloto) |
| `app/services/ramon/fluxos/sistema.rb` (novo) | `desenhos`, `sincronizar(account)`, `hoje(account, chave)`, `extras(account, chave)` |
| `app/services/ramon/fluxos/disparo.rb` | 1 guarda em `#iniciar`: origem `sistema` nunca roda |
| `app/controllers/api/v1/accounts/ramon_fluxos_controller.rb` | `index` sincroniza; `index`/`show` com extras do sistema; resumo só dos meus; `ensaio` no `bloquear_sistema` |
| `app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js` | `GRUPOS_SISTEMA`, `ALCANCES`; `CAMPOS` + `regra`; comentário da B3 corrigido |
| `…/captain/automacoes/Lista.vue` | abas (`?aba=sistema`), grupos, selo de alcance, rótulo do gatilho |
| `…/captain/automacoes/Editor.vue` | painel "Como roda hoje", selo de alcance, sem Versões, Voltar → aba Do sistema |
| `…/captain/automacoes/RodarFluxo.vue` (novo) | modal "Rodar fluxo…" (lista manuais publicados/ligados, roda, toast com link, vazio → Automações) |
| `app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadPanelBody.vue` | item "Rodar fluxo…" no ⋯ (admin) + modal com `{ lead_id }` |
| `app/javascript/dashboard/components/widgets/conversation/MoreActions.vue` | item "Rodar fluxo…" no ⋯ do cabeçalho (admin) + modal com `{ conversation_id }` (FORK) |
| `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json` | `ABA_SISTEMA`, `SISTEMA.{EXPLICA,SEM_CONTADOR,GRUPOS.*,ALCANCE.*}`, `RODAR.*`, `SELO.NO_CODIGO`, `EDITOR.COMO_RODA`, `CAMPOS.regra` |
| `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | sai o item "Automação" de Configurações (FORK) |
| `app/javascript/dashboard/routes/dashboard/settings/automation/automation.routes.js` | rota antiga → `captain_automacoes_index` (FORK) |
| `…/captain/automacoes/Automacoes.story.vue` | variantes `DoSistema`, `SistemaLembretes`, `SistemaAvisos` |
| `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` | §14 Notas da B3 |
| specs | Ruby: `spec/services/ramon/fluxos/sistema_spec.rb` (novo), `spec/services/ramon/fluxos/{disparo,relogio}_spec.rb`, `spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb`; front: `…/automacoes/specs/{sistema,RodarFluxo}.spec.js` (novos), `…/automacoes/specs/{Lista,i18n}.spec.js`, `…/ramon/components/lead/specs/LeadPanelBody.spec.js`, `…/settings/automation/specs/automation.routes.spec.js` (novo) |

---

### Task 1: Desenhos do sistema I — as 6 principais + grupos no catálogo + trava de desenho

**Files:**
- Create: `db/seeds/ramon/fluxos/sistema/{cadencia,sla_primeira_resposta,lembretes_reuniao,eventos_advbox,lead_ganho,resumo_do_dia}.json`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js` (2 constantes novas antes de `PAPEIS`)
- Test: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/sistema.spec.js` (novo)

**Interfaces:**
- Consumes: `validar(desenho)` de `…/automacoes/validar.js` (espelho do `Ramon::Fluxos::Grafo#erros`; devolve `[{no, codigo, params}]`).
- Produces (usado pelas Tasks 2, 3, 5, 9 e pela B4):
  - formato do arquivo: `{ "nome": String, "grupo": um de GRUPOS_SISTEMA, "alcance"?: um de ALCANCES, "descricao": String /* 1ª linha "No código: …" */, "limite_dia"?: Integer, "desenho": { "nos": [{id, tipo, config, posicao}], "setas": [{de, saida, para}] } }`; todo passo (menos o gatilho) tem `config.rotulo`; o gatilho pode ter `config.rotulo` (= evento real). Único erro de validação aceito: `FALTA etapa_id`.
  - `fluxo.js`: `export const GRUPOS_SISTEMA = ['leads_conversas', 'contrato_documentos', 'painel_cliente', 'rotinas_relatorios', 'instagram']` (ordem da tela) e `export const ALCANCES = ['fala_com_cliente', 'publica']`.

- [ ] **Step 1: Write the failing test** — `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/sistema.spec.js` (versão da Task 1; a Task 2 troca o 1º teste pelo das 29):

```js
// Trava dos desenhos do sistema (db/seeds/ramon/fluxos/sistema/*.json, spec §8 +
// decisão do Eduardo 06/10: as 29 automações do código): o quadro abre cada um e a
// validação (espelho do Grafo) só deixa passar a etapa em aberto — a etapa é do
// funil de cada conta e a B4 escolhe ao migrar.
import { ALCANCES, GRUPOS_SISTEMA } from '../fluxo';
import { validar } from '../validar';

const ARQUIVOS = import.meta.glob(
  '../../../../../../../../db/seeds/ramon/fluxos/sistema/*.json',
  { eager: true, import: 'default' }
);
const DESENHOS = Object.entries(ARQUIVOS).map(([caminho, d]) => [
  caminho.split('/').pop().replace('.json', ''),
  d,
]);

describe('fluxos do sistema', () => {
  it('tem os 6 da spec §8', () => {
    expect(DESENHOS.map(([chave]) => chave)).toEqual(
      expect.arrayContaining([
        'cadencia',
        'eventos_advbox',
        'lead_ganho',
        'lembretes_reuniao',
        'resumo_do_dia',
        'sla_primeira_resposta',
      ])
    );
  });

  it.each(DESENHOS)(
    '%s: nome, grupo, onde vive no código e desenho válido (menos a etapa)',
    (_chave, d) => {
      expect(d.nome).toBeTruthy();
      expect(GRUPOS_SISTEMA).toContain(d.grupo);
      expect([undefined, ...ALCANCES]).toContain(d.alcance);
      expect(d.descricao.split('\n')[0]).toMatch(/^No código: /);
      const erros = validar(d.desenho).filter(
        e => !(e.codigo === 'FALTA' && e.params.campo === 'etapa_id')
      );
      expect(erros).toEqual([]);
    }
  );

  it.each(DESENHOS)(
    '%s: todo passo diz no rótulo o que o código faz',
    (_chave, d) => {
      const semRotulo = d.desenho.nos
        .filter(n => n.tipo !== 'gatilho' && !n.config?.rotulo)
        .map(n => n.id);
      expect(semRotulo).toEqual([]);
    }
  );
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/sistema.spec.js --config vitest.local.config.ts`
Expected: FAIL — import de `GRUPOS_SISTEMA`/`ALCANCES` indefinido e a pasta ainda não existe (`import.meta.glob` vazio).

- [ ] **Step 3: Implementation**

(a) `fluxo.js` — logo antes de `export const PAPEIS = ['sdr', 'closer']; // Ramon::Papeis::COLUNA`, inserir:

```js
// Fluxos do sistema (B3, db/seeds/ramon/fluxos/sistema/*.json): grupos da aba "Do sistema"
// na ordem da tela, e o selo de quem sai para fora sem uma pessoa no meio.
export const GRUPOS_SISTEMA = [
  'leads_conversas',
  'contrato_documentos',
  'painel_cliente',
  'rotinas_relatorios',
  'instagram',
];
export const ALCANCES = ['fala_com_cliente', 'publica'];
```

(b) Os 6 JSON (UTF-8, exatamente como abaixo; textos ao cliente = cópia do código).

`db/seeds/ramon/fluxos/sistema/cadencia.json`:

```json
{
  "nome": "Cadência de retomada",
  "grupo": "leads_conversas",
  "descricao": "No código: Ramon::DailyFollowUpJob (todo dia às 11:00) → Ramon::FollowUpDraftService; também roda na hora pelo botão Preparar retomada do painel do lead (Ramon::FollowUpDraftJob).\n\nO desenho não consegue mostrar:\n• o Se só confere se há conversa; as outras regras (nenhuma tarefa de retomada aberta e a última retomada há mais de 5 dias) estão só no rótulo;\n• o código roda todo dia para quem segue parado (o gatilho Lead parado dos fluxos dispara 1 vez por parada);\n• o teto é de 15 retomadas por dia por conta, na ordem do radar de parados;\n• o rascunho vai para as notas do lead (não para a conversa) e, se a IA falhar, entra um texto fixo de retomada;\n• o contador de tentativas fica em custom_attributes.follow_up (o passo Preencher campo grava em campos);\n• o aviso na conversa é um balão de evento (não nota privada) e o push é um só por conta, com o total do lote.",
  "limite_dia": 15,
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"lead_parado","hora":"11:00"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"se","config":{"rotulo":"Pode retomar? (tem conversa, nenhuma retomada aberta, última há mais de 5 dias)","juncao":"e","condicoes":[{"campo":"caixa","operador":"existe","valor":""}]},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"rascunho_ia","config":{"rotulo":"Rascunho de retomada nº N (nas notas do lead)","instrucao":"Mensagem de retomada de WhatsApp para um lead que parou de responder: 2 a 4 frases, tom de médico de confiança, sem pressão. O ângulo muda com a tentativa — 1ª: lembrete leve de que estamos à disposição; 2ª: uma informação nova e útil sobre a tese; 3ª em diante: pergunta direta sobre o interesse, deixando a porta aberta. Nunca prometa resultado do caso nem prazo do INSS. Não invente fatos que não estejam na conversa."},"posicao":{"x":0,"y":300}},
      {"id":"n4","tipo":"criar_tarefa","config":{"rotulo":"Tarefa de retomada para hoje","titulo":"Retomada nº N","tipo":"follow_up","prazo_dias":0},"posicao":{"x":0,"y":460}},
      {"id":"n5","tipo":"preencher_campo","config":{"rotulo":"Conta a tentativa (custom_attributes.follow_up)","chave":"follow_up","valor":"tentativa nº N, hoje"},"posicao":{"x":0,"y":600}},
      {"id":"n6","tipo":"nota_privada","config":{"rotulo":"Balão na conversa: Cadência do hub","texto":"⟳ Cadência do hub preparou o rascunho de retomada nº N — revise e envie pelo painel."},"posicao":{"x":0,"y":740}},
      {"id":"n7","tipo":"avisar_push","config":{"rotulo":"Push: retomadas prontas (1 por conta)","titulo":"Retomadas prontas pra revisar","texto":"N rascunho(s) de retomada esperando revisão no hub"},"posicao":{"x":0,"y":880}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"sim","para":"n3"},
      {"de":"n3","saida":"s","para":"n4"},
      {"de":"n4","saida":"s","para":"n5"},
      {"de":"n5","saida":"s","para":"n6"},
      {"de":"n6","saida":"s","para":"n7"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/sla_primeira_resposta.json`:

```json
{
  "nome": "SLA da 1ª resposta",
  "grupo": "leads_conversas",
  "descricao": "No código: RamonLeadListener#conversation_created (caixas com Criar lead ligado) agenda Ramon::FirstResponseSlaJob para N minutos depois; o próprio job agenda a escalada de 60 minutos.\n\nO desenho não consegue mostrar:\n• o tempo vem do SLA de cada caixa (padrão de 5 min no env RAMON_SLA_FIRST_RESPONSE_MINUTES) e a escalada conta 60 min desde a criação da conversa;\n• \"ainda sem 1ª resposta\" não tem campo — o Se só confere se a conversa segue aberta; o código também desiste se a conversa não tem lead;\n• o horário do código é das 7h às 21h, todos os dias — diferente do horário comercial dos fluxos (seg–sex, 8h–18h);\n• a escalada é agendada mesmo fora do horário; só o aviso respeita o horário;\n• o sino vai para o SDR do lead (sem SDR, para os gestores) e, na escalada, para os gestores — o passo Sino não escolhe por papel.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"conversa_criada"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"esperar","config":{"rotulo":"SLA da caixa (padrão 5 min)","quantidade":5,"unidade":"minutos"},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"se","config":{"rotulo":"Ainda sem 1ª resposta e aberta?","juncao":"e","condicoes":[{"campo":"status","operador":"igual","valor":"open"}]},"posicao":{"x":0,"y":280}},
      {"id":"n4","tipo":"se","config":{"rotulo":"Entre 7h e 21h?","juncao":"e","condicoes":[{"campo":"texto","operador":"em_horario_comercial","valor":""}]},"posicao":{"x":-130,"y":440}},
      {"id":"n5","tipo":"avisar_sino","config":{"rotulo":"Sino do SDR (sem SDR: gestores)","texto":"Lead aguardando 1ª resposta há 5 min: {nome_completo}"},"posicao":{"x":-260,"y":600}},
      {"id":"n6","tipo":"avisar_push","config":{"rotulo":"Push: lead aguardando","titulo":"Lead aguardando 1a resposta","texto":"Lead aguardando 1ª resposta há 5min: {nome_completo}"},"posicao":{"x":-260,"y":740}},
      {"id":"n7","tipo":"esperar","config":{"rotulo":"Até 60 min da criação da conversa","quantidade":55,"unidade":"minutos"},"posicao":{"x":0,"y":880}},
      {"id":"n8","tipo":"se","config":{"rotulo":"Ainda sem 1ª resposta e aberta?","juncao":"e","condicoes":[{"campo":"status","operador":"igual","valor":"open"}]},"posicao":{"x":0,"y":1020}},
      {"id":"n9","tipo":"se","config":{"rotulo":"Entre 7h e 21h?","juncao":"e","condicoes":[{"campo":"texto","operador":"em_horario_comercial","valor":""}]},"posicao":{"x":-130,"y":1180}},
      {"id":"n10","tipo":"avisar_sino","config":{"rotulo":"Escalada: sino dos gestores","texto":"Lead aguardando 1ª resposta há 60 min: {nome_completo}"},"posicao":{"x":-260,"y":1340}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"s","para":"n3"},
      {"de":"n3","saida":"sim","para":"n4"},
      {"de":"n4","saida":"sim","para":"n5"},
      {"de":"n5","saida":"s","para":"n6"},
      {"de":"n6","saida":"s","para":"n7"},
      {"de":"n4","saida":"nao","para":"n7"},
      {"de":"n7","saida":"s","para":"n8"},
      {"de":"n8","saida":"sim","para":"n9"},
      {"de":"n9","saida":"sim","para":"n10"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/lembretes_reuniao.json` (os 5 lembretes = **um** ciclo com rótulo — decisão do Eduardo):

```json
{
  "nome": "Lembretes de reunião",
  "grupo": "leads_conversas",
  "descricao": "No código: Ramon::ReuniaoAgendamento.call (reunião marcada pelo painel do lead ou pelo Cal.com) e Ramon::MeetingReminderJob (os lembretes).\n\nO desenho não consegue mostrar:\n• os 5 lembretes (24h, 8h, 1h, 30 min e 5 min antes) contam para trás a partir da hora da reunião — a espera dos fluxos só conta para a frente; aqui eles aparecem como um ciclo só, e saem apenas os que ainda estão no futuro;\n• cada lembrete confere se a tarefa da reunião segue aberta naquele horário (cancelou ou remarcou → o lembrete antigo é descartado) e não repete o mesmo lembrete;\n• a tarefa da reunião vence na hora marcada; a etapa só anda para a frente (quem já está adiante fica onde está);\n• o Closer só é escolhido se o lead ainda não tem;\n• o rascunho de confirmação vai para as notas do lead (não para a conversa) e o sino de reunião marcada vai para toda a conta;\n• remarcar refaz atividade, rascunho, lembretes e sino (sem mexer em tarefa nova, etapa ou Closer); cancelar registra a atividade, apaga a tarefa e avisa no sino e no push.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"reuniao_marcada"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"registrar_atividade","config":{"rotulo":"Atividade: reunião agendada","texto":"Reunião agendada para {quando}"},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"criar_tarefa","config":{"rotulo":"Tarefa da reunião (vence na hora marcada)","titulo":"Reunião","tipo":"meeting","prazo_dias":0},"posicao":{"x":0,"y":280}},
      {"id":"n4","tipo":"mover_etapa","config":{"rotulo":"Mover para Reunião agendada (só para a frente)","etapa_id":null},"posicao":{"x":0,"y":420}},
      {"id":"n5","tipo":"trocar_responsavel","config":{"rotulo":"Closer automático (se o lead ainda não tem)","papel":"closer"},"posicao":{"x":0,"y":560}},
      {"id":"n6","tipo":"rascunho_texto","config":{"rotulo":"Rascunho de confirmação (nas notas do lead)","texto":"Oi {nome}! Nossa conversa está confirmada pra {quando}. Vou te esperar, tá? Se não puder comparecer, me avise com antecedência que a gente remarca sem problema."},"posicao":{"x":0,"y":700}},
      {"id":"n7","tipo":"avisar_sino","config":{"rotulo":"Sino para toda a conta","texto":"Reunião marcada: {nome_completo} — {quando}"},"posicao":{"x":0,"y":860}},
      {"id":"n8","tipo":"avisar_push","config":{"rotulo":"Push: reunião marcada","titulo":"Reuniao marcada: {nome_completo}","texto":"{quando}"},"posicao":{"x":0,"y":1000}},
      {"id":"n9","tipo":"esperar","config":{"rotulo":"Até 24h · 8h · 1h · 30 min · 5 min antes da reunião","quantidade":1,"unidade":"dias"},"posicao":{"x":0,"y":1140}},
      {"id":"n10","tipo":"avisar_sino","config":{"rotulo":"Lembrete ao Closer e ao SDR (se a reunião segue marcada)","texto":"Reunião de {nome_completo}: {quando}"},"posicao":{"x":0,"y":1280}},
      {"id":"n11","tipo":"avisar_push","config":{"rotulo":"Push do lembrete","titulo":"Reunião {nome_completo} em 24h antes","texto":"{quando} — hora de mandar a mensagem de confirmação pro cliente"},"posicao":{"x":0,"y":1420}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"s","para":"n3"},
      {"de":"n3","saida":"s","para":"n4"},
      {"de":"n4","saida":"s","para":"n5"},
      {"de":"n5","saida":"s","para":"n6"},
      {"de":"n6","saida":"s","para":"n7"},
      {"de":"n7","saida":"s","para":"n8"},
      {"de":"n8","saida":"s","para":"n9"},
      {"de":"n9","saida":"s","para":"n10"},
      {"de":"n10","saida":"s","para":"n11"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/eventos_advbox.json` (o `escolha` por `regra` abre 1 coluna por handler do `AdvboxEventProcessor::RULES`, na mesma ordem; "outro" sem seta — o gatilho só nasce com regra):

```json
{
  "nome": "Eventos do ADVBOX",
  "grupo": "contrato_documentos",
  "descricao": "No código: Flowter → webhook do hub → Ramon::AdvboxEventJob → Ramon::AdvboxEventProcessor (cada regra é um método com o nome da chave).\n\nO desenho não consegue mostrar:\n• a regra sai do nome da etapa/tarefa no payload do Flowter, e o lead é achado pelo CPF ou pelo telefone (lead aberto; senão o mais recente do funil) — sem regra ou sem lead o evento fica guardado e nada roda;\n• cada atividade tem um tipo próprio (advbox_contrato_fechado, advbox_indeferido, …) e leva o nome da etapa do ADVBOX;\n• os rascunhos vão para as notas do lead (não para a conversa); a pesquisa NPS de êxito e de concessão sai uma vez só por lead;\n• os pushes só saem com o ntfy configurado (NTFY_TOPIC);\n• em Contrato fechado o lead vai para a etapa de ganho da conta (se ainda não estava); em Arquivado todas as tarefas abertas do lead são concluídas — não há passo para isso.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"evento_advbox"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"escolha","config":{"rotulo":"Qual regra do ADVBOX?","campo":"regra","casos":[{"chave":"c1","rotulo":"Contrato fechado","valores":["contrato_fechado"]},{"chave":"c2","rotulo":"Requerimento protocolado","valores":["requerimento_protocolado"]},{"chave":"c3","rotulo":"INSS negou","valores":["indeferimento"]},{"chave":"c4","rotulo":"Decisão","valores":["decisao"]},{"chave":"c5","rotulo":"Exigência","valores":["exigencia"]},{"chave":"c6","rotulo":"Benefício futuro","valores":["reativacao_futura"]},{"chave":"c7","rotulo":"Êxito","valores":["exito"]},{"chave":"c8","rotulo":"Marco","valores":["marco"]},{"chave":"c9","rotulo":"Concessão","valores":["concessao"]},{"chave":"c10","rotulo":"Arquivado","valores":["arquivado"]}]},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"mover_etapa","config":{"rotulo":"Marca o lead como ganho (etapa de ganho da conta)","etapa_id":null},"posicao":{"x":-1350,"y":320}},
      {"id":"n4","tipo":"registrar_atividade","config":{"rotulo":"Atividade: contrato fechado","texto":"ADVBOX: {texto}"},"posicao":{"x":-1350,"y":470}},
      {"id":"n5","tipo":"avisar_push","config":{"rotulo":"Push: contrato fechado","titulo":"Contrato fechado no ADVBOX","texto":"{nome_completo}: lead marcado como ganho no hub"},"posicao":{"x":-1350,"y":620}},
      {"id":"n6","tipo":"registrar_atividade","config":{"rotulo":"Atividade: requerimento protocolado","texto":"ADVBOX: {texto} (com a data de hoje)"},"posicao":{"x":-1050,"y":320}},
      {"id":"n7","tipo":"criar_tarefa","config":{"rotulo":"Follow-up de 45 dias","titulo":"Verificar decisão/exigência do INSS (protocolo ADVBOX)","tipo":"follow_up","prazo_dias":45},"posicao":{"x":-1050,"y":470}},
      {"id":"n8","tipo":"avisar_push","config":{"rotulo":"Push: requerimento protocolado","titulo":"Requerimento protocolado no INSS","texto":"{nome_completo}: follow-up de 45 dias criado"},"posicao":{"x":-1050,"y":620}},
      {"id":"n9","tipo":"registrar_atividade","config":{"rotulo":"Atividade: INSS negou","texto":"ADVBOX: {texto}"},"posicao":{"x":-750,"y":320}},
      {"id":"n10","tipo":"criar_tarefa","config":{"rotulo":"Avaliar judicialização em 1 dia","titulo":"Avaliar judicialização — INSS negou (ADVBOX)","tipo":"follow_up","prazo_dias":1},"posicao":{"x":-750,"y":470}},
      {"id":"n11","tipo":"rascunho_texto","config":{"rotulo":"Rascunho: INSS negou (nas notas do lead)","texto":"Oi {nome}, tudo bem? Saiu a decisão do INSS sobre o seu pedido e, infelizmente, foi negativa. Isso não é o fim: muitos casos como o seu são revertidos na Justiça. Posso te explicar os próximos passos?"},"posicao":{"x":-750,"y":620}},
      {"id":"n12","tipo":"avisar_push","config":{"rotulo":"Push: INSS negou","titulo":"INSS NEGOU - avaliar judicializacao","texto":"{nome_completo}: tarefa na Esteira + rascunho de mensagem no caso"},"posicao":{"x":-750,"y":770}},
      {"id":"n13","tipo":"registrar_atividade","config":{"rotulo":"Atividade: decisão proferida","texto":"ADVBOX: {texto}"},"posicao":{"x":-450,"y":320}},
      {"id":"n14","tipo":"criar_tarefa","config":{"rotulo":"Analisar a decisão em 2 dias","titulo":"Analisar decisão registrada no ADVBOX","tipo":"follow_up","prazo_dias":2},"posicao":{"x":-450,"y":470}},
      {"id":"n15","tipo":"avisar_push","config":{"rotulo":"Push: decisão","titulo":"Decisao proferida (ADVBOX)","texto":"{nome_completo}: analisar e decidir comunicação"},"posicao":{"x":-450,"y":620}},
      {"id":"n16","tipo":"registrar_atividade","config":{"rotulo":"Atividade: carta de exigências","texto":"ADVBOX: {texto}"},"posicao":{"x":-150,"y":320}},
      {"id":"n17","tipo":"criar_tarefa","config":{"rotulo":"Cumprir a exigência em 2 dias","titulo":"Cumprir exigência do INSS — prazo curto (ADVBOX)","tipo":"follow_up","prazo_dias":2},"posicao":{"x":-150,"y":470}},
      {"id":"n18","tipo":"rascunho_texto","config":{"rotulo":"Rascunho: exigência do INSS (nas notas do lead)","texto":"Oi {nome}! O INSS pediu um documento a mais no seu processo. Pode me mandar por aqui quando conseguir? Te ajudo com o que precisar."},"posicao":{"x":-150,"y":620}},
      {"id":"n19","tipo":"avisar_push","config":{"rotulo":"Push: exigência","titulo":"Carta de exigencias do INSS","texto":"{nome_completo}: prazo curto — tarefa + rascunho criados"},"posicao":{"x":-150,"y":770}},
      {"id":"n20","tipo":"registrar_atividade","config":{"rotulo":"Atividade: benefício futuro","texto":"ADVBOX: {texto}"},"posicao":{"x":150,"y":320}},
      {"id":"n21","tipo":"criar_tarefa","config":{"rotulo":"Retomar contato em 180 dias","titulo":"Reativação: benefício futuro — retomar contato","tipo":"follow_up","prazo_dias":180},"posicao":{"x":150,"y":470}},
      {"id":"n22","tipo":"registrar_atividade","config":{"rotulo":"Atividade: êxito (pagamento)","texto":"ADVBOX: {texto}"},"posicao":{"x":450,"y":320}},
      {"id":"n23","tipo":"rascunho_texto","config":{"rotulo":"Rascunho: comunicado de êxito (nas notas do lead)","texto":"{nome}, ótima notícia! 🎉 Saiu o pagamento do seu processo. Foi uma alegria acompanhar seu caso até aqui. Se puder, sua avaliação no Google ajuda muito outras pessoas a nos encontrarem."},"posicao":{"x":450,"y":470}},
      {"id":"n24","tipo":"rascunho_texto","config":{"rotulo":"Rascunho: pesquisa NPS de êxito (1 vez só)","texto":"{nome}, de 0 a 10, que nota você dá pro nosso atendimento até aqui? Sua opinião ajuda a gente a melhorar de verdade. E se a experiência foi boa, sua avaliação no Google ajuda outras pessoas a nos encontrarem: [link de avaliação do Google]"},"posicao":{"x":450,"y":620}},
      {"id":"n25","tipo":"avisar_push","config":{"rotulo":"Push: êxito","titulo":"Exito: pagamento no ADVBOX","texto":"{nome_completo}: rascunho de comunicado pronto no caso"},"posicao":{"x":450,"y":770}},
      {"id":"n26","tipo":"registrar_atividade","config":{"rotulo":"Atividade: marco processual","texto":"ADVBOX: {texto}"},"posicao":{"x":750,"y":320}},
      {"id":"n27","tipo":"avisar_push","config":{"rotulo":"Push: marco processual","titulo":"Marco processual (ADVBOX)","texto":"{nome_completo}: {texto}"},"posicao":{"x":750,"y":470}},
      {"id":"n28","tipo":"registrar_atividade","config":{"rotulo":"Atividade: benefício concedido","texto":"ADVBOX: {texto}"},"posicao":{"x":1050,"y":320}},
      {"id":"n29","tipo":"rascunho_texto","config":{"rotulo":"Rascunho: benefício concedido (nas notas do lead)","texto":"{nome}, notícia boa! 🎉 O INSS CONCEDEU o seu benefício. Agora vamos conferir a implantação e os valores — te aviso de cada passo."},"posicao":{"x":1050,"y":470}},
      {"id":"n30","tipo":"rascunho_texto","config":{"rotulo":"Rascunho: pesquisa NPS de êxito (1 vez só)","texto":"{nome}, de 0 a 10, que nota você dá pro nosso atendimento até aqui? Sua opinião ajuda a gente a melhorar de verdade. E se a experiência foi boa, sua avaliação no Google ajuda outras pessoas a nos encontrarem: [link de avaliação do Google]"},"posicao":{"x":1050,"y":620}},
      {"id":"n31","tipo":"avisar_push","config":{"rotulo":"Push: concessão","titulo":"Beneficio CONCEDIDO (ADVBOX)","texto":"{nome_completo}: rascunho de boa notícia pronto no caso"},"posicao":{"x":1050,"y":770}},
      {"id":"n32","tipo":"registrar_atividade","config":{"rotulo":"Conclui as tarefas abertas do lead e registra a atividade","texto":"ADVBOX: {texto} — follow-ups do hub encerrados"},"posicao":{"x":1350,"y":320}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"c1","para":"n3"},
      {"de":"n3","saida":"s","para":"n4"},
      {"de":"n4","saida":"s","para":"n5"},
      {"de":"n2","saida":"c2","para":"n6"},
      {"de":"n6","saida":"s","para":"n7"},
      {"de":"n7","saida":"s","para":"n8"},
      {"de":"n2","saida":"c3","para":"n9"},
      {"de":"n9","saida":"s","para":"n10"},
      {"de":"n10","saida":"s","para":"n11"},
      {"de":"n11","saida":"s","para":"n12"},
      {"de":"n2","saida":"c4","para":"n13"},
      {"de":"n13","saida":"s","para":"n14"},
      {"de":"n14","saida":"s","para":"n15"},
      {"de":"n2","saida":"c5","para":"n16"},
      {"de":"n16","saida":"s","para":"n17"},
      {"de":"n17","saida":"s","para":"n18"},
      {"de":"n18","saida":"s","para":"n19"},
      {"de":"n2","saida":"c6","para":"n20"},
      {"de":"n20","saida":"s","para":"n21"},
      {"de":"n2","saida":"c7","para":"n22"},
      {"de":"n22","saida":"s","para":"n23"},
      {"de":"n23","saida":"s","para":"n24"},
      {"de":"n24","saida":"s","para":"n25"},
      {"de":"n2","saida":"c8","para":"n26"},
      {"de":"n26","saida":"s","para":"n27"},
      {"de":"n2","saida":"c9","para":"n28"},
      {"de":"n28","saida":"s","para":"n29"},
      {"de":"n29","saida":"s","para":"n30"},
      {"de":"n30","saida":"s","para":"n31"},
      {"de":"n2","saida":"c10","para":"n32"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/lead_ganho.json` (IDs do ADVBOX = constantes de `Ramon::AdvboxClosingService`: `TASK_ID` 8745394, `USERS_ID` 266778):

```json
{
  "nome": "Lead ganho",
  "grupo": "contrato_documentos",
  "descricao": "No código: callbacks do Lead quando won_at muda (app/models/lead.rb: generate_handoff_note, enqueue_advbox_closing, enqueue_nps_draft, enqueue_drive_export).\n\nO desenho não consegue mostrar:\n• as 4 ações são independentes e rodam ao mesmo tempo (o quadro só desenha fila), cada uma com a sua trava;\n• o dossiê vai para as notas do lead e não se repete se já houver um dos últimos 5 minutos;\n• no ADVBOX o código cria o cliente, o processo (etapa CONTRATO FECHADO) e a tarefa 1º CONTATO COM O LEAD (Ramon::AdvboxClosingService) — o passo ADVBOX dos fluxos só cria tarefa num processo que já existe; só roda com o token do ADVBOX e tenta de novo até 3 vezes se o ADVBOX estiver fora;\n• a pesquisa NPS vai para as notas do lead e sai uma vez só por lead;\n• o Drive só roda com o Drive configurado e roda de novo a cada atualização dos documentos de um lead já ganho.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"lead_ganho"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"nota_privada","config":{"rotulo":"Dossiê de passagem para o jurídico (nas notas do lead)","texto":"📋 DOSSIÊ — texto único de passagem do caso (Ramon::DossiePassagemTexto)"},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"advbox","config":{"rotulo":"ADVBOX: cliente, processo e tarefa 1º contato (só com token)","acao":"tarefa","tipo_tarefa_id":8745394,"responsavel_id":266778,"descricao":"Cliente + processo na etapa CONTRATO FECHADO + tarefa 1º CONTATO COM O LEAD"},"posicao":{"x":0,"y":280}},
      {"id":"n4","tipo":"rascunho_texto","config":{"rotulo":"Rascunho: pesquisa NPS (nas notas do lead, 1 vez só)","texto":"{nome}, de 0 a 10, que nota você dá pro nosso atendimento até aqui? Sua opinião ajuda a gente a melhorar de verdade. E se a experiência foi boa, sua avaliação no Google ajuda outras pessoas a nos encontrarem: [link de avaliação do Google]"},"posicao":{"x":0,"y":420}},
      {"id":"n5","tipo":"nota_privada","config":{"rotulo":"Drive: exporta os documentos conferidos (só com o Drive ligado)","texto":"Sobe para o Drive os documentos do lead já conferidos pela equipe"},"posicao":{"x":0,"y":580}}
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

`db/seeds/ramon/fluxos/sistema/resumo_do_dia.json`:

```json
{
  "nome": "Resumo do dia",
  "grupo": "rotinas_relatorios",
  "descricao": "No código: Ramon::DailyDigestJob (todo dia às 08:00) → Ramon::DailyDigestService; o e-mail sai pelo AdministratorNotifications::RamonDigestMailer.\n\nFica no código (spec §8): é relatório, não fluxo — o desenho é só para conferir.\n\nO desenho não consegue mostrar:\n• roda uma vez por conta, não uma vez por lead como o gatilho Relógio;\n• o push só sai se o dia tem algo (tarefas vencidas, conversas fora do SLA, reunião ainda hoje ou valor em jogo) e só com o ntfy configurado;\n• o e-mail de gestão (leads novos, ganhos, perdidos e 1ª resposta de ontem) só sai com SMTP configurado — o quadro não tem passo de e-mail.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"relogio","hora":"08:00","rotulo":"Todo dia às 08:00 (1 vez por conta)"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"avisar_push","config":{"rotulo":"Push: seu dia (só se houver algo)","titulo":"Ramon Hub · seu dia","texto":"N tarefas vencidas · N fora do SLA · reunião HH:MM (nome) · R$ em jogo"},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"nota_privada","config":{"rotulo":"E-mail de gestão: números de ontem (só com SMTP)","texto":"Leads novos, ganhos, perdidos e tempo de 1ª resposta de ontem"},"posicao":{"x":0,"y":280}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"s","para":"n3"}
    ]
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts`
Expected: PASS — 12 arquivos, 99 testes (86 + 13: 1 + 6 + 6). `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/sistema.spec.js` → sem `error`.

- [ ] **Step 5: Commit**

```bash
git add db/seeds/ramon/fluxos/sistema app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/sistema.spec.js
git commit -m "feat(fluxos): desenhos das 6 automações principais do sistema (só leitura)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 2: Desenhos do sistema II — as 23 automações menores

**Files:**
- Create: 23 arquivos em `db/seeds/ramon/fluxos/sistema/` (lista abaixo)
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/sistema.spec.js` (arquivo inteiro: trava das 29 + selos)

**Interfaces:**
- Consumes: formato, `GRUPOS_SISTEMA`, `ALCANCES` e a trava da Task 1.
- Produces: as 29 chaves (ver tabela "As 29 automações"); `alcance` só em `avisos_painel` (`fala_com_cliente`) e `publicar_pecas` (`publica`); `limite_dia` 15 em `copiloto_noturno` (padrão de `RAMON_NIGHT_COPILOT_LIMIT`).

- [ ] **Step 1: Write the failing test** — substituir `specs/sistema.spec.js` inteiro por:

```js
// Trava dos desenhos do sistema (db/seeds/ramon/fluxos/sistema/*.json, spec §8 +
// decisão do Eduardo 06/10: as 29 automações do código): o quadro abre cada um e a
// validação (espelho do Grafo) só deixa passar a etapa em aberto — a etapa é do
// funil de cada conta e a B4 escolhe ao migrar.
import { ALCANCES, GRUPOS_SISTEMA } from '../fluxo';
import { validar } from '../validar';

const ARQUIVOS = import.meta.glob(
  '../../../../../../../../db/seeds/ramon/fluxos/sistema/*.json',
  { eager: true, import: 'default' }
);
const DESENHOS = Object.entries(ARQUIVOS).map(([caminho, d]) => [
  caminho.split('/').pop().replace('.json', ''),
  d,
]);

describe('fluxos do sistema', () => {
  it('são as 29 automações do código', () => {
    expect(DESENHOS.map(([chave]) => chave).sort()).toEqual([
      'acervo_pecas',
      'agente_hub',
      'assinatura_painel',
      'ata_reuniao',
      'avisos_painel',
      'cadencia',
      'chegada_cliente',
      'coach_objecao',
      'contrato_limpo',
      'contrato_limpo_cancelado',
      'contrato_zapsign',
      'copiloto_noturno',
      'criar_lead_da_conversa',
      'docs_completos',
      'documento_painel',
      'espelho_painel',
      'etiquetas_etapa_tese',
      'eventos_advbox',
      'fechamento_extrato',
      'historico_do_lead',
      'lead_ganho',
      'lembretes_reuniao',
      'origem_do_lead',
      'publicar_pecas',
      'resumo_do_dia',
      'retrato_funil',
      'sdr_automatico',
      'sla_primeira_resposta',
      'sugestao_documento',
    ]);
  });

  it('só Avisos do Painel e Publicar peças saem para fora sem uma pessoa no meio', () => {
    const comSelo = Object.fromEntries(
      DESENHOS.filter(([, d]) => d.alcance).map(([chave, d]) => [
        chave,
        d.alcance,
      ])
    );
    expect(comSelo).toEqual({
      avisos_painel: 'fala_com_cliente',
      publicar_pecas: 'publica',
    });
  });

  it.each(DESENHOS)(
    '%s: nome, grupo, onde vive no código e desenho válido (menos a etapa)',
    (_chave, d) => {
      expect(d.nome).toBeTruthy();
      expect(GRUPOS_SISTEMA).toContain(d.grupo);
      expect([undefined, ...ALCANCES]).toContain(d.alcance);
      expect(d.descricao.split('\n')[0]).toMatch(/^No código: /);
      const erros = validar(d.desenho).filter(
        e => !(e.codigo === 'FALTA' && e.params.campo === 'etapa_id')
      );
      expect(erros).toEqual([]);
    }
  );

  it.each(DESENHOS)(
    '%s: todo passo diz no rótulo o que o código faz',
    (_chave, d) => {
      const semRotulo = d.desenho.nos
        .filter(n => n.tipo !== 'gatilho' && !n.config?.rotulo)
        .map(n => n.id);
      expect(semRotulo).toEqual([]);
    }
  );
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/sistema.spec.js --config vitest.local.config.ts`
Expected: FAIL — "são as 29 automações do código" (só há 6) e "só Avisos… e Publicar…" (`{}`).

- [ ] **Step 2b: Leia antes de criar** — cada arquivo é gatilho → 1 a 4 passos. Onde o gatilho real não existe nos fluxos, o gatilho é `manual` com `rotulo` do evento real (convenção acima). Os IDs do ADVBOX de `documento_painel` são as constantes de `Ramon::PortalEnvioJob` (`TASKS_ID_ANALISAR` 9502039, `TASKS_ID_JUNTADA` 8745531, `SECRETARIA_ID` 260014) e o responsável padrão de `Ramon::AdvboxClosingService::USERS_ID` (266778).

- [ ] **Step 3: Create the 23 JSON files** (UTF-8, exatamente como abaixo).

`db/seeds/ramon/fluxos/sistema/criar_lead_da_conversa.json` (Leads e conversas — Criar lead da conversa):

```json
{
  "nome": "Criar lead da conversa",
  "grupo": "leads_conversas",
  "descricao": "No código: RamonLeadListener#conversation_created (app/listeners/ramon_lead_listener.rb), só em caixas com Criar lead ligado.\n\nO desenho não consegue mostrar:\n• cria o lead na 1ª etapa do funil ou liga a conversa ao lead aberto do mesmo contato — não há passo que crie lead;\n• o mesmo ouvinte agenda o SLA da 1ª resposta (ver \"SLA da 1ª resposta\").",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"conversa_criada","rotulo":"Conversa nova numa caixa com Criar lead"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"nota_privada","config":{"rotulo":"Cria o lead (ou liga a conversa ao lead aberto do contato)","texto":"Lead novo na 1ª etapa do funil, com o nome e o telefone do contato"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/origem_do_lead.json` (Leads e conversas — Origem do lead):

```json
{
  "nome": "Origem do lead",
  "grupo": "leads_conversas",
  "descricao": "No código: RamonLeadListener#message_created → apply_meta_referral e derive_channel_from_first_contact.\n\nO desenho não consegue mostrar:\n• lê o anúncio da Meta (click-to-WhatsApp) que chega com a mensagem e grava origem e canal; sem anúncio e sem assinatura de site/LP/bio, o canal vira indicação (ou instagram, se a caixa for do Instagram);\n• grava nas colunas do lead (source, channel) e em custom_attributes.meta_referral — o passo Preencher campo só grava em campos;\n• nunca sobrescreve um canal já definido.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"mensagem_recebida"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"preencher_campo","config":{"rotulo":"Origem e canal do lead (anúncio da Meta, site/LP/bio ou indicação)","chave":"origem_detectada","valor":"anúncio da Meta, site/LP/bio, instagram ou indicação"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/coach_objecao.json` (Leads e conversas — Coach de objeção):

```json
{
  "nome": "Coach de objeção",
  "grupo": "leads_conversas",
  "descricao": "No código: RamonLeadListener#message_created → Ramon::CoachObjecaoJob → Ramon::CoachObjecaoService (texto com 20 letras ou mais).\n\nO desenho não consegue mostrar:\n• no máximo 1 vez a cada 10 min por conversa; qualquer erro = silêncio;\n• as 2 respostas vêm do playbook da tese (objeções) e aparecem num balão de evento — \"Usar →\" só coloca o texto no editor, quem envia é a pessoa.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"mensagem_recebida","rotulo":"Mensagem com texto (20 letras ou mais)"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"perguntar_ia","config":{"rotulo":"Há objeção nesta mensagem?","pergunta":"O cliente levantou uma objeção (preço, desconfiança, \"vou pensar\"…)?"},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"nota_privada","config":{"rotulo":"Balão com 2 respostas do playbook (Usar → só preenche o editor)","texto":"Duas respostas prontas para a objeção, tiradas do playbook da tese"},"posicao":{"x":0,"y":280}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"sim","para":"n3"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/etiquetas_etapa_tese.json` (Leads e conversas — Etiquetas de etapa e tese):

```json
{
  "nome": "Etiquetas de etapa e tese",
  "grupo": "leads_conversas",
  "descricao": "No código: RamonLeadListener#lead_created, #lead_updated e #conversation_updated → Ramon::StageLabelSync e Ramon::TeseLabelSync.\n\nO desenho não consegue mostrar:\n• põe na conversa a etiqueta fase-<etapa> e tese-<tese> do lead (e tira a antiga); a etiqueta sai do nome da etapa/tese, o passo usa etiqueta fixa;\n• no sentido contrário, etiqueta fase-* posta à mão na conversa move o lead — os fluxos não têm gatilho de etiqueta;\n• também roda quando o lead é criado.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"lead_mudou_etapa"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"acao_chatwoot","config":{"rotulo":"Etiquetas fase-* e tese-* na conversa","acoes":[{"action_name":"add_label","action_params":["fase-<etapa>","tese-<tese>"]}]},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/historico_do_lead.json` (Leads e conversas — Histórico do lead):

```json
{
  "nome": "Histórico do lead",
  "grupo": "leads_conversas",
  "descricao": "No código: callbacks de Lead (record_created_activity, record_change_activities), LeadNote e LeadTask (record_*_activity).\n\nO desenho não consegue mostrar:\n• cada mudança do lead (etapa, responsável, valor, motivo de perda…), nota e tarefa vira uma linha no histórico, cada uma com o seu tipo;\n• o mesmo vale para lead criado, nota e tarefa nova — o quadro tem 1 gatilho só.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"lead_mudou_etapa"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"registrar_atividade","config":{"rotulo":"Linha no histórico do lead (de → para)","texto":"Etapa mudou para {etapa}"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/sdr_automatico.json` (Leads e conversas — SDR automático):

```json
{
  "nome": "SDR automático",
  "grupo": "leads_conversas",
  "descricao": "No código: LeadComercial (app/models/concerns/lead_comercial.rb): before_create :assign_sdr e after_commit :assign_conversation_to_sdr.\n\nO desenho não consegue mostrar:\n• o SDR é o do time com menos leads abertos (Ramon::Papeis.proximo) e só entra se o lead nasce sem SDR; roda antes de o lead existir;\n• a conversa vai para o SDR também quando o SDR muda ou o lead ganha conversa;\n• o passo Atribuir escolhe uma pessoa fixa; aqui é sempre o SDR do lead.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"lead_criado"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"trocar_responsavel","config":{"rotulo":"SDR automático (o do time com menos leads abertos)","papel":"sdr"},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"acao_chatwoot","config":{"rotulo":"Conversa atribuída ao SDR do lead","acoes":[{"action_name":"assign_agent","action_params":[]}]},"posicao":{"x":0,"y":280}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"s","para":"n3"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/chegada_cliente.json` (Leads e conversas — Chegada de cliente):

```json
{
  "nome": "Chegada de cliente",
  "grupo": "leads_conversas",
  "descricao": "No código: RamonChegadasController#create agenda Ramon::ChegadaEscalarJob para 3 min depois (Chegada::ESCALAR_APOS).\n\nO desenho não consegue mostrar:\n• o aviso de chegada é feito pela recepção no hub — os fluxos não têm esse gatilho (aqui: Rodar na mão com o rótulo do evento real);\n• só escala se ninguém respondeu; o alerta volta a tocar na tela de quem avisou (ao vivo, não é o sino).",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"manual","rotulo":"Recepção avisa a chegada do cliente"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"esperar","config":{"rotulo":"3 minutos","quantidade":3,"unidade":"minutos"},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"avisar_sino","config":{"rotulo":"Escala de volta para quem avisou (se ninguém respondeu)","texto":"Cliente chegou e ninguém respondeu"},"posicao":{"x":0,"y":280}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"s","para":"n3"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/agente_hub.json` (Leads e conversas — Agente do hub (@claude)):

```json
{
  "nome": "Agente do hub (@claude)",
  "grupo": "leads_conversas",
  "descricao": "No código: RamonAgenteListener#message_created → Ramon::AgenteNotifyJob.\n\nO desenho não consegue mostrar:\n• só nota privada começando com @claude, escrita pelo e-mail do Eduardo (RAMON_AGENTE_EDUARDO_EMAIL) e com RAMON_AGENTE_RUNNER_URL — os fluxos não têm gatilho de nota privada (aqui: Rodar na mão);\n• quem responde é o agente na VPS, também como nota privada; falha de rede só vai para o log.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"manual","rotulo":"Nota privada @claude do Eduardo"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"webhook","config":{"rotulo":"Avisa o agente do hub na VPS","url":"https://RAMON_AGENTE_RUNNER_URL"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/ata_reuniao.json` (Leads e conversas — Ata da reunião):

```json
{
  "nome": "Ata da reunião",
  "grupo": "leads_conversas",
  "descricao": "No código: RamonReunioesController (gravar e refazer) → Ramon::ReuniaoAtaJob → Ramon::ReuniaoAtaService.\n\nO desenho não consegue mostrar:\n• começa quando a reunião é gravada no hub (ou alguém pede para refazer a ata) — os fluxos não têm esse gatilho (aqui: Rodar na mão);\n• transcreve o áudio no whisper local e a IA escreve a ata na própria reunião (não é nota de conversa); tenta de novo até 3 vezes se o LLM falhar.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"manual","rotulo":"Reunião gravada (ou Refazer ata)"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"nota_privada","config":{"rotulo":"Transcreve o áudio e a IA escreve a ata","texto":"Ata da reunião escrita pela IA a partir da gravação"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/sugestao_documento.json` (Contrato e documentos — Sugestão de documento):

```json
{
  "nome": "Sugestão de documento",
  "grupo": "contrato_documentos",
  "descricao": "No código: RamonLeadListener#message_created → Ramon::DocMatchJob → Ramon::DocMatchService (anexo de imagem ou arquivo).\n\nO desenho não consegue mostrar:\n• a IA compara o anexo com o checklist da tese e grava uma sugestão (custom_attributes.doc_sugestao) — quem confirma é a equipe, no painel;\n• o aviso na conversa é um balão de evento (não nota privada);\n• é daqui que nasce o gatilho Documento recebido dos fluxos.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"mensagem_recebida","rotulo":"Mensagem com anexo (imagem ou arquivo)"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"nota_privada","config":{"rotulo":"IA sugere o item do checklist (a equipe confirma)","texto":"Balão: o anexo parece ser um documento do checklist — confirmar no painel"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/docs_completos.json` (Contrato e documentos — Documentos completos):

```json
{
  "nome": "Documentos completos",
  "grupo": "contrato_documentos",
  "descricao": "No código: LeadComercial before_save :stamp_docs_completos (app/models/concerns/lead_comercial.rb).\n\nO desenho não consegue mostrar:\n• roda a cada gravação do lead que mexa nos documentos ou na tese — os fluxos não têm esse gatilho (aqui: Rodar na mão);\n• grava a coluna docs_completos_em (usada no contrato limpo e nos relatórios), não um campo livre, e apaga o carimbo se o checklist voltar a ficar incompleto;\n• só conta o que a equipe confirmou.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"manual","rotulo":"Equipe confirma documento ou muda a tese"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"se","config":{"rotulo":"Documentos completos?","juncao":"e","condicoes":[{"campo":"documentos_completos","operador":"igual","valor":"sim"}]},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"preencher_campo","config":{"rotulo":"Carimba docs_completos_em","chave":"docs_completos_em","valor":"agora"},"posicao":{"x":0,"y":280}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"sim","para":"n3"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/contrato_zapsign.json` (Contrato e documentos — Contrato no ZapSign):

```json
{
  "nome": "Contrato no ZapSign",
  "grupo": "contrato_documentos",
  "descricao": "No código: webhook do ZapSign (Public::Api::V1::ZapsignWebhooksController) → Ramon::ZapsignLeadStatusJob; também logo depois do envio do contrato (Ramon::ZapsignContractService).\n\nO desenho não consegue mostrar:\n• confere no ZapSign o status real (o payload do webhook não é a verdade) e grava o selo em custom_attributes.zapsign — o passo Preencher campo grava em campos;\n• nunca marca o lead como ganho: ganho continua sendo decisão do Closer;\n• é daqui que nascem os gatilhos Contrato assinado e Contrato recusado dos fluxos (o desenho usa o de assinado; recusado faz o mesmo).",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"contrato_assinado","rotulo":"ZapSign: contrato assinado ou recusado"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"preencher_campo","config":{"rotulo":"Selo do contrato no card do lead","chave":"zapsign_selo","valor":"assinado ou recusado"},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"registrar_atividade","config":{"rotulo":"Histórico: contrato assinado ou recusado","texto":"Contrato assinado ou recusado no ZapSign"},"posicao":{"x":0,"y":280}},
      {"id":"n4","tipo":"avisar_sino","config":{"rotulo":"Sino do contrato","texto":"Contrato de {nome_completo} assinado ou recusado"},"posicao":{"x":0,"y":420}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"s","para":"n3"},
      {"de":"n3","saida":"s","para":"n4"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/contrato_limpo.json` (Contrato e documentos — Contrato limpo):

```json
{
  "nome": "Contrato limpo",
  "grupo": "contrato_documentos",
  "descricao": "No código: Ramon::ContratoLimpoJob (toda hora, aos 10 min — config/schedule.yml).\n\nO desenho não consegue mostrar:\n• roda de hora em hora para todos os leads ganhos, não 1 vez por lead — aqui o gatilho é Rodar na mão com o rótulo do horário real;\n• limpo = ganho + checklist completo + 7 dias corridos sem cancelar; o carimbo é o momento exato em que ficou limpo e não muda mais (vale para o extrato da variável);\n• grava a coluna contrato_limpo_em, não um campo livre.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"manual","rotulo":"Toda hora, aos 10 minutos"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"se","config":{"rotulo":"Ganho + documentos completos há 7 dias, sem cancelar?","juncao":"e","condicoes":[{"campo":"documentos_completos","operador":"igual","valor":"sim"}]},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"preencher_campo","config":{"rotulo":"Carimba contrato_limpo_em (extrato da variável)","chave":"contrato_limpo_em","valor":"momento em que ficou limpo"},"posicao":{"x":0,"y":280}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"sim","para":"n3"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/contrato_limpo_cancelado.json` (Contrato e documentos — Contrato limpo cancelado):

```json
{
  "nome": "Contrato limpo cancelado",
  "grupo": "contrato_documentos",
  "descricao": "No código: LeadComercial after_save :cancelar_contrato_limpo (app/models/concerns/lead_comercial.rb).\n\nO desenho não consegue mostrar:\n• só quando o ganho é desfeito (won_at volta a vazio) e o lead já tinha o carimbo de limpo;\n• apaga a coluna contrato_limpo_em; se o mês já fechou, o desconto entra na apuração seguinte (Ramon::ExtratoDescontos).",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"lead_mudou_etapa","rotulo":"Lead sai de Fechado depois de limpo"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"preencher_campo","config":{"rotulo":"Apaga o carimbo de contrato limpo","chave":"contrato_limpo_em","valor":"(vazio)"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/assinatura_painel.json` (Painel do Cliente — Assinatura pelo Painel do Cliente):

```json
{
  "nome": "Assinatura pelo Painel do Cliente",
  "grupo": "painel_cliente",
  "descricao": "No código: webhook do ZapSign (Public::Api::V1::ZapsignWebhooksController) → Ramon::ZapsignStatusJob.\n\nO desenho não consegue mostrar:\n• confere no ZapSign o status real e marca a assinatura do Painel (PortalAssinatura) — não é lead nem conversa, e os fluxos não têm esse gatilho (aqui: Rodar na mão).",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"manual","rotulo":"ZapSign: documento do Painel assinado"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"nota_privada","config":{"rotulo":"Marca a assinatura no Painel do Cliente","texto":"Assinatura do cliente registrada no Painel"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/documento_painel.json` (Painel do Cliente — Documento enviado pelo Painel):

```json
{
  "nome": "Documento enviado pelo Painel",
  "grupo": "painel_cliente",
  "descricao": "No código: Cliente::PainelController (envio) → Ramon::PortalEnvioJob.\n\nO desenho não consegue mostrar:\n• começa com o cliente enviando um arquivo pelo Painel — os fluxos não têm esse gatilho (aqui: Rodar na mão);\n• antes de tudo o arquivo vai para o Drive (Clientes/<Nome — CPF>) — não há passo de Drive;\n• a 1ª tarefa vai para o responsável do processo no ADVBOX (o desenho mostra o padrão, Eduardo); cada passo é idempotente e o ADVBOX tenta de novo até 5 vezes.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"manual","rotulo":"Cliente envia documento pelo Painel"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"avisar_push","config":{"rotulo":"Push: documento do cliente","titulo":"Documento do cliente {nome_completo}","texto":"Arquivo enviado pelo Painel do Cliente"},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"advbox","config":{"rotulo":"ADVBOX: ANALISAR DOCUMENTAÇÃO (responsável do processo)","acao":"tarefa","tipo_tarefa_id":9502039,"responsavel_id":266778,"descricao":"Cliente enviou pelo Painel do Cliente: <item> (link do Drive)"},"posicao":{"x":0,"y":280}},
      {"id":"n4","tipo":"advbox","config":{"rotulo":"ADVBOX: ORGANIZAR DOCUMENTOS (recepção)","acao":"tarefa","tipo_tarefa_id":8745531,"responsavel_id":260014,"descricao":"Anexar no ADVBOX o arquivo enviado pelo Painel"},"posicao":{"x":0,"y":420}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"s","para":"n3"},
      {"de":"n3","saida":"s","para":"n4"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/espelho_painel.json` (Painel do Cliente — Espelho do Painel do Cliente):

```json
{
  "nome": "Espelho do Painel do Cliente",
  "grupo": "painel_cliente",
  "descricao": "No código: Ramon::PortalSyncJob (todo dia às 00:30) → Ramon::PortalSyncService.\n\nO desenho não consegue mostrar:\n• roda 1 vez por noite para todos os clientes do Painel, não por lead; falha de um cliente não derruba os outros;\n• copia do ADVBOX processos, andamentos e pedidos de documento — não há passo que leia do ADVBOX.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"relogio","hora":"00:30","rotulo":"Toda noite às 00:30 (todos os clientes)"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"nota_privada","config":{"rotulo":"Espelha processos e andamentos do ADVBOX no Painel","texto":"Atualiza o Painel do Cliente com o que mudou no ADVBOX"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/avisos_painel.json` (Painel do Cliente — Avisos do Painel do Cliente, selo "fala_com_cliente"):

```json
{
  "nome": "Avisos do Painel do Cliente",
  "grupo": "painel_cliente",
  "alcance": "fala_com_cliente",
  "descricao": "No código: Ramon::PortalAvisosJob (todo dia às 08:00) — DESLIGADO até o Eduardo aprovar os textos (env PORTAL_AVISOS=on).\n\nO desenho não consegue mostrar:\n• quando ligado, manda e-mail DIRETO ao cliente com as novidades do espelho da noite, sem revisão de uma pessoa (etapas delicadas nunca vão por e-mail) — os fluxos não têm passo de e-mail e só fazem rascunho;\n• a equipe recebe 1 e-mail de resumo com o texto pronto de WhatsApp e o link wa.me de cada cliente — quem manda o WhatsApp é uma pessoa;\n• roda 1 vez por dia para todos os clientes, não por lead.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"relogio","hora":"08:00","rotulo":"Todo dia às 08:00 (só com PORTAL_AVISOS=on)"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"nota_privada","config":{"rotulo":"E-mail ao cliente com as novidades (direto, sem revisão)","texto":"Novidades do processo por e-mail — etapas delicadas nunca vão"},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"nota_privada","config":{"rotulo":"E-mail de resumo para a equipe (WhatsApp pronto + wa.me)","texto":"Clientes com novidade hoje, com o texto de WhatsApp para uma pessoa enviar"},"posicao":{"x":0,"y":280}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"s","para":"n3"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/copiloto_noturno.json` (Rotinas e relatórios — Copiloto noturno):

```json
{
  "nome": "Copiloto noturno",
  "grupo": "rotinas_relatorios",
  "descricao": "No código: Ramon::NightCopilotJob (todo dia às 05:00) → Ramon::NightCopilotService.\n\nO desenho não consegue mostrar:\n• varre os leads parados todo dia (no máximo RAMON_NIGHT_COPILOT_LIMIT, padrão 15) — o gatilho Lead parado dos fluxos dispara 1 vez por parada;\n• o resultado é uma sugestão pendente no Cockpit (rascunho de mensagem, mover etapa ou alerta) que uma pessoa aprova de manhã — não é nota na conversa.",
  "limite_dia": 15,
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"lead_parado","hora":"05:00"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"rascunho_ia","config":{"rotulo":"Sugestão da IA para aprovar no Cockpit","instrucao":"Analise o lead parado e sugira uma coisa só: um rascunho de mensagem, mover de etapa ou um alerta para a equipe. Nunca prometa resultado nem prazo do INSS."},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/fechamento_extrato.json` (Rotinas e relatórios — Fechamento do extrato):

```json
{
  "nome": "Fechamento do extrato",
  "grupo": "rotinas_relatorios",
  "descricao": "No código: Ramon::ExtratoFechamentoJob (todo dia às 00:20; age no 3º dia útil) → Ramon::ExtratoFechamento.\n\nO desenho não consegue mostrar:\n• fecha o extrato da variável do mês anterior (regulamento §6) — é da conta, não de um lead;\n• a tela do Extrato também fecha na 1ª leitura depois da data; o job garante o fechamento mesmo se ninguém abrir.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"relogio","hora":"00:20","rotulo":"Todo dia às 00:20 (age no 3º dia útil)"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"nota_privada","config":{"rotulo":"Fecha o extrato da variável do mês anterior","texto":"Extrato do mês anterior fechado (não muda mais)"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/retrato_funil.json` (Rotinas e relatórios — Retrato do funil):

```json
{
  "nome": "Retrato do funil",
  "grupo": "rotinas_relatorios",
  "descricao": "No código: Ramon::DailyFunnelSnapshotJob (todo dia às 00:05) → Ramon::FunnelSnapshotService.\n\nO desenho não consegue mostrar:\n• guarda o retrato agregado do funil do dia para os relatórios — é da conta, não de um lead; não há passo de relatório.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"relogio","hora":"00:05","rotulo":"Todo dia às 00:05"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"nota_privada","config":{"rotulo":"Tira o retrato do funil do dia","texto":"Números do funil do dia, guardados para os relatórios"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/publicar_pecas.json` (Instagram — Publicar peças no Instagram, selo "publica"):

```json
{
  "nome": "Publicar peças no Instagram",
  "grupo": "instagram",
  "alcance": "publica",
  "descricao": "No código: Ramon::PublicarPecasJob (a cada minuto) → Ramon::InstagramPublisher (API oficial da Meta).\n\nO desenho não consegue mostrar:\n• publica no Instagram da banca as peças agendadas que já venceram — só peças aprovadas com \"pode postar\";\n• roda a cada minuto, não 1 vez por dia (aqui: Rodar na mão com o rótulo do horário real); não é lead nem conversa;\n• sem nova tentativa automática: falhou → status falhou + push, e o Eduardo decide tentar de novo.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"manual","rotulo":"A cada minuto: peças agendadas que venceram"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"webhook","config":{"rotulo":"Publica no Instagram (API oficial da Meta)","url":"https://graph.facebook.com"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/acervo_pecas.json` (Instagram — Acervo das peças (Drive e Notion)):

```json
{
  "nome": "Acervo das peças (Drive e Notion)",
  "grupo": "instagram",
  "descricao": "No código: Ramon::ConteudoDriveJob (depois de publicar) e Ramon::NotionEspelhoJob (Peca after_update_commit quando o status muda).\n\nO desenho não consegue mostrar:\n• copia a peça publicada (JPEGs + legenda) para Posts Instagram/<tipo>/<rodada — gancho> no Drive e espelha o status no kanban Peças do Notion (só com RAMON_NOTION_TOKEN) — não há passo de Drive nem de Notion;\n• best-effort: erro não volta; não é lead nem conversa.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"manual","rotulo":"Peça publicada ou status mudou"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"nota_privada","config":{"rotulo":"Acervo no Drive + status no Notion","texto":"Peça copiada para o Drive e status espelhado no Notion"},"posicao":{"x":0,"y":140}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"}
    ]
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts`
Expected: PASS — 12 arquivos, 146 testes (sistema.spec = 2 + 29 + 29 = 60). `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/sistema.spec.js` → sem `error`.

- [ ] **Step 5: Commit**

```bash
git add db/seeds/ramon/fluxos/sistema app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/sistema.spec.js
git commit -m "feat(fluxos): desenhos das 23 automações menores do sistema" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 3: `Ramon::Fluxos::Sistema` — fluxos do sistema por conta, "Hoje" e extras

**Files:**
- Create: `app/services/ramon/fluxos/sistema.rb`
- Test: `spec/services/ramon/fluxos/sistema_spec.rb` (novo)

**Interfaces:**
- Consumes: os 29 JSON; `Ramon::Fluxos::Grafo.new(desenho).gatilho` / `#erros`; `Ramon::Cadencia.sla_conversations(account, range)` (`app/services/ramon/cadencia.rb:45-49`); `Fluxo::ZONA` (`'America/Sao_Paulo'`); associações `Account#lead_notes`, `#lead_activities`, `#leads`, `#copilot_suggestions`, `#chegadas`, `#pecas` (`app/models/account.rb:75-99`).
- Produces (usado pela Task 4):
  - `Ramon::Fluxos::Sistema.desenhos → Hash{String chave => Hash do JSON}` (ordenado pela chave)
  - `Ramon::Fluxos::Sistema.sincronizar(account) → nil` — garante 1 `Fluxo` `origem: 'sistema'` por chave, com `nome`, `descricao`, `limite_dia`, `rascunho` (= `desenho`) e `gatilho_tipo` do JSON; `ativo` `false`, `versao_publicada_id` `nil`. Nada mudou → 1 SELECT, sem lock.
  - `Ramon::Fluxos::Sistema.hoje(account, chave) → Integer | nil` (nil = sem contador → "—"); dia = hoje em SP.
  - `Ramon::Fluxos::Sistema.extras(account, chave) → { hoje:, grupo:, alcance:, gatilho_rotulo: }`.

- [ ] **Step 1: Write the failing test** — `spec/services/ramon/fluxos/sistema_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Sistema do
  let(:account) { create(:account) }

  def sp(texto) = Time.find_zone!('America/Sao_Paulo').parse(texto)

  def do_sistema(chave) = account.fluxos.find_by(origem: 'sistema', sistema_chave: chave)

  it 'os 29 desenhos passam no Grafo (só a etapa fica em aberto: é do funil de cada conta)' do
    expect(described_class.desenhos.size).to eq(29)
    described_class.desenhos.each do |chave, d|
      erros = Ramon::Fluxos::Grafo.new(d['desenho']).erros.grep_v(/: falta etapa_id\z/)
      expect([chave, d['nome'].present?, d['grupo'].present?, erros]).to eq([chave, true, true, []])
    end
  end

  it 'cria 1 fluxo do sistema por desenho, desligado e sem versão, e não duplica' do
    2.times { described_class.sincronizar(account) }
    fluxos = account.fluxos.where(origem: 'sistema')
    expect(fluxos.pluck(:sistema_chave)).to match_array(described_class.desenhos.keys)
    expect(fluxos.pluck(:ativo, :versao_publicada_id).uniq).to eq([[false, nil]])
    expect(do_sistema('lembretes_reuniao')).to have_attributes(nome: 'Lembretes de reunião', gatilho_tipo: 'reuniao_marcada')
    expect(do_sistema('cadencia').limite_dia).to eq(15)
    expect(Fluxo.executaveis).to be_empty
  end

  it 'desenho corrigido no código chega à conta na próxima lista, sem criar outro' do
    described_class.sincronizar(account)
    novo = described_class.desenhos.deep_dup
    novo['cadencia']['nome'] = 'Cadência (corrigida)'
    allow(described_class).to receive(:desenhos).and_return(novo)
    expect { described_class.sincronizar(account) }.not_to(change { account.fluxos.count })
    expect(do_sistema('cadencia').nome).to eq('Cadência (corrigida)')
  end

  it 'nada mudou: não trava a conta' do
    described_class.sincronizar(account)
    allow(account).to receive(:with_lock)
    described_class.sincronizar(account)
    expect(account).not_to have_received(:with_lock)
  end

  it 'extras: grupo, selo de quem sai para fora e o rótulo do gatilho real' do
    expect(described_class.extras(account, 'avisos_painel')).to eq(
      hoje: nil, grupo: 'painel_cliente', alcance: 'fala_com_cliente',
      gatilho_rotulo: 'Todo dia às 08:00 (só com PORTAL_AVISOS=on)'
    )
    expect(described_class.extras(account, 'publicar_pecas')).to include(grupo: 'instagram', alcance: 'publica', hoje: 0)
    expect(described_class.extras(account, 'cadencia')).to include(alcance: nil, gatilho_rotulo: nil)
  end

  describe 'Hoje (fuso SP)' do
    let(:lead) { create(:lead, account: account) }
    let(:ganho) { account.lead_stages.find_by(is_won: true) }

    it 'toda fonte de "Hoje" é de um desenho e responde um número (coluna errada quebra aqui)' do
      expect(described_class::HOJE.keys - described_class.desenhos.keys).to eq([])
      expect(described_class::HOJE.keys.map { |c| described_class.hoje(account, c) }).to all(be_a(Integer))
    end

    it 'conta só onde há fonte barata; sem fonte fica sem número' do
      travel_to(sp('2026-10-06 10:00')) do
        lead.lead_notes.create!(account: account, body: "RASCUNHO (revisar antes de enviar) — retomada nº 1:\noi")
        lead.lead_notes.create!(account: account, body: 'outra nota')
        lead.lead_activities.create!(account: account, kind: 'meeting_scheduled', to_value: 'Reunião')
        lead.update_columns(docs_completos_em: Time.current, contrato_limpo_em: Time.current) # rubocop:disable Rails/SkipsModelValidations
        AdvboxEvent.create!(account: account, event_key: 'e1', status: 'processed')
        AdvboxEvent.create!(account: account, event_key: 'e2', status: 'ignored')
        create(:lead, account: account, lead_stage: ganho)
        create(:conversation, account: account, inbox: create(:inbox, account: account, auto_create_lead: true))
        chaves = %w[cadencia lembretes_reuniao eventos_advbox lead_ganho sla_primeira_resposta docs_completos contrato_limpo resumo_do_dia]
        expect(chaves.map { |c| described_class.hoje(account, c) }).to eq([1, 1, 1, 1, 1, 1, 1, nil])
      end
    end

    it 'o dia é o de São Paulo' do
      travel_to(sp('2026-10-05 23:30')) { create(:lead, account: account, lead_stage: ganho) }
      travel_to(sp('2026-10-06 09:00')) { expect(described_class.hoje(account, 'lead_ganho')).to eq(0) }
    end
  end
end
```

Notas para conferir à mão (sem Ruby local): a conta nasce com as etapas padrão (`Account` after_create → `Leads::SeedDefaultConfigService`), por isso `find_by(is_won: true)` existe (mesmo padrão de `leads_controller_spec.rb:536`); lead criado direto em etapa de ganho grava `won_at` no `track_stage_cycle`; `update_columns` não passa pelo `stamp_docs_completos`; a nota de lead cria uma atividade `note_added` (não conta como reunião); o `RamonLeadListener` é assíncrono (não roda no spec), então a conversa nova não cria lead extra.

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/services/ramon/fluxos/sistema_spec.rb` (no CI — sem Ruby local).
Expected: FAIL — `uninitialized constant Ramon::Fluxos::Sistema`.

- [ ] **Step 3: Write minimal implementation** — `app/services/ramon/fluxos/sistema.rb`:

```ruby
# Fluxos do sistema (spec §8, D7; decisão do Eduardo 06/10: as 29 automações do código): o desenho
# só-leitura de cada automação que ainda roda no código. Fonte = db/seeds/ramon/fluxos/sistema/<chave>.json
# ({nome, grupo, alcance?, descricao, limite_dia?, desenho}). Cada conta tem 1 Fluxo origem 'sistema' por
# arquivo (sistema_chave = nome do arquivo), criado ou atualizado quando a lista abre. O motor nunca os
# executa (Fluxo.executaveis e Disparo#iniciar) e a API recusa editar, publicar, ensaiar e rodar.
module Ramon::Fluxos::Sistema
  PASTA = Rails.root.join('db/seeds/ramon/fluxos/sistema')
  CAMPOS = %w[nome descricao limite_dia rascunho].freeze
  RETOMADA = 'RASCUNHO (revisar antes de enviar) — retomada%'.freeze # Ramon::FollowUpDraftService#draft_for
  REUNIAO = %w[meeting_scheduled meeting_rescheduled].freeze # Ramon::ReuniaoAgendamento#call / #remarcar

  # "Hoje" da aba Do sistema (spec §7): só onde o código já deixa rastro barato (1 count); sem fonte → nil ("—").
  HOJE = {
    'cadencia' => ->(conta, dia) { conta.lead_notes.where(created_at: dia).where('body LIKE ?', RETOMADA).count },
    'sla_primeira_resposta' => ->(conta, dia) { Ramon::Cadencia.sla_conversations(conta, dia).count },
    'lembretes_reuniao' => ->(conta, dia) { conta.lead_activities.where(kind: REUNIAO, created_at: dia).count },
    'eventos_advbox' => ->(conta, dia) { AdvboxEvent.where(account: conta, status: 'processed', updated_at: dia).count },
    'lead_ganho' => ->(conta, dia) { conta.leads.where(won_at: dia).count },
    'docs_completos' => ->(conta, dia) { conta.leads.where(docs_completos_em: dia).count },
    'contrato_limpo' => ->(conta, dia) { conta.leads.where(contrato_limpo_em: dia).count },
    'copiloto_noturno' => ->(conta, dia) { conta.copilot_suggestions.where(created_at: dia).count },
    'chegada_cliente' => ->(conta, dia) { conta.chegadas.where(escalado_em: dia).count },
    'publicar_pecas' => ->(conta, dia) { conta.pecas.where(publicacao_iniciada_em: dia).count }
  }.freeze

  module_function

  def desenhos
    @desenhos ||= PASTA.glob('*.json').sort.to_h { |arquivo| [arquivo.basename('.json').to_s, JSON.parse(arquivo.read)] }
  end

  # Chamado pela lista: nada mudou = 1 SELECT. Criar/atualizar sob o lock da conta: duas abas abertas
  # ao mesmo tempo logo depois do deploy não duplicam. Linha cujo JSON sumiu fica (a B4 decide).
  def sincronizar(account)
    return if em_dia?(account)

    account.with_lock { gravar(account) }
  end

  def hoje(account, chave)
    HOJE[chave]&.call(account, Time.find_zone!(Fluxo::ZONA).now.all_day)
  end

  # O que a lista e o desenho mostram além das colunas do Fluxo (vem do JSON em memória, sem coluna nova).
  # gatilho_rotulo: quando o gatilho real não existe nos fluxos, o desenho usa o mais próximo e o rótulo diz o real.
  def extras(account, chave)
    desenho = desenhos[chave] || {}
    {
      hoje: hoje(account, chave), grupo: desenho['grupo'], alcance: desenho['alcance'],
      gatilho_rotulo: Ramon::Fluxos::Grafo.new(desenho['desenho']).gatilho&.dig('config', 'rotulo')
    }
  end

  def em_dia?(account)
    atuais = account.fluxos.where(origem: 'sistema').pluck(:sistema_chave, *CAMPOS).to_h { |chave, *resto| [chave, resto] }
    desenhos.all? { |chave, d| atuais[chave] == atributos(d).values_at(*CAMPOS) }
  end

  def gravar(account)
    existentes = account.fluxos.where(origem: 'sistema').index_by(&:sistema_chave)
    desenhos.each do |chave, d|
      (existentes[chave] || account.fluxos.new(origem: 'sistema', sistema_chave: chave)).update!(atributos(d))
    end
  end

  def atributos(desenho)
    {
      'nome' => desenho['nome'], 'descricao' => desenho['descricao'], 'limite_dia' => desenho['limite_dia'],
      'rascunho' => desenho['desenho'], 'gatilho_tipo' => Ramon::Fluxos::Grafo.new(desenho['desenho']).gatilho&.dig('config', 'tipo')
    }
  end
end
```

Conferência à mão: `pluck` de jsonb devolve Hash com chaves string, igual ao `JSON.parse` (inclusive `"etapa_id": null`), então `em_dia?` compara Hash com Hash (ordem das chaves não importa); `update!` em registro novo cria, e em registro igual não grava nada; o stub do spec troca `desenhos` no próprio módulo (chamadas internas de `module_function` vão para o singleton); `Grafo.new(nil)` vira desenho vazio (`gatilho` nil). Colunas do `HOJE` conferidas no `db/schema.rb`: `leads.docs_completos_em`/`contrato_limpo_em` (:1182-1183), `copilot_suggestions.created_at` (:827), `ramon_chegadas.escalado_em` (:1474), `ramon_pecas.publicacao_iniciada_em` (:1573). Linhas < 150; métodos bem abaixo de AbcSize 26.

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/services/ramon/fluxos/sistema_spec.rb` + `bundle exec rubocop app/services/ramon/fluxos/sistema.rb spec/services/ramon/fluxos/sistema_spec.rb` (CI).
Expected: PASS, rubocop sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/sistema.rb spec/services/ramon/fluxos/sistema_spec.rb
git commit -m "feat(fluxos): fluxos do sistema por conta, sincronizados dos desenhos, com Hoje e grupos" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 4: API e motor — a lista traz os do sistema; o motor nunca os roda

**Files:**
- Modify: `app/services/ramon/fluxos/disparo.rb:61-69` (`#iniciar`)
- Modify: `app/controllers/api/v1/accounts/ramon_fluxos_controller.rb:5` (before_action), `:7-16` (`index`, `show`), seção `private` (novo `item`)
- Test: `spec/services/ramon/fluxos/disparo_spec.rb`, `spec/services/ramon/fluxos/relogio_spec.rb`, `spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Fluxos::Sistema.sincronizar(account)` e `.extras(account, chave)` (Task 3).
- Produces: `GET …/ramon_fluxos` → `payload` inclui os 29 fluxos do sistema (`origem: 'sistema'`, `sistema_chave`, `descricao`, `ativo: false`, `versao: nil`, `limite_dia`, `hoje: Integer|nil`, `grupo`, `alcance: String|nil`, `gatilho_rotulo: String|nil`); `resumo` conta **só** os não-sistema. `GET …/ramon_fluxos/:id` de fluxo do sistema traz os mesmos extras. `POST …/:id/ensaio` de fluxo do sistema → 403. `Disparo#iniciar` devolve `nil` para fluxo do sistema (vale para `call`, `manual`, `ensaiar` e `Relogio`). `POST …/:id/rodar` (B1, inalterado): corpo `{lead_id}` ou `{conversation_id}` (= `display_id`), 200 = `FluxoExecucao#resumo_json` (`id`, `fluxo_id`, …), 422 `{erro: 'FLUXO_NAO_RODOU'}`, 403 sistema, 401 não-admin.

- [ ] **Step 1: Write the failing tests**

Em `spec/services/ramon/fluxos/disparo_spec.rb`, depois do exemplo `'modo sombra cria execução de ensaio'`:

```ruby
  it 'fluxo do sistema nunca roda pelo motor, nem ligado e publicado (D7: quem roda é o código)' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' }, nota), origem: 'sistema')
    expect(described_class.call('manual', lead)).to eq([])
    expect(described_class.manual(fluxo, lead)).to be_nil
    expect(described_class.ensaiar(fluxo, lead)).to be_nil
    expect(fluxo.execucoes.count).to eq(0)
  end
```

Em `spec/services/ramon/fluxos/relogio_spec.rb`, depois de `'relógio perdido no minuto exato dispara quando voltar, no mesmo dia'`:

```ruby
  it 'fluxo do sistema com relógio nunca dispara (o resumo do dia é do código)' do
    create(:lead, account: account, lead_stage: etapa)
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'relogio', 'hora' => '08:00', 'etapa_ids' => [etapa.id] }, nota),
                            origem: 'sistema')
    travel_to(sp('2026-10-06 09:00')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.count).to eq(0)
    expect(fluxo.reload.ultimo_disparo_em).to be_nil
  end
```

Em `spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb`:

(a) no exemplo `'cria, edita o rascunho, publica e lista com contadores'` a lista agora traz os do sistema primeiro (`order(:origem, :nome)`: `sistema` < `usuario`) — trocar

```ruby
    expect(response.parsed_body['payload'].first).to include('nome' => 'Pós-contrato', 'gatilho_tipo' => 'manual', 'versao' => 1,
                                                             'ativo' => true, 'hoje' => 0)
```

por

```ruby
    meu = response.parsed_body['payload'].find { |f| f['origem'] == 'usuario' }
    expect(meu).to include('nome' => 'Pós-contrato', 'gatilho_tipo' => 'manual', 'versao' => 1, 'ativo' => true, 'hoje' => 0)
```

(b) substituir o exemplo `'fluxo do sistema é só leitura'` inteiro por:

```ruby
  it 'fluxo do sistema é só leitura: não edita, não publica, não roda e não ensaia' do
    fluxo = fluxo_publicado(account, grafo, origem: 'sistema')
    lead = create(:lead, account: account)
    patch "#{url}/#{fluxo.id}", params: { nome: 'Y' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    post "#{url}/#{fluxo.id}/publicar", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    post "#{url}/#{fluxo.id}/ensaio", params: { lead_id: lead.id }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    post "#{url}/#{fluxo.id}/rodar", params: { lead_id: lead.id }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(fluxo.execucoes.count).to eq(0)
  end

  it 'a lista traz os 29 do sistema com Hoje, grupo e selo; os 4 números contam só os meus' do
    fluxo_publicado(account, grafo)
    get url, headers: admin.create_new_auth_token, as: :json
    sistema = response.parsed_body['payload'].select { |f| f['origem'] == 'sistema' }
    expect(sistema.size).to eq(29)
    avisos = sistema.find { |f| f['sistema_chave'] == 'avisos_painel' }
    expect(avisos).to include('hoje' => nil, 'ativo' => false, 'versao' => nil, 'grupo' => 'painel_cliente',
                              'alcance' => 'fala_com_cliente', 'gatilho_rotulo' => 'Todo dia às 08:00 (só com PORTAL_AVISOS=on)')
    expect(sistema.find { |f| f['sistema_chave'] == 'lead_ganho' }).to include('hoje' => 0, 'alcance' => nil)
    expect(response.parsed_body['resumo']).to include('ligados' => 1, 'total' => 1)

    get "#{url}/#{avisos['id']}", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('alcance' => 'fala_com_cliente', 'origem' => 'sistema')
    expect(response.parsed_body['rascunho']['nos']).to be_present
  end
```

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/disparo_spec.rb spec/services/ramon/fluxos/relogio_spec.rb spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb`
Expected: FAIL — `manual`/`ensaiar` criam execução; ensaio do sistema devolve 200; a lista não traz os do sistema. (O exemplo do relógio já passa hoje — `executaveis` — e fica como trava.)

- [ ] **Step 3: Implementation**

`app/services/ramon/fluxos/disparo.rb` — `#iniciar` ganha a guarda na 1ª linha:

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

`app/controllers/api/v1/accounts/ramon_fluxos_controller.rb`:

```ruby
  before_action :bloquear_sistema, only: [:update, :destroy, :publicar, :rodar, :ensaio]

  def index
    Ramon::Fluxos::Sistema.sincronizar(Current.account)
    payload = Current.account.fluxos.includes(:versao_publicada).order(:origem, :nome).map { |fluxo| item(fluxo) }
    render json: { payload: payload, resumo: resumo(payload.reject { |f| f[:origem] == 'sistema' }) }
  end

  def show
    render json: item(@fluxo).merge(rascunho: @fluxo.rascunho,
                                    versoes: @fluxo.versoes.order(numero: :desc).map { |v| { numero: v.numero, created_at: v.created_at } })
  end
```

e, na seção `private`, logo antes de `def resumo(payload)`:

```ruby
  # Do sistema: Hoje (rastro do código), grupo, selo e rótulo do gatilho real vêm do desenho (Sistema.extras).
  def item(fluxo)
    json = fluxo.resumo_json
    fluxo.origem == 'sistema' ? json.merge(Ramon::Fluxos::Sistema.extras(Current.account, fluxo.sistema_chave)) : json
  end
```

(`ensaio` sem o 403 chamaria `Disparo.ensaiar` → `nil.resumo_json`; o 403 vem antes.)

- [ ] **Step 4: Run to verify they pass** — mesmos 3 arquivos + `bundle exec rubocop app/services/ramon/fluxos/disparo.rb app/controllers/api/v1/accounts/ramon_fluxos_controller.rb` (CI). Expected: PASS, sem ofensas (controller vai de 102 para ~110 linhas).

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/disparo.rb app/controllers/api/v1/accounts/ramon_fluxos_controller.rb spec/services/ramon/fluxos/disparo_spec.rb spec/services/ramon/fluxos/relogio_spec.rb spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb
git commit -m "feat(fluxos): lista traz os fluxos do sistema e o motor nunca os executa" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 5: Front — aba "Do sistema" em grupos + textos + campo `regra`

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/Lista.vue` (arquivo inteiro abaixo)
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js` (`CAMPOS` e 1 comentário)
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`, `app/javascript/dashboard/i18n/locale/en/ramon.json`
- Test: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/Lista.spec.js` (arquivo inteiro abaixo), `…/automacoes/specs/i18n.spec.js` (grupos e selos no "cobre todo o catálogo")

**Interfaces:**
- Consumes: payload da Task 4 (`origem`, `descricao`, `hoje`, `limite_dia`, `gatilho_tipo`, `grupo`, `alcance`, `gatilho_rotulo`); `GRUPOS_SISTEMA`/`ALCANCES` (Task 1); rota `captain_automacoes_editor` (B2).
- Produces: `Lista.vue` lê `route.query.aba === 'sistema'` (usado pela Task 6); `data-testid` `aba-meus`, `aba-sistema`, `sistema-explica`, `sistema-grupo-<grupo>`, `sistema-linha`, `sistema-alcance`; chaves i18n `CAPTAIN_RAMON.FLUXOS.ABA_SISTEMA`, `.SISTEMA.{EXPLICA,SEM_CONTADOR}`, `.SISTEMA.GRUPOS.<grupo>`, `.SISTEMA.ALCANCE.<alcance>` (usada também pela Task 6), `.RODAR.*` (usadas pela Task 7), `.SELO.NO_CODIGO`, `.EDITOR.COMO_RODA` (Task 6), `.CAMPOS.regra`; `CAMPOS` de `fluxo.js` termina em `'regra'`.

- [ ] **Step 1: Write the failing tests**

(a) Substituir `specs/Lista.spec.js` inteiro por:

```js
import { mount, flushPromises } from '@vue/test-utils';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import Lista from '../Lista.vue';

const push = vi.fn();
const rota = { query: {} };
vi.mock('vue-router', () => ({
  useRouter: () => ({ push }),
  useRoute: () => rota,
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
vi.mock('dashboard/api/ramonFluxos', () => ({
  default: { get: vi.fn(), update: vi.fn(), create: vi.fn() },
}));

const FLUXO = {
  id: 1,
  nome: 'Pós-contrato',
  gatilho_tipo: 'lead_mudou_etapa',
  ativo: true,
  limite_dia: 20,
  origem: 'usuario',
  versao: 3,
  editado_em: '2026-10-04T12:00:00Z',
  hoje: 3,
  esperando: 8,
  falharam_24h: 0,
  ultima_em: null,
};
// do sistema (B3): desligado, sem versão, em grupo; "Hoje" vem do código (null = sem contador)
const SISTEMA = {
  ...FLUXO,
  id: 3,
  nome: 'Cadência de retomada',
  descricao:
    'No código: Ramon::DailyFollowUpJob (todo dia às 11:00)\n\nO desenho não consegue mostrar: o teto de 15 por dia',
  gatilho_tipo: 'lead_parado',
  ativo: false,
  limite_dia: 15,
  origem: 'sistema',
  sistema_chave: 'cadencia',
  grupo: 'leads_conversas',
  versao: null,
  hoje: 2,
  esperando: 0,
};

describe('Lista de automações', () => {
  beforeEach(() => {
    rota.query = {};
    RamonFluxosAPI.get.mockResolvedValue({
      data: {
        payload: [
          FLUXO,
          {
            ...FLUXO,
            id: 2,
            nome: 'Rascunho',
            ativo: false,
            versao: null,
            gatilho_tipo: null,
            falharam_24h: 1,
          },
          SISTEMA,
          {
            ...SISTEMA,
            id: 4,
            nome: 'Resumo do dia',
            sistema_chave: 'resumo_do_dia',
            descricao: 'No código: Ramon::DailyDigestJob',
            gatilho_tipo: 'relogio',
            gatilho_rotulo: 'Todo dia às 08:00 (1 vez por conta)',
            grupo: 'rotinas_relatorios',
            limite_dia: null,
            hoje: null,
          },
          {
            ...SISTEMA,
            id: 5,
            nome: 'Avisos do Painel do Cliente',
            sistema_chave: 'avisos_painel',
            descricao:
              'No código: Ramon::PortalAvisosJob — DESLIGADO até o Eduardo aprovar os textos',
            gatilho_tipo: 'relogio',
            grupo: 'painel_cliente',
            alcance: 'fala_com_cliente',
            limite_dia: null,
            hoje: null,
          },
        ],
        resumo: {
          ligados: 1,
          total: 2,
          hoje: 3,
          esperando: 8,
          falharam_24h: 1,
        },
      },
    });
    RamonFluxosAPI.update.mockResolvedValue({ data: {} });
  });

  it('mostra os 4 números e só "Meus fluxos" (sem os do sistema)', async () => {
    const wrapper = mount(Lista);
    await flushPromises();
    expect(wrapper.findAll('[data-testid="fluxo-linha"]')).toHaveLength(2);
    expect(wrapper.find('[data-testid="fluxos-resumo"]').text()).toContain('1');
    expect(wrapper.text()).toContain('3 / 20');
    expect(wrapper.text()).toContain('1 failed');
    expect(wrapper.find('[data-testid="sistema-linha"]').exists()).toBe(false);
  });

  it('clicar na linha abre o editor', async () => {
    const wrapper = mount(Lista);
    await flushPromises();
    await wrapper.find('[data-testid="fluxo-linha"]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'captain_automacoes_editor',
      params: { fluxoId: 1 },
    });
  });

  it('a chave liga/desliga sem abrir o editor', async () => {
    const wrapper = mount(Lista);
    await flushPromises();
    await wrapper
      .find('[data-testid="fluxo-linha"] [role="switch"]')
      .trigger('click');
    expect(RamonFluxosAPI.update).toHaveBeenCalledWith(1, { ativo: false });
    expect(push).not.toHaveBeenCalled();
  });

  it('fluxo nunca publicado: chave desabilitada; erro ao ligar avisa e recarrega', async () => {
    const wrapper = mount(Lista);
    await flushPromises();
    const [publicado, rascunho] = wrapper.findAll(
      '[data-testid="fluxo-linha"] [role="switch"]'
    );
    expect(rascunho.attributes('disabled')).toBeDefined();
    RamonFluxosAPI.update.mockRejectedValueOnce(new Error('422'));
    RamonFluxosAPI.get.mockClear();
    await publicado.trigger('click');
    await flushPromises();
    expect(RamonFluxosAPI.get).toHaveBeenCalled();
  });

  it('aba Do sistema: explica, só os do sistema, sem chave nem números; "—" sem contador; clicar abre o desenho', async () => {
    const wrapper = mount(Lista);
    await flushPromises();
    await wrapper.find('[data-testid="aba-sistema"]').trigger('click');
    expect(wrapper.find('[data-testid="sistema-explica"]').exists()).toBe(true);
    const linhas = wrapper.findAll('[data-testid="sistema-linha"]');
    expect(linhas).toHaveLength(3);
    expect(linhas[0].text()).toContain(
      'No código: Ramon::DailyFollowUpJob (todo dia às 11:00)'
    );
    expect(linhas[0].text()).not.toContain('O desenho não consegue');
    expect(linhas[0].text()).toContain('2 / 15');
    expect(linhas[2].text()).toContain('—');
    expect(linhas[2].text()).toContain('Todo dia às 08:00 (1 vez por conta)');
    expect(wrapper.find('[role="switch"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="fluxos-resumo"]').exists()).toBe(false);
    await linhas[0].trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'captain_automacoes_editor',
      params: { fluxoId: 3 },
    });
  });

  it('Do sistema em grupos, na ordem da tela; selo em quem fala com o cliente', async () => {
    rota.query = { aba: 'sistema' };
    const wrapper = mount(Lista);
    await flushPromises();
    const grupos = wrapper
      .findAll('[data-testid^="sistema-grupo-"]')
      .map(g => g.attributes('data-testid'));
    expect(grupos).toEqual([
      'sistema-grupo-leads_conversas',
      'sistema-grupo-painel_cliente',
      'sistema-grupo-rotinas_relatorios',
    ]);
    const selos = wrapper.findAll('[data-testid="sistema-alcance"]');
    expect(selos).toHaveLength(1);
    expect(selos[0].text()).toContain('talks to the client');
    expect(
      wrapper.find('[data-testid="sistema-grupo-painel_cliente"]').text()
    ).toContain('Avisos do Painel do Cliente');
  });

  it('?aba=sistema (volta do desenho do sistema) abre direto na aba Do sistema', async () => {
    rota.query = { aba: 'sistema' };
    const wrapper = mount(Lista);
    await flushPromises();
    expect(wrapper.findAll('[data-testid="sistema-linha"]')).toHaveLength(3);
    expect(wrapper.find('[data-testid="fluxo-linha"]').exists()).toBe(false);
  });
});
```

(b) Em `specs/i18n.spec.js`: no `import { … } from '../fluxo';` acrescentar `ALCANCES,` (depois de `ACOES_CHATWOOT,`) e `GRUPOS_SISTEMA,` (depois de `GATILHOS,`); no `it('cobre todo o catálogo', …)`, logo depois de `PAPEIS.forEach(p => expect(FLUXOS_PT.PAPEIS[p]).toBeTruthy());`:

```js
    GRUPOS_SISTEMA.forEach(g =>
      expect(FLUXOS_PT.SISTEMA.GRUPOS[g]).toBeTruthy()
    );
    ALCANCES.forEach(a => expect(FLUXOS_PT.SISTEMA.ALCANCE[a]).toBeTruthy());
```

- [ ] **Step 2: Run to verify it fails**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/Lista.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/i18n.spec.js --config vitest.local.config.ts`
Expected: FAIL — os 3 testes novos da Lista (não há `aba-sistema`) e o catálogo (`SISTEMA` indefinido).

- [ ] **Step 3: Implementation**

(a) `Lista.vue` — substituir o arquivo inteiro por:

```vue
<script setup>
// Automações (mockup tela 1). Aba "Meus fluxos": 4 números, a lista com
// liga/desliga e o que rodou hoje. Aba "Do sistema" (B3, spec §7/§8): o
// desenho só-leitura das 29 automações que ainda rodam no código, em grupos —
// sem chave liga/desliga, selo em quem sai para fora sem uma pessoa no meio e
// "Hoje" só onde o código tem contador barato (senão "—").
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import {
  ABA,
  ABA_ATIVA,
  ABA_INATIVA,
  AVISO,
  CHIP,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { GRUPOS_SISTEMA, gatilhoInfo } from './fluxo';
import NovoFluxo from './NovoFluxo.vue';

defineOptions({ name: 'CaptainAutomacoes' });

const K = 'CAPTAIN_RAMON.FLUXOS';
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const fluxos = ref([]);
const resumo = ref({});
const erro = ref(false);
const novo = ref(false);
const criando = ref(false);
// ?aba=sistema: o "Voltar" do desenho do sistema cai de novo nesta aba
const aba = ref(route.query.aba === 'sistema' ? 'sistema' : 'meus');
const meus = computed(() => fluxos.value.filter(f => f.origem !== 'sistema'));
const doSistema = computed(() =>
  fluxos.value.filter(f => f.origem === 'sistema')
);
// "Do sistema" em grupos (GRUPOS_SISTEMA = ordem da tela); grupo vazio não aparece
const gruposSistema = computed(() =>
  GRUPOS_SISTEMA.map(chave => ({
    chave,
    fluxos: doSistema.value.filter(f => f.grupo === chave),
  })).filter(g => g.fluxos.length)
);

const carregar = async () => {
  erro.value = false;
  try {
    const { data } = await RamonFluxosAPI.get();
    fluxos.value = data.payload;
    resumo.value = data.resumo;
  } catch (e) {
    erro.value = true;
  }
};
onMounted(carregar);

const abrir = id =>
  router.push(accountScopedRoute('captain_automacoes_editor', { fluxoId: id }));

const ligar = async (fluxo, ativo) => {
  try {
    await RamonFluxosAPI.update(fluxo.id, { ativo });
  } catch (e) {
    useAlert(t(`${K}.EDITOR.ERRO_SALVAR`));
  } finally {
    carregar();
  }
};

// clique duplo no modelo não cria dois fluxos
const criar = async modelo => {
  if (criando.value) return;
  criando.value = true;
  try {
    const { data } = await RamonFluxosAPI.create({
      nome: t(`${K}.MODELOS.${modelo.chave}.NOME`),
      limite_dia: modelo.limite_dia ?? null,
      rascunho: modelo.desenho,
    });
    abrir(data.id);
  } catch (e) {
    useAlert(t(`${K}.ERRO_CRIAR`));
  } finally {
    criando.value = false;
  }
};

const TRACO = '—';
const selo = f => {
  if (f.falharam_24h)
    return {
      classe: TOM.ruby,
      icone: 'i-lucide-triangle-alert',
      texto: t(`${K}.SELO.FALHOU`, { n: f.falharam_24h }),
    };
  if (!f.ativo)
    return { classe: TOM.slate, icone: '', texto: t(`${K}.SELO.DESLIGADO`) };
  return { classe: TOM.teal, icone: '', texto: t(`${K}.SELO.OK`) };
};
const subtitulo = f =>
  f.versao
    ? t(`${K}.VERSAO_EDITADO`, {
        versao: f.versao,
        data: new Date(f.editado_em).toLocaleDateString('pt-BR'),
      })
    : t(`${K}.NUNCA_PUBLICADO`);
const hojeLimite = f => `${f.hoje} / ${f.limite_dia ?? TRACO}`;
const largura = f =>
  `${Math.min(100, Math.round((f.hoje / f.limite_dia) * 100))}%`;
const ultima = iso =>
  iso ? dynamicTime(Math.floor(new Date(iso).getTime() / 1000)) : TRACO;
const gatilho = tipo => (tipo ? t(`${K}.GATILHOS.${tipo}`) : TRACO);
// do sistema: sem contador barato o back manda hoje = null
const hojeSistema = f => {
  if (f.hoje == null) return TRACO;
  return f.limite_dia ? `${f.hoje} / ${f.limite_dia}` : String(f.hoje);
};
// 1ª linha da descrição = onde vive no código (o resto aparece no desenho)
const ondeVive = f => (f.descricao || '').split('\n')[0];
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <div
      class="flex h-14 shrink-0 items-center gap-2.5 border-b border-n-weak px-7"
    >
      <h1 class="text-[15px] font-semibold text-n-slate-12">
        {{ t(`${K}.TITULO`) }}
      </h1>
      <span class="hidden text-[13px] text-n-slate-10 md:inline">
        {{ t(`${K}.DICA`) }}
      </span>
      <Button
        class="ml-auto"
        sm
        icon="i-lucide-plus"
        :label="t(`${K}.NOVO`)"
        @click="novo = true"
      />
    </div>
    <div class="flex gap-1 border-b border-n-weak px-7 pt-3">
      <button
        type="button"
        data-testid="aba-meus"
        :class="[ABA, aba === 'meus' ? ABA_ATIVA : ABA_INATIVA]"
        @click="aba = 'meus'"
      >
        {{ t(`${K}.ABA_MEUS`) }}
        <span class="font-mono text-[11.5px] text-n-slate-10">
          {{ meus.length }}
        </span>
      </button>
      <button
        type="button"
        data-testid="aba-sistema"
        :class="[ABA, aba === 'sistema' ? ABA_ATIVA : ABA_INATIVA]"
        @click="aba = 'sistema'"
      >
        {{ t(`${K}.ABA_SISTEMA`) }}
        <span class="font-mono text-[11.5px] text-n-slate-10">
          {{ doSistema.length }}
        </span>
      </button>
    </div>

    <div class="flex-1 overflow-y-auto px-7 pb-12 pt-5">
      <div v-if="erro" class="text-sm text-n-ruby-11">
        {{ t('CAPTAIN_RAMON.LOAD_ERROR') }}
        <button
          type="button"
          class="ml-1 text-n-blue-11 hover:underline"
          @click="carregar"
        >
          {{ t('CAPTAIN_RAMON.RETRY') }}
        </button>
      </div>

      <template v-else-if="aba === 'meus'">
        <div
          data-testid="fluxos-resumo"
          class="mb-5 grid max-w-[1100px] grid-cols-2 gap-3 md:grid-cols-4"
        >
          <div class="rounded-xl border border-n-weak px-3.5 py-3">
            <span class="block text-xs text-n-slate-10">
              {{ t(`${K}.RESUMO.LIGADOS`) }}
            </span>
            <b class="font-mono text-xl font-medium text-n-slate-12">
              {{ resumo.ligados ?? 0 }}
              <small class="text-xs font-normal text-n-slate-10">
                {{ t(`${K}.RESUMO.DE`, { total: meus.length }) }}
              </small>
            </b>
          </div>
          <div class="rounded-xl border border-n-weak px-3.5 py-3">
            <span class="block text-xs text-n-slate-10">
              {{ t(`${K}.RESUMO.HOJE`) }}
            </span>
            <b class="font-mono text-xl font-medium text-n-slate-12">
              {{ resumo.hoje ?? 0 }}
            </b>
          </div>
          <div class="rounded-xl border border-n-weak px-3.5 py-3">
            <span class="block text-xs text-n-slate-10">
              {{ t(`${K}.RESUMO.ESPERANDO`) }}
            </span>
            <b class="font-mono text-xl font-medium text-n-slate-12">
              {{ resumo.esperando ?? 0 }}
            </b>
          </div>
          <div class="rounded-xl border border-n-weak px-3.5 py-3">
            <span class="block text-xs text-n-slate-10">
              {{ t(`${K}.RESUMO.FALHARAM`) }}
            </span>
            <b
              class="font-mono text-xl font-medium"
              :class="
                resumo.falharam_24h ? 'text-n-ruby-11' : 'text-n-slate-12'
              "
            >
              {{ resumo.falharam_24h ?? 0 }}
            </b>
          </div>
        </div>

        <p v-if="!meus.length" class="text-sm text-n-slate-10">
          {{ t(`${K}.VAZIO`) }}
        </p>

        <table v-else class="w-full max-w-[1100px] border-collapse">
          <thead>
            <tr
              class="border-b border-n-weak text-left text-xs font-medium text-n-slate-10"
            >
              <th class="w-11 p-2" />
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.FLUXO`) }}</th>
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.GATILHO`) }}</th>
              <th class="p-2 font-medium">
                {{ t(`${K}.TABELA.HOJE_LIMITE`) }}
              </th>
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.ESPERANDO`) }}</th>
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.ULTIMA`) }}</th>
              <th class="p-2" />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="f in meus"
              :key="f.id"
              data-testid="fluxo-linha"
              class="cursor-pointer border-b border-n-weak text-[13.5px] hover:bg-n-alpha-2"
              @click="abrir(f.id)"
            >
              <td class="p-2" @click.stop>
                <span
                  :title="f.versao ? '' : t(`${K}.PUBLIQUE_ANTES`)"
                  :class="f.versao ? '' : 'opacity-50'"
                >
                  <Switch
                    :disabled="!f.versao"
                    :model-value="f.ativo"
                    @update:model-value="v => ligar(f, v)"
                  />
                </span>
              </td>
              <td class="p-2">
                <b class="block font-medium text-n-slate-12">{{ f.nome }}</b>
                <span class="text-[12.5px] text-n-slate-11">
                  {{ subtitulo(f) }}
                </span>
              </td>
              <td class="p-2">
                <span
                  class="inline-flex items-center gap-1.5 text-[12.5px] text-n-slate-11"
                >
                  <i
                    v-if="f.gatilho_tipo"
                    :class="gatilhoInfo(f.gatilho_tipo)?.icone"
                    class="size-3.5 text-n-blue-11"
                  />
                  {{ gatilho(f.gatilho_tipo) }}
                </span>
              </td>
              <td class="p-2 font-mono text-[12.5px]">
                {{ hojeLimite(f) }}
                <span
                  v-if="f.limite_dia"
                  class="ml-1.5 inline-block h-[5px] w-14 overflow-hidden rounded-full bg-n-alpha-2 align-middle"
                >
                  <i
                    class="block h-full bg-n-blue-9"
                    :style="{ width: largura(f) }"
                  />
                </span>
              </td>
              <td class="p-2 font-mono text-[12.5px]">{{ f.esperando }}</td>
              <td class="p-2 font-mono text-[12.5px]">
                {{ ultima(f.ultima_em) }}
              </td>
              <td class="p-2">
                <span :class="[CHIP, selo(f).classe]" class="font-mono">
                  <i
                    v-if="selo(f).icone"
                    :class="selo(f).icone"
                    class="size-3"
                  />
                  {{ selo(f).texto }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </template>

      <template v-else>
        <p
          data-testid="sistema-explica"
          :class="[AVISO, TOM.blue]"
          class="mb-5 max-w-[1100px] leading-relaxed"
        >
          {{ t(`${K}.SISTEMA.EXPLICA`) }}
        </p>
        <table class="w-full max-w-[1100px] border-collapse">
          <thead>
            <tr
              class="border-b border-n-weak text-left text-xs font-medium text-n-slate-10"
            >
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.FLUXO`) }}</th>
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.GATILHO`) }}</th>
              <th class="p-2 font-medium">
                {{ t(`${K}.TABELA.HOJE_LIMITE`) }}
              </th>
              <th class="p-2" />
            </tr>
          </thead>
          <tbody
            v-for="g in gruposSistema"
            :key="g.chave"
            :data-testid="`sistema-grupo-${g.chave}`"
          >
            <tr>
              <td
                colspan="4"
                class="px-2 pb-1.5 pt-5 text-[11px] font-medium uppercase tracking-wider text-n-slate-10"
              >
                {{ t(`${K}.SISTEMA.GRUPOS.${g.chave}`) }}
              </td>
            </tr>
            <tr
              v-for="f in g.fluxos"
              :key="f.id"
              data-testid="sistema-linha"
              class="cursor-pointer border-b border-n-weak text-[13.5px] hover:bg-n-alpha-2"
              @click="abrir(f.id)"
            >
              <td class="p-2">
                <b class="font-medium text-n-slate-12">{{ f.nome }}</b>
                <span
                  v-if="f.alcance"
                  data-testid="sistema-alcance"
                  :class="[CHIP, TOM.amber]"
                  class="ml-2 font-mono"
                >
                  <i class="i-lucide-triangle-alert size-3" />
                  {{ t(`${K}.SISTEMA.ALCANCE.${f.alcance}`) }}
                </span>
                <span class="block text-[12.5px] text-n-slate-11">
                  {{ ondeVive(f) }}
                </span>
              </td>
              <td class="p-2">
                <span
                  class="inline-flex items-center gap-1.5 text-[12.5px] text-n-slate-11"
                >
                  <i
                    v-if="f.gatilho_tipo"
                    :class="gatilhoInfo(f.gatilho_tipo)?.icone"
                    class="size-3.5 text-n-blue-11"
                  />
                  {{ f.gatilho_rotulo || gatilho(f.gatilho_tipo) }}
                </span>
              </td>
              <td
                class="p-2 font-mono text-[12.5px]"
                :title="f.hoje == null ? t(`${K}.SISTEMA.SEM_CONTADOR`) : ''"
              >
                {{ hojeSistema(f) }}
              </td>
              <td class="p-2">
                <span :class="[CHIP, TOM.blue]" class="font-mono">
                  {{ t(`${K}.SELO.NO_CODIGO`) }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>

    <NovoFluxo
      v-if="novo"
      :ocupado="criando"
      @criar="criar"
      @fechar="novo = false"
    />
  </section>
</template>
```

(b) `fluxo.js` — em `CAMPOS`, acrescentar `'regra'` depois de `'documentos_completos'` (o `escolha` do desenho do ADVBOX olha esse campo; vale também para fluxos do usuário com gatilho `evento_advbox`):

```js
  'documentos_completos',
  'regra',
];
export const OPERADORES = [
```

e trocar o comentário acima de `CHATWOOT_PERMITIDAS`

```js
// = Grafo.permitidas_chatwoot (inclui as que vêm de regras convertidas na B3)
```

por

```js
// = Grafo.permitidas_chatwoot (o que a regra nativa aceita, menos as proibidas)
```

(c) `pt_BR/ramon.json` — inserções com Edit (dentro de `CAPTAIN_RAMON.FLUXOS`):

- depois de `      "ABA_MEUS": "Meus fluxos",` → `      "ABA_SISTEMA": "Do sistema",`
- depois de `      "ERRO_CRIAR": "Não consegui criar o fluxo.",` →

```json
      "SISTEMA": {
        "EXPLICA": "Estas automações rodam hoje pelo código do hub, não pelo quadro. Aqui você vê o desenho de cada uma, só para leitura, para conferir o que o hub faz sozinho. Elas vão virar fluxos editáveis uma a uma: primeiro rodam lado a lado em modo ensaio, comparamos com o código e, se baterem, o fluxo assume.",
        "SEM_CONTADOR": "Sem contador barato para hoje",
        "GRUPOS": {
          "leads_conversas": "Leads e conversas",
          "contrato_documentos": "Contrato e documentos",
          "painel_cliente": "Painel do Cliente",
          "rotinas_relatorios": "Rotinas e relatórios",
          "instagram": "Instagram"
        },
        "ALCANCE": {
          "fala_com_cliente": "fala com o cliente",
          "publica": "publica"
        }
      },
      "RODAR": {
        "ITEM": "Rodar fluxo…",
        "TITULO": "Rodar fluxo",
        "AJUDA": "Fluxos publicados e ligados com o gatilho Rodar na mão. Mensagem ao cliente sai como rascunho.",
        "CARREGANDO": "Carregando…",
        "VAZIO": "Nenhum fluxo de Rodar na mão publicado e ligado.",
        "IR_AUTOMACOES": "Abrir Automações",
        "RODOU": "Fluxo {nome} rodando.",
        "VER_EXECUCAO": "Ver execução",
        "NAO_RODOU": "O fluxo não rodou: está desligado, sem versão publicada, no limite do dia ou já rodando aqui.",
        "ERRO": "Não consegui rodar o fluxo. Tente de novo.",
        "ERRO_LISTA": "Não consegui carregar os fluxos."
      },
```

- em `SELO`: `"DESLIGADO": "desligado"` → com vírgula + nova linha `        "NO_CODIGO": "roda no código"`
- em `EDITOR`: `"SELECIONE": "Clique num passo para configurar."` → com vírgula + nova linha `        "COMO_RODA": "Como roda hoje"`
- em `CAMPOS`: `"documentos_completos": "Documentos completos (sim ou não)"` → com vírgula + nova linha `        "regra": "Regra do ADVBOX (evento)"`

(d) `en/ramon.json` — as mesmas inserções, nas mesmas posições:

- depois de `      "ABA_MEUS": "My flows",` → `      "ABA_SISTEMA": "Built-in",`
- depois de `      "ERRO_CRIAR": "Could not create the flow.",` →

```json
      "SISTEMA": {
        "EXPLICA": "These automations run today in the hub code, not on the board. Here you see each one drawn, read-only, so you can check what the hub does on its own. They will become editable flows one by one: first they run side by side as a dry run, we compare them with the code and, if they match, the flow takes over.",
        "SEM_CONTADOR": "No cheap counter for today",
        "GRUPOS": {
          "leads_conversas": "Leads and conversations",
          "contrato_documentos": "Contract and documents",
          "painel_cliente": "Client Portal",
          "rotinas_relatorios": "Routines and reports",
          "instagram": "Instagram"
        },
        "ALCANCE": {
          "fala_com_cliente": "talks to the client",
          "publica": "publishes"
        }
      },
      "RODAR": {
        "ITEM": "Run flow…",
        "TITULO": "Run flow",
        "AJUDA": "Published, enabled flows with the Run by hand trigger. Messages to the client are drafts.",
        "CARREGANDO": "Loading…",
        "VAZIO": "No published, enabled Run by hand flow.",
        "IR_AUTOMACOES": "Open Automations",
        "RODOU": "Flow {nome} running.",
        "VER_EXECUCAO": "See run",
        "NAO_RODOU": "The flow did not run: it is off, unpublished, at its daily limit or already running here.",
        "ERRO": "Could not run the flow. Try again.",
        "ERRO_LISTA": "Could not load the flows."
      },
```

- em `SELO`: `"DESLIGADO": "off"` → com vírgula + `        "NO_CODIGO": "runs in code"`
- em `EDITOR`: `"SELECIONE": "Click a step to configure it."` → com vírgula + `        "COMO_RODA": "How it runs today"`
- em `CAMPOS`: `"documentos_completos": "Documents complete (yes or no)"` → com vírgula + `        "regra": "ADVBOX rule (event)"`

- [ ] **Step 4: Run to verify it passes**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts`
Expected: PASS — 12 arquivos, 149 testes (146 + 3 novos da Lista), inclusive `i18n.spec.js`.
Depois: `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes/Lista.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/Lista.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/i18n.spec.js` → sem `error`.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/Lista.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/Lista.spec.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/i18n.spec.js app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/i18n/locale/en/ramon.json
git commit -m "feat(fluxos): aba Do sistema em grupos na lista de automações" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 6: Front — o desenho do sistema mostra "Como roda hoje" e o selo

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/Editor.vue` (4 trechos do template; o `<script>` não muda)

**Interfaces:**
- Consumes: `somenteLeitura` (`Editor.vue:113`), `fluxo.descricao` e `fluxo.alcance` (`show` da Task 4), chaves `EDITOR.COMO_RODA` e `SISTEMA.ALCANCE.*` (Task 5), `?aba=sistema` lido pela `Lista.vue` (Task 5).
- Produces: `data-testid="sistema-descricao"` e `data-testid="sistema-alcance"` no desenho do sistema (prints da Task 9). **"Testar com um lead…" já está escondido** para `origem: sistema` (`<Button v-if="!somenteLeitura" … :label="t(\`${K}.EDITOR.TESTAR\`)"`) — conferir que continua assim; não mexer.

- [ ] **Step 1: Voltar cai na aba certa** — trocar

```vue
      <router-link
        :to="accountScopedRoute('captain_automacoes_index')"
```

por

```vue
      <router-link
        :to="
          accountScopedRoute(
            'captain_automacoes_index',
            {},
            somenteLeitura ? { aba: 'sistema' } : {}
          )
        "
```

- [ ] **Step 2: Selo de alcance** — logo **depois** do par de selos existente (o `<span v-if="somenteLeitura" …>SOMENTE_LEITURA</span>` e o `<span v-else …>{{ salvando ? … : seloRascunho }}</span>`; inserir entre os dois quebraria o `v-else`), inserir:

```vue
        <span
          v-if="somenteLeitura && fluxo.alcance"
          data-testid="sistema-alcance"
          :class="[CHIP, TOM.amber]"
          class="font-mono"
        >
          <i class="i-lucide-triangle-alert size-3" />
          {{ t(`${K}.SISTEMA.ALCANCE.${fluxo.alcance}`) }}
        </span>
```

- [ ] **Step 3: Sem "Versões" no desenho do sistema** (nunca há versão) — trocar

```vue
          <div ref="versoesRef" class="relative">
```

por

```vue
          <div v-if="!somenteLeitura" ref="versoesRef" class="relative">
```

- [ ] **Step 4: Painel "Como roda hoje"** — no `<aside>`, entre o `<PainelPasso … />` e `<div v-else class="flex min-h-0 flex-1 flex-col px-4 py-3.5">`, inserir:

```vue
        <div
          v-else-if="somenteLeitura"
          data-testid="sistema-descricao"
          class="flex min-h-0 flex-1 flex-col overflow-y-auto px-4 py-3.5"
        >
          <h4
            class="mb-2 text-[11px] font-medium uppercase tracking-wider text-n-slate-10"
          >
            {{ t(`${K}.EDITOR.COMO_RODA`) }}
          </h4>
          <p
            class="whitespace-pre-line text-[13px] leading-relaxed text-n-slate-11"
          >
            {{ fluxo.descricao }}
          </p>
        </div>
```

(o fluxo do sistema não seleciona passo — `@selecionar` já põe `null` quando `somenteLeitura` —, então este bloco sempre aparece no lugar de "Clique num passo" + execuções vazias; enquanto `fluxo` é `null`, `somenteLeitura` é `false` e nada disso monta.)

- [ ] **Step 5: Run** — `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes/Editor.vue` → sem `error`; `grep -n "EDITOR.TESTAR" -B 6 app/javascript/dashboard/routes/dashboard/captain/automacoes/Editor.vue` mostra `v-if="!somenteLeitura"`; `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts` → 12 arquivos / 149 testes (o Editor não tem spec próprio — a prova visual é o print da Task 9).

- [ ] **Step 6: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/Editor.vue
git commit -m "feat(fluxos): desenho do sistema mostra como roda hoje, o selo e volta para a aba" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 7: "Rodar fluxo…" no ⋯ do painel do lead e da conversa

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/captain/automacoes/RodarFluxo.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadPanelBody.vue` (import, 6 linhas de estado perto de `menuAberto` `:651`, 1 botão no menu ⋯ `:768-795`, o modal depois do bloco de identidade)
- Modify: `app/javascript/dashboard/components/widgets/conversation/MoreActions.vue` (upstream; FORK mínimo)
- Test: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/RodarFluxo.spec.js` (novo), `app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadPanelBody.spec.js` (1 exemplo)

**Interfaces:**
- Consumes: `RamonFluxosAPI.get()` (lista, admin-only) e `RamonFluxosAPI.rodar(id, alvo)` (`app/javascript/dashboard/api/ramonFluxos.js`; contrato na Task 4); rota `captain_automacoes_execucao` (`{ fluxoId, execId }`) e `captain_automacoes_index`; `useAlert(msg, { type: 'link', to, message })` (o `Snackbar.vue` renderiza `router-link` com `to`); `isAdmin` já existente em `LeadPanelBody.vue:610` (`getCurrentRole === 'administrator'`); `useAdmin()` de `dashboard/composables/useAdmin` no `MoreActions.vue`; chaves `CAPTAIN_RAMON.FLUXOS.RODAR.*` (Task 5).
- Produces: `<RodarFluxo :alvo="{ lead_id } | { conversation_id }" @fechar />` — lista só fluxos com `origem !== 'sistema'`, `gatilho_tipo === 'manual'`, `ativo` e `versao`; rodou → toast com link para a execução e fecha; `FLUXO_NAO_RODOU` → explica e não fecha; sem fluxo → estado vazio com link para Automações. `data-testid`: `rodar-fluxo`, `rodar-fluxo-item`, `rodar-vazio`, `lead-rodar-fluxo`.

Por que só admin: a API de fluxos inteira é admin-only (`RamonFluxoPolicy#gerenciar?` = `@account_user.administrator?`); um agente receberia 401 ao abrir a lista. O item nem aparece para quem não é admin.

- [ ] **Step 1: Write the failing tests**

(a) `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/RodarFluxo.spec.js`:

```js
import { mount, flushPromises, RouterLinkStub } from '@vue/test-utils';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import { useAlert } from 'dashboard/composables';
import RodarFluxo from '../RodarFluxo.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
vi.mock('dashboard/api/ramonFluxos', () => ({
  default: { get: vi.fn(), rodar: vi.fn() },
}));

const MANUAL = {
  id: 7,
  nome: 'Pedir documentos',
  gatilho_tipo: 'manual',
  ativo: true,
  versao: 2,
  origem: 'usuario',
};
const montar = (alvo = { lead_id: 31 }) =>
  mount(RodarFluxo, {
    props: { alvo },
    global: { stubs: { teleport: true, RouterLink: RouterLinkStub } },
  });

describe('Rodar fluxo…', () => {
  beforeEach(() => {
    RamonFluxosAPI.get.mockResolvedValue({
      data: {
        payload: [
          MANUAL,
          { ...MANUAL, id: 8, nome: 'Desligado', ativo: false },
          { ...MANUAL, id: 9, nome: 'Nunca publicado', versao: null },
          {
            ...MANUAL,
            id: 10,
            nome: 'Outro gatilho',
            gatilho_tipo: 'lead_ganho',
          },
          { ...MANUAL, id: 11, nome: 'Do sistema', origem: 'sistema' },
        ],
      },
    });
  });

  it('lista só os manuais publicados e ligados; rodar avisa com link para a execução', async () => {
    RamonFluxosAPI.rodar.mockResolvedValue({ data: { id: 412 } });
    const wrapper = montar({ conversation_id: 1802 });
    await flushPromises();
    const itens = wrapper.findAll('[data-testid="rodar-fluxo-item"]');
    expect(itens.map(i => i.text())).toEqual(['Pedir documentos']);
    await itens[0].trigger('click');
    await flushPromises();
    expect(RamonFluxosAPI.rodar).toHaveBeenCalledWith(7, {
      conversation_id: 1802,
    });
    expect(useAlert).toHaveBeenCalledWith(expect.any(String), {
      type: 'link',
      to: {
        name: 'captain_automacoes_execucao',
        params: { fluxoId: 7, execId: 412 },
      },
      message: expect.any(String),
    });
    expect(wrapper.emitted('fechar')).toHaveLength(1);
  });

  it('sem fluxo manual: estado vazio com link para Automações', async () => {
    RamonFluxosAPI.get.mockResolvedValue({ data: { payload: [] } });
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-testid="rodar-vazio"]').exists()).toBe(true);
    expect(wrapper.findComponent(RouterLinkStub).props('to')).toEqual({
      name: 'captain_automacoes_index',
      params: undefined,
    });
  });

  it('fluxo que não rodou (limite, já rodando…) explica e não fecha', async () => {
    RamonFluxosAPI.rodar.mockRejectedValue({
      response: { data: { erro: 'FLUXO_NAO_RODOU' } },
    });
    const wrapper = montar();
    await flushPromises();
    await wrapper.find('[data-testid="rodar-fluxo-item"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('did not run');
    expect(wrapper.emitted('fechar')).toBeUndefined();
    expect(useAlert).not.toHaveBeenCalled();
  });
});
```

(b) `app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadPanelBody.spec.js` — depois de `import ConfirmModal from '../../ConfirmModal.vue';`:

```js
import RodarFluxo from 'dashboard/routes/dashboard/captain/automacoes/RodarFluxo.vue';
```

e, no mesmo `describe` dos exemplos do menu ⋯, logo antes de `it('seções nativas da conversa ficam recolhidas atrás de "Mais da conversa"', …`:

```js
    it('"Rodar fluxo…" no menu ⋯ só para admin, com o lead como alvo', async () => {
      const agente = mountBody();
      await agente.find('[data-testid="lead-more"]').trigger('click');
      expect(agente.find('[data-testid="lead-rodar-fluxo"]').exists()).toBe(
        false
      );

      const admin = mountBody({ spies: { role: 'administrator' } });
      await admin.find('[data-testid="lead-more"]').trigger('click');
      await admin.find('[data-testid="lead-rodar-fluxo"]').trigger('click');
      expect(admin.find('[data-testid="lead-rodar-fluxo"]').exists()).toBe(
        false
      );
      expect(admin.findComponent(RodarFluxo).props('alvo')).toEqual({
        lead_id: 7,
      });
    });
```

(o `mountBody` usa `shallowMount` e o `build` aceita `role`; o lead do spec tem `id: 7`.)

- [ ] **Step 2: Run to verify they fail**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/RodarFluxo.spec.js app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadPanelBody.spec.js --config vitest.local.config.ts`
Expected: FAIL — `RodarFluxo.vue` não existe.

- [ ] **Step 3: Implementation**

(a) `app/javascript/dashboard/routes/dashboard/captain/automacoes/RodarFluxo.vue`:

```vue
<script setup>
// "Rodar fluxo…" (spec §7): lista os fluxos publicados e ligados com gatilho
// manual e roda o escolhido neste lead/conversa pela API da B1
// (POST ramon_fluxos/:id/rodar). Só admin (RamonFluxoPolicy): quem abre este
// modal já esconde o item de menu para quem não é admin.
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onKeyStroke } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import {
  AVISO,
  FUNDO_JANELA,
  JANELA,
  LINHA,
  TITULO_JANELA,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

const props = defineProps({
  // o mesmo corpo do POST …/rodar: { lead_id } | { conversation_id } (display_id)
  alvo: { type: Object, required: true },
});
const emit = defineEmits(['fechar']);
const K = 'CAPTAIN_RAMON.FLUXOS.RODAR';
const { t } = useI18n();
const { accountScopedRoute } = useAccount();
onKeyStroke('Escape', () => emit('fechar'));

const fluxos = ref(null); // null = carregando
const rodando = ref(null);
const erro = ref('');

onMounted(async () => {
  try {
    const { data } = await RamonFluxosAPI.get();
    fluxos.value = data.payload.filter(
      f =>
        f.origem !== 'sistema' &&
        f.gatilho_tipo === 'manual' &&
        f.ativo &&
        f.versao
    );
  } catch (e) {
    fluxos.value = [];
    erro.value = t(`${K}.ERRO_LISTA`);
  }
});

// clique duplo não roda duas vezes
const rodar = async fluxo => {
  if (rodando.value) return;
  rodando.value = fluxo.id;
  erro.value = '';
  try {
    const { data } = await RamonFluxosAPI.rodar(fluxo.id, props.alvo);
    useAlert(t(`${K}.RODOU`, { nome: fluxo.nome }), {
      type: 'link',
      to: accountScopedRoute('captain_automacoes_execucao', {
        fluxoId: fluxo.id,
        execId: data.id,
      }),
      message: t(`${K}.VER_EXECUCAO`),
    });
    emit('fechar');
  } catch (e) {
    erro.value =
      e.response?.data?.erro === 'FLUXO_NAO_RODOU'
        ? t(`${K}.NAO_RODOU`)
        : t(`${K}.ERRO`);
  } finally {
    rodando.value = null;
  }
};
</script>

<template>
  <Teleport to="body">
    <div :class="FUNDO_JANELA" @click.self="emit('fechar')">
      <div :class="JANELA" class="!w-[420px]" data-testid="rodar-fluxo">
        <h2 :class="TITULO_JANELA">{{ t(`${K}.TITULO`) }}</h2>
        <p class="mb-3 text-xs text-n-slate-10">{{ t(`${K}.AJUDA`) }}</p>
        <p v-if="erro" :class="[AVISO, TOM.ruby]" class="mb-3">{{ erro }}</p>

        <p v-if="fluxos === null" class="text-sm text-n-slate-10">
          {{ t(`${K}.CARREGANDO`) }}
        </p>
        <div
          v-else-if="!fluxos.length"
          data-testid="rodar-vazio"
          class="text-sm text-n-slate-11"
        >
          <p class="mb-2">{{ t(`${K}.VAZIO`) }}</p>
          <router-link
            :to="accountScopedRoute('captain_automacoes_index')"
            class="text-n-blue-11 hover:underline"
            @click="emit('fechar')"
          >
            {{ t(`${K}.IR_AUTOMACOES`) }}
          </router-link>
        </div>
        <div v-else class="flex flex-col gap-0.5">
          <button
            v-for="f in fluxos"
            :key="f.id"
            type="button"
            data-testid="rodar-fluxo-item"
            :class="LINHA"
            class="flex items-center gap-2"
            :disabled="rodando !== null"
            @click="rodar(f)"
          >
            <i class="i-lucide-hand size-4 shrink-0 text-n-blue-11" />
            <span class="min-w-0 flex-1 truncate">{{ f.nome }}</span>
            <i
              v-if="rodando === f.id"
              class="i-lucide-loader-circle size-4 animate-spin"
            />
          </button>
        </div>

        <div class="mt-4 flex justify-end">
          <Button
            ghost
            slate
            sm
            :label="t('CAPTAIN_RAMON.FLUXOS.FECHAR')"
            @click="emit('fechar')"
          />
        </div>
      </div>
    </div>
  </Teleport>
</template>
```

(b) `LeadPanelBody.vue`:

- depois de `import LeadsAPI from 'dashboard/api/leads';`:

```js
import RodarFluxo from 'dashboard/routes/dashboard/captain/automacoes/RodarFluxo.vue';
```

- trocar

```js
// "⋯" ao lado do nome: hoje só tem o "Não é lead"
const menuAberto = ref(false);
```

por

```js
// "⋯" ao lado do nome: "Não é lead" e, para admin, "Rodar fluxo…"
const menuAberto = ref(false);
// "Rodar fluxo…" (Automações em fluxo, B3): só admin (isAdmin acima) — a API dos fluxos é admin-only
const rodandoFluxo = ref(false);
const abrirRodarFluxo = () => {
  menuAberto.value = false;
  rodandoFluxo.value = true;
};
```

- no menu ⋯, logo depois do `</button>` do `data-testid="lead-discard"`:

```vue
                <button
                  v-if="isAdmin"
                  type="button"
                  data-testid="lead-rodar-fluxo"
                  class="flex items-center gap-2"
                  :class="LINHA"
                  @click="abrirRodarFluxo"
                >
                  <span class="i-lucide-workflow size-4 shrink-0" />
                  {{ $t('CAPTAIN_RAMON.FLUXOS.RODAR.ITEM') }}
                </button>
```

- logo antes de `        <!-- reunião nova com outra aberta: confirma antes de marcar -->`:

```vue
        <RodarFluxo
          v-if="rodandoFluxo"
          :alvo="{ lead_id: lead.id }"
          @fechar="rodandoFluxo = false"
        />

```

(c) `MoreActions.vue` (upstream; a `id` da conversa no front é o `display_id`, que é o que `POST …/rodar` espera em `conversation_id`):

- depois de `import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';`:

```js
// FORK(ramon): "Rodar fluxo…" (Automações em fluxo, B3) — só admin, como a API
import { useAdmin } from 'dashboard/composables/useAdmin';
import RodarFluxo from 'dashboard/routes/dashboard/captain/automacoes/RodarFluxo.vue';
```

- depois de `const [showActionsDropdown, toggleDropdown] = useToggle(false);`:

```js
const [showRodarFluxo, toggleRodarFluxo] = useToggle(false); // FORK(ramon)
const { isAdmin } = useAdmin(); // FORK(ramon)
```

- em `actionMenuItems`, logo antes de `  return items;`:

```js
  // FORK(ramon): roda um fluxo de gatilho manual nesta conversa (só admin)
  if (isAdmin.value) {
    items.push({
      icon: 'i-lucide-workflow',
      label: t('CAPTAIN_RAMON.FLUXOS.RODAR.ITEM'),
      action: 'rodar_fluxo',
      value: 'rodar_fluxo',
    });
  }

```

- em `handleActionClick`, trocar

```js
  } else if (action === 'send_transcript') {
    toggleEmailModal();
  }
```

por

```js
  } else if (action === 'send_transcript') {
    toggleEmailModal();
  } else if (action === 'rodar_fluxo') {
    toggleRodarFluxo(true); // FORK(ramon)
  }
```

- no template, logo depois do `<EmailTranscriptModal … />` (antes do `</div>` final):

```vue
    <!-- FORK(ramon): Rodar fluxo… (B3) -->
    <RodarFluxo
      v-if="showRodarFluxo"
      :alvo="{ conversation_id: currentChat.id }"
      @fechar="toggleRodarFluxo(false)"
    />
```

- [ ] **Step 4: Run to verify they pass**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadPanelBody.spec.js app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/LeadConversationPanel.spec.js app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/LeadDrawer.spec.js --config vitest.local.config.ts
./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes/RodarFluxo.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/RodarFluxo.spec.js app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadPanelBody.vue app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadPanelBody.spec.js app/javascript/dashboard/components/widgets/conversation/MoreActions.vue
```
Expected: automacoes 13 arquivos / 152 testes; LeadPanelBody 88; os 2 specs vizinhos que montam o painel verdes; eslint sem `error`. (`MoreActions.vue` não tem spec no upstream — o caminho dele é o mesmo modal testado acima; conferir no smoke.)

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/RodarFluxo.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/RodarFluxo.spec.js app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadPanelBody.vue app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadPanelBody.spec.js app/javascript/dashboard/components/widgets/conversation/MoreActions.vue
git commit -m "feat(fluxos): Rodar fluxo… no menu do lead e da conversa (admin)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 8: "Configurações → Automação" sai do menu e a rota antiga redireciona

**Files:**
- Modify: `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:807-812` (item `'Settings Automation'`)
- Modify: `app/javascript/dashboard/routes/dashboard/settings/automation/automation.routes.js` (arquivo inteiro)
- Test: `app/javascript/dashboard/routes/dashboard/settings/automation/specs/automation.routes.spec.js` (novo)

**Interfaces:**
- Consumes: rota `captain_automacoes_index` (`captain.routes.js:147-152`, `metaAdmin`).
- Produces: `/app/accounts/:accountId/settings/automation` e `…/settings/automation/list` → `{ name: 'captain_automacoes_index', params: { accountId } }`. A rota nomeada `automation_list` deixa de existir (o único uso era o `Sidebar.vue:811`). `Index.vue`, `AutomationRuleForm.vue` etc. ficam no código, sem rota (merge com o upstream).

- [ ] **Step 1: Write the failing test** — `app/javascript/dashboard/routes/dashboard/settings/automation/specs/automation.routes.spec.js`:

```js
import automation from '../automation.routes';

describe('Configurações → Automação (FORK ramon)', () => {
  it('o link antigo cai em Inteligência → Automações', () => {
    expect(automation.routes.map(r => r.path)).toEqual([
      '/app/accounts/:accountId/settings/automation',
      '/app/accounts/:accountId/settings/automation/list',
    ]);
    automation.routes.forEach(r =>
      expect(r.redirect({ params: { accountId: '7' } })).toEqual({
        name: 'captain_automacoes_index',
        params: { accountId: '7' },
      })
    );
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/settings/automation/specs --config vitest.local.config.ts`
Expected: FAIL — hoje há 1 rota com `children` e sem `redirect` de topo.

- [ ] **Step 3: Implementation**

`automation.routes.js` — substituir o arquivo inteiro por:

```js
import { frontendURL } from '../../../../helper/URLHelper';

// FORK(ramon): a Automação nativa saiu de Configurações (B3 das Automações em
// fluxo, decisão do Eduardo 06/10). O motor nativo segue no código, sem tela; o
// link antigo cai em Inteligência → Automações. Index.vue e o formulário ficam
// no código (sem rota) para o merge com o upstream.
const paraAutomacoes = to => ({
  name: 'captain_automacoes_index',
  params: { accountId: to.params.accountId },
});

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/automation'),
      redirect: paraAutomacoes,
    },
    {
      path: frontendURL('accounts/:accountId/settings/automation/list'),
      redirect: paraAutomacoes,
    },
  ],
};
```

`Sidebar.vue` — trocar o item

```js
        {
          name: 'Settings Automation',
          label: t('SIDEBAR.AUTOMATION'),
          icon: 'i-lucide-repeat',
          to: accountScopedRoute('automation_list'),
        },
```

por

```js
        // FORK(ramon): a "Automação" nativa saiu daqui — as automações vivem em
        // Inteligência → Automações (fluxos, fatia B3); o link antigo redireciona.
```

(`SIDEBAR.AUTOMATION` fica no `settings.json` — arquivo do upstream, sem uso não quebra nada.)

- [ ] **Step 4: Run to verify it passes**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/settings/automation/specs --config vitest.local.config.ts` → PASS (1 teste).
`./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/settings/automation app/javascript/dashboard/components-next/sidebar/Sidebar.vue` → sem `error`.
`grep -rn "automation_list" app/javascript` → vazio.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/components-next/sidebar/Sidebar.vue app/javascript/dashboard/routes/dashboard/settings/automation/automation.routes.js app/javascript/dashboard/routes/dashboard/settings/automation/specs/automation.routes.spec.js
git commit -m "feat(configuracoes): Automação nativa sai do menu e cai em Inteligência → Automações" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 9: Story — aba "Do sistema" e desenhos do sistema abertos (para os prints)

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/Automacoes.story.vue`

**Interfaces:**
- Consumes: os 29 JSON (via `import.meta.glob`, 7 níveis acima da pasta `automacoes/` = raiz do repo); `Lista.vue` (Task 5); `Editor.vue` (Task 6).
- Produces: variantes `DoSistema` (lista na aba Do sistema, em grupos), `SistemaLembretes` (desenho `lembretes_reuniao`) e `SistemaAvisos` (desenho `avisos_painel` com o selo "fala com o cliente"). **Quem tira os prints é o controlador** (o harness Vite + Chrome headless vive no `tmp/` não versionado de outro worktree); esta task só acrescenta as variantes.

- [ ] **Step 1: Dados do sistema** — logo depois do fechamento de `const FLUXO = { … };` e antes de `const API = {`, inserir:

```js
// B3: a aba "Do sistema" e os desenhos abertos vêm dos JSON de verdade
// (db/seeds/ramon/fluxos/sistema); "Hoje" FICTÍCIO, sem contador = "—".
const DESENHOS_SISTEMA = import.meta.glob(
  '../../../../../../../db/seeds/ramon/fluxos/sistema/*.json',
  { eager: true, import: 'default' }
);
const HOJE_SISTEMA = {
  cadencia: 6,
  sla_primeira_resposta: 9,
  lembretes_reuniao: 2,
  eventos_advbox: 4,
  lead_ganho: 1,
  docs_completos: 2,
  contrato_limpo: 1,
  copiloto_noturno: 12,
  chegada_cliente: 0,
  publicar_pecas: 1,
};
const SISTEMA = Object.entries(DESENHOS_SISTEMA).map(([arquivo, d], i) => {
  const chave = arquivo.split('/').pop().replace('.json', '');
  const gatilho = d.desenho.nos.find(n => n.tipo === 'gatilho').config;
  return {
    ...FLUXO,
    id: 101 + i,
    nome: d.nome,
    descricao: d.descricao,
    gatilho_tipo: gatilho.tipo,
    gatilho_rotulo: gatilho.rotulo ?? null,
    grupo: d.grupo,
    alcance: d.alcance ?? null,
    ativo: false,
    limite_dia: d.limite_dia ?? null,
    origem: 'sistema',
    sistema_chave: chave,
    versao: null,
    hoje: HOJE_SISTEMA[chave] ?? null,
    esperando: 0,
    falharam_24h: 0,
    ultima_em: null,
    rascunho: d.desenho,
    versoes: [],
  };
});
```

- [ ] **Step 2: API fictícia responde por eles** — no `API`, (a) no fim do array `ramon_fluxos.payload`, depois do item `id: 4` ("Rodar na mão: pedir documentos"), acrescentar `...SISTEMA,`; (b) logo depois de `'ramon_fluxos/1': FLUXO,` acrescentar:

```js
  ...Object.fromEntries(SISTEMA.map(f => [`ramon_fluxos/${f.id}`, f])),
```

(`ramon_fluxos/<id>/execucoes` cai no `{ payload: [] }` padrão do `responder`.)

- [ ] **Step 3: Variantes** — no fim do `<script setup>`, depois de `const paletaAoFim = …;`:

```js
// B3: a lista abre na aba "Do sistema" (como na volta do desenho do sistema)
const abaSistema = () => {
  rota.query = { aba: 'sistema' };
};
// B3: o editor abre um desenho do sistema (só leitura + "Como roda hoje")
const abreSistema = chave => () => {
  rota.params.fluxoId = String(SISTEMA.find(f => f.sistema_chave === chave).id);
};
```

e no template, antes de `<Variant title="Execucao">`:

```vue
    <Variant title="DoSistema" :init-state="abaSistema">
      <div class="h-screen"><Lista /></div>
    </Variant>
    <Variant
      title="SistemaLembretes"
      :init-state="abreSistema('lembretes_reuniao')"
    >
      <div class="h-screen"><Editor /></div>
    </Variant>
    <Variant title="SistemaAvisos" :init-state="abreSistema('avisos_painel')">
      <div class="h-screen"><Editor /></div>
    </Variant>
```

- [ ] **Step 4: Run** — `./node_modules/.bin/eslint --fix app/javascript/dashboard/routes/dashboard/captain/automacoes/Automacoes.story.vue` e depois sem `--fix` → sem `error`. Checklist para o controlador conferir nos prints (claro e escuro): aba "Do sistema 29" ativa em azul; aviso azul translúcido; 5 grupos na ordem (Leads e conversas · Contrato e documentos · Painel do Cliente · Rotinas e relatórios · Instagram), cabeçalho cinza pequeno; linhas com nome + "No código: …"; gatilho com ícone azul e, onde há rótulo, o evento real ("Recepção avisa a chegada do cliente", "A cada minuto: …"); "Hoje" `6 / 15` na cadência e `—` sem contador; selo âmbar "fala com o cliente" em Avisos do Painel e "publica" em Publicar peças; selo azul "roda no código"; nenhuma chave liga/desliga. `SistemaLembretes`: 11 passos de cima para baixo, selo "Fluxo do sistema · só leitura", sem Testar/Publicar/Versões/Excluir, painel "Como roda hoje". `SistemaAvisos`: selo âmbar "fala com o cliente" na barra.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/Automacoes.story.vue
git commit -m "test(fluxos): story da aba Do sistema para os prints de aprovação" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 10: Verificação final + notas na spec (§14 Notas da B3) + texto do PR

**Files:**
- Modify: `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (acrescentar §14 no fim)

- [ ] **Step 1: Front inteiro**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs app/javascript/dashboard/routes/dashboard/settings/automation/specs app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadPanelBody.spec.js --config vitest.local.config.ts
./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes app/javascript/dashboard/routes/dashboard/settings/automation app/javascript/dashboard/components-next/sidebar/Sidebar.vue app/javascript/dashboard/components/widgets/conversation/MoreActions.vue app/javascript/dashboard/routes/dashboard/ramon/components/lead
```
Expected: 15 arquivos / 241 testes verdes (152 + 1 + 88); eslint sem `error`. `git status --short` não pode listar `vitest.local.config.ts`.

- [ ] **Step 2: Varredura de regras**

```bash
git diff 9cdd5c6 --stat -- app/models/lead.rb app/services/ramon/advbox_event_processor.rb app/finders/conversation_finder.rb enterprise db/migrate db/schema.rb
grep -rn "automation_list" app/javascript
grep -rn "converter_regras" lib app
ls db/seeds/ramon/fluxos/sistema | wc -l
```
Expected: os três primeiros vazios; `29`.

- [ ] **Step 3: Notas da B3 na spec** — acrescentar ao fim de `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md`:

```markdown
## 14. Notas da B3 (06/10/2026)

- **Conversor das regras nativas descartado** (decisão do Eduardo, 06/10): produção tem 0 `AutomationRule`, então o rake `ramon:fluxos:converter_regras` do §8 não existe e não há `origem: convertido` em uso. "Configurações → Automação" saiu do menu e o link antigo (`/settings/automation`, `/settings/automation/list`) cai em Inteligência → Automações; o motor nativo do Chatwoot segue no código, sem tela (o `AutomationRules::ActionService` continua servindo o passo `acao_chatwoot`).
- **Fluxos do sistema = as 29 automações do código** (não só as 6 do §8), em 5 grupos: Leads e conversas · Contrato e documentos · Painel do Cliente · Rotinas e relatórios · Instagram. São JSON em `db/seeds/ramon/fluxos/sistema/<chave>.json` (`{nome, grupo, alcance?, descricao, limite_dia?, desenho}`); `Ramon::Fluxos::Sistema.sincronizar` cria/atualiza 1 `Fluxo` `origem: sistema` por conta quando a lista abre (sob lock da conta; nada mudou = 1 SELECT). `grupo`, `alcance` e o rótulo do gatilho saem do JSON (`Sistema.extras`), sem coluna nova.
- Nunca rodam: `Fluxo.executaveis` exclui a origem, `Disparo#iniciar` recusa (evento, relógio, manual e ensaio), a API devolve 403 em editar/publicar/ensaiar/rodar e o desenho esconde "Testar com um lead…". O ensaio fica bloqueado até cada um migrar (B4+).
- Convenção dos desenhos: 1ª linha da `descricao` = onde vive no código; o resto = o que o desenho não expressa. Onde o gatilho real não existe nos fluxos, o desenho usa `manual` com o rótulo do evento real (a lista mostra o rótulo); ações sem passo (Drive, Notion, e-mail, carimbos de coluna) usam o tipo mais próximo com rótulo claro. `mover_etapa` vem sem `etapa_id` (a etapa é do funil de cada conta). Os 5 lembretes de reunião são um ciclo só.
- Selo nas 2 que saem para fora sem uma pessoa no meio: **Avisos do Painel do Cliente** = "fala com o cliente" (desligado até o Eduardo aprovar os textos, `PORTAL_AVISOS=on`); **Publicar peças no Instagram** = "publica".
- "Hoje" na aba Do sistema só com fonte barata (10 das 29): retomadas preparadas, conversas novas em caixa de lead, reuniões marcadas/remarcadas, eventos do ADVBOX processados, leads ganhos, documentos completos, contratos limpos, sugestões do copiloto, chegadas escaladas, peças publicadas — tudo no dia de São Paulo; o resto "—".
- **Rodar fluxo…** (§7) entrou na B3: menu ⋯ do painel do lead (`lead_id`) e do cabeçalho da conversa (`conversation_id`), só admin (a API de fluxos é admin-only); lista os fluxos publicados e ligados com gatilho `manual`, roda pelo `POST …/rodar` da B1 e avisa com link para a execução; sem fluxo, aponta para Automações.
- **B4**: o fluxo em sombra é um fluxo próprio (origem `usuario`), porque o motor recusa `origem: sistema`; quando assumir, apagar o JSON **e** a linha do sistema (a sincronização não apaga linha cujo JSON sumiu).
```

- [ ] **Step 4: Texto do PR (não abrir — gate do Eduardo)** — deixar no relatório final:

```markdown
Automações em fluxo — B3: Inteligência → Automações ganha a aba "Do sistema", com as 29 automações que hoje rodam no código do hub, em 5 grupos (Leads e conversas, Contrato e documentos, Painel do Cliente, Rotinas e relatórios, Instagram), desenhadas como fluxos só para leitura: dá para abrir cada uma, ver o caminho e ler, ao lado, onde ela vive no código e o que o desenho ainda não consegue mostrar. As duas que saem para fora sem uma pessoa no meio levam selo: "fala com o cliente" (Avisos do Painel do Cliente, desligado até a aprovação dos textos) e "publica" (Instagram). Nada disso roda pelo motor — continua tudo pelo código, e cada uma vai virar fluxo editável depois (B4, uma a uma, em modo ensaio). O painel do lead e o cabeçalho da conversa ganham "Rodar fluxo…" no menu ⋯ (administradores). "Configurações → Automação" saiu do menu: quem tiver o link antigo cai em Automações.

## Closes
- Spec `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` §7 (abas da lista, Rodar fluxo…), §8 (fluxos do sistema) e §10 (fatia B3); o conversor das regras nativas foi descartado (0 regras em produção) — ver §14.

## How to test
1. Inteligência → Automações → aba "Do sistema": 29 linhas em 5 grupos, cada uma com "No código: …", "Hoje" (ou "—") e o selo "roda no código"; "Avisos do Painel do Cliente" com o selo "fala com o cliente" e "Publicar peças no Instagram" com "publica"; nenhuma chave liga/desliga; os 4 números de "Meus fluxos" não mudam.
2. Abra "Lembretes de reunião": quadro só leitura, sem Testar/Publicar/Versões/Excluir, painel "Como roda hoje" à direita; "Voltar" volta para a aba "Do sistema". Abra "Avisos do Painel do Cliente": selo "fala com o cliente" na barra.
3. Como administrador, numa conversa com lead: ⋯ do painel do lead → "Rodar fluxo…" lista os fluxos de "Rodar na mão" publicados e ligados; escolha um → aviso com "Ver execução". O mesmo pelo ⋯ do cabeçalho da conversa. Sem nenhum fluxo assim, o modal aponta para Automações. Como agente, o item não aparece.
4. Configurações: o item "Automação" sumiu. Abra `/app/accounts/<id>/settings/automation/list`: cai em Automações.

## What changed
- `Ramon::Fluxos::Sistema` (novo) + 29 desenhos em `db/seeds/ramon/fluxos/sistema/*.json`; `GET ramon_fluxos` sincroniza os do sistema e traz Hoje, grupo, selo e o rótulo do gatilho; o resumo conta só os seus fluxos.
- `Disparo#iniciar` recusa fluxo do sistema; `POST …/ensaio` de fluxo do sistema → 403.
- Front: abas e grupos na lista (`?aba=sistema`), painel "Como roda hoje" e selo no desenho, modal novo "Rodar fluxo…" no ⋯ do painel do lead e do cabeçalho da conversa, campo "Regra do ADVBOX" nas condições/escolha; item "Automação" fora de Configurações e rota antiga redirecionando.
- Sem migração, sem env nova.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv
```

- [ ] **Step 5: Smoke em bloco (para o Eduardo, depois do deploy)** — anotar no relatório: (1) abrir a lista uma vez (cria os 29 na conta) e conferir a aba Do sistema em grupos, com os 2 selos; (2) abrir os desenhos e ler o "Como roda hoje" de cada um — é aqui que o Eduardo aprova se o desenho bate com a operação; (3) como admin, no ⋯ do painel do lead e no ⋯ do cabeçalho da conversa: "Rodar fluxo…" lista os fluxos de Rodar na mão publicados e ligados; rodar um num lead de teste → toast "Ver execução" abre a execução; (4) como agente: o item não aparece; (5) Configurações sem "Automação" + link antigo; (6) "Meus fluxos" e seus números iguais.

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md
git commit -m "docs(fluxos): notas da B3 na spec" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

Sem push.

---

## Divergências registradas (spec × este plano)

| # | Onde | Divergência | Motivo |
|---|---|---|---|
| 1 | Spec §8 / §2 D6 | Sem rake `ramon:fluxos:converter_regras`, sem `origem: convertido` | Decisão do Eduardo 06/10: 0 `AutomationRule` em produção |
| 2 | Spec §8 | 29 desenhos (não 6), em 5 grupos | Decisão do Eduardo 06/10: mostrar tudo que o hub faz sozinho |
| 3 | Spec §8 | Desenhos = JSON em `db/seeds` **sincronizados em linhas por conta**; `grupo`/`alcance`/rótulo do gatilho vêm do JSON em memória | Editor, policy, `show` e `executaveis` já funcionam por linha; sem migração |
| 4 | Spec §7 | Aba Do sistema sem chave liga/desliga, sem "Esperando"/"Última"; 4 números só em Meus fluxos | Nada disso existe para o que roda no código |
| 5 | Spec §4.1 | Desenhos com gatilho `manual` + rótulo do evento real onde o gatilho não existe (crons de hora/minuto, Painel, chegada, @claude, ata, gravação do lead) | Honestidade: o rótulo diz o evento; a lista mostra o rótulo; nunca rodam |
| 6 | Spec §8 | Lembretes de reunião = 1 ciclo com rótulo "24h · 8h · 1h · 30 min · 5 min" | Decisão do Eduardo; a B4 precisa de "esperar até X antes de {quando}" |
| 7 | Spec §8 | `mover_etapa` sem `etapa_id` nos desenhos (único erro aceito) | A etapa é do funil de cada conta |
| 8 | Spec §6 | `ensaio` também recusado para fluxo do sistema | "Nunca executados pelo motor" — ensaio também cria execução |

## Decisões do Eduardo (06/10/2026)

| # | Decisão | Onde no plano |
|---|---|---|
| E1 | Conversor das regras nativas **descartado** (0 regras em produção) | Escopo §1, §14 |
| E2 | "Configurações → Automação" sai do menu; link antigo → Inteligência → Automações; telas antigas no código sem rota | Task 8 |
| E3 | Desenhos do sistema em JSON (`db/seeds`) + 1 linha por conta sincronizada ao abrir a lista | Tasks 1-4 |
| E4 | A aba Do sistema mostra **as 29** automações do código, em 5 grupos (Leads e conversas · Contrato e documentos · Painel do Cliente · Rotinas e relatórios · Instagram); onde os tipos não desenham, gatilho → 1 passo descritivo | Tasks 1-2, 5 |
| E5 | Selo nas 2 que saem sem pessoa no meio: Avisos do Painel do Cliente = "fala com o cliente" (desligado até o Eduardo aprovar os textos, `PORTAL_AVISOS`); Publicar peças no Instagram = "publica" | Tasks 2, 5, 6 |
| E6 | Lembretes de reunião = 1 ciclo "24h · 8h · 1h · 30 min · 5 min" | Task 1 |
| E7 | "Hoje" só com fonte barata (10 das 29); o resto "—" | Task 3 |
| E8 | Ensaio bloqueado nos fluxos do sistema até cada um migrar (B4+): 403, guarda no motor, "Testar com um lead…" escondido | Tasks 4, 6 |
| E9 | "Rodar fluxo…" no ⋯ do painel do lead e da conversa, só admin (a API é admin-only), toast com link para a execução, estado vazio com link para Automações | Task 7 |
