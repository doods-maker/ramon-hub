# Automações em fluxo (motor + quadro tipo n8n) — design

**Data:** 05/10/2026 · **Status:** aprovado em conversa com o Eduardo (partes 1–5), aguardando revisão desta spec
**Mockup aprovado (alvo da tela):** `RAdvogados\comercial\docs\mockups\2026-10-05-inteligencia-fluxos\fluxos.html` (+ prints claro/escuro na mesma pasta)
**Subprojeto irmão:** A — Inteligência completa (tela a tela), documento próprio.

---

## 1. Objetivo

Dar ao hub **um lugar só** onde se vê, monta e acompanha tudo que ele faz sozinho: um
quadro de **fluxos** (gatilho → condições → esperas → ações) com cara de n8n, que **roda
de verdade** dentro do hub, cobre eventos de **conversa e de lead** e as ações da banca
(funil, Esteira, IA, ADVBOX, avisos).

Hoje: a Automação nativa do Chatwoot é linear (evento → condições → ações, sem espera, sem
ramo, sem evento de lead) e todas as automações da banca (cadência, SLA, lembretes, regras
do Flowter, pós-ganho, resumo) estão escritas no código, invisíveis e não editáveis.

**Sucesso =** o Eduardo monta um fluxo como "Contrato assinado → boas-vindas (rascunho) →
tarefa → espera 2 dias → se faltam documentos → rascunho IA + push", testa com um lead
real sem executar nada, publica, e depois abre qualquer execução e vê o caminho aceso.

## 2. Decisões (todas do Eduardo, 05/10/2026)

| # | Decisão |
|---|---|
| D1 | Motor de fluxos **próprio** dentro do hub (não instalar o n8n; não só "pele" nas regras nativas). |
| D2 | Quadro livre (Vue Flow) com as travas de esteira do Flowter: **1 gatilho por fluxo**, espera conta **do passo anterior**, ramos só **sim/não**, sem laços. |
| D3 | Mensagem ao cliente **sempre rascunho** (nota privada "RASCUNHO…"); quem envia é uma pessoa. |
| D4 | Só **administradores** montam/editam; equipe vê o efeito (balão de evento na conversa, atividade do lead). |
| D5 | Automações ficam **dentro da Inteligência** no menu. |
| D6 | Regras nativas do Chatwoot são **absorvidas** (convertidas em fluxos; a tela antiga sai do menu). |
| D7 | Automações de hoje aparecem como **"Do sistema" (só leitura)** e migram **uma a uma**, em modo sombra. |
| D8 | Extras obrigatórios: **ensaio**, **versão congelada**, **falhou→tenta 3×→avisa**, **limite por dia**, **gatilho manual**, **variáveis entre passos**, **modelos prontos**. |
| D9 | Fluxo corre **de cima para baixo** no quadro (horizontal ficou ilegível na tela real — visto no mockup). |
| D10 | A e B andam **em paralelo**. |

## 3. Vocabulário (entra no `CONTEXT.md`, § Inteligência)

- **Fluxo** — uma automação desenhada no quadro: 1 gatilho + passos ligados por setas.
- **Passo** — uma caixinha do fluxo (condição, ação ou controle).
- **Versão (de fluxo)** — foto publicada do desenho; execuções rodam na versão em que começaram.
- **Execução de fluxo** — uma passada de um fluxo por um lead/conversa, com trilha.
  _Não confundir com **Execução** (registro de uma Tool da IA), que já existe no glossário._
- **Trilha** — a lista de passos por onde uma execução passou, com entrada/saída/erro.
- **Ensaio** — execução de mentira num alvo real: avalia condições, descreve as ações, não executa nada.
- **Modo sombra** — fluxo que roda como ensaio nos eventos reais, para comparar com o código antes de assumir.
- **Fluxo do sistema** — desenho só-leitura de uma automação que ainda roda pelo código.

## 4. Peças (catálogo)

Cada nó do desenho: `{ id, tipo, config, posicao: {x, y} }`. Setas: `{ de, saida, para }`,
`saida ∈ {s, sim, nao}`.

### 4.1 Gatilhos (exatamente 1 por fluxo)

| tipo | quando | de onde vem (ponto no código) | alvo |
|---|---|---|---|
| `conversa_criada` | nova conversa | ouvinte novo `RamonFluxoListener` (`conversation_created`) | conversa |
| `mensagem_recebida` | mensagem incoming | `message_created` (incoming, não-privada) | conversa |
| `conversa_resolvida` / `conversa_reaberta` | status | `conversation_resolved` / `conversation_opened` | conversa |
| `conversa_atribuida` | atribuição mudou | `assignee_changed` | conversa |
| `lead_criado` | lead novo | `lead_created` | lead |
| `lead_mudou_etapa` | etapa mudou (filtro opcional de→para) | `lead_updated` c/ mudança de `lead_stage_id` | lead |
| `lead_ganho` / `lead_perdido` | entrou em etapa `is_won` / `is_lost` | `lead_updated` | lead |
| `lead_parado` | parado há N dias (1×/dia, hora configurável, padrão 11:00 SP) | relógio; reaproveita `Ramon::Cadencia.parado?` | lead |
| `reuniao_marcada` / `reuniao_cancelada` | reunião | 1 linha em `Ramon::ReuniaoAgendamento` (cobre Cal.com e painel) | lead |
| `evento_advbox` | regra do Flowter (filtro por chave: contrato_fechado, indeferimento…) | 1 linha em `Ramon::AdvboxEventProcessor` | lead |
| `contrato_assinado` / `contrato_recusado` | ZapSign | 1 linha em `ZapsignLeadStatusJob` | lead |
| `documento_recebido` | anexo casado com o checklist | 1 linha no fim do `DocMatchJob` | lead |
| `relogio` | todo dia HH:MM sobre um grupo de leads (filtro: etapa/tese/responsável) | relógio | cada lead do grupo |
| `manual` | botão "Rodar fluxo" no lead/conversa | API `POST …/fluxos/:id/rodar` | o lead/conversa |

Conversa ↔ lead: quando o alvo é conversa e existe lead ligado (`lead.conversation_id`), o
contexto carrega os dois; idem ao contrário.

### 4.2 Condição

- `se` — lista de condições com **E/OU** sobre o contexto (campo, operador, valor). Operadores:
  `igual, diferente, contem, nao_contem, maior, menor, existe, vazio, em_horario_comercial`.
  Saídas `sim` e `nao` (uma delas pode ficar sem seta = termina).
- `perguntar_ia` — pergunta de sim/não ao LLM (`Ramon::LlmClient`) com a conversa/lead no
  contexto; resposta normalizada para `sim|nao`; o texto da justificativa vira `{resposta_ia}`.

### 4.3 Ações

| tipo | faz | reaproveita |
|---|---|---|
| `rascunho_texto` | nota privada `RASCUNHO (revisar antes de enviar): …` com texto fixo + variáveis | prefixo de `Ramon::RascunhoCarimbo::PREFIXO` (o carimbo de desfecho continua funcionando) |
| `rascunho_ia` | idem, texto escrito pela IA a partir de uma instrução (+ assistente/skill opcional) | `Ramon::LlmClient`; skill via `Captain::Assistant::AgentRunnerService` (enterprise) |
| `acao_chatwoot` | qualquer ação nativa (etiqueta, atribuir, time, status, prioridade, e-mail p/ time, anexo, transcript, SLA…) | `AutomationRules::ActionService` com regra em memória — **mesma execução das regras nativas** |
| `nota_privada` | nota interna | — |
| `mover_etapa` | muda etapa do lead | update do lead (dispara sync etapa↔etiqueta de sempre) |
| `criar_tarefa` | tarefa na Esteira (`LeadTask`) c/ responsável e prazo relativo | — |
| `trocar_responsavel` / `preencher_campo` | SDR/Closer; `custom_attributes` (merge por chave após reload) | — |
| `registrar_atividade` | linha na atividade do lead | `LeadActivity` |
| `avisar_sino` / `avisar_push` | sino do hub / push ntfy | `Notification` tipo `ramon_*` / `Ramon::NtfyPushJob` |
| `rodar_skill` | roda uma skill de um assistente; resultado vira nota privada e `{resposta_ia}` | `AgentRunnerService` (enterprise) |
| `advbox` | criar tarefa ou movimentação **fixa** (IDs escolhidos na tela a partir de `advbox_configuracoes`) | `Ramon::AdvboxMcpService` |
| `webhook` | POST JSON do contexto para uma URL | — ; **só como último passo** (regra do Flowter) |

### 4.4 Controle

- `esperar` — X min/h/dias **ou** "até o próximo horário comercial"; conta do passo anterior.
- `parar` — encerra a execução.

### 4.5 Variáveis

Contexto = `{ contato, lead, conversa, gatilho, vars }`. No texto, `{chave}` com apelidos
amigáveis (`{nome}`, `{tese}`, `{etapa}`, `{responsavel}`, `{documentos_faltantes}`, …) +
o que cada passo devolve (`{resposta_ia}`, `{prazo_advbox}`, …). Substituição simples
(sem Liquid); chave desconhecida fica literal e o **ensaio aponta**.

## 5. Dados (3 tabelas, migração à mão na VPS)

**`ramon_fluxos`** — `account_id`, `nome`, `descricao`, `gatilho_tipo` (indexado), `ativo`,
`limite_dia` (null = sem limite), `origem` (`usuario|convertido|sistema`), `sistema_chave`
(ex. `lembretes_reuniao`), `modo` (`normal|sombra`), `rascunho` jsonb (desenho em edição),
`versao_publicada_id`, `ultimo_disparo_em`, `created_by_id`, timestamps.

**`ramon_fluxo_versoes`** — `fluxo_id`, `numero` (único por fluxo), `grafo` jsonb,
`publicado_por_id`, `created_at`. Imutável.

**`ramon_fluxo_execucoes`** — `account_id`, `fluxo_id`, `versao_id`, `alvo_type/alvo_id`
(Lead|Conversation), `status` (`rodando|esperando|concluida|falhou|cancelada|ensaio`),
`no_atual`, `retomar_em`, `tentativas`, `contexto` jsonb, `trilha` jsonb (array
`{no, inicio, fim, resultado, saida, erro}`), `profundidade`, `erro`, timestamps.
- Índice **único parcial** `(fluxo_id, alvo_type, alvo_id) WHERE status IN ('rodando','esperando')`
  → "não roda 2× ao mesmo tempo para o mesmo alvo" garantido pelo banco.
- Índice parcial `(retomar_em) WHERE status = 'esperando'`.

**Publicar** valida o rascunho: 1 gatilho; sem ciclo; todo passo alcançável; `webhook` sem
saída; `se` com ≥1 saída; config obrigatória preenchida. Erro → aponta o passo no quadro.

## 6. Motor

- **Disparo** (`Ramon::Fluxos::Disparo.call(gatilho, alvo, dados)`): acha fluxos ativos da
  conta com aquele `gatilho_tipo` (origem ≠ sistema), aplica o filtro do gatilho, checa
  **limite do dia** (execuções não-ensaio de hoje, fuso SP) e cria a execução (o índice
  único barra duplicata — conflito = ignora). Enfileira `Ramon::FluxoAvancarJob(id)`.
  Fluxo em `modo: sombra` cria execução com `status: ensaio`.
- **Avançar** (`Ramon::Fluxos::Executor`): sob `with_lock`, segue as setas a partir de
  `no_atual`; cada tipo de passo é uma classe pequena `Ramon::Fluxos::Passos::<Tipo>#call(ctx)`
  que devolve `{saida:, vars:, resumo:}`; grava a trilha a cada passo; guarda de 50 passos.
  - `esperar` → `status: esperando`, `retomar_em`, solta.
  - **ao retomar**: se "cancelar se sair da etapa" (padrão ligado em fluxos de lead) e a
    etapa mudou desde o início → `cancelada`.
  - **erro numa ação** → `tentativas += 1`, `retomar_em` = +1 / +5 / +15 min; na 3ª →
    `falhou` + sino para admins (`ramon_fluxo_falhou`) + push.
- **Relógio** (`Ramon::FluxoRelogioJob`, cron a cada minuto): retoma execuções vencidas;
  dispara `relogio` e `lead_parado` do dia (marca `ultimo_disparo_em`). Nada fica preso em
  memória → deploy/reinício não perde quem esperava (sem `perform_in` longo).
- **Cadeia entre fluxos**: ação de um fluxo pode disparar outro (ex.: mover etapa → fluxo de
  etapa). O contexto leva `profundidade`; > 3 não dispara; um fluxo **nunca** redispara a si
  mesmo para o mesmo alvo.
- **Ensaio** (`POST …/fluxos/:id/ensaio {lead_id|conversation_id, usar: rascunho|publicada}`):
  síncrono; condições de verdade (inclusive `perguntar_ia`), esperas puladas, ações só
  **descrevem** o que fariam; devolve a trilha (persistida como `ensaio`, fora de limite e de
  unicidade).
- **Visível para a equipe**: cada ação executada registra balão via `Ramon::EventoInline`
  ("⚙ Fluxo Pós-contrato: moveu para Documentação") e/ou atividade do lead.
- Sidekiq `strict_args`: jobs só recebem IDs.
- Código em `app/` (namespace `Ramon::Fluxos`), **fora de `enterprise/`**, para os specs
  rodarem no CI FOSS; os passos que tocam Captain (`rodar_skill`) ficam atrás de
  `ChatwootApp.enterprise?` e os specs deles com o guard de sempre.

## 7. Tela (alvo = mockup aprovado)

- **Rotas** (área Captain, antes do catch-all `:navigationPath`):
  `captain/automacoes` (lista), `captain/automacoes/:id` (editor),
  `captain/automacoes/:id/execucoes/:execId` (execução/ensaio).
- **Menu Inteligência** ganha "Automações". "Configurações → Automação" sai na fatia B3.
- **Lista**: abas *Meus fluxos* / *Do sistema*; 4 números (ligados, execuções hoje,
  esperando, falharam 24h); linha = chave, nome, gatilho, hoje/limite, esperando, última,
  selo (ok / N falhou / desligado). ⚠️ Divergência consciente do mockup: na aba *Do sistema*
  a coluna "Hoje" só aparece onde já existe fonte barata; senão "—".
- **Editor**: Vue Flow (`@vue-flow/core` + `minimap` + `controls`, MIT — dependência nova,
  única); vertical; "+ Adicionar passo" abre a paleta por grupos; clique no passo abre o
  painel direito com a config e as variáveis clicáveis; selo "sai como rascunho" em toda
  mensagem ao cliente; barra: Ligado + limite, Versões, **Testar com um lead…**, **Publicar vN**.
- **Execução/Ensaio**: mesmo quadro só-leitura, caminho aceso em verde, resto apagado;
  painel com alvo (abrir) e trilha com horários.
- **Novo fluxo**: em branco + modelos (os modelos são JSON versionados em
  `db/seeds/ramon/fluxos/*.json`).
- **Rodar na mão**: menu ⋯ do painel do lead / conversa → "Rodar fluxo…" (lista os fluxos
  com gatilho `manual`).
- Kit visual do hub (`ramon/helpers/ui.js` + components-next), tokens branco/preto + azul,
  fundos coloridos translúcidos; claro e escuro.
- API admin-only (policy como as demais de `ramon_*`).

## 8. Migração

**B3 — regras nativas → fluxos** (rake `ramon:fluxos:converter_regras[account_id]`,
idempotente): evento → gatilho; condições → um `se` (E/OU preservado); ações → `acao_chatwoot`;
**`send_message` → `rascunho_texto`** (única mudança de comportamento; o rake lista quais
regras tinham envio antes de converter, para o Eduardo ver). Regra antiga: `active=false`
(não apaga). Fluxo convertido nasce `origem: convertido`, ligado se a regra estava ativa.

**B3 — fluxos do sistema (só leitura)**: 6 desenhos em `db/seeds/ramon/fluxos/sistema/*.json`
(cadência, SLA 1ª resposta, lembretes de reunião, eventos do ADVBOX, lead ganho, resumo do dia),
`origem: sistema`, nunca executados pelo motor.

**B4+ — migração 1 a 1, modo sombra**, um PR por automação, nesta ordem:
lembretes de reunião → SLA → cadência → lead ganho → eventos do ADVBOX.
1. fluxo equivalente em `modo: sombra` (ensaio nos eventos reais) por alguns dias;
2. comparar trilhas × o que o código fez;
3. bateu + aprovado → env/flag desliga o caminho do código, fluxo vira `normal` e editável.
**Resumo do dia fica no código** (é relatório, não fluxo).

## 9. Testes

- Specs (RSpec, fora de `enterprise/`): cada passo; filtro de cada gatilho; disparo
  (limite, unicidade, profundidade, sombra); esperar/retomar via relógio; cancelar se saiu da
  etapa; tentativas 1/5/15 → falhou + sino; versão congelada (editar/publicar não afeta
  execução em andamento); ensaio não grava nada fora da própria execução; validação de
  publicar; rake de conversão (inclui `send_message` → rascunho). Relógio fixo em dia útil
  10h SP onde tocar ADVBOX.
- Vitest: desenho ↔ JSON (salvar e reabrir idêntico); validação no front espelha a do back.
- **Prova real na VPS** (`rails runner`): fluxo de teste ponta a ponta num lead temporário
  (apagar `LeadActivity` antes do lead), incluindo uma espera curta retomada pelo relógio.
- Prints claro/escuro das 4 telas (harness Vite + Chrome headless) → página de aprovação do pacote.

## 10. Fatias e entrega

| Fatia | Conteúdo | Migração |
|---|---|---|
| **B1** | tabelas, motor, relógio, gatilhos de conversa/lead/manual, ações básicas (rascunho texto, nota, etiqueta via `acao_chatwoot`, mover etapa, tarefa, sino/push, esperar, se), API de execuções | sim (3 tabelas) |
| **B2** | quadro (lista, editor Vue Flow, versões, ensaio, execução acesa, modelos) + menu | não |
| **B2b** | passos de IA (`perguntar_ia`, `rascunho_ia`, `rodar_skill`), `advbox`, `webhook`, gatilhos externos (reunião, ADVBOX, ZapSign, documento), `lead_parado`, `relogio` | não |
| **B3** | conversão das regras nativas + aba "Do sistema" + sai "Configurações → Automação" | não |
| **B4+** | migração 1 a 1 em sombra | não |

Ritmo combinado: merge contínuo com CI verde; aprovação por pacote (prints); 1 deploy por
pacote, Eduardo roda via `!`; migração `db:migrate` à mão no deploy da B1; smoke em bloco.
Motor entra **desligado** (nenhum fluxo ativo) até o smoke.

## 11. Fora de escopo (agora)

Laços/loops e "para cada item"; ramos com mais de 2 saídas; envio automático ao cliente;
edição por não-admin; fluxos entre contas; n8n externo; gatilho por webhook de entrada
genérico (só os 4 externos conhecidos).

## 12. Riscos

- **Tempestade de eventos** (`message_created` em massa): o disparo é barato (consulta por
  `gatilho_tipo` indexado) e o limite do dia segura o resto.
- **Fluxo encadeando fluxo**: profundidade ≤ 3 + não-autodisparo.
- **Mudança de comportamento na conversão** (`send_message` → rascunho): listada antes, aprovada pelo Eduardo.
- **Dependência nova** (Vue Flow): MIT, Vue 3 nativo, isolada nas 2 telas do quadro.
